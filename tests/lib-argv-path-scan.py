#!/usr/bin/env python3
"""Report FILE PATHS interpolated into a `python3 -c "..."` block.

The Windows rule, measured on a real runner (docs/WINDOWS-SUPPORT-PLAN.md §13.2):
a path reaching a program as an ARGUMENT is rewritten by MSYS into the Windows
spelling; a path INTERPOLATED into a `-c "..."` string is not. Native Windows
python then receives `/d/a/repo/x.json` — meaningless off MSYS — and raises
FileNotFoundError.

Every such site in this repo swallowed that error (`2>/dev/null || echo 0`), so
the failure was silent: hook-doctor reported "0 registered hooks" on a healthy
Windows install, config-health scored it broken, stop-verify never found a test
script. The fix is always the same shape: `open(sys.argv[1])` plus the path as a
real argument.

Usage: lib-argv-path-scan.py <repo-root> [--tests]
Prints one `path:line: snippet` per finding, nothing when clean.
"""
import glob
import os
import re
import sys

# open(...) is the only path-consuming call this repo uses inside -c blocks; the
# broader forms (os.path.isfile, glob.glob, Path) are scanned too so a new site
# in a different shape is still caught.
CALL = re.compile(
    r"(?:open|os\.path\.(?:exists|isfile|isdir|getmtime|getsize|join)"
    r"|os\.(?:listdir|walk|stat|chdir|remove|rename)|glob\.glob|Path)"
    r"\(\s*[\"']\$"
)
OPEN_BLOCK = re.compile(r"-c\s+\"")


def scan(repo, include_tests=False):
    targets = sorted(
        glob.glob(os.path.join(repo, "hooks", "*.sh"))
        + glob.glob(os.path.join(repo, "lib", "*.sh"))
        + glob.glob(os.path.join(repo, "tools", "*.sh"))
    ) + [os.path.join(repo, "install.sh"), os.path.join(repo, "uninstall.sh")]
    if include_tests:
        targets += sorted(glob.glob(os.path.join(repo, "tests", "*.sh")))
        # test-argv-path-scan.sh PLANTS a site on purpose, to prove this regex
        # still fires. Scanning it would report that decoy forever, so the one
        # file whose job is to fail the pattern is the one file exempt from it.
        targets = [t for t in targets
                   if os.path.basename(t) != "test-argv-path-scan.sh"]

    hits = []
    for path in targets:
        if not os.path.isfile(path):
            continue
        inblock = False
        for i, line in enumerate(open(path, errors="ignore").read().split("\n"), 1):
            if not inblock:
                m = OPEN_BLOCK.search(line)
                # A single-line -c "..." opens and closes on the same line; it is
                # still a real site, so scan it rather than skipping it.
                if m:
                    if line[m.end():].count('"') % 2 == 0:
                        inblock = True
                    if CALL.search(line):
                        hits.append((path, i, line.strip()))
                continue
            if CALL.search(line):
                hits.append((path, i, line.strip()))
            if line.rstrip().startswith('"') or re.match(r'^"\s', line):
                inblock = False
    return hits


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    with_tests = "--tests" in sys.argv
    found = scan(root, with_tests)
    for p, i, snip in found:
        print("%s:%d: %s" % (os.path.relpath(p, root), i, snip[:110]))
    sys.exit(1 if found else 0)
