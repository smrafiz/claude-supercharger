#!/usr/bin/env bash
# Claude Supercharger — New Hook Scaffolder
# Generates a hook stub with standard boilerplate.
# Usage: bash tools/hook-new.sh <hook-name> [event] [matcher]
#
# Examples:
#   bash tools/hook-new.sh my-hook
#   bash tools/hook-new.sh my-hook PostToolUse Bash
#   bash tools/hook-new.sh my-hook UserPromptSubmit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/hooks"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
  echo "Usage: bash tools/hook-new.sh <hook-name> [event] [matcher]"
  echo ""
  echo "  hook-name   kebab-case name (e.g. my-hook → hooks/my-hook.sh)"
  echo "  event       PreToolUse | PostToolUse | UserPromptSubmit | SessionStart | FileChanged | ..."
  echo "              (default: PostToolUse)"
  echo "  matcher     Tool matcher e.g. Bash, Write,Edit, Agent  (default: none)"
  echo ""
  echo "Events: PreToolUse PostToolUse UserPromptSubmit SessionStart"
  echo "        SubagentStop PreCompact PostCompact FileChanged"
  exit 1
}

[ $# -lt 1 ] && usage

HOOK_NAME="$1"
EVENT="${2:-PostToolUse}"
MATCHER="${3:-(none)}"

# Validate name
if ! echo "$HOOK_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  echo -e "${RED}Error:${NC} hook name must be lowercase kebab-case (e.g. my-hook)"
  exit 1
fi

OUTFILE="$HOOKS_DIR/${HOOK_NAME}.sh"

if [ -f "$OUTFILE" ]; then
  echo -e "${RED}Error:${NC} $OUTFILE already exists. Choose a different name."
  exit 1
fi

# Derive profile-skip name and function name from hook name
FUNC_NAME=$(echo "$HOOK_NAME" | tr '-' '_')

cat > "$OUTFILE" << TEMPLATE
#!/usr/bin/env bash
# Claude Supercharger — $(echo "$HOOK_NAME" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')
# Event: ${EVENT} | Matcher: ${MATCHER}
# TODO: describe what this hook does

set -euo pipefail
HOOKS_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "\$HOOKS_DIR/lib-suppress.sh"

_INPUT=\$(cat)
PROJECT_DIR=\$(printf '%s\n' "\$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null); [ -z "\$PROJECT_DIR" ] && PROJECT_DIR="\$PWD"
init_hook_suppress "\$PROJECT_DIR"
hook_profile_skip "${HOOK_NAME}" && exit 0

# ── Your logic here ──────────────────────────────────────────────────────────

# Example: read a field from input
# FIELD=\$(printf '%s\n' "\$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
# [ -z "\$FIELD" ] && exit 0

# Example: inject a system message
# MSG="Your message here"
# MSG_JSON=\$(printf '%s' "\$MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
# printf '{"systemMessage":%s,"suppressOutput":%s}\n' "\$MSG_JSON" "\$HOOK_SUPPRESS"

# Example: block a command (PreToolUse only — exit 2 to block)
# printf '{"decision":"block","reason":"Reason here"}\n'
# exit 2

exit 0
TEMPLATE

chmod +x "$OUTFILE"

echo -e "${GREEN}✓${NC} Created: ${BOLD}hooks/${HOOK_NAME}.sh${NC}"
echo ""
echo -e "  Event:   ${CYAN}${EVENT}${NC}"
echo -e "  Matcher: ${CYAN}${MATCHER}${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Edit ${BOLD}hooks/${HOOK_NAME}.sh${NC} — fill in your logic"
echo -e "  2. Add to ${BOLD}~/.claude/settings.json${NC} hooks array to activate"
echo -e "  3. Run ${BOLD}bash tools/claude-check.sh${NC} to verify wiring"
echo ""
echo -e "  Register in settings.json:"
echo -e "  ${CYAN}bash tools/hook-toggle.sh ${HOOK_NAME} on${NC}"
