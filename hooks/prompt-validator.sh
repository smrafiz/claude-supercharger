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

if [ -n "$NOTES" ]; then
  echo -e "$NOTES" >&2
fi

exit 0
