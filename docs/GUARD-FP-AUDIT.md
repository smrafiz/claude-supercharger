# Guard false-positive audit

Method taken from Steer (github.com/steer-sh/steer, MIT): read a sample of each guard's
real blocks and judge each one. Code and judgments ours.

## 2026-11-07, one machine, 30 days

**Source.** Every `PreToolUse … hook error` tool result in `~/.claude/projects/**/*.jsonl`,
paired with its `tool_use` input. Not `scope/.blocked-commands`: it cuts commands at 400
characters and rotates at 30 days, so most triggers are not visible in it.

**Sample.** 356 denials. 262 came from a project's own `.claude/hooks/*.mjs` and 12 from
another (not ours). Deduplicated by (reason, command): 56 unique Supercharger blocks across
3 projects (shopify-plinth, noorjar, claude-supercharger), plus 2 this audit hit itself.
2 were fail-closed hook failures (`onFailure`: a timeout, a crash), not judgments. **58 judged.**

**Judgment.** True positive (TP): the guard stopped what it exists to stop, whether or not
the user would have allowed it. False positive (FP): the call could not do the harm named.
One judge (the model), no second reader; borderline calls are marked.

| Guard / reason | n | TP | FP | Note |
|---|---|---|---|---|
| sensitive file (`.env`, `.npmrc`, `.claude.json`) | 15 | 3 | 12 | FP: the name appears in edit text (3), count-only or value-masked reads (`grep -c`, `sed 's/=.*/=<set>/'`) (5), `rm` of a copy, `node --env-file`, a grep with no `.env` at all |
| task-poll (sleep loops on background tasks) | 8 | 8 | 0 | |
| git discard (`checkout --`, `restore`) | 4 | 4 | 0 | |
| `git stash drop` | 3 | 3 | 0 | |
| network upload of sensitive source | 4 | 0 | 4 | ~/.ssh path elsewhere in the chain; doc-edit text; test probe strings |
| potential credential in command | 4 | 0 | 4 | `password = ""` in test code, `export X_KEY=""`, a dummy key for a local stand-in |
| dangerous pattern (`dropdb`, `<<<…\|sh`, `ps e…\|curl`, `curl\|bash`) | 4 | 0 | 4 | `find -name dropdb`; test strings; `curl` after `;`, not in the pipe |
| commit format | 4 | 2 | 2 | 2 `wip(…)` TP; 2 well-formed messages FP, not reproducible on 4.4.4 offline |
| DNS exfiltration | 3 | 0 | 3 | words `host`/`token`/`secret` in TypeScript edit text; this audit's own search terms |
| SQL destructive (`drop database`) | 3 | 0 | 3 | all test strings in a `for q in '…'` list |
| instruction-file write | 2 | 0 | 2 | `.claude/handoff.md` (the carry file the workflow requires editing) |
| clipboard | 2 | 1 | 1 | FP: this audit's own search terms |
| `git branch -f` protected | 1 | 1 | 0 | borderline: `main` to `origin/main` |
| cron | 1 | 0 | 1 | `Crontab unchanged.` inside a `sed` replacement |
| **total** | **58** | **22** | **36** | **62% FP** |

## What it says

- **The guards that act on git and process state are exact** (task-poll, discard, stash,
  branch: 16/16). **The content scanners are not** (credential, network, DNS, SQL,
  dangerous pattern: 0/18).
- **Half the FPs (~18/36) are a trigger word inside data**: a heredoc body that edits a
  file, a quoted test string, a `sed` replacement. `sc_blank_data_into` blanks commit
  messages, but a heredoc fed to `python3 -` is executed code, so blanking it would open a
  hole. Telling "edit text in a Python string" from "Python that runs it" needs a parse, not
  a regex.
- **The sensitive-file guard treats a masked or count-only read as a read.** `grep -c` and
  `| sed 's/=.*/=…/'` cannot print a value; recognising those two forms covers 5 of its 12 FPs.
- **The `.claude/handoff.md` deny contradicts this project's own workflow** (CLAUDE.md
  requires updating it).

## Next, if wanted (each its own PR, each with the FP cases above as fixtures)

1. sensitive-file: allow `grep -c` / `-l` / `-q` and a `sed` mask of the value.
2. instruction-file: exempt `.claude/handoff*.md`.
3. credential-in-command: skip empty values (`X=""`) and assignments to `localhost`/`127.0.0.1` stand-ins.
4. The data-in-heredoc class: measure first; no cheap fix found.

Re-run: same transcript scan, after a month on 4.4.5+.
