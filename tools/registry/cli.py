#!/usr/bin/env python3
"""Command line for the registry shape checkers (task 007a). Offline, standard library only.

    python3 tools/registry/cli.py classify    --reserved-file MERGE_BASE_reserved-namespaces.json (PATH... | --paths-file FILE)
    python3 tools/registry/cli.py schema      --root DIR PATH...
    python3 tools/registry/cli.py append-only --old-root DIR --new-root DIR PATH...

PATHs are repository-relative changed paths. For `schema`, a PATH missing under --root is a deleted file.
For `append-only`, a PATH missing under a root is absent on that side (--old-root is the merge-base
checkout, --new-root the PR branch); only entry.json paths are compared, page.json is not append-only.
The reserved list given to `classify` MUST be the merge-base revision of reserved-namespaces.json
(ownership.md I4), never the PR's own copy.

Output: a JSON verdict on stdout (shape in report.py), one 'REJECTED ...' line per finding on stderr.
Exit codes: 0 accepted, 1 rejected, 2 usage or internal error (NOT a rejection).

WARNING: `append-only` alone never authorises a merge. Its verdict lists `authority_required` (T1/T2/T3);
when that list is non-empty an 'accepted' exit only means the SHAPE is legal. Who may carry T1/T3 and who
may open a takedown is the ownership checker's (task 007b); task 039 must run it as well.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # so `python3 -I cli.py` finds its siblings

import append_only  # noqa: E402
import classify  # noqa: E402
import report  # noqa: E402
import schema  # noqa: E402


def _read(root, rel):
    """(parsed-or-None, parse-error-or-None) for root/rel; a missing file is (None, None)."""
    p = Path(root) / rel
    if classify.parse_mod_path(rel) is None or not p.is_file():  # never read a path outside the R1 form
        return None, None
    try:
        return json.loads(p.read_text()), None
    except (ValueError, UnicodeDecodeError) as exc:
        return None, f"{rel} is not valid JSON ({exc})"
    except OSError as exc:
        raise report.ToolError(f"cannot read {p}: {exc}") from exc


def _parse_error_findings(errors):
    return [report.finding(["json-syntax"], err, "fix the JSON syntax", "E2/E4: the file must parse", path=rel)
            for rel, err in errors]


def _cmd_classify(a):
    paths = list(a.paths)
    if a.paths_file:
        try:
            text = sys.stdin.read() if a.paths_file == "-" else Path(a.paths_file).read_text()
        except OSError as exc:
            raise report.ToolError(f"cannot read paths file: {exc}") from exc
        paths += [line for line in text.split("\n") if line != ""]
    try:
        reserved = json.loads(Path(a.reserved_file).read_text())
    except (OSError, ValueError) as exc:
        raise report.ToolError(f"cannot read the merge-base reserved list {a.reserved_file}: {exc}") from exc
    return classify.classify(paths, reserved)


def _cmd_schema(a):
    files, errors = {}, []
    for rel in a.paths:
        doc, err = _read(a.root, rel)
        if err:
            errors.append((rel, err))
        else:
            files[rel] = doc
    v = schema.check(files)
    v["findings"] += _parse_error_findings(errors)
    return report.make("schema", v["findings"], results=v["results"])


def _cmd_append_only(a):
    pairs, errors = {}, []
    for rel in a.paths:
        old, e1 = _read(a.old_root, rel)
        new, e2 = _read(a.new_root, rel)
        errors += [(rel, e) for e in (e1, e2) if e]
        if not (e1 or e2):
            pairs[rel] = (old, new)
    v = append_only.check_pr(pairs)
    v["findings"] += _parse_error_findings(errors)
    return report.make("append-only", v["findings"], **{k: x for k, x in v.items()
                                                       if k not in ("checker", "verdict", "findings")})


def main(argv):
    ap = argparse.ArgumentParser(prog="registry-checkers", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("classify")
    c.add_argument("--reserved-file", required=True)
    c.add_argument("--paths-file")
    c.add_argument("paths", nargs="*")
    c.set_defaults(fn=_cmd_classify)
    s = sub.add_parser("schema")
    s.add_argument("--root", required=True)
    s.add_argument("paths", nargs="+")
    s.set_defaults(fn=_cmd_schema)
    o = sub.add_parser("append-only")
    o.add_argument("--old-root", required=True)
    o.add_argument("--new-root", required=True)
    o.add_argument("paths", nargs="+")
    o.set_defaults(fn=_cmd_append_only)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(report.run(main, sys.argv[1:]))
