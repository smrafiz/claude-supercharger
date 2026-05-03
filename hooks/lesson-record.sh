#!/usr/bin/env bash
# Claude Supercharger — Lesson Recorder (Reflexion Memory)
# Event: Stop | Matcher: *
# Scans assistant's last transcript message for diagnostic markers
# (the issue was, root cause, fixed by, ...) and appends a structured
# lesson record to <repo>/.claude/supercharger/lessons.jsonl.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-record" && exit 0
hook_profile_skip "lesson-record" && exit 0

exit 0
