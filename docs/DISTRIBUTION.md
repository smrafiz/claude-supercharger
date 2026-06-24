# Claude Supercharger — Distribution & Marketing Playbook

Internal launch plan for getting Supercharger in front of Claude Code users. Not user-facing docs — gitignore if you don't want it public.

**Status:** v2.6.82 shipped. 1018 tests passing. Production-ready but underleveraged. Goal: 10× stars in 90 days.

---

## Objectives

| Metric | 30-day target | 90-day target |
|---|---|---|
| GitHub stars | +200 | +2000 |
| Marketplace installs | +50 | +500 |
| Awesome-cc card position | top 10 | featured |
| Issues opened by non-maintainer users | 5+ | 30+ |
| Inbound feature requests | 3+ | 20+ |

If you don't hit 30-day targets, the messaging isn't landing — iterate before pushing harder.

---

## Phase 0 — Repo hygiene (do FIRST, ~30 min)

Pre-distribution polish. Without this, posts will land but drop-off rate is high.

### 0.1 Repo description + topics

```bash
gh repo edit smrafiz/claude-supercharger \
  --description "Shell-level guardrails for Claude Code — command blocking, token economy, agent routing, MCP profiles, session memory. Zero context cost." \
  --add-topic claude-code --add-topic hooks --add-topic safety \
  --add-topic guardrails --add-topic mcp --add-topic agentic-engineering \
  --add-topic ai-safety --add-topic shell
```

### 0.2 README hero section

Top 5 lines decide whether a visitor scrolls. Check:
- One-line value prop (already strong: "Shell-level enforcement... invisible to the model")
- Demo GIF visible above-the-fold (already shipped v2.6.68)
- Three-bullet "What you get" list
- One-line install command, copy-paste safe
- Star count + tests badge

### 0.3 Pin the demo GIF

GitHub doesn't auto-play GIFs in social cards. Add an .mp4 or .webm version for X/LinkedIn previews. Same content, different file.

### 0.4 CODE_OF_CONDUCT.md + CONTRIBUTING.md

Quick stubs. Project looks abandoned without them. Use GitHub's default templates — copy verbatim.

### 0.5 Pinned issue: "Roadmap"

Pin one issue titled "v2.7 Roadmap — feedback wanted". Lists ~5 next-feature ideas with reactions enabled. Surfaces engagement signals and gives first-time visitors something to interact with beyond starring.

### 0.6 GitHub Releases

You've been tagging (v2.6.82 just landed). Make sure each tag has a release with the CHANGELOG entry as the body. `gh release create v2.6.82 --notes-from-tag` if not auto-published.

---

## Phase 1 — Warm channels (low-risk, do BEFORE cold)

Burn these first so the cold launches have early momentum.

### 1.1 Friends & immediate network

DM 5-10 people personally with: link, 2-line context, ask for star. Not for upvotes — for genuine first-look feedback. Use what you learn to refine messaging before paid attention.

### 1.2 awesome-claude-code card update (issue #2096)

Already submitted, validation-passed. Comment on the issue with:
- v2.6.82 changelog highlights
- Test count 1018
- Quote a real bug we caught (the rm -rf project-wipe incident is your best story)
- Ask maintainer to bump card prominence

Don't open a new issue. Reply on #2096.

### 1.3 Anthropic Discord / community

Find the Anthropic Discord or Claude Code-specific channels. Post in the #showcase or equivalent. Tone: peer engineer sharing a tool, not vendor pitching. Lead with the rm -rf incident.

---

## Phase 2 — Cold launch (high-leverage, do all in one week)

Sequence matters: HN first (highest reach, hardest to time), then Reddit (warm), then X (sustained).

### 2.1 HN Show

**Platform:** https://news.ycombinator.com/submit
**Best time:** Tue/Wed 8-10am Pacific
**URL field:** repo link
**Title:** `Show HN: Claude Supercharger – shell-level guardrails for Claude Code`

**Critical first comment** (paste within 60 seconds of submit):

```
Author here. Built this after Claude wiped a project of mine with `rm -rf /Users/.../creative-shapes-theme` on a CC v2.1.176 bug where PreToolUse:Bash hooks silently stopped firing (filed as anthropics/claude-code#69970).

Supercharger runs ~99 shell hooks outside Claude's process. The model can't see them, can't prompt-engineer around them. They block destructive commands, scan tool output for secrets, manage token economy tiers, route prompts to named agents, etc.

Three things that make it different from "safer prompt" approaches:
1. Zero context-window cost — rules live in shell, not your prompt
2. Hard-deny at exit 2, not advisory — physically can't run blocked commands
3. Self-teaching on user corrections — fewer repeated mistakes

What I'd love feedback on: the fuzz harness in tests/fuzz-safety.sh just caught 3 bypasses I'd missed (env-var prefix, ${HOME} braced form, credential-in-env-var). Curious what other shapes you'd try.

Repo: <link>
```

**Launch checklist:**
- Post account has karma (HN sandboxes new accounts)
- 3-5 friends ready to upvote at staggered times in first 30 min (NOT immediately — looks like vote ring)
- Stay online for 4h after submit to reply fast
- Front-page hits need ~10 upvotes in first 30 min

**If it doesn't make front page:** don't repost. Wait 2 weeks, try a different angle (e.g. "Show HN: I fuzz-tested my own Claude Code safety layer and found 3 bypasses").

### 2.2 Reddit r/ClaudeAI (same day as HN)

**Title:** `I built shell-level guardrails for Claude Code (100+ hooks, blocks rm -rf, force-push, secret leaks)`

**Body template:**

```markdown
**Problem:** Claude Code with auto-approve mode is fast but scary. A bug or
prompt injection can wipe your project. Safety-mode prompts don't help —
the model can ignore them.

**Solution:** Shell hooks running outside Claude's process. They intercept
tool calls BEFORE execution. The model can't see them, can't override them,
can't prompt-engineer around them.

**What it catches:**
- rm -rf /, ~, $PWD, $(pwd) and variants
- git push --force to main/master
- credentials in commands (AWS, GitHub PAT, OpenAI keys, etc)
- shell escapes (! prefix in CC prompts)
- subagent permission grants (CC v2.1.186 surfacing change)
- 90+ more patterns

**Bonus features:**
- token economy (lean/standard/minimal tiers)
- 9 agent personas with auto-routing
- MCP profile management
- session memory persistence

**The story:** Built it after CC wiped my project on a silent hook
regression (filed #69970). Now ships 1018 tests + fuzz harness.

GIF demo + repo: <link>

Open to feedback on what else to block.
```

**Cross-post:** r/programming (highest reach but stricter mods), r/devops (warm), r/MachineLearning (skip — wrong audience).

### 2.3 X/Twitter thread (1-day delay after HN)

5-7 tweet thread. Lead with story, not features.

**Tweet 1 (hook):**
```
A few weeks ago Claude Code ran `rm -rf <project>` on me.

PreToolUse:Bash hooks silently stopped firing in v2.1.176 (filed #69970).
The whole project: gone.

So I built shell-level guardrails that the model can't see and can't override. 🧵
```

**Tweet 2:** the architecture diagram (model → CC → shell hook → tool). Picture > words.

**Tweet 3:** specific blocks — rm -rf, force-push, secret-leak. Screenshot of a real block message.

**Tweet 4:** the v2.1.186 subagent return-channel bug — 80-tool subagent reports lost to "Ready.". Show the workaround we built.

**Tweet 5:** zero-context-cost claim. The competitive frame vs prompt-based safety.

**Tweet 6:** install command + link + tests/stars badges.

**Tweet 7 (CTA):** "What's the worst Claude Code disaster you've seen? Drop them — I'll write hooks for them."

Tag @AnthropicAI sparingly. Pin to profile for 1 week. Reply to every comment.

### 2.4 Dev.to / Hashnode blog post (1 week after launch)

Long-form: "How I built shell-level guardrails for Claude Code after it deleted my project."

~1500 words. Story-led. Include code snippets. Link to repo at the end, NOT the start.

Cross-publish to:
- dev.to
- hashnode (your own subdomain)
- LinkedIn Article (if you have a presence)
- Medium (lowest priority)

### 2.5 Product Hunt (optional, 2 weeks out)

Only if HN+Reddit landed. Product Hunt rewards polish (logo, screenshots, tagline) more than substance.

**Tagline:** "Shell-level safety for Claude Code"
**Description:** 2 paragraphs max
**Gallery:** 4-5 screenshots, demo GIF
**First comment:** maker intro, same shape as HN comment

Launch on Tue/Wed 12am PT. Top-5-of-day needs ~200 upvotes.

---

## Phase 3 — Sustained presence (ongoing)

### 3.1 Issue/PR engagement

Reply to every issue within 24h. Even "thanks, looking into this" beats silence. Conversion: lurkers → contributors.

### 3.2 Weekly changelog tweets

Every Friday post a 1-tweet "shipped this week" recap. Even if quiet, post the test count. Consistency > volume.

### 3.3 Comparison posts

Write 1 comparison piece every 2-3 weeks:
- vs CC built-in safety
- vs SuperClaude_Framework
- vs claude-code-best-practice
- vs prompt-based "Don't do X" approaches

Honest, with credit. Don't bash competitors.

### 3.4 Bug-public PR storytelling

When you fix a bug, write a 3-tweet thread: shape of bug → why our hook caught (or didn't) → fix. The fuzz harness landing v2.6.81 was perfect material — didn't capitalize.

---

## Content templates (copy-paste-ready)

### Twitter bio addition
```
Builder of @ClaudeSupercharger — shell-level guardrails for Claude Code
```

### Email signature line
```
ps. I built Claude Supercharger — guardrails for Claude Code: <link>
```

### Hacker News profile "about"
```
Built Claude Supercharger (claude-supercharger on GitHub) — shell-level
hooks for Claude Code that block destructive commands the model can't see.
```

### One-line repo description (use everywhere)
```
Shell-level guardrails for Claude Code — command blocking, token economy,
agent routing, MCP profiles, session memory. Zero context cost.
```

### Two-paragraph elevator (for PMs/CTOs)
```
Claude Supercharger is shell-level safety for Claude Code. It runs ~99
hooks outside Claude's process — so the model can't see them, can't
prompt-engineer around them, and can't override them. It blocks `rm -rf`,
force-push, credential leaks, prompt injection from tool output, and 90+
other patterns.

Unlike prompt-based "be careful" approaches, Supercharger costs zero
context tokens (rules live in shell) and physically prevents the dangerous
action (exit 2 deny, not advisory). 1018 tests, MIT licensed, runs on
macOS + Linux. Ships as a one-line install or a Claude Code plugin.
```

---

## Metrics to track

Set up a weekly review. 15 minutes.

| Metric | Source | Why |
|---|---|---|
| Stars/week | github.com/smrafiz/claude-supercharger/graphs | leading indicator |
| Clones/week | repo Insights → Traffic | who's installing |
| Unique visitors | repo Insights → Traffic | brand awareness |
| Issue open rate | issues tab | engagement quality |
| Plugin installs | marketplace.json telemetry | actual usage |
| Referrer mix | Insights → Traffic → Referring sites | which channels work |

Drop channels with bad ROI after 2 attempts. Double down on the 1-2 that bring qualified users.

---

## Don'ts

- **Don't fake upvotes.** HN/Reddit detect rings via account age, IP, timing. One ring kills the submission and shadowbans the account.
- **Don't post the same content same-day across 5+ subreddits.** Mods will flag as spam. Stagger 24h between cross-posts.
- **Don't tag Anthropic employees on personal accounts.** Use @AnthropicAI handle or relevant @-mentions only. Cold @-ing engineers reads as begging.
- **Don't compare unfairly.** "X is bad, mine is good" loses respect. "X handles Y, we handle Z" wins it.
- **Don't promise features you haven't built.** Roadmap = signals interest. Commitment = future user disappointment.
- **Don't reply defensively to criticism.** Even bad-faith critics surface real concerns the polite ones won't.
- **Don't burn out.** This is a 90-day campaign, not a 1-week sprint. Pick 3 channels you'll sustain, not 10 you'll abandon.

---

## Timeline (suggested 30-day plan)

| Day | Action |
|---|---|
| 1 | Phase 0 (repo hygiene) + Phase 1.1 (DM friends) |
| 2 | Phase 1.2 (awesome-cc ping) + Phase 1.3 (Discord) |
| 3-6 | Wait. Let warm-channel feedback land. |
| 7 (Tue) | HN Show submit + reply window |
| 7 (Tue PM) | r/ClaudeAI post |
| 8 (Wed) | r/programming post (if r/ClaudeAI traction) |
| 9 (Thu) | X thread |
| 10-13 | Reply to all incoming, fix friction issues |
| 14 | Blog post drafted |
| 15-21 | Blog cross-published, weekly tweets resume |
| 22 | Comparison post #1 |
| 28-30 | Review metrics, adjust for month 2 |

---

## When to stop

If after 30 days:
- HN didn't front-page AND
- Reddit posts averaged <50 upvotes AND
- Stars/week <10 sustained

Then either:
1. The product hits a real but narrow audience (early CC adopters) — accept the ceiling and ship features for them
2. The messaging is wrong — rewrite README hero + retry in 60 days
3. The market isn't ready — CC ecosystem is too young, wait 90 days, retry

Don't keep posting the same thing harder. Diagnose, adjust, retry.
