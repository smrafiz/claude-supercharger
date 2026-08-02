Break out of a debugging loop. Current symptom: $ARGUMENTS

Stop retrying. Step back. Think differently.

**Step 1 — What's been tried**
List every approach attempted so far in this session. Include what happened and why it didn't work. If you've been looping on the same fix, say so.

**Step 2 — What's actually known** ← *this is the step that breaks the loop*
Separate facts (confirmed by evidence) from assumptions (things you believe but haven't verified). Be honest — most "known" things are assumptions.

A debug loop is almost always an unexamined assumption being retried. The other steps are
mechanical; this one is where the loop actually breaks. Do it properly even if a hypothesis
already feels obvious — the obvious hypothesis is usually the assumption you haven't checked.

**Step 3 — Three fresh hypotheses**
Generate 3 explanations that are DIFFERENT from what's been tried. Each must be in a distinct category:
- One that questions the symptom itself (is the error message misleading?)
- One that looks upstream (is the input wrong, not the processing?)
- One that looks at environment (config, dependencies, state, timing)

Each must be **falsifiable** — state the prediction it makes:

> If [X] is the cause, then [doing Y] makes the symptom disappear / [doing Z] makes it worse.

If you cannot state that prediction, it is a vibe, not a hypothesis. Sharpen it or drop it
and generate another. An unfalsifiable hypothesis cannot end the loop, because nothing you
observe can rule it out.

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
1. [symptom-level]: [hypothesis]
     Predicts: if true, [Y] makes it disappear
     Test: [one command]
2. [upstream]: [hypothesis]
     Predicts: ...
     Test: [one command]
3. [environment]: [hypothesis]
     Predicts: ...
     Test: [one command]

NEXT: [which test to run and why]
```

If the test needs temporary logging, tag every line with a unique marker — `[DEBUG-a4f2]`
— so removing it later is one grep rather than a re-read of the diff. Untagged debug logs
are the ones that ship.
