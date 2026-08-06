#!/usr/bin/env bash
# Block-ledger line integrity (v2.26.17)
#
# scope/.blocked-commands is LINE-BASED: /why reads the last N lines, and
# learn-from-blocks parses it into the [BLOCKS] summary injected into every session's
# context. All three writers embedded the raw command, so a MULTI-LINE blocked command
# wrote a multi-line entry — a fragment such as `rm -rf .` became its own row and read
# as a real destructive block. Three corrupted rows were found in the live ledger.
#
# Shortening to 120 chars does not help: the newline sits inside the first 120 bytes.
# The collapse has to happen first, which is what these tests pin.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# A command whose dangerous part is on a LATER line — the shape that corrupted rows.
MULTILINE='echo "step one"
rm -rf /
echo "step three"'

run_hook() { # hook, command -> writes into an isolated state dir, echoes that dir
  local hook="$1" cmd="$2" st
  st=$(mktemp -d); mkdir -p "$st/scope"
  printf '%s' "$(CMD="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]}}))')" \
    | env SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$hook" >/dev/null 2>&1
  printf '%s' "$st"
}

# Every line in the ledger must be a complete entry: `[timestamp] reason — command`.
all_lines_well_formed() {
  local f="$1"
  [ -s "$f" ] || return 1
  ! grep -qvE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}' "$f"
}

echo "=== Block Ledger Format Tests ==="

begin_test "safety.sh: a multi-line command writes ONE well-formed row"
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED"; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' ')"
else
  fail "ledger empty or contains a fragment row: $(head -3 "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test "safety.sh: the entry keeps the dangerous text (collapsed, not truncated away)"
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
grep -q 'rm -rf /' "$LED" 2>/dev/null && pass || fail "collapsing lost the command: $(cat "$LED" 2>/dev/null)"
rm -rf "$ST"

begin_test "harness-tamper-guard: a multi-line teardown writes ONE well-formed row"
ST=$(run_hook harness-tamper-guard.sh 'echo one
rm -rf ~/.claude/supercharger/hooks
echo three')
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED"; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' ')"
else
  fail "ledger empty or fragmented: $(head -3 "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test 'no row is a bare fragment (the rm-dash-rf-dot symptom)'
ST=$(run_hook safety.sh "$MULTILINE")
LED="$ST/scope/.blocked-commands"
grep -qxE '\s*(rm -rf \.|echo .*)' "$LED" 2>/dev/null && fail "a fragment row was written" || pass
rm -rf "$ST"

begin_test "single-line commands are unaffected"
ST=$(run_hook safety.sh 'rm -rf /')
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ] && all_lines_well_formed "$LED" && [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ]; then
  pass
else
  fail "single-line case regressed: $(cat "$LED" 2>/dev/null)"
fi
rm -rf "$ST"

begin_test "tabs are collapsed too (they break column parsing downstream)"
# Tab-indented second line: blockable AND carries a real tab.
ST=$(run_hook safety.sh "$(printf 'echo one\n\trm -rf /')")
LED="$ST/scope/.blocked-commands"
if [ -s "$LED" ]; then
  if LC_ALL=C grep -q "$(printf '\t')" "$LED" 2>/dev/null; then
    fail "a tab survived into the ledger"
  else
    pass
  fi
else
  fail "nothing logged"
fi
rm -rf "$ST"

# --- Sibling ledgers (v2.26.64) -----------------------------------------------
# v2.26.17 fixed this for .blocked-commands only. The SAME line-based contract
# governs .user-corrections, .user-reinforcements and .failed-commands, and none
# of those writers collapsed newlines. Found by auditing the sibling branches of
# the original fix rather than other instances of the same call.

# learn-from-prompts fires on UserPromptSubmit; the prompt text is the payload.
prompt_hook() { # prompt -> state dir
  local st; st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  ST="$st" P="$1" python3 -c '
import json, os
print(json.dumps({"prompt": os.environ["P"], "cwd": os.environ["ST"],
                  "session_id": "led", "hook_event_name": "UserPromptSubmit"}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/learn-from-prompts.sh" >/dev/null 2>&1
  printf '%s' "$st"
}

# failure-tracker short-circuits unless stderr carries a STRONG failure marker.
fail_hook() { # command, repeats -> state dir; echoes nothing
  local st="$1" cmd="$2" n="$3" i
  ST="$st" C="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["C"]},
                  "tool_response": {"stderr": "deploy: command not found",
                                    "stdout": "", "interrupted": False},
                  "cwd": os.environ["ST"], "hook_event_name": "PostToolUse"}))' > "$st/payload.json"
  LAST=""
  for ((i=0; i<n; i++)); do
    LAST=$(env HOME="$st/home" SUPERCHARGER_STATE="$st" \
      bash "$REPO_DIR/hooks/failure-tracker.sh" < "$st/payload.json" 2>/dev/null)
  done
  printf '%s' "$LAST"
}

MULTILINE_PROMPT='no, that is wrong:
use the other approach instead'

begin_test "learn-from-prompts: a multi-line CORRECTION writes ONE row"
ST=$(prompt_hook "$MULTILINE_PROMPT")
LED=$(ls "$ST"/scope/.user-corrections-* 2>/dev/null | head -1)
if [ -s "$LED" ]; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' '): $(cat "$LED")"
else
  fail "nothing logged for a correction-shaped prompt"
fi
rm -rf "$ST"

begin_test "learn-from-prompts: the correction row is well-formed"
ST=$(prompt_hook "$MULTILINE_PROMPT")
LED=$(ls "$ST"/scope/.user-corrections-* 2>/dev/null | head -1)
all_lines_well_formed "$LED" && pass || fail "fragment row written: $(cat "$LED" 2>/dev/null)"
rm -rf "$ST"

begin_test "learn-from-prompts: the continuation text is kept, not dropped"
# Collapsing must not truncate the correction away — the tail is the useful half.
ST=$(prompt_hook "$MULTILINE_PROMPT")
LED=$(ls "$ST"/scope/.user-corrections-* 2>/dev/null | head -1)
grep -q 'use the other approach instead' "$LED" 2>/dev/null && pass || fail "collapsing lost the tail: $(cat "$LED" 2>/dev/null)"
rm -rf "$ST"

begin_test "learn-from-prompts: a multi-line REINFORCEMENT writes ONE row"
ST=$(prompt_hook 'perfect, thanks:
that is exactly what I wanted')
LED=$(ls "$ST"/scope/.user-reinforcements-* 2>/dev/null | head -1)
if [ -s "$LED" ]; then
  [ "$(wc -l < "$LED" | tr -d ' ')" -eq 1 ] && pass || fail "expected 1 row, got $(wc -l < "$LED" | tr -d ' '): $(cat "$LED")"
else
  fail "nothing logged for a reinforcement-shaped prompt"
fi
rm -rf "$ST"

begin_test "failure-tracker: a multi-line failing command writes ONE row per failure"
ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home"
fail_hook "$ST" 'npm run build
&& deploy --prod' 3 >/dev/null
LED=$(ls "$ST"/scope/.failed-commands-* 2>/dev/null | head -1)
N=$(wc -l < "$LED" 2>/dev/null | tr -d ' ')
[ "${N:-0}" -eq 3 ] && pass || fail "3 failures wrote $N rows: $(cat "$LED" 2>/dev/null)"
rm -rf "$ST"

begin_test "failure-tracker: the repeat-failure nudge fires for MULTI-LINE commands"
# The consequence that was not cosmetic. FAIL_COUNT comes from `awk index($0,k)`;
# a key containing a newline can never match a single line, so the counter stuck
# at 0 and the "try a different approach" nudge never fired.
ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home"
OUT=$(fail_hook "$ST" 'npm run build
&& deploy --prod' 3)
printf '%s' "$OUT" | grep -q 'failed' && pass || fail "no nudge after 3 multi-line failures (got: ${OUT:-<empty>})"
rm -rf "$ST"

begin_test "failure-tracker: single-line commands still nudge (no regression)"
ST=$(mktemp -d); mkdir -p "$ST/scope" "$ST/home"
OUT=$(fail_hook "$ST" 'npm run build && deploy --prod' 3)
printf '%s' "$OUT" | grep -q 'failed' && pass || fail "single-line nudge regressed (got: ${OUT:-<empty>})"
rm -rf "$ST"

# --- ledger command budget (v2.26.67) -----------------------------------------

begin_test "a long command survives past 120 chars in the ledger"
# The cap was 120 with the rationale "avoid bloating session context". That stopped
# being true in v2.26.63, when [BLOCKS] switched to injecting reasons and never
# command text. The cost showed up on 2026-08-06: an FP investigation could not read
# its own ledger, because the blocks under investigation were `--message` values
# sitting past character 120 — the stored fragment kept neither the trigger nor the
# flag that caused the block.
LONGCMD="rm -rf / # $(printf 'x%.0s' $(seq 1 200)) TAILMARKER"
ST=$(run_hook safety.sh "$LONGCMD")
LED="$ST/scope/.blocked-commands"
grep -q 'TAILMARKER' "$LED" 2>/dev/null && pass || fail "tail lost — cap still too low: $(wc -c < "$LED" 2>/dev/null) bytes"
rm -rf "$ST"

begin_test "every ledger writer shares the same command budget"
# A meta-test rather than a shared constant: four hooks append to this one file, and
# the 120 cap drifted across them independently. Any writer left at a lower cap makes
# the ledger inconsistent, which is what makes it unreadable for forensics.
# Only writes bound for THIS ledger count. safety.sh also has a `cmd=%.140s` trace
# line writing to a different file — an earlier draft of this test flagged it, and
# widening the budget there would have been a change made to satisfy a bad assertion.
BAD=$(REPO="$REPO_DIR" python3 - <<'PY'
import os, re
budget = 400
bad = []
for name in ('safety.sh', 'git-safety.sh', 'harness-tamper-guard.sh'):
    path = os.path.join(os.environ['REPO'], 'hooks', name)
    for i, line in enumerate(open(path), 1):
        # `safe_cmd="${safe_cmd:0:N}"` — the slice that feeds the ledger printf.
        m = re.search(r'safe_cmd:0:(\d+)', line)
        if m and int(m.group(1)) < budget:
            bad.append(f'{name}:{i}={m.group(1)}')
        # `printf ... %.Ns ... >> <ledger>` on one line.
        if 'blocked-commands' in line or '"$_BLK"' in line or '"$_al"' in line:
            for n in re.findall(r'%\.(\d+)s', line):
                if int(n) < budget:
                    bad.append(f'{name}:{i}={n}')
print(' '.join(bad))
PY
)
[ -z "$BAD" ] && pass || fail "writer(s) below the 400-char budget: $BAD"

report
