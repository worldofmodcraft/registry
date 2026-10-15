"""Shared test helpers for the registry shape checkers (task 007a). Standard library only.

Run the suite with:   python3 -m unittest discover -s tests/registry -v
"""

import copy
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools" / "registry"))
sys.path.insert(0, str(REPO / "tests" / "contracts"))

import append_only  # noqa: E402,F401
import classify  # noqa: E402,F401
import report  # noqa: E402,F401
import schema  # noqa: E402,F401
import schema_check  # noqa: E402,F401

FIXTURES_PATH = REPO / "docs" / "tasks" / "057-transition-fixtures.json"
CLI = REPO / "tools" / "registry" / "cli.py"
RESERVED = {"schema_version": "1.0.0", "namespaces": {"mc": {}, "test": {}}}

A40 = "a" * 40
B64 = "b" * 64
SRC = "https://github.com/example/mod"
OWNER = {"provider": "github", "id": 4831207, "name_at_registration": "kelsi"}
PIPELINE = {
    "source_archive": "https://cdn.worldofmodcraft.org/archives/example-mod-1.0.0.tar.gz",
    "source_sha256": B64,
    "signature": "c" * 62,
    "key_id": "platform-2026-01",
    "published_at": "2026-10-15T09:00:00Z",
}


def pending(version="1.0.0", commit=A40):
    return {"version": version, "commit": commit, "source_url": SRC, "status": "pending"}


def published(version="1.0.0", commit=A40):
    d = pending(version, commit)
    d.update(PIPELINE)
    d["status"] = "published"
    return d


def removed(version="1.0.0", commit=A40, reason="Takedown for a legal reason."):
    d = published(version, commit)
    d.update(status="removed", reason=reason)
    return d


def rejected(version="1.0.0", commit=A40, reason="Build failed.", url="https://builds.example.org/log.txt"):
    d = pending(version, commit)
    d.update(status="rejected", reason=reason, build_log_url=url)
    return d


def entry(*versions, id="kelsi:housing", owner=None):
    return {"id": id, "owner": copy.deepcopy(owner or OWNER), "versions": list(versions)}


def commit_for(label):
    return hashlib.sha1(label.encode()).hexdigest()


def rules_of(verdict, index):
    """The rule-id list of the element at `index` (violations only)."""
    el = verdict["elements"][index]
    return el["rules"]


def attacker_entry(indices=(0, 1, 2, 3)):
    """Task 006's malicious first publish (docs/tasks/006-verify.sh lines 210-264, same construction):
    absent -> present, born published/removed, duplicate version strings."""
    def sha1(label):
        return hashlib.sha1(label.encode()).hexdigest()

    def sha256(label):
        return hashlib.sha256(label.encode()).hexdigest()

    def v(version, label, status="published", reason=None):
        o = {
            "version": version,
            "commit": sha1(label),
            "source_url": "https://github.com/attacker/mod",
            "source_archive": "https://cdn.worldofmodcraft.org/archives/attacker-mod-%s.tar.gz" % label,
            "source_sha256": sha256(label),
            "signature": "c" * 62,
            "key_id": "platform-2026-01",
            "published_at": "2026-09-03T00:00:00Z",
            "status": status,
        }
        if reason is not None:
            o["reason"] = reason
        return o

    all4 = [
        v("1.2.0", "first-1.2.0"),
        v("1.2.0", "second-1.2.0"),
        v("2.0.0", "born-removed-no-reason", status="removed"),
        v("2.1.0", "born-removed-blank", status="removed", reason="   "),
    ]
    return {"id": "attacker:mod", "owner": {"provider": "github", "id": 999001, "name_at_registration": "attacker"},
            "versions": [all4[i] for i in indices]}


def load_fixtures():
    return json.loads(FIXTURES_PATH.read_text())


def fixture_pair(fx):
    if "new_text" in fx:
        return (json.loads(fx["old_text"]) if fx.get("old_text") else None), json.loads(fx["new_text"])
    return fx["old"], fx["new"]
