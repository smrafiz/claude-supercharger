#!/usr/bin/env bash
# Claude Supercharger — Trust an MCP server for Elicitation credential prompts
# Usage:
#   bash tools/trust-mcp.sh <server>           # trust a server
#   bash tools/trust-mcp.sh --list             # list trusted servers
#   bash tools/trust-mcp.sh --remove <server>  # untrust a server
#
# elicitation-guard.sh declines an MCP server that asks for a credential-style
# field (or credential-request prose) via an Elicitation form, unless the server
# is trusted. Trust normally lives in a project's .supercharger.json
# (trustedElicitationServers), but that file is protected by the self-modification
# path-guard — so this tool writes a separate, global scope allowlist the guard
# ALSO reads: ~/.claude/supercharger/scope/.trusted-elicitation-servers
# (one lowercased server name per line). Lets /trust-mcp add a server without
# hand-editing config.

set -euo pipefail
SCOPE_DIR="$HOME/.claude/supercharger/scope"
TRUST_FILE="$SCOPE_DIR/.trusted-elicitation-servers"
mkdir -p "$SCOPE_DIR" 2>/dev/null || true

_norm() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-'; }

_list() {
  if [ -s "$TRUST_FILE" ]; then
    echo "Trusted MCP servers for Elicitation credential prompts:"
    sed 's/^/  - /' "$TRUST_FILE"
  else
    echo "No trusted MCP servers yet. Trust one with: /trust-mcp <server>"
  fi
}

case "${1:-}" in
  ""|--help|-h)
    echo "Usage: trust-mcp <server> | --list | --remove <server>"
    echo ""
    _list
    ;;
  --list|-l)
    _list
    ;;
  --remove|-r)
    srv=$(_norm "${2:-}")
    [ -z "$srv" ] && { echo "Usage: trust-mcp --remove <server>" >&2; exit 1; }
    if [ -f "$TRUST_FILE" ] && grep -qxF "$srv" "$TRUST_FILE" 2>/dev/null; then
      grep -vxF "$srv" "$TRUST_FILE" > "$TRUST_FILE.tmp" 2>/dev/null || true
      mv "$TRUST_FILE.tmp" "$TRUST_FILE" 2>/dev/null || rm -f "$TRUST_FILE.tmp"
      echo "Removed '$srv' from trusted MCP servers."
    else
      echo "'$srv' was not in the trusted list."
    fi
    ;;
  *)
    srv=$(_norm "$1")
    [ -z "$srv" ] && { echo "Usage: trust-mcp <server>" >&2; exit 1; }
    if [ -f "$TRUST_FILE" ] && grep -qxF "$srv" "$TRUST_FILE" 2>/dev/null; then
      echo "'$srv' is already trusted."
    else
      printf '%s\n' "$srv" >> "$TRUST_FILE"
      echo "Trusted '$srv' for Elicitation credential prompts."
      echo "It can now request password/token/API-key fields without being declined."
      echo "Undo with: /trust-mcp --remove $srv"
    fi
    ;;
esac
