# Community Wants & Pain Points — Claude Code (2026-09-17)

Research sweep of what Claude Code users are asking for and hitting, and what of it
Claude Supercharger can act on.

**Method.** Reaction-ranked open issues from `anthropics/claude-code` (top 40 overall,
plus the `area:permissions`, `area:hooks`, `area:security`, `area:agents`,
`area:skills` label slices, plus everything filed in the last 21 days), cross-checked
against web discussion of Claude Code guardrails and file-deletion incidents.

**Thesis filter.** Supercharger is a harness-layer enforcement product: shell hooks that
fire outside the model loop and deny by exit code. Anything that needs a change inside
the CLI, the TUI, billing, or the model itself is *not ours* no matter how loud it is.
See `[[extension-thesis-enforcement-not-orchestration]]`.

---

## 1. Permissions — the largest structural complaint

The single most-duplicated grievance in the tracker. #30519 puts it bluntly:
"Permissions matching is fundamentally broken — 30+ open issues, no staff engagement,
community building workarounds."

| 👍 | Issue | Summary | Ours? |
|----|-------|---------|-------|
| 207 | #28240 | Permission prompt triggers on `cd` instead of the actual command in compound bash | partial |
| 80 | #30519 | Permissions matching fundamentally broken (meta-issue) | yes |
| 71 | #18950 | Skills/subagents do not inherit user-level `settings.json` permissions | yes |
| 65 | #36168 | Bypass/skip-permissions broken in all versions after v2.1.77 | no |
| 59 | #91650 | `Read()` deny rule prompts on absolute `cd` targets (Windows Git Bash) | yes |
| 51 | #13340 | `allow` rules in global/local settings.json not respected | yes |
| 47 | #47180 | Cowork scheduled tasks ignore "Always allow" | no |
| 46 | #10906 | Plan agent ignores parent settings.json permissions | yes |
| 46 | #6850 | `settings.local.json` allow not working | yes |
| 40 | #30435 | Want: suppress bash safety-heuristic prompts via settings | yes |
| 34 | #5140 | User settings.json permissions not applied at project level | yes |
| 26 | #17017 | Project-level permissions **replace** global instead of merging | yes |
| 25 | #8961 | Deny rules in `.claude/settings.local.json` ignored — filed as a security vulnerability | yes |

### The fresh wave: deny-rule false positives

Every high-signal bug filed in the last three weeks is the same shape — a `Read()` deny
rule arming permission prompts on commands that never touch the denied path:

- #91650 — prompts on absolute `cd` targets whenever any `Read()` deny rule exists (2.1.257–2.1.259)
- #91683 — `bypassPermissions` prompts on `cd DIR && grep …` (regression in 2.1.259)
- #91776 — prompts on `cd` compounds even when the `cd` target is a literal path
- #91853 — unrelated Bash `grep` after `cd` with a relative glob
- #91681 — `Read(**/.env)` prompts on every `rg` directory search, although `rg` skips hidden files by default
- #91778 — `grep -r --include` falsely triggers `Read(.env)`, breaking every recursive search
- #91848 — deny rule arms an unwhitelistable prompt in `bypassPermissions`, and the predicate ignores the rule's own patterns
- #91837 — read-only Bash compounds starting with `cd DIR` lost static auto-approval

This is precisely the failure mode we have shipped twice ourselves
(`[[pathguard-cwd-boundary-fp]]`), and it is the failure mode that makes users uninstall
(`[[perf-hook-overhead]]`, `[[supercharger-has-real-users]]`).

---

## 2. Hooks and extensibility

| 👍 | Issue | Summary |
|----|-------|---------|
| 181 | #91870 | "Mods" — make Claude 10x more extensible |
| 66 | #43326 | Auto-select model and effort by task complexity |
| 66 | #9516 | User Interrupt hook |
| 35 | #31969 | Worktree resume, configurable branch naming, **hook removal control** |
| 32 | #5186 | Notification hook 10-second delay |
| 24 | #29716 | WorktreeCreate/Remove hooks not called in Claude Desktop |
| 23 | #27365 | `updatedPrompt` support on `UserPromptSubmit` |
| 21 | #40495 | Cowork sessions ignore user hooks and managed settings |
| 17 | #82001 | `UserInputChange` hook — expose the prompt input buffer |
| 16 | #6305 | Pre/PostToolUse hooks not executing |
| 19 | #30355 | Global option to disable skill auto-triggering per project |

Most of these are harness capabilities we cannot add. The interesting ones are the
*trust* items: hooks silently not firing (#6305, #40495) and no control over which hooks
a plugin installs (#31969). Both are arguments for our own self-diagnosis surface
(`/sc-doctor`).

---

## 3. Safety and data loss — external validation of the thesis

- Documented incidents of Claude Code wiping a home directory via `rm -rf` with tilde
  expansion, **despite a global CLAUDE.md forbidding destructive commands**. Prompt-level
  rules do not hold; the community's answer is deterministic hooks.
- #32733 (201👍) secure secrets injection for Claude Code on the web.
- #29910 (45👍) built-in secrets management.
- #4276 (36👍) environment-variable expansion in `settings.json`.
- #90450 (16👍, new) **Auto Mode's Bash-first instruction silently disables nested
  CLAUDE.md and path-scoped rules.**

The last one matters to us directly: this session runs Auto Mode with a Bash-first
directive, and our rule delivery depends on nested CLAUDE.md files being honoured.

---

## 4. Model-behaviour complaints that our rules already target

| 👍 | Issue | Summary | Our lever |
|----|-------|---------|-----------|
| 229 | #65961 | Verbose code comments by default, ignores instructions to stop | economy.md |
| 117 | #19649 | Reaches for bash `sed`/`grep` when Read/Grep fit better | rules |
| 563 | #77136 | Repetitive rhetorical tics, style instructions ignored | economy.md |

No build required; useful as evidence that the rule layer solves something real.

---

## 5. Loudest overall, not addressable by us

Buddy removal (2090👍 #45596) · multi-account switching (958👍 #18435, 1009👍 #36151) ·
usage limits burning a 5-hour window in 30 minutes (725👍 #16157, 545👍 #38335, 160👍
#45756) · India/INR pricing (636👍 #17432) · XDG Base Directory support (448👍 #1455) ·
AGENTS.md support (499👍 #31005) · terminal flicker (321👍 #1913, 335👍 #769) · Visual
Studio 2026 (550👍) · VS Code diff-review UI (271👍) · Cowork/Plan9 Windows breakage
(61👍 #92984, 11👍 #92958).

---

# Plans

Five candidates, ranked by frequency in the tracker times fit with the thesis. Each is
scoped so it can be dropped without touching the others.

## P1 — Deny-rule false-positive audit (highest value)

**Why.** Seven issues in twenty-one days, all the same shape. If the harness's own path
guards false-positive this way, ours plausibly do too, and an FP is what makes people
uninstall.

**Scope.** Audit every guard that maps a command to a path — the `.env` / credential
read guards and `path-guard` — against the exact shapes the upstream issues name:

1. `cd /absolute/path && grep foo .` (absolute `cd` target)
2. `cd subdir && grep -r --include='*.js' foo .` (relative glob + include filter)
3. `rg foo` in a directory containing a `.env` (ripgrep skips hidden files by default)
4. `cd X && cat README.md` where a `Read(**/.env)` deny rule exists
5. The same four under `bypassPermissions`

**Done when.** One test file exercising all five shapes, each asserting *allow*, and any
guard that blocks them is narrowed. Note the trap in `[[guard-fp-verify-with-literal-input]]`:
verify with literal command strings, not concatenations.

**Non-goals.** Do not widen any guard to fix an FP without a test that fails first.

## P2 — Guard survival when harness deny rules are ignored (#8961)

**Why.** #8961 reports deny rules in `settings.local.json` being silently ignored — the
exact scenario Supercharger exists to cover. We have never proven our guards still fire
in it.

**Scope.** A positive test: with a `Read(.env)` deny rule configured *and disregarded*,
confirm our PreToolUse hook still denies the read by exit code. Same for one destructive
Bash pattern.

**Done when.** Two tests, both red if the hook is removed. See
`[[guard-fails-open-oracle-fails-loud]]` — assert on the exit code and the reason string,
not on silence.

## P3 — Subagent and skill permission inheritance (#18950, #10906)

**Why.** Users report skills and subagents not inheriting permissions. We already know
`additionalContext` on `SubagentStop` does not reach the parent
(`[[subagent-return-channel-facts]]`), but we have not confirmed the *PreToolUse* path
inside a subagent.

**Scope.** Confirm, by measurement, whether our PreToolUse hooks fire for tool calls made
from inside a subagent and from inside a skill invocation. Record the answer in memory
either way — it is a fact about the harness, not a feature.

**Done when.** A measured yes/no for both, written up. If the answer is "no", that is a
documented limitation for the README, not a bug to fix.

## P4 — Auto Mode Bash-first versus nested CLAUDE.md (#90450)

**Why.** 16👍 and new. If the Bash-first directive really suppresses nested CLAUDE.md and
path-scoped rules, our configs that rely on directory-scoped rules degrade silently under
Auto Mode — and this session is running exactly that combination.

**Scope.** Reproduce: a nested `CLAUDE.md` with a distinctive directive, a session in Auto
Mode, and a check of whether the directive is honoured. Then decide whether our shipped
configs depend on nested files at all.

**Done when.** Reproduced or refuted with evidence. If confirmed and it affects us,
document it in `docs/KNOWN-ISSUES.md` and stop relying on nesting.

## P5 — No build: verbose-comment and tool-choice complaints

#65961, #19649 and #77136 are already targeted by `economy.md` and the rules layer.
Action is limited to citing them as evidence in the README, not new code.

---

## Deliberately not planned

- Anything in section 5. Loud, but requires changes inside the CLI, billing, or the model.
- A "mods"/extensibility framework (#91870). Off-thesis: orchestration, not enforcement.
- Secrets *management* (#29910). We scan for secrets; we do not want to store them.

---

## Sources

- `anthropics/claude-code` issue tracker, queried 2026-09-17 via `gh issue list`
  (reaction-sorted; label slices and a 21-day recency slice).
- <https://www.morphllm.com/claude-code-reddit> — Reddit sentiment roundup
- <https://ofox.ai/blog/claude-code-safety-prevent-accidental-file-deletion/> — file-deletion incidents and defense-in-depth
- <https://www.askglitch.com/blog/claude-code-hooks> — hooks as deterministic guardrails
- <https://www.techbuzz.ai/articles/anthropic-launches-auto-mode-safety-guardrails-for-claude-code> — Auto Mode guardrails
