// SPDX-License-Identifier: GPL-3.0-only
// Release notes + version validation (发布说明与版本校验) — pure
// Foundation, no UI, no device access, no writes to the MobileGestalt
// cache. The release tooling (`scripts/prepare-release.py`) mirrors
// this logic in Python; the Swift module is the testable definition
// and the Python script is the operational tool. Both agree: a
// marketing version is `X.Y.Z`, a build number is a positive
// integer, and the notes are Markdown grouped by section.
import Foundation

/// A release version: a marketing version (`X.Y.Z`) and an integer
/// build number. Both are validated on parse; an invalid value
/// produces `nil` instead of a guessed version.
struct ReleaseVersion: Equatable, Sendable {
    let marketing: String
    let build: Int

    /// Parses `marketing` and `build`. The marketing version must be
    /// exactly three dot-separated parts, each a non-negative integer
    /// without leading zeros (unless the part is exactly "0"). The
    /// build must be a positive integer without leading zeros.
    /// Returns `nil` for anything else — never a guessed version.
    static func parse(marketing: String, build: String) -> ReleaseVersion? {
        guard isValidMarketing(marketing), let buildValue = validBuild(build) else {
            return nil
        }
        return ReleaseVersion(marketing: marketing, build: buildValue)
    }

    /// Whether `value` is a valid marketing version (`X.Y.Z`).
    static func isValidMarketing(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { isPlainInteger(String($0)) }
    }

    /// Whether `value` is a valid build number (a positive integer).
    static func isValidBuild(_ value: String) -> Bool {
        validBuild(value) != nil
    }

    /// The next build number for the same marketing version.
    func nextBuild() -> ReleaseVersion {
        ReleaseVersion(marketing: marketing, build: build + 1)
    }

    /// A non-negative integer without leading zeros (unless the
    /// value is exactly "0"). Used for the marketing-version parts.
    private static func isPlainInteger(_ value: String) -> Bool {
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber }) else { return false }
        if value.count > 1 && value.hasPrefix("0") { return false }
        return true
    }

    /// The build number as an integer, or `nil` when `value` is not
    /// a positive integer without leading zeros. `Int` conversion
    /// returns `nil` on overflow, so an over-long digit string is
    /// rejected rather than wrapped.
    private static func validBuild(_ value: String) -> Int? {
        guard !value.isEmpty, value.allSatisfy({ $0.isNumber }) else { return nil }
        if value.count > 1 && value.hasPrefix("0") { return nil }
        guard let parsed = Int(value), parsed > 0 else { return nil }
        return parsed
    }
}

/// One entry in the release notes: a PR (or a manual item) with a
/// section. `number` is `nil` for a manual item (no PR to link).
struct ReleaseNoteEntry: Equatable, Sendable {
    enum Section: String, CaseIterable, Sendable {
        case added
        case changed
        case fixed

        var heading: String {
            switch self {
            case .added: return "Added"
            case .changed: return "Changed"
            case .fixed: return "Fixed"
            }
        }
    }

    let number: Int?
    let title: String
    let section: Section
}

/// Renders release notes as Markdown. Sections appear in
/// Added/Changed/Fixed order and are omitted when empty. Entries
/// keep the order they were given. A `notes` string (human-editable,
/// for example known limitations) is appended as a final "Notes"
/// section when it is non-empty after trimming.
enum ReleaseNotes {
    static func render(
        version: ReleaseVersion, entries: [ReleaseNoteEntry], notes: String? = nil
    ) -> String {
        var lines: [String] = []
        lines.append("## LilaShift \(version.marketing) (Build \(version.build))")
        lines.append("")
        for section in ReleaseNoteEntry.Section.allCases {
            let sectionEntries = entries.filter { $0.section == section }
            guard !sectionEntries.isEmpty else { continue }
            lines.append("### \(section.heading)")
            lines.append("")
            for entry in sectionEntries {
                if let number = entry.number {
                    lines.append("- \(entry.title) (#\(number))")
                } else {
                    lines.append("- \(entry.title)")
                }
            }
            lines.append("")
        }
        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            lines.append("### Notes")
            lines.append("")
            lines.append(notes)
            lines.append("")
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }
}
