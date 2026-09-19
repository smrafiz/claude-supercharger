#!/usr/bin/env bash
# Claude Supercharger — context-percentage sidecar reader
# Helper: not a registered hook — sourced by hooks that need context window usage.
#
# WHY THIS EXISTS (v4.1.8)
# ------------------------
# `context_window.used_percentage` is NOT in any hook event payload. It rides
# only on the statusLine payload (docs/en/statusline, "Available data"). Three
# hooks read it straight off their own stdin and therefore never fired once in
# 62 sessions — see docs/ECONOMY-LAYER-2026-09-19.md.
#
# Upstream will not close this: anthropics/claude-code #16988, #34340 and #44790
# were all closed "not planned"; #27969 closed as duplicate; only #49226 is open
# and has not moved since April 2026. So the value has to be carried across.
#
# hooks/statusline.sh already parses the percentage and already writes a
# per-session file. It writes this sidecar in the same block, and the hooks join
# on `session_id`, which every hook payload does carry.
#
# COVERAGE LIMIT, on purpose: the sidecar exists only where Supercharger owns the
# statusLine (settings.json, written by lib/hooks.sh). A plugin install cannot set
# statusLine (tools/gen-plugin-hooks.sh), and lib/hooks.sh deliberately leaves a
# statusLine the user set themselves alone. Both cases get no sidecar and the
# callers degrade to exactly their pre-4.1.8 behaviour: silent exit 0. Absence is
# the normal case, not an error — never fail closed on it.

# _ctx_pct <outvar> <session_id> [max_age_s]
#
# Sets <outvar> to an integer 0-100, or to "" when unavailable for ANY reason
# (no sidecar, unreadable, malformed, stale, unsafe session id). Always returns 0.
#
# max_age_s defaults to 300. Pass 0 to skip the freshness check — do that only on
# a path that cannot run while the session is idle, because the check is the only
# thing standing between a caller and a percentage from an hour ago.
#
# Fork-free apart from one `date` on bash 3.2 (macOS default), and that fork is
# reached only when the sidecar actually exists — the no-statusline case costs a
# file test. This matters: auto-compact.sh is PostToolUse with no matcher, so
# anything unconditional here is paid on every tool call.
# See memory a-second-fork-on-a-hot-hook-costs-a-full-spawn.
_ctx_pct() {
  local __out="$1" __sid="${2:-}" __max="${3:-300}"
  local __f __ts __p __now
  printf -v "$__out" '%s' ''

  # Session id lands in a file path — allow only path-safe characters.
  case "$__sid" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac

  __f="${SUPERCHARGER_STATE:-$HOME/.claude/supercharger}/scope/.ctx-pct-$__sid"
  [ -r "$__f" ] || return 0

  # Format is a single line: "<epoch> <pct>". `read < file` is a builtin.
  __ts=""; __p=""
  IFS=' ' read -r __ts __p _ < "$__f" 2>/dev/null || return 0
  case "$__ts" in ''|*[!0-9]*) return 0 ;; esac
  case "$__p"  in ''|*[!0-9]*) return 0 ;; esac
  [ "$__p" -le 100 ] || return 0

  if [ "$__max" -gt 0 ]; then
    __now="${EPOCHSECONDS:-}"
    [ -z "$__now" ] && __now=$(date +%s 2>/dev/null || echo 0)
    case "$__now" in ''|*[!0-9]*) return 0 ;; esac
    [ "$__now" -ge "$__ts" ] || return 0            # clock went backwards
    [ $(( __now - __ts )) -le "$__max" ] || return 0
  fi

  printf -v "$__out" '%s' "$__p"
  return 0
}
