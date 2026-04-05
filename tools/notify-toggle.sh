#!/usr/bin/env bash
# Claude Supercharger — Desktop Notification Toggle
# Usage: bash tools/notify-toggle.sh [on|off|status]

FLAG="$HOME/.claude/supercharger/.no-desktop-notify"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

case "${1:-status}" in
  off)
    mkdir -p "$(dirname "$FLAG")"
    touch "$FLAG"
    echo -e "${YELLOW}○${NC} Desktop notifications disabled."
    echo "  Re-enable: bash tools/notify-toggle.sh on"
    ;;
  on)
    rm -f "$FLAG"
    echo -e "${GREEN}●${NC} Desktop notifications enabled."
    ;;
  status)
    if [ -f "$FLAG" ]; then
      echo -e "${YELLOW}○${NC} Desktop notifications: OFF"
    else
      echo -e "${GREEN}●${NC} Desktop notifications: ON"
    fi
    ;;
  *)
    echo "Usage: notify-toggle.sh [on|off|status]"
    exit 1
    ;;
esac
