#!/usr/bin/env bash
# Claude Supercharger — Strict mode (time-boxed "ask me everything")
# Writes an expiry timestamp to a scope flag. While now < that time, smart-approve
# auto-approves NOTHING — every tool call falls through to Claude Code's normal
# permission prompt, including the read-only calls it would usually wave through.
# It also OVERRIDES autopilot (a strict window active in this session suppresses an
# autopilot window). The tighten end of the modes family: autopilot loosens, strict
# tightens the approval flow. Expiry is per request; no timer. Hard-capped at 2h.
#
# (This does not add blocks — the always-on safety hooks already do that. Strict only
#  removes auto-approvals, so you're asked to confirm more, e.g. near a deploy.)
#
# Scope (mirrors autopilot / readonly):
#   per-session (DEFAULT) — only this session is strict.
#     flag: scope/.strict-until-<session-id>  (session id from CLAUDE_CODE_SESSION_ID)
#   global — every session on the machine is strict.
#     flag: scope/.strict-until
#
# Usage: strict.sh <duration> [session|global]   e.g. 30m, 2h, 90s, 45 (bare = min)
#        strict.sh off | status
set -uo pipefail

# Flags are read by hooks at ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/scope; this
# tool runs outside any hook (CLAUDE_PLUGIN_DATA unset), so write/clear/read by BASENAME
# across EVERY scope dir (classic + plugin) — else strict is a no-op on plugin installs.
_ST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$(dirname "$_ST_SCRIPT_DIR")/lib/utils.sh"

MAX_SECONDS=7200   # 2h hard cap
SID="${CLAUDE_CODE_SESSION_ID:-}"
GLOBAL_BASE=".strict-until"
SESS_BASE=""
[ -n "$SID" ] && SESS_BASE=".strict-until-$SID"

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
  if [ -n "$s" ]; then echo "Strict (this session): ON — $(fmt_dur "$s") remaining"; any=1; fi
  if [ -n "$g" ]; then echo "Strict (global, all sessions): ON — $(fmt_dur "$g") remaining"; any=1; fi
  [ -z "$any" ] && echo "Strict: OFF"
}

ARG="${1:-status}"
MODE="${2:-session}"

case "$ARG" in
  status|"") status ;;
  off)
    _rm_all "$GLOBAL_BASE"
    [ -n "$SESS_BASE" ] && _rm_all "$SESS_BASE"
    echo "Strict: OFF — normal auto-approvals restored."
    ;;
  *)
    case "$ARG" in
      *h) N="${ARG%h}"; U=3600 ;;
      *m) N="${ARG%m}"; U=60 ;;
      *s) N="${ARG%s}"; U=1 ;;
      *)  N="$ARG"; U=60 ;;
    esac
    if ! printf '%s' "$N" | grep -qE '^[0-9]+$' || [ "$((10#$N))" -le 0 ]; then
      echo "Strict: invalid duration '$ARG'. Try 30m, 2h, 90s (bare = minutes), or 'off'." >&2
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
      *) echo "Strict: unknown scope '$MODE'. Use 'session' (default) or 'global'." >&2; exit 1 ;;
    esac

    REQ=$((10#$N * U)); CAPPED=""
    if [ "$REQ" -gt "$MAX_SECONDS" ]; then REQ="$MAX_SECONDS"; CAPPED=" (capped at 2h)"; fi
    UNTIL=$(( $(date +%s) + REQ ))
    _write_all "$TARGET_BASE" "$UNTIL"
    echo "Strict: ON for $(fmt_dur "$REQ")${CAPPED} — auto-approving nothing (you'll be asked to confirm every call) for ${scope_desc} until $(fmt_time "$UNTIL")."
    echo "Overrides autopilot while active. The safety hooks stay active as always."
    echo "Turn off early: /sc-strict off"
    ;;
esac
