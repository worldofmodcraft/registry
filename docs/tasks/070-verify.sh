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
CLOSED="006 007a 007b 008a 032 034 057 062 066 067 069 075"

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
#  Also: 032-verify.sh, 034-verify.sh annotated with comments (no check added, removed or renamed), contracts/ownership.md edited, one check
#  added to 006-verify.sh, and a follow-up commit whose subject starts "Task 062" touching a file outside 062's scope.
mk_later() {
    new_clone "$1" "$HEADREV" || return 1
    git -C "$1" checkout -q -b later-007b
    printf '\nA later task adds this sentence to the contracts README.\n' >> "$1/docs/contracts/README.md"
    echo "# probe one, task 070 later branch" > "$1/tools/registry/probe_one.py"; echo "# probe two, task 070 later branch" > "$1/tools/registry/probe_two.py"   # content differs from 069 mk_later (it would otherwise find nothing to commit)
    printf '\n# a later task annotates this script\n' >> "$1/docs/tasks/032-verify.sh"
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

# mk_deleter DEST : HEAD plus a later task that DELETES or RENAMES one check in each of 006, 008a, 032, 034, 057 (committed).
#  These are the changes 062's live guards (AC6L.*) exist to catch; they are the opposite of mk_later's additions.
mk_deleter() {
    new_clone "$1" "$HEADREV" || return 1
    git -C "$1" checkout -q -b later-deleter
    sed -i 's/"S5 /"S5x /g' "$1/docs/tasks/032-verify.sh"                      # 032: check id S5 renamed
    sed -i 's/"C4\.1 /"C4.1x /' "$1/docs/tasks/034-verify.sh"                  # 034: check id C4.1 renamed
    sed -i 's/"O1 /"OX /g' "$1/docs/tasks/057-verify.sh"                         # 057: check id O1 renamed
    sed -i 's/ok "no key-like file tracked"/ok "no key-like file tracked (reworded)"/' "$1/docs/tasks/008a-verify.sh"   # 008a: label reworded
    python3 -I - "$1/docs/tasks/006-verify.sh" <<'PY' || return 1
import sys
p = sys.argv[1]
s = open(p).read()
old = "expect_hits \"C10.3 id/owner are stated frozen, full stop, with no carve-out\" \\\n    'is a violation, full stop'\n"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, ""))                                           # 006: check C10.3 deleted
PY
    git -C "$1" add -A
    git -C "$1" "${GITID[@]}" commit -q -m "Task 007b: later task deletes or renames one check in each closed script"
}
LIVE_IDS="AC6L.006 AC6L.008a AC6L.032 AC6L.034 AC6L.057 AC6L.006.count"
# deleter_unseen DIR : run 062 in DIR; echo how many of LIVE_IDS did NOT turn red; the ids that did not go to $TMP/unseen.txt
deleter_unseen() {
    local id n=0
    ( cd "$1" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash docs/tasks/062-verify.sh ) > "$TMP/D.out" 2>&1
    : > "$TMP/unseen.txt"
    for id in $LIVE_IDS; do grep -q "^FAIL  $id " "$TMP/D.out" || { n=$((n + 1)); echo "$id" >> "$TMP/unseen.txt"; }; done
    echo "$n"
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
    for id in AC2.1 AC2.2 AC2.3 AC2.4 AC2.5 AC2.6; do
        grep -q "^PASS  $id " "$TMP/L.067.out" && pass "AC2.067.$id 067-verify.sh reports $id PASS on the later branch" || fail "AC2.067.$id 067-verify.sh has no passing $id line on the later branch"
    done
    for id in AC6.006 AC6.008a AC6.032 AC6.057 AC6.006.count AC6.034 AC7.1 AC7.4 SELF.1 $LIVE_IDS; do
        grep -q "^PASS  $id " "$TMP/L.062.out" && pass "AC2.062.$id 062-verify.sh reports $id PASS on the later branch" || fail "AC2.062.$id 062-verify.sh has no passing $id line on the later branch"
    done
fi

section "AC5 -- a later task that deletes or renames a check turns 062's live guards red (the pinned parts stay green)"
if ! mk_deleter "$TMP/D0"; then fail "AC5.0 cannot build the deleter branch"; else
    git -C "$TMP/D0" diff --stat "$HEADREV" HEAD | sed 's/^/  /'
    n=$(deleter_unseen "$TMP/D0")
    for id in $LIVE_IDS; do
        grep -q "^FAIL  $id " "$TMP/D.out" && pass "AC5.$id a deleted/renamed check turns $id red: $(grep -m1 "^FAIL  $id " "$TMP/D.out" | cut -c1-150)" || fail "AC5.$id a deleted/renamed check left $id green (the live guard is missing or blind)"
    done
    for id in AC6.006 AC6.008a AC6.032 AC6.057 AC6.034 AC6.006.count AC7.1 SELF.1; do
        grep -q "^PASS  $id " "$TMP/D.out" && pass "AC5.pinned.$id the pinned own-change check $id stays green on the deleter branch" || fail "AC5.pinned.$id the pinned check $id is not green on the deleter branch"
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
    expect_red "AC3.m4 062 FINAL062 widened to HEAD" 062 docs/tasks/062-verify.sh 'FINAL062="82fa564"' 'FINAL062="HEAD"' '^FAIL  AC6\.034' '^FAIL  AC6\.006\.count' '^FAIL  AC7\.1' '^FAIL  SELF\.1'
    expect_red "AC3.m5 062 unreachable FINAL062 pin must FAIL, never skip" 062 docs/tasks/062-verify.sh 'FINAL062="82fa564"' 'FINAL062="deadbee"' '^FAIL  AC6\.0 .*deadbee'
    # ---- 069: ajv default removed
    expect_red "AC3.m6 069 ajv default removed" 069 docs/tasks/069-verify.sh 'NM="${WOM_NODE_MODULES:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/tools/dev/node_modules}"' 'NM="${WOM_NODE_MODULES:-}"' '^FAIL  AC4\.0' '^FAIL  AC7\.0'

    # ---- AC4: live-property checks are not converted; breaking the live property still reddens them
    expect_red "AC4.m1 README sentence deleted (committed) reddens 067's live AC2.5" 067 docs/contracts/README.md 'None of the three tasks implements checking logic' 'None of the tasks implement checking logic' '^FAIL  AC2\.5'
    expect_red "AC4.m2 a 006 retirement successor renamed (committed) reddens 062's live AC5.1" 062 docs/tasks/006-verify.sh '#   successor:  057-textchecks.py old-gone/rule2-born-removed' '#   successor:  057-textchecks.py old-gone/rule2-born-removedX' '^FAIL  AC5\.1'
    # ---- live guards removed: the deleter branch must then go undetected (n = 6 unseen); proves AC5 can fail
    if mk_deleter "$TMP/D1"; then
        python3 -I - "$TMP/D1/docs/tasks/062-verify.sh" <<'PY' || fail "AC5.m0 cannot neutralise the live guards"
import sys
p = sys.argv[1]
s = open(p).read()
for old, new in (('LIVE_IDS_SCRIPTS="006 008a 032 034 057"', 'LIVE_IDS_SCRIPTS=""'), ("\nLIVE_COUNT_GUARD=1\n", "\nLIVE_COUNT_GUARD=0\n")):
    assert s.count(old) == 1, old
    s = s.replace(old, new)
open(p, "w").write(s)
PY
        git -C "$TMP/D1" "${GITID[@]}" commit -q -am "mutation: live guards removed"
        n=$(deleter_unseen "$TMP/D1")
        if [ "$n" = 6 ]; then pass "AC5.m1 with the six live guards removed from 062, the delete/rename branch goes undetected ($n of 6 ids stay green), so AC5 turns red on such a 062"
        else fail "AC5.m1 guards removed but only $n of 6 live ids stayed green (unseen: $(tr '\n' ' ' < "$TMP/unseen.txt"))"; fi
    else fail "AC5.m0 cannot build the deleter branch"; fi

    # ---- F2: 032's N5b pattern reverted to the old phrase (committed) reddens 067's live AC2.6
    expect_red "AC5.m2 032's N5b pattern reverted to the old phrase reddens 067's live AC2.6" 067 docs/tasks/032-verify.sh "'None of the three tasks implements checking logic' \"\$CONTRACTS_README\"" "'in any of the three tasks' \"\$CONTRACTS_README\"" '^FAIL  AC2\.6'
    # ---- F3: a stale quoting sentence re-introduced into contracts/ownership.md (committed) reddens 062's live AC7.4
    expect_red "AC5.m3 the stale 'one permitted in-place mutation' quote re-introduced in ownership.md reddens 062's live AC7.4" 062 contracts/ownership.md '<!-- a later task annotates this contract -->' 'the one permitted in-place mutation' '^FAIL  AC7\.4'
fi
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
