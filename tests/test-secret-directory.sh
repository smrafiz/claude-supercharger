#!/usr/bin/env bash
# Secret directories (v4.0.7).
#
# The detector matched sensitive FILENAMES, so a private key was protected only
# if it was called id_rsa. Measured before this existed — all open:
#
#   ~/.ssh/deploy_key   ~/.ssh/github_ci   ~/.ssh/prod-server
#   ~/.gnupg/secring.gpg                   ~/.aws/sso-cache.json
#
# Deploy keys, per-host keys and CI keys with custom names are ordinary
# practice, which makes "is it called id_rsa" a weak thing to hang protection on.
#
# The PUBLIC half is load-bearing. A blanket directory rule denies `cat
# ~/.ssh/config` and `cat ~/.ssh/known_hosts`, which are read routinely and are
# not secrets — that is how a guard earns a reputation for crying wolf and gets
# switched off. Both halves are pinned below.
#
# This rule was ALSO unreachable when first written: the detector fired, but
# safety.sh's _NEED_PY gate is keyed on filename globs and `deploy_key` matched
# none of them, so python never ran. Every case here therefore goes through the
# WHOLE hook, not the detector alone — testing the detector directly is what hid
# it the first time.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SAFETY="$REPO_DIR/hooks/safety.sh"
echo "=== secret directories ==="

_hook() {  # whole hook: gate + detector
  local d; d=$(mktemp -d)
  printf '{"session_id":"sd","cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"cat %s"}}' "$1" \
    | SUPERCHARGER_STATE="$d" SUPERCHARGER_NO_DEDUP=1 bash "$SAFETY" >/dev/null 2>&1
  local rc=$?; rm -rf "$d"
  [ "$rc" = 2 ] && echo deny || echo open
}

while IFS='|' read -r P WANT; do
  [ -z "$P" ] && continue
  case "$P" in \#*) continue ;; esac
  begin_test "secret-dir: ${P#/home/u/} -> $WANT"
  GOT=$(_hook "$P")
  [ "$GOT" = "$WANT" ] && pass || fail "got $GOT, wanted $WANT"
done <<'CASES'
# --- secrets whose NAME gives nothing away ---
/home/u/.ssh/deploy_key|deny
/home/u/.ssh/github_ci|deny
/home/u/.ssh/prod-server|deny
/home/u/.ssh/work_ed25519|deny
/home/u/.gnupg/secring.gpg|deny
/home/u/.aws/sso-cache.json|deny
# --- the standard names must still be caught (no regression) ---
/home/u/.ssh/id_rsa|deny
/home/u/.aws/credentials|deny
# --- PUBLIC members: routine reads that must NOT be denied ---
/home/u/.ssh/known_hosts|open
/home/u/.ssh/config|open
/home/u/.ssh/authorized_keys|open
/home/u/.ssh/id_rsa.pub|open
/home/u/.aws/config|open
/home/u/.gnupg/pubring.kbx|open
# --- unrelated paths that merely resemble one ---
/home/u/project/.sshconfig|open
/home/u/docs/ssh/setup.md|open
CASES

begin_test "secret-dir: the gate lets it reach the detector"
# The rule fired in safety-detect.py and was unreachable through safety.sh,
# because _NEED_PY is keyed on filename globs. Assert the whole path, not the
# detector — a rule present and unreachable looks exactly like a rule that works.
[ "$(_hook /home/u/.ssh/deploy_key)" = "deny" ] && pass || fail "gate swallowed the secret-directory rule"

begin_test "secret-dir: the category can be disabled like its siblings"
OUT=$(CMD="cat /home/u/.ssh/deploy_key" DISABLED_CATS="secret_directory" \
      python3 "$REPO_DIR/hooks/safety-detect.py" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "still fired with the category disabled: $OUT"

report
