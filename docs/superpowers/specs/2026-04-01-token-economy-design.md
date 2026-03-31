# Token Economy Feature — Design Spec

**Date:** 2026-04-01
**Goal:** Reduce token exchange ~40-50% without sacrificing response quality
**Scope:** CLAUDE.md template, supercharger.md, 5 role configs
**Approach:** Rules-only + smarter context preservation (no new hooks/infrastructure)

## Motivation

Claude Code's default output is verbose: preambles, restating, hedging, unsolicited alternatives, sign-offs. This wastes API credits and burns context window faster. Users who install Supercharger are power users running long sessions — they need both cost savings and longer productive sessions.

Current state: CLAUDE.md has vague "match response length to question complexity." supercharger.md has a 4-line Output Discipline section. Neither provides concrete targets.

## Changes

### 1. Token Economy Section (CLAUDE.md template)

New section between "Response Principles" and "Verification Gate":

```markdown
## Token Economy
- Responses: 1-3 lines for simple tasks, max 10 lines for complex ones
- Code: no comments, no imports the user can infer, no boilerplate wrappers
- Never repeat back the user's request or restate what you just did
- Lists over prose, tables over lists, symbols over words when meaning is preserved
- One completion per turn — don't offer alternatives unless asked
- Skip: "Here's what I found", "Let me explain", "Great question", preambles, sign-offs
- When asked "did it work?" → "Yes." or "No — [reason]." Not a paragraph.
```

### 2. Role-Specific Token Calibration

Append to each role's existing config file:

**Developer** (`configs/roles/developer.md`):
```markdown
## Token Efficiency
- Code blocks only — no surrounding explanation unless asked
- One-line commit messages unless change is multi-faceted
- Error fixes: show the diff, not the reasoning
```

**Writer** (`configs/roles/writer.md`):
```markdown
## Token Efficiency
- Draft content at requested length — don't over-deliver
- Meta-discussion (outlines, options, revision notes) stays under 5 lines
- Edits: show the changed text, not a description of what changed
```

**Student** (`configs/roles/student.md`):
```markdown
## Token Efficiency
- Explanations are the product — don't cut them for brevity
- Cap examples at 1 per concept unless asked for more
- After teaching, stop — don't add "you might also want to know..."
```

**Data** (`configs/roles/data.md`):
```markdown
## Token Efficiency
- Tables and queries are the product — deliver at full fidelity
- Narrative summaries stay under 3 lines
- Methodology notes: 1-2 lines, not paragraphs
```

**PM** (`configs/roles/pm.md`):
```markdown
## Token Efficiency
- Bullet-only output — no prose paragraphs
- Status updates: 3 lines max (done / doing / blocked)
- Decision logs: options | decision | rationale — one line each
```

### 3. Context Carry-Forward Upgrade (supercharger.md)

Replace existing "Context Carry-Forward" section (lines 41-44):

```markdown
## Context Carry-Forward
For multi-turn tasks (3+ related prompts):
- Track: decisions made, constraints established, what failed
- When referencing prior work, state what you're building on
- If context was compacted, reconstruct key decisions before proceeding

Preserve through compaction:
- Decisions made and constraints locked
- File paths and patterns established
- What was tried and failed

Discard through compaction:
- Full file contents already read (re-read if needed)
- Verbose tool output (keep only the result line)
- Exploratory discussion that led to a decision (keep the decision)
```

### 4. Output Discipline Upgrade (supercharger.md)

Replace existing "Output Discipline" section (lines 27-30):

```markdown
## Output Discipline
- Every sentence load-bearing — no filler, no hedging, no caveats
- Code: deliver the diff or block, nothing else
- Errors: what failed → why → fix. Three lines.
- Done: state what changed and what to verify. Two lines.
- Never: "I hope this helps", "Feel free to ask", "Happy to help"
```

## Files Changed

| File | Change |
|------|--------|
| `configs/universal/CLAUDE.md` | Add Token Economy section (7 lines) |
| `configs/universal/supercharger.md` | Replace Output Discipline (5 lines), expand Context Carry-Forward (+6 lines) |
| `configs/roles/developer.md` | Append Token Efficiency (3 lines) |
| `configs/roles/writer.md` | Append Token Efficiency (3 lines) |
| `configs/roles/student.md` | Append Token Efficiency (3 lines) |
| `configs/roles/data.md` | Append Token Efficiency (3 lines) |
| `configs/roles/pm.md` | Append Token Efficiency (3 lines) |

## Success Criteria

- [ ] All 7 files updated with token economy rules
- [ ] Rules are concrete (specific line counts, not "be concise")
- [ ] Student role preserves explanation quality (doesn't over-cut)
- [ ] No new hooks, scripts, or infrastructure
- [ ] All 57 existing tests still pass
- [ ] CHANGELOG updated
