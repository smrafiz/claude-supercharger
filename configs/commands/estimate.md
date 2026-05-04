Scoped time + complexity estimate for: $ARGUMENTS

Do NOT write code. Do NOT start work. This is a report-only analysis.

**Step 1 — Decompose the task**
List concrete subtasks (5-10 max). Each must be a discrete unit of work.

**Step 2 — Estimate per subtask**
For each subtask, estimate:
- Files touched (count + list)
- Lines changed (rough — under 50 / 50-200 / over 200)
- Tool calls (rough — under 10 / 10-30 / over 30)
- Wall-clock time (under 15 min / 15-60 min / over 1 hour)
- Risk (low/med/high) with one-line reason

**Step 3 — Identify dependencies**
Which subtasks block others? Critical path?

**Step 4 — Surface unknowns**
List explicit "I don't know yet" items that would change the estimate. These need user clarification or investigation BEFORE work starts.

**Step 5 — Bottom line**
Total estimated turns and wall-clock. Confidence level (low/med/high).

Output format:

```
TASK: [one sentence]

DECOMPOSITION:
  1. [subtask] — [files/lines/turns/time/risk]
  2. [subtask] — [files/lines/turns/time/risk]
  ...

CRITICAL PATH: [N] → [N] → [N] (subtasks that block downstream work)

UNKNOWNS:
  - [unknown 1]: would change estimate by [+X turns / +X min]
  - [unknown 2]: ...

TOTAL: ~[N] turns, ~[T] wall-clock
CONFIDENCE: [low/med/high] — [reason]

Proceed? (Estimate only — wait for user approval before any code.)
```

End after the report. Do not start work even if asked in the same prompt — require explicit confirmation in a separate prompt.
