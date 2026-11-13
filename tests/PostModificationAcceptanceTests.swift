// SPDX-License-Identifier: GPL-3.0-only
// Tests for Post-Modification Auto-Acceptance (修改后自动验收):
// reverted-field listing (the known region case), accepted fields,
// file-vs-live distinction, unreadable fields, and no claims
// without a post-restart re-read.
import Foundation
import XCTest
@testable import GestaltX

final class PostModificationAcceptanceTests: XCTestCase {
    /// No post-restart document: every item is not re-read, nothing
    /// is claimed accepted, and no record is a restart-verified
    /// candidate.
    func testNoPostRestartDocumentMeansNotReRead() {
        let records = [regionRecord(), esimGreenTeaRecord()]
        let report = PostModificationAcceptance.accept(records: records, current: nil)
        XCTAssertEqual(report.notReReadCount, 2)
        XCTAssertEqual(report.acceptedCount, 0)
        XCTAssertTrue(report.restartVerifiedCandidateIDs.isEmpty)
        XCTAssertTrue(report.items.allSatisfy { $0.outcome == .notReRead })
    }

    /// Region staged CH → LL and still LL after the restart: accepted.
    func testAcceptedRegionChange() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let report = PostModificationAcceptance.accept(
            records: [record], current: current, restartConfirmed: true)
        XCTAssertEqual(report.acceptedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .accepted)
        XCTAssertEqual(report.restartVerifiedCandidateIDs, [record.id])
    }

    /// The known region case: region staged CH → LL, but the
    /// post-restart file reads CH again — reverted, and the key is
    /// listed in `revertedKeys`.
    func testRevertedRegionChange() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document()
        let report = PostModificationAcceptance.accept(
            records: [record], current: current, restartConfirmed: true)
        XCTAssertEqual(report.revertedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .reverted)
        XCTAssertEqual(report.revertedKeys, [GestaltKeys.regionCode])
        XCTAssertTrue(report.restartVerifiedCandidateIDs.isEmpty,
                      "A reverted record is never a restart-verified candidate")
    }

    /// A field that holds a third value — neither the target nor the
    /// original — is reported as changed, not accepted or reverted.
    func testChangedToSomethingElse() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "JP"])
        let report = PostModificationAcceptance.accept(records: [record], current: current)
        XCTAssertEqual(report.changedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .changed)
    }

    /// The eSIM pair staged and still staged after the restart:
    /// both slots accepted.
    func testESIMPairAccepted() throws {
        let greenTea = esimGreenTeaRecord()
        let notGreenTea = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "esim", key: DeviceCacheOptions.notGreenTeaKey,
            layer: .cacheData, original: .bool(false), new: .bool(true),
            backupProvenance: .preModification, verified: true)
        let current = try CoreModuleFixtures.document(greenTea: false, notGreenTea: true)
        let report = PostModificationAcceptance.accept(
            records: [greenTea, notGreenTea], current: current, restartConfirmed: true)
        XCTAssertEqual(report.acceptedCount, 2)
        XCTAssertEqual(Set(report.restartVerifiedCandidateIDs), [greenTea.id, notGreenTea.id])
    }

    /// A post-restart document whose layout cannot resolve leaves
    /// CacheData items unreadable, while CacheExtra items are still
    /// read — the report never guesses a slot value.
    func testUnreadableCacheDataWithoutLayout() throws {
        let records = [regionRecord(), esimGreenTeaRecord()]
        let current = try documentWithUnknownLayout()
        let report = PostModificationAcceptance.accept(records: records, current: current)
        let region = report.items.first { $0.key == GestaltKeys.regionCode }
        let greenTea = report.items.first { $0.key == DeviceCacheOptions.greenTeaKey }
        XCTAssertEqual(region?.outcome, .reverted,
                       "The region key still reads from CacheExtra")
        XCTAssertEqual(greenTea?.outcome, .unreadable,
                       "The eSIM slot cannot be read without a layout")
        XCTAssertEqual(report.unreadableCount, 1)
    }

    /// File vs live: the file holds the staged LL, but the live
    /// probe reports CH — the item is file-accepted and the live
    /// disagreement is reported, never hidden.
    func testFileVsLiveDistinction() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let disagreeing = PostModificationAcceptance.accept(
            records: [record], current: current,
            liveValues: [GestaltKeys.regionCode: .string("CH")])
        XCTAssertEqual(disagreeing.items.first?.outcome, .accepted,
                       "The file holds the staged value")
        XCTAssertEqual(disagreeing.items.first?.liveAgrees, false,
                       "The live probe disagrees with the staged value")
        let agreeing = PostModificationAcceptance.accept(
            records: [record], current: current,
            liveValues: [GestaltKeys.regionCode: .string("LL")])
        XCTAssertEqual(agreeing.items.first?.liveAgrees, true)
    }

    /// The summary says plainly when the device was not confirmed
    /// restarted: file values alone say nothing about whether the
    /// system took the change.
    func testRestartConfirmedAffectsSummary() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let unconfirmed = PostModificationAcceptance.accept(
            records: [record], current: current, restartConfirmed: false)
        let confirmed = PostModificationAcceptance.accept(
            records: [record], current: current, restartConfirmed: true)
        XCTAssertTrue(unconfirmed.summary.contains("not confirmed restarted"),
                      "Without a confirmed restart the summary must say so, got: \(unconfirmed.summary)")
        XCTAssertFalse(confirmed.summary.contains("not confirmed restarted"))
        XCTAssertEqual(unconfirmed.acceptedCount, confirmed.acceptedCount,
                       "The counts are the same; only the claim differs")
    }

    // MARK: - Helpers

    /// Region staged CH → LL.
    private func regionRecord() -> RecordedChange {
        RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "regionCode", key: GestaltKeys.regionCode,
            layer: .cacheExtra, original: .string("CH"), new: .string("LL"),
            backupProvenance: .preModification, verified: true)
    }

    /// eSIM green-tea staged true → false.
    private func esimGreenTeaRecord() -> RecordedChange {
        RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "esim", key: DeviceCacheOptions.greenTeaKey,
            layer: .cacheData, original: .bool(true), new: .bool(false),
            backupProvenance: .preModification, verified: true)
    }

    /// A document with a CacheUUID no known layout matches, so the
    /// layout cannot resolve.
    private func documentWithUnknownLayout() throws -> GestaltDocument {
        try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": "00000000-0000-0000-0000-000000000000",
            "CacheData": CoreModuleFixtures.cacheData(greenTea: true, notGreenTea: false, wapi: true),
            "CacheExtra": [GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
    }
}
