# Pattern + Parity Audit — Claude Supercharger

**Date:** 2026-10-14
**Type:** static pattern + parity audit (code + design)
**Scope:** the shared security pattern surfaces and the channels that are supposed to share them.
**Out of scope here:** contract auditing (separate file), dynamic verification (separate file), full file-by-file sweep (separate file).

---

## 1. Why this audit exists

The most common bug in a multi-channel security harness is **parity drift**: a pattern that is supposed to protect two channels protects one and not the other, usually because the channels evolved separately. Supercharger is unusually aware of this — `lib-secret-patterns.sh` is a deliberate single source of truth, and the changelog repeatedly calls out channel-parity gaps as they were found. This audit checks whether the *current* shared surfaces are structured so parity can be maintained, and where the residual false-positive / false-negative surfaces still live.

---

## 2. Secret patterns (lib-secret-patterns.sh)

**Contract:** one pattern array consumed by the output scanner, the commit guard, and the sendmessage guard. A pattern added here should strengthen all three channels; a pattern missing here should be a deliberate, explained gap.

**Assessment:** this is the best-maintained pattern surface in the repo. The rationales are measured and specific: the Base58 Bitcoin WIF anchoring (42 FPs across 20 screenshots down to 1), the property-reference dot removal with per-category FP counts, the SHA-256-vs-WIF disambiguation, the image-payload elimination. When a harness maintains its secret patterns at this level of care, the residual risk is usually operational rather than algorithmic.

**Residual false-negative surfaces to keep in view:**
- a secret that doesn't match any fixed format and isn't a keyword=value shape (a custom internal token with no prefix) will not be caught. That's inherent to pattern-based detection; the honest framing is "catches known formats."
- the per-channel posture differs: output scanner is async warn, commit guard is deny-on-staged-diff, sendmessage guard is pre-prompt. A secret can be caught in one channel and not another depending on when and how it appears.

**Residual false-positive surfaces to keep in view:**
- the 400-char ledger cap is now above the redaction step (correct ordering), but a long command whose sensitive portion sat past char 400 before redaction can still survive in a partially redacted form. The ordering fix is right; the residual is the cap itself.
- the generic keyword=value pattern still has a small FP surface on any identifier-heavy code/log output. The dot-removal change reduced it a lot; it is not zero.

**Recommendation:**
- keep `lib-secret-patterns.sh` as the single source for the three named channels. If a new channel is added, it should consume the same array, not a copy.
- surface the active pricing/redaction state in an operator-visible place when a secret-related block occurs, so a false positive can be triaged with the right context (which channel, which pattern class, which rule).
- consider redacting the full string *before* applying the cap, so a secret at position 401+ cannot survive as a partial fragment. The current ordering is better than before; pre-cap full-string redaction would close the residual.

---

## 3. Prompt-injection patterns (multi-channel scanner)

**Contract:** the same override payloads should be caught regardless of which channel carries them; the channels that share patterns should not drift into different rule sets.

**What's there:** scanners on MCP output, WebFetch/WebSearch, Read content, Bash output (warn-only, fail-open), slash-command expansion, and a structural MCP-provenance check. The Bash-output channel is explicitly warn-only and fail-open; the MCP/WebFetch/Read channels are async.

**Assessment:** coverage is expanding and the project is honest that this is best-effort opposition to opportunistic injection, not a defense against a targeted attacker who controls your prompts. The Bash-output channel's posture (warn-only, after the fact) is the right performance call, but it should be stated plainly as "detected after the fact, not prevented" for that channel.

**Residual surfaces:**
- Bash output is the hottest text channel and the one with the weakest pre-execution posture. An injection that arrives through Bash output is seen by the model before the async scanner can warn.
- the structural provenance check is a different kind of defense (forged tool-call/system framing) and should not be conflated with the persuasion-pattern scanner. Conflating them would hide the gap each covers.
- new channels (e.g. a future tool whose output reaches the model) need to be checked for parity, not silently assumed covered by "we have a scanner."

**Recommendation:**
- make the operator-facing posture explicit per channel: synchronous block vs. async warn vs. after-the-fact detect. The distinction matters and is currently a bit scattered across hook docs.
- when a new output-reaching tool is added, add a parity line for it explicitly, even if the answer is "no pre-execution guard, only 사후 detection."
- keep the provenance check and the persuasion scanner as two named defenses with their own limits, so a reader doesn't infer one from the other.

---

## 4. Egress and exfiltration patterns (Bash + MCP + WebFetch)

**Contract:** the dangerous egress shapes should be caught regardless of whether the agent reaches them through Bash, MCP tool args, or WebFetch, and the patterns across those channels should not drift.

**What's there:** `safety.sh` covers Bash-shaped egress, `mcp-egress-guard.sh` covers MCP tool-arg URLs, `webfetch-egress-guard.sh` covers the native WebFetch/WebSearch channel, and `bulk-exfil-guard.sh` covers whole-tree archive-to-network-sink shapes. The changelog notes shared egress pattern sources and the residual IRC/cloud-metadata/instance-metadata encodings.

**Assessment:** the multi-channel coverage here is real and the project has already chased several parity gaps (WebFetch being unguarded was one). The shared-pattern-source discipline (where it exists) is the right structure.

**Residual surfaces:**
- egress is a shape problem, and shapes are easy to rephrase. The residual is always "a new spelling of the same capability." The honest framing is "catches known egress shapes," not "blocks all egress."
- the WS form of Monitor is explicitly noted as having no `command` field and therefore no inspection; that's a known residual, not a silent gap, which is good.
- cloud-metadata and instance-metadata SSRF encodings keep expanding (decimal, hex, IPv6, userinfo-prefixed private-net forms). A static pattern list will always lag a little here.

**Recommendation:**
- keep egress patterns in as few shared sources as practical, with an explicit note per source about which channels consume it.
- when a new egress encoding is added, record which channels gained it and which already had it, so a future drift review can see the coverage map rather than infer it.

---

## 5. Dangerous-command patterns (safety.sh, git-safety.sh)

**Contract:** the destructive/dangerous command patterns should be anchored on command position and shape, not on keywords anywhere in the string, and the Bash patterns and the git patterns should not silently drift apart where they overlap.

**What's there:** `safety.sh` has a large ERE rule set with positional anchoring on many rules, a fast-path that structurally excludes content-reading verbs, and explicit notes about keyword-anywhere vs. command-position mistakes. `git-safety.sh` is a separate, more precise engine for the git family, with rewrite + deny + ask paths.

**Assessment:** the anchoring discipline here is strong and the history of keyword-anywhere false positives is documented. The fast-path is structurally justified (bare verbs, no metachar, no content-reading verbs excluded). The git-safety rewrite path is the most contract-fragile part and belongs in the contract audit, but its *pattern* side (which git spellings are dangerous) is well-maintained and well-changelog'd.

**Residual surfaces:**
- POSIX ERE has no lookahead, so some anchors have to be positive-shape and some false-positive avoidance has to use second anchors rather than clean lookarounds. That's a real limitation and is handled honestly where it matters.
- compound commands can still reach a dangerous verb after a safe prefix (`safe && rm -rf /`). The segment-based checks reduce this but any pattern engine has to be explicit about whether it sees the command pre- or post-normalization and pre- or post-split.
- the `cmd-normalize.sh` / `split_segments` pipeline is a shared dependency for many rules; a change there can silently disable a rule that read what was removed. This is more a process risk than a pattern risk, but it's part of the parity story.

**Recommendation:**
- keep a note per dangerous-command rule about whether it anchors on command position, segment, or full command, and what normalization it assumes. That makes future rule reviews less likely to reintroduce the keyword-anywhere class.
- when `cmd-normalize.sh` or `split_segments` changes, grep the rule set for the text being removed before merging. This repo already has that note in its own authoring guide; treat it as a required step, not a suggestion.

---

## 6. Findings

### F1 — Secret-pattern discipline is excellent; close the cap-ordering residual

**Severity:** low-medium
**Where:** `hooks/lib-secret-patterns.sh`, `hooks/safety.sh`, `hooks/commit-guard.sh`, `hooks/sendmessage-guard.sh`
**Note:** redact the full string before the cap so a secret at position 401+ cannot survive as a partial fragment. Surface which channel and which pattern class fired on a block for triage.

### F2 — Prompt-injection posture differs by channel and should be explicit per channel

**Severity:** low-medium
**Where:** `hooks/prompt-injection-scanner.sh`, `hooks/bash-injection-scanner.sh`, `hooks/mcp-provenance.sh`, `hooks/webfetch-egress-guard.sh`
**Note:** label each channel as synchronous block / async warn / after-the-fact detect. Bash output is the hottest text channel with the weakest pre-execution posture; say that plainly.

### F3 — Egress coverage is real and multi-channel; keep a coverage map per pattern source

**Severity:** low
**Where:** `hooks/safety.sh`, `hooks/mcp-egress-guard.sh`, `hooks/webfetch-egress-guard.sh`, `hooks/bulk-exfil-guard.sh`
**Note:** when a new egress encoding is added, record which channels gained it. Cloud/instance-metadata encodings keep expanding; state the residual honestly.

### F4 — Dangerous-command anchoring discipline is strong; formalize the per-rule anchor assumption

**Severity:** low
**Where:** `hooks/safety.sh`, `hooks/git-safety.sh`, `hooks/cmd-normalize.sh`
**Note:** per-rule anchor note (command position / segment / full command, normalization assumed). Treat `cmd-normalize`/`split_segments` changes as a required gating review for the rule set.

### F5 — Parity is structurally supported but must be actively maintained per new channel

**Severity:** low-medium
**Where:** all shared pattern surfaces
**Note:** the single-source discipline is the right structure. The residual is that every new channel must be checked for parity explicitly; silent assumption of coverage is the drift mechanism this repo has already hit more than once.

---

## 7. Summary

The pattern surfaces here are better-structured than in most harnesses of this size: one shared secret array, explicit channel notes for injection and egress, honest anchoring discipline on dangerous-command rules, and a changelog that names the parity gaps as they were found. The residual is operational and process-shaped: cap ordering on the ledger, explicit per-channel posture for injection, a coverage map per egress source, and a habit of checking every new channel for parity instead of assuming it.

*See also:* `docs/audits/contract-drift-audit.md` (the contracts the patterns depend on), `docs/audits/dynamic-verification-plan.md` (payload matrix for the channels above), `docs/audits/file-sweep-audit.md` (hook-by-hook evidence).
