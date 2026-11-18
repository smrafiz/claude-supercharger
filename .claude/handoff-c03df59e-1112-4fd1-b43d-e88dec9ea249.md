## Handoff — claude-supercharger — 2026-11-18

Session `c03df59e`. Reviewed tsrmehmet/memokit (MIT) and took "all the goodies" into five PRs.
Autopilot (full) was on for this session until 03:44.

### Done
- Reviewed https://github.com/tsrmehmet/memokit: replayed 701 of its destructive-command fixtures
  through our 24-hook Bash chain (probe: `scratchpad/memokit/probe.py`).
- **#325 `fix/memokit-delta`**: 7 gaps + 2 false denies (glued redirect hid `main`/`-f`; whole-word
  quotes; `git branch -df`; `git clean -e -nx`; `find $PWD/..`; `mysqladmin drop`; `helm un/del`;
  FPs `rm -rf x 2> /dev/null`, `eval "$(ssh-agent -s)"`). CI all green incl. Windows (run 44134525780).
- **#326 `feat/approval-codes`**: human-approval-gate now needs the user's `approve <code>` prompt
  (same hook on UserPromptSubmit); `approve <code> 30m` opens a per-category window (max 4h).
  Grant/window files selfmod-protected. PR checks green; Windows green in dispatch 44142633583.
- **#327 `feat/disk-watch`**: new PostToolUse(Failure) hook, warns on a ≥10 GB drop or <5 GB free.
  PR checks green; Windows green in dispatch 44133360338.
- **#328 `feat/office-read`**: opt-in (`SUPERCHARGER_MARKITDOWN=1`) Read redirect to a cached
  markitdown conversion. PR checks green; Windows green in dispatch 44142710536.
- **#329 `fix/quoted-pipe-fp`**: single-quoted `|` no longer reads as a pipe into a shell.
  Windows shards green; macOS still running at handoff.
- PR titles of #326/#328 fixed (gh `--fill` had used the branch name).

### In Flight
- #329 CI (dispatch 44143923492): macOS jobs not finished.
- Nothing merged. Merge order matters: see Blockers.

### Decisions Made
- Approval-gate semantics changed (#326): a retry alone is no longer approval. The old behaviour let
  Claude approve itself by retrying; the gate is opt-in, so the stricter meaning is the point of it.
- Window file named `.gate-granted-window-*` so the existing `.gate-granted` selfmod rule covers it
  (an edit adding `.gate-window` to the selfmod list was itself blocked by that rule).
- disk-watch baseline = previous Bash call, not a PreToolUse snapshot: one df fork per call.
- office-read stays out if ANY settings file has a Read deny/ask rule (a redirect would sidestep a
  rule naming the original path) and never denies.
- The rm redirect fix lives where `args` is built in `safety.sh`, not in the python resolver: the
  Windows text arm reads the same `args` (first fix was in python only and failed on Windows).

### What Failed
- First rm-redirect fix (python resolver only): Windows text arm still denied → moved to `args`.
- #326 on Windows: CR from CRLF jq stayed on the session id → no grant file matched. Fixed both sides.
- #328 on Windows: test fed MSYS paths to native python, and a shebang fake markitdown is not
  runnable by CreateProcess. Fixed with `shutil.which` + `cygpath -m` paths + a `.cmd` fake.
- Unquote pass in `normalize_cmd` first turned `git commit -m '-n'` into `--no-verify` → message
  values blanked before unquoting (caught by `tests/test-hook-bypass-forms.sh`).

### Blockers
- #326, #327, #328 each bump the full-mode hook count in `tests/test-install.sh` (175→176/177/176)
  and each regenerates `hooks/hooks.json` + `docs/HOOKS.md`. Whichever merges second needs a rebase:
  regenerate with `tools/gen-plugin-hooks.sh` and `tools/list-hooks.sh`, recount.
- 4.4.8 release is held by the user (carried from c8c4db43).

### Worktrees
- none (main checkout only; the user asked for no more worktrees — work in the main checkout).

### Files Touched
- See PR diffs #325–#329. Docs on this branch: `.claude/handoff.md`, `docs/HOOK_AUTHORING.md`.

### Resume With
Read `.claude/handoff.md`. Check CI on #325–#329, merge #325 and #329 first, then #326/#327/#328
one at a time, rebasing each on master and regenerating hooks.json/HOOKS.md and the install count.
Do not create worktrees; switch branches in the main checkout.

### Start With
none — `gh pr checks <N>` per PR is all that is needed.

### Measurements
- memokit fixtures through our Bash chain (701 commands, `scratchpad/memokit/probe.py`):
  allow→allow 207, allow→ask 2, allow→deny 6, deny→allow 381 (331 of them memokit's blanket
  recursive-rm policy, not ours), deny→ask 38, deny→deny 67.
- #325 replay over 14,811 real transcript Bash commands, master vs branch, 3 hooks: 0 verdicts changed
  (`scratchpad/vdiff.py`; harness validated by a 2-command sanity check that does differ).
- #329: fuzz-safety 5705 runs, 0 FN / 0 FP; replay 15,051 commands, 1 verdict changed (the FP fixed).
- disk-watch: 10 calls 0.164 s total (≈16 ms each incl. bash startup), df agreed with `df -Pk`.
- Full suites: #325 8362/0, #326 8347/0, #327 8342/0, #328 all green after lint fix, #329 8343/0.

### Rejected — do not rebuild
- memokit's blanket recursive-rm deny (outside build dirs): 331 of its rm fixtures; would flood us
  with false denies — policy difference, not a gap.
- `kubectl -n x delete pod` as a gap: a bare `kubectl delete pod` is allowed by design (pods are
  rescheduled). My oracle was wrong; compare with the bare form first.
- `git push --fo`: git rejects it as ambiguous (`--force-if-includes` / `--follow-tags`).
- Subagent-background gate (memokit check-subagent-background.sh): SubagentStop notes reach nobody on
  CC 2.1.318 and `SubagentHandback` is not offered offline (host-contract). Unverifiable → not built.
- Scratchpad cleanup and state-stale warning: covered by the harness and the handoff carry file.

### Dead ends
- Local Windows simulation of the Windows-only rm arm via `OSTYPE`: rc=1 on old and new code alike,
  proves nothing. Windows CI is the only oracle.
- guard-replay.py `--json` keeps only crashes (`tally`, `bad`), not per-call verdicts: use vdiff.py.

### Open questions
- Pre-existing, unverified-as-intended: `ssh host 'curl … | sh'`, `watch '…'`, `tmux send-keys '…'`,
  `script -c '…'` are ALLOWED (quoted remote/deferred bodies are not appended as segments).
  Verified allowed on master; whether to add them is a design question.
- office-read verified only with a fake markitdown (none installed here).
- #326 CR fix: Windows CI green; local CRLF-jq simulation could not reproduce the illegal-filename part.

### Reproduce
`scratchpad/` = `/private/tmp/claude-501/-Users-srafiz-GithubProjects-claude-supercharger/c03df59e-1112-4fd1-b43d-e88dec9ea249/scratchpad`
on c03df59e's machine only; /tmp, so it may be gone. vdiff.py is ~40 lines: rebuild from the
description (distinct Bash commands from the newest 600 transcripts, run 3 hooks under both trees).
- Fixture replay: `python3 -I scratchpad/memokit/probe.py <scratch> <repo>` (fixtures.json from
  memokit's `tests/careful*.bats`).
- Verdict diff vs master: `git worktree add --detach <scratch>/master-wt master` then
  `python3 -I scratchpad/vdiff.py <scratch> <repo>`, then remove the worktree.
- Per-PR tests: `tests/test-memokit-delta.sh`, `tests/test-human-approval-gate.sh`,
  `tests/test-disk-watch.sh`, `tests/test-office-read.sh`, `tests/test-quoted-pipe.sh`.
- Windows artifacts: `gh run download <run> -D <dir>`; grep `FAIL` in `windows-suite-log*`.
