---
stack: php
detect:
  - composer.json
  - "**/*.php"
priority: high
---

## Forbidden
- `eval()` on any input (almost never necessary)
- `extract()` on user-supplied arrays (variable injection)
- `mysqli_query`/`mysql_*` without prepared statements
- `==` comparison when `===` is correct (type juggling)
- `error_reporting(0)` or `@` to silence errors in production paths

## Toolchain
- test: phpunit
- lint: phpcs --standard=PSR12
- analyze: phpstan analyse (level 6+) or psalm
- format: php-cs-fixer fix

## Pitfalls
- Type juggling: `"0" == false` is true, `"abc" == 0` was true pre-PHP 8
- Array vs object access: `$x['key']` vs `$x->key` — distinct, not interchangeable
- Autoloader paths: PSR-4 namespace must match directory exactly (case-sensitive)
- `null` propagation: use `?->` (PHP 8) and null coalescing `??`
- Production: disable `display_errors`, log via error_log or monolog instead
