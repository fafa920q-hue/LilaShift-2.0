// SPDX-License-Identifier: GPL-3.0-only
// Dependency Analyzer (功能依赖分析器) — read-only SwiftUI display.
//
// Shows, for a selected proposal (one-tap, AI only, or eSIM &
// Region), the dependencies, conflicts and duplicate modifications
// the analyzer found, grouped by feature, plus the overall verdict.
// It never writes anything: the analysis reuses
// `DependencyResolver`, the eligibility evaluator and the SafePatch
// written-key expansion. Staging, if the user chooses it, goes
// through the existing stage paths only.
import SwiftUI

struct DependencyAnalyzerCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProposal: SafePatchProposal = SafePatchProposal.oneTap()
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The analysis for the selected proposal, or `nil` when the
    /// device has not been read yet.
    private var analysis: DependencyAnalysis? {
        guard model.snapshot != nil else { return nil }
        let report = LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups)
        return DependencyAnalyzer.analyze(
            featureIDs: selectedProposal.featureIDs,
            profile: report.profile, snapshot: model.snapshot,
            liveAIEnabled: report.profile.liveAIEnabled.value)
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "point.3.connected.trianglepath.dotted", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Dependency Analyzer"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Dependencies, conflicts and duplicates for a proposal, before you stage it."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.snapshot == nil {
                    Text(L("Read the device first to analyze a proposal."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else if let analysis {
                    Picker(L("Proposal"), selection: $selectedProposal) {
                        Text(L("One-Tap Unlock")).tag(SafePatchProposal.oneTap())
                        Text(L("AI Only")).tag(SafePatchProposal.aiOnly())
                        Text(L("eSIM & Region")).tag(SafePatchProposal.esimRegion())
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 6) {
                        Image(systemName: analysis.verdict == .safeToStage
                            ? "checkmark.circle.fill"
                            : analysis.verdict == .unknown ? "questionmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(analysis.verdict == .safeToStage ? .green
                                : analysis.verdict == .unknown ? .secondary : .red)
                        Text(analysis.verdict.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    Text(analysis.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                        showingDetails.toggle()
                    }
                    .font(.subheadline)

                    if showingDetails {
                        ForEach(selectedProposal.featureIDs, id: \.self) { featureID in
                            if let findings = analysis.perFeature[featureID], !findings.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(title(for: featureID))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    ForEach(findings) { finding in
                                        findingRow(finding)
                                    }
                                }
                            }
                        }
                        if let setFindings = analysis.perFeature[""], !setFindings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Across the selected set"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                ForEach(setFindings) { finding in
                                    findingRow(finding)
                                }
                            }
                        }
                    }
                    Text(L("Analysis only — nothing is staged or written here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: DependencyFinding) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: finding.severity == .blocker ? "xmark.circle.fill"
                : finding.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(finding.severity == .blocker ? .red
                    : finding.severity == .warning ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.kind == .dependency ? L("Dependency")
                    : finding.kind == .conflict ? L("Conflict") : L("Duplicate"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(finding.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The user-facing title for a feature id: the capability's
    /// title when it is one, the virtual feature's label otherwise.
    private func title(for featureID: String) -> String {
        switch featureID {
        case FeatureEligibilityEvaluator.esimFeatureID:
            return L("eSIM")
        case FeatureEligibilityEvaluator.regionCodeFeatureID:
            return L("Region code")
        case FeatureEligibilityEvaluator.wapiFeatureID:
            return L("WAPI")
        default:
            return Capability.all.first(where: { $0.id == featureID })?.title ?? featureID
        }
    }
}
