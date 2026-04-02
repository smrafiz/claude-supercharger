#!/usr/bin/env bash
# Claude Supercharger — Webhook Notification Functions

# Note: WEBHOOK_CONFIG is computed inside each function (not global)
# so it respects $HOME at call time, not source time.

# Check if webhook is configured and enabled
webhook_enabled() {
  local WEBHOOK_CONFIG="$HOME/.claude/supercharger/webhook.json"
  if [ ! -f "$WEBHOOK_CONFIG" ]; then
    return 1
  fi

  local enabled
  export WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG"
  enabled=$(python3 -c "
import json, os
try:
    with open(os.environ['WEBHOOK_CONFIG_FILE'], 'r') as f:
        config = json.load(f)
    print('true' if config.get('enabled', False) else 'false')
except:
    print('false')
" 2>/dev/null)
  unset WEBHOOK_CONFIG_FILE

  [[ "$enabled" == "true" ]]
}

# Send a webhook notification
# Usage: send_webhook "message text"
send_webhook() {
  local WEBHOOK_CONFIG="$HOME/.claude/supercharger/webhook.json"
  local message="$1"
  local project
  project=$(basename "$(pwd)" 2>/dev/null || echo "unknown")

  if [ ! -f "$WEBHOOK_CONFIG" ]; then
    return 1
  fi

  WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG" MESSAGE="$message" PROJECT="$project" python3 -c "
import json, os, subprocess, sys, re

config_file = os.environ['WEBHOOK_CONFIG_FILE']
message = os.environ['MESSAGE']
project = os.environ['PROJECT']

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except Exception as e:
    print(f'Webhook config error: {e}', file=sys.stderr)
    sys.exit(1)

if not config.get('enabled', False):
    sys.exit(0)

platform = config.get('platform', 'custom')
full_message = f'{message} — {project}'

def validate_url(url):
    if not url:
        print('Webhook URL is empty', file=sys.stderr)
        return False
    if not re.match(r'^https?://', url):
        print(f'Webhook URL must start with http(s)://', file=sys.stderr)
        return False
    if not url.startswith('https://'):
        print('WARNING: Webhook URL uses HTTP — blocked for security. Use HTTPS.', file=sys.stderr)
        return False
    return True

def send(url, payload):
    if not validate_url(url):
        return
    subprocess.run(['curl', '-s', '--fail', '--proto', '=https',
                     '-X', 'POST', '-H', 'Content-Type: application/json',
                     '-d', payload, url], capture_output=True, timeout=10)

try:
    if platform == 'slack':
        url = config.get('url', '')
        send(url, json.dumps({'text': full_message}))
    elif platform == 'discord':
        url = config.get('url', '')
        send(url, json.dumps({'content': full_message}))
    elif platform == 'telegram':
        token = config.get('bot_token', '')
        chat_id = config.get('chat_id', '')
        url = f'https://api.telegram.org/bot{token}/sendMessage'
        subprocess.run(['curl', '-s', '--fail', '--proto', '=https',
                         '-X', 'POST', '-H', 'Content-Type: application/json',
                         '-d', json.dumps({'chat_id': chat_id, 'text': full_message}),
                         url], capture_output=True, timeout=10)
    elif platform == 'custom':
        url = config.get('url', '')
        send(url, json.dumps({'text': full_message, 'project': project}))
except Exception as e:
    print(f'Webhook send error: {e}', file=sys.stderr)
" 2>/dev/null

  return $?
}
