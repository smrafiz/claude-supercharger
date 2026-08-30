Generate a structured session handoff brief. Context: $ARGUMENTS

This produces a machine-readable resume that can be pasted into the next session or consumed by session-memory-inject.

**Modes.** Default is the terse brief below. If `$ARGUMENTS` contains `--deep`,
ALSO do Step 4 (extended brief) and Step 5 (memory pass). That exact spelling —
no aliases.

Deep mode is for the end of a long or expensive session — one that burned hours,
changed direction, or produced findings that would cost real money to rediscover.
It is not the default because most sessions do not earn it, and a brief nobody
reads is worse than a short one somebody does.

**Step 1 — Gather state**
Read git status, recent commits, modified files, and any .claude/supercharger-memory.md.

**Step 2 — Compile brief**
Fill in every field. Leave nothing blank — write "none" if empty.

**Redact before writing.** This brief is assembled from git output, config, and command
history — the places secrets actually live. Strip API keys, tokens, passwords, connection
strings and personal data. Never paste a config dump verbatim to "capture state"; describe
it instead. A handoff is read by a fresh agent that has no idea which strings are secret.

**Reference, don't restate.** If it is already in a commit message, CHANGELOG entry, ADR,
issue, PR or diff, link the path or ref instead of copying it. The brief is for what is
*not* recoverable from the repo: why a decision was made, what was tried and abandoned,
what is half-finished. Anything git can already tell the next session is bloat.

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

### Start With
[the 1-2 Supercharger commands the next session should run first, and why —
 e.g. "/resolve-conflicts — the rebase is mid-flight" or "/why — a guard fired
 and the cause is unclear". Write "none" if nothing applies. Use /supercharger
 <situation> if you are unsure which command fits.]
```

---

## Deep mode only (`--deep`)

**Step 4 — Extended sections.** Append these to the brief above. Every one is
for something a fresh agent CANNOT reconstruct from the repo. If a section has
nothing real in it, write "none" and move on — padding a section is how these
files stop being read.

```
### Measurements
[Exact numbers with the fixture that produced them: "safety.sh 50ms at 43 bytes,
 1520ms at 41KB (scratchpad/safety-vs-len.py)". Never round, never paraphrase a
 quantitative result. A number without its method is a rumour.]

### Rejected — do not rebuild
[Each approach that was considered and dropped, WITH the evidence that killed it.
 "Structural injection slice: caught 4/4 injections, fired on 9/12 ordinary
 command outputs — rejected." Without the measurement the next session re-derives
 it and ships the thing that fails.]

### Dead ends
[Investigations that produced nothing, so they are not retried: paths searched,
 tools that could not answer, hypotheses that were disproved and how.]

### Open questions
[What is genuinely unknown, and what evidence would settle it. Distinguish
 "unverified" from "verified false" — they lead to different next moves.]

### Reproduce
[The exact commands to re-derive the session's key results: probe scripts, test
 invocations, CI queries. Paths to scratchpad probes worth keeping.]
```

**Verify before you write.** Every claim in the brief must be something you
checked this session, not something you believe. If you write "X is fixed",
confirm it by behaviour first. A confidently wrong handoff is worse than a
missing one, because the next session builds on it.

**Step 5 — Memory pass.** The brief dies with the project directory; file-memory
outlives it. For each durable lesson from this session:

1. **Check for an existing entry first** — read the memory index and look for a
   file that already covers it. Update that file rather than creating a near
   duplicate; a second entry on the same lesson makes both weaker.
2. **Only durable facts.** A lesson qualifies if it would change behaviour in a
   FUTURE session on a different task. Skip anything the repo already records
   (code structure, git history, CLAUDE.md) and anything true only of this
   conversation.
3. **Write the why.** A rule without its cause gets overridden the first time it
   is inconvenient. Include the incident that produced it and the measurement if
   there was one.
4. **Convert relative dates to absolute** ("today" and "last week" rot).
5. **Link related entries** so the next recall pulls the whole cluster.
6. **Add one index line per new entry.** An entry the index does not point at is
   an entry that never loads.

State plainly in your reply which memory files you created or updated, and which
lessons you deliberately did NOT save and why. Do not claim to have recorded
something without checking that the file exists — that claim has been wrong
before, and it is cheap to verify.
