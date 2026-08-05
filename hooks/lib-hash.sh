#!/usr/bin/env bash
# Claude Supercharger — portable MD5 helper
#
# Reads stdin, echoes a 32-char lowercase hex digest, or an empty string when no
# backend exists. Callers keep their own "" fallback (usually "global").
#
# WHY THIS EXISTS (v2.26.50). Eight call sites carried a chain like:
#
#     printf '%s' "$X" | md5sum 2>/dev/null | cut -d' ' -f1 \
#       || printf '%s' "$X" | md5 -q 2>/dev/null || echo "global"
#
# That fallback is UNREACHABLE. `||` binds to the whole pipeline, and the
# pipeline's status is `cut`'s — which exits 0 on empty input. So when md5sum is
# missing the chain yields an EMPTY STRING, never "global" and never the md5 arm.
# Verified: with md5sum forced off PATH the result is [] rather than [global].
#
# The consequence is worse than a missing hash. These digests are per-project
# state KEYS — `.failed-commands-<hash>`, quality-gate and typecheck caches,
# session-memory files. An empty key means every project silently shares one
# file: the cross-project collision class closed as audit HIGH #13 (v2.26.33),
# reintroduced by a broken fallback rather than by keying.
#
# It has been invisible on macOS and Linux CI because both have md5sum or md5.
# Git Bash has NEITHER, which is how the Windows work surfaced it (plan G2).
#
# Guarded with `command -v` instead of `||` chaining, so each backend is chosen
# BEFORE running rather than by inspecting a pipeline's misleading exit status.
# v2.26.61: every tier costs exactly ONE fork.
#
# The first version piped md5sum through `cut` and openssl through `sed`, which
# made those tiers 2 forks. lib-suppress calls this on its dedup path, which runs
# on every Bash tool call, so v2.26.50 measurably slowed a hot hook: budget-cap
# went 7.4 -> 10.6 ms median (baseline BELOW the min of six samples, so not noise)
# where the code it replaced used a single `md5 -q`.
#
# Trimming is done with bash parameter expansion instead. `${out%% *}` takes
# everything before the first space — md5sum prints "<hash>  -" — and `${out##*= }`
# drops openssl's "MD5(stdin)= " prefix. Both are builtins: no process, no pipe.
# Net effect: the portability fix no longer costs what it used to save.
sc_md5() {
  local out=""
  if command -v md5sum >/dev/null 2>&1; then
    out=$(md5sum 2>/dev/null)
    out="${out%% *}"
  elif command -v md5 >/dev/null 2>&1; then
    # BSD/macOS. -q prints the digest alone.
    out=$(md5 -q 2>/dev/null)
  elif command -v openssl >/dev/null 2>&1; then
    # "(stdin)= <hex>" or "MD5(stdin)= <hex>" depending on version.
    out=$(openssl md5 2>/dev/null)
    out="${out##*=}"; out="${out## }"
  elif command -v python3 >/dev/null 2>&1; then
    # Final tier, and the one Git Bash actually reaches. python3 is already a
    # hard install requirement, so this is not a new dependency.
    out=$(python3 -c 'import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())' 2>/dev/null)
  fi
  # Only ever emit something digest-shaped; a partial or error string would
  # become a state-file name.
  case "$out" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) printf '%s' "$out" ;;
    *) printf '' ;;
  esac
}
