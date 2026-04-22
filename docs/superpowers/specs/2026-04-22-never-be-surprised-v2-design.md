# Supercharger v2 — "Never Be Surprised"

Design spec for 10 new features across 3 waves, unified by one principle: every dimension of a Claude Code session becomes visible and controllable — cost, context, cache, performance, state — without requiring user configuration or code.

**Date:** 2026-04-22
**Status:** Draft
**Author:** smrafiz + Claude

---

## Problem Statement

The #1 reason users abandon AI coding tools is **illegibility** — opaque costs, silent performance degradation, surprise rate limits, and invisible cache failures. Research across 6,852+ sessions and ecosystem tools (ccusage, oh-my-claudecode, GSD, Cline, Cursor, Windsurf) confirms:

- Silent rate limit drain is the top abandonment driver for paying users
- Prompt caching bugs silently re-bill full context at creation rates (3-50x cost)
- Runaway subagent costs hit $8K-$47K in documented incidents with no warning
- 73% of users can't predict when their session will exhaust

Supercharger v1 made sessions *observable* (statusline, audit trail, context advisor). v2 makes them *predictable and controllable*.

---

## Design Principles

1. **Zero-config by default** — every feature works on install with no configuration
2. **Opt-in control, opt-out restriction** — caps and overrides require explicit setup; protection is automatic
3. **Advisory before enforced** — warn first, block only when user has set a hard limit
4. **Token-cheap** — all injections target <50 tokens. No feature should cost more than it saves
5. **Existing architecture** — all features are hooks or tools. No new runtime dependencies. No API proxies
6. **Crash-safe** — state written incrementally, not just on clean exit

---

## Wave 1: Cost Shield

Theme: "Never be surprised by cost"

### 1.1 Budget Cap (`budget-cap.sh`)

**Purpose:** Optional hard stop when session cost exceeds a user-defined limit.

**Events:**
- `PostToolUse` (async) — accumulate cost after each tool call
- `UserPromptSubmit` — check accumulated cost against cap, warn or block

**Configuration (all optional):**
- `.supercharger.json` → `"budget": 5.00`
- Environment variable: `SESSION_BUDGET_CAP=5.00`
- No cap set = no blocking. Cost tracking still runs for other features.

**Behavior:**
- `PostToolUse` (async): reads token usage from stdin (`tool_response.usage`), calculates cost using pricing table, writes to `$SCOPE_DIR/.session-cost`
- `PreToolUse` (sync, subcommand `check`): reads `.session-cost`, compares to cap
- At 80% of cap: inject via additionalContext `"[BUDGET] $4.00/$5.00 (80%). Approaching session limit."`
- At 100%: exit 2 with `"Session budget of $5.00 reached. Start a new session or raise the cap."`
- After blocking, matcher excludes `Read`, `Glob`, `Grep` (read-only escape hatch — same pattern as smart-approve)

**Script pattern:** Single script with subcommand arg, matching `scope-guard.sh check|snapshot|clear`:
- `budget-cap.sh` (no arg) — PostToolUse accumulator
- `budget-cap.sh check` — PreToolUse blocker

**State file:** `$SCOPE_DIR/.session-cost`
```json
{"total_usd": 3.42, "turn_count": 18, "avg_per_turn": 0.19, "last_updated": "2026-04-22T14:30:00Z"}
```

**Pricing table (embedded, offline):**
```
input:       $3.00/MTok
cache_write: $3.75/MTok
cache_read:  $0.30/MTok
output:     $15.00/MTok
```

**Statusline integration:** Line 3 gains `Budget: $3.42/$5.00` when cap is set. No change when no cap.

**Safe mode:** Cost tracking (PostToolUse accumulator) runs in safe mode. Budget blocking (PreToolUse check) runs in full mode only.

---

### 1.2 Cost Forecast (`cost-forecast.sh`)

**Purpose:** Estimate cost before expensive operations so users can make informed decisions.

**Event:** `PreToolUse` matcher `Agent`

**Logic:**
1. Read `avg_per_turn` from `$SCOPE_DIR/.session-cost`
2. When an Agent tool fires, estimate: `avg_per_turn × estimated_turns`
3. Default estimate: 10 turns per subagent (configurable via `.supercharger.json` → `"forecastTurnsPerAgent": 10`)
4. Inject: `"[COST] Est. ~$1.90 for this agent (avg $0.19/turn × ~10 turns)"`

**When it fires:**
- Agent tool calls only — these are the expensive operations
- Skip if `avg_per_turn` is 0 (no data yet — first few turns of session)
- Skip if estimated cost < $0.10 (not worth the context injection)

**When it does NOT fire:**
- Simple tool calls (Read, Write, Bash, Grep, Glob) — too granular, too noisy
- After budget cap is hit (budget-cap already blocking)

**State:** Reads `.session-cost` (written by budget-cap). No state of its own.

---

### 1.3 Cache Health Monitor (`cache-health.sh`)

**Purpose:** Detect when prompt caching breaks down and silently re-bills full context.

**Event:** `PostToolUse` (async, sampled)

**Logic:**
1. Read `cache_read_input_tokens` and `cache_creation_input_tokens` from stdin
2. Calculate hit rate: `cache_read / (cache_read + cache_creation) × 100`
3. Write to rolling window in `$SCOPE_DIR/.cache-health` (last 5 readings)
4. If hit rate < 50% for 3 consecutive readings: fire warning

**Alert message:** `"[CACHE] Hit rate dropped to NN% (was ~90%). You may be getting re-billed for full context. Consider /compact or starting a fresh session."`

**Sampling:** Every 5th PostToolUse call (counter in `.cache-health`). Avoids per-tool-call overhead.

**Dedup:** One alert per 10% band drop. Don't spam if cache stays at 40%.

**Statusline integration:** Cache segment on line 2 (`cache 92%`) already exists. Change color: green (>70%), yellow (50-70%), red (<50%).

**Safe mode:** Yes — this affects all users, not just power users.

---

### 1.4 Subagent Cost Tracker (`subagent-cost.sh`)

**Purpose:** Make parallel agent costs visible per-agent, not just as an opaque total.

**Events:**
- `SubagentStart` — record agent ID, name, timestamp
- `SubagentStop` — calculate cost, log, inject summary

**On SubagentStart:**
Write to `$SCOPE_DIR/.subagent-active-{agent_id}`:
```json
{"agent_id": "abc123", "name": "code-helper", "started_at": "2026-04-22T14:30:00Z"}
```

**On SubagentStop:**
1. Read start record
2. Read token usage from stdin
3. Calculate cost
4. Delete start record
5. Append to `$SCOPE_DIR/.subagent-costs-{session_id}.jsonl`:
```json
{"agent_id": "abc123", "name": "code-helper", "cost_usd": 0.42, "tokens": 28000, "duration_s": 34}
```
6. Inject: `"[AGENT] code-helper completed: ~$0.42 (28K tokens, 34s)"`
7. Update `.session-cost` total (budget-cap reads this)

**Tooling:** `session-analytics.sh --subagents` reads the JSONL for per-agent breakdowns.

**Full mode only.**

---

## Wave 2: Smart Adaptation

Theme: "Supercharger adjusts for you"

### 2.1 Adaptive Economy Auto-Switch (upgrade `adaptive-economy.sh`)

**Purpose:** Automatically switch economy tier based on context pressure instead of just suggesting.

**Current behavior:** Suggests tier changes at thresholds. User must act manually.

**New behavior:**

| Condition | Action |
|---|---|
| Context ≥70% + tier is standard | Auto-switch to lean. Write `.economy-tier`. Reinforce immediately. Inject: `"[ECO] Auto-switched to Lean (context at NN%)"` |
| Context ≥80% + tier is lean | Auto-switch to minimal. Same mechanism. |
| Context <30% + tier is minimal | Suggest (not auto): `"[ECO] Context low (NN%). Lean tier OK if you want richer output."` |
| Context <20% + tier is lean | Suggest: `"[ECO] Context low. Standard tier OK."` |

**Session-history learning:**
- On `SessionEnd`: append to `$SCOPE_DIR/.economy-history.jsonl`:
  ```json
  {"date": "2026-04-22", "tier_start": "standard", "tier_end": "lean", "avg_context_pct": 74, "duration_min": 45}
  ```
- On `SessionStart`: read last 3 entries. If avg context >70%, start at lean:
  `"[ECO] Starting at Lean — recent sessions averaged NN% context."`

**Opt-out:** `SUPERCHARGER_NO_AUTO_ECONOMY=1` or `.supercharger.json` → `"autoEconomy": false`

**Backward compatible:** When `autoEconomy` is not set, defaults to `true` (auto-switch on). Existing suggest-only behavior available via opt-out.

---

### 2.2 Extended-Thinking Budget Control (`thinking-budget.sh`)

**Purpose:** Nudge Claude to reduce thinking depth on simple tasks, preserving deep reasoning for complex ones.

**Event:** `UserPromptSubmit`

**Classification signals (no LLM call):**

| Complexity | Signals | Injection |
|---|---|---|
| **Low** | Token count <50 AND (contains "read"/"show"/"list"/"yes"/"no"/"run" OR no question marks) | `"[THINK] Trivial task. Respond directly, minimal reasoning."` |
| **High** | Contains "design"/"architect"/"plan"/"debug"/"investigate"/"refactor" OR token count >200 | `"[THINK] Complex task. Reason thoroughly before acting."` |
| **Medium** | Everything else | No injection |

**Integration with agent-router:** If `agent-router.sh` has already classified the prompt (written to `$SCOPE_DIR/.agent-classified-{session_id}`), use that:
- debugger, architect, planner → high
- code-helper (simple edit context) → low
- Everything else → medium

Read the agent classification file. If it exists and is <2s old, use it. Otherwise classify independently.

**Honest limitation:** This is advisory. Claude Code doesn't expose `thinking_budget` to hooks at the API level. But research shows prompt-level nudges reduce thinking token usage 20-30% on simple tasks. The token savings compound over a session.

**State:** Stateless. No files. Runs per-prompt.

**Full mode only.**

---

### 2.3 Rate-Limit Burn Forecasting (upgrade `statusline.sh` + new `rate-limit-advisor.sh`)

**Purpose:** Predict when the session will exhaust rate limits so users can pace themselves.

**Statusline upgrade:**
Current line 3: `Session: 45% (resets: 2h 10m) · Weekly: 15%`
New line 3: `Session: 45% (resets: 2h 10m) · ~52m left at this pace · Weekly: 15%`

**Calculation:**
```python
elapsed_min = (now - session_start) in minutes
burn_rate = used_pct / elapsed_min  # percent per minute
remaining_pct = 100 - used_pct
time_to_exhaust = remaining_pct / burn_rate  # minutes

# Display only when meaningful
if elapsed_min >= 5 and burn_rate > 0:
    show "~{time_to_exhaust:.0f}m left at this pace"
```

**Warning hook (`rate-limit-advisor.sh`):**

| | |
|---|---|
| Event | `UserPromptSubmit` (async) |
| Trigger | Projected exhaustion < 30 minutes |
| Message | `"[RATE] At current pace, session exhausts in ~NNm. Consider: eco minimal, fewer subagents, or pause for rate reset."` |
| Dedup | One warning per 10-minute projection band. Don't repeat at 28m and 27m. |

**Data source:** `rate_limits` object from `UserPromptSubmit` stdin (same data context-advisor reads). Session start time derived from: first entry in `.session-cost` (`last_updated` field), or fallback to `$SCOPE_DIR/.session-start-ts` written by `session-memory-inject.sh` on SessionStart.

**State:** `$SCOPE_DIR/.rate-limit-last-warn` — stores last warning band for dedup.

**Full mode only** (rate limits are a power-user concern).

---

## Wave 3: Session Intelligence

Theme: "Sessions that survive anything"

### 3.1 Crash-Resilient Session State (`session-checkpoint.sh`)

**Purpose:** Survive mid-session crashes by writing lightweight checkpoints continuously.

**Event:** `PostToolUse` matcher `Write,Edit,Bash` (async)

**Logic:**
1. After every file-modifying tool call, overwrite `$SCOPE_DIR/.checkpoint-{session_id}`
2. Content: dense key=value, same format as session-memory-write:
   ```
   ckpt:2026-04-22T14:30Z branch:feature/auth files:src/auth.ts,src/middleware.ts cost:$2.34
   ```
3. Capped at 500 chars. Overwrite, not append.

**Recovery (upgrade `session-memory-inject.sh`):**
On `SessionStart`:
1. Check for `supercharger-memory.md` (normal path — use it)
2. If absent, check for `.checkpoint-*` files in `$SCOPE_DIR`
3. If checkpoint found and <24h old: inject it with prefix `"[RECOVERY] Restored from mid-session checkpoint (last: {timestamp})"`
4. If checkpoint is >24h old: delete it silently (stale)

**Cleanup:**
- `session-complete.sh` (normal Stop) deletes checkpoint files for the session
- `session-memory-write.sh` also deletes after successful memory write
- Checkpoints older than 24h cleaned up on next SessionStart

**Performance:** Async, <1KB write, overwrites previous. No measurable latency addition.

**Full mode only.**

---

### 3.2 Enhanced Session Resume (upgrade `session-memory-inject.sh`)

**Purpose:** Enrich session start context with live git state and cost history, not just stale memory.

**Current injection:** `mem:{ts} branch:{name} open:{files} commits:{hashes} corrections:{list}`

**New injection format:**
```
mem:{ts} branch:{name} open:{files} commits:{hashes} corrections:{list} diff:{N files +X/-Y} last_cost:{$X.XX} failures:{list}
```

**New fields:**

| Field | Source | How |
|---|---|---|
| `diff:{N files +X/-Y}` | `git diff --stat HEAD` | Count files and +/- from stat output |
| `last_cost:{$X.XX}` | `$SCOPE_DIR/.session-cost` from previous session | Read total_usd if file exists and <24h old |
| `failures:{list}` | `$SCOPE_DIR/.failure-log-{proj_hash}` | Last 3 unique failure messages, comma-separated |

**Logic change in `session-memory-inject.sh`:**
1. Read memory file (existing behavior)
2. Enrich with live data:
   - Run `git diff --stat HEAD 2>/dev/null` — extract summary line
   - Read `.session-cost` if <24h old — extract `total_usd`
   - Read failure log — deduplicate, take last 3
3. Inject combined string

**Token budget:** Target <300 tokens total. Current memory ~100 tokens. Enrichment budget: 200 tokens. Truncate aggressively if over.

**Full mode only.**

---

### 3.3 Hook Performance Profiler (`tools/hook-perf.sh`)

**Purpose:** Self-diagnosis — ensure 52+ hooks aren't adding latency users can feel.

**Type:** CLI tool (not a hook). No runtime cost.

**Usage:**
```bash
bash tools/hook-perf.sh              # all hooks, last 24h
bash tools/hook-perf.sh --slow       # only hooks averaging >50ms
bash tools/hook-perf.sh --days 7     # last 7 days
```

**Data source:** Hook stderr log lines. Every hook already writes `[Supercharger] hookname: message` to stderr. Upgrade: add optional timing.

**Timing instrumentation (in `lib-suppress.sh`):**
```bash
# Add to init_hook_suppress():
HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
```

Hooks that want profiling can compute elapsed on exit. But the profiler can also infer timing from audit trail timestamps (consecutive entries = elapsed time for the hook between them).

**Output format:**
```
Hook Performance Report (last 24h)
─────────────────────────────────────────────────────
Hook                      Calls   Avg(ms)  Total(s)  Mode
safety.sh                   142      12      1.7     sync
code-security-scanner.sh     38      89      3.4     asyncRewake
agent-router.sh              24      34      0.8     sync
economy-reinforce.sh         48       8      0.4     sync
budget-cap.sh                67      15      1.0     async
─────────────────────────────────────────────────────
Total hook overhead: 8.3s across 319 calls (avg 26ms/call)
Sync hooks (blocking): 3.2s across 214 calls (avg 15ms/call)
```

**Flags:**
- `--slow` — only show hooks averaging >50ms
- `--days N` — lookback window (default: 1)
- `--session` — filter to most recent session only
- `--json` — machine-readable output

---

## Shared Infrastructure

### A. Session Cost Accumulator (`$SCOPE_DIR/.session-cost`)

Single source of truth for session cost. Written by multiple hooks, read by many.

**Writers:**
- `budget-cap.sh` PostToolUse — primary accumulator
- `subagent-cost.sh` SubagentStop — adds subagent costs

**Readers:**
- `budget-cap.sh` UserPromptSubmit — check against cap
- `cost-forecast.sh` PreToolUse — read avg_per_turn for estimates
- `statusline.sh` — display budget progress
- `session-checkpoint.sh` — include cost in checkpoint
- `session-memory-inject.sh` — include last_cost in resume

**Format:**
```json
{"total_usd": 3.42, "turn_count": 18, "avg_per_turn": 0.19, "last_updated": "2026-04-22T14:30:00Z", "subagent_total": 1.15}
```

**Atomic writes:** Write to `.session-cost.tmp`, then `mv` to `.session-cost`. Prevents partial reads.

**Pricing table:** Embedded as an associative array in budget-cap.sh. When Anthropic changes pricing, `tools/update.sh` pulls the latest version of the script (which includes updated prices). No separate config file — single source of truth in the script itself.

### B. Timing Instrumentation (`lib-suppress.sh`)

Add `HOOK_START_MS` to the shared init function. Backward compatible — existing hooks don't need to use it.

```bash
# Added to init_hook_suppress():
if command -v python3 >/dev/null 2>&1; then
  HOOK_START_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
else
  HOOK_START_MS=0
fi
```

Hooks that want to report timing add one line before exit:
```bash
# Optional — only hooks that opt in
if [ "$HOOK_START_MS" -gt 0 ]; then
  HOOK_END_MS=$(python3 -c "import time; print(int(time.time()*1000))" 2>/dev/null || echo "0")
  echo "[Supercharger] my-hook: ${msg} elapsed=$((HOOK_END_MS - HOOK_START_MS))ms" >&2
fi
```

### C. `.supercharger.json` Schema Extension

New optional fields for project-level configuration:

```json
{
  "roles": ["developer"],
  "economy": "lean",
  "hints": "React + Tailwind, use pnpm",
  "budget": 5.00,
  "autoEconomy": true,
  "thinkingControl": true,
  "forecastTurnsPerAgent": 10
}
```

All fields optional. All have sensible defaults when absent:
- `budget`: no cap (tracking still runs)
- `autoEconomy`: `true`
- `thinkingControl`: `true`
- `forecastTurnsPerAgent`: `10`

Read by `project-config.sh` on SessionStart — already exists, just needs to parse new fields and write to scope files.

---

## Hook Registration Summary

### New hooks (Full mode)

| Hook | Event | Matcher | Flags |
|---|---|---|---|
| `budget-cap.sh` | `PostToolUse` | `*` | `async` |
| `budget-cap.sh check` | `PreToolUse` | `*` | (sync — must block) |
| `cost-forecast.sh` | `PreToolUse` | `Agent` | |
| `subagent-cost.sh start` | `SubagentStart` | | `async` |
| `subagent-cost.sh stop` | `SubagentStop` | | |
| `thinking-budget.sh` | `UserPromptSubmit` | | |
| `rate-limit-advisor.sh` | `UserPromptSubmit` | | `async` |
| `session-checkpoint.sh` | `PostToolUse` | `Write,Edit,Bash` | `async` |

### New hooks (Safe mode)

| Hook | Event | Matcher | Flags |
|---|---|---|---|
| `cache-health.sh` | `PostToolUse` | `*` | `async` |

### Upgraded hooks (no new registration)

| Hook | Change |
|---|---|
| `adaptive-economy.sh` | Add auto-switch logic + session-history learning |
| `statusline.sh` | Add rate-limit burn projection + budget display + cache coloring |
| `session-memory-inject.sh` | Add checkpoint recovery + enriched resume |
| `session-memory-write.sh` | Add checkpoint cleanup on normal exit |
| `session-complete.sh` | Add checkpoint cleanup |
| `project-config.sh` | Parse new `.supercharger.json` fields |
| `lib-suppress.sh` | Add timing instrumentation |

### New tools

| Tool | Purpose |
|---|---|
| `tools/hook-perf.sh` | Hook performance profiler |

### Hook count

| Mode | Current | After v2 | Delta |
|---|---|---|---|
| Safe | 9 | 10 | +1 (cache-health) |
| Full | 52 | 60 | +8 |
| Tools | 15 | 16 | +1 (hook-perf) |

---

## Delivery Waves

Each wave is independently shippable and testable.

### Wave 1: Cost Shield
- `budget-cap.sh` (PostToolUse accumulator + PreToolUse blocker)
- `cost-forecast.sh` (PreToolUse Agent)
- `cache-health.sh` (PostToolUse sampled)
- `subagent-cost.sh` (SubagentStart + SubagentStop)
- Shared: `.session-cost` accumulator, pricing table
- Statusline: budget display, cache coloring
- Tests: cost accumulation accuracy, budget blocking behavior, forecast calculation, cache degradation detection, subagent cost aggregation

### Wave 2: Smart Adaptation
- `adaptive-economy.sh` upgrade (auto-switch + history learning)
- `thinking-budget.sh` (UserPromptSubmit)
- `rate-limit-advisor.sh` (UserPromptSubmit async)
- Statusline: burn rate projection
- Tests: auto-switch triggers, history persistence, thinking classification accuracy, burn rate calculation, dedup behavior

### Wave 3: Session Intelligence
- `session-checkpoint.sh` (PostToolUse async)
- `session-memory-inject.sh` upgrade (checkpoint recovery + enriched resume)
- `tools/hook-perf.sh` (CLI tool)
- Shared: `lib-suppress.sh` timing instrumentation
- Tests: checkpoint write/recovery cycle, stale cleanup, enrichment accuracy, profiler output format

---

## Explicit Non-Goals

| Excluded | Reason |
|---|---|
| Model-tier routing (Haiku/Sonnet/Opus) | Claude Code doesn't expose model selection to hooks |
| Per-project hook overrides | Adds hook resolution complexity; separate feature |
| Team/multi-user analytics | Requires shared storage; breaks "nothing leaves your machine" |
| Visual dashboard / TUI | Requires web server or TUI framework; out of scope for Bash+Python |
| Wave execution / task parallelism | Requires deep Claude agent system integration |
| API-level thinking budget control | Not exposed to hooks; using prompt-level nudges instead |

---

## Testing Strategy

Each new hook gets a dedicated test file following existing patterns (`tests/test-{hookname}.sh`).

**Wave 1 tests:**
- `test-budget-cap.sh`: accumulation math, 80% warning, 100% block, read-only escape hatch, no-cap passthrough
- `test-cost-forecast.sh`: estimate calculation, skip-when-cheap, skip-when-no-data
- `test-cache-health.sh`: rolling window, 3-consecutive-drop trigger, dedup, color thresholds
- `test-subagent-cost.sh`: start/stop lifecycle, JSONL format, aggregation into session-cost

**Wave 2 tests:**
- `test-adaptive-economy-v2.sh`: auto-switch at thresholds, history write/read, opt-out, suggest-not-auto for low context
- `test-thinking-budget.sh`: low/medium/high classification, agent-router integration, stateless behavior
- `test-rate-limit-advisor.sh`: burn rate math, <30m trigger, dedup by band

**Wave 3 tests:**
- `test-session-checkpoint.sh`: write on file-modify, overwrite behavior, recovery inject, stale cleanup, normal-exit cleanup
- `test-session-resume-v2.sh`: enrichment fields, token budget cap, graceful degradation when git unavailable
- `test-hook-perf.sh`: output format, --slow filter, --json flag, timing extraction from stderr

**Target:** ~40 new tests across 9 test files. Total suite: ~330 tests.
