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
