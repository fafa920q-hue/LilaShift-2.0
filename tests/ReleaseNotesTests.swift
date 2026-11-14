// SPDX-License-Identifier: GPL-3.0-only
// Tests for the release-notes module (`ReleaseNotes`): version
// parsing, build validation, and Markdown rendering. Pure logic —
// no device, no file system, no network.
import XCTest
@testable import GestaltX

final class ReleaseNotesTests: XCTestCase {
    // MARK: - Version parsing

    func testParseValidVersion() {
        let version = ReleaseVersion.parse(marketing: "1.0.8", build: "11130113")
        XCTAssertEqual(version, ReleaseVersion(marketing: "1.0.8", build: 11130113))
    }

    func testParseRejectsMalformedMarketingVersion() {
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8.1", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "01.0.8", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.x", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1..8", build: "11130113"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8 ", build: "11130113"))
    }

    func testParseRejectsInvalidBuild() {
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: "0"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: "01"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: "abc"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: ""))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: "-1"))
        XCTAssertNil(ReleaseVersion.parse(marketing: "1.0.8", build: "99999999999999999999"))
    }

    func testIsValidMarketingAndBuild() {
        XCTAssertTrue(ReleaseVersion.isValidMarketing("1.0.8"))
        XCTAssertTrue(ReleaseVersion.isValidMarketing("0.0.0"))
        XCTAssertFalse(ReleaseVersion.isValidMarketing("1.0"))
        XCTAssertFalse(ReleaseVersion.isValidMarketing("1.0.08"))
        XCTAssertTrue(ReleaseVersion.isValidBuild("11130113"))
        XCTAssertFalse(ReleaseVersion.isValidBuild("0"))
        XCTAssertFalse(ReleaseVersion.isValidBuild("11130113 "))
    }

    func testNextBuild() {
        let version = ReleaseVersion(marketing: "1.0.8", build: 11130112)
        XCTAssertEqual(version.nextBuild(), ReleaseVersion(marketing: "1.0.8", build: 11130113))
    }

    // MARK: - Notes rendering

    func testRenderEmptyNotes() {
        let rendered = ReleaseNotes.render(
            version: ReleaseVersion(marketing: "1.0.8", build: 11130113), entries: [])
        XCTAssertEqual(rendered, "## LilaShift 1.0.8 (Build 11130113)\n")
    }

    func testRenderGroupsSectionsAndKeepsOrder() {
        let rendered = ReleaseNotes.render(
            version: ReleaseVersion(marketing: "1.0.8", build: 11130113),
            entries: [
                ReleaseNoteEntry(number: 9, title: "Add snapshot tests", section: .added),
                ReleaseNoteEntry(number: nil, title: "Manual item", section: .added),
                ReleaseNoteEntry(number: 8, title: "Fix a bug", section: .fixed),
            ],
            notes: "Known limitation: none.")
        XCTAssertEqual(
            rendered,
            """
            ## LilaShift 1.0.8 (Build 11130113)

            ### Added

            - Add snapshot tests (#9)
            - Manual item

            ### Fixed

            - Fix a bug (#8)

            ### Notes

            Known limitation: none.
            """
            + "\n")
    }

    func testRenderOmitsEmptySectionsAndBlankNotes() {
        let rendered = ReleaseNotes.render(
            version: ReleaseVersion(marketing: "1.0.8", build: 11130113),
            entries: [
                ReleaseNoteEntry(number: 7, title: "Change the theme", section: .changed),
            ],
            notes: "   \n  ")
        XCTAssertEqual(
            rendered,
            """
            ## LilaShift 1.0.8 (Build 11130113)

            ### Changed

            - Change the theme (#7)
            """
            + "\n")
    }

    func testRenderSectionsAppearInAddedChangedFixedOrder() {
        let rendered = ReleaseNotes.render(
            version: ReleaseVersion(marketing: "1.0.8", build: 11130113),
            entries: [
                ReleaseNoteEntry(number: 1, title: "Fix first", section: .fixed),
                ReleaseNoteEntry(number: 2, title: "Add second", section: .added),
                ReleaseNoteEntry(number: 3, title: "Change third", section: .changed),
            ])
        let addedRange = rendered.range(of: "### Added")
        let changedRange = rendered.range(of: "### Changed")
        let fixedRange = rendered.range(of: "### Fixed")
        XCTAssertNotNil(addedRange)
        XCTAssertNotNil(changedRange)
        XCTAssertNotNil(fixedRange)
        guard let added = addedRange, let changed = changedRange, let fixed = fixedRange else {
            return XCTFail("expected all three sections")
        }
        XCTAssertLessThan(added.lowerBound, changed.lowerBound)
        XCTAssertLessThan(changed.lowerBound, fixed.lowerBound)
    }
}
