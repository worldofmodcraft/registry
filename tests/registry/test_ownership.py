"""Ownership checker (task 007b, E16): ownership.md R1-R12 and I1-I9 (R12 and I9: tasks 118/120), plus the ADR-0121
fail-closed rule for changes to existing elements that are not a T1, T2 or T3.

Test names are `test_<rule>_<accept|reject>_<what>` so test_ownership_mutations.py can prove, per rule id, that a
named mutation reddens a test of that rule (B3). The unit under test never touches the network or environment.
"""

import copy
import io
import os
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import support
from support import published, pending, removed, rejected, entry as _entry, report  # noqa: F401

import ownership  # noqa: E402

ORG_ID = 324218296  # the reserved owner's recorded id (a fixture value; the checker never hard-codes it)
ORG = {"provider": "github", "id": ORG_ID, "name_at_registration": "worldofmodcraft"}
RES = {"schema_version": "1.0.0", "namespaces": {"mc": {"owner": ORG, "reason": "r"}, "test": {"owner": ORG, "reason": "r"}}}
ALICE_ID, MALLORY_ID, PIPE_ID, OTHER_ID = 100200300, 900800700, 555111, 424242
ALICE, MALLORY = ("github", ALICE_ID), ("github", MALLORY_ID)
PIPE = ("github", PIPE_ID)  # the configured pipeline identity of the R12 tests (a fixture value, never the real id)
ORG_MEMBER = ("github", 777000)
R11 = ("github", OTHER_ID)  # deliberately NOT the reserved owner's id: R11 is configuration, not reserved-list data


def own(i=ALICE_ID, name="alice", provider="github"):
    return {"provider": provider, "id": i, "name_at_registration": name}


def ent(ns, name, *versions, owner=None, id=None):
    return {"id": id or f"{ns}:{name}", "owner": copy.deepcopy(owner or (ORG if ns in ("mc", "test") else own())),
            "versions": list(versions)}


def P(ns, name, kind="entry"):
    return f"mods/{ns}.{name}/{kind}.json"


def status(n):
    return lambda org, author: n


def boom(org, author):
    raise ConnectionError("network down")


def run(author, files, oracle=status(404), reserved=RES, **kw):
    kw.setdefault("namespace_owners", {})  # an empty registry; tests of owned namespaces pass the real mapping
    return ownership.check(author, files, reserved, oracle, **kw)


def rules(v):
    return [r for f in v["findings"] for r in f["rules"]]


def add_version(ns="alice", name="cooltool", owner=None):
    old = ent(ns, name, published(), owner=owner)
    new = ent(ns, name, published(), pending("1.1.0", "b" * 40), owner=owner)
    return {P(ns, name): (old, new)}


def first_publish(ns="alice", name="cooltool", owner=None, **kw):
    return {P(ns, name): (None, ent(ns, name, pending(), owner=owner or own(**kw)))}


def takedown(ns="alice", name="cooltool", n=1, owner=None):
    old = ent(ns, name, *[published(f"1.{i}.0", f"{i:x}" * 40) for i in range(n)], owner=owner)
    new = ent(ns, name, *[removed(f"1.{i}.0", f"{i:x}" * 40) for i in range(n)], owner=owner)
    return {P(ns, name): (old, new)}


class R1Path(unittest.TestCase):
    def test_r1_accept_wellformed_paths(self):
        self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_r1_reject_malformed_and_foreign_paths(self):
        for bad in ("mods/alice.cooltool/notes.txt", "mods/a.b.c/entry.json", "mods/alice/entry.json", "README.md"):
            with self.subTest(path=bad):
                files = dict(add_version(), **{bad: (None, {"x": 1})})
                v = run(ALICE, files)
                self.assertEqual(v["verdict"], "rejected")
                self.assertTrue(any(bad in f["message"] for f in v["findings"]))


class R2Id(unittest.TestCase):
    def test_r2_accept_id_matches_directory(self):
        self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_r2_reject_new_id_names_another_namespace(self):
        old = ent("alice", "cooltool", published())
        new = ent("alice", "cooltool", published(), pending("1.1.0", "b" * 40), id="mallory:cooltool")
        v = run(ALICE, {P("alice", "cooltool"): (old, new)})
        self.assertIn("R2", rules(v))
        self.assertTrue(any("authoritative" in f["message"] and "mallory:cooltool" in f["message"] for f in v["findings"]))

    def test_r2_reject_old_id_disagrees(self):
        old = ent("alice", "cooltool", published(), id="bob:cooltool")
        new = ent("alice", "cooltool", published(), pending("1.1.0", "b" * 40))
        self.assertIn("R2", rules(run(ALICE, {P("alice", "cooltool"): (old, new)})))


class R3Existing(unittest.TestCase):
    def test_r3_accept_owner_adds_a_version(self):
        self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_r3_accept_rename_same_id_different_username(self):
        v = run(ALICE, add_version(), login="alice-renamed")
        self.assertEqual(v["verdict"], "accepted")

    def test_r3_reject_stranger(self):
        v = run(MALLORY, add_version(), login="mallory")
        self.assertEqual(rules(v), ["R3"])
        self.assertIn("alice", v["findings"][0]["message"].lower())

    def test_r3_reject_same_username_different_id(self):
        """Ludwig's required fixture: username matches name_at_registration, numeric id does not."""
        v = run(MALLORY, add_version(), login="alice")
        self.assertEqual(v["verdict"], "rejected")
        self.assertIn("R3", rules(v))
        self.assertIn(str(MALLORY_ID), v["findings"][0]["message"])

    def test_r3_reject_rebinding_an_existing_namespace_as_if_it_were_a_first_publish(self):
        """Mallory (login alice) rewrites owner to herself on alice's existing entry: judged against OLD owner."""
        old = ent("alice", "cooltool", published())
        new = ent("alice", "cooltool", published(), owner=own(MALLORY_ID, "alice"))
        v = run(MALLORY, {P("alice", "cooltool"): (old, new)}, login="alice")
        self.assertEqual(rules(v), ["R3"])

    def test_r3_reject_binding_is_not_a_bypass_for_a_second_pr(self):
        v = run(MALLORY, add_version(), login="mallory")
        self.assertEqual(v["verdict"], "rejected")


class OwnedNamespaceSibling(unittest.TestCase):
    """Amendment 1 / F1: a NEW entry.json in a namespace that already exists at the merge-base is judged by R3 on
    the recorded owner's id, never by the first-publish login rules (ownership.md Attack 4)."""

    def test_r3_reject_new_sibling_entry_by_a_stranger_whose_login_matches_the_namespace(self):
        files = first_publish("alice", "new", owner=own(MALLORY_ID, "alice"))
        v = run(MALLORY, files, login="alice", namespace_owners={"alice": ALICE})
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(sorted(rules(v)), ["R3", "R5"])

    def test_r3_accept_renamed_owner_adds_a_second_mod(self):
        v = run(ALICE, first_publish("alice", "second"), login="alice-renamed", namespace_owners={"alice": ALICE})
        self.assertEqual(v["verdict"], "accepted")

    def test_r3_reject_owners_provider_is_part_of_the_comparison(self):
        v = run(("gitlab", ALICE_ID), first_publish("alice", "second"), login="alice",
                namespace_owners={"alice": ALICE})
        self.assertEqual(rules(v), ["R3"])

    def test_r3_reject_missing_namespace_owners_fails_closed_but_empty_is_legitimate(self):
        files = first_publish("alice", "second")
        v = run(ALICE, files, login="alice", namespace_owners=None)
        self.assertEqual(rules(v), ["namespace-owners-missing"])
        self.assertIn("namespace_owners", v["findings"][0]["message"])
        self.assertEqual(run(ALICE, files, login="alice", namespace_owners={})["verdict"], "accepted")

    def test_r3_reject_owners_are_not_read_from_the_prs_own_files(self):
        """A PR cannot declare its own namespace unowned by omission or owned by itself: only the injected mapping counts."""
        files = dict(first_publish("alice", "new", owner=own(MALLORY_ID, "alice")),
                     **first_publish("alice", "other", owner=own(MALLORY_ID, "alice")))
        v = run(MALLORY, files, login="alice", namespace_owners={"alice": ALICE})
        self.assertEqual(sorted(rules(v)), ["R3", "R3", "R5", "R5"])  # one per new entry, each against the injected owner, not the PR's

    def test_r5_reject_owner_adds_a_sibling_whose_owner_field_names_another_account(self):
        """N1: the true owner may not freeze a different owner into a new entry of their own namespace."""
        files = first_publish("alice", "new", owner=own(555, "alice"))
        v = run(ALICE, files, login="alice", namespace_owners={"alice": ALICE})
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(rules(v), ["R5"])
        self.assertIn("555", v["findings"][0]["message"])


class R4R5R6FirstPublish(unittest.TestCase):
    def test_r4_accept_namespace_equals_username_case_folded(self):
        self.assertEqual(run(ALICE, first_publish(), login="Alice")["verdict"], "accepted")

    def test_r4_reject_namespace_of_someone_elses_name(self):
        files = first_publish("alice", "cooltool", owner=own(MALLORY_ID, "mallory"))
        v = run(MALLORY, files, login="mallory")
        self.assertEqual(rules(v), ["R4"])

    def test_r4_reject_without_a_login(self):
        v = run(ALICE, first_publish())
        self.assertIn("R4", rules(v))
        self.assertIn("fails closed", v["findings"][0]["message"])

    def test_r5_accept_owner_is_the_author(self):
        self.assertEqual(run(ALICE, first_publish(), login="alice")["verdict"], "accepted")

    def test_r5_reject_owner_claims_someone_elses_id(self):
        files = first_publish("alice", "cooltool", owner=own(OTHER_ID, "alice"))
        self.assertEqual(rules(run(ALICE, files, login="alice")), ["R5"])

    def test_r6_accept_name_at_registration_is_the_login(self):
        self.assertEqual(run(ALICE, first_publish(), login="alice")["verdict"], "accepted")

    def test_r6_reject_name_at_registration_is_not_the_login(self):
        files = first_publish("alice", "cooltool", owner=own(ALICE_ID, "somebody-else"))
        self.assertEqual(rules(run(ALICE, files, login="alice")), ["R6"])


class ReservedNamespaces(unittest.TestCase):
    def mc_add(self):
        return add_version("mc", "core")

    def test_r7_accept_org_member(self):
        self.assertEqual(run(ORG_MEMBER, self.mc_add(), oracle=status(204))["verdict"], "accepted")

    def test_r7_reject_non_member_naming_adr_0119(self):
        v = run(MALLORY, self.mc_add(), oracle=status(404))
        self.assertEqual(rules(v), ["R7"])
        self.assertIn("ADR-0119", v["findings"][0]["message"])

    def test_r7_reject_even_the_owner_of_an_individual_namespace_id_equality_is_not_authority(self):
        v = run(("github", ORG_ID), self.mc_add(), oracle=status(404))
        self.assertIn("R7", rules(v))

    def test_r8_accept_first_publish_with_the_recorded_org_owner(self):
        files = {P("mc", "core"): (None, ent("mc", "core", pending()))}
        self.assertEqual(run(ORG_MEMBER, files, oracle=status(204), login="member")["verdict"], "accepted")

    def test_r8_reject_first_publish_owned_by_the_author(self):
        files = {P("mc", "core"): (None, ent("mc", "core", pending(), owner=own(ORG_MEMBER[1], "member")))}
        v = run(ORG_MEMBER, files, oracle=status(204), login="member")
        self.assertEqual(rules(v), ["R8"])

    def test_r8_precedence_over_r4_r5_r6(self):
        files = {P("mc", "core"): (None, ent("mc", "core", pending()))}
        v = run(ORG_MEMBER, files, oracle=status(204), login="member")
        self.assertFalse({"R4", "R5", "R6"} & set(rules(v)))

    def test_r9_accept_only_204_and_404_are_answers(self):
        for n, want in ((204, "accepted"), (404, "rejected")):
            with self.subTest(status=n):
                self.assertEqual(run(ORG_MEMBER, self.mc_add(), oracle=status(n))["verdict"], want)
        self.assertNotIn("R9", rules(run(ORG_MEMBER, self.mc_add(), oracle=status(404))))

    def test_r9_reject_everything_else_naming_the_status(self):
        for n in (302, 301, 401, 403, 500, 200):
            with self.subTest(status=n):
                v = run(ORG_MEMBER, self.mc_add(), oracle=status(n))
                self.assertEqual(rules(v), ["R9"])
                self.assertIn(str(n), v["findings"][0]["message"])

    def test_r9_reject_oracle_exception_and_non_integer_answers(self):
        for oracle in (boom, lambda o, a: None, lambda o, a: "204", lambda o, a: True):
            with self.subTest(oracle=oracle):
                self.assertEqual(rules(run(ORG_MEMBER, self.mc_add(), oracle=oracle)), ["R9"])

    def test_i5_accept_a_direct_answer_is_used(self):
        self.assertEqual(run(ORG_MEMBER, self.mc_add(), oracle=status(204))["verdict"], "accepted")

    def test_i5_reject_a_302_is_neither_member_nor_not_member(self):
        v = run(ORG_MEMBER, self.mc_add(), oracle=status(302))
        self.assertEqual(rules(v), ["R9"])
        self.assertNotIn("R7", rules(v))
        self.assertIn("302", v["findings"][0]["message"])

    def test_i4_accept_membership_oracle_is_asked_about_the_baseline_org(self):
        asked = []
        run(ORG_MEMBER, self.mc_add(), oracle=lambda org, a: asked.append((org, a)) or 204)
        self.assertEqual(asked, [("worldofmodcraft", ORG_MEMBER)])

    def test_i4_reject_a_pr_cannot_strip_a_namespace_from_its_own_reserved_list(self):
        stripped = {"schema_version": "1.0.0", "namespaces": {"test": RES["namespaces"]["test"]}}
        files = {"reserved-namespaces.json": (RES, stripped),
                 P("mc", "core"): (None, ent("mc", "core", pending(), owner=own(MALLORY_ID, "mallory")))}
        v = run(MALLORY, files, oracle=status(404), login="mallory")
        self.assertIn("R7", rules(v))
        self.assertIn("R8", rules(v))
        self.assertIn("unrecognised-path", rules(v))


class R10Pages(unittest.TestCase):
    page = {"description": "d"}

    def test_r10_accept_page_of_an_existing_entry_by_its_owner(self):
        files = {P("alice", "cooltool", "page"): (self.page, {"description": "e"})}
        base = {P("alice", "cooltool"): ent("alice", "cooltool", published())}
        self.assertEqual(run(ALICE, files, base_entries=base)["verdict"], "accepted")

    def test_r10_accept_page_with_its_entry_created_in_the_same_pr(self):
        files = dict(first_publish(), **{P("alice", "cooltool", "page"): (None, self.page)})
        self.assertEqual(run(ALICE, files, login="alice")["verdict"], "accepted")

    def test_r10_reject_page_only_pr_with_no_entry(self):
        files = {P("alice", "cooltool", "page"): (None, self.page)}
        v = run(ALICE, files)
        self.assertEqual(rules(v), ["R10"])
        self.assertIn("no entry", v["findings"][0]["message"])

    def test_r10_reject_page_whose_sibling_is_in_the_pr_but_absent_on_both_sides(self):
        files = {P("alice", "cooltool", "page"): (None, self.page), P("alice", "cooltool"): (None, None)}
        self.assertIn("R10", rules(run(ALICE, files)))

    def test_r3_reject_page_of_someone_elses_entry(self):
        files = {P("alice", "cooltool", "page"): (self.page, {"description": "e"})}
        base = {P("alice", "cooltool"): ent("alice", "cooltool", published())}
        self.assertEqual(rules(run(MALLORY, files, base_entries=base)), ["R3"])


class Takedowns(unittest.TestCase):
    """B2: R11 authority, with r11_identity injected."""

    def test_r11_accept_one_and_two_t2s_from_the_configured_identity(self):
        for n in (1, 2):
            with self.subTest(takedowns=n):
                v = run(R11, takedown(n=n), r11_identity=R11)
                self.assertEqual((v["verdict"], v["authorised_takedown"]), ("accepted", True))

    def test_r11_accept_two_entries_in_one_pr_and_a_reserved_namespace(self):
        files = dict(takedown(), **takedown("mc", "core", owner=ORG))
        self.assertEqual(run(R11, files, r11_identity=R11)["verdict"], "accepted")

    def test_r11_reject_everyone_else(self):
        """Owner, stranger and org member are all rejected: the stranger by R3 (and R11), the owner and the member
        pass R3/R7 on their own merits but are still not the platform's identity, so R11's row rejects them."""
        cases = (("owner", ALICE, takedown(), 404), ("stranger", MALLORY, takedown(), 404),
                 ("org member", ORG_MEMBER, takedown("mc", "core", owner=ORG), 204))
        for label, author, files, st in cases:
            with self.subTest(author=label):
                v = run(author, files, r11_identity=R11, oracle=status(st))
                self.assertEqual(v["verdict"], "rejected")
                self.assertFalse(v["authorised_takedown"])
                self.assertIn("R11", rules(v))
                self.assertIn("only the platform", v["findings"][0]["message"])

    def test_r11_reject_owner_stranger_and_member_are_rejected_in_the_ordinary_way(self):
        self.assertEqual(rules(run(MALLORY, takedown(), r11_identity=R11)), ["R11", "R3"])
        self.assertEqual(rules(run(ORG_MEMBER, takedown("mc", "core", owner=ORG), r11_identity=R11,
                                   oracle=status(404))), ["R11", "R7"])

    def test_r11_reject_when_unconfigured_nobody_is_authorised(self):
        for author in (R11, ALICE, MALLORY, ("github", ORG_ID)):
            with self.subTest(author=author):
                v = run(author, takedown(), oracle=status(404))
                self.assertFalse(v["authorised_takedown"])
                self.assertIn("R11", rules(v))
        self.assertIn("authorises nobody", run(R11, takedown())["findings"][0]["message"])

    def test_r11_reject_a_takedown_plus_any_other_change(self):
        t = takedown()
        old, new = t[P("alice", "cooltool")]
        new2 = copy.deepcopy(new)
        new2["versions"].append(pending("2.0.0", "c" * 40))
        extras = {"appended version": {P("alice", "cooltool"): (old, new2)},
                  "page edit": dict(t, **{P("alice", "cooltool", "page"): ({"description": "a"}, {"description": "b"})}),
                  "new entry": dict(t, **first_publish("zed", "thing", owner=own(OTHER_ID, "zed"))),
                  "owner edit": {P("alice", "cooltool"): (old, dict(new, owner=own(OTHER_ID, "zed")))}}
        for label, files in extras.items():
            with self.subTest(change=label):
                v = run(R11, files, r11_identity=R11)
                self.assertEqual(v["verdict"], "rejected")
                self.assertFalse(v["authorised_takedown"])
                self.assertIn("R11", rules(v))  # task 075: R11 itself rejects the mixed PR

    def test_r11_reject_malformed_t2_is_not_a_takedown(self):
        old, new = takedown()[P("alice", "cooltool")]
        del new["versions"][0]["reason"]
        v = run(R11, {P("alice", "cooltool"): (old, new)}, r11_identity=R11)
        self.assertFalse(v["authorised_takedown"])
        # task 075: a raw published->removed change counts as a takedown mutation, so R11 now also rejects this PR
        self.assertEqual(rules(v), ["R11", "R3"])

    def test_r11_reject_reserved_list_edit_beside_a_t2_is_not_authorised(self):
        edited = {"schema_version": "1.0.0", "namespaces": {}}
        files = dict(takedown(), **{"reserved-namespaces.json": (RES, edited)})
        v = run(R11, files, r11_identity=R11)
        self.assertFalse(v["authorised_takedown"])
        self.assertEqual(v["verdict"], "rejected")

    def test_r11_authority_is_configuration_not_the_reserved_owner(self):
        self.assertEqual(run(R11, takedown(), r11_identity=R11)["verdict"], "accepted")
        v = run(("github", ORG_ID), takedown(), r11_identity=R11)  # the reserved owner's id, but not configured
        self.assertFalse(v["authorised_takedown"])
        edited = {"schema_version": "1.0.0", "namespaces": {"mc": {"owner": own(OTHER_ID, "x")}}}
        v = run(R11, dict(takedown(), **{"reserved-namespaces.json": (RES, edited)}), r11_identity=None)
        self.assertFalse(v["authorised_takedown"])

    def test_r11_precedence_is_authority_based_not_shape_based(self):
        """Attempt 9: a takedown-shaped PR from a non-authorised account is judged by R3 in full."""
        v = run(MALLORY, takedown(), r11_identity=R11)
        self.assertIn("R3", rules(v))
        v = run(MALLORY, takedown(), r11_identity=None)
        self.assertIn("R3", rules(v))

    def test_i9_reject_pipeline_identity_equal_to_r11_identity_is_no_verdict_not_even_for_a_takedown(self):
        """Task 120: replaces the 008b-3a app-id case. One account may not hold R11 and R12 (I9)."""
        with self.assertRaises(report.ToolError):
            run(R11, takedown(), r11_identity=R11, pipeline_identity=R11)


def removal_plus_new_version(ns="alice", name="cooltool", owner=None):
    """One entry: element 0 is taken down (T2) and a pending version is appended in the same file."""
    old, new = takedown(ns, name, owner=owner)[P(ns, name)]
    new = copy.deepcopy(new)
    new["versions"].append(pending("2.0.0", "c" * 40))
    return {P(ns, name): (old, new)}


class R11MixedPr(unittest.TestCase):
    """Task 075: ANY PR whose diff contains a takedown mutation is rejected by R11 unless it is nothing but takedown
    mutations from the platform's own identity (ADR-0041:15; Ludwig 2026-10-17). Whoever the author is."""

    def assertR11Mixed(self, v, msg=""):
        self.assertEqual(v["verdict"], "rejected", msg)
        self.assertFalse(v["authorised_takedown"], msg)
        hits = [f for f in v["findings"] if "R11" in f["rules"] and "split" in f["message"].lower()]
        self.assertTrue(hits, f"no R11 finding saying to split the PR: {v['findings']!r} {msg}")

    def test_r11_reject_owner_bundling_a_removal_with_a_new_version(self):
        v = run(ALICE, removal_plus_new_version(), r11_identity=R11, namespace_owners={"alice": ALICE})
        self.assertR11Mixed(v)

    def test_r11_reject_platform_identity_bundling_a_removal_with_another_change(self):
        t = takedown()
        for label, files in {"appended version": removal_plus_new_version(),
                             "page edit": dict(t, **{P("alice", "cooltool", "page"): ({"description": "a"}, {"description": "b"})}),
                             "new entry": dict(t, **first_publish("zed", "thing", owner=own(OTHER_ID, "zed")))}.items():
            with self.subTest(change=label):
                self.assertR11Mixed(run(R11, files, r11_identity=R11, namespace_owners={"alice": ALICE}), label)

    def test_r11_reject_mixed_pr_when_r11_is_unconfigured(self):
        self.assertR11Mixed(run(ALICE, removal_plus_new_version(), r11_identity=None, namespace_owners={"alice": ALICE}))

    def test_r11_reject_two_entries_one_removal_one_unrelated_edit(self):
        files = dict(takedown("alice", "cooltool"), **add_version("alice", "other"))
        for author in (ALICE, R11):
            with self.subTest(author=author):
                self.assertR11Mixed(run(author, files, r11_identity=R11, namespace_owners={"alice": ALICE}))

    def test_r11_reject_page_change_plus_a_removal_from_the_owner(self):
        files = dict(takedown(), **{P("alice", "cooltool", "page"): ({"description": "a"}, {"description": "b"})})
        self.assertR11Mixed(run(ALICE, files, r11_identity=R11, namespace_owners={"alice": ALICE}))

    def test_r11_reject_t2_element_plus_a_malformed_second_element(self):
        old = ent("alice", "cooltool", published("1.0.0", "a" * 40), published("1.1.0", "b" * 40))
        new = ent("alice", "cooltool", removed("1.0.0", "a" * 40), "garbage")
        for author in (ALICE, R11):
            with self.subTest(author=author):
                self.assertR11Mixed(run(author, {P("alice", "cooltool"): (old, new)}, r11_identity=R11,
                                        namespace_owners={"alice": ALICE}))

    def test_r11_reject_checker_error_on_an_entry_fails_closed_naming_the_path(self):
        old = ent("alice", "cooltool", "garbage")  # the merge-base entry is not well formed: check_entry raises
        new = ent("alice", "cooltool", published(), pending("2.0.0", "c" * 40))
        v = run(ALICE, {P("alice", "cooltool"): (old, new)}, r11_identity=R11, namespace_owners={"alice": ALICE})
        self.assertEqual(v["verdict"], "rejected")
        self.assertTrue([f for f in v["findings"] if "R11" in f["rules"] and P("alice", "cooltool") in f["message"]],
                        v["findings"])

    def test_r11_reject_unreadable_only_message_does_not_claim_a_takedown(self):
        old = ent("alice", "cooltool", "garbage")  # check_entry raises; no removal is known to exist
        new = ent("alice", "cooltool", published(), pending("2.0.0", "c" * 40))
        v = run(ALICE, {P("alice", "cooltool"): (old, new)}, r11_identity=R11, namespace_owners={"alice": ALICE})
        msgs = [f["message"] for f in v["findings"] if "R11" in f["rules"]]
        self.assertTrue(msgs, v["findings"])
        for m in msgs:
            self.assertNotIn("contains a takedown mutation", m)
            self.assertIn("could not be evaluated", m)
            self.assertIn(P("alice", "cooltool"), m)
            self.assertIn("ADR-0121", m)
            self.assertNotIn("split the PR", m)

    def test_r11_reject_removal_in_a_reserved_namespace_bundled_with_another_change(self):
        files = dict(takedown("mc", "core", owner=ORG), **add_version())
        self.assertR11Mixed(run(R11, files, r11_identity=R11, namespace_owners={"alice": ALICE, "mc": ("github", ORG_ID)}))
        files = removal_plus_new_version("mc", "core", owner=ORG)
        self.assertR11Mixed(run(ORG_MEMBER, files, r11_identity=R11, oracle=status(204),
                                namespace_owners={"mc": ("github", ORG_ID)}))

    def test_r11_accept_unchanged_neighbours_of_the_mixed_rule(self):
        """Only the presence of a removal changes the verdict: an owner's plain new version is still accepted, the
        platform's removal-only PR is still authorised, and an owner's removal-only PR is still rejected."""
        self.assertEqual(run(ALICE, add_version(), r11_identity=R11, namespace_owners={"alice": ALICE})["verdict"], "accepted")
        v = run(R11, takedown(n=2), r11_identity=R11, namespace_owners={"alice": ALICE})
        self.assertEqual((v["verdict"], v["authorised_takedown"]), ("accepted", True))
        v = run(ALICE, takedown(), r11_identity=R11, namespace_owners={"alice": ALICE})
        self.assertEqual((v["verdict"], v["authorised_takedown"]), ("rejected", False))
        self.assertNotIn("split", " ".join(f["message"] for f in v["findings"]).lower())


def t1(ns="alice", signature=True):
    new = published("1.0.0", "a" * 40)
    if not signature:
        del new["signature"]
    return {P(ns, "cooltool"): (ent(ns, "cooltool", pending("1.0.0", "a" * 40)), ent(ns, "cooltool", new))}


def t3(ns="alice"):
    return {P(ns, "cooltool"): (ent(ns, "cooltool", pending("1.0.0", "a" * 40)),
                                ent(ns, "cooltool", rejected("1.0.0", "a" * 40)))}


def two(ns, a, b):
    """old [pending 1.0.0, pending/published 1.1.0] -> new with element 0 as `a` and element 1 as `b`."""
    return {P(ns, "cooltool"): (ent(ns, "cooltool", pending("1.0.0", "a" * 40), pending("1.1.0", "b" * 40)),
                                ent(ns, "cooltool", a, b))}


def t2_plus(ns, second_old, second_new):
    return {P(ns, "cooltool"): (ent(ns, "cooltool", published("1.0.0", "a" * 40), second_old),
                                ent(ns, "cooltool", removed("1.0.0", "a" * 40), second_new))}


KINDS = {
    "T1": lambda ns: t1(ns),
    "T3": lambda ns: t3(ns),
    "T1+T3": lambda ns: two(ns, published("1.0.0", "a" * 40), rejected("1.1.0", "b" * 40)),
    "malformed pending->published": lambda ns: t1(ns, signature=False),
    "T2+T1": lambda ns: t2_plus(ns, pending("1.1.0", "b" * 40), published("1.1.0", "b" * 40)),
    "T2+T3": lambda ns: t2_plus(ns, pending("1.1.0", "b" * 40), rejected("1.1.0", "b" * 40)),
}
AUTHORS = {  # label: (author, namespace, kwargs)
    "namespace owner": (ALICE, "alice", {}),
    "stranger": (MALLORY, "alice", {}),
    "org member on a reserved namespace": (ORG_MEMBER, "mc", {"oracle": status(204)}),
    "pipeline identity, R12 not configured": (("github", PIPE_ID), "alice", {}),
    "r11 identity": (R11, "alice", {"r11_identity": R11}),
}


def failclosed_findings(v):
    return [f for f in v["findings"] if f["rules"] == ["fail-closed"]]


def r12_findings(v):
    return [f for f in v["findings"] if f["rules"] == ["R12"]]


class FailClosed(unittest.TestCase):
    def test_b1_matrix_every_cell_rejected_with_the_adr_0121_message(self):
        cells = 0
        for kind, build in KINDS.items():
            for label, (author, ns, kw) in AUTHORS.items():
                with self.subTest(kind=kind, author=label):
                    v = run(author, build(ns), login="x", **kw)
                    self.assertEqual(v["verdict"], "rejected")
                    fc = r12_findings(v)
                    self.assertTrue(fc, "no R12 finding")
                    self.assertFalse(failclosed_findings(v), "a leftover fail-closed tag on a T1/T3 cell")
                    self.assertIn("ADR-0121", fc[0]["message"])
                    self.assertIn("R12", fc[0]["message"])
                    cells += 1
        self.assertEqual(cells, 30)

    def test_b1_r11_identity_has_no_write_back_power_even_when_a_pipeline_identity_is_configured(self):
        """Task 120: replaces the 008b-3a app-id case: the platform's own identity cannot carry T1 or T3."""
        for build in (t1, t3):
            v = run(R11, build(), r11_identity=R11, pipeline_identity=PIPE)
            self.assertEqual(v["verdict"], "rejected")
            self.assertTrue(r12_findings(v))

    def test_b6_truncation_trips_fail_closed_for_every_author(self):
        old = ent("alice", "cooltool", published("1.0.0", "a" * 40), published("1.1.0", "b" * 40))
        new = ent("alice", "cooltool", published("1.0.0", "a" * 40))
        for label, (author, ns, kw) in AUTHORS.items():
            with self.subTest(author=label):
                if ns == "mc":
                    old, new = ent("mc", "cooltool", old["versions"][0], old["versions"][1]), ent("mc", "cooltool", new["versions"][0])
                v = run(author, {P(ns, "cooltool"): (old, new)}, **kw)
                fc = failclosed_findings(v)
                self.assertTrue(fc)
                self.assertIn("truncated", fc[0]["message"])

    def test_b1_deleting_the_file_is_truncation_too(self):
        old = ent("alice", "cooltool", published())
        self.assertTrue(failclosed_findings(run(ALICE, {P("alice", "cooltool"): (old, None)})))

    def test_fail_closed_says_not_permitted_at_all_for_plain_rule_1_violations(self):
        for old_v, new_v in ((published(), published("1.0.0", "d" * 40)), (removed(), published())):
            with self.subTest(old=old_v["status"]):
                v = run(ALICE, {P("alice", "cooltool"): (ent("alice", "cooltool", old_v), ent("alice", "cooltool", new_v))})
                self.assertIn("not permitted at all", failclosed_findings(v)[0]["message"])

    def test_fail_closed_key_is_independent_of_the_shape_verdict(self):
        """A malformed pending -> published (007a calls it a violation) must still trip it."""
        v = run(ALICE, t1(signature=False))
        self.assertTrue(r12_findings(v))
        self.assertFalse(failclosed_findings(v))
        self.assertEqual(support.append_only.check_pr(
            {P("alice", "cooltool"): (ent("alice", "cooltool", pending("1.0.0", "a" * 40)),
                                      t1(signature=False)[P("alice", "cooltool")][1])})["authority_required"], [])

    def test_fail_closed_does_not_fire_for_appends_and_first_publishes(self):
        for files, kw in ((add_version(), {}), (first_publish(), {"login": "alice"})):
            self.assertFalse(failclosed_findings(run(ALICE, files, **kw)))

    def test_fail_closed_reports_other_rule_failures_too(self):
        v = run(MALLORY, t1())
        self.assertEqual(sorted(rules(v)), ["R12", "R3"])


class Recorder:
    """A membership oracle that records every call and then raises, so a test can assert it was never consulted."""

    def __init__(self):
        self.calls = []

    def __call__(self, org, author):
        self.calls.append((org, author))
        raise AssertionError("the membership oracle was consulted")


def wb(ns="alice", name="cooltool", kind="T1", **kw):
    """One entry whose only change is element 0: pending -> published (T1) or pending -> rejected (T3)."""
    new = published("1.0.0", "a" * 40) if kind == "T1" else rejected("1.0.0", "a" * 40)
    return {P(ns, name): (ent(ns, name, pending("1.0.0", "a" * 40), **kw), ent(ns, name, new, **kw))}


def run12(author, files, **kw):
    kw.setdefault("pipeline_identity", PIPE)
    return run(author, files, **kw)


def only_path(files):
    (path, pair), = files.items()
    return path, pair


class R12Accept(unittest.TestCase):
    def test_r12_accept_exactly_one_t1_or_one_t3_by_the_pipeline_identity_on_an_ordinary_namespace(self):
        for kind in ("T1", "T3"):
            with self.subTest(kind=kind):
                v = run12(PIPE, wb(kind=kind), login="worldofmodcraft-pipeline[bot]")
                self.assertEqual((v["verdict"], v["authorised_writeback"], v["authorised_takedown"]), ("accepted", True, False))
                self.assertEqual(v["findings"], [])

    def test_r12_accept_on_the_reserved_namespace_test_without_consulting_r7_or_r9(self):
        for kind in ("T1", "T3"):
            with self.subTest(kind=kind):
                oracle = Recorder()
                v = run12(PIPE, wb("test", "hello-world", kind), oracle=oracle)
                self.assertEqual(v["verdict"], "accepted", v["findings"])
                self.assertEqual(oracle.calls, [], "R7/R9 must not be consulted for an authorised write-back")

    def test_r12_accept_a_byte_different_but_parsed_equal_entry(self):
        path, (old, new) = only_path(wb())
        reordered = {k: new[k] for k in reversed(list(new))}
        reordered["versions"] = [{k: e[k] for k in reversed(list(e))} for e in new["versions"]]
        self.assertNotEqual(list(reordered), list(new))
        self.assertEqual(run12(PIPE, {path: (old, reordered)})["verdict"], "accepted")

    def test_r12_accept_leaves_the_owner_positive_control_and_the_hostile_fixtures_as_they_were(self):
        self.assertEqual(run12(ALICE, add_version())["verdict"], "accepted")  # an owner's new version still accepts
        self.assertEqual(rules(run12(MALLORY, add_version())), ["R3"])
        self.assertEqual(rules(run12(MALLORY, add_version(), login="alice")), ["R3"])  # the 007 hostile login pattern


class R12Reject(unittest.TestCase):
    def assertR12(self, v, *also):
        self.assertEqual(v["verdict"], "rejected")
        self.assertIn("R12", rules(v))
        self.assertFalse(failclosed_findings(v), "a leftover fail-closed tag")
        self.assertFalse(v["authorised_writeback"])
        for r in also:
            self.assertIn(r, rules(v))

    def test_r12_reject_the_same_diffs_by_a_different_id(self):
        for kind in ("T1", "T3"):
            for label, author, ns in (("owner", ALICE, "alice"), ("stranger", MALLORY, "alice"), ("r11", R11, "alice"),
                                      ("org member", ORG_MEMBER, "mc")):
                with self.subTest(kind=kind, author=label):
                    self.assertR12(run12(author, wb(ns, kind=kind), oracle=status(204), r11_identity=R11))

    def test_r12_reject_a_login_that_matches_the_bot_when_the_id_differs(self):
        v = run12(("github", PIPE_ID + 1), wb(), login="worldofmodcraft-pipeline[bot]")
        self.assertR12(v, "R3")

    def test_r12_reject_when_the_identity_is_not_configured(self):
        for kind in ("T1", "T3"):
            with self.subTest(kind=kind):
                v = run(PIPE, wb(kind=kind), pipeline_identity=None)
                self.assertR12(v)
                self.assertIn("authorises nobody", r12_findings(v)[0]["message"])

    def test_r12_reject_a_t1_plus_a_new_version_a_page_edit_or_an_extra_top_level_key(self):
        path, (old, new) = only_path(wb())
        plus_version = dict(new, versions=new["versions"] + [pending("1.1.0", "b" * 40)])
        plus_key = dict(new, extra="x")
        plus_page = {path: (old, new), P("alice", "cooltool", "page"): ({"a": 1}, {"a": 2})}
        for label, files in (("new version", {path: (old, plus_version)}), ("extra top-level key", {path: (old, plus_key)}),
                             ("page.json edit", plus_page)):
            with self.subTest(change=label):
                self.assertR12(run12(PIPE, files))

    def test_r12_reject_two_t1s_a_t1_and_a_t3_and_two_entries_each_with_a_t1(self):
        two_t1 = two("alice", published("1.0.0", "a" * 40), published("1.1.0", "b" * 40))
        t1_t3 = two("alice", published("1.0.0", "a" * 40), rejected("1.1.0", "b" * 40))
        two_files = dict(wb(name="one"), **wb(name="two"))
        for label, files in (("two T1", two_t1), ("T1 and T3", t1_t3), ("two entries", two_files)):
            with self.subTest(case=label):
                self.assertR12(run12(PIPE, files))

    def test_r12_reject_a_t1_and_a_takedown_by_r11_as_well(self):
        files = t2_plus("alice", pending("1.1.0", "b" * 40), published("1.1.0", "b" * 40))
        self.assertR12(run12(PIPE, files), "R11")
        self.assertR12(run12(R11, files, r11_identity=R11, pipeline_identity=PIPE), "R11")

    def test_r12_reject_a_t3_with_a_blank_reason_or_a_non_https_build_log_url(self):
        for label, new in (("blank reason", rejected("1.0.0", "a" * 40, reason="   ")),
                           ("http url", rejected("1.0.0", "a" * 40, url="http://builds.example.org/log.txt"))):
            with self.subTest(case=label):
                self.assertR12(run12(PIPE, {P("alice", "cooltool"): (ent("alice", "cooltool", pending("1.0.0", "a" * 40)),
                                                                     ent("alice", "cooltool", new))}))

    def test_r12_reject_a_t1_plus_any_change_to_another_file(self):
        base = wb()
        for other in ("config/r11-identity.json", "contracts/ownership.md", ".github/workflows/x.yml",
                      "reserved-namespaces.json", P("alice", "other"), P("alice", "other", "page")):
            with self.subTest(other=other):
                self.assertR12(run12(PIPE, dict(base, **{other: ({"a": 1}, {"a": 2})})))

    def test_r12_reject_a_newly_added_element_born_published_or_rejected_even_by_the_owner(self):
        """057 attack 1: an author appends an element that is already published (or rejected)."""
        for label, born in (("published", published("1.1.0", "b" * 40)), ("rejected", rejected("1.1.0", "b" * 40))):
            files = {P("alice", "cooltool"): (ent("alice", "cooltool", published()), ent("alice", "cooltool", published(), born))}
            first = {P("alice", "cooltool"): (None, ent("alice", "cooltool", born))}
            for who, author, f in (("owner", ALICE, files), ("pipeline", PIPE, files), ("owner first publish", ALICE, first)):
                with self.subTest(born=label, author=who):
                    self.assertR12(run12(author, f, login="alice"))

    def test_r12_reject_a_created_or_deleted_entry_json_holding_a_published_or_rejected_element(self):
        """Contract 116282e: a created file holding such an element, or a deleted file that held one, is a T1/T3 mutation."""
        for label, el in (("published", published()), ("rejected", rejected())):
            created = {P("alice", "tool"): (None, ent("alice", "tool", el))}
            deleted = {P("alice", "tool"): (ent("alice", "tool", el), None)}
            for what, files in (("created", created), ("deleted", deleted)):
                for who, author in (("pipeline", PIPE), ("owner", ALICE)):
                    with self.subTest(element=label, file=what, author=who):
                        v = run12(author, files, login="alice")
                        self.assertEqual(v["verdict"], "rejected")
                        self.assertIn("R12", rules(v))
                        self.assertFalse(v["authorised_writeback"])
        control = {P("alice", "tool"): (ent("alice", "tool", pending()), None)}
        self.assertNotIn("R12", rules(run12(ALICE, control)))  # a deleted file holding only pending is not R12's (007a rejects it)

    def test_r12_reject_a_t1_plus_a_path_in_any_status_added_deleted_renamed_or_mode_only(self):
        """Contract 116282e: 'touches no other path' counts every path in the diff, whatever its status."""
        base = wb()
        other = P("alice", "other", "page")
        doc = {"a": 1}
        for label, extra in (("added", {other: (None, doc)}), ("deleted", {other: (doc, None)}),
                             ("mode change only (old == new)", {other: (doc, doc)}),
                             ("renamed (a deletion plus an addition)", {other: (doc, None), P("alice", "moved", "page"): (None, doc)})):
            with self.subTest(status=label):
                self.assertR12(run12(PIPE, dict(base, **extra)))
        self.assertEqual(run12(PIPE, base)["verdict"], "accepted")  # positive control: the same T1 alone

    def test_r12_reject_a_t1_that_is_not_classified_as_one_by_the_append_only_rules(self):
        self.assertR12(run12(PIPE, t1(signature=False)))
        path, (old, new) = only_path(wb())
        extra_key = dict(new, versions=[dict(new["versions"][0], reason="x")])
        self.assertR12(run12(PIPE, {path: (old, extra_key)}))

    def test_r12_reject_a_t1_that_also_changes_id_owner_or_another_element(self):
        path, (old, new) = only_path(wb())
        two_el_old = ent("alice", "cooltool", pending("1.0.0", "a" * 40), pending("1.1.0", "b" * 40))
        two_el_new = ent("alice", "cooltool", published("1.0.0", "a" * 40), pending("1.1.0", "c" * 40))
        for label, n in (("owner", dict(new, owner=own(MALLORY_ID, "mallory"))), ("id", dict(new, id="alice:other"))):
            with self.subTest(change=label):
                self.assertR12(run12(PIPE, {path: (old, n)}))
        with self.subTest(change="another element"):
            self.assertR12(run12(PIPE, {path: (two_el_old, two_el_new)}))

    def test_r12_reject_the_pipeline_identity_changing_an_already_published_element(self):
        """Not a T1, so R12 has nothing to say: the ordinary rules and the fail-closed rule reject it."""
        old = ent("alice", "cooltool", published())
        new = ent("alice", "cooltool", published("1.0.0", "d" * 40))
        v = run12(PIPE, {P("alice", "cooltool"): (old, new)})
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(sorted(rules(v)), ["R3", "fail-closed"])
        both = {P("alice", "cooltool"): (ent("alice", "cooltool", pending("1.0.0", "a" * 40), published("1.1.0", "b" * 40)),
                                         ent("alice", "cooltool", published("1.0.0", "a" * 40), published("1.1.0", "d" * 40)))}
        self.assertR12(run12(PIPE, both))

    def test_r12_reject_still_applies_r3_and_r7_to_an_unauthorised_pr(self):
        self.assertEqual(sorted(rules(run12(MALLORY, wb()))), ["R12", "R3"])
        self.assertEqual(sorted(rules(run12(ORG_MEMBER, wb("mc", name="core"), oracle=status(404)))), ["R12", "R7"])

    def test_r12_reject_r2_and_r10_still_apply_to_an_authorised_write_back(self):
        bad_id = wb(id="bob:cooltool")
        v = run12(PIPE, bad_id)
        self.assertEqual((v["verdict"], set(rules(v)), v["authorised_writeback"]), ("rejected", {"R2"}, True))
        orphan = dict(wb(), **{P("alice", "orphan", "page"): (None, {"a": 1})})
        v = run12(PIPE, orphan)
        self.assertIn("R10", rules(v))
        self.assertIn("R12", rules(v))
        v = run12(PIPE, {P("alice", "orphan", "page"): (None, {"a": 1})})
        self.assertIn("R10", rules(v))

    def test_r12_reject_is_in_the_cli_for_an_entry_that_does_not_parse_or_repeats_a_key(self):
        import json
        import tempfile
        from pathlib import Path
        import ownership_cli
        for label, bad in (("syntax", "{not json"), ("duplicate key", '{"id": "a", "id": "b"}')):
            with self.subTest(case=label), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                for side in ("old", "new"):
                    for name in ("cooltool", "broken"):
                        (root / side / f"mods/alice.{name}").mkdir(parents=True)
                (root / "res.json").write_text(json.dumps(RES))
                path, (old, new) = only_path(wb())
                (root / "old" / path).write_text(json.dumps(old))
                (root / "new" / path).write_text(json.dumps(new))
                (root / "old/mods/alice.broken/entry.json").write_text(json.dumps(ent("alice", "broken", pending())))
                (root / "new/mods/alice.broken/entry.json").write_text(bad)
                out = io.StringIO()
                args = ["--author-provider", "github", "--author-id", str(PIPE_ID), "--old-root", str(root / "old"),
                        "--new-root", str(root / "new"), "--reserved-file", str(root / "res.json"),
                        "--pipeline-identity", f"github:{PIPE_ID}", path, "mods/alice.broken/entry.json"]
                with redirect_stdout(out), redirect_stderr(io.StringIO()):
                    code = report.run(ownership_cli.main, args)
                self.assertEqual(code, 1)
                v = json.loads(out.getvalue())
                self.assertIn("R12", [r for f in v["findings"] for r in f["rules"]])
                self.assertTrue(all(f["path"] == "mods/alice.broken/entry.json" for f in v["findings"]))


class R12Cli(unittest.TestCase):
    def cli(self, files_old, files_new, extra, author=PIPE_ID):
        import json
        import tempfile
        from pathlib import Path
        import ownership_cli
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "res.json").write_text(json.dumps(RES))
            for side, files in (("old", files_old), ("new", files_new)):
                for path, doc in files.items():
                    (root / side / path).parent.mkdir(parents=True, exist_ok=True)
                    (root / side / path).write_text(json.dumps(doc))
            (root / "old/mods").mkdir(parents=True, exist_ok=True)
            (root / "new/mods").mkdir(parents=True, exist_ok=True)
            args = ["--author-provider", "github", "--author-id", str(author), "--old-root", str(root / "old"),
                    "--new-root", str(root / "new"), "--reserved-file", str(root / "res.json")] + extra
            out, err = io.StringIO(), io.StringIO()
            with redirect_stdout(out), redirect_stderr(err):
                code = report.run(ownership_cli.main, args)
            return code, err.getvalue()

    def test_r12_accept_through_the_cli_with_the_flag_and_reject_without_it(self):
        path, (old, new) = only_path(wb())
        status_arg = ["--membership-status", "404"]
        with_flag = self.cli({path: old}, {path: new}, status_arg + ["--pipeline-identity", f"github:{PIPE_ID}", path])
        without = self.cli({path: old}, {path: new}, status_arg + [path])
        other = self.cli({path: old}, {path: new}, status_arg + ["--pipeline-identity", f"github:{PIPE_ID + 1}", path])
        self.assertEqual((with_flag[0], without[0], other[0]), (0, 1, 1))
        self.assertIn("R12", without[1])

    def test_i9_reject_equal_identities_exit_2_in_the_cli_whatever_the_pr(self):
        path, (old, new) = only_path(wb())
        for ident in (f"github:{R11[1]}",):
            code, err = self.cli({path: old}, {path: new}, ["--r11-identity", ident, "--pipeline-identity", ident, path])
            self.assertEqual(code, 2)
            self.assertIn("I9", err)
        for r11, pipe, want in ((f"github:{R11[1]}", f"github:{PIPE_ID}", 0), (f"github:{R11[1]}", None, 1),
                                (None, f"github:{R11[1]}", 1)):  # distinct or unconfigured: a verdict, as before
            extra = (["--r11-identity", r11] if r11 else []) + (["--pipeline-identity", pipe] if pipe else [])
            self.assertEqual(self.cli({path: old}, {path: new}, extra + ["--membership-status", "404", path])[0], want)

    def test_r12_reject_a_malformed_pipeline_identity_flag_is_exit_2(self):
        path, (old, new) = only_path(wb())
        self.assertEqual(self.cli({path: old}, {path: new}, ["--pipeline-identity", "x", path])[0], 2)


class I9Separation(unittest.TestCase):
    def test_i9_accept_either_identity_unconfigured_or_two_distinct_ones_give_a_verdict(self):
        for r11, pipe in ((None, None), (R11, None), (None, R11), (R11, PIPE)):
            with self.subTest(r11=r11, pipeline=pipe):
                v = run(ALICE, add_version(), r11_identity=r11, pipeline_identity=pipe)
                self.assertEqual(v["verdict"], "accepted")

    def test_i9_reject_equal_identities_raise_a_tool_error_for_every_pr_on_a_direct_call(self):
        for label, author, files in (("ordinary", ALICE, add_version()), ("takedown", R11, takedown()),
                                     ("write-back", R11, wb()), ("empty", ALICE, {})):
            with self.subTest(pr=label):
                with self.assertRaises(report.ToolError) as cm:
                    run(author, files, r11_identity=R11, pipeline_identity=R11)
                self.assertIn("I9", str(cm.exception))

    def test_i9_reject_the_comparison_is_on_provider_and_id(self):
        v = run(ALICE, add_version(), r11_identity=("github", 7), pipeline_identity=("gitlab", 7))
        self.assertEqual(v["verdict"], "accepted")


class Identity(unittest.TestCase):
    def test_i1_accept_identity_comes_from_the_argument_not_the_environment(self):
        with mock.patch.dict(os.environ, {"GITHUB_ACTOR_ID": str(MALLORY_ID), "GITHUB_ACTOR": "mallory"}):
            self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_i1_reject_environment_actor_cannot_stand_in_for_the_author(self):
        with mock.patch.dict(os.environ, {"GITHUB_ACTOR_ID": str(ALICE_ID), "GITHUB_ACTOR": "alice"}):
            self.assertEqual(rules(run(MALLORY, add_version())), ["R3"])

    def test_i2_accept_namespace_comes_from_the_directory(self):
        self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_i2_reject_id_cannot_move_a_file_into_another_namespace(self):
        """Dir alice.cooltool, id mallory:cooltool: judged as alice's (R3 against alice), never as mallory's."""
        old = ent("alice", "cooltool", published(), id="mallory:cooltool")
        new = ent("alice", "cooltool", published(), pending("1.1.0", "b" * 40), id="mallory:cooltool")
        v = run(MALLORY, {P("alice", "cooltool"): (old, new)}, login="mallory")
        self.assertIn("R3", rules(v))
        self.assertIn("R2", rules(v))

    def test_i3_accept_owner_read_from_old(self):
        self.assertEqual(run(ALICE, add_version())["verdict"], "accepted")

    def test_i3_reject_a_pr_that_rewrites_owner_to_itself_gains_nothing(self):
        old = ent("alice", "cooltool", published())
        new = ent("alice", "cooltool", published(), pending("1.1.0", "b" * 40), owner=own(MALLORY_ID, "mallory"))
        v = run(MALLORY, {P("alice", "cooltool"): (old, new)}, login="mallory")
        self.assertEqual(rules(v), ["R3"])

    def test_i6_accept_provider_and_id_both_match(self):
        self.assertEqual(run(("github", ALICE_ID), add_version())["verdict"], "accepted")

    def test_i6_reject_same_id_on_another_provider(self):
        v = run(("gitlab", ALICE_ID), add_version())
        self.assertEqual(rules(v), ["R3"])

    def test_i6_reject_a_login_alone_never_authorises(self):
        self.assertEqual(run(MALLORY, add_version(), login="alice")["verdict"], "rejected")

    def test_i7_accept_every_namespace_passes(self):
        files = dict(add_version("alice", "cooltool"), **add_version("alice", "second"))
        self.assertEqual(run(ALICE, files)["verdict"], "accepted")

    def test_i7_reject_one_foreign_namespace_rejects_the_whole_pr(self):
        files = dict(add_version("alice", "cooltool"), **add_version("bob", "widget", owner=own(31337, "bob")))
        v = run(ALICE, files)
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(rules(v), ["R3"])
        self.assertIn("'bob'", v["findings"][0]["message"])

    def test_i7_reject_an_unauthorised_second_namespace_after_an_authorised_first(self):
        files = dict(add_version("aaa", "x", owner=own(ALICE_ID, "aaa")), **add_version("zzz", "y", owner=own(31337, "zzz")))
        self.assertEqual(run(ALICE, files)["verdict"], "rejected")

    def test_i8_accept_a_green_verdict_is_never_a_merge_signal(self):
        v = run(ALICE, add_version())
        self.assertEqual((v["verdict"], v["merge_signal"]), ("accepted", False))

    def test_i8_reject_the_cli_help_says_accepted_is_not_a_merge_signal(self):
        import subprocess
        import sys
        out = subprocess.run([sys.executable, str(support.REPO / "tools/registry/ownership_cli.py"), "--help"],
                             capture_output=True, text=True).stdout
        self.assertIn("NEVER a merge signal", out)


class Seam(unittest.TestCase):
    """B5: nothing but the arguments is read; no network, environment or file access."""

    class NoEnv(dict):
        def _no(self, *a, **k):
            raise AssertionError("environment read")
        __getitem__ = get = __contains__ = __iter__ = keys = items = _no

    def test_b5_checker_touches_neither_socket_nor_environ_nor_open(self):
        def no_open(*a, **k):
            raise AssertionError("file opened")
        scenarios = [(ALICE, add_version(), {}), (MALLORY, add_version(), {}), (R11, takedown(), {"r11_identity": R11}),
                     (ORG_MEMBER, add_version("mc", "core"), {"oracle": status(204)}), (ALICE, t1(), {})]
        with mock.patch("socket.socket", side_effect=AssertionError("network")), \
                mock.patch.object(os, "environ", self.NoEnv()), mock.patch("builtins.open", no_open):
            for author, files, kw in scenarios:
                run(author, files, **kw)

    def test_b5_source_has_no_io_imports(self):
        import ast
        tree = ast.parse((support.REPO / "tools/registry/ownership.py").read_text())
        imported = {a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
        self.assertEqual(imported, {"append_only", "classify", "report"})
        names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)} | \
            {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
        self.assertFalse(names & {"open", "environ", "getenv", "socket", "Path", "read_text"})

    def test_b5_bad_inputs_are_tool_errors_not_rejections(self):
        for bad in (None, "alice", ("github",), ("github", "1"), ("github", True)):
            with self.subTest(author=bad):
                with self.assertRaises(report.ToolError):
                    run(bad, add_version())


class Cli(unittest.TestCase):
    def test_cli_exit_codes_and_reject_without_membership_status(self):
        import json
        import tempfile
        from pathlib import Path
        import ownership_cli
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "old/mods/mc.core").mkdir(parents=True)
            (root / "new/mods/mc.core").mkdir(parents=True)
            (root / "res.json").write_text(json.dumps(RES))
            (root / "old/mods/mc.core/entry.json").write_text(json.dumps(ent("mc", "core", published())))
            (root / "new/mods/mc.core/entry.json").write_text(json.dumps(
                ent("mc", "core", published(), pending("1.1.0", "b" * 40))))
            base = ["--author-provider", "github", "--author-id", "777000", "--old-root", str(root / "old"),
                    "--new-root", str(root / "new"), "--reserved-file", str(root / "res.json")]
            codes = {}
            for label, extra in (("member", ["--membership-status", "204"]), ("no-status", []),
                                 ("302", ["--membership-status", "302"]), ("bad-r11", ["--r11-identity", "x"])):
                with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                    codes[label] = report.run(ownership_cli.main, base + extra + ["mods/mc.core/entry.json"])
            self.assertEqual(codes, {"member": 0, "no-status": 1, "302": 1, "bad-r11": 2})

    def test_cli_builds_namespace_owners_from_the_old_root_only(self):
        import json
        import tempfile
        from pathlib import Path
        import ownership_cli
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for side in ("old", "new"):
                (root / side / "mods/alice.cooltool").mkdir(parents=True)
            (root / "new/mods/alice.new").mkdir(parents=True)
            (root / "res.json").write_text(json.dumps(RES))
            (root / "old/mods/alice.cooltool/entry.json").write_text(json.dumps(ent("alice", "cooltool", published())))
            (root / "new/mods/alice.cooltool/entry.json").write_text(json.dumps(ent("alice", "cooltool", published())))
            # the PR's own copy claims the namespace for the stranger; only the old root may count
            (root / "new/mods/alice.new/entry.json").write_text(json.dumps(
                ent("alice", "new", pending(), owner=own(MALLORY_ID, "alice"))))
            args = ["--author-provider", "github", "--author-id", str(MALLORY_ID), "--author-login", "alice",
                    "--old-root", str(root / "old"), "--new-root", str(root / "new"),
                    "--reserved-file", str(root / "res.json"), "mods/alice.new/entry.json"]
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(report.run(ownership_cli.main, args), 1)
            (root / "old/mods/alice.cooltool/entry.json").unlink()  # no merge-base owner => a genuine first publish
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(report.run(ownership_cli.main, args), 0)

    def test_cli_fails_closed_when_merge_base_entries_of_one_namespace_disagree_on_owner(self):
        import json
        import tempfile
        from pathlib import Path
        import ownership_cli
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            for name, oid in (("a", ALICE_ID), ("b", 555)):
                for side in ("old", "new"):
                    (root / side / f"mods/alice.{name}").mkdir(parents=True)
                (root / f"old/mods/alice.{name}/entry.json").write_text(
                    json.dumps(ent("alice", name, published(), owner=own(oid, "alice"))))
            (root / "new/mods/alice.c").mkdir(parents=True)
            (root / "new/mods/alice.c/entry.json").write_text(json.dumps(ent("alice", "c", pending())))
            (root / "res.json").write_text(json.dumps(RES))
            err = io.StringIO()
            args = ["--author-provider", "github", "--author-id", str(ALICE_ID), "--author-login", "alice",
                    "--old-root", str(root / "old"), "--new-root", str(root / "new"),
                    "--reserved-file", str(root / "res.json"), "mods/alice.c/entry.json"]
            with redirect_stdout(io.StringIO()), redirect_stderr(err):
                self.assertEqual(report.run(ownership_cli.main, args), 2)
            self.assertIn("alice.a", err.getvalue())
            self.assertIn("alice.b", err.getvalue())


if __name__ == "__main__":
    unittest.main()
