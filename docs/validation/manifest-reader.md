# Manifest reader (`tools/validation/manifest.py`)

`mod.lua` is a Lua file that `return`s a table (ADR-0030). The registry pipeline must read the
eleven fields of `contracts/manifest.schema.json` out of an **attacker-supplied** file, so it
**never executes it**. `manifest.py` is a restricted static reader (decision Q-C, Ludwig,
2026-10-14): a tokeniser and a recursive-descent parser for a literal-only subset of Lua. It imports
nothing but `re`; the input is bytes decoded as strict UTF-8.

## What it accepts

`return { ... }`, optionally followed by `;`, where the values are string literals (single or double
quoted with the usual escapes, or long brackets `[[ ]]` / `[==[ ]==]`), numbers (decimal, hex,
exponent, unary minus), `true`, `false`, `nil` and nested table constructors. Table keys are
`name = v`, `["str"] = v`, `[number] = v` or positional. `,` and `;` separate entries. `--` line
comments and `--[[ ]]` / `--[==[ ]==]` block comments are skipped. Kernel-only keys (`depends`,
`permissions`, `server`, ...) are *parsed* (their syntax is checked) and then ignored by the
projection.

## What it rejects (each with a stable rule name, `ManifestError.rule`)

| Rule | Input |
|---|---|
| `function-call` | `f(x)`, `f"x"`, `f{...}`, `a.b(...)`, `x:m()`, `function ...` |
| `forbidden-call` | `require`, `dofile`, `loadfile`, `load`, `loadstring`, `import`, `include`, `execute` |
| `concatenation` | `"a" .. "b"` |
| `operator` | `1 + 2`, comparison and bitwise operators |
| `variable` | a bare identifier used as a value |
| `no-return` | any statement before `return`, or no `return` at all |
| `not-a-table` | `return "string"` |
| `unterminated-string` / `unterminated-comment` / `unterminated-table` | the obvious |
| `trailing-content` | anything after the returned table |
| `duplicate-key` | the same key twice in one table |
| `mixed-table` | a projected field that mixes positional and keyed entries |
| `bad-escape`, `bad-number`, `bad-character`, `bad-key`, `syntax`, `too-deep`, `too-large`, `not-utf8` | malformed input; nesting above 32, size above 1 MiB |

## Projection

`read_manifest(bytes) -> dict` returns only `id, name, version, api_version, license, source, type,
description, tags, screenshots, ai_assisted`, as plain Python values. An empty table is a list; a
field set to `nil` is absent. The result is then validated against `manifest.schema.json` by the
pipeline (`tools/pipeline/build_version.py`), which also checks `id` and `version` against the
entry.

## Limits

This is **not** a Lua implementation: a manifest that is valid Lua but uses an expression, a local
or a helper function is rejected by design, with a message that names the construct. Tests:
`tests/pipeline/test_manifest_reader.py`.
