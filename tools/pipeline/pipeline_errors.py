"""Exception types that carry the pipeline's two failure exit codes.

`Rejected`      -> exit 1: the version being built is bad. Names the rule and the remedy.
`PipelineError` -> exit 2: usage or internal error (missing tool, clone failure, scanner exit 2).
Never conflated (OPERATIONS.md): a 2 is never a rejection, a 1 is never an outage.
"""

from __future__ import annotations


class Rejected(Exception):
    def __init__(self, rule: str, message: str, remedy: str):
        super().__init__(message)
        self.rule = rule
        self.message = message
        self.remedy = remedy

    def __str__(self) -> str:
        return f"REJECTED [{self.rule}]: {self.message} -- remedy: {self.remedy}"


class PipelineError(Exception):
    """Exit 2: not a statement about the version."""
