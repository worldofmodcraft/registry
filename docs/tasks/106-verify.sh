#!/usr/bin/env bash
#
# 106-verify.sh -- the runnable verification artefact for task 106 (MANAGER.md Section 2c).
#
# Task 106: the quiet-wait predicate of 089a1-verify.sh (others) and 089a2-verify.sh (others_list) counted their own parent
# 039a-verify.sh as "another verify run" and deadlocked for 6 h. Both now exclude this process, its descendants and its ancestors
# (the shape of 089e-verify.sh others()). Demonstrates acceptance criteria 1-3 of docs/tasks/106-quiet-wait-ancestors.md.
#
# Usage:  docs/tasks/106-verify.sh        (any cwd inside the repository)
#   AC1  RED FIRST: the predicate extracted from each OLD script (registry main 2939bef), run as a child of a stub parent whose
#        command line contains docs/tasks/zz-verify.sh, lists that parent (not quiet); the NEW one (PIN_FIX) lists neither the
#        stub parent nor this script (quiet w.r.t. ancestors).
#   AC2  control: an unrelated sibling process docs/tasks/yy-verify.sh is still listed by the NEW predicate (not quiet).
#   AC3  diff of each script OLD..NEW is limited to the predicate function.
# Reads the scripts as blobs of fixed SHAs; the working tree is never modified. Network: none. Exit code: number of failed checks.
# Requires: git, bash, awk, ps, sleep.

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1
OLDREF=2939befe157ea9e428ee4338d269f97c71eb23de
PIN_FIX="f10a00ae8dc14faf35b5ad82b5b6109000b3510f"   # the commit that fixes the two predicates (40 hex), set in the commit that records the fix

FAILS=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

ROOT="$(git rev-parse --show-toplevel)" || { echo "FAIL not inside a git repository"; exit 1; }
G() { git -C "$ROOT" "$@"; }
TMP="$(mktemp -d)"; STUBPID=""; SIBPID=""
cleanup() { [ -n "$SIBPID" ] && kill "$SIBPID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

[[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]] || fail "AC0 the fix commit is not pinned yet (PIN_FIX='$PIN_FIX'): the NEW scripts cannot be read"
for s in 089a1 089a2; do
    G show "$OLDREF:docs/tasks/$s-verify.sh" > "$TMP/$s.old" 2>/dev/null || fail "AC0 cannot read $s-verify.sh at OLD $OLDREF"
    if [[ "$PIN_FIX" =~ ^[0-9a-f]{40}$ ]]; then G show "$PIN_FIX:docs/tasks/$s-verify.sh" > "$TMP/$s.new" 2>/dev/null || fail "AC0 cannot read $s-verify.sh at $PIN_FIX"
    else : > "$TMP/$s.new"; fi
done

# extract FILE FUNC : print the definition of FUNC (a one-line definition ending in '; }', or a block up to a line '}')
extract() {
    awk -v fn="$2" '
        !on && $0 ~ ("^" fn "\\(\\) \\{") { on = 1; print; if ($0 ~ /; \}[[:space:]]*$/) exit; next }
        on { print; if ($0 ~ /^\}[[:space:]]*$/) exit }' "$1"
}
# run_pred FILE FUNC OUT : a stub parent 'bash .../docs/tasks/zz-verify.sh' runs a child bash that defines FUNC and calls it
mkdir -p "$TMP/docs/tasks"
cat > "$TMP/docs/tasks/zz-verify.sh" <<'STUB'
#!/usr/bin/env bash
# stub parent: runs the child (not exec'd, so this process stays an ancestor)
bash -c 'source "$1"; "$2"' _ "$1" "$2" > "$3" 2>&1
STUB
run_pred() {   # run_pred SRC FUNC OUT
    local f="$TMP/pred.$$.$RANDOM.sh"
    extract "$1" "$2" > "$f"
    [ -s "$f" ] || { echo "EXTRACT-EMPTY" > "$3"; return; }
    bash "$TMP/docs/tasks/zz-verify.sh" "$f" "$2" "$3"
}

declare -A FN=([089a1]=others [089a2]=others_list)
for s in 089a1 089a2; do
    fn="${FN[$s]}"
    run_pred "$TMP/$s.old" "$fn" "$TMP/$s.old.out"
    if grep -Eq 'docs/tasks/zz-verify\.sh' "$TMP/$s.old.out" && ! grep -q EXTRACT-EMPTY "$TMP/$s.old.out"; then pass "AC1 OLD $s $fn: the ancestor zz-verify.sh counts as another run (not quiet; the deadlock)"
    else fail "AC1 OLD $s $fn: expected the ancestor zz-verify.sh to be listed, got: $(head -n3 "$TMP/$s.old.out" | cut -c1-120 | tr '\n' '|')"; fi
    run_pred "$TMP/$s.new" "$fn" "$TMP/$s.new.out"
    if grep -q EXTRACT-EMPTY "$TMP/$s.new.out"; then fail "AC1 NEW $s $fn: function not found in the NEW script"
    elif grep -Eq 'zz-verify\.sh|106-verify\.sh' "$TMP/$s.new.out"; then fail "AC1 NEW $s $fn: still lists an ancestor: $(grep -E 'zz-verify|106-verify' "$TMP/$s.new.out" | head -n2 | cut -c1-120 | tr '\n' '|')"
    else pass "AC1 NEW $s $fn: ancestors zz-verify.sh and 106-verify.sh are not counted"; fi
done

# AC2 control: an unrelated sibling (not an ancestor) docs/tasks/yy-verify.sh must still be seen
cat > "$TMP/docs/tasks/yy-verify.sh" <<'STUB'
#!/usr/bin/env bash
sleep 120
STUB
bash "$TMP/docs/tasks/yy-verify.sh" & SIBPID=$!
sleep 1
for s in 089a1 089a2; do
    fn="${FN[$s]}"
    run_pred "$TMP/$s.new" "$fn" "$TMP/$s.ctl.out"
    if grep -Eq 'docs/tasks/yy-verify\.sh' "$TMP/$s.ctl.out"; then pass "AC2 NEW $s $fn: an unrelated sibling yy-verify.sh still counts (not quiet)"
    else fail "AC2 NEW $s $fn: the unrelated sibling yy-verify.sh was NOT listed (predicate always quiet?): $(head -n3 "$TMP/$s.ctl.out" | cut -c1-120 | tr '\n' '|')"; fi
done
kill "$SIBPID" 2>/dev/null; SIBPID=""

# AC3 diff limited to the predicate: delete the predicate from both versions, the rest must be byte-identical
for s in 089a1 089a2; do
    fn="${FN[$s]}"
    for v in old new; do extract "$TMP/$s.$v" "$fn" > "$TMP/$s.$v.fn"; done
    if [ ! -s "$TMP/$s.new.fn" ] || [ ! -s "$TMP/$s.old.fn" ]; then fail "AC3 $s: predicate $fn not found in OLD or NEW"; continue; fi
    for v in old new; do
        awk -v fn="$fn" '
            !on && $0 ~ ("^" fn "\\(\\) \\{") { on = 1; if ($0 ~ /; \}[[:space:]]*$/) on = 0; next }
            on { if ($0 ~ /^\}[[:space:]]*$/) on = 0; next }
            { print }' "$TMP/$s.$v" > "$TMP/$s.$v.rest"
    done
    if cmp -s "$TMP/$s.old.rest" "$TMP/$s.new.rest"; then pass "AC3 $s: outside $fn the script is byte-identical OLD..NEW"
    else fail "AC3 $s: differences outside $fn: $(diff "$TMP/$s.old.rest" "$TMP/$s.new.rest" | head -n4 | cut -c1-100 | tr '\n' '|')"; fi
    [ -s "$TMP/$s.old.rest" ] || fail "AC3 $s: empty remainder (broken extraction)"
done

echo "106-verify: $FAILS failed"
exit "$FAILS"
