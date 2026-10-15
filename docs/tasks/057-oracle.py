#!/usr/bin/env python3
"""Reference oracle for task 057's version-lifecycle shape rules (append-only.rules.md, T1/T2/T3).

This is NOT the checker (task 007 builds that, under tools/) and not an enforcement tool: it is
the executable reading of the contract text, used only to classify docs/tasks/057-transition-
fixtures.json. Task 007's checker must pass the same fixtures.

Usage:
  python3 -I docs/tasks/057-oracle.py                      run every fixture, exit non-zero on any mismatch
  python3 -I docs/tasks/057-oracle.py --mutation NAME      same, with one deliberate defect injected
  python3 -I docs/tasks/057-oracle.py --list-mutations
Authority layer (who may carry T1/T3) is out of scope: ownership.md's. Shape only.
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
FIXTURES = HERE / "057-transition-fixtures.json"
SCHEMA = REPO / "contracts" / "entry.schema.json"

FOUR = {"version", "commit", "source_url", "status"}
FIVE = ("source_archive", "source_sha256", "signature", "key_id", "published_at")
NINE = FOUR | set(FIVE)
BUILD_LOG_URL_PATTERN = r"^https://\S+$"

MUTATIONS = [
    "skip_patterns", "t3_keys_atleast", "t3_http_log", "t3_ws_reason", "born_pending_extra_key",
    "skip_version_frozen", "nonstring_reason", "skip_frozen_author", "allow_pending_removed",
    "t1_not_all_five", "t1_allow_reason", "allow_born_published", "allow_born_removed",
    "allow_born_rejected", "allow_published_rejected", "allow_rejected_pending",
    "allow_rejected_published", "allow_rejected_rewrite", "t3_no_reason", "t3_no_log",
    "allow_delete_rejected", "allow_published_pending", "raw_text_compare", "t1_keys_atleast",
    "allow_pending_rewrite", "skip_owner_freeze", "t2_ws_reason", "allow_rule4_dup",
    "reject_all",
]


def _pat(name):
    s = json.loads(SCHEMA.read_text())
    return s["properties"]["versions"]["items"]["properties"][name]["pattern"]


def classify(old, new, mut=frozenset()):
    """Return ('accept', '') or ('reject', reason). old/new: parsed entries or None."""
    M = mut.__contains__

    def pat_ok(p, s):
        return M("skip_patterns") or (isinstance(s, str) and re.search(p, s) is not None)

    def author_frozen(o, n):
        if M("skip_frozen_author"):
            return True
        for k in ("version", "commit", "source_url"):
            if k == "version" and M("skip_version_frozen"):
                continue
            if o.get(k) != n.get(k):
                return False
        return True

    def reason_ok(r, ws_flag):
        if M("nonstring_reason"):
            r = str(r)
        if not isinstance(r, str):
            return False
        if M(ws_flag):
            return r != ""
        return r.strip() != ""

    def sameparsed(a, b):
        if M("raw_text_compare"):
            return json.dumps(a) == json.dumps(b)
        return a == b

    if M("reject_all"):
        return "reject", "mutation: a suite that rejects everything"
    if new is None:
        return "reject", "present -> absent"
    nv = new.get("versions")
    if not isinstance(nv, list):
        return "reject", "versions not an array"
    ov = [] if old is None else old["versions"]
    n = len(ov)
    if old is not None:
        if new.get("id") != old.get("id"):
            return "reject", "id frozen"
        if not M("skip_owner_freeze") and new.get("owner") != old.get("owner"):
            return "reject", "owner frozen"
    if len(nv) < n:
        if not (M("allow_delete_rejected") and all(e.get("status") == "rejected" for e in ov[len(nv):])):
            return "reject", "rule 3"
    for i in range(min(n, len(nv))):
        o, w = ov[i], nv[i]
        if sameparsed(o, w):
            continue
        so, sw = o.get("status"), w.get("status")
        if so == "pending" and sw == "published":
            why = _t1(o, w, M, pat_ok, author_frozen)
        elif so == "published" and sw == "removed":
            why = _t2(o, w, lambda r: reason_ok(r, "t2_ws_reason"))
        elif so == "pending" and sw == "rejected":
            why = _t3(o, w, M, pat_ok, author_frozen, lambda r: reason_ok(r, "t3_ws_reason"))
        elif (M("allow_pending_rewrite") and (so, sw) == ("pending", "pending")) \
                or (M("allow_pending_removed") and (so, sw) == ("pending", "removed")) \
                or (M("allow_published_rejected") and (so, sw) == ("published", "rejected")) \
                or (M("allow_rejected_pending") and (so, sw) == ("rejected", "pending")) \
                or (M("allow_rejected_published") and (so, sw) == ("rejected", "published")) \
                or (M("allow_rejected_rewrite") and (so, sw) == ("rejected", "rejected")) \
                or (M("allow_published_pending") and (so, sw) == ("published", "pending")):
            why = None
        else:
            why = f"rule 1: element changed outside T1/T2/T3 ({so} -> {sw})"
        if why:
            return "reject", f"index {i}: {why}"
    seen = {e.get("version") for e in ov}
    for j, e in enumerate(nv[n:], start=n):
        why = _born(e, M, pat_ok)
        if why:
            return "reject", f"index {j}: {why}"
        if e["version"] in seen and not M("allow_rule4_dup"):
            return "reject", f"index {j}: rule 4 duplicate version string"
        seen.add(e["version"])
    return "accept", ""


def _born(e, M, pat_ok):
    if not isinstance(e, dict):
        return "not an object"
    st = e.get("status")
    if (st, True) in (("published", M("allow_born_published")), ("removed", M("allow_born_removed")),
                      ("rejected", M("allow_born_rejected"))):
        return None
    if st != "pending":
        return f"born {st!r}: a new element must be pending"
    keys = set(e)
    if keys != FOUR and not (M("born_pending_extra_key") and FOUR <= keys):
        return f"born pending key set {sorted(keys)} is not exactly the four keys"
    for k in ("version", "commit", "source_url"):
        if not pat_ok(_pat(k), e.get(k)):
            return f"{k} does not match its schema pattern"
    return None


def _t1(o, w, M, pat_ok, author_frozen):
    if not author_frozen(o, w):
        return "T1: version/commit/source_url changed"
    keys = set(w)
    if M("t1_keys_atleast"):
        if not NINE <= keys:
            return "T1: key set"
    elif M("t1_allow_reason"):
        if keys not in (NINE, NINE | {"reason"}):
            return "T1: key set"
    elif M("t1_not_all_five"):
        if not (keys <= NINE and keys & set(FIVE)):
            return "T1: key set"
    elif keys != NINE:
        return f"T1: key set differs from exactly the nine ({sorted(keys ^ NINE)})"
    present = [f for f in FIVE if f in w]
    if M("t1_not_all_five"):
        if not present:
            return "T1: no pipeline field"
    elif len(present) != 5:
        return "T1: all five pipeline fields required"
    if any(f in o for f in FIVE):
        return "T1: pipeline field already present in old"
    for f in present:
        s = w[f]
        if f in ("signature", "key_id"):
            if not (M("skip_patterns") or (isinstance(s, str) and len(s) >= 1)):
                return f"T1: {f} empty"
        elif not pat_ok(_pat(f), s):
            return f"T1: {f} violates its pattern"
    return None


def _t2(o, w, reason_ok):
    if "reason" not in w or not reason_ok(w["reason"]):
        return "T2: reason missing or empty after trim"
    if set(w) != NINE | {"reason"} or "reason" in o:
        return "T2: key set"
    for k in NINE - {"status"}:
        if o.get(k) != w.get(k):
            return f"T2: {k} changed"
    return None


def _t3(o, w, M, pat_ok, author_frozen, reason_ok):
    if not author_frozen(o, w):
        return "T3: version/commit/source_url changed"
    want = FOUR | {"reason", "build_log_url"}
    keys = set(w)
    if M("t3_keys_atleast"):
        ok = want <= keys
    elif M("t3_no_reason"):
        ok = keys in (want, want - {"reason"})
    elif M("t3_no_log"):
        ok = keys in (want, want - {"build_log_url"})
    else:
        ok = keys == want
    if not ok:
        return f"T3: key set differs from exactly the rejected row ({sorted(keys ^ want)})"
    if "reason" in w and not reason_ok(w["reason"]):
        return "T3: reason not a non-empty (post-trim) string"
    if "build_log_url" in w:
        b = w["build_log_url"]
        if M("t3_http_log"):
            good = isinstance(b, str) and re.search(r"^https?://\S+$", b) is not None
        else:
            good = pat_ok(BUILD_LOG_URL_PATTERN, b)
        if not good:
            return "T3: build_log_url must match ^https://\\S+$"
    return None


def load(fx):
    if "new_text" in fx:
        return (json.loads(fx["old_text"]) if fx.get("old_text") else None), json.loads(fx["new_text"])
    return fx["old"], fx["new"]


def run(mut=frozenset(), quiet=False):
    fixtures = json.loads(FIXTURES.read_text())
    bad, counts = [], {"accept": 0, "reject": 0}
    for fx in fixtures:
        old, new = load(fx)
        v, why = classify(old, new, mut)
        counts[fx["expect"]] += 1
        if v != fx["expect"]:
            bad.append((fx["name"], fx["expect"], v, why))
    if not quiet:
        print(f"{len(fixtures)} fixtures ({counts['accept']} accept, {counts['reject']} reject); mutation={sorted(mut) or 'none'}")
        for name, exp, got, why in bad:
            print(f"  MISMATCH {name}: expected {exp}, oracle said {got} {why}")
        if not bad:
            print("  every fixture classified as recorded")
    return bad


def main(argv):
    if "--list-mutations" in argv:
        print("\n".join(MUTATIONS))
        return 0
    mut = frozenset()
    if "--mutation" in argv:
        name = argv[argv.index("--mutation") + 1]
        if name not in MUTATIONS:
            print(f"unknown mutation {name}", file=sys.stderr)
            return 2
        mut = frozenset([name])
    return 1 if run(mut) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
