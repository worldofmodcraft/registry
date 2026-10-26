#!/usr/bin/env bash
#
# 084-verify.sh -- the runnable verification artefact for task 084 (MANAGER.md Section 2c).
#
# Task 084: 075-verify.sh measures 075's OWN change (the declared-file-scope check) on 075's pinned PR range (registry
# PR #18), never on BASE..HEAD. Demonstrates acceptance criteria 1, 2 and 4 of docs/tasks/084-repin-075-verify.md.
# Criterion 3 (every closed script green on HEAD, and 075-verify.sh green on the merge with origin/task/065-entry-schema-key-id;
# one script at a time on a quiet machine) is a sequential run done by hand and logged; it is not repeated here.
#
# Usage:  docs/tasks/084-verify.sh [--mutate]      (any cwd inside the repository)
#   (no flag)  AC0 (075-verify.sh's pins are PR #18's own fork point and last commit; it no longer measures BASE..HEAD),
#              AC1 (on a throw-away later branch that edits contracts/append-only.rules.md and tools/registry/schema.py: the
#              OLD 075-verify.sh, taken from the merge commit 4356583, FAILS its scope check; the current one passes),
#              AC4 (084's own change, measured on fixed SHAs: the red commit touches only 084's files, the fix commit only
#              075-verify.sh and 070-verify.sh).
#   --mutate   AC2 (range widened to HEAD in two ways, unreachable BASE pin, unreachable FINAL pin: each red, none skipped).
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Network: none. Exit code: the number of failed checks. Run it with no other registry suite running (it runs 075-verify.sh,
# which runs the whole tests/registry suite and 032-verify.sh, several times).
# Requires: git, python3 (and whatever 075-verify.sh requires).

set -u
set -o pipefail

MUTATE=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) echo "usage: $0 [--mutate]"; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify084 -c user.email=verify084@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
MERGE075="4356583"      # registry PR #18, task 075's merge commit
S=docs/tasks/075-verify.sh

# 084's own commits, fixed SHAs (AC4; REVIEW-CHECKLIST item 12). Filled in by the pin commit after the red and fix commits exist.
PIN084_BASE="4356583"   # registry origin/main when 084 was cut
PIN084_RED="0932119"    # 084-verify.sh + task file only
PIN084_FIX="ec3f258"    # 075-verify.sh re-pinned, 070-verify.sh closed list

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# mk_later DEST : HEAD plus a later task's legitimate edits (the 065 shape): contracts/append-only.rules.md and
#  tools/registry/schema.py edited (two files outside 075's declared scope).
mk_later() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$HEADREV" || return 1
    git -C "$1" checkout -q -b later-065 || return 1
    printf '\n<!-- a later task (065 shape) edits this contract -->\n' >> "$1/contracts/append-only.rules.md"
    printf '\n# a later task (065 shape) edits this module\n' >> "$1/tools/registry/schema.py"
    git -C "$1" add -A
    git -C "$1" "${GITID[@]}" commit -q -m "Task 065 shape: later task edits append-only.rules.md and schema.py"
}

run075() {   # run075 DIR OUTFILE [SCRIPT] : run the 075 script in DIR; echo exit code
    ( cd "$1" && PYTHONDONTWRITEBYTECODE=1 bash "${3:-$S}" ) > "$2" 2>&1
    echo $?
}

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC0 -- the pins in 075-verify.sh are PR #18's own fork point and last commit"
read_pin() { sed -n "s/^$1=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$ROOT/$S" | head -n1; }
lb=$(read_pin BASE); lf=$(read_pin FINAL)
if [ -z "$lb" ] || [ -z "$lf" ]; then fail "AC0.1 cannot read BASE / FINAL from $S (a search that finds nothing is broken)"; else
    [ "$(git -C "$ROOT" rev-parse "$lb^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" merge-base "$MERGE075^1" "$MERGE075^2")" ] \
        && pass "AC0.1 BASE=$lb is PR #18's fork point (git merge-base $MERGE075^1 $MERGE075^2)" || fail "AC0.1 BASE=$lb is not PR #18's fork point"
    [ "$(git -C "$ROOT" rev-parse "$lf^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$MERGE075^2")" ] \
        && pass "AC0.2 FINAL=$lf is the last commit of PR #18 (git rev-parse $MERGE075^2)" || fail "AC0.2 FINAL=$lf is not $MERGE075^2"
fi
if grep -nE '"\$BASE" HEAD|BASE\.\.HEAD' "$ROOT/$S" | grep -vE '^[0-9]+:\s*#' >/dev/null; then
    fail "AC0.3 $S still measures BASE..HEAD outside comments: $(grep -nE '"\$BASE" HEAD|BASE\.\.HEAD' "$ROOT/$S" | grep -vE '^[0-9]+:\s*#' | head -n2 | cut -c1-120 | tr '\n' '|')"
else pass "AC0.3 $S no longer diffs the BASE against HEAD (outside comments)"; fi
if grep -q '"\$BASE" "\$FINAL"' "$ROOT/$S"; then pass "AC0.4 $S diffs \"\$BASE\" \"\$FINAL\""; else fail "AC0.4 $S has no \"\$BASE\" \"\$FINAL\" diff"; fi

section "AC1 -- on a later branch (append-only.rules.md + schema.py edited) the OLD script fails its scope check, the new one passes"
if ! mk_later "$TMP/L"; then fail "AC1.0 cannot build the later branch"; else
    git -C "$TMP/L" diff --stat "$HEADREV" HEAD | sed 's/^/  /'
    git -C "$ROOT" show "$MERGE075:$S" > "$TMP/L/docs/tasks/075-verify-old.sh" || fail "AC1.0 cannot extract the old script from $MERGE075"
    rc=$(run075 "$TMP/L" "$TMP/old.out" docs/tasks/075-verify-old.sh)
    if [ "$rc" != 0 ] && grep -q '^FAIL  out-of-scope files in base\.\.HEAD' "$TMP/old.out" \
        && grep -q 'contracts/append-only.rules.md' "$TMP/old.out" && grep -q 'tools/registry/schema.py' "$TMP/old.out"; then
        pass "AC1.1 the OLD 075-verify.sh (from $MERGE075) exits $rc on the later branch: scope check red, naming both files"
    else fail "AC1.1 the OLD script did not fail as expected on the later branch (exit $rc): $(grep -E '^FAIL' "$TMP/old.out" | head -n4 | cut -c1-120 | tr '\n' '|')"; fi
    rc=$(run075 "$TMP/L" "$TMP/new.out")
    if [ "$rc" = 0 ]; then pass "AC1.2 the current 075-verify.sh exits 0 on the later branch"; else fail "AC1.2 the current script exit $rc on the later branch: $(grep -E '^FAIL' "$TMP/new.out" | head -n4 | cut -c1-140 | tr '\n' '|')"; fi
    for pat in 'pin .* exists' 'range .* touches only the task' 'ALL CHECKS PASSED'; do
        grep -qE "^(PASS  .*|)($pat)" "$TMP/new.out" && pass "AC1.3 the current script reports a passing '$pat' line" || fail "AC1.3 no passing '$pat' line in the current script's output"
    done
fi

section "AC4 -- 084's own change, measured on fixed SHAs (never HEAD)"
if [ "$PIN084_RED" = "__RED__" ] || [ "$PIN084_FIX" = "__FIX__" ]; then
    fail "AC4.0 the 084 red/fix SHAs are not pinned yet"
else
    for s in "$PIN084_BASE" "$PIN084_RED" "$PIN084_FIX"; do
        git -C "$ROOT" cat-file -e "$s^{commit}" 2>/dev/null && pass "AC4.1 pin $s exists" || fail "AC4.1 pin $s does not exist"
    done
    [ "$(git -C "$ROOT" rev-parse "$PIN084_RED^" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$PIN084_BASE^{commit}" 2>/dev/null)" ] \
        && pass "AC4.2 the red commit's parent is the base" || fail "AC4.2 the red commit's parent is not the base"
    [ "$(git -C "$ROOT" rev-parse "$PIN084_FIX^" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$PIN084_RED^{commit}" 2>/dev/null)" ] \
        && pass "AC4.3 the fix commit follows the red commit directly" || fail "AC4.3 the fix commit does not follow the red commit"
    git -C "$ROOT" merge-base --is-ancestor "$PIN084_FIX" HEAD && pass "AC4.4 the fix commit is an ancestor of HEAD" || fail "AC4.4 the fix commit is not an ancestor of HEAD"
    red_files="$(git -C "$ROOT" diff --name-only "$PIN084_BASE" "$PIN084_RED" 2>/dev/null | sort | tr '\n' ' ')"
    [ "$red_files" = "docs/tasks/084-repin-075-verify.md docs/tasks/084-verify.sh " ] \
        && pass "AC4.5 the red commit touches only 084-verify.sh and the task file" || fail "AC4.5 the red commit touches: $red_files"
    fix_files="$(git -C "$ROOT" diff --name-only "$PIN084_RED" "$PIN084_FIX" 2>/dev/null | sort | tr '\n' ' ')"
    [ "$fix_files" = "docs/tasks/070-verify.sh docs/tasks/075-verify.sh " ] \
        && pass "AC4.6 the fix commit touches only 075-verify.sh and 070-verify.sh" || fail "AC4.6 the fix commit touches: $fix_files"
    # 070's change is the closed list only: exactly the CLOSED= line differs
    nd="$(git -C "$ROOT" diff -U0 "$PIN084_RED" "$PIN084_FIX" -- docs/tasks/070-verify.sh | grep -E '^[+-][^+-]' | grep -vE '^[+-]CLOSED=' | wc -l)"
    [ "$nd" = 0 ] && pass "AC4.7 in 070-verify.sh only the CLOSED= line changed" || fail "AC4.7 070-verify.sh changed outside the CLOSED= line ($nd lines)"
    git -C "$ROOT" diff -U0 "$PIN084_RED" "$PIN084_FIX" -- docs/tasks/070-verify.sh | grep -qE '^\+CLOSED=.* 075( |")' \
        && pass "AC4.8 070-verify.sh's CLOSED list gains 075" || fail "AC4.8 070-verify.sh's CLOSED list does not gain 075"
fi

# ==================================================================================================
else
section "AC2 mutations (a throw-away later branch; each mutation is committed in the clone, run, and reverted)"
if ! mk_later "$TMP/M"; then fail "AC2.0 cannot build the later branch"; else
    mutate_commit() {   # mutate_commit OLD NEW : replace OLD (exactly once) with NEW in the script in the clone, commit it
        if [ "$(grep -cF -- "$1" "$TMP/M/$S")" != 1 ]; then return 1; fi
        python3 -I - "$TMP/M/$S" "$1" "$2" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new, 1))
PY
        git -C "$TMP/M" "${GITID[@]}" commit -q -am "mutation" || return 1
    }
    expect_red() {   # expect_red LABEL OLD NEW REGEX... : mutate, run, demand exit!=0 and every REGEX
        local label="$1" old="$2" new="$3" rc re miss=""; shift 3
        if ! mutate_commit "$old" "$new"; then fail "$label: the mutation did not apply (pattern not found exactly once in $S)"; return; fi
        rc=$(run075 "$TMP/M" "$TMP/mut.out")
        for re in "$@"; do grep -Eq "$re" "$TMP/mut.out" || miss="$miss /$re/"; done
        if [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, $(grep -E "$1" "$TMP/mut.out" | head -n1 | cut -c1-150)"
        else fail "$label stayed green or missed$miss: exit $rc"; fi
        git -C "$TMP/M" reset -q --hard HEAD~1
    }
    FINALPIN="$(git -C "$ROOT" show "HEAD:$S" | sed -n 's/^FINAL=\([0-9a-f]\{7,\}\).*/\1/p' | head -n1)"
    BASEPIN="$(git -C "$ROOT" show "HEAD:$S" | sed -n 's/^BASE=\([0-9a-f]\{7,\}\).*/\1/p' | head -n1)"
    if [ -z "$FINALPIN" ] || [ -z "$BASEPIN" ]; then fail "AC2.0 cannot read the BASE / FINAL pins from $S (a search that finds nothing is broken)"; else
    expect_red "AC2.m1 FINAL widened to HEAD (the later branch's edits come into range)" "FINAL=$FINALPIN" 'FINAL=HEAD' \
        '^FAIL  out-of-scope files in ' 'contracts/append-only.rules.md' 'tools/registry/schema.py'
    expect_red "AC2.m2 the scope check's range text widened back to BASE..HEAD" 'diff --name-only "$BASE" "$FINAL" 2>/dev/null' 'diff --name-only "$BASE" HEAD 2>/dev/null' \
        '^FAIL  out-of-scope files in ' 'contracts/append-only.rules.md' 'tools/registry/schema.py'
    expect_red "AC2.m3 unreachable BASE pin must FAIL, never skip" "BASE=$BASEPIN" 'BASE=deadbee' \
        '^FAIL  pin deadbee' '^FAIL  .*scope'
    expect_red "AC2.m4 unreachable FINAL pin must FAIL, never skip" "FINAL=$FINALPIN" 'FINAL=deadbee' \
        '^FAIL  pin deadbee' '^FAIL  .*scope'
    fi
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
