// SPDX-License-Identifier: GPL-3.0-only
// System Health Score (系统健康评分) — read-only SwiftUI display.
//
// Shows the overall score and the four dimension scores, each with
// its reasons. The card always carries the disclaimer: the score is
// a diagnostic summary only, never a guarantee of safety or that a
// feature will work. It never writes anything: the score is computed
// from the current snapshot, the backup inventory (with read-only
// verification), a one-tap SafePatch simulation, the persisted
// change records and the Modified Values report.
import SwiftUI

struct SystemHealthScoreCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [RecordedChange] = []
    @State private var historyError: String?
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The report for the current snapshot, or `nil` when the device
    /// has not been read yet.
    private var healthScore: SystemHealthScore? {
        guard model.snapshot != nil else { return nil }
        let report = LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: records.count)
        let verifications = RestoreIntelligence.verifyBackups(model.backups, against: model.working)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: model.snapshot,
            currentDocument: model.working, backups: model.backups)
        return SystemHealthScorer.score(
            profile: report.profile, snapshot: model.snapshot,
            backups: model.backups, backupVerifications: verifications,
            simulation: simulation, recordedChanges: records,
            externalModificationCount: externalModificationCount)
    }

    /// Fields the Modified Values report found changed, minus the
    /// keys this app recorded: what remains was modified outside
    /// this app's records. The match is by key string (rows carry
    /// no layer); the known keys do not collide across layers.
    private var externalModificationCount: Int {
        let recordedKeys = Set(records.map(\.key))
        return ModifiedValues.report(for: model.snapshot).rows
            .filter { !recordedKeys.contains($0.key) }.count
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "heart.text.square", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("System Health Score"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Cache, compatibility, backup and modification risk, from real readings only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.snapshot == nil {
                    Text(L("Read the device first to score its health."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else if let healthScore {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let overall = healthScore.overallScore {
                            Text("\(overall)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("/ 100 · \(healthScore.overallLevel.title)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(L("Unknown"))
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(healthScore.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(healthScore.dimensions) { dimension in
                        HStack(spacing: 8) {
                            Text(dimension.dimension.title)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let score = dimension.score {
                                Text("\(score)")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Text("· \(dimension.level.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(L("Unknown"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                        showingDetails.toggle()
                    }
                    .font(.subheadline)

                    if showingDetails {
                        ForEach(healthScore.dimensions) { dimension in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dimension.dimension.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                ForEach(Array(dimension.reasons.enumerated()), id: \.offset) { _, reason in
                                    Text("• \(reason)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let historyError {
                        Text(historyError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(SystemHealthScore.disclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { reloadHistory() }
        .onChange(of: model.working != nil) { _, _ in reloadHistory() }
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
}
