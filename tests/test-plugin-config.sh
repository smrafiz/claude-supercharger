#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SEED="$REPO_DIR/hooks/plugin-config-seed.sh"
PJ="$REPO_DIR/.claude-plugin/plugin.json"
MJ="$REPO_DIR/.claude-plugin/marketplace.json"

echo "=== Plugin userConfig + first-run seeder Tests ==="

begin_test "plugin-config-seed: seeds scope files from CLAUDE_PLUGIN_OPTION_* (plugin mode)"
D=$(mktemp -d)
CLAUDE_PLUGIN_ROOT=/plug CLAUDE_PLUGIN_DATA="$D" \
  CLAUDE_PLUGIN_OPTION_ROLE=writer CLAUDE_PLUGIN_OPTION_ECONOMY_TIER=minimal CLAUDE_PLUGIN_OPTION_MCP_PROFILE=full \
  bash "$SEED" </dev/null
if [ "$(cat "$D/scope/.economy-tier" 2>/dev/null)" = "minimal" ] \
   && [ "$(cat "$D/scope/.mcp-profile" 2>/dev/null)" = "full" ] \
   && [ "$(cat "$D/scope/.roles" 2>/dev/null)" = "writer" ]; then pass; else fail "seed values wrong"; fi
rm -rf "$D"

begin_test "plugin-config-seed: never clobbers an existing scope file (runtime switch wins)"
D=$(mktemp -d); mkdir -p "$D/scope"; printf 'lean\n' > "$D/scope/.economy-tier"
CLAUDE_PLUGIN_ROOT=/plug CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_ECONOMY_TIER=minimal bash "$SEED" </dev/null
[ "$(cat "$D/scope/.economy-tier")" = "lean" ] && pass || fail "clobbered an existing file"
rm -rf "$D"

begin_test "plugin-config-seed: NO-OP under installer runtime (CLAUDE_PLUGIN_ROOT unset)"
D=$(mktemp -d)
CLAUDE_PLUGIN_DATA="$D" CLAUDE_PLUGIN_OPTION_ROLE=writer bash "$SEED" </dev/null
[ ! -e "$D/scope" ] && pass || fail "seeded scope under the installer runtime"
rm -rf "$D"

begin_test "plugin-config-seed: defaults when no userConfig provided"
D=$(mktemp -d)
CLAUDE_PLUGIN_ROOT=/plug CLAUDE_PLUGIN_DATA="$D" bash "$SEED" </dev/null
if [ "$(cat "$D/scope/.economy-tier" 2>/dev/null)" = "standard" ] \
   && [ "$(cat "$D/scope/.mcp-profile" 2>/dev/null)" = "light" ] \
   && [ "$(cat "$D/scope/.roles" 2>/dev/null)" = "developer" ]; then pass; else fail "wrong defaults"; fi
rm -rf "$D"

begin_test "plugin.json: userConfig declares role/economy_tier/mcp_profile with defaults"
MISS=$(python3 -c "
import json
u=json.load(open('$PJ')).get('userConfig',{})
need=['role','economy_tier','mcp_profile']
bad=[k for k in need if k not in u or 'default' not in u[k] or u[k].get('type')!='string']
print(','.join(bad))
" 2>/dev/null)
[ -z "$MISS" ] && pass || fail "userConfig missing/malformed: $MISS"

begin_test "plugin.json: userConfig keys match the CLAUDE_PLUGIN_OPTION_* the seeder reads"
# key -> CLAUDE_PLUGIN_OPTION_<UPPER>; the seeder must reference each uppercased key.
BAD=""
for k in ROLE ECONOMY_TIER MCP_PROFILE; do
  grep -q "CLAUDE_PLUGIN_OPTION_$k" "$SEED" || BAD="$BAD $k"
done
[ -z "$BAD" ] && pass || fail "seeder does not read:$BAD"

begin_test "prompt-layer-inject: role/tier fall back through CLAUDE_PLUGIN_OPTION_*"
if grep -q 'CLAUDE_PLUGIN_OPTION_ROLE' "$REPO_DIR/hooks/prompt-layer-inject.sh" \
   && grep -q 'CLAUDE_PLUGIN_OPTION_ECONOMY_TIER' "$REPO_DIR/hooks/prompt-layer-inject.sh"; then pass; else fail "inject not wired to userConfig env"; fi

begin_test "marketplace.json: no invalid 'id' / 'metadata.homepage' fields"
BAD=$(python3 -c "
import json
m=json.load(open('$MJ'))
bad=[]
if 'id' in m: bad.append('id')
if 'homepage' in m.get('metadata',{}): bad.append('metadata.homepage')
print(','.join(bad))
" 2>/dev/null)
[ -z "$BAD" ] && pass || fail "invalid marketplace fields present: $BAD"

# 2.17: installer-promotion nudge (plugin edition can't set the status line) fires
# ONCE and never under the installer.
SEED="$REPO_DIR/hooks/plugin-config-seed.sh"
begin_test "plugin-config-seed: statusline nudge shows once, silent thereafter"
ND=$(mktemp -d)
n1=$(printf '{"session_id":"x"}' | CLAUDE_PLUGIN_ROOT="$REPO_DIR" CLAUDE_PLUGIN_DATA="$ND" bash "$SEED" 2>&1 | grep -c "status line isn't available")
n2=$(printf '{"session_id":"x"}' | CLAUDE_PLUGIN_ROOT="$REPO_DIR" CLAUDE_PLUGIN_DATA="$ND" bash "$SEED" 2>&1 | grep -c "status line isn't available")
[ "$n1" = "1" ] && [ "$n2" = "0" ] && pass || fail "nudge once-behavior wrong (1st=$n1 2nd=$n2)"
rm -rf "$ND"

begin_test "plugin-config-seed: no nudge under the installer runtime"
n=$(printf '{"session_id":"x"}' | env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA bash "$SEED" 2>&1 | grep -c "status line")
[ "$n" = "0" ] && pass || fail "nudge leaked into installer runtime"

report
