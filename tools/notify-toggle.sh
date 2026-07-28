#!/usr/bin/env bash
# Claude Supercharger — Desktop Notification Toggle
# Usage: bash tools/notify-toggle.sh [on|off|sound|status]

# notify-helper reads these flags at ${CLAUDE_PLUGIN_DATA:-~/.claude/supercharger}/
# (the state ROOT, not scope/). This tool runs outside any hook (CLAUDE_PLUGIN_DATA
# unset), so write/clear/check across EVERY state root (classic + plugin) — else the
# toggle is a silent no-op on plugin installs. Roots = sc_scope_dirs minus /scope.
_NT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/utils.sh
source "$(dirname "$_NT_SCRIPT_DIR")/lib/utils.sh"

DIR="$HOME/.claude/supercharger"   # canonical root (for the re-enable hint)
OFF_BASE=".no-desktop-notify"
SOUND_BASE=".sound-only-notify"

_roots() { local d; while IFS= read -r d; do [ -n "$d" ] && printf '%s\n' "${d%/scope}"; done <<EOF
$(sc_scope_dirs)
EOF
}
_touch_all() { local base="$1" d; while IFS= read -r d; do mkdir -p "$d" 2>/dev/null || true; touch "$d/$base" 2>/dev/null || true; done <<EOF
$(_roots)
EOF
}
_rm_all() { local base="$1" d; while IFS= read -r d; do rm -f "$d/$base" 2>/dev/null || true; done <<EOF
$(_roots)
EOF
}
_any() { local base="$1" d; while IFS= read -r d; do [ -f "$d/$base" ] && return 0; done <<EOF
$(_roots)
EOF
  return 1; }

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

case "${1:-status}" in
  off)
    _touch_all "$OFF_BASE"
    _rm_all "$SOUND_BASE"
    echo -e "${YELLOW}○${NC} Desktop notifications disabled. (webhooks still active)"
    echo "  Re-enable: bash ~/.claude/supercharger/tools/notify-toggle.sh on"
    ;;
  sound)
    _touch_all "$SOUND_BASE"
    _rm_all "$OFF_BASE"
    echo -e "${GREEN}♪${NC} Sound-only mode — bell only, no popup."
    echo "  Disable: bash ~/.claude/supercharger/tools/notify-toggle.sh off"
    ;;
  on)
    _rm_all "$OFF_BASE"; _rm_all "$SOUND_BASE"
    echo -e "${GREEN}●${NC} Desktop notifications enabled."
    ;;
  status)
    if _any "$OFF_BASE"; then
      echo -e "${YELLOW}○${NC} Desktop notifications: OFF"
    elif _any "$SOUND_BASE"; then
      echo -e "${GREEN}♪${NC} Desktop notifications: SOUND ONLY"
    else
      echo -e "${GREEN}●${NC} Desktop notifications: ON"
    fi
    ;;
  *)
    echo "Usage: notify-toggle.sh [on|off|sound|status]"
    echo "  on     — popup + sound (default)"
    echo "  off    — silent (webhooks still fire)"
    echo "  sound  — bell only, no popup"
    echo "  status — show current setting"
    exit 1
    ;;
esac
