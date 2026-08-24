#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/tool-preferences.sh"

echo "=== tool-preferences Tests ==="

export SUPERCHARGER_NO_DEDUP=1

begin_test "tool-preferences: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "tool-preferences: no .supercharger.json → silent allow"
PROJ=$(mktemp -d)
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow without config, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: blocks npm with pnpm suggestion"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install react"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && echo "$OUT" | grep -q 'pnpm' && pass || fail "expected deny + pnpm suggestion, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: allows preferred tool (pnpm)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"pnpm install react"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent allow for pnpm, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: handles env var prefix (FOO=bar npm install)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"NODE_ENV=production npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected deny with env prefix, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: catches npx wrapper (npx jest → suggest vitest)"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"jest":"vitest"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npx jest --watch"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q 'vitest' && pass || fail "expected vitest suggestion via npx, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: SUPERCHARGER_TOOL_PREFS=0 disables hook"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(SUPERCHARGER_TOOL_PREFS=0 bash -c "echo '$INPUT' | bash $HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected disabled output, got: $OUT"
rm -rf "$PROJ"

begin_test "tool-preferences: skips non-Bash tools"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"%s/foo.ts"},"cwd":"%s"}' "$PROJ" "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected silent on Edit, got: $OUT"
rm -rf "$PROJ"

# --- v2.29.16: Monitor was registered on this hook (v2.29.7) but the internal
# TOOL_NAME gate still hard-exited unless TOOL_NAME=="Bash" exactly, so the
# registration did nothing for two releases. Verified live before fixing: an
# npm command routed through Monitor produced no suggestion while the identical
# Bash command did. ---
begin_test "tool-preferences: Monitor gets the same toolPreferences coverage as Bash"
PROJ=$(mktemp -d)
echo '{"toolPreferences":{"npm":"pnpm"}}' > "$PROJ/.supercharger.json"
INPUT=$(printf '{"tool_name":"Monitor","tool_input":{"command":"npm install"},"cwd":"%s"}' "$PROJ")
OUT=$(echo "$INPUT" | bash "$HOOK" 2>/dev/null)
echo "$OUT" | grep -q '"permissionDecision":"deny"' && pass || fail "Monitor did not get a suggestion: $OUT"
rm -rf "$PROJ"

# --- preferGhCli (v2.29.16): opt-in GitHub curl/wget/WebFetch redirect to gh ---
_tp_gh_decide() {  # $1=tool_name $2=tool_input-json $3=config-json $4=path-override(optional)
  local proj out
  proj=$(mktemp -d)
  printf '%s' "$3" > "$proj/.supercharger.json"
  out=$(printf '{"tool_name":"%s","tool_input":%s,"cwd":"%s"}' "$1" "$2" "$proj" \
    | env ${4:+PATH="$4"} bash "$HOOK" 2>/dev/null)
  rm -rf "$proj"
  if [ -z "$out" ]; then echo "passthrough"
  elif echo "$out" | grep -q '"permissionDecision":"deny"'; then echo "deny"
  else echo "other"; fi
}

begin_test "preferGhCli: off by default — curl to GitHub API passes through"
[ "$(_tp_gh_decide Bash '{"command":"curl https://api.github.com/repos/foo/bar/pulls"}' '{}')" = "passthrough" ] && pass || fail "should pass through with no config"

begin_test "preferGhCli: on — curl to GitHub API is denied with a gh suggestion"
R=$(_tp_gh_decide Bash '{"command":"curl https://api.github.com/repos/foo/bar/pulls"}' '{"preferGhCli":true}')
[ "$R" = "deny" ] && pass || fail "expected deny, got $R"

begin_test "preferGhCli: on — curl to a non-GitHub host still passes through"
R=$(_tp_gh_decide Bash '{"command":"curl https://example.com/data.json"}' '{"preferGhCli":true}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough for a non-GitHub host, got $R"

begin_test "preferGhCli: on — WebFetch to a github.com PR URL is denied"
R=$(_tp_gh_decide WebFetch '{"url":"https://github.com/foo/bar/pull/42"}' '{"preferGhCli":true}')
[ "$R" = "deny" ] && pass || fail "expected deny, got $R"

begin_test "preferGhCli: on — WebFetch to a non-GitHub URL passes through"
R=$(_tp_gh_decide WebFetch '{"url":"https://example.com/docs"}' '{"preferGhCli":true}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough, got $R"

begin_test "preferGhCli: on — Monitor curl to GitHub is denied (same channel as Bash)"
R=$(_tp_gh_decide Monitor '{"command":"curl https://github.com/foo/bar/archive/refs/heads/main.zip"}' '{"preferGhCli":true}')
[ "$R" = "deny" ] && pass || fail "expected deny, got $R"

begin_test "preferGhCli: raw.githubusercontent.com suggests clone, not gh api base64-decode"
PROJ=$(mktemp -d); echo '{"preferGhCli":true}' > "$PROJ/.supercharger.json"
OUT=$(printf '{"tool_name":"WebFetch","tool_input":{"url":"https://raw.githubusercontent.com/foo/bar/main/README.md"},"cwd":"%s"}' "$PROJ" | bash "$HOOK" 2>/dev/null)
rm -rf "$PROJ"
echo "$OUT" | grep -q 'gh repo clone foo/bar' && pass || fail "expected a clone suggestion: $OUT"

begin_test "preferGhCli: fails open when gh is not on PATH"
R=$(_tp_gh_decide Bash '{"command":"curl https://api.github.com/repos/foo/bar/pulls"}' '{"preferGhCli":true}' "/usr/bin:/bin")
[ "$R" = "passthrough" ] && pass || fail "expected passthrough without gh installed, got $R"

begin_test "preferGhCli: an unrelated Bash command is untouched"
R=$(_tp_gh_decide Bash '{"command":"echo hello"}' '{"preferGhCli":true}')
[ "$R" = "passthrough" ] && pass || fail "expected passthrough, got $R"


report
