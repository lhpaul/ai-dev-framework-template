# Pre-merge Setup Signal — Spec

**Depends on**: none

---

## Overview

When an agent produces a PR that is technically complete and reviewer-loop clean, there is currently no in-process signal that the PR cannot be safely enabled until the human performs out-of-band setup steps (environment variables, secrets, DNS records, service account tokens, etc.). This feature adds a lightweight, standard mechanism that makes pre-merge or pre-enable setup requirements visible at the moment a PR reaches `ready-for-human-review` — surfacing them proactively rather than requiring the human to read the full diff. The signal is emitted automatically by the agent when it detects that the implementation introduces infrastructure dependencies, and does not block CI or automated review from passing.

---

## Use Cases

### Use Case 1: Agent detects infrastructure dependencies and applies setup signal

**Actor**: Agent (automated — the Work Item Runner or developer agent executing the orchestration protocol)
**Preconditions**: The PR is approaching `ready-for-human-review`. The implementation introduces at least one infrastructure dependency that requires a human to perform a setup step before the feature can be enabled or safely used (e.g., a new environment variable, a GitHub Actions secret, a DNS record, or a service account token).

**Steps**:
1. After all automated reviewer loops and CI checks pass (Step 8 of the orchestration protocol), the agent scans the PR diff for infrastructure dependency signals.
2. The agent identifies one or more setup requirements from the diff.
3. The agent applies the `needs-setup` label to the PR alongside `ready-for-human-review`.
4. The agent populates a standardized "Pre-merge Setup" section in the PR body listing each requirement with a plain-language description, the type of requirement (e.g., environment variable, secret, DNS record), and where it must be set (e.g., GitHub Actions secrets, Railway environment, DNS provider).
5. The PR is labeled `ready-for-human-review`.

**Postconditions**: The PR has both `needs-setup` and `ready-for-human-review` labels. The PR body contains a "Pre-merge Setup" section that enumerates each setup requirement in a structured format.

**Information shown**:
- The `needs-setup` label is visible on the PR in the GitHub interface and in label-based PR listing.
- The "Pre-merge Setup" section is visible in the PR body, at a fixed location (near the top or in a dedicated section), and contains one row per requirement with: requirement name, type, value description, and where to set it.

**Actions available**:
- The human can read the setup requirements and perform each one.
- After completing all setup steps, the human removes the `needs-setup` label.
- The human then proceeds to merge (or defer merge) at their own discretion.

**Considerations**:
- The `needs-setup` label does not prevent merge — it is a signal, not a hard gate. The decision to merge before, after, or without completing setup belongs to the human.
- If no infrastructure dependencies are detected, the `needs-setup` label is not applied and no "Pre-merge Setup" section is added to the PR body.
- The section must be omitted (not included with empty content) when there are no setup requirements.

---

### Use Case 2: Agent detects no infrastructure dependencies — clean path

**Actor**: Agent
**Preconditions**: The PR is approaching `ready-for-human-review`. The implementation does not introduce any infrastructure dependency signals.

**Steps**:
1. After all automated reviewer loops and CI checks pass, the agent scans the PR diff for infrastructure dependency signals.
2. No signals are found.
3. The agent does not apply `needs-setup` and does not add a "Pre-merge Setup" section.
4. The PR is labeled `ready-for-human-review` as normal.

**Postconditions**: The PR has only `ready-for-human-review` (and any other applicable labels). No `needs-setup` label is present. No "Pre-merge Setup" section appears in the PR body.

**Information shown**:
- Standard PR labels and body without any setup-signal additions.

**Actions available**:
- The human reviews and merges the PR as normal.

**Considerations**:
- The absence of `needs-setup` is a meaningful signal: the agent found no infrastructure dependencies. This is the expected state for the majority of PRs.

---

### Use Case 3: Human acknowledges and clears the setup signal

**Actor**: Human reviewer / operator
**Preconditions**: The PR has both `needs-setup` and `ready-for-human-review` labels. The human has completed (or intentionally deferred) the listed setup steps.

**Steps**:
1. Human reads the "Pre-merge Setup" section in the PR body.
2. Human performs each required setup step (or decides to defer).
3. Human removes the `needs-setup` label from the PR.

**Postconditions**: The `needs-setup` label is no longer on the PR. The "Pre-merge Setup" section remains in the PR body as a record (it is not deleted when the label is removed).

**Information shown**:
- After removing the label, the PR shows only `ready-for-human-review`.

**Actions available**:
- Human merges the PR.

**Considerations**:
- The human may defer setup and merge anyway — this is intentional. The signal documents the requirement; enforcement is the human's responsibility.
- The "Pre-merge Setup" section is not removed when the label is cleared, so the requirement is preserved in the PR history.

---

### Use Case 4: Agent rescans after a fixer push — setup signal stays current

**Actor**: Agent
**Preconditions**: A fixer push has been made to the PR branch (e.g., to address a reviewer finding after the initial setup signal was applied).

**Steps**:
1. After the fixer push, the agent re-runs automated review and CI loops.
2. The agent re-scans the PR diff for infrastructure dependency signals.
3. If setup requirements remain or new ones were introduced, the agent updates the "Pre-merge Setup" section and ensures `needs-setup` is present.
4. If all setup requirements have been removed from the diff (e.g., the env var was replaced with a hardcoded default), the agent removes the `needs-setup` label and removes the "Pre-merge Setup" section.

**Postconditions**: The PR body and labels accurately reflect the current state of the diff — not the state at initial scan time.

**Information shown**:
- The "Pre-merge Setup" section is up to date with the latest diff.

**Actions available**:
- Human reviews the updated signal and acts accordingly.

**Considerations**:
- Re-scanning on every push is the correct behavior. Stale setup sections from prior commits mislead humans.

---

## Business Rules

- BR-1: The `needs-setup` label must always be accompanied by a "Pre-merge Setup" section in the PR body. Applying the label without the section is an incomplete signal.
- BR-2: Agents must not add or retain the "Pre-merge Setup" section in the PR body without also applying the `needs-setup` label. After the human removes `needs-setup`, the section may remain as a historical record — this is not an orphaned section but an intentional audit trail.
- BR-3: The `needs-setup` label is a signal only — it must not prevent CI from passing, block automated review tools from completing, or prevent `ready-for-human-review` from being applied. It co-exists with `ready-for-human-review`.
- BR-4: The detection scan runs after all automated reviewer loops and CI checks pass (at the Step 8a / Step 8c stage of the orchestration protocol), not before.
- BR-5: When no infrastructure dependency signals are detected, the `needs-setup` label must not be applied and the "Pre-merge Setup" section must not be included.
- BR-6: On each fixer push, the agent must rescan the diff and update the setup signal state (add, update, or remove) to reflect the current diff — not cached prior state.
- BR-7: When the `needs-setup` label is removed by the human (Use Case 3), the "Pre-merge Setup" section remains in the PR body as a historical record — the human's removal signals that setup has been acknowledged, and the section preserves the audit trail. When the agent rescans and finds no infrastructure dependencies (Use Case 4), the agent removes both the label and the section — there is no record to preserve because the code change itself eliminated the dependency.
- BR-8: Each requirement listed in the "Pre-merge Setup" section must identify: the requirement name, the type (e.g., environment variable, GitHub Actions secret, DNS record), a plain-language description of the expected value, and the location where it must be set.
- BR-9: The detection heuristics are a best-effort scan. False negatives (missed dependencies) are acceptable and do not represent a defect in this feature. The human is the final authority on whether all setup is complete.
- BR-10: The `needs-setup` label must be a distinct label from `needs-fixes`. They may co-exist on the same PR if both conditions apply, but they have different semantics: `needs-fixes` signals reviewer-requested code changes; `needs-setup` signals out-of-band human configuration steps.

---

## Statuses / Enum Values

| Code value | Display label | Description |
|---|---|---|
| `needs-setup` | Needs Setup | PR introduces one or more infrastructure dependencies that require human setup steps before the feature can be safely enabled |
| `ready-for-human-review` | Ready for Human Review | PR is technically complete and all automated checks have passed |

**Valid label combinations**:
- `ready-for-human-review` only — no setup requirements detected; standard ready state
- `ready-for-human-review` + `needs-setup` — PR is technically ready but has unmet setup requirements; human must perform setup and then remove `needs-setup` before or after merge
- `needs-fixes` + `needs-setup` — PR has both code changes requested by reviewers and setup requirements; both must be addressed before the PR can reach `ready-for-human-review`

---

## Acceptance Criteria

- [ ] AC-1: When an agent completes the reviewer loop and CI for a PR whose diff contains one or more infrastructure dependency signals (new environment variable, new GitHub Actions secret reference, or other detection-heuristic match), the agent applies the `needs-setup` label and populates a "Pre-merge Setup" section in the PR body before applying `ready-for-human-review`.
- [ ] AC-2: The "Pre-merge Setup" section lists each detected requirement with: requirement name, type, plain-language description of the expected value, and the location where it must be set.
- [ ] AC-3: When a PR's diff contains no infrastructure dependency signals, the agent does not apply `needs-setup` and does not add a "Pre-merge Setup" section to the PR body.
- [ ] AC-4: The `needs-setup` label is applied alongside (not instead of) `ready-for-human-review` — the PR is still declared ready for human review.
- [ ] AC-5: After a fixer push, the agent rescans the diff; if infrastructure dependency signals are no longer present, it removes both the `needs-setup` label and the "Pre-merge Setup" section from the PR body.
- [ ] AC-6: After a fixer push, the agent rescans the diff; if new infrastructure dependency signals are introduced, the "Pre-merge Setup" section is updated and `needs-setup` remains applied.
- [ ] AC-7: The orchestration protocol (Step 8a label readiness checklist) documents the `needs-setup` label as a valid co-label with `ready-for-human-review` and does not treat its presence as an error.
- [ ] AC-8: The `needs-setup` label is defined in the PR readiness signal protocol (`92-pr-readiness-signal-protocol.md`) with its semantics, valid combinations, and who removes it.
- [ ] AC-9: A smoke test runbook or manual verification checklist covers: confirming `needs-setup` is applied when expected, confirming the "Pre-merge Setup" section content, and confirming `needs-setup` is absent on a clean PR.

---

## Out of Scope (MVP)

- Automated provisioning or injection of the required values (this feature is about surfacing requirements, not fulfilling them).
- Blocking CI or any automated check from passing based on detected setup requirements — the label is informational.
- Machine-readable structured output of setup requirements (e.g., JSON schema or YAML block) — plain-language prose in the PR body section is sufficient for this iteration.
- Integration with secret managers or environment dashboards to verify whether a required value has been set.
- Notification or alert to the human when `needs-setup` is applied (beyond the standard GitHub label notification mechanism).
- Detection of infrastructure dependencies from arbitrary docs or runbooks using natural language parsing — the initial detection scope is limited to structured heuristics (e.g., new env var entries, new secret references in workflow files) defined in the implementation plan.
- Retroactively rescanning merged PRs or PRs that already have `ready-for-human-review`.
- Enforcement of setup completion before merge (a "merge gate") — this is a conscious deferral.
- UI changes to any dashboard or admin panel.
