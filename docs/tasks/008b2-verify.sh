#!/usr/bin/env bash
#
# 008b2-verify.sh -- runnable verification artefact for task 008b-2 (MANAGER.md 2c): the pipeline workflow's plan,
# build, sign, dry-run and summary jobs, `--no-sign`, sign_built.py and the handoff.
#   ./docs/tasks/008b2-verify.sh            structural checks of the workflow + the whole unit suite + docs + scope
#   ./docs/tasks/008b2-verify.sh --mutate   break the workflow text / the tools in scratch copies; each named check
#                                           must turn red (the unmodified files are the positive control)
# Exit code = number of failed checks. Missing tools FAIL (never skip). No network, no key, no credential: tests
# generate throwaway minisign keys in temp directories. Needs PyYAML (the checks parse the workflow).
# Criteria covered [script]: 1, 7-pin, 14, 15, 16, 17 (workflow clause), 25, 26, 13 (this script), 18 (docs).
# NOT covered here ([live], recorded with run URLs in the task log): 7, 8, 10, 11, and the 25 live clause.
# `--mutate` needs the changes COMMITTED (it mutates `git archive HEAD`).
set -u
cd "$(dirname "$0")/../.." || exit 99
FAILS=0
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
ok()   { echo "ok    $*"; }
SCOPE_RE='\.github/workflows/pipeline\.yml|tools/pipeline/(sign_built|handoff|build_version)\.py|tests/pipeline/test_handoff\.py|docs/pipeline/build-pipeline\.md|docs/tasks/008b2-pipeline-build-sign\.md|docs/tasks/008b2-verify\.sh'
WF=.github/workflows/pipeline.yml
CONTRACT=contracts/pipeline-trigger.md

for tool in git python3 grep sed tar minisign; do
  command -v "$tool" >/dev/null 2>&1 && ok "tool present: $tool" || fail "tool missing: $tool"
done
python3 -c 'import yaml' 2>/dev/null && ok "PyYAML importable" || fail "PyYAML is not importable (the structural checks need it)"
[ "$FAILS" -eq 0 ] || { echo "SUMMARY failed=$FAILS (tools missing)"; exit "$FAILS"; }

export PYTHONDONTWRITEBYTECODE=1
T=$(mktemp -d "${TMPDIR:-/tmp}/w008b2-verify.XXXXXX")
trap 'rm -rf "$T"' EXIT

cat > "$T/wfcheck.py" <<'PYEOF'
#!/usr/bin/env python3
"""Structural checks of .github/workflows/pipeline.yml (task 008b-2 criteria 1, 14, 15, 17, 25, 26a).
usage: wfcheck.py WORKFLOW CONTRACT   -> prints `ok <name>` / `FAIL <name>: why`; exit 1 if any FAIL.
Every check fails on zero matches: it must FIND the job / step / binding it judges, never pass vacuously."""
import json
import re
import sys

import yaml

wf_path, contract_path = sys.argv[1], sys.argv[2]
text = open(wf_path, encoding="utf-8").read()
doc = yaml.safe_load(text)
results = []


def check(name, fn):
    try:
        fn()
        results.append((name, None))
    except AssertionError as exc:
        results.append((name, str(exc) or "assertion failed"))


def walk(node, path=()):
    yield path, node
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(v, path + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, path + (i,))


def dump(node):
    return json.dumps(node, sort_keys=True)


jobs = doc.get("jobs") or {}
on = doc.get("on", doc.get(True))


def job_with_step(token):
    found = [(n, j) for n, j in jobs.items() if any(token in str(s.get("run", "")) for s in j.get("steps", []))]
    assert found, f"no job has a step running {token} (zero matches)"
    return found


# ---- criterion 1
def c1():
    blocks = re.findall(r"## Normative trigger block.*?```yaml\n(.*?)```", open(contract_path, encoding="utf-8").read(), re.S)
    assert len(blocks) == 1, "the normative trigger block was not found exactly once in the contract (zero matches)"
    block = yaml.safe_load(blocks[0])
    bon = block.get("on", block.get(True))
    assert isinstance(on, dict) and set(on) == {"push", "workflow_dispatch"}, f"on keys are {sorted(map(str, on or []))}"
    assert bon["push"] == on["push"] and on["push"].get("branches") == ["main"], "push differs from the contract block"
    assert doc.get("concurrency") == block["concurrency"], "concurrency differs from the contract block"
    inputs = (on["workflow_dispatch"] or {}).get("inputs") or {}
    for name in ("dry_run", "version", "dry_run_source_url", "dry_run_commit"):
        assert name in inputs, f"workflow_dispatch input {name} is missing"
    for bad in ("pull_request_target", "pull_request:", "workflow_run"):
        assert bad not in text, f"the workflow file contains {bad}"
check("c1 trigger block equals the contract on parsed keys; inputs; no forbidden trigger", c1)


# ---- criterion 14
def build_job():
    found = job_with_step("build_version.py")
    assert len(found) == 1, f"{len(found)} jobs run build_version.py, expected exactly one"
    return found[0]


def c14_build():
    name, job = build_job()
    sub = dump(job)
    assert "secrets." not in sub, "the build job's subtree contains a secrets. token"
    assert "secrets" not in job, "the build job has a secrets: key (inherit)"
    assert "uses" not in job, "the build job uses a reusable workflow"
    assert job.get("permissions") == {"contents": "read"}, f"build job permissions are {job.get('permissions')}"
    assert "secrets." not in dump(doc.get("env", {})) + dump(doc.get("permissions", {})), "workflow-level env/permissions reference a secret"
    assert "secrets." not in dump(job.get("env", {})), "job-level env references a secret"
    for n in ("MINISIGN_SECRET_KEY", "PIPELINE_APP_PRIVATE_KEY"):
        assert n not in sub, f"the build job mentions {n}"
check("c14 (a)(b)(c) build job holds no secret, permissions exactly contents: read", c14_build)


def sign_job():
    found = [(n, j) for n, j in jobs.items() if "secrets.MINISIGN_SECRET_KEY" in dump(j)]
    assert len(found) == 1, f"{len(found)} jobs reference secrets.MINISIGN_SECRET_KEY, expected exactly one"
    return found[0]


def c14_sign():
    name, job = sign_job()
    bname, _ = build_job()
    sub = dump(job)
    assert sub.count("secrets.MINISIGN_SECRET_KEY") == 1, "the signing job names the key more than once"
    assert text.count("secrets.MINISIGN_SECRET_KEY") == 1, "the key is named more than once in the file"
    needs = job.get("needs")
    assert bname in (needs if isinstance(needs, list) else [needs]), "the signing job does not need the build job"
    low = sub.lower()
    for bad in ("git clone", "build_version.py", "source_url"):
        assert bad not in low, f"the signing job contains {bad}"
    co = [s for s in job["steps"] if str(s.get("uses", "")).startswith("actions/checkout")]
    assert co, "the signing job has no checkout step (zero matches)"
    for s in co:
        w = s.get("with", {})
        assert "repository" not in w and w.get("ref") == "${{ needs.plan.outputs.head_sha }}", f"checkout in the signing job is not this repository at the planned main sha: {w}"
    assert "PIPELINE_APP_PRIVATE_KEY" not in sub, "the signing job mentions the App key"
check("c14 (d) signing job: key once, needs build, no clone/build tool/source_url, own checkout only", c14_sign)


def c14_unset():
    name, job = sign_job()
    steps = [s for s in job["steps"] if "secrets.MINISIGN_SECRET_KEY" in dump(s)]
    assert len(steps) == 1, "signing step not found exactly once"
    run = steps[0]["run"]
    assert "unset MINISIGN_SECRET_KEY" in run, "the signing step never unsets MINISIGN_SECRET_KEY"
    w, u, p = run.find('> "$RUNNER_TEMP/signing.key"'), run.find("unset MINISIGN_SECRET_KEY"), run.find("sign_built.py")
    assert 0 <= w < u < p, "the key must be written, then unset, before sign_built.py is invoked"
check("c14 (d2) signing step unsets the secret from the environment before the python call", c14_unset)


def c14_f():
    name, job = sign_job()
    assert job.get("environment") == "signing", f"signing job environment is {job.get('environment')!r}"
    assert "github.ref == 'refs/heads/main'" in str(job.get("if")), "signing job lacks the github.ref == 'refs/heads/main' condition"
    assert "dry-run" in jobs, "no dry-run job (zero matches)"
    d = jobs["dry-run"]
    assert "environment" not in d, "the dry-run job declares an environment"
    assert "secrets." not in dump(d) and "MINISIGN_SECRET_KEY" not in dump(d) and "PIPELINE_APP_PRIVATE_KEY" not in dump(d), "the dry-run job references a secret"
check("c14 (f) signing: environment signing + main ref; dry-run: no environment, no secret", c14_f)


# ---- criterion 15
def c15():
    flags = ["--allow-local-source", "--clone-timeout", "--max-clone-bytes", "--max-compressed-bytes", "--max-uncompressed-bytes", "--max-entries", "--scanner"]
    assert "build_version.py" in text, "workflow does not call build_version.py (zero matches)"
    for f in flags:
        assert f not in text, f"the workflow contains the test-only flag {f}"
    assert "--no-sign" in text, "the build step lacks --no-sign"
check("c15 no test-only flag in the workflow; --no-sign present", c15)


# ---- criterion 17
def c17():
    wanted = {"version": "inputs.version", "dry_run_source_url": "inputs.dry_run_source_url", "dry_run_commit": "inputs.dry_run_commit"}
    bound = {k: 0 for k in wanted}
    for path, node in walk(doc):
        if isinstance(node, str) and "inputs." in node:
            in_env = "env" in path and path.index("env") < len(path) - 1
            in_if = path and path[-1] == "if"
            in_run = path and path[-1] == "run"
            assert not in_run, f"an expression on inputs.* appears inside a run: at {path}"
            for k, v in wanted.items():
                if v in node:
                    assert in_env, f"{v} is used outside an env: binding, at {path}"
                    bound[k] += 1
    for k, n in bound.items():
        assert n >= 1, f"no env binding of inputs.{k} found (zero matches)"
    for jn, j in jobs.items():
        for s in j.get("steps", []):
            assert "${{" not in str(s.get("run", "")), f"job {jn}: an expression ${{{{ }}}} appears inside a run: block (design 9: values reach scripts through env: only)"
    matrixed = [n for n, j in jobs.items() if "strategy" in j]
    assert matrixed, "no matrix job found (zero matches)"
    for n in matrixed:
        assert jobs[n]["strategy"].get("fail-fast") is False, f"job {n}: strategy.fail-fast is not false"
check("c17 inputs reach scripts only through env:; fail-fast false", c17)


# ---- criterion 25
def c25():
    assert jobs, "no jobs found (zero matches)"
    G = "github.event_name != 'push'"
    expected = {
        "plan": G,
        "build": G + " && needs.plan.result == 'success' && needs.plan.outputs.has_build == 'true'",
        "sign": "always() && " + G + " && github.ref == 'refs/heads/main' && needs.plan.result == 'success' && needs.plan.outputs.has_build == 'true' && inputs.dry_run != true",
        "dry-run": "always() && " + G + " && inputs.dry_run == true && needs.plan.result == 'success' && needs.plan.outputs.has_build == 'true'",
        "summary": "always() && " + G,
    }
    assert set(jobs) == set(expected), f"jobs are {sorted(jobs)}, expected {sorted(expected)}"
    for n, j in jobs.items():
        assert str(j.get("if", "")).strip() == expected[n], f"job {n}: if is {j.get('if')!r}, expected exactly {expected[n]!r}"
    assert jobs["summary"]["if"] == "always() && github.event_name != 'push'", f"summary if is {jobs['summary'].get('if')!r}"
    assert on["push"] == {"branches": ["main"], "paths": ["mods/*/entry.json"]}, "on.push differs from the contract block"
check("c25 every job is gated off on push; summary condition exact; on.push unchanged", c25)


# ---- criterion 26 (a)
def uploads(job):
    return {s["with"]["name"]: [p for p in s["with"]["path"].splitlines() if p.strip()] for s in job["steps"] if str(s.get("uses", "")).startswith("actions/upload-artifact")}


def c26a():
    allup = {}
    for j in jobs.values():
        allup.update(uploads(j))
    exp = {
        "plan": ["plan.json"],
        "build-${{ matrix.tag }}": ["out/outcome.json", "out/build.stderr", "out/build.log", "out/${{ matrix.tag }}.tar.gz", "out/result.json"],
        "signed-${{ matrix.tag }}": ["signed/${{ matrix.tag }}.tar.gz", "signed/${{ matrix.tag }}.tar.gz.minisig", "signed/result.json", "signed/outcome.json"],
    }
    for name, paths in exp.items():
        assert name in allup, f"no upload named {name} (zero matches)"
        assert allup[name] == paths, f"upload {name} has paths {allup[name]}"
    assert jobs["build"]["strategy"].get("fail-fast") is False, "the build matrix does not have fail-fast: false"
    assert set(jobs["summary"]["needs"]) == set(jobs) - {"summary"}, f"summary needs {jobs['summary']['needs']}"
    assert "has_build" in str(jobs["build"].get("if")), "build job if does not test has_build"
    sif = str(jobs["sign"].get("if"))
    for tok in ("always()", "needs.plan.result == 'success'", "has_build"):
        assert tok in sif, f"sign job if lacks {tok}"
    steps = jobs["sign"]["steps"]
    guard = [s for s in steps if "handoff.py guard" in str(s.get("run", ""))]
    assert len(guard) == 1 and guard[0].get("id") == "guard", "the sign job has no guard step (zero matches)"
    signing_steps = [s for s in steps if "secrets.MINISIGN_SECRET_KEY" in dump(s)]
    assert len(signing_steps) == 1, "signing step not found exactly once"
    assert "steps.guard.outputs.proceed == 'true'" in str(signing_steps[0].get("if")), "the signing step lacks the per-version exit_code == 0 guard"
    assert "outcome.json" in "".join(uploads(jobs["sign"]).get("signed-${{ matrix.tag }}", [])), "signed artifact lacks outcome.json"
check("c26a artifact names and path lists, summary needs, build/sign conditions, per-version guard", c26a)

# ---- criterion 7 support: the minisign download pin is the verified value, in BOTH jobs that install it
def c7pin():
    for jn in ("sign", "dry-run"):
        pins = [s["env"]["MINISIGN_TARBALL_SHA256"] for s in jobs[jn]["steps"] if "MINISIGN_TARBALL_SHA256" in (s.get("env") or {})]
        assert len(pins) == 1, f"job {jn}: {len(pins)} install steps carry MINISIGN_TARBALL_SHA256 (zero matches or duplicates)"
        assert pins[0] == "9a599b48ba6eb7b1e80f12f36b94ceca7c00b7a5173c95c3efc88d9822957e73", f"job {jn}: pin is {pins[0]!r}, not the verified value"
check("c7 minisign tarball pin is the verified SHA-256 in sign and dry-run", c7pin)

bad = 0
for name, why in results:
    if why is None:
        print(f"ok    {name}")
    else:
        bad += 1
        print(f"FAIL  {name}: {why}")
sys.exit(1 if bad else 0)
PYEOF

cat > "$T/wfmutate.py" <<'PYEOF'
#!/usr/bin/env python3
"""Mutations of the workflow text: each must turn the NAMED check red (and the unmodified file must pass).
usage: wfmutate.py CHECKER WORKFLOW CONTRACT. Exit code = number of mutations that did not turn red.
An anchor that is not found exactly once (or the stated occurrence) is a hard error, never a silent pass."""
import os
import subprocess
import sys
import tempfile

checker, wf, contract = sys.argv[1:4]
orig = open(wf, encoding="utf-8").read()
M = []


def mut(mid, edits, red):
    M.append((mid, edits, red))


GATE = "    if: github.event_name != 'push'\n"
mut("c1-extra-branch", [("    branches: [main]\n", "    branches: [main, dev]\n", 1)], "c1 ")
mut("c1-workflow-run-trigger", [("  workflow_dispatch:\n    inputs:\n", "  workflow_run:\n    workflows: [x]\n  workflow_dispatch:\n    inputs:\n", 1)], "c1 ")
mut("c1-drop-input", [("      dry_run_commit:\n", "      dry_run_commit_renamed:\n", 1)], "c1 ")
mut("c14-secret-in-build-env", [("          LEG_ENTRY_PATH: ${{ matrix.entry_path }}\n", "          MINISIGN_SECRET_KEY: ${{ secrets.MINISIGN_SECRET_KEY }}\n          LEG_ENTRY_PATH: ${{ matrix.entry_path }}\n", 1)], "c14 (a)(b)(c)")
mut("c14-secrets-inherit", [("  build:\n    needs: [plan]\n", "  build:\n    secrets: inherit\n    needs: [plan]\n", 1)], "c14 (a)(b)(c)")
mut("c14-signing-step-moved-into-build", [("      - name: Mark a pipeline fault on this leg\n", "      - name: Sign (moved here)\n        env:\n          MINISIGN_SECRET_KEY: ${{ secrets.MINISIGN_SECRET_KEY }}\n        run: python3 -I tools/pipeline/sign_built.py --out signed\n      - name: Mark a pipeline fault on this leg\n", 1)], "c14 (a)(b)(c)")
mut("c14-build-tool-in-signing-job", [('        run: rm -f "$RUNNER_TEMP/signing.key"\n', '        run: rm -f "$RUNNER_TEMP/signing.key"; python3 tools/pipeline/build_version.py\n', 1)], "c14 (d)")
mut("c14-build-permissions-write", [("    timeout-minutes: 30\n    permissions:\n      contents: read\n", "    timeout-minutes: 30\n    permissions:\n      contents: write\n", 1)], "c14 (a)(b)(c)")
mut("c14-drop-signing-environment", [("    environment: signing\n", "", 1)], "c14 (f)")
mut("c14-environment-on-dry-run", [("    timeout-minutes: 15\n    permissions:\n      contents: read\n    strategy:", "    timeout-minutes: 15\n    environment: signing\n    permissions:\n      contents: read\n    strategy:", 1)], "c14 (f)")
mut("c15-test-only-flag", [('--workdir "$RUNNER_TEMP/work" --out out --no-sign', '--workdir "$RUNNER_TEMP/work" --out out --no-sign --max-entries 5', 1)], "c15 ")
mut("c17-input-in-run", [("          cat plan.json\n", '          echo "${{ inputs.version }}"; cat plan.json\n', 1)], "c17 ")
mut("c17-fail-fast-true", [("    strategy:\n      fail-fast: false\n", "    strategy:\n      fail-fast: true\n", "first")], "c17 ")
mut("c25-gate-removed-from-plan", [(GATE, "", "first")], "c25 ")
mut("c25-summary-condition-widened", [("    if: always() && github.event_name != 'push'\n", "    if: always() && github.event_name != 'push' || true\n", 1)], "c25 ")
mut("c26-drop-build-log-from-upload", [("            out/build.log\n", "", 1)], "c26a")
mut("c26-fail-fast-true-build", [("    strategy:\n      fail-fast: false\n", "    strategy:\n      fail-fast: true\n", "first")], "c26a")
mut("c26-fail-fast-true-sign", [("    strategy:\n      fail-fast: false\n", "    strategy:\n      fail-fast: true\n", 2)], "c17 ")
mut("c26-drop-always-from-sign-if", [("    if: always() && github.event_name != 'push' && github.ref == 'refs/heads/main'", "    if: github.event_name != 'push' && github.ref == 'refs/heads/main'", 1)], "c26a")
mut("c26-drop-per-version-guard", [("        if: steps.guard.outputs.proceed == 'true'\n        env:\n          MINISIGN_SECRET_KEY", "        env:\n          MINISIGN_SECRET_KEY", 1)], "c26a")

mut("c7-blank-pin-in-dry-run", [('MINISIGN_TARBALL_SHA256: "9a599b48ba6eb7b1e80f12f36b94ceca7c00b7a5173c95c3efc88d9822957e73"\n', 'MINISIGN_TARBALL_SHA256: ""\n', 2)], "c7 ")
mut("c7-blank-pin-in-sign", [('MINISIGN_TARBALL_SHA256: "9a599b48ba6eb7b1e80f12f36b94ceca7c00b7a5173c95c3efc88d9822957e73"\n', 'MINISIGN_TARBALL_SHA256: ""\n', "first")], "c7 ")

mut("c14-remove-unset", [("          unset MINISIGN_SECRET_KEY   # the python below parses untrusted build output: keep the key out of its environment\n", "", 1)], "c14 (d2)")
mut("c17-expression-in-run", [('          echo "pipeline fault (exit 2) while building this version; see build.stderr"\n', '          echo "pipeline fault ${{ matrix.tag }}"\n', 1)], "c17 ")
mut("c25-or-true-on-build", [("    if: github.event_name != 'push' && needs.plan.result == 'success' && needs.plan.outputs.has_build == 'true'\n", "    if: github.event_name != 'push' && needs.plan.result == 'success' && needs.plan.outputs.has_build == 'true' || true\n", 1)], "c25 ")
mut("c25-or-true-on-plan", [(GATE, "    if: github.event_name != 'push' || true\n", "first")], "c25 ")


def apply(text, edits):
    for old, new, nth in edits:
        n = text.count(old)
        want = 1 if nth == "first" else nth
        if (nth == 1 and n != 1) or n < want:
            sys.exit(f"HARD ERROR: anchor {old!r} found {n} times, wanted occurrence {nth}")
        i = -1
        for _ in range(want):
            i = text.index(old, i + 1)
        text = text[:i] + new + text[i + len(old):]
    return text


def run(path):
    r = subprocess.run([sys.executable, checker, path, contract], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


rc, out = run(wf)
if rc != 0:
    print("FAIL  positive control: the unmodified workflow does not pass\n" + out)
    sys.exit(99)
print("ok    positive control: the unmodified workflow passes every structural check")
failed = 0
for mid, edits, red in M:
    mutated = apply(orig, edits)
    assert mutated != orig, mid
    with tempfile.NamedTemporaryFile("w", suffix=".yml", delete=False, encoding="utf-8") as f:
        f.write(mutated)
    try:
        rc, out = run(f.name)
    finally:
        os.unlink(f.name)
    line = [l for l in out.splitlines() if l.startswith("FAIL") and red in l]
    if rc == 1 and line:
        print(f"ok    mutation {mid}: red as required ({line[0][:100]})")
    else:
        failed += 1
        print(f"FAIL  mutation {mid}: did not turn the check named '{red}' red\n{out}")
assert open(wf, encoding="utf-8").read() == orig, "the workflow file changed during the run"
sys.exit(failed)
PYEOF

cat > "$T/toolmutate.py" <<'PYEOF'
#!/usr/bin/env python3
"""Mutations of the tools: break one thing in a scratch copy of the COMMITTED tree (git archive HEAD); the named
unit tests must turn red. usage: toolmutate.py REPO. Exit code = number of mutations that did not turn red.
An anchor not found exactly once is a hard error, never a silent pass."""
import os
import shutil
import subprocess
import sys
import tempfile

repo = os.path.abspath(sys.argv[1])
BV, SB, HO = "tools/pipeline/build_version.py", "tools/pipeline/sign_built.py", "tools/pipeline/handoff.py"
M = [
    ("16a no-sign accepts --key/--pubkey", BV, [("        if args.key is not None or args.pubkey is not None:\n", "        if False:\n")],
     ["test_no_sign_with_key_or_pubkey_is_refused_before_any_clone"]),
    ("16c skip the sha re-check (both copies)", SB, [('    if actual != res["artifact"]["source_sha256"]:\n', "    if False:\n"), ("        if _sha256(tgz) != sha:\n", "        if False:\n")],
     ["test_c_valid_gzip_with_changed_content_is_a_sha_mismatch", "test_c_sha_mismatch_in_result_json_is_refused"]),
    ("16c skip the size re-check", SB, [("    if size > limits.max_compressed:\n", "    if False:\n")], ["test_c_size_over_limit_is_refused"]),
    ("16c skip the entry rules (inspect_archive)", SB, [("        archive.inspect_archive(tarball, limits)\n", "        pass\n")],
     ["test_c_extra_hostile_entry_with_matching_sha_is_refused_by_the_entry_rules", "test_c_size_over_limit_is_refused"]),
    ("16c skip reference_verify", SB, [("            reference_verify.verify(tgz, reference_verify.VersionClaim(", "            (lambda *a: None)(tgz, reference_verify.VersionClaim(")],
     ["test_signature_that_fails_the_reference_verifier_is_exit_2_class"]),
    ("26d omit the reason for exit 1", HO, [("        reason = rejection_reason(out_dir)\n", '        reason = ""\n')],
     ["test_b_exit1_after_start", "test_d_reason_from_stderr_else_from_the_log"]),
    ("26d empty reason no longer a fault", HO, [("        if not reason:\n            exit_code = 2\n", "        pass\n")], ["test_d_all_whitespace_reason_is_an_exit_2_fault"]),
    ("26b tarball written into build-<tag> for exit 1", HO,
     [("    return write_outcome(out_dir, version_id, tag, exit_code)\n\n\ndef finish_sign", '    if exit_code == 1:\n        open(os.path.join(out_dir, f"{tag}.tar.gz"), "wb").close()\n    return write_outcome(out_dir, version_id, tag, exit_code)\n\n\ndef finish_sign')],
     ["test_b_exit1_after_start"]),
    ("26c has_writeback ignores refuse", HO, [('    has_writeback = has_build or bool(plan["refuse"])\n', "    has_writeback = has_build\n")], ["test_c_plan_flags"]),
    ("26e tampered tarball mapped to exit_code 1", HO, [('"tag": tag, "exit_code": 2, "reason": ""}\n    _write_json(os.path.join(signed_dir', '"tag": tag, "exit_code": 1, "reason": ""}\n    _write_json(os.path.join(signed_dir')],
     ["test_e_every_sign_refusal_becomes_exit_code_2"]),
    ("F2 checkout assertion removed", HO, [("    if tracked and not os.path.isdir(os.path.join(repo, \"mods\")):\n", "    if False:\n"), ("    if missing:\n", "    if False:\n")],
     ["test_check_checkout_fails_closed_on_a_broken_or_sparse_checkout"]),
    ("F4 result allow-list removed", SB, [('        raise SignRefused("result/shape", "result.json has keys outside 008a\'s result shape")\n', "        pass\n")],
     ["test_result_json_with_unknown_keys_is_refused_at_every_level"]),
    ("F5 reason takes everything after the REJECTED line", HO, [('            text = err[m.start():].split("\\n", 1)[0]     # the one line, never what follows it\n', "            text = err[m.start():]\n")],
     ["test_d_reason_is_the_single_rejected_line_only"]),
]
failed = 0
for name, rel, edits, tests in M:
    scratch = tempfile.mkdtemp(prefix="w008b2-mut-")
    try:
        arc = subprocess.run(["git", "-C", repo, "archive", "HEAD"], capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", scratch], input=arc, check=True)
        path = os.path.join(scratch, rel)
        text = open(path, encoding="utf-8").read()
        for old, new in edits:
            if text.count(old) != 1:
                sys.exit(f"HARD ERROR: {name}: anchor {old!r} found {text.count(old)} times")
            text = text.replace(old, new)
        open(path, "w", encoding="utf-8").write(text)
        cmd = [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tests/pipeline", "-p", "test_handoff.py"]
        for t in tests:
            cmd += ["-k", t]
        r = subprocess.run(cmd, cwd=scratch, capture_output=True, text=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        out = r.stdout + r.stderr
        missing = [t for t in tests if f"FAIL: {t}" not in out and f"ERROR: {t}" not in out]
        if r.returncode != 0 and not missing:
            print(f"ok    mutation {name}: red as required ({len(tests)} named test(s) failed)")
        else:
            failed += 1
            print(f"FAIL  mutation {name}: rc={r.returncode}, named tests not red: {missing}\n{out[-600:]}")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
sys.exit(failed)
PYEOF

scope_base() {
  local r
  for r in origin/main refs/heads/main; do
    if git rev-parse -q --verify "$r^{commit}" >/dev/null 2>&1; then git merge-base HEAD "$r"; return $?; fi
  done
  return 1
}

if [ "${1:-}" = "--mutate" ]; then
  python3 "$T/wfmutate.py" "$T/wfcheck.py" "$WF" "$CONTRACT"; rc=$?
  [ "$rc" -eq 0 ] && ok "workflow mutations: all red, positive control green" || fail "workflow mutations: $rc problem(s)"
  python3 "$T/toolmutate.py" "$PWD"; rc=$?
  [ "$rc" -eq 0 ] && ok "tool mutations: all red" || fail "tool mutations: $rc did not turn red"
  git diff --quiet -- "$WF" tools tests docs && ok "working tree byte-identical after the mutations (they ran on scratch copies)" || fail "working tree changed"
  echo "SUMMARY mutate failed=$FAILS"; exit "$FAILS"
fi

# ---- criterion 13: this script
[ -x docs/tasks/008b2-verify.sh ] && ok "13: docs/tasks/008b2-verify.sh is executable" || fail "13: not executable"

# ---- criteria 1, 14, 15, 17, 25, 26(a): structural checks of the workflow (each fails on zero matches)
[ -f "$CONTRACT" ] && ok "1: contracts/pipeline-trigger.md is present" || fail "1: contracts/pipeline-trigger.md is missing (task 082 not merged)"
out=$(python3 "$T/wfcheck.py" "$WF" "$CONTRACT"); rc=$?
echo "$out" | sed 's/^/      /'
[ "$rc" -eq 0 ] && ok "workflow structural checks (criteria 1, 14, 15, 17, 25, 26a)" || fail "workflow structural checks"

# ---- criteria 16, 26(b)-(e) and the rest: the whole unit suite, 008a's tests unchanged
out=$(python3 -B -m unittest discover -s tests/pipeline 2>&1); rc=$?
echo "$out" | tail -4 | sed 's/^/      /'
[ "$rc" -eq 0 ] && ok "16, 26: the whole tests/pipeline suite passes (008a's, 008b-1's and test_handoff.py)" || fail "unit suite"
n=$(python3 -B -m unittest discover -s tests/pipeline -p test_handoff.py 2>&1 | sed -n 's/^Ran \([0-9]*\) tests.*/\1/p')
[ -n "$n" ] && [ "$n" -ge 20 ] && ok "test_handoff.py ran $n tests (zero-match guard: at least 20)" || fail "test_handoff.py ran '${n:-none}' tests"
if b=$(scope_base) && [ -n "$b" ]; then
  mod=$(git diff --name-status "$b" HEAD -- tests/pipeline | grep -v '^A' || true)
  [ -z "$mod" ] && ok "16(d): no pre-existing test file was modified (only additions)" || fail "16(d): existing tests modified: $mod"
  viol=$(git diff --name-only "$b" HEAD | grep -vxE "$SCOPE_RE" || true)
  [ -z "$viol" ] && ok "scope: every changed file is in the declared file scope" || fail "scope: out-of-scope changes: $viol"
else
  fail "scope and 16(d): no main ref to compute the base"
fi

# ---- criterion 18: docs
grep -q '^## The pipeline workflow (task 008b-2)' docs/pipeline/build-pipeline.md \
  && grep -q 'handoff' docs/pipeline/build-pipeline.md && grep -q 'dry-run' docs/pipeline/build-pipeline.md \
  && ok "18: build-pipeline.md has the workflow section (plan, build, sign, dry-run; handoff)" || fail "18: workflow section missing from build-pipeline.md"

echo "SUMMARY failed=$FAILS"
exit "$FAILS"
