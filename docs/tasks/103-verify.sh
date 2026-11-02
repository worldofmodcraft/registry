#!/usr/bin/env bash
#
# 103-verify.sh -- the runnable verification artefact for task 103 (MANAGER.md Section 2c).
#
# Task 103: 089a1 renamed the two labels of 008a-verify.sh's README check, which made closed script 062-verify.sh red on
# main (AC6L.008a). This script demonstrates acceptance criteria 1-4 of docs/tasks/103-restore-008a-labels.md.
#
# Usage:  docs/tasks/103-verify.sh [NODE_MODULES_DIR]     (any cwd inside the repository)
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES) node_modules with ajv 8, for 062-verify.sh (npm ci --prefix tools/dev).
# Everything runs on COMMITTED state: blobs of the fixed SHAs below, and temporary clones of the repository (the caller's
# worktree is never modified). Only fixed SHAs are used: no TIP..HEAD checks. Needs a non-shallow clone.
# Runs 062-verify.sh whole twice (long); run it on a quiet machine (ps is logged before each heavy run).
# Exit code: the number of failed checks.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
NM="${WOM_NODE_MODULES:-$ROOT/tools/dev/node_modules}"
[ -n "${1:-}" ] && NM="$1"

BAD=4eca2511aeb19871b36e65e6bf417cb0b347f32e    # registry main after 089a1's merge: 062 is red here
ORIG=82fa56416cc46611318e2eeaeaa6f0d833e16346   # the commit 062 guards (its FINAL062); the original label strings
FIX=""                                           # task 103's 008a fix commit (full SHA; recorded after the fix commit exists)

FAILS=0
pass() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

L_OK="docs/contracts/README.md points at the pipeline doc"
L_FAIL="docs/contracts/README.md not updated"

if ! echo "$FIX" | grep -Eq '^[0-9a-f]{40}$' || ! git -C "$ROOT" cat-file -e "$FIX^{commit}" 2>/dev/null; then
    fail "AC0 FIX is not a reachable full SHA ('$FIX'): the fix commit is not recorded yet"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
fi
for p in "$BAD" "$ORIG" "$FIX"; do
    git -C "$ROOT" cat-file -e "$p^{commit}" 2>/dev/null && pass "AC0 pin $p is readable" || fail "AC0 pin $p is not readable (shallow clone?)"
done
[ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = false ] && pass "AC0 repository is not shallow" || fail "AC0 repository is shallow"
git -C "$ROOT" merge-base --is-ancestor "$BAD" "$FIX" && pass "AC0 BAD is an ancestor of FIX" || fail "AC0 BAD is not an ancestor of FIX"

blob() { git -C "$ROOT" show "$1:docs/tasks/008a-verify.sh" 2>/dev/null; }
blob "$BAD" > "$TMP/bad.sh"; blob "$ORIG" > "$TMP/orig.sh"; blob "$FIX" > "$TMP/fix.sh"
for f in bad orig fix; do [ -s "$TMP/$f.sh" ] && pass "AC0 008a-verify.sh blob at $f is non-empty" || fail "AC0 008a-verify.sh blob at $f is empty"; done

# --- AC2: label strings byte-identical to 82fa564 (positive control on ORIG, negative control on BAD)
for pair in "ok|$L_OK" "fail|$L_FAIL"; do
    fn="${pair%%|*}"; lab="${pair#*|}"
    c="$(grep -cF "$fn \"$lab\"" "$TMP/orig.sh")"; [ "$c" = 1 ] && pass "AC2 control: $fn label present exactly once at 82fa564" || fail "AC2 control: $fn label count at 82fa564 is $c, not 1"
    c="$(grep -cF "$fn \"$lab\"" "$TMP/bad.sh")";  [ "$c" = 0 ] && pass "AC2 control: $fn label absent at 4eca251 (the defect)" || fail "AC2 control: $fn label count at 4eca251 is $c, not 0"
    c="$(grep -cF "$fn \"$lab\"" "$TMP/fix.sh")";  [ "$c" = 1 ] && pass "AC2 $fn label present exactly once at FIX, byte-identical to 82fa564" || fail "AC2 $fn label count at FIX is $c, not 1"
done

# --- AC3: the README check still reads the blob at the pinned FINAL
grep -qE '^FINAL=[0-9a-f]{40}$' "$TMP/fix.sh" && pass "AC3.1 FINAL is a full-SHA pin at FIX" || fail "AC3.1 FINAL is not a full-SHA pin at FIX"
grep -F 'git show "$FINAL:docs/contracts/README.md"' "$TMP/fix.sh" | grep -qF "$L_OK" && pass "AC3.2 the check line at FIX reads git show \$FINAL:docs/contracts/README.md and carries the restored labels" || fail "AC3.2 the check line at FIX does not read the pinned blob with the restored labels"
if grep -E 'grep .*docs/contracts/README\.md( |$)' "$TMP/fix.sh" | grep -vF 'git show' | grep -q .; then fail "AC3.3 a README check at FIX reads the worktree file"; else pass "AC3.3 no README check at FIX reads the worktree file"; fi

# temp clone at FIX: 008a green; mutation of the pin reddens exactly the README check
git clone -q --no-hardlinks "$ROOT" "$TMP/fixclone" 2>/dev/null && git -C "$TMP/fixclone" checkout -q --detach "$FIX" && pass "AC3.4 temporary clone at FIX" || { fail "AC3.4 cannot clone at FIX"; echo "SUMMARY failed=$FAILS"; exit "$FAILS"; }
echo "--- ps before 008a at FIX"; ps -eo pid,etime,args | grep -E 'verify\.sh|pytest|npm' | grep -v grep || echo "(no verify/pytest/npm process)"
( cd "$TMP/fixclone" && ./docs/tasks/008a-verify.sh > "$TMP/008a.fix.out" 2>&1 ); rc=$?
[ $rc = 0 ] && pass "AC3.5 008a-verify.sh exits 0 at FIX" || { fail "AC3.5 008a-verify.sh exits $rc at FIX"; grep '^FAIL' "$TMP/008a.fix.out" | sed 's/^/    /'; }
grep -qF "ok    $L_OK" "$TMP/008a.fix.out" && pass "AC3.6 008a output at FIX prints the restored ok label" || fail "AC3.6 008a output at FIX lacks the restored ok label"
# mutation: unreadable pin must FAIL the README check (named by its restored fail label)
sed -i 's/^FINAL=[0-9a-f]\{40\}$/FINAL=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef/' "$TMP/fixclone/docs/tasks/008a-verify.sh"
( cd "$TMP/fixclone" && ./docs/tasks/008a-verify.sh > "$TMP/008a.mut.out" 2>&1 ); rcm=$?
grep -qF "FAIL  $L_FAIL" "$TMP/008a.mut.out" && pass "AC3.7 mutation (unreadable FINAL pin) turns the README check red under its restored label" || fail "AC3.7 mutation (unreadable FINAL pin) did not turn the README check red"
[ $rcm -gt 0 ] && pass "AC3.8 mutated 008a exits non-zero ($rcm)" || fail "AC3.8 mutated 008a exits 0"
# mutation 2: the check must read the pinned blob, not the worktree: damage the worktree README, check stays green
git -C "$TMP/fixclone" checkout -q -- docs/tasks/008a-verify.sh
: > "$TMP/fixclone/docs/contracts/README.md"
( cd "$TMP/fixclone" && ./docs/tasks/008a-verify.sh > "$TMP/008a.wt.out" 2>&1 )
grep -qF "ok    $L_OK" "$TMP/008a.wt.out" && pass "AC3.9 emptying the worktree README does not redden the README check (reads the pinned blob)" || fail "AC3.9 the README check followed the worktree README"

# --- AC4: scope of the fix commit: 008a-verify.sh only, and only the README-check lines
git -C "$ROOT" diff --name-only "$BAD" "$FIX" > "$TMP/scope"
bad_paths="$(grep -vE '^docs/tasks/(008a-verify\.sh|103-verify\.sh|103-restore-008a-labels\.md)$' "$TMP/scope" || true)"
[ -z "$bad_paths" ] && pass "AC4.1 BAD..FIX touches only the three declared files" || fail "AC4.1 BAD..FIX touches undeclared paths: $bad_paths"
grep -qx 'docs/tasks/062-verify.sh' "$TMP/scope" && fail "AC4.2 062-verify.sh was touched" || pass "AC4.2 062-verify.sh untouched"
git -C "$ROOT" diff -U0 "$BAD" "$FIX" -- docs/tasks/008a-verify.sh | grep -E '^[+-][^+-]' > "$TMP/chg"
[ -s "$TMP/chg" ] && pass "AC4.3 the 008a diff is non-empty (the fix exists)" || fail "AC4.3 the 008a diff is empty"
off="$(grep -vE 'contracts/README\.md|^\+# ?Task 089a1|FINAL|pin' "$TMP/chg" || true)"
[ -z "$off" ] && pass "AC4.4 every changed 008a line concerns the README check or its pin" || { fail "AC4.4 changed 008a lines outside the README check:"; echo "$off" | sed 's/^/    /'; }

# --- AC1: 062 whole, at BAD (expect AC6L.008a FAIL) and at FIX (expect exit 0 and AC6L.008a ok)
run062() { # $1 = sha, $2 = label
    local d="$TMP/c$2"
    git clone -q --no-hardlinks "$ROOT" "$d" && git -C "$d" checkout -q --detach "$1" || { fail "AC1 cannot clone at $2"; return 99; }
    echo "--- ps before 062 at $2"; ps -eo pid,etime,args | grep -E 'verify\.sh|pytest|npm' | grep -v grep || echo "(no verify/pytest/npm process)"
    ( cd "$d" && ./docs/tasks/062-verify.sh "$NM" > "$TMP/062.$2.out" 2>&1 ); return $?
}
run062 "$BAD" bad; rcb=$?
grep -E '^(FAIL|not ok|.*FAIL).*AC6L\.008a' "$TMP/062.bad.out" | sed 's/^/    /'
if grep -q 'FAIL.*AC6L\.008a' "$TMP/062.bad.out" && [ $rcb -gt 0 ]; then pass "AC1.1 062-verify.sh at 4eca251 FAILs AC6L.008a (exit $rcb) [whole script run]"; else fail "AC1.1 062 at 4eca251: AC6L.008a not red (exit $rcb)"; fi
run062 "$FIX" fix; rcf=$?
grep 'AC6L\.008a' "$TMP/062.fix.out" | sed 's/^/    /'
grep -q 'ok.*AC6L\.008a' "$TMP/062.fix.out" && ! grep -q 'FAIL.*AC6L\.008a' "$TMP/062.fix.out" && pass "AC1.2 062-verify.sh at FIX passes AC6L.008a" || fail "AC1.2 062 at FIX: AC6L.008a not ok"
[ $rcf = 0 ] && pass "AC1.3 062-verify.sh at FIX exits 0 [whole script run]" || { fail "AC1.3 062-verify.sh at FIX exits $rcf"; grep -E 'FAIL' "$TMP/062.fix.out" | sed 's/^/    /'; }

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
