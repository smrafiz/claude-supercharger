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
if grep -qE '\$\{CLAUDE_PLUGIN_DATA\}/scope' "$OUT_DIR/status.md"; then pass; else fail "status.md scope path not rewritten to CLAUDE_PLUGIN_DATA"; fi

begin_test "commands/: project-memory refs (~/.claude/projects) are preserved, NOT rewritten"
# sc-status reads Claude file-memory under ~/.claude/projects — must stay literal
if grep -qE '~/\.claude/projects|\$HOME/\.claude/projects' "$OUT_DIR/status.md"; then pass; else fail "project-memory ref was clobbered"; fi

begin_test "commands/: every non-skipped source command has a generated counterpart"
MISSING=""
for src in "$SRC_DIR"/*.md; do
  name="$(basename "$src" .md)"
  case " sc sc-update " in *" $name "*) continue ;; esac
  # 2.17: the plugin namespace is `supercharger`, so the generator drops the `sc-`
  # prefix (sc-status -> status). Check the stripped name.
  [ -f "$OUT_DIR/${name#sc-}.md" ] || MISSING="$MISSING $name"
done
[ -z "$MISSING" ] && pass || fail "missing generated commands:$MISSING"

begin_test "plugin.json: agents[] matches configs/agents/*.md exactly (no drift)"
# The second argument used to carry a GLOB. A plain path argument is rewritten by
# MSYS on the way to native Windows python, but one containing a wildcard is not,
# so glob.glob got an MSYS path, matched nothing, and every agent read as drift —
# note the failure showed listed=[...] populated, i.e. plugin.json itself loaded
# fine. Pass the DIRECTORY (converted) and build the pattern inside python.
AGENTS_DIR_NATIVE=$(native_path "$REPO_DIR/configs/agents")
DRIFT=$(python3 -c "
import json, glob, os, sys
p = json.load(open(sys.argv[1]))
listed = sorted(os.path.basename(a) for a in p.get('agents', []))
ondisk = sorted(os.path.basename(f) for f in glob.glob(os.path.join(sys.argv[2], '*.md')))
print('' if listed == ondisk else 'listed=%s ondisk=%s' % (listed, ondisk))
" "$REPO_DIR/.claude-plugin/plugin.json" "$AGENTS_DIR_NATIVE" 2>/dev/null)
[ -z "$DRIFT" ] && pass || fail "plugin.json agents[] out of sync: $DRIFT"

begin_test "gen-plugin-commands: --check detects drift"
# Probe a SANDBOX copy, never the live tree. This used to drop a stray .md into
# $REPO_DIR/commands/ and delete it a moment later; the suite runs in parallel, so
# any concurrent read of that directory saw a file that does not exist. Same shape
# as the test-hook-new.sh fixtures that raced test-install (2.26.2), and
# test-repo-tree-isolation.sh now fails the suite for it.
# gen-plugin-commands.sh resolves SRC_DIR/OUT_DIR from its own location, so a copy
# of the script plus the two directories is a complete sandbox.
GEN_SANDBOX=$(mktemp -d)
mkdir -p "$GEN_SANDBOX/tools" "$GEN_SANDBOX/configs" "$GEN_SANDBOX/commands"
cp "$GEN" "$GEN_SANDBOX/tools/gen-plugin-commands.sh"
cp -R "$SRC_DIR" "$GEN_SANDBOX/configs/commands"
cp "$OUT_DIR"/*.md "$GEN_SANDBOX/commands/"
printf 'drift\n' > "$GEN_SANDBOX/commands/.__drift_probe.md"
bash "$GEN_SANDBOX/tools/gen-plugin-commands.sh" --check >/dev/null 2>&1
RC=$?
rm -rf "$GEN_SANDBOX"
[ "$RC" -ne 0 ] && pass || fail "--check did not flag an extra file as drift"

begin_test "handoff carries its deep mode in BOTH the source and the generated copy"
# The lockstep check above catches the two files disagreeing. It cannot catch the
# feature being dropped from both at once, which is what a careless regeneration
# or a bad merge does. Assert the contract itself: the mode trigger, the extended
# sections, and the memory pass that makes --deep worth typing.
_hd_ok=1
for f in "$SRC_DIR/handoff.md" "$OUT_DIR/handoff.md"; do
  [ -f "$f" ] || { _hd_ok=0; continue; }
  for marker in -- '--deep' 'Memory pass' 'Rejected — do not rebuild' 'Dead ends' 'Reproduce'; do
    [ "$marker" = "--" ] && continue
    grep -qF -- "$marker" "$f" || _hd_ok=0
  done
done
[ "$_hd_ok" = 1 ] && pass || fail "handoff lost its --deep contract (source or generated copy)"

report
