#!/usr/bin/env bash
# Claude Supercharger — Project-Level Config Hook
# Event: SessionStart | Matcher: (none)
# Reads .supercharger.json from project root and applies profile overrides.
# Outputs a systemMessage telling Claude about the active project config.

set -euo pipefail

INPUT=$(cat)

PROJECT_DIR=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")

if [ -z "$PROJECT_DIR" ]; then
  exit 0
fi

# Walk up to find .supercharger.json (max 5 levels)
CONFIG_FILE=""
SEARCH_DIR="$PROJECT_DIR"
for _ in 1 2 3 4 5; do
  if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
    CONFIG_FILE="$SEARCH_DIR/.supercharger.json"
    break
  fi
  PARENT=$(dirname "$SEARCH_DIR")
  [ "$PARENT" = "$SEARCH_DIR" ] && break
  SEARCH_DIR="$PARENT"
done

if [ -z "$CONFIG_FILE" ]; then
  exit 0
fi

# Parse the project config
RESULT=$(CONFIG_FILE="$CONFIG_FILE" python3 << 'PYEOF'
import json, os, sys, re

config_file = os.environ['CONFIG_FILE']
try:
    with open(config_file) as f:
        config = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(0)

roles = config.get('roles', [])
VALID_ROLES = {'developer', 'writer', 'student', 'data', 'pm', 'designer', 'devops', 'researcher'}
roles = [r for r in roles if isinstance(r, str) and r in VALID_ROLES]

VALID_ECONOMY = {'standard', 'lean', 'minimal'}
economy = config.get('economy', '')
if economy and economy not in VALID_ECONOMY:
    economy = ''
raw_hints = config.get('hints', '')

hints = re.sub(r'[^\x20-\x7E]', '', str(raw_hints))[:200]
hints = re.sub(r'[<>{}\[\]\\`$]', '', hints)

parts = []
if roles:
    parts.append('Roles: ' + ', '.join(roles))
if economy:
    parts.append('Economy: ' + economy)
if hints:
    parts.append('Project hints: ' + hints)

if not parts:
    sys.exit(0)

msg = '[Supercharger] Project config loaded from ' + config_file + '. ' + '. '.join(parts) + '.'

print(json.dumps({
    'continue': True,
    'suppressOutput': False,
    'systemMessage': msg
}))
PYEOF
)

if [ -n "$RESULT" ]; then
  echo "$RESULT"
fi

exit 0
