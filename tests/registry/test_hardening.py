"""Fix round 1: F1 trailing-newline patterns (ECMA-262 `$`), F2 symlinks, F3 duplicate JSON keys.

Each hostile test was first shown red against the unfixed code (see the task log), then fixed.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support
from support import CLI, append_only, entry, pending, published, rejected, schema

ENTRY = "mods/kelsi.housing/entry.json"
PAGE = "mods/kelsi.housing/page.json"


def t1_with(**change):
    w = published()
    w.update(change)
    return append_only.check_entry(entry(pending()), entry(w))


class F1TrailingNewlineAppendOnly(unittest.TestCase):
    def test_f1_born_pending_commit_with_trailing_newline_is_rule_2(self):
        v = append_only.check_entry(None, entry(pending(commit="a" * 40 + "\n")))
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(v["elements"][0]["rules"], ["rule 2"])

    def test_f1_born_pending_version_and_source_url_with_trailing_newline_are_rule_2(self):
        for k, val in (("version", "1.0.0\n"), ("source_url", "https://github.com/e/m\n")):
            with self.subTest(field=k):
                v = append_only.check_entry(None, entry(dict(pending(), **{k: val})))
                self.assertEqual(v["elements"][0]["rules"], ["rule 2"])

    def test_f1_t1_pipeline_fields_with_trailing_newline_are_rejected(self):
        for k, val in (("source_sha256", "b" * 64 + "\n"), ("source_archive", "https://cdn.example.org/a.tgz\n"),
                       ("published_at", "2026-10-15T09:00:00Z\n")):
            with self.subTest(field=k):
                v = t1_with(**{k: val})
                self.assertEqual(v["verdict"], "rejected")
                self.assertEqual(v["elements"][0]["rules"], ["rule 1"])
                self.assertEqual(v["elements"][0]["attempted"], "T1")

    def test_f1_signature_and_key_id_carry_no_pattern_so_a_trailing_newline_is_contract_valid(self):
        """entry.schema.json gives these two minLength only, and signature-format.md says `signature` holds
        multi-line text. Rejecting them would invent a rule; reported to the manager (task log, Questions)."""
        for k, val in (("signature", "c" * 62 + "\n"), ("key_id", "platform-2026-01\n")):
            with self.subTest(field=k):
                self.assertEqual(t1_with(**{k: val})["verdict"], "accepted")
                self.assertEqual(schema.check({ENTRY: entry(dict(published(), **{k: val}))})["verdict"], "accepted")

    def test_f1_key_id_with_trailing_newline_is_rejected_task_065(self):
        """Task 065 (the one deliberate assertion reversal, objective item 2b): contracts/signature-format.md
        "Deriving `key_id`" says `key_id` is exactly 16 uppercase hex characters, so entry.schema.json now carries
        `^[0-9A-F]{16}$` and a trailing newline is rejected. Before 065 there was no such rule and this value was
        accepted (the signature half of the old test keeps that assertion unchanged)."""
        for value in ("platform-2026-01\n", "E7A1B2C3D4E5F607\n"):
            with self.subTest(key_id=value):
                self.assertEqual(t1_with(key_id=value)["verdict"], "rejected")
                self.assertEqual(schema.check({ENTRY: entry(dict(published(), key_id=value))})["verdict"], "rejected")

    def test_f1_t3_build_log_url_with_trailing_newline_is_rejected(self):
        v = append_only.check_entry(entry(pending()), entry(rejected(url="https://x.org/log\n")))
        self.assertEqual(v["verdict"], "rejected")
        self.assertEqual(v["elements"][0]["rules"], ["rule 1"])

    def test_f1_positive_controls_same_values_without_the_newline_are_accepted(self):
        self.assertEqual(t1_with()["verdict"], "accepted")
        self.assertEqual(append_only.check_entry(entry(pending()), entry(rejected(url="https://x.org/log")))["verdict"],
                         "accepted")
        self.assertEqual(append_only.check_entry(None, entry(pending()))["verdict"], "accepted")

    def test_f1_a_newline_inside_the_value_was_already_rejected_and_still_is(self):
        self.assertEqual(append_only.check_entry(None, entry(pending(commit="a" * 39 + "\n" + "a")))["verdict"],
                         "rejected")


class F1TrailingNewlineSchema(unittest.TestCase):
    def test_f1_schema_check_rejects_entry_strings_with_trailing_newline(self):
        for k, val in (("commit", "a" * 40 + "\n"), ("version", "1.0.0\n"), ("source_url", "https://github.com/e/m\n")):
            with self.subTest(field=k):
                v = schema.check({ENTRY: entry(dict(pending(), **{k: val}))})
                self.assertEqual(v["verdict"], "rejected")
                self.assertEqual(v["findings"][0]["rules"], ["schema:entry"])
                self.assertIn("end of input", v["findings"][0]["message"])

    def test_f1_schema_check_rejects_published_and_rejected_pipeline_strings(self):
        for doc in (entry(dict(published(), source_sha256="b" * 64 + "\n")), entry(rejected(url="https://x.org/log\n"))):
            with self.subTest(doc=doc["versions"][0]["status"]):
                self.assertEqual(schema.check({ENTRY: doc})["verdict"], "rejected")

    def test_f1_schema_check_rejects_page_strings_with_trailing_newline(self):
        page = {"description": "d", "screenshots": [], "tags": [], "links": [], "deprecated": False}
        for patch in ({"screenshots": ["a/b.png\n"]}, {"links": [{"label": "l", "url": "https://x.org\n"}]}):
            with self.subTest(patch=patch):
                self.assertEqual(schema.check({PAGE: dict(page, **patch)})["verdict"], "rejected")

    def test_f1_schema_check_positive_controls(self):
        page = {"description": "d", "screenshots": ["a/b.png"], "tags": [], "links": [{"label": "l", "url": "https://x.org"}],
                "deprecated": False}
        self.assertEqual(schema.check({PAGE: page, ENTRY: entry(pending())})["verdict"], "accepted")

    def test_f1_ecma_conversion_leaves_escaped_dollar_and_classes_alone(self):
        self.assertEqual(schema.ecma_pattern(r"^a\$b$"), r"^a\$b\Z")
        self.assertEqual(schema.ecma_pattern(r"^[$]x$"), r"^[$]x\Z")
        self.assertEqual(schema.ecma_pattern(r"^[\]$]$"), r"^[\]$]\Z")


class F2Symlinks(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def run_cli(self, *args):
        p = subprocess.run([sys.executable, "-I", str(CLI), *map(str, args)], capture_output=True, text=True)
        return p.returncode, (json.loads(p.stdout) if p.stdout.strip() else None), p.stderr

    def test_f2_a_symlinked_entry_json_is_a_rejection_not_a_read_through(self):
        target = self.tmp / "elsewhere.json"
        target.write_text(json.dumps(entry(pending())))
        d = self.tmp / "new" / "mods" / "kelsi.housing"
        d.mkdir(parents=True)
        os.symlink(target, d / "entry.json")
        (self.tmp / "old").mkdir()
        for args in (("schema", "--root", self.tmp / "new", ENTRY),
                     ("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new", ENTRY)):
            with self.subTest(cmd=args[0]):
                code, v, _ = self.run_cli(*args)
                self.assertEqual(code, 1)
                self.assertEqual(v["findings"][0]["rules"], ["symlink"])
                self.assertIn("--no-renames", v["findings"][0]["message"])

    def test_f2_a_symlink_on_the_old_side_is_also_a_rejection(self):
        target = self.tmp / "elsewhere.json"
        target.write_text(json.dumps(entry(pending())))
        d = self.tmp / "old" / "mods" / "kelsi.housing"
        d.mkdir(parents=True)
        (self.tmp / "new").mkdir()
        d2 = d
        os.symlink(target, d2 / "entry.json")
        code, v, _ = self.run_cli("append-only", "--old-root", self.tmp / "old", "--new-root", self.tmp / "new", ENTRY)
        self.assertEqual((code, v["findings"][0]["rules"]), (1, ["symlink"]))

    def test_f2_help_and_readme_say_diff_with_no_renames(self):
        helptext = subprocess.run([sys.executable, str(CLI), "--help"], capture_output=True, text=True).stdout
        self.assertIn("--no-renames", helptext)
        self.assertIn("--no-renames", (support.REPO / "docs" / "contracts" / "README.md").read_text())


class F3DuplicateKeys(unittest.TestCase):
    DUP = '{"id": "kelsi:housing", "id": "evil:thing", "owner": {"provider": "github", "id": 1, "name_at_registration": "k"}, "versions": []}'

    def test_f3_schema_check_text_path_rejects_duplicate_keys(self):
        v = schema.check({ENTRY: self.DUP})
        self.assertEqual((v["verdict"], v["findings"][0]["rules"]), ("rejected", ["duplicate-key"]))
        self.assertIn("To fix:", v["findings"][0]["message"])

    def test_f3_nested_duplicate_keys_are_rejected_too(self):
        text = '{"id": "a:b", "owner": {"provider": "x", "provider": "y", "id": 1, "name_at_registration": "k"}, "versions": []}'
        self.assertEqual(schema.check({ENTRY: text})["findings"][0]["rules"], ["duplicate-key"])

    def test_f3_cli_rejects_duplicate_keys_on_either_side(self):
        with tempfile.TemporaryDirectory() as t:
            t = Path(t)
            for side, text in (("old", self.DUP), ("new", self.DUP)):
                d = t / side / "mods" / "kelsi.housing"
                d.mkdir(parents=True)
                (d / "entry.json").write_text(text)
                other = "new" if side == "old" else "old"
                (t / other).mkdir(exist_ok=True)
                args = ["append-only", "--old-root", t / "old", "--new-root", t / "new", ENTRY]
                p = subprocess.run([sys.executable, "-I", str(CLI), *map(str, args)], capture_output=True, text=True)
                self.assertEqual(p.returncode, 1, side)
                self.assertEqual(json.loads(p.stdout)["findings"][0]["rules"], ["duplicate-key"])
                (d / "entry.json").unlink()
            (t / "r" / "mods" / "kelsi.housing").mkdir(parents=True)
            (t / "r" / ENTRY).write_text(self.DUP)
            p = subprocess.run([sys.executable, "-I", str(CLI), "schema", "--root", str(t / "r"), ENTRY],
                               capture_output=True, text=True)
            self.assertEqual((p.returncode, json.loads(p.stdout)["findings"][0]["rules"]), (1, ["duplicate-key"]))

    def test_f3_positive_control_distinct_keys_still_parse(self):
        self.assertEqual(schema.check({ENTRY: json.dumps(entry(pending()))})["verdict"], "accepted")


if __name__ == "__main__":
    unittest.main()
