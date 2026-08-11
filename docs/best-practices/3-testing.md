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

See the [smoke test runbook template](../workflow/development-workflow/templates/smoke-test-runbook-template.md) for the standard format, and [docs/testing/README.md](../testing/README.md) for how to execute them in this repo.

Smoke tests should be run:

- Before every release
- After deploying to staging
- When investigating a reported production issue

The recommended approach is a **two-tier execution model**: a committed automated test suite (preferred) with ad-hoc scripts as a fallback when no spec exists yet. See `docs/project/3-software-architecture.md` → Testing Strategy.

## Filter-Schema Canary Tests

Any PR that adds a new filter parameter to a tool schema (Zod, JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism) **must include a canary test** for each added filter before it may be merged.

**What a canary test must do**:

1. Call the tool with the new filter set to a value that narrows or alters the result set.
2. Call the tool again with the filter absent or set to a meaningfully different value.
3. Assert that the two result sets differ.

**Why**: A filter added to a schema is accepted by the API but may not be wired to the query builder's WHERE clause. Without a canary test, this silent no-op reaches production undetected.

**Exemption**: Modifying or removing an existing filter parameter without changing the schema contract does not trigger the canary obligation, though confirming existing tests still pass is encouraged.

**Framework-agnostic**: The requirement is satisfied regardless of language or test framework. The substance — two invocations, differing results — is what matters.

## Planted-Violation Proofs

Any PR that adds or materially modifies an automated check, guard, lint rule, or CI job **must prove it catches the violation it targets** before it may be merged. This mirrors and generalizes the Filter-Schema Canary Test requirement above beyond filter parameters.

**What a planted-violation proof must do**:

1. Plant the violation the check is meant to catch at a concrete file and line (a real or minimal representative example).
2. Run the check and show it fails against the planted violation, citing the file and line.
3. Remove the violation and run the check again, showing it now passes.

**Why**: A check that is declared but never exercised against a real failure case can silently do nothing — passing every PR by coincidence rather than by validation. Proving both directions (fails-when-present, passes-when-absent) is the only way to confirm a control actually works. This discipline traced multiple real defects during framework hardening work, including a base-10 parsing bug and destructive reset logic that a description-only review pass missed.

**Exemption**: Pure refactors of already-proven validation logic, with no behavior change, are exempt from re-proof; state the exemption rationale in the PR.

See `REVIEW.md` → Code Review Checklist → Pass 2 → "PRs that add or modify an automated check, guard, lint rule, or CI job" for the reviewer-facing enforcement of this rule.

For a worked instance of this rule — a regex-based key-extraction scanner, its full edge-case table, and a named dynamic-key concatenation gap (`t('x.' + k)`) that a naive first version missed and a fix closed with documented regression cases — see [`docs/best-practices/stack/i18n.md` § Key-extraction scanner and the dynamic-key pitfall](stack/i18n.md#key-extraction-scanner-and-the-dynamic-key-pitfall).

## Test Data and Seed Data

- Tests that require data should use deterministic seed data, not random values
- Seed data should cover all scenarios, roles, and statuses (see `docs/project/4-database-model.md`)
- Never use production data in tests

### E2E Fixture Contract

When this repository has a committed, non-placeholder E2E/functional test suite (i.e., `docs/testing/README.md` Section 2's committed-spec path is filled in and the E2E CI job runs real tests, not a template placeholder), every feature PR extends the suite's seed/fixture data with that feature's edge cases in the same PR — keeping the functional suite able to reach the new states the feature introduces.

The fixture's initial state must be **deterministic and versioned**: rebuilding it from the same seed inputs produces a byte-identical result, and the fixture change ships in the same PR as the code change it supports (not a manual, undocumented data edit).

**Not applicable** when no committed E2E suite exists yet (e.g., this template's placeholder `E2E regression (placeholder)` CI job, before a real suite replaces it) — record the not-applicable rationale explicitly rather than silently skipping the check. Once a real suite exists, this requirement is active: extend the fixture in the same PR rather than silently skipping fixture work.

See `REVIEW.md` → Code Review Checklist → Pass 2 → "PRs that add a feature (when a committed E2E suite exists)" for the reviewer-facing enforcement of this rule.

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
