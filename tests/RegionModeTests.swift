import Foundation

/// Offline tests for the item-5 region mode choice: the US regulatory
/// model mapping (refuses unknown models) and Full US staging/restore.
/// No device or signing is needed.
@main struct RegionModeTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    /// China-mainland fixture: region CH with CH/A suffixes, Air model
    /// number A3518 (China mainland), product type iPhone18,1.
    static func fixture(productType: String = "iPhone18,1",
                        modelNumber: String = "A3518") throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache,
            "CacheExtra": [
                GestaltKeys.productType: productType,
                GestaltKeys.regionCode: "CH",
                GestaltKeys.regionInfo: "CH/A",
                GestaltKeys.legacyRegionInfo: "CH/A",
                GestaltKeys.modelNumber: modelNumber,
            ],
        ], format: .binary, options: 0))
    }

    @MainActor
    static func main() throws {
        // Mapping table spot checks (original reg model first, then
        // product type; unknown models refused, never guessed).
        try expect(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A3718", productType: "iPhone19,3") == "A3473",
                   "A3718 (18 Pro Max China) maps to US A3473")
        try expect(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A3518", productType: "iPhone18,1") == "A3260",
                   "A3518 (Air China) maps to US A3260, not the product-type fallback A3256")
        try expect(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil, productType: "iPhone18,4") == "A3260",
                   "Product-type fallback maps iPhone18,4 to US A3260")
        try expect(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A9999", productType: "iPhone99,9") == nil,
                   "Unknown model and product type map to nil, never a guessed A-number")
        try expect(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil, productType: "iPad16,1") == nil,
                   "iPads map to nil: the unlock is iPhone-focused")

        // Default mode stays region-code-only: staging is byte-identical
        // to the 9-item unlock (verified in ChinaUnlockTests).
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try fixture()
        let snapshot = DocumentSnapshot(data: try original.encoded(), document: original,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        try expect(manager.chinaUnlockRegionMode == .regionCodeOnly,
                   "Default region mode is region-code-only")
        manager.stageChinaUnlock()
        try expect(manager.changeCount == 9 && manager.regionID == "keep",
                   "Region-code-only staging still changes exactly 9 items")

        // Full US staging on the fixture: LL + LL/A + A3260.
        ChinaUnlockRegionMode.stored = .fullUS
        let fullUS = GestaltManager()
        fullUS.loadSnapshotForTests(snapshot)
        try expect(fullUS.chinaUnlockRegionMode == .fullUS, "Stored Full US mode is picked up")
        fullUS.stageChinaUnlock()
        guard let preview = fullUS.preview else { throw Failure(message: "Preview exists after Full US staging") }
        try expect(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Full US sets RegionCode to LL")
        try expect(preview.extra[GestaltKeys.regionInfo] as? String == "LL/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "LL/A",
                   "Full US sets both sales-region suffixes to LL/A")
        try expect(preview.extra[GestaltKeys.modelNumber] as? String == "A3260",
                   "Full US maps A3518 to the US model A3260")
        try expect(fullUS.isChinaUnlockedInPreview, "Full US preview reads as unlocked")
        // 10 CacheExtra keys (region code + 2 suffixes + model + 6 AI)
        // + 2 cache bytes = 12 staged changes.
        try expect(fullUS.changeCount == 12, "Full US staging changes 12 items, got \(fullUS.changeCount)")

        // Restore after Full US returns all three region/model keys.
        fullUS.restoreChinaUnlock()
        guard let restored = fullUS.preview else { throw Failure(message: "Preview exists after restore") }
        try expect(restored.matches(original), "Restore after Full US returns the original document")
        try expect(restored.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && restored.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A"
                   && restored.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Restore returns suffixes and model number to their originals")

        // Unknown device: Full US stages region + sales region only and
        // says so; the model number is left untouched.
        ChinaUnlockRegionMode.stored = .fullUS
        let unknownOriginal = try fixture(productType: "iPhone99,9", modelNumber: "A9999")
        let unknownSnapshot = DocumentSnapshot(data: try unknownOriginal.encoded(), document: unknownOriginal,
                                               source: .local, name: "unknown fixture")
        let unknown = GestaltManager()
        unknown.loadSnapshotForTests(unknownSnapshot)
        unknown.stageChinaUnlock()
        guard let unknownPreview = unknown.preview else { throw Failure(message: "Preview exists for unknown device") }
        try expect(unknownPreview.extra[GestaltKeys.regionCode] as? String == "LL"
                   && unknownPreview.extra[GestaltKeys.regionInfo] as? String == "LL/A",
                   "Unknown device still stages region code and sales region")
        try expect(unknownPreview.extra[GestaltKeys.modelNumber] as? String == "A9999",
                   "Unknown device leaves the model number untouched")
        try expect(unknown.regionModeNote != nil,
                   "Unknown device shows the no-mapping note")
        try expect(unknown.isChinaUnlockedInPreview,
                   "Unknown device still reads as unlocked without a mapped model")

        ChinaUnlockRegionMode.stored = .regionCodeOnly
        print("PASS: US regulatory mapping refuses unknown models, Full US stages LL + LL/A + mapped model (12 items) and restores all three keys, and unknown devices stage region-only with a note.")
    }
}
