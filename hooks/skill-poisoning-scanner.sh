#!/usr/bin/env bash
# Claude Supercharger — Skill/Tool Poisoning Scanner
# Event: PreToolUse | Matcher: Skill
# Scans skill content for hidden shell commands, encoded payloads,
# and prompt injection patterns before the skill is loaded.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)

# v2.6.35: one python3 fork replaces 2 python3 (stdin parse) + bash for-loop
# `find` over 4 base dirs + ~10 grep -cE per skill file + 1 python3 per file
# for stego whitespace + 1 python3 for grep -c CRITICAL + 1 python3 for JSON
# wrap. Now: 1 python3 heredoc parses stdin, walks the 4 candidate dirs with
# pathlib, runs all 10 compiled regexes against each skill file's text,
# counts zero-width chars directly, emits the final JSON. Median 70ms → ~30ms.
RESULT=$(HOOK_INPUT="$_INPUT" PWD_DIR="$PWD" HOME_DIR="$HOME" HOOK_SUPPRESS="$HOOK_SUPPRESS" \
         python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys
from pathlib import Path

raw = os.environ.get('HOOK_INPUT', '')
home_dir = os.environ.get('HOME_DIR', '')
pwd_dir = os.environ.get('PWD_DIR', '')
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

skill = (data.get('tool_input') or {}).get('skill') or ''
if not skill:
    sys.exit(0)

cwd = data.get('cwd') or pwd_dir

# Find skill definition files. Match only the skill's own file, not random
# READMEs that happen to contain the skill name.
scan_paths = []
candidates = [
    Path(home_dir) / '.claude' / 'commands',
    Path(home_dir) / '.claude' / 'plugins',
    Path(cwd) / '.claude' / 'commands',
    Path(cwd) / '.claude' / 'plugins',
]
# Targeted globs only — rglob over ~/.claude/ walks 1000s of files.
# Three direct shapes: <base>/.../<skill>.md, <base>/.../<skill>/SKILL.md,
# <base>/.../<skill>/skill.md. Depth limit 6.
glob_patterns = (
    f'{skill}.md',
    f'*/{skill}.md',
    f'*/*/{skill}.md',
    f'*/*/*/{skill}.md',
    f'{skill}/SKILL.md',
    f'*/{skill}/SKILL.md',
    f'*/*/{skill}/SKILL.md',
    f'{skill}/skill.md',
    f'*/{skill}/skill.md',
    f'*/*/{skill}/skill.md',
)
for base in candidates:
    if not base.is_dir():
        continue
    for pat in glob_patterns:
        try:
            for p in base.glob(pat):
                if p.is_file():
                    scan_paths.append(p)
        except Exception:
            continue

if not scan_paths:
    sys.exit(0)

# (label, compiled regex, severity) — ordered by severity.
# v2.7.14: all patterns are re.IGNORECASE — previously case-sensitive against raw
# skill text, so UPPERCASE injection (e.g. "IGNORE PREVIOUS INSTRUCTIONS", "CURL ... | SH")
# evaded every check. This matches the three sibling scanners' case-insensitive behavior.
I = re.IGNORECASE
patterns = [
    ('base64 decode execution',       re.compile(r'base64\s+(?:-d|--decode)|atob\(|b64decode', I),                    'CRITICAL'),
    ('hidden eval/exec',              re.compile(r'\beval\b.*\$|exec\s*\(', I),                                       'CRITICAL'),
    ('curl pipe to shell',            re.compile(r'curl.*\|\s*(?:ba)?sh|wget.*\|\s*(?:ba)?sh', I),                    'CRITICAL'),
    ('environment exfiltration',      re.compile(r'env\b.*curl|printenv.*\||(?:API_KEY|SECRET|TOKEN|PASSWORD).*curl', I), 'CRITICAL'),
    ('reverse shell pattern',         re.compile(r'mkfifo|/dev/tcp/|nc\s+-[el]', I),                                  'CRITICAL'),
    ('hidden instruction override',   re.compile(r'ignore\s+(?:previous|above|all)\s+(?:instructions|rules)|disregard.*instructions|you\s+are\s+now', I), 'HIGH'),
    ('obfuscated variable expansion', re.compile(r'\$\{[A-Z_]*:.*:.*\}.*\$\{', I),                                    'HIGH'),
    ('credential file access',        re.compile(r'/etc/shadow|\.ssh/id_|\.aws/credentials|\.netrc|keychain', I),     'HIGH'),
    ('subprocess spawn',              re.compile(r'os\.system\(|subprocess\.(?:run|call|Popen)|child_process', I),    'MEDIUM'),
    ('file write outside project',    re.compile(r"open\(.*'/tmp|open\(.*'/var|>/etc/", I),                            'MEDIUM'),
]

ZERO_WIDTH = ('​', '‌', '‍', '﻿')

findings = []
critical = 0
for p in scan_paths:
    try:
        text = p.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    fname = p.name
    for label, regex, sev in patterns:
        n = len(regex.findall(text))
        if n:
            findings.append(f'{sev}: {label} ({n}x in {fname})')
            if sev == 'CRITICAL':
                critical += 1
    stego = sum(text.count(c) for c in ZERO_WIDTH)
    if stego:
        findings.append(f'HIGH: steganographic whitespace ({stego}x in {fname})')

if not findings:
    sys.exit(0)

body = '\n'.join(findings)
if critical:
    reason = f"Skill '{skill}' contains suspicious patterns:\n{body}\nReview the skill source before allowing execution."
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }))
else:
    msg = f"[SUPERCHARGER] Skill '{skill}' has suspicious patterns (non-blocking):\n{body}"
    print(json.dumps({'systemMessage': msg, 'suppressOutput': suppress}))
PYEOF
)

[ -z "$RESULT" ] && exit 0
printf '%s\n' "$RESULT"

# CRITICAL findings → emit deny + exit 2 (block). Otherwise just warn.
# json.dumps emits `"permissionDecision": "deny"` with a space after colon —
# match the literal "deny" token, not the punctuation.
if printf '%s' "$RESULT" | grep -q '"deny"'; then
  echo "[Supercharger] skill-poisoning-scanner: BLOCKED skill" >&2
  exit 2
fi
echo "[Supercharger] skill-poisoning-scanner: warned on skill" >&2
exit 0
