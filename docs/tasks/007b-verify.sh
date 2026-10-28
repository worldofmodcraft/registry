#!/usr/bin/env bash
#
# 007b-verify.sh -- the runnable verification artefact for task 007b (MANAGER.md 2c).
#
# Usage (from anywhere; it cd's to the repository root):
#   ./docs/tasks/007b-verify.sh            run the suite, a fresh-clone run, and the structural checks
#   ./docs/tasks/007b-verify.sh --mutate   break each guard in a scratch CLONE of the COMMITTED tree and require
#                                          the named tests to turn red (B3/B4/B6). WOM_TMP picks the scratch parent.
#
# Exit code: the number of failed checks (0 = everything passed). One line per check.
# Needs: git, python3. A missing tool is a FAILURE, never a skip. Reads no credential, reaches no network.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }

for tool in git python3; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

if [ "${1:-}" = "--mutate" ]; then
  if [ -n "$(git status --porcelain -- tools tests docs)" ]; then
    fail "uncommitted changes in tools/ tests/ docs/: mutations run against the COMMITTED tree, commit first"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
  fi
  N=$(python3 tests/registry/test_ownership_mutations.py --list | wc -l)
  [ "$N" -ge 45 ] && ok "mutation table has $N entries (floor 45)" || fail "mutation table has only $N entries"
  python3 tests/registry/test_ownership_mutations.py
  RC=$?
  [ "$RC" -eq 0 ] && ok "every mutation turned its named tests red" || fail "$RC mutation(s) did not turn their named tests red"
  echo "SUMMARY failed=$FAILS"
  exit "$FAILS"
fi

# 1. the whole registry suite (007a's tests must stay green beside ours), one line per test
OUT=$(python3 -B -m unittest discover -s tests/registry -v 2>&1)
RUNLINE=$(echo "$OUT" | grep -E '^Ran [0-9]+ tests')
N=$(echo "$RUNLINE" | grep -oE '[0-9]+' | head -1)
echo "$OUT" | tail -4
echo "$OUT" | tail -1 | grep -q '^OK' && ok "unittest: $RUNLINE, OK" || { fail "unittest not OK"; echo "$OUT" | grep -E '^(FAIL|ERROR)'; }
NO=$(echo "$OUT" | grep -cE '^test_.*\(test_ownership(_mutations)?\.' )
[ "$NO" -ge 75 ] && ok "ownership tests ran: $NO (floor 75)" || fail "only $NO ownership tests ran (floor 75): a search that finds nothing is broken"

# 1b. umbrella 11: the same suite passes in a FRESH CLONE of the committed tree, not only in this worktree
SCR=$(mktemp -d "${WOM_TMP:-${TMPDIR:-/tmp}}/wom007b-fresh.XXXXXX")
git clone -q --no-hardlinks . "$SCR/c" && git -C "$SCR/c" checkout -q "$(git rev-parse HEAD)" \
  && FRESH=$(cd "$SCR/c" && python3 -B -m unittest discover -s tests/registry 2>&1 | tail -1)
[ "$FRESH" = "OK" ] && ok "umbrella 11: fresh clone of HEAD runs the whole suite OK" || fail "umbrella 11: fresh clone: '$FRESH'"
rm -rf "$SCR"

# 2. one named line per acceptance criterion: >=1 passing test and none failing
crit() { # label pattern
  local P F
  P=$(echo "$OUT" | grep -cE "^($2).* \.\.\. ok$")
  F=$(echo "$OUT" | grep -cE "^($2).* \.\.\. (FAIL|ERROR)$")
  if [ "$P" -ge 1 ] && [ "$F" -eq 0 ]; then ok "$1: $P passing, 0 failing"; else fail "$1: $P passing, $F failing"; fi
}
crit "umbrella 4   id differs / username matches rejected; rename accepted" "test_r3_(reject_same_username|accept_rename)"
crit "umbrella 5   first publish binds; binding is not a bypass"            "test_(r4|r5|r6)_|test_r3_reject_(binding|rebinding)"
crit "umbrella 6   reserved namespaces by org membership, naming ADR-0119"  "test_(r7|r8|r9|i4|i5)_"
crit "umbrella 9   positive controls accepted"                              "test_(r3_accept|r4_accept|r5_accept|r7_accept|r10_accept|r11_accept|i3_accept|i7_accept)"
crit "umbrella 10  messages name the problem and the rule"                  "test_(r7_reject_non_member|r9_reject_everything|r10_reject_page_only|r2_reject_new_id|b1_matrix)"
crit "umbrella 14  fail-closed T1/T3, every author, ADR-0121 named"          "test_(b1_|fail_closed_)"
crit "B1           fail-closed matrix (6 kinds x 5 authors = 30 cells)"      "test_b1_matrix_every_cell"
crit "B2           takedown authority (R3/R7/R11)"                           "test_r11_"
crit "B3           every rule has accept+reject tests and a reddening mutation" "test_b3_"
crit "B4           the required mutations are all present"                   "test_b4_"
crit "B5           seam: no network / environ / open; bad inputs are errors" "test_b5_"
crit "B6           truncation and composition cells"                          "test_b6_|test_r11_reject_(malformed|reserved_list)"
crit "I1..I8       checker invariants"                                       "test_i[1-8]_"
crit "R1..R10      verdict rules"                                            "test_r(1|2|3|4|5|6|7|8|9|10)_"
crit "CLI          ownership_cli exit codes in unittest"                     "test_cli_exit_codes"

# 3. structural checks
# Task 071: the scope and size claims below describe 007b's OWN change, so they measure 007b's pinned PR range (registry PR #12,
# merge 70cedca), never HEAD or origin/main: BASE007B = merge-base of 70cedca's parents, FINAL007B = 70cedca^2 (its last commit).
# A later task that legitimately edits tools/registry/schema.py or adds a file no longer reddens this script.
# Task 089a1 (findings 3 and 4): the two README checks below are 007b's OWN change to docs/contracts/README.md, so they read the
# README blob at FINAL007B (`git show $FINAL007B:docs/contracts/README.md`), never HEAD; an unreadable pin FAILS them. Finding 4 was
# vacuous (the grep matched no line, so the branch always passed): it now also requires the positive statement that the README
# calls the ownership checker built, and a grep for the old wording that finds nothing is not accepted as the only evidence.
# Pins are full SHAs: BASE007B = `git merge-base 70cedca^1 70cedca^2`, FINAL007B = `git rev-parse 70cedca^2`.
BASE007B="fb76ee54aac413cd40fa61df31c3f11d8cbb76e3"
FINAL007B="17555d94323192eaf315c49818ff34b393f57aa2"
PINS_OK=1
for pin in "$BASE007B" "$FINAL007B"; do
  if git merge-base --is-ancestor "$pin" HEAD 2>/dev/null; then ok "pinned commit $pin is reachable from HEAD"; else fail "pinned commit $pin is not reachable from HEAD (a pin that cannot be read proves nothing; fetch the full history)"; PINS_OK=0; fi
done
if [ "$PINS_OK" -eq 1 ]; then
  SRC=$(git ls-tree -r --name-only "$FINAL007B" -- tools/registry | grep -cE '^tools/registry/ownership[^/]*\.py$')
  [ "$SRC" -le 2 ] && ok "size: $SRC ownership source files at $FINAL007B (cap 2: ownership.py, ownership_cli.py)" || fail "size: $SRC ownership source files at $FINAL007B (cap 2)"
else
  fail "size: cannot measure ownership source files at $FINAL007B (pin unreachable)"
fi
LINES=$(cat tools/registry/ownership*.py | wc -l)
echo "info  ownership source lines: $LINES (spec expects 300-450 changed, over the 300 cap; reason in the spec's Size section)"
if grep -nE '324218296|324089373|4831207' tools/registry/ownership*.py >/dev/null; then fail "tools/ hard-codes a real account id"; else ok "no real account or App id hard-coded in tools/ownership*"; fi
if grep -nE '^\s*(import|from)\s+(os|socket|subprocess|urllib|http|requests|ssl)\b' tools/registry/ownership.py >/dev/null; then fail "ownership.py imports an I/O module"; else ok "ownership.py imports no os/socket/subprocess/urllib/http"; fi
if grep -nE 'GITHUB_ACTOR|gh auth|hosts\.yml|\.claude' tools/registry/ownership*.py | grep -vE '^\S+:[0-9]+:\s*(#|""")|never|NEVER|not from' >/dev/null; then fail "ownership source reaches for actor/credential state"; else ok "ownership source reads no actor/credential state"; fi
python3 tools/registry/ownership_cli.py --help | grep -q "NEVER a merge signal" && ok "CLI help documents that accepted is never a merge signal (I8)" || fail "CLI help lacks the I8 warning"
python3 tools/registry/ownership_cli.py --help | grep -q "0 accepted, 1 rejected, 2 usage or internal error" && ok "CLI help documents the three exit codes" || fail "CLI help lacks the exit codes"
python3 tools/registry/ownership_cli.py --help | grep -q "authorises nobody" && ok "CLI help documents that r11_identity None authorises nobody" || fail "CLI help lacks the R11 default"
README_PATH=docs/contracts/README.md
if README_TXT=$(git show "$FINAL007B:$README_PATH" 2>/dev/null) && [ -n "$README_TXT" ]; then
  ok "$README_PATH is readable at 007b's pinned FINAL $FINAL007B (criterion 12 reads that copy, never HEAD)"
else
  README_TXT=""
  fail "pinned commit $FINAL007B (or $README_PATH at it) is not readable: criterion 12 has no README to read"
fi
if printf '%s\n' "$README_TXT" | grep -q "ownership" && printf '%s\n' "$README_TXT" | grep -q "task 039"; then ok "criterion 12: docs/contracts/README.md at $FINAL007B names the ownership checker as built and 039 as owed"; else fail "criterion 12: README at $FINAL007B not updated (or unreadable)"; fi
# the old wording ("ownership checker (task 007b" on a line saying "still to come") must be gone, AND the new wording must be present:
# the new statement is what makes this check non-vacuous (the old grep matches no line at FINAL007B, so absence alone proves nothing).
if [ -z "$README_TXT" ]; then fail "README-ownership-checker-built check cannot run: README at $FINAL007B unreadable (an empty input proves nothing)"
elif printf '%s\n' "$README_TXT" | grep -n "ownership checker (task 007b" | grep -qi "still to come"; then fail "README at $FINAL007B still lists the ownership checker as still to come"
elif printf '%s\n' "$README_TXT" | grep -qF '**built** (task 007b) is the ownership checker'; then ok "README at $FINAL007B lists the ownership checker as built (task 007b) and no longer as still to come"
else fail "README at $FINAL007B does not state that the ownership checker (task 007b) is built"; fi
# real exit codes through the real CLI
D=$(mktemp -d "${WOM_TMP:-${TMPDIR:-/tmp}}/wom007b-cli.XXXXXX")
mkdir -p "$D/old/mods/alice.tool" "$D/new/mods/alice.tool"
echo '{"namespaces":{"mc":{"owner":{"provider":"github","id":1,"name_at_registration":"org"}}}}' > "$D/res.json"
E='{"id":"alice:tool","owner":{"provider":"github","id":7,"name_at_registration":"alice"},"versions":[%s]}'
V='{"version":"1.0.0","commit":"'$(printf 'a%.0s' $(seq 40))'","source_url":"https://github.com/alice/tool","status":"pending"}'
printf "$E" "" > "$D/old/mods/alice.tool/entry.json"
printf "$E" "$V" > "$D/new/mods/alice.tool/entry.json"
CLI=(python3 tools/registry/ownership_cli.py --author-provider github --old-root "$D/old" --new-root "$D/new" --reserved-file "$D/res.json")
"${CLI[@]}" --author-id 7 --author-login alice mods/alice.tool/entry.json >/dev/null 2>&1; A=$?
"${CLI[@]}" --author-id 8 --author-login mallory mods/alice.tool/entry.json >/dev/null 2>&1; B=$?
"${CLI[@]}" --author-id 7 --r11-identity bogus mods/alice.tool/entry.json >/dev/null 2>&1; C=$?
rm -rf "$D"
[ "$A $B $C" = "0 1 2" ] && ok "CLI exit codes owner/stranger/usage = $A $B $C" || fail "CLI exit codes were '$A $B $C', expected '0 1 2'"
# declared file scope of 007b's own change: BASE007B..FINAL007B (Task 071; pinned, see above). Live-property checks elsewhere stay live.
if [ "$PINS_OK" -eq 1 ]; then
  BAD=$(git diff --name-only "$BASE007B" "$FINAL007B" | grep -vE '^(tools/registry/ownership[a-z_]*\.py|tests/registry/test_ownership[a-z_]*\.py|docs/tasks/007b-registry-checker-ownership\.md|docs/tasks/007b-verify\.sh|docs/contracts/README\.md)$' || true)
  [ -z "$BAD" ] && ok "changed files in the pinned range $BASE007B..$FINAL007B all inside the declared scope" || fail "files outside the declared scope: $BAD"
  CH=$(git diff --name-only "$BASE007B" "$FINAL007B" -- tools/registry | grep -v ownership || true)
  [ -z "$CH" ] && ok "007a's modules are untouched in the pinned range" || fail "007a modules changed: $CH"
else
  fail "scope check cannot run: pinned range $BASE007B..$FINAL007B unreachable (a skipped check proves nothing)"
  fail "007a-modules-unchanged check cannot run: pinned range unreachable"
fi

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
