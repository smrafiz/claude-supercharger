# Contract + Drift Audit — Claude Supercharger

**Date:** 2026-10-14
**Type:** static contract + drift audit (code + design)
**Scope:** the pieces that must agree across files, events, and channels, plus the recurring "registered but inert" failure class.
**Out of scope here:** pattern quality, dynamic verification, full file-by-file sweep (those are separate audits in this directory).

---

## 1. Why this audit exists

A harness like this has a small number of *contracts* that, if they drift, silently weaken the whole product:

- the bash/python agreement on **where per-project state lives** (scope keys)
- the harness agreement on **what output shape actually blocks or rewrites** (`permissionDecision`, `updatedInput`, `additionalContext`, `systemMessage`)
- the agreement between **writers and readers** of per-session and per-project state files
- the agreement between **hook registration** and **hook fireability** (a registered hook that never matches is the worst failure mode)

This audit checks those contracts and the drift surfaces around them. It is not a claim that every hook currently behaves correctly in a live session; it is a claim about whether the contracts are *constructively auditable* and where the invariants are fragile.

---

## 2. The highest-value contracts in the product

### 2.1 The scope-key invariant (lib-paths.sh <-> project-config.sh)

**Contract:** per-project scope files must be named identically by the writer (`project-config.sh`) and by every reader (`lib-paths.sh` / `sc_project_key`).

**Why it matters:** if the two disagree, a project's profile, disabled-hooks, disabled-security-categories, budget, customPatterns, and allowPatterns silently do nothing. The reader looks at one file; the writer wrote another.

**What's there:** `lib-paths.sh` derives `SC_PROJECT_KEY` from the project path by folding `/` -> `-`, plus `\` and `:` for Windows payload cwds, capping at 100 chars, and a `root` fallback. `project-config.sh` has its own Python copy of the same algorithm and an explicit note that it *must* match byte-for-byte.

**Assessment:** correct and aware. Passing the derived key as an env var to the Python side is the right fix for the historical MSYS respelling problem that made the two channels key the same project differently on Windows.

**Fragility:** the invariant lives in two places and must be kept identical across any future change to the algorithm. The current test orbit can verify *behavior* (does the setting take effect?), but that is an indirect and slow signal for a key-parity bug.

**Recommendation:** add an explicit key-parity test: have one side write a per-project scope file and the other side read it back, asserting they addressed the same path. Keep the algorithm in one authoritative location if at all possible, even if both channels still consume it; two copies that must stay identical forever is a known fragile pattern.

---

### 2.2 The decision-contract invariant (lib-deny.sh)

**Contract:** the only output that blocks a PreToolUse tool call is `hookSpecificOutput.permissionDecision: deny` **and** exit 2. The only output that asks is `permissionDecision: ask` and exit 0. A reason without the right exit/shape is not a decision the harness necessarily honors.

**Why it matters:** a hook that emits a reason but forgets exit 2 looks like enforcement and is not. The centralized `sc_deny`/`sc_ask`/`sc_decision` helpers exist specifically to make this less error-prone.

**Assessment:** strong. Centralizing the emit shape is the right call, and the notes in `lib-deny.sh` about why the shape exists (the agent receives only `permissionDecisionReason`) are accurate and useful.

**Fragility:** the contract still depends on every new blocking hook either using the helper or perfectly reproducing its shape. The risk is not current code; it's future additions and any hook that gains a new output channel.

**Recommendation:** treat the decision contract as a recorded interface. Any new hook that blocks should route through `lib-deny.sh`, and any hook that wants a new output shape (rewrite, additionalContext, systemMessage) should be documented against the harness event's actual contract, not against a guessed one. The git-safety `updatedInput` notes are the right model here: state the contract, state the known CC behavior, state the drop-bug history.

---

### 2.3 The rewrite-contract invariant (git-safety.sh updatedInput)

**Contract:** when git-safety rewrites a command, it emits `hookSpecificOutput.updatedInput` with the new command, and that rewrite only survives if the harness honors that shape and if the emitted object includes whatever field CC requires (here: `hookEventName`).

**Why it matters:** a rewrite that emits the wrong shape is worse than no rewrite — it appears to enforce and silently does not. The project's own changelog documents two such drop-bugs: a missing `hookEventName` causing the rewrite to be dropped, and the `+refspec` native-force-push spelling bypassing the flag stripper.

**Assessment:** the rewrite path is real enforcement and the changelog is unusually honest about the drop-bugs. That said, it is the most contract-fragile path in the product because it depends on a harness contract that is partly documented and partly inferred from observed behavior.

**Fragility:** the rewrite is gated on "the whole command is the single git push (no compound)." A compound like `git fetch && git push origin +main` would not go through the strip path, and the `+main` arm is the one needing deny rather than rewrite. Ordering between "strip safe pushes" and "deny force to protected" has to be exact.

**Recommendation:**
- Assert the exact emitted JSON shape in the regression suite, including `hookEventName`, `updatedInput`, and that the original force spelling is absent from the output.
- Add one deny-style regression for the compound `+refspec` case so the rewrite-vs-deny boundary is explicitly covered, not just inferred.
- Keep the rewrite path documented as a harness-dependent contract, not as "we rewrite git commands."

---

### 2.4 The writer/reader state-file invariant (per-session + per-project files)

**Contract:** state files written by one hook must be read back by the intended reader under the same naming and scoping rules, and per-session files must stay per-session.

**Why it matters:** this is the bug class that produced `.read-history` being global when it should have been per-session, and the old shared `.session-cost` total that would have blocked every session once lifetime spend exceeded the cap.

**What's there:** per-session suffixes (`-<sid>`) on tool history, read history, readonly/autopilot/strict until files, session roots, budget walk timestamps, file leases, and a per-transcript offset map in the budget accumulator. The per-session spend file (`.main-tokens-<sid>`) is what makes the cap compare against this session instead of a never-resetting machine-global total.

**Assessment:** the state-scoping story is mature and the fixes are honest. The budget accumulator's incremental offset map, binary readline, fcntl-bounded acquire, 4.3.2 version-gated reset, and 40-entry eviction are exactly the right engineering for a hook that runs on every tool call.

**Fragility:**
- The per-session file naming must agree between writer and reader (identical session-id sanitization).
- The per-transcript offset map must not lose or double-count across concurrent sessions.
- The `.session-cost` version field must stay in sync with the reader's interpretation of it.

**Recommendation:** for any new state file, require the writer and reader to be reviewed together, with an explicit per-session-vs-per-project-vs-per-transcript label. The label should be in the file name or the file comment, because that's what a future reader will actually look at.

---

### 2.5 The registration-vs-fireability invariant (the inert-hook class)

**Contract:** a hook that is listed in `settings.json` should actually fire and actually match on the payloads it is meant to guard.

**Why it matters:** this is the recurring defect class in the repo. A hook can be registered and fire on every matching tool call while matching nothing, exiting 0 every time. That is the worst failure mode for a security harness: a fork per call and zero enforcement, with no visible trace in the session.

**History in this repo:**
- bare `mcp__` matcher token matching nothing
- `if` field in the wrong dialect making two git guards inert
- `DirectoryAdded` registration on an event Claude Code didn't dispatch, with a test asserting the registration existed and passing

**What's there now:** `guard-registration-check.sh`, `setup-check.sh`, `version-floor-check.sh`, and code-level notes preserving the old failure stories as warnings.

**Assessment:** the project understands this better than most, and the notes-left-in-place discipline is good. But the checks are mostly "is it listed" and "did we write the expected count," which can pass while a guard is inert.

**Recommendation:**
- Add a per-guard "fired N, denied M" breadcrumb (even just to the audit log) for the security-critical guards. The blocked-command ledger records denials, not "fired with zero matches," so inertness is still invisible there.
- Add an anomaly rule: a security-critical guard that fires many times across a window with zero denials is worth a look, because either it is inert or nothing is happening that should have been denied.
- Keep treating "registration proves nothing about dispatch" as a first-class caution in any test that asserts a registration: the test should be paired with a payload probe, where feasible, not just a settings.json grep.

---

## 3. Cross-channel drift (classic install vs plugin)

**Contract:** the same guard should mean the same thing under both install channels, modulo the documented exceptions.

**Documented exceptions (good, should stay explicit):**
- slash commands namespaced under the plugin
- SessionStart context delivery instead of a CLAUDE.md block
- the three settings.json keys a plugin manifest cannot declare (statusline, prompt cache, attribution)
- MCP profile filtering not applying under the plugin (Claude Code's own per-server approval selects servers)

**Drift risk:** the hardest-to-see divergence is MCP-server activation. A guard that decides from "is this server currently active in the current profile" may agree with itself about *whether the guard runs* but disagree about *which servers are in scope* between channels. That's not currently a documented live bug; it's the axis most worth keeping under a scripted check.

**Recommendation:** make "list the MCP servers actually active under this profile right now" a scripted assertion in the plugin smoke path, and qualify any "runs identically on both channels" line with the explicit exceptions above.

---

## 4. Transfer and update trust contract

**Contract:** an operator should be able to know what version and what source commit they are running, and the update path should not silently downgrade or silently execute new code without an explicit human step.

**What's there:**
- version stamp + source-commit stamp (full SHA, readers truncate, absent-on-tarball treated as unknown)
- 24h-cached remote version for update-check
- changelog noting the old string-version-compare downgrade bug and its fix

**Assessment:** good. The version-vs-commit distinction is the right model, and the downgrade bug is exactly the kind of thing that happens when versions are compared as strings.

**Recommendation:** surface the source-commit stamp next to the version in an operator-visible command (`/sc-status` or `/sc-doctor`), and make the update direction explicit in docs: update-check fetches a version string; update.sh is the human-run path that brings code in. That distinction is the whole point of the kill-switch and the update UX.

---

## 5. Findings

### F1 — The scope-key invariant is correct but fragile across two implementations

**Severity:** medium (silent misconfiguration, not a bypass)
**Where:** `lib-paths.sh` and `project-config.sh`
**Note:** the env-var handoff is the right fix for the Windows respelling problem. Add an explicit writer-vs-reader key-parity test and reduce the number of authoritative copies of the algorithm.

### F2 — The git-safety rewrite path is the most contract-fragile enforcement path

**Severity:** medium-high (a wrong rewrite shape looks like enforcement and is not)
**Where:** `hooks/git-safety.sh`, `hooks/lib-deny.sh`, CC harness contract
**Note:** assert exact emitted JSON shape + absence of the original force spelling; add a compound `+refspec` deny regression; keep it documented as harness-dependent.

### F3 — Inertness is still partly invisible

**Severity:** medium-high (a fork per call, zero enforcement, no session trace)
**Where:** registration checks vs. actual fire/deny telemetry
**Note:** add per-guard fire/deny breadcrumbs and an anomaly rule for "fired a lot, denied zero."

### F4 — Per-session state scoping is mature, but new state files need a writer+reader reviewed together

**Severity:** low-medium (the fixes are in place; the risk is future additions)
**Where:** any new `scope/` writer/reader pair
**Note:** require an explicit per-session / per-project / per-transcript label at creation.

### F5 — Transfer/update trust is well-built; make the commit visible and the update direction explicit

**Severity:** low
**Where:** stamps, update-check, update.sh, docs
**Note:** surface source-commit in an operator command and state the fetch-vs-execute distinction explicitly.

---

## 6. Summary

The contracts in this product are, on the whole, well-engineered and well-documented about their own fragility. The highest-value residual is not that a contract is missing, but that some invariants are *two-copy* (scope key, state-file naming) and some failure modes (inertness, wrong rewrite shape) are still partly invisible. Those are the places to keep auditing.

*See also:* `docs/audits/pattern-parity-audit.md` (shared security patterns), `docs/audits/dynamic-verification-plan.md` (payload matrix for the contracts above), `docs/audits/file-sweep-audit.md` (hook-by-hook evidence for the inert-hook class).
