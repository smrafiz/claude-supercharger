Add an entry to the project's DEV-LOG.md: $ARGUMENTS

DEV-LOG.md is a living architecture journal — a running log of non-obvious decisions, context that isn't in the code, and rationale that git commit messages can't hold. It is NOT a changelog. It captures the WHY.

**Step 1 — Locate or create DEV-LOG.md**
Check if `DEV-LOG.md` exists in the project root. If not, create it with a header:
```
# DEV-LOG

Running log of architectural decisions, non-obvious context, and rationale.
Most recent entries at the top.
```

**Step 2 — Draft the entry**
Gather from context (current task, recent changes, conversation):
- What decision was made or what changed
- Why — the constraint, tradeoff, or rationale (this is the essential part)
- What was rejected and why (if applicable)

**Step 3 — Write the entry**

Format:
```
## YYYY-MM-DD — [short title: what this is about]

**What:** [1-2 sentences describing the decision or change]

**Why:** [the reason — constraint, incident, stakeholder requirement, tradeoff chosen]

**Rejected:** [what was considered but not chosen, and why — omit if nothing notable]
```

Prepend the new entry (most recent at top). Do not modify existing entries.

**Step 4 — Confirm**
State the entry path and the title of the entry added.
