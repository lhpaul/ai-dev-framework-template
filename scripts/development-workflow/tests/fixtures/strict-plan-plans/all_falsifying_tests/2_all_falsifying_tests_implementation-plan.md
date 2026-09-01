# Plan

**Spec**: [spec](./1_all_falsifying_tests_specs.md)

## Steps

1. Implement single dispatch (AC-1).
2. Emit STRICT_PLAN_APPLIED (AC-2).

## Tests

- AC-1: assert exactly one strict invocation in harness (fails if zero or two).
- AC-2: grep STRICT_PLAN_APPLIED in reviewer output (fails if absent).
