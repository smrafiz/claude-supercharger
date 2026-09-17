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


cmd = _strip_pattern_operands(cmd)

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
