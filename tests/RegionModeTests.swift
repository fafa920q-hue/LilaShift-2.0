import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the item-5 region mode choice: the US regulatory
/// model mapping (refuses unknown models) and the one-tap unlock, which
/// stages exactly the 9 items in either region mode — the sales-region
/// suffix and the regulatory model number are never staged, so a
/// regulatory model that does not match the hardware cannot make the
/// system discard the cache at boot. No device or signing is needed.
final class RegionModeTests: XCTestCase {
    struct Failure: Error { let message: String }

    /// China-mainland fixture: region CH with CH/A suffixes, Air model
    /// number A3518 (China mainland), product type iPhone18,1.
    func fixture(productType: String = "iPhone18,1",
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
    func testRegionMode() throws {
        // Mapping table spot checks (original reg model first, then
        // product type; unknown models refused, never guessed).
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A3718", productType: "iPhone19,3") == "A3473",
                   "A3718 (18 Pro Max China) maps to US A3473")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A3518", productType: "iPhone18,1") == "A3260",
                   "A3518 (Air China) maps to US A3260, not the product-type fallback A3256")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil, productType: "iPhone18,4") == "A3260",
                   "Product-type fallback maps iPhone18,4 to US A3260")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: "A9999", productType: "iPhone99,9") == nil,
                   "Unknown model and product type map to nil, never a guessed A-number")
        XCTAssert(USRegulatoryModelMapping.usRegulatoryModel(originalRegModel: nil, productType: "iPad16,1") == nil,
                   "iPads map to nil: the unlock is iPhone-focused")

        // Default mode stays region-code-only: staging is byte-identical
        // to the 9-item unlock (verified in ChinaUnlockTests).
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try fixture()
        let snapshot = DocumentSnapshot(data: try original.encoded(), document: original,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        XCTAssert(manager.chinaUnlockRegionMode == .regionCodeOnly,
                   "Default region mode is region-code-only")
        manager.stageChinaUnlock()
        XCTAssert(manager.changeCount == 9 && manager.regionID == "keep",
                   "Region-code-only staging still changes exactly 9 items")

        // Full US mode stages exactly the same 9 items as region-code-only:
        // the sales-region suffix and the regulatory model number are
        // never staged by the one-tap, in either mode.
        ChinaUnlockRegionMode.stored = .fullUS
        let fullUS = GestaltManager()
        fullUS.loadSnapshotForTests(snapshot)
        XCTAssert(fullUS.chinaUnlockRegionMode == .fullUS, "Stored Full US mode is picked up")
        fullUS.stageChinaUnlock()
        guard let preview = fullUS.preview else { throw Failure(message: "Preview exists after Full US staging") }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Full US sets RegionCode to LL")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Full US leaves both sales-region suffixes at CH/A")
        XCTAssert(preview.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Full US keeps the factory model number")
        XCTAssert(fullUS.isChinaUnlockedInPreview, "Full US preview reads as unlocked")
        XCTAssert(fullUS.changeCount == 9 && fullUS.regionID == "keep",
                   "Full US staging changes exactly 9 items, got \(fullUS.changeCount)")

        // Restore after staging returns the original document.
        fullUS.restoreChinaUnlock()
        guard let restored = fullUS.preview else { throw Failure(message: "Preview exists after restore") }
        XCTAssert(restored.matches(original), "Restore returns the original document")
        XCTAssert(restored.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && restored.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A"
                   && restored.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Restore returns suffixes and model number to their originals")

        // Unknown device: the one-tap still stages exactly the 9 items;
        // the sales-region suffixes and the model number are untouched.
        ChinaUnlockRegionMode.stored = .fullUS
        let unknownOriginal = try fixture(productType: "iPhone99,9", modelNumber: "A9999")
        let unknownSnapshot = DocumentSnapshot(data: try unknownOriginal.encoded(), document: unknownOriginal,
                                               source: .local, name: "unknown fixture")
        let unknown = GestaltManager()
        unknown.loadSnapshotForTests(unknownSnapshot)
        unknown.stageChinaUnlock()
        guard let unknownPreview = unknown.preview else { throw Failure(message: "Preview exists for unknown device") }
        XCTAssert(unknownPreview.extra[GestaltKeys.regionCode] as? String == "LL"
                   && unknownPreview.extra[GestaltKeys.regionInfo] as? String == "CH/A",
                   "Unknown device stages the region code and leaves the sales region alone")
        XCTAssert(unknownPreview.extra[GestaltKeys.modelNumber] as? String == "A9999",
                   "Unknown device leaves the model number untouched")
        XCTAssert(unknown.changeCount == 9,
                   "Unknown device stages exactly 9 items, got \(unknown.changeCount)")
        XCTAssert(unknown.isChinaUnlockedInPreview,
                   "Unknown device still reads as unlocked")

        ChinaUnlockRegionMode.stored = .regionCodeOnly
    }
}
