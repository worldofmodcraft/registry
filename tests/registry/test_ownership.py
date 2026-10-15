"""Ownership checker (task 007b, E16): ownership.md R1-R11 and I1-I8, plus the ADR-0121 fail-closed rule.

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
        self.assertEqual(rules(v), ["R3"])

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
        files = dict(first_publish("alice", "new", owner=own(MALLORY_ID, "alice")), **add_version("alice", "cooltool"))
        v = run(MALLORY, files, login="alice", namespace_owners={"alice": ALICE})
        self.assertIn("R3", rules(v))


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

    def test_r11_reject_malformed_t2_is_not_a_takedown(self):
        old, new = takedown()[P("alice", "cooltool")]
        del new["versions"][0]["reason"]
        v = run(R11, {P("alice", "cooltool"): (old, new)}, r11_identity=R11)
        self.assertFalse(v["authorised_takedown"])
        self.assertEqual(rules(v), ["R3"])

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

    def test_r11_pipeline_app_id_equal_to_r11_identity_behaves_as_r11_for_t2(self):
        v = run(R11, takedown(), r11_identity=R11, pipeline_app_id=R11[1])
        self.assertEqual(v["verdict"], "accepted")


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
    "pipeline app id": (("github", PIPE_ID), "alice", {"pipeline_app_id": PIPE_ID}),
    "r11 identity": (R11, "alice", {"r11_identity": R11}),
}


def failclosed_findings(v):
    return [f for f in v["findings"] if f["rules"] == ["fail-closed"]]


class FailClosed(unittest.TestCase):
    def test_b1_matrix_every_cell_rejected_with_the_adr_0121_message(self):
        cells = 0
        for kind, build in KINDS.items():
            for label, (author, ns, kw) in AUTHORS.items():
                with self.subTest(kind=kind, author=label):
                    v = run(author, build(ns), login="x", **kw)
                    self.assertEqual(v["verdict"], "rejected")
                    fc = failclosed_findings(v)
                    self.assertTrue(fc, "no fail-closed finding")
                    self.assertIn("ADR-0121", fc[0]["message"])
                    self.assertIn("task 008b", fc[0]["message"])
                    cells += 1
        self.assertEqual(cells, 30)

    def test_b1_pipeline_app_id_equal_to_r11_identity_still_cannot_carry_t1_or_t3(self):
        for build in (t1, t3):
            v = run(R11, build(), r11_identity=R11, pipeline_app_id=R11[1])
            self.assertEqual(v["verdict"], "rejected")
            self.assertTrue(failclosed_findings(v))

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
        self.assertTrue(failclosed_findings(v))
        self.assertEqual(support.append_only.check_pr(
            {P("alice", "cooltool"): (ent("alice", "cooltool", pending("1.0.0", "a" * 40)),
                                      t1(signature=False)[P("alice", "cooltool")][1])})["authority_required"], [])

    def test_fail_closed_does_not_fire_for_appends_and_first_publishes(self):
        for files, kw in ((add_version(), {}), (first_publish(), {"login": "alice"})):
            self.assertFalse(failclosed_findings(run(ALICE, files, **kw)))

    def test_fail_closed_reports_other_rule_failures_too(self):
        v = run(MALLORY, t1())
        self.assertEqual(sorted(rules(v)), ["R3", "fail-closed"])


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


if __name__ == "__main__":
    unittest.main()
