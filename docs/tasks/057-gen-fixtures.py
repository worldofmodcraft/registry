#!/usr/bin/env python3
"""Generates docs/tasks/057-transition-fixtures.json (task 057).

Run: python3 -I docs/tasks/057-gen-fixtures.py > docs/tasks/057-transition-fixtures.json
The JSON is committed; 057-verify.sh re-runs this generator and diffs it against the committed
file, so the fixtures cannot drift from their recipe. Every fixture: name, old (null for a first
publish), new, expect (accept|reject), rule (what it proves). A fixture may carry old_text /
new_text (raw JSON text) instead of old / new, to prove comparison is over parsed values.
"""
import copy
import json
import sys

ID = "kelsi:housing"
OWNER = {"provider": "github", "id": 4831207, "name_at_registration": "kelsi"}
SRC = "https://github.com/kelsi/housing"
C1, C2, C3 = "a" * 40, "b" * 40, "c" * 40
H = "0123456789abcdef" * 4  # 64 hex
SIG = "untrusted comment: signature from minisign secret key\nRWQAAAAA_placeholder_signature_bytes_base64=="
FIVE = ["source_archive", "source_sha256", "signature", "key_id", "published_at"]
REASON = "Contained a Blizzard-derived asset reported after publish; artefacts pulled per ADR-0041."
LOG = "https://builds.worldofmodcraft.com/logs/kelsi/housing/1.0.0.txt"


def pend(v="1.0.0", c=C1):
    return {"version": v, "commit": c, "source_url": SRC, "status": "pending"}


def pub(v="1.0.0", c=C1, h=H):
    d = pend(v, c)
    d.update({
        "source_archive": f"https://archive.worldofmodcraft.com/kelsi/housing/{v}.tar.gz",
        "source_sha256": h,
        "signature": SIG,
        "key_id": "E7A1B2C3D4E5F607",
        "published_at": "2026-10-15T09:00:00Z",
        "status": "published",
    })
    return d


def rem(v="1.0.0", c=C1):
    d = pub(v, c)
    d.update({"status": "removed", "reason": REASON})
    return d


def rej(v="1.0.0", c=C1):
    d = pend(v, c)
    d.update({"status": "rejected", "reason": "Build failed: manifest declares an undeclared dependency.", "build_log_url": LOG})
    return d


def E(*versions):
    return {"id": ID, "owner": copy.deepcopy(OWNER), "versions": [copy.deepcopy(v) for v in versions]}


def mod(d, **kw):
    d = copy.deepcopy(d)
    for k, v in kw.items():
        if v is _DEL:
            d.pop(k, None)
        else:
            d[k] = v
    return d


_DEL = object()
F = []


def fx(name, old, new, expect, rule, **extra):
    row = {"name": name, "old": old, "new": new, "expect": expect, "rule": rule}
    row.update(extra)
    F.append(row)


# --- first publish (old = null, n = 0) -------------------------------------------------
fx("first-publish-one-pending", None, E(pend()), "accept", "the author's PR is legal (born pending, four keys)")
fx("first-publish-born-published", None, E(pub()), "reject", "D-2/Q-L: forged published object")
fx("first-publish-born-removed", None, E(rem()), "reject", "D-2/Q-L: born removed")
fx("first-publish-born-rejected", None, E(rej()), "reject", "D-2/Q-L: rejected only via T3")
fx("first-publish-pending-with-reason", None, E(mod(pend(), reason="x")), "reject", "Q-L: exactly four keys")
fx("first-publish-pending-with-build-log-url", None, E(mod(pend(), build_log_url=LOG)), "reject", "Q-L: exactly four keys")
fx("first-publish-pending-bad-commit", None, E(mod(pend(), commit="abc")), "reject", "shape: commit pattern")
fx("first-publish-duplicate-version-strings", None, E(pend("1.0.0", C1), pend("1.0.0", C2)), "reject", "rule 4")
fx("entry-deleted", E(pend()), None, "reject", "present -> absent is always a violation")

# --- appends -----------------------------------------------------------------------------
fx("append-second-pending-after-published", E(pub("1.0.0")), E(pub("1.0.0"), pend("1.1.0", C2)), "accept", "later versions are appended pending")
fx("append-second-pending-after-rejected", E(rej("1.0.0")), E(rej("1.0.0"), pend("1.0.1", C2)), "accept", "a new version after a rejection")
fx("append-born-published-later", E(pub("1.0.0")), E(pub("1.0.0"), pub("1.1.0", C2)), "reject", "D-2/Q-L at any position")
fx("rejected-version-reappended-as-pending", E(rej("1.0.0")), E(rej("1.0.0"), pend("1.0.0", C2)), "reject", "string stays occupied, rule 4")
fx("delete-pending-version", E(pend("1.0.0"), pend("1.1.0", C2)), E(pend("1.0.0")), "reject", "rule 3")
fx("rejected-deleted", E(rej("1.0.0")), E(), "reject", "Q-J never deletion, rule 3")
fx("unchanged-mixed-states", E(pub("1.0.0"), rem("1.1.0", C2), rej("1.2.0", C3), pend("1.3.0", C1)), E(pub("1.0.0"), rem("1.1.0", C2), rej("1.2.0", C3), pend("1.3.0", C1)), "accept", "no change is not a transition")

# --- T1 pending -> published --------------------------------------------------------------
fx("t1-exact", E(pend()), E(pub()), "accept", "T1")
fx("t1-two-elements-two-transitions", E(pub("1.0.0"), pend("1.1.0", C2)), E(rem("1.0.0"), pub("1.1.0", C2)), "accept", "shape layer classifies each element independently (T2 + T1)")
fx("t1-and-t3-different-elements", E(pend("1.0.0"), pend("1.1.0", C2)), E(pub("1.0.0"), rej("1.1.0", C2)), "accept", "shape layer classifies each element independently (T1 + T3)")
fx("t1-extra-changed-field-commit", E(pend()), E(mod(pub(), commit=C2)), "reject", "frozen author field commit")
fx("t1-source-url-changed", E(pend()), E(mod(pub(), source_url="https://github.com/evil/housing")), "reject", "frozen author field source_url")
fx("t1-version-changed", E(pend()), E(mod(pub(), version="1.0.1")), "reject", "frozen author field version")
for f in FIVE:
    fx(f"t1-missing-{f}", E(pend()), E(mod(pub(), **{f: _DEL})), "reject", "all five pipeline fields required")
fx("t1-extra-key", E(pend()), E(mod(pub(), extra="x")), "reject", "key set is exactly nine")
fx("t1-with-reason", E(pend()), E(mod(pub(), reason="x")), "reject", "key set / coexistence: no reason on T1")
fx("t1-published-at-not-rfc3339", E(pend()), E(mod(pub(), published_at="yesterday")), "reject", "pattern")
fx("t1-sha256-wrong-length", E(pend()), E(mod(pub(), source_sha256="abc123")), "reject", "pattern")
fx("t1-source-archive-http", E(pend()), E(mod(pub(), source_archive="http://archive.worldofmodcraft.com/x.tar.gz")), "reject", "pattern")
fx("t1-empty-signature", E(pend()), E(mod(pub(), signature="")), "reject", "signature non-empty")
fx("t1-empty-key-id", E(pend()), E(mod(pub(), key_id="")), "reject", "key_id non-empty")
fx("t1-plus-owner-change", E(pend()), mod(E(pub()), owner={"provider": "github", "id": 1, "name_at_registration": "evil"}), "reject", "owner frozen")
fx("t1-plus-id-change", E(pend()), mod(E(pub()), id="evil:housing"), "reject", "id frozen")
fx("t1-reorders-versions", E(pub("1.0.0"), pend("1.1.0", C2)), E(pub("1.1.0", C2), pub("1.0.0")), "reject", "ordering frozen")
old_t = json.dumps(E(pub("1.0.0"), pend("1.1.0", C2)), indent=2)
new_e = E(pub("1.0.0"), pub("1.1.0", C2))
# unchanged element 0 rewritten with reversed key order and 8-space indentation; T1 on element 1.
rev = dict(reversed(list(new_e["versions"][0].items())))
new_e2 = copy.deepcopy(new_e)
new_e2["versions"][0] = rev
fx("t1-plus-whitespace-and-key-order-change-elsewhere", None, None, "accept", "comparison is over parsed values: whitespace and key order carry no meaning",
   old_text=old_t, new_text=json.dumps(new_e2, indent=8))
fx("pending-with-partial-writeback", E(pend()), E(mod(pend(), signature=SIG)), "reject", "pending carrying a pipeline field")
fx("pending-with-partial-writeback-born", None, E(mod(pend(), signature=SIG)), "reject", "born pending with a pipeline field")
fx("pending-to-pending-changed-commit", E(pend()), E(pend(c=C2)), "reject", "pending is frozen until T1/T3")
fx("pending-to-removed", E(pend()), E(mod(pub(), status="removed", reason=REASON)), "reject", "nothing archived, nothing to pull")
fx("published-to-pending", E(pub()), E(pend()), "reject", "one-way")
fx("published-rewritten-hashes", E(pub()), E(pub(h="f" * 64)), "reject", "exactly once: second write-back")
fx("published-to-rejected", E(pub()), E(mod(rej(), status="rejected")), "reject", "coexistence")

# --- T2 takedown (existing behaviour unchanged) ---------------------------------------------
fx("t2-takedown-exact", E(pub()), E(rem()), "accept", "existing takedown")
fx("t2-takedown-whitespace-reason", E(pub()), E(mod(rem(), reason="  \t ")), "reject", "existing: reason non-empty after trim")
fx("t2-takedown-hash-changed", E(pub()), E(mod(rem(), source_sha256="f" * 64)), "reject", "existing: every other field frozen")
fx("t2-with-t1-same-element", E(pend()), E(rem()), "reject", "coexistence: impossible start state")
fx("removed-to-published", E(rem()), E(pub()), "reject", "removed is terminal")
fx("removed-reason-rewritten", E(rem()), E(mod(rem(), reason="Different words")), "reject", "removed is frozen completely")

# --- T3 pending -> rejected -----------------------------------------------------------------
fx("t3-exact", E(pend()), E(rej()), "accept", "the rejection transition")
fx("t3-version-changed", E(pend()), E(mod(rej(), version="1.0.1")), "reject", "frozen author field version")
fx("t3-commit-changed", E(pend()), E(mod(rej(), commit=C2)), "reject", "frozen author field commit")
fx("t3-source-url-changed", E(pend()), E(mod(rej(), source_url="https://github.com/evil/housing")), "reject", "frozen author field source_url")
fx("t3-reason-not-a-string-number", E(pend()), E(mod(rej(), reason=5)), "reject", "Q-J: reason is a string")
fx("t3-reason-not-a-string-null", E(pend()), E(mod(rej(), reason=None)), "reject", "Q-J: reason is a string")
fx("t3-reason-not-a-string-object", E(pend()), E(mod(rej(), reason={"a": 1})), "reject", "Q-J: reason is a string")
fx("t3-missing-reason", E(pend()), E(mod(rej(), reason=_DEL)), "reject", "Q-J: reason required")
fx("t3-whitespace-only-reason", E(pend()), E(mod(rej(), reason=" \t\n ")), "reject", "Q-J: non-empty after trimming")
fx("t3-missing-build-log-url", E(pend()), E(mod(rej(), build_log_url=_DEL)), "reject", "Q-J: link required")
fx("t3-build-log-url-http", E(pend()), E(mod(rej(), build_log_url="http://builds.worldofmodcraft.com/log.txt")), "reject", "pattern ^https://\\S+$")
for f in FIVE:
    fx(f"t3-carries-{f}", E(pend()), E(mod(rej(), **{f: pub()[f]})), "reject", "T3 key set is exactly the rejected row")
fx("t3-extra-key", E(pend()), E(mod(rej(), extra="x")), "reject", "T3 key set")

# --- rejected is terminal ----------------------------------------------------------------------
fx("rejected-unchanged", E(rej()), E(rej()), "accept", "no change is not a transition")
fx("rejected-to-pending", E(rej()), E(pend()), "reject", "terminal")
fx("rejected-to-published", E(rej()), E(pub()), "reject", "terminal")
fx("rejected-reason-rewritten", E(rej()), E(mod(rej(), reason="A kinder reason")), "reject", "terminal, no correction by rewrite")
fx("rejected-to-removed", E(rej()), E(mod(rej(), status="removed")), "reject", "terminal")

json.dump(F, sys.stdout, indent=1, sort_keys=False)
sys.stdout.write("\n")
