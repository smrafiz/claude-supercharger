Record an explicit user-stated rule. Arguments: $ARGUMENTS

Capture `$ARGUMENTS` as a project rule. Rules recorded here are shown to Claude on **every** prompt in this project (by `hooks/lesson-recall.sh`, newest 10), so keep each one short and genuinely standing.

**Action:**

1. **Validate** — `$ARGUMENTS` must contain a clear directive (verb + object). If empty or vague (fewer than 4 words, no verb), respond: `Usage: /learn <rule>. Example: /learn always use pnpm in this project.` If it describes a one-off ("fix the login bug"), it is a task, not a rule — say so and stop.

2. **Find the file** — `.claude/supercharger/lessons.jsonl` at the project root (walk up from cwd to the directory holding `.git`).

3. **Check for a duplicate or a contradiction** — read the existing `"source":"user-explicit"` lines. Same rule already there → say so and stop. A rule that contradicts an existing one ("always use npm" vs "always use pnpm") → show both and ask which to keep; replace the old line only if the user confirms.

4. **Append one line**, in the schema `hooks/lesson-record.sh` writes:

```json
{"sig":"<user rule>","fix":"<rule restated as instruction>","files":[],"lesson":"<rule>","recall":"<lowercase tokens of length ≥ 3, deduped, sorted, space-joined>","ts":"<ISO timestamp>","source":"user-explicit"}
```

`"source":"user-explicit"` is what makes the rule show on every prompt instead of only on keyword matches — never omit it.

5. **Confirm** — print:

```
✓ Recorded: <rule>
  → .claude/supercharger/lessons.jsonl
  → shown on every prompt in this project (user rules in effect: <N>, newest 10 shown)
  → to remove it later: delete that line from the file
```

**Do not:**
- Fabricate context the user did not state.
- Apply the rule retroactively to past code.
- Modify any other config file.

Stop after the confirmation message. Do not ask follow-up questions, except the contradiction check in step 3.
