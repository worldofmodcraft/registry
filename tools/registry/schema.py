r"""Schema validation of changed files (task 007a, edges E2 and E3).

Every changed JSON file is validated against the schema its path implies, using the repository's own
tests/contracts/schema_check.py (never a reimplementation): mods/<ns>.<name>/entry.json against
contracts/entry.schema.json, .../page.json against contracts/page.schema.json. A path with no implied
schema is a rejection (fail closed). A deleted file (value None) has nothing to validate here; the
append-only checker owns deletion.

End-of-input semantics (fix round 1, F1). schema_check matches patterns with `re.search`, and Python's `$`
(no MULTILINE) also matches just before a final "\n", so "a"*40+"\n" satisfies `^[0-9a-f]{40}$`. The contracts'
patterns follow ECMA-262, where `$` matches only at the very end of input. `validate()` below therefore runs
schema_check first and then re-checks every string pattern with each unescaped `$` outside a character class
rewritten to `\Z` (`ecma_pattern`). `re.fullmatch` alone would NOT be equivalent: it changes how unanchored
patterns (no end anchor at all) and for alternations, whereas the `\Z` rewrite alters exactly one thing:
where `$` may match. Fields with no `pattern` in the schema (`signature`, `key_id`: minLength only) are not
affected; see the task log, Questions. schema_check.py itself is shared and untouched; its
root-cause fix is a separate task. Duplicate JSON object keys in raw text are rejected (`loads_strict`), since
json.loads silently keeps the last one.

Input: {path: value}. value is the parsed document, a str of raw JSON text (parse failure is a
rejection, the PR's fault), or None for a file the PR deletes.
"""

import json
import re
import sys
from pathlib import Path

import classify
import report

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tests" / "contracts"))
import schema_check  # noqa: E402  (the repository's own validator; see module docstring)

class DuplicateKey(ValueError):
    pass


def _no_dups(pairs):
    keys = [k for k, _ in pairs]
    dup = sorted({k for k in keys if keys.count(k) > 1})
    if dup:
        raise DuplicateKey(f"duplicate object key(s) {dup}")
    return dict(pairs)


def loads_strict(text):
    """json.loads that raises DuplicateKey on a repeated object key (ValueError for bad syntax)."""
    return json.loads(text, object_pairs_hook=_no_dups)


# ECMA-262 -> Python pattern translation (task 064 and its amendment 1). No global re flag is used: a flag changes every
# escape at once (an ASCII-only flag made `\S` accept U+00A0). Each escape ECMA-262 defines differently is translated explicitly.
_WS = "\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff"  # ECMA WhiteSpace + LineTerminator
_OUTSIDE = {"d": "[0-9]", "D": "[^0-9]", "w": "[A-Za-z0-9_]", "W": "[^A-Za-z0-9_]", "s": "[" + _WS + "]", "S": "[^" + _WS + "]"}
_INSIDE = {"d": "0-9", "w": "A-Za-z0-9_", "s": _WS}
_DOT = "[^\\n\\r\\u2028\\u2029]"
_SAME_ESCAPES = set("nrtfv0xu")  # letter escapes with the same meaning in Python and ECMA-262
_SAME_GROUPS = ("(?:", "(?=", "(?!", "(?<=", "(?<!")


def ecma_pattern(pattern):
    r"""The pattern with ECMA-262 semantics spelled out for Python's `re` (used with search, never fullmatch).

    Unescaped `$` outside a class becomes `\Z` (ECMA `$` is end of input only); `.` and `\d \D \w \W \s \S` become explicit
    classes (in a class `\d \w \s` expand to ranges); a literal `[` inside a class is escaped. A construct whose meaning
    differs between Python and ECMA-262 and that is not translated raises NotImplementedError, never a silent pass."""
    def unsupported(why):
        raise NotImplementedError(f"pattern {pattern!r}: {why} (not translated to ECMA-262 semantics; extend the translator deliberately)")

    out, i, n, in_class = [], 0, len(pattern), False
    while i < n:
        c = pattern[i]
        if c == "\\":
            if i + 1 >= n:
                unsupported("dangling backslash")
            e = pattern[i + 1]
            if in_class and e in _INSIDE:
                out.append(_INSIDE[e])
            elif in_class and e in "DWS":
                unsupported(f"negated escape \\{e} inside a character class")
            elif in_class and e == "b":
                out.append("\\b")  # backspace in both
            elif not in_class and e in _OUTSIDE:
                out.append(_OUTSIDE[e])
            elif e.isalpha() and e not in _SAME_ESCAPES:
                unsupported(f"escape \\{e}")
            else:
                out.append(pattern[i:i + 2])
            i += 2
            continue
        if in_class:
            if c == "]":
                in_class = False
                out.append(c)
            else:
                out.append("\\[" if c == "[" else c)
            i += 1
            continue
        if c == "[":
            in_class = True
            out.append(c)
            i += 1
            if pattern[i:i + 1] == "^":
                out.append("^")
                i += 1
            if pattern[i:i + 1] == "]":
                unsupported("']' first in a character class (empty class in ECMA-262, a literal in Python)")
            continue
        if c == "(" and pattern[i + 1:i + 2] == "?" and not pattern.startswith(_SAME_GROUPS, i):
            unsupported("group construct")
        if c == ".":
            out.append(_DOT)
        elif c == "$":
            out.append("\\Z")
        else:
            out.append(c)
        i += 1
    if in_class:
        unsupported("unterminated character class")
    return "".join(out)


def _strict_patterns(instance, sub, path):
    if isinstance(instance, str) and "pattern" in sub:
        if re.search(ecma_pattern(sub["pattern"]), instance) is None:
            raise schema_check.SchemaValidationError(
                path, f"{instance!r} does not match pattern {sub['pattern']!r} at end of input "
                      "(a trailing newline is not accepted by `$`)")
    elif isinstance(instance, dict):
        for k, child in sub.get("properties", {}).items():
            if k in instance:
                _strict_patterns(instance[k], child, f"{path}.{k}")
    elif isinstance(instance, list) and isinstance(sub.get("items"), dict):
        for i, item in enumerate(instance):
            _strict_patterns(item, sub["items"], f"{path}[{i}]")


def validate(instance, sub):
    """schema_check.validate plus ECMA end-of-input pattern semantics. Raises like schema_check."""
    schema_check.validate(instance, sub)
    _strict_patterns(instance, sub, "$")


SCHEMA_FILES = {"entry": "entry.schema.json", "page": "page.schema.json"}


def load_schema(kind):
    return json.loads((REPO / "contracts" / SCHEMA_FILES[kind]).read_text())


def check(files):
    findings, results = [], []
    schemas = {}
    for path, value in files.items():
        parsed = classify.parse_mod_path(path)
        if parsed is None:
            findings.append(report.finding(
                ["no-schema"], f"path {path!r} implies no schema (only mods/<ns>.<name>/entry.json and "
                               "page.json are registry JSON files)",
                "remove the file from the PR or move it to a recognised path", "criterion 8: fails closed",
                path=path))
            continue
        kind = parsed[2]
        if value is None:
            results.append({"path": path, "schema": SCHEMA_FILES[kind], "result": "deleted-not-validated"})
            continue
        if isinstance(value, str):
            try:
                value = loads_strict(value)
            except DuplicateKey as exc:
                findings.append(report.finding(
                    ["duplicate-key"], f"{path} has {exc}", "keep each object key once; json parsers silently keep "
                    "only the last", "E2/E3: the file must be unambiguous", path=path))
                continue
            except ValueError as exc:
                findings.append(report.finding(
                    ["json-syntax"], f"{path} is not valid JSON ({exc})", "fix the JSON syntax",
                    "E2/E3: the file must parse", path=path))
                continue
        if kind not in schemas:
            schemas[kind] = load_schema(kind)
        try:
            validate(value, schemas[kind])
        except schema_check.SchemaValidationError as exc:
            edge = "E2 entry.schema.json" if kind == "entry" else "E3 page.schema.json"
            findings.append(report.finding(
                [f"schema:{kind}"], f"{path} violates {SCHEMA_FILES[kind]}: {exc}",
                f"edit the file so it validates against contracts/{SCHEMA_FILES[kind]}", edge, path=path))
            results.append({"path": path, "schema": SCHEMA_FILES[kind], "result": "invalid"})
            continue
        except NotImplementedError as exc:
            raise report.ToolError(f"schema_check cannot evaluate {SCHEMA_FILES[kind]}: {exc}") from exc
        results.append({"path": path, "schema": SCHEMA_FILES[kind], "result": "valid"})
    return report.make("schema", findings, results=results)
