// SPDX-License-Identifier: GPL-3.0-only
// Tests for Personalization Center (个性化中心): custom preset
// create/edit/delete validation, save/load round-trip, corrupt /
// newer-format / foreign-device file handling, dependency check runs
// and its result is shown (applying is not connected — there is no
// apply path for a custom preset), and settings persist and take
// effect (sort order, favorites first, Tool-card visibility).
import Foundation
import XCTest
@testable import GestaltX

final class PersonalizationCenterTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalizationCenterTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func samplePreset(members: [String] = ["ai", "esim"]) -> CustomPreset {
        CustomPreset(
            id: UUID(), name: "My Preset", chineseDescription: "只开 AI 与 eSIM。",
            riskLevel: .medium, riskReason: "只改能力标记。", memberIDs: members,
            createdAt: Date(timeIntervalSince1970: 1_000_000))
    }

    private func happyPathFixture() throws -> (DocumentSnapshot, DeviceProfile) {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        return (snapshot, profile)
    }

    // MARK: - Validation

    func testValidationRejectsEmptyName() {
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "  ", description: "d", riskReason: "r", featureIDs: ["ai"]))
    }

    func testValidationRejectsNameOver32Characters() {
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: String(repeating: "a", count: 33),
            description: "d", riskReason: "r", featureIDs: ["ai"]))
    }

    func testValidationAcceptsNameOf32Characters() {
        XCTAssertNil(CustomPresetStore.validationError(
            name: String(repeating: "a", count: 32),
            description: "d", riskReason: "r", featureIDs: ["ai"]))
    }

    func testValidationRejectsEmptyDescriptionAndRiskReason() {
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "n", description: "  ", riskReason: "r", featureIDs: ["ai"]))
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "n", description: "d", riskReason: " ", featureIDs: ["ai"]))
    }

    func testValidationRejectsEmptyMembersUnknownMemberAndDuplicates() {
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "n", description: "d", riskReason: "r", featureIDs: []))
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "n", description: "d", riskReason: "r", featureIDs: ["no-such-preset"]))
        XCTAssertNotNil(CustomPresetStore.validationError(
            name: "n", description: "d", riskReason: "r", featureIDs: ["ai", "ai"]))
    }

    func testValidationAcceptsValidPreset() {
        XCTAssertNil(CustomPresetStore.validationError(
            name: "My Preset", description: "只开 AI。",
            riskReason: "只改能力标记。", featureIDs: ["ai", "esim"]))
    }

    // MARK: - Custom preset store

    func testCustomPresetSaveLoadRoundTrip() throws {
        let directory = try tempDirectory()
        let store = CustomPresetStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertTrue(loaded.presets.isEmpty)
        XCTAssertNil(loaded.error)
        let first = samplePreset()
        let second = samplePreset(members: ["regionCode"])
        try store.save([first, second])
        let reloaded = store.load()
        XCTAssertEqual(reloaded.presets, [first, second])
        XCTAssertNil(reloaded.error)
        XCTAssertTrue(reloaded.droppedMemberIDs.isEmpty)
    }

    func testCustomPresetLoadCorruptFileIsEmptyWithError() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(CustomPresetStore.fileName)
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let loaded = CustomPresetStore(directory: directory, deviceID: "test-device").load()
        XCTAssertTrue(loaded.presets.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    func testCustomPresetLoadNewerFormatRefused() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(CustomPresetStore.fileName)
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 99, deviceID: "test-device", records: [samplePreset()]),
            to: fileURL)
        let loaded = CustomPresetStore(directory: directory, deviceID: "test-device").load()
        XCTAssertTrue(loaded.presets.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    func testCustomPresetLoadForeignDeviceRefused() throws {
        let directory = try tempDirectory()
        let store = CustomPresetStore(directory: directory, deviceID: "test-device")
        try store.save([samplePreset()])
        let loaded = CustomPresetStore(directory: directory, deviceID: "other-device").load()
        XCTAssertTrue(loaded.presets.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    func testCustomPresetLoadDropsUnknownMembersAndReportsThem() throws {
        let directory = try tempDirectory()
        let store = CustomPresetStore(directory: directory, deviceID: "test-device")
        try store.save([samplePreset(members: ["ai", "gone-preset"])])
        let loaded = store.load()
        XCTAssertEqual(loaded.presets.count, 1)
        XCTAssertEqual(loaded.presets[0].memberIDs, ["ai"])
        XCTAssertEqual(loaded.droppedMemberIDs, ["gone-preset"])
    }

    func testCustomPresetLoadDropsPresetWithNoKnownMembers() throws {
        let directory = try tempDirectory()
        let store = CustomPresetStore(directory: directory, deviceID: "test-device")
        try store.save([samplePreset(members: ["gone-preset"])])
        let loaded = store.load()
        XCTAssertTrue(loaded.presets.isEmpty)
        XCTAssertEqual(loaded.droppedMemberIDs, ["gone-preset"])
    }

    // MARK: - Custom preset check (plan only)

    /// The check runs through the same tools staging uses, and the
    /// result is shown. There is no apply path for a custom preset:
    /// the preset only converts to a P3 combination for checking.
    func testCustomPresetCheckOneTapSafe() throws {
        let (snapshot, profile) = try happyPathFixture()
        let preset = samplePreset(members: SafePatchProposal.oneTap().featureIDs)
        let check = CustomPresetChecker.check(
            preset: preset, profile: profile, snapshot: snapshot)
        XCTAssertEqual(check.analysis.verdict, .safeToStage)
        XCTAssertTrue(check.simulation.canProceed,
                      "One-tap custom preset must simulate cleanly; blockers: \(check.simulation.blockers)")
        XCTAssertTrue(check.canProceed)
    }

    func testCustomPresetCheckConflictCannotProceed() throws {
        let (snapshot, profile) = try happyPathFixture()
        let preset = samplePreset(members: ["siriOnDevice", "ai"])
        let check = CustomPresetChecker.check(
            preset: preset, profile: profile, snapshot: snapshot)
        XCTAssertEqual(check.analysis.verdict, .hasConflicts)
        XCTAssertFalse(check.canProceed)
    }

    func testCustomPresetCheckWithoutSnapshotUnknown() throws {
        let (_, profile) = try happyPathFixture()
        let preset = samplePreset(members: SafePatchProposal.oneTap().featureIDs)
        let check = CustomPresetChecker.check(
            preset: preset, profile: profile, snapshot: nil)
        XCTAssertEqual(check.analysis.verdict, .unknown)
        XCTAssertFalse(check.canProceed)
    }

    func testCustomPresetConvertsToCombinationForChecking() {
        let preset = samplePreset(members: ["ai", "esim"])
        XCTAssertEqual(preset.asCombination.id, preset.id)
        XCTAssertEqual(preset.asCombination.name, preset.name)
        XCTAssertEqual(preset.asCombination.featureIDs, ["ai", "esim"])
    }

    // MARK: - Settings

    func testSettingsDefaults() {
        let settings = PersonalizationSettings.defaults
        XCTAssertEqual(settings.catalogSort, .byCategory)
        XCTAssertFalse(settings.favoritesFirst)
        XCTAssertEqual(settings.visibleToolCards, Set(PersonalizationCenter.allToolCardIDs))
        XCTAssertEqual(PersonalizationCenter.allToolCardIDs.count, 6)
    }

    func testSettingsSaveLoadRoundTrip() throws {
        let directory = try tempDirectory()
        let store = PersonalizationSettingsStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertEqual(loaded.settings, .defaults)
        XCTAssertNil(loaded.error)
        let changed = PersonalizationSettings(
            catalogSort: .byRisk, favoritesFirst: true,
            visibleToolCards: ["screenLock", "personalization"])
        try store.save(changed)
        XCTAssertEqual(store.load().settings, changed)
        XCTAssertNil(store.load().error)
    }

    func testSettingsLoadCorruptFileIsDefaultsWithError() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PersonalizationSettingsStore.fileName)
        try "not json".write(to: fileURL, atomically: true, encoding: .utf8)
        let loaded = PersonalizationSettingsStore(directory: directory, deviceID: "test-device").load()
        XCTAssertEqual(loaded.settings, .defaults)
        XCTAssertNotNil(loaded.error)
    }

    func testSettingsLoadNewerFormatAndForeignDeviceRefused() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PersonalizationSettingsStore.fileName)
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 99, deviceID: "test-device",
                            records: [PersonalizationSettings.defaults]),
            to: fileURL)
        let newer = PersonalizationSettingsStore(directory: directory, deviceID: "test-device").load()
        XCTAssertEqual(newer.settings, .defaults)
        XCTAssertNotNil(newer.error)

        let store = PersonalizationSettingsStore(directory: directory, deviceID: "test-device")
        try store.save(.defaults)
        let foreign = PersonalizationSettingsStore(directory: directory, deviceID: "other-device").load()
        XCTAssertEqual(foreign.settings, .defaults)
        XCTAssertNotNil(foreign.error)
    }

    // MARK: - Sorting takes effect

    func testSortedEntriesByName() {
        let entries = Array(PresetCatalog.all.shuffled())
        let sorted = PersonalizationCenter.sortedEntries(
            entries, by: .byName, favoriteIDs: [], favoritesFirst: false)
        let names = sorted.map(\.chineseName)
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        XCTAssertEqual(sorted.map(\.featureID).sorted(), entries.map(\.featureID).sorted())
    }

    func testSortedEntriesByRiskHighFirstStable() {
        let sorted = PersonalizationCenter.sortedEntries(
            PresetCatalog.all, by: .byRisk, favoriteIDs: [], favoritesFirst: false)
        let risks = sorted.map(\.riskLevel)
        let highEnd = risks.lastIndex(of: .high) ?? -1
        let mediumStart = risks.firstIndex(of: .medium) ?? risks.count
        let mediumEnd = risks.lastIndex(of: .medium) ?? -1
        let lowStart = risks.firstIndex(of: .low) ?? risks.count
        XCTAssertTrue(highEnd < mediumStart, "High-risk entries must come before medium-risk entries")
        XCTAssertTrue(mediumEnd < lowStart, "Medium-risk entries must come before low-risk entries")
        // Stable: entries with the same risk keep catalog order.
        for risk in [CapabilityRiskLevel.high, .medium, .low] {
            let inCatalog = PresetCatalog.all.filter { $0.riskLevel == risk }.map(\.featureID)
            let inSorted = sorted.filter { $0.riskLevel == risk }.map(\.featureID)
            XCTAssertEqual(inSorted, inCatalog, "Same-risk entries must keep catalog order")
        }
    }

    func testSortedEntriesByCategoryInCatalogOrderStable() {
        let sorted = PersonalizationCenter.sortedEntries(
            PresetCatalog.all, by: .byCategory, favoriteIDs: [], favoritesFirst: false)
        let categories = sorted.map(\.category)
        let order = PresetCategory.allCases
        var lastIndex = -1
        for category in categories {
            let index = order.firstIndex(of: category) ?? order.count
            XCTAssertGreaterThanOrEqual(index, lastIndex, "Categories must follow PresetCategory order")
            lastIndex = index
        }
        for category in PresetCategory.allCases {
            let inCatalog = PresetCatalog.all.filter { $0.category == category }.map(\.featureID)
            let inSorted = sorted.filter { $0.category == category }.map(\.featureID)
            XCTAssertEqual(inSorted, inCatalog, "Same-category entries must keep catalog order")
        }
    }

    func testSortedEntriesFavoritesFirstKeepsSortOrderWithinGroups() {
        let sorted = PersonalizationCenter.sortedEntries(
            PresetCatalog.all, by: .byName,
            favoriteIDs: ["storage", "ai"], favoritesFirst: true)
        XCTAssertEqual(sorted[0].featureID, "ai")
        XCTAssertEqual(sorted[1].featureID, "storage")
        let rest = Array(sorted.dropFirst(2))
        let restNames = rest.map(\.chineseName)
        XCTAssertEqual(restNames, restNames.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        let withoutFavorites = PersonalizationCenter.sortedEntries(
            PresetCatalog.all, by: .byName, favoriteIDs: [], favoritesFirst: false)
        XCTAssertEqual(sorted.map(\.featureID).sorted(), withoutFavorites.map(\.featureID).sorted())
    }

    // MARK: - Tool-card visibility takes effect

    func testVisibleToolCardIDsDefaultIsAllInOrder() {
        XCTAssertEqual(
            PersonalizationCenter.visibleToolCardIDs(.defaults),
            PersonalizationCenter.allToolCardIDs)
    }

    func testVisibleToolCardIDsRespectsSettingsAndIgnoresUnknownIDs() {
        let settings = PersonalizationSettings(
            catalogSort: .byName, favoritesFirst: false,
            visibleToolCards: ["personalization", "unknown-card", "screenLock"])
        XCTAssertEqual(
            PersonalizationCenter.visibleToolCardIDs(settings),
            ["screenLock", "personalization"])
    }

    func testVisibleToolCardIDsEmptyHidesAll() {
        let settings = PersonalizationSettings(
            catalogSort: .byName, favoritesFirst: false, visibleToolCards: [])
        XCTAssertTrue(PersonalizationCenter.visibleToolCardIDs(settings).isEmpty)
    }

    func testToolCardTitleUnknownIDReturnsID() {
        XCTAssertEqual(PersonalizationCenter.toolCardTitle(for: "no-such-card"), "no-such-card")
        XCTAssertEqual(PersonalizationCenter.toolCardTitle(for: "screenLock"), "Screen & Lock Screen")
    }
}
