// SPDX-License-Identifier: GPL-3.0-only
// Tests for Restore Intelligence (智能恢复引擎): timeline records
// (including the no-original-value refusal), restore-preview
// correctness, eligibility decisions, and the history journal's
// tamper resistance.
//
// The first-read value is the "first-recorded value", never a factory
// original: the tests assert that a `.firstRead` record is never
// auto-restorable and that a field with no trusted original never
// offers a fake precise restore.
import Foundation
import XCTest
@testable import GestaltX

final class RestoreIntelligenceTests: XCTestCase {
    private func makeChange(id: UUID = UUID(), key: String = GestaltKeys.regionCode,
                            layer: ChangeLayer = .cacheExtra,
                            original: ChangeValue = .string("CH"), new: ChangeValue = .string("LL"),
                            provenance: BackupProvenance = .verifiedFactory,
                            verified: Bool = true) -> RecordedChange {
        RecordedChange(id: id, date: Date(), deviceID: "test-device", osBuild: "23A344",
                       featureID: "regionCode", key: key, layer: layer,
                       original: original, new: new,
                       backupProvenance: provenance, verified: verified,
                       restartVerified: false)
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - History journal and stores

    func testChangeRecordStoreRoundTrip() throws {
        let directory = try tempDirectory()
        let store = ChangeRecordStore(directory: directory, deviceID: "test-device")
        XCTAssertEqual(try store.load(), [], "A missing history file loads as an empty store")
        let first = makeChange(key: GestaltKeys.regionCode)
        let second = makeChange(key: DeviceCacheOptions.greenTeaKey, layer: .cacheData,
                                original: .bool(true), new: .bool(false),
                                provenance: .preModification)
        try store.append(first)
        try store.append(second)
        XCTAssertEqual(try store.load(), [first, second], "Records survive a verified round-trip")
    }

    func testChangeRecordStoreRefusesTamperedFile() throws {
        let directory = try tempDirectory()
        let store = ChangeRecordStore(directory: directory, deviceID: "test-device")
        try store.append(makeChange())
        let fileURL = directory.appendingPathComponent(ChangeRecordStore.fileName)
        var bytes = try Data(contentsOf: fileURL)
        bytes[bytes.count - 2] = bytes[bytes.count - 2] ^ 0xFF
        try bytes.write(to: fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load(),
                             "A tampered history file must be refused, never trusted")
    }

    func testChangeRecordStoreRefusesForeignDevice() throws {
        let directory = try tempDirectory()
        let store = ChangeRecordStore(directory: directory, deviceID: "device-A")
        try store.append(makeChange())
        let other = ChangeRecordStore(directory: directory, deviceID: "device-B")
        XCTAssertThrowsError(try other.load(),
                             "History from another device must never be restored here")
    }

    func testRestoreLogRoundTripAndExport() throws {
        let directory = try tempDirectory()
        let log = RestoreLogStore(directory: directory, deviceID: "test-device")
        XCTAssertEqual(try log.load(), [], "A missing log loads as empty")
        let entry = RestoreLogEntry(
            id: UUID(), date: Date(), changeID: UUID(), featureID: "regionCode",
            key: GestaltKeys.regionCode, layer: .cacheExtra, targetValue: .string("CH"),
            outcome: .restored, reason: "test", restorePointID: nil,
            deviceID: "test-device", osBuild: "23A344")
        XCTAssertTrue(log.append(entry), "Appending a log entry must succeed")
        XCTAssertEqual(try log.load(), [entry])
        let exported = try log.exportJSON()
        let decoded = try JSONDecoder().decode([RestoreLogEntry].self, from: exported)
        XCTAssertEqual(decoded, [entry], "The exported log must decode back to the same entries")
    }

    func testHistoryJournalDigestMismatch() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent("probe.json")
        try HistoryJournal.writeVerifiedJSON(["a", "b"], to: fileURL)
        XCTAssertEqual(try HistoryJournal.readVerifiedJSON([String].self, from: fileURL), ["a", "b"])
        try "tampered".write(to: fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HistoryJournal.readVerifiedJSON([String].self, from: fileURL)) { error in
            XCTAssertEqual(error as? HistoryJournalError, .digestMismatch,
                           "A file whose bytes no longer match its digest must fail as a digest mismatch")
        }
    }

    // MARK: - Eligibility (decision only)

    func testEligibilityTrustedOriginalRestorable() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(provenance: .verifiedFactory, verified: true)
        let record = BackupRecord(id: UUID(), date: Date(), reason: "test", source: .device,
                                  deviceID: "test-device", byteCount: 6480,
                                  sha256: nil, provenance: .verifiedFactory)
        let result = RestoreEligibilityChecker.eligibility(
            for: change, record: record, current: document, layout: CoreModuleFixtures.layout)
        if case .restorable = result { } else {
            XCTFail("A verified change with trusted provenance must be restorable, got \(result)")
        }
    }

    func testEligibilityFirstReadNotRestorable() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(provenance: .firstRead, verified: true)
        let result = RestoreEligibilityChecker.eligibility(
            for: change, record: nil, current: document, layout: CoreModuleFixtures.layout)
        if case .notRestorable(let reason) = result {
            XCTAssertFalse(reason.isEmpty, "The refusal must carry a specific reason")
        } else {
            XCTFail("A first-read record must never be auto-restored")
        }
    }

    func testEligibilityUnverifiedNotRestorable() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(provenance: .verifiedFactory, verified: false)
        let result = RestoreEligibilityChecker.eligibility(
            for: change, record: nil, current: document, layout: CoreModuleFixtures.layout)
        if case .restorable = result {
            XCTFail("An unverified change must never be auto-restored")
        }
    }

    func testEligibilityUnlocatableSlotNotRestorable() throws {
        let document = try CoreModuleFixtures.document()
        // The offline profile does not resolve the Audio Intelligence
        // slot, so a change to it must refuse rather than guess an offset.
        let change = makeChange(key: DeviceCacheOptions.audioIntelligenceKey, layer: .cacheData,
                                original: .bool(false), new: .bool(true),
                                provenance: .verifiedFactory, verified: true)
        let result = RestoreEligibilityChecker.eligibility(
            for: change, record: nil, current: document, layout: CoreModuleFixtures.layout)
        if case .notRestorable = result { } else {
            XCTFail("A change to an unlocatable CacheData slot must refuse")
        }
    }

    func testEligibilityUntrustedBackupRecordNotRestorable() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(provenance: .verifiedFactory, verified: true)
        let record = BackupRecord(id: UUID(), date: Date(), reason: "test", source: .device,
                                  deviceID: "test-device", byteCount: 6480,
                                  sha256: nil, provenance: .unknown)
        let result = RestoreEligibilityChecker.eligibility(
            for: change, record: record, current: document, layout: CoreModuleFixtures.layout)
        if case .restorable = result {
            XCTFail("A backup with unknown provenance must never be silently applied")
        }
    }

    // MARK: - Restore preview

    func testPreviewESIMPairSplitIsReview() throws {
        let document = try CoreModuleFixtures.document()
        // Only one half of the eSIM pair: restoring it alone would
        // leave the flags inconsistent, so it demotes to review.
        let change = makeChange(key: DeviceCacheOptions.greenTeaKey, layer: .cacheData,
                                original: .bool(true), new: .bool(false),
                                provenance: .preModification, verified: true)
        let preview = RestorePreviewBuilder.build(
            changes: [change], records: [:], current: document, layout: CoreModuleFixtures.layout)
        XCTAssertEqual(preview.items.count, 1)
        XCTAssertEqual(preview.items[0].risk, .review)
        XCTAssertFalse(preview.items[0].autoRestorable)
        XCTAssertFalse(preview.items[0].conflicts.isEmpty)
        XCTAssertFalse(preview.canAutoRestoreAll)
        XCTAssertEqual(preview.reviewCount, 1)
    }

    func testPreviewRegionSplitIsReview() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(key: GestaltKeys.regionCode, layer: .cacheExtra,
                                original: .string("CH"), new: .string("LL"),
                                provenance: .preModification, verified: true)
        let preview = RestorePreviewBuilder.build(
            changes: [change], records: [:], current: document, layout: CoreModuleFixtures.layout)
        XCTAssertEqual(preview.items[0].risk, .review,
                       "Restoring only the region code leaves the sales-region suffix inconsistent")
        XCTAssertFalse(preview.items[0].conflicts.isEmpty)
    }

    func testPreviewWholeSetRestorable() throws {
        let document = try CoreModuleFixtures.document()
        let greenTea = makeChange(key: DeviceCacheOptions.greenTeaKey, layer: .cacheData,
                                  original: .bool(true), new: .bool(false),
                                  provenance: .preModification, verified: true)
        let notGreenTea = makeChange(key: DeviceCacheOptions.notGreenTeaKey, layer: .cacheData,
                                     original: .bool(false), new: .bool(true),
                                     provenance: .preModification, verified: true)
        let preview = RestorePreviewBuilder.build(
            changes: [greenTea, notGreenTea], records: [:], current: document,
            layout: CoreModuleFixtures.layout)
        XCTAssertTrue(preview.canAutoRestoreAll, "The whole eSIM pair restores together")
        XCTAssertTrue(preview.items.allSatisfy { $0.risk == .low })
        XCTAssertTrue(preview.hasReliableBackup)
        XCTAssertNil(preview.notice)
    }

    func testPreviewNoReliableBackupNotice() throws {
        let document = try CoreModuleFixtures.document()
        let change = makeChange(provenance: .firstRead, verified: true)
        let preview = RestorePreviewBuilder.build(
            changes: [change], records: [:], current: document, layout: CoreModuleFixtures.layout)
        XCTAssertFalse(preview.hasReliableBackup)
        XCTAssertNotNil(preview.notice, "With no reliable backup the preview must say a precise restore cannot be guaranteed")
        XCTAssertEqual(preview.items[0].risk, .blocked)
    }

    // MARK: - Timeline

    func testTimelineStatuses() throws {
        // Snapshot: region CH. Current: region LL (changed).
        let snapshot = try CoreModuleFixtures.document()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        // Recorded change 1: region CH -> LL (still in effect).
        let pending = makeChange(key: GestaltKeys.regionCode, original: .string("CH"), new: .string("LL"))
        // Recorded change 2: a key already restored (current == original).
        let restored = makeChange(key: "XNCjqOupLM/S8fNyxRNQTA", original: .absent, new: .bool(true))
        let entries = RestoreIntelligence.timeline(
            records: [pending, restored], snapshot: snapshot, current: current,
            layout: CoreModuleFixtures.layout)
        let pendingEntry = entries.first { $0.key == GestaltKeys.regionCode }
        XCTAssertEqual(pendingEntry?.status, .pending, "Current LL matches the recorded new value")
        XCTAssertTrue(pendingEntry?.isRecordedOperation == true)
        let restoredEntry = entries.first { $0.key == "XNCjqOupLM/S8fNyxRNQTA" }
        XCTAssertEqual(restoredEntry?.status, .restored,
                       "Current absent matches the recorded original")
    }

    func testTimelineDetectedDifferenceIsFirstRead() throws {
        // No recorded operation: the snapshot-vs-current difference is
        // detected, and its original is the first-recorded value —
        // never a factory claim.
        let snapshot = try CoreModuleFixtures.document()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let entries = RestoreIntelligence.timeline(
            records: [], snapshot: snapshot, current: current,
            layout: CoreModuleFixtures.layout)
        let entry = entries.first { $0.key == GestaltKeys.regionCode }
        XCTAssertNotNil(entry, "The snapshot-vs-current difference must be detected")
        XCTAssertEqual(entry?.original, .string("CH"))
        XCTAssertEqual(entry?.current, .string("LL"))
        XCTAssertEqual(entry?.provenance, .firstRead)
        XCTAssertEqual(entry?.provenanceLabel, L("First-recorded value"))
        XCTAssertFalse(entry?.isRecordedOperation == true)
        XCTAssertEqual(entry?.status, .pending)
    }

    func testTimelineWithoutSnapshotClaimsNothing() throws {
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let entries = RestoreIntelligence.timeline(
            records: [], snapshot: nil, current: current, layout: CoreModuleFixtures.layout)
        XCTAssertTrue(entries.isEmpty,
                      "Without a snapshot there is no recorded original to compare against, so nothing is claimed")
    }

    // MARK: - Backup verification

    func testBackupVerificationNotFound() throws {
        let record = BackupRecord(id: UUID(), date: Date(), reason: "test", source: .device,
                                  deviceID: "test-device", byteCount: 6480,
                                  sha256: nil, provenance: .verifiedFactory)
        let results = RestoreIntelligence.verifyBackups([record], against: nil)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .notFound,
                       "A backup with no file on disk must report not-found, never verified")
    }

    func testProvenanceLabelsNeverClaimFactory() {
        XCTAssertEqual(RestoreIntelligence.provenanceLabel(for: .firstRead), L("First-recorded value"))
        XCTAssertNotEqual(RestoreIntelligence.provenanceLabel(for: .firstRead), L("Verified factory backup"))
        XCTAssertEqual(RestoreIntelligence.provenanceLabel(for: .verifiedFactory), L("Verified factory backup"))
        XCTAssertEqual(RestoreIntelligence.provenanceLabel(for: .unknown), L("Unknown source"))
    }
}
