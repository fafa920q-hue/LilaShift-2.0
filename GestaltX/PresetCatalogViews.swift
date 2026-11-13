// SPDX-License-Identifier: GPL-3.0-only
// Preset Catalog (智能预设数据库) — read-only SwiftUI display.
//
// Shows the preset catalog: Chinese names and descriptions, scope,
// minimum system, risk level with a specific reason, restore method
// and traceable evidence — plus search, filters, favorites and
// custom combinations. The catalog itself needs no device read: it
// is browsable before any read. Per-device eligibility is layered
// on top when a snapshot exists; without one every entry reads
// "unknown — read the device first".
//
// The card never writes to the MobileGestalt cache. Favorites and
// custom combinations are local-only app data (versioned JSON with
// a SHA-256 sidecar in the history directory). A custom combination
// is a PLAN: it is checked by the dependency analyzer and the
// SafePatch simulator, and the UI always says applying is not
// connected.
import SwiftUI

struct PresetCatalogCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var selectedCategory: PresetCategory?
    @State private var selectedRisk: CapabilityRiskLevel?
    @State private var selectedEligibility: FeatureEligibility?
    @State private var settings = PersonalizationSettings.defaults
    @State private var lastSavedSettings = PersonalizationSettings.defaults
    @State private var settingsError: String?
    @State private var expandedEntryID: String?
    @State private var records: [RecordedChange] = []
    @State private var historyError: String?

    @State private var favoriteIDs: [String] = []
    @State private var favoritesError: String?
    @State private var combinations: [PresetCombination] = []
    @State private var combinationsError: String?
    @State private var droppedMemberIDs: [String] = []

    @State private var showingCombinationForm = false
    @State private var newCombinationName = ""
    @State private var newCombinationMembers: Set<String> = []
    @State private var combinationFormError: String?

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The per-device report (profile + eligibility evaluations), or
    /// `nil` when the device has not been read yet.
    private var deviceReport: LilaDeviceReport? {
        guard model.snapshot != nil else { return nil }
        return LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: records.count)
    }

    /// Eligibility by feature id, from the device report. Empty when
    /// the device has not been read — every entry is then unknown.
    private var evaluations: [String: FeatureEligibility] {
        guard let report = deviceReport else { return [:] }
        var map: [String: FeatureEligibility] = [:]
        for evaluation in report.evaluations {
            map[evaluation.featureID] = evaluation.eligibility
        }
        return map
    }

    /// The visible entries: search, then filters, then the user's
    /// persisted catalog sort and favorites-first setting. The sort
    /// and the toggle live in the Personalization Center; this card
    /// applies them, so changing the setting takes effect here.
    private var visibleEntries: [PresetEntry] {
        let searched = PresetCatalog.search(searchText)
        let filtered = PresetCatalog.filtered(
            searched, category: selectedCategory, riskLevel: selectedRisk,
            eligibility: selectedEligibility, evaluations: evaluations)
        return PersonalizationCenter.sortedEntries(
            filtered, by: settings.catalogSort,
            favoriteIDs: Set(favoriteIDs), favoritesFirst: settings.favoritesFirst)
    }

    /// The dependency + simulation check for each saved combination,
    /// or empty when the device has not been read yet.
    private var combinationChecks: [UUID: PresetCombinationCheck] {
        guard let report = deviceReport else { return [:] }
        var checks: [UUID: PresetCombinationCheck] = [:]
        for combination in combinations {
            checks[combination.id] = PresetCombinationChecker.check(
                combination: combination, profile: report.profile,
                snapshot: model.snapshot, backups: model.backups)
        }
        return checks
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "books.vertical", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Preset Catalog"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Search, filter and save presets — from the catalog only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField(L("Search presets…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Picker(L("Category"), selection: $selectedCategory) {
                        Text(L("All")).tag(nil as PresetCategory?)
                        ForEach(PresetCategory.allCases) { category in
                            Text(category.title).tag(category as PresetCategory?)
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
                    Picker(L("Eligibility"), selection: $selectedEligibility) {
                        Text(L("All")).tag(nil as FeatureEligibility?)
                        Text(L("Native")).tag(FeatureEligibility.nativeSupported as FeatureEligibility?)
                        Text(L("Eligible")).tag(FeatureEligibility.eligibleToEnable as FeatureEligibility?)
                        Text(L("Unknown")).tag(FeatureEligibility.unknown as FeatureEligibility?)
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

                if model.snapshot == nil {
                    Text(L("Read the device first to see eligibility on this device."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if visibleEntries.isEmpty {
                    Text(L("No presets match this search."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleEntries) { entry in
                        PresetEntryRow(
                            entry: entry,
                            eligibility: PresetCatalog.eligibility(of: entry, evaluations: evaluations),
                            isFavorite: favoriteIDs.contains(entry.featureID),
                            isExpanded: expandedEntryID == entry.featureID,
                            onToggleFavorite: { toggleFavorite(entry.featureID) },
                            onToggleExpanded: {
                                expandedEntryID = expandedEntryID == entry.featureID ? nil : entry.featureID
                            })
                    }
                }

                Divider()

                PresetCombinationsSection(
                    combinations: combinations,
                    checks: combinationChecks,
                    deviceRead: model.snapshot != nil,
                    showingForm: $showingCombinationForm,
                    newName: $newCombinationName,
                    newMembers: $newCombinationMembers,
                    formError: combinationFormError,
                    onSaveCombination: saveCombination,
                    onDeleteCombination: deleteCombination)

                if let favoritesError {
                    Text(favoritesError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let settingsError {
                    Text(settingsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let combinationsError {
                    Text(combinationsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !droppedMemberIDs.isEmpty {
                    Text(String(format: L("%d members are no longer in the catalog."), droppedMemberIDs.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let historyError {
                    Text(historyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { reloadHistory(); reloadFavorites(); reloadCombinations(); reloadSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .personalizationSettingsDidChange)) { _ in
            reloadSettings()
        }
        .onChange(of: model.working != nil) { _, _ in
            reloadHistory(); reloadFavorites(); reloadCombinations()
        }
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

    private func saveCombination() {
        let error = PresetCombinationStore.validationError(
            name: newCombinationName, featureIDs: Array(newCombinationMembers))
        guard error == nil else {
            combinationFormError = error
            return
        }
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            combinationFormError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PresetCombinationStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let combination = PresetCombination(
            id: UUID(),
            name: newCombinationName.trimmingCharacters(in: .whitespacesAndNewlines),
            featureIDs: Array(newCombinationMembers).sorted(),
            createdAt: Date())
        var saved = combinations
        saved.append(combination)
        do {
            try store.save(saved)
            combinations = saved
            newCombinationName = ""
            newCombinationMembers = []
            showingCombinationForm = false
            combinationFormError = nil
        } catch {
            combinationFormError = L("The combinations could not be saved and verified. No system changes were made.")
        }
    }

    private func deleteCombination(_ id: UUID) {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            combinationsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PresetCombinationStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let remaining = combinations.filter { $0.id != id }
        do {
            try store.save(remaining)
            combinations = remaining
            combinationsError = nil
        } catch {
            combinationsError = L("The combinations could not be saved and verified. No system changes were made.")
        }
    }

    private func reloadHistory() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            historyError = L("History is unavailable: no installation ID has been recorded yet.")
            records = []
            return
        }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            records = try store.load()
            historyError = nil
        } catch {
            records = []
            historyError = L("The change history could not be read. No system changes were made.")
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

    private func reloadCombinations() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            combinations = []
            droppedMemberIDs = []
            combinationsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = PresetCombinationStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let loaded = store.load()
        combinations = loaded.combinations
        droppedMemberIDs = loaded.droppedMemberIDs
        combinationsError = loaded.error
    }

    /// Loads the persisted personalization settings (sort and
    /// favorites-first). The Personalization Center owns the
    /// settings UI; this card only applies them.
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

    /// Applies a settings change from this card (sort or
    /// favorites-first), persists it, and reverts the UI on a failed
    /// save instead of showing a setting that did not stick.
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

// MARK: - Entry row

private struct PresetEntryRow: View {
    let entry: PresetEntry
    let eligibility: FeatureEligibility
    let isFavorite: Bool
    let isExpanded: Bool
    let onToggleFavorite: () -> Void
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.chineseName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(entry.englishTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(eligibilityTitle(eligibility))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(eligibilityColor(eligibility))
                Text(riskTitle(entry.riskLevel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(riskColor(entry.riskLevel))
                Button(isExpanded ? L("Hide Details") : L("Show Details")) {
                    onToggleExpanded()
                }
                .font(.caption)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.chineseDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    detailRow(label: L("Applies to"),
                              value: entry.scope.label + " — " + entry.scopeNote)
                    detailRow(label: L("Minimum system"), value: entry.minSystem.label)
                    detailRow(label: L("Risk level"),
                              value: riskTitle(entry.riskLevel) + " — " + entry.riskReason)
                    detailRow(label: L("Restore method"), value: entry.restoreMethod)
                    if !entry.memberIDs.isEmpty {
                        detailRow(label: L("Members"),
                                  value: entry.memberIDs.joined(separator: ", "))
                    }
                    if !entry.dependencies.isEmpty {
                        detailRow(label: L("Dependencies"),
                                  value: entry.dependencies.joined(separator: ", "))
                    }
                    if !entry.conflicts.isEmpty {
                        detailRow(label: L("Conflicts"),
                                  value: entry.conflicts.joined(separator: ", "))
                    }
                    Text(entry.underlyingKeyOrSlot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L("Evidence"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    ForEach(entry.evidence.indices, id: \.self) { index in
                        let evidence = entry.evidence[index]
                        Text("• [\(evidence.kind.title)] \(evidence.text)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func eligibilityTitle(_ eligibility: FeatureEligibility) -> String {
        switch eligibility {
        case .nativeSupported: return L("Native")
        case .alreadyConfigured: return L("Configured")
        case .eligibleToEnable: return L("Eligible")
        case .unsupported: return L("Unsupported")
        case .unknown: return L("Unknown")
        case .conflict: return L("Conflict")
        }
    }

    private func eligibilityColor(_ eligibility: FeatureEligibility) -> Color {
        switch eligibility {
        case .nativeSupported: return .green
        case .alreadyConfigured: return .secondary
        case .eligibleToEnable: return .blue
        case .unsupported: return .orange
        case .unknown: return .secondary
        case .conflict: return .red
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
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Custom combinations section

private struct PresetCombinationsSection: View {
    let combinations: [PresetCombination]
    let checks: [UUID: PresetCombinationCheck]
    let deviceRead: Bool
    @Binding var showingForm: Bool
    @Binding var newName: String
    @Binding var newMembers: Set<String>
    let formError: String?
    let onSaveCombination: () -> Void
    let onDeleteCombination: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L("Custom Combinations"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(showingForm ? L("Cancel") : L("New Combination")) {
                    showingForm.toggle()
                }
                .font(.subheadline)
            }

            Text(L("This combination is a plan only. It is not connected to staging or applying."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showingForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L("Combination name"), text: $newName)
                        .textFieldStyle(.roundedBorder)
                    Text(L("Choose members"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    ForEach(PresetCatalog.all) { entry in
                        Button {
                            if newMembers.contains(entry.featureID) {
                                newMembers.remove(entry.featureID)
                            } else {
                                newMembers.insert(entry.featureID)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: newMembers.contains(entry.featureID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(newMembers.contains(entry.featureID)
                                                     ? .blue : .secondary)
                                Text(entry.chineseName)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(entry.englishTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let formError {
                        Text(formError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button(L("Save Combination")) {
                        onSaveCombination()
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }

            if combinations.isEmpty {
                Text(L("No combinations yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(combinations) { combination in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(combination.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(String(format: L("%d members"), combination.featureIDs.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L("Delete")) {
                                onDeleteCombination(combination.id)
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                        Text(combination.featureIDs.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let check = checks[combination.id] {
                            Text(L("Check Result") + ": " + check.analysis.verdict.title
                                 + " — " + check.simulationNote)
                                .font(.caption)
                                .foregroundStyle(check.canProceed ? .green : .orange)
                        } else if !deviceRead {
                            Text(L("Read the device first to see eligibility on this device."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
