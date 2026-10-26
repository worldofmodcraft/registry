# Task 039: The registry CI workflow — the 007a and 007b checkers wired onto real pull requests

- **Mission:** SITE-V1, deliverable **D1** (the CI half); mission §7 criterion 1 (registry half). **Status:** spec-approved (2026-10-25 night, after spec review rounds 1-2); revised
  (manager, 2026-10-25; replaces the 2026-09-06 placeholder; review rounds 1-2 done). **Security-touching → independent spec review before dispatch.**
- **Merge:** needs **Ludwig's written approval** (CI security check, MANAGER.md §7).
- **Repo:** registry; plus one docs-only change in the platform repo (runbook M9/M10, see File scope).
- **Agent / model:** implementer (ROUTING.md). **Budget:** medium (≤ 3 agent-sessions).
- **Branch / worktree:** `task/039-registry-ci-workflow` / `~/wt/registry-task-039`, cut from registry `origin/main`
  (`4356583` on 2026-10-25, or later; the actual cut SHA is `BASE` in the log and in `039-verify.sh`). Platform docs:
  `task/039-runbook-m9` / `~/wt/task-039-runbook`.
- **Graph:** completes node **N3 `registry-ci`**; realises edge **E16** (`author (forge identity) → N3`, read per
  `ownership.md` I1); E16 also covers the membership call (§4) and the PR-object read (§2 step 1). No new edges. The manager
  does the `INDEX.json` lookup before approval. [unverified] the R11 configuration file is an input to N3, not a new node — the
  manager confirms against `docs/architecture/depgraph.md` before approval.

## What changed since the 2026-09-06 draft
- "Task 007" now means **007a** (shape checkers: `tools/registry/cli.py classify|schema|append-only`, registry PR #10) **and**
  **007b** (ownership: `tools/registry/ownership_cli.py`, PR #12, `70cedca`), both merged. Task **075** (R11: any PR containing
  a removal is a takedown; mixed PRs rejected whoever opened them; PR #18, `4356583`) is merged — resolving the 2026-10-15
  "blocked by the mixed-PR takedown question" note.
- **R11 identity** (Ludwig, 2026-10-17): a dedicated takedown-only account or App that only Ludwig controls; every takedown it
  files still needs his written approval before merge (MANAGER.md §7, `ownership.md` I8). That identity does not exist yet.
  This task ships R11 **unconfigured**: per `ownership.md` R11 ("until it is configured, R11 authorises nobody") every takedown
  PR is rejected. **That is the intended, acceptable state for this task.**
- No `.github/workflows/` exists on registry `main` (checked 2026-10-25); the registry has no `mods/` entries yet.

## Objective
Every pull request to `worldofmodcraft/registry` gets one required status check, **`gate`**, computed **only by code from the
base branch**, never by code from the PR. It is red when any of the four checkers (classify, schema, append-only, ownership)
rejects, and red when any step cannot decide; the author sees why in a PR comment. The verdict uses the PR author's numeric
id from the PR object (`pulls.user.id`) and reads every authority input — the reserved list, existing namespaces' owners, the
R11 identity — at the PR's merge-base. The mission §7 criterion-1 registry rejections (invalid schema, wrong account for an
existing namespace, modified version object) are demonstrated offline against recorded PR shapes. `CONTRIBUTING.md` documents
the manual publish flow with the ADR-0058 §3 namespace-permanence notice.

## Context to load (reading list, 10)
1. `contracts/ownership.md`: I1 (identity source), I4 (merge-base reads), I5/R9 (membership: no redirect following; anything
   but 204/404 rejected closed), R11 + "The mechanism, marked rather than assumed" + I8.
2. `contracts/append-only.rules.md`: T1/T2/T3 and "Coexistence" (fail-closed).
3. `tools/registry/cli.py`; 4. `tools/registry/ownership_cli.py`; 5. `tools/registry/report.py` (exit codes 0/1/2; 2 is
   **not** a rejection).
6. `docs/decisions/0058-publishing-flow.md` §2, §3 (confirmation text verbatim), §5.
7. `docs/decisions/0059-mod-pages-and-page-content.md` §3. 8. `docs/decisions/0119-reserved-namespaces.md` §3-4.
9. Platform `docs/tasks/008b-pipeline-workflow.md`, design 1 and 8 only (the seam: push-triggered pipeline, job split).
10. This file.
ADRs the diff may touch (ADR-0116 layer 2): 0039, 0041, 0058, 0059, 0099, 0119, 0121, 0122.

## Approach (decided here; the implementer raises a Question before deviating)

### 1. Trust model
- **Trigger:** `on: pull_request_target`, `types: [opened, synchronize, reopened, edited]`, branches `[main]`. No other trigger.
  Not `pull_request`: fork PRs get no secrets and a read-only token, so the membership question (R9) could not be asked and no
  comment posted. `pull_request_target` is safe here because GitHub runs the workflow file and the checkout from the **base
  branch**, so a PR cannot change the workflow, the checkers or the config that judge it. **The rule that keeps it safe:
  nothing from the PR head is ever executed, imported, installed or sourced** — the PR's files are data (JSON read by
  base-branch checkers from a separate directory). [unverified U1]
- M1.4's "require approval for first-time contributors" gates `pull_request` fork runs, **not** `pull_request_target`
  [unverified U1]; safety rests on "PR content is data only", not on that setting.
- **Tokens:** M1.4 set the repository default to read and write, so the workflow declares top-level `permissions: {}`, each
  job its minimum, and a `timeout-minutes` on each job. Job **`gate`** (the required check): `contents: read`,
  `pull-requests: read`; its only secrets are the M10 App id and key, used in the token-mint step alone (§4); produces
  `verdict.json` + `comment.md` as an artifact. Job **`comment`** (`needs: gate`, `if: always()`): `pull-requests: write` only,
  **no checkout**, runs no repository code; downloads the artifact and creates-or-updates **one** comment, found by a fixed
  hidden marker (`<!-- registry-ci-gate -->`) **and** author `github-actions[bot]` (none found → create), posting `comment.md`
  as data (`gh api … -F body=@comment.md`, [unverified U8]); with no artifact it posts a fixed "registry CI could not decide;
  see the run log". Its result never changes `gate`.
- **Checkout:** `actions/checkout` pinned to a 40-hex SHA, `fetch-depth: 0`, `persist-credentials: false`, **no `ref:`**. The PR
  number (`^[0-9]+$`) and head sha (40-hex) are validated in the step's shell, both passed via `env:`, **before** the PR head is
  fetched as objects only (`git fetch origin +refs/pull/<N>/head:refs/wom/pr-head`); the fetched SHA must equal the event's
  `pull_request.head.sha` or the run exits 2. [unverified U5]
- **Injection rule (outputs and environment):** no `run:` block contains `${{` at all; event, API and step values reach scripts
  only through `env:` or files. Anything written to `$GITHUB_OUTPUT` matches a strict form: class ∈ the classify enum,
  membership status `^[0-9]{3}$|none`, PR number `^[0-9]+$`, shas 40-hex, `present` ∈ {`true`,`false`}, `org` and `login`
  matching `^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$` — never other PR free text (title, body, branch, path).
  Writers of `$GITHUB_OUTPUT` are exactly four steps (R2): the presence step (`present=`), the `--classify-only` pre-pass
  (`class=`, `org=`, `login=`, via its validated `OUT/outputs`), the membership step (`status=`), and the `ci_gate.py` step
  (`OUT/outputs`, one validated `key=value` per line). The composer refuses (exit 2) to write any line not in a strict form. `$GITHUB_ENV` and `$GITHUB_PATH` are never written. The `comment` job takes `gate`
  outputs through `env:`, never `${{ needs.gate.outputs.* }}` inside a `run:`.
- **`gate` cannot go green by accident:** the `ci_gate.py` step has no `if:`; its `run:` has no pipe (or the step sets
  `shell: bash` with `pipefail`); the steps after it are `actions/upload-artifact` only, so nothing later in `gate` can turn the
  job green. The job result is the composer's exit status.

### 2. The composer: `tools/registry/ci_gate.py` (new, offline, stdlib only)
`python3 -I tools/registry/ci_gate.py --repo DIR --event EVENT.json --pr PR.json --membership-status (^[0-9]{3}$|none) --out DIR`
→ exit 0 accepted / 1 rejected / 2 could not decide; writes `OUT/verdict.json`, `OUT/comment.md`, `OUT/class`, `OUT/outputs`.
**No `--tools-dir` flag:** the checker directory is a parameter of the library entry point that tests call directly (stub
checkers); the CLI always uses the base checkout's `tools/registry/`. `main` is wrapped: any exception, including
`subprocess.TimeoutExpired`, exits 2 (never Python's default traceback exit 1, which would read as a rejection).
1. **Identity (I1):** author = `PR.json.user.id` / `.user.login`; `PR.json` is the `GET /repos/{repo}/pulls/{n}` response the
   workflow fetched with the read-only token. Exit 2 unless event and API object agree on number, `user.id`, `head.sha`,
   `base.ref == "main"` and base repository. Never reads `GITHUB_ACTOR(_ID)`, commit authors or trailers.
2. **Merge-base:** `git merge-base --all HEAD <head.sha>` (HEAD = the checked-out base-branch tip); exactly one result, else exit
   2. The API `base.sha` must be an ancestor of HEAD (`git merge-base --is-ancestor`), else exit 2.
3. **Changed paths:** `git diff --no-renames --name-only -z <mb> <head>` (a rename is a deletion plus a creation, per 007a). A
   list that does not parse (no trailing NUL, an empty entry) → exit 2. **Empty diff → exit 1:** the composer builds the
   classify-shaped rejection ("empty diff") itself and runs none of the other three checkers.
4. **Routing (no workflow path filter):** an *infra PR* is a non-empty diff in which **no path equals `mods` or starts with
   `mods/`**: exit 0, comment "not a registry content PR; registry CI does not judge it" listing the touched paths **inside the same fence rule as §2.9** (a fence longer than any backtick run; capped at 50
   paths and 4 KiB, with a count of the rest), saying
   **green does not mean safe** and that this relies on human review before merge (M9, MANAGER.md §7). Every other PR —
   including any mix of `mods/` with other paths — goes through the full gate (classify rejects mixes as `other`). Reasons: a
   `paths:` filter would leave the required check pending on skipped PRs [unverified U3] (so ADR-0099's path-filtered CI does
   not apply: this check must always report); 007a rejects every path outside `mods/` by design and its Questions(A) left
   routing to this task.
5. **Materialisation (no checkout of PR trees):** via `git ls-tree -r -z` + `git cat-file blob`, write **old-root** = the
   merge-base tree's `mods/`, `reserved-namespaces.json` and `config/r11-identity.json`, and **new-root** = the head tree's
   `mods/`, into fresh `mkdtemp` dirs (0700). Mode 100644/100755 → regular file; 120000 → a symlink with its literal target,
   written **after** all regular files, never followed (the checkers reject it as `symlink`); any other mode (gitlink 160000, …)
   on a changed path → rejection (fail closed). Files are created with `O_EXCL` and never through a symlink. Any of these →
   **exit 2**, nothing further written: a tree path with a `.`, `..`, empty or `.git` component or a NUL; a duplicate path or a
   directory/file conflict (blob or symlink `x` with tree `x/…`); a realpath outside the temp root; a blob over the byte cap or
   more entries than the entry cap (caps chosen by the implementer, recorded in the log, tested); any `git` call over its
   timeout.
6. **Run all four checkers, always (except on an empty diff), from the base checkout** (`sys.executable -I tools/registry/…`;
   argv lists; a timeout on each; every checker that takes PATH arguments gets them as **argv after `--`**, never via
   `--paths-file`): `cli.py classify --reserved-file OLD/reserved-namespaces.json -- PATH...`; `cli.py schema --root NEW`;
   `cli.py append-only --old-root OLD --new-root NEW`; `ownership_cli.py --author-provider github --author-id ID --author-login
   LOGIN --old-root OLD --new-root NEW --reserved-file OLD/reserved-namespaces.json [--membership-status N] [--r11-identity
   github:ID] -- PATH...`. A changed path named like a flag (`--membership-status=204`) is thus an unrecognised path, never a
   checker option. All four run even after a rejection, so the author gets the full log. Every subprocess (git included) runs
   with a scrubbed env built from literals: no `GITHUB_*`, `PATH=/usr/bin:/bin` [unverified U7], `GIT_CONFIG_NOSYSTEM=1`,
   `GIT_CONFIG_GLOBAL=/dev/null`.
7. **Composition (fail closed):** accepted iff all four exit 0 **and** each JSON verdict says `accepted`. A checker exit 2, any
   other exit code, unparsable JSON, a timeout, or an exit code disagreeing with its verdict → composed exit 2, reported as
   "could not decide (not a rejection)", never green. **Precedence: if any checker is exit 2 the composed result is 2, even when
   another checker rejects.** The ownership verdict's `merge_signal: false` (I8) is restated: green means "the checks pass",
   never "approved".
8. **R11 identity:** read from `OLD/config/r11-identity.json` (merge-base, I4), never from the PR head or an env var. File:
   `{"schema_version": "1.0.0", "r11_identity": null}` or `{"provider": "github", "id": <int>}` in that slot. `null` or absent
   → no `--r11-identity` (R11 authorises nobody); malformed → exit 2. **This task commits it as `null` and forbids setting it.**
9. **Comment (`comment.md`):**
   - Rejection or exit 2: the full checker output inside a code fence longer than any backtick run in it (it contains
     PR-controlled strings), truncated below GitHub's limit [unverified U12] with a link to the run log.
   - The ADR-0058 §3 notice appears **only on the accepted path**, for a PR that first publishes a non-reserved namespace,
     verbatim: *"This creates the namespace `X:` permanently bound to your GitHub account (id N). Namespaces are never
     reassigned."* (X = the namespace from the path that passed R1, N = `pulls.user.id`). A rejected or undecided PR never
     carries it. For a reserved-namespace first publish it says instead that the namespace is bound to the organisation in the
     merge-base reserved list (ADR-0119).
   - Infra PRs: as step 4. Page-only PRs (`OUT/class` = `page-only`): "page.json-only: no build runs", and that the screenshot
     scan (ADR-0059 §3, task 040) is not yet running.
10. **Process discipline:** `subprocess` only with argv[0] `git` or `sys.executable`, no `shell=True`; no network modules; no
    `os.environ`/`getenv` read; no `eval`/`exec`/`__import__`.

### 3. page.json-only PRs skip the build
008b's pipeline triggers on `push` to `main` with `paths: ['mods/*/entry.json']` (008b design 1), so a page-only merge starts no
build without wiring here. This task exposes the class (`OUT/class`, job output, comment) and tests it; it does not edit 008b.
**Merge stays a human action in v1** (C8); this workflow never merges (008b design 4 has the App merging write-back PRs, which
is a different workflow). The screenshot scan ADR-0059 §3 requires is **task 040** (extends `ci_gate.py`); until it exists the
page-only comment says so.

### 4. Membership oracle (R9/I5)
- **Pre-pass:** `ci_gate.py --classify-only --repo DIR --event EVENT.json --pr PR.json --out DIR` (no `--membership-status`)
  runs steps 1-5 and classify only, and emits `class=`, and for class `reserved-namespace` `org=` and `login=` in strict form
  (exit 2 on anything else). The membership question is asked only when `class=reserved-namespace`.
- The org is the single organisation named by every merge-base reserved entry; more than one → exit 2. The step validates the
  login against `^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$` (passed via `env:`).
- **Token mint (choice C10, decided):** a step using the official `actions/create-github-app-token` pinned to a 40-hex SHA, with
  the M10 App id and private key from secrets, scoped to the org, Members:read only [unverified U14]; it runs only when the
  secret is non-empty — **choice C18:** a preceding **presence step** receives the key only via its `env:` and writes only
  `present=true|false` to `$GITHUB_OUTPUT` (never the value); the mint step has `if: steps.<presence>.outputs.present ==
  'true'`; absent secret → mint skipped → status `none`. AC7's secret rule: `secrets.` appears in exactly these two steps (presence
  and mint); the minted token appears only in the membership step's `env:`; the presence step's `run:` prints nothing derived
  from the secret. The minted token is passed via `env:` to the membership step only.
- **Membership step:** `GET /orgs/{org}/members/{login}` with `curl`; argv has no short-flag cluster containing `L`, no
  `--location*`, no `--proto-redir`, and does have `-o /dev/null`, `-w '%{http_code}'`, `--max-time`. It checks the result
  against `^[0-9]{3}$`; empty or anything else (curl failure, timeout) → `none`; an empty minted token (mint skipped) →
  `none` without calling curl. It writes only `status=<value>` to
  `$GITHUB_OUTPUT`.
- **Credential:** a separate org App with only *Organization → Members: read* (C5), booked as runbook **M10**.
  **`PIPELINE_APP_PRIVATE_KEY` is never used here.** Until M10, no secret → status `none` → every reserved-namespace PR is
  rejected by R9: accepted for this merge; must be lifted before task 010 (`test:hello-world`). [unverified U6]

### 5. Required status check (Ludwig's manual step)
Branch protection changes only by Ludwig, by hand: runbook **M9** (platform repo): registry → Settings → Branches → rule for
`main` → *Require status checks to pass* → select `gate` → *Require branches to be up to date before merging* → Save, plus what
he should see. Only possible **after** the first live run (the check appears in the selector once it has run) [unverified U2].
Org on GitHub Free, repo public [unverified U10; the M9 screen confirms]. Existing protection unchanged; infra PRs stay
mergeable (infra route is green).

### 6. CONTRIBUTING.md
Manual-PR publish flow: fork, `mods/<ns>.<name>/entry.json` (+ `page.json`), namespace = your username (R4), owner = your numeric
id (R5/R6), append-only versions, page-only edits, owners cannot remove a published version (ADR-0122, R11); the ADR-0058 §3
notice verbatim. README's "CONTRIBUTING.md will document…" line updated.

## Acceptance criteria — all run by `docs/tasks/039-verify.sh`; the log pastes its output
**Permitted demonstration mechanism:** offline simulation only — throwaway git repos in `mktemp` dirs (base commit = fixture
registry state, head commit = fixture PR) plus **recorded event and PR-object payloads** committed under
`tests/registry/fixtures/ci/`, trimmed to the documented shapes [unverified U4]; everything under `env -i PATH="$PATH"
HOME="$(mktemp -d)" LANG=C.UTF-8`. **No credential of any kind, no `gh` call, no `curl`, no `act`, no live PR.**
1. **§7 criterion 1, registry trio — each exit 1 with the named rule in `comment.md`:** (a) `entry.json` with `owner.id` as a
   string (schema); (b) a new version on a namespace owned by `github:100200300`, opened by `github:900800700` whose **login
   equals** the owner's `name_at_registration` (R3 — ids, not usernames); (c) an existing version's `commit` changed by its own
   owner (append-only rule 1).
2a. **Hostile strings (R3):** an infra PR touching files named `@org/team`, one containing a backtick and one with a newline →
   exit 0, the names appear only inside the fence, the comment stays below the limit; `OUT/outputs` built from hostile login,
   namespace and path strings contains only strict-form lines, or the run exits 2. The comment job lists comments with
   `--paginate` when finding its marker.
2. **Positive controls (exit 0):** first publish of `alice:demo` by `alice` (comment contains the ADR-0058 §3 sentence with
   `alice:` and alice's id, byte-exact; the same sentence is **absent** from every rejected and exit-2 fixture); the owner adding
   a version; the owner's page-only PR (class `page-only`, "no build runs", names the not-yet-running screenshot scan); an infra
   PR touching only `README.md` (comment lists `README.md` and says green does not mean safe). A suite that rejects everything
   fails this criterion.
3. **Fail-closed matrix (each exit 2, never 0 or 1, never reported as a plain rejection):** event/API disagree on `user.id`; on
   `head.sha`; `PR.json` missing or unparsable; no merge-base; two merge-bases; API `base.sha` not an ancestor of base HEAD; an
   unparsable `-z` path list; a checker exiting 2; a stub checker exiting 3 and one printing non-JSON (stubs via the library's
   checker-directory parameter; asserted absent from the CLI and the workflow); a checker over its timeout
   (`subprocess.TimeoutExpired`); any other injected exception in `main`; **precedence:** one checker exits 2 while another
   rejects → composed 2; malformed `config/r11-identity.json`; a reserved list naming two organisations. **Empty diff → exit 1**
   (a rejection, not 2): `comment.md` carries the classify rejection and recording stubs show the other three checkers never ran.
4. **Identity source:** with `GITHUB_ACTOR`/`GITHUB_ACTOR_ID` set to the owner and the head commit's author/committer set to the
   owner, a stranger's PR is still rejected R3.
5. **Merge-base reads:** a PR removing `test` from `reserved-namespaces.json` and adding `mods/test.x/entry.json` is still judged
   reserved (and rejected); a takedown-only PR by any author with R11 unconfigured → rejected "R11 is not configured"; with a
   **test-only** merge-base config naming `github:555`, a takedown-only PR by 555 passes ownership, the same PR plus another
   change is rejected (R11, 075); a PR setting the config to its own author in the same diff gains nothing. Membership:
   `none`, `302`, `500` → R9 rejection; `204` passes R7; `404` → R7 rejection.
6. **Tree handling and argv safety:** an `entry.json` rename → rejected as deletion; a symlinked `entry.json` → `symlink`; a
   gitlink under `mods/` → rejected; a path containing a newline handled via `-z` without crashing. **Materialisation — each
   exit 2, and a before/after listing of a sentinel parent dir shows nothing written outside the temp dir:** crafted trees
   (built with `git hash-object --literally` / `git mktree`) with symlink `x` plus tree `x`; blob `x` plus tree `x`; a `..`, a
   `.`, an empty and a `.git` component; a duplicate entry; a symlink whose target escapes the root; a blob over the byte cap;
   more entries than the cap. **Argv injection:** each of the files `--membership-status=204`, `--root=x`,
   `--paths-file=README.md`, `-h`, added to an otherwise valid reserved-namespace publish, gives exit 1 (unrecognised path,
   class `other`) with the R9 rejection still reported at status `none`/`302` — no checker flag overridden; the same file alone
   in a PR takes the infra route (exit 0, no checker invoked).
7. **Workflow structure — a live guard on HEAD.** PyYAML parses `.github/workflows/registry-ci.yml` (missing PyYAML → exit 2,
   never skip; PyYAML reads the key `on` as boolean `True`, the test handles both). Asserts:
   - triggers exactly `pull_request_target` with the four types, no `paths`/`paths-ignore`; top-level `permissions: {}`; `gate`
     exactly `contents: read, pull-requests: read`; `comment` exactly `pull-requests: write`, no `actions/checkout`, no step
     running repository code; `timeout-minutes` on every job.
   - **no `run:` block contains `${{`** (values arrive via `env:`); `$GITHUB_ENV` and `$GITHUB_PATH` appear nowhere;
     `$GITHUB_OUTPUT` appears only in the four writer steps of §1 (presence, pre-pass, membership, `ci_gate.py`).
   - `secrets.` appears in exactly two steps: the presence step (`env:` only; writes only `present=`) and the token-mint step
     (`actions/create-github-app-token`, pinned, with its `if:`); mutations: `secrets.` in a third step → red; the minted
     token appears only in the membership step's `env:`; `PIPELINE_APP_PRIVATE_KEY` and `MINISIGN_SECRET_KEY` nowhere.
   - every `uses:` pinned to 40 hex; checkout `persist-credentials: false` and no `ref:`.
   - membership `curl` argv, tokenised: no short-flag cluster containing `L`, no `--location*`, no `--proto-redir`; has
     `-o /dev/null`, `-w '%{http_code}'`, `--max-time`; the step maps empty/non-3-digit to `none`.
   - in `gate`: no `continue-on-error`, `|| true` or `set +e`; the `ci_gate.py` step has no `if:`, its `run:` has no pipe (or
     `shell: bash` with `pipefail`), and every later step is `actions/upload-artifact`.
   **Fails on zero matches** (must find `gate`, the mint, membership and `ci_gate.py` steps). **Mutations**, each red then
   restored byte-identically: add a `pull_request` trigger; `gate` permissions `write-all`; checkout `ref: ${{
   github.event.pull_request.head.sha }}`; `${{ github.event.pull_request.title }}` in a `run:`; `${{ needs.gate.outputs.x }}` in
   a `run:`; `-L`; `-sSL`; drop `-o /dev/null`; `continue-on-error: true`; an `if:` on the `ci_gate.py` step; a pipe in its
   `run:`; `secrets.` in the membership step; a `$GITHUB_ENV` write; drop a `timeout-minutes`; unpin one `uses:`; a `paths:`
   filter. Positive control: the unmodified file passes.
8. **No network, no environment, no shell in the composer:** an AST scan of `ci_gate.py` finds no import of `socket`, `urllib`,
   `http`, `ssl`, `requests`; no `os.environ`/`getenv`, `shell=True`, `os.system`, `os.popen`, `eval`, `exec`, `__import__`;
   every `subprocess` argv[0] is literal `"git"` or `sys.executable`; no `--tools-dir` option. Mutations, each red:
   `import urllib.request`; `os.environ["X"]`; `shell=True`.
9. **Production R11 unconfigured:** `config/r11-identity.json` at `FINAL` parses with `"r11_identity": null`.
10. **Docs:** `CONTRIBUTING.md` contains the ADR-0058 §3 sentence verbatim (placeholders explained) and "never reassigned";
    `README.md` no longer says CONTRIBUTING "will" exist.
11. **Own-change checks pinned (REVIEW-CHECKLIST item 12):** `BASE` and `FINAL` recorded in the script; `git diff --name-only
    BASE FINAL` inside the file scope; the red-first commit (tests for AC1-AC6 + AC8, before `ci_gate.py`) is an ancestor of
    the implementation commit and its tests fail at that commit (in a `mktemp` worktree). Control: `FINAL=BASE` → exit 1.
12. **Live guards on HEAD:** the full registry test suite green; every closed verify script on the closed list (070/075 list +
    075) green, one at a time from the repo root; the script passes in a **fresh clone** from GitHub (REVIEW-CHECKLIST item 8).

**Post-merge live checks (observed by Ludwig/manager; not merge-gating; logged):** L1 an infra PR shows `gate` green and the run
log prints `python3 --version` and the non-secret PR fields (closes U2, U4, U5, U7); L2 Ludwig does M9; L3 an invalid-schema PR
from `womcraft` in namespace `womcraft` is red with the comment, then closed unmerged; L4 M9 blocks merging L3. R3 and
append-only live demos need entries on `main` and a second account (M6) → the mission §7 walkthrough.

## File scope
Registry: `.github/workflows/registry-ci.yml` (new), `tools/registry/ci_gate.py` (new), `config/r11-identity.json` (new,
`null`), `CONTRIBUTING.md` (new, docs), `README.md` (one paragraph), `tests/registry/test_ci_gate.py`,
`tests/registry/test_ci_workflow.py`, `tests/registry/fixtures/ci/**`, `docs/tasks/039-registry-ci-workflow.md` (carried with
its log), `docs/tasks/039-verify.sh`.
Platform (`task/039-runbook-m9`, docs only; the reviewer reads it): `docs/runbooks/site-v1-manual-steps.md` — new **M9**
(required check), **M10** (membership-read App), and a ⏸ note on the R11 takedown-only identity awaiting its own task.

## Size (SPEC-CHECKLIST 5b)
Source files 3 (workflow, composer, config); reading list 10. **Changed lines estimated 400-500 (over 300; likely above 400
after the materialisation guards, caps, precedence and wrapped `main`).** Justification: the risk is the seam between the YAML
and the composer (which input comes from the event, the API, the merge-base; which job holds which token). Split, the
composer's input contract would be reviewed without its only caller and the workflow without the code it trusts —
`pull_request_target` defects live in that gap; AC7 and AC1-AC6 mean something only together (C7). **C19: implemented in two sessions on one branch, one PR** — session 1 the composer (`ci_gate.py`, config, tests, AC1-AC6,
AC8-AC9), session 2 the workflow, AC7, docs, runbook and AC10-AC12. **Diff over 450 lines → stop
and report.** Split fallback if it fires: **039a** = `ci_gate.py` + `config/r11-identity.json` + `test_ci_gate.py` + fixtures
(AC1-AC6, AC8, AC9, AC11-AC12 for its part); **039b** = workflow + `test_ci_workflow.py` (AC7) + CONTRIBUTING/README (AC10) +
runbook M9/M10, reviewed against the merged 039a composer.

## Forbidden (beyond MANAGER.md §3.7)
- Any trigger but `pull_request_target`; any `paths` filter; `workflow_run`; auto-merge of any PR by this workflow.
- Checking out, executing, importing, installing or sourcing anything from the PR head; `actions/checkout` with a head `ref`.
- `${{` anywhere inside a `run:` (including `github.event.*`, `github.head_ref`, `needs.*.outputs.*`); writing `$GITHUB_ENV` or
  `$GITHUB_PATH`; PR free text in `$GITHUB_OUTPUT`.
- Identity from anything but the API PR object cross-checked with the event (I1); `GITHUB_ACTOR(_ID)`, commit metadata.
- Reading the reserved list, owners or R11 config from the PR head or base tip instead of the merge-base (I4).
- `r11_identity` other than `null` in a committed file; any `pipeline_app_id` carve-out (008b's amendment).
- `continue-on-error`, `|| true`, exit 2 treated as green, skipping later checkers after an earlier rejection (the empty-diff
  case excepted, §2 step 3).
- Passing PR paths to a checker other than as argv after `--` (`--paths-file` included); a `--tools-dir` CLI flag; `shell=True`,
  `os.system`/`popen`, `eval`/`exec`/`__import__`, `os.environ`/`getenv` in the composer.
- Following redirects in the membership call (`-L`, `--location*`, `--proto-redir`), or reading 302 as 404 (I5/R9); `secrets.`
  anywhere but the presence step and the token-mint step (C18).
- `PIPELINE_APP_PRIVATE_KEY` or `MINISIGN_SECRET_KEY` in this workflow.
- Editing `tools/registry/{cli,ownership_cli,ownership,append_only,schema,classify,report}.py` or any `contracts/*` — if one
  seems needed, stop and report (a contract task with Ludwig's approval).
- **Any credential use by the implementer:** no `gh auth`, `gh api`, `gh secret`, `curl` with a token, reading or listing
  secrets, `act`, live PRs, branch-protection changes (CLAUDE.md rule 11). Unauthenticated public reads are allowed (e.g.
  `git ls-remote https://github.com/actions/checkout` to pin SHAs; docs.github.com). `gh pr create` for this task's own PRs is
  allowed (the session's configured identity; no token read).

## Dependencies / sequencing
- Done: 007a (PR #10), 007b (PR #12, `70cedca`), 075 (PR #18, `4356583`), M1, M5.
- **Before 008b goes live:** its write-back PRs must pass `gate` (T1/T3 stay rejected until 008b amends `ownership.md`).
- **Then 040** (extends `ci_gate.py`; sequenced after this task). **Before 010 / criterion 2:** M10 and M6. **M10 is sequenced
  after live checks L1 and L3 pass** (no secret exists until then; the gate is proven first at status `none`).
- **Later task, not this one:** create the takedown-only identity (Ludwig, runbook), amend `ownership.md` R11 to name it (U11 —
  R11 currently names the org id `324218296`), set `config/r11-identity.json`; merge needs Ludwig.

## Assumptions marked [unverified], with how each gets verified
U1 `pull_request_target` runs the default-branch workflow with secrets for fork PRs and is not gated by the first-time
contributor approval — docs.github.com "Events that trigger workflows: pull_request_target" and "Approving workflow runs from
public forks". U2 its check runs appear on the PR head and are selectable as required as `gate` — L1 and the M9 screen. U3 a
path-filtered skipped workflow leaves a required check pending — docs "Handling skipped but required checks". U4 payload
field names — webhook/REST docs and L1. U5 anonymous `git fetch` of `refs/pull/N/head` on a public repo — L1. U6 an App token
with org Members:read answers 204/404 (no 302) for private members — after M10, once, about `womcraft` (status only). U7 runner
has Python ≥ 3.10 and git — L1. U8 `gh api -F body=@file` reads the file — `gh api --help` locally. U9 PyYAML present where the
verify script runs; missing → exit 2. U10 required checks available on Free for a public repo — the M9 screen. U11 R11 names the
org id while Ludwig chose a dedicated account — a follow-up `ownership.md` amendment task. U12 PR comment limit (≈65 536) —
docs, and a truncation test. U13 a step-level `if:` cannot read the `secrets` context (docs "Contexts: context availability") — resolved by C18 (presence
step); the implementer verifies that docs page and that `steps.<id>.outputs` is readable in a step `if:`. U14 `actions/create-github-app-token` input names (app id, private key, owner,
permission scope) — its README at the pinned SHA.

---
# Task 039 log
- 2026-09-06 manager: placeholder draft (scope only).
- 2026-10-15 session 9: 007 split into 007a/007b; depends on both.
- 2026-10-15 session 10: gated on the mixed-PR takedown answer — resolved by task 075 (merged `4356583`).
- 2026-10-25 manager (session 11 night): spec revised (draft by a Plan agent, gated by the manager): trust model, identity
  source, merge-base reads, R11 unconfigured, M9/M10 runbook steps, offline §7 criterion-1 demonstration, size justification.
  Open questions decided under Ludwig's standing ★ approval as C4-C8 (mission log). Awaiting independent spec review.
- 2026-10-25 manager: spec review round 1 FAIL (B1-B5 blocking, N1-N6); all folded in; C10 decided; round 2 pending.
- 2026-10-25 manager: spec review round 2 FAIL narrowly (R1-R3 text contradictions/regression); fixed by the manager (secret rule = presence + mint steps; all $GITHUB_OUTPUT writers enumerated with strict forms incl. present/org/login; pre-pass interface; empty token → none; infra-comment paths fenced and capped; AC2a hostile strings). Reviewer: 'the manager can accept without a full third review'. C19 decided. **spec-approved** (manager, 2026-10-25 night).
- 2026-10-25 implementer (session 1 of 2, C19), start: worktree `~/wt/registry-task-039`, branch `task/039-registry-ci-workflow`,
  **BASE = `4356583fb2360592a680f40bee396f9f23df35a4`** (registry `origin/main` at fetch time). Scope this session: composer
  `tools/registry/ci_gate.py` (+ `--classify-only`), `config/r11-identity.json` (null), `tests/registry/test_ci_gate.py`,
  `tests/registry/fixtures/ci/**`; AC1-AC6, AC2a, AC8, AC9. Session 2: workflow, AC7, CONTRIBUTING/README, runbook, verify script, AC10-AC12.
- Red commit: tests + fixtures + this spec/log committed before `ci_gate.py` exists; 77 tests, all 77 fail/error at that commit
  (checked: two argument-error tests would have passed spuriously on Python's "can't open file" exit 2, so they now also
  assert the composer's own stderr text; every exit-code assertion also requires `verdict.json`, which only the composer writes).
- 2026-10-25 implementer (session 1), STOPPED at the size tripwire. Red commit `88c97ac` (77 tests, all failing). First draft of
  `tools/registry/ci_gate.py` is **418 lines** (369 non-blank; plus `config/r11-identity.json`, 1 line): over the 300-line
  per-session limit, so I stopped and reported instead of golfing it down. State, not green: 67 of 77 tests pass, 10 fail:
  AC9 (config file only just added), `test_bad_path_components` (git `ls-tree` itself exits 128 on `..`/empty/`.` names, so the
  guard never sees them: either the composer must treat that git failure as the answer or the test fragment changes),
  `res.cls` has a trailing newline in 3 tests (test-side fix: strip), `test_emits_class_org_and_login_only` (`class=entry` came
  back `other` for a plain add-version PR in the pre-pass: pre-pass bug to find), and 4 AC2 positive controls plus
  `test_hostile_namespace_and_path_strings_never_reach_outputs` (not yet diagnosed; likely one shared cause in the accepted
  path). AC8 scan (4 tests), AC3 matrix (almost all), AC4, AC5, AC6 symlink/gitlink/rename/argv-injection already pass.
  Caps chosen: blob 1 MiB, tree total 32 MiB, 5000 entries per tree and per diff, 256 KiB of path text; git timeout 30 s,
  checker timeout 120 s. Notes for session 2: comment.md line 1 is `<!-- registry-ci-gate -->`; OUT/outputs keys are exactly
  `result route class pr head_sha merge_base` (full gate) and `class [org login]` (pre-pass), nothing on exit 2 except
  `result=undecided`; the comment job must still list comments with `--paginate`; AC3 "absent from the workflow" for
  `--tools-dir` is still to be asserted in test_ci_workflow.py; blobs are read one `git cat-file` per file (fine for v1,
  `--batch` if the registry grows to thousands). Question for the manager: the total estimate (400-500 lines) is already
  exceeded by the composer alone; continue as C19 (one PR), or fire the 039a/039b split fallback?
- 2026-10-25 manager: session 1 hit the size tripwire (composer 418 lines, 369 non-blank). **Split fallback applied (C23):**
  **039a** = this branch's composer work: `ci_gate.py`, `config/r11-identity.json`, `test_ci_gate.py`, fixtures; criteria AC1-AC6
  (incl. AC2a), AC8, AC9, AC11 (own-change pins), AC12 (live guards, fresh clone); its own `docs/tasks/039a-verify.sh`; its own
  PR (merge needs Ludwig). Source size over the 300 soft cap is accepted with this justification: the composer is one cohesive
  trust-boundary unit; splitting it further would review its parts without each other. **039b** (later task, after 039a merges)
  = the workflow YAML, AC7, AC10, CONTRIBUTING/README, the platform runbook M9/M10/M11 note, `039b-verify.sh`. Rule for the
  failing path-component test: any git failure on a crafted tree (e.g. `ls-tree` exit 128) maps to composer exit 2; the test
  asserts exit 2 and nothing written outside the temp root, not which guard fired.
- 2026-10-26 implementer (039a, C23): **fixed.** BASE `4356583`, RED `88c97ac` (77 tests, all failing), FINAL `09145b4` (composer green:
  77/77), verify script `docs/tasks/039a-verify.sh` (`1754439`, waits for other verify scripts, up to six hours). Fixes since the
  WIP: the pre-pass `other`-for-`entry` bug was the checkers writing `__pycache__` into the test repo (python `-I` ignores
  `PYTHONDONTWRITEBYTECODE`; now `-B`), the 3 `res.cls` failures were a test-side trailing newline, the path-component test now
  asserts exit 2 only (git refuses `''`/`.`-named trees itself, `..` and `.git` hit the composer guard). Composer source:
  417 lines (`tools/registry/ci_gate.py`) + 1 line config; accepted over the 300 soft cap by C23.
  `039a-verify.sh` run on HEAD (`1754439`) with ajv from another worktree: AC11 all PASS incl. control (FINAL=BASE makes 3 checks
  fail); AC1 3/3, AC2 7/7, AC2a 8/8, AC3 25/25, AC4 2/2, AC5 6/6, AC6 17/17, pre-pass 4/4, AC8 4/4 + independent scan, AC9 1/1 + config;
  AC12: full `tests/registry` suite 350 tests green; 006 007a 007b 008a 032 034 057 062 064 066 067 069 070 071 exit 0; **075-verify.sh
  exits 1**: its check "base..HEAD touches only the task's declared file scope" fails for ANY later branch
  (`out-of-scope files in base..HEAD: config/r11-identity.json`), the same HEAD-relative own-change defect that task 070 re-pinned for
  the older scripts. Not mine to edit (closed script): needs a 071-pattern re-pin task for 075 (it will also redden task 065's branch).
  Not done: the fresh-clone-from-GitHub run of the whole script (another agent's verify scripts kept the machine busy for hours;
  the one real failure above would repeat). Queue: re-pin 075 first, then the fresh-clone run, then Ludwig's merge approval.
  Session-2 notes (039b) as above: `comment.md` line 1 is the marker; `OUT/outputs` keys; `--paginate`; assert no `--tools-dir` in the workflow.
- 2026-10-26 implementer (039a, security review LOW fix): `run_gate` wrote verdict.json before comment.md/outputs, so a later write
  failure (ENOSPC) exited 2 while an "accepted" verdict sat on disk. Red `3ef53be` (new test: a directory where comment.md/outputs/class
  should go), fix `ceb0458` = new FINAL (verdict.json now written last; any write failure clears OUT/* and leaves only an "undecided"
  verdict, exit 2). Composer now 423 lines; test_ci_gate.py 78 tests, full registry suite 351 green (foreground, no closed scripts run).
  Booked for 039b: (1) bot logins such as `dependabot[bot]` fail the login regex, so the composer exits 2 (fail-closed, accepted);
  (2) runbook M9 must keep "Require branches to be up to date before merging"; (3) the comment's "see the run log" has no link, the
  composer must not read the environment, so 039b's workflow may add the link outside the composer. **Merge gate:** do not merge until
  task 084 has re-pinned 075-verify.sh and the full 039a-verify.sh has passed in a fresh clone.
- 2026-10-26 implementer (039a, REVIEW-CHECKLIST item 12 fix): `039a-verify.sh` own-change checks read BASE..HEAD, which a merge with
  registry main reddens (`contracts/append-only.rules.md` from other tasks). Now pinned: `TIP=999b2b7` (last branch commit before the
  pin commit `d4d726d`, which changes only the script); checks are BASE..TIP inside scope, FINAL ancestor of TIP, and an empty
  `git diff FINAL TIP -- tools/registry config tests/registry contracts` (merged bytes = verified bytes); no HEAD/origin/main in any
  own-change check. Shown in a temp clone of GitHub with the branch merged onto origin/main (`208c6d1`): the AC11 block alone (script cut before
  the AC1 section, no skip added to the real path) -> "0 failed", control FINAL=BASE fails 4 checks; widening TIP to the merge HEAD -> red
  ("out-of-scope files in BASE..TIP: contracts/append-only.rules.md", "code files differ between FINAL and TIP"). Full script not run.
