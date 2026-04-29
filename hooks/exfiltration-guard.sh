#!/usr/bin/env bash
# Claude Supercharger — Data Exfiltration Guard
# Event: PreToolUse | Matcher: Bash
# Blocks data-exfiltration vectors:
#   - DNS tunneling tools (dnscat, iodine, dns2tcp) — always blocked
#   - Cloud uploads of sensitive files (.env, ~/.ssh, .pem, /etc/shadow)
#     via aws s3, gsutil, az storage, azcopy, rclone, s3cmd
# Inspired by vaporif/parry exfil patterns (MIT).

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "exfiltration-guard" && exit 0

COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Fast-path: if command has no exfil-related keywords, skip python3 fork.
# Triggers for: cloud upload tools, network tools that can POST, DNS exfil tools.
case "$COMMAND" in
  *aws*|*gsutil*|*azcopy*|*az\ storage*|*rclone*|*s3cmd*) ;;
  *curl*|*wget*|*nc*|*netcat*) ;;
  *dnscat*|*iodine*|*dns2tcp*|*dnsexfil*) ;;
  *) exit 0 ;;
esac

block() {
  local reason="$1"
  echo "" >&2
  echo "Supercharger blocked likely data-exfiltration." >&2
  echo "  Reason : $reason" >&2
  echo "  Command: ${COMMAND:0:120}" >&2
  echo "  Run it in your terminal directly if this is intentional." >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

REASON=$(CMD="$COMMAND" python3 "$HOOKS_DIR/exfiltration-detect.py" 2>/dev/null)
if [ -n "$REASON" ]; then
  block "$REASON"
fi
exit 0
