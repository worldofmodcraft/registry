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
SRC=$(ls tools/registry/ownership*.py | wc -l)
[ "$SRC" -le 2 ] && ok "size: $SRC ownership source files (cap 2: ownership.py, ownership_cli.py)" || fail "size: $SRC ownership source files (cap 2)"
LINES=$(cat tools/registry/ownership*.py | wc -l)
echo "info  ownership source lines: $LINES (spec expects 300-450 changed, over the 300 cap; reason in the spec's Size section)"
if grep -nE '324218296|324089373|4831207' tools/registry/ownership*.py >/dev/null; then fail "tools/ hard-codes a real account id"; else ok "no real account or App id hard-coded in tools/ownership*"; fi
if grep -nE '^\s*(import|from)\s+(os|socket|subprocess|urllib|http|requests|ssl)\b' tools/registry/ownership.py >/dev/null; then fail "ownership.py imports an I/O module"; else ok "ownership.py imports no os/socket/subprocess/urllib/http"; fi
if grep -nE 'GITHUB_ACTOR|gh auth|hosts\.yml|\.claude' tools/registry/ownership*.py | grep -vE '^\S+:[0-9]+:\s*(#|""")|never|NEVER|not from' >/dev/null; then fail "ownership source reaches for actor/credential state"; else ok "ownership source reads no actor/credential state"; fi
python3 tools/registry/ownership_cli.py --help | grep -q "NEVER a merge signal" && ok "CLI help documents that accepted is never a merge signal (I8)" || fail "CLI help lacks the I8 warning"
python3 tools/registry/ownership_cli.py --help | grep -q "0 accepted, 1 rejected, 2 usage or internal error" && ok "CLI help documents the three exit codes" || fail "CLI help lacks the exit codes"
python3 tools/registry/ownership_cli.py --help | grep -q "authorises nobody" && ok "CLI help documents that r11_identity None authorises nobody" || fail "CLI help lacks the R11 default"
grep -q "ownership" docs/contracts/README.md && grep -q "task 039" docs/contracts/README.md && ok "criterion 12: docs/contracts/README.md names the ownership checker as built and 039 as owed" || fail "criterion 12: README not updated"
if grep -n "ownership checker (task 007b" docs/contracts/README.md | grep -qi "still to come"; then fail "README still lists the ownership checker as still to come"; else ok "README no longer lists the ownership checker as still to come"; fi
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
# declared file scope (only when origin/main is known)
if git rev-parse -q --verify origin/main >/dev/null 2>&1; then
  BAD=$(git diff --name-only origin/main...HEAD | grep -vE '^(tools/registry/ownership[a-z_]*\.py|tests/registry/test_ownership[a-z_]*\.py|docs/tasks/007b-registry-checker-ownership\.md|docs/tasks/007b-verify\.sh|docs/contracts/README\.md)$' || true)
  [ -z "$BAD" ] && ok "changed files all inside the declared scope" || fail "files outside the declared scope: $BAD"
  CH=$(git diff --name-only origin/main...HEAD -- tools/registry | grep -v ownership || true)
  [ -z "$CH" ] && ok "007a's modules are untouched" || fail "007a modules changed: $CH"
else
  fail "scope check cannot run: no origin/main in this clone (fetch it; a skipped check proves nothing)"
fi

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
