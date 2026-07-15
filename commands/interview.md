Gather requirements before planning: $ARGUMENTS

Do NOT write any code or create an implementation plan. This is a requirements gate.

Use the `AskUserQuestion` tool for EVERY question. Never ask questions as plain prose.

**Rules:**
- One question at a time — wait for the answer before asking the next
- Every question MUST include a recommended option, marked **(recommended)**
- Ask until you have enough to write a clear requirements summary
- Minimum 3 questions, maximum 7 — stop when scope is clear

**Question sequence:**

1. **What problem is being solved?** (not what to build — what pain or gap)
2. **Who uses this and what do they need?** (user, system, or both)
3. **What does success look like?** (observable outcome, not implementation detail)
4. **What are the hard constraints?** (must-nots, non-negotiables, existing systems to respect)
5. **What's out of scope?** (what you explicitly will NOT do in this iteration)
6-7. Ask follow-up questions only if critical ambiguity remains.

**On completion:**

Output a requirements summary, then invoke the `superpowers:brainstorming` skill (or `superpowers:writing-plans` if the design is already clear).

Output format:
```
REQUIREMENTS SUMMARY

Problem: [one sentence — the actual pain or gap]

Users: [who and what they need]

Success criteria:
  - [observable outcome 1]
  - [observable outcome 2]

Constraints:
  - [hard constraint 1]
  - [hard constraint 2]

Out of scope:
  - [explicit exclusion 1]

Open questions: [any remaining ambiguity, or "none"]
```
