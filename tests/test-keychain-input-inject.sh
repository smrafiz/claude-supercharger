#!/usr/bin/env bash
# Keychain reads + synthetic input injection (v2.24.13)
#
# Both shapes were listed as dangerous in tests/fuzz-safety.sh but NO pattern
# implemented them, so they sat in the fuzzer's false-negative total: 100 and 125 of
# 300 entries respectively. The number had never been triaged, so nobody noticed that
# 225 of the 300 "bypasses" were two real, unguarded attacks.
#
#   security find-generic-password -s github -w   → prints one credential to stdout,
#     needs no GUI confirmation. dump-keychain was guarded; the targeted read was not.
#   osascript … keystroke                          → types into the focused window, so
#     it can drive a GUI app, a password prompt, or a terminal the agent must not use.
#     An authorization bypass that never passes through a guarded tool.
#
# The remaining 75 FN entries are mutation artifacts: fuzz-safety's hyphen mutation
# rewrites command NAMES (`ssh-keygen` → `ssh  -keygen`), producing unrunnable
# mutants. Those are documented in the fuzzer, not fixed here.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/safety.sh"

echo "=== Keychain Read + Input Injection Tests ==="

# verdict for a Bash command; optional disabled-categories list.
verdict() {
  local c="$1" cats="${2:-}" st payload rc
  st=$(mktemp -d); mkdir -p "$st/scope"
  [ -n "$cats" ] && printf '%s\n' "$cats" > "$st/scope/.disabled-security-categories"
  payload=$(CMD="$c" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')
  printf '%s' "$payload" | env SUPERCHARGER_STATE="$st" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && echo DENY || echo ALLOW
}

expect() { # want label cmd
  begin_test "$2"
  local got; got=$(verdict "$3")
  [ "$got" = "$1" ] && pass || fail "expected $1, got $got — $3"
}

# --- Keychain credential reads (category: credentials) ---
expect DENY "keychain: find-generic-password (targeted read, -w prints the secret)" \
  "security find-generic-password -s github -w"
expect DENY "keychain: find-internet-password" \
  "security find-internet-password -s github.com -w"
expect DENY "keychain: export (bulk key material)" \
  "security export -k login.keychain"
expect DENY "keychain: find-certificate -p (PEM, may include private keys)" \
  "security find-certificate -p -c mycert"
expect DENY "keychain: dump-keychain still blocked (pre-existing)" \
  "security dump-keychain"

# --- Synthetic input injection (category: clipboard) ---
expect DENY "input-inject: osascript keystroke" \
  "osascript -e 'tell app \"System Events\" to keystroke \"x\"'"
expect DENY "input-inject: osascript key code" \
  "osascript -e 'tell application \"System Events\" to key code 36'"
expect DENY "input-inject: cliclick" \
  "cliclick c:100,200"
expect DENY "input-inject: System Events click" \
  "osascript -e 'tell app \"System Events\" to click at {10, 20}'"

# --- Must NOT over-block: ordinary osascript / security usage ---
expect ALLOW "allows osascript display notification" \
  "osascript -e 'display notification \"build done\"'"
expect ALLOW "allows osascript app query (no input synthesis)" \
  "osascript -e 'tell app \"Finder\" to get name of front window'"
expect ALLOW "allows security --help" \
  "security --help"
expect ALLOW "allows the word keystroke in a commit message" \
  "git commit -m 'fix: keystroke handling in editor'"
expect ALLOW "allows grepping for the word keystroke" \
  "grep -rn keystroke src/"

# --- Category opt-out must reach both new arms ---
begin_test "credentials opt-out allows the keychain read"
[ "$(verdict 'security find-generic-password -s github' credentials)" = "ALLOW" ] && pass \
  || fail "disableSecurityCategories=credentials did not reach the keychain patterns"

begin_test "clipboard opt-out allows the keystroke injection"
[ "$(verdict "osascript -e 'tell app \"System Events\" to keystroke \"x\"'" clipboard)" = "ALLOW" ] && pass \
  || fail "disableSecurityCategories=clipboard did not reach the input-inject patterns"

begin_test "an unrelated opt-out does NOT allow the keychain read"
[ "$(verdict 'security find-generic-password -s github' history)" = "DENY" ] && pass \
  || fail "an unrelated category opt-out disabled the keychain patterns"

report
