Break out of a debugging loop. Current symptom: $ARGUMENTS

Stop retrying. Step back. Think differently.

**Step 1 — What's been tried**
List every approach attempted so far in this session. Include what happened and why it didn't work. If you've been looping on the same fix, say so.

**Step 2 — What's actually known**
Separate facts (confirmed by evidence) from assumptions (things you believe but haven't verified). Be honest — most "known" things are assumptions.

**Step 3 — Three fresh hypotheses**
Generate 3 explanations that are DIFFERENT from what's been tried. Each must be in a distinct category:
- One that questions the symptom itself (is the error message misleading?)
- One that looks upstream (is the input wrong, not the processing?)
- One that looks at environment (config, dependencies, state, timing)

**Step 4 — Cheapest test**
For each hypothesis: what is the single fastest way to confirm or rule it out? One command or one file read. Not a fix — a test.

**Step 5 — Recommend**
Pick the hypothesis with the cheapest test. Do that test now.

Output format:
```
SYMPTOM: [restated precisely]

TRIED:
1. [approach] — [result]
2. [approach] — [result]

FACTS vs ASSUMPTIONS:
  Facts: [bullet list with evidence source]
  Assumptions: [bullet list — things not yet verified]

FRESH HYPOTHESES:
1. [symptom-level]: [hypothesis] — Test: [one command]
2. [upstream]: [hypothesis] — Test: [one command]
3. [environment]: [hypothesis] — Test: [one command]

NEXT: [which test to run and why]
```
