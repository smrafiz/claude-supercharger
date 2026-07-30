#!/usr/bin/env bash
# Sensitive-filename token boundaries (v2.25.2)
#
# safety-detect.py's _SENSITIVE_NAME_RE matched `.env` with no terminator, so it fired
# on the substring inside ordinary identifiers — `os.environ`, `process.environ`,
# `.environment`. Any reader command (cat/grep/head/sed/awk…) whose arguments happened
# to contain one was denied as "sensitive file access: .env — credentials likely
# present". Hit repeatedly while inspecting the guards themselves.
#
# The trap when fixing it: the obvious terminator (`\b` or `(?!\w)`) silently DROPS
# `.envrc`, which direnv uses and which holds secrets — it only matched before
# BECAUSE the pattern was unbounded. So the fix carries `(?:rc)?`, and both halves are
# pinned below: the false positives must stop, and every real filename must still be
# caught. A guard that stops over-blocking by quietly under-blocking is worse than the
# false positive it fixed.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

DETECT="$REPO_DIR/hooks/safety-detect.py"

echo "=== Sensitive Filename Boundary Tests ==="

# Ask safety-detect.py directly: does it flag this command?
flags() { CMD="$1" python3 "$DETECT" 2>/dev/null; }

expect_flag() { # label cmd
  begin_test "$1"
  local out; out=$(flags "$2")
  [ -n "$out" ] && pass || fail "expected a block for: $2"
}
expect_clean() { # label cmd
  begin_test "$1"
  local out; out=$(flags "$2")
  [ -z "$out" ] && pass || fail "false positive: $out — for: $2"
}

# --- real sensitive files must STILL be caught ---
expect_flag "still blocks: cat .env"                 'cat .env'
expect_flag "still blocks: cat .env.local"           'cat .env.local'
expect_flag "still blocks: cat .env.production"      'cat .env.production'
expect_flag "still blocks: cat /srv/app/.env"        'cat /srv/app/.env'
expect_flag "still blocks: grep in .env"             'grep SECRET .env'
expect_flag "still blocks: head .env-local"          'head .env-local'
# The one a naive boundary fix would have silently dropped.
expect_flag "still blocks: cat .envrc (direnv)"      'cat .envrc'
expect_flag "still blocks: cat ~/.aws/credentials"   'cat ~/.aws/credentials.json'
expect_flag "still blocks: cat id_rsa"               'cat ~/.ssh/id_rsa'

# --- the false positives that motivated this ---
expect_clean "allows python reading os.environ"      'python3 -c "import os; print(os.environ)"'
expect_clean "allows os.environ in a longer command" 'head -3 log.txt; python3 -c "print(os.environ[\"X\"])"'
expect_clean "allows process.environ in JS"          'grep -rn "process.environ" src/'
expect_clean "allows a .environment identifier"      'grep -rn settings.environment src/'
expect_clean "allows an .environment_notes file"     'cat notes/.environment_notes'

# --- v2.25.3: the SAME unbounded-token flaw on every OTHER alternative ---
# 2.25.2 bounded only the .env arm and checked the other .env SITES rather than the
# other ALTERNATIVES, leaving twelve in place. `.keys()` is the worst of them: it is
# ubiquitous in Python and JavaScript, and it read as a private-key file.
expect_clean "allows Object.keys(cfg)"               'grep -rn "Object.keys(cfg)" src/'
expect_clean "allows obj.keys() in python"           'grep -rn "for k in obj.keys():" src/'
expect_clean "allows sorted(d.keys())"               'cat app.py; grep -n "sorted(d.keys())" app.py'
expect_clean "allows a .keyword field"               'grep -rn row.keyword src/'
expect_clean "allows .certificate identifier"        'grep -rn cfg.certificate src/'
expect_clean "allows a name ending pemberton"        'grep -rn x.pemberton src/'
expect_clean "allows .walletsize identifier"         'grep -rn data.walletsize src/'
expect_clean "allows .tokens.jsonl (not .json)"      'cat s.tokens.jsonl'

# Real key/cert material must still be caught after the boundary change.
expect_flag "still blocks: cat server.key"           'cat server.key'
expect_flag "still blocks: cat cert.pem"             'cat cert.pem'
expect_flag "still blocks: cat cert.pem.bak"         'cat cert.pem.bak'
expect_flag "still blocks: cat client.crt"           'cat client.crt'
expect_flag "still blocks: cat store.p12"            'cat store.p12'
expect_flag "still blocks: cat key.pfx"              'cat key.pfx'
expect_flag "still blocks: cat id_ed25519"           'cat ~/.ssh/id_ed25519'
expect_flag "still blocks: cat ~/.npmrc"             'cat ~/.npmrc'
expect_flag "still blocks: cat ~/.netrc"             'cat ~/.netrc'
expect_flag "still blocks: cat .git-credentials"     'cat ~/.git-credentials'
expect_flag "still blocks: cat wallet.dat"           'cat wallet.dat'
expect_flag "still blocks: cat main.tfvars"          'cat main.tfvars'
expect_flag "still blocks: cat a.tokens.json"        'cat a.tokens.json'
expect_flag "still blocks: cat ~/.kube/config"       'cat ~/.kube/config'
expect_flag "still blocks: cat ~/.docker/config.json" 'cat ~/.docker/config.json'

report
