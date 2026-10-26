---
paths:
  - "**/*.{ts,tsx,js,jsx,py,go,rs,rb,java,sh}"
---

# Anti-patterns: scan prompts for these. bad → fix.

vague_input: "help me with X" → "Refactor X to Y. Done when: tests pass + handles null"
two_tasks: "explain AND rewrite" → split sequential
emotional: "totally broken, fix everything" → "TypeError line 43 when user is null"
build_whole: "build entire app" → break into prompt 1/2/3
implicit_ref: "the other thing we discussed" → restate full task
no_memory: "continue where we left off" → re-provide context each session
no_context: "write a cover letter" → add role/industry/experience
hallucination: "what do experts say" → cite only certain sources, say uncertain if not
no_audience: "write for users" → specify: non-technical B2B, decision-maker level
no_failures: (blank) → "tried X, didn't work because Y. Don't suggest X."
no_format: "explain this" → "3 bullets, <20 words each"
no_role: (blank) → "senior backend engineer, Node.js + PostgreSQL"
vague_look: "make it professional" → "monochrome, 16px base, no decorative elements"
no_scope: "fix my app" → "fix login validation in src/auth.js:handleLogin(). Touch nothing else."
no_stack: "build React component" → "React 18, TS strict, no external libs, Tailwind only"
no_stop: "build whole feature" → explicit stop conditions + checkpoint output
full_paste: "full repo context" → scope to relevant function + file only
no_reasoning: "which is better?" → think through both step-by-step before recommending
cot_on_reasoning: "think step by step" to o1/o3/R1 → remove, degrades output
no_grounding: "what experts say" → use only high-confidence info, mark uncertain
no_state: "build REST API" → "starting: empty Node.js. Target: auth.js with JWT verify"
silent_agent: no progress → after each step output what was completed
no_file_restrict: no limits → "only edit src/. Don't touch package.json, .env, config"
no_review_gate: agent decides alone → stop before: deleting files, adding deps, changing schema
dead_code: removing pre-existing unused code → only remove dead code YOUR changes introduced
