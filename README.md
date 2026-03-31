# Claude Supercharger

A role-aware, zero-dependency configuration kit for Claude Code. Drop it in, things get better.

### Quick Install

Run this in your terminal to install Claude Supercharger:

```bash
curl -fsSL https://raw.githubusercontent.com/smrafiz/claude-supercharger/main/install.sh | bash
```

The interactive installer will guide you through mode selection, role setup, and config handling. See [Manual Install](#manual-install) if you prefer to review before running.

---

## Why this exists

Claude Code is powerful out of the box. But out of the box, it also:

- Claims tasks are "done" without running tests or verifying output
- Refactors code you didn't ask it to touch
- Runs destructive commands (`rm -rf`, `git push --force`) without hesitation
- Gives the same response style whether you're a senior developer or a student
- Halluccinates library names, function signatures, and CLI flags
- Loses context in long sessions and forgets what was decided
- Adds ceremonial text ("I'll now proceed to...") that wastes your time

Every Claude Code configuration project tries to fix these problems. Most of them are built for developers only, require npm/pip/docker to install, ship 500+ lines of rules that Claude ignores 20% of the time, and feel overwhelming on first use.

Claude Supercharger takes a different approach.

---

## What makes it different

**It asks who you are.** Not everyone using Claude Code is a developer. Writers, students, data analysts, project managers — they all use Claude Code differently. Supercharger configures Claude for your specific workflow, not a generic "coding assistant" profile.

**Hooks enforce, rules advise.** Research shows CLAUDE.md rules are followed ~80% of the time. Hooks are followed 100% of the time. Supercharger uses hooks for safety-critical behavior (blocking `rm -rf`, preventing force-push to main) and rules for behavioral guidance (output style, workflow patterns). The right enforcement at the right layer.

**It's not a framework.** No package manager. No build step. No runtime dependencies. Just a shell script that copies markdown files and configures hooks. Install takes under 10 seconds. Uninstall restores your original config completely.

**It respects what you already have.** Existing CLAUDE.md? The installer offers to merge, replace, or skip — your config is never overwritten without consent. A timestamped backup is always created first.

---

## What you get

### For everyone (all roles)

- **Safety hooks** — destructive commands like `rm -rf`, `DROP TABLE`, `chmod 777` are blocked before execution. Not advised against. Blocked.
- **Verification gates** — Claude must provide evidence before claiming work is done. No more "should work" or "looks correct" without actually checking.
- **Anti-pattern detection** — 35 common prompt patterns that waste tokens and produce poor results, caught and fixed automatically.
- **Four Laws** — Read before editing. Stay in scope. Verify before committing. Halt when uncertain. Simple rules that prevent the most common Claude mistakes.
- **Autonomy levels** — Low-risk work proceeds without asking. Medium-risk states intent first. High-risk stops and confirms. Claude makes fewer unnecessary interruptions while still checking on things that matter.
- **Structured escalation** — when Claude is stuck, it reports what it tried, what's blocking it, and what it recommends. No more vague "I'm not sure" responses.
- **Context management** — proactive compaction suggestions at 60% context usage, with key decisions preserved across compaction.

### For developers

- **Git safety hooks** — force-push to main/master, `git reset --hard`, `git checkout .` are blocked. Your work is protected.
- **Auto-format** — Prettier, Black, rustfmt, gofmt run automatically after Claude edits a file. Detects your project's formatter.
- **Stack detection** — reads package.json, Cargo.toml, pyproject.toml to understand your toolchain. Won't suggest npm if you use pnpm.
- **Regression prevention** — checks recent git history before modifying files, avoids reintroducing patterns that were explicitly removed.
- **Scope discipline** — only changes what was requested. If Claude notices something else worth improving, it mentions it without touching the code.

### For writers

- **Clarity-first output** — no technical jargon unless requested. Headers, bullets, and structured prose.
- **Draft workflow** — outlines before long-form content, version tracking (v1, v2), 2-3 alternatives for key phrases.
- **Source citation** — flags when claims are uncertain rather than fabricating sources.

### For students

- **Teach, don't do** — explains concepts before showing solutions. Uses analogies. Builds complexity gradually.
- **Guided learning** — encourages the student to try first, offers simpler alternatives before advanced patterns, suggests what to learn next.
- **Understanding checks** — asks "Does this make sense?" instead of steamrolling through explanations.

### For data analysts

- **Analysis rigor** — states assumptions, cites sources, distinguishes correlation from causation.
- **Reproducibility** — includes the query/code that produced every result. Tables for comparisons, not prose.
- **Data validation** — flags missing values, outliers, and anomalies. Never silently drops data.

### For project managers

- **Range estimates** — optimistic/likely/pessimistic, never single numbers.
- **Decision logs** — options considered, decision made, rationale documented.
- **Risk management** — flags risks with likelihood and impact, proposes mitigations rather than just warnings.

---

## Install modes

Choose your comfort level during installation:

| Mode | Features | Best for |
|------|----------|----------|
| **Safe** | 7 | Cautious users, corporate environments. Configs + safety hook only. |
| **Standard** | 10 | Most users. Configs + productivity hooks. Recommended. |
| **Full** | 15 | Power users. Everything + MCP setup + diagnostics. |

Every mode includes the universal configs, role overlays, anti-patterns library, and clean uninstaller. They differ in which hooks are activated.

---

## Roles

Select one or more during installation. Combine any roles freely.

| Role | Who it's for | What changes |
|------|-------------|--------------|
| **Developer** | Engineers, full-stack, backend, frontend | Code-only output, git safety, auto-format, TDD workflow, stack detection |
| **Writer** | Content creators, marketers, copywriters | Structured prose, draft versioning, no jargon, source citation |
| **Student** | Learners, bootcamp students, career changers | Explanations first, progressive complexity, guided learning |
| **Data** | Analysts, data scientists, researchers | Analysis rigor, reproducibility, data validation, visualization |
| **PM** | Project managers, product owners, team leads | Range estimates, decision logs, stakeholder summaries, risk tracking |

---

## Hooks

Safety and productivity enforcement that can't be ignored.

| Hook | Modes | What it does |
|------|-------|-------------|
| **safety** | All | Blocks `rm -rf`, `DROP TABLE`, `chmod 777`, `curl\|bash`, and 11 other destructive patterns |
| **notify** | Standard, Full | Sends desktop notification (macOS/Linux) when Claude needs your input |
| **git-safety** | Standard, Full | Blocks `git push --force` to main/master, `git reset --hard`, `git checkout .`, `git clean -f` |
| **auto-format** | Standard, Full | Runs Prettier/Black/rustfmt/gofmt after edits. Developer role only. |
| **prompt-validator** | Full | Scans your prompt for vague scope, multiple tasks, missing success criteria. Suggests improvements, never blocks. |
| **compaction-backup** | Full | Saves conversation transcript before context compaction. Never lose session history. |

---

## How it works

Supercharger deploys to `~/.claude/` using Claude Code's native configuration system:

```
~/.claude/
  CLAUDE.md                  # Universal config (merged with yours if exists)
  rules/
    supercharger.md          # Execution workflow, anti-patterns, output discipline
    guardrails.md            # Four Laws, autonomy levels, halt conditions
    developer.md             # Your selected role(s)
    pm.md
  shared/
    anti-patterns.yml        # 35 prompt anti-pattern library
  supercharger/
    hooks/                   # Hook scripts referenced by settings.json
  settings.json              # Hooks registered here (merged with existing)
```

Files in `~/.claude/rules/` are automatically loaded by Claude Code on every conversation. No manual activation needed. Hooks in `settings.json` execute deterministically on every tool use.

---

## Install walkthrough

```
$ curl -fsSL .../install.sh | bash

╔═══════════════════════════════════════════╗
║    Claude Supercharger v1.0.0 Installer   ║
╚═══════════════════════════════════════════╝

Step 1 of 4: Install Mode

  1) Safe       — configs + safety hooks only
  2) Standard   — recommended (configs + hooks + productivity)
  3) Full       — everything (+ MCP setup + diagnostics)

> 2

Step 2 of 4: Your Roles

  Which roles describe you? (comma-separated, or 'all')

  1) Developer  — build things
  2) Writer     — communicate things
  3) Student    — learn things
  4) Data       — analyze things
  5) PM         — plan things

> 1,5

Step 3 of 4: Existing Config

  Found existing CLAUDE.md:

  1) Merge   — append Supercharger to your existing file
  2) Replace — back up yours, use Supercharger's
  3) Skip    — keep yours, install everything else

> 1

Step 4 of 4: Installing...

  ✓ Backed up ~/.claude/ to ~/.claude/backups/20260331-142305/
  ✓ Universal config merged (your CLAUDE.md preserved)
  ✓ Universal rules installed
  ✓ Guardrails installed
  ✓ Roles configured: Developer, PM
  ✓ Anti-patterns library installed
  ✓ 4 hooks installed (Standard mode)
  ✓ Done! Run 'claude-check' to verify.
```

Total install time: under 10 seconds.

---

## Verify installation

```bash
bash tools/claude-check.sh
```

Output:

```
Config Files:
  ✓ CLAUDE.md
  ✓ rules/supercharger.md — universal rules
  ✓ rules/guardrails.md — Four Laws + safety

Roles:
  ✓ Developer
  ✓ Pm

Hooks (Standard mode):
  ✓ safety — active
  ✓ notify — active
  ✓ git-safety — active
  ✓ auto-format — active (Developer)

All checks passed ✓
```

---

## Uninstall

From the repo directory:

```bash
./uninstall.sh
```

The uninstaller:
- Removes all Supercharger hooks from `settings.json` (preserves your own hooks)
- Removes the Supercharger block from `CLAUDE.md` (preserves your content above it)
- Removes all rule files, shared assets, and hook scripts
- Offers to restore from the backup created during installation

Your original config is never lost.

---

## Manual install

If you don't trust `curl | bash` (fair), clone and review first:

```bash
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger
cat install.sh          # review the installer
./install.sh            # run locally
```

The installer is ~170 lines of bash. No hidden downloads. No network calls. Everything it installs is in this repo.

---

## Existing config handling

| Scenario | What happens |
|----------|-------------|
| No existing `CLAUDE.md` | Supercharger's config is deployed directly |
| Existing `CLAUDE.md` + Merge | Your content preserved, Supercharger block appended below a marker |
| Existing `CLAUDE.md` + Replace | Your file backed up, Supercharger's deployed |
| Existing `CLAUDE.md` + Skip | Your file untouched, everything else installed |
| No existing `settings.json` | Created with Supercharger hooks only |
| Existing `settings.json` + Merge | Your hooks preserved, Supercharger hooks added alongside |
| Existing `settings.json` + Replace | Your file backed up, Supercharger hooks deployed |
| Existing `settings.json` + Skip | No hooks installed |

A timestamped backup is always created before any changes.

---

## Requirements

- Claude Code (Anthropic's CLI)
- Bash (macOS or Linux)
- Python 3 (for JSON merge operations — comes with Claude Code)

No npm. No pip. No Docker. No build step.

---

## FAQ

**Will this break my existing setup?**
No. The installer backs up your `~/.claude/` directory before making any changes. If you choose "Merge", your existing configs are preserved with Supercharger content appended below a clear marker. Uninstall restores everything.

**How do I change roles after install?**
Run `./install.sh` again. It's idempotent — existing Supercharger configs are replaced, your personal configs are preserved.

**Can I use multiple roles?**
Yes. Enter comma-separated numbers during install (e.g., `1,5` for Developer + PM). All selected role overlays are loaded by Claude Code simultaneously.

**How do I upgrade?**
`git pull && ./install.sh` — the installer detects existing Supercharger content and replaces it cleanly.

**What if a hook blocks something I need?**
Hooks block known-dangerous patterns. If you need to run a blocked command, you can run it directly in your terminal (outside Claude Code). To permanently disable a hook, remove its entry from `~/.claude/settings.json`.

**Does this work with other Claude Code plugins/skills?**
Yes. Supercharger uses `~/.claude/rules/` (scoped rules) and `settings.json` (hooks) — both are standard Claude Code features. It doesn't conflict with skills, MCP servers, or other plugins.

---

## Contributing

**Add a role:** Create a new `.md` file in `configs/roles/`, add the role name to the arrays in `lib/roles.sh`.

**Add a hook:** Create a new `.sh` file in `hooks/`, add it to the mode mapping in `lib/hooks.sh`.

**Improve configs:** Edit files in `configs/universal/`. Keep CLAUDE.md under 50 lines, supercharger.md under 70 lines.

---

## Credits

- [SuperClaude Framework](https://github.com/SuperClaude-Org/SuperClaude_Framework) (MIT) — execution workflow patterns, anti-patterns library
- [TheArchitectit/agent-guardrails-template](https://github.com/TheArchitectit/agent-guardrails-template) (BSD-3) — Four Laws, halt conditions, autonomy levels

---

## License

MIT — see [LICENSE](LICENSE)
