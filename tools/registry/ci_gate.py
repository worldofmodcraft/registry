#!/usr/bin/env python3
"""The CI composer (task 039): runs the four registry checkers on one pull request and composes one verdict.

    python3 -I tools/registry/ci_gate.py --repo DIR --event EVENT.json --pr PR.json --membership-status (NNN|none) --out DIR
    python3 -I tools/registry/ci_gate.py --classify-only --repo DIR --event EVENT.json --pr PR.json --out DIR

Offline, standard library only, no environment reads, no shell. DIR is a checkout of the BASE branch with the PR head
fetched as objects only; nothing from the PR head is executed, only read as data through `git`. Identity is the API PR
object's user.id cross-checked with the event (ownership.md I1); every authority input (reserved list, existing owners,
the R11 configuration) is read at the merge-base (I4). Exit 0 accepted, 1 rejected, 2 could not decide (NOT a rejection).
Writes OUT/verdict.json, OUT/comment.md (starts with the marker line the workflow looks for), OUT/class and OUT/outputs
(strict key=value lines only; the workflow appends this file to the step output). Green means "the checks pass", never
"approved" (I8): a human still decides the merge.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

GIT_TIMEOUT, CHECKER_TIMEOUT = 30, 120
MAX_BLOB_BYTES, MAX_TOTAL_BYTES, MAX_ENTRIES = 1 << 20, 32 << 20, 5000  # per blob, per tree, per tree / per diff
MARKER = "<!-- registry-ci-gate -->"
ENV = {"PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0"}
SHA, NAME = r"[0-9a-f]{40}", r"[A-Za-z0-9](-?[A-Za-z0-9]){0,38}"
CLASSES = ("entry", "page-only", "reserved-namespace", "other")
STRICT = {k: re.compile(v) for k, v in {  # the only lines OUT/outputs may hold (never PR free text)
    "class": "|".join(CLASSES), "result": r"accepted|rejected|undecided",
    "route": r"infra|content|empty", "pr": r"[0-9]+", "head_sha": SHA, "merge_base": SHA, "org": NAME, "login": NAME}.items()}
ENTRY_RE = re.compile(r"mods/([a-z0-9][a-z0-9_-]*)\.([a-z0-9][a-z0-9_-]*)/entry\.json")
EMPTY_DIFF = ("unrecognised-pr (criterion 8: classification fails closed): the PR changes no paths (empty diff), so it "
              "has no registry shape. To fix: open the PR with the mods/<namespace>.<name>/ files it is meant to change")


class Undecided(Exception):
    """The composer could not decide; maps to exit 2, never to a rejection."""


def _git(repo, *args, timeout=GIT_TIMEOUT, ok=(0,)):
    try:
        r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, timeout=timeout, env=ENV,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        raise Undecided(f"git {args[0]} timed out after {timeout}s") from None
    if r.returncode not in ok:
        raise Undecided(f"git {args[0]} failed with exit {r.returncode}")
    return r.stdout


def _checker(tools_dir, script, args, timeout):
    try:
        r = subprocess.run([sys.executable, "-I", "-B", str(Path(tools_dir) / script), *args], capture_output=True,
                           timeout=timeout, env=ENV, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, b"", b""
    return r.returncode, r.stdout, r.stderr


def _nodup(pairs):
    if len({k for k, _ in pairs}) != len(pairs):
        raise ValueError("duplicate object key")
    return dict(pairs)


def _load(path, what):
    try:
        return json.loads(Path(path).read_text(), object_pairs_hook=_nodup)
    except (OSError, ValueError) as exc:  # includes UnicodeDecodeError and JSONDecodeError
        raise Undecided(f"cannot read {what}: {exc}") from None


def _at(doc, *keys):
    for k in keys:
        if not isinstance(doc, dict) or k not in doc:
            raise Undecided(f"missing field {'.'.join(keys)}")
        doc = doc[k]
    return doc


def read_identity(event, pr):
    """Author and PR facts from the API object (I1), after cross-checking the event; anything off is exit 2."""
    n, repo = _at(pr, "number"), _at(pr, "base", "repo", "full_name")
    for label, a, b in (("number", _at(event, "number"), n), ("pull_request.number", _at(event, "pull_request", "number"), n),
                        ("user.id", _at(event, "pull_request", "user", "id"), _at(pr, "user", "id")),
                        ("head.sha", _at(event, "pull_request", "head", "sha"), _at(pr, "head", "sha")),
                        ("base.ref", _at(event, "pull_request", "base", "ref"), "main"), ("base.ref (API)", _at(pr, "base", "ref"), "main"),
                        ("base repository", _at(event, "pull_request", "base", "repo", "full_name"), repo),
                        ("repository", _at(event, "repository", "full_name"), repo)):
        if a != b or type(a) is not type(b):
            raise Undecided(f"the event and the API PR object disagree on {label}: {a!r} vs {b!r}")
    who = {"number": n, "uid": _at(pr, "user", "id"), "login": _at(pr, "user", "login"), "head": _at(pr, "head", "sha"),
           "base_sha": _at(pr, "base", "sha")}
    good = (type(n) is int and n > 0 and type(who["uid"]) is int and who["uid"] > 0 and isinstance(who["login"], str)
            and re.fullmatch(NAME, who["login"]) and all(isinstance(who[k], str) and re.fullmatch(SHA, who[k]) for k in ("head", "base_sha")))
    if not good:
        raise Undecided("the PR object has a malformed number, user id, user login or sha")
    return who


def merge_base(repo, who):
    tip = _git(repo, "rev-parse", "--verify", "HEAD^{commit}").decode().strip()
    _git(repo, "cat-file", "-e", who["head"] + "^{commit}")
    found = _git(repo, "merge-base", "--all", tip, who["head"], ok=(0, 1)).decode().split()
    if len(found) != 1:
        raise Undecided(f"expected exactly one merge-base of the base tip and the PR head, found {len(found)}")
    if _git(repo, "merge-base", "--all", who["base_sha"], tip, ok=(0, 1)).decode().split() != [who["base_sha"]]:
        raise Undecided("the API base.sha is not an ancestor of the base branch tip")
    return found[0]


def parse_z_paths(data):
    if not data:
        return []
    if not data.endswith(b"\0") or b"" in data[:-1].split(b"\0"):
        raise Undecided("the changed-path list is not a clean NUL-terminated list")
    try:
        return [p.decode("utf-8") for p in data[:-1].split(b"\0")]
    except UnicodeDecodeError:
        raise Undecided("a changed path is not valid UTF-8") from None


def materialise(repo, commit, dest, prefixes, *, max_blob_bytes=MAX_BLOB_BYTES, max_entries=MAX_ENTRIES,
                max_total_bytes=MAX_TOTAL_BYTES, git_timeout=GIT_TIMEOUT):
    """Write the blobs of `commit` under `prefixes` into the existing dir `dest`, as data, via ls-tree and cat-file only.
    Returns [(path, mode)] for entries that are neither regular files nor symlinks (not written). Raises Undecided."""
    recs = [r for r in _git(repo, "ls-tree", "-r", "-l", "-z", "--full-tree", commit, "--", *prefixes, timeout=git_timeout).split(b"\0") if r]
    if len(recs) > max_entries:
        raise Undecided(f"{len(recs)} tree entries, over the entry cap of {max_entries}")
    seen, files, links, odd, total = set(), [], [], [], 0
    for rec in recs:
        head, _, raw = rec.partition(b"\t")
        fields = head.split()
        if len(fields) != 4:
            raise Undecided("unparsable ls-tree record")
        mode, _, sha, size = (f.decode() for f in fields)
        try:
            path = raw.decode("utf-8")
        except UnicodeDecodeError:
            raise Undecided("a tree path is not valid UTF-8") from None
        if any(c in ("", ".", "..") or c.lower() == ".git" for c in path.split("/")):
            raise Undecided(f"bad path component in tree path {path!r}")
        if path in seen:
            raise Undecided(f"duplicate tree entry {path!r}")
        seen.add(path)
        if mode in ("100644", "100755", "120000"):
            if int(size) > max_blob_bytes:
                raise Undecided(f"blob {path!r} is {size} bytes, over the byte cap of {max_blob_bytes}")
            total += int(size)
            (links if mode == "120000" else files).append((path, sha, int(size)))
        else:
            odd.append((path, mode))
    if total > max_total_bytes:
        raise Undecided(f"{total} blob bytes, over the byte cap of {max_total_bytes}")
    for path in seen:
        parts = path.split("/")
        if any("/".join(parts[:i]) in seen for i in range(1, len(parts))):
            raise Undecided(f"path conflict: {path!r} lies below another file or link")
    root, real = Path(dest), os.path.realpath(dest)

    def blob(sha, size):
        data = _git(repo, "cat-file", "blob", sha, timeout=git_timeout)
        if len(data) != size:
            raise Undecided(f"blob {sha} has {len(data)} bytes, ls-tree said {size}")
        return data
    for path, sha, size in files:  # every regular file first, so no symlink exists while files are created
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(root / path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(blob(sha, size))
    for path, sha, size in links:  # symlinks last, with their literal target, never followed
        try:
            target = blob(sha, size).decode("utf-8")
        except UnicodeDecodeError:
            raise Undecided(f"symlink {path!r} has a non-UTF-8 target") from None
        if not target or target.startswith("/") or "\0" in target:
            raise Undecided(f"symlink {path!r} target {target!r} escapes the root (empty, absolute or NUL)")
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        os.symlink(target, root / path)
    for path, _, _ in links:
        if os.path.realpath(root / path) != real and not os.path.realpath(root / path).startswith(real + os.sep):
            raise Undecided(f"symlink {path!r} escapes the root")
    return odd


def read_r11(old):
    p = Path(old) / "config" / "r11-identity.json"
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise Undecided("config/r11-identity.json at the merge-base is not a regular file")
    if not p.exists():
        return None  # absent means unconfigured: R11 authorises nobody
    doc, bad = _load(p, "config/r11-identity.json"), Undecided("config/r11-identity.json is malformed")
    if not isinstance(doc, dict) or set(doc) != {"schema_version", "r11_identity"} or doc["schema_version"] != "1.0.0":
        raise bad
    r = doc["r11_identity"]
    if r is None:
        return None
    if isinstance(r, dict) and set(r) == {"provider", "id"} and r["provider"] == "github" and type(r["id"]) is int and r["id"] > 0:
        return r["id"]
    raise bad


def reserved_org(old):
    """The single organisation named by every merge-base reserved entry (more than one, or none, is exit 2)."""
    doc = _load(Path(old) / "reserved-namespaces.json", "the merge-base reserved list")
    orgs = set()
    for ent in _at(doc, "namespaces").values():
        orgs.add(_at(ent, "owner", "name_at_registration"))
    if len(orgs) != 1 or not all(isinstance(o, str) and re.fullmatch(NAME, o) for o in orgs):
        raise Undecided(f"the reserved list must name exactly one valid organisation, found {sorted(map(str, orgs))}")
    return orgs.pop()


def judge(name, rc, out, err):
    r = {"exit": rc, "state": "undecided", "stderr": err.decode("utf-8", "replace")}
    if rc is None:
        r["why"] = "timed out"
    elif rc not in (0, 1):
        r["why"] = f"exit code {rc} (not 0 or 1)"
    else:
        try:
            v = json.loads(out)
        except ValueError:
            v = None
        if not isinstance(v, dict) or v.get("checker") != name or v.get("verdict") not in ("accepted", "rejected"):
            r["why"] = "stdout is not a verdict of this checker"
        elif (rc == 0) != (v["verdict"] == "accepted") or bool(v.get("findings")) != (rc == 1):
            r["why"] = "exit code disagrees with the verdict"
        else:
            r.update(state=v["verdict"], verdict=v)
    return r


def fence(text):
    """A code fence longer than any backtick run in `text`, so PR-controlled strings cannot close it."""
    bar = "`" * max([3] + [len(m) + 1 for m in re.findall(r"`+", text)])
    return f"\n{bar}\n{text.rstrip(chr(10))}\n{bar}\n"


def clip(text, n):
    return text if len(text) <= n else text[:n] + "\n... (truncated; see the run log)"


def first_publishes(old, new, paths, reserved, who):
    owned = {d.name.split(".")[0] for d in (Path(old) / "mods").glob("*.*") if (d / "entry.json").is_file()} if (Path(old) / "mods").is_dir() else set()
    out = []
    for ns in sorted({m.group(1) for p in paths if (m := ENTRY_RE.fullmatch(p)) and (Path(new) / p).is_file()} - owned):
        if ns in _at(reserved, "namespaces"):
            org = _at(reserved, "namespaces", ns, "owner", "name_at_registration")
            out.append(f"The namespace `{ns}:` is reserved (ADR-0119) and stays bound to the organisation `{org}` recorded in "
                       "the merge-base reserved list, not to your account.")
        else:
            out.append(f"This creates the namespace `{ns}:` permanently bound to your GitHub account (id {who['uid']}). "
                       "Namespaces are never reassigned.")
    return out


def render(code, route, cls, results, notes, reason, paths):
    head = {0: "all checks pass", 1: "rejected", 2: "could not decide (not a rejection)"}[code]
    body = [MARKER, f"### Registry CI: {head}", ""]
    if route == "infra":
        shown, size = [], 0
        for p in paths[:50]:
            if size + len(p) + 1 > 4096:
                break
            shown.append(p)
            size += len(p) + 1
        body += ["This is not a registry content PR; registry CI does not judge it. Note that green does not mean safe: this "
                 "relies on human review before merge (M9, MANAGER.md section 7).", "", f"Touched paths ({len(paths)}):" + fence("\n".join(shown))]
        if len(paths) > len(shown):
            body.append(f"... and {len(paths) - len(shown)} more paths not shown.")
    for name, r in results.items():
        if r["state"] == "accepted":
            body.append(f"- **{name}**: accepted")
        else:
            why = r.get("why") or "rejected"
            body += [f"- **{name}**: {why if r['state'] == 'undecided' else 'rejected'}"
                     + fence(clip(r["stderr"] or "(no output)", 12000))]
    if reason:
        body += ["Registry CI could not decide, so this is not a rejection and not a pass:" + fence(clip(reason, 4000))]
    if code == 0 and cls == "page-only":
        body.append("page.json-only: no build runs. The screenshot scan (ADR-0059 section 3, task 040) is not yet running.")
    if code == 0 and route == "content":
        body += notes + ["", "Green means the checks pass. It is **not approval**: a human still decides the merge (ownership.md I8)."]
    return clip("\n".join(body) + "\n", 60000)


def _decide(repo, event_path, pr_path, status, classify_only, tools_dir, lim):
    who = read_identity(_load(event_path, "the event payload"), _load(pr_path, "the PR object"))
    mb = merge_base(repo, who)
    paths = parse_z_paths(_git(repo, "diff", "--no-renames", "--ignore-submodules=none", "--name-only", "-z", mb, who["head"], "--",
                               timeout=lim["git_timeout"]))
    if len(paths) > lim["max_entries"] or sum(map(len, paths)) > 256 * 1024:
        raise Undecided(f"the PR changes {len(paths)} paths, over the cap")
    info = {"pr": who["number"], "head_sha": who["head"], "merge_base": mb}
    res = {"route": "content", "class": "other", "checkers": {}, "notes": [], "paths": paths, "info": info, "extra": []}
    if not paths:
        f = {"rules": ["unrecognised-pr"], "path": None, "index": None, "message": EMPTY_DIFF}
        v = {"checker": "classify", "verdict": "rejected", "findings": [f], "class": "other"}
        res.update(route="empty", checkers={"classify": {"exit": 1, "state": "rejected", "verdict": v,
                                                         "stderr": f"REJECTED {EMPTY_DIFF}\n"}})
    elif not any(p == "mods" or p.startswith("mods/") for p in paths):
        res["route"] = "infra"
    else:
        old, new = (tempfile.mkdtemp(prefix=f"wom-{n}-", dir=lim["tmp_parent"]) for n in ("old", "new"))
        try:
            if materialise(repo, mb, old, ("mods", "reserved-namespaces.json", "config/r11-identity.json"), **lim["mat"]):
                raise Undecided("the merge-base tree holds an entry that is neither a file nor a symlink")
            odd = materialise(repo, who["head"], new, ("mods",), **lim["mat"])
            for root in (old, new):
                if not Path(root, "mods").exists():
                    Path(root, "mods").mkdir()
            reserved_path = Path(old, "reserved-namespaces.json")
            if reserved_path.is_symlink() or not reserved_path.is_file():
                raise Undecided("reserved-namespaces.json is not a regular file at the merge-base")
            r11, tools = read_r11(old), Path(tools_dir or Path(repo) / "tools" / "registry")
            rsv = str(reserved_path)
            plan = [("classify", "cli.py", ["classify", "--reserved-file", rsv, "--", *paths])]
            if not classify_only:
                own = ["--author-provider", "github", "--author-id", str(who["uid"]), "--author-login", who["login"],
                       "--old-root", old, "--new-root", new, "--reserved-file", rsv]
                own += [] if status in (None, "none") else ["--membership-status", status]
                own += [] if r11 is None else ["--r11-identity", f"github:{r11}"]
                plan += [("schema", "cli.py", ["schema", "--root", new, "--", *paths]),
                         ("append-only", "cli.py", ["append-only", "--old-root", old, "--new-root", new, "--", *paths]),
                         ("ownership", "ownership_cli.py", own + ["--", *paths])]
            res["checkers"] = {n: judge(n, *_checker(tools, s, a, lim["checker_timeout"])) for n, s, a in plan}
            c = res["checkers"]["classify"]
            if c["state"] != "undecided" and c["verdict"].get("class") in CLASSES:
                res["class"] = c["verdict"]["class"]
            elif c["state"] != "undecided":
                c.update(state="undecided", why="classify returned an unknown class")
            if odd:
                res["checkers"]["composer"] = {"exit": 1, "state": "rejected", "stderr": "".join(
                    f"REJECTED tree-mode: {p!r} has git mode {m}, which registry content may not use (fail closed)\n" for p, m in odd),
                    "verdict": {"verdict": "rejected", "findings": [{"rules": ["tree-mode"]}]}}
            if res["class"] == "reserved-namespace":  # the question is only ever asked about this one organisation
                org = reserved_org(old)
                res["extra"] = [("org", org), ("login", who["login"])] if classify_only else []
            if not classify_only:
                res["notes"] = first_publishes(old, new, paths, _load(reserved_path, "the reserved list"), who)
        finally:
            shutil.rmtree(old, ignore_errors=True)
            shutil.rmtree(new, ignore_errors=True)
    if classify_only:
        res["checkers"] = {k: v for k, v in res["checkers"].items() if k == "classify"}
    return res


def run_gate(repo, event_path, pr_path, out, membership_status, *, classify_only=False, tools_dir=None,
             checker_timeout=CHECKER_TIMEOUT, git_timeout=GIT_TIMEOUT, max_blob_bytes=MAX_BLOB_BYTES,
             max_entries=MAX_ENTRIES, tmp_parent=None):
    lim = {"checker_timeout": checker_timeout, "git_timeout": git_timeout, "max_entries": max_entries, "tmp_parent": tmp_parent,
           "mat": {"max_blob_bytes": max_blob_bytes, "max_entries": max_entries, "git_timeout": git_timeout}}
    reason, res = "", None
    try:
        res = _decide(Path(repo).resolve(), event_path, pr_path, membership_status, classify_only, tools_dir, lim)
        states = [r["state"] for r in res["checkers"].values()]
        code = 2 if "undecided" in states else 1 if ("rejected" in states or res["route"] == "empty") else 0
        if classify_only:
            code = 2 if "undecided" in states else 0
    except Exception as exc:  # noqa: BLE001 - whatever went wrong, the answer is "could not decide", never a rejection
        code, reason = 2, f"{type(exc).__name__}: {exc}"
    outputs = [] if res is None else ([("class", res["class"]), *res["extra"]] if classify_only else
                                      [("result", {0: "accepted", 1: "rejected"}.get(code, "undecided")), ("route", res["route"]),
                                       ("class", res["class"]), *res["info"].items(), *res["extra"]])
    if code == 2:
        outputs = [] if classify_only else [("result", "undecided")]
    try:
        if any(k not in STRICT or not STRICT[k].fullmatch(str(v)) for k, v in outputs):
            raise Undecided("refusing to write a non-strict output line")
        os.makedirs(out, exist_ok=True)
        body = {"result": {0: "accepted", 1: "rejected", 2: "undecided"}[code], "merge_signal": False, "reason": reason}
        if res:
            body.update(route=res["route"], checkers=res["checkers"], **{"class": res["class"]}, **res["info"])
        Path(out, "verdict.json").write_text(json.dumps(body, indent=2, sort_keys=True) + "\n")
        shown = res["checkers"] if res else {}
        Path(out, "comment.md").write_text(render(code, res["route"] if res else "", res["class"] if res else "", shown,
                                                  res["notes"] if res else [], reason, res["paths"] if res else []))
        if res:
            Path(out, "class").write_text(res["class"] + "\n")
        Path(out, "outputs").write_text("".join(f"{k}={v}\n" for k, v in outputs))
    except (OSError, Undecided) as exc:
        sys.stderr.write(f"ERROR (could not write the result, not a rejection): {exc}\n")
        return 2
    sys.stderr.write(f"ci_gate: exit {code}" + (f" ({reason})" if reason else "") + "\n")
    return code


def _status(value):
    if not re.fullmatch(r"[0-9]{3}|none", value):
        raise argparse.ArgumentTypeError("must be a three digit HTTP status or the word none")
    return value


def main(argv):
    ap = argparse.ArgumentParser(prog="ci_gate", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for flag in ("--repo", "--event", "--pr", "--out"):
        ap.add_argument(flag, required=True)
    ap.add_argument("--membership-status", type=_status)
    ap.add_argument("--classify-only", action="store_true")
    a = ap.parse_args(argv)
    if a.classify_only == (a.membership_status is not None):
        ap.error("give exactly one of --classify-only and --membership-status")
    try:
        return run_gate(a.repo, a.event, a.pr, a.out, a.membership_status, classify_only=a.classify_only)
    except Exception as exc:  # noqa: BLE001 - never Python's default exit 1, which would read as a rejection
        sys.stderr.write(f"ERROR (internal, not a rejection): {type(exc).__name__}: {exc}\n")
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
