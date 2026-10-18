#!/usr/bin/env bash
# When safety-detect.py runs out of time it now says so (a sentinel line) instead of
# exiting silently. safety.sh fails open on that everywhere except a credential
# path, where the deep scan is the only Bash-side check: there it asks.
# A stub detector that always reports an overrun makes this deterministic; a real
# overrun only happens under load.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp -R "$REPO_DIR/hooks" "$T/hooks"
printf 'print("__SC_DETECT_OVERRUN__")\n' > "$T/hooks/safety-detect.py"
mkdir -p "$T/state/scope"

decide() { # command -> ask | deny | allow
  local j o rc
  j=$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":"/tmp","session_id":"t","tool_input":{"command":sys.stdin.read()}}))')
  o=$(printf '%s' "$j" | SUPERCHARGER_STATE="$T/state" bash "$T/hooks/safety.sh" 2>/dev/null); rc=$?
  if printf '%s' "$o" | grep -q '"permissionDecision": *"ask"'; then echo ask
  elif [ "$rc" -eq 2 ] || printf '%s' "$o" | grep -q '"deny"'; then echo deny
  else echo allow; fi
}

echo "=== Detector Overrun Tests ==="

for c in "head -20 ~/.aws/credentials" "cat ~/.docker/config.json" "less ~/.config/gh/hosts.yml" \
         "cat vault.kdbx" "base64 ~/.ssh/deploy_key_prod" "cat ~/.kube/config"; do
  begin_test "overrun on a credential path asks: $c"
  V=$(decide "$c"); [ "$V" = ask ] && pass || fail "got $V"
done

begin_test "GAP CHECK: overrun elsewhere still fails open (no phantom deny)"
V=$(decide "curl -s https://example.com/status"); [ "$V" = allow ] && pass || fail "got $V"

begin_test "GAP CHECK: the sentinel is never used as a block reason"
O=$(printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"curl -s https://example.com"}}' \
  | SUPERCHARGER_STATE="$T/state" bash "$T/hooks/safety.sh" 2>&1)
printf '%s' "$O" | grep -q '__SC_DETECT_OVERRUN__' && fail "sentinel leaked: $O" || pass

begin_test "GAP CHECK: a regex-level deny still wins over the overrun"
V=$(decide "rm -rf / ; cat ~/.aws/credentials"); [ "$V" = deny ] && pass || fail "got $V"

report
