# Task 066: A pinned, reproducible ajv 8 for the registry's verify scripts

- **Mission:** SITE-V1 (verification reproducibility) — **Status:** spec-approved (manager, solo gate, 2026-10-15, session 10;
  small task, not security-touching). Ludwig chose option A on 2026-10-15 (session 9).
- **Repo:** registry. **Agent / model:** implementer / sonnet. **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/066-registry-dev-tools-ajv` / `~/wt/registry-task-066`, cut from registry `origin/main`
- **Graph:** no component node or contract edge; verification tooling only. No new edges.

## Objective
`docs/tasks/057-verify.sh` (V1) and `docs/tasks/062-verify.sh` need ajv 8. Today the only copy on the machine is
`/tmp/fc041/node_modules` (ajv 8.20.0, checked 2026-10-15), which a reboot can wipe. After this task:
- `tools/dev/package.json` declares `ajv` at exactly `8.20.0` (no `^`, `~` or range; the site repo pins the same
  version, `site/package.json` line 30, checked 2026-10-15), and `tools/dev/package-lock.json` is committed with
  integrity hashes. `tools/dev/node_modules/` is gitignored.
- `tools/dev/README.md` gives the one install command, `npm ci --prefix tools/dev`, run from the repository root.
- `057-verify.sh` and `062-verify.sh` resolve ajv in this order: explicit argument, then `WOM_NODE_MODULES`, then
  `<repo root>/tools/dev/node_modules` (an absolute path computed from the script's own repository, so 062's runs in
  temporary clones still find it). A missing install fails with a message naming `npm ci --prefix tools/dev`.
- Nothing in `tools/registry/` or any checker's runtime path imports or invokes ajv or node.

ADR-0067 asks for frozen toolchains; a pinned lock file serves that for this one tool. A registry devcontainer is out of
scope (no task exists for it); the node version used is recorded in the log, not pinned.

## Context to load (exhaustive)
This file; registry `docs/tasks/057-verify.sh`, `docs/tasks/062-verify.sh`, `docs/tasks/057-ajv-check.mjs`,
`.gitignore`, `README.md`; platform `docs/manager/MANAGER.md` §2c, `docs/manager/OPERATIONS.md`,
`docs/decisions/0067-reproducible-dev-environments.md`, `docs/decisions/0103-restart-is-the-unit.md`.

## Acceptance criteria — demonstrated by `docs/tasks/066-verify.sh`, whose output the log pastes
1. `tools/dev/package.json` pins `ajv` to `8.20.0` exactly; the lock file resolves ajv to `8.20.0` with an `integrity`
   field. Mutation: a `^8.20.0` range in package.json reddens the check.
2. In a fresh clone of the committed HEAD, `npm ci --prefix tools/dev` succeeds and `tools/dev/node_modules/ajv` reports
   version `8.20.0`. (This one step needs the npm registry over the network; it is the only networked step and is
   labelled so in the script's output.)
3. In that clone, `057-verify.sh` run with **no argument and no `WOM_NODE_MODULES`** passes V1 (Ajv agreement), and
   `062-verify.sh` run the same way reports ALL CHECKS PASSED.
4. With `tools/dev/node_modules` absent and no argument or env, both scripts fail (never skip to green) and their output
   contains `npm ci --prefix tools/dev`. Shown red.
5. The explicit argument and `WOM_NODE_MODULES` still override the default (shown with `/tmp/fc041/node_modules` if it
   exists, else with the clone's own install passed explicitly).
6. No ajv in the runtime path: a search for `ajv` and for `node` invocations under `tools/registry/` finds nothing,
   with a positive control proving the same search finds `ajv` in `tools/dev/package.json` (MANAGER.md §2c rule 1).
7. `git status` in the clone after `npm ci` shows no untracked files (the gitignore covers `node_modules`).
8. Mutation set run by `066-verify.sh --mutate`, each shown red: range pin (1); default path removed from 057-verify.sh
   (3); failure message without the command (4); `.gitignore` line removed (7).

## File scope (declared)
`tools/dev/package.json`, `tools/dev/package-lock.json`, `tools/dev/README.md` (new); `.gitignore`;
`docs/tasks/057-verify.sh`, `docs/tasks/062-verify.sh` (ajv resolution and the failure message only — no other check
changes); `README.md` (one line pointing to `tools/dev/README.md`, if the README lists prerequisites);
`docs/tasks/066-registry-dev-tools-ajv.md` (log); `docs/tasks/066-verify.sh` (new).

## Size
Source files: 2 scripts + 3 new small files, within the cap. Changed lines: well under 300 excluding the generated lock file
(a lock file is generated data, not source). Reading list: 9.

## Forbidden here
Installing anything globally or outside `tools/dev/`; a version range; committing `node_modules`; changing any check's
verdict logic in 057/062 (only where ajv is found and what the failure says); making ajv or node a dependency of any
checker; npm credentials, `.npmrc` tokens or any authenticated registry access (CLAUDE.md rule 11) — the public npm
registry anonymously is the only permitted source.

## Dependencies
None blocking. File-disjoint from 007b (in flight) and 064. Task 064's verify script uses this default once 066 merges;
until then it takes `NODE_MODULES_DIR`. Before merging: run `062-verify.sh` on the PR branch merged onto `main`
(OPERATIONS.md, session 9).

---
# Task 066 log
- 2026-10-15 manager (session 9): drafted after Ludwig chose option A.
- 2026-10-15 manager (session 10): spec completed and approved (solo gate; SPEC-CHECKLIST 1–8 checked: observable
  objective, criteria each scripted, scope declared, context incl. ADR-0067/0103, budget small, size within cap,
  traps under Forbidden, no file overlap with 007b/064, verify artefact named).
- 2026-10-15 manager: worktree cut from registry origin/main `ac22c8f`; dispatched. check-log-entry baseline = 3.
- 2026-10-15 implementer (sonnet): built tools/dev/{package.json,package-lock.json,README.md} (ajv exact 8.20.0; lock
  from `npm install --userconfig /dev/null`, anonymous public registry, 5 packages with integrity), `.gitignore`
  `node_modules/`, default ajv location in 057-verify.sh and 062-verify.sh (argument, then WOM_NODE_MODULES, then
  `<repo root>/tools/dev/node_modules`; missing-install messages name `npm ci --prefix tools/dev`), and
  `docs/tasks/066-verify.sh`. Root README lists no prerequisites, so it is unchanged. Environment: node v24.20.0,
  npm 11.19.0 (recorded, not pinned).
- 2026-10-15 implementer: `066-verify.sh --mutate` output (HEAD clone; networked step labelled; exit 0):
  C1 PASS (pin + lock integrity); C2 PASS (`NETWORKED STEP: npm ci --prefix tools/dev`, added 5 packages, ajv 8.20.0);
  C3a PASS (V1: ajv 8.20.0; 156 cases; disagreements: []); C3b PASS (062 ALL CHECKS PASSED, default location);
  C4 PASS (both scripts exit 1, output names the command); C5a-d PASS (argument, WOM_NODE_MODULES incl. 062,
  /tmp/fc041); C6a-d PASS (positive controls found ajv in tools/dev/package.json and a node invocation in 057-verify.sh;
  nothing under tools/registry/); C7 PASS (clean git status after npm ci); M1-M4 PASS, each red:
  M1 `package.json ajv spec is '^8.20.0'`, M2 `FAIL V1 Ajv agreement not demonstrated`, M3 C4 reddens,
  M4 `?? tools/dev/node_modules/`. Final: ALL CHECKS PASSED.
- 2026-10-15 implementer FINDING (pre-existing, not 066): 008a-verify.sh counts `/tmp/wom008a-*` dirs before and after
  its suite, so any parallel verify run (another worktree's 064/062/008a) makes it fail "suite left N temp dir(s)", which
  reddens 062 AC3.head.008a (reproduced on unmodified origin/main with /tmp/fc041). Verify runs must not overlap on one
  machine; 066's final run waited for quiet. Suggest a follow-up task to make that check use a private TMPDIR.

## Questions
- Q1: README.md lists no prerequisites, so I made no README change (spec: only "if"). Assumption taken: leave it.
- 2026-10-15 manager: independent review PASS (static; no blocking findings; non-blocking: C2 runs `npm ci` with --userconfig /dev/null --ignore-scripts, stricter than the README command; 057 default depends on cwd being the repo root, failure direction safe; absent_check minor weakness). Merge gate remaining: `062-verify.sh` on this branch merged onto main, on a quiet machine (manager). Merge authorised by Ludwig's standing approval (mission log, session 10).
