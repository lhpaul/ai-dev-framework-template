# Explicit PR-Agent Trigger Model — Spec

**Epic**: #1095 Actions cost reduction

---

## Overview

Workflow maintainers need PR-Agent to remain available as an automated review
platform without paying for broad automatic runs on every pull request update or
every human comment. This feature makes PR-Agent an explicit review action while
preserving the staged workflow contract used by `/run-reviewer-loop`,
`/run-item`, `/run-epic`, and downstream local review overrides.

The operator experience should be predictable: routine pull request activity no
longer fans out to PR-Agent by default, but configured review loops can still
request PR-Agent and report whether it ran, skipped, timed out, or was
unavailable.

## Brief Objective List

Derived from issue #1096:

1. Stop PR-Agent from running automatically on every pull request synchronize
   event by default.
2. Stop PR-Agent from running automatically on every human issue comment by
   default.
3. Provide an explicit manual trigger path for PR-Agent review.
4. Preserve the `pr-review-loop.sh` contract when `pr-agent` is configured in
   draft-review settings or local overrides.
5. Make PR-Agent participation deterministic, including polling, timeout, and
   skipped or unavailable outcomes.
6. Document the impact on `/run-reviewer-loop`, `/run-item`, `/run-epic`, and
   downstream local review overrides.
7. Cover the trigger behavior and workflow configuration path with tests.

---

## Use Cases

### Use Case 1: Routine PR updates do not trigger PR-Agent automatically

**Actor**: Contributor or workflow agent updating a pull request.
**Preconditions**: A pull request exists in a downstream repository that has not
explicitly opted into automatic PR-Agent runs.

**Steps**:

1. The contributor pushes one or more commits to the pull request branch.
2. The repository runs its normal review, CI, and readiness workflows.
3. PR-Agent does not run solely because the pull request was synchronized.

**Postconditions**: The pull request remains eligible for other review
platforms and CI, but no PR-Agent runner minutes are consumed unless an explicit
trigger or configured review loop requests it.

**Information shown**:

- The usual pull request checks and review-loop summary.
- No automatic PR-Agent result appears unless PR-Agent was explicitly requested.

**Actions available**:

- Continue normal workflow review.
- Explicitly request PR-Agent review when its output is useful.

**Considerations**:

- Repositories that intentionally want automatic PR-Agent review need a clear
  opt-in path rather than relying on the template default.

### Use Case 2: Human comments do not trigger PR-Agent unless explicit

**Actor**: Human reviewer or maintainer commenting on a pull request.
**Preconditions**: A pull request is open and PR-Agent is installed or available
to the repository.

**Steps**:

1. The human posts a normal discussion, approval, request, or operational comment.
2. The repository does not treat the comment as a PR-Agent request.
3. If the human uses the documented explicit trigger, PR-Agent runs for that
   requested action only.

**Postconditions**: General discussion comments do not spend PR-Agent runner
minutes, while intentional PR-Agent requests remain available.

**Information shown**:

- A documented trigger phrase or manual action for requesting PR-Agent.
- A clear result when the explicit request is accepted, skipped, or unavailable.

**Actions available**:

- Post normal comments without starting PR-Agent.
- Use the explicit PR-Agent trigger path for a focused review.

**Considerations**:

- The trigger must be constrained enough that casual text does not accidentally
  start PR-Agent.

### Use Case 3: The reviewer loop can still request configured PR-Agent review

**Actor**: Workflow operator running `/run-reviewer-loop`, `/run-item`, or
`/run-epic`.
**Preconditions**: Repository configuration or local overrides include PR-Agent
as a review platform for the relevant review phase.

**Steps**:

1. The operator runs the normal workflow command.
2. The reviewer loop determines that PR-Agent is configured for the phase.
3. The reviewer loop requests PR-Agent through the explicit trigger path.
4. The reviewer loop waits only within the documented deterministic bounds.
5. The final review-loop summary reports the PR-Agent outcome.

**Postconditions**: PR-Agent remains part of the workflow contract when
configured, but the cost of running it is tied to deliberate review-loop use.

**Information shown**:

- Whether PR-Agent was requested by the review loop.
- Whether it completed cleanly, found issues, skipped, timed out, or was
  unavailable.
- Any action needed from the operator when PR-Agent cannot run.

**Actions available**:

- Fix blocking findings and rerun the reviewer loop.
- Accept a documented skipped or unavailable result when policy allows.
- Escalate when the configured review platform cannot be verified.

**Considerations**:

- The review-loop summary must not silently report a clean review if PR-Agent was
  configured but could not be requested or verified.

### Use Case 4: Downstream projects understand the migration

**Actor**: Downstream template maintainer.
**Preconditions**: A downstream repository syncs this template and currently
relies on automatic PR-Agent comments or pull request update triggers.

**Steps**:

1. The maintainer reads the migration guidance.
2. The guidance explains the new default and how to opt into automatic behavior
   if the downstream repository deliberately wants it.
3. The guidance explains how local review overrides interact with the explicit
   PR-Agent trigger path.

**Postconditions**: Downstream maintainers can reduce default runner minutes
without losing the ability to use PR-Agent intentionally.

**Information shown**:

- Default trigger behavior.
- Opt-in guidance for automatic PR-Agent usage.
- How `/run-reviewer-loop`, `/run-item`, and `/run-epic` request PR-Agent.

**Actions available**:

- Keep the cost-saving default.
- Opt into automatic PR-Agent triggers with an explicit configuration change.
- Remove PR-Agent from local review overrides when it is no longer desired.

**Considerations**:

- Migration guidance should distinguish public template behavior from private
  downstream cost risk.

---

## Business Rules

- PR-Agent must not run on every pull request synchronize event by default.
- PR-Agent must not run on every human issue comment by default.
- Only documented explicit trigger paths may request PR-Agent review.
- If PR-Agent is configured as a review platform, the reviewer loop must either
  request and verify it or report a deterministic skipped, timed-out, or
  unavailable state.
- A configured PR-Agent platform may not be silently ignored by workflow
  commands that claim reviewer-loop readiness.
- Downstream repositories may opt into broader automatic PR-Agent behavior, but
  that opt-in must be explicit and documented.

---

## Operational Visibility

- **Review-loop summary**: Records whether PR-Agent was requested, completed,
  skipped, timed out, or unavailable.
- **Pull request checks or comments**: Show the PR-Agent result only when an
  explicit trigger or configured reviewer loop requested it.
- **Documentation**: Explains the default trigger model and downstream migration
  options.

---

## Acceptance Criteria

- [ ] Pull request synchronize events do not start PR-Agent by default.
- [ ] Human issue or pull request comments do not start PR-Agent unless they use
      the documented explicit trigger.
- [ ] A manual PR-Agent trigger path exists and is documented for maintainers.
- [ ] `/run-reviewer-loop` can request PR-Agent when `pr-agent` is configured for
      the active review phase.
- [ ] `/run-item` and `/run-epic` retain their reviewer-loop semantics when
      PR-Agent is configured.
- [ ] The reviewer-loop result distinguishes PR-Agent clean, findings, skipped,
      timed-out, and unavailable outcomes.
- [ ] Tests cover the default trigger suppression, explicit trigger path, and
      configured reviewer-loop path.
- [ ] Documentation explains downstream migration impact for repositories that
      previously relied on automatic PR-Agent comments or synchronize events.

---

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Stop automatic PR synchronize runs | Use Case 1; Business Rules; AC 1 |
| Stop automatic human comment runs | Use Case 2; Business Rules; AC 2 |
| Provide explicit manual trigger | Use Case 2; AC 3 |
| Preserve reviewer-loop contract | Use Case 3; Business Rules; AC 4, AC 5 |
| Deterministic polling and outcomes | Use Case 3; Operational Visibility; AC 6 |
| Document workflow and downstream impact | Use Case 4; AC 8 |
| Test trigger and config behavior | AC 7 |

---

## Out of Scope (MVP)

- Changing the overall set of supported automated reviewer platforms.
- Removing PR-Agent support from repositories that explicitly configure it.
- Defining a new cost-reporting dashboard for PR-Agent usage.
- Changing merge authority, branch protection, or human review policy.
