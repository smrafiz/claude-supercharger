#!/usr/bin/env bash
# 2026-10-28 — a kill chosen by name or pattern ASKS (randommonicle/claude-skills
# kill-guard). Several sessions share one machine; a pattern reaches their processes.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== kill by name or pattern ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
PK, KA = 'pk' + 'ill', 'kill' + 'all'
cases = [
    ("pkill -f pattern", PK + " -f pytest", "ASK"),
    ("pkill by name", PK + " vite", "ASK"),
    ("killall by name", KA + " Python", "ASK"),
    ("pgrep piped to xargs kill", "pgrep -f vite | xargs kill", "ASK"),
    ("kill of a pgrep substitution", "kill $(pgrep -f next)", "ASK"),
    ("kill of a pidof substitution", "kill -9 `pidof node`", "ASK"),
    # still denied: killing node kills Claude Code itself
    ("pkill node", PK + " node", "DENY"),
    # still allowed
    ("kill a PID", "kill 12345", "ALLOW"),
    ("kill -9 a PID", "kill -9 4242", "ALLOW"),
    ("pgrep alone", "pgrep -fl vite", "ALLOW"),
    ("lsof then nothing", "lsof -ti :3000", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  st=$(mktemp -d)
  out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/safety.sh" < "$TMP/p$i.json" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) got=DENY ;; *'"permissionDecision":"ask"'*) got=ASK ;; *) got=ALLOW ;; esac
  begin_test "kill: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

rm -rf "$TMP"
report
