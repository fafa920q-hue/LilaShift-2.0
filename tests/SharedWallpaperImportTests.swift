import Foundation
import Darwin
import XCTest
@testable import GestaltX

final class SharedWallpaperImportTests: XCTestCase {
    /// The original test read its wallpaper archive from
    /// `CommandLine.arguments[1]` and there is no in-repo fixture for it, so
    /// there is no input to run against under XCTest. To re-enable real
    /// coverage, add a small `.tendies`/`.zip` fixture to the test target and
    /// restore the original body, reading the archive from the fixture
    /// instead of the command line.
    func testSharedWallpaperImport() throws {
        throw XCTSkip("SharedWallpaperImportTests requires a wallpaper archive path via CommandLine.arguments[1]; no in-repo fixture exists. Add a .tendies/.zip fixture to the test target to re-enable wallpaper streaming, restart/gates, immutable offer, cancellation, size limits, special-file rejection and plist isolation coverage.")
    }
}
