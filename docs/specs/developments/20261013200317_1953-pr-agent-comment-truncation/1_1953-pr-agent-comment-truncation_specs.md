# PR-Agent Comment Truncation — Spec

**Work item**: [#1953](https://github.com/lhpaul/ai-dev-framework-template/issues/1953)

## Overview

Large PR-Agent reviews can consume almost the entire GitHub comment allowance with hidden review history, cutting off the visible summary and verdict. The template must prioritize the current review so maintainers and the automated reviewer loop can assess it. Luis authorized a local runtime patch in the template, with spec and plan, on 2026-10-13; the implementation approach belongs in the plan.

## Use Cases

### Use Case 1: Publish a large review

**Actor**: PR-Agent, triggered by a supported pull-request event or an authorized review request.
**Preconditions**: The generated review contains a current visible summary and verdict plus hidden history; the combined comment exceeds the publication limit.

**Steps**:

1. Generate the current review through the existing template review workflow.
2. Fit the comment into the publication limit by reducing hidden history first.
3. Publish the fitted comment and let the existing reviewer loop classify it.

**Postconditions**: When the current visible review fits on its own, its summary and verdict survive intact. The published comment fits the limit, and the classifier recognizes the original verdict rather than reporting ambiguity caused by truncation.

**Information shown**: The current review and an explicit notice whenever history was omitted.

**Actions available**: Maintainers can read the review and address its findings using the existing workflow.

**Considerations**: Retained history must remain well formed. Omitted history must not be represented as a complete record or interpreted as proof that earlier findings were resolved.

### Use Case 2: Publish a review within the limit

**Actor**: PR-Agent.
**Preconditions**: The complete generated comment is at or below the publication limit.

**Steps**:

1. Generate the review as usual.
2. Publish the original comment without truncation or rewriting.

**Postconditions**: Publication content and existing classification behavior are unchanged.

**Information shown**: The original review and history.

**Actions available**: Existing review actions remain available.

## Business Rules

1. The final published body must never exceed the provider's GitHub comment limit; the truncation notice counts toward that limit.
2. Comments at or below the limit must remain byte-for-byte unchanged by the patch.
3. For oversized comments, hidden history has lower priority than the current visible summary and verdict. When the visible review plus an omission notice fits, preserve the visible review intact.
4. Omitted history must have an explicit truncation notice. Retained structured history must remain valid; incomplete history must not silently appear complete to subsequent reviews.
5. If the current visible review itself exceeds the limit, reduce history first and clearly disclose any subsequent reduction of visible content. Do not fabricate a clean verdict when the original verdict cannot be retained or recognized.
6. The patch must run before irreversible publication truncation. Editing an already-truncated comment or weakening ambiguity detection does not satisfy this work item.
7. Preserve current review triggers, model selection, permissions, and repository-origin restrictions. The patch must be usable by template consumers without repository-specific incident data.

## Operational Visibility

- Published comments disclose history truncation, and any required visible-content truncation, without exposing credentials.
- Review workflow failures remain observable through existing workflow logs and statuses; an incompatible runtime must not silently bypass the patch.

## Acceptance Criteria

- [ ] **AC1**: A generated comment over the GitHub limit, whose visible review fits with a truncation notice, publishes with its visible summary and verdict unchanged; hidden history is reduced first and the notice is present.
- [ ] **AC2**: The existing classifier produces the original non-ambiguous verdict for that oversized fixture after publication fitting. Include both a clean verdict and a blocking verdict so fitting cannot convert a blocker into approval.
- [ ] **AC3**: Oversized fixtures always produce a published body at or below the limit, including the truncation notice and retained markup. Cover an exact-limit comment and a visible review that alone exceeds the limit.
- [ ] **AC4**: Below-limit and exact-limit comments remain byte-for-byte unchanged and retain their original classifier outcome.
- [ ] **AC5**: Retained structured history is valid; omission is explicit and does not silently claim complete review-history coverage or resolution of dropped findings.
- [ ] **AC6**: The template's actual PR-Agent publication path uses the patch before truncation. Its existing triggers, model configuration, permissions, and repository-origin restrictions are preserved, and runtime incompatibility is observable.

## Brief Objective List and Coverage Matrix

| Objective from the brief or confirmed decision | Coverage |
| --- | --- |
| Conserve the visible verdict and summary; truncate hidden history first with a marker | AC1, AC5; business rules 3–4 |
| Test an over-limit comment with its visible review intact | AC1–AC3 |
| Classifier returns a non-ambiguous verdict | AC2 |
| Published body never exceeds GitHub's limit | AC3 |
| No behavior changes for comments under the limit | AC4 |
| Apply a local runtime patch in the template with spec and plan | AC6; overview; business rule 6 |

## Out of Scope (MVP)

- Upstream PR-Agent contributions, provider migration, model changes, or a release.
- Changes to reviewer verdict policy, risk classification, or merge authority.
- Repairing comments already published with missing content, and modifying consumer repositories during this item.
- Unrelated work items or changes to local workflow configuration.

**Deferral notes**: No brief objective is deferred. Out-of-scope items bound the fix rather than remove an acceptance criterion.
