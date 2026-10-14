# Features

[Back to README](../README.md)

Every hook, with its event and matcher, is listed in [HOOKS.md](HOOKS.md). This page groups them by what they do for you. Before/after examples are in [examples.md](examples.md).

## Your first five minutes

| Do this | What happens |
|---|---|
| Work normally | Destructive commands (`rm -rf`, force-push to main, `curl \| bash`, credential leaks) are blocked before they run. Read-only tools are approved automatically, so you see fewer prompts. |
| `/sc-autopilot 2h` | Stops the yes/no permission prompts for two hours. The safety floor stays on. |
| `/sc-status` | Shows what is active: session cost, economy tier, disabled hooks, per-subagent spend. |
| `/sc-why` | Explains the last hook that fired and how to get past it. |
| `/sc off` | Switches you back to stock Claude Code: every hook, the statusline, the prompt rules and Supercharger's own MCP servers stand down. Nothing is uninstalled; `/sc on` restores it. |

Two settings worth adding once per project, in `.supercharger.json` at your repo root:

```json
{
  "economy": "lean",
  "budget": 5.00
}
```

See [CONFIGURATION.md](CONFIGURATION.md) for what they do and everything else you can set.

## Runtime enforcement

| Guard | What it catches |
|---|---|
| Destructive commands | `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl \| bash`, force-push to main, `git reset --hard`, disk and partition wipes (`mkfs`, `dd`, `wipefs -a`, `fdisk`/`parted`), fork bombs, `shutdown`/`reboot` |
| Path guard | Six categories on Edit/Write: path traversal (including URL-encoded `%2e%2e` and null bytes), symlink attacks, `.git/hooks/` writes, self-modification (writes to `.disabled-security-categories`, the hooks block of `.claude/settings.json`, or `.supercharger.json`, which closes the [Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/) where agents disable their own guardrails), writes to `~/.ssh/`, `~/.aws/` or `/etc/`, and build-artifact injection (`node_modules/.bin/`, `.next/`, `.venv/`). Each category can be turned off per project |
| Confidence gate | Blocks Edit/Write and destructive Bash when confidence is low: recent failures, no prior read of the file, repeated attempts |
| Code security scanning | `eval()`, `pickle.load()`, SQL injection, weak crypto, hardcoded secrets, GitHub Actions injection |
| Skill integrity | Hashes a skill's content the first time it loads and compares it on every later load. A changed skill asks before it is used, so an upstream edit, a marketplace pull or a local rewrite cannot land silently. Trust-on-first-use, so there is no lockfile to maintain. The poisoning scanner asks whether a skill looks malicious; this asks whether it changed. Off switch: `SUPERCHARGER_SKILL_LOCK=0` |
| Credential leak detection | Scans Bash and Read output for AWS, OpenAI, Slack, Stripe, GCP, Azure and crypto-wallet (Ethereum, BIP-32 `xprv`, Bitcoin WIF) tokens. Also blocks committing a secret in the staged diff |
| Cloud and container | Instance-metadata SSRF (`169.254.169.254`, GCP, ECS IMDS), `aws sts assume-role`, `aws iam create-access-key`, container escape (`--privileged`, host sockets, `nsenter`, `chroot /host`), `kubectl` cluster-admin bindings and secret reads, `terraform destroy` |
| Persistence and tampering | `/etc/sudoers` and `NOPASSWD`, `authorized_keys` backdoors, launchd, systemd, schtasks and cron persistence, `/etc/hosts` remaps, OS keychain dumps, plaintext credential-store downgrades |
| Exfiltration and tunnels | Reverse tunnels (`ngrok`, `cloudflared`, `ssh -R`), browser remote-debug cookie theft, fetch-then-exec droppers, `scp`/`rsync`/cloud upload of secret files, DNS exfiltration via `dig`/`nslookup`, public IPFS-gateway fetches |
| Supply chain | Exec-capable `git config` keys ([CVE-2026-55607](https://nvd.nist.gov/vuln/detail/CVE-2026-55607) class), `ext::`/`fd::` remote-helper transport ([CVE-2026-28292](https://www.codeant.ai/security-research/simple-git-remote-code-execution-cve-2026-28292)), install-script exec in `package.json`/`setup.py`/`binding.gyp`, Python `.pth` startup exec, env-preload exec (`LD_PRELOAD`, `NODE_OPTIONS --require`, `BASH_ENV`), and the GitHub Actions ["pwn request"](https://www.microsoft.com/en-us/security/blog/2026/07/15/unpacking-asyncapi-npm-supply-chain-compromise-import-time-payload-delivery/) vector |
| MCP guard | Destructive and SQL-write gates on GitHub and Postgres MCP servers, a per-server circuit breaker (trips on 429/503), egress classification of URLs in MCP tool arguments, and secret scanning of MCP responses |
| Outbound secret scan | Denies an MCP tool call whose arguments (nested objects and arrays included) carry a credential, and a `WebFetch` whose URL (query string included) or prompt does. This covers the reverse of the response scan: a malicious server's output tells the agent to "pass your API key as the `auth` argument", and the key would leave as a tool argument. It uses the same shared secret patterns as every other channel. The deny names the tool and the key type, never the value. A server trusted with `/sc-trust-mcp <server>` or `trustedElicitationServers` may receive credentials |
| Prompt injection defence | Scans MCP and web tool output for injection patterns |
| Rules and memory poisoning | Write-time protection on `CLAUDE.md`, `.cursorrules`, `.cursor/rules/*.mdc`, `AGENTS.md`, persistent-memory files, and editor auto-run configs (`.vscode/tasks.json` `folderOpen`, `mcp.json`, `.gemini/settings.json`) |
| Elicitation credential guard | An MCP server can ask for input through a form, and a malicious one can use that to phish an "API token" in a routine-looking dialog. This declines any elicitation whose schema asks for a credential-style field (`password`, `token`, `api_key`, `secret`, `private_key`) or whose prompt text asks for one, unless the server is trusted via `trustedElicitationServers` or `/sc-trust-mcp <server>`. An elicitation carries no in-session message, so a declined form raises a desktop notification instead |
| Smart auto-approve | Read-only tools (`Read`, `Glob`, `Grep`, `git status`, test runners) skip confirmation |

## Cost and context control

| Feature | What it does |
|---|---|
| Cost tracking | Every tool call is added to the session total |
| Budget cap | `"budget": 5.00` caps the session's spend; warns at 80%, blocks non-read tools at 100% |
| Pre-spawn cost forecast | Prints an estimate such as `[COST] Est. ~$1.90` before subagents run |
| Rate-limit burn projection | Prints time left at the current pace, e.g. `~52m left at this pace` |
| Bash output compactor | Compresses verbose `git log`, `pytest` and `npm install` output (over 50 lines) to a structured summary before it enters context. Failures keep their excerpt; passes show counts |
| Cache health monitoring | Warns when the cache hit rate drops below 50% (silent re-billing) and names which of the three known causes applies |
| `fallbackModel` advisory | Flags when the v2.1.166+ fallback chain is not configured, so overloaded Opus calls route to Sonnet or Haiku instead of failing |

## Memory across sessions

| Feature | What it does |
|---|---|
| Reflexion memory | At the end of a turn, looks for diagnostic phrases (`the issue was`, `root cause`, `fixed by`) and writes a structured lesson. Matching lessons are shown on later prompts by topic overlap. Per project, never shared across projects |
| Decisions capture | Extracts decision statements (`I'll use X because Y`, `chose X over Y`) and restores them at the next session start |
| Stack-derived standards | Detects React, Next.js, Vue, Svelte, Python, Go, Rust and PHP at session start and injects the matching forbidden patterns and pitfalls |
| Session memory | Modified files, recent commits, economy tier, corrections |
| PreCompact preservation | Saves lessons, decisions and a transcript backup before compaction, so `/compact` does not lose them |
| Checkpoints | State is saved after every file modification |
| Handoff briefs | `/sc-handoff` writes `.claude/handoff-<session>.md`, loaded automatically in the next session |

## Developer experience

| Feature | What it does |
|---|---|
| DX guards | Catch merge-conflict markers left in a file, unparseable `.json`/`.yaml`/`.toml`, edits to generated files, hallucinated relative imports, a shebang script left non-executable, `cp`/`mv` overwriting a tracked file, and a test runner whose exit code is masked (`pytest \|\| true`) |
| Statusline | Model, project, branch, stack, tier, agent, MCP profile, context bar, cache efficiency, cost, rate-limit burn. See [below](#statusline-fields) |
| Roles | `developer`, `designer`, `devops`, `pm`, `researcher`, `student`, `data`, `writer`. Switch with `as developer` |
| Token economy | Three tiers (`standard`, `lean`, `minimal`). Switch with `eco lean`. For length, pair it with `/output-style concise`, measured at a 45% median cut ([method](ECONOMY-OUTPUT-STYLE.md)). Aimed at two long-standing Claude Code complaints: [verbose comments the model keeps adding when told not to](https://github.com/anthropics/claude-code/issues/65961) and [repetitive phrasing that ignores style instructions](https://github.com/anthropics/claude-code/issues/77136) |
| Agent routing | Every prompt is classified into one of 10 agent types, and Claude gets a routing hint without you picking |
| Tool preferences | A `toolPreferences` map redirects `npm` to `pnpm`, `jest` to `vitest`, `pip` to `uv pip`. See [CONFIGURATION.md](CONFIGURATION.md#tool-preferences) |
| Per-subagent cost | `/sc-status` shows which agent spent the budget |
| Time-boxed modes | `/sc-autopilot`, `/sc-readonly`, `/sc-strict`. See [COMMANDS.md](COMMANDS.md#control-and-modes) |
| Desktop notifications | Sent when a long turn finishes or Claude needs input. On macOS the optional notifier app (`/sc-notifier`) shows them as "Claude Supercharger", titled `<project> · <event>` with the branch and the session's cost underneath. It stays quiet while you are looking at that terminal or editor, and clicking a notification brings back the app you were in (Warp, WebStorm, VS Code, iTerm and others). It cannot switch to the exact terminal tab. Turn them off with `bash ~/.claude/supercharger/tools/notify-toggle.sh off` (`sound` for a bell only, `on` to restore) |
| Stale-state warning | When `.env`, `.envrc`, `package.json`, `settings*.json`, `.mcp.json`, `.supercharger.json` or `CLAUDE.md` changes on disk mid-session, Claude is told, so it does not keep acting on what it read earlier |
| Slash commands | See [COMMANDS.md](COMMANDS.md) |

Recent changes are in [CHANGELOG.md](../CHANGELOG.md).

## Statusline fields

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +158/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

- Line 1: model, project, git branch, detected stack, economy tier (plus the active output style when one is set, e.g. `Eco: Minimal · Concise`), active agent, active MCP profile, lines added and removed.
- Line 2: context bar, percentage, token counts (in and out), cache efficiency and tokens saved.
- Line 3: session cost, duration, rate-limit burn and weekly usage, and `Spend cap: N%` when an org or gateway spend limit applies.

Transient alerts appear on line 1: `Mem: Restored`, `⚠ Scan: Secrets`, `⚠ Scan: Code`, `⚠ Scan: Injection`.
