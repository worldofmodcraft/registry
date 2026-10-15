"""report (verdict shape, three distinct exit codes) and the CLI end to end through real subprocesses."""

import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support
from support import CLI, attacker_entry, entry, pending, published, removed, report


class ReportModule(unittest.TestCase):
    def test_the_three_exit_codes_are_distinct_and_documented(self):
        self.assertEqual((report.EXIT_ACCEPTED, report.EXIT_REJECTED, report.EXIT_ERROR), (0, 1, 2))
        for word in ("accepted", "rejected", "usage or internal"):
            self.assertIn(word, report.__doc__)

    def test_verdict_is_rejected_exactly_when_there_are_findings(self):
        f = report.finding(["rule 2", "rule 4"], "what", "fix", "cite")
        self.assertEqual(report.make("x", [])["verdict"], "accepted")
        v = report.make("x", [f])
        self.assertEqual((v["verdict"], report.exit_code(v)), ("rejected", 1))
        self.assertEqual(report.exit_code(report.make("x", [])), 0)

    def test_a_finding_carries_a_list_of_rule_ids_and_a_three_part_message(self):
        f = report.finding(["rule 2", "rule 4"], "it is wrong", "do this", "append-only.rules.md", path="p", index=3)
        self.assertEqual(f["rules"], ["rule 2", "rule 4"])
        self.assertEqual((f["path"], f["index"]), ("p", 3))
        self.assertIn("rule 2 + rule 4 (append-only.rules.md): it is wrong. To fix: do this", f["message"])

    def test_a_finding_with_a_bare_string_rule_is_refused(self):
        for bad in ("rule 2", [], None):
            with self.assertRaises(report.ToolError):
                report.finding(bad, "w", "f", "c")

    def run_main(self, main):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            return report.run(main, []), out.getvalue(), err.getvalue()

    def test_run_maps_accepted_rejected_tool_error_and_crash_to_three_distinct_exits(self):
        rej = report.make("x", [report.finding(["R1"], "w", "f", "c")])

        def boom(_):
            raise KeyError("oops")

        def usage(_):
            raise report.ToolError("bad args")

        self.assertEqual(self.run_main(lambda _: report.make("x", []))[0], 0)
        self.assertEqual(self.run_main(lambda _: rej)[0], 1)
        code, out, err = self.run_main(usage)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("not a rejection", err)
        code, out, err = self.run_main(boom)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("KeyError", err)

    def test_a_rejection_prints_json_on_stdout_and_a_human_line_on_stderr(self):
        rej = report.make("x", [report.finding(["R1"], "w", "f", "c")])
        _, out, err = self.run_main(lambda _: rej)
        self.assertEqual(json.loads(out)["verdict"], "rejected")
        self.assertTrue(err.startswith("REJECTED R1 (c): w. To fix: f"))


class Cli(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        self.reserved = self.tmp / "reserved.json"
        self.reserved.write_text(json.dumps(support.RESERVED))

    def run_cli(self, *args):
        p = subprocess.run([sys.executable, "-I", str(CLI), *map(str, args)], capture_output=True, text=True)
        return p.returncode, (json.loads(p.stdout) if p.stdout.strip() else None), p.stderr

    def put(self, root, rel, doc):
        path = self.tmp / root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(doc if isinstance(doc, str) else json.dumps(doc))

    # --- classify
    def test_classify_accepts_exit_0_with_the_class(self):
        code, v, _ = self.run_cli("classify", "--reserved-file", self.reserved, "mods/a.b/page.json")
        self.assertEqual((code, v["class"]), (0, "page-only"))

    def test_classify_rejects_exit_1_and_names_r1(self):
        code, v, err = self.run_cli("classify", "--reserved-file", self.reserved, "mods/a.b/notes.txt")
        self.assertEqual(code, 1)
        self.assertEqual(v["findings"][0]["rules"], ["R1"])
        self.assertIn("REJECTED R1", err)

    def test_classify_reads_paths_from_a_file(self):
        pf = self.tmp / "paths.txt"
        pf.write_text("mods/a.b/entry.json\nmods/a.b/page.json\n")
        code, v, _ = self.run_cli("classify", "--reserved-file", self.reserved, "--paths-file", pf)
        self.assertEqual((code, v["class"]), (0, "entry"))

    def test_classify_empty_paths_file_is_a_rejection_not_a_pass(self):
        pf = self.tmp / "paths.txt"
        pf.write_text("")
        self.assertEqual(self.run_cli("classify", "--reserved-file", self.reserved, "--paths-file", pf)[0], 1)

    # --- usage / internal errors are exit 2, never exit 1
    def test_usage_errors_exit_2_and_print_no_verdict(self):
        for args in ((), ("classify",), ("schema", "mods/a.b/entry.json"), ("append-only", "--old-root", "x"),
                     ("nonsense",)):
            with self.subTest(args=args):
                code, v, err = self.run_cli(*args)
                self.assertEqual(code, 2)
                self.assertIsNone(v)
                self.assertTrue(err)

    def test_unreadable_or_garbage_reserved_list_is_exit_2_not_a_rejection(self):
        bad = self.tmp / "bad.json"
        bad.write_text("{nope")
        for rf in (self.tmp / "missing.json", bad):
            with self.subTest(reserved=rf.name):
                self.assertEqual(self.run_cli("classify", "--reserved-file", rf, "mods/a.b/entry.json")[0], 2)

    def test_a_merge_base_that_is_not_an_entry_is_exit_2(self):
        self.put("old", "mods/a.b/entry.json", {"versions": "x"})
        self.put("new", "mods/a.b/entry.json", entry(pending(), id="a:b"))
        code, v, err = self.run_cli("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new",
                                    "mods/a.b/entry.json")
        self.assertEqual(code, 2)
        self.assertIsNone(v)

    # --- schema
    def test_schema_cli_accepts_and_rejects(self):
        self.put("r", "mods/a.b/entry.json", entry(pending(), id="a:b"))
        self.put("r", "mods/c.d/entry.json", attacker_entry())
        self.assertEqual(self.run_cli("schema", "--root", self.tmp / "r", "mods/a.b/entry.json")[0], 0)
        code, v, _ = self.run_cli("schema", "--root", self.tmp / "r", "mods/c.d/entry.json")
        self.assertEqual((code, v["findings"][0]["rules"]), (1, ["schema:entry"]))

    def test_schema_cli_invalid_json_is_a_rejection(self):
        self.put("r", "mods/a.b/entry.json", "{broken")
        code, v, _ = self.run_cli("schema", "--root", self.tmp / "r", "mods/a.b/entry.json")
        self.assertEqual((code, v["findings"][0]["rules"]), (1, ["json-syntax"]))

    def test_cli_never_reads_a_path_outside_the_r1_form(self):
        secret = self.tmp / "secret.json"
        secret.write_text("{broken")
        code, v, _ = self.run_cli("schema", "--root", self.tmp, "secret.json")
        self.assertEqual((code, v["findings"][0]["rules"]), (1, ["no-schema"]))

    # --- append-only
    def test_append_only_cli_lists_authority_required_and_documents_it(self):
        self.put("old", "mods/a.b/entry.json", entry(published(), id="a:b"))
        self.put("new", "mods/a.b/entry.json", entry(removed(), id="a:b"))
        code, v, _ = self.run_cli("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new",
                                  "mods/a.b/entry.json")
        self.assertEqual((code, v["authority_required"], v["elements"][0]["classification"]), (0, ["T2"], "T2"))
        doc = subprocess.run([sys.executable, str(CLI), "--help"], capture_output=True, text=True).stdout
        self.assertIn("never authorises a merge", doc)
        self.assertIn("authority_required", doc)

    def test_append_only_cli_absent_sides_deletion_and_creation(self):
        self.put("old", "mods/a.b/entry.json", entry(pending(), id="a:b"))
        (self.tmp / "new").mkdir()
        code, v, _ = self.run_cli("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new",
                                  "mods/a.b/entry.json")
        self.assertEqual((code, v["findings"][0]["rules"]), (1, ["deletion"]))
        code, v, _ = self.run_cli("append-only", "--old-root", self.tmp / "new", "--new-root", self.tmp / "old",
                                  "mods/a.b/entry.json")
        self.assertEqual((code, v["states"]), (0, {"mods/a.b/entry.json": "absent->present"}))

    def test_append_only_cli_attacker_first_publish_is_rejected(self):
        self.put("new", "mods/attacker.mod/entry.json", attacker_entry())
        (self.tmp / "old").mkdir()
        code, v, _ = self.run_cli("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new",
                                  "mods/attacker.mod/entry.json")
        self.assertEqual(code, 1)
        self.assertEqual([e["rules"] for e in v["elements"]],
                         [["rule 2", "rule 4"], ["rule 2", "rule 4"], ["rule 2"], ["rule 2"]])


if __name__ == "__main__":
    unittest.main()
