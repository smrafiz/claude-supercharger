# Claude Supercharger

Claude Code has root access to your filesystem and git history. One hallucinated `rm -rf ~`, one `git push --force main`, one committed API key — and you're spending hours recovering.

Supercharger prevents that. Shell hooks run before commands execute, outside Claude's conversation. Claude can't argue with them, override them, or find a creative reason to ignore them. Exit code 2. Command blocked. That's it.

The safety layer is the product. Everything else — agents, roles, economy tiers, MCP servers — is workflow improvement built on top of it.

![Version](https://img.shields.io/badge/version-2.0.8-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-253%20passing-brightgreen)

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

30 seconds. Six questions. Done. `./uninstall.sh` reverses everything.

<details>
<summary>Other install options</summary>

**One-liner** (temp clone, auto-clean):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI/scripts):
```bash
./install.sh --mode standard --roles developer --economy lean --config deploy --settings deploy
```

**Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash.
</details>

---

## What it actually does

Supercharger has two layers. The first is enforced — shell hooks that block dangerous commands regardless of what Claude wants. The second is instructional — prompt configurations that improve Claude's behavior but can't guarantee it.

### The enforced layer

These run as shell hooks. Claude doesn't see them, can't disable them, and gets a plain-English reason when something is blocked.

| What gets blocked | Why |
|---|---|
| `rm -rf /`, `rm -rf ~`, `rm -rf ..` (root, home, parent traversal), `DROP TABLE`, `chmod 777`, fork bombs | Irreversible destruction |
| `git push --force` to main/master | Overwrites shared history |
| `curl \| bash`, `eval`, credential patterns (AWS keys, GitHub tokens, etc.) | Remote code execution, secret exposure |
| `git reset --hard`, `git checkout .` | Loses uncommitted work |
| Wrong package manager (`npm` in a pnpm project) | Corrupts lockfile |
| Writing to `.bashrc`, `.zshrc`; SSH key commands (`ssh-keygen`, `ssh-add`) | Unauthorized persistence |

Other enforced features:
- **Audit trail** — every file write and command is logged to JSONL. Credentials auto-redacted before logging. 30-day rotation. When something goes wrong, you can trace what Claude changed and when.
- **Quality gate** — lint, auto-fix, re-check after file edits. Developer role, Standard/Full install mode only.
- **Prompt validator** — catches common anti-patterns (vague scope, missing file paths, multiple tasks in one request) before they waste a turn. Full install mode only.

### The instructional layer

These are prompt configurations. They shape Claude's behavior through system instructions — effective in practice, but not enforced at the shell level. Claude follows them because the instructions are well-structured, not because it's physically prevented from doing otherwise.

**Token economy** — three output tiers that instruct Claude to be more concise:

| Tier | What changes |
|---|---|
| **Standard** | Complete sentences. Good for learning. |
| **Lean** *(default)* | Every word earns its place. Fragments OK. |
| **Minimal** | Telegraphic. Bare output only. |

Switch mid-conversation: `eco lean` / `eco standard` / `eco minimal`. These instructions work — Claude does respond more concisely — but there's no hard token limit. Some responses will still be longer than you want.

**Agent routing** — each prompt is pattern-matched to one of nine agents, each with its own scope rules and verification requirements. Eight agents have specific regex routes (shown below); the ninth — Steve Jobs (Generalist) — handles prompts that don't match any pattern. The agent updates per prompt, so if you switch from debugging to writing docs, the agent changes with you. Greetings and small talk won't trigger a match — the router only responds to task-like prompts:

```
"There's a null pointer at line 42"            → Sherlock Holmes (Detective)
"Review this file for security issues"         → Gordon Ramsay (Critic)
"Add a login form to this page"                → Tony Stark (Engineer)
"Write a README for this project"              → Ernest Hemingway (Writer)
"Compare Redis vs Memcached for our use case"  → Marie Curie (Scientist)
"Design the auth system before we build it"    → Leonardo da Vinci (Architect)
"Plan the rollout and prioritize the backlog"  → Sun Tzu (Strategist)
"Analyze this CSV and show me the top sellers" → Albert Einstein (Analyst)
```

Routing uses regex matching, so it works best with clear intent. Ambiguous prompts may not match any pattern — Claude will still work, just without agent-specific rules. This isn't magic, but it does produce noticeably more focused output for common task types.

**Roles** — eight behavioral profiles you can switch mid-conversation:

| Say this | Claude prioritizes |
|---|---|
| `"as developer"` | Code only. No explanations unless asked. Git best practices. |
| `"as writer"` | Structured prose. Asks audience first. Active voice. |
| `"as student"` | Step-by-step explanations. Checks understanding. |
| `"as data"` | Tables over prose. Shows queries. Cites assumptions. |
| `"as pm"` | Range estimates. Decision logs. Risk tracking. |
| `"as designer"` | Component-first. Accessibility. Design tokens. |
| `"as devops"` | IaC. Docker. CI/CD. Least privilege. |
| `"as researcher"` | Citations. Methodology. Evidence-based claims. |

These are prompt configurations — the same thing you could write in your own CLAUDE.md, packaged for convenience.

**Slash commands** — four structured reasoning tools:

| Command | What it does |
|---|---|
| `/think [problem]` | Structured reasoning: clarify, inventory, hypotheses, stress-test, decide |
| `/challenge [decision]` | Adversarial stress-test: assumptions, failure modes, alternatives |
| `/refactor [file]` | Code quality sweep: complexity, duplication, naming, coupling, testability |
| `/audit [scope]` | Inconsistency sweep: naming, patterns, docs, interfaces |

---

## Before and after

<table>
<tr><th width="50%">Without Supercharger</th><th width="50%">With Supercharger</th></tr>
<tr><td>

**"Fix the typo in the header"**

"Fixed the typo. While I was at it, I also refactored the header component to use a more modern pattern, updated the styles to use Tailwind utility classes, and extracted the navigation into its own component for better reusability..."

*Nobody asked for that.*

</td><td>

**"Fix the typo in the header"**

Fixed `'Welcom'` → `'Welcome'` in `Header.tsx:12`. No other changes.

*Stays in scope.*

</td></tr>
<tr><td>

**"Add a login form"**

"Here's the login form I've created for your authentication system. It includes email and password fields, client-side validation, and error handling. It *should* work correctly with your existing setup."

*No tests run. No build check. "Should work."*

</td><td>

**"Add a login form"**

`LoginForm.tsx` added. `npm test` — 3/3 pass. Build clean. Handles empty fields, invalid email, server errors.

*Verified. Done.*

</td></tr>
</table>

More examples → [docs/examples.md](docs/examples.md)

---

## MCP servers

Pre-configured and auto-installed based on your roles. No API keys needed for the core set.

| Who gets it | Servers |
|---|---|
| Everyone | Context7 (live library docs), Sequential Thinking (structured reasoning), Memory (persistent across sessions) |
| Developer | + Playwright (browser automation), Magic UI (component library) |
| Designer | + Magic UI (component library) |
| Writer, Student, PM, Data, DevOps, Researcher | + DuckDuckGo Search |

Advanced servers (Brave, Notion, Sentry, Figma, Slack) available via `bash tools/mcp-setup.sh`.

---

## Session tools

**Status bar** — model, project, branch, stack, active agent, context usage (color-coded at 70%/90%), session cost, per-prompt token usage with in/out breakdown, cache hit rate. You see context pressure building before it becomes a problem.

**Transcript backup** — when context gets compressed, Supercharger saves the raw conversation transcript to disk. Claude is prompted to include a structured summary (decisions, files changed, next steps), but the hook captures the full transcript regardless. Run `bash tools/resume.sh` to view it and copy a resume prompt to your clipboard.

```bash
bash tools/resume.sh         # latest summary + copy resume prompt
bash tools/resume.sh --list  # browse past sessions
```

**Verification gate** — Claude must prove work is done:
1. File exists at expected path
2. Real code — not stubs or TODOs
3. Wired — imports resolve, route registered, component used
4. Tests pass, build succeeds

---

## Team features

**Audit trail** — every file edit, git commit, and package install is logged to `~/.claude/supercharger/audit/` as JSONL. Credentials auto-redacted. 30-day rotation.

**Webhooks** — get notified when Claude needs input or sessions complete:
```bash
bash tools/webhook-setup.sh  # Slack, Discord, Telegram, or custom HTTP
```

**Project config** — drop `.supercharger.json` in your repo root:
```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```
Commit it. Every team member gets the same behavior.

**Profiles** — bundle role + economy + MCP into named presets:
```bash
bash tools/profile-switch.sh frontend-dev     # Developer+Designer, Lean
bash tools/profile-switch.sh --save my-setup  # save current config
bash tools/export-preset.sh team.supercharger # share with teammates
```

**Health check:**
```bash
bash tools/claude-check.sh  # verify installation, list active features
```

**Agent scaffolding** for teams:
```bash
bash tools/init-agents.sh  # auto-detects stack, creates .claude/agents/
```

---

## Install modes

| Mode | What you get | Who it's for |
|---|---|---|
| **Safe** | Config files + safety hooks only | Trying it out, minimal footprint |
| **Standard** | + git-safety, quality gate, pkg enforcement, audit trail, notifications | Most users. *Recommended.* |
| **Full** | + prompt validation, compaction backup, session intelligence, statusline | Power users and teams |

---

## FAQ

<details>
<summary>Will this break my existing Claude setup?</summary>
No. Supercharger backs up your existing config before touching anything. Run <code>./uninstall.sh</code> to restore exactly what you had.
</details>

<details>
<summary>What if a hook blocks something I actually need?</summary>
<code>bash tools/hook-toggle.sh safety off</code> — re-enable with <code>on</code>. Or run the command directly in your terminal outside Claude Code.
</details>

<details>
<summary>I'm not a developer. Is this for me?</summary>
The safety hooks help everyone. The roles (writer, student, researcher) shape Claude's output for non-coding work. If your prompt doesn't match a specific agent, Claude works normally — just with the safety and economy rules active.
</details>

<details>
<summary>Does this work with my existing MCP servers?</summary>
Yes. Supercharger tags its own entries with <code>#supercharger</code>. Your servers are never touched.
</details>

<details>
<summary>How do I upgrade?</summary>
If installed via git clone: <code>bash tools/update.sh</code><br>
If installed via one-liner: <code>bash ~/.claude/supercharger/tools/update.sh</code><br>
Just check if an update is available: <code>bash ~/.claude/supercharger/tools/update.sh --check</code>
</details>

<details>
<summary>How do I switch roles or economy tier?</summary>
Mid-conversation: <code>"as developer"</code> / <code>eco lean</code><br>
Permanent: <code>./install.sh</code> or <code>bash tools/economy-switch.sh lean</code>
</details>

<details>
<summary>What about commit trailers? (Co-Authored-By)</summary>
Disabled automatically. Your commits, your name.
</details>

<details>
<summary>How do I disable desktop notifications?</summary>
To disable the desktop popup while keeping webhooks:
<pre>bash ~/.claude/supercharger/tools/notify-toggle.sh off</pre>
Re-enable with <code>on</code>. To disable all notifications: <code>bash tools/hook-toggle.sh notify off</code>.
</details>

<details>
<summary>What about Windows?</summary>
Use <a href="https://learn.microsoft.com/en-us/windows/wsl/install">WSL</a> or Git Bash. Install Python from <a href="https://python.org">python.org</a> if needed.
</details>

---

## Context cost

Supercharger loads ~3,700 tokens of config into each conversation (under 2% of any Claude model's context window). MCP server tool definitions are deferred by default in Claude Code 2.x — they load on first use, not at session start. You won't notice the overhead.

---

## Why I built this

Claude Code is powerful. It's also unsupervised. It has access to your files, your git history, your terminal — and no guardrails beyond its own judgment about what you "probably" wanted.

I got tired of Claude rewriting files I asked it to leave alone. Deleting things I didn't ask it to delete. Running commands I wouldn't have approved. The usual advice is "write better prompts." But prompts are suggestions. Claude is good at finding reasons to go beyond suggestions.

So I moved the enforcement outside Claude's reach. Shell hooks that run before the command executes. Not a prompt it can reconsider — a wall it can't pass through.

The rest came later. Once I had safety, I added the workflow features I wished Claude had out of the box: focused agents, concise output, structured reasoning, session memory. They're useful. But the safety layer is what I'd install even if nothing else existed.

Zero dependencies for core install — shell scripts and config files only. MCP servers (optional) use npx at runtime. MIT licensed. Backs up your config. Uninstall reverses everything.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS and Claude Code)
- **Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for hook authoring, testing conventions, and the Python-in-Bash guidelines.

---

## Credits

Built on patterns from:

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, autonomy levels
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) — statusline, pkg enforcement, audit trail
- [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook) — quality gate pipeline
- [prompt-master](https://github.com/nidhinjs/prompt-master) — deep interview, verification gate
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) — keyword switching
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — verification gate patterns
- [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — safety hook patterns
- [claude-code-tips](https://github.com/ykdojo/claude-code-tips) — statusline context bar

## License

MIT — see [LICENSE](LICENSE)
