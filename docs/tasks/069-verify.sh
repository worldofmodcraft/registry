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

# ==================================================================================================
else
section "mutations (temporary clone of HEAD)"
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
