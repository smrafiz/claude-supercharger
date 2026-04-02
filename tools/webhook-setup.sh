#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

source "$REPO_DIR/lib/utils.sh"
source "$REPO_DIR/lib/webhook.sh"

WEBHOOK_CONFIG="$HOME/.claude/supercharger/webhook.json"

show_usage() {
  echo "Usage: webhook-setup.sh [command]"
  echo ""
  echo "Commands:"
  echo "  (no args)   Interactive webhook setup"
  echo "  status      Show current webhook configuration"
  echo "  test        Send a test notification"
  echo "  enable      Enable webhook notifications"
  echo "  disable     Disable webhook notifications"
  echo "  remove      Remove webhook configuration"
  exit 0
}

# --- Status ---
if [[ "${1:-}" == "status" ]]; then
  if [ ! -f "$WEBHOOK_CONFIG" ]; then
    info "No webhook configured."
    echo "  Run: bash tools/webhook-setup.sh"
  else
    echo ""
    info "Webhook configuration:"
    WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG" python3 -c "
import json, os
with open(os.environ['WEBHOOK_CONFIG_FILE'], 'r') as f:
    config = json.load(f)
platform = config.get('platform', 'unknown')
enabled = config.get('enabled', False)
print(f'  Platform: {platform}')
print(f'  Enabled:  {enabled}')
if platform == 'telegram':
    print(f'  Chat ID:  {config.get(\"chat_id\", \"not set\")}')
else:
    url = config.get('url', 'not set')
    print(f'  URL:      {url[:40]}...' if len(url) > 40 else f'  URL:      {url}')
"
  fi
  exit 0
fi

# --- Test ---
if [[ "${1:-}" == "test" ]]; then
  if ! webhook_enabled; then
    error "No webhook configured or webhook is disabled."
    exit 1
  fi
  info "Sending test notification..."
  if send_webhook "Test notification from Claude Supercharger"; then
    success "Test notification sent!"
  else
    error "Failed to send test notification. Check your webhook URL."
    exit 1
  fi
  exit 0
fi

# --- Enable ---
if [[ "${1:-}" == "enable" ]]; then
  if [ ! -f "$WEBHOOK_CONFIG" ]; then
    error "No webhook configured. Run: bash tools/webhook-setup.sh"
    exit 1
  fi
  WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG" python3 -c "
import json, os
config_file = os.environ['WEBHOOK_CONFIG_FILE']
with open(config_file, 'r') as f:
    config = json.load(f)
config['enabled'] = True
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
"
  success "Webhook notifications enabled."
  exit 0
fi

# --- Disable ---
if [[ "${1:-}" == "disable" ]]; then
  if [ ! -f "$WEBHOOK_CONFIG" ]; then
    info "No webhook configured."
    exit 0
  fi
  WEBHOOK_CONFIG_FILE="$WEBHOOK_CONFIG" python3 -c "
import json, os
config_file = os.environ['WEBHOOK_CONFIG_FILE']
with open(config_file, 'r') as f:
    config = json.load(f)
config['enabled'] = False
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
"
  success "Webhook notifications disabled."
  exit 0
fi

# --- Remove ---
if [[ "${1:-}" == "remove" ]]; then
  rm -f "$WEBHOOK_CONFIG"
  success "Webhook configuration removed."
  exit 0
fi

# --- Help ---
if [[ "${1:-}" == "--help" ]]; then
  show_usage
fi

# --- Interactive Setup ---
echo ""
info "Webhook Notification Setup"
echo ""
echo -e "  ${BOLD}1)${NC} Slack"
echo -e "  ${BOLD}2)${NC} Discord"
echo -e "  ${BOLD}3)${NC} Telegram"
echo -e "  ${BOLD}4)${NC} Custom URL"
echo ""
read -rp "Select platform: " platform_choice

write_config() {
  local platform="$1"
  local json_content="$2"
  mkdir -p "$(dirname "$WEBHOOK_CONFIG")"
  echo "$json_content" > "$WEBHOOK_CONFIG"
  chmod 600 "$WEBHOOK_CONFIG"
}

case "$platform_choice" in
  1)
    PLATFORM="slack"
    echo ""
    info "Paste your Slack Incoming Webhook URL:"
    info "  (Create one at: https://api.slack.com/messaging/webhooks)"
    read -rp "> " WEBHOOK_URL
    write_config "$PLATFORM" "$(PLATFORM="$PLATFORM" URL="$WEBHOOK_URL" python3 -c "
import json, os
print(json.dumps({'platform': os.environ['PLATFORM'], 'url': os.environ['URL'], 'enabled': True}, indent=2))
")"
    ;;
  2)
    PLATFORM="discord"
    echo ""
    info "Paste your Discord Webhook URL:"
    info "  (Server Settings → Integrations → Webhooks → New Webhook → Copy URL)"
    read -rp "> " WEBHOOK_URL
    write_config "$PLATFORM" "$(PLATFORM="$PLATFORM" URL="$WEBHOOK_URL" python3 -c "
import json, os
print(json.dumps({'platform': os.environ['PLATFORM'], 'url': os.environ['URL'], 'enabled': True}, indent=2))
")"
    ;;
  3)
    PLATFORM="telegram"
    echo ""
    info "Paste your Telegram Bot Token:"
    info "  (Get one from @BotFather)"
    read -rp "Bot token: " BOT_TOKEN
    echo ""
    info "Paste your Telegram Chat ID:"
    info "  (Send a message to @userinfobot to get your chat ID)"
    read -rp "Chat ID: " CHAT_ID
    write_config "$PLATFORM" "$(PLATFORM="$PLATFORM" BOT_TOKEN="$BOT_TOKEN" CHAT_ID="$CHAT_ID" python3 -c "
import json, os
print(json.dumps({'platform': os.environ['PLATFORM'], 'bot_token': os.environ['BOT_TOKEN'], 'chat_id': os.environ['CHAT_ID'], 'enabled': True}, indent=2))
")"
    ;;
  4)
    PLATFORM="custom"
    echo ""
    info "Paste your webhook URL (will receive POST with JSON payload):"
    read -rp "> " WEBHOOK_URL
    write_config "$PLATFORM" "$(PLATFORM="$PLATFORM" URL="$WEBHOOK_URL" python3 -c "
import json, os
print(json.dumps({'platform': os.environ['PLATFORM'], 'url': os.environ['URL'], 'enabled': True}, indent=2))
")"
    ;;
  *)
    error "Invalid selection."
    exit 1
    ;;
esac
success "Webhook configured ($PLATFORM)"

echo ""
info "Sending test notification..."
if send_webhook "Webhook configured successfully"; then
  success "Test notification sent!"
else
  warn "Could not send test notification. Check your URL/token."
fi

echo ""
info "Manage with:"
echo "  bash tools/webhook-setup.sh status"
echo "  bash tools/webhook-setup.sh test"
echo "  bash tools/webhook-setup.sh disable"
echo "  bash tools/webhook-setup.sh enable"
echo "  bash tools/webhook-setup.sh remove"
