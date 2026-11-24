## Handoff — claude-supercharger — 2026-11-24 (session c7ed25f1, --deep)

### Done
- Audited boxdawn/guard v0.4.18 (FSL license: ideas only). Verdict: subset of ours, PAID small. Index entry added to memory `repo-audits-index.md`.
- Shipped **#366** (squash, master `1476f7e2`): inline python/node/ruby deletes, fetch-then-run via `/bin/bash x.sh` and `deno run`, `< file cmd` / `cp -r ~/.ssh` / `.dockercfg` / `containers/auth.json` / `socat FILE:` reads, 5 FPs (`--exclude=.env`, `scp -i`, `ssh-add`, `.env.*.example`, `docker -e PASSWORD=<placeholder>`). Files: `hooks/cmd-normalize.sh`, `hooks/safety-detect.py`, `hooks/safety.sh`, `hooks/env-file-guard.sh`, `tests/test-boxdawn-gaps.sh` (50 assertions), `tests/test-gate-detector-parity.sh` (PINNED 39→40).
- v4.4.9 was ALREADY released (tag + release 2026-11-24 05:15Z). The earlier carry file said unreleased: wrong.

### In Flight
- Master CI run for `1476f7e2` was `in_progress` when this was written (Windows leg included). Result not seen. Version consistency was still pending when #366 merged.
- #366 is on master but NOT released: installed copies lack it until the next release + `/sc-update`.

### Decisions Made
- Opus review BEFORE opening the PR (user ask): it caught 2 fail-open defects the builder introduced. Keep that order for guard changes.
- `ssh-add` allowed outright (policy change; `ssh-keygen`/`ssh-copy-id` still deny).
- Windows test: redirect-prefix case asserts verdict PARITY with plain quoted rm, not deny, on Git Bash.

### What Failed
- First commit 9234f657 had: redirect-swap infinite loop in `cmd-normalize.sh`, quadratic `.env` template lookahead and socat regex, unanchored scp `-i` strip, over-wide template exemption. All fixed in 4bf27aeb (reviewed, then merged).
- My merge ran with Version consistency pending (process gap, I caused this).

### Blockers
- none

### Worktrees
- none (main checkout only, per user rule)

### Files Touched
- see Done; also `.claude/handoff.md` (carry file) and this brief.

### Measurements
- Quadratic regex, name lookahead alone: `"cat x"+".env"*N+".example"`, N=1000 0.85s, N=4000 19s, N=8000 76s; master 0.002s. Full hook with N=5000: 21.2s vs master 2.5s; hook timeout 15s (reviewer probes, scratchpad `p/`).
- Socat rule before fix: `"socat "*10000` 7.6s. After fix all three timing tests <1s (detector alone).
- Suite after fixes (builder, unpiped): rc=0, 8901 passed, 0 failed. New test file 50/50; 11 fail on the pre-fix commit.
- Audit corpus: 742 boxdawn test literals replayed; ~216 positives still pass our chain (mostly PowerShell/Windows/Korean text).
- Windows CI: run 45359602773 failed 49/50 (one assertion); 45365085213 diagnostic: `got=allow plain-quoted-rm=allow`; 45370397004 green.

### Rejected — do not rebuild
- Stricter-policy items from boxdawn (sudo, `source`, `psql -f`, `sed -i /etc/hosts`, `find -delete`, `git stash`, `$CMD -rf /`): policy noise, not recommended.
- Their undo shadow-git snapshots, signed rules bundle, block telemetry: off-thesis.

### Dead ends
- Audit claim `curl -o x.sh URL; bash y.sh` allows was WRONG (denies today). Verified by builder.
- First grep for the Windows failure used `FAIL.*boxdawn` on the job log: the line is only in the downloaded `windows-suite-log*` artifacts (`gh run download -n windows-suite-log-N`).

### Open questions
- Is `"rm" -rf /` (and plain `rm -rf /`) allowed on Git Bash on master too? UNVERIFIED. Probe with the test `timed` helper on a Windows dispatch. If plain `rm -rf /` is allowed, a real Windows gap.
- Master CI for 1476f7e2: unknown.

### Reproduce
- `bash tests/test-boxdawn-gaps.sh` (macOS rc=0, 50 pass).
- Windows: `gh workflow run ci.yml --ref <branch>`; failures live in artifacts `windows-suite-log-*`.
- Audit report: scratchpad `boxdawn-audit.md`; reviewer probes: scratchpad `p/`.

### Resume With
Check master CI for 1476f7e2 (`gh run list --branch master`). Then probe whether `rm -rf /` (plain and quoted) is allowed on Git Bash via a Windows dispatch, and decide on the next release carrying #366.

### Start With
none
