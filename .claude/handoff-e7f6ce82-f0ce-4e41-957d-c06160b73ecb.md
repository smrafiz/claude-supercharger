## Handoff — claude-supercharger — 2026-11-14 (session e7f6ce82)

### Done
- **Reviewed tunguyen1993/kintsugi-harness** (Apache-2.0; benchmark claims not credible —
  nonexistent models, "100/100 DARPA CRS"). Ran 24 of its scenarios through our PreToolUse
  chain (probe script was in the session scratchpad). Real gaps: Bidi in written code;
  JWT/torch.load/CORS code patterns. Everything else covered, not a bypass, or rejected.
- **#302** merged (`62e8e3c3`): `code-security-scanner.sh` warns on Unicode Bidi controls
  (Trojan Source, CVE-2021-42574). Test in `tests/test-hooks.sh`, red before / green after.
- **#303** merged (`7ef44edf`): `lib_code_patterns.py` (shared by the scanner and
  commit-guard) warns on JWT verify_signature False / alg "none", torch.load without
  weights_only=True, any-origin CORS with credentials. 10 tests in
  `tests/test-lib-code-patterns.sh`; 5 detection tests red before. Replay over 668 past
  writes: no hits outside this work's fixtures.

### In Flight
- none

### Decisions Made
- Option 3 (scan SKILL.md writes for injection) not built: `memory-write-guard.sh` already
  denies it for CLAUDE.md, AGENTS.md and `.claude/**/*.md` incl. `.claude/skills/`. Only a
  repo-root `skills/*/SKILL.md` (plugin repos) is unguarded — measured rc=2 vs rc=0.
- ssh `StrictHostKeyChecking=no` stays allowed (`hooks/safety.sh:959`, prior decision).

### What Failed
- #303 first CI: `py-floor` (`tests/test-owasp-asi.sh:178`) greps hooks for a literal
  `:=`; the regex class `[:=]` matched it. Rewrote as `(?::|=)`. I ran only related test
  files locally, not `tests/run.sh`.
- #303 second CI: Windows `test-update-check` "cache miss when stale" hit its 6s `timeout`
  (`tests/test-update-check.sh:69`). Unrelated flake; full rerun (attempt 2) green.
- Re-running only the "Windows (Git Bash)" summary job would re-read the same shard
  artifacts and fail again — rerun the whole run.

### Blockers
- none

### Worktrees
- none. Per-machine: stale local `rel/4.4.5`; 0 stashes.

### Files Touched
- `hooks/code-security-scanner.sh`, `tests/test-hooks.sh` (#302);
  `hooks/lib_code_patterns.py`, `tests/test-lib-code-patterns.sh` (#303);
  `.claude/handoff.md`, this file.

### Resume With
Read `.claude/handoff.md`. Master has #302 and #303, unreleased since v4.4.6. Nothing in flight.

### Open questions
- Widen the 6s timeout in `tests/test-update-check.sh:69`? Flaked once on Windows.
- Guard repo-root `skills/*/SKILL.md` in `memory-write-guard.sh`? Low value.
