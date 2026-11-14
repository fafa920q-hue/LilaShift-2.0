// SPDX-License-Identifier: GPL-3.0-only
//
// DashboardV3SnapshotTests.swift — SnapshotTesting UI regression
// tests for the LilaShift 3.0 home and its secondary navigation
// destinations (Phase H, gaps 1, 4, 5, 6).
//
// What is snapshotted (10 image snapshots, all `record: .missing`
// for first-run recording on CI — see ViewSnapshotTests for how
// references are created and committed):
//   - DashboardV3Home (the 8-section home, summaries only):
//     unread manager / populated fixture manager, light, 390x844.
//   - One snapshot per secondary destination, rendered through
//     the REAL navigation builder (`ContentView.dashboardDestination`,
//     made internal for this purpose — see its comment): unlock,
//     diagnostics, restore, presets, tools. Populated manager,
//     light, 390x844. The destination views are ScrollViews, so a
//     fixed-size snapshot captures the top of the page only; that is
//     still a regression guard for the page's header and first cards.
//   - Dark mode (gap 5): the populated home with dark traits.
//   - Small screen (gap 6): the populated home at 320pt wide —
//     the home's summary tiles must wrap, not truncate, the status
//     text at that width.
//   - Accessibility Dynamic Type (gap 4): the populated home with
//     an accessibility content-size trait. The home grid collapses
//     to one column at accessibility sizes (see `DashboardV3Home`);
//     the recorded reference shows the one-column layout, so a
//     regression back to two columns changes pixels and fails.
//
// These do NOT conflict with the 8 pending re-records in
// ViewSnapshotTests (Phase C shadow removal, Phase F status badge,
// Phase E sort/hide section): those are different views with
// different snapshot names, in a different test class (separate
// reference directory). Nothing here re-records or weakens them.
//
// Determinism: same fixture discipline as ViewSnapshotTests — the
// fixed CoreModuleFixtures snapshot (iPhone18,1 Air, region LL,
// eSIM on), an unread manager for the empty states, no live device
// read, no clock, fixed size and traits, `drawHierarchyInKeyWindow:
// true` (Liquid Glass needs it — see ViewSnapshotTests).
// The home reads its section order from
// `LilaShift.v3.dashboardOrder` in UserDefaults; the test host
// has no value stored, so the default order applies.
import SnapshotTesting
import SwiftUI
import XCTest

@testable import GestaltX

@MainActor
final class DashboardV3SnapshotTests: XCTestCase {

    // MARK: - Fixtures (same fixture as ViewSnapshotTests)

    private func unreadManager() -> GestaltManager {
        GestaltManager()
    }

    private func populatedManager() throws -> GestaltManager {
        let manager = GestaltManager()
        let document = try CoreModuleFixtures.document(
            extra: [
                "productType": "iPhone18,1",
                "regionCode": "LL",
            ],
            greenTea: false,
            notGreenTea: true,
            wapi: false
        )
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        manager.loadSnapshotForTests(snapshot)
        return manager
    }

    // MARK: - Snapshot helper

    /// Asserts an image snapshot of a 3.0 surface with the fixed
    /// P5 layout (light traits, display scale 2, `record: .missing`)
    /// and `drawHierarchyInKeyWindow: true` (required for Liquid
    /// Glass — see ViewSnapshotTests). `width` defaults to the
    /// 390pt phone width; pass 320 for the small-screen test.
    /// `contentSize` adds a Dynamic Type trait when set.
    private func assertV3Snapshot<V: View>(
        _ view: V, named name: String,
        width: CGFloat = 390,
        userInterfaceStyle: UIUserInterfaceStyle = .light,
        contentSize: UIContentSizeCategory? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        var traits: [UITraitCollection] = [
            UITraitCollection(userInterfaceStyle: userInterfaceStyle),
            UITraitCollection(displayScale: 2),
        ]
        if let contentSize {
            traits.append(UITraitCollection(preferredContentSizeCategory: contentSize))
        }
        assertSnapshot(
            of: view,
            as: .image(
                drawHierarchyInKeyWindow: true,
                precision: 1,
                perceptualPrecision: 0.98,
                layout: .fixed(width: width, height: 844),
                traits: UITraitCollection(traitsFrom: traits)
            ),
            named: name,
            record: .missing,
            file: file,
            testName: testName,
            line: line
        )
    }

    /// The 3.0 home in a NavigationStack, with a placeholder
    /// destination: the home only shows NavigationLinks, so the
    /// destination content is never rendered here.
    private func home(_ manager: GestaltManager) -> some View {
        NavigationStack {
            DashboardV3Home { _ in Text("Destination") }
        }
        .environmentObject(manager)
    }

    /// One secondary destination, rendered through the real
    /// navigation builder, in a NavigationStack with the manager.
    private func destination(_ section: DashboardV3Destination, _ manager: GestaltManager) -> some View {
        NavigationStack {
            ContentView().dashboardDestination(section)
        }
        .environmentObject(manager)
    }

    // MARK: - Gap 1: the 3.0 home

    func testV3HomeUnreadSnapshot() {
        assertV3Snapshot(home(unreadManager()), named: "v3-home-unread")
    }

    func testV3HomePopulatedSnapshot() throws {
        assertV3Snapshot(home(try populatedManager()), named: "v3-home-populated")
    }

    // MARK: - Gap 1: the secondary navigation destinations

    func testV3UnlockDestinationSnapshot() throws {
        assertV3Snapshot(
            destination(.unlock, try populatedManager()),
            named: "v3-unlock-populated")
    }

    func testV3DiagnosticsDestinationSnapshot() throws {
        assertV3Snapshot(
            destination(.diagnostics, try populatedManager()),
            named: "v3-diagnostics-populated")
    }

    func testV3RestoreDestinationSnapshot() throws {
        assertV3Snapshot(
            destination(.restore, try populatedManager()),
            named: "v3-restore-populated")
    }

    func testV3PresetsDestinationSnapshot() throws {
        assertV3Snapshot(
            destination(.presets, try populatedManager()),
            named: "v3-presets-populated")
    }

    func testV3ToolsDestinationSnapshot() throws {
        assertV3Snapshot(
            destination(.advanced, try populatedManager()),
            named: "v3-tools-populated")
    }

    // MARK: - Gap 5: dark mode

    func testV3HomePopulatedDarkSnapshot() throws {
        assertV3Snapshot(
            home(try populatedManager()),
            named: "v3-home-populated-dark",
            userInterfaceStyle: .dark)
    }

    // MARK: - Gap 6: small screen (320pt wide)

    func testV3HomePopulatedNarrowSnapshot() throws {
        assertV3Snapshot(
            home(try populatedManager()),
            named: "v3-home-populated-narrow-320",
            width: 320)
    }

    // MARK: - Gap 4: accessibility Dynamic Type
    //
    // .accessibilityExtraLarge is DynamicTypeSize.accessibility3:
    // the home grid must collapse to one column at this size.
    // The structural rule itself lives in the private `columns`
    // of DashboardV3Home, so this snapshot is the guard: a
    // regression to two columns changes the recorded pixels.

    func testV3HomePopulatedAccessibilitySnapshot() throws {
        assertV3Snapshot(
            home(try populatedManager()),
            named: "v3-home-populated-accessibility",
            contentSize: .accessibilityExtraLarge)
    }
}
