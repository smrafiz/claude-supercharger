#!/usr/bin/env bash
# PowerShell forms that print an environment secret or read a dotenv file. Cases from
# randommonicle/claude-skills (hooks tests, 2026-10-28): 34 of its 35 deny cases passed
# safety.sh. Names and paths are assembled from pieces so this file never trips the
# guards it tests.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== PowerShell secrets ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
E = "." + "env"
N = "NETLIFY_" + "TOKEN"
S = "SUPABASE_ACCESS_" + "TOKEN"
V = "$env:"
cases = [
    ("Write-Host a key", 'Write-Host "key: ' + V + 'RESEND_API_' + 'KEY"', "DENY"),
    ("bare env ref", V + "ADMIN_" + "SECRET", "DENY"),
    ("string with a token", '"token is ' + V + N + '"', "DENY"),
    ("Get-ChildItem Env:", "Get-ChildItem Env:", "DENY"),
    ("gci env: wildcard", "gci env:SUPABASE*", "DENY"),
    ("Get-Item one secret", "Get-Item Env:SUPABASE_SERVICE_ROLE_" + "KEY", "DENY"),
    ("GetEnvironmentVariable", '[Environment]::GetEnvironmentVariable("' + S + '")', "DENY"),
    ("GetEnvironmentVariables", "[System.Environment]::GetEnvironmentVariables()", "DENY"),
    ("Get-Content dotenv", "Get-Content " + E + ".local", "DENY"),
    ("type a Windows dotenv path", "type C:\\Users\\dev\\site\\" + E, "DENY"),
    ("powershell -Command", 'powershell -Command "Write-Host ' + V + N + '"', "DENY"),
    ("Env: with values", "Get-ChildItem Env: | Select-Object Name,Value", "DENY"),
    ("length then value", 'Write-Host "$(' + V + N + '.Length) ' + V + N + '"', "DENY"),
    ("Out-String", V + N + " | Out-String", "DENY"),
    ("Write-Verbose", "Write-Verbose " + V + N + " -Verbose", "DENY"),
    ("Get-Variable -ValueOnly", "Get-Variable -Name " + N + " -ValueOnly", "DENY"),
    ("braced ref", "Write-Output ${env:" + N + "}", "DENY"),
    ("Env:\\", "Get-ChildItem Env:\\", "DENY"),
    ("Env:/", "Get-ChildItem Env:/", "DENY"),
    ("GetEnvironmentVariable User", "[Environment]::GetEnvironmentVariable('" + N + "','User')", "DENY"),
    ("check written inside a string", 'Write-Output "IsNullOrEmpty(' + V + N + ')"', "DENY"),
    ("ForEach Name,Value", "Get-ChildItem Env: | ForEach-Object { $_.Name, $_.Value }", "DENY"),
    ("here-string", '@"\n' + V + N + '\n"@', "DENY"),
    ("Select-String -Path", "Select-String -Path " + E + " -Pattern X", "DENY"),
    ("Select-String quoted pattern", "Select-String -Path " + E + " -Pattern 'process.env'", "DENY"),
    ("Get-Content | Select-String", "Get-Content " + E + " | Select-String KEY", "DENY"),
    ("Select-String -LiteralPath", "Select-String -LiteralPath " + E + " -Pattern KEY", "DENY"),
    ("Select-String -NotMatch", "Select-String -Path " + E + " -Pattern KEY -NotMatch", "DENY"),
    # a later rule still fires after the new check
    ("env ref, then a key read", "$env:PATH; cat ~/.s" + "sh/id_" + "rsa", "DENY"),
    # still allowed
    ("set or unset", "if (" + V + S + ') { "set ($(' + V + S + '.Length) chars)" } else { "unset" }', "ALLOW"),
    ("IsNullOrEmpty", "[string]::IsNullOrEmpty(" + V + N + ")", "ALLOW"),
    ("assign and clear", V + 'ICC_HOSTED_IT = "1"; node --test t.js; Remove-Item Env:ICC_HOSTED_IT', "ALLOW"),
    ("names only, filtered", "Get-ChildItem Env: | Where-Object Name -like 'SUPABASE*' | Select-Object Name", "ALLOW"),
    ("names only, expanded", "gci env: | select -ExpandProperty Name", "ALLOW"),
    ("dotenv template", "Get-Content " + E + ".template", "ALLOW"),
    ("Get-Item PATH", "Get-Item Env:PATH", "ALLOW"),
    ("single-quoted literal", "Write-Output '" + V + N + "'", "ALLOW"),
    ("type a README", "type README.md", "ALLOW"),
    ("Measure-Object", "Write-Output " + V + N + " | Measure-Object -Character", "ALLOW"),
    ("Select-String on code", "Select-String -Pattern 'process.env' -Path app.js", "ALLOW"),
    ("assign a token", V + N + ' = "x"', "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "PowerShell", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  st=$(mktemp -d)
  out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/safety.sh" < "$TMP/p$i.json" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) got=DENY ;; *'"permissionDecision":"ask"'*) got=ASK ;; *) got=ALLOW ;; esac
  begin_test "powershell: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got"
done < "$TMP/cases"

rm -rf "$TMP"
report
