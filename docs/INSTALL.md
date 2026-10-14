# Installing Claude Supercharger

[Back to README](../README.md)

## Requirements

- Claude Code CLI
- Bash 3.2 or later (macOS, Linux, or Git Bash on Windows)
- Python 3.7 or later
- `jq`

## Install from a clone

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

If you do not want the repo left on disk, this clones to a temp dir, installs, and deletes the clone:

```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

It takes about 30 seconds. Your existing config is backed up first to `~/.claude/backups/`, and `./uninstall.sh` offers to restore it.

To read the installer before running it, use the first command without `&& ./install.sh`, then open `install.sh` and `lib/` in the clone.

Then check the install:

```bash
bash ~/.claude/claude-check.sh
```

Inside Claude Code, `/sc-doctor` runs a similar check (registration, deployed-code integrity, state permissions, update status) and ends with one line you can paste when asking for help.

## Install modes

| Mode | What it installs | Use when |
|--|--|--|
| Safe | Security blocks, smart auto-approve and the audit trail | You want the smallest footprint |
| Full | Everything: cost tracking, memory, the learning loop, statusline, confidence gate | Recommended |

```bash
./install.sh                                    # interactive
./install.sh --mode full --roles developer      # non-interactive (CI or scripts)
```

The exact hook list for each mode is in [HOOKS.md](HOOKS.md), generated from the hook headers by `bash tools/list-hooks.sh`.

## What install writes

Install copies hooks, agents, commands and rules into `~/.claude/`, registers the hooks in `~/.claude/settings.json`, and appends a managed block to `~/.claude/CLAUDE.md`. It also sets two `settings.json` keys: `env.ENABLE_PROMPT_CACHING_1H=1` and an `attribution` override. `./uninstall.sh` reverses all of it. See [Uninstall](../README.md#uninstall) for the exact list.

## Upgrading

```bash
bash ~/.claude/supercharger/tools/update.sh
```

`/sc-update` does the same from inside Claude Code.

Upgrading from 4.2 or earlier: every command is now `/sc-<name>` (`/security` became `/sc-security`, `/pr` became `/sc-pr`). `/sc` and `/supercharger` did not change. For one release the old names still work and point you to the new one. Only unmodified copies are replaced. A command you edited, or one that is not ours, is never touched.

## macOS notifier app (optional)

By default macOS shows Supercharger's notifications as coming from "Script Editor". The optional notifier app shows them as "Claude Supercharger", and clicking one returns you to your terminal or editor.

It needs macOS 10.14 or later and Apple's Command Line Tools (for Swift; full Xcode is not required). It needs no admin rights and downloads nothing: it is compiled from source on your Mac in under a minute.

1. Make sure Swift works: `swift --version`. If it is missing, run `xcode-select --install`.
2. Say yes when install asks, or run `/sc-notifier install` any time. It builds `~/Applications/Claude Supercharger.app` on your Mac.
3. Turn it on once in System Settings, Notifications, Claude Supercharger. New apps start switched off.

Updates never install it unless you said yes. Check it with `/sc-notifier status` and remove it with `/sc-notifier remove`. Set `SUPERCHARGER_NO_NOTIFIER=1` at install to never build or update it.

If the build fails with `redefinition of module 'SwiftBridging'`, see the [FAQ](FAQ.md#sc-notifier-fails-with-redefinition-of-module-swiftbridging).

## Install as a plugin

Supercharger also ships the full framework through Claude Code's native plugin system, with no install script to run:

```
/plugin marketplace add smrafiz/claude-supercharger
/plugin install supercharger@claude-supercharger
```

When you enable it you are asked for a role, an economy tier and an MCP profile. Update with `/plugin update` and toggle with `/plugin enable|disable`.

On Windows the plugin still needs Git Bash. There is no install script to run, but every hook is a bash script. Claude Code picks Git Bash as its hook interpreter when it is installed and falls back to PowerShell when it is not, and under PowerShell none of these hooks run. The classic installer cannot hit this because it needs bash to run at all. The plugin can, because nothing in its install path requires bash. Install Git for Windows first.

Every guard runs the same way on both channels. The packaging differs:

- Slash commands are namespaced: `/sc-audit` becomes `/supercharger:audit`.
- `/sc-update` becomes `/plugin update`, and `/sc on|off` becomes `/plugin enable|disable`. Those two commands are not shipped in the plugin.
- The guardrail rules arrive as SessionStart context instead of a `CLAUDE.md` block. The rules are the same, and uninstalling leaves nothing behind.
- The statusline, the 1h prompt cache and attribution need three `settings.json` keys that a plugin cannot declare (its manifest supports only `agent` and `subagentStatusLine`). Answer yes to "Write statusline + prompt-cache settings" when enabling and they are written on first run. They are backed up first, an existing statusline is never overwritten, and `tools/plugin-setup.sh --revert` undoes it. Answer no to keep the plugin inside its own directory; you can run that script yourself later.
- MCP profile filtering does not apply. The plugin ships its MCP servers through the manifest, so Claude Code's per-server approval decides which load. The `light`/`dev`/`research`/`full` profiles only work when Supercharger writes `~/.claude.json` itself.
- Hooks keep the portable `#!/usr/bin/env bash` shebang, so each one is about 1.8 ms slower per run than in a classic install, which rewrites them to an absolute interpreter path.

Pick one channel. Do not run `install.sh` and the plugin at the same time: hooks would fire twice and state would split across two directories. The plugin's setup detects a classic install and stands down rather than repointing your working statusline.

## Windows and other platforms

See the [Windows FAQ entry](FAQ.md#windows). Alpine Linux is not supported because it ships `ash`, not `bash`. Run inside a Debian, Ubuntu or Fedora container, or install GNU bash first.
