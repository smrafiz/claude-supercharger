#!/usr/bin/env bash
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOK="$REPO_DIR/hooks/commit-secret-guard.sh"

echo "=== commit-secret-guard Tests ==="
export SUPERCHARGER_NO_DEDUP=1

# Build a throwaway git repo, stage some content, run the hook against `git commit`.
# Echoes hook stdout; deny path exits 2.
_run() { # <repo-cwd> <command> [enabled=1]
  local cwd="$1" cmd="$2" en="${3:-1}"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$cmd" "$cwd" \
    | SUPERCHARGER_COMMIT_SECRET_GUARD="$en" bash "$HOOK" 2>/dev/null
}
_newrepo() { local d; d=$(mktemp -d); ( cd "$d" && git init -q && git config user.email t@t && git config user.name t ) ; echo "$d"; }

begin_test "commit-secret-guard: hook exists and is executable"
[ -x "$HOOK" ] && pass || fail "hook missing or not executable"

begin_test "commit-secret-guard: staged AWS key blocks the commit"
D=$(_newrepo); printf 'AWS_KEY = "AKIAIOSFODNN7EXAMPLE"\n' > "$D/config.py"; ( cd "$D" && git add config.py )
OUT=$(_run "$D" "git commit -m add-config")
echo "$OUT" | grep -q 'permissionDecision.*deny' && echo "$OUT" | grep -qi 'secret' \
  && pass || fail "expected block on staged AWS key, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: staged private key block is blocked"
D=$(_newrepo); printf -- '-----BEGIN RSA PRIVATE KEY-----\nMIIabc\n' > "$D/id_rsa"; ( cd "$D" && git add id_rsa )
OUT=$(_run "$D" "git commit -m key")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block on private key, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: staged Ethereum wallet key is blocked (wallet pattern)"
D=$(_newrepo); printf 'PK=0x%064d\n' 1 > "$D/w.env"; ( cd "$D" && git add w.env )
OUT=$(_run "$D" "git commit -m wallet")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block on eth key, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: staged BIP-32 xprv key is blocked (v2.9.10)"
D=$(_newrepo); printf 'k=xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi\n' > "$D/w.txt"; ( cd "$D" && git add w.txt )
OUT=$(_run "$D" "git commit -m xprv")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block on xprv key, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: staged Bitcoin WIF key is blocked (v2.9.10)"
D=$(_newrepo); printf 'wif=5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ\n' > "$D/w.txt"; ( cd "$D" && git add w.txt )
OUT=$(_run "$D" "git commit -m wif")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block on WIF key, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: clean staged diff commits fine"
D=$(_newrepo); printf 'export function add(a,b){return a+b}\n' > "$D/util.js"; ( cd "$D" && git add util.js )
OUT=$(_run "$D" "git commit -m util")
[ -z "$OUT" ] && pass || fail "expected clean commit allowed, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: secret only in UNSTAGED file is ignored (staged-only)"
D=$(_newrepo); printf 'ok=1\n' > "$D/a.txt"; ( cd "$D" && git add a.txt )
printf 'AKIAIOSFODNN7EXAMPLE\n' > "$D/secret.txt"   # present but NOT staged
OUT=$(_run "$D" "git commit -m a")
[ -z "$OUT" ] && pass || fail "expected unstaged secret ignored, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: non-commit git command is ignored"
D=$(_newrepo); printf 'AKIAIOSFODNN7EXAMPLE\n' > "$D/s.txt"; ( cd "$D" && git add s.txt )
OUT=$(_run "$D" "git status")
[ -z "$OUT" ] && pass || fail "expected git status ignored, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: git commit-tree plumbing is not matched"
D=$(_newrepo)
OUT=$(_run "$D" "git commit-tree HEAD^{tree} -m x")
[ -z "$OUT" ] && pass || fail "expected commit-tree ignored, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: chained '&& git commit' with staged secret is blocked"
D=$(_newrepo); printf 'token: ghp_%036d\n' 1 > "$D/c.yml"; ( cd "$D" && git add c.yml )
OUT=$(_run "$D" "echo done && git commit -m c")
echo "$OUT" | grep -q 'permissionDecision.*deny' && pass || fail "expected block on chained commit, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: disabled via env still allows"
D=$(_newrepo); printf 'AKIAIOSFODNN7EXAMPLE\n' > "$D/x.txt"; ( cd "$D" && git add x.txt )
OUT=$(_run "$D" "git commit -m x" 0)
[ -z "$OUT" ] && pass || fail "expected no block when disabled, got: $OUT"
rm -rf "$D"

begin_test "commit-secret-guard: fail-open on malformed JSON"
OUT=$(printf 'not json' | bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && pass || fail "expected fail-open, got: $OUT"

begin_test "commit-secret-guard: non-git dir commit is ignored (fail-open)"
D=$(mktemp -d)   # NOT a git repo
OUT=$(_run "$D" "git commit -m x")
[ -z "$OUT" ] && pass || fail "expected non-git ignored, got: $OUT"
rm -rf "$D"

report
