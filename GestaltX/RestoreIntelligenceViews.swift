// SPDX-License-Identifier: GPL-3.0-only
// Restore Intelligence (智能恢复引擎) — read-only SwiftUI display
// plus restore actions wired ONLY to GestaltManager's existing
// restore paths.
//
// The card shows the modification timeline (recorded operations plus
// differences detected against the snapshot), the verification state
// of each stored backup, and — for each entry — a pre-restore Diff
// and the restore action. Restore execution goes only through the
// existing paths (`restore(_:)` for a full backup,
// `restoreCapability(_:)` for one capability,
// `restoreCacheOption()` for the eSIM flags, and the China Unlock
// group restores). Where no existing path covers an item, the action
// is preview-only with a clear "restore path not yet connected"
// state. A restore stages the revert; the user still applies it
// through the normal flow and verifies it after a restart — the
// timeline records the restore as staged, never as verified.
import SwiftUI

struct RestoreIntelligenceCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [RecordedChange] = []
    @State private var logCount = 0
    @State private var historyError: String?
    @State private var verifications: [BackupVerification] = []
    @State private var selectedEntry: RestoreTimelineEntry?
    @State private var selectedBackup: BackupRecord?
    @State private var showingAll = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The records to use: the cache's, when the cache is present
    /// (it loads the history on a background task), else this card's
    /// own (loaded on appear, the fallback for a render without the
    /// cache).
    private var effectiveRecords: [RecordedChange] {
        diagnostics?.records ?? records
    }

    /// The backup verifications to use: the cache's, when the cache
    /// is present (verified once per input change on a background
    /// task), else this card's own. This is what stops the backup
    /// files from being re-read and re-hashed on every body
    /// evaluation.
    private var effectiveVerifications: [BackupVerification] {
        diagnostics?.backupVerifications ?? verifications
    }

    /// The history error to display: the cache's when present.
    private var displayedHistoryError: String? {
        diagnostics?.historyError ?? historyError
    }

    private var timeline: [RestoreTimelineEntry] {
        guard let document = model.working else { return [] }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        return RestoreIntelligence.timeline(
            records: effectiveRecords, snapshot: model.snapshot?.document,
            current: document, layout: layout)
    }

    /// The unified history & restore entries: the timeline rows plus
    /// the staged value, the restore eligibility and the backup
    /// verification state for each entry, from the same data. Keyed
    /// by timeline entry id, so the rows below stay in timeline
    /// order.
    private var unifiedEntriesByID: [UUID: UnifiedHistoryEntry] {
        guard let document = model.working else { return [:] }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        var map: [UUID: UnifiedHistoryEntry] = [:]
        for entry in HistoryRestoreSummary.unifiedEntries(
            timeline: timeline, records: effectiveRecords,
            snapshot: model.snapshot?.document, working: document,
            layout: layout, verifications: effectiveVerifications) {
            map[entry.id] = entry
        }
        return map
    }

    private var visibleEntries: [RestoreTimelineEntry] {
        showingAll ? timeline : Array(timeline.prefix(5))
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "clock.arrow.circlepath", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Restore Intelligence"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Modification timeline and precise restore, from trusted records only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.working == nil {
                    Text(L("Read the device first to see the modification timeline."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    if let displayedHistoryError {
                        Text(displayedHistoryError)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    timelineSection
                    backupSection
                    if logCount > 0 {
                        Text(String(format: L("Restore log: %d entries"), logCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(L("The first-read value is the first-recorded value, never a factory original. Fields with no trusted original never offer a precise restore."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { reloadHistory() }
        .onChange(of: model.working != nil) { _, _ in reloadHistory() }
        .sheet(item: $selectedEntry) { entry in
            RestoreEntryDetailView(entry: entry, records: effectiveRecords,
                                   verifications: effectiveVerifications,
                                   deviceDisplayName: model.displayedName) {
                reloadHistory()
            }
        }
    }

    private func reloadHistory() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            historyError = L("History is unavailable: no installation ID has been recorded yet.")
            records = []
            verifications = []
            return
        }
        // The shared cache owns the history load and the backup
        // verification when it is present (both run on a background
        // task); skip them here and only load the restore-log count,
        // which is card-specific. The disk reads below are only the
        // fallback for a render without the cache.
        if diagnostics == nil {
            let store = ChangeRecordStore(
                directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
            do {
                records = try store.load()
                historyError = nil
            } catch {
                records = []
                historyError = L("The change history could not be read. No system changes were made.")
            }
            verifications = RestoreIntelligence.verifyBackups(model.backups, against: model.working)
        }
        let logStore = RestoreLogStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        logCount = (try? logStore.load().count) ?? 0
    }

    /// The unified history & restore section: one row per entry
    /// showing the first-recorded value, the current value, the
    /// staged value (when the working document differs from the
    /// first read), the restore state and whether a verified backup
    /// is on file. The first-recorded value is never labelled as a
    /// factory original. Tapping a row opens the restore preview
    /// for that entry.
    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("History & Restore"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if timeline.isEmpty {
                Text(L("No modifications recorded and no differences detected."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    Button { selectedEntry = entry } label: {
                        timelineRow(entry, unified: unifiedEntriesByID[entry.id])
                    }
                    .buttonStyle(.plain)
                }
                if timeline.count > 5 {
                    Button(showingAll ? L("Show Less") : L("Show All")) {
                        showingAll.toggle()
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: RestoreTimelineEntry, unified: UnifiedHistoryEntry?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L(entry.title))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !entry.isRecordedOperation {
                        Text(L("Detected"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(entry.original.displayText)
                    Text("→")
                    Text(entry.current?.displayText ?? L("Unknown"))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let staged = unified?.stagedValue {
                    HStack(spacing: 4) {
                        Text(L("Staged value") + ": " + staged.displayText)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                }
                HStack(spacing: 4) {
                    Text(entry.provenanceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.restartVerified {
                        Text(L("Restart verified"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let unified {
                        Text(unified.autoRestorable ? L("Can restore") : L("Cannot restore automatically"))
                            .font(.caption)
                            .foregroundStyle(unified.autoRestorable ? .green : .secondary)
                    }
                }
            }
            Spacer()
            Text(statusLabel(entry.status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(entry.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(entry.status).opacity(0.12), in: Capsule())
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Backup Verification"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if effectiveVerifications.isEmpty {
                Text(L("No backups stored yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(effectiveVerifications, id: \.record.id) { verification in
                    HStack(spacing: 8) {
                        Image(systemName: verification.status == .verified
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(verification.status == .verified ? .green : .red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verification.record.filename)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(backupStatusText(verification))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if verification.status == .verified {
                            Button(L("Restore")) {
                                selectedBackup = verification.record
                            }
                            .buttonStyle(GlassPrimaryButtonStyle())
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(item: $selectedBackup) { record in
            FullBackupRestoreView(record: record, verifications: effectiveVerifications,
                                  deviceDisplayName: model.displayedName) { reloadHistory() }
        }
    }

    private func statusLabel(_ status: RestoreTimelineStatus) -> String {
        switch status {
        case .restored: return L("Restored")
        case .pending: return L("In effect")
        case .changed: return L("Changed")
        case .unknown: return L("Unknown")
        }
    }

    private func statusColor(_ status: RestoreTimelineStatus) -> Color {
        switch status {
        case .restored: return .green
        case .pending: return .orange
        case .changed: return .red
        case .unknown: return .secondary
        }
    }

    private func backupStatusText(_ verification: BackupVerification) -> String {
        switch verification.status {
        case .verified:
            if let layoutMatches = verification.layoutMatchesCurrent {
                return layoutMatches
                    ? L("Verified. Cache layout matches this device.")
                    : L("Verified, but the cache layout differs from this device.")
            }
            return L("Verified.")
        case .failed(let reason):
            return reason
        case .notFound:
            return L("Backup file not found.")
        }
    }
}

// MARK: - Entry detail + pre-restore preview

private struct RestoreEntryDetailView: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    let entry: RestoreTimelineEntry
    let records: [RecordedChange]
    let verifications: [BackupVerification]
    let deviceDisplayName: String
    let onRestored: () -> Void
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    /// The second-confirmation gate: the first tap on Restore only
    /// arms it and shows the confirmation alert; only the second
    /// tap (Confirm Restore) executes.
    @State private var confirmation = TwoStepConfirmation()
    @State private var showingRestoreConfirmation = false

    /// The recorded change behind this entry, or a synthesized
    /// unverified change for a detected difference (which the
    /// eligibility checker correctly refuses to auto-restore).
    private var change: RecordedChange {
        if let recorded = records.first(where: { $0.id == entry.id }) { return recorded }
        return RecordedChange(
            id: entry.id, date: entry.date,
            deviceID: RestoreIntelligence.installationDeviceID ?? "",
            osBuild: SystemDeviceIdentitySource().osBuild ?? "",
            featureID: entry.featureID, key: entry.key, layer: entry.layer,
            original: entry.original, new: entry.current ?? entry.target,
            backupProvenance: entry.provenance, verified: false,
            restartVerified: false)
    }

    private var preview: RestorePreview? {
        guard let document = model.working else { return nil }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        return RestorePreviewBuilder.build(
            changes: [change], records: [:], current: document, layout: layout)
    }

    /// The pre-restore checklist: device identity, file integrity,
    /// backup source, current system compatibility, and the
    /// before/after diff (the diff itself lives in `previewSection`
    /// below). Anything unverifiable is shown as unknown, never as
    /// a pass.
    private var checklist: RestorePreviewChecklist? {
        guard let document = model.working,
              let item = preview?.items.first else { return nil }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        return RestorePreviewChecklistBuilder.build(
            change: change, item: item, verifications: verifications,
            deviceID: RestoreIntelligence.installationDeviceID,
            deviceDisplayName: deviceDisplayName,
            current: document, layout: layout)
    }

    /// The honest label for the recorded value: a first-read value
    /// is the "first-recorded value", never a factory original. A
    /// trusted pre-change or factory value keeps the established
    /// "Original" label, qualified by the provenance label shown
    /// directly above it.
    private var originalLabel: String {
        entry.provenance == .firstRead ? L("First-recorded value") : L("Original")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(entry.title))
                            .font(.headline)
                        Text(entry.provenanceLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(originalLabel + ": " + entry.original.displayText)
                        Text("→")
                        Text(L("Current") + ": " + (entry.current?.displayText ?? L("Unknown")))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let checklist {
                        checklistSection(checklist)
                    }
                    if let item = preview?.items.first {
                        previewSection(item)
                    }
                    if let restoreMessage {
                        Text(restoreMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Restore Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close")) { dismiss() }
                }
            }
            .alert(L("Restore this change?"), isPresented: $showingRestoreConfirmation) {
                Button(L("Cancel"), role: .cancel) { confirmation.reset() }
                Button(L("Confirm Restore")) {
                    guard let item = preview?.items.first else { return }
                    Task { await performRestore(item) }
                }
            } message: {
                if let checklist {
                    Text(checklist.deviceDisplayName + " · " + checklist.backupSource
                         + "\n" + (checklist.beforeValue?.displayText ?? L("Unknown"))
                         + " → " + (checklist.afterValue?.displayText ?? L("Unknown")))
                }
            }
        }
    }

    @ViewBuilder
    private func checklistSection(_ checklist: RestorePreviewChecklist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Restore Preview"))
                .font(.subheadline.weight(.semibold))
            checklistRow(label: L("Device identity"),
                         value: checklist.deviceDisplayName + " — " + checklist.deviceIdentity,
                         ok: checklist.deviceMatches)
            checklistRow(label: L("File integrity"),
                         value: checklist.fileIntegrity,
                         ok: checklist.fileIntegrityOK)
            checklistRow(label: L("Backup source"),
                         value: checklist.backupSource,
                         ok: nil)
            checklistRow(label: L("System compatibility"),
                         value: checklist.systemCompatible,
                         ok: checklist.systemCompatibleOK)
            if !checklist.noCheckFailed {
                Text(L("A check failed. The restore cannot proceed until it is resolved."))
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func checklistRow(label: String, value: String, ok: Bool?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok == true ? "checkmark.circle.fill"
                  : ok == false ? "xmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(ok == true ? .green : ok == false ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ item: RestoreItemPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Pre-Restore Diff"))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                Text(L("Current") + ": " + (item.currentValue?.displayText ?? L("Unknown")))
                Text("→")
                Text(L("Restore to") + ": " + item.targetValue.displayText)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(item.reason)
                .font(.subheadline)
                .foregroundStyle(item.risk == .blocked ? .red : .orange)
            if !item.conflicts.isEmpty {
                ForEach(Array(item.conflicts.enumerated()), id: \.offset) { _, conflict in
                    Text(conflict)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            switch item.action {
            case .previewOnly(let reason):
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("Restore path not yet connected for this item."))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            case .capability(let capability):
                Text(String(format: L("This restores all %d keys of %@."), capability.keys.count, L(capability.title)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                restoreButton(item)
            case .cacheOption:
                Text(L("This restores both eSIM flags together."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                restoreButton(item)
            case .fullBackup, .chinaUnlock, .aiOnly, .esimRegion:
                restoreButton(item)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    /// The restore button: the first tap only arms the
    /// second-confirmation gate and shows the confirmation alert;
    /// the restore executes only from the alert's Confirm Restore.
    /// The button stays disabled when the preview forbids an
    /// automatic restore, or when a preview check failed (wrong
    /// device, unverified file, layout mismatch).
    @ViewBuilder
    private func restoreButton(_ item: RestoreItemPreview) -> some View {
        Button(L(isRestoring ? "Restoring…" : "Restore")) {
            if confirmation.request() {
                Task { await performRestore(item) }
            } else {
                showingRestoreConfirmation = true
            }
        }
        .buttonStyle(GlassPrimaryButtonStyle())
        .disabled(isRestoring || !item.autoRestorable || checklist?.noCheckFailed == false)
        .opacity(item.autoRestorable && checklist?.noCheckFailed != false ? 1 : 0.5)
    }

    /// Runs the restore through the existing GestaltManager path for
    /// this action, then records the operation and logs the outcome.
    /// A restore stages the revert; the user still applies it through
    /// the normal flow and verifies it after a restart.
    private func performRestore(_ item: RestoreItemPreview) async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false; confirmation.reset() }
        let staged: Bool
        switch item.action {
        case .fullBackup(let record):
            await model.restore(record)
            staged = true
        case .capability(let capability):
            await model.restoreCapability(capability)
            staged = true
        case .cacheOption:
            await model.restoreCacheOption()
            staged = true
        case .chinaUnlock:
            staged = model.restoreChinaUnlock()
        case .aiOnly:
            staged = model.restoreChinaAIOnly()
        case .esimRegion:
            staged = model.restoreChinaESIMRegion()
        case .previewOnly:
            staged = false
        }
        let deviceID = RestoreIntelligence.installationDeviceID ?? ""
        let osBuild = SystemDeviceIdentitySource().osBuild ?? ""
        if staged {
            let recorded = RecordedChange(
                id: UUID(), date: Date(), deviceID: deviceID, osBuild: osBuild,
                featureID: entry.featureID, key: entry.key, layer: entry.layer,
                original: entry.current ?? entry.target, new: entry.original,
                backupProvenance: entry.provenance, verified: false,
                restartVerified: false)
            _ = RestoreIntelligence.recordChange(recorded)
            let logEntry = RestoreLogEntry(
                id: UUID(), date: Date(), changeID: entry.id,
                featureID: entry.featureID, key: entry.key, layer: entry.layer,
                targetValue: entry.original, outcome: .restored,
                reason: L("Restore staged through the existing path. Apply and restart to verify."),
                restorePointID: nil, deviceID: deviceID, osBuild: osBuild)
            _ = RestoreIntelligence.logRestore(logEntry)
            restoreMessage = L("Restore staged. Apply it, then restart and re-read to verify.")
            onRestored()
        } else {
            let logEntry = RestoreLogEntry(
                id: UUID(), date: Date(), changeID: entry.id,
                featureID: entry.featureID, key: entry.key, layer: entry.layer,
                targetValue: entry.original, outcome: .failed,
                reason: L("The restore could not be staged."),
                restorePointID: nil, deviceID: deviceID, osBuild: osBuild)
            _ = RestoreIntelligence.logRestore(logEntry)
            restoreMessage = L("The restore could not be staged. No system changes were made.")
        }
    }
}

// MARK: - Full-backup restore

private struct FullBackupRestoreView: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    let record: BackupRecord
    let verifications: [BackupVerification]
    let deviceDisplayName: String
    let onRestored: () -> Void
    @State private var message: String?
    @State private var isRestoring = false
    /// The second-confirmation gate: the first tap on Restore
    /// Whole Backup only arms it and reveals the preview checklist
    /// below; only the second tap (Confirm Restore) executes.
    @State private var confirmation = TwoStepConfirmation()

    /// The pre-restore checklist for this backup file: device
    /// identity, file integrity of this exact file, backup source,
    /// current system compatibility. The diff is whole-file, so
    /// there is no single before/after value — the view says so.
    private var checklist: RestorePreviewChecklist {
        let layout = model.working.flatMap { try? MobileGestaltCacheLayout.resolve(in: $0) }
        return RestorePreviewChecklistBuilder.buildForBackup(
            record: record, verifications: verifications,
            deviceID: RestoreIntelligence.installationDeviceID,
            deviceDisplayName: deviceDisplayName,
            current: model.working, layout: layout)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(record.filename)
                        .font(.headline)
                    Text(String(format: L("Restores the whole device file from this backup (%@)."), record.provenance.displayLabel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L("This restores every field in the backup, not just one change."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    checklistSection(checklist)
                    if confirmation.armed {
                        Text(L("Check the preview above, then confirm to restore the whole backup."))
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Button(L("Confirm Restore")) {
                            Task { await executeRestore() }
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(isRestoring || !checklist.noCheckFailed)
                    } else {
                        Button(L(isRestoring ? "Restoring…" : "Restore Whole Backup")) {
                            // First tap only arms the gate and reveals
                            // the checklist + confirm button above.
                            _ = confirmation.request()
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(isRestoring)
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Restore Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func checklistSection(_ checklist: RestorePreviewChecklist) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Restore Preview"))
                .font(.subheadline.weight(.semibold))
            checklistRow(label: L("Device identity"),
                         value: checklist.deviceDisplayName + " — " + checklist.deviceIdentity,
                         ok: checklist.deviceMatches)
            checklistRow(label: L("File integrity"),
                         value: checklist.fileIntegrity,
                         ok: checklist.fileIntegrityOK)
            checklistRow(label: L("Backup source"),
                         value: checklist.backupSource,
                         ok: nil)
            checklistRow(label: L("System compatibility"),
                         value: checklist.systemCompatible,
                         ok: checklist.systemCompatibleOK)
            Text(L("Before / after") + ": " + L("The whole device file is replaced by the backup."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !checklist.noCheckFailed {
                Text(L("A check failed. The restore cannot proceed until it is resolved."))
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func checklistRow(label: String, value: String, ok: Bool?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok == true ? "checkmark.circle.fill"
                  : ok == false ? "xmark.circle.fill" : "questionmark.circle.fill")
                .foregroundStyle(ok == true ? .green : ok == false ? .red : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The actual restore, through the existing GestaltManager path.
    /// Reached only from Confirm Restore, after the preview was
    /// shown. A failed check disables the confirm button, so this
    /// never runs on a failed preview.
    private func executeRestore() async {
        guard !isRestoring, checklist.noCheckFailed else { return }
        isRestoring = true
        defer { isRestoring = false; confirmation.reset() }
        await model.restore(record)
        message = L("Restore staged. Apply it, then restart and re-read to verify.")
        onRestored()
    }
}
