## Handoff — claude-supercharger — 2026-11-27 (deep, session 5623ea04, "Supercharger", updated after #377)

### Done
- PR #376 merged (squash `d1bc4692`): readback covers-file writer. `hooks/lib-readback-covers.sh` (new), called from `hooks/project-config.sh` after its python block; `tools/sc-toggle.sh` `_covers_empty` on off and on; `tests/test-readback-covers.sh` (13 rows).
- Same PR, `c3edd713`: `hooks/lib-suppress.sh` `_load_disabled_hooks` strips `\r` (Windows python wrote `.disabled-hooks` as CRLF; every entry but the last never matched, for ALL hooks). Found by the covers test on the Windows leg.
- #375 (the 2026-11-26 brief + carry file) merged the same turn. #373 was already merged 2026-11-26.
- PR #377 merged (squash `6064cc01`), on the user's word: `hooks/claim-evidence-gate.sh` `TERMINATED_RE` used `\\b` inside raw strings (a literal backslash + b), so a bare `Exit code 143` / SIGTERM with no "timed out" text fell through to a contradicted block. Fixed; new row in `tests/test-claim-evidence-gate.sh`. Also `tests/test-readback-arm.sh` row "single JSON object" could pass with zero output, now requires at least one nudge; one-line comment in `hooks/lib-readback.sh` on `sc_rb_gates`' reliance on the caller's `[ -f ]`.
- Master CI on `a74be28c` (CI and Host contract) was read: success. #377 branch CI: Windows (run 45954965831, aggregate gate and 4 shards), macOS and Ubuntu all success.
- Told the `Readback` peer about #376 and the CRLF fix (message delivered to its inbox). Answered its installer-hooks questions with repo facts. NOT yet told about #377.
- Research only, nothing built: a GUI for Supercharger (see Open questions).

### In Flight
- Nothing mid-flight. Local checkout `master` at `6064cc01`, in sync with origin, clean at the time of writing (before this brief's commit).
- NOT released. Release on hold (user). Unreleased on master: #366, #368, #370-#377. Released: v4.4.9.
- Autopilot (per-session, full) was enabled until 20:42 on 2026-11-27; it expires on its own.

### Decisions Made
- Writer lives in project-config.sh, not a new hook: it is what writes per-project `.disabled-hooks`/`.profile`; a separate SessionStart hook would race it if SessionStart hooks run in parallel (reasoned, NOT measured) and a new hook trips the hook-count gates.
- Write BOTH the payload session id and the transcript-derived id: on resume SessionStart carries a new id, later tool calls the old one.
- Each guard's predicate mirrors that hook's OWN disable logic. claim-evidence-gate honours only its env toggle; failure-tracker has no env toggle.
- `/sc off` and `/sc on` empty ALL covers files (sc-toggle has no session id). Empty = readback keeps its own hooks on, so it is safe.
- CRLF fixed at the reader (`_load_disabled_hooks`), not the writer.
- #377 scoped to three small nits only; the claim-gate readback arm (block-once) was NOT started: it needs the user's decision and a rebase on #370.

### What Failed
- Windows CI run 45862019564: covers row failed (CRLF, above). Re-run 45866576025 green.
- Bash heredoc edit to a test was denied by the self-modification guard (earlier in this session). Told the user; after "go" I used the Edit tool, not blocked. Same effect by a different tool, on the user's go; flagged so it is not read as a clean guard-respecting path.
- #377 first draft of the 143 test row passed on the UNFIXED code: its claim text ("Tests all pass.") did not match the gate's CLAIM pattern, so the gate never reached the termination branch. Reworded to "All tests pass — the suite is green." and re-ran against the old regex: FAIL, then PASS after the fix. A green row is not a proof until it fails on the old code.
- A `bash tests/run.sh > log; echo rc=$?; tail` compound reported the exit of `tail`. Read the log's `Total:` line instead.

### Blockers
- None. Merges, release and the claim-gate block-once decision are the user's.

### Worktrees
- none (main checkout only; `git worktree list` showed one entry).
- Local branches, per-machine, none on origin (`git ls-remote --heads` returned 0 for each), each ahead of master: `docs/2026-11-17-brief` (2), `feat/approval-codes` (3), `feat/disk-watch` (1), `feat/office-read` (4), `fix/memokit-delta` (2), `fix/quoted-pipe-fp` (1). `git branch --merged master` lists only master, but squash merges do not show there, so merged-or-abandoned is UNKNOWN. Not removed.

### Files Touched
- hooks/lib-readback-covers.sh (new), hooks/project-config.sh, tools/sc-toggle.sh, hooks/lib-suppress.sh, tests/test-readback-covers.sh (new): #376.
- hooks/claim-evidence-gate.sh, hooks/lib-readback.sh, tests/test-claim-evidence-gate.sh, tests/test-readback-arm.sh: #377.
- .claude/handoff.md, this file: rewritten this turn.
- Memory: `diagnosing-windows-ci-failures.md` has the eighth trap (CRLF). Updated again this turn, see below.

### Resume With
Master `6064cc01` has #376 and #377 merged, unreleased. Next from `docs/PENDING-2026-11-26.md`: the user's #373 live probe, the `stop-verify` trust gate (needs 3 decisions), batch-editor PR, input-size fail-open, claim-gate readback arm (needs the block-once decision). Tell Readback #377 merged if it matters to them.

### Start With
none.

### Measurements
- Full suite on the #377 branch: 9094 passed, 0 failed (`bash tests/run.sh`, log `scratchpad/full3.log`). #376: 9092 then 9093.
- Covers test 13 rows; claim-gate test 95 rows passing after the new row; readback-arm 31 rows.
- 143 row: FAIL on the unfixed regex (`bare exit code 143 treated as a test failure`), PASS after.
- Windows run 45954965831: success, aggregate and 4 shards. Earlier Windows failure run 45862019564: `files: 353 clean: 352 failing: 1`.
- Not measured: cost of the added `[ -f READBACK.md ]` in project-config (one test on SessionStart).

### Rejected — do not rebuild
- A new SessionStart hook for the covers writer: ordering vs project-config unprovable, plus hook-count gates (`docs/HOOKS.md`, `tests/test-install.sh`). Rejected on reasoning, not measured.
- Per-session truncation in sc-toggle: no session id there; truncating all files accepted.
- A standalone GUI app (Electron/desktop) for Supercharger: not built; packaging, signing and Windows work for what a read-only pane or static report covers. Reasoned, not measured.
- A localhost dashboard server with toggle buttons: not built; adds a long-running process and a new write path to `settings.json`, the surface the self-modification guard protects.

### Dead ends
- None.

### Open questions
- UNVERIFIED: SessionStart hooks of one event run in parallel (the design assumed it).
- UNVERIFIED: `/sc off` at session start in the plugin runtime writes no file; relies on readback's fallback grep.
- UNKNOWN: whether users want a GUI at all (roadmap memory still lists the user question as unanswered).
- GUI probe, from the mods API types (`$TMP/bundled-skills/.../plugin-authoring/types/claude-code.d.ts`): a mod can `$.fs.read/list/stat` absolute paths and `$.process.run(argv)` with no shell, CLI only, so it can read `~/.claude/supercharger/audit`, `scope`, `receipts` and call `tools/hook-toggle.sh` / `sc-toggle.sh` / `autopilot.sh`. UNKNOWN: whether a command run through `$.process.run` passes through Supercharger's PreToolUse guards (it is not a tool call, so probably not), which would put a toggle button's write path outside the self-modification guard. UNKNOWN: another mod's `fs.*` hook can refuse a path ("where one may go is an `fs.*` hook's to say"). Mods need Claude Code 2.1.314-2.1.326 depending on the feature (from a subagent's read of 40k of 88k characters of the official page; the types file was read directly).
- UNVERIFIED: third-party Claude Code GUIs found by search (ccboard, CCHub, Claude Code GUI, Clawdboard, Agent Monitor, Claudia): search snippets only; some write hook entries into `settings.json`, which would collide with `#supercharger` tags.
- UNVERIFIED: `install.sh` has no plugin-coexistence detection (grep for "plugin" in install.sh found nothing); installer-written plus plugin hooks might double-register. Not tested.
- UNKNOWN: the six local branches' merged-or-abandoned state.

### Reproduce
- `bash tests/test-readback-covers.sh` (13 rows), `bash tests/test-claim-evidence-gate.sh`, `bash tests/test-readback-arm.sh`.
- 143 proof: revert the `\b` fix in `hooks/claim-evidence-gate.sh` (`\\b` in the raw string) and run the claim-gate test; the "bare SIGTERM" row fails.
- Windows: `gh workflow run ci.yml --ref <branch>`, then `gh run view <id> --json conclusion,jobs`; the aggregate "Windows (Git Bash)" job is the gate; on a failure `gh run download <id>` and read `win-suite*.log`.
- Mods probe: `grep -n 'fs: {\|process: {' $TMP/bundled-skills/*/plugin-authoring/types/claude-code.d.ts` (the path changes per Claude Code version and session).
