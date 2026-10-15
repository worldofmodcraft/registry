#!/usr/bin/env python3
"""Mutation table and runner for the ownership checker (task 007b, MANAGER.md 2c rule 2, B3/B4).

    python3 tests/registry/test_ownership_mutations.py [--list] [--discover] [id ...]

A mutation breaks one thing in a scratch CLONE of the committed tree (tools/registry/ownership.py); `red` lists
substrings that must each appear in a FAIL/ERROR line of test_ownership.py run against the mutant. A mutation
whose run is green, or that leaves a named test green, is NOT RED. Exit code = number of NOT RED mutations.

Under `unittest discover` this file contributes only the coverage tests at the bottom (B3): every rule id found
in contracts/ownership.md's `**Rn (MUST` / `**In (MUST` markers has accepting and rejecting tests, and a
mutation whose `red` list names a test of that rule. A tag without a reddening mutation does not count.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
OW = "tools/registry/ownership.py"
M = []
DESCRIPTIVE = {"I8"}  # merge authority: constrains the process around the checker, not its decisions


def mut(mid, edits, red):
    M.append((mid, edits, red))


A = 'authorised = r11 is not None and author == r11 and shape'
SHAPE_GATE = '''        if v["findings"] or "T2" not in kinds or any(k not in ("unchanged", "T2") for k in kinds):'''
PATHGATE = '''        if p is None or p[2] != "entry" or old is None or new is None:
            return False'''
R3GATE = 'if not ctx["authorised"] and _owner_pair(existing) != author:'
FC = 'findings = _fail_closed(files) + classify.classify(sorted(files), reserved_base)["findings"]'

# ---- B4 required mutations -----------------------------------------------------------------------------------
mut("b4-owner-from-new-i3", [('            if old is not None:\n                existing = old\n',
                              '            if old is not None:\n                existing = new if new is not None else old\n')],
    ["test_i3_reject_a_pr_that_rewrites_owner", "test_r3_reject_rebinding"])
mut("b4-ignore-provider-i6", [(R3GATE, 'if not ctx["authorised"] and (_owner_pair(existing) or (0, 0))[1] != author[1]:')],
    ["test_i6_reject_same_id_on_another_provider"])
mut("b4-reserved-list-from-new-i4", [('names = classify.reserved_names(reserved_base)',
                                      'names = classify.reserved_names(files.get("reserved-namespaces.json", (None, reserved_base))[1])')],
    ["test_i4_reject_a_pr_cannot_strip"])
mut("b4-compare-logins-not-ids", [(R3GATE, 'if not ctx["authorised"] and (login or "").lower() != str(_d(_d(existing).get("owner")).get("name_at_registration")).lower():')],
    ["test_r3_reject_same_username_different_id", "test_r3_accept_rename_same_id_different_username"])
mut("b4-302-is-member-r9-i5", [('    if status == 204:', '    if status in (204, 302):')],
    ["test_i5_reject_a_302", "test_r9_reject_everything_else"])
mut("b4-302-is-not-member-r9-i5", [('    if status == 404:', '    if status in (404, 302):')],
    ["test_i5_reject_a_302", "test_r9_reject_everything_else"])
mut("b4-oracle-exception-is-member-r9", [('        return [_r9(ns, f"the membership oracle raised {type(exc).__name__}: {exc}")]', '        return []')],
    ["test_r9_reject_oracle_exception"])
mut("b4-page-only-without-entry-accepted-r10", [('if kind == "page" and existing is None and first is None:', 'if False:')],
    ["test_r10_reject_page_only_pr_with_no_entry", "test_r10_reject_page_whose_sibling"])
mut("b4-namespaces-evaluated-jointly-i7", [('    for ns in sorted(by_ns):\n        findings += _namespace',
                                            '    for ns in sorted(by_ns)[:1]:\n        findings += _namespace')],
    ["test_i7_reject_an_unauthorised_second_namespace"])
mut("b4-skip-fail-closed", [(FC, 'findings = classify.classify(sorted(files), reserved_base)["findings"]')],
    ["test_b1_matrix_every_cell", "test_b6_truncation", "test_b1_deleting_the_file"])
mut("b4-fail-closed-keyed-on-007a-classification", [(
    'elif not append_only._same(o, nv[i]) and (_status(o) == "pending" or _status(nv[i]) in ("published", "rejected")):',
    'elif not append_only._same(o, nv[i]) and append_only.check_entry(old, new)["elements"][i]["classification"] in ("T1", "T3"):')],
    ["test_b1_matrix_every_cell", "test_fail_closed_key_is_independent"])
mut("b4-pipeline-app-id-bypasses-fail-closed", [(FC, 'findings = (_fail_closed(files) if author[1] != pipeline_app_id else []) + classify.classify(sorted(files), reserved_base)["findings"]')],
    ["test_b1_matrix_every_cell"])
mut("b4-any-author-may-use-r11", [(A, 'authorised = shape')],
    ["test_r11_reject_everyone_else", "test_r11_reject_when_unconfigured"])
mut("b4-r11-admits-non-takedown-changes", [(SHAPE_GATE, '        if "T2" not in kinds:')],
    ["test_r11_reject_a_takedown_plus_any_other_change"])
mut("b4-r11-admits-page-edit", [(PATHGATE, '        if p is None or old is None or new is None:\n            return False\n        if p[2] == "page":\n            continue')],
    ["test_r11_reject_a_takedown_plus_any_other_change"])
mut("b4-r11-precedence-shape-based-attempt-9", [
    ('"authorised": authorised,', '"authorised": authorised, "shape": shape,'),
    (R3GATE, 'if not ctx["shape"] and _owner_pair(existing) != author:'),
    ('    if reserved and not ctx["authorised"]:', '    if reserved and not ctx["shape"]:')],
    ["test_r11_precedence_is_authority_based", "test_r11_reject_owner_stranger_and_member"])
mut("b4-binding-pr-rebinds-existing-namespace", [(
    '            if old is not None:\n                existing = old\n            elif new is not None:\n                first = new\n',
    '            if new is not None and _owner_pair(new) == author:\n                first = new\n            elif old is not None:\n                existing = old\n')],
    ["test_r3_reject_rebinding"])
mut("b4-reject-everything-positive-control", [(
    '    return report.make("ownership", findings,', '    findings.append(report.finding(["x"], "w", "f", "c"))\n    return report.make("ownership", findings,')],
    ["test_r3_accept_owner_adds_a_version", "test_r7_accept_org_member", "test_r10_accept_page_of", "test_r11_accept_one_and_two"])

# ---- B6 --------------------------------------------------------------------------------------------------
mut("b6-truncation-ignored", [('            if i >= len(nv):\n', '            if i >= len(nv):\n                continue\n            if False:\n')],
    ["test_b6_truncation", "test_b1_deleting_the_file"])
mut("b6-malformed-t2-authorised", [
    ('        kinds = [e["classification"] for e in v["elements"]]',
     '        kinds = ["T2" if e["classification"] in ("T2", "violation") else e["classification"] for e in v["elements"]]'),
    ('        if v["findings"] or "T2"', '        if "T2"')],
    ["test_r11_reject_malformed_t2"])
mut("b6-reserved-list-edit-beside-t2-authorised", [(PATHGATE, PATHGATE.replace("return False", "continue"))],
    ["test_r11_reject_reserved_list_edit_beside_a_t2"])
mut("b6-r11-identity-read-from-reserved-list", [(
    'r11 = None if r11_identity is None else _pair(r11_identity, "r11_identity")',
    'r11 = _owner_pair({"owner": reserved_base["namespaces"]["mc"]["owner"]})')],
    ["test_r11_authority_is_configuration", "test_r11_accept_one_and_two"])

# ---- one or more per rule (B3) -----------------------------------------------------------------------------
mut("r1-path-form-not-enforced", [('+ classify.classify(sorted(files), reserved_base)["findings"]', '+ []')],
    ["test_r1_reject_malformed"])
mut("r2-id-vs-directory-not-checked", [('if src is not None and _d(src).get("id") != f"{ns}:{name}":', 'if False:')],
    ["test_r2_reject_new_id", "test_r2_reject_old_id"])
mut("r3-owner-not-checked", [(R3GATE, 'if False:')], ["test_r3_reject_stranger", "test_r3_reject_same_username"])
mut("r4-not-checked", [('if login is None or ns.lower() != login.lower():', 'if False:')],
    ["test_r4_reject_namespace_of_someone_elses_name", "test_r4_reject_without_a_login"])
mut("r4-case-sensitive", [('if login is None or ns.lower() != login.lower():', 'if login is None or ns != login:')],
    ["test_r4_accept_namespace_equals_username_case_folded"])
mut("r5-not-checked", [('if _owner_pair(first) != author:', 'if False:')], ["test_r5_reject_owner_claims"])
mut("r6-not-checked", [('if login is None or str(own.get("name_at_registration")).lower() != login.lower():', 'if False:')],
    ["test_r6_reject_name_at_registration"])
mut("r7-membership-not-checked", [('    if reserved and not ctx["authorised"]:', '    if False:')],
    ["test_r7_reject_non_member", "test_r9_reject_everything_else"])
mut("r7-404-reported-as-indeterminate", [('    if status == 404:', '    if status == 999:')], ["test_r7_reject_non_member"])
mut("r8-recorded-owner-not-checked", [('if not append_only._same(_d(first).get("owner"), rec):', 'if False:')],
    ["test_r8_reject_first_publish_owned_by_the_author"])
mut("r8-does-not-take-precedence", [('        elif first is not None and reserved:', '        elif first is not None and reserved and False:')],
    ["test_r8_precedence_over_r4_r5_r6", "test_r8_accept_first_publish"])
mut("r9-other-statuses-accepted", [(
    '    return [_r9(ns, f"the membership question answered HTTP {status}, neither 204 (member) nor 404 (not a member)")]', '    return []')],
    ["test_r9_reject_everything_else"])
mut("r9-non-integer-answer-accepted", [(
    '    if isinstance(status, bool) or not isinstance(status, int):\n        return [_r9(ns, f"the membership oracle returned {status!r}, not an HTTP status")]\n',
    '    if status is True:\n        return []\n')],
    ["test_r9_reject_oracle_exception_and_non_integer"])
mut("r10-unconfigured-sibling-absent-on-both-sides-ignored", [(
    '            if eo is None and en is None:\n                existing = None\n            else:\n                continue',
    '            continue')],
    ["test_r10_reject_page_whose_sibling"])
mut("r11-unconfigured-authorises-the-reserved-owner", [(A, 'authorised = shape and (r11 is None or author == r11)')],
    ["test_r11_reject_when_unconfigured"])
mut("r11-finding-dropped", [('    if shape and not authorised:', '    if False:')],
    ["test_r11_reject_everyone_else", "test_r11_reject_when_unconfigured"])

# ---- invariants ------------------------------------------------------------------------------------------
mut("i1-identity-read-from-environment", [
    ('import append_only\n', 'import os\nimport append_only\n'),
    ('    author = _pair(author, "author")', '    author = _pair((author[0], int(os.environ.get("GITHUB_ACTOR_ID", author[1]))), "author")')],
    ["test_i1_accept_identity", "test_i1_reject_environment_actor"])
mut("i2-namespace-from-id-not-directory", [(
    '            by_ns.setdefault(p[0], []).append(path)',
    '            by_ns.setdefault(str(files[path][1].get("id", p[0] + ":") if isinstance(files[path][1], dict) else p[0]).split(":")[0], []).append(path)')],
    ["test_i2_reject_id_cannot_move"])
mut("i3-owner-from-new", [('                existing = old\n', '                existing = new\n')], ["test_i3_reject_a_pr_that_rewrites_owner"])
mut("i4-reserved-list-from-new", [('names = classify.reserved_names(reserved_base)',
                                   'names = classify.reserved_names(files.get("reserved-namespaces.json", (None, reserved_base))[1])')],
    ["test_i4_reject_a_pr_cannot_strip"])
mut("i4-oracle-asked-about-the-wrong-org", [('out += _membership(ns, org, author, ctx["oracle"])', 'out += _membership(ns, "attacker-org", author, ctx["oracle"])')],
    ["test_i4_accept_membership_oracle_is_asked"])
mut("i5-302-followed-as-member", [('    if status == 204:', '    if status in (204, 302):')], ["test_i5_reject_a_302"])
mut("i5-direct-answers-ignored", [('    if status == 204:\n        return []', '    if status == 204:\n        return [_r9(ns, "x")]')],
    ["test_i5_accept_a_direct_answer"])
mut("i6-provider-ignored", [(R3GATE, 'if not ctx["authorised"] and (_owner_pair(existing) or (0, 0))[1] != author[1]:')],
    ["test_i6_reject_same_id_on_another_provider"])
mut("i6-login-alone-authorises", [(R3GATE, 'if not ctx["authorised"] and (login or "") != _d(_d(existing).get("owner")).get("name_at_registration"):')],
    ["test_i6_reject_a_login_alone_never_authorises", "test_i6_accept_provider_and_id_both_match"])
mut("i7-first-namespace-only", [('    for ns in sorted(by_ns):\n        findings += _namespace', '    for ns in sorted(by_ns)[:1]:\n        findings += _namespace')],
    ["test_i7_reject_one_foreign_namespace", "test_i7_reject_an_unauthorised_second_namespace"])
mut("i7-namespaces-pooled-accept-if-any-passes", [(
    '    for ns in sorted(by_ns):\n        findings += _namespace(ns, sorted(by_ns[ns]), ctx)',
    '    per = [_namespace(ns, sorted(by_ns[ns]), ctx) for ns in sorted(by_ns)]\n    findings += per[0] if all(per) else []')],
    ["test_i7_reject_one_foreign_namespace", "test_i7_accept_every_namespace_passes"])
mut("i8-verdict-claims-merge-signal", [("merge_signal=False)", "merge_signal=True)")], ["test_i8_accept_a_green_verdict"])

# ---------------------------------------------------------------------------------------------------------


def _suite(clone):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    p = subprocess.run([sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests/registry", "-p", "test_ownership.py"],
                       cwd=clone, capture_output=True, text=True, env=env)
    return p.returncode, [ln for ln in p.stderr.splitlines() if ln.startswith(("FAIL:", "ERROR:"))], p.stderr


def _apply(clone, edits):
    path = Path(clone) / OW
    for old, new in edits:
        text = path.read_text()
        if text.count(old) != 1:
            raise SystemExit(f"ANCHOR ERROR: {old[:70]!r} occurs {text.count(old)} times (need exactly 1)")
        path.write_text(text.replace(old, new))


def main(argv):
    if "--list" in argv:
        print("\n".join(m[0] for m in M))
        return 0
    discover = "--discover" in argv
    ids = [a for a in argv if not a.startswith("--")]
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True, check=True).stdout.strip()
    base = tempfile.mkdtemp(prefix="wom007b-mut-", dir=os.environ.get("WOM_TMP") or None)
    not_red = 0
    try:
        clone = os.path.join(base, "clone")
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", str(REPO), clone], check=True)
        subprocess.run(["git", "-C", clone, "checkout", "-q", sha], check=True)
        rc, lines, err = _suite(clone)
        if rc != 0:
            print("BASELINE NOT GREEN: a mutation proves nothing against a red suite")
            print(err[-2000:])
            return 99
        print(f"baseline green on committed {sha[:9]}")
        selected = [m for m in M if not ids or m[0] in ids]
        for mid, edits, red in selected:
            _apply(clone, edits)
            rc, lines, err = _suite(clone)
            subprocess.run(["git", "-C", clone, "checkout", "-q", "--", "."], check=True)
            if discover:
                print(f"== {mid}: {len(lines)} failing")
                for ln in lines[:14]:
                    print("   " + ln)
                continue
            missing = [r for r in red if not any(r in ln for ln in lines)]
            if rc == 0 or missing:
                not_red += 1
                print(f"NOT RED  {mid}: suite {'green' if rc == 0 else 'red'}; unreddened: {missing or '-'}")
            else:
                print(f"red      {mid}: {len(lines)} failing, all {len(red)} named tests red")
        print(f"SUMMARY {len(selected)} mutations, not_red={not_red}")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    return not_red


class MutationCoverage(unittest.TestCase):
    """B3: every rule in the contract has accepting + rejecting tests and a mutation naming a test of that rule."""

    @classmethod
    def setUpClass(cls):
        text = (REPO / "contracts" / "ownership.md").read_text()
        cls.rules = sorted(set(re.findall(r"\*\*([RI]\d+) \(MUST", text)), key=lambda r: (r[0], int(r[1:])))
        sys.path.insert(0, str(HERE))
        import test_ownership
        cls.tests = unittest.defaultTestLoader.getTestCaseNames(test_ownership.R1Path)  # sanity: loader works
        names = set()
        for obj in vars(test_ownership).values():
            if isinstance(obj, type) and issubclass(obj, unittest.TestCase):
                names |= set(unittest.defaultTestLoader.getTestCaseNames(obj))
        cls.names = names

    def test_b3_the_contract_still_declares_eleven_r_rules_and_eight_i_rules(self):
        self.assertEqual(len([r for r in self.rules if r[0] == "R"]), 11, self.rules)
        self.assertEqual(len([r for r in self.rules if r[0] == "I"]), 8, self.rules)

    def test_b3_every_rule_has_an_accepting_and_a_rejecting_test(self):
        for r in self.rules:
            for kind in ("accept", "reject"):
                with self.subTest(rule=r, kind=kind):
                    self.assertTrue([n for n in self.names if n.startswith(f"test_{r.lower()}_{kind}")],
                                    f"{r} has no {kind} test")

    def test_b3_every_non_descriptive_rule_has_a_mutation_that_names_one_of_its_tests(self):
        for r in self.rules:
            if r in DESCRIPTIVE:
                continue
            with self.subTest(rule=r):
                hits = [mid for mid, _, red in M if any(t.startswith(f"test_{r.lower()}_") for t in red)]
                self.assertTrue(hits, f"{r} is tagged by tests but no mutation reddens one of them")

    def test_b3_every_named_red_test_exists(self):
        for mid, _, red in M:
            for t in red:
                with self.subTest(mutation=mid, test=t):
                    self.assertTrue([n for n in self.names if n.startswith(t)], f"{t} matches no test")

    def test_b4_the_required_mutations_are_all_present(self):
        have = {m[0] for m in M}
        for want in ("b4-owner-from-new-i3", "b4-ignore-provider-i6", "b4-reserved-list-from-new-i4",
                     "b4-compare-logins-not-ids", "b4-302-is-member-r9-i5", "b4-302-is-not-member-r9-i5",
                     "b4-oracle-exception-is-member-r9", "b4-page-only-without-entry-accepted-r10",
                     "b4-namespaces-evaluated-jointly-i7", "b4-skip-fail-closed",
                     "b4-fail-closed-keyed-on-007a-classification", "b4-pipeline-app-id-bypasses-fail-closed",
                     "b4-any-author-may-use-r11", "b4-r11-admits-non-takedown-changes",
                     "b4-r11-precedence-shape-based-attempt-9", "b4-binding-pr-rebinds-existing-namespace",
                     "b4-reject-everything-positive-control", "b6-truncation-ignored",
                     "b6-malformed-t2-authorised", "b6-reserved-list-edit-beside-t2-authorised"):
            self.assertIn(want, have)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
