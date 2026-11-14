// SPDX-License-Identifier: GPL-3.0-only
// Feature Catalog browser (Phase E) — the searchable, filterable
// front end of the unified catalog (`FeatureCatalog`). View-layer
// only: it reads the catalog, the user's catalog settings and the
// favorites store, and writes only its own settings files. It never
// stages, writes, or reads the MobileGestalt cache.
//
// Eligibility is deliberately NOT shown here: the catalog is
// browsable before any device read, and per-device eligibility
// lives on the Preset Catalog card, which layers the device report
// on top. A row never claims a feature is available on this device.
import SwiftUI

struct FeatureCatalogView<DestinationView: View>: View {
    let destination: (DashboardV3Destination) -> DestinationView

    /// The shared diagnostics cache (nil when the view renders
    /// without it). Its device report is the ONLY source of
    /// per-device status here: the catalog stays browsable before
    /// any device read, and a row never claims a status the device
    /// has not been read for.
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?

    /// The unified compatibility status for one preset item, from
    /// the cached device report. `nil` when the device has not been
    /// read (no claim is shown), for page items (not a preset), and
    /// for group entries (no single feature id).
    private func statusDetail(for item: FeatureCatalogItem) -> CompatibilityStatusDetail? {
        guard item.kind == .preset, item.id != "modelNumber",
              let report = diagnostics?.deviceReport,
              let evaluation = report.evaluations.first(where: { $0.featureID == item.id }) else {
            return nil
        }
        return CompatibilityStatusResolver.resolve(
            featureID: evaluation.featureID, eligibility: evaluation.eligibility,
            reason: evaluation.reason, profile: report.profile,
            documentRead: true, working: nil,
            stagedFeatureIDs: diagnostics?.stagedFeatureIDs ?? [],
            pendingRestartFeatureIDs: diagnostics?.pendingRestartFeatureIDs ?? [],
            riskLevel: evaluation.riskLevel)
    }

    @State private var searchText = ""
    @State private var selectedCategory: FeatureCatalogCategory?
    @State private var selectedRisk: CapabilityRiskLevel?
    @State private var settings = PersonalizationSettings.defaults
    @State private var lastSavedSettings = PersonalizationSettings.defaults
    @State private var settingsError: String?
    @State private var catalogSettings = FeatureCatalogSettings.defaults
    @State private var catalogSettingsError: String?
    @State private var favoriteIDs: [String] = []
    @State private var favoritesError: String?
    @State private var expandedID: String?
    @State private var showingManage = false

    /// The visible items: the one pipeline (`FeatureCatalog.apply`)
    /// — hidden out, search, category and risk filters, then the
    /// single ordering rule.
    private var visibleItems: [FeatureCatalogItem] {
        FeatureCatalog.apply(
            FeatureCatalog.allItems, query: searchText,
            category: selectedCategory, riskLevel: selectedRisk,
            settings: catalogSettings, catalogSort: settings.catalogSort,
            favoritesFirst: settings.favoritesFirst,
            favoriteIDs: Set(favoriteIDs))
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
                HStack(spacing: GlassTokens.gridSpacing) {
                    GlassIconPedestal(systemImage: "books.vertical", tint: .gestaltAccent, size: GlassTokens.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Feature Catalog"))
                            .font(GlassTokens.cardTitleFont)
                            .foregroundStyle(.primary)
                        Text(L("Browse, search and organize every preset."))
                            .font(GlassTokens.cardSubtitleFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button(L("Manage")) { showingManage = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                }

                TextField(L("Search features…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Picker(L("Category"), selection: $selectedCategory) {
                        Text(L("All Categories")).tag(nil as FeatureCatalogCategory?)
                        ForEach(FeatureCatalogCategory.allCases) { category in
                            Text(category.title).tag(category as FeatureCatalogCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker(L("Risk"), selection: $selectedRisk) {
                        Text(L("All")).tag(nil as CapabilityRiskLevel?)
                        Text(L("Low")).tag(CapabilityRiskLevel.low as CapabilityRiskLevel?)
                        Text(L("Medium")).tag(CapabilityRiskLevel.medium as CapabilityRiskLevel?)
                        Text(L("High")).tag(CapabilityRiskLevel.high as CapabilityRiskLevel?)
                    }
                    .pickerStyle(.menu)
                }

                Picker(L("Catalog Sort"), selection: Binding(
                    get: { settings.catalogSort },
                    set: { newValue in updateSettings { $0.catalogSort = newValue } }
                )) {
                    ForEach(CatalogSort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.menu)

                Toggle(L("Favorites first"), isOn: Binding(
                    get: { settings.favoritesFirst },
                    set: { newValue in updateSettings { $0.favoritesFirst = newValue } }
                ))
                .font(.subheadline)

                if visibleItems.isEmpty {
                    Text(L("No features match this search."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleItems) { item in
                        catalogRow(item)
                    }
                }

                if let favoritesError {
                    Text(favoritesError).font(.caption).foregroundStyle(.red)
                }
                if let settingsError {
                    Text(settingsError).font(.caption).foregroundStyle(.red)
                }
                if let catalogSettingsError {
                    Text(catalogSettingsError).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .onAppear { reloadSettings(); reloadCatalogSettings(); reloadFavorites() }
        .onReceive(NotificationCenter.default.publisher(for: .personalizationSettingsDidChange)) { _ in
            reloadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureCatalogSettingsDidChange)) { _ in
            reloadCatalogSettings()
        }
        .sheet(isPresented: $showingManage) {
            FeatureCatalogManageView(
                settings: $catalogSettings,
                catalogSort: settings.catalogSort,
                favoritesFirst: settings.favoritesFirst,
                favoriteIDs: Set(favoriteIDs),
                save: saveCatalogSettings,
                restoreDefaults: {
                    saveCatalogSettings(.defaults)
                    catalogSettings = .defaults
                })
        }
    }

    @ViewBuilder
    private func catalogRow(_ item: FeatureCatalogItem) -> some View {
        switch item.kind {
        case .preset:
            presetRow(item)
        case .page:
            NavigationLink {
                destination(item.destination)
            } label: {
                catalogRowContent(item)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { recordUse(item.id) })
        }
    }

    private func presetRow(_ item: FeatureCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    toggleFavorite(item.id)
                } label: {
                    Image(systemName: favoriteIDs.contains(item.id) ? "star.fill" : "star")
                        .foregroundStyle(favoriteIDs.contains(item.id) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                Button {
                    recordUse(item.id)
                    expandedID = expandedID == item.id ? nil : item.id
                } label: {
                    catalogRowContent(item)
                }
                .buttonStyle(.plain)
            }
            if expandedID == item.id {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.chineseDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // The compatibility status, only when the device
                    // has been read. Before a read nothing is shown:
                    // a row never claims a status for an unread
                    // device. Group entries and the model-number
                    // virtual entry have no single status.
                    if let status = statusDetail(for: item) {
                        Text(L("Compatibility Status") + ": " + status.status.title
                             + " — " + status.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if status.status == .nativeSupported {
                            Text(L("Already supported on this device — no change needed."))
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        if status.status == .unsupported {
                            Text(L("Not offered on this device"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    if let entry = PresetCatalog.entry(for: item.id) {
                        Text(L("Risk level") + ": " + riskTitle(entry.riskLevel)
                             + " — " + entry.riskReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The shared row content: icon, Chinese name, English title,
    /// category and risk. Text wraps instead of truncating; the
    /// trailing chevron (pages) or disclosure (presets) is separate.
    private func catalogRowContent(_ item: FeatureCatalogItem) -> some View {
        HStack(spacing: 10) {
            GlassIconPedestal(systemImage: item.symbol, tint: .gestaltAccent, size: GlassTokens.iconSizeSmall)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.chineseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.englishTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let risk = item.riskLevel {
                Text(riskTitle(risk))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(riskColor(risk))
            }
            if item.kind == .page {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func riskTitle(_ risk: CapabilityRiskLevel) -> String {
        switch risk {
        case .low: return L("Low")
        case .medium: return L("Medium")
        case .high: return L("High")
        }
    }

    private func riskColor(_ risk: CapabilityRiskLevel) -> Color {
        switch risk {
        case .low: return GlassTokens.successColor
        case .medium: return GlassTokens.warningColor
        case .high: return GlassTokens.dangerColor
        }
    }

    private func recordUse(_ id: String) {
        let updated = FeatureCatalog.recordingUse(id, in: catalogSettings)
        guard updated != catalogSettings else { return }
        saveCatalogSettings(updated)
    }

    private func toggleFavorite(_ id: String) {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            favoritesError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PresetFavoritesStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            favoriteIDs = try store.toggle(id)
            favoritesError = nil
        } catch {
            favoritesError = L("The favorites could not be saved and verified. No system changes were made.")
        }
    }

    private func reloadFavorites() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            favoriteIDs = []
            favoritesError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PresetFavoritesStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let loaded = store.load()
        favoriteIDs = loaded.ids
        favoritesError = loaded.error
    }

    private func reloadCatalogSettings() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            catalogSettings = .defaults
            catalogSettingsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = FeatureCatalogSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let loaded = store.load()
        catalogSettings = loaded.settings
        catalogSettingsError = loaded.error
    }

    private func saveCatalogSettings(_ updated: FeatureCatalogSettings) {
        catalogSettings = updated
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            catalogSettingsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = FeatureCatalogSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            try store.save(updated)
            catalogSettingsError = nil
        } catch {
            catalogSettingsError = L("The settings could not be saved and verified. No system changes were made.")
        }
    }

    private func reloadSettings() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            settings = .defaults
            lastSavedSettings = .defaults
            settingsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PersonalizationSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let loaded = store.load()
        settings = loaded.settings
        lastSavedSettings = loaded.settings
        settingsError = loaded.error
    }

    private func updateSettings(_ change: (inout PersonalizationSettings) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            settings = lastSavedSettings
            settingsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PersonalizationSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            try store.save(updated)
            lastSavedSettings = updated
            settingsError = nil
        } catch {
            settings = lastSavedSettings
            settingsError = L("The settings could not be saved and verified. No system changes were made.")
        }
    }
}

// MARK: - Manage sheet

/// Drag reorder, hide / show and restore defaults for the catalog.
/// Every change saves immediately (like the dashboard reorder
/// sheet): there is no unsaved draft to lose. The list shows every
/// item in the current order, hidden ones included and marked, so
/// a hidden item can always be shown again from here.
private struct FeatureCatalogManageView: View {
    @Binding var settings: FeatureCatalogSettings
    let catalogSort: CatalogSort
    let favoritesFirst: Bool
    let favoriteIDs: Set<String>
    let save: (FeatureCatalogSettings) -> Void
    let restoreDefaults: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Every item in the current order (hidden included): the same
    /// single ordering rule, without search or category filters, so
    /// a drag reorder stores the full order.
    private var orderedItems: [FeatureCatalogItem] {
        HomeSorting.sortCatalogItems(
            FeatureCatalog.allItems, by: catalogSort,
            favoritesFirst: favoritesFirst, favoriteIDs: favoriteIDs,
            customOrder: settings.customOrder, recentIDs: settings.recentIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .foregroundStyle(Color.gestaltAccent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.chineseName)
                                .font(.subheadline.weight(.semibold))
                            Text(item.category.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button(settings.hiddenIDs.contains(item.id) ? L("Show") : L("Hide")) {
                            var updated = settings
                            if updated.hiddenIDs.contains(item.id) {
                                updated.hiddenIDs.remove(item.id)
                            } else {
                                updated.hiddenIDs.insert(item.id)
                            }
                            settings = updated
                            save(updated)
                        }
                        .font(.subheadline)
                        .frame(minHeight: GlassTokens.buttonMinHeight)
                    }
                    .opacity(settings.hiddenIDs.contains(item.id) ? 0.5 : 1)
                }
                .onMove { offsets, destination in
                    var ids = orderedItems.map(\.id)
                    ids.move(fromOffsets: offsets, toOffset: destination)
                    var updated = settings
                    updated.customOrder = ids
                    settings = updated
                    save(updated)
                }
            }
            .environment(\.editMode, .constant(EditMode.active))
            .navigationTitle(L("Custom Order"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("Restore Defaults")) { restoreDefaults() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
    }
}
