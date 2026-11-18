## Handoff — claude-supercharger — 2026-11-17 (deep)

### Done
- **#319 → 7a8f54ea.** `/sc-security` skill-scan FP: a command file byte-identical to a shipped one
  (hash in `configs/commands-shipped.txt`) keeps only CRITICAL findings.
- **#320 → 3d3fde96.** `local LC_ALL=C` in `normalize_cmd` (`hooks/cmd-normalize.sh`); see Measurements.
- **#321 → 24aac44f.** cc-safety-net v2.7.14+ container ideas: deny a recursive rm of a bind-mounted
  project dir inside `docker|podman run` (`check_container_rm_mount` in `hooks/safety-detect.py`);
  a mount-less single `docker run … rm -rf /x` no longer gets the outside-project ASK.
  Test `tests/test-container-mount-rm.sh` (20 rows).
- **#322 → 0f45926f.** `/sc-security` Step 4b "Chains" (idea from dmdhrumilmistry/indra, own wording).
- **#323 → fe1e423f.** `/sc-health` fails Security on `allowManagedHooksOnly: true` in managed
  settings; prints unscored hardening lines (subprocess env scrub, bypass-permissions mode).
- Repo audits (all in memory `repo-audits-index.md`): cc-safety-net (ported → #321), unifi-dashboard,
  indra (→ #322), pandaward, ai-coding-starter-kit, claude-security-skills, Claude_Code_Security_Labs (→ #323).
- Branch cleanup: only `master` locally; deleted feat/supply-chain-gaps and two empty agent branches.

### In Flight
- **Release 4.4.8 held by the user** ("hold the release for now"): covers #319–#323. Release only
  on their word; it is not an issue to report.

### Decisions Made
- Hold 4.4.8 (user).
- indra: take chaining only; SARIF skipped until there is a CI mode (user agreed).
- Skill `` !`cmd` ``: no poison-pattern rule; the live probe showed it runs through the Bash tool.
- `/sc-health`: `allowUnsandboxedCommands` not shown (matters only with the sandbox on).

### What Failed
- #321 first Windows CI (run 44052487166): 7 rows. 5 expected an ASK that native Windows skips;
  2 compared `/c/Users/…` to a `C:\…` CWD. Fixed with `$HOST_RM` expectations and `_host_path_key`.
- #321 container-only check first read normalized `CMD` and still asked; fixed by `CMD="$COMMAND"`.
- Bang probe launched with the skip-permissions flag: denied by harness-tamper (correct). The
  same guard also denied a later heredoc that only MENTIONED the flag in text (FP, not fixed).

### Blockers
- none.

### Worktrees
- `.claude/worktrees/docs-1117` (docs/2026-11-17-brief): active, this brief's PR. Remove after merge.

### Files Touched
- See PRs #319–#323; this PR: `docs/HOOK_AUTHORING.md` (Notes from 2026-11-17), this brief, `.claude/handoff.md`.

### Resume With
Read `.claude/handoff.md`. Nothing is in flight except the held 4.4.8 release (#319–#323), which
waits for the user's word. Next optional work: harness-tamper FP on the flag in heredoc text.

### Start With
- none required. `/sc-health` to see the new hardening lines on this machine.

### Measurements
- `normalize_cmd` on a 63,386-byte `$( )` payload (scratchpad `nc_time.sh`): master 12.49/13.00/13.72 s
  vs LC_ALL=C 7.22/7.69/8.13 s at load 21–55; master 123.57/94.05/46.34 s vs 62.29/24.97/24.70 s at load ≈115.
- #321 replay (`ctr_replay.py`): 60,236 unique transcript commands, 36 docker/podman, 2,036 replayed, 0 verdicts differ.
- Suites: #321 8,326/0 then 8,325/0; #322 8,305/1 (test-perf-chain under load, 14/14 alone); #323 8,331/0.
- CI: #319 44025778691, #320 44026931646, #321 44062256786, #322 44062872198, #323 44077512715 — all green incl. Windows.

### Rejected — do not rebuild
- N2 heredoc-run scan (2026-11-16, memory `n2-heredoc-run-dropped.md`).
- Poison rule for skill `` !`cmd` ``: unnecessary, the command reaches PreToolUse:Bash (memory `skill-bang-context-goes-through-bash.md`).
- Pre-install `/sc-skill-check` command: the scanner already checks on every invoke.
- `/sc-health` check of `allowManagedHooksOnly` in user/project settings: Claude Code ignores it there.

### Dead ends
- `grep` on the Claude Code binary finds no setting names; use `strings` (all four names present in 2.1.326).

### Open questions
- Unverified: `allowManagedHooksOnly` behaviour in real managed settings (docs-based; needs sudo).
- Unverified: whether `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` in a settings `env` block is honored (docs silent).
- Not handled: `managed-settings.d` drop-ins are not read by `/sc-health`.
- RISK: a ≈120 KB `$( )` payload may still exceed the 15 s hook timeout.

### Reproduce
- `bash tests/test-container-mount-rm.sh`; `bash tests/test-health-hooks-off.sh` (12/12).
- Bang probe: scratch project with `.claude/skills/x/SKILL.md` containing `` !`echo RAN > marker` ``,
  then `claude -p "/x" --model haiku --allowedTools Bash` from that folder.
