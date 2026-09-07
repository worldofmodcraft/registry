#!/usr/bin/env bash
#
# 032-verify.sh -- the runnable verification artefact for task 032.
#
# MANAGER.md Section 2c: "Any task whose acceptance criteria are command-based ships
# docs/tasks/NNN-verify.sh, committed and executable." Round 1's own finding B6 is the
# reason this script exists: a fabricated `--jq` output was pasted into contracts/ownership.md
# and into this task's own log, and nothing but hand-running six commands caught it. This
# script makes that kind of fabrication detectable by construction.
#
# Usage:  ./docs/tasks/032-verify.sh          (run from the worktree root, no arguments)
# Exit:   0 if every check that decides the verdict passed, non-zero otherwise (the failure
#         count). The exit code depends ONLY on the deterministic checks below -- see
#         "FIX ROUND 2" for why that is now a hard guarantee, not just a convention.
#
# BOUNDARY -- read before adding anything here.
# This script verifies task 032's acceptance criteria. It implements NO ownership check: it
# never reads a real PR diff, never decides whether a submitter is authorised to touch a
# namespace, and never enforces anything. That is task 007's job and is forbidden here. What
# this script does is exactly three kinds of thing:
#   (1) assert textual facts about contracts/ownership.md and the two other prose files this
#       task touched (docs/tasks/032-ownership-contract.md, docs/contracts/README.md) -- these
#       are prose contracts; nothing executes them, so "the document says X" is the only kind of
#       proof available for their content;
#   (2) cross-check the document's pasted transcripts against RECORDED FIXTURES -- files
#       committed under docs/tasks/, captured once from real commands, carrying inline when/how/
#       against-what metadata (see "FIX ROUND 2" below) -- and, only as an ADVISORY bonus, a live
#       re-run of the same commands, never required for the verdict;
#   (3) run a structural check, in Python, against the pre-fix blob of contracts/ownership.md
#       (pinned at commit fcde6d5, the commit fix round 1 started from) and against the current
#       working tree, to prove finding B6's fabrication would have been caught by a check that
#       existed before the fix (MANAGER.md Section 2c rule 5).
#
# FIX ROUND 2 (2026-09-06) -- why the design changed, and what "advisory" means here.
# The manager's independent re-run (finding F-B, logged below "Manager verification of fix round
# 1") reproduced the artefact reporting "ALL CHECKS PASSED" / exit 0 while B1's checks -- the
# round's headline finding, the one that would have rejected every legitimate reserved-namespace
# PR -- were silently SKIPPED for an unauthenticated GitHub API rate limit exhaustion (60
# requests/hour, shared per source IP, easily exhausted by this project's own mutation testing).
# A live network call inside an artefact that must re-run identically on any machine at any hour
# is neither portable nor deterministic (Section 2c rule 4), and a skip that still yields a green
# verdict is exactly the "asserted, not demonstrated" failure shape Section 2c exists to close.
#
# The fix: B1's evidence is now RECORDED FIXTURES (docs/tasks/032-b1-fixtures.json), captured
# once from real, unauthenticated curl calls, carrying their own capture date, exact command, and
# target inline (so a reader can re-capture and diff). The checks that decide this script's exit
# code compare the document's pasted transcripts against that committed fixture -- a pure text
# comparison, zero network calls, same result on any machine at any hour. A live re-run of the
# same commands is kept as a clearly-labelled ADVISORY section: printed for extra confidence when
# network is reachable, but it NEVER increments the failure count and NEVER gates the exit code,
# in either direction -- a live check that could pass or fail unpredictably has no business
# deciding a verdict that must be reproducible. The same treatment is applied to the B6 live
# `gh api` diff section for the identical reason: it depends on an active `gh` identity, which is
# not guaranteed on every machine, and B6's actual defect-catching power lives entirely in the
# deterministic pinned-blob check (B6.1-B6.4) below, not in the live diff.
#
# DETERMINISM. Every check that contributes to $FAILURES (and therefore to the exit code) reads
# only committed repository content -- contracts/ownership.md, the fixture file, the pinned git
# blob, the local test suite -- and makes no network call. Same repository content, same result,
# on any machine, with or without network, with or without an active `gh` identity. The ADVISORY
# sections make real network/`gh` calls when available and report drift for a human to notice;
# their availability depends on the environment, and that is exactly why they cannot be load-
# bearing for the verdict.

set -u
set -o pipefail

DOC="contracts/ownership.md"
TASKLOG="docs/tasks/032-ownership-contract.md"
CONTRACTS_README="docs/contracts/README.md"
B1_FIXTURE="docs/tasks/032-b1-fixtures.json"
# The task file's own header -- everything before the first `---` separator, i.e. the spec, the
# Context list and the acceptance-criteria evidence, and NOT the review rounds or the round logs.
# Checks about "what this task's Context list contains" must read this and not the whole file:
# the round logs paste this script's own output, and that output echoes the paragraphs it matched,
# so a whole-file check would match its own evidence and report a duplicate. Found by this
# script's own uniqueness rule during fix round 3, immediately after the round-3 log was appended.
TASKLOG_HEADER="$(mktemp -t 032-tasklog-header.XXXXXX)"
trap 'rm -f "$TASKLOG_HEADER"' EXIT
awk '/^---$/ { exit } { print }' "$TASKLOG" > "$TASKLOG_HEADER"
PREFIX_BLOB="fcde6d5:contracts/ownership.md"   # the commit fix round 1 started from
FAILURES=0
ADVISORY_OK=0
ADVISORY_DRIFT=0
ADVISORY_SKIP=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
# ADVISORY: for live/network/gh-auth-dependent checks only. These NEVER touch $FAILURES in
# either direction -- not on drift, not on skip -- because a check whose availability or outcome
# depends on the network or an active `gh` identity cannot be allowed to decide a verdict that
# must be reproducible on any machine at any hour (fix round 2, finding F-B). They exist purely
# to give a human extra confidence when the environment permits it.
advise_pass() { printf 'ADVISORY-PASS  %s\n' "$1"; ADVISORY_OK=$((ADVISORY_OK + 1)); }
advise_drift() { printf 'ADVISORY-DRIFT %s\n' "$1"; ADVISORY_DRIFT=$((ADVISORY_DRIFT + 1)); }
advise_skip() { printf 'ADVISORY-SKIP  %s -- network/gh-auth unavailable, advisory only, never affects the verdict or exit code\n' "$1"; ADVISORY_SKIP=$((ADVISORY_SKIP + 1)); }

expect_hits() {
    local label="$1" pattern="$2" file="${3:-$DOC}" hits
    hits=$(grep -nE "$pattern" "$file")
    if [ -z "$hits" ]; then
        fail "$label -- pattern matched nothing in $file (a search that finds nothing is a broken search, not a clean document)"
    else
        pass "$label"
        printf '%s\n' "$hits" | sed 's/^/        /'
    fi
}

expect_hits_flow() {
    # Same as expect_hits, but joins each blank-line-delimited paragraph into one line
    # first. Prose in these documents wraps at ~90-100 columns for readability -- that
    # wrapping is presentational, not semantic (the same "whitespace carries no meaning"
    # principle contracts/append-only.rules.md states for entry.json applies to reading
    # prose too), so a phrase split across a line break by the text wrapper is not absent
    # from the document. Line numbers are not reported here (paragraph joining loses them);
    # the matching paragraph text is printed instead.
    local label="$1" pattern="$2" file="${3:-$DOC}" hits
    hits=$(awk 'BEGIN{RS="";ORS="\n-----\n"} {gsub(/\n/," "); print}' "$file" | grep -E "$pattern")
    if [ -z "$hits" ]; then
        fail "$label -- pattern matched nothing in $file, even after joining wrapped lines within each paragraph"
    else
        pass "$label"
        printf '%s\n' "$hits" | sed 's/^/        /'
    fi
}

expect_no_hits() {
    local label="$1" pattern="$2" file="${3:-$DOC}"
    if grep -nE "$pattern" "$file" > /dev/null; then
        fail "$label -- pattern still present in $file (expected it gone)"
    else
        pass "$label"
    fi
}

# --- Scoping helpers (fix round 3, finding B5) -----------------------------------------------
# Round-2 finding B5: `expect_hits`/`expect_hits_flow` search the WHOLE document, so a check
# named after one section goes green because some OTHER paragraph happens to contain the two
# strings the pattern names. That is a check that is green for the wrong reason -- worse than no
# check, because it manufactures confidence (MANAGER.md Section 2c rule 2). B5 was raised as a
# CLASS, not an instance, so every pattern-matching check in this file is now bound to the
# narrowest region that can honestly carry its claim:
#   expect_hits_in       -- one `## ` section
#   expect_hits_in_para  -- ONE blank-line-delimited paragraph, identified by a unique anchor
#                           (if the anchor matches more than one paragraph the check FAILS, so
#                           the scoping itself cannot silently rot into whole-document scope)
# Both flatten line wrapping inside the region first: the ~95-column wrapping in these documents
# is presentational, so a phrase split by the wrapper is not absent from the text.
# The unscoped expect_hits/expect_hits_flow above are kept ONLY for claims that are genuinely
# about the whole document (e.g. "this string appears nowhere"), and each remaining use says so.

section_heading_count() {
    local pat="$1" file="${2:-$DOC}"
    grep -cE "^## .*$pat" "$file" 2>/dev/null || printf '0'
}

section_of() {
    # Body of the `## ` section whose heading matches ERE $1, up to (not including) the next `## `.
    # Callers must first check section_heading_count: a pattern matching two headings is not a
    # scope, and silently taking the first one is how a scoped check rots back into an unscoped
    # one. (Caught by this script on itself during fix round 3: two headings contained the words
    # "rejection taxonomy", so every check scoped to it was reading the wrong section.)
    local pat="$1" file="${2:-$DOC}"
    awk -v pat="$pat" '
        /^## / { if (inside) exit; if ($0 ~ pat) inside = 1 }
        inside { print }
    ' "$file"
}

expect_hits_in() {
    # $1 label, $2 section-heading ERE, $3 content ERE, $4 file (default $DOC)
    local label="$1" secpat="$2" pattern="$3" file="${4:-$DOC}" body hits nsec
    nsec=$(section_heading_count "$secpat" "$file")
    if [ "$nsec" -ne 1 ]; then
        fail "$label -- /$secpat/ matches $nsec '## ' headings in $file; a section pattern that is not unique is not a scope"
        return
    fi
    body=$(section_of "$secpat" "$file")
    if [ -z "$body" ]; then
        fail "$label -- no '## ' section matching /$secpat/ in $file (the scope itself is missing, so the claim cannot be checked)"
        return
    fi
    hits=$(printf '%s\n' "$body" | awk 'BEGIN{RS=""} {gsub(/\n/," "); print}' | grep -E "$pattern")
    if [ -z "$hits" ]; then
        fail "$label -- pattern /$pattern/ matched nothing inside the section /$secpat/ (that section only, never the whole document)"
    else
        pass "$label"
        printf '%s\n' "$hits" | cut -c1-300 | sed 's/^/        /'
    fi
}

expect_no_hits_in() {
    local label="$1" secpat="$2" pattern="$3" file="${4:-$DOC}" body nsec
    nsec=$(section_heading_count "$secpat" "$file")
    if [ "$nsec" -ne 1 ]; then
        fail "$label -- /$secpat/ matches $nsec '## ' headings in $file; a section pattern that is not unique is not a scope"
        return
    fi
    body=$(section_of "$secpat" "$file")
    if [ -z "$body" ]; then
        fail "$label -- no '## ' section matching /$secpat/ in $file"
        return
    fi
    if printf '%s\n' "$body" | awk 'BEGIN{RS=""} {gsub(/\n/," "); print}' | grep -qE "$pattern"; then
        fail "$label -- pattern /$pattern/ still present inside the section /$secpat/ (expected it gone)"
    else
        pass "$label"
    fi
}

expect_hits_in_para() {
    # $1 label, $2 anchor ERE identifying EXACTLY ONE paragraph, $3 content ERE, $4 file.
    # The uniqueness requirement is the point: an anchor that matches several paragraphs is not a
    # scope, and the check fails rather than quietly widening to whichever paragraph matched.
    local label="$1" anchor="$2" pattern="$3" file="${4:-$DOC}" paras n
    paras=$(awk 'BEGIN{RS=""} {gsub(/\n/," "); print}' "$file" | grep -E "$anchor")
    n=$(printf '%s' "$paras" | grep -c . || true)
    if [ "$n" -eq 0 ]; then
        fail "$label -- anchor /$anchor/ matched no paragraph in $file"
        return
    fi
    if [ "$n" -ne 1 ]; then
        fail "$label -- anchor /$anchor/ matched $n paragraphs in $file; an anchor that is not unique is not a scope"
        return
    fi
    if printf '%s\n' "$paras" | grep -qE "$pattern"; then
        pass "$label"
        printf '%s\n' "$paras" | cut -c1-300 | sed 's/^/        /'
    else
        fail "$label -- pattern /$pattern/ absent from the ONE paragraph anchored by /$anchor/ (that paragraph only)"
    fi
}

section() { printf '\n== %s ==\n' "$1"; }

printf '032-verify.sh -- task 032 fix-round-1 acceptance verification\n'
printf 'repo root: %s\n' "$(git rev-parse --show-toplevel)"
printf 'doc: %s (%s lines)\n' "$DOC" "$(wc -l < "$DOC" | tr -d ' ')"

# --------------------------------------------------------------------------------
section "B6 -- the fixture that would have caught the fabrication, shown failing against the pre-fix blob"

# This is MANAGER.md Section 2c rule 5's required shape: the found break enters the suite as a
# fixture BEFORE the fix, shown failing, and the fix is then shown turning it green. Because this
# round both finds and fixes B6 in one pass, the "before" state is the real pre-fix commit
# (fcde6d5), pinned by hash so this stays true forever, not the current working tree.
python3 - "$PREFIX_BLOB" <<'PY'
import re, subprocess, sys, json

prefix_blob = sys.argv[1]

def extract_pr3_json(text):
    # Find the line following the `gh api ... pulls/3 --jq '{merged, user:...}'` command and
    # parse it as JSON. Returns (json_obj, found_line) or (None, None) if the command isn't
    # present at all (a search that finds nothing is a broken search, not a clean result).
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if "pulls/3 --jq" in line and "merged, user" in line:
            if i + 1 < len(lines):
                candidate = lines[i + 1].strip()
                try:
                    return json.loads(candidate), candidate
                except json.JSONDecodeError:
                    return None, candidate
    return None, None

def check(label, text):
    obj, raw = extract_pr3_json(text)
    if obj is None:
        print("  FAIL  %s -- PR#3 command/output not found or not valid JSON (raw: %r)" % (label, raw))
        return False
    # The filter is `{merged, user:{login:.user.login,id:.user.id}}` -- exactly two top-level
    # keys, and exactly two keys under `user`. Any other key (e.g. "number") cannot be emitted
    # by this filter and is a fabrication.
    top_keys = set(obj.keys())
    user_keys = set(obj.get("user", {}).keys()) if isinstance(obj.get("user"), dict) else set()
    expected_top = {"merged", "user"}
    expected_user = {"login", "id"}
    if top_keys == expected_top and user_keys == expected_user:
        print("  PASS  %s -- exact key set %s / user %s, matches what the two-key filter can emit" % (label, sorted(top_keys), sorted(user_keys)))
        return True
    else:
        print("  FAIL  %s -- key set %s / user %s does not match what the filter can emit (expected top=%s, user=%s)" % (
            label, sorted(top_keys), sorted(user_keys), sorted(expected_top), sorted(expected_user)))
        return False

# Pre-fix: the real committed blob at the round's start commit.
prefix_text = subprocess.run(["git", "show", prefix_blob], capture_output=True, text=True, check=True).stdout
print("$ git show %s | (parse the PR#3 transcript)" % prefix_blob)
prefix_ok = check("B6.1 pre-fix blob (fcde6d5) -- MUST be red (the known fabrication)", prefix_text)

# Post-fix: the current working tree.
with open("contracts/ownership.md") as f:
    current_text = f.read()
print("$ (parse the PR#3 transcript in the current working tree)")
current_ok = check("B6.2 current working tree -- MUST be green (the fix)", current_text)

if prefix_ok:
    print("  ERROR: the pre-fix blob passed the fixture -- this fixture would NOT have caught B6, contradicting the finding.")
    sys.exit(1)
if not current_ok:
    print("  ERROR: the current working tree still fails the fixture -- B6 is not actually fixed.")
    sys.exit(1)
print("  Fixture demonstrated: red against fcde6d5, green against the current fix. (Section 2c rule 5.)")
sys.exit(0)
PY
if [ $? -eq 0 ]; then
    pass "B6.3 the B6 fixture reddens against the pre-fix blob and passes against the fix (Section 2c rule 5 shape)"
else
    fail "B6.4 the B6 fixture did not behave as required -- see Python output above"
fi

# --------------------------------------------------------------------------------
section "B6 -- ADVISORY: live re-run of every command pasted in the document, diffed against the paste (never gates the verdict -- fix round 2)"
# B6's actual defect-catching power is the deterministic pinned-blob check above (B6.1-B6.4),
# which needs no network and cannot be skipped. This section is a bonus freshness check: it
# depends on an active `gh` identity, which is not guaranteed on every machine, so -- per the
# same fix-round-2 design applied to B1 below -- none of its outcomes touch $FAILURES.

if ! gh auth status > /dev/null 2>&1; then
    advise_skip "B6.5 gh auth status -- no active gh identity, live gh api checks skipped"
else
    LIVE_PR3=$(gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}' 2>/dev/null)
    DOC_PR3=$(grep -A1 "pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'" "$DOC" | tail -1)
    printf '  $ gh api repos/worldofmodcraft/registry/pulls/3 --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_PR3" "$DOC_PR3"
    if [ -n "$LIVE_PR3" ] && [ "$LIVE_PR3" = "$DOC_PR3" ]; then
        advise_pass "B6.6 live PR#3 shape matches the document's paste exactly"
    else
        advise_drift "B6.7 live PR#3 shape ($LIVE_PR3) does not match the document's paste ($DOC_PR3)"
    fi

    LIVE_ORG=$(gh api orgs/worldofmodcraft --jq '{login,id,type}' 2>/dev/null)
    DOC_ORG=$(grep -A1 "gh api orgs/worldofmodcraft --jq '{login,id,type}'" "$DOC" | tail -1)
    printf '  $ gh api orgs/worldofmodcraft --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_ORG" "$DOC_ORG"
    if [ -n "$LIVE_ORG" ] && [ "$LIVE_ORG" = "$DOC_ORG" ]; then
        advise_pass "B6.8 live org id/login/type matches the document's paste exactly"
    else
        advise_drift "B6.9 live org id/login/type ($LIVE_ORG) does not match the document's paste ($DOC_ORG)"
    fi

    LIVE_REPO=$(gh api repos/worldofmodcraft/registry --jq '{full_name,owner:{login:.owner.login,id:.owner.id,type:.owner.type}}' 2>/dev/null)
    DOC_REPO=$(grep -A1 "gh api repos/worldofmodcraft/registry --jq '{full_name,owner:" "$DOC" | tail -1)
    printf '  $ gh api repos/worldofmodcraft/registry --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_REPO" "$DOC_REPO"
    if [ -n "$LIVE_REPO" ] && [ "$LIVE_REPO" = "$DOC_REPO" ]; then
        advise_pass "B6.10 live repo-owner shape matches the document's paste exactly (including nested key order)"
    else
        advise_drift "B6.11 live repo-owner shape ($LIVE_REPO) does not match the document's paste ($DOC_REPO)"
    fi

    LIVE_MEMBER_STATUS=$(gh api orgs/worldofmodcraft/members/womcraft -i 2>/dev/null | head -1 | tr -d '\r')
    if [ "$LIVE_MEMBER_STATUS" = "HTTP/2.0 204 No Content" ]; then
        advise_pass "B6.12 live member-caller membership check for womcraft returns 204 (matches the document)"
    else
        advise_drift "B6.13 live member-caller membership check returned '$LIVE_MEMBER_STATUS', expected 'HTTP/2.0 204 No Content'"
    fi

    LIVE_GHOST=$(gh api users/ghost --jq '{login,id,type}' 2>/dev/null)
    DOC_GHOST=$(grep -A1 "gh api users/ghost --jq '{login,id,type}'" "$DOC" | tail -1)
    printf '  $ gh api users/ghost --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_GHOST" "$DOC_GHOST"
    if [ -n "$LIVE_GHOST" ] && [ "$LIVE_GHOST" = "$DOC_GHOST" ]; then
        advise_pass "B6.14 live ghost-account shape matches the document's paste exactly"
    else
        advise_drift "B6.15 live ghost-account shape ($LIVE_GHOST) does not match the document's paste ($DOC_GHOST)"
    fi
fi

# --------------------------------------------------------------------------------
section "B1 -- the org-membership endpoint: recorded fixture, deterministic, no network required (fix round 2, finding F-B)"
# This is the section that used to make a live, unauthenticated curl call and SKIP -- silently,
# with the verdict unaffected -- when GitHub's 60-request/hour unauthenticated quota was
# exhausted (finding F-B). The checks below never touch the network: they read the committed
# fixture docs/tasks/032-b1-fixtures.json (captured once, with inline when/how/against-what
# metadata) and compare it against the document's own pasted transcripts. Same result, any
# machine, any hour, network or none.

if [ ! -f "$B1_FIXTURE" ]; then
    fail "B1.0 fixture file $B1_FIXTURE is missing -- B1's evidence has nowhere to be recorded"
else
    python3 - "$B1_FIXTURE" "$DOC" <<'PY'
import json, re, sys

fixture_path, doc_path = sys.argv[1], sys.argv[2]
failures = 0

def pf(label, ok, detail=""):
    global failures
    if ok:
        print("PASS  %s" % label)
    else:
        failures += 1
        print("FAIL  %s%s" % (label, (" -- " + detail) if detail else ""))

with open(fixture_path) as f:
    fx = json.load(f)

# --- Fixture provenance: a fixture with no capture metadata is not evidence (round-2 spec). ---
meta = fx.get("_meta", {})
required_meta = ["captured_at", "captured_by", "against", "how_to_recapture"]
missing = [k for k in required_meta if not meta.get(k)]
pf("B1.0a fixture carries its own capture date/command/target metadata inline",
   not missing, "missing keys: %s" % missing)

with open(doc_path) as f:
    doc = f.read()

def doc_has_line(literal):
    return literal in doc

# --- Probe 1: unauthenticated GET /orgs/{org}/members/{username} -> 302 + redirect target. ---
p1 = fx["unauthenticated_members_endpoint"]
print("  fixture (captured %s): %s" % (meta.get("captured_at", "?"), p1["recorded_output"]))
pf("B1.2 fixture records status=302 for the unauthenticated members-endpoint probe",
   p1["status"] == 302, "fixture says status=%s" % p1["status"])
pf("B1.3 the document's pasted transcript matches the fixture's recorded status=302/redirect line exactly",
   doc_has_line(p1["recorded_output"]), "recorded_output=%r not found verbatim in %s" % (p1["recorded_output"], doc_path))
pf("B1.4 the fixture's redirect target is the public_members endpoint",
   "public_members" in p1["redirect_target"], "redirect_target=%r" % p1["redirect_target"])

# --- Probe 2: following the redirect (default client behaviour) -> 404. ---
p2 = fx["unauthenticated_members_endpoint_redirect_followed"]
print("  fixture (captured %s): %s" % (meta.get("captured_at", "?"), p2["recorded_output"]))
pf("B1.5 fixture records final_status=404 after following the redirect",
   p2["final_status"] == 404, "fixture says final_status=%s" % p2["final_status"])
pf("B1.6 the document's pasted transcript matches the fixture's recorded final_status=404 line exactly",
   doc_has_line(p2["recorded_output"]), "recorded_output=%r not found verbatim in %s" % (p2["recorded_output"], doc_path))

# --- Probe 3: unauthenticated GET /orgs/{org}/memberships/{username} -> 401 (refuses outright). ---
p3 = fx["unauthenticated_memberships_endpoint"]
print("  fixture (captured %s): %s" % (meta.get("captured_at", "?"), p3["recorded_output"]))
pf("B1.7 fixture records status=401 for the unauthenticated memberships-endpoint probe",
   p3["status"] == 401, "fixture says status=%s" % p3["status"])
pf("B1.8 the document's pasted transcript matches the fixture's recorded status=401 line exactly",
   doc_has_line(p3["recorded_output"]), "recorded_output=%r not found verbatim in %s" % (p3["recorded_output"], doc_path))

sys.exit(1 if failures else 0)
PY
    PYRC=$?
    if [ $PYRC -ne 0 ]; then
        fail "B1.9 one or more fixture-vs-document checks above failed (see the FAIL line(s) printed above, python exit=$PYRC)"
    fi
fi

# --------------------------------------------------------------------------------
section "B1 -- ADVISORY: live re-run of the same three probes against real GitHub, diffed against the fixture (never gates the verdict)"
# Kept for a human's extra confidence that the recorded fixture still matches GitHub's real,
# current behaviour. Never required, never load-bearing: whether this section runs, skips, or
# finds drift has zero effect on $FAILURES or the exit code -- that is the entire point of the
# fix (finding F-B). To re-capture the fixture itself (not just check for drift), see
# docs/tasks/032-b1-fixtures.json's own "how_to_recapture" field.

RATE_REMAINING=$(curl -s -m 10 https://api.github.com/rate_limit 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('resources',{}).get('core',{}).get('remaining','?'))" 2>/dev/null || echo "?")
if ! curl -s -m 10 -o /dev/null https://api.github.com 2>/dev/null; then
    advise_skip "B1-live reachability to api.github.com"
elif [ "$RATE_REMAINING" = "0" ]; then
    # GitHub's unauthenticated rate limit is 60 requests/hour per source IP -- a real,
    # demonstrated hazard (this project's own mutation testing exhausted it more than once).
    # This is exactly the condition finding F-B was about; the difference now is that hitting
    # it only skips an ADVISORY section, never the verdict.
    printf '  $ curl https://api.github.com/rate_limit -> core.remaining=%s\n' "$RATE_REMAINING"
    advise_skip "B1-live unauthenticated GitHub API rate limit exhausted (core.remaining=0) -- re-run after the reset time GitHub reports, or from a different source IP"
else
    printf '  $ curl https://api.github.com/rate_limit -> core.remaining=%s\n' "$RATE_REMAINING"
    FX_STATUS1=$(python3 -c "import json; print(json.load(open('$B1_FIXTURE'))['unauthenticated_members_endpoint']['status'])")
    FX_REDIRECT1=$(python3 -c "import json; print(json.load(open('$B1_FIXTURE'))['unauthenticated_members_endpoint']['redirect_target'])")
    FX_STATUS2=$(python3 -c "import json; print(json.load(open('$B1_FIXTURE'))['unauthenticated_members_endpoint_redirect_followed']['final_status'])")
    FX_STATUS3=$(python3 -c "import json; print(json.load(open('$B1_FIXTURE'))['unauthenticated_memberships_endpoint']['status'])")

    UNAUTH_STATUS=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    UNAUTH_REDIRECT=$(curl -s -m 10 -o /dev/null -w '%{redirect_url}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    printf '  $ curl (unauthenticated) -> status=%s redirect=%s   [fixture: status=%s redirect=%s]\n' \
        "$UNAUTH_STATUS" "$UNAUTH_REDIRECT" "$FX_STATUS1" "$FX_REDIRECT1"
    if [ "$UNAUTH_STATUS" = "$FX_STATUS1" ] && [ "$UNAUTH_REDIRECT" = "$FX_REDIRECT1" ]; then
        advise_pass "B1-live.1 live unauthenticated members-endpoint probe matches the recorded fixture"
    else
        advise_drift "B1-live.1 live unauthenticated members-endpoint probe (status=$UNAUTH_STATUS redirect=$UNAUTH_REDIRECT) drifted from the fixture (status=$FX_STATUS1 redirect=$FX_REDIRECT1) -- consider re-capturing"
    fi

    FOLLOWED_STATUS=$(curl -s -m 10 -L -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    printf '  $ curl -L (following the redirect) -> final_status=%s   [fixture: final_status=%s]\n' "$FOLLOWED_STATUS" "$FX_STATUS2"
    if [ "$FOLLOWED_STATUS" = "$FX_STATUS2" ]; then
        advise_pass "B1-live.2 live redirect-followed probe matches the recorded fixture"
    else
        advise_drift "B1-live.2 live redirect-followed probe (final_status=$FOLLOWED_STATUS) drifted from the fixture (final_status=$FX_STATUS2) -- consider re-capturing"
    fi

    MEMBERSHIPS_UNAUTH=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/memberships/womcraft)
    printf '  $ curl (unauthenticated) /memberships/{username} -> status=%s   [fixture: status=%s]\n' "$MEMBERSHIPS_UNAUTH" "$FX_STATUS3"
    if [ "$MEMBERSHIPS_UNAUTH" = "$FX_STATUS3" ]; then
        advise_pass "B1-live.3 live memberships-endpoint probe matches the recorded fixture"
    else
        advise_drift "B1-live.3 live memberships-endpoint probe (status=$MEMBERSHIPS_UNAUTH) drifted from the fixture (status=$FX_STATUS3) -- consider re-capturing"
    fi
fi

# ==============================================================================================
# FIX ROUND 3 (2026-09-07). Every check below this line is either NEW or a round-2 check
# re-bound to a narrow scope (finding B5, treated as a class). See the "SCOPE AUDIT" note at the
# end of this file for the count.
# ==============================================================================================

section "T -- the rejection taxonomy is DERIVED from the MUSTs, and drift is detectable (round-2 finding B1)"
# Round-2 finding B1: the document kept a prose list of failure modes BESIDE its MUST rules, and
# the two drifted -- twice, in two consecutive rounds, each time leaving a MUST with no rejection
# path. A promise not to let them drift again is worth nothing; this is the check instead.
# The convention the document now follows (stated in its own "How to read this document" section):
#   * every rule that can reject a PR is declared as `**Rn (MUST)** -- ...` at the start of a line
#   * every rule that constrains the checker without rejecting a PR is declared `**In (MUST)**`
#   * every normative MUST/MUST NOT sits in a paragraph that cites a rule id
#   * the rejection taxonomy has exactly one row per declared R-rule, and no row without one
# Any of those four broken -- a MUST added with no id, a rule with no taxonomy row, a taxonomy row
# for a rule that no longer exists -- turns this section red.

python3 - "$DOC" <<'PY'
import re, sys

doc_path = sys.argv[1]
text = open(doc_path).read()
lines = text.splitlines()
failures = 0

def pf(label, ok, detail=""):
    global failures
    if ok:
        print("PASS  %s" % label)
    else:
        failures += 1
        print("FAIL  %s%s" % (label, (" -- " + detail) if detail else ""))

DECL = re.compile(r'^\*\*(R|I)(\d+) \(MUST(?: NOT)?\)\*\*')
decl_r, decl_i, dup = [], [], []
for ln in lines:
    m = DECL.match(ln)
    if not m:
        continue
    rid = m.group(1) + m.group(2)
    (decl_r if m.group(1) == 'R' else decl_i).append(rid)
for seq in (decl_r, decl_i):
    seen = set()
    for rid in seq:
        if rid in seen:
            dup.append(rid)
        seen.add(rid)

pf("T1 the document declares verdict rules in the `**Rn (MUST)**` form (>= 11 expected)",
   len(set(decl_r)) >= 11, "found %d: %s" % (len(set(decl_r)), sorted(set(decl_r))))
pf("T2 the document declares checker rules in the `**In (MUST)**` form (>= 8 expected)",
   len(set(decl_i)) >= 8, "found %d: %s" % (len(set(decl_i)), sorted(set(decl_i))))
pf("T3 no rule id is declared twice", not dup, "duplicated: %s" % sorted(set(dup)))

# --- the taxonomy table, read ONLY from the section that carries it ---
tax_heads = [ln for ln in lines if ln.startswith('## ') and 'rejection taxonomy' in ln.lower()]
tax_section = []
inside = False
for ln in lines:
    if ln.startswith('## '):
        if inside:
            break
        if 'rejection taxonomy' in ln.lower():
            inside = True
    if inside:
        tax_section.append(ln)
pf("T4 exactly one '## ' section carries the rejection taxonomy (an ambiguous heading is not a scope)",
   len(tax_heads) == 1 and bool(tax_section), "%d heading(s) matched: %s" % (len(tax_heads), tax_heads))

ROW = re.compile(r'^\|\s*`(R\d+)`\s*\|(.*)\|\s*$')
rows, thin = {}, []
for ln in tax_section:
    m = ROW.match(ln)
    if not m:
        continue
    rid, rest = m.group(1), m.group(2)
    cells = [c.strip() for c in rest.split('|')]
    if rid in rows:
        thin.append(rid + " (duplicate row)")
    rows[rid] = cells
    if len([c for c in cells if c]) < 2 or any(len(c) < 12 for c in cells):
        thin.append(rid + " (empty or stub cell: %r)" % cells)

declared, tabled = set(decl_r), set(rows)
pf("T5 every declared verdict rule has a taxonomy row (a MUST with no rejection path is the defect)",
   declared <= tabled, "declared but not in the taxonomy: %s" % sorted(declared - tabled))
pf("T6 every taxonomy row names a rule the document still declares (no orphan rows)",
   tabled <= declared, "in the taxonomy but not declared: %s" % sorted(tabled - declared))
pf("T7 no taxonomy row is a stub -- each names what failed and what the rejection says",
   not thin, "; ".join(thin))

# --- every normative MUST cites a rule id, so a new MUST cannot be added outside the scheme ---
paras = re.split(r'\n\s*\n', text)
orphan = []
for p in paras:
    flat = ' '.join(p.split())
    if re.search(r'\bMUST\b', flat) and not re.search(r'\b[RI]\d+\b', flat):
        orphan.append(flat[:150])
pf("T8 every paragraph containing a normative MUST cites a rule id (no MUST outside the scheme)",
   not orphan, "%d paragraph(s) with a MUST and no rule id: %s" % (len(orphan), orphan))

# --- the taxonomy must actually cover the five cases the last two review rounds found missing ---
need = {
    "R5":  "first publish, non-reserved: the declared owner is not the submitter (round-2 B1, mode 1 of 2 missing)",
    "R8":  "first publish, reserved: the declared owner is not the reserved owner (round-2 B1, mode 2 of 2 missing)",
    "R2":  "the directory path and `id` disagree about the namespace (round-2 B2)",
    "R10": "page.json touched where no entry.json exists (round-2 B3)",
    "R9":  "membership indeterminate -- the 302 arm (round-2 B4)",
}
for rid, why in need.items():
    pf("T9.%s the taxonomy covers: %s" % (rid, why), rid in rows, "no row for %s" % rid)

sys.exit(1 if failures else 0)
PY
if [ $? -ne 0 ]; then fail "T0 the rule/taxonomy derivation check reported failures (see FAIL lines above)"; fi

# --------------------------------------------------------------------------------
section "B1 (round 2) -- the failure taxonomy is exhaustive, and no longer advertises itself as closed at three"

expect_no_hits "B1a.1 the closed-list phrasing 'one of **three** failure modes' is gone (it was the defect: a closed list beside an open set of MUSTs)" \
    'one of \*\*three\*\* failure modes'
expect_hits_in "B1a.2 the taxonomy section states the list is derived from the rule declarations, not maintained beside them" \
    'rejection taxonomy' 'derived from the rule declarations|one row per declared'
expect_hits_in "B1a.3 the how-to-read section explains the rule-id convention a new MUST must follow" \
    'How to read this document' 'every normative MUST'
expect_hits_in "B1a.4 the how-to-read section names the verify check that makes drift detectable rather than promised" \
    'How to read this document' '032-verify\.sh'

# --------------------------------------------------------------------------------
section "B2 (round 2) -- one authoritative source for the namespace, and the other must agree"

expect_hits_in "B2a.1 a section states which of the two sources is authoritative" \
    'directory path is authoritative' 'the directory path.*authoritative|authoritative.*directory path'
expect_hits_in "B2a.2 the same section states WHY the path wins (page.json carries neither id nor owner)" \
    'directory path is authoritative' 'page\.json'
expect_hits_in_para "B2a.3 the agreement requirement is a rule, not a description: entry.json's id must agree with its own directory" \
    '\*\*R2 \(MUST\)\*\*' 'agree|equal'
expect_hits_in "B2a.4 the mods/alice.cooltool + id mallory:cooltool disagreement is worked as an attack attempt" \
    'Attack attempts' 'mods/alice\.cooltool.*id.*mallory:cooltool|id..? .?mallory:cooltool'
expect_hits_in "B2a.5 the comparison model says the namespace is derived from the path only, never from id" \
    'directory path is authoritative' '\*\*I2 \(MUST\)\*\*'

# --------------------------------------------------------------------------------
section "B3 (round 2) -- page.json for a namespace with no entry.json is defined, not merely claimed complete"

expect_hits_in "B3a.1 the page.json section names the no-entry.json case explicitly" \
    'page\.json. PRs' 'no .entry\.json. exists|does not exist at the merge-base'
expect_hits_in "B3a.2 the page.json section states page.json carries neither owner nor id, so the first-publish rule cannot apply" \
    'page\.json. PRs' 'neither .?owner.? nor .?id.?|no .owner. field and no .id. field'
expect_hits_in_para "B3a.3 the no-entry.json case has a rule with a verdict, not a gap" \
    '\*\*R10 \(MUST\)\*\*' 'reject'
expect_hits_in "B3a.4 the page.json section states what happens when the SAME PR also creates the entry.json" \
    'page\.json. PRs' 'same PR|same diff'
expect_no_hits_in "B3a.5 the page.json section no longer claims completeness while leaving the case undefined" \
    'page\.json. PRs' 'This is the entirety of what this document requires'

# --------------------------------------------------------------------------------
section "B4 (round 2) -- the 302 arm is mandatory, not one of two acceptable designs"

expect_no_hits "B4a.1 the 'either is acceptable' framing of the two designs is gone" \
    'either is acceptable'
expect_hits_in "B4a.2 the reserved-namespace section states the 302 arm is mandatory" \
    'reserved-namespace case' 'mandatory'
expect_hits_in_para "B4a.3 detecting the 302 without following it is a declared checker rule" \
    '\*\*I5 \(MUST NOT\)\*\*' '302'
expect_hits_in_para "B4a.4 an indeterminate membership answer has its own verdict rule, failing closed" \
    '\*\*R9 \(MUST\)\*\*' '302'
expect_hits_in "B4a.5 running as a confirmed org member is stated as an ADDITION to the 302 arm, never an alternative to it" \
    'reserved-namespace case' 'in addition to|never instead of|not a substitute for the'
expect_hits_in "B4a.6 the redirect-following defaults are stated for each client separately, with what was tested here" \
    'reserved-namespace case' 'verified in this environment|verified here'

# --------------------------------------------------------------------------------
section "B5 (round 2) -- B2.2 rewritten to look at the exception itself (a class defect, not an instance)"

# THE ROUND-2 REPRODUCTION, AS A FIXTURE. The old B2.2 matched '324218296.*organisation' against
# EVERY flattened paragraph, so an unrelated paragraph in the reserved-namespace section kept it
# green while the number inside the exception was falsified. This check reads the ONE paragraph
# that declares the exception, and reads the required value from reserved-namespaces.json rather
# than from a literal in this script, so a falsified value in the document reddens it.
RESERVED_OWNER_ID=$(python3 -c "import json; d=json.load(open('reserved-namespaces.json')); print(d['namespaces']['mc']['owner']['id'])")
expect_hits_in_para "B2.2 the reserved first-publish exception names the required owner value ($RESERVED_OWNER_ID, read from reserved-namespaces.json) IN THE EXCEPTION ITSELF" \
    '\*\*R8 \(MUST\)\*\*' "$RESERVED_OWNER_ID"

# --------------------------------------------------------------------------------
section "V -- content checks on the identity values themselves (round-2 non-blocking 6)"
# Round-2 finding 6: the reviewer falsified BOTH central numeric identities in the document and
# the only red was S4, the scope check -- which it separately showed fires on whitespace. The
# suite caught a falsified key SET and not a falsified VALUE. These checks read the expected
# values from the real data file and from the committed fixture, never from a literal here, and
# assert them at the specific points in the document that carry the claim.

ORG_ID=$(python3 -c "import json; d=json.load(open('reserved-namespaces.json')); print(d['namespaces']['mc']['owner']['id'])")
TEST_ORG_ID=$(python3 -c "import json; d=json.load(open('reserved-namespaces.json')); print(d['namespaces']['test']['owner']['id'])")
if [ "$ORG_ID" = "$TEST_ORG_ID" ]; then
    pass "V1 reserved-namespaces.json records the same owner.id for mc and test ($ORG_ID)"
else
    fail "V1 reserved-namespaces.json records different owner.ids (mc=$ORG_ID test=$TEST_ORG_ID)"
fi
expect_hits_in "V2 the org id the document pastes from \`gh api orgs/worldofmodcraft\` equals reserved-namespaces.json's recorded owner.id" \
    'reserved-namespace case' "\"id\":$ORG_ID,\"login\":\"worldofmodcraft\""
expect_hits_in "V3 the document's 'no individual id can equal the org id' argument still contrasts the two REAL ids" \
    'reserved-namespace case' "$ORG_ID.*324089373|324089373.*$ORG_ID"
expect_hits_in "V4 the individual account id the argument uses is the one the PR#3 transcript actually returned" \
    'What identity is compared' '"id":324089373,"login":"womcraft"'

python3 - "$DOC" "$B1_FIXTURE" "$ORG_ID" <<'PY'
import json, re, sys
doc = open(sys.argv[1]).read()
fx = json.load(open(sys.argv[2]))
org_id = sys.argv[3]
failures = 0
def pf(label, ok, detail=""):
    global failures
    if not ok:
        failures += 1
        print("FAIL  %s%s" % (label, (" -- " + detail) if detail else ""))
    else:
        print("PASS  %s" % label)

# Every 5+-digit integer in the contract is an account id or a documented placeholder. An
# allow-list makes a falsified value fail even where no section-scoped check names it: the
# falsified number is simply not one of the numbers this document is allowed to contain.
found = sorted(set(re.findall(r'\b\d{5,}\b', doc)))
allowed = {
    org_id: "the worldofmodcraft organisation's numeric account id (reserved-namespaces.json)",
    "324089373": "the womcraft individual account's numeric id (live gh api transcripts)",
    "10137": "GitHub's `ghost` placeholder account, cited as indirect evidence on id reuse",
    "100200300": "fabricated placeholder id in the task-007 regression fixture, marked as such",
    "900800700": "fabricated placeholder id in the task-007 regression fixture, marked as such",
    "15062869": "the jestjs/jest repository id, in the live evidence for I5's redirect-following claims",
}
unexpected = [n for n in found if n not in allowed]
pf("V5 every 5+-digit number in the contract is a known identity or a marked placeholder",
   not unexpected, "unrecognised number(s) %s -- a falsified identity value, or a new one that must be added to this allow-list with its provenance" % unexpected)
missing = [n for n in allowed if n not in found]
pf("V6 every identity the contract's argument depends on is still present in it",
   not missing, "missing from the document: %s" % [(n, allowed[n]) for n in missing])

# The fixture's redirect target embeds the org id; it must be the same org.
pf("V7 the recorded fixture's redirect target names the same organisation id as reserved-namespaces.json",
   ("/organizations/%s/" % org_id) in fx["unauthenticated_members_endpoint"]["redirect_target"],
   "redirect_target=%r, org id from reserved-namespaces.json=%s" % (fx["unauthenticated_members_endpoint"]["redirect_target"], org_id))

# Round-2 finding 15: the fixture's own how_to_recapture instructions did not match the commands
# it records, so a reader following the file's instructions produces output that fails B1.8.
meta_cmds = fx["_meta"]["how_to_recapture"]
probe_cmds = [fx["unauthenticated_members_endpoint"]["command"],
              fx["unauthenticated_members_endpoint_redirect_followed"]["command"],
              fx["unauthenticated_memberships_endpoint"]["command"]]
mismatch = [(i, a, b) for i, (a, b) in enumerate(zip(meta_cmds, probe_cmds)) if a != b]
pf("V8 the fixture's how_to_recapture commands are byte-identical to the commands it records (round-2 finding 15)",
   not mismatch and len(meta_cmds) == len(probe_cmds),
   "mismatched at index %s" % [m[0] for m in mismatch] if mismatch else "list lengths differ: %d vs %d" % (len(meta_cmds), len(probe_cmds)))

sys.exit(1 if failures else 0)
PY
if [ $? -ne 0 ]; then fail "V0 one or more identity-value checks failed (see FAIL lines above)"; fi

# --------------------------------------------------------------------------------
section "K -- Ludwig's two rulings of 2026-09-07 are written into the contract as rules"
# Ludwig answered the contract's own Questions 3 and 4 on 2026-09-07. Both had to become stated
# rules, not implicit behaviour and not open questions -- his reasoning, binding on how this is
# written: "no ADR states this in those words, so the contract must."

expect_hits_in "K1 the takedown section states who may OPEN a takedown PR, as a ruling with its date" \
    'Takedown PRs' '2026-09-07'
expect_hits_in_para "K2 the takedown opener is a verdict rule, so an unauthorised opener has a rejection path" \
    '\*\*R11 \(MUST\)\*\*' 'takedown'
expect_hits_in "K3 the takedown section keeps MANAGER.md Section 7's written-approval gate on the MERGE, unsoftened" \
    'Takedown PRs' 'written approval'
expect_hits_in_para "K4 passing this gate is stated NOT to be merge authorisation" \
    '\*\*I8 \(MUST\)\*\*' 'merge'
expect_hits_in "K5 the takedown carve-out is confined to the takedown mutation itself, not to the whole PR" \
    'Takedown PRs' 'nothing but|only that mutation|no other change'
expect_hits_in "K6 case-insensitive namespace comparison is stated in the contract, with the live evidence at the point of the claim" \
    'namespace string itself' 'case-insensitive|case-insensitively'
expect_hits_in "K7 the case-folding claim carries its verification inline (three casings, one account id)" \
    'namespace string itself' 'WOMCRAFT|WomCraft'
expect_no_hits_in "K8 Questions 3 and 4 are no longer booked as open questions for Ludwig" \
    '^## Questions$' 'Booked to Ludwig as an FYI|An authority question sitting with Ludwig'
expect_hits_in "K9 both answers are recorded with Ludwig and the date, so no round re-asks them" \
    'answered by Ludwig' '2026-09-07'

# --------------------------------------------------------------------------------
section "B1 (round 1) -- the document states the caller-dependent rule, the redirect hazard, and the Actions-token caveat"
# All six of these were whole-document searches in round 2 (finding B5's class); each is now
# bound to the section that must carry the claim.

expect_hits_in "B1.10 the document states three GitHub-documented outcomes including 302 for a non-member requester" \
    'reserved-namespace case' 'requester is not an organization member'
expect_hits_in "B1.11 the document states a checker must NOT follow the redirect and treat the result as the answer" \
    'reserved-namespace case' 'MUST NOT follow the .302.'
expect_hits_in "B1.12a the redirect-following default is stated for curl, and matches what was run here" \
    'reserved-namespace case' 'curl'
expect_hits_in "B1.12b the redirect-following default is stated for Python's requests" \
    'reserved-namespace case' 'requests'
expect_hits_in "B1.12c the redirect-following default is stated for gh api" \
    'reserved-namespace case' 'gh api'
expect_hits_in "B1.12d octokit's redirect default is marked unverified here rather than asserted" \
    'reserved-namespace case' 'octokit[^.]*(not established|not verified|unverified)|(not established|not verified|unverified)[^.]*octokit'
expect_hits_in "B1.13 the document marks the GITHUB_TOKEN/Actions-caller case as unverified, at the point the claim is made" \
    'reserved-namespace case' 'no GitHub Actions runner'
expect_hits_in "B1.14 the document names the memberships endpoint as a candidate, not an answer" \
    'reserved-namespace case' 'candidate, not an answer'
expect_no_hits "B1.15 the old, caller-unqualified flat claim ('returns .204. if the named user is a member, .404. otherwise') is gone (whole-document scope is correct here: an absence claim)" \
    'returns .204. if the named user is a member, .404. otherwise'

# --------------------------------------------------------------------------------
section "B2 (round 1) -- the reserved-namespace first-publish exception is stated where the first-publish rule is made"

expect_hits_in "B2.1 the first-publish section states an explicit exception for reserved namespaces" \
    'What a first publish binds' 'Exception for a namespace on the reserved list'
expect_hits_in "B2.3 the reserved-namespace section states it governs first publish, not only present->present" \
    'reserved-namespace case' 'governs a reserved namespace.s first publish exactly as it governs every later'

if [ "$ORG_ID" = "324218296" ] && [ "$TEST_ORG_ID" = "324218296" ]; then
    pass "B2.4 reserved-namespaces.json's real mc/test owner.id both equal 324218296, matching what the document cites"
else
    fail "B2.5 reserved-namespaces.json's real owner.id (mc=$ORG_ID test=$TEST_ORG_ID) does not match 324218296"
fi

# --------------------------------------------------------------------------------
section "B3 (round 1) -- the namespace-string check"

expect_hits_in "B3.1 the document states the namespace-string rule as a rule, not a description" \
    'namespace string itself' '\*\*R4 \(MUST\)\*\*'
expect_hits_in "B3.2 the document states case-folding to lowercase" \
    'namespace string itself' 'folding both sides to lowercase'
expect_hits_in "B3.3 reserved namespaces are stated exempt from the namespace-string check" \
    'namespace string itself' 'Reserved namespaces are exempt from this check'
expect_hits_in "B3.4 the namespace-string section records the residual case it does NOT close (round-2 finding 12)" \
    'namespace string itself' 'does not close|residual'
expect_hits_in "B3.5 the mallory/alice first-publish-capture attack is worked in the attack-attempts section" \
    'Attack attempts' 'mallory'
expect_hits_in "B3.6 that attack attempt names the review finding it came from" \
    'Attack attempts' 'found in review round 1 \(finding B3\)'
expect_hits_in_para "B3.7 name_at_registration at first publish is a rule with a verdict, not a description (round-2 finding 11)" \
    '\*\*R6 \(MUST\)\*\*' 'name_at_registration'

# --------------------------------------------------------------------------------
section "B4 (round 1) -- page.json enumeration"

PAGE_JSON_HITS=$(grep -c 'page\.json' "$DOC")
printf '  $ grep -c "page.json" %s -> %s\n' "$DOC" "$PAGE_JSON_HITS"
if [ "$PAGE_JSON_HITS" -gt 0 ]; then
    pass "B4.1 contracts/ownership.md mentions page.json ($PAGE_JSON_HITS hits; the review's own falsifying command returned 0 before round 1)"
else
    fail "B4.2 contracts/ownership.md still has zero page.json hits"
fi
expect_hits_in "B4.3 the enumeration section explicitly includes page.json paths" \
    'Against what' 'page\.json'
expect_hits_in "B4.4 ADR-0059 Section 3's exact wording is quoted (same ownership check, numeric id)" \
    'page\.json. PRs' 'same ownership check \(numeric id\)'
expect_hits_in "B4.5 the asset-scan requirement is named and deferred to task 040" \
    'page\.json. PRs' 'deferred to task \*\*040\*\*|deferred to task 040'
if [ -s "$TASKLOG_HEADER" ] && [ "$(wc -c < "$TASKLOG_HEADER")" -lt "$(wc -c < "$TASKLOG")" ]; then
    pass "B4.5a the task file's header (its Context list) was extracted, and is a real subset of the file"
else
    fail "B4.5a the task file's header extraction is empty or is the whole file -- the scope for B4.6/B4.7 is not a scope"
fi
expect_hits_flow "B4.6 ADR-0059 is in the task file's own Context list" \
    'Missing from this.*list originally, found in review round 1 \(finding B4\): ADR-0059' \
    "$TASKLOG_HEADER"
expect_hits_in_para "B4.7 ADR-0030 is in the task file's own Context list, not merely mentioned where the review named the miss (round-2 finding 18)" \
    'ADR-0058 \(publishing flow, ownership' 'ADR-0030' "$TASKLOG_HEADER"

# --------------------------------------------------------------------------------
section "B5 (round 1) -- the takedown question, now answered rather than declared"

TAKEDOWN_HITS=$(grep -ic 'takedown' "$DOC")
printf '  $ grep -ic "takedown" %s -> %s\n' "$DOC" "$TAKEDOWN_HITS"
if [ "$TAKEDOWN_HITS" -gt 0 ]; then
    pass "B5.1 contracts/ownership.md mentions 'takedown' ($TAKEDOWN_HITS hits; the review's own falsifying command returned 0 before round 1)"
else
    fail "B5.2 contracts/ownership.md still has zero takedown hits"
fi
expect_hits_in "B5.3 the takedown section still names both contracts the delegation falls between" \
    'Takedown PRs' 'append-only\.rules\.md'
expect_hits_in "B5.4 the takedown section states what happens to a takedown PR from any other account" \
    'Takedown PRs' 'rejected'
expect_hits_in "B5.6 the takedown section records which review finding raised it" \
    'Takedown PRs' 'finding B5'

# --------------------------------------------------------------------------------
section "N -- non-blocking items from both review rounds"

expect_hits_in "N1 reserved-list revision rule: old, never new, is stated in the reserved-namespace section" \
    'reserved-namespace case' 'the check reads: .old., never .new.'
# Round-2 rule-3 split: the round-2 check hid an alternation behind a label naming two variables,
# and its second branch mentioned neither of them. Three checks now, one claim each.
expect_hits_in "N2a GITHUB_ACTOR is named in the identity section" \
    'What identity is compared' 'GITHUB_ACTOR\b'
expect_hits_in "N2b GITHUB_ACTOR_ID is named in the identity section" \
    'What identity is compared' 'GITHUB_ACTOR_ID'
expect_hits_in "N2c the identity section forbids them as an identity source" \
    'What identity is compared' 'forbidden as an identity source'
if [ -x "docs/tasks/032-verify.sh" ]; then
    pass "N4 docs/tasks/032-verify.sh exists and is executable (this script)"
else
    fail "N4 docs/tasks/032-verify.sh is not executable"
fi
expect_hits "N5 docs/contracts/README.md's worked-examples count names eight prose documents" \
    'eight prose' "$CONTRACTS_README"
expect_hits "N5b docs/contracts/README.md's checking-logic paragraph names three tasks" \
    'in any of the three tasks' "$CONTRACTS_README"
expect_hits_in "N9 the two-namespace example names a concrete PR author instead of restating the owner (round-2 finding 9)" \
    'Against what' 'opened by|the PR author is'
expect_hits_in_para "N10 the first-publish classification paragraph says merge-base, matching append-only.rules.md, not 'target branch' (round-2 finding 10)" \
    'this is a first publish' 'merge-base'
expect_hits_in_para "N13 a PR touching ONLY reserved-namespaces.json is named as enumerating no namespace, with ADR-0119's human review as its guard (round-2 finding 13)" \
    'touching only .reserved-namespaces\.json' 'ADR-0119'
expect_hits_in "N14 the case-folding premise (usernames are unique case-insensitively) is stated with its live evidence (round-2 finding 14)" \
    'namespace string itself' '324089373'
expect_no_hits "N16 the garbled 'authenticates as is itself' sentence is repaired (round-2 finding 16)" \
    'authenticates as is itself'

# --------------------------------------------------------------------------------
section "Scope and suite -- unchanged elsewhere, existing tests still pass"

SUITE_OUT=$(python3 -m unittest discover -s tests/contracts 2>&1 | sed -E 's/in [0-9]+\.[0-9]+s/in <elapsed>s/')
SUITE_RC=$?
printf '  $ python3 -m unittest discover -s tests/contracts   (elapsed time normalised)\n'
printf '%s\n' "$SUITE_OUT" | sed 's/^/  /'
if [ "$SUITE_RC" -eq 0 ]; then
    pass "S1 tests/contracts suite passes (exit 0), untouched by this round"
else
    fail "S2 tests/contracts suite failed (exit $SUITE_RC)"
fi

# SCOPE CHECK -- merge-base-relative, and a SUBSET test (fix round 3, round-2 finding 7).
#
# Two defects in the round-2 version, both real, both demonstrated before this rewrite:
#   1. It pinned a hash (ROUND2_BASE=38600d2). A pinned base is a base that goes stale: this task
#      had already had to move the pin once (fcde6d5 -> 38600d2, because v.html's later deletion
#      showed forever in a diff against the older base). The moment this branch merges and main
#      moves on, a diff against a hash on the branch is a diff against a commit that is no longer
#      anyone's baseline, and the check goes permanently red. That is not hypothetical:
#      docs/tasks/006-verify.sh is red on registry main today for exactly this reason.
#   2. It required the changed set to EQUAL a fixed list. Equality means the check fails whenever
#      the round legitimately changes a different number of files -- and it fails after the merge,
#      when the diff is correctly empty. The guardrail this check exists to enforce (MANAGER.md
#      Section 3.3: a task does not touch files outside its declared scope; task 032's own finding
#      F-A) is a SUBSET property: nothing changed outside the declared scope. Subset is the
#      assertion; equality was an over-claim that could only rot.
#
# The base is now computed, never pinned: the merge-base of HEAD and the integration branch. On
# this branch it is the fork point, so the changed set is exactly this task's own work. After the
# merge, on main, the merge-base is HEAD itself, the changed set is empty, and the subset test is
# trivially true -- green, correctly, forever, without anyone re-pinning anything.
MERGE_BASE=""
for ref in origin/main main origin/master master; do
    if git rev-parse --verify --quiet "$ref" > /dev/null 2>&1; then
        MERGE_BASE=$(git merge-base HEAD "$ref" 2>/dev/null) && [ -n "$MERGE_BASE" ] && { SCOPE_REF="$ref"; break; }
    fi
done
if [ -z "$MERGE_BASE" ]; then
    # No skip, no silent green: an unresolvable base is a failed check (Section 2c rule 1 --
    # a check that does not evaluate is not a clean result).
    fail "S3a no integration branch (origin/main, main, origin/master, master) resolved, so the scope check has no base to compute against"
else
    CHANGED=$( { git diff --name-only "$MERGE_BASE" -- .; git ls-files --others --exclude-standard; } \
        | grep -v '__pycache__' | sort -u )
    printf '  $ git merge-base HEAD %s -> %s\n' "$SCOPE_REF" "$MERGE_BASE"
    printf '  $ { git diff --name-only %s -- . ; git ls-files --others --exclude-standard ; } | grep -v __pycache__ | sort -u\n' "$MERGE_BASE"
    printf '%s\n' "$CHANGED" | sed 's/^/  /'
    # Task 032's declared file scope, from the task file's own "What I wrote" plus the two
    # artefacts later rounds added (the verify script and its B1 fixture).
    DECLARED_SCOPE="contracts/ownership.md
docs/contracts/README.md
docs/tasks/032-ownership-contract.md
docs/tasks/032-verify.sh
docs/tasks/032-b1-fixtures.json"
    OUT_OF_SCOPE=$(printf '%s\n' "$CHANGED" | grep -v '^$' | grep -vxF "$DECLARED_SCOPE" || true)
    if [ -z "$OUT_OF_SCOPE" ]; then
        pass "S3 every path changed since the merge-base with $SCOPE_REF is inside task 032's declared file scope (subset test, survives the merge)"
    else
        fail "S4 file(s) outside task 032's declared scope changed since the merge-base with $SCOPE_REF: $(printf '%s' "$OUT_OF_SCOPE" | tr '\n' ' ')"
    fi
fi

# Lexical convention check (matches 006-verify.sh's own): this script must contain no ownership-
# gate checking logic of its own (no real (old, new) comparison against a live PR diff).
if grep -nE '^[^#]*\bold\.owner\.id\s*==|^[^#]*\bnew\.owner\.id\s*==' "docs/tasks/032-verify.sh" > /dev/null; then
    fail "S5 (lexical convention check) this script appears to implement an ownership comparison -- that is task 007's job"
else
    pass "S5 (lexical convention check, not a structural guarantee) this script contains no old.owner.id/new.owner.id equality logic (no ownership-gate implementation)"
fi

# SCOPE AUDIT (fix round 3, round-2 finding B5 treated as a class).
# Every pattern-matching check in this file was re-read and asked one question: can this pattern
# match somewhere other than the place whose claim the label makes? The counts are in the task
# log under "Fix round 3". Three unscoped forms remain, deliberately:
#   * expect_no_hits x4 -- absence claims, where whole-document scope IS the claim ("this string
#     appears nowhere in the document").
#   * expect_hits x2 (N5, N5b) -- against docs/contracts/README.md, a 30-line index with no
#     internal sections to scope to; the pattern is unique in that file.
#   * expect_hits_flow x2 (B4.6, B4.7) -- against the task log, where the claim genuinely is
#     "this appears somewhere in the file".

# --------------------------------------------------------------------------------
printf '\n== RESULT ==\n'
# Fix round 2 (finding F-B): the exit code below is a function of $FAILURES ONLY -- the
# deterministic checks above, every one of which reads committed repository content and makes
# no network call. The advisory tally is printed for a human's information and is never added
# to $FAILURES anywhere in this script; a skip or a drift in the advisory section can change
# this line's wording, never the exit code.
if [ "$((ADVISORY_OK + ADVISORY_DRIFT + ADVISORY_SKIP))" -gt 0 ]; then
    printf 'advisory (live, network/gh-auth dependent, informational only -- NEVER affects the verdict or exit code): %d matched fixture/paste, %d drifted, %d not evaluated\n' \
        "$ADVISORY_OK" "$ADVISORY_DRIFT" "$ADVISORY_SKIP"
fi
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED (deterministic verdict -- 0 network calls required to reach it)\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
