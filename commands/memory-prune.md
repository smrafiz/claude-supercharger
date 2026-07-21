Archive resolved memory entries so they stop loading into context every session. Arguments: $ARGUMENTS

Claude's file-memory (`~/.claude/projects/<project>/memory/`) loads its `MEMORY.md`
index into context at the start of every session. Entries that are done — resolved,
superseded, debunked — keep costing tokens forever. This prunes them **safely**:
it only auto-archives entries the author explicitly marked `status: resolved` (or
`superseded`) with `type: project`; everything else is only *suggested*. Nothing is
deleted — entries move to `memory/archive/` and can be restored.

**Step 1 — show what would happen (default, no changes):**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/memory-prune.sh
```

This prints three groups: **Auto-archivable** (will move on `--apply`), **Suggestions**
(project entries with a terminal marker or >90d untouched — you decide), and entries
**marked resolved but not `type: project`** (left in place by design).

**Step 2 — decide.** If `$ARGUMENTS` contains `apply` (or the user confirms), archive
the auto-archivable set:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/tools/memory-prune.sh --apply
```

For an entry in the **Suggestions** list that the user confirms is done, don't force it —
edit that entry's frontmatter to add `status: resolved` under `metadata:`, then re-run
`--apply`. That keeps the author-declared safety model intact.

**Other actions:**
- `bash ${CLAUDE_PLUGIN_ROOT}/tools/memory-prune.sh --list-archive` — show archived entries.
- `bash ${CLAUDE_PLUGIN_ROOT}/tools/memory-prune.sh --restore <name>` — bring one back (re-adds its index line).

**Report** the tool output verbatim, then state how many entries were archived (or would be)
and the approximate per-session token saving (each index line ≈ 40–60 tokens).
