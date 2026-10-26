#!/usr/bin/env bash
# Spellings that skip or re-point git hooks, from ECC's block-no-verify corpus
# (affaan-m/ECC tests/hooks/block-no-verify.test.js, re-audited 2026-10-26).
# Thirteen of them passed safety.sh AND git-safety.sh before this file existed.
# Every case runs through both hooks; a case passes if either denies (or, for an
# inline config include, asks).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== Git hook-bypass forms ==="

TMP=$(mktemp -d)
python3 - "$TMP/cases" <<'PY'
import json, sys
NV = '--no-' + 'verify'
HP = 'core.' + 'hooksPath'
B = '`'
cases = [
    ("quoted flag", "git push '" + NV + "'", "DENY"),
    ("quote splice in the verb", "git com''mit " + NV, "DENY"),
    ("line continuation in the word", "g\\\nit push " + NV, "DENY"),
    ("quoted interpreter name", "'bash' -c 'git push " + NV + "'", "DENY"),
    ("piped into sudo -u root bash", "printf '%s' 'git push " + NV + "' | sudo -u root bash", "DENY"),
    ("backticks in an unquoted heredoc", "cat <<EOF\n" + B + "git push " + NV + B + "\nEOF", "DENY"),
    ("$() in an unquoted heredoc", "cat <<EOF\n$(git push " + NV + ")\nEOF", "DENY"),
    ("exec -a git", "exec -a git /usr/bin/git commit " + NV + " -m x", "DENY"),
    ("-c hooksPath inside a quoted $()", 'git commit -m "$(git -c ' + HP + '=/dev/null push)"', "DENY"),
    ("-c include.path", "git -c include.path=/tmp/x push", "ASK"),
    ("-c includeIf.*.path", "git -c includeIf.onbranch:main.path=/tmp/x push", "ASK"),
    ("GIT_CONFIG_KEY_n env trio", "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=" + HP + " GIT_CONFIG_VALUE_0=/dev/null git push", "DENY"),
    ("git config core.hooksPath <dir>", "git config " + HP + " /dev/null", "DENY"),
    ("absolute git path", "/usr/bin/git push " + NV, "DENY"),
    # still allowed
    ("message mentioning the flag", 'git commit -m "docs: explain ' + NV + '"', "ALLOW"),
    ("message that is a flag", "git commit -m '-n'", "ALLOW"),
    ("push -n is a dry run", "git push -n origin main", "ALLOW"),
    ("reading hooksPath", "git config --get " + HP, "ALLOW"),
    ("unsetting hooksPath", "git config --unset " + HP, "ALLOW"),
    ("other git config", "git config user.name x", "ALLOW"),
    ("quoted heredoc is data", "cat <<'EOF' > notes.md\ngit push " + NV + "\nEOF", "ALLOW"),
    ("heredoc commit message", "git commit -m \"$(cat <<'EOF'\nfix: x\n\nmentions " + NV + "\nEOF\n)\"", "ALLOW"),
    ("message naming the hooksPath flag beside a $", 'git commit -m "costs $5: never run git -c ' + HP + '=x"', "ALLOW"),
    ("sed -i '' keeps working", "sed -i '' 's/a/b/' f.txt && git push", "ALLOW"),
]
with open(sys.argv[1], "w") as f:
    for name, cmd, want in cases:
        f.write(json.dumps({"name": name, "want": want,
                            "payload": {"tool_name": "Bash", "cwd": "/tmp", "tool_input": {"command": cmd}}}) + "\n")
PY

_one() {  # hook, payload-file -> DENY | ASK | ALLOW
  local st out rc; st=$(mktemp -d)
  out=$(SUPERCHARGER_STATE="$st" SUPERCHARGER_NO_DEDUP=1 bash "$REPO_DIR/hooks/$1" < "$2" 2>/dev/null); rc=$?
  rm -rf "$st"
  case "$rc:$out" in 2:*|*'"permissionDecision":"deny"'*) echo DENY ;; *'"permissionDecision":"ask"'*) echo ASK ;; *) echo ALLOW ;; esac
}

i=0
while IFS= read -r line; do
  i=$((i+1))
  name=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["name"])')
  want=$(printf '%s' "$line" | python3 -c 'import json,sys;print(json.load(sys.stdin)["want"])')
  printf '%s' "$line" | python3 -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["payload"]))' > "$TMP/p$i.json"
  a=$(_one safety.sh "$TMP/p$i.json"); b=$(_one git-safety.sh "$TMP/p$i.json")
  case "$a $b" in *DENY*) got=DENY ;; *ASK*) got=ASK ;; *) got=ALLOW ;; esac
  begin_test "bypass: $name -> $want"
  [ "$got" = "$want" ] && pass || fail "got $got (safety=$a git-safety=$b)"
done < "$TMP/cases"

rm -rf "$TMP"

# Windows jq hands the command over with CRLF, so a continuation arrives as
# backslash-CR-LF. This passed on macOS/Linux and failed only on the Windows runner;
# check the normalizer directly with that spelling so every OS exercises it.
begin_test "bypass: normalizer joins a backslash-CR-LF continuation"
NORM=$(source "$REPO_DIR/hooks/cmd-normalize.sh"; normalize_cmd "g\\"$'\r\n'"it push --no-verify")
case "$NORM" in *"git push --no-verify"*) pass ;; *) fail "not joined: $(printf '%q' "$NORM")" ;; esac

report
