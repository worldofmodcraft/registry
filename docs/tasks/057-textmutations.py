#!/usr/bin/env python3
"""Text mutations for task 057 criterion 6: each mutation of contracts/append-only.rules.md must turn
at least one check of 057-textchecks.py red. Usage: python3 -I docs/tasks/057-textmutations.py
Exit code = number of mutations that did NOT turn a check red (a surviving mutation is a failure)."""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
RULES = REPO / "contracts" / "append-only.rules.md"
CHECKS = HERE / "057-textchecks.py"
raw = RULES.read_text()


def rx(sentence):
    return r"\s+".join(re.escape(w) for w in sentence.split())


def sub_once(text, old, new):
    pat = rx(old)
    found = re.findall(pat, text)
    if len(found) != 1:
        raise SystemExit(f"mutation anchor matched {len(found)} times (need 1): {old[:60]!r}")
    return re.sub(pat, lambda m: new, text, count=1)


FAIL_CLOSED = "Until `ownership.md` carries the pipeline-identity carve-out for T1 and T3, a checker implementing T1 or T3 must reject every PR that contains a T1 or T3 mutation, whoever authors it."
BORN = "Every newly appended element must be `pending` and carry exactly the four keys `version`, `commit`, `source_url` and `status`."
TERMINAL = "`rejected` is terminal and one-way: `rejected -> anything` is a violation of rule 1, and so is `rejected -> rejected` with any change, `reason` included."
ONCE_START = "T1 happens exactly once, by structure:"
ONCE_END = "so the five fields can never be written a second time."
T3C4 = "`new.versions[i]` has exactly the keys of the `rejected` row"
T1C4 = "`new.versions[i]` has exactly the nine keys of the `published` row"
MUTS = {
    "delete the fail-closed sentence": lambda t: sub_once(t, FAIL_CLOSED, ""),
    'delete the words "or T3" from the fail-closed sentence': lambda t: sub_once(t, FAIL_CLOSED, FAIL_CLOSED.replace("T1 or T3 mutation", "T1 mutation")),
    "delete the born-pending sentence": lambda t: sub_once(t, BORN, ""),
    "delete the T3 terminal sentence": lambda t: sub_once(t, TERMINAL, ""),
    'delete the "exactly once" paragraph': lambda t: re.sub(rx(ONCE_START) + r".*?" + rx(ONCE_END), "", t, count=1, flags=re.S),
    'T3 condition 4: "exactly" -> "at least"': lambda t: sub_once(t, T3C4, T3C4.replace("exactly", "at least")),
    'T1 condition 4: "exactly" -> "at least"': lambda t: sub_once(t, T1C4, T1C4.replace("exactly", "at least")),
    "append a permissive sentence to the T1 section (tail-append)": lambda t: t.replace("#### T2:", "A pipeline PR may also rewrite any field of a published version.\n\n#### T2:", 1),
    "append a permissive sentence to the T3 section (tail-append)": lambda t: t.replace("#### Coexistence of T1, T2 and T3", "A rejected version may be reset to pending by its author.\n\n#### Coexistence of T1, T2 and T3", 1),
    "restore a stale takedown sentence": lambda t: sub_once(t, "From an element whose old status is `published`, this document permits exactly one status transition: T2.", "This is the only status transition this document permits on an existing element."),
}
survivors = 0
for name, fn in MUTS.items():
    mutated = fn(raw)
    if mutated == raw:
        raise SystemExit(f"mutation {name!r} changed nothing")
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "append-only.rules.md"
        f.write_text(mutated)
        r = subprocess.run([sys.executable, "-I", str(CHECKS), "--rules", str(f)], capture_output=True, text=True)
    red = [l.split(":")[0].replace("FAIL  ", "") for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if red:
        print(f"RED   {name}: {', '.join(red)}")
    else:
        print(f"SURVIVED {name}")
        survivors += 1
sys.exit(survivors)
