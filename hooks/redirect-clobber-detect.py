#!/usr/bin/env python3
"""Redirect-clobber detector — called by redirect-clobber-guard.sh.

Reads CMD (the Bash command) and PROJECT_DIR (cwd) from the environment. Extracts
files that a truncating clobber (`>` not `>>`, `sed -i`, `tee` no -a, `dd of=`,
`truncate`) would overwrite, and prints the FIRST one that is git-TRACKED. Empty
output = nothing to ask about.
"""
import os
import re
import shlex
import subprocess
import sys

cmd = os.environ.get("CMD", "")
proj = os.environ.get("PROJECT_DIR", "") or "."
if not cmd:
    sys.exit(0)

EXCLUDE_DIRS = (
    "dist/", "build/", ".next/", ".nuxt/", ".output/", "node_modules/",
    "coverage/", ".venv/", "__pycache__/", "vendor/", "target/",
)


def excluded(p):
    n = p.replace("\\", "/")
    if n == "/dev/null" or n.startswith("/dev/"):
        return True
    if any(seg in n for seg in EXCLUDE_DIRS):
        return True
    # lockfiles are handled by lockfile-integrity-guard; skip generated/minified.
    if n.endswith((".lock", ".min.js", ".min.css", ".map")):
        return True
    return False


def segments(c):
    return re.split(r";|&&|\|\||\||&", c)


cands = []

# 1) stdout truncating redirect: `>` not `>>`, not `2>`/`1>`, not `&>`/`>&`.
# v2.22.10: also catch an fd-qualified truncate (`1> f`) and clobber-force (`>| f`).
# `(?![>&])` still excludes append `>>` and fd-dup `>&`/`2>&1`; `\|?` consumes the
# clobber-force pipe. (Only tracked files are ever surfaced, so `2> untracked.log`
# stays silent.)
for m in re.finditer(r"""(?<![>&])>(?![>&])\|?\s*("[^"]+"|'[^']+'|[^\s;&|<>()]+)""", cmd):
    cands.append(m.group(1))

# 2) sed -i / --in-place: file args are the trailing non-flag tokens (the FIRST
#    non-flag is the s/…/…/ script; the rest are files).
for seg in segments(cmd):
    if re.search(r"(^|\s)sed(\s|$)", seg) and re.search(r"(^|\s)(-i\b|--in-place)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        if "sed" in toks:
            nonflag = [t for t in toks[toks.index("sed") + 1:] if not t.startswith("-")]
            cands.extend(nonflag[1:])

# 3) tee (no -a/--append): non-flag args are target files.
for seg in segments(cmd):
    if re.search(r"(^|\s)tee(\s|$)", seg) and not re.search(r"(^|\s)(-a\b|--append)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        if "tee" in toks:
            cands.extend(t for t in toks[toks.index("tee") + 1:] if not t.startswith("-"))

# 4) dd of=FILE
for m in re.finditer(r"""\bdd\b[^;&|]*?\bof=("[^"]+"|'[^']+'|[^\s;&|]+)""", cmd):
    cands.append(m.group(1))

# 5) truncate … FILE (last non-flag token of the truncate segment).
for seg in segments(cmd):
    if re.search(r"(^|\s)truncate(\s|$)", seg):
        try:
            toks = shlex.split(seg)
        except Exception:
            toks = seg.split()
        files = [t for t in toks if not t.startswith("-") and t != "truncate"]
        if files:
            cands.append(files[-1])

seen = set()
for raw in cands:
    p = raw.strip().strip('"').strip("'")
    if not p or p in seen:
        continue
    seen.add(p)
    if excluded(p):
        continue
    try:
        r = subprocess.run(
            ["git", "-C", proj, "ls-files", "--error-unmatch", "--", p],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
        )
    except Exception:
        continue
    if r.returncode == 0:
        print(p)
        break
