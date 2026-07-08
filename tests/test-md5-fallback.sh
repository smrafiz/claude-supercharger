#!/usr/bin/env bash
# v2.9.3: Git Bash ships neither md5sum nor md5 — every hash site falls back to
# python3 hashlib.md5. Verify the exact one-liners used across the hooks produce
# correct, correctly-truncated hex, matching a reference md5.
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "=== md5 python fallback tier (G2) ==="

S="/some/project/path"
# Reference hash from whichever native tool exists (md5sum on Linux, md5 on macOS).
REF=$(printf '%s' "$S" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$S" | md5 -q 2>/dev/null)

begin_test "md5 fallback: python3 available in test env"
command -v python3 >/dev/null 2>&1 && pass || fail "python3 missing — fallback untestable"

begin_test "md5 fallback: stdin full-hex matches native md5"
OUT=$(printf '%s' "$S" | python3 -c 'import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest())' 2>/dev/null)
[ -n "$REF" ] && [ "$OUT" = "$REF" ] && pass || fail "full hex mismatch: py=$OUT ref=$REF"

begin_test "md5 fallback: stdin [:8] truncation (failure-tracker/proj-hash sites)"
OUT=$(printf '%s' "$S" | python3 -c 'import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:8])' 2>/dev/null)
[ "${#OUT}" -eq 8 ] && [ "$OUT" = "${REF:0:8}" ] && pass || fail "8-hex mismatch: py=$OUT ref=${REF:0:8}"

begin_test "md5 fallback: stdin [:32] truncation (lib-suppress dedup site)"
OUT=$(printf '%s' "$S" | python3 -c 'import sys,hashlib; print(hashlib.md5(sys.stdin.buffer.read()).hexdigest()[:32])' 2>/dev/null)
[ "${#OUT}" -eq 32 ] && [ "$OUT" = "$REF" ] && pass || fail "32-hex mismatch: py=$OUT ref=$REF"

begin_test "md5 fallback: file-arg variant (quality-gate content hash)"
TMPF=$(mktemp)
printf '%s' "$S" > "$TMPF"
OUT=$(python3 -c 'import sys,hashlib; print(hashlib.md5(open(sys.argv[1],"rb").read()).hexdigest())' "$TMPF" 2>/dev/null)
rm -f "$TMPF"
[ "$OUT" = "$REF" ] && pass || fail "file hash mismatch: py=$OUT ref=$REF"

# End-to-end: confirm repetition-detector still keys its history file by a hash
# when the native md5 tools are gone (i.e. the python tier actually fires in-hook).
# Where md5sum/md5 EXIST (Linux/macOS) hide them via a full-PATH symlink mirror;
# where they're already absent (Windows/Git Bash) run directly — do NOT mirror PATH
# on MSYS, where `ln -s` copies files and cloning System32 hangs the job.
begin_test "md5 fallback: repetition-detector still hashes with md5sum/md5 absent"
setup_test_home
HOOK="$REPO_DIR/hooks/repetition-detector.sh"
INPUT='{"session_id":"md5sess","prompt":"do the thing again please"}'
if command -v md5sum >/dev/null 2>&1 || command -v md5 >/dev/null 2>&1; then
  SHADOW=$(mktemp -d)
  IFS=':' read -ra _pdirs <<< "$PATH"
  for d in "${_pdirs[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      b=$(basename "$f" 2>/dev/null)
      { [ "$b" = "md5sum" ] || [ "$b" = "md5" ]; } && continue
      [ -e "$SHADOW/$b" ] || ln -sf "$f" "$SHADOW/$b" 2>/dev/null
    done
  done
  OUT=$(PATH="$SHADOW" bash "$HOOK" <<<"$INPUT" 2>&1)
  EXIT=$?
  rm -rf "$SHADOW"
else
  OUT=$(bash "$HOOK" <<<"$INPUT" 2>&1)
  EXIT=$?
fi
teardown_test_home
[ "$EXIT" -eq 0 ] && pass || fail "repetition-detector errored with md5 tools absent (exit $EXIT): $OUT"

report
