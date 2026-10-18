# Audits

An outside review sweep from 2026-10-14, kept as written. Each finding was checked
against the code on 2026-10-15 (v4.3.12). No security bug was reported or found; most
findings are about making existing behaviour visible.

| File | What it covers |
|---|---|
| `security-review.md` | Read-only security review |
| `deep-review.md` | Security and engineering review; covers almost everything in `security-review.md` |
| `contract-drift-audit.md` | Invariants between hooks, state files and the two install channels |
| `pattern-parity-audit.md` | Secret, injection, egress and command patterns across channels |
| `file-sweep-audit.md` | File-by-file pass over the hooks |
| `claims-docs-audit.md` | README and doc claims against behaviour |
| `dynamic-verification-plan.md` | Payloads to probe each guard with |
| `../integration-research-report.md` | User complaints and integration ideas, with citations |

## Corrections

Where a document disagrees with the code, the code wins:

- **"A secret past character 400 survives in the block log"** (`security-review.md` §5,
  `pattern-parity-audit.md` F1): wrong. `safety.sh` redacts the first 1000 characters and
  then cuts to 400, so anything past 400 is dropped, not kept.
- **"The project-key algorithm must be kept identical in two places"** (`deep-review.md`
  F5, `contract-drift-audit.md` F1): mostly out of date. `project-config.sh` takes the key
  bash already derived; the python copy is a fallback. Both copies are compared in
  `tests/test-project-key-windows.sh`.
- **Hook counts** ("160", "166"): there are 167 `hooks/*.sh` files. Installed counts are
  43 (Safe) and 156 (Full, developer role); `tests/test-install.sh` now pins the README
  table to the installer.
- **"The secret patterns are used by three hooks"** (`pattern-parity-audit.md` §2): 19.
- **"Every guard runs identically on both channels" needs qualifying** and **"no
  telemetry" needs the update check named** (`claims-docs-audit.md` 2.2, 2.3): already
  done; the README lists the exceptions next to both claims.
- **"output-secrets-scanner never blocks"** (`dynamic-verification-plan.md` §3.6): it exits
  2 as an async rewake, so Claude is told after the tool ran. Post-hoc, but not silent.
- **The verification plan's payload matrix** is already covered by the suite; see the
  test names in each section's guard.
- **SkillJect citation** (`integration-research-report.md`): the paper's three agents are
  Attack, Victim and Evaluate, not Attack, Code and Evaluate.

## Acted on

- README: the zero-token claim now covers the guards only; the Full hook count is 156 and
  tested.
- `tests/test-git-refspec-insteadof.sh`: a chained `+main` push is denied, and the
  feature-branch rewrite is asserted in the exact shape Claude Code accepts.
- `tests/test-project-key-windows.sh`: bash and python key parity past the 100-character
  cap and on mixed separators.
- `lib-stdin.sh`: a non-blocking scanner that times out records the miss, and
  `/sc-status` shows the count.
- `docs/CVE-COVERAGE.md`: CVE to hook map, built from the ids the hooks cite.

## Since then

- `/sc-health` and `tools/guard-canary.sh` (4.3.18): each core guard is run through its
  registered command on a call it must stop.
- `docs/TRUST-BOUNDARIES.md`: what is checked for skills, agents, MCP servers and other
  hooks, and where it stops (integration report recommendations 3 and 6).

## Not building

- Per-guard fire and deny counts: a write on every hook call, the cost we remove elsewhere.
- A combined `/sc-trust` view: `/sc-status`, `/sc-health` and `/sc-mcp-audit` cover it.
