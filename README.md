# Claude Supercharger

Safety hooks for Claude Code that run **outside Claude's process** — before commands execute, invisible to the model. Zero context-window cost: the rules live in your shell, not in your prompt.

![Version](https://img.shields.io/badge/version-2.29.14-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-3844%20passing-brightgreen)

![Supercharger hooks denying destructive commands before they run](assets/demo/demo.gif)

---

## Install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Don't want the repo lying around? This clones to a temp dir, installs, and cleans up:

```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

Takes about 30 seconds. Your existing config is backed up first, and `./uninstall.sh` restores it exactly.

Prefer Claude Code's native plugin system? See [Install as a plugin](#install-as-a-plugin).

**Requirements:** Claude Code CLI · Bash 3.2+ (macOS, Linux, or Git Bash on Windows) · Python 3.6+ · `jq`

---

## Your first five minutes

Everything else is optional. These five are what you'll actually use day to day.

| Do this | What happens |
|---|---|
| Just work normally | Destructive commands (`rm -rf`, force-push to main, `curl \| bash`, credential leaks) are blocked before they run. Read-only tools auto-approve, so you're prompted less, not more. |
| **`/sc-autopilot 2h`** | Stops the yes/no permission prompts for two hours. The safety floor stays on. This is the single biggest speed win. |
| **`/sc-status`** | What's active right now — session cost, economy tier, disabled hooks, per-subagent spend. |
| **`/why`** | Something got blocked and you don't know why? This explains the last hook firing and how to get past it. |
| **`/sc off`** | Flips you back to plain, stock Claude Code — every hook, the statusline, the prompt rules, and Supercharger's own MCP servers all stand down. Nothing is uninstalled; `/sc on` restores it. |

Two things worth setting once, per project, in a `.supercharger.json` at your repo root:

```json
{
  "economy": "lean",
  "budget": 5.00
}
```

`economy: lean` cuts response length ~45% with no information loss. `budget` caps what a single session can spend. Commit the file and your whole team gets the same behavior. [Full config reference →](#configure)

---

## Why hooks instead of prompt rules

Prompts are suggestions, and Claude is good at finding reasons to ignore suggestions.

Every Claude Code user has a version of the same story: you ask to fix a typo and Claude rewrites the component. You ask a quick question and get an essay. You come back to find files overwritten, commands run, work undone — with no warning.

The fix isn't better prompts. It's moving enforcement somewhere the model can't reach.

```
You ──▶ Claude ──▶ Tool call ──▶ [Hook] ──▶ exit 0 or exit 2
                                    │
                                    └── Runs outside Claude's view
```

Supercharger has two layers, and they come with different guarantees:

- **Shell hooks run outside Claude's process, before commands execute.** Claude can't see them, can't reason about them, and can't be talked into skipping them. Exit code 2 means the command doesn't run.
- **Prompt rules in `CLAUDE.md` shape behavior** — roles, economy tier, agent routing. Claude follows these reliably, but not unconditionally.

|  | Prompt-only frameworks (`CLAUDE.md` rules) | `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|---|---|
| Claude sees the rules | Yes | Yes | No |
| Can be argued with | Yes | Yes | No — exit code 2 is not a negotiation |
| Advisory or enforced | Advisory | Advisory | Enforced |
| **Cost in context tokens** | **~5–20K per session** | a few hundred | **0** |

That last row is the part people underestimate. Rules written as prompt text are re-read every session and shrink the window available for actual work. Supercharger's enforcement lives in the shell, so it costs nothing.

### What this does and doesn't guarantee

Worth being precise, because the distinction matters:

- **The mechanism is not bypassable by the model.** A hook is a separate process. Claude cannot see it, disable it, or argue with its exit code. This is a hard guarantee.
- **The patterns are best-effort.** The guards match commands and file writes against known-dangerous shapes. `cmd-normalize.sh` unwraps common obfuscation, but string matching has limits — a determined adversary with shell access can construct evasions.

The threat model this is built for is a capable agent making mistakes, plus opportunistic prompt-injection from tool output. It raises the cost of both a great deal. It is not a sandbox, and it is not a defense against a targeted attacker who already controls your prompts. For that, layer real OS-level isolation underneath.

---

## What you get

### Runtime enforcement

- **Destructive command blocking** — `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl | bash`, force-push to main, `git reset --hard`, disk/partition wipe (`mkfs`, `dd`, `wipefs -a`, `fdisk`/`parted`), fork bombs, `shutdown`/`reboot`
- **Path guard** — 6 attack categories on Edit/Write: path traversal (incl. URL-encoded `%2e%2e`, null bytes), symlink attacks, `.git/hooks/` writes, **self-modification** (writes to `.disabled-security-categories`, the `.claude/settings.json` hooks block, or `.supercharger.json` — closing the [Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/) where agents disable their own guardrails), writes to `~/.ssh/` / `~/.aws/` / `/etc/`, and build-artifact injection (`node_modules/.bin/`, `.next/`, `.venv/`). Each category is opt-out per project
- **Confidence gate** — blocks Edit/Write/destructive Bash when confidence is low (recent failures, no prior read, repeated attempts)
- **Code security scanning** — `eval()`, `pickle.load()`, SQL injection, weak crypto, hardcoded secrets, GitHub Actions injection
- **Credential leak detection** — scans Bash and Read output for AWS, OpenAI, Slack, Stripe, GCP, Azure, and crypto-wallet (Ethereum / BIP-32 `xprv` / Bitcoin WIF) tokens before Claude can echo them; also blocks committing a secret in the staged diff
- **Cloud & container guard** — instance-metadata SSRF (`169.254.169.254` / GCP / ECS IMDS), `aws sts assume-role`, `aws iam create-access-key`, container escape (`--privileged`, host sockets, `nsenter`, `chroot /host`), `kubectl` cluster-admin bindings and secret reads, `terraform destroy`
- **Persistence & tamper guard** — `/etc/sudoers` / `NOPASSWD`, `authorized_keys` backdoors, launchd / systemd / schtasks / cron persistence, `/etc/hosts` remaps, OS keychain dumps, plaintext credential-store downgrades
- **Exfiltration & tunnel guard** — reverse tunnels (`ngrok`, `cloudflared`, `ssh -R`), browser remote-debug cookie theft, fetch-then-exec droppers, `scp`/`rsync`/cloud-upload of secret files, DNS-exfil via `dig`/`nslookup`, public IPFS-gateway fetches
- **Supply-chain guards** — exec-capable `git config` keys ([CVE-2026-55607](https://nvd.nist.gov/vuln/detail/CVE-2026-55607) class), `ext::`/`fd::` remote-helper transport ([CVE-2026-28292](https://www.codeant.ai/security-research/simple-git-remote-code-execution-cve-2026-28292)), install-script exec in `package.json`/`setup.py`/`binding.gyp`, Python `.pth` startup-exec, env-preload exec (`LD_PRELOAD`, `NODE_OPTIONS --require`, `BASH_ENV`), and the GitHub Actions ["pwn request"](https://www.microsoft.com/en-us/security/blog/2026/07/15/unpacking-asyncapi-npm-supply-chain-compromise-import-time-payload-delivery/) vector
- **MCP guard** — destructive/SQL write gates on GitHub and Postgres MCP servers, a per-server circuit-breaker (trips on 429/503), egress classification of MCP tool-argument URLs, and secret-scanning of MCP responses
- **Prompt injection defense** — scans MCP and web tool output for injection patterns
- **Rules & memory poisoning guard** — write-time protection on `CLAUDE.md`, `.cursorrules`, `.cursor/rules/*.mdc`, `AGENTS.md`, persistent-memory files, and editor auto-run configs (`.vscode/tasks.json` `folderOpen`, `mcp.json`, `.gemini/settings.json`)
- **Elicitation credential guard** — an MCP server can solicit input via a form; a malicious one uses that to phish an "API token" in a routine-looking dialog. This **declines** any elicitation whose schema asks for a credential-style field (`password`, `token`, `api_key`, `secret`, `private_key`) or whose prompt text asks for one in prose — unless the server is trusted via `trustedElicitationServers` or `/trust-mcp <server>`. Since an elicitation carries no in-session message, a declined form raises a desktop notification so the block isn't silent
- **Smart auto-approve** — read-only tools (`Read`, `Glob`, `Grep`, `git status`, test runners) skip confirmation automatically

### Cost & context control

- **Real-time cost tracking** — every tool call rolls up. No end-of-month surprises
- **Budget cap** — `"budget": 5.00` caps this session's spend; warns at 80%, blocks non-read tools at 100%
- **Pre-spawn cost forecast** — `[COST] Est. ~$1.90` before subagents run
- **Rate-limit burn projection** — `~52m left at this pace`
- **Bash output compactor** — verbose `git log`, `pytest`, `npm install` output (>50 lines) is compressed to a structured summary before it enters context. Failures keep their excerpt; passes show counts. Cuts the most common source of mid-session context exhaustion
- **Cache health monitoring** — warns when cache hit rate drops below 50% (silent re-billing), and names which of the three known causes applies
- **`fallbackModel` advisory** — flags when the v2.1.166+ fallback chain isn't configured, so overloaded Opus calls route to Sonnet/Haiku instead of dropping

### Memory across sessions

- **Reflexion memory** — at end-of-turn, scans for diagnostic markers (`the issue was`, `root cause`, `fixed by`) and writes a structured lesson. Surfaces matching lessons by topic overlap on the next prompt. Per-project, no cross-pollination
- **Auto-decisions capture** — extracts decision statements (`I'll use X because Y`, `chose X over Y`) and restores them at next session start, so you return to a mental model rather than a file list
- **Stack-derived standards** — detects React, Next.js, Vue, Svelte, Python, Go, Rust, PHP at session start and injects the relevant forbidden patterns and pitfalls
- **Session memory** — modified files, recent commits, economy tier, corrections
- **PreCompact preservation** — dumps lessons, decisions, and a transcript backup before compaction, so `/compact` doesn't lose them
- **Crash-resilient checkpoints** — state saved after every file modification

### Developer experience

- **DX guards that catch mistakes before they cost a round-trip** — merge-conflict markers left in a file, unparseable `.json`/`.yaml`/`.toml`, edits to generated files, hallucinated relative imports, a shebang script left non-executable, `cp`/`mv` clobbering a tracked file, and a verification runner whose exit code is masked (`pytest || true`)
- **Statusline** — model, project, branch, stack, tier, agent, MCP profile, context bar, cache efficiency, cost, rate-limit burn
- **8 roles** — `developer`, `designer`, `devops`, `pm`, `researcher`, `student`, `data`, `writer`. Switch with `as developer`
- **Token economy** — 3 tiers (`standard`, `lean`, `minimal`). Switch with `eco lean`
- **9 agent types** — every prompt classified automatically; Claude gets a routing hint without you picking
- **Tool preferences** — a `toolPreferences` map redirects `npm` → `pnpm`, `jest` → `vitest`, `pip` → `uv pip`. Suggests rather than blanket-denying, and catches `npx`/`bunx` wrappers
- **Per-subagent cost breakdown** — `/sc-status` shows which agent burned the budget
- **Time-boxed modes** — auto-expiring session controls (per-session by default, `global` opt-in, 2h cap, statusline indicator, no daemon). One governing rule: **tighten beats loosen**
  - **`/sc-autopilot 30m`** *loosens* — stops the yes/no prompts. Keeps the safety floor (`rm -rf`, force-push, credential leaks still blocked); it only drops the approval friction
  - **`/sc-readonly 20m`** *tightens* — blocks all file edits **and** mutating shell commands while allowing reads, searches, and planning. "Look, don't touch"
  - **`/sc-strict 30m`** *tightens* — auto-approves nothing; you confirm every call. Overrides autopilot while active
- **30+ slash commands** — [full list below](#slash-commands)

Recent changes are in [`CHANGELOG.md`](CHANGELOG.md).

---

## Install modes

| Mode | Hooks | Use when |
|--|--|--|
| **Safe** | 25 | Security blocks + smart auto-approve + audit trail. Minimal footprint. |
| **Full** | 90 | Everything: cost tracking, memory, learning loop, statusline, confidence gate. Recommended. |

```bash
./install.sh                                    # interactive
./install.sh --mode full --roles developer      # non-interactive (CI/scripts)
```

Install writes hooks/agents/commands/rules to `~/.claude/`, registers them in `~/.claude/settings.json`, and appends a managed block to `~/.claude/CLAUDE.md`. It also sets two `settings.json` keys — `env.ENABLE_PROMPT_CACHING_1H=1` and an `attribution` override. `./uninstall.sh` reverses all of it from the pre-install backup.

### Install as a plugin

Supercharger ships the **full** framework through Claude Code's native plugin system, with no install script to run:

```
/plugin marketplace add smrafiz/claude-supercharger
/plugin install supercharger@claude-supercharger
```

At enable time you're prompted for role, economy tier, and MCP profile. Update with `/plugin update`, toggle with `/plugin enable|disable`.

> **On Windows the plugin still needs Git Bash.** There is no install script to run,
> but every hook *is* a bash script. Claude Code picks Git Bash as its hook
> interpreter when it is installed and **falls back to PowerShell when it is not** —
> and under PowerShell none of these hooks run. The classic installer cannot hit this
> (it needs bash to execute at all); the plugin can, because nothing in the install
> path requires bash. Install Git for Windows first.

**Every guard runs identically on both channels.** What differs is packaging:

- **Slash commands are namespaced** — `/audit` becomes `/supercharger:audit`
- **`/sc-update` → `/plugin update`** and **`/sc on|off` → `/plugin enable|disable`** (those two aren't shipped in the plugin)
- The guardrail layer is delivered as **SessionStart context** instead of a `CLAUDE.md` block — same rules, and uninstalling leaves zero residue
- **Statusline, 1h prompt cache and attribution** need three `settings.json` keys a plugin cannot declare (its manifest supports only `agent` and `subagentStatusLine`). Answer **yes** to *"Write statusline + prompt-cache settings"* when enabling and they're written for you on first run — backed up first, never overwriting a statusline you already set, and undoable with `tools/plugin-setup.sh --revert`. Answer **no** to keep the plugin strictly inside its own space; you can run that script yourself later instead.
- **MCP profile filtering doesn't apply.** The plugin ships its MCP servers through the manifest, so Claude Code's per-server approval is what selects them — the `light`/`dev`/`research`/`full` profiles only work when Supercharger writes `~/.claude.json` itself.
- Hooks keep the portable `#!/usr/bin/env bash` shebang, so they're **~1.8 ms/exec slower** than a classic install, which rewrites them to an absolute interpreter path.

> **Pick one channel.** Don't run `install.sh` and the plugin at the same time — they'd double-fire hooks and split state across two directories. The plugin's setup detects a classic install and stands down rather than repointing your working statusline.


---

<details id="configure">
<summary><strong>Configure</strong></summary>

### Project config

Drop `.supercharger.json` in your repo root. Commit it so your whole team gets the same behavior:

```json
{
  "roles": ["developer", "designer"],
  "economy": "lean",
  "budget": 5.00,
  "profile": "fast",
  "hints": "React + Tailwind, use pnpm"
}
```

### Performance profiles

| Profile | Behavior |
|--|--|
| `standard` | All hooks active (default) |
| `fast` | Skips 7 analytics hooks; keeps code quality and security |
| `minimal` | Skips 10 hooks; security-only |

Security hooks always run regardless of profile.

```bash
SUPERCHARGER_PROFILE=fast claude
# or per-project: {"profile": "fast"}
```

### Opt out of specific features

| Feature | Env var |
|--|--|
| Reflexion memory | `SUPERCHARGER_LESSONS=0` |
| Stack standards | `SUPERCHARGER_STANDARDS=0` |
| Confidence gate | `SUPERCHARGER_CONFIDENCE=0` |
| Path guard | `SUPERCHARGER_PATH_GUARD=0` |
| Tool preferences | `SUPERCHARGER_TOOL_PREFS=0` |
| Bash output compactor | `SUPERCHARGER_BASH_COMPACTOR=0` |
| All advisory hooks | `SUPERCHARGER_ADVISORY_HOOKS=0` |
| Memory injection | `SUPERCHARGER_NO_MEMORY=1` |
| Daily update check (network) | `SUPERCHARGER_NO_UPDATE_CHECK=1` |

### Tune behavior

| Setting | Env var | Default |
|--|--|--|
| Lesson-recall match threshold (Jaccard overlap) | `SUPERCHARGER_LESSON_THRESHOLD` | `0.35` |
| Pricing model override (cost trackers) | `SUPERCHARGER_PRICING_MODEL` | auto-detect from payload |
| Performance profile | `SUPERCHARGER_PROFILE` | `standard` (or `fast`, `minimal`) |
| Economy tier | `SUPERCHARGER_TIER` | `standard` (or `lean`, `minimal`) |

Lower `SUPERCHARGER_LESSON_THRESHOLD` to 0.2 if lessons rarely surface; raise to 0.5 if noisy.

Disable security categories: `{"disableSecurityCategories": ["clipboard", "build-artifacts"]}`

Categories: `filesystem`, `database`, `destructive`, `network`, `credentials`, `persistence`, `clipboard`, `browser`, `history`, `selfmod`, `path-traversal`, `symlink`, `git-internals`, `abs-path`, `build-artifacts`.

Add your own blocks: `{"customPatterns": ["terraform[[:space:]]+apply", "kubectl[[:space:]]+delete"]}`

Extended regex, matched case-insensitively against the command — the same engine the built-in patterns use. Commit it and the whole team inherits the rule. Capped at 50 patterns of 200 chars. A pattern that isn't valid regex is reported at session start and skipped — it cannot disable the built-in guards, which are evaluated separately for exactly that reason.

Exempt a specific command: `{"allowPatterns": ["rm -rf .*/Library/Caches/"]}`

For the false positive you hit repeatedly. Without it the only escape is `disableSecurityCategories`, which switches a whole category off — so this is the narrower instrument, never a wider one: it reaches exactly the blocks that setting already removes wholesale. Three limits are enforced in code, not just documented:

- **It can never exempt a self-modification block.** These patterns live in `.supercharger.json`, which the `selfmod` rule protects — a pattern able to exempt `selfmod` could authorise edits to the file granting it that power.
- **`git-safety`, `path-guard` and `harness-tamper-guard` are untouched.** The human-approval floor is not negotiable from a config file.
- **An invalid regex fails safe.** The command stays blocked; a broken allow rule never widens the guard.

Every exemption is written to the block ledger, so `/why` and the session `[BLOCKS]` summary show what was let through.

Work across sibling repos: `{"additionalRoots": ["../my-pro-plugin"]}`

For a wrapper directory holding two repos that must change together (a free/pro plugin pair, an SDK and its example app).

**You probably don't need this.** Since v2.26.43, path-guard honours Claude Code's own directory authorisation — `--add-dir`, the `/add-dir` command, and `permissions.additionalDirectories` in `settings.json`. If you've told Claude Code a directory is in your workspace, writes to it are allowed. Reach for `/add-dir ../sibling-repo` first; `additionalRoots` is only for roots Claude Code doesn't know about.

**And since v2.26.42** the project boundary is pinned to the directory you *launched* Claude in, and stays there for the whole session. Open Claude in the wrapper and both repos are in scope permanently — even after `cd` moves the working directory into one of them. Previously the boundary followed `cwd`, so a mid-session `cd` silently pushed the sibling out of the project and writes that worked at the start began failing with nothing explaining why.

`additionalRoots` is for the case the launch directory can't cover: repos that aren't under one parent, or a session started inside one repo. Widening to the enclosing git repo doesn't help there, because each repo is its own git root.

Paths are relative to the project root, or absolute. Put one in each repo pointing at the other; commit them and the team inherits the setup. *(Launching Claude from the wrapper directory needs no config at all — both repos are then already inside the boundary.)*

It only widens the "is this inside my project" test, and it can never subtract a protection:

- **`/`, `$HOME`, any ancestor of `$HOME`, and `~/.claude` are refused.** A root that resolves to any of them would disable the guard while looking like a whitelist. The same refusals apply to the launch directory *and* to Claude Code's own added directories — starting Claude from `~`, or running `/add-dir ~`, would otherwise quietly make your whole home directory writable. Claude Code granting **read** access to a tree is not consent to **write** to it.
- **The credential and system list stays blocked** — `~/.ssh`, `~/.aws`, `~/.config`, `/etc/` and the rest are checked *before* the boundary test, so no whitelist can reach them.
- **Roots are resolved through symlinks** before being trusted, and a path that doesn't exist (or isn't a directory) is ignored rather than silently accepted.

This is the supported way to customise enforcement. Editing the installed hooks is not: `harness-tamper-guard` blocks it, and a forked guard stops receiving security updates.

### Speed & tokens

Measured, not estimated: **Claude Code runs same-event hooks concurrently** (observed ~11 at a time), so a tool call's *felt* cost is the slowest wave, not the sum of every hook.

| machine | felt / tool call | chain sum (CPU) | statusline (cold / warm) |
|---|---:|---:|---:|
| M4 Pro, bash 3.2 | **7.6 ms** | 70.0 ms | 36.4 / 6.6 ms |
| GitHub ubuntu runner | **12.4 ms** | 107.2 ms | 61.7 / 4.0 ms |
| 2020 Intel Mac, bash 3.2 | 20–40 ms | — | — |

**Half the chain sum is not ours to give back.** Starting bash and exiting costs 2.00 ms on the M4 Pro, so 17 hooks pay 34 ms in process creation before one of them runs a line — 49% of the 70 ms. The per-hook spread is flat (2.0–7.4 ms, no outlier), and the cheapest guard is already *at* that floor. Optimising individual hooks can only touch the other half, and none of it is perceptible: the felt number is what you feel, and it is under 13 ms everywhere we measure.

Reproduce it on your own machine with `bash tests/perf-chain.sh` (from a clone) — it reports the felt estimate, the sequential sum split into process spawn and hook work, and the slowest single hook. `--target statusline` measures the status bar separately. CI runs both on every push and posts the table to the job summary.

**A caveat on `/perf`:** on bash 3.2 — the macOS default — its `avg_ms` column is inflated, sometimes 10–60×, because the profiler forks `python` per hook fire to read the clock and that fork lands inside the measurement. `/perf` prints a warning to this effect; rank by its **Calls** column and measure a specific hook independently before optimising it. On bash 5+ the clock is fork-free and the numbers are accurate.

That said, most felt slowness is not the hooks. Biggest levers, in order of impact:

**Faster**
- **`/sc-autopilot 2h`** — stop the per-command yes/no prompts for a while (safety hooks still run). Permission waits dwarf hook overhead; this is the single biggest latency win
- **Background long commands** — run `tsc`, builds, tests, and dev servers in the background so they don't block the turn
- **`/profile fast`** (skips 7 analytics hooks) or **`/profile minimal`** (skips 10; security-only)
- **`.supercharger-no-typecheck`** in a repo root — skip type-checking on just that repo (the one real per-edit cost on big projects)
- **Thinking a long time on a *simple* request?** That's native Claude reasoning effort, not Supercharger — use `/effort low` or `/effort medium`

**Fewer tokens**
- **`/compact`** when context is high; **`/clear`** when switching to unrelated work
- **`/memory-prune`** — archive resolved memory entries so they stop loading every session
- Supercharger's own footprint is small — rule files are path-scoped and per-prompt injections are a few tokens — so the dominant token cost is **conversation length**, not the hooks

### Project verify hook

Drop `.claude/verify.sh` in your repo. Claude runs it on stop; failures keep it fixing.

```bash
cp ~/.claude/supercharger/docs/templates/verify.sh .claude/verify.sh
chmod +x .claude/verify.sh
```

</details>

<details>
<summary><strong>Statusline indicators</strong></summary>

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

- **Line 1** — model, project, git branch, detected stack, economy tier, active agent, active MCP profile, lines added/removed
- **Line 2** — context bar, percentage, token counts (in/out), cache efficiency and tokens saved
- **Line 3** — session cost, duration, rate-limit burn rate and weekly usage

Transient alerts appear on line 1: `Mem: Restored`, `⚠ Scan: Secrets`, `⚠ Scan: Code`, `⚠ Scan: Injection`

</details>

<details id="slash-commands">
<summary><strong>Slash commands</strong></summary>

**Control & modes** — the everyday levers, several unique to Supercharger:

| Command | Purpose |
|--|--|
| `/sc-autopilot 2h` | Stop the yes/no permission prompts for a set time — the safety floor stays on. The single biggest speed win |
| `/sc-readonly 20m` | "Look, don't touch" — blocks all edits **and** mutating shell commands, allows reads / searches / planning |
| `/sc-strict 30m` | Confirm **every** call — auto-approves nothing. Overrides autopilot while active |
| `/sc off\|on\|status` | Flip to plain Claude Code and back — guards, statusline, prompt rules and Supercharger's MCP servers all stand down; no uninstall |
| `/sc-status` | What's active now — session cost, economy tier, disabled hooks, per-subagent spend |
| `/profile [fast\|minimal]` | Show or switch the performance profile (skips analytics hooks to cut overhead) |
| `/sc-update` | Check for and apply Supercharger updates *(classic install; the plugin uses `/plugin update`)* |

**Workflow:**

| Command | Purpose |
|--|--|
| `/handoff [context]` | Session resume brief → `.claude/handoff.md` |
| `/pr [description]` | Prepare and create a pull request |
| `/scope [task]` | Pre-flight check — files to touch, risks, blast radius |
| `/estimate [task]` | Time + complexity report. Halts before code starts |
| `/interview [topic]` | Structured requirements gathering, one question at a time |
| `/multi-review [target]` | Three parallel agents (security / perf / DX), synthesized |
| `/security [scope]` | OWASP-anchored review with severity-ranked findings |
| `/audit [scope]` | Consistency sweep across naming, patterns, docs, interfaces |
| `/cleanup [scope]` | Dead code / unused-import removal with two-tier safety |

**Reasoning & debugging:**

| Command | Purpose |
|--|--|
| `/think [problem]` | Structured reasoning for ambiguous problems |
| `/challenge [decision]` | Adversarial stress-test — assumptions, failure modes, strongest alternative |
| `/stuck [symptom]` | Breaks debug loops with fresh hypotheses |
| `/why [hook]` | Explain the most recent hook firing — what triggered, what was blocked, fix step |

**Insight, memory & housekeeping:**

| Command | Purpose |
|--|--|
| `/learn <rule>` | Record an explicit project rule. Surfaces on future prompts |
| `/memory-prune` | Archive resolved memory entries so they stop loading into context |
| `/perf [--slow]` | Hook timing report |
| `/cache-stats` · `/cache-clear` | Typecheck / quality-gate cache state, or clear the hash caches |
| `/trust-mcp <server>` | Trust an MCP server to request credential-style fields (elicitation) |
| `/reflect` | Score session quality, write to `.claude/session-observations.md` |
| `/devlog [entry]` | Append a decision to `DEV-LOG.md` |
| `/design [brand]` | Generate `DESIGN.md` — tokens, typography, components |
| `/supercharger` | List all slash commands |

</details>

<details>
<summary><strong>MCP profiles</strong></summary>

| Profile | Servers | Context cost |
|--|--|--|
| `light` (default) | context7 | ~300 tokens |
| `dev` | + Playwright, GitHub, Magic UI | ~1,200 tokens |
| `research` | + Memory, Sequential Thinking | ~1,500 tokens |
| `full` | everything (dev + research) | ~3,500 tokens |

Supercharger tags its entries `#supercharger` and never touches your existing servers. Heavy servers are opt-in via `SUPERCHARGER_MCP_EXTRAS="playwright,github"`.

```bash
bash tools/mcp-profile.sh [profile]
```

**Your own MCP servers.** Adding a server is Claude Code's job — `claude mcp add <name> -- <cmd>`, or `--transport http <name> <url>` — and Supercharger doesn't reimplement it. What it adds is *profile awareness*: register a server you already added, pick which profiles it belongs to, and it's configured only while one of those is active (and moved aside by `/sc off`).

```bash
claude mcp add my-thing -- npx -y my-mcp-server     # Claude Code adds it
bash tools/mcp-custom.sh adopt my-thing dev,full    # only loaded in dev + full
bash tools/mcp-custom.sh list
bash tools/mcp-custom.sh remove my-thing            # hands it back, untagged
```

Adopting takes ownership: the entry moves into a Supercharger registry (so a profile switch can add/remove it) and is restored to you untouched on `remove`. Servers you don't adopt are never modified.

</details>

<details>
<summary><strong>Tools</strong></summary>

All in `~/.claude/supercharger/tools/` after install:

| Script | Purpose |
|--|--|
| `update.sh` | Self-update |
| `claude-check.sh` | Full diagnostic |
| `hook-toggle.sh` | Enable/disable individual hooks |
| `hook-new.sh` | Scaffold a custom hook |
| `hook-doctor.sh` | Diagnose broken hook installs |
| `economy-switch.sh` | Change economy tier permanently |
| `mcp-profile.sh` | Switch MCP profile |
| `token-report.sh` | Per-session token cost breakdown |
| `session-analytics.sh` | Daily cost rollup (`--days N`) |
| `hook-perf.sh` | Hook timing analysis |

</details>

---

## FAQ

**Will this break my existing Claude setup?**
No. The installer backs up everything before touching it. `./uninstall.sh` restores exactly what you had.

**A hook blocked something I actually need.**
Run `/why` to see what fired and why. Then either `bash tools/hook-toggle.sh <hook-name> off`, or run the command directly in your terminal outside Claude.

**My script copies a file into `~/.claude/supercharger/hooks/` and is now denied.**
Expected as of 2.24.14. Writing over an installed hook is how the guardrail layer gets torn down, so `cp`/`install`/`rsync`/`curl -o`/`wget -O` aimed **into** the install dir are blocked alongside `rm` and `>`. Use `./install.sh` or `tools/update.sh`, which the guard does not intercept. Reading and copying **out** (`cp <hook> /tmp/`) still work.

**Can I temporarily switch back to plain Claude Code?**
Yes — `/sc off` deactivates Supercharger globally (a kill-switch every hook honors instantly: no guards, no injection, no statusline) and `/sc on` restores it. Nothing is uninstalled; the files stay dormant and a timestamped backup is written first. It also moves **Supercharger's own** MCP servers aside so they stop loading and stop costing you context — MCP servers you added yourself are left alone. Two caveats: hooks stop immediately, but the `CLAUDE.md` prompt rules and the MCP change take effect on your **next** session; and **while off, the security guards are off too** — you're on stock Claude with no safety net until you `/sc on`.

**How does this compare to SuperClaude, agent-os, or BMad?**
Those are markdown files Claude reads and chooses to follow, and every rule costs context tokens that compound over a session. Supercharger's enforcement is a separate process with an exit code — no context cost, and no way for the model to opt out. The prompt-based layer here (roles, economy tiers) works the same way theirs does; the hook layer is what's different. See [What this does and doesn't guarantee](#what-this-does-and-doesnt-guarantee) for the limits.

**How do I debug what hooks are doing?**
Hook output is hidden by default. Per-project: `touch .supercharger-debug` in your repo root. Globally: `touch ~/.claude/supercharger/scope/.debug-hooks`.

**How do I upgrade?**
`bash ~/.claude/supercharger/tools/update.sh`

**Does this send any data anywhere?**
No telemetry, no analytics, no API keys read, and no user data ever leaves your machine. The only network call is an optional once-daily version check (`update-check.sh`, Full mode) that fetches this project's public version string from GitHub and sends nothing but a static `User-Agent`. Disable with `SUPERCHARGER_NO_UPDATE_CHECK=1`, `--mode safe`, or `hook-toggle.sh update-check off`. `tools/update.sh` also contacts GitHub, but only when you run it. Optional webhook notifications (opt-in) POST to URLs you configure. Nothing else makes network calls.

**Can I write my own hooks?**
```bash
bash tools/hook-new.sh my-hook PostToolUse Bash
bash tools/hook-toggle.sh my-hook on
```
Full guide: [`docs/HOOK_AUTHORING.md`](docs/HOOK_AUTHORING.md)

**Windows?**
Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or **Git Bash** — Claude Code auto-selects Git Bash as its hook interpreter on Windows, so the hooks run as-is. Git Bash is a **requirement, not a preference**: Claude Code falls back to PowerShell when it is absent, and every hook here is a bash script, so all of them silently fail to run.

Every CI run exercises a `windows-latest` job under Git Bash. It verifies that hooks execute, `rm -rf /` is still blocked, the hashing used for per-project state works, the platform is detected for notifications, and `.sh` files check out with LF endings rather than CRLF. Install prerequisites: **Git for Windows**, Python (the `py` launcher is fine), and `jq` — `winget install jqlang.jq` or `choco install jq`, then reopen Git Bash.

Two things are **not** verified, and it would be dishonest to imply otherwise: nobody has watched a desktop notification actually render on Windows (the CI job proves the correct backend is selected, not that a toast appears), and no human has run a full install on a Windows desktop — only the scripted CI path. If you try it, [open an issue](https://github.com/smrafiz/claude-supercharger/issues) either way; that is the gap.

Alpine Linux is **not supported** (it ships `ash`, not `bash`) — run inside a Debian/Ubuntu/Fedora container, or install GNU bash first.

---

## Scope of protection

Supercharger guards **agent-initiated** tool calls — anything the model invokes through Claude Code's tool channel passes through PreToolUse hooks first. Two flows fall outside that channel and cannot be enforced by exit-code blocking:

- **User `!` shell escapes** — Claude Code's `! <cmd>` prompt prefix runs commands directly in your shell, not through the Bash tool, so PreToolUse hooks never fire. `shell-escape-advisor.sh` scans `!` prompts for `rm -rf`, `curl|bash`, `git push --force`, and `git reset --hard` and warns — but the shell still executes the command. Treat `!` like a separate terminal: Supercharger does not see it.
- **Commands run in your terminal outside the Claude Code session** — by design. This is a Claude Code layer, not a shell-level guard.

If you need shell-level enforcement regardless of source, layer that separately (e.g. an `rm` function in `~/.zshrc`).

### Standards alignment

Supercharger maps to the [**OWASP Top 10 for Agentic Applications 2026**](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/):

- **Least-Agency** — every guardrail category is opt-out per project via `.supercharger.json`. Raising autonomy requires an explicit human-authored config change
- **Strong Observability** — every blocked command, Edit/Write/Bash decision, and subagent spawn is logged to `~/.claude/supercharger/scope/.blocked-commands` and `audit/` JSONL
- **Self-modification defense** — the `selfmod` category covers both the Bash channel (`safety.sh`) and the Write/Edit channel (`path-guard.sh`), closing the [March 2026 Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/)
- **Sandbox-bypass detection** — `config-scan.sh` covers three documented CVEs at session start: foreign hook injection ([CVE-2025-59536](https://nvd.nist.gov/vuln/detail/CVE-2025-59536)), `ANTHROPIC_BASE_URL` exfiltration ([CVE-2026-21852](https://nvd.nist.gov/vuln/detail/CVE-2026-21852)), and `defaultMode=bypassPermissions` ([CVE-2026-33068](https://nvd.nist.gov/vuln/detail/CVE-2026-33068))

---

## Going deeper

- Every hook documented: [`docs/HOOKS.md`](docs/HOOKS.md) — event, matcher, purpose
- Hook authoring guide: [`docs/HOOK_AUTHORING.md`](docs/HOOK_AUTHORING.md)
- Roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md)
- Changelog: [`CHANGELOG.md`](CHANGELOG.md) · [archive](docs/CHANGELOG-archive.md)

---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), and others.

The security-hardening layer adapts enforcement patterns from several MIT-licensed guardrail projects — [efij/secure-claude-code (Stallion)](https://github.com/efij/secure-claude-code) (cloud/container/persistence/exfil/MCP vectors), [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) (staged-diff secret scan + crypto keys), [wintermeyer/heinzel](https://github.com/wintermeyer/heinzel) (disk/partition taboos), [mafiaguy/claude-security-guardrails](https://github.com/mafiaguy/claude-security-guardrails) (docker/system-power/scp-exfil), and [Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness) (file-lease, fact-gate, MCP circuit-breaker) — plus the commit-attribution-gate concept from [domengabrovsek/claude](https://github.com/domengabrovsek/claude). All were independently re-implemented as self-contained bash/python; see [NOTICE](NOTICE) for attributions.

## License

MIT — see [LICENSE](LICENSE)
