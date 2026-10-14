#!/usr/bin/env python3
"""Run the task 008a suite and print one `CHECK <name> PASS|FAIL` line per test, then a summary.
`--only <substring> ...` restricts to tests whose id contains any substring (used by the mutation
runner). Exit code: number of failing checks (0 = all pass; 99 if nothing ran)."""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, HERE)


class Result(unittest.TextTestResult):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self.lines = []

    def _line(self, test, verdict):
        self.lines.append(f"CHECK {test.id().split('.', 1)[-1]} {verdict}")

    def addSuccess(self, test):
        super().addSuccess(test); self._line(test, "PASS")

    def addFailure(self, test, err):
        super().addFailure(test, err); self._line(test, "FAIL")

    def addError(self, test, err):
        super().addError(test, err); self._line(test, "FAIL")

    def addSkip(self, test, reason):
        super().addSkip(test, reason); self._line(test, "FAIL")   # a skipped check proves nothing


def flatten(suite):
    for t in suite:
        if isinstance(t, unittest.TestSuite):
            yield from flatten(t)
        else:
            yield t


def main():
    argv = sys.argv[1:]
    only = []
    if argv and argv[0] == "--only":
        only = argv[1:]
    suite = unittest.defaultTestLoader.discover(HERE, pattern="test_*.py")
    tests = [t for t in flatten(suite) if not only or any(o in t.id() for o in only)]
    if not tests:
        print("CHECK (none) FAIL -- no test matched; a search that finds nothing is a broken search")
        return 99
    s = unittest.TestSuite(tests)
    stream = open(os.devnull, "w")
    runner = unittest.TextTestRunner(stream=stream, resultclass=Result, verbosity=0)
    res = runner.run(s)
    for line in res.lines:
        print(line)
    for _, tb in res.failures + res.errors:
        print(tb, file=sys.stderr)
    bad = sum(1 for l in res.lines if l.endswith("FAIL"))
    print(f"SUMMARY ran={len(res.lines)} failed={bad}")
    return bad


if __name__ == "__main__":
    sys.exit(main())
