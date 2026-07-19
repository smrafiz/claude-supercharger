#!/usr/bin/env bash
# Claude Supercharger — Autopilot (time-boxed auto-approve)
# Writes an expiry timestamp to a scope flag. While now < that time, smart-approve.sh
# auto-approves every PermissionRequest, so the user isn't prompted. The PreToolUse
# safety hooks still fire, so dangerous commands stay blocked — this only removes the
# yes/no friction, not the safety floor. Expiry is evaluated per request; no timer.
# Ceiling defaults to 8h (a full workday) so it can't be left on forever; raise or
# lower it with SUPERCHARGER_AUTOPILOT_MAX_HOURS. A request above the ceiling is
# clamped with a loud notice (never silently), so the granted window is never a surprise.
#
# Scope (v2.12.2):
#   per-session (DEFAULT) — only the session that enabled it auto-approves.
#     flag: scope/.autopilot-until-<session-id>  (session id from CLAUDE_CODE_SESSION_ID)
#   global — every session on the machine auto-approves.
#     flag: scope/.autopilot-until
#
# Usage: autopilot.sh <duration> [session|global]   e.g. 30m, 2h, 90s, 45 (bare = min)
#        autopilot.sh off | status
set -uo pipefail

# Same state root the reader (lib-smart-approve.sh) resolves — installer default,
# CLAUDE_PLUGIN_DATA under the plugin runtime.
SC_STATE="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}"
SCOPE="$SC_STATE/scope"
# Ceiling: 8h default, overridable via SUPERCHARGER_AUTOPILOT_MAX_HOURS (positive int).
MAX_HOURS="${SUPERCHARGER_AUTOPILOT_MAX_HOURS:-8}"
printf '%s' "$MAX_HOURS" | grep -qE '^[0-9]+$' && [ "$((10#$MAX_HOURS))" -gt 0 ] || MAX_HOURS=8
MAX_SECONDS=$(( 10#$MAX_HOURS * 3600 ))

SID="${CLAUDE_CODE_SESSION_ID:-}"
GLOBAL_FLAG="$SCOPE/.autopilot-until"
SESS_FLAG=""
[ -n "$SID" ] && SESS_FLAG="$SCOPE/.autopilot-until-$SID"

# Portable epoch -> HH:MM (BSD/macOS `date -r`, GNU/Linux `date -d @`).
fmt_time() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo '?'; }
fmt_dur()  { local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60));
  if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m $((s%60))s"; fi; }

# echo remaining seconds for a flag file if it's a future epoch, else nothing.
remaining_of() {
  local f="$1" v now
  [ -n "$f" ] && [ -f "$f" ] || return 0
  v=$(cat "$f" 2>/dev/null || echo 0); now=$(date +%s)
  printf '%s' "$v" | grep -qE '^[0-9]+$' || return 0
  [ "$v" -gt "$now" ] && echo $((v - now))
}

status() {
  local g s any=""
  g=$(remaining_of "$GLOBAL_FLAG")
  s=$(remaining_of "$SESS_FLAG")
  if [ -n "$s" ]; then echo "Autopilot (this session): ON — $(fmt_dur "$s") remaining"; any=1; fi
  if [ -n "$g" ]; then echo "Autopilot (global, all sessions): ON — $(fmt_dur "$g") remaining"; any=1; fi
  [ -z "$any" ] && echo "Autopilot: OFF"
}

ARG="${1:-status}"
MODE="${2:-session}"   # default scope: this session only

case "$ARG" in
  status|"") status ;;
  off)
    # Turn off decisively — clear both this session's window and the global one.
    rm -f "$GLOBAL_FLAG" 2>/dev/null || true
    [ -n "$SESS_FLAG" ] && rm -f "$SESS_FLAG" 2>/dev/null || true
    echo "Autopilot: OFF — normal permission prompts restored."
    ;;
  *)
    case "$ARG" in
      *h) N="${ARG%h}"; U=3600 ;;
      *m) N="${ARG%m}"; U=60 ;;
      *s) N="${ARG%s}"; U=1 ;;
      *)  N="$ARG"; U=60 ;;   # bare number = minutes
    esac
    if ! printf '%s' "$N" | grep -qE '^[0-9]+$' || [ "$((10#$N))" -le 0 ]; then
      echo "Autopilot: invalid duration '$ARG'. Try 30m, 2h, 90s (bare = minutes), or 'off'." >&2
      exit 1
    fi

    # Resolve scope.
    local_scope_desc="this session only"
    TARGET="$SESS_FLAG"
    case "$MODE" in
      global|all|machine) TARGET="$GLOBAL_FLAG"; local_scope_desc="ALL sessions on this machine" ;;
      session|"")
        if [ -z "$SID" ]; then
          # No session id available (e.g. older Claude Code) — fall back to global.
          TARGET="$GLOBAL_FLAG"; local_scope_desc="ALL sessions (no session id available for per-session)"
        fi
        ;;
      *) echo "Autopilot: unknown scope '$MODE'. Use 'session' (default) or 'global'." >&2; exit 1 ;;
    esac

    REQ=$((10#$N * U)); CAPPED=""
    if [ "$REQ" -gt "$MAX_SECONDS" ]; then
      # Loud, never silent: tell the user their request was clamped and how to lift it.
      echo "Autopilot: requested $(fmt_dur "$REQ") exceeds the ${MAX_HOURS}h ceiling — granting ${MAX_HOURS}h. Raise it with SUPERCHARGER_AUTOPILOT_MAX_HOURS=<hours>." >&2
      REQ="$MAX_SECONDS"; CAPPED=" (capped at ${MAX_HOURS}h ceiling)"
    fi
    mkdir -p "$SCOPE" 2>/dev/null || true
    UNTIL=$(( $(date +%s) + REQ ))
    printf '%s\n' "$UNTIL" > "$TARGET"
    echo "Autopilot: ON for $(fmt_dur "$REQ")${CAPPED} — auto-approving all prompts for ${local_scope_desc} until $(fmt_time "$UNTIL")."
    echo "Safety hooks stay active: rm -rf, force-push, credential leaks, curl|bash and the like are still blocked."
    echo "Turn off early: /sc-autopilot off"
    ;;
esac
