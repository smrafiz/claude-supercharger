#!/usr/bin/env bash
# Claude Supercharger — Subagent Report Fallback
# Event: SubagentStop | Matcher: * | async
#
# Companion to subagent-safety.sh's report-pin instruction (v2.6.82).
# The instruction is advisory — some subagents follow it, some don't.
# When the subagent DIDN'T Write its report to the per-agent-id path,
# this hook scrapes the JSONL transcript and writes the report itself.
# Result: zero-effort recovery — every subagent run has a readable report
# at $HOME/.claude/supercharger/scope/subagent-reports/<agent-id>.md.

set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // .workspace.current_dir // empty' 2>/dev/null || true); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"
check_hook_disabled "subagent-report-fallback" && exit 0

AGENT_ID=$(printf '%s\n' "$_INPUT" | jq -r '.agent_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-' | head -c 64 || true)
[ -z "$AGENT_ID" ] && exit 0

REPORT_DIR="$HOME/.claude/supercharger/scope/subagent-reports"
REPORT_PATH="$REPORT_DIR/${AGENT_ID}.md"

# Already wrote? Subagent complied; nothing to do.
[ -f "$REPORT_PATH" ] && [ -s "$REPORT_PATH" ] && exit 0

mkdir -p "$REPORT_DIR" 2>/dev/null || true

# Find the transcript. CC v2.1.176+ payloads carry `.agent_transcript_path`
# but older builds don't, so fall back to scanning the session task dir.
TRANSCRIPT=$(printf '%s\n' "$_INPUT" | jq -r '.agent_transcript_path // .transcript_path // empty' 2>/dev/null || true)

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  # Search common task dirs by agent-id.
  for d in /tmp/claude-*/-Users-*/*/tasks /private/tmp/claude-*/-Users-*/*/tasks; do
    [ -d "$d" ] || continue
    if [ -f "$d/${AGENT_ID}.output" ]; then
      TRANSCRIPT="$d/${AGENT_ID}.output"
      break
    fi
  done
fi

[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# Scrape assistant text blocks. Prefer structured markers (HOOK:, FINDING,
# etc.) but fall back to "all blocks ≥ 80 chars" if none match (mirrors
# tools/agent-report-tail.sh behavior).
TRANSCRIPT="$TRANSCRIPT" AGENT_ID="$AGENT_ID" REPORT_PATH="$REPORT_PATH" python3 <<'PYEOF' 2>/dev/null || true
import json, os, sys

transcript = os.environ['TRANSCRIPT']
agent_id = os.environ['AGENT_ID']
report_path = os.environ['REPORT_PATH']
markers = ('HOOK:', 'STATUS:', 'FAIL', 'PASS', 'BUG', 'FINDING', 'EXPECTED', 'ACTUAL', 'REPRO', 'PICK')

seen = set()
structured = []
all_blocks = []
with open(transcript) as f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get('type') != 'assistant':
            continue
        msg = d.get('message') or {}
        content = msg.get('content') or []
        if not isinstance(content, list):
            continue
        for c in content:
            if not isinstance(c, dict) or c.get('type') != 'text':
                continue
            t = (c.get('text') or '').strip()
            if not t or t in seen:
                continue
            seen.add(t)
            if len(t) >= 80:
                all_blocks.append(t)
            if any(m in t for m in markers):
                structured.append(t)

blocks = structured if structured else all_blocks
if not blocks:
    sys.exit(0)

with open(report_path, 'w') as f:
    f.write(f'# Subagent report (auto-recovered)\n\n')
    f.write(f'agent-id: `{agent_id}`\n')
    f.write(f'source: `{transcript}`\n')
    f.write(f'recovery: SubagentStop fallback (subagent did not Write the report itself)\n\n')
    for i, b in enumerate(blocks, 1):
        f.write(f'\n---\n\n## Block {i}\n\n{b}\n')

print(f'[Supercharger] subagent-report-fallback: wrote {len(blocks)} block(s) to {report_path}', file=sys.stderr)
PYEOF

exit 0
