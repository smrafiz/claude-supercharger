# Claims + Docs Audit — Claude Supercharger

**Date:** 2026-10-14
**Type:** static claims + documentation audit
**Scope:** README, hook catalog, hook-authoring guide, changelog, slash-command specs, and any in-code claims that imply a behavior or guarantee.
**Out of scope here:** pattern quality, contract details, dynamic verification, full file-by-file sweep.

---

## 1. Why this audit exists

A harness that advertises itself as security tooling has a special obligation to say, precisely, what it does and does not do. Overclaiming here is worse than usual, because operators will act on the claim (install it as a control, trust it as a floor) and then discover the gap only when something gets through or when they read the code later. This audit checks whether the docs' strongest claims are actually supported by what's in the repo, and where the language quietly implies more than the code delivers.

---

## 2. Strong claims and how they hold up

### 2.1 "Runs outside Claude's process / not bypassable by the model"

**Where:** README, hook-authoring guide, docs
**What it means:** hooks are a separate process; Claude cannot see or disable them.
**How it holds up:** the mechanism claim is correctly scoped. A hook is a separate process and exit 2 is not negotiable by the model. The docs are careful to separate *mechanism* from *pattern quality*, which is exactly right.
**Watch-out:** "not bypassable by the model" is true of the *mechanism*, not of the *patterns*. A reader who shortens that to "Supercharger cannot be bypassed" is wrong, because the patterns are best-effort and there are documented in-scope and out-of-scope flows.
**Verdict:** claim is true when read precisely; the risk is a reader who reads it imprecisely.

### 2.2 "Every guard runs identically on both channels" / "identical on both channels"

**Where:** README, plugin docs
**What it means:** classic install and plugin deliver the same enforcement.
**How it holds up:** mostly true for the guards themselves, but with documented exceptions (namespacing, SessionStart context vs CLAUDE.md block, the three settings.json keys a plugin manifest can't declare, MCP profile filtering not applying under the plugin). The exceptions are real and worth keeping explicit.
**Watch-out:** "identically" is too strong taken verbatim. The guards run, but the observability, MCP-server-activation rules, and config-delivery path differ in documented ways. The honest version is "the same guards run; some surrounding behavior differs, and here are the exceptions."
**Verdict:** mostly true, but should be qualified with the explicit exceptions rather than left to the reader to infer.

### 2.3 "No telemetry / no data leaves the machine"

**Where:** README, FAQ
**What it means:** the harness does not phone home with user data.
**How it holds up:** the documented network behavior is an optional once-daily version check that fetches a public version string with a static User-Agent, plus the user-run update.sh contacting GitHub only when run, plus optional webhooks the user configures. That's consistent with the claim.
**Watch-out:** the update fetch is the one network call that brings code in. The claim is about *user data*, not about *code ingress*, and the docs mostly respect that distinction. Make the distinction explicit: no telemetry, no user data leaves; update-check fetches a version string; update.sh is the human-run code-ingress path.
**Verdict:** claim is true as stated; make the update-ingress distinction explicit so nobody infers "no network at all."

### 2.4 "Zero context-window cost" for hooks/rules

**Where:** README, marketing framing
**What it means:** enforcement lives in the shell, so it doesn't cost prompt tokens the way inline prompt rules do.
**How it holds up:** the *enforcement* layer is mostly outside the prompt, which is true and is the real differentiator. But Supercharger also has a prompt-layer side (roles, economy tiers, stack standards, session memory, handoff briefs, *additionalContext* injections from many hooks). Those do cost tokens. So "zero context-window cost" is true for the hook enforcement channel, but not for the whole product.
**Watch-out:** the headline is true for the part that matters most (enforcement), but a reader who takes it to mean "nothing Supercharger does costs tokens" is wrong. The honest framing is "enforcement costs nothing in the prompt; the advisory/injection layer does, and is scoped to be small."
**Verdict:** true for enforcement; should not be read as a claim about every feature.

### 2.5 Hook counts and mode counts

**Where:** docs, installer output, README
**What it means:** "43 hooks in safe mode," "152 hooks in full mode," etc.
**How it holds up:** these numbers can be true at a point in time and still mislead, because a hook count can include async bookkeeping hooks that don't block, and a "registered" hook can be inert. The repo has already had the "14 PostToolUse" miscount and the registration-vs-dispatch distinction. So any number should be read as "at version X, with this metric definition."
**Watch-out:** a hook count is a weak security signal by itself. The useful number is "how many guards can actually deny," not "how many entries are in settings.json." The docs mostly know this; the risk is a reader who treats the headline number as assurance.
**Verdict:** fine as a snapshot with a metric definition; not a substitute for "which guards can deny and do they fire."

### 2.6 "Security hooks always run regardless of profile"

**Where:** README, profile docs
**What it means:** the performance profiles (standard/fast/minimal) skip analytics/advisory hooks but not security hooks.
**How it holds up:** this is the right design, and the docs are clear that security hooks are the floor. The watch-out is the same as 2.5: "security hooks" should mean "guards that can deny," and the profile skip list should be auditable against that definition.
**Verdict:** true and well-designed; keep the skip list legible against the deny-capable set.

---

## 3. Doc-level observations (non-claims)

### 3.1 README threat-model section is the best part

The "What this does and doesn't guarantee" section, the mechanism-vs-pattern distinction, and the out-of-scope flows (`!` shell escapes, commands outside the session) are the right framing and should stay canonical. Anything that shortens that section into a stronger marketing line is the wrong direction.

### 3.2 Stale notes are visibly stale

The hook-authoring guide's note about `MessageDisplay`/`UserPromptExpansion` being "later dropped" is now wrong (they were re-added), and the guide says so. That's good — the note self-corrects. More notes like that should be kept visible rather than silently edited, because the silent-edit version hides the defect class.

### 3.3 The hook catalog is auto-generated and that's fine

`docs/HOOKS.md` is clearly labeled as auto-generated. That's the right call for a catalog that big. The risk is that auto-generated content can drift from reality if the generator isn't re-run; the fix is to keep the generator in the repo and treat a stale catalog as a CI/check concern.

### 3.4 Slash-command specs are high quality

The command specs I read are real workflow contracts with reading rules, safety tiers, evidence requirements, and output templates. They're among the best-written parts of the docs and should be treated as the template for any future operator-facing command.

---

## 4. Findings

### F1 — "Identical on both channels" is too strong verbatim

**Severity:** low-medium (misleading over a real but narrow set of differences)
**Where:** README, plugin docs
**Fix:** qualify with the documented exceptions (namespacing, SessionStart context, three settings.json keys, MCP profile filtering). The guards run; some surrounding behavior differs.

### F2 — "Zero context-window cost" is true for enforcement, not for the whole product

**Severity:** low-medium (overbroad if read literally)
**Where:** README headline framing
**Fix:** keep the enforcement claim; add a short qualifier that the advisory/injection/memory layer does carry prompt tokens and is scoped to be small. The headline is strongest when it's precise.

### F3 — "Not bypassable by the model" is a mechanism claim, not a pattern claim

**Severity:** low-medium (true when precise, wrong when shortened)
**Where:** README, docs
**Fix:** keep the mechanism claim; ensure the adjacent text keeps the pattern-quality caveat close to it so the two are not read apart.

### F4 — Hook-count and mode-count numbers should carry a metric definition

**Severity:** low
**Where:** docs, installer output
**Fix:** when a count is given, say what it counts (entries in settings.json vs. deny-capable guards vs. firing hooks). The repo has already been bitten by miscounts; the habit of stating the metric prevents the next one.

### F5 — Auto-generated catalog should have a freshness guard

**Severity:** low
**Where:** `docs/HOOKS.md`
**Fix:** keep the generator in the repo and treat a stale catalog as a checkable condition. A catalog that's auto-generated but not re-run is still drift-prone.

---

## 5. Summary

The docs are unusually good about their own limits, which is the most important property to verify. The strongest claims hold up when read precisely; the risk is imprecise reading and a few phrases that are too strong verbatim ("identical on both channels," "zero context-window cost" taken broadly, "not bypassable" untethered from mechanism). Tightening those to precision costs little and removes the main surface for overclaiming.

*See also:* `docs/audits/contract-drift-audit.md`, `docs/audits/pattern-parity-audit.md`, `docs/audits/dynamic-verification-plan.md`, `docs/audits/file-sweep-audit.md`.
