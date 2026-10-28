"""Task 008b-1: the pipeline planner (tools/pipeline/plan_pending.py). Offline: registry states are
throw-away directories built in a temp dir (prefix wom008b1-), branches and archive logs are injected lists.

Expected values are typed here as literals (the contracts' worked examples, the exact 092 reason text), never
derived from the function under test. Criterion numbers are the umbrella's (see docs/tasks/008b1-pipeline-plan.md)."""

import ast
import copy
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

from helpers import REPO, TOOLS  # noqa: F401  (helpers puts tools/pipeline on sys.path)

import naming  # noqa: E402
import plan_pending as pp  # noqa: E402
import write_back as wb  # noqa: E402

PLANNER = os.path.join(TOOLS, "plan_pending.py")
HEAD = "0123456789abcdef0123456789abcdef01234567"
COMMIT = "a" * 40
SRC = "https://example.invalid/mod.git"
# 092's text, typed literally (em dash included): contracts/artifact-naming.md, producer obligation 3.
PLUS_REASON = "versions with build metadata (+) are not yet published — pending proof that GitHub resolves them (task 010)"
OWNER = {"provider": "github", "id": 1, "name_at_registration": "someone"}
PUBLISHED_EXTRA = {"source_archive": "https://archive.worldofmodcraft.com/a/a.tar.gz", "source_sha256": "0" * 64,
                   "signature": "sig", "key_id": "E7A1B2C3D4E5F607", "published_at": "2026-10-28T10:00:00Z"}


def pending(v):
    return {"version": v, "commit": COMMIT, "source_url": SRC, "status": "pending"}


def published(v):
    return {"version": v, "commit": COMMIT, "source_url": SRC, "status": "published", **PUBLISHED_EXTRA}


def removed(v):
    return {**published(v), "status": "removed", "reason": "legal"}


def rejected(v):
    return {"version": v, "commit": COMMIT, "source_url": SRC, "status": "rejected", "reason": "r",
            "build_log_url": "https://github.com/worldofmodcraft/archive/blob/main/logs/x.log"}


def entry(ns, name, versions):
    return {"id": f"{ns}:{name}", "owner": dict(OWNER), "versions": versions}


class Registry:
    """A throw-away registry checkout: mods/<dir>/entry.json files."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="wom008b1-")

    def add(self, doc, dirname=None, raw=None):
        ns, name = doc["id"].split(":") if isinstance(doc, dict) and "id" in doc else ("x", "y")
        d = os.path.join(self.root, "mods", dirname or f"{ns}.{name}")
        os.makedirs(d)
        with open(os.path.join(d, "entry.json"), "w", encoding="utf-8") as f:
            f.write(raw if raw is not None else json.dumps(doc))
        return self

    def close(self):
        shutil.rmtree(self.root)


class Base(unittest.TestCase):
    def setUp(self):
        self.reg = Registry()
        self.addCleanup(self.reg.close)

    def plan(self, branches=(), logs=(), **kw):
        return pp.plan(self.reg.root, HEAD, list(branches), list(logs), **kw)

    def cli(self, *extra, branches=(), logs=(), registry=None):
        d = tempfile.mkdtemp(prefix="wom008b1-cli-")
        self.addCleanup(shutil.rmtree, d)
        bf, lf = os.path.join(d, "branches"), os.path.join(d, "logs")
        open(bf, "w").write("\n".join(branches) + "\n")
        open(lf, "w").write("\n".join(logs) + "\n")
        args = ["--registry", registry or self.reg.root, "--head-sha", HEAD, "--branches", bf, "--archive-logs", lf, *extra]
        r = subprocess.run([sys.executable, "-I", PLANNER, *args], capture_output=True, text=True)
        return r

    def ids(self, doc, kind):
        return [e["version_id"] for e in doc[kind]]


class C3Naming(unittest.TestCase):
    """Criterion 3: tag, assets and URLs against 092's worked examples (typed literally)."""

    def test_c3_example1_tag_assets_urls(self):
        self.assertEqual(naming.release_tag("mc", "hello-world", "1.0.0"), "mc.hello-world-1.0.0")
        self.assertEqual(naming.asset_names("mc", "hello-world", "1.0.0"),
                         ("mc.hello-world-1.0.0.tar.gz", "mc.hello-world-1.0.0.tar.gz.minisig"))
        self.assertEqual(wb.source_archive_url("mc", "hello-world", "1.0.0"),
                         "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz")
        self.assertEqual(naming.release_asset_url("worldofmodcraft", "archive", "mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz"),
                         "https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz")

    def test_c3_example2_derivation_only_never_published(self):
        # DERIVATION ONLY, NEVER PUBLISHED: a `+` version is refused by design 2 and 7 (Q10); no run uploads it.
        self.assertEqual(naming.release_tag("a", "b", "1.0.0-rc.1+build.5"), "a.b-1.0.0-rc.1+build.5")
        self.assertEqual(wb.source_archive_url("a", "b", "1.0.0-rc.1+build.5"),
                         "https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz")
        self.assertEqual(naming.release_asset_url("worldofmodcraft", "archive", "a.b-1.0.0-rc.1+build.5", "a.b-1.0.0-rc.1+build.5.tar.gz"),
                         "https://github.com/worldofmodcraft/archive/releases/download/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz")


class C12NoOp(Base):
    def test_c12_zero_pending_is_an_empty_plan_exit_0(self):
        self.reg.add(entry("mc", "a", [published("1.0.0"), removed("1.1.0"), rejected("1.2.0")]))
        doc = self.plan()
        self.assertEqual(doc, {"head_sha": HEAD, "build": [], "refuse": [], "skip": [], "fault": []})
        r = self.cli()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout), {"head_sha": HEAD, "build": [], "refuse": [], "skip": [], "fault": []})

    def test_c12_empty_registry_without_mods_dir_is_an_empty_plan(self):
        self.assertEqual(self.plan()["build"], [])
        self.assertEqual(self.cli().returncode, 0)

    def test_c12_published_removed_rejected_appear_nowhere(self):
        self.reg.add(entry("mc", "a", [published("1.0.0"), removed("1.1.0"), rejected("1.2.0"), pending("2.0.0")]))
        doc = self.plan()
        blob = json.dumps(doc)
        self.assertEqual(self.ids(doc, "build"), ["mc.a@2.0.0"])
        for v in ("1.0.0", "1.1.0", "1.2.0"):
            self.assertNotIn(f"@{v}", blob)


class C17Selection(Base):
    def test_c17_no_input_builds_every_pending_version(self):
        self.reg.add(entry("mc", "a", [published("1.0.0"), pending("1.1.0"), pending("1.2.0")]))
        self.reg.add(entry("zz", "b", [pending("0.1.0")]))
        doc = self.plan()
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.1.0", "mc.a@1.2.0", "zz.b@0.1.0"])
        self.assertEqual(doc["build"][0], {"version_id": "mc.a@1.1.0", "entry_path": "mods/mc.a/entry.json", "kind": "build", "reason": ""})

    def test_c17_empty_version_dispatch_is_like_a_push(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0"), pending("1.2.0")]))
        self.assertEqual(self.ids(self.plan(dry_run="false", version=""), "build"), ["mc.a@1.1.0", "mc.a@1.2.0"])

    def test_c17_version_input_builds_only_that_version(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0"), pending("1.2.0")]))
        self.reg.add(entry("zz", "b", [pending("0.1.0")]))
        doc = self.plan(version="mc.a@1.2.0")
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.2.0"])
        self.assertEqual(doc["skip"] + doc["refuse"] + doc["fault"], [])

    def test_c17_version_input_ignores_faults_in_other_entries(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0")]))
        self.reg.add(None, dirname="bad.one", raw="{not json")
        doc = self.plan(version="mc.a@1.1.0")
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.1.0"])
        self.assertEqual(doc["fault"], [])

    def test_c17_version_input_refused_exit_1_for_published_removed_rejected(self):
        self.reg.add(entry("mc", "a", [published("1.0.0"), removed("1.1.0"), rejected("1.2.0"), pending("2.0.0")]))
        for v in ("1.0.0", "1.1.0", "1.2.0", "3.0.0"):
            with self.assertRaises(pp.PlanInputError, msg=v):
                self.plan(version=f"mc.a@{v}")
            r = self.cli("--version", f"mc.a@{v}")
            self.assertEqual(r.returncode, 1, v)
            self.assertEqual(r.stdout, "", "no document is written on exit 1")

    def test_c17_version_input_absent_entry_exit_1(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0")]))
        with self.assertRaises(pp.PlanInputError):
            self.plan(version="mc.nope@1.1.0")
        self.assertEqual(self.cli("--version", "mc.nope@1.1.0").returncode, 1)

    def test_c17_malformed_version_ids_exit_1(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0")]))
        for bad in ("mc.a", "mc:a@1.1.0", "mc.a@1.1", "mc.a@01.1.0", "MC.a@1.1.0", "mc.a@1.1.0\n", "mc.a@1.1.0;rm",
                    ".a@1.1.0", "mc.@1.1.0", "mc.a.b@1.1.0", "mc.a@١.1.0", "@", "mc.a@1.1.0 ", "../x.y@1.0.0"):
            with self.assertRaises(pp.PlanInputError, msg=repr(bad)):
                self.plan(version=bad)
            self.assertEqual(self.cli("--version", bad).returncode, 1, repr(bad))

    def test_c17_version_input_with_invalid_entry_is_a_fault_naming_the_version(self):
        self.reg.add(None, dirname="mc.a", raw=json.dumps({"id": "mc:a"}))
        doc = self.plan(version="mc.a@1.0.0")
        self.assertEqual(self.ids(doc, "fault"), ["mc.a@1.0.0"])
        self.assertEqual(doc["build"], [])


class C17aSkip(Base):
    def test_c17a_existing_branch_is_skipped_not_built(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0"), pending("1.2.0")]))
        doc = self.plan(branches=["main", "pipeline/mc.a-1.1.0", "pipeline/other-9.9.9"])
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.2.0"])
        self.assertEqual(doc["skip"], [{"version_id": "mc.a@1.1.0", "entry_path": "mods/mc.a/entry.json",
                                        "kind": "skip", "reason": "pipeline/mc.a-1.1.0"}])
        r = self.cli(branches=["pipeline/mc.a-1.1.0"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["skip"][0]["version_id"], "mc.a@1.1.0")

    def test_c17a_summarize_over_a_skip_plan_is_non_green_naming_the_version(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0")]))
        doc = self.plan(branches=["pipeline/mc.a-1.1.0"])
        green, msg = pp.summarize_outcomes(doc, [])
        self.assertFalse(green)
        self.assertIn("mc.a@1.1.0", msg)

    def test_c17a_a_similar_branch_name_does_not_skip(self):
        self.reg.add(entry("mc", "a", [pending("1.1.0")]))
        doc = self.plan(branches=["pipeline/mc.a-1.1.00", "pipeline/mc.a-1.1.", "xpipeline/mc.a-1.1.0", "pipeline/mc.a-1.1.0/x"])
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.1.0"])

    def test_c17a_skip_applies_before_refuse(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0+b.1")]))
        doc = self.plan(branches=["pipeline/mc.a-1.0.0+b.1"])
        self.assertEqual(self.ids(doc, "skip"), ["mc.a@1.0.0+b.1"])
        self.assertEqual(doc["refuse"], [])


class C17bSchemaFault(Base):
    def test_c17b_invalid_entry_is_a_fault_naming_the_file_and_builds_nothing(self):
        bad = entry("mc", "a", [pending("1.1.0"), pending("1.2.0")])
        bad["versions"][0]["commit"] = "xyz"
        self.reg.add(bad)
        self.reg.add(entry("zz", "b", [pending("0.1.0")]))
        doc = self.plan()
        self.assertEqual(self.ids(doc, "build"), ["zz.b@0.1.0"], "the other entry continues; none of the bad entry's versions builds")
        self.assertEqual(len(doc["fault"]), 1)
        f = doc["fault"][0]
        self.assertEqual((f["version_id"], f["entry_path"], f["kind"]), (None, "mods/mc.a/entry.json", "fault"))
        self.assertIn("mods/mc.a/entry.json", f["reason"])
        self.assertIn("commit", f["reason"])

    def test_c17b_each_kind_of_invalid_entry_is_a_fault(self):
        cases = {
            "not-json": "{nope",
            "empty": "",
            "array": "[]",
            "duplicate-key": '{"id":"mc:a","id":"mc:a","owner":{"provider":"g","id":1,"name_at_registration":"n"},"versions":[]}',
            "nan": '{"id":"mc:a","owner":{"provider":"g","id":NaN,"name_at_registration":"n"},"versions":[]}',
            "no-versions": json.dumps({**entry("mc", "a", []), "versions": []}),
            "extra-key": json.dumps({**entry("mc", "a", [pending("1.0.0")]), "extra": 1}),
            "owner-id-string": json.dumps({**entry("mc", "a", [pending("1.0.0")]), "owner": {**OWNER, "id": "1"}}),
            "owner-id-bool": json.dumps({**entry("mc", "a", [pending("1.0.0")]), "owner": {**OWNER, "id": True}}),
            "pending-with-reason": json.dumps(entry("mc", "a", [{**pending("1.0.0"), "reason": "x"}])),
            "published-missing-key": json.dumps(entry("mc", "a", [{k: v for k, v in published("1.0.0").items() if k != "key_id"}])),
            "bad-status": json.dumps(entry("mc", "a", [{**pending("1.0.0"), "status": "building"}])),
            "bad-semver": json.dumps(entry("mc", "a", [pending("1.0")])),
            "arabic-digit-semver": json.dumps(entry("mc", "a", [pending("١.0.0")])),
            "trailing-newline-commit": json.dumps(entry("mc", "a", [{**pending("1.0.0"), "commit": COMMIT + "\n"}])),
            "bad-source-url": json.dumps(entry("mc", "a", [{**pending("1.0.0"), "source_url": "not a url"}])),
            "duplicate-version": json.dumps(entry("mc", "a", [pending("1.0.0"), pending("1.0.0")])),
            "id-vs-directory": json.dumps(entry("mc", "other", [pending("1.0.0")])),
        }
        for label, raw in cases.items():
            with self.subTest(label):
                reg = Registry()
                self.addCleanup(reg.close)
                reg.add(None, dirname="mc.a", raw=raw)
                doc = pp.plan(reg.root, HEAD, [], [])
                self.assertEqual(doc["build"] + doc["refuse"] + doc["skip"], [], label)
                self.assertEqual([(f["entry_path"], f["kind"], f["version_id"]) for f in doc["fault"]],
                                 [("mods/mc.a/entry.json", "fault", None)], label)
                self.assertTrue(doc["fault"][0]["reason"])

    def test_c17b_positive_control_valid_entries_of_every_state_are_not_faults(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0-rc.1"), published("1.0.0"), removed("0.9.0"), rejected("0.8.0")]))
        doc = self.plan()
        self.assertEqual(doc["fault"], [])
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.0.0-rc.1"])

    def test_c17b_missing_entry_json_in_a_mods_directory_is_a_fault(self):
        os.makedirs(os.path.join(self.reg.root, "mods", "mc.a"))
        doc = self.plan()
        self.assertEqual([f["entry_path"] for f in doc["fault"]], ["mods/mc.a/entry.json"])

    def test_c17b_a_plain_file_in_mods_is_ignored(self):
        os.makedirs(os.path.join(self.reg.root, "mods"))
        open(os.path.join(self.reg.root, "mods", "README.md"), "w").write("x")
        self.assertEqual(self.plan()["fault"], [])


class C17cSummarize(unittest.TestCase):
    def plan_of(self, build=(), refuse=(), skip=(), fault=()):
        mk = lambda kind, vid: {"version_id": vid, "entry_path": "mods/" + (vid or "x.y@0").split("@")[0] + "/entry.json",
                                "kind": kind, "reason": "" if kind == "build" else "why"}
        return {"head_sha": HEAD, "build": [mk("build", v) for v in build], "refuse": [mk("refuse", v) for v in refuse],
                "skip": [mk("skip", v) for v in skip], "fault": [mk("fault", v) for v in fault]}

    def test_c17c_three_versions_ok_fault_ok_is_non_green_naming_exactly_the_faulted_one(self):
        p = self.plan_of(build=["a.one@1.0.0", "b.two@1.0.0", "c.three@1.0.0"])
        green, msg = pp.summarize_outcomes(p, [{"version_id": "a.one@1.0.0", "exit_class": 0},
                                               {"version_id": "b.two@1.0.0", "exit_class": 2},
                                               {"version_id": "c.three@1.0.0", "exit_class": 0}])
        self.assertFalse(green)
        self.assertIn("b.two@1.0.0", msg)
        self.assertNotIn("a.one@1.0.0", msg)
        self.assertNotIn("c.three@1.0.0", msg)

    def test_c17c_all_ok_is_green(self):
        p = self.plan_of(build=["a.one@1.0.0", "b.two@1.0.0"])
        green, msg = pp.summarize_outcomes(p, [{"version_id": "a.one@1.0.0", "exit_class": 0},
                                               {"version_id": "b.two@1.0.0", "exit_class": 0}])
        self.assertTrue(green)
        self.assertEqual(msg, "")

    def test_c17c_empty_plan_is_green(self):
        self.assertEqual(pp.summarize_outcomes(self.plan_of(), []), (True, ""))

    def test_c17c_a_skip_entry_is_non_green_naming_the_version(self):
        green, msg = pp.summarize_outcomes(self.plan_of(skip=["a.one@1.0.0"]), [])
        self.assertFalse(green)
        self.assertIn("a.one@1.0.0", msg)

    def test_c17c_refuse_entries_only_are_green(self):
        green, msg = pp.summarize_outcomes(self.plan_of(refuse=["a.one@1.0.0+b.1"]), [])
        self.assertTrue(green)

    def test_c17c_a_fault_entry_is_non_green_naming_the_file(self):
        p = self.plan_of(fault=[None])
        p["fault"][0]["entry_path"] = "mods/mc.a/entry.json"
        green, msg = pp.summarize_outcomes(p, [])
        self.assertFalse(green)
        self.assertIn("mods/mc.a/entry.json", msg)

    def test_c17c_exit_1_verdict_alone_keeps_the_run_green(self):
        # a 008a rejection is handled by its T3 (008b-3b); only exit 2 is a pipeline fault
        green, _ = pp.summarize_outcomes(self.plan_of(build=["a.one@1.0.0"]), [{"version_id": "a.one@1.0.0", "exit_class": 1}])
        self.assertTrue(green)

    def test_c17c_a_built_version_with_no_outcome_is_non_green(self):
        green, msg = pp.summarize_outcomes(self.plan_of(build=["a.one@1.0.0"]), [])
        self.assertFalse(green)
        self.assertIn("a.one@1.0.0", msg)

    def test_c17c_malformed_outcomes_raise(self):
        p = self.plan_of(build=["a.one@1.0.0"])
        for bad in ([{"version_id": "a.one@1.0.0", "exit_class": 3}], [{"version_id": "a.one@1.0.0"}],
                    [{"version_id": "a.one@1.0.0", "exit_class": True}],
                    [{"version_id": "x.y@1.0.0", "exit_class": 0}],
                    [{"version_id": "a.one@1.0.0", "exit_class": 0}, {"version_id": "a.one@1.0.0", "exit_class": 0}]):
            with self.assertRaises(ValueError, msg=repr(bad)):
                pp.summarize_outcomes(p, bad)


class C17dPlusRefusal(Base):
    def test_c17d_plus_version_is_refused_and_a_prerelease_is_built(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0+build.5"), pending("1.0.0-rc.1"), pending("1.0.0-rc.1+x")]))
        doc = self.plan()
        self.assertEqual(self.ids(doc, "build"), ["mc.a@1.0.0-rc.1"])
        self.assertEqual(self.ids(doc, "refuse"), ["mc.a@1.0.0+build.5", "mc.a@1.0.0-rc.1+x"])
        self.assertEqual(doc["refuse"][0]["reason"], PLUS_REASON)
        self.assertEqual(doc["refuse"][0]["kind"], "refuse")

    def test_c17d_reason_text_equals_the_contract_text(self):
        # the planner's constant is checked against the contract file, not only against this test's copy
        text = open(os.path.join(REPO, "contracts", "artifact-naming.md"), encoding="utf-8").read()
        flat = " ".join(text.split())
        self.assertIn('reason "' + PLUS_REASON + '"', flat)
        self.assertEqual(pp.PLUS_REFUSAL_REASON, PLUS_REASON)

    def test_c17d_a_published_plus_version_is_not_listed(self):
        self.reg.add(entry("mc", "a", [published("1.0.0+b.1")]))
        self.assertEqual(self.plan()["refuse"], [])


class C17eRefusalLog(Base):
    def test_c17e_log_exists_true_with_the_log_and_false_without_neither_is_a_fault(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0+b.1"), pending("2.0.0+b.2")]))
        doc = self.plan(logs=["logs/mc.a/1.0.0+b.1.log", "logs/mc.a/9.9.9.log"])
        by = {e["version_id"]: e for e in doc["refuse"]}
        self.assertIs(by["mc.a@1.0.0+b.1"]["log_exists"], True)
        self.assertIs(by["mc.a@2.0.0+b.2"]["log_exists"], False)
        self.assertEqual(doc["fault"], [])
        self.assertEqual(doc["build"], [])

    def test_c17e_log_match_is_exact(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0+b.1")]))
        for near in ("logs/mc.a/1.0.0+b.1", "logs/mc.a/1.0.0+b.2.log", "logs/mc.b/1.0.0+b.1.log", "mc.a/1.0.0+b.1.log",
                     "logs/mc.a/1.0.0+b.1.log.bak"):
            self.assertIs(self.plan(logs=[near])["refuse"][0]["log_exists"], False, near)

    def test_c17e_cli_carries_log_exists(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0+b.1")]))
        r = self.cli(logs=["logs/mc.a/1.0.0+b.1.log"])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIs(json.loads(r.stdout)["refuse"][0]["log_exists"], True)


class C17fExitCodes(Base):
    def test_c17f_plan_with_skip_refuse_and_fault_is_written_with_exit_0(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0"), pending("2.0.0+b.1")]))
        self.reg.add(None, dirname="bad.one", raw="{")
        r = self.cli(branches=["pipeline/mc.a-1.0.0"])
        self.assertEqual(r.returncode, 0, r.stderr)
        doc = json.loads(r.stdout)
        self.assertEqual([len(doc[k]) for k in ("build", "refuse", "skip", "fault")], [0, 1, 1, 1])

    def test_c17f_out_file_is_written_on_success_and_not_on_exit_1(self):
        d = tempfile.mkdtemp(prefix="wom008b1-out-")
        self.addCleanup(shutil.rmtree, d)
        out = os.path.join(d, "plan.json")
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        self.assertEqual(self.cli("--out", out).returncode, 0)
        self.assertEqual(json.load(open(out))["build"][0]["version_id"], "mc.a@1.0.0")
        os.remove(out)
        r = self.cli("--out", out, "--version", "bad")
        self.assertEqual(r.returncode, 1)
        self.assertFalse(os.path.exists(out))

    def test_c17f_conflicting_or_malformed_dry_run_sets_exit_1_no_document(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        url, c = "https://github.com/example/mod.git", "b" * 40
        bad_sets = [
            ["--dry-run", "yes"],
            ["--dry-run", "false", "--dry-run-source-url", url, "--dry-run-commit", c],   # pair without dry_run
            ["--dry-run", "true", "--dry-run-source-url", url],                              # half a pair
            ["--dry-run", "true", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", url, "--dry-run-commit", c, "--version", "mc.a@1.0.0"],
            ["--dry-run", "true", "--dry-run-source-url", "http://example.invalid/x", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", "https://", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", "https:///x", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", url + " x", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", url + "\n", "--dry-run-commit", c],
            ["--dry-run", "true", "--dry-run-source-url", url, "--dry-run-commit", "B" * 40],
            ["--dry-run", "true", "--dry-run-source-url", url, "--dry-run-commit", "b" * 39],
            ["--dry-run", "true", "--dry-run-source-url", url, "--dry-run-commit", "b" * 40 + "\n"],
            ["--dry-run", "true"],                                                          # nothing to dry-run
            ["--dry-run-source-url", url, "--dry-run-commit", c],                           # dry_run unset
        ]
        for argv in bad_sets:
            with self.subTest(argv=argv):
                r = self.cli(*argv)
                self.assertEqual(r.returncode, 1, r.stderr)
                self.assertEqual(r.stdout, "")

    def test_c17f_valid_dry_run_sets(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0"), pending("1.1.0")]))
        url, c = "https://github.com/example/mod.git", "b" * 40
        r = self.cli("--dry-run", "true", "--version", "mc.a@1.1.0")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual([e["version_id"] for e in json.loads(r.stdout)["build"]], ["mc.a@1.1.0"])
        r = self.cli("--dry-run", "true", "--dry-run-source-url", url, "--dry-run-commit", c)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout), {"head_sha": HEAD, "build": [], "refuse": [], "skip": [], "fault": []})

    def test_c17f_unreadable_or_malformed_state_and_inputs_exit_1(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        self.assertEqual(self.cli(registry=os.path.join(self.reg.root, "nope")).returncode, 1)
        d = tempfile.mkdtemp(prefix="wom008b1-cli-")
        self.addCleanup(shutil.rmtree, d)
        good = os.path.join(d, "g")
        open(good, "w").write("")
        base = ["--registry", self.reg.root, "--branches", good, "--archive-logs", good]
        runs = [
            base + ["--head-sha", "abc"],                                             # short sha
            base + ["--head-sha", HEAD.upper()],
            ["--registry", self.reg.root, "--head-sha", HEAD, "--branches", os.path.join(d, "absent"), "--archive-logs", good],
            ["--registry", self.reg.root, "--head-sha", HEAD, "--archive-logs", good],  # --branches missing
            base,                                                                      # --head-sha missing
            base + ["--head-sha", HEAD, "--bogus"],
        ]
        for argv in runs:
            r = subprocess.run([sys.executable, "-I", PLANNER, *argv], capture_output=True, text=True)
            self.assertEqual((r.returncode, r.stdout), (1, ""), (argv, r.stderr))
        bad = os.path.join(d, "badbranches")
        open(bad, "w").write("pipeline/a b\n")
        r = subprocess.run([sys.executable, "-I", PLANNER, "--registry", self.reg.root, "--head-sha", HEAD, "--branches", bad,
                            "--archive-logs", good], capture_output=True, text=True)
        self.assertEqual((r.returncode, r.stdout), (1, ""))

    def test_c17f_unreadable_entry_file_exits_1(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        p = os.path.join(self.reg.root, "mods", "mc.a", "entry.json")
        os.chmod(p, 0)
        try:
            if os.access(p, os.R_OK):
                self.skipTest("running as a user that ignores file modes")
            with self.assertRaises(pp.PlanInputError):
                self.plan()
        finally:
            os.chmod(p, 0o644)


class C17gSchema(Base):
    def test_c17g_every_entry_has_exactly_the_pinned_fields(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0"), pending("1.1.0"), pending("2.0.0+b.1"), pending("3.0.0")]))
        self.reg.add(None, dirname="bad.one", raw="{")
        doc = self.plan(branches=["pipeline/mc.a-1.1.0"], logs=["logs/mc.a/2.0.0+b.1.log"])
        self.assertEqual(set(doc), {"head_sha", "build", "refuse", "skip", "fault"})
        self.assertEqual(doc["head_sha"], HEAD)
        n = 0
        for kind in ("build", "refuse", "skip", "fault"):
            self.assertTrue(doc[kind], f"fixture must exercise {kind}")
            for e in doc[kind]:
                n += 1
                want = {"version_id", "entry_path", "kind", "reason"} | ({"log_exists"} if kind == "refuse" else set())
                self.assertEqual(set(e), want, kind)
                self.assertEqual(e["kind"], kind)
                self.assertTrue(e["entry_path"].startswith("mods/") and e["entry_path"].endswith("/entry.json"))
                self.assertIsInstance(e["reason"], str)
                if kind == "build":
                    self.assertEqual(e["reason"], "")
                else:
                    self.assertTrue(e["reason"])
                if kind == "refuse":
                    self.assertIsInstance(e["log_exists"], bool)
                if kind == "fault":
                    self.assertIsNone(e["version_id"])
                else:
                    self.assertRegex(e["version_id"], r"^[a-z0-9_-]+\.[a-z0-9_-]+@[0-9]")
        self.assertEqual(n, 5)

    def test_c17g_document_is_valid_json_on_stdout_only(self):
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        r = self.cli()
        json.loads(r.stdout)
        self.assertIn("head_sha=" + HEAD, r.stderr)

    def test_c17g_output_is_deterministic(self):
        self.reg.add(entry("zz", "b", [pending("1.0.0")]))
        self.reg.add(entry("mc", "a", [pending("1.0.0")]))
        a, b = self.cli().stdout, self.cli().stdout
        self.assertEqual(a, b)
        self.assertEqual([e["version_id"] for e in json.loads(a)["build"]], ["mc.a@1.0.0", "zz.b@1.0.0"])


def forbidden_imports(source):
    bad = {"subprocess", "socket", "urllib", "http", "requests", "ssl", "ftplib", "smtplib", "datetime", "time"}
    found = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            found |= {a.name.split(".")[0] for a in node.names} & bad
        elif isinstance(node, ast.ImportFrom) and node.module:
            found |= {node.module.split(".")[0]} & bad
    return found


class Forbidden(unittest.TestCase):
    def test_planner_has_no_network_process_clock_or_actor_use(self):
        src = open(PLANNER, encoding="utf-8").read()
        self.assertEqual(forbidden_imports(src), set())
        for needle in ("GITHUB_ACTOR", "os.system", "os.popen", "os.environ", "getenv"):
            self.assertNotIn(needle, src)

    def test_positive_control_forbidden_imports_are_detected(self):
        self.assertEqual(forbidden_imports("import subprocess\n"), {"subprocess"})
        self.assertEqual(forbidden_imports("from urllib.request import urlopen\n"), {"urllib"})
        self.assertEqual(forbidden_imports("import os, json\n"), set())

    def test_in_process_main_matches_cli_and_leaves_no_document_on_error(self):
        self.reg = Registry()
        self.addCleanup(self.reg.close)
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = pp.main(["--registry", self.reg.root, "--head-sha", "short", "--branches", "/dev/null", "--archive-logs", "/dev/null"])
        self.assertEqual((rc, out.getvalue()), (1, ""))


if __name__ == "__main__":
    unittest.main()
