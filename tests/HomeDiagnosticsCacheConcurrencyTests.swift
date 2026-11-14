// SPDX-License-Identifier: GPL-3.0-only
//
// HomeDiagnosticsCacheConcurrencyTests.swift — concurrency safety
// tests for the shared home-diagnostics cache (Phase H, gap 3).
//
// The cache is @MainActor (it owns @Published state) and does its
// heavy work in a `Task.detached`; the tests prove, with the REAL
// cache and the REAL fixtures (no mock), that:
//   - Concurrent refreshes with identical inputs converge on one
//     deterministic final state (no crash, no stuck `isComputing`).
//   - Concurrent readers sampling the published report while
//     refreshes alternate between two snapshots never observe a
//     torn value: every sample is nil, the first snapshot's whole
//     report, or the second snapshot's whole report.
//   - A refresh triggered from a background task still publishes
//     on the main actor (the values arrive and are readable).
//
// Determinism: no sleeps, no timing assertions. Readers sample a
// bounded number of times with `Task.yield()` between samples;
// refreshes are issued a bounded number of times; the only
// assertions are membership in the set of legitimate whole
// values and the final converged state. A test fails (rather
// than hanging) if a refresh never finishes, via the bounded
// yield budget in `waitForIdle`.
import XCTest

@testable import GestaltX

@MainActor
final class HomeDiagnosticsCacheConcurrencyTests: XCTestCase {

    // MARK: - Fixtures (same fixtures as HomeDiagnosticsCacheTests)

    private func snapshotA() throws -> DocumentSnapshot {
        let document = try CoreModuleFixtures.document(
            extra: [
                "productType": "iPhone18,1",
                "regionCode": "LL",
            ],
            greenTea: false,
            notGreenTea: true,
            wapi: false
        )
        return CoreModuleFixtures.snapshot(document: document)
    }

    private func snapshotB() throws -> DocumentSnapshot {
        CoreModuleFixtures.snapshot(document: try CoreModuleFixtures.document())
    }

    // MARK: - Helpers

    private func waitForIdle(_ cache: HomeDiagnosticsCache) async {
        for _ in 0..<5000 {
            if !cache.isComputing { return }
            await Task.yield()
        }
        XCTFail("HomeDiagnosticsCache did not finish refreshing within the yield budget")
    }

    private func refreshAndWait(
        _ cache: HomeDiagnosticsCache,
        snapshot: DocumentSnapshot?,
        working: GestaltDocument?,
        backups: [BackupRecord]
    ) async {
        cache.refresh(snapshot: snapshot, working: working, backups: backups)
        await waitForIdle(cache)
    }

    // MARK: - Concurrent refreshes converge

    func testConcurrentRefreshesWithSameInputsConverge() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await cache.refresh(
                        snapshot: snapshot, working: snapshot.document, backups: [])
                }
            }
        }
        await waitForIdle(cache)
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")
        XCTAssertTrue(cache.backupVerifications.isEmpty)
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
    }

    // MARK: - Concurrent reads never observe a torn report

    func testConcurrentReadsNeverObserveATornReport() async throws {
        let cache = HomeDiagnosticsCache()
        let first = try snapshotA()
        let second = try snapshotB()

        // Establish the two whole values the cache may publish.
        await refreshAndWait(cache, snapshot: first, working: first.document, backups: [])
        let reportA = try XCTUnwrap(cache.deviceReport)
        await refreshAndWait(cache, snapshot: second, working: second.document, backups: [])
        let reportB = try XCTUnwrap(cache.deviceReport)
        XCTAssertNotEqual(reportA, reportB)

        await withTaskGroup(of: [LilaDeviceReport?].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var seen: [LilaDeviceReport?] = []
                    for _ in 0..<20 {
                        seen.append(await cache.deviceReport)
                        await Task.yield()
                    }
                    return seen
                }
            }
            // Alternate refreshes between the two snapshots while
            // the readers sample. The group body runs on the main
            // actor; each yield lets the refresh tasks apply.
            for _ in 0..<4 {
                cache.refresh(snapshot: first, working: first.document, backups: [])
                await Task.yield()
                cache.refresh(snapshot: second, working: second.document, backups: [])
                await Task.yield()
            }
            for await seen in group {
                for report in seen {
                    XCTAssertTrue(
                        report == nil || report == reportA || report == reportB,
                        "Reader observed a report that is neither snapshot's whole report")
                }
            }
        }
        await waitForIdle(cache)
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
    }

    // MARK: - Refresh from a background task publishes on the main actor

    func testRefreshTriggeredFromBackgroundTaskPublishes() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()

        await Task.detached {
            await cache.refresh(
                snapshot: snapshot, working: snapshot.document, backups: [])
        }.value
        await waitForIdle(cache)
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")
    }
}
