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
out = []
for name, inst in corpus:
    try:
        validate(inst, schema)
        verdict = "valid"
    except SchemaValidationError:
        verdict = "invalid"
    out.append({"name": name, "instance": inst, "python": verdict})
json.dump(out, sys.stdout)
