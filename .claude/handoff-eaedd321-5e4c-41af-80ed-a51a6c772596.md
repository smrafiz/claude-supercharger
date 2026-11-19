## Handoff — claude-supercharger — 2026-11-19 (session eaedd321, deep)

### Done
- Merged: #335 (symlink target in path-guard + critical-infra-guard), #336 (/sc-health managed MCP
  allowlist), #337 (claim-gate counts a reviewer only once it completes), #338 (compress validator
  fails on dropped negations / MUST / NEVER), #339 (A: credential reads via path spellings, extra
  readers, git history, Terraform/Vault token files), #342 (7 review/fix prompt rules from the
  vantage-security-agent audit).
- **Release held** by the user (4.4.9 = #335–#342 + B + C). Release only on the user's word.
- Audits recorded in memory/repo-audits-index.md: coding-agent-security, token-optimizer,
  skills-optimizer, claude-md-compress, avhn/secret, vantage-security-agent, Agasthy, agent-white-hat.

### In Flight
- **#340 (B, credential printers + env dumps)**: rebased on master after #339 (test-safety-fp.sh
  conflict: kept both blocks). See Current State in handoff.md for whether it merged.
- **#341 (C, indirect reads / launcher-wrapped readers / uploads + jq/.pub FPs)**: conflicts with
  master; rebase after B merges.

### Plan for the next session
The full step-by-step plan: `docs/GUARD-GAP-PLAN-2026-11-19.md`.
Order: (1) finish #340 B and #341 C (rebase C after B; conflicts in tests/test-safety-fp.sh),
(2) PR D (top priority, see the page), (3) PR E (smaller gaps from the agent-white-hat replay),
(4) a design, not code, for one larger check, (5) a decision for the user.
Rules for every PR: branch from origin/master in the main checkout (no worktrees, no stash); new
rows must fail on master; full suite unpiped in the background; shellcheck --severity=error;
regenerate tools/gen-plugin-commands.sh and tools/gen-commands-shipped.sh after any command edit;
dispatch `ci.yml` for Windows; merge only on the user's word.

### What Failed
- A macOS CI flake: `lib-bounded-run.sh: child setpgid (…): Operation not permitted`; rerun passed.
  If it recurs, look at the setpgid race.
- First full suite for #342: 3 fails from a stale commands-shipped manifest
  (`tools/gen-commands-shipped.sh`) after editing configs/commands/*.md. Regenerate
  `tools/gen-plugin-commands.sh` AND `tools/gen-commands-shipped.sh` after any command edit.
- #339 Windows: `mktemp -d` path given to native Windows python; fixed with `native_path`.

### Measurements
- avhn/secret replay: 78 verified misses; A/B/C deny 17/24/16 of them (57). Detail in the plan doc.
- agent-white-hat replay: counts and classes in the plan doc.

### Resume With
Read `.claude/handoff.md`, then `docs/GUARD-GAP-PLAN-2026-11-19.md`. Start at Step 1.
