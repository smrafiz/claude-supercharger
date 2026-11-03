#!/usr/bin/env bash
# Claude Supercharger — MCP spend guard
# Event: PreToolUse | Matcher: mcp__
#
# Pay-per-call MCP servers (x402, L402) and wallet servers let an agent spend money
# through a structured tool call, which no shell guard sees. This hook ASKS when
# the TOOL NAME says it pays: pay, purchase, buy, checkout, withdraw, swap, tip, or
# an action word (create, make, send, submit...) with payment, transfer, order,
# deposit, charge or funds. Words are matched whole, so `display` or `payload`
# never match. An ask is never auto-approved, not even under autopilot.
# Advisory + fail-open. Disable: SUPERCHARGER_MCP_SPEND_GUARD=0
set -uo pipefail
HOOKS_DIR="${BASH_SOURCE[0]%/*}"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh" 2>/dev/null || true

[ "${SUPERCHARGER_MCP_SPEND_GUARD:-1}" = "0" ] && exit 0

. "${BASH_SOURCE[0]%/*}/lib-stdin.sh"
. "${BASH_SOURCE[0]%/*}/lib-deny.sh"; sc_read_input _INPUT
TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$TOOL" in mcp__*__*) ;; *) exit 0 ;; esac

check_hook_disabled "mcp-spend-guard" 2>/dev/null && exit 0

# The tool's own name (after the server), split into lower-case words:
# makePayment -> make payment, send_usdc -> send usdc.
NAME="${TOOL##*__}"
WORDS=" $(printf '%s' "$NAME" | sed -E 's/([a-z0-9])([A-Z])/\1 \2/g; s/[^A-Za-z0-9]+/ /g' | tr '[:upper:]' '[:lower:]') "

SPEND=""
case "$WORDS" in
  *" pay "*|*" purchase "*|*" buy "*|*" checkout "*|*" withdraw "*|*" swap "*|*" tip "*|*" x402 "*|*" l402 "*) SPEND=1 ;;
esac
if [ -z "$SPEND" ]; then
  case "$WORDS" in
    *" payment "*|*" payments "*|*" transfer "*|*" order "*|*" deposit "*|*" charge "*|*" funds "*|*" usdc "*|*" eth "*|*" btc "*|*" sats "*)
      case "$WORDS" in
        " create "*|" make "*|" send "*|" submit "*|" execute "*|" initiate "*|" place "*|" confirm "*|" process "*|" complete "*|" sign "*|" approve "*) SPEND=1 ;;
      esac ;;
  esac
fi
[ -n "$SPEND" ] || exit 0

SC_ASK_KEEP=1 sc_decision ask "the MCP tool '$NAME' looks like it spends money (a payment, purchase, transfer or order). Pay-per-call and wallet MCP servers pay without asking, and the shell guards never see this call." "confirm the amount and the recipient first"
echo "[Supercharger] mcp-spend-guard: ASK on $TOOL" >&2
exit 0
