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
PREFIX_BLOB="fcde6d5:contracts/ownership.md"   # the commit fix round 1 started from
ROUND2_BASE="38600d2"   # the commit fix round 2 started from (manager's F-A/F-B verification)
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

section "B1 -- the document states the caller-dependent rule, the redirect hazard, and the Actions-token caveat"

expect_hits "B1.10 the document states three GitHub-documented outcomes including 302 for a non-member requester" \
    'requester is not an organization member'
expect_hits "B1.11 the document states a checker must NOT follow the redirect and treat the result as the answer" \
    'MUST NOT follow the .302.'
expect_hits "B1.12 the document names the redirect-following default of common clients (the hazard)" \
    'curl -L.*requests.*gh api.*octokit'
expect_hits_flow "B1.13 the document marks the GITHUB_TOKEN/Actions-caller case as unverified, at the point the claim is made" \
    'no GitHub Actions runner'
expect_hits "B1.14 the document names the memberships endpoint as a candidate, not an answer" \
    'candidate, not an answer'
expect_no_hits "B1.15 the old, caller-unqualified flat claim ('returns .204. if the named user is a member, .404. otherwise') is gone" \
    'returns .204. if the named user is a member, .404. otherwise'

# --------------------------------------------------------------------------------
section "B2 -- the reserved-namespace first-publish exception is stated where the first-publish rule is made"

expect_hits "B2.1 the first-publish section states an explicit exception for reserved namespaces" \
    'Exception for a namespace on the reserved list'
expect_hits_flow "B2.2 the exception names the required owner value (organisation id 324218296) at first publish" \
    '324218296.*organisation'
expect_hits "B2.3 the reserved-namespace section states it governs first publish, not only present->present" \
    'governs a reserved namespace.s first publish exactly as it governs every later'

# Cross-check the doc's cited org id against the real data file, not just against itself.
RESERVED_MC_ID=$(python3 -c "import json; print(json.load(open('reserved-namespaces.json'))['namespaces']['mc']['owner']['id'])")
RESERVED_TEST_ID=$(python3 -c "import json; print(json.load(open('reserved-namespaces.json'))['namespaces']['test']['owner']['id'])")
printf '  $ python3 -c "...reserved-namespaces.json mc/test owner.id..." -> mc=%s test=%s\n' "$RESERVED_MC_ID" "$RESERVED_TEST_ID"
if [ "$RESERVED_MC_ID" = "324218296" ] && [ "$RESERVED_TEST_ID" = "324218296" ]; then
    pass "B2.4 reserved-namespaces.json's real mc/test owner.id both equal 324218296, matching what the document cites"
else
    fail "B2.5 reserved-namespaces.json's real owner.id (mc=$RESERVED_MC_ID test=$RESERVED_TEST_ID) does not match 324218296"
fi

# --------------------------------------------------------------------------------
section "B3 -- the namespace-string check (finding B3)"

expect_hits "B3.1 the document states the namespace-string MUST rule" \
    'namespace string .* MUST equal the PR'
expect_hits "B3.2 the document states case-folding to lowercase" \
    'folding both sides to lowercase'
expect_hits "B3.3 reserved namespaces are stated exempt from the namespace-string check" \
    'Reserved namespaces are exempt from this check'
expect_hits "B3.4 the failure taxonomy lists three failure modes, not two" \
    'one of \*\*three\*\* failure modes'
expect_hits "B3.5 the mallory first-publish-capture attack scenario is present as a worked attack attempt" \
    'mallory'
expect_hits "B3.6 the attack attempt names this as finding B3" \
    'found in review round 1 \(finding B3\)'

# --------------------------------------------------------------------------------
section "B4 -- page.json enumeration (finding B4)"

PAGE_JSON_HITS=$(grep -c 'page\.json' "$DOC")
printf '  $ grep -c "page.json" %s -> %s\n' "$DOC" "$PAGE_JSON_HITS"
if [ "$PAGE_JSON_HITS" -gt 0 ]; then
    pass "B4.1 contracts/ownership.md now mentions page.json ($PAGE_JSON_HITS hits; the review's own falsifying command returned 0 before this round)"
else
    fail "B4.2 contracts/ownership.md still has zero page.json hits"
fi
expect_hits "B4.3 the enumeration ('Against what') explicitly includes page.json paths" \
    'and/or .mods/<namespace>\.<name>/page\.json'
expect_hits "B4.4 ADR-0059 Section 3's exact wording is quoted (same ownership check, numeric id)" \
    'same ownership check \(numeric id\)'
expect_hits "B4.5 the asset-scan requirement is named and deferred to task 040" \
    'deferred to task \*\*040\*\*|deferred to task 040'
expect_hits_flow "B4.6 ADR-0059 is added to the task file's Context list" \
    'Missing from this.*list originally, found in review round 1 \(finding B4\): ADR-0059' \
    "$TASKLOG"

# --------------------------------------------------------------------------------
section "B5 -- the takedown authority gap is declared, not silent (finding B5)"

TAKEDOWN_HITS=$(grep -ic 'takedown' "$DOC")
printf '  $ grep -ic "takedown" %s -> %s\n' "$DOC" "$TAKEDOWN_HITS"
if [ "$TAKEDOWN_HITS" -gt 0 ]; then
    pass "B5.1 contracts/ownership.md now mentions 'takedown' ($TAKEDOWN_HITS hits; the review's own falsifying command returned 0 before this round)"
else
    fail "B5.2 contracts/ownership.md still has zero takedown hits"
fi
expect_hits "B5.3 the document names both contracts the delegation falls between" \
    'contracts the delegation falls between, named explicitly'
expect_hits "B5.4 the document states the consequence today: rejected by the ordinary rule" \
    'is rejected by the \*\*ordinary\*\* rule in this document'
expect_hits_flow "B5.5 the document does not invent an authorisation rule -- states it declines to" \
    'does not.*invent an answer to a question that belongs to Ludwig'
expect_hits "B5.6 the gap is booked as a Question in the document itself, not only the task log" \
    'found in review round 1, finding B5'

# --------------------------------------------------------------------------------
section "Non-blocking items -- all five"

expect_hits "N1 reserved-namespaces.json revision rule: old, never new, is stated" \
    'the check reads: .old., never .new.'
expect_hits "N2 GITHUB_ACTOR / GITHUB_ACTOR_ID are named as a forbidden identity source" \
    'GITHUB_ACTOR_ID.*forbidden as an identity source|equally forbidden as an identity source'
# N3 (case-folding) is covered by B3.2 above -- same fix, not a separate check.
if [ -x "docs/tasks/032-verify.sh" ]; then
    pass "N4 docs/tasks/032-verify.sh exists and is executable (this script)"
else
    fail "N4 docs/tasks/032-verify.sh is not executable"
fi
expect_hits "N5 docs/contracts/README.md's worked-examples count names eight prose documents" \
    'eight prose' "$CONTRACTS_README"
expect_hits "N5b docs/contracts/README.md's checking-logic paragraph is corrected to name three tasks" \
    'in any of the three tasks' "$CONTRACTS_README"

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

# Baseline note (fix round 2): this used to compare against fcde6d5 (fix round 1's start
# commit). That baseline broke on its own terms after round 1: v.html was committed (out of
# scope) and later removed by the manager (commit 90a3940) -- both AFTER fcde6d5 -- so a diff
# against fcde6d5 shows v.html's deletion as a permanent, unavoidable "changed file" forever,
# even though v.html exists nowhere in the working tree or in HEAD. Found by actually running
# this check (guardrail 6c), not assumed: `git show fcde6d5:v.html` succeeds (292 lines) and
# `git diff --stat fcde6d5 -- v.html` shows "292 deletions" against a clean, current working
# tree. The fix: pin the scope check to THIS round's own start commit (the manager's F-A/F-B
# verification, 38600d2 -- v.html was already gone by then) rather than the whole task's.
CHANGED=$( { git diff --name-only "$ROUND2_BASE" -- .; git ls-files --others --exclude-standard; } \
    | grep -v '__pycache__' | sort -u )
printf '  $ { git diff --name-only %s -- . ; git ls-files --others --exclude-standard ; } | grep -v __pycache__ | sort -u\n' "$ROUND2_BASE"
printf '%s\n' "$CHANGED" | sed 's/^/  /'
EXPECTED=$(printf 'docs/tasks/032-b1-fixtures.json\ndocs/tasks/032-ownership-contract.md\ndocs/tasks/032-verify.sh\n')
if [ "$CHANGED" = "$EXPECTED" ]; then
    pass "S3 exactly the three files this round declared (the new B1 fixture, the task log, and this script) changed since $ROUND2_BASE"
else
    fail "S4 changed-file set does not match the declared scope for this round (expected: $(printf '%s' "$EXPECTED" | tr '\n' ' '))"
fi

# Lexical convention check (matches 006-verify.sh's own): this script must contain no ownership-
# gate checking logic of its own (no real (old, new) comparison against a live PR diff).
if grep -nE '^[^#]*\bold\.owner\.id\s*==|^[^#]*\bnew\.owner\.id\s*==' "docs/tasks/032-verify.sh" > /dev/null; then
    fail "S5 (lexical convention check) this script appears to implement an ownership comparison -- that is task 007's job"
else
    pass "S5 (lexical convention check, not a structural guarantee) this script contains no old.owner.id/new.owner.id equality logic (no ownership-gate implementation)"
fi

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
