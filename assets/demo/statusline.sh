#!/usr/bin/env bash
# Demo helper — render Supercharger's real statusline from a fixed sample payload
# (the JSON Claude Code sends it), so the recording needs no live session. It runs
# in a throwaway HOME with a neutral project, so nothing of yours shows up.
set -uo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
scope="$tmp/.claude/supercharger/scope"; mkdir -p "$scope"
echo '{"new_tokens": 1240000}' > "$scope/.main-tokens-demo"
proj="$tmp/my-app"; mkdir -p "$proj"
git -C "$proj" init -q -b main && echo app > "$proj/README.md" && git -C "$proj" add README.md \
  && git -C "$proj" -c user.email=demo@example.com -c user.name=demo commit -qm init
now=$(date +%s)
printf '%s' "{\"session_id\":\"demo\",\"model\":{\"id\":\"claude-opus-5-5\",\"display_name\":\"Opus 5.5\"},
 \"workspace\":{\"current_dir\":\"$proj\",\"project_dir\":\"$proj\"},\"cwd\":\"$proj\",
 \"cost\":{\"total_cost_usd\":2.45,\"total_duration_ms\":492000},
 \"context_window\":{\"context_window_size\":1000000,\"used_percentage\":42,
   \"current_usage\":{\"input_tokens\":12000,\"output_tokens\":5300,\"cache_read_input_tokens\":398000,\"cache_creation_input_tokens\":9000}},
 \"rate_limits\":{\"five_hour\":{\"used_percentage\":34,\"resets_at\":$((now + 8580))},
   \"seven_day\":{\"used_percentage\":88,\"resets_at\":$((now + 30000))}}}" \
  | HOME="$tmp" SUPERCHARGER_STATE="$tmp/.claude/supercharger" bash "$REPO_DIR/hooks/statusline.sh"
echo
