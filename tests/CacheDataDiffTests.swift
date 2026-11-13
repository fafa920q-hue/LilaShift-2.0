import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the item-3 diff preview: hex offset/slot rows and the
/// "other bytes changed" row, plus the pre-preview validation gate.
/// No device or signing is needed.
final class CacheDataDiffTests: XCTestCase {
    struct Failure: Error { let message: String }

    static func fixture() throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache,
            "CacheExtra": [GestaltKeys.productType: "iPhone18,1", GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
    }

    static func tampered(_ original: GestaltDocument, offset: Int, value: UInt8) throws -> GestaltDocument {
        var root = original.root
        var cache = root["CacheData"] as! Data
        cache[offset] = value
        root["CacheData"] = cache
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))
    }

    func testCacheDataDiff() throws {
        let original = try Self.fixture()

        // A green-tea change explains both eSIM bytes with hex/slot rows.
        var edited = original
        try edited.setCacheOptions(.enabled)
        guard let diff = DeviceCacheOptions.diff(from: original, to: edited) else {
            throw Failure(message: "Diff exists for a changed CacheData")
        }
        XCTAssert(diff.explained.count == 2, "Two explained slot changes, got \(diff.explained.count)")
        XCTAssert(diff.unexplainedChangedByteCount == 0 && !diff.hasUnexplained,
                   "No unexplained bytes for a clean eSIM change")
        let greenTea = diff.explained.first { $0.name == "green-tea" }
        XCTAssert(greenTea?.keyPathText == "CacheData[0xBF8] · slot 383",
                   "Green-tea row shows offset 0xBF8 / slot 383, got \(greenTea?.keyPathText ?? "nil")")
        let notGreenTea = diff.explained.first { $0.name == "not-green-tea" }
        XCTAssert(notGreenTea?.keyPathText == "CacheData[0xFD0] · slot 506",
                   "Not-green-tea row shows offset 0xFD0 / slot 506, got \(notGreenTea?.keyPathText ?? "nil")")
        XCTAssert(DeviceCacheOptions.diff(from: original, to: original) == nil,
                   "Identical CacheData has no diff")

        // One extra changed byte at an unrelated offset is unexplained.
        let tampered = try Self.tampered(original, offset: 100, value: 1)
        guard let diff2 = DeviceCacheOptions.diff(from: original, to: tampered) else {
            throw Failure(message: "Diff exists for a tampered CacheData")
        }
        XCTAssert(diff2.explained.isEmpty, "No explained row for an unrelated byte")
        XCTAssert(diff2.unexplainedChangedByteCount == 1 && diff2.unexplainedOffsets == [100],
                   "Exactly one unexplained byte at offset 100, got \(diff2.unexplainedOffsets)")
        // The pre-preview gate reports the same failure the review
        // sheet shows before Apply is pressed.
        XCTAssertThrowsError(try DeviceCacheOptions.validateEdit(from: original, to: tampered)) { error in
            XCTAssertTrue(error is GestaltFailure)
        }

    }
}
