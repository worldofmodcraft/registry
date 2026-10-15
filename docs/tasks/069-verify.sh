#!/usr/bin/env bash
#
# 069-verify.sh -- the runnable verification artefact for task 069 (MANAGER.md Section 2c).
#
# Task 069: closed tasks' verify scripts stay correct under concurrency and on later branches (008a, 007a, 062).
# Demonstrates acceptance criteria 1-5 of docs/tasks/069-closed-verify-maintenance.md. Criterion 6 (every closed
# script green on HEAD, and 062 green on the merge with 007b / 064) is a sequential run on a quiet machine, done by
# hand and logged; it is not repeated here.
#
# Usage:  docs/tasks/069-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (008a survives a foreign wom008a-* directory appearing in the global temp dir mid-run),
#              AC3 (007a on a later branch), AC4 (062 runs 007a), AC5 (AC6.034 allowance accepts 064's change).
#   --mutate   AC2 (a real leak inside the per-run TMPDIR reddens 008a), AC3/AC4 mutations, AC5 mutations.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES) a node_modules directory with ajv 8 (only the 062 runs need it).
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Deterministic, no network. Exit code: the number of failed checks. Run it with no other registry suite running
# (the point of AC1 is that a concurrent run no longer matters, but a measuring run should still be quiet).
# Requires: git, python3, plus everything 008a-verify.sh / 007a-verify.sh require (minisign, ...).

set -u
set -o pipefail

MUTATE=0
NM="${WOM_NODE_MODULES:-}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
BASE069="ac22c8f"            # registry origin/main when task 069 was cut: the frame of the red-first controls
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify069 -c user.email=verify069@invalid -c commit.gpgsign=false)

TMP="$(mktemp -d)" || exit 99
RACE_DIRS="$TMP/race-dirs"; : > "$RACE_DIRS"
cleanup() {
    while read -r d; do [ -n "$d" ] && rm -rf "$d"; done < "$RACE_DIRS"
    chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null
}
trap cleanup EXIT

HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
new_clone() {   # new_clone DEST REV : a fresh clone of the repository, detached at REV
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
}
if ! git -C "$ROOT" rev-parse --verify -q "$BASE069^{commit}" >/dev/null; then
    fail "P0 base $BASE069 is reachable"
    printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"; exit "$FAILURES"
fi

# A python3 shim that, the first time the 008a suite runner starts, creates a wom008a-race.* directory in the
# GLOBAL temp dir (/tmp) -- exactly what a concurrent 008a run does -- then execs the real python3.
mkdir -p "$TMP/shim"
REALPY="$(command -v python3)"
cat > "$TMP/shim/python3" <<SHIM
#!/usr/bin/env bash
case " \$* " in
  *run_checks.py*)
    if [ ! -e "$TMP/shim.mark" ]; then
      : > "$TMP/shim.mark"
      d=\$(mktemp -d /tmp/wom008a-race.XXXXXX) && echo "\$d" >> "$RACE_DIRS"
    fi ;;
esac
exec "$REALPY" "\$@"
SHIM
chmod +x "$TMP/shim/python3"

# run_008a_raced DIR OUT : run DIR's 008a-verify.sh with the race staged exactly once; echoes its exit code
run_008a_raced() {
    rm -f "$TMP/shim.mark"
    ( cd "$1" && PATH="$TMP/shim:$PATH" bash docs/tasks/008a-verify.sh ) > "$2" 2>&1
    echo $?
}

# --- AC5 machinery: 062-verify.sh's own helper (its c33 command) judges variants of 034-verify.sh ---------
MERGE10="3c94cf2"            # registry PR #10, the merge of task 007a
mk_later() {   # mk_later DEST : HEAD plus two new source files under tools/registry (007b's shape); origin/main = the 069 base
    new_clone "$1" "$HEADREV" || return 1
    git -C "$1" update-ref refs/remotes/origin/main "$BASE069"
    git -C "$1" checkout -q -b later-007b
    echo "# probe one" > "$1/tools/registry/probe_one.py"; echo "# probe two" > "$1/tools/registry/probe_two.py"
    git -C "$1" add tools/registry/probe_one.py tools/registry/probe_two.py
    git -C "$1" "${GITID[@]}" commit -q -m "later branch adds two registry source files"
}
run007a() { ( cd "$1" && bash docs/tasks/007a-verify.sh ) > "$2" 2>&1; echo $?; }
BASE062="e009ef0"            # registry origin/main when task 062 was cut; AC6.034 compares against it
# extract_helper CLONE : the helper.py that CLONE's 062-verify.sh writes out (the heredoc between 'PYH' markers)
extract_helper() {
    sed -n "/^cat > \"\$TMP\/helper.py\" <<'PYH'\$/,/^PYH\$/p" "$1/docs/tasks/062-verify.sh" | sed '1d;$d' > "$TMP/helper062.py"
}
# gen034 OUT [--064] [OLD NEW]... : 034-verify.sh as of BASE062, with task 064's C3.3 re-pin applied if --064 is given,
# then each OLD replaced (exactly once) by NEW. Exit 2 when a replacement does not apply.
gen034() {
    git -C "$ROOT" show "$BASE062:docs/tasks/034-verify.sh" > "$1.base" || return 2
    python3 -I - "$@" <<'PY'
import sys
out = sys.argv[1]; args = sys.argv[2:]
s = open(out + ".base").read()
if args and args[0] == "--064":
    args = args[1:]
    old = '    \'re\\.search(schema\\["pattern"\\], instance)\' "$CHECK_FILE"\n'
    new = ('    \'re\\.search(_ecma_pattern(schema\\["pattern"\\]), instance)\' "$CHECK_FILE"\n'
           '# Re-pinned by task 064 (successor of the original text \'re.search(schema["pattern"], instance)\', as task 067 re-pinned\n'
           '# 032 N5b): same intent -- search semantics, the schema\'s pattern, the instance -- now with ECMA-262 end-of-input\n'
           '# (`$` rewritten to \\Z by _ecma_pattern) and ECMA escapes translated explicitly (amendment 1). re.fullmatch stays forbidden (C3.4, unedited).\n')
    assert s.count(old) == 1, "C3.3 call text not found exactly once in the base 034-verify.sh"
    s = s.replace(old, new)
for i in range(0, len(args), 2):
    if s.count(args[i]) != 1:
        print("MUTATION DID NOT APPLY: %r" % args[i][:60]); sys.exit(2)
    s = s.replace(args[i], args[i + 1])
open(out, "w").write(s)
PY
}
# c33_judge FILE : run the helper's c33 on the diff of FILE against the base 034-verify.sh; prints its output, returns its rc
c33_judge() {
    git -C "$ROOT" show "$BASE062:docs/tasks/034-verify.sh" > "$TMP/034.base"
    git diff --no-index -U0 -- "$TMP/034.base" "$1" > "$TMP/034.diff"
    python3 -I "$TMP/helper062.py" c33 "$TMP/034.diff" > "$TMP/c33.out" 2>&1; local rc=$?
    sed 's/^/    /' "$TMP/c33.out" | cut -c1-200
    return $rc
}
# c33_expect_red LABEL FILE : must exit non-zero AND say FAILED (a crash of the helper is not a red verdict)
c33_expect_red() {
    local rc; c33_judge "$2" > "$TMP/judge.txt"; rc=$?
    if [ "$rc" != 0 ] && grep -q 'FAILED:' "$TMP/judge.txt"; then pass "$1 is rejected: $(grep -m1 'FAILED:' "$TMP/judge.txt" | sed 's/^ *//' | cut -c1-110)"
    else fail "$1 was not rejected by a FAILED verdict (rc $rc)"; fi
}

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC1 -- 008a-verify.sh does not count other people's wom008a-* directories"
new_clone "$TMP/base" "$BASE069" || fail "AC1.0 cannot clone $BASE069"
new_clone "$TMP/head" "$HEADREV" || fail "AC1.0 cannot clone HEAD"
# positive control: the OLD script (task 069's base) is red when a foreign directory appears mid-run
n0=$(wc -l < "$RACE_DIRS")
rc=$(run_008a_raced "$TMP/base" "$TMP/b.out"); n1=$(wc -l < "$RACE_DIRS")
if [ $((n1 - n0)) = 1 ]; then pass "AC1.1 the race was staged exactly once against the base script"; else fail "AC1.1 the race was staged $((n1 - n0)) time(s), expected 1"; fi
if [ "$rc" != 0 ] && grep -q '^FAIL  suite left' "$TMP/b.out"; then
    pass "AC1.2 base $BASE069: a foreign wom008a-* directory turns the temp-dir check red: $(grep '^FAIL  suite left' "$TMP/b.out" | head -n1)"
else fail "AC1.2 base $BASE069: expected the temp-dir check red, got exit $rc and $(grep -c '^FAIL' "$TMP/b.out") FAIL line(s)"; fi
# the measured property: HEAD's script stays green under the same hostile event
n0=$(wc -l < "$RACE_DIRS")
rc=$(run_008a_raced "$TMP/head" "$TMP/h.out"); n1=$(wc -l < "$RACE_DIRS")
if [ $((n1 - n0)) = 1 ]; then pass "AC1.3 the race was staged exactly once against HEAD's script"; else fail "AC1.3 the race was staged $((n1 - n0)) time(s), expected 1"; fi
if [ "$rc" = 0 ]; then pass "AC1.4 HEAD: 008a-verify.sh exits 0 while a foreign wom008a-* directory appears in the global temp dir"
else fail "AC1.4 HEAD: 008a-verify.sh exit $rc under the race; failing: $(grep '^FAIL' "$TMP/h.out" | head -n3 | tr '\n' '|')"; fi
grep -q '^ok    no wom008a-\* temp dirs left behind by the suite' "$TMP/h.out" && pass "AC1.5 HEAD: the temp-dir check itself ran and passed" || fail "AC1.5 HEAD: the temp-dir check did not report ok"

# --------------------------------------------------------------------------------------------------
section "AC3 -- 007a-verify.sh measures 007a's own pinned range, so it is green on a later branch"
lb=$(sed -n 's/^BASE=\([0-9a-f]\{7,\}\).*/\1/p' "$ROOT/docs/tasks/007a-verify.sh" | head -n1)
lf=$(sed -n 's/^FINAL=\([0-9a-f]\{7,\}\).*/\1/p' "$ROOT/docs/tasks/007a-verify.sh" | head -n1)
if [ -z "$lb" ] || [ -z "$lf" ]; then fail "AC3.0 cannot read BASE/FINAL from 007a-verify.sh (a search that finds nothing is broken)"
else
    [ "$(git -C "$ROOT" rev-parse "$lf^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$MERGE10^2")" ] && pass "AC3.1 FINAL=$lf is the last commit of PR #10 (git rev-parse $MERGE10^2)" || fail "AC3.1 FINAL=$lf is not $MERGE10^2"
    [ "$(git -C "$ROOT" rev-parse "$lb^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" merge-base "$MERGE10^1" "$MERGE10^2")" ] && pass "AC3.2 BASE=$lb is PR #10's fork point (git merge-base $MERGE10^1 $MERGE10^2)" || fail "AC3.2 BASE=$lb is not the fork point of PR #10"
fi
mk_later "$TMP/later" || fail "AC3.0 cannot build the later branch"
git -C "$TMP/later" show "$BASE069:docs/tasks/007a-verify.sh" > "$TMP/old007a.sh"
cp "$TMP/old007a.sh" "$TMP/later/docs/tasks/007a-verify.sh"
rc=$(run007a "$TMP/later" "$TMP/old007a.out")
if [ "$rc" != 0 ] && grep -q '^FAIL  size:' "$TMP/old007a.out" && grep -q '^FAIL  files outside the declared scope' "$TMP/old007a.out"; then
    pass "AC3.3 red first: the OLD 007a-verify.sh on a branch adding two tools/registry files fails size and scope (exit $rc)"
else fail "AC3.3 the old script was not red on the later branch as expected (exit $rc)"; fi
git -C "$TMP/later" checkout -q -- docs/tasks/007a-verify.sh
rc=$(run007a "$TMP/later" "$TMP/new007a.out")
if [ "$rc" = 0 ]; then pass "AC3.4 HEAD's 007a-verify.sh exits 0 on the later branch"
else fail "AC3.4 HEAD's 007a-verify.sh exit $rc on the later branch; failing: $(grep '^FAIL' "$TMP/new007a.out" | head -n3 | tr '\n' '|')"; fi

# --------------------------------------------------------------------------------------------------
section "AC4 -- 062-verify.sh runs 007a on HEAD and on a later branch"
if [ -z "$NM" ] || [ ! -d "$NM/ajv" ]; then fail "AC4.0 a node_modules directory with ajv is required to run 062-verify.sh: pass NODE_MODULES_DIR"
else
    new_clone "$TMP/h062" "$HEADREV" || fail "AC4.0 cannot clone HEAD"
    ( cd "$TMP/h062" && bash docs/tasks/062-verify.sh "$NM" ) > "$TMP/062.out" 2>&1; rc=$?
    grep -E '^(PASS|FAIL)  AC3\.(head|later)\.007a' "$TMP/062.out" | cut -c1-110
    grep -q '^PASS  AC3.head.007a' "$TMP/062.out" && pass "AC4.1 062-verify.sh reports 007a green on HEAD" || fail "AC4.1 062-verify.sh has no passing AC3.head.007a line"
    grep -q '^PASS  AC3.later.007a' "$TMP/062.out" && pass "AC4.2 062-verify.sh reports 007a green on a later branch" || fail "AC4.2 062-verify.sh has no passing AC3.later.007a line"
    [ "$rc" = 0 ] && pass "AC4.3 062-verify.sh exits 0 on HEAD" || fail "AC4.3 062-verify.sh exit $rc on HEAD: $(grep '^FAIL' "$TMP/062.out" | head -n3 | tr '\n' '|')"
fi

# --------------------------------------------------------------------------------------------------
section "AC5 -- 062's AC6.034 accepts task 064's C3.3 re-pin and nothing else"
extract_helper "$TMP/head"
if [ ! -s "$TMP/helper062.py" ]; then fail "AC5.0 cannot extract helper.py from 062-verify.sh (a search that finds nothing is broken)"
else
    gen034 "$TMP/034.untouched" || fail "AC5.0 cannot build the untouched variant"
    gen034 "$TMP/034.064" --064 || fail "AC5.0 cannot build the 064 variant"
    c33_judge "$TMP/034.untouched" > "$TMP/judge.txt"; rc=$?; cat "$TMP/judge.txt"
    [ $rc = 0 ] && grep -q 'untouched' "$TMP/judge.txt" && pass "AC5.1 an untouched 034-verify.sh is accepted" || fail "AC5.1 an untouched 034-verify.sh was not accepted (rc $rc)"
    c33_judge "$TMP/034.064" > "$TMP/judge.txt"; rc=$?; cat "$TMP/judge.txt"
    [ $rc = 0 ] && grep -q 'only task 064' "$TMP/judge.txt" && pass "AC5.2 034-verify.sh with task 064's C3.3 re-pin applied is accepted" || fail "AC5.2 task 064's re-pin was not accepted (rc $rc)"
    # the real thing, when the branch is reachable here (it is deleted after 064 merges; then AC5.2 above is the evidence)
    if git -C "$ROOT" cat-file -e origin/task/064-schema-check-end-anchor:docs/tasks/034-verify.sh 2>/dev/null; then
        git -C "$ROOT" show origin/task/064-schema-check-end-anchor:docs/tasks/034-verify.sh > "$TMP/034.real"
        c33_judge "$TMP/034.real" > "$TMP/judge.txt"; rc=$?; cat "$TMP/judge.txt"
        [ $rc = 0 ] && grep -q 'only task 064' "$TMP/judge.txt" && pass "AC5.3 the actual 034-verify.sh on origin/task/064-schema-check-end-anchor ($(git -C "$ROOT" rev-parse --short origin/task/064-schema-check-end-anchor)) is accepted" || fail "AC5.3 the actual 064 branch's 034-verify.sh is not accepted (rc $rc)"
    else
        echo "  note: origin/task/064-schema-check-end-anchor is not available in this clone; AC5.3 (the real branch file) not evaluated, AC5.2 is the evidence"
    fi
fi

# ==================================================================================================
else
section "AC5 mutations -- anything beyond 064's C3.3 re-pin is rejected"
new_clone "$TMP/m5" "$HEADREV" || fail "AC5.m0 cannot clone HEAD"
extract_helper "$TMP/m5"
if [ ! -s "$TMP/helper062.py" ]; then fail "AC5.m0 cannot extract helper.py from 062-verify.sh"
else
    gen034 "$TMP/034.a" --064 "grep -q 're\\.fullmatch(' " "grep -q 're\\.fullmatchX(' " && c33_expect_red "AC5.m1 064's change plus an edit to C3.4 (its grep pattern)" "$TMP/034.a" || fail "AC5.m1 variant did not build"
    gen034 "$TMP/034.b" --064 "C4.1 TRAVERSAL_PATHS contains" "C4.1 TRAVERSAL_PATHS holds" && c33_expect_red "AC5.m2 064's change plus an edit to an unrelated line (C4.1)" "$TMP/034.b" || fail "AC5.m2 variant did not build"
    gen034 "$TMP/034.c" "grep -q 're\\.fullmatch(' " "grep -q 're\\.fullmatchX(' " && c33_expect_red "AC5.m3 an edit to C3.4 alone (no 064 change)" "$TMP/034.c" || fail "AC5.m3 variant did not build"
    gen034 "$TMP/034.d" "C4.1 TRAVERSAL_PATHS contains" "C4.1 TRAVERSAL_PATHS holds" && c33_expect_red "AC5.m4 an unrelated edit alone" "$TMP/034.d" || fail "AC5.m4 variant did not build"
    gen034 "$TMP/034.e" --064 're\.search(_ecma_pattern(schema\["pattern"\]), instance)' 're\.fullmatch(_ecma_pattern(schema\["pattern"\]), instance)' && c33_expect_red "AC5.m5 the re-pin weakened to re.fullmatch" "$TMP/034.e" || fail "AC5.m5 variant did not build"
    gen034 "$TMP/034.f" --064 're.fullmatch stays forbidden (C3.4, unedited).' 're.fullmatch stays forbidden (C3.4, unedited).
exit 0' && c33_expect_red "AC5.m6 a code line smuggled in after the comment" "$TMP/034.f" || fail "AC5.m6 variant did not build"
    gen034 "$TMP/034.g" --064 'Re-pinned by task 064' 'Re-pinned by somebody' && c33_expect_red "AC5.m7 the comment no longer names task 064" "$TMP/034.g" || fail "AC5.m7 variant did not build"
fi

# --------------------------------------------------------------------------------------------------
section "AC3 mutations -- the pinned-range checks can fail"
mk_later "$TMP/m3" || fail "AC3.m0 cannot build the later branch"
S=docs/tasks/007a-verify.sh
cp "$TMP/m3/$S" "$TMP/007a.orig"
mut007a() {   # mut007a OLD NEW LABEL EXPECT_REGEX : apply one textual mutation to the clone's 007a script, run it, demand red
    if [ "$(grep -cF -- "$1" "$TMP/m3/$S")" != 1 ]; then fail "$3: the mutation did not apply (pattern not found exactly once)"; return; fi
    python3 -I - "$TMP/m3/$S" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
open(p, "w").write(s.replace(old, new, 1))
PY
    local rc; rc=$(run007a "$TMP/m3" "$TMP/mut.out")
    if [ "$rc" != 0 ] && grep -Eq "$4" "$TMP/mut.out"; then pass "$3 turns red: exit $rc, $(grep -E "$4" "$TMP/mut.out" | head -n1)"
    else fail "$3 stayed green or missed /$4/: exit $rc"; fi
    cp "$TMP/007a.orig" "$TMP/m3/$S"
}
mut007a 'FINAL=aaf4260' 'FINAL=HEAD' "AC3.m1 range widened to HEAD (the later branch's two extra files come into range)" '^FAIL  (size:|files outside)'
mut007a 'FINAL=aaf4260' 'FINAL=deadbee' "AC3.m2 unreachable FINAL pin must FAIL, never skip" '^FAIL  pinned commit deadbee'
mut007a 'BASE=e009ef0' 'BASE=deadbee' "AC3.m3 unreachable BASE pin must FAIL, never skip" '^FAIL  pinned commit deadbee'
mut007a 'tests/registry/|' '' "AC3.m4 declared-scope regex loses tests/registry/" '^FAIL  files outside the declared scope'
rc=$(run007a "$TMP/m3" "$TMP/mut.out"); [ "$rc" = 0 ] && pass "AC3.m5 restored: exit 0 on the later branch" || fail "AC3.m5 restored but exit $rc"

section "AC4 -- 062-verify.sh --mutate carries the 007a mutations"
if [ -z "$NM" ] || [ ! -d "$NM/ajv" ]; then fail "AC4.0 a node_modules directory with ajv is required to run 062-verify.sh --mutate"
else
    new_clone "$TMP/m062" "$HEADREV" || fail "AC4.0 cannot clone HEAD"
    ( cd "$TMP/m062" && bash docs/tasks/062-verify.sh --mutate "$NM" ) > "$TMP/062m.out" 2>&1; rc=$?
    grep -E '^(PASS|FAIL)  AC4\.007a' "$TMP/062m.out" | cut -c1-120
    for k in drop-path bad-pin; do
        grep -q "^PASS  AC4.007a.$k" "$TMP/062m.out" && pass "AC4.m.$k 062 --mutate shows the 007a $k mutation red" || fail "AC4.m.$k 062 --mutate has no passing AC4.007a.$k line"
    done
    grep -q '^PASS  AC4.007a restored' "$TMP/062m.out" && pass "AC4.m.restored 062 --mutate shows 007a green after restore" || fail "AC4.m.restored no passing AC4.007a restored line"
    [ "$rc" = 0 ] && pass "AC4.m.exit 062-verify.sh --mutate exits 0" || fail "AC4.m.exit 062-verify.sh --mutate exit $rc: $(grep '^FAIL' "$TMP/062m.out" | head -n3 | tr '\n' '|')"
fi

section "AC2 -- the leak check still bites: a test that really leaks a wom008a-* dir reddens 008a-verify.sh"
new_clone "$TMP/m" "$HEADREV" || fail "AC2.0 cannot clone HEAD"
H=tests/pipeline/helpers.py
if [ "$(grep -c 'shutil.rmtree(cls.tmp, ignore_errors=True)' "$TMP/m/$H")" = 1 ]; then
    # tearDownClass stops removing its per-class temp dir: every test class now leaks one wom008a-* directory
    sed -i 's/shutil.rmtree(cls.tmp, ignore_errors=True)/pass/' "$TMP/m/$H"
    git -C "$TMP/m" diff --stat | tail -n1
    ( cd "$TMP/m" && bash docs/tasks/008a-verify.sh ) > "$TMP/leak.out" 2>&1; rc=$?
    if [ "$rc" != 0 ] && grep -q '^FAIL  suite left [1-9][0-9]* wom008a-\* temp dir(s)' "$TMP/leak.out"; then
        pass "AC2.1 a leaking test class turns the check red: exit $rc, $(grep '^FAIL  suite left' "$TMP/leak.out" | head -n1)"
    else fail "AC2.1 a real leak did NOT redden the temp-dir check: exit $rc, $(grep -c '^FAIL' "$TMP/leak.out") FAIL line(s)"; fi
else fail "AC2.0 the mutation did not apply: tearDownClass cleanup line not found exactly once (a mutation that changes nothing proves nothing)"; fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
