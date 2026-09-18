#!/usr/bin/env python3
"""Detect .env file access in a shell command.

Reads CMD env var, prints a one-line reason if a dangerous .env op is found,
otherwise prints nothing. Used by env-file-guard.sh.
"""
import os
import re
import shlex
import sys

cmd = os.environ.get("CMD", "")

ENV_FILE_RE = r"(^|[\s/=\'\"])\.env(\.[a-zA-Z0-9_-]+)?(?=[\s\'\")\]]|$)"
SAFE_TEMPLATES = (".env.example", ".env.template", ".env.sample", ".env.dist")

# v4.1.6 (F1): a search PATTERN is not a path. Searching docs FOR the dotenv
# name opens no such file, and denying it is the false-positive shape upstream
# filed eight issues about (#91681, #91778 and siblings). Keep in sync with
# hooks/safety-detect.py, which carries the same pair for the Bash channel --
# this file is the fork-free copy env-file-guard.sh execs, and the two guards
# drifting apart is what made the defect visible on one channel only.
PATTERN_READER_INVOCATION_RE = re.compile(
    r"\b(grep|egrep|fgrep|rg|ag|ack|sed|awk|gawk)\b(\s+)([\S\s]*?)(?=$|\||;|&&)"
)


def _drop_first_operand(args: str) -> str:
    """Remove the leading non-flag token (the pattern/script) from an arg string."""
    try:
        toks = shlex.split(args)
    except ValueError:
        # Unbalanced quotes: scan untouched. Failing toward MORE scanning is the
        # only safe direction -- dropping tokens we failed to parse would hide
        # real filenames.
        return args
    out, dropped = [], False
    for t in toks:
        if not dropped and not t.startswith("-"):
            dropped = True
            continue
        out.append(t)
    return " ".join(out)


def _strip_pattern_operands(c: str) -> str:
    """Drop each pattern-reader's leading pattern/script operand from a command."""
    return PATTERN_READER_INVOCATION_RE.sub(
        lambda m: m.group(1) + m.group(2) + _drop_first_operand(m.group(3)), c
    )


# v4.1.7: metadata text is prose, not a path. `git commit -m "...dotenv..."`,
# `git tag -m`, `gh pr create --body` carry human text that legitimately names
# credential files — release notes and audit write-ups in this repo do it
# constantly. env-file-guard.sh used to pre-filter these with a start-anchored
# `^\s*(git commit|...)` that exited 0 for the WHOLE command; it missed every
# compound (`cd repo && git commit -m '...'` was denied on its own message) and
# exempted anything chained after one (`git commit -m x && cat <secret>` rode
# along). That pre-filter is gone; this is its replacement, segment-scoped.
#
# A segment containing a substitution is NOT dropped: `$(...)` and backticks
# execute, so `git commit -m "$(cat <secret>)"` is a real read and must stay
# visible to the detector. Keep in sync with _strip_metadata_text in
# hooks/safety-detect.py — these two files drifting apart is exactly what left
# the pattern-operand defect live on one channel only.
METADATA_TEXT_RE = re.compile(
    r"(?:^|(?<=[;&|]))"
    r"(\s*(?:git\s+(?:commit|tag)|gh\s+(?:pr|issue|release)\s+create)\b[^;&|]*)"
)


def _strip_metadata_text(c: str) -> str:
    """Drop metadata-text segments (commit/tag/PR bodies) from a command."""
    def _drop(m):
        seg = m.group(1)
        return seg if ("$(" in seg or "`" in seg) else " "
    return METADATA_TEXT_RE.sub(_drop, c)


cmd = _strip_metadata_text(_strip_pattern_operands(cmd))

flagged = []
for m in re.finditer(ENV_FILE_RE, cmd):
    full = cmd[m.start():m.end()]
    token = re.search(r"\.env(\.[a-zA-Z0-9_-]+)?", full)
    if not token:
        continue
    name = token.group(0)
    if name in SAFE_TEMPLATES:
        continue
    flagged.append(name)

if not flagged:
    sys.exit(0)

READ_WRITE_PREFIXES = [
    r"\b(cat|less|more|head|tail|bat)\s+",
    r"\b(nano|vim?|emacs|code|subl|atom|gedit)\s+",
    r"\b(cp|mv|scp|rsync)\s+",
    r"\bgrep\s+",
    r"\bawk\s+",
    r"\bsed\s+",
    r"\btee\s+",
    r"\b(curl|wget)\s+.*\s-o\s+",
]
SELF_CONTAINED = [
    r">\s*\.env\b",
    r">>\s*\.env\b",
]

triggered = False
for pat in READ_WRITE_PREFIXES:
    if re.search(pat + r".*\.env\b", cmd, re.IGNORECASE):
        triggered = True
        break

if not triggered:
    for pat in SELF_CONTAINED:
        if re.search(pat, cmd, re.IGNORECASE):
            triggered = True
            break

if triggered:
    name = flagged[0] if flagged else ".env"
    print(f".env file access ({name}) — credentials likely present")
