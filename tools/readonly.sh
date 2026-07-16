#!/usr/bin/env bash
# Claude Supercharger — Read-only mode (time-boxed "look, don't touch")
# Writes an expiry timestamp to a scope flag. While now < that time, readonly-guard.sh
# BLOCKS every file edit (Write/Edit/MultiEdit/NotebookEdit) and every mutating Bash
# command; reads, searches, and planning stay allowed. The inverse of autopilot: a
# time-boxed TIGHTENING. Expiry is evaluated per request; no timer. Hard-capped at 2h.
#
# Scope (mirrors autopilot):
#   per-session (DEFAULT) — only this session is read-only.
#     flag: scope/.readonly-until-<session-id>  (session id from CLAUDE_CODE_SESSION_ID)
#   global — every session on the machine is read-only.
#     flag: scope/.readonly-until
#
# Usage: readonly.sh <duration> [session|global]   e.g. 30m, 2h, 90s, 45 (bare = min)
#        readonly.sh off | status
set -uo pipefail

SC_STATE="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}"
SCOPE="$SC_STATE/scope"
MAX_SECONDS=7200   # 2h hard cap

SID="${CLAUDE_CODE_SESSION_ID:-}"
GLOBAL_FLAG="$SCOPE/.readonly-until"
SESS_FLAG=""
[ -n "$SID" ] && SESS_FLAG="$SCOPE/.readonly-until-$SID"

fmt_time() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo '?'; }
fmt_dur()  { local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60));
  if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m $((s%60))s"; fi; }

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
  if [ -n "$s" ]; then echo "Read-only (this session): ON — $(fmt_dur "$s") remaining"; any=1; fi
  if [ -n "$g" ]; then echo "Read-only (global, all sessions): ON — $(fmt_dur "$g") remaining"; any=1; fi
  [ -z "$any" ] && echo "Read-only: OFF"
}

ARG="${1:-status}"
MODE="${2:-session}"

case "$ARG" in
  status|"") status ;;
  off)
    rm -f "$GLOBAL_FLAG" 2>/dev/null || true
    [ -n "$SESS_FLAG" ] && rm -f "$SESS_FLAG" 2>/dev/null || true
    echo "Read-only: OFF — writes and mutating commands are allowed again."
    ;;
  *)
    case "$ARG" in
      *h) N="${ARG%h}"; U=3600 ;;
      *m) N="${ARG%m}"; U=60 ;;
      *s) N="${ARG%s}"; U=1 ;;
      *)  N="$ARG"; U=60 ;;
    esac
    if ! printf '%s' "$N" | grep -qE '^[0-9]+$' || [ "$((10#$N))" -le 0 ]; then
      echo "Read-only: invalid duration '$ARG'. Try 30m, 2h, 90s (bare = minutes), or 'off'." >&2
      exit 1
    fi

    scope_desc="this session only"
    TARGET="$SESS_FLAG"
    case "$MODE" in
      global|all|machine) TARGET="$GLOBAL_FLAG"; scope_desc="ALL sessions on this machine" ;;
      session|"")
        if [ -z "$SID" ]; then
          TARGET="$GLOBAL_FLAG"; scope_desc="ALL sessions (no session id available for per-session)"
        fi
        ;;
      *) echo "Read-only: unknown scope '$MODE'. Use 'session' (default) or 'global'." >&2; exit 1 ;;
    esac

    REQ=$((10#$N * U)); CAPPED=""
    if [ "$REQ" -gt "$MAX_SECONDS" ]; then REQ="$MAX_SECONDS"; CAPPED=" (capped at 2h)"; fi
    mkdir -p "$SCOPE" 2>/dev/null || true
    UNTIL=$(( $(date +%s) + REQ ))
    printf '%s\n' "$UNTIL" > "$TARGET"
    echo "Read-only: ON for $(fmt_dur "$REQ")${CAPPED} — blocking file edits and mutating commands for ${scope_desc} until $(fmt_time "$UNTIL")."
    echo "Reads, searches, and planning stay allowed. The safety hooks stay active too."
    echo "Turn off early: /sc-readonly off"
    ;;
esac
