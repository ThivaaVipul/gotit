"""Tests for the release version rules. Run: python -m unittest discover -s scripts/release"""

import unittest

from version import (
    Commit,
    build_number,
    bump,
    latest_version,
    next_release,
    parse_commit,
    release_level,
    render_notes,
)


def commits(*subjects: str) -> list[Commit]:
    return [parse_commit(f"c{i}", subject) for i, subject in enumerate(subjects)]


class ParseCommitTest(unittest.TestCase):
    def test_type_scope_and_subject(self):
        commit = parse_commit("abc", "feat(link): pair with a code")
        self.assertEqual(commit.type, "feat")
        self.assertEqual(commit.scope, "link")
        self.assertEqual(commit.subject, "pair with a code")
        self.assertFalse(commit.breaking)

    def test_bang_and_footer_are_breaking(self):
        self.assertTrue(parse_commit("a", "feat!: new protocol").breaking)
        self.assertTrue(parse_commit("b", "fix: x", "BREAKING CHANGE: pair again").breaking)

    def test_not_conventional(self):
        commit = parse_commit("a", "Update things")
        self.assertIsNone(commit.type)
        self.assertFalse(commit.breaking)


class LevelTest(unittest.TestCase):
    def test_levels(self):
        self.assertEqual(release_level(commits("docs: a", "chore: b")), "none")
        self.assertEqual(release_level(commits("fix: a", "docs: b")), "patch")
        self.assertEqual(release_level(commits("fix: a", "feat: b")), "minor")
        self.assertEqual(release_level(commits("feat: a", "perf!: b")), "major")

    def test_bump(self):
        self.assertEqual(bump("0.1.2", "patch"), "0.1.3")
        self.assertEqual(bump("0.1.2", "minor"), "0.2.0")
        self.assertEqual(bump("0.1.2", "major"), "1.0.0")
        self.assertEqual(bump("0.1.2", "none"), "0.1.2")


class NextReleaseTest(unittest.TestCase):
    def test_first_feat_ships_0_1_0(self):
        result = next_release(None, "0.0.0", commits("chore: set up", "feat: updates"))
        self.assertEqual((result.release, result.version), (True, "0.1.0"))

    def test_nothing_to_ship_before_the_first_feature(self):
        result = next_release(None, "0.0.0", commits("chore: set up", "ci: releases"))
        self.assertEqual((result.release, result.version), (False, "0.0.0"))

    def test_bumps_from_the_last_release(self):
        result = next_release("0.1.0", "0.0.0", commits("fix: crash"))
        self.assertEqual((result.release, result.version), (True, "0.1.1"))

    def test_no_release_without_shipping_commits(self):
        result = next_release("0.1.0", "0.0.0", commits("docs: notes"))
        self.assertEqual((result.release, result.version), (False, "0.1.0"))

    def test_pubspec_version_forces_a_higher_one(self):
        result = next_release("0.1.0", "1.0.0", commits("docs: notes"))
        self.assertEqual((result.release, result.version), (True, "1.0.0"))

    def test_rejects_a_bad_pubspec_version(self):
        with self.assertRaises(ValueError):
            next_release(None, "1.0", [])


class HelpersTest(unittest.TestCase):
    def test_latest_version_ignores_other_tags(self):
        self.assertEqual(latest_version(["v0.2.0", "v0.10.0", "data", "v1.x"]), "0.10.0")
        self.assertIsNone(latest_version(["data"]))

    def test_build_number(self):
        self.assertEqual(build_number("0.1.0"), 1000)
        self.assertEqual(build_number("1.2.3"), 1002003)
        with self.assertRaises(ValueError):
            build_number("0.1000.0")

    def test_notes_grouped_by_type(self):
        notes = render_notes(commits("feat(link): pair", "fix: crash", "docs: x"))
        self.assertIn("### Features\n\n- **link:** pair (c0)", notes)
        self.assertIn("### Fixes\n\n- crash (c1)", notes)
        self.assertNotIn("docs", notes)

    def test_notes_without_changes(self):
        self.assertEqual(render_notes(commits("docs: x")), "Maintenance release.\n")


if __name__ == "__main__":
    unittest.main()
