#!/usr/bin/env bash
# Demo helper — run a command string through Supercharger's shell hooks and
# report whether it was BLOCKED (exit 2) or allowed, without executing it.
# Usage: ./try.sh "rm -rf /"
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cmd="${1:?usage: try.sh \"<command>\"}"

# Build the PreToolUse:Bash payload Claude Code would send.
payload=$(REPO="$REPO_DIR" CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash",
                  "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["REPO"]}))')

# safety.sh covers most categories; git-safety.sh covers force-push / reset --hard.
rc=0
for hook in safety.sh git-safety.sh; do
  out=$(printf '%s' "$payload" | bash "$REPO_DIR/hooks/$hook" 2>&1) || rc=$?
  [ "$rc" -eq 2 ] && break
done

if [ "$rc" -eq 2 ]; then
  printf '\033[1;31m  ✗ BLOCKED\033[0m  %s\n' "$cmd"
  printf '%s\n' "$out" | grep -F 'Reason :' | sed 's/^[[:space:]]*/      /'
else
  printf '\033[1;32m  ✓ allowed\033[0m  %s\n' "$cmd"
fi
