---
description: "Clear writing mode: Simplified Technical English, about 80% (on, off or status)."
argument-hint: "on | off | status"
disable-model-invocation: true
---
Switch the clear writing mode. Argument: $ARGUMENTS (on | off | status; default status)

Clear writing mode makes your prose follow Simplified Technical English (ASD-STE100)
about 80% of the way: one instruction per sentence, short sentences, active voice,
simple words, steps in numbered lists, warnings before the step. Code, commands and
paths are never changed. It sets how you write; the economy tier still sets how much.

**Run it** (pass the argument straight through; default to `status`):

```bash
bash ~/.claude/supercharger/tools/writing-mode.sh ste $ARGUMENTS
```

Report the tool's output in one line.

Rule files load when a session starts, so the tool only changes later sessions.
- After **on**: read `~/.claude/rules/sc-mode-ste.md` and follow it for the rest of
  this session too.
- After **off**: stop following it in this session.

Use `bash ~/.claude/supercharger/tools/writing-mode.sh list` to see every writing mode.
