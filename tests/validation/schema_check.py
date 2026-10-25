"""A tiny, stdlib-only JSON Schema (draft 2020-12) subset validator.

No `jsonschema` package is installed in this environment and the task's runtime
must stay offline and dependency-free (ADR-0103: boring, predictable; no pip
install at test time). This module implements exactly the subset of JSON Schema
that contracts/validation-report.schema.json actually uses: `type` (including
union types via a list, e.g. ["integer", "null"]), `required`, `properties`,
`additionalProperties` (boolean form only), `items`, `pattern`, and `minimum`.
It is deliberately not a general-purpose validator -- if the contract ever needs
a keyword this does not support, that is a visible NotImplementedError, never a
silent pass.
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


def _check_type(instance: Any, json_type: str, path: str) -> None:
    if json_type == "integer":
        # bool is a subclass of int in Python; a JSON boolean must never satisfy
        # an "integer" schema.
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


def validate(instance: Any, schema: dict, path: str = "$") -> None:
    """Raise SchemaValidationError on the first violation found; return None if
    `instance` satisfies `schema` (the supported subset of it)."""
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

    if "pattern" in schema and isinstance(instance, str):
        if re.search(_ecma_pattern(schema["pattern"]), instance) is None:
            # Name the ECMA-262 difference when Python's own semantics would have accepted the value (task 064; the
            # 007a hardening tests pin the phrase "end of input" in the message a trailing newline produces).
            hint = ""
            if re.search(schema["pattern"], instance) is not None or not instance.isascii() or "\r" in instance or "\n" in instance:
                hint = " (rejected under ECMA-262 semantics: `$` is end of input only, `\\d` is [0-9])"
            raise SchemaValidationError(path, f"{instance!r} does not match pattern {schema['pattern']!r}{hint}")

    if "minimum" in schema and isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if instance < schema["minimum"]:
            raise SchemaValidationError(path, f"{instance!r} is below minimum {schema['minimum']!r}")

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

    if isinstance(instance, list) and "items" in schema:
        for i, item in enumerate(instance):
            validate(item, schema["items"], f"{path}[{i}]")
