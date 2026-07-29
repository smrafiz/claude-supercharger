#!/usr/bin/env bash
# v2.23.48 — profile-aware custom MCP servers. Claude Code owns ADDING a server;
# this makes one you already added participate in Supercharger's context profiles.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/mcp-custom.sh"
echo "=== Custom MCP Server Tests ==="

_mc_setup() {
  setup_test_home
  mkdir -p "$HOME/.claude/supercharger"
  export SUPERCHARGER_MCP_CUSTOM="$HOME/.claude/supercharger/mcp-custom.json"
  # an HTTP server with url+headers — a shape the curated pipe format can't express
  python3 -c '
import json,sys
json.dump({"mcpServers":{
 "sentry":{"type":"http","url":"https://mcp.sentry.dev/mcp","headers":{"Authorization":"Bearer x"}},
 "keepme":{"command":"node"}}}, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude.json"
  printf '{}\n' > "$HOME/.claude/settings.json"
  printf 'developer\n' > "$HOME/.claude/supercharger/.roles"
}
_keys() { python3 -c '
import json,sys
try: m=json.load(open(sys.argv[1])).get("mcpServers",{})
except Exception: m={}
print(",".join(sorted(m)))' "$HOME/.claude.json" 2>/dev/null; }
_switch() { ( . "$REPO_DIR/lib/mcp.sh"; merge_mcp_into_settings developer "$1" ) >/dev/null 2>&1; }

begin_test "adopt refuses a server that isn't configured"
_mc_setup
bash "$TOOL" adopt nosuchserver >/dev/null 2>&1 && fail "should exit non-zero" || pass

begin_test "adopt rejects an invalid profile name"
bash "$TOOL" adopt sentry devv >/dev/null 2>&1 && fail "should reject bad profile" || pass

begin_test "adopt takes ownership — the untagged original is not left behind"
bash "$TOOL" adopt sentry dev,full >/dev/null 2>&1
[ "$(_keys)" = "keepme" ] && pass || fail "expected only keepme, got: $(_keys)"

begin_test "profile switch excludes a server outside its profile list"
_switch light
printf '%s' "$(_keys)" | grep -q "sentry" && fail "sentry should be absent at light: $(_keys)" || pass

begin_test "profile switch adds it back, exactly once, for an included profile"
_switch dev
N=$(python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))["mcpServers"]
print(len([k for k in m if k.startswith("sentry")]))' "$HOME/.claude.json")
[ "$N" = "1" ] && pass || fail "expected exactly 1 sentry entry, got $N"

begin_test "the raw entry survives (http url + headers preserved)"
python3 -c '
import json,sys
m=json.load(open(sys.argv[1]))["mcpServers"]
e=[v for k,v in m.items() if k.startswith("sentry")][0]
sys.exit(0 if e.get("url")=="https://mcp.sentry.dev/mcp" and e.get("headers") else 1)' "$HOME/.claude.json" \
  && pass || fail "url/headers lost through the profile round-trip"

begin_test "a user's own MCP server is never touched"
printf '%s' "$(_keys)" | grep -q "keepme" && pass || fail "user server disappeared"

begin_test "remove hands the server back untagged instead of losing it"
bash "$TOOL" remove sentry >/dev/null 2>&1
_switch light
python3 -c '
import json,sys
m=json.load(open(sys.argv[1])).get("mcpServers",{})
# exact untagged key present, and no managed copy left over
sys.exit(0 if "sentry" in m and not any(k.startswith("sentry ") for k in m) else 1)' "$HOME/.claude.json" \
  && pass || fail "server not handed back untagged: $(_keys)"
teardown_test_home

begin_test "list works with an empty/missing registry"
_mc_setup
bash "$TOOL" list 2>&1 | grep -qi "no custom mcp" && pass || fail "unexpected list output"
teardown_test_home

report
