#!/usr/bin/env bash
#
# 008b3a-verify.sh -- the runnable verification artefact for task 008b-3a (ownership carve-out for the pipeline identity;
# MANAGER.md Section 2c). Covers criteria 4, 5 and 13 of docs/tasks/008b3a-ownership-carve-out.md.
#
# Usage:  docs/tasks/008b3a-verify.sh [--mutate]      (any cwd inside the repository; run it from a fresh clone of the pushed branch)
#   (no flag)  C4   the 057 oracle T1 and T3 fixtures, authored by the pipeline fixture id, are accepted; by any other id, rejected
#              C5   the carve-out is narrow: first publish, new version, page.json edit, takedown, mixed T1+T3, blank T3 reason,
#                   non-https build_log_url, anything under contracts/ or .github/ are rejected for that id; the hostile 007 fixture
#                   (id differs, username matches) still rejects; the owner's ordinary PR still accepts (positive control)
#              the whole of test_ownership.py is green (the 91 pre-existing tests unchanged); forbidden shapes are absent from the
#              code (no GITHUB_ACTOR*, the real bot id is not hard-coded); the own change touched only the declared scope
#   --mutate   C13: five mutations of the carve-out in a temporary clone at TIP (widen to a first publish; accept the id for a
#              page.json edit; drop the https:// check on build_log_url; accept a username instead of the id; accept two
#              transitions), each must redden its named test; each file is then restored from git and shown byte-identical
#              (sha256) and the suite is green again.
# Every check fails on zero matches (a test that did not run, or a name that is not found, is a FAIL, never a pass).
# Own-change checks read the pinned BASE and TIP blobs, never HEAD (a later task cannot redden them); the live guard is only
# "the whole tests/registry/test_ownership.py suite is green at HEAD". No network, no credential, no background process.
# Exit code: the number of failed checks. Requires: git, python3, bash.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

BASE=e213cbce9a2b33f70e72c564be377085a3045640   # registry origin/main the branch was cut from (094 merged)
TIP=827c562e0eedde5977d3be8f6faa2759cdf81bc5    # the commit holding the carve-out, its tests and the spec/log; later commits: this script and the log only
OW=tools/registry/ownership.py
TESTS=tests/registry/test_ownership.py
CLASS=test_ownership.PipelineCarveOut

MUTATE=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) printf 'usage: %s [--mutate]\n' "$0" >&2; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

OUT="$(mktemp -d)" || exit 99
cd "$ROOT" || exit 99

git cat-file -e "$BASE^{commit}" 2>/dev/null || { fail "BASE $BASE is not in this clone"; exit 1; }
git cat-file -e "$TIP^{commit}" 2>/dev/null || { fail "TIP $TIP is not in this clone"; exit 1; }

run_class() {  # $1 = tree, $2 = output file; runs only the PipelineCarveOut class, verbose
    (cd "$1" && python3 -I -B -m unittest discover -s tests/registry -p test_ownership.py -k PipelineCarveOut -v) >"$2" 2>&1
}

want_ok() {  # $1 = label, $2 = output file, $3.. = test names that must be reported ok (zero matches = FAIL)
    local label="$1" file="$2" shown=0 bad=0 name n
    shift 2
    for name in "$@"; do
        # a test with a docstring prints "name (id)" and then "<docstring> ... ok" on the next line
        n=$(awk -v t="$name" 'index($0, t " (") == 1 { if ($0 ~ /\.\.\. ok$/) c++; else { getline nx; if (nx ~ /\.\.\. ok$/) c++ } } END { print c + 0 }' "$file")
        if [ "$n" -ne 1 ]; then bad=1; printf '      %s: %s ok lines (want 1)\n' "$name" "$n"; fi
        shown=$((shown + 1))
    done
    if [ "$bad" -eq 0 ] && [ "$shown" -gt 0 ]; then pass "$label ($shown tests ok)"; else fail "$label"; fi
}

section "CLASS  PipelineCarveOut runs and is green at HEAD"
run_class "$ROOT" "$OUT/class.txt"
RAN=$(grep -c -E '\.\.\. ' "$OUT/class.txt")
if [ "$RAN" -ge 17 ] && grep -q '^OK$' "$OUT/class.txt"; then pass "the class ran $RAN tests, OK"; else fail "the class ran $RAN tests (want >= 17 and OK)"; tail -5 "$OUT/class.txt"; fi

section "C4  oracle T1 and T3, pipeline id accepted, any other id rejected"
want_ok "C4 accept t1-exact and t3-exact for the pipeline id" "$OUT/class.txt" test_e16_accept_oracle_t1_and_t3_by_the_pipeline_id
want_ok "C4 same diffs rejected for owner, stranger, other provider, id off by one" "$OUT/class.txt" test_e16_reject_the_same_diffs_authored_by_another_id
want_ok "C4 carve-out off (None) and the 007 pipeline_app_id still confer nothing" "$OUT/class.txt" test_e16_reject_when_the_carve_out_is_not_configured
python3 -I -B - <<'EOF' || FAILURES=$((FAILURES + 1))
import json, sys
fx = {f["name"]: f for f in json.load(open("docs/tasks/057-transition-fixtures.json"))}
need = ("t1-exact", "t3-exact")
missing = [n for n in need if n not in fx or fx[n]["expect"] != "accept"]
print(("FAIL  the 057 oracle fixtures %s are missing or not accept-expected" % missing) if missing else
      "PASS  the 057 oracle fixtures t1-exact and t3-exact exist and are accept-expected (the diffs are the oracle's, not built here)")
sys.exit(1 if missing else 0)
EOF

section "C5  the carve-out is narrow, both ways"
want_ok "C5 first publish rejected" "$OUT/class.txt" test_e16_reject_a_first_publish
want_ok "C5 new version rejected (alone, and appended beside a T1)" "$OUT/class.txt" test_e16_reject_a_new_version
want_ok "C5 page.json edit rejected (alone, and beside a T1)" "$OUT/class.txt" test_e16_reject_a_page_json_edit test_e16_reject_a_t1_with_a_page_json_edit_beside_it
want_ok "C5 takedown rejected, the carve-out never stands in for R11; T2 beside T1/T3 rejected" "$OUT/class.txt" test_e16_reject_a_takedown_the_carve_out_never_stands_in_for_r11 test_e16_reject_t2_beside_a_t1_or_t3
want_ok "C5 mixed T1 and T3 rejected (one file, two files, two T1)" "$OUT/class.txt" test_e16_reject_a_mixed_t1_and_t3_pr
want_ok "C5 blank T3 reason / non-https build_log_url rejected" "$OUT/class.txt" test_e16_reject_a_t3_with_a_blank_reason_or_a_non_https_build_log
want_ok "C5 T1 that changes anything else rejected" "$OUT/class.txt" test_e16_reject_a_t1_that_changes_anything_else
want_ok "C5 anything under contracts/ or .github/ rejected" "$OUT/class.txt" test_e16_reject_any_change_under_contracts_or_github
want_ok "C5 reserved namespace needs no membership for the carve-out" "$OUT/class.txt" test_e16_accept_in_a_reserved_namespace_without_membership
want_ok "C5 hostile: login matches, id differs, GITHUB_ACTOR* set -> rejected" "$OUT/class.txt" test_e16_reject_hostile_login_matches_but_id_differs
want_ok "C5 positive control: the owner's ordinary PR still accepts" "$OUT/class.txt" test_e16_accept_positive_control_an_owner_pr_is_unaffected
want_ok "C5 a malformed pipeline_identity is a ToolError, not a rejection" "$OUT/class.txt" test_e16_reject_bad_pipeline_identity_is_a_tool_error

section "007  the whole of test_ownership.py is green, including task 007's hostile fixtures (live guard, HEAD)"
(cd "$ROOT" && python3 -I -B -m unittest discover -s tests/registry -p test_ownership.py -v) >"$OUT/all.txt" 2>&1
ALLRAN=$(grep -c -E '\.\.\. ' "$OUT/all.txt")
if [ "$ALLRAN" -ge 108 ] && grep -q '^OK$' "$OUT/all.txt"; then pass "test_ownership.py: $ALLRAN tests, OK"; else fail "test_ownership.py: $ALLRAN tests (want >= 108 and OK)"; tail -5 "$OUT/all.txt"; fi
want_ok "007 hostile fixtures still reject (id differs, username matches)" "$OUT/all.txt" \
    test_i6_reject_a_login_alone_never_authorises test_r3_reject_same_username_different_id \
    test_b1_pipeline_app_id_equal_to_r11_identity_still_cannot_carry_t1_or_t3 test_b1_matrix_every_cell_rejected_with_the_adr_0121_message

section "FORBIDDEN  shapes absent from the code at TIP"
git show "$TIP:$OW" >"$OUT/ow.py"
python3 -I -B - "$OUT/ow.py" <<'EOF' || FAILURES=$((FAILURES + 1))
import ast, sys
src = open(sys.argv[1]).read()
tree = ast.parse(src)
doc_nodes = {id(n.body[0].value) for n in ast.walk(tree)
             if isinstance(n, (ast.Module, ast.FunctionDef)) and n.body and isinstance(n.body[0], ast.Expr)
             and isinstance(n.body[0].value, ast.Constant) and isinstance(n.body[0].value.value, str)}
code_strings = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in doc_nodes]
names = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)} | {n.attr for n in ast.walk(tree) if isinstance(n, ast.Attribute)}
bad = [s for s in code_strings if "GITHUB_ACTOR" in s] + [n for n in names if "ACTOR" in n.upper() or n in ("environ", "getenv")]
hard = "342916936" in src
has = "_pipeline_shape" in names or "def _pipeline_shape" in src
if bad: print("FAIL  GITHUB_ACTOR*/environment used as code in ownership.py: %r" % bad)
else: print("PASS  no GITHUB_ACTOR* or environment access in ownership.py code (docstring mentions excluded)")
if hard: print("FAIL  the real bot id 342916936 is hard-coded in ownership.py (it is the caller's configuration)")
else: print("PASS  the real bot id is not hard-coded in ownership.py")
if not has: print("FAIL  _pipeline_shape not found in ownership.py")
else: print("PASS  _pipeline_shape found in ownership.py")
sys.exit(1 if (bad or hard or not has) else 0)
EOF

section "SCOPE  the own change (BASE..TIP) touched only the declared files"
git diff --name-only "$BASE" "$TIP" | sort >"$OUT/changed.txt"
printf '%s\n' docs/tasks/008b3a-ownership-carve-out.md "$OW" "$TESTS" | sort >"$OUT/allowed.txt"
if [ -s "$OUT/changed.txt" ] && [ -z "$(comm -13 "$OUT/allowed.txt" "$OUT/changed.txt")" ]; then
    pass "BASE..TIP changed only: $(tr '\n' ' ' <"$OUT/changed.txt")"
else
    fail "BASE..TIP changed files outside the declared scope: $(comm -13 "$OUT/allowed.txt" "$OUT/changed.txt" | tr '\n' ' ')"
fi
if git diff "$BASE" "$TIP" -- "$TESTS" | grep -E '^-[^-]' | grep -q .; then fail "BASE..TIP removed or changed lines in $TESTS (additions only allowed)"; else pass "$TESTS: BASE..TIP is additions only (no existing test weakened)"; fi

if [ "$MUTATE" -eq 1 ]; then
    section "C13  mutations of the carve-out, each shown red, then restored byte-identically"
    git clone -q "$ROOT" "$OUT/mut" 2>/dev/null && git -C "$OUT/mut" checkout -q "$TIP" || { fail "could not make the mutation clone at TIP"; }
    MUT="$OUT/mut"
    mutate() {  # $1 = id, $2 = file (relative), $3 = old text, $4 = new text, $5.. = tests that must be FAIL/ERROR
        local id="$1" file="$2" old="$3" new="$4" sha_before sha_after n
        shift 4
        sha_before=$(sha256sum "$MUT/$file" | cut -d' ' -f1)
        OLD="$old" NEW="$new" python3 -I -B - "$MUT/$file" <<'EOF' || { fail "$id: the mutation did not apply (text not found exactly once)"; return; }
import os, sys
p = sys.argv[1]
s = open(p).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
EOF
        run_class "$MUT" "$OUT/m-$id.txt"
        local missing=0 t
        for t in "$@"; do
            n=$(grep -c -E "^(FAIL|ERROR): ${t} " "$OUT/m-$id.txt")
            if [ "$n" -lt 1 ]; then missing=1; printf '      %s did not go red\n' "$t"; fi
        done
        if [ "$missing" -eq 0 ] && grep -q '^FAILED' "$OUT/m-$id.txt"; then
            pass "$id: red ($(grep -c -E '^(FAIL|ERROR):' "$OUT/m-$id.txt") failing lines; named: $*)"
        else
            fail "$id: NOT RED"
        fi
        git -C "$MUT" checkout -q -- "$file"
        sha_after=$(sha256sum "$MUT/$file" | cut -d' ' -f1)
        if [ "$sha_before" = "$sha_after" ]; then pass "$id: restored byte-identically ($sha_after)"; else fail "$id: restore differs"; fi
        run_class "$MUT" "$OUT/r-$id.txt"
        if grep -q '^OK$' "$OUT/r-$id.txt"; then pass "$id: green after restore"; else fail "$id: not green after restore"; fi
    }
    mutate m1-widen-to-first-publish "$OW" \
        '    if p is None or p[2] != "entry" or old is None or new is None:
        return None
    if len(_versions(old))' \
        '    if p is not None and p[2] == "entry" and old is None and new is not None:
        return "T1"
    if p is None or p[2] != "entry" or old is None or new is None:
        return None
    if len(_versions(old))' \
        test_e16_reject_a_first_publish
    mutate m2-accept-id-for-page-json-edit "$OW" \
        '    if len(files) != 1:
        return None
    (path, (old, new)), = files.items()
    p = classify.parse_mod_path(path)' \
        '    if len(files) != 1:
        return None
    (path, (old, new)), = files.items()
    p = classify.parse_mod_path(path)
    if p is not None and p[2] == "page":
        return "T1"' \
        test_e16_reject_a_page_json_edit
    mutate m3-drop-https-check-on-build-log-url tools/registry/append_only.py \
        'if "build_log_url" in w and not _field_ok("build_log_url", w["build_log_url"]):' \
        'if False:' \
        test_e16_reject_a_t3_with_a_blank_reason_or_a_non_https_build_log
    mutate m4-accept-a-username-instead-of-the-id "$OW" \
        'carve_out = pipe is not None and author == pipe and' \
        'carve_out = pipe is not None and (author == pipe or login == "worldofmodcraft-pipeline[bot]") and' \
        test_e16_reject_hostile_login_matches_but_id_differs
    mutate m5-accept-two-transitions "$OW" \
        'len(changed) != 1 or changed[0]' \
        'len(changed) < 1 or changed[0]' \
        test_e16_reject_a_mixed_t1_and_t3_pr
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then printf 'ALL CHECKS PASSED (0 failures)\n'; else printf '%d CHECK(S) FAILED\n' "$FAILURES"; fi
exit "$FAILURES"
