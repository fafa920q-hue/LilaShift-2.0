// SPDX-License-Identifier: GPL-3.0-only
// Post-Modification Auto-Acceptance (修改后自动验收) — read-only
// SwiftUI display.
//
// After the user restarts the device, compares each recorded
// modification against the re-read document and reports, per field,
// whether it was accepted, reverted, changed to something else, or
// could not be read. Fields that were not re-read are never claimed
// accepted. "Mark accepted as restart-verified" only sets a flag on
// history records whose items all accepted — it never writes to the
// MobileGestalt cache. The live probe is not connected yet, so
// acceptance is based on the file value only, and the card says so.
import SwiftUI

struct PostModificationAcceptanceCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [RecordedChange] = []
    @State private var historyError: String?
    @State private var restartConfirmed = false
    @State private var saveMessage: String?
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The acceptance report for the recorded changes against the
    /// re-read document. `model.working` is the document read after
    /// the restart; when it is `nil` every item is not re-read.
    private var acceptanceReport: AcceptanceReport {
        PostModificationAcceptance.accept(
            records: records, current: model.working,
            restartConfirmed: restartConfirmed)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "checkmark.seal", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Post-Modification Acceptance"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Re-read the device after a restart and check what actually stuck."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if records.isEmpty {
                    Text(L("No modifications have been recorded yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle(L("I restarted the device after applying"), isOn: $restartConfirmed)
                        .font(.subheadline)

                    let report = acceptanceReport
                    Text(report.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Text(String(format: L("%d accepted"), report.acceptedCount))
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(String(format: L("%d reverted"), report.revertedCount))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(String(format: L("%d not re-read"), report.notReReadCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !report.revertedKeys.isEmpty {
                        Text(String(format: L("Reverted: %@"), report.revertedKeys.joined(separator: ", ")))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                        showingDetails.toggle()
                    }
                    .font(.subheadline)

                    if showingDetails {
                        ForEach(report.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(item.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(item.outcome.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(outcomeColor(item.outcome))
                                }
                                Text(String(format: L("Target %@ · Now %@"), item.target.displayText, item.current?.displayText ?? L("Unknown")))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let liveAgrees = item.liveAgrees {
                                    Text(liveAgrees ? L("Live probe agrees with the staged value.") : L("Live probe disagrees with the staged value."))
                                        .font(.caption)
                                        .foregroundStyle(liveAgrees ? .green : .red)
                                }
                            }
                        }
                    }

                    if !report.restartVerifiedCandidateIDs.isEmpty {
                        Button(L("Mark accepted as restart-verified")) {
                            markRestartVerified(report.restartVerifiedCandidateIDs)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    }

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let historyError {
                        Text(historyError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text(AcceptanceReport.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(L("The live probe is not connected yet: acceptance is based on the file value only."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reloadHistory() }
        .onChange(of: model.working != nil) { _, _ in reloadHistory() }
    }

    private func outcomeColor(_ outcome: AcceptanceOutcome) -> Color {
        switch outcome {
        case .accepted: return .green
        case .reverted: return .red
        case .changed: return .orange
        case .unreadable, .notReRead: return .secondary
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

    /// Marks the given records restart-verified in history only:
    /// rebuilds each record with `restartVerified` set, and saves
    /// the history file. Never writes to the MobileGestalt cache.
    private func markRestartVerified(_ ids: [UUID]) {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            historyError = L("History is unavailable: no installation ID has been recorded yet.")
            return
        }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        let updated = records.map { record in
            RecordedChange(
                id: record.id, date: record.date, deviceID: record.deviceID,
                osBuild: record.osBuild, featureID: record.featureID,
                key: record.key, layer: record.layer, original: record.original,
                new: record.new, backupProvenance: record.backupProvenance,
                verified: record.verified,
                restartVerified: ids.contains(record.id) ? true : record.restartVerified)
        }
        do {
            try store.save(updated)
            records = updated
            saveMessage = L("Accepted changes marked restart-verified in history.")
            historyError = nil
        } catch {
            saveMessage = nil
            historyError = L("The change history could not be saved. No system changes were made.")
        }
    }
}
