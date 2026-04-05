# Claude Supercharger

I built this because Claude kept doing things I didn't ask for.

A developer says "fix the typo" — Claude rewrites the whole component. A writer asks for a short paragraph — Claude delivers five. A PM asks for a quick estimate — Claude writes a project plan nobody requested. And sometimes it goes further: deleting files, overwriting work, running commands that can't be undone.

The problem isn't that Claude is bad. It's that Claude is eager. And there's no way to say "stay in your lane" that it can't find a reason to ignore.

**Supercharger fixes this.** Safety guardrails run at the shell level — outside Claude's conversation, before commands execute. Not a prompt Claude can argue with. An actual wall.

But safety was just the start. Once I had that working, I kept going: agents that stay in scope, token economy that cuts your costs in half, slash commands that think harder than you'd expect, roles that adapt to how you work, MCP servers that just work out of the box, session memory that survives context limits, and team configs that keep everyone consistent.

![Version](https://img.shields.io/badge/version-1.7.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-227%20passing-brightgreen)

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

30 seconds. Four questions. Done. `./uninstall.sh` reverses everything.

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

## What happens after you install

No config files to edit. No prompts to write. No learning curve.

**First session** — Claude introduces itself:
> *"Supercharger is active. Guardrails on — I won't make destructive changes without asking. I verify before claiming done. Responses are lean by default."*

**Every session** — Claude already knows your project. Supercharger detects your stack (React, Python, Rust, whatever) and tells Claude before you type a word. You see it in the status bar: `[sonnet] my-project | master | TypeScript, React`

**Every task** — the right agent activates automatically. You don't pick. Claude does.

---

## Before and after

This is the difference I was tired of:

<table>
<tr><th width="50%">Without Supercharger</th><th width="50%">With Supercharger</th></tr>
<tr><td>

**"Add a login form"**

"Here's the login form I've created for your authentication system. It includes email and password fields, client-side validation, and error handling. It *should* work correctly with your existing setup. Let me know if you need any changes!"

*No tests run. No build check. "Should work."*

</td><td>

**"Add a login form"**

`LoginForm.tsx` added. `npm test` — 3/3 pass. Build clean. Handles empty fields, invalid email, server errors.

*Verified. Specific. Done.*

</td></tr>
<tr><td>

**"Fix the typo in the header"**

"Fixed the typo. While I was at it, I also refactored the header component to use a more modern pattern, updated the styles to use Tailwind utility classes, and extracted the navigation into its own component for better reusability..."

*Nobody asked for that.*

</td><td>

**"Fix the typo in the header"**

Fixed `'Welcom'` → `'Welcome'` in `Header.tsx:12`. No other changes.

*Surgical. Stays in scope.*

</td></tr>
<tr><td>

**"Help me write a product description"**

"Certainly! Here is a comprehensive product description you can use. It covers the key features, benefits, target audience, and unique selling points. I've written it in a professional tone with multiple paragraphs..."

*Unprompted length, unknown audience, no iteration.*

</td><td>

**"Help me write a product description"**

Who's the audience and what's the tone? (casual / professional / technical)

*Asks first. Gets it right once.*

</td></tr>
</table>

More examples → [docs/examples.md](docs/examples.md)

---

## Eight things that change

### 1. Guardrails that can't be argued with

This is the core of Supercharger. Everything else is built on top of it.

Most Claude behavior guides are prompts. Claude can be talked out of prompts. Supercharger's guardrails are shell hooks — they run outside Claude's conversation, before the command executes. Exit code 0 or 2. No negotiation.

| What gets blocked | Why |
|---|---|
| `rm -rf /`, `DROP TABLE`, `chmod 777`, fork bombs | Irreversible destruction |
| `git push --force` to main/master | Overwrites shared history |
| `curl \| bash`, `eval`, credential patterns | Security |
| `git reset --hard`, `git checkout .` | Loses uncommitted work |
| Wrong package manager (`npm` in a pnpm project) | Corrupts lockfile |
| Writing to `.bashrc`, `.zshrc`, SSH keys | Unauthorized persistence |

Plus: a 3-stage quality gate runs lint → auto-fix → re-check after every file edit. A prompt validator catches 20 anti-patterns before they waste a turn. An audit trail logs every mutation to JSONL with 30-day rotation.

When something's blocked, Claude gets a plain-English reason — not a shell error.

### 2. Token economy — same results, less money

Claude is verbose by default. Supercharger ships three output tiers:

| Tier | What changes | Reduction |
|---|---|---|
| **Standard** | Complete sentences. Good for learning. | ~30% |
| **Lean** *(default)* | Every word earns its place. Fragments OK. | ~45% |
| **Minimal** | Telegraphic. Bare output only. | ~60% |

Switch mid-conversation: `eco lean` / `eco standard` / `eco minimal`

Role constraints apply — Student can't go below Standard because explanations need breathing room. Developer defaults to Lean because you're reading code, not prose.

The savings add up. If you use Claude Code daily, this pays for itself in the first week.

### 3. Nine agents. Zero selection required.

You don't pick an agent. You talk naturally, and the right one activates:

```
"There's a null pointer at line 42"           → Sherlock Holmes (debugger)
"Review this file for security issues"        → Gordon Ramsay (reviewer)
"Add a login form to this page"               → Tony Stark (code-helper)
"Write a README for this project"             → Ernest Hemingway (writer)
"Should I use REST or GraphQL here?"          → Sun Tzu (planner)
"Compare Redis vs Memcached for our use case" → Marie Curie (researcher)
"Analyze this CSV and show me the top sellers"→ Albert Einstein (data-analyst)
"How does this codebase work?"                → Steve Jobs (general)
"Design the auth system before we build it"   → Leonardo da Vinci (architect)
```

Each agent has scope rules, numbered safety-first rules (Rule 0 is always production safety), escalation blocks, and a verification gate.

Sherlock won't guess — he reads the actual error, traces the call chain, and only forms a hypothesis after gathering evidence. Ramsay uses severity tiers: MUST FIX (security) → SHOULD FIX (conformance) → CONSIDER (quality). Hemingway asks about your audience before writing a single word.

**For teams:** scaffold a project-specific agent team with one command:
```bash
bash tools/init-agents.sh  # auto-detects stack, creates .claude/agents/
```

### 4. Four commands that think harder than you do

Type these in any session, any project:

| Command | What it does |
|---|---|
| `/think [problem]` | Structured reasoning: clarify → inventory → hypotheses → stress-test → decide |
| `/challenge [decision]` | Adversarial stress-test: assumptions, failure modes, strongest alternative, verdict |
| `/refactor [file]` | Code quality sweep across 7 dimensions — complexity, duplication, naming, coupling, testability, error handling, dead code |
| `/audit [scope]` | Inconsistency sweep: naming, patterns, docs, interfaces, structure |

I use `/challenge` before every architecture decision now. It's caught blind spots I wouldn't have found in review.

### 5. Eight roles — one tool, every perspective

Roles change how Claude thinks, not just what it says:

| Say this | Claude becomes |
|---|---|
| `"as developer"` | Code only. No explanations unless asked. Git best practices. |
| `"as writer"` | Structured prose. Asks audience first. No filler. Active voice. |
| `"as student"` | Step-by-step. Checks understanding. Builds gradually. |
| `"as data"` | Tables over prose. Shows queries. Cites assumptions. |
| `"as pm"` | Range estimates. Decision logs. Risk tracking. |
| `"as designer"` | Component-first. Accessibility. Design tokens. |
| `"as devops"` | IaC. Docker. CI/CD. Least privilege. |
| `"as researcher"` | Citations. Methodology. Evidence-based claims. |

Switch mid-conversation, as many times as you want. "Build this API `as developer`, then `as pm` estimate the remaining work, then `as writer` draft the release notes."

### 6. MCP servers — pro tools, zero setup

These are pre-configured and auto-installed based on your roles. No API keys for the core set.

| Who gets it | Servers |
|---|---|
| Everyone | Context7 (live library docs), Sequential Thinking (structured reasoning), Memory (persistent across sessions) |
| Developer, Designer | + Playwright (browser automation), Magic UI (component library) |
| Writer, Student, PM, Researcher | + DuckDuckGo Search |

```
"Look up the React useEffect docs"        → live docs via Context7
"Test the login page in a real browser"    → Playwright automation
"Remember that we use pnpm in this repo"   → Memory across sessions
```

Advanced servers (Brave, Notion, Sentry, Figma, Slack) available via `bash tools/mcp-setup.sh`.

### 7. Session intelligence — never lose context

Long sessions hit context limits. Rate limits interrupt your flow. Supercharger handles both:

**Status bar** shows what matters in real time: model, project, branch, stack, context usage (color-coded), session cost, cache hit rate. You see context pressure building before it becomes a problem.

**Auto-save on compaction** — when context gets compressed, Supercharger saves a structured summary: decisions made, files changed, what failed, what to do next. A paste-ready resume prompt gets copied to your clipboard.

**Session resume:**
```bash
bash tools/resume.sh         # latest summary + copy resume prompt
bash tools/resume.sh --list  # browse past sessions
```

**Verification gate** — Claude has to prove it's done:
1. File exists at expected path
2. Real code — not stubs or TODOs
3. Wired — imports resolve, route registered, component used
4. Tests pass, build succeeds

No more "should work." Evidence or it didn't happen.

### 8. Team & compliance — share configs, track everything

For teams and organizations that need consistency and accountability:

**Audit trail** — every file edit, git commit, and package install is logged to `~/.claude/supercharger/audit/` as JSONL. Credentials auto-redacted. 30-day rotation. This is how you answer "what did the AI change and when."

**Webhooks** — get notified when Claude needs input or sessions complete:
```bash
bash tools/webhook-setup.sh  # Slack, Discord, Telegram, or custom HTTP
```

**Project config** — drop `.supercharger.json` in your repo root:
```json
{"roles": ["developer", "designer"], "economy": "lean", "hints": "React + Tailwind, use pnpm"}
```
Every team member gets the same behavior. Commit it to your repo.

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

---

## Works for everyone

You don't need to be a developer. Supercharger improves Claude for any kind of work.

| You do | What changes |
|---|---|
| **Write** (blogs, docs, emails) | Writer agent activates. Asks about audience first. Short paragraphs, active voice, no filler. |
| **Research** (compare, summarize, explain) | Researcher agent activates. Leads with the answer, tables over prose, states what it doesn't know. |
| **Plan** (projects, decisions, approaches) | Planner agent activates. Numbered steps, flags the riskiest part, recommends the simplest path. |
| **Code** (build, debug, review) | Code agent + full guardrails. Stack auto-detected. Nothing deleted without asking. |
| **Analyze data** (CSV, SQL, metrics) | Data-analyst agent activates. Shows queries, interprets results, flags data quality issues. |
| **Anything else** | General agent. Plain language. No jargon. Asks one question if something's unclear. |

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
<summary>I'm not a developer. Is this for me?</summary>
Yes. Install it, choose "general" as your role, and Claude just behaves better — clearer answers, stays focused, asks before doing something you didn't request. You don't need to know what hooks or MCP servers are.
</details>

<details>
<summary>What if a hook blocks something I actually need?</summary>
<code>bash tools/hook-toggle.sh safety off</code> — re-enable with <code>on</code>. Or run the command directly in your terminal.
</details>

<details>
<summary>How do I disable desktop notifications?</summary>
To disable the desktop popup (macOS/Linux) while keeping webhook notifications:
<pre>bash ~/.claude/supercharger/tools/notify-toggle.sh off</pre>
Re-enable with <code>on</code>, check status with <code>status</code>. Or if you have the repo locally: <code>bash tools/notify-toggle.sh off</code>.<br>
To disable notifications entirely (including webhooks):
<pre>bash ~/.claude/supercharger/tools/hook-toggle.sh notify off</pre>
</details>

<details>
<summary>Does this work with my existing MCP servers?</summary>
Yes. Supercharger tags its own entries with <code>#supercharger</code>. Your servers are never touched.
</details>

<details>
<summary>How do I upgrade?</summary>
<code>git pull && ./install.sh</code>
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
<summary>What about Windows?</summary>
Use <a href="https://learn.microsoft.com/en-us/windows/wsl/install">WSL</a> or Git Bash. Install Python from <a href="https://python.org">python.org</a> if needed.
</details>

---

## Why I built this

I wanted Claude to do what I asked. Not what it interpreted. Not what seemed impressive. What I actually requested.

Every person who uses Claude Code has a version of the same story. The developer whose files got deleted. The writer who got four paragraphs when they asked for one. The PM who asked a simple question and got an essay. Claude is helpful — sometimes too helpful, in ways you didn't want.

I stopped trying to fix this with better prompts. Prompts are suggestions. Claude is good at finding reasons to ignore suggestions. So I moved the enforcement to where Claude can't reach it — shell hooks that run before the command executes. And then I built everything else I wished Claude did out of the box.

Supercharger is open source, MIT licensed, and zero-dependency — shell scripts and config files only. No npm packages, no pip installs. It backs up your existing config and `./uninstall.sh` reverses everything.

If Claude has ever ignored your instructions, gone way beyond what you asked, or given you a wall of text when you wanted a sentence — this is what I built to fix that.

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Bash 3.2+ (macOS or Linux)
- Python 3 (ships with macOS and Claude Code)
- **Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) or Git Bash. Install Python from [python.org](https://python.org) if needed.

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
