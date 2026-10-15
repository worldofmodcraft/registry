"""Shared verdict shape and exit codes for the registry checkers (task 007a; used by 007b too).

Every checker returns a plain dict (a *verdict*) built by `make()`:

    {"checker": "classify" | "schema" | "append-only" | ...,
     "verdict": "accepted" | "rejected",            # "rejected" iff findings is non-empty
     "findings": [ {"rules": [...], "path": str|None, "index": int|None, "message": str}, ... ],
     ...checker-specific keys (classify: "class"; append-only: "elements", "authority_required")}

`rules` is always a LIST of rule ids (one finding may break several rules at once, e.g.
["rule 2", "rule 4"]). Every `message` names what was wrong, cites the rule or ADR clause, and says what
to do about it (see `finding`).

Why this is not contracts/validation-report.schema.json: that schema is the asset scanner's report
(per-file inspected/accepted/rejected lists for a directory scan, edges E5/E6). It has no place for a
rule-id list, a per-element transition classification or an authority list, so it does not fit; this
module defines the registry-checker shape instead and does not pretend the two are one convention.

Exit codes (three DISTINCT meanings; reading a usage error as a rejection once produced a completely
false verification on this project, OPERATIONS.md):

    0  EXIT_ACCEPTED  the checker accepts the input
    1  EXIT_REJECTED  the checker rejects the input (the verdict names why)
    2  EXIT_ERROR     usage or internal error: the checker could not decide. NOT a rejection.
"""

import json
import sys

EXIT_ACCEPTED = 0
EXIT_REJECTED = 1
EXIT_ERROR = 2


class ToolError(Exception):
    """The checker could not decide (bad arguments, unreadable input, unsupported schema keyword).
    Maps to EXIT_ERROR, never to a rejection."""


def finding(rules, what, fix, cite, path=None, index=None):
    """One finding. `rules` is a list of rule ids; the message is '<rules> (<cite>): <what>. To fix: <fix>'."""
    if not isinstance(rules, list) or not rules:
        raise ToolError("internal: a finding needs a non-empty list of rule ids")
    return {"rules": list(rules), "path": path, "index": index,
            "message": f"{' + '.join(rules)} ({cite}): {what}. To fix: {fix}"}


def make(checker, findings, **extra):
    v = {"checker": checker, "verdict": "rejected" if findings else "accepted", "findings": findings}
    v.update(extra)
    return v


def exit_code(verdict):
    return EXIT_REJECTED if verdict["findings"] else EXIT_ACCEPTED


def emit(verdict, out=None, err=None):
    """JSON verdict on stdout; one human-readable line per finding on stderr."""
    (out or sys.stdout).write(json.dumps(verdict, indent=2, sort_keys=True) + "\n")
    for f in verdict["findings"]:
        (err or sys.stderr).write(f"REJECTED {f['message']}\n")


def run(main, argv):
    """Run `main(argv) -> verdict`, map ToolError and any unexpected exception to EXIT_ERROR."""
    try:
        verdict = main(argv)
    except ToolError as exc:
        sys.stderr.write(f"ERROR (usage or internal, not a rejection): {exc}\n")
        return EXIT_ERROR
    except Exception as exc:  # noqa: BLE001 - an unexpected crash must be exit 2, never exit 1
        sys.stderr.write(f"ERROR (internal, not a rejection): {type(exc).__name__}: {exc}\n")
        return EXIT_ERROR
    emit(verdict)
    return exit_code(verdict)
