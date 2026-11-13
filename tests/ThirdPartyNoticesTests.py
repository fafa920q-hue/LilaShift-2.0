import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"
LICENSES_DIR = ROOT / "GestaltX" / "Licenses"
ABOUT_VIEW = ROOT / "GestaltX" / "AboutView.swift"

# Every third-party project the tree actually uses (see THIRD_PARTY_NOTICES.md
# for what each contributes). Distinctive strings, so "Erosion" cannot pass
# on the strength of "Erosion-CN" alone.
REQUIRED_NOTICE_NAMES = (
    "GestaltX",
    "huamidev",
    "@steam8871",
    "worse_query",
    "Ketamine",
    "NeoSpring",
    "LCSign",
    "Erosion-CN",
    "jailbreakdotparty/Erosion",
    "Gester",
    "ZIPFoundation",
    "Primer Octicons",
    "MGKeys",
    "Nugget",
    "mond",
    "GestaltEdit",
)

# Projects the in-app Credits & Licenses page must show, matching the
# completed notices file.
REQUIRED_ABOUT_NAMES = (
    "worse_query",
    "NeoSpring",
    "Ketamine",
    "MGKeys",
    "Nugget",
    "mond",
    "GestaltEdit",
    "LCSign",
    "Gester",
    "Erosion",
    "Erosion-CN",
    "ZIPFoundation",
    "Primer Octicons",
    "huamidev",
    "@steam8871",
)


class ThirdPartyNoticesTests(unittest.TestCase):
    def test_notices_file_exists_and_names_required_projects(self):
        self.assertTrue(NOTICES.is_file(), "THIRD_PARTY_NOTICES.md is missing")
        text = NOTICES.read_text(encoding="utf-8")
        for name in REQUIRED_NOTICE_NAMES:
            with self.subTest(project=name):
                self.assertIn(name, text)

    def test_notices_distinguishes_usage_kinds(self):
        text = NOTICES.read_text(encoding="utf-8")
        for kind in ("bundled code", "adapted code", "reused data",
                     "design reference", "research reference"):
            with self.subTest(kind=kind):
                self.assertIn(kind, text)

    def test_license_files_named_in_notices_exist_and_are_nonempty(self):
        text = NOTICES.read_text(encoding="utf-8")
        named = sorted(set(re.findall(r"[A-Za-z0-9][\w.-]*\.txt", text)))
        self.assertTrue(named, "no license files named in notices")
        for filename in named:
            with self.subTest(file=filename):
                path = LICENSES_DIR / filename
                self.assertTrue(path.is_file(), f"{filename} missing from GestaltX/Licenses/")
                self.assertGreater(path.stat().st_size, 0, f"{filename} is empty")

    def test_bundled_gpl_texts_match_root_license(self):
        root_license = (ROOT / "LICENSE").read_bytes()
        for filename in ("GestaltX-GPL-3.0.txt", "Erosion-GPL-3.0.txt"):
            with self.subTest(file=filename):
                self.assertEqual((LICENSES_DIR / filename).read_bytes(), root_license)

    def test_bundled_mit_texts_carry_the_permission_grant(self):
        for filename in ("Gester-MIT.txt", "ZIPFoundation-MIT.txt",
                         "Primer-Octicons-MIT.txt"):
            with self.subTest(file=filename):
                text = (LICENSES_DIR / filename).read_text(encoding="utf-8")
                self.assertIn("MIT License", text)
                self.assertIn("Permission is hereby granted, free of charge", text)

    def test_about_credits_match_notices(self):
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        for name in REQUIRED_ABOUT_NAMES:
            with self.subTest(project=name):
                self.assertIn(name, text)

    def test_about_license_files_exist_in_bundle(self):
        text = ABOUT_VIEW.read_text(encoding="utf-8")
        referenced = sorted(set(re.findall(r'file: "([^"]+)"', text)))
        self.assertTrue(referenced, "no licensedCredit files in AboutView")
        for name in referenced:
            with self.subTest(file=name):
                path = LICENSES_DIR / f"{name}.txt"
                self.assertTrue(path.is_file(), f"{name}.txt missing from GestaltX/Licenses/")


if __name__ == "__main__":
    unittest.main()
