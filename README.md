# Claude Supercharger

Shell-level enforcement for Claude Code. Safety hooks that run **outside Claude's process** — before commands execute, invisible to the model, impossible to prompt-engineer around. Zero context-window cost: rules live in the shell, not in your prompt.

![Version](https://img.shields.io/badge/version-2.23.38-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-2338%20passing-brightgreen)

```
[claude-sonnet-4-6] myproject | main | TypeScript | Eco: Lean | Agent: Debugger | MCP: context7 | +156/-23
████████████░░░░░░░░ Context: 60% (120.5K/200K) | 115.2K in / 5.3K out | cache 92% (~103.7K saved)
Cost: $2.45 | Time: 8m 12s | Session: 24% (resets: 3h 42m) · Weekly: 15%
```

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

Or install without keeping the repo around — clones to a temp dir, installs, cleans up:

```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

30 seconds. Backs up your config. `./uninstall.sh` reverses everything.

Want plain Claude for a task? **`/sc off`** switches to default Claude Code (guards, memory, statusline all off), **`/sc on`** restores it — no uninstall, nothing deleted.

---

## The problem

Prompts are suggestions. Claude is good at finding reasons to ignore suggestions.

Every Claude Code user has a version of the same story: you ask to fix a typo and Claude rewrites the component. You ask a quick question and get an essay. You come back to find files overwritten, commands run, work undone — with no warning.

The fix isn't better prompts. It's moving enforcement somewhere Claude can't reach.

---

## How it works

Two layers with different guarantees.

**Shell hooks run outside Claude's process, before commands execute.** Claude can't see them, can't reason about them, can't be convinced to skip them. Exit code 2 means the command doesn't run. No negotiation.

**Prompt rules in `CLAUDE.md` shape behavior** — roles, economy tier, agent routing. Claude follows these reliably, but not unconditionally.

```
You ──▶ Claude ──▶ Tool call ──▶ [Hook] ──▶ exit 0 or exit 2
                                    │
                                    └── Runs outside Claude's view
```

![Supercharger hooks denying destructive commands before they run](assets/demo/demo.gif)

|  | Prompt-only frameworks (`CLAUDE.md` rules) | `/permissions` (inside Claude) | Supercharger hooks (outside Claude) |
|---|---|---|---|
| Claude sees the rules | Yes | Yes | No |
| Can be argued with | Yes | Yes | Can't argue with exit code 2 |
| Advisory or enforced | Advisory | Advisory | Enforced |
| **Cost in context tokens** | **~5–20K per session** | a few hundred | **0** |

This is the line between Supercharger and prompt-only frameworks. SuperClaude, agent-os, BMad modes — all are markdown files Claude reads and chooses to follow. Every rule they enforce burns context tokens that compound over a session and shrink the effective window for actual work. Supercharger's enforcement lives in the shell, not the prompt: zero context cost, zero risk of being talked out of it.

---

## What you get

### Runtime enforcement — can't be bypassed

- **Destructive command blocking** — `rm -rf /`, `DROP TABLE`, `chmod 777`, `curl | bash`, force-push to main, `git reset --hard`, disk/partition wipe (`mkfs`, `dd`, `wipefs -a`, `fdisk`/`parted`), fork bombs, `shutdown`/`reboot`
- **Path guard** — blocks 6 attack categories on Edit/Write: path traversal (incl. URL-encoded `%2e%2e`, null bytes), symlink attacks, `.git/hooks/` writes, **self-modification** (writes to `.disabled-security-categories`, `.claude/settings.json` hooks block, or `.supercharger.json` — closes the [Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/) where agents disable their own guardrails), writes to `~/.ssh/` / `~/.aws/` / `/etc/`, build artifact injection (`node_modules/.bin/`, `.next/`, `.venv/`). Each category opt-out per project
- **Confidence gate** — blocks Edit/Write/destructive Bash when confidence is low (recent failures, no prior read, repeated attempts). Warns or denies via PreToolUse hook
- **Code security scanning** — `eval()`, `pickle.load()`, SQL injection, weak crypto, hardcoded secrets, GitHub Actions injection
- **Credential leak detection** — scans Bash and Read output for AWS, OpenAI, Slack, Stripe, GCP, Azure, and crypto-wallet (Ethereum / BIP-32 `xprv` / Bitcoin WIF) tokens before Claude can echo them; also blocks committing a secret in the staged diff
- **Cloud & container guard** — blocks agent-unprompted cloud credential theft and escape: instance-metadata SSRF (`169.254.169.254` / GCP / ECS IMDS), `aws sts assume-role`, `aws iam create-access-key`, container escape (`--privileged`, host sockets, `nsenter`, `chroot /host`), `kubectl` cluster-admin bindings + secret reads, `terraform destroy`. Opt out per project with the `cloud` category
- **Persistence & tamper guard** — write-gated blocks on `/etc/sudoers` / `NOPASSWD`, `authorized_keys` backdoors, launchd / systemd / schtasks / cron persistence, `/etc/hosts` domain remaps, OS keychain dumps, and plaintext credential-store downgrades
- **Exfiltration & tunnel guard** — reverse tunnels (`ngrok`, `cloudflared`, `ssh -R`), browser remote-debug cookie theft (`--remote-debugging-port`), fetch-then-exec script droppers, `scp`/`rsync`/cloud-upload of secret files, and DNS-exfil via `dig` / `nslookup`
- **MCP guard** — destructive/SQL write gates on GitHub / Postgres MCP servers, a reactive per-server circuit-breaker (trips on 429/503), egress classification of MCP tool-argument URLs (metadata / webhook / paste-site), and secret-scanning of MCP responses
- **Prompt injection defense** — scans MCP and web tool output for injection patterns
- **Elicitation credential guard** — an MCP server can solicit input via a form (`Elicitation`); a malicious one uses that to phish an "API token" or "database password" in a routine-looking dialog. This **declines** any elicitation whose schema asks for a credential-style field (`password`, `token`, `api_key`, `secret`, `private_key`, camelCase variants) — or whose prompt text asks for one in prose ("paste your GitHub token"), catching servers that hide behind an innocuous field name — unless the server is trusted — in `trustedElicitationServers` in `.supercharger.json`, or added on the fly with `/trust-mcp <server>`. Since an Elicitation carries no in-session message, a declined form raises a **desktop notification** (respecting your notify off-switch) so the block isn't silent. Companion audit hook logs every request's schema shape + `ElicitationResult` keys (never values)
- **Smart auto-approve** — read-only tools (`Read`, `Glob`, `Grep`, `git status`, test runners) bypass confirmation automatically

### Cost & context control

- **Real-time cost tracking** — every tool call rolls up. No end-of-month surprises
- **Budget cap** — set `"budget": 5.00` in `.supercharger.json`. Caps **this session's** cost (resets each new conversation); warns at 80%, blocks non-read tools at 100%
- **Pre-spawn cost forecast** — `[COST] Est. ~$1.90` before subagents run
- **Rate-limit burn projection** — `~52m left at this pace`
- **Bash output compactor** — verbose `git log`, `pytest`, `npm install` output (>50 lines) compressed to a structured summary before it enters context. Failures keep their excerpt; passes show counts. Cuts the most common source of mid-session context exhaustion
- **Cache health monitoring** — warns when cache hit rate drops below 50% (silent re-billing). Diagnoses three causes: 5-minute default TTL, per-workspace cache isolation (Feb 2026+), and 20-block lookback drift in long sessions
- **`fallbackModel` advisory** — `claude-check.sh` flags when the v2.1.166+ fallback chain isn't configured. Overloaded Opus calls drop instead of routing to Sonnet/Haiku without it

### Memory across sessions

- **Reflexion memory** — at end-of-turn, scans for diagnostic markers (`the issue was`, `root cause`, `fixed by`) and writes a structured lesson. On the next prompt, surfaces matching lessons by topic overlap. Per-project, no cross-pollination
- **Auto-decisions capture** — extracts decision statements from your session (`I'll use X because Y`, `decided to`, `chose X over Y`) and persists them in session memory. Restored at next session start so you don't return to a file list — you return to a mental model
- **Stack-derived standards** — detects React, Next.js, Vue, Svelte, Python, Go, Rust, PHP at session start and injects forbidden patterns, toolchain conventions, and pitfalls
- **Session memory** — modified files, recent commits, economy tier, corrections — injected at next session start
- **PreCompact preservation** — before context compaction, dumps lessons + decisions + transcript backup. Survives `/compact` cleanly
- **Crash-resilient checkpoints** — state saved after every file modification

### Developer experience

- **Statusline** — model, project, branch, stack, tier, agent, MCP profile, context bar, cache efficiency, cost, rate-limit burn — every line
- **8 roles** — `developer`, `designer`, `devops`, `pm`, `researcher`, `student`, `data`, `writer`. Switch with `as developer`
- **Token economy** — 3 tiers (`standard`, `lean`, `minimal`). Switch with `eco lean`. Lean cuts response length ~45% with no information loss
- **9 agent types** — every prompt classified automatically, Claude gets a routing hint without you picking
- **Tool preferences** — `.supercharger.json` `toolPreferences` map redirects `npm` → `pnpm`, `jest` → `vitest`, `pip` → `uv pip`. Suggests instead of blanket-denying. Catches `npx`/`bunx` wrappers
- **Per-subagent cost breakdown** — `/sc-status` aggregates cost across subagents (Scientist, Detective, Engineer, etc.) so you can see which one burned the budget. Mirrors Claude Code's `/usage` view
- **On/off switch** — `/sc off` flips to plain default Claude Code (a global kill-switch every hook honors instantly; nothing uninstalled), `/sc on` restores everything. For when you want the vanilla experience for a task, or to A/B compare
- **Time-boxed modes** — auto-expiring session controls, unique to Supercharger (per-session by default, `global` opt-in, 2h cap, statusline indicator, no daemon). Governed by one rule: **tighten beats loosen.**
  - **`/sc-autopilot 30m`** *loosens* — stops the yes/no permission prompts for a set time. Keeps the **safety floor** (`rm -rf`, force-push, credential leaks still blocked); it only drops the approval friction.
  - **`/sc-readonly 20m`** *tightens* — blocks all file edits **and** mutating shell commands (`rm`, `git commit`, `npm install`, `sed -i`, write-redirects…) while allowing reads, searches, and planning. "Look, don't touch" for exploring or reviewing safely.
  - **`/sc-strict 30m`** *tightens* — auto-approves **nothing**; you confirm every call (near a deploy, on prod config). Overrides autopilot while active.
- **25+ slash commands** — `/think`, `/sc-status`, `/sc-autopilot`, `/sc-readonly`, `/sc-strict`, `/why`, `/learn`, `/estimate`, `/cleanup`, `/audit`, `/security`, `/stuck`, `/scope`, `/pr`, `/handoff`, `/multi-review`, `/trust-mcp`, and more

---

## Recent highlights (v2.14)

### Time-boxed modes (v2.12–v2.14)

A family of auto-expiring session controls — unique to Supercharger (every competitor toggles modes manually or statically; the per-tool-call expiry with no daemon is the differentiator). One governing rule: **tighten beats loosen.** Per-session by default, `global` opt-in, 2h cap, statusline indicator.

- **`/sc-autopilot`** *loosens* — skip the yes/no permission prompts for a set time; the safety floor stays active. *(v2.12.0, per-session default v2.12.2)*
- **`/sc-readonly`** *tightens* — block all edits + mutating shell commands, allow reads/searches/planning. "Look, don't touch." *(v2.13.0)*
- **`/sc-strict`** *tightens* — auto-approve nothing; confirm every call. Overrides autopilot. *(v2.14.0)*

### Distribution & reliability (v2.11)

- **Install as a Claude Code plugin** — the full framework now ships through the native plugin system (`/plugin marketplace add smrafiz/claude-supercharger` → `/plugin install`), alongside the classic `install.sh`. One dual-runnable codebase: hooks resolve their code and state roots so the same scripts run under both the installer and `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; the guardrail/economy layer a plugin can't write as files is delivered at SessionStart instead. See [Install as a plugin](#install-as-a-plugin). *(v2.11.0)*
- **Reliable `/sc-update`** — version detection now reads the `VERSION` in `lib/utils.sh` via the fresh GitHub contents API, so it never mis-reports "up to date" from orphaned tags or a stale CDN. *(v2.11.1, v2.12.1)*

### Security-hardening milestone (v2.9–v2.10)

A large expansion of the enforcement surface, most of it distilled from auditing ~50 "guardrail/harness" projects against Supercharger's thesis and adopting only the self-contained, low-false-positive patterns (see [Credits](#credits)). Test suite grew 1319 → 1464 with zero regressions.

### New enforcement hooks

- **Commit-time secret guard** — blocks `git commit` when the **staged diff** introduces a secret (API keys, cloud creds, and Ethereum / BIP-32 / Bitcoin-WIF wallet keys) — closing the gap between output-scanning and Edit-scanning where a secret written via a shell redirect slips into history
- **Git hook-bypass block** — refuses `git commit --no-verify` / `-n` and the `-c core.hooksPath=` override, so the repo's own pre-commit checks can't be skipped
- **MCP circuit-breaker & egress guard** — trips a per-server breaker on `429`/`503` (stops burning turns on a down server), and classifies URLs in MCP tool arguments to block metadata-SSRF / webhook / paste-site egress
- **File-lease** — advisory warning when two live Claude sessions edit the same file; **fact-gate** (opt-in) makes Claude recite a file's importers/rollback before its first edit; **commit-coauthor-guard** (opt-in) strips AI-attribution trailers from commits

### Expanded attack surface (all opt-out by category)

- **Cloud & container** — instance-metadata SSRF, `aws sts assume-role` / `iam create-access-key`, container escape (`--privileged` / host sockets / `nsenter`), `kubectl` cluster-admin + secret reads, `terraform destroy`
- **Persistence & tamper** — `/etc/sudoers`, `authorized_keys` backdoors, launchd/systemd/schtasks/cron, `/etc/hosts` remaps, keychain dumps
- **Exfil & tunnel** — `ngrok`/`cloudflared`/`ssh -R`, browser remote-debug cookie theft, fetch-then-exec droppers, DNS-exfil
- **Disk destruction** — the partition-editor family (`wipefs -a`, `fdisk`/`parted`) on top of the existing `mkfs`/`dd` blocks

### New agent

- **Ferdinand Magellan (Navigator)** — a read-only code-exploration agent (Supercharger's analog of Claude Code's `Explore`): fans out, locates code, returns `file:line` conclusions rather than a pile of files

### Under the hood

- **Shared secret-pattern library** — one `lib-secret-patterns.sh` feeds both the output scanner and the commit guard, so a new pattern lands in both channels with no drift
- **Hot-files resume** — session restore now leads with the files the last session most actively edited (recency-decayed from the audit log), not just a flat diff

### Correct under concurrency

- **Cumulative session state is preserved** — fixed Stop/SubagentStop hooks that re-fire every turn wrongly wiping running per-session totals
- **Per-session isolation** — session-scoped state files (memory-restore badge, transcript token/cost offsets) keyed by session id, so running several Claude sessions at once no longer cross-contaminates token and cost counts

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

`./uninstall.sh` restores your original config from backup.

Install writes hooks/agents/commands/rules to `~/.claude/`, registers them in `~/.claude/settings.json`, and appends a managed block to `~/.claude/CLAUDE.md`. It also sets two `settings.json` keys — `env.ENABLE_PROMPT_CACHING_1H=1` (1-hour prompt cache) and an `attribution` override. `./uninstall.sh` reverses all of these from the pre-install backup.

### Install as a plugin

Prefer Claude Code's native plugin system? Supercharger ships the **full** framework — the same safety hooks, code security scanner, token economy, agent routing, and session memory — as a plugin, with no shell script:

```
/plugin marketplace add smrafiz/claude-supercharger
/plugin install supercharger@claude-supercharger
```

At enable time you're prompted for **role**, **economy tier**, and **MCP profile**. Update with `/plugin update`, toggle with `/plugin enable|disable claude-supercharger` — no reinstall.

A plugin can't write outside its own space, so a few things differ from `install.sh`:

- **Slash commands are namespaced** — `/audit` becomes `/supercharger:audit`, etc.
- **`/sc-update` → `/plugin update`** and **`/sc on|off` → `/plugin enable|disable`** (native equivalents; those two commands aren't shipped in the plugin).
- **No statusline** and **no `settings.json` tweaks** (`ENABLE_PROMPT_CACHING_1H`, attribution) — set those manually if you want them.
- The instructional/guardrail layer is delivered as **SessionStart context** instead of a `CLAUDE.md` block — same rules, and uninstalling leaves zero residue.

> **Pick one channel.** Don't run `install.sh` and the plugin at the same time — they'd double-fire hooks and split state across two directories. Uninstall one before adopting the other.

---

<details>
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

### Speed & tokens

Most felt slowness is **not** the hooks (~50–80ms total) — it's per-command permission prompts and long-running foreground commands. Biggest levers, in order of impact:

**Faster**
- **`/sc-autopilot 2h`** — stop the per-command yes/no prompts for a while (the safety hooks still run). This is the single biggest latency win; permission waits dwarf hook overhead.
- **Background long commands** — run `tsc`, builds, tests, and dev servers in the background so they don't block the turn. On a large repo, Supercharger nudges you here when type-checking runs slow.
- **`/profile fast`** (skips 7 analytics hooks) or **`/profile minimal`** (skips 10; security-only).
- **`.supercharger-no-typecheck`** in a repo root — skip type-checking on just that repo (the one real per-edit cost on big projects).
- **Thinking a long time on a *simple* request?** That's native Claude reasoning (effort level), not Supercharger — use **`/effort low`** or **`/effort medium`**. (Supercharger no longer touches reasoning time as of v2.18.0.)

**Fewer tokens**
- **`/compact`** when context is high; **`/clear`** when switching to unrelated work.
- **`/memory-prune`** — archive resolved memory entries so they stop loading into context every session.
- Supercharger's own footprint is small — the rule files are path-scoped (load only when relevant) and per-prompt injections are a few tokens — so the dominant token cost is **conversation length**, not the hooks.

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
  Transient alerts on line 1: `Mem: Restored`, `⚠ Scan: Secrets`, `⚠ Scan: Code`, `⚠ Scan: Injection`

</details>
<details>
<summary><strong>Slash commands</strong></summary>

| Command | Purpose |
|--|--|
| `/think [problem]` | Structured reasoning for ambiguous problems |
| `/challenge [decision]` | Adversarial stress-test — assumptions, failure modes, strongest alternative |
| `/audit [scope]` | Consistency sweep across naming, patterns, docs, interfaces |
| `/security [scope]` | OWASP-anchored review with severity-ranked findings |
| `/stuck [symptom]` | Breaks debug loops with fresh hypotheses |
| `/scope [task]` | Pre-flight check — files to touch, risks, blast radius |
| `/estimate [task]` | Time + complexity report. Halts before code starts |
| `/cleanup [scope]` | Dead code / unused-import removal with two-tier safety |
| `/pr [description]` | Prepare and create a pull request |
| `/handoff [context]` | Session resume brief → `.claude/handoff.md` |
| `/multi-review [target]` | Three parallel agents (security / perf / DX), synthesized |
| `/reflect` | Score session quality, write to `.claude/session-observations.md` |
| `/devlog [entry]` | Append decision to `DEV-LOG.md` |
| `/design [brand]` | Generate `DESIGN.md` — tokens, typography, components |
| `/sc-status` | Render current Supercharger session state (cost, lessons, disabled hooks) |
| `/why [hook]` | Explain the most recent hook firing — what triggered, what was blocked, fix step |
| `/learn <rule>` | Record an explicit project rule. Surfaces on future prompts |
| `/perf [--slow]` | Hook timing report |
| `/sc off\|on\|status` | Deactivate/reactivate Supercharger — flip to plain default Claude on demand, no uninstall |
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

## FAQ

**Will this break my existing Claude setup?**
No. The installer backs up everything before touching it. `./uninstall.sh` restores exactly what you had.

**A hook blocked something I actually need.**
`bash tools/hook-toggle.sh <hook-name> off` — or run the command directly in your terminal, outside Claude.

**Can I temporarily switch back to plain Claude Code?**
Yes — `/sc off` deactivates Supercharger globally (a kill-switch every hook honors instantly: no guards, no injection, no statusline — stock Claude), and `/sc on` restores everything. `/sc status` shows the current state. Nothing is uninstalled; files stay dormant on disk, `settings.json` is never touched, and a backup is written to `~/.claude/backups/` first. Good for A/B comparing, or a task where you want the vanilla experience. Two notes: hooks go off immediately (next tool call), but the `CLAUDE.md` prompt rules clear on your **next session** (they're loaded once at start); and **while off, the security guards are off too** — you're on stock Claude with no safety net until you `/sc on`.

**How do I debug what hooks are doing?**
Hook output is hidden by default. Enable per-project: `touch .supercharger-debug` in your repo root. Enable globally: `touch ~/.claude/supercharger/scope/.debug-hooks`.

**How do I upgrade?**
`bash ~/.claude/supercharger/tools/update.sh`

**Does this send any data anywhere?**
No telemetry, no analytics, no API keys read, and no user data ever leaves your machine. The only network call is an optional once-daily version check (`update-check.sh`, Full mode) that fetches this project's public version string from GitHub and sends nothing but a static `User-Agent`. Disable it with `SUPERCHARGER_NO_UPDATE_CHECK=1`, `--mode safe`, or `hook-toggle.sh update-check off`. `tools/update.sh` also contacts GitHub, but only when you run it. Optional webhook notifications (opt-in via `webhook.json`) POST to URLs you configure. Nothing else makes network calls.

**Can I write my own hooks?**
```bash
bash tools/hook-new.sh my-hook PostToolUse Bash
bash tools/hook-toggle.sh my-hook on
```
Full guide: [`docs/HOOK_AUTHORING.md`](docs/HOOK_AUTHORING.md)

**Windows?**
Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.
 
---

## Going deeper

- Every hook documented: [`docs/HOOKS.md`](docs/HOOKS.md) — event, matcher, purpose
- Hook authoring guide: [`docs/HOOK_AUTHORING.md`](docs/HOOK_AUTHORING.md)
- Roadmap: [`docs/ROADMAP.md`](docs/ROADMAP.md)
- Contributing: [`CONTRIBUTING.md`](CONTRIBUTING.md)
---

## Standards alignment

Supercharger maps to the [**OWASP Top 10 for Agentic Applications 2026**](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/) framework:

- **Least-Agency** — every guardrail category (`filesystem`, `database`, `destructive`, `network`, `credentials`, `persistence`, `selfmod`, etc.) is opt-out per project via `.supercharger.json`. Agents get the minimum autonomy needed for the task; raising autonomy requires an explicit human-authored config change
- **Strong Observability** — every blocked command, every Edit/Write/Bash decision, every subagent spawn is logged to `~/.claude/supercharger/scope/.blocked-commands` and `audit/` JSONL. Tool-use patterns and decision pathways are reconstructable
- **Self-modification defense** — `selfmod` category in `safety.sh` (Bash channel) and `path-guard.sh` (Write/Edit channel) blocks attempts to modify `.disabled-security-categories`, `.claude/settings.json` hooks block, or `.supercharger.json` — closes the [March 2026 Ona Security sandbox-bypass pattern](https://www.penligent.ai/hackinglabs/claude-code-sandbox-bypass/) where Claude Code agents reasoned about their bubblewrap sandbox and disabled the blocker
- **Sandbox-bypass attempt detection** — `config-scan.sh` covers three documented CVEs at session start: foreign hook injection ([CVE-2025-59536](https://nvd.nist.gov/vuln/detail/CVE-2025-59536)), ANTHROPIC_BASE_URL exfiltration ([CVE-2026-21852](https://nvd.nist.gov/vuln/detail/CVE-2026-21852)), and `defaultMode=bypassPermissions` ([CVE-2026-33068](https://nvd.nist.gov/vuln/detail/CVE-2026-33068))

### Scope of protection

Supercharger guards **agent-initiated** tool calls (Bash, Write, Edit, etc.) — anything the model invokes through Claude Code's tool channel passes through PreToolUse hooks first. Two flows fall outside that channel and cannot be enforced by exit-code blocking:

- **User `!` shell escapes** — Claude Code's `! <cmd>` prompt prefix runs commands directly in the user's shell, not through the Bash tool. PreToolUse:Bash hooks never fire. `shell-escape-advisor.sh` (UserPromptSubmit) scans prompts starting with `!` for `rm -rf`, `curl|bash`, `git push --force`, `git reset --hard` and emits an advisory warning — but the shell still executes the command. Treat `!` like running the command in a separate terminal: Supercharger does not see it.
- **Commands run in your terminal outside the Claude Code session** — by design. Supercharger is a Claude Code layer, not a shell-level guard.

If you need shell-level enforcement of dangerous patterns regardless of source, layer a shell-level guard (e.g. an `rm` function in `~/.zshrc` or a `command_not_found_handler` wrapper). Supercharger's enforcement applies to what the agent does on your behalf.
---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3.6+
- `jq` (install with `brew install jq` or `apt-get install jq` — install.sh checks at start)

**Not supported:** Alpine Linux (ships `ash`, not `bash`). Run inside a Debian/Ubuntu/Fedora container instead, or install GNU bash on Alpine first.
---

## Credits

Built on patterns from [SuperClaude](https://github.com/SuperClaude-Org/SuperClaude_Framework), [agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template), [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config), [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook), [prompt-master](https://github.com/nidhinjs/prompt-master), [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), [get-shit-done](https://github.com/gsd-build/get-shit-done), [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [claude-code-tips](https://github.com/ykdojo/claude-code-tips), and others.

The security-hardening layer (v2.9–2.10) adapts enforcement patterns from several MIT-licensed guardrail projects — [efij/secure-claude-code (Stallion)](https://github.com/efij/secure-claude-code) (cloud/container/persistence/exfil/MCP vectors), [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) (staged-diff secret scan + crypto keys), [wintermeyer/heinzel](https://github.com/wintermeyer/heinzel) (disk/partition taboos), [mafiaguy/claude-security-guardrails](https://github.com/mafiaguy/claude-security-guardrails) (docker/system-power/scp-exfil), and [Chachamaru127/claude-code-harness](https://github.com/Chachamaru127/claude-code-harness) (file-lease, fact-gate, MCP circuit-breaker) — plus the commit-attribution-gate concept from [domengabrovsek/claude](https://github.com/domengabrovsek/claude). All were independently re-implemented as self-contained bash/python; see [NOTICE](NOTICE) for attributions.

## License

MIT — see [LICENSE](LICENSE)
