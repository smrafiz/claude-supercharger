#!/usr/bin/env bash
# Claude Supercharger — Plugin first-run config seeder
# Event: SessionStart
#
# The installer has an interactive wizard that writes role / economy-tier /
# mcp-profile into scope files. A plugin has no install script, so this hook is the
# equivalent: under the PLUGIN runtime it seeds those scope files from the plugin's
# userConfig values (exported to hook processes as CLAUDE_PLUGIN_OPTION_<KEY>) on
# first run.
#
# Guarantees:
#   - NO-OP under the installer runtime (CLAUDE_PLUGIN_ROOT unset) — the wizard owns
#     those files there.
#   - NEVER clobbers an existing scope file — a runtime switch ("eco minimal",
#     /profile, mcp-profile.sh) always wins over the enable-time default.
set -uo pipefail

# Only the plugin runtime seeds; the installer already wrote these.
[ -z "${CLAUDE_PLUGIN_ROOT:-}" ] && exit 0

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-paths.sh
. "$HOOKS_DIR/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"

SCOPE="$SUPERCHARGER_STATE/scope"
mkdir -p "$SCOPE" 2>/dev/null || exit 0

# seed <scope-file> <value> — write only if absent and value non-empty.
seed() {
  local f="$SCOPE/$1" v="$2"
  [ -n "$v" ] && [ ! -f "$f" ] && printf '%s\n' "$v" > "$f" 2>/dev/null || true
}

seed .economy-tier "${CLAUDE_PLUGIN_OPTION_ECONOMY_TIER:-standard}"
seed .mcp-profile  "${CLAUDE_PLUGIN_OPTION_MCP_PROFILE:-light}"
seed .roles        "${CLAUDE_PLUGIN_OPTION_ROLE:-developer}"

exit 0
