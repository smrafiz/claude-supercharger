#!/usr/bin/env bash
# Claude Supercharger — Session Complete Hook
# Event: Stop | Matcher: (none)
# Logs session metadata on exit. Sends webhook if configured.

set -eo pipefail

SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"
WEBHOOK_CONFIG="$HOME/.claude/supercharger/webhook.json"

mkdir -p "$SUMMARIES_DIR" 2>/dev/null || true

# Capture session metadata
PROJECT=$(basename "$(pwd)" 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
MODIFIED=$(git diff --name-only HEAD 2>/dev/null | head -10 || echo "")

# Write session-end marker to summaries dir
MARKER_FILE="$SUMMARIES_DIR/.last-session"
{
  echo "timestamp: $TIMESTAMP"
  echo "project: $PROJECT"
  echo "branch: $BRANCH"
  echo "modified_files:"
  if [ -n "$MODIFIED" ]; then
    echo "$MODIFIED" | while read -r f; do echo "  - $f"; done
  else
    echo "  (none detected)"
  fi
} > "$MARKER_FILE" 2>/dev/null || true

# Send webhook notification if configured
if [ -f "$WEBHOOK_CONFIG" ]; then
  WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG" PROJECT="$PROJECT" python3 -c "
import json, os, subprocess, sys

config_file = os.environ['WEBHOOK_CONFIG_FILE']
project = os.environ['PROJECT']

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    sys.exit(0)

if not config.get('enabled', False):
    sys.exit(0)

platform = config.get('platform', 'custom')
message = f'Claude Code session complete — {project}'

try:
    if platform == 'slack':
        url = config.get('url', '')
        payload = json.dumps({'text': message})
        subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
                         '-d', payload, url], capture_output=True, timeout=10)
    elif platform == 'discord':
        url = config.get('url', '')
        payload = json.dumps({'content': message})
        subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
                         '-d', payload, url], capture_output=True, timeout=10)
    elif platform == 'telegram':
        token = config.get('bot_token', '')
        chat_id = config.get('chat_id', '')
        url = f'https://api.telegram.org/bot{token}/sendMessage'
        payload = json.dumps({'chat_id': chat_id, 'text': message})
        subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
                         '-d', payload, url], capture_output=True, timeout=10)
    elif platform == 'custom':
        url = config.get('url', '')
        payload = json.dumps({'text': message, 'project': project})
        subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
                         '-d', payload, url], capture_output=True, timeout=10)
except:
    pass
" 2>/dev/null || true
fi

exit 0
