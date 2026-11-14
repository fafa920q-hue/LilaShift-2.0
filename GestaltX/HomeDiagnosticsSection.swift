// SPDX-License-Identifier: GPL-3.0-only
// Home diagnostics section + detail pages.
//
// The Tools home used to inline every diagnostics card (eleven full
// cards, ~16 glass cards in one scroll view). That made the home long,
// duplicated the same summaries in several cards, and forced every
// card to build and lay out at once. The home now shows only a
// compact diagnostics summary plus one row per diagnostic area; the
// full card lives on a secondary page behind a NavigationLink. The
// full cards themselves are unchanged (the SwiftUI snapshot tests
// render them in isolation), only where they are hosted changed.
//
// The section ids are stable: they are the ordering keys stored in
// PersonalizationSettings (`homeSectionOrder`). The categories are
// fixed and semantically clear — each id names one diagnostic area,
// and the order is the enum's CaseIterable order unless the user
// reordered them in the Personalization Center.
import SwiftUI

/// One diagnostic area on the Tools home. The raw value is the
/// stable id stored in PersonalizationSettings.
enum HomeDiagnosticsSectionID: String, CaseIterable, Identifiable, Sendable {
    case lilaIntelligence
    case safePatch
    case restore
    case healthScore
    case dependencyAnalyzer
    case deviceFingerprint
    case acceptance
    case faultDiagnosis
    case presetCatalog
    case personalization
    case diagnosticsExpansion

    var id: String { rawValue }

    /// The default order of the sections on the home.
    static let defaultOrder: [HomeDiagnosticsSectionID] = allCases

    /// The sections to show on the home, in the user's preferred
    /// order, with hidden sections removed. A stored order that
    /// omits a section (for example one added in a later version)
    /// gets the missing sections appended in default order, so no
    /// section silently disappears. Unknown ids are ignored.
    static func orderedVisibleSections(_ settings: PersonalizationSettings) -> [HomeDiagnosticsSectionID] {
        let hidden = settings.hiddenHomeSections ?? []
        let ordered: [HomeDiagnosticsSectionID]
        if let stored = settings.homeSectionOrder {
            let known = stored.compactMap { HomeDiagnosticsSectionID(rawValue: $0) }
            let missing = defaultOrder.filter { !known.contains($0) }
            ordered = known + missing
        } else {
            ordered = defaultOrder
        }
        return ordered.filter { !hidden.contains($0.rawValue) }
    }

    var title: String {
        switch self {
        case .lilaIntelligence: return L("Lila Intelligence")
        case .safePatch: return L("SafePatch Simulator")
        case .restore: return L("Restore Intelligence")
        case .healthScore: return L("System Health Score")
        case .dependencyAnalyzer: return L("Dependency Analyzer")
        case .deviceFingerprint: return L("Device Capability Fingerprint")
        case .acceptance: return L("Post-Modification Acceptance")
        case .faultDiagnosis: return L("Smart Fault Diagnosis")
        case .presetCatalog: return L("Preset Catalog")
        case .personalization: return L("Personalization Center")
        case .diagnosticsExpansion: return L("Diagnostics Expansion")
        }
    }

    var subtitle: String {
        switch self {
        case .lilaIntelligence:
            return L("Personalized recommendations for this device, generated locally from real readings.")
        case .safePatch:
            return L("See what a change would do before you enable it. Simulation only — nothing is written.")
        case .restore:
            return L("Modification timeline and precise restore, from trusted records only.")
        case .healthScore:
            return L("Cache, compatibility, backup and modification risk, from real readings only.")
        case .dependencyAnalyzer:
            return L("Dependencies, conflicts and duplicates for a proposal, before you stage it.")
        case .deviceFingerprint:
            return L("This device's real capabilities and build, recorded locally with a SHA-256 digest.")
        case .acceptance:
            return L("Re-read the device after a restart and check what actually stuck.")
        case .faultDiagnosis:
            return L("What went wrong, why, and what to try — from real readings only.")
        case .presetCatalog:
            return L("Search, filter and save presets — from the catalog only.")
        case .personalization:
            return L("Custom presets, catalog sort and Tools page cards — saved on this device only.")
        case .diagnosticsExpansion:
            return L("Battery, app cache, connection status and the operation log — read-only.")
        }
    }

    var symbol: String {
        switch self {
        case .lilaIntelligence: return "brain"
        case .safePatch: return "shield.checkered"
        case .restore: return "clock.arrow.circlepath"
        case .healthScore: return "heart.text.square"
        case .dependencyAnalyzer: return "point.3.connected.trianglepath.dotted"
        case .deviceFingerprint: return "fingerprint"
        case .acceptance: return "checkmark.seal"
        case .faultDiagnosis: return "stethoscope"
        case .presetCatalog: return "books.vertical"
        case .personalization: return "paintpalette"
        case .diagnosticsExpansion: return "waveform.path.ecg"
        }
    }

    /// The full card for this area, hosted on its detail page.
    /// The card itself is unchanged; only where it is hosted moved.
    @ViewBuilder
    var detailContent: some View {
        switch self {
        case .lilaIntelligence: LilaIntelligenceCard()
        case .safePatch: SafePatchCard()
        case .restore: RestoreIntelligenceCard()
        case .healthScore: SystemHealthScoreCard()
        case .dependencyAnalyzer: DependencyAnalyzerCard()
        case .deviceFingerprint: DeviceFingerprintCard()
        case .acceptance: PostModificationAcceptanceCard()
        case .faultDiagnosis: SmartFaultDiagnosisCard()
        case .presetCatalog: PresetCatalogCard()
        case .personalization: PersonalizationCenterCard()
        case .diagnosticsExpansion: DiagnosticsExpansionCard()
        }
    }
}

/// The compact diagnostics summary shown on the home: the health
/// score, the one-tap simulation verdict and the recorded-change
/// count, all from the shared cache (no recomputation). It is a
/// summary only — the full cards live on the detail pages below.
/// Unknown stays unknown: an unread device shows "Unknown", never a
/// fabricated score.
struct DiagnosticsSummaryCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics: HomeDiagnosticsCache?

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "heart.text.square", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Diagnostics Summary"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Health, simulation and recorded changes at a glance. Details are on the pages below."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if model.snapshot == nil {
                    Text(L("Read the device first to see the diagnostics summary."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        summaryChip(
                            value: healthScoreText,
                            label: L("Health Score"),
                            color: .gestaltAccent)
                        summaryChip(
                            value: simulationText,
                            label: L("Simulation"),
                            color: simulationColor)
                        summaryChip(
                            value: "\(recordCount)",
                            label: L("Recorded Changes"),
                            color: .secondary)
                    }
                }
            }
        }
    }

    private var healthScoreText: String {
        guard let score = diagnostics?.healthScore?.overallScore else { return L("Unknown") }
        return "\(score)"
    }

    private var simulationText: String {
        guard let simulation = diagnostics?.oneTapSimulation else { return L("Unknown") }
        return simulation.canProceed ? L("Passed") : L("Blocked")
    }

    private var simulationColor: Color {
        guard let simulation = diagnostics?.oneTapSimulation else { return .secondary }
        return simulation.canProceed ? .green : .red
    }

    private var recordCount: Int {
        diagnostics?.records.count ?? 0
    }

    @ViewBuilder
    private func summaryChip(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One row per diagnostic area: the area's icon, title and subtitle,
/// linking to the full card on a secondary page. The rows render in
/// `order` (the user's preferred order from PersonalizationSettings,
/// or the default order). Hidden sections are omitted by the caller.
struct HomeDiagnosticsSection: View {
    let order: [HomeDiagnosticsSectionID]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Diagnostics"))
                .font(.headline)
            ForEach(order) { section in
                NavigationLink {
                    HomeDiagnosticsDetailPage(section: section)
                } label: {
                    GlassCard(cornerRadius: GlassTokens.tileRadius) {
                        GlassCategoryTile(
                            title: section.title,
                            detail: section.subtitle,
                            symbol: section.symbol,
                            tint: .gestaltAccent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A secondary page hosting one full diagnostics card. The card
/// itself is unchanged; it reads the same GestaltManager and the
/// same shared diagnostics cache as it did on the home.
private struct HomeDiagnosticsDetailPage: View {
    let section: HomeDiagnosticsSectionID

    var body: some View {
        ScrollView {
            section.detailContent
                .padding()
        }
        .background(GlassBackground())
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
