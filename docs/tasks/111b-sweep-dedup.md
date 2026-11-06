# Task 111b: the whole sweep runs each closed script's nested sweep once, not again inside 064 and 065

- **Mission:** SITE-V1 (process; Ludwig's option C) — **Status:** spec-approved (manager, 2026-11-05, solo gate: a skip flag with a proven pattern; the merge gate is a whole sweep)
- **Repo:** registry. **Agent / model:** implementer (model per frontmatter). **Budget:** small (≤ 1 agent-session)
- **Branch / worktree:** `task/111b-sweep-dedup` / `~/wt/registry-task-111b`, cut from registry `origin/main` (`ab5fcba`)
- **Graph:** no node or edge. **Depends on:** 111a (merged). **Sequel:** 111c (path-filtered pre-merge plus nightly sweep, ADR-0099).

## Measured (manager, `tools/dev/sweep.py` on `58c75c0`, 2026-11-05; report in the mission log)
Sum 26,195 s (7.3 h). 065 = 11,563 s, 064 = 5,665 s, 070 = 2,944 s: 77 % together. `065-verify.sh:232` runs 13 closed scripts, including 064, and those account for about 11,386 s. `064-verify.sh:141,147` runs 12, about 5,515 s. Removing both loops inside a sweep leaves about 9,300 s (2.6 h). Timing is from a machine also running read-only agents, so it may be somewhat high.

## Objective
Inside a sweep, 064 and 065 do not re-run other closed scripts; the sweep already runs each one. Standalone behaviour is unchanged. The driver also refuses a source clone that would give its inner clone no `origin/main`.

## Design (fixed by this spec, 039b's pattern: `039b-verify.sh:34,191,218`, `039a-verify.sh:222`)
- `064-verify.sh` and `065-verify.sh` accept `--no-closed` as the **first** argument. It skips only the sections that run *other* closed scripts at HEAD: 065's AC4.2 and AC4.3; 064's AC4.2. It prints "`ACx NOT RUN (--no-closed)`" and a NOTE "not a full pass", and exits on the remaining checks. 064's and 065's direct run of 057 (AC3.2, AC2.4) checks their own subject and stays.
- `039a-verify.sh:222` and `tools/dev/sweep.py` pass `--no-closed` to 039b, 064 and 065. The list is one named constant in `sweep.py`.
- `sweep.py`: exit 2 with a plain message when the source clone has no local `main` (found 2026-11-05: `089c-verify.sh` AC0.4 went red when the driver was run from a clone made with `--branch`, because the inner clone had no `origin/main`).
- No `--no-closed` for 070, 069 or others: their nested runs are fixtures of their own checks, not sweeps. Do not change them.

## Acceptance criteria — `docs/tasks/111b-verify.sh`
**The missing-`main` break found on 2026-11-05 goes in as a fixture, shown failing first (§2c rule 5).**
1. Stubbed in a temp copy of the scripts, or by inspecting a run with a harmless stub `docs/tasks/*-verify.sh` tree: with `--no-closed`, 064 and 065 start no other closed script except 057; without it they still start them. Prove by reading `BASH_ENV`-style nested starts, as `tools/dev/sweep.py` does, and do not run the real closed scripts end to end from this verify script.
2. Standalone is unchanged: a diff of 064 and 065 shows additions only around the flag, with every existing check line byte-identical outside the guarded section.
3. Labels: a `--no-closed` run prints the NOT RUN line and the NOTE for the skipped sections.
4. `--list` on the real tree shows `--no-closed` for 039b, 064, 065. The driver gives 064 and 065 the flag.
5. The missing-`main` fixture gives exit 2, with a positive control where `main` exists.
6. `--mutate` reddens: flag ignored in 064; flag ignored in 065; `sweep.py` not passing it; missing-`main` check removed.
7. Fresh clone from GitHub; own-change checks on fixed SHAs; live guards on HEAD; under two minutes; tolerates being run from 039a; `python3 -I -B`, no `__pycache__`.

**Not in the agent's criteria: the merge gate.** The manager runs the real sweep on the merge result and records the new timing, because this changes closed scripts (OPERATIONS.md). Other closed scripts may pin text in 039a, 064 or 065; the sweep finds them. If one reddens, report it and stop; do not edit another closed script.

## File scope
`docs/tasks/064-verify.sh`, `docs/tasks/065-verify.sh`, `docs/tasks/039a-verify.sh` (line 222's case only), `tools/dev/sweep.py`, `tests/registry/test_sweep.py`, `docs/tasks/111a-sweep-measure.md` (only to append the measurement the manager gives you; see below), `docs/tasks/111b-sweep-dedup.md` (copy of this file, carrying the log), `docs/tasks/111b-verify.sh`, its fixtures.

## Forbidden
Weakening any check that runs in standalone mode; removing a loop rather than guarding it; changing 070, 069 or any other closed script; running the real sweep, 039a, or the real 064 or 065 end to end (they take hours; the manager does that); a command line naming a `*-verify.sh` in a shell pipeline, since quiet-waits see it (use a script file); a `pgrep -f` watcher naming a verify script, which never ends and blocks the machine (OPERATIONS.md, booked); `pkill`; touching any other checkout; credentials of any kind. If anything is denied, do not retry; report.

---
# Task 111b log
- 2026-11-05 manager (session 15): spec written from the measurement; gate passed solo.
- 2026-11-06 implementer: done; pins BASE=ab5fcba (origin/main), RED=62fc5be, FIX=b19bf12; `docs/tasks/111b-verify.sh` default (~15 s) and `--mutate` (~10 s) green.
  - Red first (RED commit 62fc5be = test_sweep.py only, run against the unfixed sweep.py of ab5fcba; 36 older tests and both positive controls stay green). Output of `python3 -I -B -m unittest discover -s tests/registry -p test_sweep.py`:
    ```
    FAIL: test_list_shows_no_closed_for_039b_064_065_only (test_sweep.ListReal.test_list_shows_no_closed_for_039b_064_065_only)
    FAIL: test_source_cloned_with_branch_has_no_local_main_exit_2 (test_sweep.MissingMain.test_source_cloned_with_branch_has_no_local_main_exit_2)
    FAIL: test_source_on_a_branch_named_trunk_exit_2 (test_sweep.MissingMain.test_source_on_a_branch_named_trunk_exit_2)
    FAIL: test_064_and_065_get_no_closed_and_other_scripts_get_none (test_sweep.NoClosedArguments.test_064_and_065_get_no_closed_and_other_scripts_get_none)
    FAIL: test_the_flag_list_is_one_named_constant_and_a_list_of_three (test_sweep.NoClosedArguments.test_the_flag_list_is_one_named_constant_and_a_list_of_three)
    Ran 41 tests in 6.091s
    FAILED (failures=5)
    ```
    The missing-main fixture is the 2026-11-05 shape: `git clone --branch feat` of a stub repository, so the source has no local `main`. At the red commit the driver exits 0 and runs the script; with the fix it exits 2 before cloning ("the source clone ... has no local branch 'main'"), no script runs, no report is written. Positive control: with a local main the probe script sees `origin/main` in the inner clone and the sweep exits 0. FIX: 41 tests green.
  - Fix (FIX commit b19bf12): `tools/dev/sweep.py` (EXTRA_ARGS names 039b, 064, 065, all `NO_CLOSED_ARGS`; the refs/heads/main check), `039a-verify.sh` (the one case line in the verify loop), `064-verify.sh` and `065-verify.sh` (additions only: 7 and 8 lines, 0 removed).
  - Guarded sections (the full list): 064: AC4.2 only (both loops: 006 032 034 057, then 007a 007b 008a 062 066 067 069 070). 065: AC4.2 (007a 007b 008a 032 034 062 064 066 067 069 070 071 075) and AC4.3 (006), under one guard. Not guarded: 064 AC3.2 and 065 AC2.4 (the direct run of 057), AC4.1 (the four unit-test suites) and everything else. 070, 069 and every other closed script are untouched.
  - How the closed scripts are exercised without running them: `111b-verify.sh` cuts the real 064/065 text into a slice (real prelude with the real argument parsing and pins, the 057 line, the real AC4 section, the real RESULT tail) and runs it over a stub tree (every `*-verify.sh` is `exit 0`; one trivial passing test per tests/ directory) with a BASH_ENV file that records each `*-verify.sh` start, as sweep.py does. Measured: with `--no-closed` the nested starts are exactly {057} for both; without it 064 starts 13 (057 twice, plus 006 032 034 007a 007b 008a 062 066 067 069 070) and 065 starts 15; the same slices cut from BASE and given `--no-closed` still start 13 and 15 (the control that the harness sees the break).
  - Mutations (all red, restore green): flag ignored in 064; flag ignored in 065; sweep.py not passing it; missing-main check removed; 039a's case not passing it.
  - FOR THE MANAGER, not done by me: (1) the merge-gate sweep. (2) `111a-verify.sh` pins `FINAL..HEAD touches only in-scope files` with a scope that does not list 064/065/039a/the 111b files, so by its own design it may redden on this branch (see the entry below for the measured result). I did not edit it (not in scope). (3) 089b-verify.sh runs the NEW 065 `--mutate` on HEAD and checks AC3.5; I did not run it. (4) The real 064, 065, 039a and the sweep were not run, by order.
- 2026-11-06 manager: **scope extended (★ under ADR-0125).** `111a-verify.sh`'s own-change check reads `FINAL..HEAD`, which breaks Ludwig's decision A ("own-change checks read fixed SHAs only"; OPERATIONS.md) and reddens on any later commit. 111b found it. Options: A★ re-pin it inside 111b to `FINAL..TIP` with TIP = `58c75c0` (111a's merged head, `ab5fcba^2`), task 101's pattern, red-first shown on this branch; B a separate task, which costs a second multi-hour sweep. Added to the file scope: `docs/tasks/111a-verify.sh` (the own-change range only; its live guards stay on HEAD). Missed by three 111a review rounds and by the manager.
- 2026-11-06 implementer (scope extension, 111a-verify.sh re-pin): done in commit 23d32e7 (FIX2). `111a-verify.sh`: new pin `TIP=58c75c033cbddc506f55358e6716682e9bfe9a53` (111a's merged head, `ab5fcba^2`; FINAL 1fdf6e7 is an ancestor of it); the check line `FINAL..HEAD touches only in-scope files` becomes `FINAL..TIP` (read through a variable so an empty or unreadable range is a FAIL, not a pass), plus a new check that TIP exists, FINAL is an ancestor of TIP and TIP an ancestor of HEAD (task 101's pattern). 8 lines added, 1 removed; the tests, `--list` and timing checks of 111a stay on the HEAD clone, unchanged. The measured FINAL..TIP file set is `111a-sweep-measure.md` and `111a-verify.sh`, both in 111a's scope.
  - Red first, in `111b-verify.sh` AC8 (frame = a clone of this branch head, 111a's script replaced by the OLD blob `ab5fcba:docs/tasks/111a-verify.sh`): exit 1 with exactly one failure,
    ```
    FAIL  FINAL..HEAD touches out-of-scope files
    ```
    The new script (the committed blob) on the same head: exit 0, `ALL PASS`, printing `PASS  FINAL..TIP touches only in-scope files` and `PASS  TIP is reachable: ...`. It is also green on a frame where a later commit touches an out-of-scope file (`docs/tasks/999-later-task.txt`), where the OLD blob is red again (the control that the frame discriminates).
  - `111b-verify.sh` itself no longer reads HEAD for a range: the former `FIX..HEAD in scope` check is replaced by `FIX..FIX2` (fixed; FIX2 = 23d32e7 is this script's TIP, 101's pattern: nothing after it is range-checked) plus the ancestry order. New mutation (sixth): TIP in 111a-verify.sh set back to HEAD, run on the later-commit frame, reddens with `FINAL..TIP touches out-of-scope files`; its control (unmutated, same frame) is green. 111a's own `--mutate` (about 77 s) is not run from 111b-verify.sh; it was run separately (see the report).
  - The item "(2)" under "FOR THE MANAGER" in the previous entry is resolved by this extension.
