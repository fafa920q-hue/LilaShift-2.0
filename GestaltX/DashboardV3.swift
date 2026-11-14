// SPDX-License-Identifier: GPL-3.0-only
// LilaShift 3.0: a lightweight, task-oriented landing page.
// All device readings remain sourced from GestaltManager, never placeholders.
import SwiftUI

enum DashboardV3Destination: String, CaseIterable, Identifiable {
    case unlock, diagnostics, restore, presets, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unlock: return L("One-Tap Unlock")
        case .diagnostics: return L("Advanced & Diagnostics")
        case .restore: return L("Backups")
        case .presets: return L("Feature Categories")
        case .advanced: return L("Tools")
        }
    }

    var subtitle: String {
        switch self {
        case .unlock: return L("Apple Intelligence & Region")
        case .diagnostics: return L("Compatibility")
        case .restore: return L("Restore pre-unlock state")
        case .presets: return L("Personalization")
        case .advanced: return L("All tools")
        }
    }

    var symbol: String {
        switch self {
        case .unlock: return "lock.open.fill"
        case .diagnostics: return "stethoscope"
        case .restore: return "clock.arrow.circlepath"
        case .presets: return "square.grid.2x2"
        case .advanced: return "slider.horizontal.3"
        }
    }

    // Keep newly introduced sections visible when opening saved settings from
    // an older build; never trust stored values as arbitrary navigation routes.
    static func resolvedOrder(_ raw: String) -> [DashboardV3Destination] {
        let saved = raw.split(separator: ",").compactMap { DashboardV3Destination(rawValue: String($0)) }
        var unique: [DashboardV3Destination] = []
        for item in saved where !unique.contains(item) { unique.append(item) }
        for item in allCases where !unique.contains(item) { unique.append(item) }
        return unique
    }
}

struct DashboardV3Home<DestinationView: View>: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("LilaShift.v3.dashboardOrder") private var savedOrder = ""
    @State private var showingReorder = false
    let destination: (DashboardV3Destination) -> DestinationView

    private var orderedSections: [DashboardV3Destination] {
        DashboardV3Destination.resolvedOrder(savedOrder)
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                GlassCard(cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L("Device Overview"), systemImage: "iphone")
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.hasDocument ? model.displayedName : UIDevice.current.model)
                                .font(.title3.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            Text(model.hasDocument ? L("Device connected") : L("Device not read yet"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if model.changeCount > 0 {
                            Label(String(format: L("%d changes"), model.changeCount),
                                  systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        Button {
                            Task { await model.connect() }
                        } label: {
                            Label(model.isBusy ? L("Reading…") : (model.hasDocument ? L("Read Again") : L("Read Device")),
                                  systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || model.changeCount > 0)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Text(L("Feature Categories"))
                        .font(.headline)
                    Spacer()
                    Button {
                        showingReorder = true
                    } label: {
                        Label(L("Sort"), systemImage: "arrow.up.arrow.down")
                            .font(.subheadline)
                    }
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(orderedSections) { section in
                        NavigationLink {
                            destination(section)
                        } label: {
                            GlassCard(cornerRadius: 18) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: section.symbol)
                                        .font(.title2)
                                        .foregroundStyle(Color.gestaltAccent)
                                    Text(section.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(section.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
                                .padding(14)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(L("Device-specific results are available after reading the device."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(GlassBackground())
        .navigationTitle("LilaShift 3.0")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingReorder) {
            NavigationStack {
                List {
                    ForEach(orderedSections) { section in
                        Label(section.title, systemImage: section.symbol)
                    }
                    .onMove { offsets, destination in
                        var sections = orderedSections
                        sections.move(fromOffsets: offsets, toOffset: destination)
                        savedOrder = sections.map(\.rawValue).joined(separator: ",")
                    }
                }
                .environment(\.editMode, .constant(EditMode.active))
                .navigationTitle(L("Sort"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(L("Reset")) { savedOrder = "" }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("Done")) { showingReorder = false }
                    }
                }
            }
        }
    }
}
