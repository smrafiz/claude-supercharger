#!/usr/bin/env bash
# Guards are independent of the harness's permission layer (P2, 2026-09-17)
#
# The product claim, as stated to users: the safety checks fire outside the model
# loop and deny by exit code, whatever the approval mode says. Upstream #8961
# reports deny rules in `.claude/settings.local.json` being silently ignored —
# exactly the scenario Supercharger exists to cover — and #36168 reports
# bypassPermissions behaving differently across versions. Neither should matter
# to us, because no deny-path guard reads the harness's permission config.
#
# "Because it doesn't read it" is an argument, not a test. This pins the OUTCOME,
# so that a future guard which DOES start consulting an allow-list fails here
# rather than in someone's repo. The adjacent invariants are already covered and
# are deliberately not repeated: the autopilot safety floor lives in
# test-autopilot.sh, the user's own deny/ask in test-smart-approve-user-deny.sh.
#
# Hostile config, applied to every case at once:
#   - permissions.allow wide open, in user AND project settings
#   - permissions.defaultMode = bypassPermissions
#   - permission_mode = bypassPermissions in the tool payload itself
#   - an OPEN autopilot window
#
# Sensitive literals are assembled at runtime (E="."'env'); spelled out, the
# deployed guards would deny every edit and grep of this file.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

E="."'env'

echo "=== Guards vs a hostile harness permission layer ==="

# hostile settings, written to BOTH the user and the project location
OPEN_RULES='{"permissions":{"defaultMode":"bypassPermissions","allow":["Bash(*)","Read(//**)","Bash(cat:*)","Bash(rm:*)","Bash(git push:*)"]}}'

denies_under_hostile_config() { # label, hook, tool, json-tool-input
  local st h
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home/.claude" "$st/.claude"
  printf '%s' "$OPEN_RULES" > "$st/home/.claude/settings.json"
  printf '%s' "$OPEN_RULES" > "$st/.claude/settings.json"
  printf '%s' "$OPEN_RULES" > "$st/.claude/settings.local.json"
  # an open autopilot window: every prompt auto-approved for the next hour
  echo $(( $(date +%s) + 3600 )) > "$st/scope/.autopilot-until"

  TOOL="$3" TI="$4" ST="$st" python3 -c '
import json, os
print(json.dumps({"tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TI"]),
                  "permission_mode": "bypassPermissions",
                  "cwd": os.environ["ST"]}))' > "$st/payload.json"

  env HOME="$st/home" SUPERCHARGER_STATE="$st" \
    bash "$REPO_DIR/hooks/$2" < "$st/payload.json" >/dev/null 2>&1
  h=$?
  rm -rf "$st"
  [ "$h" -eq 2 ] && pass || fail "$1: $2 returned $h, expected 2 — the harness permission layer suppressed a guard"
}

allows_under_hostile_config() { # label, hook, tool, json-tool-input
  # The negative control. Without it, every assertion above would also pass if
  # the fixture made the hooks deny EVERYTHING -- a corpus that cannot fail is
  # the instrument-blindness shape this repo keeps finding in its own checks.
  local st h
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home/.claude" "$st/.claude"
  printf '%s' "$OPEN_RULES" > "$st/home/.claude/settings.json"
  printf '%s' "$OPEN_RULES" > "$st/.claude/settings.json"
  printf '%s' "$OPEN_RULES" > "$st/.claude/settings.local.json"
  echo $(( $(date +%s) + 3600 )) > "$st/scope/.autopilot-until"

  TOOL="$3" TI="$4" ST="$st" python3 -c '
import json, os
print(json.dumps({"tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TI"]),
                  "permission_mode": "bypassPermissions",
                  "cwd": os.environ["ST"]}))' > "$st/payload.json"

  env HOME="$st/home" SUPERCHARGER_STATE="$st" \
    bash "$REPO_DIR/hooks/$2" < "$st/payload.json" >/dev/null 2>&1
  h=$?
  rm -rf "$st"
  [ "$h" -ne 2 ] && pass || fail "$1: $2 denied an ordinary command — the fixture denies everything, so the cases above prove nothing"
}

begin_test "a protected-path rm still denies with permissions.allow wide open"
denies_under_hostile_config "rm-protected" safety.sh Bash '{"command":"rm -rf /"}'

begin_test "a credential read still denies under bypassPermissions"
denies_under_hostile_config "cred-read" env-file-guard.sh Bash "$(printf '{"command":"cat %s"}' "$E")"

begin_test "the Read channel still denies with Read(//**) allowed"
denies_under_hostile_config "cred-read-tool" env-file-guard.sh Read "$(printf '{"file_path":"/srv/app/%s"}' "$E")"

begin_test "a force push still denies with Bash(git push:*) allowed"
denies_under_hostile_config "force-push" git-safety.sh Bash '{"command":"git push --force origin master"}'

begin_test "an ordinary read is still allowed under the same hostile config"
allows_under_hostile_config "benign-read" env-file-guard.sh Read '{"file_path":"/srv/app/README.md"}'

begin_test "an ordinary command is still allowed under the same hostile config"
allows_under_hostile_config "benign-bash" safety.sh Bash '{"command":"ls -la src/"}'

report
