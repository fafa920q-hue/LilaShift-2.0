import Foundation

/// Offline tests for the item-3 diff preview: hex offset/slot rows and the
/// "other bytes changed" row, plus the pre-preview validation gate.
/// No device or signing is needed.
@main struct CacheDataDiffTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

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

    static func main() throws {
        let original = try fixture()

        // A green-tea change explains both eSIM bytes with hex/slot rows.
        var edited = original
        try edited.setCacheOptions(.enabled)
        guard let diff = DeviceCacheOptions.diff(from: original, to: edited) else {
            throw Failure(message: "Diff exists for a changed CacheData")
        }
        try expect(diff.explained.count == 2, "Two explained slot changes, got \(diff.explained.count)")
        try expect(diff.unexplainedChangedByteCount == 0 && !diff.hasUnexplained,
                   "No unexplained bytes for a clean eSIM change")
        let greenTea = diff.explained.first { $0.name == "green-tea" }
        try expect(greenTea?.keyPathText == "CacheData[0xBF8] · slot 383",
                   "Green-tea row shows offset 0xBF8 / slot 383, got \(greenTea?.keyPathText ?? "nil")")
        let notGreenTea = diff.explained.first { $0.name == "not-green-tea" }
        try expect(notGreenTea?.keyPathText == "CacheData[0xFD0] · slot 506",
                   "Not-green-tea row shows offset 0xFD0 / slot 506, got \(notGreenTea?.keyPathText ?? "nil")")
        try expect(DeviceCacheOptions.diff(from: original, to: original) == nil,
                   "Identical CacheData has no diff")

        // One extra changed byte at an unrelated offset is unexplained.
        let tampered = try tampered(original, offset: 100, value: 1)
        guard let diff2 = DeviceCacheOptions.diff(from: original, to: tampered) else {
            throw Failure(message: "Diff exists for a tampered CacheData")
        }
        try expect(diff2.explained.isEmpty, "No explained row for an unrelated byte")
        try expect(diff2.unexplainedChangedByteCount == 1 && diff2.unexplainedOffsets == [100],
                   "Exactly one unexplained byte at offset 100, got \(diff2.unexplainedOffsets)")
        do {
            try DeviceCacheOptions.validateEdit(from: original, to: tampered)
            throw Failure(message: "validateEdit accepted an unrelated cache byte")
        } catch is GestaltFailure {
            // The pre-preview gate reports the same failure the review
            // sheet shows before Apply is pressed.
        }

        print("PASS: CacheData diff shows hex offset/slot rows for explained slots and counts one unexplained byte at an unrelated offset, which validateEdit refuses.")
    }
}
