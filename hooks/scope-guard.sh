#!/usr/bin/env bash
# Claude Supercharger — Scope Guard
# Event: PostToolUse (check) | SessionStart (snapshot) | UserPromptSubmit (contract) | Stop (clear) | Matcher: Write,Edit (check)
# Modes:
#   snapshot  — capture git file state at SessionStart
#   contract  — extract scope from first user prompt (UserPromptSubmit)
#   check     — compare current state against snapshot (PostToolUse Write/Edit)
#   clear     — reset state at session end (Stop)

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

MODE="${1:-check}"
SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

# v2.6.77: drain stdin once at top so all modes can use SID-suffixed paths.
# Concurrent sessions in the same project previously shared `.snapshot` and
# `.contract`, so session B's snapshot would overwrite A's baseline, producing
# false scope-alert mismatches or missed violations downstream.
_INPUT=$(cat 2>/dev/null || echo "")
# `|| true` keeps the pipeline from tripping `set -e` under `pipefail` when jq
# parse-fails on malformed JSON (head closes the pipe early → jq exits non-zero).
SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$SID" ] && SID="default"

SNAPSHOT_FILE="$SCOPE_DIR/.snapshot-${SID}"
CONTRACT_FILE="$SCOPE_DIR/.contract-${SID}"

# ── snapshot ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "snapshot" ]]; then
  PROJECT_DIR="${2:-$(pwd)}"
  cd "$PROJECT_DIR" 2>/dev/null || exit 0
  git rev-parse --git-dir &>/dev/null 2>&1 || exit 0
  FILE_COUNT=$(git ls-files 2>/dev/null | wc -l | tr -d ' ')
  {
    echo "commit:$(git rev-parse HEAD 2>/dev/null || echo 'none')"
    echo "dir:$PROJECT_DIR"
    echo "time:$(date +%s)"
    if [ "$FILE_COUNT" -gt 1000 ]; then
      # Large repo: skip mtime scan, use git-diff at check time
      echo "large-repo:true"
    else
      git ls-files 2>/dev/null | while read -r f; do
        if [ -f "$PROJECT_DIR/$f" ]; then
          # v2.6.78: GNU-first + numeric guard (Linux `stat -f` returns
          # filesystem stats, polluting the value with non-numeric text).
          mtime=$(stat -c "%Y" "$PROJECT_DIR/$f" 2>/dev/null \
               || stat -f "%m" "$PROJECT_DIR/$f" 2>/dev/null \
               || echo "")
          case "$mtime" in ''|*[!0-9]*) mtime=0 ;; esac
          echo "file:$f:$mtime"
        fi
      done
    fi
  } > "$SNAPSHOT_FILE.$$.tmp" && mv "$SNAPSHOT_FILE.$$.tmp" "$SNAPSHOT_FILE"
  exit 0
fi

# ── contract ──────────────────────────────────────────────────────────────────
if [[ "$MODE" == "contract" ]]; then
  # TTL: stale contracts (>6h) from crashed sessions are self-healed so the
  # next session can extract a fresh scope instead of inheriting stale state.
  if [ -f "$CONTRACT_FILE" ]; then
    _NOW=$(date +%s 2>/dev/null || echo 0)
    _MT=$(stat -c '%Y' "$CONTRACT_FILE" 2>/dev/null || stat -f '%m' "$CONTRACT_FILE" 2>/dev/null || echo "")
    case "$_MT" in ''|*[!0-9]*) _MT=$_NOW ;; esac
    if [ "$((_NOW - _MT))" -lt 21600 ]; then
      exit 0
    fi
    rm -f "$CONTRACT_FILE"
  fi
  # _INPUT already drained at top (v2.6.77)
  PROMPT=$(printf '%s\n' "$_INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
  if [ -z "$PROMPT" ]; then
    PROMPT=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('prompt',''))" 2>/dev/null || echo "")
  fi
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
  # _INPUT already drained at top (v2.6.77)
  TOUCHED=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  if [ -z "$TOUCHED" ]; then
    TOUCHED=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")
  fi
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

# Check if this is a large repo (no mtime data — use git diff instead)
large_repo = False
with open(snapshot_file) as f:
    for line in f:
        if line.strip() == 'large-repo:true':
            large_repo = True
            break

changed = []
if large_repo:
    try:
        r = subprocess.run(['git','diff','--name-only'],
            capture_output=True, text=True, cwd=project_dir)
        changed = [f for f in r.stdout.strip().split('\n') if f]
        r2 = subprocess.run(['git','diff','--cached','--name-only'],
            capture_output=True, text=True, cwd=project_dir)
        for f in r2.stdout.strip().split('\n'):
            if f and f not in changed:
                changed.append(f)
    except:
        pass
else:
    mtimes = {}
    with open(snapshot_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith('file:'):
                parts = line[5:].rsplit(':', 1)
                if len(parts) == 2:
                    mtimes[parts[0]] = int(parts[1])

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

  # v2.6.42: awk emits exactly one number; `grep -c | || echo 0` doubled
  # output on zero matches and aborted the arithmetic at lines below.
  COUNT=$(echo "$CHANGED" | awk 'NF{c++} END{print c+0}')
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
  # SNAPSHOT_FILE and CONTRACT_FILE are already SID-suffixed (v2.6.77).
  # Also clean the legacy unsuffixed paths from pre-v2.6.77 sessions if any
  # crashed before the upgrade.
  # v2.7.23: $SNAPSHOT_FILE (.snapshot-$SID) is NO LONGER cleared here. `clear`
  # runs on every Stop (turn end), but the snapshot is scope-guard's OWN
  # SessionStart baseline that `check` mode diffs against — wiping it per turn
  # silently disabled ALL scope-alerts after turn 1 (the hook destroyed the data
  # it needs). It's overwritten fresh at SessionStart (snapshot mode) and
  # TTL-pruned below. Legacy unsuffixed .snapshot/.contract cleanup stays.
  rm -f "$CONTRACT_FILE" \
        "$SCOPE_DIR/.snapshot" "$SCOPE_DIR/.contract" \
        "$SCOPE_DIR/.session-tokens"
  # SID already set at top (v2.6.77); keep the original re-extraction below
  # for forward-compat with the legacy clear-only payload that lacks session_id.
  if [ -n "$SID" ]; then
    rm -f "$SCOPE_DIR/.agent-classified-$SID" \
          "$SCOPE_DIR/.agent-dispatched-$SID" \
          "$SCOPE_DIR/.last-category-$SID" \
          "$SCOPE_DIR/.last-tier-$SID" \
          "$SCOPE_DIR/.router-hash-$SID" \
          "$SCOPE_DIR/.router-cache-$SID" \
          "$SCOPE_DIR/.repetition-flag-$SID" 2>/dev/null || true
  # v2.7.22/.23: CUMULATIVE session state is NOT cleared per-turn — only
  # TTL-pruned (below) or reset at SessionStart. Removed from this per-turn rm:
  #   .subagent-costs-$SID.jsonl       (v2.7.22) — /sc-status + statusline rollup
  #   .snapshot-$SID                   (v2.7.23) — scope-guard's check baseline
  #   .tool-history-$SID               (v2.7.23) — confidence-gate session history
  #   .subagent-safety-injected-$SID   (v2.7.23) — once/session preamble dedup flag
  # Wiping them every Stop defeated their purpose (lost data / repeated work).
  fi
  # Also TTL-prune any orphaned session files older than 7 days
  find "$SCOPE_DIR" -maxdepth 1 -type f \( \
       -name '.agent-classified-*' \
    -o -name '.agent-dispatched-*' \
    -o -name '.last-category-*' \
    -o -name '.last-tier-*' \
    -o -name '.router-hash-*' \
    -o -name '.repetition-flag-*' \
    -o -name '.subagent-safety-injected-*' \
    -o -name '.subagent-costs-*.jsonl' \
    -o -name '.snapshot-*' \
    -o -name '.contract-*' \
    -o -name '.tool-history-*' \
    -o -name '.router-cache-*' \) -mtime +7 -delete 2>/dev/null || true
  exit 0
fi

exit 0