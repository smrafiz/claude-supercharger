Score this session and write quality observations to memory: $ARGUMENTS

Run after completing significant work. Scores what worked, what didn't, and writes structured observations that future sessions will load — building a project-specific improvement signal over time.

Do NOT summarize what was done. Focus only on quality signals: what patterns helped, what went wrong, what should change next time.

**Step 1 — Score the session**

Assess across four dimensions (0–3 each):

| Dimension | 0 | 3 |
|---|---|---|
| **Accuracy** | Multiple wrong assumptions, rework required | First-attempt correct, no backtracking |
| **Scope discipline** | Drifted beyond what was asked | Stayed tightly scoped |
| **Verification** | Claimed done without evidence | Ran checks, confirmed output |
| **Efficiency** | Many redundant tool calls / retries | Direct path to solution |

**Step 2 — Extract observations**

For each dimension scored < 2, write one observation:
- What went wrong (specific, not generic)
- Why it happened
- What to do differently next time

For each dimension scored 3, write one observation if a non-obvious approach worked well.

**Step 3 — Append to `.claude/session-observations.md`**

Create if absent. Prepend new entry (most recent first):

```markdown
## YYYY-MM-DD — [one-line description of work done]

Scores: accuracy=N scope=N verification=N efficiency=N

Observations:
- [observation 1 — what + why + next time]
- [observation 2 — what + why + next time]
```

Cap file at 50 entries — trim oldest if exceeded.

**Step 4 — Confirm**

State: `Reflection written. [N] observation(s) logged to .claude/session-observations.md`
