// SPDX-License-Identifier: GPL-3.0-only
// Tests for HomeSorting (P1.6): the stable sorting rules for
// presets, restore history, and modified fields. Each rule is
// stated by a test, not just a comment.
import Foundation
import XCTest
@testable import GestaltX

final class HomeSortingTests: XCTestCase {
    // MARK: - Fixtures

    private func preset(
        featureID: String,
        chineseName: String,
        riskLevel: CapabilityRiskLevel,
        category: PresetCategory = .intelligence
    ) -> PresetEntry {
        PresetEntry(
            featureID: featureID,
            kind: .capability,
            category: category,
            chineseName: chineseName,
            englishTitle: featureID,
            chineseDescription: "",
            scope: .unknown(reason: "test"),
            scopeNote: "",
            minSystem: .unknown(reason: "test"),
            riskLevel: riskLevel,
            riskReason: "",
            restoreMethod: "",
            evidence: [],
            memberIDs: [],
            keys: [],
            underlyingKeyOrSlot: "",
            dependencies: [],
            conflicts: []
        )
    }

    private func timelineEntry(id: UUID, date: Date, featureID: String = "ai") -> RestoreTimelineEntry {
        RestoreTimelineEntry(
            id: id,
            date: date,
            featureID: featureID,
            key: featureID,
            title: featureID,
            layer: .cacheExtra,
            original: .bool(false),
            current: .bool(true),
            target: .bool(true),
            provenance: .firstRead,
            provenanceLabel: "first recorded value",
            status: .pending,
            restartVerified: false,
            isRecordedOperation: true
        )
    }

    private func modifiedRow(key: String) -> ModifiedValueRow {
        ModifiedValueRow(
            key: key,
            title: key,
            originalText: "0",
            currentText: "1",
            wasAbsent: false
        )
    }

    /// The CacheExtra key of one AI capability, from the catalog.
    private func aiKey(for featureID: String) -> String {
        guard let capability = Capability.all.first(where: { $0.id == featureID }) else {
            XCTFail("AI capability \(featureID) missing from the catalog")
            return ""
        }
        XCTAssertEqual(capability.keys.count, 1, "\(featureID) must have exactly one key")
        return capability.keys[0]
    }

    // MARK: - One-tap order (the single source of truth)

    func testOneTapFeatureOrderMatchesProposal() {
        // The sorting rule and the one-tap proposal must stay the
        // same list: if the proposal gains or drops a field, this
        // test fails and the sort order is revisited deliberately.
        XCTAssertEqual(HomeSorting.oneTapFeatureOrder, SafePatchProposal.oneTap().featureIDs)
        XCTAssertEqual(HomeSorting.oneTapFeatureOrder.first, FeatureEligibilityEvaluator.esimFeatureID)
        XCTAssertEqual(HomeSorting.oneTapFeatureOrder[1], FeatureEligibilityEvaluator.regionCodeFeatureID)
        XCTAssertEqual(
            Array(HomeSorting.oneTapFeatureOrder.dropFirst(2)),
            ChinaUnlock.aiCapabilityIDs
        )
    }

    // MARK: - Presets

    func testPresetsCatalogOrderKeepsInputOrder() {
        let entries = [
            preset(featureID: "b", chineseName: "乙", riskLevel: .low),
            preset(featureID: "a", chineseName: "甲", riskLevel: .high),
        ]
        XCTAssertEqual(
            HomeSorting.sortPresets(entries, by: .catalog).map(\.featureID),
            ["b", "a"]
        )
    }

    func testPresetsNameSortBreaksTiesByFeatureID() {
        let entries = [
            preset(featureID: "b", chineseName: "相同", riskLevel: .low),
            preset(featureID: "a", chineseName: "相同", riskLevel: .low),
            preset(featureID: "c", chineseName: "甲", riskLevel: .high),
        ]
        // "甲" sorts before "相同"; the two entries sharing a name
        // are ordered by feature id.
        XCTAssertEqual(
            HomeSorting.sortPresets(entries, by: .name).map(\.featureID),
            ["c", "a", "b"]
        )
    }

    func testPresetsRiskSortHighestFirstBreaksTiesByFeatureID() {
        let entries = [
            preset(featureID: "low-one", chineseName: "低", riskLevel: .low),
            preset(featureID: "high-b", chineseName: "高乙", riskLevel: .high),
            preset(featureID: "medium", chineseName: "中", riskLevel: .medium),
            preset(featureID: "high-a", chineseName: "高甲", riskLevel: .high),
        ]
        XCTAssertEqual(
            HomeSorting.sortPresets(entries, by: .risk).map(\.featureID),
            ["high-a", "high-b", "medium", "low-one"]
        )
    }

    // MARK: - Restore history

    func testHistorySortsNewestFirst() {
        let older = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: Date(timeIntervalSince1970: 100))
        let newer = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: Date(timeIntervalSince1970: 200))
        let newest = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, date: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(
            HomeSorting.sortHistory([older, newest, newer]).map(\.id),
            [newest.id, newer.id, older.id]
        )
    }

    func testHistoryEqualDatesKeepInputOrder() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let first = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: sameDate)
        let second = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: sameDate)
        let third = timelineEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, date: sameDate)
        XCTAssertEqual(
            HomeSorting.sortHistory([third, first, second]).map(\.id),
            [third.id, first.id, second.id]
        )
    }

    // MARK: - Modified fields

    func testModifiedValuesFollowOneTapOrder() {
        let aiKeys = ChinaUnlock.aiCapabilityIDs.map { aiKey(for: $0) }
        let shuffled = [
            modifiedRow(key: aiKeys[5]),
            modifiedRow(key: "esim-not-green-tea"),
            modifiedRow(key: aiKeys[0]),
            modifiedRow(key: "esim-green-tea"),
            modifiedRow(key: aiKeys[3]),
            modifiedRow(key: aiKeys[1]),
            modifiedRow(key: aiKeys[4]),
            modifiedRow(key: aiKeys[2]),
        ]
        let expected = ["esim-green-tea", "esim-not-green-tea"] + aiKeys
        XCTAssertEqual(HomeSorting.sortModifiedValues(shuffled).map(\.key), expected)
    }

    func testModifiedValuesNonOneTapFieldsSortAfterAlphabetically() {
        let rows = [
            modifiedRow(key: "zzz-custom"),
            modifiedRow(key: aiKey(for: "ai")),
            modifiedRow(key: "wapi"),
            modifiedRow(key: "aaa-custom"),
        ]
        XCTAssertEqual(
            HomeSorting.sortModifiedValues(rows).map(\.key),
            [aiKey(for: "ai"), "aaa-custom", "wapi", "zzz-custom"]
        )
    }
}
