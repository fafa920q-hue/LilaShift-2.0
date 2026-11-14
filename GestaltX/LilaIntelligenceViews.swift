// SPDX-License-Identifier: GPL-3.0-only
// Lila Intelligence (紫序智能引擎) — read-only SwiftUI display.
//
// Shows the device profile and the per-feature eligibility the local
// rule engine derives from REAL readings of the current device,
// plus the China Unlock recommendation (eSIM + region + the six AI
// capabilities). Nothing here writes to the device, stages a change,
// or sends anything anywhere: the engine is local-only, and every
// reading that could not be made is shown as unknown, never
// fabricated.
import SwiftUI

struct LilaIntelligenceCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?
    @Environment(\.colorScheme) private var colorScheme
    @State private var recordCount = 0
    @State private var records: [RecordedChange] = []
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The report for the current snapshot, or `nil` when the device
    /// has not been read yet. Prefers the shared diagnostics cache
    /// (computed once per input change on a background task) over
    /// recomputing on every body evaluation; falls back to direct
    /// computation when no cache is provided (for example the SwiftUI
    /// snapshot tests, which only supply a GestaltManager), so the
    /// rendered output is identical either way.
    private var report: LilaDeviceReport? {
        if let cached = diagnostics?.deviceReport { return cached }
        guard model.snapshot != nil else { return nil }
        return LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: recordCount)
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "brain", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Lila Intelligence"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Personalized recommendations for this device, generated locally from real readings."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.working == nil {
                    Text(L("Read the device first to see personalized recommendations."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else if let report {
                    deviceSummary(report.profile)
                    eligibilitySummary(report)
                    recommendationSummary(report.chinaUnlockRecommendation)
                    if !report.evaluations.isEmpty {
                        Button(showingDetails ? L("Hide Details") : L("Show Details")) {
                            showingDetails.toggle()
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    }
                    if showingDetails {
                        detailsList(report.evaluations, profile: report.profile)
                    }
                    Text(L("Recommendations are generated on this device from its own readings. Nothing is sent anywhere."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { loadRecordCount() }
        .onChange(of: model.working != nil) { _, _ in loadRecordCount() }
    }

    private func loadRecordCount() {
        // The shared cache owns the record count when it is present
        // (it loads the history on a background task); this disk read
        // is only the fallback for a render without the cache.
        guard diagnostics == nil else { return }
        guard let deviceID = RestoreIntelligence.installationDeviceID else { return }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        records = (try? store.load()) ?? []
        recordCount = records.count
    }

    /// The records to use for restart-pending status: the cache's
    /// when present, else this card's own fallback load.
    private var effectiveRecords: [RecordedChange] {
        diagnostics?.records ?? records
    }

    /// Feature ids staged in the working document but not yet
    /// applied (snapshot vs working diff), and ids applied but not
    /// yet verified after a restart. Both come from existing data —
    /// the shared cache when present, else this card's own
    /// computation; eligibility itself is never recomputed here.
    private var stagedFeatureIDs: Set<String> {
        diagnostics?.stagedFeatureIDs ?? CompatibilityStatusResolver.stagedFeatureIDs(
            snapshot: model.snapshot, working: model.working)
    }

    private var pendingRestartFeatureIDs: Set<String> {
        diagnostics?.pendingRestartFeatureIDs ?? CompatibilityStatusResolver.pendingRestartFeatureIDs(records: effectiveRecords)
    }

    /// The unified compatibility status for one evaluation, from
    /// the report's own eligibility + reason and the staged /
    /// restart-pending sets above.
    private func statusDetail(for evaluation: LilaFeatureEvaluation,
                              profile: DeviceProfile) -> CompatibilityStatusDetail {
        CompatibilityStatusResolver.resolve(
            featureID: evaluation.featureID, eligibility: evaluation.eligibility,
            reason: evaluation.reason, profile: profile,
            documentRead: model.snapshot != nil, working: model.working,
            stagedFeatureIDs: stagedFeatureIDs,
            pendingRestartFeatureIDs: pendingRestartFeatureIDs,
            riskLevel: evaluation.riskLevel)
    }

    @ViewBuilder
    private func deviceSummary(_ profile: DeviceProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(profile.productType.value ?? L("Unknown device"))
                    .font(.subheadline.weight(.semibold))
                Text("•")
                    .foregroundStyle(.secondary)
                Text(profile.osVersion.value ?? L("Unknown OS"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(profile.osBuild.value ?? L("Unknown build"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text(L("Region") + ": " + (profile.regionCode.value ?? L("Unknown")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(L("Sales region") + ": " + (profile.salesRegionSuffix.value ?? L("Unknown")))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if profile.isNativeAppleIntelligence.value == true {
                Text(L("This device natively supports Apple Intelligence."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if profile.cacheLayout.value == nil {
                Text(L("The system cache layout could not be resolved, so CacheData checks are unavailable."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func eligibilitySummary(_ report: LilaDeviceReport) -> some View {
        HStack(spacing: 12) {
            countChip(String(report.nativeCount), label: L("Native"), color: .green)
            countChip(String(report.eligibleCount), label: L("Eligible"), color: .gestaltAccent)
            countChip(String(report.unknownCount), label: L("Unknown"), color: .orange)
            countChip(String(report.blockedCount), label: L("Blocked"), color: .red)
        }
    }

    @ViewBuilder
    private func recommendationSummary(_ recommendation: LilaRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: recommendation.isExecutable
                      ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(recommendation.isExecutable ? .green : .orange)
                Text(recommendation.isExecutable
                     ? L("China Unlock is ready to stage")
                     : L("China Unlock is not ready"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text(String(format: L("%d steps, %d blockers"), recommendation.steps.count, recommendation.blockers.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if recommendation.requiresRestart {
                Text(L("Requires a device restart to take effect."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // One line per distinct blocking reason: the same reason
            // can block several features, and repeating it once per
            // feature reads as clutter. The per-feature evaluations
            // below (Show Details) still list every feature with its
            // own reason, so no evidence is lost.
            ForEach(deduplicated(recommendation.blockers.map(\.reason)), id: \.self) { reason in
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        // Full card width: without this the summary sizes to its
        // widest line and looks narrower than the rest of the card.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.gestaltAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func countChip(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Per-feature detail rows: the unified compatibility status
    /// (not the raw eligibility) is the badge, with the evaluator's
    /// reason, the detection evidence for unverified features, the
    /// "already supported" note for native capabilities (no modify
    /// action is offered for them), and the #178 warning where it
    /// applies. All values come from the report and the staged /
    /// restart-pending sets; nothing here re-evaluates eligibility.
    @ViewBuilder
    private func detailsList(_ evaluations: [LilaFeatureEvaluation], profile: DeviceProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Compatibility Status"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(evaluations, id: \.featureID) { evaluation in
                let detail = statusDetail(for: evaluation, profile: profile)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(L(evaluation.title))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(detail.status.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor(detail.status))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(statusColor(detail.status).opacity(0.12), in: Capsule())
                    }
                    Text(detail.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if detail.status == .unverified {
                        Text(L("Detection evidence"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        ForEach(detail.evidence, id: \.self) { line in
                            Text("• " + line)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if detail.status == .nativeSupported {
                        Text(L("Already supported on this device — no change needed."))
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    if detail.status == .unsupported {
                        Text(L("Not offered on this device"))
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    if let warning = detail.nativeAIWarning {
                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func statusColor(_ status: CompatibilityStatus) -> Color {
        switch status {
        case .nativeSupported: return .green
        case .modifiable: return .gestaltAccent
        case .enabled: return .teal
        case .staged: return .blue
        case .needsRestart: return .orange
        case .unverified: return .orange
        case .unsupported: return .secondary
        case .readFailed: return .red
        }
    }
}
