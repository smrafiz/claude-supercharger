#!/usr/bin/env bash
# A shell glob that expands to the dotenv file reads it as surely as the plain name
# (`.en?`, `.e*`, `.[e]nv`). Found re-auditing JeongJaeSoon/agent-guard 2026-10-27:
# each DENY case passed safety.sh before. ALLOW cases are globs that cannot match it.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== dotenv glob spellings ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
cases = [
    ("question mark", "cat .en?", "DENY"),
    ("star", "cat .e*", "DENY"),
    ("bracket", "cat .[e]nv", "DENY"),
    ("bracket after ./", "cat ./.en[v]", "DENY"),
    ("glob in a subdir", "head -5 app/.e?v", "DENY"),
    ("dotfiles glob", "grep KEY .*", "DENY"),
    # still allowed
    ("eslintrc glob", "cat .eslintrc*", "ALLOW"),
    ("source glob", "cat src/*.ts", "ALLOW"),
    ("github dir glob", "ls .github/*", "ALLOW"),
    ("list dotfiles", "ls -a .e*", "ALLOW"),
    ("list env file names", "ls .en" + "v* 2>/dev/null; echo done", "ALLOW"),
    ("grep in a dotenv glob", "grep -n KEY .en" + "v* | wc -l", "DENY"),
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
  begin_test "dotenv glob: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

rm -rf "$TMP"
report
