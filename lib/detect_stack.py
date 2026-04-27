#!/usr/bin/env python3
"""Claude Supercharger — Shared Stack Detection Library.

Usage as module:
    from detect_stack import detect_stack
    stack = detect_stack('/path/to/project')  # returns dict

Usage as script:
    python3 detect-stack.py /path/to/project  # prints JSON
"""

import json
import os


def detect_stack(project_dir):
    """Detect project stack from filesystem signals.

    Returns dict with keys:
        detected      bool
        language      list[str]
        framework     list[str]
        package_manager  str | None
        test_framework   list[str]
        build_tool    list[str]
    """
    stack = {
        'detected': False,
        'language': [],
        'framework': [],
        'package_manager': None,
        'test_framework': [],
        'build_tool': [],
    }

    def path(*parts):
        return os.path.join(project_dir, *parts)

    def exists(*parts):
        return os.path.isfile(path(*parts))

    # --- Node.js / JavaScript / TypeScript ---
    if exists('package.json'):
        try:
            with open(path('package.json')) as f:
                pkg = json.load(f)
            deps = {}
            deps.update(pkg.get('dependencies', {}))
            deps.update(pkg.get('devDependencies', {}))

            if 'typescript' in deps or exists('tsconfig.json'):
                stack['language'].append('TypeScript')
            else:
                stack['language'].append('JavaScript')

            for dep, name in [
                ('next', 'Next.js'), ('nuxt', 'Nuxt'), ('react', 'React'),
                ('vue', 'Vue'), ('svelte', 'Svelte'), ('@sveltejs/kit', 'SvelteKit'),
                ('express', 'Express'), ('fastify', 'Fastify'), ('hono', 'Hono'),
                ('@nestjs/core', 'NestJS'), ('astro', 'Astro'), ('remix', 'Remix'),
                ('@angular/core', 'Angular'), ('solid-js', 'SolidJS'), ('gatsby', 'Gatsby'),
            ]:
                if dep in deps:
                    stack['framework'].append(name)

            for dep, name in [
                ('jest', 'Jest'), ('vitest', 'Vitest'), ('mocha', 'Mocha'),
                ('@playwright/test', 'Playwright'), ('cypress', 'Cypress'),
            ]:
                if dep in deps:
                    stack['test_framework'].append(name)

            for dep, name in [
                ('vite', 'Vite'), ('webpack', 'Webpack'), ('esbuild', 'esbuild'),
                ('turbo', 'Turborepo'), ('tsup', 'tsup'), ('rollup', 'Rollup'),
            ]:
                if dep in deps:
                    stack['build_tool'].append(name)

        except (json.JSONDecodeError, IOError):
            stack['language'].append('JavaScript')

    # Package manager detection (JS + Python)
    for lockfile, pm in [
        ('pnpm-lock.yaml', 'pnpm'),
        ('yarn.lock', 'yarn'),
        ('bun.lockb', 'bun'),
        ('bun.lock', 'bun'),
        ('package-lock.json', 'npm'),
    ]:
        if exists(lockfile):
            stack['package_manager'] = pm
            break

    # --- Python ---
    py_markers = ['requirements.txt', 'setup.py', 'setup.cfg', 'pyproject.toml']
    if any(exists(f) for f in py_markers):
        if 'Python' not in stack['language']:
            stack['language'].append('Python')

        dep_text = ''
        for fname in ['requirements.txt', 'pyproject.toml']:
            if exists(fname):
                try:
                    with open(path(fname)) as f:
                        dep_text += f.read().lower()
                except IOError:
                    pass

        for kw, name in [
            ('django', 'Django'), ('fastapi', 'FastAPI'), ('flask', 'Flask'),
            ('starlette', 'Starlette'), ('tornado', 'Tornado'), ('aiohttp', 'aiohttp'),
        ]:
            if kw in dep_text and name not in stack['framework']:
                stack['framework'].append(name)

        for kw, name in [
            ('pytest', 'pytest'), ('unittest', 'unittest'), ('nose', 'nose'),
        ]:
            if kw in dep_text and name not in stack['test_framework']:
                stack['test_framework'].append(name)

        if not stack['package_manager']:
            for lockfile, pm in [
                ('uv.lock', 'uv'), ('poetry.lock', 'poetry'),
                ('Pipfile.lock', 'pipenv'), ('requirements.txt', 'pip'),
            ]:
                if exists(lockfile):
                    stack['package_manager'] = pm
                    break

    # --- Rust ---
    if exists('Cargo.toml'):
        stack['language'].append('Rust')
        stack['package_manager'] = stack['package_manager'] or 'cargo'
        try:
            with open(path('Cargo.toml')) as f:
                cargo_text = f.read().lower()
            for kw, name in [('actix', 'Actix'), ('axum', 'Axum'), ('rocket', 'Rocket')]:
                if kw in cargo_text:
                    stack['framework'].append(name)
            if 'tokio' in cargo_text:
                stack['build_tool'].append('Tokio')
        except IOError:
            pass

    # --- Go ---
    if exists('go.mod'):
        stack['language'].append('Go')
        stack['package_manager'] = stack['package_manager'] or 'go modules'
        try:
            with open(path('go.mod')) as f:
                go_text = f.read().lower()
            for kw, name in [
                ('gin-gonic', 'Gin'), ('go-chi', 'Chi'), ('chi/v5', 'Chi'),
                ('fiber', 'Fiber'),
            ]:
                if kw in go_text:
                    stack['framework'].append(name)
            if 'echo' in go_text and 'labstack' in go_text:
                stack['framework'].append('Echo')
        except IOError:
            pass

    # --- PHP ---
    if exists('composer.json'):
        stack['language'].append('PHP')
        stack['package_manager'] = stack['package_manager'] or 'composer'

    # --- WordPress ---
    if exists('wp-config.php') or exists('functions.php'):
        if 'PHP' not in stack['language']:
            stack['language'].append('PHP')
        if 'WordPress' not in stack['framework']:
            stack['framework'].append('WordPress')

    # --- Docker ---
    if any(exists(f) for f in ['Dockerfile', 'docker-compose.yml', 'docker-compose.yaml']):
        if 'Docker' not in stack['build_tool']:
            stack['build_tool'].append('Docker')

    stack['detected'] = bool(stack['language'])
    return stack


if __name__ == '__main__':
    import sys
    project_dir = sys.argv[1] if len(sys.argv) > 1 else '.'
    print(json.dumps(detect_stack(os.path.abspath(project_dir))))
