---
stack: go
detect:
  - go.mod
  - "**/*.go"
priority: high
---

## Forbidden
- Ignored errors (`_ = err`) outside justified cases
- Naked returns in long functions
- panic() in library code (return error)
- Global mutable state without sync
- Empty interface (`interface{}` / `any`) where concrete type fits

## Toolchain
- test: go test ./...
- lint: golangci-lint run
- vet: go vet ./...
- format: gofmt -w

## Pitfalls
- Wrap errors with %w for unwrapping: `fmt.Errorf("op: %w", err)`
- Defer cleanup immediately after acquisition
- Channels: close from sender, never receiver
- Goroutine leaks: ensure cancellation context propagates
- Slice gotchas: append may share underlying array
