# Agent Routing: Enforced Dispatch Design

**Date:** 2026-04-06
**Status:** Approved
**Goal:** Enforce correct agent selection without any user behavior change — ~99% accuracy for classifiable prompts, silent fallthrough for ambiguous ones.

---

## Problem

Claude Code's agent dispatch is pure judgment: Claude reads 9 agent `description:` fields and decides which subagent to invoke. Accuracy is ~70%. The system is advisory, not enforced — Claude can and does choose the wrong agent for obvious cases like "debug this stack trace" or "review this file."

## Solution

Two hooks working in layers:

- **Layer A** (`agent-router.sh`, UserPromptSubmit): classifies the first prompt, stores the result, injects a mandatory routing directive into Claude's context
- **Layer B** (`agent-gate.sh`, PreToolUse on Agent tool): reads the stored classification, verifies what Claude is actually dispatching, blocks with exit 2 if wrong

Together: guidance + enforcement. Layer A alone gets ~85%. Both layers together get ~99% for classifiable prompts.

---

## Architecture & Data Flow

```
User types first message
        │
        ▼
UserPromptSubmit → agent-router.sh
        ├─ .agent-route exists? → exit 0 (already classified this session)
        ├─ Extract prompt from stdin JSON
        ├─ Empty prompt → exit 0
        ├─ Run ordered regex classification (9 rules, most specific first)
        ├─ Confident match:
        │       write agent name → ~/.claude/supercharger/scope/.agent-route
        │       stdout: {"additionalContext": "[SUPERCHARGER ROUTING] ..."}
        └─ No match → exit 0 silently (uncertain, gate stays open)
        │
        ▼
Claude reads additionalContext, dispatches an agent
        │
        ▼
PreToolUse (matcher: Agent) → agent-gate.sh
        ├─ .agent-route missing → exit 0 (no classification, allow any agent)
        ├─ Read stored agent name
        ├─ Extract tool_input.subagent_type from stdin JSON
        ├─ Case-insensitive substring match
        ├─ Match → exit 0
        └─ Mismatch → exit 2
                stderr: "[Supercharger] Agent routing: dispatch '<stored>' not '<attempted>'"
                Claude retries with correct agent
        │
        ▼
Stop → scope-guard.sh clear
        └─ rm .snapshot .contract .agent-route (state cleared for next session)
```

**State file:** `~/.claude/supercharger/scope/.agent-route`
One line: the agent's `name:` frontmatter value (e.g. `Tony Stark (Engineer)`).
Written once per session by router. Read by gate. Cleared on Stop.

---

## Classification Rules

Ordered by specificity — most specific checked first to prevent broad patterns swallowing precise ones.

| Priority | Pattern (case-insensitive) | Agent |
|----------|---------------------------|-------|
| 1 | `error\|exception\|stack trace\|not working\|broken\|failing\|crash\|null pointer\|undefined\|bug at line\|segfault\|traceback\|exit code` | Sherlock Holmes (Detective) |
| 2 | `review\|security issue\|code smell\|what do you think of\|look at this\|check my\|critique\|audit this\|LGTM` | Gordon Ramsay (Critic) |
| 3 | `analyze\|query\|SQL\|CSV\|how many\|metrics\|report\|data file\|show me the\|dataset\|aggregate\|pivot\|histogram` | Albert Einstein (Analyst) |
| 4 | `write\|draft\|blog\|README\|document\|explain to\|email\|release notes\|marketing\|copywriting\|prose` | Ernest Hemingway (Writer) |
| 5 | `design\|architect\|before we build\|system design\|how should I structure\|ADR\|architecture decision\|diagram` | Leonardo da Vinci (Architect) |
| 6 | `plan\|break down\|estimate\|how should I\|what.s the best approach\|help me think\|roadmap\|prioritize\|scope this` | Sun Tzu (Strategist) |
| 7 | `what is\|how does\|compare\|difference between\|research\|best way to\|explain.*concept\|versus\|trade.?off` | Marie Curie (Scientist) |
| 8 | `build\|implement\|add feature\|fix\|create\|refactor\|write a function\|write a test\|make it\|update the` | Tony Stark (Engineer) |
| — | No match | Fall through (no routing) |

**Steve Jobs (Generalist) is never explicitly routed.** He is Claude's natural fallback when nothing else fits. Routing to him explicitly adds no value.

**"fix" appears at priority 8 (Engineer), but "fix the error/crash/bug" hits priority 1 (Detective) first.** Order enforces this correctly.

---

## Hook Specifications

### agent-router.sh

- **Event:** UserPromptSubmit
- **Matcher:** (none — all prompts)
- **Input:** stdin JSON `{ "input": { "prompt": "..." } }`
- **Output (on match):** stdout JSON `{ "additionalContext": "[SUPERCHARGER ROUTING] Classified as: <agent>. Dispatch this agent with the Agent tool as your first action. Do not reason about it — just dispatch." }`
- **Output (no match):** nothing
- **Side effect:** writes `~/.claude/supercharger/scope/.agent-route` on match
- **Idempotent:** exits 0 immediately if `.agent-route` already exists

### agent-gate.sh

- **Event:** PreToolUse
- **Matcher:** Agent
- **Input:** stdin JSON `{ "tool_name": "Agent", "tool_input": { "subagent_type": "..." } }`
- **Output (on block):** stderr `[Supercharger] Agent routing: dispatch '<stored-agent>' for this task (not '<attempted-agent>')`
- **Exit codes:** 0 = allow, 2 = block
- **Match logic:** case-insensitive substring — stored value checked against dispatched value. `"Sherlock"` matches `"Sherlock Holmes (Detective)"`.

---

## Wiring Changes

### lib/hooks.sh — get_hooks_for_mode()

Add to standard + full block (after scope-guard contract line):
```bash
hooks+=("UserPromptSubmit||${hooks_dir}/agent-router.sh")
hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh")
```

### lib/hooks.sh — count_installed_hooks()

Standard mode: `+9` → `+11` (two new hooks added)
Full mode: unchanged relative increment (already counted from standard base)

### hooks/scope-guard.sh — clear mode

Extend the `rm` line to include `.agent-route`:
```bash
rm -f "$SNAPSHOT_FILE" "$CONTRACT_FILE" "$SCOPE_DIR/.agent-route"
```

### configs/universal/CLAUDE.md

Add after existing rules:
```markdown
## Agent Routing
When [SUPERCHARGER ROUTING] appears in context, dispatch that exact agent
as your first action. Do not reason about it — just dispatch.
```

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Follow-up message ("now fix it") | `.agent-route` exists → router exits 0, gate uses first classification |
| User says "use the debugger" explicitly | Router classifies normally; if Claude dispatches Sherlock, gate allows |
| Claude dispatches wrong agent, blocked, retries wrong again | Gate blocks every incorrect attempt until correct agent dispatched |
| Claude handles task directly without agent dispatch | PreToolUse on Agent never fires — gate never triggers |
| Ambiguous prompt ("help", "ok", "continue") | No regex match → no state written → gate stays open |
| Non-English prompt | Regex won't match → falls through silently |
| No agents installed | Gate checks `.agent-route` but Agent tool never called — harmless |

---

## Test Coverage

### tests/test-agent-router.sh (8 cases)

1. Debug prompt → classifies as Sherlock Holmes, writes `.agent-route`
2. Review prompt → classifies as Gordon Ramsay
3. Build prompt → classifies as Tony Stark
4. Write/doc prompt → classifies as Ernest Hemingway
5. Ambiguous prompt ("help me") → no `.agent-route` written, exits 0
6. Second call same session → `.agent-route` unchanged (idempotent)
7. Router stdout is valid JSON with `additionalContext` key
8. `.agent-route` content matches agent name exactly

### tests/test-agent-gate.sh (5 cases)

1. No `.agent-route` → exits 0 (gate open)
2. Correct agent dispatched → exits 0
3. Wrong agent dispatched → exits 2 + stderr names correct agent
4. Case-insensitive match works (`"tony stark"` matches `"Tony Stark (Engineer)"`)
5. Partial match works (`"Sherlock"` matches `"Sherlock Holmes (Detective)"`)

---

## Files Changed

| File | Change type |
|------|-------------|
| `hooks/agent-router.sh` | New |
| `hooks/agent-gate.sh` | New |
| `hooks/scope-guard.sh` | Modify — extend clear mode |
| `lib/hooks.sh` | Modify — add 2 hooks, update count |
| `configs/universal/CLAUDE.md` | Modify — add routing rule |
| `tests/test-agent-router.sh` | New |
| `tests/test-agent-gate.sh` | New |

---

## What This Does Not Do

- Does not intercept follow-up messages within a session (by design)
- Does not route to Steve Jobs explicitly (he is the natural fallback)
- Does not require any user behavior change
- Does not add latency (pure shell + regex, no API calls)
- Does not affect sessions where no agent is dispatched
