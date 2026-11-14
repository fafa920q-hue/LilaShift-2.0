// SPDX-License-Identifier: GPL-3.0-only
//
// HomeDiagnosticsCacheTests.swift — invalidation tests for the
// shared home-diagnostics cache (Phase H, gap 2).
//
// These tests drive the REAL `HomeDiagnosticsCache` (no mock): the
// cache computes on its background task and publishes on the main
// actor, exactly as ContentView drives it. Waiting is a bounded
// `Task.yield()` loop on `isComputing` — no sleeps, no timing
// assertions; the loop only bounds how long a stuck refresh may
// run before the test fails.
//
// What is proven here:
//   - A snapshot change invalidates the report (nil -> populated
//     -> nil publishes nil -> a report -> nil; a different
//     snapshot recomputes a different report).
//   - A backup-only change updates the backup verifications
//     WITHOUT dropping the report: the device report stays
//     published, and the values that do not depend on the backup
//     inventory (staged set, external-modification count, history
//     records) stay identical.
//   - A working-document change invalidates the staged set
//     (staged -> empty again when the staging is undone).
//   - A refresh with identical inputs republishes nothing new
//     (every published value stays equal).
//   - No snapshot means unknown, never fabricated: the report,
//     health score and fingerprint stay nil.
//
// Deliberate scoping note on "backup change invalidates ONLY the
// backup-derived summaries": the cache recomputes the whole
// report in one background pass BY DESIGN (see its header — the
// cards must never disagree about the same data), and the device
// report legitimately depends on the backup inventory
// (`DeviceProfile.backupCount`, the health backup dimension), so
// the report itself is recomputed too. What the test asserts is
// the honest, observable part of that claim: the backup
// verifications track the new inventory, the report is NOT
// dropped to nil, and the snapshot/working-derived values that
// do not depend on backups are unchanged. `apply()` only
// publishes values that actually changed, so unchanged values
// do not rebuild the home.
//
// Fixtures use the offline `originalProfile` layout via
// CoreModuleFixtures: no live device read, no clock, no network.
// The history stores load from the test host's history directory;
// their contents are whatever the host has, so these tests assert
// records/history are UNCHANGED across a refresh, never an
// absolute value.
import XCTest

@testable import GestaltX

@MainActor
final class HomeDiagnosticsCacheTests: XCTestCase {

    // MARK: - Fixtures

    /// iPhone18,1 (Air, A3518), region LL, eSIM on — the same
    /// fixture ViewSnapshotTests renders.
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

    /// The default fixture: iPhone14,7, region CH, eSIM off.
    private func snapshotB() throws -> DocumentSnapshot {
        CoreModuleFixtures.snapshot(document: try CoreModuleFixtures.document())
    }

    /// A backup record whose file does not exist in the backup
    /// directory, so verification deterministically reports
    /// `.notFound`. Fixed id/date so the record is stable.
    private func missingBackupRecord() -> BackupRecord {
        BackupRecord(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            date: Date(timeIntervalSince1970: 0),
            reason: "test",
            source: .device,
            deviceID: "test-device",
            byteCount: 1234,
            sha256: nil,
            provenance: .unknown)
    }

    // MARK: - Helpers

    /// Waits until no refresh is in flight. Bounded yield loop:
    /// no sleep, no timing assertion — the budget only fails a
    /// refresh that never finishes.
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

    // MARK: - Snapshot change invalidates the report

    func testSnapshotChangeInvalidatesReport() async throws {
        let cache = HomeDiagnosticsCache()

        await refreshAndWait(cache, snapshot: nil, working: nil, backups: [])
        XCTAssertNil(cache.deviceReport)
        XCTAssertNil(cache.healthScore)
        XCTAssertNil(cache.currentFingerprint)
        XCTAssertEqual(cache.externalModificationCount, 0)

        let snapshot = try snapshotA()
        await refreshAndWait(cache, snapshot: snapshot, working: snapshot.document, backups: [])
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertNotNil(cache.healthScore)
        XCTAssertNotNil(cache.currentFingerprint)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")

        await refreshAndWait(cache, snapshot: nil, working: nil, backups: [])
        XCTAssertNil(cache.deviceReport)
        XCTAssertNil(cache.healthScore)
        XCTAssertNil(cache.currentFingerprint)
    }

    func testDifferentSnapshotRecomputesReport() async throws {
        let cache = HomeDiagnosticsCache()
        let first = try snapshotA()
        let second = try snapshotB()

        await refreshAndWait(cache, snapshot: first, working: first.document, backups: [])
        let reportA = try XCTUnwrap(cache.deviceReport)
        XCTAssertEqual(reportA.profile.regionCode.value, "LL")

        await refreshAndWait(cache, snapshot: second, working: second.document, backups: [])
        let reportB = try XCTUnwrap(cache.deviceReport)
        XCTAssertEqual(reportB.profile.regionCode.value, "CH")
        XCTAssertNotEqual(reportA, reportB)
    }

    // MARK: - Backup-only change updates verifications, keeps the report

    func testBackupChangeUpdatesVerificationsWithoutDroppingReport() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()
        let record = missingBackupRecord()

        await refreshAndWait(cache, snapshot: snapshot, working: snapshot.document, backups: [])
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertTrue(cache.backupVerifications.isEmpty)
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
        XCTAssertEqual(cache.externalModificationCount, 0)
        let recordsBefore = cache.records
        let liveValuesBefore = cache.liveValues

        await refreshAndWait(cache, snapshot: snapshot, working: snapshot.document, backups: [record])
        XCTAssertEqual(cache.backupVerifications.count, 1)
        XCTAssertEqual(cache.backupVerifications.first?.record.id, record.id)
        XCTAssertEqual(cache.backupVerifications.first?.status, .notFound)
        // The report is recomputed (it counts backups) but never
        // dropped: the home keeps showing the device state.
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertNotNil(cache.healthScore)
        // Values that do not depend on the backup inventory are
        // untouched by a backup-only change.
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
        XCTAssertEqual(cache.externalModificationCount, 0)
        XCTAssertEqual(cache.records, recordsBefore)
        XCTAssertEqual(cache.liveValues, liveValuesBefore)
    }

    // MARK: - Working-document change invalidates the staged set

    func testWorkingDocumentChangeInvalidatesStagedSet() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()
        let base = snapshot.document
        // Staging the Audio Intelligence CacheExtra key stages
        // exactly that capability (see CompatibilityStatusTests for
        // the pure-function form of this rule).
        let staged = try CoreModuleFixtures.document(
            extra: [
                "productType": "iPhone18,1",
                "regionCode": "LL",
                DeviceCacheOptions.audioIntelligenceKey: true,
            ],
            greenTea: false,
            notGreenTea: true,
            wapi: false
        )

        await refreshAndWait(cache, snapshot: snapshot, working: base, backups: [])
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)

        await refreshAndWait(cache, snapshot: snapshot, working: staged, backups: [])
        XCTAssertEqual(cache.stagedFeatureIDs, ["audioIntelligence"])

        await refreshAndWait(cache, snapshot: snapshot, working: base, backups: [])
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
    }

    // MARK: - Identical refresh republishes nothing new

    func testIdenticalRefreshDoesNotChangePublishedValues() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()

        await refreshAndWait(cache, snapshot: snapshot, working: snapshot.document, backups: [])
        let report = cache.deviceReport
        let health = cache.healthScore
        let verifications = cache.backupVerifications
        let staged = cache.stagedFeatureIDs
        let externalCount = cache.externalModificationCount
        let records = cache.records
        let fingerprint = cache.currentFingerprint

        await refreshAndWait(cache, snapshot: snapshot, working: snapshot.document, backups: [])
        XCTAssertEqual(cache.deviceReport, report)
        XCTAssertEqual(cache.healthScore, health)
        XCTAssertEqual(cache.backupVerifications, verifications)
        XCTAssertEqual(cache.stagedFeatureIDs, staged)
        XCTAssertEqual(cache.externalModificationCount, externalCount)
        XCTAssertEqual(cache.records, records)
        XCTAssertEqual(cache.currentFingerprint, fingerprint)
    }

    // MARK: - No snapshot means unknown, never fabricated

    func testRefreshWithNoSnapshotPublishesUnknownNotFabricated() async throws {
        let cache = HomeDiagnosticsCache()
        await refreshAndWait(cache, snapshot: nil, working: nil, backups: [])
        XCTAssertNil(cache.deviceReport)
        XCTAssertNil(cache.healthScore)
        XCTAssertNil(cache.currentFingerprint)
        XCTAssertEqual(cache.externalModificationCount, 0)
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
        XCTAssertTrue(cache.backupVerifications.isEmpty)
    }
}
