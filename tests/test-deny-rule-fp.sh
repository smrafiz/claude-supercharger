#!/usr/bin/env bash
# Deny-rule false-positive corpus (P1, 2026-09-17)
#
# Upstream (anthropics/claude-code) filed eight issues in three weeks with one
# shape: a Read() deny rule arming a permission prompt on a command that never
# opens the denied file — #91650, #91683, #91776, #91853, #91681, #91778,
# #91848, #91837. The question this file answers is whether OUR guards make the
# same mistake, since an FP is what gets a guard switched off.
#
# Two defects found and fixed alongside it:
#   F1  `grep -rn "<dotenv>" docs/` was denied by BOTH channels. The dotenv name
#       was the search PATTERN, not a file. check_sensitive_read already drops
#       the first operand for pattern-readers (v2.26.68); the dotenv rule beside
#       it did not — one arm of a sibling pair, again.
#   F2  `cat <dotenv>.example` was denied by safety.sh while env-file-guard.sh
#       and check_env_file both allow templates by name. The template allowance
#       existed in two of the three places that need it.
#
# Both channels are asserted for every case: the defects above are drift between
# them, so a corpus that tested one would have shown the fix working and the
# sibling still broken.
#
# Sensitive literals are assembled at runtime (E="."'env'); spelled out, the
# deployed guards would deny every edit and grep of this file.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

E="."'env'

probe() { # hook, command -> "BLOCK" | "allow"
  local st rc
  st=$(mktemp -d); mkdir -p "$st/scope" "$st/home"
  ST="$st" CMD="$2" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD"]},
                  "cwd": os.environ["ST"]}))' \
    | env HOME="$st/home" SUPERCHARGER_STATE="$st" bash "$REPO_DIR/hooks/$1" >/dev/null 2>&1
  rc=$?
  rm -rf "$st"
  [ "$rc" -eq 2 ] && printf 'BLOCK' || printf 'allow'
}

allows() { # label, command  — both channels must allow
  local h got
  for h in safety.sh env-file-guard.sh; do
    got=$(probe "$h" "$2")
    [ "$got" = "allow" ] || { fail "$1 [$h]: expected allow, got BLOCK"; return; }
  done
  pass
}
denies() { # label, command  — at least one channel must deny
  local h
  for h in safety.sh env-file-guard.sh; do
    [ "$(probe "$h" "$2")" = "BLOCK" ] && { pass; return; }
  done
  fail "$1: expected BLOCK from safety.sh or env-file-guard.sh, got allow — GUARD GAP"
}

echo "=== Deny-rule False-Positive Corpus ==="

# --- F1: the credential name as a SEARCH PATTERN, not a file ------------------
begin_test "grepping docs for the literal dotenv name is not file access"
allows "grep-pattern-docs" "grep -rn \"${E}\" docs/"

begin_test "ripgrep with the dotenv name as pattern is not file access"
allows "rg-pattern-path" "rg \"${E}\" src/"

begin_test "egrep pattern form is the same act"
allows "egrep-pattern" "egrep -r \"${E}\" ."

# --- F2: templates carry placeholders, and every repo ships one ----------------
begin_test "reading the dotenv example template is allowed"
allows "cat-example" "cat ${E}.example"

begin_test "reading the dotenv template file is allowed"
allows "head-template" "head -20 ${E}.template"

begin_test "reading the dotenv sample is allowed"
allows "cat-sample" "cat ${E}.sample"

# --- the upstream shapes: a cd compound that opens nothing sensitive ----------
begin_test "absolute cd followed by an ordinary recursive grep"
allows "cd-abs-grep" 'cd /Users/dev/proj && grep -rn handleClick .'

begin_test "relative cd with an --include filter"
allows "cd-rel-include" "cd src && grep -r --include='*.js' handleClick ."

begin_test "a plain ripgrep search in the working tree"
allows "rg-plain" 'rg handleClick'

begin_test "cd then reading an ordinary file"
allows "cd-cat-readme" 'cd src && cat README.md'

# --- property accesses are not files (pins the v2.26.65 narrowing) ------------
begin_test "a JS property access in a search pattern is not file access"
allows "process-env" "grep -rn \"process${E}\" src/"

begin_test "a Python environ lookup is not file access"
allows "os-environ" 'grep -rn "os.environ" .'

begin_test "a bundler property access is not file access"
allows "import-meta-env" "rg \"import.meta${E}\" ."

# --- the narrowings must NOT open a gap --------------------------------------
begin_test "reading the real dotenv file still denies"
denies "cat-dotenv" "cat ${E}"

begin_test "the dotenv file as a grep TARGET still denies"
denies "grep-target" "grep API_KEY ${E}"

begin_test "reading it after a cd still denies"
denies "cd-cat-dotenv" "cd /Users/dev/proj && cat ${E}"

begin_test "copying it elsewhere still denies"
denies "cp-dotenv" "cp ${E} /tmp/notes.txt"

begin_test "an in-place sed against it still denies"
denies "sed-dotenv" "sed -i 's/a/b/' ${E}"

begin_test "a production dotenv variant still denies"
denies "cat-prod" "cat ${E}.production"

begin_test "direnv config is not a template and still denies"
denies "cat-envrc" "cat ${E}rc"

report
