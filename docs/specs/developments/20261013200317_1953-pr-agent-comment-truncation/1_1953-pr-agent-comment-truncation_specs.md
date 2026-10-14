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

**Information shown**: The current review and, when space permits, an explicit notice that history was omitted. If the notice would displace the visible summary or verdict, shorten it to fit the remaining space or omit it entirely.

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
3. For oversized comments, hidden history and the truncation notice have lower priority than the current visible summary and verdict. When the visible review fits on its own, preserve it intact. Reduce hidden history first; use only the remaining space for a notice, shortening or omitting the notice when needed rather than displacing the visible review. This includes a visible review that exactly fills the limit.
4. Display an explicit truncation notice when it fits without displacing the visible summary or verdict; otherwise shorten or omit it as specified in rule 3. Record history omission in the existing workflow logs even when the comment has no room for a notice. Retained structured history must remain valid; incomplete history must not appear complete to subsequent reviews or imply that omitted findings were resolved, regardless of whether a notice is displayed.
5. If the current visible review itself exceeds the limit, reduce history first, then reduce visible content while prioritizing its verdict and summary over the truncation notice. Disclose visible-content reduction in the existing workflow logs and, when space permits, in the comment; shorten or omit the notice rather than displacing the retained verdict and summary. Do not fabricate a clean verdict when the original verdict cannot be retained or recognized.
6. The patch must run before irreversible publication truncation. Editing an already-truncated comment or weakening ambiguity detection does not satisfy this work item.
7. Preserve current review triggers, model selection, permissions, and repository-origin restrictions. The patch must be usable by template consumers without repository-specific incident data.

## Operational Visibility

- Published comments disclose history truncation, and any required visible-content truncation, when a full or shortened notice fits after prioritizing the visible verdict and summary. Existing workflow logs record these omissions even when the notice cannot fit; neither surface exposes credentials.
- Review workflow failures remain observable through existing workflow logs and statuses; an incompatible runtime must not silently bypass the patch.

## Acceptance Criteria

- [ ] **AC1**: A generated comment over the GitHub limit, whose visible review fits on its own, publishes with its visible summary and verdict unchanged; hidden history is reduced first. Test space for a full notice, space for only a shortened notice, and no space for a notice: shorten or omit the notice without altering the visible review.
- [ ] **AC2**: The existing classifier produces the original non-ambiguous verdict for that oversized fixture after publication fitting. Include both a clean verdict and a blocking verdict so fitting cannot convert a blocker into approval.
- [ ] **AC3**: Oversized fixtures always produce a published body at or below the limit, counting any retained truncation notice and markup. Cover a visible review that exactly fills the limit while hidden history makes the generated comment oversized, and a visible review that alone exceeds the limit; prioritize its verdict and summary over the notice in both cases.
- [ ] **AC4**: Below-limit and exact-limit comments remain byte-for-byte unchanged and retain their original classifier outcome.
- [ ] **AC5**: Retained structured history is valid; omissions are recorded in the existing workflow logs and in a full or shortened comment notice when space permits. Even when the notice is omitted, retained history does not claim complete review-history coverage or resolution of dropped findings.
- [ ] **AC6**: The template's actual PR-Agent publication path uses the patch before truncation. Its existing triggers, model configuration, permissions, and repository-origin restrictions are preserved, and runtime incompatibility is observable.

## Brief Objective List and Coverage Matrix

| Objective from the brief or confirmed decision | Coverage |
| --- | --- |
| Conserve the visible verdict and summary; truncate hidden history first with a marker, shortened or omitted when needed per Luis's confirmed decision | AC1, AC5; business rules 3–4 |
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
