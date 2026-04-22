Pre-flight scope check before starting: $ARGUMENTS

Do NOT start implementation. This is a planning gate.

**Step 1 — Parse the task**
What exactly is being asked? Restate in one sentence, no ambiguity.

**Step 2 — File inventory**
List every file that will be created, modified, or deleted. For each:
- Path
- What changes (1 sentence)
- Risk level (low/medium/high)

**Step 3 — Boundaries**
What files/dirs are explicitly OUT of scope? Name them.

**Step 4 — Risks**
What could go wrong? List 2-3 specific risks (not generic).

**Step 5 — Estimate**
Rough turn count: how many tool calls will this take?

**Step 6 — Approval gate**
Present the scope and wait for user approval before proceeding.

Output format:
```
TASK: [one sentence]

FILES TO TOUCH:
  Create: [path] — [what]
  Modify: [path] — [what] — [risk]
  Delete: [path] — [why]

OUT OF SCOPE:
  - [file/dir]: [why not touching]

RISKS:
  1. [risk]: [mitigation]
  2. [risk]: [mitigation]

ESTIMATE: ~[N] turns

Proceed? (waiting for approval)
```
