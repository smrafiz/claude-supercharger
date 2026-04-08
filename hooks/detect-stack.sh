#!/usr/bin/env bash
# Claude Supercharger — Stack Auto-Detection
# Usage: bash detect-stack.sh [project_dir]
# Outputs detected stack info as key=value pairs.
# Used by claude-check and can be sourced by other tools.
#
# NOTE: This is a standalone utility invoked directly by tools/claude-check.sh
# and tools/init-agents.sh. It outputs key=value pairs to stdout.
#
# hooks/project-config.sh contains its own inline stack detection (embedded
# Python, richer framework coverage) and does NOT source this file.
# TODO: consolidate both into a shared lib once output formats are unified.

set -euo pipefail

PROJECT_DIR="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

python3 -c "
import json, os, sys

project_dir = sys.argv[1]

stack = {
    'language': [],
    'framework': [],
    'package_manager': None,
    'test_framework': [],
    'build_tool': [],
}

# --- Node.js / JavaScript / TypeScript ---
pkg_json = os.path.join(project_dir, 'package.json')
if os.path.isfile(pkg_json):
    try:
        with open(pkg_json) as f:
            pkg = json.load(f)
        deps = {}
        deps.update(pkg.get('dependencies', {}))
        deps.update(pkg.get('devDependencies', {}))

        if 'typescript' in deps or os.path.isfile(os.path.join(project_dir, 'tsconfig.json')):
            stack['language'].append('TypeScript')
        else:
            stack['language'].append('JavaScript')

        # Frameworks
        fw_map = {
            'next': 'Next.js', 'nuxt': 'Nuxt', 'react': 'React', 'vue': 'Vue',
            'svelte': 'Svelte', '@sveltejs/kit': 'SvelteKit', 'express': 'Express',
            'fastify': 'Fastify', 'hono': 'Hono', '@nestjs/core': 'NestJS',
            'astro': 'Astro', 'remix': 'Remix', '@angular/core': 'Angular',
            'solid-js': 'SolidJS', 'gatsby': 'Gatsby',
        }
        for dep, name in fw_map.items():
            if dep in deps:
                stack['framework'].append(name)

        # Test frameworks
        test_map = {
            'jest': 'Jest', 'vitest': 'Vitest', 'mocha': 'Mocha',
            '@playwright/test': 'Playwright', 'cypress': 'Cypress',
        }
        for dep, name in test_map.items():
            if dep in deps:
                stack['test_framework'].append(name)

        # Build tools
        build_map = {
            'vite': 'Vite', 'webpack': 'Webpack', 'esbuild': 'esbuild',
            'turbo': 'Turborepo', 'tsup': 'tsup', 'rollup': 'Rollup',
        }
        for dep, name in build_map.items():
            if dep in deps:
                stack['build_tool'].append(name)
    except (json.JSONDecodeError, IOError):
        stack['language'].append('JavaScript')

# Package manager detection
pm_map = [
    ('pnpm-lock.yaml', 'pnpm'),
    ('yarn.lock', 'yarn'),
    ('bun.lockb', 'bun'),
    ('bun.lock', 'bun'),
    ('package-lock.json', 'npm'),
]
for lockfile, pm in pm_map:
    if os.path.isfile(os.path.join(project_dir, lockfile)):
        stack['package_manager'] = pm
        break

# --- Python ---
py_files = ['requirements.txt', 'setup.py', 'setup.cfg', 'pyproject.toml']
if any(os.path.isfile(os.path.join(project_dir, f)) for f in py_files):
    if 'Python' not in stack['language']:
        stack['language'].append('Python')

    pyproject = os.path.join(project_dir, 'pyproject.toml')
    reqs = os.path.join(project_dir, 'requirements.txt')

    # Read deps from requirements.txt or pyproject.toml (simple parsing)
    dep_text = ''
    if os.path.isfile(reqs):
        with open(reqs) as f:
            dep_text = f.read().lower()
    if os.path.isfile(pyproject):
        with open(pyproject) as f:
            dep_text += f.read().lower()

    py_fw = {
        'django': 'Django', 'flask': 'Flask', 'fastapi': 'FastAPI',
        'starlette': 'Starlette', 'tornado': 'Tornado', 'aiohttp': 'aiohttp',
    }
    for dep, name in py_fw.items():
        if dep in dep_text and name not in stack['framework']:
            stack['framework'].append(name)

    py_test = {'pytest': 'pytest', 'unittest': 'unittest', 'nose': 'nose'}
    for dep, name in py_test.items():
        if dep in dep_text and name not in stack['test_framework']:
            stack['test_framework'].append(name)

    # Python package manager
    if not stack['package_manager']:
        if os.path.isfile(os.path.join(project_dir, 'uv.lock')):
            stack['package_manager'] = 'uv'
        elif os.path.isfile(os.path.join(project_dir, 'poetry.lock')):
            stack['package_manager'] = 'poetry'
        elif os.path.isfile(os.path.join(project_dir, 'Pipfile.lock')):
            stack['package_manager'] = 'pipenv'
        elif os.path.isfile(os.path.join(project_dir, 'requirements.txt')):
            stack['package_manager'] = 'pip'

# --- Rust ---
if os.path.isfile(os.path.join(project_dir, 'Cargo.toml')):
    stack['language'].append('Rust')
    stack['package_manager'] = stack['package_manager'] or 'cargo'

    cargo = os.path.join(project_dir, 'Cargo.toml')
    with open(cargo) as f:
        cargo_text = f.read().lower()
    if 'actix' in cargo_text:
        stack['framework'].append('Actix')
    if 'axum' in cargo_text:
        stack['framework'].append('Axum')
    if 'rocket' in cargo_text:
        stack['framework'].append('Rocket')
    if 'tokio' in cargo_text:
        stack['build_tool'].append('Tokio')

# --- Go ---
if os.path.isfile(os.path.join(project_dir, 'go.mod')):
    stack['language'].append('Go')
    stack['package_manager'] = stack['package_manager'] or 'go modules'

    gomod = os.path.join(project_dir, 'go.mod')
    with open(gomod) as f:
        go_text = f.read().lower()
    if 'gin-gonic' in go_text:
        stack['framework'].append('Gin')
    if 'go-chi' in go_text or 'chi/v5' in go_text:
        stack['framework'].append('Chi')
    if 'echo' in go_text and 'labstack' in go_text:
        stack['framework'].append('Echo')
    if 'fiber' in go_text:
        stack['framework'].append('Fiber')

# --- Docker ---
if os.path.isfile(os.path.join(project_dir, 'Dockerfile')) or os.path.isfile(os.path.join(project_dir, 'docker-compose.yml')) or os.path.isfile(os.path.join(project_dir, 'docker-compose.yaml')):
    stack['build_tool'].append('Docker')

# --- Output ---
if not stack['language']:
    print('detected=false')
    sys.exit(0)

print('detected=true')
print('language=' + ', '.join(stack['language']))
if stack['framework']:
    print('framework=' + ', '.join(stack['framework']))
if stack['package_manager']:
    print('package_manager=' + stack['package_manager'])
if stack['test_framework']:
    print('test_framework=' + ', '.join(stack['test_framework']))
if stack['build_tool']:
    print('build_tool=' + ', '.join(stack['build_tool']))
" "$PROJECT_DIR"
