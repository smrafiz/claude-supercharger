# Agent Eval Framework — Design Spec

**Date:** 2026-04-05
**Status:** Draft
**Scope:** Multi-scenario eval for all 9 Claude Supercharger agents

## Problem

The project has structural tests (`test-agents.sh`) that verify agent files exist and have correct frontmatter. There is no way to measure actual agent response quality — whether agents follow their rules, produce correct output format, and adhere to their role.

## Goal

One command (`bash tests/eval-agents.sh`) that:
- Creates a disposable temp project with sample code and intentional bugs
- Sends 2-3 test prompts per agent via `claude` CLI
- Scores responses against rubric patterns
- Outputs a summary report (PASS / PARTIAL / FAIL per agent)
- Zero user intervention, fully self-contained

## Architecture

```
tests/
  eval-agents.sh              # Main runner
  eval-prompts/               # Prompt + rubric files (one per agent)
    debugger.json
    reviewer.json
    code-helper.json
    architect.json
    planner.json
    researcher.json
    writer.json
    data-analyst.json
    general.json
  helpers.sh                  # Existing test helpers (reused)
```

## Temp Project Scaffold

The script creates a temp directory with:

```
/tmp/eval-project-XXXX/
  package.json                # Node project metadata
  src/
    index.js                  # Entry point with an intentional bug (undefined var)
    utils.js                  # Utility with N+1 query pattern
    api.js                    # Express endpoint with missing error handling
  tests/
    index.test.js             # Failing test
  README.md                   # Minimal project readme
```

This gives agents realistic material to work with.

## Prompt Format (JSON per agent)

Each `eval-prompts/<agent>.json` contains:

```json
{
  "agent": "debugger",
  "scenarios": [
    {
      "name": "undefined-var-bug",
      "prompt": "The app crashes on startup with 'ReferenceError: config is not defined'. Investigate.",
      "must_contain": ["ROOT CAUSE:", "FILE:", "WHY:", "SUGGESTED FIX:"],
      "must_not_contain": ["I'll fix", "Let me edit"],
      "description": "Should produce root-cause report, not implement fix"
    },
    {
      "name": "n-plus-one",
      "prompt": "The /users endpoint is slow. Profile and find the bottleneck.",
      "must_contain": ["ROOT CAUSE:", "FILE:"],
      "must_not_contain": [],
      "description": "Should identify N+1 query pattern"
    }
  ]
}
```

## CLI Invocation

Each scenario runs:

```bash
claude \
  --print \
  --agent <agent-name> \
  --model sonnet \
  --bare \
  --dangerously-skip-permissions \
  --add-dir "$TEMP_PROJECT" \
  --max-budget-usd 0.50 \
  "$PROMPT_TEXT"
```

Key flags:
- `--print` — non-interactive, captures output
- `--agent` — selects the agent config
- `--bare` — skips hooks, MCP, auto-memory (clean eval)
- `--dangerously-skip-permissions` — unattended execution
- `--max-budget-usd 0.50` — cost cap per scenario
- `--model sonnet` — consistent model across evals

## Scoring

Per scenario:
- **PASS** — all `must_contain` patterns found, no `must_not_contain` patterns found
- **PARTIAL** — some `must_contain` found (>50%)
- **FAIL** — fewer than 50% of `must_contain` found, or any `must_not_contain` found

Per agent:
- **PASS** — all scenarios pass
- **PARTIAL** — at least one scenario passes
- **FAIL** — no scenarios pass

## Output Report

```
=== Agent Eval Report ===
  PASS  debugger       (2/2 scenarios passed)
  PART  reviewer       (1/2 scenarios passed)
  FAIL  general        (0/2 scenarios passed)

  Details:
    debugger/undefined-var-bug    PASS  [4/4 patterns matched]
    debugger/n-plus-one           PASS  [2/2 patterns matched]
    reviewer/code-quality         PASS  [3/3 patterns matched]
    reviewer/security-review      PART  [1/3 patterns matched]
    general/greeting              FAIL  [0/2 patterns matched]

Summary: 7 PASS, 1 PARTIAL, 1 FAIL (9 agents, 20 scenarios)
Total time: 3m 42s
```

## Rubrics Per Agent

| Agent | must_contain patterns | must_not_contain |
|-------|----------------------|------------------|
| debugger | `ROOT CAUSE:`, `FILE:`, `WHY:`, `SUGGESTED FIX:` | `I'll fix`, `Let me edit` |
| reviewer | severity keyword (`MUST FIX`/`SHOULD FIX`/`CONSIDER`), file reference | `I'll change`, implementation code |
| code-helper | code block (triple backtick), addresses prompt | — |
| architect | trade-offs/alternatives, component boundaries | implementation code |
| planner | numbered steps, scope/priority | code blocks |
| researcher | structured sections, evidence/citations | — |
| writer | headers/structure, prose paragraphs | code blocks (unless asked) |
| data-analyst | data reference, structured output (table/list) | — |
| general | relevant to prompt, coherent response | hallucination markers (`as an AI`) |

## Parallelism

Agents are independent — scenarios within an agent run sequentially, but agents can run in parallel (background subshells). Default: sequential for predictable output. Flag `--parallel` for speed.

## Cost Estimate

- ~20 scenarios x sonnet model
- ~500-1000 input tokens + ~500-1500 output tokens per scenario
- Estimated total: $0.10-0.30 per full eval run

## Constraints

- No user intervention required
- No API key setup beyond what `claude` CLI already has
- Temp project cleaned up on exit (trap)
- Timeout per scenario: 60 seconds
- Total timeout: 10 minutes

## Out of Scope

- Claude-as-judge scoring (future enhancement)
- Historical tracking / regression detection (future)
- Custom agent eval (project-agent-templates) — only configs/agents/ for now
