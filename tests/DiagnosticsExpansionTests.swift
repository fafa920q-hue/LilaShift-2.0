// SPDX-License-Identifier: GPL-3.0-only
// Tests for Diagnostics Expansion (诊断扩展): battery level/state
// mapping including unknown, app cache size calculation and the
// own-Caches-only clear action, connection status from real data,
// and the operation log viewer (recorded and empty states). Nothing
// here touches the MobileGestalt cache.
import Foundation
import UIKit
import XCTest
@testable import GestaltX

final class DiagnosticsExpansionTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsExpansionTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    // MARK: - Battery

    func testBatteryLevelAndStateMapping() {
        let charging = BatteryStatus.from(level: 0.5, state: .charging)
        XCTAssertEqual(charging.level, 0.5)
        XCTAssertEqual(charging.levelPercent, 50)
        XCTAssertEqual(charging.state, .charging)

        let full = BatteryStatus.from(level: 1.0, state: .full)
        XCTAssertEqual(full.levelPercent, 100)
        XCTAssertEqual(full.state, .full)

        let unplugged = BatteryStatus.from(level: 0.0, state: .unplugged)
        XCTAssertEqual(unplugged.levelPercent, 0)
        XCTAssertEqual(unplugged.state, .unplugged)
    }

    /// UIDevice reports -1.0 when it cannot determine the level:
    /// that is unknown, never zero.
    func testBatteryUnknownLevelIsNilNotZero() {
        let unknown = BatteryStatus.from(level: -1.0, state: .unknown)
        XCTAssertNil(unknown.level)
        XCTAssertNil(unknown.levelPercent)
        XCTAssertEqual(unknown.state, .unknown)
    }

    func testBatteryLevelIsClampedToUnitRange() {
        XCTAssertEqual(BatteryStatus.from(level: 1.5, state: .charging).level, 1.0)
        XCTAssertEqual(BatteryStatus.from(level: -0.5, state: .charging).level, nil)
    }

    /// Battery health, cycle count and capacity are not available
    /// through public iOS APIs: the note says so, and the struct
    /// carries no such field.
    func testBatteryHealthIsExplicitlyNotAvailable() {
        XCTAssertFalse(BatteryStatus.healthNotAvailable.isEmpty)
        XCTAssertTrue(BatteryStatus.healthNotAvailable.contains("not available"))
    }

    // MARK: - App container cache

    func testAppCacheMeasureRealSizes() throws {
        let base = try tempDirectory()
        let appSupport = base.appendingPathComponent("Application Support")
        let caches = base.appendingPathComponent("Caches")
        let tmp = base.appendingPathComponent("tmp")
        try writeFile(appSupport.appendingPathComponent("a.plist"), bytes: 100)
        try writeFile(caches.appendingPathComponent("sub/b.dat"), bytes: 200)
        try writeFile(tmp.appendingPathComponent("c.tmp"), bytes: 50)

        let report = AppContainerCacheMeasurer.measure(
            applicationSupport: appSupport, caches: caches, temporary: tmp)
        XCTAssertEqual(report.entry(for: .applicationSupport)?.byteCount, 100)
        XCTAssertEqual(report.entry(for: .applicationSupport)?.fileCount, 1)
        XCTAssertEqual(report.entry(for: .caches)?.byteCount, 200)
        XCTAssertEqual(report.entry(for: .caches)?.fileCount, 1)
        XCTAssertEqual(report.entry(for: .temporary)?.byteCount, 50)
        XCTAssertEqual(report.entry(for: .temporary)?.fileCount, 1)
        XCTAssertEqual(report.totalBytes, 350)
        XCTAssertEqual(report.totalFiles, 3)
    }

    func testAppCacheMeasureMissingDirectoriesAreZero() throws {
        let base = try tempDirectory()
        let report = AppContainerCacheMeasurer.measure(
            applicationSupport: base.appendingPathComponent("Application Support"),
            caches: base.appendingPathComponent("Caches"),
            temporary: base.appendingPathComponent("tmp"))
        XCTAssertEqual(report.totalBytes, 0)
        XCTAssertEqual(report.totalFiles, 0)
        XCTAssertEqual(report.entries.count, 3)
    }

    func testClearCachesFreesOwnCachesOnly() throws {
        let base = try tempDirectory()
        let appSupport = base.appendingPathComponent("Application Support")
        let caches = base.appendingPathComponent("Caches")
        let tmp = base.appendingPathComponent("tmp")
        try writeFile(appSupport.appendingPathComponent("keep.plist"), bytes: 100)
        try writeFile(caches.appendingPathComponent("sub/drop.dat"), bytes: 200)
        try writeFile(tmp.appendingPathComponent("keep.tmp"), bytes: 50)

        let freed = try AppContainerCacheMeasurer.clearCaches(at: caches)
        XCTAssertEqual(freed, 200)
        let after = AppContainerCacheMeasurer.measure(
            applicationSupport: appSupport, caches: caches, temporary: tmp)
        XCTAssertEqual(after.entry(for: .caches)?.byteCount, 0)
        XCTAssertEqual(after.entry(for: .caches)?.fileCount, 0)
        // The other directories are untouched.
        XCTAssertEqual(after.entry(for: .applicationSupport)?.byteCount, 100)
        XCTAssertEqual(after.entry(for: .temporary)?.byteCount, 50)
        // The Caches directory itself still exists.
        XCTAssertTrue(FileManager.default.fileExists(atPath: caches.path))
    }

    func testClearCachesRefusesNonCachesDirectory() throws {
        let base = try tempDirectory()
        let appSupport = base.appendingPathComponent("Application Support")
        try writeFile(appSupport.appendingPathComponent("keep.plist"), bytes: 100)
        XCTAssertThrowsError(try AppContainerCacheMeasurer.clearCaches(at: appSupport))
        XCTAssertThrowsError(try AppContainerCacheMeasurer.clearCaches(
            at: base.appendingPathComponent("NotCaches")))
        // The refused directory is untouched.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: appSupport.appendingPathComponent("keep.plist").path))
    }

    // MARK: - Connection status

    func testConnectionStatusFromRealProfile() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let readAt = Date(timeIntervalSince1970: 2_000_000)
        let status = DeviceConnectionStatus.from(profile: profile, lastReadAt: readAt)
        XCTAssertEqual(status.productType.value, "iPhone14,7")
        XCTAssertEqual(status.osVersion.value, "27.0.1")
        XCTAssertEqual(status.osBuild.value, "23A344")
        XCTAssertEqual(status.regionCode.value, "CH")
        XCTAssertEqual(status.appGroupSummary, "Available")
        XCTAssertEqual(status.cacheUUID, CoreModuleFixtures.uuid)
        if case .read(_, let byteCount) = status.cacheReadState {
            XCTAssertEqual(status.cacheReadSummary, "Read: \(byteCount) bytes")
        } else {
            XCTFail("Expected a successful cache read state")
        }
        XCTAssertEqual(status.lastReadAt, readAt)
        XCTAssertNotEqual(status.lastReadSummary, "Unknown")
    }

    func testConnectionStatusNotReadIsAllUnknown() {
        let status = DeviceConnectionStatus.notRead
        XCTAssertNil(status.productType.value)
        XCTAssertNil(status.osVersion.value)
        XCTAssertNil(status.appGroupAvailable.value)
        XCTAssertEqual(status.appGroupSummary, "Unknown")
        XCTAssertEqual(status.cacheReadSummary, "Not read yet")
        XCTAssertNil(status.cacheUUID)
        XCTAssertNil(status.lastReadAt)
        XCTAssertEqual(status.lastReadSummary, "Unknown")
    }

    func testConnectionStatusFailedReadKeepsReason() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let status = DeviceConnectionStatus(
            productType: profile.productType, osVersion: profile.osVersion,
            osBuild: profile.osBuild, regionCode: profile.regionCode,
            appGroupAvailable: .unknown(reason: "test"),
            cacheReadState: .failed(reason: "layout unresolvable"), lastReadAt: nil)
        XCTAssertEqual(status.appGroupSummary, "Unknown")
        XCTAssertEqual(status.cacheReadSummary, "layout unresolvable")
        XCTAssertNil(status.cacheUUID)
    }

    // MARK: - Operation event recorder and log viewer

    func testOperationEventRecorderNewestFirstAndCap() async {
        let recorder = OperationEventRecorder()
        await recorder.record(OperationEvent(kind: .readSucceeded, detail: "first"))
        await recorder.record(OperationEvent(kind: .backupCreated, detail: "second"))
        await recorder.record(OperationEvent(kind: .readFailed, detail: "third"))
        XCTAssertEqual(await recorder.count, 3)
        let events = await recorder.recordedEvents()
        XCTAssertEqual(events.map(\.detail), ["third", "second", "first"])

        for index in 0..<600 {
            await recorder.record(OperationEvent(kind: .readSucceeded, detail: "event \(index)"))
        }
        XCTAssertEqual(await recorder.count, OperationEventRecorder.maxEvents)
        XCTAssertEqual(await recorder.recordedEvents().first?.detail, "event 599")

        await recorder.clear()
        XCTAssertEqual(await recorder.count, 0)
        XCTAssertTrue(await recorder.recordedEvents().isEmpty)
    }

    func testOperationLogSnapshotEmptyAndConnectedStates() {
        let empty = OperationLogSnapshot(events: [], freeTextLines: [])
        XCTAssertFalse(empty.hasEvents)
        XCTAssertFalse(empty.hasFreeTextLines)
        // Write/restore/guard events are not connected yet, by
        // design — the viewer must say so, not pretend otherwise.
        XCTAssertFalse(OperationLogSnapshot.writeAndRestoreEventsConnected)
        XCTAssertFalse(OperationLogSnapshot.writeAndRestoreNote.isEmpty)

        let filled = OperationLogSnapshot(
            events: [OperationEvent(kind: .readSucceeded, detail: "read")],
            freeTextLines: ["[read] ok"])
        XCTAssertTrue(filled.hasEvents)
        XCTAssertTrue(filled.hasFreeTextLines)
    }

    func testOperationEventKindTitlesArePresent() {
        for kind in [OperationEventKind.readSucceeded, .readFailed,
                     .writeVerified, .writeFailed,
                     .restoreSucceeded, .restoreFailed,
                     .guardLayoutUnresolved, .guardHardwareIdentity,
                     .guardNativeConflict, .slotUnresolvable,
                     .backupCreated, .backupFailed, .regionReverted] {
            XCTAssertFalse(kind.title.isEmpty, "\(kind.rawValue) must have a title")
        }
        XCTAssertEqual(OperationEventKind.readSucceeded.title, "Read succeeded")
        XCTAssertEqual(OperationEventKind.backupCreated.title, "Backup saved")
    }

    // MARK: - Recorded events flow into diagnosis

    /// A recorded read failure produces the read-failed diagnosis,
    /// and the report says events are connected.
    func testRecordedReadFailureDiagnosed() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let input = FaultDiagnosisInput(
            profile: profile, backupRecords: [],
            events: [OperationEvent(kind: .readFailed, detail: "read timed out")])
        let report = SmartFaultDiagnosis.diagnose(input)
        XCTAssertTrue(report.eventsConnected)
        XCTAssertNotNil(report.diagnosis(code: "read-failed"))
    }

    /// Success events carry no diagnosis: they change nothing in
    /// the report.
    func testSuccessEventsCarryNoDiagnosis() {
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let baseline = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile, backupRecords: [], events: []))
        let withSuccess = SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: profile, backupRecords: [],
            events: [OperationEvent(kind: .readSucceeded, detail: "read ok"),
                     OperationEvent(kind: .backupCreated, detail: "backup saved")]))
        XCTAssertEqual(
            withSuccess.diagnoses.map(\.code), baseline.diagnoses.map(\.code),
            "Success events must not add diagnoses")
    }
}
