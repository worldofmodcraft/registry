"""Append-only checker for entry.json (task 007a, edge E4): contracts/append-only.rules.md as merged by
task 057 (ADR-0041 as amended by ADR-0121).

Compares two PARSED values (old = merge-base, new = PR branch; None = file absent), never bytes. It
implements: the four file-level existence states, the id/owner freeze, rules 1-4 (rule 5 is a
deliberate non-rule: no monotonic versions, no semver normalisation), the four-state shape table,
born-pending only, and the three in-place transitions T1 pending->published, T2 published->removed,
T3 pending->rejected, each element classified independently.

Verdict (see report.py) adds:
  "state"               "absent->absent" | "absent->present" | "present->present" | "present->absent"
  "elements"            one entry per element of new.versions: {"index", "classification", "rules", ...}
                        classification: unchanged | appended | T1 | T2 | T3 | violation. A violation carries
                        the LIST of rule ids it breaks (e.g. ["rule 2", "rule 4"]).
  "authority_required"  sorted list of the transitions present among the elements ("T1", "T2", "T3").
This checker does NOT decide authority: T1 and T3 are shape-legal here. An "accepted" verdict with a
non-empty authority_required is NEVER a merge signal; the ownership checker (007b) must also run.

Rule ids used: "rule 1".."rule 4", "id-freeze", "owner-freeze", "deletion" (present->absent, and a rename,
which is a deletion plus a creation), "malformed" (structurally not an entry), "unrecognised-path".
"""

import classify
import report
import schema

FOUR = {"version", "commit", "source_url", "status"}
FIVE = ("source_archive", "source_sha256", "signature", "key_id", "published_at")
NINE = FOUR | set(FIVE)
T3_KEYS = FOUR | {"reason", "build_log_url"}
CITE = "append-only.rules.md"

_FIELDS = schema.load_schema("entry")["properties"]["versions"]["items"]["properties"]


def _field_ok(name, value):
    """A field satisfies its entry.schema.json sub-schema (pattern / minLength), via the repo's validator."""
    try:
        schema.schema_check.validate(value, _FIELDS[name])
    except schema.schema_check.SchemaValidationError:
        return False
    return True


def _same(a, b):
    """Deep equality of parsed JSON where a boolean never equals a number (Python's True == 1 would let
    owner.id true pass for 1) and key order is irrelevant."""
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    return isinstance(a, bool) == isinstance(b, bool) and a == b


def _reason_ok(r):
    return isinstance(r, str) and r.strip() != ""


def _author_frozen(o, w):
    return all(_same(o.get(k), w.get(k)) for k in ("version", "commit", "source_url"))


def _t1(o, w):
    """T1 pending -> published. Returns a list of reasons it is NOT a legal T1 (empty = legal)."""
    why = []
    if not _author_frozen(o, w):
        why.append("version, commit or source_url changed")
    if set(w) != NINE:
        why.append(f"key set differs from exactly the nine published keys ({sorted(set(w) ^ NINE)})")
    if any(f in o for f in FIVE):
        why.append("a pipeline-written field already exists in the old element")
    for f in FIVE:
        if f in w and not _field_ok(f, w[f]):
            why.append(f"{f} violates its entry.schema.json pattern or minimum length")
    return why


def _t2(o, w):
    """T2 published -> removed (the takedown)."""
    why = []
    if not _reason_ok(w.get("reason")):
        why.append("reason is missing or empty after trimming whitespace")
    if set(w) != NINE | {"reason"} or "reason" in o:
        why.append("key set differs from the nine published keys plus reason")
    for k in sorted(NINE - {"status"}):
        if not _same(o.get(k), w.get(k)):
            why.append(f"{k} changed alongside the status transition")
    return why


def _t3(o, w):
    """T3 pending -> rejected."""
    why = []
    if not _author_frozen(o, w):
        why.append("version, commit or source_url changed")
    if set(w) != T3_KEYS:
        why.append(f"key set differs from exactly the rejected row ({sorted(set(w) ^ T3_KEYS)})")
    if any(k in o for k in ("reason", "build_log_url")):
        why.append("reason or build_log_url already exists in the old element")
    if "reason" in w and not _reason_ok(w["reason"]):
        why.append("reason is not a string that is non-empty after trimming whitespace")
    if "build_log_url" in w and not _field_ok("build_log_url", w["build_log_url"]):
        why.append("build_log_url must match ^https://\\S+$")
    return why


TRANSITIONS = {
    ("pending", "published"): ("T1", _t1),
    ("published", "removed"): ("T2", _t2),
    ("pending", "rejected"): ("T3", _t3),
}


def _born_problems(e):
    """Rule 2 for a newly appended element: shape and born-pending. Returns reasons (empty = fine)."""
    if e.get("status") != "pending":
        return [f"born {e.get('status')!r}: a new element must be pending (T1/T2/T3 are the only ways out of it)"]
    why = []
    if set(e) != FOUR:
        why.append(f"key set {sorted(e)} is not exactly version, commit, source_url, status")
    for k in ("version", "commit", "source_url"):
        if not _field_ok(k, e.get(k)):
            why.append(f"{k} does not match its entry.schema.json pattern")
    return why


def _violation(index, rules, what, fix, path, attempted=None):
    f = report.finding(rules, what, fix, CITE, path=path, index=index)
    return {"index": index, "classification": "violation", "rules": list(rules), "attempted": attempted,
            "message": f["message"]}, f


def check_entry(old, new, path=None):
    findings, elements = [], []
    if old is None and new is None:
        return report.make("append-only", [], state="absent->absent", elements=[], authority_required=[])
    if new is None:
        findings.append(report.finding(
            ["deletion"], "entry.json is deleted (or renamed away): at least as severe as removing one version",
            "restore the file; versions can never be removed (ADR-0041)", CITE + " file-level: present->absent",
            path=path))
        return report.make("append-only", findings, state="present->absent", elements=[], authority_required=[])
    state = "absent->present" if old is None else "present->present"
    if not isinstance(new, dict) or not isinstance(new.get("versions"), list) \
            or not all(isinstance(e, dict) for e in new["versions"]):
        findings.append(report.finding(
            ["malformed"], "entry.json is not an object with a versions array of objects",
            "make the file a valid entry.json (contracts/entry.schema.json)", CITE, path=path))
        return report.make("append-only", findings, state=state, elements=[], authority_required=[])
    if old is not None and (not isinstance(old, dict) or not isinstance(old.get("versions"), list)
                            or not all(isinstance(e, dict) for e in old["versions"])):
        raise report.ToolError("the merge-base entry.json is not a well-formed entry; cannot compare against it")
    ov = [] if old is None else old["versions"]
    nv = new["versions"]
    n = len(ov)
    if old is not None:
        if not _same(new.get("id"), old.get("id")):
            findings.append(report.finding(
                ["id-freeze"], f"id changed from {old.get('id')!r} to {new.get('id')!r}",
                "restore the original id; it is frozen forever", CITE + " Fields outside versions[]", path=path))
        if not _same(new.get("owner"), old.get("owner")):
            findings.append(report.finding(
                ["owner-freeze"], "owner changed", "restore the original owner; no PR may ever change it",
                CITE + " Fields outside versions[]", path=path))
    if len(nv) < n:
        findings.append(report.finding(
            ["rule 3"], f"versions shrank from {n} to {len(nv)} elements", "restore the removed version objects; "
            "a version can never be deleted, whatever its status", CITE + " rule 3", path=path))
    for i in range(min(n, len(nv))):
        o, w = ov[i], nv[i]
        if _same(o, w):
            elements.append({"index": i, "classification": "unchanged", "rules": []})
            continue
        key = (o.get("status"), w.get("status"))
        if all(isinstance(s, str) for s in key) and key in TRANSITIONS:
            label, test = TRANSITIONS[key]
            why = test(o, w)
            if not why:
                elements.append({"index": i, "classification": label, "rules": []})
                continue
            el, f = _violation(i, ["rule 1"], f"element {i} is an attempted {label} but is not a legal one: "
                               + "; ".join(why), f"make element {i} exactly the {label} shape or revert it",
                               path, label)
        else:
            el, f = _violation(i, ["rule 1"], f"existing element {i} changed in place ({key[0]} -> {key[1]}), "
                               "which is not T1, T2 or T3", f"revert element {i} to its merge-base content",
                               path)
        elements.append(el)
        findings.append(f)
    versions = [e.get("version") for e in nv]
    for j in range(n, len(nv)):
        rules, what = [], []
        born = _born_problems(nv[j])
        if born:
            rules.append("rule 2")
            what.append("; ".join(born))
        if sum(1 for v in versions if _same(v, versions[j])) > 1:
            rules.append("rule 4")
            what.append(f"version {versions[j]!r} is not unique across the entry (exact string comparison)")
        if rules:
            el, f = _violation(j, rules, f"appended element {j}: " + "; ".join(what),
                               f"append element {j} as exactly a pending version with a unique version string",
                               path)
            elements.append(el)
            findings.append(f)
        else:
            elements.append({"index": j, "classification": "appended", "rules": []})
    authority = sorted({e["classification"] for e in elements if e["classification"] in ("T1", "T2", "T3")})
    return report.make("append-only", findings, state=state, elements=elements, authority_required=authority)


def check_pr(pairs):
    """pairs: {path: (old, new)} for every changed path. Only entry.json paths are append-only; page.json is
    not (it is editable content) and is skipped; any other path is rejected (fail closed)."""
    findings, elements, authority, states, skipped = [], [], set(), {}, []
    for path, (old, new) in pairs.items():
        parsed = classify.parse_mod_path(path)
        if parsed is None:
            findings.append(report.finding(
                ["unrecognised-path"], f"path {path!r} is not mods/<ns>.<name>/entry.json or page.json",
                "remove it from the PR", "ownership.md R1 / criterion 8", path=path))
        elif parsed[2] == "page":
            skipped.append(path)
        else:
            v = check_entry(old, new, path)
            findings += v["findings"]
            elements += [dict(e, path=path) for e in v["elements"]]
            authority |= set(v["authority_required"])
            states[path] = v["state"]
    return report.make("append-only", findings, states=states, elements=elements,
                       authority_required=sorted(authority), skipped_not_append_only=skipped)
