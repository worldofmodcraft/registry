# Task 111a: a measuring sweep driver for the registry's closed verify scripts

- **Mission:** SITE-V1 (process; Ludwig's option C for long test runs, 2026-11-04) — **Status:** spec-approved (manager, 2026-11-04, solo gate: a new read-only dev tool; no closed script, workflow or security surface changes)
- **Repo:** registry. **Agent / model:** implementer (model per frontmatter). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/111a-sweep-measure` / `~/wt/registry-task-111a`, cut from registry `origin/main`
- **Graph:** no node or edge; a developer tool that reads the repository only.
- **Sequel:** 111b (de-duplicate) and 111c (path-filtered pre-merge plus nightly sweep per ADR-0099) are specified from this task's measurement. Ordering decided ★ under ADR-0125; see the mission log, 2026-11-04.

## Objective
`tools/dev/sweep.py` runs every registry `docs/tasks/*-verify.sh` exactly once at top level, one at a time, and writes a JSON report with
each script's wall time and exit code and how many times each verify script was started in nested form underneath it. The manager can then
state the top costs and the duplicated work from data, without any closed script having changed.

## Known facts (survey, 2026-11-04, registry `428df02`; line numbers as grepped)
- Sweepers: 039a (unconditional, `039a-verify.sh:218`), 039b (unless `--no-closed`, first argument), 082 (`--full` only), 092 (`--closed` only).
- Static nested calls exist at least in 062, 064, 065, 066, 067, 069, 070, 075, 087, 089a1, 089a2, 089b, 089c. The list may be incomplete, so the driver measures rather than trusts it.
- Scripts needing ajv take a `node_modules` path by first argument or `WOM_NODE_MODULES` (`057-verify.sh:29`); 066 uses the network for `npm ci`.
- Quiet-wait: use 089e's `others()` shape (skip this PID, its descendants and ancestors; OPERATIONS.md).

## Design (fixed by this spec)
- Python 3 stdlib only, run as `python3 -I -B tools/dev/sweep.py`. Arguments: `--nm ABS_PATH` (required; refused if `ajv` is missing), `--out FILE` (required, outside the repository), `--only a,b` (basenames, for tests), `--list`.
- Runs against a fresh `git clone --no-hardlinks` of the local repository at HEAD in a `mktemp -d`, as 039a does; the source checkout is never written.
- Scripts run sorted, one at a time, after a quiet-wait. `039b` gets `--no-closed`. `039a` is **listed as skipped with the reason "it is the sweep"**; it has no skip flag yet (111b).
- **Nested starts** are counted without touching any script: the driver sets `BASH_ENV` to a small generated file appending `$0` and a timestamp to a per-run log when `$0` matches `*-verify.sh`. A script that clears its environment hides its children; the report therefore carries `nested_visibility: "BASH_ENV; children of a cleared environment are not counted"`, and a test shows the counting works on a stub.
- Report JSON: `head`, `started`, `finished`, `scripts[]` with `name`, `seconds`, `exit`, `nested_starts` (name -> count), `skipped` with reason; a `totals` block with the sum of seconds and the sum of nested starts per script. A non-zero script is recorded and the sweep continues; the driver's own exit is 1 if any script failed, 2 on a usage or environment error, never 0 on an empty script list.

## Acceptance criteria — `docs/tasks/111a-verify.sh`
1. Stubs in a temp repository: three stub verify scripts (one green, one red, one that runs another) give the expected `exit`, `seconds` > 0 and `nested_starts`; driver exit 1 because of the red one. Positive control: all green gives exit 0.
2. Failure modes: an empty script list, a missing `ajv` and an `--out` inside the repository each give exit 2. A broken search counts as failure (MANAGER.md §2c rule 1).
3. `--list` on the real tree prints every `docs/tasks/*-verify.sh`, count asserted against the glob and non-zero, with 039a marked skipped and 039b's `--no-closed` shown.
4. The source checkout is unchanged after a run (`git status --porcelain` empty), and no `__pycache__` is left.
5. `--mutate` reddens a check for each of: nested counting removed; exit code ignored; the `--no-closed` argument dropped.
6. Fresh-clone run passes. Own-change checks read fixed SHAs, live guards read HEAD. **The verify script does not run the real closed scripts and finishes in under two minutes**, because 039a will include it in every sweep. It tolerates being run from 039a (no quiet-wait in the verify script itself).

**Not in this task's criteria:** the real measurement. The manager runs it after merge on a quiet machine and records the output in this log.

## File scope
`tools/dev/sweep.py`, `tests/registry/test_sweep.py`, `docs/tasks/111a-sweep-measure.md` (a copy of this file, carrying the log), `docs/tasks/111a-verify.sh`.

## Forbidden
Editing any existing verify script, workflow, tool or test; running a whole sweep (039a, or the driver without `--only`) because the machine is shared; `pkill`; credentials of any kind; a dependency outside the stdlib.

---
# Task 111a log
- 2026-11-04 manager (session 15): spec written, gate passed solo.
- 2026-11-04 implementer: tools/dev/sweep.py, tests/registry/test_sweep.py (19 tests, stubs only) and docs/tasks/111a-verify.sh done; FINAL=c18d6da. Verify default and --mutate green (7s). Additions beyond the spec's argument list: `--no-wait` (skips the quiet-wait; needed so tests on a shared machine do not block; the production run omits it), `nested_total` and `output_tail` (last 6 lines, non-zero scripts only) per script, `totals.nested_starts_total`, and the report is rewritten after every script so a hang loses nothing. `--list` needs no --nm/--out. The quiet-wait polls every 30 s for at most 6 h; on timeout the script is recorded with `error` and `exit: null` and counts as failed. Nested counting skips only the top-level process (PID match), so a script that runs itself recursively counts its inner starts. Real measurement not run (reserved for the manager after merge).
- 2026-11-04 implementer (fix round, review findings 1-5): fixtures written FIRST and run against the pushed code (cf6e0e2), red output:
  ```
  ERROR: test_complete_report (test_sweep.ReportCompleteness.test_complete_report)
  ERROR: test_partial_report_is_marked_incomplete (test_sweep.ReportCompleteness.test_partial_report_is_marked_incomplete)
  ERROR: test_no_wait_never_calls_the_waiter (test_sweep.WaitLoop.test_no_wait_never_calls_the_waiter)
  ERROR: test_timeout_records_error_and_null_exit (test_sweep.WaitLoop.test_timeout_records_error_and_null_exit)
  ERROR: test_timeout_returns_false (test_sweep.WaitLoop.test_timeout_returns_false)
  ERROR: test_wait_is_used_when_not_no_wait (test_sweep.WaitLoop.test_wait_is_used_when_not_no_wait)
  ERROR: test_waits_until_quiet (test_sweep.WaitLoop.test_waits_until_quiet)
  FAIL: test_env_unset_and_node_modules_is_a_real_directory (test_sweep.GateEnvironment.test_env_unset_and_node_modules_is_a_real_directory)
  FAIL: test_untracked_files_in_the_clone_before_the_first_script_exit_2 (test_sweep.GateEnvironment.test_untracked_files_in_the_clone_before_the_first_script_exit_2)
  Ran 28 tests in 1.836s
  FAILED (failures=2, errors=7)
  ```
  Then fixed in sweep.py; 28 tests green. Changes: (1) report has `planned` (written to disk before the first script), `complete` (false until the last script is recorded), `finished` null until then; a test kills the driver mid-sweep and the file says complete=false. (2) per-script `waited_seconds`, top-level `quiet_wait` (false under --no-wait). (3) scripts run in 039a's environment: node_modules copied with `cp -a` into tools/dev/node_modules, WOM_NODE_MODULES and NODE_MODULES_DIR unset (the test sets both in the parent; the stub sees UNSET). (4) the driver exits 2 if the clone's `git status --porcelain` is non-empty before the first script (a stub without .gitignore proves it; the real repo ignores node_modules/). (5) wait_quiet/run_script take injected others_fn/sleep/waiter: tests for wait-until-quiet, timeout, error plus null exit, and the no_wait guard; the --mutate item 'quiet-wait guard removed' reddens test_no_wait_never_calls_the_waiter. FINAL re-pinned to 0bc7b8a. Findings 6 and 7: no change.
