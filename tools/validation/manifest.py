"""Restricted, static reader for `mod.lua` (task 008a, decision Q-C, Ludwig 2026-10-14).

`mod.lua` is a Lua file that `return`s a table (ADR-0030). The pipeline must never EXECUTE
attacker-supplied Lua, so this module does not run it: it tokenises and parses a tiny
literal-only subset and refuses everything else with a named message.

Accepted:  `return { ... }` (optionally a trailing `;`), where values are string literals
           (quoted with escapes, or long brackets), numbers, `true`, `false`, `nil`, and nested
           table constructors; keys are `name = v`, `["str"] = v`, `[number] = v`, or positional;
           `--` line comments and `--[[ ]]` / `--[==[ ]==]` block comments.
Rejected:  function calls (`f(x)`, `f"x"`, `f{...}`), `require`, `dofile` and the other loaders,
           string concatenation (`..`) and every other operator, bare identifiers (variables),
           statements before `return`, unterminated strings/comments, a file that does not
           return a table, duplicate keys, trailing content after the table.

Never reads or imports anything else; the input is bytes decoded as UTF-8 text.
`project()` keeps only the eleven fields manifest.schema.json lists; kernel-only keys
(`depends`, `permissions`, ...) were parsed (so their syntax is still checked) and are then
ignored. Each failure raises `ManifestError` whose `.rule` is a stable short name.
"""

from __future__ import annotations

import re
from typing import Any

PROJECTED_FIELDS = (
    "id", "name", "version", "api_version", "license", "source",
    "type", "description", "tags", "screenshots", "ai_assisted",
)

_FORBIDDEN_LOADERS = frozenset(
    ["require", "dofile", "loadfile", "load", "loadstring", "import", "include", "execute"]
)
MAX_DEPTH = 32
MAX_BYTES = 1 << 20


class ManifestError(Exception):
    def __init__(self, rule: str, message: str, line: int | None = None):
        where = f" (line {line})" if line else ""
        super().__init__(f"{rule}: {message}{where}")
        self.rule = rule
        self.message = message
        self.line = line


class _Table:
    __slots__ = ("array", "hash")

    def __init__(self) -> None:
        self.array: list[Any] = []
        self.hash: dict[Any, Any] = {}


_NIL = object()  # distinguishes a parsed `nil` literal from "absent"

_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUM_RE = re.compile(r"0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_LONG_OPEN_RE = re.compile(r"\[(=*)\[")
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f", "v": "\v",
            "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
# Longest first.
_SYMBOLS = ("...", "..", "==", "~=", "<=", ">=", "//", "::", "<<", ">>",
            "{", "}", "[", "]", "(", ")", ",", ";", "=", "-", "+", "*", "/", "%", "^", "#",
            "<", ">", ":", ".", "&", "|", "~")


def _tokenise(src: str) -> list[tuple[str, Any, int]]:
    toks: list[tuple[str, Any, int]] = []
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f\v":
            i += 1
            continue
        if src.startswith("--", i):
            m = _LONG_OPEN_RE.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                end = src.find(close, m.end())
                if end < 0:
                    raise ManifestError("unterminated-comment", "block comment is never closed", line)
                line += src.count("\n", i, end)
                i = end + len(close)
            else:
                end = src.find("\n", i)
                i = n if end < 0 else end
            continue
        if c in "\"'":
            quote, j, buf, start_line = c, i + 1, [], line
            while True:
                if j >= n:
                    raise ManifestError("unterminated-string", "string literal is never closed", start_line)
                d = src[j]
                if d == quote:
                    j += 1
                    break
                if d == "\n":
                    raise ManifestError("unterminated-string", "string literal runs into a newline", start_line)
                if d == "\\":
                    j += 1
                    if j >= n:
                        raise ManifestError("unterminated-string", "string ends inside an escape", start_line)
                    e = src[j]
                    if e in _ESCAPES:
                        if e == "\n":
                            line += 1
                        buf.append(_ESCAPES[e])
                        j += 1
                    elif e == "x":
                        h = src[j + 1:j + 3]
                        if not re.fullmatch(r"[0-9a-fA-F]{2}", h):
                            raise ManifestError("bad-escape", "\\x needs two hex digits", line)
                        buf.append(chr(int(h, 16)))
                        j += 3
                    elif e.isdigit():
                        m = re.match(r"\d{1,3}", src[j:])
                        v = int(m.group(0))
                        if v > 255:
                            raise ManifestError("bad-escape", "decimal escape above 255", line)
                        buf.append(chr(v))
                        j += len(m.group(0))
                    else:
                        raise ManifestError("bad-escape", f"unsupported escape \\{e}", line)
                    continue
                buf.append(d)
                j += 1
            toks.append(("STRING", "".join(buf), start_line))
            i = j
            continue
        m = _LONG_OPEN_RE.match(src, i)
        if m:
            close = "]" + m.group(1) + "]"
            end = src.find(close, m.end())
            if end < 0:
                raise ManifestError("unterminated-string", "long string is never closed", line)
            text = src[m.end():end]
            if text.startswith("\n"):
                text = text[1:]
            toks.append(("STRING", text, line))
            line += src.count("\n", i, end)
            i = end + len(close)
            continue
        m = _NAME_RE.match(src, i)
        if m:
            toks.append(("NAME", m.group(0), line))
            i = m.end()
            continue
        m = _NUM_RE.match(src, i)
        if m:
            t = m.group(0)
            try:
                v: Any = int(t, 16) if t[:2].lower() == "0x" else (int(t) if t.isdigit() else float(t))
            except ValueError:
                raise ManifestError("bad-number", f"malformed number {t!r}", line)
            toks.append(("NUMBER", v, line))
            i = m.end()
            continue
        for s in _SYMBOLS:
            if src.startswith(s, i):
                toks.append(("SYM", s, line))
                i += len(s)
                break
        else:
            raise ManifestError("bad-character", f"unexpected character {c!r}", line)
    toks.append(("EOF", None, line))
    return toks


class _Parser:
    def __init__(self, toks):
        self.toks = toks
        self.p = 0

    def peek(self, k=0):
        return self.toks[min(self.p + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.p]
        self.p += 1
        return t

    def is_sym(self, s, k=0):
        t = self.peek(k)
        return t[0] == "SYM" and t[1] == s

    def parse_file(self) -> _Table:
        kind, val, line = self.peek()
        if kind == "NAME" and val in _FORBIDDEN_LOADERS:
            raise ManifestError("forbidden-call", f"`{val}` is not allowed: mod.lua is never executed", line)
        if not (kind == "NAME" and val == "return"):
            raise ManifestError("no-return", "mod.lua must consist of `return { ... }` and nothing before it", line)
        self.next()
        if not self.is_sym("{"):
            raise ManifestError("not-a-table", "`return` must be followed by a table constructor", self.peek()[2])
        table = self.table(0)
        if self.is_sym(";"):
            self.next()
        kind, val, line = self.peek()
        if kind != "EOF":
            self.reject_operator_or_junk(kind, val, line)
            raise ManifestError("trailing-content", f"unexpected {val!r} after the returned table", line)
        return table

    def reject_operator_or_junk(self, kind, val, line):
        if kind == "SYM" and val == "..":
            raise ManifestError("concatenation", "string concatenation (`..`) is not allowed", line)
        if kind == "SYM" and val == "(":
            raise ManifestError("function-call", "a function call is not allowed", line)

    def table(self, depth: int) -> _Table:
        if depth > MAX_DEPTH:
            raise ManifestError("too-deep", f"tables nested deeper than {MAX_DEPTH}", self.peek()[2])
        self.next()  # {
        t = _Table()
        while True:
            if self.is_sym("}"):
                self.next()
                return t
            kind, val, line = self.peek()
            if kind == "EOF":
                raise ManifestError("unterminated-table", "table is never closed", line)
            if kind == "NAME" and self.is_sym("=", 1) and not self.is_sym("==", 1):
                self.next(); self.next()
                self.put(t, val, self.value(depth), line)
            elif self.is_sym("["):
                self.next()
                k, kv, kl = self.next()
                if k not in ("STRING", "NUMBER"):
                    raise ManifestError("bad-key", "a computed key is not allowed; use a literal", kl)
                if not self.is_sym("]"):
                    raise ManifestError("bad-key", "expected `]` after the key", self.peek()[2])
                self.next()
                if not self.is_sym("="):
                    raise ManifestError("bad-key", "expected `=` after `[key]`", self.peek()[2])
                self.next()
                self.put(t, kv, self.value(depth), line)
            else:
                t.array.append(self.value(depth))
            if self.is_sym(",") or self.is_sym(";"):
                self.next()
            elif self.is_sym("}"):
                continue
            else:
                kind, val, line = self.peek()
                if kind == "EOF":
                    raise ManifestError("unterminated-table", "table is never closed", line)
                self.reject_operator_or_junk(kind, val, line)
                raise ManifestError("syntax", f"expected `,` or `}}`, found {val!r}", line)

    def put(self, t: _Table, key, value, line):
        if key in t.hash:
            raise ManifestError("duplicate-key", f"key {key!r} is set twice in one table", line)
        t.hash[key] = value

    def value(self, depth: int):
        kind, val, line = self.peek()
        if kind == "STRING":
            self.next()
            result: Any = val
        elif kind == "NUMBER":
            self.next()
            result = val
        elif kind == "SYM" and val == "-" and self.peek(1)[0] == "NUMBER":
            self.next()
            result = -self.next()[1]
        elif kind == "SYM" and val == "{":
            result = self.table(depth + 1)
        elif kind == "NAME":
            if val in ("true", "false", "nil"):
                self.next()
                result = {"true": True, "false": False, "nil": _NIL}[val]
            elif val in _FORBIDDEN_LOADERS:
                raise ManifestError("forbidden-call", f"`{val}` is not allowed: mod.lua is never executed", line)
            elif val == "function":
                raise ManifestError("function-call", "function definitions are not allowed", line)
            elif self.is_sym("(", 1) or self.peek(1)[0] == "STRING" or self.is_sym("{", 1) \
                    or self.is_sym(".", 1) or self.is_sym(":", 1):
                raise ManifestError("function-call", f"call to `{val}` is not allowed: mod.lua is never executed", line)
            else:
                raise ManifestError("variable", f"identifier `{val}` is not a literal; only literal values are allowed", line)
        else:
            self.reject_operator_or_junk(kind, val, line)
            raise ManifestError("syntax", f"expected a value, found {val!r}", line)
        # A value must be followed by a separator or the end of the table; an operator after it is
        # named explicitly (the most likely attack shapes).
        nk, nv, nl = self.peek()
        if nk == "SYM" and nv == "..":
            raise ManifestError("concatenation", "string concatenation (`..`) is not allowed", nl)
        if nk == "SYM" and nv in ("(", "+", "-", "*", "/", "%", "^", "#", "==", "~=", "<", ">", "<=", ">=", "&", "|", "~", "<<", ">>", "//", ":", "."):
            if nv == "(":
                raise ManifestError("function-call", "a function call is not allowed", nl)
            raise ManifestError("operator", f"operator {nv!r} is not allowed; only literal values are allowed", nl)
        return result


def _to_python(v: Any, path: str) -> Any:
    if v is _NIL:
        return None
    if isinstance(v, _Table):
        if v.array and v.hash:
            raise ManifestError("mixed-table", f"{path} mixes positional and keyed entries")
        if v.hash:
            return {str(k): _to_python(x, f"{path}.{k}") for k, x in v.hash.items()}
        return [_to_python(x, f"{path}[{i + 1}]") for i, x in enumerate(v.array)]
    return v


def parse_manifest_text(text: str) -> _Table:
    if len(text.encode("utf-8", "surrogatepass")) > MAX_BYTES:
        raise ManifestError("too-large", f"mod.lua exceeds {MAX_BYTES} bytes")
    return _Parser(_tokenise(text)).parse_file()


def read_manifest(data: bytes) -> dict:
    """Parse `mod.lua` bytes and return the projection: only the eleven manifest fields, as
    plain Python values. Fields set to `nil` are treated as absent."""
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ManifestError("not-utf8", f"mod.lua is not valid UTF-8: {exc}")
    if "\x00" in text:
        raise ManifestError("bad-character", "NUL byte in mod.lua")
    table = parse_manifest_text(text)
    out: dict = {}
    for key in PROJECTED_FIELDS:
        if key in table.hash:
            value = _to_python(table.hash[key], key)
            if value is not None:
                out[key] = value
    return out
