import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the two standalone presets: the AI-only preset (six
/// Apple Intelligence keys, no eSIM or region) and the eSIM+region preset
/// (two eSIM CacheData slots + RegionCode LL, no AI keys). Both are pure
/// subsets of the 9-item one-tap unlock; the full one-tap is unchanged.
/// No device or signing is needed.
final class StandalonePresetsTests: XCTestCase {
    struct Failure: Error { let message: String }

    /// The six Apple Intelligence keys, in the same order as
    /// `ChinaUnlock.aiCapabilityIDs`: ai, audioIntelligence,
    /// personalTranslator, photosCleanUp, handwritingSynthesis,
    /// alwaysListeningSiri.
    static let aiKeys = [
        "A62OafQ85EJAiiqKn4agtg",
        "rb2tKZxlj0Gm2tBmUQSLqQ",
        "M1n2sAqf33NAOgZRGxQYBA",
        "XNCjqOupLM/S8fNyxRNQTA",
        "YgYIIViDt1kgzyIsIV61vA",
        "TusANsf9Lfe3P/9fIXXSrQ",
    ]
    static let siriKey = "K/R1GfGfCkXvEhaPS2Vrng"

    /// China-mainland fixture: eSIM restricted (green-tea on), region CH
    /// with CH/A sales suffixes, no AI keys, a device-specific Siri
    /// value (2) and an Air model number. Pass a bogus cacheUUID for an
    /// unsupported layout (the eSIM cache layout cannot be verified).
    static func fixture(cacheUUID: String? = nil) throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        let extra: [String: Any] = [
            GestaltKeys.productType: "iPhone18,1",
            GestaltKeys.regionCode: "CH",
            GestaltKeys.regionInfo: "CH/A",
            GestaltKeys.legacyRegionInfo: "CH/A",
            GestaltKeys.modelNumber: "A3518",
            siriKey: NSNumber(value: 2),
        ]
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": cacheUUID ?? layout.uuid,
            "CacheData": cache, "CacheExtra": extra,
        ], format: .binary, options: 0))
    }

    @MainActor
    func manager(for document: GestaltDocument) throws -> GestaltManager {
        let snapshot = DocumentSnapshot(data: try document.encoded(), document: document,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        return manager
    }

    @MainActor
    func testAIOnlyPreset() throws {
        // The region mode is a persisted user setting; pin the default
        // here so this test never inherits another run's opt-in Full US mode.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture()
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Fixture starts with AI absent")

        // Staging the AI-only preset changes exactly the six AI keys.
        XCTAssert(manager.stageChinaAIOnly(), "AI-only staging succeeds")
        XCTAssert(manager.isChinaAIOnlyStaged, "AI-only staged flag is set")
        XCTAssert(manager.isChinaAIOnlyApplied, "Preview shows all six AI presets enabled")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "AI-only staging is not the full one-tap: eSIM and region are not staged")
        XCTAssert(manager.changeCount == 6, "AI-only staging changes exactly 6 items, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after AI-only staging") }
        for key in Self.aiKeys {
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == 1,
                       "Preview enables AI key \(key)")
        }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "AI-only staging leaves RegionCode at CH")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "AI-only staging leaves the sales-region suffixes alone")
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .restricted,
                   "AI-only staging leaves the eSIM flags restricted")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "AI-only staging keeps the device-specific Siri value")
        XCTAssert(manager.chinaUnlockAIEnabledCount == 6, "All six AI presets read as enabled")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "AI-only staging does not stage the eSIM+region preset")

        // Staging twice is idempotent.
        manager.stageChinaAIOnly()
        XCTAssert(manager.changeCount == 6, "Staging AI-only twice does not duplicate changes")

        // Restoring the AI-only preset returns the AI keys to their originals.
        XCTAssert(manager.restoreChinaAIOnly(), "AI-only restore succeeds")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Restore clears the AI-only staged and applied state")
        XCTAssert(manager.changeCount == 0, "Restore unstages every AI change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after AI-only restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        for key in Self.aiKeys {
            XCTAssert(restored.extra[key] == nil, "Restore removes AI key \(key)")
        }
        XCTAssert(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore leaves RegionCode at CH")
        XCTAssert(try DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore leaves the eSIM flags restricted")

        // The AI-only preset can be staged again after a restore.
        manager.stageChinaAIOnly()
        XCTAssert(manager.isChinaAIOnlyStaged && manager.changeCount == 6,
                   "AI-only stages again after a restore")
    }

    @MainActor
    func testESIMRegionPreset() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture()
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "Fixture starts locked: eSIM restricted, region CH")

        // Staging the eSIM+region preset changes exactly 3 items.
        XCTAssert(manager.stageChinaESIMRegion(), "eSIM+region staging succeeds")
        XCTAssert(manager.isChinaESIMRegionStaged, "eSIM+region staged flag is set")
        XCTAssert(manager.isChinaESIMRegionApplied, "Preview shows eSIM enabled and region LL")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "eSIM+region staging is not the full one-tap: AI is not staged")
        XCTAssert(manager.changeCount == 3, "eSIM+region staging changes exactly 3 items, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after eSIM+region staging") }
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .enabled,
                   "Preview enables eSIM: green-tea false, not-green-tea true")
        let before = original.root["CacheData"] as! Data
        let after = preview.root["CacheData"] as! Data
        let layout = MobileGestaltCacheLayout.originalProfile
        XCTAssert(before.indices.filter { before[$0] != after[$0] } == [layout.greenTeaOffset, layout.notGreenTeaOffset].sorted(),
                   "Only the two eSIM bytes change in CacheData")
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Preview sets RegionCode to LL")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Sales-region suffixes stay CH/A")
        for key in Self.aiKeys {
            XCTAssert(preview.extra[key] == nil, "eSIM+region staging leaves AI key \(key) absent")
        }
        XCTAssert(manager.chinaUnlockAIEnabledCount == 0, "No AI preset reads as enabled")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "eSIM+region staging keeps the device-specific Siri value")
        XCTAssert(preview.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Model number is untouched")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "eSIM+region staging does not stage the AI-only preset")

        // Staging twice is idempotent.
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 3, "Staging eSIM+region twice does not duplicate changes")

        // Restoring the eSIM+region preset returns eSIM and region to their originals.
        XCTAssert(manager.restoreChinaESIMRegion(), "eSIM+region restore succeeds")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "Restore clears the eSIM+region staged and applied state")
        XCTAssert(manager.changeCount == 0, "Restore unstages every eSIM+region change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after eSIM+region restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        XCTAssert(try DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore returns the eSIM flags to restricted")
        XCTAssert(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore returns RegionCode to CH")
        for key in Self.aiKeys {
            XCTAssert(restored.extra[key] == nil, "Restore leaves AI key \(key) absent")
        }

        // The eSIM+region preset can be staged again after a restore.
        manager.stageChinaESIMRegion()
        XCTAssert(manager.isChinaESIMRegionStaged && manager.changeCount == 3,
                   "eSIM+region stages again after a restore")
    }

    @MainActor
    func testStandalonePresetsLayoutGating() throws {
        // Unsupported cache layout: the eSIM layout cannot be verified.
        let unsupported = try Self.fixture(cacheUUID: "unsupported-layout")
        let manager = try manager(for: unsupported)
        XCTAssert(manager.chinaUnlockESIMLayoutError != nil,
                   "Unsupported layout: the eSIM layout error names the reason")
        XCTAssert(manager.previewESIMFlags == nil, "Unknown cache layout has no reliable eSIM status")

        // The AI-only preset is NOT blocked by the eSIM layout: the six AI
        // keys are CacheExtra values and do not need the layout to resolve.
        XCTAssert(manager.stageChinaAIOnly(),
                   "AI-only staging succeeds even when the eSIM layout cannot be verified")
        XCTAssert(manager.changeCount == 6,
                   "AI-only staging on an unsupported layout changes exactly the 6 AI keys, got \(manager.changeCount)")
        XCTAssert(manager.isChinaAIOnlyStaged, "AI-only staged flag is set on an unsupported layout")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after AI-only staging") }
        for key in Self.aiKeys {
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == 1,
                       "Preview enables AI key \(key) on an unsupported layout")
        }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "AI-only staging leaves RegionCode at CH on an unsupported layout")
        manager.restoreChinaAIOnly()
        XCTAssert(manager.changeCount == 0, "AI-only restore clears the staging on an unsupported layout")

        // The eSIM+region preset IS blocked by the eSIM layout, exactly
        // like the full one-tap unlock.
        XCTAssert(!manager.stageChinaESIMRegion(),
                   "eSIM+region staging stops when the eSIM layout cannot be verified")
        XCTAssert(manager.message?.isEmpty == false,
                   "eSIM+region staging shows the reason")
        XCTAssert(manager.changeCount == 0 && !manager.isChinaESIMRegionStaged,
                   "A blocked eSIM+region staging leaves nothing staged")
        XCTAssert(!manager.restoreChinaESIMRegion(),
                   "eSIM+region restore stops when the eSIM layout cannot be verified")
    }

    @MainActor
    func testStandalonePresetsComposeIntoOneTap() throws {
        // The two subsets compose into the full 9-item one-tap: staging
        // AI-only and then eSIM+region stages exactly the 9 items, and
        // the one-tap staged flag reads true.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture()
        let manager = try manager(for: original)
        manager.stageChinaAIOnly()
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 9,
                   "Both subsets staged together change exactly 9 items, got \(manager.changeCount)")
        XCTAssert(manager.isChinaUnlockStaged,
                   "Both subsets staged together read as the full one-tap staged")
        XCTAssert(manager.isChinaUnlockedInPreview,
                   "Both subsets staged together read as unlocked in preview")
        // Restoring the full one-tap clears both subsets.
        manager.restoreChinaUnlock()
        XCTAssert(manager.changeCount == 0, "One-tap restore clears both subsets")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after one-tap restore") }
        XCTAssert(restored.matches(original), "One-tap restore returns the original document")
    }
}
