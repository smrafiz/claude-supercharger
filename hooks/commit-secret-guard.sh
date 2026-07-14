#!/usr/bin/env bash
# Claude Supercharger — Commit Secret Guard
# Event: PreToolUse | Matcher: Bash (git commit)
# Blocks `git commit` when the STAGED diff introduces a secret. Closes the gap
# between the other secret scanners:
#   - output-secrets-scanner scans tool OUTPUT (Bash/Read)
#   - code-security-scanner scans Write/Edit CONTENT
# A secret written via a Bash redirect (echo >> .env.local), or already present
# in a file that gets `git add`ed, reaches a commit unscanned by either. This
# hook scans `git diff --cached` added-lines against the shared pattern set.
# Reports only that a secret WAS found (never the value). Fully fail-open.
# Idea from dwarvesf/claude-guardrails (scan-commit.sh), ported to the shared
# pattern lib. Disable: SUPERCHARGER_COMMIT_SECRET_GUARD=0

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_COMMIT_SECRET_GUARD:-1}" = "0" ] && exit 0

_INPUT=$(cat)

# Fast-path: only `git commit` can matter.
case "$_INPUT" in *commit*) ;; *) exit 0 ;; esac

CMD=$(printf '%s\n' "$_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$CMD" ]; then
  CMD=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null || echo "")
fi
[ -z "$CMD" ] && exit 0

# Match `git commit` (word boundary so `git commit-tree`/`commit-graph` are left
# alone; leading boundary handles chained commands like `... && git commit`).
printf '%s\n' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_-])git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Run the scan in the command's cwd (top-level hook payload field).
CWD=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true)
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  cd "$CWD" 2>/dev/null || exit 0
fi

# Not a git repo → let git itself error; nothing to scan.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Scan ONLY staged changes — bounded to what's about to be recorded, and avoids
# re-flagging secrets committed before this hook existed.
DIFF=$(git diff --cached --unified=0 --no-color 2>/dev/null || true)
[ -z "$DIFF" ] && exit 0

# Added-line content only (strip the leading '+'); skip '+++' file headers so
# path strings don't leak into the scan.
ADDED=$(printf '%s\n' "$DIFF" | awk '/^\+\+\+ /{next} /^\+/{sub(/^\+/,""); print}')
[ -z "$ADDED" ] && exit 0

# shellcheck source=hooks/lib-secret-patterns.sh
. "$HOOKS_DIR/lib-secret-patterns.sh"
COMBINED_PATTERN=$(IFS='|'; echo "${SECRET_PATTERNS[*]}")

if printf '%s\n' "$ADDED" | LC_ALL=C grep -qE "$COMBINED_PATTERN"; then
  echo "[Supercharger] commit-secret-guard: SECRET in staged diff — blocking commit" >&2
  REASON='The staged changes introduce a value matching a known secret/credential format (API key, token, private key, or wallet key). Blocking this commit to prevent leaking it into git history. Remove the secret from the staged files (use an env var or a secrets manager), re-stage, and commit again. If this is a false positive, run the commit yourself in the terminal.'
  RSN=$(printf '%s' "$REASON" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || printf '"%s"' "$REASON")
  # Log the block (never the value).
  BLOG="$SUPERCHARGER_STATE/scope/.blocked-commands"
  mkdir -p "$(dirname "$BLOG")" 2>/dev/null || true
  printf '[%s] secret in staged commit — blocked\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BLOG" 2>/dev/null || true
  SID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true); [ -z "$SID" ] && SID="default"
  echo "secrets" > "$SUPERCHARGER_STATE/scope/.scan-alert-${SID}" 2>/dev/null || true
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$RSN"
  exit 2
fi

exit 0
