"""Bounded subprocess runner: wall-clock timeout plus a size cap on a watched path.

Used for `git clone` (watch the clone directory), `git archive` (watch the tar it writes) and
`minisign`. A child is started in its own session (no controlling terminal, so nothing can prompt)
and its whole process group is killed on timeout or cap breach.
"""

from __future__ import annotations

import os
import signal
import subprocess
import tempfile
import time

from pipeline_errors import PipelineError, Rejected

POLL_SECONDS = 0.05


def path_size(path: str) -> int:
    """Total bytes under `path` (file or directory), counting links by lstat, never following."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return 0
    if not os.path.isdir(path) or os.path.islink(path):
        return st.st_size
    total = 0
    stack = [path]
    while stack:
        d = stack.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_dir(follow_symlinks=False):
                            stack.append(e.path)
                        else:
                            total += e.stat(follow_symlinks=False).st_size
                    except FileNotFoundError:
                        pass
        except FileNotFoundError:
            pass
    return total


class RunResult:
    def __init__(self, returncode: int, stderr: str):
        self.returncode = returncode
        self.stderr = stderr


def run_bounded(
    cmd: list[str],
    env: dict[str, str],
    *,
    timeout: float,
    what: str,
    cwd: str | None = None,
    stdout_path: str | None = None,
    watch_path: str | None = None,
    max_bytes: int | None = None,
    size_rule: str = "size-cap",
    size_message: str = "",
    size_remedy: str = "",
) -> RunResult:
    """Run `cmd`; raise PipelineError (exit 2) on timeout, Rejected (exit 1) when the watched path
    grows past `max_bytes`. Returns the exit status and captured stderr otherwise."""
    err = tempfile.TemporaryFile()
    out = open(stdout_path, "wb") if stdout_path else subprocess.DEVNULL
    try:
        try:
            proc = subprocess.Popen(
                cmd, env=env, cwd=cwd, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                start_new_session=True,
            )
        except FileNotFoundError as exc:
            raise PipelineError(f"{what}: cannot start {cmd[0]!r}: {exc}")
        deadline = time.monotonic() + timeout
        verdict: str | None = None
        while True:
            rc = proc.poll()
            if rc is not None:
                break
            if time.monotonic() > deadline:
                verdict = "timeout"
                break
            if watch_path is not None and max_bytes is not None and path_size(watch_path) > max_bytes:
                verdict = "size"
                break
            time.sleep(POLL_SECONDS)
        if verdict:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait()
        err.seek(0)
        stderr = err.read(65536).decode("utf-8", "replace")
        if verdict == "timeout":
            raise PipelineError(f"{what}: timed out after {timeout:g}s and was killed")
        if verdict == "size":
            raise Rejected(size_rule, size_message, size_remedy)
        # A size breach that happened between the last poll and exit is still a breach.
        if watch_path is not None and max_bytes is not None and path_size(watch_path) > max_bytes:
            raise Rejected(size_rule, size_message, size_remedy)
        return RunResult(proc.returncode, stderr)
    finally:
        err.close()
        if stdout_path:
            out.close()
