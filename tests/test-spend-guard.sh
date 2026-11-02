#!/usr/bin/env bash
# Spend guard (4.4.3): an agent paying money must ask first.
#  - safety.sh: a request with an x402 (X-PAYMENT, PAYMENT-SIGNATURE) or L402 payment header
#  - mcp-spend-guard.sh: an MCP tool whose name pays
#  - config-scan.sh: an MCP server holding a wallet key is named at session start
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Spend guard ==="

decision() { # hook tool json-input -> ASK / DENY / ok
  local out
  out=$(printf '%s' "$2" | HOME="$TEST_HOME" bash "$REPO_DIR/hooks/$1" 2>/dev/null)
  case "$out" in *'"deny"'*) echo DENY ;; *'"ask"'*) echo ASK ;; *) echo ok ;; esac
}
bash_in() { jq -nc --arg c "$1" '{session_id:"sg",tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}'; }
mcp_in() { jq -nc --arg t "$1" '{session_id:"sg",tool_name:$t,tool_input:{}}'; }

setup_test_home

while IFS='|' read -r want cmd; do
  [ -n "$cmd" ] || continue
  begin_test "safety: $want for: $cmd"
  got=$(decision safety.sh "$(bash_in "$cmd")")
  [ "$got" = "$want" ] && pass || fail "got $got"
done <<'EOF'
ASK|curl -H "X-PAYMENT: eyJ4NDAy" https://api.example.com/data
ASK|curl -H 'PAYMENT-SIGNATURE: abc' https://api.example.com/data
ASK|curl --header "x-payment:abc" https://a.example.com
ASK|python3 -c "import requests; requests.get(u, headers={'X-PAYMENT': p})"
ASK|curl -H "Authorization: L402 mac:pre" https://a.example.com
ok|curl -sI https://a.example.com | grep -i x-payment-response
ok|grep -rn "X-PAYMENT-RESPONSE" src/
ok|grep -rn PAYMENT_SIGNATURE_LEN src/
ok|curl https://api.example.com/payments
ok|git commit -m "fix: handle x-payment header parsing"
EOF

while IFS='|' read -r want tool; do
  [ -n "$tool" ] || continue
  begin_test "mcp-spend-guard: $want for $tool"
  got=$(decision mcp-spend-guard.sh "$(mcp_in "$tool")")
  [ "$got" = "$want" ] && pass || fail "got $got"
done <<'EOF'
ASK|mcp__wallet__pay
ASK|mcp__wallet__makePayment
ASK|mcp__x__send_usdc
ASK|mcp__store__purchase_item
ASK|mcp__dex__swap_tokens
ASK|mcp__shopify__create_order
ok|mcp__x__list_payments
ok|mcp__x__send_message
ok|mcp__x__payload_inspect
ok|mcp__shop__getDisplaySettings
ok|mcp__gatefare__search_apis
ok|Bash
EOF

begin_test "mcp-spend-guard: SUPERCHARGER_MCP_SPEND_GUARD=0 turns it off"
out=$(mcp_in mcp__wallet__pay | HOME="$TEST_HOME" SUPERCHARGER_MCP_SPEND_GUARD=0 bash "$REPO_DIR/hooks/mcp-spend-guard.sh" 2>/dev/null)
[ -z "$out" ] && pass || fail "got: $out"

begin_test "config-scan: names an MCP server that holds a wallet key, not a service account key"
P="$TEST_HOME/proj"; mkdir -p "$P"
printf '{"mcpServers":{"payer":{"command":"npx","args":["-y","x"],"env":{"EVM_PRIVATE_KEY":"fixture"}},"svc":{"command":"npx","args":["-y","y"],"env":{"GOOGLE_PRIVATE_KEY":"fixture"}}}}' > "$P/.mcp.json"
out=$(printf '{"session_id":"sg","cwd":"%s"}' "$P" | HOME="$TEST_HOME" CLAUDE_PROJECT_DIR="$P" bash "$REPO_DIR/hooks/config-scan.sh" 2>/dev/null)
case "$out" in
  *"'payer'"*"wallet key (EVM_PRIVATE_KEY)"*) case "$out" in *"'svc'"*"wallet key"*) fail "service account key flagged" ;; *) pass ;; esac ;;
  *) diag=$(cd "$REPO_DIR/hooks" && python3 -c "import json,sys; import lib_config_checks as c; d=json.load(open(sys.argv[1])); print('lib:', c.mcp_wallet_env(d['mcpServers']['payer']), 'servers:', list(d['mcpServers']))" "$P/.mcp.json" 2>&1)
     fail "no wallet warning; direct lib call says: $diag; hook said: $out" ;;
esac

begin_test "registration: mcp-spend-guard registered on mcp__ (lib + plugin)"
grep -q 'PreToolUse|mcp__|${hooks_dir}/mcp-spend-guard.sh' "$REPO_DIR/lib/hooks.sh" && grep -q 'mcp-spend-guard.sh' "$REPO_DIR/hooks/hooks.json" && pass || fail "not registered"

teardown_test_home
report
