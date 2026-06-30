#!/usr/bin/env bash
# Claude Supercharger — Session Complete Hook
# Event: Stop | Matcher: (none)
# Logs session metadata on exit. Sends webhook if configured.

set -euo pipefail

SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
SUPERCHARGER_DIR="$HOME/.claude/supercharger"

mkdir -p "$SUMMARIES_DIR" 2>/dev/null || true

_INPUT=$(cat)

# v2.7.16: skip Stop re-fires (stop_hook_active) so the completion webhook fires
# once per session, not once per re-entry.
case "$_INPUT" in *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;; esac

# v2.6.24: one python3 fork does stdin-parse + economy-detect + both file
# writes. Was: 1 python3 (cost parse) + 2 greps (economy) + 1 basename + 1
# git branch + 1 git diff + 1 date (×2) — 7 forks. Now: 1 python3 + 1 git
# branch + 1 git diff (git subprocesses are cheap, no python cold-start).
# Median 90ms → 40ms (-55%).
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -10 || echo "")

HOOK_INPUT="$_INPUT" SUPERCHARGER_DIR="$SUPERCHARGER_DIR" SUMMARIES_DIR="$SUMMARIES_DIR" \
  HOME_DIR="$HOME" BRANCH="$BRANCH" MODIFIED="$MODIFIED" PROJECT="$(basename "$PWD")" \
  python3 <<'PYEOF' 2>/dev/null || true
import json, os
from datetime import datetime

raw = os.environ.get('HOOK_INPUT', '')
supercharger_dir = os.environ.get('SUPERCHARGER_DIR', '')
summaries_dir = os.environ.get('SUMMARIES_DIR', '')
home_dir = os.environ.get('HOME_DIR', '')
branch = os.environ.get('BRANCH', '')
modified = os.environ.get('MODIFIED', '')
project = os.environ.get('PROJECT', 'unknown')

# 1. Cost from stdin
try:
    d = json.loads(raw)
except Exception:
    d = {}
cost = (d.get('cost_usd')
        or d.get('total_cost_usd')
        or (d.get('cost') or {}).get('total_cost_usd')
        or 0)
try:
    cost_str = '{:.4f}'.format(float(cost))
except Exception:
    cost_str = '0'

# 2. Economy tier (read file directly, one open instead of two greps)
economy = 'lean'
econ_path = os.path.join(home_dir, '.claude', 'rules', 'economy.md')
try:
    with open(econ_path) as f:
        content = f.read()
    if 'Active Tier: Minimal' in content:
        economy = 'minimal'
    elif 'Active Tier: Standard' in content:
        economy = 'standard'
except Exception:
    pass

# 3. Persist cost + economy
now = datetime.now()
ts_iso = now.strftime('%Y-%m-%dT%H:%M:%S')
try:
    with open(os.path.join(supercharger_dir, '.last-session-cost'), 'w') as f:
        f.write('cost={}\neconomy={}\ntimestamp={}\n'.format(cost_str, economy, ts_iso))
except Exception:
    pass

# 4. Session marker
ts_marker = now.strftime('%Y-%m-%d-%H%M%S')
files_block = '\n'.join('  - ' + f for f in modified.splitlines() if f) or '  (none detected)'
try:
    with open(os.path.join(summaries_dir, '.last-session'), 'w') as f:
        f.write('timestamp: {}\nproject: {}\nbranch: {}\nmodified_files:\n{}\n'.format(
            ts_marker, project, branch, files_block))
except Exception:
    pass
PYEOF

# Clean up THIS session's checkpoint. v2.7.23: was a bare `.checkpoint-*` glob,
# so a concurrent session's Stop deleted OTHER live sessions' checkpoints. Scope
# to this session_id (checkpoints are written as .checkpoint-<session_id>).
_CK_SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -n "$_CK_SID" ] && rm -f "$HOME/.claude/supercharger/scope/.checkpoint-${_CK_SID}" 2>/dev/null || true

# Send webhook notification if configured — uses shared webhook lib
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$HOOKS_DIR/webhook-lib.sh" ]; then
  source "$HOOKS_DIR/webhook-lib.sh"
  if webhook_enabled; then
    send_webhook "Claude Code session complete" || true
  fi
fi

exit 0
