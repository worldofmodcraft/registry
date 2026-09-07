# Ownership check: the numeric account id, never the username string

Contract for edge **E16** (`author (forge identity) -> N3`) in `docs/architecture/depgraph.md`
(platform repository), added by amendment on Ludwig's explicit approval (task 032, option A,
2026-09-05). Task 007 implements the ownership gate directly from this document: every ambiguity
left here becomes a bug there, exactly as `contracts/append-only.rules.md` states for its own
edge (E4).

## Scope: what this document governs, and what it deliberately does not

This document answers exactly one question: **is the account that opened this PR authorised to
touch every namespace it touches?** It is the check `contracts/append-only.rules.md` names and
declines to perform itself: "Binding the namespace to an owner is the ownership gate's job
(ADR-0058 Section 2–3), not this document's." That delegation is correct, and this document is
its other half.

This document does **not** govern:
- **Whether `owner` may change after it is first set.** That is `append-only.rules.md`'s frozen-
  field rule ("no PR may ever change either, not even one from the namespace's own owner"). This
  document only decides who may cause the *first* write of `owner`, and who may add a version
  once `owner` already exists — never whether `owner` itself may later be edited. The two
  documents work together: this one gates identity, that one gates mutation, and neither
  substitutes for the other.
- **Schema shape or PR classification** — N3's other two jobs (`docs/architecture/depgraph.md`),
  owned by `contracts/entry.schema.json` and task 007's own classifier respectively.
- **Reserved-namespace list membership itself** (which namespaces are on the list, and why) —
  that is ADR-0119 and `reserved-namespaces.json`. This document only states how the identity
  check behaves once a namespace is known to be on that list.

## How to read this document: rule ids, and where the failure list comes from

Every requirement below is declared as a numbered rule at the start of its own paragraph, in one
of two classes:

- **Verdict rules, `R1`-`R11`.** Each one can reject a PR. Each has exactly one row in "Where the
  check runs and what it does on failure" below, naming what the rejection message says.
- **Checker rules, `I1`-`I8`.** These constrain how the check is built and what its verdict means.
  Breaking one is a defect in the checker, or in the process around it, rather than a reason to
  reject a particular PR, so they have no taxonomy row.

**The taxonomy is derived from the rules, not maintained beside them.** Two consecutive review
rounds of this document found the same defect: a prose list of "the failure modes" sitting next to
a growing set of requirements and drifting from them, each time leaving a requirement that could
reject nothing. The rule declarations are therefore the authority; the table is the per-rule
rejection message, keyed by rule id, and it is exactly as long as the set of verdict rules is.

Because a promise not to let the two drift again is worth nothing, `docs/tasks/032-verify.sh`
enforces the convention mechanically: its `T1`-`T9` checks fail the verification run if a rule id
is declared twice, if a declared verdict rule such as `R1` has no taxonomy row, if a taxonomy row
names a rule that no longer exists, or if any normative MUST is stated without a rule id beside
it. The convention that last check enforces is that **every normative MUST in this document cites
its rule id, such as `I1`, in the same paragraph**; it is what stops a future round from adding a
requirement outside the scheme, which is how the drift happened both times.

## The comparison model: `old.owner`, never `new.owner`

This document adopts `append-only.rules.md`'s own `old`/`new` vocabulary: `old` is the parsed
`entry.json` at the PR's merge-base with the target branch; `new` is the parsed `entry.json` in
the PR branch. **The ownership check always compares the PR author's real numeric account id
against `old.owner.id` (and `old.owner.provider` — see "Provider is part of the comparison,
not just id" below) — it must never read the id to compare against out of `new.owner`, the
version of the file the PR itself proposes.** This single rule is stated up front, ahead of
everything else below, because getting it backwards produces a checker that looks correct on
every well-behaved input and silently authorises the one attack this document exists to prevent
(Attack attempt 1, below).

**R3 (MUST)** — for a namespace that already exists at the PR's merge-base and is not on the
reserved list, the PR author's real `(provider, id)` pair MUST equal `old.owner.provider` and
`old.owner.id`. This is the ordinary case and the most common rejection; it is stated as a rule
here, beside the comparison model it depends on, so that the model and the requirement cannot
drift apart.

For a namespace that does not yet exist at the PR's merge-base with the target branch (no `old`
value — this is a first publish), there is nothing in `old` to compare against; "What a first
publish binds" below states the rules that apply instead. The classification is made against the
**merge-base**, deliberately and not loosely: ADR-0058 §5 makes every publish PR fork-based, so a
branch forked before someone else's merge is the normal case rather than the exception, and
`contracts/append-only.rules.md` already classifies changes against the merge-base. A checker that
classified against the target branch's current tip instead would call the same PR a first publish
or not depending on what merged while it sat open.

**I3 (MUST)** — the check reads `owner` from `old`, never from `new`, wherever an `old` value
exists. The only rules that read `new.owner` at all are `R5`, `R6` and `R8`, and only at a first
publish, where no `old` value exists to read: at that moment the PR's own proposed `owner` is
being checked *against the forge*, never trusted.

## What identity is compared: the forge's numeric account id, never the username string

**The check compares the PR author's numeric account id against `owner.id`. It never compares
usernames, display names, or `owner.name_at_registration`.** This must hold precisely because a
username can be released by its holder — deliberately, by renaming, or involuntarily, by account
deletion — and later registered by a completely different person, while a numeric account id
identifies exactly one account for that account's entire lifetime and is never reassigned to a
different one. A check that "helpfully" compares names instead of ids reopens exactly the
namespace-capture attack ADR-0058 §2 exists to close: once a username is recycled, a
username-based check cannot tell the new holder apart from the original owner.

**Verified, live, against this project's own registry (re-run in this fix round, 2026-09-06):**
```
$ gh api repos/worldofmodcraft/registry/pulls/3 --jq '{merged, user:{login:.user.login,id:.user.id}}'
{"merged":true,"user":{"id":324089373,"login":"womcraft"}}
```
(A two-key `--jq` object filter cannot emit a third `number` field; an earlier revision of this
document pasted `{"merged":true,"number":3,"user":{...}}` here, which the filter above cannot
produce under any input. That was a fabrication, found and corrected in review round 1 — see
`docs/tasks/032-ownership-contract.md`'s fix-round-1 log and `docs/tasks/032-verify.sh`, whose
`B6` checks assert this object's exact key set against both the current text and the pre-fix blob.)
This is the real shape the check reads from: a PR's `user.id` is a stable integer field on the PR
object itself (returned by GitHub's API independent of anything the PR's file contents claim),
distinct from `user.login`, which is a mutable display string.

**Why the check must read this from the PR object's `user.id`, never from anything inside the
git commits the PR carries.** A git commit's author name and email are arbitrary, unauthenticated
text the committer sets locally — they carry no relationship to any forge account and are not
verified by the forge at all. Demonstrated in this environment, on this worktree, with a
throwaway commit created and immediately discarded:
```
$ git log -1 --format='%an <%ae>'
womcraft <womcraft@snabbpost.com>
$ git commit --allow-empty --author="Totally Fake Name <fake@example.com>" -m "throwaway test commit, will be reset"
$ git log -1 --format='%an <%ae>'
Totally Fake Name <fake@example.com>
$ git reset --hard HEAD~1
$ git log -1 --format='%an <%ae> (restored)'
womcraft <womcraft@snabbpost.com> (restored)
```
(The committer address shown is whatever this worktree's local `git config user.email` holds at
the moment the demonstration is run — it has genuinely changed since this document was first
written, which is expected environment drift, not a defect; re-run to see the current value. The
substantive claim — a commit's author/committer identity is arbitrary, unauthenticated text — does
not depend on which placeholder address happens to be configured.)
Anyone can set a commit's author to any string with no verification whatsoever. The only identity
in a PR that the forge itself vouches for is the account that opened the PR through its own
authenticated API/UI session — GitHub's `pulls.user` field. **The ownership gate must read
identity from `pulls.user.id`, never from `git log`'s author/committer fields, a `Co-Authored-By`
trailer, or any other text inside the diff.**

**`GITHUB_ACTOR` and `GITHUB_ACTOR_ID`, the environment variables GitHub Actions exposes to a
running job, are equally forbidden as an identity source — for a different, more subtle reason
than the git-commit case above.** Unlike commit metadata, `GITHUB_ACTOR_ID` genuinely is a numeric,
forge-verified id, free in the CI environment, and is exactly what an implementer told to "compare
the numeric account id" is likely to reach for. But it identifies whoever's workflow run is
currently executing, which equals the PR author only for a plain `pull_request` event — it is a
**different** account (frequently a maintainer re-running a failed job, or a service account) for a
workflow re-run or a `workflow_dispatch` trigger. The only field this document ever authorises is
`pulls.user.id`, read from the PR object itself via the API, never from the environment of the job
evaluating it, `GITHUB_ACTOR`/`GITHUB_ACTOR_ID` included.

**I1 (MUST)** — the check reads the submitting identity from the PR object's `pulls.user.id` and
`pulls.user.login` and from nothing else: never from a commit's author or committer fields, never
from a `Co-Authored-By` trailer, never from any other text inside the diff, and never from
`GITHUB_ACTOR` or `GITHUB_ACTOR_ID` in the job's environment.

## Provider is part of the comparison, not just id

`owner` is `{ provider, id, name_at_registration }` (ADR-0058 §2, `contracts/entry.schema.json`).
**The comparison is on the `(provider, id)` pair, never on `id` alone.** The registry format is
provider-agnostic (ADR-0058 §4) precisely so a future non-GitHub source can publish, and two
different providers can — with nothing preventing it — assign the identical small integer to two
completely unrelated accounts. Phase 1 only ever sees `provider = "github"` in practice, but a
checker hard-coded to assume that (comparing bare integers with no provider check) would already
be wrong the day a second provider is accepted, and "already wrong the day X happens" is exactly
the failure shape `contracts/artifact-naming.md`'s `:`-in-a-git-ref attack describes for a
different document. Stated once, here, so task 007 never has to rediscover it.

**I6 (MUST)** — every identity comparison in this document is on the `(provider, id)` pair as a
whole, never on `id` alone. This binds `R3`, `R5` and `R8`, each of which names a `(provider, id)`
comparison for that reason.

## Against what: `owner.id` for every namespace the PR touches

The check runs **once per distinct namespace the PR touches, independently** — never only against
the first `entry.json` in the diff, and never only against whichever file changed the most lines.
A registry PR is a single diff that may touch any number of `mods/<namespace>.<name>/entry.json`
**and/or `mods/<namespace>.<name>/page.json`** paths — **the enumeration is not confined to
`entry.json`: ADR-0059 §3 requires a PR touching only `page.json` to pass "the same ownership
check (numeric id)"** as a PR touching `entry.json`, so a `page.json`-only PR is not a hole this
check skips (see "`page.json` PRs" below for what this does, and does not, additionally require).
The check enumerates every such path that appears in the diff, extracts its namespace (from the
path, identically for either file), and
evaluates that namespace's rule (this document's ordinary rule, or the reserved-namespace rule
below, whichever applies) independently for each.

**The two-namespace case, stated explicitly, with a named author rather than a restatement of
ownership.** A PR has exactly one author (`pulls.user`, a single account), so take a concrete one:
the PR is **opened by** `alice`, and the id the check compares is `alice`'s own real
`pulls.user.id` — the same single number for both namespaces, because there is only one author.
That id must equal `alice:toolkit`'s `old.owner.id` **and, separately,** `bob:widget`'s
`old.owner.id`. `bob:widget` is owned by `bob`, a different account with a different id, so the
second comparison fails and the entire PR is rejected — not merged with the `alice:toolkit` half
applied. A PR can therefore only legitimately touch several *existing* namespaces when the one
account that opened it owns every one of them.

**I7 (MUST)** — every namespace the PR touches is evaluated independently, and the PR is accepted
only if *every* namespace passes every rule that applies to it. There is no partial-merge path in
this model: `contracts/append-only.rules.md`'s own gate operates on the PR as a whole, and this
check is a further whole-PR precondition, not a per-file filter.

## The namespace of a touched path: the directory path is authoritative, and `id` must agree

A registry PR names a namespace in two places, and until this section they were free to disagree:
the directory a file sits in (`mods/<namespace>.<name>/`) and, for `entry.json` only, the `id`
field inside the file (`<namespace>:<name>`). Nothing in `contracts/append-only.rules.md` or
`contracts/entry.schema.json` ties the two together, so three faithful checkers — one reading the
path, one reading `id`, one reading each for a different purpose — reach three different verdicts
on the same PR. Review round 2 (finding B2) demonstrated the capture that follows; this section
removes the choice.

**I2 (MUST)** — the namespace a rule is evaluated against is derived from the **directory path**
and from nothing else. The path is authoritative. Three reasons, all structural rather than
stylistic. First, `contracts/page.schema.json` has no `id` and no `owner`, so a `page.json` path
has no in-file namespace to read at all — verified in this environment rather than assumed
(guardrail 6c):

```
$ python3 -c "import json;print(sorted(json.load(open('contracts/page.schema.json'))['properties']))"
['deprecated', 'description', 'links', 'screenshots', 'tags']
```

Second, two entries cannot occupy one directory, so the path is unique by construction, while `id`
is only a string the PR proposes about itself. Third, `append-only.rules.md` already classifies a
PR's changes by path, and a second, disagreeing derivation would put two contracts at odds over
the same PR.

**R1 (MUST)** — every path the PR touches under `mods/` MUST be of the form
`mods/<namespace>.<name>/entry.json` or `mods/<namespace>.<name>/page.json`, where `<namespace>`
and `<name>` each match `[a-z0-9][a-z0-9_-]*` — the character class
`contracts/entry.schema.json`'s `id` pattern already requires, and in which neither part may
contain a `.`, so the directory name contains exactly one. A touched path under `mods/` that does
not parse this way yields no namespace, and is **rejected rather than skipped**: a path the check
cannot attribute to a namespace is precisely the input that must never fall through it. Today
those two filenames are the only ones the registry defines under `mods/<namespace>.<name>/`; if a
future ADR adds a third, it must amend `R1` in the same change, because until it does `R1` rejects
it — deliberately, since the alternative is a path this check silently ignores.

**R2 (MUST)** — for every `entry.json` the PR touches, `new.id` MUST equal the `<namespace>:<name>`
derived from that file's own directory, and where an `old` entry exists `old.id` MUST agree as
well. The two sources naming different namespaces is not a stylistic complaint to fold into schema
validation; it is the exact condition under which a checker's verdict depends on which source it
happened to read, so it is rejected here, with both namespaces named in the message.

## What a first publish binds

ADR-0058 §3, quoted verbatim, is the confirmation the CLI shows and the site documents before a
first publish proceeds:

> "This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces
> are never reassigned."

At the moment a namespace is created — no `old` entry exists for it at the PR's merge-base, so
this PR is that namespace's first publish (ADR-0058 §1) — five things become authoritative
forever: `id`, `owner.provider`, `owner.id`, `owner.name_at_registration`, and the namespace
string itself (the part of `id` before `:`, which ADR-0039 derives from the account's username).
`id` and every field of `owner` are frozen from this PR onward by `contracts/append-only.rules.md`'s
existing frozen-field rule, which this document relies on and never restates.

Four rules decide who may cause that first write. `R4`, in "The namespace string itself" below,
governs the namespace string; `R5` and `R6` here govern `owner`; and a namespace on the reserved
list is governed by `R8` and `R7` instead of all three, as the exception at the end of this
section states.

**R5 (MUST)** — at a first publish of a namespace **not** on the reserved list,
`new.owner.provider` and `new.owner.id` MUST equal the PR author's real `(provider, id)` pair as
read from the PR object (`pulls.user.id`, GitHub in phase 1), never a value taken from the PR's own
proposed `entry.json` without that cross-check against the live PR object. A checker that trusts
the JSON's self-declared `owner.id` at a first publish lets a PR create an entry claiming any
numeric id at all — including someone else's — with nothing to stop it, because there is no `old`
value yet to contradict it. The check at a first publish is therefore not "does `new.owner.id`
equal `old.owner.id`" but "does `new.owner.id` equal the real, forge-verified id of whoever is
submitting this PR right now."

**R6 (MUST)** — at that same first publish, `new.owner.name_at_registration` MUST equal the PR
author's username as the PR object reports it (`pulls.user.login`), compared case-insensitively
per `R4`'s folding rule. The value is frozen forever and is what ADR-0058 §3's confirmation text
names the account by, so a false one is permanent misinformation in the registry's own history. It
stays informational *for authorisation*: no rule ever compares it to decide who may touch an
existing namespace — `R3` compares `owner.id`, and only `owner.id`.
**Where this rule comes from, attributed rather than assumed:** it is **this document's derivation
from ADR-0058 §2**, which *defines* `name_at_registration` as the account's username at
registration. Requiring the recorded value to actually be that username is this document reading
that definition as a requirement; **ADR-0058 §2 does not state the check in those words**, and no
ADR read for this task does. The rule is required as written — that is the point of stating the
basis rather than softening the rule — but a reader should be able to see that it rests on an
interpretation, so it can be revisited if ADR-0058 §2 is ever clarified or amended. Ruled by
Ludwig on 2026-09-07 (option (a): keep it checked, because it is derivable and it is checkable,
and guardrail 6c says check what can be checked rather than caveat it). If a future decision
reverses that, `R6` and its row in the rejection taxonomy are removed together — `docs/tasks/032-verify.sh`'s
`T5`/`T6` fail if only one of the two goes.

**R8 (MUST)** — **Exception for a namespace on the reserved list (ADR-0119 §2), stated here at the
point the ordinary rule is made, so the two never have to be reconciled by a reader:** at a first
publish of a namespace on the reserved list, `new.owner` MUST equal the owner
`reserved-namespaces.json` records for that namespace at the PR's merge-base — in phase 1
`{"provider": "github", "id": 324218296, "name_at_registration": "worldofmodcraft"}`, the
`worldofmodcraft` organisation — and never the PR author's own id. `R4`, `R5` and `R6` do not
apply to these namespaces and could never be satisfied for them anyway: no individual account's
numeric id can equal the organisation's, which "The reserved-namespace case" below proves from
this project's own data. Authorisation for such a PR is `R7`, organisation membership, from the
first publish onward. There is no separate reserved-first-publish rule anywhere else in this
document.

**What may never change afterwards:** `id` and every field of `owner`, per
`contracts/append-only.rules.md`'s existing frozen-field rule — this document does not repeat that
rule's mechanics, only relies on it. Consistent with "namespaces are never reassigned," nothing in
this document, or in `append-only.rules.md`, admits any path by which `owner` changes after the
namespace's first publish, short of a future ADR that amends both documents together
(`append-only.rules.md` already states this precondition explicitly).

## The namespace string itself: it equals the author's username at first publish (ADR-0039)

**R4 (MUST)** — at a first publish of a namespace **not** on the reserved list, the namespace
string (derived from the directory path per `I2`) MUST equal the PR author's current GitHub
username (`pulls.user.login`), compared case-insensitively.

Without this rule, nothing in the id-based rules stops a fresh account from first-publishing into
a namespace named after someone else's username entirely: `R5` only ever asks whether the PR
author's id equals `new.owner.id`, and at a first publish the PR itself supplies `new.owner.id` —
nothing yet requires that value, or the namespace string beside it, to bear any relationship to
any *other* person's account. Concretely: an account whose real id is `999` and whose username is
`mallory` opens a first-publish PR creating `mods/alice.cooltool/entry.json` with
`owner: {provider: "github", id: 999, name_at_registration: "mallory"}`. `R5` alone asks only
"does `999` (the submitter's real id) equal `999` (`new.owner.id`, which the same PR supplies)?" —
trivially yes; `alice` is not reserved; so a checker built from the id rules alone accepts it. That
is namespace capture, the exact attack ADR-0058 §2 exists to close and the reason edge E16 was
added to the graph at all. **`R4` is what closes it:** `mallory` does not equal `alice`, so the PR
is rejected regardless of what `owner` it proposes for itself.

**Case-folding: compare after folding both sides to lowercase — Ludwig's ruling, 2026-09-07.**
`contracts/entry.schema.json`'s `id` pattern (`^[a-z0-9][a-z0-9_-]*:[a-z0-9][a-z0-9_-]*$`) is
lowercase-only, while GitHub usernames may contain uppercase letters, so a literal, case-sensitive
comparison would reject every first publish from a user whose username contains a capital. No ADR
states this normalisation in those words, and that is exactly why it is stated here: a behaviour
that exists only inside a checker's implementation is what this contract exists to prevent.

The premise `R4`'s folding rests on — that a GitHub username identifies one account
case-insensitively, so folding can never merge two different people — is **verified in this
environment** rather than assumed (guardrail 6c):

```
$ for u in womcraft WOMCRAFT WomCraft; do printf '%s -> ' "$u"; gh api users/$u --jq '{login,id}'; done
womcraft -> {"id":324089373,"login":"womcraft"}
WOMCRAFT -> {"id":324089373,"login":"womcraft"}
WomCraft -> {"id":324089373,"login":"womcraft"}
```

Three casings, one account id. **The caveat that travels with the claim** (guardrail 6b): that is
GitHub's live behaviour for a real account today, observed here, not a guarantee located in
GitHub's own reference documentation. The rule is required as written; if GitHub ever permitted
two accounts differing only in case, `R4`'s folding would need re-examination before it could
merge them.

**Scope: first publish only, and never re-checked after.** There is no `old` value for a
namespace-derivation rule to compare against on a later PR to an existing namespace — a PR adding
a version never re-derives the namespace string, and `id` is frozen forever once created
(`append-only.rules.md`, and "What may never change afterwards" above). A later account rename
does not retroactively invalidate an existing binding: `owner.id` is what is bound, and
`name_at_registration` is informational for authorisation, exactly as stated above.

**What `R4` does not close — the residual, recorded rather than left to be discovered.** `R4`
compares against the author's username *at the moment of the first publish*, which is the only
moment a namespace string is ever derived, so the rename-and-claim sequence survives it: `alice`
renames her account away, her old username becomes claimable ("After changing your username, your
old username becomes available for anyone else to claim" — GitHub's own documentation, quoted with
its source under "Attack attempts" below), `mallory` registers `alice`, and `mallory` then
first-publishes `alice:cooltool`. At that moment `mallory`'s current username genuinely *is*
`alice`; `R4` passes; the binding is permanent. This is the same residual Attempt 4 records for
*existing* namespaces, arriving at the other end of a namespace's life: the identity this document
trusts is the forge's, and the forge itself hands the name over. Closing it would need a rule no
ADR has decided — a reservation window on released usernames, or a decision that a recycled
username may never found a namespace — so it is recorded here, not invented.

**Reserved namespaces are exempt from this check.** `mc` and `test` do not derive their namespace
string from any account's username at all (ADR-0119 §1-2); `R8` and `R7` are the entire rule for
those namespaces' first publish, replacing `R4`, `R5` and `R6` together.

## The reserved-namespace case (ADR-0119): a reservation, not an ownership exemption

`mc` and `test` are reserved (`reserved-namespaces.json`), bound to the `worldofmodcraft`
organisation's numeric account id rather than an individual's:

```
$ gh api orgs/worldofmodcraft --jq '{login,id,type}'
{"id":324218296,"login":"worldofmodcraft","type":"Organization"}
```
This matches `reserved-namespaces.json`'s own recorded `owner.id` (`324218296`) for both `mc` and
`test`, confirmed live against the real account rather than assumed from the file's own content.

**This section governs a reserved namespace's first publish exactly as it governs every later
version — it is not confined to `present -> present`.** "What a first publish binds" above states
this section's rule replaces the ordinary first-publish rule for `mc` and `test`, in full, not
only after the namespace already exists; there is no separate reserved-first-publish rule anywhere
else in this document.

**The binding mechanism is identical to every other namespace** (ADR-0119 §2): `owner` for a
reserved namespace is the same three-field shape, and `contracts/entry.schema.json`'s own
description states this explicitly — "this schema does not distinguish the two cases, by design."
Nothing about *what is stored* differs.

**What differs is *how a PR is authorised*, and it must differ, structurally — this is not a
design choice with an alternative, it is a consequence of what the numbers are.** No individual
GitHub account's numeric id can ever equal the organisation's own numeric id — they are different
accounts, verified distinct in this project's own data:
```
$ gh api repos/worldofmodcraft/registry --jq '{full_name,owner:{login:.owner.login,id:.owner.id,type:.owner.type}}'
{"full_name":"worldofmodcraft/registry","owner":{"id":324218296,"login":"worldofmodcraft","type":"Organization"}}
```
(Re-run in this fix round: the nested `owner` object's key order in real output is `id, login,
type` — alphabetical — not the `login, id, type` order the filter literally names. `gh api --jq`
uses `gojq`, which sorts constructed-object keys alphabetically regardless of the order they are
written in the filter; an earlier revision of this document pasted the filter's literal order
instead of the real output. The values themselves were always correct; only the key order was
wrong. Content, not just presence, now matches a fresh run.)
(`324218296`, the org, against `324089373`, the individual account `womcraft` used to submit real
PRs in this repository's own history — shown above under "What identity is compared.") **The
ordinary rule ("PR author's id equals `owner.id`") can therefore never pass for a reserved
namespace by construction, no matter who submits the PR** — this is exactly why ADR-0119 §3
defines a *separate* authorisation path rather than special-casing the equality check: the two
are different questions. Ordinary case: "is this PR author's id equal to `owner.id`?" Reserved
case: "is this PR author currently a member of the organisation that owns this namespace?"

**The membership check itself: the answer depends on who is calling, not only on who is being
asked about — this is documented GitHub behaviour, not just an observation from one token.**
GitHub's own REST reference for `GET /orgs/{org}/members/{username}` states three outcomes:
`204` if "requester is an organization member and user is a member"; `404` if "requester is an
organization member and user is not a member"; **`302`** if "requester is not an organization
member" — regardless of whether the named user is one. (<https://docs.github.com/en/rest/orgs/members>,
fetched live during this round.) **The calling identity's own membership gates which of these
three branches is even reachable.**

Verified live, in this environment, both branches:

- **Member-caller branch** (the `womcraft` token, itself an org member, asking about `womcraft`):
  ```
  $ gh api orgs/worldofmodcraft/members/womcraft -i
  HTTP/2.0 204 No Content
  ```
  Direct `204`/`404` answers, no redirect, exactly as documented for a member requester.
- **Non-member-caller branch** (an unauthenticated request — GitHub treats "no credential" the
  same as "requester is not an organization member" for this endpoint, since there is no
  authenticated identity to be a member):
  ```
  $ curl -s -o /dev/null -w 'status=%{http_code} redirect=%{redirect_url}\n' \
      https://api.github.com/orgs/worldofmodcraft/members/womcraft
  status=302 redirect=https://api.github.com/organizations/324218296/public_members/womcraft
  $ curl -s -L -o /dev/null -w 'final_status=%{http_code}\n' \
      https://api.github.com/orgs/worldofmodcraft/members/womcraft
  final_status=404
  ```
  `womcraft` genuinely **is** a member (`204` above, from the member-caller branch) but is not a
  **public** member, so a non-member caller is redirected to `GET
  /orgs/{org}/public_members/{username}` — a different, public-only endpoint — and following that
  redirect lands on `404` regardless of the target's real (private) membership.

**I5 (MUST NOT)** — a checker MUST NOT follow the `302` and treat the followed request's final
status as the answer; the request that asks the membership question is made with redirect-following
turned off. This is the **mandatory** arm of the check, not one of two designs a reader may choose
between, because every default HTTP client disagrees with it and the failure is silent.

What was actually run here rather than reasoned about (guardrail 6c), against a GitHub endpoint
that genuinely redirects — the renamed repository `facebook/jest`, which the API answers with a
`301` — because the membership `302` itself is only reachable from a non-member caller:

```
$ curl -s -o /dev/null -w 'status=%{http_code} redirect=%{redirect_url}\n' https://api.github.com/repos/facebook/jest
status=301 redirect=https://api.github.com/repositories/15062869
$ python3 -c "import requests; r=requests.get('https://api.github.com/repos/facebook/jest'); print(r.status_code, [h.status_code for h in r.history])"
200 [301]
$ gh api repos/facebook/jest --jq '{full_name,id}'
{"full_name":"jestjs/jest","id":15062869}
```

So, **verified in this environment**, client by client rather than as one sweeping claim: plain
`curl` does **not** follow a redirect — `-L` is opt-in, and an earlier revision of this document
had this backwards; Python's `requests` **does** (`allow_redirects=True` is its default, shown by
the `[301]` in its redirect history); and `gh api` **does** — it was asked for `facebook/jest` and
answered with `jestjs/jest`. **`octokit.js`'s default was not established here** — no octokit
installation exists on this machine — and is marked unverified rather than asserted (guardrail
6b); an implementer using it must check its redirect behaviour before relying on `I5`.

**R9 (MUST)** — if the membership question returns anything other than the two answers GitHub
documents for a member requester — `204` (is a member) or `404` (is not) — the check MUST reject
the PR, closed, with an error naming the status it received. The `302` is the case this rule exists
for: it means the calling identity cannot see this organisation's private membership, which is not
evidence about the PR author at all, and reinterpreting it as "not a member" is what rejects every
legitimate `mc:`/`test:` PR — including the first publish of `test:hello-world`, mission acceptance
criterion 2. Every other status (`401`, `403`, `5xx`, a timeout) takes the same path: an
indeterminate answer is never read as "no", and never as "yes" either.

Running the check as a caller that is itself a confirmed organisation member is worth doing **in
addition to** `I5` and `R9`, because it makes the direct `204`/`404` branch the one normally taken.
It is **never instead of** them. It is a precondition this document cannot verify (see the next
paragraph), and a precondition that stops holding silently — a rotated token, a membership change —
degrades into exactly the `302` that `R9` must still be there to catch. An earlier revision of this document offered
the two as interchangeable designs, which left a checker built from the first one with no `302` arm
at all: review round 2's finding B4.

**What this means for the actual CI caller — marked here, not assumed.** Which branch CI hits
depends entirely on whether the identity that registry CI uses to authenticate is itself an
organisation member. **This could not be established in this environment: this machine has no
GitHub Actions runner, and settling it by reading a stored credential is forbidden (CLAUDE.md
rule 11, MANAGER.md guardrail 10).** GitHub Actions' default `GITHUB_TOKEN` is a per-run,
repository-scoped installation token, not any individual account's token, and whether it (or an
org-scoped credential stored as a secret) satisfies "requester is an organization member" for this
endpoint is an **unverified claim, marked here at the point this document would otherwise assert
it** (guardrail 6b): task 007's implementer must confirm which identity the ownership-check job
authenticates as before relying on the member-caller branch above, and if it is not itself an org
member, the check must not silently run through the non-member branch and reject every reserved-
namespace PR.

**A second candidate, with its own caller requirement — not adopted, only established:**
`GET /orgs/{org}/memberships/{username}` has no `302` branch, but GitHub's own documentation
states it requires the same precondition: *"In order to get a user's membership with an
organization, the authenticated user must be an organization member."* Verified live in this
environment: unauthenticated, it refuses outright rather than degrading to a public view —
```
$ curl -s -o /dev/null -w 'status=%{http_code}\n' \
    https://api.github.com/orgs/worldofmodcraft/memberships/womcraft
status=401
```
— and as a member-caller (the `womcraft` token) it answers directly, no redirect:
```
$ gh api orgs/worldofmodcraft/memberships/womcraft --jq '{role,state}'
{"role":"admin","state":"active"}
```
(Re-run in fix round 4: the real output's key order is `role, state` — alphabetical — not the
`state, role` order an earlier revision of this document pasted here. `gh api --jq` uses `gojq`,
which sorts constructed-object keys alphabetically regardless of the order the filter names them,
exactly as the note under `gh api repos/worldofmodcraft/registry` above already recorded for that
transcript; the correction was applied there and not here. The filter above is now written in the
same order it emits. The values were always correct; only the key order was unproducible.
`docs/tasks/032-verify.sh`'s `J` checks now assert this for **every** `gh api ... --jq '{…}'`
transcript in this document, deriving the permitted key set from each filter, so the next instance
cannot hide behind a per-transcript check again.)
`state == "active"` is the success condition when this endpoint answers at all. **This endpoint is
a candidate, not an answer**, exactly as the round-1 fix brief named it: it removes the `302`/
redirect ambiguity, but it does not remove the "is CI's own identity an org member" question above
— GitHub's documented `403` for an authenticated-but-non-member caller was not independently
reproduced here, since doing so would require a second identity, which this round does not use.

**I4 (MUST)** — which revision of `reserved-namespaces.json` the check reads: `old`, never `new` —
the same discipline "The comparison model" above applies to `owner`, applied here to list
membership. The
check evaluates a PR against the reserved list as it stood at the PR's merge-base with the target
branch, never the version the PR itself proposes. A PR that, in the same diff, removes `mc` from
`reserved-namespaces.json` **and** first-publishes `mc:core` must still be evaluated as if `mc`
were reserved — reading `new` here would let a single PR strip a namespace's reserved status and
capture it in the same breath, the identical attack shape Attempt 1 below closes for `owner`
itself, applied to list membership instead of the ownership field.

**R7 (MUST)** — a PR touching a namespace on the reserved list is authorised only if the PR author
is a **current member** of the organisation `reserved-namespaces.json` records as that namespace's
owner. This is a reservation, not an ownership exemption: every other account is rejected, exactly
as an ordinary namespace rejects a non-owner, citing ADR-0119 by name in the rejection message
(ADR-0119 §3: "rejects it otherwise with a message naming this ADR"). It applies to a first publish
and to every later version alike — see "governs a reserved namespace's first publish" above — and
it is an active check re-run on each CI evaluation, never an early exit taken because a namespace
is special.

## Where the check runs and what it does on failure: the rejection taxonomy

The check runs in registry CI (**N3**, `docs/architecture/depgraph.md`), on every PR against
`worldofmodcraft/registry`, before the append-only diff check and schema validation are treated as
sufficient to merge — `append-only.rules.md` explicitly assumes this check exists elsewhere and
does not perform it.

On failure the PR is rejected with a message that states, per namespace that failed: which
namespace, the PR author's real numeric id and provider as read from the PR object, and the row
below for the rule that failed. **The table is derived from the rule declarations above — one row
per declared verdict rule, no more and no fewer** — rather than being a separate list maintained
beside them; `docs/tasks/032-verify.sh`'s `T5` and `T6` fail the verification run if the two ever
diverge in either direction. It is not a closed list of "the" failure modes and must not be read as
one: it is exactly as long as the set of verdict rules is, and it grows when they do.

| Rule | When it rejects | What the rejection message says |
|---|---|---|
| `R1` | a touched path under `mods/` does not parse as `mods/<namespace>.<name>/entry.json` or `.../page.json` | the offending path, and that no namespace could be attributed to it |
| `R2` | an `entry.json`'s `id` names a different namespace than its own directory does | the path's namespace, the `id`'s namespace, and that the path is authoritative (`I2`) |
| `R3` | an existing, non-reserved namespace's `old.owner` `(provider, id)` is not the PR author's | the namespace, the author's real `(provider, id)`, and the `owner.id` it did not match |
| `R4` | at a first publish, the namespace string is not the author's username, folded to lowercase | the namespace, the author's username, and that a first publish binds the namespace to the name it derives from (ADR-0039) |
| `R5` | at a first publish, the proposed `new.owner` `(provider, id)` is not the submitter's own | the namespace, the author's real `(provider, id)`, and the `owner` the PR proposed instead |
| `R6` | at a first publish, `new.owner.name_at_registration` is not the author's username | the namespace, the author's username, and the value the PR proposed instead |
| `R7` | the PR author is not a current member of the organisation owning a reserved namespace | the namespace, the organisation, and ADR-0119 by name, per ADR-0119 §3 |
| `R8` | at a reserved namespace's first publish, `new.owner` is not what `reserved-namespaces.json` records | the namespace, the recorded owner, and the `owner` the PR proposed instead |
| `R9` | the membership question answered neither `204` nor `404` — a `302`, or anything else | the status received, that membership could not be determined, and that the check fails closed rather than guessing |
| `R10` | a `page.json` is touched where no `entry.json` exists at the merge-base and none is created in the same PR | the path, and that no entry exists for that namespace to own it |
| `R11` | a takedown PR is opened by an account other than the platform's own identity | the namespace, the author's real `(provider, id)`, and that only the platform's own account may open a takedown (Ludwig, 2026-09-07) |

This is the same actionable-rejection standard `append-only.rules.md` and the asset scanner already
meet — no generic "ownership check failed," always the specific mismatch a reader can act on.

## `page.json` PRs: same ownership check, and the case where no `entry.json` exists

A PR touching `page.json` is enumerated exactly as an `entry.json` PR is (`I2`, `I7`): the
namespace comes from the directory path, and ADR-0059 §3 requires such a PR to pass "the same
ownership check (numeric id)" as one touching `entry.json`. Which rule then applies depends on what
exists at the merge-base, and there are exactly three cases — the third, where no `entry.json`
exists at all, is the one review round 2 (finding B3) found undefined while this section claimed to
be complete.

1. **An `entry.json` for that namespace exists at the merge-base.** `R3` applies against that
   entry's `old.owner` — or `R7`, if the namespace is on the reserved list. Nothing is special
   about the touched file being `page.json`.
2. **No `entry.json` exists at the merge-base, but the same PR creates one.** That namespace's
   first publish is happening in this same diff, so the first-publish rules decide the whole PR —
   `R4`, `R5` and `R6`, or `R8` and `R7` for a reserved namespace — and the `page.json` raises no
   separate authorisation question: it belongs to the same namespace and rides on the same verdict.
3. **No `entry.json` exists at the merge-base and the PR does not create one.** `R10`.

**R10 (MUST)** — a PR that touches `mods/<namespace>.<name>/page.json` where no `entry.json` for
that namespace exists at the merge-base, and none is created in the same diff, MUST be rejected.
There is no owner anywhere for the check to read: `old` does not exist, and `page.json` carries
neither `owner` nor `id` — `contracts/page.schema.json`'s properties are exactly `deprecated`,
`description`, `links`, `screenshots` and `tags`, verified in this environment with the command and
output shown under "The namespace of a touched path" above. The first-publish rules cannot be
applied to a file that has no `owner` to check and nothing to bind to an author, so a checker told
only that "the first-publish rule applies when there is no `old`" would crash, pass the PR
vacuously, or reject every legitimate page PR, depending purely on how it was written. The
rejection is not a limitation to work around: a mod page describes a mod, and the mod's `entry.json`
is what records who owns it, so a page with no entry has no owner by construction rather than by
oversight.

**What this document does not additionally require for `page.json` — a declared boundary, not a
silent one.** ADR-0059 §3 also requires an "asset scan on new screenshots" for a page-content PR.
That is a separate gate, owned by the asset scanner (`contracts/validation-report.schema.json`),
not this document — and it is **deferred to task 040**, because no archived source exists to scan
new screenshots against until task 008 (the build pipeline) has run at least once; task 040 depends
on that archive existing. A `page.json` PR that changes screenshots must therefore pass **two**
independent gates before it is accepted: this document's ownership check, and task 040's asset
scan. This document only ever speaks to the first, and passing this check alone is not sufficient
to accept such a PR.

## The required regression case for task 007 (acceptance criterion 3)

**A PR whose author id differs from `owner.id` while the username matches must be rejected.**
Written here as a required fixture so task 007 inherits it rather than inventing its own version
of the same test.

**Fabricated example — no real account is involved, every id below is placeholder data clearly
marked as such:**

- On the target branch, `mods/alice.cooltool/entry.json` already exists, with
  `owner = { provider: "github", id: 100200300, name_at_registration: "alice" }`.
- The GitHub account whose *current* username is `alice` opens a PR adding a new version to this
  entry. Its real numeric id, as GitHub's API reports on the PR object
  (`pulls.user.id`), is `900800700` — a different number entirely. (Consistent with real,
  verified GitHub behaviour: "Your username will be available for anyone to use after 90 days"
  — GitHub's own documentation, quoted verbatim under "Attack attempts against this contract"
  below — so a second, unrelated account legitimately holding the username `alice` today is a
  real reachable state, not a contrived one.)
- **A checker comparing usernames** (`pulls.user.login == owner.name_at_registration`, both
  literally the string `"alice"`) **accepts this PR.** This is the wrong check and must never be
  what task 007 implements.
- **A checker comparing `pulls.user.id` against `owner.id`** (`900800700` vs `100200300`)
  **rejects this PR**, correctly, because the two numbers differ. This is the check this document
  requires.

Task 007 must include this exact fixture shape — matching username, differing numeric id — as a
regression test before its ownership gate ships, and the test must fail (i.e. correctly reject)
against it.

## Attack attempts against this contract, recorded per acceptance criterion 4

**Attempt 1 — rewrite `owner.id` to the submitter's own id, inside the same PR that adds a
version ("namespace transfer between accounts").** A publisher wants to move
`alice:cooltool` to a new account they control (a personal reorganisation, or moving a solo
project under a fresh organisation) and opens a single PR that both adds a new version **and**
changes `owner` to the new account, submitted *from* that new account. **Under a checker that
compares the PR author's real id against `new.owner.id`** (the version of `owner` the PR itself
proposes, rather than `old.owner.id`, the version already on the target branch) **this passes
completely** — the new account's real id, freshly written into `new.owner.id` by the same PR,
trivially equals itself. Every input looks legitimate: the version content is real and wanted,
and "the PR author's id matches owner.id" is technically true of the PR's own proposed content.
**What the contract does about it:** "The comparison model" above fixes this before it can be
implemented wrong — the comparison is always against `old.owner`, which still names the
*original* account, so the mismatch (original id vs new submitter's id) is caught regardless of
what the PR proposes to change `owner` to. This is also exactly why
`contracts/append-only.rules.md`'s frozen-`owner` rule exists as a second, independent barrier: even
setting the identity question aside, no PR may ever change `owner` at all, so this specific attempt
is rejected twice over, by two different documents, for two different reasons — this document
because the *submitter* was never authorised in the first place, `append-only.rules.md` because
`owner` itself may not move even for someone who is.

**Attempt 2 — treat "reserved" as "unchecked," from outside the organisation.** A contributor who
is not a member of `worldofmodcraft` opens a PR adding a version to `test:hello-world`, an
existing reserved-namespace entry, changing nothing about `owner` at all (so
`append-only.rules.md`'s freeze never even triggers — `owner` is genuinely, byte-for-byte,
unchanged). The bet: since `test:` is "the platform's own namespace, not any individual's," maybe
nothing actually re-checks who is submitting once a PR merely adds a version rather than
touching `owner`. **What the contract does about it:** the reserved-namespace path above is an
*active* authorisation check — org membership, re-verified live — not an early-exit that skips
authorisation because the namespace is special. The contributor's account is not a member of
`worldofmodcraft`, the membership check returns `404`, and the PR is rejected citing ADR-0119, the
same as any other unauthorised PR. ADR-0119 §4's own words apply directly here: this reservation
"is an exception surface," and an exception surface that turns into "nobody checks" the moment a
PR avoids touching `owner` would be exactly the undocumented leniency ADR-0119's context section
exists to prevent.

**Attempt 3 — collide numeric ids across providers.** ADR-0058 §4 requires the registry format to
stay provider-agnostic; suppose a second provider is eventually accepted (phase 3) and, by sheer
coincidence, assigns the same small integer as some existing GitHub account's id to an entirely
different person on the new provider. A PR from that second-provider account, touching a
namespace whose `owner.id` happens to equal that same integer under `provider: "github"`, is
submitted. **Under a checker comparing `id` alone**, ignoring `provider`, **this passes** — the
integers match, even though the two accounts have nothing to do with each other and live on
different forges entirely. **What the contract does about it:** "Provider is part of the
comparison, not just id" above requires the `(provider, id)` pair to match as a whole; a PR from
`provider: "some-new-forge", id: 100200300` never matches `owner = { provider: "github", id:
100200300, ... }`, regardless of the numeric coincidence, because the providers differ.

**Attempt 4 — a deleted-then-recreated account, same human, same username, new id.** The original
owner of `alice:cooltool` deletes their GitHub account (any reason — a fresh start, a security
incident, a policy action) and, more than 90 days later, registers a **new** GitHub account under
the identical username `alice` (GitHub's own documentation, quoted below, confirms the old
username becomes available to be claimed again after that window — by anyone, including
originally the very same person). They now hold a **different** numeric account id than before —
GitHub assigns a new id to every new account — and attempt to publish a new version to their own,
original `alice:cooltool` namespace from this new account. **Under this document's rule, this PR
is rejected**, indistinguishably from an attacker who is not the original person at all: the new
account's real id does not equal `old.owner.id`, full stop, and this document's own id-based
check has no way — and is not designed to have a way — to tell "the original person, now on a
new account" apart from "someone else entirely who happens to hold the same username today." This
is not a gap to close; it is the direct, permanent, intended consequence of "namespaces are never
reassigned" (ADR-0058 §3) plus ADR-0041's "the platform never reassigns a namespace" for
abandoned mods — the only paths back are forking to a new namespace (ADR-0041) or a future ADR
that defines an explicit account-migration recovery process and amends both this document and
`append-only.rules.md`'s frozen-`owner` rule together (that document's own text already names
this exact hook: "account migration, namespace transfer under new governance"). **Recording this
here, rather than treating it as self-evidently fine, is the point of this attack attempt**: a
reader who has not thought it through might expect the "legitimate original owner" case to be
special-cased somehow; it is not, and cannot be, from GitHub identity data alone.

**Attempt 5 — first-publish into a namespace named after someone else, relying on the id rule
alone.** An account whose real numeric id is `999` and whose current username is `mallory` opens a
first-publish PR creating `mods/alice.cooltool/entry.json` with `owner: {provider: "github", id:
999, name_at_registration: "mallory"}` — a namespace named after a different person's identity
entirely, one `mallory` does not hold. **Under a checker built only from the id-equality rule in
"What a first publish binds,"** without "The namespace string itself" section, **this passes**:
the submitter's real id (`999`) trivially equals `new.owner.id` (`999`), which the same PR
supplies, and there is no `old` value yet to contradict it. By this document's own "namespaces are
never reassigned," there is then no recovery path — the real `alice`, whoever she is, can never
register the namespace her own username would otherwise have bound her to. **What the contract
does about it:** "The namespace string itself" above requires the namespace string to equal
(case-insensitively) the PR author's own username at first publish; `mallory` does not equal
`alice`, so this PR is rejected regardless of what `owner` it proposes for itself. This is
namespace capture through the front door of the id-equality rule alone — exactly the attack
ADR-0058 §2, and edge E16 itself, exist to prevent — closed by a check this document did not
originally state explicitly, found in review round 1 (finding B3).

**Attempt 6 — a `page.json`-only PR, hoping the enumeration only ever looks at `entry.json`.** ADR-
0059 §3 requires "the same ownership check (numeric id)" for a PR that touches only
`mods/<ns>.<name>/page.json` — no `entry.json` change at all. An account not authorised for a
namespace opens a PR editing only that namespace's `page.json` (rewriting its description, links,
or screenshots), betting that an enumeration written narrowly against `entry.json` paths finds
nothing to check in this diff and lets it through vacuously. **What the contract does about it:**
"Against what" above enumerates every `mods/<ns>.<name>/entry.json` **and**
`mods/<ns>.<name>/page.json` path in the diff, on identical per-namespace, no-partial-merge terms;
a `page.json`-only PR is not exempt, and is rejected by the same `old.owner.id`/reserved-membership
rule as any other PR touching that namespace. Found in review round 1 (finding B4); before the fix,
this document's enumeration named only `entry.json`, and `grep -c "page.json"
contracts/ownership.md` returned `0`.

**Attempt 7 — put the namespace in two places and let the checker pick.** `mallory` (real id
`999`, username `mallory`) opens a first-publish PR creating `mods/alice.cooltool/entry.json` whose
`id` is `mallory:cooltool` and whose `owner` is `{provider: "github", id: 999,
name_at_registration: "mallory"}`. The bet is that the checker reads the namespace from one source
for one rule and the other source for another. **Under a checker that enumerates by path but
evaluates `R4` against `id`**, it works exactly as designed to: the enumeration finds namespace
`alice`, sees no `old` entry and classifies a first publish; `R4` then reads `mallory` out of `id`,
compares it to the author's username `mallory`, and passes; `R5` compares `999` to `999` and
passes. The PR is accepted and `mods/alice.cooltool/` is squatted permanently, with the directory
and the entry inside it disagreeing about which namespace they even are. **What the contract does
about it:** `I2` makes the directory path the single source — so `R4` compares `alice` against
`mallory` and rejects — and `R2` rejects the disagreement itself, on its own, before any question
of ownership arises. Two independent rules, because the defect was that a checker had a *choice*.
Found in review round 2 (finding B2).

**Attempt 8 — wrap something else in a takedown.** The platform's own account (the only account
`R11` authorises to open a takedown against a namespace it does not own) opens a PR that sets a
version's `status` to `"removed"` with a reason **and**, in the same diff, adds a new version to
that entry, or edits its `owner`, or rewrites its `page.json`. The bet is that a checker
implementing `R11` classifies the PR as "a takedown" from the presence of the status change and
then exempts the *whole PR* from the ordinary rules. **What the contract does about it:** `R11`'s
authorisation covers nothing but the takedown mutation itself, in the shape
`append-only.rules.md` defines; a PR that makes any other change is not a takedown for `R11`'s
purposes and is judged in full by `R3`/`R7`, which reject it because the platform account does not
own that namespace. `append-only.rules.md`'s own frozen-field rule is the second, independent
barrier against the `owner`-editing variant, exactly as it is for Attempt 1.

**On GitHub's documented username-recycling behaviour, quoted verbatim, underpinning attempts 1
and 4 above:**
> "After changing your username, your old username becomes available for anyone else to claim."
> — <https://docs.github.com/en/account-and-profile/concepts/username-changes>, fetched live
> during this task.

> "Your username will be available for anyone to use after 90 days." — the same account's
> username, after **deletion** rather than a voluntary rename —
> <https://docs.github.com/en/account-and-profile/reference/personal-account-reference>, fetched
> live during this task.

**What could not be verified, and is carried as an inline caveat rather than asserted: whether a
numeric account id is ever reused for a different account, including after the original account
is deleted.** ADR-0058 §2's entire defence rests on this never happening ("the numeric GitHub
account id (never reused)"). Neither GitHub docs page fetched above states this explicitly for
numeric ids (only for usernames, which they explicitly say *are* recycled); a general web search
for GitHub's own numeric-id-reuse policy for deleted accounts returned no authoritative GitHub
statement either — only third-party summaries with no cited source. Indirect, and only indirect,
supporting evidence was found and is real: GitHub attributes content from **deleted** accounts to
a fixed placeholder account, `ghost` (numeric id `10137`), rather than leaving the original id
free for reassignment:
```
$ gh api users/ghost --jq '{login,id,type}'
{"id":10137,"login":"ghost","type":"User"}
```
This is consistent with ids not being recycled — a recycling scheme would have no particular need
for a placeholder account — but it is not a documented guarantee, and this document does not
claim it is one. **If GitHub's numeric-id-reuse behaviour is ever found to differ from "never
reused," ADR-0058 §2's own defence needs re-examination, not just this contract** — this is
flagged here because this is the first document written under MANAGER.md guardrail 6b, and the
claim is load-bearing for the entire ownership model, not a peripheral detail.

## What this document does not cover

- **Whether `owner` may ever change after first publish, or the mechanics of that freeze** —
  `contracts/append-only.rules.md` (E4), relied on throughout above, never restated here.
- **Which namespaces are on the reserved list, or why** — `reserved-namespaces.json` and ADR-0119
  itself; this document only states how the identity check behaves once a namespace is known to
  be reserved.
- **Schema shape validation or PR classification** — N3's other two jobs
  (`docs/architecture/depgraph.md`), owned by `contracts/entry.schema.json` and task 007's own
  classifier.
- **An account-migration or namespace-transfer recovery process.** None exists. Attempt 1 and
  Attempt 4 above both end at "rejected, permanently, absent a future ADR" — this document does
  not invent a recovery path that no ADR has decided.
- **Any provider other than GitHub in practice.** Phase 1 only ever sees `provider = "github"`;
  "Provider is part of the comparison" above states the rule in provider-neutral terms because
  ADR-0058 §4 requires the *format* to stay provider-agnostic, not because a second provider
  exists yet.
- **The asset scan on new screenshots in a `page.json` PR** (ADR-0059 §3) — a separate gate from
  this one, deferred to task 040 for the reasons "`page.json` PRs" above states (no archive to scan
  against before task 008 runs). This document's check and that scan are two independent gates a
  screenshot-changing `page.json` PR must both pass.
- **Whether a takedown PR, once authorised to be opened by `R11`, may be merged.** That is
  MANAGER.md §7's written-approval gate, not this document's — `I8` and "Takedown PRs" below.

**A PR touching only `reserved-namespaces.json`, and nothing under `mods/`, passes this check
vacuously** — it touches no path this document enumerates, so there is no namespace for any rule to
be evaluated against, and a green ownership check on such a PR means only "nothing here was mine to
judge." Stated so no reader mistakes the green for an endorsement. The guard is not this document:
ADR-0119 §4 makes the reserved list a human-reviewed surface, and `I4` independently ensures that a
PR editing the list cannot benefit from its own edit in the same diff, because the check reads the
merge-base revision of that file.

## Takedown PRs: who may open one (Ludwig's ruling, 2026-09-07)

A legally-mandated takedown (ADR-0041) sets an existing version's `status` to `"removed"` with a
reason. `contracts/append-only.rules.md` defines the *shape* of that one permitted in-place
mutation and explicitly declines to say who may perform it: *"This document defines the shape of a
legal takedown, not who may perform one."* Review round 1's finding B5 found that the delegation
landed nowhere — the ownership gate is the only other place the identity question could go, and it
did not mention takedowns at all, so the ordinary rule rejected every takedown PR, including one
opened by the platform to remove someone else's infringing entry, which is the entire premise of
ADR-0041's legal-grounds clause. Fix round 1 declared the gap rather than inventing an answer,
and booked it for Ludwig.

**Ludwig ruled on 2026-09-07: the platform's own organisation account may open a takedown PR, and
the human gate sits on the merge, not on the opening.**

**R11 (MUST)** — a PR performing a takedown against a namespace its author does not own is
authorised only when its author is the platform's own identity: the account
`reserved-namespaces.json` records as the reserved namespaces' owner — `provider: "github"`,
`id: 324218296`, the `worldofmodcraft` organisation. Every other author is rejected by `R3` or
`R7` exactly as any other unauthorised PR is, with no takedown carve-out at all. The authorisation
covers **nothing but** the takedown mutation itself, in the shape `append-only.rules.md` defines: a
PR that sets `status` to `"removed"` with its reason *and* makes any other change — a new version,
an edited `owner`, a `page.json` rewrite — is not a takedown for this rule's purposes and is judged
in full by the ordinary rules (Attempt 8 above).

**The mechanism, marked rather than assumed (guardrail 6b).** A GitHub Organization does not itself
authenticate, so which concrete `pulls.user.id` a PR opened on the organisation's behalf actually
carries — a machine account the organisation owns, a GitHub App installation, or a member acting
for it — **was not established in this environment**: no such PR exists here to read, and settling
it by reading a stored credential is forbidden (CLAUDE.md rule 11, MANAGER.md guardrail 10). The
rule above names the *identity*; task 007's implementer must establish which id the platform's own
takedown PRs present and configure `R11` against it. The rule is required as written — that belief
about the mechanism is what is untested, not the rule. **Until it is configured, `R11` authorises
nobody:** the check fails closed and every takedown PR is rejected by `R3`/`R7`, which is exactly
today's state. It never fails the other way, into "accept any PR that says it is a takedown."

**I8 (MUST)** — passing this gate is not authorisation to merge. MANAGER.md §7 requires Ludwig's
explicit **written approval**, given in session and referenced in the PR, before a takedown PR is
merged, and this check neither represents nor replaces it: registry CI cannot verify that a human
decided anything. `R11` decides who may open; §7 decides who may merge. A green ownership check on
a takedown PR means only that the opener was the platform's own account — never that the takedown
was approved.

## Questions

1. **Whether the reserved-namespace membership check (ADR-0119 §3) must be re-evaluated on every
   CI run for a given PR, or only once when the PR is first opened.** A PR can sit open for a long
   time, and organisation membership can change while it does (someone leaves `worldofmodcraft`
   after opening a PR against `test:`, for instance). No ADR read for this task settles whether
   the check is a point-in-time gate or a continuously-reasserted one. **Assumed meanwhile:** the
   check re-runs, and must pass, on every CI evaluation of the PR (e.g. every new commit push and
   every re-run), never cached from the PR's first evaluation — the boring, restartable choice
   (ADR-0103), and consistent with "membership is never frozen" as stated above. **What rests on
   this:** if a future decision instead treats membership as fixed at PR-open time, a person who
   leaves the organisation mid-review would need an explicit re-check step added back in.
2. **The account-migration recovery path Attempt 4 above ends without one.**
   `contracts/append-only.rules.md` already books this same hook ("If a future ADR introduces a
   legitimate way to change `owner` ... that ADR must amend this document"). Recorded here too,
   in matching wording, because this document's own attack attempts are what surfaces the human
   cost of there being no such path today, not merely append-only's field-freeze mechanics.
   **Assumed meanwhile:** no recovery path exists; a namespace whose owning account is
   inaccessible is permanently unpublishable-to, per ADR-0041's "abandoned mods" clause (fork to a
   new namespace). **What rests on this:** nothing yet — this is a known, accepted consequence of
   two already-accepted ADRs, not a defect in this document, and is booked only so it is visible
   next to the attack attempt that demonstrates it rather than left to be rediscovered.

Both of the other questions this document booked — the case-folding rule and who may open a
takedown PR — were answered by Ludwig on 2026-09-07 and are recorded in the next section, so no
future round re-asks them.

## Questions answered by Ludwig, recorded here so no round re-asks them

- **Case-folding the namespace/username comparison** (booked by fix round 1 as this document's
  Question 3). **Answered by Ludwig, 2026-09-07:** approved, and required to be written into this
  contract explicitly rather than left to a checker's implementation — no ADR states the
  normalisation in those words, so the contract must. Written above as `R4`'s case-insensitive
  comparison, with the live verification of its premise beside it.
- **Who may open a legally-mandated takedown PR against a namespace they do not own** (booked by
  fix round 1 as Question 4, raised by review round 1's finding B5). **Answered by Ludwig,
  2026-09-07:** the platform's own organisation account may open one, and MANAGER.md §7's
  written-approval gate governs the merge rather than the opening. Written above as `R11` and `I8`.
