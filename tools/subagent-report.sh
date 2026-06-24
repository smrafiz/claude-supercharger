#!/usr/bin/env bash
# Claude Supercharger — Subagent Report Reader
#
# Companion to subagent-safety.sh's v2.6.82 report-pin instruction: the
# subagent is told to Write its full report to:
#   $HOME/.claude/supercharger/scope/subagent-reports/<agent-id>.md
# This tool lists and reads those reports. Use when the parent session
# sees only "Ready." / "Standing by." instead of the full subagent output
# (CC v2.1.176+ return-channel degradation, anthropics/claude-code#69970).
#
# Usage:
#   bash tools/subagent-report.sh                 # list all reports
#   bash tools/subagent-report.sh --latest        # show newest report
#   bash tools/subagent-report.sh <agent-id>      # show specific report
#   bash tools/subagent-report.sh --clean         # remove all reports

set -euo pipefail

REPORT_DIR="$HOME/.claude/supercharger/scope/subagent-reports"
mkdir -p "$REPORT_DIR" 2>/dev/null || true

if [ ! -d "$REPORT_DIR" ] || [ -z "$(ls -A "$REPORT_DIR" 2>/dev/null)" ]; then
  echo "No subagent reports found at $REPORT_DIR" >&2
  echo "(Subagents must write to this path during SubagentStart hook injection.)" >&2
  exit 0
fi

case "${1:-}" in
  --clean)
    find "$REPORT_DIR" -maxdepth 1 -type f -name '*.md' -delete 2>/dev/null
    echo "Cleared subagent reports" >&2
    exit 0
    ;;
  --latest)
    LATEST=$(ls -t "$REPORT_DIR"/*.md 2>/dev/null | head -1)
    if [ -z "$LATEST" ]; then
      echo "No reports found" >&2
      exit 1
    fi
    echo "── $(basename "$LATEST" .md) ──" >&2
    cat "$LATEST"
    ;;
  "")
    echo "Subagent reports in $REPORT_DIR:"
    ls -lt "$REPORT_DIR"/*.md 2>/dev/null | awk '{
      size=$5; mtime=$6" "$7" "$8;
      n=split($NF, parts, "/"); name=parts[n]; sub(/\.md$/, "", name);
      printf "  %s  %5s bytes  %s\n", mtime, size, name
    }'
    echo ""
    echo "Use: bash $(basename "$0") --latest"
    echo "  or bash $(basename "$0") <agent-id>"
    ;;
  -h|--help)
    sed -n '4,17p' "$0" | sed 's/^# //'
    exit 0
    ;;
  *)
    AGENT_ID="$1"
    if ! [[ "$AGENT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      echo "error: invalid agent-id (must match [a-zA-Z0-9_-]+)" >&2
      exit 1
    fi
    REPORT="$REPORT_DIR/${AGENT_ID}.md"
    if [ ! -f "$REPORT" ]; then
      echo "error: report not found: $REPORT" >&2
      echo "Available reports:" >&2
      ls -1 "$REPORT_DIR"/*.md 2>/dev/null | sed 's|.*/||; s|\.md$||' | sed 's/^/  /' >&2
      exit 1
    fi
    cat "$REPORT"
    ;;
esac
