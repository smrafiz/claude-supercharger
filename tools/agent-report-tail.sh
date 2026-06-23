#!/usr/bin/env bash
# Claude Supercharger — Agent Report Recovery
#
# Workaround for the Claude Code v2.1.176 return-message degradation bug
# (anthropics/claude-code#69970): subagents' final messages reach the parent
# session as one-line confirmations ("Ready.", "Standing by.") even when the
# agent produced full structured output earlier in the conversation. The full
# report still exists in the agent's JSONL transcript on disk; this tool
# extracts it.
#
# CC SUBAGENT RETURN CHANNELS (per liuup/claude-code-analysis 04h-multi-agent):
# There are three independent return paths, not one. The v2.1.176 regression
# appears to affect only the *coordinator* path (used by the Task tool's
# spawned agents that we rely on here):
#   1. Direct synchronous return — `runAgent()` iterates response messages and
#      returns structured output to the caller. Used by simple/in-process
#      subagent calls. May still work reliably in v2.1.176.
#   2. Mailbox files at `.claude/teams/{team}/inboxes/{agent}.json`, polled by
#      `useInboxPoller()` with file locking. Used by swarm/teammates mode.
#   3. Resume-injection via `resumeAgentBackground()` queueing results into the
#      parent's `pendingUserMessages`. Used by background agents.
# This tool targets the JSONL transcript scrape — a 4th out-of-band path that
# survives all three above being degraded. Keep using it until #69970 is fixed
# upstream; do NOT delete this tool just because the parent return-channel
# starts working again, since the failure modes differ per CC version.
#
# Usage:
#   bash tools/agent-report-tail.sh <agent-id>
#   bash tools/agent-report-tail.sh <agent-id> --all
#   bash tools/agent-report-tail.sh --latest
#
# Default filter: prints assistant text blocks containing structured markers
# (HOOK:, STATUS:, FAIL, PASS, BUG, FINDING). Use --all to print every text
# block longer than 80 chars (broader recovery for unstructured reports).
#
# --latest: scans the current session's task dir and uses the most recently
# completed agent id.

set -euo pipefail

AGENT_ID=""
MODE="structured"

while [ $# -gt 0 ]; do
  case "$1" in
    --all)    MODE="all" ;;
    --latest) AGENT_ID="__LATEST__" ;;
    -h|--help)
      sed -n '4,30p' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      [ -z "$AGENT_ID" ] && AGENT_ID="$1"
      ;;
  esac
  shift
done

# v2.6.77: validate AGENT_ID before using it in a file path — prevents path
# traversal (e.g. ../../.ssh/id_rsa) when the tool is invoked with a
# model-generated or user-supplied agent id.
if [ -n "$AGENT_ID" ] && [ "$AGENT_ID" != "__LATEST__" ]; then
  if ! [[ "$AGENT_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "error: invalid agent-id (must match [a-zA-Z0-9_-]+)" >&2
    exit 1
  fi
fi

if [ -z "$AGENT_ID" ]; then
  echo "usage: $(basename "$0") <agent-id> [--all]" >&2
  echo "       $(basename "$0") --latest [--all]" >&2
  exit 1
fi

# Locate the task dir for the current session.
SESSION_BASE=""
for d in /tmp/claude-*/-Users-*/*/tasks /private/tmp/claude-*/-Users-*/*/tasks; do
  [ -d "$d" ] || continue
  SESSION_BASE="$d"
  break
done

if [ -z "$SESSION_BASE" ]; then
  echo "error: no Claude Code session task dir found under /tmp" >&2
  exit 1
fi

if [ "$AGENT_ID" = "__LATEST__" ]; then
  AGENT_ID=$(ls -t "$SESSION_BASE"/*.output 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.output$//')
  if [ -z "$AGENT_ID" ]; then
    echo "error: no agent transcripts found in $SESSION_BASE" >&2
    exit 1
  fi
  echo "[latest] agent: $AGENT_ID" >&2
fi

OUTPUT_FILE="$SESSION_BASE/${AGENT_ID}.output"
if [ ! -f "$OUTPUT_FILE" ]; then
  echo "error: transcript not found: $OUTPUT_FILE" >&2
  exit 1
fi

MODE="$MODE" python3 -c "
import json, os, sys

mode = os.environ.get('MODE', 'structured')
markers = ('HOOK:', 'STATUS:', 'FAIL', 'PASS', 'BUG', 'FINDING', 'EXPECTED', 'ACTUAL', 'REPRO')

seen = set()
count = 0
with open(sys.argv[1]) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get('type') != 'assistant':
            continue
        content = (d.get('message') or {}).get('content') or []
        if not isinstance(content, list):
            continue
        for c in content:
            if not isinstance(c, dict) or c.get('type') != 'text':
                continue
            t = (c.get('text') or '').strip()
            if not t or t in seen:
                continue
            if mode == 'structured':
                if not any(m in t for m in markers):
                    continue
            else:
                if len(t) < 80:
                    continue
            seen.add(t)
            print(t)
            print('---')
            count += 1

print(f'[{count} block(s)]', file=sys.stderr)
" "$OUTPUT_FILE"
