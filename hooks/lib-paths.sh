#!/usr/bin/env bash
# Claude Supercharger — Path Resolution
# Single source of truth for WHERE Supercharger's code and state live, so the
# exact same hooks run under BOTH the shell installer and the plugin runtime.
#
#   SUPERCHARGER_HOME  — read-only code + assets (hooks/, lib/, rules/, economy/, roles/)
#   SUPERCHARGER_STATE — mutable per-user/session state (scope/, audit/, .version)
#
# Resolution (only sets a var if unset, so callers can override for tests):
#   install.sh runtime  → neither CLAUDE_PLUGIN_* is set → both resolve to
#                         ~/.claude/supercharger  → byte-identical to pre-plugin behavior.
#   plugin runtime      → Claude Code sets CLAUDE_PLUGIN_ROOT (read-only cache dir,
#                         changes on update) and CLAUDE_PLUGIN_DATA (persistent,
#                         writable, survives updates). Code from ROOT, state in DATA.
#
# Not executable on its own — sourcing it sets the two vars in the caller's shell.
# shellcheck disable=SC2034  # consumed by the sourcing hook, not this file
: "${SUPERCHARGER_HOME:=${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/supercharger}}"
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
