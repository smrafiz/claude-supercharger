Check for and apply Claude Supercharger updates. Arguments: $ARGUMENTS

**Step 1 — Check for updates**

```bash
bash ~/.claude/supercharger/tools/update.sh --check 2>&1 || true
```

If `--check` reports no update available, stop here and tell the user they're on the latest version.

**Step 2 — Apply update (if available)**

If an update is available, confirm with the user before proceeding. Then run:

```bash
bash ~/.claude/supercharger/tools/update.sh 2>&1
```

**Step 3 — Report what changed**

After a successful update:
- State the old version → new version
- Note any new hooks, commands, or tools mentioned in the output
- Remind the user: type `/supercharger` to see all available commands
