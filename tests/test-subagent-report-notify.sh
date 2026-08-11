#!/usr/bin/env bash
# Tests for v2.7.4 subagent-report-notify.sh — blocking SubagentStop hook that
# points the parent at the recovered report when the subagent's final message
# is a degraded stub (CC return-channel bug #54323).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

H="$REPO_DIR/hooks/subagent-report-notify.sh"

echo "=== Subagent Report Notify Tests (v2.7.4) ==="

export SUPERCHARGER_NO_DEDUP=1

emit() { # stdin JSON -> 1 if it injected the report pointer, else 0
  grep -c "SUBAGENT REPORT" 2>/dev/null
}

for stub in "Ready." "Standing by." "[Agent stopped]" "Complete." "[No user message.]" "Done." "Acknowledged."; do
  begin_test "notify: degraded stub \"$stub\" points parent to report"
  n=$(echo "{\"agent_id\":\"a$RANDOM\",\"agent_name\":\"Marie\",\"last_assistant_message\":\"$stub\",\"session_id\":\"s$RANDOM\"}" | bash "$H" 2>/dev/null | emit)
  [ "$n" -ge 1 ] && pass || fail "expected report pointer for stub '$stub'"
done

begin_test "notify: empty final message is treated as degraded"
n=$(echo '{"agent_id":"aE","agent_name":"x","last_assistant_message":"","session_id":"sE"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -ge 1 ] && pass || fail "expected pointer for empty final"

begin_test "notify: substantive final message stays silent"
n=$(echo '{"agent_id":"aF1","agent_name":"x","last_assistant_message":"Found 3 bugs in src/app.ts:42 with repro steps and a fix.","session_id":"sF1"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -eq 0 ] && pass || fail "expected silence on full final"

begin_test "notify: short but substantive (has path) stays silent"
n=$(echo '{"agent_id":"aF2","agent_name":"x","last_assistant_message":"see src/x.ts:10","session_id":"sF2"}' | bash "$H" 2>/dev/null | emit)
[ "$n" -eq 0 ] && pass || fail "expected silence when final has a path reference"

begin_test "notify: missing agent_id exits silently (rc 0)"
echo '{"last_assistant_message":"Ready."}' | bash "$H" >/dev/null 2>&1
[ "$?" -eq 0 ] && pass || fail "expected rc 0 with no agent_id"

begin_test "notify: message names the read command and the report path"
out=$(echo '{"agent_id":"aCMD","agent_name":"Sherlock","last_assistant_message":"Ready.","session_id":"sCMD"}' | bash "$H" 2>/dev/null)
echo "$out" | grep -q "subagent-report.sh aCMD" && echo "$out" | grep -q "subagent-reports/aCMD.md" \
  && pass || fail "expected both the read command and the report path in the pointer"

# v2.26.55: this assertion used to be `additionalContext AND NOT systemMessage`.
# That encoded a decision that turned out to be the bug: the two channels are
# complementary, not exclusive — additionalContext reaches CLAUDE, systemMessage
# reaches the USER (v2.7.31). Emitting only the model channel meant a person
# watching a subagent return "Ready." saw nothing, reported twice from the field.
# The old objection (systemMessage may replace the subagent's terminal output)
# is the desired behaviour here, because this hook only fires when that output
# is a stub worth replacing.
begin_test "notify: emits BOTH channels — model and user"
out=$(echo '{"agent_id":"aAC","agent_name":"x","last_assistant_message":"Ready.","session_id":"sAC"}' | bash "$H" 2>/dev/null)
echo "$out" | grep -q '"additionalContext"' && echo "$out" | grep -q '"systemMessage"' \
  && pass || fail "expected both channels; got: $(printf '%s' "$out" | head -c 120)"

# Dedup is a real feature — verify a second identical call is suppressed.
begin_test "notify: dedup suppresses a repeated pointer in the same session"
unset SUPERCHARGER_NO_DEDUP
rm -f "$HOME/.claude/supercharger/scope/.dedup-sDUP-subagent-report-notify"
J='{"agent_id":"aDUP","agent_name":"x","last_assistant_message":"Ready.","session_id":"sDUP"}'
first=$(echo "$J" | bash "$H" 2>/dev/null | emit)
second=$(echo "$J" | bash "$H" 2>/dev/null | emit)
rm -f "$HOME/.claude/supercharger/scope/.dedup-sDUP-subagent-report-notify"
export SUPERCHARGER_NO_DEDUP=1
[ "$first" -ge 1 ] && [ "$second" -eq 0 ] && pass || fail "expected first=emit second=suppressed (got $first/$second)"

# v2.19.1: when the recovered report is already on disk, INLINE its tail (the
# findings) into the pointer so the parent gets them without a recovery command.
begin_test "notify: inlines recovered findings when the report is on disk"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
printf '## Block 1\nscratch\n\n## Block N\nUNIQUE_FINDINGS_MARKER: agent-router KILL, context-advisor OPTIMIZE\n' > "$_NST/scope/subagent-reports/inl1.md"
_OUT=$(echo '{"agent_id":"inl1","agent_name":"Critic","last_assistant_message":"Complete.","session_id":"zi1"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" bash "$H" 2>/dev/null)
_CTX=$(printf '%s' "$_OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || echo "")
echo "$_CTX" | grep -q 'UNIQUE_FINDINGS_MARKER' && pass || fail "findings not inlined: ${_CTX:0:80}"
rm -rf "$_NST"

begin_test "notify: falls back to a pointer when the report is not on disk yet"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
_OUT=$(echo '{"agent_id":"inl2","agent_name":"x","last_assistant_message":"Done.","session_id":"zi2"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" bash "$H" 2>/dev/null)
{ echo "$_OUT" | grep -q 'SUBAGENT REPORT' && echo "$_OUT" | grep -q 'retry the command once'; } && pass \
  || fail "expected pointer+retry fallback when report absent"
rm -rf "$_NST"

begin_test "notify: inline respects the cap (large report → bounded, tail kept)"
_NST=$(mktemp -d); mkdir -p "$_NST/scope/subagent-reports"
python3 -c 'print("PAD "*400 + "TAILMARK_END")' > "$_NST/scope/subagent-reports/inl3.md"
_OUT=$(echo '{"agent_id":"inl3","last_assistant_message":"Complete.","session_id":"zi3"}' \
  | SUPERCHARGER_STATE="$_NST" SUPERCHARGER_HOME="$REPO_DIR" SUPERCHARGER_SUBAGENT_INLINE_CAP=300 bash "$H" 2>/dev/null)
_CTX=$(printf '%s' "$_OUT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null || echo "")
{ echo "$_CTX" | grep -q 'TAILMARK_END' && [ "$(printf '%s' "$_CTX" | wc -c)" -lt 900 ]; } && pass \
  || fail "cap not respected or tail missed (len=$(printf '%s' "$_CTX" | wc -c))"
rm -rf "$_NST"

# --- durable record (v2.26.54) ------------------------------------------------
# Reported twice from the field: the report WAS recovered to disk and the parent
# still went and read the files itself — the behaviour you would see if the
# additionalContext pointer never arrived. Whether Claude Code delivers
# additionalContext from a SubagentStop hook is unconfirmed, so this hook no
# longer relies on it alone:
#   - `/why` reads .subagent-report-<sid>, a channel that cannot be discarded
#   - an entry proves the hook FIRED, which separates "did not run" from
#     "ran and the context was dropped" — previously indistinguishable
rec() { # state_dir, sid -> file contents
  cat "$1/scope/.subagent-report-$2" 2>/dev/null || true
}

begin_test "record: a degraded final writes a pointer line"
RST=$(mktemp -d); mkdir -p "$RST/scope/subagent-reports"
printf '%s' '{"agent_id":"recA","agent_name":"Translator","last_assistant_message":"Ready.","session_id":"rs1","cwd":"."}' \
  | SUPERCHARGER_STATE="$RST" bash "$H" >/dev/null 2>&1
rec "$RST" rs1 | grep -q 'recA' && rec "$RST" rs1 | grep -q 'subagent-reports/recA.md' && pass \
  || fail "no pointer recorded: $(rec "$RST" rs1)"

begin_test "record: the line carries a timestamp and the agent name"
rec "$RST" rs1 | grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] Translator' && pass \
  || fail "line shape wrong: $(rec "$RST" rs1)"

begin_test "record: written even on the DEDUPED second firing"
# The repeat is precisely the evidence that would otherwise be missing, so the
# record must be written before the dedup exit.
SUPERCHARGER_NO_DEDUP=0 printf '%s' '{"agent_id":"recA","agent_name":"Translator","last_assistant_message":"Ready.","session_id":"rs1","cwd":"."}' \
  | SUPERCHARGER_STATE="$RST" bash "$H" >/dev/null 2>&1
[ "$(rec "$RST" rs1 | wc -l | tr -d ' ')" -ge 2 ] && pass \
  || fail "dedup swallowed the record — the firing becomes invisible"

begin_test "record: a HEALTHY final records nothing"
printf '%s' '{"agent_id":"recB","agent_name":"Good","last_assistant_message":"I reviewed src/auth.ts:44 and found three issues worth fixing before release.","session_id":"rs1","cwd":"."}' \
  | SUPERCHARGER_STATE="$RST" bash "$H" >/dev/null 2>&1
rec "$RST" rs1 | grep -q 'recB' && fail "recorded a healthy agent — /why would report a non-event" || pass

begin_test "record: per-session, never shared"
printf '%s' '{"agent_id":"recC","agent_name":"Other","last_assistant_message":"Done.","session_id":"rs2","cwd":"."}' \
  | SUPERCHARGER_STATE="$RST" bash "$H" >/dev/null 2>&1
rec "$RST" rs1 | grep -q 'recC' && fail "session rs2 leaked into rs1" || pass

begin_test "record: bounded so a fan-out cannot grow it without limit"
python3 -c "
import os, sys
p = os.path.join(sys.argv[1],'scope','.subagent-report-rs1')
open(p,'w').write('\n'.join('[2026-01-01 00:00] filler %d' % i for i in range(400)) + '\n')" "$RST"
printf '%s' '{"agent_id":"recD","agent_name":"N","last_assistant_message":"Ready.","session_id":"rs1","cwd":"."}' \
  | SUPERCHARGER_STATE="$RST" bash "$H" >/dev/null 2>&1
N=$(rec "$RST" rs1 | wc -l | tr -d ' ')
[ "$N" -le 200 ] && pass || fail "grew to $N lines unbounded"
rm -rf "$RST"

begin_test "record: /why knows to read it"
grep -q 'subagent-report' "$REPO_DIR/configs/commands/why.md" && pass \
  || fail "why.md does not read the subagent-report file"

begin_test "record: the generated command carries it (commands/ is generated)"
grep -q 'subagent-report' "$REPO_DIR/commands/why.md" && pass \
  || fail "run tools/gen-plugin-commands.sh — config and generated copy have drifted"

begin_test "record: /why frames it as recovered work, not a failure"
grep -qi 'not a block\|nothing failed' "$REPO_DIR/configs/commands/why.md" && pass \
  || fail "why.md should say the work completed and only the reply was lost"

# --- both channels (v2.26.55) -------------------------------------------------
# additionalContext reaches CLAUDE; systemMessage reaches the USER (established
# v2.7.31 in session-memory-inject). Emitting only additionalContext meant the
# findings were available to the model and INVISIBLE to the person watching a
# subagent return "Ready." — which is exactly what was reported twice.
CST=$(mktemp -d); mkdir -p "$CST/scope/subagent-reports"
printf '# findings\nTranslated into 6 locales; MARKER_FINDINGS present.\n' > "$CST/scope/subagent-reports/ch1.md"
COUT=$(printf '%s' '{"agent_id":"ch1","agent_name":"Translator","last_assistant_message":"Ready.","session_id":"cs1","cwd":"."}' \
  | SUPERCHARGER_STATE="$CST" bash "$H" 2>/dev/null)

begin_test "channels: the emitted JSON is valid"
printf '%s' "$COUT" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null && pass \
  || fail "invalid JSON — CC would discard the whole payload: $(printf '%s' "$COUT" | head -c 120)"

begin_test "channels: systemMessage is present (the USER-facing one)"
printf '%s' "$COUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("systemMessage") else 1)' 2>/dev/null \
  && pass || fail "no systemMessage — the user sees only the stub, which is the reported bug"

begin_test "channels: additionalContext is still present (the MODEL-facing one)"
printf '%s' "$COUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d["hookSpecificOutput"].get("additionalContext") else 1)' 2>/dev/null \
  && pass || fail "additionalContext lost — the parent can no longer act on the findings"

begin_test "channels: the user-facing copy carries the FINDINGS, not just a path"
printf '%s' "$COUT" | python3 -c '
import sys, json
d = json.load(sys.stdin)
sys.exit(0 if "MARKER_FINDINGS" in d.get("systemMessage","") else 1)' 2>/dev/null \
  && pass || fail "systemMessage has no findings — a pointer asks the reader to run a command to see existing work"
rm -rf "$CST"

begin_test "channels: a HEALTHY subagent emits nothing at all"
CST2=$(mktemp -d); mkdir -p "$CST2/scope/subagent-reports"
GOUT=$(printf '%s' '{"agent_id":"ok1","agent_name":"Good","last_assistant_message":"Reviewed src/auth.ts:44 and found three issues worth fixing.","session_id":"cs2","cwd":"."}' \
  | SUPERCHARGER_STATE="$CST2" bash "$H" 2>/dev/null)
rm -rf "$CST2"
[ -z "$GOUT" ] && pass || fail "replaced a healthy subagent's output: $GOUT"

report
