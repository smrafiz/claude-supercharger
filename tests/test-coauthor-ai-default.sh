#!/usr/bin/env bash
# 4.4: a Co-Authored-By trailer naming an AI tool is denied by default (user rule,
# 2026-10-28); a human co-author is not. Opt out with SUPERCHARGER_COAUTHOR_GUARD=0.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== AI co-author trailers ==="

T=$(mktemp -d); ST=$(mktemp -d)
TR='Co-Authored-By'
printf 'fix: x\n\n%s: Claude <noreply@anthropic.com>\n' "$TR" > "$T/msg-ai.txt"
printf 'fix: x\n\n%s: Jane Doe <jane@example.com>\n' "$TR" > "$T/msg-human.txt"

run() {  # $1 = command, $2 = extra env -> DENY | ALLOW
  local p out rc
  p=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$1" "$T")
  out=$(printf '%s' "$p" | env $2 SUPERCHARGER_STATE="$ST" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/commit-guard.sh" 2>/dev/null); rc=$?
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) echo DENY ;; *) echo ALLOW ;; esac
}
check() { begin_test "co-author: $1 -> $3"; local g; g=$(run "$2" "${4:-X=1}"); [ "$g" = "$3" ] && pass || fail "got $g"; }

check "Claude trailer in -m" "git commit -m \"fix: x\" -m \"$TR: Claude <noreply@anthropic.com>\"" DENY
check "Copilot trailer" "git commit -m \"fix: x

$TR: GitHub Copilot <copilot@github.com>\"" DENY
check "bot trailer" "git commit -m \"x\" -m \"$TR: cursor[bot] <bot@cursor.com>\"" DENY
check "heredoc message" "git commit -m \"\$(cat <<'EOF'
fix: x

$TR: Claude Opus <noreply@anthropic.com>
EOF
)\"" DENY
check "-F message file" "git commit -F msg-ai.txt" DENY
check "human co-author" "git commit -m \"x\" -m \"$TR: Jane Doe <jane@example.com>\"" ALLOW
check "human co-author in -F file" "git commit -F msg-human.txt" ALLOW
check "plain commit" "git commit -m \"fix: plain\"" ALLOW
check "opt-out" "git commit -m \"x\" -m \"$TR: Claude <noreply@anthropic.com>\"" ALLOW SUPERCHARGER_COAUTHOR_GUARD=0
check "strict mode denies a human too" "git commit -m \"x\" -m \"$TR: Jane <j@x.com>\"" DENY SUPERCHARGER_COAUTHOR_GUARD=1

rm -rf "$T" "$ST"
report
