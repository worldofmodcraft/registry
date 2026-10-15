#!/usr/bin/env bash
#
# 066-verify.sh -- the runnable verification artefact for task 066 (MANAGER.md Section 2c).
#
# Task 066: a pinned, reproducible ajv 8.20.0 in tools/dev/ for 057-verify.sh and 062-verify.sh. Demonstrates
# acceptance criteria 1-8 of docs/tasks/066-registry-dev-tools-ajv.md.
#
# Usage:  docs/tasks/066-verify.sh [--mutate]      (any cwd inside the repository)
#   (no flag)  criteria 1-7, on the COMMITTED state (HEAD) in temporary clones.
#   --mutate   criterion 8: range pin, default path removed from 057-verify.sh, failure message without the
#              command, .gitignore line removed; each must turn a check red.
# NETWORK: exactly one step is networked: `npm ci --prefix tools/dev` in a fresh clone (public npm registry,
# anonymous, no npmrc/user config read). It is labelled "NETWORKED STEP" in the output. Everything else is offline.
# The caller's worktree is never modified. Exit code: the number of failed checks.
# Requires: git, python3, node, npm, plus everything 057-verify.sh and 062-verify.sh require (minisign, ...).

set -u
set -o pipefail

MUTATE=0
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=1 ;;
        *) echo "unknown argument: $a" >&2; exit 99 ;;
    esac
done

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)" || exit 99
CMD='npm ci --prefix tools/dev'
FAILURES=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

TMP="$(mktemp -d)" || exit 99
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -r "$TMP" 2>/dev/null' EXIT

# Run a verify script in a clone with no argument and no WOM_NODE_MODULES (the default-location path).
run_default() { # dir script [extra args...]
    local d="$1" s="$2"; shift 2
    ( cd "$d" && env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "docs/tasks/$s" "$@" ) 2>&1
}

# Criterion 1 check, on a directory: exact pin in package.json, lock resolves ajv 8.20.0 with integrity.
pin_check() { # dir -> prints reason, returns 0 if good
    python3 -I - "$1/tools/dev/package.json" "$1/tools/dev/package-lock.json" <<'PYE'
import json, sys
pkg = json.load(open(sys.argv[1])); lock = json.load(open(sys.argv[2]))
deps = {**pkg.get("dependencies", {}), **pkg.get("devDependencies", {})}
spec = deps.get("ajv")
if spec != "8.20.0":
    print("package.json ajv spec is %r, not exactly '8.20.0'" % spec); sys.exit(1)
ent = lock.get("packages", {}).get("node_modules/ajv", {})
if ent.get("version") != "8.20.0" or not str(ent.get("integrity", "")).startswith("sha"):
    print("lock ajv entry is %r" % {k: ent.get(k) for k in ("version", "integrity")}); sys.exit(1)
print("package.json pins ajv '8.20.0'; lock resolves ajv %s, integrity %s..." % (ent["version"], ent["integrity"][:20]))
PYE
}

# Criterion 4 check on a clone WITHOUT an install: both scripts fail and name the command.
absent_check() { # dir label -> sets A4_* results via output
    local d="$1" n=0 s out rc
    for s in 057-verify.sh 062-verify.sh; do
        out="$(run_default "$d" "$s")"; rc=$?
        if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF "$CMD"; then
            echo "  $s: exit $rc, output names '$CMD'"
        else
            echo "  $s: exit $rc, names command: $(printf '%s\n' "$out" | grep -cF "$CMD")"; n=$((n + 1))
        fi
    done
    return "$n"
}

section "1 pin and lock (criterion 1)"
HEADC="$TMP/head"
git clone -q "$ROOT" "$HEADC" || { fail "setup: cannot clone $ROOT"; exit 99; }
if out="$(pin_check "$HEADC")"; then pass "C1 $out"; else fail "C1 $out"; fi

section "2 fresh clone, install (criterion 2)"
INST="$TMP/inst"
git clone -q "$ROOT" "$INST" || { fail "setup: cannot clone"; exit 99; }
echo "NETWORKED STEP: $CMD in a fresh clone (public npm registry, anonymous)"
if ( cd "$INST" && npm ci --prefix tools/dev --userconfig /dev/null --ignore-scripts --no-audit --no-fund ) > "$TMP/npmci.out" 2>&1; then
    tail -n 2 "$TMP/npmci.out" | sed 's/^/  npm: /'
    echo "OFFLINE from here on."
    V="$(node -p "require('$INST/tools/dev/node_modules/ajv/package.json').version" 2>&1)"
    [ "$V" = "8.20.0" ] && pass "C2 npm ci succeeded; tools/dev/node_modules/ajv reports $V" || fail "C2 installed ajv reports '$V', expected 8.20.0"
else
    sed 's/^/  npm: /' "$TMP/npmci.out"; fail "C2 npm ci failed"
fi

section "3 default location, no argument, no env (criterion 3)"
OUT57="$(run_default "$INST" 057-verify.sh)"; rc57=$?
printf '%s\n' "$OUT57" | grep -E 'ajv 8\.|^(PASS|FAIL)  V1'
printf '%s\n' "$OUT57" | grep -q '^PASS  V1' && pass "C3a 057-verify.sh V1 passes by default (057 exit $rc57)" || fail "C3a 057-verify.sh V1 did not pass by default"
OUT62="$(run_default "$INST" 062-verify.sh)"; rc62=$?
printf '%s\n' "$OUT62" | tail -n 3
{ [ "$rc62" = 0 ] && printf '%s\n' "$OUT62" | grep -q 'ALL CHECKS PASSED'; } && pass "C3b 062-verify.sh reports ALL CHECKS PASSED by default" || fail "C3b 062-verify.sh exit $rc62, no ALL CHECKS PASSED"

section "4 install absent -> red, names the command (criterion 4)"
ABS="$TMP/absent"
git clone -q "$ROOT" "$ABS" || { fail "setup: cannot clone"; exit 99; }
[ ! -e "$ABS/tools/dev/node_modules" ] && echo "  (tools/dev/node_modules absent in this clone)"
if out="$(absent_check "$ABS")"; then pass "C4 both scripts fail without an install and name the command"; else fail "C4 a script did not fail or did not name the command"; fi
printf '%s\n' "$out"

section "5 explicit argument and WOM_NODE_MODULES override the default (criterion 5)"
# The absent clone has no default install, so a pass there can only come from the override.
NMI="$INST/tools/dev/node_modules"
o="$( cd "$ABS" && env -u WOM_NODE_MODULES bash docs/tasks/057-verify.sh "$NMI" 2>&1 )"
printf '%s\n' "$o" | grep -q '^PASS  V1' && pass "C5a argument overrides: 057 V1 passes in the clone with no default install" || fail "C5a argument did not override"
o="$( cd "$ABS" && WOM_NODE_MODULES="$NMI" bash docs/tasks/057-verify.sh 2>&1 )"
printf '%s\n' "$o" | grep -q '^PASS  V1' && pass "C5b WOM_NODE_MODULES overrides: 057 V1 passes" || fail "C5b env did not override"
o="$( cd "$ABS" && WOM_NODE_MODULES="$NMI" bash docs/tasks/062-verify.sh 2>&1 )"; rc=$?
{ [ "$rc" = 0 ] && printf '%s\n' "$o" | grep -q 'ALL CHECKS PASSED'; } && pass "C5c WOM_NODE_MODULES overrides: 062 ALL CHECKS PASSED" || fail "C5c 062 env override failed (exit $rc)"
if [ -d /tmp/fc041/node_modules/ajv ]; then
    o="$( cd "$ABS" && env -u WOM_NODE_MODULES bash docs/tasks/057-verify.sh /tmp/fc041/node_modules 2>&1 )"
    printf '%s\n' "$o" | grep -q '^PASS  V1' && pass "C5d /tmp/fc041/node_modules via argument also passes" || fail "C5d /tmp/fc041 argument failed"
fi

section "6 no ajv or node in the runtime path (criterion 6)"
# Positive control first: the same search must find ajv where it is declared.
if grep -rIni 'ajv' "$HEADC/tools/dev/package.json" >/dev/null; then pass "C6a positive control: the ajv search finds ajv in tools/dev/package.json"; else fail "C6a positive control: the ajv search found nothing in tools/dev/package.json"; fi
H="$(grep -rIni 'ajv' "$HEADC/tools/registry" 2>/dev/null)"
[ -z "$H" ] && pass "C6b no 'ajv' anywhere under tools/registry/" || { fail "C6b 'ajv' found under tools/registry/"; printf '%s\n' "$H"; }
# Positive control for the node search: it must find a node invocation in a known script.
NODERE='(^|[^A-Za-z0-9_./-])(node|nodejs|npx|npm)([[:space:]]|$)'
if grep -Eq "$NODERE" "$HEADC/docs/tasks/057-verify.sh"; then pass "C6c positive control: the node search matches an invocation in 057-verify.sh"; else fail "C6c node search does not match 057-verify.sh"; fi
H="$(grep -rInE "$NODERE" "$HEADC/tools/registry" 2>/dev/null)"
[ -z "$H" ] && pass "C6d no node/npm/npx invocation under tools/registry/" || { fail "C6d node/npm invocation found under tools/registry/"; printf '%s\n' "$H"; }

section "7 gitignore covers the install (criterion 7)"
U="$(git -C "$INST" status --porcelain)"
[ -z "$U" ] && pass "C7 git status in the clone after npm ci is empty (no untracked files)" || { fail "C7 git status not clean after npm ci"; printf '%s\n' "$U"; }

if [ "$MUTATE" = 1 ]; then
    section "8 mutations, each must be red (criterion 8)"
    mclone() { [ -d "$TMP/m" ] && rm -r "$TMP/m"; cp -a "$INST" "$TMP/m"; }       # installed clone, including node_modules

    mclone; sed -i 's/"ajv": "8.20.0"/"ajv": "^8.20.0"/' "$TMP/m/tools/dev/package.json"
    if out="$(pin_check "$TMP/m")"; then fail "M1 range pin ^8.20.0 did NOT redden the pin check"; else pass "M1 range pin reddens C1: $out"; fi

    mclone; sed -i 's|^NM="\${1:-.*|NM="${1:-}"|' "$TMP/m/docs/tasks/057-verify.sh"
    grep -q '^NM="\${1:-}"$' "$TMP/m/docs/tasks/057-verify.sh" || fail "M2 mutation did not apply"
    o="$(run_default "$TMP/m" 057-verify.sh)"
    if printf '%s\n' "$o" | grep -q '^PASS  V1'; then fail "M2 default path removed from 057 but V1 still passes"; else pass "M2 default path removed from 057-verify.sh reddens C3a: $(printf '%s\n' "$o" | grep -m1 '^FAIL  V1')"; fi

    mclone; rm -rf "$TMP/m/tools/dev/node_modules"
    sed -i "s|npm ci --prefix tools/dev|install the dependencies|g" "$TMP/m/docs/tasks/057-verify.sh" "$TMP/m/docs/tasks/062-verify.sh"
    if absent_check "$TMP/m" >/dev/null; then fail "M3 failure message without the command did NOT redden C4"; else pass "M3 failure message without the command reddens C4"; fi

    mclone; sed -i '/^node_modules\/$/d' "$TMP/m/.gitignore"
    U="$(git -C "$TMP/m" status --porcelain | grep '^??')"
    [ -n "$U" ] && pass "M4 .gitignore line removed reddens C7: $(printf '%s\n' "$U" | head -n 1)" || fail "M4 .gitignore line removed but git status still shows no untracked files"
fi

section "RESULT"
if [ "$FAILURES" = 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILURES CHECK(S) FAILED"; fi
exit "$FAILURES"
