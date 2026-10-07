#!/usr/bin/env bash
# Regenerate configs/commands-shipped.txt: every slash-command file name ever
# shipped from configs/commands/, with the sha256 of every version of it.
# The installer uses it to tell OUR unmodified files (safe to replace or remove)
# from files the user wrote or edited (never touched). CR is stripped before
# hashing so a CRLF checkout hashes the same as LF.
# Usage: bash tools/gen-commands-shipped.sh   (run after changing a command)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
git log --all --format=%H -- configs/commands \
  | while read -r c; do
      git ls-tree "$c" configs/commands/ | awk '$2=="blob" && $4 ~ /\.md$/ {print $3, $4}'
    done \
  | { cat; for f in configs/commands/*.md; do echo "$(git hash-object -w "$f") $f"; done; } \
  | sort -u \
  | while read -r blob path; do
      h=$(git cat-file blob "$blob" | tr -d '\r' | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
      printf '%s %s\n' "$(basename "$path" .md)" "$h"
    done \
  | sort -u > configs/commands-shipped.txt
echo "configs/commands-shipped.txt: $(wc -l < configs/commands-shipped.txt | tr -d ' ') entries, $(cut -d' ' -f1 configs/commands-shipped.txt | sort -u | wc -l | tr -d ' ') names"
