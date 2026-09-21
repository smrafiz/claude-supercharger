#!/usr/bin/env bash
# Every deny tells the agent who blocked it and how to proceed (v4.1.10)
#
# `permissionDecisionReason` is the ONLY part of a block the model receives. The
# `Supercharger blocked …` banner and the remediation line that hooks write to
# stderr reach the human and stop there. Measured 2026-09-17 with a subagent
# probe: the subagent got `.env file access (.env) — credentials likely present`
# and nothing else — no attribution, no way through. An agent that cannot
# distinguish a policy block from a shell error retries blindly, which is the
# behaviour the guard exists to prevent.
#
# Two kinds of assertion here, and the second is the one that keeps this true:
#   - behavioural: a guard given a blocking payload emits an attributed reason
#   - structural: NO hook emits a decision without going through the helper
# The structural one is what stops the next hook from reintroducing the shape.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Deny attribution ==="

. "$REPO_DIR/hooks/lib-deny.sh"

reason_of() { # json -> the reason string, via a real parser
  # newline='' is load-bearing on Git Bash. Python's text-mode stdout translates
  # an embedded \n to \r\n there, so a reason containing a newline came back
  # with a \r the expected string did not have, and the comparison failed while
  # the VALUE was correct. Windows CI caught it; macOS and Linux cannot.
  python3 -c 'import json,sys
sys.stdout.reconfigure(newline="")
try: print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecisionReason"])
except Exception: pass'
}

begin_test "a deny names Supercharger, so the agent knows it is policy"
OUT=$(sc_decision deny "reading that file is blocked" | reason_of)
case "$OUT" in "Supercharger: reading that file is blocked"*) pass ;; *) fail "got: $OUT" ;; esac

begin_test "a remedy is carried through when the caller gives one"
OUT=$(sc_decision deny "blocked" "run it in your terminal" | reason_of)
case "$OUT" in *"Way through: run it in your terminal") pass ;; *) fail "got: $OUT" ;; esac

begin_test "no remedy means no dangling label"
OUT=$(sc_decision deny "blocked" | reason_of)
case "$OUT" in *"Way through"*) fail "empty remedy still emitted a label: $OUT" ;; *) pass ;; esac

# Escaping is pure bash, so it is the part most worth attacking. A reason is
# built from user-supplied paths and commands, which carry all of these.
begin_test "quotes and backslashes survive as valid JSON"
OUT=$(sc_decision deny 'read of "/tmp/a b\c" blocked' | reason_of)
[ "$OUT" = 'Supercharger: read of "/tmp/a b\c" blocked' ] && pass || fail "got: $OUT"

begin_test "newlines and tabs do not break the JSON"
OUT=$(sc_decision deny "$(printf 'line1\nline2\tend')" | reason_of)
[ "$OUT" = "$(printf 'Supercharger: line1\nline2\tend')" ] && pass || fail "got: $OUT"

begin_test "control bytes are dropped rather than emitted raw"
OUT=$(sc_decision deny "$(printf 'a\001\002b')" | reason_of)
[ "$OUT" = "Supercharger: ab" ] && pass || fail "got: $OUT"

begin_test "an ask is emitted as ask, not as a block"
OUT=$(sc_decision ask "confirm this" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"])')
[ "$OUT" = "ask" ] && pass || fail "got: $OUT"

# --- behavioural: real guards, real payloads ---------------------------------
guard_reason() { # hook, tool, json-input -> reason string
  local st; st=$(mktemp -d); mkdir -p "$st/scope"
  TOOL="$2" TI="$3" ST="$st" python3 -c '
import json, os
print(json.dumps({"tool_name": os.environ["TOOL"],
                  "tool_input": json.loads(os.environ["TI"]),
                  "cwd": os.environ["ST"]}))' \
    | env HOME="$st" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$1" 2>/dev/null | reason_of
  rm -rf "$st"
}

begin_test "safety.sh attributes a real block"
R=$(guard_reason safety.sh Bash '{"command":"rm -rf /"}')
case "$R" in "Supercharger: "*) pass ;; *) fail "unattributed: $R" ;; esac

begin_test "git-safety.sh attributes a force push"
R=$(guard_reason git-safety.sh Bash '{"command":"git push --force origin master"}')
case "$R" in "Supercharger: "*) pass ;; *) fail "unattributed: $R" ;; esac

E="."'env'
begin_test "the credential guard attributes and names the way through"
R=$(guard_reason env-file-guard.sh Read "$(printf '{"file_path":"/srv/app/%s"}' "$E")")
case "$R" in "Supercharger: "*"Way through:"*) pass ;; *) fail "missing attribution or remedy: $R" ;; esac

# --- structural: the convention cannot rot silently --------------------------
begin_test "no hook emits ANY decision outside the helper"
# Widened from deny-only once the ask sites moved (v4.1.10). lib-stdin.sh is the
# single documented exemption: its ask fires when stdin could not be read at all,
# which is exactly the moment a hook cannot depend on another lib having loaded.
OFFENDERS=$(grep -ln '"permissionDecision":"\(deny\|ask\)"' "$REPO_DIR"/hooks/*.sh 2>/dev/null \
            | grep -vE '(lib-deny|lib-stdin)\.sh$' || true)
[ -z "$OFFENDERS" ] && pass || fail "raw decision emitters: $(printf '%s' "$OFFENDERS" | tr '\n' ' ')"

begin_test "an ask carries attribution too, not just a deny"
# Empty is NOT a pass here. The first draft of this accepted "", which would
# have gone green if the guard never fired — the vacuous shape this repo keeps
# finding in its own instruments. The path must sit under the fixture dir or
# critical-infra-guard correctly ignores it.
ASK_ST=$(mktemp -d); mkdir -p "$ASK_ST/scope"
R=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/.github/workflows/ci.yml","new_string":"x"},"cwd":"%s"}' "$ASK_ST" "$ASK_ST" \
    | env HOME="$ASK_ST" SUPERCHARGER_STATE="$ASK_ST" bash "$REPO_DIR/hooks/critical-infra-guard.sh" 2>/dev/null | reason_of)
rm -rf "$ASK_ST"
case "$R" in
  "Supercharger: "*"Way through:"*) pass ;;
  "") fail "the ask never fired — fixture does not exercise the guard" ;;
  *) fail "unattributed ask: $R" ;;
esac

report
