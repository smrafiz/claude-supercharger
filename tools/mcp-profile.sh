#!/usr/bin/env bash
# Claude Supercharger — MCP Profile Switcher
# Usage: bash tools/mcp-profile.sh [light|dev|research|full]
# Profiles:
#   light    — context7 only (~300 tokens)
#   dev      — light + playwright + github + magic-ui
#   research — light + memory + sequential-thinking (~1,500 tokens)
#   full     — everything (~3,500 tokens)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/mcp.sh"

PROFILE="${1:-}"

if [ -z "$PROFILE" ]; then
  echo "Usage: mcp-profile.sh [light|dev|research|full]"
  echo ""
  echo "  light    — context7 only (~300 tokens of tool schemas)"
  echo "  dev      — light + playwright + github + magic-ui"
  echo "  research — light + memory + sequential-thinking"
  echo "  full     — everything"
  echo ""
  PROFILE_STAMP="$HOME/.claude/supercharger/scope/.mcp-profile"
  if [ -f "$PROFILE_STAMP" ]; then
    echo "Current profile: $(cat "$PROFILE_STAMP")"
  else
    echo "Current profile: light (default)"
  fi
  exit 0
fi

case "$PROFILE" in
  light|dev|research|full) ;;
  *) echo "Unknown profile: $PROFILE. Use: light | dev | research | full"; exit 1 ;;
esac

# Read installed roles from stamp
INSTALLED_ROLES="developer"
ROLES_STAMP="$HOME/.claude/supercharger/.roles"
if [ -f "$ROLES_STAMP" ]; then
  INSTALLED_ROLES=$(cat "$ROLES_STAMP" | tr -d '[:space:]')
fi

# Map profile to internal args
# 'dev' forces developer role to ensure playwright/magic-ui are included
ROLES="$INSTALLED_ROLES"
INTERNAL_PROFILE="$PROFILE"

if [ "$PROFILE" = "dev" ]; then
  INTERNAL_PROFILE="light"
  echo "$ROLES" | grep -q "developer" || ROLES="developer,${ROLES}"
fi

echo "Switching to MCP profile: $PROFILE..."

if merge_mcp_into_settings "$ROLES" "$INTERNAL_PROFILE"; then
  COUNT=$(count_mcp_servers "$ROLES" "$INTERNAL_PROFILE")
  mkdir -p "$HOME/.claude/supercharger/scope"
  echo "$PROFILE" > "$HOME/.claude/supercharger/scope/.mcp-profile"
  echo "Done. $COUNT MCP server(s) configured. Restart Claude Code to apply."
else
  echo "Error: failed to write MCP config."
  exit 1
fi
