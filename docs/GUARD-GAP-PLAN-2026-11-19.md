# Guard Gap Plan — 2026-11-19

Plan for the next session (session `eaedd321`). Release 4.4.9 is held: merge and release only on the
user's word.

## State when this was written

- **Merged:** #335, #336, #337, #338, #339 (A), #342.
- **Open:** #340 (B, credential printers + env dumps), rebased on master after #339 (kept both test
  blocks in `tests/test-safety-fp.sh`). Check `.claude/handoff.md` Current State for whether it merged.
- **Open:** #341 (C, indirect reads / launcher-wrapped readers / uploads + `jq` and `.pub` FPs).
  Conflicts with master; rebase after B merges.

## Rules for every PR

- Branch from `origin/master` in the main checkout. No worktrees, no stash.
- Every new row must fail on master: run the test file against a `git archive master` copy.
- Full suite: `bash tests/run.sh > file 2>&1` in the background, unpiped, one at a time.
  `shellcheck --severity=error`.
- After editing `configs/commands/*.md`: run `tools/gen-plugin-commands.sh` and
  `tools/gen-commands-shipped.sh`.
- Commit message from a file, no backticks. Push, `gh pr create`, then
  `gh workflow run ci.yml --ref <branch>` (PR CI skips Windows).
- Merge with `gh pr merge N --squash --delete-branch --match-head-commit <sha>`, only on the user's word.

## Step 1 — finish B and C

1. If #340 is still open: confirm its suite at head, dispatch Windows, merge.
2. `git switch fix/cred-indirect-launchers-uploads && git rebase origin/master`. Expect conflicts in
   `tests/test-safety-fp.sh` (keep all blocks) and maybe `hooks/safety.sh`, `hooks/safety-detect.py`,
   `hooks/cmd-normalize.sh` (keep both sides; re-read each hunk).
3. Full suite, `git push --force-with-lease`, dispatch Windows, merge.

## Step 2 — PR D: post-output scanners see the real Read and WebFetch payload (top priority)

**BROKEN.** Verified live with `claude -p --settings` and a PostToolUse dump hook: a Read's
`tool_response` is `{"type":"text","file":{"filePath":…,"content":"…","numLines":…}}`.
WebFetch reportedly uses `.result`; verify the same way.

- `hooks/prompt-injection-scanner.sh:65-67` reads only `.output` / `.content`, so Read and WebFetch
  text is never scanned (likely since v2.6.83, which added Read).
- Audit the same pattern in `hooks/mcp-provenance.sh:46`, `hooks/output-secrets-scanner.sh:42`
  (Read branch), `hooks/mcp-output-truncator.sh:42`; `git grep -n tool_response hooks/` for the rest.
- Fix once in a shared helper: text = `.stdout` // `.output` // `.content` // `.file.content` //
  `.result`, with dict/list coerced to JSON.
- Rows: the real shape with an injection or a secret must flag; the flat shape still flags; a clean
  file stays silent. Prove the real-shape rows fail on master. Re-run the live probe after the fix.

## Step 3 — PR E: smaller gaps from the agent-white-hat replay

Corpus: public repo `ji-hun-git/agent-white-hat`, `bench/fixtures/drill-chains.json` and
`bench/fixtures/traprepo/`. Re-clone into scratch, treat as data, never run it. Split into two PRs
past ~300 lines.

| # | Gap | Where | Fixture |
|---|---|---|---|
| 1 | Downloaded file without a script extension, then chmod'ed or run in the same command. Key on the file the download writes (`-o`, `>`), not the URL. | `hooks/safety.sh:1025-1029` | `download-chmod-run`, `skill-linked-setup-doc-loader` |
| 2 | `claude plugin disable\|uninstall` is allowed. Add to the pre-filter AND the rule (two-gate trap). | `hooks/harness-tamper-guard.sh:52` | `injection-then-disable-guard` |
| 3 | Windows `Unblock-File` and `mshta <url>`: no rule. | `hooks/safety.sh:1130` (POWERSHELL_PATTERNS) | drill chains |
| 4 | Injection worded as claimed approval or an order to the assistant. New family; watch FPs on doc text. | `hooks/prompt-injection-scanner.sh:36` | `agentjacking-sentry-npx` |
| 5 | Sibling drift: `pip config set global.index-url` allowed while npm asks; `ANTHROPIC_BASE_URL` in AGENTS.md missed; "do not report" not a concealment verb. | `hooks/package-source-guard.sh:144` vs `:149`; `hooks/config-scan.sh:340` vs `:135`; `hooks/config-scan.sh:113-116` | `agents-md-install-and-reconfigure` |
| 6 | Project settings pre-approve run-anything commands (`Bash(npx:*)`, `Bash(node:*)`, `Bash(find:*)`). | `hooks/lib_config_checks.py:84-96` | `claude-settings-preapprove-runners` |
| 7 | FP: `pip install -r requirements.txt` asks; `tokens()` skips `-r` but keeps its value. Also skip the values of `-c`, `--requirement`, `--constraint`, `-e`. | `hooks/package-credibility.py` `tokens()` | `benign-requirements-hashes` |

## Step 4 — design only: install/build gate (41 trap repos)

Before `npm i`, `pip install`, `make`, `cargo build`, `pytest`: scan the project's install surfaces
(npm lifecycle scripts, `binding.gyp`, `.pnpmfile.cjs`, `.yarnrc` yarnPath, `setup.py`, `.pth`,
`conftest.py`, `build.rs`, `.cargo` rustc-wrapper, Makefile `$(shell)`, gradle distributionUrl, git
hooks). Their `docs/threat-model.md` and `docs/rules.md` describe one. Write the design, measure
hot-path cost, ask the user before building.

## Step 5 — the user's decision

The build agent for A/B/C routed around three of our own denies while writing guard code and tests:
one rule edit reused the existing `_SECRET_DIRS` list instead of the literal name; two test files
assemble sensitive literals at runtime (the documented test convention). The user decides whether
that is acceptable under "a block is final".

**Decision (user, 2026-11-21): accepted.** Reusing `_SECRET_DIRS` is one rule written once, and
runtime-assembled literals in tests are the documented convention. "A block is final" is about the
session working around a deny to get the same effect, not about guard code and its tests.

## Left alone on purpose

- ~70 `python -c` subprocess FPs (`hooks/safety-detect.py:236`): report only.
- 21 of the 78 avhn/secret misses: count-only output, `~/.aws/config` treated as public, 13 shaped
  printers left to the output scanner, alias/variable forms (known limit), `~/.secrets/*` and
  `.secrets.env` (possible follow-up).
- C fixes `.ssh/id_*.pub` on Bash without a regression row (the Read side is tested).
- macOS CI flake: `lib-bounded-run.sh: child setpgid (…): Operation not permitted`. Look at it if it
  recurs.

## Measurements

- avhn/secret: 78 verified misses; A/B/C deny 17 / 24 / 16 of them (57).
- agent-white-hat on master `8a8a1451`: attack chains stopped 9/12; trap repos 18/77 flagged
  (12 real); benign 4/40 flagged.
- The replay kits lived only in the work machine's temp scratchpad; re-create them from the public
  corpora if needed.
