#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GEN="$REPO_DIR/tools/gen-plugin-commands.sh"
SRC_DIR="$REPO_DIR/configs/commands"
OUT_DIR="$REPO_DIR/commands"

echo "=== Plugin commands/ Generator Tests ==="

begin_test "gen-plugin-commands: committed commands/ is up to date"
OUT=$(bash "$GEN" --check 2>&1)
if [ $? -eq 0 ]; then pass; else fail "stale — run gen-plugin-commands.sh: $OUT"; fi

begin_test "commands/: exists and is non-empty"
CNT=$(ls "$OUT_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$CNT" -gt 0 ] && pass || fail "commands/ has no .md files"

begin_test "commands/: no generated file references ~/.claude/supercharger or \$HOME"
BAD=$(grep -rlE '~/\.claude/supercharger|\$HOME/\.claude/supercharger' "$OUT_DIR"/*.md 2>/dev/null)
[ -z "$BAD" ] && pass || fail "untransformed literals in: $BAD"

begin_test "commands/: meta-commands with native /plugin equivalents are NOT emitted"
if [ ! -f "$OUT_DIR/sc.md" ] && [ ! -f "$OUT_DIR/sc-update.md" ]; then pass; else fail "sc.md/sc-update.md should be skipped"; fi

begin_test "commands/: tool invocations use \${CLAUDE_PLUGIN_ROOT}/tools"
# perf.md invokes hook-perf.sh — must resolve to the plugin root, not $HOME
if grep -qE '\$\{CLAUDE_PLUGIN_ROOT\}/tools/hook-perf\.sh' "$OUT_DIR/perf.md"; then pass; else fail "perf.md tool path not rewritten to CLAUDE_PLUGIN_ROOT"; fi

begin_test "commands/: state reads use \${CLAUDE_PLUGIN_DATA}/scope"
if grep -qE '\$\{CLAUDE_PLUGIN_DATA\}/scope' "$OUT_DIR/sc-status.md"; then pass; else fail "sc-status.md scope path not rewritten to CLAUDE_PLUGIN_DATA"; fi

begin_test "commands/: project-memory refs (~/.claude/projects) are preserved, NOT rewritten"
# sc-status reads Claude file-memory under ~/.claude/projects — must stay literal
if grep -qE '~/\.claude/projects|\$HOME/\.claude/projects' "$OUT_DIR/sc-status.md"; then pass; else fail "project-memory ref was clobbered"; fi

begin_test "commands/: every non-skipped source command has a generated counterpart"
MISSING=""
for src in "$SRC_DIR"/*.md; do
  name="$(basename "$src" .md)"
  case " sc sc-update " in *" $name "*) continue ;; esac
  [ -f "$OUT_DIR/$name.md" ] || MISSING="$MISSING $name"
done
[ -z "$MISSING" ] && pass || fail "missing generated commands:$MISSING"

begin_test "plugin.json: agents[] matches configs/agents/*.md exactly (no drift)"
DRIFT=$(python3 -c "
import json, glob, os
p = json.load(open('$REPO_DIR/.claude-plugin/plugin.json'))
listed = sorted(os.path.basename(a) for a in p.get('agents', []))
ondisk = sorted(os.path.basename(f) for f in glob.glob('$REPO_DIR/configs/agents/*.md'))
print('' if listed == ondisk else 'listed=%s ondisk=%s' % (listed, ondisk))
" 2>/dev/null)
[ -z "$DRIFT" ] && pass || fail "plugin.json agents[] out of sync: $DRIFT"

begin_test "gen-plugin-commands: --check detects drift"
TMPF="$OUT_DIR/.__drift_probe.md"
printf 'drift\n' > "$TMPF"
bash "$GEN" --check >/dev/null 2>&1
RC=$?
rm -f "$TMPF"
[ "$RC" -ne 0 ] && pass || fail "--check did not flag an extra file as drift"

report
