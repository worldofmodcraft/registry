"""The CI composer (task 039, session 1): tools/registry/ci_gate.py, offline.

Every case builds a throwaway git repository (base commit = a fixture registry state, head commit = the fixture PR)
and feeds the composer recorded event / PR-object payloads from fixtures/ci/. No network, no credential, no live PR.
Covers acceptance criteria AC1-AC6 and AC8 (AC9 at the bottom); AC7 (the workflow file) belongs to session 2.

Run with:   python3 -m unittest discover -s tests/registry -v
"""

import ast
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support
from support import commit_for, entry, pending, published, removed

REPO = Path(__file__).resolve().parents[2]
CI_GATE = REPO / "tools" / "registry" / "ci_gate.py"
FIX = Path(__file__).resolve().parent / "fixtures" / "ci"
EVENT_FIXTURE = (FIX / "event.pull_request_target.json").read_text()
PR_FIXTURE = (FIX / "pr.get-pull.json").read_text()

ALICE, MALLORY, MEMBER, ORG_ID = 100200300, 900800700, 777000, 324218296
ALICE_OWNER = {"provider": "github", "id": ALICE, "name_at_registration": "alice"}
ORG_OWNER = {"provider": "github", "id": ORG_ID, "name_at_registration": "worldofmodcraft"}
NOTICE_FRAGMENT = "permanently bound to your GitHub account"
NOTICE_ALICE = ("This creates the namespace `alice:` permanently bound to your GitHub account (id 100200300). "
                "Namespaces are never reassigned.")
MARKER = "<!-- registry-ci-gate -->"
NAME_RE = r"[A-Za-z0-9](-?[A-Za-z0-9]){0,38}"
STRICT_LINES = [re.compile(p) for p in (
    r"class=(entry|page-only|reserved-namespace|other)", r"result=(accepted|rejected|undecided)",
    r"route=(infra|content|empty)", r"pr=[0-9]+", r"head_sha=[0-9a-f]{40}", r"merge_base=[0-9a-f]{40}",
    f"org={NAME_RE}", f"login={NAME_RE}")]


class Link:
    def __init__(self, target):
        self.target = target


class Gitlink:
    def __init__(self, sha="1" * 40):
        self.sha = sha


def alice_entry(*versions):
    return entry(*versions, id="alice:demo", owner=ALICE_OWNER)


def js(obj):
    return json.dumps(obj, indent=2) + "\n"


def base_files():
    files = {"README.md": "registry\n", "reserved-namespaces.json": (REPO / "reserved-namespaces.json").read_text(),
             "config/r11-identity.json": js({"schema_version": "1.0.0", "r11_identity": None}),
             "mods/alice.demo/entry.json": js(alice_entry(published())),
             "mods/alice.demo/page.json": js({"description": "d", "screenshots": [], "tags": [], "links": [],
                                              "deprecated": False})}
    for p in (REPO / "tools" / "registry").glob("*.py"):
        if p.name != "ci_gate.py":
            files[f"tools/registry/{p.name}"] = p.read_text()
    files["tests/contracts/schema_check.py"] = (REPO / "tests" / "contracts" / "schema_check.py").read_text()
    for p in (REPO / "contracts").glob("*.json"):
        files[f"contracts/{p.name}"] = p.read_text()
    return files


class World:
    """A throwaway repository: `main` is the base-branch checkout, PR branches hang off it."""

    def __init__(self, tc, files=None):
        self.tc = tc
        self.ws = Path(tempfile.mkdtemp(prefix="ci039-"))
        tc.addCleanup(shutil.rmtree, self.ws, True)
        self.repo = self.ws / "repo"
        self.repo.mkdir()
        self.env = {"PATH": os.environ["PATH"], "HOME": str(self.ws), "GIT_CONFIG_NOSYSTEM": "1",
                    "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.org",
                    "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.org"}
        self.git("init", "-q", "-b", "main")
        self.apply(base_files() if files is None else files)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD").strip()
        self.runs = 0

    def git(self, *args, input=None, check=True):
        r = subprocess.run(["git", *args], cwd=self.repo, env=self.env, capture_output=True, input=input)
        if check and r.returncode:
            raise AssertionError(f"git {args} failed: {r.stderr.decode(errors='replace')}")
        return r.stdout.decode(errors="surrogateescape") if input is None or isinstance(input, bytes) else r.stdout

    def apply(self, changes):
        for rel, val in changes.items():
            p = self.repo / rel
            if val is None:
                p.unlink()
                continue
            p.parent.mkdir(parents=True, exist_ok=True)
            if p.is_symlink() or p.exists():
                p.unlink()
            if isinstance(val, Link):
                os.symlink(val.target, p)
            elif isinstance(val, Gitlink):
                continue
            else:
                p.write_bytes(val if isinstance(val, bytes) else val.encode())

    def commit_on_main(self, changes, message="main moves"):
        self.apply(changes)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD").strip()

    def pr(self, changes, name="pr", message="pr", allow_empty=False):
        """Commit `changes` on a branch cut from main; leave main checked out. Returns the head sha."""
        self.git("checkout", "-q", "-b", name, "main")
        self.apply(changes)
        self.git("add", "-A")
        for rel, val in changes.items():
            if isinstance(val, Gitlink):
                self.git("update-index", "--add", "--cacheinfo", f"160000,{val.sha},{rel}")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        head = self.git("rev-parse", "HEAD").strip()
        self.git("checkout", "-q", "-f", "main")
        return head

    def blob(self, data):
        return self.git("hash-object", "-w", "--stdin", input=data if isinstance(data, bytes) else data.encode()).strip()

    def raw_tree(self, entries):
        """entries: [(mode, name-bytes-or-str, sha)]; written with --literally so malformed trees are possible."""
        raw = b"".join(m.encode() + b" " + (n if isinstance(n, bytes) else n.encode()) + b"\0" + bytes.fromhex(s)
                       for m, n, s in entries)
        return self.git("hash-object", "-w", "--literally", "-t", "tree", "--stdin", input=raw).strip()

    def craft(self, mods_entries, name="crafted"):
        """A head commit (parent: main) whose `mods` tree is built from raw entries."""
        mods = self.raw_tree(mods_entries)
        root = []
        for rec in self.git("ls-tree", "-z", "main").split("\0"):
            if rec:
                head, nm = rec.split("\t", 1)
                mode, _, sha = head.split(" ")
                root.append(("40000" if mode == "040000" else mode, nm, mods if nm == "mods" else sha))
        head = self.git("commit-tree", self.raw_tree(root), "-p", "main", "-m", "crafted").strip()
        self.git("update-ref", f"refs/heads/{name}", head)
        return head


class Result:
    def __init__(self, code, out, stderr=""):
        self.code, self.out, self.stderr = code, Path(out), stderr
        self.comment = self._read("comment.md")
        self.cls = self._read("class").strip()
        self.outputs = self._read("outputs")
        v = self._read("verdict.json")
        self.verdict = json.loads(v) if v else None

    def _read(self, name):
        p = self.out / name
        return p.read_text() if p.is_file() else ""


def payloads(w, head, *, number=7, uid=ALICE, login="alice", base_sha=None, event=None, pr=None, pr_file="ok"):
    w.runs += 1
    ev, prj = json.loads(EVENT_FIXTURE), json.loads(PR_FIXTURE)
    for d in (ev["pull_request"], prj):
        d["number"] = number
        d["user"].update(id=uid, login=login)
        d["head"]["sha"] = head
        d["base"]["sha"] = base_sha or w.base
    ev["number"] = number
    for mut, doc in ((event, ev), (pr, prj)):
        if mut:
            mut(doc)
    e, p = w.ws / f"event{w.runs}.json", w.ws / f"pr{w.runs}.json"
    e.write_text(json.dumps(ev))
    if pr_file == "ok":
        p.write_text(json.dumps(prj))
    elif pr_file == "garbage":
        p.write_text("{not json")
    return e, p, w.ws / f"out{w.runs}"


def run_cli(w, head, *, status="none", classify_only=False, env=None, **kw):
    e, p, out = payloads(w, head, **kw)
    argv = [sys.executable, "-I", str(CI_GATE), "--repo", str(w.repo), "--event", str(e), "--pr", str(p),
            "--out", str(out)]
    argv += ["--classify-only"] if classify_only else ["--membership-status", status]
    r = subprocess.run(argv, capture_output=True, text=True, env={"PATH": "/usr/bin:/bin", "HOME": str(w.ws),
                                                                  "LANG": "C.UTF-8", **(env or {})})
    return Result(r.returncode, out, r.stderr)


def run_lib(w, head, *, status="none", classify_only=False, **kw):
    import ci_gate
    lib = {k: kw.pop(k) for k in list(kw) if k in ("tools_dir", "checker_timeout", "git_timeout", "max_blob_bytes",
                                                    "max_entries", "tmp_parent")}
    e, p, out = payloads(w, head, **kw)
    code = ci_gate.run_gate(w.repo, e, p, out, None if status is None else status, classify_only=classify_only, **lib)
    return Result(code, out)


def snapshot(root):
    return sorted((str(p.relative_to(root)), p.is_symlink(), p.stat().st_size if p.is_file() else -1)
                  for p in Path(root).rglob("*"))


def outside_fences(text):
    """The text of a comment that is not inside a backtick fence (a closing fence is at least as long as the opening)."""
    out, fence = [], 0
    for line in text.split("\n"):
        m = re.fullmatch(r"(`{3,})", line)
        if fence == 0 and m:
            fence = len(m.group(1))
        elif fence and m and len(m.group(1)) >= fence:
            fence = 0
        elif fence == 0:
            out.append(line)
    return "\n".join(out)


def write_stubs(d, behaviours, record=None):
    """Stub checker directory: cli.py (classify|schema|append-only) and ownership_cli.py with scripted behaviour
    {name: (exit, stdout, stderr, sleep_seconds)}. A record file collects the name of every stub that ran."""
    d = Path(d)
    d.mkdir(parents=True, exist_ok=True)
    body = ("import json, sys, time\nB = json.loads(%r)\nREC = %r\n"
            "name = sys.argv[1] if sys.argv[1] in B else NAME\n"
            "if REC:\n    open(REC, 'a').write(name + '\\n')\n"
            "code, out, err, nap = B[name]\ntime.sleep(nap)\nsys.stdout.write(out)\nsys.stderr.write(err)\nsys.exit(code)\n")
    (d / "cli.py").write_text("NAME = None\n" + body % (json.dumps(behaviours), str(record) if record else ""))
    (d / "ownership_cli.py").write_text("NAME = 'ownership'\n" + body % (json.dumps(behaviours), str(record) if record else ""))
    return d


def acc(checker, **extra):
    return json.dumps({"checker": checker, "verdict": "accepted", "findings": [], **extra})


def rej(checker, **extra):
    f = [{"rules": ["stub"], "path": None, "index": None, "message": "stub (stub): rejected. To fix: nothing"}]
    return json.dumps({"checker": checker, "verdict": "rejected", "findings": f, **extra})


ALL_OK = {"classify": (0, acc("classify", **{"class": "entry"}), "", 0), "schema": (0, acc("schema"), "", 0),
          "append-only": (0, acc("append-only"), "", 0), "ownership": (0, acc("ownership", merge_signal=False), "", 0)}


def first_publish_changes(ns="alice", name="demo2", own=None):
    return {f"mods/{ns}.{name}/entry.json": js(entry(pending(), id=f"{ns}:{name}", owner=own or ALICE_OWNER))}


def add_version_changes():
    return {"mods/alice.demo/entry.json": js(alice_entry(published(), pending("1.1.0", commit_for("v1.1"))))}


def reserved_publish(extra=None):
    return {"mods/test.hello-world/entry.json": js(entry(pending(), id="test:hello-world", owner=ORG_OWNER)),
            **(extra or {})}


class Base(unittest.TestCase):
    def world(self, files=None):
        return World(self, files)

    def check(self, res, code, *needles, absent=()):
        self.assertEqual(res.code, code, f"stderr: {getattr(res, 'stderr', '')}\ncomment:\n{res.comment}")
        self.assertIsNotNone(res.verdict, "the composer must always leave verdict.json (a missing one means it never ran)")
        self.assertEqual(res.verdict["result"], {0: "accepted", 1: "rejected", 2: "undecided"}[code])
        for n in needles:
            self.assertIn(n, res.comment)
        for n in absent:
            self.assertNotIn(n, res.comment)
        if code != 0:
            self.assertNotIn(NOTICE_FRAGMENT, res.comment, "ADR-0058 section 3 notice on a non-accepted PR")
        for line in res.outputs.splitlines():
            self.assertTrue(any(r.fullmatch(line) for r in STRICT_LINES), f"non-strict outputs line {line!r}")
        self.assertLess(len(res.comment), 65000)
        return res


class AC1RegistryTrio(Base):
    """Mission section 7 criterion 1: each registry rejection, exit 1, with the named rule in comment.md."""

    def test_invalid_schema_owner_id_as_string(self):
        w = self.world()
        bad = entry(pending(), id="alice:demo2", owner={**ALICE_OWNER, "id": "100200300"})
        head = w.pr({"mods/alice.demo2/entry.json": js(bad)})
        res = self.check(run_cli(w, head), 1, "schema")
        self.assertIn("mods/alice.demo2/entry.json", res.comment)

    def test_wrong_account_for_existing_namespace_ids_not_usernames(self):
        w = self.world()
        head = w.pr(add_version_changes())
        res = self.check(run_cli(w, head, uid=MALLORY, login="alice"), 1, "R3", str(MALLORY), str(ALICE))

    def test_modified_version_object_by_its_own_owner(self):
        w = self.world()
        head = w.pr({"mods/alice.demo/entry.json": js(alice_entry(published(commit=commit_for("other"))))})
        self.check(run_cli(w, head), 1, "rule 1")


class AC2PositiveControls(Base):
    def test_first_publish_of_alice_demo(self):
        files = base_files()
        del files["mods/alice.demo/entry.json"], files["mods/alice.demo/page.json"]
        w = self.world(files)
        head = w.pr({"mods/alice.demo/entry.json": js(entry(pending(), id="alice:demo", owner=ALICE_OWNER))})
        res = self.check(run_cli(w, head), 0, NOTICE_ALICE, MARKER)
        self.assertIn("never reassigned", res.comment)
        self.assertIn("not approval", res.comment)
        self.assertEqual(res.cls, "entry")

    def test_owner_adds_a_version(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr(add_version_changes())), 0, absent=[NOTICE_FRAGMENT])
        self.assertEqual(res.cls, "entry")

    def test_first_publish_in_an_existing_namespace_has_no_new_namespace_notice(self):
        w = self.world()
        self.check(run_cli(w, w.pr(first_publish_changes("alice", "second"))), 0, absent=[NOTICE_FRAGMENT])

    def test_owner_page_only_pr(self):
        w = self.world()
        page = js({"description": "new text", "screenshots": [], "tags": ["x"], "links": [], "deprecated": False})
        res = self.check(run_cli(w, w.pr({"mods/alice.demo/page.json": page})), 0, "page.json-only: no build runs",
                         "screenshot", absent=[NOTICE_FRAGMENT])
        self.assertEqual(res.cls, "page-only")

    def test_infra_pr_touching_only_readme(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr({"README.md": "changed\n"})), 0, "README.md", "green does not mean safe",
                         "not a registry content PR")
        self.assertEqual(res.verdict["route"], "infra")

    def test_reserved_namespace_first_publish_by_member(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr(reserved_publish()), uid=MEMBER, login="memberbob", status="204"), 0,
                         "organisation", "ADR-0119", absent=[NOTICE_FRAGMENT])
        self.assertEqual(res.cls, "reserved-namespace")

    def test_main_advancing_after_the_pr_was_cut_does_not_look_like_deletions(self):
        w = self.world()
        head = w.pr(add_version_changes())
        w.commit_on_main(first_publish_changes("zed", "other", {**ALICE_OWNER, "id": 5, "name_at_registration": "zed"}))
        self.check(run_cli(w, head, base_sha=w.base), 0)


class AC2aHostileStrings(Base):
    HOSTILE = {"@org/team": "x\n", "tick`file": "x\n", "fence```y": "x\n", "q\n```\n@evil": "x\n"}

    def test_infra_pr_names_stay_inside_the_fence(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr(self.HOSTILE)), 0)
        for token in ("@org/team", "@evil", "tick`file", "fence```y"):
            self.assertIn(token, res.comment)
        outside = outside_fences(res.comment)
        for token in ("@org/team", "@evil", "tick`file", "fence```y"):
            self.assertNotIn(token, outside)

    def test_many_paths_are_capped_with_a_count_of_the_rest(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr({f"docs/f{i:03}.md": "x\n" for i in range(120)})), 0, "70 more")
        self.assertLessEqual(res.comment.count("docs/f"), 50)

    def test_long_names_cap_the_listing_by_bytes(self):
        w = self.world()
        res = self.check(run_cli(w, w.pr({f"d{i}/" + "n" * 200 + ".md": "x\n" for i in range(40)})), 0, "more")
        self.assertLess(len(res.comment), 6000)

    def test_hostile_login_exits_2_and_writes_no_free_text_output(self):
        w = self.world()
        head = w.pr(add_version_changes())
        for login in ("evil\nclass=entry", "a b", "x=y", "-lead", "bot[bot]", "A" * 40):
            res = self.check(run_cli(w, head, login=login), 2)
            self.assertNotIn("evil", res.outputs)

    def test_hostile_namespace_and_path_strings_never_reach_outputs(self):
        w = self.world()
        head = w.pr({"mods/ev\nil=1.x/entry.json": "{}\n", "mods/a.b/entry.json\nclass=entry": "{}\n"})
        res = self.check(run_cli(w, head), 1)
        self.assertEqual(res.cls, "other")
        self.assertNotIn("ev\nil", res.outputs)

    def test_hostile_org_name_in_the_reserved_list_exits_2(self):
        files = base_files()
        res_list = json.loads(files["reserved-namespaces.json"])
        for ns in res_list["namespaces"].values():
            ns["owner"]["name_at_registration"] = "evil\norg=x"
        files["reserved-namespaces.json"] = js(res_list)
        w = self.world(files)
        head = w.pr(reserved_publish())
        self.check(run_cli(w, head, classify_only=True), 2)

    def test_checker_output_is_truncated_below_the_comment_limit(self):
        w = self.world()
        big = {**ALL_OK, "schema": (1, rej("schema"), "REJECTED " + "x" * 200000 + "\n", 0)}
        res = self.check(run_lib(w, w.pr(add_version_changes()), tools_dir=write_stubs(w.ws / "stubs", big)), 1,
                         "truncated")

    def test_checker_output_containing_backticks_cannot_close_the_fence(self):
        w = self.world()
        evil = "REJECTED a\n`````````\n@evil-mention\n"
        stubs = {**ALL_OK, "schema": (1, rej("schema"), evil, 0)}
        res = self.check(run_lib(w, w.pr(add_version_changes()), tools_dir=write_stubs(w.ws / "stubs", stubs)), 1,
                         "@evil-mention")
        self.assertNotIn("@evil-mention", outside_fences(res.comment))


class AC3FailClosed(Base):
    def head(self, w):
        return w.pr(add_version_changes())

    def test_event_and_api_disagree_on_user_id(self):
        w = self.world()
        self.check(run_cli(w, self.head(w), event=lambda e: e["pull_request"]["user"].update(id=1)), 2)

    def test_event_and_api_disagree_on_head_sha(self):
        w = self.world()
        self.check(run_cli(w, self.head(w), event=lambda e: e["pull_request"]["head"].update(sha="f" * 40)), 2)

    def test_event_and_api_disagree_on_number_base_ref_and_repository(self):
        w = self.world()
        h = self.head(w)
        self.check(run_cli(w, h, event=lambda e: e["pull_request"].update(number=8)), 2)
        self.check(run_cli(w, h, pr=lambda p: p["base"].update(ref="dev")), 2)
        self.check(run_cli(w, h, pr=lambda p: p["base"]["repo"].update(full_name="evil/registry")), 2)

    def test_malformed_identity_fields(self):
        w = self.world()
        h = self.head(w)
        for mut in (lambda p: p["user"].update(id="100200300"), lambda p: p["user"].update(id=True),
                    lambda p: p["user"].pop("id"), lambda p: p["head"].update(sha="ABC")):
            self.check(run_cli(w, h, pr=mut, event=lambda e: None), 2)

    def test_pr_json_missing_or_unparsable(self):
        w = self.world()
        h = self.head(w)
        self.check(run_cli(w, h, pr_file="missing"), 2)
        self.check(run_cli(w, h, pr_file="garbage"), 2)

    def test_no_merge_base(self):
        w = self.world()
        orphan = w.git("commit-tree", w.git("rev-parse", "main^{tree}").strip(), "-m", "orphan").strip()
        w.git("update-ref", "refs/heads/orphan", orphan)
        self.check(run_cli(w, orphan), 2)

    def test_two_merge_bases(self):
        w = self.world()
        w.git("checkout", "-q", "-b", "a", "main")
        a1 = w.commit_on_main({"a.txt": "a\n"}, "a1")
        w.git("checkout", "-q", "-b", "b", w.base)
        b1 = w.commit_on_main({"b.txt": "b\n"}, "b1")
        w.git("checkout", "-q", "-b", "m1", a1)
        w.git("merge", "-q", "--no-ff", "-m", "m1", b1)
        m1 = w.git("rev-parse", "HEAD").strip()
        w.git("checkout", "-q", "-b", "m2", b1)
        w.git("merge", "-q", "--no-ff", "-m", "m2", a1)
        m2 = w.git("rev-parse", "HEAD").strip()
        self.assertEqual(len(w.git("merge-base", "--all", m1, m2).split()), 2)
        w.git("checkout", "-q", "-f", "main")
        w.git("reset", "-q", "--hard", m1)
        self.check(run_cli(w, m2, base_sha=w.base), 2)

    def test_api_base_sha_not_an_ancestor_of_base_head(self):
        w = self.world()
        h = self.head(w)
        self.check(run_cli(w, h, base_sha=h), 2)
        self.check(run_cli(w, h, base_sha="e" * 40), 2)

    def test_unparsable_z_path_list(self):
        import ci_gate
        for bad in (b"a", b"a\0b", b"a\0\0", b"\0", b"\0a\0"):
            with self.assertRaises(ci_gate.Undecided, msg=repr(bad)):
                ci_gate.parse_z_paths(bad)
        self.assertEqual(ci_gate.parse_z_paths(b""), [])
        self.assertEqual(ci_gate.parse_z_paths(b"a\0b c\nd\0"), ["a", "b c\nd"])
        with self.assertRaises(ci_gate.Undecided):
            ci_gate.parse_z_paths(b"\xff\xfe\0")

    def test_unparsable_z_list_end_to_end(self):
        from unittest import mock
        import ci_gate
        w = self.world()
        h = self.head(w)
        real = ci_gate._git

        def fake(repo, *args, **kw):
            out = real(repo, *args, **kw)
            return b"mods/a\0\0" if "--name-only" in args else out
        with mock.patch.object(ci_gate, "_git", fake):
            self.check(run_lib(w, h), 2)

    def test_a_checker_exiting_2(self):
        w = self.world()
        stubs = {**ALL_OK, "append-only": (2, "", "ERROR (usage or internal, not a rejection): boom\n", 0)}
        res = self.check(run_lib(w, self.head(w), tools_dir=write_stubs(w.ws / "s", stubs)), 2, "could not decide",
                         "not a rejection", "boom")

    def test_stub_checker_exit_3_and_non_json_and_disagreeing_exit(self):
        w = self.world()
        h = self.head(w)
        for i, bad in enumerate(((3, acc("schema"), "", 0), (0, "this is not json", "", 0), (0, rej("schema"), "", 0),
                                 (1, acc("schema"), "", 0), (0, "[]", "", 0), (0, acc("append-only"), "", 0))):
            stubs = {**ALL_OK, "schema": bad}
            self.check(run_lib(w, h, tools_dir=write_stubs(w.ws / f"s{i}", stubs)), 2)

    def test_a_checker_over_its_timeout(self):
        w = self.world()
        stubs = {**ALL_OK, "ownership": (0, acc("ownership"), "", 20)}
        self.check(run_lib(w, self.head(w), tools_dir=write_stubs(w.ws / "s", stubs), checker_timeout=1), 2,
                   "timed out")

    def test_precedence_exit_2_beats_a_rejection(self):
        w = self.world()
        stubs = {**ALL_OK, "classify": (2, "", "ERROR boom\n", 0), "schema": (1, rej("schema"), "REJECTED x\n", 0)}
        self.check(run_lib(w, self.head(w), tools_dir=write_stubs(w.ws / "s", stubs)), 2)

    def test_all_four_checkers_run_even_after_a_rejection(self):
        w = self.world()
        rec = w.ws / "record"
        stubs = {**ALL_OK, "classify": (1, rej("classify", **{"class": "other"}), "REJECTED c\n", 0)}
        self.check(run_lib(w, self.head(w), tools_dir=write_stubs(w.ws / "s", stubs, rec)), 1)
        self.assertEqual(sorted(rec.read_text().split()), ["append-only", "classify", "ownership", "schema"])

    def test_any_exception_in_main_exits_2(self):
        from unittest import mock
        import ci_gate
        w = self.world()
        e, p, out = payloads(w, self.head(w))
        argv = ["--repo", str(w.repo), "--event", str(e), "--pr", str(p), "--membership-status", "none",
                "--out", str(out)]
        for exc in (RuntimeError("injected"), KeyError("k"), ci_gate.subprocess.TimeoutExpired("git", 1), MemoryError()):
            with mock.patch.object(ci_gate, "run_gate", side_effect=exc):
                self.assertEqual(ci_gate.main(argv), 2, repr(exc))

    def test_an_exception_deep_inside_a_run_exits_2_with_a_verdict(self):
        from unittest import mock
        import ci_gate
        w = self.world()
        e, p, out = payloads(w, self.head(w))
        argv = ["--repo", str(w.repo), "--event", str(e), "--pr", str(p), "--membership-status", "none",
                "--out", str(out)]
        with mock.patch.object(ci_gate, "materialise", side_effect=RuntimeError("injected")):
            self.assertEqual(ci_gate.main(argv), 2)
        self.assertEqual(json.loads((out / "verdict.json").read_text())["result"], "undecided")

    def test_bad_membership_status_argument_exits_2(self):
        w = self.world()
        h = self.head(w)
        for bad in ("2040", "20x", "", "NONE", "-1"):
            res = run_cli(w, h, status=bad)
            self.assertEqual(res.code, 2, bad)
            self.assertIn("membership-status", res.stderr, "exit 2 must come from the composer's own argument check")

    def test_malformed_r11_config(self):
        for i, bad in enumerate(("{not json", "[]", js({"schema_version": "1.0.0"}),
                                 js({"schema_version": "1.0.0", "r11_identity": {"provider": "github", "id": "555"}}),
                                 js({"schema_version": "1.0.0", "r11_identity": {"provider": "gitlab", "id": 555}}),
                                 js({"schema_version": "1.0.0", "r11_identity": {"provider": "github", "id": 555, "x": 1}}),
                                 js({"schema_version": "9", "r11_identity": None}),
                                 '{"schema_version": "1.0.0", "r11_identity": null, "r11_identity": null}',
                                 js({"schema_version": "1.0.0", "r11_identity": 555}))):
            w = self.world({**base_files(), "config/r11-identity.json": bad})
            self.check(run_cli(w, w.pr(add_version_changes())), 2, "r11")

    def test_absent_r11_config_means_unconfigured_not_an_error(self):
        files = base_files()
        del files["config/r11-identity.json"]
        w = self.world(files)
        self.check(run_cli(w, w.pr(add_version_changes())), 0)

    def test_reserved_list_naming_two_organisations(self):
        files = base_files()
        res_list = json.loads(files["reserved-namespaces.json"])
        res_list["namespaces"]["test"]["owner"]["name_at_registration"] = "otherorg"
        files["reserved-namespaces.json"] = js(res_list)
        w = self.world(files)
        h = w.pr(reserved_publish())
        self.check(run_cli(w, h, uid=MEMBER, login="memberbob", status="204"), 2, "organisation")
        self.check(run_cli(w, h, uid=MEMBER, login="memberbob", classify_only=True), 2)

    def test_missing_reserved_list_or_unreadable_inputs(self):
        files = base_files()
        del files["reserved-namespaces.json"]
        w = self.world(files)
        self.check(run_cli(w, w.pr(add_version_changes())), 2)
        self.assertEqual(run_cli(w, w.pr({"README.md": "x\n"}, "p2"), pr_file="missing").code, 2)
        r = subprocess.run([sys.executable, "-I", str(CI_GATE), "--repo", str(w.repo)], capture_output=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn(b"required", r.stderr)

    def test_empty_diff_is_a_rejection_and_no_checker_runs(self):
        w = self.world()
        rec = w.ws / "record"
        head = w.pr({}, name="empty")
        self.assertNotEqual(head, w.base)
        res = self.check(run_lib(w, head, tools_dir=write_stubs(w.ws / "s", ALL_OK, rec)), 1, "unrecognised-pr",
                         "empty")
        self.assertFalse(rec.exists() and rec.read_text().strip(), "a checker ran on an empty diff")
        self.assertEqual(res.verdict["route"], "empty")
        self.check(run_cli(w, head), 1, "unrecognised-pr")

    def test_no_tools_dir_option_on_the_cli(self):
        self.assertNotIn("--tools-dir", CI_GATE.read_text())
        r = subprocess.run([sys.executable, "-I", str(CI_GATE), "--help"], capture_output=True, text=True)
        self.assertIn("usage", r.stdout + r.stderr)
        self.assertNotIn("tools-dir", r.stdout + r.stderr)
        w = self.world()
        e, p, out = payloads(w, self.head(w))
        r = subprocess.run([sys.executable, "-I", str(CI_GATE), "--repo", str(w.repo), "--event", str(e), "--pr", str(p),
                            "--membership-status", "none", "--out", str(out), "--tools-dir", str(w.ws)],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("tools-dir", r.stderr)  # argparse: unrecognized arguments

    def test_cli_always_uses_the_base_checkout_checkers_not_the_prs(self):
        w = self.world()
        evil = "import sys; sys.stdout.write('{\"checker\":\"x\",\"verdict\":\"accepted\",\"findings\":[]}'); sys.exit(0)\n"
        changes = {**add_version_changes(), "tools/registry/cli.py": evil, "tools/registry/ownership_cli.py": evil,
                   "tools/registry/ci_gate.py": evil}
        # mixed with a non-mods path: classify (base version) rejects the mix; the PR's checkers never run
        self.check(run_cli(w, w.pr(changes)), 1, "unrecognised-path")


class AC4IdentitySource(Base):
    def test_actor_env_and_commit_metadata_do_not_make_a_stranger_the_owner(self):
        w = self.world()
        w.env.update(GIT_AUTHOR_NAME="alice", GIT_COMMITTER_NAME="alice", GIT_AUTHOR_EMAIL=f"{ALICE}+alice@users.noreply.github.com",
                     GIT_COMMITTER_EMAIL=f"{ALICE}+alice@users.noreply.github.com")
        head = w.pr(add_version_changes(), message=f"x\n\nSigned-off-by: alice\nCo-authored-by: alice <{ALICE}+alice@users.noreply.github.com>")
        self.assertIn("alice", w.git("log", "-1", "--format=%an %cn", head))
        res = self.check(run_cli(w, head, uid=MALLORY, login="mallory",
                                 env={"GITHUB_ACTOR": "alice", "GITHUB_ACTOR_ID": str(ALICE), "GITHUB_TRIGGERING_ACTOR": "alice"}),
                         1, "R3", str(MALLORY))
        self.assertNotIn(f"github id {ALICE} (login", res.comment)

    def test_the_same_pr_by_the_owner_passes_with_the_same_environment(self):
        w = self.world()
        head = w.pr(add_version_changes())
        self.check(run_cli(w, head, env={"GITHUB_ACTOR": "mallory", "GITHUB_ACTOR_ID": str(MALLORY)}), 0)


class AC5MergeBaseReads(Base):
    TAKEDOWN = {"mods/alice.demo/entry.json": js(alice_entry(removed()))}

    def test_a_pr_removing_a_namespace_from_the_reserved_list_is_still_judged_reserved(self):
        w = self.world()
        res_list = json.loads(base_files()["reserved-namespaces.json"])
        del res_list["namespaces"]["test"]
        changes = reserved_publish({"reserved-namespaces.json": js(res_list)})
        res = self.check(run_cli(w, w.pr(changes), uid=MALLORY, login="test", status="404"), 1, "R7")
        res = self.check(run_cli(w, w.pr(changes, "p2"), uid=MALLORY, login="test", status="none"), 1, "R9")

    def test_takedown_only_pr_with_r11_unconfigured_is_rejected_whoever_opens_it(self):
        w = self.world()
        head = w.pr(self.TAKEDOWN)
        for uid, login in ((ALICE, "alice"), (555, "platform"), (MEMBER, "memberbob")):
            self.check(run_cli(w, head, uid=uid, login=login), 1, "R11", "R11 is not configured")

    def test_takedown_only_pr_by_the_test_only_merge_base_identity_passes(self):
        files = {**base_files(), "config/r11-identity.json": (FIX / "r11-identity.test-only.json").read_text()}
        w = self.world(files)
        res = self.check(run_cli(w, w.pr(self.TAKEDOWN), uid=555, login="platform"), 0, "not approval")
        self.assertEqual(res.verdict["checkers"]["ownership"]["exit"], 0)
        self.assertEqual(res.verdict["merge_signal"], False)
        self.check(run_cli(w, w.pr(self.TAKEDOWN, "p2"), uid=ALICE, login="alice"), 1, "R11")

    def test_takedown_plus_another_change_is_rejected_by_r11_whoever_opens_it(self):
        files = {**base_files(), "config/r11-identity.json": (FIX / "r11-identity.test-only.json").read_text()}
        w = self.world(files)
        mixed = {**self.TAKEDOWN, **first_publish_changes("alice", "second")}
        for uid, login in ((555, "platform"), (ALICE, "alice")):
            self.check(run_cli(w, w.pr(mixed, f"p{uid}"), uid=uid, login=login), 1, "R11")

    def test_a_pr_setting_the_config_to_its_own_author_gains_nothing(self):
        w = self.world()
        changes = {**self.TAKEDOWN, "config/r11-identity.json": (FIX / "r11-identity.test-only.json").read_text()}
        self.check(run_cli(w, w.pr(changes), uid=555, login="platform"), 1, "R11")
        only_config = {"config/r11-identity.json": (FIX / "r11-identity.test-only.json").read_text()}
        # on its own it is an infra PR (human review): green, but the config it set is NOT used by the next PR
        self.check(run_cli(w, w.pr(only_config, "p2"), uid=555, login="platform"), 0, "green does not mean safe")
        self.check(run_cli(w, w.pr(self.TAKEDOWN, "p3"), uid=555, login="platform"), 1, "R11 is not configured")

    def test_membership_statuses(self):
        w = self.world()
        head = w.pr(reserved_publish())
        for status, rule in (("none", "R9"), ("302", "R9"), ("500", "R9"), ("404", "R7")):
            res = self.check(run_cli(w, head, uid=MEMBER, login="memberbob", status=status), 1, rule)
        self.check(run_cli(w, head, uid=MEMBER, login="memberbob", status="204"), 0)
        res = run_cli(w, head, uid=MEMBER, login="memberbob", status="204")
        self.assertNotIn("R7", res.comment)


class AC6TreeHandlingAndArgv(Base):
    def test_rename_of_entry_json_is_rejected_as_a_deletion(self):
        w = self.world()
        body = (w.repo / "mods/alice.demo/entry.json").read_text().replace("alice:demo", "alice:moved")
        head = w.pr({"mods/alice.demo/entry.json": None, "mods/alice.moved/entry.json": body})
        self.check(run_cli(w, head), 1, "deletion")

    def test_symlinked_entry_json_is_rejected_not_followed(self):
        w = self.world()
        head = w.pr({"mods/alice.demo/entry.json": Link("page.json")})
        self.check(run_cli(w, head), 1, "symlink")

    def test_gitlink_under_mods_is_rejected(self):
        w = self.world()
        head = w.pr({"mods/alice.demo/sub": Gitlink()})
        self.check(run_cli(w, head), 1, "mods/alice.demo/sub")
        w.git("checkout", "-q", "-b", "p3", "main")
        w.git("rm", "-q", "-f", "mods/alice.demo/entry.json")
        w.git("update-index", "--add", "--cacheinfo", f"160000,{'2' * 40},mods/alice.demo/entry.json")
        w.git("commit", "-q", "-m", "gitlink at entry.json")
        head3 = w.git("rev-parse", "HEAD").strip()
        w.git("checkout", "-q", "-f", "main")
        self.check(run_cli(w, head3), 1, "mods/alice.demo/entry.json")

    def test_path_with_a_newline_is_handled_via_z(self):
        w = self.world()
        head = w.pr({"mods/alice.demo/entry.json": js(alice_entry(published())), "mods/a.b/x\ny.json": "{}\n"})
        res = self.check(run_cli(w, head), 1)
        self.assertEqual(res.cls, "other")

    # materialisation -------------------------------------------------------------------------------------------------
    def assert_materialise_fails(self, w, entries, fragment, **kw):
        import ci_gate
        head = w.craft(entries)
        dest = w.ws / "dest"
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir()
        with self.assertRaises(ci_gate.Undecided) as cm:
            ci_gate.materialise(w.repo, head, dest, ("mods",), **kw)
        self.assertIn(fragment, str(cm.exception))

    def e2e_exit_2(self, w, entries, fragment):
        head = w.craft(entries)
        sandbox = w.ws / "sandbox"
        shutil.rmtree(sandbox, ignore_errors=True)
        (sandbox / "tmp").mkdir(parents=True)
        (sandbox / "marker.txt").write_text("sentinel\n")
        before = snapshot(sandbox)
        res = run_cli(w, head, env={"TMPDIR": str(sandbox / "tmp")})
        self.check(res, 2)
        self.assertEqual(snapshot(sandbox), before, "the composer wrote outside its temp dir, or left files behind")
        self.assertIn(fragment, res.comment + res.stderr + json.dumps(res.verdict))
        return res

    def test_symlink_x_plus_tree_x(self):
        w = self.world()
        t = w.raw_tree([("100644", "entry.json", w.blob("{}"))])
        entries = [("120000", "x", w.blob("target")), ("40000", "x", t)]
        self.assert_materialise_fails(w, entries, "conflict")
        self.e2e_exit_2(w, entries, "conflict")

    def test_blob_x_plus_tree_x(self):
        w = self.world()
        t = w.raw_tree([("100644", "entry.json", w.blob("{}"))])
        entries = [("100644", "x", w.blob("data")), ("40000", "x", t)]
        self.assert_materialise_fails(w, entries, "conflict")
        self.e2e_exit_2(w, entries, "conflict")

    def test_bad_path_components(self):
        w = self.world()
        t = w.raw_tree([("100644", "entry.json", w.blob("{}"))])
        for comp in (b"..", b".", b"", b".git", b".GIT"):
            entries = [("40000", comp, t)]
            # git itself may refuse such a tree (ls-tree/diff exit 128); either guard is exit 2 (manager, C23)
            self.assert_materialise_fails(w, entries, "")
            self.e2e_exit_2(w, entries, "")

    def test_duplicate_entry(self):
        w = self.world()
        b = w.blob("{}")
        entries = [("100644", "a.json", b), ("100644", "a.json", w.blob("[]"))]
        self.assert_materialise_fails(w, entries, "duplicate")
        self.e2e_exit_2(w, entries, "duplicate")

    def test_symlink_whose_target_escapes_the_root(self):
        w = self.world()
        for target in ("../../../../etc/passwd", "/etc/passwd", "../../..", ""):
            t = w.raw_tree([("120000", "entry.json", w.blob(target))])
            entries = [("40000", "alice.demo", t)]
            self.assert_materialise_fails(w, entries, "escape")
            self.e2e_exit_2(w, entries, "escape")

    def test_symlink_chain_that_escapes_through_another_link(self):
        w = self.world()
        link_dir = w.raw_tree([("120000", "up", w.blob("../.."))])
        t = w.raw_tree([("120000", "entry.json", w.blob("../a.b/up/../../x"))])
        entries = [("40000", "a.b", link_dir), ("40000", "alice.demo", t)]
        self.assert_materialise_fails(w, entries, "escape")

    def test_symlink_with_an_inside_target_is_materialised_never_followed(self):
        import ci_gate
        w = self.world()
        t = w.raw_tree([("120000", "entry.json", w.blob("page.json")), ("100644", "page.json", w.blob("{}"))])
        head = w.craft([("40000", "alice.demo", t)])
        dest = w.ws / "dest"
        dest.mkdir()
        ci_gate.materialise(w.repo, head, dest, ("mods",))
        self.assertTrue((dest / "mods/alice.demo/entry.json").is_symlink())
        self.assertEqual(os.readlink(dest / "mods/alice.demo/entry.json"), "page.json")

    def test_blob_over_the_byte_cap(self):
        import ci_gate
        w = self.world()
        t = w.raw_tree([("100644", "entry.json", w.blob("x" * 100))])
        entries = [("40000", "alice.demo", t)]
        self.assert_materialise_fails(w, entries, "byte cap", max_blob_bytes=99)
        w2 = self.world()
        head = w2.pr(add_version_changes())
        self.check(run_lib(w2, head, max_blob_bytes=10), 2, "byte cap")
        self.check(run_lib(w2, head), 0)

    def test_more_entries_than_the_cap(self):
        w = self.world()
        entries = [("40000", f"a{i}.b", w.raw_tree([("100644", "entry.json", w.blob("{}"))])) for i in range(6)]
        self.assert_materialise_fails(w, entries, "entry cap", max_entries=5)
        w2 = self.world()
        head = w2.pr(add_version_changes())
        sandbox = w2.ws / "sandbox"
        (sandbox / "tmp").mkdir(parents=True)
        before = snapshot(sandbox)
        self.check(run_lib(w2, head, max_entries=3, tmp_parent=sandbox / "tmp"), 2, "entry cap")
        self.assertEqual(snapshot(sandbox), before)

    def test_unsupported_mode_in_the_merge_base_is_not_decidable(self):
        files = base_files()
        w = self.world(files)
        w.git("update-index", "--add", "--cacheinfo", f"160000,{'3' * 40},mods/zz.sub")
        w.git("commit", "-q", "-m", "gitlink on main")
        w.base = w.git("rev-parse", "HEAD").strip()
        head = w.pr(add_version_changes())
        self.check(run_cli(w, head), 2)

    # argv injection --------------------------------------------------------------------------------------------------
    FLAG_FILES = ("--membership-status=204", "--root=x", "--paths-file=README.md", "-h")

    def test_flag_named_files_are_unrecognised_paths_never_checker_options(self):
        w = self.world()
        for i, name in enumerate(self.FLAG_FILES):
            head = w.pr(reserved_publish({name: "x\n"}), f"p{i}")
            for status in ("none", "302"):
                res = self.check(run_cli(w, head, uid=MEMBER, login="memberbob", status=status), 1, "R9", name)
                self.assertEqual(res.cls, "other", name)
                self.assertNotIn("usage:", res.comment)

    def test_flag_named_file_alone_takes_the_infra_route_and_runs_no_checker(self):
        w = self.world()
        rec = w.ws / "record"
        stubs = write_stubs(w.ws / "s", ALL_OK, rec)
        for i, name in enumerate(self.FLAG_FILES):
            res = self.check(run_lib(w, w.pr({name: "x\n"}, f"p{i}"), tools_dir=stubs), 0, name,
                             "green does not mean safe")
            self.assertEqual(res.verdict["route"], "infra")
        self.assertFalse(rec.exists() and rec.read_text().strip(), "a checker ran on an infra PR")

    def test_checkers_receive_paths_only_after_double_dash(self):
        w = self.world()
        argvs = w.ws / "argvs"
        d = write_stubs(w.ws / "s", ALL_OK)
        for f in ("cli.py", "ownership_cli.py"):
            src = (d / f).read_text()
            (d / f).write_text(src.replace("import json, sys, time\n", "import json, sys, time\nopen(%r, 'a').write(json.dumps(sys.argv[1:]) + '\\n')\n" % str(argvs)))
        head = w.pr(add_version_changes())
        self.check(run_lib(w, head, tools_dir=d, status="204"), 0)
        lines = [json.loads(l) for l in argvs.read_text().splitlines()]
        self.assertEqual(len(lines), 4)
        for argv in lines:
            self.assertIn("--", argv)
            self.assertEqual(argv[argv.index("--") + 1:], ["mods/alice.demo/entry.json"])
            self.assertNotIn("--paths-file", argv)
        own = [a for a in lines if "--author-id" in a][0]
        self.assertEqual(own[own.index("--author-id") + 1], str(ALICE))
        self.assertEqual(own[own.index("--membership-status") + 1], "204")
        self.assertNotIn("--r11-identity", own)


class ClassifyOnlyPrePass(Base):
    def test_emits_class_org_and_login_only_for_reserved_namespace(self):
        w = self.world()
        res = run_cli(w, w.pr(reserved_publish()), uid=MEMBER, login="memberbob", classify_only=True)
        self.assertEqual(res.code, 0)
        self.assertEqual(sorted(res.outputs.split()), ["class=reserved-namespace", "login=memberbob", "org=worldofmodcraft"])
        res = run_cli(w, w.pr(add_version_changes(), "p2"), classify_only=True)
        self.assertEqual((res.code, res.outputs.split()), (0, ["class=entry"]))
        res = run_cli(w, w.pr({"README.md": "x\n"}, "p3"), classify_only=True)
        self.assertEqual((res.code, res.outputs.split()), (0, ["class=other"]))
        res = run_cli(w, w.pr({}, "p4"), classify_only=True)
        self.assertEqual((res.code, res.outputs.split()), (0, ["class=other"]))

    def test_pre_pass_does_not_run_the_other_checkers(self):
        w = self.world()
        rec = w.ws / "record"
        stubs = write_stubs(w.ws / "s", ALL_OK, rec)
        res = run_lib(w, w.pr(add_version_changes()), tools_dir=stubs, status=None, classify_only=True)
        self.assertEqual(res.code, 0)
        self.assertEqual(rec.read_text().split(), ["classify"])

    def test_pre_pass_fails_closed_like_the_gate(self):
        w = self.world()
        h = w.pr(add_version_changes())
        res = run_cli(w, h, classify_only=True, event=lambda e: e["pull_request"]["user"].update(id=1))
        self.check(res, 2)

    def test_pre_pass_rejects_membership_argument(self):
        w = self.world()
        e, p, out = payloads(w, w.pr(add_version_changes()))
        r = subprocess.run([sys.executable, "-I", str(CI_GATE), "--classify-only", "--repo", str(w.repo), "--event",
                            str(e), "--pr", str(p), "--out", str(out), "--membership-status", "204"], capture_output=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("membership-status", r.stderr.decode())


# AC8 ---------------------------------------------------------------------------------------------------------------

BANNED_MODULES = {"socket", "urllib", "http", "ssl", "requests", "ftplib", "smtplib", "telnetlib", "xmlrpc", "asyncio"}
BANNED_CALLS = {"eval", "exec", "__import__"}
SUBPROCESS_FUNCS = {"run", "Popen", "call", "check_call", "check_output", "getoutput", "getstatusoutput"}


def scan(src):
    """Violations of AC8 in the source text of the composer."""
    bad, tree = [], ast.parse(src)

    def dotted(n):
        return f"{dotted(n.value)}.{n.attr}" if isinstance(n, ast.Attribute) else (n.id if isinstance(n, ast.Name) else "?")
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            bad += [f"import {a.name}" for a in n.names if a.name.split(".")[0] in BANNED_MODULES]
        elif isinstance(n, ast.ImportFrom):
            root = (n.module or "").split(".")[0]
            if root in BANNED_MODULES:
                bad.append(f"from {n.module} import ...")
            if root == "os":
                bad += [f"from os import {a.name}" for a in n.names if a.name in ("environ", "getenv", "system", "popen", "putenv")]
            if root == "subprocess":
                bad.append("from subprocess import ... (use subprocess.run so argv[0] can be checked)")
        elif isinstance(n, ast.Attribute):
            d = dotted(n)
            if d in ("os.environ", "os.getenv", "os.putenv", "os.system", "os.popen", "os.environb", "os.execv", "os.execve"):
                bad.append(d)
        elif isinstance(n, ast.Call):
            if isinstance(n.func, ast.Name) and n.func.id in BANNED_CALLS:
                bad.append(f"{n.func.id}()")
            for kw in n.keywords:
                if kw.arg == "shell" and not (isinstance(kw.value, ast.Constant) and kw.value.value is False):
                    bad.append("shell=" + ast.unparse(kw.value))
            f = dotted(n.func)
            if f.startswith("subprocess.") and f.split(".")[1] in SUBPROCESS_FUNCS:
                a0 = n.args[0] if n.args else None
                ok = False
                if isinstance(a0, ast.List) and a0.elts:
                    e0 = a0.elts[0]
                    ok = (isinstance(e0, ast.Constant) and e0.value == "git") or ast.unparse(e0) == "sys.executable"
                if not ok:
                    bad.append(f"subprocess argv[0] not literal 'git' or sys.executable: {ast.unparse(n)[:60]}")
    if "--tools-dir" in src or "tools-dir" in src:
        bad.append("--tools-dir option")
    return bad


class AC8NoNetworkNoEnvNoShell(unittest.TestCase):
    def setUp(self):
        self.src = CI_GATE.read_text()

    def test_the_composer_is_clean(self):
        self.assertEqual(scan(self.src), [])

    def test_the_scan_finds_the_subprocess_calls_it_is_judging(self):
        calls = [n for n in ast.walk(ast.parse(self.src)) if isinstance(n, ast.Call) and ast.unparse(n.func).startswith("subprocess.")]
        self.assertGreaterEqual(len(calls), 2, "fails on zero matches: the scan must see the git and python calls")

    def test_mutations_are_each_red(self):
        for label, mut in (("urllib", "\nimport urllib.request\n"), ("environ", '\nos.environ["X"]\n'),
                           ("shell", '\nsubprocess.run(["git"], shell=True)\n'), ("getenv", "\nos.getenv('X')\n"),
                           ("socket", "\nfrom socket import socket\n"), ("eval", "\neval('1')\n"),
                           ("system", "\nos.system('x')\n"), ("variable argv0", "\nsubprocess.run([cmd, 'x'])\n"),
                           ("string argv", "\nsubprocess.run('git status')\n"), ("tools-dir", "\n# --tools-dir\n"),
                           ("http", "\nimport http.client\n"), ("exec", "\nexec('1')\n")):
            self.assertNotEqual(scan(self.src + mut), [], f"mutation {label} stayed green")

    def test_only_stdlib_is_imported(self):
        mods = set()
        for n in ast.walk(ast.parse(self.src)):
            if isinstance(n, ast.Import):
                mods |= {a.name.split(".")[0] for a in n.names}
            elif isinstance(n, ast.ImportFrom) and n.level == 0:
                mods.add((n.module or "").split(".")[0])
        self.assertLessEqual(mods, set(sys.stdlib_module_names), mods - set(sys.stdlib_module_names))


class AC9ProductionR11Unconfigured(unittest.TestCase):
    def test_committed_config_names_nobody(self):
        doc = json.loads((REPO / "config" / "r11-identity.json").read_text())
        self.assertEqual(doc, {"schema_version": "1.0.0", "r11_identity": None})


if __name__ == "__main__":
    unittest.main()
