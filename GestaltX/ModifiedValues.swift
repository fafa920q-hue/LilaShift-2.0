// SPDX-License-Identifier: GPL-3.0-only
// Read-only "Modified Values" report: which fields in the live-read
// document differ from their recorded originals, showing original
// and current side by side.
//
// Honesty rules (never relaxed):
// - A field is listed ONLY when BOTH its original and its current
//   value are known and verified. The original must come from a
//   recorded `OriginalField` (or a recorded CacheData original); the
//   current must come from the live-read snapshot document.
// - A field with no recorded original is never listed. Its original
//   is unknown, never guessed, and never shown as "absent" — absence
//   is only claimed when the recorded original itself is nil
//   (`OriginalField(value: nil)` means the field did not exist).
// - A difference is never attributed to a specific tool or time.
// - This feature stages nothing and writes nothing; it only reads
//   the snapshot and its recorded originals.
// - The comparison is against the live-read snapshot document (the
//   file as it is), not the staged preview: staged-but-unapplied
//   changes are shown by the review sheet, not here.
import Foundation

/// One field whose current value differs from its recorded original.
/// `originalText` / `currentText` are display strings produced by the
/// app's standard plist formatter (`PlistValueKind.text(for:)`); a
/// missing value reads as the localized "Not set" string.
struct ModifiedValueRow: Identifiable, Equatable, Sendable {
    let key: String
    let title: String
    let originalText: String
    let currentText: String
    /// True when the field did not exist originally (the recorded
    /// original is nil) and is present now.
    let wasAbsent: Bool
    var id: String { key }
}

/// The outcome of comparing the live-read document against its
/// recorded originals. Three honest states:
/// - `.noDocument`: no snapshot (device never read / no file opened).
/// - `.noRecordedOriginals`: a snapshot exists but nothing was ever
///   recorded as an original, so whether anything was modified cannot
///   be determined. This is NOT "nothing modified".
/// - `.compared(rows:)`: recorded originals exist; `rows` holds the
///   fields whose current value differs from the recorded original.
///   An empty `rows` here honestly means "no modification found",
///   because a baseline existed to compare against.
enum ModifiedValuesReport: Equatable, Sendable {
    case noDocument
    case noRecordedOriginals
    case compared(rows: [ModifiedValueRow])

    var rows: [ModifiedValueRow] {
        if case .compared(let rows) = self { return rows }
        return []
    }
}

enum ModifiedValues {
    /// Builds the report for a snapshot. `snapshot` is nil when no
    /// document has been read yet.
    static func report(for snapshot: DocumentSnapshot?) -> ModifiedValuesReport {
        guard let snapshot else { return .noDocument }
        var rows: [ModifiedValueRow] = []

        // CacheExtra keys with a recorded original. Only keys present
        // in `snapshot.originals` are evaluated: a key with no recorded
        // original has an unknown original and is never listed.
        for (key, original) in snapshot.originals {
            let current = snapshot.document.extra[key]
            guard valuesDiffer(original: original.value, current: current) else { continue }
            rows.append(ModifiedValueRow(
                key: key,
                title: title(forKey: key),
                originalText: displayText(for: original.value),
                currentText: displayText(for: current),
                wasAbsent: original.value == nil))
        }

        // eSIM CacheData slots. Both sides must read successfully;
        // an unresolvable layout means the slot is omitted, never
        // guessed.
        if let originalFlags = snapshot.cachedOptionsOriginal,
           let currentFlags = try? DeviceCacheOptions.flags(in: snapshot.document) {
            if originalFlags.flags.greenTea != currentFlags.greenTea {
                rows.append(ModifiedValueRow(
                    key: "esim-green-tea",
                    title: "eSIM (green-tea)",
                    originalText: boolText(originalFlags.flags.greenTea),
                    currentText: boolText(currentFlags.greenTea),
                    wasAbsent: false))
            }
            if originalFlags.flags.notGreenTea != currentFlags.notGreenTea {
                rows.append(ModifiedValueRow(
                    key: "esim-not-green-tea",
                    title: "eSIM (not-green-tea)",
                    originalText: boolText(originalFlags.flags.notGreenTea),
                    currentText: boolText(currentFlags.notGreenTea),
                    wasAbsent: false))
            }
        }

        // WAPI CacheData slot. Same rule: both sides must read.
        if let wapiOriginal = snapshot.wapiOriginal,
           let originalWAPI = try? wapiOriginal.value(in: snapshot.document),
           let currentWAPI = try? DeviceCacheOptions.wapi(in: snapshot.document),
           originalWAPI != currentWAPI {
            rows.append(ModifiedValueRow(
                key: "wapi",
                title: "WAPI",
                originalText: boolText(originalWAPI),
                currentText: boolText(currentWAPI),
                wasAbsent: false))
        }

        // Whether any original was recorded at all. Without one, the
        // report cannot say anything about modifications — not even
        // "none".
        let hasAnyOriginal = !snapshot.originals.isEmpty
            || snapshot.cachedOptionsOriginal != nil
            || snapshot.wapiOriginal != nil
        guard hasAnyOriginal else { return .noRecordedOriginals }

        rows.sort { $0.key < $1.key }
        return .compared(rows: rows)
    }

    /// True when the two values differ. `nil` means the field was
    /// absent; absent vs present counts as a difference, absent vs
    /// absent does not.
    static func valuesDiffer(original: Any?, current: Any?) -> Bool {
        switch (original, current) {
        case (nil, nil): return false
        case (nil, _), (_, nil): return true
        case (let a?, let b?): return !GestaltDocument.valuesEqual(a, b)
        }
    }

    /// Display text for a value. A missing value reads as the
    /// localized "Not set"; anything else uses the app's standard
    /// plist formatter (boolean "true"/"false", numbers and strings
    /// as themselves).
    static func displayText(for value: Any?) -> String {
        guard let value else { return L("Not set") }
        return PlistValueKind.detect(value).text(for: value)
    }

    static func boolText(_ value: Bool) -> String { value ? "true" : "false" }

    /// Human-readable title for a CacheExtra key. Prefers the
    /// capability that owns the key; well-known standalone keys get a
    /// dedicated name; anything else falls back to the raw key so the
    /// row is still identifiable and honest.
    static func title(forKey key: String) -> String {
        if let capability = Capability.all.first(where: { $0.keys.contains(key) }) {
            return capability.title
        }
        switch key {
        case GestaltKeys.regionCode: return "Region Code"
        case GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo: return "Sales Region"
        case GestaltKeys.modelNumber: return "Regulatory Model"
        case GestaltKeys.productType: return "Product Type"
        default: return key
        }
    }
}
