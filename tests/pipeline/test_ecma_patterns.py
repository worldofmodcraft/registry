"""Task 094: the pipeline matches every schema pattern with the gate's ECMA-262 semantics.

The registry gate validates with tools/registry/schema.py (`re.search(ecma_pattern(p), s)`). The pipeline modules
(build_version, write_back, plan_pending and, through them, handoff and sign_built) must give the same verdict
for every pattern in contracts/entry.schema.json. The oracle below loads schema.py ITSELF (not through
tools/pipeline/ecma.py) so a defect in the helper cannot hide in the test.

Expected values are typed here or computed by the gate's own translator, never by the code under test.
Nothing here touches the network, a process or any key."""

from __future__ import annotations

import ast
import json
import os
import random
import re
import sys
import tempfile
import unittest

from helpers import REPO, TOOLS  # noqa: F401  (helpers puts tools/pipeline on sys.path)

import build_version  # noqa: E402
import handoff  # noqa: E402
import plan_pending  # noqa: E402
import sign_built  # noqa: E402
import write_back as wb  # noqa: E402
from pipeline_errors import Rejected  # noqa: E402

ENTRY_SCHEMA = os.path.join(REPO, "contracts", "entry.schema.json")

ARABIC = "٣"        # ARABIC-INDIC DIGIT THREE: Python's \d matches it, ECMA-262's does not
FULLWIDTH = "１"     # FULLWIDTH DIGIT ONE
SHA = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
SIG = "untrusted comment: placeholder\nRWQAAAAA_placeholder_signature_bytes_base64==\ntrusted comment: x\nAAAA"
BUILT_AT = "2026-10-28T10:00:00Z"
OWNER = {"provider": "github", "id": 4831207, "name_at_registration": "kelsi"}
PEND = {"version": "1.0.0", "commit": "a" * 40, "source_url": "https://github.com/kelsi/housing", "status": "pending"}
ARCHIVE = "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz"


# ------------------------------------------------------------------ the oracle: the gate, loaded independently

def load_gate_schema():
    """tools/registry/schema.py, loaded by path. It imports `classify`, `report` (next to it) and `schema_check`
    (tests/contracts); those three module names are saved and restored so neither this loader nor the gate's
    imports can shadow, or be shadowed by, tests/validation/schema_check.py or anything else on sys.path."""
    import importlib.util
    names = ("classify", "report", "schema_check")
    saved_mods = {n: sys.modules.pop(n, None) for n in names}
    saved_path = list(sys.path)
    sys.path[:0] = [os.path.join(REPO, "tools", "registry"), os.path.join(REPO, "tests", "contracts")]
    try:
        spec = importlib.util.spec_from_file_location("wom_094_gate_schema", os.path.join(REPO, "tools", "registry", "schema.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        sys.path[:] = saved_path
        for n, m in saved_mods.items():
            if m is None:
                sys.modules.pop(n, None)
            else:
                sys.modules[n] = m


GATE = load_gate_schema()


def gate(pattern: str, value) -> bool:
    """The gate's verdict, written out here: re.search(ecma_pattern(p), s) (tools/registry/schema.py `_strict_patterns`)."""
    return isinstance(value, str) and re.search(GATE.ecma_pattern(pattern), value) is not None


def helper():
    """The module under test, imported at call time so that, before the fix, only the tests that need it fail."""
    import ecma
    return ecma


def collect_patterns(node, path="$"):
    """Every `pattern` keyword in a JSON schema, by recursive walk: [(path, pattern)]."""
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "pattern" and isinstance(v, str):
                out.append((path, v))
            else:
                out.extend(collect_patterns(v, f"{path}.{k}"))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out.extend(collect_patterns(v, f"{path}[{i}]"))
    return out


def entry_with(*versions, eid="kelsi:housing"):
    return {"id": eid, "owner": dict(OWNER), "versions": [dict(v) for v in versions]}


def result_for(version="1.0.0", eid="kelsi:housing", built_at=BUILT_AT):
    return {"id": eid, "version": version, "built_at": built_at, "tag": "x", "assets": ["x"],
            "artifact": {"source_sha256": SHA, "signature": SIG, "key_id": "E7A1B2C3D4E5F607"}}


def apply_with_archive(url):
    return wb.apply_write_back(entry_with(PEND), result_for(), url)


def refused_bad_value(testcase, url):
    with testcase.assertRaises(wb.WriteBackRefused) as cm:
        apply_with_archive(url)
    testcase.assertEqual(cm.exception.reason, "bad-value")


def write_entry_file(directory, mod_id="test:hello", version="1.0.0"):
    path = os.path.join(directory, "entry.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"id": mod_id, "owner": dict(OWNER),
                   "versions": [{"version": version, "commit": "a" * 40, "source_url": "https://example.invalid/x", "status": "pending"}]}, f)
    return path


# ------------------------------------------------------------------ criterion 1: red first

class RedFirst(unittest.TestCase):
    def test_c1a_build_version_rejects_a_non_ascii_digit_in_the_version(self):
        with tempfile.TemporaryDirectory(prefix="wom094-") as d:
            entry = write_entry_file(d)
            for v in ("1.0.1" + ARABIC, ARABIC + ".0.0", "1.0.0-rc." + ARABIC, "1.0." + FULLWIDTH):
                with self.subTest(version=v):
                    with self.assertRaises(Rejected) as cm:
                        build_version.preflight(entry, v, True)
                    self.assertEqual(cm.exception.rule, "version/not-semver")

    def test_c1a_build_version_rejects_a_non_ascii_digit_in_published_at(self):
        for bad in ("2026-10-2" + ARABIC + "T10:00:00Z", "202" + ARABIC + "-10-28T10:00:00Z", "2026-10-28T10:00:00." + ARABIC + "Z",
                    "2026-10-28T10:00:00Z\n"):
            with self.subTest(built_at=bad):
                self.assertFalse(build_version._fullmatch(build_version._PAT_PUBLISHED_AT, bad))
        self.assertTrue(build_version._fullmatch(build_version._PAT_PUBLISHED_AT, BUILT_AT), "positive control")

    def test_c1b_write_back_refuses_u_feff_in_source_archive(self):
        # ECMA-262 WhiteSpace includes U+FEFF, so `\S` excludes it; Python's `\S` accepts it.
        for url in ("https://a.example/x﻿y", "https://a.example/x﻿", "https://﻿"):
            with self.subTest(url=url):
                refused_bad_value(self, url)

    def test_c1c_write_back_accepts_u_001c_to_u_001f_and_u_0085_in_source_archive(self):
        # Python's `\s` matches these, ECMA-262's does not, so ECMA `\S` matches them: the gate accepts, so the pipeline must.
        for ch in ("\x1c", "\x1d", "\x1e", "\x1f", "\x85"):
            url = "https://a.example/x" + ch + "y"
            with self.subTest(codepoint="U+%04X" % ord(ch)):
                self.assertTrue(gate(r"^https://\S+$", url), "control: the gate accepts it")
                out = apply_with_archive(url)
                self.assertEqual(out["versions"][0]["source_archive"], url)


# ------------------------------------------------------------------ criterion 2: positive controls

class PositiveControls(unittest.TestCase):
    def test_c2_unicode_whitespace_in_source_archive_stays_refused(self):
        for ch in (" ", " ", " ", "　", " "):
            with self.subTest(codepoint="U+%04X" % ord(ch)):
                refused_bad_value(self, "https://a.example/x" + ch + "y")

    def test_c2_ordinary_non_ascii_visible_characters_stay_accepted(self):
        url = "https://a.example/café/中/\U0001f600"
        self.assertEqual(apply_with_archive(url)["versions"][0]["source_archive"], url)

    def test_c2_id_with_a_trailing_newline_stays_rejected(self):
        with self.assertRaises(wb.WriteBackRefused) as cm:
            wb.source_archive_url("mc", "hello\n", "1.0.0")
        self.assertEqual(cm.exception.reason, "bad-id")
        with tempfile.TemporaryDirectory(prefix="wom094-") as d:
            with self.assertRaises(Rejected) as cm2:
                build_version.preflight(write_entry_file(d, "test:hello\n"), "1.0.0", True)
            self.assertEqual(cm2.exception.rule, "entry/id")

    def test_c2_commit_stays_hex_only(self):
        with tempfile.TemporaryDirectory(prefix="wom094-") as d:
            for bad in ("a" * 39 + "g", "A" * 40, "a" * 40 + "\n", "a" * 39 + ARABIC, "a" * 39):
                path = write_entry_file(d)
                with open(path, encoding="utf-8") as f:
                    e = json.load(f)
                e["versions"][0]["commit"] = bad
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(e, f)
                with self.subTest(commit=bad):
                    with self.assertRaises(Rejected) as cm:
                        build_version.preflight(path, "1.0.0", True)
                    self.assertEqual(cm.exception.rule, "commit/not-40-lowercase-hex")


# ------------------------------------------------------------------ criterion 3: equivalence with the gate

# One known-valid example per pattern of contracts/entry.schema.json (keyed by the pattern text, so a changed pattern is a KeyError).
EXAMPLES = {
    "^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$": "mc:hello-world",
    "^(0|[1-9]\\d*)\\.(0|[1-9]\\d*)\\.(0|[1-9]\\d*)(?:-((?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+([0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$": "1.0.0-rc.1+build.5",
    "^[0-9a-f]{40}$": "0123456789abcdef0123456789abcdef01234567",
    "^([a-zA-Z][a-zA-Z0-9+.-]*://\\S+|[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:\\S+)$": "https://github.com/kelsi/housing",
    "^https://\\S+$": "https://archive.worldofmodcraft.com/x/y.tar.gz",
    "^[0-9a-f]{64}$": SHA,
    "^[0-9A-F]{16}$": "E7A1B2C3D4E5F607",
    "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?(Z|[+-]\\d{2}:\\d{2})$": "2026-10-28T10:00:00.5+01:00",
}

INTERESTING = ["\n", "\r", ARABIC, FULLWIDTH, "﻿", "\x1c", "\x1d", "\x1e", "\x1f", "\x85", "\xa0", " ", " "]
ALPHABET = [chr(c) for c in range(0x20, 0x7F)] + INTERESTING
MIN_PER_PATTERN = 20000
SEED = 94094


def strings_for(pattern: str, index: int) -> list:
    """>= MIN_PER_PATTERN distinct strings, seeded: the valid example, near-valid mutants of it, random strings over the
    alphabet, and random tails after a prefix of the example."""
    rnd = random.Random(SEED + index)
    example = EXAMPLES[pattern]

    def ch():
        return rnd.choice(INTERESTING) if rnd.random() < 0.5 else rnd.choice(ALPHABET)

    def mutant():
        s = example
        for _ in range(rnd.randint(1, 3)):
            op = rnd.choice(("replace", "insert", "delete", "append", "prepend", "truncate"))
            pos = rnd.randint(0, max(len(s) - 1, 0))
            if op == "replace" and s:
                s = s[:pos] + ch() + s[pos + 1:]
            elif op == "insert":
                s = s[:pos] + ch() + s[pos:]
            elif op == "delete" and s:
                s = s[:pos] + s[pos + 1:]
            elif op == "append":
                s += ch()
            elif op == "prepend":
                s = ch() + s
            elif op == "truncate":
                s = s[:pos]
        return s

    out = {example}
    while len(out) < MIN_PER_PATTERN:
        kind = rnd.random()
        if kind < 0.6:
            out.add(mutant())
        elif kind < 0.75:
            out.add("".join(rnd.choice(ALPHABET) for _ in range(rnd.randint(0, 40))))
        else:
            cut = example[:rnd.randint(0, len(example))]
            out.add(cut + "".join(ch() for _ in range(rnd.randint(1, 6))))
    return sorted(out)


class Equivalence(unittest.TestCase):
    def test_c3_the_schema_has_nine_patterns_all_anchored_and_all_have_an_example(self):
        with open(ENTRY_SCHEMA, encoding="utf-8") as f:
            found = collect_patterns(json.load(f))
        self.assertEqual(len(found), 9, f"entry.schema.json changed: review the pattern list {[p for _, p in found]}")
        for path, p in found:
            with self.subTest(path=path):
                self.assertTrue(p.startswith("^"), f"{path}: {p!r} is not anchored at the start")
                self.assertTrue(p.endswith("$") and not p.endswith("\\$"), f"{path}: {p!r} is not anchored at the end")
                self.assertIn(p, EXAMPLES, f"{path}: no known-valid example for this pattern")
                self.assertTrue(gate(p, EXAMPLES[p]), f"{path}: the example is not valid under the gate")

    def test_c3_helper_verdict_equals_the_gates_for_every_pattern(self):
        ecma = helper()
        with open(ENTRY_SCHEMA, encoding="utf-8") as f:
            found = collect_patterns(json.load(f))
        self.assertEqual(len(found), 9)
        for index, (path, p) in enumerate(found):
            strings = strings_for(p, index)
            self.assertGreaterEqual(len(strings), MIN_PER_PATTERN)
            compiled = re.compile(GATE.ecma_pattern(p))
            accepted = rejected = 0
            diffs = []
            for s in strings:
                want = compiled.search(s) is not None
                got = ecma.matches(p, s)
                if got != want and len(diffs) < 5:
                    diffs.append((s, got, want))
                accepted += want
                rejected += not want
            with self.subTest(path=path, pattern=p):
                self.assertEqual(diffs, [], f"{path}: helper and gate disagree (string, helper, gate)")
                self.assertGreaterEqual(accepted, 1, f"{path}: no accepted string: the set proves nothing")
                self.assertGreaterEqual(rejected, 1, f"{path}: no rejected string: the set proves nothing")

    def test_c3_the_generator_reaches_the_cases_that_matter(self):
        # The sets must contain the Python-vs-ECMA divergences, else equivalence over them is vacuous.
        semver = next(p for p in EXAMPLES if p.startswith("^(0|"))
        url = "^https://\\S+$"
        s_semver, s_url = strings_for(semver, 1), strings_for(url, 4)
        self.assertTrue(any(ARABIC in s for s in s_semver))
        self.assertTrue(any("﻿" in s and s.startswith("https://") for s in s_url))
        self.assertTrue(any("\x1c" in s and s.startswith("https://") for s in s_url))
        self.assertTrue(any("\x85" in s and s.startswith("https://") for s in s_url))
        self.assertTrue(any(s.endswith("\n") for s in s_semver))

    def test_c3_the_divergences_are_real(self):
        # Control: raw Python re really differs from the gate on these, so a helper that skipped the translation would be caught.
        url = "^https://\\S+$"
        self.assertTrue(re.search(url, "https://a/x﻿y") is not None and not gate(url, "https://a/x﻿y"))
        self.assertTrue(re.search(url, "https://a/x\x85y") is None and gate(url, "https://a/x\x85y"))
        semver = next(p for p in EXAMPLES if p.startswith("^(0|"))
        self.assertTrue(re.search(semver, "1.0.1" + ARABIC) is not None and not gate(semver, "1.0.1" + ARABIC))


# ------------------------------------------------------------------ criterion 3b: handoff and sign_built (new callers)

SCAN = {"schema_version": "1.0.0", "root": "src",
        "summary": {"files_inspected": 0, "files_accepted": 0, "files_rejected": 0, "files_skipped": 0,
                    "skipped_reasons": {}, "scan_errors": 0},
        "accepted": [], "rejected": [], "scan_errors": []}


def built_result(built_at):
    return {"id": "test:hello", "version": "1.0.0", "tag": "test.hello-1.0.0",
            "assets": {"tarball": "test.hello-1.0.0.tar.gz", "signature": "test.hello-1.0.0.tar.gz.minisig"},
            "built_at": built_at, "artifact": {"source_sha256": SHA}, "signed": False, "scan": SCAN}


class NewCallers(unittest.TestCase):
    ID = "^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$"
    SEMVER = next(p for p in EXAMPLES if p.startswith("^(0|"))
    PUBLISHED_AT = next(p for p in EXAMPLES if p.startswith("^\\d{4}"))

    BAD_COMMON = [ARABIC, FULLWIDTH, "\n", "\r", "﻿", "\x1c", "\x1f", "\x85", "\xa0", " ", " "]

    def verdicts(self, pattern, prefix, suffix, call):
        """For each hostile character in three positions, the caller's accept/reject must equal the gate's."""
        seen_ok = seen_bad = 0
        for ch in self.BAD_COMMON:
            for s in (prefix + ch + suffix, ch + prefix + suffix, prefix + suffix + ch):
                want = gate(pattern, s)
                got = call(s)
                with self.subTest(value=s):
                    self.assertEqual(got, want)
                seen_ok += want
                seen_bad += not want
        self.assertTrue(call(prefix + suffix) and gate(pattern, prefix + suffix), "positive control")
        self.assertGreaterEqual(seen_bad, 1)

    def test_c3b_handoff_synthetic_entry_gives_the_gates_verdict_on_id_and_version(self):
        def id_ok(s):
            try:
                handoff.synthetic_entry(s, "1.0.0", "0" * 40, "https://example.invalid/")
                return True
            except handoff.HandoffError:
                return False

        def version_ok(s):
            try:
                handoff.synthetic_entry("test:hello", s, "0" * 40, "https://example.invalid/")
                return True
            except handoff.HandoffError:
                return False

        self.verdicts(self.ID, "test:", "hello", id_ok)
        self.verdicts(self.SEMVER, "1.0.", "1", version_ok)
        for s in ("1.0.1" + ARABIC, "1.0.1\n", "1.0.1\x1c", "1.0.1\x85"):
            self.assertFalse(version_ok(s), repr(s))

    def test_c3b_handoff_plan_matrix_refuses_a_non_ascii_digit_version(self):
        with self.assertRaises(handoff.HandoffError):
            handoff.plan_matrix({"build": []}, "test:hello", "1.0.1" + ARABIC, pair=True)

    def test_c3b_sign_built_gives_the_gates_verdict_on_built_at(self):
        with tempfile.TemporaryDirectory(prefix="wom094-") as d:
            path = os.path.join(d, "result.json")

            def built_at_ok(s):
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(built_result(s), f)
                try:
                    sign_built._read_result(path)
                    return True
                except sign_built.SignRefused as exc:
                    if exc.rule != "result/built-at":
                        raise
                    return False

            self.verdicts(self.PUBLISHED_AT, "2026-10-28T10:00:0", "0Z", built_at_ok)
            for s in ("2026-10-2" + ARABIC + "T10:00:00Z", "202" + ARABIC + "-10-28T10:00:00Z", "2026-10-28T10:00:00." + FULLWIDTH + "Z"):
                self.assertFalse(built_at_ok(s), repr(s))


# ------------------------------------------------------------------ plan_pending's subset validator and callers

class PlanPendingValidator(unittest.TestCase):
    URL = {"type": "string", "pattern": "^https://\\S+$"}
    SEMVER = {"type": "string", "pattern": NewCallers.SEMVER}

    def fault(self, value, sub):
        try:
            plan_pending._validate(value, sub, "$")
            return False
        except plan_pending.SchemaFault:
            return True

    def test_validator_gives_the_gates_verdict(self):
        cases = [(self.URL, "https://a/x﻿y"), (self.URL, "https://a/x\x1cy"), (self.URL, "https://a/x\x85y"),
                 (self.URL, "https://a/x y"), (self.URL, "https://a/x y"), (self.URL, "https://a/x\n"),
                 (self.URL, "https://a/café"), (self.SEMVER, "1.0.1" + ARABIC), (self.SEMVER, "1.0.1\n"), (self.SEMVER, "1.0.1")]
        for sub, value in cases:
            with self.subTest(value=value, pattern=sub["pattern"]):
                self.assertEqual(self.fault(value, sub), not gate(sub["pattern"], value))

    def test_a_pending_entry_whose_source_url_holds_u_0085_is_planned_not_faulted(self):
        # The gate accepts U+0085 inside `\S+`; the planner must not turn a gate-valid entry into a fault.
        with tempfile.TemporaryDirectory(prefix="wom094-") as d:
            mod_dir = os.path.join(d, "mods", "test.hello")
            os.makedirs(mod_dir)
            path = write_entry_file(mod_dir)
            with open(path, encoding="utf-8") as f:
                e = json.load(f)
            e["versions"][0]["source_url"] = "https://example.invalid/x\x85y"
            with open(path, "w", encoding="utf-8") as f:
                json.dump(e, f)
            doc = plan_pending.plan(d, "a" * 40, [], [])
            self.assertEqual([x["version_id"] for x in doc["build"]], ["test.hello@1.0.0"], doc)
            self.assertEqual(doc["fault"], [])

    def test_parse_version_id_refuses_non_ascii_digits(self):
        for s in ("test.hello@1.0.1" + ARABIC, "test.hello@1.0.1\n", "test.hello@1.0.1\x85"):
            with self.subTest(value=s):
                with self.assertRaises(plan_pending.PlanInputError):
                    plan_pending.parse_version_id(s)
        self.assertEqual(plan_pending.parse_version_id("test.hello@1.0.1"), ("test", "hello", "1.0.1"))


# ------------------------------------------------------------------ the helper itself (the old digit-translator tests, moved)

def top_level_imports(source: str) -> set:
    out = set()
    for n in ast.walk(ast.parse(source)):
        if isinstance(n, ast.Import):
            out |= {a.name.split(".")[0] for a in n.names}
        elif isinstance(n, ast.ImportFrom) and n.module:
            out.add(n.module.split(".")[0])
    return out


FORBIDDEN = {"subprocess", "socket", "ssl", "urllib", "http", "requests", "ftplib", "smtplib", "asyncio", "multiprocessing"}


class Helper(unittest.TestCase):
    def test_escaped_backslash_is_not_mangled(self):
        # Moved from test_write_back.py's test_fix3_digit_translation_leaves_escaped_backslash_alone (the private digit translator is gone).
        # `\\d` is a literal backslash then a literal `d`; `\\\d` is a literal backslash then a digit.
        ecma = helper()
        cases = [(r"^\d$", "5", True), (r"^\d$", ARABIC, False), (r"^\\d$", "\\d", True), (r"^\\d$", "5", False),
                 (r"^\\\d$", "\\5", True), (r"^\\\d$", "\\" + ARABIC, False), (r"^\\\\d$", "\\\\d", True), (r"^\\\\d$", "\\5", False),
                 (r"^[\d.]$", "5", True), (r"^[\d.]$", ".", True), (r"^[\d.]$", ARABIC, False), (r"^[\d.]$", "x", False),
                 (r"^a\.b$", "a.b", True), (r"^a\.b$", "axb", False)]
        for pattern, value, want in cases:
            with self.subTest(pattern=pattern, value=value):
                self.assertIs(ecma.matches(pattern, value), want)

    def test_an_untranslatable_construct_propagates_not_implemented_error(self):
        # Moved from the `\D` raise test. `\D` inside a class is a construct the gate's translator refuses.
        ecma = helper()
        with self.assertRaises(NotImplementedError):
            ecma.matches(r"^[\D]$", "x")
        with self.assertRaises(NotImplementedError):
            ecma.matches(r"^[^\W]$", "x")
        for caller in (build_version._fullmatch, wb._fullmatch):
            with self.subTest(caller=caller.__module__):
                with self.assertRaises(NotImplementedError):
                    caller(r"^[\D]$", "x")
        with self.assertRaises(NotImplementedError):
            plan_pending._validate("x", {"type": "string", "pattern": r"^[\D]$"}, "$")

    def test_matches_is_the_gates_expression_search_not_fullmatch(self):
        ecma = helper()
        self.assertIs(ecma.matches("a", "xay"), True)           # re.search: an unanchored pattern finds a substring
        self.assertIs(ecma.matches("^a$", "a\n"), False)        # `$` is end of input only (ECMA-262)
        self.assertIs(ecma.matches("^a$", "a"), True)

    def test_a_non_string_value_never_matches(self):
        ecma = helper()
        for value in (None, 5, b"abc", ["abc"], True):
            with self.subTest(value=value):
                self.assertIs(ecma.matches("^abc$", value), False)

    def test_loading_the_gate_restores_the_bytecode_flag_and_the_shadowable_module_names(self):
        # F3: the load switches bytecode writing off while it runs and puts the caller's setting back; classify/report/schema_check
        # in sys.modules are the caller's own afterwards (present stays present and identical, absent stays absent).
        ecma = helper()
        names = ("classify", "report", "schema_check")
        before = {n: sys.modules.get(n) for n in names}
        original = sys.dont_write_bytecode
        try:
            for flag in (True, False):
                sys.dont_write_bytecode = flag
                module = ecma._load_gate_schema()
                self.assertIs(sys.dont_write_bytecode, flag)
                self.assertTrue(callable(module.ecma_pattern))
                self.assertEqual({n: sys.modules.get(n) for n in names}, before)
        finally:
            sys.dont_write_bytecode = original

    def test_write_back_has_no_private_digit_translator(self):
        # The name is built from two halves so that a grep for the removed function finds no hit in tests/ (criterion 6).
        self.assertFalse(hasattr(wb, "_ecma" + "_digits"))

    def test_helper_imports_neither_a_process_nor_a_network_library(self):
        with open(os.path.join(TOOLS, "ecma.py"), encoding="utf-8") as f:
            src = f.read()
        self.assertEqual(top_level_imports(src) & FORBIDDEN, set())
        self.assertNotIn("os.system", src)
        self.assertNotIn("os.popen", src)
        self.assertNotIn("re.ASCII", src)
        self.assertNotIn("except NotImplementedError", src)

    def test_positive_control_forbidden_import_is_detected(self):
        self.assertEqual(top_level_imports("import subprocess\nfrom urllib.request import urlopen\nimport os\n") & FORBIDDEN, {"subprocess", "urllib"})


if __name__ == "__main__":
    unittest.main()
