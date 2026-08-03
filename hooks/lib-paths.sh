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

# --- per-project scope files --------------------------------------------------
# .profile, .disabled-hooks, .disabled-security-categories and .budget-cap hold
# values that belong to ONE project, but they lived at a single global path. With
# two projects open, each overwrote the other: a project with no `profile` key
# os.remove()d another project's profile, and a `budget` set in one silently
# capped the other. Tracked as the last open audit HIGH since v2.21.
#
# The key is the project path with '/' -> '-', NOT a hash. It has to be computed
# inside lib-suppress, which every hook sources, and an md5sum there would add a
# fork to the per-hook floor — the one cost this project cannot afford. Parameter
# expansion is free. It also stays readable in `ls`, which matters when debugging
# whose config is in effect.
#
# Written as a var-setting function, not one returning via $(...): command
# substitution forks a subshell, which is exactly what this avoids.
sc_project_key() { # project_dir -> sets SC_PROJECT_KEY
  local p="${1:-$PWD}"
  p="${p//\//-}"
  p="${p#-}"
  # Cap for filename limits (255 bytes typical). A collision needs two projects
  # sharing a 100-char path suffix, and degrades to the old shared-file
  # behaviour rather than to anything worse.
  if [ ${#p} -gt 100 ]; then p="${p:${#p}-100}"; fi
  # "/" sanitises to the empty string, which would yield a bare "<name>-" file.
  if [ -z "$p" ]; then p="root"; fi
  SC_PROJECT_KEY="$p"
}

# Resolve a scope file for reading: the per-project file when it exists, else the
# legacy global path. That fallback is what keeps installs written before this
# change working until the next config load rewrites them.
sc_scope_resolve() { # name, project_dir -> sets SC_SCOPE_FILE
  sc_project_key "${2:-$PWD}"
  SC_SCOPE_FILE="$SUPERCHARGER_STATE/scope/${1}-$SC_PROJECT_KEY"
  if [ ! -f "$SC_SCOPE_FILE" ]; then SC_SCOPE_FILE="$SUPERCHARGER_STATE/scope/${1}"; fi
}
