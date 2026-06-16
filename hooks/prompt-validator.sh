#!/usr/bin/env bash
# Claude Supercharger — Prompt Validator Hook
# Event: UserPromptSubmit | Matcher: (none)
# Deterministic enforcement: catches obvious anti-patterns via regex.
# For soft guidance (why patterns are bad, what to ask instead), see rules/anti-patterns.yml.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-timing.sh"

_INPUT=$(cat)

# v2.6.30: one python3 fork replaces 1 jq + 1 python3 prompt extract + ~30
# separate `grep -qiE` forks (one per anti-pattern check, sometimes two for
# negative match guards). Was 70ms with all those subprocess starts; now
# ~30ms because compiled regex over a single string is essentially free
# inside python. Sync UserPromptSubmit hook — drops user-perceived input
# latency by ~40ms on every prompt.
HOOK_INPUT="$_INPUT" python3 <<'PYEOF'
import json, os, re, sys

raw = os.environ.get('HOOK_INPUT', '')
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

prompt = data.get('prompt') or ''
if not prompt:
    sys.exit(0)

I = re.IGNORECASE
notes = []

def m(pat):     return re.search(pat, prompt, I) is not None
def not_m(pat): return re.search(pat, prompt, I) is None

# 1. Vague scope
if re.search(r'^(fix|update|change|improve|make)\s+(it|this|that|the app|the code)\b', prompt, I):
    notes.append('Consider specifying which files or functions to target.')

# 2. Multiple tasks
if m(r'\b(and also|and then|plus|additionally)\b.*\b(and also|and then|plus|additionally)\b'):
    notes.append('Multiple tasks detected. Consider splitting into separate requests.')

# 3. Vague success criteria
if m(r'\b(make it better|improve|optimize|clean up)\b') and not_m(r'\b(should|must|ensure|so that|such that)\b'):
    notes.append("Consider adding success criteria (what does 'better' mean here?).")

# 4. Emotional description
if m(r'\b(totally broken|fix everything|nothing works|completely messed|everything is broken)\b'):
    notes.append('Try describing the specific error or symptom instead of the frustration.')

# 5. Build whole thing
if m(r'\b(build me a|create an entire|full app|whole application|build a complete)\b'):
    notes.append('Large scope detected. Consider breaking this into smaller, sequential requests.')

# 6. No file path
if m(r'\b(update the function|fix the component|change the method|modify the class)\b') and \
   not_m(r'(/|\.tsx?|\.jsx?|\.py|\.rs|\.go|:\d+|src/|lib/|app/)'):
    notes.append('Consider specifying the file path (e.g., src/components/Header.tsx).')

# 7. Implicit reference
if m(r'\b(the thing we discussed|what we talked about|the other thing|that thing from before)\b'):
    notes.append('Please restate what you are referring to — context may have been lost.')

# 8. Assumed prior knowledge
if m(r'\b(continue where we left off|keep going|you already know|you remember)\b'):
    notes.append('Please re-provide context — each session starts fresh.')

# 9. Vague aesthetic
if m(r'\b(make it look good|look professional|look modern|look nice|look better)\b'):
    notes.append('Consider specifying visual requirements (colors, spacing, layout, reference design).')

# 10. No audience
if m(r'\b(write for users|write documentation|write a guide|write docs)\b') and \
   not_m(r'\b(developer|beginner|technical|non-technical|admin|end user|stakeholder)\b'):
    notes.append('Consider specifying the target audience (e.g., developers, beginners, stakeholders).')

# 11. No output format specified
if m(r'\b(generate|create|produce|write|output)\b') and \
   not_m(r'\b(json|yaml|csv|markdown|html|table|list|xml|typescript|python|bash)\b') and \
   m(r'\b(report|summary|analysis|data|results|response)\b'):
    notes.append('Consider specifying output format (JSON, markdown, table, etc.).')

# 12. Implicit length
if m(r'\b(write a (long|short|brief|detailed|comprehensive|thorough))\b') and \
   not_m(r'\b([0-9]+ (words|lines|paragraphs|pages|sentences))\b'):
    notes.append('Consider specifying approximate length (e.g., 200 words, 10 lines).')

# 13. No file scope for code tasks
if m(r'\b(refactor|extract|move|rename|split|merge|inline)\b') and \
   not_m(r'(/|\.tsx?|\.jsx?|\.py|\.rs|\.go|\.java|\.rb|src/|lib/|app/|components/)'):
    notes.append('Refactoring request without file path — specify which files to modify.')

# 14. No negative constraints
if m(r'\b(rewrite|redesign|rebuild|restructure|overhaul|rearchitect)\b') and \
   not_m(r"\b(don.t|do not|must not|without|except|avoid|keep|preserve|maintain)\b"):
    notes.append('Large change without constraints — specify what to preserve or avoid changing.')

# 15. No starting state for agent tasks
if m(r'\b(set up|configure|deploy|migrate|initialize|bootstrap)\b') and \
   not_m(r'\b(currently|existing|already|right now|at the moment|from scratch|new project)\b'):
    notes.append('Setup task without starting state — clarify what exists now.')

# 16. Template mismatch (prose to code tool)
if m(r'\b(explain|describe|summarize|tell me about|what is)\b') and \
   m(r'\b(write code|implement|build|create a function)\b'):
    notes.append('Mixed intent: both explanation and implementation. Consider splitting.')

# 17. Missing role/persona
if m(r'\b(act as|pretend|you are a|behave like|roleplay)\b'):
    notes.append("Use Supercharger roles instead: 'as developer', 'as writer', etc.")

# 18. Unscoped "all" or "every"
if m(r'\b(fix all|update all|change every|modify all|refactor all|test all)\b') and \
   not_m(r'\b(in (this|the) (file|folder|directory|module|component))\b'):
    notes.append("'All' without scope — specify which files/directories.")

# 19. Version/dependency without pinning
if m(r'\b(install|add|upgrade|update)\b.*\b(latest|newest|recent)\b') and \
   not_m(r'\b(@[0-9]|==[0-9]|>=[0-9]|~[0-9]|\^[0-9]|version [0-9])\b'):
    notes.append("Consider pinning to a specific version instead of 'latest'.")

# 20. No error context
if m(r"\b(getting an error|there.s a bug|it.s broken|not working|fails|crashes)\b") and \
   not_m(r'(Error:|Exception:|Traceback|stack trace|TypeError|SyntaxError|ReferenceError|RuntimeError|KeyError|ValueError|stderr|\.log\b|line [0-9]+|at .+:[0-9]|ENOENT|EACCES|exit code|segfault|panic:)'):
    notes.append('Include the actual error message or stack trace for faster debugging.')

for n in notes:
    sys.stderr.write('[Supercharger] ' + n + '\n')
PYEOF

exit 0
