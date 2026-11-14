// SPDX-License-Identifier: GPL-3.0-only
// LilaShift 3.0: a lightweight, task-oriented landing page.
// All device readings remain sourced from GestaltManager, never placeholders.
import SwiftUI

enum DashboardV3Destination: String, CaseIterable, Identifiable {
    case unlock, diagnostics, restore, presets, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlock: return L("One-Tap Unlock")
        case .diagnostics: return L("Advanced & Diagnostics")
        case .restore: return L("Backups")
        case .presets: return L("Feature Categories")
        case .advanced: return L("Tools")
        }
    }

    var subtitle: String {
        switch self {
        case .unlock: return L("Apple Intelligence & Region")
        case .diagnostics: return L("Compatibility")
        case .restore: return L("Restore pre-unlock state")
        case .presets: return L("Personalization")
        case .advanced: return L("All tools")
        }
    }

    var symbol: String {
        switch self {
        case .unlock: return "lock.open.fill"
        case .diagnostics: return "stethoscope"
        case .restore: return "clock.arrow.circlepath"
        case .presets: return "square.grid.2x2"
        case .advanced: return "slider.horizontal.3"
        }
    }

    // Keep newly introduced sections visible when opening saved settings from
    // an older build; never trust stored values as arbitrary navigation routes.
    static func resolvedOrder(_ raw: String) -> [DashboardV3Destination] {
        let saved = raw.split(separator: ",").compactMap { DashboardV3Destination(rawValue: String($0)) }
        var unique: [DashboardV3Destination] = []
        for item in saved where !unique.contains(item) { unique.append(item) }
        for item in allCases where !unique.contains(item) { unique.append(item) }
        return unique
    }
}

/// The 3.0 home, restructured (Phase D) into eight sections that show
/// summaries only — the full cards live on the destination pages:
///
/// 1. Device overview — the read / re-read card (inline, unchanged).
/// 2. Common features — the user's favorites from the unified
///    catalog (at most three), or the three preset groups when there
///    are no favorites yet. Each tile opens its destination page.
/// 3. China one-tap unlock — eSIM / region / AI summary, opens the
///    unlock page.
/// 4. Apple Intelligence & eSIM — AI readiness summary, opens the
///    unlock page (that page holds both the one-tap card and the
///    AI / eSIM cards).
/// 5. Security diagnosis — health score and simulation summary,
///    opens the diagnostics page.
/// 6. Backup & restore — backup count, opens the restore page.
/// 7. Preset management — favorites count, opens the presets page.
/// 8. More tools — opens the tools page.
///
/// The section order follows the user's destination order
/// (`HomeSectionID.resolvedSections`): reordering destinations in
/// the Sort sheet reorders sections 3–8 with them. Summaries show
/// "Unknown" / "Not read yet" when the device has not been read —
/// never a fabricated state. Layout uses `GlassTokens` throughout
/// (one source of truth for radii, spacing, padding, icon sizes and
/// text styles); the app follows the system appearance, and Dynamic
/// Type collapses the grids to one column at accessibility sizes so
/// text wraps instead of overlapping or clipping.
struct DashboardV3Home<DestinationView: View>: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("LilaShift.v3.dashboardOrder") private var savedOrder = ""
    @State private var showingReorder = false
    @State private var favoriteIDs: [String] = []
    @State private var catalogSettings = FeatureCatalogSettings.defaults
    let destination: (DashboardV3Destination) -> DestinationView

    /// The eight sections in display order.
    private var orderedSections: [HomeSectionID] {
        HomeSectionID.resolvedSections(savedOrder)
    }

    /// The destination-backed sections (3–8), in display order.
    private var destinationSections: [HomeSectionID] {
        orderedSections.filter { $0.destination != nil }
    }

    /// The common-features tiles: the user's favorites, ordered by
    /// the single catalog rule (favorites first, then custom order,
    /// then recent use, then category order), at most three — or the
    /// three preset groups when there are no favorites yet.
    private var commonItems: [FeatureCatalogItem] {
        guard !favoriteIDs.isEmpty else {
            return FeatureCatalog.presetItems.filter { item in
                PresetCatalog.entry(for: item.id)?.kind == .group
            }
        }
        let ordered = FeatureCatalog.apply(
            FeatureCatalog.allItems, query: "", category: nil, riskLevel: nil,
            settings: catalogSettings, catalogSort: .byCategory,
            favoritesFirst: true, favoriteIDs: Set(favoriteIDs))
        return Array(ordered.filter { $0.kind == .preset }.prefix(3))
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: GlassTokens.gridSpacing)]
            : [GridItem(.flexible(), spacing: GlassTokens.gridSpacing),
               GridItem(.flexible(), spacing: GlassTokens.gridSpacing)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.sectionSpacing) {
                deviceOverviewSection
                commonFeaturesSection
                ForEach(destinationSections) { section in
                    homeSectionBlock(section)
                }
                Text(L("Device-specific results are available after reading the device."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(GlassTokens.pageMargin)
        }
        .background(GlassBackground())
        .navigationTitle("LilaShift 3.0")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingReorder = true
                } label: {
                    Label(L("Sort"), systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .onAppear { reloadFavorites(); reloadCatalogSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .featureCatalogSettingsDidChange)) { _ in
            reloadCatalogSettings()
        }
        .sheet(isPresented: $showingReorder) {
            NavigationStack {
                List {
                    ForEach(DashboardV3Destination.resolvedOrder(savedOrder)) { section in
                        Label(section.title, systemImage: section.symbol)
                    }
                    .onMove { offsets, destination in
                        var sections = DashboardV3Destination.resolvedOrder(savedOrder)
                        sections.move(fromOffsets: offsets, toOffset: destination)
                        savedOrder = sections.map(\.rawValue).joined(separator: ",")
                    }
                }
                .environment(\.editMode, .constant(EditMode.active))
                .navigationTitle(L("Sort"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L("Reset")) { savedOrder = "" }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("Done")) { showingReorder = false }
                    }
                }
            }
        }
    }

    // MARK: - Section 1: device overview

    private var deviceOverviewSection: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
                Label(L("Device Overview"), systemImage: "iphone")
                    .font(GlassTokens.cardTitleFont)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.hasDocument ? model.displayedName : UIDevice.current.model)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(model.hasDocument ? L("Device connected") : L("Device not read yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.changeCount > 0 {
                    Label(String(format: L("%d changes"), model.changeCount),
                          systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                Button {
                    Task { await model.connect() }
                } label: {
                    Label(model.isBusy ? L("Reading…") : (model.hasDocument ? L("Read Again") : L("Read Device")),
                          systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy || model.changeCount > 0)
            }
            .padding(GlassTokens.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section 2: common features

    private var commonFeaturesSection: some View {
        VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            homeSectionHeader(.commonFeatures)
            LazyVGrid(columns: columns, spacing: GlassTokens.gridSpacing) {
                ForEach(commonItems) { item in
                    NavigationLink {
                        destination(item.destination)
                    } label: {
                        GlassCard(cornerRadius: GlassTokens.tileRadius) {
                            GlassCategoryTile(
                                title: item.chineseName,
                                detail: item.englishTitle,
                                symbol: item.symbol,
                                tint: .gestaltAccent
                            )
                            .frame(maxWidth: .infinity, minHeight: GlassTokens.tileMinHeight, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if favoriteIDs.isEmpty {
                Text(L("No favorites yet. The three preset groups are shown instead."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sections 3–8: destination summaries

    private func homeSectionHeader(_ section: HomeSectionID) -> some View {
        VStack(alignment: GlassTokens.cardAlignment, spacing: 2) {
            Label(section.title, systemImage: section.symbol)
                .font(GlassTokens.cardTitleFont)
            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(GlassTokens.cardSubtitleFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One destination section: its header (title + description)
    /// plus a full-width summary tile that opens the page. The tile
    /// shows the live summary when the device has been read, and
    /// the section description otherwise — never a fabricated
    /// state. Text wraps; nothing is truncated.
    private func homeSectionBlock(_ section: HomeSectionID) -> some View {
        VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            homeSectionHeader(section)
            if let page = section.destination {
                NavigationLink {
                    destination(page)
                } label: {
                    GlassCard(cornerRadius: GlassTokens.tileRadius) {
                        HStack(spacing: GlassTokens.gridSpacing) {
                            GlassIconPedestal(systemImage: section.symbol, tint: .gestaltAccent, size: GlassTokens.iconSize)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title)
                                    .font(GlassTokens.cardTitleFont)
                                    .foregroundStyle(.primary)
                                if let summary = summaryText(for: section) {
                                    Text(summary)
                                        .font(GlassTokens.cardSubtitleFont)
                                        .foregroundStyle(.secondary)
                                } else if let subtitle = section.subtitle {
                                    Text(subtitle)
                                        .font(GlassTokens.cardSubtitleFont)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(GlassTokens.tilePadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The one-line live summary for a section, or `nil` when there
    /// is nothing honest to show yet (device not read, no favorites).
    /// The caller then shows the section description instead.
    private func summaryText(for section: HomeSectionID) -> String? {
        switch section {
        case .deviceOverview, .commonFeatures, .moreTools:
            return nil
        case .chinaUnlock:
            guard model.hasDocument else { return nil }
            return "\(L("eSIM")): \(esimStatusText) · \(L("Region Code")): \(model.previewRegionCode ?? L("Not read yet")) · \(L("Apple Intelligence")): \(model.chinaUnlockAIEnabledCount)/\(ChinaUnlock.aiCapabilities.count)"
        case .appleIntelligenceEsim:
            guard let checkup = model.aiReadinessCheckup else {
                return model.hasDocument ? L("Unknown") : nil
            }
            return String(format: L("Ready %d/4"), checkup.readyCount)
        case .securityDiagnosis:
            guard model.hasDocument else { return nil }
            let health = diagnostics?.healthScore?.overallScore.map { "\(L("Health Score")): \($0)" }
            let simulation = diagnostics?.oneTapSimulation.map {
                "\(L("Simulation")): \($0.canProceed ? L("Passed") : L("Blocked"))"
            }
            let parts = [health, simulation].compactMap { $0 }
            if parts.isEmpty { return L("Unknown") }
            return parts.joined(separator: " · ")
        case .backupRestore:
            guard model.hasDocument else { return nil }
            if model.backups.isEmpty { return L("No backups stored yet.") }
            return "\(model.backups.count) \(L("Backups"))"
        case .presetManagement:
            guard !favoriteIDs.isEmpty else { return nil }
            return "\(favoriteIDs.count) \(L("Favorites"))"
        }
    }

    private var esimStatusText: String {
        guard let flags = model.previewESIMFlags else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private func reloadFavorites() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            favoriteIDs = []
            return
        }
        let store = PresetFavoritesStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        favoriteIDs = store.load().ids
    }

    private func reloadCatalogSettings() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            catalogSettings = .defaults
            return
        }
        let store = FeatureCatalogSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        catalogSettings = store.load().settings
    }
}
