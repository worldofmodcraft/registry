#!/usr/bin/env bash
#
# 071-verify.sh -- the runnable verification artefact for task 071 (MANAGER.md Section 2c).
#
# Task 071: 007b-verify.sh measures 007b's OWN change (file scope, "007a modules unchanged", ownership-file size cap) on
# 007b's pinned PR range (registry PR #12), never on origin/main...HEAD. Demonstrates acceptance criteria 1 and 2 of
# docs/tasks/071-repin-007b-verify.md. Criterion 3 (every closed script green on HEAD, and 007b + 062 green on the merge
# with origin/task/064-schema-check-end-anchor; one script at a time on a quiet machine) is a sequential run done by hand
# and logged; it is not repeated here.
#
# Usage:  docs/tasks/071-verify.sh [--mutate]      (any cwd inside the repository)
#   (no flag)  AC0 (the pins are PR #12's own fork point and last commit), AC1 (on a throw-away later branch that edits
#              tools/registry/schema.py and .gitignore and adds tools/registry/ownership_extra.py: the OLD 007b-verify.sh,
#              taken from the merge commit 70cedca, FAILS; the current one passes).
#   --mutate   AC2 (range widened to HEAD, size pin widened, unreachable BASE pin, unreachable FINAL pin: each red, none skipped).
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Network: none. Exit code: the number of failed checks. Run it with no other registry suite running.
# Requires: git, python3.

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
GITID=(-c user.name=verify071 -c user.email=verify071@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
MERGE007B="70cedca"     # registry PR #12, task 007b's merge commit
S=docs/tasks/007b-verify.sh

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# mk_later DEST : HEAD plus a later task's legitimate edits (the 064 shape): schema.py (a 007a module) and .gitignore edited,
#  one further ownership*.py file added. origin/main in the clone is pointed at HEAD, so what the OLD script saw as "the
#  branch's change" is exactly these edits.
mk_later() {
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$HEADREV" || return 1
    git -C "$1" checkout -q -b later-064 || return 1
    git -C "$1" update-ref refs/remotes/origin/main "$HEADREV" || return 1
    printf '\n# a later task (064 shape) edits this 007a module\n' >> "$1/tools/registry/schema.py"
    printf '\n# a later task edits .gitignore\n' >> "$1/.gitignore"
    printf '# a later task adds a third ownership file\n' > "$1/tools/registry/ownership_extra.py"
    git -C "$1" add -A
    git -C "$1" "${GITID[@]}" commit -q -m "Task 064 shape: later task edits schema.py, .gitignore, adds ownership_extra.py"
}

run007b() {   # run007b DIR OUTFILE [SCRIPT] : run the 007b script in DIR; echo exit code
    ( cd "$1" && bash "${3:-$S}" ) > "$2" 2>&1
    echo $?
}

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC0 -- the pins in 007b-verify.sh are PR #12's own fork point and last commit"
read_pin() { sed -n "s/^$1=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$ROOT/$S" | head -n1; }
lb=$(read_pin BASE007B); lf=$(read_pin FINAL007B)
if [ -z "$lb" ] || [ -z "$lf" ]; then fail "AC0.1 cannot read BASE007B / FINAL007B from $S (a search that finds nothing is broken)"; else
    [ "$(git -C "$ROOT" rev-parse "$lb^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" merge-base "$MERGE007B^1" "$MERGE007B^2")" ] \
        && pass "AC0.1 BASE007B=$lb is PR #12's fork point (git merge-base $MERGE007B^1 $MERGE007B^2)" || fail "AC0.1 BASE007B=$lb is not PR #12's fork point"
    [ "$(git -C "$ROOT" rev-parse "$lf^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$MERGE007B^2")" ] \
        && pass "AC0.2 FINAL007B=$lf is the last commit of PR #12 (git rev-parse $MERGE007B^2)" || fail "AC0.2 FINAL007B=$lf is not $MERGE007B^2"
fi
if grep -nE 'origin/main' "$ROOT/$S" | grep -vE '^[0-9]+:\s*#' >/dev/null; then
    fail "AC0.3 $S still refers to origin/main outside comments: $(grep -nE 'origin/main' "$ROOT/$S" | grep -vE '^[0-9]+:\s*#' | head -n2 | cut -c1-120 | tr '\n' '|')"
else pass "AC0.3 $S no longer depends on origin/main (outside comments)"; fi

section "AC1 -- on a later branch (schema.py + .gitignore edited, a third ownership file added) the OLD script fails, the new one passes"
if ! mk_later "$TMP/L"; then fail "AC1.0 cannot build the later branch"; else
    git -C "$TMP/L" diff --stat "$HEADREV" HEAD | sed 's/^/  /'
    git -C "$ROOT" show "$MERGE007B:$S" > "$TMP/L/docs/tasks/007b-verify-old.sh" || fail "AC1.0 cannot extract the old script from $MERGE007B"
    rc=$(run007b "$TMP/L" "$TMP/old.out" docs/tasks/007b-verify-old.sh)
    if [ "$rc" != 0 ] && grep -q '^FAIL  files outside the declared scope' "$TMP/old.out" && grep -q '^FAIL  007a modules changed' "$TMP/old.out" && grep -q '^FAIL  size: 3 ownership' "$TMP/old.out"; then
        pass "AC1.1 the OLD 007b-verify.sh (from $MERGE007B) exits $rc on the later branch: scope, 007a-unchanged and size checks red"
    else fail "AC1.1 the OLD script did not fail as expected on the later branch (exit $rc): $(grep -E '^FAIL' "$TMP/old.out" | head -n4 | cut -c1-120 | tr '\n' '|')"; fi
    rc=$(run007b "$TMP/L" "$TMP/new.out")
    if [ "$rc" = 0 ]; then pass "AC1.2 the current 007b-verify.sh exits 0 on the later branch"; else fail "AC1.2 the current script exit $rc on the later branch: $(grep -E '^FAIL' "$TMP/new.out" | head -n4 | cut -c1-140 | tr '\n' '|')"; fi
    for pat in 'pinned commit .* is reachable' 'changed files in the pinned range .* all inside' "007a's modules are untouched in the pinned range" 'size: .* ownership source files at'; do
        grep -qE "^ok    .*($pat)" "$TMP/new.out" && pass "AC1.3 the current script reports a passing '$pat' line" || fail "AC1.3 no passing '$pat' line in the current script's output"
    done
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
        rc=$(run007b "$TMP/M" "$TMP/mut.out")
        for re in "$@"; do grep -Eq "$re" "$TMP/mut.out" || miss="$miss /$re/"; done
        if [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, $(grep -E "$1" "$TMP/mut.out" | head -n1 | cut -c1-150)"
        else fail "$label stayed green or missed$miss: exit $rc"; fi
        git -C "$TMP/M" reset -q --hard HEAD~1
    }
    expect_red "AC2.m1 FINAL007B widened to HEAD (the later branch's edits come into range)" 'FINAL007B="17555d9"' 'FINAL007B="HEAD"' \
        '^FAIL  files outside the declared scope' '^FAIL  007a modules changed'
    expect_red "AC2.m2 the size pin widened to HEAD" 'ls-tree -r --name-only "$FINAL007B" -- tools/registry' 'ls-tree -r --name-only HEAD -- tools/registry' \
        '^FAIL  size: 3 ownership'
    expect_red "AC2.m3 unreachable BASE007B pin must FAIL, never skip" 'BASE007B="fb76ee5"' 'BASE007B="deadbee"' \
        '^FAIL  pinned commit deadbee' '^FAIL  .*scope' '^FAIL  .*007a'
    expect_red "AC2.m4 unreachable FINAL007B pin must FAIL, never skip" 'FINAL007B="17555d9"' 'FINAL007B="deadbee"' \
        '^FAIL  pinned commit deadbee' '^FAIL  .*scope' '^FAIL  .*007a' '^FAIL  size'
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
