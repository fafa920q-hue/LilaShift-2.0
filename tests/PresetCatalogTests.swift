// SPDX-License-Identifier: GPL-3.0-only
// Tests for Preset Catalog (智能预设数据库): catalog completeness
// (every preset has all fields, no entry without evidence, no
// generic risk text), search (Chinese/English/key, case-insensitive,
// no false positives), filters (category/risk/eligibility —
// unknown stays unknown), favorites (add/remove/persist/reload,
// corrupt file handled gracefully), custom combinations (validate,
// save/load, dependency check runs, applying is not connected), and
// risk hints (every entry has a risk level + specific reason).
import Foundation
import XCTest
@testable import GestaltX

final class PresetCatalogTests: XCTestCase {
    // MARK: - Catalog completeness

    /// The catalog covers every preset the app offers: the 35
    /// `CapabilityEntry` entries (33 capabilities + eSIM + region
    /// code), WAPI, the model number, and the three preset groups.
    func testCatalogEntryCount() {
        XCTAssertEqual(PresetCatalog.all.count, 40,
                       "Catalog must have 40 entries, got \(PresetCatalog.all.count)")
    }

    /// Every `CapabilityEntry` id is covered by the catalog.
    func testEveryCapabilityEntryCovered() {
        let catalogIDs = Set(PresetCatalog.all.map(\.featureID))
        for entry in CapabilityEntry.all {
            XCTAssertTrue(catalogIDs.contains(entry.id),
                          "Catalog is missing CapabilityEntry id: \(entry.id)")
        }
    }

    /// No duplicate ids in the catalog.
    func testNoDuplicateIDs() {
        let ids = PresetCatalog.all.map(\.featureID)
        XCTAssertEqual(Set(ids).count, ids.count, "Catalog has duplicate ids")
    }

    /// Every entry has all fields filled in: a Chinese name and
    /// description, a scope note, a risk reason, a restore method,
    /// an underlying key/slot description, and at least one evidence
    /// item. Groups have members and no direct keys; every other
    /// entry has keys.
    func testEveryEntryHasAllFields() {
        for entry in PresetCatalog.all {
            XCTAssertFalse(entry.chineseName.isEmpty, "\(entry.featureID): missing Chinese name")
            XCTAssertFalse(entry.englishTitle.isEmpty, "\(entry.featureID): missing English title")
            XCTAssertFalse(entry.chineseDescription.isEmpty, "\(entry.featureID): missing Chinese description")
            XCTAssertFalse(entry.scopeNote.isEmpty, "\(entry.featureID): missing scope note")
            XCTAssertFalse(entry.riskReason.isEmpty, "\(entry.featureID): missing risk reason")
            XCTAssertFalse(entry.restoreMethod.isEmpty, "\(entry.featureID): missing restore method")
            XCTAssertFalse(entry.underlyingKeyOrSlot.isEmpty, "\(entry.featureID): missing key/slot")
            XCTAssertFalse(entry.evidence.isEmpty, "\(entry.featureID): missing evidence")
            if entry.kind == .group {
                XCTAssertFalse(entry.memberIDs.isEmpty, "\(entry.featureID): group has no members")
            } else {
                XCTAssertFalse(entry.keys.isEmpty, "\(entry.featureID): missing keys")
            }
        }
    }

    /// The three groups contain exactly the members the stage paths
    /// use: one-tap stages 9 fields (2 eSIM flags + region + 6 AI)
    /// as 8 member feature IDs — the eSIM virtual feature bundles
    /// the two CacheData flags under one id — AI-only is the 6 AI
    /// keys, eSIM+region is the 2 virtual features (3 fields).
    func testGroupMembers() {
        guard let oneTap = PresetCatalog.entry(for: "preset.oneTap"),
              let aiOnly = PresetCatalog.entry(for: "preset.aiOnly"),
              let esimRegion = PresetCatalog.entry(for: "preset.esimRegion") else {
            XCTFail("Preset groups are missing from the catalog")
            return
        }
        XCTAssertEqual(oneTap.memberIDs,
                       [FeatureEligibilityEvaluator.esimFeatureID,
                        FeatureEligibilityEvaluator.regionCodeFeatureID]
                        + ChinaUnlock.aiCapabilityIDs)
        XCTAssertEqual(oneTap.memberIDs.count, 8,
                       "9 staged fields map to 8 member feature IDs: the eSIM virtual feature bundles the two CacheData flags (green-tea + not-green-tea) under one id")
        XCTAssertEqual(aiOnly.memberIDs, ChinaUnlock.aiCapabilityIDs)
        XCTAssertEqual(aiOnly.memberIDs.count, 6)
        XCTAssertEqual(esimRegion.memberIDs,
                       [FeatureEligibilityEvaluator.esimFeatureID,
                        FeatureEligibilityEvaluator.regionCodeFeatureID])
    }

    /// Risk reasons are entry-specific, never a single generic
    /// string repeated across entries: within each risk level the
    /// reasons must not all be identical.
    func testNoGenericRiskText() {
        for level in [CapabilityRiskLevel.low, .medium, .high] {
            let reasons = PresetCatalog.all
                .filter { $0.riskLevel == level }
                .map(\.riskReason)
            XCTAssertGreaterThan(Set(reasons).count, 1,
                                 "Risk level \(level) has identical risk reasons — they must be entry-specific")
        }
        // No reason may be the generic placeholder text.
        for entry in PresetCatalog.all {
            XCTAssertNotEqual(entry.riskReason, "This may be risky.")
            XCTAssertFalse(entry.riskReason.contains("100% safe"))
            XCTAssertFalse(entry.riskReason.contains("fully supported"))
        }
    }

    /// The cache-discard hypothesis is labelled a hypothesis, never
    /// presented as an observed fact.
    func testHypothesisIsLabelled() {
        let hypothesisEntries = PresetCatalog.all.filter { entry in
            entry.evidence.contains { $0.kind == .hypothesis }
        }
        XCTAssertFalse(hypothesisEntries.isEmpty, "At least one entry must carry a labelled hypothesis")
        for entry in hypothesisEntries {
            XCTAssertTrue(entry.evidence.contains { evidence in
                evidence.kind == .hypothesis && evidence.text.contains("假设")
            }, "\(entry.featureID): hypothesis evidence must say it is a hypothesis")
        }
        // The region entry carries the observed revert AND the
        // hypothesis — the two are never conflated.
        guard let region = PresetCatalog.entry(for: "regionCode") else {
            XCTFail("regionCode entry is missing")
            return
        }
        XCTAssertTrue(region.evidence.contains { $0.kind == .observed })
        XCTAssertTrue(region.evidence.contains { $0.kind == .hypothesis })
    }

    // MARK: - Search

    /// Search by Chinese name finds exactly the one entry.
    func testSearchByChineseName() {
        let results = PresetCatalog.search("音频智能")
        XCTAssertEqual(results.map(\.featureID), ["audioIntelligence"])
    }

    /// Search by English title finds exactly the one entry.
    func testSearchByEnglishTitle() {
        let results = PresetCatalog.search("Dynamic Island")
        XCTAssertEqual(results.map(\.featureID), ["dynamicIsland"])
    }

    /// Search by underlying key finds exactly the one entry.
    func testSearchByKey() {
        let results = PresetCatalog.search("rb2tKZxlj0Gm2tBmUQSLqQ")
        XCTAssertEqual(results.map(\.featureID), ["audioIntelligence"])
    }

    /// Search is case-insensitive.
    func testSearchCaseInsensitive() {
        XCTAssertEqual(PresetCatalog.search("DYNAMIC ISLAND").map(\.featureID), ["dynamicIsland"])
        XCTAssertEqual(PresetCatalog.search("dynamic island").map(\.featureID), ["dynamicIsland"])
    }

    /// Search returns nothing for a query that matches nothing —
    /// no fuzzy guessing.
    func testSearchNoFalsePositives() {
        XCTAssertTrue(PresetCatalog.search("xyz-no-such-preset").isEmpty)
        XCTAssertEqual(PresetCatalog.search("pencil").map(\.featureID), ["pencil"])
    }

    /// An empty or blank query returns the whole catalog.
    func testSearchEmptyReturnsAll() {
        XCTAssertEqual(PresetCatalog.search("").count, PresetCatalog.all.count)
        XCTAssertEqual(PresetCatalog.search("   ").count, PresetCatalog.all.count)
    }

    // MARK: - Filters

    /// Category filter counts: intelligence 9 (7 AI-family + region
    /// + model number), display 11, device 10 (8 + eSIM + WAPI),
    /// iPad 3, advanced 4, group 3.
    func testFilterByCategory() {
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .intelligence).count, 9)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .display).count, 11)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .device).count, 10)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .ipad).count, 3)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .advanced).count, 4)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, category: .group).count, 3)
    }

    /// Risk filter counts: high 17 (15 `caution: true`
    /// capabilities + modelNumber + one-tap), medium 6 (the
    /// non-caution intelligence capability "ai" + eSIM + region
    /// code + WAPI + the two medium groups), low 17.
    func testFilterByRisk() {
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, riskLevel: .high).count, 17)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, riskLevel: .medium).count, 6)
        XCTAssertEqual(PresetCatalog.filtered(PresetCatalog.all, riskLevel: .low).count, 17)
    }

    /// Eligibility filtering with no evaluations: everything is
    /// unknown, so the unknown filter returns all and the eligible
    /// filter returns none — unknown is never assumed eligible.
    func testFilterByEligibilityUnknownStaysUnknown() {
        let unknown = PresetCatalog.filtered(
            PresetCatalog.all, eligibility: .unknown, evaluations: [:])
        XCTAssertEqual(unknown.count, PresetCatalog.all.count)
        let eligible = PresetCatalog.filtered(
            PresetCatalog.all, eligibility: .eligibleToEnable, evaluations: [:])
        XCTAssertTrue(eligible.isEmpty, "No entry may be eligible without evaluations")
    }

    /// Eligibility filtering with evaluations: a capability matches
    /// its own evaluation; a group matches when any member matches.
    func testFilterByEligibilityWithEvaluations() {
        let evaluations: [String: FeatureEligibility] = [
            "ai": .eligibleToEnable,
            "dynamicIsland": .nativeSupported,
        ]
        let eligible = PresetCatalog.filtered(
            PresetCatalog.all, eligibility: .eligibleToEnable, evaluations: evaluations)
        XCTAssertEqual(Set(eligible.map(\.featureID)),
                       Set(["ai", "preset.oneTap", "preset.aiOnly"]))
        let native = PresetCatalog.filtered(
            PresetCatalog.all, eligibility: .nativeSupported, evaluations: evaluations)
        XCTAssertEqual(native.map(\.featureID), ["dynamicIsland"])
    }

    /// A group's eligibility is its first non-unknown member's
    /// eligibility, or unknown when every member is unknown.
    func testGroupEligibility() {
        guard let oneTap = PresetCatalog.entry(for: "preset.oneTap") else {
            XCTFail("oneTap group is missing")
            return
        }
        XCTAssertEqual(
            PresetCatalog.eligibility(of: oneTap, evaluations: [:]), .unknown)
        XCTAssertEqual(
            PresetCatalog.eligibility(
                of: oneTap, evaluations: ["ai": .eligibleToEnable]),
            .eligibleToEnable)
    }

    /// Favorites-first ordering keeps the catalog order inside each
    /// group and moves favorites to the front.
    func testFavoritesFirstOrdering() {
        let ordered = PresetCatalog.favoritesFirst(
            PresetCatalog.all, favoriteIDs: Set(["storage", "ai"]))
        XCTAssertEqual(ordered[0].featureID, "ai")
        XCTAssertEqual(ordered[1].featureID, "storage")
        let rest = Array(ordered.dropFirst(2))
        let originalRest = PresetCatalog.all.filter { $0.featureID != "ai" && $0.featureID != "storage" }
        XCTAssertEqual(rest.map(\.featureID), originalRest.map(\.featureID),
                       "Non-favorites must keep catalog order")
    }

    // MARK: - Favorites store

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetCatalogTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    /// Add, remove, persist and reload favorites round-trips.
    func testFavoritesAddRemovePersistReload() throws {
        let directory = try tempDirectory()
        let store = PresetFavoritesStore(directory: directory, deviceID: "test-device")
        var loaded = store.load()
        XCTAssertTrue(loaded.ids.isEmpty)
        XCTAssertNil(loaded.error)
        try store.save(["ai", "esim"])
        loaded = store.load()
        XCTAssertEqual(loaded.ids, ["ai", "esim"])
        let toggled = try store.toggle("ai")
        XCTAssertEqual(toggled, ["esim"])
        XCTAssertEqual(store.load().ids, ["esim"])
        let toggledAgain = try store.toggle("dynamicIsland")
        XCTAssertEqual(Set(toggledAgain), Set(["esim", "dynamicIsland"]))
    }

    /// A corrupt favorites file loads as empty favorites with an
    /// error — never a crash, never trusted.
    func testFavoritesCorruptFileHandledGracefully() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PresetFavoritesStore.fileName)
        try Data("garbage, not JSON".utf8).write(to: fileURL)
        let store = PresetFavoritesStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertTrue(loaded.ids.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    /// Unknown ids in a verified favorites file are dropped; known
    /// ids survive.
    func testFavoritesUnknownIDsDropped() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PresetFavoritesStore.fileName)
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 1, deviceID: "test-device",
                            records: ["ai", "no-such-id"]),
            to: fileURL)
        let store = PresetFavoritesStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertEqual(loaded.ids, ["ai"])
        XCTAssertNil(loaded.error)
    }

    /// A favorites file for another device loads as empty with an
    /// error.
    func testFavoritesDeviceMismatch() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PresetFavoritesStore.fileName)
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 1, deviceID: "other-device", records: ["ai"]),
            to: fileURL)
        let store = PresetFavoritesStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertTrue(loaded.ids.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    // MARK: - Custom combinations

    /// Validation: empty name, no members, unknown member and
    /// duplicate members are all refused; a valid combination
    /// passes.
    func testCombinationValidation() {
        XCTAssertNotNil(PresetCombinationStore.validationError(name: "", featureIDs: ["ai"]))
        XCTAssertNotNil(PresetCombinationStore.validationError(name: "   ", featureIDs: ["ai"]))
        XCTAssertNotNil(PresetCombinationStore.validationError(name: "Test", featureIDs: []))
        XCTAssertNotNil(PresetCombinationStore.validationError(name: "Test", featureIDs: ["ai", "no-such-id"]))
        XCTAssertNotNil(PresetCombinationStore.validationError(name: "Test", featureIDs: ["ai", "ai"]))
        XCTAssertNil(PresetCombinationStore.validationError(name: "Test", featureIDs: ["ai", "esim"]))
    }

    /// Save and load round-trips combinations unchanged.
    func testCombinationSaveLoadRoundTrip() throws {
        let directory = try tempDirectory()
        let store = PresetCombinationStore(directory: directory, deviceID: "test-device")
        let first = PresetCombination(id: UUID(), name: "My Set",
                                      featureIDs: ["ai", "esim"], createdAt: Date())
        let second = PresetCombination(id: UUID(), name: "Region Only",
                                       featureIDs: ["regionCode"], createdAt: Date())
        try store.save([first, second])
        let loaded = store.load()
        XCTAssertNil(loaded.error)
        XCTAssertTrue(loaded.droppedMemberIDs.isEmpty)
        XCTAssertEqual(loaded.combinations, [first, second])
    }

    /// Members that are no longer in the catalog are dropped on
    /// load and reported, so the UI can say so.
    func testCombinationLoadDropsUnknownMembers() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PresetCombinationStore.fileName)
        let combination = PresetCombination(id: UUID(), name: "Old Set",
                                            featureIDs: ["ai", "no-such-id"], createdAt: Date())
        try HistoryJournal.writeVerifiedJSON(
            HistoryEnvelope(version: 1, deviceID: "test-device", records: [combination]),
            to: fileURL)
        let store = PresetCombinationStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertNil(loaded.error)
        XCTAssertEqual(loaded.combinations.count, 1)
        XCTAssertEqual(loaded.combinations[0].featureIDs, ["ai"])
        XCTAssertEqual(loaded.droppedMemberIDs, ["no-such-id"])
    }

    /// A corrupt combinations file loads as empty with an error.
    func testCombinationCorruptFileHandledGracefully() throws {
        let directory = try tempDirectory()
        let fileURL = directory.appendingPathComponent(PresetCombinationStore.fileName)
        try Data("garbage, not JSON".utf8).write(to: fileURL)
        let store = PresetCombinationStore(directory: directory, deviceID: "test-device")
        let loaded = store.load()
        XCTAssertTrue(loaded.combinations.isEmpty)
        XCTAssertNotNil(loaded.error)
    }

    // MARK: - Combination check

    private func happyPathFixture() throws -> (DocumentSnapshot, DeviceProfile) {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        return (snapshot, profile)
    }

    /// The 9-item one-tap as a custom combination checks out: the
    /// dependency analysis is safe and the simulation can proceed.
    func testCombinationCheckOneTapSafe() throws {
        let (snapshot, profile) = try happyPathFixture()
        let combination = PresetCombination(
            id: UUID(), name: "One-Tap",
            featureIDs: SafePatchProposal.oneTap().featureIDs, createdAt: Date())
        let check = PresetCombinationChecker.check(
            combination: combination, profile: profile, snapshot: snapshot)
        XCTAssertEqual(check.analysis.verdict, .safeToStage)
        XCTAssertTrue(check.simulation.canProceed,
                      "One-tap combination must simulate cleanly; blockers: \(check.simulation.blockers)")
        XCTAssertTrue(check.canProceed)
    }

    /// With no snapshot the check is unknown and cannot proceed —
    /// dependencies cannot be checked without a document.
    func testCombinationCheckWithoutSnapshotUnknown() throws {
        let (_, profile) = try happyPathFixture()
        let combination = PresetCombination(
            id: UUID(), name: "One-Tap",
            featureIDs: SafePatchProposal.oneTap().featureIDs, createdAt: Date())
        let check = PresetCombinationChecker.check(
            combination: combination, profile: profile, snapshot: nil)
        XCTAssertEqual(check.analysis.verdict, .unknown)
        XCTAssertFalse(check.simulation.canProceed)
        XCTAssertFalse(check.canProceed)
    }

    /// siriOnDevice plus an AI capability conflicts: the check
    /// reports it and cannot proceed.
    func testCombinationCheckSiriConflict() throws {
        let (snapshot, profile) = try happyPathFixture()
        let combination = PresetCombination(
            id: UUID(), name: "Siri + AI",
            featureIDs: ["siriOnDevice", "ai"], createdAt: Date())
        let check = PresetCombinationChecker.check(
            combination: combination, profile: profile, snapshot: snapshot)
        XCTAssertEqual(check.analysis.verdict, .hasConflicts)
        XCTAssertFalse(check.canProceed)
    }

    /// The AI-only set without region is missing its prerequisite.
    func testCombinationCheckAIOnlyWithoutRegion() throws {
        let (snapshot, profile) = try happyPathFixture()
        let combination = PresetCombination(
            id: UUID(), name: "AI Only",
            featureIDs: SafePatchProposal.aiOnly().featureIDs, createdAt: Date())
        let check = PresetCombinationChecker.check(
            combination: combination, profile: profile, snapshot: snapshot)
        XCTAssertEqual(check.analysis.verdict, .missingPrerequisites)
        XCTAssertFalse(check.canProceed)
    }

    // MARK: - Risk hints

    /// Every entry has a risk level and a specific reason; the
    /// reason is never the generic placeholder.
    func testEveryEntryHasRiskLevelAndReason() {
        for entry in PresetCatalog.all {
            XCTAssertFalse(entry.riskReason.isEmpty,
                           "\(entry.featureID): missing risk reason")
            XCTAssertFalse(entry.riskReason.contains("may be risky"),
                           "\(entry.featureID): generic risk text")
        }
    }

    /// High-risk entries name their specific mechanism: the
    /// hardware-identity and boot-discard risks are spelled out
    /// where they apply.
    func testHighRiskEntriesNameTheMechanism() {
        guard let modelNumber = PresetCatalog.entry(for: "modelNumber"),
              let audio = PresetCatalog.entry(for: "audioIntelligence") else {
            XCTFail("modelNumber or audioIntelligence entry is missing")
            return
        }
        XCTAssertTrue(modelNumber.riskReason.contains("面容 ID"),
                      "modelNumber must name the Face ID risk")
        XCTAssertTrue(audio.riskReason.contains("CacheData"),
                      "audioIntelligence must name the CacheData slot duality")
    }
}
