#!/usr/bin/env python3
"""Unified safety detector — combines shell-wrapper, env-file, and exfiltration
detection in a single Python process. Called by safety.sh.

Reads CMD env var. Prints first-match reason on stdout, then exits.
Empty output = clean.
"""
from __future__ import annotations

import os
import re
import sys

cmd = os.environ.get("CMD", "")
if not cmd:
    sys.exit(0)


# ──────────────────────────────────────────────────────────────────────────
# 1. Shell wrapper detection (python -c / node -e / perl -e / ruby -e / dash -c / ksh -c / fish -c)
# ──────────────────────────────────────────────────────────────────────────

_PATH_CONT = r"(?![/A-Za-z0-9._-])"
_DANGEROUS_TARGET = (
    r"(?:/" + _PATH_CONT
    + r"|/\*"
    + r"|~" + _PATH_CONT
    + r"|\$HOME"
    + r"|\.\." + _PATH_CONT
    + r")"
)
_WRAPPER_DESTRUCT = [
    r"rm\s+-[a-zA-Z]*[rR][a-zA-Z]*[fF]?\s+" + _DANGEROUS_TARGET,
    r"rm\s+-[a-zA-Z]*[fF][a-zA-Z]*[rR]?\s+" + _DANGEROUS_TARGET,
    r"git\s+reset\s+--hard",
    r"git\s+clean\s+-[fdFD]+",
    r"git\s+checkout\s+\.",
    r"git\s+push\s+.*--force.*\b(main|master)\b",
    r"mkfs\.",
    r"dd\s+if=",
    r">\s*/dev/sd",
    r"chmod\s+(-R\s+)?777\s+/",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:",
]
_INTERPRETERS = [
    (r"(?:^|[\s;&|])python[23]?(?:\.\d+)?\s+-c\s+", "python -c"),
    (r"(?:^|[\s;&|])(?:perl|ruby)\s+-e\s+", "perl/ruby -e"),
    (r"(?:^|[\s;&|])node\s+-e\s+", "node -e"),
    (r"(?:^|[\s;&|])(?:dash|ksh|fish)\s+-c\s+", "dash/ksh/fish -c"),
]


def check_shell_wrapper(c: str) -> str | None:
    for wrap_re, label in _INTERPRETERS:
        m = re.search(wrap_re, c)
        if not m:
            continue
        inner = c[m.end():]
        if inner and inner[0] in ("'", '"'):
            inner = inner[1:]
        for p in _WRAPPER_DESTRUCT:
            if re.search(p, inner, re.IGNORECASE):
                return f"destructive command hidden in {label} wrapper"
    return None


# ──────────────────────────────────────────────────────────────────────────
# 2. .env file access detection
# ──────────────────────────────────────────────────────────────────────────

_ENV_FILE_RE = r"(^|[\s/=\'\"])\.env(\.[a-zA-Z0-9_-]+)?(?=[\s\'\")\]]|$)"
_SAFE_TEMPLATES = (".env.example", ".env.template", ".env.sample", ".env.dist")

# Extended sensitive file/dir patterns (claudekit-inspired)
_SENSITIVE_NAME_RE = re.compile(
    r"(?i)(?:"
    r"\.env(?:\.[a-zA-Z0-9_-]+)?"
    r"|\.npmrc|\.pypirc|\.pgpass|\.my\.cnf|\.netrc|\.authinfo(?:\.gpg)?|\.git-credentials"
    r"|id_rsa[a-zA-Z0-9_.-]*|id_dsa[a-zA-Z0-9_.-]*|id_ecdsa[a-zA-Z0-9_.-]*|id_ed25519[a-zA-Z0-9_.-]*"
    r"|[\w.*-]+\.(?:ppk|pem|key|crt|cer|p12|pfx)"
    r"|wallet\.dat|wallet\.json|[\w.*-]+\.wallet"
    r"|secrets?\.[a-zA-Z0-9_-]+|credentials\.[a-zA-Z0-9_-]+"
    r")"
)


def check_sensitive_read(c: str) -> str | None:
    """Block direct reader/editor commands targeting sensitive files."""
    # Skip safe metadata commits/PRs that may mention sensitive names in text
    if re.match(r"^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b", c):
        return None

    # Reader/editor commands followed by a sensitive filename token
    READER = r"\b(?:cat|less|more|head|tail|bat|nano|vim?|emacs|code|subl|atom|gedit|grep|awk|sed|tee|xxd|hexdump|od)\b"
    # Capture the args of a reader command and search for sensitive names within
    for m in re.finditer(READER + r"\s+([\S\s]*?)(?:$|\||;|&&|\|\|)", c):
        args = m.group(1)
        sm = _SENSITIVE_NAME_RE.search(args)
        if sm:
            return f"sensitive file access: {sm.group(0)} — credentials likely present"
    return None


def check_pipeline_bypass(c: str) -> str | None:
    """Detect pipeline-based bypasses of direct file-read protections.

    Patterns:
      echo|printf <SENSITIVE> | xargs cat
      find ... -name <SENSITIVE> | xargs cat
      find ... -name <SENSITIVE> -exec cat {} \\;
      ls <SENSITIVE> | xargs cat
    """
    # echo/printf <SENSITIVE> | ... | xargs cat
    for m in re.finditer(r"\b(?:echo|printf|ls)\b\s+([\"\']?[\w./*-]+[\"\']?)", c):
        arg = m.group(1).strip("'\"")
        if not _SENSITIVE_NAME_RE.search(arg):
            continue
        tail = c[m.end():]
        if re.search(r"\|[\s\S]*?\bxargs\b[\s\S]*?\bcat\b", tail):
            return f"pipeline bypass: {m.group(0).strip()} | xargs cat — sensitive file exfiltration"
        if re.search(r"\|[\s\S]*?\b(cat|less|more|head|tail|nc|netcat|curl|wget)\b", tail):
            return f"pipeline bypass: piping sensitive name into reader/network tool"

    # find ... -name/-iname/-regex SENSITIVE ... | xargs cat OR -exec cat
    find_re = re.compile(
        r"\bfind\b[\s\S]*?-(?:name|iname|regex|iregex)\s+(?:\"([^\"]+)\"|'([^']+)'|(\S+))",
        re.IGNORECASE,
    )
    for m in find_re.finditer(c):
        pat = m.group(1) or m.group(2) or m.group(3) or ""
        if not _SENSITIVE_NAME_RE.search(pat):
            continue
        # Check if find result is piped to a reader or used in -exec cat
        find_tail = c[m.start():]
        if re.search(r"-exec\s+(cat|less|more|head|tail|nc|netcat|curl|wget)\b", find_tail):
            return f"find bypass: -exec reader on sensitive pattern '{pat}'"
        if re.search(r"\|[\s\S]*?\b(xargs|cat|less|more|head|tail|nc|netcat|curl|wget)\b", find_tail):
            return f"find bypass: piping sensitive results to reader/network tool ('{pat}')"
    return None
_ENV_READ_WRITE_PREFIXES = [
    r"\b(cat|less|more|head|tail|bat)\s+",
    r"\b(nano|vim?|emacs|code|subl|atom|gedit)\s+",
    r"\b(cp|mv|scp|rsync)\s+",
    r"\bgrep\s+",
    r"\bawk\s+",
    r"\bsed\s+",
    r"\btee\s+",
    r"\b(curl|wget)\s+.*\s-o\s+",
]
_ENV_SELF_CONTAINED = [
    r">\s*\.env\b",
    r">>\s*\.env\b",
]


def check_env_file(c: str) -> str | None:
    # Allow safe metadata commits/PRs that mention .env in text only
    if re.match(r"^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b", c):
        return None

    flagged = []
    for m in re.finditer(_ENV_FILE_RE, c):
        token = re.search(r"\.env(\.[a-zA-Z0-9_-]+)?", c[m.start():m.end()])
        if not token:
            continue
        name = token.group(0)
        if name in _SAFE_TEMPLATES:
            continue
        flagged.append(name)

    if not flagged:
        return None

    for pat in _ENV_READ_WRITE_PREFIXES:
        if re.search(pat + r".*\.env\b", c, re.IGNORECASE):
            return f".env file access ({flagged[0]}) — credentials likely present"
    for pat in _ENV_SELF_CONTAINED:
        if re.search(pat, c, re.IGNORECASE):
            return f".env file access ({flagged[0]}) — credentials likely present"
    return None


# ──────────────────────────────────────────────────────────────────────────
# 3. Data exfiltration detection (DNS tunnels + cloud upload of secrets)
# ──────────────────────────────────────────────────────────────────────────

_DNS_EXFIL_TOOLS = [
    r"\bdnscat2?\b",
    r"\biodined?\b",
    r"\bdns2tcp\b",
    r"\bdnsexfil\b",
]
_SENSITIVE_PATHS = [
    r"\.env\b(?!\.example|\.template|\.sample|\.dist)",
    r"~/\.ssh\b|/\.ssh/",
    r"~/\.aws\b|/\.aws/",
    r"~/\.gnupg\b",
    r"/etc/shadow\b",
    r"/etc/passwd\b",
    r"/etc/sudoers\b",
    r"\.pem\b",
    r"id_rsa\b|id_ed25519\b|id_ecdsa\b",
    r"\.kube/config\b",
    r"\.npmrc\b",
    r"\.pgpass\b",
    r"credentials\b",
]
_CLOUD_UPLOADS = [
    (r"\baws\s+s3\s+(cp|mv|sync)\b", "aws s3 upload"),
    (r"\bgsutil\s+(cp|mv|rsync)\b", "gsutil upload"),
    (r"\baz\s+storage\s+(blob|file)\s+upload\b", "az storage upload"),
    (r"\bazcopy\s+copy\b", "azcopy upload"),
    (r"\brclone\s+(copy|sync|move)\b", "rclone upload"),
    (r"\bs3cmd\s+put\b", "s3cmd upload"),
]
_NETWORK_UPLOADS = [
    r"\bcurl\b.*(?:--data-binary|--upload-file|-F\s|--form\b|-d\s)",
    r"\bwget\b.*--post-file=",
    r"\bnc\b.*(?:-c|<|<<)",
    r"\bnetcat\b.*(?:-c|<|<<)",
]


def check_exfiltration(c: str) -> str | None:
    for pat in _DNS_EXFIL_TOOLS:
        if re.search(pat, c):
            return "DNS tunneling tool detected — used for covert data exfiltration"

    for upload_re, label in _CLOUD_UPLOADS:
        if not re.search(upload_re, c):
            continue
        for sens in _SENSITIVE_PATHS:
            if re.search(sens, c):
                return f"{label} of sensitive source — possible credential/key exfiltration"

    for upload_re in _NETWORK_UPLOADS:
        if not re.search(upload_re, c):
            continue
        for sens in _SENSITIVE_PATHS:
            if re.search(sens, c):
                return "network upload of sensitive source — possible credential exfiltration"
    return None


# ──────────────────────────────────────────────────────────────────────────
# Main: run checks in order, first match wins. Categories may be disabled
# via $DISABLED_CATS (newline-separated, from
# ~/.claude/supercharger/scope/.disabled-security-categories).
# Categories: shell_wrapper, env_files, exfiltration
# ──────────────────────────────────────────────────────────────────────────

disabled = set((os.environ.get("DISABLED_CATS", "") or "").split())

if "shell_wrapper" not in disabled:
    r = check_shell_wrapper(cmd)
    if r:
        print(r)
        sys.exit(0)

if "env_files" not in disabled:
    r = check_env_file(cmd)
    if r:
        print(r)
        sys.exit(0)

if "sensitive_read" not in disabled:
    r = check_sensitive_read(cmd)
    if r:
        print(r)
        sys.exit(0)

if "pipeline_bypass" not in disabled:
    r = check_pipeline_bypass(cmd)
    if r:
        print(r)
        sys.exit(0)

if "exfiltration" not in disabled:
    r = check_exfiltration(cmd)
    if r:
        print(r)
        sys.exit(0)
