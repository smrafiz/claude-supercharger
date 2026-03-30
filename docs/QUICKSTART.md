# Quick Start Guide

Get Claude Supercharger v1.0.0 running in 5 minutes.

---

## 1. Install (30 seconds)

```bash
curl -fsSL https://raw.githubusercontent.com/smrafiz/claude-supercharger/main/install.sh | bash
```

Or manually:

```bash
git clone https://github.com/smrafiz/claude-supercharger.git
cd claude-supercharger
bash install.sh
```

**Have existing configuration?** Use merge mode:

```bash
bash merge.sh  # Preserves your config + adds Supercharger features
```

See [MIGRATION.md](MIGRATION.md) for manual cherry-picking.

---

## 2. Verify Installation (10 seconds)

```bash
grep "Claude Supercharger v1.0.0" ~/.claude/RULES.md
# Should output: *Claude Supercharger v1.0.0 | C=CRITICAL H=HIGH M=MEDIUM | Optimized ops rules + Prompt Master integration*
```

---

## 3. Test Anti-Pattern Detection (1 minute)

**Try this vague request:**

```
You: "fix the bug"
```

**Claude Supercharger detects "vague scope" anti-pattern** and asks:
- Which file/function contains the bug?
- What is the symptom/error message?

---

## 4. Test Memory Block (1 minute)

**First request:**

```
You: "create a login component using JWT in httpOnly cookies"
```

**Second request:**

```
You: "now create logout using the same pattern"
```

**Claude Supercharger prepends Memory Block:**

```
## Context (carry forward)
- Stack: React 18, TypeScript
- Auth pattern: JWT in httpOnly cookie
- Component location: src/components/auth/
```

---

## 5. Test Verification Gate (1 minute)

**Make a change, then:**

```
You: "verify this is done correctly"
```

**Claude Supercharger checks 10 items:**
- ✓ TypeScript compilation passes
- ✓ Tests pass
- ✓ No debug code left
- ✓ Imports resolve
- ✓ Constraints preserved
- ✓ Binary success criteria met

---

## 6. Use Personas (30 seconds)

Activate personas through natural language:

```
You: "load the frontend persona"
→ Frontend persona active (UX-first, mobile-first)

You: "load the security persona"
→ Security persona active (threat modeling, defense-in-depth)

You: "switch to architect persona"
You: "As performance: optimize this"
```

**9 available:** architect, frontend, backend, analyzer, security, mentor, refactorer, performance, qa

---

## What's Happening Behind the Scenes?

When you make a request, Claude Supercharger follows this 8-step workflow:

1. **Anti-Pattern Detection** → Scans for 35 patterns
2. **Ambiguity Resolution** → Detects unclear elements
3. **Intent Extraction** → 9-dimension analysis, max 3 questions
4. **Session Awareness** → Tracks context implicitly
5. **Memory Block** → Prepends explicit context if multi-turn
6. **Execute Task** → Uses appropriate tools
7. **Pre-Delivery Verification** → 10-point quality gate
8. **Output Lock** → Deliverable + optimization note

**Simple requests skip to step 6.**

---

## Next Steps

- Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand how it works
- Read [CUSTOMIZATION.md](CUSTOMIZATION.md) to tailor to your needs
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if you hit issues

---

## Uninstall

```bash
cd claude-supercharger
bash uninstall.sh
```
