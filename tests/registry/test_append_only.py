"""append_only: the hostile and positive fixtures (criteria 3, 7-shape, 9, 10, A2, A5), written as code.

Every hostile test here has a mutation in tests/registry/mutate.py that makes it red; a hostile test that
cannot be reddened proves nothing (MANAGER.md 2c rule 5).
"""

import copy
import unittest

import support
from support import (OWNER, append_only, attacker_entry, entry, pending, published, rejected, removed,
                     schema, schema_check)


def check(old, new):
    return append_only.check_entry(old, new)


def classes(v):
    return [e["classification"] for e in v["elements"]]


class FileLevelStates(unittest.TestCase):
    def test_absent_to_absent_is_accepted_and_empty(self):
        v = check(None, None)
        self.assertEqual((v["verdict"], v["state"], v["elements"]), ("accepted", "absent->absent", []))

    def test_present_to_absent_is_a_deletion_violation(self):
        v = check(entry(published()), None)
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(v["state"], "present->absent")
        self.assertEqual(v["findings"][0]["rules"], ["deletion"])

    def test_deleting_an_entry_with_only_a_pending_version_is_still_a_violation(self):
        self.assertEqual(check(entry(pending()), None)["verdict"], "rejected")

    def test_rename_is_a_deletion_plus_a_creation_and_is_rejected(self):
        e = entry(pending())
        v = append_only.check_pr({"mods/kelsi.housing/entry.json": (e, None),
                                  "mods/kelsi.homes/entry.json": (None, copy.deepcopy(e))})
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(v["states"], {"mods/kelsi.housing/entry.json": "present->absent",
                                       "mods/kelsi.homes/entry.json": "absent->present"})
        self.assertEqual([f["rules"] for f in v["findings"]], [["deletion"]])
        self.assertEqual(v["findings"][0]["path"], "mods/kelsi.housing/entry.json")

    def test_clean_first_publish_is_accepted_positive_control(self):
        v = check(None, entry(pending("1.0.0"), pending("1.1.0", commit="b" * 40)))
        self.assertEqual((v["verdict"], v["state"]), ("accepted", "absent->present"))
        self.assertEqual(classes(v), ["appended", "appended"])
        self.assertEqual(v["authority_required"], [])

    def test_clean_version_append_is_accepted_positive_control(self):
        v = check(entry(published()), entry(published(), pending("1.1.0", commit="b" * 40)))
        self.assertEqual((v["verdict"], classes(v)), ("accepted", ["unchanged", "appended"]))

    def test_non_entry_new_values_are_malformed_not_crashes(self):
        for bad in ([], {"id": "a:b", "owner": OWNER}, {"versions": "x"}, {"versions": [1]}):
            with self.subTest(bad=bad):
                v = check(None, bad)
                self.assertEqual(v["verdict"], "rejected")
                self.assertEqual(v["findings"][0]["rules"], ["malformed"])

    def test_a_malformed_merge_base_is_a_tool_error_not_a_rejection(self):
        with self.assertRaises(support.report.ToolError):
            check({"versions": "nope"}, entry(pending()))


class FrozenFields(unittest.TestCase):
    def test_id_change_is_rejected(self):
        old = entry(published())
        new = entry(published(), id="kelsi:other")
        v = check(old, new)
        self.assertEqual([f["rules"] for f in v["findings"]], [["id-freeze"]])

    def test_each_owner_subfield_change_is_rejected(self):
        for field, value in (("provider", "gitlab"), ("id", 1), ("name_at_registration", "renamed")):
            with self.subTest(field=field):
                owner = dict(OWNER, **{field: value})
                v = check(entry(published()), entry(published(), owner=owner))
                self.assertEqual([f["rules"] for f in v["findings"]], [["owner-freeze"]])

    def test_owner_id_true_is_not_the_number_one(self):
        """Python's True == 1; parsed JSON true must not pass as the number 1."""
        old = entry(published(), owner=dict(OWNER, id=1))
        new = entry(published(), owner=dict(OWNER, id=True))
        self.assertEqual(check(old, new)["findings"][0]["rules"], ["owner-freeze"])

    def test_owner_key_order_alone_is_not_a_violation(self):
        reordered = {"name_at_registration": "kelsi", "id": 4831207, "provider": "github"}
        self.assertEqual(check(entry(published()), entry(published(), owner=reordered))["verdict"], "accepted")


class Rule1InPlaceEdits(unittest.TestCase):
    def test_in_place_edit_of_a_published_element_is_rule_1(self):
        w = published()
        w["source_sha256"] = "d" * 64
        v = check(entry(published()), entry(w))
        self.assertEqual(v["elements"][0]["rules"], ["rule 1"])
        self.assertEqual(classes(v), ["violation"])

    def test_in_place_edit_of_a_pending_element_is_rule_1(self):
        v = check(entry(pending()), entry(pending(commit="b" * 40)))
        self.assertEqual(v["elements"][0]["rules"], ["rule 1"])

    def test_published_to_pending_is_rule_1(self):
        v = check(entry(published()), entry(pending()))
        self.assertEqual(v["elements"][0]["rules"], ["rule 1"])

    def test_removed_and_rejected_are_frozen_completely(self):
        for old_el, new_el in ((removed(), dict(removed(), reason="A different reason.")),
                               (rejected(), dict(rejected(), reason="A different reason.")),
                               (removed(), published()), (rejected(), pending())):
            with self.subTest(old=old_el["status"], new=new_el["status"]):
                self.assertEqual(check(entry(old_el), entry(new_el))["elements"][0]["rules"], ["rule 1"])


class Rule3Truncation(unittest.TestCase):
    def test_truncating_the_array_is_rule_3(self):
        v = check(entry(published(), pending("1.1.0", "b" * 40)), entry(published()))
        self.assertEqual([f["rules"] for f in v["findings"]], [["rule 3"]])

    def test_a_rejected_version_cannot_be_deleted(self):
        v = check(entry(published(), rejected("1.1.0", "b" * 40)), entry(published()))
        self.assertEqual(v["findings"][0]["rules"], ["rule 3"])


class OrderingAndReadd(unittest.TestCase):
    def setUp(self):
        self.a, self.b, self.c = (published("1.0.0", "a" * 40), published("1.1.0", "b" * 40),
                                  published("1.2.0", "c" * 40))

    def test_reordering_identical_elements_is_a_violation_at_each_moved_index(self):
        v = check(entry(self.a, self.b), entry(self.b, self.a))
        self.assertEqual(classes(v), ["violation", "violation"])
        self.assertEqual([e["rules"] for e in v["elements"]], [["rule 1"], ["rule 1"]])

    def test_remove_and_readd_identically_is_a_violation(self):
        v = check(entry(self.a, self.b, self.c), entry(self.a, self.c, copy.deepcopy(self.b)))
        self.assertEqual(classes(v), ["unchanged", "violation", "violation"])

    def test_remove_one_and_append_identical_copy_keeps_length_but_fails(self):
        v = check(entry(self.a, self.b), entry(self.b, copy.deepcopy(self.a)))
        self.assertEqual(v["verdict"], "rejected")


class Rule2BornPending(unittest.TestCase):
    base = staticmethod(lambda: entry(published()))

    def appended(self, el):
        return check(self.base(), entry(published(), el))

    def test_born_published_removed_rejected_are_rule_2(self):
        for el in (published("1.1.0", "b" * 40), removed("1.1.0", "b" * 40), rejected("1.1.0", "b" * 40)):
            with self.subTest(status=el["status"]):
                self.assertEqual(self.appended(el)["elements"][1]["rules"], ["rule 2"])

    def test_born_pending_with_a_fifth_key_is_rule_2(self):
        el = dict(pending("1.1.0", "b" * 40), reason="why")
        self.assertEqual(self.appended(el)["elements"][1]["rules"], ["rule 2"])

    def test_born_pending_with_a_bad_commit_or_url_is_rule_2(self):
        for k, bad in (("commit", "ABC"), ("source_url", "not a url"), ("version", "1.0")):
            with self.subTest(field=k):
                el = dict(pending("1.1.0", "b" * 40), **{k: bad})
                self.assertIn("rule 2", self.appended(el)["elements"][1]["rules"])

    def test_born_pending_missing_a_key_is_rule_2(self):
        el = pending("1.1.0", "b" * 40)
        del el["source_url"]
        self.assertIn("rule 2", self.appended(el)["elements"][1]["rules"])

    def test_first_publish_is_not_exempt_from_rule_2(self):
        self.assertEqual(check(None, entry(published()))["elements"][0]["rules"], ["rule 2"])


class Rule4Uniqueness(unittest.TestCase):
    def test_duplicate_against_history_is_rule_4(self):
        v = check(entry(published("1.0.0")), entry(published("1.0.0"), pending("1.0.0", "b" * 40)))
        self.assertEqual(v["elements"][1]["rules"], ["rule 4"])

    def test_duplicate_between_two_new_elements_flags_both_with_rule_4(self):
        v = check(entry(published("1.0.0")), entry(published("1.0.0"), pending("2.0.0", "b" * 40),
                                                     pending("2.0.0", "c" * 40)))
        self.assertEqual([e["rules"] for e in v["elements"]], [[], ["rule 4"], ["rule 4"]])

    def test_a_rejected_version_string_stays_occupied(self):
        v = check(entry(rejected("1.0.0")), entry(rejected("1.0.0"), pending("1.0.0", "b" * 40)))
        self.assertEqual(v["elements"][1]["rules"], ["rule 4"])

    def test_rule_5_semver_equivalent_strings_do_not_collide(self):
        v = check(entry(published("1.0.0")), entry(published("1.0.0"), pending("1.0.0+build.2", "b" * 40)))
        self.assertEqual(v["verdict"], "accepted")

    def test_rule_5_versions_need_not_increase(self):
        v = check(entry(published("2.0.0")), entry(published("2.0.0"), pending("0.0.1", "b" * 40)))
        self.assertEqual(v["verdict"], "accepted")


class T1Variants(unittest.TestCase):
    def t1(self, **change):
        w = published()
        for k, val in change.items():
            if val is None:
                w.pop(k, None)
            else:
                w[k] = val
        return check(entry(pending()), entry(w))

    def test_exact_t1_is_shape_legal_and_needs_authority(self):
        v = self.t1()
        self.assertEqual((v["verdict"], classes(v), v["authority_required"]), ("accepted", ["T1"], ["T1"]))

    def test_t1_with_a_missing_pipeline_field_a_reason_or_a_changed_author_field_is_rule_1(self):
        for change in ({"signature": None}, {"reason": "x"}, {"commit": "b" * 40}, {"source_sha256": "zz"},
                       {"source_archive": "http://x/y"}, {"published_at": "yesterday"}, {"key_id": ""}):
            with self.subTest(change=change):
                v = self.t1(**change)
                self.assertEqual(v["elements"][0]["rules"], ["rule 1"])
                self.assertEqual(v["elements"][0]["attempted"], "T1")


class T2Variants(unittest.TestCase):
    def t2(self, old_el=None, **change):
        w = removed()
        for k, val in change.items():
            if val is None:
                w.pop(k, None)
            else:
                w[k] = val
        return check(entry(old_el or published()), entry(w))

    def test_exact_t2_is_shape_legal_and_needs_authority(self):
        v = self.t2()
        self.assertEqual((v["verdict"], classes(v), v["authority_required"]), ("accepted", ["T2"], ["T2"]))

    def test_t2_that_also_changes_another_field_is_rejected(self):
        for field, val in (("source_sha256", "d" * 64), ("commit", "b" * 40), ("signature", "z" * 5),
                           ("published_at", "2027-01-01T00:00:00Z"), ("version", "9.9.9")):
            with self.subTest(field=field):
                self.assertEqual(self.t2(**{field: val})["elements"][0]["rules"], ["rule 1"])

    def test_t2_reason_must_be_present_a_string_and_non_blank_after_trim(self):
        for reason in (None, "", "   ", "\t", "\n\n", 7, ["x"]):
            with self.subTest(reason=reason):
                self.assertEqual(self.t2(reason=reason)["elements"][0]["rules"], ["rule 1"])

    def test_t2_reason_is_trimmed_only_to_decide_emptiness(self):
        self.assertEqual(self.t2(reason="  padded but real  ")["verdict"], "accepted")

    def test_takedown_from_an_old_status_other_than_published_is_rejected(self):
        for old_el in (pending(), rejected()):
            with self.subTest(old=old_el["status"]):
                v = check(entry(old_el), entry(removed()))
                self.assertEqual(v["elements"][0]["rules"], ["rule 1"])
                self.assertEqual(v["authority_required"], [])

    def test_t2_with_an_extra_key_is_rejected(self):
        self.assertEqual(self.t2(build_log_url="https://x.example/y")["elements"][0]["rules"], ["rule 1"])


class T3Variants(unittest.TestCase):
    def t3(self, **change):
        w = rejected()
        for k, val in change.items():
            if val is None:
                w.pop(k, None)
            else:
                w[k] = val
        return check(entry(pending()), entry(w))

    def test_exact_t3_is_shape_legal_and_needs_authority(self):
        v = self.t3()
        self.assertEqual((v["verdict"], classes(v), v["authority_required"]), ("accepted", ["T3"], ["T3"]))

    def test_t3_hostile_variants_are_rule_1(self):
        for change in ({"build_log_url": "http://builds.example.org/log"}, {"build_log_url": None},
                       {"reason": None}, {"reason": "   "}, {"reason": 5}, {"extra": "k"},
                       {"signature": "c" * 62}, {"commit": "b" * 40}, {"build_log_url": "https://has space/x"}):
            with self.subTest(change=change):
                self.assertEqual(self.t3(**change)["elements"][0]["rules"], ["rule 1"])

    def test_published_to_rejected_is_rule_1(self):
        self.assertEqual(check(entry(published()), entry(rejected()))["elements"][0]["rules"], ["rule 1"])


class CoexistenceAndMultiT2(unittest.TestCase):
    """A5, and the shape layer's treatment of coexisting transitions."""

    def test_a5_two_valid_t2s_are_shape_accepted_with_t2_authority(self):
        old = entry(published("1.0.0", "a" * 40), published("1.1.0", "b" * 40))
        new = entry(removed("1.0.0", "a" * 40), removed("1.1.0", "b" * 40, reason="Another legal ground."))
        v = check(old, new)
        self.assertEqual((v["verdict"], classes(v), v["authority_required"]), ("accepted", ["T2", "T2"], ["T2"]))

    def test_a5_one_valid_t2_and_one_other_in_place_change_rejects_naming_the_second(self):
        edited = published("1.1.0", "b" * 40)
        edited["signature"] = "tampered"
        old = entry(published("1.0.0", "a" * 40), published("1.1.0", "b" * 40))
        v = check(old, entry(removed("1.0.0", "a" * 40), edited))
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(classes(v), ["T2", "violation"])
        self.assertEqual([f["index"] for f in v["findings"]], [1])
        self.assertIn("element 1", v["findings"][0]["message"])
        self.assertEqual(v["authority_required"], ["T2"])

    def test_t1_and_t2_and_t3_on_three_elements_are_shape_legal_with_all_three_listed(self):
        old = entry(pending("1.0.0", "a" * 40), published("1.1.0", "b" * 40), pending("1.2.0", "c" * 40))
        new = entry(published("1.0.0", "a" * 40), removed("1.1.0", "b" * 40), rejected("1.2.0", "c" * 40))
        v = check(old, new)
        self.assertEqual((v["verdict"], classes(v), v["authority_required"]),
                         ("accepted", ["T1", "T2", "T3"], ["T1", "T2", "T3"]))

    def test_a_transition_plus_a_legal_append_is_accepted_with_the_transition_listed(self):
        v = check(entry(pending()), entry(published(), pending("1.1.0", "b" * 40)))
        self.assertEqual((classes(v), v["authority_required"]), (["T1", "appended"], ["T1"]))


class AttackerFirstPublish(unittest.TestCase):
    """Criterion 3 re-based (umbrella revision 2026-10-15), A2. Each attribution is its own assertion."""

    def test_a2_premise_four_element_entry_is_schema_rejected(self):
        with self.assertRaises(schema_check.SchemaValidationError) as ctx:
            schema_check.validate(attacker_entry(), schema.load_schema("entry"))
        self.assertIn("versions[2]", str(ctx.exception))

    def test_a2_measured_facts_each_element_alone(self):
        """The manager's probe, re-established: elements 0, 1, 3 validate alone; element 2 does not."""
        items = schema.load_schema("entry")["properties"]["versions"]["items"]
        el = attacker_entry()["versions"]
        for i, valid in ((0, True), (1, True), (2, False), (3, True)):
            with self.subTest(element=i):
                try:
                    schema_check.validate(el[i], items)
                    got = True
                except schema_check.SchemaValidationError:
                    got = False
                self.assertEqual(got, valid)

    def test_a2_four_element_append_only_verdict_is_rejected(self):
        self.assertEqual(check(None, attacker_entry())["verdict"], "rejected")

    def test_a2_four_element_element_0_breaks_rule_2(self):
        self.assertIn("rule 2", check(None, attacker_entry())["elements"][0]["rules"])

    def test_a2_four_element_element_0_breaks_rule_4(self):
        self.assertIn("rule 4", check(None, attacker_entry())["elements"][0]["rules"])

    def test_a2_four_element_element_1_breaks_rule_2(self):
        self.assertIn("rule 2", check(None, attacker_entry())["elements"][1]["rules"])

    def test_a2_four_element_element_1_breaks_rule_4(self):
        self.assertIn("rule 4", check(None, attacker_entry())["elements"][1]["rules"])

    def test_a2_four_element_element_2_breaks_rule_2(self):
        self.assertIn("rule 2", check(None, attacker_entry())["elements"][2]["rules"])

    def test_a2_four_element_element_3_breaks_rule_2(self):
        self.assertIn("rule 2", check(None, attacker_entry())["elements"][3]["rules"])

    def test_a2_four_element_element_2_and_3_do_not_break_rule_4(self):
        v = check(None, attacker_entry())
        self.assertNotIn("rule 4", v["elements"][2]["rules"])
        self.assertNotIn("rule 4", v["elements"][3]["rules"])

    def test_a2_three_element_variant_is_schema_valid(self):
        schema_check.validate(attacker_entry((0, 1, 3)), schema.load_schema("entry"))  # raises if not valid

    def test_a2_three_element_variant_is_rejected_by_append_only(self):
        self.assertEqual(check(None, attacker_entry((0, 1, 3)))["verdict"], "rejected")

    def test_a2_three_element_variant_element_0_rules_2_and_4(self):
        r = check(None, attacker_entry((0, 1, 3)))["elements"][0]["rules"]
        self.assertIn("rule 2", r)
        self.assertIn("rule 4", r)

    def test_a2_three_element_variant_element_1_rules_2_and_4(self):
        r = check(None, attacker_entry((0, 1, 3)))["elements"][1]["rules"]
        self.assertIn("rule 2", r)
        self.assertIn("rule 4", r)

    def test_a2_three_element_variant_element_2_is_the_whitespace_reason_born_removed_rule_2(self):
        v = check(None, attacker_entry((0, 1, 3)))
        self.assertIn("rule 2", v["elements"][2]["rules"])
        self.assertEqual(attacker_entry((0, 1, 3))["versions"][2]["reason"], "   ")


class MessagesCriterion10(unittest.TestCase):
    def test_rejection_messages_name_the_problem_the_rule_and_the_remedy(self):
        v = check(None, attacker_entry())
        for f in v["findings"]:
            with self.subTest(index=f["index"]):
                self.assertIn("append-only.rules.md", f["message"])
                self.assertIn("To fix:", f["message"])
                self.assertIn(f"element {f['index']}", f["message"])
                for rule in f["rules"]:
                    self.assertIn(rule, f["message"])

    def test_element_dicts_carry_the_same_message_as_their_finding(self):
        v = check(None, attacker_entry())
        by_index = {f["index"]: f["message"] for f in v["findings"]}
        for e in v["elements"]:
            self.assertEqual(e["message"], by_index[e["index"]])

    def test_deletion_message_cites_adr_0041(self):
        f = check(entry(published()), None)["findings"][0]
        self.assertIn("ADR-0041", f["message"])
        self.assertIn("To fix:", f["message"])


class CheckPr(unittest.TestCase):
    def test_page_json_is_not_append_only_and_is_skipped(self):
        v = append_only.check_pr({"mods/kelsi.housing/page.json": ({"anything": 1}, {"anything": 2})})
        self.assertEqual((v["verdict"], v["skipped_not_append_only"]), ("accepted", ["mods/kelsi.housing/page.json"]))

    def test_unrecognised_path_is_rejected_fail_closed(self):
        v = append_only.check_pr({"mods/kelsi.housing/extra.json": (None, {})})
        self.assertEqual(v["findings"][0]["rules"], ["unrecognised-path"])

    def test_authority_is_the_union_across_entries(self):
        v = append_only.check_pr({
            "mods/a.one/entry.json": (entry(pending(), id="a:one"), entry(published(), id="a:one")),
            "mods/b.two/entry.json": (entry(published(), id="b:two"), entry(removed(), id="b:two")),
        })
        self.assertEqual((v["verdict"], v["authority_required"]), ("accepted", ["T1", "T2"]))
        self.assertEqual([e["path"] for e in v["elements"]], ["mods/a.one/entry.json", "mods/b.two/entry.json"])


if __name__ == "__main__":
    unittest.main()
