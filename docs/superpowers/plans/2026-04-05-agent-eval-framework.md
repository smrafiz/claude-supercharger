# Agent Eval Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `bash tests/eval-agents.sh` — a zero-intervention eval that sends real prompts to each of the 9 agents via `claude` CLI, scores responses against rubrics, and prints a PASS/PARTIAL/FAIL report.

**Architecture:** A single bash script (`eval-agents.sh`) creates a disposable temp project, loads agent definitions from `configs/agents/`, runs scenarios using `claude --print --agents <json> --agent <name>`, scores responses using Python string matching, then prints a structured report. Nine JSON files in `tests/eval-prompts/` define prompts and rubrics per agent.

**Tech Stack:** Bash, `claude` CLI (already installed), Python 3 (already used in project), JSON

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `tests/eval-agents.sh` | Create | Main runner — scaffold, invoke, score, report |
| `tests/eval-prompts/debugger.json` | Create | 2 scenarios + rubrics for debugger agent |
| `tests/eval-prompts/reviewer.json` | Create | 2 scenarios + rubrics for reviewer agent |
| `tests/eval-prompts/code-helper.json` | Create | 2 scenarios + rubrics for code-helper agent |
| `tests/eval-prompts/architect.json` | Create | 2 scenarios + rubrics for architect agent |
| `tests/eval-prompts/planner.json` | Create | 2 scenarios + rubrics for planner agent |
| `tests/eval-prompts/researcher.json` | Create | 2 scenarios + rubrics for researcher agent |
| `tests/eval-prompts/writer.json` | Create | 2 scenarios + rubrics for writer agent |
| `tests/eval-prompts/data-analyst.json` | Create | 2 scenarios + rubrics for data-analyst agent |
| `tests/eval-prompts/general.json` | Create | 2 scenarios + rubrics for general agent |

---

## Task 1: Create eval-prompts directory + debugger.json

**Files:**
- Create: `tests/eval-prompts/debugger.json`

- [ ] **Step 1: Create the eval-prompts directory and debugger.json**

```bash
mkdir -p tests/eval-prompts
```

Create `tests/eval-prompts/debugger.json`:

```json
{
  "agent": "debugger",
  "scenarios": [
    {
      "name": "undefined-var-bug",
      "prompt": "The app crashes on startup with 'ReferenceError: config is not defined' in src/index.js. Investigate.",
      "must_contain": ["ROOT CAUSE:", "FILE:", "WHY:", "SUGGESTED FIX:"],
      "must_not_contain": ["I'll fix", "Let me edit", "I edited", "I modified"],
      "description": "Debugger must produce root-cause report without modifying files"
    },
    {
      "name": "slow-endpoint",
      "prompt": "The GET /users endpoint is slow. Find the performance bottleneck in src/utils.js.",
      "must_contain": ["ROOT CAUSE:", "FILE:"],
      "must_not_contain": ["I'll fix", "Let me edit", "I edited"],
      "description": "Debugger must identify N+1 pattern without fixing it"
    }
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add tests/eval-prompts/debugger.json
git commit -m "eval: add debugger eval prompts and rubrics"
```

---

## Task 2: Create remaining 8 eval-prompts JSON files

**Files:**
- Create: `tests/eval-prompts/reviewer.json`
- Create: `tests/eval-prompts/code-helper.json`
- Create: `tests/eval-prompts/architect.json`
- Create: `tests/eval-prompts/planner.json`
- Create: `tests/eval-prompts/researcher.json`
- Create: `tests/eval-prompts/writer.json`
- Create: `tests/eval-prompts/data-analyst.json`
- Create: `tests/eval-prompts/general.json`

- [ ] **Step 1: Create tests/eval-prompts/reviewer.json**

```json
{
  "agent": "reviewer",
  "scenarios": [
    {
      "name": "security-review",
      "prompt": "Review src/api.js for security and correctness issues.",
      "must_contain": ["MUST FIX", "SHOULD FIX", "CONSIDER", "STRENGTHS"],
      "must_not_contain": ["I'll change", "I edited", "I modified", "I fixed"],
      "description": "Reviewer must produce structured severity-tagged report without modifying code"
    },
    {
      "name": "performance-review",
      "prompt": "Review src/utils.js for performance issues.",
      "must_contain": ["MUST FIX", "SHOULD FIX", "CONSIDER"],
      "must_not_contain": ["I edited", "I modified", "I fixed"],
      "description": "Reviewer must identify N+1 pattern and report it with file:line evidence"
    }
  ]
}
```

- [ ] **Step 2: Create tests/eval-prompts/code-helper.json**

```json
{
  "agent": "code-helper",
  "scenarios": [
    {
      "name": "write-function",
      "prompt": "Write a function called `getMaxValue` in src/utils.js that returns the maximum value from an array of numbers.",
      "must_contain": ["```"],
      "must_not_contain": ["I cannot", "I'm unable"],
      "description": "Code-helper must produce a code block with the requested function"
    },
    {
      "name": "fix-bug",
      "prompt": "Fix the ReferenceError in src/index.js where config is not defined.",
      "must_contain": ["```"],
      "must_not_contain": ["I cannot", "I'm unable"],
      "description": "Code-helper must write the fix as code"
    }
  ]
}
```

- [ ] **Step 3: Create tests/eval-prompts/architect.json**

```json
{
  "agent": "architect",
  "scenarios": [
    {
      "name": "auth-design",
      "prompt": "Design JWT authentication for this Express app in src/api.js. Produce a design plan only.",
      "must_contain": ["GOAL:", "APPROACH:", "DESIGN DECISIONS:", "ACCEPTANCE CRITERIA:"],
      "must_not_contain": ["I edited", "I modified", "I created the file"],
      "description": "Architect must produce structured design plan without writing implementation code"
    },
    {
      "name": "logging-design",
      "prompt": "Design request logging middleware for this Express project. Produce a design plan only.",
      "must_contain": ["GOAL:", "APPROACH:", "FILE CHANGES:"],
      "must_not_contain": ["I edited", "I modified"],
      "description": "Architect must produce design with file change plan, no implementation"
    }
  ]
}
```

- [ ] **Step 4: Create tests/eval-prompts/planner.json**

```json
{
  "agent": "planner",
  "scenarios": [
    {
      "name": "error-handling-plan",
      "prompt": "How should I add error handling to the API endpoints in src/api.js?",
      "must_contain": ["GOAL:", "STEPS:", "RISKIEST STEP:"],
      "must_not_contain": ["I edited", "I modified", "I created"],
      "description": "Planner must produce numbered steps with risk flag, no implementation"
    },
    {
      "name": "database-plan",
      "prompt": "What is the plan for adding a PostgreSQL connection to this Node project?",
      "must_contain": ["GOAL:", "STEPS:"],
      "must_not_contain": ["I edited", "I modified"],
      "description": "Planner must produce an ordered step plan"
    }
  ]
}
```

- [ ] **Step 5: Create tests/eval-prompts/researcher.json**

```json
{
  "agent": "researcher",
  "scenarios": [
    {
      "name": "jwt-vs-sessions",
      "prompt": "What are the trade-offs between JWT and session-based authentication for a Node.js API?",
      "must_contain": ["JWT", "session"],
      "must_not_contain": ["I don't know", "I cannot answer", "as an AI"],
      "description": "Researcher must answer directly with trade-offs for both options"
    },
    {
      "name": "node-concurrency",
      "prompt": "How does Node.js handle concurrency compared to traditional multi-threaded servers?",
      "must_contain": ["event loop", "Node"],
      "must_not_contain": ["I don't know", "as an AI"],
      "description": "Researcher must explain event loop model with trade-offs"
    }
  ]
}
```

- [ ] **Step 6: Create tests/eval-prompts/writer.json**

```json
{
  "agent": "writer",
  "scenarios": [
    {
      "name": "readme-section",
      "prompt": "Write a 'Getting Started' section for the README.md of this Node.js project.",
      "must_contain": ["#", "install", "npm"],
      "must_not_contain": ["Certainly!", "I hope this helps", "In conclusion", "as an AI"],
      "description": "Writer must produce a markdown section with no filler phrases"
    },
    {
      "name": "contributing-guide",
      "prompt": "Write a short CONTRIBUTING.md for this project covering how to submit a bug report.",
      "must_contain": ["#"],
      "must_not_contain": ["Certainly!", "I hope this helps", "as an AI"],
      "description": "Writer must produce structured markdown without filler"
    }
  ]
}
```

- [ ] **Step 7: Create tests/eval-prompts/data-analyst.json**

```json
{
  "agent": "data-analyst",
  "scenarios": [
    {
      "name": "csv-summary",
      "prompt": "Analyze data/sales.csv. Show the number of rows, columns, and summarize the revenue column.",
      "must_contain": ["```", "rows", "columns"],
      "must_not_contain": ["I cannot", "I'm unable", "as an AI"],
      "description": "Data-analyst must show query/code and interpret the results"
    },
    {
      "name": "csv-top-products",
      "prompt": "Which product in data/sales.csv has the highest total revenue? Show your work.",
      "must_contain": ["```"],
      "must_not_contain": ["I cannot", "I'm unable"],
      "description": "Data-analyst must produce code and a result, not just describe"
    }
  ]
}
```

- [ ] **Step 8: Create tests/eval-prompts/general.json**

```json
{
  "agent": "general",
  "scenarios": [
    {
      "name": "project-overview",
      "prompt": "What does this project do?",
      "must_contain": ["Node", "Express", "API"],
      "must_not_contain": ["as an AI", "I'm just an AI", "I don't have access"],
      "description": "General agent must give a direct answer about the project"
    },
    {
      "name": "simple-question",
      "prompt": "What is the difference between a bug and a feature request?",
      "must_contain": ["bug", "feature"],
      "must_not_contain": ["as an AI", "I'm just an AI"],
      "description": "General agent must answer directly without jargon or AI disclaimers"
    }
  ]
}
```

- [ ] **Step 9: Commit all prompt files**

```bash
git add tests/eval-prompts/
git commit -m "eval: add eval-prompts JSON rubrics for all 9 agents"
```

---

## Task 3: Create eval-agents.sh (scaffold + agent loader + runner + scorer)

**Files:**
- Create: `tests/eval-agents.sh`

- [ ] **Step 1: Write the full eval-agents.sh script**

Create `tests/eval-agents.sh`:

```bash
#!/usr/bin/env bash
# Claude Supercharger — Agent Eval
# Usage: bash tests/eval-agents.sh [--agent <name>] [--parallel]
# Runs 2 scenarios per agent via claude CLI, scores responses, prints report.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="$REPO_DIR/configs/agents"
PROMPTS_DIR="$REPO_DIR/tests/eval-prompts"

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

AGENTS_PASSED=0; AGENTS_PARTIAL=0; AGENTS_FAILED=0
SCENARIOS_PASSED=0; SCENARIOS_PARTIAL=0; SCENARIOS_FAILED=0
DETAIL_LINES=()
START_TIME=$(date +%s)

TEMP_PROJECT=""
ARG_AGENT=""
ARG_PARALLEL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) ARG_AGENT="$2"; shift 2 ;;
    --parallel) ARG_PARALLEL=true; shift ;;
    --help)
      echo "Usage: bash tests/eval-agents.sh [--agent <name>] [--parallel]"
      echo "  --agent <name>   Eval only this agent (e.g. debugger)"
      echo "  --parallel       Run agents concurrently (faster, noisier output)"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

cleanup() {
  [[ -n "$TEMP_PROJECT" && -d "$TEMP_PROJECT" ]] && rm -rf "$TEMP_PROJECT"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Temp project scaffold
# ---------------------------------------------------------------------------
create_temp_project() {
  TEMP_PROJECT=$(mktemp -d)

  cat > "$TEMP_PROJECT/package.json" << 'EOF'
{
  "name": "eval-project",
  "version": "1.0.0",
  "description": "Sample Node.js Express API for eval testing",
  "main": "src/index.js",
  "scripts": { "start": "node src/index.js", "test": "jest" },
  "dependencies": { "express": "^4.18.0" },
  "devDependencies": { "jest": "^29.0.0" }
}
EOF

  mkdir -p "$TEMP_PROJECT/src" "$TEMP_PROJECT/tests" "$TEMP_PROJECT/data"

  # Bug: config is used but never imported/defined
  cat > "$TEMP_PROJECT/src/index.js" << 'EOF'
const express = require('express');
const { getUsers } = require('./utils');
const { createUserRoute } = require('./api');

const app = express();
app.use(express.json());

app.get('/users', async (req, res) => {
  const users = await getUsers();
  res.json(users);
});

app.use('/api', createUserRoute());

// BUG: config is never defined or imported
const port = config.port || 3000;
app.listen(port, () => console.log(`Server running on port ${port}`));

module.exports = app;
EOF

  # N+1 pattern: getUsers calls getUser in a loop
  cat > "$TEMP_PROJECT/src/utils.js" << 'EOF'
const db = {
  query: async (sql, params) => {
    // Simulated database query
    return [];
  }
};

// N+1 BUG: fetches user list then queries each user individually
async function getUsers() {
  const userIds = await db.query('SELECT id FROM users');
  const users = [];
  for (const row of userIds) {
    const user = await db.query('SELECT * FROM users WHERE id = ?', [row.id]);
    users.push(user[0]);
  }
  return users;
}

async function getUserById(id) {
  const result = await db.query('SELECT * FROM users WHERE id = ?', [id]);
  return result[0] || null;
}

module.exports = { getUsers, getUserById };
EOF

  # Missing error handling, no try/catch
  cat > "$TEMP_PROJECT/src/api.js" << 'EOF'
const express = require('express');
const { getUserById } = require('./utils');

function createUserRoute() {
  const router = express.Router();

  // Missing error handling — if getUserById throws, server crashes
  router.get('/users/:id', async (req, res) => {
    const user = await getUserById(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(user);
  });

  // SQL injection risk: req.query.name used directly
  router.get('/users/search', async (req, res) => {
    const name = req.query.name;
    const results = await db.query(`SELECT * FROM users WHERE name = '${name}'`);
    res.json(results);
  });

  return router;
}

module.exports = { createUserRoute };
EOF

  # Failing test
  cat > "$TEMP_PROJECT/tests/index.test.js" << 'EOF'
const { getUserById } = require('../src/utils');

test('getUserById returns null for unknown id', async () => {
  const user = await getUserById(99999);
  expect(user).toBeNull();
});

test('getUserById returns user object for valid id', async () => {
  const user = await getUserById(1);
  expect(user).toHaveProperty('id');
});
EOF

  cat > "$TEMP_PROJECT/README.md" << 'EOF'
# eval-project

A sample Node.js Express API.

## Setup

Install dependencies and start the server.

## API

- GET /users — list all users
- GET /api/users/:id — get user by ID
- GET /api/users/search?name=X — search users by name
EOF

  # CSV for data-analyst
  cat > "$TEMP_PROJECT/data/sales.csv" << 'EOF'
date,product,units,revenue
2026-01-01,Widget A,10,150.00
2026-01-02,Widget B,5,75.00
2026-01-03,Widget A,8,120.00
2026-01-04,Gadget C,3,210.00
2026-01-05,Widget B,12,180.00
2026-01-06,Gadget C,7,490.00
2026-01-07,Widget A,15,225.00
2026-01-08,Gadget C,2,140.00
2026-01-09,Widget B,9,135.00
2026-01-10,Widget A,20,300.00
EOF
}

# ---------------------------------------------------------------------------
# Build --agents JSON from configs/agents/<name>.md
# ---------------------------------------------------------------------------
build_agents_json() {
  local agent_name="$1"
  local agent_file="$AGENTS_DIR/$agent_name.md"

  if [[ ! -f "$agent_file" ]]; then
    echo "{}"
    return 1
  fi

  PYTHONUTF8=1 python3 - "$agent_file" "$agent_name" << 'PYEOF'
import sys, json, re

with open(sys.argv[1], encoding='utf-8') as f:
    content = f.read()

parts = content.split('---\n', 2)
frontmatter = parts[1] if len(parts) >= 3 else ''
body = parts[2].strip() if len(parts) >= 3 else content.strip()

desc_match = re.search(r'^description:\s*(.+)', frontmatter, re.MULTILINE)
description = desc_match.group(1).strip() if desc_match else 'Agent'

agents = {sys.argv[2]: {'description': description, 'prompt': body}}
sys.stdout.write(json.dumps(agents))
PYEOF
}

# ---------------------------------------------------------------------------
# Score a response against must_contain / must_not_contain patterns
# Returns two lines: PASS|PARTIAL|FAIL and matched/total
# ---------------------------------------------------------------------------
score_response() {
  local response="$1"
  local must_contain_json="$2"
  local must_not_contain_json="$3"

  PYTHONUTF8=1 python3 - "$response" "$must_contain_json" "$must_not_contain_json" << 'PYEOF'
import sys, json

response = sys.argv[1].lower()
must_contain = json.loads(sys.argv[2])
must_not_contain = json.loads(sys.argv[3])

blocked = any(p.lower() in response for p in must_not_contain)
total = len(must_contain)
matched = sum(1 for p in must_contain if p.lower() in response)

if blocked:
    print("FAIL")
    print(f"0/{total} (blocked by must_not_contain)")
elif total == 0:
    print("PASS")
    print("0/0")
elif matched == total:
    print("PASS")
    print(f"{matched}/{total}")
elif matched > total / 2:
    print("PARTIAL")
    print(f"{matched}/{total}")
else:
    print("FAIL")
    print(f"{matched}/{total}")
PYEOF
}

# ---------------------------------------------------------------------------
# Run one scenario: invoke claude, return captured response
# ---------------------------------------------------------------------------
run_scenario() {
  local agent_name="$1"
  local prompt="$2"
  local agents_json
  agents_json=$(build_agents_json "$agent_name") || { echo ""; return; }

  timeout 90 claude \
    --print \
    --agents "$agents_json" \
    --agent "$agent_name" \
    --dangerously-skip-permissions \
    --add-dir "$TEMP_PROJECT" \
    --max-budget-usd 0.20 \
    --no-session-persistence \
    "$prompt" 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Evaluate one agent: parse its JSON, run scenarios, collect scores
# ---------------------------------------------------------------------------
eval_agent() {
  local agent_name="$1"
  local prompts_file="$PROMPTS_DIR/$agent_name.json"

  if [[ ! -f "$prompts_file" ]]; then
    echo -e "  ${YELLOW}SKIP${NC}  $agent_name — no prompts file found"
    return
  fi

  local scenarios_count
  scenarios_count=$(PYTHONUTF8=1 python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(len(d['scenarios']))" "$prompts_file")

  local agent_pass=0
  local agent_total=0

  for i in $(seq 0 $((scenarios_count - 1))); do
    local scenario_name prompt must_contain must_not_contain
    scenario_name=$(PYTHONUTF8=1 python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['scenarios'][int(sys.argv[2])]['name'])" "$prompts_file" "$i")
    prompt=$(PYTHONUTF8=1 python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d['scenarios'][int(sys.argv[2])]['prompt'])" "$prompts_file" "$i")
    must_contain=$(PYTHONUTF8=1 python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d['scenarios'][int(sys.argv[2])]['must_contain']))" "$prompts_file" "$i")
    must_not_contain=$(PYTHONUTF8=1 python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(d['scenarios'][int(sys.argv[2])]['must_not_contain']))" "$prompts_file" "$i")

    local response
    response=$(run_scenario "$agent_name" "$prompt")

    local score_result score_detail
    score_result=$(echo "$response" | xargs -0 -I{} bash -c 'score_response "$@"' _ "$response" "$must_contain" "$must_not_contain" 2>/dev/null) || true

    # Re-invoke score directly
    local score_lines
    score_lines=$(score_response "$response" "$must_contain" "$must_not_contain")
    local verdict detail_count
    verdict=$(echo "$score_lines" | head -1)
    detail_count=$(echo "$score_lines" | tail -1)

    agent_total=$((agent_total + 1))

    case "$verdict" in
      PASS)
        agent_pass=$((agent_pass + 1))
        SCENARIOS_PASSED=$((SCENARIOS_PASSED + 1))
        DETAIL_LINES+=("    ${GREEN}PASS${NC}   $agent_name/$scenario_name  [${detail_count} patterns matched]")
        ;;
      PARTIAL)
        SCENARIOS_PARTIAL=$((SCENARIOS_PARTIAL + 1))
        DETAIL_LINES+=("    ${YELLOW}PART${NC}   $agent_name/$scenario_name  [${detail_count} patterns matched]")
        ;;
      FAIL)
        SCENARIOS_FAILED=$((SCENARIOS_FAILED + 1))
        DETAIL_LINES+=("    ${RED}FAIL${NC}   $agent_name/$scenario_name  [${detail_count} patterns matched]")
        ;;
    esac
  done

  # Agent-level verdict
  if [[ $agent_pass -eq $agent_total ]]; then
    AGENTS_PASSED=$((AGENTS_PASSED + 1))
    printf "  ${GREEN}PASS${NC}  %-16s (%d/%d scenarios passed)\n" "$agent_name" "$agent_pass" "$agent_total"
  elif [[ $agent_pass -gt 0 ]]; then
    AGENTS_PARTIAL=$((AGENTS_PARTIAL + 1))
    printf "  ${YELLOW}PART${NC}  %-16s (%d/%d scenarios passed)\n" "$agent_name" "$agent_pass" "$agent_total"
  else
    AGENTS_FAILED=$((AGENTS_FAILED + 1))
    printf "  ${RED}FAIL${NC}  %-16s (%d/%d scenarios passed)\n" "$agent_name" "$agent_pass" "$agent_total"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ALL_AGENTS=(debugger reviewer code-helper architect planner researcher writer data-analyst general)

echo ""
echo -e "${BOLD}Claude Supercharger — Agent Eval${NC}"
echo -e "${DIM}Creating temp project...${NC}"
create_temp_project
echo -e "${DIM}Temp project: $TEMP_PROJECT${NC}"
echo ""
echo -e "${BOLD}=== Agent Eval Report ===${NC}"
echo ""

if [[ -n "$ARG_AGENT" ]]; then
  eval_agent "$ARG_AGENT"
else
  for agent in "${ALL_AGENTS[@]}"; do
    eval_agent "$agent"
  done
fi

echo ""
echo -e "${DIM}--- Details ---${NC}"
for line in "${DETAIL_LINES[@]}"; do
  echo -e "$line"
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_FMT=$(printf "%dm %ds" $((ELAPSED / 60)) $((ELAPSED % 60)))

TOTAL_AGENTS=$((AGENTS_PASSED + AGENTS_PARTIAL + AGENTS_FAILED))
TOTAL_SCENARIOS=$((SCENARIOS_PASSED + SCENARIOS_PARTIAL + SCENARIOS_FAILED))

echo ""
echo -e "${CYAN}────────────────────────────────────────────────${NC}"
echo -e "  Agents:    ${GREEN}$AGENTS_PASSED passed${NC}, ${YELLOW}$AGENTS_PARTIAL partial${NC}, ${RED}$AGENTS_FAILED failed${NC} ($TOTAL_AGENTS total)"
echo -e "  Scenarios: ${GREEN}$SCENARIOS_PASSED passed${NC}, ${YELLOW}$SCENARIOS_PARTIAL partial${NC}, ${RED}$SCENARIOS_FAILED failed${NC} ($TOTAL_SCENARIOS total)"
echo -e "  Time: $ELAPSED_FMT"
echo ""

[[ $AGENTS_FAILED -gt 0 ]] && exit 1 || exit 0
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x tests/eval-agents.sh
```

- [ ] **Step 3: Smoke-test the temp project creation in isolation**

```bash
bash -c '
  TEMP=$(mktemp -d)
  trap "rm -rf $TEMP" EXIT
  source tests/eval-agents.sh 2>/dev/null || true
  TEMP_PROJECT=$TEMP
  create_temp_project
  echo "Files created:"
  find $TEMP_PROJECT -type f | sort
'
```

Expected output: Lists `package.json`, `src/index.js`, `src/utils.js`, `src/api.js`, `tests/index.test.js`, `README.md`, `data/sales.csv`

- [ ] **Step 4: Commit**

```bash
git add tests/eval-agents.sh
git commit -m "eval: add eval-agents.sh runner with scaffold, scoring, and report"
```

---

## Task 4: Run eval against one agent to verify end-to-end

**Files:**
- None (verification only)

- [ ] **Step 1: Run eval for debugger agent only**

```bash
bash tests/eval-agents.sh --agent debugger
```

Expected output (shape — exact scores will vary):
```
Claude Supercharger — Agent Eval
Creating temp project...

=== Agent Eval Report ===

  PASS  debugger         (2/2 scenarios passed)

--- Details ---
    PASS   debugger/undefined-var-bug  [4/4 patterns matched]
    PASS   debugger/slow-endpoint      [2/2 patterns matched]

────────────────────────────────────────────────
  Agents:    1 passed, 0 partial, 0 failed (1 total)
  Scenarios: 2 passed, 0 partial, 0 failed (2 total)
  Time: 0m 45s
```

If you see `FAIL` or `PARTIAL`, check:
- `claude --version` — CLI must be available
- `claude agents` — verify the agent name resolves
- Run `claude --print --agent debugger "hello"` manually to confirm the agent responds

- [ ] **Step 2: Commit nothing (verification step only)**

---

## Task 5: Run full eval and add to test suite

**Files:**
- Modify: `tests/run.sh`

- [ ] **Step 1: Check what run.sh currently does**

```bash
cat tests/run.sh
```

- [ ] **Step 2: Add eval-agents.sh to run.sh (only if run.sh exists and orchestrates tests)**

If `run.sh` runs all tests, add an optional eval flag. Read the file first, then edit it to add:

```bash
# After existing test runs, add:
if [[ "${RUN_EVAL:-false}" == "true" ]]; then
  echo ""
  echo "Running agent evals (RUN_EVAL=true)..."
  bash "$(dirname "$0")/eval-agents.sh"
fi
```

Note: Eval is opt-in via `RUN_EVAL=true` because it makes real API calls and costs money.

- [ ] **Step 3: Run the full eval suite**

```bash
bash tests/eval-agents.sh
```

This will take ~5-10 minutes and cost ~$0.10-0.30.

- [ ] **Step 4: Commit**

```bash
git add tests/run.sh
git commit -m "eval: wire eval-agents.sh into test runner as opt-in (RUN_EVAL=true)"
```

---

## Self-Review Notes

- **Spec coverage:**
  - ✅ One command — `bash tests/eval-agents.sh`
  - ✅ Temp project created and cleaned up via `trap`
  - ✅ All 9 agents covered with 2 scenarios each
  - ✅ `claude --print --agents --agent` invocation pattern
  - ✅ PASS/PARTIAL/FAIL scoring with 50% threshold
  - ✅ Summary report with per-agent and per-scenario detail
  - ✅ `--agent <name>` flag for single-agent runs
  - ✅ `--max-budget-usd 0.20` per scenario cost cap
  - ✅ 90-second timeout per scenario

- **Type consistency:** `score_response` returns two lines (verdict + count) and is called consistently in `eval_agent`

- **Placeholder check:** No TBD or TODO in any step

- **Known risk:** The `--agents` flag with the full agent prompt body may hit shell quoting limits for very long prompts. Mitigation: Python handles the JSON serialization correctly, bash passes it as a single argument.
