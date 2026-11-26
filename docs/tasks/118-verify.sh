#!/usr/bin/env bash
#
# 118-verify.sh -- the runnable verification artefact for task 118 (MANAGER.md Section 2c).
#
# Task 118: contracts/ownership.md gains R12 (the pipeline identity's carve-out for T1 and T3) and I9.
#
# Usage (run from the repository root, in a fresh clone of the pushed branch):
#   npm ci --prefix tools/dev          # once; 057-verify.sh check V1 needs Ajv
#   bash docs/tasks/118-verify.sh            # all checks: criteria 1-6, 8, 9 (text) and 10 (closed scripts)
#   bash docs/tasks/118-verify.sh --mutate   # criterion 11: each mutation of ownership.md must turn a text check red
#
# Text checks (criteria 1-6, 8, 9) read contracts/ownership.md and contracts/append-only.rules.md, or the
# copies named by the env vars OWN and APPEND (the mutation mode uses that; it never edits a tracked file,
# so "restored byte-identically" is shown by a sha256 taken before and after).
# Criterion 10 runs 032-verify.sh, 032-mutations.sh and 057-verify.sh and diffs the closed artefacts against
# BASE (registry origin/main e213cbc, the commit this task was cut from).
# Criteria 7 and 12 are read by the reviewer and are not checked here.
set -u
BASE=${BASE:-e213cbce9a2b33f70e72c564be377085a3045640}
OWN=${OWN:-contracts/ownership.md}
APPEND=${APPEND:-contracts/append-only.rules.md}
MODE=${1:-check}
export BASE OWN APPEND

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export TMPD

cat > "$TMPD/checks.py" <<'PY'
import difflib, hashlib, json, os, re, shutil, subprocess, sys
from pathlib import Path

OWN, APPEND, BASE = os.environ["OWN"], os.environ["APPEND"], os.environ["BASE"]
SPLIT = re.compile(r'(?<=[.:;!?])\s+')


def flat(s):
    return ' '.join(s.replace('**', '').split())


class Doc:
    def __init__(self, text):
        self.text = text
        self.paras = re.split(r'\n\s*\n', text)
        self.decl = {}
        for p in self.paras:
            f = ' '.join(p.split())
            m = re.match(r'^\*\*([RI]\d+) \(MUST(?: NOT)?\)\*\*', f)
            if m:
                self.decl.setdefault(m.group(1), []).append(f)
        n = re.sub(r'\*\*', '', text)
        self.norm = ' '.join(n.split())

    def para(self, rid):
        got = self.decl.get(rid, [])
        return flat(got[0]) if got else ""

    def section(self, start, end):
        """Text from the heading containing `start` up to the heading containing `end`."""
        lines = self.text.splitlines()
        i = next((k for k, l in enumerate(lines) if l.startswith('## ') and start in l), None)
        j = next((k for k, l in enumerate(lines) if l.startswith('## ') and end in l and (i is not None and k > i)), None)
        if i is None or j is None:
            return ""
        return flat('\n'.join(lines[i:j]))

    def taxonomy_rows(self):
        rows = {}
        for l in self.text.splitlines():
            m = re.match(r'^\|\s*`(R\d+)`\s*\|(.*)\|\s*$', l)
            if m:
                rows.setdefault(m.group(1), []).append(flat(m.group(2)))
        return rows


def text_checks(own_text, app_text):
    """Return a list of (label, ok, detail) for criteria 1-6, 8, 9."""
    out = []

    def chk(label, ok, detail=""):
        out.append((label, bool(ok), detail))

    d = Doc(own_text)
    r12 = d.para("R12")
    r3, r7, r11 = d.para("R3"), d.para("R7"), d.para("R11")
    i9 = d.para("I9")
    sec = d.section("Pipeline write-back", "Questions")
    heads = [l for l in own_text.splitlines() if l.startswith('## ')]

    def contains(label, hay, *needles):
        miss = [n for n in needles if flat(n) not in hay]
        chk(label, not miss, "missing: %s" % miss)

    # ---- criterion 1: R12 declared once, in its own paragraph, in the right place, with the right content
    chk("C1.1 R12 is declared exactly once, at the start of its own paragraph", len(d.decl.get("R12", [])) == 1,
        "%d declarations" % len(d.decl.get("R12", [])))
    ti = next((k for k, h in enumerate(heads) if h.startswith("## Takedown PRs")), None)
    pi = next((k for k, h in enumerate(heads) if "Pipeline write-back" in h), None)
    qi = next((k for k, h in enumerate(heads) if h == "## Questions"), None)
    chk("C1.2 R12's section sits after the takedown section and before `## Questions`",
        None not in (ti, pi, qi) and ti < pi < qi, "heading indices takedown=%s pipeline=%s questions=%s" % (ti, pi, qi))
    chk("C1.3 R12's section lies after the takedown section's R11 and I8 paragraphs",
        own_text.find("**I8 (MUST)**") != -1 and own_text.find("**I8 (MUST)**") < own_text.find("**R12 (MUST)**"))
    contains("C1.4 R12 names the identity (provider github, id 342916936) and says it is a bot user id",
             r12, '`(provider: "github", id: 342916936)`', "numeric user id of the bot account `worldofmodcraft-pipeline[bot]`")
    contains("C1.5 R12 says the identity is read from config/pipeline-identity.json at the PR's merge-base, never the PR's own revision",
             r12, "`config/pipeline-identity.json` at the PR's merge-base revision of that file, never the revision the PR itself proposes")
    contains("C1.6 R12 states the file shape", r12,
             '{"schema_version": "1.0.0", "pipeline_identity": null}',
             '{"provider": "github", "id": 342916936}')
    contains("C1.7 R12 states the reading rules: absent or null = unconfigured, and every malformed form gives no verdict", r12,
             "An absent file, or `null`, means unconfigured", "A symlink", "a file that is not a regular file", "malformed JSON",
             "a key set other than the two above", 'a `schema_version` other than `"1.0.0"`', 'a provider other than `"github"`',
             "an `id` that is not an integer greater than zero", 'a string `"342916936"` or a boolean `true` never matches',
             "gives no verdict")
    contains("C1.8 R12's detection rule (broad) is stated exactly: pending to published or rejected, or a newly added published/rejected element, and fail closed when it cannot be evaluated", r12,
             'some `entry.json` it changes has an element whose `status` goes from `"pending"` to `"published"` or from `"pending"` to `"rejected"`',
             'or a newly added element whose `status` is `"published"` or `"rejected"`',
             "whatever else is wrong with that file or PR",
             "if that cannot be evaluated (the file does not parse, or has a duplicate key) the PR is rejected by `R12` (fail closed, ADR-0121)")
    contains("C1.9 R12's authorisation rule (narrow) is stated exactly", r12,
             "that one element is classified by `append-only.rules.md` as a T1 or a T3",
             "the parsed `new` `entry.json` equals the parsed `old` one except for that one element's transition",
             "no top-level key added or changed, no other element changed, `id` and `owner` untouched",
             "the PR touches no other path",
             "Differences in bytes that leave the parsed object equal (whitespace, key order) are not a change for `R12`'s purposes")
    contains("C1.10 R12 says its two conditions are jointly sufficient", r12,
             "not merely necessary but jointly sufficient", "no third condition is held back elsewhere in this document")
    contains("C1.11 R12 says a T1/T3-containing PR it does not authorise is rejected by R12 itself, whoever opened it", r12,
             "is rejected by `R12` itself, whoever opened it")
    contains("C1.12 R12 says it authorises nobody until the identity is configured", r12,
             "Until the pipeline identity is configured, `R12` authorises nobody")
    contains("C1.13 R12 names both numbers and says which is the identity (bot user id vs App id)", r12,
             "It is not `5327993`, which is the id of the GitHub App `worldofmodcraft-pipeline` itself")
    contains("C1.14 R12 matches on pulls.user.id and provider (I1, I6), never on login or GITHUB_ACTOR*", r12,
             "matched on `pulls.user.id` and the provider, as `I1` and `I6` require",
             "never on a login, and never on `GITHUB_ACTOR` or `GITHUB_ACTOR_ID`")

    # ---- criterion 2: precedence at both ends; no 'single exception'; T16 shape kept; taxonomy rows
    chk("C2.1 R12's paragraph carries `Precedence: R12 over R3, R7`", "Precedence: R12 over R3, R7" in r12)
    chk("C2.2 R3's paragraph names R12 beside R11", "`R11`" in r3 and "`R12`" in r3 and "or `R12` authorises it as the pipeline's write-back" in r3)
    chk("C2.3 R7's paragraph names R12 beside R11", "`R11`" in r7 and "`R12`" in r7 and "or `R12` authorises it as the pipeline's write-back" in r7)
    chk("C2.4 'the single exception' (or any claim that R11 is the only exception) appears nowhere in the document",
        not re.search(r"single exception|only exception|`R11` is the only (?:exception|one)", d.norm), "")
    chk("C2.5 the only-exception claim is also absent from R3's and R7's own paragraphs",
        not re.search(r"single exception|only exception", r3 + " " + r7))
    bad = [s[:90] for rid, body in (("R3", r3), ("R7", r7)) for s in SPLIT.split(body)
           if re.search("takedown", s, re.I) and not re.search(r"\bR11\b", s)]
    chk("C2.6 R11 stays named in every takedown sentence of R3 and R7 (032-verify.sh T16's rule)", not bad, "%s" % bad)
    rows = d.taxonomy_rows()
    for rid in ("R3", "R7"):
        row = " ".join(rows.get(rid, []))
        chk("C2.7 the taxonomy row for %s names both R11 and R12" % rid, "`R11`" in row and "`R12`" in row, row[:100])

    # ---- criterion 3: one R12 taxonomy row
    chk("C3.1 exactly one taxonomy row for R12", len(rows.get("R12", [])) == 1, "%d rows" % len(rows.get("R12", [])))
    row = " ".join(rows.get("R12", []))
    contains("C3.2 the R12 row says when it rejects: other identity, not exactly one T1/T3 element and nothing else, undecidable classification", row,
             "its author is not the pipeline identity", "it is not exactly one T1 element or exactly one T3 element in one `entry.json` and nothing else",
             "the T1/T3 classification cannot be decided")
    contains("C3.3 the R12 row says what the message says: namespace, author's real (provider, id), only the pipeline identity may write back, one transition per PR", row,
             "the namespace", "the author's real `(provider, id)`", "only the pipeline identity may write back a build result, one transition per PR")

    # ---- criterion 4: I9
    chk("C4.1 I9 is declared exactly once", len(d.decl.get("I9", [])) == 1, "%d" % len(d.decl.get("I9", [])))
    contains("C4.2 I9 is evaluated at the merge-base", i9, "read at the PR's merge-base")
    contains("C4.3 I9 compares only when both identities are configured (non-null)", i9,
             "only when both identities are configured", "each hold a non-null identity at that merge-base")
    contains("C4.4 I9: a pipeline identity equal to R11's identity stops the checker without a verdict", i9,
             "the pipeline identity equals `R11`'s identity, the checker stops without a verdict")

    # ---- criterion 5: R11/R12 interaction, explicit in both paragraphs
    for name, body in (("R12", r12), ("R11", r11)):
        contains("C5.%s the %s paragraph says a PR mixing a takedown with a T1 or T3 is rejected by both R11 and R12" % ("1" if name == "R12" else "3", name), body,
                 "a PR that mixes a takedown mutation with a T1 or T3 element is rejected by")
        chk("C5.%s the %s paragraph says the pipeline identity has no takedown power and the platform identity no write-back power" % ("2" if name == "R12" else "4", name),
            "no takedown power" in body and "no write-back power" in body)

    # ---- criterion 6: what R12 does not lift, and why
    contains("C6.1 R12 lifts R3 and R7 and nothing else, only for the one PR it authorises", sec,
             "`R12` lifts `R3` and `R7` and nothing else, and only for the one PR it authorises")
    contains("C6.2 R1, R2 and R10 still apply", sec, "`R1`, `R2` and `R10` still apply to that PR")
    contains("C6.3 R4, R5, R6 and R8 are never reached, because a T1/T3 needs an existing pending element in old, so R12 never authorises a first publish", sec,
             "`R4`, `R5`, `R6` and `R8` are never reached", "a T1 or a T3 needs an existing `pending` element in `old`",
             "`R12` never authorises a first publish")
    contains("C6.4 with R7 lifted no membership call is made for the pipeline identity, so R9 cannot fire for an authorised write-back", sec,
             "no organisation-membership call is made for the pipeline identity, so `R9` cannot fire for an authorised write-back")
    contains("C6.5 R12 applies to the reserved namespaces mc and test, recorded as a deliberate widening of ADR-0119 section 3, with test:hello-world as the worked example", sec,
             "`R12` applies to the reserved namespaces `mc` and `test` as well",
             "deliberate widening of ADR-0119 §3's reservation for this one transition", "`test:hello-world`")

    # ---- criterion 8: append-only.rules.md
    a = flat(app_text)
    chk("C8.1 the 'Fail closed' bullet names ownership.md's R12 and keeps the fail-closed default",
        "Until a checker implements the pipeline-identity carve-out for T1 and T3, which is `ownership.md`'s `R12`, it must reject every PR that contains a T1 or T3 mutation, whoever authors it." in a)
    chk("C8.2 the 'pipeline's carve-out (a sibling task)' sentence now names R12",
        "(a sibling task)" not in a and "pipeline's carve-out, `ownership.md`'s `R12`, is keyed on the pipeline identity and on T1 or T3 mutations only" in a)
    chk("C8.3 'What this document does not cover' names R12 and keeps the rejection until a checker implements it",
        "until a checker implements its pipeline carve-out, `R12`, every T1 or T3 mutation is rejected." in a and "until its pipeline carve-out exists" not in a)
    chk("C8.4 the old fail-closed wording ('Until `ownership.md` carries') is gone", "Until `ownership.md` carries" not in a)

    # ---- criterion 9: counts
    chk("C9.1 the strings `R1`-`R11` and `I1`-`I8` no longer appear in ownership.md",
        "`R1`-`R11`" not in own_text and "`I1`-`I8`" not in own_text)
    chk("C9.2 `R1`-`R12` and `I1`-`I9` appear", "`R1`-`R12`" in own_text and "`I1`-`I9`" in own_text)
    chk("C9.3 the `T1`-`T16` reference to 032-verify.sh's checks stays", "`T1`-`T16`" in own_text)
    contains("C9.4 a malformed config/pipeline-identity.json stops the checker for every registry PR, as r11-identity.json does; the merge gate is the control", sec,
             "A malformed `config/pipeline-identity.json` stops the checker for every registry PR",
             "as a malformed `config/r11-identity.json` already does", "the merge gate is what keeps such a file from landing")
    return out


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def closed_script_checks():
    out = []

    def chk(label, ok, detail=""):
        out.append((label, bool(ok), detail))

    chk("C10.0 BASE commit exists in this clone", git("cat-file", "-e", BASE + "^{commit}").returncode == 0, BASE)
    for name, cmd in (("032-verify.sh", ["bash", "docs/tasks/032-verify.sh"]),
                      ("032-mutations.sh", ["bash", "docs/tasks/032-mutations.sh"]),
                      ("057-verify.sh", ["bash", "docs/tasks/057-verify.sh"])):
        r = subprocess.run(cmd, capture_output=True, text=True)
        tail = [l for l in r.stdout.splitlines() if l.strip()][-1:] or [""]
        fails = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        chk("C10.1 %s passes on this branch (exit 0, no FAIL line)" % name, r.returncode == 0 and not fails,
            "exit %d; %d FAIL; last line: %s" % (r.returncode, len(fails), tail[0][:100]))
    # --- what changed in the closed artefacts
    def diff(path, *extra):
        return git("diff", "-U0", BASE, "--", path).stdout.splitlines()

    def changed(path):
        d = diff(path)
        rem = [l[1:] for l in d if l.startswith("-") and not l.startswith("---")]
        add = [l[1:] for l in d if l.startswith("+") and not l.startswith("+++")]
        return rem, add

    rem, add = changed("docs/tasks/032-verify.sh")
    ok_rem = len(rem) == 2 and rem[0].lstrip().startswith('"**R3 (MUST)**') and rem[1].lstrip().startswith('"**R7 (MUST)**')
    chk("C10.2 032-verify.sh: only two lines removed, the R3 and R7 CROSSREF_ALLOWED pins", ok_rem, "removed: %s" % [r[:50] for r in rem])
    pat = re.compile(r'^(\s+"\*\*R[37] \(MUST\)\*\*.*"\),|\s+#.*|\s+\(\'R(11|12)\',|\s+".*"\),|\s+"(342916936|5327993)": ".*",)$')
    badadd = [l[:80] for l in add if not pat.match(l)]
    chk("C10.3 032-verify.sh: every added line is a pin (CROSSREF_ALLOWED), a comment on it, or a V5 identity allow-list entry", not badadd, "%s" % badadd)
    chk("C10.4 032-verify.sh: no check removed (the count of pf(/pass/fail/section call lines is unchanged)",
        sum(1 for l in git("show", BASE + ":docs/tasks/032-verify.sh").stdout.splitlines() if re.match(r'\s*(pf|pass|fail|expect_\w+|section)\b', l))
        == sum(1 for l in Path("docs/tasks/032-verify.sh").read_text().splitlines() if re.match(r'\s*(pf|pass|fail|expect_\w+|section)\b', l)))
    chk("C10.5 032-mutations.sh is unchanged (every anchor still matched exactly once, shown by C10.1 passing)",
        git("diff", "--quiet", BASE, "--", "docs/tasks/032-mutations.sh").returncode == 0)
    old_fc = "Until `ownership.md` carries the pipeline-identity carve-out for T1 and T3, a checker implementing T1 or T3 must reject every PR that contains a T1 or T3 mutation, whoever authors it."
    new_fc = "Until a checker implements the pipeline-identity carve-out for T1 and T3, which is `ownership.md`'s `R12`, it must reject every PR that contains a T1 or T3 mutation, whoever authors it."
    for f, label in (("docs/tasks/057-textchecks.py", "057-textchecks.py: only the REQUIRED fail-closed sentence changed"),
                     ("docs/tasks/057-textmutations.py", "057-textmutations.py: only the FAIL_CLOSED constant changed")):
        rem, add = changed(f)
        chk("C10.6 " + label, len(rem) == 1 and len(add) == 1 and old_fc in rem[0] and new_fc in add[0] and rem[0].replace(old_fc, new_fc) == add[0],
            "removed %d, added %d" % (len(rem), len(add)))
    new_pins = json.loads(Path("docs/tasks/057-pinned-sections.json").read_text())
    old_pins = json.loads(git("show", BASE + ":docs/tasks/057-pinned-sections.json").stdout)
    chk("C10.7 057-pinned-sections.json: T1, T3 and ATTACKS are byte-equal before and after; only COEXISTENCE differs",
        set(old_pins) == set(new_pins) and all(old_pins[k] == new_pins[k] for k in ("T1", "T3", "ATTACKS")) and old_pins["COEXISTENCE"] != new_pins["COEXISTENCE"],
        "equal: %s" % {k: old_pins[k] == new_pins[k] for k in old_pins})
    # the new COEXISTENCE pin must be what the blessed text is: the textchecks pin check passes
    r = subprocess.run([sys.executable, "-I", "docs/tasks/057-textchecks.py"], capture_output=True, text=True)
    chk("C10.8 057-textchecks.py passes against the re-blessed pin", r.returncode == 0, r.stdout.strip().splitlines()[-1:] and r.stdout.strip().splitlines()[-1][:100])
    r = subprocess.run([sys.executable, "-I", "docs/tasks/057-textmutations.py"], capture_output=True, text=True)
    reds = [l for l in r.stdout.splitlines() if l.startswith("RED")]
    fc = [l for l in reds if "fail-closed" in l]
    chk("C10.9 057-textmutations.py: both mutations anchored on FAIL_CLOSED still turn red", r.returncode == 0 and len(fc) == 2, "%d fail-closed RED lines, exit %d" % (len(fc), r.returncode))
    only = git("diff", "--name-only", BASE).stdout.split()
    allowed = {"contracts/ownership.md", "contracts/append-only.rules.md", "docs/tasks/032-verify.sh", "docs/tasks/057-textchecks.py",
               "docs/tasks/057-textmutations.py", "docs/tasks/057-pinned-sections.json", "docs/tasks/118-verify.sh",
               "docs/tasks/118-ownership-pipeline-carve-out.md"}
    chk("C10.10 every changed file is inside the declared file scope", set(only) <= allowed, "outside scope: %s" % sorted(set(only) - allowed))
    return out


# ---------------------------------------------------------------- mutations (criterion 11)
def mutations():
    ws = r'\s+'
    return [
        ("delete R12's precedence line", lambda t: re.sub(r'\*\*Precedence: R12 over R3, R7\.\*\*\s*', '', t, count=1)),
        ('restore "the single exception" in R3', lambda t: t.replace("the only two exceptions to this rule", "the single exception to this rule", 1)),
        ("replace the bot id with 5327993", lambda t: t.replace('`(provider: "github", id: 342916936)`', '`(provider: "github", id: 5327993)`', 1)),
        ('drop "merge-base" from the identity source', lambda t: re.sub(r"(`config/pipeline-identity\.json`\s+at the PR's) merge-base( revision of that file)", r"\1\2", t, count=1)),
        ("drop R12's taxonomy row", lambda t: re.sub(r'^\| `R12` \|.*\n', '', t, count=1, flags=re.M)),
        ("delete I9", lambda t: re.sub(r'\*\*I9 \(MUST\)\*\*.*?\n\n', '', t, count=1, flags=re.S)),
        ("drop the detection breadth (the newly-added published/rejected element clause)",
         lambda t: re.sub(r',\s+or a newly added\s+element whose `status` is `"published"` or `"rejected"`', '', t, count=1)),
        ("drop I9's equality condition", lambda t: t.replace("When both are configured and\nthe pipeline identity equals `R11`'s identity, the checker stops", "When both are configured, the checker stops", 1)),
    ]


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def main():
    mode = sys.argv[1]
    own_text, app_text = Path(OWN).read_text(encoding="utf-8"), Path(APPEND).read_text(encoding="utf-8")
    if mode == "check":
        res = text_checks(own_text, app_text) + closed_script_checks()
        n_fail = 0
        for label, ok, detail in res:
            print("%s  %s%s" % ("PASS" if ok else "FAIL", label, "" if ok else " -- " + detail))
            n_fail += (not ok)
        print("\n== RESULT: %d check(s), %d failed" % (len(res), n_fail))
        sys.exit(1 if n_fail else 0)
    if mode == "mutate":
        base = text_checks(own_text, app_text)
        print("unmutated: %d text checks, %d failed (must be 0 for the mutation run to mean anything)" % (len(base), sum(1 for _, ok, _ in base if not ok)))
        if any(not ok for _, ok, _ in base):
            sys.exit(1)
        before = sha(OWN)
        survivors = 0
        for name, fn in mutations():
            mutated = fn(own_text)
            if mutated == own_text:
                print("BROKEN  %s: the mutation changed nothing (anchor not found)" % name)
                survivors += 1
                continue
            red = [l for l, ok, _ in text_checks(mutated, app_text) if not ok]
            if red:
                print("RED     %s -> %s" % (name, ", ".join(l.split(" ")[0] for l in red)))
            else:
                print("GREEN   %s  (SURVIVED: a blind spot)" % name)
                survivors += 1
        after = sha(OWN)
        print("ownership.md sha256 before %s, after %s: %s" % (before[:16], after[:16], "byte-identical" if before == after else "CHANGED"))
        sys.exit(1 if survivors or before != after else 0)


main()
PY

case "$MODE" in
  check|--check) python3 -I "$TMPD/checks.py" check ;;
  --mutate)      python3 -I "$TMPD/checks.py" mutate ;;
  *) echo "usage: $0 [--mutate]" >&2; exit 2 ;;
esac
