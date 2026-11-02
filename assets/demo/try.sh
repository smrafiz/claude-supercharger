#!/usr/bin/env bash
# Demo helper — run a command string through Supercharger's shell hooks and
# report whether it is BLOCKED (exit 2), would ASK first, or is allowed, without
# executing it. Usage: ./try.sh "rm -rf /"   (TRY_CWD=<dir> sets the project dir)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cmd="${1:?usage: try.sh \"<command>\"}"
cwd="${TRY_CWD:-$REPO_DIR}"

# Build the PreToolUse:Bash payload Claude Code would send.
payload=$(CWD="$cwd" CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "session_id": "demo",
                  "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["CWD"]}))')

# safety.sh covers most categories, git-safety.sh force-push / reset --hard, and
# blast-radius-guard.sh asks before deleting files git cannot bring back.
state=$(mktemp -d); trap 'rm -rf "$state"' EXIT
verdict=allowed; reason=""
for hook in safety.sh git-safety.sh blast-radius-guard.sh; do
  rc=0
  out=$(printf '%s' "$payload" | SUPERCHARGER_STATE="$state" bash "$REPO_DIR/hooks/$hook" 2>&1) || rc=$?
  if [ "$rc" -eq 2 ]; then
    verdict=blocked; reason=$(printf '%s\n' "$out" | grep -F 'Reason :' | sed 's/^[[:space:]]*Reason :[[:space:]]*//' | head -1)
    break
  fi
  case "$out" in
    *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*)
      verdict=asks
      reason=$(printf '%s' "$out" | python3 -c 'import json,sys,re
for line in sys.stdin.read().splitlines():
    line = line.strip()
    if line.startswith("{"):
        r = json.loads(line)["hookSpecificOutput"]["permissionDecisionReason"]
        m = re.search(r"Effect:\s*(.*?)(?:\s{2,}Way through:|$)", r)
        print((m.group(1) if m else r).strip()); break' 2>/dev/null) ;;
  esac
done

case "$verdict" in
  blocked) printf '\033[1;31m  ✗ BLOCKED\033[0m  %s\n      %s\n' "$cmd" "$reason" ;;
  asks)    printf '\033[1;33m  ? ASKS   \033[0m  %s\n      %s\n' "$cmd" "$reason" ;;
  *)       printf '\033[1;32m  ✓ allowed\033[0m  %s\n' "$cmd" ;;
esac
