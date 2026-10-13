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

# v4.2.0: a name before `.env` (prod.env, backup.env) is a credential file too; the
# old left boundary let any word prefix through, drifting from safety-detect.py's
# _SENSITIVE_NAME_RE. `process.env` / `import.meta.env` are property accesses, not
# files: excluded by name (a word boundary would also drop prod.env).
ENV_FILE_RE = r"(^|[\s/=:<\'\"])(?!process\.env\b)([\w-]*)\.env(\.[a-zA-Z0-9_-]+)?(?=[\s\'\")\]]|$)"
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
# v4.2.0: `cp .env.example .env` creates a dotenv FROM a template: it reads only the
# template. It was denied as a .env read, on one of the commonest setup steps
# (dcg/flowrail allow corpora). Only cp with a template SOURCE; the target may
# be any dotenv name. `cp .env x` still reads secrets and still denies.
cmd = re.sub(r"\bcp\s+(-[a-zA-Z]+\s+)*['\"]?[\w./-]*\.env\.(example|template|sample|dist)['\"]?\s+"
             r"['\"]?[\w./-]*\.env(\.[\w-]+)?['\"]?(?=\s*($|[;&|\n]))", " ", cmd)

flagged = []
for m in re.finditer(ENV_FILE_RE, cmd):
    full = cmd[m.start():m.end()]
    token = re.search(r"[\w-]*\.env(\.[a-zA-Z0-9_-]+)?", full)
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
    r"\bgit\s+(show|diff|blame|cat-file)\s+",
    r"\b(sort|uniq|cut|diff|cmp|tac|rev|jq)\s+",
    # v4.2.0: byte/text dumpers read content exactly as cat does (self-audit: 4 of 26
    # spellings). NOT `source`/`.`: `set -a; . ./.env` is how projects run scripts
    # (43 of 608 real .env commands would have been denied), and it prints nothing.
    r"\b(od|xxd|strings|nl|hexdump|base64)\s+",
    r"\b(nano|vim?|emacs|code|subl|atom|gedit)\s+",
    r"\b(cp|mv|scp|rsync)\s+",
    r"\bgrep\s+",
    r"\bawk\s+",
    r"\bsed\s+",
    r"\btee\s+",
    r"\b(curl|wget)\s+.*\s-o\s+",
]
SELF_CONTAINED = [
    r"<\s*\.env\b",
    r">\s*\.env\b",
    r">>\s*\.env\b",
]

# v4.3.6: reader matching is per SEGMENT (the `.*` used to cross `&&`/`;`), and
# a segment that prints no value -- grep -c/-q/-l, cp/mv into another dotenv --
# is exempt. Keep in sync with _env_segments / _segment_prints_nothing in
# hooks/safety-detect.py (same code; see the rationale there).
def _env_segments(c):
    segs, cur, q, esc = [], [], None, False
    for ch in c:
        if esc:
            esc = False
        elif ch == "\\" and q != "'":
            esc = True
        elif q:
            if ch == q:
                q = None
        elif ch in "'\"":
            q = ch
        elif ch in ";&|\n":
            segs.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    if q:
        return [c]
    segs.append("".join(cur))
    return segs


def _segment_prints_nothing(seg):
    if "$(" in seg or "`" in seg or "<(" in seg:
        return False
    try:
        toks = shlex.split(seg)
    except ValueError:
        return False
    while toks and re.match(r"^[A-Za-z_]\w*=", toks[0]):
        toks = toks[1:]
    if not toks:
        return False
    tool = os.path.basename(toks[0].lstrip("("))
    if tool in ("grep", "egrep", "fgrep"):
        quiet = printing = False
        for t in toks[1:]:
            if t == "--":
                break
            if t.startswith("--"):
                name = t.split("=", 1)[0]
                quiet |= name in ("--count", "--quiet", "--silent",
                                  "--files-with-matches", "--files-without-match")
                printing |= name == "--only-matching"
            elif t.startswith("-"):
                for ch in t[1:]:
                    if ch in "cqlL":
                        quiet = True
                    elif ch == "o":
                        printing = True
                    elif ch in "efmABCdD":
                        break
        return quiet and not printing
    if tool in ("cp", "mv"):
        flags = [t for t in toks[1:] if t.startswith("-")]
        ops = [t for t in toks[1:] if not t.startswith("-")]
        if any(f.startswith("--target") or (not f.startswith("--") and "t" in f) for f in flags):
            return False
        if len(ops) < 2 or ":" in ops[-1]:
            return False
        dest = os.path.basename(ops[-1])
        return bool(re.fullmatch(r"[\w-]*\.env(\.[\w-]+)?", dest)) and not dest.endswith(SAFE_TEMPLATES)
    return False


triggered = False
for seg in _env_segments(cmd):
    if _segment_prints_nothing(seg):
        continue
    if any(re.search(pat + r".*\.env\b", seg, re.IGNORECASE) for pat in READ_WRITE_PREFIXES):
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
