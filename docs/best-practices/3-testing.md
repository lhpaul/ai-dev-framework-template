# Testing Best Practices

## Testing Strategy

The testing strategy for this project — tools, tiers, when each runs, and how they relate — belongs in:

> `docs/project/3-software-architecture.md` → **Testing Strategy** section

Define it there during project setup. This file covers principles and conventions that apply regardless of which tier or tool you are working with.

## General Principles

- **Test behavior, not implementation** — tests should break when the behavior changes, not when the code is refactored
- **Readable tests are as important as readable code** — a test is documentation
- **One assertion per test** when possible — makes failures easier to diagnose
- **Tests must be deterministic** — a test that sometimes passes and sometimes fails is worse than no test
- **Don't delete tests to make the build pass** — fix the root cause

## What to Test

### Always test:
- Business logic and domain rules
- Edge cases (empty lists, null values, boundary conditions)
- Error handling paths (what happens when a dependency fails)

### Test selectively:
- Integration with external services (use mocks/stubs at the boundary)
- UI components (test interaction, not styling)

### Don't over-test:
- Simple getters/setters with no logic
- Framework code or third-party library internals
- Implementation details that may change during refactoring

## Smoke Tests

Smoke tests validate key user journeys in a running environment. They are defined in runbooks:

```
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

See the [smoke test runbook template](../ai/development-workflow/templates/smoke-test-runbook-template.md) for the standard format, and [docs/testing/README.md](../testing/README.md) for how to execute them in this repo.

Smoke tests should be run:
- Before every release
- After deploying to staging
- When investigating a reported production issue

The recommended approach is a **two-tier execution model**: a committed automated test suite (preferred) with ad-hoc scripts as a fallback when no spec exists yet. See `docs/project/3-software-architecture.md` → Testing Strategy.

## Test Data and Seed Data

- Tests that require data should use deterministic seed data, not random values
- Seed data should cover all scenarios, roles, and statuses (see `docs/project/4-database-model.md`)
- Never use production data in tests

## Running Tests

```bash
# Run all tests
[command]

# Run a specific test file
[command path/to/test]

# Run tests in watch mode
[command --watch]
```

## CI Integration

All tests run automatically on every pull request. A PR cannot be merged if:
- Any test fails
- Test coverage drops below the configured threshold (if applicable)
