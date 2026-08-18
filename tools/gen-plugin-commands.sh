#!/usr/bin/env bash
# Claude Supercharger — Plugin commands/ generator
#
# Emits commands/*.md for the PLUGIN runtime from the single source of truth
# (configs/commands/*.md — the same files the installer copies to ~/.claude/commands/).
# The installer keeps using configs/ verbatim, so the two channels never drift and
# the installer path stays byte-identical.
#
# Transform (docs/PLUGIN-DISTRIBUTION-PLAN.md §4, Phase 4):
#   - code paths  ~/.claude/supercharger/tools|lib  -> ${CLAUDE_PLUGIN_ROOT}/...
#   - state paths ~/.claude/supercharger/scope|audit -> ${CLAUDE_PLUGIN_DATA}/...
#   (both ~ and $HOME forms). The plugin runtime substitutes ${CLAUDE_PLUGIN_ROOT}/
#   ${CLAUDE_PLUGIN_DATA} anywhere in command markdown content — a documented behavior
#   (plugins-reference: placeholders resolve "anywhere the placeholder appears" in
#   command content). Project-scoped (~/.claude/projects/...) refs are left untouched.
#
# Meta-commands with a native /plugin equivalent are NOT emitted (§5 casualties):
#   - /sc        -> native /plugin enable|disable claude-supercharger
#   - /sc-update -> native /plugin update claude-supercharger
#
# Usage: bash tools/gen-plugin-commands.sh          # writes commands/*.md
#        bash tools/gen-plugin-commands.sh --check   # verify committed dir is current (CI)
set -euo pipefail

# Windows python defaults stdout to the ANSI codepage (cp1252) and raises
# UnicodeEncodeError on the box-drawing and arrow characters this tool prints,
# losing ALL of its output. Hooks get this from hooks/lib-paths.sh; tools do not
# reach that file, so they set it themselves. `:=` honours an explicit setting.
: "${PYTHONIOENCODING:=utf-8}"
: "${PYTHONUTF8:=1}"
export PYTHONIOENCODING PYTHONUTF8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_DIR/configs/commands"
OUT_DIR="$REPO_DIR/commands"

# Commands whose function is served natively by /plugin — skip in the plugin edition.
SKIP="sc sc-update"

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

# Transform one source command file to plugin form on stdout.
transform() {
  SRC_FILE="$1" python3 <<'PYEOF'
import os, re, sys

with open(os.environ['SRC_FILE']) as f:
    text = f.read()

# State roots first (scope/, audit/) -> CLAUDE_PLUGIN_DATA; then code roots
# (tools/, lib/) -> CLAUDE_PLUGIN_ROOT. Both ~ and $HOME forms. Ordering is safe
# because every rule matches a distinct subdir; no bare-root rule to over-catch.
subs = [
    (r'(?:~|\$HOME)/\.claude/supercharger/scope', '${CLAUDE_PLUGIN_DATA}/scope'),
    (r'(?:~|\$HOME)/\.claude/supercharger/audit', '${CLAUDE_PLUGIN_DATA}/audit'),
    (r'(?:~|\$HOME)/\.claude/supercharger/tools', '${CLAUDE_PLUGIN_ROOT}/tools'),
    (r'(?:~|\$HOME)/\.claude/supercharger/lib',   '${CLAUDE_PLUGIN_ROOT}/lib'),
]
for pat, repl in subs:
    text = re.sub(pat, repl, text)

sys.stdout.write(text)
PYEOF
}

# Build the desired output set in a temp dir, then either diff (--check) or sync.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

count=0
for src in "$SRC_DIR"/*.md; do
  name="$(basename "$src" .md)"
  case " $SKIP " in *" $name "*) continue ;; esac
  # 2.17: the plugin namespace is `supercharger` (plugin.json name), so the `sc-`
  # prefix is redundant under it — drop it. /sc-status -> /supercharger:status,
  # /sc-autopilot -> /supercharger:autopilot, etc. Non-sc names are unchanged.
  out="${name#sc-}"
  SRC_FILE="$src" transform "$src" > "$TMP/$out.md"
  count=$((count + 1))
done

if $CHECK; then
  if [[ ! -d "$OUT_DIR" ]]; then
    echo "commands/ is missing — run: bash tools/gen-plugin-commands.sh" >&2
    exit 1
  fi
  # Compare set + content. Any diff (missing, extra, or changed file) => stale.
  _GPC_DIFF=$(diff -r "$TMP" "$OUT_DIR" 2>&1 | head -40 || true)
  [ -n "$_GPC_DIFF" ] && { echo "--- diff: generated vs committed, first 40 lines ---" >&2; printf '%s\n' "$_GPC_DIFF" >&2; }
  if ! diff -rq "$TMP" "$OUT_DIR" >/dev/null 2>&1; then
    echo "commands/ is stale — regenerate: bash tools/gen-plugin-commands.sh" >&2
    exit 1
  fi
  echo "commands/ is up to date ($count commands)."
  exit 0
fi

mkdir -p "$OUT_DIR"
# Remove stale generated files, then copy the fresh set (keeps the dir in lockstep).
rm -f "$OUT_DIR"/*.md
cp "$TMP"/*.md "$OUT_DIR"/
echo "Wrote $OUT_DIR ($count commands; skipped: $SKIP)"
