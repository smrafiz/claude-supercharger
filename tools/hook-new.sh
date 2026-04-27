#!/usr/bin/env bash
# Claude Supercharger — New Hook Scaffolder
# Creates a hook stub with correct boilerplate and optionally registers it.
#
# Usage: bash tools/hook-new.sh [<hook-name> [event] [matcher]] [--register]
#
# Examples:
#   bash tools/hook-new.sh                                  # interactive
#   bash tools/hook-new.sh my-hook                          # PostToolUse, no matcher
#   bash tools/hook-new.sh my-hook PreToolUse Bash          # specific event + matcher
#   bash tools/hook-new.sh my-hook PostToolUse Bash --register  # + add to settings.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_DIR/hooks"
SETTINGS="$HOME/.claude/settings.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

HOOK_NAME=""
EVENT=""
MATCHER=""
REGISTER=false

# ── Parse args ────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --register) REGISTER=true; shift ;;
    -*)         echo -e "${RED}Error:${NC} unknown flag: $1"; exit 1 ;;
    *)
      if   [ -z "$HOOK_NAME" ]; then HOOK_NAME="$1"
      elif [ -z "$EVENT" ];     then EVENT="$1"
      elif [ -z "$MATCHER" ];   then MATCHER="$1"
      else echo -e "${RED}Error:${NC} unexpected argument: $1"; exit 1
      fi
      shift ;;
  esac
done

VALID_EVENTS="PreToolUse PostToolUse UserPromptSubmit SessionStart SubagentStop PreCompact PostCompact Stop"

# ── Interactive mode ──────────────────────────────────────────────────────────
if [ -z "$HOOK_NAME" ]; then
  echo -e "${CYAN}${BOLD}Claude Supercharger — New Hook${NC}"
  echo ""
  echo -n "Hook name (kebab-case, e.g. my-hook): "
  read -r HOOK_NAME
  echo ""
  echo -e "  Events: ${DIM}${VALID_EVENTS}${NC}"
  echo -n "Event [PostToolUse]: "
  read -r _EVT
  [ -n "$_EVT" ] && EVENT="$_EVT"
  echo ""
  echo -n "Matcher (e.g. Bash, Write,Edit — leave blank for all tools): "
  read -r MATCHER
  echo ""
  echo -n "Register in settings.json now? [y/N]: "
  read -r _REG
  [ "$_REG" = "y" ] || [ "$_REG" = "Y" ] && REGISTER=true
fi

[ -z "$EVENT" ]   && EVENT="PostToolUse"
[ -z "$MATCHER" ] && MATCHER="(none)"

# ── Validate ──────────────────────────────────────────────────────────────────
if ! printf '%s\n' "$HOOK_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  echo -e "${RED}Error:${NC} hook name must be lowercase kebab-case (e.g. my-hook)"
  exit 1
fi

OUTFILE="$HOOKS_DIR/${HOOK_NAME}.sh"
if [ -f "$OUTFILE" ]; then
  echo -e "${RED}Error:${NC} hooks/${HOOK_NAME}.sh already exists. Choose a different name."
  exit 1
fi

# ── Build title from hook name ────────────────────────────────────────────────
TITLE=$(printf '%s\n' "$HOOK_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')

# ── Write template ────────────────────────────────────────────────────────────
if [ "$MATCHER" = "(none)" ]; then
  MATCHER_LINE="(all tools)"
else
  MATCHER_LINE="$MATCHER"
fi

cat > "$OUTFILE" << TEMPLATE
#!/usr/bin/env bash
# Claude Supercharger — ${TITLE}
# Event: ${EVENT} | Matcher: ${MATCHER_LINE}
# TODO: describe what this hook does

set -euo pipefail
HOOKS_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "\$HOOKS_DIR/lib-suppress.sh"
check_hook_disabled "${HOOK_NAME}" && exit 0

_INPUT=\$(cat)

# ── Extract common fields ────────────────────────────────────────────────────
# Uncomment what you need:

# TOOL_NAME=\$(printf '%s\n' "\$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
# COMMAND=\$(printf '%s\n' "\$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
# PROJECT_DIR=\$(printf '%s\n' "\$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null); [ -z "\$PROJECT_DIR" ] && PROJECT_DIR="\$PWD"

# ── Your logic here ──────────────────────────────────────────────────────────

# Example: inject a context message (PostToolUse / UserPromptSubmit)
# MSG="Your message here"
# MSG_JSON=\$(printf '%s' "\$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
# printf '{"systemMessage":%s}\n' "\$MSG_JSON"

# Example: block a command (PreToolUse only)
# RSN=\$(printf '%s' "Reason here" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
# printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "\$RSN"
# exit 2

exit 0
TEMPLATE

chmod +x "$OUTFILE"

echo -e "${GREEN}✓${NC} Created: ${BOLD}hooks/${HOOK_NAME}.sh${NC}"
echo -e "  Event:   ${CYAN}${EVENT}${NC}"
echo -e "  Matcher: ${CYAN}${MATCHER_LINE}${NC}"

# ── Register in settings.json ─────────────────────────────────────────────────
if $REGISTER; then
  if [ ! -f "$SETTINGS" ]; then
    echo -e "${RED}Error:${NC} $SETTINGS not found — run install.sh first"
    exit 1
  fi

  HOOK_PATH="$HOOKS_DIR/${HOOK_NAME}.sh"
  MATCHER_ARG="$MATCHER"
  EVENT_ARG="$EVENT"

  python3 -c "
import json, sys

settings_file = sys.argv[1]
hook_path     = sys.argv[2]
event         = sys.argv[3]
matcher       = sys.argv[4]
hook_name     = sys.argv[5]

with open(settings_file) as f:
    s = json.load(f)

hooks = s.setdefault('hooks', {})
entries = hooks.setdefault(event, [])

# Check if already registered
for entry in entries:
    for h in entry.get('hooks', []):
        if hook_path in h.get('command', ''):
            print(f'Already registered: {hook_name} ({event})')
            sys.exit(0)

new_entry = {'hooks': [{'type': 'command', 'command': hook_path + ' #supercharger'}]}
if matcher not in ('(none)', '(all tools)', ''):
    new_entry['matcher'] = matcher

entries.append(new_entry)

with open(settings_file, 'w') as f:
    json.dump(s, f, indent=2)

print(f'Registered: {hook_name} ({event})')
" "$SETTINGS" "$HOOK_PATH" "$EVENT_ARG" "$MATCHER_ARG" "$HOOK_NAME"

  echo -e "  ${GREEN}✓${NC} Registered in settings.json"
else
  echo ""
  echo -e "${BOLD}Register when ready:${NC}"
  echo -e "  ${CYAN}bash tools/hook-new.sh ${HOOK_NAME} --register${NC}"
  echo -e "  or edit ${BOLD}~/.claude/settings.json${NC} manually"
fi

echo ""
echo -e "Edit: ${BOLD}hooks/${HOOK_NAME}.sh${NC}"
