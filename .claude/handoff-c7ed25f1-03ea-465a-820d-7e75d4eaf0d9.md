## Handoff — claude-supercharger — 2026-11-25 (session c7ed25f1, --deep)

(Replaces the 2026-11-24 brief of the same session id; that one is in git history at e8f75d76.)

### Done
- **PR #368 opened** (`fix/guard-gaps-2`, HEAD df519430, not merged): boxdawn follow-up gaps (rsync -e login key, perl/deno/bun deletes, glued quotes `"r"'m'`, docker volumes, remote rm via ssh/docker/podman/kubectl/compose exec, shred/srm) + two review rounds of fixes. Files: `hooks/safety.sh`, `hooks/safety-detect.py`, `hooks/cmd-normalize.sh`, `tests/test-guard-gaps-2.sh` (111 rows, new), `tests/test-boxdawn-gaps.sh` (helper `$BASH` fix).
- **Loop followed:** Sonnet builds, Opus reviews, 3 rounds (round 3 = no MUST). Rule saved: `feedback-sonnet-builds-opus-reviews`.
- **readback repo** `smrafiz/readback` created PRIVATE, `main` at bfd6de7: README (collapsibles, Install, What it optimizes, Supercharger section), WORKFLOW.md, rule, 5 skills, 3 templates, plugin manifest + SessionStart hook, `install.sh` (116 tests). 3 Opus rounds on the install, 3 Opus reads of the docs.
- Global rule `~/.claude/rules/workflow.md` installed by the user (copy), `~/.claude/agents/batch-editor.md` flipped to sonnet by the user.
- Research done: best workflow (SZZ on 468 commits + papers), plinth/radius-bundles session mining, Matt Pocock skills (OFF-thesis), Atlas (OFF-thesis), subagent model metadata (documented, not live-tested), names (readback chosen).

### In Flight
- **#368 CI:** `Test suite (ubuntu-latest)` and `(macos-latest)` were PENDING at 2026-11-25 ~18:50; Windows dispatch run 45616838013 queued on df519430. Host contract, Plugin manifest, Version consistency, Hook latency green. Merge only when `gh pr checks 368` shows nothing pending, then on the user's word.
- **Local full suite on df519430: NOT finished** (no `rc=` line; the shutdown killed it). Rerun `bash tests/run.sh` unpiped and read rc.
- **readback before public:** user runs the live plugin hook test; user checks the GitHub render; then "go public" on the user's word.

### Decisions Made
- Sonnet builds; Opus does review, security, audit, plans, research (user). No Fable unless the user asks in that request.
- Review cap: 2 rounds for T1, 3 for T2; stop at zero MUST; a MUST open at the cap goes to the user (proposed by me, user went along; written into the readback rule).
- readback starts private; user chose the name; Supercharger section states plainly it does not block a plain `git push` and does not enforce tiers/caps/"agents never push".
- Weak test row dropped (ruby -w passes without the fix) rather than rewritten; perl row stays at 4000.

### What Failed
- Opus-as-builder on guard-gaps-2 (my mis-route, ~2x cost); the user corrected it.
- Round-2 fix instruction widened a regex without repeating the linear-regex warning: the builder made it quadratic (fail-open). Fixed in 0d12844e.
- Windows probes on bare `bash` ran the WSL launcher, so the hook never ran (vacuous). Fixed to `$BASH`.
- The Sonnet builder looped ~3h re-running the full suite after small probe tweaks; I stopped it (TaskStop) at 2h56m and used the committed 1989a3e7.
- Stray uncommitted test edit (perl row shrunk to *2000) would have blinded the row; discarded by the user (my `git checkout --` was guard-blocked).
- A background-command "completed exit 0" notice meant the launcher shell exited, not that the suite passed.
- Subagents cannot run `claude -p --plugin-dir` (guard-blocked): the live plugin hook test is the user's.

### Blockers
- none (waiting on CI and the user's live test)

### Worktrees
- none (main checkout only, per user rule)

### Files Touched
- see Done. Uncommitted in the Supercharger checkout: this brief and `.claude/handoff.md` (carry file; belongs in a separate docs PR from master, like #367). Scratchpad files (`/private/tmp/claude-501/.../scratchpad/`, may be cleared): best-workflow.md, project-sessions-report.md, my-workflow-v2.md, universal-workflow.md, names-report.md, install-brief.md.

### Measurements
- Perl/ruby regex, detector alone, `'perl -a '*N`: branch 16KB 0.028s, 32KB 0.047s, 64KB 0.119s, 256KB 0.484s; master 0.027/0.059/0.121/0.449s; unfixed base 0.767s at 16KB (reviewer, scratchpad `rv3/tdet.py`).
- Differential vs master: 68 perl/ruby + 64 remote-rm + 38 false-positive commands: no case master denied that the branch allows; 15 perl/ruby cases master allowed that the branch denies. New rows: 13 of 112 fail on the unfixed hooks.
- Loop cost (one security-fix loop, before the workflow): build 34%, review 32% (38 calls), audit 20%, fix 15%; builder split cache read 50% / write 27% / output 23%; one session cache-read:output about 600:1 (3034M : 5.1M); mega-sessions had 25-48 compactions.
- SZZ on 468 squash commits: guard/security fixes rewriting a recent PR's lines 27 of 140, features 10 of 42, docs 0 of 50.
- Session cost list-price equivalents earlier: main thread $2.69, builder $1.69, Opus reviewer $1.60, fix round $0.75; the Opus-built guard-gaps-2 builder $4.55 vs about $2.27 at Sonnet rates (inferred).

### Rejected — do not rebuild
- Matt Pocock skills and Atlas as adopted tooling: off-thesis (prompt-only / scaffolder with risky defaults); only ideas borrowed (literal test values, mock at boundaries, deterministic checks first).
- A Supercharger orchestrator for the loop: off-thesis (enforcement hooks only).
- `curl | bash` install route for readback: never.
- Rewriting the ruby `-w` row: it cannot detect the regression because the shell layer denies the payload.

### Dead ends
- Fable-ban natively: `Agent(model:fable*)` deny is literal (misses omitted model); `availableModels` substitutes; `deniedModels` is managed-only. Live subagent model line: `resolvedModel` on PostToolUse Agent is documented, NOT yet seen in a live payload (probe first).
- Live load test of the readback plugin hook from an agent: blocked by Supercharger's guard.

### Open questions
- Ubuntu suite failed on workflow_dispatch run 45607193376 (commit 1989a3e7; Windows shards all passed, macOS cancelled). Cause NOT read. PR run on df519430 pending: UNVERIFIED whether the same failure recurs. Check `gh pr checks 368` first.
- Does the readback SessionStart hook output reach the model (injection defence)? UNVERIFIED, the user's live test settles it.
- Does PreCompact output reach the summarizer (queued compaction task)? UNVERIFIED; this session's compaction preserved context well.
- Sonnet vs Opus as T1 reviewer: NOT KNOWN.

### Reproduce
- Probes: `scratchpad/rv3/probe.py <list>` (verdicts across base/branch/master; `@R@` = `rm -rf`), `thook.py`, `tdet.py`.
- Tests: `bash tests/test-guard-gaps-2.sh` (111 pass), full `bash tests/run.sh` (unpiped, read rc), `shellcheck --severity=error hooks/safety.sh tests/test-guard-gaps-2.sh`.
- Windows: `gh workflow run ci.yml --ref fix/guard-gaps-2`; failure text in artifacts `windows-suite-log-1..4`.
- readback: `git clone https://github.com/smrafiz/readback /tmp/rb && claude -p --plugin-dir /tmp/rb "Quote the first line of the readback rule you have loaded, then list the readback skill names."`; `/bin/bash tests/test-install.sh` (116).

### Resume With
Resume claude-supercharger. First `gh pr checks 368` and read the ubuntu suite result (an earlier dispatch on 1989a3e7 failed ubuntu, cause unread); rerun the full suite unpiped on `fix/guard-gaps-2`. Merge #368 only on the user's word. Then the queue in memory `project-state-2026-11-25-end`.

### Start With
- `/sc-why` is not needed. Start with `gh pr checks 368` and the memory note `project-state-2026-11-25-end`. If a guard fires on a test command, `/sc-why`.
