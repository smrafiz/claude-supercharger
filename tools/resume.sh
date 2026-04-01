#!/usr/bin/env bash
set -euo pipefail

SUMMARIES_DIR="$HOME/.claude/supercharger/summaries"

show_usage() {
  echo "Usage: resume.sh [--list | --show FILE]"
  echo ""
  echo "Retrieves session summaries for resuming Claude Code sessions."
  echo ""
  echo "  (no args)     Show latest summary and copy resume prompt to clipboard"
  echo "  --list        List all saved summaries"
  echo "  --show FILE   Show a specific summary"
  exit 0
}

copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy &>/dev/null; then
    echo "$text" | pbcopy
    echo "(Copied to clipboard)" >&2
  elif command -v xclip &>/dev/null; then
    echo "$text" | xclip -selection clipboard
    echo "(Copied to clipboard)" >&2
  elif command -v xsel &>/dev/null; then
    echo "$text" | xsel --clipboard --input
    echo "(Copied to clipboard)" >&2
  fi
}

# --- Help ---
if [[ "${1:-}" == "--help" ]]; then
  show_usage
fi

# --- List mode ---
if [[ "${1:-}" == "--list" ]]; then
  if [ ! -d "$SUMMARIES_DIR" ] || [ -z "$(ls -A "$SUMMARIES_DIR" 2>/dev/null)" ]; then
    echo "No session summaries found."
    echo "Say 'session summary' in Claude Code to generate one."
    exit 0
  fi
  for f in "$SUMMARIES_DIR"/*.md; do
    name=$(basename "$f")
    first_line=$(head -1 "$f" 2>/dev/null | sed 's/^#* *//')
    echo "$name — $first_line"
  done
  exit 0
fi

# --- Show mode ---
if [[ "${1:-}" == "--show" ]]; then
  if [ -z "${2:-}" ]; then
    echo "Usage: resume.sh --show FILENAME"
    exit 1
  fi
  FILE="$SUMMARIES_DIR/$2"
  if [ ! -f "$FILE" ]; then
    echo "Summary not found: $2"
    exit 1
  fi
  cat "$FILE"
  exit 0
fi

# --- Default: show latest and copy resume prompt ---
if [ ! -d "$SUMMARIES_DIR" ] || [ -z "$(ls -A "$SUMMARIES_DIR" 2>/dev/null)" ]; then
  echo "No session summaries found."
  echo "Say 'session summary' in Claude Code to generate one."
  exit 0
fi

LATEST=$(ls -t "$SUMMARIES_DIR"/*.md 2>/dev/null | head -1)
if [ -z "$LATEST" ]; then
  echo "No session summaries found."
  exit 0
fi

echo "=== Latest Session Summary ==="
echo ""
cat "$LATEST"
echo ""

# Extract "Resume with:" section
RESUME_TEXT=$(sed -n '/\*\*Resume with:\*\*/,/^$/p' "$LATEST" | tail -n +2)
if [ -z "$RESUME_TEXT" ]; then
  # Try alternate format without bold
  RESUME_TEXT=$(sed -n '/Resume with:/,/^$/p' "$LATEST" | tail -n +2)
fi

if [ -n "$RESUME_TEXT" ]; then
  echo "=== Resume Prompt ==="
  echo ""
  echo "$RESUME_TEXT"
  copy_to_clipboard "$RESUME_TEXT"
fi
