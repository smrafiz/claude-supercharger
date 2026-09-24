Scoped time + complexity estimate for: $ARGUMENTS

Do NOT write code. Do NOT start work. This is a report-only analysis.

It answers "how big, how long, how uncertain?" before anyone decides to do the work. The exact file list, blast radius and approval gate belong to `/scope`, run once the decision is made.

Design sources: Kahneman's planning fallacy and Flyvbjerg's reference-class forecasting (the outside view first), three-point / PERT estimation, Hubbard's calibrated 90% intervals (*How to Measure Anything*), the cone of uncertainty, #NoEstimates (spike instead of inventing a number), and METR — the 2025 study where developers using AI believed they were 20% faster and were measured 19% slower, and METR's task time-horizon work.

**Evidence rule:** reference-class numbers cite the commits they came from. Anything else is an assumption and is labelled as one.

**Step 1 — Outside view first: the reference class**
Before breaking the task down, find 3–10 past changes in this repo that look like it — same area, similar shape (`git log --stat -- <paths>`, `git log --grep`). What did they actually take: commits, files, lines, and the **follow-up fix commits** that landed after them? Anchor on that. If nothing comparable exists, say so; that alone makes the estimate wider.

**Step 2 — Decompose, and split until small**
Break the task into subtasks. Any subtask whose worst case is more than about a day of human work (or ~30 agent turns), or whose best and worst cases are far apart, is too big to estimate — split it, or mark it as needing a spike.

**Step 3 — Three-point estimate per subtask**
Optimistic, most likely, pessimistic. Expected = (O + 4M + P) / 6. The spread between O and P is the real output: it is how much is not yet known. Mark which subtasks block others (the critical path).

**Step 4 — Correct for optimism**
Bottom-up estimates come out low. Compare the sum with the reference class, apply an uplift, and **name** it and its reason (thin reference class, unfamiliar code, integration unknowns). Then state the result as a range you are 90% confident in — wide enough that you would be as surprised by missing it as by losing a 1-in-10 bet.

**Step 5 — Count all the work**
Estimate agent effort (turns, tool calls, rough cost) **and** human time to review, correct and re-prompt. That second part is what estimates leave out; it is why people using AI feel faster than they measure.

**Step 6 — Unknowns, ranked by how much they move the number**
For each unknown: how far it would shift the estimate, and the cheapest way to resolve it. Name the one most worth resolving before committing.

**Step 7 — Bottom line**
The range and your confidence. If there is no reference class and the unknowns dominate, do not invent a number: recommend a time-boxed spike and say what it would settle.

**Output format:**
```
TASK: [one sentence]
REFERENCE CLASS: [N similar changes — commits] → took [range, incl. follow-up fixes] | none found — range widened

DECOMPOSITION (optimistic / likely / pessimistic → expected):
  1. [subtask] — [O / M / P → E] [blocks: N]
  2. ...
CRITICAL PATH: [N → N → N]

SUM: [E] · uplift: [+X%, because ...]
ESTIMATE (90%): [low … high] · agent: ~[N] turns / ~$[cost] · human review: ~[T]
CONFIDENCE: [low | medium | high] — driven by [widest subtask]

UNKNOWNS (by impact):
  1. [unknown] — moves estimate [±...] — resolve via [cheap check]

BOTTOM LINE: [range] | SPIKE FIRST: [time-boxed probe] — settles [...]

(Estimate only — no work started. Run /scope before implementing.)
```

End after the report. Do not start work even if asked in the same prompt — require explicit confirmation in a separate prompt.
