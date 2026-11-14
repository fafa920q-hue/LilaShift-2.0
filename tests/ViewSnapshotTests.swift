// SPDX-License-Identifier: GPL-3.0-only
//
// ViewSnapshotTests.swift — SnapshotTesting UI regression tests for the
// key SwiftUI cards (UI 回归测试).
//
// What is snapshotted (8 image snapshots + 5 text snapshots):
//   Image (pixel) — `.image` with a fixed 390x844 layout, light traits,
//   display scale 2, precision 1, perceptualPrecision 0.98:
//     - PresetCatalogCard: unread (empty manager) / populated (fixture snapshot)
//     - SmartFaultDiagnosisCard: no issues (unread) / with issues (fixture snapshot)
//     - PersonalizationCenterCard: empty (unread) / populated (fixture snapshot)
//     - SystemHealthScoreCard: unknown (unread) / scored (fixture snapshot)
//   Text (`.dump`) — the deterministic data that feeds the diagnostics card:
//     - BatteryStatus unknown / known
//     - DeviceConnectionStatus notRead / read
//     - AppContainerCacheEntry list measured from a fixed temporary directory
//
// Why the DiagnosticsExpansionCard has NO image snapshot:
//   Its cache section renders the live sizes of the app container
//   (Application Support / Caches / Temporary), including the temporary
//   directory where other tests write files. Those numbers depend on
//   test execution order, so a pixel snapshot of that card would be
//   flaky. The card's deterministic inputs are snapshotted as text
//   instead (see the dump tests below). This is a deliberate, documented
//   gap — not an oversight.
//
// How references are created (read this before running the tests):
//   This VM has no Swift compiler and no simulator, so the reference
//   snapshots cannot be generated here. They are recorded on the
//   FIRST CI RUN: `record: .missing` means only missing references
//   are recorded (an existing reference is compared, never
//   overwritten), so the first run records and passes. The recorded
//   files live in `tests/__Snapshots__/ViewSnapshotTests/` and must
//   be committed to the branch in a follow-up commit (the CI workflow
//   uploads them as an artifact so they can be downloaded). Until
//   they are committed, the tests record but do not yet guard against
//   regressions — say so in any report that mentions these tests.
//   To update a reference after a legitimate UI change, delete the
//   reference file and re-run the test (it records again), or run
//   once with SNAPSHOT_TESTING_RECORD=all. Never edit a reference
//   image by hand.
//
// Determinism (why the snapshots are stable across runs):
//   - The fixture snapshot is fixed data (CoreModuleFixtures): the
//     same product type, region and AI flags on every run. No live
//     device read, no clock, no network.
//   - The unread manager has no snapshot, so every card renders its
//     "read the device first" empty state.
//   - The test host's history directory is empty, so the cards' disk
//     loads return empty.
//   - The populated cards render no date: the operation log starts
//     empty, the combination form is hidden, the edit form is hidden,
//     and the fingerprint is absent until a read happens. The
//     populated manager's lastReadAt stays nil (loadSnapshotForTests
//     does not set it).
//   - The snapshot is taken on the main actor with a fixed size and
//     fixed traits (light, scale 2), so the layout is stable.
//
// All four cards read their GestaltManager from the environment
// (@EnvironmentObject), so every snapshot wraps the card in
// `.environmentObject(manager)`. Rendering a card without it crashes.

import SnapshotTesting
import SwiftUI
import XCTest

@testable import GestaltX

@MainActor
final class ViewSnapshotTests: XCTestCase {

    // MARK: - Fixtures

    /// A manager that has never read a device: every card renders its
    /// empty / "read the device first" state.
    private func unreadManager() -> GestaltManager {
        GestaltManager()
    }

    /// A manager holding the fixed fixture snapshot: iPhone18,1 (Air,
    /// A3518) with region LL and eSIM on (green tea off, not-green-tea
    /// on). The document carries no AI keys and no recorded originals.
    /// No live device read, no clock.
    private func populatedManager() throws -> GestaltManager {
        let manager = GestaltManager()
        let document = try CoreModuleFixtures.document(
            extra: [
                "productType": "iPhone18,1",
                "regionCode": "LL",
            ],
            greenTea: false,
            notGreenTea: true,
            wapi: false
        )
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        manager.loadSnapshotForTests(snapshot)
        return manager
    }

    // MARK: - Snapshot helpers

    /// Asserts an image snapshot of a card with the fixed P5 layout:
    /// 390x844 points, light traits, display scale 2.
    private func assertCardSnapshot<V: View>(
        _ view: V, named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        assertSnapshot(
            of: view,
            as: .image(
                precision: 1,
                perceptualPrecision: 0.98,
                layout: .fixed(width: 390, height: 844),
                traits: UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: .light),
                    UITraitCollection(displayScale: 2),
                ])
            ),
            named: name,
            record: .missing,
            file: file,
            testName: testName,
            line: line
        )
    }

    // MARK: - Preset catalog card

    func testPresetCatalogCardUnreadSnapshot() {
        assertCardSnapshot(
            PresetCatalogCard().environmentObject(unreadManager()),
            named: "preset-catalog-unread")
    }

    func testPresetCatalogCardPopulatedSnapshot() throws {
        assertCardSnapshot(
            PresetCatalogCard().environmentObject(try populatedManager()),
            named: "preset-catalog-populated")
    }

    // MARK: - Smart fault diagnosis card

    func testSmartFaultDiagnosisCardUnreadSnapshot() {
        assertCardSnapshot(
            SmartFaultDiagnosisCard().environmentObject(unreadManager()),
            named: "smart-fault-diagnosis-unread")
    }

    func testSmartFaultDiagnosisCardPopulatedSnapshot() throws {
        assertCardSnapshot(
            SmartFaultDiagnosisCard().environmentObject(try populatedManager()),
            named: "smart-fault-diagnosis-populated")
    }

    // MARK: - Personalization center card

    func testPersonalizationCenterCardUnreadSnapshot() {
        assertCardSnapshot(
            PersonalizationCenterCard().environmentObject(unreadManager()),
            named: "personalization-center-unread")
    }

    func testPersonalizationCenterCardPopulatedSnapshot() throws {
        assertCardSnapshot(
            PersonalizationCenterCard().environmentObject(try populatedManager()),
            named: "personalization-center-populated")
    }

    // MARK: - System health score card

    func testSystemHealthScoreCardUnreadSnapshot() {
        assertCardSnapshot(
            SystemHealthScoreCard().environmentObject(unreadManager()),
            named: "system-health-score-unread")
    }

    func testSystemHealthScoreCardPopulatedSnapshot() throws {
        assertCardSnapshot(
            SystemHealthScoreCard().environmentObject(try populatedManager()),
            named: "system-health-score-populated")
    }

    // MARK: - Diagnostics expansion: deterministic data (.dump)
    //
    // The DiagnosticsExpansionCard itself has no image snapshot (see
    // the header: its cache section renders live container sizes).
    // These text snapshots cover the deterministic data that feeds it.

    /// Battery unknown: the state a simulator (and an unread device)
    /// always reports.
    func testDiagnosticsBatteryUnknownSnapshot() {
        assertSnapshot(
            of: BatteryStatus(level: nil, state: .unknown),
            as: .dump,
            named: "battery-unknown",
            record: .missing)
    }

    /// Battery known: the mapping from a real UIDevice reading
    /// (level 0.8, charging) to the displayed status.
    func testDiagnosticsBatteryKnownSnapshot() {
        let status = BatteryStatus.from(level: 0.8, state: .charging)
        assertSnapshot(
            of: status,
            as: .dump,
            named: "battery-known",
            record: .missing)
    }

    /// Connection status before any device read: every field unknown.
    func testDiagnosticsConnectionNotReadSnapshot() {
        assertSnapshot(
            of: DeviceConnectionStatus.notRead,
            as: .dump,
            named: "connection-not-read",
            record: .missing)
    }

    /// Connection status after a read of the fixture profile. The
    /// last-read time stays nil (loadSnapshotForTests does not set
    /// it), so the snapshot is deterministic.
    func testDiagnosticsConnectionReadSnapshot() {
        let profile = CoreModuleFixtures.profile(
            productType: "iPhone18,1", isNativeAI: true, regionCode: "LL")
        let status = DeviceConnectionStatus.from(profile: profile, lastReadAt: nil)
        assertSnapshot(
            of: status,
            as: .dump,
            named: "connection-read",
            record: .missing)
    }

    /// Cache entries measured from a fixed temporary directory with
    /// known files (10 / 20 / 30 bytes). Only the entries are dumped,
    /// not the whole report: the report carries a `measuredAt` clock
    /// value that would make the snapshot non-deterministic.
    func testDiagnosticsCacheEntriesSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ViewSnapshotTests-cache-\(UUID().uuidString)",
                isDirectory: true)
        let applicationSupport = root.appendingPathComponent(
            "ApplicationSupport", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let temporary = root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(
            at: applicationSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 0x41, count: 10).write(
            to: applicationSupport.appendingPathComponent("a.txt"))
        try Data(repeating: 0x42, count: 20).write(
            to: caches.appendingPathComponent("b.txt"))
        try Data(repeating: 0x43, count: 30).write(
            to: temporary.appendingPathComponent("c.txt"))
        let report = AppContainerCacheMeasurer.measure(
            applicationSupport: applicationSupport,
            caches: caches,
            temporary: temporary)
        assertSnapshot(
            of: report.entries,
            as: .dump,
            named: "cache-entries",
            record: .missing)
    }
}
