#!/usr/bin/env bash
#
# 032-mutations.sh -- the mutation set for task 032's verification suite (fix round 6).
#
# Each mutation edits contracts/ownership.md in the working tree, runs the verify script, prints
# the verdict and the checks that went red, and restores the file with `git checkout`. The suite
# is expected to go RED for every mutation below. Run from the worktree root, on a clean tree:
#
#     bash docs/tasks/032-mutations.sh                 # against docs/tasks/032-verify.sh
#     VERIFY=/path/to/older-verify.sh bash docs/tasks/032-mutations.sh   # against another copy
#
# Exit 0 if every mutation reddened the suite; 1 if any mutation stayed green (a blind spot).
# ONLY=TA runs only mutations whose name starts with TA.
# Set EXPECT_GREEN=1 to invert the expectation (used once, to show the round-6 defect: the
# tail-append mutations were GREEN against the round-5 script).
set -u
VERIFY=${VERIFY:-docs/tasks/032-verify.sh}
DOC=contracts/ownership.md
[ -z "$(git status --short -- "$DOC")" ] || { echo "refusing to run: $DOC is not clean"; exit 2; }
BAD=0
mut() {  # mut NAME OLD NEW   -- OLD must occur exactly once in $DOC
    local name=$1 old=$2 new=$3
    [ -z "${ONLY:-}" ] || case "$name" in "$ONLY"*) ;; *) return;; esac
    OLD="$old" NEW="$new" python3 -I - "$DOC" <<'PY' || { echo "MUTATION $name: OLD text not found exactly once -- fixture is broken"; BAD=1; return; }
import os, sys
p = sys.argv[1]; t = open(p, encoding="utf-8").read()
old, new = os.environ["OLD"], os.environ["NEW"]
if t.count(old) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(t.replace(old, new))
PY
    local out rc
    out=$(bash "$VERIFY" 2>/dev/null); rc=$?
    local reds; reds=$(printf '%s\n' "$out" | grep '^FAIL' | awk '{print $2}' | tr '\n' ' ')
    printf '%-62s exit=%-2s %s PASS %s FAIL  red: %s\n' "$name" "$rc" \
        "$(printf '%s\n' "$out" | grep -c '^PASS')" "$(printf '%s\n' "$out" | grep -c '^FAIL')" "${reds:-(none)}"
    git checkout -- "$DOC"
    if [ "${EXPECT_GREEN:-0}" = 1 ]; then [ "$rc" = 0 ] || BAD=1; else [ "$rc" != 0 ] || BAD=1; fi
}

# --- round 6, finding 1: a tail appended AFTER character 70 of a pinned sentence ---------------
mut "TA-R3 tail appended to R3's pinned declaration sentence" \
    "reconciled by a reader. This is the ordinary" \
    "reconciled by a reader, and \`R9\` does not apply either. This is the ordinary"
mut "TA-R7 tail appended to R7's pinned declaration sentence" \
    "with exactly the
precedence \`R3\` states above:" \
    "with exactly the
precedence \`R3\` states above, and \`R9\` does not apply either:"

# --- round 6, items 5: P17 / P22 / P23 must be able to fail on the CONFIRMED wording -----------
mut "P22 R11's cardinality weakened to 'exactly one' (D2)" \
    "any number, provided the diff contains nothing else" \
    "exactly one, and the diff contains nothing else"
mut "P22 R11's D2 confirmation marking removed" \
    "2026-10-14**: the strict reading (one version per PR)" \
    "2026-09-08**: the strict reading (one version per PR)"
mut "P17 R11's D1 confirmation marking removed from its paragraph" \
    "owned or not (confirmed by Ludwig, 2026-10-14), deliberately" \
    "owned or not, deliberately"
mut "P23 scope note's 'confirmed by Ludwig, 2026-10-14' removed" \
    "(manager, 2026-09-08; **confirmed by Ludwig, 2026-10-14**)" \
    "(manager, 2026-09-08)"
mut "P23b a 'pending Ludwig's confirmation' marking re-introduced" \
    "Ludwig confirmed that reading on 2026-10-14, so" \
    "pending Ludwig's confirmation, so"

# --- regression: the round-5 exception mutations M2/M3 stay red (unchanged paths) -------------
mut "M2 'overridden by R3' sentence added to R10" \
    "that namespace exists at the merge-base, and none is created in the same diff, MUST be rejected." \
    "that namespace exists at the merge-base, and none is created in the same diff, MUST be rejected. This rule is overridden by \`R3\`."
mut "M3 'unless R9' added to R5's declaration" \
    "**R5 (MUST)** — at a first publish of a namespace **not** on the reserved list," \
    "**R5 (MUST)** — unless \`R9\` has already rejected the PR, at a first publish of a namespace **not** on the reserved list,"
exit $BAD
