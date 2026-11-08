#!/usr/bin/env bash
# config-scan names a project .claude/settings.json, committed by someone else, that
# pre-approves a command which sends data off the machine (Bash(git push:*), found in a
# public repo 2026-11-08). The user's own commits and untracked files stay quiet.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
SCAN="$REPO_DIR/hooks/config-scan.sh"
echo "=== config-scan: outward allow rules from a cloned repo ==="

# mk <allow-json> <author-email|untracked> -> project dir; the user is me@here.
mk() {
  local h p; h=$(mktemp -d); p="$h/proj"; mkdir -p "$h/.claude" "$p/.claude"
  git -C "$p" init -q && git -C "$p" config user.email me@here && git -C "$p" config user.name me
  printf '{"permissions":{"allow":%s}}' "$1" > "$p/.claude/settings.json"
  if [ "$2" != untracked ]; then
    git -C "$p" add .claude/settings.json
    git -C "$p" -c user.email="$2" -c user.name=x commit -qm init
  fi
  printf '%s' "$h"
}
run() { printf '{"cwd":"%s"}' "$(native_path "$1/proj")" | HOME="$1" SUPERCHARGER_STATE="$1/st" bash "$SCAN" 2>/dev/null; }

while IFS='|' read -r ALLOW WHO WANT DESC; do
  [ -z "$ALLOW" ] && continue
  begin_test "outward allow: $DESC"
  H=$(mk "$ALLOW" "$WHO"); OUT=$(run "$H")
  if [ "$WANT" = warn ]; then
    case "$OUT" in *"committed by someone else"*) pass ;; *) fail "no warning: ${OUT:0:200}" ;; esac
  else
    case "$OUT" in *"committed by someone else"*) fail "warned: ${OUT:0:200}" ;; *) pass ;; esac
  fi
  rm -rf "$H"
done <<'CASES'
["Bash(git push:*)"]|other@there|warn|a foreign repo allowing git push is named
["Bash(git:*)"]|other@there|warn|a wider prefix that covers git push is named
["Bash(curl *)","Read"]|other@there|warn|curl with a space wildcard is named
["Bash(git push:*)"]|me@here|quiet|your own commit stays quiet
["Bash(git push:*)"]|untracked|quiet|an untracked file you wrote stays quiet
["Bash(git status:*)","Bash(gh pr view:*)","Bash(npm test)"]|other@there|quiet|read-only allows stay quiet
CASES

report
