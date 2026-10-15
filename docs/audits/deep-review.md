# Deep Security + Engineering Review — Claude Supercharger

**Date:** 2026-10-14
**Reviewer:** Buffy (Solar Pro 4)
**Mode:** read-only code + design review (not a dynamic audit, not a test-suite run)
**What I read in depth:** the hook registry, the core Bash safety hook, the Write/Edit path guard, the harness/self-defense guard, the git-safety rewrite path, the commit guard, the budget-cap accumulator/check, the session-memory lifecycle, the config-loader and per-project scope system, the update-check + update.sh paths, the decision engine libs (`lib-deny`, `lib-stdin`, `lib-json-fast`, `lib-suppress`, `lib-paths`, `lib-secret-patterns`), the MCP write/egress guards, the elicitation/skill/agent poisoning scanners, and the slash-command contracts for the operator-facing workflow commands.

**What I did NOT do:** run the 6,300+ test suite, dynamically fire hooks against a live Claude Code session, or read all 166 hooks cover-to-cover. This is a static review; conclusions are about design, contracts, and failure modes, not about whether the current binary passes its own tests.

---

## 1. The harness in one paragraph

Claude Supercharger is a Claude Code layer that moves enforcement out of the model's process and into shell/Python hooks that run before (PreToolUse) and after (PostToolUse) tool calls. The enforcement surface is huge: destructive command blocking, path guards on Write/Edit, credential leak detection across Bash/Read/Write/PostToolUse/SendMessage/commit, prompt-injection scanning across MCP/WebFetch/Read/Bash/slash-expansion, MCP server write-gates and egress classification, supply-chain guards on manifests/install scripts/.pth/pth, and a large memory/cost/economy/rolemode subsystem. It ships in two channels (classic install.sh and the Claude Code plugin), with "safe" (core enforcement) and "full" (everything) modes.

The architecture is internally consistent and unusually well-documented about its own limits. That is the single most important property to verify in a harness like this, because the alternative is a product that quietly implies a stronger guarantee than its patterns can deliver. This project mostly avoids that trap, and the places where it's still ambiguous are the highest-value findings below.

---

## 2. What is genuinely strong

### 2.1 The decision engine is centralized and contract-enforced

Every blocking hook goes through `hooks/lib-deny.sh` (`sc_decision / sc_deny / sc_ask`), which emits exactly one output shape that actually blocks (`permissionDecision: deny` + exit 2) and one that asks (`permissionDecision: ask` + exit 0). That centralization is the right call: a hook that emits a reason but forgets exit 2 is a guard that "fires" and does nothing, and the centralized helper makes that failure mode a one-liner instead of something each hook has to get right independently.

Equally important: the codebase keeps the failure history visible. The notes about hooks that were **registered but inert** because the matcher was in the wrong dialect (the bare `mcp__` token, the `if` field, the `DirectoryAdded` event that Claude Code didn't dispatch yet) are left in place as warnings. That's good engineering discipline — silent corrections hide the defect class that produced them.

### 2.2 The secret surface is the best-maintained part of the repo

`hooks/lib-secret-patterns.sh` is a single shared source of truth consumed by the output scanner, the commit guard, and the sendmessage guard. That's exactly the right structure to prevent the most common cross-channel bug in this kind of product: "we catch leaked secrets in output but not at commit" (or vice versa). The pattern rationales are unusually good and measured: the Base58 Bitcoin WIF anchoring story, the property-reference dot removal with per-category FP counts, the SHA-256 vs. WIF disambiguation, the image-payload false-positive elimination. When a harness maintains its secret patterns with this level of care, the residual risk is usually operational (ledger timing, scoping) rather than algorithmic — and that's true here too.

### 2.3 The git-safety rewrite path is real enforcement, not just a block

`hooks/git-safety.sh` does something most harness guards don't: for force-pushes to non-protected branches it **rewrites** the command (`updatedInput`) to strip the force flag instead of merely blocking. That's a better UX for the non-malicious case and a stronger story for the malicious case, because the rewrite is auditable. The rewrite path is also where the most subtle contract bugs live, and this project has already found and fixed the two highest-value ones: a missing `hookEventName` causing the rewrite to be silently dropped by Claude Code, and the `+refspec` native-force-push path that bypassed the flag stripper entirely. That the project both ships a rewrite and has a changelog entries naming the exact drop-bugs is a strong signal.

### 2.4 The session-state scoping story is mature

The project has clearly gone through the "two projects open at once silently clobber each other's profile/budget/disabled-hooks" bug class and fixed it in `lib-paths.sh` (`sc_project_key`) and the config loader (`project-config.sh`), with the key derived from the project path rather than a `md5sum` fork. The session-scoped file naming (`.tool-history-<sid>`, `.readonly-until-<sid>`, `.session-root-<sid>`) and the per-transcript budget offset map are the right shapes for a multi-session tool. The `chmod 700` on the state dir, with the explicit symlink refusal, is exactly the right level of attention for a directory that holds blocked-command ledgers and handoff briefs.

### 2.5 The operator-facing commands are well-designed as workflow artifacts

The slash commands I read (`sc-scope`, `sc-estimate`, `sc-interview`, `sc-pr`, `sc-audit`, `sc-cleanup`, `sc-security`, `sc-multi-review`) aren't just "ask the model to do X" — they're structured contracts with reading rules, evidence requirements, safety tiers, and output templates. The two-tier safety model in `sc-cleanup`, the verifier-in-a-separate-context pattern in `sc-multi-review` and `sc-security`, and the reference-class-first estimation discipline in `sc-estimate` are all real engineering, not filler. If the security core is the heart of the product, this workflow layer is the part that makes it usable as a daily driver instead of a lab demo.

---

## 3. Findings, in priority order

### Finding 1 — The highest-risk failure mode is "hook registered and firing but matching nothing," and it is a recurring defect class

**What's there:** the project knows this better than most. There's `guard-registration-check.sh`, `setup-check.sh`, `version-floor-check.sh`, and repeated code-level notes about declared-but-inert filters. The `dir-added-record.sh` saga is the clearest example: a hook was registered on an event Claude Code didn't dispatch, a test asserted the registration existed and passed, and nothing caught that the hook never actually fired until a user's `/doctor` flagged it.

**Why it matters:** if your security property is "a separate process returns exit 2," then a hook that exists in `settings.json`, fires on every matching tool call, and returns 0 for every payload is the worst failure mode — it costs a fork per call and provides zero enforcement, with no visible trace in the session. A registration-count check can pass while this is happening.

**Concrete gap:** the current checks are mostly "is the hook listed" and "did we write the expected count." The missing layer is "did each guard actually fire with the expected denial pattern over some window." A per-guard fire/deny counter, sampled over a session or a day, would catch matcher-rot that the registration check can't. The blocked-command ledger is the closest thing to this, but it only records denials, not "fires with zero matches," so a silently-matching-nothing guard is invisible there too.

**Recommendation:** add a lightweight per-hook "fired N times, denied M times" breadcrumb (even just to the audit log) for the security-critical guards, and compare it against a minimum-expected baseline or a "fired > 0 but denied == 0 over a long window" anomaly rule. The point isn't to block on it — it's to make inertness visible.

---

### Finding 2 — The stdin-timeout path is a deliberate, documented "fail open," and it is wider on the non-blocking scanners than the docs imply

**What's there:** `hooks/lib-stdin.sh` correctly identifies that bash 3.2 returns `rc=1` on a `-t` timeout (indistinguishable from EOF), uses elapsed time as the discriminator, and emits an explicit `ask` for PreToolUse guards. For the non-blocking scanners (PostToolUse secret/injection scanners, Stop-channel evidence gate, UserPromptSubmit prompt-secret guard) it uses `sc_read_input_warn`, which emits a stderr notice and exits 0 — the payload is simply not scanned.

**Why it matters:** this is a design choice, not a bug, and it's defensible. But the blast radius is asymmetric. On a PreToolUse guard, a timeout at least surfaces an `ask` that may prompt the user. On a PostToolUse scanner, a timeout means a credential-bearing or injection-bearing payload was skipped with **no** entry in the blocked-commands ledger and no injection into the session. The scanner that would have caught it is the one that timed out. If you're operating this as a security control rather than a UX aid, that silence matters.

**Also worth noting:** the `sc_read_input_warn` path says something on stderr, but for PostToolUse the harness may not deliver that to the user in a useful way, so "said something" and "was seen" are different. The docs are honest that async hooks can't steer anything; the residual is that a timed-out non-blocking scanner is effectively off for that payload with no audit artifact.

**Recommendation:** for the non-blocking scanners, write a one-line breadcrumb into the per-session audit state on timeout (e.g. a counter or a `SCANNED=0 TIMEOUT=1` flag) so post-hoc analysis can distinguish "scanned and clean" from "timed out and skipped." This is defensive visibility, not a change to the timeout policy itself.

---

### Finding 3 — `git-safety.sh` is the most contract-fragile enforcement path in the product

**What's there:** a rewrite-based force-strip for non-protected pushes, plus a large deny/ask matrix for the destructive git family (reset --hard, checkout/restore whole-tree, stash drop/clear, clean -f, reflog expire, push --mirror, update-ref -d, etc.). The contract notes are unusually good: the changelog explicitly documents the `hookEventName`-missing drop-bug and the `+refspec` bypass.

**Why it matters:** the rewrite path is the sharpest surface here because it depends on a Claude Code harness contract (`updatedInput`, last-write-wins, `hookEventName` required) that is partly documented and partly inferred from behavior. A rewrite that emits the wrong shape is worse than no rewrite, because it looks like enforcement and silently isn't. The existing drop-bug history shows this isn't hypothetical. And the `+refspec` bypass is exactly the kind of parallel path a security reviewer has to chase manually: the flag stripper removes `--force`, but git's native force-push spelling is `+branch`, which the stripper never touches.

**Residual I'd flag for a future pass:** the rewrite is gated on "the whole command is the single git push (no compound)." A compound like `git fetch && git push origin +main` would not be rewritten by the strip path, and the `+main` arm is the one that needs the deny rather than the rewrite. The ordering between "strip safe pushes" and "deny force to protected" has to be exact, because a denied protected push and a rewritten non-protected push are different exit paths and different user-visible behavior.

**Recommendation:** treat the `updatedInput` rewrite path as a first-class contract with its own regression suite that asserts the exact emitted JSON shape (including `hookEventName`), not just "some output was produced." The existing test does assert `updatedInput` is present; make sure it also asserts the rewrite actually changed the command and that the original force spelling is gone from the output.

---

### Finding 4 — The budget-cap accumulator has a real cross-platform and correctness history, and the price table is a hidden dependency

**What's there:** a two-mode hook — PostToolUse accumulator (reads the transcript incrementally by byte offset, with fcntl locking and a bounded acquire so a stuck holder doesn't hang the session) and PreToolUse check (warn at 80%, block at 100%, with a per-session spend file so the cap doesn't compare against a never-resetting machine-global total). The incremental offset map, the per-transcript keying, the binary-mode readline, the 4.3.2 reset-on-version-mismatch, and the 40-entry eviction cap are all exactly the right engineering for a hook that runs on every tool call and reads a growing transcript.

**Why it matters:** this hook is the single most expensive on the Bash PreToolUse chain, and it has had real correctness bugs: a Windows `fcntl` import that killed the whole block (so the cap never ran), a text-mode seek that overshot and re-counted transcripts (~3.8x), a shared offset that double-counted concurrent sessions, and a machine-global total that would have blocked every session instantly once lifetime spend exceeded the cap. All of those are now fixed and changelog'd, which is good. The residual is that the pricing table is a hidden dependency: if you're on Bedrock/Vertex/a gateway, the first-party pricing is wrong unless you set `SUPERCHARGER_PRICE_*` overrides, and the changelog says the Fable/Mythos tier was once priced ~3x too low without its override. A cost guard whose numbers are wrong is a denial-of-wallet risk, not a security bypass, but for a product whose headline feature is "no end-of-month surprises," wrong numbers are a real failure of the value proposition.

**Recommendation:** surface the active pricing table in `/sc-status` or `/sc-why` so an operator can see which rates are actually in force (first-party vs. overridden), and add a one-line "pricing source" note when an override is active. Also make the per-session vs. machine-global distinction visible in the block message — "this session has spent $X of $Y" is the right frame, and it should be stated as such.

---

### Finding 5 — The config loader does too much in one process and carries a cross-channel keying invariant that must stay byte-identical

**What's there:** `hooks/project-config.sh` is a SessionStart hook that walks for `.supercharger.json`, detects the stack, writes per-project scope files (`.profile`, `.disabled-hooks`, `.disabled-security-categories`, `.budget-cap`, `.custom-patterns`, `.allow-patterns`), caches the stack, reads the last-session cost, and emits a systemMessage. The per-project scope-file writing is correct and the "key absent vs. present-but-empty" distinction for `disableHooks` is the right semantics.

**Why it matters:** the config loader and the reader hooks must agree on the scope-key algorithm byte-for-byte, or per-project settings silently do nothing. The codebase knows this — there's an explicit "MUST match `sc_project_key()` byte for byte" note — and it passes the derived key as an env var to avoid the MSYS respelling problem that historically made the two channels key the same project differently on Windows. That's the right fix. The residual risk is that the invariant is fragile: any future change to the key algorithm has to be made in two places (bash + python) and kept identical, and the test for it is "does the setting take effect," which is a slow and indirect signal.

**Recommendation:** add an explicit "writer key == reader key" assertion somewhere in the test orbit — ideally a test that writes a per-project scope file from the bash side and reads it back from the python side (or vice versa) and asserts they name the same file. The current tests cover behavior; a direct key-parity test would catch the exact failure mode that bit this project before.

---

### Finding 6 — The plugin vs. classic channel split is a real integrity surface and is under-tested at the behavior level

**What's there:** `lib-paths.sh` unifies `SUPERCHARGER_HOME`/`SUPERCHARGER_STATE` resolution, the plugin detects a classic install and stands down, and the docs clearly enumerate what differs (namespaced commands, SessionStart context instead of CLAUDE.md block, the three settings.json keys a plugin manifest can't declare, MCP profile filtering not applying under the plugin). That enumeration is good.

**Why it matters:** the split means "Supercharger is on" is not one state but two, with different observability (statusline, prompt cache, attribution), different MCP-server-activation rules, and different config-delivery paths. The most dangerous divergence is the one that's hardest to see: under the plugin, profile-gated guards can't rely on the same MCP-server-activation mechanism as the classic install, so a guard that decides from "is this server currently active" may disagree between channels about which servers are in scope. The docs note this, but the verification is manual.

**Recommendation:** make "list the MCP servers actually active under this profile right now" a scripted, asserted check in the plugin smoke test rather than a manual bullet, because that's the axis on which the two channels most plausibly diverge in enforcement. Also qualify any "every guard runs identically on both channels" claim with the explicit exceptions (MCP profile filtering, the three settings.json keys, namespacing).

---

### Finding 7 — Trust-on-first-use for skills/agents is correct but should be surfaced, not just documented

**What's there:** a skill-integrity guard (hash-on-first-use, "has this file changed?") and a skill-poisoning scanner (does this look malicious?), plus the analogous agent-poisoning scanner. The docs are clear that these are complementary — one catches edits, the other catches a freshly-loaded malicious file.

**Why it matters:** the integrity guard is trust-on-first-use. If a skill was already loaded before Supercharger was installed (or before the guard was registered), the first Supercharger-seen load is treated as trusted. A poison that lands before install passes integrity on day one and then only needs to evade the pattern scanner. The project treats this as an acceptable trade-off against maintaining a lockfile, which is a reasonable choice — but it's exactly the kind of assumption a security reviewer should call out explicitly, because a user who installs Supercharger mid-flight may assume pre-existing skills were re-baselined when they weren't.

**Recommendation:** make the "first load under Supercharger = trusted baseline" assumption visible in user-facing output, so an operator who installs mid-flight understands that pre-existing skills weren't re-baselined. A one-line note in `/sc-why` or `/sc-status` when a skill is first seen under Supercharger would do most of the work.

---

### Finding 8 — Prompt-injection defense is well-scoped but its posture differs by channel, and that should be visible

**What's there:** scanners on MCP output, WebFetch/WebSearch, Read content, Bash output (warn-only, fail-open), slash-command expansion, and a structural MCP-provenance check. The project is explicit that this is best-effort opposition to opportunistic injection, not a defense against a targeted attacker who controls your prompts.

**Why it matters:** I agree with the framing. The risk is that a 160-hook "security" product implies a stronger guarantee than the scanners deliver, especially because the hottest channels (Bash output) are async and warn-only. A prompt injection that reaches the model through Bash output is flagged asynchronously after the model has already seen it. That's the right performance trade-off, but it should be stated as "detected after the fact, not prevented" for that channel, not as a blanket "injection defense."

**Recommendation:** ensure the statusline/transcript indicators distinguish "injection detected" (async, after the fact) from "injection blocked" (synchronous, pre-execution), so the operator can tell which channels actually have a pre-execution gate and which only have 사후 detection.

---

### Finding 9 — The update path is a trust anchor and should be treated like one

**What's there:** `tools/update.sh` and `hooks/update-check.sh`, with a version stamp, a source-commit stamp, a 24h-cached remote version, and the changelog noting that the old string-based version compare silently downgraded the install when the CDN-cached remote lagged. The commit stamp is the right fix (full SHA, readers truncate, absent-on-tarball treated as unknown).

**Why it matters:** an auto-updating security harness has a built-in trust anchor — the user must trust that the code being pulled is the code being run. The version-vs-commit distinction is the right model, and the downgrade bug is exactly the kind of thing that happens when you compare versions as strings. The residual is that the update path is also the one place where a compromised upstream (or a MITM on the fetch, though the fetch is HTTPS) could ship new code into an installed harness. The product's "no telemetry, no data leaves the machine" story is good, but the update fetch is the one network call that *does* bring code in, and it deserves the same level of explicitness as the security guarantees.

**Recommendation:** surface the source-commit stamp in `/sc-status` or `/sc-doctor` alongside the version, so an operator can see "I am running v4.3.5 at commit <sha>" and know whether that matches what they expect. Also make the update-check direction explicit in the docs — "we fetch the remote version string from GitHub; we do not fetch and execute new code without you running update.sh" — because that distinction is the whole point of the kill-switch and the update UX.

---

### Finding 10 — A few smaller things worth naming

- **The README's threat-model section is the best part of the docs** and should be the first thing a new operator reads. It correctly separates mechanism ("not bypassable by the model") from pattern quality ("best-effort"), and it names the out-of-scope flows (`!` shell escapes, commands run outside the session). Keep that section as the canonical statement; don't let shorter marketing copy around it imply more.

- **`payload.json` is gone.** This was flagged in the earlier review as leftover scratch in the repo root. It's now removed, which is the right call — a random API payload in a security-harness repo root is noise at best, a distraction at worst. No other stray data files are present in the root.

- **The `sc_cleanup`-style two-tier safety model and the `sc_multi-review` verifier pattern are excellent** and could be referenced as the template for any future operator-facing command that touches code. The "Tier 1 = proven by compiler/linter; Tier 2 = approval" split is the right default for any automated deletion.

- **`lib-json-fast.sh`'s size gate** (fall back to jq/python above ~4–6KB because the fork-free path is quadratic and becomes slower than the fork it replaces) is exactly the right kind of measurement-backed threshold. The note that it exists to avoid a fork, and that above the crossover it _doesn't_, is the kind of honest engineering that prevents a micro-optimization from becoming a DoS surface on large payloads.

- **The `hook_already_emitted` dedup** (600s TTL, per-session, per-hook) is a good fit for the advisory hooks that fire on every prompt; the test/CI escape hatch (`SUPERCHARGER_NO_DEDUP=1`) is the right shape. The only risk is that dedup is a suppression mechanism, so any hook that gains a blocking path must be checked not to have silently become async+dedup+non-blocking.

---

## 4. Risk summary

| Area | Assessment | Residual |
|---|---|---|
| Decision engine | Strong — centralized, contract-enforced | Inertness visibility (fires-but-no-denials) |
| Secret detection | Best-maintained surface | Ledger timing/cap ordering; pricing-table correctness |
| Git safety | Real rewrite enforcement, well-changelog'd | `updatedInput` contract fragility; `+refspec` parallel path |
| Session/state scoping | Mature, per-session, symlink-safe | Key-parity invariant is fragile across bash/python |
| Budget cap | Correct incremental design, cross-platform fixes | Pricing table is a hidden dependency; per-session framing should be surfaced |
| Plugin vs classic | Handled, well-documented exceptions | Divergence under MCP profile filtering is under-asserted |
| Skills/agents trust | Correct decomposition | Trust-on-first-use should be surfaced to the operator |
| Prompt injection | Honestly scoped, expanding coverage | Channel posture (async warn vs sync block) should be visible |
| Update path | Good version/commit model, downgrade bug fixed | Update fetch is the one code-ingress network call; make it explicit |
| Operator commands | Well-designed workflow contracts | None significant |

**Overall:** this is a serious, mature security harness whose biggest risk is operational breadth and the gap between "guard exists" and "guard fires with effect." The codebase's own history is the best evidence that the maintainer understands that gap. The highest-value next work is making inertness and channel divergence visible rather than merely prevented-and-hoped-for.

---

*Reviewed (non-exhaustive):* `lib/hooks.sh`, `install.sh`, `uninstall.sh`, `hooks/safety.sh`, `hooks/path-guard.sh`, `hooks/harness-tamper-guard.sh`, `hooks/git-safety.sh`, `hooks/commit-guard.sh`, `hooks/budget-cap.sh`, `hooks/memory-write-guard.sh`, `hooks/readonly-guard.sh`, `hooks/human-approval-gate.sh`, `hooks/scope-guard.sh`, `hooks/confidence-gate.sh`, `hooks/config-scan.sh`, `hooks/output-secrets-scanner.sh`, `hooks/write-secret-guard.sh`, `hooks/prompt-injection-scanner.sh`, `hooks/bash-injection-scanner.sh`, `hooks/mcp-egress-guard.sh`, `hooks/mcp-github-write-gate.sh`, `hooks/mcp-destructive-guard.sh`, `hooks/mcp-sql-guard.sh`, `hooks/mcp-playwright-guard.sh`, `hooks/elicitation-guard.sh`, `hooks/skill-integrity-guard.sh`, `hooks/skill-poisoning-scanner.sh`, `hooks/agent-poisoning-scanner.sh`, `hooks/subagent-safety.sh`, `hooks/subagent-circuit-breaker.sh`, `hooks/session-memory-write.sh`, `hooks/session-memory-inject.sh`, `hooks/learn-from-blocks.sh`, `hooks/project-config.sh`, `hooks/config-weakening-notice.sh`, `hooks/file-watcher.sh`, `hooks/dir-added-record.sh`, `hooks/plugin-config-seed.sh`, `hooks/plugin-settings-seed.sh`, `hooks/dependency-preflight.sh`, `hooks/guard-registration-check.sh`, `hooks/update-check.sh`, `tools/update.sh`, `hooks/lib-deny.sh`, `hooks/lib-stdin.sh`, `hooks/lib-json-fast.sh`, `hooks/lib-suppress.sh`, `hooks/lib-paths.sh`, `hooks/lib-secret-patterns.sh`, `hooks/lib-project-root.sh`, `hooks/lib-toolpath.sh`, `hooks/lib-critical-infra.sh`, `hooks/lib-git-remote.sh`, `hooks/lib-lockfile.sh`, `configs/commands/sc-pr.md`, `configs/commands/sc-audit.md`, `configs/commands/sc-cleanup.md`, `configs/commands/sc-scope.md`, `configs/commands/sc-estimate.md`, `configs/commands/sc-interview.md`, `configs/commands/sc-multi-review.md`, `configs/commands/sc-security.md`.
