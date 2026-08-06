#!/usr/bin/env python3
"""Report command substitution inside multi-line double-quoted `-c "` blocks.

Such a block is a double-quoted bash string, so bash expands backticks and $(...)
in it before the interpreter runs. Illustration text — an example path in a comment —
therefore executes. See tests/test-interp-block-safety.sh for the incident.

Usage: lib-interp-scan.py <repo-root>
Prints one `path:line` per finding, nothing when clean. Lives in its own file so the
scan is not embedded in a heredoc inside the shell test that uses it — the first
version was, and its quoting collided with the decoy it had to build.
"""
import glob
import os
import re
import sys

OPEN = re.compile(r"-c\s+\"")
SUBST = re.compile(r"`|\$\(")


def scan(repo: str) -> list[str]:
    targets = sorted(
        glob.glob(os.path.join(repo, "hooks", "*.sh"))
        + glob.glob(os.path.join(repo, "lib", "*.sh"))
        + glob.glob(os.path.join(repo, "tools", "*.sh"))
    ) + [os.path.join(repo, "install.sh"), os.path.join(repo, "uninstall.sh")]

    hits = []
    for path in targets:
        if not os.path.isfile(path):
            continue
        inblock = False
        for i, line in enumerate(open(path, errors="ignore").read().split("\n"), 1):
            if not inblock:
                m = OPEN.search(line)
                # A single-line `-c "..."` opens AND closes on the same line and is
                # not a block. Missing that made the first version of this scan flag
                # every ordinary shell line following such a call — 35KB of noise.
                if m and line[m.end():].count('"') % 2 == 0:
                    inblock = True
                continue
            if '"' in line:
                inblock = False
                continue
            if SUBST.search(line):
                hits.append(f"{os.path.relpath(path, repo)}:{i}")
    return hits


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    for h in scan(root):
        print(h)
