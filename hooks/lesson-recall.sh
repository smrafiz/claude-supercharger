#!/usr/bin/env bash
# Claude Supercharger — Lesson Recaller (Reflexion Memory)
# Event: UserPromptSubmit | Matcher: (none)
# Tokenizes user prompt, computes Jaccard overlap against stored
# lessons.jsonl, injects top 3 matches above threshold 0.5.
# Output is tier-scaled.
# Disable: SUPERCHARGER_LESSONS=0

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

[ "${SUPERCHARGER_LESSONS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "lesson-recall" && exit 0
hook_profile_skip "lesson-recall" && exit 0

exit 0
