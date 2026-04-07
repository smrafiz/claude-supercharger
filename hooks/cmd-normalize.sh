#!/usr/bin/env bash
# Claude Supercharger — Command Normalization Helper
# Sourced by PreToolUse hooks that inspect the Bash command string.
# Usage: CMD=$(normalize_cmd "$COMMAND")

normalize_cmd() {
  local cmd="$1"
  cmd=$(printf '%s\n' "$cmd" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  cmd=$(printf '%s\n' "$cmd" | sed 's/^\\//')
  while printf '%s\n' "$cmd" | grep -qE '^(sudo|command|env)[[:space:]]+'; do
    cmd=$(printf '%s\n' "$cmd" | sed -E 's/^(sudo|command|env)[[:space:]]+//')
  done
  cmd=$(printf '%s\n' "$cmd" | tr -s ' ')
  printf '%s\n' "$cmd"
}
