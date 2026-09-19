# Why the economy layer does not bind — 2026-09-19

**Question.** The active tier has been `minimal` for an entire session. Output has been
anything but telegraphic. Is the model ignoring the instruction, or is the instruction
not arriving?

**Why it was run.** The one external user this project has uninstalled it, and reported
finding "nothing useful compared to vanilla Claude Code". His own Claude independently
advised him to keep the Bash safety hooks and drop the economy tiers, the role files and
the `[CTX]` injection. Two independent signals that the prompt layer does not bind. This
document establishes which of three possible causes is real, because they have different
fixes and only one of them is a bug.

**Answer, up front.** Three separate causes. Two are defects; the third is not, and no
amount of fixing will make it go away.

| # | Cause | Status |
|---|---|---|
| 1 | The auto-switch input never arrives — the feature has never executed | **Bug.** Fixable. |
| 2 | Reinforcement fires twice a session, not every Nth prompt | **Bug.** Comment and gate disagree. |
| 3 | The instruction is outnumbered ~26:1 by rules asking for the opposite | **Design collision.** Not fixable by re-injection. |

---

## 1. `adaptive-economy.sh` has never run. Not once.

`hooks/adaptive-economy.sh:34` reads `.context_window.used_percentage` from the
`UserPromptSubmit` payload. That field is not in that payload. The hook's own comment,
at `:28`, says so — it was added while optimising the *speed* of the dead path:

> `context_window` is not part of the UserPromptSubmit payload at all, so the old
> `[ -z "$PCT" ]` test fired on every prompt and paid ~20ms for a python fork

So the hook exits at `:44` (`[ -z "$PCT" ] && exit 0`) on every prompt of every session.

**The logic is correct.** Given the field, it works exactly as designed — measured with
an isolated `SUPERCHARGER_STATE`:

```
$ printf '{"session_id":"p","cwd":"…","context_window":{"used_percentage":85}}' \
    | SUPERCHARGER_STATE=$ST bash hooks/adaptive-economy.sh
[Supercharger] adaptive-economy: 85% tier=lean -> minimal
{"hookSpecificOutput":{…"additionalContext":"[ECO] Auto-switched to Minimal (context at 85%)"}}
tier now: minimal
history: {"date":"2026-09-19","tier_before":"lean","tier_after":"minimal","context_pct":85}
```

This is a plumbing failure, not a logic failure. Worth stating plainly, because the
tempting fix — rewriting the switch logic — would change working code.

**The receipts are missing — across 62 sessions.** Each of these hooks writes a state file
on its only success path. Those files are the receipt: present means it fired, absent
means it never did. On this install:

```
sessions ever seen:    62      (scope/.session-root-*)
economy-history:       absent  (adaptive-economy writes it on every switch)
compact-band receipts: 0       (auto-compact writes .compact-last-band-<sid>)
ctx-advisor receipts:  0       (context-advisor writes .ctx-advisor-peak-<sid>)
```

Sixty-two sessions, three hooks, zero receipts. That is the load-bearing evidence here —
stronger than reading the source, and the check to repeat on any other install before
assuming this is universal.

**Three hooks read the same missing field:**

| Hook | Event | Line | Effect |
|---|---|---|---|
| `hooks/adaptive-economy.sh` | UserPromptSubmit | `:34` | inert — auto-tier-switch never happens |
| `hooks/context-advisor.sh` | UserPromptSubmit | `:25` | inert — the `[CTX WARN] …run /compact` advisory never appears |
| `hooks/auto-compact.sh` | **PostToolUse** | `:45` | inert — the `[CTX HIGH]` warning never appears |

Note the third event. `auto-compact` is registered on `PostToolUse`, not
`UserPromptSubmit`, so the payload probes below say nothing about it — a
UserPromptSubmit-shaped payload is not evidence about a different event, and reading the
first two results as covering all three was the wrong turn on the way here. Its claim
rests on the receipt count alone. Its own comment at `:26` hedges where the others assert:
`used_percentage` "only rides along on payloads that carry a `context_window`".

The two UserPromptSubmit hooks, probed with the field injected, produce output
immediately — confirming the logic is fine and only the input is missing:

```
--- context-advisor WITH the field ---
[CTX WARN] 85% — run /compact now. eco minimal. …
--- auto-compact WITH the field (PostToolUse-shaped, hand-built) ---
[CTX HIGH 85%] Run /compact before continuing. …
```

`hooks/statusline.sh:97` reads the same field and **does** work, because the statusline
event genuinely carries it. That is the likely origin of the mistake: a working line
copied to an event with a different payload shape.

Scanning this session's 2209-record transcript for `context_window` returns 13 hits, all
of them text from the commands run during this investigation. No payload evidence either
way from that source — the absent history file is what carries the claim.

## 2. Reinforcement fires twice per session, not every Nth prompt

`hooks/economy-reinforce.sh` is headed:

> Re-injects active economy tier rules every Nth prompt to prevent drift.

It does not. The gate at `:56` is:

```bash
[ ! -f "$RESTORED_FLAG" ] && exit 0
```

`$RESTORED_FLAG` is written by `post-compact-inject.sh`. So the hook fires **only after a
compaction**, and its own ack flag limits it to once per compaction event. Measured:

```
--- no compaction flag ---      (no output — never fires pre-compact)
--- with compaction flag ---    [ECONOMY:MINIMAL] Telegraphic. Bare deliverables. …
--- second prompt, same flag -- (no output — once per event, not per Nth prompt)
```

Net delivery of the tier rules in a session: **once at SessionStart** (via
`~/.claude/rules/economy.md`), **once per compaction**. In this session, twice across
roughly forty turns.

What *does* arrive every single turn is `hooks/agent-router.sh:194`:

```
[CTX] task=general agent=generalist tier=minimal
```

Nine characters of tier state with no rule attached. A label, not an instruction. Anything
reading that has to already know what `minimal` obliges — which is exactly the knowledge
that decays.

**This may be deliberate.** Per-turn reinforcement costs tokens on every prompt, which is
in tension with the point of an economy tier. But the comment claims behaviour the code
does not have, and that is what sent this investigation down the wrong path first.

## 3. The instruction is outnumbered, and contradicted by its own siblings

Every session loads 12,586 characters of prompt layer:

| File | Chars |
|---|---|
| `rules/supercharger.md` | 4,846 |
| `rules/economy.md` | 2,720 |
| `CLAUDE.md` | 2,459 |
| `rules/guardrails.md` | 1,570 |
| `rules/developer.md` | 991 |

Of `economy.md`'s 2,672 characters, the **active tier rules are 463** — the rest is a
logic-shorthand table, an output-type taxonomy, a safety override and switching
instructions. So about **3.7% of the prompt layer** says "be terse".

The other 96% asks for the opposite, and asks for it *specifically*:

- `supercharger.md` — "Verification Gate (4-level check) … verify at all applicable levels"
- `supercharger.md` — "Error Recovery: … explain what was tried"
- `guardrails.md` — "When escalating, report: what you're trying to do, what's blocking
  you, **options considered with trade-offs**, recommended action"
- `developer.md` — "note what was changed and why"

When the task is "explain why X is broken", the reporting rules are *on-task* and the
terseness rule is *generic*. Specific instructions beat generic ones. Economy does not
lose a fight about obedience; it loses a fight about relevance, against four resident
rules that asked first and asked more precisely.

`economy.md` also undercuts itself. Its own **Safety Override** section suspends terse
mode for "security warnings and vulnerability disclosures" and "irreversible/destructive
action confirmations". On this repo — a guardrail framework whose daily subject matter is
denials, bypasses and releases — that override is load-bearing most of the time.

**This is not fixable by injecting harder.** Re-injecting 463 characters more often does
not resolve a contradiction with 4,846 characters that were never reconciled with it.
The resolution is editorial: decide which layer owns output length, and delete the claim
from the others.

---

## What this changes

The external user's verdict was read as a UX complaint. It is better read as accurate
reporting. A third of the economy layer never executed, another third fires twice a
session, and the remainder is out-argued by this project's own other rule files. "Nothing
useful compared to vanilla" is a fair description of that.

It also reframes the open positioning question in `docs/ROADMAP.md`. The question was
whether the prompt layer should be opt-in. The prior evidence was "it does not seem to
bind", which invites a fix. The evidence now is that **it largely does not run**, which is
a different question: fix the plumbing first, then re-measure whether the layer binds when
it is actually delivered. Deciding opt-in before that measurement would be deciding on
data produced by a bug.

## Fixes

Ordered by confidence, not by size.

1. **The three dead `context_window` readers.** Either move the logic to an event whose
   payload carries the field, or delete the readers and their hook registrations. Do not
   leave a hook registered that cannot fire — it costs a process spawn per prompt to
   return nothing. `hooks/statusline.sh` should keep its copy; it works.
2. **`economy-reinforce.sh`'s header comment.** Make it describe the post-compaction gate
   it actually has. If per-turn reinforcement is wanted, that is a separate decision with
   a token cost attached, and it should not be made by rewording a comment.
3. **The contradiction in #3.** Editorial, not mechanical, and the one that needs a human
   decision: pick the single file that owns output length and strip the competing claims
   out of the other three.

## Not concluded

- Whether `context_window` is absent from `UserPromptSubmit` on **all** Claude Code
  versions, or was removed at some point. The probes here establish it is absent now, on
  this version. A hook that silently does nothing when a field disappears is the deeper
  problem, and neither the tests nor CI would have caught it.
- Whether the layer binds **when properly delivered.** Unmeasurable until #1 and #2 are
  fixed. This document deliberately does not claim the tiers would work if delivered —
  that is the next experiment, not a finding.
