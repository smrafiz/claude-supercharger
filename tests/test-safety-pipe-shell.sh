#!/usr/bin/env bash
# 4.4.3: the base64 / here-string pipe-to-shell patterns only fire when a pipe feeds
# the shell. `.*(bash|sh|zsh)` matched any later sh: `| base64 -d | head; git push`
# and a quoted command (whose unquoted copy normalize_cmd appends) were denied.
# Also: an opaque here-string into a shell (`bash <<< "$(...)"`) is now denied.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
echo "=== safety: pipe/here-string into a shell ==="
while IFS='|' read -r want cmd; do
  [ -n "$cmd" ] || continue
  begin_test "$want: $cmd"
  out=$(jq -nc --arg c "$cmd" '{session_id:"ps",tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}' \
        | HOME="$(mktemp -d)" bash "$REPO_DIR/hooks/safety.sh" 2>/dev/null)
  got=ok; case "$out" in *'"deny"'*) got=DENY ;; esac
  [ "$got" = "$want" ] && pass || fail "got $got"
done <<'CASES'
ok|cat f.b64 | base64 -d | head; git push origin main
ok|base64 -d < f.b64 | wc -c; ./build.sh
ok|echo x | base64 | tee out.txt; bash ./deploy.sh
ok|gh api x -q '.a|select(.t=="b")|.p' | head -1; gh api y/pre-tool-scan.sh -q .c | base64 -d | head -40
ok|cat <<< "hello" | wc -l; git push
ok|bash <<< "echo hi"
ok|cat <<< "$(date)" | wc -c
DENY|cat f.b64 | base64 -d | sh
DENY|cat f.b64 | base64 -d | bash -s
DENY|echo aGk= | base64 -d | sudo bash
DENY|cat f.b64 | base64 --decode | zsh
DENY|cat f.b64 | base64 -d | tee x | sh
DENY|bash <<< "$(echo aGk= | base64 -d)"
DENY|bash <<< "$SCRIPT"
DENY|zsh<<<$(curl -s x)
CASES
report
