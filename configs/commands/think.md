Structured reasoning for an ambiguous problem. Apply this process to: $ARGUMENTS

This command FRAMES a problem before anyone commits to an answer. It ends in a direction, not a verdict. Siblings: `/challenge` stress-tests a decision once made (pre-mortem, kill criteria); `/stuck` breaks a failing debug loop. Do not do their jobs here.

Design sources: Cynefin (Snowden & Boone — the right method depends on the kind of problem), Rephrase-and-Respond (arXiv 2311.04205), Step-Back prompting (arXiv 2310.06117), least-to-most decomposition (arXiv 2205.10625) and MECE issue trees, Platt's strong inference (Science, 1964), analogical prompting (arXiv 2310.01714), Anthropic's "think" tool and extended-thinking guidance — and the overthinking evidence that accuracy falls when simple problems get long chains.

**Rule for every step:** a KNOWN cites `file:line`, command output or a doc read this session. Anything else is ASSUMED. Read the repo and run read-only commands wherever a fact can be checked instead of believed.

**Step 0 — Size the problem and pick the method**
- **Clear** — the answer is known or a lookup away. Answer in two lines and stop. More reasoning makes simple answers worse, not better.
- **Complicated** — knowable by analysis. Run Steps 1–7 and converge on a direction.
- **Complex** — cause and effect are only visible in hindsight (user behaviour, performance under real load, an unfamiliar system). Hypotheses stay provisional; end with a cheap, safe-to-fail probe, not a direction.
- **Chaotic** — something is on fire. Stabilize first (roll back, stop the bleeding), then come back.

**Step 1 — Clarify the question**
Restate it, then list the 2–3 readings it could plausibly have. Name the one you are taking and why. If the choice changes the answer and the context cannot settle it, ask exactly one question.

**Step 2 — Step back**
What is the general question behind this specific one — the principle, pattern or class of problem it belongs to? Have you, or this repo, solved a relevant one before (an earlier commit, PR or module)? What worked there?

**Step 3 — Ground what is known**
KNOWN (cited) · ASSUMED (flagged) · UNKNOWN. Check the assumptions that are cheap to check before going further.

**Step 4 — Decompose**
Break the question into sub-questions that do not overlap and together cover it. Mark the **crux**: the one the others depend on.

**Step 5 — Hypotheses**
Two or three candidate answers to the crux. They are distinct only if each **predicts something different you could observe**. Two hypotheses ruled out by the same observation are one hypothesis. For each: what it predicts, what supports it, and what single observation would rule it out.

**Step 6 — The decisive fact**
The cheapest read-only fact that would most change the answer, and exactly how to get it (a file, a command, a query). If you can get it now, get it and update Step 5.

**Step 7 — Direction**
The leading path and your confidence in it. Not a verdict: before committing to anything expensive or hard to reverse, it goes through `/challenge`. In a complex problem, give the probe instead.

**Output format:**
```
FRAME: [question] · KIND: [clear | complicated | complex | chaotic]
READINGS: [A] / [B] → taking [A], because [...]
STEP BACK: [general question] · related prior solution: [ref | none found]

KNOWN:   [fact — file:line / command]
ASSUMED: [belief — unverified]
UNKNOWN: [gap]

CRUX: [the sub-question the rest depends on]

H1: [answer] — predicts: [observable] — supported by: [...] — ruled out by: [...]
H2: ...

DECISIVE FACT: [what] — how: [command / file] — [result, if already checked]

DIRECTION: [leading path] · confidence: [low | medium | high]
NEXT: [/challenge before committing | PROBE: safe-to-fail test for a complex problem]
```
