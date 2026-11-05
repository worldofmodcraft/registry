#!/usr/bin/env python3
"""A measuring sweep driver for the registry's closed verify scripts (task 111a).

    python3 -I -B tools/dev/sweep.py --nm ABS_NODE_MODULES --out REPORT.json [--only a,b] [--no-wait]
    python3 -I -B tools/dev/sweep.py --list

Runs every docs/tasks/*-verify.sh exactly once at top level, one at a time, in a fresh `git clone --no-hardlinks`
of this repository at HEAD (a mktemp directory; the source checkout is never written), and writes a JSON report:
wall time and exit code per script, and how many times each verify script was started NESTED underneath it.

Nested starts are counted without touching any script: BASH_ENV points at a generated file that appends the PID, the
PPID and `$0` to a per-script log whenever `$0` matches *-verify.sh. A script that clears its environment hides its
children; the report says so in `nested_visibility`.

039a is listed as skipped ("it is the sweep"; it has no skip flag yet, task 111b). 039b runs with --no-closed.
Before each script the driver waits until no other *-verify.sh runs on the machine (this process, its descendants
and its ancestors do not count; OPERATIONS.md, 089e's others() shape). --no-wait turns that off (tests only).
Exit: 0 all scripts green; 1 at least one script failed; 2 usage or environment error (never 0 on an empty list).
Python 3 standard library only.
"""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP = {"039a-verify.sh": "it is the sweep"}
NO_CLOSED_ARGS = ["--no-closed"]
EXTRA_ARGS = {"039b-verify.sh": NO_CLOSED_ARGS}
NESTED_VISIBILITY = "BASH_ENV; children of a cleared environment are not counted"
BASH_ENV_TEXT = (
    'case "$0" in *-verify.sh) printf \'%s %s %s\\n\' "$$" "$PPID" "$0" >> "$WOM_SWEEP_LOG" ;; esac\n'
)
QUIET_LIMIT_S = 21600
QUIET_POLL_S = 30
SCRIPT_TIMEOUT_S = 21600
VERIFY_RE = re.compile(r"[0-9A-Za-z]+-verify[.]sh")


class EnvError(Exception):
    """A usage or environment error: exit 2."""


def list_scripts(root):
    return sorted(p.name for p in (root / "docs" / "tasks").glob("*-verify.sh"))


def others_from(ps_text, me):
    """Lines '<pid> <args>' of every *-verify.sh process that is not `me`, a descendant of `me` or an ancestor of `me`."""
    ppid, args, order = {}, {}, []
    for line in ps_text.splitlines():
        parts = line.split(None, 2)
        if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit():
            raise EnvError("unparseable ps line: %r" % line)
        pid = int(parts[0])
        ppid[pid] = int(parts[1])
        args[pid] = parts[2] if len(parts) > 2 else ""
        order.append(pid)
    if me not in ppid:
        raise EnvError("own pid %d missing from the ps table (a broken search is a failure)" % me)
    ancestors, q = set(), ppid[me]
    while q > 1 and q not in ancestors:
        ancestors.add(q)
        q = ppid.get(q, 0)
    result = []
    for pid in order:
        if pid == me or pid in ancestors or not VERIFY_RE.search(args[pid]):
            continue
        q, seen, descendant = pid, set(), False
        while q > 1 and q not in seen:
            if q == me:
                descendant = True
                break
            seen.add(q)
            q = ppid.get(q, 0)
        if not descendant:
            result.append("%d %s" % (pid, args[pid]))
    return result


def others():  # noqa: D401
    r = subprocess.run(["ps", "-eo", "pid=,ppid=,args="], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        raise EnvError("ps failed (exit %d): %s" % (r.returncode, r.stderr.strip()[:200]))
    return others_from(r.stdout, os.getpid())


def wait_quiet(label, others_fn=None, sleep=time.sleep):
    """Block until no other *-verify.sh runs. Returns (quiet, waited_seconds); quiet is False after QUIET_LIMIT_S."""
    others_fn = others_fn or others
    waited = 0
    while True:
        o = others_fn()
        if not o:
            print("ps    %s: no other *-verify.sh process running (waited %ds)" % (label, waited), flush=True)
            return True, waited
        print("ps    %s: waiting, %d other process(es):" % (label, len(o)), flush=True)
        for line in o:
            print("        " + line[:160], flush=True)
        if waited >= QUIET_LIMIT_S:
            return False, waited
        sleep(QUIET_POLL_S)
        waited += QUIET_POLL_S


def count_nested(log_path, top_pid):
    """name -> count of verify-script starts in the log other than the top-level process itself."""
    counts = {}
    if not log_path.exists():
        return counts
    for line in log_path.read_text(errors="replace").splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3 or int(parts[0]) == top_pid:
            continue
        name = os.path.basename(parts[2])
        counts[name] = counts.get(name, 0) + 1
    return dict(sorted(counts.items()))


def kill_group(proc):
    """SIGKILL the script's whole process group (it is its own session); a group that is already gone is fine."""
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def run_script(clone, name, nm, work, no_wait, waiter=wait_quiet, timeout=SCRIPT_TIMEOUT_S):
    rec = {"name": name, "seconds": None, "exit": None, "nested_starts": {}, "waited_seconds": 0}
    if not no_wait:
        quiet, rec["waited_seconds"] = waiter(name)
        if not quiet:
            rec["error"] = "another *-verify.sh kept running for six hours"
            return rec
    log = work / (name + ".nested.log")
    env = dict(os.environ)
    env.pop("NODE_MODULES_DIR", None)  # 039a runs `env -u WOM_NODE_MODULES -u NODE_MODULES_DIR bash "$f"`
    env.pop("WOM_NODE_MODULES", None)
    env["WOM_SWEEP_LOG"] = str(log)
    env["BASH_ENV"] = str(work / "bash_env.sh")
    cmd = ["bash", str(clone / "docs" / "tasks" / name)] + EXTRA_ARGS.get(name, [])
    outfile = work / (name + ".out")
    t0 = time.monotonic()
    with open(outfile, "wb") as fh:
        proc = subprocess.Popen(cmd, cwd=clone, env=env, stdin=subprocess.DEVNULL, stdout=fh, stderr=subprocess.STDOUT,
                                start_new_session=True)
        timed_out = False
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            # timeout, interrupt, exception or a normal exit that left background children: nothing survives the script
            kill_group(proc)
            proc.wait()
    rec["seconds"] = round(time.monotonic() - t0, 4)
    rec["exit"] = None if timed_out else proc.returncode
    if timed_out:
        rec["error"] = "timeout"
    rec["nested_starts"] = count_nested(log, proc.pid)
    rec["nested_total"] = sum(rec["nested_starts"].values())
    if rec["exit"] != 0:
        rec["output_tail"] = outfile.read_text(errors="replace").splitlines()[-6:]
    return rec


def write_report(path, report):
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(report, indent=2) + "\n")
    os.replace(tmp, path)


def totals(scripts):
    nested = {}
    for s in scripts:
        for k, v in s["nested_starts"].items():
            nested[k] = nested.get(k, 0) + v
    return {
        "seconds": round(sum(s["seconds"] or 0 for s in scripts), 4),
        "nested_starts": dict(sorted(nested.items())),
        "nested_starts_total": sum(nested.values()),
    }


def main(argv):
    ap = argparse.ArgumentParser(prog="sweep.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--nm", help="absolute path of a node_modules directory containing ajv")
    ap.add_argument("--out", help="report file, outside the repository")
    ap.add_argument("--only", help="comma-separated basenames to run (tests)")
    ap.add_argument("--list", action="store_true", help="print the scripts and exit")
    ap.add_argument("--script-timeout", type=float, default=SCRIPT_TIMEOUT_S, metavar="SECONDS",
                    help="kill a script's process group after this many seconds and record error=timeout, exit=null (default 21600)")
    ap.add_argument("--no-wait", action="store_true", help="skip the quiet-machine wait (tests only)")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    def on_term(signum, frame):
        raise SystemExit(128 + signum)  # unwinds through run()'s finally: the script's group is killed, the clone removed
    signal.signal(signal.SIGTERM, on_term)
    try:
        return run(a)
    except EnvError as e:
        print("sweep.py: error: %s" % e, file=sys.stderr)
        return 2


def run(a):
    names = list_scripts(ROOT)
    if a.list:
        if not names:
            raise EnvError("no docs/tasks/*-verify.sh found under %s" % ROOT)
        for n in names:
            if n in SKIP:
                print("%s  [skipped: %s]" % (n, SKIP[n]))
            else:
                print("%s%s" % (n, ("  args: " + " ".join(EXTRA_ARGS[n])) if n in EXTRA_ARGS else ""))
        print("%d scripts, %d skipped" % (len(names), sum(1 for n in names if n in SKIP)))
        return 0
    if not a.nm or not a.out:
        raise EnvError("--nm and --out are required")
    nm, out = Path(a.nm), Path(a.out)
    if a.script_timeout <= 0:
        raise EnvError("--script-timeout must be positive")
    if nm.is_absolute():
        nm = Path(os.path.realpath(nm))  # a symlinked --nm would make `cp -a` copy the link
    if not nm.is_absolute() or not (nm / "ajv").is_dir():
        raise EnvError("--nm must be an absolute path of a directory containing ajv (npm ci --prefix tools/dev): %s" % a.nm)
    out = out.resolve()
    if out == ROOT or ROOT in out.parents:
        raise EnvError("--out must be outside the repository: %s" % out)
    if not out.parent.is_dir():
        raise EnvError("--out directory does not exist: %s" % out.parent)
    if a.only:
        want = [x.strip() for x in a.only.split(",") if x.strip()]
        missing = [x for x in want if x not in names]
        if missing:
            raise EnvError("--only names not found in docs/tasks: %s" % ", ".join(missing))
        names = [n for n in names if n in want]
    skipped = [{"name": n, "reason": SKIP[n]} for n in names if n in SKIP]
    todo = [n for n in names if n not in SKIP]
    if not todo:
        raise EnvError("empty script list: nothing to run")
    head = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"], capture_output=True, text=True)
    if head.returncode != 0:
        raise EnvError("cannot read HEAD of %s" % ROOT)
    head = head.stdout.strip()
    work = Path(tempfile.mkdtemp(prefix="wom-sweep."))
    try:
        clone = work / "clone"
        r = subprocess.run(["git", "clone", "-q", "--no-hardlinks", str(ROOT), str(clone)], capture_output=True, text=True)
        if r.returncode != 0:
            raise EnvError("git clone failed: %s" % r.stderr.strip()[:200])
        chead = subprocess.run(["git", "-C", str(clone), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
        if chead != head:
            raise EnvError("clone HEAD %s differs from source HEAD %s" % (chead, head))
        (clone / "tools" / "dev").mkdir(parents=True, exist_ok=True)
        r = subprocess.run(["cp", "-a", str(nm), str(clone / "tools" / "dev" / "node_modules")], capture_output=True, text=True)
        if r.returncode != 0:
            raise EnvError("cp -a node_modules failed: %s" % r.stderr.strip()[:200])
        dirty = subprocess.run(["git", "-C", str(clone), "status", "--porcelain"], capture_output=True, text=True)
        if dirty.returncode != 0 or dirty.stdout.strip():
            raise EnvError("clone is not clean before the first script (git status --porcelain): %s" % (dirty.stdout.strip()[:200] or dirty.stderr.strip()[:200]))
        (work / "bash_env.sh").write_text(BASH_ENV_TEXT)
        report = {
            "head": head,
            "started": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "finished": None,
            "complete": False,
            "measured": [],
            "unmeasured": [],
            "quiet_wait": not a.no_wait,
            "planned": todo,
            "nested_visibility": NESTED_VISIBILITY,
            "scripts": [],
            "skipped": skipped,
            "totals": totals([]),
        }
        write_report(out, report)  # `planned` is on disk before the first script runs
        for n in todo:
            print("run   %s" % n, flush=True)
            rec = run_script(clone, n, nm, work, a.no_wait, timeout=a.script_timeout)
            report["scripts"].append(rec)
            report["totals"] = totals(report["scripts"])
            report["measured"] = [s["name"] for s in report["scripts"] if s["exit"] is not None]
            report["unmeasured"] = [s["name"] for s in report["scripts"] if s["exit"] is None]
            if len(report["scripts"]) == len(todo):
                report["complete"] = True
                report["finished"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
            write_report(out, report)
            print("done  %s exit=%s seconds=%s nested=%s" % (n, rec["exit"], rec["seconds"], rec.get("nested_total")), flush=True)
        failed = [s["name"] for s in report["scripts"] if s["exit"] != 0]
        print("report %s: %d run, %d failed%s" % (out, len(todo), len(failed), (": " + ", ".join(failed)) if failed else ""))
        return 1 if failed else 0
    finally:
        subprocess.run(["chmod", "-R", "u+w", str(work)], capture_output=True)
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
