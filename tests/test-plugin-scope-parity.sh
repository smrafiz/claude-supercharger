#!/usr/bin/env bash
# v2.23.38 — skill/CLI tools that write control flags must reach the PLUGIN scope dir
# ($CLAUDE_PLUGIN_DATA/scope), not just the classic path. Hooks read the plugin path,
# but these tools run outside any hook (CLAUDE_PLUGIN_DATA unset), so they must glob
# the plugin data dirs. Regression guard for the whole bug class (see sc-toggle-plugin-
# path-divergence). Each tool: set a control -> flag lands in the plugin scope; clear
# -> flag removed from it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Plugin Scope Parity Tests ==="

PDATA_REL=".claude/plugins/data/claude-supercharger-claude-supercharger"

_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/$PDATA_REL/scope"
}
_pflag() { [ -f "$HOME/$PDATA_REL/scope/$1" ]; }   # flag present in plugin scope?

# profile-switch
begin_test "profile-switch: fast writes .profile to plugin scope"
_setup; bash "$REPO_DIR/tools/profile-switch.sh" fast >/dev/null 2>&1
_pflag ".profile" && pass || fail "plugin .profile not written"
begin_test "profile-switch: standard clears it from plugin scope"
bash "$REPO_DIR/tools/profile-switch.sh" standard >/dev/null 2>&1
_pflag ".profile" && fail "plugin .profile not cleared" || pass
teardown_test_home

# readonly
begin_test "readonly: 30m global writes .readonly-until to plugin scope"
_setup; bash "$REPO_DIR/tools/readonly.sh" 30m global >/dev/null 2>&1
_pflag ".readonly-until" && pass || fail "plugin readonly flag not written"
begin_test "readonly: off clears it from plugin scope"
bash "$REPO_DIR/tools/readonly.sh" off >/dev/null 2>&1
_pflag ".readonly-until" && fail "plugin readonly flag not cleared" || pass
teardown_test_home

# strict
begin_test "strict: 30m global writes .strict-until to plugin scope"
_setup; bash "$REPO_DIR/tools/strict.sh" 30m global >/dev/null 2>&1
_pflag ".strict-until" && pass || fail "plugin strict flag not written"
begin_test "strict: off clears it from plugin scope"
bash "$REPO_DIR/tools/strict.sh" off >/dev/null 2>&1
_pflag ".strict-until" && fail "plugin strict flag not cleared" || pass
teardown_test_home

# mcp-profile (stamp only; the server merge writes settings.json separately)
begin_test "mcp-profile: dev stamps .mcp-profile to plugin scope"
_setup; bash "$REPO_DIR/tools/mcp-profile.sh" dev >/dev/null 2>&1
_pflag ".mcp-profile" && pass || fail "plugin mcp-profile stamp not written"
teardown_test_home

# trust-mcp (security allowlist read by elicitation-guard)
begin_test "trust-mcp: add writes server to plugin scope allowlist"
_setup; bash "$REPO_DIR/tools/trust-mcp.sh" acmeserver >/dev/null 2>&1
{ _pflag ".trusted-elicitation-servers" && grep -qxF acmeserver "$HOME/$PDATA_REL/scope/.trusted-elicitation-servers"; } && pass || fail "plugin trust allowlist missing server"
begin_test "trust-mcp: --remove clears it from plugin scope allowlist"
bash "$REPO_DIR/tools/trust-mcp.sh" --remove acmeserver >/dev/null 2>&1
grep -qxF acmeserver "$HOME/$PDATA_REL/scope/.trusted-elicitation-servers" 2>/dev/null && fail "server still trusted in plugin scope" || pass
teardown_test_home

# the shared resolver emits the plugin dir when it exists
begin_test "sc_scope_dirs emits the plugin scope dir"
_setup
OUT=$(source "$REPO_DIR/lib/utils.sh"; sc_scope_dirs)
printf '%s\n' "$OUT" | grep -q "$PDATA_REL/scope" && pass || fail "resolver missed the plugin dir: $OUT"
teardown_test_home

report
