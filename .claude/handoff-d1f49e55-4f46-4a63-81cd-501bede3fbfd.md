## Handoff — claude-supercharger — 2026-10-30

### Done
- **#202 merged** (`03c75b41`, squash, pinned to tested head `2020c5f9`). Windows dispatched first,
  run 41027345901, 8/8 green. The auto-mode classifier denied `gh pr merge` from Claude; the user ran it.
- **`/sc-de-ai`** (`0e6e1e10`, straight to master): adapted from petergyang/no-ai-slop (MIT, credited
  with full licence text in NOTICE). Edit mode + detect mode ("is this slop?"), 18 patterns, self-check.
  Exempts product names and technical senses ("harness"); a writer's em-dash habit beats the dash limit.
  Writer agent gained `Skill` and runs it at self-edit (`sc-de-ai` / plugin `supercharger:de-ai`).
  3 tests in `tests/test-agents.sh`, shown red against the unwired writer.
- **Issues List rule** (`51792935`): `configs/universal/supercharger.md` after the Verification Gate.
  Replies that report work end with `## Issues`, tagged BROKEN / RISK / NOT DONE / UNKNOWN, plus
  "I caused this". Skipped on replies that report no work. Idea from trycompai/crm AGENTS.md (credited
  in NOTICE). Test in `tests/test-install.sh` reads the INSTALLED copy; shown red without the rule.
- Full local suite before each commit: 7242, then 7250 passed, 0 failed.

### Audited, nothing taken
- **trycompai/crm:** only the Issues List. Its skills-lock = our skill-integrity-guard; its anti-slop
  oxlint rules are TypeScript-only.
- **browser-use/video-use:** a video-editing skill. Note for anyone installing it: its setup has the
  agent write `ELEVENLABS_API_KEY` to `.env`, which our env guard denies — the user must do that step.
- **"Each rule names its consequence" sweep:** rejected. Unmeasured, adds bytes to every session, and
  two of my four drafted consequences were unverified claims.
- **NVIDIA/SkillSpector re-check** (≈50 upstream commits since the 10-26 audit): one static-scan gap.
  Upstream AS2 (3ae98afc) widened MCP config names; our `lib_poison_patterns.py:65` still matches only
  `mcp(_config).json`. Missing: `mcp_settings.json` (Cline/Roo), `claude_desktop_config.json`,
  `~/.claude.json`. Runtime reads of the last two are already guarded (`env-file-guard.sh:286,296`);
  `cline_mcp_settings.json` is not. Their MP3 memory-write rule (2de9b387) targets test files that
  write to MEMORY.md/CLAUDE.md — we guard that at runtime (`memory-write-guard.sh`). Not acted on.

### In Flight
- **#203 merged** (`ec372afc`): `lib_poison_patterns.py` MCP-config names widened per SkillSpector AS2;
  `env-file-guard.sh` asks on Cline/Roo MCP settings. Windows run 41047321478 8/8 green; user merged.
- **PR #204 open** (`038a12b2`): `safety.sh` asks on a Bash reader of `.cursor/mcp.json`,
  `windsurf/mcp_config.json`, `claude_desktop_config.json`, `*mcp_settings.json`. 6 tests in
  `test-safety-bash-evasions.sh`, 5 shown red without the fix. Suite 7263/0. Windows run 41098777970.
- Master CI on `b24cd407` (run 41043497740) 8/8 green incl. Windows.

### Decisions Made
- Separate feature commits stay out of fix PRs (sc-de-ai was not added to #202).
- `sc-*` "skills" are slash commands in `configs/commands/`; plugin copies are generated
  (`tools/gen-plugin-commands.sh`), shipped hashes regenerated (`tools/gen-commands-shipped.sh`).
- The tests badge is a gist endpoint now; there is no README number to bump.

### Next
- Merge #204 once run 41098777970 is green (user-run, full SHA).
- Not acted on: scanner reverse word order (upstream has the same limit); `cat <mcp cfg> | curl -d @-`
  only asks.
- Unverified: whether a subagent can invoke a slash command through the `Skill` tool. Proving it needs
  an install and a real writer-agent run.
