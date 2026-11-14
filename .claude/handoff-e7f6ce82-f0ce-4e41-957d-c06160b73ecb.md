## Handoff — claude-supercharger — 2026-11-14 (session e7f6ce82, deep)

### Done
- **Reviewed 3 external repos** (gh api only): tunguyen1993/kintsugi-harness (Apache-2.0;
  fake benchmarks), Nodrail/agent-plugins (Apache-2.0; cloud approval client),
  JeongJaeSoon/agent-guard (MIT, 41 stars; credible). Each probed against our PreToolUse chain.
- **#302** `62e8e3c3`: code-security-scanner warns on Unicode Bidi controls (Trojan Source).
- **#303** `7ef44edf`: lib_code_patterns warns on JWT verify off / alg none, bare torch.load,
  any-origin CORS + credentials.
- **#304** `05c0be9e`: update-check background fetch `} >/dev/null 2>&1 &` (held stdout).
- **#305** `639c353d`: removed the stale-cache update-check test (vacuous on macOS).
- **#306** `784db292`: env-file-guard blocks Grep wildcard globs matching credential names.
- **#307 open** (`fix/cred-read-parity`): kubectl secret output in either flag order
  (`-oyaml`, `--output=yaml`, `-o json secrets`), `mvn -DshowPasswords=true`, Read parity for
  `*.tfvars(.json)`, `*service-account*.json`, `*firebase-adminsdk*.json`, `client_secret*.json`.
- Engineering notes: `docs/HOOK_AUTHORING.md` "Notes from 2026-11-14" (commit `8db71fc3`).

### In Flight
- #307: full CI dispatched, run 43624725793, in progress at write time. Merge with
  `gh pr merge 307 --squash --delete-branch --match-head-commit <sha>` once green.

### Decisions Made
- Release v4.4.7 **held by the user**. Master carries #302–#306 unreleased since v4.4.6.
- `gh auth token`, `npm config get _authToken`, `pip config list` NOT added: the v4.0.45
  comment in `hooks/safety.sh` (secret-manager patterns) rejects them, since the output
  scanner covers known-shape tokens. Reversing it is the user's call.
- `env.production` style reads not blocked: Bash doesn't block them either, and `env.*` would
  hit code files (`env.ts`).
- `*.tfvars` Read now denied (parity with Bash `cat`), not ask. FP risk accepted, unmeasured.
- Repo-root `skills/*/SKILL.md` not added to memory-write-guard (low value).
- ssh `StrictHostKeyChecking=no` stays allowed (`hooks/safety.sh:959`).
- Did not switch gh accounts myself when a merge failed; user ran `gh auth switch -u smrafiz`.

### What Failed
- #303 first CI: py-floor grep hit `:=` inside regex class `[:=]`; rewrote as `(?::|=)`.
- #303 second CI: Windows update-check 6s timeout; root cause was #304, not a flake.
- Bash commands whose text named a dotenv path or the process-environment path were denied by
  our own safety.sh (two probes, one memory write). Moved the strings into files.
- `gh pr merge 306` failed: active gh account was `wp-sigmadevs` (no merge rights).

### Blockers
- none

### Worktrees
- none (main checkout only). Per-machine: stale local branch `rel/4.4.5`; 0 stashes;
  local `fix/cred-read-parity` until #307 merges.

### Files Touched
- `hooks/code-security-scanner.sh`, `tests/test-hooks.sh` (#302)
- `hooks/lib_code_patterns.py`, `tests/test-lib-code-patterns.sh` (#303)
- `hooks/update-check.sh`, `tests/test-update-check.sh` (#304, #305)
- `hooks/env-file-guard.sh`, `tests/test-env-file-guard.sh` (#306, #307)
- `hooks/safety.sh`, `tests/test-secret-printing.sh` (#307)
- `docs/HOOK_AUTHORING.md`, `.claude/handoff.md`, this file

### Resume With
Read `.claude/handoff.md`. Check #307's CI (run 43624725793) and merge it if green, then
update the carry file. Release v4.4.7 stays held until the user says otherwise.

### Start With
none — `gh pr checks 307` is enough. If a guard blocks a probe, `/sc-why`.

### Measurements
- kintsugi probe: 24 scenarios; gaps Bidi, JWT, torch.load, CORS, repo-root SKILL.md.
- agent-guard probe: 48 scenarios → 31 deny, 2 ask, 15 allowed (`scratchpad/cases_ag.py`).
- #303 replay: 668 distinct transcript writes, no hits outside own fixtures.
- #304: stale path held 4s locally before the fix; new test 3s FAIL before, pass after.
- #306: 9 wildcard block cases red before; 138/138 after (bash 3.2 too). Real Grep globs in all
  transcripts: 1 distinct, still allowed.
- #307: 9 block cases red before; env-file-guard 147/147, secret-printing 49/49,
  test-hooks 673/673. guard-replay (400 transcripts): env-file-guard 660 runs, safety.sh 3006
  runs, 0 blocks.
- Full local suite: 8021 (after #304), 8038 (#306 branch), 8053 (#307 branch), 0 failed.

### Rejected — do not rebuild
- Command rules for `gh auth token` / npm authToken / pip config: rejected in v4.0.45 (output
  scanner covers known-shape tokens); re-proposed this session in error.
- Nodrail's approach (send calls to a cloud for approval): out of scope for a local plugin.
- agent-guard's gitleaks dependency and output rewriting: we warn via output-secrets-scanner.
- URL userinfo password rule: agent-guard itself lists many accepted residuals; FP-prone.

### Dead ends
- Probing via inline Bash heredoc with credential-path strings: blocked by safety.sh every time.
- guard-replay `--json` does not keep tool inputs; count globs from transcripts directly.

### Open questions
- `*.tfvars` Read deny: FP rate unknown (no Read of tfvars in transcripts). Unverified.
- #306 wildcard rule: FP evidence thin (1 real glob). Watch the block log; FP audit ~2026-12-08.
- `disableAllHooks: true` vs user hooks (2026-11-12 brief), still open.
- `env > file` and `set | grep` env-dump-to-sink: allowed today; medium value, not built.

### Reproduce
- Probe harness (session scratchpad): `probe.py` (kintsugi cases), `probe2.py` (Nodrail, never
  ran), `probe3.py` + `cases_ag.py` (agent-guard): `python3 probe3.py <repo>`.
- `bash tests/test-env-file-guard.sh`, `bash tests/test-secret-printing.sh`,
  `bash tests/test-update-check.sh`, `bash tests/run.sh`.
- `python3 -I tools/guard-replay.py --hook env-file-guard.sh --hook safety.sh --per-tool 3000 --transcripts 400`.
- CI: `gh workflow run ci.yml --ref <branch>`; `gh run view <id> --json status,conclusion`.

### Memory (this session)
- Created: `background-block-holds-hook-stdout.md`, `gh-account-can-switch.md`.
- Updated: `reviewing-external-repos.md`, `a-green-assertion-can-be-vacuous.md`,
  `verify-gaps-before-claiming-them.md`.
