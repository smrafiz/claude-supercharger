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

# autopilot (v2.23.40 — was missed in the first sweep; smart-approve reads plugin scope)
begin_test "autopilot: 30m global writes .autopilot-until to plugin scope"
_setup; bash "$REPO_DIR/tools/autopilot.sh" 30m global >/dev/null 2>&1
_pflag ".autopilot-until" && pass || fail "plugin autopilot flag not written"
begin_test "autopilot: off clears it from plugin scope"
bash "$REPO_DIR/tools/autopilot.sh" off >/dev/null 2>&1
_pflag ".autopilot-until" && fail "plugin autopilot flag not cleared" || pass
teardown_test_home

# notify-toggle (flags live at the state ROOT, not scope/)
begin_test "notify-toggle: off writes .no-desktop-notify to plugin ROOT"
_setup; bash "$REPO_DIR/tools/notify-toggle.sh" off >/dev/null 2>&1
[ -f "$HOME/$PDATA_REL/.no-desktop-notify" ] && pass || fail "plugin-root notify flag not written"
begin_test "notify-toggle: on clears it from plugin ROOT"
bash "$REPO_DIR/tools/notify-toggle.sh" on >/dev/null 2>&1
[ -f "$HOME/$PDATA_REL/.no-desktop-notify" ] && fail "plugin-root notify flag not cleared" || pass
teardown_test_home

# path-guard (SECURITY): a Write to the plugin-path guardrail-disable file must be blocked
begin_test "path-guard: blocks Write to plugin-path .disabled-security-categories"
_setup
_SEC=".disabled-securi""ty-categories"
_PAY=$(FP="$HOME/$PDATA_REL/scope/$_SEC" python3 -c 'import json,os;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":os.environ["FP"],"content":"x"},"cwd":"'"$HOME"'","session_id":"pg"}))')
_OUT=$(printf '%s' "$_PAY" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" SUPERCHARGER_HOME="$REPO_DIR" bash "$REPO_DIR/hooks/path-guard.sh" 2>&1)
printf '%s' "$_OUT" | grep -qi "self-mod" && pass || fail "plugin-path guardrail-disable write was NOT blocked"
begin_test "path-guard: still allows a normal source write"
_PAY2=$(python3 -c 'import json;print(json.dumps({"tool_name":"Write","tool_input":{"file_path":"'"$HOME"'/src/app.ts","content":"x"},"cwd":"'"$HOME"'","session_id":"pg"}))')
_OUT2=$(printf '%s' "$_PAY2" | SUPERCHARGER_STATE="$HOME/.claude/supercharger" SUPERCHARGER_HOME="$REPO_DIR" bash "$REPO_DIR/hooks/path-guard.sh" 2>&1)
printf '%s' "$_OUT2" | grep -qi "self-mod" && fail "normal write wrongly blocked" || pass
teardown_test_home

# v2.24.3: an explicit CLAUDE_PLUGIN_DATA must be the ONLY root. Isolation depends on
# this: the tool suites sandbox by setting that var (not by overriding HOME), so when
# v2.23.40 made the resolver glob $HOME unconditionally, `autopilot.sh off` inside a
# test deleted the developer's REAL autopilot/readonly/strict flags mid-session.
begin_test "sc_scope_dirs returns ONLY \$CLAUDE_PLUGIN_DATA when it is set"
OUT=$(CLAUDE_PLUGIN_DATA=/tmp/sc-explicit-root bash -c ". '$REPO_DIR/lib/utils.sh'; sc_scope_dirs")
{ [ "$OUT" = "/tmp/sc-explicit-root/scope" ]; } && pass || fail "expected only the explicit root, got: $OUT"

begin_test "a sandboxed tool run does not touch the real HOME scope dir"
_setup
REALFLAG="$HOME/.claude/supercharger/scope/.autopilot-until-sentinel"
printf '%s\n' "$(( $(date +%s) + 3600 ))" > "$REALFLAG"
SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/scope"
CLAUDE_PLUGIN_DATA="$SANDBOX" bash "$REPO_DIR/tools/autopilot.sh" off >/dev/null 2>&1
[ -f "$REALFLAG" ] && pass || fail "a CLAUDE_PLUGIN_DATA-sandboxed 'off' deleted a flag outside the sandbox"
rm -rf "$SANDBOX"
teardown_test_home

# the shared resolver emits the plugin scope dir when discovering (var unset)
begin_test "sc_scope_dirs emits the plugin scope dir"
_setup
OUT=$(source "$REPO_DIR/lib/utils.sh"; sc_scope_dirs)
printf '%s\n' "$OUT" | grep -q "$PDATA_REL/scope" && pass || fail "resolver missed the plugin dir: $OUT"
teardown_test_home

report
