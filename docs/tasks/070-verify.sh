#!/usr/bin/env bash
#
# 070-verify.sh -- the runnable verification artefact for task 070 (MANAGER.md Section 2c).
#
# Task 070: no closed task's verify script measures its OWN change against HEAD (audit + re-pin), and every script that
# needs ajv finds the pinned one. Demonstrates acceptance criteria 1-4 of docs/tasks/070-closed-verify-head-audit.md.
# Criterion 5 (every closed script green on HEAD, and on the merges with 007b / 064; one script at a time, on a quiet
# machine) is a sequential run done by hand and logged; it is not repeated here.
#
# Usage:  docs/tasks/070-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (the re-pinned FINAL commits are the tasks' own), AC2 (all ten closed scripts are green on a throw-away
#              later branch that edits every file an own-change check guards; the named own-change checks pass there).
#   --mutate   AC3 (widening a re-pinned range to HEAD, an unreachable pin, removing the ajv default: each red),
#              AC4 (live-property checks still bite on HEAD-shaped breakage).
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with
#                     npm ci --prefix tools/dev) a node_modules directory containing ajv 8. A missing ajv is a FAILURE.
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Network: only 066-verify.sh (it runs `npm ci` anonymously against the public registry, as its own spec says).
# Exit code: the number of failed checks. Run it with no other registry suite running (it runs the scripts one at a time).
# Requires: git, python3, node, plus everything the ten closed scripts require (minisign, ...).

set -u
set -o pipefail

MUTATE=0
NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify070 -c user.email=verify070@invalid -c commit.gpgsign=false)
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"
CLOSED="006 007a 008a 032 034 057 062 066 067 069"

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

if [ -z "$NM" ] || [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then
    fail "AC0 prerequisite: a node_modules directory with ajv and a node binary are required; run: npm ci --prefix tools/dev (or pass NODE_MODULES_DIR / set WOM_NODE_MODULES)"
    printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"
    exit "$FAILURES"
fi

new_clone() {   # new_clone DEST REV : a fresh clone, detached at REV, with a real (git-ignored) tools/dev/node_modules copy
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
    mkdir -p "$1/tools/dev" && cp -a "$NM" "$1/tools/dev/node_modules" || return 1
}

# mk_later DEST : HEAD plus a later task's legitimate edits to every file an own-change check of a closed script guards.
#  007b's shape: docs/contracts/README.md edited, two new files under tools/registry/.
#  Also: 032-verify.sh, 034-verify.sh edited (one check id renamed in 032), contracts/ownership.md edited, one check
#  added to 006-verify.sh, and a follow-up commit whose subject starts "Task 062" touching a file outside 062's scope.
mk_later() {
    new_clone "$1" "$HEADREV" || return 1
    git -C "$1" checkout -q -b later-007b
    printf '\nA later task adds this sentence to the contracts README.\n' >> "$1/docs/contracts/README.md"
    echo "# probe one" > "$1/tools/registry/probe_one.py"; echo "# probe two" > "$1/tools/registry/probe_two.py"
    printf '\n# a later task annotates this script\n' >> "$1/docs/tasks/032-verify.sh"
    sed -i 's/"S5 /"S5x /g' "$1/docs/tasks/032-verify.sh"
    printf '\n# a later task annotates this script\n' >> "$1/docs/tasks/034-verify.sh"
    printf '\n<!-- a later task annotates this contract -->\n' >> "$1/contracts/ownership.md"
    python3 -I - "$1/docs/tasks/006-verify.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
marker = "printf '\\n== RESULT ==\\n'"
assert s.count(marker) == 1
open(p, "w").write(s.replace(marker, 'pass "C99.1 a later task adds one check"\n' + marker))
PY
    git -C "$1" add -A
    git -C "$1" "${GITID[@]}" commit -q -m "Task 007b: later task edits files the closed scripts guard"
    echo "probe" > "$1/probe062.txt"; git -C "$1" add probe062.txt
    git -C "$1" "${GITID[@]}" commit -q -m "Task 062 follow-up: a later commit with a 062 subject outside 062's scope"
}

# run_closed DIR NAME OUT : run NAME-verify.sh in DIR with no argument and no WOM_NODE_MODULES (the default ajv path); echo exit code
run_closed() {
    ( cd "$1" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "docs/tasks/$2-verify.sh" ) > "$3" 2>&1
    echo $?
}
fail_lines() { grep -E '^FAIL  ' "$1" | head -n "${2:-6}" | cut -c1-150 | tr '\n' '|'; }

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC1 -- the re-pinned FINAL commits are the tasks' own: FINAL = <merge commit>^2 (the last commit of the PR)"
check_final() {   # check_final LABEL SCRIPT VARNAME MERGE
    local label="$1" f="$ROOT/docs/tasks/$2" var="$3" m="$4" lf
    lf=$(sed -n "s/^$var=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}\([[:space:]].*\)\{0,1\}$/\1/p" "$f" | head -n1)
    if [ -z "$lf" ]; then fail "$label cannot read $var from $2 (a search that finds nothing is broken)"; return; fi
    [ "$(git -C "$ROOT" rev-parse "$lf^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" rev-parse "$m^2")" ] \
        && pass "$label $var=$lf in $2 is the last commit of the PR (git rev-parse $m^2)" || fail "$label $var=$lf in $2 is not $m^2"
}
check_final AC1.062 062-verify.sh FINAL062 eba11b7     # registry PR #9, task 062
check_final AC1.067 067-verify.sh FINAL ac22c8f        # registry PR #11, task 067 (already pinned by task 069; control)
lb=$(sed -n 's/^BASE062="\([0-9a-f]\{7,\}\)".*/\1/p' "$ROOT/docs/tasks/062-verify.sh" | head -n1)
[ -n "$lb" ] && [ "$(git -C "$ROOT" rev-parse "$lb^{commit}" 2>/dev/null)" = "$(git -C "$ROOT" merge-base eba11b7^1 eba11b7^2)" ] \
    && pass "AC1.062.base BASE062=$lb is PR #9's fork point (git merge-base eba11b7^1 eba11b7^2)" || fail "AC1.062.base BASE062 is not PR #9's fork point"

section "AC2 -- every closed script is green on a later branch (007b's shape plus an edit to every guarded file)"
if ! mk_later "$TMP/L"; then fail "AC2.0 cannot build the later branch"; else
    printf '  later branch: %s (HEAD %s + 2 commits)\n' "$(git -C "$TMP/L" rev-parse --abbrev-ref HEAD)" "${HEADREV:0:7}"
    git -C "$TMP/L" diff --stat "$HEADREV" HEAD | sed 's/^/  /'
    for n in $CLOSED; do
        rc=$(run_closed "$TMP/L" "$n" "$TMP/L.$n.out")
        if [ "$rc" = 0 ]; then pass "AC2.$n $n-verify.sh exits 0 on the later branch"; else fail "AC2.$n $n-verify.sh exit $rc on the later branch; $(fail_lines "$TMP/L.$n.out")"; fi
    done
    # the own-change checks the audit re-pins, each by name: a green exit is not enough (a check could have vanished)
    for id in AC2.1 AC2.2 AC2.3 AC2.4 AC2.5; do
        grep -q "^PASS  $id " "$TMP/L.067.out" && pass "AC2.067.$id 067-verify.sh reports $id PASS on the later branch" || fail "AC2.067.$id 067-verify.sh has no passing $id line on the later branch"
    done
    for id in AC6.006 AC6.008a AC6.032 AC6.057 AC6.006.count AC6.034 AC7.1 SELF.1; do
        grep -q "^PASS  $id " "$TMP/L.062.out" && pass "AC2.062.$id 062-verify.sh reports $id PASS on the later branch" || fail "AC2.062.$id 062-verify.sh has no passing $id line on the later branch"
    done
fi

# ==================================================================================================
else
# --mutate
section "AC3 / AC4 mutations (a throw-away later branch; each mutation is committed in the clone, run, and reverted)"
if ! mk_later "$TMP/M"; then fail "AC3.0 cannot build the later branch"; else
    mutate_commit() {   # mutate_commit FILE OLD NEW : replace OLD (exactly once) with NEW in the clone, commit it
        if [ "$(grep -cF -- "$2" "$TMP/M/$1")" != 1 ]; then return 1; fi
        python3 -I - "$TMP/M/$1" "$2" "$3" <<'PY' || return 1
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new, 1))
PY
        git -C "$TMP/M" "${GITID[@]}" commit -q -am "mutation" || return 1
    }
    revert_mutation() { git -C "$TMP/M" reset -q --hard HEAD~1; }
    expect_red() {   # expect_red LABEL SCRIPT FILE OLD NEW REGEX... : mutate, run SCRIPT by default path, demand exit!=0 and every REGEX
        local label="$1" n="$2" file="$3" old="$4" new="$5" rc re miss=""; shift 5
        if ! mutate_commit "$file" "$old" "$new"; then fail "$label: the mutation did not apply (pattern not found exactly once in $file)"; return; fi
        rc=$(run_closed "$TMP/M" "$n" "$TMP/mut.out")
        for re in "$@"; do grep -Eq "$re" "$TMP/mut.out" || miss="$miss /$re/"; done
        if [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, $(grep -E "$1" "$TMP/mut.out" | head -n1 | cut -c1-150)"
        else fail "$label stayed green or missed$miss: exit $rc"; fi
        revert_mutation
    }

    # ---- 067: range widened to HEAD / unreachable / ajv default removed
    expect_red "AC3.m1 067 FINAL widened to HEAD (the later branch's edits come into range)" 067 docs/tasks/067-verify.sh 'FINAL="06c721c"' 'FINAL="HEAD"' '^FAIL  AC2\.1' '^FAIL  AC2\.4'
    expect_red "AC3.m2 067 unreachable FINAL pin must FAIL, never skip" 067 docs/tasks/067-verify.sh 'FINAL="06c721c"' 'FINAL="deadbee"' '^FAIL  AC2\.1' '^FAIL  AC2\.4' '^FAIL  AC5\.1 pinned commit deadbee'
    expect_red "AC3.m3 067 ajv default removed" 067 docs/tasks/067-verify.sh 'NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"' 'NM="${WOM_NODE_MODULES:-}"' '^FAIL  AC3\.2'
    # ---- 062: FINAL062 widened to HEAD / unreachable
    expect_red "AC3.m4 062 FINAL062 widened to HEAD" 062 docs/tasks/062-verify.sh 'FINAL062="82fa564"' 'FINAL062="HEAD"' '^FAIL  AC6\.032' '^FAIL  AC6\.034' '^FAIL  AC6\.006\.count' '^FAIL  AC7\.1' '^FAIL  SELF\.1'
    expect_red "AC3.m5 062 unreachable FINAL062 pin must FAIL, never skip" 062 docs/tasks/062-verify.sh 'FINAL062="82fa564"' 'FINAL062="deadbee"' '^FAIL  AC6\.0 .*deadbee'
    # ---- 069: ajv default removed
    expect_red "AC3.m6 069 ajv default removed" 069 docs/tasks/069-verify.sh 'NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"' 'NM="${WOM_NODE_MODULES:-}"' '^FAIL  AC4\.0' '^FAIL  AC7\.0'

    # ---- AC4: live-property checks are not converted; breaking the live property still reddens them
    expect_red "AC4.m1 README sentence deleted (committed) reddens 067's live AC2.5" 067 docs/contracts/README.md 'None of the three tasks implements checking logic' 'None of the tasks implement checking logic' '^FAIL  AC2\.5'
    expect_red "AC4.m2 a 006 retirement successor renamed (committed) reddens 062's live AC5.1" 062 docs/tasks/006-verify.sh '#   successor:  057-textchecks.py required/born-pending' '#   successor:  057-textchecks.py required/born-pendingX' '^FAIL  AC5\.1'
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
