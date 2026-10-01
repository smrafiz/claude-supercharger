#!/usr/bin/env bash
# elicitation-guard: URL-mode requests and the documented server field.
#
# Coverage diff against the Claude Code hooks reference (2026-10-01): Elicitation
# input carries `mcp_server_name`, optional `mode` and `url`. The guard read
# neither the server field (so no server could ever be trusted) nor the URL.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== elicitation-guard URL mode ==="
HOOK="$REPO_DIR/hooks/elicitation-guard.sh"

verdict() { # url [state-dir] -> decline|allow
  local st="${2:-$(mktemp -d)}"
  printf '{"hook_event_name":"Elicitation","mcp_server_name":"srv","message":"Sign in to continue","mode":"url","url":"%s"}' "$1" \
    | HOME="$st" SUPERCHARGER_STATE="$st" bash "$HOOK" 2>/dev/null | grep -q '"decline"' && echo decline || echo allow
}

begin_test "elicitation-url: an ordinary https auth link is allowed"
[ "$(verdict 'https://auth.example.com/login')" = allow ] && pass || fail "declined a normal https link"

begin_test "elicitation-url: a loopback http callback is allowed"
[ "$(verdict 'http://localhost:8080/callback')" = allow ] && pass || fail "declined a local OAuth callback"

for u in 'http://login.example.com' 'https://203.0.113.5/login' 'https://xn--pple-43d.com/' 'https://name@example.com/'; do
  begin_test "elicitation-url: declines $u"
  [ "$(verdict "$u")" = decline ] && pass || fail "allowed $u"
done

begin_test "elicitation-url: a trusted server (mcp_server_name) is not declined"
ST=$(mktemp -d); mkdir -p "$ST/scope"; printf 'srv\n' > "$ST/scope/.trusted-elicitation-servers"
[ "$(verdict 'https://203.0.113.5/login' "$ST")" = allow ] && pass || fail "trust list ignored for mcp_server_name"
rm -rf "$ST"

# The server field fix on its own: a trusted server's credential form. Before the
# fix `server` was always empty, so this was declined despite the trust entry.
begin_test "elicitation: a server trusted by mcp_server_name may request a credential field"
ST=$(mktemp -d); mkdir -p "$ST/scope"; printf 'srv\n' > "$ST/scope/.trusted-elicitation-servers"
OUT=$(printf '{"hook_event_name":"Elicitation","mcp_server_name":"srv","message":"Enter token","mode":"form","requested_schema":{"type":"object","properties":{"api_token":{"type":"string"}}}}' \
  | HOME="$ST" SUPERCHARGER_STATE="$ST" bash "$HOOK" 2>/dev/null)
rm -rf "$ST"
case "$OUT" in *decline*) fail "trusted server declined: mcp_server_name not read" ;; *) pass ;; esac

report
