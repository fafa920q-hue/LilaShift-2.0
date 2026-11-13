// SPDX-License-Identifier: GPL-3.0-only
// Personalization Center (个性化中心) — custom presets and real,
// working personalization settings. Pure Foundation — no SwiftUI, no
// UIKit, no singletons, no global mutable state.
//
// What this layer does:
//   • Custom presets: the user creates, edits and deletes their own
//     presets (name, Chinese description, risk level with a reason,
//     member selection from the P3 catalog). A custom preset is a
//     PLAN, not an action: it is checked by the dependency analyzer
//     and the SafePatch simulator (reusing the P3
//     `PresetCombinationChecker`), and it is NEVER wired to the
//     staging/apply path. Custom presets are saved locally as a
//     versioned JSON envelope with a SHA-256 sidecar in the history
//     directory (the same pattern as the P3 favorites/combination
//     stores); a corrupt, newer-format or foreign-device file loads
//     as empty with an error, never trusted.
//   • Personalization settings: the default catalog sort (by name /
//     by risk / by category), the favorites-first toggle, and which
//     cards are shown on the Tools page. Every setting takes effect
//     in the UI; a setting that does nothing is not allowed. Settings
//     are saved with the same envelope pattern.
//
// What this layer deliberately does NOT do:
//   • Wallpaper management: iOS offers no public API for an app to
//     change the system wallpaper. UIKit has no wallpaper-setting
//     API; `UIImageWriteToSavedPhotosAlbum` only saves an image to
//     Photos, and the user then sets it manually in Settings. The
//     Shortcuts app's "Set Wallpaper" action is a Shortcuts action,
//     not an API an app can call. Changing the wallpaper by writing
//     to SpringBoard files needs a jailbreak or a sandbox escape and
//     is out of scope for this layer. This is documented, not faked.
//   • Launch-image management: an app's launch image is a static
//     build-time asset (launch storyboard / asset catalog). iOS
//     offers no public API to change another app's launch image at
//     runtime, nor its own. The existing launch-artwork feature in
//     this app is unchanged by P4.
//   • Staging, applying, or writing to the MobileGestalt cache: this
//     layer never touches it.
//
// Honesty rules: a custom preset is always shown as a plan; the
// check result is display data; no string here claims "100% safe",
// "fully supported", or "guaranteed".
import Foundation

// MARK: - Catalog sort

/// How the preset catalog is sorted by default. The sort is applied
/// by `PersonalizationCenter.sortedEntries`, which the catalog card
/// calls for its visible entries — the setting takes effect there.
enum CatalogSort: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case byName
    case byRisk
    case byCategory

    var title: String {
        switch self {
        case .byName: return L("Sort by Name")
        case .byRisk: return L("Sort by Risk")
        case .byCategory: return L("Sort by Category")
        }
    }
}

// MARK: - Settings

/// The user's personalization settings. All three settings take
/// effect in the UI: `catalogSort` and `favoritesFirst` order the
/// catalog card's visible entries; `visibleToolCards` filters the
/// Tools page category grid in ContentView.
struct PersonalizationSettings: Codable, Equatable, Sendable {
    var catalogSort: CatalogSort
    var favoritesFirst: Bool
    /// Tool card ids shown on the Tools page. An id is a
    /// `ToolGroup` raw value ("screenLock", "networkEsim",
    /// "intelligenceRegion", "chargingButtons", "ipadMultitasking",
    /// "personalization"). Unknown ids are ignored by the UI.
    var visibleToolCards: Set<String>

    static let defaults = PersonalizationSettings(
        catalogSort: .byCategory, favoritesFirst: false,
        visibleToolCards: Set(PersonalizationCenter.allToolCardIDs))

    init(catalogSort: CatalogSort = .byCategory, favoritesFirst: Bool = false,
         visibleToolCards: Set<String> = Set(PersonalizationCenter.allToolCardIDs)) {
        self.catalogSort = catalogSort
        self.favoritesFirst = favoritesFirst
        self.visibleToolCards = visibleToolCards
    }
}

/// What loading the settings produced. A missing file loads the
/// defaults with no error; a bad file loads the defaults with an
/// error — the store never crashes and never trusts a bad file.
struct PersonalizationSettingsLoad: Equatable, Sendable {
    let settings: PersonalizationSettings
    let error: String?
}

/// Posted on the default notification center whenever the settings
/// are saved successfully, so the Tools page and the catalog card
/// reload them without polling.
extension Notification.Name {
    static let personalizationSettingsDidChange =
        Notification.Name("LilaShift.personalizationSettingsDidChange")
}

/// Local-only personalization settings, persisted in the app's own
/// history directory as a versioned JSON envelope with a SHA-256
/// sidecar (the same pattern as `PresetFavoritesStore`). Settings
/// never touch the MobileGestalt cache and never affect staging.
struct PersonalizationSettingsStore: Sendable {
    static let fileName = "personalization-settings.json"
    static let currentVersion = 1

    let directory: URL
    let deviceID: String

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Loads the settings. A missing file loads the defaults; a
    /// digest mismatch, an undecodable file, an envelope newer than
    /// this version, or an envelope for another device loads the
    /// defaults with an error.
    func load() -> PersonalizationSettingsLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PersonalizationSettingsLoad(settings: .defaults, error: nil)
        }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<PersonalizationSettings>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                return PersonalizationSettingsLoad(
                    settings: .defaults,
                    error: L("These settings use a newer format this version cannot read."))
            }
            guard envelope.deviceID == deviceID else {
                return PersonalizationSettingsLoad(
                    settings: .defaults,
                    error: L("These settings belong to a different device."))
            }
            guard let settings = envelope.records.first else {
                return PersonalizationSettingsLoad(
                    settings: .defaults,
                    error: L("The settings could not be read. Defaults are used."))
            }
            return PersonalizationSettingsLoad(settings: settings, error: nil)
        } catch {
            return PersonalizationSettingsLoad(
                settings: .defaults,
                error: L("The settings could not be read. Defaults are used."))
        }
    }

    /// Saves the settings as a v1 envelope with a SHA-256 sidecar,
    /// verified by a read-back, and posts
    /// `.personalizationSettingsDidChange` so the UI reloads them.
    func save(_ settings: PersonalizationSettings) throws {
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID,
                                records: [settings]),
                to: fileURL)
        } catch {
            throw GestaltFailure("The settings could not be saved and verified. No system changes were made.")
        }
        NotificationCenter.default.post(
            name: .personalizationSettingsDidChange, object: nil)
    }
}

// MARK: - Custom presets

/// One user-created custom preset: a named set of catalog entries
/// with a Chinese description and a risk level with a specific
/// reason. A PLAN only — never staged or applied by any layer.
/// `memberIDs` are catalog feature ids.
struct CustomPreset: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var chineseDescription: String
    var riskLevel: CapabilityRiskLevel
    var riskReason: String
    var memberIDs: [String]
    let createdAt: Date

    /// The equivalent P3 combination, for checking with the same
    /// tools staging uses.
    var asCombination: PresetCombination {
        PresetCombination(id: id, name: name, featureIDs: memberIDs, createdAt: createdAt)
    }
}

/// What loading the custom presets produced. Member ids that are no
/// longer in the catalog are dropped and reported in
/// `droppedMemberIDs`; a preset whose members are all dropped is
/// dropped as a whole, so the UI can say so instead of silently
/// showing an empty preset.
struct CustomPresetLoad: Equatable, Sendable {
    let presets: [CustomPreset]
    let droppedMemberIDs: [String]
    let error: String?
}

/// Local-only storage for custom presets, same envelope pattern as
/// the P3 combination store.
struct CustomPresetStore: Sendable {
    static let fileName = "custom-presets.json"
    static let currentVersion = 1
    /// A preset name is 1–32 characters, matching the app-appearance
    /// name rule.
    static let maxNameLength = 32

    let directory: URL
    let deviceID: String

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Validates a custom preset before it is saved: a name of 1–32
    /// characters, a non-empty description, a non-empty risk reason,
    /// at least one member, every member a known catalog id, no
    /// duplicates. Returns the first problem, or `nil` when the
    /// preset is valid.
    static func validationError(
        name: String, description: String, riskReason: String, featureIDs: [String]
    ) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return L("Give the custom preset a name.")
        }
        if trimmedName.count > maxNameLength {
            return L("A preset name is 1–32 characters.")
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("Describe what this preset does.")
        }
        if riskReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L("Explain the risk of this preset.")
        }
        if featureIDs.isEmpty {
            return L("Choose at least one preset.")
        }
        let known = Set(PresetCatalog.all.map(\.featureID))
        if let unknownID = featureIDs.first(where: { !known.contains($0) }) {
            return String(format: L("Unknown preset: %@"), unknownID)
        }
        if Set(featureIDs).count != featureIDs.count {
            return L("A custom preset cannot contain the same preset twice.")
        }
        return nil
    }

    /// Loads the saved custom presets. A missing file loads as
    /// empty; a bad file loads as empty with an error. Member ids no
    /// longer in the catalog are dropped and reported.
    func load() -> CustomPresetLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CustomPresetLoad(presets: [], droppedMemberIDs: [], error: nil)
        }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<CustomPreset>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                return CustomPresetLoad(
                    presets: [], droppedMemberIDs: [],
                    error: L("These custom presets use a newer format this version cannot read."))
            }
            guard envelope.deviceID == deviceID else {
                return CustomPresetLoad(
                    presets: [], droppedMemberIDs: [],
                    error: L("These custom presets belong to a different device."))
            }
            let known = Set(PresetCatalog.all.map(\.featureID))
            var dropped: [String] = []
            var kept: [CustomPreset] = []
            for preset in envelope.records {
                let keptMembers = preset.memberIDs.filter { id in
                    if known.contains(id) { return true }
                    dropped.append(id)
                    return false
                }
                guard !keptMembers.isEmpty else { continue }
                var cleanedPreset = preset
                cleanedPreset.memberIDs = keptMembers
                kept.append(cleanedPreset)
            }
            return CustomPresetLoad(presets: kept, droppedMemberIDs: dropped, error: nil)
        } catch {
            return CustomPresetLoad(
                presets: [], droppedMemberIDs: [],
                error: L("The custom presets could not be read. No system changes were made."))
        }
    }

    /// Saves the custom presets as a v1 envelope with a SHA-256
    /// sidecar, verified by a read-back.
    func save(_ presets: [CustomPreset]) throws {
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID, records: presets),
                to: fileURL)
        } catch {
            throw GestaltFailure("The custom presets could not be saved and verified. No system changes were made.")
        }
    }
}

// MARK: - Custom preset check

/// Checks a custom preset with the same tools staging uses:
/// `DependencyAnalyzer` for prerequisites, conflicts and
/// duplicates, and `SafePatch` for the pre-write simulation. Pure:
/// reads its inputs, writes nothing. The result is display data —
/// a custom preset is a plan, and the UI must say applying is not
/// connected.
enum CustomPresetChecker {
    static func check(
        preset: CustomPreset,
        profile: DeviceProfile,
        snapshot: DocumentSnapshot?,
        backups: [BackupRecord] = [],
        liveAIEnabled: Bool? = nil
    ) -> PresetCombinationCheck {
        PresetCombinationChecker.check(
            combination: preset.asCombination, profile: profile,
            snapshot: snapshot, backups: backups, liveAIEnabled: liveAIEnabled)
    }
}

// MARK: - Catalog ordering

/// The personalization logic: sorting and Tool-card visibility. The
/// Tools page and the catalog card both read from here, so a setting
/// has exactly one implementation.
enum PersonalizationCenter {
    /// The Tools page card ids, in grid order. These are the
    /// `ToolGroup` raw values in ContentView; the strings are kept
    /// here so the settings store does not depend on SwiftUI.
    static let allToolCardIDs: [String] = [
        "screenLock", "networkEsim", "intelligenceRegion",
        "chargingButtons", "ipadMultitasking", "personalization",
    ]

    /// The display title for one Tools page card id. Unknown ids
    /// return the id itself — the UI never shows a blank title.
    static func toolCardTitle(for id: String) -> String {
        switch id {
        case "screenLock": return L("Screen & Lock Screen")
        case "networkEsim": return L("Network & eSIM")
        case "intelligenceRegion": return L("Apple Intelligence & Region")
        case "chargingButtons": return L("Charging & Buttons")
        case "ipadMultitasking": return L("iPad & Multitasking")
        case "personalization": return L("Personalization")
        default: return id
        }
    }

    /// The Tools page cards that are visible under `settings`, in
    /// grid order. Cards the settings hide are not shown; a card id
    /// the settings do not know is ignored.
    static func visibleToolCardIDs(
        _ settings: PersonalizationSettings
    ) -> [String] {
        allToolCardIDs.filter { settings.visibleToolCards.contains($0) }
    }

    /// Orders catalog entries under the user's settings: first by
    /// the default sort, then favorites first when the toggle is on.
    /// The sorts are stable: entries that compare equal keep their
    /// catalog order.
    static func sortedEntries(
        _ entries: [PresetEntry], by sort: CatalogSort,
        favoriteIDs: Set<String>, favoritesFirst: Bool
    ) -> [PresetEntry] {
        let sorted = stableSorted(entries, by: sort)
        if favoritesFirst {
            return PresetCatalog.favoritesFirst(sorted, favoriteIDs: favoriteIDs)
        }
        return sorted
    }

    private static func stableSorted(_ entries: [PresetEntry], by sort: CatalogSort) -> [PresetEntry] {
        entries.enumerated().sorted { left, right in
            let comparison = compare(left.element, right.element, by: sort)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.offset < right.offset
        }.map { enumerated in enumerated.element }
    }

    private static func compare(_ left: PresetEntry, _ right: PresetEntry, by sort: CatalogSort) -> ComparisonResult {
        switch sort {
        case .byName:
            let nameComparison = left.chineseName.localizedStandardCompare(right.chineseName)
            if nameComparison != .orderedSame { return nameComparison }
            return left.featureID.localizedStandardCompare(right.featureID)
        case .byRisk:
            if left.riskLevel != right.riskLevel {
                return riskOrder(left.riskLevel) < riskOrder(right.riskLevel)
                    ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case .byCategory:
            let leftIndex = PresetCategory.allCases.firstIndex(of: left.category) ?? PresetCategory.allCases.count
            let rightIndex = PresetCategory.allCases.firstIndex(of: right.category) ?? PresetCategory.allCases.count
            if leftIndex != rightIndex {
                return leftIndex < rightIndex ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        }
    }

    /// Risk order for sorting: high first, then medium, then low —
    /// the entries that need the most attention come first.
    private static func riskOrder(_ risk: CapabilityRiskLevel) -> Int {
        switch risk {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
