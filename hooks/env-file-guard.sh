#!/usr/bin/env bash
# Claude Supercharger — .env File Protection
# Event: PreToolUse | Matcher: Bash, Read
# Blocks reading/editing .env files (which typically contain credentials).
# Allows .env.example, .env.template, .env.sample, .env.dist (templates).
# Inspired by pchalasani/claude-code-tools/safety-hooks (Apache-2.0).

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "env-file-guard" && exit 0

block() {
  local reason="$1" preview="$2"
  echo "" >&2
  echo "Supercharger blocked .env access." >&2
  echo "  Reason : $reason" >&2
  echo "  Input  : ${preview:0:120}" >&2
  echo "  .env files commonly contain credentials. If you need this, run it in your terminal." >&2
  echo "" >&2
  RSN=$(printf '%s' "$reason" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
}

TOOL=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# Bash: check command for .env reads/edits
if [ "$TOOL" = "Bash" ]; then
  COMMAND=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
  [ -z "$COMMAND" ] && exit 0

  # Fast-path: if the command can't possibly reference a real .env file, skip.
  case "$COMMAND" in
    *.env*) ;;
    *) exit 0 ;;
  esac

  # Allow safe metadata commits/PRs that may mention .env in text
  if printf '%s\n' "$COMMAND" | grep -qE '^\s*(git\s+commit|git\s+tag|gh\s+(pr|issue|release)\s+create)\b'; then
    exit 0
  fi

  # Run the env-detection logic via external python module
  REASON=$(CMD="$COMMAND" python3 "$HOOKS_DIR/env-file-detect.py" 2>/dev/null)
  if [ -n "$REASON" ]; then
    block "$REASON" "$COMMAND"
  fi
  exit 0
fi

# Read tool: block reading .env files + /proc and /sys (process env exfil)
if [ "$TOOL" = "Read" ]; then
  FILE_PATH=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  [ -z "$FILE_PATH" ] && exit 0

  # v2.6.83: block /proc/<pid>/environ and /sys reads. Real incident: GitHub
  # issue-body prompt injection caused agent to Read /proc/self/environ,
  # exposing ANTHROPIC_API_KEY + GITHUB_TOKEN, which were then posted as a
  # PR comment (CC v2.1.128 fix, May 2026). Block at the Read input rather
  # than relying on output-secrets-scanner to catch the values downstream.
  case "$FILE_PATH" in
    /proc/*|/sys/*)
      block "Read of $FILE_PATH blocked — /proc and /sys may expose process env (e.g. /proc/self/environ contains ANTHROPIC_API_KEY)" "$FILE_PATH"
      ;;
  esac

  base=$(basename "$FILE_PATH")
  # templates are safe
  case "$base" in
    .env.example|.env.template|.env.sample|.env.dist) exit 0 ;;
  esac
  # v2.8.9: the Read tool is a separate channel from Bash — reading id_rsa /
  # *.pem / .netrc / .git-credentials / cloud credentials via Read bypassed this
  # guard, which only matched .env*. safety.sh/safety-detect.py already block the
  # full set for `cat`; mirror it here (keep in sync with
  # hooks/safety-detect.py:_SENSITIVE_NAME_RE). Pure bash case — no python fork
  # on the frequent Read path.
  case "$base" in
    .env|.env.*)
      block "Read of .env file blocked — credentials likely present" "$FILE_PATH" ;;
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*)
      block "Read of SSH private key blocked ($base) — key material" "$FILE_PATH" ;;
    *.pem|*.key|*.ppk|*.p12|*.pfx|*.crt|*.cer)
      block "Read of key/certificate file blocked ($base)" "$FILE_PATH" ;;
    .npmrc|.pypirc|.pgpass|.netrc|.authinfo|.authinfo.gpg|.git-credentials|.my.cnf)
      block "Read of credential file blocked ($base)" "$FILE_PATH" ;;
    wallet.dat|wallet.json|*.wallet|credentials)
      block "Read of wallet/credentials file blocked ($base)" "$FILE_PATH" ;;
  esac
  # credential paths not distinguished by basename alone
  case "$FILE_PATH" in
    */.aws/credentials|*/.ssh/id_*|*/.config/gcloud/*|*/.docker/config.json)
      block "Read of cloud/SSH credential blocked" "$FILE_PATH" ;;
  esac
  exit 0
fi

exit 0
