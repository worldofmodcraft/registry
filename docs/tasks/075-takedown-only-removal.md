# Task 075: any PR that removes a published version is a takedown — owners cannot remove (R11 amendment + 007b checker)

- **Mission:** SITE-V1 (registry integrity) — **Status:** spec-approved (manager, 2026-10-18, after independent spec
  review round 2 PASS — security-touching, MANAGER.md §2b)
- **Repo:** registry. **Agent / model:** implementer (ROUTING.md). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/075-takedown-only-removal` / `~/wt/registry-task-075`, cut from registry `origin/main`
  **after task 064 merges** (064 touches `tools/registry/schema.py`; this task must start from main containing it)
- **Graph:** registry CI ownership check (007b node); edge: `contracts/ownership.md` ↔ `tools/registry/ownership.py`.
- **Merge:** Ludwig's written approval required (contract + CI security check + takedown semantics, §7).

## Source of the decision
Ludwig, 2026-10-17 (mission log, "Ludwig's answers, 2026-10-17", item 1, and "Removal policy — brainstorm and Ludwig's
decision", item 0): owners cannot remove a published version. ADR-0041:15 already says so; `contracts/ownership.md` R11
(lines ~1022-1024 at registry `825da5e`, starting "a PR that sets") contradicts it: "a PR that sets `status` to `"removed"` with its reason *and*
makes any other change ... is not a takedown for this rule's purposes and is judged in full by the ordinary rules" — so
an owner bundling a removal with, e.g., a new version of their own entry passes R3 as the owner (007b review F2).

## Objective
After this task, **every** PR whose diff contains at least one takedown mutation (a version's `status` becoming
`"removed"` with its reason, as `contracts/append-only.rules.md` defines it) is rejected unless R11 authorises it — the
platform's own identity **and** a diff of nothing but takedown mutations. A mixed PR (a takedown mutation plus anything
else) is rejected **whoever** its author is, with a finding that names R11 and says to split the PR. The non-takedown
part of a PR is still judged by the ordinary rules as now; only the presence of a removal changes the verdict.

## Approach (the manager's reading; the implementer flags any disagreement as a Question before building)
1. **Contract:** amend `contracts/ownership.md` R11's "nothing but" sentence (and the Attempt 8 discussion, ~line 879-890,
   wherever it states the mixed-PR consequence) so a mixed PR is **rejected by R11**, not judged by the ordinary rules.
   Also amend **every** sentence in R3 (~121-124), R7 (~626), R11 ("Every other author is rejected by R3 or R7"; "for
   every other PR R11 grants nothing and R3/R7 apply in full"), Attempt 8 ("judged in full by R3/R7") and Attempt 9
   ("every takedown PR is rejected by R3/R7" when R11 is unconfigured) that says a mixed or unauthorised takedown PR is
   rejected only by R3/R7, so it also states that R11 rejects it. In R3's and R7's paragraphs every takedown sentence must
   still name R11 (`032-verify.sh` T16). The enforcement-table row for R11 (~line 687) is extended **additively**: its
   rejection condition becomes "wrong identity, or a takedown mutation in a PR that is not nothing but takedown
   mutations", keeping every phrase `032-verify.sh` T17 requires. Record the amendment's source (Ludwig 2026-10-17,
   ADR-0041:15) in R11's text. These are the only contract edits: no rule other than R11's verdict changes meaning; the
   R3/R7/Attempt edits only make them consistent with it.
2. **Checker:** in `tools/registry/ownership.py` (around `_takedown_shape`, ~line 95, and the R11 verdict, ~line 237),
   detect "contains a takedown mutation" separately from "is nothing but takedown mutations" (`shape`), and emit an
   R11 rejection for a mixed PR regardless of author (including the platform identity). **Definition:** a PR contains a
   takedown mutation iff any `entry.json` path with both old and new present has an element classified T2 by
   `append_only.check_entry`, or a raw published→removed `status` change, evaluated per element and independent of
   findings elsewhere in that file or PR. If `check_entry` raises (`ToolError`) on such a path, the PR is rejected with an
   R11 finding naming the path (fail closed, ADR-0121). Mixed = contains a takedown mutation and not `shape`.
3. **Tests:** in `tests/registry/test_ownership.py` (and `test_ownership_mutations.py` if the mutation harness covers
   R11): owner + removal + new version → rejected (R11); platform identity + removal + other change → rejected (R11);
   platform identity + only removals → authorised (unchanged); owner + only removals → rejected (unchanged); owner + new
   version without removal → accepted (unchanged). Plus: two entries in one PR, one with a removal and the other with
   an unrelated edit → rejected (R11); a `page.json` change plus a removal → rejected (R11); a T2 element plus a malformed
   second element in the same file → rejected, with an R11 finding; a removal in a reserved namespace bundled with
   another change → rejected (R11). The existing `test_r11_reject_a_takedown_plus_any_other_change` stays unchanged in
   its inputs and must now see an R11 finding.

## Acceptance criteria — `docs/tasks/075-verify.sh`, whose output the log pastes
1. **Red first:** a commit containing only the new tests, on which the mixed-PR tests fail (owner case passes the old
   checker); the fix commit after it. Shown by the script checking out both commits in temporary clones.
2. **Fixed at HEAD:** all cases listed in Approach 3 hold; the full `tests/registry` suite is green.
3. **Mutation red:** a new `mut(...)` entry in `tests/registry/test_ownership_mutations.py` removes the checker's
   mixed-PR branch and is added to the mutation list (~line 302); it turns the new tests red.
4. **Contract text:** `contracts/ownership.md` no longer contains "judged in full by the ordinary rules" in R11's
   mixed-PR sentence; R11's paragraph names ADR-0041 and Ludwig 2026-10-17 as the source; a grep shows each passage
   listed in Approach 1 (R3, R7, R11, Attempt 8, Attempt 9) states that R11 rejects a mixed or unauthorised takedown.
   `032-verify.sh` T16 and T17 stay green.
5. **Closed scripts:** before building, run `032-verify.sh` and `062-verify.sh` on the base and record the exit codes.
   At the end, every `docs/tasks/*-verify.sh` on HEAD exits 0 (quiet machine, one at a time). If a closed
   script still reddens despite the additive edits, name the exact check id and the text it pins in the log and stop
   — do not edit closed scripts in this task; the manager then specs a re-pin task (the 071 pattern) with Ludwig's
   approval.
6. **Own-change pinning:** 075-verify.sh's own-change checks (file scope, red-commit ancestry) use explicit SHAs
   recorded at the end of the task, never HEAD or origin/main (approved REVIEW-CHECKLIST item, Ludwig 2026-10-17).

## File scope
`contracts/ownership.md`, `tools/registry/ownership.py`, `tests/registry/test_ownership.py`,
`tests/registry/test_ownership_mutations.py`, `docs/tasks/075-takedown-only-removal.md` (copy + log),
`docs/tasks/075-verify.sh` (new). Anything else = stop and report.

## Size
Source files: 2 (`ownership.py`, `ownership.md`), well under 300 lines. Reading list (≤ 10): this file; ADR-0041;
`contracts/ownership.md` (R3, R7, R11, Attempt 8, enforcement table); `contracts/append-only.rules.md` (permitted
in-place mutations, ~line 590-630); `tools/registry/ownership.py`; `tests/registry/test_ownership.py`;
`tests/registry/test_ownership_mutations.py`; `docs/tasks/007b-registry-checker-ownership.md` (review F2);
`docs/tasks/071-verify.sh` (pinning pattern); `docs/tasks/032-verify.sh` (T16, T17 only). OPERATIONS.md's "What
session 10 paid for" is recommended background reading only (11th entry, over the cap by one, justified: it explains
the pinning class AC6 guards against).

## Forbidden here
Changing who R11 authorises (identity, configuration); touching append-only rules or any schema; weakening or deleting
any existing test or check; editing closed verify scripts; `--force`; any credential.

## Dependencies
064 merged (base). Gates task 039 (registry CI workflow). ADR-0122 (Proposed) is not needed: this rule stands on
ADR-0041:15 alone.

---
# Task 075 log
- 2026-10-18 manager (session 11): drafted from Ludwig's 2026-10-17 decision (removal policy item 0). Line numbers
  measured on `~/wt/registry-task-064` (registry branch at 064 + main `825da5e`); the implementer re-measures on its base.
- 2026-10-18 manager: independent spec review round 1 (reviewer) FAIL, 3 blocking + 2 minor. All five folded in: full
  list of contract passages (R3, R7, R11, Attempts 8/9; 032 T16 named), a precise detection definition with fail-closed
  ToolError and four extra test cases, 032 T16/T17 named and the table row edit made additive, the line reference fixed,
  a named mutation entry. Round 2 pending.
- 2026-10-18 manager: spec review round 2 PASS; minors a ("all cases") and b (ToolError → R11 finding naming the path) folded in. spec-approved. Dispatch after 064 merges.
- 2026-10-25 implementer: executed. Base 79d5377. AC5 base runs from the worktree root: 032-verify.sh exit 0; 062-verify.sh
  exit 1 on the first run ONLY because AC0 (057-verify V1) found no tools/dev/node_modules in this fresh worktree; with
  WOM_NODE_MODULES pointing at another worktree's installed ajv (the documented 066 resolution order) 062 exits 0.
  Pins (AC6): BASE 79d5377, RED 45c5be9 (tests/registry/test_ownership.py only; 17 tests fail on the old checker, incl.
  the owner + removal + new version case), FIX 067a45d (ownership.md, ownership.py, test_ownership_mutations.py).
  Checker: `_takedown_paths` (per element: T2 per check_entry, or raw published->removed; ToolError -> path reported and
  the PR rejected by R11) and `mixed = bool(hits or unreadable) and not shape` -> one R11 finding naming the paths and
  saying to split the PR. Contract: R3, R7, R11 (3 sentences + source ADR-0041:15 / Ludwig 2026-10-17 + detection
  definition), table row (additive), Attempts 8 and 9. R11's pinned sentence "Every other author is rejected by `R3` or
  `R7`" was kept verbatim (032 B5.4 pins it) and a following clause added. Mutations: b7-r11-mixed-pr-branch-removed,
  b7-r11-mixed-ignores-checker-error, b7-r11-mixed-ignores-raw-status-change; full mutation run 59 mutations, not_red=0.
  Final exits, one at a time from the worktree root on HEAD: 006 0, 007a 0, 007b 0, 008a 0, 032 0, 034 0, 057 0,
  062 0, 064 0, 066 0, 067 0, 069 0, 070 0, 071 0, 075 0 (WOM_NODE_MODULES set; the machine was shared with other
  agents' verify runs during the 062-071 pass, no script reddened).
  Full `unittest discover -s tests/registry`: 272 tests OK.

## Questions
1. Existing test `test_r11_reject_malformed_t2_is_not_a_takedown` asserted `rules(v) == ["R3"]` for the platform
   identity's PR with a removal lacking its `reason`. Task Approach 2 defines a raw published->removed change as a
   takedown mutation, so R11 now also rejects it and the assertion became `["R11", "R3"]` (same inputs, strictly more
   specific; no assertion removed). Flagged because it edits an existing assertion; Ludwig/manager to confirm at review.
2. A malformed merge-base entry (check_entry raises ToolError) now yields an R11 finding even when the PR contains no
   removal, per the fail-closed clause of Approach 2. Confirm that is intended.
