# Risk-triggered review — design (2026-11-06, not built)

Idea from Provost (norton77930/Provost, MIT): send a change to a fresh-context
reviewer when it touches code whose failure tests and a live run cannot show —
not when the diff is big. Today the `reviewer` agent (Gordon Ramsay, Opus) runs
only when the user asks.

## What fails today

A turn that edits a `catch` block, a parser or a lock ends with "done" after the
tests pass. Tests exercise the happy path; the swallowed error, the lossy
conversion and the race are exactly what they miss. Nothing asks for a second look.

## Channel: not the router, not a rule

- **Router hint — rejected.** `agent-router.sh` stopped sending its hint in 4.1.21:
  measured on 6,557 prompts, Claude dispatched the named agent 1.1% of the time.
- **Rules line — not enough alone.** A prose rule is advisory; the claim gate
  exists because "never say should work" was ignored.
- **Stop gate — chosen.** A Stop block's reason reaches the model (Stop
  additionalContext does not). `claim-evidence-gate.sh` already parses the turn's
  edits (`edits_of`), finds the turn start, detects a completion claim, and blocks
  once via `stop_hook_active`. This becomes its fourth arm.

## The arm: UNREVIEWED

Block the stop, once, when all hold:
1. The turn states the work is complete (the claim gate's existing detector).
2. Lines the turn **added** (Edit `new_string` minus `old_string`, Write content)
   in a code file match a risk class:

   | Class | Signals (added lines only) |
   |---|---|
   | error handling | `catch`, `except`, `rescue`, `recover()`, `finally`, `\|\| true`, `2>/dev/null`, `.catch(`, `on error` |
   | data conversion | `parse`, `serialize`, `decode`/`encode`, `JSON.`, `strconv`, `parseInt`/`Number(`, timezone/`Date(`, encoding names |
   | concurrency | `lock`, `mutex`, `atomic`, `go func`, `thread`, `Promise.all`, `async`/`await` on shared state, `flock` |

3. No `Agent` call with a reviewer agent ran **after the turn's last edit**.

Reason text: the files and the class hit, then "dispatch the reviewer on these
lines in a fresh context, or say in one line why review isn't needed". The
second stop carries `stop_hook_active` and passes, so it can cost one extra turn,
never a loop.

Auth, secrets, payments and migrations are **not** this arm: they already stop
for the user (guardrails "stop before", `human-approval-gate.sh`).

## Not by size

No line-count trigger. A 400-line rename is safe; a one-line `|| true` is not.

## Cost and noise

- Each trigger can buy one Opus review. Cap: at most one UNREVIEWED block per
  session per file (scope file `.risk-reviewed-<session>`).
- Off switch: `SUPERCHARGER_RISK_REVIEW=0`. Tests and docs files never count.

## Measure before blocking

Ship **report-only** first: log would-fire events to the audit file for two
weeks, then replay this machine's transcripts (`~/.claude/projects/*/*.jsonl`)
through the same detector and read a sample. Turn on blocking only if:
- fires on fewer than ~1 in 10 completed code turns, and
- a hand-read sample of 20 fires shows most are real risk, not `parse` in a
  comment or an `await` in a test.

If the signal list is too noisy, narrow it (drop `async`/`await`, keep
`catch`/`|| true`/`lock`) rather than widen the cap.

## Open questions

1. Reviewer model for these: Opus (current reviewer) or a Sonnet pass first?
2. Should the reason name the agent (`Gordon Ramsay (Critic)`) or just "a
   fresh-context reviewer" so a project's own reviewer agent counts?
3. Does a review by the user in chat ("I checked it") count as evidence?
