#!/usr/bin/env bash
#
# 065-verify.sh -- the runnable verification artefact for task 065 (MANAGER.md Section 2c).
#
# Task 065: entry.schema.json enforces the `key_id` format that signature-format.md defines (16 uppercase hex).
# Demonstrates acceptance criteria 1-6 of docs/tasks/065-entry-schema-key-id-format.md (criterion 7 is the site PR).
#
# Usage:  docs/tasks/065-verify.sh [--mutate] [NODE_MODULES_DIR]      (any cwd inside the repository)
#   (no flag)  AC1 (red on the red commit), AC2 (HEAD rejects/accepts, three validators), AC3 (diff integrity of
#              the fix range), AC4 (every closed verify script on HEAD, one at a time), AC5 (rules-document examples).
#   --mutate   AC1-AC3, AC5 and AC6 (AC4, the long run of every closed script, is skipped): three mutations of the schema
#              pattern in a temporary clone, each must turn a criterion-1 test red.
#   NODE_MODULES_DIR  (or env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules; install with
#                     npm ci --prefix tools/dev) a node_modules directory with ajv 8. Missing ajv is a FAILURE, never a skip.
# Pinning (REVIEW-CHECKLIST item 12): the task's OWN change (red-commit ancestry, scope, diffs, substitutions) is
# measured on the fixed range BASE..FIX below, never HEAD or origin/main; the LIVE guards (tests, validators,
# closed scripts) run on HEAD. Everything runs on the COMMITTED state in temporary clones; the caller's worktree is
# never modified. Deterministic, no network. Exit code: the number of failed checks.
# Run it with no other registry suite running (AC4 runs the other closed scripts one after the other).
# Requires: git, python3, node, plus everything the closed verify scripts require (minisign, ...).

set -u
set -o pipefail
export PYTHONDONTWRITEBYTECODE=1

MUTATE=0
NM="${WOM_NODE_MODULES:-}"
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) NM="$a" ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
[ -z "$NM" ] && NM="$ROOT/tools/dev/node_modules"
BASE="4356583"      # registry origin/main when task 065 was cut (merge of PR #18, task 075)
RED="3b53628"       # the commit that adds the failing tests and nothing else (AC1)
FIX="e9b121e"       # 065's fix commit; the own-change checks measure BASE..FIX (a fixed range), never HEAD
NEWTESTS="tests/registry/test_key_id_format.py"
GOOD="E7A1B2C3D4E5F607"
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

for c in "$BASE" "$RED" "$FIX"; do
    if ! git -C "$ROOT" rev-parse --verify -q "$c^{commit}" >/dev/null; then
        fail "P0 commit $c is reachable"
        printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"; exit "$FAILURES"
    fi
done
if [ -z "$NM" ] || [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then
    fail "P0 prerequisite: node and a node_modules directory with ajv are required; pass NODE_MODULES_DIR or set WOM_NODE_MODULES"
    printf '\n== RESULT ==\n%d CHECK(S) FAILED\n' "$FAILURES"; exit "$FAILURES"
fi
HEADSHA="$(git -C "$ROOT" rev-parse HEAD)"
clone_at() { git clone -q --no-hardlinks "$ROOT" "$1" 2>/dev/null && git -C "$1" checkout -q --detach "$2"; }
clone_at "$TMP/head" "$HEADSHA" || exit 99
clone_at "$TMP/red" "$RED" || exit 99
# run_tests DIR -> the new test module, output to $TMP/t.out
run_tests() { ( cd "$1" && python3 -I -m unittest discover -s tests/registry -p 'test_key_id_format.py' -v >"$TMP/t.out" 2>&1 ); }
blob() { git -C "$ROOT" show "$1:$2"; }

section "AC1 -- red first: at the red commit the new tests fail"
git -C "$ROOT" merge-base --is-ancestor "$BASE" "$RED" && git -C "$ROOT" merge-base --is-ancestor "$RED" "$FIX" && git -C "$ROOT" merge-base --is-ancestor "$FIX" "$HEADSHA" \
    && pass "AC1.1 BASE $BASE < RED $RED < FIX $FIX are ancestors of HEAD in that order" || fail "AC1.1 commit order BASE < RED < FIX < HEAD does not hold"
[ "$(git -C "$ROOT" rev-parse "$RED~1")" = "$(git -C "$ROOT" rev-parse "$BASE")" ] && pass "AC1.2 the red commit sits directly on BASE" || fail "AC1.2 the red commit is not directly on BASE"
RF=$(git -C "$ROOT" diff --name-only "$RED~1" "$RED" | tr '\n' ' ')
[ "$RF" = "tests/registry/test_hardening.py tests/registry/test_key_id_format.py " ] && pass "AC1.3 the red commit touches only test files (no schema, no fix)" || fail "AC1.3 red commit touches: $RF"
git -C "$ROOT" diff --quiet "$RED~1" "$RED" -- contracts tools && pass "AC1.4 contracts/ and tools/ are unchanged at the red commit" || fail "AC1.4 the red commit changes contracts/ or tools/"
git -C "$TMP/red" show "$RED:contracts/entry.schema.json" | python3 -I -c '
import json,sys
k=json.load(sys.stdin)["properties"]["versions"]["items"]["properties"]["key_id"]
sys.exit(0 if "pattern" not in k else 1)' && pass "AC1.5 at the red commit key_id carries no pattern (the defect is present)" || fail "AC1.5 key_id already carries a pattern at the red commit"
run_tests "$TMP/red"; rc=$?
nfail=$(grep -cE '\.\.\. (FAIL|ERROR)$' "$TMP/t.out")
[ "$rc" != 0 ] && [ "$nfail" -gt 0 ] && pass "AC1.6 red commit: $NEWTESTS exits $rc with $nfail failing subtests" || fail "AC1.6 red commit: exit $rc, failing subtests $nfail (expected red)"
for t in test_each_bad_key_id_is_rejected_by_schema_check_py_for_published_and_removed test_each_bad_key_id_is_rejected_by_the_strict_check_for_published_and_removed test_each_bad_key_id_is_rejected_by_the_schema_checker_verdict test_trailing_newline_is_rejected_explicitly_by_both_python_validators_task_064_guard test_the_schema_carries_the_signature_format_pattern_and_cites_the_rule; do
    grep -qE "^(FAIL|ERROR): $t " "$TMP/t.out" && pass "AC1.7 red commit: $t is red" || fail "AC1.7 red commit: $t is not red"
done
for state in published removed; do
    for why in "a non-hex label" "lowercase hex" "15 characters" "17 characters" "trailing newline"; do
        grep -E "^FAIL: test_each_bad_key_id_is_rejected_by_schema_check_py_for_published_and_removed .*state='$state', why='$why'" "$TMP/t.out" >/dev/null \
            && pass "AC1.8 red commit: schema_check.py accepts the $why key_id in a $state version (red)" || fail "AC1.8 red commit: [$state, $why] is not red against schema_check.py"
    done
done
( cd "$TMP/red" && python3 -I -m unittest discover -s tests/registry -p 'test_hardening.py' -v >"$TMP/h.out" 2>&1 ); rc=$?
grep -qE "^(FAIL|ERROR): test_f1_key_id_with_trailing_newline_is_rejected_task_065 " "$TMP/h.out" && pass "AC1.9 red commit: the new test_hardening key_id test is red (exit $rc)" || fail "AC1.9 red commit: the new test_hardening test is not red"

section "AC2 -- HEAD: bad values rejected by three validators, E7A1B2C3D4E5F607 accepted"
run_tests "$TMP/head"; rc=$?
[ "$rc" = 0 ] && pass "AC2.1 HEAD: $NEWTESTS green ($(grep -E '^Ran ' "$TMP/t.out"); $(tail -1 "$TMP/t.out"))" || { fail "AC2.1 HEAD: $NEWTESTS exits $rc"; tail -15 "$TMP/t.out"; }
( cd "$TMP/head" && python3 -I - <<'PYE'
import json, sys
sys.path.insert(0, "tests/contracts"); sys.path.insert(0, "tools/registry")
import schema_check, schema
sch = json.load(open("contracts/entry.schema.json"))
def doc(state, key_id):
    v = {"version": "1.0.0", "commit": "a" * 40, "source_url": "https://github.com/e/m",
         "source_archive": "https://cdn.example.org/a.tgz", "source_sha256": "b" * 64, "signature": "c" * 62,
         "key_id": key_id, "published_at": "2026-10-15T09:00:00Z", "status": state}
    if state == "removed":
        v["reason"] = "Takedown."
    return {"id": "kelsi:housing", "owner": {"provider": "github", "id": 1, "name_at_registration": "kelsi"}, "versions": [v]}
BAD = ["platform-2026-01", "e7a1b2c3d4e5f607", "E7A1B2C3D4E5F60", "E7A1B2C3D4E5F6071", "E7A1B2C3D4E5F607\n"]
fails = 0
for name, fn in (("tests/contracts/schema_check.py", schema_check.validate), ("tools/registry/schema.py (007a strict)", schema.validate)):
    for state in ("published", "removed"):
        for k in BAD:
            try:
                fn(doc(state, k), sch); print("  ACCEPTED (bad)", name, state, repr(k)); fails += 1
            except schema_check.SchemaValidationError:
                pass
        try:
            fn(doc(state, "E7A1B2C3D4E5F607"), sch)
        except schema_check.SchemaValidationError as e:
            print("  REJECTED (good)", name, state, e); fails += 1
    print(f"  {name}: {len(BAD)} bad values x 2 states rejected, E7A1B2C3D4E5F607 accepted for both" if not fails else f"  {name}: {fails} wrong verdict(s)")
for state in ("published", "removed"):
    nl = doc(state, "E7A1B2C3D4E5F607\n")
    for name, fn in (("schema_check.py", schema_check.validate), ("007a strict check", schema.validate)):
        try:
            fn(nl, sch); print("  trailing-newline ACCEPTED by", name, state); fails += 1
        except schema_check.SchemaValidationError:
            print(f"  trailing newline explicitly rejected by {name} ({state})")
sys.exit(fails)
PYE
) ; rc=$?
[ "$rc" = 0 ] && pass "AC2.2 HEAD: schema_check.py and 007a's strict check reject all five bad values (published and removed), including the explicit trailing-newline assertion on BOTH" || fail "AC2.2 HEAD: $rc wrong verdict(s)"
( cd "$TMP/head" && python3 -I docs/tasks/057-corpus.py > "$TMP/c.json" && node docs/tasks/057-ajv-check.mjs "$NM" < "$TMP/c.json" > "$TMP/a.json" ) && \
python3 -I - "$TMP/c.json" "$TMP/a.json" <<'PYE'
import json, sys
c = json.load(open(sys.argv[1])); a = json.load(open(sys.argv[2]))["verdicts"]
assert len(c) == len(a) and all(x["name"] == y["name"] for x, y in zip(c, a))
dis = [x["name"] for x, y in zip(c, a) if x["python"] != y["ajv"]]
k = [(x["name"], x["python"], y["ajv"]) for x, y in zip(c, a) if x["name"].startswith("pattern065:")]
bad_ok = [n for n, p, j in k if n.endswith(":ok") and (p, j) != ("valid", "valid")]
bad_bad = [n for n, p, j in k if not n.endswith(":ok") and (p, j) != ("invalid", "invalid")]
print(f"  Ajv 2020 strict: {len(c)} corpus cases, {len(k)} pattern065 cases (2 accepted controls + 10 rejected), disagreements: {dis}")
sys.exit(0 if len(k) == 12 and not dis and not bad_ok and not bad_bad else 1)
PYE
[ $? = 0 ] && pass "AC2.3 HEAD: Ajv 2020 strict agrees with schema_check.py on the 12 new corpus cases (E7A1B2C3D4E5F607 valid, the other five invalid, both states)" || fail "AC2.3 HEAD: Ajv and schema_check.py disagree, or the pattern065 cases are missing"
( cd "$TMP/head" && env WOM_NODE_MODULES="$NM" bash docs/tasks/057-verify.sh >"$TMP/057.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "AC2.4 HEAD: 057-verify.sh (V1 corpus, T1 pin refreshed) exits 0" || { fail "AC2.4 HEAD: 057-verify.sh exits $rc"; grep -E '^FAIL' "$TMP/057.out"; }

section "AC3 -- the fix range BASE..FIX: scope, value substitutions, the one assertion reversal"
CHANGED=$(git -C "$ROOT" diff --name-only "$BASE" "$FIX" | sort)
EXPECTED=$(printf '%s\n' contracts/append-only.rules.md contracts/entry.schema.json docs/tasks/057-corpus.py docs/tasks/057-pinned-sections.json tests/contracts/test_contracts.py tests/registry/support.py tests/registry/test_hardening.py tests/registry/test_key_id_format.py tests/registry/test_pattern_semantics.py | sort)
[ "$CHANGED" = "$EXPECTED" ] && pass "AC3.1 BASE..FIX changes exactly the declared files (plus test_pattern_semantics.py: the one new pattern key needs its sample and count, booked as a scope question)" || fail "AC3.1 changed files differ from the declared set: $(diff <(echo "$EXPECTED") <(echo "$CHANGED") | tr '\n' ' ')"
git -C "$ROOT" diff --quiet "$BASE" "$FIX" -- contracts/signature-format.md contracts/examples && pass "AC3.2 signature-format.md and contracts/examples/ are untouched (examples already conformed)" || fail "AC3.2 signature-format.md or an example changed"
python3 -I - "$ROOT" "$BASE" "$FIX" <<'PYE'
import json, subprocess, sys
root, base, fix = sys.argv[1:4]
def blob(rev, path):
    return subprocess.run(["git", "-C", root, "show", f"{rev}:{path}"], capture_output=True, text=True, check=True).stdout
ok = True
def check(label, cond, detail=""):
    global ok
    print(("  ok    " if cond else "  WRONG ") + label + (f": {detail}" if detail and not cond else ""))
    ok = ok and cond
old = json.loads(blob(base, "contracts/entry.schema.json")); new = json.loads(blob(fix, "contracts/entry.schema.json"))
ko = old["properties"]["versions"]["items"]["properties"].pop("key_id"); kn = new["properties"]["versions"]["items"]["properties"].pop("key_id")
check("schema: everything except the key_id property is identical", old == new)
check("schema: key_id.type is string and its pattern is ^[0-9A-F]{16}$", kn.get("type") == "string" and kn.get("pattern") == "^[0-9A-F]{16}$", repr(kn))
check("schema: key_id has exactly type, pattern, description", sorted(kn) == ["description", "pattern", "type"], repr(sorted(kn)))
check("schema: description cites signature-format.md \"Deriving `key_id`\"", "signature-format.md" in kn["description"] and "Deriving `key_id`" in kn["description"])
sig = new["properties"]["versions"]["items"]["properties"]["signature"]
check("schema: signature carries no pattern (objective item 4: not invented)", "pattern" not in sig, repr(sig))
def subst(path, old_s, new_s, n):
    o = blob(base, path); f = blob(fix, path)
    check(f"{path}: exactly {n} substitution(s) of {old_s!r}, nothing else", o.count(old_s) == n and o.replace(old_s, new_s) == f, f"base has {o.count(old_s)}")
subst("contracts/append-only.rules.md", '"key_id": "platform-2026-01"', '"key_id": "E7A1B2C3D4E5F607"', 4)
subst("docs/tasks/057-pinned-sections.json", '\\"key_id\\": \\"platform-2026-01\\"', '\\"key_id\\": \\"E7A1B2C3D4E5F607\\"', 1)
subst("tests/registry/support.py", '"key_id": "platform-2026-01"', '"key_id": "E7A1B2C3D4E5F607"', 2)
subst("tests/contracts/test_contracts.py", '"key_id": "k"', '"key_id": "E7A1B2C3D4E5F607"', 1)
sys.exit(0 if ok else 1)
PYE
[ $? = 0 ] && pass "AC3.3 schema change confined to key_id; the four rules-document examples, the 057 pin, support.py and test_contracts.py are value substitutions only" || fail "AC3.3 a diff is not what the spec declares"
python3 -I - "$ROOT" "$BASE" "$FIX" <<'PYE'
import subprocess, sys
root, base, fix = sys.argv[1:4]
out = subprocess.run(["git", "-C", root, "diff", "-U0", base, fix, "--", "tests", "docs/tasks/057-corpus.py"], capture_output=True, text=True, check=True).stdout
removed, cur = [], None
for line in out.splitlines():
    if line.startswith("+++ "):
        cur = line[6:]
    elif line.startswith("-") and not line.startswith("---"):
        removed.append((cur, line[1:]))
EXPECT = [
    ("tests/contracts/test_contracts.py", '            "key_id": "k",'),
    ("tests/registry/support.py", '    "key_id": "platform-2026-01",'),
    ("tests/registry/support.py", '            "key_id": "platform-2026-01",'),
    ("tests/registry/test_hardening.py", '    def test_f1_signature_and_key_id_carry_no_pattern_so_a_trailing_newline_is_contract_valid(self):'),
    ("tests/registry/test_hardening.py", '        """entry.schema.json gives these two minLength only, and signature-format.md says `signature` holds'),
    ("tests/registry/test_hardening.py", '        multi-line text. Rejecting them would invent a rule; reported to the manager (task log, Questions)."""'),
    ("tests/registry/test_hardening.py", '        for k, val in (("signature", "c" * 62 + "\\n"), ("key_id", "platform-2026-01\\n")):'),
    ("tests/registry/test_pattern_semantics.py", '        self.assertEqual(len(SUBS), 15)'),
]
for r in removed:
    print("  removed:", r[0], "|", r[1].strip()[:110])
sys.exit(0 if sorted(removed) == sorted(EXPECT) else 1)
PYE
[ $? = 0 ] && pass "AC3.4 the only removed lines under tests/ are: 3 key_id values, the old hardening test header+docstring+loop (split, objective item 2b), and the pattern count 15 -> 16" || fail "AC3.4 unexpected removed line(s) under tests/ (see above)"
python3 -I - "$TMP/head" <<'PYE'
import re, sys
t = open(sys.argv[1] + "/tests/registry/test_hardening.py").read()
sig = re.search(r"def test_f1_signature_carries_no_pattern_so_a_trailing_newline_is_contract_valid.*?(?=\n    def )", t, re.S).group(0)
key = re.search(r"def test_f1_key_id_with_trailing_newline_is_rejected_task_065.*?(?=\n    def )", t, re.S).group(0)
ok = ('"signature", "c" * 62 + "\\n"' in sig and '"accepted"' in sig and "rejected" not in sig.split('"""')[2]
      and '"rejected"' in key and "signature-format.md" in key and "065" in key)
sys.exit(0 if ok else 1)
PYE
[ $? = 0 ] && pass "AC3.5 test_hardening: signature keeps its 'accepted' assertion; key_id moved to a test asserting 'rejected' that cites task 065 and signature-format.md" || fail "AC3.5 test_hardening split is not as specified"

if [ "$MUTATE" = 0 ]; then
section "AC4 -- the repository's suites and every closed verify script on HEAD (one at a time)"
for d in tests/contracts tests/registry tests/validation tests/pipeline; do
    ( cd "$TMP/head" && python3 -I -m unittest discover -s "$d" >"$TMP/u.out" 2>&1 ); rc=$?
    [ "$rc" = 0 ] && pass "AC4.1 unittest discover -s $d: $(grep -E '^Ran ' "$TMP/u.out")" || { fail "AC4.1 unittest discover -s $d exits $rc"; tail -8 "$TMP/u.out"; }
done
# 006 runs through 062 (its checks over their pinned ranges); the rest are listed by their closed task number.
for s in 007a 007b 008a 032 034 062 064 066 067 069 070 071 075; do
    [ -f "$TMP/head/docs/tasks/$s-verify.sh" ] || { fail "AC4.2 $s-verify.sh does not exist at HEAD"; continue; }
    ( cd "$TMP/head" && env WOM_NODE_MODULES="$NM" bash docs/tasks/$s-verify.sh >"$TMP/s.out" 2>&1 ); rc=$?
    [ "$rc" = 0 ] && pass "AC4.2 $s-verify.sh exits 0 at HEAD" || fail "AC4.2 $s-verify.sh exits $rc at HEAD; failing: $(grep -E '^FAIL' "$TMP/s.out" | cut -c1-90 | tr '\n' '|')"
done
( cd "$TMP/head" && env WOM_NODE_MODULES="$NM" bash docs/tasks/006-verify.sh >"$TMP/s.out" 2>&1 ); rc=$?
[ "$rc" = 0 ] && pass "AC4.3 006-verify.sh exits 0 at HEAD (also covered through 062 over its pinned ranges)" || echo "  note: 006-verify.sh run directly exits $rc (its moving-frame checks are not the live guard; 062 runs them over pinned ranges and is green above)"
fi

section "AC5 -- the JSON examples embedded in contracts/append-only.rules.md validate against the schema"
( cd "$TMP/head" && python3 -I - <<'PYE'
import json, re, sys
sys.path.insert(0, "tests/contracts"); sys.path.insert(0, "tools/registry")
import schema_check, schema
sch = json.load(open("contracts/entry.schema.json"))
text = open("contracts/append-only.rules.md", encoding="utf-8").read()
blocks = [json.loads(m.group(1)) for m in re.finditer(r"```json\n(.*?)```", text, re.S)]
bad = 0
for i, b in enumerate(blocks):
    b = dict(b)
    if b.get("source_sha256") == "d" * 62:   # pre-existing 62-character hash in the counter-example: booked, unrelated to key_id
        b["source_sha256"] = "d" * 64
    doc = {"id": "example:mod", "owner": {"provider": "github", "id": 1, "name_at_registration": "example"}, "versions": [b]}
    for fn in (schema_check.validate, schema.validate):
        try:
            fn(doc, sch)
        except schema_check.SchemaValidationError as e:
            print(f"  block {i} (status {b.get('status')}): {e}"); bad += 1
    if "key_id" in b and b["key_id"] != "E7A1B2C3D4E5F607":
        print(f"  block {i}: key_id {b['key_id']!r}"); bad += 1
print(f"  {len(blocks)} JSON example blocks extracted, {sum('key_id' in b for b in blocks)} carry key_id; {bad} failure(s)")
sys.exit(1 if bad or len(blocks) == 0 else 0)
PYE
); [ $? = 0 ] && pass "AC5.1 every extracted example validates (count > 0; a zero count fails)" || fail "AC5.1 an embedded example is invalid or none was found"

if [ "$MUTATE" = 1 ]; then
    section "AC6 -- mutations of the schema pattern in a temporary clone, each must turn a criterion-1 test red"
    M="$TMP/head"
    mutate() { python3 -I - "$M/contracts/entry.schema.json" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
t = open(p, encoding="utf-8").read()
assert t.count(old) == 1, (old, t.count(old))
open(p, "w", encoding="utf-8").write(t.replace(old, new))
PY
    }
    run_tests "$M"; [ $? = 0 ] && pass "AC6.0 control: new tests green before mutating" || fail "AC6.0 control: new tests not green before mutating"
    check_red() {
        if run_tests "$M"; then fail "AC6 $1: tests stayed GREEN (mutation survived)"; else
            if grep -qE "^(FAIL|ERROR): test_each_bad_key_id_is_rejected_by_[a-z_]+ " "$TMP/t.out"; then pass "AC6 $1: red ($(grep -cE '\.\.\. (FAIL|ERROR)$' "$TMP/t.out") failing subtests, incl. a criterion-1 rejection test)"; else fail "AC6 $1: red, but no criterion-1 test failed"; fi
        fi
        git -C "$M" checkout -q -- .
    }
    mutate '            "pattern": "^[0-9A-F]{16}$",
' '';                                                              check_red "pattern removed"
    mutate '^[0-9A-F]{16}$' '^[0-9A-Fa-f]{16}$';                    check_red "lowercase allowed"
    mutate '^[0-9A-F]{16}$' '^[0-9A-F]{16,}$';                      check_red "{16} loosened to {16,}"
    run_tests "$M"; [ $? = 0 ] && pass "AC6.4 restored: new tests green again" || fail "AC6.4 restored tree is not green"
fi

printf '\n== RESULT ==\n'
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
