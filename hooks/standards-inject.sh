#!/usr/bin/env bash
# Claude Supercharger — Stack Standards Injector
# Event: SessionStart | Matcher: (none)
# Detects project stack via lib/detect_stack.py and injects matching standards
# (forbidden patterns, toolchain, pitfalls) from rules/stacks/<name>.md.
# User override: ~/.claude/rules/stacks/<name>.md takes precedence over bundled.
# Tier-scaled output: minimal=stack tag, lean=key sections, standard=full.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"
RULES_DIR="$(cd "$HOOKS_DIR/../rules" && pwd)"

[ "${SUPERCHARGER_STANDARDS:-1}" = "0" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "standards-inject" && exit 0
hook_profile_skip "standards-inject" && exit 0

exit 0
