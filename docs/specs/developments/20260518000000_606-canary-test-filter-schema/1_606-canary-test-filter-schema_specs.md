# Canary Test Requirement for Filter-Schema Additions — Spec

---

## Overview

This feature adds a mandatory workflow rule requiring a canary test whenever a new filter is added to a tool schema. The rule targets a recurring silent-failure bug class: a filter added to a schema (Zod, JSON Schema, or equivalent) is accepted by the API but never wired to the query builder's WHERE clause, causing it to no-op without any error or warning. Three confirmed instances of this bug class were observed in downstream projects (RAD-118, RAD-130, RAD-143) before this rule existed. The rule will be embedded in the developer-agent implementation checklist, the code-reviewer review contract (`REVIEW.md`), and the general testing best-practices document so every downstream project benefits from this protection at all three enforcement points.

---

## Use Cases

### Use Case 1: Developer adds a new filter to a tool schema

**Actor**: Developer (or developer-agent) implementing a feature or fix that extends a tool's accepted filter parameters.

**Preconditions**: The developer has added or is about to add a new query filter to a tool schema (Zod, JSON Schema, or equivalent contract). The tool delegates query construction to a separate query builder or WHERE-clause builder that must be updated independently of the schema declaration.

**Steps**:

1. Developer adds the new filter to the schema definition.
2. Developer wires the filter to the query builder's WHERE clause or equivalent filter-application function.
3. Developer writes a canary test that:
   a. Calls the tool with the new filter set to a specific, non-null value that should visibly narrow the result set.
   b. Calls the tool with the filter absent or set to a different value.
   c. Asserts that the two result sets differ.
4. Developer runs the canary test and confirms it passes with both the schema declaration and the WHERE-clause wiring in place.
5. Developer includes the canary test in the same PR as the filter addition.

**Postconditions**: The PR includes a passing canary test demonstrating that the filter actively changes query results. If the WHERE-clause wiring is missing or incorrect, the canary test fails and blocks the PR.

**Information shown**: Test output showing two distinct result sets for the two filter invocations.

**Actions available**: Proceed with the PR; the canary test acts as living documentation of the filter's effect.

**Considerations**:

- If the tool's data layer makes it difficult to write a canary test (e.g., no test fixtures, no in-memory DB), the developer must note this explicitly and propose an alternative verification approach for human reviewer approval. Silence is not acceptable.
- A canary test that always passes because the test data is identical for both invocations does not satisfy the requirement; the test data must be designed so the filter has an observable effect.
- When multiple filters are added in a single PR, each filter requires its own canary assertion (they may share a single test function or be grouped in a parameterized test).

---

### Use Case 2: Code reviewer checks a PR that adds a filter to a schema

**Actor**: Code reviewer (human or code-reviewer agent) evaluating a PR that adds or modifies filter parameters in a tool schema.

**Preconditions**: A PR is open that includes a change to a tool schema adding one or more filter parameters.

**Steps**:

1. Reviewer scans the PR diff for additions to any tool schema file (Zod schema, JSON Schema, OpenAPI spec, or equivalent).
2. Reviewer checks whether the filter is wired to the query builder's WHERE clause or filter-application function.
3. Reviewer checks whether a canary test is present in the PR that asserts the filter changes results between two distinct invocations.
4. If either the wiring or the canary test is absent, reviewer raises a blocking finding.
5. If both are present, reviewer confirms the canary test is correctly structured (two distinct invocations, result-set comparison, data designed so the filter has an observable effect).

**Postconditions**: PRs with unwired filters or missing canary tests are blocked from merging. PRs with correctly wired and tested filters proceed.

**Information shown**: Review comment citing the specific schema change and the missing wiring or canary test.

**Actions available**: Reject (request changes) if canary test or wiring is absent; approve if both are present and correctly structured.

**Considerations**:

- The reviewer should not require a specific test framework or assertion style; the substance (two invocations, differing results) is what matters.
- If the PR author provided a documented exception (e.g., no test fixture support), the reviewer evaluates the proposed alternative and may approve with a note.

---

## Business Rules

- BR-1: Any PR that adds one or more new filter parameters to a tool schema MUST include a canary test for each added filter before it may be merged.
- BR-2: A canary test satisfies the requirement if and only if it: (a) calls the tool with the filter set to a value that should narrow or alter the result set, (b) calls the tool with the filter absent or set to a meaningfully different value, and (c) asserts the two result sets differ.
- BR-3: A filter that produces identical results for both invocations is a canary-test failure. The developer must fix either the test data or the filter wiring before the PR may proceed.
- BR-4: The canary test must be included in the same PR as the filter addition. It may not be deferred to a follow-up PR.
- BR-5: This rule applies to all tool-schema filter additions regardless of the language or schema library in use (Zod, JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism).
- BR-6: The rule applies to the template's developer-agent implementation checklist, the code-reviewer review contract (`REVIEW.md`), and the general testing best-practices document. All three documents must be updated in the implementation PR.
- BR-7: The canary requirement applies to new filter parameters only. Modifying or removing an existing filter parameter without changing the schema contract does not trigger the canary obligation, though the developer is encouraged to confirm existing tests still pass.

---

## Acceptance Criteria

- [ ] The developer-agent implementation checklist (in `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` or the pre-PR checklist section) includes a mandatory item: when a PR adds a new filter to a tool schema, a canary test must be present that confirms the filter changes results between two distinct invocations.
- [ ] The code-reviewer review contract (`REVIEW.md`) includes a blocking check: for any PR that adds a new filter parameter to a tool schema, the reviewer must verify that a canary test is present demonstrating the filter alters the result set.
- [ ] The general testing best-practices document (`docs/best-practices/3-testing.md` or equivalent) includes the canary test rule: any accepted query filter must have a test proving it affects results.
- [ ] A developer who writes a canary test following the two-invocation-plus-assertion pattern defined in BR-2 satisfies the requirement regardless of language or test framework.
- [ ] A developer who adds a filter without a canary test, or with a canary test that cannot demonstrate the filter changes results, is blocked from merging by the code-review gate.
- [ ] The rule explicitly exempts modifications to existing filters that do not change the schema contract (BR-7).

---

## Out of Scope (MVP)

- Automated static analysis or CI tooling that detects unwired filter parameters at build time — this is a testing-convention rule enforced by review, not a lint-time check.
- Retrofitting canary tests for existing filters that predate this rule — only new additions (in PRs after this rule lands) are covered.
- Prescribing a specific test framework, assertion library, or test-file naming convention — the rule is framework-agnostic.
- Rules for non-query-builder patterns such as in-memory filtering, client-side filters, or read-model projections — those are out of scope unless they follow the same schema-declaration-plus-separate-application pattern.
- Detecting which specific downstream projects are affected or coordinating retroactive fixes across them — this is a forward-looking prevention rule only.
