#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Tests for scripts/prepare-release.py (release preparation).

Covers version parsing/validation, PR-list parsing, notes
rendering (mirroring the expected output of the Swift
ReleaseNotesTests), project-version reading/bumping, and IPA
SHA-256 recording. Pure logic — no network, no device, no
MobileGestalt cache.

Run: python3 tests/PrepareReleaseTests.py
"""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "prepare-release.py"


def load_prepare_release():
    spec = importlib.util.spec_from_file_location(
        "prepare_release", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pr = load_prepare_release()


class VersionParsingTests(unittest.TestCase):
    def test_parse_valid_version(self):
        self.assertEqual(
            pr.parse_version("1.0.8", "11130113"), ("1.0.8", 11130113))
        self.assertEqual(
            pr.parse_version("0.0.0", "1"), ("0.0.0", 1))

    def test_parse_rejects_malformed_marketing_version(self):
        for bad in ("1.0", "1.0.8.1", "01.0.8", "1.0.x", "",
                    "1..8", "1.0.8 ", " 1.0.8", "v1.0.8"):
            with self.subTest(value=bad):
                self.assertIsNone(pr.parse_version(bad, "11130113"))

    def test_parse_rejects_invalid_build(self):
        for bad in ("0", "01", "abc", "", "-1", "99999999999999999999"):
            with self.subTest(value=bad):
                self.assertIsNone(pr.parse_version("1.0.8", bad))

    def test_is_valid_marketing_and_build(self):
        self.assertTrue(pr.is_valid_marketing("1.0.7"))
        self.assertFalse(pr.is_valid_marketing("1.0"))
        self.assertTrue(pr.is_valid_build("11130112"))
        self.assertFalse(pr.is_valid_build("0"))
        self.assertFalse(pr.is_valid_build("01"))


class NotesRenderingTests(unittest.TestCase):
    def test_render_empty_notes(self):
        self.assertEqual(
            pr.render_notes("1.0.8", 11130113, []),
            "## LilaShift 1.0.8 (Build 11130113)\n")

    def test_render_groups_sections_and_keeps_order(self):
        # Mirrors Swift ReleaseNotesTests.testRenderGroupsSectionsAndKeepsOrder.
        entries = [
            {"number": 9, "title": "Add snapshot tests", "section": "added"},
            {"number": None, "title": "Manual item", "section": "added"},
            {"number": 8, "title": "Fix a bug", "section": "fixed"},
        ]
        self.assertEqual(
            pr.render_notes("1.0.8", 11130113, entries,
                            "Known limitation: none."),
            "## LilaShift 1.0.8 (Build 11130113)\n"
            "\n"
            "### Added\n"
            "\n"
            "- Add snapshot tests (#9)\n"
            "- Manual item\n"
            "\n"
            "### Fixed\n"
            "\n"
            "- Fix a bug (#8)\n"
            "\n"
            "### Notes\n"
            "\n"
            "Known limitation: none.\n")

    def test_render_omits_empty_sections_and_blank_notes(self):
        # Mirrors Swift ReleaseNotesTests.testRenderOmitsEmptySectionsAndBlankNotes.
        entries = [
            {"number": 7, "title": "Change the theme", "section": "changed"},
        ]
        self.assertEqual(
            pr.render_notes("1.0.8", 11130113, entries, "   \n  "),
            "## LilaShift 1.0.8 (Build 11130113)\n"
            "\n"
            "### Changed\n"
            "\n"
            "- Change the theme (#7)\n")

    def test_render_sections_appear_in_added_changed_fixed_order(self):
        # Input order is fixed, changed, added; output must still be
        # Added, Changed, Fixed.
        entries = [
            {"number": 3, "title": "Fix it", "section": "fixed"},
            {"number": 2, "title": "Change it", "section": "changed"},
            {"number": 1, "title": "Add it", "section": "added"},
        ]
        rendered = pr.render_notes("1.0.8", 11130113, entries)
        self.assertLess(rendered.index("### Added"),
                        rendered.index("### Changed"))
        self.assertLess(rendered.index("### Changed"),
                        rendered.index("### Fixed"))
        self.assertTrue(rendered.endswith("\n"))
        self.assertFalse(rendered.endswith("\n\n"))


class PrsParsingTests(unittest.TestCase):
    def _write_prs(self, directory, text):
        path = Path(directory) / "prs.txt"
        path.write_text(text, encoding="utf-8")
        return path

    def test_parse_valid_prs(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_prs(
                tmp,
                "9|added|SwiftUI snapshot tests\n"
                "8|fixed|Diagnostics actor isolation in tests\n")
            entries = pr.parse_prs_file(path)
        self.assertEqual(entries, [
            {"number": 9, "title": "SwiftUI snapshot tests", "section": "added"},
            {"number": 8, "title": "Diagnostics actor isolation in tests",
             "section": "fixed"},
        ])

    def test_parse_skips_comments_and_blank_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_prs(
                tmp,
                "# a comment\n"
                "\n"
                "9|added|SwiftUI snapshot tests\n"
                "   \n")
            entries = pr.parse_prs_file(path)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["number"], 9)

    def test_parse_empty_number_is_a_manual_item(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_prs(tmp, "|added|Manual item\n")
            entries = pr.parse_prs_file(path)
        self.assertEqual(entries, [
            {"number": None, "title": "Manual item", "section": "added"},
        ])

    def test_parse_rejects_malformed_lines(self):
        bad_lines = [
            "9|added",                      # missing title
            "0|added|Zero PR number",
            "-1|added|Negative PR number",
            "abc|added|Non-numeric PR number",
            "9|other|Unknown section",
            "9|added|   ",                  # empty title
        ]
        for bad in bad_lines:
            with tempfile.TemporaryDirectory() as tmp:
                path = self._write_prs(tmp, bad + "\n")
                with self.subTest(line=bad):
                    with self.assertRaises(ValueError):
                        pr.parse_prs_file(path)


class ProjectVersionTests(unittest.TestCase):
    PBXPROJ_SAMPLE = (
        "\t\t\t\tCURRENT_PROJECT_VERSION = 11130112;\n"
        "\t\t\t\tMARKETING_VERSION = 1.0.7;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 11130112;\n"
        "\t\t\t\tMARKETING_VERSION = 1.0.7;\n")

    def _write_pbxproj(self, directory, text):
        path = Path(directory) / "project.pbxproj"
        path.write_text(text, encoding="utf-8")
        return path

    def test_read_project_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_pbxproj(tmp, self.PBXPROJ_SAMPLE)
            self.assertEqual(pr.read_project_version(path), ("1.0.7", 11130112))

    def test_read_rejects_inconsistent_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_pbxproj(
                tmp,
                "\t\t\t\tMARKETING_VERSION = 1.0.7;\n"
                "\t\t\t\tMARKETING_VERSION = 1.0.8;\n"
                "\t\t\t\tCURRENT_PROJECT_VERSION = 11130112;\n")
            self.assertIsNone(pr.read_project_version(path))

    def test_read_rejects_missing_file(self):
        self.assertIsNone(
            pr.read_project_version("/nonexistent/project.pbxproj"))

    def test_read_real_project_version(self):
        self.assertEqual(
            pr.read_project_version(),
            ("1.0.7", 11130112))

    def test_bump_project_version_updates_all_occurrences(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_pbxproj(tmp, self.PBXPROJ_SAMPLE)
            self.assertTrue(
                pr.bump_project_version(path, "1.0.8", 11130113))
            text = path.read_text(encoding="utf-8")
            self.assertEqual(text.count("MARKETING_VERSION = 1.0.8;"), 2)
            self.assertEqual(text.count("CURRENT_PROJECT_VERSION = 11130113;"), 2)
            self.assertEqual(pr.read_project_version(path), ("1.0.8", 11130113))

    def test_bump_rejects_invalid_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_pbxproj(tmp, self.PBXPROJ_SAMPLE)
            with self.assertRaises(ValueError):
                pr.bump_project_version(path, "1.0", 11130113)
            with self.assertRaises(ValueError):
                pr.bump_project_version(path, "1.0.8", 0)
            # The file is untouched after a failed bump.
            self.assertEqual(pr.read_project_version(path), ("1.0.7", 11130112))


class IpaAndManifestTests(unittest.TestCase):
    def test_sha256_file(self):
        content = b"fake-ipa-bytes"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "LilaShift.ipa"
            path.write_bytes(content)
            digest, size = pr.sha256_file(path)
        self.assertEqual(digest, hashlib.sha256(content).hexdigest())
        self.assertEqual(size, len(content))

    def test_build_manifest(self):
        entries = [
            {"number": 9, "title": "Add snapshot tests", "section": "added"},
        ]
        manifest = pr.build_manifest(
            "1.0.8", 11130113, entries,
            "/tmp/LilaShift.ipa", "deadbeef", 12345)
        self.assertEqual(manifest["marketing_version"], "1.0.8")
        self.assertEqual(manifest["build"], 11130113)
        self.assertEqual(manifest["tag"], "v1.0.8")
        self.assertEqual(manifest["prs"], entries)
        self.assertEqual(manifest["ipa"]["sha256"], "deadbeef")
        self.assertEqual(manifest["ipa"]["size_bytes"], 12345)
        # The manifest must be JSON-serialisable.
        json.dumps(manifest)

    def test_build_manifest_without_ipa(self):
        manifest = pr.build_manifest("1.0.8", 11130113, [], None, None, None)
        self.assertIsNone(manifest["ipa"])


if __name__ == "__main__":
    unittest.main()
