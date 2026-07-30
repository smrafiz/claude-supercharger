#!/usr/bin/env bash
# Claude Supercharger — Dependency preflight
# Event: SessionStart | Matcher: —
#
# install.sh refuses to proceed without `jq` and `python3` (install.sh:8, :25). A
# PLUGIN install has no install step, so nothing ever checked — and 103 of 138 hooks
# shell out to `jq`, 122 to `python3`. Without them the guards do not announce
# anything; they degrade quietly, which is the failure mode this project keeps
# getting bitten by. A guard that cannot run looks exactly like a guard with nothing
# to do.
#
# Runs on BOTH channels: a classic install can also lose a dependency later (a PATH
# change, a Homebrew cleanup, a Python upgrade that drops the `python3` shim), and the
# install-time check cannot see that.
#
# Deliberately quiet: warns only when something is actually missing, and only once
# per distinct missing-set, so a healthy machine never pays a line of noise and a
# newly-missing dependency is still reported. `command -v` is a shell builtin, so the
# healthy path costs zero forks.
set -uo pipefail

# Honor the global kill-switch (/sc off must silence every hook).
# shellcheck source=hooks/lib-timing.sh
. "${BASH_SOURCE[0]%/*}/lib-timing.sh" 2>/dev/null || true

[ "${SUPERCHARGER_DEPENDENCY_PREFLIGHT:-1}" = "0" ] && exit 0

MISSING=""
command -v jq      >/dev/null 2>&1 || MISSING="${MISSING}jq "
command -v python3 >/dev/null 2>&1 || MISSING="${MISSING}python3 "

# bash 3.2 is supported (macOS ships it); anything older is not.
if [ -n "${BASH_VERSINFO:-}" ] && [ "${BASH_VERSINFO[0]}" -lt 3 ]; then
  MISSING="${MISSING}bash>=3.2 "
fi

[ -z "$MISSING" ] && exit 0

HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-paths.sh
. "$HOOKS_DIR/lib-paths.sh" 2>/dev/null || true
: "${SUPERCHARGER_STATE:=${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}}"
SCOPE="$SUPERCHARGER_STATE/scope"

# Key the marker on WHAT is missing, not merely "warned once": if jq is installed and
# python3 later disappears, that is a new fact and must be reported again.
KEY=$(printf '%s' "$MISSING" | tr -d ' ')
MARKER="$SCOPE/.deps-warned-$KEY"
if [ -f "$MARKER" ]; then exit 0; fi
mkdir -p "$SCOPE" 2>/dev/null && : > "$MARKER" 2>/dev/null || true

INSTALL_HINT="brew install jq python3"
case "$(uname -s 2>/dev/null)" in
  Linux) INSTALL_HINT="sudo apt install jq python3   # or your distro's package manager" ;;
esac

{
  echo ""
  echo "[Supercharger] Missing dependency: ${MISSING%% }"
  echo "  103 of 138 hooks use jq and 122 use python3. Without them the guards"
  echo "  degrade silently — they will not block what they normally block."
  echo "  Install with: $INSTALL_HINT"
  echo "  Then restart Claude Code. Silence this check: SUPERCHARGER_DEPENDENCY_PREFLIGHT=0"
  echo ""
} >&2

exit 0
