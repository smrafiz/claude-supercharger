# Changelog

## Contents

- [2.4.18] - 2026-05-07 — perf(observability): close the `/perf` blind spot for hooks that don't source `lib-suppress.sh`. Today's profiling pipeline (v2.4.6) only instrumented hooks that source `lib-suppress.sh`. Six high-traffic hooks weren't sourcing it: `safety.sh` (every Bash, sync, blocks user), `audit-trail.sh` (every Bash/PowerShell/Write/Edit), `smart-approve.sh` (every PermissionRequest), `prompt-injection-scanner.sh` (every mcp__/WebFetch/WebSearch), `scope-guard.sh` (multiple events), `prompt-validator.sh` (every UserPromptSubmit). They were invisible to `/perf` so optimization was blind to their cost. New `hooks/lib-timing.sh` ships a standalone EXIT-trap-based timing emitter (no suppress side effects, just timing). One line added at the top of each unprofiled hook. Re-run `/perf --slow` after a session to see the now-complete picture. 801 tests passing.
- [2.4.17] - 2026-05-07 — feat(ux): commit-check block message now teaches the format. Previously said "permanently blocked. Run it in your terminal directly if needed." — wrong advice for a fixable format violation. Bypass via terminal would let bad commit messages slip through. Now: shows the Conventional Commits format, valid types (feat/fix/chore/docs/style/refactor/test/perf/ci/build/revert), an example (`feat(auth): add OAuth support`), and how to disable the hook for projects that don't use Conventional Commits. High-frequency event — every malformed commit hits this. 801 tests passing.
- [2.4.16] - 2026-05-07 — feat(ux): block messages now tell users how to override. `safety.sh` previously said "permanently blocked. Run it in your terminal directly if needed." — no mention that categories can be disabled via `.supercharger.json`. Users hitting a legitimate block (e.g. clipboard access for a test, .venv write for a tool) had no in-context path forward and had to read docs they didn't know existed. Now: every safety block message lists the 10 category names and the `disableSecurityCategories` opt-out path. `git-safety.sh` clarifies that git blocks are absolute by design (no per-project opt-out — destructive git ops should never run from an agent). `path-guard.sh` reasons now consistently include `; opt out via disableSecurityCategories: ["<category>"]` for every category branch (previously only build-artifacts had the hint). 801 tests passing (existing tests updated to match new phrasing).
- [2.4.15] - 2026-05-07 — feat(ux): lower lesson-recall Jaccard threshold from 0.5 to 0.35. The previous threshold meant lessons rarely surfaced — a lesson stored as "don't use sed -i without backup suffix on macOS" would not match a later prompt like "edit this config in place" because the token overlap fell well below 0.5. Reflexion memory was working but silently filtering itself into oblivion. New default 0.35 is still discriminative (~3 of 8 tokens must overlap, not just 2 of 8) while letting genuinely related lessons fire. Configurable via `SUPERCHARGER_LESSON_THRESHOLD=<float>` for users who want to tune. 801 tests passing.
- [2.4.14] - 2026-05-07 — fix(install): `deploy_hook_scripts` now removes stale hook .sh files. Hooks deleted in earlier releases (e.g. `exfiltration-guard.sh`, `loop-detector.sh`, `project-verify.sh`, `reread-detector.sh`, `shell-wrapper-guard.sh`, `verify-on-stop.sh` — all merged or removed in v2.3.x and v2.4.0) lingered on disk forever after each update. They were harmless (settings.json never registered them, so they never fired) but polluted `/why` explanations, diagnostics, and audits — and risked someone manually re-registering them. Now: any hook file in `~/.claude/supercharger/hooks/` that's not in the source `hooks/` directory is removed during deploy. `webhook-lib.sh` is preserved (it's the renamed copy of `lib/webhook.sh`). Local install dropped from 87 to 81 hook files. 801 tests passing.
- [2.4.13] - 2026-05-07 — perf(tokens): cross-session dedup for `standards-inject.sh`. Stack rules don't change between sessions of the same project, but the hook re-emitted the full ~380-token stack injection (Forbidden + Toolchain + Pitfalls for react/nextjs etc.) on every SessionStart. The existing `hook_already_emitted` dedup is in-session only. Added a per-project TTL file (`scope/.standards-inject-<project-hash>`) that records `<timestamp> <message-hash>` and skips re-emit if the same hash was emitted within 24h. Saves ~380 tokens × N sessions/day per project (active devs hit 3-5 sessions/day). Behavior preserved: changes to the hash (e.g. user edits stack file) re-emit immediately. 801 tests passing.
- [2.4.12] - 2026-05-07 — perf: drop unnecessary python3 JSON-escape fork in `auto-compact.sh`. The hook composed a fixed-template message (3 hardcoded strings + integer PCT) and then forked python3 just to wrap it in JSON. Since the message body has no quotes, backslashes, or control chars, bash `printf '{"systemMessage":"%s"}'` is safe. Bench: 216ms → 50ms (-77%). Today's data showed this hook contributing 4.5s of session overhead (21 fires × 216ms). 801 tests passing.
- [2.4.11] - 2026-05-07 — perf: continued data-driven fork consolidation. `cache-health.sh` (PostToolUse async, fires every 5th call) was forking 4 sequential python3 calls — once for `cache_read_input_tokens`, once for `cache_creation_input_tokens` (parsing the same JSON twice), once for hit-rate math, and once each for window update + degraded check. Consolidated to a single python3 fork that does all of it (parse, extract both fields, compute hit rate, update rolling window, decide degraded state, return space-separated tuple). Avg drops from 173ms to ~24ms in benchmark (-86%). Total session-overhead saving: this hook contributed 3.8s in today's `/perf` data and should drop to <1s. 801 tests passing (no test changes).
- [2.4.10] - 2026-05-07 — perf: hot-path fork consolidation surfaced by today's `/perf --slow` data. (1) `budget-cap.sh check` mode (PreToolUse, sync — fired before every tool call) was forking 3-5 times per call: jq for tool_name, jq for cwd, python3 for `.supercharger.json`, python3 for `.session-cost`, python3 for threshold decision. Consolidated into one python3 fork that does all of it. Avg drops ~184ms → ~129ms (-30%). (2) `bash-output-compactor.sh` (PostToolUse|Bash, sync) was forking 4 separate jq calls for cwd/tool_name/command/output. Combined cwd+tool_name+command into one jq with `@tsv` (output kept separate to avoid tab-mangling on multi-line stdout). Saves 2-3 jq forks per Bash call on the hot path that early-exits before the python3 compaction step. 801 tests passing (no test changes needed).
- [2.4.9] - 2026-05-07 — fix(security): defense-in-depth for CVE-2026-33068. `config-scan.sh` now warns when project `.claude/settings.json` (or `.local.json`, or user `~/.claude/settings.json`) contains `permissions.defaultMode: "bypassPermissions"` or top-level `dangerouslySkipPermissions: true` — both silently disable the trust dialog and run all tools without confirmation. Patched upstream in Claude Code v2.1.53; supercharger adds the SessionStart warning so a tampered project file from a cloned repo doesn't slip through on patched versions. 2 new tests, 801 passing.
- [2.4.8] - 2026-05-07 — fix(security): close `rm -rf` blind spots that match the claude-code#29023 vector (Claude Code deleted user profile directory). Previous regex caught `/`, `~`, `$HOME`, `..` but missed: (1) `rm -rf .` and `rm -rf ./` and `rm -rf ./*` (deletes CWD wholesale — same effect as the ghost-CWD cascade in #29023); (2) absolute paths that resolve to the project root or any of its ancestors (e.g. `rm -rf $(pwd)`, `rm -rf /Users/me/myproject`). `safety.sh` now extracts `cwd` from the hook payload, walks each rm arg with `shlex` + `os.path.realpath`, and blocks any target whose resolved path equals or is an ancestor of `cwd`. Specific subdirs (`rm -rf ./build/dist`, `rm -rf /tmp/temp123`) remain allowed. 5 new tests, 799 passing.
- [2.4.7] - 2026-05-07 — fix: `standards-inject.sh` crashed on every SessionStart because `install.sh` never copied `rules/stacks/` to `~/.claude/supercharger/rules/`. The hook did `cd "$HOOKS_DIR/../rules"` under `set -e`, so the missing dir aborted the hook with a non-blocking error every session for users on existing installs (silent loss of stack-derived standards). Two fixes: (1) `lib/hooks.sh` `deploy_hook_scripts()` now copies `rules/stacks/*.md` alongside hooks/lib/tools so fresh installs land complete; (2) `standards-inject.sh` now skips cleanly when `LIB_DIR` or `RULES_DIR` is missing (defensive — protects installs that never had the dir). Re-run `./install.sh` to deploy the missing rules locally. 794 tests passing.
- [2.4.6] - 2026-05-07 — feat: finish the `/perf` profiling pipeline. `hooks/lib-suppress.sh` now installs an `EXIT` trap inside `init_hook_suppress` (when the `.profiling` sentinel is present) that appends `{hook, elapsed_ms, ts}` to `~/.claude/supercharger/audit/<date>.jsonl` on hook completion. `/perf` reads these and produces a real timing report. Trap is skipped on hooks that already have an EXIT trap (better partial data than broken cleanup). Hook name resolution walks `BASH_SOURCE` past `lib-suppress.sh` itself, so the 10 hooks that rely on the auto-init at `lib-suppress.sh:183` (auto-compact, budget-cap, human-approval-gate, mcp-tracker, notify, rate-limit-advisor, session-checkpoint, thinking-budget, tool-call-limiter, tool-history-tracker) are now correctly named in the audit log instead of all being labeled "lib-suppress". Also fixes hook-perf.sh emitting a help message to stderr in `--json` mode (broke the existing JSON-output test). 2 new tests, 794 passing. v2.4.5 surfaced this gap; v2.4.6 closes it.
- [2.4.5] - 2026-05-07 — fix: `/perf` profiling sentinel was self-destructing. `tools/hook-perf.sh` ran `touch ~/.claude/supercharger/scope/.profiling` then `trap 'rm -f $PROFILING_FILE' EXIT` — sentinel was alive only for the few seconds the report ran, so timing data could never accumulate. Removed the touch+trap; sentinel is now user-controlled (`touch` to start, `rm` to stop). Also documents that the timing-emit half of the pipeline (`HOOK_START_MS` is captured in `lib-suppress.sh` but no hook writes `elapsed_ms` to the audit log on exit) is incomplete — `/perf` will still report "No hook timing data found" until that's filled in. Slash command updated to surface this limitation honestly. 792 tests passing (no test changes needed).
- [2.4.4] - 2026-05-06 — patch: defense-in-depth for CVE-2026-21852. `config-scan.sh` now scans project `CLAUDE.md`, `.claude/settings.json`, and `.claude/settings.local.json` for `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, or `ANTHROPIC_AUTH_TOKEN` references — these were the exfiltration vectors in CVE-2026-21852 (cloning a malicious repo silently rerouted API traffic to an attacker, leaking the user's API key before the trust dialog appeared). Patched upstream in Claude Code v2.0.65; supercharger now warns if any project file contains those references so users notice tampering even on patched versions. 2 new tests, 792 passing.
- [2.4.3] - 2026-05-06 — patch: third settings.json footgun. `config-scan.sh` (SessionStart) now warns when `sandbox.filesystem.denyRead` is set in user/project settings — this field is silently unenforced by Claude Code (claude-code#44274), so files in those paths remain readable despite the policy. Users who set it have false confidence; warning directs them to env-file-guard.sh and path-guard.sh for actual read protection. 1 new test, 790 passing.
- [2.4.2] - 2026-05-06 — patch: harden against two recently-reported Claude Code footguns. (1) `git-safety.sh` now blocks `git checkout <ref> -- .`, `git checkout <ref> .` (no `--`), and `git restore --source=<ref> .` — silent destruction of unstaged work, real-world data loss reported in claude-code#55024 (14 files lost, no recoverable blobs). Specific-path forms (`git checkout <ref> -- src/file.ts`) and `-b` branch creation remain allowed. (2) `config-scan.sh` (SessionStart) now scans `~/.claude/settings.json`, project `.claude/settings.json`, and `.claude/settings.local.json` for bare `Edit`/`Write`/`Bash`/`MultiEdit` entries in `allowedTools` or `permissions.allow` — these silently bypass all PreToolUse hooks (path-guard, env-file-guard, git-safety, safety, tool-preferences) per claude-code#44482. Scoped patterns like `Edit(src/**)` are not flagged. Emits a SessionStart warning instructing user to scope or remove. 9 new tests, 789 passing. No new hooks; existing hooks extended.
- [2.4.1] - 2026-05-05 — patch: portability + UX wins from post-release research. (1) `install.sh` now hard-fails with package-manager-specific install hints (brew/apt-get/dnf/pacman/apk) when `jq` or `python3` is missing — prevents silent breakage on minimal Linux containers. (2) `git-safety.sh` falls back to `python3 -c "json.dumps(...)"` when `jq` is unavailable so the hook never silently allows commands. (3) CI `version-consistency` job replaces GNU-only `grep -oP` with portable `grep -oE | sed` — Linux-CI green again. (4) Alpine/musl explicitly documented as unsupported in the README compat note. (5) `compaction-backup.sh` now pipes the original PreCompact JSON (with `transcript_path`) into `session-memory-write.sh` instead of empty stdin — closes the gap where decisions made in pre-compact sessions weren't captured to `supercharger-memory.md`. (6) NEW `bash-output-compactor.sh` (PostToolUse|Bash, v2.1.121 `updatedToolOutput` schema) — when bash output exceeds 50 lines AND the command matches a verbose pattern (`git log`, pytest/vitest/jest/mocha/go test/cargo test, npm/pnpm/yarn install), replaces Claude's view with a structured summary (head+tail for git log, pass/fail counts + failure excerpt for tests, package count + warnings for installs). Original output is preserved in transcript log. Disable via `SUPERCHARGER_BASH_COMPACTOR=0`. Hook counts: 80→81 full, 18→19 safe. 780 tests passing (+9 new tests for bash-output-compactor).
- [2.4.0] - 2026-05-05 — minor release: optimization plan execution. Phase 1 (quick wins): removed 3 dead hooks + 2 orphan tests, cleaned stale comments, replaced fabricated CVE-2026-35021 reference with generic description, capped `safety.sh` Python fork at 500ms via `timeout`/`gtimeout`, added `SUPERCHARGER_ADVISORY_HOOKS=0` env var that disables 4 chatty advisory hooks at once. Phase 2 (perf): per-session `.tool-history-<sid>` file fixes cross-session data leakage when multiple Claude windows run concurrently; agent-router 30s TTL on existing prompt-hash dedup so idle sessions re-inject context after pauses. Phase 3 (security): new `path-guard.sh` blocks 5 attack categories with per-category opt-out via `.supercharger.json` `disableSecurityCategories` — path traversal (incl. URL-encoded `%2e%2e`, double-encoded, null bytes), symlink attacks, git internals (`.git/hooks/`, `.git/refs/`, `~/.claude/hooks/`), absolute-path writes outside project (`~/.ssh/`, `~/.aws/`, `/etc/`), build artifact injection (`node_modules/.bin/`, `.next/`, `.venv/`). Phase 4 (UX): new `tool-preferences.sh` reads `.supercharger.json` `toolPreferences` and suggests alternatives instead of blanket deny — e.g. `npm install` → "Use `pnpm install`". Handles env var prefixes and `npx`/`bunx` wrappers. Hook counts: 78→80 full, 16→18 safe. 771 tests passing (+18 new tests for path-guard, tool-preferences, session-isolation).
- [2.3.60] - 2026-05-04 — feat: hook-toggle override-feedback loop. Each `off` action now appends to `~/.claude/supercharger/scope/.toggle-history` (timestamped, capped at 200 entries with PID-suffix atomic trim). After each disable, counts off-events for the same hook in the last 7 days; if ≥ 3, prints a suggestion to add a per-project exception in `.supercharger.json` instead of repeatedly toggling. Closes the trust-calibration gap surfaced in user-facing research — when users override the same hook repeatedly, supercharger now suggests structural fixes rather than ignoring the signal. 779 tests passing.
- [2.3.59] - 2026-05-04 — feat: user-facing visibility + auto-decision capture. New `/sc-status` command renders supercharger session state (cost vs budget, confidence score, lessons count + recent 3, disabled hooks, memory size, recent blocks) — single-shot dashboard for state previously scattered across `~/.claude/supercharger/scope/`. New `/why` command explains the most recent hook firing (which hook, what triggered it, evidence, fix step). New `/learn <rule>` command for explicit user-stated rule capture (writes to `lessons.jsonl` with `source:user-explicit` flag for distinguishing from passive auto-capture). `session-memory-write.sh` now extracts decision statements from assistant messages on Stop (`I'll X because Y`, `decided to X`, `skipped X because Y`, `chose X over Y`) and appends a `decisions:` field to `supercharger-memory.md` — closes the gap where memory captured what changed but not why. 779 tests passing.
- [2.3.58] - 2026-04-30 — feat: SuperClaude port — `--think` / `--think-hard` / `--ultrathink` reasoning-depth flags detected by `thinking-budget.sh` PreToolUse hook (new `ultra` level injects deep-reasoning directive). New `/estimate` slash command (scoped time + complexity report, halts before any code). New `/cleanup` slash command (dead code removal with two-tier safety: Tier 1 auto-fixes unused imports / unreachable code, Tier 2 gates exported zero-caller symbols and dynamic-dispatch suspects for explicit user approval). Audit found that root-cause-analyst, requirements-analyst, and `/sc:reflect` were already covered by existing supercharger primitives (Sherlock Holmes debugger, `/interview`, `/reflect` + reflexion memory) so they are not duplicated. 779 tests passing.
- [2.3.57] - 2026-04-30 — perf: 4 token-economy + disk-I/O wins from full hooks audit. (1) `economy-reinforce.sh` no longer fires every 3rd prompt — now only after compaction (reads `.memory-restored` mtime + own ack flag). ~66% fewer firings in normal sessions. (2) `subagent-safety.sh` deduplicates per session — full safety block emitted once via `.subagent-safety-injected-<sid>` flag; subsequent SubagentStart calls in fan-out get a 1-line stub (~60 → ~12 tokens per repeat). (3) `post-compact-inject.sh` lazy-stub: when working tree is clean and memory is small, emits stub pointer instead of full 2000-char body (~50% per-compact reduction in clean sessions). (4) `scope-guard.sh clear` extended — deletes per-session orphan files (`.agent-classified-`, `.last-tier-`, `.repetition-flag-`, `.subagent-costs-`, `.subagent-safety-injected-`) on Stop + 7-day TTL prune. Prevents unbounded scope/ growth across long-running users. 779 tests passing.
- [2.3.56] - 2026-04-30 — docs: README overhaul. 465 → 308 lines. Architecture-before-features ordering. Runtime-enforcement framing as differentiator vs prompt-only frameworks (SuperClaude, agent-os, BMad). Hook count corrected (62-65 → 78). New features documented: confidence gate, reflexion memory, stack-derived standards (8 ecosystems). ASCII hook-flow diagram added. Cut: first-person testimonial language, Two-modes/Configuration repetition, install variant detail. 7 sections (down from 11): Lead → How → What → Install → Configure → Going deeper → FAQ.
- [2.3.55] - 2026-04-30 — fix: expanded race-condition + injection fixes from full older-hook audit (~55 hooks). (1) `.tmp` rotation race extended to 6 more hooks (`budget-cap`, `subagent-cost`, `learn-from-blocks` rotate+dedup, `adaptive-economy`, `event-logger`, `stop-failure`) — all switched to `$$.tmp` PID-suffix pattern matching v2.3.54 fix. (2) `scope-guard.sh` snapshot now written atomically (build to `.$$.tmp`, then `mv`) — fixes partial-read race where concurrent `check` mode could see empty `dir:` field and silently stop enforcing. (3) `subagent-cost.sh` JSONL entry build no longer interpolates shell vars into Python string literal — agent names with quotes (e.g., `O'Brien`) used to corrupt the record (write `{}`); now passes via env vars. perf(reentry-detector): replaced 2 python3 JSON-parse forks with jq (~30ms saved per UserPromptSubmit). 778 tests passing.
- [2.3.54] - 2026-04-30 — fix: race conditions + security hardening from self-audit. (1) `.tmp` file races: parallel hook runs in `tool-history-tracker.sh`, `lesson-record.sh`, `repetition-detector.sh` (loop + reads) clobbered each other's writes — switched to `$$.tmp` suffix for atomic isolation. (2) confidence-gate `rm -rf` regex bypass: `rm -rf/tmp` (no space) and `rm -rf -- /path` evaded patterns — broadened regex to handle paths/separators. (3) `session_id` unsanitized in path construction (theoretical traversal risk) — now stripped to `[a-zA-Z0-9_-]` and capped at 64 chars in confidence-gate + repetition-detector. (4) confidence-gate hot path forked 5+ python3 processes per Edit/Write/Bash — combined score+threshold computation into single fork (~150ms saved). 778 tests passing.
- [2.3.53] - 2026-04-30 — feat: confidence gate (runtime-enforced). New `hooks/tool-history-tracker.sh` (PostToolUse async) appends per-tool success/failure to `~/.claude/supercharger/scope/.tool-history` (rolling 20). New `hooks/confidence-gate.sh` (PreToolUse on Edit/Write/destructive-Bash) computes score 1.0 − Σ(deductions): failures_in_last_5 × 0.20, read-before-write × 0.30, repetition_flagged × 0.20. Three-tier action: ≥0.7 silent allow, 0.4–0.7 warn via `systemMessage`, <0.4 deny via `permissionDecision: deny` (PreToolUse v2.1.119 schema). `repetition-detector.sh` extended to drop a per-session marker file consumed by gate. Tier-scaled output (minimal/lean/standard). Disable: `SUPERCHARGER_CONFIDENCE=0`. 15 new tests, 778 passing. Differentiator: SuperClaude's `confidence-check` is pure prompt engineering — supercharger ships real runtime enforcement.
- [2.3.52] - 2026-04-30 — feat: stack standards expanded — `rules/stacks/` now ships vue, svelte, rust, php in addition to react/nextjs/python/go. `hooks/standards-inject.sh` matcher extended (Vue framework value matched exactly to avoid false positives; Svelte/SvelteKit substring-matched; Rust/PHP added to language list). 4 new tests, 763 passing. No new hooks; `lib/detect_stack.py` already detected all 4.
- [2.3.51] - 2026-04-30 — feat: reflexion memory (lesson capture + recall). New `hooks/lesson-record.sh` (Stop event) scans assistant's last transcript message for diagnostic markers (`the issue was`, `root cause`, `fixed by`, ...) and appends structured lesson records to `<repo>/.claude/supercharger/lessons.jsonl`. New `hooks/lesson-recall.sh` (UserPromptSubmit) tokenizes prompt, computes Jaccard overlap against stored lessons (threshold 0.5), injects top 3 matches with tier-scaled output (minimal=count, lean=one-line, standard=full+fix+files). Per-project storage with walk-up resolution. 1000-entry rotation. Disable: `SUPERCHARGER_LESSONS=0`. 14 new tests, 749 passing.
- [2.3.50] - 2026-04-30 — feat: stack-derived standards auto-injection. New `hooks/standards-inject.sh` (SessionStart) detects project stack via `lib/detect_stack.py` and injects matching rules from `rules/stacks/{react,nextjs,python,go}.md` (Forbidden patterns, Toolchain, Pitfalls). Tier-scaled output: minimal=stack tag (~15 tokens), lean=Forbidden+Toolchain (~150), standard=full (~400). User override via `~/.claude/rules/stacks/<name>.md`. Disable with `SUPERCHARGER_STANDARDS=0`. 10 new tests, 735 passing.
- [2.3.49] - 2026-04-29 — fix: install.sh MCP profile prompt was misleading after v2.3.47 — "Dev" claimed to include playwright/github/Magic UI but actually only Magic UI is auto-included now. Updated text and token estimates; added post-install hint for `SUPERCHARGER_MCP_EXTRAS`.
- [2.3.48] - 2026-04-29 — feat: `SUPERCHARGER_MCP_EXTRAS` now also accepts `sequential-thinking` and `memory` (role-agnostic). Previously these were only available by switching to the `research` or `full` profile (which loaded both at once). Opt-in flag is more granular: `SUPERCHARGER_MCP_EXTRAS="sequential-thinking"` to enable just one.
- [2.3.47] - 2026-04-29 — perf: developer role MCP defaults trimmed to context7 + magic-ui (~750 tokens). Playwright (~3300 tokens) and GitHub (~1500 tokens) are now opt-in via `SUPERCHARGER_MCP_EXTRAS=playwright,github`. Most users get an 86% MCP token reduction. Existing users keep their current config; only fresh installs and `mcp-profile.sh` invocations are affected.
- [2.3.46] - 2026-04-29 — fix: stale version strings across tools/supercharger.sh, plugin.json, marketplace.json, README badges (CI version-consistency check had been failing since v2.3.25 due to wrong sed patterns); portable backdate helpers and stat compatibility in scope-cleanup.sh tests so Linux CI passes; `bash tools/bump-version.sh <ver>` is now the canonical way to bump versions. CI green on all jobs.
- [2.3.45] - 2026-04-28 — stabilize: scope-cleanup expanded with 14 more TTL patterns (.quality-gate-cache, .typecheck-cache, .notify-ts, .prompt-cost, .prompt-tokens, .active-mcp, .loop-detector, etc.). Now covers ~250 stale files. ORPHANS=1 env var lists unmatched files for future pattern additions. README links to docs/HOOKS.md.
- [2.3.44] - 2026-04-28 — stabilize: add `tools/list-hooks.sh` + `docs/HOOKS.md` — auto-generated catalog of all hooks (Event/Matcher/Purpose) parsed from each hook's header. Includes disable instructions and tool inventory. 9 new tests, 732 passing.
- [2.3.43] - 2026-04-28 — stabilize: add `tools/scope-cleanup.sh` to prune stale state files. Covers 14 patterns (.dedup-, .agent-classified-, .agent-dispatched-, .denied-, .keep-going-, .stack-cache-, .pending-, .gate-pending-, .router-hash-, .last-tier-, .last-category-, .subagent-active-, .subagent-costs-*.jsonl, .user-corrections-, .user-reinforcements-, .eco-stop-, .tier-snapshot-, .rate-limit-) with appropriate TTLs (1h to 30d). SessionEnd hook auto-runs cleanup at most once/day. First run on dev system pruned 83 stale files. 5 new tests, 723 passing.
- [2.3.42] - 2026-04-28 — perf: extend tier-aware output to 4 more hooks (subagent-stop-check, comment-replacement-check, lazy-refactor-check, cwd-changed). All 7 noisy hooks now emit telegraphic form on economy=minimal. Estimated 70-85% per-emission token reduction in minimal tier.
- [2.3.41] - 2026-04-28 — perf: tier-aware hook output. slow-tool-detector / tool-failure-advisor / permission-denied-advisor now emit telegraphic form on economy=minimal (~80% smaller messages: "[slow] Bash 15.0s" vs "[Slow tool] Bash took 15.0s (threshold: 10s) | Command: ls | Consider..."). lean tier emits middle ground. SUPERCHARGER_TIER read from scope/.economy-tier at session start. 718 passing.
- [2.3.40] - 2026-04-28 — perf: per-session dedup of repeated systemMessage emissions across 7 noisy hooks. Each hook records (hook_name, message_hash, timestamp) per session; 10-min TTL. Same hook+message within window emits once instead of N times. Saves ~70-80% of redundant context-injection tokens. `SUPERCHARGER_NO_DEDUP=1` disables for tests. 717 passing.
- [2.3.39] - 2026-04-28 — add lazy-refactor-check hook (PostToolUse Edit,MultiEdit) — flags renaming `foo` to `_foo` (lazy refactor: should remove the param or document why it stays). Covers TS/JS/Python/Rust/Go/Java/Kotlin/Swift/Ruby/PHP. 9 new tests. 717 passing. (Inspired by carlrannaberg/claudekit.)
- [2.3.38] - 2026-04-28 — add comment-replacement-check hook (PostToolUse Edit,MultiEdit) — flags when Claude replaces working code with `// ... ` or `# ...` comments instead of deleting cleanly. Detects // /* */ # -- * <!-- patterns across JS/TS/Python/SQL/HTML/etc. Skips .md/.mdx/.txt/.rst. 10 new tests. 708 passing.
- [2.3.37] - 2026-04-28 — security: extend safety.sh with pipeline-bypass + sensitive-file-read detection. New blocks: `echo .env | xargs cat`, `find . -name .env -exec cat {} \;`, `find -name "*.pem" | xargs cat`, `cat .npmrc`, `cat ~/.ssh/id_rsa`. Extended sensitive patterns: .npmrc, .pypirc, .pgpass, .netrc, .git-credentials, SSH keys (id_rsa/id_ed25519/etc.), .pem/.key/.crt/.p12/.pfx/.ppk, wallets, secrets.*, credentials.*. 6 new tests. 698 tests passing. (Inspired by carlrannaberg/claudekit file-guard.)
- [2.3.36] - 2026-04-28 — perf: consolidate shell-wrapper, env-file (Bash), and exfiltration detection into safety.sh — single python3 fork via new safety-detect.py replaces 3 separate hook processes. PreToolUse Bash overhead reduced ~40% (500ms → 297ms per call). env-file-guard remains for Read tool. 15 verification cases passing. 692 tests passing.
- [2.3.35] - 2026-04-28 — perf: fast-path early-exit in env-file-guard, exfiltration-guard, shell-wrapper-guard — skip python3 fork when command lacks trigger keywords (.env, aws/gsutil/rclone/curl/wget/dnscat, python -c / node -e / perl -e / ruby -e). 692 tests passing.
- [2.3.34] - 2026-04-28 — security: add exfiltration-guard hook (PreToolUse Bash) — blocks DNS tunneling tools (dnscat/iodine/dns2tcp) and cloud uploads of sensitive files (.env, ~/.ssh, .pem, id_rsa, /etc/shadow) via aws s3, gsutil, az storage, azcopy, rclone, s3cmd, plus curl/wget upload of sensitive sources. 15 new tests. 692 tests passing. (Inspired by vaporif/parry exfil patterns.)
- [2.3.33] - 2026-04-28 — add precompact-priorities (PreCompact: augments compact prompt with fidelity rules for root causes, exact numbers, file:line refs, subagent findings) + env-file-guard (PreToolUse Bash,Read: blocks reading/editing .env; allows .env.example/template/sample/dist). 22 new tests. 677 tests passing. (Inspired by fcakyon/claude-codex-settings + pchalasani/claude-code-tools.)
- [2.3.32] - 2026-04-27 — fix: install script now copies `lib/*.py` to `~/.claude/supercharger/lib/`. Previously only `utils.sh` and `economy.sh` were synced — `detect_stack.py` was missing, breaking `cwd-changed`, `project-config`, and `statusline` hooks for fresh installs after v2.3.23.
- [2.3.31] - 2026-04-27 — security: add shell-wrapper-guard hook — blocks destructive commands hidden in `python -c "..."`, `node -e "..."`, `perl -e "..."`, `ruby -e "..."`, `dash/ksh/fish -c "..."` wrappers (bash/sh/zsh -c already covered by safety.sh). Path-aware: /tmp, ./dist, node_modules pass through; /, ~, /*, $HOME, .. blocked. 12 tests. 655 tests passing. (Inspired by davila7/claude-code-templates shell-wrapper-guard.)
- [2.3.30] - 2026-04-27 — perf: enforce-pkg-manager.sh collapsed 2 jq + 2 python3 fallback forks into single python3 extraction (~20ms saved per Bash call). 643 tests passing.
- [2.3.29] - 2026-04-27 — security: close compound-command bypass in git-safety.sh (7 ^anchored checks), commit-check.sh, and enforce-pkg-manager.sh (4 ^anchored checks). All PreToolUse Bash hooks now validate per-segment using split_segments. 5 new bypass tests. 643 tests passing.
- [2.3.28] - 2026-04-27 — security: close compound-command bypass in safety.sh — `safe && rm -rf /`, `true; rm -rf /`, `ls || rm -rf /` were previously allowed because rm/mv anchors only matched at command start. Added quote-aware split_segments helper to cmd-normalize.sh; rm/mv now validated per-segment. 5 new bypass tests. 638 tests passing. (Inspired by Anthropic claude-quickstarts/autonomous-coding allowlist approach.)
- [2.3.27] - 2026-04-27 — audit fixes across 6 new hooks: rename NEW_DIR→PROJECT_DIR (cwd-changed), hoist SESSION_ID extraction (permission-denied-advisor), document opt-in mechanism in header (stop-keep-going), standardize URL/path truncation to 80 chars. 633 tests passing.
- [2.3.26] - 2026-04-27 — add stop-keep-going hook (opt-in Stop nudge that detects deferred work patterns like "Should I continue?", "Want me to..."; capped at 3 pokes/session). 633 tests passing.
- [2.3.25] - 2026-04-27 — add subagent-stop-check hook (SubagentStop quality gate; flags failure/incomplete/deferred patterns in last_assistant_message). 625 tests passing.
- [2.3.24] - 2026-04-27 — add tool-failure-advisor (PostToolUseFailure), slow-tool-detector (duration_ms thresholds), permission-denied-advisor (PermissionDenied), cwd-changed (stack re-detection on dir change). 617 tests passing.
- [2.3.23] - 2026-04-27 — consolidate stack detection into lib/detect_stack.py; removes ~250 lines of duplicated inline logic across detect-stack.sh, project-config.sh, statusline.sh; adds Go/Rust/PHP/WordPress detection to statusline and project-config. 588 tests passing.
- [2.3.22] - 2026-04-27 — standardize suppress check via lib-suppress.sh in dep-vuln-scanner, output-secrets-scanner, code-security-scanner, trace-compactor, mcp-output-truncator; batch 7-field python3 extraction in subagent-cost (was 5 separate forks). 588 tests passing.
- [2.3.21] - 2026-04-27 — fix skill-poisoning-scanner false positives (narrow path matching, python3 Unicode check); fix block() JSON escaping + add hookEventName in safety/git-safety; remove dead jq_or_python() from lib-suppress; fix commit-check suppress init order; fix $(pwd)→$PWD in 2 hooks; fix compaction-backup stderr prefix. 588 tests passing.
- [2.3.20] - 2026-04-27 — add auto-compact.sh hook (PostToolUse context advisor with per-band debounce for agentic runs; warns at 70/80/90%); add 15 tests for hook-new scaffold and --register flag. 576 tests passing.
- [2.3.19] - 2026-04-27 — hook-new.sh: add interactive mode, --register flag (auto-adds to settings.json), fix template to use check_hook_disabled and correct PreToolUse block JSON. 561 tests passing.
- [2.3.18] - 2026-04-27 — add 17 tests for hook-doctor and release tools; fix release.sh dry-run to skip test run; fix hook-doctor ISSUES subshell propagation and ls pipefail on empty dirs. 561 tests passing.
- [2.3.17] - 2026-04-27 — add tools/hook-doctor.sh (diagnose broken installs), tools/release.sh (automated release workflow), approval-gate 1-hour TTL for stale pending files. 544 tests passing.
- [2.3.16] - 2026-04-26 — human-approval-gate hook (soft gate for high-risk commands: SQL drops, git reset --hard, terraform destroy, npm publish, docker prune, disk ops — opt-in, pauses for user confirmation before retry); fix block() JSON output in commit-check + enforce-pkg-manager; standardize INPUT→_INPUT + CWD→PROJECT_DIR across 25 hooks; mcp-tracker + session-checkpoint use hook_profile_skip. 544 tests passing.
- [2.3.15] - 2026-04-26 — Expand test coverage to 233 tests: learn-from-blocks, session-memory-write; fix relative REPO_DIR path bug (cd-invariant hook paths).
- [2.3.14] - 2026-04-26 — Expand test coverage to 227 tests: stop-failure, session-checkpoint, session-complete, session-end, mcp-tracker, cost-forecast, failure-tracker, subagent-cost.
- [2.3.13] - 2026-04-26 — tool-call-limiter hook: per-session tool call cap with warn at 80%/block at 100%; configurable via SESSION_MAX_TOOL_CALLS env or .supercharger.json maxToolCalls; read-only tools bypass cap; CLAUDE_SESSION_ID scoping. 210 tests passing.
- [2.3.12] - 2026-04-26 — Complete hook test coverage: 28 new tests for session-memory-inject, learn-from-prompts, cache-health, config-scan; fix env var passing bug in tests (D="$VAR" python3 prefix form). 205 tests passing.
- [2.3.11] - 2026-04-26 — 42 new tests across 14 hooks (repetition-detector, agent-router, agent-gate, economy-reinforce, rate-limit-advisor, context-advisor, budget-cap, thinking-budget, adaptive-economy, trace-compactor, mcp-output-truncator, dep-vuln-scanner, commit-check, stop-verify); fix commit-check regex to allow breaking change syntax (feat!:, fix!:). 177 tests passing.
- [2.3.10] - 2026-04-26 — tools/profile-switch.sh (fixes missing tool referenced in status screen); 23 new tests covering skill-poisoning-scanner, output-secrets-scanner, prompt-injection-scanner, code-security-scanner, scope-guard, smart-approve. 135 tests passing.
- [2.3.9] - 2026-04-26 — Security hardening: re-entry loop detector (catches hook-echo infinite loops); skill poisoning scanner (blocks base64/eval/curl|bash/reverse-shells in loaded skills); per-category security toggles (10 categories: filesystem, database, destructive, network, credentials, persistence, clipboard, browser, history, selfmod) with .supercharger.json disableSecurityCategories support. 112 tests passing.
- [2.3.8] - 2026-04-23 — README: /sc-update in slash commands table; custom hook FAQ with hook-new.sh quickstart. 107 tests passing.
- [2.3.7] - 2026-04-23 — /sc-update slash command (check + apply updates); renamed from /update to avoid Claude Code builtin conflict; /supercharger in post-update banner; builtin conflict audit (no other renames needed). 107 tests passing.
- [2.3.6] - 2026-04-23 — tools/hook-new.sh scaffold (generates boilerplated hook stub); HOOK_AUTHORING.md quick-start section; hook-new.sh in README tools table + supercharger.sh status screen; tests badge corrected to 107. 107 tests passing.
- [2.3.5] - 2026-04-23 — /supercharger command (lists all 18 slash commands by category); README slash commands table updated with /perf, /cache-stats, /cache-clear, /profile, /supercharger. 107 tests passing.
- [2.3.4] - 2026-04-23 — /profile slash command (show/switch performance profile mid-conversation); perf profile shown in tools/supercharger.sh status screen. 107 tests passing.
- [2.3.3] - 2026-04-23 — SUPERCHARGER_PROFILE=fast tier (skips 8 analytics hooks, keeps quality-gate + typecheck + dep-vuln-scanner); /cache-clear slash command + tools/cache-clear.sh with --dry-run. 107 tests passing.
- [2.3.2] - 2026-04-23 — /cache-stats slash command (typecheck/quality-gate cache state); fix CI version mismatch (lib/utils.sh + tools/supercharger.sh were missed in v2.3.0/v2.3.1 bumps). 406 tests passing.
- [2.3.1] - 2026-04-23 — Post-v2.3.0 fixes: atomic cache writes in typecheck + quality-gate (tempfile + os.replace); prune stale cache entries for deleted files on write; per-project profile via .supercharger.json ("profile": "minimal"); /perf slash command (hook timing report with suggestions); SUPERCHARGER_PROFILE docs in README. 406 tests passing.
- [2.3.0] - 2026-04-23 — Hook performance: 7 optimizations across lib-suppress.sh, typecheck.sh, quality-gate.sh, statusline.sh. SUPERCHARGER_PROFILE=minimal env var skips 11 high-latency non-security hooks. sha256 hash-cache in typecheck + quality-gate (skip tsc/lint on unchanged files). $EPOCHREALTIME timing (zero fork). in-memory disabled-hooks cache (eliminates grep fork). economy.md scan skipped when .economy-tier is fresh. jq_or_python() wrapper prevents double fork on jq-less systems. Boris Cherny workflow rules adapted: Demand Elegance, Autonomous Bug Fixing guardrails, staff-engineer verification check. 406 tests passing.
- [2.2.3] - 2026-04-23 — Audit fixes: add missing # Event: headers to 4 hooks (event-logger, git-safety, safety, scope-guard); fix /design + /multi-review + /reflect + agent-handoff-gate from R&D pass; CHANGELOG pre-stable separator to resolve duplicate version tags; 3 new credits (awesome-claude-design, awesome-llm-apps, claude-code-best). 401 tests passing.
- [2.2.2] - 2026-04-23 — Security/correctness audit: fix shell injection in rate-limit-advisor (heredoc interpolation) and subagent-cost (file path interpolation); fix prompt-injection-scanner indentation bug; fix session-checkpoint cost parsing (JSON not line-based); fix PCRE (?i) in grep -E; fix duplicate install step label; proper JSON escaping in test helper; tighten hook-toggle test assertion. 392 tests passing.
- [2.2.1] - 2026-04-22 — Add /interview command (structured requirements gathering with AskUserQuestion, recommended options) and /devlog command (living architecture journal). 392 tests passing.
- [2.2.0] - 2026-04-22 — Slash command overhaul: removed /test, /doc, /refactor (redundant); added /handoff (session resume brief), /security (OWASP review), /stuck (debug loop breaker), /scope (pre-flight gate), /pr (one-step PR). 8 commands total. 388 tests passing.
- [2.1.0] - 2026-04-22 — User-facing improvements: session-analytics --subagents per-agent cost breakdown; per-project hook overrides via disableHooks in .supercharger.json; smarter compaction guidance (session-specific preservation); cost in desktop stop notifications; stop-verify suggests specific test command (npm/pnpm/pytest/cargo) based on stack detection. Performance: lib-suppress.sh timing gated behind profiling sentinel (saves 28ms/hook); budget-cap.sh Python calls 6→2; jq for field extraction in thinking-budget + cost-forecast; .economy-tier cached at SessionStart. 380 tests passing.
- [2.0.1] - 2026-04-22 — Fix budget-cap usage parsing (tool_response.usage nesting); fix session-memory-write crash on clean repos (grep exit 1 with pipefail); compress anti-patterns.yml 856→531 tokens; add 24-scenario end-to-end integration test suite; 369 tests passing.
- [2.0.0] - 2026-04-22 — "Never Be Surprised": 10 new hooks, 1 new tool, 4 upgraded hooks across 3 waves. Wave 1 (Cost Shield): budget-cap with session cost tracking and optional hard stop, cost-forecast before agent spawns, cache-health monitor warns on cache degradation (safe mode), subagent-cost per-agent JSONL logging. Wave 2 (Smart Adaptation): adaptive-economy auto-switches tier at context thresholds with session-history learning, thinking-budget calibrates reasoning depth by task complexity, rate-limit-advisor warns when projected exhaustion <30m with statusline burn projection. Wave 3 (Session Intelligence): session-checkpoint crash-resilient state on every file change, enhanced session-memory-inject with checkpoint recovery + diff/cost/failures enrichment, hook-perf CLI profiler. Shared: lib-suppress.sh timing instrumentation, project-config.sh parses budget/autoEconomy/thinkingControl/forecastTurnsPerAgent. Statusline: budget display line 3, cache health coloring line 2, burn rate projection. Hook counts: safe 10 (+1), full+dev 64 (+10). 345 tests passing (+52), 0 failures.
- [1.0.6] - 2026-04-21 — Session analytics: daily cost/cache rollup + per-project breakdown (session-analytics.sh); 7d summary in claude-check.sh; remove confusing guardrails-template.yml line from health check
- [1.0.5] - 2026-04-21 — Fix project-scope .supercharger-debug not working: $PWD unreliable in hook context; refactor lib-suppress.sh with init_hook_suppress(dir) function; all 12 hooks now re-call with actual project dir after reading stdin; session-memory-inject now reads stdin for cwd
- [1.0.4] - 2026-04-21 — Fix UserPromptSubmit/SubagentStart hooks showing [CTX] banner in UI; switch to hookSpecificOutput.additionalContext for silent injection; systemMessage reserved for infrequent events (SessionStart, PostCompact, FileChanged)
- [1.0.3] - 2026-04-21 — Hook output suppressed by default (suppressOutput:true); debug flag to re-enable: ~/.claude/supercharger/scope/.debug-hooks (global) or .supercharger-debug (project); lib-suppress.sh shared helper; README debug FAQ entry
- [1.0.2] - 2026-04-21 — Fix all hook JSON output schemas (systemMessage replaces invalid hookSpecificOutput/additionalContext); config health score in claude-check (0-100); fix hardcoded version in claude-check; bump-version now covers plugin files
- [1.0.1] - 2026-04-20 — Tests for file-watcher/event-logger/dep-vuln-scanner (287 total); HOOK_AUTHORING.md; CONTRIBUTING.md; Git Bash md5sum order fix
- [1.0.0] - 2026-04-20 — Initial stable release: 52 hooks, statusline (eco tier, mem restore, scan alerts), 9 agent types, adaptive token economy, code/secrets/injection scanners, session memory, MCP profiles, CVE-2025-59536 guard

### Pre-stable Releases (development numbering — predates stable v1.0.0)

- [3.6.11] - 2026-04-19 — Add Claude Code marketplace plugin metadata; dead-code carveout anti-pattern; fix hook counts in tests
- [3.6.10] - 2026-04-19 — Add session memory (writes .claude/supercharger-memory.md on Stop, injects at SessionStart)
- [3.6.9] - 2026-04-19 — Add project-verify hook (.claude/verify.sh runs on Stop, feeds failures back); compress subagent safety injection 26→4 lines
- [3.6.8] - 2026-04-19 — Fix credential leakage in blocked-commands log; redact PASSWORD/TOKEN/SECRET before logging; truncate to 120 chars; reduce injection cap 15→10
- [3.6.7] - 2026-04-19 — Compaction instructions, skill trigger table, cache-ordered economy.md, MCP output truncator, supercharger.md lazy-load
- [3.6.6] - 2026-04-19 — MCP profile tiers (light/dev/research/full), paths: lazy-loading for role rules, ~5k token/session reduction
- [3.6.5] - 2026-04-19 — Add rubber-duck, diff-preview, teach-me opt-in rules
- [3.6.4] - 2026-04-16 — Opt-in checkpoint mode, humanized README, OpenCode port plan
- [3.6.3] - 2026-04-15 — CVE-2026-35021 file path check, obfuscation detection, role anti-patterns, smart-approve expansion, statusline resilience
- [3.6.2] - 2026-04-15 — Self-teaching: 30-day log rotation, dedup, capped 15-entry injection; smart-approve Write/Edit in project dir
- [3.6.1] - 2026-04-15 — Smart-approve: Write/Edit in project dir, npm run/build/dev, build tools, script runners; statusline resilient 3-line output
- [3.6.0] - 2026-04-15 — Optimize all 9 agents: add color, example blocks, fix tools (researcher+web, general+bash), planner haiku→sonnet
- [3.5.9] - 2026-04-15 — Fix CI: statusline tests for 3-line output, actions/checkout v5, time display hours fix
- [3.5.8] - 2026-04-15 — Agent name normalization in statusline (safety net), simplified rate limit format
- [3.5.7] - 2026-04-15 — Normalize dispatched agent name (dash→space, title case), Agent: label in statusline
- [3.5.6] - 2026-04-15 — 3-line statusline with labels, Agent: prefix, Usage: Session/Weekly format, agent-gate multi-field detection
- [3.5.5] - 2026-04-15 — Fix statusline line 2 vanishing (rate limits type error), idle notification 60s cooldown
- [3.5.4] - 2026-04-15 — Fix false idle notifications: 60s cooldown, filter transient states
- [3.5.3] - 2026-04-15 — Fix statusline token math (input-only context, session cumulative output), project-scoped stack cache, agent-gate re-registration
- [3.5.2] - 2026-04-15 — Fix agent-gate re-registration for correct dispatched agent in statusline; credit token-optimizer and CCNotify
- [3.5.1] - 2026-04-15 — Statusline: exact context size, rate limits with countdown, lines changed; reread-detector mtime check; token economy CLAUDE.md improvements; README update
- [3.5.0] - 2026-04-15 — Token optimization: loop detector (catches repeated tool calls, saves 10-50K tokens) and re-read detector (nudges Claude to use cached file knowledge)
- [3.4.0] - 2026-04-15 — Code security scanner: warns on eval(), innerHTML, SQL injection, pickle, hardcoded secrets, weak crypto in Write/Edit content
- [3.3.2] - 2026-04-13 — Fix statusline null-safe .get() chains, remove app-switching from notifications, tighten learning false positives
- [3.3.1] - 2026-04-13 — 3 notification types (task complete, input needed, permission request), idle cooldown fix, README update, credit claude-code-warp
- [3.3.0] - 2026-04-12 — Enhanced self-teaching: positive reinforcement detection, repeated failure tracker with live nudge, 4-signal learning system
- [3.2.1] - 2026-04-12 — Session-scoped agent/MCP scope files — multiple Claude sessions no longer share agent names in statusline
- [3.2.0] - 2026-04-12 — 3-layer injection defense: SessionStart config scan + PostToolUse output secrets scanner, smart-approve persistent session rules, /effort and subagent model tips
- [3.1.0] - 2026-04-12 — Self-teaching: learn from blocked commands + user corrections, MCP server name in statusline, structured deny reasons, verify-on-stop, statusline token/cache fix
- [3.0.7] - 2026-04-12 — /permissions wildcard tip in README, verify-on-stop hook, statusline cached token fix
- [3.0.6] - 2026-04-12 — Warn-only Stop hook (alerts when files modified but no test/build ran), statusline token count fix (cached tokens included), structured deny reasons
- [3.0.5] - 2026-04-12 — Fix statusline token count (include cached tokens), remove broken Stop prompt hook, structured deny reasons in safety/git-safety, notification matcher filter
- [3.0.4] - 2026-04-12 — LLM-evaluated Stop hook for verification, structured deny reasons in safety/git-safety, notification matcher filter, smart-approve decision reasons
- [3.0.3] - 2026-04-09 — Fix update.sh hang, quality-gate lint loop early-break, shellcheck SC2259 fix, all CI green
- [3.0.2] - 2026-04-09 — Fix notify.sh RCE, bash-native regex in git-safety/enforce-pkg-manager/safety.sh, jq-first in scope-guard/project-config, dedup update-check, injection scanner grep consolidation, compaction-backup rotation
- [3.0.1] - 2026-04-09 — Performance: grep consolidation (~36 forks eliminated in safety.sh), bash-native regex in agent-router, fix audit-trail POSIX regex bug, fix quality-gate race condition, statusline token display improvements
- [3.0.0] - 2026-04-09 — Major pruning: 24→17 hooks, 3→2 install modes, forced agent dispatch removed, 7 tools cut, context-monitor+adaptive-economy merged
- [2.0.17] - 2026-04-09 — v1.7: adaptive economy, session analytics CLI, config health score tool
- [2.0.16] - 2026-04-09 — v1.6 Intelligence Layer: context budget monitor, trace compactor, prompt injection scanner
- [2.0.15] - 2026-04-08 — Economy tier injected into every prompt context; GitHub MCP uses gh extension; quality-gate eslint glob fix
- [2.0.14] - 2026-04-08 — Fix statusline showing classifier name instead of dispatched agent (.agent-classified / .agent-dispatched split)
- [2.0.13] - 2026-04-08 — New hooks: PermissionRequest smart-approve, SubagentStart safety injection, SessionEnd cleanup; git-safety rewrites force-push instead of blocking
- [2.0.12] - 2026-04-08 — Fix economy tier detection in update.sh (loose substring → Active Tier heading regex)
- [2.0.11] - 2026-04-08 — Deploy tools/ and lib/ to install target so economy-switch runs without local repo
- [2.0.10] - 2026-04-08 — Audit log redaction expanded, macOS CI runner, shellcheck lib/tools/tests, agent name normalization (title case, dash→space)
- [2.0.9] - 2026-04-08 — Fix awk field variable bug in project agent parsing, 273 passing
- [2.0.8] - 2026-04-08 — Fix agent-gate mismatch detection regression, test suite green
- [2.0.7] - 2026-04-08 — Fix project agent CWD resolution and statusline agent name
- [2.0.6] - 2026-04-08 — Project agent priority routing in agent-router.sh
- [2.0.5] - 2026-04-07 — Refactor: shared cmd-normalize, dynamic uninstall command list
- [2.0.4] - 2026-04-07 — Consistency audit: hook safety, install accuracy, version placeholder
- [2.0.3] - 2026-04-07 — Stack assumption verification, .claudedocs gitignored
- [2.0.2] - 2026-04-07 — Stabilization: per-step token display, redundant safety rules removed, MCP deferred loading confirmed
- [2.0.1] - 2026-04-07 — Performance: jq fallback, background quality-gate, stack cache, daily audit rotation
- [2.0.0] - 2026-04-07 — New features: conventional commits, GitHub MCP, /test, /doc, safety improvements
- [1.9.8] - 2026-04-07 — Notification filtering, statusline updates, install step count fix
- [1.9.7] - 2026-04-07 — Desktop notification prompt in installer
- [1.9.6] - 2026-04-07 — Statusline per-prompt token display with in/out breakdown
- [1.9.5] - 2026-04-07 — Session token accumulation, statusline prompt/session display
- [1.9.4] - 2026-04-07 — Token usage display in statusline, install detection, feature doc rewrite
- [1.9.3] - 2026-04-06 — README rewrite, agent gate fix, examples accuracy
- [1.9.2] - 2026-04-06 — Context size reduction, README accuracy fixes
- [1.9.1] - 2026-04-06 — README accuracy fixes, update integrity, cost feedback loop
- [1.9.0] - 2026-04-06 — Hook JSON key fix, echo pipe safety
- [1.8.0] - 2026-04-06 — Enforced agent routing
- [1.7.6] - 2026-04-06 — Scope Guard hook, hook count fix
- [1.7.5] - 2026-04-06 — Auto-update banner, sound-only notifications
- [1.7.4] - 2026-04-06 — update.sh: detect and preserve config silently
- [1.7.0] - 2026-04-03 — Custom Commands, Architect agent, reviewer hierarchy
- [1.6.0] - 2026-04-02 — 8 Focused Agents, Stack Detection, Project Agent Scaffolder
- [1.5.0] - 2026-04-02 — Profile System, Project-Level Config, Team Presets
- [1.4.0] - 2026-04-02 — Enhanced Statusline, 3 New Roles, Config Validation
- [1.3.0] - 2026-04-02 — Package Manager Enforcement, Quality Gate, Audit Trail
- [1.2.0] - 2026-04-01 — Session Summary, Resume Tool
- [1.1.0] - 2026-04-01 — Tiered Token Economy
- [1.0.0] - 2026-03-31 — Initial Release

---

## Pre-stable Detailed Notes (development era — predates stable v1.0.0)

## [2.0.9] - 2026-04-08

### Fixed
- **Project agent parsing** — `parse_agent_field` in `agent-router.sh` was not passing the `field` variable to awk (`-v field="$field"` missing). `name` and `description` were never extracted from agent frontmatter — project agents were silently never detected. Smoke tests caught this.

### Added
- **Agent routing smoke tests** — `tests/test-agent-routing-project.sh` covers: project agent injection, fallback when no agents dir, skipping nameless agents, `workspace.current_dir` priority over `$PWD`, description truncation and JSON validity. 273 passing, 0 failing.

---

## [2.0.8] - 2026-04-08

### Fixed
- **agent-gate mismatch detection** — route file was overwritten with dispatched agent before mismatch check, so warning never fired. Now reads stored route first, then updates file. Mismatch warnings restored.
- **Test suite** — `test-economy.sh` PM row assertion updated to match renamed `Project Manager` table entry. 253 passing, 0 failing.
- **README test badge** — corrected to 253 (actual passing count).

---

## [2.0.7] - 2026-04-08

### Fixed
- **Project agent CWD resolution** — `agent-router.sh` was using `$PWD` to locate `.claude/agents/`, which resolves to the hook process directory, not the open project. Now parses project path from hook JSON payload (`workspace.current_dir` / `cwd`), falling back to `$PWD`. Project agents now auto-activate correctly.
- **Statusline agent name** — `agent-gate.sh` now updates the route file on every agent dispatch, not just the first. Statusline now shows the actual dispatched agent (e.g., `shopify-integration-engineer`) instead of the global pre-classification.

---

## [2.0.6] - 2026-04-08

### Added
- **Project agent priority routing** — `agent-router.sh` now detects `.claude/agents/` in the current project, parses `name` and `description` from each agent's frontmatter, and injects them into `additionalContext` with an explicit precedence signal. Project agents take priority over global classification when they better fit the task. Conflict rule: if a project agent and global agent would both handle the same request, the project agent wins. Falls back to global routing when no project agents are present.

---

## [2.0.5] - 2026-04-07

### Fixed
- **Uninstall completeness** — `uninstall.sh` now derives command removal list dynamically from `configs/commands/*.md`; `/test` and `/doc` are no longer left behind after uninstall

### Changed
- **Shared normalization** — extracted 7-line command normalization block into `hooks/cmd-normalize.sh`; `safety.sh`, `git-safety.sh`, `enforce-pkg-manager.sh`, and `commit-check.sh` now source it

---

## [2.0.4] - 2026-04-07

### Fixed
- **Version placeholder** — `configs/universal/CLAUDE.md` now uses `{{VERSION}}` instead of hardcoded `v1.8.0`; substituted at install time alongside `{{ROLES}}` and `{{MODE}}`
- **Silent hook failures** — `quality-gate.sh` and `prompt-validator.sh` now capture stdin before parsing; missing `python3` no longer causes all checks to silently pass
- **Hook consistency** — `agent-gate.sh` aligned to jq-first + python3 fallback pattern; `notify.sh`, `session-complete.sh`, `update-check.sh` updated to `set -euo pipefail`
- **Install accuracy** — step counter now shows "Step 3 of 6" for economy tier; summary derives command names dynamically from `configs/commands/`
- **Block message format** — `enforce-pkg-manager.sh` aligned to multi-line Reason/Command format used by all sibling hooks
- **Test badge** — corrected from 253 to 207

---

## [2.0.3] - 2026-04-07

### Fixed
- **Stack assumption verification** — SessionStart message now prompts Claude to ask before proceeding if any detected stack assumptions seem wrong.
- **Gitignore** — added `.claudedocs/` to prevent per-user audit reports from being committed.

---

## [2.0.2] - 2026-04-07

### Changed
- **Statusline token display** — settled on per-step tokens with in/out breakdown after 3 accumulation approaches proved unreliable due to statusline rendering architecture. Simple, accurate, real-time.
- **CLAUDE.md safety rules** — replaced 3 redundant lines with 1: "Destructive commands are blocked at the shell level." Hooks enforce these already.
- **README context cost** — clarified MCP tool definitions are deferred by default in Claude Code 2.x (no hidden overhead).
- **MCP deferred loading** — confirmed already active by default. No config change needed or possible from settings.json.

---

## [2.0.1] - 2026-04-07

### Performance
- **jq-first JSON parsing** — safety.sh, git-safety.sh, enforce-pkg-manager.sh, commit-check.sh now try `jq` (~5ms) before falling back to `python3` (~35ms). Saves ~90ms per Bash tool call.
- **agent-router.sh** — merged 2 python3 calls into 1 (jq for stdin, printf for JSON output). Saves ~35ms per prompt.
- **quality-gate.sh background execution** — linters now run in a background subshell. Hook returns immediately. Eliminates 300-2000ms blocking per Write/Edit call.
- **Linter timeout** — all linter invocations prefixed with 30s timeout (gtimeout/timeout). Prevents indefinite stalls on large projects.
- **audit-trail.sh daily rotation** — `find -mtime +30 -delete` now gated behind daily timestamp check instead of running on every tool call.
- **Stack detection cache** — project-config.sh writes detected stack to `.stack-cache` at SessionStart. statusline.sh reads from cache instead of re-parsing package.json on every render.

---

## [2.0.0] - 2026-04-07

### Added
- **Conventional commit enforcement** — new `commit-check.sh` hook blocks non-conventional commit messages (`feat:`, `fix:`, `chore:`, etc.). Handles `-m "..."`, `-m '...'`, and HEREDOC patterns. Allows `--amend` and merge commits.
- **GitHub MCP server** — auto-installed for developer role. Uses `@modelcontextprotocol/server-github` via npx. Works zero-config with `gh` CLI auth.
- **/test command** — generate unit tests with framework detection, coverage targets, and automatic test execution.
- **/doc command** — generate documentation with style detection (JSDoc, docstrings, rustdoc) and scope inference.
- **Generalist agent fallback** — unmatched prompts now route to Steve Jobs (Generalist) instead of getting no agent.

### Fixed
- **Package manager bypass** — `sudo npm install` in pnpm project was not blocked. Added prefix stripping (sudo/command/env) matching safety.sh pattern.
- **Git safety gaps** — added blocks for `git branch -D main/master`, `git clean -f`, `git stash drop`, `git stash clear`, and `git checkout -- .` variant.
- **Commit-check HEREDOC handling** — uses Python regex to extract messages from HEREDOC patterns, not just simple `-m "..."` strings.

---

## [1.9.8] - 2026-04-07

### Fixed
- **Phantom notifications** — `notify.sh` was firing on all 7 Claude Code notification types. Now filters to only `idle_prompt` (Claude waiting) and `worker_permission_prompt` (subagent needs permission). Silently exits for auth, computer-use, and elicitation events. Uses payload's message field instead of hardcoded string.
- **Install step count** — updated from "4 of 4" to "5 of 5" and README from "Four questions" to "Five questions" (notification prompt was added in v1.9.7).
- **README statusline description** — now mentions active agent display and per-prompt token usage with in/out breakdown.

---

## [1.9.7] - 2026-04-07

### Added
- **Desktop notification prompt** — installer now asks users to choose notification mode: On (popup), Sound (beep only), or Off. Applies via flag files used by `notify.sh`. Also available as `--notify on|off|sound` CLI arg for non-interactive installs. Notification preference shown in install summary.

---

## [1.9.6] - 2026-04-07

### Changed
- **Statusline token display** — shows per-prompt tokens with input/output breakdown: `180 tok (1 in / 179 out)`. Removed session accumulation (was delayed by one render, confusing to users). Cost display still tracks session total.

---

## [1.9.5] - 2026-04-07

### Fixed
- **Session token accumulation** — statusline renders multiple times per response; token counts were duplicated on each re-render. Now tracks last-seen values and only accumulates on new responses.
- **Statusline shows both session and prompt tokens** — `session: 1.2K tok | prompt: 180 tok` format replaces the single combined display.
- **Session token cleanup** — `.session-tokens` file cleared on session end via scope-guard.sh.

---

## [1.9.4] - 2026-04-07

### Added
- **Token usage in statusline** — shows total tokens with input/output breakdown (e.g. `1.2K tok (1.1K in / 96 out)`). Updates per response.
- **Full agent name in statusline** — shows `Agent: Sherlock Holmes (Detective)` instead of just `Sherlock`.
- **Install detection** — `install.sh` detects existing installation and offers Update (preserves config) vs Reinstall. Non-interactive installs bypass the prompt.

### Fixed
- **Statusline syntax error** — nested double quotes in a Python comment inside `python3 -c` block broke bash quoting. Caused statusline to disappear after install.
- **MCP setup prompt** — no longer blocks non-interactive installs (full args provided).

### Changed
- **Feature recommendations doc** — rewrote entirely. Removed 11 items that already exist, removed hallucinated URLs, added 11 genuine recommendations with effort/risk/context-cost assessment.

---

## [1.9.3] - 2026-04-06

### Changed
- **README rewrite** — restructured around honest value hierarchy. Safety layer presented as the core product; agents, roles, economy tiers clearly labeled as instructional (prompt-based, not enforced). Removed marketing language and unverifiable claims.
- **Agent gate** — changed from hard block (exit 2) to advisory warning (exit 0). Session routing still works via the system message directive; the gate no longer prevents legitimate subtask dispatches (e.g., spawning a Critic for code review during a Writer-routed session).

### Fixed
- **Agent name labels** — all 8 agent routing examples now match source code names exactly: (Detective), (Critic), (Engineer), (Writer), (Scientist), (Architect), (Strategist), (Analyst).
- **SSH keys claim** — scoped from "SSH keys" to specific commands blocked (`ssh-keygen`, `ssh-add`, `ssh-copy-id`).
- **Block message format** — 3 examples in docs/examples.md now match actual hook output (`"Supercharger blocked this command.\n  Reason: ..."` instead of single-line format).
- **Compaction summary claim** — examples.md now states summary is "prompted, not enforced."

---

## [1.9.2] - 2026-04-06

### Changed
- **Context size reduction** — reduced per-conversation token load by ~1,200 tokens (24%). guardrails.md: removed rules duplicated in CLAUDE.md (761 chars saved). supercharger.md: compressed deep interview, session summary, memory block, removed duplicate anti-pattern section (3,214 chars saved). anti-patterns.yml: consolidated overlapping patterns (804 chars saved). All 8 role files: removed Token Efficiency footers already defined in economy.md (~640 chars saved).

### Fixed
- **README rm -rf claim** — now specifies which targets are blocked (root, home, parent traversal), not "all rm -rf".
- **README quality gate claim** — now states conditionality: Developer role, Standard/Full install mode.
- **README agent fallback example** — replaced non-matching Steve Jobs example with a working Sun Tzu pattern.
- **README zero-dependency claim** — scoped to "core install"; added note that MCP servers use npx at runtime.
- **README compaction backup claim** — accurately describes hook saving raw transcript; structured summary is prompted, not guaranteed.

---

## [1.9.1] - 2026-04-06

### Fixed
- **README MCP table** — Designer role was incorrectly listed alongside Developer for Playwright. Designer only receives Magic UI; Playwright is Developer-only. Split into two rows.
- **README economy claims** — Removed unverifiable percentage reduction figures (`~45%`, `~60%`). Economy tiers are prompt instructions, not enforced constraints. Column renamed from "Reduction" to "Target"; values updated to intent language (`concise output`, `minimal output`, etc.).
- **README economy headline** — "cuts your costs in half" replaced with "instructs Claude to prioritize concise output".
- **`tools/update.sh` integrity** — Added GitHub API commit SHA verification before executing `install.sh` from cloned repo. Mismatch aborts update and cleans up temp directory.

### Added
- **Session cost feedback loop** — `hooks/session-complete.sh` now persists session cost and active economy tier to `~/.claude/supercharger/.last-session-cost` on every Stop event. `hooks/project-config.sh` reads this at SessionStart and injects "Last session cost: $X (economy: lean)" into Claude's system context, giving a live signal instead of a static promise.

---

## [1.9.0] - 2026-04-06

### Fixed
- **Critical hook JSON key bug** — `safety.sh`, `git-safety.sh`, and `enforce-pkg-manager.sh` were reading `input.command` instead of `tool_input.command`. All three safety hooks were silently passing every command through (read empty string, exited 0). Also fixed `input.file_path` → `tool_input.file_path` in `quality-gate.sh`, `audit-trail.sh`, and `scope-guard.sh` check mode.
- **echo pipe safety** — replaced `echo "$VAR" | grep/python3` with `printf '%s\n' "$VAR"` across all 7 affected hooks to prevent flag injection when variable content starts with `-n` or `-e`.
- **Test JSON format** — updated `tests/helpers.sh` `run_hook()` and all inline hook assertions in `tests/test-hooks.sh` to use `tool_input.*` keys, matching actual Claude Code hook protocol.

---

## [1.8.0] - 2026-04-06

### Added
- **Agent routing** — `agent-router.sh` (UserPromptSubmit) classifies the first prompt using ordered regex rules and injects a mandatory routing directive into Claude's context. Covers 8 agent patterns; ambiguous prompts fall through silently.
- **Agent gate** — `agent-gate.sh` (PreToolUse/Agent) enforces the classification: blocks dispatch of the wrong agent (exit 2). If no route was set by the router, latches on the first agent Claude dispatches and enforces from there. Achieves ~99% correct routing without any user behavior change.
- **13 new tests** — `tests/test-agent-router.sh` (9 cases) and `tests/test-agent-gate.sh` (6 cases).

### Fixed
- `scope-guard.sh` clear mode now also removes `.agent-route` so routing state resets cleanly on session end.
- Regex priority: `write a function/test/class/script` now correctly routes to Tony Stark (Engineer) before the generic `write` pattern reaches Ernest Hemingway (Writer).
- Routing patterns extended: `add a`, `should I use`, `should I go with` now match correctly.
- README routing examples corrected to match actual regex behavior.
- Install test hook count assertions updated (standard: 13, full: 17).

---

## [1.7.6] - 2026-04-06

### Added
- **Scope Guard hook** — `scope-guard.sh` runs in three modes: `snapshot` (SessionStart), `contract` (UserPromptSubmit), `check` (PostToolUse). Warns when writes exceed declared scope.

### Fixed
- `count_installed_hooks` was undercounting by 3 in standard mode and 1 in full mode (missing scope-guard entries and scope-guard clear).

---

## [1.7.5] - 2026-04-06

### Added
- **Auto-update banner** — `update-check.sh` hook prints a banner at SessionStart when a newer version is available (checks once per 24 hours, non-blocking).
- **Sound-only notification mode** — notify hook supports sound-only output without desktop popup.

### Changed
- `--check` flag now shows changelog summary.

---

## [1.7.4] - 2026-04-06

### Fixed
- `update.sh` no longer re-runs the full installer on update — detects installed mode and preserves user config silently.

---

## [1.7.0] - 2026-04-03

### Added
- **4 Custom Commands** — `/think`, `/refactor`, `/challenge`, `/audit`. Reusable slash-command workflows installed to `~/.claude/commands/` on every install.
  - `/think [problem]` — structured 5-step reasoning: clarify → inventory → hypotheses → stress-test → decide
  - `/refactor [target]` — systematic code quality analysis across 7 dimensions (complexity, duplication, naming, error handling, coupling, testability, dead code)
  - `/challenge [decision]` — adversarial stress-test: assumptions → failure modes → strongest alternative → blind spots → verdict
  - `/audit [target]` — inconsistency sweep across naming, patterns, documentation, interfaces, and structure
- **Architect agent** — global (`~/.claude/agents/architect.md`) + project template (`configs/project-agent-templates/architect.md`). Design-before-code specialist: produces design plans with explicit decisions and rejected alternatives. Does NOT write implementation code.
- **Architect added to all project scaffolds** — `tools/init-agents.sh` now includes architect in every stack's agent set (after orchestrator)
- **Evidence threshold in debugger** — both global and project template: must have exact error + source line + 2-level call chain before forming any hypothesis
- **Reviewer RULE 0/1/2 hierarchy** — both global and project template: production safety > conformance > structural quality. Replaces generic CRITICAL/SHOULD/CONSIDER.
- **Failure-mode reasoning** — reviewer findings now require "When X fails, Y happens, resulting in Z" — not vague "this could cause issues"
- **Thinking economy** — added to code-helper, general, debugger, and implementation project agents (frontend, backend, systems). Output conclusions only.
- **Cleanup attestation** — added to done checklists: code-helper, frontend-engineer, backend-engineer, systems-engineer. No debug statements in submitted code.
- **`tools/init-context.sh`** — scaffolds `CLAUDE.md` index stubs in subdirectories. Skips node_modules/dist/build/vendor. Keeps stubs under 200 tokens.
- 23 new tests (227 total): architect file + frontmatter, commands existence + content, reviewer severity model, evidence threshold, project template upgrades, commands on install

### Changed
- `install.sh` now deploys `configs/commands/*.md` to `~/.claude/commands/`
- `install.sh` deploys `architect.md` as part of agent set (9 agents total)

## [1.6.0] - 2026-04-02

### Added
- **8 Focused Agents**: Auto-installed to `~/.claude/agents/` — `code-helper`, `debugger`, `writer`, `reviewer`, `researcher`, `planner`, `data-analyst`, `general`. Each has a focused description so Claude Code invokes the right agent automatically based on task type. No selection required.
- **First-Run Welcome**: On first session after install, Claude introduces Supercharger in plain English — guardrails, verification, lean responses. Fires once, never repeats.
- **Always-On Stack Detection**: `project-config` hook now detects stack (Node/TypeScript/React, Python/Django/FastAPI, WordPress, Rust, Go, PHP) on every session start and silently tells Claude — no `.supercharger.json` required.
- **Statusline Stack Indicator**: Line 1 of the status bar now shows detected stack (e.g. `[sonnet] my-project | master | TypeScript, React`)
- **Human-Readable Hook Messages**: Blocked commands now show plain-English reason + "Tell me to confirm if you want to proceed" — no raw error strings
- **Project Agent Scaffolder**: `bash tools/init-agents.sh` — auto-detects stack, scaffolds `.claude/agents/` with project-specific agents (orchestrator, frontend-engineer, backend-engineer, debugger, code-reviewer, qa-engineer, systems-engineer). Supports `--force`, `--stack`, `--dir` flags. Merge/Replace/Cancel if agents already exist.
- **Upgraded Global Agents**: All 8 global agents rewritten with production-quality structure — Own/Read-only/Forbidden scope sections, numbered safety-first rules (Rule 0=security/safety), escalation blocks, done checklists. Reviewer uses opus, planner uses haiku.
- 64 new tests (204 total): agent file existence, frontmatter validation, model assignments, first-run welcome, welcome flag creation, no-repeat logic, stack detection via project-config, human-readable block messages, agent deploy on install

### Changed
- `project-config` hook always runs (previously exited early with no `.supercharger.json`)
- `safety.sh` and `git-safety.sh` block messages restructured: `Reason:` label, command echo, confirmation instruction
- install.sh deploys agents from `configs/agents/` to `~/.claude/agents/`

## [1.5.0] - 2026-04-02

### Added
- **Profile System**: Bundle role + economy + MCP into named profiles. 5 built-in (frontend-dev, backend-dev, data-analyst, tech-writer, team-lead) + custom profiles. `bash tools/profile-switch.sh <name>`
- **Project-Level Config**: `.supercharger.json` in project root auto-applies roles, economy, and project hints on session start via SessionStart hook
- **Team Presets**: Export/import config as `.supercharger` files. `bash tools/export-preset.sh` / `bash tools/import-preset.sh`
- **Onboarding Mode**: First-time users get a welcome guide during install explaining what each step does
- `project-config` SessionStart hook added to standard+ mode
- 7 new tests (140 total)

### Changed
- Standard mode now includes `project-config` hook (7 hooks for standard+developer, was 6)
- claude-check shows active profile and detects `.supercharger.json` in current directory
- claude-check hook list includes `project-config`
- claude-check role loops check all 8 roles (was 5)

## [1.4.0] - 2026-04-02

### Added
- **Enhanced Statusline**: 2-line status bar showing model, project, git branch, context usage bar (color-coded), session cost, duration, and prompt cache hit rate
- **Stack Auto-Detection**: Detects language, framework, package manager, test framework, and build tool from project files (Python, JS/TS, Rust, Go ecosystems)
- **3 New Roles**: Designer (UI/UX, accessibility, design systems), DevOps (IaC, Docker, CI/CD, security scanning), Researcher (citations, methodology, evidence-based)
- **Config Validation**: claude-check lints empty rule files, oversized CLAUDE.md, non-executable hooks, syntax errors in hook scripts, malformed settings.json
- **MCP Usage Tips**: Post-install cheat sheet showing example prompts for installed MCP servers
- Designer gets Magic UI MCP server; DevOps and Researcher get DuckDuckGo Search
- 15 new tests (133 total)

### Changed
- Roles expanded from 5 to 8 (added Designer, DevOps, Researcher)
- Economy constraints added for new roles: Designer/DevOps unrestricted, Researcher floors at Standard
- Mode switching updated for 8 roles in CLAUDE.md template
- claude-check updated with statusline check, stack detection, config validation sections, version 1.4.0

## [1.3.0] - 2026-04-02

### Added
- **Package Manager Enforcement**: PreToolUse hook blocks wrong package manager based on lockfile detection (pnpm-lock.yaml, yarn.lock, uv.lock, poetry.lock, bun.lockb)
- **Quality Gate Pipeline**: PostToolUse hook runs 3-stage lint→auto-fix→re-check after every edit (ruff, eslint, clippy, rustfmt, gofmt, Prettier, Black)
- **Mutation Audit Trail**: PostToolUse hook logs all mutations (file edits, git commits, installs) to JSONL with 30-day rotation at `~/.claude/supercharger/audit/`
- **Hook Toggle Tool**: `bash tools/hook-toggle.sh safety off` — enable/disable any hook without editing JSON
- **Credential Leak Detection**: Safety hook blocks API keys, AWS AKIA patterns, GitHub `ghp_` tokens, OpenAI `sk-` keys in commands
- **SSH Key Operation Blocking**: Safety hook blocks `ssh-keygen`, `ssh-add`, `ssh-copy-id`
- **Shell Profile Protection**: Safety hook blocks writes to `.bashrc`, `.zshrc`, `.profile`, `.bash_profile`
- **Self-Modification Prevention**: Safety hook blocks agent from writing to `.claude/settings.json` or `.claude/CLAUDE.md`
- **Stop Conditions Framework**: Guardrails now include start/target state, checkpoints, forbidden actions, and human review triggers
- **Deep Interview expanded**: 4→9 dimensions (added Input, Output, Audience, Memory, Examples) with Critical vs Conditional scoring
- **Enhanced Verification Gate**: 4-level check — Existence → Substantive → Wired → Functional
- **Memory Block Template**: Structured context carry-forward format for multi-turn tasks after compaction
- 10 new prompt validator checks (11-20): output format, implicit length, file scope, negative constraints, starting state, template mismatch, role/persona, unscoped "all", version pinning, error context
- 25 new tests (118 total)

### Changed
- Safety hook expanded with 4 new blocking categories (credentials, persistence, self-modification, production reads)
- Prompt validator expanded from 10 to 20 checks
- Developer role hook changed from `auto-format` to `quality-gate` (3-stage pipeline replaces single formatter)
- Standard mode now includes `enforce-pkg-manager` and `audit-trail` hooks (6 hooks total, was 4)
- Install modes description updated (Standard now mentions quality gate, pkg enforcement, audit trail)
- claude-check updated with new hook names and v1.3.0 version

## [1.2.0] - 2026-04-01

### Added
- **Enhanced clarification mode**: Lightweight scan on all prompts + scored deep interview (4 dimensions, threshold-based questioning)
- **Session summary**: Structured handoff block with decisions, files changed, and paste-ready resume prompt
- **Auto-summary triggers**: Fires on "session summary" keyword, context compaction, and rate limits
- **Resume tool**: `bash tools/resume.sh` — shows latest summary, copies resume prompt to clipboard
- **Resume --list/--show**: Browse and view past session summaries
- **Summaries directory**: `~/.claude/supercharger/summaries/` — created by compaction hook
- 7 new tests for resume tool (93 total)

### Changed
- Clarification Mode in supercharger.md upgraded from 4 bullets to two-tier system (lightweight + deep interview)
- Session Handoff now references Session Summary format
- Compaction backup hook creates summaries directory alongside transcript backup
- claude-check shows session summary count and latest file
- Uninstaller cleans up summaries directory

## [1.1.0] - 2026-04-01

### Added
- **Tiered token economy**: Standard (~30%), Lean (~45%), Minimal (~60%) reduction tiers
- **5 output types**: Code, Commands, Explanation, Diagnosis, Coordination — each with per-tier rules
- **Role-aware constraints**: Student floors at Standard, Writer floors at Standard, Student ceiling at Lean
- **Mid-conversation switching**: "eco standard", "eco lean", "eco minimal" keywords
- **Economy selection at install**: New installer step after role selection
- **Post-install switching**: `bash tools/economy-switch.sh [tier]` CLI tool
- **Universal output rules**: 7 always-on rules (no ceremony, no restating, lead with deliverable)
- New file: `configs/universal/economy.md` — single source of truth for token economy
- New file: `lib/economy.sh` — tier selection, validation, deployment logic
- New file: `tools/economy-switch.sh` — CLI for changing tiers after install
- New files: `configs/economy/standard.md`, `lean.md`, `minimal.md` — tier templates
- 18 new tests covering tier deployment, validation, constraint enforcement, and integration

### Changed
- Role configs now declare economy metadata (2 lines) instead of role-specific token rules
- CLAUDE.md template references economy.md instead of inline token rules
- supercharger.md Output Discipline section references economy.md
- Installer now has economy tier selection step
- Uninstaller cleans up economy.md

### Removed
- Inline Token Economy section from CLAUDE.md template
- Per-role Token Efficiency bullet lists (replaced with economy metadata)
- Redundant anti-pattern bullets (ceremony, repeating — now in economy.md universal rules)
- Output Discipline rules from supercharger.md (moved to economy.md)

## [1.0.0] - 2026-03-31

### New
- Role-based installer with 5 roles: Developer, Writer, Student, Data, PM
- 3 install modes: Safe, Standard, Full
- Multi-select role support (combine any roles)
- Universal CLAUDE.md (~50 lines) with verification gate and safety boundaries
- Universal rules (supercharger.md) with execution workflow and anti-pattern detection
- Guardrails system inspired by TheArchitectit/agent-guardrails-template (Four Laws, autonomy levels, halt conditions)
- 6 hooks: safety, notify, git-safety, auto-format, prompt-validator, compaction-backup
- Existing config handling: Merge / Replace / Skip for CLAUDE.md and settings.json
- MCP server setup tool (12 servers supported)
- claude-check diagnostic tool
- Clean uninstaller with backup restore
- Anti-patterns library (35 patterns)
- Non-interactive install via CLI flags (`--mode`, `--roles`, `--config`, `--settings`)
- MIT LICENSE with BSD-3 attribution for guardrails content

### Ship-Ready Fixes
- **Role prioritization:** Only selected roles deploy to `rules/` (auto-loaded); all 5 stored in `supercharger/roles/` for mode switching
- **Safety hook hardening:** Command normalization (strips `sudo`/`command`/`env`/`\` prefixes, collapses whitespace) + flag-aware `rm` detection + new patterns (fork bomb, `truncate`, `mv /`, `kill -9 -1`)
- **Git-safety hardening:** Position-independent flag matching for `--force`, `--hard`, `--clean`
- **Prompt validator expanded:** 3 → 10 checks (vague scope, multiple tasks, emotional descriptions, implicit references, etc.)
- **Anti-patterns integration:** Moved from `shared/` to `rules/` so Claude Code auto-loads the 35-pattern library
- **CLAUDE.md merge fix:** Merge mode now appends full rendered config (not just a 4-line comment)
- **CLAUDE.md template:** Added role priority line, removed dead `@` import references
- **Version consistency:** Standardized to `1.0.0` across all files
- **README trimmed:** 555 → 180 lines; overflow examples moved to `docs/examples.md`
- **Test suite added:** 57 tests covering install, uninstall, hooks (with bypass attempts), and role deployment
- **Token economy:** Concrete response length targets, upgraded output discipline, role-specific token efficiency rules, and compaction preserve/discard guidance
- **Role-based MCP servers:** Auto-configures 3-5 zero-config MCP servers based on role selection (Context7, Sequential Thinking, Memory as core; Playwright, Magic UI, DuckDuckGo as role-specific). Rewritten `mcp-setup.sh` for advanced key-required servers (GitHub, Brave, Slack, etc.). 65 tests total.

### Credits
- Inspired by SuperClaude Framework (MIT) — execution workflow patterns
- Guardrails adapted from TheArchitectit/agent-guardrails-template (BSD-3)
