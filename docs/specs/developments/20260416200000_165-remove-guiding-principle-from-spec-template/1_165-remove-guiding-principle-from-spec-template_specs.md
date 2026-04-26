# Remove Boilerplate 'Guiding Principle' Section from Spec Template — Spec

**Depends on**: <!-- None -->

---

## Overview

The spec template and all generated spec documents currently include a verbatim "Guiding principle (important)" section that is addressed to the spec author or agent, not to a reader of the finished spec. The same paragraph is repeated in every merged spec file, adding dead-weight text without adding information. The same guidance already exists in the spec generation protocol. This fix removes the section from the template (and from existing spec files) and consolidates the authoring guidance into the protocol document where it belongs.

---

## Use Cases

### Use Case 1: Agent or Developer Generates a New Spec

**Actor**: Product Manager agent or developer running the spec generation protocol
**Preconditions**: A new backlog item has been promoted to "Writing Spec" status; the spec template is loaded as the starting point

**Steps**:
1. The agent reads `01-generate-spec-protocol.md` to understand what belongs in a spec and what does not.
2. The agent opens `spec-template.md` and fills in the required sections.
3. The agent writes the spec document without including any author-addressed instructional boilerplate.
4. The agent commits the spec file and opens a draft PR.

**Postconditions**: The generated spec contains only product-facing content (overview, use cases, business rules, UX rules, acceptance criteria, out-of-scope, open questions) — no instructional preamble addressed to the author.

**Information shown**:
- A spec file containing the feature's actual content
- No "Guiding principle" or equivalent author-instruction section

**Actions available**:
- Review the spec for completeness against the checklist in `REVIEW.md`
- Proceed to the implementation plan stage

**Considerations**:
- The guidance that was previously in the "Guiding principle" section is retained in `01-generate-spec-protocol.md` so agents and developers writing specs can still reference it
- The `REVIEW.md` spec checklist verifies substance (no implementation-detail leakage), not the presence of a boilerplate section

---

### Use Case 2: Reviewer Reviews a Spec PR

**Actor**: Internal spec reviewer (claude) or automated reviewer (Devin, CodeRabbit) running against `REVIEW.md`
**Preconditions**: A spec PR is open and the draft has been marked ready for review

**Steps**:
1. The reviewer reads the spec against the `REVIEW.md` spec checklist.
2. The reviewer checks that the spec is product-focused: no table names, endpoints, file paths, class names, or migration design.
3. The reviewer approves or requests revisions based on substance, not on the presence of a template preamble section.

**Postconditions**: The review result is based on actual content quality.

**Information shown**:
- Review findings (if any) that describe substantive content issues

**Actions available**:
- Approve or request revisions

**Considerations**:
- Automated reviewers (e.g., Devin) must not flag the absence of a "Guiding principle" section as a finding because the updated template and review checklist do not require it
- The "Guiding principle" section is intentionally removed; a reviewer seeing it absent must treat that as correct, not as a missing required section

---

## Business Rules

- The spec template (`docs/workflow/development-workflow/templates/spec-template.md`) must not contain any section addressed to the author or agent that a reader of the finished spec would gain nothing from.
- The authoring guidance ("this stage is product-focused: write user-facing behavior, avoid implementation details") must be present in `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` so agents generating specs can reference it.
- The `REVIEW.md` spec checklist must enforce implementation-detail cleanliness on substance, not on the presence of a named boilerplate section.
- Existing merged spec files that still contain the "Guiding principle" section must be updated to remove it, keeping the remaining content intact.

---

## Acceptance Criteria

- [ ] `docs/workflow/development-workflow/templates/spec-template.md` no longer contains the "Guiding principle (important)" section.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` contains the "product-focused" authoring guidance (verbatim or equivalent) so that spec authors and agents generating specs can reference it.
- [ ] `REVIEW.md` spec checklist does not require the "Guiding principle" section to be present; instead it checks that the spec does not contain implementation details (table names, endpoints, file paths, class names, migration design).
- [ ] All existing spec files that contain the "Guiding principle" section have it removed:
  - `docs/specs/developments/20260413201328_retrospective-protocol/1_retrospective-protocol_specs.md`
  - `docs/specs/developments/20260414184900_batch-merge/1_batch-merge_specs.md`
  - `docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`
  - `docs/specs/developments/20260416120000_agent-timeout-handling/1_agent-timeout-handling_specs.md`
  - `docs/specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md`
  - `docs/specs/developments/20260416120000_coderabbit-success-fallback/1_coderabbit-success-fallback_specs.md`
  - `docs/specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md`
- [ ] After the fix, new spec PRs do not trigger any automated reviewer finding about a missing "Guiding principle" section.

---

## Out of Scope (MVP)

- Changing any other sections of the spec template beyond removing the "Guiding principle" section.
- Updating the implementation plan template or implementation plan files.
- Changing the content or structure of any spec other than removing the boilerplate "Guiding principle" section.
- Adding new linting or validation rules to enforce spec template compliance beyond what `REVIEW.md` already provides.

---

## Open Questions

<!-- None — scope and proposed fix are fully defined in the issue brief. -->
