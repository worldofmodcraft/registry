#!/usr/bin/env bash
#
# 092-verify.sh -- the runnable verification artefact for task 092 (contracts/artifact-naming.md fixes the archived-source
# URL as https://archive.worldofmodcraft.com/<tag>/<asset>; MANAGER.md Section 2c).
#
# Usage (any cwd inside the repository):
#   docs/tasks/092-verify.sh                 AC1-AC9: offline (git + stdlib python3). Exit code = number of failed checks.
#   docs/tasks/092-verify.sh --site DIR      also (ADVISORY, AC7): node DIR/scripts/check-schemas.mjs <clone at FINAL> -> compared=3 differ=0
#   docs/tasks/092-verify.sh --mutate        AC10: positive control, then each mutation of a temp clone at FINAL must turn the named check
#                                            red and be restored byte-identically.
#   docs/tasks/092-verify.sh --live          AC11 (network, unauthenticated curl, NO credentials): hop 1 of the real front. Run by the manager
#                                            after Ludwig reports runbook step M12 done; the output is pasted into the task log. This
#                                            gates the merge (decision Q7). Without --live the default run prints the "not run" line
#                                            and does NOT count it as a failure.
#   docs/tasks/092-verify.sh --live-selftest
#                                            OFFLINE: the AC11 verdict functions (the same ones --live uses) against a throwaway fake front on
#                                            127.0.0.1 (python3 stdlib): http -> the https GitHub target must PASS; http -> the archive host, a
#                                            wrong target, a query, a non-hop status, a Location that differs only in raw form must FAIL.
#   docs/tasks/092-verify.sh --closed [--nm DIR]
#                                            AC12: every OTHER docs/tasks/*-verify.sh, one at a time on a quiet machine (ps logged),
#                                            on the committed HEAD in a temp clone. Needs node + a node_modules directory with ajv
#                                            (--nm DIR, env WOM_NODE_MODULES, else <repo root>/tools/dev/node_modules). This is a flag
#                                            of its own, not part of the default run, because closed script 039a sweeps every
#                                            docs/tasks/*-verify.sh: a default run that swept them too would recurse (039a -> 092 -> 039a).
#   Flags combine (e.g. --live --closed). To satisfy AC12's "fresh clone" clause run the default mode from a fresh
#   `git clone -b task/092-artifact-naming-archive-url` of the pushed branch.
#
# Rules this script follows (the task file's AC list and REVIEW-CHECKLIST item 12):
#   * Every expected literal below is TYPED here. None is derived from the contract text, the code or the examples under test.
#   * Own-change checks use the EXPLICIT SHAs below (BASE, FINAL, TIP), never HEAD or origin/main.
#   * Content checks run on temp clones checked out at BASE and FINAL; the caller's worktree is never modified.
#   * A check that cannot find what it looks for FAILS (a search that finds nothing is a broken search); an unreachable pin is red.
# Requires: git, python3 (3.9+), curl (--live only), node (--site and --closed only).

set -u
set -o pipefail

BASE=426873502a150ef746063c1b55c2cfbfeed31566   # registry origin/main the branch was cut from (phase 1 log)
FINAL=ab31a88e6e828db689b64e73d4310320938570de  # the content commit (fix round: F1/F2 in artifact-naming.md; the 14 example files and the README row came earlier)
TIP=ab31a88e6e828db689b64e73d4310320938570de    # last contract-changing commit (fix round): BASE..TIP is the scope-checked range, so a later merge
                                                # with registry main cannot redden it. Commits after TIP change only docs/tasks/092-* files
                                                # (the task log and this script), which no check can pin without a cycle; the AC9 post-TIP
                                                # check proves it by name.

MODE_MUTATE=0; MODE_LIVE=0; MODE_SELFTEST=0; MODE_CLOSED=0; SITE=""; NMARG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --mutate) MODE_MUTATE=1 ;;
        --live) MODE_LIVE=1 ;;
        --live-selftest) MODE_SELFTEST=1 ;;
        --closed) MODE_CLOSED=1 ;;
        --site) shift; SITE="${1:-}"; [ -n "$SITE" ] || { echo "092-verify: --site needs a directory" >&2; exit 99; } ;;
        --nm) shift; NMARG="${1:-}"; [ -n "$NMARG" ] || { echo "092-verify: --nm needs a directory" >&2; exit 99; } ;;
        *) echo "usage: 092-verify.sh [--mutate] [--live] [--live-selftest] [--closed [--nm DIR]] [--site DIR]" >&2; exit 99 ;;
    esac
    shift
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }
TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT
G() { git -C "$ROOT" "$@"; }
CLEAN() { env -i PATH="$PATH" HOME="$(mktemp -d "$TMP/home.XXXXXX")" LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 "$@"; }

for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FAIL  tool missing: $tool"; exit 99; }
done

# File scope of the registry branch (task file "File scope"). Typed here, not read from the task file.
SCOPE='^(contracts/artifact-naming\.md|docs/contracts/README\.md|contracts/examples/entry/.+|docs/tasks/092-artifact-naming-archive-url\.md|docs/tasks/092-verify\.sh)$'

# Literals for the live checks and the mutation harness (typed; the python content checker has its own typed copies).
EX1_URL='https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz'
EX1_T='https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz'
EX2_URL='https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz'
EX2_T='https://github.com/worldofmodcraft/archive/releases/download/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz'
RC_URL='https://archive.worldofmodcraft.com/mc.hello-world-1.0.0-RC.1/mc.hello-world-1.0.0-RC.1.tar.gz'
RC_T='https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0-RC.1/mc.hello-world-1.0.0-RC.1.tar.gz'

# ---------------------------------------------------------------------------------------------------------------------
# Temp clones at the fixed pins. The clone is of the local repository (no network): BASE and FINAL must be reachable in it.
mkclone() {  # mkclone REV DEST
    git clone -q --no-hardlinks "$ROOT" "$2" 2>/dev/null && git -C "$2" checkout -q --detach "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------------------------------------------------
write_content_py() {
cat > "$TMP/content.py" <<'PY'
"""AC1-AC8 content checks. argv: BDIR (clone checked out at BASE), FDIR (clone checked out at FINAL, possibly mutated), BASE sha.
Prints one PASS/FAIL line per check. Every expected literal is typed in this file."""
import copy, difflib, hashlib, importlib.util, itertools, json, os, random, re, subprocess, sys

BDIR, FDIR, BASE = sys.argv[1], sys.argv[2], sys.argv[3]
FAILS = 0


def out(tag, cid, msg):
    print(f"{tag}  {cid} {msg}", flush=True)


def chk(cid, cond, msg):
    global FAILS
    if cond:
        out("PASS", cid, msg)
    else:
        FAILS += 1
        out("FAIL", cid, msg)


def guarded(cid, fn):
    try:
        fn()
    except Exception as exc:  # a crashing check is a failing check, never a skipped one
        chk(cid, False, f"raised {type(exc).__name__}: {exc}")


def rd(d, rel):
    with open(os.path.join(d, rel), encoding="utf-8", newline="") as f:
        return f.read()


def rdb(d, rel):
    with open(os.path.join(d, rel), "rb") as f:
        return f.read()


def norm(s):
    return " ".join(s.split())


def sha(b):
    return hashlib.sha256(b).hexdigest()


CN = "contracts/artifact-naming.md"
B, F = rd(BDIR, CN), rd(FDIR, CN)
BN, FN = norm(B), norm(F)
HEAD = "## The archived-source URL (`source_archive`)"


def sections(text):
    """[(heading, text)] -- the preamble has heading ''; a section runs to the next '## ' line."""
    parts, head, buf = [], "", []
    for line in text.split("\n"):
        if line.startswith("## "):
            parts.append((head, "\n".join(buf)))
            head, buf = line, [line]
        else:
            buf.append(line)
    parts.append((head, "\n".join(buf)))
    return parts


def sec(text, heading):
    for h, t in sections(text):
        if h == heading:
            return t
    return None


# ---- typed literals ---------------------------------------------------------------------------------------------------
HOST = "archive.worldofmodcraft.com"
FORM = 'source_archive = "https://archive.worldofmodcraft.com/" + tag + "/" + tag + ".tar.gz"'
TARGET_FORM = "https://github.com/worldofmodcraft/archive/releases/download/<tag>/<asset>"
EX1_URL = "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz"
EX1_SIG = "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz.minisig"
EX1_T = "https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz"
EX1_TS = "https://github.com/worldofmodcraft/archive/releases/download/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz.minisig"
EX2_URL = "https://archive.worldofmodcraft.com/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz"
EX2_T = "https://github.com/worldofmodcraft/archive/releases/download/a.b-1.0.0-rc.1+build.5/a.b-1.0.0-rc.1+build.5.tar.gz"
URL_RE = r"https://archive\.worldofmodcraft\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\.tar\.gz"


def derive(ns, nm, v):
    """The script's own implementation of the task's Objective 1 (typed from the task file, not from the contract text)."""
    tag = ns + "." + nm + "-" + v
    return "https://archive.worldofmodcraft.com/" + tag + "/" + tag + ".tar.gz"


def target(tag, asset):
    return "https://github.com/worldofmodcraft/archive/releases/download/" + tag + "/" + asset


SEC = sec(F, HEAD)
SECN = norm(SEC) if SEC else ""


def load_mod(d, rel, name):
    path = os.path.join(d, rel)
    sys.path.insert(0, os.path.dirname(path))
    try:
        spec = importlib.util.spec_from_file_location(name, path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    finally:
        sys.path.pop(0)
        sys.modules.pop("pipeline_errors", None)


# ---- AC1 ----------------------------------------------------------------------------------------------------------------
def ac1():
    chk("AC1.1", SEC is not None and len(SEC) > 2000, "the section 'The archived-source URL (`source_archive`)' exists at FINAL")
    chk("AC1.2", sec(B, HEAD) is None and "archived-source URL" not in B, "control: the section is absent at BASE")
    paras = F.split("\n\n")
    chk("AC1.3", paras[0] == "# Release tag and asset naming" and paras[1].startswith("Contract for edge"), "title and first paragraph in place")
    p = norm(paras[1])
    for lit in ("**E7**", "`N5 -> N6`", "`docs/architecture/depgraph.md`"):
        chk("AC1.4", lit in p, f"first paragraph still names {lit}")


guarded("AC1", ac1)


# ---- AC2 ----------------------------------------------------------------------------------------------------------------
def ac2():
    chk("AC2.1", derive("mc", "hello-world", "1.0.0") == EX1_URL and derive("a", "b", "1.0.0-rc.1+build.5") == EX2_URL,
        "the script's own derivation reproduces its typed example URLs (self-consistency of the typed literals)")
    chk("AC2.2", target("mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz") == EX1_T
        and target("mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz.minisig") == EX1_TS
        and target("a.b-1.0.0-rc.1+build.5", "a.b-1.0.0-rc.1+build.5.tar.gz") == EX2_T,
        "the script's own redirect-target construction reproduces its typed targets")
    chk("AC2.3", SECN.count(FORM) == 1, "the URL form line is in the section exactly once, byte-equal to the typed form")
    chk("AC2.4", SECN.count("The host is the constant `archive.worldofmodcraft.com`; the URL has scheme `https`, no port, no userinfo, "
                            "no query, no fragment and no trailing slash.") == 1,
        "host constant, scheme and the five absences stated exactly once")
    chk("AC2.5", SECN.count("`" + TARGET_FORM + "`") == 1, "the redirect-target form is in the section exactly once")
    for cid, lit in (("AC2.6", EX1_URL), ("AC2.7", EX1_SIG), ("AC2.8", EX1_T), ("AC2.10", EX2_URL), ("AC2.11", EX2_T)):
        chk(cid, SECN.count("`" + lit + "`") == 1, f"worked-example literal exactly once: {lit}")
    chk("AC2.9", EX1_TS == EX1_T + ".minisig" and SECN.count(EX1_TS) == 0 and SECN.count("`.minisig`") >= 2,
        "the signature's redirect target is not spelled out in the contract: the typed target is the tarball's plus .minisig, as the contract's sentence says")
    chk("AC2.12", SECN.count("This section is the only place the hostname is fixed; task 008c's single named constant takes its value from here.") == 1,
        "'only place the hostname is fixed' stated once")
    chk("AC2.13", SECN.count("redirect target of the signature: the tarball's redirect target plus `.minisig`.") == 1, "signature redirect target stated once")
    chk("AC2.14", FN.count(HOST) >= 4 and FN.count("archive.worldofmodcraft.org") == 0 and FN.count("worldofmodcraft/registry/releases") == 0,
        "host appears, never as .org; the redirect repository is never `registry`")


guarded("AC2", ac2)

# ---- AC3 ----------------------------------------------------------------------------------------------------------------
SCHEMA_MOD = {}


def ac3():
    for label, d in (("BASE", BDIR), ("FINAL", FDIR)):
        nm = load_mod(d, "tools/pipeline/naming.py", "wom_naming_" + label.lower())
        got1 = nm.release_asset_url("worldofmodcraft", "archive", "mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz")
        got2 = nm.release_asset_url("worldofmodcraft", "archive", "mc.hello-world-1.0.0", "mc.hello-world-1.0.0.tar.gz.minisig")
        tag2 = nm.release_tag("a", "b", "1.0.0-rc.1+build.5")
        got3 = nm.release_asset_url("worldofmodcraft", "archive", tag2, nm.asset_names("a", "b", "1.0.0-rc.1+build.5")[0])
        chk("AC3.1", got1 == EX1_T and got2 == EX1_TS and got3 == EX2_T and tag2 == "a.b-1.0.0-rc.1+build.5",
            f"naming.release_asset_url at {label} (imported from the clone) equals the typed targets")
    for rel in ("tools/pipeline/naming.py", "tests/pipeline/test_cli.py"):
        chk("AC3.2", sha(rdb(BDIR, rel)) == sha(rdb(FDIR, rel)), f"{rel} is byte-identical at BASE and FINAL")
    tc = rd(FDIR, "tests/pipeline/test_cli.py")
    for lit in (EX1_T, EX1_TS):
        chk("AC3.3", ('"' + lit + '"') in tc, f"test_cli.py (FINAL clone) holds the literal {lit}")
    env = {"PATH": os.environ.get("PATH", ""), "HOME": os.environ.get("TMPDIR", "/tmp"), "LANG": "C.UTF-8", "PYTHONDONTWRITEBYTECODE": "1"}
    for label, d in (("BASE", BDIR), ("FINAL", FDIR)):
        r = subprocess.run([sys.executable, "-B", "-m", "unittest", "test_cli.ComputedValues.test_ac12_release_asset_url_pinned_over_artifact_naming_examples"],
                           cwd=os.path.join(d, "tests", "pipeline"), env=env, capture_output=True, text=True)
        chk("AC3.4", r.returncode == 0 and "Ran 1 test" in r.stderr and "OK" in r.stderr, f"test_cli.py test_ac12 passes in the {label} clone (rc {r.returncode})")

    schema_mod = load_mod(FDIR, "tools/registry/schema.py", "wom_registry_schema")
    sc = schema_mod.schema_check
    entry_schema = json.loads(rd(FDIR, "contracts/entry.schema.json"))
    pattern = entry_schema["properties"]["versions"]["items"]["properties"]["source_archive"]["pattern"]
    chk("AC3.5", pattern == "^https://\\S+$", "entry.schema.json's source_archive pattern is the typed ^https://\\S+$")
    base_doc = json.loads(rd(FDIR, "contracts/examples/entry/valid/basic-github-single-version.json"))["example"]

    def mkdoc(status, idv, ver, url):
        doc = copy.deepcopy(base_doc)
        doc["id"] = idv
        v = doc["versions"][0]
        v["version"], v["source_archive"], v["status"] = ver, url, status
        if status == "removed":
            v["reason"] = "taken down for the test"
        return doc

    def verdicts(doc):
        res = {}
        for name, fn in (("schema_check", lambda x: sc.validate(x, entry_schema)), ("schema.py(strict)", lambda x: schema_mod.validate(x, entry_schema))):
            try:
                fn(doc)
                res[name] = True
            except sc.SchemaValidationError:
                res[name] = False
        return res

    chk("AC3.6", all(verdicts(mkdoc("published", "mc:hello-world", "1.0.0", "https://example.org/x.tar.gz")).values()),
        "control: the fixture document with a plain https source_archive validates under both validators")
    for url, idv, ver in ((EX1_URL, "mc:hello-world", "1.0.0"), (EX2_URL, "a:b", "1.0.0-rc.1+build.5")):
        for status in ("published", "removed"):
            v = verdicts(mkdoc(status, idv, ver, url))
            chk("AC3.7", all(v.values()), f"{status} version document with source_archive {url} validates: {v}")
        chk("AC3.8", re.fullmatch(r"https://\S+", url) is not None, f"fullmatch of the typed pattern: {url}")
    for bad in ("http://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz", "https://a b/x"):
        v = verdicts(mkdoc("published", "mc:hello-world", "1.0.0", bad))
        chk("AC3.9", not any(v.values()), f"control: {bad!r} is rejected by both validators: {v}")


guarded("AC3", ac3)


# ---- AC4 ----------------------------------------------------------------------------------------------------------------
def ac4():
    schema_mod = load_mod(FDIR, "tools/registry/schema.py", "wom_registry_schema4")
    entry_schema = json.loads(rd(FDIR, "contracts/entry.schema.json"))
    ver_rx = re.compile(schema_mod.ecma_pattern(entry_schema["properties"]["versions"]["items"]["properties"]["version"]["pattern"]))
    id_rx = re.compile(schema_mod.ecma_pattern(entry_schema["properties"]["id"]["pattern"]))
    nm = load_mod(FDIR, "tools/pipeline/naming.py", "wom_naming_ac4")
    reserved = ["con", "prn", "aux", "nul"] + ["com%d" % i for i in range(10)] + ["lpt%d" % i for i in range(10)]  # typed
    chk("AC4.1", set(reserved) == set(nm.RESERVED_DEVICE_NAMES) and len(reserved) == 24, "the 24 reserved device names equal naming.RESERVED_DEVICE_NAMES")
    rejected = 0
    for name in reserved + ["COM1", "Aux"]:
        try:
            nm.check_namespace(name)
        except Exception as exc:
            rejected += type(exc).__name__ == "Rejected"
    chk("AC4.2", rejected == len(reserved) + 2, f"naming.check_namespace rejects all {len(reserved) + 2} reserved-device-name spellings (rejected {rejected})")
    rule = "**A namespace matching one of these names, case-insensitively, must be rejected at first-publish time"
    rb, rf = sec(B, "## Rejected namespaces: Windows reserved device names"), sec(F, "## Rejected namespaces: Windows reserved device names")
    chk("AC4.3", rb is not None and rb == rf and norm(rf).count(rule) == 1,
        "the reserved-device-name rule is unchanged from BASE; quoted: " + rule + " ... [namespace must be rejected before any release is attempted]")

    lower = "abcdefghijklmnopqrstuvwxyz0123456789"
    rest = lower + "_-"
    r = random.Random(92)

    def rname():
        n = r.choice(lower) + "".join(r.choice(rest) for _ in range(r.randrange(0, 11)))
        if r.random() < 0.3:
            n += "-" + str(r.randrange(0, 100))
        return n

    def rident(pre):
        if r.random() < 0.4:
            return str(r.choice([0, 1, 7, 10, r.randrange(0, 10**r.randrange(1, 5))]))
        s = "".join(r.choice("0123456789abcdefXYZ-" if pre else "0123456789abcdefXYZ-") for _ in range(r.randrange(1, 6)))
        return s if (not pre or not s.isdigit()) else s + "a"

    def rver():
        v = ".".join(str(r.choice([0, 1, 2, 9, 10, r.randrange(0, 1000)])) for _ in range(3))
        if r.random() < 0.55:
            v += "-" + ".".join(rident(True) for _ in range(r.randrange(1, 4)))
        if r.random() < 0.4:
            v += "+" + ".".join("".join(r.choice("0123456789abcXZ-") for _ in range(r.randrange(1, 5))) for _ in range(r.randrange(1, 3)))
        return v

    triples, skipped_reserved, skipped_invalid = set(), 0, 0
    adversarial = [("n", "x-1", "2.3.4"), ("n", "x", "1.0.0-2.3.4"), ("n", "x-1-2", "3.4.5"), ("n", "a", "1.0.0-1"), ("n", "a-1", "0.0.0"),
                   ("a-b", "c", "1.0.0"), ("a", "b-c", "1.0.0"), ("n", "a", "1.0.0-1+1"), ("n", "a-1", "0.0.0-1+1"), ("n", "a", "1.2.3-x-1.2")]
    for rn in reserved:
        adversarial.append((rn, "x", "1.0.0"))
    for _ in range(3000):
        adversarial.append((rname(), rname(), rver()))
    alphabet = "a1-_"
    names = ["".join(p) for n in (1, 2, 3) for p in itertools.product(alphabet, repeat=n) if p[0] in "a1"]
    versions = ["0.0.0", "1.0.0", "1.0.0-1", "1.0.0-a", "1.0.0-a.1", "1.0.0+1", "1.0.0-1+1", "10.0.0", "1.0.0-a-1", "1.0.0-1.2", "0.0.0-0", "2.3.4"]
    for ns, n2 in itertools.product(names, names):
        for v in versions:
            adversarial.append((ns, n2, v))
    for ns, n2, v in adversarial:
        if ns in reserved:
            skipped_reserved += 1
            continue
        if not id_rx.search(ns + ":" + n2) or not ver_rx.search(v):
            skipped_invalid += 1
            continue
        triples.add((ns, n2, v))
    chk("AC4.4", len(triples) >= 2000, f"{len(triples)} distinct valid triples generated (floor 2000); {skipped_reserved} reserved-namespace triples excluded, {skipped_invalid} invalid skipped")
    chk("AC4.5", ("n", "x", "1-2.3.4") not in triples and not ver_rx.search("1-2.3.4"),
        "the adversarial split x-1 + 2.3.4 versus x + 1-2.3.4: the second 'version' is not semver, so the schema excludes the split")
    seen, collisions, malformed = {}, [], []
    for t in sorted(triples):
        url = derive(*t)
        if url in seen and seen[url] != t:
            collisions.append((t, seen[url]))
        seen[url] = t
        tag = t[0] + "." + t[1] + "-" + t[2]
        after_authority = url[len("https://archive.worldofmodcraft.com/"):]
        segs = after_authority.split("/")
        if (re.fullmatch(URL_RE, url) is None or "%" in url or ".." in url or "?" in url or "#" in url or "//" in url[len("https://"):]
                or len(segs) != 2 or segs[0] != tag or segs[1] != tag + ".tar.gz" or segs[0] in (".", "..") or segs[0][0] in "-_."):
            malformed.append(url)
    chk("AC4.6", not collisions, f"injectivity: {len(seen)} URLs from {len(triples)} triples, collisions: {collisions[:3]}")
    chk("AC4.7", not malformed and len(seen) == len(triples),
        f"every URL matches ^https://archive\\.worldofmodcraft\\.com/[0-9A-Za-z._+-]+/[0-9A-Za-z._+-]+\\.tar\\.gz$ with no %, .., //, ? or # (bad: {malformed[:3]})")
    ex_plus = [u for u in seen if "+" in u]
    chk("AC4.8", len(ex_plus) > 100 and all("%2B" not in u for u in ex_plus), f"{len(ex_plus)} URLs carry a literal + and none a %2B")
    s = SECN
    for cid, sent in (("AC4.9", "`+` is written literally and `%2B` is a different string."),
                      ("AC4.10", "Injectivity is over byte strings."),
                      ("AC4.11", "Every character of `tag` is in `[0-9A-Za-z._+-]`")):
        chk(cid, s.count(sent) == 1, "contract states: " + sent)


guarded("AC4", ac4)

# ---- AC5: normative sentences pinned by full text ---------------------------------------------------------------------
CONSUMER_INTRO = '**Consumer rules (normative).** "Consumer" means the site (task 055), the pipeline\'s own checks (task 008b), the runbook check in task 010 and any later launcher or installer.'
CONSUMER = [
    "A consumer compares `source_archive` by exact string equality with the URL derived above from the entry's own `id` and `version`; it never parses the URL and accepts one that is \"close enough\".",
    "A consumer requests `archive.worldofmodcraft.com` with no query string; this applies to the request to the front only.",
    "A consumer follows every later hop (hop 2 onward, any 301, 302, 307 or 308: GitHub, then its signed asset host) unchanged, including its query, only over https with TLS verified, within at most 5 hops in total; the hosts on those hops are not an allowlist and not a trust anchor.",
    "A consumer accepts the final 2xx response body only within 52,428,800 bytes (50 MiB) and aborts the download at that cap. The number equals `MAX_COMPRESSED_BYTES` in `tools/pipeline/archive.py` and the site downloader's ceiling (`docs/pipeline/build-pipeline.md`); `archive-layout.md` states no cap of its own. Raising task 008a's compressed-size limit above this number requires amending this contract.",
    "A consumer uses the received bytes only after `source_sha256` and the signature verify, meaning none of the rejection rules 1-11 of `signature-format.md` (\"What a verifier must reject\") applies; before that point it does not install, extract or render them.",
    "A consumer never executes or parses HTML received at any hop.",
    "Consumers do not enforce hop 1's target. Reason: a client that follows redirects automatically (`curl -L`, a browser fetch) cannot see hop 1, and this way the front can be repointed without a consumer release; a repoint changes runbook step M12 and the redirect-target sentence in this section (a contract amendment), not consumers.",
]
PRODUCER_INTRO = "**Producer obligations (task 008c writes the entry, task 008b runs the pipeline).**"
PRODUCER = [
    "`source_archive` is exactly the URL derived above from the entry's own `id` and `version`, never taken from upload output, the GitHub API or `result.json` text.",
    "Before opening T1 (`contracts/append-only.rules.md`) the pipeline (i) requests the front without following redirects and applies the hop-1 check of \"Fail closed\" (a), then (ii) fetches `source_archive` through the full chain under the consumer rules and requires the SHA-256 of the received bytes to equal its own computed `source_sha256`. Any failure is a pipeline fault (task 082 PT10, exit 2): no T3 is written, the version stays `pending` and the run fails naming the URL. This is the only point where a URL that does not resolve can be stopped before it becomes permanent in an append-only record. The manager performs the hop-1 check live (runbook step M12, \"the manager checks\").",
    "The pipeline publishes no version whose `version` contains `+` (build metadata) until a live Release proves that GitHub resolves `+` in `releases/download` (task 010). Such a version gets a T3 `rejected` with the reason \"versions with build metadata (+) are not yet published — pending proof that GitHub resolves them (task 010)\"; it is not left `pending`. The derivation above still defines the URL of such a version.",
]
FAIL_INTRO = "**Fail closed (normative).** There are two lists."
FAIL_A = "- **(a) Hop 1, checked by the producer (before T1) and the manager (live), not by consumers.** The hop-1 check fails when the response from `archive.worldofmodcraft.com` is anything other than a 301, 302, 307 or 308 whose `Location` equals the redirect target byte for byte: a 200 with any body (for example a meta-refresh HTML page, task 058's option A), any 4xx or 5xx, any other `Location`."
FAIL_B = "- **(b) Everywhere, consumers and producer.** Each of these makes the artefact **unverified**: DNS failure (for example runbook step M12 not done yet, so the name does not resolve), TLS failure, any hop that is not https (no downgrade), any 4xx or 5xx on a later hop, a final response that is not 2xx, more than 5 hops, a body over the size cap, a hash mismatch, a signature rejection. Consumers then do not install, extract or render the artefact, and never fall back to another URL, in particular never to a self-built `github.com` URL (decision Q4). The producer does not write T1 and the version stays `pending`."
UNVERIFIED = [
    "- **[unverified]** Whether GitHub resolves a tag containing `+` in `releases/download`.",
    "- **[unverified]** Whether GitHub keeps an uploaded asset filename containing `+` unchanged.",
]
OBSERVED_INTRO = "**Observed 2026-10-26** (by unauthenticated curl against the live front, recorded in the task 092 log; the front's behaviour, not GitHub's):"
OBSERVED = [
    "- The Cloudflare rule preserves the case of the captured path (`-RC.1` came through unchanged).",
    "- The Cloudflare rule keeps a literal `+` in the path.",
    "- The proxied name served a valid certificate (a plain curl, no `-k`, completed); how long issuance took was not recorded and is not a dependency.",
]
UNVERIFIED_INTRO = "**Unverified in this environment** (each is a fact about GitHub behaviour not yet observed; none is a trust dependency, because \"Fail closed\" catches each):"
LOOSE = [
    ("hop", "A **hop** is one redirect response (301, 302, 307 or 308); the response that ends the chain is not a hop."),
    ("hop1", "Hop 1 is the response from `archive.worldofmodcraft.com`, and its target is the `worldofmodcraft/archive` Release asset above"),
    ("hop2", "Hop 2 is GitHub's own redirect to a signed, expiring asset host (`release-assets.githubusercontent.com`, observed in task 058) and is never stored anywhere."),
    ("integrity", "Integrity comes from the hash and the signature (ADR-0041), never from the address;"),
    ("3xx", "nobody may depend on which of the four 3xx statuses it sends."),
    ("case", "Cloudflare's wildcard matching is case-insensitive (source: platform runbook step M12 in `docs/runbooks/site-v1-manual-steps.md`, task 091, which cites Cloudflare's documentation as read on 2026-10-26; this document has not re-read that documentation) and GitHub tags are case-sensitive, so the redirect must preserve the case of the captured path (uppercase prerelease identifiers such as `-RC.1` are legal in semver); observed 2026-10-26 by unauthenticated curl, recorded in the task 092 log: the live front does preserve it."),
    ("attempt3", "**Attempt 3 — a hostile or compromised redirect.** A Cloudflare account takeover (or a bad repoint) points `archive.worldofmodcraft.com` at attacker bytes, or at another genuine signed artefact. **Outcome: the hash does not match `source_sha256`, or `signature-format.md` rule 11 rejects the artefact because the trusted comment's `id` and `version` are not the entry's own; at worst this is a denial of service, never a substituted install.** The producer's and the manager's hop-1 check detects the repoint itself; consumers, which do not check hop 1, still hold because of the hash and signature rules."),
    ("attempt4", "**Attempt 4 — a plausible variant URL accepted by a lenient consumer.** A consumer that parses `source_archive` and accepts `HTTPS://ARCHIVE.WORLDOFMODCRAFT.COM/...`, `%2B` for `+`, a trailing `/`, `?x=` or `/../` would fetch something other than the derived string. **Outcome: exact string equality (consumer rule 1) rejects every one of these.** The redirect forwards any path to `github.com/worldofmodcraft/archive/releases/download/`, so a consumer that fetched non-derived paths could be steered to another file there; consumers fetch only the derived string, and verification still applies."),
]


def block(text, start, end):
    i = text.index(start)
    j = text.index(end, i + len(start)) if end else len(text)
    return text[i:j]


def items(blk, pat):
    pieces = re.split(pat, blk)
    return [norm(p) for p in pieces]


def ac5():
    chk("AC5.0", SEC is not None and "52,428,800" in FN, "the pinned-sentence checks run over a non-empty section")
    cb = block(SEC, "**Consumer rules (normative).**", "**Producer obligations")
    pieces = re.split(r"(?m)^(?=\d+\. )", cb)
    intro, its = norm(pieces[0]), [re.sub(r"^\d+\.\s", "", norm(p)) for p in pieces[1:]]
    chk("AC5.1", intro == CONSUMER_INTRO, "consumer rules: intro sentence is exactly the typed one")
    chk("AC5.2", len(its) == len(CONSUMER), f"consumer rules: exactly {len(CONSUMER)} numbered rules (found {len(its)})")
    for i, (got, want) in enumerate(itertools.zip_longest(its, CONSUMER), 1):
        chk("AC5.3", got == want, f"consumer rule {i} is byte-equal (whitespace-normalised) to the typed text: " + (want or "<none>")[:70])
    pb = block(SEC, "**Producer obligations", "**Fail closed (normative).**")
    pieces = re.split(r"(?m)^(?=\d+\. )", pb)
    intro, its = norm(pieces[0]), [re.sub(r"^\d+\.\s", "", norm(p)) for p in pieces[1:]]
    chk("AC5.4", intro == PRODUCER_INTRO, "producer obligations: intro exactly the typed one")
    chk("AC5.5", len(its) == len(PRODUCER), f"producer obligations: exactly {len(PRODUCER)} (found {len(its)})")
    for i, (got, want) in enumerate(itertools.zip_longest(its, PRODUCER), 1):
        chk("AC5.6", got == want, f"producer obligation {i} is byte-equal to the typed text: " + (want or "<none>")[:70])
    fb = norm(block(SEC, "**Fail closed (normative).**", "**Unverified in this environment**"))
    chk("AC5.7", fb == norm(FAIL_INTRO + " " + FAIL_A + " " + FAIL_B), "fail closed: intro, list (a) and list (b) are byte-equal to the typed text")
    ub = norm(block(SEC, "**Unverified in this environment**", None))
    chk("AC5.8", ub == norm(UNVERIFIED_INTRO + " " + " ".join(UNVERIFIED) + " " + OBSERVED_INTRO + " " + " ".join(OBSERVED)), "the two [unverified] markers and the three observed facts, with their intros, are byte-equal to the typed text")
    chk("AC5.9", SECN.count("**[unverified]**") == 2, f"exactly two **[unverified]** markers in the section (found {SECN.count('**[unverified]**')})")
    # each normative statement exactly once in the whole file (the writer states it once and refers to it elsewhere)
    texts = list(CONSUMER) + PRODUCER[:1] + PRODUCER[2:] + [FAIL_A[2:], FAIL_B[2:]] + [t for _, t in LOOSE]
    for t in texts:
        chk("AC5.10", FN.count(norm(t)) == 1, f"exactly once in the file: {t[:78]}")
    for name, t in (("pre-T1 fetch-and-hash check", PRODUCER[1].split(" The manager performs")[0]),):
        chk("AC5.11", FN.count(norm(t)) == 1, f"exactly once in the file: {name}")
    for cid, lit, n in (("AC5.12", "52,428,800", 1), ("AC5.13", "at most 5 hops in total", 1), ("AC5.14", "more than 5 hops", 1),
                        ("AC5.15", "exact string equality", 2), ("AC5.16", "fall back", 1), ("AC5.17", "not a trust anchor", 1), ("AC5.18", "never executes or parses HTML", 1)):
        chk(cid, FN.count(lit) == n, f"'{lit}' appears exactly {n} time(s) in the file (found {FN.count(lit)})")
    for bad in ("may fall back", "fall back to the github.com", "follow the HTML", "consumers enforce hop 1", "consumer enforces hop 1", "consumer checks hop 1",
                "consumer also requires hop 1", "may parse HTML", "http:// is accepted", "ignore the hash"):
        chk("AC5.19", bad.lower() not in FN.lower(), f"no permissive or hop-1-enforcing wording: '{bad}'")


guarded("AC5", ac5)


# ---- AC6 ----------------------------------------------------------------------------------------------------------------
def ac6():
    stale = "no ADR or graph node fixes this"
    chk("AC6.1", BN.count(stale) >= 1 and FN.count(stale) == 0, f"'{stale}': {BN.count(stale)} at BASE (control), {FN.count(stale)} at FINAL")
    old_q = "(none — the two decisions this contract needed to make, the delimiter substitution and the reserved-device-name rejection, are both settled above with their reasoning; nothing here was left for a future ADR to decide.)"
    new_q = "(none open; task 092's Q1-Q10 were decided by Ludwig on 2026-10-26.)"
    chk("AC6.2", BN.count(old_q) == 1 and FN.count(old_q) == 0 and FN.count(new_q) == 1, "the old Questions sentence is gone (present once at BASE) and the typed new one stands once")
    bullet_old = "**Which specific org-owned repository hosts these Releases** (a dedicated artifact-store repo versus Releases on the `registry` repository itself) \u2014 no ADR or graph node fixes this;"
    chk("AC6.3", FN.count("**Which repository hosts these Releases** \u2014 decided: `worldofmodcraft/archive` (decision Q-E, 008 umbrella F6).") == 1
        and BN.count(bullet_old) == 1 and FN.count(bullet_old) == 0,
        "the 'which repository hosts these Releases' bullet (present at BASE) became the Q-E decision")
    for lit in ("**The Cloudflare rule's exact configuration**", "**`build_log_url`**", "**Enforcing the equality of `source_archive` with the derived URL in registry CI**"):
        chk("AC6.4", FN.count(lit) == 1, f"'does not cover' gained: {lit}")
    bs, fs = dict(sections(B)), dict(sections(F))
    chk("AC6.5", set(bs) | {HEAD} == set(fs), "FINAL has exactly BASE's sections plus the new one")
    same_sections = ["", "## Inputs and what \"deterministic\" means here", "## Why not the `id` string's own separator", "## The naming scheme",
                     "## Rejected namespaces: Windows reserved device names", "## Characters legal in an `id` but awkward in a filename"]
    for h in same_sections:
        chk("AC6.6", h in bs and bs[h] == fs.get(h) and len(bs[h]) > 200, f"section byte-identical to BASE: {h or '(title and first paragraph)'}")
    ns = fs["## The naming scheme"]
    for lit in ("- **Release tag:** `ns.nm-v`", "- **Source tarball asset:** `ns.nm-v.tar.gz`", "- **Detached signature asset:** `ns.nm-v.tar.gz.minisig`"):
        chk("AC6.7", lit in ns, f"naming-scheme bullet present: {lit}")
    att = "## Attack attempts against this contract, recorded per acceptance criterion 3"
    chk("AC6.8", att in bs and att in fs and fs[att].startswith(bs[att].rstrip()) and "**Attempt 1 " in bs[att] and "**Attempt 2 " in bs[att],
        "attack attempts 1-2 are byte-identical to BASE (FINAL's section starts with BASE's whole section)")
    chk("AC6.9", "**Attempt 3 " in fs[att] and "**Attempt 4 " in fs[att] and "**Attempt 5 " not in fs[att], "attempts 3 and 4 follow, numbered after the existing two")


guarded("AC6", ac6)


# ---- AC7 ----------------------------------------------------------------------------------------------------------------
def git(d, *a):
    return subprocess.run(["git", "-C", d] + list(a), capture_output=True, text=True, check=True).stdout


def ac7():
    names = git(FDIR, "diff", "--name-only", BASE, "--", "contracts/").split()
    ex = sorted(n for n in names if n.startswith("contracts/examples/entry/"))
    other = sorted(n for n in names if not n.startswith("contracts/examples/entry/"))
    chk("AC7.1", other == ["contracts/artifact-naming.md"] and 1 <= len(ex) <= 14, f"contracts/ changed: artifact-naming.md plus {len(ex)} example file(s) and nothing else (other: {other})")
    for rel in ("contracts/entry.schema.json", "contracts/append-only.rules.md", "contracts/signature-format.md", "contracts/archive-layout.md"):
        a, b = sha(rdb(BDIR, rel)), sha(rdb(FDIR, rel))
        chk("AC7.2", a == b, f"sha256 equal at BASE and FINAL: {rel} {b[:16]}")
    for rel in ("contracts/page.schema.json", "contracts/manifest.schema.json"):
        chk("AC7.3", sha(rdb(BDIR, rel)) == sha(rdb(FDIR, rel)), f"sha256 equal at BASE and FINAL: {rel}")
    schema_mod = load_mod(FDIR, "tools/registry/schema.py", "wom_registry_schema7")
    sc = schema_mod.schema_check
    entry_schema = json.loads(rd(FDIR, "contracts/entry.schema.json"))

    def verdict(doc):
        try:
            sc.validate(doc, entry_schema)
            return True
        except sc.SchemaValidationError:
            return False

    files = sorted(os.path.join(root, f)[len(FDIR) + 1:] for root, _, fs_ in os.walk(os.path.join(FDIR, "contracts/examples/entry")) for f in fs_)
    chk("AC7.4", len(files) == 20, f"20 example files under contracts/examples/entry (found {len(files)})")
    changed_checked = 0
    for rel in files:
        fj, bj = json.loads(rd(FDIR, rel)), json.loads(rd(BDIR, rel))
        diffs = []

        def walk(x, y, path):
            if type(x) is not type(y):
                diffs.append((path, x, y))
            elif isinstance(x, dict):
                for k in sorted(set(x) | set(y)):
                    if k not in x or k not in y:
                        diffs.append((path + [k], x.get(k), y.get(k)))
                    else:
                        walk(x[k], y[k], path + [k])
            elif isinstance(x, list):
                if len(x) != len(y):
                    diffs.append((path, "len", len(x), len(y)))
                else:
                    for i, (p, q) in enumerate(zip(x, y)):
                        walk(p, q, path + [i])
            elif x != y:
                diffs.append((path, x, y))

        walk(bj, fj, [])
        ok_paths = all(len(d[0]) == 4 and d[0][:2] == ["example", "versions"] and d[0][3] == "source_archive" for d in diffs)
        ident = fj["example"]["id"]
        derived_ok = True
        for v in fj["example"]["versions"]:
            if "source_archive" in v:
                derived_ok &= v["source_archive"] == derive(*ident.split(":"), v["version"])
        text_ok = all('"source_archive":' in ln[2:] for ln in difflib.unified_diff(rd(BDIR, rel).split("\n"), rd(FDIR, rel).split("\n"), lineterm="", n=0)
                      if ln[:1] in "+-" and ln[:3] not in ("+++", "---"))
        expect_valid = "/valid/" in rel
        vb, vf = verdict(bj["example"]), verdict(fj["example"])
        chk("AC7.5", ok_paths and derived_ok and text_ok and vb == vf == expect_valid,
            f"{rel}: only source_archive changed ({len(diffs)}), each = derived URL, raw diff touches only source_archive lines, verdict unchanged ({vb}->{vf}, expected {expect_valid})")
        changed_checked += bool(diffs)
    chk("AC7.6", changed_checked == len(ex) == 14, f"the {changed_checked} example files with a parsed-JSON diff are exactly the {len(ex)} files git reports changed (14 expected)")


guarded("AC7", ac7)


# ---- AC8 ----------------------------------------------------------------------------------------------------------------
def ac8():
    rb, rf = rd(BDIR, "docs/contracts/README.md").split("\n"), rd(FDIR, "docs/contracts/README.md").split("\n")
    changed = [i for i, (x, y) in enumerate(zip(rb, rf)) if x != y]
    chk("AC8.1", len(rb) == len(rf) and len(changed) == 1 and rf[changed[0]].startswith("| `contracts/artifact-naming.md` |"),
        f"README: exactly one line differs from BASE, and it is the artifact-naming.md row (lines {changed})")
    row = rf[changed[0]] if changed else ""
    for lit in ("`https://archive.worldofmodcraft.com/<tag>/<asset>`", "Cloudflare redirect", "`worldofmodcraft/archive` Releases", "fail-closed rules every consumer applies"):
        chk("AC8.2", lit in row, f"README row names: {lit}")
    base_row = rb[changed[0]] if changed else ""
    chk("AC8.3", row.startswith(base_row.rsplit(" | ADR-0041 | E7 |", 1)[0]) and row.endswith("| ADR-0041 | E7 |"), "the row keeps its old text, its ADR and its edge; the clause is an addition")
    ftxt = norm("\n".join(rf))
    for phrase in ("eight prose", "None of the three tasks implements checking logic"):
        chk("AC8.4", ftxt.count(phrase) >= 1 and norm("\n".join(rb)).count(phrase) >= 1, f"README still holds '{phrase}'")


guarded("AC8", ac8)

print(f"CONTENT done fails={FAILS}", flush=True)
PY
}

run_content() {  # run_content BDIR FDIR OUTFILE : returns the number of FAIL lines (a crash counts as one)
    local b="$1" f="$2" o="$3" rc n
    CLEAN python3 -I -B "$TMP/content.py" "$b" "$f" "$BASE" > "$o" 2> "$o.err"; rc=$?
    n=$(grep -c '^FAIL ' "$o")
    if [ "$rc" != 0 ] || ! grep -q '^CONTENT done' "$o"; then
        n=$((n + 1)); echo "FAIL  content.py did not complete (exit $rc): $(head -c 400 "$o.err")" >> "$o"
    fi
    return "$n"
}

# ---------------------------------------------------------------------------------------------------------------------
# AC9: pinned own-change checks. Prints PASS/FAIL lines and returns the number of failures it found.
own_change_checks() {  # own_change_checks FINALREV
    local final="$1" n=0 s files bad
    for s in "$BASE" "$final" "$TIP"; do
        G cat-file -e "$s^{commit}" 2>/dev/null && pass "pin $s exists" || { fail "pin $s does not exist (an unreachable pin is red, never skipped)"; n=$((n + 1)); }
    done
    G merge-base --is-ancestor "$BASE" "$final" 2>/dev/null && pass "BASE is an ancestor of FINAL" || { fail "BASE is not an ancestor of FINAL"; n=$((n + 1)); }
    G merge-base --is-ancestor "$final" "$TIP" 2>/dev/null && pass "FINAL is an ancestor of TIP" || { fail "FINAL is not an ancestor of TIP"; n=$((n + 1)); }
    files="$(G diff --name-only "$BASE" "$final" 2>/dev/null)"
    bad="$(printf '%s\n' "$files" | grep -v -E "$SCOPE")"
    [ -n "$files" ] && [ -z "$bad" ] && pass "git diff --name-only BASE FINAL is non-empty and inside the file scope ($(printf '%s\n' "$files" | wc -l) files)" \
        || { fail "BASE..FINAL is empty or touches out-of-scope files: ${bad:-<empty diff>}"; n=$((n + 1)); }
    files="$(G diff --name-only "$BASE" "$TIP" 2>/dev/null)"
    bad="$(printf '%s\n' "$files" | grep -v -E "$SCOPE")"
    [ -n "$files" ] && [ -z "$bad" ] && pass "git diff --name-only BASE TIP is non-empty and inside the file scope" || { fail "BASE..TIP is empty or touches out-of-scope files: ${bad:-<empty diff>}"; n=$((n + 1)); }
    if G diff --quiet "$final" "$TIP" -- contracts docs/contracts tools tests 2>/dev/null && G cat-file -e "$final^{commit}" 2>/dev/null && G cat-file -e "$TIP^{commit}" 2>/dev/null; then
        pass "no contract, README, tool or test byte differs between FINAL and TIP (merged bytes = verified bytes)"
    else
        fail "contracts, README, tools or tests differ between FINAL and TIP (or a pin is unreachable)"; n=$((n + 1))
    fi
    bad="$(G diff --name-only "$BASE" "$final" 2>/dev/null | grep -E '^(tools|tests)/|^docs/tasks/[0-9a-z]+-verify\.sh$|057-' | grep -v -E '^docs/tasks/092-verify\.sh$' )"
    [ -z "$bad" ] && pass "BASE..FINAL touches no tool, test, closed verify script or 057 pin file" || { fail "BASE..FINAL touches protected files: $bad"; n=$((n + 1)); }
    return "$n"
}

# AC9 post-TIP: the commits after TIP (first-parent chain, name-only) touch only docs/tasks/092-* files. Note: `git log --first-parent --name-only`
# lists no files for merge commits, so a conflict-resolution edit inside a main-into-branch merge after TIP is not seen (mitigation: BASE..TIP is
# pinned above and main is reviewed separately). If TIP is an ancestor of HEAD but not on its first-parent chain (the branch was merged into main),
# the check prints a NA line, NOT a PASS: NOT-APPLICABLE (merged). If TIP is not an ancestor of HEAD at all (rewritten away), it is RED.
post_tip_check() {  # post_tip_check TIPREV HEADREV -> PASS/FAIL/NA line; returns 0/1
    local t="$1" h="$2" files bad
    G cat-file -e "$t^{commit}" 2>/dev/null && G cat-file -e "$h^{commit}" 2>/dev/null || { fail "post-TIP check: pin $t or $h does not exist"; return 1; }
    if ! G merge-base --is-ancestor "$t" "$h" 2>/dev/null; then
        fail "post-TIP: TIP $t is not an ancestor of $h (history rewritten away from the pin)"; return 1
    fi
    if ! G rev-list --first-parent "$h" 2>/dev/null | grep -x -F "$t" >/dev/null; then
        printf 'NA    post-TIP NOT-APPLICABLE (merged): %s is an ancestor of %s but not on its first-parent chain (BASE..TIP pins above still apply)\n' "$t" "$h"; return 0
    fi
    files="$(G log --first-parent --name-only --format= "$t..$h" 2>/dev/null | sort -u | sed '/^$/d')"
    bad="$(printf '%s\n' "$files" | sed '/^$/d' | grep -v -E '^docs/tasks/092-[^/]+$')"
    if [ -z "$bad" ]; then pass "post-TIP: commits after TIP touch only docs/tasks/092-* files ($(printf '%s\n' "$files" | sed '/^$/d' | wc -l) file name(s))"; return 0
    else fail "post-TIP: commits after TIP touch files outside docs/tasks/092-*: $(echo "$bad" | tr '\n' ' ')"; return 1; fi
}

section "AC9 -- pinned own-change checks (BASE $BASE, FINAL $FINAL, TIP $TIP)"
( own_change_checks "$FINAL" ) > "$TMP/ac9.out"; rc=$?
cat "$TMP/ac9.out"
FAILURES=$((FAILURES + $(grep -c '^FAIL ' "$TMP/ac9.out")))
[ "$rc" = 0 ] && pass "AC9: all own-change checks pass" || fail "AC9: $rc own-change check(s) failed"
( own_change_checks "$BASE" ) > "$TMP/ac9c.out"; rc=$?
[ "$rc" -gt 0 ] && pass "AC9 control: FINAL=BASE makes $rc own-change check(s) fail (red as required)" || fail "AC9 control: FINAL=BASE does not fail the own-change checks"
( own_change_checks "0000000000000000000000000000000000000000" ) > "$TMP/ac9u.out"; rc=$?
[ "$rc" -gt 0 ] && grep -q '^FAIL  pin 0000000000000000000000000000000000000000 does not exist' "$TMP/ac9u.out" \
    && pass "AC9 control: an unreachable FINAL pin is red, never skipped ($rc failure(s))" || fail "AC9 control: an unreachable pin did not fail"
post_tip_check "$TIP" "$(G rev-parse HEAD)"
( post_tip_check "$BASE" "$FINAL" ) > "$TMP/ac9p.out"; rc=$?
[ "$rc" != 0 ] && grep -q '^FAIL  post-TIP: commits after TIP touch files outside docs/tasks/092-' "$TMP/ac9p.out" \
    && pass "AC9 control: BASE..FINAL as the post-TIP range is red (touches contracts, not only 092-* files)" || fail "AC9 control: the post-TIP check did not fail on BASE..FINAL"
( post_tip_check "$BASE" "0000000000000000000000000000000000000000" ) > "$TMP/ac9q.out"; rc=$?
[ "$rc" != 0 ] && pass "AC9 control: an unreachable HEAD pin makes the post-TIP check red, never skipped" || fail "AC9 control: an unreachable pin did not fail the post-TIP check"
( post_tip_check "$FINAL" "$BASE" ) > "$TMP/ac9r.out"; rc=$?
[ "$rc" != 0 ] && grep -q '^FAIL  post-TIP' "$TMP/ac9r.out" \
    && pass "AC9 control: a TIP that is not an ancestor of HEAD (rewritten away) makes the post-TIP check red" || fail "AC9 control: a non-ancestor TIP did not fail the post-TIP check"
# merged case: a synthetic main (BASE) that merged the branch (TIP) with --no-ff; TIP is then an ancestor of HEAD but off the first-parent chain.
MC="$TMP/mergedclone"
if git clone -q --no-hardlinks "$ROOT" "$MC" 2>/dev/null && git -C "$MC" checkout -q --detach "$BASE" 2>/dev/null \
    && git -C "$MC" -c user.name=selftest -c user.email=selftest@invalid merge -q --no-ff -m "synthetic merge of the branch into main" "$TIP" >/dev/null 2>&1; then
    MH="$(git -C "$MC" rev-parse HEAD)"
    ( ROOT="$MC"; post_tip_check "$TIP" "$MH" ) > "$TMP/ac9m.out"; rc=$?
    [ "$rc" = 0 ] && grep -q '^NA    post-TIP NOT-APPLICABLE (merged)' "$TMP/ac9m.out" && ! grep -q '^PASS' "$TMP/ac9m.out" \
        && pass "AC9 control: the merged case prints NOT-APPLICABLE (merged), not a PASS" || fail "AC9 control: the merged case did not print NOT-APPLICABLE (merged) alone (rc $rc: $(head -c 200 "$TMP/ac9m.out"))"
else
    fail "AC9 control: could not build the synthetic merged clone"
fi
for p in tools/pipeline/naming.py contracts/entry.schema.json docs/tasks/057-verify.sh README.md; do
    printf '%s\n' "$p" | grep -q -E "$SCOPE" && fail "AC9 control: the scope pattern wrongly admits $p" || pass "AC9 control: the scope pattern rejects $p"
done

# ---------------------------------------------------------------------------------------------------------------------
write_content_py
BDIR="$TMP/base"; FDIR="$TMP/final"
if mkclone "$BASE" "$BDIR" && mkclone "$FINAL" "$FDIR"; then
    pass "temp clones created at the fixed BASE and FINAL (the caller's worktree is not touched)"
else
    fail "cannot create the BASE/FINAL clones (are both commits reachable from this repository?)"
    echo; echo "SUMMARY failed=$FAILURES (stopped: no clones)"; exit "$FAILURES"
fi

if [ "$MODE_MUTATE" = 0 ]; then
    section "AC1-AC8 -- content checks on the BASE and FINAL clones"
    run_content "$BDIR" "$FDIR" "$TMP/content.out"; rc=$?
    cat "$TMP/content.out"
    FAILURES=$((FAILURES + rc))
    printf 'content checks: %s PASS, %s FAIL\n' "$(grep -c '^PASS ' "$TMP/content.out")" "$(grep -c '^FAIL ' "$TMP/content.out")"
    for ac in AC1 AC2 AC3 AC4 AC5 AC6 AC7 AC8; do
        grep -q "^PASS  $ac\." "$TMP/content.out" && ! grep -q "^FAIL  $ac\." "$TMP/content.out" && pass "$ac: at least one passing check and none failing" || fail "$ac: no passing check or a failing check"
    done

    if [ -n "$SITE" ]; then
        section "AC7 ADVISORY -- the site's schema check against the FINAL clone"
        if [ -f "$SITE/scripts/check-schemas.mjs" ] && command -v node >/dev/null 2>&1; then
            o="$( cd "$SITE" && node scripts/check-schemas.mjs "$FDIR" 2>&1 )"; rc=$?
            printf '%s\n' "$o"
            if [ "$rc" = 0 ] && printf '%s\n' "$o" | grep -q 'compared=3 differ=0'; then pass "ADVISORY: check-schemas.mjs: compared=3 differ=0"
            else printf 'ADVISORY (not counted): check-schemas.mjs exit %s -- the site copy of the schemas is out of sync with this registry for a reason outside this task (entry.schema.json is byte-identical BASE..FINAL)\n' "$rc"; fi
        else
            printf 'ADVISORY (not counted): %s/scripts/check-schemas.mjs or node not found\n' "$SITE"
        fi
    fi
fi

# ---------------------------------------------------------------------------------------------------------------------
if [ "$MODE_MUTATE" = 1 ]; then
    section "AC10 -- --mutate: positive control, then each mutation of a temp clone at FINAL must turn the named check red"
    cat > "$TMP/mut.py" <<'PY'
import re, sys
p, op = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8", newline="").read()
if op == "replace1":
    assert s.count(sys.argv[3]) == 1, f"{p}: expected exactly one occurrence of {sys.argv[3]!r}, found {s.count(sys.argv[3])}"
    s = s.replace(sys.argv[3], sys.argv[4])
elif op == "replaceall":
    assert s.count(sys.argv[3]) >= 1, f"{p}: {sys.argv[3]!r} not found"
    s = s.replace(sys.argv[3], sys.argv[4])
elif op == "resub":
    s, n = re.subn(sys.argv[3], sys.argv[4], s, flags=re.S)
    assert n == 1, f"{p}: pattern {sys.argv[3]!r} matched {n} times"
elif op == "append":
    s += sys.argv[3]
else:
    raise SystemExit("bad op")
open(p, "w", encoding="utf-8", newline="").write(s)
PY
    # positive control
    run_content "$BDIR" "$FDIR" "$TMP/pos.out"; rc=$?
    [ "$rc" = 0 ] && pass "positive control: the unmutated FINAL clone is green ($(grep -c '^PASS ' "$TMP/pos.out") checks)" || { fail "positive control: the unmutated clone is red ($rc)"; grep '^FAIL' "$TMP/pos.out" | head -5; }
    [ -z "$(git -C "$FDIR" status --porcelain)" ] && pass "the clone is clean before the mutations" || fail "the clone is not clean before the mutations"

    mutate() {  # mutate NAME EXPECT_PREFIX FILE OP ARG...   -> one mutation, one check
        local name="$1" expect="$2" file="$3"; shift 3
        local path="$FDIR/$file" before after tag out="$TMP/mut.$RANDOM.out"
        before="$(sha256sum "$path" | cut -d' ' -f1)"
        cp -p "$path" "$TMP/mut.backup"
        if ! python3 -I -B "$TMP/mut.py" "$path" "$@" 2> "$out.err"; then
            fail "mutation '$name' could not be applied: $(head -c 300 "$out.err")"; cp -p "$TMP/mut.backup" "$path"; return
        fi
        [ "$(sha256sum "$path" | cut -d' ' -f1)" != "$before" ] || { fail "mutation '$name' changed nothing"; return; }
        run_content "$BDIR" "$FDIR" "$out"; rc=$?
        tag="$(grep '^FAIL ' "$out" | awk '{print $2}' | sed 's/\..*//' | sort -u | tr '\n' ' ')"
        if [ "$rc" -gt 0 ] && grep -q "^FAIL  $expect" "$out"; then pass "mutation '$name' turns $expect red ($rc failing; reds: $tag)"
        else fail "mutation '$name' did not turn $expect red (failing $rc; reds: $tag)"; fi
        cp -p "$TMP/mut.backup" "$path"
        after="$(sha256sum "$path" | cut -d' ' -f1)"
        [ "$after" = "$before" ] && [ -z "$(git -C "$FDIR" status --porcelain)" ] && pass "restored byte-identically after '$name' (sha256 ${after:0:16}, git status clean)" || fail "NOT restored after '$name'"
    }
    A=contracts/artifact-naming.md
    mutate "host -> .org" AC2 "$A" replaceall "archive.worldofmodcraft.com" "archive.worldofmodcraft.org"
    mutate "URL join -> <tag>-<asset>" AC2 "$A" replace1 '+ tag + "/" + tag +' '+ tag + "-" + tag +'
    mutate "redirect target repo -> worldofmodcraft/registry" AC2 "$A" replaceall "worldofmodcraft/archive/releases" "worldofmodcraft/registry/releases"
    mutate "example tag -> mc:hello-world-1.0.0" AC2 "$A" replaceall "mc.hello-world-1.0.0" "mc:hello-world-1.0.0"
    mutate "hash-and-signature-before-use sentence deleted" AC5 "$A" resub '5\. A consumer uses the received bytes only after.*?render them\.\n' ''
    mutate "permissive tail: may fall back to the github.com URL" AC5 "$A" replace1 "(a contract amendment), not consumers." "(a contract amendment), not consumers. A consumer may fall back to the github.com URL."
    mutate "tail: consumers enforce hop 1's target (Q9)" AC5 "$A" replace1 "(a contract amendment), not consumers." "(a contract amendment), not consumers. A consumer also requires hop 1's Location to equal the redirect target."
    mutate "observed-case sentence loses its basis" AC5 "$A" resub 'observed 2026-10-26 by\s+unauthenticated curl, recorded in the task 092 log: the live front does preserve it\.' "the manager's live checks record whether it does."
    mutate "case-insensitivity claim loses its source" AC5 "$A" resub '\s+\(source: platform runbook step M12.*?re-read that documentation\)' ''
    mutate "5 hops -> bounded" AC5 "$A" replaceall "5 hops" "bounded"
    mutate "an [unverified] marker dropped" AC5 "$A" replace1 "- **[unverified]** Whether GitHub keeps an uploaded asset filename containing" "- Whether GitHub keeps an uploaded asset filename containing"
    mutate "one byte of entry.schema.json's description changed" AC7.2 contracts/entry.schema.json replace1 "Mutability rules for this document are NOT" "Mutability rules for this document are Not"
    mutate "signature-format.md touched" AC7.2 contracts/signature-format.md append "
"
    mutate "a README phrase deleted" AC8.4 docs/contracts/README.md replace1 "None of the three tasks implements checking logic" ""
    [ -z "$(git -C "$FDIR" status --porcelain)" ] && pass "the clone is clean after all mutations" || fail "the clone is not clean after all mutations"
    run_content "$BDIR" "$FDIR" "$TMP/pos2.out"; rc=$?
    [ "$rc" = 0 ] && pass "positive control again after all restores: green" || fail "positive control after the mutations is red ($rc)"
fi

# ---------------------------------------------------------------------------------------------------------------------
hop1() {  # hop1 URL -> prints "CODE|redirect_url|raw Location header" (no -L: hop 1 is invisible to auto-following clients)
    local w loc
    w="$(curl -s -o /dev/null --max-time 30 -D "$TMP/hdr" -w '%{http_code} %{redirect_url}' "$1")" || { echo "curl-exit-$?||"; return; }
    loc="$(tr -d '\r' < "$TMP/hdr" | awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/^[^:]*: */, ""); print; exit}')"
    echo "${w%% *}|${w#* }|$loc"
}
# The AC11 verdict functions (code, redirect_url, raw Location [, wanted]). Live mode and --live-selftest call the same ones.
is3xx() { case "$1" in 301|302|307|308) return 0 ;; *) return 1 ;; esac; }
live_check() {  # live_check LABEL URL EXPECTED_LOCATION
    local r code ru raw
    r="$(hop1 "$2")"; code="${r%%|*}"; ru="$(echo "$r" | cut -d'|' -f2)"; raw="$(echo "$r" | cut -d'|' -f3-)"
    printf '  $ curl -s -o /dev/null -w "%%{http_code} %%{redirect_url}" %s\n    -> %s %s\n    raw Location: %s\n' "$2" "$code" "$ru" "$raw"
    if ac11_exact_ok "$code" "$ru" "$raw" "$3"; then pass "$1: $code, Location byte-equal to the derived target"
    else fail "$1: expected 301/302/307/308 with Location $3, got '$code' redirect_url '$ru' raw '$raw'"; fi
}
ac11_exact_ok() { is3xx "$1" && [ "$2" = "$4" ] && [ "$3" = "$4" ]; }   # AC11a/b: status class + redirect_url AND raw Location byte-equal
ac11c_ok() { ac11_exact_ok "$1" "$2" "$3" "$EX1_T"; }                  # AC11c: no query forwarded (redirect_url AND raw Location byte-equal)
ac11f_ok() { ac11_exact_ok "$1" "$2" "$3" "$EX1_T"; }                  # AC11f: http:// -> 301/302/307/308 to the derived https target (runbook M12, third check)

# ---------------------------------------------------------------------------------------------------------------------
section "AC11 -- LIVE (hop 1 of the real front)"
if [ "$MODE_LIVE" = 0 ]; then
    echo "LIVE not run; merge gate satisfied by the log capture of <date> (run with --live after runbook step M12; paste the capture in the task log)"
else
    command -v curl >/dev/null 2>&1 || { fail "AC11 prerequisite: curl is missing"; }
    echo "LIVE capture $(date -u +%Y-%m-%dT%H:%M:%SZ)  host: $(uname -n)  curl: $(curl --version | head -1)"
    live_check "AC11a tarball URL of mc.hello-world-1.0.0" "$EX1_URL" "$EX1_T"
    live_check "AC11b '+' build URL keeps the literal +" "$EX2_URL" "$EX2_T"
    live_check "AC11b uppercase prerelease keeps its case" "$RC_URL" "$RC_T"
    r="$(hop1 "$EX1_URL?x=1")"; code="${r%%|*}"; ru="$(echo "$r" | cut -d'|' -f2)"; raw="$(echo "$r" | cut -d'|' -f3-)"
    printf '  $ curl ... %s?x=1\n    -> %s %s\n    raw Location: %s\n' "$EX1_URL" "$code" "$ru" "$raw"
    if ac11c_ok "$code" "$ru" "$raw"; then pass "AC11c a request with ?x=1 gets a Location without any query (redirect_url and raw Location byte-equal)"
    else fail "AC11c STOP: the front must send no query (M12 is path-only); got '$code' redirect_url '$ru' raw '$raw' -- record this and change the contract text, do not patch the check"; fi
    printf '  $ curl -sI https://archive.worldofmodcraft.com/\n'
    curl -sI --max-time 30 https://archive.worldofmodcraft.com/ > "$TMP/root.hdr" 2> "$TMP/root.err"; rc=$?
    sed 's/^/    /' "$TMP/root.hdr"
    if [ "$rc" = 0 ] && tr -d '\r' < "$TMP/root.hdr" | grep -qi '^server: cloudflare$'; then pass "AC11d the root answers with the header 'server: cloudflare' (recorded above)"
    else fail "AC11d the root request failed or has no 'server: cloudflare' header (curl exit $rc: $(head -c 200 "$TMP/root.err"))"; fi
    curl -s -o /dev/null --max-time 30 "$EX1_URL" 2> "$TMP/tls.err"; rc=$?
    case "$rc" in
        0) pass "AC11e TLS: a plain curl (no -k) completes, so the certificate is valid" ;;
        60|35|51|58|59|77|83|91) fail "AC11e TLS: certificate or handshake problem (curl exit $rc: $(head -c 200 "$TMP/tls.err"))" ;;
        6) fail "AC11e the name does not resolve (curl exit 6): runbook step M12 is not done" ;;
        *) fail "AC11e plain curl failed (exit $rc: $(head -c 200 "$TMP/tls.err"))" ;;
    esac
    r="$(hop1 "http://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz")"; code="${r%%|*}"; ru="$(echo "$r" | cut -d'|' -f2)"; raw="$(echo "$r" | cut -d'|' -f3-)"
    printf '  $ curl ... http://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz\n    -> %s %s\n    raw Location: %s\n' "$code" "$ru" "$raw"
    if ac11f_ok "$code" "$ru" "$raw"; then pass "AC11f http:// is redirected ($code) to the https target, Location byte-equal"
    else fail "AC11f http:// must answer 301/302/307/308 with redirect_url AND raw Location byte-equal to $EX1_T; got '$code' redirect_url '$ru' raw '$raw'"; fi
    echo "  not proven by AC11: that GitHub resolves a '+' tag or keeps a '+' asset filename (Q10 covers it; 008b criterion 6 / task 010 carry the end-to-end bytes check)."
fi

# ---------------------------------------------------------------------------------------------------------------------
# --live-selftest: the AC11 verdict functions against a throwaway fake front on 127.0.0.1 (python3 stdlib). OFFLINE: the real host is never
# contacted (every URL below is http://127.0.0.1:PORT/...). Each case names the verdict function, the expected verdict, and what the fake sends.
if [ "$MODE_SELFTEST" = 1 ]; then
    section "AC11 --live-selftest -- the AC11 verdict functions against a local fake front (never the real host)"
    command -v curl >/dev/null 2>&1 || fail "selftest prerequisite: curl is missing"
    cat > "$TMP/fakefront.py" <<'PY'
import http.server, sys
EX1_T = sys.argv[2]
ARCH = "https://archive.worldofmodcraft.com/mc.hello-world-1.0.0/mc.hello-world-1.0.0.tar.gz"
# path -> (status, Location or None)
CASES = {
    "/http-to-github": (302, EX1_T),
    "/http-to-github-301": (301, EX1_T),
    "/http-to-github-308": (308, EX1_T),
    "/http-to-archive": (302, ARCH),
    "/wrong-target": (302, "https://github.com/worldofmodcraft/archive/releases/download/other/other.tar.gz"),
    "/query": (302, EX1_T + "?x=1"),
    "/clean": (302, EX1_T),
    "/upper-scheme-host": (302, "HTTPS://GITHUB.COM" + EX1_T[len("https://github.com"):]),
    "/dot-segment": (302, EX1_T.replace("/download/", "/download/x/../")),   # curl normalises ../ in redirect_url; the raw header keeps it
    "/trailing-slash": (302, EX1_T + "/"),
    "/status-303": (303, EX1_T),
    "/status-200-with-location": (200, EX1_T),
    "/status-404": (404, None),
}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        code, loc = CASES.get(self.path.split("?")[0], (404, None))
        self.send_response(code)
        if loc is not None:
            self.send_header("Location", loc)
        self.send_header("Content-Length", "0")
        self.end_headers()
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(srv.server_address[1]))
srv.serve_forever()
PY
    python3 "$TMP/fakefront.py" "$TMP/fake.port" "$EX1_T" & FAKE_PID=$!
    for _ in $(seq 1 50); do [ -s "$TMP/fake.port" ] && break; sleep 0.1; done
    if [ ! -s "$TMP/fake.port" ]; then fail "selftest: the fake front did not start"; else
        FAKE="http://127.0.0.1:$(cat "$TMP/fake.port")"
        selftest_case() {  # selftest_case LABEL VERDICT-FUNCTION PATH WANT(PASS|FAIL)
            local r code ru raw got
            r="$(hop1 "$FAKE$3")"; code="${r%%|*}"; ru="$(echo "$r" | cut -d'|' -f2)"; raw="$(echo "$r" | cut -d'|' -f3-)"
            case "$2" in
                f) ac11f_ok "$code" "$ru" "$raw" ;;
                c) ac11c_ok "$code" "$ru" "$raw" ;;
                exact) ac11_exact_ok "$code" "$ru" "$raw" "$EX1_T" ;;
            esac && got=PASS || got=FAIL
            if [ "$got" = "$4" ]; then pass "selftest $1: verdict $got as required (code '$code', redirect_url '$ru', raw '$raw')"
            else fail "selftest $1: verdict $got, required $4 (code '$code', redirect_url '$ru', raw '$raw')"; fi
        }
        selftest_case "AC11f http -> https GitHub target (302)"          f /http-to-github PASS
        selftest_case "AC11f http -> https GitHub target (301)"          f /http-to-github-301 PASS
        selftest_case "AC11f http -> https GitHub target (308)"          f /http-to-github-308 PASS
        selftest_case "AC11f http -> https://archive.worldofmodcraft.com" f /http-to-archive FAIL
        selftest_case "AC11f wrong target"                               f /wrong-target FAIL
        selftest_case "AC11f target plus a query"                        f /query FAIL
        selftest_case "AC11f target plus a trailing slash"               f /trailing-slash FAIL
        selftest_case "AC11f status 303 (not in the set)"                f /status-303 FAIL
        selftest_case "AC11f status 200 carrying a Location"             f /status-200-with-location FAIL
        selftest_case "AC11f status 404"                                 f /status-404 FAIL
        selftest_case "AC11c clean Location"                             c /clean PASS
        selftest_case "AC11c raw Location carries a query"               c "/query?x=1" FAIL
        selftest_case "AC11c raw Location differs only in scheme/host case" c /upper-scheme-host FAIL
        selftest_case "AC11c raw Location has a dot segment (redirect_url is normalised and looks right)" c /dot-segment FAIL
        selftest_case "AC11a/b exact: clean Location"                    exact /clean PASS
        selftest_case "AC11a/b exact: raw Location differs only in scheme/host case" exact /upper-scheme-host FAIL
        selftest_case "AC11a/b exact: wrong target"                      exact /wrong-target FAIL
    fi
    kill "$FAKE_PID" 2>/dev/null; wait "$FAKE_PID" 2>/dev/null
fi

# ---------------------------------------------------------------------------------------------------------------------
if [ "$MODE_CLOSED" = 1 ]; then
    section "AC12 -- every other closed verify script on the committed HEAD, one at a time on a quiet machine"
    others_running() { ps -eo args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v '092-verify\.sh' | grep -q .; }
    wait_quiet() {  # polls up to 60 minutes; prints the ps evidence
        local waited=0
        while others_running; do
            [ "$waited" -ge 3600 ] && return 1
            sleep 10; waited=$((waited + 10))
        done
        return 0
    }
    NM="${NMARG:-${WOM_NODE_MODULES:-$ROOT/tools/dev/node_modules}}"
    if [ ! -d "$NM/ajv" ] || ! command -v node >/dev/null 2>&1; then
        fail "AC12 prerequisite: node and a node_modules directory with ajv are needed (--nm DIR, WOM_NODE_MODULES, or npm ci --prefix tools/dev); looked in $NM"
    else
        HEADREV="$(G rev-parse HEAD)"
        HC="$TMP/headclone"
        if git clone -q --no-hardlinks "$ROOT" "$HC" && git -C "$HC" checkout -q --detach "$HEADREV"; then
            mkdir -p "$HC/tools/dev" && cp -a "$NM" "$HC/tools/dev/node_modules"
            if wait_quiet; then
                echo "ps check ($(date -u +%H:%M:%SZ)): $(ps -eo args | grep -E 'docs/tasks/[^ ]*-verify\.sh' | grep -v grep | grep -v '092-verify\.sh' | wc -l) other verify scripts running"
                pass "machine quiet: no other *-verify.sh running before the sweep"
            else
                fail "AC12 PENDING: another *-verify.sh was still running after 60 minutes; the sweep was not started"
            fi
            if ! others_running; then
                for f in $(cd "$HC" && ls docs/tasks/*-verify.sh | sort); do
                    case "$f" in *092-verify.sh) continue ;; esac
                    wait_quiet || { fail "$f: another *-verify.sh kept running for 60 minutes (not run)"; continue; }
                    s0=$(date +%s)
                    ( cd "$HC" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "$f" > "$TMP/v.out" 2>&1 ); rc=$?
                    if [ "$rc" = 0 ]; then pass "$(basename "$f") exits 0 on HEAD $HEADREV ($(( $(date +%s) - s0 ))s, ps quiet before it)"
                    else fail "$(basename "$f") exit $rc on HEAD: $(grep -m3 '^FAIL' "$TMP/v.out" | tr '\n' ' ')"; fi
                done
            fi
        else
            fail "AC12: cannot clone HEAD"
        fi
    fi
fi

echo
echo "SUMMARY failed=$FAILURES"
exit "$FAILURES"
