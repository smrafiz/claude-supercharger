#!/usr/bin/env bash
# Claude Supercharger — Autopilot (time-boxed auto-approve)
# Writes scope/.autopilot-until <epoch>. While now < that time, smart-approve.sh
# auto-approves EVERY PermissionRequest, so the user isn't prompted. The PreToolUse
# safety hooks still fire, so dangerous commands stay blocked — this only removes
# the yes/no friction, not the safety floor. Expiry is evaluated per request; no
# background timer. Hard-capped at 2h so it can't be left on forever.
#
# Usage: autopilot.sh <duration>   e.g. 30m, 2h, 90s, 45  (bare number = minutes)
#        autopilot.sh off | status
set -uo pipefail

# Same state root the reader (lib-smart-approve.sh) resolves — installer default,
# CLAUDE_PLUGIN_DATA under the plugin runtime.
SC_STATE="${CLAUDE_PLUGIN_DATA:-$HOME/.claude/supercharger}"
SCOPE="$SC_STATE/scope"
FLAG="$SCOPE/.autopilot-until"
MAX_SECONDS=7200   # 2h hard cap

# Portable epoch -> HH:MM (BSD/macOS `date -r`, GNU/Linux `date -d @`).
fmt_time() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null || echo '?'; }
fmt_dur()  { local s="$1" h m; h=$((s/3600)); m=$(((s%3600)/60));
  if [ "$h" -gt 0 ]; then echo "${h}h ${m}m"; else echo "${m}m $((s%60))s"; fi; }

status() {
  if [ -f "$FLAG" ]; then
    local until now; until=$(cat "$FLAG" 2>/dev/null || echo 0); now=$(date +%s)
    if printf '%s' "$until" | grep -qE '^[0-9]+$' && [ "$until" -gt "$now" ]; then
      echo "Autopilot: ON — $(fmt_dur $((until - now))) remaining (until $(fmt_time "$until"))"
      return 0
    fi
  fi
  echo "Autopilot: OFF"
}

ARG="${1:-status}"

case "$ARG" in
  status|"") status ;;
  off)
    rm -f "$FLAG" 2>/dev/null || true
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
    REQ=$((10#$N * U)); CAPPED=""
    if [ "$REQ" -gt "$MAX_SECONDS" ]; then REQ="$MAX_SECONDS"; CAPPED=" (capped at 2h)"; fi
    mkdir -p "$SCOPE" 2>/dev/null || true
    UNTIL=$(( $(date +%s) + REQ ))
    printf '%s\n' "$UNTIL" > "$FLAG"
    echo "Autopilot: ON for $(fmt_dur "$REQ")${CAPPED} — auto-approving all prompts until $(fmt_time "$UNTIL")."
    echo "Safety hooks stay active: rm -rf, force-push, credential leaks, curl|bash and the like are still blocked."
    echo "Turn off early: /sc-autopilot off"
    ;;
esac
