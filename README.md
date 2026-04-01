# Claude Supercharger

**Make Claude Code actually work the way you expect.**

A role-aware, zero-dependency configuration kit that transforms Claude Code from a talented but undisciplined assistant into a focused, safe, and efficient one — tailored to how *you* work.

![Version](https://img.shields.io/badge/version-1.4.0-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey) ![Tests](https://img.shields.io/badge/tests-133%20passing-brightgreen)

---

## Why?

Out of the box, Claude Code:

- Claims tasks are **"done" without running tests** or verifying output
- **Refactors code you didn't ask it to touch** (the "while I was here..." problem)
- **Runs destructive commands** (`rm -rf`, `git push --force`) without hesitation
- Gives the **same verbose response** whether you're a senior dev or a student learning CSS
- **Wastes tokens** on preambles, caveats, and paragraphs where one line would do
- **Loses all context** when a session ends, rate limits, or compacts

Supercharger fixes all of this. One install, zero config, instant improvement.

---

## See the Difference

<table>
<tr><td width="50%">

### Without Supercharger

**You:** "Add a login form"

**Claude:** "Here's the login form I've created. It should work correctly with your authentication system."

*(No tests run. No verification. "Should work.")*

</td><td width="50%">

### With Supercharger

**You:** "Add a login form"

**Claude:** "Login form added to `src/components/LoginForm.tsx`. Ran `npm test` — 3/3 pass. Ran `npm run build` — clean. Handles empty fields, invalid email, server errors. Try: `npm run dev` → `/login`."

*(Verified. Specific. Actionable.)*

</td></tr>
<tr><td>

**You:** "Did the tests pass?"

**Claude:** "I ran the test suite and I'm happy to report that all tests passed successfully. The test runner executed 57 test cases across 4 test files, and each one completed without any errors. This means our changes are working correctly..."

*(73 words for a yes/no question)*

</td><td>

**You:** "Did the tests pass?"

**Claude:** "Yes. 57 passed, 0 failed."

*(7 words. Same information.)*

</td></tr>
<tr><td>

**You:** "Fix the typo in the header"

**Claude:** "Fixed the typo. While I was there, I also refactored the header to use a modern pattern, updated the CSS to Tailwind, and extracted the nav..."

*(Scope creep. Unrequested changes.)*

</td><td>

**You:** "Fix the typo in the header"

**Claude:** "Fixed 'Welcom' → 'Welcome' in `Header.tsx:12`. No other changes. (Nav links could use `aria-label` — want me to add those?)"

*(Surgical. Observes but doesn't act.)*

</td></tr>
</table>

[More examples →](docs/examples.md)

---

## Quick Install

```bash
git clone https://github.com/smrafiz/claude-supercharger.git && cd claude-supercharger && ./install.sh
```

<details>
<summary>Other install methods</summary>

**One-liner** (clones to temp dir, installs, cleans up):
```bash
bash -c 'TMP=$(mktemp -d) && git clone https://github.com/smrafiz/claude-supercharger.git "$TMP/cs" && "$TMP/cs/install.sh" && rm -rf "$TMP"'
```

**Non-interactive** (CI/scripted):
```bash
./install.sh --mode standard --roles developer,pm --economy lean --config deploy --settings deploy
```
</details>

The installer walks you through 4 steps: install mode → roles → economy tier → config handling. Takes about 30 seconds.

---

## Features at a Glance

| Feature | What it does | How |
|---------|-------------|-----|
| **Safety Hooks** | Blocks `rm -rf /`, `DROP TABLE`, `chmod 777`, force-push, credential leaks, SSH key ops, self-modification | Deterministic — runs on every command |
| **Verification Gate** | 4-level check: Exists → Substantive → Wired → Functional. Catches stubs and placeholders. | Rules in supercharger.md |
| **Quality Gate** | 3-stage lint→auto-fix→re-check pipeline after every edit (ruff, eslint, clippy, rustfmt, gofmt) | PostToolUse hook |
| **Scope Discipline** | Prevents unrequested refactoring and drive-by changes | Rules + guardrails |
| **Token Economy** | 30-60% output reduction in 3 tiers (Standard/Lean/Minimal) | Per-output-type rules |
| **8 Roles** | Developer, Writer, Student, Data, PM, Designer, DevOps, Researcher — each with tuned behavior | Auto-loaded from `~/.claude/rules/` |
| **MCP Servers** | 3-5 zero-config MCP servers auto-configured per role | `settings.json` integration |
| **Clarification Mode** | Scans prompts for vague/ambiguous requests, asks before acting | Lightweight (auto) + Deep Interview (9 dims) |
| **Session Summary** | Structured handoff with Memory Block and paste-ready resume prompt | Keyword, compaction, rate limit triggers |
| **Resume Tool** | Retrieve and clipboard-copy past session summaries | `bash tools/resume.sh` |
| **Anti-Patterns** | 35-pattern library catches common prompt mistakes | Auto-loaded YAML + hook |
| **Prompt Validator** | 20 checks: vague scope, missing format, no constraints, no error context, and more | UserPromptSubmit hook |
| **Pkg Manager Enforce** | Blocks `npm` in pnpm projects, `pip` in uv projects — auto-detects from lockfiles | PreToolUse hook |
| **Audit Trail** | JSONL log of all mutations (file edits, git commits, installs) — 30-day rotation | PostToolUse hook |
| **Hook Toggle** | `bash tools/hook-toggle.sh safety off` — snooze any hook without editing JSON | CLI tool |
| **Stop Conditions** | Start/target state, checkpoints, forbidden actions, human review triggers | Rules in guardrails.md |
| **Guardrails** | Four Laws, autonomy levels, halt conditions | Always active |
| **Mode Switching** | Switch roles mid-conversation: "as developer", "as designer" | All 8 roles always available |
| **Enhanced Statusline** | 2-line status bar: model, project, git branch, context %, cost, cache hit rate | `statusLine` in settings.json |
| **Stack Auto-Detection** | Detects language, framework, package manager, test framework from project files | Python, JS/TS, Rust, Go |
| **Config Validation** | Lints rule files, checks hooks are executable, validates settings.json | `claude-check` |

---

## Roles

| Role | Optimized for | Key behaviors |
|------|--------------|---------------|
| **Developer** | Engineers & coders | Code-only output, git safety, auto-format, stack detection, regression prevention |
| **Writer** | Content creators & authors | Structured prose, asks about audience/tone first, draft workflow, no jargon |
| **Student** | Learners at any level | Explains concepts before code, analogies, checks understanding, progressive complexity |
| **Data** | Analysts & data scientists | Tables over prose, shows queries, cites assumptions, statistical rigor |
| **PM** | Project managers | Range estimates (not single numbers), decision logs, risk tracking, bullet-only |
| **Designer** | UI/UX designers | Component-first, accessibility, design tokens, visual hierarchy, interactive states |
| **DevOps** | Infrastructure & ops | IaC, Docker best practices, CI/CD pipelines, security scanning, least privilege |
| **Researcher** | Academics & investigators | Citations, methodology, evidence-based claims, literature review, reproducibility |

Select one or more during install. Switch mid-conversation:

```
"as developer" → code-only mode
"as designer"  → design mode
"as devops"    → infrastructure mode
"as student"   → teaching mode
```

---

## Token Economy

Three tiers of output compression — selectable at install, switchable mid-conversation:

| Tier | Reduction | What it looks like |
|------|-----------|-------------------|
| **Standard** | ~30% | Concise, natural English. Complete sentences. Good for learning. |
| **Lean** | ~45% | Every word earns its place. Fragments OK. *Default.* |
| **Minimal** | ~60% | Telegraphic. Bare deliverables only. Maximum efficiency. |

Each tier defines rules for 5 output types: **Code**, **Commands**, **Explanation**, **Diagnosis**, **Coordination**.

**Role-aware constraints** prevent bad combinations:
- Student floors at Standard (explanations need room)
- Writer floors at Standard (prose needs sentences)
- Developer/Data/PM are unrestricted

Switch anytime: `eco standard`, `eco lean`, or `eco minimal`

Switch permanently: `bash tools/economy-switch.sh [standard|lean|minimal]`

---

## Session Intelligence

### Clarification Mode

**Lightweight** (always on): Every prompt is scanned for vague verbs, missing scope, and unclear success criteria. Max 3 questions, then Claude proceeds.

**Deep Interview** (say `"deep interview"` or `"interview me"`): Claude scores your prompt across 9 dimensions and asks targeted questions for the weakest areas:

| Critical (always) | Conditional (complex tasks) |
|-------------------|---------------------------|
| **Scope** — files/functions? | **Input** — what data starts it? |
| **Success** — what's "done"? | **Output** — format/deliverable? |
| **Constraints** — don't touch? | **Audience** — who uses this? |
| **Context** — what exists? | **Memory** — prior decisions? |
| | **Examples** — reference patterns? |

Score 9-12 → proceed. Score 5-8 → one question. Score 0-4 → full interview before executing.

### Session Summary & Resume

Say **`"session summary"`** and Claude generates a structured handoff:

```
## Session Summary — 2026-04-01
Working on: Auth migration for user-service
Decisions made:
- Using refresh token rotation, 15min access token TTL
Files changed: src/auth/middleware.ts, src/auth/tokens.ts
What failed: bcrypt 5.x had a breaking change, reverted to 4.x
Next steps: Session migration script, OAuth callback updates
Resume with: Continue the auth migration. Middleware and token
  generation are done (8/8 tests passing). Next: write the session
  migration script in src/auth/migrate-sessions.ts.
```

Also auto-generates on **context compaction** and **rate limits** — so you never lose progress.

Resume a previous session:
```bash
bash tools/resume.sh           # show latest, copy resume prompt to clipboard
bash tools/resume.sh --list    # list all saved summaries
bash tools/resume.sh --show FILE  # view a specific summary
```

---

## Safety & Hooks

| Hook | Modes | What it does |
|------|-------|-------------|
| **safety** | All | Blocks `rm -rf /`, `DROP TABLE`, `chmod 777`, `mkfs`, fork bombs, `curl \| bash`, credential leaks, SSH key ops, shell profile writes, self-modification |
| **git-safety** | Standard+ | Blocks force-push to main/master, `git reset --hard`, `git checkout .`, `git clean -f` |
| **enforce-pkg-manager** | Standard+ | Blocks `npm` in pnpm/yarn/bun projects, `pip` in uv/poetry projects — auto-detects from lockfiles |
| **quality-gate** | Standard+ | *(Doesn't block — 3-stage lint→auto-fix→re-check pipeline: ruff, eslint, clippy, rustfmt, gofmt)* |
| **audit-trail** | Standard+ | *(Doesn't block — JSONL log of all mutations: file edits, git commits, installs. 30-day rotation)* |
| **notify** | Standard+ | *(Doesn't block — desktop notification when Claude needs input)* |
| **prompt-validator** | Full | Scans your prompts for 20 anti-patterns, suggests improvements |
| **compaction-backup** | Full | Saves transcript + prepares summaries directory before compaction |

Safety hooks are **deterministic** — they execute on every command, every time. Claude can't talk its way past them.

Multi-layer bypass protection: `sudo rm -rf /`, `command rm -rf /`, `env sudo command rm -rf /` — all blocked.

Toggle any hook without editing JSON: `bash tools/hook-toggle.sh safety off`

---

## MCP Servers

Auto-configured during install. Zero API keys, zero JSON editing.

| Tier | Servers | Who gets them |
|------|---------|--------------|
| **Core** | Context7, Sequential Thinking, Memory | Everyone |
| **Developer** | + Playwright, Magic UI | Developer role |
| **Non-dev** | + DuckDuckGo Search | Writer, Student, Data, PM |
| **Advanced** | GitHub, Brave, Slack, Notion, Sentry, + more | `bash tools/mcp-setup.sh` (API keys needed) |

3-5 servers per role. Research shows 3 is the sweet spot; beyond 5, token overhead hurts performance.

---

## Install Modes

| Mode | What's included |
|------|----------------|
| **Safe** | Configs + safety hooks. Nothing that auto-runs or notifies. |
| **Standard** | + notifications, git-safety, quality gate, pkg-manager enforcement, audit trail. Recommended for most users. |
| **Full** | + prompt validation, compaction backup, diagnostics. Everything. |

---

## How It Works

Deploys to `~/.claude/` using Claude Code's native config system:

```
~/.claude/
  CLAUDE.md                  # Universal config (merged with yours if exists)
  rules/
    supercharger.md          # Execution workflow, clarification mode, session summary
    guardrails.md            # Four Laws, autonomy levels, halt conditions
    economy.md               # Token economy (universal rules + active tier)
    developer.md             # Your selected role(s)
    anti-patterns.yml        # 35 prompt anti-pattern library
  supercharger/
    hooks/                   # Hook scripts referenced by settings.json
    roles/                   # All role files (for mid-conversation switching)
    economy/                 # Tier templates (for economy switching)
    summaries/               # Session summaries (created by compaction hook)
    audit/                   # Mutation audit trail (JSONL, 30-day rotation)
  settings.json              # Hooks + MCP servers registered here
```

- Files in `~/.claude/rules/` are **automatically loaded** by Claude Code
- Hooks execute **deterministically** on every tool use
- MCP servers are configured in `settings.json` with `#supercharger` tags for clean management
- Everything is **idempotent** — run the installer again anytime

---

## Your Existing Config

| Scenario | What happens |
|----------|-------------|
| No existing config | Supercharger's deployed directly |
| **Merge** | Your content preserved, Supercharger appended below a marker |
| **Replace** | Your file backed up first, then Supercharger's deployed |
| **Skip** | Your file untouched, everything else installed |

A timestamped backup is **always** created before any changes.

---

## Tools

| Tool | Command | What it does |
|------|---------|-------------|
| **Health Check** | `bash tools/claude-check.sh` | Verify installation, show active roles/hooks/MCP/summaries |
| **Economy Switch** | `bash tools/economy-switch.sh lean` | Permanently change token economy tier |
| **MCP Setup** | `bash tools/mcp-setup.sh` | Add advanced MCP servers (GitHub, Brave, Slack, etc.) |
| **Resume** | `bash tools/resume.sh` | Show latest session summary, copy resume prompt |
| **Hook Toggle** | `bash tools/hook-toggle.sh safety off` | Enable/disable any hook without editing JSON |

---

## Uninstall

```bash
./uninstall.sh
```

Removes all Supercharger content. Preserves your configs. Offers backup restore. Clean exit.

---

## FAQ

<details>
<summary><strong>Will this break my existing setup?</strong></summary>

No. Everything is backed up before any changes. Uninstall restores everything. Supercharger content is tagged with markers so it never touches your own config.
</details>

<details>
<summary><strong>How do I change roles after install?</strong></summary>

Run `./install.sh` again — it's idempotent. Or switch mid-conversation by saying "as developer", "as student", etc.
</details>

<details>
<summary><strong>How do I upgrade?</strong></summary>

```bash
git pull && ./install.sh
```
</details>

<details>
<summary><strong>How do I change the token economy tier?</strong></summary>

Mid-conversation: say `eco lean`, `eco standard`, or `eco minimal`.

Permanent: `bash tools/economy-switch.sh lean`
</details>

<details>
<summary><strong>What if a hook blocks something I need?</strong></summary>

Toggle it off: `bash tools/hook-toggle.sh safety off` — re-enable with `on`. Or run the command directly in your terminal (outside Claude Code). Supercharger hooks are tagged with `#supercharger` in `settings.json` so they're easy to identify.
</details>

<details>
<summary><strong>Does this work with my existing MCP servers?</strong></summary>

Yes. Supercharger MCP entries are tagged with `#supercharger`. Your own servers are never touched during install or uninstall.
</details>

<details>
<summary><strong>How do I resume a session after a rate limit?</strong></summary>

Supercharger rules tell Claude to generate a session summary before stopping. Run `bash tools/resume.sh` to retrieve it and copy the resume prompt to your clipboard. Paste it into your next session.
</details>

---

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Anthropic's CLI)
- Bash 3.2+ (macOS or Linux)
- Python 3 (for JSON operations — ships with Claude Code)
- **Windows:** Use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) (recommended) or Git Bash

---

## Credits

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow patterns, anti-patterns library
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, halt conditions, autonomy levels
- [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (MIT) — magic keyword switching, clarification mode, session handoff patterns
- [prompt-master](https://github.com/nidhinjs/prompt-master) — deep interview dimensions, verification gate patterns
- [Trail of Bits claude-code-config](https://github.com/trailofbits/claude-code-config) — package manager enforcement, audit trail patterns
- [claude-code-quality-hook](https://github.com/dhofheinz/claude-code-quality-hook) — three-stage lint/fix quality gate pipeline
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — verification gate patterns
- [claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — safety hook patterns informed by Claude Code's internal security monitor rules

## License

MIT — see [LICENSE](LICENSE)
