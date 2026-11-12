// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct MobileGestaltCacheLayout: Codable, Equatable, Sendable {
    let uuid: String
    let slotCount: Int
    let greenTeaIndex: Int
    let notGreenTeaIndex: Int
    var wapiIndex: Int? = nil
    /// Dynamically resolved Apple Intelligence CacheData slots (item 4).
    /// `nil` means the slot did not resolve on this library: the guard that
    /// needs it reports "unknown", never a guessed number. These are
    /// resolved, never hardcoded: #178/#266 are per-device observations,
    /// not constants.
    var audioIntellIndex: Int? = nil
    var personalTranslatorIndex: Int? = nil

    var wapiOffset: Int? { wapiIndex.map { $0 * 8 } }
    var audioIntellOffset: Int? { audioIntellIndex.map { $0 * 8 } }
    var personalTranslatorOffset: Int? { personalTranslatorIndex.map { $0 * 8 } }

    /// Slot index for a known obfuscated key, or `nil` when the key has no
    /// resolved CacheData slot on this layout.
    func slotIndex(forKey key: String) -> Int? {
        switch key {
        case DeviceCacheOptions.greenTeaKey: return greenTeaIndex
        case DeviceCacheOptions.notGreenTeaKey: return notGreenTeaIndex
        case DeviceCacheOptions.wapiKey: return wapiIndex
        case DeviceCacheOptions.audioIntelligenceKey: return audioIntellIndex
        case DeviceCacheOptions.personalTranslatorKey: return personalTranslatorIndex
        default: return nil
        }
    }

    var byteCount: Int { slotCount * 9 }
    var greenTeaOffset: Int { greenTeaIndex * 8 }
    var notGreenTeaOffset: Int { notGreenTeaIndex * 8 }
    func validityOffset(for index: Int) -> Int { slotCount * 8 + index }

    // Retain offline editing of the previously verified layout. Other layouts
    // are resolved from the device's own library, never selected by model/OS.
    // Simulator/offline fixtures ONLY: on a device build `resolve(in:)`
    // never consults this profile (see the `#if` in `resolve(in:)`), so an
    // unknown device can never silently borrow it. Do not use it as a
    // fallback anywhere else.
    static let originalProfile = Self(uuid: "7F1DF278-18B7-4E5A-8425-09E8830DE9AF",
                                      slotCount: 720, greenTeaIndex: 383, notGreenTeaIndex: 506, wapiIndex: 694)
    private static let runtimeProfile: Self? = {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = GXCopyMobileGestaltImage() else { return nil }
        return try? scan(image: image)
        #else
        return nil
        #endif
    }()

    func matches(_ document: GestaltDocument) -> Bool {
        guard (1...16384).contains(slotCount), (0..<slotCount).contains(greenTeaIndex),
              (0..<slotCount).contains(notGreenTeaIndex), greenTeaIndex != notGreenTeaIndex,
              let uuid = document.root["CacheUUID"] as? String,
              let data = document.root["CacheData"] as? Data else { return false }
        if let wapiIndex, (!(0..<slotCount).contains(wapiIndex) || wapiIndex == greenTeaIndex || wapiIndex == notGreenTeaIndex) { return false }
        for index in [audioIntellIndex, personalTranslatorIndex].compactMap({ $0 }) {
            guard (0..<slotCount).contains(index), index != greenTeaIndex, index != notGreenTeaIndex,
                  index != wapiIndex else { return false }
        }
        return self.uuid.caseInsensitiveCompare(uuid) == .orderedSame && data.count == byteCount
    }

    /// The runtime layout resolved from this launch's loaded library, if
    /// the scan succeeded. Exposed only so diagnostics can name which
    /// profile matched; resolution itself goes through `resolve(in:)`.
    static func runtimeLayout() -> Self? { runtimeProfile }

    /// The reason the cache layout cannot be resolved for this document,
    /// or `nil` when it resolves. This is the lock reason for the eSIM /
    /// WAPI switches: when it is non-nil the switches stay locked and
    /// this string is shown, rather than falling back to any layout.
    /// On a device build a failed runtime scan lands here; the hardcoded
    /// offline profile is never substituted.
    static func lockReason(in document: GestaltDocument) -> String? {
        do {
            _ = try resolve(in: document)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func resolve(in document: GestaltDocument) throws -> Self {
        #if os(iOS) && !targetEnvironment(simulator)
        // On device the hardcoded layout is never silently used. If the
        // runtime scan failed, the eSIM switches lock and the reason is
        // shown instead of guessing a layout that may not match this iOS
        // build. The offline profile below exists only for the simulator
        // and the offline test fixtures, where no library can be scanned.
        guard let runtime = runtimeProfile else {
            throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        }
        guard runtime.matches(document) else {
            throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        }
        return runtime
        #else
        for layout in [runtimeProfile, originalProfile].compactMap({ $0 }) {
            if layout.matches(document) { return layout }
        }
        throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        #endif
    }

    static func scan(image: [String: Any]) throws -> Self {
        guard let strings = image["strings"] as? Data,
              let address = image["stringAddress"] as? NSNumber,
              let constants = image["constants"] as? [Data] else {
            throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        }
        return try scan(strings: strings, stringAddress: address.uint64Value, constants: constants,
                        cfUUIDs: image["cfUUIDs"] as? [String] ?? [])
    }

    // Modern MobileGestalt query descriptors are 64 bytes. Their first pointer
    // identifies the exact obfuscated key; +0x3A is the signed cache index and
    // +0x3C is the query type (11 = Boolean). Resolve both independently.
    // `cfUUIDs` are UUID strings harvested from the library's `__cfstring`
    // section (see GXMobileGestaltImage.m): if a future iOS moves the
    // CacheUUID string out of `__cstring`, the scan still resolves.
    static func scan(strings: Data, stringAddress: UInt64, constants: [Data], cfUUIDs: [String] = []) throws -> Self {
        let failure = GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        guard !strings.isEmpty, strings.count <= 32 * 1024 * 1024,
              stringAddress <= UInt64.max - UInt64(strings.count),
              !constants.isEmpty, constants.count <= 8, constants.allSatisfy({ $0.count <= 32 * 1024 * 1024 }) else { throw failure }
        let bytes = [UInt8](strings)
        var hashes: [UInt64: String] = [:]
        var uuids = Set<String>()
        for uuid in cfUUIDs {
            if let parsed = UUID(uuidString: uuid) { uuids.insert(parsed.uuidString) }
        }
        var start = 0
        for end in bytes.indices where bytes[end] == 0 {
            let token = bytes[start..<end]
            if token.count == 22 && token.allSatisfy({
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 43 || $0 == 47
            }) {
                hashes[stringAddress + UInt64(start)] = String(decoding: token, as: UTF8.self)
            } else if token.count == 36, let text = String(bytes: token, encoding: .utf8), let uuid = UUID(uuidString: text) {
                uuids.insert(uuid.uuidString)
            }
            start = end + 1
        }
        // Ambiguous UUIDs or descriptors are rejected rather than guessed.
        guard uuids.count == 1, let uuid = uuids.first else { throw failure }
        var indices = Set<Int>()
        var targets: [String: Set<Int>] = [:]
        var wapiIndices = Set<Int>()
        var wapiLocations = Set<String>()
        var targetLocations: [String: Set<String>] = [:]
        // Apple Intelligence CacheData slots: resolved only when unique,
        // in range and alignment-matched. An ambiguous or invalid AdvAI
        // descriptor leaves the slot unresolved (nil), never guessed.
        var advTargets: [String: Set<Int>] = [:]
        var advLocations: [String: Set<String>] = [:]
        for (sectionID, section) in constants.enumerated() where section.count >= 64 {
            try section.withUnsafeBytes { raw in
                for offset in stride(from: 0, through: section.count - 64, by: 8) {
                    // Loaded pointers may carry arm64e PAC bits; no pointer is
                    // dereferenced. Compare its canonical user address only.
                    // Darwin arm64e userland VA space is 47-bit, so bits
                    // 63:47 are stripped (a 48-bit mask would keep a set
                    // bit 47 and map a PAC-tagged pointer to a wrong address).
                    let pointer = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) & 0x0000_7FFF_FFFF_FFFF
                    guard let key = hashes[pointer] else { continue }
                    let index = Int(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 0x3A, as: Int16.self)))
                    let type = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 0x3C, as: UInt32.self))
                    if key == DeviceCacheOptions.wapiKey {
                        // A wapi descriptor that exists but is unusable
                        // fails the whole scan: silently dropping it would
                        // let the scan claim a layout it cannot verify.
                        guard type == 11, (0..<16384).contains(index) else { throw failure }
                        wapiIndices.insert(index)
                        wapiLocations.insert("\(sectionID):\(offset % 64)")
                    }
                    if key == DeviceCacheOptions.greenTeaKey || key == DeviceCacheOptions.notGreenTeaKey {
                        // Every reference to a target must be usable. Ignoring an
                        // invalid duplicate would silently select another offset.
                        guard type == 11, (0..<16384).contains(index) else { throw failure }
                        targets[key, default: []].insert(index)
                        targetLocations[key, default: []].insert("\(sectionID):\(offset % 64)")
                    }
                    if key == DeviceCacheOptions.audioIntelligenceKey || key == DeviceCacheOptions.personalTranslatorKey {
                        if type == 11, (0..<16384).contains(index) {
                            advTargets[key, default: []].insert(index)
                            advLocations[key, default: []].insert("\(sectionID):\(offset % 64)")
                        }
                    }
                    guard (-1..<16384).contains(index), (1...11).contains(type) else { continue }
                    if index >= 0 { indices.insert(index) }
                }
            }
        }
        guard let maximum = indices.max(), maximum >= 1,
              indices.count > (maximum + 1) / 2,
              let green = targets[DeviceCacheOptions.greenTeaKey], green.count == 1,
              let notGreen = targets[DeviceCacheOptions.notGreenTeaKey], notGreen.count == 1,
              let greenIndex = green.first, let notGreenIndex = notGreen.first, greenIndex != notGreenIndex,
              let greenLocation = targetLocations[DeviceCacheOptions.greenTeaKey], greenLocation.count == 1,
              greenLocation == targetLocations[DeviceCacheOptions.notGreenTeaKey] else { throw failure }
        let wapi = wapiIndices.count == 1 && !wapiIndices.contains(greenIndex) && !wapiIndices.contains(notGreenIndex) && wapiLocations == greenLocation
            ? wapiIndices.first : nil
        // A wapi descriptor that resolved to several indices, or to an index
        // colliding with the eSIM pair, is ambiguous too: refuse it rather
        // than picking one. No descriptor at all still means "no WAPI".
        if !wapiIndices.isEmpty && wapi == nil { throw failure }
        func featureSlot(for key: String) -> Int? {
            guard let found = advTargets[key], found.count == 1,
                  let index = found.first, index != greenIndex, index != notGreenIndex,
                  index != wapi, advLocations[key] == greenLocation else { return nil }
            return index
        }
        return Self(uuid: uuid, slotCount: maximum + 1, greenTeaIndex: greenIndex,
                    notGreenTeaIndex: notGreenIndex, wapiIndex: wapi,
                    audioIntellIndex: featureSlot(for: DeviceCacheOptions.audioIntelligenceKey),
                    personalTranslatorIndex: featureSlot(for: DeviceCacheOptions.personalTranslatorKey))
    }
}
