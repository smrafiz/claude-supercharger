#!/usr/bin/env bash
# Claude Supercharger — Scope Guard
# Modes:
#   snapshot  — capture git file state at SessionStart
#   contract  — extract scope from first user prompt (UserPromptSubmit)
#   check     — compare current state against snapshot (PostToolUse Write/Edit)
#   clear     — reset state at session end (Stop)

set -euo pipefail

MODE="${1:-check}"
SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

SNAPSHOT_FILE="$SCOPE_DIR/.snapshot"
CONTRACT_FILE="$SCOPE_DIR/.contract"

# ── snapshot ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "snapshot" ]]; then
  PROJECT_DIR="${2:-$(pwd)}"
  cd "$PROJECT_DIR" 2>/dev/null || exit 0
  git rev-parse --git-dir &>/dev/null 2>&1 || exit 0
  {
    echo "commit:$(git rev-parse HEAD 2>/dev/null || echo 'none')"
    echo "dir:$PROJECT_DIR"
    echo "time:$(date +%s)"
    git ls-files 2>/dev/null | while read -r f; do
      if [ -f "$PROJECT_DIR/$f" ]; then
        mtime=$(stat -f "%m" "$PROJECT_DIR/$f" 2>/dev/null \
             || stat -c "%Y" "$PROJECT_DIR/$f" 2>/dev/null \
             || echo "0")
        echo "file:$f:$mtime"
      fi
    done
  } > "$SNAPSHOT_FILE"
  exit 0
fi

# ── contract ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "contract" ]]; then
  [ -f "$CONTRACT_FILE" ] && exit 0
  INPUT=$(cat)
  PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('prompt',''))
except:
    print('')
" 2>/dev/null || echo "")
  [ -z "$PROMPT" ] && exit 0

  SCOPE_PROMPT="$PROMPT" python3 << 'PYEOF' > "$CONTRACT_FILE" 2>/dev/null || echo "scope:general" > "$CONTRACT_FILE"
import re, os

prompt = os.environ.get('SCOPE_PROMPT', '')
signals = []

paths = re.findall(r'[\w./\-]+\.(?:tsx?|jsx?|py|rs|go|rb|java|php|sh|md|json|yaml|yml|css|scss|html|vue|svelte)', prompt)
signals.extend(paths[:5])

lines = re.findall(r'line\s+(\d+)', prompt, re.IGNORECASE)
if lines:
    signals.append('line ' + ', '.join(lines))

if re.search(r'\b(only|just|this file|single file|one file)\b', prompt, re.IGNORECASE):
    signals.append('single-file-scope')

if signals:
    print('scope:' + '|'.join(dict.fromkeys(signals)))
else:
    print('scope:general')
PYEOF
  exit 0
fi

# ── check ─────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "check" ]]; then
  INPUT=$(cat)
  TOUCHED=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('input', {}).get('file_path', ''))
except:
    print('')
" 2>/dev/null || echo "")
  [ -z "$TOUCHED" ] && exit 0
  [ -f "$SNAPSHOT_FILE" ] || exit 0

  PROJECT_DIR=$(grep "^dir:" "$SNAPSHOT_FILE" 2>/dev/null | cut -d: -f2- || echo "")
  [ -z "$PROJECT_DIR" ] && exit 0
  cd "$PROJECT_DIR" 2>/dev/null || exit 0
  git rev-parse --git-dir &>/dev/null 2>&1 || exit 0

  CHANGED=$(SNAPSHOT_FILE="$SNAPSHOT_FILE" PROJECT_DIR="$PROJECT_DIR" python3 << 'PYEOF'
import os, subprocess

snapshot_file = os.environ['SNAPSHOT_FILE']
project_dir = os.environ['PROJECT_DIR']

mtimes = {}
with open(snapshot_file) as f:
    for line in f:
        line = line.strip()
        if line.startswith('file:'):
            parts = line[5:].rsplit(':', 1)
            if len(parts) == 2:
                mtimes[parts[0]] = int(parts[1])

changed = []
for fpath, old in mtimes.items():
    full = os.path.join(project_dir, fpath)
    if os.path.isfile(full):
        try:
            if int(os.stat(full).st_mtime) > old:
                changed.append(fpath)
        except:
            pass

try:
    r = subprocess.run(['git','ls-files','--others','--exclude-standard'],
        capture_output=True, text=True, cwd=project_dir)
    for f in r.stdout.strip().split('\n'):
        if f and f not in changed:
            changed.append(f)
except:
    pass

print('\n'.join(changed))
PYEOF
)

  COUNT=$(echo "$CHANGED" | grep -c '\S' 2>/dev/null || echo "0")
  CONTRACT=$(cat "$CONTRACT_FILE" 2>/dev/null || echo "scope:general")

  if echo "$CONTRACT" | grep -q "single-file-scope" && [ "$COUNT" -gt 1 ]; then
    echo "[Supercharger] Scope warning: task looked single-file but $COUNT files were modified:" >&2
    echo "$CHANGED" | head -8 | while read -r f; do [ -n "$f" ] && echo "  modified: $f" >&2; done
  fi

  if [ "$COUNT" -gt 5 ]; then
    echo "[Supercharger] Scope alert: $COUNT files modified this session." >&2
    echo "$CHANGED" | head -10 | while read -r f; do [ -n "$f" ] && echo "  - $f" >&2; done
    [ "$COUNT" -gt 10 ] && echo "  (and more — run: git diff --name-only)" >&2
  fi

  exit 0
fi

# ── clear ─────────────────────────────────────────────────────────────────────
if [[ "$MODE" == "clear" ]]; then
  rm -f "$SNAPSHOT_FILE" "$CONTRACT_FILE"
  exit 0
fi

exit 0