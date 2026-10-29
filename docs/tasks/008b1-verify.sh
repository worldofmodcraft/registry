#!/usr/bin/env bash
#
# 008b1-verify.sh -- runnable verification artefact for task 008b-1 (MANAGER.md 2c): the pipeline planner.
#   ./docs/tasks/008b1-verify.sh            run the suite + structural checks + the criterion-12 state checks
#   ./docs/tasks/008b1-verify.sh --mutate   break the module in scratch copies of the COMMITTED tree;
#                                           each named check must turn red
#   ./docs/tasks/008b1-verify.sh --scope-selftest   only the scope-check self-test
# Exit code = number of failed checks. Missing tools FAIL. No network, no key, no credential.
# Criteria covered: 3, 12, 17 (a)-(g), 13 (this script), 18 (docs). There are no [live] criteria in this part.
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }
SCOPE_RE='tools/pipeline/plan_pending.py|tests/pipeline/test_plan_pending.py|docs/pipeline/build-pipeline.md|docs/tasks/008b1-pipeline-plan.md|docs/tasks/008b1-verify.sh'

# Task 101: the own-change scope check reads 008b-1's MERGED range, fixed by three pins (full 40-character SHAs), never HEAD
# and never the current main: a later merge of main into any branch cannot change what this range contains (REVIEW-CHECKLIST
# item 12). M = the merge of registry PR #29; BASE = git merge-base M^1 M^2; FINAL = M^2. The pins are re-derived from M below
# (check "scope pins re-derived from the merge commit") and 101-verify.sh recomputes them independently. There is no
# environment override. A pin that is not a full SHA, does not resolve, or is not BASE <= FINAL is a FAIL, never a skip.
PIN_M="dd7da2d79fc278597762cce862b48cc48434f816"
PIN_BASE="32c641b5f56139a86c820f0b16d522c0f991d207"
PIN_FINAL="2f179d08a9786ba94cb2f6c6fc2da4bf0ba5ffca"
pin_full() { [[ "$1" =~ ^[0-9a-f]{40}$ ]] && git cat-file -e "$1^{commit}" 2>/dev/null; }
# Prints out-of-scope files changed in PIN_BASE..PIN_FINAL (one per line); returns 1 if the range cannot be computed.
scope_violations() {
  local d
  pin_full "$PIN_BASE" && pin_full "$PIN_FINAL" || return 1
  git merge-base --is-ancestor "$PIN_BASE" "$PIN_FINAL" || return 1
  d=$(git diff --name-only "$PIN_BASE" "$PIN_FINAL") || return 1
  [ -z "$d" ] || printf '%s\n' "$d" | grep -vxE "$SCOPE_RE" || true
}

for tool in git python3 grep sed sha256sum; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

export PYTHONDONTWRITEBYTECODE=1
MOD=tools/pipeline/plan_pending.py
TST=tests/pipeline/test_plan_pending.py
SELF=docs/tasks/008b1-verify.sh

# ---------------------------------------------------------------- scope self-test (finding 5, re-pinned by task 101)
# Scenarios in throw-away repos. Each is judged by scope_violations (the real function, with PIN_BASE/PIN_FINAL assigned
# inside the scenario's subshell to that repo's commits) and, to prove the scenario is sensitive, by the OLD formula
# (a diff that ends at HEAD, which a merge of main into the branch drags out-of-scope files into).
scope_selftest() {
  local T rc=0 first old
  T=$(mktemp -d "${TMPDIR:-/tmp}/w008b1-scope.XXXXXX")
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  g() { git -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
  mkrepo() { # $1 dir; leaves cwd inside it, on main, with one base commit
    mkdir "$1" && cd "$1" && g init -q && echo base > README && g add README && g commit -q -m base
    first=$(git rev-parse HEAD)
  }
  # A: the branch's range is pinned, then main advances with an OUT-of-scope file and is merged into the branch: must be GREEN
  ( mkrepo "$T/a" && g checkout -q -b task && mkdir -p tools/pipeline && echo x > tools/pipeline/plan_pending.py \
      && g add . && g commit -q -m work && PIN_FINAL=$(git rev-parse HEAD) && PIN_BASE=$first \
      && g checkout -q main && echo m > main-only.txt && g add . && g commit -q -m "main moves" \
      && g checkout -q task && g merge -q --no-edit main
    new=$(scope_violations; echo "rc=$?"); old=$(git diff --name-only "$first" HEAD | grep -vxE "$SCOPE_RE" || true)
    [ "$new" = "rc=0" ] && echo "ok    scope scenario merge-from-main: pinned-range check green" || { echo "FAIL  scope scenario merge-from-main: pinned-range check red: $new"; exit 1; }
    [ -n "$old" ] && echo "ok    scope scenario merge-from-main: old HEAD-ended formula is red (flags: $old), scenario is sensitive" || { echo "FAIL  scope scenario merge-from-main: old formula not red, scenario is not sensitive"; exit 1; }
  ) || rc=1
  # B: control, a stray out-of-scope commit inside the pinned range: must be RED
  ( mkrepo "$T/b" && g checkout -q -b task && echo x > stray.txt && g add . && g commit -q -m stray && PIN_FINAL=$(git rev-parse HEAD) && PIN_BASE=$first
    new=$(scope_violations; echo "rc=$?")
    [ "$new" = "stray.txt
rc=0" ] && echo "ok    scope scenario stray-commit: check red as it must be (flags stray.txt)" || { echo "FAIL  scope scenario stray-commit: not flagged: $new"; exit 1; }
  ) || rc=1
  # C: control, a stray commit inside the range AND a later merge from main: still RED, and only for the stray file
  ( mkrepo "$T/c" && g checkout -q -b task && echo x > stray.txt && g add . && g commit -q -m stray && PIN_FINAL=$(git rev-parse HEAD) && PIN_BASE=$first \
      && g checkout -q main && echo m > main-only.txt && g add . && g commit -q -m "main moves" && g checkout -q task && g merge -q --no-edit main
    new=$(scope_violations; echo "rc=$?")
    [ "$new" = "stray.txt
rc=0" ] && echo "ok    scope scenario stray-plus-merge: flags only stray.txt" || { echo "FAIL  scope scenario stray-plus-merge: $new"; exit 1; }
  ) || rc=1
  # D: pins that cannot be used must FAIL (never skip): not a full SHA, a full SHA that does not exist, FINAL not a descendant of BASE
  ( mkrepo "$T/d" && echo x > stray.txt && g add . && g commit -q -m x
    head=$(git rev-parse HEAD); bad=0
    PIN_BASE=${first:0:7} PIN_FINAL=$head; scope_violations >/dev/null 2>&1 && { echo "FAIL  scope scenario bad-pin: a 7-character BASE passed"; bad=1; }
    PIN_BASE=deadbee PIN_FINAL=$head; scope_violations >/dev/null 2>&1 && { echo "FAIL  scope scenario bad-pin: BASE deadbee passed"; bad=1; }
    PIN_BASE=$first PIN_FINAL=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef; scope_violations >/dev/null 2>&1 && { echo "FAIL  scope scenario bad-pin: a nonexistent full-SHA FINAL passed"; bad=1; }
    PIN_BASE=$head PIN_FINAL=$first; scope_violations >/dev/null 2>&1 && { echo "FAIL  scope scenario bad-pin: FINAL not a descendant of BASE passed"; bad=1; }
    PIN_BASE=$first PIN_FINAL=$head; v=$(scope_violations; echo "rc=$?")
    [ "$v" = "stray.txt
rc=0" ] || { echo "FAIL  scope scenario bad-pin: the valid control pins did not flag stray.txt: $v"; bad=1; }
    [ $bad -eq 0 ] && echo "ok    scope scenario bad-pin: 7-char, nonexistent, deadbee and reversed pins all fail (fail, never pass); valid pins still flag" || exit 1
  ) || rc=1
  rm -r "$T"
  return $rc
}
if [ "${1:-}" = "--scope-selftest" ]; then
  scope_selftest; rc=$?; echo "SUMMARY scope-selftest rc=$rc"; exit "$rc"
fi



# ---------------------------------------------------------------- criterion 12 state checks
# Plans a throw-away registry state with the real CLI. $1 = state dir. Echoes "rc=<n> build=<n> refuse=<n> skip=<n> fault=<n>".
plan_counts() {
  local d="$1" empty; empty=$(mktemp "${TMPDIR:-/tmp}/w008b1-empty.XXXXXX")
  local out rc
  out=$(python3 -I "$MOD" --registry "$d" --head-sha 0123456789abcdef0123456789abcdef01234567 --branches "$empty" --archive-logs "$empty" 2>/dev/null); rc=$?
  rm -f "$empty"
  printf '%s' "$out" | python3 -I -c "
import json,sys
raw=sys.stdin.read()
if not raw.strip(): print('rc=$rc nodoc'); sys.exit(0)
d=json.loads(raw); print('rc=$rc ' + ' '.join('%s=%d'%(k,len(d[k])) for k in ('build','refuse','skip','fault')))"
}
# Writes a registry state: $1 dir, $2 = comma-separated statuses of the versions of mods/mc.a/entry.json.
write_state() {
  python3 -I - "$1" "$2" <<'PY'
import json, os, sys
root, statuses = sys.argv[1], sys.argv[2].split(",")
ex = {"source_archive": "https://archive.worldofmodcraft.com/x/x.tar.gz", "source_sha256": "0" * 64, "signature": "s",
      "key_id": "E7A1B2C3D4E5F607", "published_at": "2026-10-28T10:00:00Z"}
vs = []
for i, st in enumerate(statuses):
    v = {"version": "1.%d.0" % i, "commit": "a" * 40, "source_url": "https://example.invalid/m.git", "status": st}
    if st in ("published", "removed"): v.update(ex)
    if st == "removed": v["reason"] = "legal"
    if st == "rejected": v.update(reason="r", build_log_url="https://example.invalid/l")
    vs.append(v)
os.makedirs(os.path.join(root, "mods", "mc.a"))
json.dump({"id": "mc:a", "owner": {"provider": "github", "id": 1, "name_at_registration": "n"}, "versions": vs},
          open(os.path.join(root, "mods", "mc.a", "entry.json"), "w"))
PY
}
state_checks() {
  local T rc=0 got; T=$(mktemp -d "${TMPDIR:-/tmp}/w008b1-state.XXXXXX")
  write_state "$T/noop" "published,removed,rejected"
  got=$(plan_counts "$T/noop")
  [ "$got" = "rc=0 build=0 refuse=0 skip=0 fault=0" ] && echo "ok    [12] a state with zero pending versions plans empty, exit 0 ($got)" || { echo "FAIL  [12] zero-pending state: $got"; rc=1; }
  # control: the SAME check on a state that still has a pending version must NOT pass (the check is sensitive)
  write_state "$T/pending" "published,pending"
  got=$(plan_counts "$T/pending")
  [ "$got" = "rc=0 build=1 refuse=0 skip=0 fault=0" ] && echo "ok    [12] control: a state with one pending version plans build=1, so the no-op check above would be red on it ($got)" || { echo "FAIL  [12] control state: $got"; rc=1; }
  [ "$got" != "rc=0 build=0 refuse=0 skip=0 fault=0" ] && echo "ok    [12] control differs from the no-op result" || { echo "FAIL  [12] control is indistinguishable from the no-op"; rc=1; }
  mkdir "$T/emptyreg"
  got=$(plan_counts "$T/emptyreg")
  [ "$got" = "rc=0 build=0 refuse=0 skip=0 fault=0" ] && echo "ok    [12] a registry without a mods/ directory plans empty, exit 0" || { echo "FAIL  [12] empty registry: $got"; rc=1; }
  got=$(plan_counts "$T/does-not-exist")
  [ "$got" = "rc=1 nodoc" ] && echo "ok    [17f] an unreadable state exits 1 and writes no document ($got)" || { echo "FAIL  [17f] missing state: $got"; rc=1; }
  rm -r "$T"
  return $rc
}

# ---------------------------------------------------------------- mutation mode
if [ "${1:-}" = "--mutate" ]; then
  if [ -n "$(git status --porcelain -- tools tests docs)" ]; then
    fail "uncommitted changes: mutations run against the COMMITTED tree, commit first"
    echo "SUMMARY failed=$FAILS"; exit "$FAILS"
  fi
  SCR=$(mktemp -d "${TMPDIR:-/tmp}/w008b1-mut.XXXXXX"); trap 'rm -r "$SCR"' EXIT
  FILES="$MOD $TST $SELF tools/pipeline/naming.py tools/pipeline/write_back.py contracts/artifact-naming.md"
  BEFORE=$(sha256sum $FILES | sha256sum)
  # positive control: the unmodified planner passes every planner check, or red means nothing
  git archive HEAD | tar -x -C "$SCR"
  ( cd "$SCR" && python3 -I tests/pipeline/run_checks.py --only test_plan_pending >"$SCR/base.out" 2>/dev/null )
  [ $? -eq 0 ] && ok "baseline green in scratch copy ($(grep -c '^CHECK .* PASS$' "$SCR/base.out") checks)" || { fail "baseline not green"; echo "SUMMARY failed=$FAILS"; exit "$FAILS"; }
  fresh_t() { [ ! -e "$SCR/t" ] || rm -r "$SCR/t"; mkdir "$SCR/t"; }
  # id | file | old | new | check-name prefixes that must be FAIL (a prefix is matched after "CHECK <Class>.")
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
    ( cd "$SCR/t" && python3 -I tests/pipeline/run_checks.py --only test_plan_pending >"$SCR/m.out" 2>/dev/null )
    local bad=0
    for c in "$@"; do
      grep -qE "^CHECK [A-Za-z0-9]+\\.$c[A-Za-z0-9_]* FAIL$" "$SCR/m.out" || { bad=1; echo "      not red: $c"; }
    done
    [ $bad -eq 0 ] && ok "mutation $id: red -> $*" || fail "mutation $id did not turn the named check(s) red"
  }
  # --- criterion 3 (one character of a helper's output)
  run_mut c3-tag-separator tools/pipeline/naming.py '    return f"{ns}.{nm}-{version}"' '    return f"{ns}.{nm}_{version}"' test_c3_example1_tag_assets_urls test_c3_example2_derivation_only_never_published
  run_mut c3-signature-suffix tools/pipeline/naming.py 'f"{tag}.tar.gz.minisig"' 'f"{tag}.tar.gz.minisign"' test_c3_example1_tag_assets_urls
  run_mut c3-release-url tools/pipeline/naming.py 'releases/download/{tag}/{asset}' 'releases/downloads/{tag}/{asset}' test_c3_example1_tag_assets_urls test_c3_example2_derivation_only_never_published
  run_mut c3-source-archive-url tools/pipeline/write_back.py '{tag}/{tag}.tar.gz"' '{tag}/{tag}.tar.gz2"' test_c3_example1_tag_assets_urls test_c3_example2_derivation_only_never_published
  # --- criterion 17
  run_mut c17-ignore-version-input $MOD 'only = d["version"]' 'only = None' test_c17_version_input_builds_only_that_version test_c17_version_input_refused_exit_1
  run_mut c17-accept-published $MOD 'if v["status"] != "pending":' 'if v["status"] not in ("pending", "published"):' test_c12_published_removed_rejected_appear_nowhere test_c17_version_input_refused_exit_1
  run_mut c17a-drop-branch-check $MOD 'if branch in branches:' 'if False:' test_c17a_existing_branch_is_skipped_not_built test_c17a_summarize_over_a_skip_plan
  run_mut c17b-invalid-entry-treated-valid $MOD '        _validate(entry, schema, "$")' '        pass' test_c17b_invalid_entry_is_a_fault test_c17b_each_kind_of_invalid_entry
  run_mut c17b-ecma-digits-dropped $MOD '_PATTERN_CACHE[p] = wb._ecma_digits(p)' '_PATTERN_CACHE[p] = p' test_c17b_each_kind_of_invalid_entry
  run_mut c17b-duplicate-version-allowed $MOD 'if v["version"] in seen:' 'if False:' test_c17b_each_kind_of_invalid_entry
  run_mut c17c-green-for-skip $MOD 'for e in plan_doc["skip"]:' 'for e in []:' test_c17c_a_skip_entry_is_non_green test_c17a_summarize_over_a_skip_plan
  run_mut c17c-exit2-not-counted $MOD 'elif by_id[vid] == 2:' 'elif False:' test_c17c_three_versions_ok_fault_ok
  run_mut c17d-remove-plus-check $MOD 'elif "+" in semver:' 'elif False:' test_c17d_plus_version_is_refused
  run_mut c17d-reason-text-changed $MOD '(task 010)"' '(task 011)"' test_c17d_plus_version_is_refused test_c17d_reason_text_equals_the_contract_text
  run_mut c17e-log-exists-constant-false $MOD '"log_exists": f"logs/{ns}.{name}/{semver}.log" in logs}' '"log_exists": False}' test_c17e_log_exists_true test_c17e_cli_carries_log_exists
  run_mut c17e-drop-log_exists-key $MOD '"reason": PLUS_REFUSAL_REASON,
                        "log_exists": f"logs/{ns}.{name}/{semver}.log" in logs}' '"reason": PLUS_REFUSAL_REASON}' test_c17e_log_exists_true test_c17g_every_entry_has_exactly_the_pinned_fields
  run_mut c17f-exit-1-on-skip $MOD '    sys.stdout.write(text)
    return 0' '    sys.stdout.write(text)
    return 1 if doc["skip"] else 0' test_c17f_plan_with_skip_refuse_and_fault test_c17a_existing_branch_is_skipped_not_built
  run_mut c17f-half-dry-run-pair-accepted $MOD 'if given == 1:' 'if False:' test_c17f_conflicting_or_malformed_dry_run_sets
  run_mut c17f-pair-without-dry-run-accepted $MOD 'if pair and not dry:' 'if False:' test_c17f_conflicting_or_malformed_dry_run_sets
  run_mut c17f-bad-head-sha-accepted $MOD '    _check_head_sha(head_sha)' '    pass' test_c17f_unreadable_or_malformed_state_and_inputs
  run_mut c17f-error-exit-code-changed $MOD 'except (PlanInputError, NotImplementedError) as exc:
        print(f"plan_pending: {exc}", file=sys.stderr)
        return 1' 'except (PlanInputError, NotImplementedError) as exc:
        print(f"plan_pending: {exc}", file=sys.stderr)
        return 2' test_c17f_ test_c17_version_input_refused_exit_1
  run_mut c17b-recursion-error-unhandled $MOD '    except RecursionError:' '    except ZeroDivisionError:' test_c17b_deeply_nested_entry_is_a_per_entry_fault
  run_mut c17g-build-reason-nonempty $MOD 'out.append({**base, "kind": "build", "reason": ""})' 'out.append({**base, "kind": "build", "reason": "x"})' test_c17g_every_entry_has_exactly_the_pinned_fields test_c17_no_input_builds_every_pending_version
  run_mut forbidden-import $MOD 'import json
' 'import json
import subprocess
' test_planner_has_no_network_process_clock_or_actor_use
  # --- scope check (task 101): (m1) the pinned range's right side is widened back to HEAD -> scenario merge-from-main must go red;
  # (m2) an unusable pin is passed instead of failed -> scenario bad-pin must go red
  mkdir "$SCR/s" && git show HEAD:$SELF > "$SCR/s/v.sh"
  scope_mut() { # id | exact anchor line (must occur once) | replacement | scenario label that must be FAIL
    local id="$1" anchor="$2" repl="$3" want="$4"
    if [ "$(grep -cxF -- "$anchor" "$SCR/s/v.sh")" != 1 ]; then fail "mutation $id: anchor not found exactly once (broken search)"; return; fi
    SRC="$SCR/s/v.sh" DST="$SCR/s/m.sh" ANCHOR="$anchor" REPL="$repl" python3 -I -c '
import os
s=open(os.environ["SRC"]).read(); open(os.environ["DST"],"w").write(s.replace(os.environ["ANCHOR"],os.environ["REPL"],1))'
    if cmp -s "$SCR/s/v.sh" "$SCR/s/m.sh"; then fail "mutation $id: nothing changed"; return; fi
    ( cd "$SCR" && bash "$SCR/s/m.sh" --scope-selftest >"$SCR/s/out" 2>&1 )
    grep -q "^FAIL  scope scenario $want" "$SCR/s/out" && ok "mutation $id: red -> scope scenario $want" || { fail "mutation $id not red"; cat "$SCR/s/out"; }
  }
  scope_mut scope-right-side-head '  d=$(git diff --name-only "$PIN_BASE" "$PIN_FINAL") || return 1' '  d=$(git diff --name-only "$PIN_BASE" HEAD) || return 1' merge-from-main
  scope_mut scope-unusable-pin-passes '  pin_full "$PIN_BASE" && pin_full "$PIN_FINAL" || return 1' '  pin_full "$PIN_BASE" && pin_full "$PIN_FINAL" || return 0' bad-pin
  # --- criterion 12: the state check must go red on a state that still has a pending version
  M12=$(mktemp -d "$SCR/m12.XXXXXX"); write_state "$M12" "published,pending"
  got=$(plan_counts "$M12")
  [ "$got" != "rc=0 build=0 refuse=0 skip=0 fault=0" ] && ok "mutation c12-state-still-pending: the no-op expectation is red on it ($got)" || fail "mutation c12-state-still-pending not red: $got"
  AFTER=$(sha256sum $FILES | sha256sum)
  [ "$BEFORE" = "$AFTER" ] && ok "real tree byte-identical before/after (mutations ran in scratch copies)" || fail "real tree changed"
  echo "SUMMARY mutate failed=$FAILS"; exit "$FAILS"
fi

# ---------------------------------------------------------------- normal mode
OUT=$(python3 -I tests/pipeline/run_checks.py --only test_plan_pending 2>/tmp/w008b1-stderr.$$)
PASSN=$(echo "$OUT" | grep -c '^CHECK .* PASS$')
FAILN=$(echo "$OUT" | grep -c '^CHECK .* FAIL$')
echo "$OUT" | grep '^CHECK .* FAIL$' | sed 's/^/FAIL  /'
echo "suite: $PASSN passed, $FAILN failed"
[ "$FAILN" -eq 0 ] || { fail "$FAILN suite check(s) failed"; cat /tmp/w008b1-stderr.$$ >&2; }
rm -f /tmp/w008b1-stderr.$$
[ "$PASSN" -ge 40 ] && ok "suite ran at least 40 checks ($PASSN)" || fail "suite ran only $PASSN checks (floor 40)"
# every criterion group must have at least one passing check and no failing one (a group that matches nothing FAILS)
for grp in C3Naming:3 C12NoOp:12 C17Selection:17 C17aSkip:17a C17bSchemaFault:17b C17cSummarize:17c C17dPlusRefusal:17d C17eRefusalLog:17e C17fExitCodes:17f C17gSchema:17g; do
  cls=${grp%%:*}; crit=${grp##*:}
  P=$(echo "$OUT" | grep -c "^CHECK $cls\\..* PASS$"); F=$(echo "$OUT" | grep -c "^CHECK $cls\\..* FAIL$")
  [ "$P" -ge 1 ] && [ "$F" -eq 0 ] && ok "[criterion $crit] $cls: $P passing, 0 failing" || fail "[criterion $crit] $cls: $P passing, $F failing"
done

# criterion 3: contract <-> typed literals (the expected strings are 092's worked examples, typed in the test)
for ex in 'https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz' 'https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz'; do
  grep -qF "\`$ex\`" contracts/artifact-naming.md && ok "contract contains worked example $ex" || fail "contract lacks $ex"
  grep -qF "$ex" $TST && ok "test types worked example literally" || fail "test lacks $ex"
done
grep -qF 'DERIVATION ONLY, NEVER PUBLISHED' $TST && ok "example 2 is labelled derivation only, never published" || fail "example 2 label missing in the test"

# criteria 12 and 17f: the real CLI against throw-away states
state_checks && ok "criterion 12 state checks" || fail "criterion 12 / 17f state checks"

# forbidden-use greps with positive controls (no network, no process, no GITHUB_ACTOR)
PC=$(mktemp -d); echo 'import subprocess' > "$PC/c.py"
IMP='^\s*(import|from)\s+(subprocess|socket|ssl|urllib|http|requests|httpx|aiohttp)\b'
grep -qE "$IMP" "$PC/c.py" && ok "positive control: import grep finds subprocess" || fail "import grep is blind"
echo 'x = GITHUB_ACTOR' > "$PC/c.py"
grep -qF GITHUB_ACTOR "$PC/c.py" && ok "positive control: actor grep finds a planted use" || fail "actor grep is blind"
rm -r "$PC"
grep -qE "$IMP" $MOD && fail "$MOD imports subprocess/network" || ok "$MOD imports neither subprocess nor a network library"
grep -qF GITHUB_ACTOR $MOD && fail "$MOD mentions GITHUB_ACTOR" || ok "$MOD never uses GITHUB_ACTOR"

# criterion 18: docs
grep -q '^## The planner (task 008b-1)' docs/pipeline/build-pipeline.md && ok "build-pipeline.md has the planner section" || fail "planner section missing"
for h in '### The plan document' '### Planner rules' '### Recovering a skipped version'; do
  grep -qF "$h" docs/pipeline/build-pipeline.md && ok "docs heading present: $h" || fail "docs heading missing: $h"
done
# a phrase may wrap across lines in the prose: match it whitespace-insensitively in the normalised text
doc_has() { tr '\n\t' '  ' < "$2" | tr -s ' ' | grep -qF -- "$1"; }
REC='delete its `pipeline/` branch'
doc_has "$REC" docs/pipeline/build-pipeline.md && ok "manual recovery for a skipped version documented (phrase may wrap lines)" || fail "recovery text missing"
PCD=$(mktemp -d); grep -vF 'its `pipeline/` branch' docs/pipeline/build-pipeline.md | grep -v 'close its PR, delete' > "$PCD/b.md"
doc_has "$REC" "$PCD/b.md" && fail "positive control: the recovery check passes on a copy with the sentence removed (blind)" || ok "positive control: the recovery check fails on a copy with the recovery sentence removed"
rm -r "$PCD"

# hygiene and scope (own-change scope = 008b-1's merged range, fixed pins; see PIN_M above)
[ -x $SELF ] && ok "verify script executable" || fail "verify script not executable"
git ls-files | grep -E '(__pycache__|\.pyc$)' >/dev/null && fail "bytecode tracked" || ok "no bytecode tracked"
scope_selftest >"/tmp/w008b1-scope.$$" 2>&1 && ok "scope check self-test (merge-from-main green, stray commit red, unusable pins fail)" || { fail "scope self-test failed"; cat "/tmp/w008b1-scope.$$"; }
grep '^ok' "/tmp/w008b1-scope.$$" | sed 's/^/        /'; rm -f "/tmp/w008b1-scope.$$"
for p in PIN_M PIN_BASE PIN_FINAL; do
  pin_full "${!p}" && ok "scope pin $p is a full SHA and resolves" || fail "scope pin $p='${!p}' is not a full 40-character SHA that resolves (FAIL, never a pass)"
done
if pin_full "$PIN_M" && pin_full "$PIN_BASE" && pin_full "$PIN_FINAL"; then
  DB=$(git merge-base "$PIN_M^1" "$PIN_M^2" 2>/dev/null); DF=$(git rev-parse "$PIN_M^2" 2>/dev/null)
  [ "$DB" = "$PIN_BASE" ] && [ "$DF" = "$PIN_FINAL" ] && ok "scope pins re-derived from the merge commit: BASE=merge-base(M^1,M^2), FINAL=M^2" || fail "scope pins differ from the merge commit's range (derived BASE=$DB FINAL=$DF)"
  CH=$(git diff --name-only "$PIN_BASE" "$PIN_FINAL")
  [ -n "$CH" ] && ok "changed files in ${PIN_BASE:0:7}..${PIN_FINAL:0:7}: $(echo $CH | wc -w)" || fail "no changes in the pinned range (broken search)"
  BAD=$(scope_violations || echo "BASE-ERROR")
  [ -z "$BAD" ] && ok "all changes of 008b-1's merged range inside the declared file scope" || fail "out of scope: $BAD"
else fail "scope pins unusable: scope cannot be checked (FAIL, never a pass)"; fi

echo "SUMMARY failed=$FAILS"; exit "$FAILS"
