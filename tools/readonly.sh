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

# Flags are read by hooks at ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/scope, but
# this tool runs outside any hook (CLAUDE_PLUGIN_DATA unset) — so write/clear/read the
# flag by BASENAME across EVERY scope dir (classic + plugin). Relying on the env var
# fallback alone made readonly a silent no-op on plugin installs.
_RO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$(dirname "$_RO_SCRIPT_DIR")/lib/utils.sh"

MAX_SECONDS=7200   # 2h hard cap
SID="${CLAUDE_CODE_SESSION_ID:-}"
GLOBAL_BASE=".readonly-until"
SESS_BASE=""
[ -n "$SID" ] && SESS_BASE=".readonly-until-$SID"

fmt_time() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo '?'; }
fmt_dur()  { local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60));
  if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m $((s%60))s"; fi; }

_write_all() { local base="$1" val="$2" d; [ -n "$base" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] || continue; mkdir -p "$d" 2>/dev/null || true
    printf '%s\n' "$val" > "$d/$base" 2>/dev/null || true
  done <<EOF
$(sc_scope_dirs)
EOF
}
_rm_all() { local base="$1" d; [ -n "$base" ] || return 0
  while IFS= read -r d; do [ -n "$d" ] || continue; rm -f "$d/$base" 2>/dev/null || true
  done <<EOF
$(sc_scope_dirs)
EOF
}
# max remaining seconds for <basename> across all scope dirs (empty if none/expired).
remaining_of() { local base="$1" d f v now best=0; [ -n "$base" ] || return 0; now=$(date +%s)
  while IFS= read -r d; do f="$d/$base"; [ -f "$f" ] || continue
    v=$(cat "$f" 2>/dev/null || echo 0); printf '%s' "$v" | grep -qE '^[0-9]+$' || continue
    [ "$v" -gt "$now" ] && [ $((v - now)) -gt "$best" ] && best=$((v - now))
  done <<EOF
$(sc_scope_dirs)
EOF
  [ "$best" -gt 0 ] && echo "$best"; }

status() {
  local g s any=""
  g=$(remaining_of "$GLOBAL_BASE")
  s=$(remaining_of "$SESS_BASE")
  if [ -n "$s" ]; then echo "Read-only (this session): ON — $(fmt_dur "$s") remaining"; any=1; fi
  if [ -n "$g" ]; then echo "Read-only (global, all sessions): ON — $(fmt_dur "$g") remaining"; any=1; fi
  [ -z "$any" ] && echo "Read-only: OFF"
}

ARG="${1:-status}"
MODE="${2:-session}"

case "$ARG" in
  status|"") status ;;
  off)
    _rm_all "$GLOBAL_BASE"
    [ -n "$SESS_BASE" ] && _rm_all "$SESS_BASE"
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
    TARGET_BASE="$SESS_BASE"
    case "$MODE" in
      global|all|machine) TARGET_BASE="$GLOBAL_BASE"; scope_desc="ALL sessions on this machine" ;;
      session|"")
        if [ -z "$SID" ]; then
          TARGET_BASE="$GLOBAL_BASE"; scope_desc="ALL sessions (no session id available for per-session)"
        fi
        ;;
      *) echo "Read-only: unknown scope '$MODE'. Use 'session' (default) or 'global'." >&2; exit 1 ;;
    esac

    REQ=$((10#$N * U)); CAPPED=""
    if [ "$REQ" -gt "$MAX_SECONDS" ]; then REQ="$MAX_SECONDS"; CAPPED=" (capped at 2h)"; fi
    UNTIL=$(( $(date +%s) + REQ ))
    _write_all "$TARGET_BASE" "$UNTIL"
    echo "Read-only: ON for $(fmt_dur "$REQ")${CAPPED} — blocking file edits and mutating commands for ${scope_desc} until $(fmt_time "$UNTIL")."
    echo "Reads, searches, and planning stay allowed. The safety hooks stay active too."
    echo "Turn off early: /sc-readonly off"
    ;;
esac
