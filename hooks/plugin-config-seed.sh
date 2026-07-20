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

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
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

# One-time nudge (SessionStart stderr reaches the user): the plugin edition can't
# provide the status line — Claude Code plugins cannot write settings.json, and
# statusLine lives only there. Point the user at the installer, which can. Shown
# once per install; disable with SUPERCHARGER_PLUGIN_NUDGE=0.
NUDGE_FLAG="$SUPERCHARGER_STATE/.statusline-nudge-shown"
if [ "${SUPERCHARGER_PLUGIN_NUDGE:-1}" != "0" ] && [ ! -f "$NUDGE_FLAG" ]; then
  : > "$NUDGE_FLAG" 2>/dev/null || true
  echo "[Supercharger] Plugin edition — the status line isn't available here (Claude Code plugins can't set statusLine)." >&2
  echo "  Want it (plus always-on rule files)? Use the installer: https://github.com/smrafiz/claude-supercharger#install" >&2
  echo "  Everything else — guards, modes, economy, agents, commands — works under the plugin as-is." >&2
fi

exit 0
