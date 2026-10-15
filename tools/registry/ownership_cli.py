#!/usr/bin/env python3
"""Command line for the registry ownership checker (task 007b, edge E16). Offline, standard library only.

    python3 tools/registry/ownership_cli.py --author-provider github --author-id N [--author-login NAME]
        --old-root DIR --new-root DIR --reserved-file MERGE_BASE_reserved-namespaces.json
        [--membership-status HTTP_STATUS] [--r11-identity PROVIDER:ID] PATH...

PATHs are repository-relative changed paths (`git diff --no-renames`). --old-root is the merge-base checkout and
--new-root the PR branch; a PATH missing under a root is absent on that side. The reserved list MUST be the
merge-base revision of reserved-namespaces.json (I4). The author id MUST be the PR object's `pulls.user.id`
(I1), never a commit author or GITHUB_ACTOR. --membership-status is the recorded HTTP status of the one live
question "is the author a member of the reserved namespace's organisation" (204 member, 404 not, anything else,
or no value at all, is R9's closed rejection); task 039 makes that call. --r11-identity defaults to none, and
none means R11 authorises nobody: every takedown PR is rejected.

Output: a JSON verdict on stdout, one 'REJECTED ...' line per finding on stderr.
Exit codes: 0 accepted, 1 rejected, 2 usage or internal error (NOT a rejection).

WARNING: this checker's `accepted` is NEVER a merge signal on its own (ownership.md I8). Task 039 must compose it
with the shape checkers (cli.py classify / schema / append-only), and MANAGER.md section 7 still requires Ludwig's
written approval before a takedown is merged. T1/T3 (pipeline transitions) are rejected for every author until
task 008b amends ownership.md (ADR-0121 fail-closed).
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # so `python3 -I ownership_cli.py` finds its siblings

import classify  # noqa: E402
import cli  # noqa: E402
import ownership  # noqa: E402
import report  # noqa: E402


def _oracle(status):
    def ask(org, author):
        if status is None:
            raise report.ToolError("no --membership-status was supplied")
        return status
    return ask


def main(argv):
    ap = argparse.ArgumentParser(prog="registry-ownership", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--author-provider", required=True)
    ap.add_argument("--author-id", required=True, type=int)
    ap.add_argument("--author-login")
    ap.add_argument("--old-root", required=True)
    ap.add_argument("--new-root", required=True)
    ap.add_argument("--reserved-file", required=True)
    ap.add_argument("--membership-status", type=int)
    ap.add_argument("--r11-identity")
    ap.add_argument("paths", nargs="+")
    a = ap.parse_args(argv)
    try:
        reserved = json.loads(Path(a.reserved_file).read_text())
    except (OSError, ValueError) as exc:
        raise report.ToolError(f"cannot read the merge-base reserved list {a.reserved_file}: {exc}") from exc
    r11 = None
    if a.r11_identity:
        prov, _, ident = a.r11_identity.rpartition(":")
        if not prov or not ident.isdigit():
            raise report.ToolError("--r11-identity must be PROVIDER:NUMERIC_ID")
        r11 = (prov, int(ident))
    files, errors, base = {}, [], {}
    for rel in a.paths:
        old, e1 = cli._read(a.old_root, rel)
        new, e2 = cli._read(a.new_root, rel)
        errors += [(rel, e) for e in (e1, e2) if e]
        files[rel] = (old, new)
        p = classify.parse_mod_path(rel)
        if p is not None and p[2] == "page":
            sib = f"mods/{p[0]}.{p[1]}/entry.json"
            entry, err = cli._read(a.old_root, sib)
            errors += [(sib, err)] if err else []
            if entry is not None:
                base[sib] = entry
    owners, src = {}, {}  # namespace -> owner pair, from EVERY merge-base entry.json (never from the PR's files)
    for d in sorted(Path(a.old_root, "mods").glob("*")):
        p = classify.parse_mod_path(f"mods/{d.name}/entry.json")
        if p is None:
            continue
        entry, err = cli._read(a.old_root, f"mods/{d.name}/entry.json")
        if err:
            errors.append((f"mods/{d.name}/entry.json", err))
        elif entry is not None:
            pair = ownership._owner_pair(entry)
            if pair is None:
                raise report.ToolError(f"the merge-base mods/{d.name}/entry.json has no well-formed owner")
            if p[0] in owners and owners[p[0]] != pair:
                raise report.ToolError(
                    f"merge-base entries of namespace {p[0]!r} disagree on the owner: mods/{p[0]}.{src[p[0]]}/entry.json "
                    f"says {owners[p[0]]!r}, mods/{d.name}/entry.json says {pair!r}; the registry is inconsistent "
                    "and the check cannot decide")
            owners.setdefault(p[0], pair)
            src.setdefault(p[0], d.name.split(".", 1)[1])
    if errors:  # a file we cannot parse unambiguously is not evidence; reject, never guess
        return report.make("ownership", cli._parse_error_findings(errors), merge_signal=False)
    return ownership.check((a.author_provider, a.author_id), files, reserved, _oracle(a.membership_status),
                           login=a.author_login, r11_identity=r11, base_entries=base, namespace_owners=owners)


if __name__ == "__main__":
    sys.exit(report.run(main, sys.argv[1:]))
