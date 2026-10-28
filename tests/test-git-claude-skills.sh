#!/usr/bin/env bash
# 2026-10-28 — git gaps from replaying randommonicle/claude-skills' push-gate tests
# and lessons 10/21/40 through git-safety.sh. Each DENY/ASK case was ALLOW before.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== git gaps (claude-skills) ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
F = '--' + 'force'
cases = [
    ("send-pack force to main", "git send-pack " + F + " origin HEAD:refs/heads/main", "DENY"),
    ("push force to the full ref of main", "git push " + F + " origin HEAD:refs/heads/main", "DENY"),
    ("send-pack force to a feature branch", "git send-pack " + F + " origin HEAD:refs/heads/feat", "ASK"),
    ("saved alias that force-pushes", "git config alias.ship 'push " + F + "'", "ASK"),
    ("saved global alias that force-pushes", "git config --global alias.ship 'push " + F + "'", "ASK"),
    ("saved shell alias", "git config alias.x '!sh -c date'", "ASK"),
    ("checkout HEAD -- file", "git checkout HEAD -- a.txt", "DENY"),
    ("restore from HEAD", "git restore --source=HEAD a.txt", "DENY"),
    ("checkout -B main backwards", "git checkout -B main HEAD~1", "DENY"),
    ("update-ref main backwards", "git update-ref refs/heads/main HEAD~1", "DENY"),
    ("gh pr merge", "gh pr merge 41 --squash", "ASK"),
    ("gh api merge", "gh api -X PUT /repos/o/r/pulls/333/merge", "ASK"),
    ("worktree in /tmp", "git worktree add /tmp/wt-x -b wt-x", "ASK"),
    # still allowed
    ("read-only saved alias", "git config alias.lg 'log --oneline --graph'", "ALLOW"),
    ("checkout a file from another ref", "git checkout origin/main -- a.txt", "ALLOW"),
    ("restore --staged from HEAD", "git restore --staged --source=HEAD a.txt", "ALLOW"),
    ("checkout -B a feature branch", "git checkout -B feat origin/feat", "ALLOW"),
    ("plain push", "git push origin feat", "ALLOW"),
    ("worktree in the project", "git worktree add .claude/worktrees/x -b x", "ALLOW"),
    ("gh pr view", "gh pr view 41", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

run_case() {  # $1 = payload file, $2 = extra env -> DENY | ASK | ALLOW
  local st out rc; st=$(mktemp -d)
  out=$(env $2 SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/git-safety.sh" < "$1" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) echo DENY ;; *'"permissionDecision":"ask"'*) echo ASK ;; *) echo ALLOW ;; esac
}

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  got=$(run_case "$TMP/p$i.json" "X=1")
  begin_test "git: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

begin_test "opt-in: SUPERCHARGER_ASK_EVERY_PUSH=1 asks on a plain push"
printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"git push origin feat"}}' > "$TMP/push.json"
[ "$(run_case "$TMP/push.json" SUPERCHARGER_ASK_EVERY_PUSH=1)" = ASK ] && pass || fail "did not ask"

rm -rf "$TMP"
report
