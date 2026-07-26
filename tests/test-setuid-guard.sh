#!/usr/bin/env bash
# v2.23.22 — safety.sh DESTRUCT_PATTERNS setuid/setgid fold-in (only chmod 777 before).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
export SUPERCHARGER_HOME="$REPO_DIR"
HOOK="$REPO_DIR/hooks/safety.sh"

echo "=== setuid/setgid guard Tests ==="

TMP=$(mktemp -d)
mkin() { VAL="$2" python3 - "$1" <<'PY'
import json, os, sys
open(sys.argv[1], "w").write(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["VAL"]}, "session_id": "su"}))
PY
}
dec() { python3 -c "import json,sys;s=sys.stdin.read().strip();print(json.loads(s)['hookSpecificOutput']['permissionDecision'].upper() if s else 'ALLOW')"; }
n=0
check() { n=$((n+1)); mkin "$TMP/c$n" "$2"; begin_test "$1"
  local g; g=$(printf '%s' "$(SUPERCHARGER_STATE="$(mktemp -d)" bash "$HOOK" < "$TMP/c$n" 2>/dev/null)" | dec)
  [ "$g" = "$3" ] && pass || fail "expected $3 got $g — $2"; }

# --- should DENY: special (setuid/setgid) bit set ---
check "chmod 4755 (setuid)"       "chmod 4755 /usr/bin/x"          DENY
check "chmod 6755 (setuid+setgid)" "chmod 6755 /x"                 DENY
check "chmod 2755 (setgid)"       "chmod 2755 /srv/app"            DENY
check "chmod u+s (symbolic)"      "chmod u+s /tmp/b"              DENY
check "chmod g+s (symbolic)"      "chmod g+s /tmp/dir"           DENY
check "install-less chmod +s"     "chmod +s /tmp/x"              DENY

# --- should still fire on the legacy 777 (regression) ---
check "chmod 777 (still caught)"  "chmod 777 /tmp/x"             DENY

# --- should ALLOW: ordinary modes (no special leading bit) ---
check "chmod 755"                 "chmod 755 script.sh"          ALLOW
check "chmod 644"                 "chmod 644 file"               ALLOW
check "chmod 0644 (leading 0)"    "chmod 0644 file"              ALLOW
check "chmod 1755 (sticky only)"  "chmod 1755 /tmp/sticky"       ALLOW
check "chmod -R 755 dir"          "chmod -R 755 dir"             ALLOW
check "chmod +x script"           "chmod +x run.sh"             ALLOW

rm -rf "$TMP"
report
