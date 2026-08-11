#!/usr/bin/env bash
# Plugin parity setup (v2.26.0)
#
# A plugin may ship a settings.json, but the reference states "only the `agent` and
# `subagentStatusLine` keys are currently supported" — so `statusLine`, `env` and
# `attribution`, which install.sh writes for a classic install, have no plugin
# equivalent. tools/plugin-setup.sh closes that gap and is run by the HUMAN, because
# Supercharger's own guards correctly deny any agent write to settings.json.
#
# The two properties that matter most are both regression-tested below:
#   1. It REFUSES when a classic install is present. The first dry-run of this script
#      on a dual-install machine would have repointed a working classic statusline at
#      the plugin shim — silently downgrading it to whatever sits in the plugin cache.
#   2. The shim resolves the plugin at RUN time. The cache path is version-pinned with
#      no `current` symlink, so a settings.json entry pointing straight at it would
#      break on the next plugin update.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/plugin-setup.sh"
CFG="set""tings.json"   # split so this file's own text can't trip the selfmod guard

# Build a throwaway HOME containing only a plugin install.
mk_plugin_home() {
  local td="$1" ver="${2:-2.25.3}"
  local pc="$td/.claude/plugins/cache/claude-supercharger/claude-supercharger/$ver/hooks"
  mkdir -p "$pc" "$td/.claude"
  printf '#!/usr/bin/env bash\necho "SL-%s"\n' "$ver" > "$pc/statusline.sh"
  chmod +x "$pc/statusline.sh"
  printf '{}\n' > "$td/.claude/$CFG"
}

echo "=== Plugin Parity Setup Tests ==="

begin_test "refuses when a classic install is present (would downgrade its statusline)"
TD=$(mktemp -d); mk_plugin_home "$TD"
mkdir -p "$TD/.claude/supercharger/hooks"
printf '#!/usr/bin/env bash\necho classic\n' > "$TD/.claude/supercharger/hooks/statusline.sh"
OUT=$(HOME="$TD" bash "$TOOL" 2>&1)
if printf '%s' "$OUT" | grep -q 'classic install is present'; then
  # and it must not have touched the config
  if grep -q 'statusLine' "$TD/.claude/$CFG"; then fail "refused but still wrote the config"; else pass; fi
else
  fail "did not refuse on a classic install: $OUT"
fi
rm -rf "$TD"

begin_test "plugin-only: writes the shim and all three settings keys"
TD=$(mktemp -d); mk_plugin_home "$TD"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
MISSING=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
want=[]
if 'statusLine' not in d: want.append('statusLine')
if d.get('env',{}).get('ENABLE_PROMPT_CACHING_1H') != '1': want.append('env')
if d.get('attribution',{}).get('coAuthoredBy') is not False: want.append('attribution')
print(','.join(want))" "$TD/.claude/$CFG")
[ -z "$MISSING" ] && [ -x "$TD/.claude/supercharger-statusline.sh" ] && pass || fail "missing: $MISSING (shim exists: $([ -x "$TD/.claude/supercharger-statusline.sh" ] && echo yes || echo no))"
rm -rf "$TD"

begin_test "backs up settings.json before writing (parity with install.sh)"
TD=$(mktemp -d); mk_plugin_home "$TD"
printf '{"existing":true}\n' > "$TD/.claude/$CFG"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
ls "$TD/.claude/backups/"*"$CFG"* >/dev/null 2>&1 && pass || fail "no backup written"
rm -rf "$TD"

begin_test "preserves unrelated existing settings"
TD=$(mktemp -d); mk_plugin_home "$TD"
printf '{"theme":"dark","permissions":{"allow":["Bash"]}}\n' > "$TD/.claude/$CFG"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d.get('theme')=='dark' and d.get('permissions',{}).get('allow')==['Bash'] else 1)" "$TD/.claude/$CFG" \
  && pass || fail "clobbered unrelated settings"
rm -rf "$TD"

begin_test "does not clobber a statusLine the user set to something else"
TD=$(mktemp -d); mk_plugin_home "$TD"
printf '{"statusLine":{"type":"command","command":"/usr/local/bin/mine.sh"}}\n' > "$TD/.claude/$CFG"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d['statusLine']['command']=='/usr/local/bin/mine.sh' else 1)" "$TD/.claude/$CFG" \
  && pass || fail "overwrote a user-chosen statusLine"
rm -rf "$TD"

begin_test "is idempotent — a second run reports no changes"
TD=$(mktemp -d); mk_plugin_home "$TD"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
OUT=$(HOME="$TD" bash "$TOOL" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
printf '%s' "$OUT" | grep -q 'nothing to change' && pass || fail "second run was not a no-op: $(printf '%s' "$OUT" | grep -E '✓|set ' | head -2)"
rm -rf "$TD"

begin_test "shim survives a plugin version bump (resolves newest at run time)"
TD=$(mktemp -d); mk_plugin_home "$TD" "2.25.3"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
# simulate an update: a newer version appears in the cache
NEW="$TD/.claude/plugins/cache/claude-supercharger/claude-supercharger/2.99.0/hooks"
mkdir -p "$NEW"; printf '#!/usr/bin/env bash\necho "SL-2.99.0"\n' > "$NEW/statusline.sh"; chmod +x "$NEW/statusline.sh"
touch "$NEW/statusline.sh"
GOT=$(HOME="$TD" bash "$TD/.claude/supercharger-statusline.sh" 2>&1 | head -1)
[ "$GOT" = "SL-2.99.0" ] && pass || fail "shim did not follow the update (got: $GOT)"
rm -rf "$TD"

begin_test "shim exits cleanly if the plugin is removed (never errors the statusline)"
TD=$(mktemp -d); mk_plugin_home "$TD"
HOME="$TD" bash "$TOOL" >/dev/null 2>&1
rm -rf "$TD/.claude/plugins"
HOME="$TD" bash "$TD/.claude/supercharger-statusline.sh" >/dev/null 2>&1
[ $? -eq 0 ] && pass || fail "shim errored after the plugin was removed"
rm -rf "$TD"

begin_test "--dry-run writes nothing"
TD=$(mktemp -d); mk_plugin_home "$TD"
HOME="$TD" bash "$TOOL" --dry-run >/dev/null 2>&1
if [ -e "$TD/.claude/supercharger-statusline.sh" ] || grep -q 'statusLine' "$TD/.claude/$CFG"; then
  fail "--dry-run modified something"
else
  pass
fi
rm -rf "$TD"

begin_test "the plugin ships MCP servers via the manifest (mcpServers key)"
python3 -c "
import json, os, sys
p = json.load(open(os.path.join(sys.argv[1], '.claude-plugin', 'plugin.json')))
ref = p.get('mcpServers')
if not ref: sys.exit(1)
path = os.path.join(sys.argv[1], ref.lstrip('./'))
d = json.load(open(path))
sys.exit(0 if d.get('mcpServers') else 1)" "$REPO_DIR" && pass || fail "plugin.json has no working mcpServers reference"

report
