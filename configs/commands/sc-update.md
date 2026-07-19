Check for and apply Claude Supercharger updates. Arguments: $ARGUMENTS

**Step 1 — Check for updates**

```bash
bash ~/.claude/supercharger/tools/update.sh --check 2>&1 || true
```

If `--check` reports no update available, stop here and tell the user they're on the latest version.

**Step 2 — Apply update (if available)**

If an update is available, apply it **non-interactively** with `--yes`. The plain
`update.sh` prompts on stdin ("Update now?" / "Proceed?"), which a tool-invoked
shell can't answer — it just hangs. `--yes` (a.k.a. `-y` / `--non-interactive`)
skips both prompts so the update applies on the fly. Tell the user it's updating,
then run:

```bash
bash ~/.claude/supercharger/tools/update.sh --yes 2>&1
```

(The update backs up existing config and preserves your settings before reinstalling.)

**Step 3 — Report what changed**

After a successful update:
- State the old version → new version
- Note any new hooks, commands, or tools mentioned in the output
- Remind the user: type `/supercharger` to see all available commands
