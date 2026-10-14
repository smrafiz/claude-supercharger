# Security Review — Claude Supercharger (read-only)

**Date:** 2026-10-14
** reviewer:** Buffy (Solar Pro 4)
**Scope:** code & design review, not a dynamic audit. Inspected the hook registry, the core Bash safety hook, the Write/Edit path guard, the harness/self-defense guard, the config/prompt/secret/exfil scanners, the shared pattern + decision libs, the installer/uninstaller, and the hook-authoring + OWASP-mapping docs. Did **not** read all 166 hooks or run the test suite.

**Overall verdict:** High-quality security harness with a mature understanding of its own limits. The main residual risk is operational — breadth, known platform gaps, and the difference between “guard exists” and “guard fires with effect.” The README’s threat-model framing (mechanism vs. best-effort patterns; prompt-injection class it does not cover; `!` shell-escape out of scope) is the right one and should be trusted over any marketing gloss.

> Note: `payload.json` was present in the repo root during the initial review and was flagged as leftover test data. It has since been removed; that item is dropped from this revision.

---

## 1. The real failure mode is “guards that silently stop firing”

The product’s security property is “a hook returns exit 2,” which means the worst defect is a hook that is **registered and fires but matches nothing** — and that leaves no visible trace in the user’s session.

The maintainer clearly understands this. There is a `guard-registration-check.sh`, a `setup-check.sh`, a `version-floor-check.sh`, and repeated notes in the codebase about hooks that were **declared but inert** because the matcher was in the wrong dialect (the bare `mcp__` token, the `if` field, the `DirectoryAdded` event that Claude Code didn’t dispatch yet). The project even keeps the old failure notes in place as a warning rather than silently editing them away.

**Concern:** the same defect class keeps recurring across multiple releases. When your entire enforcement story is “a separate process returns exit 2,” a matcher that silently matches nothing is the nightmare case — it looks configured, it costs a fork, and it does nothing. The registration check reduces but does not eliminate this, because a “fired but matched nothing” hook still passes a registration-count check.

**Recommendation:** treat “guard X fired N times with M denials” as a first-class, auditable metric, not just a registration-presence check. A periodic diff of per-guard fire/deny counts against expected minimums would catch a matcher-rot failure that the current checks can miss.

---

## 2. The stdin-timeout path is a deliberate, documented “fail open” window

`hooks/lib-stdin.sh` is well-engineered. It correctly identifies that bash 3.2 returns `rc=1` on a `-t` timeout (indistinguishable from EOF), uses **elapsed time** as the discriminator, and — for PreToolUse — emits an explicit `ask` with a plain-language warning instead of silently passing. That is the right answer.

The catch is the **design choice**: on timeout, the hook exits **0**, so it does not block. For PreToolUse, `ask` at least surfaces something to the user. But the same read helper is used by several **non-PreToolUse** scanners (PostToolUse secret/injection scanners, Stop-channel evidence gate, UserPromptSubmit prompt-secret guard). For those, there is no decision channel at all — the tool already ran, or it’s the user’s own prompt. On timeout those paths emit a stderr notice and exit 0, which means **the payload simply wasn’t scanned**, with no entry in the blocked-commands ledger and no injection into the session.

This is a deliberate trade-off, not a bug. Still worth surfacing because the blast radius is: a slow writer (or a stall) causes a credential-bearing or injection-bearing payload to be skipped with no audit artifact.

**Recommendation:** for the non-blocking scanners, write a one-line breadcrumb into the per-session audit log on timeout (e.g. `SCANNED=0 TIMEOUT=1`), so post-hoc analysis can see that a payload was skipped rather than silently assumed clean.

---

## 3. Windows is the weakest-tested surface — and the README already under-claims here

`hooks/safety.sh` carries a long, well-motivated Windows text-match overlay for the `rm -rf` path checks, with detailed comments explaining exactly why the Python resolver is inert there and what each text rule covers. That’s the right kind of engineering for a bash-only tool on Git Bash.

The concerning part is that the project itself flags **two Windows gaps that are not closed**:

- The Python resolver inside `safety.sh` and `path-guard.sh` is **fail-open on Windows** for path-resolution checks (realpath maps `/etc` onto the wrong drive, etc.). The shell-layer text match closes the worst `rm` cases, but `path-guard.sh`’s Python body still handles symlink resolution, absolute-path writes, git-internals, build-artifact, and selfmod — and the notes don’t show equivalent Windows text-match coverage for all of those.
- The README explicitly says **nobody has verified a desktop notification renders on Windows**, and **no human has run a full install on a Windows desktop** — only the scripted CI path.

If your audience is macOS/Linux-dev-rooted, this is probably fine. If any Windows users are in scope, the security floor there is meaningfully thinner than “every guard runs identically on both channels” implies for the path-resolution and notification classes.

**Recommendation:** qualify the “identical on both channels” language in the README to enumerate the known Windows deviations explicitly (resolver inert, notifications unverified, full-desktop install untested), so a Windows user isn’t handed a security guarantee the code doesn’t actually deliver there.

---

## 4. The plugin vs. classic install duality is a real integrity surface

Two install channels doubles the paths through which state can diverge. The codebase handles the obvious collision (plugin detects a classic install and stands down), and `lib-paths.sh` unifies `SUPERCHARGER_HOME` / `SUPERCHARGER_STATE` resolution. Good.

What to watch:

- **MCP-profile filtering doesn’t apply under the plugin.** The plugin ships its own MCP servers through the manifest, and Claude Code’s own per-server approval is what selects them. That means profile-gated guards that depend on “only loaded in `dev`/`full`” can’t rely on the same mechanism under the plugin. If any guard’s enforcement decision is keyed to “is this MCP server currently active,” the two channels may disagree on *which* servers are active, not just on *whether* the guard runs.
- **Statusline, 1h prompt cache, and attribution** need three `settings.json` keys a plugin manifest can’t declare, so the plugin asks the user at enable time whether to write them. That’s a human-in-the-loop integrity point: a user who answers “no” keeps the plugin strictly inside its own space (good), but it also means two otherwise-identical installs can have different observability. Not a vulnerability, but a real divergence in what “Supercharger is on” means.
- **`/sc off`** stands the plugin’s *own* MCP servers aside but leaves user-added ones alone. The distinction is correct, but it’s exactly the kind of subtle behavior a tired user misreads as “everything is off.”

**Recommendation:** the plugin smoke-test doc already lists the right verification steps. Make the “which MCP servers are active under this profile right now” check a **scripted assertion**, not a manual bullet — it’s the axis on which the two channels most plausibly diverge.

---

## 5. Secret handling is strong; the residual is in ledger timing and capping

`hooks/lib-secret-patterns.sh` is a single source of truth for the pattern array consumed by the output scanner, the commit guard, and the sendmessage guard — exactly the right structure to prevent cross-channel drift. The pattern rationales are unusually good (the Base58 Bitcoin WIF anchoring story, the property-reference dot removal with measured FP counts, the SHA-256 vs. WIF disambiguation). This is the best-maintained secret surface in a harness like this.

The residual risk is operational rather than algorithmic:

- The blocked-commands ledger (`scope/.blocked-commands`) records command text that has passed through `ledger_redact`, but it’s still **plain text on disk**, world-readable under the default umask until the installer applies `chmod 700` to the scope dir (v4.0.35). The installer now does that, and it explicitly refuses to follow symlinks — both good. But for installs predating that fix, or for a scope dir recreated under a looser umask, the ledger can leak truncated-but-not-fully-redacted command text to any local user.
- The **400-char cap** on the logged command is now **above** the redaction step (a deliberate ordering fix, and correct), but it means a long command whose sensitive portion sat past char 400 can still be retained in a form that escaped redaction. The code is aware of this (the comment history is detailed), but “a secret straddling the cap” is a real residual.

**Recommendation:**
1. Confirm the `chmod 700` guard runs on every state-dir **creation** path, not just install — state dirs can be recreated by hooks after uninstall/reinstall.
2. Consider redacting **after** the cap, or running the redaction pass on the full string before slicing, so a secret at position 401–800 can’t survive as a partial fragment in the ledger.

---

## 6. Trust-on-first-use skills: the “pre-existing skill” baseline is a real assumption

There are two overlapping checks: **skill-integrity guard** (hash-on-first-use, “has this file changed?”) and **skill-poisoning scanner** (“does this look malicious?”). The docs are clear that they’re complementary — one catches upstream edits, the other catches a freshly-loaded malicious skill. Correct decomposition.

The subtlety: the integrity guard is **trust-on-first-use**. If a skill is already loaded and hashed before Supercharger is installed (or before the guard is registered), the first Supercharger-seen load is treated as trusted. An attacker who poisons a skill *before* install lands a file that passes integrity on day one and then passes poisoning only if the pattern list catches it. The project knows this (the `SKILLS-LOCK-PLAN.md` doc is in the repo) and treats it as an acceptable trade-off vs. a lockfile to maintain, but it’s the kind of thing a security reviewer should call out explicitly rather than leave buried in docs.

**Recommendation:** make the “first load under Supercharger = trusted baseline” assumption visible in user-facing output (`/sc-why`, `/sc-status`), so an operator who installs Supercharger mid-flight understands that pre-existing skills weren’t re-baselined.

---

## 7. Prompt injection: honest about the limits, but channel posture differs

Scanner coverage is good and expanding: MCP output, WebFetch/WebSearch, Read content, Bash output (warn-only, fail-open), slash-command expansion, and a structural MCP-provenance check. The project explicitly says it is **not** a defense against a targeted attacker who controls your prompts, and scopes prompt-injection defense to the “opportunistic instruction-in-fitting-text” class.

I agree with that framing. The risk is that users install a 160-hook “security” product and infer a stronger guarantee than the scanners can deliver — especially because the scanners are mostly **async** and **warn-only** on the hottest channels (Bash output). A prompt injection that reaches the model through Bash output is “flagged asynchronously” while the model has already seen it. That’s the right engineering call given the performance budget, but it should be stated plainly as “injection in Bash output is detected after the fact, not prevented.”

**Recommendation:** ensure statusline/transcript indicators distinguish “injection detected” (async, after the fact) from “injection blocked” (synchronous, pre-execution), so the operator can tell which channels actually have a pre-execution gate and which only have 사후 detection.

---

## 8. Smaller positives worth naming

- **`set -euo pipefail` is everywhere**, and the malformed-input defense (`|| true` / `|| echo ""` on every `jq`/`python3` read) is consistently applied. This is the right discipline and it shows.
- **`safety.sh` fast-path** (bare verbs with no metachar skip the full scan) is well-justified, and the exclusion list is structural (no content-reading verbs), not an allowlist to drift.
- **`lib-json-fast.sh`** has a size gate and an explicit note that above ~6.7 KB the fork-free path becomes slower than the fork it replaces — and it falls back. Measurement-backed thresholds keep a micro-optimization from becoming a DoS surface on large payloads.
- **`sc_decision / sc_deny / sc_ask`** centralize the only output shape that actually blocks, which reduces the chance of a hook emitting a reason but forgetting exit 2. Good architecture.
- **Per-project scope-file design** (`lib-paths.sh`’s `sc_project_key`) cleanly fixes the “two projects overwrite each other’s profile/budget” bug, and it avoids a `md5sum` fork in the hot path. The Windows path-separator/colon folding is the right level of attention to the platform.

---

## Appendix A — threat-model alignment (OWASP ASI 2026)

The project maps itself to the OWASP Top 10 for Agentic Applications 2026 and cites specific coverage for Least-Agency (opt-out per project), Strong Observability (blocked-command + audit JSONL), Self-modification defense (the `selfmod` category across Bash and Write/Edit), and Sandbox-bypass detection (`config-scan.sh` covering three documented CVE classes at session start). That’s the right mapping to do and the right level of specificity to claim.

The gap between “we have a hook for X” and “X is covered end-to-end” is the theme of this review. The mapping is honest where it says “best-effort patterns”; the risk is a reader who shortens that to “we defend against X.”

---

## Appendix B — summary table

| Area | Assessment |
|---|---|
| Threat model & honesty | Strong — limits are named, not implied away |
| Core Bash safety hook | Thorough, measurement-backed, hardened against its own regressions |
| Write/Edit path guard | Strong, with real Windows-surface attention |
| Secret detection patterns | Best-maintained surface in the repo; residual is ledger timing/cap, not pattern quality |
| Prompt injection | Good coverage, correctly scoped; Bash-output channel is 사후 detection only |
| Install / plugin duality | Two-channel divergence is handled but is itself a risk worth scripting checks around |
| Windows | Thinnest surface; project already under-claims here, which is good — but “identical on both channels” should be qualified |
| Silent-failure-of-guards | Recurring defect class; registration checks help, but a “fired with zero denials” anomaly detector would help more |
| Skills trust model | Correct, but trust-on-first-use should be surfaced to the operator |
| Overall | Serious security engineering with a mature self-model. Main residual risk is operational breadth + platform gaps + “exists vs. fires with effect.” |

---

*Reviewed files (non-exhaustive): `lib/hooks.sh`, `install.sh`, `uninstall.sh`, `hooks/safety.sh`, `hooks/path-guard.sh`, `hooks/harness-tamper-guard.sh`, `hooks/config-scan.sh`, `hooks/output-secrets-scanner.sh`, `hooks/write-secret-guard.sh`, `hooks/prompt-injection-scanner.sh`, `hooks/mcp-egress-guard.sh`, `hooks/mcp-github-write-gate.sh`, `hooks/mcp-destructive-guard.sh`, `hooks/env-file-guard.sh`, `hooks/bash-injection-scanner.sh`, `hooks/code-security-scanner.sh`, `hooks/lib-secret-patterns.sh`, `hooks/lib-deny.sh`, `hooks/lib-stdin.sh`, `hooks/lib-json-fast.sh`, `hooks/lib-suppress.sh`, `hooks/lib-paths.sh`, `docs/HOOKS.md`, `docs/HOOK_AUTHORING.md`.*
