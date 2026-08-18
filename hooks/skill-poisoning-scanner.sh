#!/usr/bin/env bash
# Claude Supercharger — Skill/Tool Poisoning Scanner
# Event: PreToolUse | Matcher: Skill
# Scans skill content for hidden shell commands, encoded payloads,
# and prompt injection patterns before the skill is loaded.

set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

# v2.26.35: fork-free stdin read. `$(cat)` forks /bin/cat in EVERY hook —
# ~1.8ms each, and 18 blocking hooks fire per Bash tool call. The trailing
# strip reproduces $(cat)'s newline handling so this is byte-identical.
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

# v2.6.35: one python3 fork replaces 2 python3 (stdin parse) + bash for-loop
# `find` over 4 base dirs + ~10 grep -cE per skill file + 1 python3 per file
# for stego whitespace + 1 python3 for grep -c CRITICAL + 1 python3 for JSON
# wrap. Now: 1 python3 heredoc parses stdin, walks the 4 candidate dirs with
# pathlib, runs all 10 compiled regexes against each skill file's text,
# counts zero-width chars directly, emits the final JSON. Median 70ms → ~30ms.
RESULT=$(HOOK_INPUT="$_INPUT" PWD_DIR="$PWD" HOME_DIR="$HOME" HOOK_SUPPRESS="$HOOK_SUPPRESS" \
         HOOKS_DIR_PY="$HOOKS_DIR" \
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

# v2.27.32: Git Bash hands paths POSIX-shaped (/d/a/repo). Native Windows python
# resolves a leading-slash path against the CURRENT DRIVE, so that becomes
# D:\\d\\a\\repo, every is_dir() below is False, the project-level base is
# skipped, and the scanner reports CLEAN having looked at nothing. Same
# normalisation as path-guard's _msys_path, which carries the runner
# measurements. Gated on os.name, so POSIX is provably untouched.
def _msys(x):
    if os.name != 'nt' or not x or not isinstance(x, str):
        return x
    _m = re.match(r'^/([A-Za-z])(/|$)', x)
    return (_m.group(1).upper() + ':\\' + x[3:].replace('/', '\\')) if _m else x

home_dir = _msys(home_dir)
cwd = _msys(cwd)


# Find skill definition files. Match only the skill's own file, not random
# READMEs that happen to contain the skill name.
scan_paths = []
# v2.26.39: 'skills' is the CANONICAL directory for a standalone skill — a bundle
# installed with `git clone && ./install.sh` lands in ~/.claude/skills/<name>/SKILL.md,
# not commands/ or plugins/. Omitting it meant the primary install path was never
# scanned: an identical poisoned SKILL.md was DENIED under plugins/ and commands/
# and PASSED under skills/. Found by scanning two real published bundles, not
# fixtures — every test staged into commands/ or plugins/, so the suite agreed
# with the bug. The globs and patterns below already worked; only the root was missing.
candidates = [
    Path(home_dir) / '.claude' / 'commands',
    Path(home_dir) / '.claude' / 'plugins',
    Path(home_dir) / '.claude' / 'skills',
    Path(cwd) / '.claude' / 'commands',
    Path(cwd) / '.claude' / 'plugins',
    Path(cwd) / '.claude' / 'skills',
]
# v2.7.54: skills are often invoked NAMESPACED ("plugin:skill"), but the file on
# disk is named by the BARE skill — a raw-name glob then matches nothing and the
# skill is never scanned (a full bypass for any plugin skill). Search the bare
# name (after the last ':' or '/') in addition to the raw invoked value.
skill_names = {skill}
_bare = re.split(r'[:/]', skill)[-1]
if _bare:
    skill_names.add(_bare)

# Targeted globs only — rglob over ~/.claude/ walks 1000s of files.
# Three direct shapes: <base>/.../<name>.md, <base>/.../<name>/SKILL.md,
# <base>/.../<name>/skill.md. Depth limit 6.
glob_patterns = []
for _nm in skill_names:
    glob_patterns += [
        f'{_nm}.md', f'*/{_nm}.md', f'*/*/{_nm}.md', f'*/*/*/{_nm}.md',
        f'{_nm}/SKILL.md', f'*/{_nm}/SKILL.md', f'*/*/{_nm}/SKILL.md',
        f'{_nm}/skill.md', f'*/{_nm}/skill.md', f'*/*/{_nm}/skill.md',
    ]

_seen = set()
for base in candidates:
    if not base.is_dir():
        continue
    for pat in glob_patterns:
        try:
            for p in base.glob(pat):
                if p.is_file():
                    rp = str(p.resolve())
                    if rp not in _seen:
                        _seen.add(rp)
                        scan_paths.append(p)
        except Exception:
            continue

if not scan_paths:
    sys.exit(0)

# v2.26.40: patterns moved to lib_poison_patterns.py, shared with
# agent-poisoning-scanner. Two scanners hunting "the same" injection markers
# WILL diverge the first time one is tightened alone — this project's signature
# security-hook bug class (v2.8.1-.11). Add a pattern THERE, not here.
# The list below is the fallback for a missing asset (v2.17.3: a hook died
# because the installer never copied hooks/*.py) and must stay in step.
_shared_scan = None
try:
    # v2.27.33: normalise first — HOOKS_DIR_PY is a CUSTOM env var and MSYS only
    # rewrites the ones it recognises, so on Git Bash this arrives POSIX-shaped,
    # Windows python resolves it against the current drive, and the import fails
    # silently into the fallback. Reported by the recon as the shared resolver
    # not being importable.
    sys.path.insert(0, _msys(os.environ.get('HOOKS_DIR_PY', '')))
    from lib_poison_patterns import scan_text as _shared_scan
except Exception:
    _shared_scan = None

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
    if _shared_scan is not None:
        _f, _c = _shared_scan(text, fname)
        findings.extend(_f)
        critical += _c
        continue
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
