// SPDX-License-Identifier: GPL-3.0-only
// Feature Catalog (Phase D + E) — ONE unified data source that backs
// the home sections, the preset pages and search.
//
// The catalog does not duplicate the preset database: every preset
// item is a view of a `PresetEntry` from `PresetCatalog` (40 entries),
// mapped onto one of the eleven feature categories below. Page items
// are the thirteen non-preset destinations (diagnostics pages,
// backups, modified values, personalization, launch artwork) that
// have no `PresetEntry` of their own. Together they are the whole
// browsable surface of the app: 53 items, each with a Simplified
// Chinese name and description.
//
// The eleven categories are the task's list, in the task's order
// (used for the category filter and the home sections). The sort
// order for `.byCategory` is a different, deliberately preserved
// scale — see `categorySortRank` — so preset-only ordering stays
// identical to `PersonalizationCenter.sortedEntries` (see the
// equivalence test in FeatureCatalogTests).
//
// This layer never stages, writes, or reads the MobileGestalt cache.
// It only organizes what already exists. Unknown stays unknown:
// a page item never claims a device state, and a preset item's
// eligibility comes from the caller's device report, never from
// this file.
import Foundation

// MARK: - Categories

/// The eleven feature categories, in display order. `title` and
/// `subtitle` reuse existing localized strings wherever one already
/// says the same thing, so no duplicate keys were added for them.
enum FeatureCatalogCategory: String, CaseIterable, Identifiable, Sendable {
    case smartUnlock
    case appleIntelligence
    case esimRegion
    case screenLock
    case systemSettings
    case personalization
    case launchArtwork
    case deviceDiagnostics
    case modifiedRecords
    case backupRestore
    case advancedTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartUnlock: return L("Smart Unlock")
        case .appleIntelligence: return L("Apple Intelligence")
        case .esimRegion: return L("eSIM & Region")
        case .screenLock: return L("Screen & Lock Screen")
        case .systemSettings: return L("System Settings")
        case .personalization: return L("Personalization")
        case .launchArtwork: return L("App Launch Images")
        case .deviceDiagnostics: return L("Diagnostics")
        case .modifiedRecords: return L("Modified Records")
        case .backupRestore: return L("Backup & Restore")
        case .advancedTools: return L("Advanced Tools")
        }
    }

    var subtitle: String {
        switch self {
        case .smartUnlock:
            return L("Set up eSIM, region code and Apple Intelligence in one tap.")
        case .appleIntelligence:
            return L("Region and generative model capabilities")
        case .esimRegion:
            return L("eSIM options, WAPI and call audio.")
        case .screenLock:
            return L("Lock screen display, screen brightness and display effects.")
        case .systemSettings:
            return L("Charging, buttons and device identity")
        case .personalization:
            return L("Custom presets, catalog sort and Tools page cards — saved on this device only.")
        case .launchArtwork:
            return L("Wallpapers, Lock Screen text and app launch images.")
        case .deviceDiagnostics:
            return L("Battery, app cache, connection status and the operation log — read-only.")
        case .modifiedRecords:
            return L("Fields whose current value differs from the recorded original.")
        case .backupRestore:
            return L("Backups appear here before each write. You can also make one anytime.")
        case .advancedTools:
            return L("Internal features and research settings")
        }
    }

    var symbol: String {
        switch self {
        case .smartUnlock: return "lock.open.fill"
        case .appleIntelligence: return "sparkles"
        case .esimRegion: return "simcard.fill"
        case .screenLock: return "iphone"
        case .systemSettings: return "gearshape"
        case .personalization: return "paintpalette"
        case .launchArtwork: return "photo"
        case .deviceDiagnostics: return "stethoscope"
        case .modifiedRecords: return "list.bullet"
        case .backupRestore: return "clock.arrow.circlepath"
        case .advancedTools: return "wrench.and.screwdriver"
        }
    }

    /// The `.byCategory` rank of a PAGE item in this category. Page
    /// items have no `PresetCategory`, so they sit between the
    /// preset categories on a fractional scale: after iPad (5) and
    /// before Advanced (6). Preset items never use this — their
    /// rank is their entry's `PresetCategory` index, which keeps
    /// preset-only `.byCategory` order identical to
    /// `PersonalizationCenter.sortedEntries`. Categories with no
    /// page items return 0 (unused).
    var pageSortRank: Double {
        switch self {
        case .personalization: return 5.5
        case .launchArtwork: return 5.6
        case .deviceDiagnostics: return 5.7
        case .modifiedRecords: return 5.8
        case .backupRestore: return 5.9
        case .smartUnlock, .appleIntelligence, .esimRegion,
             .screenLock, .systemSettings, .advancedTools:
            return 0
        }
    }
}

// MARK: - Item

/// One browsable item: either a preset (a view of a `PresetEntry`)
/// or a page (a non-preset destination). `categorySortRank` is the
/// `.byCategory` sort key: for presets the entry's `PresetCategory`
/// index, for pages the category's `pageSortRank`.
struct FeatureCatalogItem: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case preset
        case page
    }

    let id: String
    let kind: Kind
    let category: FeatureCatalogCategory
    /// Chinese name (preset entries) or localized title (pages).
    let chineseName: String
    let englishTitle: String
    /// Chinese description (preset entries) or localized subtitle.
    let chineseDescription: String
    /// Preset risk level; `nil` for pages, which carry no risk.
    let riskLevel: CapabilityRiskLevel?
    /// The dashboard page this item lives on. Preset items expand
    /// inline in the catalog browser; the destination is the page
    /// where the feature itself can be staged.
    let destination: DashboardV3Destination
    let symbol: String
    let categorySortRank: Double

    /// The preset feature id, for preset items; `nil` for pages.
    var presetFeatureID: String? { kind == .preset ? id : nil }
}

// MARK: - Catalog

/// The unified catalog: 40 preset items + 13 page items = 53.
/// Built from `PresetCatalog.all` plus the explicit page table, so
/// a preset added to the catalog appears here with no extra edit,
/// and a preset dropped there disappears here (the count test fails
/// loudly if the totals drift).
enum FeatureCatalog {
    /// All items: presets first in catalog order, then pages in
    /// category order. The order here is the input order for the
    /// stable sorts — it is not itself a display order.
    static let allItems: [FeatureCatalogItem] = presetItems + pageItems

    static let presetItems: [FeatureCatalogItem] = PresetCatalog.all.map { item(for: $0) }

    /// Every catalog id, for validating stored custom orders,
    /// hidden ids and recent-use lists.
    static var knownIDs: Set<String> { Set(allItems.map(\.id)) }

    /// The category of one preset entry. Feature id wins over the
    /// entry's `PresetCategory`: eSIM, region code and WAPI are
    /// eSIM & region even though the catalog files them under
    /// device/intelligence, the three groups map to their own
    /// categories, and the model-number virtual entry is an
    /// advanced tool, not an intelligence feature.
    static func category(for entry: PresetEntry) -> FeatureCatalogCategory {
        if entry.kind == .group {
            switch entry.featureID {
            case "preset.oneTap": return .smartUnlock
            case "preset.aiOnly": return .appleIntelligence
            case "preset.esimRegion": return .esimRegion
            default: return .smartUnlock
            }
        }
        switch entry.featureID {
        case FeatureEligibilityEvaluator.esimFeatureID,
             FeatureEligibilityEvaluator.regionCodeFeatureID,
             FeatureEligibilityEvaluator.wapiFeatureID:
            return .esimRegion
        case "modelNumber":
            return .advancedTools
        default:
            break
        }
        if ChinaUnlock.aiCapabilityIDs.contains(entry.featureID) {
            return .appleIntelligence
        }
        switch entry.category {
        case .intelligence: return .appleIntelligence
        case .display: return .screenLock
        case .device, .ipad: return .systemSettings
        case .advanced: return .advancedTools
        case .esim, .region: return .esimRegion
        case .group: return .smartUnlock
        }
    }

    /// The dashboard page where a preset can be staged: the unlock
    /// page for the one-tap family (unlock, AI, eSIM & region), the
    /// tools page for everything else (its category groups).
    static func destination(for entry: PresetEntry) -> DashboardV3Destination {
        switch category(for: entry) {
        case .smartUnlock, .appleIntelligence, .esimRegion: return .unlock
        case .screenLock, .systemSettings, .personalization,
             .launchArtwork, .deviceDiagnostics, .modifiedRecords,
             .backupRestore, .advancedTools:
            return .advanced
        }
    }

    private static func item(for entry: PresetEntry) -> FeatureCatalogItem {
        let rank = Double(PresetCategory.allCases.firstIndex(of: entry.category)
                            ?? PresetCategory.allCases.count)
        return FeatureCatalogItem(
            id: entry.featureID,
            kind: .preset,
            category: category(for: entry),
            chineseName: entry.chineseName,
            englishTitle: entry.englishTitle,
            chineseDescription: entry.chineseDescription,
            riskLevel: entry.riskLevel,
            destination: destination(for: entry),
            symbol: category(for: entry).symbol,
            categorySortRank: rank)
    }

    /// The thirteen page items. Each reuses the localized title and
    /// subtitle of the card or page it points at — no new strings,
    /// no invented descriptions.
    static let pageItems: [FeatureCatalogItem] = [
        page(id: "page.lilaIntelligence", category: .deviceDiagnostics,
             title: "Lila Intelligence",
             subtitle: "Personalized recommendations for this device, generated locally from real readings.",
             destination: .diagnostics, symbol: "brain"),
        page(id: "page.safePatch", category: .deviceDiagnostics,
             title: "SafePatch Simulator",
             subtitle: "See what a change would do before you enable it. Simulation only — nothing is written.",
             destination: .diagnostics, symbol: "shield.checkered"),
        page(id: "page.healthScore", category: .deviceDiagnostics,
             title: "System Health Score",
             subtitle: "Cache, compatibility, backup and modification risk, from real readings only.",
             destination: .diagnostics, symbol: "heart.text.square"),
        page(id: "page.dependencyAnalyzer", category: .deviceDiagnostics,
             title: "Dependency Analyzer",
             subtitle: "Dependencies, conflicts and duplicates for a proposal, before you stage it.",
             destination: .diagnostics, symbol: "point.3.connected.trianglepath.dotted"),
        page(id: "page.deviceFingerprint", category: .deviceDiagnostics,
             title: "Device Capability Fingerprint",
             subtitle: "This device's real capabilities and build, recorded locally with a SHA-256 digest.",
             destination: .diagnostics, symbol: "fingerprint"),
        page(id: "page.acceptance", category: .deviceDiagnostics,
             title: "Post-Modification Acceptance",
             subtitle: "Re-read the device after a restart and check what actually stuck.",
             destination: .diagnostics, symbol: "checkmark.seal"),
        page(id: "page.faultDiagnosis", category: .deviceDiagnostics,
             title: "Smart Fault Diagnosis",
             subtitle: "What went wrong, why, and what to try — from real readings only.",
             destination: .diagnostics, symbol: "stethoscope"),
        page(id: "page.diagnosticsExpansion", category: .deviceDiagnostics,
             title: "Diagnostics Expansion",
             subtitle: "Battery, app cache, connection status and the operation log — read-only.",
             destination: .diagnostics, symbol: "waveform.path.ecg"),
        page(id: "page.restoreIntelligence", category: .backupRestore,
             title: "Restore Intelligence",
             subtitle: "Modification timeline and precise restore, from trusted records only.",
             destination: .restore, symbol: "clock.arrow.circlepath"),
        page(id: "page.backups", category: .backupRestore,
             title: "Backups",
             subtitle: "Backups appear here before each write. You can also make one anytime.",
             destination: .restore, symbol: "externaldrive"),
        page(id: "page.modifiedValues", category: .modifiedRecords,
             title: "Modified Values",
             subtitle: "Fields whose current value differs from the recorded original.",
             destination: .unlock, symbol: "list.bullet"),
        page(id: "page.personalization", category: .personalization,
             title: "Personalization Center",
             subtitle: "Custom presets, catalog sort and Tools page cards — saved on this device only.",
             destination: .presets, symbol: "paintpalette"),
        page(id: "page.launchArtwork", category: .launchArtwork,
             title: "App Launch Images",
             subtitle: "Wallpapers, Lock Screen text and app launch images.",
             destination: .advanced, symbol: "photo"),
    ]

    private static func page(
        id: String, category: FeatureCatalogCategory,
        title: String, subtitle: String,
        destination: DashboardV3Destination, symbol: String
    ) -> FeatureCatalogItem {
        FeatureCatalogItem(
            id: id, kind: .page, category: category,
            chineseName: L(title), englishTitle: title,
            chineseDescription: L(subtitle), riskLevel: nil,
            destination: destination, symbol: symbol,
            categorySortRank: category.pageSortRank)
    }

    // MARK: Search and filter

    /// Case-insensitive substring search over the Chinese name,
    /// English title, id and Chinese description. An empty or blank
    /// query returns all entries. No fuzzy guessing: only real
    /// substring matches are returned. Same semantics as
    /// `PresetCatalog.search`, extended to page items.
    static func search(_ query: String, in items: [FeatureCatalogItem] = allItems) -> [FeatureCatalogItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { item in
            item.chineseName.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || item.englishTitle.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || item.id.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || item.chineseDescription.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Filters by category and risk level. Page items carry no risk
    /// level, so a risk filter excludes them — a page is not a
    /// preset and has nothing risky to rank.
    static func filtered(
        _ items: [FeatureCatalogItem],
        category: FeatureCatalogCategory? = nil,
        riskLevel: CapabilityRiskLevel? = nil
    ) -> [FeatureCatalogItem] {
        items.filter { item in
            if let category, item.category != category { return false }
            if let riskLevel, item.riskLevel != riskLevel { return false }
            return true
        }
    }

    // MARK: One pipeline

    /// The one pipeline every catalog surface uses: hidden items
    /// out, then search, then category and risk filters, then the
    /// single ordering rule (`HomeSorting.sortCatalogItems`). The
    /// home common-features section, the catalog browser and the
    /// preset pages all call this — no per-page ad-hoc ordering.
    static func apply(
        _ items: [FeatureCatalogItem],
        query: String,
        category: FeatureCatalogCategory?,
        riskLevel: CapabilityRiskLevel?,
        settings: FeatureCatalogSettings,
        catalogSort: CatalogSort,
        favoritesFirst: Bool,
        favoriteIDs: Set<String>
    ) -> [FeatureCatalogItem] {
        let visible = items.filter { !settings.hiddenIDs.contains($0.id) }
        let searched = search(query, in: visible)
        let filteredItems = filtered(searched, category: category, riskLevel: riskLevel)
        return HomeSorting.sortCatalogItems(
            filteredItems, by: catalogSort, favoritesFirst: favoritesFirst,
            favoriteIDs: favoriteIDs, customOrder: settings.customOrder,
            recentIDs: settings.recentIDs)
    }

    /// Records one use for recency: most recent first, duplicates
    /// removed, capped at ten. Unknown ids are ignored — a stored
    /// recent list never resurrects a removed feature.
    static func recordingUse(_ id: String, in settings: FeatureCatalogSettings) -> FeatureCatalogSettings {
        guard knownIDs.contains(id) else { return settings }
        var recent = settings.recentIDs.filter { $0 != id }
        recent.insert(id, at: 0)
        var updated = settings
        updated.recentIDs = Array(recent.prefix(FeatureCatalogSettings.maxRecentCount))
        return updated
    }
}

// MARK: - Catalog settings (custom order, hidden, recent)

/// The user's catalog settings: a custom item order (drag reorder),
/// the hidden item ids, and the recent-use list (most recent
/// first). Sort and favorites-first are NOT duplicated here — they
/// stay in `PersonalizationSettings` (`catalogSort`,
/// `favoritesFirst`), the single source for those two settings.
/// Favorites themselves stay in `PresetFavoritesStore`.
/// All three fields are optional-tolerant on decode: a settings
/// file written before a field existed decodes with that field at
/// its default, so upgrades preserve existing user config.
struct FeatureCatalogSettings: Codable, Equatable, Sendable {
    /// Item ids in the user's preferred order, or `nil` for the
    /// default order. Unknown ids are ignored by the sorter; items
    /// missing from a stored order are appended in default order,
    /// so an item added in a later version still appears.
    var customOrder: [String]?
    /// Item ids the user hid. Unknown ids are ignored.
    var hiddenIDs: Set<String>
    /// Recently used item ids, most recent first, capped at
    /// `maxRecentCount`. Unknown ids are ignored.
    var recentIDs: [String]

    static let maxRecentCount = 10

    static let defaults = FeatureCatalogSettings(
        customOrder: nil, hiddenIDs: [], recentIDs: [])

    init(customOrder: [String]? = nil, hiddenIDs: Set<String> = [],
         recentIDs: [String] = []) {
        self.customOrder = customOrder
        self.hiddenIDs = hiddenIDs
        self.recentIDs = recentIDs
    }
}

/// What loading the catalog settings produced. A missing file loads
/// the defaults with no error; a bad file loads the defaults with
/// an error — the store never crashes and never trusts a bad file.
struct FeatureCatalogSettingsLoad: Equatable, Sendable {
    let settings: FeatureCatalogSettings
    let error: String?
}

/// Posted on the default notification center whenever the catalog
/// settings are saved successfully, so the catalog browser and the
/// home reload them without polling.
extension Notification.Name {
    static let featureCatalogSettingsDidChange =
        Notification.Name("LilaShift.featureCatalogSettingsDidChange")
}

/// Local-only catalog settings, persisted in the app's own history
/// directory as a versioned JSON envelope with a SHA-256 sidecar
/// (the same pattern as `PersonalizationSettingsStore`). Settings
/// never touch the MobileGestalt cache and never affect staging.
struct FeatureCatalogSettingsStore: Sendable {
    static let fileName = "feature-catalog-settings.json"
    static let currentVersion = 1

    let directory: URL
    let deviceID: String

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Loads the settings. A missing file loads the defaults; a
    /// digest mismatch, an undecodable file, an envelope newer than
    /// this version, or an envelope for another device loads the
    /// defaults with an error.
    func load() -> FeatureCatalogSettingsLoad {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return FeatureCatalogSettingsLoad(settings: .defaults, error: nil)
        }
        do {
            let envelope = try HistoryJournal.readVerifiedJSON(
                HistoryEnvelope<FeatureCatalogSettings>.self, from: fileURL)
            guard envelope.version <= Self.currentVersion else {
                return FeatureCatalogSettingsLoad(
                    settings: .defaults,
                    error: L("These settings use a newer format this version cannot read."))
            }
            guard envelope.deviceID == deviceID else {
                return FeatureCatalogSettingsLoad(
                    settings: .defaults,
                    error: L("These settings belong to a different device."))
            }
            guard let settings = envelope.records.first else {
                return FeatureCatalogSettingsLoad(
                    settings: .defaults,
                    error: L("The settings could not be read. Defaults are used."))
            }
            return FeatureCatalogSettingsLoad(settings: settings, error: nil)
        } catch {
            return FeatureCatalogSettingsLoad(
                settings: .defaults,
                error: L("The settings could not be read. Defaults are used."))
        }
    }

    /// Saves the settings as a v1 envelope with a SHA-256 sidecar,
    /// verified by a read-back, and posts
    /// `.featureCatalogSettingsDidChange` so the UI reloads them.
    func save(_ settings: FeatureCatalogSettings) throws {
        do {
            try HistoryJournal.writeVerifiedJSON(
                HistoryEnvelope(version: Self.currentVersion, deviceID: deviceID,
                                records: [settings]),
                to: fileURL)
        } catch {
            throw GestaltFailure("The settings could not be saved and verified. No system changes were made.")
        }
        NotificationCenter.default.post(
            name: .featureCatalogSettingsDidChange, object: nil)
    }
}

// MARK: - Home sections

/// The eight home sections (Phase D). The raw value is the stable
/// id; the order on screen follows the user's dashboard-destination
/// order (`DashboardV3Destination.resolvedOrder`), so a stored
/// order from an older build keeps working and a destination added
/// in a later version gets its sections appended. Device overview
/// and common features are always first: they are summaries, not
/// destinations.
enum HomeSectionID: String, CaseIterable, Identifiable, Sendable {
    case deviceOverview
    case commonFeatures
    case chinaUnlock
    case appleIntelligenceEsim
    case securityDiagnosis
    case backupRestore
    case presetManagement
    case moreTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deviceOverview: return L("Device Overview")
        case .commonFeatures: return L("Common Features")
        case .chinaUnlock: return L("One-Tap Unlock")
        case .appleIntelligenceEsim: return L("Apple Intelligence & eSIM")
        case .securityDiagnosis: return L("Security Diagnosis")
        case .backupRestore: return L("Backup & Restore")
        case .presetManagement: return L("Preset Management")
        case .moreTools: return L("More Tools")
        }
    }

    /// The one-line description under the section title. Every
    /// section has one, in Simplified Chinese via the catalog.
    /// Device overview has none: the card itself is the summary.
    var subtitle: String? {
        switch self {
        case .deviceOverview: return nil
        case .commonFeatures: return L("Most-used presets at a glance.")
        case .chinaUnlock: return L("Set up eSIM, region code and Apple Intelligence in one tap.")
        case .appleIntelligenceEsim: return L("Region code and Apple Intelligence features.")
        case .securityDiagnosis: return L("Health, simulation and recorded changes at a glance. Details are on the pages below.")
        case .backupRestore: return L("Backups appear here before each write. You can also make one anytime.")
        case .presetManagement: return L("Search, filter and save presets — from the catalog only.")
        case .moreTools: return L("All tools")
        }
    }

    var symbol: String {
        switch self {
        case .deviceOverview: return "iphone"
        case .commonFeatures: return "star.fill"
        case .chinaUnlock: return "lock.open.fill"
        case .appleIntelligenceEsim: return "sparkles"
        case .securityDiagnosis: return "stethoscope"
        case .backupRestore: return "clock.arrow.circlepath"
        case .presetManagement: return "books.vertical"
        case .moreTools: return "slider.horizontal.3"
        }
    }

    /// The dashboard page this section opens, or `nil` for the two
    /// inline summary sections. One-tap unlock and Apple
    /// Intelligence & eSIM share the unlock page: that page holds
    /// both the one-tap card and the AI / eSIM cards, so the two
    /// sections are summaries of different parts of one page.
    var destination: DashboardV3Destination? {
        switch self {
        case .deviceOverview, .commonFeatures: return nil
        case .chinaUnlock, .appleIntelligenceEsim: return .unlock
        case .securityDiagnosis: return .diagnostics
        case .backupRestore: return .restore
        case .presetManagement: return .presets
        case .moreTools: return .advanced
        }
    }

    /// The home sections for a destination order: device overview
    /// and common features first, then one or two sections per
    /// destination in the user's order.
    static func sections(for destinations: [DashboardV3Destination]) -> [HomeSectionID] {
        var sections: [HomeSectionID] = [.deviceOverview, .commonFeatures]
        for destination in destinations {
            switch destination {
            case .unlock:
                sections += [.chinaUnlock, .appleIntelligenceEsim]
            case .diagnostics:
                sections.append(.securityDiagnosis)
            case .restore:
                sections.append(.backupRestore)
            case .presets:
                sections.append(.presetManagement)
            case .advanced:
                sections.append(.moreTools)
            }
        }
        return sections
    }

    /// The home sections for a stored destination order string:
    /// the same migration-safe resolution as the destinations
    /// themselves (unknown ids ignored, duplicates dropped, new
    /// destinations appended), mapped to sections.
    static func resolvedSections(_ raw: String) -> [HomeSectionID] {
        sections(for: DashboardV3Destination.resolvedOrder(raw))
    }
}
