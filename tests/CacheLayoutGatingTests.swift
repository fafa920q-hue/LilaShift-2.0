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

        print("PASS: 47-bit PAC mask, cfUUIDs rescue, dynamic AI slot resolution, ambiguous AdvAI isolation, and wapi ambiguity failing the scan.")
    }
}
