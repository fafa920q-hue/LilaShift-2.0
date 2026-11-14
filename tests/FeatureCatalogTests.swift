// SPDX-License-Identifier: GPL-3.0-only
// Tests for the unified feature catalog (Phase D + E): the catalog
// contents and category mapping, search and filters, the one
// ordering rule (including its equivalence with the catalog card's
// ordering), hide / restore-defaults / recent use, the versioned
// settings store, and the eight home sections.
import Foundation
import XCTest
@testable import GestaltX

final class FeatureCatalogTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeatureCatalogTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func item(
        id: String,
        category: FeatureCatalogCategory = .appleIntelligence,
        chineseName: String = "测试",
        riskLevel: CapabilityRiskLevel? = .low,
        categorySortRank: Double = 2
    ) -> FeatureCatalogItem {
        FeatureCatalogItem(
            id: id, kind: .preset, category: category,
            chineseName: chineseName, englishTitle: id,
            chineseDescription: "", riskLevel: riskLevel,
            destination: .unlock, symbol: "sparkles",
            categorySortRank: categorySortRank)
    }

    private func pageItem(id: String, category: FeatureCatalogCategory) -> FeatureCatalogItem {
        FeatureCatalogItem(
            id: id, kind: .page, category: category,
            chineseName: id, englishTitle: id,
            chineseDescription: "", riskLevel: nil,
            destination: .diagnostics, symbol: "stethoscope",
            categorySortRank: category.pageSortRank)
    }

    private func ordered(
        _ items: [FeatureCatalogItem],
        by sort: CatalogSort = .byCategory,
        favoritesFirst: Bool = false,
        favoriteIDs: Set<String> = [],
        customOrder: [String]? = nil,
        recentIDs: [String] = []
    ) -> [String] {
        HomeSorting.sortCatalogItems(
            items, by: sort, favoritesFirst: favoritesFirst,
            favoriteIDs: favoriteIDs, customOrder: customOrder,
            recentIDs: recentIDs).map(\.id)
    }

    // MARK: - Contents and mapping

    func testCatalogCounts() {
        XCTAssertEqual(PresetCatalog.all.count, 40)
        XCTAssertEqual(FeatureCatalog.presetItems.count, 40)
        XCTAssertEqual(FeatureCatalog.pageItems.count, 13)
        XCTAssertEqual(FeatureCatalog.allItems.count, 53)
    }

    func testCatalogHasNoDuplicateIDsAndCoversEveryPreset() {
        let ids = FeatureCatalog.allItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Catalog ids must be unique")
        let presetIDs = Set(FeatureCatalog.presetItems.map(\.id))
        XCTAssertEqual(presetIDs, Set(PresetCatalog.all.map(\.featureID)))
    }

    func testCatalogCategoryCounts() {
        let counts = Dictionary(grouping: FeatureCatalog.allItems, by: \.category)
            .mapValues(\.count)
        XCTAssertEqual(counts[.smartUnlock], 1)
        XCTAssertEqual(counts[.appleIntelligence], 8)
        XCTAssertEqual(counts[.esimRegion], 4)
        XCTAssertEqual(counts[.screenLock], 11)
        XCTAssertEqual(counts[.systemSettings], 11)
        XCTAssertEqual(counts[.personalization], 1)
        XCTAssertEqual(counts[.launchArtwork], 1)
        XCTAssertEqual(counts[.deviceDiagnostics], 8)
        XCTAssertEqual(counts[.modifiedRecords], 1)
        XCTAssertEqual(counts[.backupRestore], 2)
        XCTAssertEqual(counts[.advancedTools], 5)
        XCTAssertEqual(FeatureCatalogCategory.allCases.count, 11)
    }

    func testCategoryMappingUsesFeatureIDBeforePresetCategory() {
        func category(of featureID: String) -> FeatureCatalogCategory {
            guard let entry = PresetCatalog.entry(for: featureID) else {
                XCTFail("Missing catalog entry \(featureID)")
                return .advancedTools
            }
            return FeatureCatalog.category(for: entry)
        }
        XCTAssertEqual(category(of: "esim"), .esimRegion)
        XCTAssertEqual(category(of: "regionCode"), .esimRegion)
        XCTAssertEqual(category(of: "wapi"), .esimRegion)
        XCTAssertEqual(category(of: "modelNumber"), .advancedTools)
        XCTAssertEqual(category(of: "preset.oneTap"), .smartUnlock)
        XCTAssertEqual(category(of: "preset.aiOnly"), .appleIntelligence)
        XCTAssertEqual(category(of: "preset.esimRegion"), .esimRegion)
        XCTAssertEqual(category(of: "ai"), .appleIntelligence)
        XCTAssertEqual(category(of: "dynamicIsland"), .screenLock)
        XCTAssertEqual(category(of: "storage"), .advancedTools)
        XCTAssertEqual(category(of: "pencil"), .systemSettings)
    }

    func testEveryCategoryHasAtLeastOneItem() {
        for category in FeatureCatalogCategory.allCases {
            XCTAssertFalse(
                FeatureCatalog.allItems.filter { $0.category == category }.isEmpty,
                "Category \(category) must have at least one item")
        }
    }

    func testEveryItemHasChineseDescription() {
        for item in FeatureCatalog.allItems {
            XCTAssertFalse(item.chineseName.isEmpty, "Missing name for \(item.id)")
            XCTAssertFalse(item.chineseDescription.isEmpty, "Missing description for \(item.id)")
        }
    }

    // MARK: - Search and filter

    func testSearchByChineseNameAndID() {
        XCTAssertEqual(FeatureCatalog.search("音频智能").map(\.id), ["audioIntelligence"])
        XCTAssertEqual(FeatureCatalog.search("page.healthScore").map(\.id), ["page.healthScore"])
        XCTAssertEqual(FeatureCatalog.search("").count, FeatureCatalog.allItems.count)
        XCTAssertEqual(FeatureCatalog.search("   ").count, FeatureCatalog.allItems.count)
    }

    func testSearchHasNoFalsePositives() {
        XCTAssertTrue(FeatureCatalog.search("不存在的功能-zzz").isEmpty)
    }

    func testFilterByCategoryAndRisk() {
        XCTAssertEqual(
            FeatureCatalog.filtered(FeatureCatalog.allItems, category: .screenLock).count, 11)
        XCTAssertEqual(
            FeatureCatalog.filtered(FeatureCatalog.allItems, category: .deviceDiagnostics).count, 8)
        // A risk filter excludes page items: they carry no risk.
        let high = FeatureCatalog.filtered(FeatureCatalog.allItems, riskLevel: .high)
        XCTAssertFalse(high.isEmpty)
        XCTAssertTrue(high.allSatisfy { $0.kind == .preset && $0.riskLevel == .high })
        XCTAssertEqual(
            FeatureCatalog.filtered(FeatureCatalog.allItems, riskLevel: .high).count,
            PresetCatalog.filtered(PresetCatalog.all, riskLevel: .high).count)
    }

    // MARK: - The one ordering rule

    func testOrderingMatchesCatalogCardWithNoCustomization() {
        // With no favorites, no custom order and no recent use, the
        // unified ordering must be exactly the catalog card's
        // ordering for preset-only input, for every sort.
        for sort in CatalogSort.allCases {
            let expected = PersonalizationCenter.sortedEntries(
                PresetCatalog.all, by: sort,
                favoriteIDs: [], favoritesFirst: false).map(\.featureID)
            let actual = ordered(FeatureCatalog.presetItems, by: sort)
            XCTAssertEqual(actual, expected, "Sort \(sort) must match the catalog card")
        }
    }

    func testFavoritesFirstKeepsSortOrderWithinGroups() {
        // Names sort by localizedStandardCompare (pinyin order):
        // 丙 (bǐng) < 甲 (jiǎ) < 乙 (yǐ).
        let items = [
            item(id: "b", chineseName: "乙"),
            item(id: "a", chineseName: "甲"),
            item(id: "c", chineseName: "丙"),
        ]
        XCTAssertEqual(
            ordered(items, by: .byName, favoritesFirst: true, favoriteIDs: ["c", "a"]),
            ["c", "a", "b"])
    }

    func testCustomOrderWinsAndUnlistedItemsAppendInSortOrder() {
        // Unlisted items sort by name (pinyin: 安 ān < 陈 chén).
        let items = [
            item(id: "b", chineseName: "白"),
            item(id: "a", chineseName: "安"),
            item(id: "c", chineseName: "陈"),
            item(id: "d", chineseName: "丁"),
        ]
        XCTAssertEqual(
            ordered(items, by: .byName, customOrder: ["d", "b", "unknown-id"]),
            ["d", "b", "a", "c"])
    }

    func testRecentUseIsMostRecentFirst() {
        let items = [
            item(id: "a", chineseName: "甲"),
            item(id: "b", chineseName: "乙"),
            item(id: "c", chineseName: "丙"),
        ]
        XCTAssertEqual(
            ordered(items, by: .byName, recentIDs: ["c", "a"]),
            ["c", "a", "b"])
    }

    func testCustomOrderBeatsRecentUse() {
        let items = [
            item(id: "a", chineseName: "甲"),
            item(id: "b", chineseName: "乙"),
        ]
        XCTAssertEqual(
            ordered(items, by: .byName, customOrder: ["b", "a"], recentIDs: ["a", "b"]),
            ["b", "a"])
    }

    func testRiskSortPutsPagesLast() {
        // Pages carry no risk, so they sort as low; among equal
        // risk the stable sort keeps input order, so the page
        // (first in the input) comes before the low preset.
        let items = [
            pageItem(id: "page.x", category: .deviceDiagnostics),
            item(id: "high", riskLevel: .high),
            item(id: "low", riskLevel: .low),
        ]
        XCTAssertEqual(ordered(items, by: .byRisk), ["high", "page.x", "low"])
    }

    // MARK: - Apply pipeline, hide, recent

    func testApplyHidesItemsAndCombinesSearchWithCategory() {
        var settings = FeatureCatalogSettings.defaults
        settings.hiddenIDs = ["audioIntelligence"]
        let hidden = FeatureCatalog.apply(
            FeatureCatalog.allItems, query: "", category: nil, riskLevel: nil,
            settings: settings, catalogSort: .byCategory,
            favoritesFirst: false, favoriteIDs: [])
        XCTAssertFalse(hidden.map(\.id).contains("audioIntelligence"))
        XCTAssertEqual(hidden.count, FeatureCatalog.allItems.count - 1)

        let searched = FeatureCatalog.apply(
            FeatureCatalog.allItems, query: "音频智能", category: .appleIntelligence,
            riskLevel: nil, settings: .defaults, catalogSort: .byCategory,
            favoritesFirst: false, favoriteIDs: [])
        XCTAssertEqual(searched.map(\.id), ["audioIntelligence"])
    }

    func testRecordingUsePrependsDedupesCapsAndIgnoresUnknown() {
        var settings = FeatureCatalogSettings.defaults
        settings = FeatureCatalog.recordingUse("ai", in: settings)
        settings = FeatureCatalog.recordingUse("esim", in: settings)
        settings = FeatureCatalog.recordingUse("ai", in: settings)
        XCTAssertEqual(settings.recentIDs, ["ai", "esim"])
        settings = FeatureCatalog.recordingUse("no-such-feature", in: settings)
        XCTAssertEqual(settings.recentIDs, ["ai", "esim"])
        for id in FeatureCatalog.allItems.map(\.id) {
            settings = FeatureCatalog.recordingUse(id, in: settings)
        }
        XCTAssertEqual(settings.recentIDs.count, FeatureCatalogSettings.maxRecentCount)
        XCTAssertEqual(settings.recentIDs.first, FeatureCatalog.allItems.last?.id)
    }

    func testRestoreDefaultsClearsCustomOrderHiddenAndRecent() {
        let changed = FeatureCatalogSettings(
            customOrder: ["ai", "esim"], hiddenIDs: ["ai"], recentIDs: ["esim"])
        XCTAssertNotEqual(changed, .defaults)
        XCTAssertEqual(FeatureCatalogSettings.defaults.customOrder, nil)
        XCTAssertTrue(FeatureCatalogSettings.defaults.hiddenIDs.isEmpty)
        XCTAssertTrue(FeatureCatalogSettings.defaults.recentIDs.isEmpty)
    }

    // MARK: - Settings store

    func testSettingsDefaults() {
        XCTAssertNil(FeatureCatalogSettings.defaults.customOrder)
        XCTAssertTrue(FeatureCatalogSettings.defaults.hiddenIDs.isEmpty)
        XCTAssertTrue(FeatureCatalogSettings.defaults.recentIDs.isEmpty)
    }

    func testSettingsSaveLoadRoundTrip() throws {
        let directory = try tempDirectory()
        let store = FeatureCatalogSettingsStore(directory: directory, deviceID: "test-device")
        XCTAssertEqual(store.load().settings, .defaults)
        XCTAssertNil(store.load().error)
        let changed = FeatureCatalogSettings(
            customOrder: ["esim", "ai"], hiddenIDs: ["storage"], recentIDs: ["ai"])
        try store.save(changed)
        XCTAssertEqual(store.load().settings, changed)
        XCTAssertNil(store.load().error)
    }

    func testSettingsLoadCorruptFileIsDefaultsWithError() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(FeatureCatalogSettingsStore.fileName)
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let loaded = FeatureCatalogSettingsStore(directory: directory, deviceID: "test-device").load()
        XCTAssertEqual(loaded.settings, .defaults)
        XCTAssertNotNil(loaded.error)
    }

    func testSettingsLoadNewerFormatAndForeignDeviceRefused() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(FeatureCatalogSettingsStore.fileName)
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 99, deviceID: "test-device",
                            records: [FeatureCatalogSettings.defaults]),
            to: fileURL)
        let newer = FeatureCatalogSettingsStore(directory: directory, deviceID: "test-device").load()
        XCTAssertEqual(newer.settings, .defaults)
        XCTAssertNotNil(newer.error)

        let store = FeatureCatalogSettingsStore(directory: directory, deviceID: "test-device")
        try store.save(.defaults)
        let foreign = FeatureCatalogSettingsStore(directory: directory, deviceID: "other-device").load()
        XCTAssertEqual(foreign.settings, .defaults)
        XCTAssertNotNil(foreign.error)
    }

    // MARK: - Home sections

    func testHomeSectionsDefaultOrderIsTheEightSections() {
        XCTAssertEqual(
            HomeSectionID.resolvedSections(""),
            [.deviceOverview, .commonFeatures, .chinaUnlock,
             .appleIntelligenceEsim, .securityDiagnosis, .backupRestore,
             .presetManagement, .moreTools])
    }

    func testHomeSectionsFollowDestinationOrder() {
        XCTAssertEqual(
            HomeSectionID.resolvedSections("restore,unlock"),
            [.deviceOverview, .commonFeatures, .backupRestore,
             .chinaUnlock, .appleIntelligenceEsim,
             .securityDiagnosis, .presetManagement, .moreTools])
    }

    func testHomeSectionsIgnoreUnknownAndDuplicateDestinations() {
        let sections = HomeSectionID.resolvedSections("unlock,invalid,unlock")
        XCTAssertEqual(sections.count, 8)
        XCTAssertEqual(Set(sections.map(\.rawValue)).count, sections.count)
    }

    func testHomeSectionsHaveTitlesSubtitlesAndDestinations() {
        for section in HomeSectionID.allCases {
            XCTAssertFalse(section.title.isEmpty, "Missing title for \(section)")
            XCTAssertFalse(section.symbol.isEmpty, "Missing symbol for \(section)")
        }
        XCTAssertNil(HomeSectionID.deviceOverview.subtitle)
        XCTAssertNotNil(HomeSectionID.commonFeatures.subtitle)
        XCTAssertNil(HomeSectionID.deviceOverview.destination)
        XCTAssertNil(HomeSectionID.commonFeatures.destination)
        XCTAssertEqual(HomeSectionID.chinaUnlock.destination, .unlock)
        XCTAssertEqual(HomeSectionID.appleIntelligenceEsim.destination, .unlock)
        XCTAssertEqual(HomeSectionID.securityDiagnosis.destination, .diagnostics)
        XCTAssertEqual(HomeSectionID.backupRestore.destination, .restore)
        XCTAssertEqual(HomeSectionID.presetManagement.destination, .presets)
        XCTAssertEqual(HomeSectionID.moreTools.destination, .advanced)
    }

    func testHomeSectionCountMatchesTask() {
        XCTAssertEqual(HomeSectionID.allCases.count, 8)
    }
}
