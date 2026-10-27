"""Task 039b, AC7: the structure of .github/workflows/registry-ci.yml, asserted from the parsed file and from its text.

`check(text)` returns the list of violations of the trust model of 039 section 1 (empty = the file is acceptable). The
unmodified workflow must pass; every mutation listed in AC7 is applied to a COPY of the file in a temp directory and must be
red; "fails on zero matches" is shown by deleting each element the checks look for. PyYAML is required: a missing PyYAML
is an error here (an ImportError at import time), never a skip. PyYAML reads the key `on` as boolean True (YAML 1.1);
`triggers()` handles both spellings.

Run:   python3 -m unittest discover -s tests/registry -p test_ci_workflow.py -v
"""

import hashlib
import json
import re
import shlex
import tempfile
import unittest
from pathlib import Path

import yaml  # required; a missing PyYAML is a hard error, not a skip

REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github" / "workflows" / "registry-ci.yml"

SHA_USES = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?@[0-9a-f]{40}$")
PIPE = re.compile(r"(?<!\|)\|(?!\|)")  # a pipe, not the "||" of a fallback
TYPES = {"opened", "synchronize", "reopened", "edited"}
WRITERS = ("presence", "pre-pass", "membership", "gate")


def triggers(doc):
    """PyYAML parses the key `on` as True; accept True and the string spellings."""
    for key in (True, "on", "On", "ON"):
        if key in doc:
            return doc[key]
    return None


def steps_of(doc, job):
    return ((doc.get("jobs") or {}).get(job) or {}).get("steps") or []


def run_of(step):
    return step.get("run", "") if isinstance(step, dict) else ""


def joined(run):
    return run.replace("\\\n", " ")


def check(text):  # noqa: C901 - one flat list of independent rules reads better than a split
    v = []
    try:
        doc = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        return [f"does not parse: {exc}"]
    if not isinstance(doc, dict):
        return ["not a mapping"]

    # --- triggers, permissions, jobs ------------------------------------------------------------------------------
    on = triggers(doc)
    if not isinstance(on, dict) or set(on) != {"pull_request_target"}:
        v.append(f"triggers must be exactly pull_request_target, got {sorted(map(str, on)) if isinstance(on, dict) else on!r}")
    else:
        t = on["pull_request_target"] or {}
        if set(t.get("types") or []) != TYPES or len(t.get("types") or []) != 4:
            v.append(f"pull_request_target types must be exactly {sorted(TYPES)}")
        if set(t) - {"types", "branches"} or t.get("branches") != ["main"]:
            v.append("pull_request_target takes only types and branches: [main] (no paths, paths-ignore, tags)")
    if doc.get("permissions") != {}:
        v.append("top-level permissions must be {}")
    jobs = doc.get("jobs") or {}
    if set(jobs) != {"gate", "comment"}:
        v.append(f"jobs must be exactly gate and comment, got {sorted(jobs)}")
    for name, job in jobs.items():
        if not isinstance(job.get("timeout-minutes"), int):
            v.append(f"job {name}: timeout-minutes missing")
    gate = jobs.get("gate")
    if gate is None:
        return v + ["found no `gate` job"]
    comment = jobs.get("comment") or {}
    if gate.get("permissions") != {"contents": "read", "pull-requests": "read"}:
        v.append(f"gate permissions must be exactly contents: read, pull-requests: read, got {gate.get('permissions')!r}")
    if comment.get("permissions") != {"pull-requests": "write"}:
        v.append(f"comment permissions must be exactly pull-requests: write, got {comment.get('permissions')!r}")

    # --- comment job: no checkout, no repository code -------------------------------------------------------------
    for s in steps_of(doc, "comment"):
        if str(s.get("uses", "")).startswith("actions/checkout"):
            v.append("the comment job must not check anything out")
        if re.search(r"python|ci_gate|tools/registry|\bnpm\b|\bpip\b|\bmake\b|\bsource\b|(^|\s)\./", run_of(s)):
            v.append("the comment job's steps must not run repository code")
    if comment.get("needs") != "gate" or comment.get("if") != "always()":
        v.append("comment must be `needs: gate` with `if: always()`")
    if "--paginate" not in "".join(run_of(s) for s in steps_of(doc, "comment")):
        v.append("the comment job must list comments with --paginate when it looks for its marker")
    if "<!-- registry-ci-gate -->" not in "".join(run_of(s) for s in steps_of(doc, "comment")):
        v.append("the comment job must look for the marker <!-- registry-ci-gate -->")

    # --- find the steps the rules are about (zero matches fail) ---------------------------------------------------
    steps = steps_of(doc, "gate")
    ci = [s for s in steps if "ci_gate.py" in run_of(s) and "--classify-only" not in run_of(s)]
    pre = [s for s in steps if "ci_gate.py" in run_of(s) and "--classify-only" in run_of(s)]
    mint = [s for s in steps if str(s.get("uses", "")).startswith("actions/create-github-app-token@")]
    member = [s for s in steps if re.search(r"\bcurl\b", run_of(s))]
    present = [s for s in steps if not s.get("uses") and "present=" in run_of(s)]
    checkout = [s for s in steps if str(s.get("uses", "")).startswith("actions/checkout@")]
    for label, found in (("`ci_gate.py` gate", ci), ("`ci_gate.py --classify-only` pre-pass", pre), ("token-mint", mint),
                         ("membership `curl`", member), ("presence", present), ("checkout", checkout)):
        if len(found) != 1:
            v.append(f"found no {label} step (or more than one): {len(found)}")
    if len(ci) != 1 or len(pre) != 1 or len(mint) != 1 or len(member) != 1 or len(present) != 1 or len(checkout) != 1:
        return v
    ci, pre, mint, member, present, checkout = ci[0], pre[0], mint[0], member[0], present[0], checkout[0]

    # --- injection rule -------------------------------------------------------------------------------------------
    for job in jobs:
        for s in steps_of(doc, job):
            if "${{" in run_of(s):
                v.append(f"{job}: a run block contains ${{{{ : {run_of(s).strip().splitlines()[0][:60]!r}")
    for name in ("GITHUB_ENV", "GITHUB_PATH"):
        if re.search(rf"\b{name}\b", text):
            v.append(f"{name} must appear nowhere")
    writers = [s for s in steps if "GITHUB_OUTPUT" in run_of(s)]
    expected = [present, pre, member, ci]
    if len(writers) != 4 or any(not any(w is e for e in expected) for w in writers):
        v.append(f"GITHUB_OUTPUT may be written only by the presence, pre-pass, membership and ci_gate steps ({len(writers)} writers)")
    if any("GITHUB_OUTPUT" in run_of(s) for s in steps_of(doc, "comment")):
        v.append("the comment job must not write GITHUB_OUTPUT")
    for line in run_of(present).splitlines():
        if "GITHUB_OUTPUT" in line and not re.fullmatch(r'\s*if \[ -n "\$[A-Z_]+" \]; then echo "present=true" >> "\$GITHUB_OUTPUT"; '
                                                         r'else echo "present=false" >> "\$GITHUB_OUTPUT"; fi\s*', line):
            v.append(f"the presence step may write only present=true|false: {line.strip()!r}")

    # --- secrets (C18): exactly the presence and the mint step ----------------------------------------------------
    holders = [s for job in jobs for s in steps_of(doc, job) if "secrets." in json.dumps(s)]
    if len(holders) != 2 or not any(h is present for h in holders) or not any(h is mint for h in holders):
        v.append(f"`secrets.` must appear in exactly the presence and token-mint steps, found {len(holders)} step(s)")
    if "secrets." in json.dumps({k: x for k, x in present.items() if k != "env"}):
        v.append("the presence step may use secrets only in env:")
    var = re.findall(r"\$\{?([A-Z_]+)", " ".join(f"${k}" for k in present.get("env", {})))
    stripped = re.sub(r'\[ -n "\$[A-Z_]+" \]', "", run_of(present))
    if any(re.search(rf"\$\{{?{k}\b", stripped) for k in var):
        v.append("the presence step prints or uses something derived from the secret")
    if not SHA_USES.match(str(mint.get("uses", ""))):
        v.append("the token-mint step must be pinned to a 40-hex SHA")
    if "if" not in mint or f"steps.{present.get('id')}.outputs.present == 'true'" not in str(mint["if"]):
        v.append("the token-mint step needs `if: steps.<presence>.outputs.present == 'true'`")
    members_perm = {k: x for k, x in (mint.get("with") or {}).items() if k.startswith("permission-")}
    if members_perm != {"permission-members": "read"}:
        v.append(f"the minted token must be scoped to Members: read only, got {members_perm}")
    token_ref = f"steps.{mint.get('id')}.outputs"
    for job in jobs:
        for s in steps_of(doc, job):
            where = json.dumps(s)
            if token_ref in where and not (s is member and token_ref in json.dumps(s.get("env", {})) and token_ref not in json.dumps(
                    {k: x for k, x in s.items() if k != "env"})):
                v.append("the minted token may appear only in the membership step's env")
    for bad in ("PIPELINE_APP_PRIVATE_KEY", "MINISIGN_SECRET_KEY"):
        if bad in text:
            v.append(f"{bad} must appear nowhere")
    if "secrets." in json.dumps(member) or "secrets." in json.dumps(ci) or "secrets." in json.dumps(pre):
        v.append("`secrets.` in the membership, pre-pass or gate step")

    # --- pins and checkout ----------------------------------------------------------------------------------------
    for job in jobs:
        for s in steps_of(doc, job):
            if "uses" in s and not SHA_USES.match(str(s["uses"])):
                v.append(f"unpinned uses: {s['uses']}")
    with_ = checkout.get("with") or {}
    if with_.get("persist-credentials") is not False or "ref" in with_ or with_.get("fetch-depth") != 0:
        v.append("checkout needs fetch-depth: 0, persist-credentials: false and no ref")

    # --- membership curl (I5/R9: no redirects followed) -----------------------------------------------------------
    cmd = next((m.group(0) for line in joined(run_of(member)).splitlines() if (m := re.search(r"\bcurl\b.*", line))), "")
    cmd = re.sub(r'\)"\s*(\|\|.*)?$', "", cmd)  # drop the closing of the command substitution and the fallback
    try:
        toks = shlex.split(cmd)
    except ValueError as exc:
        toks = []
        v.append(f"membership run does not tokenise: {exc}")
    if "curl" in toks:
        args = toks[toks.index("curl") + 1:]
        for end, a in enumerate(args):
            if a in ("||", "&&", ";", "then", "fi"):
                args = args[:end]
                break
        for a in args:
            if re.fullmatch(r"-[A-Za-z]+", a) and "L" in a:
                v.append(f"curl flag cluster with L (follows redirects): {a}")
            if a.startswith("--location") or a.startswith("--proto-redir"):
                v.append(f"curl follows or re-protocols redirects: {a}")
        if not any(args[i] == "-o" and args[i + 1] == "/dev/null" for i in range(len(args) - 1)):
            v.append("curl needs -o /dev/null")
        if not any(args[i] == "-w" and args[i + 1] == "%{http_code}" for i in range(len(args) - 1)):
            v.append("curl needs -w '%{http_code}'")
        if "--max-time" not in args:
            v.append("curl needs --max-time")
    else:
        v.append("found no curl in the membership step")
    if "[0-9]{3}" not in run_of(member) or "none" not in run_of(member):
        v.append("the membership step must map an empty or non-3-digit status to none")

    # --- gate cannot go green by accident -------------------------------------------------------------------------
    for s in steps + [gate]:
        if "continue-on-error" in s:
            v.append("continue-on-error in the gate job")
    gate_text = "\n".join(run_of(s) for s in steps)
    if re.search(r"\|\|\s*true\b", gate_text) or re.search(r"\bset\s+\+e\b", gate_text):
        v.append("`|| true` or `set +e` in the gate job")
    if "if" in ci:
        v.append("the ci_gate.py step must have no `if:`")
    if PIPE.search(joined(run_of(ci))) and not (ci.get("shell") or "").startswith("bash"):
        v.append("the ci_gate.py step's run has a pipe")
    later = steps[steps.index(ci) + 1:]
    if not later or any(not str(s.get("uses", "")).startswith("actions/upload-artifact@") for s in later):
        v.append("every step after the ci_gate.py step must be actions/upload-artifact")
    if 'exit "$rc"' not in run_of(ci):
        v.append("the ci_gate.py step must exit with the composer's status")
    if "--tools-dir" in text or "--paths-file" in text:
        v.append("--tools-dir / --paths-file must appear nowhere (the composer has no such option; paths go after --)")
    return v


def mutate(text, name):
    """The AC7 mutations. Each returns a changed copy of `text`; a mutation that changes nothing is itself a failure."""
    def after_line(anchor, new, indent_of=None):
        out, hit = [], 0
        for line in text.splitlines(keepends=True):
            out.append(line)
            if line.strip() == anchor:
                hit += 1
                out.append(new if new.endswith("\n") else new + "\n")
        assert hit == 1, f"{name}: anchor {anchor!r} matched {hit} times"
        return "".join(out)

    def in_step(step, key_line=None, run_line=None, env_line=None):
        """Insert into the step named `step`: a key right after `- name:`, the first line of its run, or an env entry."""
        lines, out, i, hit = text.splitlines(keepends=True), [], 0, 0
        while i < len(lines):
            out.append(lines[i])
            if lines[i].strip() == f"- name: {step}":
                hit += 1
                if key_line:
                    out.append(f"        {key_line}\n")
                j = i + 1
                while j < len(lines) and not lines[j].lstrip().startswith("- name:") and not re.match(r"^  \S", lines[j]):
                    out.append(lines[j])
                    if run_line and lines[j].strip() == "run: |":
                        out.append(f"          {run_line}\n")
                    if env_line and lines[j].strip() == "env:":
                        out.append(f"          {env_line}\n")
                    j += 1
                i = j
                continue
            i += 1
        assert hit == 1, f"{name}: step {step!r} matched {hit} times"
        return "".join(out)

    def replace(old, new, count=1):
        assert text.count(old) == count, f"{name}: {old!r} occurs {text.count(old)} times, expected {count}"
        return text.replace(old, new)

    gate_step, member_step, comment_step = "Run the gate", "Ask the organisation whether the author is a member", "Create or update the one comment"
    table = {
        "add a pull_request trigger": lambda: replace("on:\n  pull_request_target:", "on:\n  pull_request:\n  pull_request_target:"),
        "gate permissions write-all": lambda: replace("    permissions:\n      contents: read\n      pull-requests: read\n",
                                                      "    permissions: write-all\n"),
        "checkout ref from the PR head": lambda: replace("          fetch-depth: 0\n",
                                                         "          fetch-depth: 0\n          ref: ${{ github.event.pull_request.head.sha }}\n"),
        "PR title in a run": lambda: in_step("Fetch the pull request head as objects only",
                                             run_line='echo "${{ github.event.pull_request.title }}"'),
        "needs.gate.outputs in a run": lambda: in_step(comment_step, run_line='echo "${{ needs.gate.outputs.x }}"'),
        "curl -L": lambda: replace(" --max-time", " -L --max-time"),
        "curl -sSL": lambda: replace("curl -sS ", "curl -sSL "),
        "curl --location": lambda: replace(" --max-time", " --location --max-time"),
        "curl --proto-redir": lambda: replace(" --max-time", " --proto-redir =all --max-time"),
        "curl without -o /dev/null": lambda: replace(" -o /dev/null", ""),
        "curl without --max-time": lambda: replace(" --max-time 20", ""),
        "continue-on-error on a gate step": lambda: in_step(gate_step, key_line="continue-on-error: true"),
        "continue-on-error on the pre-pass": lambda: in_step("Pre-pass, classify only", key_line="continue-on-error: true"),
        "an if on the ci_gate.py step": lambda: in_step(gate_step, key_line="if: always()"),
        "a pipe in the ci_gate.py run": lambda: in_step(gate_step, run_line="echo x | cat"),
        "|| true in the gate job": lambda: in_step(gate_step, run_line="false || true"),
        "set +e in the gate job": lambda: in_step(gate_step, run_line="set +e"),
        "secrets in the membership step": lambda: in_step(member_step, env_line="EXTRA: ${{ secrets.OTHER }}"),
        "secrets in a third step": lambda: in_step("Read the pull request object", env_line="EXTRA: ${{ secrets.OTHER }}"),
        "a GITHUB_ENV write": lambda: in_step("Pre-pass, classify only", run_line='echo "X=1" >> "$GITHUB_ENV"'),
        "a GITHUB_PATH write": lambda: in_step("Pre-pass, classify only", run_line='echo "/tmp" >> "$GITHUB_PATH"'),
        "a fifth GITHUB_OUTPUT writer": lambda: in_step("Read the pull request object", run_line='echo "x=1" >> "$GITHUB_OUTPUT"'),
        "drop a timeout-minutes": lambda: replace("    timeout-minutes: 10\n", ""),
        "unpin one uses": lambda: re.sub(r"actions/checkout@[0-9a-f]{40}", "actions/checkout@v6", text, count=1),
        "a paths filter": lambda: after_line("branches: [main]", "    paths: ['mods/**']"),
        "workflow_run trigger": lambda: replace("on:\n  pull_request_target:", "on:\n  workflow_run:\n    workflows: [x]\n  pull_request_target:"),
        "PIPELINE_APP_PRIVATE_KEY": lambda: in_step("Read the pull request object", env_line="K: ${{ vars.PIPELINE_APP_PRIVATE_KEY }}"),
        "the presence step prints the secret": lambda: in_step("Is the membership App configured", run_line='echo "$APP_KEY"'),
        "the minted token in the gate step": lambda: in_step(gate_step, env_line="T: ${{ steps.mint.outputs.token }}"),
        "--tools-dir passed to the composer": lambda: replace("tools/registry/ci_gate.py --repo .", "tools/registry/ci_gate.py --tools-dir x --repo ."),
        "the comment job checks out": lambda: replace("    steps:\n      - name: Fetch the verdict and the comment text\n",
                                                      "    steps:\n      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd\n"
                                                      "      - name: Fetch the verdict and the comment text\n"),
        "comment runs repository code": lambda: in_step(comment_step, run_line="python3 tools/registry/ci_gate.py"),
        "comment without --paginate": lambda: replace("--paginate ", ""),
        "a step after the gate that is not an upload": lambda: replace("      - name: Keep the verdict and the comment text\n",
                                                                       "      - name: After\n        run: echo done\n"
                                                                       "      - name: Keep the verdict and the comment text\n"),
    }
    return table[name]()


MUTATIONS = [
    "add a pull_request trigger", "gate permissions write-all", "checkout ref from the PR head", "PR title in a run",
    "needs.gate.outputs in a run", "curl -L", "curl -sSL", "curl --location", "curl --proto-redir", "curl without -o /dev/null",
    "curl without --max-time", "continue-on-error on a gate step", "continue-on-error on the pre-pass", "an if on the ci_gate.py step",
    "a pipe in the ci_gate.py run", "|| true in the gate job", "set +e in the gate job", "secrets in the membership step",
    "secrets in a third step", "a GITHUB_ENV write", "a GITHUB_PATH write", "a fifth GITHUB_OUTPUT writer", "drop a timeout-minutes",
    "unpin one uses", "a paths filter", "workflow_run trigger", "PIPELINE_APP_PRIVATE_KEY", "the presence step prints the secret",
    "the minted token in the gate step", "--tools-dir passed to the composer", "the comment job checks out",
    "comment runs repository code", "comment without --paginate", "a step after the gate that is not an upload",
]


class WorkflowTestCase(unittest.TestCase):
    def setUp(self):  # per test (not setUpClass): a missing workflow makes EVERY test error, which is the red state
        self.raw = WORKFLOW.read_bytes()
        self.text = self.raw.decode("utf-8")
        self.digest = hashlib.sha256(self.raw).hexdigest()

    def tearDown(self):
        self.assertEqual(hashlib.sha256(WORKFLOW.read_bytes()).hexdigest(), self.digest, "the workflow file changed during a test")


class AC7Structure(WorkflowTestCase):
    def test_unmodified_workflow_passes_every_rule(self):  # positive control
        self.assertEqual(check(self.text), [])

    def test_pyyaml_reads_on_as_true_and_both_spellings_are_handled(self):
        self.assertIn(True, yaml.safe_load(self.text), "PyYAML 1.1 reads the bare key `on` as True (the test relies on handling it)")
        quoted = self.text.replace("\non:\n", '\n"on":\n', 1)
        self.assertNotEqual(quoted, self.text)
        self.assertIn("on", yaml.safe_load(quoted))
        self.assertEqual(check(quoted), [], "the string spelling of `on` is read like the boolean one")
        self.assertIsNone(triggers({"jobs": {}}))

    def test_exactly_the_documented_shape(self):
        doc = yaml.safe_load(self.text)
        self.assertEqual(triggers(doc), {"pull_request_target": {"types": ["opened", "synchronize", "reopened", "edited"], "branches": ["main"]}})
        self.assertEqual(doc["permissions"], {})
        self.assertEqual(set(doc["jobs"]), {"gate", "comment"})
        self.assertNotIn("name", doc["jobs"]["gate"], "the required check is named by the job id `gate`; a `name:` would rename it")

    def test_every_uses_is_pinned_and_none_is_missing(self):
        uses = [s["uses"] for j in yaml.safe_load(self.text)["jobs"].values() for s in j["steps"] if "uses" in s]
        self.assertGreaterEqual(len(uses), 4, "checkout, mint, upload, download")
        for u in uses:
            self.assertRegex(u, SHA_USES)

    def test_workflow_is_small_enough_to_review(self):
        self.assertLessEqual(len(self.text.splitlines()), 200)

    def test_no_composer_option_that_the_cli_lacks(self):
        self.assertNotIn("--tools-dir", self.text)
        self.assertNotIn("--paths-file", self.text)

    def test_run_log_link_is_built_by_the_workflow_not_the_composer(self):
        comment = "".join(run_of(s) for s in yaml.safe_load(self.text)["jobs"]["comment"]["steps"])
        self.assertIn("GITHUB_RUN_ID", comment)

    def test_missing_artifact_comment_is_worded_by_the_gate_result(self):  # security review S3
        comment = joined("".join(run_of(s) for s in yaml.safe_load(self.text)["jobs"]["comment"]["steps"]))
        self.assertRegex(comment, r'\[ "\$GATE_RESULT" = failure \]', "the fixed text must branch on needs.gate.result == failure")
        self.assertIn("the gate failed", comment)
        failed_branch = comment.split('"$GATE_RESULT" = failure', 1)[1].split("else", 1)[0]
        self.assertNotIn("not a rejection", failed_branch, "a failed gate must never be called 'not a rejection'")
        self.assertNotIn("${{", comment, "no expression inside run:")


class AC7ZeroMatches(WorkflowTestCase):
    """A rule that matches nothing proves nothing: deleting the thing it looks for must make the checker complain."""

    def test_each_missing_element_is_reported(self):
        cases = {
            "gate job": ("  gate:\n", "  gatex:\n"),
            "ci_gate step": ("tools/registry/ci_gate.py --repo .", "tools/registry/other.py --repo ."),
            "pre-pass step": ("--classify-only", "--classify"),
            "mint step": ("actions/create-github-app-token@", "actions/other-action@"),
            "membership curl": ("curl -sS", "wget -q"),
            "presence step": ("present=", "found="),
            "checkout": ("actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2", "actions/other@de0fac2e4500dabe0009e67214ff5f5447ce83dd"),
        }
        for label, (old, new) in cases.items():
            with self.subTest(label):
                self.assertIn(old, self.text, f"the zero-match case for {label} needs its anchor")
                found = check(self.text.replace(old, new))
                self.assertTrue(any("found no" in x for x in found), f"{label}: {found}")

    def test_an_empty_or_unrelated_document_is_red(self):
        for text in ("", "name: x\n", "jobs: {}\n", "[1, 2]\n", "on: [push\n"):
            with self.subTest(text=text):
                self.assertTrue(check(text))


class AC7Mutations(WorkflowTestCase):
    def test_every_mutation_is_red_and_the_file_is_restored_byte_identically(self):
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "registry-ci.yml"
            for name in MUTATIONS:
                with self.subTest(mutation=name):
                    copy.write_bytes(self.raw)
                    copy.write_text(mutate(self.text, name))
                    self.assertNotEqual(copy.read_bytes(), self.raw, f"{name}: the mutation changed nothing")
                    found = check(copy.read_text())
                    self.assertTrue(found, f"{name}: the mutated workflow was not rejected")
                    copy.write_bytes(self.raw)  # restore
                    self.assertEqual(copy.read_bytes(), self.raw)
                    self.assertEqual(check(copy.read_text()), [], f"{name}: the restored file must pass again")
        self.assertGreaterEqual(len(MUTATIONS), 15, "AC7 names 15 mutations; more are fine")

    def test_the_mutations_named_by_ac7_are_all_present(self):
        required = {"add a pull_request trigger", "gate permissions write-all", "checkout ref from the PR head", "PR title in a run",
                    "needs.gate.outputs in a run", "curl -L", "curl -sSL", "curl without -o /dev/null", "continue-on-error on a gate step",
                    "an if on the ci_gate.py step", "a pipe in the ci_gate.py run", "secrets in the membership step", "a GITHUB_ENV write",
                    "drop a timeout-minutes", "unpin one uses", "a paths filter"}
        self.assertEqual(required - set(MUTATIONS), set())


if __name__ == "__main__":
    unittest.main()
