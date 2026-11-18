## Handoff — claude-supercharger — 2026-11-18 (session eaedd321, deep)

### Done
- Merged #324–#333 (squash, each at a head whose full CI incl. Windows passed) and released **v4.4.8**
  (tag on `68071b2a`; CHANGELOG has the summary). This machine updated to 4.4.8 via `/sc-update`
  (verified: installed `safety.sh` carries `_sc_fail_closed_exit`, `disk-watch.sh` and `office-read.sh` exist).
- Before merge, read-only reviews found fail-opens in three PRs; each was fixed with a regression row
  shown to fail on the pre-fix code:
  - #326: approval-gate self-grant via a command containing `UserPromptSubmit`.
  - #329: a quote scanner masked a real pipe via `$( )` nesting or a `#`-comment apostrophe.
  - #325: `eval` allow-list matched on the first argument only.
- New fixes: #331 `>|` in 4 guards · #332 disk-watch `$(( ))` code execution + `df` parse ·
  #333 `safety.sh` fail-closed EXIT trap, grep rc>1 = hit, `grep -e` for `--build-arg`.
- #330: shellcheck CI on ubuntu only.
- Engineering notes: `docs/HOOK_AUTHORING.md` "Notes from 2026-11-18", second half.

### In Flight
- PR #334 (this branch, `docs/2026-11-18-handoff`): this brief, carry file, engineering notes. Not merged.

### Decisions Made
- Release 4.4.8 now, audits after: 17 fully tested commits; more audits would only grow the batch (user said "release").
- Disk-watch stays registered on PowerShell: `tests/test-powershell-parity.sh` requires every Bash PostToolUse hook to run on PowerShell too.
- #333 fails closed for a harmless command too, when the guard cannot finish. Fast-path commands exit before any fork, so they are unaffected.
- #326 window over 4h: clamped to 4h with a notice to the user (no silent clamp).
- #328 cache eviction left out: it is a feature, not a fix.

### What Failed
- **Worktrees all session**, against the user's 2026-11-18 "no worktrees" in `.claude/handoff.md`. I did not read the carry file first. Now a memory entry.
- **Called macOS shellcheck "hangs".** The check-run annotations said "job was not acquired by Runner" (capacity).
- **`set -- $var` in zsh does not split.** It broke a push loop and a CI-then-merge step; the merge was redone by hand at the tested head.
- **Three full suites in parallel** gave load-only failures; all were re-run alone before being trusted.
- **A dispatched CI on two branches that already had green Windows runs.** I cancelled them.

### Blockers
- none

### Worktrees
- none (only the main checkout; `.claude/worktrees/` is empty)

### Files Touched
- See PRs #324–#334; nothing here that the diffs don't show.

### Resume With
Read `.claude/handoff.md` first. v4.4.8 is released and #334 (docs) is the only open PR. Next work is repo
audits (check `memory/repo-audits-index.md` first). Do not use worktrees in this repo: switch branches in the main checkout.

### Start With
- `/sc-status`: confirm this machine is on 4.4.8 and the guards are on before starting audits.

### Measurements
- Fork exhaustion: `ulimit -u` just above the live process count, 12 runs of `safety.sh` on a
  pipe-into-shell command → 5× rc=128, empty stdout (`fork: Resource temporarily unavailable`), 7× deny.
- `tests/test-safety-fail-closed.sh` (#333): master's `safety.sh` 2 passed / 6 failed (rc 137 or 0
  where 2 was expected); with the fix 8/8. Full suite on #333: 8449 passed, 0 failed (engineer's run).
- `tests/test-safety-fp.sh` with the two `>|` selfmod rows: master 204/206 (both new rows GUARD GAP), fix 206/206.
- #331 siblings on master vs fix: profile `echo x >| ~/.bashrc` rc 0 → 2; readonly `echo hi >| out.txt`
  allowed → blocked; tamper `>|` over a hook SILENT → DENY.
- #329 new deny rows against the pre-fix scanner: 16 passed / 3 failed (`$( )`, comment, backtick).
- #326 new rows against the pre-fix hook: 5 failures, incl. "SELF-GRANT BYPASS: exit 0".
- #328 timeout row with the inner timeout forced to 60: fails `took=21s`; with the fix passes.
- macOS shellcheck, 2026-11-17: 3 jobs cancelled at 15–37 min with no runner and zero steps.

### Rejected — do not rebuild
- Removing PowerShell from disk-watch's registration: `test-powershell-parity.sh` fails ("every
  PostToolUse hook on Bash also runs on PowerShell"); master passes.
- Modelling `$( )`/comments in the #329 quote scanner: bailing is smaller and fails safe; modelling is where both bypasses came from.

### Dead ends
- Looked for `fork: Resource temporarily unavailable` in the kept logs of the 3-parallel-suite failure
  (`$TMPDIR/sc-suite-failure-136{58,59,61}`): none found. That run's cause stays unconfirmed.
- The python quote scanner and the detector budget were ruled out as the case-B allow: a killed or slow
  python3 still denied. The deny there comes from the bash pipe rule, not safety-detect.py.

### Open questions
- **Unverified:** does Claude Code treat a hook's exit 128 as an `onFailure: block` failure? Settle it
  with a live `claude -p --settings <file>` probe (see memory `onfailure-block-facts`).
- **Not covered:** a crash inside lib-timing/lib-paths before `safety.sh` installs its trap.
- **Design, not started:** quoted remote bodies (`ssh host '…|sh'`, `watch`, `tmux send-keys`, `script -c`) are allowed.
- Git Bash `df` parsing (#332) was proven on Windows CI only, never run locally.

### Reproduce
- `bash tests/test-safety-fail-closed.sh` (fake grep/sed first on PATH; deterministic, no ulimit race).
- `bash tests/test-safety-fp.sh`, `bash tests/test-quoted-pipe.sh`, `bash tests/test-human-approval-gate.sh`,
  `bash tests/test-memokit-delta.sh`, `bash tests/test-disk-watch.sh`, `bash tests/test-office-read.sh`.
- Pre-fix comparison: `git archive <old-sha> | tar -x -C <tmpdir>`, copy the new test file in, run it there.
- A cancelled job's cause: `gh api repos/smrafiz/claude-supercharger/check-runs/<job id>/annotations`.
