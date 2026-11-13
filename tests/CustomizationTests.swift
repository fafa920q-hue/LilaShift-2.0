// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ImageIO
import XCTest
@testable import GestaltX

/// CustomizationTests requires external fixture zips (valid.zip,
/// traversal.zip, ...) passed via the command line; no fixtures exist in
/// the repo, so this test skips in CI.
final class CustomizationTests: XCTestCase {
    func testCustomization() throws {
        throw XCTSkip("CustomizationTests requires an external fixtures directory passed on the command line, not available in CI.")
    }
}
