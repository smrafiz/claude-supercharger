Record an explicit user-stated rule. Arguments: $ARGUMENTS

Capture `$ARGUMENTS` as a high-confidence project rule that will be surfaced on future prompts.

**Action:**

1. **Validate** — `$ARGUMENTS` must contain a clear directive (verb + object). If empty or vague (less than 4 words, no verb), respond: `Usage: /learn <rule>. Example: /learn always use pnpm in this project.`

2. **Append a lesson record** to `.claude/supercharger/lessons.jsonl` (per-project, walk up from cwd to find the project root):

```json
{"sig":"<user rule>","fix":"<rule restated as instruction>","files":[],"lesson":"<rule>","recall":"<lowercase tokens of rule, deduped, joined by space>","ts":"<ISO timestamp>","source":"user-explicit"}
```

3. **Optionally update `.supercharger.json`** — if a `hints` field exists, append the rule to it (newline-separated). If no `.supercharger.json`, do not create one (out of scope).

4. **Confirm** — print:

```
✓ Recorded: <rule>
  → lessons.jsonl (1 entry added)
  → will surface on prompts containing: <top 3 keywords>
```

**Do not:**
- Fabricate context the user did not state.
- Apply the rule retroactively to past code.
- Modify any other config file.

**Do:**
- Use the same JSONL schema as `hooks/lesson-record.sh` for compatibility with `hooks/lesson-recall.sh` (Jaccard match).
- Mark `source: "user-explicit"` so future analysis can distinguish from auto-captured lessons.
- Use lowercase tokens of length ≥ 3, deduped and sorted, for the `recall` field.

Stop after the confirmation message. Do not ask follow-up questions.
