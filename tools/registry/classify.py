"""PR classification (task 007a, ADR-0059 Section 3, ownership.md R1/I4, criterion 8).

Given the set of paths a PR changes, decide which of the registry's PR shapes it is. Exactly one class:

    "entry"               at least one mods/<ns>.<name>/entry.json, no reserved namespace
    "page-only"           only mods/<ns>.<name>/page.json paths (the lighter ADR-0059 Section 3 gate)
    "reserved-namespace"  touches a namespace on the reserved list (ADR-0119); takes precedence
    "other"               anything else; ALWAYS a rejection (fail closed)

Rules owned here: ownership.md R1 (path form). Any path under mods/ that is not exactly
mods/<namespace>.<name>/entry.json or .../page.json, with <namespace> and <name> each matching
[a-z0-9][a-z0-9_-]*, is rejected citing R1 -- never skipped. Any path outside mods/ is unrecognised and
also rejected: this checker knows no other kind of registry PR, and an unknown shape must never pass.
A mixed page.json + entry.json PR is class "entry", never "page-only".

The reserved list is DATA the caller passes in (the parsed reserved-namespaces.json as it stood at the
PR's MERGE-BASE, ownership.md I4). This module never reads the PR's own copy, so a PR that edits that
file cannot change its own classification.
"""

import re

import report

PATH_RE = re.compile(r"mods/([a-z0-9][a-z0-9_-]*)\.([a-z0-9][a-z0-9_-]*)/(entry|page)\.json")

CLASS_ENTRY = "entry"
CLASS_PAGE = "page-only"
CLASS_RESERVED = "reserved-namespace"
CLASS_OTHER = "other"


def parse_mod_path(path):
    """(namespace, name, kind) with kind 'entry' or 'page', or None if the path is not of the R1 form."""
    m = PATH_RE.fullmatch(path) if isinstance(path, str) else None
    return m.groups() if m else None


def reserved_names(reserved):
    """Names on the reserved list from the parsed merge-base reserved-namespaces.json."""
    if not isinstance(reserved, dict) or not isinstance(reserved.get("namespaces"), dict):
        raise report.ToolError("the reserved list must be the parsed merge-base reserved-namespaces.json "
                               "(an object with a 'namespaces' object)")
    return set(reserved["namespaces"])


def classify(paths, reserved):
    if isinstance(paths, str) or not all(isinstance(p, str) for p in paths):
        raise report.ToolError("paths must be a list of strings")
    names = reserved_names(reserved)
    findings, kinds, touches_reserved = [], set(), False
    if not paths:
        findings.append(report.finding(
            ["unrecognised-pr"], "the PR changes no paths, so it has no registry shape",
            "open the PR with the mods/<namespace>.<name>/ files it is meant to change",
            "criterion 8: classification fails closed"))
    for p in paths:
        parsed = parse_mod_path(p)
        if parsed is not None:
            kinds.add(parsed[2])
            touches_reserved = touches_reserved or parsed[0] in names
        elif p.startswith("mods/"):
            findings.append(report.finding(
                ["R1"], f"path {p!r} is under mods/ but is not mods/<namespace>.<name>/entry.json or "
                        "page.json, so no namespace can be attributed to it",
                "use exactly mods/<namespace>.<name>/entry.json or page.json (lowercase [a-z0-9][a-z0-9_-]* "
                "parts, one '.' between them) and remove other files", "ownership.md R1", path=p))
        else:
            findings.append(report.finding(
                ["unrecognised-path"], f"path {p!r} is outside mods/, which no registry PR shape includes",
                "split the change: a registry PR may only touch mods/<namespace>.<name>/entry.json or "
                "page.json", "criterion 8: classification fails closed", path=p))
    if findings:
        cls = CLASS_OTHER
    elif touches_reserved:
        cls = CLASS_RESERVED
    elif "entry" in kinds:
        cls = CLASS_ENTRY
    else:
        cls = CLASS_PAGE
    return report.make("classify", findings, **{"class": cls})
