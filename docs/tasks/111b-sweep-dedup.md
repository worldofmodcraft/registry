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
