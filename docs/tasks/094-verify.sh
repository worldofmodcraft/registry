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
# Review round (2026-11-06, scope extended): FINAL is the fix-round content commit. OLDFINAL is the first review's FINAL (a5710ed): the tree on
# which the F3 hygiene check must be red. E01 is the pushed head e01a0d7, whose docs/tasks/008b1-verify.sh and 008c-verify.sh are the OLD
# scripts of F1.
FINAL=eb303ed2a13700313e10cce99dd8228936354651
OLDFINAL=a5710ed0aaae5b7a547e3509363cec55beb2474b
E01=e01a0d7c08df5837ec991375f489b1417fa8d8fa
# TIP: the last commit the FINAL..TIP name-list check measures, i.e. the commit before the one that records this line. The pin commit and the
# log entries after it change only docs/tasks/094-* files and are not range-checked (101's pattern). Empty until recorded; empty FAILS.
TIP=2eaa48304ea04a4504865d1e336fe96d701b3822

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
for pin in BASE A OLDFINAL E01 FINAL TIP; do
  if pin_ok "${!pin}"; then ok "pin $pin is a full SHA and resolves (${!pin:0:7})"; else fail "pin $pin (${!pin}) is not a full SHA or does not resolve"; fi
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (a pin is unreachable: fetch the branch)"; exit "$FAILS"; }

git merge-base --is-ancestor "$BASE" "$A" && git merge-base --is-ancestor "$A" "$OLDFINAL" && git merge-base --is-ancestor "$OLDFINAL" "$E01" \
  && git merge-base --is-ancestor "$E01" "$FINAL" && git merge-base --is-ancestor "$FINAL" "$TIP" && git merge-base --is-ancestor "$TIP" HEAD \
  && ok "BASE <= A <= OLDFINAL <= E01 <= FINAL <= TIP <= HEAD" || fail "the pins are not in order BASE <= A <= OLDFINAL <= E01 <= FINAL <= TIP <= HEAD"

# F4 (part): after FINAL, up to the fixed TIP, only docs/tasks/094-* files change. A name list over every commit in the range (a file touched
# and reverted still shows), no merges, with a positive control for the matcher.
outside_094() { grep -vE '^docs/tasks/094-[A-Za-z0-9._-]+$' || true; }   # stdin: file names; prints those that are not docs/tasks/094-*
ctl=$(printf 'docs/tasks/094-verify.sh\ndocs/tasks/094-pipeline-ecma-patterns.md\ntools/pipeline/ecma.py\ndocs/tasks/008c-verify.sh\n' | outside_094 | tr '\n' ' ')
[ "$ctl" = "tools/pipeline/ecma.py docs/tasks/008c-verify.sh " ] && ok "control: the FINAL..TIP matcher flags tools/pipeline/ecma.py and docs/tasks/008c-verify.sh and passes docs/tasks/094-*" \
  || fail "control: the FINAL..TIP matcher is wrong (flagged: $ctl)"
range_names=$(git log --no-renames --name-only --format= "$FINAL..$TIP")
[ -n "$range_names" ] && ok "FINAL..TIP changes something (the range is not empty)" || fail "FINAL..TIP is empty (broken search)"
[ -z "$(git rev-list --merges "$FINAL..$TIP")" ] && ok "FINAL..TIP holds no merge commit" || fail "FINAL..TIP holds a merge commit"
out=$(printf '%s\n' "$range_names" | outside_094)
[ -z "$out" ] && ok "FINAL..TIP changes only docs/tasks/094-* files ($(printf '%s\n' "$range_names" | sort -u | wc -l) names)" || fail "FINAL..TIP touches: $(echo "$out" | tr '\n' ' ')"

# Criterion 1: commit A is tests only.
a_files=$(git diff --name-only "$A^" "$A")
[ "$a_files" = "tests/pipeline/test_ecma_patterns.py" ] && ok "commit A changes exactly tests/pipeline/test_ecma_patterns.py (tests only)" \
  || fail "commit A is not tests only: $(echo "$a_files" | tr '\n' ' ')"
[ "$(git diff --name-only "$BASE" "$A^")" = "docs/tasks/094-pipeline-ecma-patterns.md" ] && ok "BASE..A^ is only the spec copy" \
  || fail "BASE..A^ holds more than the spec copy"

# File scope (spec). handoff.py and sign_built.py are NOT in it: if either needs an edit the task stops and reports.
SCOPE_RE='^(tools/pipeline/(ecma|build_version|write_back|plan_pending)\.py|tests/pipeline/(test_ecma_patterns|test_write_back|mutate)\.py|docs/pipeline/build-pipeline\.md|docs/tasks/094-(pipeline-ecma-patterns\.md|verify\.sh)|docs/tasks/(008b1|008c)-verify\.sh)$'
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
other=$(git diff --name-only "$BASE" "$FINAL" | grep -E '^docs/tasks/.*(-verify\.sh|\.py|\.json)$' | grep -vE '^docs/tasks/(008b1|008c|094)-verify\.sh$')
[ -z "$other" ] && ok "BASE..FINAL touches no verify script (but 008b1 and 008c, F1), pin file or fixture under docs/tasks" || fail "BASE..FINAL touches: $other"
# F1: in 008b1-verify.sh and 008c-verify.sh only the mutation anchors changed. Every changed hunk between E01 (old) and FINAL (new) must
# start at a `run_mut <id>` line, the old and new hunks must name the same ids, and 008b1/008c must have exactly the expected ids.
cat > "$RUNTMP/anchors.py" <<'PYEOF'
import difflib, sys
old, new, want = open(sys.argv[1], encoding="utf-8").read().split("\n"), open(sys.argv[2], encoding="utf-8").read().split("\n"), sys.argv[3].split(",")
def ids(lines):
    return [l.split()[1] for l in lines if l.startswith("  run_mut ")]
# R2-2 (approved): 008c's real-tree hash lines may gain exactly tools/registry/schema.py and tools/pipeline/ecma.py (new mutation targets).
ALLOWED = {}
if len(sys.argv) > 4 and sys.argv[4] == "hash8c":
    for k in ("BEFORE", "AFTER"):
        a = '  %s=$(sha256sum "$MOD" "$TST" docs/tasks/008c-verify.sh contracts/artifact-naming.md | sha256sum)' % k
        ALLOWED[a] = a.replace(" | sha256sum)", " tools/registry/schema.py tools/pipeline/ecma.py | sha256sum)")
got_old, got_new, bad = [], [], []
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
    if tag == "equal":
        continue
    o, n = old[i1:i2], new[j1:j2]
    if len(o) == 1 and len(n) == 1 and ALLOWED.get(o[0]) == n[0]:
        continue
    if not (o and n and o[0].startswith("  run_mut ") and n[0].startswith("  run_mut ")):
        bad.append((tag, o[:1], n[:1]))
    got_old += ids(o); got_new += ids(n)
if bad or sorted(got_old) != sorted(want) or sorted(got_new) != sorted(want):
    print("BAD", bad, got_old, got_new); sys.exit(1)
print("ok", sorted(got_new))
PYEOF
git show "$E01:docs/tasks/008c-verify.sh" > "$RUNTMP/008c.old"; git show "$FINAL:docs/tasks/008c-verify.sh" > "$RUNTMP/008c.new"
git show "$E01:docs/tasks/008b1-verify.sh" > "$RUNTMP/008b1.old"; git show "$FINAL:docs/tasks/008b1-verify.sh" > "$RUNTMP/008b1.new"
W8C=ascii-flag-dropped,digit-translation-dropped,digit-translation-dropped-published-at,digit-translation-mangles-escaped-backslash
$PY "$RUNTMP/anchors.py" "$RUNTMP/008c.old" "$RUNTMP/008c.new" "$W8C" hash8c > "$RUNTMP/a1.out" 2>&1 && ok "008c-verify.sh: only the four mutation anchors and the two real-tree hash lines (R2-2) changed ($(cat "$RUNTMP/a1.out"))" || fail "008c-verify.sh changed outside the four mutation anchors: $(cat "$RUNTMP/a1.out")"
$PY "$RUNTMP/anchors.py" "$RUNTMP/008b1.old" "$RUNTMP/008b1.new" c17b-ecma-digits-dropped > "$RUNTMP/a2.out" 2>&1 && ok "008b1-verify.sh: only the c17b mutation anchor changed ($(cat "$RUNTMP/a2.out"))" || fail "008b1-verify.sh changed outside the c17b mutation anchor: $(cat "$RUNTMP/a2.out")"
# control: a hash line that gains anything beyond the two approved files, or an ordinary extra line, must be flagged
sed 's#tools/pipeline/ecma.py | sha256sum#tools/pipeline/ecma.py README.md | sha256sum#' "$RUNTMP/008c.new" > "$RUNTMP/008c.ctl"
$PY "$RUNTMP/anchors.py" "$RUNTMP/008c.old" "$RUNTMP/008c.ctl" "$W8C" hash8c > /dev/null 2>&1 && fail "control: the anchors check passes a hash line with an unapproved extra file" || ok "control: the anchors check flags a hash line with an unapproved extra file"
# control: one extra changed line outside any run_mut line must be flagged
{ cat "$RUNTMP/008b1.new"; echo 'echo stray'; } > "$RUNTMP/008b1.ctl"
$PY "$RUNTMP/anchors.py" "$RUNTMP/008b1.old" "$RUNTMP/008b1.ctl" c17b-ecma-digits-dropped > /dev/null 2>&1 && fail "control: the anchors-only check passes a script with a stray added line" || ok "control: the anchors-only check flags a stray added line"

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
SUITE_FLOOR=$((147 + 26))
# F3 hygiene, part 1 (sweep fix): the caller's tree may already hold __pycache__ written by OTHER scripts that ran before this one in the same
# clone (a sweep runs every closed script in one clone; several run `python3 -I` without -B). Only what THIS run leaves is counted: the state of
# tools/registry and tests/contracts (pycache directories by path; pyc files by path and mtime) is recorded before the suite and compared after.
pycache_state() {  # $1 = a tree root; one line per __pycache__ dir (path) and per file inside one (path + mtime), sorted
  find "$1/tools/registry" "$1/tests/contracts" -path '*__pycache__*' \( -type d -printf '%p d\n' -o -type f -printf '%p f %T@\n' \) 2>/dev/null | sort
}
new_entries() {  # new_entries BEFORE AFTER : the lines of AFTER that are not in BEFORE
  comm -13 <(printf '%s\n' "$1" | sort) <(printf '%s\n' "$2" | sort) | grep -v '^$'
}
PRE_STATE=$(pycache_state .)
OUT=$($PY tests/pipeline/run_checks.py 2>"$RUNTMP/suite-stderr")
PASSN=$(echo "$OUT" | grep -c '^CHECK .* PASS$')
FAILN=$(echo "$OUT" | grep -c '^CHECK .* FAIL$')
echo "$OUT" | grep '^CHECK .* FAIL$' | sed 's/^/FAIL  /'
echo "suite at HEAD: $PASSN passed, $FAILN failed; $(echo "$OUT" | grep '^SUMMARY')"
[ "$FAILN" -eq 0 ] && echo "$OUT" | grep -q '^SUMMARY ran=[0-9]* failed=0$' && ok "the pipeline suite is green at HEAD (SUMMARY failed=0)" || { fail "$FAILN suite check(s) failed"; cat "$RUNTMP/suite-stderr" >&2; }
[ "$PASSN" -ge "$SUITE_FLOOR" ] && ok "the suite ran at least $SUITE_FLOOR checks (147 + the 26 new ones): $PASSN" || fail "the suite ran only $PASSN checks (floor $SUITE_FLOOR)"
for pat in 'RedFirst.test_c1a' 'RedFirst.test_c1b' 'RedFirst.test_c1c' 'PositiveControls.test_c2' 'Equivalence.test_c3' 'NewCallers.test_c3b' 'PlanPendingValidator' 'Helper.test_'; do
  P=$(echo "$OUT" | grep -c "^CHECK ${pat}.* PASS$"); F=$(echo "$OUT" | grep -c "^CHECK ${pat}.* FAIL$")
  [ "$P" -ge 1 ] && [ "$F" -eq 0 ] && ok "$pat*: $P passing, 0 failing" || fail "$pat*: $P passing, $F failing"
done
[ "$(echo "$OUT" | grep -c '^CHECK ReviewFixes.*PASS$')" -ge 7 ] && ok "test_write_back's ReviewFixes (008c's fix-round tests) all pass" || fail "test_write_back's ReviewFixes did not all pass"

# F3 hygiene: importing tools/pipeline/ecma.py (which loads tools/registry/schema.py and tests/contracts/schema_check.py by path) must leave no
# __pycache__ in tools/registry or tests/contracts. tools/pipeline/__pycache__ is NOT counted: it is written by tests/pipeline/test_plan_pending.py,
# which runs `python3 -I` without -B (-I ignores PYTHONDONTWRITEBYTECODE); that file is outside task 094 (booked).
pycache_leaks() { find "$1/tools/registry" "$1/tests/contracts" -name __pycache__ 2>/dev/null; }   # $1 = a tree root (a whole fresh export: everything counts)
mkdir -p "$RUNTMP/hyctl/tools/registry/__pycache__" "$RUNTMP/hyctl/tests/contracts"
[ -n "$(pycache_leaks "$RUNTMP/hyctl")" ] && ok "control: the hygiene check finds a planted tools/registry/__pycache__" || fail "control: the hygiene check is blind to a planted __pycache__"
# control: an entry that exists before the run is NOT counted; a directory or file created during the run IS.
mkdir -p "$RUNTMP/hy2/tools/registry/__pycache__" "$RUNTMP/hy2/tests/contracts"
echo old > "$RUNTMP/hy2/tools/registry/__pycache__/old.pyc"
S0=$(pycache_state "$RUNTMP/hy2")
echo new > "$RUNTMP/hy2/tools/registry/__pycache__/new.pyc"; mkdir "$RUNTMP/hy2/tests/contracts/__pycache__"
N=$(new_entries "$S0" "$(pycache_state "$RUNTMP/hy2")")
[ "$(echo "$N" | wc -l)" -eq 2 ] && echo "$N" | grep -q 'registry/__pycache__/new.pyc f' && echo "$N" | grep -q 'contracts/__pycache__ d' && ! echo "$N" | grep -q 'old.pyc' \
  && ok "control: a pre-existing __pycache__ dir and pyc are not counted; a pyc and a dir created during the run are" || fail "control: the before/after comparison is wrong (new: $(echo "$N" | tr '\n' '|'))"
[ -z "$(new_entries "$S0" "$S0")" ] && ok "control: an unchanged tree has no new entries" || fail "control: an unchanged tree reports new entries"
leaks=$(new_entries "$PRE_STATE" "$(pycache_state .)")
if [ -n "$PRE_STATE" ]; then note "tools/registry or tests/contracts already held __pycache__ entries before this run (written by other scripts, not counted): $(echo "$PRE_STATE" | awk '{print $1}' | tr '\n' ' ')"; fi
[ -z "$leaks" ] && ok "this run left no new __pycache__ in tools/registry or tests/contracts" || fail "__pycache__ left behind by this run: $(echo "$leaks" | tr '\n' ' ')"
note "other __pycache__ dirs in this tree after the run (informational): $(find . -name __pycache__ -not -path './.git/*' | tr '\n' ' ')"

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
grep -q '^SUMMARY ran=[0-9]* failed=0$' "$RUNTMP/F.out" && [ "$(grep -c '^CHECK .* PASS$' "$RUNTMP/F.out")" -ge 26 ] \
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

  # F1 (review round): the closed scripts' --mutate modes. RED FIRST: the OLD scripts (blobs at E01) run on the tree at FINAL (the new code) must
  # go red, naming the anchors the removed code took with it; then the scripts at FINAL (re-anchored) must be green on the same tree.
  g1() { git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
  git clone -q --no-hardlinks "$PWD" "$RUNTMP/f1old" 2>/dev/null && ( cd "$RUNTMP/f1old" && g1 checkout -q --detach "$FINAL" \
    && cp "$RUNTMP/008c.old" docs/tasks/008c-verify.sh && cp "$RUNTMP/008b1.old" docs/tasks/008b1-verify.sh \
    && g1 commit -q -am "the old closed scripts (e01a0d7)" ) && ok "F1: scratch clone with the OLD 008b1/008c-verify.sh (blobs at E01) over the tree at FINAL" || fail "F1: cannot build the scratch clone with the old scripts"
  git clone -q --no-hardlinks "$PWD" "$RUNTMP/f1new" 2>/dev/null && ( cd "$RUNTMP/f1new" && g1 checkout -q --detach "$FINAL" ) && ok "F1: scratch clone at FINAL (the re-anchored scripts)" || fail "F1: cannot build the scratch clone at FINAL"
  ( cd "$RUNTMP/f1old" && bash docs/tasks/008c-verify.sh --mutate > "$RUNTMP/o8c.out" 2>&1; echo "rc=$?" >> "$RUNTMP/o8c.out" )
  ( cd "$RUNTMP/f1old" && bash docs/tasks/008b1-verify.sh --mutate > "$RUNTMP/o8b1.out" 2>&1; echo "rc=$?" >> "$RUNTMP/o8b1.out" )
  for id in ascii-flag-dropped digit-translation-dropped digit-translation-dropped-published-at digit-translation-mangles-escaped-backslash; do
    grep -q "^FAIL  mutation $id: anchor not found exactly once" "$RUNTMP/o8c.out" && ok "F1 red first: OLD 008c-verify.sh --mutate names the missing anchor of $id" || fail "F1 red first: OLD 008c-verify.sh --mutate does not report $id as an anchor not found"
  done
  grep -q '^SUMMARY mutate failed=4$' "$RUNTMP/o8c.out" && grep -q '^rc=4$' "$RUNTMP/o8c.out" && ok "F1 red first: OLD 008c-verify.sh --mutate: SUMMARY mutate failed=4, exit 4" || fail "F1 red first: OLD 008c-verify.sh --mutate is not exactly 4 failures: $(grep -E '^SUMMARY|^rc=' "$RUNTMP/o8c.out" | tr '\n' ' ')"
  grep -q '^FAIL  mutation c17b-ecma-digits-dropped: anchor not found exactly once' "$RUNTMP/o8b1.out" && grep -q '^SUMMARY mutate failed=1$' "$RUNTMP/o8b1.out" && grep -q '^rc=1$' "$RUNTMP/o8b1.out" \
    && ok "F1 red first: OLD 008b1-verify.sh --mutate: c17b-ecma-digits-dropped anchor not found, SUMMARY mutate failed=1, exit 1" || fail "F1 red first: OLD 008b1-verify.sh --mutate is not exactly the c17b failure: $(grep -E '^FAIL|^SUMMARY|^rc=' "$RUNTMP/o8b1.out" | tr '\n' ' ')"
  ( cd "$RUNTMP/f1new" && bash docs/tasks/008c-verify.sh --mutate > "$RUNTMP/n8c.out" 2>&1; echo "rc=$?" >> "$RUNTMP/n8c.out" )
  ( cd "$RUNTMP/f1new" && bash docs/tasks/008b1-verify.sh --mutate > "$RUNTMP/n8b1.out" 2>&1; echo "rc=$?" >> "$RUNTMP/n8b1.out" )
  for id in ascii-flag-dropped digit-translation-dropped digit-translation-dropped-published-at digit-translation-mangles-escaped-backslash; do
    grep -q "^ok    mutation $id: red -> " "$RUNTMP/n8c.out" && ok "F1 green: re-anchored 008c-verify.sh --mutate: $id is red (the property still breaks)" || fail "F1 green: re-anchored 008c-verify.sh --mutate: $id is not red"
  done
  grep -q '^SUMMARY mutate failed=0$' "$RUNTMP/n8c.out" && grep -q '^rc=0$' "$RUNTMP/n8c.out" && ok "F1 green: 008c-verify.sh --mutate at FINAL: SUMMARY mutate failed=0, exit 0" || fail "F1 green: 008c-verify.sh --mutate at FINAL: $(grep -E '^FAIL|^SUMMARY|^rc=' "$RUNTMP/n8c.out" | tr '\n' ' ')"
  grep -q '^ok    mutation c17b-ecma-digits-dropped: red -> ' "$RUNTMP/n8b1.out" && grep -q '^SUMMARY mutate failed=0$' "$RUNTMP/n8b1.out" && grep -q '^rc=0$' "$RUNTMP/n8b1.out" \
    && ok "F1 green: 008b1-verify.sh --mutate at FINAL: c17b-ecma-digits-dropped red, SUMMARY mutate failed=0, exit 0" || fail "F1 green: 008b1-verify.sh --mutate at FINAL: $(grep -E '^FAIL|^SUMMARY|^rc=' "$RUNTMP/n8b1.out" | tr '\n' ' ')"

  # F3 (review round): RED FIRST on the first review's FINAL (a5710ed), whose ecma load wrote bytecode: after the full suite its tree holds a
  # __pycache__ in tools/registry and/or tests/contracts; the tree at FINAL holds none.
  extract "$OLDFINAL" "$RUNTMP/hy-old" && ( cd "$RUNTMP/hy-old" && $PY tests/pipeline/run_checks.py > "$RUNTMP/hy-old.out" 2>&1 )
  grep -q '^SUMMARY ran=[0-9]* failed=0$' "$RUNTMP/hy-old.out" && ok "F3: the suite is green at OLDFINAL (so the leak below is not a failing run)" || fail "F3: the suite at OLDFINAL is not green"
  old_leaks=$(pycache_leaks "$RUNTMP/hy-old")
  [ -n "$old_leaks" ] && ok "F3 red first: at OLDFINAL the suite leaves __pycache__ in $(echo "$old_leaks" | sed "s#$RUNTMP/hy-old/##" | tr '\n' ' ')" || fail "F3 red first: the hygiene check is NOT red at OLDFINAL"
  extract "$FINAL" "$RUNTMP/hy-new" && ( cd "$RUNTMP/hy-new" && $PY tests/pipeline/run_checks.py > "$RUNTMP/hy-new.out" 2>&1 )
  grep -q '^SUMMARY ran=[0-9]* failed=0$' "$RUNTMP/hy-new.out" && ok "F3: the suite is green at FINAL" || fail "F3: the suite at FINAL is not green"
  [ -z "$(pycache_leaks "$RUNTMP/hy-new")" ] && ok "F3 green: at FINAL the suite leaves no __pycache__ in tools/registry or tests/contracts" || fail "F3: at FINAL the suite still leaves $(pycache_leaks "$RUNTMP/hy-new" | tr '\n' ' ')"
  # R2-1 (review round 2): the 008c mutation digit-translation-mangles-escaped-backslash must break ONLY the escaped-backslash cases (see r21.py below):
  # with the reviewer's anchor the three escaped-backslash cases fail and the plain \d, [\d.] and \. cases pass; the test is red; with those cases
  # removed from the test the mutation is NOT red; the previous round's anchor (i += 1) is still red without them.
  git show "$FINAL:docs/tasks/008c-verify.sh" | grep -qF 'i += 1 if e == "\\" else 2' && ok "R2-1: 008c-verify.sh uses the reviewer's anchor (i += 1 if e is a backslash else 2)" || fail "R2-1: 008c-verify.sh does not use the reviewer's anchor"
  cat > "$RUNTMP/r21.py" <<'PYEOF2'
"""R2-1 (review round 2): the 008c mutation digit-translation-mangles-escaped-backslash must isolate the escaped-backslash property.
argv: FINAL-sha. Prints one `R21 ...` line per result; exit code = number of unexpected results."""
import json
import os
import subprocess
import sys
import tempfile

final = sys.argv[1]
OLD = '            i += 2\n            continue\n        if in_class:'
NEW_REVIEWER = '            i += 1 if e == "\\\\" else 2\n            continue\n        if in_class:'   # the text 008c-verify.sh uses (python source: e == "\\")
NEW_OLDROUND = '            i += 1\n            continue\n        if in_class:'
TEST = "test_fix3_digit_translation_leaves_escaped_backslash_alone"
ARABIC = "٣"
CASES = [(r"^\d$", "5", True), (r"^\d$", ARABIC, False), (r"^\\d$", "\\d", True), (r"^\\d$", "5", False),
         (r"^\\\d$", "\\5", True), (r"^\\\d$", "\\" + ARABIC, False), (r"^\\\\d$", "\\\\d", True),
         (r"^[\d.]$", "5", True), (r"^[\d.]$", ".", True), (r"^[\d.]$", ARABIC, False), (r"^a\.b$", "axb", False)]
ESCAPED = {r"^\\d$", r"^\\\d$", r"^\\\\d$"}
bad = 0


def say(ok, text):
    global bad
    print(("R21 ok    " if ok else "R21 FAIL  ") + text, flush=True)
    bad += not ok


def export(td):
    p = subprocess.run(f"git archive {final} | tar -x -C '{td}'", shell=True, capture_output=True, text=True)
    if p.returncode:
        print("cannot export", p.stderr)
        sys.exit(99)


def mutate_schema(td, new):
    path = os.path.join(td, "tools", "registry", "schema.py")
    text = open(path, encoding="utf-8").read()
    if text.count(OLD) != 1:
        print(f"R21 ANCHOR BROKEN: {text.count(OLD)} occurrences")
        sys.exit(99)
    open(path, "w", encoding="utf-8").write(text.replace(OLD, new))


def drop_escaped_cases(td):
    path = os.path.join(td, "tests", "pipeline", "test_write_back.py")
    text = open(path, encoding="utf-8").read()
    start = text.index('(r"^\\\\d$", "\\\\d", True)')
    end = text.index('(r"^[\\d.]$", "5", True)')
    assert start < end and text.count(TEST) == 1
    open(path, "w", encoding="utf-8").write(text[:start] + text[end:])


def run_test(td):
    r = subprocess.run([sys.executable, "-I", "-B", os.path.join(td, "tests", "pipeline", "run_checks.py"), "--only", TEST],
                       capture_output=True, text=True, cwd=td)
    lines = [l for l in r.stdout.splitlines() if l.startswith("CHECK ") and TEST in l]
    return "MISSING" if not lines else ("FAIL" if all(l.endswith(" FAIL") for l in lines) else "PASS")


PROBE = r'''
import json, sys
sys.path.insert(0, sys.argv[1] + "/tools/pipeline")
import ecma
cases = json.loads(sys.argv[2])
print(json.dumps([[p, v, w, ecma.matches(p, v)] for p, v, w in cases]))
'''


def mismatches(td):
    r = subprocess.run([sys.executable, "-I", "-B", "-c", PROBE, td, json.dumps(CASES)], capture_output=True, text=True)
    return [(p, v) for p, v, w, got in json.loads(r.stdout) if got is not w]


with tempfile.TemporaryDirectory(prefix="w094-r21-") as td:
    export(td)
    say(mismatches(td) == [] and run_test(td) == "PASS", "control: unmutated tree, every case of the test passes and the test is PASS")
    mutate_schema(td, NEW_REVIEWER)
    mm = mismatches(td)
    say({p for p, v in mm} == ESCAPED and len(mm) == 3, f"reviewer's anchor: exactly the three want-True escaped-backslash cases fail ({[p for p, v in mm]}); `^\\d$`, `[\\d.]` and `a\\.b` still pass")
    say(run_test(td) == "FAIL", "reviewer's anchor: the test (all cases) is RED")
with tempfile.TemporaryDirectory(prefix="w094-r21-") as td:
    export(td)
    mutate_schema(td, NEW_REVIEWER)
    drop_escaped_cases(td)
    say(run_test(td) == "PASS", "reviewer's anchor with the escaped-backslash cases REMOVED from the test: NOT red (the mutation isolates exactly that property)")
with tempfile.TemporaryDirectory(prefix="w094-r21-") as td:
    export(td)
    mutate_schema(td, NEW_OLDROUND)
    drop_escaped_cases(td)
    say(run_test(td) == "FAIL", "the previous round's anchor (`i += 1`) with those cases removed stays RED: it broke every escape (the finding)")
print(f"R21 SUMMARY unexpected={bad}")
sys.exit(bad)
PYEOF2
  $PY "$RUNTMP/r21.py" "$FINAL" > "$RUNTMP/r21.out" 2>&1; rc=$?
  cat "$RUNTMP/r21.out"
  [ "$rc" -eq 0 ] && grep -q '^R21 SUMMARY unexpected=0$' "$RUNTMP/r21.out" && ok "R2-1: the mutation is red only on the escaped-backslash cases, and not red without them" || fail "R2-1: the isolation check reports $rc unexpected result(s)"

fi

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
