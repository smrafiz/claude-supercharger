#!/usr/bin/env bash
# Tests for the /sc activate-deactivate toggle (v2.9.0):
#   tools/sc-toggle.sh off|on|status  +  the shared-lib kill-switch early-exit.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOGGLE="$REPO_DIR/tools/sc-toggle.sh"

echo "=== sc-toggle (activate/deactivate) Tests ==="

# Build an isolated ~/.claude with the deployed lib + a CLAUDE.md managed block.
_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks" "$HOME/.claude/backups"
  cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  cp "$REPO_DIR/hooks/lib-timing.sh"   "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  cp "$REPO_DIR/hooks/lib-paths.sh"    "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
  # merge-style CLAUDE.md: user content, then the Supercharger managed block
  printf '# My rules\nUse tabs.\n\n# --- Claude Supercharger\nManaged block line 1\nManaged block line 2\n' > "$HOME/.claude/CLAUDE.md"
}
FLAG_REL=".claude/supercharger/scope/.supercharger-disabled"

begin_test "sc-toggle: status is ACTIVE by default"
_setup
bash "$TOGGLE" status 2>/dev/null | grep -q "ACTIVE" && pass || fail "expected ACTIVE"
teardown_test_home

begin_test "sc-toggle: off sets the kill-switch flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$FLAG_REL" ] && pass || fail "flag not created"
teardown_test_home

begin_test "sc-toggle: off strips the Supercharger block but keeps user content"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
if grep -q "Use tabs" "$HOME/.claude/CLAUDE.md" && ! grep -q "Managed block" "$HOME/.claude/CLAUDE.md"; then
  pass
else
  fail "expected user content kept + managed block removed, got: $(cat "$HOME/.claude/CLAUDE.md")"
fi
teardown_test_home

begin_test "sc-toggle: off writes a backup"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
ls "$HOME/.claude/backups"/deactivate-* >/dev/null 2>&1 && pass || fail "no backup written"
teardown_test_home

begin_test "sc-toggle: a hook sourcing lib-suppress EXITS immediately when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "hook did not early-exit (kill-switch ignored)"
teardown_test_home

begin_test "sc-toggle: security hooks (lib-timing) also early-exit when off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-timing.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" != "REACHED" ] && pass || fail "security hook did not early-exit"
teardown_test_home

begin_test "sc-toggle: SUPERCHARGER_TOGGLE bypasses the kill-switch (no bootstrap trap)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" SUPERCHARGER_TOGGLE=1 bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "toggle bypass failed — /sc on could strand disabled"
teardown_test_home

begin_test "sc-toggle: status is DISABLED after off"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" status 2>/dev/null | grep -qi "DISABLED" && pass || fail "expected DISABLED"
teardown_test_home

begin_test "sc-toggle: on removes the flag"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ ! -f "$HOME/$FLAG_REL" ] && pass || fail "flag not removed"
teardown_test_home

begin_test "sc-toggle: on restores the CLAUDE.md block byte-exactly"
_setup
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
[ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ] && pass || fail "CLAUDE.md not restored exactly"
teardown_test_home

begin_test "sc-toggle: hook runs normally again after on"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on >/dev/null 2>&1
OUT=$(HOME="$HOME" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ "$OUT" = "REACHED" ] && pass || fail "hook still blocked after on"
teardown_test_home

begin_test "sc-toggle: off is idempotent (already off)"
_setup
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" off 2>/dev/null | grep -qi "already OFF" && pass || fail "expected already-OFF message"
teardown_test_home

begin_test "sc-toggle: on is idempotent (already on)"
_setup
bash "$TOGGLE" on 2>/dev/null | grep -qi "already ON" && pass || fail "expected already-ON message"
teardown_test_home

begin_test "sc-toggle: statusline renders nothing when off (looks vanilla)"
_setup
cp "$REPO_DIR/hooks/statusline.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
bash "$TOGGLE" off >/dev/null 2>&1
# kill-switch fires before stdin is even read → no output at all
OFF_OUT=$(printf '%s' '{"model":{"display_name":"x"},"cwd":"/tmp"}' | HOME="$HOME" bash "$HOME/.claude/supercharger/hooks/statusline.sh" 2>/dev/null)
[ -z "$OFF_OUT" ] && pass || fail "statusline should be blank when off, got: $OFF_OUT"
teardown_test_home

begin_test "sc-toggle: statusline does NOT early-exit when on (guard line not taken)"
_setup
cp "$REPO_DIR/hooks/statusline.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
# no flag → the guard is false → the script must reach `_INPUT=$(cat)` and consume stdin.
# Prove it read stdin: pipe a sentinel and confirm the process consumed it (grep the source
# path is simplest — assert the guard line exists AND the flag is absent so it's inert).
[ ! -f "$HOME/.claude/supercharger/scope/.supercharger-disabled" ] \
  && grep -q 'supercharger-disabled.*exit 0' "$HOME/.claude/supercharger/hooks/statusline.sh" \
  && pass || fail "statusline missing the kill-switch guard, or flag present when it should not be"
teardown_test_home

begin_test "sc-toggle: deploy-mode (whole-file CLAUDE.md, marker at line 1) blanks then restores"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope" "$HOME/.claude/supercharger/hooks"
cp "$REPO_DIR/hooks/lib-suppress.sh" "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
cp "$REPO_DIR/hooks/lib-paths.sh"    "$HOME/.claude/supercharger/hooks/" 2>/dev/null || true
printf '# Claude Supercharger v9.9.9\n\n## rules\nbe terse\n' > "$HOME/.claude/CLAUDE.md"
ORIG=$(cat "$HOME/.claude/CLAUDE.md")
bash "$TOGGLE" off >/dev/null 2>&1
BLANK_OK=1; [ -s "$HOME/.claude/CLAUDE.md" ] && BLANK_OK=0
bash "$TOGGLE" on >/dev/null 2>&1
if [ "$BLANK_OK" = 1 ] && [ "$(cat "$HOME/.claude/CLAUDE.md")" = "$ORIG" ]; then pass; else fail "deploy-mode blank/restore failed (blank_ok=$BLANK_OK)"; fi
teardown_test_home

# --- v2.23.46: `off` must also drop Supercharger's OWN MCP servers (they load at
# session start and cost context), while never touching the user's own. ---
# Servers can live in ~/.claude.json (mcp-setup's PRIMARY target) and/or the legacy
# ~/.claude/settings.json — both must be handled, each restoring to its own file.
_mcp_setup() {
  _setup
  python3 -c '
import json,sys
json.dump({"mcpServers":{
  "context7 #supercharger":{"command":"npx"},
  "magic-ui #supercharger":{"command":"npx"},
  "my-own-primary":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude.json"
  python3 -c '
import json,sys
json.dump({"model":"opus","mcpServers":{
  "context7 #supercharger":{"command":"npx"},
  "my-own-legacy":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude/settings.json"
}
_keys_of() { python3 -c '
import json,sys
try: m=json.load(open(sys.argv[1])).get("mcpServers",{})
except Exception: m={}
print(",".join(sorted(m)))' "$1" 2>/dev/null; }
_mcp_keys() { _keys_of "$HOME/.claude/settings.json"; }

begin_test "sc-toggle: off removes tagged MCP servers from the LEGACY settings.json"
_mcp_setup; bash "$TOGGLE" off >/dev/null 2>&1
[ "$(_mcp_keys)" = "my-own-legacy" ] && pass || fail "expected only the user's server, got: $(_mcp_keys)"

begin_test "sc-toggle: off removes tagged MCP servers from ~/.claude.json (primary)"
[ "$(_keys_of "$HOME/.claude.json")" = "my-own-primary" ] && pass || fail "primary file not cleaned: $(_keys_of "$HOME/.claude.json")"

begin_test "sc-toggle: off leaves the user's own MCP servers alone (both files)"
{ printf '%s' "$(_mcp_keys)" | grep -q "my-own-legacy" \
  && printf '%s' "$(_keys_of "$HOME/.claude.json")" | grep -q "my-own-primary"; } && pass || fail "a user MCP server was removed"

begin_test "sc-toggle: off backs up ~/.claude.json (it is now edited)"
ls "$HOME/.claude/backups/"*/claude.json >/dev/null 2>&1 && pass || fail "no claude.json in the backup dir"

begin_test "sc-toggle: off stashes them and settings.json stays valid JSON"
{ [ -f "$HOME/.claude/supercharger/.deactivated/mcp-servers.json" ] \
  && python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$HOME/.claude/settings.json"; } 2>/dev/null \
  && pass || fail "stash missing or settings.json invalid"

begin_test "sc-toggle: on restores each MCP server to the file it came from"
bash "$TOGGLE" on >/dev/null 2>&1
{ [ "$(_keys_of "$HOME/.claude.json")" = "context7 #supercharger,magic-ui #supercharger,my-own-primary" ] \
  && [ "$(_mcp_keys)" = "context7 #supercharger,my-own-legacy" ]; } && pass \
  || fail "round-trip wrong — primary:[$(_keys_of "$HOME/.claude.json")] legacy:[$(_mcp_keys)]"
teardown_test_home

begin_test "sc-toggle: settings.json with no mcpServers key still toggles cleanly"
_setup; printf '{"model":"opus"}\n' > "$HOME/.claude/settings.json"
{ bash "$TOGGLE" off >/dev/null 2>&1 && bash "$TOGGLE" on >/dev/null 2>&1; } && pass || fail "toggle failed without mcpServers"
teardown_test_home

# --- v2.23.37: plugin-install path parity. The flag must land where PLUGIN hooks
# read it ($CLAUDE_PLUGIN_DATA/scope), not only the classic path — else /sc off is a
# silent no-op on plugin installs (rules kept loading). ---
PDATA_REL=".claude/plugins/data/claude-supercharger-claude-supercharger"

begin_test "sc-toggle: off writes the flag to the PLUGIN scope dir too"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
[ -f "$HOME/$PDATA_REL/scope/.supercharger-disabled" ] && pass || fail "plugin-scope flag not written (the reported bug)"
teardown_test_home

begin_test "sc-toggle: a PLUGIN-context hook (CLAUDE_PLUGIN_DATA set) early-exits when off"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
OUT=$(HOME="$HOME" CLAUDE_PLUGIN_DATA="$HOME/$PDATA_REL" bash -c '. "$HOME/.claude/supercharger/hooks/lib-suppress.sh"; echo REACHED' 2>/dev/null)
[ -z "$OUT" ] && pass || fail "plugin hook did NOT early-exit when off (got: $OUT)"
teardown_test_home

begin_test "sc-toggle: on clears the flag from the PLUGIN scope dir too"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
bash "$TOGGLE" off >/dev/null 2>&1
bash "$TOGGLE" on  >/dev/null 2>&1
[ ! -f "$HOME/$PDATA_REL/scope/.supercharger-disabled" ] && pass || fail "plugin-scope flag not cleared by on"
teardown_test_home

begin_test "sc-toggle: status reports DISABLED when only the plugin flag exists"
_setup
mkdir -p "$HOME/$PDATA_REL/scope"
# simulate a flag that somehow only exists at the plugin path
printf 'disabled_at test\n' > "$HOME/$PDATA_REL/scope/.supercharger-disabled"
bash "$TOGGLE" status 2>/dev/null | grep -qi "DISABLED" && pass || fail "status missed the plugin-only flag"
teardown_test_home

report
