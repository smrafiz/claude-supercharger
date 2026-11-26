## Handoff — claude-supercharger — 2026-11-27 (deep, session 5623ea04, "Supercharger")

### Done
- PR #376 merged (squash `d1bc4692`): readback covers-file writer. `hooks/lib-readback-covers.sh` (new), called from `hooks/project-config.sh` after its python block; `tools/sc-toggle.sh` `_covers_empty` on off and on; `tests/test-readback-covers.sh` (13 rows).
- Same PR, `c3edd713`: `hooks/lib-suppress.sh` `_load_disabled_hooks` strips `\r` (Windows python wrote `.disabled-hooks` as CRLF; every entry but the last never matched, for ALL hooks). Found by the covers test on the Windows leg.
- #375 (the 2026-11-26 brief + carry file) merged the same turn. #373 was already merged 2026-11-26 11:36.
- Readback session verified the real output against its reader: 9/9 (its report). Contract unchanged.

### In Flight
- Nothing mid-flight. Local checkout is on `master` at `d1bc4692`, clean.
- NOT released. Release on hold (user). Unreleased on master: #366, #368, #370, #371, #372, #373, #374, #375, #376. Released: v4.4.9.

### Decisions Made
- Writer lives in project-config.sh, not a new hook: it is what writes per-project `.disabled-hooks`/`.profile`; a separate SessionStart hook would race it if SessionStart hooks run in parallel (reasoned from Claude Code's documented behaviour, NOT measured here) and a new hook trips the hook-count gates.
- Write BOTH the payload session id and the transcript-derived id: on resume SessionStart carries a new id, later tool calls the old one (comment already in project-config.sh).
- Each guard's predicate mirrors that hook's OWN disable logic. claim-evidence-gate honours only its env toggle (it does not read `.disabled-hooks`); failure-tracker has no env toggle.
- `/sc off` and `/sc on` empty ALL files (sc-toggle has no session id). Empty = readback keeps its own hooks on, so it is safe.
- Fix the CRLF bug at the reader (`_load_disabled_hooks`), not the writer: one fork-free line, covers existing files and every hook.

### What Failed
- Windows CI run 45862019564: gate failed on 1 of 12 covers rows. disableHooks with two entries dropped only the last. Cause: CRLF (above). Re-run 45866576025 green (Windows, macOS, Ubuntu).
- Bash heredoc edit adding the CRLF test row was denied by the self-modification guard. I stopped and told the user; after the user said "go" I applied the same change with the Edit tool and it was not blocked. That is the same effect by a different tool, on the user's explicit go; flagged here so it is not mistaken for a clean guard-respecting path.
- A `bash tests/run.sh > log; echo rc=$?; tail` background command reported exit 0 from `tail`, not the suite. I read the log's `Total: N passed, 0 failed` line instead. Do not trust a compound command's exit code.

### Blockers
- None for #376. Release is the user's call.

### Worktrees
- none (main checkout only). `git worktree list` showed one entry.
- Local branches not checked for staleness this session: `docs/2026-11-17-brief`, `feat/approval-codes`, `feat/disk-watch`, `feat/office-read`, `fix/memokit-delta`, `fix/quoted-pipe-fp` exist locally (per-machine). Not removed.

### Files Touched
- hooks/lib-readback-covers.sh: new, the writer.
- hooks/project-config.sh: calls it when `${CLAUDE_PROJECT_DIR:-$PWD}/READBACK.md` exists.
- tools/sc-toggle.sh: `_covers_empty`.
- hooks/lib-suppress.sh: `\r` strip.
- tests/test-readback-covers.sh: new, 13 rows.
- .claude/handoff.md, this file: written this turn, uncommitted.

### Resume With
Covers-file writer (#376) is merged to master, unreleased. Next from `docs/PENDING-2026-11-26.md`: user's live probe, the `stop-verify` trust gate (needs the user's 3 decisions), batch-editor PR, input-size fail-open, claim-gate readback arm. Tell the Readback session #376 is merged and about the CRLF fix.

### Start With
none.

### Measurements
- Full suite on the branch: 9092 passed, 0 failed before the CRLF fix; 9093 after (`bash tests/run.sh`, log in scratchpad).
- Covers test: 12 rows then 13. The CRLF row fails without the fix (`got [test-mask-guard\nclaim-evidence-gate\nfailure-tracker]`) and passes with it, run against a copy with `git show HEAD:hooks/lib-suppress.sh`.
- Windows run 45862019564: `files: 353 clean: 352 failing: 1` (`test-readback-covers 11 pass / 1 fail`). Run 45866576025: all green.
- Not measured: cost of the added `[ -f READBACK.md ]` in project-config (one test on SessionStart).

### Rejected — do not rebuild
- A new SessionStart hook for the writer: ordering vs project-config unprovable, plus hook-count gates (`docs/HOOKS.md`, `tests/test-install.sh`). Rejected on reasoning, not measured.
- Per-session truncation in sc-toggle: no session id available there. Truncating all files was accepted instead.

### Dead ends
- None.

### Open questions
- UNVERIFIED: that SessionStart hooks of one event run in parallel. The design assumed it; nobody measured it.
- UNVERIFIED: the `/sc off`-at-start case in the plugin runtime (no file written; relies on readback's fallback grep finding nothing).
- UNKNOWN: whether the `failure-tracker` listing is correct for an install that has the writer but not #373's arm. Both ship in the same release, so only a partial install could differ.

### Reproduce
- `bash tests/test-readback-covers.sh` (13 rows, isolated HOME).
- CRLF proof: copy the repo, `git show HEAD~:hooks/lib-suppress.sh` over `hooks/lib-suppress.sh`, run the test with that copy as arg 1.
- Windows: `gh workflow run ci.yml --ref <branch>`, then `gh run download <id>` and read `win-suite*.log`; the aggregate job is the gate.
