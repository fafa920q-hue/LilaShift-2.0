// SPDX-License-Identifier: GPL-3.0-only
// LilaShift 3.0 landing page ordering and compatibility migration tests.
import XCTest
@testable import GestaltX

final class DashboardV3Tests: XCTestCase {
    func testDefaultOrderingIncludesAllSections() {
        XCTAssertEqual(DashboardV3Destination.resolvedOrder(""), DashboardV3Destination.allCases)
    }

    func testCustomOrderingSurvivesReload() {
        let original = DashboardV3Destination.allCases
        let desired = [original[2], original[0], original[1], original[4], original[3]]
        let stored = desired.map(\.rawValue).joined(separator: ",")
        XCTAssertEqual(DashboardV3Destination.resolvedOrder(stored), desired)
    }

    func testUnknownAndDuplicateIdentifiersAreIgnored() {
        let order = DashboardV3Destination.resolvedOrder("restore,invalid,restore,unlock")
        XCTAssertEqual(order.count, DashboardV3Destination.allCases.count)
        XCTAssertEqual(Array(order.prefix(2)), [.restore, .unlock])
        XCTAssertEqual(Set(order).count, order.count)
    }

    func testOlderOrderAutomaticallyReceivesNewSections() {
        let order = DashboardV3Destination.resolvedOrder("unlock,diagnostics")
        XCTAssertEqual(order.count, DashboardV3Destination.allCases.count)
        XCTAssertEqual(Array(order.prefix(2)), [.unlock, .diagnostics])
    }
}
