#!/usr/bin/env bash
# 4.4.3: a pattern block tells the user and the agent WHY in plain words, and keeps the
# raw rule after it. The block log keeps `dangerous pattern: <regex>` unchanged, since
# learn-from-blocks parses that prefix.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== safety: plain-language block reasons ==="
while IFS='|' read -r want cmd; do
  [ -n "$cmd" ] || continue
  begin_test "says '$want': $cmd"
  H=$(mktemp -d)
  why=$(jq -nc --arg c "$cmd" '{session_id:"pr",tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}' \
        | HOME="$H" bash "$REPO_DIR/hooks/safety.sh" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  log=$(cat "$H/.claude/supercharger/scope/.blocked-commands" 2>/dev/null)
  rm -rf "$H"
  case "$why" in
    "Supercharger: blocked because "*"$want"*". (rule: dangerous pattern: "*")")
      case "$log" in *"] dangerous pattern: "*) pass ;; *) fail "ledger lost the raw rule: $log" ;; esac ;;
    *) fail "reason: $why" ;;
  esac
done <<'CASES'
straight into a shell|echo aGk= | base64 -d | sh
database data|psql -c "DROP TABLE users"
stored passwords|security find-generic-password -s github -w
hard to undo|mkfs.ext4 /dev/sdb1
hard to undo|chmod -R 777 /srv
CASES
report
