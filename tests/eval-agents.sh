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

  cat > "$TEMP_PROJECT/src/utils.js" << 'EOF'
const db = {
  query: async (sql, params) => {
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

  # perl -e "alarm(N)" provides a portable timeout on macOS + Linux
  (cd "$TEMP_PROJECT" && perl -e 'alarm(300); exec @ARGV' -- claude \
    --print \
    --agents "$agents_json" \
    --agent "$agent_name" \
    --dangerously-skip-permissions \
    --max-budget-usd 0.20 \
    --no-session-persistence \
    "$prompt" 2>/dev/null) || echo ""
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

    local score_lines verdict detail_count
    score_lines=$(score_response "$response" "$must_contain" "$must_not_contain")
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
