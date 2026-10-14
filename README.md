# Claude Supercharger

**Claude Code is quick and very sure of itself. Supercharger is the part that says no.**

![Version](https://img.shields.io/badge/version-4.3.9-blue) [![CI](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml/badge.svg)](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml) [![Tests](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/smrafiz/b57e04622039cbdf04f2a2ed338d36e7/raw/supercharger-tests.json)](https://github.com/smrafiz/claude-supercharger/actions/workflows/ci.yml) ![License](https://img.shields.io/badge/license-MIT-green)

![Supercharger hooks denying destructive commands before they run](assets/demo/demo.gif)

You give an agent a shell and it will, one day, run something you would never have typed. A path variable comes back empty and `rm -rf "$DIR"/` points at the wrong place. A "quick fix" ends in `git push --force` on main. It reads `.env` to "check the config" and now your keys are in the transcript.

Supercharger is a set of hooks that Claude Code runs before and after every tool call. They live in your shell, not in the prompt, so Claude cannot talk its way past them and they cost zero context tokens. Install it once and keep working the way you already do.

## What it catches

| Claude tries to | What happens |
|---|---|
| `rm -rf ~/` | Blocked before it runs |
| `rm -rf "$DIR"/` with a variable it has not checked | Stops and asks you first |
| `git push --force origin main` | Blocked, and Claude is told why |
| `cat .env` to "see the settings" | Blocked |
| `curl -fsSL https://... \| bash` from a README it just read | Blocked |
| Edit `~/.ssh/config` | Blocked |
| Commit a file with a live API key in it | Commit blocked; the key is never echoed back |
| Send a credential out as an MCP tool argument or a WebFetch URL | Blocked |
| Keep going after the session passed the budget you set | Non-read tools stop at the limit |

When something is blocked, Claude sees a plain reason instead of a mystery shell error, so it changes course instead of retrying the same thing:

```text
Supercharger blocked this git operation.
  Reason : force push to protected branch
  Command: git push --force origin main
  Override: if this is intentional, run it in your terminal directly. Git-safety
            blocks are absolute by design ...
```

Want to see how a command would be judged without running it? `./assets/demo/try.sh '<command>'` replays it through the guards.

## Install

You need the Claude Code CLI, Bash 3.2 or later (macOS, Linux, or Git Bash on Windows), Python 3.7 or later, and `jq`.

1. Clone and run the installer. It asks which mode you want (Safe or Full) and backs up your current config to `~/.claude/backups/` before touching anything.

   ```bash
   git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
   ```

   Rather not keep the repo lying around? This clones into a temp dir, installs, and cleans up after itself:

   ```bash
   bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
   ```

2. Check that it took, then open a new Claude Code session.

   ```bash
   bash ~/.claude/claude-check.sh
   ```

   Inside Claude Code, `/sc-doctor` does the same and gives you one line to paste into a bug report.

3. Optional, macOS only: the Supercharger app. Out of the box, macOS shows our notifications as coming from "Script Editor". Run `/sc-notifier install` and they arrive as "Claude Supercharger" instead, and clicking one takes you back to your terminal or editor. It needs macOS 10.14 or later and Apple's Command Line Tools (`swift --version`; if that fails, `xcode-select --install`). It is built from source on your Mac in under a minute: no download, no admin rights. Then switch it on once in System Settings, Notifications, Claude Supercharger.

4. Changed your mind? `./uninstall.sh` from the clone. Details in [Uninstall](#uninstall).

Other ways in (non-interactive flags, the Claude Code plugin, Windows notes) are in [docs/INSTALL.md](docs/INSTALL.md).

## What else is in the box

The guards are the reason it exists. The rest is what we wanted every day once they were in place.

- Secret scanning on the way out. Tool output, staged diffs, prompts, MCP arguments and WebFetch URLs are scanned for credentials. If a key shows up in output, Claude is told which tool printed it and asked not to repeat it. [More](docs/FEATURES.md#runtime-enforcement)
- Prompts you can switch off for a while. `/sc-autopilot 2h` stops the yes/no questions for two hours and the guards stay on. `/sc-readonly 20m` blocks every edit while you poke around. [Commands](docs/COMMANDS.md#control-and-modes)
- A spending limit. Put `"budget": 5.00` in `.supercharger.json` and non-read tools stop once the session has spent $5. Say `eco lean` mid-chat for shorter answers. [Cost features](docs/FEATURES.md#cost-and-context-control)
- Memory between sessions. `/sc-handoff` writes a brief that the next session picks up on its own, so you do not start every morning by explaining yesterday. [Memory](docs/FEATURES.md#memory-across-sessions)
- Commands for the annoying parts. `/sc-why` explains the last block in plain words. `/sc-multi-review` sends parallel reviewers at a diff, then tries to knock down each finding before showing it to you. [All commands](#commands)
- A statusline that tells you things. Context used, cache hit rate and what the session has cost so far, plus a notification when a long turn finishes. [Details](#the-statusline)

Per-project settings live in a `.supercharger.json` at the repo root. Commit it and everyone on the project gets the same rules:

```json
{
  "economy": "lean",
  "budget": 5.00
}
```

Every key and env var is in [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## The statusline

Three lines at the bottom of Claude Code, so you always know where the session stands:

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +158/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

- Line 1 is where you are: model, project, git branch, detected stack, economy tier, active agent, MCP profile, and lines added and removed.
- Line 2 is how full the context window is, tokens in and out, and how much the prompt cache is saving you.
- Line 3 is what it costs: session spend, time, rate-limit burn and weekly usage. `Spend cap: N%` shows up when an org or gateway limit applies.

When something needs your eye, a short alert appears on line 1: `Mem: Restored`, `⚠ Scan: Secrets`, `⚠ Scan: Code` or `⚠ Scan: Injection`.

## Commands

Type `/supercharger` in Claude Code to list them all. The ones you will reach for most:

| Command | What it does |
|---|---|
| `/sc-why` | Explains the last block: what fired, why, and how to get past it |
| `/sc-status` | What is on right now: cost, economy tier, disabled hooks |
| `/sc-autopilot 2h` | No permission prompts for two hours; the guards stay on |
| `/sc-readonly 20m` | Look around without any edits |
| `/sc-handoff` | Write a brief the next session loads by itself |
| `/sc-multi-review` | Parallel reviewers on a diff, then a pass that tries to disprove each finding |
| `/sc-stuck` | Fresh hypotheses when a bug has you going in circles |
| `/sc off` | Back to stock Claude Code until `/sc on`; nothing is uninstalled |

Commands that change state or settings (`/sc`, the time-boxed modes, `/sc-update`, `/sc-pr`, `/sc-cleanup`) only run when you type them. Claude cannot start them on its own.

<details>
<summary>All commands</summary>

#### Control and modes

| Command | Purpose |
|--|--|
| `/sc-autopilot 2h` | Stop the yes/no permission prompts for a set time. The safety floor stays on |
| `/sc-readonly 20m` | Block all edits and mutating shell commands; allow reads, searches and planning |
| `/sc-strict 30m` | Confirm every call. Auto-approves nothing and overrides autopilot while active |
| `/sc off\|on\|status` | Switch to plain Claude Code and back. Guards, statusline, prompt rules and Supercharger's MCP servers all stand down; nothing is uninstalled |
| `/sc-status` | What is active now: session cost, economy tier, disabled hooks, per-subagent spend |
| `/sc-profile [fast\|minimal]` | Show or switch the performance profile (skips analytics hooks to cut overhead) |
| `/sc-update` | Check for and apply Supercharger updates (classic install; the plugin uses `/plugin update`) |
| `/sc-mcp-audit [--accept] [--server NAME]` | Scan every MCP server's tool descriptions for hidden instructions (tool poisoning) and report tools whose description changed since you accepted it (rug pull). Hooks never see descriptions, so this is the only check on them |
| `/sc-notifier [install\|status\|remove]` | macOS: install, check or remove the optional notifier app |
| `/sc-doctor` | Diagnose the install: registration, deployed-code integrity, state permissions, update status. Ends with one line to paste when asking for help |

The time-boxed modes expire on their own. They are per session by default (`global` is opt-in), capped at 2h, shown in the statusline, and need no daemon. When two modes conflict, the tighter one wins: `/sc-readonly` and `/sc-strict` override `/sc-autopilot`. Autopilot only removes approval prompts; `rm -rf`, force-push and credential leaks are still blocked.

#### Workflow

| Command | Purpose |
|--|--|
| `/sc-handoff [--deep] [context]` | Write a session resume brief to `.claude/handoff-<session>.md`, loaded automatically next session |
| `/sc-pr [description]` | Prepare and create a pull request |
| `/sc-scope [task]` | Pre-flight check: files to touch, risks, blast radius |
| `/sc-estimate [task]` | Time and complexity report. Stops before any code is written |
| `/sc-interview [topic]` | Structured requirements gathering, one question at a time |
| `/sc-multi-review [quick\|standard\|deep] [target]` | Parallel specialist reviewers, then a separate pass that tries to refute each finding |
| `/sc-security [scope]` | OWASP-anchored review with severity-ranked findings |
| `/sc-audit [scope]` | Consistency sweep across naming, patterns, docs and interfaces |
| `/sc-cleanup [scope]` | Dead code and unused-import removal with two-tier safety |
| `/sc-resolve-conflicts [context]` | Resolve an in-progress merge or rebase conflict, then verify it with the typecheck and tests |

#### Reasoning and debugging

| Command | Purpose |
|--|--|
| `/sc-think [problem]` | Structured reasoning for ambiguous problems |
| `/sc-challenge [decision]` | Adversarial stress-test: assumptions, failure modes, strongest alternative |
| `/sc-stuck [symptom]` | Break a debugging loop with fresh hypotheses |
| `/sc-why [hook]` | Explain the most recent hook firing: what triggered, what was blocked, how to get past it |

#### Insight, memory and housekeeping

| Command | Purpose |
|--|--|
| `/sc-learn <rule>` | Record an explicit project rule. Shown on every prompt in this project |
| `/sc-memory-prune` | Archive resolved memory entries so they stop loading into context |
| `/sc-perf [--slow]` | Hook timing report (see [PERFORMANCE.md](docs/PERFORMANCE.md) for its bash 3.2 caveat) |
| `/sc-cache-stats`, `/sc-cache-clear` | Typecheck and quality-gate cache state, or clear the hash caches |
| `/sc-trust-mcp <server>` | Trust an MCP server to request credential-style fields (elicitation) and to receive credentials as tool arguments |
| `/sc-reflect` | Evidence-based retrospective; keeps only grounded, checkable lessons in `.claude/session-observations.md` |
| `/sc-devlog [entry]` | Append a decision to `DEV-LOG.md` |
| `/sc-design [brand]` | Generate `DESIGN.md`: tokens read from the project's theme, typography, components |
| `/sc-design-review [pages]` | Review UI: WCAG 2.2 AA with measured values, hierarchy, responsiveness (read-only) |
| `/supercharger` | List all slash commands |

</details>

The bundled scripts (`update.sh`, `hook-toggle.sh`, `token-report.sh` and others) are listed in [docs/COMMANDS.md](docs/COMMANDS.md#bundled-tools).

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
