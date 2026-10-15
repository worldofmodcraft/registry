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
