// SPDX-License-Identifier: GPL-3.0-only
// SafePatch (修改模拟器) — read-only SwiftUI display.
//
// Before the user taps enable, this card shows each field's current
// value, target value, risk and expected impact, the pre-check
// sequence, and the offline-simulated serialization result. It never
// writes anything: simulation runs on an in-memory copy of the
// document. A simulation passing does NOT mean the system will take
// effect — the card says plainly that real-device verification is
// still required.
import SwiftUI

struct SafePatchCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProposal: SafePatchProposal = SafePatchProposal.oneTap()
    @State private var showingChecks = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    /// The simulation for the selected proposal, or `nil` when the
    /// device has not been read yet. Prefers the shared diagnostics
    /// cache (all three proposals are simulated once per input change
    /// on a background task) over recomputing on every body
    /// evaluation; falls back to direct computation when no cache is
    /// provided (for example the SwiftUI snapshot tests), so the
    /// rendered output is identical either way.
    private var simulation: SafePatchSimulation? {
        if let cached = diagnostics?.simulations[selectedProposal] { return cached }
        guard model.working != nil else { return nil }
        return SafePatch.simulate(
            proposal: selectedProposal, snapshot: model.snapshot,
            currentDocument: model.working, backups: model.backups)
    }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "shield.checkered", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("SafePatch Simulator"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("See what a change would do before you enable it. Simulation only — nothing is written."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.working == nil {
                    Text(L("Read the device first to simulate a change."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    Picker(L("Proposal"), selection: $selectedProposal) {
                        Text(L("One-Tap Unlock")).tag(SafePatchProposal.oneTap())
                        Text(L("AI Only")).tag(SafePatchProposal.aiOnly())
                        Text(L("eSIM & Region")).tag(SafePatchProposal.esimRegion())
                    }
                    .pickerStyle(.segmented)

                    if let simulation {
                        verdictView(simulation)
                        diffList(simulation)
                        Button(showingChecks ? L("Hide Pre-Checks") : L("Show Pre-Checks")) {
                            showingChecks.toggle()
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        if showingChecks {
                            checksList(simulation)
                        }
                        effectStatesView(simulation)
                        Text(L("A simulation passing does not mean the system will take effect. Real-device verification after a restart is still required."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verdictView(_ simulation: SafePatchSimulation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: simulation.canProceed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(simulation.canProceed ? .green : .red)
                Text(simulation.canProceed ? L("Simulation passed") : L("Simulation blocked"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            // One line per distinct reason: the same reason can be
            // raised by several pre-checks, and repeating it reads as
            // clutter. The pre-check list below still shows every
            // check with its own reason, so no evidence is lost.
            if !simulation.blockers.isEmpty {
                ForEach(deduplicated(simulation.blockers), id: \.self) { blocker in
                    Text(blocker)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            if !simulation.warnings.isEmpty {
                ForEach(deduplicated(simulation.warnings), id: \.self) { warning in
                    Text(warning)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .background((simulation.canProceed ? Color.green : Color.red).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func diffList(_ simulation: SafePatchSimulation) -> some View {
        if simulation.diffs.isEmpty {
            Text(L("This proposal would change nothing."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text(String(format: L("Would change %d fields"), simulation.diffs.count))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(simulation.diffs) { diff in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(L(diff.title))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(riskLabel(diff.risk))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(riskColor(diff.risk))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(riskColor(diff.risk).opacity(0.12), in: Capsule())
                        }
                        HStack(spacing: 4) {
                            Text(diff.original.displayText)
                            Text("→")
                            Text(diff.target.displayText)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Text(diff.sourceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func checksList(_ simulation: SafePatchSimulation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(simulation.checks) { check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.passed ? "checkmark.circle.fill"
                              : (check.isBlocker ? "xmark.circle.fill" : "exclamationmark.triangle.fill"))
                        .foregroundStyle(check.passed ? .green : (check.isBlocker ? .red : .orange))
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(check.title))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(check.reason)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func effectStatesView(_ simulation: SafePatchSimulation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Effect States"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            ForEach(simulation.effectStates, id: \.effect.rawValue) { state in
                effectRow(state)
            }
            Text(L("File write success is never presented as the feature definitely working."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func effectRow(_ state: SafePatchEffectState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: state.status == .verified ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state.status == .verified ? .green : .secondary)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.effect.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(state.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Never truncate the status: without this the middle
            // VStack's long note took the width and the status
            // ("Not yet" / a failure reason) was clipped at the
            // card's right edge.
            Text(effectStatusLabel(state.status))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func effectStatusLabel(_ status: SafePatchEffectStatus) -> String {
        switch status {
        case .notReached: return L("Not yet")
        case .verified: return L("Verified")
        case .failed(let reason): return reason
        case .unknown(let reason): return reason
        }
    }

    private func riskLabel(_ risk: CapabilityRiskLevel) -> String {
        switch risk {
        case .low: return L("Low risk")
        case .medium: return L("Medium risk")
        case .high: return L("High risk")
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
