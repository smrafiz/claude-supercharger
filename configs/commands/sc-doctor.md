Diagnose this Claude Supercharger installation. Arguments: $ARGUMENTS

Run the installed diagnostic and report its output:

```bash
bash ~/.claude/supercharger/tools/claude-check.sh 2>&1
```

Then do three things, in this order:

1. **Lead with the one-line verdict** the script prints under "Paste this if you
   are asking for help". That line is the deliverable — it is what a colleague
   can send back when something is wrong.
2. **Name only what actually failed.** Do not restate passing checks; a report
   that lists everything is a report nobody reads to the end.
3. **Give the single next action.** Almost every finding resolves to `/sc-update`
   (a partial install, stale version, or old permissions). Say so plainly rather
   than explaining the check.

If the script is missing, the install is broken in a way this command cannot
diagnose — tell the user to re-run the installer rather than guessing.
