# Canary Test Requirement for Filter-Schema Additions — Implementation Plan

**Spec**: [Spec file](./1_606-canary-test-filter-schema_specs.md)
**Smoke test runbook**: [Smoke test runbook](../../../testing/workflow/606-canary-test-filter-schema.smoke-test.md)

---

## Summary

**Approach**: Add a conditional canary-test checklist item to the developer-agent implementation protocol (applies whenever a PR adds a new filter to a tool schema), a blocking review check to `REVIEW.md` (for the code-reviewer gate), and a canary-test rule to the general testing best-practices document. The agent guidance files for the developer role (Claude Code and Cursor) each contain inline key rules derived from the protocol and must also be updated for consistency.

**Estimated complexity**: S

**Rationale**: All changes are documentation only — prose additions to three existing protocol/best-practice files plus two thin agent-wrapper files. No scripts, no schema migrations, no new tooling. The rule text is well-defined by the spec; the only implementation work is locating the correct insertion points and writing consistent prose.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `5c237c4` |
| Files referencing `03-implement-development-protocol` in agent/skill files | `grep -rl "03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/` | `.claude/agents/developer.md`, `.cursor/agents/developer.md` (Codex skill defers to protocol via reference only, no inline key rules) |
| Existing canary / filter-schema text in target files | `grep -rn "canary\|filter.*schema\|schema.*filter" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md REVIEW.md docs/best-practices/3-testing.md .claude/agents/developer.md .cursor/agents/developer.md` | 0 matches — no prior canary or filter-schema rule exists in any target file |
| Pre-PR checklist section headers in protocol 03 | `grep -n "Pre-Implementation Scope Checklist\|Pre-Commit\|Test Harness" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Lines 258, 341, 589, 614, 799, 822, 1024, 1045 — all four paths have a `Step 5: Pre-Commit Verification` or equivalent; the canary-test check belongs here as a conditional item mirroring the `Test Harness Coverage Checklist` pattern |
| Code Review Checklist section in REVIEW.md | `grep -n "Pass 2\|Code Quality\|Additional checks" REVIEW.md` | Lines 176–213 — Pass 2 contains all additional per-PR-type checks; canary check goes here |

---

## Layer-by-Layer Changes

### Documentation / Protocol Layer

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — add a conditional canary-test pre-commit check (a new named subsection mirroring the `Test Harness Coverage Checklist` pattern) that fires whenever a PR adds a new filter parameter to a tool schema. The check must appear in **every path's Step 5 / Verify section** (Path 1 Full Pipeline Step 5, Path 2 Refactor Step 5, Path 3 Fast Track Step 4/5, Path 4 Hotfix Step 5) or, preferably, as a single shared section placed before Path 1 like the existing `Test Harness Coverage Checklist`, with each path's verify step referencing it.
- [ ] `REVIEW.md` — add a blocking check to **Pass 2: Code Quality** section: when a PR adds a new filter parameter to a tool schema, the reviewer must verify a canary test is present demonstrating the filter alters the result set. Add under "Additional checks" pattern, after the existing per-category blocks.
- [ ] `docs/best-practices/3-testing.md` — add a new subsection "Filter-Schema Canary Tests" under `## What to Test → Always test:` (or as a new top-level subsection) documenting the canary test rule: any accepted query filter must have a test proving it affects results.
- [ ] `.claude/agents/developer.md` — add a single bullet to the `Key rules:` list summarising the canary-test obligation (mirrors the existing pattern for other protocol rules kept inline in the agent file).
- [ ] `.cursor/agents/developer.md` — same update as `.claude/agents/developer.md` (the two files are kept in sync).

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Read `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` and confirm a canary-test section or conditional check exists that fires on filter-schema additions — maps to AC-1.
2. Read `REVIEW.md` and confirm the code-review checklist includes a blocking check for missing canary tests on filter-schema PRs — maps to AC-2.
3. Read `docs/best-practices/3-testing.md` and confirm the canary test rule is present — maps to AC-3.
4. Confirm the two-invocation-plus-assertion pattern is described and satisfies the requirement regardless of language or framework — maps to AC-4.
5. Confirm the text explicitly states that a missing canary test is a blocking code-review finding — maps to AC-5.
6. Confirm the exemption for modifications to existing filters (no schema-contract change) is stated — maps to AC-6 (BR-7).

**Smoke test runbook**: `docs/testing/workflow/606-canary-test-filter-schema.smoke-test.md`

---

## Seed Data

None — documentation-only change.

---

## Documentation Updates

None — the documentation files themselves are the deliverable. No additional project docs need updating after implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Cross-section inconsistency between protocol 03 and REVIEW.md (different wording for same rule) | Med | Med | Write both sections in one pass; cross-read both before committing |
| Developer agent key-rules list grows unwieldy | Low | Low | Keep the bullet concise (one sentence); link to protocol 03 for the full rule |
| The check is placed in only some paths in protocol 03, silently missing others | Med | High | Prefer a single shared section (before Path 1, matching `Test Harness Coverage Checklist`), referenced from each path's verify step |

---

## Code Samples

All content below is illustrative — adapt during implementation.

### Canary-test checklist item (for protocol 03)

```markdown
**Filter-Schema Canary Test (conditional — applies when this PR adds a new filter parameter
to a tool schema)**: If your PR adds one or more new filter parameters to a tool schema
(Zod, JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism),
verify that each new filter has a canary test before opening the PR:

- [ ] A canary test is present for each newly added filter.
- [ ] The canary test calls the tool with the new filter set to a value that narrows or
  alters the result set, and calls the tool again with the filter absent or set to a
  meaningfully different value.
- [ ] The canary test asserts that the two result sets differ.
- [ ] The test data is designed so the filter has an observable effect (not identical
  results for both invocations).
- [ ] If a canary test is impractical (e.g., no test fixtures, no in-memory DB), document
  the constraint explicitly in the PR and propose an alternative verification approach —
  silence is not acceptable.
- [ ] The canary test is included in the same PR as the filter addition (not deferred).

This requirement applies to **new** filter parameters only. Modifying or removing an
existing filter parameter without changing the schema contract does not trigger this
obligation.
```

### Blocking check (for REVIEW.md — Pass 2: Code Quality)

```markdown
Additional checks for **PRs that add new filter parameters to a tool schema** (Zod,
JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism):

- **Filter-wiring verification**: confirm the new filter is wired to the query builder's
  WHERE clause or equivalent filter-application function — not only declared in the schema.
- **Canary test presence**: confirm a canary test is present that calls the tool with the
  new filter set to a value that narrows results, calls the tool again without the filter
  (or with a meaningfully different value), and asserts the two result sets differ. A
  canary test that produces identical results for both invocations does not satisfy this
  requirement.
- **Same-PR inclusion**: confirm the canary test is part of this PR, not deferred.
- **Exemption**: this check applies to new filter parameters only. Modifications to
  existing filter parameters that do not change the schema contract are exempt.
```

### Testing best-practices addition (for `docs/best-practices/3-testing.md`)

```markdown
## Filter-Schema Canary Tests

Any PR that adds a new filter parameter to a tool schema (Zod, JSON Schema, Joi, Pydantic,
OpenAPI, or any equivalent contract-declaration mechanism) **must include a canary test** for
each added filter before it may be merged.

**What a canary test must do**:

1. Call the tool with the new filter set to a value that narrows or alters the result set.
2. Call the tool again with the filter absent or set to a meaningfully different value.
3. Assert that the two result sets differ.

**Why**: A filter added to a schema is accepted by the API but may not be wired to the query
builder's WHERE clause. Without a canary test, this silent no-op reaches production undetected.

**Exemption**: Modifying or removing an existing filter parameter without changing the schema
contract does not trigger the canary obligation, though confirming existing tests still pass is
encouraged.

**Framework-agnostic**: The requirement is satisfied regardless of language or test framework.
The substance — two invocations, differing results — is what matters.
```

---

## Implementation Order

1. **Add the canary-test shared section to `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`**: Place a new named section "Filter-Schema Canary Test Checklist" immediately after the existing "Test Harness Coverage Checklist" section (before "Path 1: Full Pipeline"). The section is conditional — it fires when "this PR adds a new filter parameter to a tool schema." Then add a one-line cross-reference to this section in each path's verify step (Path 1 Step 5, Path 2 Step 5, Path 3 Step 4/5, Path 4 Step 5), matching the pattern used for "Test Harness Coverage Checklist" cross-references. Verify: open the file and confirm the section heading appears once, each path verify step contains the cross-reference, and the six checklist items from AC-1 and BR-2/BR-4/BR-5/BR-7 are covered.

2. **Add the blocking check to `REVIEW.md` — Pass 2: Code Quality**: Add the new "Additional checks for PRs that add new filter parameters to a tool schema" block after the existing "Additional checks for documentation PRs" block (before the "Additional checks for shell scripts" block). Verify: open the file and confirm the block appears once in Pass 2, covers filter-wiring, canary test presence, same-PR inclusion, and the exemption.

3. **Add the "Filter-Schema Canary Tests" section to `docs/best-practices/3-testing.md`**: Place as a new top-level section after the "Smoke Tests" section. Verify: open the file and confirm the section appears once with the three-step pattern, the "why" rationale, the exemption, and the framework-agnostic note.

4. **Add a key-rule bullet to `.claude/agents/developer.md`**: Add to the `Key rules:` list: "When a PR adds a new filter parameter to a tool schema (Zod, JSON Schema, or equivalent), include a canary test for each new filter — two invocations (filter set vs. absent/different), assert results differ — before opening the PR; see the Filter-Schema Canary Test Checklist in `03-implement-development-protocol.md`". Verify: open the file and confirm the bullet appears in the key rules list.

5. **Apply the same key-rule bullet to `.cursor/agents/developer.md`**: Mirror step 4 exactly. Verify: the two developer agent files have identical canary-test bullet text.

6. **Cross-section consistency self-check**: After writing all five files, re-read each one and verify:
   - The exemption (modifications to existing filters, no schema-contract change) is stated consistently in all five files.
   - The two-invocation-plus-assertion pattern is described consistently (call with filter set → call with filter absent/different → assert results differ).
   - "Blocking" language appears in `REVIEW.md` and in the protocol 03 section; "conditional" language appears in the protocol 03 section header.

7. **Pre-commit lint check**: Run `markdownlint-cli2` on all modified files before staging:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260518000000_606-canary-test-filter-schema/2_606-canary-test-filter-schema_implementation-plan.md" \
     "docs/testing/workflow/606-canary-test-filter-schema.smoke-test.md" \
     "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
     "REVIEW.md" \
     "docs/best-practices/3-testing.md" \
     ".claude/agents/developer.md" \
     ".cursor/agents/developer.md"
   ```

   Fix all reported violations before committing.

8. **Update `CHANGELOG.md`** under `[Unreleased]`: Add under `### Added`:

   ```markdown
   - **Add canary test requirement for filter-schema additions** (#606): developer-agent protocol, code-reviewer contract, and testing best-practices now require a canary test (two-invocation, assert-results-differ pattern) for every new filter parameter added to a tool schema; the check is a blocking code-review finding when absent.
   ```
