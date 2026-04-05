#!/usr/bin/env bash
# Claude Supercharger — Desktop Notification Toggle
# Usage: bash tools/notify-toggle.sh [on|off|sound|status]

DIR="$HOME/.claude/supercharger"
FLAG_OFF="$DIR/.no-desktop-notify"
FLAG_SOUND="$DIR/.sound-only-notify"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

case "${1:-status}" in
  off)
    mkdir -p "$DIR"
    touch "$FLAG_OFF"
    rm -f "$FLAG_SOUND"
    echo -e "${YELLOW}○${NC} Desktop notifications disabled. (webhooks still active)"
    echo "  Re-enable: bash ~/.claude/supercharger/tools/notify-toggle.sh on"
    ;;
  sound)
    mkdir -p "$DIR"
    touch "$FLAG_SOUND"
    rm -f "$FLAG_OFF"
    echo -e "${GREEN}♪${NC} Sound-only mode — bell only, no popup."
    echo "  Disable: bash ~/.claude/supercharger/tools/notify-toggle.sh off"
    ;;
  on)
    rm -f "$FLAG_OFF" "$FLAG_SOUND"
    echo -e "${GREEN}●${NC} Desktop notifications enabled."
    ;;
  status)
    if [ -f "$FLAG_OFF" ]; then
      echo -e "${YELLOW}○${NC} Desktop notifications: OFF"
    elif [ -f "$FLAG_SOUND" ]; then
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
