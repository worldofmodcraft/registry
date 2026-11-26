#!/usr/bin/env bash
#
# 120-verify.sh -- the runnable verification artefact for task 120 (MANAGER.md Section 2c).
#
# Task 120: the ownership checker implements R12 and I9 (contracts/ownership.md "Pipeline write-back").
#
# Usage (run from the repository root, in a fresh clone of the pushed branch):
#   npm ci --prefix tools/dev            # once; 118-verify.sh runs 057-verify.sh, which needs Ajv
#   bash docs/tasks/120-verify.sh            # criteria 1-7 and 118-verify.sh
#   bash docs/tasks/120-verify.sh --mutate   # criterion 7: each mutation of the checker must turn a test red,
#                                            # then the file is restored byte-identically (sha256 before/after)
#
# Every negative check has a positive control next to it. Temp dirs live under one trap-cleaned directory, and the
# script fails if a child leaves anything behind in it.
set -u
BASE=${BASE:-4f65d12}   # the 118 head this branch was cut from
MODE=${1:-check}
FAILS=0
ok()   { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILS=$((FAILS + 1)); }
[ -f tools/registry/ownership.py ] && [ -f docs/tasks/120-verify.sh ] || { echo "run from the registry repository root"; exit 2; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
mkdir "$TMPD/run"
export TMPDIR="$TMPD/run" WOM_TMP="$TMPD/run" PYTHONDONTWRITEBYTECODE=1
export TMPD

sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---------------------------------------------------------------------------------------------------------------
if [ "$MODE" = "--mutate" ]; then
  mutate() {  # id, file, suite-pattern, k-filter, then edits as "old<TAB>new" pairs on stdin-free args
    local id=$1 file=$2 pattern=$3 filter=$4
    shift 4
    local before; before=$(sha "$file")
    cp "$file" "$TMPD/backup"
    if ! python3 - "$file" "$@" <<'PY'
import sys
path, *pairs = sys.argv[1:]
text = open(path).read()
for pair in pairs:
    old, new = pair.split("\t", 1)
    if text.count(old) != 1:
        sys.exit(f"ANCHOR ERROR: {old[:70]!r} occurs {text.count(old)} times in {path}")
    text = text.replace(old, new)
open(path, "w").write(text)
PY
    then fail "mutation $id: its anchor does not occur exactly once"; cp "$TMPD/backup" "$file"; return; fi
    local mutated; mutated=$(sha "$file")
    python3 -B -m unittest discover -s tests/registry -p "$pattern" ${filter:+-k "$filter"} >"$TMPD/mut.out" 2>&1
    local rc=$?
    cp "$TMPD/backup" "$file"
    local after; after=$(sha "$file")
    [ "$before" != "$mutated" ] || fail "mutation $id changed nothing"
    if [ "$rc" -ne 0 ]; then ok "mutation $id turns the tests red ($(grep -cE '^(FAIL|ERROR):' "$TMPD/mut.out") failing)"; else fail "mutation $id left the tests green"; fi
    [ "$before" = "$after" ] && ok "  $file restored byte-identically after $id" || fail "  $file NOT restored after $id"
  }
  OW=tools/registry/ownership.py
  CG=tools/registry/ci_gate.py
  python3 -B -m unittest discover -s tests/registry -p test_ownership.py >/dev/null 2>&1 && ok "positive control: the ownership suite is green before any mutation" || fail "the ownership suite is red before mutating"
  python3 -B -m unittest discover -s tests/registry -p test_ci_gate.py -k AC12 >/dev/null 2>&1 && ok "positive control: the ci_gate R12/I9 tests are green before any mutation" || fail "the ci_gate R12/I9 tests are red before mutating"

  mutate accept-a-username-instead-of-the-id "$OW" test_ownership.py "" \
    $'why = _writeback(author, pipeline, files, hits)\twhy = _writeback((pipeline if pipeline and (login or "").endswith("[bot]") else author), pipeline, files, hits)'
  mutate accept-two-t1s "$OW" test_ownership.py "" \
    $'    if len(files) != 1 or len(hits) != 1 or sum(len(v) for v in hits.values()) != 1:\t    if len(files) != 1:' \
    $'    (path, [(i, born)]), = hits.items()\t    (path, [(i, born), *_]), = hits.items()' \
    $'    if not append_only._same(only, new):\t    if False:'
  mutate accept-t1-plus-a-page-edit "$OW" test_ownership.py "" \
    $'    if len(files) != 1 or len(hits) != 1 or\t    if len(hits) != 1 or'
  mutate skip-the-parsed-equality-check "$OW" test_ownership.py "" \
    $'    if not append_only._same(only, new):\t    if False:'
  mutate drop-i9-in-check "$OW" test_ownership.py "" \
    $'    pipeline = None if pipeline_identity is None else _pair(pipeline_identity, "pipeline_identity")\n    separate_identities(r11, pipeline)\n\t    pipeline = None if pipeline_identity is None else _pair(pipeline_identity, "pipeline_identity")\n'
  mutate drop-i9-in-ci-gate "$CG" test_ci_gate.py AC12 \
    $'            if r11 is not None and r11 == pipeline:\n                raise Undecided("I9:\t            if False:\n                raise Undecided("I9:'
  mutate read-the-config-from-the-pr-revision "$CG" test_ci_gate.py AC12 \
    $'            r11, pipeline = read_r11(old), read_pipeline(old)\n\t            r11 = read_r11(old)\n            materialise(repo, who["head"], new, ("config/pipeline-identity.json",), **lim["mat"])\n            pipeline = read_pipeline(new)\n'
  mutate accept-a-string-id "$CG" test_ci_gate.py AC12 \
    $'type(r["id"]) is int and r["id"] > 0:\n        return r["id"]\t(type(r["id"]) is int and r["id"] > 0) or (isinstance(r["id"], str) and r["id"].isdigit()):\n        return r["id"]'
  mutate drop-the-identity-comparison "$OW" test_ownership.py "" \
    $'    if author != pipeline:\n        return f"its author\t    if False:\n        return f"its author'

  python3 -B -m unittest discover -s tests/registry -p test_ownership.py >/dev/null 2>&1 && ok "positive control: the ownership suite is green again after every restore" || fail "the ownership suite is red after the restores"
  if git diff --quiet -- tools; then ok "git diff of tools/ is empty after the mutations"; else fail "tools/ differs from HEAD after the mutations"; fi
  [ -z "$(ls -A "$TMPD/run")" ] && ok "no temp dir left behind by the child processes" || fail "children left $(ls "$TMPD/run")"
  echo; echo "SUMMARY: $FAILS failure(s)"
  exit $((FAILS > 0))
fi

# ---------------------------------------------------------------------------------------------------------------
echo "== registry unit suite (whole tests/registry)"
if python3 -B -m unittest discover -s tests/registry >"$TMPD/suite.out" 2>&1; then ok "whole suite: $(grep -E '^Ran ' "$TMPD/suite.out")"; else fail "the registry suite is red"; tail -15 "$TMPD/suite.out"; fi

echo "== criteria 1 and 2 end to end through the real CLI (a positive control beside every negative)"
python3 - <<'PY' || FAILS=$((FAILS + 1))
import copy, json, os, subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, "tests/registry")
import support
from support import pending, published, rejected, entry

CLI = str(Path("tools/registry/ownership_cli.py").resolve())
PIPE, OWNER_ID, R11ID = 342916936, 4831207, 324218296   # the pipeline id here is only an argument, never configuration
ORG = {"provider": "github", "id": 99, "name_at_registration": "worldofmodcraft"}
RES = {"schema_version": "1.0.0", "namespaces": {"test": {"owner": ORG, "reason": "r"}}}
bad = []


def ent(ns, name, *v, owner=None, **extra):
    return {"id": f"{ns}:{name}", "owner": owner or (ORG if ns == "test" else {"provider": "github", "id": OWNER_ID, "name_at_registration": ns}),
            "versions": list(v), **extra}


def run(label, want_code, old, new, author=PIPE, extra=(), want_rule=None, raw=None):
    with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as d:
        root = Path(d)
        (root / "res.json").write_text(json.dumps(RES))
        paths = []
        for side, files in (("old", old), ("new", new)):
            (root / side / "mods").mkdir(parents=True)
            for p, doc in files.items():
                (root / side / p).parent.mkdir(parents=True, exist_ok=True)
                if doc is not None:
                    (root / side / p).write_text(doc if isinstance(doc, str) else json.dumps(doc))
        paths = sorted(set(old) | set(new))
        r = subprocess.run([sys.executable, "-I", CLI, "--author-provider", "github", "--author-id", str(author),
                            "--author-login", "pipeline-bot", "--old-root", str(root / "old"), "--new-root", str(root / "new"),
                            "--reserved-file", str(root / "res.json"), *extra, *paths], capture_output=True, text=True)
    rules = []
    if r.stdout.strip():
        rules = [x for f in json.loads(r.stdout)["findings"] for x in f["rules"]]
    good = r.returncode == want_code and (want_rule is None or want_rule in rules)
    print(("ok    " if good else "FAIL  ") + f"{label}: exit {r.returncode} (want {want_code}){'' if want_rule is None else f', rules {rules}'}")
    if not good:
        bad.append(label)


P = lambda ns, n, k="entry": f"mods/{ns}.{n}/{k}.json"
T1 = lambda ns, n="tool": ({P(ns, n): ent(ns, n, pending())}, {P(ns, n): ent(ns, n, published())})
T3 = lambda ns, n="tool": ({P(ns, n): ent(ns, n, pending())}, {P(ns, n): ent(ns, n, rejected())})
CFG = ["--pipeline-identity", f"github:{PIPE}"]

for ns in ("alice", "test"):  # "test" is reserved and no --membership-status is given: R9 would reject if it were consulted
    for k, mk in (("T1", T1), ("T3", T3)):
        run(f"accept: pipeline identity, one {k} on {ns}:tool", 0, *mk(ns), extra=CFG)
run("control: owner's ordinary new version still accepts", 0, {P("alice", "tool"): ent("alice", "tool", published())},
    {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))}, author=OWNER_ID)
o, n = T1("alice")
run("accept: parsed-equal entry with the keys reordered", 0, o, {k: {x: v[x] for x in reversed(list(v))} for k, v in n.items()}, extra=CFG)
run("reject R12: a different id (the owner)", 1, o, n, author=OWNER_ID, extra=CFG, want_rule="R12")
run("reject R12: login of the bot but another id", 1, o, n, author=PIPE + 1, extra=CFG, want_rule="R12")
run("reject R12: pipeline identity unconfigured", 1, o, n, extra=[], want_rule="R12")
run("reject R12: configured as another id", 1, o, n, extra=["--pipeline-identity", f"github:{PIPE + 1}"], want_rule="R12")
run("reject R12: T1 plus a page.json edit", 1, {**o, P("alice", "tool", "page"): {"a": 1}}, {**n, P("alice", "tool", "page"): {"a": 2}}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus an extra top-level key", 1, o, {P("alice", "tool"): {**n[P("alice", "tool")], "extra": 1}}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus a new version", 1, o, {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))}, extra=CFG, want_rule="R12")
run("reject R12: two T1s", 1, {P("alice", "tool"): ent("alice", "tool", pending(), pending("1.1.0", "b" * 40))},
    {P("alice", "tool"): ent("alice", "tool", published(), published("1.1.0", "b" * 40))}, extra=CFG, want_rule="R12")
run("reject R12: a T1 on another entry.json too", 1, {**o, **T1("alice", "two")[0]}, {**n, **T1("alice", "two")[1]}, extra=CFG, want_rule="R12")
run("reject R12 and R11: a T1 and a takedown", 1, {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))},
    {P("alice", "tool"): ent("alice", "tool", support.removed(), published("1.1.0", "b" * 40))}, extra=CFG, want_rule="R11")
run("reject R12: born published", 1, {P("alice", "tool"): ent("alice", "tool", published())},
    {P("alice", "tool"): ent("alice", "tool", published(), published("1.1.0", "b" * 40))}, author=OWNER_ID, extra=CFG, want_rule="R12")
run("reject R12: an entry.json that does not parse", 1, o, {P("alice", "tool"): "{not json"}, extra=CFG, want_rule="R12")
run("reject R12: an entry.json with a duplicate key", 1, o, {P("alice", "tool"): '{"id": "a", "id": "b"}'}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus a change to config/", 1, {**o, "config/r11-identity.json": {"a": 1}}, {**n, "config/r11-identity.json": {"a": 2}}, extra=CFG, want_rule="R12")
run("I9: equal identities are exit 2 (no verdict)", 2, o, n, extra=CFG + ["--r11-identity", f"github:{PIPE}"])
run("I9 control: distinct identities give a verdict", 0, o, n, extra=CFG + ["--r11-identity", f"github:{R11ID}"])
sys.exit(1 if bad else 0)
PY

echo "== criterion 3: ci_gate reads the configuration (read_pipeline, merge-base, I9)"
python3 - <<'PY' || FAILS=$((FAILS + 1))
import json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0, "tools/registry")
import ci_gate

bad = []


def case(label, doc, want, link=False, directory=False):
    with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as d:
        cfg = Path(d, "config")
        cfg.mkdir()
        f = cfg / "pipeline-identity.json"
        if link:
            os.symlink("r11-identity.json", f)
        elif directory:
            f.mkdir()
        elif doc is not None:
            f.write_text(doc)
        try:
            got = ci_gate.read_pipeline(d)
        except ci_gate.Undecided:
            got = "Undecided"
    good = got == want
    print(("ok    " if good else "FAIL  ") + f"{label}: {got!r}")
    if not good:
        bad.append(label)


mk = lambda v: json.dumps({"schema_version": "1.0.0", "pipeline_identity": v})
case("absent -> unconfigured", None, None)
case("null -> unconfigured", mk(None), None)
case("configured github 342916936 -> 342916936", mk({"provider": "github", "id": 342916936}), 342916936)
case("symlink", None, "Undecided", link=True)
case("directory", None, "Undecided", directory=True)
for label, doc in (("malformed JSON", "{x"), ("extra key", json.dumps({"schema_version": "1.0.0", "pipeline_identity": None, "x": 1})),
                   ("wrong schema_version", json.dumps({"schema_version": "2", "pipeline_identity": None})),
                   ("provider gitlab", mk({"provider": "gitlab", "id": 5})), ("id as string", mk({"provider": "github", "id": "342916936"})),
                   ("id true", mk({"provider": "github", "id": True})), ("id 0", mk({"provider": "github", "id": 0})),
                   ("id -1", mk({"provider": "github", "id": -1}))):
    case(label, doc, "Undecided")
sys.exit(1 if bad else 0)
PY
python3 -B -m unittest discover -s tests/registry -p test_ci_gate.py -k AC12PipelineIdentity >"$TMPD/ac3.out" 2>&1 && ok "ci_gate end-to-end tests: merge-base read, every PR with a mods path, I9, flag pass-through ($(grep -E '^Ran ' "$TMPD/ac3.out"))" || { fail "ci_gate AC12PipelineIdentity tests"; tail -20 "$TMPD/ac3.out"; }

echo "== criterion 4: config/pipeline-identity.json"
if [ "$(cat config/pipeline-identity.json)" = '{"schema_version": "1.0.0", "pipeline_identity": null}' ] && [ "$(tail -c1 config/pipeline-identity.json | xxd -p)" = "0a" ] && [ "$(wc -l < config/pipeline-identity.json)" = 1 ]; then ok "config/pipeline-identity.json is the null identity with one trailing newline"; else fail "config/pipeline-identity.json is wrong"; fi
grep -q 342916936 config/pipeline-identity.json && fail "the real id is set in config/pipeline-identity.json (008b-3b's job)" || ok "the real id is not set in config/pipeline-identity.json"

echo "== criterion 5: rule counts, mutation table, declared test changes"
python3 -B tests/registry/test_ownership_mutations.py >"$TMPD/mut.out" 2>&1; tail -1 "$TMPD/mut.out" | grep -q "not_red=0" && ok "every mutation turns red: $(tail -1 "$TMPD/mut.out")" || { fail "the mutation table has a NOT RED entry"; grep -E "NOT RED|ANCHOR|BASELINE" "$TMPD/mut.out"; }
python3 -B -m unittest discover -s tests/registry -p test_ownership_mutations.py 2>&1 | tail -1 | grep -q '^OK' && ok "MutationCoverage: twelve R rules, nine I rules, accept/reject tests and a mutation per rule" || fail "MutationCoverage is red"
git archive "$BASE" | tar -x -C "$TMPD" --one-top-level=base 2>/dev/null || { mkdir -p "$TMPD/base"; git archive "$BASE" | tar -x -C "$TMPD/base"; }
python3 -B "$TMPD/base/tests/registry/test_ownership_mutations.py" --list | sort > "$TMPD/mut.before"
python3 -B tests/registry/test_ownership_mutations.py --list | sort > "$TMPD/mut.after"
names() { (cd "$1" && python3 -B - <<'PY'
import sys, unittest
sys.path.insert(0, "tests/registry")
def walk(s):
    for t in s:
        if isinstance(t, unittest.TestSuite):
            yield from walk(t)
        else:
            yield t.id()
print("\n".join(sorted(walk(unittest.defaultTestLoader.discover("tests/registry", top_level_dir="tests/registry")))))
PY
); }
names "$TMPD/base" > "$TMPD/tests.before"
names "$PWD" > "$TMPD/tests.after"
REMOVED_M=$(comm -23 "$TMPD/mut.before" "$TMPD/mut.after" | tr '\n' ' ')
[ "$REMOVED_M" = "b4-pipeline-app-id-bypasses-fail-closed " ] && ok "removed mutation ids: exactly b4-pipeline-app-id-bypasses-fail-closed (replaced by b4-pipeline-identity-matched-on-login-r12)" || fail "removed mutation ids: $REMOVED_M"
grep -qx b4-pipeline-identity-matched-on-login-r12 "$TMPD/mut.after" && ok "its R12 equivalent exists" || fail "its R12 equivalent is missing"
echo "info  mutation ids added: $(comm -13 "$TMPD/mut.before" "$TMPD/mut.after" | tr '\n' ' ')"
REMOVED_T=$(comm -23 "$TMPD/tests.before" "$TMPD/tests.after" | sed 's/^test_ownership\.//; s/^test_ownership_mutations\.//' | tr '\n' ' ')
EXPECT_T="FailClosed.test_b1_pipeline_app_id_equal_to_r11_identity_still_cannot_carry_t1_or_t3 Takedowns.test_r11_pipeline_app_id_equal_to_r11_identity_behaves_as_r11_for_t2 MutationCoverage.test_b3_the_contract_still_declares_eleven_r_rules_and_eight_i_rules "
[ "$REMOVED_T" = "$EXPECT_T" ] && ok "removed test names: exactly the three declared (two pipeline_app_id cases and the 11/8 count test)" || fail "removed test names: $REMOVED_T"
echo "info  tests before/after: $(wc -l < "$TMPD/tests.before") / $(wc -l < "$TMPD/tests.after"); mutations before/after: $(wc -l < "$TMPD/mut.before") / $(wc -l < "$TMPD/mut.after")"
# control: the comparison does flag a removal
printf 'a\nb\n' > "$TMPD/c1"; printf 'a\n' > "$TMPD/c2"
[ -n "$(comm -23 "$TMPD/c1" "$TMPD/c2")" ] && ok "control: the before/after comparison flags a removed name" || fail "control: the comparison is blind"
# closed-script floors (007b-verify.sh): >= 45 mutations, and the test-name patterns it greps
[ "$(wc -l < "$TMPD/mut.after")" -ge 45 ] && ok "007b floor: at least 45 mutations" || fail "fewer than 45 mutations"
for pat in test_b1_ test_b3_ test_b4_ test_r11_ test_cli_exit_codes; do grep -q "\.$pat" "$TMPD/tests.after" && ok "test-name pattern $pat still matches" || fail "pattern $pat matches nothing"; done
grep -q "b7-r11-mixed-pr-branch-removed" "$TMPD/mut.after" && ok "075's mutation b7-r11-mixed-pr-branch-removed exists" || fail "b7-r11-mixed-pr-branch-removed is gone"

echo "== criterion 6: the 008b-3a review findings"
grep -rIn "pipeline_app_id" tools tests config .github >/dev/null 2>&1 && fail "F4: pipeline_app_id still appears in tools/ tests/ config/ .github/" || ok "F4: no pipeline_app_id in tools/, tests/, config/ or .github/"
printf 'pipeline_app_id\n' | grep -In "pipeline_app_id" >/dev/null && ok "F4 control: the grep finds a planted occurrence"
python3 - <<'PY' && ok "F2: every old-string of every ownership.py mutation occurs exactly once (the runner would stop on ANCHOR ERROR otherwise)" || fail "F2: an anchor does not occur exactly once"
import sys
sys.path.insert(0, "tests/registry")
import test_ownership_mutations as tm
from pathlib import Path
n = 0
for mid, edits, red in tm.M:
    for old, new, *target in edits:
        text = Path(target[0] if target else tm.OW).read_text()
        if text.count(old) != 1:
            print("ANCHOR", mid, repr(old[:60]), text.count(old))
            sys.exit(1)
        n += 1
print(f"{n} anchors checked")
PY
# F6: scope check with a positive control, and no stray temp dirs
SCOPE_RE='^(tools/registry/(ownership|ownership_cli|ci_gate)\.py|config/pipeline-identity\.json|tests/registry/(test_ownership|test_ownership_mutations|test_ci_gate)\.py|tests/registry/fixtures/.*|docs/tasks/120-verify\.sh|docs/tasks/120-ownership-r12-checker\.md)$'
outside() { grep -vE "$SCOPE_RE" || true; }
printf 'contracts/ownership.md\ntools/registry/ci_gate.py\n' | outside | grep -qx 'contracts/ownership.md' && ok "F6 control: the scope check flags contracts/ownership.md" || fail "F6 control: the scope check is blind"
STRAY=$(git diff --name-only "$BASE" HEAD | outside)
[ -z "$STRAY" ] && ok "F6: the branch changes nothing outside the declared file scope (contracts/, .github/, other verify scripts untouched)" || fail "files outside the declared scope: $STRAY"
[ -z "$(ls -A "$TMPD/run")" ] && ok "F6: no temp dir left behind by any child process" || fail "children left: $(ls "$TMPD/run")"
mkdir "$TMPD/run/planted"; [ -n "$(ls -A "$TMPD/run")" ] && ok "F6 control: a planted temp dir is detected" ; rmdir "$TMPD/run/planted"

echo "== 118-verify.sh (the contract's own checks, criteria 1-6, 8-10)"
# 118-verify.sh's C10.10 diffs the working tree against e213cbc and allows only 118's own files, so on the combined head
# (118 + 120) it necessarily names 120's files. That one line is the only failure tolerated, and only if every file it names
# is inside 120's declared scope; any other FAIL, or an unrelated file in that list, is a failure here.
bash docs/tasks/118-verify.sh >"$TMPD/118.out" 2>&1; RC118=$?
NFAIL=$(grep -c '^FAIL' "$TMPD/118.out")
if [ "$RC118" -eq 0 ]; then ok "118-verify.sh passes outright: $(tail -1 "$TMPD/118.out")"
elif [ "$NFAIL" -eq 1 ] && grep -q '^FAIL  C10.10 ' "$TMPD/118.out"; then
  LEFT=$(grep '^FAIL  C10.10 ' "$TMPD/118.out" | grep -o "\['[^]]*\]" | tr -d "[]'," | tr ' ' '\n' | outside)
  [ -z "$LEFT" ] && ok "118-verify.sh: every check passes except C10.10, which names only 120's own files (expected on the combined head)" || fail "118-verify.sh C10.10 names files outside 120's scope: $LEFT"
else fail "118-verify.sh failed beyond C10.10"; grep '^FAIL' "$TMPD/118.out"; fi
# control: an unrelated failing line must not be tolerated by the rule above
printf 'FAIL  C1.1 x\nFAIL  C10.10 y\n' > "$TMPD/c118"
[ "$(grep -c '^FAIL' "$TMPD/c118")" -ne 1 ] && ok "control: a second failing check would not be tolerated" || fail "control: the tolerance rule is blind"

echo; echo "SUMMARY: $FAILS failure(s)"
  exit $((FAILS > 0))
fi

# ---------------------------------------------------------------------------------------------------------------
echo "== registry unit suite (whole tests/registry)"
if python3 -B -m unittest discover -s tests/registry >"$TMPD/suite.out" 2>&1; then ok "whole suite: $(grep -E '^Ran ' "$TMPD/suite.out")"; else fail "the registry suite is red"; tail -15 "$TMPD/suite.out"; fi

echo "== criteria 1 and 2 end to end through the real CLI (a positive control beside every negative)"
python3 - <<'PY' || FAILS=$((FAILS + 1))
import copy, json, os, subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, "tests/registry")
import support
from support import pending, published, rejected, entry

CLI = str(Path("tools/registry/ownership_cli.py").resolve())
PIPE, OWNER_ID, R11ID = 342916936, 4831207, 324218296   # the pipeline id here is only an argument, never configuration
ORG = {"provider": "github", "id": 99, "name_at_registration": "worldofmodcraft"}
RES = {"schema_version": "1.0.0", "namespaces": {"test": {"owner": ORG, "reason": "r"}}}
bad = []


def ent(ns, name, *v, owner=None, **extra):
    return {"id": f"{ns}:{name}", "owner": owner or (ORG if ns == "test" else {"provider": "github", "id": OWNER_ID, "name_at_registration": ns}),
            "versions": list(v), **extra}


def run(label, want_code, old, new, author=PIPE, extra=(), want_rule=None, raw=None):
    with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as d:
        root = Path(d)
        (root / "res.json").write_text(json.dumps(RES))
        paths = []
        for side, files in (("old", old), ("new", new)):
            (root / side / "mods").mkdir(parents=True)
            for p, doc in files.items():
                (root / side / p).parent.mkdir(parents=True, exist_ok=True)
                if doc is not None:
                    (root / side / p).write_text(doc if isinstance(doc, str) else json.dumps(doc))
        paths = sorted(set(old) | set(new))
        r = subprocess.run([sys.executable, "-I", CLI, "--author-provider", "github", "--author-id", str(author),
                            "--author-login", "pipeline-bot", "--old-root", str(root / "old"), "--new-root", str(root / "new"),
                            "--reserved-file", str(root / "res.json"), *extra, *paths], capture_output=True, text=True)
    rules = []
    if r.stdout.strip():
        rules = [x for f in json.loads(r.stdout)["findings"] for x in f["rules"]]
    good = r.returncode == want_code and (want_rule is None or want_rule in rules)
    print(("ok    " if good else "FAIL  ") + f"{label}: exit {r.returncode} (want {want_code}){'' if want_rule is None else f', rules {rules}'}")
    if not good:
        bad.append(label)


P = lambda ns, n, k="entry": f"mods/{ns}.{n}/{k}.json"
T1 = lambda ns, n="tool": ({P(ns, n): ent(ns, n, pending())}, {P(ns, n): ent(ns, n, published())})
T3 = lambda ns, n="tool": ({P(ns, n): ent(ns, n, pending())}, {P(ns, n): ent(ns, n, rejected())})
CFG = ["--pipeline-identity", f"github:{PIPE}"]

for ns in ("alice", "test"):  # "test" is reserved and no --membership-status is given: R9 would reject if it were consulted
    for k, mk in (("T1", T1), ("T3", T3)):
        run(f"accept: pipeline identity, one {k} on {ns}:tool", 0, *mk(ns), extra=CFG)
run("control: owner's ordinary new version still accepts", 0, {P("alice", "tool"): ent("alice", "tool", published())},
    {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))}, author=OWNER_ID)
o, n = T1("alice")
run("accept: parsed-equal entry with the keys reordered", 0, o, {k: {x: v[x] for x in reversed(list(v))} for k, v in n.items()}, extra=CFG)
run("reject R12: a different id (the owner)", 1, o, n, author=OWNER_ID, extra=CFG, want_rule="R12")
run("reject R12: login of the bot but another id", 1, o, n, author=PIPE + 1, extra=CFG, want_rule="R12")
run("reject R12: pipeline identity unconfigured", 1, o, n, extra=[], want_rule="R12")
run("reject R12: configured as another id", 1, o, n, extra=["--pipeline-identity", f"github:{PIPE + 1}"], want_rule="R12")
run("reject R12: T1 plus a page.json edit", 1, {**o, P("alice", "tool", "page"): {"a": 1}}, {**n, P("alice", "tool", "page"): {"a": 2}}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus an extra top-level key", 1, o, {P("alice", "tool"): {**n[P("alice", "tool")], "extra": 1}}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus a new version", 1, o, {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))}, extra=CFG, want_rule="R12")
run("reject R12: two T1s", 1, {P("alice", "tool"): ent("alice", "tool", pending(), pending("1.1.0", "b" * 40))},
    {P("alice", "tool"): ent("alice", "tool", published(), published("1.1.0", "b" * 40))}, extra=CFG, want_rule="R12")
run("reject R12: a T1 on another entry.json too", 1, {**o, **T1("alice", "two")[0]}, {**n, **T1("alice", "two")[1]}, extra=CFG, want_rule="R12")
run("reject R12 and R11: a T1 and a takedown", 1, {P("alice", "tool"): ent("alice", "tool", published(), pending("1.1.0", "b" * 40))},
    {P("alice", "tool"): ent("alice", "tool", support.removed(), published("1.1.0", "b" * 40))}, extra=CFG, want_rule="R11")
run("reject R12: born published", 1, {P("alice", "tool"): ent("alice", "tool", published())},
    {P("alice", "tool"): ent("alice", "tool", published(), published("1.1.0", "b" * 40))}, author=OWNER_ID, extra=CFG, want_rule="R12")
run("reject R12: an entry.json that does not parse", 1, o, {P("alice", "tool"): "{not json"}, extra=CFG, want_rule="R12")
run("reject R12: an entry.json with a duplicate key", 1, o, {P("alice", "tool"): '{"id": "a", "id": "b"}'}, extra=CFG, want_rule="R12")
run("reject R12: T1 plus a change to config/", 1, {**o, "config/r11-identity.json": {"a": 1}}, {**n, "config/r11-identity.json": {"a": 2}}, extra=CFG, want_rule="R12")
run("I9: equal identities are exit 2 (no verdict)", 2, o, n, extra=CFG + ["--r11-identity", f"github:{PIPE}"])
run("I9 control: distinct identities give a verdict", 0, o, n, extra=CFG + ["--r11-identity", f"github:{R11ID}"])
sys.exit(1 if bad else 0)
PY

echo "== criterion 3: ci_gate reads the configuration (read_pipeline, merge-base, I9)"
python3 - <<'PY' || FAILS=$((FAILS + 1))
import json, os, sys, tempfile
from pathlib import Path
sys.path.insert(0, "tools/registry")
import ci_gate

bad = []


def case(label, doc, want, link=False, directory=False):
    with tempfile.TemporaryDirectory(dir=os.environ["TMPDIR"]) as d:
        cfg = Path(d, "config")
        cfg.mkdir()
        f = cfg / "pipeline-identity.json"
        if link:
            os.symlink("r11-identity.json", f)
        elif directory:
            f.mkdir()
        elif doc is not None:
            f.write_text(doc)
        try:
            got = ci_gate.read_pipeline(d)
        except ci_gate.Undecided:
            got = "Undecided"
    good = got == want
    print(("ok    " if good else "FAIL  ") + f"{label}: {got!r}")
    if not good:
        bad.append(label)


mk = lambda v: json.dumps({"schema_version": "1.0.0", "pipeline_identity": v})
case("absent -> unconfigured", None, None)
case("null -> unconfigured", mk(None), None)
case("configured github 342916936 -> 342916936", mk({"provider": "github", "id": 342916936}), 342916936)
case("symlink", None, "Undecided", link=True)
case("directory", None, "Undecided", directory=True)
for label, doc in (("malformed JSON", "{x"), ("extra key", json.dumps({"schema_version": "1.0.0", "pipeline_identity": None, "x": 1})),
                   ("wrong schema_version", json.dumps({"schema_version": "2", "pipeline_identity": None})),
                   ("provider gitlab", mk({"provider": "gitlab", "id": 5})), ("id as string", mk({"provider": "github", "id": "342916936"})),
                   ("id true", mk({"provider": "github", "id": True})), ("id 0", mk({"provider": "github", "id": 0})),
                   ("id -1", mk({"provider": "github", "id": -1}))):
    case(label, doc, "Undecided")
sys.exit(1 if bad else 0)
PY
python3 -B -m unittest discover -s tests/registry -p test_ci_gate.py -k AC12PipelineIdentity >"$TMPD/ac3.out" 2>&1 && ok "ci_gate end-to-end tests: merge-base read, every PR with a mods path, I9, flag pass-through ($(grep -E '^Ran ' "$TMPD/ac3.out"))" || { fail "ci_gate AC12PipelineIdentity tests"; tail -20 "$TMPD/ac3.out"; }

echo "== criterion 4: config/pipeline-identity.json"
if [ "$(cat config/pipeline-identity.json)" = '{"schema_version": "1.0.0", "pipeline_identity": null}' ] && [ "$(tail -c1 config/pipeline-identity.json | xxd -p)" = "0a" ] && [ "$(wc -l < config/pipeline-identity.json)" = 1 ]; then ok "config/pipeline-identity.json is the null identity with one trailing newline"; else fail "config/pipeline-identity.json is wrong"; fi
grep -q 342916936 config/pipeline-identity.json && fail "the real id is set in config/pipeline-identity.json (008b-3b's job)" || ok "the real id is not set in config/pipeline-identity.json"

echo "== criterion 5: rule counts, mutation table, declared test changes"
python3 -B tests/registry/test_ownership_mutations.py >"$TMPD/mut.out" 2>&1; tail -1 "$TMPD/mut.out" | grep -q "not_red=0" && ok "every mutation turns red: $(tail -1 "$TMPD/mut.out")" || { fail "the mutation table has a NOT RED entry"; grep -E "NOT RED|ANCHOR|BASELINE" "$TMPD/mut.out"; }
python3 -B -m unittest discover -s tests/registry -p test_ownership_mutations.py 2>&1 | tail -1 | grep -q '^OK' && ok "MutationCoverage: twelve R rules, nine I rules, accept/reject tests and a mutation per rule" || fail "MutationCoverage is red"
git archive "$BASE" | tar -x -C "$TMPD" --one-top-level=base 2>/dev/null || { mkdir -p "$TMPD/base"; git archive "$BASE" | tar -x -C "$TMPD/base"; }
python3 -B "$TMPD/base/tests/registry/test_ownership_mutations.py" --list | sort > "$TMPD/mut.before"
python3 -B tests/registry/test_ownership_mutations.py --list | sort > "$TMPD/mut.after"
names() { (cd "$1" && python3 -B - <<'PY'
import sys, unittest
sys.path.insert(0, "tests/registry")
def walk(s):
    for t in s:
        if isinstance(t, unittest.TestSuite):
            yield from walk(t)
        else:
            yield t.id()
print("\n".join(sorted(walk(unittest.defaultTestLoader.discover("tests/registry", top_level_dir="tests/registry")))))
PY
); }
names "$TMPD/base" > "$TMPD/tests.before"
names "$PWD" > "$TMPD/tests.after"
REMOVED_M=$(comm -23 "$TMPD/mut.before" "$TMPD/mut.after" | tr '\n' ' ')
[ "$REMOVED_M" = "b4-pipeline-app-id-bypasses-fail-closed " ] && ok "removed mutation ids: exactly b4-pipeline-app-id-bypasses-fail-closed (replaced by b4-pipeline-identity-matched-on-login-r12)" || fail "removed mutation ids: $REMOVED_M"
grep -qx b4-pipeline-identity-matched-on-login-r12 "$TMPD/mut.after" && ok "its R12 equivalent exists" || fail "its R12 equivalent is missing"
echo "info  mutation ids added: $(comm -13 "$TMPD/mut.before" "$TMPD/mut.after" | tr '\n' ' ')"
REMOVED_T=$(comm -23 "$TMPD/tests.before" "$TMPD/tests.after" | sed 's/^test_ownership\.//; s/^test_ownership_mutations\.//' | tr '\n' ' ')
EXPECT_T="FailClosed.test_b1_pipeline_app_id_equal_to_r11_identity_still_cannot_carry_t1_or_t3 Takedowns.test_r11_pipeline_app_id_equal_to_r11_identity_behaves_as_r11_for_t2 MutationCoverage.test_b3_the_contract_still_declares_eleven_r_rules_and_eight_i_rules "
[ "$REMOVED_T" = "$EXPECT_T" ] && ok "removed test names: exactly the three declared (two pipeline_app_id cases and the 11/8 count test)" || fail "removed test names: $REMOVED_T"
echo "info  tests before/after: $(wc -l < "$TMPD/tests.before") / $(wc -l < "$TMPD/tests.after"); mutations before/after: $(wc -l < "$TMPD/mut.before") / $(wc -l < "$TMPD/mut.after")"
# control: the comparison does flag a removal
printf 'a\nb\n' > "$TMPD/c1"; printf 'a\n' > "$TMPD/c2"
[ -n "$(comm -23 "$TMPD/c1" "$TMPD/c2")" ] && ok "control: the before/after comparison flags a removed name" || fail "control: the comparison is blind"
# closed-script floors (007b-verify.sh): >= 45 mutations, and the test-name patterns it greps
[ "$(wc -l < "$TMPD/mut.after")" -ge 45 ] && ok "007b floor: at least 45 mutations" || fail "fewer than 45 mutations"
for pat in test_b1_ test_b3_ test_b4_ test_r11_ test_cli_exit_codes; do grep -q "\.$pat" "$TMPD/tests.after" && ok "test-name pattern $pat still matches" || fail "pattern $pat matches nothing"; done
grep -q "b7-r11-mixed-pr-branch-removed" "$TMPD/mut.after" && ok "075's mutation b7-r11-mixed-pr-branch-removed exists" || fail "b7-r11-mixed-pr-branch-removed is gone"

echo "== criterion 6: the 008b-3a review findings"
grep -rIn "pipeline_app_id" tools tests config .github >/dev/null 2>&1 && fail "F4: pipeline_app_id still appears in tools/ tests/ config/ .github/" || ok "F4: no pipeline_app_id in tools/, tests/, config/ or .github/"
printf 'pipeline_app_id\n' | grep -In "pipeline_app_id" >/dev/null && ok "F4 control: the grep finds a planted occurrence"
python3 - <<'PY' && ok "F2: every old-string of every ownership.py mutation occurs exactly once (the runner would stop on ANCHOR ERROR otherwise)" || fail "F2: an anchor does not occur exactly once"
import sys
sys.path.insert(0, "tests/registry")
import test_ownership_mutations as tm
from pathlib import Path
n = 0
for mid, edits, red in tm.M:
    for old, new, *target in edits:
        text = Path(target[0] if target else tm.OW).read_text()
        if text.count(old) != 1:
            print("ANCHOR", mid, repr(old[:60]), text.count(old))
            sys.exit(1)
        n += 1
print(f"{n} anchors checked")
PY
# F6: scope check with a positive control, and no stray temp dirs
SCOPE_RE='^(tools/registry/(ownership|ownership_cli|ci_gate)\.py|config/pipeline-identity\.json|tests/registry/(test_ownership|test_ownership_mutations|test_ci_gate)\.py|tests/registry/fixtures/.*|docs/tasks/120-verify\.sh|docs/tasks/120-ownership-r12-checker\.md)$'
outside() { grep -vE "$SCOPE_RE" || true; }
printf 'contracts/ownership.md\ntools/registry/ci_gate.py\n' | outside | grep -qx 'contracts/ownership.md' && ok "F6 control: the scope check flags contracts/ownership.md" || fail "F6 control: the scope check is blind"
STRAY=$(git diff --name-only "$BASE" HEAD | outside)
[ -z "$STRAY" ] && ok "F6: the branch changes nothing outside the declared file scope (contracts/, .github/, other verify scripts untouched)" || fail "files outside the declared scope: $STRAY"
[ -z "$(ls -A "$TMPD/run")" ] && ok "F6: no temp dir left behind by any child process" || fail "children left: $(ls "$TMPD/run")"
mkdir "$TMPD/run/planted"; [ -n "$(ls -A "$TMPD/run")" ] && ok "F6 control: a planted temp dir is detected" ; rmdir "$TMPD/run/planted"

echo "== 118-verify.sh (the contract's own checks, criteria 1-6, 8-10)"
if bash docs/tasks/118-verify.sh >"$TMPD/118.out" 2>&1; then ok "118-verify.sh passes: $(tail -1 "$TMPD/118.out")"; else fail "118-verify.sh failed"; tail -25 "$TMPD/118.out"; fi

echo; echo "SUMMARY: $FAILS failure(s)"
exit $((FAILS > 0))
