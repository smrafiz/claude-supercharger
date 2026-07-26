Generate a structured session handoff brief. Context: $ARGUMENTS

This produces a machine-readable resume that can be pasted into the next session or consumed by session-memory-inject.

**Step 1 — Gather state**
Read git status, recent commits, modified files, and any .claude/supercharger-memory.md.

**Step 2 — Compile brief**
Fill in every field. Leave nothing blank — write "none" if empty.

**Step 3 — Write to file**
Write a **session-scoped** file so concurrent sessions in the same project don't clobber each other's brief. Get this session's id from the `CLAUDE_CODE_SESSION_ID` environment variable and save to `.claude/handoff-$CLAUDE_CODE_SESSION_ID.md` in the project root (e.g. `bash -c 'echo "$CLAUDE_CODE_SESSION_ID"'` to read it). If that variable is empty, fall back to `.claude/handoff.md`. The auto-load hooks (`session-memory-inject`, `post-compact-inject`) prefer this session's own file, then the newest recent one, then the legacy unsuffixed path — so the suffixed name loads correctly on resume.

Output format:
```
## Handoff — [project name] — [date]

### Done
- [completed item with file paths]

### In Flight
- [started but incomplete, with current state]

### Decisions Made
- [decision]: [rationale]

### What Failed
- [approach]: [why it didn't work]

### Blockers
- [blocker]: [what's needed to unblock]

### Files Touched
- [file path]: [what changed and why]

### Resume With
[paste-ready prompt for next session — 2-3 sentences max]
```
