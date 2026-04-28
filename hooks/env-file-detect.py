#!/usr/bin/env python3
"""Detect .env file access in a shell command.

Reads CMD env var, prints a one-line reason if a dangerous .env op is found,
otherwise prints nothing. Used by env-file-guard.sh.
"""
import os
import re
import sys

cmd = os.environ.get("CMD", "")

ENV_FILE_RE = r"(^|[\s/=\'\"])\.env(\.[a-zA-Z0-9_-]+)?(?=[\s\'\")\]]|$)"
SAFE_TEMPLATES = (".env.example", ".env.template", ".env.sample", ".env.dist")

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
