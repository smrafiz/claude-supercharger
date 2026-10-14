# Integration Research Report — Claude Supercharger

**Date:** 2026-10-14
**Prepared by:** Buffy (Solar Pro 4)
**Method:** web search (Google), GitHub topic search, direct reads of selected sources. Sources are cited inline. This is a research report and an ideas menu, not an implementation plan and not a commitment to add any of these.
**Read-only everywhere below:** no Supercharger code is changed by this document.
**Verification status:** sources re-checked during prep; corrections and a verification appendix were added (see end). Two Reddit threads were not fetchable and remain search-snippet-supported.

---

## 1. What users are actually complaining about (Reddit + secondary sources)

These are the pain points that show up repeatedly in the 2026 Reddit discourse and in the cost/performance write-ups. I'm including this because an integration worth building should solve a real complaint, not just add a feature.

### 1.1 Cost burns through the day fast

- The most repeated complaint tier is **usage/rate-limit burn**: a Pro session hits its limit by mid-afternoon; a casual hello can eat a surprising fraction of a day's budget.
- One long-term user report (r/ClaudeAI, May 2026) attributed quality drift between March and April 2026 to three product-layer changes: a reasoning-effort downgrade, a caching bug, and token inflation. The same thread says the April postmortem didn't fix everything and the token inflation makes it worse. *(search-snippet-supported; Reddit did not render on direct fetch)*
- Secondary cost write-ups (Termdock, Lowcode Agency, Ofox, Claudefa.st) converge on the same structural causes: too much Opus-level reasoning on simple tasks, bloated CLAUDE.md / context, long sessions filling the window, and few explicit budgets.

**Implication for Supercharger:** the product already has a budget cap, economy tiers, and an output compactor. The complaint is not "no cost tools exist" — it's that **cost is still hard to control in the moment** and hard to see. That points to better real-time visibility and better routing of work to the right effort/price, not just post-hoc reporting.

### 1.2 Long sessions feel slow and degrade

- Repeated complaints: "Claude Code performance has dropped drastically," "feels slow, frustrating and expensive," "long sessions degrade." *(search-snippet-supported; Reddit did not render on direct fetch)*
- A LinkedIn note on Claude Code's shipped verbosity setting says the problem is mainly **long sessions**, "which is exactly where caching matters most," and that the fix was giving every layer a plain cache.
- A GitHub issue (anthropics/claude-code#14634) is about excessive file I/O during normal sessions (~1.5 writes/sec to `.claude.json`), which is the kind of internal behavior that makes a session feel janky.

**Implication for Supercharger:** the product already compacts Bash output and tracks context %. The complaint suggests the next lever is **session-internal state hygiene** — keeping the in-session transcript/state from growing noisy, and giving the user cleaner levers to reset mid-session rather than only at the end.

### 1.3 Verbosity and "it keeps talking"

- Users complain about verbose output and models ignoring style/conciseness instructions. One Instagram/LinkedIn note says Opus can "wander into unnecessary rabbit holes" and that some users complain about verbosity specifically.
- Supercharger's own README cites the long-standing Claude Code complaints this is built to address (verbose comments the model won't stop adding; repetitive rhetorical tics that ignore style instructions), with upvote counts.

**Implication for Supercharger:** this is the core of the economy/output-style layer already here. The integration gap is less "add verbosity control" and more **make the existing tiers + output style actually stick across the session and be visible**, especially when Claude is the one producing the verbose text.

### 1.4 Security people are watching Claude Code closely

The CVE surface in 2026 is real and is the kind of context a guardrail framework should be aware of:
- **CVE-2026-39861** — Anthropic Claude Code sandbox escape via symlink attack (CWE-22); prior to 2.1.64; prompt-injection trigger; NVD published 2026-04-21. *(verified)*
- **CVE-2026-33068** — Claude Code **workspace trust dialog bypass via repo-controlled settings file** (`permissions.defaultMode` in committed `.claude/settings.json`); multiple sources cite CVSS 7.7; fixed prior to 2.1.53. *(verified; wording precision corrected below)*
- **CVE-2026-55607** — Claude Code git worktree sandbox escape via `.git` worktree-name confusion (2.1.38–2.1.163), full chain to `~/.zshenv` write + code execution; working PoC. *(verified)*
- **CVE-2026-28292** — simple-git RCE (CVSS 9.8) via case-sensitivity bypass of `blockUnsafeOperationsPlugin`; wide npm reach. *(verified)*
- **CVE-2026-21852** — Claude Code project-load flow allowed malicious repos to exfiltrate data including Anthropic API keys before trust confirmation; fixed prior to 2.0.65. *(verified)*
- Adversa: Claude Code deny rules silently bypassed after a command exceeds ~50 subcommands; the tree-sitter parser that handles it correctly exists in Anthropic's codebase but is not enabled in public builds. *(verified)*
- CSA research note (June 2026): Claude Code GitHub Action permission bypass (`checkWritePermissions` trusted any GitHub App actor ending in `[bot]`); broader "Comment and Control" class across Claude Code, Gemini CLI Action, and GitHub Copilot Agent; Clinejection incident (Feb 17, 2026). *(verified)*
- Aviatrix: Claude Code 2026 domain validation bypass / data exfiltration (Feb 2026). *(search-snippet-supported)*

**Implication for Supercharger:** the product already maps to OWASP ASI 2026 and already covers several of these classes in its config-scan and guards. The value-add here is **keeping the CVE watch live and making the mapping explicit and current**, because security users will ask "does this help against CVE-X" and the answer should be current, not implied.

### 1.5 Skill/injection surface is real, current, and increasingly well-known

- **SkillJect (arXiv 2602.14211)** — automated framework for stealthy skill-based prompt injection with a three-agent closed loop (Attack/Code/Evaluate) and a malicious-payload hiding strategy; evaluated across coding-agent settings and real-world software-engineering tasks. Frames skill-based prompt injection as an under-measured surface. *(verified)*
- **Snyk ToxicSkills (Feb 5, 2026)** — first comprehensive audit of the agent-skills ecosystem; scanned 3,984 skills from ClawHub and skills.sh; 13.4% (534 skills) with at least one critical-level issue; 36.82% (1,467 skills) with at least one flaw at any severity; 76 confirmed malicious payloads (credential theft, backdoor, data exfiltration), 8 still publicly available on clawhub.ai as of publication; first coordinated malware campaign targeting Claude Code and OpenClaw via 30+ malicious skills on ClawHub. *(verified)*
- **CSA research note (June 5, 2026)** — Claude Code GitHub Action permission bypass + "Comment and Control" class across multiple AI agent platforms; Clinejection incident as a real supply-chain compromise. *(verified)*
- arXiv survey (2601.17548) — systematizes prompt injection on agentic coding assistants from 78 sources. *(search-snippet-supported)*
- Reddit testing thread: Claude Code has "no reliable defense against injections embedded as workflow completion steps," with the caveat that this is not a Claude-specific bug. *(search-snippet-supported)*

**Implication for Supercharger:** the product already has prompt-injection scanning, skill-integrity + skill-poisoning scanners, MCP-provenance, and output secret scanning. The complaint/surface here is that **the trust boundary around skills and agent instructions is the hot spot**, and users are aware of it. That argues for making the trust model more explicit and for closing any channel-parity gaps in what channels get scanned.

### 1.6 What people like and reach for

- The "awesome-claude-code" ecosystem is large: skills, subagents, hooks, slash commands, MCP servers, status lines, developer tooling. The repo (hesreallyhim/awesome-claude-code) is large and active: 2,122 commits, ~55.7k stars, ~4.8k forks. *(verified)*
- The TrueFoundry MCP list (Sep 2026) frames the "essential five" as Filesystem, GitHub, Context7, Playwright, Sequential Thinking — i.e., the value is **execution across real systems**, not just code generation. *(verified)*
- Community thread: users mention leaning on Superpowers and Nelson for feature development. *(search-snippet-supported)*

**Implication for Supercharger:** the integration sweet spot is **gating and guiding the use of these things**, not necessarily providing them. Supercharger already has agent routing, subagent guards, MCP write-gates, and a skills lock/layer. The gap is more about **making the harness a good citizen in a world full of skills/MCP/agents**, with clear trust and cost controls.

---

## 2. Integration ideas worth considering

Grouped by the complaint/surface they address. Each is framed as "what it would do," "why it's worth it," and "where it overlaps what Supercharger already does."

### 2.1 Real-time cost + effort routing (addresses cost burn, verbosity)

**What:** a hook/command layer that routes a task to the right effort/price before the work starts, and gives the user a clear in-session "this is expensive, do you want to continue" moment for expensive operations.

**Why:** the dominant cost complaint is paying Opus-level reasoning for simple work. The Termdock write-up is explicit that routing simple tasks away from Opus is the highest-leverage move, and that `/effort` tuning plus good CLAUDE.md are the main levers.

**Overlap:** Supercharger already has economy tiers, a budget cap, a cost forecast before agent spawns, a budget-cap check hook, and an output compactor. This idea is about **making the routing/visibility first-class and in-the-moment** rather than post-hoc. Possible shape: a `/sc-cost` or `/sc-effort` control that suggests effort/price for the current task, and a PreToolUse or UserPromptSubmit nudge when a high-cost pattern is about to be used for a low-complexity task.

**Watch-outs:** don't build a "silent auto-downgrade" that the user can't see or override; cost routing is a trade-off between speed/cost and quality, and the user should be able to see and disagree.

### 2.2 Session health + mid-session reset levers (addresses slow, long-session degradation)

**What:** hooks/commands that help keep a long session healthy and give the user clean mid-session reset options: compact/reset guidance tied to real signals, transcript/state hygiene, and a clearer "you are now thrashing / context is noisy" indicator.

**Why:** the long-session complaint is not just "context fills up"; it's that sessions become slow, noisy, and expensive, and the user's only good option is often to start over. Better mid-session levers + a clearer health signal would directly address that.

**Overlap:** Supercharger already compacts output, tracks context %, has `/compact` awareness, and has session checkpoints/memory. This idea is about **session health as a first-class signal**, not just context percentage. Possible shape: a `/sc-health` or `/sc-prune` control with a plain-language read on session health and what to do about it.

**Watch-outs:** don't make the hook itself add the I/O pressure that makes sessions feel janky (the GitHub issue about excessive writes is a cautionary example). Keep health checks light and mostly read-only.

### 2.3 Trust transparency for skills, agents, and MCP (addresses the security/skill-injection surface)

**What:** make the trust model for skills, agent definitions, and MCP servers explicit and per-session: what was loaded, what is trusted on first use, what changed since last load, what is an MCP server and what can it do.

**Why:** the 2026 skill-injection and malicious-skills literature is real and current. Supercharger already has skill-integrity + poisoning scanners and MCP guards, but the **trust story is somewhat implicit**. Making it explicit (and visible in a command like `/sc-trust` or `/sc-status`) would directly address the security-aware user's question "what did my session just load and trust."

**Overlap:** Supercharger already has skill-integrity guard, skill-poisoning scanner, agent-poisoning scanner, MCP write-gates, MCP egress guard, MCP circuit-breaker, and elicitation guard. This idea is about **consolidating the trust view**, not inventing new scanning. Possible shape: a `/sc-trust` command that lists loaded skills/agents/MCP servers with their trust status and change history.

**Watch-outs:** trust-on-first-use is a deliberate trade-off vs. a lockfile; don't present it as stronger than it is. Also don't make the trust reporter itself a network call that loads new code.

### 2.4 Live CVE / threat-surface watch (addresses the security maintenance surface)

**What:** a lightweight, clearly-scoped watch that keeps the project's security coverage mapped to current CVEs and known bypass classes, and surfaces when a new class appears that Supercharger should consider.

**Why:** security users will ask "does this guard against CVE-X," and the answer should be current. The 2026 landscape is already broad enough (CVE-2026-39861, CVE-2026-33068, CVE-2026-55607, CVE-2026-28292, CVE-2026-21852, the Adversa deny-rule bypass, the CSA GitHub Action / "Comment and Control" class, the Aviatrix domain-validation/exfiltration note) that manual tracking is the failure mode.

**Overlap:** Supercharger already has `config-scan.sh` covering some CVE classes at session start and an OWASP ASI 2026 mapping in the README. This idea is about **keeping that mapping current and visible**, possibly as a periodic advisory rather than a per-session block. Possible shape: a weekly/read-only advisory hook or command that reports the current CVE coverage map and any new class worth a look.

**Watch-outs:** this should be read-only advisory and should not fetch and execute anything. The update path is the one network call that brings code in; a CVE watch should not become a second code-ingress path.

### 2.5 Better "what just happened" observability (addresses the "I don't know why it did that" complaint)

**What:** a clearer in-session explanation layer for blocks, asks, and cost events: why a command was blocked, what category fired, what the remedy is, and what the cost impact of the last turn was — in plain language, visible to the human and usable by the model.

**Why:** a recurring complaint is that blocks and cost events feel opaque. Supercharger already has `/sc-why`, a block ledger, event logging, and a statusline. The gap is **making the explanation consistently good and consistently visible**, especially the "what would have let this through" part.

**Overlap:** Supercharger already has `/sc-why`, the block ledger, `lib-deny`'s decision shape, and event logging. This idea is about **quality and consistency of explanation**, plus surfacing cost impact in a way that is actually useful mid-session. Possible shape: a `/sc-why`-style explanation for the last N events with category, reason, remedy, and cost impact.

**Watch-outs:** explanation text that reaches the model costs tokens; keep it bounded and purposeful. Also avoid leaking redacted-secret fragments into explanations (the ledger cap ordering issue from the earlier review is exactly this risk).

### 2.6 A cleaner plugin/skill/command marketplace posture (addresses the ecosystem fit)

**What:** position Supercharger as a good citizen in the awesome-claude-code ecosystem: a clear story for how its hooks/commands/roles interact with skills and third-party MCP servers, and a clear "you can add more; here's how we guard it" posture.

**Why:** the ecosystem is large and growing, and users are assembling their own stacks from skills + subagents + MCP + hooks. A harness that only talks about itself loses mindshare; one that says "here's how we fit with the rest of the ecosystem and here's how we keep it safe" is more useful.

**Overlap:** Supercharger already ships hooks, commands, roles, economy tiers, MCP profiles, and a plugin channel, and already guards skills/agents/MCP. This idea is about **documentation + trust posture + integration points**, not new runtime behavior. Possible shape: a `docs/ecosystem-fit.md` or similar that explains how Supercharger relates to skills, MCP, subagents, and third-party hooks, and what it does and doesn't guard.

**Watch-outs:** don't imply Supercharger guards things it can't (e.g., a skill's behavior after it's loaded and trusted). Keep the trust boundaries explicit.

---

## 3. Source map (what each claim rests on)

**Complaints + cost/performance:**
- r/ClaudeAI long-term user report, May 2026 (quality drift; reasoning-effort downgrade, caching bug, token inflation) — search-snippet-supported; Reddit did not render on direct fetch.
- r/ClaudeCode "Claude Code performance has dropped drastically" and "Developing with Claude Code feels slow, frustrating and expensive" — search-snippet-supported; Reddit did not render on direct fetch.
- LinkedIn note on Claude Code verbosity setting + long-session/caching framing — search-snippet-supported.
- GitHub anthropics/claude-code#14634 — excessive `.claude.json` writes during sessions — search-snippet-supported.
- Termdock "Claude Code Costs $200/mo — Cut It in Half" — **directly read**: 40% simple / 25% moderate / 35% deep-reasoning; 65% of budget on tasks that could be cheaper/faster; `/effort` low/medium/high/max; "before: 100% at high effort, hit rate limits by mid-afternoon"; CLAUDE.md 2.3→1.4 iterations; Gemini CLI offload.
- Ofox, Lowcode Agency, Claudefa.st, Hackernoon, UXPlanet — cost/context optimization 2026 — search-snippet-supported.

**Security / injection / CVEs:**
- SkillJect (arXiv 2602.14211) — **directly read**: automated stealthy skill-based prompt injection; three-agent closed loop; real-world SWE tasks; under-measured surface.
- Snyk ToxicSkills (Feb 5, 2026) — **directly read**: 3,984 skills scanned; 13.4% critical (534); 36.82% any flaw (1,467); 76 confirmed malicious payloads; 8 still on clawhub.ai; 30+ malicious skills target Claude Code/OpenClaw.
- CSA research note "AI Agent Prompt Injection: The New CI/CD Supply Chain Threat" (June 5, 2026) — **directly read**: Claude Code GitHub Action permission bypass in `checkWritePermissions` (any `[bot]` actor trusted); "Comment and Control" class across Claude Code, Gemini CLI Action, GitHub Copilot Agent; Clinejection incident Feb 17, 2026.
- CVEs: **directly read/verified** — CVE-2026-39861 (SentinelOne), CVE-2026-55607 (SecureLayer7), CVE-2026-28292 (CodeAnt), CVE-2026-21852 (SentinelOne + NVD + GHSA). CVE-2026-33068 — **directly read** from search results (SentinelOne, GitLab, NVD, Reddit, Mondoo, Vulners); wording precision corrected below.
- Adversa deny-rules bypass — **directly read**: >50 subcommands; legacy regex parser permissive "ask"; tree-sitter parser exists in codebase but not enabled in public builds.
- Aviatrix Claude Code 2026 domain validation bypass / data exfiltration (Feb 2026) — search-snippet-supported.

**Ecosystem / MCP / hooks:**
- hesreallyhim/awesome-claude-code — **directly read**: 2,122 commits; ~55.7k stars; ~4.8k forks; topics include agent-skills, claude-code, coding-agents, hooks.
- claude-code-hooks mastery / topics; claude-code-skills topics — search-snippet-supported.
- TrueFoundry "Best MCP Servers for Claude Code" (Sep 10, 2026) — **directly read**: 18 servers; essential five = Filesystem, GitHub, Context7, Playwright, Sequential Thinking; "real power is execution across systems."
- Medium "8 Claude Code Hooks That Replaced My Pre-Commit Checks"; ayautomate "12 Best Picks for 2026"; GitButler hooks post — search-snippet-supported.
- r/ClaudeCode favorite plugins/skills thread (Superpowers, Nelson) — search-snippet-supported.

**Workflow / agent patterns:**
- MindStudio "5 Claude Code Workflow Patterns" (Apr 2026) — search-snippet-supported.
- Anthropic "Building Effective AI Agents" — search-snippet-supported.
- arXiv "Design Space of Today's and Future AI Agent Systems" (2604.14228) — search-snippet-supported.
- Tembo "Claude Code Subagents: A 2026 Practical Guide" — search-snippet-supported.

---

## 4. What I would not build (and why)

- **A silent auto-downgrade of model/effort without user visibility.** Cost routing is useful; invisibly switching the user's model/effort is a trust risk and a complaint generator in its own right.
- **A second code-ingress network path under the guise of a "CVE watch" or "update check."** The product already has one update path; adding another one that fetches and runs things is the wrong architecture.
- **A claim that Supercharger defends against prompt injection end-to-end.** The 2026 literature and the product's own docs are clear that it's best-effort, channel-specific, and not a defense against a targeted attacker who controls prompts. Keep that honest.
- **A trust story that overpromises on skills/agents/MCP.** Trust-on-first-use is a deliberate trade-off; present it as such.
- **A feature that claims to make prompt injection "solved."** The literature says otherwise.

---

## 5. What I would not recommend

- Don't chase a feature that claims to make prompt injection "solved." The 2026 literature and the product's own docs are clear that this is best-effort and channel-specific, not an end-to-end defense against a targeted attacker who controls prompts.
- Don't build invisibility into cost/effort controls. That's the wrong trade-off and will generate its own complaints.
- Don't let the report's ideas drift into re-implementing MCP servers, skills, or other things the ecosystem already provides. Supercharger's value is gating, guiding, and explaining — not becoming another plugin marketplace.
- Don't add a second code-ingress network path under any guise. The update path is the one place code comes in; keep it singular and explicit.

---

## 6. Recommendations (standalone read)

These are the recommendations distilled from the research above. They are not an integration plan and not a commitment to build any of them; they are the directions I'd prioritize if the goal is to address the real complaints and fit well with the existing 160-hook, two-channel architecture.

### 1. Make cost and effort control first-class and in-the-moment

**Why this matters most:** the dominant complaint is cost burn — a Pro session hitting its limit by mid-afternoon, trivial prompts eating budget, and too much Opus-level reasoning spent on work that does not need it. The strongest external takeaway (from the Termdock analysis) is that routing simple tasks away from Opus is the highest-leverage move, and that `/effort` tuning plus a good CLAUDE.md are the main levers. Supercharger already has economy tiers, a budget cap, a cost forecast before agent spawns, a budget-cap check hook, and an output compactor. The gap is not raw capability; it is making cost and effort control visible and usable in the moment.

**What a good version of this looks like:**
- A clear in-session read on "you are spending a lot right now; here is why and what is expensive."
- A plain way to say "this task does not need maximum effort; use a cheaper level."
- A visible cost impact for the last turn or last few turns, in plain language, not just a statusline number.
- Better defaults that route simple lookups and small edits away from expensive reasoning without the user micromanaging every prompt.

**What to avoid:** silent auto-downgrade the user cannot see or override. Cost routing is a trade-off between speed/cost and quality; invisibly switching the user's model or effort is its own complaint generator.

### 2. Make long-session health a real feature, not just "compact sometimes"

**Why this matters:** the long-session complaint is not only that context fills up. It is that sessions become slow, noisy, expensive, and hard to recover mid-flight, and the user's best option is often to start over. One external note made the point that the problem is mainly long sessions, "which is exactly where caching matters most." There is also a real GitHub issue about Claude Code itself doing excessive file I/O during sessions, which is the kind of internal behavior that makes a session feel janky.

**What a good version looks like:**
- A plain-language session health signal that says something useful, not just "context is at 70%."
- Clean mid-session reset/prune levers tied to real signals, so the user can recover without abandoning the whole session.
- Health checks that do not add the kind of I/O pressure that makes sessions feel janky in the first place.

**What to avoid:** health checks that add noticeable per-turn overhead, or reset levers so buried that nobody uses them when they are actually needed.

### 3. Make the trust model for skills, agents, and MCP explicit and visible

**Why this matters:** this is the security hot spot in 2026, and users are increasingly aware of it. Supercharger already has skill-integrity, skill-poisoning, agent-poisoning, MCP write-gates, egress, circuit-breaker, and elicitation guards, but the trust story is somewhat implicit. The external literature — SkillJect on skill-based prompt injection, Snyk ToxicSkills (13.4% critical, 36.82% any flaw, 76 confirmed malicious payloads, 8 still live on clawhub.ai; 30+ malicious skills targeting Claude Code/OpenClaw), the CSA GitHub Action / "Comment and Control" note — all points the same way: the trust boundary around skills, agent instructions, and MCP servers is the live surface.

**What a good version looks like:**
- A clear, per-session view of what was loaded and trusted: which skills, which agent definitions, which MCP servers, and the trust status of each.
- A clear statement of what "trusted on first use" means and does not mean, so a user who installs mid-flight understands that pre-existing skills were not re-baselined.
- Change-detection visibility: if something that was trusted is later different, that should be visible, not silent.

**What to avoid:** overpromising. Trust-on-first-use is a deliberate trade-off against maintaining a lockfile; present it honestly. And don't claim the harness guards a skill's behavior after it's loaded and trusted — that's not what any scanner can guarantee.

### 4. Keep the CVE / threat-surface coverage current and visible

**Why this matters:** security users will ask whether the harness helps against specific recent issues, and the 2026 landscape is already broad enough (CVE-2026-39861, CVE-2026-33068, CVE-2026-55607, CVE-2026-28292, CVE-2026-21852, the Adversa deny-rule bypass, the CSA GitHub Action / "Comment and Control" class, the Aviatrix domain-validation/exfiltration note) that manual tracking is the failure mode. The product already has `config-scan.sh` covering some classes at session start and an OWASP ASI 2026 mapping in the README.

**What a good version looks like:**
- A current, visible mapping from recent CVE/surface classes to what Supercharger covers, what it does not, and what is worth a look.
- A lightweight advisory that does not become a second code-ingress path.

**What to avoid:** any "CVE watch" that fetches and executes code. The update path is the one network call that brings code in; don't turn a CVE advisory into a second ingress path.

### 5. Improve the consistency and visibility of explanations

**Why this matters:** a recurring complaint is opacity — blocks and cost events feel unexplained. Supercharger already has `/sc-why`, a block ledger, event logging, and a statusline. The gap is consistency and usefulness: a good explanation of what fired, why, what would have let it through, and what it cost.

**What a good version looks like:**
- A consistently good explanation for the last several events: what fired, why, what would have let it through, and what it cost.
- Explanations that are useful to both the human and the model, without leaking redacted-secret fragments into explanations.

**What to avoid:** explanation text that reaches the model and costs tokens without being bounded and purposeful. Also avoid the ledger-cap ordering pit that can leave a partial secret fragment in a block record — that is exactly the class of thing that turns a good explanation into a leak.

### 6. Publish a clear ecosystem-fit story

**Why this matters:** the ecosystem is large and growing (skills, subagents, hooks, slash commands, MCP servers, status lines), and users are assembling their own stacks. The value users reach for is execution across real systems, not just code generation — the TrueFoundry MCP roundup's "essential five" were Filesystem, GitHub, Context7, Playwright, Sequential Thinking. A harness that only talks about itself loses mindshare; one that says "here is how we fit with the rest of the ecosystem and here is how we keep it safe" is more useful and more credible.

**What a good version looks like:**
- A clear document explaining how Supercharger relates to skills, MCP servers, subagents, and third-party hooks.
- A clear statement of the trust boundaries: what it guards, what it cannot, and where first-use trust is the model.

**What to avoid:** implying Supercharger defends things it cannot. The honest framing is "we are a strong default harness with explicit limits," not "we make the whole ecosystem safe."

---

## 7. Bottom line

The complaints are mostly about cost control in the moment, long-session health, verbosity, opacity, and an increasingly real trust/injection surface. The recommendations follow from that: make cost and effort control first-class and visible; make session health a real feature; make the trust model for skills/agents/MCP explicit; keep CVE coverage current and visible; improve the consistency of explanations; and publish a clear ecosystem-fit story.

That is the report and the recommendations. No integration plan attached. The existing 160-hook, two-channel architecture is the starting point for all of it; most of the value here is surfacing, routing, explaining, and watching — not replacing what is already there.

---

## 8. Source verification notes (added during prep)

- **Directly read and verified:** Termdock cost analysis; TrueFoundry MCP list; SkillJect (arXiv 2602.14211); Snyk ToxicSkills; CSA Claude Code GitHub Action note; CVE-2026-39861 (SentinelOne); CVE-2026-55607 (SecureLayer7); CVE-2026-28292 (CodeAnt); CVE-2026-21852 (SentinelOne + NVD + GHSA); Adversa deny-rules bypass.
- **Corrected during verification:** CVE-2026-33068 is more precisely a workspace trust dialog bypass via repo-controlled settings (`permissions.defaultMode`); I dropped the loose "bypassPermissions" shorthand and did not assert a single CVSS number.
- **Upgraded during verification:** Snyk ToxicSkills is stronger and more specific than the earlier "a documented malicious-agent-skills campaign" line, and the CSA note is broader than "Claude Code GitHub Action prompt injection." Both are now written with more precision.
- **Disclosed as not directly fetchable:** the two Reddit performance threads (r/ClaudeCode "performance dropped drastically" and "feels slow, frustrating and expensive") remain search-snippet-supported, as the report's method line already states.
