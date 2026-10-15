"""A tiny, stdlib-only JSON Schema (draft 2020-12) subset validator.

Mirrors the approach of tests/validation/schema_check.py (task 002): no
`jsonschema` package is installed in this environment and this task's tests
must stay offline and dependency-free (ADR-0103, acceptance criterion 8). This
is a separate copy rather than an import of task 002's module, because this
repository's tests directory is organised per-task (tests/validation/ is task
002's declared scope, tests/contracts/ is this task's) and because this
schema set needs a few keywords task 002's contract never used: `enum`,
`minLength`, `maxLength` and `minItems`. Adding them here, deliberately, is
schema *tooling* to make the contracts self-checking -- not the checking
*logic* task 007 is responsible for (no diffing, no ownership check, no
append-only enforcement lives in this file).

Like task 002's version, this is deliberately not a general-purpose
validator: an unsupported keyword is a visible NotImplementedError, never a
silent pass, and every `pattern` in this repository's schemas is written
anchored (`^...$`) because this validator matches with `re.search`, not
`re.fullmatch`.
"""

from __future__ import annotations

import re
from typing import Any


# ECMA-262 -> Python pattern translation (task 064 and its amendment 1). No global re flag is used: a flag changes every
# escape at once (an ASCII-only flag made `\S` accept U+00A0). Each escape ECMA-262 defines differently is translated explicitly.
_WS = "\\t\\n\\v\\f\\r \\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff"  # ECMA WhiteSpace + LineTerminator
_OUTSIDE = {"d": "[0-9]", "D": "[^0-9]", "w": "[A-Za-z0-9_]", "W": "[^A-Za-z0-9_]", "s": "[" + _WS + "]", "S": "[^" + _WS + "]"}
_INSIDE = {"d": "0-9", "w": "A-Za-z0-9_", "s": _WS}
_DOT = "[^\\n\\r\\u2028\\u2029]"
_SAME_ESCAPES = set("nrtfv0xu")  # letter escapes with the same meaning in Python and ECMA-262
_SAME_GROUPS = ("(?:", "(?=", "(?!", "(?<=", "(?<!")


def _ecma_pattern(pattern):
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


class SchemaValidationError(Exception):
    def __init__(self, path: str, message: str):
        super().__init__(f"{path}: {message}")
        self.path = path
        self.message = message


_PY_TYPE_FOR_JSON_TYPE = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "null": type(None),
}

_SUPPORTED_KEYWORDS = {
    "type",
    "pattern",
    "minimum",
    "minLength",
    "maxLength",
    "minItems",
    "enum",
    "required",
    "properties",
    "additionalProperties",
    "items",
    "oneOf",
    # Annotation-only keywords: never change validation outcome, only
    # documentation. Explicitly listed so an unrecognised keyword still
    # fails loudly rather than being confused with one of these.
    "$schema",
    "$id",
    "$comment",
    "title",
    "description",
}


def _check_type(instance: Any, json_type: str, path: str) -> None:
    if json_type == "integer":
        # bool is a subclass of int in Python; a JSON boolean must never
        # satisfy an "integer" schema.
        if isinstance(instance, bool) or not isinstance(instance, int):
            raise SchemaValidationError(path, f"expected integer, got {type(instance).__name__}: {instance!r}")
        return
    if json_type == "number":
        if isinstance(instance, bool) or not isinstance(instance, (int, float)):
            raise SchemaValidationError(path, f"expected number, got {type(instance).__name__}: {instance!r}")
        return
    py_type = _PY_TYPE_FOR_JSON_TYPE.get(json_type)
    if py_type is None:
        raise NotImplementedError(f"schema_check does not support JSON type {json_type!r}")
    if not isinstance(instance, py_type):
        raise SchemaValidationError(path, f"expected {json_type}, got {type(instance).__name__}: {instance!r}")


def _assert_supported(schema: dict, path: str) -> None:
    unknown = set(schema.keys()) - _SUPPORTED_KEYWORDS
    if unknown:
        raise NotImplementedError(
            f"{path}: schema_check does not support keyword(s) {sorted(unknown)} "
            "-- extend this validator deliberately rather than let it silently ignore them"
        )


def validate(instance: Any, schema: dict, path: str = "$") -> None:
    """Raise SchemaValidationError on the first violation found; return None if
    `instance` satisfies `schema` (the supported subset of it)."""
    _assert_supported(schema, path)

    if "type" in schema:
        types = schema["type"]
        types = types if isinstance(types, list) else [types]
        errors = []
        matched = False
        for t in types:
            try:
                _check_type(instance, t, path)
                matched = True
                break
            except SchemaValidationError as exc:
                errors.append(str(exc))
        if not matched:
            raise SchemaValidationError(path, f"matched none of {types}: {'; '.join(errors)}")

    if "enum" in schema:
        if instance not in schema["enum"]:
            raise SchemaValidationError(path, f"{instance!r} is not one of the {len(schema['enum'])} allowed enum values")

    if "pattern" in schema and isinstance(instance, str):
        if re.search(_ecma_pattern(schema["pattern"]), instance) is None:
            # Name the ECMA-262 difference when Python's own semantics would have accepted the value (task 064; the
            # 007a hardening tests pin the phrase "end of input" in the message a trailing newline produces).
            hint = ""
            if re.search(schema["pattern"], instance) is not None or not instance.isascii() or "\r" in instance or "\n" in instance:
                hint = " (rejected under ECMA-262 semantics: `$` is end of input only, `\\d` is [0-9])"
            raise SchemaValidationError(path, f"{instance!r} does not match pattern {schema['pattern']!r}{hint}")

    if "minLength" in schema and isinstance(instance, str):
        if len(instance) < schema["minLength"]:
            raise SchemaValidationError(path, f"length {len(instance)} is below minLength {schema['minLength']!r}")

    if "maxLength" in schema and isinstance(instance, str):
        if len(instance) > schema["maxLength"]:
            raise SchemaValidationError(path, f"length {len(instance)} exceeds maxLength {schema['maxLength']!r}")

    if "minimum" in schema and isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if instance < schema["minimum"]:
            raise SchemaValidationError(path, f"{instance!r} is below minimum {schema['minimum']!r}")

    if "minItems" in schema and isinstance(instance, list):
        if len(instance) < schema["minItems"]:
            raise SchemaValidationError(path, f"length {len(instance)} is below minItems {schema['minItems']!r}")

    if isinstance(instance, dict) and schema.get("type") in ("object", None) and (
        "properties" in schema or "required" in schema or "additionalProperties" in schema
    ):
        properties = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in instance:
                raise SchemaValidationError(path, f"missing required property {req!r}")
        if schema.get("additionalProperties") is False:
            allowed = set(properties.keys())
            extra = set(instance.keys()) - allowed
            if extra:
                raise SchemaValidationError(path, f"unexpected propert{'y' if len(extra)==1 else 'ies'}: {sorted(extra)}")
        for key, subschema in properties.items():
            if key in instance:
                validate(instance[key], subschema, f"{path}.{key}")
        if isinstance(schema.get("additionalProperties"), dict):
            allowed = set(properties.keys())
            for key in set(instance.keys()) - allowed:
                validate(instance[key], schema["additionalProperties"], f"{path}.{key}")

    if "oneOf" in schema:
        # Task 057: exactly one branch must match. Zero matches and two or more matches
        # are both failures (never "first match wins"). Branches may use only the keywords
        # supported above; an unsupported keyword inside a branch still raises
        # NotImplementedError rather than counting as a non-match.
        matched, errors = [], []
        for index, branch in enumerate(schema["oneOf"]):
            try:
                validate(instance, branch, path)
                matched.append(index)
            except SchemaValidationError as exc:
                errors.append(f"branch {index}: {exc.message}")
        if len(matched) != 1:
            if not matched:
                raise SchemaValidationError(path, "matched none of the oneOf branches: " + "; ".join(errors))
            raise SchemaValidationError(path, f"matched {len(matched)} oneOf branches {matched}, exactly one is required")

    if isinstance(instance, list) and "items" in schema:
        for i, item in enumerate(instance):
            validate(item, schema["items"], f"{path}[{i}]")
