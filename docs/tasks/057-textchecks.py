#!/usr/bin/env python3
"""Text checks on the contract prose for task 057 (criteria 2 and 7).

  python3 -I docs/tasks/057-textchecks.py [--rules FILE] [--schema FILE] [--readme FILE]
  python3 -I docs/tasks/057-textchecks.py --old-present --rules FILE    positive control: every OLD sentence must be FOUND (run on the pre-change blob)
  python3 -I docs/tasks/057-textchecks.py --bless                       rewrite 057-pinned-sections.json from the current rules file

--readme: the default (docs/contracts/README.md in the working copy) is for live use. 057-verify.sh passes the README blob AT
057's pinned FINAL commit, because the "README names task 057" check measures 057's own change (task 089a2, finding 6).
Exit code = number of failed checks. Text is normalised (markdown bold removed, whitespace collapsed)
before matching so line wrapping does not matter; wording does. Sentences are pinned by FULL text.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PINS = HERE / "057-pinned-sections.json"


def norm(s):
    s = s.replace("**", "")
    return re.sub(r"\s+", " ", s).strip()


# Sentences that must NO LONGER appear (the edit map's old anchors), by id.
OLD_RULES = {
    "rule1-one-exception": "with exactly one permitted exception: the takedown transition",
    "rule1-two-branch": "This is a two-branch mechanism (unchanged, or takedown)",
    "rule2-born-removed": 'any newly added element whose `status` is `"removed"` must carry a `reason`',
    "rule2-creation-removed": 'any element whose `status` is `"removed"` must carry a `reason`',
    "rule2-cannot-express": "cannot express this conditional requirement",
    "heading-one-permitted": "The one permitted in-place mutation",
    "only-status-transition": "This is the only status transition this document permits on an existing element",
    "outside-versions": "and the one takedown transition below",
    "one-permitted-phrase": "one permitted in-place mutation",
    "creation-pairing": "A first publish is not exempt from the status-and-reason pairing ADR-0041 requires.",
}
OLD_SCHEMA = {
    "schema-nine-field": "required-9-field",
    "schema-starts-published": 'a version starts "published"',
    "schema-single-published": "Every element is a single published version",
    "schema-absent-until": "absent until the pipeline runs",
    "schema-no-conditional": "does not enforce that conditional requirement",
    "schema-yanked-comment": "one of 'published' or 'removed'",
}

# Full sentences that must appear (new contract text), by id.
REQUIRED = {
    "born-pending": "Every newly appended element must be `pending` and carry exactly the four keys `version`, `commit`, `source_url` and `status`.",
    "fail-closed": "Until `ownership.md` carries the pipeline-identity carve-out for T1 and T3, a checker implementing T1 or T3 must reject every PR that contains a T1 or T3 mutation, whoever authors it.",
    "t1-exactly-once": 'T1 happens exactly once, by structure: it requires `old.versions[i].status == "pending"`, and a `pending` element has none of the five pipeline-written fields. After T1 the element is `published`, and a `published` element is covered by plain deep-equality under rule 1 (or by T2), so the five fields can never be written a second time.',
    "t1-condition-4": "`new.versions[i]` has exactly the nine keys of the `published` row of the shape table, so no key outside them, and in particular no `reason` and no `build_log_url`.",
    "t3-condition-4": "`new.versions[i]` has exactly the keys of the `rejected` row of the shape table: none of the five pipeline-written fields of T1, and nothing else.",
    "t3-terminal": "`rejected` is terminal and one-way: `rejected -> anything` is a violation of rule 1, and so is `rejected -> rejected` with any change, `reason` included.",
    "t2-only-from-published": "From an element whose old status is `published`, this document permits exactly one status transition: T2.",
    "authority-not-defined": "Authority for T1 and T3 is therefore not defined by this document.",
    "shape-legal-mixed": "A PR holding a T1 on one version and a T2 or T3 on another is shape-legal.",
    "rule1-four-branch": "with exactly three permitted exceptions: the transitions T1, T2 and T3 defined in \"The permitted in-place mutations\" below.",
}
REQUIRED_SCHEMA = {
    "schema-four-branches": None,  # structural, checked below
}
SECTIONS = {
    "T1": r"#### T1: ",
    "T3": r"#### T3: ",
    "COEXISTENCE": r"#### Coexistence of T1, T2 and T3",
    "ATTACKS": r"#### Attack attempts",
}


def section(text, start_re):
    """Text of the section whose heading line starts with start_re, up to the next heading of level <= 4."""
    m = re.search(r"(?m)^" + start_re + r".*$", text)
    if not m:
        return None
    rest = text[m.start():]
    nxt = re.search(r"(?m)^#{1,4} ", rest[len(m.group(0)):])
    body = rest if not nxt else rest[: len(m.group(0)) + nxt.start()]
    return norm(body)


def main(argv):
    def arg(name, default):
        return Path(argv[argv.index(name) + 1]) if name in argv else REPO / default

    rules_p = arg("--rules", "contracts/append-only.rules.md")
    schema_p = arg("--schema", "contracts/entry.schema.json")
    readme_p = arg("--readme", "docs/contracts/README.md")
    raw = rules_p.read_text()
    text = norm(raw)

    if "--bless" in argv:
        pins = {k: section(raw, v) for k, v in SECTIONS.items()}
        missing = [k for k, v in pins.items() if v is None]
        if missing:
            print(f"cannot bless, sections missing: {missing}", file=sys.stderr)
            return 1
        PINS.write_text(json.dumps(pins, indent=1) + "\n")
        print(f"blessed {sorted(pins)} -> {PINS.name}")
        return 0

    fails = 0

    def report(ok, cid, msg):
        nonlocal fails
        print(("PASS  " if ok else "FAIL  ") + f"{cid}: {msg}")
        if not ok:
            fails += 1

    if "--old-present" in argv:
        for cid, s in OLD_RULES.items():
            report(norm(s) in text, f"old-present/{cid}", "old sentence is FOUND in this (pre-change) file")
        hits0 = re.findall(r"one permitted|only status transition", text)
        report(len(hits0) > 0, "old-present/grep-zero", f"the grep pattern finds {len(hits0)} hit(s) in the pre-change file (positive control)")
        if "--schema" in argv:
            sch0 = json.loads(schema_p.read_text())
            strs = []

            def w0(o):
                if isinstance(o, str):
                    strs.append(o)
                elif isinstance(o, dict):
                    [w0(v) for v in o.values()]
                elif isinstance(o, list):
                    [w0(v) for v in o]

            w0(sch0)
            st = norm(" ".join(strs))
            for cid, s_ in OLD_SCHEMA.items():
                if cid != "schema-yanked-comment":
                    report(norm(s_) in st, f"old-present/{cid}", "old phrase is FOUND in this (pre-change) schema")
        return fails

    for cid, s in OLD_RULES.items():
        report(norm(s) not in text, f"old-gone/{cid}", "old sentence no longer appears in append-only.rules.md")
    hits = re.findall(r"one permitted|only status transition", text)
    report(not hits, "old-gone/grep-zero", f'grep "one permitted\\|only status transition" returns zero (found {len(hits)})')
    for cid, s in REQUIRED.items():
        report(norm(s) in text, f"required/{cid}", "full sentence present")

    pins = json.loads(PINS.read_text()) if PINS.exists() else {}
    for k, v in SECTIONS.items():
        got = section(raw, v)
        if got is None:
            report(False, f"pinned/{k}", "section heading not found")
        elif k not in pins:
            report(False, f"pinned/{k}", "no pin recorded")
        else:
            report(got == pins[k], f"pinned/{k}", "section text equals its full-text pin (a tail-append or edit turns this red)")

    sch = json.loads(schema_p.read_text())
    strings = []

    def walk(o):
        if isinstance(o, str):
            strings.append(o)
        elif isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(sch)
    schema_text = norm(" ".join(strings))
    for cid, s_ in OLD_SCHEMA.items():
        if cid != "schema-yanked-comment":
            report(norm(s_) not in schema_text, f"old-gone/{cid}", "old phrase no longer appears in the text of entry.schema.json")
    ex = REPO / "contracts/examples/entry/invalid/status-not-in-enum.json"
    report("one of 'published' or 'removed'" not in ex.read_text(), "old-gone/schema-yanked-comment", "status-not-in-enum.json _comment updated")
    item = sch["properties"]["versions"]["items"]
    branches = item.get("oneOf", [])
    st = [b.get("properties", {}).get("status", {}).get("enum") for b in branches]
    report(st == [["pending"], ["published"], ["removed"], ["rejected"]], "required/schema-four-branches", f"oneOf has four branches, one per status (got {st})")
    report("required" not in item, "required/schema-no-item-required-nine", "item-level `required` list of nine is gone")
    report(item["properties"]["status"]["enum"] == ["pending", "published", "removed", "rejected"], "required/schema-status-enum", "status enum is the four states")
    report(item["properties"].get("build_log_url", {}).get("pattern") == r"^https://\S+$", "required/schema-build-log-url", "build_log_url pattern is ^https://\\S+$")
    readme = norm(readme_p.read_text())
    report("task 057" in readme.lower(), "required/readme-names-057", "docs/contracts/README.md names task 057")
    return fails


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
