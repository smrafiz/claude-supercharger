#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/mcp-egress-guard.sh"

echo "=== mcp-egress-guard Tests ==="
export SUPERCHARGER_NO_DEDUP=1

_run() { # <tool_name> <tool_input-json>
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2" \
    | bash "$HOOK" 2>/dev/null
}

begin_test "mcp-egress: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "mcp-egress: cloud metadata SSRF in MCP arg is blocked"
OUT=$(_run "mcp__fetch__get" '{"url":"http://169.254.169.254/latest/meta-data/"}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "metadata not blocked: $OUT"

begin_test "mcp-egress: discord webhook is blocked"
OUT=$(_run "mcp__http__post" '{"url":"https://discord.com/api/webhooks/123/abc","body":"data"}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "webhook not blocked: $OUT"

begin_test "mcp-egress: pastebin exfil target is blocked"
OUT=$(_run "mcp__fetch__post" '{"url":"https://transfer.sh/upload"}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "paste site not blocked: $OUT"

begin_test "mcp-egress: public IPFS gateway is blocked (v2.23.42)"
OUT=$(_run "mcp__fetch__get" '{"url":"https://dweb.link/ipfs/QmYwAPJzv5short"}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "ipfs gateway not blocked: $OUT"

begin_test "mcp-egress: /ipfs/<CID> path on a self-hosted gateway is blocked"
OUT=$(_run "mcp__fetch__get" '{"url":"https://gw.example.com/ipfs/bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "ipfs CID path not blocked: $OUT"

begin_test "mcp-egress: nested arg (list/dict) is still scanned"
OUT=$(_run "mcp__x__y" '{"opts":{"targets":["ok","http://169.254.169.254/x"]}}')
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "nested metadata not blocked: $OUT"

begin_test "mcp-egress: private-network target warns (not blocked)"
OUT=$(_run "mcp__http__get" '{"url":"http://192.168.1.1/admin"}')
echo "$OUT" | grep -q 'additionalContext' && ! echo "$OUT" | grep -q 'deny' && pass || fail "private net should warn: $OUT"

begin_test "mcp-egress: normal public URL passes silently"
OUT=$(_run "mcp__fetch__get" '{"url":"https://api.github.com/repos/x/y"}')
[ -z "$OUT" ] && pass || fail "normal URL wrongly flagged: $OUT"

begin_test "mcp-egress: non-mcp tool is ignored"
OUT=$(_run "Bash" '{"command":"curl http://169.254.169.254/"}')
[ -z "$OUT" ] && pass || fail "non-mcp wrongly handled: $OUT"

begin_test "mcp-egress: disabled via SUPERCHARGER_MCP_EGRESS=0"
OUT=$(printf '{"tool_name":"mcp__x__y","tool_input":{"url":"http://169.254.169.254/"}}' | SUPERCHARGER_MCP_EGRESS=0 bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "disable flag ignored: $OUT"

begin_test "mcp-egress: fail-open on malformed JSON"
OUT=$(printf 'not json' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected fail-open: $OUT"

report
