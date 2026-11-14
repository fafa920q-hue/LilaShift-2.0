// SPDX-License-Identifier: GPL-3.0-only
// Smart Fault Diagnosis (智能故障诊断) — read-only SwiftUI display.
//
// Shows what went wrong, the most likely cause, and what to try next,
// from real readings only: the device profile, the health score, the
// fingerprint comparison, the acceptance report, backup verification
// and the eligibility evaluations. A diagnosis whose cause is not
// known says so plainly ("Cause not yet determined") with what was
// observed — it never invents a cause. A suggested fix is a
// suggestion, never a guarantee, and the card always carries that
// disclaimer. The card never writes anything: it only reads the same
// inputs the other cards already compute.
//
// Structured operation events are supplied when the manager
// recorded them this session (reads and backups since P4); write,
// restore and guard events are not connected yet, so the report
// says so when none were recorded. The diagnosis still covers
// everything the other inputs can show. The "I restarted" toggle
// mirrors the acceptance card: the region-reverted diagnosis only
// fires after a confirmed restart.
import SwiftUI

struct SmartFaultDiagnosisCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [RecordedChange] = []
    @State private var historyError: String?
    @State private var storedFingerprint: DeviceFingerprint?
    @State private var fingerprintError: String?
    @State private var restartConfirmed = false
    @State private var showingDetails = false
    /// Structured operation events recorded this session (reads and
    /// backups). Write, restore and guard events are not connected
    /// yet — see `OperationEventRecorder` — so the report says so
    /// when none were recorded.
    @State private var recordedEvents: [OperationEvent] = []

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

    /// The stored fingerprint to use: the cache's when present.
    private var effectiveStoredFingerprint: DeviceFingerprint? {
        diagnostics?.storedFingerprint ?? storedFingerprint
    }

    /// The history error to display: the cache's when present.
    private var displayedHistoryError: String? {
        diagnostics?.historyError ?? historyError
    }

    /// The fingerprint error to display: the cache's when present.
    private var displayedFingerprintError: String? {
        diagnostics?.fingerprintError ?? fingerprintError
    }

    /// The per-device report (profile + eligibility evaluations), or
    /// `nil` when the device has not been read yet. Prefers the
    /// shared diagnostics cache over recomputing on every body
    /// evaluation; falls back to direct computation when no cache is
    /// provided (for example the SwiftUI snapshot tests).
    private var deviceReport: LilaDeviceReport? {
        if let cached = diagnostics?.deviceReport { return cached }
        guard model.snapshot != nil else { return nil }
        return LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: effectiveRecords.count)
    }

    /// The health score, computed exactly like the health card: the
    /// same profile, snapshot, backup verifications, one-tap
    /// simulation, recorded changes and external modifications.
    /// Prefers the shared cache; the direct computation is only the
    /// fallback for a render without the cache.
    private var healthScore: SystemHealthScore? {
        if let cached = diagnostics?.healthScore { return cached }
        guard let report = deviceReport else { return nil }
        let verifications = RestoreIntelligence.verifyBackups(model.backups, against: model.working)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: model.snapshot,
            currentDocument: model.working, backups: model.backups)
        return SystemHealthScorer.score(
            profile: report.profile, snapshot: model.snapshot,
            backups: model.backups, backupVerifications: verifications,
            simulation: simulation, recordedChanges: effectiveRecords,
            externalModificationCount: externalModificationCount)
    }

    /// Fields the Modified Values report found changed, minus the
    /// keys this app recorded: what remains was modified outside
    /// this app's records. Same definition as the health card.
    /// Prefers the cached count.
    private var externalModificationCount: Int {
        if let cached = diagnostics?.externalModificationCount { return cached }
        let recordedKeys = Set(effectiveRecords.map(\.key))
        return ModifiedValues.report(for: model.snapshot).rows
            .filter { row in !recordedKeys.contains(row.key) }.count
    }

    /// The current fingerprint from the latest read, or `nil` when
    /// the device has not been read yet. Prefers the cache.
    private var currentFingerprint: DeviceFingerprint? {
        if let cached = diagnostics?.currentFingerprint { return cached }
        guard let report = deviceReport else { return nil }
        return DeviceFingerprintCapture.capture(profile: report.profile, snapshot: model.snapshot)
    }

    private var fingerprintComparison: FingerprintComparison? {
        guard let stored = effectiveStoredFingerprint, let current = currentFingerprint else { return nil }
        return DeviceFingerprintCapture.compare(stored: stored, current: current)
    }

    /// The acceptance report for the recorded changes against the
    /// re-read document, with live-probe values where the probe
    /// answers. The region-reverted diagnosis only fires when the
    /// restart is confirmed here. The live-probe values come from
    /// the shared cache when present (read on a background task —
    /// the live Gestalt query can be slow); the acceptance comparison
    /// itself is cheap and stays in the card because it depends on
    /// the restart-confirmed toggle.
    private var acceptanceReport: AcceptanceReport {
        PostModificationAcceptance.accept(
            records: effectiveRecords, current: model.working,
            liveValues: diagnostics?.liveValues ?? PostModificationAcceptance.liveValues(for: effectiveRecords),
            restartConfirmed: restartConfirmed)
    }

    /// The diagnosis report, or `nil` when the device has not been
    /// read yet. Structured operation events recorded this session
    /// (reads and backups) are supplied; write, restore and guard
    /// events are not connected yet, so the report says so when
    /// none were recorded. The backup verifications come from the
    /// shared cache when present, so the backup files are not
    /// re-read and re-hashed on every body evaluation.
    private var diagnosisReport: FaultDiagnosisReport? {
        guard let report = deviceReport else { return nil }
        let verifications = diagnostics?.backupVerifications
            ?? RestoreIntelligence.verifyBackups(model.backups, against: model.working)
        return SmartFaultDiagnosis.diagnose(FaultDiagnosisInput(
            profile: report.profile,
            health: healthScore,
            fingerprintComparison: fingerprintComparison,
            acceptance: acceptanceReport,
            backupRecords: model.backups,
            backupVerifications: verifications,
            evaluations: report.evaluations,
            events: recordedEvents))
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "stethoscope", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Smart Fault Diagnosis"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("What went wrong, why, and what to try — from real readings only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.snapshot == nil {
                    Text(L("Read the device first to diagnose faults."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else if let diagnosisReport {
                    Toggle(L("I restarted the device after applying"), isOn: $restartConfirmed)
                        .font(.subheadline)

                    Text(diagnosisReport.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if diagnosisReport.hasIssues {
                        Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                            showingDetails.toggle()
                        }
                        .font(.subheadline)

                        if showingDetails {
                            ForEach(diagnosisReport.diagnoses) { diagnosis in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(diagnosis.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(diagnosis.severity.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(severityColor(diagnosis.severity))
                                    }
                                    Text(diagnosis.whatHappened)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(diagnosis.cause.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(L("Suggested fix") + ": " + diagnosis.suggestedFix)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !diagnosis.evidence.isEmpty {
                                        Text(L("Evidence"))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        ForEach(diagnosis.evidence.indices, id: \.self) { index in
                                            Text("• \(diagnosis.evidence[index])")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !diagnosisReport.eventsConnected {
                        Text(L("Write, restore and guard events are not recorded yet."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(FaultDiagnosisReport.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let displayedHistoryError {
                        Text(displayedHistoryError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if let displayedFingerprintError {
                        Text(displayedFingerprintError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear { reloadHistory(); reloadFingerprint(); reloadRecordedEvents() }
        .onChange(of: model.working != nil) { _, _ in reloadHistory(); reloadFingerprint(); reloadRecordedEvents() }
    }

    private func severityColor(_ severity: FaultSeverity) -> Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    private func reloadHistory() {
        // The shared cache owns the history load when it is present
        // (it reads the store on a background task); this disk read
        // is only the fallback for a render without the cache.
        guard diagnostics == nil else { return }
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

    /// Loads the structured operation events recorded this session
    /// from the manager's recorder. The recorder is an actor, so
    /// the read is async; the diagnosis recomputes when the events
    /// arrive.
    private func reloadRecordedEvents() {
        Task {
            recordedEvents = await model.operationEvents.recordedEvents()
        }
    }

    private func reloadFingerprint() {
        // The shared cache owns the fingerprint load when it is
        // present (background task); this disk read is only the
        // fallback for a render without the cache.
        guard diagnostics == nil else { return }
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            storedFingerprint = nil
            fingerprintError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = DeviceFingerprintStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            storedFingerprint = try store.load()
            fingerprintError = nil
        } catch {
            storedFingerprint = nil
            fingerprintError = L("The device fingerprint could not be read. No system changes were made.")
        }
    }
}
