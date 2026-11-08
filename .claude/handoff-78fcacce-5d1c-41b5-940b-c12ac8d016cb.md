## Handoff — claude-supercharger — 2026-11-08 (deep; session 78fcacce)

### Done
- **v4.4.5 released** 2026-11-08 (`bda06a90`, tag v4.4.5). This machine (per-machine) updated 4.4.3 → 4.4.5 via `/sc-update`.
- **#263** (`b9ad1f04`): `tools/release.sh` filters all 4 `gh run list` calls with `--workflow ci.yml`. Before it, stage/promote read `runs[0]`, which was the Host contract run, so stage ran the ~55-min local gate and promote said Windows "missing". Tests: `tests/test-release-stage-promote.sh` (+2, both fail unfixed).
- **#264** (`5e16bfb1`): `hooks/package-credibility.py` + `-guard.sh` deny an install that OSV lists as malware (MAL- ids): either the version being installed is on the list, or other versions are and the package lacks credibility. Source: agent-security-playbook audit.
- **#265** (`ee056e15`): `hooks/lib_config_checks.py` warns when a project settings file committed by someone else pre-approves an outward command (git push, publish, gh write verbs, curl, scp…). Source: nook-web-app audit.
- Memory: `repo-audits-index.md` (+2 repos), `project-hold-release-4-4-4.md` (4.4.6 held).

### In Flight
- **Master is RED on Windows** at `5e16bfb1` and `ee056e15` (ci.yml runs 42467464473, 42471021887). Linux + macOS green. Both new test files fail on Windows only:
  - `test-package-credibility`: 5/34 fail, all malware tests. Got `goodpkg does NOT EXIST on npm` (or empty): the stubbed curl is not answering on Windows.
  - `test-config-scan-outward-allow`: 3/6 fail, every "is named" case. No warning, so `committed_by_someone_else` returns False on Windows.
  - Not diagnosed. Logs: `gh run download 42471021887 -n windows-suite-log`.
- **Release 4.4.6 (#264 + #265) is HELD** until the user says to release. Windows has to be green first, or promote will refuse.

### Decisions Made
- Release only on the user's explicit word, for this batch too ("merge it when green and but hold the release").
- The OSV check is credibility-aware rather than exact-version only: `dsh-notify-focus` latest `0.0.0-stage` is not in its MAL version list, but the package is malicious.
- gh outward verbs are the write verbs only: `gh pr view` fired at first and was dropped.
- Merged #264/#265 on "green", which then meant the PR checks. PR CI does not run Windows, so "green" did not include it. That is how the red got to master.

### What Failed
- Promote #1: master had diverged (docs commit `942165fb`). Fix: deleted unpromoted `rel/4.4.5` (`ec72f63a`), re-staged.
- I estimated the stage gate at 7 min; it ran ~55 min (the #263 bug). I caused the wrong estimate.
- #264 first CI: I moved the `Disable:` header line past line 40 (`tests/test-hook-contracts.sh:30`) and ran no full suite first. 2 fails. I caused this.
- #264/#265 merged with Windows untested → master red. **I caused this.**

### Blockers
- Windows red on master: diagnose + fix the 8 failing tests, then confirm Windows green before any release.

### Worktrees
- `.claude/worktrees/ep` (`ci/test-pool`, `390be2a3`, 2026-11-05): no PR and not merged. **It has uncommitted changes**: `.claude/handoff.md`, `.claude/handoff-3d213381…md` and `docs/HOOK_AUTHORING.md` modified; `tests/run-waves-baseline.sh` untracked. Left alone (per-machine).
- Stashes (per-machine): 5, the oldest from 4.3.0. Left alone.

### Files Touched
- `tools/release.sh`, `tests/test-release-stage-promote.sh` (#263)
- `hooks/package-credibility.py`, `hooks/package-credibility-guard.sh`, `tests/test-package-credibility.sh` (#264)
- `hooks/lib_config_checks.py`, `tests/test-config-scan-outward-allow.sh` (#265)
- `.claude/handoff.md`, `docs/HOOK_AUTHORING.md` (this handoff)

### Resume With
Master `ee056e15` is red on Windows only. 8 tests fail in `test-package-credibility` (malware stubs) and `test-config-scan-outward-allow` (git-author check), runs 42467464473 and 42471021887. Fix them on a branch and dispatch Windows with `gh workflow run ci.yml --ref <branch>`. Do not release 4.4.6 until the user says to.

### Start With
- `gh run download 42471021887 -n windows-suite-log`. It has the full FAIL lines.
- `/sc-stuck` if the Windows fix takes more than two CI rounds.

### Measurements
- Full suite: 7624 (#262) → +9 (#264), +6 (#265). Local #265 run: 7638 passed, 1 failed (`test-audit-gaps-1026.sh` curl -F 0x0.st got ASK; it passed 3/3 in isolation; load average 12.40 18.12 21.59).
- Windows (run 42471021887): 325 files, 323 clean. package-credibility 29 pass / 5 fail; config-scan-outward-allow 3 pass / 3 fail.
- Unfixed-code checks: the #263 tests 2/2 fail; #264 5/9 fail; #265 3/6 fail.
- Stage gate with the #263 bug: ~55 min. After #263 the gate was skipped (master CI green on HEAD).
- Update cache TTL is 21600 s (`hooks/update-check.sh`). The notice lagged because the cache was fetched 09:41 with 4.4.4 and expires 15:41.

### Rejected — do not rebuild
- Exact-version OSV matching alone: it missed `dsh-notify-focus` (MAL ids exist, latest `0.0.0-stage` is unlisted).
- Treating every `gh` call as outward: `gh pr view` is a read and fired.
- A patched local copy of release.sh to finish 4.4.5: the user chose fix-first (#263).
- Running `/sc-security` on nook-web-app: it is a third party's live app with no license.

### Dead ends
- `gh run watch` exits rc=1 early here, so it gives no result. Poll `gh run view --json status` instead.
- `gh run view --log-failed | grep FAIL` shows only the step script. The per-test lines are in the `windows-suite-log` artifact.

### Open questions
- Why the curl stub misses on Windows: one guess is that native Windows Python resolves `curl` to `curl.exe` and bypasses the bash stub on PATH. Unverified.
- Why `committed_by_someone_else` returns False on Windows: one guess is the `D:\` path, git config isolation, or a git failure that is swallowed and falls back to False. Unverified.
- Whether `test-audit-gaps-1026.sh` under load is a real timeout-to-ASK fallback or a test race. Unverified.
- Global-option sweep for pulumi, flyctl, gh, eksctl: not started.

### Reproduce
- `bash tests/test-package-credibility.sh; bash tests/test-config-scan-outward-allow.sh` (they pass on macOS).
- `gh run list --branch master --workflow ci.yml --limit 3`
- Scratchpad (session-only): `/private/tmp/claude-501/-Users-radiustheme-GithubRepos-claude-supercharger/78fcacce-5d1c-41b5-940b-c12ac8d016cb/scratchpad/winart/win-suite.log`
