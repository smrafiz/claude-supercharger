#!/usr/bin/env bash
# Claude Supercharger — Hook Output Suppress Helper
# Source this file to get HOOK_SUPPRESS (true/false).
#
# Output is suppressed by default. To show hook output:
#   Global:  touch ~/.claude/supercharger/scope/.debug-hooks
#   Project: touch .supercharger-debug  (in project root)

HOOK_SUPPRESS=true
if [ -f "$HOME/.claude/supercharger/scope/.debug-hooks" ] || [ -f "${PWD}/.supercharger-debug" ]; then
  HOOK_SUPPRESS=false
fi
