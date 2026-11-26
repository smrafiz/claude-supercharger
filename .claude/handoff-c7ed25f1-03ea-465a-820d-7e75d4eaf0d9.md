## Handoff — claude-supercharger — 2026-11-26 (session c7ed25f1, --deep)

(Replaces the 2026-11-25 brief of the same session id; that one is in git history at 5a00af75 and e8f75d76. The step-by-step list of open work is in `docs/PENDING-2026-11-26.md`.)

### Done
- **Merged to master (squash), none released:** #368 guard gaps `a8914e9d`; #369 handoff docs `5a00af75`; #370 claim-gate evidence `edfd9c70`; #371 `.gitignore` pycache `7a139d25`; #372 scanner image blanking `e70bdc56`; #373 readback failure-tracker `6d07eb18`; #374 pending-items doc `e8c780f4`. Master CI green on `e8c780f4` (2 runs success; one duplicate run on `6d07eb18` cancelled, a 1-job Host-contract cancel, cause unconfirmed).
- **#370** (`hooks/claim-evidence-gate.sh`): the "no test command ran" advisory no longer fires after a single test file run (`bash tests/test-x.sh`, `./tests/test-x.sh`, absolute paths, `bash -x`), `gh pr checks` / `gh run view|watch|list`, or a subagent report in the same turn (Agent/Task call, `<task-notification>` user entry or attachment). `TEST_CMD` and all blocking arms unchanged (differential: 90 synthetic transcripts, only the intended no-test-run cases differ). Two Opus rounds, no MUST.
- **#372** (`hooks/lib_tool_text.py`): every MCP screenshot was flagged "base64 payload" because the image block's base64 was json-dumped into the scanned text. Now `data` / `source.data` of `type=="image"` blocks is blanked only when it fullmatches `[A-Za-z0-9+/]{256,}={0,2}`. 200k-shape fuzz: 0 output differences for inputs without an image dict. Two Opus rounds.
- **#373**: `hooks/lib-readback.sh` (parse gate rows from `READBACK.md`, never execute), failure-tracker readback branch (count on PostToolUseFailure or `interrupted:true`; nudge at the 2nd failure, emitted only from PostToolUseFailure), a SYNC PostToolUseFailure registration, converter fix (`commas_to_pipes` now covers PostToolUseFailure, also changes `disk-watch`), scope-cleanup prunes `.readback-fails-*`, `tests/test-readback-arm.sh` (31 rows). Two Opus rounds (round 1: 4 SHOULD, no MUST; round 2: none).
- Deleted 7 merged branches (6 local, 7 remote). Kept `origin/wip/download-ledger` (1 unmerged WIP commit).
- Peer coordination: `Readback` (session formerly `readback-2f`) accepted the contract and the divergences; `FBT` (formerly `radius-bundles-aa`) told the screenshot flood is fixed on master, unreleased.

### In Flight
- Nothing running. No open PRs. Checkout on `master` `e8c780f4`; `.claude/handoff*.md` modified (this brief and the carry file, uncommitted; commit via a docs PR like #369); `.claude/PENDING-2026-11-26.md` is an untracked, git-ignored duplicate of `docs/PENDING-2026-11-26.md`.
- Waiting on the user: (1) the live probe; (2) decisions on the `stop-verify` trust gate; (3) go on the covers-file PR and on block-once for the claim-gate arm; (4) release timing.

### Decisions Made
- Parallel work with ONE checkout and no worktrees: only read-only planners/reviewers can run in parallel with a builder; a second builder would need a branch switch under the first one's feet. (user rule: no worktrees.)
- Do not widen `TEST_CMD` to fix advisory false triggers: it also feeds the blocking arms (exit 2). Added a separate evidence-only regex instead.
- Count readback gate failures on PostToolUseFailure (sync), not on async PostToolUse text markers: async hook output is documented as ignored; failures arrive as PostToolUseFailure (events.log: 32 `tool_failure ... Exit code 1` rows in one day).
- Scanner fix = blank image base64, keep every other key scanned (first attempt, "join text blocks only", stopped scanning other keys and changed text-only lists; Opus round 1 caught it, replaced in the same PR).
- The user wants Supercharger to FULLY integrate with readback when `READBACK.md` is detected (reversed my earlier "defer").
- Agreed with Readback: parse only the "Your value" column of `| Item | Your value | Example |`; gate rows `Targeted test`, `Full suite`, `New warnings`, `Secret scan`; root only (`${CLAUDE_PROJECT_DIR:-$PWD}/READBACK.md`); fixed nudge text with N; no fallback runner list on our side; stricter prefix match.

### What Failed
- zsh does not word-split `$VAR`: my branch-deletion loop `for b in $B` ran once with the whole string and deleted nothing (silently). Re-ran with an explicit list.
- `.claude/` is git-ignored except the handoff files and CLAUDE.md: the docs file had to live under `docs/` to be committed.
- `git pull --ff-only` aborted because two modified handoff files matched files changed upstream; the user ran `git checkout --` (the guard blocks agents from discarding changes).
- Guard denies hit by agents on text-only patterns (regex text looks like a pipe into a shell; `-c "(...)"` fixtures; the disable-flag name in a test heredoc): each redone with Edit/Write on the guard/test file under the user's 2026-11-22 rule; none got the denied action done another way.
- A background launcher's "completed (exit 0)" notice again looked like suite completion (it is the launcher shell). Read the `rc=` line.
- `radius-bundles-84` (the reporter) ended before I could reply; peer sessions were renamed (`readback-2f` to `Readback`, `radius-bundles-aa` to `FBT`): use ListAgents before messaging.

### Blockers
- Probe (live `claude -p`, agents cannot run it): needed to settle two UNKNOWNs. See Open questions.

### Worktrees
- none (main checkout only, per user rule).

### Files Touched
- see Done (hooks: `claim-evidence-gate.sh`, `lib_tool_text.py`, `lib-readback.sh`, `failure-tracker.sh`; `lib/hooks.sh`, `tools/gen-plugin-hooks.sh`, `tools/scope-cleanup.sh`, `hooks/hooks.json`, `.gitignore`; tests `test-claim-evidence-gate.sh`, `test-prompt-injection-scanner.sh`, `test-readback-arm.sh`, `test-scope-cleanup.sh`, `test-comma-matchers.sh`, `test-install.sh` counts).
- Not committed: this brief, `.claude/handoff.md`.

### Measurements
- Full suite unpiped: `d1155fe5` (PR #373 head) rc=0, 9080 passed, 0 failed (log `scratchpad/suite-pr1b.log`); the earlier `7cced5e0` run rc=0, 9070 passed. Both run on the live checkout.
- Targeted: `test-claim-evidence-gate` 94 passed; `test-prompt-injection-scanner` 71; `test-injection-families` 87; `test-secret-patterns` 47; `test-output-secrets-attribution` 16; `test-readback-arm` 31; `test-scope-cleanup` 6; `test-comma-matchers` 5.
- CI: Windows dispatches on `05322521` (45753276346) and `d1155fe5` (45805158418) all green incl. 4 shards.
- 30 real screenshot payloads: rc=2 before, rc=0 after (#372). 5 MB image block through `tool_text`: 12 ms valid base64, about 90 ms near-base64. Whole hook with no READBACK.md: 15.1 ms branch vs 19.5 ms master (noise).
- Input-size fail-open (reviewer, macOS): scanner exits 126 at about 1,042,000 bytes of payload text (ARG_MAX 1,048,576 minus env). Linux about 131 KB: INFERRED, not run.
- Claim-gate hostile inputs: whole hook 0.1 to 0.9 s on 100 KB inputs.

### Rejected — do not rebuild
- Widening `TEST_CMD` for the advisory: would add new blocks (exit 2). Evidence-only regex instead.
- Whole-tool exemption of `mcp__claude-in-chrome__computer` from the injection scanner: not needed; the cause was image base64.
- "Join text blocks only" scanner design: stopped scanning other keys, changed text-only lists (44 cases 0 to 2), left mixed lists dumping base64.
- Async-only failure-tracker for readback: its output is dropped; asyncRewake: misleading "Stop hook blocking error" framing and wakes the parent from subagents; making PostToolUse sync: costs every Bash call.
- Counting exit-0 outputs that merely contain FAILED/Error markers: false positives (`pytest | tee`), and test-mask-guard covers masking.
- stop-verify options (b) git-tracked allowlist (a hostile repo's script is tracked), (c) global-only (kills the per-repo feature), (d) default-off env only, a `/sc-trust-verify` tool with `ask` (ask does not reliably prompt in auto mode or `claude -p`).
- A Supercharger orchestrator, `curl | bash` install for readback, Matt Pocock skills / Atlas as adopted tooling (OFF-thesis).

### Dead ends
- Reading the macOS job log of run 45616809167 (job 139214201078): "log not found", the job was cancelled before steps ran. Runner-not-acquired class.
- Agents cannot run `claude -p` or timing probes with heredoc'd regex text (guard denies); the probe is the user's.
- `git commit --only` of a git-ignored `.claude/PENDING-*.md` silently skipped (the `&&` chain stopped): check `git status` after a commit chain.

### Open questions
- UNKNOWN: does Claude Code fire both an interrupted `PostToolUse` and `PostToolUseFailure` for ONE call (a failure would count twice, S-13b pins "both count")? Probe: `docs/PENDING-2026-11-26.md` section 2.1; plus one real timeout and one Esc-interrupt.
- UNKNOWN: does `additionalContext` from an async PostToolUse hook reach the model? Design avoids relying on it.
- UNKNOWN: why run 45812105902 (Host contract on `6d07eb18`) was cancelled (inferred: duplicate-run concurrency cancel).
- UNKNOWN: whether Claude Code shows an image block's `data` to the model as text (inferred no).
- Open design call: block-once for the readback claim-gate arm.
- Not verified by me, reported by planners: the `stop-verify.sh` exec path (~lines 86-90, 205), the dead `SUPERCHARGER_VERIFY=0`, `typecheck.sh` / `quality-gate.sh` executing repo binaries, the list of ~40 hooks passing input via env.
- readback live plugin-hook test, render check, bash 5 / Windows `install.sh`, "go public": still the user's.

### Reproduce
- Suite: `bash tests/run.sh > LOG 2>&1; echo rc=$? >> LOG` (unpiped; read `rc=`). Do not switch branches while it runs.
- Gate and scanner: `bash tests/test-claim-evidence-gate.sh`, `bash tests/test-prompt-injection-scanner.sh`, `bash tests/test-readback-arm.sh`; `shellcheck --severity=error <files>`; `tools/gen-plugin-hooks.sh --check`; `tools/list-hooks.sh --check`.
- Windows: `gh workflow run ci.yml --ref <branch>`; PR CI skips it.
- Probe files: inline in `docs/PENDING-2026-11-26.md` (the scratchpad copies under `scratchpad/probe-u2/` may be gone).
- Scanner repro payloads were in the scratchpad (`p0..p29.json`, `mk.py`); may be cleared.

### Resume With
Resume claude-supercharger on master `e8c780f4`. Read `docs/PENDING-2026-11-26.md` and `.claude/handoff.md`. Ask the user for the probe result and the `stop-verify` decisions; build next in this order: stop-verify trust gate (Opus plan exists), covers-file PR for `Readback`, batch-editor PR. Merge/push only on the user's word; release stays on hold.

### Start With
- `/sc-why` only if a guard fires on a test command. Otherwise none: start with `gh pr list` and `docs/PENDING-2026-11-26.md`.
