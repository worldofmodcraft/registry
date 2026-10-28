#!/usr/bin/env bash
#
# 062-verify.sh -- the runnable verification artefact for task 062 (MANAGER.md Section 2c).
#
# Task 062: the registry's closed-task verify scripts stay green on later branches, and stop pinning the
# superseded born-`removed` rule. This script demonstrates acceptance criteria AC1-AC8 of
# docs/tasks/062-registry-test-maintenance.md.
#
# Usage:  docs/tasks/062-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (red inventory, reproduced at the task's base), AC2 (pins), AC3 (later-branch property),
#              AC5 (retirements traceable), AC6 (nothing else removed), AC7 (ownership.md), self-scope.
#   --mutate   AC4 plus the reddening mutations of AC5 and AC6, all in a temporary clone.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with
#                     npm ci --prefix tools/dev) a node_modules directory containing ajv 8. 057-verify.sh's check
#                     V1 needs it and, by that script's own rule, a missing ajv is a FAILURE, never a skip; so
#                     this script cannot go green without it.
# Everything runs on the COMMITTED state (HEAD) in temporary clones; the caller's worktree is never modified.
# Deterministic, no network (the 032 script's advisory live probes are advisory-only and never change a verdict).
# Exit code: the number of failed checks. Output contains no timestamps or temp paths.
#
# Requires: git, python3, node, plus everything the verify scripts under test require (minisign, ...).

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
BASE062="e009ef0"            # registry origin/main when task 062 was cut: the frame of AC1, and the fork point of PR #9
# Task 070: AC6, AC7 and the self-scope check describe 062's OWN change, so they measure 062's pinned range
# BASE062..FINAL062 and never HEAD (HEAD moves with every later task: 069 and 070 edit the very scripts these checks
# compare). FINAL062 is the last commit on task/062-registry-test-maintenance before its merge (registry PR #9: the
# second parent of merge eba11b7, `git rev-parse eba11b7^2`). An unreachable pin is a FAILURE naming the commit
# (AC6.0), never a skip.
FINAL062="82fa564"
# Task 070 (fix round): each pinned own-change check in AC6 has a LIVE guard beside it, because a pinned range cannot see a
# later task that deletes or renames a check. LIVE_IDS_SCRIPTS: scripts whose check ids (labels, for 008a) at HEAD must be a
# superset of those at FINAL062 (adding checks stays green; deleting or renaming one goes red). LIVE_COUNT_GUARD=1: 006's
# evaluated-check count at HEAD must be >= its count at FINAL062. (Both are variables so 070-verify.sh can mutate them away.)
LIVE_IDS_SCRIPTS="006 008a 032 034 057"
LIVE_COUNT_GUARD=1
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
GITID=(-c user.name=verify062 -c user.email=verify062@invalid -c commit.gpgsign=false)

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

if [ -z "$NM" ] || [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then
    fail "AC0 prerequisite: a node_modules directory with ajv and a node binary are required (057-verify.sh V1); run: npm ci --prefix tools/dev (or pass NODE_MODULES_DIR / set WOM_NODE_MODULES)"
    printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"
    exit "$FAILURES"
fi

# --------------------------------------------------------------------------------------------------
# helper.py: all the structured reasoning, kept in one place and run with python3 -I.
cat > "$TMP/helper.py" <<'PYH'
import re, subprocess, sys

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def noncomment(text):
    return [l for l in text.splitlines() if not l.lstrip().startswith("#")]

ID = re.compile(r"""["']([A-Za-z][A-Za-z0-9]*(?:[.\-/][A-Za-z0-9]+)*) """)
def ids(text):
    out = set()
    for l in noncomment(text):
        out.update(t for t in ID.findall(l) if any(c.isdigit() for c in t))   # a check id always carries a digit (C1.5b, S4, T2); plain words are not ids
    return out

MSG = re.compile(r'\b(?:ok|fail)\s+"([^"]*)"')
VAR = re.compile(r"\$\{?[A-Za-z_]+\}?")
def msgs(text):
    out = set()
    for l in noncomment(text):
        for m in MSG.findall(l):
            out.add(VAR.sub("$", m))
    return out

# 008a labels carry no ids; these three messages were reworded when the scope block was re-pinned (D-1).
RENAMES_008A = {
    "every changed path is within the declared file scope": "every path changed in $..$ is within the declared file scope",
    "untouched: $": "untouched in $..$: $",
    "base commit 4d4a204 is not an ancestor of HEAD: file-scope check cannot run": "pinned commit $ is not an ancestor of HEAD: file-scope check cannot run",
}

def cmd_diffids(argv):
    name, oldp, newp, allowed = argv[0], argv[1], argv[2], set(a for a in argv[3].split(",") if a)
    old, new = read(oldp), read(newp)
    if name == "008a":
        o = {RENAMES_008A.get(m, m) for m in msgs(old)}
        n = msgs(new)
        label = "labels"
    else:
        o, n = ids(old), ids(new)
        label = "ids"
    if len(o) < 5:
        print("BROKEN-SEARCH: only %d %s found in the OLD script: the extractor matched (almost) nothing" % (len(o), label))
        return 2
    missing = sorted(o - n)
    print("%s: %d check %s before, %d after; missing now: %s; allowed to be missing: %s" % (name, len(o), label, len(n), missing or "none", sorted(allowed) or "none"))
    return 0 if set(missing) == allowed else 1

def cmd_retire(argv):
    # argv: repo-dir. Parses the RETIRED blocks of 006-verify.sh and checks every named successor really exists.
    d = argv[0]
    text = read(d + "/docs/tasks/006-verify.sh")
    blocks, cur = {}, None
    for l in text.splitlines():
        m = re.match(r"# RETIRED (\S+)", l)
        if m:
            cur = m.group(1)
            blocks[cur] = []
            continue
        m = re.match(r"#\s+successor:\s+(\S+)\s+(\S+)\s*$", l)
        if m and cur:
            blocks[cur].append((m.group(1), m.group(2)))
    rc = 0
    want = {"C1.5b", "C8.2", "C8.3a", "C8.3b"}
    if set(blocks) != want:
        print("FAILED: RETIRED blocks are %s, expected exactly %s" % (sorted(blocks), sorted(want)))
        return 1
    runtext = "\n".join(noncomment(text))
    for rid in sorted(blocks):
        succ = blocks[rid]
        if not succ or not any(f == "057-verify.sh" for f, _ in succ):
            print("FAILED: %s names no 057-verify.sh successor" % rid)
            rc = 1
            continue
        still = [s for s in ("%s " % rid, "C8.1 ") if rid == "C8.2" or s == "%s " % rid]
        for s in still:
            if '"' + s in runtext:
                print("FAILED: %s still has a live label \"%s...\" outside comments" % (rid, s.strip()))
                rc = 1
        for f, sid in succ:
            p = d + "/docs/tasks/" + f
            try:
                body = read(p)
            except OSError:
                print("FAILED: %s: successor file %s does not exist" % (rid, f))
                rc = 1
                continue
            if f == "057-verify.sh":
                ok = re.search(r'\b(?:pass|fail)\s+"%s\b' % re.escape(sid), body) is not None
            elif f == "057-textchecks.py":
                r = subprocess.run(["python3", "-I", p], capture_output=True, text=True, cwd=d)
                ok = ("PASS  %s:" % sid) in r.stdout
            elif f == "057-oracle.py":
                r = subprocess.run(["python3", "-I", p, "--list-mutations"], capture_output=True, text=True, cwd=d)
                ok = sid in r.stdout.split()
            elif f == "057-gen-fixtures.py":
                ok = ('"%s"' % sid) in body and ('"name": "%s"' % sid) in read(d + "/docs/tasks/057-transition-fixtures.json")
            else:
                print("FAILED: %s: successor file %s is not a 057 artefact" % (rid, f))
                rc = 1
                continue
            if not ok:
                print("FAILED: %s: successor %s %s does not exist (or does not pass)" % (rid, f, sid))
                rc = 1
            else:
                print("  %s -> %s %s: exists" % (rid, f, sid))
    return rc

def cmd_mut(argv):
    path, old, new, count = argv[0], argv[1], argv[2], argv[3]
    s = read(path)
    n = s.count(old)
    if n == 0 or (count == "one" and n != 1):
        print("MUTATION DID NOT APPLY: %r found %d time(s) in %s" % (old[:60], n, path))
        return 2
    s = s.replace(old, new) if count == "all" else s.replace(old, new, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(s)
    return 0

OLD_C33 = r"""    're\.search(schema\["pattern"\], instance)' """ + '"$CHECK_FILE"'
NEW_C33 = re.compile(r"""^\s+'re\\\.search\(.*schema\\\["pattern"\\\].*instance.*\)' "\$CHECK_FILE"$""")

def cmd_c33(argv):
    # argv: unified -U0 diff of docs/tasks/034-verify.sh against 062's base. Task 069: the ONLY change allowed is task
    # 064's re-pin of C3.3 -- the one call-text line plus the comment lines that follow it and name task 064. An empty
    # diff (034 untouched) passes. C3.4 (re.fullmatch stays forbidden) and every other line stay fully protected.
    lines = read(argv[0]).splitlines()
    if not [l for l in lines if l.strip()]:
        print("  034-verify.sh is untouched since the base")
        return 0
    rc = 0
    hunks = [l for l in lines if l.startswith("@@")]
    removed = [l[1:] for l in lines if l.startswith("-") and not l.startswith("---")]
    added = [l[1:] for l in lines if l.startswith("+") and not l.startswith("+++")]
    print("  034-verify.sh differs from the base: %d hunk(s), %d line(s) removed, %d added" % (len(hunks), len(removed), len(added)))
    if len(hunks) != 1:
        print("FAILED: expected exactly 1 hunk (the C3.3 call-text line and its comment), found %d" % len(hunks)); rc = 1
    if removed != [OLD_C33]:
        print("FAILED: the only line that may be removed is C3.3's old call text; removed: %r" % removed[:3]); rc = 1
    if not added or not NEW_C33.match(added[0]):
        print("FAILED: the first added line must be C3.3's re.search(schema[\"pattern\"], ... instance ...) call text; got %r" % (added[:1],)); rc = 1
    rest = added[1:]
    if not rest or not all(l.startswith("#") for l in rest) or len(rest) > 8:
        print("FAILED: after the call-text line only 1-8 comment lines may be added; got %d line(s), non-comment: %r" % (len(rest), [l for l in rest if not l.startswith("#")][:2])); rc = 1
    elif not any("task 064" in l for l in rest):
        print("FAILED: the added comment must name task 064"); rc = 1
    if rc == 0:
        print("  only task 064's C3.3 re-pin differs (call text + %d comment line(s) naming task 064); C3.4 untouched" % len(rest))
    return rc

def cmd_own(argv):
    # argv: old-blob-file new-file unified-diff-file
    old, new, diff = read(argv[0]), read(argv[1]), read(argv[2])
    norm = lambda t: re.sub(r"\s+", " ", t.replace("**", ""))
    rc = 0
    o_old = norm(old).count("one permitted in-place mutation")
    o_new = norm(new).count("one permitted in-place mutation")
    h_old = norm(old).count("The permitted in-place mutations")
    h_new = norm(new).count("The permitted in-place mutations")
    print("  whitespace-normalised count of 'one permitted in-place mutation': before %d, after %d" % (o_old, o_new))
    print("  whitespace-normalised count of 'The permitted in-place mutations': before %d, after %d" % (h_old, h_new))
    if o_old != 2:
        print("FAILED: positive control: the old quote must be found twice in the pre-change blob (found %d)" % o_old); rc = 1
    if o_new != 0:
        print("FAILED: the old quote still appears %d time(s)" % o_new); rc = 1
    if h_new < 1 or h_old != 0:
        print("FAILED: the new heading text is not found (after %d, before %d)" % (h_new, h_old)); rc = 1
    hunks = [l for l in diff.splitlines() if l.startswith("@@")]
    print("  hunks in the diff: %d" % len(hunks))
    if len(hunks) != 2:
        print("FAILED: expected exactly 2 hunks (the two quoting sentences), found %d" % len(hunks)); rc = 1
    # every hunk's removed side must contain the stale phrase 'permitted in-place' (the quoting sentence)
    removed, cur = [], None
    for l in diff.splitlines():
        if l.startswith("@@"):
            cur = []; removed.append(cur)
        elif cur is not None and l.startswith("-") and not l.startswith("---"):
            cur.append(l[1:])
    for i, r in enumerate(removed):
        if not any("permitted in-place" in x for x in r):
            print("FAILED: hunk %d removes lines that are not the quoting sentence" % (i + 1)); rc = 1
    return rc

if __name__ == "__main__":
    sys.exit({"diffids": cmd_diffids, "retire": cmd_retire, "mut": cmd_mut, "own": cmd_own, "c33": cmd_c33}[sys.argv[1]](sys.argv[2:]))
PYH
H=(python3 -I "$TMP/helper.py")

# ids of FAIL lines at column 0, first token each, sorted and comma-joined ("-" when none)
fail_ids() { local r; r=$(grep -E '^FAIL  ' "$1" | awk '{print $2}' | sort | paste -sd, -); printf '%s' "${r:--}"; }

# run one verify script in a clone dir; stdout+stderr to $3; echoes its exit code
run_verify() {
    local dir="$1" name="$2" out="$3"
    if [ "$name" = "057" ]; then
        ( cd "$dir" && bash "docs/tasks/057-verify.sh" "$NM" ) > "$out" 2>&1
    else
        ( cd "$dir" && bash "docs/tasks/${name}-verify.sh" ) > "$out" 2>&1
    fi
    echo $?
}

new_clone() {   # new_clone DEST REV : a fresh clone of the repository, detached at REV
    git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null || return 1
    git -C "$1" checkout -q --detach "$2" || return 1
}

SCRIPTS="006 008a 032 034 057"
SCRIPTS_LATER="$SCRIPTS 007a"   # task 069: 007a (merged after 062's base, so absent from AC1's inventory) is also run on HEAD and on a later branch
HEADREV="$(git -C "$ROOT" rev-parse HEAD)"

# ==================================================================================================
if [ "$MUTATE" = 0 ]; then

section "AC1 -- the red inventory, reproduced at the task's base ($BASE062), on main and on a probe branch"
# The scripts as they were at BASE062 are run in a clone where origin/main and main are BASE062 itself, which
# is the frame the inventory was captured in (before any edit). 'probe' adds one unrelated file.
new_clone "$TMP/old" "$BASE062" || fail "AC1.0 cannot clone $BASE062"
git -C "$TMP/old" update-ref refs/remotes/origin/main "$BASE062"
git -C "$TMP/old" update-ref refs/heads/main "$BASE062"
EXP_MAIN_006="C1.5b,C8.2,C8.3a,C8.3b,C9.4,C9.6"; EXP_PROBE_006="$EXP_MAIN_006"
EXP_MAIN_008a="changed,paths";                   EXP_PROBE_008a="$EXP_MAIN_008a"
EXP_MAIN_032="-";                                EXP_PROBE_032="S4"
EXP_MAIN_034="-";                                EXP_PROBE_034="-"
EXP_MAIN_057="S4,T2";                            EXP_PROBE_057="S1,S4,T2"
for n in $SCRIPTS; do
    rc=$(run_verify "$TMP/old" "$n" "$TMP/o.main.$n"); got=$(fail_ids "$TMP/o.main.$n"); var="EXP_MAIN_$n"
    printf '  main  %-5s exit=%s failing: %s\n' "$n" "$rc" "$got"
    [ "$got" = "${!var}" ] && pass "AC1.main.$n failing check ids at $BASE062 are exactly [${!var}]" || fail "AC1.main.$n expected failing ids [${!var}], got [$got]"
done
git -C "$TMP/old" checkout -q -b probe
echo probe > "$TMP/old/probe.txt"; git -C "$TMP/old" add probe.txt; git -C "${TMP}/old" "${GITID[@]}" commit -q -m probe
for n in $SCRIPTS; do
    rc=$(run_verify "$TMP/old" "$n" "$TMP/o.probe.$n"); got=$(fail_ids "$TMP/o.probe.$n"); var="EXP_PROBE_$n"
    printf '  probe %-5s exit=%s failing: %s\n' "$n" "$rc" "$got"
    [ "$got" = "${!var}" ] && pass "AC1.probe.$n failing check ids on the probe branch at $BASE062 are exactly [${!var}]" || fail "AC1.probe.$n expected failing ids [${!var}], got [$got]"
done

# --------------------------------------------------------------------------------------------------
section "AC2 -- each closed task's scope check is pinned at both ends, and the pins are the task's own"
check_pins() {   # name mergecommit basevar finalvar
    local n="$1" f="$ROOT/docs/tasks/$1-verify.sh" m="$2" bv="$3" fv="$4" lb lf rb rf fork
    lb=$(sed -n "s/^$bv=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}.*/\1/p" "$f" | head -n1)
    lf=$(sed -n "s/^$fv=\"\{0,1\}\([0-9a-f]\{7,\}\)\"\{0,1\}.*/\1/p" "$f" | head -n1)
    if [ -z "$lb" ] || [ -z "$lf" ]; then fail "AC2.$n cannot read $bv/$fv from $n-verify.sh (a search that finds nothing is broken)"; return; fi
    fork=$(git -C "$ROOT" merge-base "$m^1" "$m^2")
    rf=$(git -C "$ROOT" rev-parse "$m^2"); rb=$(git -C "$ROOT" rev-parse "$lb^{commit}" 2>/dev/null)
    printf '  %-5s merge %s: second parent (tip) %s, fork point %s; script pins %s=%s %s=%s\n' "$n" "$m" "${rf:0:7}" "${fork:0:7}" "$bv" "$lb" "$fv" "$lf"
    [ "$(git -C "$ROOT" rev-parse "$lf^{commit}" 2>/dev/null)" = "$rf" ] && pass "AC2.$n.final $fv=$lf is the last commit on the task branch (git rev-parse $m^2)" || fail "AC2.$n.final $fv=$lf is not $m^2 (${rf:0:7})"
    if [ "$n" = "006" ]; then
        # 006's check measures one escalation round, which started at be82c19 (inside the task); only the end is new.
        git -C "$ROOT" merge-base --is-ancestor "$fork" "$lb" && [ "$rb" != "$fork" ] && git -C "$ROOT" merge-base --is-ancestor "$lb" "$rf" \
            && pass "AC2.$n.base $bv=$lb is the round-3 base (the check's existing base, kept) and lies inside the task's range ${fork:0:7}..${rf:0:7}" \
            || fail "AC2.$n.base $bv=$lb is not inside the task's range"
    else
        [ "$rb" = "$fork" ] && pass "AC2.$n.base $bv=$lb is the task's fork point (git merge-base $m^1 $m^2)" || fail "AC2.$n.base $bv=$lb is not the fork point ${fork:0:7}"
    fi
}
check_pins 006 497af6f ROUND3_BASE ROUND3_FINAL
check_pins 008a a50daac BASE FINAL
check_pins 032 4d4a204 SCOPE_BASE SCOPE_FINAL
check_pins 057 e009ef0 BASE_COMMIT FINAL_COMMIT
for n in 032 057; do
    if grep -vE '^\s*#' "$ROOT/docs/tasks/$n-verify.sh" | grep -qE 'merge-base HEAD|BASE_REF|ls-files --others'; then fail "AC2.$n.moving the script still computes a moving base or counts untracked files"; else pass "AC2.$n.moving no moving merge-base, BASE_REF or untracked-file term remains in the scope checks"; fi
done

# --------------------------------------------------------------------------------------------------
section "AC3 -- every closed task's verify script passes on HEAD and on a later branch (an unrelated file added)"
new_clone "$TMP/head" "$HEADREV" || fail "AC3.0 cannot clone HEAD"
for n in $SCRIPTS_LATER; do
    rc=$(run_verify "$TMP/head" "$n" "$TMP/h.$n"); eval "HEADRC_$n=$rc"
    [ "$rc" = 0 ] && pass "AC3.head.$n $n-verify.sh exits 0 on HEAD" || { fail "AC3.head.$n $n-verify.sh exit $rc on HEAD; failing: $(fail_ids "$TMP/h.$n")"; }
done
git -C "$TMP/head" checkout -q -b later-task
echo "unrelated" > "$TMP/head/later-task-unrelated.txt"; git -C "$TMP/head" add later-task-unrelated.txt; git -C "$TMP/head" "${GITID[@]}" commit -q -m "later task adds an unrelated file"
for n in $SCRIPTS_LATER; do
    rc=$(run_verify "$TMP/head" "$n" "$TMP/l.$n")
    [ "$rc" = 0 ] && pass "AC3.later.$n $n-verify.sh exits 0 on a later branch" || fail "AC3.later.$n $n-verify.sh exit $rc on a later branch; failing: $(fail_ids "$TMP/l.$n")"
done

# --------------------------------------------------------------------------------------------------
section "AC5 -- the four retirements are complete and traceable (D-2)"
if "${H[@]}" retire "$TMP/head" > "$TMP/retire.out" 2>&1; then
    sed 's/^/ /' "$TMP/retire.out"
    pass "AC5.1 C1.5b, C8.2, C8.3a, C8.3b: no live label remains, each comment block names successors, and every named successor exists"
else
    sed 's/^/ /' "$TMP/retire.out"; fail "AC5.1 retirement blocks incomplete (see FAILED lines)"
fi
[ "${HEADRC_057:-1}" = 0 ] && pass "AC5.2 057-verify.sh (the named successor script) passes on HEAD" || fail "AC5.2 057-verify.sh does not pass on HEAD"

# --------------------------------------------------------------------------------------------------
section "AC6 -- no other check was removed or weakened: check ids before ($BASE062) and after ($FINAL062, task 062's last commit)"
PIN062_OK=1
if ! git -C "$ROOT" merge-base --is-ancestor "$FINAL062" HEAD 2>/dev/null; then
    fail "AC6.0 pinned commit $FINAL062 is not an ancestor of HEAD: AC6, AC7 and SELF cannot run"; PIN062_OK=0
fi
for n in 006 008a 032 057; do
    git -C "$ROOT" show "$BASE062:docs/tasks/$n-verify.sh" > "$TMP/old.$n.sh"
    git -C "$ROOT" show "$FINAL062:docs/tasks/$n-verify.sh" > "$TMP/new.$n.sh" 2>/dev/null
    allowed=""; [ "$n" = "006" ] && allowed="C1.5b,C8.1,C8.2,C8.3a,C8.3b"
    "${H[@]}" diffids "$n" "$TMP/old.$n.sh" "$TMP/new.$n.sh" "$allowed" > "$TMP/d.$n" 2>&1; rc=$?
    sed 's/^/  /' "$TMP/d.$n"
    [ $rc = 0 ] && [ "$PIN062_OK" = 1 ] && pass "AC6.$n only the allowed ids are missing from $n-verify.sh" || fail "AC6.$n unexpected check(s) missing from $n-verify.sh (see the line above)"
done
echo "  note: C8.1 is the PASS sibling of C8.2 (one 'if' printed C8.1 or C8.2): retiring C8.2 retires the pair, not a fifth check."
# Task 069: 034-verify.sh stays untouched since the base, EXCEPT for task 064's re-pin of C3.3 (the call-text line and
# its comment naming task 064), judged by the helper's c33 command; C3.4 and every other line stay protected.
# Task 070 (fix round): the LIVE guard beside the pinned id comparison above. Ids/labels at FINAL062 must all still exist at HEAD.
for n in $LIVE_IDS_SCRIPTS; do
    git -C "$ROOT" show "$FINAL062:docs/tasks/$n-verify.sh" > "$TMP/fin.$n.sh" 2>/dev/null
    git -C "$ROOT" show "HEAD:docs/tasks/$n-verify.sh" > "$TMP/hd.$n.sh"
    "${H[@]}" diffids "$n" "$TMP/fin.$n.sh" "$TMP/hd.$n.sh" "" > "$TMP/dl.$n" 2>&1; rc=$?
    sed 's/^/  live: /' "$TMP/dl.$n"
    [ $rc = 0 ] && [ "$PIN062_OK" = 1 ] && pass "AC6L.$n every check id of $n-verify.sh at $FINAL062 still exists at HEAD (live guard; additions are fine)" || fail "AC6L.$n a check id of $n-verify.sh that existed at $FINAL062 is gone at HEAD (deleted or renamed; see the line above)"
done
# Task 070: judged over 062's own range BASE062..FINAL062 (a later task may legitimately edit 034-verify.sh; that is
# that task's own scope check's business, and 064's C3.3 re-pin is exactly such a later edit).
git -C "$ROOT" diff -U0 "$BASE062" "$FINAL062" -- docs/tasks/034-verify.sh > "$TMP/034.diff" 2>/dev/null
if [ "$PIN062_OK" = 1 ] && "${H[@]}" c33 "$TMP/034.diff" > "$TMP/034.out" 2>&1; then
    sed 's/^/ /' "$TMP/034.out"; pass "AC6.034 034-verify.sh is untouched since the base, or differs only by task 064's C3.3 re-pin"
else
    sed 's/^/ /' "$TMP/034.out"; fail "AC6.034 034-verify.sh was modified beyond task 064's C3.3 re-pin (see FAILED lines)"
fi
# Task 070: the "after" count is 006-verify.sh as of task 062's last commit (a clone at FINAL062), not HEAD's.
new_clone "$TMP/f062" "$FINAL062" || fail "AC6.006.count cannot clone $FINAL062"
run_verify "$TMP/f062" 006 "$TMP/f.006" > /dev/null
n006_pass=$(grep -c '^PASS' "$TMP/f.006" 2>/dev/null); n006_fail=$(grep -c '^FAIL' "$TMP/f.006" 2>/dev/null)
b006_pass=$(grep -c '^PASS' "$TMP/o.main.006"); b006_fail=$(grep -c '^FAIL' "$TMP/o.main.006")
printf '  006-verify.sh evaluated checks: before %d (%d PASS, %d FAIL), after %d (%d PASS, %d FAIL)\n' $((b006_pass + b006_fail)) "$b006_pass" "$b006_fail" $((n006_pass + n006_fail)) "$n006_pass" "$n006_fail"
if [ "$LIVE_COUNT_GUARD" = 1 ]; then   # Task 070 (fix round): the LIVE guard beside the pinned count: HEAD's 006 evaluates at least as many checks as at FINAL062
    h006=$(( $(grep -c '^PASS' "$TMP/h.006") + $(grep -c '^FAIL' "$TMP/h.006") ))
    [ "$PIN062_OK" = 1 ] && [ "$h006" -ge $((n006_pass + n006_fail)) ] && pass "AC6L.006.count 006-verify.sh evaluates $h006 checks at HEAD, at least the $((n006_pass + n006_fail)) it evaluated at $FINAL062 (live guard)" || fail "AC6L.006.count 006-verify.sh evaluates $h006 checks at HEAD, fewer than at $FINAL062 ($((n006_pass + n006_fail))): a check was deleted"
fi
[ "$PIN062_OK" = 1 ] && [ $((n006_pass + n006_fail)) -gt 0 ] && [ $((b006_pass + b006_fail - 4)) = $((n006_pass + n006_fail)) ] && pass "AC6.006.count 006-verify.sh evaluates exactly 4 fewer checks than before (the four retired)" || fail "AC6.006.count 006-verify.sh evaluated-check count did not drop by exactly 4"

# --------------------------------------------------------------------------------------------------
section "AC7 -- contracts/ownership.md: only the stale quoting sentences changed (D-3)"
# Task 070: both sides are 062's range: BASE062 (before) and FINAL062 (after), never HEAD's contracts/ownership.md.
git -C "$ROOT" show "$BASE062:contracts/ownership.md" > "$TMP/own.old.md"
git -C "$ROOT" show "$FINAL062:contracts/ownership.md" > "$TMP/own.new.md" 2>/dev/null
git -C "$ROOT" diff -U0 "$BASE062" "$FINAL062" -- contracts/ownership.md > "$TMP/own.diff" 2>/dev/null
printf '  the literal grep from the spec: grep -c "one permitted in-place mutation" -> %s (vacuous: both quotes wrap across a line break, so it prints 0 before and after)\n' "$(grep -c 'one permitted in-place mutation' "$TMP/own.new.md")"
if [ "$PIN062_OK" = 1 ] && "${H[@]}" own "$TMP/own.old.md" "$TMP/own.new.md" "$TMP/own.diff" > "$TMP/own.out" 2>&1; then
    sed 's/^/ /' "$TMP/own.out"; pass "AC7.1 whitespace-normalised: old quote 2 -> 0, new heading text found, exactly two hunks, both on the quoting sentences"
else
    sed 's/^/ /' "$TMP/own.out"; fail "AC7.1 ownership.md change is wrong (see FAILED lines)"
fi
# Task 070 (fix round, F3): LIVE guard beside the pinned AC7.1: the stale quoting sentences are not re-introduced at HEAD.
ONORM=$(git -C "$ROOT" show HEAD:contracts/ownership.md | tr -s '[:space:]' ' ' | sed 's/\*\*//g')
if printf '%s' "$ONORM" | grep -qF 'The permitted in-place mutations' && ! printf '%s' "$ONORM" | grep -qF 'one permitted in-place mutation'; then
    pass "AC7.4 contracts/ownership.md at HEAD has the new heading text and no stale 'one permitted in-place mutation' quote (live guard)"
else fail "AC7.4 contracts/ownership.md at HEAD lacks 'The permitted in-place mutations' or carries the stale 'one permitted in-place mutation' quote again"; fi
[ "${HEADRC_032:-1}" = 0 ] && pass "AC7.2 032-verify.sh passes on HEAD with the edited ownership.md" || fail "AC7.2 032-verify.sh does not pass on HEAD"
if grep -q 'one permitted in-place' "$ROOT/docs/tasks/032-verify.sh"; then fail "AC7.3 032-verify.sh pins the old quote (it must be updated)"; else pass "AC7.3 032-verify.sh holds no pin on the old quote (nothing to update; there is no pin mutation to re-show)"; fi

# --------------------------------------------------------------------------------------------------
section "Scope of task 062 itself: files changed by commits whose subject starts 'Task 062' (no pin needed, immune to later branches)"
SELF=$(git -C "$ROOT" log --no-merges --grep='^Task 062' --format=%H "$BASE062..$FINAL062" 2>/dev/null | while read -r c; do git -C "$ROOT" diff-tree --no-commit-id --name-only -r "$c"; done | sort -u)
printf '%s\n' "$SELF" | sed 's/^/  /'
if [ -z "$SELF" ]; then fail "SELF.0 no commit with a 'Task 062' subject found between $BASE062 and $FINAL062 (a search that finds nothing is broken)"; else
    BAD=$(printf '%s\n' "$SELF" | grep -vE '^(docs/tasks/(006|008a|032|057)-verify\.sh|contracts/ownership\.md|docs/tasks/062-registry-test-maintenance\.md|docs/tasks/062-verify\.sh)$' || true)
    [ -z "$BAD" ] && pass "SELF.1 every file task 062 changed is inside its declared file scope" || fail "SELF.1 out of scope: $(printf '%s' "$BAD" | tr '\n' ' ')"
fi
[ -x "$ROOT/docs/tasks/062-verify.sh" ] && pass "SELF.2 062-verify.sh is executable" || fail "SELF.2 062-verify.sh is not executable"

# ==================================================================================================
else
# --mutate
section "AC4 / AC5 / AC6 mutations (temporary clone of HEAD; each mutation must turn the named check red, the restore green)"
new_clone "$TMP/m" "$HEADREV" || fail "AC4.0 cannot clone HEAD"

mutate() {   # mutate FILE OLD NEW one|first|all  -> applies, returns helper's rc
    "${H[@]}" mut "$TMP/m/$1" "$2" "$3" "$4"
}
restore() { git -C "$TMP/m" checkout -q -- "$1"; }
expect_red() {   # expect_red LABEL NAME EXPECTED_IDS(comma)   (runs script NAME in the clone and demands every expected id failing)
    local label="$1" n="$2" want="$3" rc got id miss=""
    rc=$(run_verify "$TMP/m" "$n" "$TMP/m.out"); got=$(fail_ids "$TMP/m.out")
    for id in ${want//,/ }; do case ",$got," in *",$id,"*) ;; *) miss="$miss $id" ;; esac; done
    if [ "$rc" != 0 ] && [ -z "$miss" ]; then pass "$label turns red: exit $rc, failing [$got]"; else fail "$label stayed green or missed [$miss ]: exit $rc, failing [$got]"; fi
}
expect_green() {
    local label="$1" n="$2" rc
    rc=$(run_verify "$TMP/m" "$n" "$TMP/m.out")
    [ "$rc" = 0 ] && pass "$label restored: exit 0" || fail "$label restored but exit $rc, failing [$(fail_ids "$TMP/m.out")]"
}
applies() { [ "$1" = 0 ] || { fail "$2: the mutation did not apply (a mutation that changes nothing proves nothing)"; return 1; }; }

# ---- 006
f=docs/tasks/006-verify.sh
mutate $f '\ndocs/tasks/006-verify.sh\n'"'"')' '\n'"'"')' one; applies $? "AC4.006.drop-path" && expect_red "AC4.006.drop-path (C9.3 equality list loses docs/tasks/006-verify.sh)" 006 "C9.4"
restore $f
mutate $f 'ROUND3_BASE="be82c19"' 'ROUND3_BASE="6a14f9b"' one; applies $? "AC4.006.widen-range" && expect_red "AC4.006.widen-range (range widened to the task fork point: tests/schemas now in range)" 006 "C9.4,C9.6"
restore $f
mutate $f 'ROUND3_FINAL="2241923"' 'ROUND3_FINAL="deadbee"' one; applies $? "AC4.006.bad-pin" && expect_red "AC4.006.bad-pin (unreachable pin must FAIL, never skip)" 006 "C9.7"
restore $f
expect_green "AC4.006" 006

# ---- 008a
f=docs/tasks/008a-verify.sh
mutate $f 'docs/contracts/README\.md$|' '' one; applies $? "AC4.008a.drop-path" && expect_red "AC4.008a.drop-path (declared-scope regex loses docs/contracts/README.md)" 008a "paths"
restore $f
mutate $f 'FINAL=9ccb3ec' 'FINAL=deadbee' one; applies $? "AC4.008a.bad-pin" && expect_red "AC4.008a.bad-pin (unreachable pin must FAIL, never skip)" 008a "pinned"
restore $f
expect_green "AC4.008a" 008a

# ---- 007a (task 069)
f=docs/tasks/007a-verify.sh
mutate $f 'tests/registry/|' '' one; applies $? "AC4.007a.drop-path" && expect_red "AC4.007a.drop-path (declared-scope regex loses tests/registry/)" 007a "files"
restore $f
mutate $f 'FINAL=aaf4260' 'FINAL=deadbee' one; applies $? "AC4.007a.bad-pin" && expect_red "AC4.007a.bad-pin (unreachable pin must FAIL, never skip)" 007a "pinned"
restore $f
expect_green "AC4.007a" 007a

# ---- 032
f=docs/tasks/032-verify.sh
mutate $f 'DECLARED_SCOPE="contracts/ownership.md
docs/contracts/README.md' 'DECLARED_SCOPE="docs/contracts/README.md' one; applies $? "AC4.032.drop-path" && expect_red "AC4.032.drop-path (declared-scope list loses contracts/ownership.md)" 032 "S4"
restore $f
mutate $f 'SCOPE_FINAL="76af1bb"' 'SCOPE_FINAL="deadbee"' one; applies $? "AC4.032.bad-pin" && expect_red "AC4.032.bad-pin (unreachable pin must FAIL, never skip)" 032 "S3a"
restore $f
expect_green "AC4.032" 032

# ---- 057
f=docs/tasks/057-verify.sh
mutate $f '|docs/contracts/README\.md' '' one; applies $? "AC4.057.drop-path" && expect_red "AC4.057.drop-path (S1 declared-scope regex loses docs/contracts/README.md)" 057 "S1"
restore $f
mutate $f 'BASE_COMMIT="a50daacd7e26235d1acdeadc7d19265f1b2d04e3"' 'BASE_COMMIT="3ab8f43d96013889a48e2005c57a75731b3d655f"' one && mutate $f 'FINAL_COMMIT="3ab8f43d96013889a48e2005c57a75731b3d655f"' 'FINAL_COMMIT="a50daacd7e26235d1acdeadc7d19265f1b2d04e3"' one; applies $? "AC4.057.swap-pins" && expect_red "AC4.057.swap-pins (range reversed: T2 positive control, S2 additions-only and S4 all see the wrong side)" 057 "T2,S2,S4"
restore $f
mutate $f 'FINAL_COMMIT="3ab8f43d96013889a48e2005c57a75731b3d655f"' 'FINAL_COMMIT="deadbee"' one; applies $? "AC4.057.bad-pin" && expect_red "AC4.057.bad-pin (unreachable pin must FAIL, never skip)" 057 "P0,T2"
restore $f
expect_green "AC4.057" 057

# ---- AC5: a successor id that does not exist reddens the retirement check
f=docs/tasks/006-verify.sh
mutate $f '#   successor:  057-textchecks.py required/born-pending' '#   successor:  057-textchecks.py required/born-pendingX' first; applies $? "AC5.mut1"
if "${H[@]}" retire "$TMP/m" > "$TMP/m.retire" 2>&1; then fail "AC5.mut1 a renamed successor id (textchecks) did NOT redden the retirement check"; else pass "AC5.mut1 renaming one successor id (057-textchecks.py) reddens the retirement check: $(grep FAILED "$TMP/m.retire" | head -n1)"; fi
restore $f
mutate docs/tasks/057-verify.sh '"O1 ' '"OX ' all; applies $? "AC5.mut2"
if "${H[@]}" retire "$TMP/m" > "$TMP/m.retire" 2>&1; then fail "AC5.mut2 a renamed 057-verify.sh id did NOT redden the retirement check"; else pass "AC5.mut2 renaming the 057-verify.sh id O1 reddens the retirement check: $(grep FAILED "$TMP/m.retire" | head -n1)"; fi
restore docs/tasks/057-verify.sh
if "${H[@]}" retire "$TMP/m" > "$TMP/m.retire" 2>&1; then pass "AC5.mut.restore the restored tree passes the retirement check"; else fail "AC5.mut.restore the restored tree fails the retirement check"; fi

# ---- AC6: a removed (renamed) check id reddens the id comparison
git -C "$ROOT" show "$BASE062:docs/tasks/032-verify.sh" > "$TMP/old.032.sh"
mutate docs/tasks/032-verify.sh '"S5 ' '"S5x ' all; applies $? "AC6.mut"
if "${H[@]}" diffids 032 "$TMP/old.032.sh" "$TMP/m/docs/tasks/032-verify.sh" "" > "$TMP/m.diff" 2>&1; then fail "AC6.mut removing check id S5 from 032-verify.sh did NOT redden the id comparison"; else pass "AC6.mut removing check id S5 reddens the id comparison: $(tail -n1 "$TMP/m.diff")"; fi
restore docs/tasks/032-verify.sh
fi

# --------------------------------------------------------------------------------------------------
printf '\n== RESULT ==\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
