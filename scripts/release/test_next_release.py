"""Tests for reading git history. Run: python -m unittest discover -s scripts/release"""

import unittest

from next_release import parse_log


class ParseLogTest(unittest.TestCase):
    def test_reads_subject_and_body(self):
        raw = "a1\x1ffeat: pair\x1fBody line\x1e\nb2\x1ffix!: crash\x1f\x1e\n"
        parsed = parse_log(raw)
        self.assertEqual([c.sha for c in parsed], ["a1", "b2"])
        self.assertEqual(parsed[0].type, "feat")
        self.assertTrue(parsed[1].breaking)

    def test_empty_log(self):
        self.assertEqual(parse_log(""), [])


if __name__ == "__main__":
    unittest.main()
