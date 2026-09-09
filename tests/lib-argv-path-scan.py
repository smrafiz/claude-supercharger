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


# --- the LIST-in-an-env-var sibling (v4.0.46) --------------------------------
# Three channels, not two. MSYS rewrites a POSIX path into Windows spelling for
# a native program's ARGV, and for a recognised SINGLE-path env var — but NOT
# for the entries of a list held in one. Native Windows python then gets
# `/c/Users/...` and every open() raises.
#
# Measured before this rule was written: 64 env-prefixed `python3` call sites in
# the tree, 46 of which also open a path. Flagging those would be an FP machine,
# because a single path in an env var IS converted and is fine. The predicate
# that separates them is the SPLIT: a value that gets split into several paths
# is a list, and a list is what MSYS leaves alone. That narrowed 46 to 2, and
# both were live defects (tools/token-report.sh, tools/session-analytics.sh):
# each opened every entry inside a try/except, so on Git Bash they reported
# "no session data" on a healthy install rather than failing.
#
# Known limit: a file that calls `cygpath` is exempt, because converting the
# entries in bash before building the list is the fix. That is proximity-based
# and would wrongly exempt a file that converts one list and not another.
ENVPY = re.compile(r'^\s*((?:[A-Z_][A-Z0-9_]*="[^"]*"\s+)+)python3\b')
SPLIT = re.compile(r"\.split(?:lines)?\s*\(")


def scan_env_lists(repo, include_tests=False):
    targets = sorted(
        glob.glob(os.path.join(repo, "hooks", "*.sh"))
        + glob.glob(os.path.join(repo, "lib", "*.sh"))
        + glob.glob(os.path.join(repo, "tools", "*.sh"))
    )
    if include_tests:
        targets += sorted(glob.glob(os.path.join(repo, "tests", "*.sh")))
        targets = [t for t in targets
                   if os.path.basename(t) != "test-argv-path-scan.sh"]

    hits = []
    for path in targets:
        if not os.path.isfile(path):
            continue
        text = open(path, errors="ignore").read()
        if "cygpath" in text:
            continue
        lines = text.split("\n")
        for i, line in enumerate(lines):
            m = ENVPY.search(line)
            if not m:
                continue
            names = re.findall(r"([A-Z_][A-Z0-9_]*)=", m.group(1))
            block = "\n".join(lines[i:i + 80])
            if not OPENCALL.search(block):
                continue
            for n in names:
                # The split has to be applied to THIS env value, not merely to
                # appear somewhere in the block — blocks routinely split a
                # command string. Two spellings, both live in the tree:
                #   direct:   os.environ.get('N', '').split('\n')
                #   indirect: v = os.environ.get('N', '')  ...  v.splitlines()
                env_read = r"os\.environ(?:\.get\(\s*['\"]%s['\"][^)]*\)|\[\s*['\"]%s['\"]\s*\])" % (n, n)
                # NEWLINE splits only. A path list built by a bash loop is
                # newline-separated; a comma split is a list of VALUES, not
                # paths — lib/economy.sh splits ACTIVE_ROLES on ',' and opens a
                # single-path env var in the same block, which is correct and
                # was this rule's one false positive before the narrowing.
                sp = r"\s*\.(?:splitlines\s*\(|split\s*\(\s*['\"]\\n['\"])"
                if re.search(env_read + sp, block):
                    hits.append((path, i + 1, line.strip()))
                    break
                assigned = re.search(r"(\w+)\s*=\s*" + env_read, block)
                if assigned and re.search(
                        r"\b%s%s" % (re.escape(assigned.group(1)), sp), block):
                    hits.append((path, i + 1, line.strip()))
                    break
    return hits


OPENCALL = re.compile(
    r"(?:open|os\.path\.(?:exists|isfile|isdir|getmtime|getsize)"
    r"|os\.(?:listdir|stat|remove|rename)|glob\.glob|Path)\s*\("
)


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    with_tests = "--tests" in sys.argv
    found = scan(root, with_tests)
    for p, i, snip in found:
        print("%s:%d: %s" % (os.path.relpath(p, root), i, snip[:110]))
    env_found = scan_env_lists(root, with_tests)
    for p, i, snip in env_found:
        print("%s:%d: [env path LIST -> python] %s"
              % (os.path.relpath(p, root), i, snip[:90]))
    sys.exit(1 if (found or env_found) else 0)
