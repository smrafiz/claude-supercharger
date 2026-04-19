---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs}"
  - "**/*.{py,go,rs,rb,php,java,kt,swift,c,cpp,h}"
  - "**/*.{sh,bash}"
  - "**/*.{yml,yaml}"
  - "**/*.{css,scss,sass}"
  - "package.json"
  - "Cargo.toml"
  - "go.mod"
---

# Supercharger Rules
# Inspired by SuperClaude Framework (MIT) — distilled for brevity

## Execution Workflow
For complex requests, follow this sequence:
1. Scan request for ambiguity — if vague, ask (max 3 questions)
2. Plan steps before acting — state what you'll do, then do it
3. Execute with appropriate tools
4. Verify output before claiming done
Simple requests: skip to step 3.

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
If something breaks during multi-step work, fix it before moving on.

## Context Carry-Forward
For multi-turn tasks (3+ related prompts):
- Track: decisions made, constraints established, what failed
- If context was compacted, reconstruct this block: Stack | Architecture | Naming | Forbidden (rejected & why) | What failed
- Preserve: stack choices, architecture patterns, naming conventions, rejected approaches, what failed
- Discard: full file contents (re-read if needed), verbose tool output (keep result line only)

## Verification Gate (4-level check)
Before claiming any task is complete, verify at all applicable levels:
1. **Existence** — file is present at expected path
2. **Substantive** — real implementation, not placeholder (no TODO, FIXME, stubs)
3. **Wired** — connected to the system (imports resolve, component used, route registered)
4. **Functional** — works when invoked (tests pass, build succeeds)

Never claim "done" without evidence from at least levels 1-3.
If level 4 cannot be verified, state what the user should test.

## Scope Discipline
- Only change what was requested — no drive-by refactoring
- Ask before modifying files outside the explicit scope, even if in-project
- If you notice something worth improving, mention it without fixing
- One task at a time, completed fully before starting the next

## Clarification Mode
Default: scan every prompt for vague verbs, missing scope, no success criteria, multiple tasks. Max 3 questions, then proceed. See anti-patterns.yml for the full pattern library.

**Deep Interview** (say "deep interview"): Score prompt across 4 critical dimensions (Scope, Success, Constraints, Context) on 0-3 scale. Score 9-12→proceed. Score 5-8→ask about lowest. Score 0-4→full interview, one question per low dimension. For complex tasks, also assess: Input, Output, Audience, Memory, Examples.

## Session Summary
On "session summary", after compaction, or on rate limit — generate:
- Working on, Decisions made, Files changed, What failed, Next steps, Resume with (paste-ready prompt for next session)
After compaction, first response MUST be this summary. Format as fenced code block.
When a conversation is getting long or complex, proactively generate a Session Summary before context pressure hits.
