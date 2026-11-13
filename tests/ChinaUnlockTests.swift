import Foundation
import XCTest
@testable import GestaltX

final class ChinaUnlockTests: XCTestCase {
    struct Failure: Error { let message: String }

    /// The six Apple Intelligence keys staged by China Unlock, in the same
    /// order as `ChinaUnlock.aiCapabilityIDs`:
    /// ai, audioIntelligence, personalTranslator, photosCleanUp,
    /// handwritingSynthesis, alwaysListeningSiri.
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
    /// value (2) and an Air model number.
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
    func testChinaUnlock() throws {
        // The region mode is a persisted user setting; pin the default
        // here so this test never inherits another run's opt-in Full US mode.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // No document: staging and restoring must be a no-op, never a crash,
        // and the failure must name its reason instead of failing silently.
        let empty = GestaltManager()
        XCTAssert(empty.chinaUnlockESIMLayoutError != nil,
                   "No document: the eSIM layout error names the missing read")
        XCTAssert(!empty.stageChinaUnlock(),
                   "No document: staging stops instead of staging region or AI")
        XCTAssert(empty.message?.isEmpty == false,
                   "No document: staging shows the reason")
        XCTAssert(!empty.isChinaUnlockStaged && empty.changeCount == 0,
                   "No document: nothing is staged")
        empty.restoreChinaUnlock()
        XCTAssert(!empty.isChinaUnlockStaged && !empty.isChinaUnlockedInPreview && empty.preview == nil,
                   "No document: China Unlock stages and restores nothing")

        let unsupported = try Self.fixture(cacheUUID: "unsupported-layout")
        let unsupportedSnapshot = try DocumentSnapshot(
            data: unsupported.encoded(), document: unsupported, source: .local, name: "unsupported fixture"
        )
        empty.loadSnapshotForTests(unsupportedSnapshot)
        XCTAssert(empty.previewESIMFlags == nil, "Unknown cache layout has no reliable eSIM status")
        XCTAssert(empty.chinaUnlockESIMLayoutError != nil,
                   "Unsupported layout: the eSIM layout error names the reason")
        XCTAssert(!empty.stageChinaUnlock(),
                   "Unsupported layout: staging stops the whole group")
        XCTAssert(empty.message?.isEmpty == false,
                   "Unsupported layout: staging shows the reason")
        XCTAssert(empty.changeCount == 0 && !empty.isChinaUnlockStaged,
                   "An unsupported eSIM layout does not leave region or AI changes staged")
        XCTAssert(!empty.restoreChinaUnlock(), "Unsupported layout: nothing to restore")

        let layout = MobileGestaltCacheLayout.originalProfile
        let original = try Self.fixture()
        let data = try original.encoded()
        let snapshot = DocumentSnapshot(data: data, document: original, source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaUnlockStaged && !manager.isChinaUnlockedInPreview,
                   "Fixture starts locked: eSIM restricted, region CH, AI absent")

        // One tap stages the full unlock.
        manager.stageChinaUnlock()
        XCTAssert(manager.isChinaUnlockStaged, "Staged flag is set after one tap")
        XCTAssert(manager.isChinaUnlockedInPreview, "Preview shows the full unlock")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after staging") }
        XCTAssert(DeviceCacheOptions.flags(in: preview) == .enabled,
                   "Preview enables eSIM: green-tea false, not-green-tea true")
        let before = original.root["CacheData"] as! Data
        let after = preview.root["CacheData"] as! Data
        XCTAssert(before.indices.filter { before[$0] != after[$0] } == [layout.greenTeaOffset, layout.notGreenTeaOffset].sorted(),
                   "Only the two eSIM bytes change in CacheData")
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Preview sets RegionCode to LL")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Sales-region suffixes stay CH/A")
        for key in Self.aiKeys {
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == 1,
                       "Preview enables AI key \(key)")
        }
        XCTAssert(manager.chinaUnlockAIEnabledCount == 6, "All six AI presets read as enabled")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "siriOnDevice keeps its device-specific value")
        XCTAssert((manager.choices["siriOnDevice"] ?? .keep) == .keep,
                   "siriOnDevice is never staged by China Unlock")
        XCTAssert(preview.extra[GestaltKeys.modelNumber] as? String == "A3518"
                   && manager.modelID == "keep",
                   "Model number is untouched")
        XCTAssert(manager.regionID == "keep", "Sales Region stays keep")
        // Boundary: staging touches exactly the seven CacheExtra keys of
        // the nine-item scope (region code + six AI keys) and no other
        // field, added or removed.
        let changedKeys = Set(original.extra.keys).union(preview.extra.keys).filter { key in
            let before = original.extra[key] as? NSObject
            let after = preview.extra[key] as? NSObject
            return (before?.isEqual(after) ?? (after == nil)) == false
        }
        XCTAssert(changedKeys == Set([GestaltKeys.regionCode] + Self.aiKeys),
                   "Staging changes exactly region + six AI keys, got \(changedKeys.sorted())")
        // 7 CacheExtra keys (region code + 6 AI keys) + 2 cache bytes.
        XCTAssert(manager.changeCount == 9,
                   "Staged change count is 9, got \(manager.changeCount)")

        // Staging twice is idempotent.
        manager.stageChinaUnlock()
        XCTAssert(manager.changeCount == 9, "Staging the unlock twice does not duplicate changes")

        // One-tap restore returns all three groups to their originals.
        manager.restoreChinaUnlock()
        XCTAssert(!manager.isChinaUnlockStaged && !manager.isChinaUnlockedInPreview,
                   "Restore clears the staged and unlocked state")
        XCTAssert(manager.changeCount == 0, "Restore unstages every change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        XCTAssert(DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore returns the eSIM flags to restricted")
        XCTAssert(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore returns RegionCode to CH")
        for key in Self.aiKeys {
            XCTAssert(restored.extra[key] == nil, "Restore removes AI key \(key)")
        }
        XCTAssert((restored.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "Restore preserves the device-specific Siri value")
        XCTAssert(restored.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Restore preserves the model number")

        // The unlock can be staged again after a restore.
        manager.stageChinaUnlock()
        XCTAssert(manager.isChinaUnlockStaged && manager.changeCount == 9,
                   "Unlock stages again after a restore")
    }
}
