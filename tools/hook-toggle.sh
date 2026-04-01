#!/usr/bin/env bash
# Claude Supercharger — Hook Toggle Tool
# Usage: bash tools/hook-toggle.sh <hook-name> <on|off>
# Temporarily enable/disable a supercharger hook without editing JSON.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SUPERCHARGER_TAG="#supercharger"

usage() {
  echo "Usage: hook-toggle.sh <hook-name> <on|off>"
  echo ""
  echo "Available hooks:"
  echo "  safety, git-safety, notify, auto-format, quality-gate,"
  echo "  prompt-validator, compaction-backup, enforce-pkg-manager, audit-trail"
  echo ""
  echo "Examples:"
  echo "  hook-toggle.sh prompt-validator off   # Disable prompt validator"
  echo "  hook-toggle.sh prompt-validator on    # Re-enable it"
  echo "  hook-toggle.sh                        # Show status of all hooks"
  exit 1
}

# Show status if no args
if [ $# -eq 0 ]; then
  if [ ! -f "$SETTINGS_FILE" ]; then
    echo "No settings.json found."
    exit 0
  fi
  echo "Hook Status:"
  python3 -c "
import json
with open('$SETTINGS_FILE') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
for event, entries in sorted(hooks.items()):
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            if '$SUPERCHARGER_TAG' in cmd:
                name = cmd.split('/')[-1].split('.sh')[0].split(' ')[0]
                disabled = cmd.startswith('# ')
                status = 'OFF' if disabled else 'ON'
                symbol = '○' if disabled else '●'
                print(f'  {symbol} {name:25s} [{event}] {status}')
" 2>/dev/null
  exit 0
fi

if [ $# -ne 2 ]; then
  usage
fi

HOOK_NAME="$1"
ACTION="$2"

if [[ "$ACTION" != "on" && "$ACTION" != "off" ]]; then
  usage
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  echo "Error: $SETTINGS_FILE not found. Run install.sh first."
  exit 1
fi

python3 -c "
import json, sys

hook_name = '$HOOK_NAME'
action = '$ACTION'
tag = '$SUPERCHARGER_TAG'

with open('$SETTINGS_FILE') as f:
    settings = json.load(f)

found = False
hooks = settings.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            if tag in cmd and hook_name in cmd:
                found = True
                if action == 'off' and not cmd.startswith('# '):
                    h['command'] = '# ' + cmd
                    print(f'Disabled: {hook_name} ({event})')
                elif action == 'on' and cmd.startswith('# '):
                    h['command'] = cmd[2:]
                    print(f'Enabled: {hook_name} ({event})')
                elif action == 'on' and not cmd.startswith('# '):
                    print(f'Already enabled: {hook_name}')
                elif action == 'off' and cmd.startswith('# '):
                    print(f'Already disabled: {hook_name}')

if not found:
    print(f'Hook not found: {hook_name}', file=sys.stderr)
    sys.exit(1)

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
" 2>&1

exit $?
