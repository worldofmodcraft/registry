# Task 007b: Registry checkers, authority half — ownership by numeric id, reserved namespaces, R11, fail-closed T1/T3

- **Mission:** SITE-V1, D1 — **Status:** spec-approved (manager, 2026-10-15, after independent spec review rounds 1–3: FAIL, FAIL,
  PASS). 007a merged (registry PR #10); dispatchable.
- **Umbrella:** `docs/tasks/007-registry-ci-checkers.md` — read it in full, including the
  "Revision 2026-10-15" section, which overrides its older text.
- **Agent / model:** implementer / sonnet
- **Budget:** medium (≤ 3 agent-sessions)
- **Branch / worktree:** `task/007b-registry-checker-ownership` / `~/wt/registry-task-007b`, cut from
  registry `origin/main` after 007a's merge
- **Graph:** node N3; edge E16. No new edges.

## Objective
An offline ownership checker `tools/registry/ownership` exists, using 007a's report module, implementing
`contracts/ownership.md` as merged (task 032, PR #4) — every MUST rule R1–R11 and every invariant I1–I8 that
constrains a checker — plus the **fail-closed rule** of ADR-0121 / `append-only.rules.md` ("Coexistence of
T1, T2 and T3"): every PR that changes a `pending` version, or gives an existing version the status
`published` or `rejected`, is rejected whoever the author is, until the pipeline carve-out (task 008b)
amends `ownership.md`.

## Context to load (exhaustive)
- Umbrella 007 (all, revision first); ADR-0058 §2–4, ADR-0119, ADR-0121, ADR-0041 (takedown grounds).
- Registry `origin/main`: `contracts/ownership.md` (all), `contracts/append-only.rules.md` ("Coexistence of T1,
  T2 and T3", "Attack attempts", rule 3), `reserved-namespaces.json`, `docs/tasks/032-b1-fixtures.json` (HTTP
  evidence only), 007a's `tools/registry/` and `tests/registry/` as merged.
- Doctrine: MANAGER.md §2c, §3.3, §3.7, guardrail 6c; REVIEW-CHECKLIST.md; OPERATIONS.md.

## Inputs, stated exactly (all injected; the module reads no network, environment or credential)
- `author`: the PR author's `(provider, id)` pair, as task 039 will read it from `pulls.user.id` (I1). A
  login may be passed for messages only and is never compared (I6, umbrella criterion 4).
- `old` / `new` file contents per touched path, and the **merge-base** revision of
  `reserved-namespaces.json` (I4). A PR that edits `reserved-namespaces.json` does not change the list its
  own check reads (tested).
- `membership_oracle(org, author) -> int`: returns the **HTTP status** of the membership question, so R9 is
  testable: `204` member, `404` not a member, anything else (`302`, `301`, `500`, an exception) → R9's
  fail-closed rejection naming the status (I5: a `302` is never followed).
- `r11_identity`: the `(provider, id)` that `ownership.md` R11 authorises for takedowns. **Default `None`,
  and `None` means R11 authorises nobody** (`ownership.md`, R11 "The mechanism, marked rather than
  assumed"): every takedown PR is then rejected by R3/R7. The concrete id is **not** established in this task
  — which `pulls.user.id` a PR opened on the organisation's behalf carries is an open question booked for
  Ludwig and for task 039's live part; it is never settled by reading a stored credential (CLAUDE.md rule 11).
  Tests use the reserved owner's recorded id `324218296` as one fixture value and an unrelated id as another.
  **Recorded deviation from `ownership.md`:** its mechanism paragraph says task 007's implementer establishes
  that id and configures R11. That cannot be done offline without reading a credential, so 007b ships the
  parameter with the fail-closed default and the configuration moves to Ludwig's answer and task 039; the
  contract's own fallback ("until it is configured, R11 authorises nobody") is what holds meanwhile. The value
  is configuration, not data from the PR: it is never read from `reserved-namespaces.json` or any file the PR
  can change, so it may legitimately differ from the reserved owner's id (an organisation-owned App or machine
  account). A PR that edits `reserved-namespaces.json` changes neither R11 authority nor the reserved list
  (tested both ways).
- `pipeline_app_id`: an id parameter used only to prove that it confers **nothing** today. The case
  `pipeline_app_id == r11_identity` is tested: fail-closed still rejects T1/T3; T2 behaves exactly as for
  `r11_identity`.

## The fail-closed key (independent of 007a's shape verdict)
The fail-closed branch is evaluated **first**, on the raw `old`/`new` pair, not on 007a's classification —
a malformed `pending → published` that 007a calls a violation must still trip it. It fires when, at any index
`i < len(old.versions)`, either `new.versions[i]` is **missing** (truncation, rule 3) or
`new.versions[i] != old.versions[i]` and either `old.versions[i].status == "pending"` or
`new.versions[i].status` is `"published"` or `"rejected"`. Outside the key, by design: elements appended at
index ≥ `len(old.versions)` and first publishes; a born-`published` or born-`rejected` element there is
rejected by 007a's rule 2, which is why task 039 must run both checkers. The key also fires on some plain
rule-1 violations (`published → published` with a changed field, `removed → published`); there the message
says the change is not permitted at all, not only that the carve-out is missing (tested). All reasons are reported (fail-closed plus any
R-rule failures); the fail-closed reason is always present when the key fires, so its message is asserted in
every matrix cell.

## How R11's "nothing but takedown mutations" is decided
007b imports 007a's per-element classification **for this decision only**: R11 authorises a PR if, and only
if, the author equals `r11_identity` (not `None`), every changed path is an existing `mods/<ns>.<name>/entry.json`,
and every changed element of every such file is classified T2 by 007a, with `id`, `owner` and the element count
unchanged. Anything else — a new entry, a `page.json` edit, an appended version, a malformed T2 (which 007a does
not classify as T2) — means R11 does not authorise, and R3/R7 decide. Composing the shape verdict (007a) with the
authority verdict (007b) into one PR result is task 039's job; 007b states in its CLI help that its `accepted`
is never a merge signal on its own.

## Size (SPEC-CHECKLIST 5b)
Source files: 1–2 (`ownership.py`, optionally a small `ownership_cli.py`), within the cap. Changed source lines:
expected 300–450, over the 300 cap. Reason not to split: R1–R11 and I1–I8 are one contract with explicit
precedence between rules (R3/R7/R11), and the fail-closed rule must be evaluated before them; splitting would
put precedence across two branches. Reading list: 10 entries (umbrella, four ADRs, `ownership.md`, `append-only.rules.md`, `reserved-namespaces.json`,
`032-b1-fixtures.json`, 007a's modules) plus doctrine — at the cap, one over with doctrine. Every entry is a direct input of a
rule this checker implements; none can be dropped.

## Acceptance criteria — all demonstrated by `docs/tasks/007b-verify.sh`, whose output the log pastes
Umbrella criteria **1, 2, 4, 5, 6, 9, 10 (ownership messages), 11, 12 (ownership half) and 14**, plus:
- **B1. Fail-closed matrix.** PRs containing T1 only, T3 only, T1+T3, a *malformed* `pending → published`
  (missing one field), T2+T1 and T2+T3, each authored by: the namespace owner; a stranger; an org member on a
  reserved namespace (oracle `204`); an id equal to `pipeline_app_id`; an id equal to `r11_identity`. Every cell
  rejected, the fail-closed message (naming ADR-0121 and the missing task-008b carve-out) asserted per cell.
- **B2. Takedown authority (R3/R7/R11, umbrella criterion 7's authority half).** With `r11_identity` set: one T2,
  and two T2s in one PR, from `r11_identity` → accepted; the same from the owner, a stranger or an org member →
  rejected (R3/R7). With `r11_identity = None`: every takedown PR rejected. A T2 plus any non-takedown change
  from `r11_identity` → rejected (R11 "nothing else").
- **B3. Every rule both ways, proven by mutation.** For each of R1–R11 and each of I1–I8 that constrains a
  checker (expected descriptive set: **I8 only**, merge authority; claiming any other I-rule descriptive is a
  question for the manager, not a decision), at least one accepting and
  one rejecting test, **and** at least one named mutation that reddens a test of that rule. The rule ids are
  enumerated from `ownership.md`'s `**Rn (MUST` / `**In (MUST` markers at test time (11 R-rules and 8 I-rules on
  `e009ef0`; zero found fails). A tag without a reddening mutation does not count.
- **B4. Required mutations (at least):** read `owner` from `new` instead of `old` (I3); ignore `provider` (I6);
  read the reserved list from `new` (I4); compare logins instead of ids; treat `302` as member, and separately
  as not-member (R9/I5); treat an oracle exception as member; accept a `page.json`-only PR with no `entry.json`
  (R10); evaluate namespaces jointly instead of independently (I7); skip the fail-closed branch; key fail-closed
  on 007a's classification instead of the raw diff (the malformed-T1 cell must redden); let `pipeline_app_id`
  bypass fail-closed; let any author use R11; let R11 admit a non-takedown change; make R11's precedence
  shape-based rather than authority-based (`ownership.md`'s round-3 attempt); let a binding PR rebind an
  existing namespace; reject everything (positive control).
- **B5. The seam is explicit.** No network, environment or file reads beyond the paths passed in (asserted:
  patched `socket`, `os.environ` and `open` outside the given inputs raise).

- **B6. Truncation and composition cells.** A PR truncating `versions[]` trips fail-closed for every author; a
  malformed T2 from `r11_identity` is not authorised by R11; a PR from `r11_identity` editing
  `reserved-namespaces.json` alongside a T2 is not authorised. Each has a reddening mutation.
## File scope (declared)
`tools/registry/ownership*.py` (new), `tests/registry/test_ownership*.py` (new),
`docs/tasks/007b-registry-checker-ownership.md` (log), `docs/tasks/007b-verify.sh` (new),
`docs/contracts/README.md` (ownership half of umbrella criterion 12). Changing 007a's modules = stop and report.

## Forbidden here
The umbrella's list, plus: hard-coding any real GitHub App id or account id in `tools/` (fixture values in
`tests/` are fine; the reserved list is read from the merge-base `reserved-namespaces.json` passed in, and
`r11_identity` is injected configuration only); any carve-out
letting the pipeline identity carry T1/T3 (task 008b's contract amendment); establishing `r11_identity` by any
means (open question, Ludwig's); a network call or credential read of any kind (CLAUDE.md rule 11).

## Questions
- Q (booked for Ludwig, not blocking 007b): which concrete `pulls.user.id` do the platform's own takedown PRs
  carry (`ownership.md` R11 mechanism paragraph)? Until answered, `r11_identity = None` in production and every
  takedown is rejected. Options appear when 039/008b produce a real organisation-authored PR to read.

## Dependencies
After 007a (merged). Blocks 039. Task 008b later amends `ownership.md` and this checker together.

---
# Task 007b log
- 2026-10-15 manager: spec written (session 9) from the umbrella's revision.
- 2026-10-15 manager: revised after spec review round 1 (FAIL, findings 1–3, 5, 7): inputs stated, fail-closed key
  made independent of 007a, R11 identity injected with `None` = nobody, mutation set per rule, Size section.
- 2026-10-15 manager: spec review rounds 1-3 (FAIL, FAIL, PASS); spec-approved.
- 2026-10-15 manager (session 10): worktree `~/wt/registry-task-007b` cut from registry `origin/main` `ac22c8f` (007a, 062, 067 merged); dispatched to implementer. Log-entry baseline recorded below.
- 2026-10-15 manager: check-log-entry baseline = 4 (before dispatch).
- 2026-10-15 implementer: built `tools/registry/ownership.py` (check(); 007a's classify/append_only/report imported, not
  changed) and `ownership_cli.py`; tests `tests/registry/test_ownership.py` (73) and `test_ownership_mutations.py` (5
  coverage tests plus the 50-entry mutation table and runner); `docs/tasks/007b-verify.sh`; README (criterion 12).
  Design points: the fail-closed key runs first on the raw old/new pair (`_fail_closed`); R11 authority is
  `r11_identity is not None and author == r11_identity and _takedown_shape(files)` where the shape uses 007a's
  `check_entry` classification (T2 only, id/owner/count unchanged, no finding, every touched path an existing
  entry.json); R1 and unrecognised paths come from 007a's `classify.classify`; membership is asked once per reserved
  namespace through the injected oracle.
- 2026-10-15 implementer: `docs/tasks/007b-verify.sh` output on the committed tree (per-test lines elided, `grep -v '^test_'`):
```
ok    tool present: git
ok    tool present: python3
Ran 228 tests in 1.893s   OK
ok    unittest: Ran 228 tests in 1.893s, OK
ok    ownership tests ran: 78 (floor 75)
ok    umbrella 11: fresh clone of HEAD runs the whole suite OK
ok    umbrella 4   id differs / username matches rejected; rename accepted: 1 passing, 0 failing
ok    umbrella 5   first publish binds; binding is not a bypass: 8 passing, 0 failing
ok    umbrella 6   reserved namespaces by org membership, naming ADR-0119: 13 passing, 0 failing
ok    umbrella 9   positive controls accepted: 11 passing, 0 failing
ok    umbrella 10  messages name the problem and the rule: 5 passing, 0 failing
ok    umbrella 14  fail-closed T1/T3, every author, ADR-0121 named: 6 passing, 0 failing
ok    B1           fail-closed matrix (6 kinds x 5 authors = 30 cells): 1 passing, 0 failing
ok    B2           takedown authority (R3/R7/R11): 9 passing, 0 failing
ok    B3           every rule has accept+reject tests and a reddening mutation: 4 passing, 0 failing
ok    B4           the required mutations are all present: 1 passing, 0 failing
ok    B5           seam: no network / environ / open; bad inputs are errors: 3 passing, 0 failing
ok    B6           truncation and composition cells: 3 passing, 0 failing
ok    I1..I8       checker invariants: 17 passing, 0 failing
ok    R1..R10      verdict rules: 30 passing, 0 failing
ok    CLI          ownership_cli exit codes in unittest: 1 passing, 0 failing
ok    size: 2 ownership source files (cap 2: ownership.py, ownership_cli.py)
info  ownership source lines: 318
ok    no real account or App id hard-coded in tools/ownership*
ok    ownership.py imports no os/socket/subprocess/urllib/http
ok    ownership source reads no actor/credential state
ok    CLI help documents that accepted is never a merge signal (I8)
ok    CLI help documents the three exit codes
ok    CLI help documents that r11_identity None authorises nobody
ok    criterion 12: docs/contracts/README.md names the ownership checker as built and 039 as owed
ok    README no longer lists the ownership checker as still to come
ok    CLI exit codes owner/stranger/usage = 0 1 2
ok    changed files all inside the declared scope
ok    007a's modules are untouched
SUMMARY failed=0
```
- 2026-10-15 implementer: `docs/tasks/007b-verify.sh --mutate` (clone of the committed tree): baseline green, then
  `SUMMARY 50 mutations, not_red=0` / `ok every mutation turned its named tests red` / `SUMMARY failed=0`. Every B4
  mutation is in the table (owner from new, provider ignored, reserved list from new, logins not ids, 302 as member and
  as not-member, oracle exception as member, page-only accepted, joint namespaces, fail-closed skipped, fail-closed
  keyed on 007a's classification, pipeline_app_id bypass, any author uses R11, R11 admits non-takedown changes
  (appended version, owner edit, page edit), shape-based precedence, binding PR rebinds, reject-everything), plus B6's
  three and one to two per rule R1-R11 and I1-I7. One first-run NOT RED (`i7-namespaces-pooled...` named an accept test
  the mutation cannot redden) was corrected by removing that name from its `red` list, not by weakening anything.
- 2026-10-15 implementer: the verify script itself can fail: with the fail-closed call deleted from the WORKING tree,
  the default run printed `FAILED (failures=40, errors=2)`, `FAIL unittest not OK`, `FAIL umbrella 14 ... 1 passing,
  4 failing`, `FAIL B1 ... 0 passing, 1 failing`, `SUMMARY failed=4` (file then restored with `git checkout`).
- 2026-10-15 implementer: closed tasks' verify scripts on this branch. `007a-verify.sh`: rc=2, exactly two FAILs, both
  structural to its own branch and unfixable inside 007b's scope: `size: 7 source files in tools/registry (cap 5)`
  (its cap counts every file in tools/registry; ownership.py and ownership_cli.py are the 6th and 7th) and `files
  outside the declared scope` (it lists 007b's own files). Its test, parity, mutation-coverage and CLI checks are
  green. FINDING for the manager: 007a-verify.sh needs its size/scope checks re-based by a later maintenance task
  (062-style); the same trap awaits 008b and 039. `062-verify.sh` without a node_modules argument: `FAIL AC0
  prerequisite: a node_modules directory with ajv ... required` (finding: no ajv 8 on the default path). Re-run with
  the existing read-only `/tmp/fc041/node_modules` (ajv 8.20.0), nothing installed: see the next entry.
- 2026-10-15 implementer: no network, credential or environment read happened; the tests assert this (B5).

## Findings and deviations (implementer, for the manager)
- `login` IS compared, in R4/R6 only (first publish; the contract defines them on `pulls.user.login`). The spec text "a
  login ... is never compared" is honoured for R3/R7/R8 and every existing-namespace decision; mutation
  `i6-login-alone-authorises` proves a login never authorises.
- `base_entries` (new optional input): the spec's inputs give no way to know an UNCHANGED sibling `entry.json` for a
  `page.json`-only PR (R10 needs "exists at the merge-base"). The caller passes the merge-base entries; a missing key
  means "no entry" and is R10's closed rejection. The CLI fills it from `--old-root`.
- An owner or an org member submitting a pure-T2 PR is rejected by an `R11` finding (the contract's R11 taxonomy row),
  because they pass R3/R7 on their own merits; a stranger gets R11 plus R3. B2 says "rejected (R3/R7)"; the verdict is
  the same, the rule id for owner and member is R11.
- First-publish detection is per `entry.json` path (old absent), because the inputs carry no other entry of the
  namespace. A second entry in an existing namespace by a different id still has to pass R4 (login equals the
  namespace) and R5/R6.
- The CLI's `--membership-status` is one recorded status for any org; a missing value is R9 (exit 1, closed), not exit 2.
- A PR touching `reserved-namespaces.json` is always rejected (unrecognised path, via 007a's classifier), on top of
  whatever else it triggers; the reserved list it carries never reaches any decision (tested).

## Questions booked by the implementer
- Q (Ludwig, inherited from the spec, not blocking): the concrete `pulls.user.id` of the platform's takedown PRs.
  Unchanged; production keeps `r11_identity = None`.
- Q (manager, non-blocking): should first-publish rules consider the whole namespace (all its entries) instead of the
  single entry path? Assumption taken: per path (above).
- Q (manager, non-blocking): 007a-verify.sh's size and scope checks fail on every later branch (finding above).
- 2026-10-15 implementer: `062-verify.sh /tmp/fc041/node_modules` (existing read-only ajv 8.20.0): `RESULT 4 CHECK(S) FAILED`,
  all four on one script: `AC1.main.008a`, `AC1.probe.008a` (the base commit e009ef0, which contains none of this
  branch's code: expected failing ids [changed,paths], got [changed,paths,suite]), `AC3.head.008a` and `AC3.later.008a`
  (008a-verify.sh "failing: suite" inside 062's temporary clones). Run directly on this branch,
  `docs/tasks/008a-verify.sh` gives rc=0, `suite: 114 passed, 0 failed`. Because the same failure appears at the
  untouched base commit, it is not caused by 007b; it looks environmental to 062's clone harness (finding for the
  manager; not investigated further, out of scope). Every other 062 check (006, 032, 034, 057 on HEAD and on a later
  branch, AC5-AC7, self-scope) passed.

## Amendment 1 (manager, 2026-10-15, session 10) — fix round after review round 1 (FAIL)
**F1 (blocking, security): a new `entry.json` in an already-owned namespace is treated as a first publish.** Reviewer probe:
stranger id 999 with current login `alice` adds `mods/alice.new/entry.json`; merge-base namespace `alice` is owned by
another id → `accepted`. This is `ownership.md` Attack 4 (recycled username) and contradicts "namespaces are never
reassigned" (R3 is defined on the namespace existing at the merge-base). Deviation 4 (per-path first publish) is rejected.
Required:
- A new injected input, `namespace_owners`: the mapping namespace → owner `(provider, id)` read from **every**
  `mods/*/entry.json` at the PR's **merge-base** (the CLI builds it from `--old-root`; never from the PR's own files).
  A namespace is "first published" by a PR only if it is absent from `namespace_owners` **and** from the reserved list.
- A new `entry.json` (old absent) in a namespace present in `namespace_owners` is judged by R3 against that recorded
  owner's id — never by R4/R6's login comparison. (This also fixes the fail-safe side effect: a renamed owner adding a
  second mod is no longer rejected.)
- `namespace_owners` absent (None) → fail closed: every PR adding a new `entry.json` is rejected with a message naming the
  missing input. An empty mapping is a legitimate value (empty registry) and is distinct from None (tested).
- **Red first (§2c rule 5):** the reviewer's probe becomes a test — "matching login, different id, sibling entry in an
  owned namespace" — committed before the fix and shown red (accepted) on that commit; plus the renamed-owner case.
- Mutations (added to the runner, shown red): ignore `namespace_owners` (per-path first publish again); read it from the
  PR's new files; treat None as empty; judge a sibling entry by login instead of id.
- `docs/tasks/007b-verify.sh --mutate` output pasted into the log.
**F2 (non-blocking here): mixed PR with a T2 by the owner.** 007b implements `ownership.md` R11 as written ("judged in full
by the ordinary rules"). No code change in this task; the contract gap is booked for Ludwig and gates task 039.
**F3:** no change required; the `--mutate` paste in the log is the demonstration.
- 2026-10-15 manager: amendment 1 appended; fix round sent to the implementer. Log baseline recounted below.
- 2026-10-15 implementer (fix round, amendment 1, log baseline 13): F1 fixed. Red first: commit e974fe4 adds the
  reviewer's probe (stranger id 999, login `alice`, new `mods/alice.new/entry.json`) and the renamed-owner case; on that
  commit both fail (`'accepted' != 'rejected'` and `'rejected' != 'accepted'`). Fix: commit 2ddfff5 adds the injected
  `namespace_owners` input ({namespace: (provider, id)} from every merge-base entry.json; the CLI builds it from
  `--old-root` only). A new entry.json (old absent) in a non-reserved namespace present in it is judged by R3 on the
  recorded owner's (provider, id), never by R4/R6's login; None fails closed (`namespace-owners-missing`, names the
  input), `{}` is legitimate and tested distinct. Reserved namespaces keep R8+R7. Commit ad33c2f strengthens one test
  so its mutation reddens (the first `--mutate` run had one NOT RED: `f1-namespace-owners-read-from-the-prs-own-files`,
  because the test's second path hid the effect; the test, not the mutation, was weak). Deviation 4 in the earlier
  entry is superseded by this. Four new mutations: ignore namespace_owners, read it from the PR's files, None as empty,
  judge a sibling by login; all red. Other suites were checked with `ps` and were idle before the verify runs (a task-069
  agent was running 062/067/008a verify earlier; I waited).
  `docs/tasks/007b-verify.sh` (committed tree ad33c2f): `Ran 234 tests ... OK`, `ownership tests ran: 84`, every named
  criterion line ok (R1..R10: 34 passing; umbrella 4: 2; umbrella 9: 12), `info ownership source lines: 351`,
  `SUMMARY failed=0`. `docs/tasks/007b-verify.sh --mutate`:
```
ok    tool present: git
ok    tool present: python3
ok    mutation table has 54 entries (floor 45)
baseline green on committed ad33c2f38
SUMMARY 54 mutations, not_red=0
ok    every mutation turned its named tests red
SUMMARY failed=0
red      f1-namespace-owners-ignored-per-path-first-publish: 5 failing, all 2 named tests red
red      f1-namespace-owners-read-from-the-prs-own-files: 9 failing, all 2 named tests red
red      f1-none-namespace-owners-treated-as-empty: 1 failing, all 1 named tests red
red      f1-sibling-entry-judged-by-login-not-id: 5 failing, all 2 named tests red
(the other 50 per-mutation `red` lines elided here; all 54 print `red ... all N named tests red`)
```
- 2026-10-15 manager: delta review (round 2) PASS on F1. New finding N1 taken into this task as fix round 2 (amendment 2): in the "new entry in an owned namespace" branch, the new entry's `owner` must equal the recorded namespace owner `(provider, id)` (else rejected, R3/R5 message); and the CLI's `namespace_owners` builder must fail closed (ToolError / rejection naming both entries) when merge-base entries of one namespace disagree on owner, instead of `setdefault` picking the first in sorted order. Red first (both cases shown accepted/silently-picked before the fix), one mutation each. Reason: an owner field frozen to another account plus order-dependent mapping is a namespace reassignment path, which `ownership.md` forbids.
- 2026-10-15 implementer (fix round 2, amendment 2 / N1, log baseline 15): red first, commit e6ed1d7 adds both cases and
  both fail on it: the sibling whose owner field names another account (`owner id 555`, author the real owner) is
  `'accepted' != 'rejected'`, and the CLI with disagreeing merge-base owners in namespace `alice` exits `0 != 2`
  (first sorted entry silently wins). Fix, commit 9522a70: (1) in the "new entry in an owned non-reserved namespace"
  branch the new entry's `owner` (provider, id) must equal the recorded namespace owner, else an `R5` finding naming both;
  (2) `ownership_cli.py` raises a ToolError (exit 2) naming both entries when merge-base entries of one namespace disagree
  on owner. Three existing assertions that expected exactly `R3` now expect `R3`+`R5` where the stranger also proposes
  themselves as owner (the verdict is unchanged; not weakened). Two new mutations, both red:
  `n1-sibling-owner-field-not-checked`, `n1-cli-disagreeing-merge-base-owners-first-wins` (the runner now accepts an
  optional third item in an edit naming another file). Other suites were idle (`ps`) when I ran.
  `docs/tasks/007b-verify.sh` on 9522a70: `Ran 236 tests ... OK`, `ownership tests ran: 86`, `SUMMARY failed=0`.
  `docs/tasks/007b-verify.sh --mutate`:
```
ok    mutation table has 56 entries (floor 45)
baseline green on committed 9522a7053
SUMMARY 56 mutations, not_red=0
ok    every mutation turned its named tests red
SUMMARY failed=0
red      n1-sibling-owner-field-not-checked: 3 failing, all 1 named tests red
red      n1-cli-disagreeing-merge-base-owners-first-wins: 1 failing, all 1 named tests red
```
