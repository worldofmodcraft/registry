#!/usr/bin/env bash
#
# 008c-verify.sh -- runnable verification artefact for task 008c (MANAGER.md 2c).
#   ./docs/tasks/008c-verify.sh            run the suite + structural checks
#   ./docs/tasks/008c-verify.sh --mutate   break the module in scratch copies of the COMMITTED tree;
#                                          each named check must turn red
# Exit code = number of failed checks. Missing tools FAIL. No network, no key, no credential.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }
SCOPE_RE='tools/pipeline/write_back.py|tests/pipeline/test_write_back.py|docs/pipeline/build-pipeline.md|docs/tasks/008c-pipeline-write-back.md|docs/tasks/008c-verify.sh'

# The left side of the scope diff is the merge-base with the CURRENT main, so a merge of main into the
# branch does not drag main's files into the diff. A fixed ancestor commit would. If no main ref
# exists the check cannot run: that is a FAIL, never a skip.
scope_base() {
  local r
  for r in origin/main refs/heads/main; do
    if git rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1; then git merge-base HEAD "$r"; return $?; fi
  done
  return 1
}
# Prints out-of-scope changed files (one per line); returns 1 if the base cannot be computed.
scope_violations() {
  local b; b=$(scope_base) || return 1
  [ -n "$b" ] || return 1
  git diff --name-only "$b" HEAD | grep -vxE "$SCOPE_RE" || true
}

for tool in git python3 grep; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

export PYTHONDONTWRITEBYTECODE=1
MOD=tools/pipeline/write_back.py
TST=tests/pipeline/test_write_back.py


# ---------------------------------------------------------------- scope self-test (finding 5)
# Scenarios in throw-away repos, each judged by scope_violations (the real function) and, to prove
# the scenario is sensitive, by the OLD formula (diff against a fixed ancestor).
scope_selftest() {
  local T rc=0 first old
  T=$(mktemp -d "${TMPDIR:-/tmp}/w008c-scope.XXXXXX")
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
  mkrepo() { # $1 dir; leaves cwd inside it, on main, with one base commit
    mkdir "$1" && cd "$1" && g init -q && echo base > README && g add README && g commit -q -m base
    first=$(git rev-parse HEAD)
  }
  # A: main advances with an OUT-of-scope file, then is merged into the branch: must be GREEN
  ( mkrepo "$T/a" && g checkout -q -b task && mkdir -p tools/pipeline && echo x > tools/pipeline/write_back.py \
      && g add . && g commit -q -m work && g checkout -q main && echo m > main-only.txt && g add . && g commit -q -m "main moves" \
      && g checkout -q task && g merge -q --no-edit main
    new=$(scope_violations; echo "rc=$?"); old=$(git diff --name-only "$first...HEAD" | grep -vxE "$SCOPE_RE" || true)
    [ "$new" = "rc=0" ] && echo "ok    scope scenario merge-from-main: new check green" || { echo "FAIL  scope scenario merge-from-main: new check red: $new"; exit 1; }
    [ -n "$old" ] && echo "ok    scope scenario merge-from-main: old fixed-base formula is red (flags: $old), scenario is sensitive" || { echo "FAIL  scope scenario merge-from-main: old formula not red, scenario is not sensitive"; exit 1; }
  ) || rc=1
  # B: control, a stray out-of-scope commit on the branch: must be RED
  ( mkrepo "$T/b" && g checkout -q -b task && echo x > stray.txt && g add . && g commit -q -m stray
    new=$(scope_violations; echo "rc=$?")
    [ "$new" = "stray.txt
rc=0" ] && echo "ok    scope scenario stray-commit: new check red as it must be (flags stray.txt)" || { echo "FAIL  scope scenario stray-commit: not flagged: $new"; exit 1; }
  ) || rc=1
  # C: control, a stray commit on the branch AND a merge from main: still RED, and only for the stray file
  ( mkrepo "$T/c" && g checkout -q -b task && echo x > stray.txt && g add . && g commit -q -m stray && g checkout -q main \
      && echo m > main-only.txt && g add . && g commit -q -m "main moves" && g checkout -q task && g merge -q --no-edit main
    new=$(scope_violations; echo "rc=$?")
    [ "$new" = "stray.txt
rc=0" ] && echo "ok    scope scenario stray-plus-merge: flags only stray.txt" || { echo "FAIL  scope scenario stray-plus-merge: $new"; exit 1; }
  ) || rc=1
  # D: no main ref at all: the base cannot be computed, which must FAIL (never skip)
  ( mkrepo "$T/d" && g branch -m side && echo x > stray.txt && g add . && g commit -q -m x
    if scope_violations >/dev/null 2>&1; then echo "FAIL  scope scenario no-main-ref: check passed without a base"; exit 1; else echo "ok    scope scenario no-main-ref: check fails (no skip)"; fi
  ) || rc=1
  rm -r "$T"
  return $rc
}
if [ "${1:-}" = "--scope-selftest" ]; then
  scope_selftest; rc=$?; echo "SUMMARY scope-selftest rc=$rc"; exit "$rc"
fi

# ---------------------------------------------------------------- mutation mode
if [ "${1:-}" = "--mutate" ]; then
  if [ -n "$(git status --porcelain -- tools tests docs)" ]; then
    fail "uncommitted changes: mutations run against the COMMITTED tree, commit first"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
  fi
  SCR=$(mktemp -d "${TMPDIR:-/tmp}/w008c-mut.XXXXXX"); trap 'rm -r "$SCR"' EXIT
  BEFORE=$(sha256sum "$MOD" "$TST" docs/tasks/008c-verify.sh contracts/artifact-naming.md | sha256sum)
  # baseline must be green, or red means nothing
  git archive HEAD | tar -x -C "$SCR"
  ( cd "$SCR" && python3 tests/pipeline/run_checks.py --only test_write_back >"$SCR/base.out" 2>/dev/null )
  [ $? -eq 0 ] && ok "baseline green in scratch copy" || { fail "baseline not green"; echo "SUMMARY failed=$FAILS"; exit "$FAILS"; }
  fresh_t() { [ ! -e "$SCR/t" ] || rm -r "$SCR/t"; mkdir "$SCR/t"; }
  # id | file | old | new | check names that must be FAIL (space separated)
  run_mut() {
    local id="$1" file="$2" old="$3" new="$4"; shift 4
    fresh_t; git archive HEAD | tar -x -C "$SCR/t"
    if ! OLD="$old" NEW="$new" F="$SCR/t/$file" python3 -I - <<'PY'
import os,sys
p=os.environ["F"]; s=open(p,encoding="utf-8").read(); o=os.environ["OLD"]
if s.count(o)!=1: print("anchor found %d times (must be exactly 1)"%s.count(o)); sys.exit(1)
open(p,"w",encoding="utf-8").write(s.replace(o,os.environ["NEW"]))
PY
    then fail "mutation $id: anchor not found exactly once (broken search)"; return; fi
    ( cd "$SCR/t" && python3 tests/pipeline/run_checks.py --only test_write_back >"$SCR/m.out" 2>/dev/null )
    local bad=0
    for c in "$@"; do
      grep -qE "^CHECK [A-Za-z0-9]+\\.$c[A-Za-z0-9_]* FAIL$" "$SCR/m.out" || { bad=1; echo "      not red: $c"; }
    done
    [ $bad -eq 0 ] && ok "mutation $id: red -> $*" || fail "mutation $id did not turn the named check(s) red"
  }
  V='    version_obj["status"] = "published"'
  run_mut copy-commit-from-result $MOD "$V" "$V
    version_obj[\"commit\"] = result.get(\"commit\", version_obj[\"commit\"])" test_ac1_only_the_matching_version_changes
  run_mut drop-status-change $MOD "$V" "    pass" test_ac1_transition_validates_diffs_exactly
  run_mut mutate-input $MOD "out = copy.deepcopy(entry)" "out = entry" test_ac2_no_mutation_on_success
  run_mut accept-published-target $MOD 'if status != "pending":' 'if status not in ("pending", "published"):' test_ac2_status_published_removed_rejected_each_refused
  run_mut accept-rejected-target $MOD 'if status != "pending":' 'if status not in ("pending", "rejected"):' test_ac2_status_published_removed_rejected_each_refused
  run_mut skip-mod-comparison $MOD 'if result.get("id") != entry.get("id"):' 'if False:' test_ac2_result_from_another_mod
  run_mut skip-version-comparison $MOD 'v.get("version") == rv]' 'True]' test_ac2_result_for_another_version
  run_mut drop-key-set-guard $MOD 'if set(values) != set(FIVE_KEYS) or len(values) != len(FIVE_KEYS):' 'if False:' test_ac2_extra_key_guard_tested_directly
  run_mut drop-pattern-check $MOD 'if not _fullmatch(pat, values[k]):' 'if False:' test_ac2_bad_sha256_length test_ac2_http_source_archive test_ac2_published_at_not_rfc3339
  run_mut drop-key_id-from-values $MOD '            "key_id": art["key_id"],
' '' test_ac1_write_back_values_has_exactly_the_five_keys test_ac1_transition_validates_diffs_exactly
  run_mut missing-field-not-caught $MOD 'except (KeyError, TypeError)' 'except ZeroDivisionError' test_ac2_result_missing_each_needed_field
  run_mut no-duplicate-check $MOD 'if len(matches) > 1:' 'if False:' test_ac2_duplicate_matching_version
  run_mut host-changed $MOD 'ARCHIVE_HOST = "archive.worldofmodcraft.com"' 'ARCHIVE_HOST = "archive.worldofmodcraft.org"' test_ac5_worked_examples_byte_for_byte test_ac5_host_constant_and_contract_agree
  run_mut plus-encoded $MOD '    return f"https://{ARCHIVE_HOST}/{tag}/{tag}.tar.gz"' '    return f"https://{ARCHIVE_HOST}/{tag}/{tag}.tar.gz".replace("+", "%2B")' test_ac5_worked_examples_byte_for_byte test_ac5_no_percent_encoding_of_plus
  run_mut tag-not-repeated $MOD '/{tag}/{tag}.tar.gz"' '/{tag}/archive.tar.gz"' test_ac5_worked_examples_byte_for_byte test_ac5_shape_and_forbidden_characters
  run_mut trailing-slash $MOD '/{tag}/{tag}.tar.gz"' '/{tag}/{tag}.tar.gz/"' test_ac5_worked_examples_byte_for_byte test_ac5_shape_and_forbidden_characters
  run_mut reserved-check-dropped $MOD '        naming.check_namespace(namespace)' '        pass' test_ac2_source_archive_url_refusals test_ac5_injective_over_a_generated_set_and_reserved_names_refused
  run_mut semver-check-dropped $MOD 'if not _fullmatch(_PAT_SEMVER, version):' 'if False:' test_ac2_source_archive_url_refusals
  run_mut subprocess-imported $MOD 'import copy
' 'import copy
import subprocess
' test_ac6_module_imports_no_subprocess_or_network_library
  run_mut contract-changed contracts/artifact-naming.md 'https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz`
   - signature URL' 'https://archive.worldofmodcraft.com/mc.hello-world-1.0.1/mc.hello-world-1.0.0.tar.gz`
   - signature URL' test_ac5_host_constant_and_contract_agree
  run_mut ascii-flag-dropped $MOD 're.fullmatch(pattern, value, re.ASCII)' 're.fullmatch(pattern, value)' test_fix1_non_ascii_digit_in_version_refused_by_source_archive_url test_fix1_non_ascii_digit_in_published_at_refused
  run_mut pending-shape-dropped $MOD 'if set(entry["versions"][idx]) != PENDING_KEYS:' 'if False:' test_fix2_pending_shape_stray_and_preexisting_keys_refused test_fix2_missing_pending_key_refused
  # finding 5: the scope check reverts to a fixed ancestor as its left side -> the self-test must go red
  mkdir "$SCR/s" && git show HEAD:docs/tasks/008c-verify.sh > "$SCR/s/v.sh"
  if [ "$(grep -c 'if git rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1; then git merge-base HEAD "$r"; return $?; fi' "$SCR/s/v.sh")" != 1 ]; then
    fail "mutation scope-fixed-base: anchor not found exactly once (broken search)"
  else
    sed 's#git merge-base HEAD "$r"; return $?;#git rev-list --max-parents=0 HEAD | tail -1; return 0;#' "$SCR/s/v.sh" > "$SCR/s/m.sh"
    cmp -s "$SCR/s/v.sh" "$SCR/s/m.sh" && fail "mutation scope-fixed-base: sed changed nothing" || {
      ( cd "$SCR" && bash "$SCR/s/m.sh" --scope-selftest >"$SCR/s/out" 2>&1 )
      grep -q "^FAIL  scope scenario merge-from-main" "$SCR/s/out" && ok "mutation scope-fixed-base: red -> scope scenario merge-from-main" || { fail "mutation scope-fixed-base not red"; cat "$SCR/s/out"; }
    }
  fi
  # file-adding mutation: a second module hard-codes the host
  fresh_t; git archive HEAD | tar -x -C "$SCR/t"
  echo 'U = "https://archive.worldofmodcraft.com/x"' > "$SCR/t/tools/pipeline/other_hardcode.py"
  ( cd "$SCR/t" && python3 tests/pipeline/run_checks.py --only test_write_back >"$SCR/m.out" 2>/dev/null )
  grep -q "^CHECK .*test_ac5_host_is_written_only_in_write_back_py_under_tools FAIL$" "$SCR/m.out" \
    && ok "mutation second-module-hardcodes-host: red" || fail "mutation second-module-hardcodes-host not red"
  AFTER=$(sha256sum "$MOD" "$TST" docs/tasks/008c-verify.sh contracts/artifact-naming.md | sha256sum)
  [ "$BEFORE" = "$AFTER" ] && ok "real tree byte-identical before/after (mutations ran in scratch copies)" || fail "real tree changed"
  echo "SUMMARY mutate failed=$FAILS"; exit "$FAILS"
fi

# ---------------------------------------------------------------- normal mode
OUT=$(python3 tests/pipeline/run_checks.py --only test_write_back 2>/tmp/w008c-stderr.$$)
PASSN=$(echo "$OUT" | grep -c '^CHECK .* PASS$')
FAILN=$(echo "$OUT" | grep -c '^CHECK .* FAIL$')
echo "$OUT" | grep '^CHECK .* FAIL$' | sed 's/^/FAIL  /'
echo "suite: $PASSN passed, $FAILN failed"
[ "$FAILN" -eq 0 ] || { fail "$FAILN suite check(s) failed"; cat /tmp/w008c-stderr.$$ >&2; }
rm -f /tmp/w008c-stderr.$$
[ "$PASSN" -ge 30 ] && ok "suite ran at least 30 checks ($PASSN)" || fail "suite ran only $PASSN checks (floor 30)"
for pat in test_ac1_ test_ac2_ test_ac3_ test_ac5_ test_ac6_; do
  P=$(echo "$OUT" | grep -c "^CHECK .*$pat.* PASS$"); F=$(echo "$OUT" | grep -c "^CHECK .*$pat.* FAIL$")
  [ "$P" -ge 1 ] && [ "$F" -eq 0 ] && ok "$pat*: $P passing, 0 failing" || fail "$pat*: $P passing, $F failing"
done

# AC3: the corpus selection is enumerated here and must be non-empty
COUNTS=$(cd tests/pipeline && python3 -I -c "
import sys; sys.path.insert(0,'.')
import test_write_back as t
print(len(t.t1_accept_rows()), len(t.t1_reject_rows()))" 2>&1)
set -- $COUNTS
if [ "${1:-0}" -gt 0 ] 2>/dev/null && [ "${2:-0}" -gt 0 ] 2>/dev/null; then ok "AC3 corpus selection: $1 T1 accept rows, $2 T1 reject rows with a pending version (both > 0)"; else fail "AC3 corpus selection empty or broken: $COUNTS"; fi

# AC5: contract <-> constant <-> typed literals
CHOST=$(grep -o 'source_archive = "https://[^/"]*/' contracts/artifact-naming.md | sed 's#.*//##; s#/$##')
[ -n "$CHOST" ] && ok "contract names host: $CHOST" || fail "host not found in contract (broken search)"
MHOST=$(python3 -I -c "import sys; sys.path.insert(0,'tools/pipeline'); import write_back; print(write_back.ARCHIVE_HOST)")
[ "$CHOST" = "$MHOST" ] && ok "constant ARCHIVE_HOST equals the contract's host" || fail "constant '$MHOST' != contract '$CHOST'"
for ex in 'https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz' 'https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz'; do
  grep -qF "\`$ex\`" contracts/artifact-naming.md && ok "contract contains worked example $ex" || fail "contract lacks $ex"
  grep -qF "$ex" $TST && ok "test types worked example literally" || fail "test lacks $ex"
done
# host single-source grep with positive control
PC=$(mktemp -d); echo 'U = "https://archive.worldofmodcraft.com/x"' > "$PC/c.py"
grep -rlF archive.worldofmodcraft.com "$PC" >/dev/null && ok "positive control: host grep finds a planted hardcode" || fail "host grep is blind"
HITS=$(grep -rlF archive.worldofmodcraft.com tools --include='*.py' | tr '\n' ' ')
[ "$HITS" = "tools/pipeline/write_back.py " ] && ok "host appears under tools/ only in write_back.py" || fail "host appears in: $HITS"
# AC6 grep with positive control
echo 'import subprocess' > "$PC/c.py"
grep -qE '^\s*(import|from)\s+(subprocess|socket|ssl|urllib|http|requests|httpx|aiohttp)\b' "$PC/c.py" && ok "positive control: import grep finds subprocess" || fail "import grep is blind"
rm -r "$PC"
grep -qE '^\s*(import|from)\s+(subprocess|socket|ssl|urllib|http|requests|httpx|aiohttp)\b' $MOD && fail "write_back.py imports subprocess/network" || ok "write_back.py imports neither subprocess nor a network library"

# docs
grep -q '^## Write-back (task 008c)' docs/pipeline/build-pipeline.md && ok "build-pipeline.md has the write-back section" || fail "write-back section missing"
grep -q '\[unverified\] Nothing here checks a hash against a tarball' docs/pipeline/build-pipeline.md && ok "[unverified] hash note recorded" || fail "[unverified] note missing"

# hygiene and scope (left side = merge-base with the current main; see scope_base)
[ -x docs/tasks/008c-verify.sh ] && ok "verify script executable" || fail "verify script not executable"
git ls-files | grep -E '(__pycache__|\.pyc$)' >/dev/null && fail "bytecode tracked" || ok "no bytecode tracked"
scope_selftest >"/tmp/w008c-scope.$$" 2>&1 && ok "scope check self-test (merge-from-main green, stray commit red, no main ref fails)" || { fail "scope self-test failed"; cat "/tmp/w008c-scope.$$"; }
grep '^ok' "/tmp/w008c-scope.$$" | sed 's/^/        /'; rm -f "/tmp/w008c-scope.$$"
if SB=$(scope_base); then
  CH=$(git diff --name-only "$SB" HEAD)
  [ -n "$CH" ] && ok "changed files since merge-base ${SB:0:7} with main: $(echo $CH | wc -w)" || fail "no changes since base (broken search)"
  BAD=$(scope_violations || echo "BASE-ERROR")
  [ -z "$BAD" ] && ok "all changes inside the declared file scope" || fail "out of scope: $BAD"
else fail "no origin/main or refs/heads/main: scope cannot be checked (never skipped)"; fi

echo "SUMMARY failed=$FAILS"; exit "$FAILS"
