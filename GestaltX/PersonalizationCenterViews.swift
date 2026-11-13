// SPDX-License-Identifier: GPL-3.0-only
// Personalization Center (个性化中心) — read-only SwiftUI display.
//
// Shows the user's custom presets (create / edit / delete, checked
// by the dependency analyzer and the SafePatch simulator) and the
// personalization settings (default catalog sort, favorites first,
// Tools page card visibility). The card never writes to the
// MobileGestalt cache: custom presets are plans saved locally, and
// the UI always says applying is not connected. Every setting shown
// here takes effect: the sort and favorites-first toggle order the
// catalog card, and the card-visibility toggles filter the Tools
// page grid (via the shared settings store and its change
// notification).
import SwiftUI

struct PersonalizationCenterCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var settings = PersonalizationSettings.defaults
    @State private var settingsError: String?
    @State private var lastSavedSettings = PersonalizationSettings.defaults

    @State private var records: [RecordedChange] = []
    @State private var presets: [CustomPreset] = []
    @State private var presetsError: String?
    @State private var droppedMemberIDs: [String] = []

    @State private var showingForm = false
    @State private var editingPresetID: UUID?
    @State private var formName = ""
    @State private var formDescription = ""
    @State private var formRisk = CapabilityRiskLevel.medium
    @State private var formRiskReason = ""
    @State private var formMembers: Set<String> = []
    @State private var formSearch = ""
    @State private var formError: String?
    @State private var deletingPresetID: UUID?

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

    /// The dependency + simulation check for each saved custom
    /// preset, or empty when the device has not been read yet.
    private var presetChecks: [UUID: PresetCombinationCheck] {
        guard let report = deviceReport else { return [:] }
        var checks: [UUID: PresetCombinationCheck] = [:]
        for preset in presets {
            checks[preset.id] = CustomPresetChecker.check(
                preset: preset, profile: report.profile,
                snapshot: model.snapshot, backups: model.backups)
        }
        return checks
    }

    /// The catalog entries offered as preset members, filtered by
    /// the form's search field.
    private var formMemberEntries: [PresetEntry] {
        PresetCatalog.search(formSearch)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "paintpalette", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Personalization Center"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Custom presets, catalog sort and Tools page cards — saved on this device only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsSection
                Divider()
                customPresetsSection
                Divider()
                wallpaperNoteSection

                if let settingsError {
                    Text(settingsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let presetsError {
                    Text(presetsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !droppedMemberIDs.isEmpty {
                    Text(String(format: L("%d members are no longer in the catalog."), droppedMemberIDs.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reloadHistory(); reloadSettings(); reloadPresets() }
        .onReceive(NotificationCenter.default.publisher(for: .personalizationSettingsDidChange)) { _ in
            reloadSettings()
        }
        .alert(L("Delete this custom preset?"), isPresented: Binding(
            get: { deletingPresetID != nil },
            set: { newValue in if !newValue { deletingPresetID = nil } }
        )) {
            Button(L("Cancel"), role: .cancel) { deletingPresetID = nil }
            Button(L("Delete"), role: .destructive) {
                if let id = deletingPresetID { deletePreset(id) }
                deletingPresetID = nil
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Personalization Settings"))
                .font(.headline)
                .foregroundStyle(.primary)

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

            Text(L("Tools Page Cards"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(L("Show or hide each card on the Tools page. The Personalization Center card itself always stays on this page."))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(PersonalizationCenter.allToolCardIDs, id: \.self) { cardID in
                Toggle(PersonalizationCenter.toolCardTitle(for: cardID), isOn: Binding(
                    get: { settings.visibleToolCards.contains(cardID) },
                    set: { newValue in
                        updateSettings { settings in
                            if newValue {
                                settings.visibleToolCards.insert(cardID)
                            } else {
                                settings.visibleToolCards.remove(cardID)
                            }
                        }
                    }
                ))
                .font(.subheadline)
            }
        }
    }

    /// Applies a settings change in memory, persists it, and keeps
    /// the last saved copy so a failed save reverts the UI instead
    /// of showing a setting that did not stick.
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

    // MARK: - Custom presets

    private var customPresetsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Custom Presets"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(showingForm ? L("Cancel") : L("New Custom Preset")) {
                    if showingForm {
                        clearForm()
                    } else {
                        showingForm = true
                    }
                }
                .font(.subheadline)
            }

            Text(L("Custom presets are plans only. They are not connected to staging or applying."))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showingForm {
                customPresetForm
            }

            if presets.isEmpty {
                Text(L("No custom presets yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presets) { preset in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(preset.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(String(format: L("%d members"), preset.memberIDs.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(L("Edit")) {
                                startEditing(preset)
                            }
                            .font(.caption)
                            Button(L("Delete")) {
                                deletingPresetID = preset.id
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                        }
                        if !preset.chineseDescription.isEmpty {
                            Text(preset.chineseDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text(L("Risk") + ": " + riskTitle(preset.riskLevel))
                                .font(.caption)
                                .foregroundStyle(riskColor(preset.riskLevel))
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preset.riskReason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let check = presetChecks[preset.id] {
                            Text(L("Check Result") + ": " + check.analysis.verdict.title
                                 + " — " + check.simulationNote)
                                .font(.caption)
                                .foregroundStyle(check.canProceed ? .green : .orange)
                        } else if model.snapshot == nil {
                            Text(L("Read the device first to check this preset."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var customPresetForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L("Preset Name"), text: $formName)
                .textFieldStyle(.roundedBorder)
            Text(String(format: L("%d of 32 characters"), formName.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(L("Description"), text: $formDescription)
                .textFieldStyle(.roundedBorder)
            Picker(L("Risk"), selection: $formRisk) {
                Text(L("Low")).tag(CapabilityRiskLevel.low)
                Text(L("Medium")).tag(CapabilityRiskLevel.medium)
                Text(L("High")).tag(CapabilityRiskLevel.high)
            }
            .pickerStyle(.menu)
            TextField(L("Risk Reason"), text: $formRiskReason)
                .textFieldStyle(.roundedBorder)
            TextField(L("Search presets…"), text: $formSearch)
                .textFieldStyle(.roundedBorder)
            Text(L("Choose members"))
                .font(.subheadline)
                .foregroundStyle(.primary)
            if formMemberEntries.isEmpty {
                Text(L("No presets match this search."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(formMemberEntries) { entry in
                    Button {
                        if formMembers.contains(entry.featureID) {
                            formMembers.remove(entry.featureID)
                        } else {
                            formMembers.insert(entry.featureID)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: formMembers.contains(entry.featureID)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(formMembers.contains(entry.featureID)
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
            }
            if let formError {
                Text(formError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button(editingPresetID == nil ? L("Save Custom Preset") : L("Save Changes")) {
                savePreset()
            }
            .buttonStyle(GlassPrimaryButtonStyle())
        }
    }

    private func startEditing(_ preset: CustomPreset) {
        editingPresetID = preset.id
        formName = preset.name
        formDescription = preset.chineseDescription
        formRisk = preset.riskLevel
        formRiskReason = preset.riskReason
        formMembers = Set(preset.memberIDs)
        formSearch = ""
        formError = nil
        showingForm = true
    }

    private func clearForm() {
        showingForm = false
        editingPresetID = nil
        formName = ""
        formDescription = ""
        formRisk = .medium
        formRiskReason = ""
        formMembers = []
        formSearch = ""
        formError = nil
    }

    private func savePreset() {
        let error = CustomPresetStore.validationError(
            name: formName, description: formDescription,
            riskReason: formRiskReason, featureIDs: Array(formMembers))
        guard error == nil else {
            formError = error
            return
        }
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            formError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = CustomPresetStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let preset = CustomPreset(
            id: editingPresetID ?? UUID(),
            name: formName.trimmingCharacters(in: .whitespacesAndNewlines),
            chineseDescription: formDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            riskLevel: formRisk,
            riskReason: formRiskReason.trimmingCharacters(in: .whitespacesAndNewlines),
            memberIDs: Array(formMembers).sorted(),
            createdAt: presets.first { $0.id == editingPresetID }?.createdAt ?? Date())
        var saved = presets
        if let index = saved.firstIndex(where: { $0.id == preset.id }) {
            saved[index] = preset
        } else {
            saved.append(preset)
        }
        do {
            try store.save(saved)
            presets = saved
            formError = nil
            clearForm()
        } catch {
            formError = L("The custom presets could not be saved and verified. No system changes were made.")
        }
    }

    private func deletePreset(_ id: UUID) {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            presetsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = CustomPresetStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let remaining = presets.filter { $0.id != id }
        do {
            try store.save(remaining)
            presets = remaining
            presetsError = nil
        } catch {
            presetsError = L("The custom presets could not be saved and verified. No system changes were made.")
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

    // MARK: - Wallpaper note

    /// Why wallpaper and launch-image management are not in this
    /// center: iOS offers no public API for either. The existing
    /// wallpaper-pack import and launch-image features are unchanged.
    private var wallpaperNoteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Wallpaper and Launch Images"))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(L("iOS offers no public API for an app to change the system wallpaper or another app's launch image. Save an image to Photos and set it manually."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Loading

    private func reloadHistory() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            records = []
            return
        }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        records = (try? store.load()) ?? []
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

    private func reloadPresets() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            presets = []
            droppedMemberIDs = []
            presetsError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = CustomPresetStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let loaded = store.load()
        presets = loaded.presets
        droppedMemberIDs = loaded.droppedMemberIDs
        presetsError = loaded.error
    }
}
