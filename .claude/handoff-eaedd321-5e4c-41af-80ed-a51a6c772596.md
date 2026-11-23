## Handoff — claude-supercharger — 2026-11-23 (session eaedd321, deep)

### Done
- Merged #357 (perf-chain fork-count fallback), #359 (docs), and four features/fixes, each with a full
  suite and a Windows dispatch before merge:
  - #360 `4f6080b4` download ledger: a file downloaded in one Bash call, then chmod'd/run in a later
    one, gets an ASK (`hooks/safety-detect.py` `check_download_ledger`, `scope/.downloads-<sid>`).
  - #361 `2c7156d0` `hooks/git-safety.sh` internal failure blocks with a stderr reason (peer report of
    "failed … No stderr output"; not reproduced 30/30, likely load after a reboot).
  - #362 `6724ac00` model-ask guard: asks before an Agent/agent file/Bash command uses a listed model
    (default `fable`); statusline warning; Stop notice. `SUPERCHARGER_MODEL_ASK`.
  - #363 `e19b7050` detector gets cmd/code on stdin (Git Bash rewrote env values on Windows).
- Peer questions: `/sc-handoff` is `disable-model-invocation: true` by design; noorjar `74184b6` was
  pushed from the user's own clone 23 s after commit, not by a Claude session (likely editor git sync).
- Fable usage traced: 64 messages, session start model 2026-11-18; none in subagents here.
- Memory index trimmed 22,455 → 19,587 bytes, all 134 entries kept.

### In Flight
- none. Master `e19b7050`, clean.

### Decisions Made
- Never use Fable (user): saved to memory; Supercharger asks, never blocks (user chose ask).
- Full autopilot does not approve the model ask (`SC_ASK_KEEP=1`).
- Release 4.4.9 tomorrow (2026-11-24) on the user's word; speed re-measure first if load < ~10.

### What Failed
- #360 Windows row failed 5 times; 3 guessed fixes before a diagnostic showed the env rewrite.
- I twice switched branches under a running background suite (results invalid, reruns ~40 min each).
- I merged #363 while its macOS check was pending (`gh pr checks --watch` returned early); it passed.

### Blockers
- Machine load 30–103 all day: blocks the speed re-measure.

### Worktrees
- none (main checkout only)

### Files Touched
- See #360–#363 diffs. This handoff: this brief, `.claude/handoff.md`, `docs/HOOK_AUTHORING.md`
  ("Notes from 2026-11-23").

### Resume With
Read `.claude/handoff.md`. If load < ~10, run `tests/perf-chain.sh` on v4.4.8 vs master; then, on the
user's word, release 4.4.9 (stage, rel CI, promote) and run `/sc-update` so the model-ask guard is live.

### Start With
- none (`uptime` first)

### Measurements
- Suites: #360 8803/0 (ea85f0f7); #361 8788/0; #362 combined 8827/0 (f937fa6e); #363 8836/0 (e5e01caa).
- Windows runs passed: #360 45139312925, #361 45124040701, #363 45163322407.
- MSYS env probe (run 45159143262): rewritten when the value starts with `/` or has no spaces;
  `cat /etc/passwd` and `chmod +x /tmp/a && /tmp/a` intact.
- git-safety.sh peer probe: 30/30 pass, max 0.45 s, at load 167–301.

### Rejected — do not rebuild
- Fable: blocking. User chose ask.
- `_dl_path` isabs guess for Windows `/tmp/h`: reverted; the cause was the env rewrite, not isabs.

### Dead ends
- "Python 3.13 isabs change" for #360: runner is 3.12.10, `isabs` True.
- Which Claude session pushed noorjar `74184b6`: no transcript has a push at 17:56:40 +0600.

### Open questions
- Is #354's `safety.sh` slowdown real? Unverified (load). Settle: quiet machine, `tests/perf-chain.sh`.
- Does the model-ask guard fire in a live Claude Code session (Agent with model fable; Stop notice)?
  Unverified; try after `/sc-update`.
- Why did git-safety.sh fail silently in the peer session? Unknown; #361 makes the next one visible.

### Reproduce
- `bash tests/test-download-ledger.sh`, `tests/test-model-ask-guard.sh`,
  `tests/test-git-safety-fail-closed.sh`, `tests/test-detector-env-msys.sh`.
- Windows: `gh workflow run ci.yml --ref <branch>`, then `gh run download <id> -D dir`, grep `^ *FAIL `.
