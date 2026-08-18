#!/usr/bin/env bash
# Claude Supercharger — Agent Definition Poisoning Scanner
# Event: PreToolUse | Matcher: Agent
#
# Agent definitions (~/.claude/agents/<name>.md) are instructions Claude follows.
# A poisoned one is a prompt-injection payload with a persistent home on disk:
# it survives sessions, is loaded by name, and nothing here inspected it.
#
# skill-poisoning-scanner has guarded the equivalent file for SKILLS since
# v2.7.x. Agent definitions had NO scanner at all — agent-router.sh reads them
# at UserPromptSubmit to route, but reading is not inspecting. This closes the
# same door one directory over, using the same patterns via lib_poison_patterns.
#
# Found while fixing v2.26.39, where skill-poisoning-scanner turned out never to
# have scanned ~/.claude/skills/. Both bugs are the same shape: a guard whose
# idea of "where the files are" did not match where they actually were.
#
# Severity split (deliberate, matches the skill scanner):
#   CRITICAL -> deny. base64-exec, curl|shell, reverse shell, env exfiltration.
#   HIGH/MEDIUM -> warn. Legitimate agent definitions DO mention credentials
#   paths and subprocess calls; blocking those trains users to disable the hook.
#
# Disable: SUPERCHARGER_AGENT_POISON_GUARD=0
set -euo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "agent-poisoning-scanner" && exit 0
[ "${SUPERCHARGER_AGENT_POISON_GUARD:-1}" = "0" ] && exit 0

# v2.26.35: fork-free stdin read (no $(cat) fork).
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
# Same resolution order as agent-gate.sh — subagent_type is the real field;
# the others are older/alternate spellings kept so both hooks agree on identity.
agent = ti.get('subagent_type') or ti.get('agent') or ti.get('name') or ''
if not agent or not isinstance(agent, str):
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


# Shared pattern set. Falls back to a built-in copy if the asset is missing —
# v2.17.3 shipped a hook whose python asset the installer never copied, and the
# hook died with "No stderr output" instead of degrading.
# v2.27.33: normalise BEFORE putting it on sys.path. HOOKS_DIR is a CUSTOM
# env var, and MSYS only rewrites the ones it recognises — so this arrives
# POSIX-shaped (/d/a/repo/hooks), Windows python resolves it against the
# current drive, the directory does not exist, and the import below fails
# silently into the inline fallback. That is what the recon reports as
# "shared resolver not importable". v2.27.32 normalised cwd and home_dir
# but missed this one, which is why that release did not move the needle.
hooks_dir = _msys(hooks_dir)
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

    # v2.26.76: the fallback resolver mirrors lib_poison_patterns.resolve_agent_defs.
    # Kept only for the asset-missing path; edit the shared one, not this.
    def resolve_agent_defs(agent_name, home, cwd_):
        names_ = {agent_name}
        bare_ = re.split(r'[:/]', agent_name)[-1]
        if bare_:
            names_.add(bare_)
        globs_ = []
        for nm in names_:
            globs_ += ['%s.md' % nm, '*/%s.md' % nm, '*/*/%s.md' % nm,
                       '%s/AGENT.md' % nm, '*/%s/AGENT.md' % nm]
        out_, seen_ = [], set()
        for base in (Path(home) / '.claude' / 'agents', Path(cwd_) / '.claude' / 'agents'):
            if not base.is_dir():
                continue
            for pat in globs_:
                try:
                    for p in base.glob(pat):
                        if not p.is_file():
                            continue
                        try:
                            st = p.stat(); key = (st.st_dev, st.st_ino)
                        except OSError:
                            key = str(p.resolve())
                        if key not in seen_:
                            seen_.add(key); out_.append(p)
                except Exception:
                    continue
        return out_

# v2.26.76: resolution moved to lib_poison_patterns so the Workflow channel
# (workflow-guard, via `agentType`) reads the SAME files by the SAME rules. The
# namespace and inode-dedup hazards it encodes are documented there.
scan_paths = resolve_agent_defs(agent, home_dir, cwd)

if not scan_paths:
    sys.exit(0)

findings, critical = [], 0
for p in scan_paths:
    try:
        text = p.read_text(encoding='utf-8', errors='replace')
    except Exception:
        continue
    f, c = scan_text(text, p.name)
    findings.extend(f)
    critical += c

if not findings:
    sys.exit(0)

body = '\n'.join(findings)
if critical:
    reason = ("Agent '%s' definition contains suspicious patterns:\n%s\n"
              "Review the agent definition before allowing it to run." % (agent, body))
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }))
else:
    msg = "[SUPERCHARGER] Agent '%s' definition has suspicious patterns (non-blocking):\n%s" % (agent, body)
    print(json.dumps({'systemMessage': msg, 'suppressOutput': suppress}))
PYEOF
)

[ -z "$RESULT" ] && exit 0
printf '%s\n' "$RESULT"

# CRITICAL -> deny + exit 2 (block). Otherwise warn only.
# Match the literal "deny" token, not the punctuation: json.dumps emits
# `"permissionDecision": "deny"` with a space after the colon.
if printf '%s' "$RESULT" | grep -q '"deny"'; then
  echo "[Supercharger] agent-poisoning-scanner: BLOCKED agent" >&2
  exit 2
fi
echo "[Supercharger] agent-poisoning-scanner: warned on agent" >&2
exit 0
