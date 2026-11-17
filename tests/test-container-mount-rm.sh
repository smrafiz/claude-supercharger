#!/usr/bin/env bash
# 2026-11-17 (from kenryu42/cc-safety-net #367): a container run that bind-mounts
# the project dir and recursively deletes the mount target wipes the project on the
# host (was allowed). A container run with no mount whose rm is unwrapped from
# `sh -c` deletes container paths only (was an ask).
REPO_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

HOOKS="$REPO_DIR/hooks"
PROJ=$(mktemp -d); mkdir -p "$PROJ/app/.git" "$PROJ/app/sub"; PROJ=$(cd "$PROJ" && pwd -P)

echo "=== Container bind-mount rm ==="

# command -> DENY | ASK | allow, with the project at $PROJ/app/sub.
verdict() {
  local j out rc st
  st=$(mktemp -d)
  j=$(CMD="$1" CWD="$PROJ/app/sub" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "cwd": os.environ["CWD"], "session_id": "t",
                  "tool_input": {"command": os.environ["CMD"]}}))')
  out=$(printf '%s' "$j" | SUPERCHARGER_STATE="$st" bash "$HOOKS/safety.sh" 2>&1); rc=$?
  rm -rf "$st"
  if [ "$rc" = 2 ] || [[ "$out" == *'"permissionDecision":"deny"'* ]] || [[ "$out" == *'"permissionDecision": "deny"'* ]]; then
    echo DENY
  elif [[ "$out" == *'"ask"'* ]]; then
    echo ASK
  else
    echo allow
  fi
}

expect() { # expect VERDICT command
  begin_test "$2 -> $1"
  local got; got=$(verdict "$2")
  [ "$got" = "$1" ] && pass || fail "got $got for: $2"
}

# --- the project mounted writable, then the mount target deleted -------------------
expect DENY 'docker run --rm -v "$PWD":/w alpine rm -rf /w'
expect DENY 'docker run --rm -v $PWD:/w alpine rm -rf /'
expect DENY 'docker run --rm -v "$PWD":/w alpine sh -c "rm -rf /w/*"'
expect DENY 'docker run --rm -v .:/app node rm -rf /app/'
expect DENY 'docker run --rm -v ..:/up alpine rm -r /up'
expect DENY 'docker run --rm --mount type=bind,source="$(pwd)",target=/src alpine rm -rf /src'
expect DENY "podman run --rm -v $PROJ/app:/w fedora rm -rf /w"
expect DENY "docker run --rm -v $PROJ:/w alpine rm -rf /w"
# look-alikes: a subdir, a read-only mount, a mount outside the project
expect allow 'docker run --rm -v "$PWD":/w alpine rm -rf /w/node_modules'
expect allow 'docker run --rm -v "$PWD":/w:ro alpine rm -rf /w'
expect allow 'docker run --rm -v /tmp/cache:/w alpine rm -rf /w'
expect allow 'docker run --rm -v "$PWD":/w alpine ls /w'

# --- no mount: an rm unwrapped from sh -c is a container path ----------------------
expect allow 'docker run --rm alpine sh -c "rm -rf /var/lib/x"'
expect allow 'docker container run --rm alpine sh -c "rm -rf /opt/x"'
# still asked: a host rm beside the run, a mount, exec into a running container
expect ASK 'docker run --rm alpine true; rm -rf /var/lib/x'
expect ASK 'docker run --rm alpine sh -c "true" && rm -rf /var/lib/x'
expect ASK 'docker run --rm -v /data:/d alpine sh -c "rm -rf /var/lib/x"'
expect ASK 'docker exec app sh -c "rm -rf /var/lib/x"'
expect ASK 'docker run --rm alpine sh -c "$(echo x)"; rm -rf /var/lib/x'

rm -rf "$PROJ"
echo ""
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ]
