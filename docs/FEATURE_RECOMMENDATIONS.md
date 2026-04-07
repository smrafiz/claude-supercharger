# Feature Recommendations

What's genuinely missing, what would actually help users, and what to avoid.

Last updated: April 2026 | v1.9.3

---

## Guiding principles

1. **Safety is the moat.** No other Claude Code tool does shell-level enforcement. Every new feature should either strengthen safety or stay out of its way.
2. **Don't duplicate what exists.** If Claude Code or an existing hook already does it, don't add another version.
3. **Context cost is real.** Every config file, rule, and agent description eats tokens. A feature that adds 200 tokens of config must save more than 200 tokens of value per session.
4. **Enforced > instructional.** A shell hook that blocks a bad command is worth more than a prompt that asks Claude to avoid it.

---

## What exists today

### Enforced (shell hooks, exit 2)
- Dangerous command blocking (`rm -rf /~/../`, `DROP TABLE`, `chmod 777`, fork bombs, `curl|bash`, `eval`)
- Git safety (`push --force` to main/master, `reset --hard`, `checkout .`)
- Package manager enforcement (`npm` in pnpm project, etc.)
- Credential pattern blocking (AWS keys, GitHub tokens, Stripe, etc.)
- Shell profile / SSH command blocking (`.bashrc`, `.zshrc`, `ssh-keygen`)
- Audit trail with credential redaction (JSONL, 30-day rotation)
- Quality gate — lint/fix/re-check (developer role, standard/full mode)
- Prompt validator — 20 anti-pattern checks (full mode)

### Instructional (prompt-based, not enforced)
- Token economy (standard / lean / minimal tiers)
- 9 agents with per-prompt routing
- 8 roles with mid-conversation switching
- 4 slash commands (/think, /challenge, /refactor, /audit)
- Session summary on compaction/rate limit
- Cost feedback loop (Stop → SessionStart injection)

### MCP servers (auto-installed by role)
- Everyone: Context7, Sequential Thinking, Memory
- Developer: + Playwright, Magic UI
- Designer: + Magic UI
- Writer, Student, PM, Data, DevOps, Researcher: + DuckDuckGo

### Infrastructure
- Statusline (model, project, branch, stack, context %, cost, cache %, active agent)
- Compaction transcript backup
- Session resume tool
- Project-level config (`.supercharger.json`)
- Profiles, presets, export/import
- Install mode detection (offers update vs reinstall)

---

## Recommended: Safety layer improvements

These are enforced features (shell hooks) that close real gaps.

### 1. Conventional commit enforcement
**What:** PreToolUse hook on `git commit` that validates the commit message follows conventional commit format (`feat:`, `fix:`, `chore:`, etc.).
**Why:** Bad commit messages are common when Claude commits. This enforces structure without relying on Claude's judgment.
**Effort:** Low — single regex check in a new hook or added to `git-safety.sh`.
**Risk:** Low — exit 2 on bad format, Claude retries with correct format.

### 2. TypeScript type-check hook
**What:** PostToolUse hook on Write/Edit that runs `tsc --noEmit` on the changed file (or project) after TypeScript edits.
**Why:** Claude frequently writes TypeScript that passes lint but fails type-checking. Catching this immediately saves debugging cycles.
**Effort:** Medium — need to detect tsconfig.json, handle monorepos, keep it fast (incremental check).
**Risk:** Medium — `tsc` can be slow on large projects. Need a timeout and skip-on-slow mechanism.

### 3. Prefix stripping in enforce-pkg-manager.sh
**What:** Add the same `sudo`/`command`/`env` prefix stripping loop that `safety.sh` already has.
**Why:** `sudo npm install` in a pnpm project currently bypasses the pkg manager hook. This is a known gap from the audit.
**Effort:** Low — copy the 3-line stripping loop from safety.sh.
**Risk:** None.

### 4. Schema validation hook
**What:** PostToolUse hook on Write/Edit that validates JSON and YAML files against schema (if a schema is defined in the file or project).
**Why:** Claude frequently generates invalid JSON configs (trailing commas, wrong key names). Catching this immediately is better than a runtime error.
**Effort:** Medium — need `python3 -c` with json.loads for JSON, optional jsonschema for schema validation.
**Risk:** Low — JSON syntax validation is fast and reliable. Schema validation is optional.

### 5. Protect additional dangerous git patterns
**What:** Block `git branch -D` (force-delete) on main/master, `git stash drop` without confirmation, `git clean -fd` (removes untracked files).
**Why:** These are destructive and commonly hallucinated by Claude. Currently unblocked.
**Effort:** Low — add patterns to git-safety.sh.
**Risk:** Low — same pattern as existing git-safety checks.

---

## Recommended: Ecosystem additions

### 6. GitHub MCP server (auto-install for developer role)
**What:** Add the official GitHub MCP server to auto-install for developer role. Uses `gh` CLI auth (already installed for most developers).
**Why:** Issues, PRs, code search, and repo operations are the most common developer workflow outside of editing code. Currently requires manual `mcp-setup.sh`.
**Effort:** Low — add to `lib/mcp.sh` role mapping.
**Risk:** Low — `gh` auth is standard. Fails gracefully if not authenticated.

### 7. /test slash command
**What:** A command that generates unit tests for a specified file or function, using the project's existing test framework.
**Why:** "Write tests for this" is the most common follow-up after implementing a feature. A dedicated command with structured output (test file path, framework detection, coverage target) would be more focused than a general prompt.
**Effort:** Low — it's a markdown command config, similar to /refactor.
**Risk:** None — it's instructional, not enforced.

### 8. /doc slash command
**What:** Generate documentation for a file, module, or function — JSDoc, docstrings, README sections.
**Why:** Documentation is the second most common follow-up. A structured command ensures consistent output format.
**Effort:** Low — markdown command config.
**Risk:** None.

---

## Recommended: Reliability improvements

### 9. Generalist agent fallback route
**What:** When no regex matches in `agent-router.sh`, write "Steve Jobs (Generalist)" to `.agent-route` instead of exiting silently.
**Why:** The README says the Generalist handles unmatched prompts. The code doesn't do this — it exits with no routing. Making them match would close the gap.
**Effort:** Low — change `[ -z "$AGENT" ] && exit 0` to set AGENT to Generalist.
**Risk:** Low — the Generalist agent config already exists.

### 10. Economy tier per-prompt reinforcement
**What:** Inject the active economy tier into every `UserPromptSubmit` hook response (not just SessionStart).
**Why:** Claude's compliance with economy instructions degrades over long sessions as the SessionStart context drifts further away. Reinforcing every prompt keeps the signal fresh.
**Effort:** Low — add economy tier reading to `agent-router.sh` output (it already runs per-prompt).
**Risk:** Low — adds ~10 tokens per prompt.

### 11. Hook self-test command
**What:** `bash tools/hook-test.sh` that runs a quick smoke test against each installed hook — pipes test JSON and checks exit codes.
**Why:** After install or update, users have no way to verify hooks are working without triggering them accidentally. A diagnostic tool would catch issues like the statusline syntax error that was shipped.
**Effort:** Medium — need to craft test inputs for each hook type.
**Risk:** None.

---

## Not recommended (and why)

| Feature | Why not |
|---|---|
| **Filesystem MCP** | Claude Code already has native Read/Write/Edit/Glob/Grep. Redundant. |
| **AI Code Review on commit** | Too slow for a hook (LLM call on every commit). Use /challenge or Gordon Ramsay agent instead. |
| **Multi-model routing** | Claude Code manages model selection. Supercharger can't control this. |
| **Auto-import resolution** | IDE territory (VS Code, JetBrains). Claude already handles imports when writing code. |
| **Smart rename across files** | Claude Code's Grep + Edit already does this. A hook would duplicate native capability. |
| **Docker/K8s helpers** | Too niche for a general tool. Better as a project-level `.supercharger.json` hint. |
| **More agents** (Security, Docs, Tests, etc.) | Existing agents already cover these tasks. Adding more dilutes routing accuracy and increases context cost. |
| **Brave Search as auto-include** | Requires an API key. Already in opt-in via `mcp-setup.sh`. |
| **Performance metrics/dashboards** | Claude Code doesn't expose the data needed. Would require external tooling. |

---

## Implementation priority

### Do now (low effort, high value)
1. Prefix stripping in enforce-pkg-manager.sh (#3)
2. Protect additional git patterns (#5)
3. Generalist agent fallback (#9)
4. /test and /doc commands (#7, #8)

### Do next (medium effort, high value)
5. Conventional commit enforcement (#1)
6. GitHub MCP auto-install (#6)
7. Economy tier per-prompt reinforcement (#10)

### Do later (medium effort, medium value)
8. TypeScript type-check hook (#2)
9. Schema validation hook (#4)
10. Hook self-test command (#11)

---

## Context budget

Current per-session cost: ~3,700 tokens (~1.9% of 200K context).

Each new feature should declare its token cost:
- New hook (shell only, no config): 0 tokens
- New slash command (markdown config): ~50-150 tokens
- New agent config: ~200-400 tokens
- New rule file: ~100-500 tokens

Target: stay under 4,500 tokens total (2.25% of 200K). That leaves ~800 tokens of budget for new features.
