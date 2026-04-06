# Agent Routing: Enforced Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two hooks — `agent-router.sh` (classifies prompt, injects directive) and `agent-gate.sh` (blocks wrong agent dispatch) — to enforce ~99% correct agent selection without any user behavior change.

**Architecture:** UserPromptSubmit hook classifies the first prompt per session and writes a state file + injects `additionalContext`. A PreToolUse hook on the Agent tool reads the state file and blocks dispatch if the wrong agent is chosen. Scope-guard's clear mode removes the state file on Stop. Both hooks follow the existing pattern in `hooks/scope-guard.sh`.

**Tech Stack:** Bash, Python 3 (inline snippets), Claude Code hook JSON protocol

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `hooks/agent-router.sh` | Create | Classify first prompt, write `.agent-route`, inject additionalContext |
| `hooks/agent-gate.sh` | Create | Block Agent dispatch if subagent_type doesn't match stored classification |
| `hooks/scope-guard.sh:152` | Modify | Extend clear mode to also delete `.agent-route` |
| `lib/hooks.sh:25,190` | Modify | Wire 2 new hooks; update count (+9→+11 standard) |
| `configs/universal/CLAUDE.md` | Modify | Add mandatory agent routing rule |
| `tests/test-agent-router.sh` | Create | 8 tests for router behaviour |
| `tests/test-agent-gate.sh` | Create | 5 tests for gate behaviour |
| `tests/test-scope-guard.sh` | Modify | Add test that `.agent-route` is cleared on `clear` |

---

## Key Protocol Facts

**UserPromptSubmit hook stdin:**
```json
{ "session_id": "...", "hook_event_name": "UserPromptSubmit", "prompt": "user text here", "cwd": "..." }
```
`prompt` is **top-level** — not nested under `input`.

**UserPromptSubmit hook stdout (to inject context):**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "text injected into Claude context invisibly"
  }
}
```

**PreToolUse hook stdin for Agent tool:**
```json
{ "tool_name": "Agent", "tool_input": { "subagent_type": "Sherlock Holmes (Detective)", "prompt": "..." } }
```

**PreToolUse block:** exit 2 + stderr message (consistent with all other hooks in this project).

**State file:** `~/.claude/supercharger/scope/.agent-route` — one line, the agent name (e.g. `Sherlock Holmes (Detective)`).

---

## Task 1: Write failing tests for agent-router.sh

**Files:**
- Create: `tests/test-agent-router.sh`

- [ ] **Step 1: Create the test file**

```bash
cat > /path/to/repo/tests/test-agent-router.sh << 'EOF'
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROUTER="$REPO_DIR/hooks/agent-router.sh"

# Test 1: debug prompt → Sherlock Holmes
begin_test "agent-router: error prompt classifies as Sherlock Holmes"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception at line 42"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Sherlock"; then pass
else fail ".agent-route not written or wrong: $ROUTE"; fi
teardown_test_home

# Test 2: review prompt → Gordon Ramsay
begin_test "agent-router: review prompt classifies as Gordon Ramsay"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"review this file for security issues"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Gordon"; then pass
else fail ".agent-route wrong: $ROUTE"; fi
teardown_test_home

# Test 3: build prompt → Tony Stark
begin_test "agent-router: implement prompt classifies as Tony Stark"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"implement a login function in auth.py"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Tony"; then pass
else fail ".agent-route wrong: $ROUTE"; fi
teardown_test_home

# Test 4: write prompt → Ernest Hemingway
begin_test "agent-router: write prompt classifies as Ernest Hemingway"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"write a README for this project"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if echo "$ROUTE" | grep -qi "Ernest"; then pass
else fail ".agent-route wrong: $ROUTE"; fi
teardown_test_home

# Test 5: ambiguous prompt → no .agent-route written
begin_test "agent-router: ambiguous prompt writes no .agent-route"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"help me"}' | bash "$ROUTER" >/dev/null 2>&1
if [ ! -f "$HOME/.claude/supercharger/scope/.agent-route" ]; then pass
else fail ".agent-route should not be written for ambiguous prompt"; fi
teardown_test_home

# Test 6: second call same session is idempotent
begin_test "agent-router: second call does not overwrite .agent-route"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"debug this stack trace"}' | bash "$ROUTER" >/dev/null 2>&1
FIRST=$(cat "$HOME/.claude/supercharger/scope/.agent-route")
echo '{"prompt":"write a blog post"}' | bash "$ROUTER" >/dev/null 2>&1
SECOND=$(cat "$HOME/.claude/supercharger/scope/.agent-route")
if [ "$FIRST" = "$SECOND" ]; then pass
else fail ".agent-route overwritten: first=$FIRST second=$SECOND"; fi
teardown_test_home

# Test 7: stdout is valid JSON with additionalContext
begin_test "agent-router: stdout is valid JSON with additionalContext"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
OUTPUT=$(echo '{"prompt":"debug this error"}' | bash "$ROUTER" 2>/dev/null)
CONTEXT=$(echo "$OUTPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d['hookSpecificOutput']['additionalContext'])
except Exception as e:
    print('')
" 2>/dev/null || echo "")
if echo "$CONTEXT" | grep -q "SUPERCHARGER ROUTING"; then pass
else fail "additionalContext missing or malformed: $OUTPUT"; fi
teardown_test_home

# Test 8: .agent-route contains exact agent name
begin_test "agent-router: .agent-route contains exact agent name string"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"prompt":"there is a null pointer exception"}' | bash "$ROUTER" >/dev/null 2>&1
ROUTE=$(cat "$HOME/.claude/supercharger/scope/.agent-route" 2>/dev/null || echo "")
if [ "$ROUTE" = "Sherlock Holmes (Detective)" ]; then pass
else fail "Expected 'Sherlock Holmes (Detective)', got: '$ROUTE'"; fi
teardown_test_home

report
EOF
chmod +x tests/test-agent-router.sh
```

- [ ] **Step 2: Run tests — verify they all fail**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
bash tests/test-agent-router.sh
```

Expected: 8 failed, 0 passed (hook script doesn't exist yet)

---

## Task 2: Implement agent-router.sh

**Files:**
- Create: `hooks/agent-router.sh`

- [ ] **Step 1: Create the hook**

```bash
cat > hooks/agent-router.sh << 'EOF'
#!/usr/bin/env bash
# Claude Supercharger — Agent Router
# Event: UserPromptSubmit | Matcher: (none)
# Classifies the first user prompt and injects a routing directive into
# Claude's context. Stores result in .agent-route for agent-gate.sh to enforce.

set -euo pipefail

SUPERCHARGER_DIR="$HOME/.claude/supercharger"
SCOPE_DIR="$SUPERCHARGER_DIR/scope"
mkdir -p "$SCOPE_DIR"

ROUTE_FILE="$SCOPE_DIR/.agent-route"

# Only classify once per session (idempotent)
[ -f "$ROUTE_FILE" ] && exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('prompt', ''))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$PROMPT" ] && exit 0

AGENT=""

# Ordered by specificity — most specific first
if echo "$PROMPT" | grep -qiE '(error|exception|stack trace|not working|broken|failing|crash|null pointer|undefined is not|bug at line|segfault|traceback|exit code [0-9])'; then
  AGENT="Sherlock Holmes (Detective)"
elif echo "$PROMPT" | grep -qiE '(review|security issue|code smell|what do you think of|look at this|check my|critique|audit this|LGTM)'; then
  AGENT="Gordon Ramsay (Critic)"
elif echo "$PROMPT" | grep -qiE '(analyze|query|SQL|CSV|how many|metrics|report|data file|show me the|dataset|aggregate|pivot|histogram)'; then
  AGENT="Albert Einstein (Analyst)"
elif echo "$PROMPT" | grep -qiE '(write|draft|blog|README|document|explain to|email|release notes|marketing|copywriting|prose)'; then
  AGENT="Ernest Hemingway (Writer)"
elif echo "$PROMPT" | grep -qiE '(design|architect|before we build|system design|how should I structure|ADR|architecture decision|diagram)'; then
  AGENT="Leonardo da Vinci (Architect)"
elif echo "$PROMPT" | grep -qiE '(plan|break down|estimate|how should I|what.s the best approach|help me think|roadmap|prioritize|scope this)'; then
  AGENT="Sun Tzu (Strategist)"
elif echo "$PROMPT" | grep -qiE '(what is|how does|compare|difference between|research|best way to|explain.*concept|versus|trade.?off)'; then
  AGENT="Marie Curie (Scientist)"
elif echo "$PROMPT" | grep -qiE '(build|implement|add feature|fix|create|refactor|write a function|write a test|make it|update the)'; then
  AGENT="Tony Stark (Engineer)"
fi

[ -z "$AGENT" ] && exit 0

echo "$AGENT" > "$ROUTE_FILE"

ROUTE_AGENT="$AGENT" python3 -c "
import json, os
agent = os.environ['ROUTE_AGENT']
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'UserPromptSubmit',
        'additionalContext': f'[SUPERCHARGER ROUTING] Classified as: {agent}. Dispatch this agent with the Agent tool as your first action. Do not reason about it — just dispatch.'
    }
}))
"

exit 0
EOF
chmod +x hooks/agent-router.sh
```

- [ ] **Step 2: Run tests — verify they all pass**

```bash
bash tests/test-agent-router.sh
```

Expected: 8 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add hooks/agent-router.sh tests/test-agent-router.sh
git commit -m "feat(hooks): add agent-router — classifies first prompt and injects routing directive"
```

---

## Task 3: Write failing tests for agent-gate.sh

**Files:**
- Create: `tests/test-agent-gate.sh`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/test-agent-gate.sh << 'EOF'
#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

GATE="$REPO_DIR/hooks/agent-gate.sh"

# Test 1: no .agent-route → exits 0 (gate open)
begin_test "agent-gate: no .agent-route exits 0 (gate open)"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' \
  | bash "$GATE" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass
else fail "Should exit 0 when no .agent-route exists"; fi
teardown_test_home

# Test 2: correct agent → exits 0
begin_test "agent-gate: correct agent dispatched exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock Holmes (Detective)"}}' \
  | bash "$GATE" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass
else fail "Should exit 0 for correct agent"; fi
teardown_test_home

# Test 3: wrong agent → exits 2
begin_test "agent-gate: wrong agent dispatched exits 2"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Tony Stark (Engineer)"}}' \
  | bash "$GATE" >/dev/null 2>&1
if [ $? -eq 2 ]; then pass
else fail "Should exit 2 for wrong agent (got $?)"; fi
teardown_test_home

# Test 4: case-insensitive match
begin_test "agent-gate: case-insensitive match works"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Tony Stark (Engineer)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"tony stark (engineer)"}}' \
  | bash "$GATE" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass
else fail "Should match case-insensitively"; fi
teardown_test_home

# Test 5: partial match on first word works
begin_test "agent-gate: partial match on first word exits 0"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
echo '{"tool_name":"Agent","tool_input":{"subagent_type":"Sherlock"}}' \
  | bash "$GATE" >/dev/null 2>&1
if [ $? -eq 0 ]; then pass
else fail "Should match on first word 'Sherlock'"; fi
teardown_test_home

report
EOF
chmod +x tests/test-agent-gate.sh
```

- [ ] **Step 2: Run tests — verify they all fail**

```bash
bash tests/test-agent-gate.sh
```

Expected: 5 failed, 0 passed (hook script doesn't exist yet)

---

## Task 4: Implement agent-gate.sh

**Files:**
- Create: `hooks/agent-gate.sh`

- [ ] **Step 1: Create the hook**

```bash
cat > hooks/agent-gate.sh << 'EOF'
#!/usr/bin/env bash
# Claude Supercharger — Agent Gate
# Event: PreToolUse | Matcher: Agent
# Reads the stored agent classification and blocks dispatch of any other agent.

set -euo pipefail

SCOPE_DIR="$HOME/.claude/supercharger/scope"
ROUTE_FILE="$SCOPE_DIR/.agent-route"

# No classification stored — gate open
[ -f "$ROUTE_FILE" ] || exit 0

STORED_AGENT=$(cat "$ROUTE_FILE" 2>/dev/null || echo "")
[ -z "$STORED_AGENT" ] && exit 0

INPUT=$(cat)
DISPATCHED=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('subagent_type', ''))
except:
    print('')
" 2>/dev/null || echo "")

[ -z "$DISPATCHED" ] && exit 0

# Match on first word of stored agent name (case-insensitive)
# "Sherlock Holmes (Detective)" → check if "sherlock" appears in dispatched
FIRST_WORD=$(echo "$STORED_AGENT" | awk '{print tolower($1)}')
DISPATCHED_LOWER=$(echo "$DISPATCHED" | tr '[:upper:]' '[:lower:]')

if echo "$DISPATCHED_LOWER" | grep -qF "$FIRST_WORD"; then
  exit 0
fi

echo "[Supercharger] Agent routing: dispatch '${STORED_AGENT}' for this task (not '${DISPATCHED}')" >&2
exit 2
EOF
chmod +x hooks/agent-gate.sh
```

- [ ] **Step 2: Run tests — verify all 5 pass**

```bash
bash tests/test-agent-gate.sh
```

Expected: 5 passed, 0 failed

- [ ] **Step 3: Commit**

```bash
git add hooks/agent-gate.sh tests/test-agent-gate.sh
git commit -m "feat(hooks): add agent-gate — blocks wrong agent dispatch via PreToolUse"
```

---

## Task 5: Extend scope-guard.sh clear mode + update test

**Files:**
- Modify: `hooks/scope-guard.sh:152`
- Modify: `tests/test-scope-guard.sh` (extend test 4)

The clear mode currently removes `.snapshot` and `.contract`. It must also remove `.agent-route` so routing state resets on Stop.

- [ ] **Step 1: Update the clear mode in scope-guard.sh**

Find this line in `hooks/scope-guard.sh` (inside the `clear` block, ~line 152):
```bash
  rm -f "$SNAPSHOT_FILE" "$CONTRACT_FILE"
```

Replace with:
```bash
  rm -f "$SNAPSHOT_FILE" "$CONTRACT_FILE" "$SCOPE_DIR/.agent-route"
```

- [ ] **Step 2: Update test 4 in test-scope-guard.sh to verify .agent-route is also cleared**

Find test 4 in `tests/test-scope-guard.sh`:
```bash
# Test 4: clear removes state files
begin_test "scope-guard: clear removes snapshot and contract"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "scope:general" > "$HOME/.claude/supercharger/scope/.contract"
echo "commit:abc" > "$HOME/.claude/supercharger/scope/.snapshot"
bash "$SCOPE_GUARD" clear
if [ ! -f "$HOME/.claude/supercharger/scope/.snapshot" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.contract" ]; then pass
else fail "files not cleared"; fi
teardown_test_home
```

Replace with:
```bash
# Test 4: clear removes state files including .agent-route
begin_test "scope-guard: clear removes snapshot, contract, and agent-route"
setup_test_home
mkdir -p "$HOME/.claude/supercharger/scope"
echo "scope:general" > "$HOME/.claude/supercharger/scope/.contract"
echo "commit:abc" > "$HOME/.claude/supercharger/scope/.snapshot"
echo "Sherlock Holmes (Detective)" > "$HOME/.claude/supercharger/scope/.agent-route"
bash "$SCOPE_GUARD" clear
if [ ! -f "$HOME/.claude/supercharger/scope/.snapshot" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.contract" ] && \
   [ ! -f "$HOME/.claude/supercharger/scope/.agent-route" ]; then pass
else fail "files not cleared"; fi
teardown_test_home
```

- [ ] **Step 3: Run scope-guard tests — verify all pass**

```bash
bash tests/test-scope-guard.sh
```

Expected: 5 passed, 0 failed (test 4 description changed, same count)

- [ ] **Step 4: Commit**

```bash
git add hooks/scope-guard.sh tests/test-scope-guard.sh
git commit -m "fix(hooks): clear .agent-route on session end in scope-guard clear mode"
```

---

## Task 6: Wire hooks in lib/hooks.sh

**Files:**
- Modify: `lib/hooks.sh:25,190`

Two changes: add 2 hooks to `get_hooks_for_mode`, update `count_installed_hooks`.

- [ ] **Step 1: Add hooks to get_hooks_for_mode**

In `lib/hooks.sh`, find this block (lines ~22-25):
```bash
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot")
    hooks+=("UserPromptSubmit||${hooks_dir}/scope-guard.sh contract")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh")
```

Add two lines after the `scope-guard.sh contract` line:
```bash
    hooks+=("SessionStart||${hooks_dir}/scope-guard.sh snapshot")
    hooks+=("UserPromptSubmit||${hooks_dir}/scope-guard.sh contract")
    hooks+=("UserPromptSubmit||${hooks_dir}/agent-router.sh")
    hooks+=("PreToolUse|Agent|${hooks_dir}/agent-gate.sh")
    hooks+=("SessionStart||${hooks_dir}/update-check.sh")
```

- [ ] **Step 2: Update count_installed_hooks**

Find the standard mode count block (~line 187):
```bash
  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    # notify, git-safety, enforce-pkg-manager, audit-trail,
    # scope-guard(check+snapshot+contract), project-config, update-check
    count=$((count + 9))
```

Replace with:
```bash
  if [[ "$mode" == "standard" || "$mode" == "full" ]]; then
    # notify, git-safety, enforce-pkg-manager, audit-trail,
    # scope-guard(check+snapshot+contract), project-config, update-check,
    # agent-router, agent-gate
    count=$((count + 11))
```

- [ ] **Step 3: Verify hook counts match get_hooks_for_mode**

```bash
cd /Users/radiustheme/GithubRepos/claude-supercharger
source lib/hooks.sh

echo "count standard no-dev:  $(count_installed_hooks standard false)"   # expect 12
echo "count standard dev:     $(count_installed_hooks standard true)"    # expect 13
echo "count full no-dev:      $(count_installed_hooks full false)"       # expect 16
echo "count full dev:         $(count_installed_hooks full true)"        # expect 17

echo "actual standard no-dev:  $(get_hooks_for_mode standard false /tmp | wc -l | tr -d ' ')"   # expect 12
echo "actual standard dev:     $(get_hooks_for_mode standard true /tmp | wc -l | tr -d ' ')"   # expect 13
echo "actual full no-dev:      $(get_hooks_for_mode full false /tmp | wc -l | tr -d ' ')"      # expect 16
echo "actual full dev:         $(get_hooks_for_mode full true /tmp | wc -l | tr -d ' ')"       # expect 17
```

All 8 lines must agree (count == actual).

- [ ] **Step 4: Commit**

```bash
git add lib/hooks.sh
git commit -m "feat(lib): wire agent-router and agent-gate hooks, update count to +11"
```

---

## Task 7: Add routing rule to configs/universal/CLAUDE.md

**Files:**
- Modify: `configs/universal/CLAUDE.md`

- [ ] **Step 1: Append the agent routing rule**

Add at the end of `configs/universal/CLAUDE.md` (after the last line):
```markdown

## Agent Routing
When [SUPERCHARGER ROUTING] appears in context, dispatch that exact agent
as your first action. Do not reason about it — just dispatch.
```

- [ ] **Step 2: Verify the file ends correctly**

```bash
tail -6 configs/universal/CLAUDE.md
```

Expected output:
```
## Agent Routing
When [SUPERCHARGER ROUTING] appears in context, dispatch that exact agent
as your first action. Do not reason about it — just dispatch.
```

- [ ] **Step 3: Run the full test suite to verify nothing is broken**

```bash
bash tests/run.sh
```

Expected: all tests pass, 0 failed

- [ ] **Step 4: Commit**

```bash
git add configs/universal/CLAUDE.md
git commit -m "feat(config): add mandatory agent routing rule to CLAUDE.md template"
```

---

## Self-Review

**Spec coverage:**
- [x] agent-router.sh classifies 8 agents with ordered regex — Tasks 1-2
- [x] agent-router.sh is idempotent (first message only) — Test 6, Task 2 implementation
- [x] agent-router.sh injects `hookSpecificOutput.additionalContext` JSON — Test 7, Task 2
- [x] agent-router.sh falls through silently on ambiguous prompts — Test 5, Task 2
- [x] agent-gate.sh exits 0 when no classification exists — Test 1, Task 4
- [x] agent-gate.sh exits 0 for correct agent — Test 2, Task 4
- [x] agent-gate.sh exits 2 for wrong agent — Test 3, Task 4
- [x] Case-insensitive first-word matching — Tests 4-5, Task 4
- [x] scope-guard clear deletes `.agent-route` — Task 5
- [x] Hooks wired in lib/hooks.sh standard+full — Task 6
- [x] count_installed_hooks updated — Task 6
- [x] CLAUDE.md routing rule added — Task 7

**Placeholder scan:** None found.

**Consistency check:**
- State file path: `$SCOPE_DIR/.agent-route` in router, gate reads `$HOME/.claude/supercharger/scope/.agent-route` — same resolved path ✓
- Agent names in test expectations match frontmatter `name:` values exactly ✓
- `count + 9` → `count + 11` (adds 2: agent-router + agent-gate) ✓
- `get_hooks_for_mode` adds 2 entries in standard block → count +2 matches ✓
