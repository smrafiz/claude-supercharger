#!/usr/bin/env bash
# Claude Supercharger — fork-free JSON string reader
#
# Hooks receive their payload as JSON on stdin and typically need one or two plain
# strings from it (`cwd`, `command`, `tool_name`, `file_path`). Doing that with `jq`
# costs ~6ms and with `python3` ~30ms — often paid BEFORE the hook's own fast-path
# exit, i.e. to decide it has nothing to do. This reads such a value with bash
# parameter expansion only: no fork.
#
# CONSERVATIVE BY CONSTRUCTION. It returns non-zero (and the caller falls back to the
# existing jq/python path) whenever it cannot be certain:
#   - the key isn't present
#   - the key appears more than once anywhere in the payload (ambiguous)
#   - the value contains ANY backslash — so every JSON escape (\" \\ \n \uXXXX)
#     leaves the fast path untouched rather than being mis-decoded
# It also requires the literal `"<key>":` form, so a key that merely ends with the
# name (`old_cwd`) cannot match, and a `\"key\":\"` sequence inside another value
# cannot match either (the backslashes break the literal).
#
# Usage:
#   . "$HOOKS_DIR/lib-json-fast.sh"
#   if _json_fast_str cwd "$_INPUT"; then CWD="$_JSON_FAST_VAL"; else CWD=$(…jq…); fi
#
# CONTRACT — the key is matched at ANY DEPTH, not just the top level. That is
# deliberate and is what the callers want: hooks read `.tool_input.command`, which
# this finds as `command`. It is safe *because* of the uniqueness rule above — if the
# name occurs more than once anywhere in the payload the function refuses, so there is
# never a question of which occurrence was taken. Do not use it for a name that could
# legitimately appear at two depths with different meanings.
#
# NOTE: only for STRING values. Numbers, booleans, nested objects are not handled.

# shellcheck disable=SC2034  # _JSON_FAST_VAL is the documented output variable
_json_fast_str() {
  local key="$1" body="$2" after rest
  _JSON_FAST_VAL=""
  [ -n "$key" ] && [ -n "$body" ] || return 1

  # The key must appear exactly once in the whole payload, else we can't be sure
  # which occurrence owns the value we're about to slice.
  rest="${body#*\"$key\"}"
  [ "$rest" = "$body" ] && return 1                 # key absent
  case "$rest" in *"\"$key\""*) return 1 ;; esac    # key again -> ambiguous

  # Accept both `"key":"v"` (compact) and `"key": "v"` (json.dumps/pretty).
  after="${rest#:}"
  [ "$after" = "$rest" ] && return 1                # not `"key":` -> not a scalar field
  after="${after#"${after%%[![:space:]]*}"}"        # ltrim spaces, fork-free
  case "$after" in \"*) after="${after#\"}" ;; *) return 1 ;; esac   # value must be a string

  _JSON_FAST_VAL="${after%%\"*}"
  # Any backslash means an escape we are not going to decode — hand back to jq/python.
  case "$_JSON_FAST_VAL" in *\\*) _JSON_FAST_VAL=""; return 1 ;; esac
  return 0
}

# v2.26.36: the standard "try fork-free, fall back to jq" wrapper. Every
# UserPromptSubmit hook re-parsed the SAME payload with its own jq fork — ~14
# forks across the chain at ~3ms each, on the path the user actually waits on
# (the gap between pressing enter and the model starting).
#
# Sets a NAMED variable rather than echoing: `X=$(_json_get …)` would fork a
# subshell and give back most of what this saves. printf -v is fork-free.
#
# The fallback is not optional — _json_fast_str deliberately refuses anything
# ambiguous or escaped, and those payloads still have to resolve correctly.
_json_get() { # var, key, payload, jq_filter
  local __val=""
  if _json_fast_str "$2" "$3" 2>/dev/null; then
    __val="$_JSON_FAST_VAL"
  else
    __val=$(printf '%s\n' "$3" | jq -r "$4" 2>/dev/null || true)
    [ "$__val" = "null" ] && __val=""
  fi
  printf -v "$1" '%s' "$__val"
}
