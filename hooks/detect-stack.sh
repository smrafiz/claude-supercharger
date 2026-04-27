#!/usr/bin/env bash
# Claude Supercharger — Stack Auto-Detection
# Usage: bash detect-stack.sh [project_dir]
# Outputs detected stack info as key=value pairs.
# Used by claude-check and can be sourced by other tools.

set -euo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$HOOKS_DIR/../lib" && pwd)"
PROJECT_DIR="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"

python3 -c "
import sys, json, os
sys.path.insert(0, sys.argv[1])
from detect_stack import detect_stack
s = detect_stack(sys.argv[2])
if not s['detected']:
    print('detected=false')
    sys.exit(0)
print('detected=true')
print('language=' + ', '.join(s['language']))
if s['framework']:
    print('framework=' + ', '.join(s['framework']))
if s['package_manager']:
    print('package_manager=' + s['package_manager'])
if s['test_framework']:
    print('test_framework=' + ', '.join(s['test_framework']))
if s['build_tool']:
    print('build_tool=' + ', '.join(s['build_tool']))
" "$LIB_DIR" "$PROJECT_DIR"
