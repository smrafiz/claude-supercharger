#!/usr/bin/env bash
# Claude Supercharger — End-to-End Integration Test
# Tests: crash recovery, adaptive economy, thinking budget, rate-limit advisor, normal cleanup

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

result() {
  local label="$1" status="$2" detail="${3:-}"
  if [ "$status" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    RESULTS+=("  ${GREEN}PASS${NC}  $label")
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    RESULTS+=("  ${RED}FAIL${NC}  $label${detail:+  ($detail)}")
  fi
}

hr() { printf "${CYAN}%s${NC}\n" "──────────────────────────────────────────────"; }

# ─── SECTION 1: Crash Recovery ──────────────────────────────────────────────
hr
echo -e "${BOLD}1. Crash Recovery Simulation${NC}"

PROJ=$(mktemp -d)
FAKE_HOME=$(mktemp -d)
mkdir -p "$PROJ/.claude"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email "test@test.com"
git -C "$PROJ" config user.name "Test"
# Make some real files so git tracks them
touch "$PROJ/src/app.ts" "$PROJ/src/auth.ts" 2>/dev/null || true
mkdir -p "$PROJ/src"
for f in src/app.ts src/auth.ts src/db.ts src/api.ts src/utils.ts; do
  mkdir -p "$PROJ/$(dirname $f)"
  echo "// $f" > "$PROJ/$f"
done
(cd "$PROJ" && git -c commit.gpgsign=false commit --allow-empty -q -m "chore: init")
# Leave files untracked so git ls-files --others picks them up

SCOPE="$FAKE_HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE"
SESSION_ID="crash-test"
FILES=(src/app.ts src/auth.ts src/db.ts src/api.ts src/utils.ts)

# Simulate 5 Write tool calls
for fp in "${FILES[@]}"; do
  INPUT="{\"session_id\":\"$SESSION_ID\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/$fp\"},\"cwd\":\"$PROJ\"}"
  (export HOME="$FAKE_HOME"; printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/session-checkpoint.sh") 2>/dev/null
done

CKPT_FILE="$SCOPE/.checkpoint-$SESSION_ID"

if [ -f "$CKPT_FILE" ]; then
  result "checkpoint file exists after 5 Write calls" PASS
else
  result "checkpoint file exists after 5 Write calls" FAIL "not found at $CKPT_FILE"
fi

CKPT_CONTENT=$(cat "$CKPT_FILE" 2>/dev/null || echo "")

if echo "$CKPT_CONTENT" | grep -q "^ckpt:"; then
  result "checkpoint has 'ckpt:' prefix" PASS
else
  result "checkpoint has 'ckpt:' prefix" FAIL "content: $CKPT_CONTENT"
fi

if echo "$CKPT_CONTENT" | grep -q "branch:"; then
  result "checkpoint contains branch" PASS
else
  result "checkpoint contains branch" FAIL "content: $CKPT_CONTENT"
fi

if echo "$CKPT_CONTENT" | grep -q "files:"; then
  result "checkpoint contains files list" PASS
else
  result "checkpoint contains files list" FAIL "content: $CKPT_CONTENT"
fi

CKPT_LEN=${#CKPT_CONTENT}
if [ "$CKPT_LEN" -le 500 ]; then
  result "checkpoint ≤500 chars (${CKPT_LEN})" PASS
else
  result "checkpoint ≤500 chars" FAIL "got ${CKPT_LEN} chars"
fi

# Simulate crash — skip session-memory-write.sh
# Simulate new session start with cwd=$PROJ, no memory file
INPUT_START="{\"cwd\":\"$PROJ\"}"
INJECT_OUT=$(export HOME="$FAKE_HOME"; printf '%s' "$INPUT_START" | bash "$REPO_DIR/hooks/session-memory-inject.sh" 2>/dev/null)
if echo "$INJECT_OUT" | grep -q "RECOVERY"; then
  result "session-memory-inject emits [RECOVERY] after crash" PASS
else
  result "session-memory-inject emits [RECOVERY] after crash" FAIL "output: $INJECT_OUT"
fi
echo "  Recovery output: $(echo "$INJECT_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('systemMessage','?'))" 2>/dev/null || echo "$INJECT_OUT")"

rm -rf "$PROJ" "$FAKE_HOME"

# ─── SECTION 2: Adaptive Economy ────────────────────────────────────────────
hr
echo -e "${BOLD}2. Adaptive Economy Auto-Switch Simulation${NC}"

FAKE_HOME2=$(mktemp -d)
SCOPE2="$FAKE_HOME2/.claude/supercharger/scope"
mkdir -p "$SCOPE2"
printf '%s' "standard" > "$SCOPE2/.economy-tier"

echo "  Context window progression:"
SWITCH_TO_LEAN=""
SWITCH_TO_MINIMAL=""
PREV_TIER="standard"

for pct in 40 45 50 55 60 65 70 75 80 85; do
  INPUT="{\"context_window\":{\"used_percentage\":$pct},\"cwd\":\"/tmp\"}"
  (export HOME="$FAKE_HOME2"; printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/adaptive-economy.sh") 2>/dev/null
  TIER=$(cat "$SCOPE2/.economy-tier" 2>/dev/null | tr -d '[:space:]')
  echo "    pct=${pct}% → tier=${TIER}"
  if [ "$PREV_TIER" = "standard" ] && [ "$TIER" = "lean" ] && [ -z "$SWITCH_TO_LEAN" ]; then
    SWITCH_TO_LEAN="$pct"
  fi
  if [ "$PREV_TIER" = "lean" ] && [ "$TIER" = "minimal" ] && [ -z "$SWITCH_TO_MINIMAL" ]; then
    SWITCH_TO_MINIMAL="$pct"
  fi
  PREV_TIER="$TIER"
done

if [ -n "$SWITCH_TO_LEAN" ] && [ "$SWITCH_TO_LEAN" -ge 65 ] && [ "$SWITCH_TO_LEAN" -le 75 ]; then
  result "standard→lean switch around 70% (at ${SWITCH_TO_LEAN}%)" PASS
else
  result "standard→lean switch around 70%" FAIL "switched at: ${SWITCH_TO_LEAN:-never}"
fi

if [ -n "$SWITCH_TO_MINIMAL" ] && [ "$SWITCH_TO_MINIMAL" -ge 75 ] && [ "$SWITCH_TO_MINIMAL" -le 85 ]; then
  result "lean→minimal switch around 80% (at ${SWITCH_TO_MINIMAL}%)" PASS
else
  result "lean→minimal switch around 80%" FAIL "switched at: ${SWITCH_TO_MINIMAL:-never}"
fi

if [ -f "$SCOPE2/.economy-history.jsonl" ]; then
  HISTORY_LINES=$(wc -l < "$SCOPE2/.economy-history.jsonl" | tr -d ' ')
  result ".economy-history.jsonl created (${HISTORY_LINES} entries)" PASS
else
  result ".economy-history.jsonl created" FAIL "file not found"
fi

rm -rf "$FAKE_HOME2"

# ─── SECTION 3: Thinking Budget Classification ───────────────────────────────
hr
echo -e "${BOLD}3. Thinking Budget Classification${NC}"

FAKE_HOME3=$(mktemp -d)
mkdir -p "$FAKE_HOME3/.claude/supercharger/scope"

# Use indexed arrays (bash 3 compatible)
PROMPTS=(
  "yes"
  "show me the file"
  "run the tests"
  "add a loading spinner to the button component"
  "fix the null pointer in auth.ts line 42"
  "design a microservices architecture for our payment system with event sourcing"
  "investigate why the CI pipeline is failing intermittently"
  "refactor the entire authentication module to use OAuth2"
)
EXPECTATIONS=(
  "low"
  "low"
  "low"
  "medium"
  "medium_or_high"
  "high"
  "high"
  "high"
)

for i in 0 1 2 3 4 5 6 7; do
  PROMPT="${PROMPTS[$i]}"
  EXPECTED="${EXPECTATIONS[$i]}"
  # Escape prompt for JSON
  PROMPT_ESCAPED=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$PROMPT" 2>/dev/null | tr -d '"')
  INPUT="{\"prompt\":\"$PROMPT_ESCAPED\",\"session_id\":\"think-test\"}"
  OUTPUT=$(export HOME="$FAKE_HOME3"; printf '%s' "$INPUT" | bash "$REPO_DIR/hooks/thinking-budget.sh" 2>/dev/null)

  HAS_THINK=false; IS_LOW=false; IS_HIGH=false; IS_MEDIUM_NO_OUTPUT=false
  echo "$OUTPUT" | grep -qi "THINK" && HAS_THINK=true
  echo "$OUTPUT" | grep -qiE "trivial|minimal|directly" && IS_LOW=true
  echo "$OUTPUT" | grep -qiE "complex|thorough" && IS_HIGH=true
  [ -z "$OUTPUT" ] && IS_MEDIUM_NO_OUTPUT=true

  LABEL="'${PROMPT}' → expected:${EXPECTED}"

  case "$EXPECTED" in
    low)
      if $HAS_THINK && $IS_LOW; then
        result "$LABEL" PASS
      else
        result "$LABEL" FAIL "got: ${OUTPUT:-empty}"
      fi
      ;;
    high)
      if $HAS_THINK && $IS_HIGH; then
        result "$LABEL" PASS
      else
        result "$LABEL" FAIL "got: ${OUTPUT:-empty}"
      fi
      ;;
    medium)
      if $IS_MEDIUM_NO_OUTPUT; then
        result "$LABEL" PASS
      else
        result "$LABEL" FAIL "expected no output (medium), got: ${OUTPUT:-empty}"
      fi
      ;;
    medium_or_high)
      if $IS_MEDIUM_NO_OUTPUT || ($HAS_THINK && $IS_HIGH); then
        result "$LABEL" PASS
      else
        result "$LABEL" FAIL "got: ${OUTPUT:-empty}"
      fi
      ;;
  esac
done

rm -rf "$FAKE_HOME3"

# ─── SECTION 4: Rate-Limit Advisor ──────────────────────────────────────────
hr
echo -e "${BOLD}4. Rate-Limit Advisor Simulation${NC}"

FAKE_HOME4=$(mktemp -d)
SCOPE4="$FAKE_HOME4/.claude/supercharger/scope"
mkdir -p "$SCOPE4"

TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")

# Scenario A: 70% used, session started 10min ago → burn=7%/min → ~4.3m left → WARN
printf '{"total_usd":0.5,"turn_count":5,"avg_per_turn":0.1,"first_updated":"%s","last_updated":"%s"}' \
  "$TEN_MIN_AGO" "$TEN_MIN_AGO" > "$SCOPE4/.session-cost"

PAYLOAD='{"rate_limits":{"five_hour":{"used_percentage":70}}}'
OUTPUT_A=$(export HOME="$FAKE_HOME4"; printf '%s' "$PAYLOAD" | bash "$REPO_DIR/hooks/rate-limit-advisor.sh" 2>/dev/null)

if echo "$OUTPUT_A" | grep -q "RATE"; then
  result "warns at 70% used (burn ~7%/min, ~4.3m to exhaust)" PASS
  echo "  Output: $(echo "$OUTPUT_A" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext','?'))" 2>/dev/null || echo "$OUTPUT_A" | head -1)"
else
  result "warns at 70% used (burn ~7%/min, ~4.3m to exhaust)" FAIL "no [RATE] in: $OUTPUT_A"
fi

if echo "$OUTPUT_A" | grep -qE "[0-9]+[[:space:]]*(min|m)"; then
  result "output contains minute estimate" PASS
else
  result "output contains minute estimate" FAIL "output: $OUTPUT_A"
fi

# Scenario B: 20% used in 10min → burn=2%/min → ~40m left → NO warn
FAKE_HOME4B=$(mktemp -d)
SCOPE4B="$FAKE_HOME4B/.claude/supercharger/scope"
mkdir -p "$SCOPE4B"
printf '{"total_usd":0.5,"turn_count":5,"avg_per_turn":0.1,"first_updated":"%s","last_updated":"%s"}' \
  "$TEN_MIN_AGO" "$TEN_MIN_AGO" > "$SCOPE4B/.session-cost"

PAYLOAD2='{"rate_limits":{"five_hour":{"used_percentage":20}}}'
OUTPUT_B=$(export HOME="$FAKE_HOME4B"; printf '%s' "$PAYLOAD2" | bash "$REPO_DIR/hooks/rate-limit-advisor.sh" 2>/dev/null)

if ! echo "$OUTPUT_B" | grep -q "RATE"; then
  result "silent at 20% used (burn ~2%/min, ~40m to exhaust)" PASS
else
  result "silent at 20% used" FAIL "unexpected output: $OUTPUT_B"
fi

rm -rf "$FAKE_HOME4" "$FAKE_HOME4B"

# ─── SECTION 5: Normal Session End Cleanup ──────────────────────────────────
hr
echo -e "${BOLD}5. Normal Session End Cleanup${NC}"

PROJ5=$(mktemp -d)
FAKE_HOME5=$(mktemp -d)
mkdir -p "$PROJ5/.claude"
SCOPE5="$FAKE_HOME5/.claude/supercharger/scope"
mkdir -p "$SCOPE5"
git -C "$PROJ5" init -q
git -C "$PROJ5" config user.email "test@test.com"
git -C "$PROJ5" config user.name "Test"
(cd "$PROJ5" && git -c commit.gpgsign=false commit --allow-empty -q -m "chore: init")

# Create a checkpoint file (simulating a crash-left checkpoint)
CKPT5="$SCOPE5/.checkpoint-cleanup-test"
printf '%s' "ckpt:2026-04-22T10:00Z branch:main files:src/app.ts" > "$CKPT5"
result "checkpoint file present before session end" "$([ -f "$CKPT5" ] && echo PASS || echo FAIL)"

# Run session-memory-write.sh — writes memory and deletes checkpoints
(cd "$PROJ5" && export HOME="$FAKE_HOME5"; bash "$REPO_DIR/hooks/session-memory-write.sh") 2>/dev/null

MEMORY5="$PROJ5/.claude/supercharger-memory.md"
if [ -f "$MEMORY5" ]; then
  result "session-memory-write.sh created memory file" PASS
  echo "  Memory content: $(cat "$MEMORY5")"
else
  result "session-memory-write.sh created memory file" FAIL "not found: $MEMORY5"
fi

# Verify checkpoint cleaned up
if [ ! -f "$CKPT5" ]; then
  result "checkpoint deleted after normal session end" PASS
else
  result "checkpoint deleted after normal session end" FAIL "still exists: $CKPT5"
fi

# Verify next session start uses memory, not RECOVERY
INPUT5="{\"cwd\":\"$PROJ5\"}"
INJECT5_OUT=$(export HOME="$FAKE_HOME5"; printf '%s' "$INPUT5" | bash "$REPO_DIR/hooks/session-memory-inject.sh" 2>/dev/null)
if ! echo "$INJECT5_OUT" | grep -q "RECOVERY"; then
  result "next session inject uses memory file (not RECOVERY)" PASS
else
  result "next session inject uses memory file (not RECOVERY)" FAIL "got: $INJECT5_OUT"
fi

rm -rf "$PROJ5" "$FAKE_HOME5"

# ─── SUMMARY ────────────────────────────────────────────────────────────────
hr
echo -e "${BOLD}RESULTS${NC}"
for r in "${RESULTS[@]}"; do
  echo -e "$r"
done
hr
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo -e "  Total: ${BOLD}$TOTAL${NC}  ${GREEN}$PASS_COUNT passed${NC}  ${RED}$FAIL_COUNT failed${NC}"
hr

[ "$FAIL_COUNT" -eq 0 ]
