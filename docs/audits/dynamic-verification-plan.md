# Dynamic Verification Plan — Claude Supercharger

**Date:** 2026-10-14
**Type:** scoped dynamic verification plan (runnable matrix)
**Status:** plan, not a report of a completed live run
**Scope:** a payload-based verification matrix for the highest-value enforcement and decision contracts.
**Out of scope here:** replacing the project's own test suite; full file-by-file sweep.

---

## 1. What this is and is not

This is a concrete, runnable verification matrix: which payloads to pipe into which hooks, what exit code and stdout shape to expect, and which channels can and cannot be verified for blocking behavior. It is not a claim that I ran a live Claude Code session, and it is not a substitute for the project's own 6,000+ test suite. It is the next thing after the static audits: a plan for observing the installed hooks actually fire and deny (or ask, or rewrite) the way the contracts say they should.

The honest framing matters: a static review can say "this contract is structured well and here are its failure modes." Only a dynamic pass can say "on the installed binary, with this payload, the hook denied with this shape." This plan exists to make the dynamic pass repeatable and scoped, not to pretend the static audits already did it.

---

## 2. Verification tiers

### Tier A — direct payload probe (hook run manually, exit + stdout asserted)

**What it is:** pipe a constructed JSON payload into the installed hook and assert exit code + stdout shape.

**Best for:** every deny-capable PreToolUse guard, the git-safety rewrite path, and any hook whose contract is "exit 2 with this shape."

**Why it matters:** this is the only tier that can directly confirm "the installed hook denies this payload with this shape." It is the first thing to do for any guard whose failure mode is "installed, fires, matches nothing."

**Limitation:** a manual probe confirms the hook runs and denies a specific payload; it does not prove the hook fires from Claude Code's settings.json on every real tool call. That second part is a Claude Code integration test, which is a different (and harder) effort.

### Tier B — harness-contract probe (confirm the harness shape is honored)

**What it is:** for a rewrite or ask path, confirm not just that output was produced, but that the output has the exact harness shape that Claude Code is documented to honor.

**Best for:** `git-safety.sh` `updatedInput` rewrite, any `permissionDecision: ask`, any `additionalContext`/`systemMessage` emission where the harness's treatment of that shape matters.

**Why it matters:** a hook can emit output and still be dropped by the harness if the shape is wrong. The git-safety `hookEventName`-missing drop-bug is the canonical example. Tier B is the only tier that can catch "emitted, but dropped."

**Limitation:** this requires knowing the harness contract, and some harness behavior is inferred from observed behavior rather than fully documented. Where the contract is inferred, state that in the probe notes.

### Tier C — fail-open / fail-silent probe (confirm the honest failure path)

**What it is:** confirm what a hook does when it cannot read the payload, cannot parse it, cannot run its scanner, or times out.

**Best for:** the stdin-timeout path in `lib-stdin.sh`/`lib-stdin_warn.sh`, the `lib-json-fast` fallback path, malformed-JSON handling, missing-dependency handling (jq/python3), the Windows fail-open paths.

**Why it matters:** the honest failure path is a security property too. A guard that fails open silently is worse than one that fails open loudly. Tier C is the only tier that can confirm "on this failure, the hook does X and records Y."

**Limitation:** some failure paths are platform-specific (bash 3.2 vs 5, Windows vs POSIX). A probe run on one platform may not exercise the other.

### Tier D — integration/channel probe (fires from Claude Code, not just from a pipe)

**What it is:** confirm the hook actually fires in a real Claude Code session from settings.json, not just when invoked by path.

**Best for:** the inert-hook class, matcher-dialect bugs, events whose dispatch is uncertain, the "registered but inert" failure mode.

**Why it matters:** this is the only tier that can confirm the failure mode that the static audits worry about most. A hook can pass Tier A and still be inert in real use if the matcher or event is wrong.

**Limitation:** this requires a live Claude Code session and is the hardest tier to run and reproduce. Plan it as a targeted set of probes, not a blanket claim.

---

## 3. Payload matrix — Tier A/B (deny + rewrite + ask)

For each, the probe is: construct the payload, pipe it to the installed hook, assert exit code and stdout shape. Run against the installed copy under `~/.claude/supercharger/hooks/` (or the plugin data dir), not just the repo copy, because the deployed copy is what matters.

### 3.1 safety.sh (Bash, deny shapes)

| Payload shape | Expected | Notes |
|---|---|---|
| `rm -rf /` | exit 2, deny, reason about recursive force rm on dangerous target | confirm both flag orders |
| `rm -rf ~/` and `rm -rf $HOME/` | exit 2, deny | bash + resolver path |
| `rm -rf .` / `rm -rf ./` / `rm -rf ./*` | exit 2, deny | CWD wipe class |
| `curl ... | bash` | exit 2, deny | pipe-to-shell class |
| `DROP TABLE ...` | exit 2, deny | DB destructive class |
| `chmod -R 777 ...` | exit 2, deny | permission class |
| `git push --force origin main` | exit 2, deny (or ask if not protected, depending on config) | git-safety overlap; confirm which hook denies |
| fast-path verb, e.g. `ls -la` | exit 0, no deny | confirm fast-path does not deny |

### 3.2 path-guard.sh (Write/Edit, deny shapes)

| Payload shape | Expected | Notes |
|---|---|---|
| Write to `../../../etc/passwd` | exit 2, deny | path traversal class |
| Write to `~/.ssh/authorized_keys` | exit 2, deny | absolute/credential class |
| Write to `.git/hooks/foo` | exit 2, deny | git-internals class |
| Write to `node_modules/.bin/...` | ask/deny per config | build-artifact class |
| Write to a legit in-project path | exit 0 | confirm no false block |

### 3.3 git-safety.sh (rewrite + deny)

| Payload shape | Expected | Notes |
|---|---|---|
| `git push --force origin main` (protected) | exit 2, deny, force-to-protected reason | confirm protected set |
| `git push --force origin feature` (non-protected) | exit 0, `updatedInput` rewrite stripping force | Tier B: assert exact JSON shape incl. hookEventName, and that `--force` is absent from the rewritten command |
| `git push origin +main` | exit 2, deny (or ask) | `+refspec` native force; confirm it is not silently rewritten away |
| `git reset --hard` | exit 2, deny | work-destroy class |
| `git commit --no-verify` | exit 2, deny | hook-bypass class |
| `git branch -D main` | exit 2, deny | protected branch delete |

### 3.4 commit-guard.sh (deny shapes)

| Payload shape | Expected | Notes |
|---|---|---|
| staged diff with a secret-shaped added line | exit 2, deny, secret-in-staged-diff reason | confirm the staged-diff scan fires |
| commit on default branch with no message | ask (default-branch advisory) after secret scan, not before | confirm ordering: secret scan first |
| conventional-commit opt-in, non-conforming message | exit 2, deny | confirm format check fires when enabled |
| coauthor trailer present, coauthor guard enabled | exit 2, deny | confirm trailer check fires when enabled |

### 3.5 budget-cap.sh (check path)

| Payload shape / state | Expected | Notes |
|---|---|---|
| session spend < 80% | pass | confirm no block |
| session spend >= 80% and < 100% | warn, additionalContext | confirm warn shape |
| session spend >= 100%, non-read-only tool | exit 2, deny | confirm block shape + per-session spend basis |
| session spend >= 100%, Read/Grep | pass | confirm read-only exception |

### 3.6 output-secrets-scanner.sh (warn shape, PostToolUse)

| Payload shape | Expected | Notes |
|---|---|---|
| tool output containing a secret-shaped string | async warn, additionalContext, no block | confirm warn shape; this is PostToolUse, not a block |

---

## 4. Payload matrix — Tier C (fail-open / fail-silent)

### 4.1 stdin-timeout path

| Condition | Expected | Notes |
|---|---|---|
| hook payload delivered faster than timeout | normal deny/allow | baseline |
| hook payload stalled longer than timeout on a PreToolUse guard using `sc_read_input` | `ask` emitted, exit 0, stderr notice | confirm the notice and that it is an ask, not a block |
| hook payload stalled on a non-blocking scanner using `sc_read_input_warn` | stderr notice, exit 0, no scan | confirm no scan and no block; ideally a breadcrumb is written (see recommendation) |

### 4.2 malformed-JSON / missing-field path

| Condition | Expected | Notes |
|---|---|---|
| payload not parseable JSON | exit 0, no false deny, no crash | confirm fail-safe |
| payload missing the field the hook cares about | exit 0 | confirm early exit |
| `lib-json-fast` refuses (ambiguous/escaped/large) | falls back to jq/python | confirm correct value still resolved |

### 4.3 missing-dependency path

| Condition | Expected | Notes |
|---|---|---|
| jq missing | degrades gracefully where designed; install-time check should have failed earlier | confirm which hooks degrade and how |
| python3 missing on a hook that requires it for the real check | fail-open path with visible notice, not silent allow | confirm the notice and that the real check did not run |

### 4.4 Windows fail-open path

| Condition | Expected | Notes |
|---|---|---|
| safety.sh Python resolver inert on Windows | shell-layer text match still blocks the covered `rm` cases; unresolved paths are the documented residual | probe only makes sense on Windows; on POSIX this tier is N/A |

---

## 5. Channel posture matrix (what can and cannot be verified for blocking)

This is the most important part of the plan, because it keeps the results honest.

| Channel | Event | Can verify blocking? | Notes |
|---|---|---|---|
| Bash | PreToolUse | Yes (Tier A/B) | deny = exit 2 + permissionDecision |
| Write/Edit | PreToolUse | Yes (Tier A/B) | deny/ask on path/secret/content |
| git (Bash) | PreToolUse | Yes (Tier A/B) | deny + rewrite path |
| MCP tool | PreToolUse | Yes (Tier A/B) if you can construct the MCP-shaped payload | server-specific; some guards are server-specific |
| Read/Grep/Glob | PreToolUse | Yes (Tier A/B) for env-file/credential guards | |
| Bash output | PostToolUse | No blocking to verify (warn-only, async) | Tier C for fail-open; Tier B for warn shape only |
| MCP output | PostToolUse | No blocking to verify (async warn) | same |
| UserPromptSubmit | UserPromptSubmit | No PreToolUse block; some are deny/ask on the prompt channel | verify shape, not a tool block |
| Stop | Stop | Can block stop with `decision: block` | verify shape, not a tool block |
| async bookkeeping | PostToolUse/async | Cannot verify blocking (not designed to) | skip blocking assertion; verify audit write if relevant |

The point of this matrix is to prevent overclaiming after a run. If you run Tier A on a PostToolUse scanner and it doesn't block, that is expected, not a failure. The run report should say so explicitly.

---

## 6. Run hygiene

- Run against the **installed** hooks, not only the repo copy.
- Record the installed version and source-commit stamp for the run, so the results are attributable.
- Record the platform (bash version, POSIX vs Windows/Git Bash), because bash 3.2 vs 5 and Windows vs POSIX materially change the fail-open paths.
- Record which env vars and scope files were in effect, because many guards are profile/tier/config-gated.
- Keep the probe payloads in a file and run the file, so the run is reproducible and so a probe command doesn't contain the strings it's trying to test (which can make the probe itself get denied by the harness).
- Never pipe a probe through `echo` if the payload has escapes; use `printf '%s'` as the hook-authoring guide warns.

---

## 7. Recommended first run

1. Pick a deny-capable PreToolUse guard (safety.sh is the natural first pick).
2. Run Tier A on 3–5 deny payloads and 1 fast-path allow payload.
3. Run Tier B on git-safety's rewrite path and assert the exact shape.
4. Run Tier C on the stdin-timeout and malformed-JSON paths for that guard.
5. Run the same on path-guard.sh and commit-guard.sh.
6. Run Tier A on budget-cap.sh check with a synthetic spend file.
7. Write the run report with the channel-posture matrix attached, so every "no block" result is explicitly classified as "correct for this channel" or "needs follow-up."

That first run does not prove the whole harness. It proves the highest-value deny/rewrite/fail-open paths on the installed copy, and it gives you a template for extending the matrix to more guards.

---

## 8. What this plan cannot do

- It cannot confirm hooks fire from Claude Code's settings.json in a real session (Tier D only, and only partially).
- It cannot confirm the harness actually honors every output shape under all CC versions (some behavior is inferred, not fully documented).
- It cannot replace the project's own test suite, which already has broad coverage the plan does not attempt to duplicate.
- It cannot make a static audit into a dynamic one. The static audits above remain static.

---

*See also:* `docs/audits/contract-drift-audit.md` (the contracts this plan probes), `docs/audits/pattern-parity-audit.md` (the channels and patterns), `docs/audits/file-sweep-audit.md` (which hooks are deny-capable and where to focus the matrix).
