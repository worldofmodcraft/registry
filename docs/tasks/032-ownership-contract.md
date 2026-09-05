# Task 032: The ownership check is an unwritten edge contract — registry half

- **Mission:** SITE-V1 — **Status:** spec-approved (Ludwig, in session, 2026-09-05, option A)
- **Agent / model:** doc-writer / sonnet
- **Budget:** small
- **Branch / worktree:** `task/032-ownership-contract` / `~/wt/registry-task-032`
- **Platform half:** the graph amendment (edge E16, `docs/architecture/depgraph.md`) is already
  merged to `origin/main` in the platform repository before this branch started, per ADR-0117
  ("graph before code"). This log treats that as done and cites it, rather than re-doing it.

## What I read, in order

1. `/home/ludwig/wom/CLAUDE.md` — rule 0 (token guard), rule 1 (English), rule 5 (forbidden
   shortcuts).
2. `/home/ludwig/wom/docs/manager/MANAGER.md` — guardrails 6/6b/6c in particular.
3. `docs/tasks/032-ownership-edge-contract.md` (platform repo, `origin/main`) — the full spec and
   acceptance criteria quoted in this task's brief.
4. ADR-0058 (publishing flow, ownership §2, confirmation text §3), ADR-0119 (reserved
   namespaces), ADR-0039 (namespace = username), ADR-0041 (integrity chain).
5. `contracts/append-only.rules.md`, `contracts/signature-format.md`,
   `contracts/artifact-naming.md`, `docs/contracts/README.md` — house style, in this worktree.
6. `docs/architecture/depgraph.md` (platform repo, `origin/main`) — E16's exact wording and the
   amendment log entry.
7. `contracts/entry.schema.json` and `reserved-namespaces.json` in this worktree, for the exact
   `owner` shape and the real reserved-namespace data.

## What I wrote

- `contracts/ownership.md` (new) — the contract for edge E16.
- `docs/contracts/README.md` — one index row (plus a one-sentence update to the intro paragraph
  naming this as the eleventh contract and this task's log, matching how task 025's merge was
  described in the same paragraph).
- `docs/tasks/032-ownership-contract.md` — this file.

`contracts/append-only.rules.md` was **not** touched, as instructed. Confirmed:
```
$ git diff --stat
 docs/contracts/README.md | 10 ++++++----
 1 file changed, 6 insertions(+), 4 deletions(-)
$ git status --short
 M docs/contracts/README.md
?? contracts/ownership.md
```
(`docs/tasks/032-ownership-contract.md` itself is also untracked at the point of this snapshot,
omitted from `git diff --stat` because it is new and not yet staged; the point being demonstrated
— nothing under `contracts/` besides the new file changed — holds regardless.)

## Acceptance criteria — evidence

**1. The graph is amended first (ADR-0117).** Satisfied by the already-merged platform-side
amendment, not by this branch. Verified by reading `origin/main`'s copy directly:
```
$ git -C /home/ludwig/wom show origin/main:docs/architecture/depgraph.md   # (run from this worktree's session, against the platform repo)
```
relevant lines:
```
- **Amended:** 2026-09-05 — **E16 (ownership) added** on Ludwig's explicit approval (task 032, option A). See "Amendment log" at the end of this file.
...
| E16 | author (forge identity) → N3 | ownership: the PR author's **numeric account id** is compared against `owner.id` for every namespace the PR touches; what a first publish binds; the ADR-0119 reserved-namespace case | `contracts/ownership.md` — added by amendment (Ludwig, 2026-09-05) |
```
and the amendment-log entry ("2026-09-05 — E16 (ownership) added ... Approved by Ludwig in
session, task 032, option A") is present in full at the end of that file. This criterion is
about that merge, and I did not modify anything to satisfy it.

**2. `contracts/ownership.md` exists and states, precisely enough to implement without me
present:**
- **What identity is compared, and why, in one sentence:** "the check compares the PR author's
  numeric account id against `owner.id`. It never compares usernames..." followed by the mandated
  sentence: "This must hold precisely because a username can be released by its holder ... and
  later registered by a completely different person, while a numeric account id identifies
  exactly one account for that account's entire lifetime and is never reassigned to a different
  one." (`contracts/ownership.md`, "What identity is compared" section.)
- **Against what, for every namespace, stated explicitly for the two-namespace case:** "The
  two-namespace case, stated explicitly: a single PR touching `alice:toolkit` and `bob:widget` in
  the same diff must pass **both** namespaces' checks before either is accepted..."
  (`contracts/ownership.md`, "Against what" section.)
- **What a first publish binds:** the "What a first publish binds" section names `id`,
  `owner.provider`, `owner.id` (sourced from the real PR object, never trusted from the PR's own
  proposed JSON), `owner.name_at_registration`, and the namespace string itself, and states what
  never changes afterward, tying to `append-only.rules.md`'s existing freeze.
- **The reserved-namespace case (ADR-0119):** its own section states the binding is identical in
  shape but the authorisation path differs (org membership, not id-equality), and explicitly says
  "This is a reservation, not an ownership exemption."
- **The exact ADR-0058 §3 confirmation text, quoted verbatim:**
  > "This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces
  > are never reassigned."

  Checked character-for-character against ADR-0058's own file:
  ```
  $ grep -n "This creates the namespace" /home/ludwig/wom/docs/decisions/0058-publishing-flow.md
  3. **Namespace creation:** implicit at first approved publish, after an explicit confirmation shown by the CLI and documented on the site: *"This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces are never reassigned."*
  ```
  Identical wording, reproduced as a blockquote rather than the ADR's own italic-inline styling
  (a formatting choice, not a wording change).
- **Where the check runs and what it does on failure:** stated in its own section, matching the
  actionable-rejection standard of `append-only.rules.md` and the asset scanner (names the
  namespace, the real id read, and either the mismatched `owner.id` or the ADR-0119 citation).

**3. The hostile fixture is specified as a required regression case for task 007.** Its own
section, "The required regression case for task 007 (acceptance criterion 3)," states the fixture
in full: an entry owned by id `100200300` (fabricated, marked as such), a PR opened by an account
whose current username matches (`alice`) but whose real `pulls.user.id` is `900800700`
(fabricated, marked as such) — a checker comparing usernames wrongly accepts it, a checker
comparing `pulls.user.id` against `owner.id` correctly rejects it. States plainly that task 007
"must include this exact fixture shape ... as a regression test before its ownership gate ships."

**4. At least three further attack attempts, each a real push against the rule.** Four recorded,
in `contracts/ownership.md`'s "Attack attempts against this contract" section:
1. Rewrite `owner.id` to the submitter's own id inside the same PR ("namespace transfer between
   accounts") — defeats a checker that compares against `new.owner` instead of `old.owner`;
   closed by the "old, never new" comparison-model rule stated up front in the document, plus
   `append-only.rules.md`'s independent frozen-`owner` rule as a second barrier.
2. Treat "reserved" as "unchecked" from outside the organisation (organisation-owned vs personal
   accounts) — a non-member submits a version-only PR to `test:hello-world` hoping the reserved
   path skips authorisation entirely; defeated because the reserved path is an active membership
   check (verified live, `gh api orgs/worldofmodcraft/members/womcraft` → `204`), not an
   early-exit.
3. Collide numeric ids across providers — a coincidence between a GitHub id and a future second
   provider's id; defeated by comparing the `(provider, id)` pair, never `id` alone.
4. A deleted-then-recreated account, same human, same username, new id — the original owner's
   account is deleted, the username is later reclaimed by (possibly) the same person on a new
   account with a different id; the rule cannot distinguish this from an attacker holding the
   recycled username, and is permanently locked out under "namespaces are never reassigned" —
   recorded explicitly as an intended, not incidental, consequence.

Each attempt states the concrete input, the outcome under a naive/wrong implementation, and the
specific rule in this document that closes it — not a restatement of the rule.

**5. MANAGER.md guardrail 6b/6c honoured — every environmental claim about GitHub's identity
model carries either a verification command with real output, or an inline caveat, at the point
the claim is made.** Every command below was actually run in this session; outputs are pasted
verbatim, not reconstructed.

| Claim | How it was checked | Real output |
|---|---|---|
| The `worldofmodcraft` org's numeric id is `324218296`, matching `reserved-namespaces.json` | `gh api orgs/worldofmodcraft --jq '{login,id,type}'` | `{"id":324218296,"login":"worldofmodcraft","type":"Organization"}` |
| A PR object's real author identity is `user.id`/`user.login`, distinct fields, on a real merged PR in this repository | `gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'` | `{"merged":true,"number":3,"user":{"id":324089373,"login":"womcraft"}}` |
| An individual account's id (`womcraft`, `324089373`) is distinct from the org's id (`324218296`) — needed for the reserved-namespace "cannot ever equal" argument | Same two commands above, compared | `324089373 != 324218296` |
| The org-membership check endpoint is real and username-keyed | `gh api orgs/worldofmodcraft/members/womcraft -i` | `HTTP/2.0 204 No Content` |
| GitHub attributes deleted-account content to a fixed placeholder account (`ghost`, id `10137`), rather than freeing the id | `gh api users/ghost --jq '{login,id,type}'` | `{"id":10137,"login":"ghost","type":"User"}` |
| A git commit's author/email is arbitrary, unauthenticated text, unrelated to any forge identity | Created and immediately reset a throwaway commit in this worktree (see log below) | commit showed `Totally Fake Name <fake@example.com>`; `git reset --hard HEAD~1` restored `womcraft <worldofmodcraft_github@snabbpost.com>` exactly |
| A renamed GitHub account's old username becomes available for anyone else to claim | Fetched GitHub's own docs page live | verbatim quote in the contract, cited with URL |
| A deleted account's username becomes available "after 90 days" | Fetched GitHub's own docs page live | verbatim quote in the contract, cited with URL |
| Whether a numeric account id is ever reused for a different account | Checked two official GitHub docs pages (neither states this for ids, only for usernames) and one general web search (no authoritative GitHub statement found, only third-party summaries with no cited source) | **Not verifiable within this task.** Marked as an explicit inline caveat in the contract, with the `ghost`-account finding noted as indirect, non-conclusive supporting evidence, and a note that ADR-0058 §2's defence rests on this assumption |

The throwaway-commit demonstration, in full, run in this worktree and immediately undone:
```
$ git log -1 --format='%an <%ae>'
womcraft <worldofmodcraft_github@snabbpost.com>
$ git commit --allow-empty --author="Totally Fake Name <fake@example.com>" -m "throwaway test commit, will be reset"
$ git log -1 --format='%an <%ae>'
Totally Fake Name <fake@example.com>
$ git reset --hard HEAD~1
$ git log -1 --format='%an <%ae> (restored)'
womcraft <worldofmodcraft_github@snabbpost.com> (restored)
$ git status --short
(clean before and after)
```

**6. `docs/contracts/README.md` indexes it, matching existing conventions.**
```
$ grep -n "ownership.md" docs/contracts/README.md
23:| `contracts/ownership.md` | Who may touch each namespace a PR modifies: PR author's numeric `(provider, id)` compared against `old.owner`, never a username, never `new.owner`; what a first publish binds (ADR-0058 Section 3's confirmation text, quoted); the reserved-namespace authorisation path (org membership, not id-equality) for `mc`/`test`; the required regression fixture (matching username, differing id) for task 007. | ADR-0058 Section 2-3, ADR-0119 | E16 |
```
Same table shape (File / What it is / Governing ADR / Depgraph edge(s)) as the ten rows already
there.

## What I could not verify

- **Whether GitHub ever reuses a numeric account id for a different account, including after the
  original account is deleted.** Not found stated explicitly in the two official GitHub docs
  pages fetched (`username-changes`, `personal-account-reference`) — both address username
  recycling in detail but say nothing about numeric ids specifically. A general web search
  returned only third-party summaries asserting non-reuse, with no GitHub-authored source cited.
  The one piece of real, live evidence gathered (`gh api users/ghost` → a fixed placeholder
  account, id `10137`, used for deleted-account content attribution) is consistent with non-reuse
  but does not prove it. Carried as an explicit inline caveat in `contracts/ownership.md`'s
  Attempt 4, flagged as load-bearing for ADR-0058 §2's own defence, not merely a footnote.
- **Whether GitHub organisations, like personal accounts, are subject to the identical
  90-day-after-deletion username-recycling window.** Not checked — out of this task's declared
  scope (the reserved namespaces are bound to the org's numeric id, which is what the contract's
  reserved-namespace section relies on; the org's own username-recycling behaviour was not a
  claim this contract needed to make, so it was not investigated).
- **GitHub's exact behaviour for a PR opened via API on behalf of an account distinct from the git
  committer identity inside it (e.g., a bot-mediated publish flow)** — not exercised against a
  real bot-mediated PR in this environment; the contract's rule (identity is always
  `pulls.user.id`, never anything from commit metadata) is stated as the requirement regardless of
  how the PR was mechanically opened, but this specific scenario was not independently tested.

## Questions

Both booked, in matching wording, inside `contracts/ownership.md`'s own `## Questions` section
(per the same reasoning task 025 used for its own cross-referenced questions — an implementer
reading only the contract must be able to see them too):

1. **Whether the reserved-namespace membership check must be re-evaluated on every CI run for a
   given PR, or only once at PR-open time.** No ADR settles this. Assumed: re-checked on every CI
   evaluation (the boring, restartable choice, ADR-0103). What rests on it: if a future decision
   fixes membership at PR-open time instead, a person who leaves the organisation mid-review would
   need an explicit re-check step added back.
2. **The account-migration recovery path that Attempt 4 shows does not currently exist.**
   `append-only.rules.md` already books the same hook for its own frozen-`owner` rule; recorded
   here too because this document's attack attempt is what makes the human cost visible. Assumed:
   no recovery path exists today; a namespace whose owning account becomes inaccessible is
   permanently unpublishable-to (fork to a new namespace, per ADR-0041). Nothing currently rests
   on this beyond the known, accepted consequence already implied by two accepted ADRs.

Neither is blocking; neither changes anything task 007 needs to build differently today.

## Log

- 2026-09-05 Worktree confirmed clean and based on `origin/main` at session start
  (`e449e26`, task 025's merge commit). Read all sources listed above.
- 2026-09-05 Ran the `gh api` verification commands (org id, PR author shape, org-membership
  endpoint, `ghost` placeholder account) and the throwaway-commit demonstration, before writing
  any prose, per guardrail 6c ("run it" rather than caveat what is checkable).
- 2026-09-05 Fetched GitHub's own documentation pages for username-rename and
  account-deletion behaviour (`docs.github.com/en/account-and-profile/concepts/username-changes`,
  `docs.github.com/en/account-and-profile/reference/personal-account-reference`) for verbatim
  quotes; searched for an authoritative statement on numeric-id reuse and found none — recorded as
  an explicit unverified caveat rather than asserted either way.
- 2026-09-05 Wrote `contracts/ownership.md`, then `docs/contracts/README.md`'s index row and
  intro-paragraph update, then this log. Verified file scope with `git status --short` and
  `git diff --stat` before committing — only the three declared files touched;
  `contracts/append-only.rules.md` untouched.
- 2026-09-05 Committed to `task/032-ownership-contract`. Not pushed, not merged, per this task's
  instructions — the manager reviews before anything moves.
