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

# elicitation-guard reads the trust list at ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/
# scope; this tool runs outside any hook (env var unset), so add/remove/list across
# EVERY scope dir (classic + plugin) — else trusting a server never reaches the guard
# on plugin installs (perpetual credential-prompt declines).
_TM_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$(dirname "$_TM_SCRIPT_DIR")/lib/utils.sh"
TRUST_BASE=".trusted-elicitation-servers"

_norm() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_.-'; }

# union of trusted servers across all scope dirs
_all_trusted() {
  local d
  while IFS= read -r d; do
    [ -f "$d/$TRUST_BASE" ] && cat "$d/$TRUST_BASE" 2>/dev/null
  done <<EOF
$(sc_scope_dirs)
EOF
}
_trust_add() { local srv="$1" d
  while IFS= read -r d; do [ -n "$d" ] || continue; mkdir -p "$d" 2>/dev/null || true
    grep -qxF "$srv" "$d/$TRUST_BASE" 2>/dev/null || printf '%s\n' "$srv" >> "$d/$TRUST_BASE"
  done <<EOF
$(sc_scope_dirs)
EOF
}
_trust_rm() { local srv="$1" d f
  while IFS= read -r d; do f="$d/$TRUST_BASE"; [ -f "$f" ] || continue
    grep -vxF "$srv" "$f" > "$f.tmp" 2>/dev/null || true
    mv "$f.tmp" "$f" 2>/dev/null || rm -f "$f.tmp"
  done <<EOF
$(sc_scope_dirs)
EOF
}
# NB: no `grep -q` here — under `set -o pipefail`, grep -q closes the pipe on first
# match and SIGPIPEs the upstream `cat`, making the pipeline return non-zero even on a
# hit. Reading to EOF (-> /dev/null) avoids that.
_is_trusted() { _all_trusted | grep -xF -- "$1" >/dev/null 2>&1; }

_list() {
  local u; u=$(_all_trusted | sort -u | grep -v '^$' || true)
  if [ -n "$u" ]; then
    echo "Trusted MCP servers for Elicitation credential prompts:"
    printf '%s\n' "$u" | sed 's/^/  - /'
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
    if _is_trusted "$srv"; then
      _trust_rm "$srv"
      echo "Removed '$srv' from trusted MCP servers."
    else
      echo "'$srv' was not in the trusted list."
    fi
    ;;
  *)
    srv=$(_norm "$1")
    [ -z "$srv" ] && { echo "Usage: trust-mcp <server>" >&2; exit 1; }
    if _is_trusted "$srv"; then
      echo "'$srv' is already trusted."
    else
      _trust_add "$srv"
      echo "Trusted '$srv' for Elicitation credential prompts."
      echo "It can now request password/token/API-key fields without being declined."
      echo "Undo with: /trust-mcp --remove $srv"
    fi
    ;;
esac
