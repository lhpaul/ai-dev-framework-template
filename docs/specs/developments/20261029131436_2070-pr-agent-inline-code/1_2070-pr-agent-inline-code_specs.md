# PR-Agent Classifiable Inline Code — Spec

**Work item**: [#2070](https://github.com/lhpaul/ai-dev-framework-template/issues/2070)

## Overview

PR-Agent can publish a review card whose inline code contains a literal closing HTML tag within a larger expression. That formatting can make the existing reviewer loop reject an otherwise advisory-only review as ambiguous. Newly generated reviews must present equivalent readable inline code that the existing classifier can safely assess, while preserving its fail-closed protections and the review's meaning and provenance.

## Use Cases

### Use Case 1: Publish and assess a review containing a closing-tag expression

**Actor**: PR-Agent, triggered through an existing supported review event or authorized review request.
**Preconditions**: A newly generated normal review card contains a single-line inline-code expression with a literal closing HTML tag embedded in the expression.

**Steps**:

1. Generate the review through the normal workflow.
2. Present the inline expression in an equivalent readable form before publishing the review.
3. Publish the review and run the existing classification path against the published body.

**Postconditions**: The expression remains readable with the same code meaning. A review containing only Possible Issue advisories is classifiable without a formatting-induced ambiguity escalation or a verification-only fallback. Any independent blocker continues to block.

**Information shown**: The review's findings, severity, readable code, reviewed commit identity, and review-state provenance.

**Actions available**: Maintainers can inspect findings and follow the existing review workflow; the reviewer loop can classify the actual published review.

**Considerations**: Ordinary inline code remains readable and retains its classification. A literal tag inside legitimate code must not be confused with a structural boundary crossed by malformed review markup.

### Use Case 2: Encounter genuinely ambiguous review markup

**Actor**: The reviewer loop assessing a published review.
**Preconditions**: The supplied review has genuinely ambiguous or cross-boundary HTML, rather than a legitimate inline expression in a normal card.

**Steps**:

1. Evaluate the review through the existing parser and classification path.
2. Retain the existing fail-closed handling when safe classification cannot be established.

**Postconditions**: Ambiguity still causes escalation; producer formatting does not manufacture an accepted verdict or hide a security or verification blocker.

**Information shown**: The existing ambiguity or blocker disposition and its supporting review evidence.

**Actions available**: Maintainers can inspect the evidence and resolve the underlying issue through existing gates.

**Considerations**: Missing or invalid provenance and stale reviewed-commit identity retain their existing handling. Previously published bot comments are never rewritten as part of this correction.

## Business Rules

1. Correct producer formatting before publication; extend delimiter recognition while preserving the parser guard’s ambiguity protections and classification policy. Do not add exemptions for a PR, finding identifier, or desired verdict.
2. Preserve review content and code meaning, finding severity, reviewed commit identity, and review-state provenance. Formatting must not remove findings, alter their disposition, or manufacture evidence that the review is current.
3. Scope the correction to legitimate inline code in normal review cards. Genuinely ambiguous or cross-boundary HTML must retain fail-closed rejection.
4. A safely formatted expression does not override independent security, verification, or other blocking findings. Existing blocker precedence remains unchanged.
5. Use the ordinary publication-to-classification path. Tests of an isolated formatter alone are insufficient evidence of completion.
6. Use fabricated review data for regression tests. Do not alter previously published bot comments, live review evidence, unrelated work items, reviewer configuration, or merge gates.
7. Preserve existing publication limits and current-head binding checks. Formatting must neither bypass those checks nor use omission or a verification-only fallback to claim the expression is safely classifiable.

## UX Rules

- Maintainers must be able to read the equivalent inline expression within its review card without losing code meaning or surrounding finding context.
- Ordinary inline-code controls retain their existing presentation and classification.
- No new operator action or review-state label is introduced.

## Operational Visibility

- The published review is the evidence assessed by the reviewer loop, with its existing reviewed-commit identity and review-state provenance intact.
- Existing ambiguity, security, verification, and publication failures remain observable through the existing review and workflow evidence. No new notification destination or telemetry is required.

## Acceptance Criteria

- [ ] **AC1**: A fabricated normal Possible Issue review card containing a mixed single-line expression with a literal closing HTML tag publishes as equivalent readable inline code. Classification of the independently read published body is clean, without ambiguity escalation or verification-only fallback.
- [ ] **AC2**: An ordinary inline-code control follows the same publication-to-classification path with its code presentation, finding content, severity, and classification unchanged by the formatting correction.
- [ ] **AC3**: Synthetic genuinely ambiguous and cross-boundary HTML negative controls remain rejected by the parser guard with the same ambiguity protections and retain their existing fail-closed classification. Include a structural closing boundary crossed by an inline span, rather than only a legitimate code literal.
- [ ] **AC4**: Published synthetic reviews preserve their findings, severity, reviewed commit identity, and review-state provenance. Missing, invalid, or stale identity and provenance retain their existing handling; formatting cannot make them current or valid.
- [ ] **AC5**: Synthetic reviews combining the closing-tag expression with independent security and verification blockers retain the blocking disposition of each blocker. Include each blocker independently so one cannot mask loss of the other.
- [ ] **AC6**: Automated regression coverage exercises the ordinary producer publication path and classification of its independently read published body for AC1–AC5, including below-limit reviews. No previous bot comment or live evidence is modified to obtain readiness, and publication limits and current-head checks remain enforced.

## Brief Objective List and Coverage Matrix

| Objective from the issue or confirmed constraint | Coverage |
| --- | --- |
| Producer-generated inline code containing a closing tag remains readable and safely classifiable in a normal card | AC1, AC2; use case 1 |
| Preserve the fail-closed guard for genuine ambiguity without incident-specific exemptions | AC3; business rules 1, 3 |
| Add synthetic producer/parser regressions for the mixed expression, ordinary code, and ambiguous negative controls | AC1–AC3, AC6 |
| Preserve content, severity, current-head identity, and provenance; never rewrite published evidence | AC2, AC4, AC6; business rules 2, 6 |
| Verify normal publication-to-classification including independent security and verification blockers; no bypass | AC5, AC6; business rules 4, 5, 7 |
| Support double-backtick code and bootstrap from predecessor producer without gate suppression | AC7, AC8; approved extension below |
| Limit work to #2070, with Luis approving each merge and the implementation's technical approach | Out of scope; confirmed execution constraints below |

## Out of Scope (MVP)

- Weakening the consumer parser, changing advisory severity or blocker policy, adding allowlists, or bypassing review, CI, risk, and merge gates.
- Repairing previously published comments or manufacturing clean evidence for any existing PR.
- Work on #2064 or PR #2069; those remain owned by a separate session.
- Upstream contributions, provider or model changes, architectural redesign, and changes to local workflow configuration.
- Project fields other than the authorized Type Bug and canonical workflow Status transitions for #2070.

**Deferral notes**: No issue acceptance objective is deferred. The exclusions bound the producer fix rather than remove required behavior. Technical design is reserved for the implementation plan.

## Approved scope extension: double-backtick bootstrap

Luis explicitly approved updating this spec and plan within implementation PR #2073 before implementing double-backtick support in both producer and guard. This supersedes the earlier requirement to keep the guard implementation unchanged; its fail-closed protections and classification policy remain required.

- **AC7**: Complete single-line double-backtick spans, including literal single backticks inside them, retain equivalent visible code in newly rendered findings. The consumer also accepts supported double-backtick code produced by the predecessor, without changing its published body.
- **AC8**: A synthetic bootstrap runs the unmodified predecessor producer/publication path against the candidate consumer. Advisory-only supported spans are classifiable without verification-only fallback; independent blockers and genuinely ambiguous HTML still reject. Current-head identity and provenance remain required under the existing policy.
- Mismatched, escaped, unclosed, multiline and unsupported delimiter runs remain fail-closed. No PR/finding exemption, history rewrite, reviewer bypass or premature trusted-base promotion is authorized.

**Confirmed execution constraints**: Luis accepted the current issue requirements and acceptance criteria, authorized Type Bug and canonical Status transitions, and limited this run to #2070 at maximum risk medium. Each spec, plan, and implementation merge requires his explicit OK; he will review the technical approach at the implementation PR's merge checkpoint.
