#!/usr/bin/env bash
# Claude Supercharger — Smart Approve
# Event: PermissionRequest | Matcher: (none)
# Auto-approves known-safe tool calls to reduce user prompts.
# Emits a PermissionRequest decision (hookSpecificOutput.decision.behavior=allow).
#
# RELATIONSHIP TO CC's BUILT-IN AUTO-MODE CLASSIFIER:
# CC ships an LLM-based auto-mode rule reviewer (categories: allow / soft_deny /
# hard_deny / environment) that reads user-defined rules at runtime and may
# pre-decide PermissionRequest events. This shell hook runs ADDITIVELY in the
# same pipeline — not as a replacement. Per Piebald-AI/claude-code-system-prompts
# auto-mode-rule-reviewer (v2.1.x), the two are independent decision sources:
# tightening here does not loosen CC's classifier, and vice versa. Treat this
# hook as a fast deterministic allow-list for known-safe shapes; let CC's LLM
# classifier handle the fuzzy, intent-based decisions.
#
# v2.7.32: the allow-list decision lives in lib-smart-approve.sh so that
# notify-permission.sh can consult the SAME verdict and skip its desktop
# notification for anything auto-approved here (no "permission needed" ping for
# permissions the user never has to act on).

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HOOKS_DIR/lib-timing.sh"
. "$HOOKS_DIR/lib-smart-approve.sh"

_INPUT=$(cat)

if smart_approve_verdict "$_INPUT"; then
  TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // "?"' 2>/dev/null || echo "?")
  echo "[Supercharger] smart-approve: auto-approved ${TOOL_NAME}" >&2
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
fi

# Everything else: pass through, let Claude Code / its classifier decide.
exit 0
