Generate unit tests for: $ARGUMENTS

Read the target file first. Detect the test framework in use (jest, vitest, pytest, go test, cargo test, etc.) from config files (package.json, pyproject.toml, Cargo.toml, go.mod) and existing test files. Match any existing test patterns in the project.

**Coverage requirements:**
- **Happy path** — expected inputs produce expected outputs
- **Edge cases** — empty, null/nil, zero, boundary values, large inputs
- **Error handling** — invalid inputs, thrown errors, rejected promises, panics

**Before writing:**
1. Read the target file — understand what each function/method does
2. Scan for existing test files in the project — match their structure, naming, and import style
3. Identify which functions are exported/public — those are the primary test targets

**Test quality rules:**
- One assertion focus per test — tests should have a single reason to fail
- Descriptive test names — state what the function does under what condition
- No mocks unless the code has external I/O — prefer real implementations for pure logic
- Arrange / Act / Assert structure within each test

**Output format:**
```
## FRAMEWORK DETECTED
[framework + version if found]

## TEST FILE
[path where this file should be saved — follow project conventions]

[full test file contents]

## COVERAGE SUMMARY
- Happy path: [N tests]
- Edge cases: [N tests]
- Error handling: [N tests]
- Skipped (needs mock/integration setup): [list if any]
```

After writing, run the tests and report pass/fail. If tests fail due to code bugs (not test bugs), note them — do not silently fix the source file.
