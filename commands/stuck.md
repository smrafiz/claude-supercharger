Break out of a debugging loop. Current symptom: $ARGUMENTS

Stop retrying. Step back. Look, don't think.

This command localizes a concrete, observed failure. It does not reframe the goal (that is `/think`) or judge an approach (that is `/challenge`).

Design sources: David Agans, *Debugging: 9 Indispensable Rules* (make it fail, quit thinking and look, divide and conquer, change one thing, keep an audit trail, check the plug, get a fresh view, if you didn't fix it it ain't fixed); Zeller's scientific debugging and delta debugging; Julia Evans' debugging manifesto; obra/superpowers systematic-debugging (three failed fixes means question the design); and the agent evidence — loops come from re-emitting the same failed edit (SWE-agent warns after 4–6 repeats), and self-correction without an outside signal makes answers worse (arXiv 2310.01798).

**Step 0 — Look at the real failure**
- Quote the **raw** error and stack trace, copied from output — not the summary you have been reasoning over. The exact message often names the cause.
- **Make it fail on command.** Write the exact steps that reproduce it. If you cannot, it is intermittent: say so, because a single green run then proves nothing and bisecting will give wrong answers.
- **Check the instrument.** Confirm the log, assert or test you are watching actually runs and reaches your output. A probe that never fires looks exactly like "no problem".

**Step 1 — What changed since it last worked?**
If it ever worked: what differs since then — commits, dependency versions, config, env vars, data, machine? The cheapest decisive test is often to revert to the last good state, or `git bisect` between good and bad. If reverting fixes it, the cause is inside that diff.

**Step 2 — What's been tried — now forbidden**
List every approach attempted this session and what happened. These, and near-variants of them, are **off the table** from here on. If the same fix has been tried twice, say so plainly: that is the loop.

**Step 3 — What's actually known** ← *this is the step that breaks the loop*
Separate facts (each with its evidence: output, `file:line`) from assumptions (believed, never checked). Most "known" things are assumptions.

A debug loop is almost always an unexamined assumption being retried. Do this step properly even if a hypothesis already feels obvious — the obvious hypothesis is usually the assumption you haven't checked.

**Step 4 — Find a case that works**
Somewhere this works: another input, environment, caller, branch or commit. List **every** difference between the working case and the failing one. The cause is on that list.

**Step 5 — Three fresh hypotheses**
Each in a distinct category, none of them on the forbidden list, each consistent with the facts:
- **Symptom** — is the error misleading? Is the failure really where it appears?
- **Upstream** — is the input wrong rather than the processing?
- **Environment** — config, dependencies, state, timing, caching, the wrong file being loaded.

Each must be **falsifiable** — state its prediction:

> If [X] is the cause, then [doing Y] makes the symptom disappear / [doing Z] makes it worse.

If you cannot state the prediction, it is a vibe, not a hypothesis. Sharpen it or replace it.

**Step 6 — Cheapest test, then run it**
For each hypothesis, the single fastest way to confirm or rule it out — one command, one file read. A test, not a fix. Run the cheapest now, and write down **predicted vs observed**. Where they diverge is where the bug is.

Change one thing at a time. If the test needs temporary logging, tag every line with a unique marker — `[DEBUG-a4f2]` — so removing it later is one grep rather than a re-read of the diff. Untagged debug logs are the ones that ship.

**Step 7 — Still stuck? Get a fresh view**
Dispatch a read-only agent that receives only the facts, the raw error and the reproduction steps — **not** the story of what was tried or why it should have worked. That story is what the main context is anchored on. Ask it for its single most likely cause and the test that would confirm it.

**Step 8 — Stop condition**
After **three** failed fixes, stop fixing. Three misses mean the problem is not where you are looking — question the design or the premise (`/challenge` is built for that), or hand it to the user with the minimal reproduction and the logbook below. When a fix does appear to work, prove it was the fix: remove it and watch the failure return, then put it back.

**Output format:**
```
SYMPTOM: [restated precisely]
RAW ERROR: [quoted from output]
REPRO: [exact steps] · [deterministic | intermittent | not yet reproduced]
INSTRUMENT CHECK: [the probe fires: yes / no / unchecked]
CHANGED SINCE LAST GOOD: [...] | unknown | never worked

FORBIDDEN (tried):
1. [approach] — [result]

FACTS: [each with evidence]
ASSUMPTIONS: [unverified]

WORKS vs FAILS — differences: [...]

HYPOTHESES:
1. [symptom] [hypothesis] — predicts: [...] — test: [one command]
2. [upstream] ...
3. [environment] ...

RAN: [test] — predicted: [...] — observed: [...] — rules [in | out]: [...]

NEXT: [next cheapest test | fresh-view agent | STOP — escalate with repro + logbook]
```
