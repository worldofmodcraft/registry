#!/usr/bin/env bash
#
# 094-verify.sh -- the runnable verification artefact for task 094 (MANAGER.md 2c):
# the pipeline matches every schema pattern with the registry gate's ECMA-262 semantics (tools/pipeline/ecma.py).
#
#   ./docs/tasks/094-verify.sh            own-change checks at the pinned SHAs, red-first at commit A, the pipeline suite at HEAD,
#                                         and the live guards
#   ./docs/tasks/094-verify.sh --mutate   also: positive control, then each mutation of a scratch copy of the tree at FINAL must
#                                         turn its named checks red (m1, m2, m3, m3b, m3c, m5, m7), the documented equivalent
#                                         mutation must stay green, and tests/pipeline/mutate.py (m6) must report not_red=0
#
# Exit code = the number of failed checks (0 = everything passed). One line per check; missing tools are a FAILURE.
# No network, no credential, no key. Scratch space is one mktemp -d directory, emptied with `find -delete` on exit.
#
# Pins (full SHAs; own-change checks read only these, never HEAD and never origin/main):
#   BASE  registry main the branch was cut from (235fea1, the merge of PR #41, task 111b)
#   A     commit A: the tests only, red against BASE's code
#   FINAL the last content commit (code, tests, docs); the commits after it add only docs/tasks/094-* (this script and the log),
#         which no check can pin without a cycle (the reviewer reads those two files)
# Live guards (read HEAD, true for as long as the code stands): the pipeline suite, the N3 -> N5 import grep, `_ecma_digits` absent.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }
note() { echo "note  $*"; }

BASE=235fea1980a98ab9f7c75ca856b78425975d6a4b
A=f257a53552cbb661b0bf6f7d388b24303f2721a0
FINAL=a5710ed0aaae5b7a547e3509363cec55beb2474b

export PYTHONDONTWRITEBYTECODE=1
PY="python3 -I -B"
MODE="${1:-}"

for tool in git python3 grep tar find minisign; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

RUNTMP=$(mktemp -d "${TMPDIR:-/tmp}/w094-run.XXXXXX") || { echo "FAIL  cannot create the scratch directory"; exit 99; }
cleanup() { [ -n "$RUNTMP" ] && [ -d "$RUNTMP" ] && find "$RUNTMP" -delete 2>/dev/null; }
trap cleanup EXIT
export TMPDIR="$RUNTMP"

# ------------------------------------------------------------------------------------------------ own-change checks (pins)
pin_ok() { [[ "$1" =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "$1^{commit}" 2>/dev/null; }
for pin in BASE A FINAL; do
  if pin_ok "${!pin}"; then ok "pin $pin is a full SHA and resolves (${!pin:0:7})"; else fail "pin $pin (${!pin}) is not a full SHA or does not resolve"; fi
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (a pin is unreachable: fetch the branch)"; exit "$FAILS"; }

git merge-base --is-ancestor "$BASE" "$A" && git merge-base --is-ancestor "$A" "$FINAL" && git merge-base --is-ancestor "$FINAL" HEAD \
  && ok "BASE <= A <= FINAL <= HEAD" || fail "the pins are not in order BASE <= A <= FINAL <= HEAD"

# Criterion 1: commit A is tests only.
a_files=$(git diff --name-only "$A^" "$A")
[ "$a_files" = "tests/pipeline/test_ecma_patterns.py" ] && ok "commit A changes exactly tests/pipeline/test_ecma_patterns.py (tests only)" \
  || fail "commit A is not tests only: $(echo "$a_files" | tr '\n' ' ')"
[ "$(git diff --name-only "$BASE" "$A^")" = "docs/tasks/094-pipeline-ecma-patterns.md" ] && ok "BASE..A^ is only the spec copy" \
  || fail "BASE..A^ holds more than the spec copy"

# File scope (spec). handoff.py and sign_built.py are NOT in it: if either needs an edit the task stops and reports.
SCOPE_RE='^(tools/pipeline/(ecma|build_version|write_back|plan_pending)\.py|tests/pipeline/(test_ecma_patterns|test_write_back|mutate)\.py|docs/pipeline/build-pipeline\.md|docs/tasks/094-pipeline-ecma-patterns\.md)$'
files=$(git diff --name-only "$BASE" "$FINAL")
bad=$(printf '%s\n' "$files" | grep -vE "$SCOPE_RE")
[ -n "$files" ] && [ -z "$bad" ] && ok "git diff --name-only BASE FINAL is non-empty and inside the file scope ($(printf '%s\n' "$files" | wc -l) files)" \
  || fail "BASE..FINAL is empty or touches out-of-scope files: ${bad:-<empty diff>}"
for must in tools/pipeline/ecma.py tests/pipeline/test_ecma_patterns.py tools/pipeline/build_version.py tools/pipeline/write_back.py tools/pipeline/plan_pending.py docs/pipeline/build-pipeline.md; do
  printf '%s\n' "$files" | grep -qx "$must" && ok "BASE..FINAL changes $must" || fail "BASE..FINAL does not change $must"
done
for forbidden in tools/registry/schema.py tests/contracts/schema_check.py tools/pipeline/handoff.py tools/pipeline/sign_built.py; do
  [ -z "$(git diff --name-only "$BASE" "$FINAL" -- "$forbidden")" ] && ok "BASE..FINAL leaves $forbidden untouched" || fail "BASE..FINAL touches $forbidden"
done
[ -z "$(git diff --name-only "$BASE" "$FINAL" -- contracts)" ] && ok "BASE..FINAL leaves contracts/ untouched" || fail "BASE..FINAL touches contracts/"
other=$(git diff --name-only "$BASE" "$FINAL" | grep -E '^docs/tasks/.*(-verify\.sh|\.py|\.json)$')
[ -z "$other" ] && ok "BASE..FINAL touches no verify script, pin file or fixture under docs/tasks" || fail "BASE..FINAL touches: $other"

# Content of ecma.py at FINAL (a pinned blob, not the worktree).
ECMA=$(git show "$FINAL:tools/pipeline/ecma.py" 2>/dev/null)
[ -n "$ECMA" ] && ok "tools/pipeline/ecma.py exists at FINAL" || fail "tools/pipeline/ecma.py is missing at FINAL"
echo "$ECMA" | grep -qF 're.search(schema.ecma_pattern(pattern), value)' && ok "ecma.matches is the gate's expression re.search(ecma_pattern(p), s)" \
  || fail "ecma.matches is not re.search(schema.ecma_pattern(pattern), value)"
echo "$ECMA" | grep -qE '^(import|from)[[:space:]]+(subprocess|socket|ssl|urllib|http|requests|ftplib|smtplib|asyncio)' \
  && fail "ecma.py imports a process or network library" || ok "ecma.py imports neither subprocess nor a network library (008c AC6 stays green)"
echo "$ECMA" | grep -qE 're\.ASCII|re\.A\b|\(\?a\)|re\.IGNORECASE|re\.MULTILINE' && fail "ecma.py uses a global re flag" || ok "ecma.py uses no global re flag"
echo "$ECMA" | grep -qE 'except[[:space:]]+(\(.*)?NotImplementedError' && fail "ecma.py catches NotImplementedError" || ok "ecma.py does not catch NotImplementedError"
echo "$ECMA" | grep -qE '_OUTSIDE|_INSIDE|def ecma_pattern' && fail "ecma.py copies the translator" || ok "ecma.py does not copy the translator (it loads tools/registry/schema.py)"
for f in build_version write_back plan_pending; do
  git show "$FINAL:tools/pipeline/$f.py" | grep -qE 'except[[:space:]]+NotImplementedError' && fail "$f.py has an except NotImplementedError" || ok "$f.py has no except NotImplementedError"
  git show "$FINAL:tools/pipeline/$f.py" | grep -qE '^import ecma' && ok "$f.py imports ecma" || fail "$f.py does not import ecma"
  git show "$FINAL:tools/pipeline/$f.py" | grep -qE 're\.ASCII|\(\?a\)' && fail "$f.py uses re.ASCII" || ok "$f.py uses no re.ASCII"
done
# Criterion 6: docs at FINAL.
DOC=$(git show "$FINAL:docs/pipeline/build-pipeline.md")
echo "$DOC" | grep -qF 'tools/pipeline/ecma.py' && ok "build-pipeline.md names tools/pipeline/ecma.py" || fail "build-pipeline.md does not name tools/pipeline/ecma.py"
echo "$DOC" | grep -qF 'U+001C-U+001F and U+0085' && ok "build-pipeline.md's bad-value row states the U+001C-U+001F / U+0085 behaviour" || fail "build-pipeline.md lacks the U+001C-U+001F / U+0085 sentence"
for stale in 'task 094 will move' 'left at Python' 'is translated to `\[0-9\]` when the pattern is loaded' 'matched with `fullmatch`'; do
  echo "$DOC" | grep -qE "$stale" && fail "build-pipeline.md still says: $stale" || ok "build-pipeline.md no longer says: $stale"
done

# ------------------------------------------------------------------------------------------------ live guards (HEAD)
# Criterion 6: the removed function is absent from tools/ and tests/, at FINAL (pinned) and at HEAD (live).
[ -z "$(git grep -n '_ecma_digits' "$FINAL" -- tools tests)" ] && ok "_ecma_digits is absent from tools/ and tests/ at FINAL" || fail "_ecma_digits still appears at FINAL"
[ -z "$(git grep -n '_ecma_digits' HEAD -- tools tests)" ] && ok "_ecma_digits is absent from tools/ and tests/ at HEAD" || fail "_ecma_digits appears at HEAD"
printf 'x = wb._ecma_digits(p)\n' > "$RUNTMP/ctl.py"
[ -n "$(grep -rn '_ecma_digits' "$RUNTMP/ctl.py")" ] && ok "control: the grep finds a planted _ecma_digits" || fail "control: the grep does not find a planted _ecma_digits"

# Criterion 7: no N3 -> N5 import. N3 = tools/registry; N5 = tools/pipeline. One-way: pipeline -> registry only.
n3_imports_n5() {  # $1 = directory of N3 python files; prints offending lines
  local names
  names=$(for f in tools/pipeline/*.py; do b=${f##*/}; printf '%s|' "${b%.py}"; done)
  names=${names%|}
  grep -rnE "^[[:space:]]*(import|from)[[:space:]]+(${names})([[:space:]]|\\.|,|\$)|^[[:space:]]*from[[:space:]]+tools\\.pipeline|tools/pipeline|[\"']pipeline[\"']" "$1" --include='*.py'
}
mkdir "$RUNTMP/n3ctl"
printf 'import write_back\n' > "$RUNTMP/n3ctl/a.py"
printf 'from tools.pipeline import ecma\n' > "$RUNTMP/n3ctl/b.py"
printf 'HERE = os.path.join(REPO, "tools", "pipeline")\nP = "tools/pipeline/x.py"\n' > "$RUNTMP/n3ctl/c.py"
[ "$(n3_imports_n5 "$RUNTMP/n3ctl" | wc -l)" -ge 3 ] && ok "control: the N3 -> N5 grep catches a planted import, a planted tools.pipeline import and a planted path" || fail "control: the N3 -> N5 grep misses a planted import"
hits=$(n3_imports_n5 tools/registry)
[ -z "$hits" ] && ok "no file under tools/registry imports or names tools/pipeline (N3 never imports N5)" || fail "N3 -> N5: $hits"
[ -n "$(grep -n 'tools.*registry' tools/pipeline/ecma.py)" ] && ok "the one-way import N5 -> N3 exists (ecma.py loads tools/registry/schema.py)" || fail "ecma.py does not load tools/registry/schema.py"

# Criterion 5: the pipeline suite (the invocation 008a-verify.sh uses) at HEAD.
SUITE_FLOOR=$((147 + 25))
OUT=$($PY tests/pipeline/run_checks.py 2>"$RUNTMP/suite-stderr")
PASSN=$(echo "$OUT" | grep -c '^CHECK .* PASS$')
FAILN=$(echo "$OUT" | grep -c '^CHECK .* FAIL$')
echo "$OUT" | grep '^CHECK .* FAIL$' | sed 's/^/FAIL  /'
echo "suite at HEAD: $PASSN passed, $FAILN failed; $(echo "$OUT" | grep '^SUMMARY')"
[ "$FAILN" -eq 0 ] && echo "$OUT" | grep -q '^SUMMARY ran=[0-9]* failed=0$' && ok "the pipeline suite is green at HEAD (SUMMARY failed=0)" || { fail "$FAILN suite check(s) failed"; cat "$RUNTMP/suite-stderr" >&2; }
[ "$PASSN" -ge "$SUITE_FLOOR" ] && ok "the suite ran at least $SUITE_FLOOR checks (147 + the 25 new ones): $PASSN" || fail "the suite ran only $PASSN checks (floor $SUITE_FLOOR)"
for pat in 'RedFirst.test_c1a' 'RedFirst.test_c1b' 'RedFirst.test_c1c' 'PositiveControls.test_c2' 'Equivalence.test_c3' 'NewCallers.test_c3b' 'PlanPendingValidator' 'Helper.test_'; do
  P=$(echo "$OUT" | grep -c "^CHECK ${pat}.* PASS$"); F=$(echo "$OUT" | grep -c "^CHECK ${pat}.* FAIL$")
  [ "$P" -ge 1 ] && [ "$F" -eq 0 ] && ok "$pat*: $P passing, 0 failing" || fail "$pat*: $P passing, $F failing"
done
[ "$(echo "$OUT" | grep -c '^CHECK ReviewFixes.*PASS$')" -ge 7 ] && ok "test_write_back's ReviewFixes (008c's fix-round tests) all pass" || fail "test_write_back's ReviewFixes did not all pass"

# ------------------------------------------------------------------------------------------------ red first at A, green at FINAL
extract() {  # extract REV DIR
  mkdir -p "$2" && git archive "$1" | tar -x -C "$2"
}
status_of() {  # status_of OUTFILE NAME -> PASS | FAIL | MISSING
  local hits
  hits=$(grep -F -- "$2" "$1" | grep '^CHECK ' || true)
  if [ -z "$hits" ]; then echo MISSING; elif echo "$hits" | grep -qv ' PASS$'; then echo FAIL; else echo PASS; fi
}
extract "$A" "$RUNTMP/at-A" || fail "cannot export commit A"
( cd "$RUNTMP/at-A" && $PY tests/pipeline/run_checks.py --only test_ecma_patterns ) > "$RUNTMP/A.out" 2>"$RUNTMP/A.err"
RED_AT_A="test_c1a_build_version_rejects_a_non_ascii_digit_in_the_version
test_c1a_build_version_rejects_a_non_ascii_digit_in_published_at
test_c1b_write_back_refuses_u_feff_in_source_archive
test_c1c_write_back_accepts_u_001c_to_u_001f_and_u_0085_in_source_archive
test_c3_helper_verdict_equals_the_gates_for_every_pattern
test_c3b_sign_built_gives_the_gates_verdict_on_built_at
test_validator_gives_the_gates_verdict
test_a_pending_entry_whose_source_url_holds_u_0085_is_planned_not_faulted
test_escaped_backslash_is_not_mangled
test_an_untranslatable_construct_propagates_not_implemented_error
test_matches_is_the_gates_expression_search_not_fullmatch
test_a_non_string_value_never_matches
test_helper_imports_neither_a_process_nor_a_network_library"
for t in $RED_AT_A; do
  s=$(status_of "$RUNTMP/A.out" "$t"); [ "$s" = FAIL ] && ok "red at A: $t" || fail "at A $t is $s (it must FAIL against BASE's code)"
done
# Pins, not red-first: these hold both before and after (positive controls of criterion 2; verdicts that BASE's write_back already gave).
GREEN_AT_A="test_c2_unicode_whitespace_in_source_archive_stays_refused
test_c2_ordinary_non_ascii_visible_characters_stay_accepted
test_c2_id_with_a_trailing_newline_stays_rejected
test_c2_commit_stays_hex_only
test_c3b_handoff_synthetic_entry_gives_the_gates_verdict_on_id_and_version
test_c3b_handoff_plan_matrix_refuses_a_non_ascii_digit_version
test_parse_version_id_refuses_non_ascii_digits"
for t in $GREEN_AT_A; do
  s=$(status_of "$RUNTMP/A.out" "$t"); [ "$s" = PASS ] && ok "pin (green at A and at FINAL): $t" || fail "at A $t is $s (a positive control must PASS at A)"
done
extract "$FINAL" "$RUNTMP/at-FINAL" || fail "cannot export FINAL"
( cd "$RUNTMP/at-FINAL" && $PY tests/pipeline/run_checks.py --only test_ecma_patterns ) > "$RUNTMP/F.out" 2>"$RUNTMP/F.err"
grep -q '^SUMMARY ran=[0-9]* failed=0$' "$RUNTMP/F.out" && [ "$(grep -c '^CHECK .* PASS$' "$RUNTMP/F.out")" -ge 25 ] \
  && ok "at FINAL all $(grep -c '^CHECK .* PASS$' "$RUNTMP/F.out") tests of test_ecma_patterns.py pass" || { fail "test_ecma_patterns.py is not green at FINAL"; grep -v ' PASS$' "$RUNTMP/F.out"; }

# ------------------------------------------------------------------------------------------------ --mutate
if [ "$MODE" = "--mutate" ]; then
  cat > "$RUNTMP/mut.py" <<'PYEOF'
"""Mutations of a scratch copy of the tree at FINAL (criterion 4). argv: FINAL-sha. Exit code = number of unexpected results.
Each is (id, file, [(old, new)], [check-name substrings], expect) with expect "red" (every named check must FAIL) or "green" (an
equivalent mutation: every named check must still PASS). An anchor that is not found exactly once is a hard error (a search that
finds nothing is a broken search)."""
import os
import subprocess
import sys
import tempfile

final = sys.argv[1]
SEARCH = "re.search(schema.ecma_pattern(pattern), value)"
BYPASS = 'return isinstance(value, str) and re.fullmatch(pattern, value) is not None'
BYPASS_NOIMPORT = 'return isinstance(value, str) and __import__("re").fullmatch(pattern, value) is not None'
CATCH = '''    if not isinstance(value, str):
        return False
    try:
        return re.search(schema.ecma_pattern(pattern), value) is not None
    except NotImplementedError:
        return False
'''
C1 = ["test_c1a_build_version_rejects_a_non_ascii_digit_in_the_version", "test_c1b_write_back_refuses_u_feff_in_source_archive",
      "test_c1c_write_back_accepts_u_001c_to_u_001f_and_u_0085_in_source_archive"]
M = [
    ("m1-helper-fullmatch-on-raw-pattern", "tools/pipeline/ecma.py", [(SEARCH, "re.fullmatch(pattern, value)")],
     C1 + ["test_c3_helper_verdict_equals_the_gates_for_every_pattern", "test_matches_is_the_gates_expression_search_not_fullmatch"], "red"),
    ("m2-build_version-bypasses-the-helper", "tools/pipeline/build_version.py", [("    return ecma.matches(pattern, value)", "    " + BYPASS)],
     ["test_c1a_build_version_rejects_a_non_ascii_digit_in_the_version", "test_c1a_build_version_rejects_a_non_ascii_digit_in_published_at",
      "test_c3b_sign_built_gives_the_gates_verdict_on_built_at"], "red"),
    ("m3-write_back-bypasses-the-helper", "tools/pipeline/write_back.py", [("    return ecma.matches(pattern, value)", "    " + BYPASS_NOIMPORT)],
     ["test_c1b_write_back_refuses_u_feff_in_source_archive", "test_c1c_write_back_accepts_u_001c_to_u_001f_and_u_0085_in_source_archive",
      "test_c3b_handoff_synthetic_entry_gives_the_gates_verdict_on_id_and_version", "test_c3b_handoff_plan_matrix_refuses_a_non_ascii_digit_version"], "red"),
    ("m3b-plan_pending-validator-bypasses-the-helper", "tools/pipeline/plan_pending.py",
     [('not ecma.matches(sch["pattern"], inst)', 'not __import__("re").fullmatch(sch["pattern"], inst)')],
     ["test_validator_gives_the_gates_verdict", "test_a_pending_entry_whose_source_url_holds_u_0085_is_planned_not_faulted"], "red"),
    ("m3c-plan_pending-version-id-bypasses-the-helper", "tools/pipeline/plan_pending.py",
     [("if not ecma.matches(wb._PAT_SEMVER, semver):", 'if not __import__("re").fullmatch(wb._PAT_SEMVER, semver):')],
     ["test_parse_version_id_refuses_non_ascii_digits"], "red"),
    ("m5-helper-catches-NotImplementedError", "tools/pipeline/ecma.py",
     [("    return isinstance(value, str) and " + SEARCH + " is not None\n", CATCH)],
     ["test_an_untranslatable_construct_propagates_not_implemented_error"], "red"),
    ("m7-helper-drops-the-str-check", "tools/pipeline/ecma.py", [("isinstance(value, str) and " + SEARCH, SEARCH)],
     ["test_a_non_string_value_never_matches"], "red"),
    # Documented as equivalent, NOT counted as a mutation: on the 9 anchored patterns `^...\Z` fullmatch == search.
    ("EQUIVALENT-fullmatch-of-the-translated-pattern", "tools/pipeline/ecma.py", [(SEARCH, "re.fullmatch(schema.ecma_pattern(pattern), value)")],
     C1 + ["test_c3_helper_verdict_equals_the_gates_for_every_pattern", "test_c3b_sign_built_gives_the_gates_verdict_on_built_at"], "green"),
    # Positive control for the runner: no edit, every named check must pass.
    ("CONTROL-unmutated", "tools/pipeline/ecma.py", [], C1 + ["test_c3_helper_verdict_equals_the_gates_for_every_pattern",
     "test_an_untranslatable_construct_propagates_not_implemented_error", "test_a_non_string_value_never_matches"], "green"),
]
bad = 0
for mid, rel, edits, names, expect in M:
    with tempfile.TemporaryDirectory(prefix="w094-mut-") as td:
        p = subprocess.run(f"git archive {final} | tar -x -C '{td}'", shell=True, capture_output=True, text=True)
        if p.returncode:
            print(f"MUTATION {mid}: cannot export FINAL: {p.stderr}")
            sys.exit(99)
        path = os.path.join(td, rel)
        text = open(path, encoding="utf-8").read()
        for old, new in edits:
            n = text.count(old)
            if n != 1:
                print(f"MUTATION {mid}: ANCHOR BROKEN in {rel}: found {n} times (need exactly 1): {old!r}")
                sys.exit(99)
            text = text.replace(old, new)
        open(path, "w", encoding="utf-8").write(text)
        r = subprocess.run([sys.executable, "-I", "-B", os.path.join(td, "tests", "pipeline", "run_checks.py"), "--only", *names],
                           capture_output=True, text=True, cwd=td, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        lines = [l for l in r.stdout.splitlines() if l.startswith("CHECK ")]
        st = {}
        for n in names:
            hits = [l for l in lines if n in l]
            st[n] = "MISSING" if not hits else ("FAIL" if all(h.endswith(" FAIL") for h in hits) else "PASS")
        want = "FAIL" if expect == "red" else "PASS"
        good = all(s == want for s in st.values())
        label = {"red": "RED (good)", "green": "STAYS GREEN (as documented)"}[expect] if good else ("NOT RED  <-- the check cannot fail" if expect == "red" else "WENT RED  <-- the documented equivalence is wrong")
        print(f"MUTATION {mid}: {label}  [" + "; ".join(f"{n}={s}" for n, s in st.items()) + "]", flush=True)
        if not good:
            bad += 1
print(f"MUTATION SUMMARY unexpected={bad}")
sys.exit(bad)
PYEOF
  $PY "$RUNTMP/mut.py" "$FINAL" > "$RUNTMP/mut.out" 2>&1; rc=$?
  cat "$RUNTMP/mut.out"
  [ "$rc" -eq 0 ] && ok "every mutation m1, m2, m3, m3b, m3c, m5, m7 is red, the equivalent one stays green, the control is green" || fail "mutation runner: $rc unexpected result(s)"
  # m6: the existing mutations of tests/pipeline/mutate.py (run against HEAD's committed tree) are all still red.
  $PY tests/pipeline/mutate.py --list | grep -q '^fullmatch-becomes-search	tools/pipeline/ecma.py	' && ok "m6: mutate.py's fullmatch-becomes-search mutation is adapted to ecma.py, not dropped" || fail "m6: mutate.py's fullmatch-becomes-search mutation is missing or not on ecma.py"
  if [ -n "$(git status --porcelain -- tools tests docs/pipeline)" ]; then
    fail "m6: uncommitted changes in tools/ tests/ docs/pipeline: mutate.py works on the COMMITTED tree, commit first"
  else
    $PY tests/pipeline/mutate.py > "$RUNTMP/m6.out" 2>&1; rc=$?
    grep -E '^MUTATION (SUMMARY|fullmatch-becomes-search)' "$RUNTMP/m6.out"; grep -v 'RED (good)' "$RUNTMP/m6.out" | grep -v '^MUTATION SUMMARY' | sed 's/^/      /'
    [ "$rc" -eq 0 ] && grep -q '^MUTATION SUMMARY mutations=[0-9]* not_red=0$' "$RUNTMP/m6.out" && ok "m6: tests/pipeline/mutate.py reports not_red=0" || fail "m6: mutate.py reports not-red mutations (exit $rc)"
  fi
fi

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
