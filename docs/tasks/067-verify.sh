#!/usr/bin/env bash
#
# 067-verify.sh -- the runnable verification artefact for task 067 (MANAGER.md Section 2c).
#
# Task 067: 032-verify.sh check N5b pins the README sentence as task 007a rewrote it. Demonstrates AC1-AC5 of
# docs/tasks/067-repin-032-n5b.md.
#
# Usage:  docs/tasks/067-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (red at the base), AC2 (only N5b changed, pattern not loosened), AC3 (032 + 062 green at HEAD),
#              AC5 (file scope).
#   --mutate   AC4: delete the sentence from docs/contracts/README.md in a temporary clone -> N5b red; restore -> green.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES) a node_modules directory containing ajv 8, needed by 062-verify.sh.
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Deterministic, no network. Exit code: the number of failed checks. Output has no timestamps or temp paths.
# Requires: git, python3, node, plus everything 032-verify.sh and 062-verify.sh require.

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
BASE="3c94cf2"               # registry origin/main when task 067 was cut: the frame of AC1
SENTENCE='None of the three tasks implements checking logic'
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

if ! git -C "$ROOT" rev-parse --verify -q "$BASE^{commit}" >/dev/null; then
    fail "P0 base $BASE is reachable"
    exit "$FAILURES"
fi
HEADSHA="$(git -C "$ROOT" rev-parse HEAD)"
git clone -q --no-hardlinks "$ROOT" "$TMP/head" 2>/dev/null || exit 99
git -C "$TMP/head" checkout -q --detach "$HEADSHA" || exit 99
git clone -q --no-hardlinks "$ROOT" "$TMP/base" 2>/dev/null || exit 99
git -C "$TMP/base" checkout -q --detach "$BASE" || exit 99

# n5b_status DIR -> "PASS  N5b" or "FAIL  N5b" as reported by 032-verify.sh run inside DIR
n5b_status() { ( cd "$1" && bash docs/tasks/032-verify.sh 2>&1 ) | grep -E '^(PASS|FAIL)  N5b ' | cut -c1-9; }
# run032 DIR -> 032-verify.sh exit code
run032() { ( cd "$1" && bash docs/tasks/032-verify.sh >/dev/null 2>&1 ); echo $?; }

section "AC1 -- red first: at the base the unchanged 032-verify.sh fails N5b"
s=$(n5b_status "$TMP/base")
if [ "$s" = "FAIL  N5b" ]; then pass "AC1.1 base $BASE: N5b reports FAIL"; else fail "AC1.1 base $BASE: N5b status was '$s', expected FAIL"; fi
if [ "$(run032 "$TMP/base")" != 0 ]; then pass "AC1.2 base $BASE: 032-verify.sh exits non-zero"; else fail "AC1.2 base: 032-verify.sh unexpectedly exits 0"; fi

section "AC2 -- only N5b's pattern changed, and it still guards the claim"
D=$(git -C "$TMP/head" diff -U0 "$BASE" HEAD -- docs/tasks/032-verify.sh | grep -E '^[+-][^+-]')
DM=$(printf '%s\n' "$D" | grep -E '^-')
DP=$(printf '%s\n' "$D" | grep -E '^\+')
nchg=$(printf '%s\n' "$D" | grep -c .)
if [ "$nchg" = 4 ]; then pass "AC2.1 exactly 4 changed lines (2 removed, 2 added) in 032-verify.sh"; else fail "AC2.1 changed line count is $nchg, expected 4"; fi
if printf '%s\n' "$DM" | grep -q 'N5b' && printf '%s\n' "$DM" | grep -qF "in any of the three tasks"; then
    pass "AC2.2 the removed lines are N5b's call and its old pattern"
else fail "AC2.2 removed lines are not N5b's call and old pattern"; fi
if printf '%s\n' "$DP" | grep -q 'N5b' && printf '%s\n' "$DP" | grep -qF "'$SENTENCE'"; then
    pass "AC2.3 the added pattern is the full sentence '$SENTENCE'"
else fail "AC2.3 added lines do not carry the full sentence as pattern"; fi
if git -C "$TMP/head" diff --quiet "$BASE" HEAD -- docs/contracts/README.md; then
    pass "AC2.4 docs/contracts/README.md is untouched (the old phrase was not brought back)"
else fail "AC2.4 docs/contracts/README.md was modified"; fi
if grep -qF "$SENTENCE" "$TMP/head/docs/contracts/README.md"; then pass "AC2.5 the current README states the sentence"; else fail "AC2.5 the README lacks the sentence"; fi

section "AC3 -- 032-verify.sh and 062-verify.sh pass at HEAD"
rc=$(run032 "$TMP/head")
if [ "$rc" = 0 ]; then pass "AC3.1 032-verify.sh exits 0 at HEAD"; else fail "AC3.1 032-verify.sh exits $rc at HEAD"; fi
if [ -z "$NM" ]; then
    fail "AC3.2 062-verify.sh needs ajv: pass NODE_MODULES_DIR (a missing ajv is a failure, never a skip)"
else
    ( cd "$TMP/head" && bash docs/tasks/062-verify.sh "$NM" >/dev/null 2>&1 ); rc=$?
    if [ "$rc" = 0 ]; then pass "AC3.2 062-verify.sh exits 0 at HEAD"; else fail "AC3.2 062-verify.sh exits $rc at HEAD"; fi
fi

section "AC5 -- file scope: only the three declared files differ from the base"
extra=$(git -C "$TMP/head" diff --name-only "$BASE" HEAD | grep -vxE 'docs/tasks/032-verify\.sh|docs/tasks/067-repin-032-n5b\.md|docs/tasks/067-verify\.sh')
if [ -z "$extra" ]; then pass "AC5.1 changed files are within 032-verify.sh, the 067 log, 067-verify.sh"; else fail "AC5.1 out-of-scope files changed: $(printf '%s' "$extra" | tr '\n' ' ')"; fi
if [ -x "$ROOT/docs/tasks/067-verify.sh" ]; then pass "AC5.2 067-verify.sh is executable"; else fail "AC5.2 067-verify.sh is not executable"; fi

if [ "$MUTATE" = 1 ]; then
    section "AC4 -- mutations in a temporary clone"
    M="$TMP/head"; R="$M/docs/contracts/README.md"
    if [ "$(n5b_status "$M")" = "PASS  N5b" ]; then pass "AC4.0 control: N5b green before mutating"; else fail "AC4.0 control: N5b not green before mutating"; fi
    cp "$R" "$TMP/README.orig"
    python3 -I - "$R" "$SENTENCE" <<'PY'
import sys
p, s = sys.argv[1], sys.argv[2]
t = open(p).read()
assert t.count(s) == 1
open(p, "w").write(t.replace(s, ""))
PY
    if [ "$(n5b_status "$M")" = "FAIL  N5b" ]; then pass "AC4.1 sentence deleted -> N5b red"; else fail "AC4.1 sentence deleted but N5b not red"; fi
    # looseness guard: with the sentence gone, the bare words 'three tasks' elsewhere must not satisfy N5b
    printf '\nThese three tasks are mentioned here.\n' >> "$R"
    if [ "$(n5b_status "$M")" = "FAIL  N5b" ]; then pass "AC4.2 only the bare words 'three tasks' present -> N5b still red (pattern not loose)"; else fail "AC4.2 bare 'three tasks' satisfied N5b: pattern too loose"; fi
    cp "$TMP/README.orig" "$R"
    if [ "$(n5b_status "$M")" = "PASS  N5b" ]; then pass "AC4.3 sentence restored -> N5b green"; else fail "AC4.3 restored but N5b not green"; fi
fi

printf '\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
