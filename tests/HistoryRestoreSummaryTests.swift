// SPDX-License-Identifier: GPL-3.0-only
// Tests for the Phase G history & restore presentation: the unified
// entries (first-recorded / current / staged values, restore
// eligibility), the restore-preview checklist contents (device
// identity, file integrity, backup source, system compatibility,
// before/after diff), and the two-step confirmation gate.
//
// Fixtures come from `CoreModuleFixtures` (LilaIntelligenceTests).
// No test fabricates a device value, and no test executes a restore.
import Foundation
import XCTest
@testable import GestaltX

final class HistoryRestoreSummaryTests: XCTestCase {
    private func makeChange(
        id: UUID = UUID(), key: String = GestaltKeys.regionCode,
        layer: ChangeLayer = .cacheExtra,
        original: ChangeValue = .string("CH"), new: ChangeValue = .string("LL"),
        provenance: BackupProvenance = .preModification, verified: Bool = true,
        restartVerified: Bool = false
    ) -> RecordedChange {
        RecordedChange(id: id, date: Date(), deviceID: "test-device", osBuild: "23A344",
                       featureID: "regionCode", key: key, layer: layer,
                       original: original, new: new,
                       backupProvenance: provenance, verified: verified,
                       restartVerified: restartVerified)
    }

    private func makeRecord(deviceID: String = "test-device",
                            provenance: BackupProvenance = .preModification) -> BackupRecord {
        BackupRecord(id: UUID(), date: Date(), reason: "test", source: .device,
                     deviceID: deviceID, byteCount: 6480, sha256: nil,
                     provenance: provenance)
    }

    private func timeline(
        records: [RecordedChange], snapshot: GestaltDocument, current: GestaltDocument
    ) -> [RestoreTimelineEntry] {
        RestoreIntelligence.timeline(
            records: records, snapshot: snapshot, current: current,
            layout: CoreModuleFixtures.layout)
    }

    // MARK: - Unified entries

    func testUnifiedEntryShowsStagedValueWhenWorkingDiffers() throws {
        let first = try CoreModuleFixtures.document()
        let working = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let change = makeChange()
        let entries = HistoryRestoreSummary.unifiedEntries(
            timeline: timeline(records: [change], snapshot: first, current: working),
            records: [change], snapshot: first, working: working,
            layout: CoreModuleFixtures.layout, verifications: [])
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.firstRecordedValue, .string("CH"))
        XCTAssertEqual(entry.currentValue, .string("LL"))
        XCTAssertEqual(entry.stagedValue, .string("LL"),
                       "The working document differs from the first read, so the staged value is shown")
        XCTAssertTrue(entry.isRecordedOperation)
        XCTAssertTrue(entry.autoRestorable)
    }

    func testUnifiedEntryHidesStagedValueWhenNothingStaged() throws {
        let doc = try CoreModuleFixtures.document()
        let change = makeChange()
        let entries = HistoryRestoreSummary.unifiedEntries(
            timeline: timeline(records: [change], snapshot: doc, current: doc),
            records: [change], snapshot: doc, working: doc,
            layout: CoreModuleFixtures.layout, verifications: [])
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].stagedValue,
                     "Working equals the first read: there is no staged change to show")
    }

    func testDetectedDifferenceIsFirstRecordedNeverFactory() throws {
        let first = try CoreModuleFixtures.document()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let entries = HistoryRestoreSummary.unifiedEntries(
            timeline: timeline(records: [], snapshot: first, current: current),
            records: [], snapshot: first, working: current,
            layout: CoreModuleFixtures.layout, verifications: [])
        let region = entries.first { $0.key == GestaltKeys.regionCode }
        XCTAssertNotNil(region, "The region difference must appear as a detected entry")
        XCTAssertEqual(region?.firstRecordedLabel, "First-recorded value")
        XCTAssertFalse(region?.isRecordedOperation ?? true)
        XCTAssertFalse(region?.autoRestorable ?? true,
                       "A detected difference has no trusted original and is never auto-restorable")
        XCTAssertEqual(region?.firstRecordedValue, .string("CH"))
        XCTAssertEqual(region?.currentValue, .string("LL"))
    }

    func testUnifiedEntryReportsVerifiedBackupOnFile() throws {
        let doc = try CoreModuleFixtures.document()
        let change = makeChange()
        let record = makeRecord()
        let verification = BackupVerification(record: record, status: .verified,
                                              layoutMatchesCurrent: true)
        let entries = HistoryRestoreSummary.unifiedEntries(
            timeline: timeline(records: [change], snapshot: doc, current: doc),
            records: [change], snapshot: doc, working: doc,
            layout: CoreModuleFixtures.layout, verifications: [verification])
        XCTAssertTrue(entries[0].verifiedBackupOnFile)
    }

    // MARK: - Restore preview checklist (single change)

    private func previewItem(for change: RecordedChange,
                             current: GestaltDocument) -> RestoreItemPreview {
        RestorePreviewBuilder.build(
            changes: [change], records: [:], current: current,
            layout: CoreModuleFixtures.layout).items[0]
    }

    func testChecklistShowsAllFiveContentsForMatchingDevice() throws {
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let change = makeChange()
        let record = makeRecord()
        let verification = BackupVerification(record: record, status: .verified,
                                              layoutMatchesCurrent: true)
        let checklist = RestorePreviewChecklistBuilder.build(
            change: change, item: previewItem(for: change, current: current),
            verifications: [verification], deviceID: "test-device",
            deviceDisplayName: "Test iPhone", current: current,
            layout: CoreModuleFixtures.layout)
        XCTAssertEqual(checklist.deviceIdentity, "This device")
        XCTAssertEqual(checklist.deviceMatches, true)
        XCTAssertEqual(checklist.deviceDisplayName, "Test iPhone")
        XCTAssertEqual(checklist.fileIntegrity, "Verified backup on file.")
        XCTAssertEqual(checklist.fileIntegrityOK, true)
        XCTAssertEqual(checklist.backupSource, "State before change")
        XCTAssertEqual(checklist.systemCompatible, "Verified. Cache layout matches this device.")
        XCTAssertEqual(checklist.systemCompatibleOK, true)
        XCTAssertEqual(checklist.beforeValue, .string("LL"))
        XCTAssertEqual(checklist.afterValue, .string("CH"))
        XCTAssertTrue(checklist.noCheckFailed)
    }

    func testChecklistFlagsAnotherDevice() throws {
        let current = try CoreModuleFixtures.document()
        let change = makeChange()
        let checklist = RestorePreviewChecklistBuilder.build(
            change: change, item: previewItem(for: change, current: current),
            verifications: [], deviceID: "other-device",
            deviceDisplayName: "Test iPhone", current: current,
            layout: CoreModuleFixtures.layout)
        XCTAssertEqual(checklist.deviceIdentity, "Another device")
        XCTAssertEqual(checklist.deviceMatches, false)
        XCTAssertFalse(checklist.noCheckFailed)
    }

    func testChecklistFileIntegrityUnknownWhenNoBackup() throws {
        let current = try CoreModuleFixtures.document()
        let change = makeChange()
        let checklist = RestorePreviewChecklistBuilder.build(
            change: change, item: previewItem(for: change, current: current),
            verifications: [], deviceID: "test-device",
            deviceDisplayName: "Test iPhone", current: current,
            layout: CoreModuleFixtures.layout)
        XCTAssertNil(checklist.fileIntegrityOK,
                     "No backup file to check is unknown, never a pass or a failure")
        XCTAssertEqual(checklist.fileIntegrity, "No verified backup file for this change.")
        XCTAssertTrue(checklist.noCheckFailed,
                      "An unknown check is shown as unknown; it is not a failed check")
    }

    func testChecklistSystemCompatibilityUnknownWithoutLayout() throws {
        let current = try CoreModuleFixtures.document()
        let change = makeChange()
        let checklist = RestorePreviewChecklistBuilder.build(
            change: change, item: previewItem(for: change, current: current),
            verifications: [], deviceID: "test-device",
            deviceDisplayName: "Test iPhone", current: current, layout: nil)
        XCTAssertNil(checklist.systemCompatibleOK)
        XCTAssertEqual(checklist.systemCompatible, "Unknown")
    }

    // MARK: - Restore preview checklist (whole backup)

    func testBackupChecklistVerifiesTheExactFile() throws {
        let current = try CoreModuleFixtures.document()
        let record = makeRecord()
        let verification = BackupVerification(record: record, status: .verified,
                                              layoutMatchesCurrent: true)
        let checklist = RestorePreviewChecklistBuilder.buildForBackup(
            record: record, verifications: [verification], deviceID: "test-device",
            deviceDisplayName: "Test iPhone", current: current,
            layout: CoreModuleFixtures.layout)
        XCTAssertEqual(checklist.fileIntegrity, "Verified.")
        XCTAssertEqual(checklist.fileIntegrityOK, true)
        XCTAssertNil(checklist.beforeValue, "A whole-backup restore has no single before value")
        XCTAssertNil(checklist.afterValue, "A whole-backup restore has no single after value")
        XCTAssertTrue(checklist.noCheckFailed)
    }

    func testBackupChecklistFailsWhenFileMissing() throws {
        let current = try CoreModuleFixtures.document()
        let record = makeRecord()
        let checklist = RestorePreviewChecklistBuilder.buildForBackup(
            record: record, verifications: [], deviceID: "test-device",
            deviceDisplayName: "Test iPhone", current: current,
            layout: CoreModuleFixtures.layout)
        XCTAssertEqual(checklist.fileIntegrity, "Backup file not found.")
        XCTAssertEqual(checklist.fileIntegrityOK, false)
        XCTAssertFalse(checklist.noCheckFailed)
    }

    // MARK: - Two-step confirmation gate

    func testTwoStepConfirmationRequiresSecondRequest() {
        var gate = TwoStepConfirmation()
        XCTAssertFalse(gate.request(), "The first request only arms the gate")
        XCTAssertTrue(gate.armed)
        XCTAssertTrue(gate.request(), "Only the second request executes")
    }

    func testTwoStepConfirmationResetDisarms() {
        var gate = TwoStepConfirmation()
        XCTAssertFalse(gate.request())
        gate.reset()
        XCTAssertFalse(gate.armed)
        XCTAssertFalse(gate.request(), "After a reset the next request only arms again")
    }
}
