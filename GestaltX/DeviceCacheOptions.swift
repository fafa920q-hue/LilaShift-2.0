// SPDX-License-Identifier: GPL-3.0-only
// Cache offsets are resolved from the device library and matched to the plist layout.
import Foundation

enum CacheOptionChoice: Int, CaseIterable, Identifiable {
    case keep, enable, restoreOriginal
    var id: Int { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .keep: "Keep Current"
        case .enable: "Enable"
        case .restoreOriginal: "Disable (Restore Original)"
        }
    }
}

struct CachedOptionFlags: Equatable, Codable, Sendable {
    let greenTea: Bool
    let notGreenTea: Bool

    static let enabled = Self(greenTea: false, notGreenTea: true)
    static let restricted = Self(greenTea: true, notGreenTea: false)
}

// Bind saved values to the cache layout; model and OS version are metadata only.
struct CachedOptionsOriginal: Codable, Equatable, Sendable {
    let productType: String
    let build: String
    let layoutUUID: String
    let flags: CachedOptionFlags

    init(document: GestaltDocument) throws {
        flags = try DeviceCacheOptions.flags(in: document)
        productType = document.extra[GestaltKeys.productType] as? String ?? ""
        build = document.root["CacheVersion"] as? String ?? ""
        layoutUUID = document.root["CacheUUID"] as? String ?? ""
    }

    func flags(in document: GestaltDocument) throws -> CachedOptionFlags {
        _ = try DeviceCacheOptions.validatedData(in: document)
        guard document.root["CacheUUID"] as? String == layoutUUID else {
            throw GestaltFailure("The original value belongs to a different cache layout. A matching backup is needed to restore it.")
        }
        return flags
    }
}

struct CachedBooleanChange: Identifiable {
    let name: String
    let offset: Int
    let before: Bool
    let after: Bool
    var id: Int { offset }
    /// Monospaced key path shown in the review sheet, e.g.
    /// `CacheData[0xBF8] · slot 383` for the green-tea value byte.
    var keyPathText: String {
        String(format: L("CacheData[0x%X] · slot %d"), offset, offset / 8)
    }
}

/// A CacheData diff for the review sheet: the explained slot changes plus
/// any changed byte outside the known slots. Unexplained bytes are
/// surfaced, never silently hidden; the write is refused for them by
/// `validateEdit`, and the preview shows why before Apply is pressed.
struct CacheDataDiff {
    let explained: [CachedBooleanChange]
    let unexplainedChangedByteCount: Int
    let unexplainedOffsets: [Int]
    var hasUnexplained: Bool { unexplainedChangedByteCount > 0 }
}

enum DeviceCacheOptions {
    static let wapiKey = "hiHut/WR+B9Lx/vd0WyeNg"
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"
    // Apple Intelligence CacheData slots (obfuscated keys shared with the
    // CacheExtra capabilities of the same names). Resolved dynamically by
    // MobileGestaltCacheLayout; never hardcoded slot numbers.
    static let audioIntelligenceKey = "rb2tKZxlj0Gm2tBmUQSLqQ"
    static let personalTranslatorKey = "M1n2sAqf33NAOgZRGxQYBA"

    static func validatedData(in document: GestaltDocument, using resolvedLayout: MobileGestaltCacheLayout? = nil) throws -> Data {
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: document)
        guard layout.matches(document), let data = document.root["CacheData"] as? Data,
              data[layout.validityOffset(for: layout.greenTeaIndex)] == 1,
              data[layout.validityOffset(for: layout.notGreenTeaIndex)] == 1,
              [layout.greenTeaOffset, layout.notGreenTeaOffset].allSatisfy({ offset in
                  data[offset] <= 1 && data[(offset + 1)..<(offset + 8)].allSatisfy { $0 == 0 }
              }),
              [greenTeaKey, notGreenTeaKey, "green-tea", "not-green-tea"].allSatisfy({ document.extra[$0] == nil }) else {
            throw GestaltFailure("The cache layout or values do not match this preset.")
        }
        return data
    }

    static func flags(in document: GestaltDocument, using resolvedLayout: MobileGestaltCacheLayout? = nil) throws -> CachedOptionFlags {
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: document)
        let data = try validatedData(in: document, using: layout)
        return CachedOptionFlags(greenTea: data[layout.greenTeaOffset] == 1,
                                  notGreenTea: data[layout.notGreenTeaOffset] == 1)
    }

    static func changes(from original: GestaltDocument, to edited: GestaltDocument) -> [CachedBooleanChange] {
        guard let before = original.root["CacheData"] as? Data,
              let after = edited.root["CacheData"] as? Data,
              before != after,
              let layout = try? MobileGestaltCacheLayout.resolve(in: original),
              after.count == before.count else { return [] }
        var fields: [(String, Int)] = []
        if (try? validatedData(in: original)) != nil {
            fields += [("green-tea", layout.greenTeaOffset), ("not-green-tea", layout.notGreenTeaOffset)]
        }
        if let offset = layout.wapiOffset, (try? wapi(in: original)) != nil { fields.append(("wapi", offset)) }
        for (name, key) in [("audio-intelligence", audioIntelligenceKey),
                            ("personal-translator", personalTranslatorKey)] {
            if let offset = layout.slotIndex(forKey: key).map({ $0 * 8 }),
               advAISlotValue(key, in: original, using: layout) != nil { fields.append((name, offset)) }
        }
        return fields.compactMap { name, offset in
            guard before[offset] != after[offset] else { return nil }
            return CachedBooleanChange(name: name, offset: offset, before: before[offset] != 0, after: after[offset] != 0)
        }
    }

    /// Full CacheData diff for the review sheet, or `nil` when the cached
    /// bytes are identical or the layout cannot be resolved. Known slot
    /// offsets (eSIM pair, wapi, the two AdvAI slots) are explained;
    /// every other changed byte is reported as unexplained.
    static func diff(from original: GestaltDocument, to edited: GestaltDocument) -> CacheDataDiff? {
        guard let before = original.root["CacheData"] as? Data,
              let after = edited.root["CacheData"] as? Data,
              before != after, before.count == after.count,
              let layout = try? MobileGestaltCacheLayout.resolve(in: original) else { return nil }
        var known: Set<Int> = [layout.greenTeaOffset, layout.notGreenTeaOffset]
        for offset in [layout.wapiOffset, layout.audioIntellOffset, layout.personalTranslatorOffset].compactMap({ $0 }) {
            known.insert(offset)
        }
        let unexplained = before.indices.filter { before[$0] != after[$0] && !known.contains($0) }
        return CacheDataDiff(explained: changes(from: original, to: edited),
                             unexplainedChangedByteCount: unexplained.count,
                             unexplainedOffsets: unexplained)
    }

    static func validateEdit(from original: GestaltDocument, to edited: GestaltDocument,
                             using resolvedLayout: MobileGestaltCacheLayout? = nil) throws {
        guard original.root["CacheData"] as? Data != edited.root["CacheData"] as? Data else { return }
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: original)
        guard layout.matches(original), layout.matches(edited),
              let before = original.root["CacheData"] as? Data,
              let after = edited.root["CacheData"] as? Data else {
            throw GestaltFailure("The cache layout or values do not match this preset.")
        }
        let changed = Set(before.indices.filter { before[$0] != after[$0] })
        var allowed: Set<Int> = [layout.greenTeaOffset, layout.notGreenTeaOffset]
        if let offset = layout.wapiOffset { allowed.insert(offset) }
        for key in [audioIntelligenceKey, personalTranslatorKey] {
            if let offset = layout.slotIndex(forKey: key).map({ $0 * 8 }) { allowed.insert(offset) }
        }
        guard changed.isSubset(of: allowed) else {
            throw GestaltFailure("This preset changes unrelated cache bytes.")
        }
        if !changed.isDisjoint(with: [layout.greenTeaOffset, layout.notGreenTeaOffset]) {
            _ = try validatedData(in: original, using: layout)
            _ = try validatedData(in: edited, using: layout)
        }
        if let offset = layout.wapiOffset, changed.contains(offset) {
            _ = try wapi(in: original, using: layout)
            _ = try wapi(in: edited, using: layout)
        }
        for key in [audioIntelligenceKey, personalTranslatorKey] {
            if let offset = layout.slotIndex(forKey: key).map({ $0 * 8 }), changed.contains(offset) {
                guard advAISlotValue(key, in: original, using: layout) != nil,
                      advAISlotValue(key, in: edited, using: layout) != nil else {
                    throw GestaltFailure("The cache layout or values do not match this preset.")
                }
            }
        }
    }

    static func wapi(in document: GestaltDocument, using resolvedLayout: MobileGestaltCacheLayout? = nil) throws -> Bool {
        let layout = try resolvedLayout ?? MobileGestaltCacheLayout.resolve(in: document)
        guard layout.matches(document), let index = layout.wapiIndex, let offset = layout.wapiOffset,
              let data = document.root["CacheData"] as? Data,
              data[layout.validityOffset(for: index)] == 1, data[offset] <= 1,
              data[(offset + 1)..<(offset + 8)].allSatisfy({ $0 == 0 }),
              document.extra[wapiKey] == nil, document.extra["wapi"] == nil else {
            throw GestaltFailure("The cache layout or values do not match this preset.")
        }
        return data[offset] == 1
    }

    /// Value of a resolved Apple Intelligence CacheData slot, or `nil`
    /// when the slot did not resolve on this layout or its bytes fail
    /// validation. Never guesses. Unlike `wapi`, the CacheExtra key of
    /// the same name is deliberately NOT required to be absent: our
    /// unlock sets CacheExtra `audioIntelligence`/`personalTranslator`
    /// to 1, and the slot and the key are independent layers (see the
    /// #178 note in AIReadinessCheckup.swift).
    static func advAISlotValue(_ key: String, in document: GestaltDocument,
                               using resolvedLayout: MobileGestaltCacheLayout? = nil) -> Bool? {
        let layout: MobileGestaltCacheLayout?
        if let resolvedLayout { layout = resolvedLayout }
        else { layout = try? MobileGestaltCacheLayout.resolve(in: document) }
        guard let layout, layout.matches(document),
              let index = layout.slotIndex(forKey: key),
              key == audioIntelligenceKey || key == personalTranslatorKey,
              let data = document.root["CacheData"] as? Data else { return nil }
        let offset = index * 8
        guard data[layout.validityOffset(for: index)] == 1, data[offset] <= 1,
              data[(offset + 1)..<(offset + 8)].allSatisfy({ $0 == 0 }) else { return nil }
        return data[offset] == 1
    }
}

enum WAPIChoice: Int, CaseIterable, Identifiable {
    case keep, disable, restoreOriginal
    var id: Int { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .keep: "Keep Current"
        case .disable: "Disable WAPI"
        case .restoreOriginal: "Restore Original"
        }
    }
}

struct WAPIOriginal: Codable, Equatable, Sendable {
    let layoutUUID: String
    let enabled: Bool
    init(document: GestaltDocument) throws {
        enabled = try DeviceCacheOptions.wapi(in: document)
        layoutUUID = document.root["CacheUUID"] as? String ?? ""
    }
    func value(in document: GestaltDocument) throws -> Bool {
        _ = try DeviceCacheOptions.wapi(in: document)
        guard document.root["CacheUUID"] as? String == layoutUUID else {
            throw GestaltFailure("The original value belongs to a different cache layout. A matching backup is needed to restore it.")
        }
        return enabled
    }
}
