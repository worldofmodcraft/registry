"""Criterion 13 and A1/A4: parity with task 057's fixtures, read from the file at test time.

docs/tasks/057-transition-fixtures.json is READ here, not copied; 057-oracle.py is never imported.
"""

import json
import unittest

import support
from support import append_only


def _verdict_word(fx):
    old, new = support.fixture_pair(fx)
    v = append_only.check_entry(old, new)
    return v, ("accept" if v["verdict"] == "accepted" else "reject")


class FixtureCountGuard(unittest.TestCase):
    """A4: the parity test cannot pass by reading nothing."""

    def test_a4_fixture_file_is_readable_and_large_enough(self):
        fixtures = json.loads(support.FIXTURES_PATH.read_text())  # raises (test errors) if unreadable
        self.assertGreaterEqual(len(fixtures), 73, "057 fixture file shrank below 73 fixtures")
        accepts = [f for f in fixtures if f["expect"] == "accept"]
        self.assertGreaterEqual(len(accepts), 11, "057 fixture file holds fewer than 11 accept fixtures")

    def test_a4_every_fixture_names_a_recorded_expectation(self):
        for fx in support.load_fixtures():
            self.assertIn(fx["expect"], ("accept", "reject"), fx["name"])


class Parity(unittest.TestCase):
    def test_parity_every_fixture_matches_recorded_expectation(self):
        fixtures = support.load_fixtures()
        self.assertGreaterEqual(len(fixtures), 73)  # a loop over nothing proves nothing
        disagreements = 0
        for fx in fixtures:
            with self.subTest(name=fx["name"]):
                v, got = _verdict_word(fx)
                if got != fx["expect"]:
                    disagreements += 1
                self.assertEqual(got, fx["expect"], f"{fx['name']}: {[f['message'] for f in v['findings']]}")
        self.assertEqual(disagreements, 0)

    def test_parity_every_reject_fixture_carries_a_rule_and_a_message(self):
        """Criterion 10 over the whole corpus: no rejection is silent or unattributed."""
        for fx in support.load_fixtures():
            if fx["expect"] != "reject":
                continue
            with self.subTest(name=fx["name"]):
                v, _ = _verdict_word(fx)
                self.assertTrue(v["findings"], "rejected without a finding")
                for f in v["findings"]:
                    self.assertTrue(f["rules"])
                    self.assertIn("To fix:", f["message"])
                    self.assertIn("(", f["message"])
                    self.assertIn(f["rules"][0], f["message"])

    def test_parity_every_reject_fixture_has_a_violation_element_or_entry_level_finding(self):
        for fx in support.load_fixtures():
            if fx["expect"] != "reject":
                continue
            with self.subTest(name=fx["name"]):
                v, _ = _verdict_word(fx)
                violating = [e for e in v["elements"] if e["classification"] == "violation"]
                entry_level = [f for f in v["findings"] if f["index"] is None]
                self.assertTrue(violating or entry_level)


class ElementClassificationOfAcceptFixtures(unittest.TestCase):
    """A1: which element, which transition, for the T1/T2/T3 accept fixtures."""

    def _by_name(self, name):
        for fx in support.load_fixtures():
            if fx["name"] == name:
                old, new = support.fixture_pair(fx)
                return append_only.check_entry(old, new)
        self.fail(f"fixture {name} not found in 057-transition-fixtures.json")

    def _classes(self, name):
        v = self._by_name(name)
        return [e["classification"] for e in v["elements"]], v["authority_required"]

    def test_a1_t1_exact(self):
        classes, authority = self._classes("t1-exact")
        self.assertEqual(classes[0], "T1")
        self.assertEqual(authority, ["T1"])

    def test_a1_t2_takedown_exact(self):
        classes, authority = self._classes("t2-takedown-exact")
        self.assertIn("T2", classes)
        self.assertEqual(classes.count("T2"), 1)
        self.assertEqual(authority, ["T2"])

    def test_a1_t3_exact(self):
        classes, authority = self._classes("t3-exact")
        self.assertIn("T3", classes)
        self.assertEqual(classes.count("T3"), 1)
        self.assertEqual(authority, ["T3"])

    def test_a1_t2_and_t1_on_two_elements(self):
        classes, authority = self._classes("t1-two-elements-two-transitions")
        self.assertEqual(classes, ["T2", "T1"])  # element 0 is the takedown, element 1 the write-back
        self.assertEqual(authority, ["T1", "T2"])

    def test_a1_t1_and_t3_on_different_elements(self):
        classes, authority = self._classes("t1-and-t3-different-elements")
        self.assertEqual(classes, ["T1", "T3"])  # element 0 write-back, element 1 rejection
        self.assertEqual(authority, ["T1", "T3"])

    def test_a1_t1_with_whitespace_and_key_order_changes_elsewhere(self):
        classes, authority = self._classes("t1-plus-whitespace-and-key-order-change-elsewhere")
        self.assertEqual(classes.count("T1"), 1)
        self.assertEqual(authority, ["T1"])

    def test_a1_every_authority_list_is_exactly_the_transitions_present(self):
        """Every T1/T2/T3 accept fixture yields the exact list (derived from its elements, then
        compared with an independent recount of statuses old vs new)."""
        seen = 0
        for fx in support.load_fixtures():
            if fx["expect"] != "accept":
                continue
            old, new = support.fixture_pair(fx)
            v = append_only.check_entry(old, new)
            want = set()
            for i, o in enumerate((old or {"versions": []})["versions"]):
                w = new["versions"][i]
                pair = (o["status"], w["status"])
                if o != w:
                    want.add({("pending", "published"): "T1", ("published", "removed"): "T2",
                              ("pending", "rejected"): "T3"}[pair])
            with self.subTest(name=fx["name"]):
                self.assertEqual(v["authority_required"], sorted(want))
            seen += 1
        self.assertEqual(seen, 11)

    def test_a1_plain_accepts_need_no_authority(self):
        for name in ("first-publish-one-pending", "append-second-pending-after-published", "unchanged-mixed-states"):
            with self.subTest(name=name):
                self.assertEqual(self._by_name(name)["authority_required"], [])


if __name__ == "__main__":
    unittest.main()
