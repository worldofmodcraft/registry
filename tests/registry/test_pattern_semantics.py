"""Task 064: every `pattern` check in the registry's validators agrees with ECMA-262 (and so with the site's Ajv)
on end of input (`$` matches only at the very end, never before a final "\\n") and on `\\d` (ASCII digits only).

Three pattern paths are covered: tests/contracts/schema_check.py, tests/validation/schema_check.py and the strict check
of tools/registry/schema.py (`_strict_patterns`, called directly so that the earlier schema_check pass inside
`schema.validate` cannot mask it). The two schema_check modules share a module name, so both are loaded by file path.

Run with:   python3 -m unittest discover -s tests/registry -v
"""

import importlib.util
import json
import unittest
from pathlib import Path

import support  # noqa: F401  (puts tools/registry and tests/contracts on sys.path)
import schema

REPO = Path(__file__).resolve().parents[2]


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


CONTRACTS_CHECK = _load("wom_contracts_schema_check", REPO / "tests" / "contracts" / "schema_check.py")
VALIDATION_CHECK = _load("wom_validation_schema_check", REPO / "tests" / "validation" / "schema_check.py")


def _strict(instance, sub):
    """The registry strict-pattern path on its own (raises the contracts SchemaValidationError)."""
    schema._strict_patterns(instance, sub, "$")


def _contracts(instance, sub):
    CONTRACTS_CHECK.validate(instance, sub)


def _validation(instance, sub):
    VALIDATION_CHECK.validate(instance, sub)


def _composite(instance, sub):
    schema.validate(instance, sub)


# (label, callable, exception raised on rejection)
PATHS = [
    ("tests/contracts/schema_check.py", _contracts, CONTRACTS_CHECK.SchemaValidationError),
    ("tests/validation/schema_check.py", _validation, VALIDATION_CHECK.SchemaValidationError),
    ("tools/registry/schema.py _strict_patterns", _strict, schema.schema_check.SchemaValidationError),
    ("tools/registry/schema.py validate", _composite, schema.schema_check.SchemaValidationError),
]

URL = "https://example.com/a"
# One valid sample per `pattern` key, keyed by "<schema file>#<JSON pointer>". Completeness is asserted below, so a
# new pattern added to a schema without a case here turns this suite red.
VALID = {
    "entry.schema.json#/properties/id": "kelsi:housing",
    "entry.schema.json#/properties/versions/items/properties/version": "1.2.3",
    "entry.schema.json#/properties/versions/items/properties/commit": "a" * 40,
    "entry.schema.json#/properties/versions/items/properties/source_url": "https://github.com/kelsi/housing",
    "entry.schema.json#/properties/versions/items/properties/source_archive": URL,
    "entry.schema.json#/properties/versions/items/properties/source_sha256": "b" * 64,
    "entry.schema.json#/properties/versions/items/properties/key_id": "E7A1B2C3D4E5F607",
    "entry.schema.json#/properties/versions/items/properties/published_at": "2026-10-15T09:00:00Z",
    "entry.schema.json#/properties/versions/items/properties/build_log_url": URL,
    "manifest.schema.json#/properties/id": "kelsi:housing",
    "manifest.schema.json#/properties/version": "1.2.3",
    "manifest.schema.json#/properties/source": "https://github.com/kelsi/housing",
    "manifest.schema.json#/properties/screenshots/items": "shots/one.png",
    "page.schema.json#/properties/screenshots/items": "shots/one.png",
    "page.schema.json#/properties/links/items/properties/url": URL,
    "validation-report.schema.json#/properties/schema_version": "1.0.0",
}
# Valid samples with one fullwidth digit swapped in (ECMA `\d` is ASCII-only), for the `\d` patterns only. The digit
# is non-leading in each component: the leading `[1-9]` of a semver component would reject it for the wrong reason.
FULLWIDTH = {
    "entry.schema.json#/properties/versions/items/properties/version": "1２.3.4",
    "entry.schema.json#/properties/versions/items/properties/published_at": "２０２６-10-15T09:00:00Z",
    "manifest.schema.json#/properties/version": "1.2.3４",
}


def _pattern_subschemas():
    found = {}

    def walk(node, pointer, fname):
        if isinstance(node, dict):
            if isinstance(node.get("pattern"), str):
                found[f"{fname}#{pointer}"] = node
            for k, v in node.items():
                walk(v, f"{pointer}/{k}", fname)
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{pointer}/{i}", fname)

    for f in sorted((REPO / "contracts").glob("*.schema.json")):
        walk(json.loads(f.read_text()), "", f.name)
    return found


SUBS = _pattern_subschemas()


class Completeness(unittest.TestCase):
    def test_every_pattern_key_in_contracts_has_a_valid_sample(self):
        # Protects: a new `pattern` cannot be added to contracts/ without a trailing-newline case here.
        self.assertEqual(sorted(SUBS), sorted(VALID))
        self.assertEqual(len(SUBS), 16)

    def test_every_pattern_with_backslash_d_has_a_fullwidth_case(self):
        # Protects: a `\d` pattern without a fullwidth-digit case would silently keep the Unicode-digit gap.
        with_d = sorted(k for k, s in SUBS.items() if "\\d" in s["pattern"])
        self.assertEqual(with_d, sorted(FULLWIDTH))


class ValidControls(unittest.TestCase):
    def test_valid_samples_are_accepted_by_every_path(self):
        # Protects: the fix must not reject what the schemas accept (positive control for the red cases).
        for key, sub in SUBS.items():
            for label, fn, _exc in PATHS:
                with self.subTest(pattern=key, path=label):
                    fn(VALID[key], sub)

    def test_samples_really_use_the_pattern_under_test(self):
        # Protects: the sample must satisfy the real pattern, so a rejection below is due to the defect, not the sample.
        import re
        for key, sub in SUBS.items():
            with self.subTest(pattern=key):
                self.assertIsNotNone(re.search(sub["pattern"], VALID[key]))


class TrailingNewline(unittest.TestCase):
    def test_valid_value_plus_newline_is_rejected_by_every_path(self):
        # Protects: ECMA `$` does not match before a final "\n"; Python's does (task 007a F1).
        for key, sub in SUBS.items():
            for label, fn, exc in PATHS:
                with self.subTest(pattern=key, path=label):
                    with self.assertRaises(exc):
                        fn(VALID[key] + "\n", sub)

    def test_valid_value_plus_two_newlines_is_rejected_by_every_path(self):
        # Protects: the rewrite is about end of input, not "one tolerated newline".
        for key, sub in SUBS.items():
            for label, fn, exc in PATHS:
                with self.subTest(pattern=key, path=label):
                    with self.assertRaises(exc):
                        fn(VALID[key] + "\n\n", sub)

    def test_the_f1_case_from_the_review(self):
        # Protects: the exact finding: a 40-hex commit plus "\n" against ^[0-9a-f]{40}$.
        sub = {"type": "string", "pattern": "^[0-9a-f]{40}$"}
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                fn("a" * 40, sub)
                with self.assertRaises(exc):
                    fn("a" * 40 + "\n", sub)


class RejectionMessage(unittest.TestCase):
    def test_message_names_the_ecma_reason_only_when_python_semantics_would_accept(self):
        # Protects: an author who hits the trailing-newline rule is told why; an ordinary mismatch gets no misleading hint.
        sub = {"type": "string", "pattern": "^[0-9a-f]{4}$"}
        for label, fn, exc in PATHS[:2]:
            with self.subTest(path=label):
                with self.assertRaises(exc) as ctx:
                    fn("abcd\n", sub)
                self.assertIn("end of input", ctx.exception.message)
                with self.assertRaises(exc) as ctx:
                    fn("zzzz", sub)
                self.assertNotIn("ECMA", ctx.exception.message)


class FullwidthDigits(unittest.TestCase):
    def test_one_fullwidth_digit_is_rejected_by_every_path(self):
        # Protects: ECMA `\d` is [0-9]; Python's str `\d` accepts Unicode digits (task 007a N1).
        for key, bad in FULLWIDTH.items():
            for label, fn, exc in PATHS:
                with self.subTest(pattern=key, path=label):
                    with self.assertRaises(exc):
                        fn(bad, SUBS[key])

    def test_arabic_indic_and_fullwidth_digits_in_a_synthetic_pattern(self):
        # Protects: the ASCII flag acts on the compiled pattern for any Unicode decimal digit, not one hand-picked char.
        sub = {"type": "string", "pattern": "^\\d+$"}
        for label, fn, exc in PATHS:
            for bad in ("１２", "١٢", "1２"):
                with self.subTest(path=label, value=bad):
                    with self.assertRaises(exc):
                        fn(bad, sub)
            with self.subTest(path=label, value="12"):
                fn("12", sub)


class SearchSemanticsKept(unittest.TestCase):
    def test_unanchored_pattern_still_matches_mid_string(self):
        # Protects: criterion 2 positive control; re.fullmatch would reject this (034 C3.4 forbids it).
        sub = {"type": "string", "pattern": "b+"}
        for label, fn, _exc in PATHS:
            with self.subTest(path=label):
                fn("abbc", sub)

    def test_end_anchor_only_pattern_still_matches_a_suffix(self):
        # Protects: `\Z` replaces `$` and nothing else; a suffix match under search semantics is unchanged.
        sub = {"type": "string", "pattern": "c$"}
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                fn("abc", sub)
                with self.assertRaises(exc):
                    fn("abc\n", sub)

    def test_alternation_with_end_anchor_keeps_search_semantics(self):
        # Protects: re.fullmatch would change alternations; `a|b$` under search matches "a" mid-string.
        sub = {"type": "string", "pattern": "a|b$"}
        for label, fn, _exc in PATHS:
            with self.subTest(path=label):
                fn("xay", sub)

    def test_dollar_inside_class_or_escaped_is_literal_not_end_anchor(self):
        # Protects: the rewrite touches only an unescaped `$` outside a character class.
        for pattern, good, bad in (("^a[$]$", "a$", "a"), ("^a\\$$", "a$", "a"), ("^[a$]+$", "a$a", "a$\n")):
            sub = {"type": "string", "pattern": pattern}
            for label, fn, exc in PATHS:
                with self.subTest(pattern=pattern, path=label):
                    fn(good, sub)
                    with self.assertRaises(exc):
                        fn(bad, sub)

    def test_interior_newline_with_dot_star_is_still_judged_by_the_pattern(self):
        # Protects: no MULTILINE creep: `^a$` does not match "a\nb" anywhere.
        sub = {"type": "string", "pattern": "^a$"}
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                with self.assertRaises(exc):
                    fn("a\nb", sub)


class NonStringInstances(unittest.TestCase):
    def test_non_strings_are_not_pattern_checked_by_the_strict_path(self):
        # Protects: the ASCII/`\Z` change cannot make a pattern run against ints/None (type errors are the type check's job).
        sub = {"pattern": "^[0-9]+$"}
        for label, fn, _exc in PATHS:
            with self.subTest(path=label):
                fn(12, sub)
                fn(None, sub)


TRANSLATORS = [
    ("tests/contracts/schema_check.py", CONTRACTS_CHECK._ecma_pattern),
    ("tests/validation/schema_check.py", VALIDATION_CHECK._ecma_pattern),
    ("tools/registry/schema.py", schema.ecma_pattern),
]


def _accepts(fn, exc, pattern, value):
    """True if the validator path accepts `value` for `pattern`."""
    try:
        fn(value, {"type": "string", "pattern": pattern})
        return True
    except exc:
        return False


class EscapeTranslation(unittest.TestCase):
    """Amendment 1: no re.ASCII; each ECMA-262 escape is translated explicitly, so `\\S` and `.` keep ECMA meaning."""

    def test_backslash_s_rejects_unicode_whitespace(self):
        # Protects: ECMA `\S` excludes U+00A0 and the other WhiteSpace code points (the regression a global re.ASCII caused).
        sub = {"type": "string", "pattern": "^https://\\S+$"}
        for label, fn, exc in PATHS:
            for ws in (" ", " ", "　", "﻿", " ", " "):
                with self.subTest(path=label, ws=hex(ord(ws))):
                    with self.assertRaises(exc):
                        fn("https://a" + ws + "b", sub)

    def test_backslash_s_still_accepts_non_ascii_visible_characters(self):
        # Protects: positive control; ECMA `\S` matches "é" and CJK, so the translation must not narrow it to ASCII.
        sub = {"type": "string", "pattern": "^https://\\S+$"}
        for label, fn, _exc in PATHS:
            with self.subTest(path=label):
                fn("https://exämple.com/日本", sub)
                fn("https://a​b", sub)  # U+200B is not WhiteSpace in ECMA-262

    def test_dot_rejects_cr_and_line_separators_but_accepts_other_characters(self):
        # Protects: ECMA `.` excludes \n \r U+2028 U+2029 (Python's excludes only \n); anything else still matches.
        sub = {"type": "string", "pattern": "^(?!/).+$"}
        for label, fn, exc in PATHS:
            for bad in ("a\rb", "a b", "a b", "a\nb", "\r"):
                with self.subTest(path=label, bad=repr(bad)):
                    with self.assertRaises(exc):
                        fn(bad, sub)
            for good in ("shots/é.png", "a\x85b", "a b"):
                with self.subTest(path=label, good=repr(good)):
                    fn(good, sub)

    def test_dot_translation_in_a_simple_pattern(self):
        # Protects: `.` handling outside lookaheads, with quantifiers.
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                self.assertTrue(_accepts(fn, exc, "^a.c$", "abc"))
                self.assertFalse(_accepts(fn, exc, "^a.c$", "a\rc"))
                self.assertTrue(_accepts(fn, exc, "^a[.]c$", "a.c"))
                self.assertFalse(_accepts(fn, exc, "^a[.]c$", "abc"))
                self.assertTrue(_accepts(fn, exc, "^a\\.c$", "a.c"))
                self.assertFalse(_accepts(fn, exc, "^a\\.c$", "abc"))

    def test_word_and_negated_escapes(self):
        # Protects: `\w` is [A-Za-z0-9_], `\W` and `\D` are their exact complements (Unicode letters/digits are \W / \D).
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                self.assertTrue(_accepts(fn, exc, "^\\w+$", "aZ_09"))
                self.assertFalse(_accepts(fn, exc, "^\\w+$", "café"))
                self.assertTrue(_accepts(fn, exc, "^\\W$", "é"))
                self.assertFalse(_accepts(fn, exc, "^\\W$", "a"))
                self.assertTrue(_accepts(fn, exc, "^\\D$", "５"))
                self.assertFalse(_accepts(fn, exc, "^\\D$", "5"))

    def test_whitespace_escape_is_the_ecma_set(self):
        # Protects: `\s` includes U+FEFF and U+00A0 (ECMA) and excludes U+0085 (NEL), which Python's `\s` includes.
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                for ws in (" ", "\t", "\n", "\v", "\f", "\r", " ", "﻿", " ", " ", "　", " "):
                    self.assertTrue(_accepts(fn, exc, "^\\s$", ws), hex(ord(ws)))
                    self.assertFalse(_accepts(fn, exc, "^\\S$", ws), hex(ord(ws)))
                for notws in ("\x85", "​", "a", "᠎"):
                    self.assertFalse(_accepts(fn, exc, "^\\s$", notws), hex(ord(notws)))
                    self.assertTrue(_accepts(fn, exc, "^\\S$", notws), hex(ord(notws)))

    def test_escapes_inside_character_classes_expand_to_ranges(self):
        # Protects: `[\d]`, `[\w]`, `[\s]` carry ECMA meaning inside a class, next to other members.
        for label, fn, exc in PATHS:
            with self.subTest(path=label):
                self.assertTrue(_accepts(fn, exc, "^[\\d.]+$", "1.5"))
                self.assertFalse(_accepts(fn, exc, "^[\\d.]+$", "１.5"))
                self.assertTrue(_accepts(fn, exc, "^[\\w-]+$", "a-b_1"))
                self.assertFalse(_accepts(fn, exc, "^[\\w-]+$", "é"))
                self.assertTrue(_accepts(fn, exc, "^[\\s,]+$", " ,﻿"))
                self.assertFalse(_accepts(fn, exc, "^[\\s,]+$", "\x85"))
                self.assertTrue(_accepts(fn, exc, "^[^\\d]$", "１"))
                self.assertFalse(_accepts(fn, exc, "^[^\\d]$", "1"))

    def test_unsupported_constructs_raise_not_silently_pass(self):
        # Protects: a construct whose meaning differs between Python and ECMA-262 is an explicit error, never a guess.
        cases = (
            "^[\\D]$", "^[\\W]$", "^[\\S]$",  # negated escape inside a class
            "^\\b$", "^a\\B$",  # \b / \B use Unicode \w in Python
            "^\\A$", "^a\\Z",  # Python-only anchors (literal letters in ECMA)
            "^(?P<n>a)$", "^(?<n>a)$", "^(?i)a$", "^(?#c)a$",  # named groups / inline flags / comments
            "^[]a]$", "^[^]a]$",  # empty class vs literal ] first
            "^\\cA$", "^\\k<n>$",  # control escape, named backref
        )
        for label, fn in TRANSLATORS:
            for pattern in cases:
                with self.subTest(translator=label, pattern=pattern):
                    with self.assertRaises(NotImplementedError):
                        fn(pattern)
        for label, fn, _exc in PATHS[:2]:
            with self.subTest(path=label):
                with self.assertRaises(NotImplementedError):
                    fn("a", {"type": "string", "pattern": "^[\\D]$"})

    def test_supported_constructs_pass_through_unchanged_except_the_translations(self):
        # Protects: groups, lookarounds, quantifiers, escaped punctuation and `\$` / `[$]` keep their text.
        for label, fn in TRANSLATORS:
            with self.subTest(translator=label):
                for same in ("^(?:a|b)+?$".replace("$", "\\$"), "(?=a)(?!b)(?<=c)(?<!d)e{2,3}", "^a\\.b\\/c\\-d\\\\e", "[a-c\\]]", "[$]"):
                    self.assertEqual(fn(same), same)
                self.assertEqual(fn("^a$"), "^a\\Z")
                self.assertEqual(fn("\\d"), "[0-9]")
                self.assertEqual(fn("[\\d]"), "[0-9]")

    def test_no_re_ascii_flag_remains_in_any_pattern_path(self):
        # Protects: Amendment 1; a global flag would change `\S`, `\s`, `\w` behaviour that is translated explicitly.
        for rel in ("tests/contracts/schema_check.py", "tests/validation/schema_check.py", "tools/registry/schema.py"):
            with self.subTest(file=rel):
                text = (REPO / rel).read_text()
                self.assertNotIn("re.ASCII", text)

    def test_rejection_message_names_the_ecma_reason_for_translated_cases(self):
        # Protects: the accepted message deviation holds for `.`/`\S` rejections too, not only for a trailing newline.
        for label, fn, exc in PATHS[:2]:
            with self.subTest(path=label):
                with self.assertRaises(exc) as ctx:
                    fn("https://a b", {"type": "string", "pattern": "^https://\\S+$"})
                self.assertIn("end of input", ctx.exception.message)
                self.assertIn("ECMA-262", ctx.exception.message)


if __name__ == "__main__":
    unittest.main()
