#!/usr/bin/env bash
#
# 032-verify.sh -- the runnable verification artefact for task 032, fix round 1.
#
# MANAGER.md Section 2c: "Any task whose acceptance criteria are command-based ships
# docs/tasks/NNN-verify.sh, committed and executable." Round 1's own finding B6 is the
# reason this script exists: a fabricated `--jq` output was pasted into contracts/ownership.md
# and into this task's own log, and nothing but hand-running six commands caught it. This
# script makes that kind of fabrication detectable by construction.
#
# Usage:  ./docs/tasks/032-verify.sh          (run from the worktree root, no arguments)
# Exit:   0 if every check passed, non-zero otherwise (the failure count).
#
# BOUNDARY -- read before adding anything here.
# This script verifies task 032's fix-round-1 acceptance criteria. It implements NO ownership
# check: it never reads a real PR diff, never decides whether a submitter is authorised to touch
# a namespace, and never enforces anything. That is task 007's job and is forbidden here. What
# this script does is exactly three kinds of thing:
#   (1) assert textual facts about contracts/ownership.md and the two other prose files this
#       round touched (docs/tasks/032-ownership-contract.md, docs/contracts/README.md) -- these
#       are prose contracts; nothing executes them, so "the document says X" is the only kind of
#       proof available for their content;
#   (2) run the real, live commands this document's own transcripts claim to have run (gh api,
#       curl, a throwaway git commit) and diff their output against what is pasted in the
#       document -- NETWORK REQUIRED for this section; see "Network" below;
#   (3) run a structural check, in Python, against the pre-fix blob of contracts/ownership.md
#       (pinned at commit fcde6d5, the commit this fix round started from) and against the
#       current working tree, to prove finding B6's fabrication would have been caught by a
#       check that existed before the fix (MANAGER.md Section 2c rule 5).
#
# NETWORK. Sections "B1" and "B6-live" make real, unauthenticated HTTPS requests to
# api.github.com (curl) and authenticated ones via the `gh` CLI (using whatever identity is
# already active in this environment -- this script never authenticates as anything, per
# CLAUDE.md rule 11). If the network or `gh` auth is unavailable, those specific checks report
# NETWORK-SKIP (not PASS, not silently absent) and are counted separately from FAILURES, so a
# disconnected run cannot be mistaken for a clean one.
#
# DETERMINISM. Text-based checks (contracts/ownership.md, the two other prose files) are fully
# deterministic: same repository content, same result, on any machine, no network. Live-API
# checks are pinned to the extent GitHub's API allows (fixed org, fixed repo, fixed PR number,
# fixed known account) but their *availability* depends on network reachability and the active
# `gh` identity's real, current membership state -- both are properties of the environment this
# script runs in, not of this repository, and are reported as such rather than silently retried.

set -u
set -o pipefail

DOC="contracts/ownership.md"
TASKLOG="docs/tasks/032-ownership-contract.md"
CONTRACTS_README="docs/contracts/README.md"
PREFIX_BLOB="fcde6d5:contracts/ownership.md"   # the commit this fix round started from
ROUND_BASE="fcde6d5"
FAILURES=0
NETSKIPS=0

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
netskip() { printf 'SKIP  %s -- network/gh-auth unavailable, not counted as pass or fail\n' "$1"; NETSKIPS=$((NETSKIPS + 1)); }

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
section "B6 -- live re-run of every command pasted in the document, diffed against the paste"

if ! gh auth status > /dev/null 2>&1; then
    netskip "B6.5 gh auth status -- no active gh identity, live gh api checks skipped"
else
    LIVE_PR3=$(gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}' 2>/dev/null)
    DOC_PR3=$(grep -A1 "pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'" "$DOC" | tail -1)
    printf '  $ gh api repos/worldofmodcraft/registry/pulls/3 --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_PR3" "$DOC_PR3"
    if [ "$LIVE_PR3" = "$DOC_PR3" ]; then
        pass "B6.6 live PR#3 shape matches the document's paste exactly"
    else
        fail "B6.7 live PR#3 shape ($LIVE_PR3) does not match the document's paste ($DOC_PR3)"
    fi

    LIVE_ORG=$(gh api orgs/worldofmodcraft --jq '{login,id,type}' 2>/dev/null)
    DOC_ORG=$(grep -A1 "gh api orgs/worldofmodcraft --jq '{login,id,type}'" "$DOC" | tail -1)
    printf '  $ gh api orgs/worldofmodcraft --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_ORG" "$DOC_ORG"
    if [ "$LIVE_ORG" = "$DOC_ORG" ]; then
        pass "B6.8 live org id/login/type matches the document's paste exactly"
    else
        fail "B6.9 live org id/login/type ($LIVE_ORG) does not match the document's paste ($DOC_ORG)"
    fi

    LIVE_REPO=$(gh api repos/worldofmodcraft/registry --jq '{full_name,owner:{login:.owner.login,id:.owner.id,type:.owner.type}}' 2>/dev/null)
    DOC_REPO=$(grep -A1 "gh api repos/worldofmodcraft/registry --jq '{full_name,owner:" "$DOC" | tail -1)
    printf '  $ gh api repos/worldofmodcraft/registry --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_REPO" "$DOC_REPO"
    if [ "$LIVE_REPO" = "$DOC_REPO" ]; then
        pass "B6.10 live repo-owner shape matches the document's paste exactly (including nested key order)"
    else
        fail "B6.11 live repo-owner shape ($LIVE_REPO) does not match the document's paste ($DOC_REPO)"
    fi

    LIVE_MEMBER_STATUS=$(gh api orgs/worldofmodcraft/members/womcraft -i 2>/dev/null | head -1 | tr -d '\r')
    if [ "$LIVE_MEMBER_STATUS" = "HTTP/2.0 204 No Content" ]; then
        pass "B6.12 live member-caller membership check for womcraft returns 204 (matches the document)"
    else
        fail "B6.13 live member-caller membership check returned '$LIVE_MEMBER_STATUS', expected 'HTTP/2.0 204 No Content'"
    fi

    LIVE_GHOST=$(gh api users/ghost --jq '{login,id,type}' 2>/dev/null)
    DOC_GHOST=$(grep -A1 "gh api users/ghost --jq '{login,id,type}'" "$DOC" | tail -1)
    printf '  $ gh api users/ghost --jq ...\n  live: %s\n  doc:  %s\n' "$LIVE_GHOST" "$DOC_GHOST"
    if [ "$LIVE_GHOST" = "$DOC_GHOST" ]; then
        pass "B6.14 live ghost-account shape matches the document's paste exactly"
    else
        fail "B6.15 live ghost-account shape ($LIVE_GHOST) does not match the document's paste ($DOC_GHOST)"
    fi
fi

# --------------------------------------------------------------------------------
section "B1 -- the org-membership endpoint: live, unauthenticated (no credential used)"

RATE_REMAINING=$(curl -s -m 10 https://api.github.com/rate_limit 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('resources',{}).get('core',{}).get('remaining','?'))" 2>/dev/null || echo "?")
if ! curl -s -m 10 -o /dev/null https://api.github.com 2>/dev/null; then
    netskip "B1.1 curl reachability to api.github.com"
elif [ "$RATE_REMAINING" = "0" ]; then
    # GitHub's unauthenticated rate limit is 60 requests/hour per source IP. This script's own
    # mutation-testing round (README, this file's own log) made enough unauthenticated requests
    # in one run to exhaust it -- a real, demonstrated hazard, not a hypothetical one. A 403 here
    # means "this machine asked GitHub too many times recently," not "the document is wrong," so
    # it is reported as a skip, not a failure, with the exact remaining-quota reading shown.
    printf '  $ curl https://api.github.com/rate_limit -> core.remaining=%s\n' "$RATE_REMAINING"
    netskip "B1.2..B1.9 unauthenticated GitHub API rate limit exhausted (core.remaining=0) -- re-run after the reset time GitHub reports, or from a different source IP"
else
    printf '  $ curl https://api.github.com/rate_limit -> core.remaining=%s\n' "$RATE_REMAINING"
    UNAUTH_STATUS=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    UNAUTH_REDIRECT=$(curl -s -m 10 -o /dev/null -w '%{redirect_url}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    printf '  $ curl (unauthenticated) -> status=%s redirect=%s\n' "$UNAUTH_STATUS" "$UNAUTH_REDIRECT"
    if [ "$UNAUTH_STATUS" = "302" ]; then
        pass "B1.2 unauthenticated caller to /orgs/{org}/members/{username} gets 302, not a direct 204/404"
    else
        fail "B1.3 unauthenticated caller got status=$UNAUTH_STATUS, expected 302"
    fi
    case "$UNAUTH_REDIRECT" in
        *public_members*) pass "B1.4 the redirect target is the public_members endpoint" ;;
        *) fail "B1.5 the redirect target ('$UNAUTH_REDIRECT') is not the expected public_members endpoint" ;;
    esac

    FOLLOWED_STATUS=$(curl -s -m 10 -L -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/members/womcraft)
    printf '  $ curl -L (following the redirect) -> final_status=%s\n' "$FOLLOWED_STATUS"
    if [ "$FOLLOWED_STATUS" = "404" ]; then
        pass "B1.6 following the redirect (default client behaviour) lands on 404 for a real, private member -- the redirect-following hazard, reproduced live"
    else
        fail "B1.7 following the redirect gave $FOLLOWED_STATUS, expected 404"
    fi

    MEMBERSHIPS_UNAUTH=$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://api.github.com/orgs/worldofmodcraft/memberships/womcraft)
    printf '  $ curl (unauthenticated) /memberships/{username} -> status=%s\n' "$MEMBERSHIPS_UNAUTH"
    if [ "$MEMBERSHIPS_UNAUTH" = "401" ]; then
        pass "B1.8 the memberships candidate endpoint refuses an unauthenticated caller outright (401), no public-view degrade"
    else
        fail "B1.9 memberships candidate endpoint (unauthenticated) returned $MEMBERSHIPS_UNAUTH, expected 401"
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

CHANGED=$( { git diff --name-only "$ROUND_BASE" -- .; git ls-files --others --exclude-standard; } \
    | grep -v '__pycache__' | sort -u )
printf '  $ { git diff --name-only %s -- . ; git ls-files --others --exclude-standard ; } | grep -v __pycache__ | sort -u\n' "$ROUND_BASE"
printf '%s\n' "$CHANGED" | sed 's/^/  /'
EXPECTED=$(printf 'contracts/ownership.md\ndocs/contracts/README.md\ndocs/tasks/032-ownership-contract.md\ndocs/tasks/032-verify.sh\n')
if [ "$CHANGED" = "$EXPECTED" ]; then
    pass "S3 exactly the four declared in-scope files changed since $ROUND_BASE"
else
    fail "S4 changed-file set does not match the declared scope for this round"
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
if [ "$NETSKIPS" -gt 0 ]; then
    printf '%d check(s) skipped for network/gh-auth unavailability (not counted as pass or fail)\n' "$NETSKIPS"
fi
if [ "$FAILURES" -eq 0 ]; then
    printf 'ALL CHECKS PASSED\n'
    exit 0
fi
printf '%d CHECK(S) FAILED\n' "$FAILURES"
exit "$FAILURES"
