#!/usr/bin/env bash
set -euo pipefail

LOGS_DIR="$HOME/.claude/supercharger/logs"
SESSION_LOG="$LOGS_DIR/sessions.log"

show_usage() {
  echo "Usage: session-analytics.sh <subcommand> [args]"
  echo ""
  echo "Subcommands:"
  echo "  summary          Total sessions, today/week counts, top agents, exit reasons"
  echo "  agents           Agent usage table sorted by count"
  echo "  recent [N]       Last N sessions (default 10)"
  echo "  --help           Show this help"
  exit 0
}

check_log() {
  if [ ! -f "$SESSION_LOG" ] || [ ! -s "$SESSION_LOG" ]; then
    echo "No session data yet."
    exit 0
  fi
}

extract_agents() {
  awk '{ line=$0; sub(/.*agent=/, "", line); sub(/ cost=.*/, "", line); sub(/ *$/, "", line); if (line != "") print line }' "$SESSION_LOG"
}

extract_reasons() {
  awk '{
    match($0, /reason=[^ ]+/)
    if (RSTART > 0) print substr($0, RSTART+7, RLENGTH-7)
  }' "$SESSION_LOG"
}

cmd_summary() {
  check_log

  total=$(wc -l < "$SESSION_LOG" | tr -d ' ')

  today=$(date '+%Y-%m-%d')
  today_count=$(awk -v d="$today" '{ if (substr($0,2,10) == d) c++ } END { print c+0 }' "$SESSION_LOG")

  week_start=$(date -v-6d '+%Y-%m-%d' 2>/dev/null || date -d '6 days ago' '+%Y-%m-%d' 2>/dev/null || echo "")
  if [ -n "$week_start" ]; then
    week_count=$(awk -v ws="$week_start" '{ if (substr($0,2,10) >= ws) c++ } END { print c+0 }' "$SESSION_LOG")
  else
    week_count="n/a"
  fi

  echo "=== Session Summary ==="
  printf "Total sessions  : %s\n" "$total"
  printf "Today           : %s\n" "$today_count"
  printf "Last 7 days     : %s\n" "$week_count"
  echo ""

  echo "--- Top 5 Agents ---"
  extract_agents | sort | uniq -c | sort -rn | head -5 | \
    awk '{ printf "  %-4s %s\n", $1, substr($0, index($0,$2)) }'
  echo ""

  echo "--- Exit Reasons ---"
  extract_reasons | sort | uniq -c | sort -rn | \
    awk '{ printf "  %-4s %s\n", $1, $2 }'
}

cmd_agents() {
  check_log

  total=$(wc -l < "$SESSION_LOG" | tr -d ' ')

  echo "=== Agent Usage ==="
  printf "%-40s %6s %8s\n" "Agent" "Count" "Pct"
  printf '%0.s-' {1..57}; echo

  extract_agents | sort | uniq -c | sort -rn | \
    awk -v total="$total" '{
      count = $1
      agent = substr($0, index($0,$2))
      pct = (total > 0) ? count * 100 / total : 0
      printf "%-40s %6d %7.1f%%\n", agent, count, pct
    }'
}

cmd_recent() {
  check_log

  n="${1:-10}"
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "Error: N must be a positive integer" >&2
    exit 1
  fi

  echo "=== Recent Sessions (last $n) ==="
  printf "%-12s %-10s %-35s %s\n" "Date" "Time" "Agent" "Reason"
  printf '%0.s-' {1..70}; echo

  tail -n "$n" "$SESSION_LOG" | \
    awk '{
      date = substr($0, 2, 10)
      time = substr($0, 13, 8)
      line = $0
      sub(/.*reason=/, "", line); match(line, /[^ ]+/); reason = substr(line, 1, RLENGTH)
      line = $0
      sub(/.*agent=/, "", line); sub(/ cost=.*/, "", line); sub(/ *$/, "", line); agent = line
      printf "%-12s %-10s %-35s %s\n", date, time, agent, reason
    }'
}

# --- Main ---
if [ $# -eq 0 ] || [[ "${1:-}" == "--help" ]]; then
  show_usage
fi

case "$1" in
  summary) cmd_summary ;;
  agents)  cmd_agents ;;
  recent)  cmd_recent "${2:-10}" ;;
  *) echo "Unknown subcommand: $1" >&2; echo "Run with --help for usage." >&2; exit 1 ;;
esac
