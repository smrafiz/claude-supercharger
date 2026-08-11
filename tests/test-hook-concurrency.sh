#!/usr/bin/env bash
# Hook concurrency reconstructor (v2.26.14).
#
# HOOK-LATENCY-PLAN §3b established that Claude Code runs same-event hooks in
# parallel, by reconstructing each hook's [start, end] from the audit log and
# testing for overlap. That was a one-off; every other event has since been
# reasoned about using PreToolUse's answer, which is an assumption rather than a
# result. tools/hook-concurrency.sh makes the method repeatable.
#
# Driven here with a synthetic audit log, because a real measurement needs a live
# Claude Code dispatcher — nothing a test can start.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-concurrency.sh"
TD=$(mktemp -d); trap 'rm -rf "$TD"' EXIT
mkdir -p "$TD/audit"
DATE=$(date +%Y-%m-%d)

echo "=== Hook Concurrency Tool Tests ==="

# Real hook names for the event, so the tool's hooks.json filter matches.
NAMES=$(python3 -c "
import json, sys
d=json.load(open(sys.argv[1]))
out=[]
for e in d['hooks']['UserPromptSubmit']:
    for h in e['hooks']:
        out.append(h['command'].split('/hooks/')[-1].split()[0].replace('.sh',''))
print(' '.join(out[:4]))" "$REPO_DIR/hooks/hooks.json")

write_log() {  # $1=mode (overlap|serial)
  : > "$TD/audit/$DATE.jsonl"
  local t=1000000 i=0
  for n in $NAMES; do
    if [ "$1" = "overlap" ]; then
      # All four start together and run 100ms — maximal overlap.
      printf '{"hook":"%s","elapsed_ms":100,"ts":%d}\n' "$n" "$((t + 100))" >> "$TD/audit/$DATE.jsonl"
    else
      # Strictly back-to-back — no two intervals share an instant.
      printf '{"hook":"%s","elapsed_ms":100,"ts":%d}\n' "$n" "$((t + (i + 1) * 100))" >> "$TD/audit/$DATE.jsonl"
    fi
    i=$((i + 1))
  done
}

begin_test "concurrency: detects parallel execution and reports the width"
write_log overlap
OUT=$(SUPERCHARGER_STATE="$TD" bash "$TOOL" UserPromptSubmit 2>&1)
{ printf '%s' "$OUT" | grep -q 'PARALLEL at width 4' \
  && printf '%s' "$OUT" | grep -q 'wall-clock span'; } \
  && pass || fail "parallel not detected: $OUT"

begin_test "concurrency: detects SEQUENTIAL execution and says the sum is the felt cost"
# The discriminator. A tool that reported "parallel" on everything would have
# confirmed §3b's finding no matter what the data said.
write_log serial
OUT=$(SUPERCHARGER_STATE="$TD" bash "$TOOL" UserPromptSubmit 2>&1)
{ printf '%s' "$OUT" | grep -q 'SEQUENTIAL' \
  && ! printf '%s' "$OUT" | grep -q 'PARALLEL'; } \
  && pass || fail "back-to-back intervals read as parallel: $OUT"

begin_test "concurrency: separates blocking hooks from async in the sum"
write_log overlap
OUT=$(SUPERCHARGER_STATE="$TD" bash "$TOOL" UserPromptSubmit 2>&1)
printf '%s' "$OUT" | grep -q 'of that, blocking hooks' && pass || fail "no blocking breakdown: $OUT"

begin_test "concurrency: ABORTS when there is no data rather than reporting a result"
# The failure this project keeps finding: an instrument that says something
# reassuring because it measured nothing. No records must never read as
# "sequential, cost zero".
: > "$TD/audit/$DATE.jsonl"
OUT=$(SUPERCHARGER_STATE="$TD" bash "$TOOL" UserPromptSubmit 2>&1); RC=$?
{ [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'no timing records'; } \
  && pass || fail "empty log must abort, got rc=$RC out=$OUT"

begin_test "concurrency: ABORTS on an event that is not registered"
write_log overlap
OUT=$(SUPERCHARGER_STATE="$TD" bash "$TOOL" NoSuchEvent 2>&1); RC=$?
{ [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'not registered'; } \
  && pass || fail "unregistered event must abort, got rc=$RC out=$OUT"

begin_test "concurrency: ABORTS when the audit log is missing entirely"
OUT=$(SUPERCHARGER_STATE="$TD/nope" bash "$TOOL" UserPromptSubmit 2>&1); RC=$?
{ [ "$RC" = "3" ] && printf '%s' "$OUT" | grep -q 'no audit log'; } \
  && pass || fail "missing log must abort, got rc=$RC out=$OUT"

report
