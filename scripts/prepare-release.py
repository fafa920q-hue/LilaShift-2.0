#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Prepare a LilaShift release (发布准备).

Validates (and optionally bumps) the version in the Xcode project,
renders release notes from a PR list, and verifies the IPA artifact
with its SHA-256. This is the operational twin of
`GestaltX/ReleaseNotes.swift`: the Swift module is the testable
definition, this script is the tool that does the work. Both agree:
a marketing version is `X.Y.Z` (no leading zeros), a build number
is a positive integer, and the notes are Markdown grouped
Added/Changed/Fixed.

Usage:
    python3 scripts/prepare-release.py --dry-run
    python3 scripts/prepare-release.py --bump-build --prs prs.txt \\
        --ipa path/to/LilaShift.ipa
    python3 scripts/prepare-release.py --version 1.0.8 --build 11130113 \\
        --write-project --prs prs.txt --notes-file notes.md

What it does:
  1. Reads MARKETING_VERSION and CURRENT_PROJECT_VERSION from
     GestaltX.xcodeproj/project.pbxproj. Both must have exactly one
     distinct value across all build configurations (the same rule
     `.github/scripts/build-ipa.sh` enforces); otherwise it fails.
  2. Computes the target version: `--bump-build` increments the
     build, `--version X.Y.Z` sets the marketing version,
     `--build N` sets the build explicitly. With none of these it
     validates the current version and renders notes for it.
  3. Renders the notes from `--prs FILE` (one PR per line:
     `number|section|title`, e.g. `9|added|SwiftUI snapshot tests`;
     lines starting with `#` are comments, blank lines are ignored;
     section must be `added`, `changed` or `fixed`; an empty number
     (`|added|Manual item`) is a manual item with no PR link) plus
     an optional human-editable Notes section from `--notes-file FILE`.
  4. Verifies `--ipa PATH` exists and records its SHA-256 and size.
     Without `--ipa` it warns and records no IPA.
  5. Writes the notes (`release-notes-<marketing>-<build>.md`) and a
     manifest JSON (`release-manifest-<marketing>-<build>.json`)
     with the version, IPA path, SHA-256 and size, and the PR list.
     `--dry-run` prints everything and writes nothing.
  6. With `--write-project` it updates ALL occurrences of the two
     version values in the pbxproj and re-reads to verify they are
     consistent; without it, it prints the exact manual steps
     instead of touching the project file.

It never creates a tag, never publishes a release, and never
overwrites an existing release — it only prepares the files that a
human (or the Draft Release workflow) uses to create one.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = REPO_ROOT / "GestaltX.xcodeproj" / "project.pbxproj"

SECTIONS = ("added", "changed", "fixed")
SECTION_HEADINGS = {
    "added": "Added",
    "changed": "Changed",
    "fixed": "Fixed",
}

_MARKETING_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
_BUILD_RE = re.compile(r"^(0|[1-9][0-9]*)$")


def is_valid_marketing(value):
    """Whether `value` is a valid marketing version (`X.Y.Z`).

    Exactly three dot-separated parts, each a non-negative integer
    without leading zeros (unless the part is exactly "0").
    """
    return bool(_MARKETING_RE.match(value))


def is_valid_build(value):
    """Whether `value` is a valid build number (a positive integer
    without leading zeros). It must also fit in a 64-bit signed
    integer, matching the Swift `Int` conversion in
    ReleaseNotes.swift (which returns nil on overflow)."""
    if not _BUILD_RE.match(value):
        return False
    parsed = int(value)
    return 0 < parsed <= 9223372036854775807


def parse_version(marketing, build):
    """Returns (marketing, build_int) or None for an invalid pair.
    Never guesses a version."""
    if not is_valid_marketing(marketing):
        return None
    if not is_valid_build(build):
        return None
    return (marketing, int(build))


def read_project_version(pbxproj_path=PBXPROJ):
    """Reads the version from the pbxproj. Returns
    (marketing, build) or None when the file is missing, a value is
    absent, or the values are inconsistent across configurations."""
    try:
        text = Path(pbxproj_path).read_text(encoding="utf-8")
    except OSError:
        return None
    marketing = set(re.findall(r"MARKETING_VERSION = ([^;]+);", text))
    build = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", text))
    if len(marketing) != 1 or len(build) != 1:
        return None
    marketing_value = marketing.pop().strip()
    build_value = build.pop().strip()
    parsed = parse_version(marketing_value, build_value)
    if parsed is None:
        return None
    return parsed


def bump_project_version(pbxproj_path, marketing, build):
    """Replaces ALL occurrences of the two version values in the
    pbxproj with the new ones, then re-reads to verify consistency.
    Returns True on success. Raises ValueError when the current
    values cannot be read or the new values are invalid."""
    parsed = parse_version(marketing, str(build))
    if parsed is None:
        raise ValueError(f"invalid target version: {marketing} ({build})")
    current = read_project_version(pbxproj_path)
    if current is None:
        raise ValueError("cannot read a consistent current version from the project")
    path = Path(pbxproj_path)
    text = path.read_text(encoding="utf-8")
    new_text, marketing_count = re.subn(
        r"MARKETING_VERSION = [^;]+;",
        f"MARKETING_VERSION = {marketing};",
        text,
    )
    new_text, build_count = re.subn(
        r"CURRENT_PROJECT_VERSION = [^;]+;",
        f"CURRENT_PROJECT_VERSION = {build};",
        new_text,
    )
    if marketing_count == 0 or build_count == 0:
        raise ValueError("no version settings found in the project file")
    path.write_text(new_text, encoding="utf-8")
    if read_project_version(pbxproj_path) != (marketing, int(build)):
        raise ValueError("version update did not verify after writing")
    return True

def parse_prs_file(path):
    """Parses a PR list file. One PR per line:
    `number|section|title` (e.g. `9|added|SwiftUI snapshot tests`).
    An empty number (`|added|Manual item`) is a manual item with
    no PR link. Lines starting with `#` are comments; blank lines
    are ignored. Returns a list of dicts {number, section, title}.
    Raises ValueError on a malformed line."""
    entries = []
    for lineno, raw in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) != 3:
            raise ValueError(
                f"{path}:{lineno}: expected `number|section|title`, got: {raw!r}")
        number_text, section, title = (p.strip() for p in parts)
        if number_text == "":
            number = None
        elif number_text.isdigit() and int(number_text) > 0:
            number = int(number_text)
        else:
            raise ValueError(
                f"{path}:{lineno}: PR number must be a positive integer "
                f"(or empty for a manual item), got: {number_text!r}")
        if section not in SECTIONS:
            raise ValueError(
                f"{path}:{lineno}: section must be one of {', '.join(SECTIONS)}, "
                f"got: {section!r}")
        if not title:
            raise ValueError(f"{path}:{lineno}: title must not be empty")
        entries.append({
            "number": number,
            "section": section,
            "title": title,
        })
    return entries


def render_notes(marketing, build, entries, notes=None):
    """Renders the release notes as Markdown, mirroring
    `ReleaseNotes.render` in GestaltX/ReleaseNotes.swift exactly:
    sections in Added/Changed/Fixed order, omitted when empty,
    entries keep their given order, an optional human-editable
    Notes section at the end, one trailing newline."""
    lines = [f"## LilaShift {marketing} (Build {build})", ""]
    for section in SECTIONS:
        section_entries = [e for e in entries if e["section"] == section]
        if not section_entries:
            continue
        lines.append(f"### {SECTION_HEADINGS[section]}")
        lines.append("")
        for entry in section_entries:
            if entry["number"] is None:
                lines.append(f"- {entry['title']}")
            else:
                lines.append(f"- {entry['title']} (#{entry['number']})")
        lines.append("")
    if notes is not None and notes.strip():
        lines.append("### Notes")
        lines.append("")
        lines.append(notes.strip())
        lines.append("")
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


def sha256_file(path):
    """Returns (hex_digest, size_in_bytes) for a file."""
    digest = hashlib.sha256()
    size = 0
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            size += len(chunk)
    return digest.hexdigest(), size


def manual_bump_steps(marketing, build):
    """The exact manual steps for updating the version in Xcode,
    printed when --write-project is not given."""
    return (
        "To bump the version manually (Xcode):\n"
        "  1. Open GestaltX.xcodeproj, select the GestaltX target.\n"
        "  2. General > Identity: set Version to "
        f"{marketing} and Build to {build}.\n"
        "  3. Do the same for the GestaltXTests target and the share\n"
        "     extension target, so all six build configurations agree\n"
        "     (build-ipa.sh requires exactly one distinct value).\n"
        "  4. Re-run this script without --version/--build to verify."
    )


def build_manifest(marketing, build, entries, ipa_path, ipa_sha256, ipa_size):
    """The release manifest: everything the Draft Release workflow
    needs besides the notes themselves."""
    return {
        "app": "LilaShift",
        "marketing_version": marketing,
        "build": build,
        "tag": f"v{marketing}",
        "prs": entries,
        "ipa": None if ipa_path is None else {
            "path": str(ipa_path),
            "sha256": ipa_sha256,
            "size_bytes": ipa_size,
        },
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Prepare a LilaShift release: validate/bump the "
                    "version, render release notes, verify the IPA.")
    parser.add_argument("--bump-build", action="store_true",
                        help="increment the build number")
    parser.add_argument("--version", metavar="X.Y.Z",
                        help="set the marketing version")
    parser.add_argument("--build", metavar="N", type=int,
                        help="set the build number explicitly")
    parser.add_argument("--prs", metavar="FILE",
                        help="PR list file (number|section|title per line)")
    parser.add_argument("--notes-file", metavar="FILE",
                        help="file with the human-editable Notes section")
    parser.add_argument("--ipa", metavar="PATH",
                        help="IPA artifact to verify and record its SHA-256")
    parser.add_argument("--out", metavar="FILE",
                        help="where to write the notes "
                             "(default: release-notes-<marketing>-<build>.md)")
    parser.add_argument("--manifest-out", metavar="FILE",
                        help="where to write the manifest JSON "
                             "(default: release-manifest-<marketing>-<build>.json)")
    parser.add_argument("--write-project", action="store_true",
                        help="actually update the version in project.pbxproj")
    parser.add_argument("--dry-run", action="store_true",
                        help="print everything, write nothing")
    parser.add_argument("--project", metavar="FILE", default=str(PBXPROJ),
                        help="project.pbxproj to read (default: the repo one)")
    args = parser.parse_args(argv)

    current = read_project_version(args.project)
    if current is None:
        print("error: cannot read a consistent version from "
              f"{args.project}", file=sys.stderr)
        return 1
    current_marketing, current_build = current

    target_marketing = args.version if args.version is not None else current_marketing
    if args.build is not None:
        target_build = args.build
    elif args.bump_build:
        target_build = current_build + 1
    else:
        target_build = current_build
    target = parse_version(target_marketing, str(target_build))
    if target is None:
        print(f"error: invalid target version: {target_marketing} "
              f"({target_build})", file=sys.stderr)
        return 1
    target_marketing, target_build = target

    entries = []
    if args.prs:
        try:
            entries = parse_prs_file(args.prs)
        except (OSError, ValueError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    notes = None
    if args.notes_file:
        try:
            notes = Path(args.notes_file).read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: cannot read notes file: {exc}", file=sys.stderr)
            return 1

    ipa_sha256 = None
    ipa_size = None
    if args.ipa:
        ipa_path = Path(args.ipa)
        if not ipa_path.is_file():
            print(f"error: IPA not found: {args.ipa}", file=sys.stderr)
            return 1
        ipa_sha256, ipa_size = sha256_file(ipa_path)
    else:
        print("warning: no --ipa given, so no IPA was verified; "
              "the manifest will record no IPA.", file=sys.stderr)

    rendered = render_notes(target_marketing, target_build, entries, notes)
    manifest = build_manifest(
        target_marketing, target_build, entries,
        args.ipa, ipa_sha256, ipa_size)
    notes_out = args.out or f"release-notes-{target_marketing}-{target_build}.md"
    manifest_out = args.manifest_out or (
        f"release-manifest-{target_marketing}-{target_build}.json")

    if args.dry_run:
        print(f"current version: {current_marketing} (Build {current_build})")
        print(f"target version:  {target_marketing} (Build {target_build})")
        print()
        print(rendered, end="")
        print("--- manifest ---")
        print(json.dumps(manifest, indent=2, ensure_ascii=False))
        if not args.write_project:
            print()
            print(manual_bump_steps(target_marketing, target_build))
        return 0

    if args.write_project:
        try:
            bump_project_version(args.project, target_marketing, target_build)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        print(f"updated {args.project} to "
              f"{target_marketing} (Build {target_build})")
    else:
        print(manual_bump_steps(target_marketing, target_build))

    Path(notes_out).write_text(rendered, encoding="utf-8")
    Path(manifest_out).write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    print(f"wrote {notes_out}")
    print(f"wrote {manifest_out}")
    if ipa_sha256 is not None:
        print(f"IPA SHA-256: {ipa_sha256} ({ipa_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
