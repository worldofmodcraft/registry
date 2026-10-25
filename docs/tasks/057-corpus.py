#!/usr/bin/env python3
"""Prints the entry corpus (task 057 criterion 4) as JSON, with this repository's own validator's verdict.

Corpus = every contracts/examples/entry/**/*.json `example` + every old/new entry of
docs/tasks/057-transition-fixtures.json (the shape cases). 057-ajv-check.mjs reads the same JSON
(instance only) and returns Ajv 2020 strict verdicts; 057-verify.sh compares the two.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "tests" / "contracts"))
from schema_check import SchemaValidationError, validate  # noqa: E402

schema = json.loads((REPO / "contracts" / "entry.schema.json").read_text())
corpus = []
for p in sorted((REPO / "contracts" / "examples" / "entry").rglob("*.json")):
    corpus.append((f"example:{p.parent.name}/{p.name}", json.loads(p.read_text())["example"]))
for fx in json.loads((HERE / "057-transition-fixtures.json").read_text()):
    for side in ("old", "new"):
        inst = fx.get(side)
        if inst is None and f"{side}_text" in fx:
            inst = json.loads(fx[f"{side}_text"])
        if inst is not None:
            corpus.append((f"fixture:{fx['name']}:{side}", inst))
# Task 064: pattern-semantics cases (ECMA-262 `$` = end of input only, `\d` = [0-9]) built from two valid examples.
# Each of the 8 patterns of entry.schema.json gets "valid value + newline"; each `\d` pattern gets one fullwidth digit.
import copy  # noqa: E402

_pub = json.loads((REPO / "contracts/examples/entry/valid/basic-github-single-version.json").read_text())["example"]
_rej = json.loads((REPO / "contracts/examples/entry/valid/rejected-version.json").read_text())["example"]


def _with(base, field, fn):
    inst = copy.deepcopy(base)
    if field == "id":
        inst["id"] = fn(inst["id"])
    else:
        v = next(x for x in inst["versions"] if field in x)
        v[field] = fn(v[field])
    return inst


for _field in ("id", "version", "commit", "source_url", "source_archive", "source_sha256", "published_at"):
    corpus.append((f"pattern064:newline:{_field}", _with(_pub, _field, lambda v: v + "\n")))
corpus.append(("pattern064:newline:build_log_url", _with(_rej, "build_log_url", lambda v: v + "\n")))
corpus.append(("pattern064:fullwidth:version", _with(_pub, "version", lambda v: "1０" + v[1:])))
corpus.append(("pattern064:fullwidth:published_at", _with(_pub, "published_at", lambda v: "２０" + v[2:])))
# Amendment 1: `\S` excludes Unicode WhiteSpace (U+00A0, U+2028) in ECMA-262.
corpus.append(("pattern064:nbsp:source_url", _with(_pub, "source_url", lambda v: v + "\u00a0x")))
corpus.append(("pattern064:u2028:source_archive", _with(_pub, "source_archive", lambda v: v + "\u2028x")))
out = []
for name, inst in corpus:
    try:
        validate(inst, schema)
        verdict = "valid"
    except SchemaValidationError:
        verdict = "invalid"
    out.append({"name": name, "instance": inst, "python": verdict})
json.dump(out, sys.stdout)
