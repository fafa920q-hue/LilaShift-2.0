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
    @Environment(\.colorScheme) private var colorScheme
    @State private var recordCount = 0
    @State private var showingDetails = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The report for the current snapshot, or `nil` when the device
    /// has not been read yet.
    private var report: LilaDeviceReport? {
        guard model.snapshot != nil else { return nil }
        return LilaIntelligence.report(
            snapshot: model.snapshot, backups: model.backups,
            changeRecordCount: recordCount)
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
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
                        detailsList(report.evaluations)
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
        guard let deviceID = RestoreIntelligence.installationDeviceID else { return }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        recordCount = (try? store.load().count) ?? 0
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
            ForEach(Array(recommendation.blockers.enumerated()), id: \.offset) { _, blocker in
                Text(blocker.reason)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
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

    @ViewBuilder
    private func detailsList(_ evaluations: [LilaFeatureEvaluation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(evaluations, id: \.featureID) { evaluation in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(L(evaluation.title))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(eligibilityLabel(evaluation.eligibility))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(eligibilityColor(evaluation.eligibility))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(eligibilityColor(evaluation.eligibility).opacity(0.12), in: Capsule())
                    }
                    Text(evaluation.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func eligibilityLabel(_ eligibility: FeatureEligibility) -> String {
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
        case .alreadyConfigured: return .teal
        case .eligibleToEnable: return .gestaltAccent
        case .unsupported: return .secondary
        case .unknown: return .orange
        case .conflict: return .red
        }
    }
}
