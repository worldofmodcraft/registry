# Rebuild trigger: `repository_dispatch` from registry to site

Contract for edge **E12** (`N2 -> N7`, registry-data to site-build) in
`docs/architecture/depgraph.md`. The graph has already settled the *mechanism* — the edge's own
one-line definition names `repository_dispatch` specifically, closing the "repository-dispatch or
scheduled pull" choice mission §4 D3 left open — so this document does not re-open that choice; it
names the exact event type, the payload shape, and what the site build does when either is missing
or wrong.

## Scope: one edge, one direction

This document governs the signal that tells `worldofmodcraft/site`'s build workflow "the registry
changed, rebuild" after a merge to `worldofmodcraft/registry`'s default branch. It does not govern
what the site build does once triggered (reading `entry.json`/`page.json` — `contracts/
entry.schema.json`, `contracts/page.schema.json`), what the build produces (`contracts/
site-output.md`, E13), or the unrelated `repository_dispatch`-shaped trigger for edge **E15**
(`contracts/pipeline-trigger.md`) — E15 is the registry's own build pipeline reacting to a merge
that adds a version, a same-repository `push` trigger per its own decided contract (Q4=A), not a
cross-repository dispatch at all, and must not be confused with this one just because both involve
"a merge triggers something."

## Who sends this, and when

The sender is a workflow in `worldofmodcraft/registry`, running on every push to that repository's
default branch (i.e. every merged PR — schema-changing, version-adding, or `page.json`-only
alike, per mission §4 D1's "`page.json`-only PRs skip the build pipeline and merge on green
checks" — skipping the *build pipeline* is not the same as skipping the *site rebuild*: a
page-content-only merge still changed data the site renders and must still trigger this edge).
This document does not name the credential mechanism a cross-repository `repository_dispatch` call
needs (a token with write access to `worldofmodcraft/site`) — that is a build-pipeline setup
detail, task 007/008's to implement, constrained only by ADR-0041's general secret-handling rule
that no such credential appears in a repository or a log.

## Event type: exactly `registry-updated`

The `event_type` field of the `repository_dispatch` API call (`POST
/repos/worldofmodcraft/site/dispatches`) is the literal, case-sensitive string
**`registry-updated`**. This is a plain string comparison on both ends: the sender must send this
exact string and nothing else (`Registry-Updated`, `registry_updated`, `registry-update` are all
different strings and do not trigger anything), and the site repository's workflow file's own
`on.repository_dispatch.types` list must name this exact string for GitHub to route the event to
it at all.

**GitHub Actions filters `repository_dispatch` events by `event_type` before a workflow ever
runs — a mismatched `event_type` is not an error anywhere, and produces no workflow run, no log
entry, and no visible failure.** This is the central fact this document exists to make visible: an
`event_type` typo does not fail loudly; it makes the entire rebuild trigger silently inert. See
"Attack attempt" below.

## Payload shape

```json
{
  "event_type": "registry-updated",
  "client_payload": {
    "commit": "1111111111111111111111111111111111111111",
    "triggered_at": "2026-09-04T00:00:00Z"
  }
}
```

(The commit hash above is placeholder filler — 40 repeated `1` characters — matching the shape
`contracts/entry.schema.json`'s own `commit` pattern requires, not a real commit.)

- **`commit`** — the 40-lowercase-hex SHA-1 of the merge commit on `worldofmodcraft/registry`'s
  default branch that this dispatch is reacting to (same pattern as `entry.schema.json`'s
  `versions[].commit`, reused here for consistency, though this commit is on the registry
  repository, not an author's mod repository — the two are never the same commit). Its purpose is
  to let the site build pin exactly which registry state it is building from, rather than
  whatever the default branch happens to point at by the time the workflow actually runs a few
  seconds later — closing a race window between two merges landing close together.
- **`triggered_at`** — RFC 3339 timestamp (same format as `entry.schema.json`'s `published_at`) of
  when the registry's workflow fired this dispatch. Informational only: logging and audit, never
  used to decide what to build.

Both fields are the **entire** payload; this document defines no other field, and a sender must
not add ad-hoc fields the site build is not specified to read (a receiver ignoring unknown fields
is fine; a sender inventing new load-bearing fields without updating this document is not).

## What the site build does when the payload is malformed or absent

**A `repository_dispatch` event with the correct `event_type` but a missing `client_payload`, a
missing `commit` field, or a `commit` value that is not a well-formed 40-lowercase-hex string, is
treated as: "a rebuild was requested, but which exact commit triggered it is unknown."** The
workflow does not fail and does not skip the rebuild — it logs a clearly visible warning naming
what was expected (`client_payload.commit`, 40-hex) and what was actually received (absent, or the
malformed value, quoted verbatim in the log), and then proceeds to check out
`worldofmodcraft/registry`'s default branch at its current `HEAD` instead of a pinned commit.

This is a safe degrade, not a silent one, for a reason specific to this system: the site build has
no incremental state to corrupt — every run reads the entirety of the registry it checks out and
regenerates the entire `dist/` tree from scratch (`contracts/site-output.md`). Building from
"whatever `HEAD` is right now" instead of "the exact commit that triggered this run" can, at worst,
mean a rebuild also happens to pick up one more merge that landed in the few seconds since the
dispatch fired — which is still correct output for *a* real registry state, only not necessarily
the exact one requested. Failing the whole rebuild over a missing optional pinning field, when the
data needed to build correctly is still fully present and readable, is not required by anything
this document protects and would make the site *less* current, not more correct, exactly the
overreaction ADR-0103 warns against.

**Contrast this with a `repository_dispatch` whose `event_type` does not match `registry-updated`
at all — that case is not "malformed payload" in the sense above, because the workflow never runs
to begin with (see "Event type" above); there is nothing for this section's degrade behaviour to
apply to, because no code from this repository ever executes.**

## Attack attempt against this contract, recorded per acceptance criterion 3

**Attempt: satisfy "sends a `repository_dispatch` event" by the letter, with the wrong
`event_type`.** A sender implementation that reads this document's mechanism ("fire a
`repository_dispatch`") without reading the exact string could plausibly send `event_type:
"registry-update"` (singular "update", one letter short of "updated"), or `"registry_updated"`
(underscore instead of hyphen) — both are genuine `repository_dispatch` calls, correctly formed,
successfully accepted by GitHub's API (the API returns success for any non-empty `event_type`
string; it does not validate against the receiving repository's workflow configuration at all).
**Outcome: the call "succeeds" — GitHub returns 204, the sender's own logs show a clean dispatch —
and the site repository's rebuild workflow never runs, because its `on.repository_dispatch.types`
list does not contain the string actually sent.** No error appears anywhere: not in the sender's
workflow, not in the receiver's Actions tab (no run was ever created to fail), not in GitHub's own
dispatch API response. The registry can merge PRs indefinitely while the live site silently
stops updating, discoverable only by someone noticing the site itself is stale. **What this
document does about it:** stating the event type as one single fixed literal string, in one place,
and calling out explicitly that a mismatch is silent rather than merely "probably fine" — a
reviewer implementing either side must copy the literal string `registry-updated` from this
document rather than typing it independently in two repositories and hoping both spellings agree.

## What this document does not cover

- **How the sending workflow authenticates to `worldofmodcraft/site`** (token type, secret name,
  scope) — a build-pipeline implementation detail (task 007/008), constrained only by ADR-0041's
  general rule that no credential appears in a repository or a log.
- **E15's pipeline trigger** (registry merge → build pipeline, same-repository `push`, no
  cross-repository dispatch at all) — `contracts/pipeline-trigger.md`, a different edge with a
  different mechanism, named here only to head off confusing the two.
- **What the site build does with the registry data once checked out** — `contracts/
  entry.schema.json`, `contracts/page.schema.json`, `contracts/archive-layout.md`.
- **The rebuild workflow's own retry/backoff/concurrency behaviour** (what happens if two
  dispatches arrive while a build is already running) — an implementation concern for task 009's
  workflow, not fixed by this document.

## Questions

- (none — the two things this contract needed to fix, the event type string and the payload
  shape, are both settled above.)
