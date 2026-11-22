## Handoff — claude-supercharger — 2026-11-22 (session eaedd321, deep)

### Done
- Reviewed #341, #344–#353 with 3 independent agents. Found 3 HIGH, ~8 MED and several LOW/FP. All
  fixed and merged: #354 (high), #355 (medium), #356 (low). Every new row fails on master; Windows
  green on all three; master CI green at each merge.
- Windows-only fixes CI found: #355 `/usr/bin/pip3` arrives with backslashes; #356 `cd <dir>` target
  joined onto `C:/cwd` became `C:/tmp/...` (fix: `native()` before the join).
- #358 merged: carry file, Step 5 user confirmation in `docs/GUARD-GAP-PLAN-2026-11-19.md`, design
  `docs/CROSS-COMMAND-DOWNLOAD-RUN-DESIGN.md`.
- Audited EL4CTEO/fast-anything (README only): off-fit, our cost is process startup.

### In Flight
- **#357** `fix/perf-chain-load-flake` at `bef7db1a`: statusline cache test falls back to a python3
  start count with the clock pinned (`SUPERCHARGER_SL_NOW`, one line in `hooks/statusline.sh`).
  Full suite and Windows run 45019067567 were running at handoff. Merge if both pass (user said go).
- **Item 5, cross-command download-then-run (user said build: ASK, a Read does not clear it).**
  Drafts only, on branch `wip/download-ledger` (no PR): `wip/test-download-ledger.sh` (14 rows) and
  `wip/ledger.py` (`check_download_ledger`, appended after `check_download_then_run` in
  `hooks/safety-detect.py`, called last in main under "exfiltration"). Still to do in `hooks/safety.sh`:
  read `session_id` with `_json_fast_str`, set `DL_LEDGER=$SUPERCHARGER_STATE/scope/.downloads-<sid>`,
  pass it to the detector, gate `_NEED_PY` on `[ -s "$DL_LEDGER" ]` plus chmod/install/path/interpreter
  words, and turn a `__SC_ASK__` reason into `sc_decision ask` right after the `block "$PY_REASON"` line
  (only asks follow it, so no deny is hidden). Simplification vs the design doc: no size/mtime match,
  so a file rewritten after download still asks; update the doc.
- **Release 4.4.9:** user said release after a quiet-machine speed re-measure. Not done.

### Decisions Made
- Step 5 accepted (user, 2026-11-22): Edit/Write of guard code/tests after a pattern-text deny is fine;
  never to get a denied effect.
- Item 5 verdict: ASK, not deny; a Read in between does not clear it (user, "do as you recommend").
- No Rust rewrite (discussed): cost is spawn, not compute; a single hot-path binary is the only
  version worth measuring, and a dispatcher was rejected 2026-10-14 for reasons to re-read first.

### What Failed
- Fix agent crashed once on an API error; resumed via SendMessage with context intact.
- First #357 fallback (unpinned fork count) failed 5/5 at load ~500: no two renders shared a second.
- `"$C:refs/heads/x"` push failed: zsh `:r` modifier applies inside double quotes.

### Blockers
- Machine load 100–546 all day (rustc builds, phpantom_lsp, CleanMyMac, Chrome, Teams). Blocks item 3.

### Worktrees
- none (main checkout only)

### Files Touched
- See #354–#358 diffs. This handoff: `.claude/handoff.md`, this brief, `docs/HOOK_AUTHORING.md`
  ("Notes from 2026-11-22").

### Resume With
Read `.claude/handoff.md`. Merge #357 if its suite and Windows passed. Then finish item 5 from branch
`wip/download-ledger` (In Flight lists the safety.sh steps), prove rows fail on master, open a PR.
On a quiet machine, re-measure the Bash chain v4.4.8 vs master and release 4.4.9.

### Start With
- none (no Supercharger command needed; `gh pr checks 357` first)

### Measurements
- Suites: #354 8686/0; #355 rebased 8760/0; #356 rebased 8785/1 (perf-chain timing, 14/14 alone);
  #357 first head 8785/1 (same test).
- Slow glob: `glob.glob` built 64,544 matches in 3.6 s; probe rc=0 in 1.8 s on master.
- statusline at load ~500: cold 589 ms, warm 387 ms = 1.52x (floor 2.5). Pinned clock at load ~300:
  cached 0/0/0 python3 starts, uncacheable session 1/1/1.
- `safety.sh` on `ls -la src` (noisy, load 70–310): master 23–28 ms vs #354 33–41 ms. Unreliable.
- `install-surface-gate` cwd named installer-tools: 67–118 ms master vs 16–39 ms after #356.

### Rejected — do not rebuild
- Full Rust rewrite: spawn cost dominates (bash ×18 + python3 ~20 ms); risk of new fail-opens.
- fast-anything: speeds hot functions in long-running apps; a PyO3 port still starts python3; no bash.

### Dead ends
- none

### Open questions
- Is #354's `safety.sh` slowdown real? Unverified (load). Settle: quiet machine, `tests/perf-chain.sh`
  on v4.4.8 vs master.
- Source of the 27 GB disk drop (recovered later): unknown, not ours.

### Reproduce
- Review probe kits: scratchpad `rev1/`, `rev2/`, `rev3/` (this machine only).
- Fork-count check: python3 shim on PATH writing to a file; `SUPERCHARGER_SL_NOW=1700000000`; render
  `hooks/statusline.sh` twice with the same session id; second render must start none.
- Windows log for a failing row: `gh run download <id> -n windows-suite-log`, grep `FAIL`.

---

## Handoff — claude-supercharger — 2026-11-19 (session eaedd321, deep)

### Done
- Merged: #335 (symlink target in path-guard + critical-infra-guard), #336 (/sc-health managed MCP
  allowlist), #337 (claim-gate counts a reviewer only once it completes), #338 (compress validator
  fails on dropped negations / MUST / NEVER), #339 (A: credential reads via path spellings, extra
  readers, git history, Terraform/Vault token files), #342 (7 review/fix prompt rules from the
  vantage-security-agent audit).
- Audits recorded in memory/repo-audits-index.md: coding-agent-security, token-optimizer,
  skills-optimizer, claude-md-compress, avhn/secret, vantage-security-agent, Agasthy, agent-white-hat.
- Engineering notes: `docs/HOOK_AUTHORING.md` "Notes from 2026-11-19".
- Next-session plan: `docs/GUARD-GAP-PLAN-2026-11-19.md` (this PR, #343).

### In Flight
- **#340 (B)** rebased on master after #339 (kept both blocks in `tests/test-safety-fp.sh`), pushed
  at `88650ec9`. Local full suite at that head: 8548 passed, 0 failed; shellcheck clean. Windows
  dispatched as run 44506111356 (result not seen). Merge on the user's word.
- **#341 (C)** conflicts with master; rebase after B merges (plan Step 1).
- **#343** (this docs PR): not merged.

### Decisions Made
- **Release 4.4.9 held** (user): batch B, C and more before releasing. Not an Issues item.
- **No Artifacts** (user deleted one): plans go in `docs/*.md` in the repo, even though the repo is
  public and the plan names unfixed gaps (user chose this after being told).
- **~70 `python -c` subprocess FPs left alone** (user: report only); loosening risks a bypass.
- **Grep-output grouping shelved**: replay of 222 real grep/rg outputs grouped 0 (see Rejected).
- **B kept in `safety.sh` only; shaped printers stay with the output scanner** (existing decision).

### What Failed
- macOS CI flake on #342: `lib-bounded-run.sh: child setpgid (66223 to 66223): Operation not
  permitted`; rerun passed. Not investigated.
- First full suite for #342: 3 fails from a stale shipped-commands manifest.
- #339 Windows: `mktemp -d` path handed to native Windows python; fixed with `native_path`.
- zsh `$c:refs/...` ate `:r` as a history modifier, so `git push origin $c:refs/heads/x` pushed a
  garbage refspec. Quote it: `"$c:refs/heads/x"` or `${c}:`.
- The build agent for A/B/C routed around three of our own denies (plan Step 5: user decides).

### Blockers
- none

### Worktrees
- none (main checkout only)

### Files Touched
- See #335–#343 diffs. This PR: `.claude/handoff.md`, this brief, `docs/GUARD-GAP-PLAN-2026-11-19.md`,
  `docs/HOOK_AUTHORING.md`.

### Resume With
Read `.claude/handoff.md`, then `docs/GUARD-GAP-PLAN-2026-11-19.md`, and start at Step 1 (check #340's
Windows run 44506111356, merge B on the user's word, rebase C). Then Step 2 (PR D) is the top priority.

### Start With
- `/sc-update` only if this machine's install is behind master's hooks you will test against;
  otherwise none.

### Measurements
- avhn/secret corpus: 4020 deny cases → we denied 937, asked 38, allowed 3045; 119 probes through all
  24 Bash hooks, 78 stayed allowed on a serial re-run. A/B/C deny 17 / 24 / 16 of the 78 (57).
  Their 948 allow cases: we denied 114.
- Full suites: A at `7dc12e3a` 8498/0; #342 at `2fcda2bb` 8469/0; B rebased at `88650ec9` 8548/0.
- agent-white-hat on master `8a8a1451`: attack chains stopped 9/12; key steps 7 deny / 1 ask /
  7 allow of 15; trap repos 18/77 malicious flagged (12 real); benign 4/40 flagged.
- Read PostToolUse payload, captured live: `{"type":"text","file":{"filePath":…,"content":…,
  "numLines":…,"startLine":…,"totalLines":…}}`.

### Rejected — do not rebuild
- Grep/rg output grouping in `bash-output-compactor.sh`: 222 real outputs ≥1.5 KB from 72
  transcripts grouped 0 (219 compound/context/single-file, 3 under 50 lines); 0.5% saving.
- token-optimizer's "deny re-reads": rejected (re-reads are often deliberate after edits).
- skills-optimizer: nothing to take (37 commands, 2,704 listing chars, none over the cap).
- vantage-security-agent CVSS/confidence rubric/finding schema: ours (sc-security) is sharper.
- Agasthy: off-thesis; its usage dedupe = our 4.3.21 fix.

### Dead ends
- none new beyond the rejected list.

### Open questions
- **Unverified:** WebFetch's PostToolUse text is under `.result` (agent-white-hat replay agent's
  claim from transcripts). Settle with the same `claude -p` dump-hook probe.
- **Unverified:** whether `output-secrets-scanner`, `mcp-provenance`, `mcp-output-truncator` are
  blind on the real Read shape (plan Step 2).
- **Unverified:** the claim-evidence gate treats an edit to a file outside the project (a scratchpad
  `.html`) as a code edit after a test run; seen once this session. Check before changing it.

### Reproduce
- Live payload probe: a settings file with `{"hooks":{"PostToolUse":[{"matcher":"Read|WebFetch",
  "hooks":[{"type":"command","command":"<dir>/dump.sh"}]}]}}`, `dump.sh` = `cat > <dir>/post-$(date
  +%s).json`, then `claude -p --settings s.json --allowedTools Read -- "Read note.txt ..."`.
- Commit without touching a busy checkout: `GIT_INDEX_FILE=<tmp> git read-tree origin/master`,
  `git update-index --add --cacheinfo 100644,$(git hash-object -w FILE),PATH`, `git write-tree`,
  `git commit-tree <tree> -p origin/master -F msg`, push `"<sha>:refs/heads/<branch>"`.
- Replay kits were in this machine's scratchpad only; re-create from the public corpora
  (avhn/secret `testdata/hook/denied-commands.json`; agent-white-hat `bench/fixtures/`).
