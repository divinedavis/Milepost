#!/usr/bin/env python3
"""Keep the UI tests in step with the app as screens come and go
(2026-10-07; owner: the checks must follow features as they are added and
removed). Static, no simulator. Two failures, either of which stops a ship:

  * UNTESTED SCREEN: a screen file under Milepost/Screens or Milepost/Social
    that declares accessibility identifiers, none of which any UI test
    queries. The folders ARE the list, so a new screen cannot ship without a
    test that reaches it, and a deleted one drops out by itself.
  * STALE IDENTIFIER: a UI test queries a dotted identifier
    ("record.start") that no longer appears anywhere in the app. A line with
    XCTAssertFalse is a deliberate "this must be gone" check and is skipped.

  python3 scripts/check_test_coverage.py
"""
import glob, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SCREEN_DIRS = ["Milepost/Screens", "Milepost/Social"]
APP_DIRS = ["Milepost", "MilepostWidget"]
# Screens no UI test may reach, each with the reason. Keep this list short.
EXEMPT = {
    # Shown only for a session mirrored from a real Apple Watch workout; the
    # simulator pair cannot start one under XCUITest.
    "MirroredWorkoutBanner": "needs a live mirrored HKWorkoutSession",
    # Appears only when Apple Health returns heart rate etc. for the
    # activity; the UI-test runner has no HealthKit entitlement or samples.
    "HealthMetricsSection": "needs HealthKit samples the runner cannot read",
}
DECLARED = re.compile(r'(?:accessibilityIdentifier\(|\bid: )"([^"]+)"')
LITERAL = re.compile(r'"((?:\\\((?:[^()]|\([^()]*\))*\)|\\.|[^"\\])*)"')
QUOTED = re.compile(r'"([a-z][A-Za-z0-9]*\.[A-Za-z0-9.]+)"')


def stem(s):
    return s.split("\\(")[0]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def main():
    tests = [read(f) for f in glob.glob(os.path.join(ROOT, "MilepostUITests/*.swift"))]
    test_lines = [l for t in tests for l in t.splitlines() if "XCTAssertFalse" not in l]
    queried = {stem(m.group(1)) for l in test_lines for m in QUOTED.finditer(l)
               if not m.group(1).startswith("com.apple.")}
    test_text = "\n".join(test_lines)

    untested = []
    for d in SCREEN_DIRS:
        for f in sorted(glob.glob(os.path.join(ROOT, d, "*.swift"))):
            name = os.path.splitext(os.path.basename(f))[0]
            ids = {stem(i) for i in DECLARED.findall(read(f))}
            if not ids or name in EXEMPT:
                continue
            if not any(i in test_text for i in ids):
                untested.append(f"{d}/{name}.swift ({', '.join(sorted(ids)[:4])})")

    app_lits = set()
    for d in APP_DIRS:
        for f in glob.glob(os.path.join(ROOT, d, "**/*.swift"), recursive=True):
            app_lits |= {stem(m.group(1)) for m in LITERAL.finditer(read(f))}
    # "\(prefix).pause" in the app: the fixed tail an id is built around.
    tails = set()
    for d in APP_DIRS:
        for f in glob.glob(os.path.join(ROOT, d, "**/*.swift"), recursive=True):
            tails |= set(re.findall(r'"\\\([^)]*\)(\.[A-Za-z0-9.]+)"', read(f)))
    stale = sorted(q for q in queried
                   if q not in app_lits
                   and not any(a.endswith(".") and q.startswith(a) for a in app_lits)
                   and not any(q.endswith(t) for t in tails))

    for u in untested:
        print(f"UNTESTED SCREEN: {u}")
    for s in stale:
        print(f"STALE IDENTIFIER: {s} (queried by a UI test, gone from the app)")
    if untested or stale:
        print(f"test coverage gate FAILED: {len(untested)} untested screen(s), {len(stale)} stale identifier(s)")
        return 1
    print("test coverage gate OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
