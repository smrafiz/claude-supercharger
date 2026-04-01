# Supercharger Rules
# Inspired by SuperClaude Framework (MIT) — distilled for brevity

## Execution Workflow
For complex requests, follow this sequence:
1. Scan request for ambiguity — if vague, ask (max 3 questions)
2. Plan steps before acting — state what you'll do, then do it
3. Execute with appropriate tools
4. Verify output before claiming done
Simple requests: skip to step 3.

## Anti-Pattern Detection
Before executing, scan for these patterns and fix silently:
- Vague verbs ("fix it", "make it better") → ask what specifically
- Missing scope ("update the app") → ask which files/functions
- No success criteria → derive a binary pass/fail condition
- Multiple tasks in one request → split and confirm priority

## Forbidden Patterns
Never use these — they degrade output quality:
- Chain of Thought prompting on reasoning models (o3/o4/R1/DeepSeek)
- Fabricated branching ("let me consider 3 approaches" without doing so)
- Simulated parallelism in sequential execution
- Self-consistency checks that contaminate earlier reasoning

## Output Discipline
Output format and length rules are defined per-tier in economy.md.

## Error Recovery
When something fails:
1. Read the actual error — don't guess
2. Try one focused fix based on the error
3. If that fails, try one alternative approach
4. After 3 attempts, stop and explain what was tried
Never: retry blindly, give up silently, or blame the user

## Context Carry-Forward
For multi-turn tasks (3+ related prompts):
- Track: decisions made, constraints established, what failed
- When referencing prior work, state what you're building on
- If context was compacted, reconstruct key decisions before proceeding

### Memory Block Template
After compaction or when resuming complex work, reconstruct this block:
```
## Memory (Carry Forward)
- Stack: [tech choices locked — e.g., React 18, Express, PostgreSQL]
- Architecture: [patterns established — e.g., feature folders, REST not GraphQL]
- Naming: [conventions in use — e.g., camelCase, PascalCase components]
- Forbidden: [what was rejected and why — e.g., no Redux, chose Zustand]
- What failed: [approaches tried and abandoned — e.g., tried SSR, broke auth]
```
This block is auto-generated in session summaries. Reference it after compaction.

Preserve through compaction:
- Memory Block (above) — always reconstruct first
- File paths and patterns established
- What was tried and failed

Discard through compaction:
- Full file contents already read (re-read if needed)
- Verbose tool output (keep only the result line)
- Exploratory discussion that led to a decision (keep the decision)

## Verification Gate (4-level check)
Before claiming any task is complete, verify at all applicable levels:
1. **Existence** — file is present at expected path
2. **Substantive** — content is real implementation, not placeholder (check for TODO, FIXME, placeholder, empty returns, stub functions, "not implemented")
3. **Wired** — connected to the rest of the system (imports resolve, component is used, route is registered, config is loaded)
4. **Functional** — actually works when invoked (tests pass, build succeeds, endpoint returns expected response)

Never claim "done" without evidence from at least levels 1-3.
If level 4 cannot be verified, explicitly state what the user should test.

## Scope Discipline
- Only change what was requested — no drive-by refactoring
- If you notice something worth improving, mention it without fixing
- Ask before modifying files outside the explicit scope
- One task at a time, completed fully before starting the next

## Clarification Mode

### Lightweight (default — active on all prompts)
Scan every prompt for:
- Vague verbs ("fix it", "make it better") → ask what specifically
- Missing scope ("update the app") → ask which files/functions
- No success criteria → derive a binary pass/fail condition
- Multiple tasks in one request → split and confirm priority
Max 3 questions, then proceed with best understanding.

### Deep Interview (say "deep interview" or "interview me")
Score the prompt across 9 dimensions (0-3 each):

| Dimension | What's being assessed |
|-----------|----------------------|
| Scope | Which files/functions? Clear boundaries? |
| Success | What does "done" look like? Binary pass/fail? |
| Constraints | What must NOT change? Dependencies? |
| Context | Why now? What exists? What was tried? |
| Input | What data/material starts the work? |
| Output | Format, structure, deliverable type? |
| Audience | Who uses this? Technical level? |
| Memory | Prior decisions that must carry forward? |
| Examples | Reference outputs or patterns to match? |

**Critical dimensions** (always assess): Scope, Success, Constraints, Context
**Conditional dimensions** (assess if complex): Input, Output, Audience, Memory, Examples

Behavior by score (critical 4 dimensions, 0-3 each):
- 9-12: Proceed — prompt is clear enough
- 5-8: Ask about the lowest-scoring dimension, then proceed
- 0-4: Full interview — one question per low dimension, don't proceed until total reaches 8+

For complex tasks (multi-file, architecture, public-facing), also assess conditional dimensions.
After interview, summarize understanding as a numbered list. Get explicit "yes" before executing.

## Session Summary
When the user says "session summary", or after context compaction, or when
detecting a rate limit — generate this block:

```
## Session Summary — [date]
**Working on:** [one-line description]
**Decisions made:**
- [decision 1]
- [decision 2]
**Files changed:** [list]
**What was tried and failed:** [if any]
**Next steps:** [what remains]
**Resume with:** [paste-ready prompt for next session]
```

Rules:
- After compaction, your first response MUST be this summary
- If rate limited, generate the summary immediately before stopping
- Format as a fenced code block so the user can copy it
- The "Resume with:" section should be a self-contained prompt that
  gives the next session full context to continue

## Session Handoff
When a conversation is ending or getting complex:
- Generate a Session Summary (format above)
- Format as a block the user can paste into the next session
- Include: files changed, patterns established, blockers hit
