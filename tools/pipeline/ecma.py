"""Schema patterns with the registry gate's ECMA-262 semantics (task 094, node N5 reusing node N3's translator).

The registry gate validates every string pattern with `re.search(schema.ecma_pattern(p), s)` (tools/registry/schema.py,
`_strict_patterns`). `matches` below is that exact expression, so the pipeline gives the gate's verdict for every pattern in
contracts/entry.schema.json: `\\d` is ASCII-only, `\\s`/`\\S` are ECMA-262's WhiteSpace + LineTerminator set (U+FEFF is white
space; U+001C-U+001F and U+0085 are not), `$` is end of input only. The translator is NOT copied here and NOT moved
(tools/registry/schema.py is pinned by closed scripts 034, 064 and 007b); it is loaded from that file.

Import direction is one way: tools/pipeline -> tools/registry. Nothing under tools/registry imports tools/pipeline.

A construct the translator does not support raises NotImplementedError; it propagates from `matches` (never caught): an
unsupported pattern must be a visible error, not a verdict.
"""

from __future__ import annotations

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))


def _load_gate_schema():
    """Load tools/registry/schema.py by path under a private module name. The file imports `classify` and `report` (next to it)
    and `schema_check` (tests/contracts) by bare name, so sys.path is extended for the import only, and those three names in
    sys.modules are put back afterwards: this loader cannot shadow, or be shadowed by, another module of the same name
    (tests/validation/schema_check.py is one). Bytecode writing is switched off for the load and restored afterwards, so merely
    importing this module never leaves a __pycache__ in tools/registry or tests/contracts (task 094 review F3)."""
    registry = os.path.join(REPO, "tools", "registry")
    names = ("classify", "report", "schema_check")
    saved_modules = {n: sys.modules.pop(n, None) for n in names}
    saved_path = list(sys.path)
    saved_bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    sys.path[:0] = [registry, os.path.join(REPO, "tests", "contracts")]
    try:
        spec = importlib.util.spec_from_file_location("wom_pipeline_gate_schema", os.path.join(registry, "schema.py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.dont_write_bytecode = saved_bytecode
        sys.path[:] = saved_path
        for name, previous in saved_modules.items():
            if previous is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = previous


schema = _load_gate_schema()


def matches(pattern: str, value) -> bool:
    """True when `value` is a str that the gate's `re.search(ecma_pattern(pattern), value)` accepts. A non-str never matches."""
    return isinstance(value, str) and re.search(schema.ecma_pattern(pattern), value) is not None
