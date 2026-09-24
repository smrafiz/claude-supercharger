Score this session and write quality observations to memory: $ARGUMENTS

Run after completing significant work. Scores what worked, what didn't, and writes structured observations that future sessions will load — building a project-specific improvement signal over time.

Do NOT summarize what was done. Focus only on quality signals: what patterns helped, what went wrong, what should change next time.

Design sources: the US Army after-action review (what was supposed to happen, what happened, why the gap, what to keep or change), Google SRE blameless postmortems and Etsy's debriefing guide (systemic causes, action items that can be checked), the critiques of 5 Whys (single-cause tunnel vision), Reflexion (keep the evaluator separate from the reflector), and two findings that shape everything here: models do not reliably correct their own reasoning without an outside signal (arXiv 2310.01798), and their self-assigned scores are poorly calibrated. So every score and every lesson below must point at something that **happened**, not at how the session felt.

**Step 1 — Evidence ledger (no judgement yet)**
List what the session actually shows:
- tests, builds, lint and type checks — which ran, which passed, which failed
- tool errors and permission denials; the same call retried
- commits reverted or amended; fixes that needed a second attempt
- **user corrections** — "no", "that's wrong", "revert", "I said…", a repeated request
- claims of "done" and whether a check backed them

If the ledger is empty — no checks ran, nothing failed, nobody corrected anything — stop: "Not enough signal to reflect on this session." A score with nothing under it is a guess.

**Step 2 — Intent vs outcome**
One line: what was this session supposed to achieve, and what actually happened? The gap between them is what the rest explains.

**Step 3 — Score from the ledger**
Each dimension is 0–3 **with the ledger item that justifies it**, or `n/a — no evidence`.

| Dimension | 0 | 3 |
|---|---|---|
| **Accuracy** | Multiple wrong assumptions, rework required | First-attempt correct, no backtracking |
| **Scope discipline** | Drifted beyond what was asked | Stayed tightly scoped |
| **Verification** | Claimed done without evidence | Ran checks, confirmed output |
| **Efficiency** | Many redundant tool calls / retries | Direct path to solution |

**Step 4 — Why the gap**
For each dimension below 2: list the contributing factors (usually more than one), not a single chain of whys. Name them as system causes — "the check that would have caught it never ran" — rather than "I was careless". Find the one whose fix lives in a shared place: a test, a guard, a step in a command.

**Step 5 — Keep only lessons that pass all four**
1. **Grounded** — traces to a ledger item.
2. **General** — would change what a *different* future task does, not just this one.
3. **Checkable** — names a concrete action or trigger: "run the suite before claiming done when X", "grep every caller of a shared function before editing it". "Be more careful" fails.
4. **New** — not already in the observations file or project memory. If it is, strengthen that entry instead of adding a duplicate; if it contradicts one, say so and reconcile.

Most sessions produce zero or one lesson. That is the expected result. A rule the user stated goes to `/learn`; the reason behind a design decision goes to `/devlog`.

**Step 6 — Write to `.claude/session-observations.md`**
Create if absent. Prepend the new entry (most recent first). **Lessons go on the lines right after the heading, with no blank lines**: the next session loads only the first four lines of each of the three newest entries, so anything further down is never seen.

```markdown
## YYYY-MM-DD — [one-line description of work done]
- [lesson 1 — the checkable action · evidence: ledger item]
- [lesson 2, if any]
- [lesson 3, if any]
Scores: accuracy=N scope=N verification=N efficiency=N · gap: [one line]
```

At most three lessons per entry. Cap the file at 50 entries — trim the oldest if exceeded.

**Step 7 — Confirm**
State: `Reflection written. [N] lesson(s) logged to .claude/session-observations.md` — and name what you deliberately did **not** record and why (not grounded, too specific to this task, or already recorded).
