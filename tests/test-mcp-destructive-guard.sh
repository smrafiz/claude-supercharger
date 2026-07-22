#!/usr/bin/env bash
# Suite for v2.22.14 mcp-destructive-guard — ASK on destructive ops for
# infra/filesystem/git MCP servers (structured tool calls that bypass the
# shell-channel guards).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks/mcp-destructive-guard.sh"

# verdict <tool_name> → ASK | ALLOW
verdict() {
  local j; j=$(printf '{"tool_name":"%s","cwd":"/tmp","tool_input":{}}' "$1")
  bash "$H" <<<"$j" 2>/dev/null | grep -q '"ask"' && echo ASK || echo ALLOW
}

# ---- destructive verbs → ASK ----
begin_test "mcp-destructive: aws terminate_instances asks"
[ "$(verdict "mcp__aws__terminate_instances")" = ASK ] && pass || fail "aws terminate not asked"
begin_test "mcp-destructive: kubernetes delete_namespace asks"
[ "$(verdict "mcp__kubernetes__delete_namespace")" = ASK ] && pass || fail "k8s delete not asked"
begin_test "mcp-destructive: docker prune asks"
[ "$(verdict "mcp__docker__system_prune")" = ASK ] && pass || fail "docker prune not asked"
begin_test "mcp-destructive: filesystem delete_file asks"
[ "$(verdict "mcp__filesystem__delete_file")" = ASK ] && pass || fail "fs delete not asked"
begin_test "mcp-destructive: git hard reset asks"
[ "$(verdict "mcp__git__reset_hard")" = ASK ] && pass || fail "git hard reset not asked"
begin_test "mcp-destructive: git force_push asks"
[ "$(verdict "mcp__git__force_push")" = ASK ] && pass || fail "git force push not asked"
begin_test "mcp-destructive: aws delete_bucket asks"
[ "$(verdict "mcp__aws__delete_bucket")" = ASK ] && pass || fail "aws delete_bucket not asked"

# ---- benign ops → ALLOW (no false asks) ----
begin_test "mcp-destructive: git commit not asked"
[ "$(verdict "mcp__git__commit")" = ALLOW ] && pass || fail "git commit falsely asked"
begin_test "mcp-destructive: git soft reset (bare 'reset') not asked"
[ "$(verdict "mcp__git__reset")" = ALLOW ] && pass || fail "git soft reset falsely asked"
begin_test "mcp-destructive: filesystem read_file not asked"
[ "$(verdict "mcp__filesystem__read_file")" = ALLOW ] && pass || fail "fs read falsely asked"
begin_test "mcp-destructive: aws list_instances not asked"
[ "$(verdict "mcp__aws__list_instances")" = ALLOW ] && pass || fail "aws list falsely asked"

# ---- kill switch ----
begin_test "mcp-destructive: SUPERCHARGER_MCP_DESTRUCTIVE_GUARD=0 disables it"
OUT=$(printf '{"tool_name":"mcp__aws__terminate_instances","tool_input":{}}' | SUPERCHARGER_MCP_DESTRUCTIVE_GUARD=0 bash "$H" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "kill switch did not disable it"

# ---- registration ----
begin_test "registration: mcp-destructive-guard registered (lib + plugin)"
grep -q 'mcp-destructive-guard.sh' "$REPO_DIR/lib/hooks.sh" && grep -q 'mcp-destructive-guard.sh' "$REPO_DIR/hooks/hooks.json" && pass || fail "not registered"

report
