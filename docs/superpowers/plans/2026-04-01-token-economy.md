# Token Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add token economy rules to reduce output ~40-50% without sacrificing response quality.

**Architecture:** Rules-only approach — add a Token Economy section to CLAUDE.md, upgrade Output Discipline and Context Carry-Forward in supercharger.md, append Token Efficiency to each of the 5 role configs. No new files, hooks, or infrastructure.

**Tech Stack:** Markdown config files, bash test runner

---

### Task 1: Add Token Economy section to CLAUDE.md template

**Files:**
- Modify: `configs/universal/CLAUDE.md:10-11` (insert between Response Principles and Verification Gate)

- [ ] **Step 1: Add Token Economy section**

Insert after line 11 (end of Response Principles) and before Verification Gate:

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

- [ ] **Step 2: Remove redundant line from Response Principles**

Line 10 currently says `- Match response length to question complexity`. This is now superseded by the concrete targets in Token Economy. Remove it.

- [ ] **Step 3: Commit**

```bash
git add configs/universal/CLAUDE.md
git commit -m "feat: add token economy section to CLAUDE.md template"
```

---

### Task 2: Upgrade Output Discipline in supercharger.md

**Files:**
- Modify: `configs/universal/supercharger.md:26-30`

- [ ] **Step 1: Replace Output Discipline section**

Replace lines 26-30:

```markdown
## Output Discipline
- Every sentence must be load-bearing — no filler
- Code output: no comments unless asked, no boilerplate
- Deliver the result first, then offer one optimization note if relevant
- Never pad responses with unrequested explanations
```

With:

```markdown
## Output Discipline
- Every sentence load-bearing — no filler, no hedging, no caveats
- Code: deliver the diff or block, nothing else
- Errors: what failed → why → fix. Three lines.
- Done: state what changed and what to verify. Two lines.
- Never: "I hope this helps", "Feel free to ask", "Happy to help"
```

- [ ] **Step 2: Commit**

```bash
git add configs/universal/supercharger.md
git commit -m "feat: upgrade output discipline rules in supercharger.md"
```

---

### Task 3: Expand Context Carry-Forward in supercharger.md

**Files:**
- Modify: `configs/universal/supercharger.md:40-44`

- [ ] **Step 1: Expand Context Carry-Forward section**

Replace lines 40-44:

```markdown
## Context Carry-Forward
For multi-turn tasks (3+ related prompts):
- Track: decisions made, constraints established, what failed
- When referencing prior work, state what you're building on
- If context was compacted, reconstruct key decisions before proceeding
```

With:

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

- [ ] **Step 2: Commit**

```bash
git add configs/universal/supercharger.md
git commit -m "feat: add compaction preserve/discard rules to context carry-forward"
```

---

### Task 4: Add Token Efficiency to all 5 role configs

**Files:**
- Modify: `configs/roles/developer.md` (append)
- Modify: `configs/roles/writer.md` (append)
- Modify: `configs/roles/student.md` (append)
- Modify: `configs/roles/data.md` (append)
- Modify: `configs/roles/pm.md` (append)

- [ ] **Step 1: Append to developer.md**

Add at end of file:

```markdown

## Token Efficiency
- Code blocks only — no surrounding explanation unless asked
- One-line commit messages unless change is multi-faceted
- Error fixes: show the diff, not the reasoning
```

- [ ] **Step 2: Append to writer.md**

Add at end of file:

```markdown

## Token Efficiency
- Draft content at requested length — don't over-deliver
- Meta-discussion (outlines, options, revision notes) stays under 5 lines
- Edits: show the changed text, not a description of what changed
```

- [ ] **Step 3: Append to student.md**

Add at end of file:

```markdown

## Token Efficiency
- Explanations are the product — don't cut them for brevity
- Cap examples at 1 per concept unless asked for more
- After teaching, stop — don't add "you might also want to know..."
```

- [ ] **Step 4: Append to data.md**

Add at end of file:

```markdown

## Token Efficiency
- Tables and queries are the product — deliver at full fidelity
- Narrative summaries stay under 3 lines
- Methodology notes: 1-2 lines, not paragraphs
```

- [ ] **Step 5: Append to pm.md**

Add at end of file:

```markdown

## Token Efficiency
- Bullet-only output — no prose paragraphs
- Status updates: 3 lines max (done / doing / blocked)
- Decision logs: options | decision | rationale — one line each
```

- [ ] **Step 6: Commit**

```bash
git add configs/roles/developer.md configs/roles/writer.md configs/roles/student.md configs/roles/data.md configs/roles/pm.md
git commit -m "feat: add token efficiency rules to all 5 role configs"
```

---

### Task 5: Run tests and update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run existing test suite**

```bash
bash tests/run.sh
```

Expected: 57 passed, 0 failed. No tests should break since changes are content-only (markdown rules).

- [ ] **Step 2: Update CHANGELOG**

Add under the `### Ship-Ready Fixes` section in CHANGELOG.md:

```markdown
- **Token economy:** Added concrete response length targets, output discipline upgrade, role-specific token efficiency rules, and compaction preserve/discard guidance
```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add token economy entry to CHANGELOG"
```

---

## Dependency Graph

```
Task 1 (CLAUDE.md) ──┐
Task 2 (Output)   ───┤
Task 3 (Context)  ───┼──→ Task 5 (Tests + CHANGELOG)
Task 4 (Roles)    ───┘
```

Tasks 1-4 are independent — can run in parallel. Task 5 depends on all of them.
