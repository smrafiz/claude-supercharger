#!/usr/bin/env bash
# Archiving secrets (v4.0.7).
#
# `tar czf /tmp/x.tgz ~/.ssh` was the last measured step-1 vector: it lands every
# key in one file under an innocuous name, and the upload afterwards carries no
# signature at all. The other routes into an unrecognised file — cp/mv/install/
# rsync, redirects, tee, awk/sed, interpreter copies, dd — were closed first.
#
# EXTRACTION is deliberately not matched. `tar xzf release.tgz` is ordinary work
# and denying it would be pure friction, so only create modes are checked.
#
# Every case runs through the WHOLE hook. The rule was unreachable when first
# written for the secret-directory check because safety.sh's gate is glob-based,
# and `/home/u/.ssh` has no trailing slash so `*/.ssh/*` did not match it —
# testing the detector alone is what hides that.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

SAFETY="$REPO_DIR/hooks/safety.sh"
echo "=== archiving secrets ==="

_hook() {
  local d; d=$(mktemp -d)
  printf '{"session_id":"as","cwd":"/tmp","tool_name":"Bash","hook_event_name":"PreToolUse","tool_input":{"command":"%s"}}' "$1" \
    | SUPERCHARGER_STATE="$d" SUPERCHARGER_NO_DEDUP=1 bash "$SAFETY" >/dev/null 2>&1
  local rc=$?; rm -rf "$d"
  [ "$rc" = 2 ] && echo deny || echo open
}

while IFS='|' read -r CMD WANT; do
  [ -z "$CMD" ] && continue
  case "$CMD" in \#*) continue ;; esac
  begin_test "archive: ${CMD:0:54} -> $WANT"
  GOT=$(_hook "$CMD")
  [ "$GOT" = "$WANT" ] && pass || fail "got $GOT, wanted $WANT"
done <<'CASES'
# --- creating an archive that swallows a secret directory ---
tar czf /tmp/x.tgz /home/u/.ssh|deny
tar cf /tmp/x.tar /home/u/.gnupg|deny
tar -czvf /tmp/x.tgz /home/u/.aws|deny
zip -r /tmp/x.zip /home/u/.ssh|deny
# --- a named secret swept into an archive ---
tar czf /tmp/x.tgz /home/u/.ssh/id_rsa|deny
# --- EXTRACTION is not exfil ---
tar xzf /tmp/release.tgz|open
tar xf archive.tar -C /tmp|open
unzip /tmp/site.zip|open
# --- ordinary archiving ---
tar czf /tmp/src.tgz ./src|open
tar czf dist.tgz build/|open
zip -r site.zip ./public|open
tar czf /tmp/docs.tgz docs README.md|open
# --- public members must not drag an archive into a denial ---
tar czf /tmp/keys.tgz /home/u/.ssh/id_rsa.pub|open
CASES

begin_test "archive: the gate passes a directory with no trailing slash"
# `/home/u/.ssh` does not match the */.ssh/* glob written for the reader rule.
# A rule the cheap gate does not admit is unreachable — five instances of that
# trap in this release line.
[ "$(_hook "tar czf /tmp/x.tgz /home/u/.ssh")" = "deny" ] && pass || fail "gate swallowed the archive rule"

begin_test "archive: the category can be disabled like its siblings"
OUT=$(CMD="tar czf /tmp/x.tgz /home/u/.ssh" DISABLED_CATS="archive_secrets secret_directory" \
      python3 "$REPO_DIR/hooks/safety-detect.py" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "still fired with the category disabled: $OUT"

report
