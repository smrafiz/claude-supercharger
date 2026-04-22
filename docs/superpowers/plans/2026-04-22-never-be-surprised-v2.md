# Supercharger v2 "Never Be Surprised" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 10 features across 3 waves that make every Claude Code session predictable and controllable — cost, context, cache, performance, state — without user configuration.

**Architecture:** All features are shell hooks or CLI tools following existing patterns: Bash 3.2+, Python 3 for JSON parsing, `lib-suppress.sh` for output control, scope files for state, `lib/hooks.sh` for registration. Subcommand pattern (like `scope-guard.sh check|snapshot|clear`) for hooks with multiple event registrations.

**Tech Stack:** Bash, Python 3, jq (with Python fallback), JSONL for logs, JSON for state files.

**Spec:** `docs/superpowers/specs/2026-04-22-never-be-surprised-v2-design.md`

---

## Shared Infrastructure

### Task 1: Timing Instrumentation in `lib-suppress.sh`

**Files:**
- Modify: `hooks/lib-suppress.sh`
- Test: `tests/test-lib-suppress-timing.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-lib-suppress-timing.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

LIB_SUPPRESS="$REPO_DIR/hooks/lib-suppress.sh"

echo "=== lib-suppress Timing Tests ==="

begin_test "timing: HOOK_START_MS is set after sourcing lib-suppress"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
(
  HOOKS_DIR="$REPO_DIR/hooks"
  source "$LIB_SUPPRESS"
  init_hook_suppress "/tmp"
  if [ -n "$HOOK_START_MS" ] && [ "$HOOK_START_MS" -gt 0 ] 2>/dev/null; then
    exit 0
  else
    exit 1
  fi
)
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "timing: HOOK_START_MS is numeric"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
(
  HOOKS_DIR="$REPO_DIR/hooks"
  source "$LIB_SUPPRESS"
  init_hook_suppress "/tmp"
  if [[ "$HOOK_START_MS" =~ ^[0-9]+$ ]]; then
    exit 0
  else
    exit 1
  fi
)
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "timing: HOOK_START_MS is a reasonable epoch ms"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
(
  HOOKS_DIR="$REPO_DIR/hooks"
  source "$LIB_SUPPRESS"
  init_hook_suppress "/tmp"
  # Should be at least year 2020 in epoch ms
  if [ "$HOOK_START_MS" -gt 1577836800000 ] 2>/dev/null; then
    exit 0
  else
    exit 1
  fi
)
assert_exit_code 0 $? && pass
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-lib-suppress-timing.sh`
Expected: FAIL — `HOOK_START_MS` not set yet.

- [ ] **Step 3: Add timing to `lib-suppress.sh`**

Add to `init_hook_suppress()` function, after the existing debug-hooks logic:

```bash
  # Timing instrumentation for hook-perf.sh profiler
  if command -v python3 >/dev/null 2>&1; then
    HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
  else
    HOOK_START_MS=0
  fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-lib-suppress-timing.sh`
Expected: All 3 PASS.

- [ ] **Step 5: Run full test suite for regression**

Run: `bash tests/run.sh`
Expected: All existing tests still pass (293+).

- [ ] **Step 6: Commit**

```bash
git add hooks/lib-suppress.sh tests/test-lib-suppress-timing.sh
git commit -m "feat: add timing instrumentation to lib-suppress.sh for hook profiling"
```

---

## Wave 1: Cost Shield

### Task 2: Budget Cap — Cost Accumulator (`budget-cap.sh` PostToolUse)

**Files:**
- Create: `hooks/budget-cap.sh`
- Test: `tests/test-budget-cap.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-budget-cap.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/budget-cap.sh"

echo "=== Budget Cap Tests ==="

# --- Accumulator mode (no subcommand) ---

begin_test "budget-cap: accumulates cost from PostToolUse usage data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"session_id":"test1","tool_name":"Bash","tool_response":{"usage":{"input_tokens":1000,"cache_creation_input_tokens":500,"cache_read_input_tokens":2000,"output_tokens":200}}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
assert_file_exists "$SCOPE_DIR/.session-cost" && {
  # input: 1000 * 3.00/1M = 0.003
  # cache_write: 500 * 3.75/1M = 0.001875
  # cache_read: 2000 * 0.30/1M = 0.0006
  # output: 200 * 15.00/1M = 0.003
  # total ≈ 0.008475
  TOTAL=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['total_usd'])" 2>/dev/null)
  if python3 -c "assert abs($TOTAL - 0.008475) < 0.001" 2>/dev/null; then
    pass
  else
    fail "expected ~0.008475, got $TOTAL"
  fi
}
teardown_test_home

begin_test "budget-cap: accumulates across multiple calls"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"session_id":"test2","tool_name":"Bash","tool_response":{"usage":{"input_tokens":1000,"output_tokens":100}}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
TURN_COUNT=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['turn_count'])" 2>/dev/null)
if [ "$TURN_COUNT" = "3" ]; then
  pass
else
  fail "expected turn_count=3, got $TURN_COUNT"
fi
teardown_test_home

begin_test "budget-cap: computes avg_per_turn"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"session_id":"test3","tool_name":"Bash","tool_response":{"usage":{"input_tokens":10000,"output_tokens":1000}}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
AVG=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['avg_per_turn'])" 2>/dev/null)
TOTAL=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['total_usd'])" 2>/dev/null)
EXPECTED_AVG=$(python3 -c "print(round($TOTAL / 2, 6))" 2>/dev/null)
if python3 -c "assert abs($AVG - $EXPECTED_AVG) < 0.0001" 2>/dev/null; then
  pass
else
  fail "expected avg=$EXPECTED_AVG, got $AVG"
fi
teardown_test_home

begin_test "budget-cap: handles missing usage data gracefully"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"session_id":"test4","tool_name":"Read","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE && pass
teardown_test_home

begin_test "budget-cap: atomic write via tmp file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"session_id":"test5","tool_name":"Bash","tool_response":{"usage":{"input_tokens":1000,"output_tokens":100}}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
assert_file_not_exists "$SCOPE_DIR/.session-cost.tmp" && pass
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-budget-cap.sh`
Expected: FAIL — `hooks/budget-cap.sh` does not exist.

- [ ] **Step 3: Implement `budget-cap.sh`**

Create `hooks/budget-cap.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Budget Cap
# Modes:
#   (no arg)  — PostToolUse: accumulate session cost from token usage
#   check     — PreToolUse: check accumulated cost against cap, warn or block
#
# State: $SCOPE_DIR/.session-cost (JSON, atomic writes)
# Config: .supercharger.json → "budget": N or SESSION_BUDGET_CAP env var

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

MODE="${1:-accumulate}"
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
COST_FILE="$SCOPE_DIR/.session-cost"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# ── accumulate (PostToolUse) ─────────────────────────────────────────────────
if [ "$MODE" = "accumulate" ]; then
  COST_JSON=$(COST_FILE="$COST_FILE" python3 -c "
import json, sys, os, time

data = json.loads(sys.stdin.read())
usage = (data.get('tool_response') or {}).get('usage') or {}

inp   = usage.get('input_tokens', 0) or 0
cw    = usage.get('cache_creation_input_tokens', 0) or 0
cr    = usage.get('cache_read_input_tokens', 0) or 0
out   = usage.get('output_tokens', 0) or 0

if inp + cw + cr + out == 0:
    sys.exit(0)

cost = (inp * 3.00 + cw * 3.75 + cr * 0.30 + out * 15.00) / 1_000_000

cost_file = os.environ['COST_FILE']
prev = {'total_usd': 0, 'turn_count': 0, 'avg_per_turn': 0, 'first_updated': '', 'last_updated': '', 'subagent_total': 0}
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            prev = json.load(f)
    except Exception:
        pass

now = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
prev['total_usd'] = round(prev['total_usd'] + cost, 6)
prev['turn_count'] = prev['turn_count'] + 1
prev['avg_per_turn'] = round(prev['total_usd'] / prev['turn_count'], 6)
if not prev.get('first_updated'):
    prev['first_updated'] = now
prev['last_updated'] = now

tmp = cost_file + '.tmp'
with open(tmp, 'w') as f:
    json.dump(prev, f)
os.rename(tmp, cost_file)
" <<< "$_INPUT" 2>/dev/null) || true

  echo "[Supercharger] budget-cap: accumulated cost" >&2
  exit 0
fi

# ── check (PreToolUse) ───────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
  [ ! -f "$COST_FILE" ] && exit 0

  # Resolve budget cap: env var > .supercharger.json > no cap
  CAP="${SESSION_BUDGET_CAP:-}"
  if [ -z "$CAP" ]; then
    # Walk up to find .supercharger.json
    SEARCH_DIR="$PROJECT_DIR"
    for _ in 1 2 3 4 5; do
      if [ -f "$SEARCH_DIR/.supercharger.json" ]; then
        CAP=$(python3 -c "
import json
with open('$SEARCH_DIR/.supercharger.json') as f:
    c = json.load(f)
print(c.get('budget', ''))
" 2>/dev/null || echo "")
        break
      fi
      PARENT=$(dirname "$SEARCH_DIR")
      [ "$PARENT" = "$SEARCH_DIR" ] && break
      SEARCH_DIR="$PARENT"
    done
  fi

  # No cap configured — pass through (tracking still runs)
  [ -z "$CAP" ] && exit 0

  RESULT=$(CAP="$CAP" COST_FILE="$COST_FILE" python3 -c "
import json, os, sys

cost_file = os.environ['COST_FILE']
cap = float(os.environ.get('CAP', '0'))

if cap <= 0:
    sys.exit(0)

try:
    with open(cost_file) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

total = data.get('total_usd', 0)
pct = (total / cap) * 100 if cap > 0 else 0

if pct >= 100:
    reason = f'Session budget of \${cap:.2f} reached (\${total:.2f} spent). Start a new session or raise the cap.'
    print(json.dumps({
        'action': 'block',
        'reason': reason
    }))
elif pct >= 80:
    msg = f'[BUDGET] \${total:.2f}/\${cap:.2f} ({pct:.0f}%). Approaching session limit.'
    print(json.dumps({
        'action': 'warn',
        'msg': msg
    }))
else:
    pass  # no output = exit 0
" 2>/dev/null) || true

  [ -z "$RESULT" ] && exit 0

  ACTION=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['action'])" 2>/dev/null || echo "")

  if [ "$ACTION" = "block" ]; then
    REASON=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['reason'])" 2>/dev/null)
    # Allow read-only tools through
    TOOL_NAME=$(printf '%s\n' "$_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    case "$TOOL_NAME" in
      Read|Glob|Grep) exit 0 ;;
    esac
    echo "[Supercharger] budget-cap: BLOCKED — $REASON" >&2
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
    exit 2
  elif [ "$ACTION" = "warn" ]; then
    MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)
    echo "[Supercharger] budget-cap: $MSG" >&2
    CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
    exit 0
  fi

  exit 0
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-budget-cap.sh`
Expected: All 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/budget-cap.sh tests/test-budget-cap.sh
git commit -m "feat: add budget-cap hook — session cost accumulator with pricing table"
```

---

### Task 3: Budget Cap — PreToolUse Blocker Tests

**Files:**
- Modify: `tests/test-budget-cap.sh`
- Modify: `hooks/budget-cap.sh` (already created)

- [ ] **Step 1: Add blocker tests to `test-budget-cap.sh`**

Append to the test file, before `report`:

```bash
# --- Blocker mode (check subcommand) ---

begin_test "budget-cap check: no cap configured = passthrough"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":10.00,"turn_count":5,"avg_per_turn":2.0,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "$INPUT" | SESSION_BUDGET_CAP="" bash "$HOOK" check >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "budget-cap check: under 80% = passthrough"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":3.00,"turn_count":5,"avg_per_turn":0.6,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
echo "$INPUT" | SESSION_BUDGET_CAP="5.00" bash "$HOOK" check >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "budget-cap check: at 80% = warn (exit 0)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":4.10,"turn_count":5,"avg_per_turn":0.82,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
OUTPUT=$(echo "$INPUT" | SESSION_BUDGET_CAP="5.00" bash "$HOOK" check 2>/dev/null)
assert_exit_code 0 $? || true
echo "$OUTPUT" | grep -q "BUDGET" && pass || fail "expected BUDGET warning"
teardown_test_home

begin_test "budget-cap check: at 100% = block (exit 2)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":5.50,"turn_count":10,"avg_per_turn":0.55,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Bash","tool_input":{"command":"npm test"}}'
echo "$INPUT" | SESSION_BUDGET_CAP="5.00" bash "$HOOK" check >/dev/null 2>&1
assert_exit_code 2 $? && pass
teardown_test_home

begin_test "budget-cap check: read-only tools bypass block"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":6.00,"turn_count":10,"avg_per_turn":0.6,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
echo "$INPUT" | SESSION_BUDGET_CAP="5.00" bash "$HOOK" check >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home
```

- [ ] **Step 2: Run test to verify new tests pass**

Run: `bash tests/test-budget-cap.sh`
Expected: All 10 PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/test-budget-cap.sh
git commit -m "test: add budget-cap blocker tests — warn at 80%, block at 100%, read-only bypass"
```

---

### Task 4: Cost Forecast (`cost-forecast.sh`)

**Files:**
- Create: `hooks/cost-forecast.sh`
- Test: `tests/test-cost-forecast.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-cost-forecast.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cost-forecast.sh"

echo "=== Cost Forecast Tests ==="

begin_test "cost-forecast: estimates cost for Agent tool call"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":1.90,"turn_count":10,"avg_per_turn":0.19,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Agent","tool_input":{"prompt":"Fix the auth bug"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "COST" && pass || fail "expected COST estimate"
teardown_test_home

begin_test "cost-forecast: skips when no session-cost data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"tool_name":"Agent","tool_input":{"prompt":"Fix the auth bug"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output when no cost data"
teardown_test_home

begin_test "cost-forecast: skips when avg_per_turn is 0"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":0,"turn_count":0,"avg_per_turn":0,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Agent","tool_input":{"prompt":"Fix the auth bug"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output when avg is 0"
teardown_test_home

begin_test "cost-forecast: skips when estimated cost < 0.10"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":0.01,"turn_count":10,"avg_per_turn":0.001,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
INPUT='{"tool_name":"Agent","tool_input":{"prompt":"Fix the auth bug"}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output for cheap estimate"
teardown_test_home

begin_test "cost-forecast: uses forecastTurnsPerAgent from config"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":5.00,"turn_count":10,"avg_per_turn":0.50,"last_updated":"2026-04-22T14:00:00Z"}' > "$SCOPE_DIR/.session-cost"
mkdir -p "$HOME/project"
echo '{"forecastTurnsPerAgent": 5}' > "$HOME/project/.supercharger.json"
INPUT='{"tool_name":"Agent","tool_input":{"prompt":"Fix the auth bug"},"cwd":"'"$HOME/project"'"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
# 0.50 * 5 = $2.50
echo "$OUTPUT" | grep -q "2.50" && pass || fail "expected estimate using custom turns"
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cost-forecast.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `cost-forecast.sh`**

Create `hooks/cost-forecast.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Cost Forecast
# Event: PreToolUse | Matcher: Agent
# Estimates cost before expensive agent operations.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
COST_FILE="$SCOPE_DIR/.session-cost"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

[ ! -f "$COST_FILE" ] && exit 0

RESULT=$(COST_FILE="$COST_FILE" PROJECT_DIR="$PROJECT_DIR" python3 -c "
import json, os, sys

cost_file = os.environ['COST_FILE']
project_dir = os.environ.get('PROJECT_DIR', '')

try:
    with open(cost_file) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

avg = data.get('avg_per_turn', 0)
if avg <= 0:
    sys.exit(0)

# Read forecastTurnsPerAgent from .supercharger.json
turns = 10
search = project_dir
for _ in range(5):
    cfg = os.path.join(search, '.supercharger.json')
    if os.path.isfile(cfg):
        try:
            with open(cfg) as f:
                c = json.load(f)
            turns = int(c.get('forecastTurnsPerAgent', 10))
        except Exception:
            pass
        break
    parent = os.path.dirname(search)
    if parent == search:
        break
    search = parent

estimate = round(avg * turns, 2)
if estimate < 0.10:
    sys.exit(0)

msg = f'[COST] Est. ~\${estimate:.2f} for this agent (avg \${avg:.2f}/turn × ~{turns} turns)'
print(json.dumps({'msg': msg}))
" <<< "$_INPUT" 2>/dev/null) || true

[ -z "$RESULT" ] && exit 0

MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)

echo "[Supercharger] cost-forecast: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cost-forecast.sh`
Expected: All 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/cost-forecast.sh tests/test-cost-forecast.sh
git commit -m "feat: add cost-forecast hook — estimates agent operation cost before execution"
```

---

### Task 5: Cache Health Monitor (`cache-health.sh`)

**Files:**
- Create: `hooks/cache-health.sh`
- Test: `tests/test-cache-health.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-cache-health.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/cache-health.sh"

echo "=== Cache Health Monitor Tests ==="

begin_test "cache-health: healthy cache (>70%) produces no output"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# 5 calls to build window — all healthy
for i in 1 2 3 4 5; do
  INPUT='{"tool_name":"Bash","tool_response":{"usage":{"cache_read_input_tokens":9000,"cache_creation_input_tokens":1000}}}'
  echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
done
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output for healthy cache"
teardown_test_home

begin_test "cache-health: degraded cache (<50% for 3 readings) triggers warning"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# Pre-seed counter to align with 5th-call sampling
echo "14" > "$SCOPE_DIR/.cache-health-counter"
# 3 consecutive bad readings (every 5th call)
for i in 1 2 3; do
  INPUT='{"tool_name":"Bash","tool_response":{"usage":{"cache_read_input_tokens":1000,"cache_creation_input_tokens":9000}}}'
  # Need to trigger on every 5th call
  for j in 1 2 3 4; do
    echo '{"tool_name":"Bash","tool_response":{}}' | bash "$HOOK" >/dev/null 2>&1
  done
  echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
done
# Next sample should fire the alert
for j in 1 2 3 4; do
  echo '{"tool_name":"Bash","tool_response":{}}' | bash "$HOOK" >/dev/null 2>&1
done
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "CACHE" && pass || fail "expected CACHE warning"
teardown_test_home

begin_test "cache-health: no usage data = no crash"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"tool_name":"Read","tool_response":{}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "cache-health: zero cache tokens = no crash"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"tool_name":"Bash","tool_response":{"usage":{"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-cache-health.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `cache-health.sh`**

Create `hooks/cache-health.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Cache Health Monitor
# Event: PostToolUse | Matcher: * | Flags: async
# Samples cache hit rate every 5th call. Warns when degraded.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# Sampling: only run every 5th call
COUNTER_FILE="$SCOPE_DIR/.cache-health-counter"
COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
  COUNT=${COUNT%%.*}
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
[ $((COUNT % 5)) -ne 0 ] && exit 0

RESULT=$(SCOPE_DIR="$SCOPE_DIR" python3 -c "
import json, sys, os

data = json.loads(sys.stdin.read())
usage = (data.get('tool_response') or {}).get('usage') or {}

cr = usage.get('cache_read_input_tokens', 0) or 0
cw = usage.get('cache_creation_input_tokens', 0) or 0
total = cr + cw

if total == 0:
    sys.exit(0)

hit_rate = int((cr / total) * 100)

scope = os.environ['SCOPE_DIR']
health_file = os.path.join(scope, '.cache-health')

# Read rolling window (last 5 readings)
readings = []
if os.path.isfile(health_file):
    try:
        with open(health_file) as f:
            readings = json.load(f)
    except Exception:
        readings = []

readings.append(hit_rate)
readings = readings[-5:]  # keep last 5

with open(health_file, 'w') as f:
    json.dump(readings, f)

# Alert if last 3 readings all below 50%
if len(readings) >= 3 and all(r < 50 for r in readings[-3:]):
    # Dedup: check last alert band
    dedup_file = os.path.join(scope, '.cache-health-dedup')
    band = (hit_rate // 10) * 10
    last_band = -1
    if os.path.isfile(dedup_file):
        try:
            last_band = int(open(dedup_file).read().strip())
        except Exception:
            pass
    if band == last_band:
        sys.exit(0)
    with open(dedup_file, 'w') as f:
        f.write(str(band))
    print(json.dumps({'msg': f'[CACHE] Hit rate dropped to {hit_rate}%. You may be getting re-billed for full context. Consider /compact or starting a fresh session.'}))
" <<< "$_INPUT" 2>/dev/null) || true

[ -z "$RESULT" ] && exit 0

MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)
echo "[Supercharger] cache-health: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-cache-health.sh`
Expected: All 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/cache-health.sh tests/test-cache-health.sh
git commit -m "feat: add cache-health monitor — warns when cache hit rate degrades"
```

---

### Task 6: Subagent Cost Tracker (`subagent-cost.sh`)

**Files:**
- Create: `hooks/subagent-cost.sh`
- Test: `tests/test-subagent-cost.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-subagent-cost.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/subagent-cost.sh"

echo "=== Subagent Cost Tracker Tests ==="

begin_test "subagent-cost start: creates active file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"agent_id":"agent-001","agent_name":"code-helper","session_id":"sess1"}'
echo "$INPUT" | bash "$HOOK" start >/dev/null 2>&1
assert_file_exists "$SCOPE_DIR/.subagent-active-agent-001" && pass
teardown_test_home

begin_test "subagent-cost stop: calculates cost and logs to JSONL"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# Create start record
echo "{\"agent_id\":\"agent-002\",\"name\":\"code-helper\",\"started_at\":\"2026-04-22T14:00:00Z\"}" > "$SCOPE_DIR/.subagent-active-agent-002"
INPUT='{"agent_id":"agent-002","agent_name":"code-helper","session_id":"sess1","usage":{"input_tokens":20000,"output_tokens":5000}}'
echo "$INPUT" | bash "$HOOK" stop >/dev/null 2>&1
JSONL="$SCOPE_DIR/.subagent-costs-sess1.jsonl"
assert_file_exists "$JSONL" || fail "expected JSONL file"
if grep -q "agent-002" "$JSONL" 2>/dev/null; then
  pass
else
  fail "expected agent-002 in JSONL"
fi
teardown_test_home

begin_test "subagent-cost stop: cleans up active file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "{\"agent_id\":\"agent-003\",\"name\":\"debugger\",\"started_at\":\"2026-04-22T14:00:00Z\"}" > "$SCOPE_DIR/.subagent-active-agent-003"
INPUT='{"agent_id":"agent-003","agent_name":"debugger","session_id":"sess1","usage":{"input_tokens":10000,"output_tokens":2000}}'
echo "$INPUT" | bash "$HOOK" stop >/dev/null 2>&1
assert_file_not_exists "$SCOPE_DIR/.subagent-active-agent-003" && pass
teardown_test_home

begin_test "subagent-cost stop: updates session-cost total"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo '{"total_usd":1.00,"turn_count":5,"avg_per_turn":0.20,"last_updated":"2026-04-22T14:00:00Z","subagent_total":0}' > "$SCOPE_DIR/.session-cost"
echo "{\"agent_id\":\"agent-004\",\"name\":\"researcher\",\"started_at\":\"2026-04-22T14:00:00Z\"}" > "$SCOPE_DIR/.subagent-active-agent-004"
INPUT='{"agent_id":"agent-004","agent_name":"researcher","session_id":"sess1","usage":{"input_tokens":50000,"output_tokens":10000}}'
echo "$INPUT" | bash "$HOOK" stop >/dev/null 2>&1
NEW_TOTAL=$(python3 -c "import json; print(json.load(open('$SCOPE_DIR/.session-cost'))['total_usd'])" 2>/dev/null)
if python3 -c "assert $NEW_TOTAL > 1.0" 2>/dev/null; then
  pass
else
  fail "expected total_usd > 1.0, got $NEW_TOTAL"
fi
teardown_test_home

begin_test "subagent-cost stop: injects agent summary"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "{\"agent_id\":\"agent-005\",\"name\":\"writer\",\"started_at\":\"2026-04-22T14:00:00Z\"}" > "$SCOPE_DIR/.subagent-active-agent-005"
INPUT='{"agent_id":"agent-005","agent_name":"writer","session_id":"sess1","usage":{"input_tokens":30000,"output_tokens":8000}}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" stop 2>/dev/null)
echo "$OUTPUT" | grep -q "AGENT" && pass || fail "expected [AGENT] summary"
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-subagent-cost.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `subagent-cost.sh`**

Create `hooks/subagent-cost.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Subagent Cost Tracker
# Modes:
#   start — SubagentStart: record agent start time
#   stop  — SubagentStop: calculate cost, log, inject summary, update session-cost

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

MODE="${1:-start}"
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

# ── start (SubagentStart) ───────────────────────────────────────────────────
if [ "$MODE" = "start" ]; then
  SCOPE_DIR="$SCOPE_DIR" python3 -c "
import json, sys, os, time

data = json.loads(sys.stdin.read())
agent_id = data.get('agent_id', '') or 'unknown'
name = data.get('agent_name', '') or data.get('name', '') or 'unknown'

record = {
    'agent_id': agent_id,
    'name': name,
    'started_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
}

scope = os.environ['SCOPE_DIR']
path = os.path.join(scope, f'.subagent-active-{agent_id}')
with open(path, 'w') as f:
    json.dump(record, f)
" <<< "$_INPUT" 2>/dev/null || true

  echo "[Supercharger] subagent-cost: recorded start" >&2
  exit 0
fi

# ── stop (SubagentStop) ─────────────────────────────────────────────────────
if [ "$MODE" = "stop" ]; then
  RESULT=$(SCOPE_DIR="$SCOPE_DIR" python3 -c "
import json, sys, os, time

data = json.loads(sys.stdin.read())
agent_id = data.get('agent_id', '') or 'unknown'
name = data.get('agent_name', '') or data.get('name', '') or 'unknown'
session_id = data.get('session_id', '') or 'default'
usage = data.get('usage') or {}

inp = usage.get('input_tokens', 0) or 0
out = usage.get('output_tokens', 0) or 0
cw = usage.get('cache_creation_input_tokens', 0) or 0
cr = usage.get('cache_read_input_tokens', 0) or 0

cost = (inp * 3.00 + cw * 3.75 + cr * 0.30 + out * 15.00) / 1_000_000
tokens = inp + cw + cr + out

scope = os.environ['SCOPE_DIR']

# Read start record for duration
start_file = os.path.join(scope, f'.subagent-active-{agent_id}')
duration_s = 0
if os.path.isfile(start_file):
    try:
        with open(start_file) as f:
            start = json.load(f)
        st = time.mktime(time.strptime(start['started_at'], '%Y-%m-%dT%H:%M:%SZ'))
        duration_s = int(time.time() - st)
        if not name or name == 'unknown':
            name = start.get('name', name)
    except Exception:
        pass
    os.remove(start_file)

# Append to JSONL
jsonl_path = os.path.join(scope, f'.subagent-costs-{session_id}.jsonl')
entry = {
    'agent_id': agent_id,
    'name': name,
    'cost_usd': round(cost, 6),
    'tokens': tokens,
    'duration_s': duration_s
}
with open(jsonl_path, 'a') as f:
    f.write(json.dumps(entry) + '\n')

# Update session-cost
cost_file = os.path.join(scope, '.session-cost')
if os.path.isfile(cost_file):
    try:
        with open(cost_file) as f:
            sc = json.load(f)
        sc['total_usd'] = round(sc.get('total_usd', 0) + cost, 6)
        sc['subagent_total'] = round(sc.get('subagent_total', 0) + cost, 6)
        sc['last_updated'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        tmp = cost_file + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(sc, f)
        os.rename(tmp, cost_file)
    except Exception:
        pass

# Format summary
def fmt_tokens(n):
    if n >= 1_000_000: return f'{n/1_000_000:.1f}M'
    if n >= 1_000: return f'{n/1_000:.0f}K'
    return str(n)

msg = f'[AGENT] {name} completed: ~\${cost:.2f} ({fmt_tokens(tokens)} tokens, {duration_s}s)'
print(json.dumps({'msg': msg}))
" <<< "$_INPUT" 2>/dev/null) || true

  [ -z "$RESULT" ] && exit 0

  MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)
  echo "[Supercharger] subagent-cost: $MSG" >&2

  CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
  if [ "$HOOK_SUPPRESS" = "false" ]; then
    printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"SubagentStop","additionalContext":%s}}\n' "$CONTEXT_JSON"
  fi

  exit 0
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-subagent-cost.sh`
Expected: All 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/subagent-cost.sh tests/test-subagent-cost.sh
git commit -m "feat: add subagent cost tracker — per-agent cost visibility with JSONL logging"
```

---

### Task 7: Statusline — Budget Display + Cache Coloring

**Files:**
- Modify: `hooks/statusline.sh`

- [ ] **Step 1: Add budget display to statusline line 3**

In `hooks/statusline.sh`, inside the Python block, after the rate limits section and before line 3 construction, add:

```python
 # Budget cap display
 budget_str = ''
 try:
     scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
     cost_file = os.path.join(scope, '.session-cost')
     if os.path.isfile(cost_file):
         with open(cost_file) as f:
             sc = json.load(f)
         sc_cost = sc.get('total_usd', 0)
         # Check for budget cap
         cap = float(os.environ.get('SESSION_BUDGET_CAP', '0') or '0')
         if cap > 0:
             budget_str = f' {DIM}|{RESET} {DIM}Budget:{RESET} {YELLOW}${sc_cost:.2f}/${cap:.2f}{RESET}'
 except Exception:
     budget_str = ''
```

Then update line 3 construction to include `budget_str`:

```python
 line3 = f'{DIM}Cost:{RESET} {YELLOW}{cost_fmt}{RESET} {DIM}|{RESET} {DIM}Time:{RESET} {dur_str}{budget_str}{rl_str}'
```

- [ ] **Step 2: Add cache health coloring to line 2**

In the cache display section of `statusline.sh`, update the cache color logic:

```python
 # Cache health coloring
 if cache_total == 0:
     cache_str = f'{DIM}cache: n/a{RESET}'
 elif cache_read == 0:
     cache_str = f'{DIM}cache: warming{RESET}'
 elif cache_pct < 50:
     cache_str = f'{RED}cache {cache_pct}%{RESET} {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 elif cache_pct < 70:
     cache_str = f'{YELLOW}cache {cache_pct}%{RESET} {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 elif cache_saved > 0:
     cache_str = f'cache {cache_pct}% {DIM}(~{fmt_tokens(cache_saved)} saved){RESET}'
 else:
     cache_str = f'cache {cache_pct}%'
```

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run.sh`
Expected: All tests pass. Statusline is display-only so no new test file needed — verified visually.

- [ ] **Step 4: Commit**

```bash
git add hooks/statusline.sh
git commit -m "feat: statusline — add budget display on line 3 + cache health coloring"
```

---

### Task 8: Hook Registration — Wave 1

**Files:**
- Modify: `lib/hooks.sh`

- [ ] **Step 1: Add Wave 1 hooks to `get_hooks_for_mode()`**

In `lib/hooks.sh`, add `cache-health.sh` to the **safe mode** section (after `config-scan.sh`):

```bash
  hooks+=("PostToolUse||${hooks_dir}/cache-health.sh|async")
```

Add the remaining Wave 1 hooks to the **full mode** section, after the existing `PostToolUse` entries:

```bash
    hooks+=("PostToolUse||${hooks_dir}/budget-cap.sh|async")
    hooks+=("PreToolUse||${hooks_dir}/budget-cap.sh check|")
    hooks+=("PreToolUse|Agent|${hooks_dir}/cost-forecast.sh|")
    hooks+=("SubagentStart||${hooks_dir}/subagent-cost.sh start|async")
    hooks+=("SubagentStop||${hooks_dir}/subagent-cost.sh stop|")
```

- [ ] **Step 2: Verify hook count**

Run: `bash -c 'source lib/hooks.sh; get_hooks_for_mode full true /tmp | wc -l'`
Expected: 60. Breakdown: current safe=9, full+developer=54. Adding: +1 safe (cache-health), +5 full (budget-cap×2, cost-forecast, subagent-cost×2). New total: safe=10, full+developer=60.

- [ ] **Step 3: Run install test to verify registration**

Run: `bash tests/test-install.sh`
Expected: PASS — existing tests still work.

- [ ] **Step 4: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat: register Wave 1 hooks — budget-cap, cost-forecast, cache-health, subagent-cost"
```

---

### Task 9: Wave 1 Integration — Full Suite Run

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `bash tests/run.sh`
Expected: All tests pass (existing 293 + new ~19 = ~312).

- [ ] **Step 2: Verify hook scripts are executable**

Run: `ls -la hooks/budget-cap.sh hooks/cost-forecast.sh hooks/cache-health.sh hooks/subagent-cost.sh`
Expected: All have execute permission (set via `chmod 700` in deploy).

- [ ] **Step 3: Manual smoke test — pipe sample data**

```bash
# Budget accumulator
echo '{"tool_name":"Bash","tool_response":{"usage":{"input_tokens":5000,"output_tokens":500}}}' | bash hooks/budget-cap.sh 2>&1

# Cost forecast
echo '{"total_usd":2.00,"turn_count":10,"avg_per_turn":0.20}' > ~/.claude/supercharger/scope/.session-cost
echo '{"tool_name":"Agent","tool_input":{"prompt":"Fix bug"}}' | bash hooks/cost-forecast.sh 2>&1

# Cache health
echo '{"tool_name":"Bash","tool_response":{"usage":{"cache_read_input_tokens":100,"cache_creation_input_tokens":9000}}}' | bash hooks/cache-health.sh 2>&1
```

Expected: Each produces expected stderr log + stdout JSON where applicable.

- [ ] **Step 4: Commit Wave 1 complete marker**

```bash
git add -A
git commit -m "feat: Wave 1 complete — Cost Shield (budget-cap, cost-forecast, cache-health, subagent-cost)"
```

---

## Wave 2: Smart Adaptation

### Task 10: Adaptive Economy Auto-Switch (upgrade `adaptive-economy.sh`)

**Files:**
- Modify: `hooks/adaptive-economy.sh`
- Test: `tests/test-adaptive-economy-v2.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-adaptive-economy-v2.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/adaptive-economy.sh"

echo "=== Adaptive Economy v2 Tests ==="

begin_test "adaptive-economy: auto-switches to lean at 70% when standard"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "standard" > "$SCOPE_DIR/.economy-tier"
# Clear dedup
rm -f "$SCOPE_DIR/.eco-last" 2>/dev/null
INPUT='{"context_window":{"used_percentage":72},"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
TIER=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null)
if [ "$TIER" = "lean" ]; then
  pass
else
  fail "expected tier=lean, got $TIER"
fi
teardown_test_home

begin_test "adaptive-economy: auto-switches to minimal at 80% when lean"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "lean" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last" 2>/dev/null
INPUT='{"context_window":{"used_percentage":82},"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
TIER=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null)
if [ "$TIER" = "minimal" ]; then
  pass
else
  fail "expected tier=minimal, got $TIER"
fi
teardown_test_home

begin_test "adaptive-economy: suggests (not auto) revert at <30% minimal"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "minimal" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last" 2>/dev/null
INPUT='{"context_window":{"used_percentage":20},"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
TIER=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null)
# Should NOT auto-switch — just suggest
if [ "$TIER" = "minimal" ]; then
  echo "$OUTPUT" | grep -q "ECO" && pass || fail "expected ECO suggestion"
else
  fail "should not auto-switch down, got $TIER"
fi
teardown_test_home

begin_test "adaptive-economy: respects opt-out env var"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "standard" > "$SCOPE_DIR/.economy-tier"
rm -f "$SCOPE_DIR/.eco-last" 2>/dev/null
INPUT='{"context_window":{"used_percentage":75},"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | SUPERCHARGER_NO_AUTO_ECONOMY=1 bash "$HOOK" 2>/dev/null)
TIER=$(cat "$SCOPE_DIR/.economy-tier" 2>/dev/null)
if [ "$TIER" = "standard" ]; then
  pass
else
  fail "opt-out should prevent auto-switch"
fi
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-adaptive-economy-v2.sh`
Expected: FAIL — current hook only suggests, doesn't auto-switch.

- [ ] **Step 3: Upgrade `adaptive-economy.sh` with auto-switch logic**

Replace the logic section of `hooks/adaptive-economy.sh` (the `MSG=""` block through the dedup) with:

```bash
# Check opt-out
if [ "${SUPERCHARGER_NO_AUTO_ECONOMY:-0}" = "1" ]; then
  exit 0
fi

# Also check .supercharger.json opt-out
if [ -n "$PROJECT_DIR" ]; then
  AUTO_ECO=$(python3 -c "
import json, os
d = '$PROJECT_DIR'
for _ in range(5):
    c = os.path.join(d, '.supercharger.json')
    if os.path.isfile(c):
        with open(c) as f:
            print(json.load(f).get('autoEconomy', True))
        break
    p = os.path.dirname(d)
    if p == d: break
    d = p
else:
    print('True')
" 2>/dev/null || echo "True")
  [ "$AUTO_ECO" = "False" ] && exit 0
fi

MSG=""
AUTO_SWITCH=""

# Auto-switch UP (toward more compression) when context is high
if [ "$PCT" -ge 80 ] && [ "$TIER" = "lean" ]; then
  AUTO_SWITCH="minimal"
  MSG="[ECO] Auto-switched to Minimal (context at ${PCT}%)"
elif [ "$PCT" -ge 70 ] && [ "$TIER" = "standard" ]; then
  AUTO_SWITCH="lean"
  MSG="[ECO] Auto-switched to Lean (context at ${PCT}%)"
# Suggest (not auto) revert DOWN when context is low
elif [ "$PCT" -lt 30 ] && [ "$TIER" = "minimal" ]; then
  MSG="[ECO] Context low (${PCT}%). Lean tier OK if you want richer output."
elif [ "$PCT" -lt 20 ] && [ "$TIER" = "lean" ]; then
  MSG="[ECO] Context low. Standard tier OK."
fi

[ -z "$MSG" ] && exit 0

# Dedup
PCT_BUCKET=$(( PCT / 10 * 10 ))
DEDUP_KEY="${PCT_BUCKET}:${TIER}"
DEDUP_FILE="$SCOPE_DIR/.eco-last"
LAST_KEY=$(cat "$DEDUP_FILE" 2>/dev/null || echo "")
if [ "$DEDUP_KEY" = "$LAST_KEY" ]; then
  exit 0
fi
echo "$DEDUP_KEY" > "$DEDUP_FILE"

# Execute auto-switch if triggered
if [ -n "$AUTO_SWITCH" ]; then
  echo "$AUTO_SWITCH" > "$ECONOMY_TIER_FILE"
fi
```

- [ ] **Step 4: Add session-history learning to `adaptive-economy.sh`**

At the end of the script, before `exit 0`, add a section that writes history on auto-switch:

```bash
# Session-history learning: log tier transitions
if [ -n "$AUTO_SWITCH" ]; then
  HISTORY_FILE="$SCOPE_DIR/.economy-history.jsonl"
  python3 -c "
import json, time
entry = {
    'date': time.strftime('%Y-%m-%d'),
    'tier_before': '$TIER',
    'tier_after': '$AUTO_SWITCH',
    'context_pct': $PCT
}
with open('$HISTORY_FILE', 'a') as f:
    f.write(json.dumps(entry) + '\n')
# Keep last 20 entries
try:
    with open('$HISTORY_FILE') as f:
        lines = f.readlines()
    if len(lines) > 20:
        with open('$HISTORY_FILE', 'w') as f:
            f.writelines(lines[-20:])
except Exception:
    pass
" 2>/dev/null || true
fi
```

Then in `session-memory-inject.sh` (Task 15), add session-start learning. Before the existing memory file check, add:

```bash
# Adaptive economy: check history and suggest starting tier
HISTORY_FILE="$HOME/.claude/supercharger/scope/.economy-history.jsonl"
if [ -f "$HISTORY_FILE" ]; then
  ECO_SUGGESTION=$(python3 -c "
import json
lines = open('$HISTORY_FILE').readlines()[-3:]
if len(lines) >= 3:
    pcts = [json.loads(l).get('context_pct', 0) for l in lines]
    avg = sum(pcts) / len(pcts)
    if avg > 70:
        print(f'[ECO] Starting at Lean — recent sessions averaged {int(avg)}% context.')
" 2>/dev/null || echo "")
  if [ -n "$ECO_SUGGESTION" ]; then
    # Auto-set tier to lean
    echo "lean" > "$HOME/.claude/supercharger/scope/.economy-tier"
  fi
fi
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/test-adaptive-economy-v2.sh`
Expected: All 4 PASS.

- [ ] **Step 6: Run full suite for regression**

Run: `bash tests/run.sh`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/adaptive-economy.sh tests/test-adaptive-economy-v2.sh
git commit -m "feat: adaptive economy auto-switch — automatically adjusts tier based on context pressure"
```

---

### Task 11: Thinking Budget Control (`thinking-budget.sh`)

**Files:**
- Create: `hooks/thinking-budget.sh`
- Test: `tests/test-thinking-budget.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-thinking-budget.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/thinking-budget.sh"

echo "=== Thinking Budget Tests ==="

begin_test "thinking-budget: low complexity prompt gets THINK injection"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"prompt":"show me the file","cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "THINK" && echo "$OUTPUT" | grep -qi "trivial\|minimal\|directly" && pass || fail "expected low-complexity THINK injection"
teardown_test_home

begin_test "thinking-budget: high complexity prompt gets THINK injection"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"prompt":"design the authentication system with OAuth2 integration, session management, and role-based access control for our microservices architecture","cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "THINK" && echo "$OUTPUT" | grep -qi "complex\|thorough" && pass || fail "expected high-complexity THINK injection"
teardown_test_home

begin_test "thinking-budget: medium complexity prompt gets no injection"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"prompt":"add a loading spinner to the button component","cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output for medium complexity"
teardown_test_home

begin_test "thinking-budget: uses agent classification when available"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "debugger" > "$SCOPE_DIR/.agent-classified-test-session"
INPUT='{"prompt":"fix it","cwd":"/tmp","session_id":"test-session"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "THINK" && echo "$OUTPUT" | grep -qi "complex\|thorough" && pass || fail "debugger should map to high complexity"
teardown_test_home

begin_test "thinking-budget: yes/no prompt is low complexity"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"prompt":"yes","cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "THINK" && echo "$OUTPUT" | grep -qi "trivial\|minimal\|directly" && pass || fail "expected low-complexity for yes/no"
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-thinking-budget.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `thinking-budget.sh`**

Create `hooks/thinking-budget.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Thinking Budget Control
# Event: UserPromptSubmit | Matcher: (none)
# Nudges Claude to calibrate reasoning depth based on task complexity.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"

# Opt-out via .supercharger.json → thinkingControl: false
[ -f "$SCOPE_DIR/.no-thinking-control" ] && exit 0

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

RESULT=$(SCOPE_DIR="$SCOPE_DIR" python3 -c "
import json, sys, os, time

data = json.loads(sys.stdin.read())
prompt = data.get('prompt', '') or ''
session_id = data.get('session_id', '') or ''

if not prompt:
    sys.exit(0)

scope = os.environ['SCOPE_DIR']
complexity = 'medium'

# Check agent classification first (if recent)
if session_id:
    agent_file = os.path.join(scope, f'.agent-classified-{session_id}')
    if os.path.isfile(agent_file):
        try:
            if time.time() - os.path.getmtime(agent_file) < 2:
                agent = open(agent_file).read().strip().lower()
                if agent in ('debugger', 'architect', 'planner'):
                    complexity = 'high'
                elif agent in ('code-helper', 'general', 'writer'):
                    # Code-helper with short prompt = low
                    if len(prompt.split()) < 10:
                        complexity = 'low'
        except Exception:
            pass

# Keyword-based classification (if agent didn't decide)
if complexity == 'medium':
    words = prompt.lower().split()
    # Approximate token count: ~1.3 tokens per word for English
    token_count = int(len(words) * 1.3)

    low_verbs = {'read', 'show', 'list', 'run', 'yes', 'no', 'ok', 'okay', 'sure', 'continue', 'go', 'next'}
    high_verbs = {'design', 'architect', 'plan', 'debug', 'investigate', 'refactor', 'analyze', 'migrate', 'redesign'}

    if token_count < 50 and (any(w in low_verbs for w in words) or '?' not in prompt):
        complexity = 'low'
    elif any(w in high_verbs for w in words) or token_count > 200:
        complexity = 'high'

if complexity == 'low':
    print(json.dumps({'msg': '[THINK] Trivial task. Respond directly, minimal reasoning.'}))
elif complexity == 'high':
    print(json.dumps({'msg': '[THINK] Complex task. Reason thoroughly before acting.'}))
# medium = no output
" <<< "$_INPUT" 2>/dev/null) || true

[ -z "$RESULT" ] && exit 0

MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)
echo "[Supercharger] thinking-budget: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-thinking-budget.sh`
Expected: All 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/thinking-budget.sh tests/test-thinking-budget.sh
git commit -m "feat: add thinking-budget hook — calibrates reasoning depth by task complexity"
```

---

### Task 12: Rate-Limit Burn Forecasting (`rate-limit-advisor.sh` + statusline upgrade)

**Files:**
- Create: `hooks/rate-limit-advisor.sh`
- Modify: `hooks/statusline.sh`
- Test: `tests/test-rate-limit-advisor.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-rate-limit-advisor.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/rate-limit-advisor.sh"

echo "=== Rate Limit Advisor Tests ==="

begin_test "rate-limit-advisor: warns when projected exhaustion < 30m"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# Session started 10 min ago, already at 60% — burns 6%/min → exhausts in ~6.7 min
TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")
echo "{\"total_usd\":0.5,\"turn_count\":5,\"avg_per_turn\":0.1,\"last_updated\":\"$TEN_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"
INPUT="{\"rate_limits\":{\"five_hour\":{\"used_percentage\":60}},\"cwd\":\"/tmp\"}"
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "RATE" && pass || fail "expected RATE warning"
teardown_test_home

begin_test "rate-limit-advisor: no warning when exhaustion > 30m"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
SIXTY_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-3600)))")
echo "{\"total_usd\":1.0,\"turn_count\":10,\"avg_per_turn\":0.1,\"last_updated\":\"$SIXTY_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"
# 10% used in 60 min = 0.167%/min → exhausts in ~540 min
INPUT='{"rate_limits":{"five_hour":{"used_percentage":10}},"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output for slow burn"
teardown_test_home

begin_test "rate-limit-advisor: no warning when no rate limit data"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
INPUT='{"cwd":"/tmp"}'
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected no output without rate data"
teardown_test_home

begin_test "rate-limit-advisor: deduplicates within same 10m band"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
TEN_MIN_AGO=$(python3 -c "import time; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-600)))")
echo "{\"total_usd\":0.5,\"turn_count\":5,\"avg_per_turn\":0.1,\"last_updated\":\"$TEN_MIN_AGO\"}" > "$SCOPE_DIR/.session-cost"
INPUT="{\"rate_limits\":{\"five_hour\":{\"used_percentage\":60}},\"cwd\":\"/tmp\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
# Second call should be deduped
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUTPUT" ] && pass || fail "expected dedup on second call"
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-rate-limit-advisor.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `rate-limit-advisor.sh`**

Create `hooks/rate-limit-advisor.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Rate Limit Burn Advisor
# Event: UserPromptSubmit | Matcher: (none) | Flags: async
# Warns when projected rate limit exhaustion is < 30 minutes.

set -euo pipefail
HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib-suppress.sh
. "$HOOKS_DIR/lib-suppress.sh"

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null); [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"
init_hook_suppress "$PROJECT_DIR"

RESULT=$(SCOPE_DIR="$SCOPE_DIR" python3 -c "
import json, sys, os, time

data = json.loads(sys.stdin.read())
scope = os.environ['SCOPE_DIR']

# Get rate limit percentage
rl = (data.get('rate_limits') or {}).get('five_hour') or {}
used_pct = float(rl.get('used_percentage', 0) or 0)

if used_pct <= 0:
    sys.exit(0)

# Get session start time from .session-cost (first_updated = timestamp of first accumulation)
cost_file = os.path.join(scope, '.session-cost')
if not os.path.isfile(cost_file):
    sys.exit(0)

try:
    with open(cost_file) as f:
        sc = json.load(f)
    # Use first_updated (set on first accumulation), NOT last_updated (changes every turn)
    start_str = sc.get('first_updated', '') or sc.get('last_updated', '')
    if not start_str:
        sys.exit(0)
    start_t = time.mktime(time.strptime(start_str, '%Y-%m-%dT%H:%M:%SZ'))
except Exception:
    sys.exit(0)

elapsed_min = (time.time() - start_t) / 60
if elapsed_min < 5:
    sys.exit(0)

burn_rate = used_pct / elapsed_min  # pct per minute
if burn_rate <= 0:
    sys.exit(0)

remaining_pct = 100 - used_pct
time_to_exhaust = remaining_pct / burn_rate  # minutes

if time_to_exhaust >= 30:
    sys.exit(0)

# Dedup by 10-minute band
band = int(time_to_exhaust // 10) * 10
dedup_file = os.path.join(scope, '.rate-limit-last-warn')
try:
    last_band = int(open(dedup_file).read().strip())
    if last_band == band:
        sys.exit(0)
except Exception:
    pass

with open(dedup_file, 'w') as f:
    f.write(str(band))

msg = f'[RATE] At current pace, session exhausts in ~{int(time_to_exhaust)}m. Consider: eco minimal, fewer subagents, or pause for rate reset.'
print(json.dumps({'msg': msg}))
" <<< "$_INPUT" 2>/dev/null) || true

[ -z "$RESULT" ] && exit 0

MSG=$(printf '%s\n' "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['msg'])" 2>/dev/null)
echo "[Supercharger] rate-limit-advisor: $MSG" >&2

CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
if [ "$HOOK_SUPPRESS" = "false" ]; then
  printf '{"systemMessage":%s,"suppressOutput":false}\n' "$CONTEXT_JSON"
else
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$CONTEXT_JSON"
fi

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-rate-limit-advisor.sh`
Expected: All 4 PASS.

- [ ] **Step 5: Add burn rate projection to statusline**

In `hooks/statusline.sh`, in the rate limits section, after calculating `rl_5h_pct` and `reset_label`, add burn rate projection:

```python
         # Burn rate projection
         burn_proj = ''
         try:
             scope = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope')
             cost_file = os.path.join(scope, '.session-cost')
             if os.path.isfile(cost_file) and float(rl_5h_pct) > 0:
                 with open(cost_file) as f:
                     sc = json.load(f)
                 start_str = sc.get('last_updated', '')
                 if start_str:
                     import calendar
                     st = calendar.timegm(time.strptime(start_str, '%Y-%m-%dT%H:%M:%SZ'))
                     elapsed = (time.time() - st) / 60
                     if elapsed >= 5:
                         burn = float(rl_5h_pct) / elapsed
                         if burn > 0:
                             ttx = int((100 - float(rl_5h_pct)) / burn)
                             if ttx < 120:
                                 burn_proj = f' · ~{ttx}m left at this pace'
         except Exception:
             burn_proj = ''
```

Update the `rl_str` to include `burn_proj`:

```python
         rl_str = f' {DIM}|{RESET} {rl_color}Session: {float(rl_5h_pct):.0f}%{reset_label}{burn_proj}{RESET}'
```

- [ ] **Step 6: Commit**

```bash
git add hooks/rate-limit-advisor.sh hooks/statusline.sh tests/test-rate-limit-advisor.sh
git commit -m "feat: rate-limit burn forecasting — warns when session projected to exhaust in <30m"
```

---

### Task 13: Hook Registration — Wave 2

**Files:**
- Modify: `lib/hooks.sh`

- [ ] **Step 1: Add Wave 2 hooks to `get_hooks_for_mode()`**

In the full mode section of `lib/hooks.sh`, add:

```bash
    hooks+=("UserPromptSubmit||${hooks_dir}/thinking-budget.sh|")
    hooks+=("UserPromptSubmit||${hooks_dir}/rate-limit-advisor.sh|async")
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run.sh`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat: register Wave 2 hooks — thinking-budget, rate-limit-advisor"
```

---

## Wave 3: Session Intelligence

### Task 14: Session Checkpoint (`session-checkpoint.sh`)

**Files:**
- Create: `hooks/session-checkpoint.sh`
- Test: `tests/test-session-checkpoint.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-session-checkpoint.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/session-checkpoint.sh"

echo "=== Session Checkpoint Tests ==="

begin_test "checkpoint: writes checkpoint after Write tool"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
# Need a git repo for branch detection
PROJ=$(mktemp -d)
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
INPUT="{\"session_id\":\"ckpt-test\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/src/app.ts\"},\"cwd\":\"$PROJ\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
assert_file_exists "$SCOPE_DIR/.checkpoint-ckpt-test" && pass
rm -rf "$PROJ"
teardown_test_home

begin_test "checkpoint: overwrites previous checkpoint"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ=$(mktemp -d)
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
echo "old data" > "$SCOPE_DIR/.checkpoint-ckpt-test2"
INPUT="{\"session_id\":\"ckpt-test2\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$PROJ/src/new.ts\"},\"cwd\":\"$PROJ\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
CONTENT=$(cat "$SCOPE_DIR/.checkpoint-ckpt-test2")
echo "$CONTENT" | grep -q "ckpt:" && pass || fail "expected ckpt: prefix, got: $CONTENT"
rm -rf "$PROJ"
teardown_test_home

begin_test "checkpoint: includes branch and files"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ=$(mktemp -d)
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
INPUT="{\"session_id\":\"ckpt-test3\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$PROJ/src/auth.ts\"},\"cwd\":\"$PROJ\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
CONTENT=$(cat "$SCOPE_DIR/.checkpoint-ckpt-test3")
echo "$CONTENT" | grep -q "branch:" && echo "$CONTENT" | grep -q "files:" && pass || fail "missing branch or files"
rm -rf "$PROJ"
teardown_test_home

begin_test "checkpoint: capped at 500 chars"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ=$(mktemp -d)
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
# Create many files to bloat the checkpoint
for i in $(seq 1 50); do touch "$PROJ/file-$i.ts"; done
git -C "$PROJ" add -A && git -C "$PROJ" commit -q -m "add files"
INPUT="{\"session_id\":\"ckpt-test4\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"},\"cwd\":\"$PROJ\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
SIZE=$(wc -c < "$SCOPE_DIR/.checkpoint-ckpt-test4" | tr -d ' ')
if [ "$SIZE" -le 500 ]; then
  pass
else
  fail "expected <=500 chars, got $SIZE"
fi
rm -rf "$PROJ"
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-session-checkpoint.sh`
Expected: FAIL — hook does not exist.

- [ ] **Step 3: Implement `session-checkpoint.sh`**

Create `hooks/session-checkpoint.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Session Checkpoint
# Event: PostToolUse | Matcher: Write,Edit,Bash | Flags: async
# Writes lightweight checkpoint for crash recovery.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"

_INPUT=$(cat)
SESSION_ID=$(printf '%s\n' "$_INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID=$(printf '%s\n' "$_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null || echo "")
[ -z "$SESSION_ID" ] && SESSION_ID="default"

PROJECT_DIR=$(printf '%s\n' "$_INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$PWD"

CHECKPOINT_FILE="$SCOPE_DIR/.checkpoint-${SESSION_ID}"

CONTENT=$(PROJECT_DIR="$PROJECT_DIR" SCOPE_DIR="$SCOPE_DIR" python3 -c "
import os, subprocess, time

project_dir = os.environ.get('PROJECT_DIR', '')
scope = os.environ['SCOPE_DIR']
ts = time.strftime('%Y-%m-%dT%H:%MZ', time.gmtime())

branch = ''
try:
    r = subprocess.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
        capture_output=True, text=True, cwd=project_dir, timeout=2)
    if r.returncode == 0:
        branch = r.stdout.strip()
except Exception:
    pass

files = []
try:
    r = subprocess.run(['git', 'diff', '--name-only'],
        capture_output=True, text=True, cwd=project_dir, timeout=2)
    files = [f for f in r.stdout.strip().split('\n') if f]
    r2 = subprocess.run(['git', 'diff', '--cached', '--name-only'],
        capture_output=True, text=True, cwd=project_dir, timeout=2)
    for f in r2.stdout.strip().split('\n'):
        if f and f not in files:
            files.append(f)
    r3 = subprocess.run(['git', 'ls-files', '--others', '--exclude-standard'],
        capture_output=True, text=True, cwd=project_dir, timeout=2)
    for f in r3.stdout.strip().split('\n'):
        if f and f not in files:
            files.append(f)
except Exception:
    pass

cost = ''
cost_file = os.path.join(scope, '.session-cost')
if os.path.isfile(cost_file):
    try:
        import json
        with open(cost_file) as f:
            sc = json.load(f)
        cost = f\"\${sc.get('total_usd', 0):.2f}\"
    except Exception:
        pass

line = f'ckpt:{ts} branch:{branch or \"?\"} files:{(\",\".join(files[:15])) or \"none\"} cost:{cost or \"?\"}'
# Cap at 500 chars
print(line[:500])
" 2>/dev/null) || true

[ -z "$CONTENT" ] && exit 0

printf '%s\n' "$CONTENT" > "$CHECKPOINT_FILE"
echo "[Supercharger] session-checkpoint: wrote checkpoint" >&2
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-session-checkpoint.sh`
Expected: All 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/session-checkpoint.sh tests/test-session-checkpoint.sh
git commit -m "feat: add session-checkpoint hook — crash-resilient state written on every file change"
```

---

### Task 15: Enhanced Session Resume (upgrade `session-memory-inject.sh`)

**Files:**
- Modify: `hooks/session-memory-inject.sh`
- Modify: `hooks/session-memory-write.sh` (checkpoint cleanup)
- Modify: `hooks/session-complete.sh` (checkpoint cleanup)

- [ ] **Step 1: Add checkpoint recovery to `session-memory-inject.sh`**

After the existing `[ ! -f "$MEMORY_FILE" ] && exit 0` line, replace it with fallback logic:

```bash
# Checkpoint recovery fallback
if [ ! -f "$MEMORY_FILE" ]; then
  # Check for crash checkpoint
  CKPT=""
  for f in "$HOME/.claude/supercharger/scope"/.checkpoint-*; do
    [ -f "$f" ] || continue
    # Only use if < 24h old
    if python3 -c "import os,time; exit(0 if time.time()-os.path.getmtime('$f')<86400 else 1)" 2>/dev/null; then
      CKPT=$(cat "$f" 2>/dev/null)
      break
    else
      rm -f "$f" 2>/dev/null
    fi
  done
  if [ -n "$CKPT" ]; then
    MSG="[RECOVERY] Restored from mid-session checkpoint: $CKPT"
    CONTEXT_JSON=$(printf '%s' "$MSG" | jq -Rs '.' 2>/dev/null || printf '"%s"' "$(printf '%s' "$MSG" | tr -d '"\\' | tr '\n' ' ')")
    printf '{"systemMessage":%s,"suppressOutput":%s}\n' "$CONTEXT_JSON" "$HOOK_SUPPRESS"
    echo "[Supercharger] session-memory: recovered from checkpoint" >&2
  fi
  exit 0
fi
```

- [ ] **Step 2: Add enrichment to the existing memory injection path**

Before the `MSG="[MEM] ${CONTENT}"` line (the full injection path), add enrichment:

```bash
  # Enrich with live data (Wave 3 enhanced resume)
  ENRICHMENT=""
  # Git diff summary
  DIFF_STAT=$(git -C "$PROJECT_DIR" diff --stat HEAD 2>/dev/null | tail -1 | grep -o '[0-9]* file.*' || echo "")
  [ -n "$DIFF_STAT" ] && ENRICHMENT="${ENRICHMENT} diff:${DIFF_STAT}"
  # Last session cost
  COST_FILE="$HOME/.claude/supercharger/scope/.session-cost"
  if [ -f "$COST_FILE" ]; then
    LAST_COST=$(python3 -c "
import json, os, time
f = '$COST_FILE'
if time.time() - os.path.getmtime(f) < 86400:
    print(json.load(open(f)).get('total_usd', ''))
" 2>/dev/null || echo "")
    [ -n "$LAST_COST" ] && ENRICHMENT="${ENRICHMENT} last_cost:\$${LAST_COST}"
  fi
  # Recent failures (last 3, deduplicated)
  PROJECT_ROOT=$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_DIR")
  PROJ_HASH_ENR=$(printf '%s' "$PROJECT_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$PROJECT_ROOT" | md5 -q 2>/dev/null || echo "global")
  PROJ_HASH_ENR="${PROJ_HASH_ENR:0:8}"
  FAILURE_LOG="$HOME/.claude/supercharger/scope/.failure-log-${PROJ_HASH_ENR}"
  if [ -f "$FAILURE_LOG" ]; then
    FAILURES=$(tail -10 "$FAILURE_LOG" 2>/dev/null | sort -u | tail -3 | tr '\n' ',' | sed 's/,$//')
    [ -n "$FAILURES" ] && ENRICHMENT="${ENRICHMENT} failures:${FAILURES}"
  fi
  # Active open work on same branch — inject full memory + enrichment
  MSG="[MEM] ${CONTENT}${ENRICHMENT}"
```

- [ ] **Step 3: Add checkpoint cleanup to `session-memory-write.sh`**

At the end of `session-memory-write.sh`, before `exit 0`, add:

```bash
# Clean up checkpoint files (successful memory write = no longer needed)
rm -f "$HOME/.claude/supercharger/scope"/.checkpoint-* 2>/dev/null || true
```

- [ ] **Step 4: Add checkpoint cleanup to `session-complete.sh`**

At the end of `session-complete.sh`, before the webhook section, add:

```bash
# Clean up checkpoint files on normal session end
rm -f "$HOME/.claude/supercharger/scope"/.checkpoint-* 2>/dev/null || true
```

- [ ] **Step 5: Write `tests/test-session-resume-v2.sh`**

Create `tests/test-session-resume-v2.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/session-memory-inject.sh"

echo "=== Session Resume v2 Tests ==="

begin_test "resume: recovers from checkpoint when no memory file"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "ckpt:2026-04-22T14:30Z branch:main files:src/app.ts cost:\$2.34" > "$SCOPE_DIR/.checkpoint-recovery-test"
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude"
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "RECOVERY" && pass || fail "expected RECOVERY injection"
rm -rf "$PROJ"
teardown_test_home

begin_test "resume: prefers memory file over checkpoint"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
echo "ckpt:old" > "$SCOPE_DIR/.checkpoint-prefer-test"
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude"
echo "mem:2026-04-22T15:00Z branch:main open:none commits:none corrections:none" > "$PROJ/.claude/supercharger-memory.md"
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "RECOVERY" && fail "should prefer memory over checkpoint" || pass
rm -rf "$PROJ"
teardown_test_home

begin_test "resume: deletes stale checkpoints (>24h)"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
STALE="$SCOPE_DIR/.checkpoint-stale-test"
echo "ckpt:old" > "$STALE"
# Backdate the file
touch -t 202604200000 "$STALE" 2>/dev/null || true
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude"
cd "$PROJ" && git init -q && git commit --allow-empty -m "init" -q
INPUT="{\"cwd\":\"$PROJ\"}"
echo "$INPUT" | bash "$HOOK" >/dev/null 2>&1
# Stale checkpoint should be cleaned up
if [ ! -f "$STALE" ]; then
  pass
else
  fail "expected stale checkpoint to be deleted"
fi
rm -rf "$PROJ"
teardown_test_home

begin_test "resume: enrichment includes diff when changes exist"
setup_test_home
SCOPE_DIR="$HOME/.claude/supercharger/scope"
mkdir -p "$SCOPE_DIR"
PROJ=$(mktemp -d)
mkdir -p "$PROJ/.claude"
cd "$PROJ" && git init -q
echo "hello" > "$PROJ/file.txt"
git -C "$PROJ" add file.txt && git -C "$PROJ" commit -q -m "init"
echo "modified" > "$PROJ/file.txt"
echo "mem:2026-04-22T15:00Z branch:main open:file.txt commits:abc:init corrections:none" > "$PROJ/.claude/supercharger-memory.md"
INPUT="{\"cwd\":\"$PROJ\"}"
OUTPUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUTPUT" | grep -q "diff:" && pass || fail "expected diff enrichment"
rm -rf "$PROJ"
teardown_test_home

report
```

- [ ] **Step 6: Run tests**

Run: `bash tests/test-session-resume-v2.sh`
Expected: All 4 PASS.

- [ ] **Step 7: Run full test suite**

Run: `bash tests/run.sh`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add hooks/session-memory-inject.sh hooks/session-memory-write.sh hooks/session-complete.sh tests/test-session-resume-v2.sh
git commit -m "feat: enhanced session resume — checkpoint recovery + enriched injection with diff/cost/failures"
```

---

### Task 16: Hook Performance Profiler (`tools/hook-perf.sh`)

**Files:**
- Create: `tools/hook-perf.sh`
- Test: `tests/test-hook-perf.sh` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/test-hook-perf.sh`:

```bash
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TOOL="$REPO_DIR/tools/hook-perf.sh"

echo "=== Hook Perf Tests ==="

begin_test "hook-perf: runs without error on empty audit dir"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/audit"
bash "$TOOL" >/dev/null 2>&1
assert_exit_code 0 $? && pass
teardown_test_home

begin_test "hook-perf: parses elapsed= from stderr log lines"
setup_test_home
AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
cat > "$AUDIT_DIR/$TODAY.jsonl" << 'JSONL'
{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}
{"timestamp":"2026-04-22T14:00:01Z","hook":"safety.sh","elapsed_ms":15}
{"timestamp":"2026-04-22T14:00:02Z","hook":"code-security-scanner.sh","elapsed_ms":89}
JSONL
OUTPUT=$(bash "$TOOL" 2>/dev/null)
echo "$OUTPUT" | grep -q "safety.sh" && pass || fail "expected safety.sh in output"
teardown_test_home

begin_test "hook-perf: --slow filters to hooks >50ms avg"
setup_test_home
AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
cat > "$AUDIT_DIR/$TODAY.jsonl" << 'JSONL'
{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}
{"timestamp":"2026-04-22T14:00:01Z","hook":"code-security-scanner.sh","elapsed_ms":89}
JSONL
OUTPUT=$(bash "$TOOL" --slow 2>/dev/null)
echo "$OUTPUT" | grep -q "safety.sh" && fail "safety.sh should be filtered out" || pass
teardown_test_home

begin_test "hook-perf: --json outputs valid JSON"
setup_test_home
AUDIT_DIR="$HOME/.claude/supercharger/audit"
mkdir -p "$AUDIT_DIR"
TODAY=$(date -u +"%Y-%m-%d")
echo '{"timestamp":"2026-04-22T14:00:00Z","hook":"safety.sh","elapsed_ms":12}' > "$AUDIT_DIR/$TODAY.jsonl"
OUTPUT=$(bash "$TOOL" --json 2>/dev/null)
python3 -c "import json; json.loads('$OUTPUT')" 2>/dev/null && pass || {
  # Try reading from stdout properly
  echo "$OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null && pass || fail "expected valid JSON"
}
teardown_test_home

report
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-hook-perf.sh`
Expected: FAIL — tool does not exist.

- [ ] **Step 3: Implement `tools/hook-perf.sh`**

Create `tools/hook-perf.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Hook Performance Profiler
# Usage: bash tools/hook-perf.sh [--slow] [--days N] [--session] [--json]

set -euo pipefail

DAYS=1
SLOW_ONLY=false
SESSION_ONLY=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slow)    SLOW_ONLY=true; shift ;;
    --days|-d) DAYS="$2"; shift 2 ;;
    --session) SESSION_ONLY=true; DAYS=1; shift ;;
    --json)    JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: bash tools/hook-perf.sh [--slow] [--days N] [--session] [--json]"
      echo "  --slow       Only show hooks averaging >50ms"
      echo "  --days N     Lookback window in days (default: 1)"
      echo "  --session    Filter to most recent session only"
      echo "  --json       Machine-readable output"
      exit 0 ;;
    *) shift ;;
  esac
done

AUDIT_DIR="$HOME/.claude/supercharger/audit"

if [ ! -d "$AUDIT_DIR" ]; then
  echo "No audit data found"
  exit 0
fi

SLOW_ONLY="$SLOW_ONLY" JSON_OUTPUT="$JSON_OUTPUT" DAYS="$DAYS" AUDIT_DIR="$AUDIT_DIR" python3 << 'PYEOF'
import os, json, sys, time, glob
from collections import defaultdict

days = int(os.environ.get('DAYS', '1'))
audit_dir = os.environ['AUDIT_DIR']
slow_only = os.environ.get('SLOW_ONLY', 'false') == 'true'
json_output = os.environ.get('JSON_OUTPUT', 'false') == 'true'

cutoff = time.time() - days * 86400

# Collect all JSONL files
hooks = defaultdict(lambda: {'calls': 0, 'total_ms': 0, 'mode': 'unknown'})

for fpath in sorted(glob.glob(os.path.join(audit_dir, '*.jsonl'))):
    try:
        mtime = os.path.getmtime(fpath)
        if mtime < cutoff:
            continue
    except Exception:
        continue

    try:
        with open(fpath) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    hook = entry.get('hook', '')
                    elapsed = entry.get('elapsed_ms', 0)
                    if hook and elapsed:
                        hooks[hook]['calls'] += 1
                        hooks[hook]['total_ms'] += elapsed
                except Exception:
                    continue
    except Exception:
        continue

if not hooks:
    if json_output:
        print(json.dumps({'hooks': [], 'total_overhead_s': 0, 'total_calls': 0}))
    else:
        print('No hook timing data found. Hooks report timing via elapsed= in stderr logs.')
    sys.exit(0)

# Calculate averages
results = []
for name, data in sorted(hooks.items(), key=lambda x: x[1]['total_ms'], reverse=True):
    avg = data['total_ms'] // data['calls'] if data['calls'] > 0 else 0
    if slow_only and avg <= 50:
        continue
    results.append({
        'hook': name,
        'calls': data['calls'],
        'avg_ms': avg,
        'total_s': round(data['total_ms'] / 1000, 1),
    })

total_overhead = sum(h['total_ms'] for h in hooks.values()) / 1000
total_calls = sum(h['calls'] for h in hooks.values())

if json_output:
    print(json.dumps({
        'hooks': results,
        'total_overhead_s': round(total_overhead, 1),
        'total_calls': total_calls,
        'avg_per_call_ms': round(total_overhead * 1000 / total_calls) if total_calls > 0 else 0
    }))
else:
    print(f'Hook Performance Report (last {days} day{"s" if days > 1 else ""})')
    print('─' * 55)
    print(f'{"Hook":<30} {"Calls":>6} {"Avg(ms)":>8} {"Total(s)":>9}')
    print('─' * 55)
    for r in results:
        print(f'{r["hook"]:<30} {r["calls"]:>6} {r["avg_ms"]:>8} {r["total_s"]:>9}')
    print('─' * 55)
    avg_all = round(total_overhead * 1000 / total_calls) if total_calls > 0 else 0
    print(f'Total hook overhead: {total_overhead:.1f}s across {total_calls} calls (avg {avg_all}ms/call)')
PYEOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-hook-perf.sh`
Expected: All 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/hook-perf.sh tests/test-hook-perf.sh
git commit -m "feat: add hook-perf tool — hook performance profiler with timing analysis"
```

---

### Task 17: Hook Registration — Wave 3

**Files:**
- Modify: `lib/hooks.sh`

- [ ] **Step 1: Add Wave 3 hooks to `get_hooks_for_mode()`**

In the full mode section of `lib/hooks.sh`, add:

```bash
    hooks+=("PostToolUse|Write,Edit,Bash|${hooks_dir}/session-checkpoint.sh|async")
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run.sh`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat: register Wave 3 hook — session-checkpoint"
```

---

### Task 18: Project Config Extension

**Files:**
- Modify: `hooks/project-config.sh`

- [ ] **Step 1: Add new `.supercharger.json` fields to project-config.sh**

In the Python block that parses `.supercharger.json`, after the `hints` parsing section, add:

```python
        # v2 fields
        budget = config.get('budget', '')
        if budget:
            try:
                budget = float(budget)
                if budget > 0:
                    # Write to scope for budget-cap.sh to read
                    budget_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.budget-cap')
                    with open(budget_file, 'w') as f:
                        f.write(str(budget))
                    cfg_parts.append(f'Budget: ${budget:.2f}')
            except (ValueError, TypeError):
                pass

        auto_economy = config.get('autoEconomy', True)
        if auto_economy is False:
            cfg_parts.append('Auto-economy: off')

        thinking_control = config.get('thinkingControl', True)
        if thinking_control is False:
            # Write flag for thinking-budget.sh to check
            tc_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.no-thinking-control')
            with open(tc_file, 'w') as f:
                f.write('1')
            cfg_parts.append('Thinking control: off')
        else:
            # Remove opt-out flag if it was previously set
            tc_file = os.path.join(os.path.expanduser('~'), '.claude', 'supercharger', 'scope', '.no-thinking-control')
            if os.path.isfile(tc_file):
                os.remove(tc_file)

        forecast_turns = config.get('forecastTurnsPerAgent', '')
        if forecast_turns:
            try:
                forecast_turns = int(forecast_turns)
                if forecast_turns != 10:
                    cfg_parts.append(f'Forecast: {forecast_turns} turns/agent')
            except (ValueError, TypeError):
                pass
```

- [ ] **Step 2: Run full test suite**

Run: `bash tests/run.sh`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add hooks/project-config.sh
git commit -m "feat: parse v2 .supercharger.json fields — budget, autoEconomy, forecastTurnsPerAgent"
```

---

### Task 19: Final Integration + README Update

**Files:**
- Modify: `docs/ROADMAP.md`
- Run: Full test suite

- [ ] **Step 1: Run complete test suite**

Run: `bash tests/run.sh`
Expected: All tests pass (~330 total).

- [ ] **Step 2: Update ROADMAP.md — mark shipped features**

Add Wave 1/2/3 features to the Shipped section of `docs/ROADMAP.md`.

- [ ] **Step 3: Verify hook counts in lib/hooks.sh comments**

Run: `bash -c 'source lib/hooks.sh; echo "Safe: $(get_hooks_for_mode safe false /tmp | wc -l | tr -d " ")"; echo "Full: $(get_hooks_for_mode full false /tmp | wc -l | tr -d " ")"; echo "Full+dev: $(get_hooks_for_mode full true /tmp | wc -l | tr -d " ")"'`

Expected: Safe: 10, Full: 58, Full+dev: 60.

- [ ] **Step 4: Commit**

```bash
git add docs/ROADMAP.md
git commit -m "docs: update roadmap — mark v2 Cost Shield, Smart Adaptation, Session Intelligence as shipped"
```
