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

  # SIZE GATE. This function exists to avoid a jq fork, and below a few KB it does
  # — but its slicing is greedy parameter expansion over the WHOLE payload, which
  # is quadratic, while jq is flat. Measured on macOS, extracting one key:
  #
  #     payload    this      jq
  #      2.4 KB    12 ms   20 ms   <- fork-free wins
  #      6.7 KB    23 ms   17 ms   <- crossover
  #     73.9 KB  4842 ms   17 ms   <- 280x SLOWER than the fork it replaced
  #
  # safety.sh calls this up to five times per invocation, so a long Bash command
  # (a wide `prettier --write` list, a generated command) took the top security
  # hook to 19.7s at 62KB and 102s at 126KB — past the harness's 15s kill, which
  # means the guard was being killed mid-check rather than returning a verdict.
  #
  # Refusing above the crossover hands the caller back to its jq/python fallback,
  # which every caller already has. Tune with SUPERCHARGER_JSON_FAST_MAX.
  [ "${#body}" -gt "${SUPERCHARGER_JSON_FAST_MAX:-4096}" ] && return 1

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
#
# DEPTH CHECK. _json_fast_str matches a key at ANY depth — deliberate, and what
# safety.sh needs to read the nested `tool_input.command`. But these callers ask
# for TOP-LEVEL fields, and their jq filters say so (`.cwd // .workspace.current_dir`).
# Without a depth check the two disagree on a payload whose only `cwd` is nested:
#
#   {"other":{"cwd":"/nested"},"workspace":{"current_dir":"/correct"}}
#     fast path -> /nested        jq -> /correct
#
# Not reachable with Claude Code's own payload shape (these keys are top-level),
# but it is a real difference from the code this replaced, so it is closed rather
# than documented. Counting braces in the PREFIX is fork-free and cheap for a
# top-level key, because the prefix is short exactly when the answer is yes.
_json_get() { # var, key, payload, jq_filter
  local __val="" __pre __o __c
  if _json_fast_str "$2" "$3" 2>/dev/null; then
    __pre="${3%%\"$2\"*}"
    __o="${__pre//[^\{]/}"
    __c="${__pre//[^\}]/}"
    # Exactly one unclosed brace before the key == top level.
    if [ $(( ${#__o} - ${#__c} )) -eq 1 ]; then
      __val="$_JSON_FAST_VAL"
    fi
  fi
  if [ -z "$__val" ]; then
    __val=$(printf '%s\n' "$3" | jq -r "$4" 2>/dev/null || true)
    [ "$__val" = "null" ] && __val=""
  fi
  printf -v "$1" '%s' "$__val"
}
