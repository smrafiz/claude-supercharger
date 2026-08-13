#!/usr/bin/env bash
# Claude Supercharger — Workflow Script Poisoning Scanner
# Event: PreToolUse | Matcher: Workflow
#
# The Agent channel has three guards (agent-gate, agent-poisoning-scanner,
# cost-forecast). Workflow — the SAME capability with a far larger blast radius —
# had none. Found by the coverage diff on 2026-08-09: of 42 tools the harness
# exposes, Workflow was among 28 with no PreToolUse guard beyond the two universal
# hooks, and it is the only one of those that spawns subagents.
#
# Why that asymmetry matters. One Agent call spawns one subagent and is scanned.
# One Workflow call runs a script that may spawn up to 1000 (4096 items per
# parallel()/pipeline() call), each with a prompt the script itself supplies —
# and nothing inspected the script. So the cheapest way to run an unscanned agent
# prompt was to stop using the guarded channel. This is the cross-channel parity
# drift class (v2.8.1-.11) appearing on a channel that was simply never wired up.
#
# What is scanned, in the order the tool resolves its input:
#   1. an inline `script`
#   2. `scriptPath`, a script file on disk (also the resume/iterate path)
#   3. `name`, a saved workflow in .claude/workflows/
# plus every agent definition named by an `agentType:` in that script — the exact
# files agent-poisoning-scanner reads when the Agent channel is used directly.
# Resolution and patterns both come from lib_poison_patterns so the two channels
# cannot disagree about what a poisoned definition looks like.
#
# Severity split matches its two siblings exactly:
#   CRITICAL -> deny. base64-exec, curl|shell, reverse shell, env exfiltration.
#   HIGH/MEDIUM -> warn. Real workflow scripts mention subprocesses and paths;
#   blocking those trains users to disable the hook.
#
# Disable: SUPERCHARGER_WORKFLOW_GUARD=0
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "workflow-guard" && exit 0
[ "${SUPERCHARGER_WORKFLOW_GUARD:-1}" = "0" ] && exit 0

# Fork-free stdin read (v2.26.35 convention).
IFS= read -r -d '' -t "${SUPERCHARGER_STDIN_TIMEOUT_S:-5}" _INPUT || [ $? -le 128 ] || _INPUT=""; _INPUT="${_INPUT%"${_INPUT##*[!$'\n']}"}"

RESULT=$(HOOK_INPUT="$_INPUT" PWD_DIR="$PWD" HOME_DIR="$HOME" HOOK_SUPPRESS="$HOOK_SUPPRESS" \
         HOOKS_DIR="$HOOKS_DIR" python3 <<'PYEOF' 2>/dev/null
import json, os, re, sys
from pathlib import Path

raw = os.environ.get('HOOK_INPUT', '')
home_dir = os.environ.get('HOME_DIR', '')
pwd_dir = os.environ.get('PWD_DIR', '')
hooks_dir = os.environ.get('HOOKS_DIR', '')
suppress = os.environ.get('HOOK_SUPPRESS', 'false').lower() in ('true', '1', 'yes')

try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

ti = data.get('tool_input') or {}
cwd = data.get('cwd') or pwd_dir

# Shared assets, with the built-in fallback every consumer owes this module: a
# hook that dies because an asset was not deployed is worse than one that scans
# with the local copy (v2.17.3 shipped exactly that failure).
sys.path.insert(0, hooks_dir)
try:
    from lib_poison_patterns import scan_text, resolve_agent_defs
except Exception:
    I = re.IGNORECASE
    _P = [
        ('base64 decode execution', re.compile(r'base64\s+(?:-d|--decode)|atob\(|b64decode', I), 'CRITICAL'),
        ('hidden eval/exec',        re.compile(r'\beval\b.*\$|exec\s*\(', I),                    'CRITICAL'),
        ('curl pipe to shell',      re.compile(r'curl.*\|\s*(?:ba)?sh|wget.*\|\s*(?:ba)?sh', I), 'CRITICAL'),
        ('environment exfiltration', re.compile(r'env\b.*curl|printenv.*\||(?:API_KEY|SECRET|TOKEN|PASSWORD).*curl', I), 'CRITICAL'),
        ('reverse shell pattern',   re.compile(r'mkfifo|/dev/tcp/|nc\s+-[el]', I),               'CRITICAL'),
        ('hidden instruction override', re.compile(r'ignore\s+(?:previous|above|all)\s+(?:instructions|rules)|disregard.*instructions|you\s+are\s+now', I), 'HIGH'),
    ]
    _ZW = ('​', '‌', '‍', '﻿')

    def scan_text(text, fname):
        f, c = [], 0
        for label, rx, sev in _P:
            n = len(rx.findall(text))
            if n:
                f.append('%s: %s (%dx in %s)' % (sev, label, n, fname))
                if sev == 'CRITICAL':
                    c += 1
        z = sum(text.count(ch) for ch in _ZW)
        if z:
            f.append('HIGH: steganographic whitespace (%dx in %s)' % (z, fname))
        return f, c

    def resolve_agent_defs(agent, home, cwd_):
        return []

# ── Gather the script text ────────────────────────────────────────────────────
# Precedence mirrors the tool's own: scriptPath wins over script wins over name.
sources = []

script_path = ti.get('scriptPath')
if isinstance(script_path, str) and script_path.strip():
    p = Path(os.path.expanduser(script_path.strip()))
    if not p.is_absolute():
        p = Path(cwd) / p
    try:
        if p.is_file():
            sources.append((p.read_text(encoding='utf-8', errors='replace'), p.name))
    except Exception:
        pass

inline = ti.get('script')
if isinstance(inline, str) and inline.strip():
    sources.append((inline, '<inline script>'))

# A saved workflow is a file the agent did not have to author in this turn, which
# makes it the persistent-on-disk case the sibling scanners exist for.
name = ti.get('name')
if isinstance(name, str) and name.strip():
    safe = re.split(r'[:/\\]', name.strip())[-1]
    if safe:
        for base in (Path(cwd) / '.claude' / 'workflows',
                     Path(home_dir) / '.claude' / 'workflows'):
            if not base.is_dir():
                continue
            for pat in ('%s.js' % safe, '%s.mjs' % safe, '%s.md' % safe, '%s' % safe):
                try:
                    for f in base.glob(pat):
                        if f.is_file():
                            sources.append((f.read_text(encoding='utf-8', errors='replace'), f.name))
                except Exception:
                    continue

# v2.26.81: `args` is passed to the script VERBATIM as the global `args`, and the
# tool's own canonical pattern for a parameterised workflow is agent(args.task).
# So a payload placed there reaches an agent prompt having been scanned by nothing
# — the exact "use the unguarded channel" move this hook exists to close, one
# field over. Found by red-teaming the hook after shipping it; the script arm was
# blocking while args sailed past.
# Serialised rather than walked: args may be a string, list or nested object, and
# every leaf of it is prompt material.
_args = ti.get('args')
if _args is not None:
    try:
        sources.append((_args if isinstance(_args, str) else json.dumps(_args), '<args>'))
    except Exception:
        pass

if not sources:
    sys.exit(0)

findings, critical = [], 0
for text, label in sources:
    f, c = scan_text(text, label)
    findings.extend(f)
    critical += c

# ── Agent definitions the script names ────────────────────────────────────────
# An agentType option resolves through the same registry the Agent tool uses, so
# the definition is loaded and followed. Reaching it via Workflow must not skip
# the scan that reaching it via Agent performs.
#
# QUOTING, load-bearing: this heredoc sits inside RESULT=$(...), and bash scans
# the body for the closing paren BEFORE handing it to python. An UNMATCHED quote
# character opens a quoted region in that scan, the PYEOF terminator is missed,
# and the rest of the body is parsed as SHELL — python then gets a truncated
# script. Measured, not assumed: a body line of  a = ['"]  (one single, one
# double, each unmatched) breaks it, while  a = '''q'''  (six, all paired) is
# fine. It is matching that matters, not the count — the body below has an odd
# TOTAL of single quotes and parses correctly.
#
# The first draft wrote this pattern as r'''agentType...['"]...''' and died with
# "syntax error near unexpected token" 44 lines further down, which is why the
# regex is spelled with paired quotes and a backreference instead. Same family as
# the "no backticks in a -c block" rule.
# v2.26.81: +backtick. A template literal is still a LITERAL, so agentType:`x` was
# a free bypass of the arm below. A COMPUTED agentType (const t="x"; {agentType:t})
# stays out of reach — it is not statically resolvable, and that is a documented
# limit rather than a gap to paper over.
_AT_RX = re.compile("agentType\\s*:\\s*(['\"`])([^'\"`]{1,120})\\1")
agent_types = set()
for text, _ in sources:
    for m in _AT_RX.finditer(text):
        agent_types.add(m.group(2))

seen_defs = set()
for at in sorted(agent_types):
    for p in resolve_agent_defs(at, home_dir, cwd):
        try:
            st = p.stat()
            key = (st.st_dev, st.st_ino)
        except OSError:
            key = str(p)
        if key in seen_defs:
            continue
        seen_defs.add(key)
        try:
            text = p.read_text(encoding='utf-8', errors='replace')
        except Exception:
            continue
        f, c = scan_text(text, '%s (agentType %s)' % (p.name, at))
        findings.extend(f)
        critical += c

if not findings:
    sys.exit(0)

body = '\n'.join(findings)
if critical:
    reason = ("Workflow script contains suspicious patterns:\n%s\n"
              "A workflow can spawn up to 1000 subagents, so review the script "
              "before allowing it to run." % body)
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }))
else:
    msg = "[SUPERCHARGER] Workflow script has suspicious patterns (non-blocking):\n%s" % body
    print(json.dumps({'systemMessage': msg, 'suppressOutput': suppress}))
PYEOF
)

[ -z "$RESULT" ] && exit 0
printf '%s\n' "$RESULT"

# CRITICAL -> deny + exit 2 (block). Otherwise warn only. Match the literal
# "deny" token, not the punctuation: json.dumps emits `"permissionDecision": "deny"`.
if printf '%s' "$RESULT" | grep -q '"deny"'; then
  echo "[Supercharger] workflow-guard: BLOCKED workflow" >&2
  exit 2
fi
echo "[Supercharger] workflow-guard: warned on workflow" >&2
exit 0
