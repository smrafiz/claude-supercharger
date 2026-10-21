---
description: "List what left the machine: pushes, publishes, sends and uploads."
argument-hint: "[today|session|7d|all] [--here]"
allowed-tools: Bash(python3 ~/.claude/supercharger/tools/receipts.py:*)
---
List Trust Receipts: every outward action recorded on this machine. Options: $ARGUMENTS

**Step 1 — Today's receipts** (run when this command loaded):

```
!`python3 ~/.claude/supercharger/tools/receipts.py today`
```

Only if `$ARGUMENTS` asks for another span (`session`, `7d`, `all`) or `--here`, run it yourself:

```bash
python3 ~/.claude/supercharger/tools/receipts.py $ARGUMENTS
```

**Step 2 — Present it**

Show the table as-is. Then one line: anything the user may not expect (a destination
outside their own repos or services, a send to an unfamiliar domain). Say nothing more
when every row is expected.

Receipts are local only (`~/.claude/supercharger/receipts/`) and never uploaded. They
hold a destination and a one-line summary with secrets masked, never a message body.
Turn recording off with `SUPERCHARGER_RECEIPTS=0`.
