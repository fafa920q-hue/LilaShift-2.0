import Foundation

@main struct ChinaUnlockTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

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
    static func main() throws {
        // The region mode is a persisted user setting; pin the default
        // here so this test never inherits another run's opt-in Full US mode.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // No document: staging and restoring must be a no-op, never a crash,
        // and the failure must name its reason instead of failing silently.
        let empty = GestaltManager()
        try expect(empty.chinaUnlockESIMLayoutError != nil,
                   "No document: the eSIM layout error names the missing read")
        try expect(!empty.stageChinaUnlock(),
                   "No document: staging stops instead of staging region or AI")
        try expect(empty.message?.isEmpty == false,
                   "No document: staging shows the reason")
        try expect(!empty.isChinaUnlockStaged && empty.changeCount == 0,
                   "No document: nothing is staged")
        empty.restoreChinaUnlock()
        try expect(!empty.isChinaUnlockStaged && !empty.isChinaUnlockedInPreview && empty.preview == nil,
                   "No document: China Unlock stages and restores nothing")

        let unsupported = try fixture(cacheUUID: "unsupported-layout")
        let unsupportedSnapshot = try DocumentSnapshot(
            data: unsupported.encoded(), document: unsupported, source: .local, name: "unsupported fixture"
        )
        empty.loadSnapshotForTests(unsupportedSnapshot)
        try expect(empty.previewESIMFlags == nil, "Unknown cache layout has no reliable eSIM status")
        try expect(empty.chinaUnlockESIMLayoutError != nil,
                   "Unsupported layout: the eSIM layout error names the reason")
        try expect(!empty.stageChinaUnlock(),
                   "Unsupported layout: staging stops the whole group")
        try expect(empty.message?.isEmpty == false,
                   "Unsupported layout: staging shows the reason")
        try expect(empty.changeCount == 0 && !empty.isChinaUnlockStaged,
                   "An unsupported eSIM layout does not leave region or AI changes staged")
        try expect(!empty.restoreChinaUnlock(), "Unsupported layout: nothing to restore")

        let layout = MobileGestaltCacheLayout.originalProfile
        let original = try fixture()
        let data = try original.encoded()
        let snapshot = DocumentSnapshot(data: data, document: original, source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        try expect(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        try expect(!manager.isChinaUnlockStaged && !manager.isChinaUnlockedInPreview,
                   "Fixture starts locked: eSIM restricted, region CH, AI absent")

        // One tap stages the full unlock.
        manager.stageChinaUnlock()
        try expect(manager.isChinaUnlockStaged, "Staged flag is set after one tap")
        try expect(manager.isChinaUnlockedInPreview, "Preview shows the full unlock")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after staging") }
        try expect(DeviceCacheOptions.flags(in: preview) == .enabled,
                   "Preview enables eSIM: green-tea false, not-green-tea true")
        let before = original.root["CacheData"] as! Data
        let after = preview.root["CacheData"] as! Data
        try expect(before.indices.filter { before[$0] != after[$0] } == [layout.greenTeaOffset, layout.notGreenTeaOffset].sorted(),
                   "Only the two eSIM bytes change in CacheData")
        try expect(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Preview sets RegionCode to LL")
        try expect(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Sales-region suffixes stay CH/A")
        for key in aiKeys {
            try expect((preview.extra[key] as? NSNumber)?.intValue == 1,
                       "Preview enables AI key \(key)")
        }
        try expect(manager.chinaUnlockAIEnabledCount == 6, "All six AI presets read as enabled")
        try expect((preview.extra[siriKey] as? NSNumber)?.intValue == 2,
                   "siriOnDevice keeps its device-specific value")
        try expect((manager.choices["siriOnDevice"] ?? .keep) == .keep,
                   "siriOnDevice is never staged by China Unlock")
        try expect(preview.extra[GestaltKeys.modelNumber] as? String == "A3518"
                   && manager.modelID == "keep",
                   "Model number is untouched")
        try expect(manager.regionID == "keep", "Sales Region stays keep")
        // Boundary: staging touches exactly the seven CacheExtra keys of
        // the nine-item scope (region code + six AI keys) and no other
        // field, added or removed.
        let changedKeys = Set(original.extra.keys).union(preview.extra.keys).filter { key in
            let before = original.extra[key] as? NSObject
            let after = preview.extra[key] as? NSObject
            return (before?.isEqual(after) ?? (after == nil)) == false
        }
        try expect(changedKeys == Set([GestaltKeys.regionCode] + aiKeys),
                   "Staging changes exactly region + six AI keys, got \(changedKeys.sorted())")
        // 7 CacheExtra keys (region code + 6 AI keys) + 2 cache bytes.
        try expect(manager.changeCount == 9,
                   "Staged change count is 9, got \(manager.changeCount)")

        // Staging twice is idempotent.
        manager.stageChinaUnlock()
        try expect(manager.changeCount == 9, "Staging the unlock twice does not duplicate changes")

        // One-tap restore returns all three groups to their originals.
        manager.restoreChinaUnlock()
        try expect(!manager.isChinaUnlockStaged && !manager.isChinaUnlockedInPreview,
                   "Restore clears the staged and unlocked state")
        try expect(manager.changeCount == 0, "Restore unstages every change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after restore") }
        try expect(restored.matches(original), "Restored preview matches the original document")
        try expect(DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore returns the eSIM flags to restricted")
        try expect(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore returns RegionCode to CH")
        for key in aiKeys {
            try expect(restored.extra[key] == nil, "Restore removes AI key \(key)")
        }
        try expect((restored.extra[siriKey] as? NSNumber)?.intValue == 2,
                   "Restore preserves the device-specific Siri value")
        try expect(restored.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Restore preserves the model number")

        // The unlock can be staged again after a restore.
        manager.stageChinaUnlock()
        try expect(manager.isChinaUnlockStaged && manager.changeCount == 9,
                   "Unlock stages again after a restore")
        print("PASS: China Unlock stages eSIM, region LL and six AI keys, keeps sales region, Siri value and model number untouched, and restores all three groups to their originals.")
    }
}
