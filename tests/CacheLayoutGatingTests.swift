import Foundation

/// Offline tests for the item-1 scanner deltas: 47-bit PAC mask, `cfUUIDs`
/// as a second UUID source, wapi ambiguity failing the scan, and dynamic
/// Apple Intelligence slot resolution. No device or signing is needed.
@main struct CacheLayoutGatingTests {
    struct Failure: Error { let message: String }
    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func expectThrows(_ message: String, _ work: () throws -> Void) throws {
        do { try work() } catch is GestaltFailure { return } catch is Failure { throw Failure(message: message) } catch { return }
        throw Failure(message: message)
    }

    static func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }

    /// Builds a 6-slot table for the given keys at indices 0...5, with the
    /// UUID token in `strings` unless `includeUUID` is false.
    static func table(uuid: String, keys: [String], includeUUID: Bool = true,
                      pacBit47: [Int] = []) throws -> (strings: Data, address: UInt64, constants: [Data]) {
        let address: UInt64 = 0x180100000
        var strings = Data()
        if includeUUID { strings.append(contentsOf: (uuid + "\0").utf8) }
        var pointers: [UInt64] = []
        for key in keys {
            pointers.append(address + UInt64(strings.count))
            strings.append(contentsOf: (key + "\0").utf8)
        }
        var descriptors = Data(repeating: 0, count: keys.count * 64)
        for i in keys.indices {
            var pointer = pointers[i]
            if pacBit47.contains(i) { pointer |= 0x0000_8000_0000_0000 }
            put(pointer, into: &descriptors, at: i * 64)
            put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        return (strings, address, [descriptors])
    }

    /// A document on the offline profile's layout, unless a different
    /// UUID or CacheData is supplied. Mirrors the RegionModeTests fixture.
    static func fixtureDocument(cacheUUID: String? = nil, cacheData: Data? = nil) throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = cacheData ?? Data(count: layout.byteCount)
        if cache.count == layout.byteCount {
            cache[layout.greenTeaOffset] = 1
            cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
            cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        }
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": cacheUUID ?? layout.uuid,
            "CacheData": cache,
            "CacheExtra": [GestaltKeys.productType: "iPhone18,1", GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
    }

    static func main() throws {
        let uuid = "A4A4A4A4-1111-2222-3333-123456789ABC"
        let keys = ["AAAAAAAAAAAAAAAAAAAAAA", DeviceCacheOptions.greenTeaKey,
                    DeviceCacheOptions.notGreenTeaKey, DeviceCacheOptions.wapiKey,
                    DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey]

        // 47-bit PAC mask: a pointer with bit 47 set still resolves.
        // With the old 48-bit mask the tagged pointer would miss the hash
        // table and the scan would fail.
        let pac = try table(uuid: uuid, keys: keys, pacBit47: [1])
        let pacLayout = try MobileGestaltCacheLayout.scan(strings: pac.strings, stringAddress: pac.address, constants: pac.constants)
        try expect(pacLayout.greenTeaIndex == 1 && pacLayout.notGreenTeaIndex == 2,
                   "PAC-tagged pointer with bit 47 set resolves under the 47-bit mask")

        // cfUUIDs rescue a table whose UUID left `__cstring`.
        let noUUID = try table(uuid: uuid, keys: keys, includeUUID: false)
        try expectThrows("No UUID anywhere fails the scan") {
            _ = try MobileGestaltCacheLayout.scan(strings: noUUID.strings, stringAddress: noUUID.address, constants: noUUID.constants)
        }
        let rescued = try MobileGestaltCacheLayout.scan(strings: noUUID.strings, stringAddress: noUUID.address,
                                                         constants: noUUID.constants, cfUUIDs: [uuid])
        try expect(rescued.uuid == uuid && rescued.greenTeaIndex == 1,
                   "A UUID supplied via cfUUIDs resolves the scan")
        try expectThrows("Two distinct cfUUIDs are ambiguous") {
            _ = try MobileGestaltCacheLayout.scan(strings: noUUID.strings, stringAddress: noUUID.address,
                                                  constants: noUUID.constants,
                                                  cfUUIDs: [uuid, "BBBBBBBB-1111-2222-3333-123456789ABC"])
        }

        // Apple Intelligence slots resolve dynamically, like wapi.
        let full = try table(uuid: uuid, keys: keys)
        let layout = try MobileGestaltCacheLayout.scan(strings: full.strings, stringAddress: full.address, constants: full.constants)
        try expect(layout.audioIntellIndex == 4 && layout.personalTranslatorIndex == 5,
                   "Audio Intelligence and Personal Translator slots resolve from their descriptors")
        try expect(layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey) == 4
                   && layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey) == 5
                   && layout.slotIndex(forKey: "unknown-key") == nil,
                   "slotIndex(forKey:) answers the known keys and nil for anything else")

        // An ambiguous AdvAI descriptor leaves only that slot unresolved;
        // the eSIM pair still resolves (unlike wapi, which fails the scan).
        var ambiguous = full.constants[0]
        ambiguous.append(full.constants[0].subdata(in: 5 * 64..<6 * 64))
        put(Int16(0), into: &ambiguous, at: full.constants[0].count + 0x3A)
        let partial = try MobileGestaltCacheLayout.scan(strings: full.strings, stringAddress: full.address, constants: [ambiguous])
        try expect(partial.personalTranslatorIndex == nil && partial.audioIntellIndex == 4
                   && partial.greenTeaIndex == 1,
                   "An ambiguous Personal Translator descriptor leaves that slot nil without failing the scan")

        // A wapi descriptor at an index colliding with green-tea fails.
        var colliding = full.constants[0]
        put(Int16(1), into: &colliding, at: 3 * 64 + 0x3A)
        try expectThrows("A wapi descriptor colliding with green-tea fails the scan") {
            _ = try MobileGestaltCacheLayout.scan(strings: full.strings, stringAddress: full.address, constants: [colliding])
        }

        // Layout-scan failure locks with a reason instead of falling back.
        // An empty scan input fails outright, never resolving a layout.
        try expectThrows("An empty scan fails rather than resolving a layout") {
            _ = try MobileGestaltCacheLayout.scan(strings: Data(), stringAddress: 0x180100000, constants: [])
        }

        // A document on the offline profile resolves and has no lock reason.
        let matching = try fixtureDocument()
        try expect(MobileGestaltCacheLayout.lockReason(in: matching) == nil,
                   "A document matching the resolved layout has no lock reason")

        // A document whose UUID matches no layout throws on resolve and
        // carries a lock reason — the eSIM/WAPI switches stay locked and
        // show why, instead of silently borrowing the offline profile.
        // (On a device build the same throw comes from the failed runtime
        // scan; the hardcoded profile is never substituted there.)
        let wrongUUID = try fixtureDocument(cacheUUID: "00000000-0000-0000-0000-000000000000")
        try expectThrows("A document with an unknown CacheUUID fails to resolve") {
            _ = try MobileGestaltCacheLayout.resolve(in: wrongUUID)
        }
        let uuidReason = MobileGestaltCacheLayout.lockReason(in: wrongUUID)
        try expect(uuidReason != nil && uuidReason!.contains("Unable to resolve"),
                   "An unresolvable layout locks with a reason naming the failure")

        // A document with the wrong CacheData length fails the same way.
        let wrongLength = try fixtureDocument(cacheData: Data(count: 10))
        try expectThrows("A document with the wrong CacheData length fails to resolve") {
            _ = try MobileGestaltCacheLayout.resolve(in: wrongLength)
        }
        try expect(MobileGestaltCacheLayout.lockReason(in: wrongLength) != nil,
                   "A wrong-length CacheData locks with a reason")

        print("PASS: 47-bit PAC mask, cfUUIDs rescue, dynamic AI slot resolution, ambiguous AdvAI isolation, wapi ambiguity failing the scan, and layout-scan failure locking with a reason.")
    }
}
