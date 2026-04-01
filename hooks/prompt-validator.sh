#!/usr/bin/env bash
# Claude Supercharger — Prompt Validator Hook
# Event: UserPromptSubmit | Matcher: (none)
# Deterministic enforcement: catches obvious anti-patterns via regex.
# For soft guidance (why patterns are bad, what to ask instead), see rules/anti-patterns.yml.

set -euo pipefail

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('prompt',''))" 2>/dev/null || echo "")

if [ -z "$PROMPT" ]; then
  exit 0
fi

NOTES=""

# 1. Vague scope
if echo "$PROMPT" | grep -qiE '^(fix|update|change|improve|make)\s+(it|this|that|the app|the code)\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying which files or functions to target.\n"
fi

# 2. Multiple tasks
if echo "$PROMPT" | grep -qiE '\b(and also|and then|plus|additionally)\b.*\b(and also|and then|plus|additionally)\b'; then
  NOTES="${NOTES}[Supercharger] Multiple tasks detected. Consider splitting into separate requests.\n"
fi

# 3. Vague success criteria
if echo "$PROMPT" | grep -qiE '\b(make it better|improve|optimize|clean up)\b' && ! echo "$PROMPT" | grep -qiE '\b(should|must|ensure|so that|such that)\b'; then
  NOTES="${NOTES}[Supercharger] Consider adding success criteria (what does 'better' mean here?).\n"
fi

# 4. Emotional description
if echo "$PROMPT" | grep -qiE '\b(totally broken|fix everything|nothing works|completely messed|everything is broken)\b'; then
  NOTES="${NOTES}[Supercharger] Try describing the specific error or symptom instead of the frustration.\n"
fi

# 5. Build whole thing
if echo "$PROMPT" | grep -qiE '\b(build me a|create an entire|full app|whole application|build a complete)\b'; then
  NOTES="${NOTES}[Supercharger] Large scope detected. Consider breaking this into smaller, sequential requests.\n"
fi

# 6. No file path
if echo "$PROMPT" | grep -qiE '\b(update the function|fix the component|change the method|modify the class)\b' && ! echo "$PROMPT" | grep -qiE '(/|\.tsx?|\.jsx?|\.py|\.rs|\.go|:\d+|src/|lib/|app/)'; then
  NOTES="${NOTES}[Supercharger] Consider specifying the file path (e.g., src/components/Header.tsx).\n"
fi

# 7. Implicit reference
if echo "$PROMPT" | grep -qiE '\b(the thing we discussed|what we talked about|the other thing|that thing from before)\b'; then
  NOTES="${NOTES}[Supercharger] Please restate what you are referring to — context may have been lost.\n"
fi

# 8. Assumed prior knowledge
if echo "$PROMPT" | grep -qiE '\b(continue where we left off|keep going|you already know|you remember)\b'; then
  NOTES="${NOTES}[Supercharger] Please re-provide context — each session starts fresh.\n"
fi

# 9. Vague aesthetic
if echo "$PROMPT" | grep -qiE '\b(make it look good|look professional|look modern|look nice|look better)\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying visual requirements (colors, spacing, layout, reference design).\n"
fi

# 10. No audience
if echo "$PROMPT" | grep -qiE '\b(write for users|write documentation|write a guide|write docs)\b' && ! echo "$PROMPT" | grep -qiE '\b(developer|beginner|technical|non-technical|admin|end user|stakeholder)\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying the target audience (e.g., developers, beginners, stakeholders).\n"
fi

# 11. No output format specified
if echo "$PROMPT" | grep -qiE '\b(generate|create|produce|write|output)\b' && ! echo "$PROMPT" | grep -qiE '\b(json|yaml|csv|markdown|html|table|list|xml|typescript|python|bash)\b'; then
  if echo "$PROMPT" | grep -qiE '\b(report|summary|analysis|data|results|response)\b'; then
    NOTES="${NOTES}[Supercharger] Consider specifying output format (JSON, markdown, table, etc.).\n"
  fi
fi

# 12. Implicit length
if echo "$PROMPT" | grep -qiE '\b(write a (long|short|brief|detailed|comprehensive|thorough))\b' && ! echo "$PROMPT" | grep -qiE '\b([0-9]+ (words|lines|paragraphs|pages|sentences))\b'; then
  NOTES="${NOTES}[Supercharger] Consider specifying approximate length (e.g., 200 words, 10 lines).\n"
fi

# 13. No file scope for code tasks
if echo "$PROMPT" | grep -qiE '\b(refactor|extract|move|rename|split|merge|inline)\b' && ! echo "$PROMPT" | grep -qiE '(/|\.tsx?|\.jsx?|\.py|\.rs|\.go|\.java|\.rb|src/|lib/|app/|components/)'; then
  NOTES="${NOTES}[Supercharger] Refactoring request without file path — specify which files to modify.\n"
fi

# 14. No negative constraints
if echo "$PROMPT" | grep -qiE '\b(rewrite|redesign|rebuild|restructure|overhaul|rearchitect)\b' && ! echo "$PROMPT" | grep -qiE '\b(don.t|do not|must not|without|except|avoid|keep|preserve|maintain)\b'; then
  NOTES="${NOTES}[Supercharger] Large change without constraints — specify what to preserve or avoid changing.\n"
fi

# 15. No starting state for agent tasks
if echo "$PROMPT" | grep -qiE '\b(set up|configure|deploy|migrate|initialize|bootstrap)\b' && ! echo "$PROMPT" | grep -qiE '\b(currently|existing|already|right now|at the moment|from scratch|new project)\b'; then
  NOTES="${NOTES}[Supercharger] Setup task without starting state — clarify what exists now.\n"
fi

# 16. Template mismatch (prose to code tool)
if echo "$PROMPT" | grep -qiE '\b(explain|describe|summarize|tell me about|what is)\b' && echo "$PROMPT" | grep -qiE '\b(write code|implement|build|create a function)\b'; then
  NOTES="${NOTES}[Supercharger] Mixed intent: both explanation and implementation. Consider splitting.\n"
fi

# 17. Missing role/persona
if echo "$PROMPT" | grep -qiE '\b(act as|pretend|you are a|behave like|roleplay)\b'; then
  NOTES="${NOTES}[Supercharger] Use Supercharger roles instead: 'as developer', 'as writer', etc.\n"
fi

# 18. Unscoped "all" or "every"
if echo "$PROMPT" | grep -qiE '\b(fix all|update all|change every|modify all|refactor all|test all)\b' && ! echo "$PROMPT" | grep -qiE '\b(in (this|the) (file|folder|directory|module|component))\b'; then
  NOTES="${NOTES}[Supercharger] 'All' without scope — specify which files/directories.\n"
fi

# 19. Version/dependency without pinning
if echo "$PROMPT" | grep -qiE '\b(install|add|upgrade|update)\b.*\b(latest|newest|recent)\b' && ! echo "$PROMPT" | grep -qiE '\b(@[0-9]|==[0-9]|>=[0-9]|~[0-9]|\^[0-9]|version [0-9])\b'; then
  NOTES="${NOTES}[Supercharger] Consider pinning to a specific version instead of 'latest'.\n"
fi

# 20. No error context
if echo "$PROMPT" | grep -qiE '\b(getting an error|there.s a bug|it.s broken|not working|fails|crashes)\b' && ! echo "$PROMPT" | grep -qiE '(Error:|Exception:|Traceback|stack trace|TypeError|SyntaxError|ReferenceError|RuntimeError|KeyError|ValueError|stderr|\.log\b|line [0-9]+|at .+:[0-9]|ENOENT|EACCES|exit code|segfault|panic:)'; then
  NOTES="${NOTES}[Supercharger] Include the actual error message or stack trace for faster debugging.\n"
fi

if [ -n "$NOTES" ]; then
  echo -e "$NOTES" >&2
fi

exit 0
