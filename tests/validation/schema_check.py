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
        if re.search(schema["pattern"], instance) is None:
            raise SchemaValidationError(path, f"{instance!r} does not match pattern {schema['pattern']!r}")

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
