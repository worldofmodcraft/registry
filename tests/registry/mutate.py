#!/usr/bin/env python3
"""Mutation runner for task 007a (MANAGER.md 2c rule 2): break the thing a check claims to check, in a
scratch CLONE of the committed tree, and require the named tests to turn red.

    python3 tests/registry/mutate.py [--list] [--discover] [id ...]

A mutation is (id, file, edits, red). `edits` is a list of (old, new) text replacements (old must occur
exactly once: a search that finds nothing is a broken search) or a callable(clone_root) for data-file
mutations. `red` lists substrings that must each appear in a FAIL/ERROR line of the mutated run; a
mutation whose run is green, or that does not redden every named test, counts as NOT RED (fails A3).
`--discover` prints the failing test lines of each mutation instead of judging (used to author `red`).
Exit code = number of mutations that did NOT redden their named tests (0 = all red).
Scratch location: $WOM_TMP if set, else the system temp dir. Nothing outside it is written.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
AO, CL, SC, RP = "tools/registry/append_only.py", "tools/registry/classify.py", "tools/registry/schema.py", \
    "tools/registry/report.py"
FIX = "docs/tasks/057-transition-fixtures.json"
M = []


def mut(mid, file, edits, red):
    M.append((mid, file, edits, red))


def allow_pair(mid, pair, red):
    """The oracle's allow_X mutations: accept a (old status, new status) pair outright."""
    mut(mid, AO, [('TRANSITIONS = {\n', f'TRANSITIONS = {{\n    {pair}: ("T1", lambda o, w: []),\n')], red)


# ---- (a) an analogue of every one of the 29 mutations in 057-oracle.py's MUTATIONS list ----------------
mut("oracle-01-skip_patterns", AO, [('def _field_ok(name, value):\n', 'def _field_ok(name, value):\n    return True\n')],
    ["first-publish-pending-bad-commit", "t1-sha256-wrong-length", "t3-build-log-url-http"])
mut("oracle-02-t3_keys_atleast", AO, [('    if set(w) != T3_KEYS:\n', '    if not T3_KEYS <= set(w):\n')],
    ["t3-extra-key", "t3-carries-signature"])
mut("oracle-03-t3_http_log", AO, [('not _field_ok("build_log_url", w["build_log_url"])', 'not str(w["build_log_url"]).startswith("http")')],
    ["t3-build-log-url-http"])
mut("oracle-04-t3_ws_reason", AO, [('    if "reason" in w and not _reason_ok(w["reason"]):\n', '    if "reason" in w and w["reason"] == "":\n')],
    ["t3-whitespace-only-reason"])
mut("oracle-05-born_pending_extra_key", AO, [('    if set(e) != FOUR:\n', '    if not FOUR <= set(e):\n')],
    ["first-publish-pending-with-reason", "first-publish-pending-with-build-log-url"])
mut("oracle-06-skip_version_frozen", AO, [('("version", "commit", "source_url"))', '("commit", "source_url"))')],
    ["t1-version-changed", "t3-version-changed"])
mut("oracle-07-nonstring_reason", AO, [('    return isinstance(r, str) and r.strip() != ""\n', '    return str(r).strip() != ""\n')],
    ["t3-reason-not-a-string-number", "t3-reason-not-a-string-null", "t3-reason-not-a-string-object"])
mut("oracle-08-skip_frozen_author", AO, [('def _author_frozen(o, w):\n', 'def _author_frozen(o, w):\n    return True\n')],
    ["t1-source-url-changed", "t3-commit-changed", "t1-version-changed"])
allow_pair("oracle-09-allow_pending_removed", '("pending", "removed")', ["pending-to-removed"])
mut("oracle-10-t1_not_all_five", AO, [('    if set(w) != NINE:\n        why.append(f"key set differs from exactly the nine published',
                                      '    if not (set(w) <= NINE and set(w) & set(FIVE)):\n        why.append(f"key set differs from exactly the nine published')],
    ["t1-missing-source_archive", "t1-missing-signature", "t1-missing-published_at"])
mut("oracle-11-t1_allow_reason", AO, [('    if set(w) != NINE:\n        why.append(f"key set differs from exactly the nine published',
                                      '    if set(w) not in (NINE, NINE | {"reason"}):\n        why.append(f"key set differs from exactly the nine published')],
    ["t1-with-reason"])
for _n, _s in (("12-allow_born_published", "published"), ("13-allow_born_removed", "removed"),
               ("14-allow_born_rejected", "rejected")):
    mut("oracle-" + _n, AO, [('    if e.get("status") != "pending":\n', f'    if e.get("status") == "{_s}":\n        return []\n    if e.get("status") != "pending":\n')],
        ["first-publish-born-" + _s, "append-born-published-later" if _s == "published" else "first-publish-born-" + _s])
allow_pair("oracle-15-allow_published_rejected", '("published", "rejected")', ["published-to-rejected"])
allow_pair("oracle-16-allow_rejected_pending", '("rejected", "pending")', ["rejected-to-pending"])
allow_pair("oracle-17-allow_rejected_published", '("rejected", "published")', ["rejected-to-published"])
allow_pair("oracle-18-allow_rejected_rewrite", '("rejected", "rejected")', ["rejected-reason-rewritten"])
mut("oracle-19-t3_no_reason", AO, [('    if set(w) != T3_KEYS:\n', '    if set(w) not in (T3_KEYS, T3_KEYS - {"reason"}):\n')],
    ["t3-missing-reason"])
mut("oracle-20-t3_no_log", AO, [('    if set(w) != T3_KEYS:\n', '    if set(w) not in (T3_KEYS, T3_KEYS - {"build_log_url"}):\n')],
    ["t3-missing-build-log-url"])
mut("oracle-21-allow_delete_rejected", AO, [('    if len(nv) < n:\n', '    if len(nv) < n and not all(e.get("status") == "rejected" for e in ov[len(nv):]):\n')],
    ["rejected-deleted"])
allow_pair("oracle-22-allow_published_pending", '("published", "pending")', ["published-to-pending"])
mut("oracle-23-raw_text_compare", AO, [('    if isinstance(a, dict) and isinstance(b, dict):\n        return a.keys()', '    import json\n    return json.dumps(a) == json.dumps(b)\n    if isinstance(a, dict) and isinstance(b, dict):\n        return a.keys()')],
    ["t1-plus-whitespace-and-key-order-change-elsewhere"])
mut("oracle-24-t1_keys_atleast", AO, [('    if set(w) != NINE:\n        why.append(f"key set differs from exactly the nine published',
                                      '    if not NINE <= set(w):\n        why.append(f"key set differs from exactly the nine published')],
    ["t1-extra-key", "t1-with-reason"])
allow_pair("oracle-25-allow_pending_rewrite", '("pending", "pending")', ["pending-to-pending-changed-commit"])
mut("oracle-26-skip_owner_freeze", AO, [('        if not _same(new.get("owner"), old.get("owner")):\n', '        if False:\n')],
    ["t1-plus-owner-change", "test_each_owner_subfield_change_is_rejected"])
mut("oracle-27-t2_ws_reason", AO, [('    if not _reason_ok(w.get("reason")):\n', '    if "reason" not in w or w.get("reason") == "":\n')],
    ["t2-takedown-whitespace-reason"])
mut("oracle-28-allow_rule4_dup", AO, [('if sum(1 for v in versions if _same(v, versions[j])) > 1:', 'if False:')],
    ["first-publish-duplicate-version-strings"])
mut("oracle-29-reject_all", AO, [('def check_entry(old, new, path=None):\n', 'def check_entry(old, new, path=None):\n    return report.make("append-only", [report.finding(["x"], "w", "f", "c")], state="x", elements=[], authority_required=[])\n')],
    ["first-publish-one-pending", "t1-exact", "t2-takedown-exact", "t3-exact", "test_clean_first_publish_is_accepted_positive_control"])

# ---- (b) rule 1/3 and file-level mutations the oracle does not cover ----------------------------------
mut("b-inplace-edit-of-published", AO, [('        key = (o.get("status"), w.get("status"))\n', '        if o.get("status") == "published" and w.get("status") == "published":\n            elements.append({"index": i, "classification": "unchanged", "rules": []})\n            continue\n        key = (o.get("status"), w.get("status"))\n')],
    ["published-rewritten-hashes", "test_in_place_edit_of_a_published_element_is_rule_1"])
mut("b-allow-truncation", AO, [('    if len(nv) < n:\n', '    if False:\n')],
    ["delete-pending-version", "test_truncating_the_array_is_rule_3"])
mut("b-allow-id-change", AO, [('        if not _same(new.get("id"), old.get("id")):\n', '        if False:\n')],
    ["t1-plus-id-change", "test_id_change_is_rejected"])
mut("b-allow-owner-id-bool", AO, [('    return isinstance(a, bool) == isinstance(b, bool) and a == b\n', '    return a == b\n')],
    ["test_owner_id_true_is_not_the_number_one"])
mut("b-allow-entry-deletion", AO, [('    if new is None:\n', '    if new is None:\n        return report.make("append-only", [], state="present->absent", elements=[], authority_required=[])\n')],
    ["entry-deleted", "test_present_to_absent_is_a_deletion_violation"])
mut("b-allow-rename", AO, [('            v = check_entry(old, new, path)\n', '            v = check_entry(old, new, path) if new is not None else check_entry(None, None, path)\n')],
    ["test_rename_is_a_deletion_plus_a_creation_and_is_rejected"])
mut("b-allow-reorder-by-content", AO, [('        if _same(o, w):\n', '        if any(_same(w, x) for x in ov):\n')],
    ["t1-reorders-versions", "test_reordering_identical_elements_is_a_violation_at_each_moved_index"])
mut("b-allow-remove-and-readd", AO, [('        if _same(o, w):\n', '        if _same(o, w) or (len(nv) == n and all(any(_same(x, y) for y in ov) for x in nv)):\n')],
    ["test_remove_and_readd_identically_is_a_violation", "test_remove_one_and_append_identical_copy_keeps_length_but_fails"])
allow_pair("b-allow-published-to-pending", '("published", "pending")', ["test_published_to_pending_is_rule_1"])

# ---- (c) T2 variants ----------------------------------------------------------------------------------
mut("c-t2-also-changes-another-field", AO, [('    for k in sorted(NINE - {"status"}):\n', '    for k in []:\n')],
    ["t2-takedown-hash-changed", "test_t2_that_also_changes_another_field_is_rejected"])
mut("c-t2-whitespace-reason", AO, [('    if not _reason_ok(w.get("reason")):\n', '    if "reason" not in w or w.get("reason") == "":\n')],
    ["t2-takedown-whitespace-reason", "test_t2_reason_must_be_present_a_string_and_non_blank_after_trim"])
mut("c-t2-old-status-not-published", AO, [
    ('        key = (o.get("status"), w.get("status"))\n', '        key = (o.get("status"), w.get("status"))\n        if key[1] == "removed":\n            key = ("published", "removed")\n'),
    ('    for k in sorted(NINE - {"status"}):\n', '    for k in []:\n')],
    ["pending-to-removed", "rejected-to-removed", "test_takedown_from_an_old_status_other_than_published_is_rejected"])

# ---- (d) T3 / born-pending / published->rejected ------------------------------------------------------
mut("d-t3-http-build-log", AO, [('not _field_ok("build_log_url", w["build_log_url"])', 'not str(w["build_log_url"]).startswith("http")')],
    ["t3-build-log-url-http", "test_t3_hostile_variants_are_rule_1"])
mut("d-t3-extra-key", AO, [('    if set(w) != T3_KEYS:\n', '    if not T3_KEYS <= set(w):\n')],
    ["t3-extra-key", "test_t3_hostile_variants_are_rule_1"])
mut("d-born-pending-fifth-key", AO, [('    if set(e) != FOUR:\n', '    if not FOUR <= set(e):\n')],
    ["first-publish-pending-with-reason", "test_born_pending_with_a_fifth_key_is_rule_2"])
allow_pair("d-published-to-rejected", '("published", "rejected")', ["published-to-rejected", "test_published_to_rejected_is_rule_1"])
mut("d-rule4-one-sided", AO, [('if sum(1 for v in versions if _same(v, versions[j])) > 1:', 'if any(_same(v, versions[j]) for v in versions[:j]):')],
    ["test_a2_four_element_element_0_breaks_rule_4", "test_duplicate_between_two_new_elements_flags_both_with_rule_4"])
mut("d-rule4-skips-history", AO, [('if sum(1 for v in versions if _same(v, versions[j])) > 1:', 'if sum(1 for v in versions[n:] if _same(v, versions[j])) > 1:')],
    ["test_duplicate_against_history_is_rule_4", "test_a_rejected_version_string_stays_occupied"])

# ---- (e) schema validation and path -> class mapping --------------------------------------------------
mut("e-skip-schema-validation", SC, [('            schema_check.validate(value, schemas[kind])\n', '            pass\n')],
    ["test_invalid_documents_are_rejected_with_the_validator_message", "test_the_attacker_four_element_entry_is_schema_rejected"])
mut("e-wrong-schema-for-path", SC, [('SCHEMA_FILES = {"entry": "entry.schema.json", "page": "page.schema.json"}', 'SCHEMA_FILES = {"entry": "page.schema.json", "page": "entry.schema.json"}')],
    ["test_valid_entry_and_page_are_accepted_positive_control"])
mut("e-wrong-schema-kind-swap", SC, [('        kind = parsed[2]\n', '        kind = "page" if parsed[2] == "entry" else "entry"\n')],
    ["test_valid_entry_and_page_are_accepted_positive_control"])
mut("e-corrupt-class-mapping", CL, [('    elif "entry" in kinds:\n        cls = CLASS_ENTRY\n    else:\n        cls = CLASS_PAGE\n', '    elif "page" in kinds:\n        cls = CLASS_ENTRY\n    else:\n        cls = CLASS_PAGE\n')],
    ["test_entry_only_pr_is_entry_class", "test_page_only_pr_is_page_only_class"])
mut("e-nomods-path-accepted-as-no-schema", SC, [('            findings.append(report.finding(\n                ["no-schema"]', '            results.append(report.finding(\n                ["no-schema"]')],
    ["test_a_path_with_no_implied_schema_is_rejected"])
mut("e-unparseable-json-text-skipped", SC, [('            except ValueError as exc:\n', '            except ZeroDivisionError as exc:\n')],
    ["test_raw_text_that_is_not_json_is_a_rejection_not_a_tool_error"])
mut("e-unsupported-keyword-swallowed", SC, [('            raise report.ToolError(f"schema_check cannot evaluate', '            continue\n            raise report.ToolError(f"schema_check cannot evaluate')],
    ["test_an_unsupported_schema_keyword_is_a_tool_error_never_a_silent_pass"])

# ---- (f) classification, exit codes, authority_required -----------------------------------------------
mut("f-mixed-page-entry-as-page-only", CL, [('    elif "entry" in kinds:\n', '    elif False:\n')],
    ["test_page_plus_entry_does_not_get_the_light_page_gate", "test_entry_only_pr_is_entry_class"])
mut("f-unknown-path-class-accepted", CL, [('    return report.make("classify", findings, **{"class": cls})\n', '    return report.make("classify", [f for f in findings if "unrecognised-path" not in f["rules"]], **{"class": cls})\n')],
    ["test_paths_outside_mods_are_unrecognised_and_rejected", "test_good_plus_outside_path_is_other_never_a_silent_pass"])
mut("f-r1-not-enforced", CL, [('    return report.make("classify", findings, **{"class": cls})\n', '    return report.make("classify", [f for f in findings if "R1" not in f["rules"]], **{"class": cls})\n')],
    ["test_every_malformed_path_under_mods_is_rejected_citing_r1"])
mut("f-r1-prefix-match", CL, [('PATH_RE.fullmatch(path)', 'PATH_RE.match(path)')],
    ["test_every_malformed_path_under_mods_is_rejected_citing_r1"])
mut("f-reserved-ignored", CL, [('touches_reserved = touches_reserved or parsed[0] in names', 'touches_reserved = touches_reserved or False')],
    ["test_reserved_namespace_pr_is_reserved_class_even_for_page_json"])
mut("f-empty-pr-accepted", CL, [('    if not paths:\n', '    if False:\n')],
    ["test_empty_path_set_is_rejected"])
mut("f-usage-error-as-rejection-exit", RP, [('not a rejection): {exc}\\n")\n        return EXIT_ERROR', 'not a rejection): {exc}\\n")\n        return EXIT_REJECTED')],
    ["test_run_maps_accepted_rejected_tool_error_and_crash_to_three_distinct_exits", "test_unreadable_or_garbage_reserved_list_is_exit_2_not_a_rejection"])
mut("f-crash-as-rejection-exit", RP, [('{type(exc).__name__}: {exc}\\n")\n        return EXIT_ERROR', '{type(exc).__name__}: {exc}\\n")\n        return EXIT_REJECTED')],
    ["test_run_maps_accepted_rejected_tool_error_and_crash_to_three_distinct_exits"])
mut("f-exit-codes-collapsed", RP, [('EXIT_ERROR = 2\n', 'EXIT_ERROR = 1\n')],
    ["test_the_three_exit_codes_are_distinct_and_documented", "test_usage_errors_exit_2_and_print_no_verdict"])
mut("f-drop-authority-required", AO, [('    authority = sorted({e["classification"] for e in elements if e["classification"] in ("T1", "T2", "T3")})\n', '    authority = []\n')],
    ["test_exact_t1_is_shape_legal_and_needs_authority", "test_a1_t1_exact", "test_a5_two_valid_t2s_are_shape_accepted_with_t2_authority"])
mut("f-message-without-remedy", RP, [("{what}. To fix: {fix}\"", "{what}.\"")],
    ["test_rejection_messages_name_the_problem_the_rule_and_the_remedy", "test_parity_every_reject_fixture_carries_a_rule_and_a_message"])
mut("f-rule-attribution-collapsed-to-one", AO, [('        if rules:\n            el, f = _violation(j, rules,', '        rules = rules[:1]\n        if rules:\n            el, f = _violation(j, rules,')],
    ["test_a2_four_element_element_0_breaks_rule_4", "test_a2_three_element_variant_element_0_rules_2_and_4"])
mut("f-page-json-treated-as-append-only", AO, [('        elif parsed[2] == "page":\n            skipped.append(path)\n', '        elif parsed[2] == "page" and False:\n            skipped.append(path)\n')],
    ["test_page_json_is_not_append_only_and_is_skipped"])

# ---- (g) positive controls: a checker that rejects everything -----------------------------------------
mut("g-classify-rejects-everything", CL, [('    names = reserved_names(reserved)\n', '    names = reserved_names(reserved)\n    paths = list(paths) + ["zzz"]\n')],
    ["test_entry_only_pr_is_entry_class", "test_page_only_pr_is_page_only_class"])
mut("g-schema-rejects-everything", SC, [('    findings, results = [], []\n', '    findings, results = [report.finding(["x"], "w", "f", "c")], []\n')],
    ["test_valid_entry_and_page_are_accepted_positive_control"])

# ---- A4: the fixture-count guard ----------------------------------------------------------------------


def _fixtures(root, fn):
    p = Path(root) / FIX
    data = json.loads(p.read_text())
    p.write_text(json.dumps(fn(data)))


def _drop_last(data):
    return data[:-1]


def _fewer_accepts(data):
    """Same count (73), but only 10 accept fixtures: one accept replaced by a copy of a reject fixture."""
    out = list(data)
    i = next(k for k, f in enumerate(out) if f["expect"] == "accept")
    rej = next(f for f in out if f["expect"] == "reject")
    out[i] = dict(rej, name="stand-in-" + rej["name"])
    return out


mut("a4-fewer-than-73-fixtures", None, [lambda root: _fixtures(root, _drop_last)], ["test_a4_fixture_file_is_readable_and_large_enough"])
mut("a4-fewer-than-11-accepts", None, [lambda root: _fixtures(root, _fewer_accepts)], ["test_a4_fixture_file_is_readable_and_large_enough"])
mut("a4-fixture-file-unreadable", None, [lambda root: (Path(root) / FIX).write_text("{not json")], ["test_a4_fixture_file_is_readable_and_large_enough", "test_parity_every_fixture_matches_recorded_expectation"])
mut("a4-fixture-file-missing", None, [lambda root: (Path(root) / FIX).unlink()], ["test_a4_fixture_file_is_readable_and_large_enough"])


def run_suite(clone):
    p = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests/registry"], cwd=clone,
                       capture_output=True, text=True)
    lines = [ln for ln in p.stderr.splitlines() if ln.startswith(("FAIL:", "ERROR:"))]
    return p.returncode, lines, p.stderr


def apply(clone, file, edits):
    for e in edits:
        if callable(e):
            e(clone)
            continue
        old, new = e
        path = Path(clone) / file
        text = path.read_text()
        if text.count(old) != 1:
            raise SystemExit(f"ANCHOR ERROR in {file}: {old!r} occurs {text.count(old)} times (need exactly 1)")
        path.write_text(text.replace(old, new))


def main(argv):
    if "--list" in argv:
        print("\n".join(m[0] for m in M))
        return 0
    discover = "--discover" in argv
    ids = [a for a in argv if not a.startswith("--")]
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO, capture_output=True, text=True, check=True).stdout.strip()
    base = tempfile.mkdtemp(prefix="wom007a-mut-", dir=os.environ.get("WOM_TMP") or None)
    not_red = 0
    try:
        clone = os.path.join(base, "clone")
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", str(REPO), clone], check=True)
        subprocess.run(["git", "-C", clone, "checkout", "-q", sha], check=True)
        rc, lines, err = run_suite(clone)
        if rc != 0:
            print("BASELINE NOT GREEN: a mutation proves nothing against a red suite")
            print(err[-2000:])
            return 99
        print(f"baseline green on committed {sha[:9]}")
        selected = [m for m in M if not ids or m[0] in ids]
        for mid, file, edits, red in selected:
            apply(clone, file, edits)
            rc, lines, err = run_suite(clone)
            subprocess.run(["git", "-C", clone, "checkout", "-q", "--", "."], check=True)
            if discover:
                print(f"== {mid}: {len(lines)} failing")
                if any("_FailedTest" in ln for ln in lines):
                    print("   (import-time failure) " + err.strip().splitlines()[-1])
                for ln in lines[:12]:
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


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
