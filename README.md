# Claude Supercharger

Shell hooks for Claude Code that block destructive commands and secret leaks before the tool call runs.

![Version](https://img.shields.io/badge/version-4.3.9-blue) [![CI](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml/badge.svg)](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml) [![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/smrafiz/b57e04622039cbdf04f2a2ed338d36e7/raw/supercharger-tests.json)](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml) ![License](https://img.shields.io/badge/license-MIT-green)

Supercharger registers bash hooks that Claude Code runs around every tool call. They block destructive shell commands (`rm -rf` on system paths, force-push to a protected branch, `curl | bash`), writes into credential and system directories, and credentials leaving through tool output, MCP arguments or a commit. These are guardrails for a capable agent that makes mistakes, not a sandbox: pattern matching can be evaded on purpose, and commands you run yourself with `!` never pass through a hook. A hook that hits an internal error allows the call, and one that runs past its timeout (15 seconds, 60 on Windows) is killed by Claude Code and the command runs. A broken guard fails open rather than blocking your work.

## What a block looks like

Claude tried to run `git push --force origin main`. The hook stopped it before it ran and printed this:

```text
Supercharger blocked this git operation.
  Reason : force push to protected branch
  Command: git push --force origin main
  Override: if this is intentional, run it in your terminal directly. Git-safety
            blocks are absolute by design ...
```

Claude itself is told `Supercharger: force push to protected branch`, so it knows this is policy rather than a shell error. A recorded run of several blocks is in [assets/demo/demo.gif](assets/demo/demo.gif); `./assets/demo/try.sh '<command>'` replays any command through the guards without executing it.

## Quickstart

You need the Claude Code CLI, Bash 3.2 or later (macOS, Linux, or Git Bash on Windows), Python 3.7 or later, and `jq`.

1. Install. The installer asks for a mode (Safe or Full) and backs up your existing config to `~/.claude/backups/` first.

   ```bash
   git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
   ```

2. Check the install, then start a new Claude Code session.

   ```bash
   bash ~/.claude/claude-check.sh
   ```

   Inside Claude Code, `/sc-doctor` runs the same kind of check and ends with one line you can paste into a bug report.

3. Optional, macOS only: install the notifier app so notifications show as "Claude Supercharger" instead of "Script Editor". It needs macOS 10.14 or later and Apple's Command Line Tools (`swift --version`; if missing, `xcode-select --install`). It is compiled on your Mac in under a minute, downloads nothing and needs no admin rights. Run `/sc-notifier install`, then turn it on once in System Settings, Notifications, Claude Supercharger.

4. To remove it later, run `./uninstall.sh` from the clone. See [Uninstall](#uninstall).

Other ways to install (temp-dir one-liner, non-interactive flags, Claude Code plugin, Windows notes) are in [docs/INSTALL.md](docs/INSTALL.md).

## What it does

- Destructive-command and path guards. Commands and file writes are checked before they run. Example: `rm -rf /`, `DROP TABLE`, `terraform destroy`, and an Edit to `~/.ssh/config` are denied. [Feature list](docs/FEATURES.md#runtime-enforcement), [every hook](docs/HOOKS.md).
- Secret and egress scanning. Tool output, staged diffs, prompts and outbound MCP or WebFetch arguments are scanned for credentials. Example: an AWS key in the staged diff blocks `git commit`, and the message says a secret was found without repeating it. [Feature list](docs/FEATURES.md#runtime-enforcement).
- Permission modes with a time limit. Example: `/sc-autopilot 2h` stops the yes/no prompts for two hours while the safety floor stays on; `/sc-readonly 20m` blocks every edit. [Commands](docs/COMMANDS.md#control-and-modes).
- Cost and token economy. Example: `"budget": 5.00` in `.supercharger.json` blocks non-read tools once a session has spent $5, and `eco lean` asks for shorter answers. [Cost features](docs/FEATURES.md#cost-and-context-control), [configuration](docs/CONFIGURATION.md).
- Memory between sessions. Example: `/sc-handoff` writes `.claude/handoff-<session>.md`, which the next session loads, and lessons from debugging are recalled on later prompts. [Memory features](docs/FEATURES.md#memory-across-sessions).
- Slash commands for review and debugging. Example: `/sc-why` explains the last block, and `/sc-multi-review` runs parallel reviewers and then tries to refute each finding. [All commands](docs/COMMANDS.md).
- Statusline and notifications. Example: the statusline shows context use, cache hit rate and session cost; a notification fires when a long turn finishes. [Developer features](docs/FEATURES.md#developer-experience).

Most per-project settings go in a `.supercharger.json` at the repo root. Commit it and everyone on the project gets the same behaviour:

```json
{
  "economy": "lean",
  "budget": 5.00
}
```

Every key and env var is listed in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Limits and trade-offs

### What it does not protect against

- A targeted attacker who controls your prompts. Matching is best effort; someone trying to evade it can. Run untrusted work in a container or VM.
- Commands typed with Claude Code's `!` prefix and anything you run in your own terminal. Those never reach a hook.
- Anything after the fact. Hooks that run after a tool call can warn, but cannot undo it.
- Hangs. A guard that exceeds its timeout is killed and the command runs.
- Documented open gaps, listed in [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md).

The full threat model, failure table and block-ledger details are in [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md).

### Cost per tool call

Claude Code runs a tool call's hooks concurrently. On an M4 Pro with bash 3.2, the 19 PreToolUse hooks for a Bash call add about 6.8 ms when the command takes the fast path, and 23.4 ms when `safety.sh` runs its full scan. On a GitHub ubuntu runner the fast path measured 10.0 ms. Run `/sc-perf` to see timings from your own sessions; on bash 3.2 its averages read high, so read [docs/PERFORMANCE.md](docs/PERFORMANCE.md) before acting on them. From a clone, `bash tests/perf-chain.sh` reproduces the numbers above.

### False positives and ways through

Every block is logged to `~/.claude/supercharger/scope/.blocked-commands`, and `/sc-why` explains the most recent one. If a block is wrong, take the narrowest way through:

1. Run that one command yourself in your terminal.
2. Exempt that command shape for the project with `allowPatterns` in `.supercharger.json`. It cannot exempt self-modification, git-safety, path-guard or harness-tamper-guard blocks. [How](docs/CONFIGURATION.md#exempt-one-command).
3. Turn off one guard with its env var, for example `SUPERCHARGER_PATH_GUARD=0 claude`. [Env var table](docs/CONFIGURATION.md#turn-off-one-feature).
4. Turn off a category of rules for the project with `disableSecurityCategories`. [Categories](docs/CONFIGURATION.md#security-categories).
5. `/sc off` turns every guard off until `/sc on`.

Destructive git operations (force-push to a protected branch, `reset --hard`) have no project-level opt-out. Run those in your terminal.

## Where to go next

| I want to... | Read |
|---|---|
| Install as a plugin, on Windows, or without keeping the clone | [docs/INSTALL.md](docs/INSTALL.md) |
| See everything it does | [docs/FEATURES.md](docs/FEATURES.md) |
| Look up a hook by name | [docs/HOOKS.md](docs/HOOKS.md) |
| Configure a project or turn something off | [docs/CONFIGURATION.md](docs/CONFIGURATION.md) |
| Find a slash command or bundled tool | [docs/COMMANDS.md](docs/COMMANDS.md) |
| Understand the threat model and failure behaviour | [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) |
| Measure or reduce overhead | [docs/PERFORMANCE.md](docs/PERFORMANCE.md) |
| See before/after examples | [docs/examples.md](docs/examples.md) |
| Write my own hook | [docs/HOOK_AUTHORING.md](docs/HOOK_AUTHORING.md) |
| Get an answer to a common question | [docs/FAQ.md](docs/FAQ.md) |
| See what changed | [CHANGELOG.md](CHANGELOG.md) |

## Uninstall

If you only want a break, `/sc off` switches back to stock Claude Code without removing anything, and `/sc on` brings it back.

To remove it, run this from a clone of the repo (clone it again if you installed from a temp dir):

```bash
./uninstall.sh
```

It asks before doing anything, then offers to restore the newest backup from `~/.claude/backups/`. It removes:

- Supercharger's hook entries, statusline, `attribution` override and `ENABLE_PROMPT_CACHING_1H` from `~/.claude/settings.json`
- the MCP servers it tagged `#supercharger` in `~/.claude.json`
- the managed block at the end of `~/.claude/CLAUDE.md`, and its rule files in `~/.claude/rules/`
- `~/.claude/supercharger/`, which holds the hooks, tools, block ledger and session state
- the agents and commands it installed in `~/.claude/agents/` and `~/.claude/commands/`, by name; other files there are left alone
- `~/.claude/claude-check.sh`, and `~/Applications/Claude Supercharger.app` if its bundle id is ours

It keeps `~/.claude/backups/` and anything inside your projects, such as `.supercharger.json` and handoff briefs. If you restore the backup, your pre-install `CLAUDE.md`, `rules/`, `shared/` and `settings.json` come back.

On the plugin channel, `/plugin disable` stops it, and `tools/plugin-setup.sh --revert` undoes the settings it wrote.

## Why this exists

Rules in `CLAUDE.md` are text the model reads and can decide to set aside. A hook is a separate process with an exit code: Claude does not see it and cannot argue with it, and it costs no context tokens. We built Supercharger to put the rules we cared about most where the model cannot reach them, then added the cost, memory and workflow pieces we wanted in daily use. [docs/SECURITY-MODEL.md](docs/SECURITY-MODEL.md) compares the two approaches.

Status: actively maintained. Every release is listed in [CHANGELOG.md](CHANGELOG.md) (older entries in [docs/CHANGELOG-archive.md](docs/CHANGELOG-archive.md)), and planned work is in [docs/ROADMAP.md](docs/ROADMAP.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and false positives are welcome as [issues](https://github.com/smrafiz/claude-supercharger/issues).

Supercharger builds on patterns from other Claude Code and guardrail projects; they are credited in [docs/CREDITS.md](docs/CREDITS.md) and [NOTICE](NOTICE).

## License

MIT. See [LICENSE](LICENSE).
