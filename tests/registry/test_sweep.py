"""Tests for tools/dev/sweep.py (task 111a). Standard library only; stub repositories in temp directories.

Run:  python3 -I -B -m unittest discover -s tests/registry -p 'test_sweep.py'
No real closed verify script is run: every sweep below uses stub scripts and --only / --no-wait.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
REPO = Path(__file__).resolve().parents[2]
SWEEP_SRC = REPO / "tools" / "dev" / "sweep.py"
sys.path.insert(0, str(REPO / "tools" / "dev"))
import sweep  # noqa: E402

GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@example.invalid", "-c", "commit.gpgsign=false"]

GREEN = "#!/usr/bin/env bash\nexit 0\n"
RED = "#!/usr/bin/env bash\necho boom\nexit 3\n"
RUNNER = '#!/usr/bin/env bash\nbash "$(dirname "$0")/a-verify.sh"\nbash "$(dirname "$0")/a-verify.sh"\nexit 0\n'


class Stub:
    """A throwaway git repository holding a copy of sweep.py and the given verify scripts."""

    def __init__(self, test, scripts, gitignore=True):
        self.dir = Path(tempfile.mkdtemp(prefix="sweep-test."))
        test.addCleanup(shutil.rmtree, self.dir, True)
        self.repo = self.dir / "repo"
        (self.repo / "tools" / "dev").mkdir(parents=True)
        (self.repo / "docs" / "tasks").mkdir(parents=True)
        shutil.copy(SWEEP_SRC, self.repo / "tools" / "dev" / "sweep.py")
        for name, text in scripts.items():
            (self.repo / "docs" / "tasks" / name).write_text(text)
        if gitignore:
            (self.repo / ".gitignore").write_text("node_modules/\n")
        self.nm = self.dir / "nm"
        (self.nm / "ajv").mkdir(parents=True)
        (self.nm / "ajv" / "package.json").write_text("{}\n")
        self.out = self.dir / "report.json"
        self.markers = self.dir / "markers"
        self.markers.mkdir()
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        subprocess.run(GIT + ["-C", str(self.repo), "add", "-A"], check=True)
        subprocess.run(GIT + ["-C", str(self.repo), "commit", "-q", "-m", "stub"], check=True)

    def run(self, *args, nm=None, out=None, use_defaults=True):
        cmd = [sys.executable, "-I", "-B", str(self.repo / "tools" / "dev" / "sweep.py")]
        if use_defaults:
            cmd += ["--nm", str(nm or self.nm), "--out", str(out or self.out), "--no-wait"]
        env = dict(os.environ, WOM_STUB_OUT=str(self.markers), WOM_NODE_MODULES="/nonexistent/leak", NODE_MODULES_DIR="/nonexistent/leak2")
        return subprocess.run(cmd + list(args), capture_output=True, text=True, env=env, cwd=str(self.dir))

    def report(self):
        return json.loads(self.out.read_text())

    def status(self):
        return subprocess.run(["git", "-C", str(self.repo), "status", "--porcelain"], capture_output=True, text=True).stdout


def by_name(report):
    return {s["name"]: s for s in report["scripts"]}


class MixedSweep(unittest.TestCase):
    def setUp(self):
        self.s = Stub(self, {"a-verify.sh": GREEN, "b-verify.sh": RED, "c-verify.sh": RUNNER})

    def test_exit_seconds_and_nested(self):
        p = self.s.run()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        r = self.s.report()
        d = by_name(r)
        self.assertEqual([x["name"] for x in r["scripts"]], ["a-verify.sh", "b-verify.sh", "c-verify.sh"])
        self.assertEqual(d["a-verify.sh"]["exit"], 0)
        self.assertEqual(d["b-verify.sh"]["exit"], 3)
        self.assertEqual(d["c-verify.sh"]["exit"], 0)
        for x in r["scripts"]:
            self.assertGreater(x["seconds"], 0, x)
        self.assertEqual(d["a-verify.sh"]["nested_starts"], {})
        self.assertEqual(d["b-verify.sh"]["nested_starts"], {})
        self.assertEqual(d["c-verify.sh"]["nested_starts"], {"a-verify.sh": 2})
        self.assertIn("boom", "\n".join(d["b-verify.sh"]["output_tail"]))
        self.assertEqual(r["totals"]["nested_starts"], {"a-verify.sh": 2})
        self.assertEqual(r["totals"]["nested_starts_total"], 2)
        self.assertEqual(r["nested_visibility"], "BASH_ENV; children of a cleared environment are not counted")
        self.assertEqual(len(r["head"]), 40)
        self.assertTrue(r["started"] and r["finished"])

    def test_red_script_does_not_stop_the_sweep(self):
        self.s.run()
        self.assertEqual(len(self.s.report()["scripts"]), 3)

    def test_source_checkout_unchanged_and_no_pycache(self):
        self.s.run()
        self.assertEqual(self.s.status(), "")
        found = [p for p in self.s.repo.rglob("__pycache__")]
        self.assertEqual(found, [])

    def test_only_selects(self):
        p = self.s.run("--only", "a-verify.sh")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual([x["name"] for x in self.s.report()["scripts"]], ["a-verify.sh"])


class AllGreen(unittest.TestCase):
    def test_positive_control_exit_zero(self):
        s = Stub(self, {"a-verify.sh": GREEN, "c-verify.sh": RUNNER})
        p = s.run()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(by_name(s.report())["c-verify.sh"]["nested_starts"], {"a-verify.sh": 2})


class SpecialScripts(unittest.TestCase):
    def setUp(self):
        marker = '#!/usr/bin/env bash\necho "$@" > "$WOM_STUB_OUT/%s.args"\nexit 0\n'
        self.s = Stub(self, {"039a-verify.sh": marker % "039a", "039b-verify.sh": marker % "039b", "z-verify.sh": GREEN})

    def test_039a_skipped_with_reason_and_039b_gets_no_closed(self):
        p = self.s.run()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        r = self.s.report()
        self.assertEqual(r["skipped"], [{"name": "039a-verify.sh", "reason": "it is the sweep"}])
        self.assertNotIn("039a-verify.sh", by_name(r))
        self.assertFalse((self.s.markers / "039a.args").exists())
        self.assertEqual((self.s.markers / "039b.args").read_text().strip(), "--no-closed")

    def test_only_the_skipped_script_is_an_empty_list(self):
        p = self.s.run("--only", "039a-verify.sh")
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)


class ClearedEnvironment(unittest.TestCase):
    def test_child_of_cleared_environment_is_not_counted(self):
        text = '#!/usr/bin/env bash\nenv -i PATH="$PATH" bash "$(dirname "$0")/a-verify.sh"\nexit 0\n'
        s = Stub(self, {"a-verify.sh": GREEN, "d-verify.sh": text})
        p = s.run("--only", "d-verify.sh")
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        r = s.report()
        self.assertEqual(by_name(r)["d-verify.sh"]["nested_starts"], {})
        self.assertIn("cleared environment", r["nested_visibility"])


class FailureModes(unittest.TestCase):
    def test_empty_script_list_exits_2(self):
        s = Stub(self, {"README.md": "x\n"})
        p = s.run()
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertFalse(s.out.exists())

    def test_missing_ajv_exits_2(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        empty = s.dir / "empty-nm"
        empty.mkdir()
        p = s.run(nm=empty)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("ajv", p.stderr)

    def test_out_inside_repository_exits_2(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        p = s.run(out=s.repo / "report.json")
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertFalse((s.repo / "report.json").exists())

    def test_unknown_only_name_exits_2(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        p = s.run("--only", "nope-verify.sh")
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_missing_required_arguments_exit_2(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        p = s.run(use_defaults=False)
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)

    def test_relative_nm_exits_2(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        p = s.run(nm="relative/nm")
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)


class ListReal(unittest.TestCase):
    def test_list_matches_glob(self):
        p = subprocess.run([sys.executable, "-I", "-B", str(SWEEP_SRC), "--list"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        want = sorted(x.name for x in (REPO / "docs" / "tasks").glob("*-verify.sh"))
        self.assertGreater(len(want), 0)
        lines = p.stdout.splitlines()
        listed = [ln.split()[0] for ln in lines[:-1]]
        self.assertEqual(listed, want)
        self.assertEqual(lines[-1], "%d scripts, 1 skipped" % len(want))
        self.assertIn("039a-verify.sh  [skipped: it is the sweep]", lines)
        self.assertIn("039b-verify.sh  args: --no-closed", lines)


ENVPROBE = (
    '#!/usr/bin/env bash\n'
    'echo "${WOM_NODE_MODULES-UNSET}/${NODE_MODULES_DIR-UNSET}" > "$WOM_STUB_OUT/env"\n'
    'if [ -d tools/dev/node_modules ] && [ ! -L tools/dev/node_modules ] && [ -d tools/dev/node_modules/ajv ]; then echo real > "$WOM_STUB_OUT/nm"; else echo bad > "$WOM_STUB_OUT/nm"; fi\n'
    'exit 0\n'
)


class GateEnvironment(unittest.TestCase):
    """Finding 3/4: scripts get 039a's environment: node_modules copied (cp -a), WOM_NODE_MODULES and NODE_MODULES_DIR unset."""

    def test_env_unset_and_node_modules_is_a_real_directory(self):
        s = Stub(self, {"e-verify.sh": ENVPROBE})
        p = s.run()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual((s.markers / "env").read_text().strip(), "UNSET/UNSET")
        self.assertEqual((s.markers / "nm").read_text().strip(), "real")

    def test_untracked_files_in_the_clone_before_the_first_script_exit_2(self):
        s = Stub(self, {"a-verify.sh": GREEN}, gitignore=False)
        p = s.run()
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("porcelain", p.stderr)
        self.assertFalse((s.markers / "ran").exists())


class ReportCompleteness(unittest.TestCase):
    """Findings 1/2: the report says whether it is complete and whether the quiet-wait was on."""

    def test_complete_report(self):
        s = Stub(self, {"a-verify.sh": GREEN, "c-verify.sh": RUNNER})
        s.run()
        r = s.report()
        self.assertEqual(r["planned"], ["a-verify.sh", "c-verify.sh"])
        self.assertIs(r["complete"], True)
        self.assertTrue(r["finished"])
        self.assertIs(r["quiet_wait"], False)
        for x in r["scripts"]:
            self.assertEqual(x["waited_seconds"], 0)

    def test_partial_report_is_marked_incomplete(self):
        # the second script kills the driver (its parent) mid-sweep: the report written after script 1 must say incomplete
        killer = '#!/usr/bin/env bash\nkill -9 $PPID\nexit 0\n'
        s = Stub(self, {"a-verify.sh": GREEN, "b-verify.sh": killer, "c-verify.sh": GREEN})
        s.run()
        r = s.report()
        self.assertEqual(r["planned"], ["a-verify.sh", "b-verify.sh", "c-verify.sh"])
        self.assertIs(r["complete"], False)
        self.assertIsNone(r["finished"])
        self.assertEqual([x["name"] for x in r["scripts"]], ["a-verify.sh"])


class WaitLoop(unittest.TestCase):
    """Finding 5: the wait loop, its timeout and the no_wait guard, with injected others() and sleep."""

    def test_waits_until_quiet(self):
        seq = [["1 busy"], ["1 busy"], []]
        slept = []
        ok, waited = sweep.wait_quiet("x", others_fn=lambda: seq.pop(0), sleep=slept.append)
        self.assertTrue(ok)
        self.assertEqual(waited, 2 * sweep.QUIET_POLL_S)
        self.assertEqual(slept, [sweep.QUIET_POLL_S] * 2)

    def test_timeout_returns_false(self):
        slept = []
        ok, waited = sweep.wait_quiet("x", others_fn=lambda: ["1 busy"], sleep=slept.append)
        self.assertFalse(ok)
        self.assertGreaterEqual(waited, sweep.QUIET_LIMIT_S)

    def test_timeout_records_error_and_null_exit(self):
        d = Path(tempfile.mkdtemp(prefix="sweep-w."))
        self.addCleanup(shutil.rmtree, d, True)
        rec = sweep.run_script(d, "x-verify.sh", d, d, False, waiter=lambda label: (False, 99))
        self.assertIsNone(rec["exit"])
        self.assertIn("six hours", rec["error"])
        self.assertEqual(rec["waited_seconds"], 99)

    def test_no_wait_never_calls_the_waiter(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        calls = []
        rec = sweep.run_script(s.repo, "a-verify.sh", s.nm, s.dir, True, waiter=lambda label: calls.append(label) or (True, 0))
        self.assertEqual(calls, [])
        self.assertEqual(rec["exit"], 0)

    def test_wait_is_used_when_not_no_wait(self):
        s = Stub(self, {"a-verify.sh": GREEN})
        calls = []
        rec = sweep.run_script(s.repo, "a-verify.sh", s.nm, s.dir, False, waiter=lambda label: calls.append(label) or (True, 7))
        self.assertEqual(calls, ["a-verify.sh"])
        self.assertEqual(rec["waited_seconds"], 7)


class QuietWait(unittest.TestCase):
    PS = "\n".join([
        "1 0 /sbin/init",
        "100 1 bash docs/tasks/039a-verify.sh",       # ancestor: excluded
        "200 100 python3 tools/dev/sweep.py",         # me
        "300 200 bash docs/tasks/062-verify.sh",      # descendant: excluded
        "301 300 bash docs/tasks/057-verify.sh",      # grandchild: excluded
        "400 1 bash docs/tasks/089e-verify.sh",       # unrelated: counts
        "401 400 bash docs/tasks/062-verify.sh",      # child of unrelated: counts
        "500 1 grep nothing",                         # not a verify script
    ])

    def test_tree_exclusion(self):
        got = sweep.others_from(self.PS, 200)
        self.assertEqual([x.split()[0] for x in got], ["400", "401"])

    def test_nothing_else_running(self):
        self.assertEqual(sweep.others_from("1 0 init\n200 1 python3 sweep.py", 200), [])

    def test_missing_own_pid_is_an_error(self):
        with self.assertRaises(sweep.EnvError):
            sweep.others_from("1 0 init", 200)

    def test_garbled_table_is_an_error(self):
        with self.assertRaises(sweep.EnvError):
            sweep.others_from("garbage line", 200)


if __name__ == "__main__":
    unittest.main()
