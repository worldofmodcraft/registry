"""Schema validation of changed files (task 007a, edges E2 and E3).

Every changed JSON file is validated against the schema its path implies, using the repository's own
tests/contracts/schema_check.py (never a reimplementation): mods/<ns>.<name>/entry.json against
contracts/entry.schema.json, .../page.json against contracts/page.schema.json. A path with no implied
schema is a rejection (fail closed). A deleted file (value None) has nothing to validate here; the
append-only checker owns deletion.

Input: {path: value}. value is the parsed document, a str of raw JSON text (parse failure is a
rejection, the PR's fault), or None for a file the PR deletes.
"""

import json
import sys
from pathlib import Path

import classify
import report

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tests" / "contracts"))
import schema_check  # noqa: E402  (the repository's own validator; see module docstring)

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
                value = json.loads(value)
            except ValueError as exc:
                findings.append(report.finding(
                    ["json-syntax"], f"{path} is not valid JSON ({exc})", "fix the JSON syntax",
                    "E2/E3: the file must parse", path=path))
                continue
        if kind not in schemas:
            schemas[kind] = load_schema(kind)
        try:
            schema_check.validate(value, schemas[kind])
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
