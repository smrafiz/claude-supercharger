#!/usr/bin/env bash
# The .claude DIRECTORY as a Bash target (2026-11-09, applygate delta).
# safety.sh's selfmod arms matched config FILE names only, so moving the whole
# directory away (every guard off) or planting into it was allowed.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== .claude directory guard ==="

verdict() { # command -> deny | ask | allow (safety.sh)
  local st out rc
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  out=$(CMD="$1" python3 -c 'import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}, "session_id": "cdir", "cwd": "/tmp"}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/safety.sh" 2>&1); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"deny"'*) echo deny ;; *'"ask"'*) echo ask ;; *) echo allow ;; esac
}

while IFS='|' read -r want cmd; do
  [ -z "$cmd" ] && continue
  begin_test "$want: $cmd"
  got=$(verdict "$cmd")
  [ "$got" = "$want" ] && pass || fail "got $got"
done <<'CASES'
deny|mv ~/.claude ~/.claude.old
deny|mv "$HOME/.claude" /tmp/c
deny|mv .claude .claude.bak
deny|mv -t /tmp .claude
deny|mv staged .claude
deny|cp settings.json .claude/
deny|cp ../o/CLAUDE.md ../../.claude
deny|cp -t .claude settings.local.json
deny|cp -r skills .claude/
deny|cp -a ../tpl/hooks ~/.claude/
deny|cp -r ../other/.claude .
deny|cp -r ../other/.claude ~/
deny|rsync -a ../other/.claude/ .claude/
deny|ln -sf ../other/.claude .claude
deny|tar -xf a.tar -C ../../.claude
deny|tar -xf a.tar --directory=.claude
deny|unzip a.zip -d ../../.claude
deny|find .claude -delete
deny|git checkout other -- .claude
deny|cd x && mv .claude .old
allow|cp -r ~/.claude ~/claude-backup
allow|rsync -a .claude/ /backup/claude/
allow|mv .claude/handoff-a.md .claude/handoff-b.md
allow|cp .claude/agents/x.md /tmp/
allow|cp foo.md .claude/agents/
allow|tar -czf backup.tgz .claude
allow|find .claude -name x.md
allow|unzip a.zip -d out
allow|git add .claude/handoff.md
allow|git checkout main
allow|mkdir -p .claude/agents
allow|mv notes.claude.md done.md
allow|cp .claude/handoff.md .claude/handoff-a.md $W/.claude/
allow|cp notes.md .claude/
allow|cp -t .claude a.md b.md
CASES

begin_test "a .claude directory inside a mktemp dir stays allowed (test fixtures)"
got=$(verdict 'T=$(mktemp -d); mv "$T/.claude" "$T/old"')
[ "$got" = allow ] && pass || fail "got $got"

report
