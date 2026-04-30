---
stack: python
detect:
  - pyproject.toml
  - requirements.txt
  - setup.py
  - "**/*.py"
priority: high
---

## Forbidden
- Bare `except:` clauses (catch specific exceptions)
- Mutable default arguments (`def f(x=[])`)
- `from module import *` outside __init__.py
- print() for diagnostics in libraries (use logging)
- shell=True in subprocess unless input is fully controlled

## Toolchain
- test: pytest
- lint: ruff check
- format: ruff format
- typecheck: mypy

## Pitfalls
- f-strings over .format() and % formatting
- pathlib.Path over os.path string manipulation
- context managers (`with`) for files, locks, connections
- type hints on public APIs
- dataclasses or pydantic over plain dicts for structured data
