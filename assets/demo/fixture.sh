#!/usr/bin/env bash
# Demo helper — create a small throwaway git project (12 committed files, one
# edited, 3 never committed) and print its path, so `rm -rf src` has real files
# for the blast-radius prompt to count. Nothing in it is ever deleted by the demo.
set -euo pipefail
d=$(mktemp -d)/my-app
mkdir -p "$d/src"
for i in $(seq 1 12); do echo "export const v$i = $i" > "$d/src/mod$i.ts"; done
git -C "$d" init -q -b main
git -C "$d" add src
git -C "$d" -c user.email=demo@example.com -c user.name=demo commit -qm init
for i in 1 2 3; do echo "export const draft$i = true" > "$d/src/draft$i.ts"; done
echo "// edited" >> "$d/src/mod1.ts"
printf '%s\n' "$d"
