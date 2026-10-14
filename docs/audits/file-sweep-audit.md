# File-by-File Sweep Audit — Claude Supercharger

**Date:** 2026-10-14
**Type:** scoped static file sweep (findings log)
**Scope:** a structured sweep of the deny-capable and state-touching hooks, plus the lib-* decision/state/engineering helpers, with a findings log. Not a claim of full cover-to-cover reading of all 166 hooks.
**Out of scope here:** dynamic verification (separate file), pattern quality in depth (separate file).

---

## 1. Method and scope

This sweep reads hooks in the order of their role in the security story, with a findings log per hook or per small group. The goal is not to recite each hook's description (the catalog already does that), but to record the one or two things worth auditing about each: what it blocks or touches, what its honest failure mode is, and where it depends on a shared contract.

Scope decision: 166 hooks is too many to claim a full cover-to-cover audit in one doc without actually doing it file by file. This sweep therefore concentrates on the hooks that can deny, can rewrite, can write state, or can touch credentials/prompts, plus the shared libs that make those contracts possible. The remaining hooks (mostly async bookkeeping, notifications, analytics, advisory prompt hooks) are lower yield for a security sweep and are noted as such rather than omitted silently.

---

## 2. Sweep findings

### 2.1 Decision + state engine (read first; findings are shared infrastructure)

**`hooks/lib-deny.sh` — decision emit**
Finding: well-centralized. The only thing to keep auditing is that every new deny-capable hook either uses it or reproduces its shape exactly.
Note: the `sc_ask` / `sc_deny` split is correct (ask must not exit 2).

**`hooks/lib-stdin.sh` — fork-free read + timeout handling**
Finding: the timeout path is the highest-value surface here. PreToolUse guards get an explicit `ask`; non-blocking scanners get `sc_read_input_warn` and exit 0 with a notice. The residual is that the non-blocking path does not write a breadcrumb, so a skipped payload is invisible in the ledger.
Recommendation: add a one-line audit breadcrumb on the warn path.

**`hooks/lib-json-fast.sh` — fork-free JSON read**
Finding: size gate is correctly measured and correct about when it loses to the fork it replaces. The depth check and truncation guard are the right defensive additions.
Note: the key-parity note (fast path matches at any depth; callers wanting top-level fields add a brace check) is exactly the kind of subtle contract to keep visible.

**`hooks/lib-suppress.sh` — init, suppress, disable, profile, dedup**
Finding: the kill-switch exit-at-source is the security-critical path here; the notes about it not sourcing `lib-suppress` when it must survive the kill-switch are correct and worth keeping.
Note: `hook_profile_skip` is the gate for profile-based skipping; audit that list against the deny-capable set whenever it changes.

**`hooks/lib-paths.sh` — HOME/STATE resolution + per-project scope keys**
Finding: the scope-key algorithm is the shared invariant. Two copies (bash + python) must stay identical; pass the derived key as an env var to avoid MSYS respelling.
Recommendation: key-parity test between writer and reader.

**`hooks/lib-secret-patterns.sh` — shared secret array**
Finding: best-maintained pattern surface. Single source for output/commit/sendmessage.
Note: ledger redaction ordering vs. cap is the main residual; see pattern-parity audit.

**`hooks/lib-project-root.sh`, `lib-toolpath.sh`, `lib-critical-infra.sh`, `lib-git-remote.sh`, `lib-lockfile.sh`**
Finding: these are shared helpers for specific guard families. The highest-value thing to audit is that any change to a helper is checked against the guards that consume it, especially normalization/segmentation helpers.

---

### 2.2 Core enforcement hooks

**`hooks/safety.sh`**
Finding: the core. Fast-path is structurally justified; deny patterns are anchored with attention to positional vs. keyword-anywhere. Python resolver is fail-open on Windows; shell-layer text match closes the worst `rm` cases.
Residual: resolver inertness on Windows for non-rm path checks; ledger cap ordering; stdin-timeout breadcrumb.

**`hooks/path-guard.sh`**
Finding: strong Write/Edit hardening; good Windows attention; good Claude-Code-added-directory honoring.
Residual: Python body still does symlink/abs-path/git-internals/build-artifact/selfmod on Windows, where resolver behavior is the documented residual.

**`hooks/harness-tamper-guard.sh`**
Finding: correct self-defense orientation; asks on a wide set of harness-tamper shapes.
Note: watch for any hook that writes into the install dir; this guard exists precisely for that.

**`hooks/env-file-guard.sh`**
Finding: covers Read/Grep/Glob/.env access that safety.sh's Bash matcher can't reach.
Note: correct to keep separate; the risk is drift between this and any other .env-touching guard.

**`hooks/output-secrets-scanner.sh`**
Finding: PostToolUse async warn; shared patterns; mcp__/WebFetch/Read coverage is good.
Residual: async warn posture; ledger cap ordering.

**`hooks/write-secret-guard.sh`**
Finding: PreToolUse ask on writing secrets into files; the write channel was a real gap before this.
Note: ask, not deny, is the right posture for legitimate key-file writes; confirm the ask framing stays that way.

**`hooks/bash-injection-scanner.sh`**
Finding: PostToolUse warn-only, fail-open, seed-gated.
Residual: same as output scanner posture; a timed-out payload is skipped with no scan.

**`hooks/code-security-scanner.sh`**
Finding: asyncRewake on Write/Edit; scans content about to be written.
Note: asyncRewake is correct for a read-only scan that can wake on a finding; confirm it stays read-only and does not gain a silent mutating path.

**`hooks/mcp-egress-guard.sh`, `hooks/webfetch-egress-guard.sh`, `hooks/bulk-exfil-guard.sh`**
Finding: multi-channel egress coverage; shared-pattern discipline where it exists.
Residual: egress encodings keep expanding; state coverage map per source.

**`hooks/mcp-github-write-gate.sh`, `hooks/mcp-destructive-guard.sh`, `hooks/mcp-sql-guard.sh`, `hooks/mcp-playwright-guard.sh`**
Finding: per-server write gates with real incident motivation.
Note: server names in matchers are a drift surface; when a new MCP server is added, check whether it should be in a matcher.

**`hooks/mcp-provenance.sh`**
Finding: structural check, distinct from persuasion-pattern scanner.
Note: keep the two defenses named separately; conflating them hides their different gaps.

**`hooks/prompt-injection-scanner.sh`**
Finding: multiple channels; honest about best-effort scope.
Residual: per-channel posture should be explicit; Bash-output is after-the-fact.

**`hooks/elicitation-guard.sh`**
Finding: sync, credentials-in-form decline; trusted-server list.
Note: correct to keep sync; a declined form raises a notification so the block isn't silent.

---

### 2.3 Git + commit + filesystem administration

**`hooks/git-safety.sh`**
Finding: rewrite + deny + ask; well-changelog'd drop-bugs.
Residual: `updatedInput` contract fragility; `+refspec`; compound command boundary; this is the highest-value contract audit target.

**`hooks/git-config-exec-guard.sh`, `hooks/git-remote-guard.sh`, `hooks/cloud-cli-destructive-guard.sh`**
Finding: git exec-capable config, remote exfil, cloud CLI destructive ops.
Note: ASK posture is intentional for several of these; confirm the ask framing is the intended balance and not silently weakening.

**`hooks/commit-guard.sh`**
Finding: consolidated three-check hook; ordering fix (secret scan before default-branch ask).
Note: the ordering fix is exactly the right kind of thing to keep testing; a future change that moves the checks around should re-verify ordering.

**`hooks/redirect-clobber-guard.sh`**
Finding: Bash redirect clobber of tracked files is a real gap the Edit/Write path can't cover.
Note: ask posture; confirm it stays scoped to git-tracked targets and once-per-file.

**`hooks/critical-infra-guard.sh`**
Finding: ask on CI/CD/container/DB-migration/auth files.
Note: ask, not deny; confirm that's the intended review-trigger posture.

**`hooks/scope-guard.sh`**
Finding: multi-mode; check/snapshot/contract/clear.
Note: keep the mode semantics legible; a hook with several modes is easier to misread.

---

### 2.4 Modes, budget, cost, confidence

**`hooks/budget-cap.sh`**
Finding: two-mode accumulator/check; per-session spend; incremental offset map; fcntl-bounded acquire; cross-platform fixes.
Residual: pricing table is a hidden dependency; per-session framing should be surfaced; pricing source should be visible.

**`hooks/readonly-guard.sh`, `hooks/human-approval-gate.sh`, `hooks/confidence-gate.sh`**
Finding: the tighten/loosen family and the confidence score.
Note: `confidence-gate` is advisory-ish (score-based ask/deny); keep its score basis legible so a reader doesn't infer a stronger guarantee than a score provides.

**`hooks/subagent-circuit-breaker.sh`, `hooks/subagent-safety.sh`, `hooks/subagent-cost.sh`, `hooks/subagent-stop-check.sh`, `hooks/subagent-report-fallback.sh`, `hooks/subagent-report-notify.sh`**
Finding: subagent governance is a real surface; the report-recovery path is well-thought-through.
Note: subagent start/stop is a place where "fires but does nothing" is worth a probe, because several of these are discovery/async.

**`hooks/tool-call-limiter.sh`**
Finding: count-based cap.
Note: keep the cap basis legible; a count cap is a different kind of limit than a cost cap and should not be conflated with it.

---

### 2.5 State writers + injectors

**`hooks/session-memory-write.sh`, `hooks/session-memory-inject.sh`**
Finding: session memory lifecycle is mature; differential write; crash checkpoint fallback; handoff brief.
Note: the injection path reaches the model via `additionalContext`; keep that channel legible.

**`hooks/learn-from-blocks.sh`**
Finding: blocked-commands/corrections/reinforcements/failures aggregation; 30-day rotation; dedup.
Note: the dangerous-pattern bucket collapse is a good fix; keep the per-session dedup marker.

**`hooks/project-config.sh`**
Finding: SessionStart config loader; per-project scope files; stack detection.
Residual: scope-key parity with readers; too much in one process.

**`hooks/config-weakening-notice.sh`, `hooks/file-watcher.sh`, `hooks/dir-added-record.sh`**
Finding: config-arrival and file-change notices; dir-added recording.
Note: `dir-added-record` is the parked-but-unit-tested hook; keep it parked unless dispatch is confirmed live.

**`hooks/plugin-config-seed.sh`, `hooks/plugin-settings-seed.sh`, `hooks/dependency-preflight.sh`, `hooks/guard-registration-check.sh`**
Finding: plugin parity and install integrity.
Note: the preflight + registration checks are the right integrity layer; keep them legible as integrity checks, not as generic startup noise.

---

### 2.6 Lower-yield (advisory / analytics / notification / async bookkeeping)

These are real bits of the product, but for a security sweep they are lower yield and mostly don't deny or touch credentials/prompts in a security-critical way:

`hooks/adaptive-economy.sh`, `hooks/economy-reinforce.sh`, `hooks/context-advisor.sh`, `hooks/tool-history-tracker.sh`, `hooks/failure-tracker.sh`, `hooks/slow-tool-detector.sh`, `hooks/repetition-detector.sh`, `hooks/reentry-detector.sh`, `hooks/learn-from-prompts.sh`, `hooks/rate-limit-advisor.sh`, `hooks/cache-health.sh`, `hooks/audit-trail.sh`, `hooks/trace-compactor.sh`, `hooks/bash-output-compactor.sh`, `hooks/mcp-output-truncator.sh`, `hooks/mcp-tracker.sh`, `hooks/notify.sh`, `hooks/notify-permission.sh`, `hooks/notify-helper.sh`, `hooks/notify-stop.sh`, `hooks/session-complete.sh`, `hooks/session-end.sh`, `hooks/stop-keep-going.sh`, `hooks/stop-failure.sh`, `hooks/stop-verify.sh`, `hooks/claim-evidence-gate.sh`, `hooks/event-logger.sh`, `hooks/compaction-backup.sh`, `hooks/post-compact-inject.sh`, `hooks/precompact-priorities.sh`, `hooks/agent-router.sh`, `hooks/prompt-validator.sh`, `hooks/destructive-prompt-scanner.sh`, `hooks/peer-message-scanner.sh`, `hooks/shell-escape-advisor.sh`, `hooks/sc-toggle-notice.sh`, `hooks/lesson-recall.sh`, `hooks/lesson-record.sh`, `hooks/auto-compact.sh`, `hooks/design-context.sh`, `hooks/quality-gate.sh`, `hooks/typecheck.sh`, `hooks/agent-gate.sh`, `hooks/agent-poisoning-scanner.sh`, `hooks/agent-handoff-gate.sh`, `hooks/agent-report-tail.sh`, `hooks/file-lease.sh`, `hooks/fact-gate.sh`, `hooks/lockfile-integrity-guard.sh`, `hooks/install-script-guard.sh`, `hooks/pth-persistence-guard.sh`, `hooks/package-source-guard.sh`, `hooks/test-integrity-guard.sh`, `hooks/test-mask-guard.sh`, `hooks/generated-file-guard.sh`, `hooks/phantom-import-guard.sh`, `hooks/comment-replacement-check.sh`, `hooks/lazy-refactor-check.sh`, `hooks/post-write-advisor.sh`, `hooks/ansi-escape-guard.sh`, `hooks/editor-config-guard.sh`, `hooks/workflow-pwn-guard.sh`, `hooks/workflow-guard.sh`, `hooks/cron-guard.sh`, `hooks/cron-discovery.sh`, `hooks/remote-trigger-guard.sh`, `hooks/sendmessage-guard.sh`, `hooks/designsync-upload-guard.sh`, `hooks/artifact-publish-guard.sh`, `hooks/prompt-secret-guard.sh`, `hooks/ai-lock-guard.sh`, `hooks/task-poll-guard.sh`, `hooks/exitworktree-guard.sh`, `hooks/version-floor-check.sh`, `hooks/update-check.sh`, `hooks/setup-check.sh`

For these, the sweep note is: confirm none of them silently gains a state-writing or credential-touching path, and confirm any that are deny-capable are represented in the contract and dynamic-verification audits. The highest-value subset of this group for a future pass is the async ones that touch state (`tool-history-tracker`, `failure-tracker`, `session-memory-*`, `learn-from-*`, `scope-guard`).

---

## 3. Cross-sweep findings

### F1 — The deny-capable surface is well-distributed, not concentrated

There is no single "security hook"; there are many, across Bash, Write/Edit, MCP, Read, and prompt channels. That's correct. The audit implication is that any sweep has to track *which channel* each deny-capable hook covers, because channel gaps are the recurring bug class.

### F2 — The state writers are the second concentrated risk surface

Session memory, learn-from-blocks, budget-cap, scope-guard, file-lease, dir-added-record, plugin seeds, project-config. These are the hooks that write state, and state is where the cross-session and cross-project bugs live. Any future change to a state writer should be reviewed with its reader.

### F3 — Async bookkeeping is not security-critical by default, but state-touching async hooks are

Most async hooks are fine to treat as lower yield. The exception is async hooks that write state that another hook reads. Those should be swept together as writer/reader pairs.

### F4 — The parked-but-tested hook is a good sign, but only if it stays visibly parked

`dir-added-record.sh` is the canonical example. The right state is "parked, unit-tested, not registered unless dispatch is confirmed live." The wrong state is "registered, test passes, never fires."

---

## 4. Summary

This sweep is not a full 166-hook cover-to-cover; it is a structured findings log for the deny-capable, state-touching, and shared-infrastructure hooks, plus an explicit lower-yield bucket so the omission is visible. The highest-value targets for a follow-up dynamic pass are `safety.sh`, `path-guard.sh`, `git-safety.sh`, `commit-guard.sh`, and `budget-cap.sh`, because those are where deny/rewrite/fail-open and the cost cap actually live. The highest-value targets for a future state-audit pass are the writer/reader pairs in session memory, learn-from-blocks, budget-cap, and scope-guard.

*See also:* `docs/audits/contract-drift-audit.md`, `docs/audits/pattern-parity-audit.md`, `docs/audits/dynamic-verification-plan.md`, `docs/audits/claims-docs-audit.md`.
