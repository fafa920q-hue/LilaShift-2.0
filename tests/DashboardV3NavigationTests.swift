// SPDX-License-Identifier: GPL-3.0-only
//
// DashboardV3NavigationTests.swift — navigation / reachability
// tests for the 3.0 home and the unified feature catalog
// (Phase H, gap 7). A data test: no UI is needed, because
// reachability is a property of the section and catalog tables.
//
// What is proven here (and NOT already covered elsewhere):
//   - Every dashboard destination is reached by at least one
//     home section (the inverse of the per-section mapping,
//     which FeatureCatalogTests
//     .testHomeSectionsHaveTitlesSubtitlesAndDestinations
//     already asserts — that test is not duplicated here).
//   - Every one of the 53 catalog items is reachable: it has a
//     non-empty id, names and symbol, and a destination that is
//     a real dashboard destination.
//   - Every dashboard destination is reached by at least one
//     catalog item.
//   - Every preset item's destination matches the staging-page
//     rule for its PresetEntry (`FeatureCatalog.destination`),
//     so the catalog never sends a preset to a page where it
//     cannot be staged.
//   - The home sections and the catalog agree on the
//     destinations: both surfaces reach exactly the five
//     dashboard destinations, so no destination is reachable
//     from one surface but missing from the other.
import XCTest

@testable import GestaltX

final class DashboardV3NavigationTests: XCTestCase {

    func testEveryDestinationIsReachedByAtLeastOneHomeSection() {
        for destination in DashboardV3Destination.allCases {
            let sections = HomeSectionID.allCases.filter { $0.destination == destination }
            XCTAssertFalse(
                sections.isEmpty,
                "No home section opens \(destination.rawValue)")
        }
    }

    func testEveryCatalogItemIsReachable() {
        XCTAssertEqual(FeatureCatalog.allItems.count, 53)
        for item in FeatureCatalog.allItems {
            XCTAssertFalse(item.id.isEmpty, "Catalog item has an empty id")
            XCTAssertFalse(item.chineseName.isEmpty, "Missing name for \(item.id)")
            XCTAssertFalse(item.englishTitle.isEmpty, "Missing English title for \(item.id)")
            XCTAssertFalse(item.chineseDescription.isEmpty, "Missing description for \(item.id)")
            XCTAssertFalse(item.symbol.isEmpty, "Missing symbol for \(item.id)")
            XCTAssertTrue(
                DashboardV3Destination.allCases.contains(item.destination),
                "\(item.id) points at an unknown destination")
            if item.kind == .preset {
                XCTAssertEqual(item.presetFeatureID, item.id)
                XCTAssertNotNil(item.riskLevel, "Preset item \(item.id) has no risk level")
            } else {
                XCTAssertNil(item.presetFeatureID)
                XCTAssertNil(item.riskLevel, "Page item \(item.id) must not carry a risk level")
            }
        }
        XCTAssertEqual(
            Set(FeatureCatalog.allItems.map(\.id)).count,
            FeatureCatalog.allItems.count,
            "Duplicate catalog ids would make one item unreachable")
    }

    func testEveryDestinationIsReachedByAtLeastOneCatalogItem() {
        for destination in DashboardV3Destination.allCases {
            let items = FeatureCatalog.allItems.filter { $0.destination == destination }
            XCTAssertFalse(
                items.isEmpty,
                "No catalog item opens \(destination.rawValue)")
        }
    }

    func testPresetItemDestinationsMatchTheStagingPageRule() {
        for item in FeatureCatalog.presetItems {
            guard let entry = PresetCatalog.entry(for: item.id) else {
                XCTFail("Preset item \(item.id) has no PresetEntry")
                continue
            }
            XCTAssertEqual(
                item.destination,
                FeatureCatalog.destination(for: entry),
                "\(item.id) points at \(item.destination.rawValue) but its entry stages on \(FeatureCatalog.destination(for: entry).rawValue)")
            XCTAssertEqual(
                item.category,
                FeatureCatalog.category(for: entry),
                "\(item.id) has category \(item.category.rawValue) but its entry maps to \(FeatureCatalog.category(for: entry).rawValue)")
        }
    }

    func testHomeSectionsAndCatalogAgreeOnDestinations() {
        let sectionDestinations = Set(HomeSectionID.allCases.compactMap(\.destination))
        let catalogDestinations = Set(FeatureCatalog.allItems.map(\.destination))
        XCTAssertEqual(sectionDestinations, Set(DashboardV3Destination.allCases))
        XCTAssertEqual(catalogDestinations, Set(DashboardV3Destination.allCases))
        XCTAssertEqual(sectionDestinations, catalogDestinations)
    }
}
