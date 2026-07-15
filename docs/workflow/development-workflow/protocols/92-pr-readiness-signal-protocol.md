# Protocol: PR Readiness Signal

**Purpose**: Define the labels and conditions that signal whether an agent's PR is ready for human review or needs fixes.

This is a **repo-wide definition**. All agents apply these labels consistently.

---

## Labels

| Label                    | Meaning                                                                                                                                                                                                                                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ready-for-human-review` | The PR is ready for a human reviewer. CI is green. The `REVIEW.md` gate is satisfied. Every configured automated reviewer is clean or skipped.                                                                                                                                                                           |
| `needs-fixes`            | The PR still needs fixes before it is ready for human review. This may be due to human-requested changes, failing CI, or blocking automated PR feedback.                                                                                                                                                                 |
| `ready-for-regression`   | Automated code reviews are clean (or skipped). Configured real e2e/regression tests, or an explicitly enabled placeholder, should now run. Applied by the orchestrator (Step 7b) on implementation PRs (`feature/*`, `fix/*`, `hotfix/*`, `refactor/*`, `backport/hotfix/*`), and by the prepare-release flow (protocol `05`) on **production** release PRs (`release/*` → `main`) only. |
| `needs-setup`            | PR introduces one or more infrastructure dependencies (env vars, secrets, DNS records, service account tokens, etc.) that require human setup steps before the feature can be safely enabled. Co-exists with `ready-for-human-review`; the human removes this label after completing (or intentionally deferring) setup. |
| `human-checkpoint-required` | The PR's linked work item has at least one `pending` human checkpoint that applies to this PR: same `item_number` and either matching the PR's current workflow stage or an earlier stage not yet `satisfied`/`waived`. Human feedback or approval named in `required_human_action` is still required. Co-exists with `ready-for-human-review` when automation is clean but a checkpoint remains open. Does **not** satisfy when only `needs-setup` is removed. |

---

## Conditions for `ready-for-human-review`

Apply this label when **all** of the following are true:

- [ ] CI checks are green (build, lint, tests all pass)
- [ ] The relevant pre-PR review gate from `REVIEW.md` has been completed
- [ ] Step 7's latest automated reviewer-loop summary has `Result: clean` or `Result: skipped`; `RESULT=escalate`, `pending_timeout`, `timeout`, `needs_fixes`, or any other non-clean terminal result blocks this label
- [ ] Every configured automated PR reviewer has no blocking PR feedback (or is skipped)
- [ ] All feedback from a previous human review cycle has been addressed
- [ ] For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
      items, the required residual gate has run in verification mode and the
      latest result is `pass`. `not_applicable` only satisfies readiness when
      the residual gate is not required for the item. `block` maps to
      `needs-fixes`; `escalate` maps to a human-decision stop.

---

## Conditions for `needs-fixes`

Apply this label when **any** of the following is true:

- CI checks are failing
- Any automated PR reviewer reports blocking PR feedback
- A human has requested changes on the PR (and those changes have not yet been addressed)
- A required residual gate returns `block`, meaning broad-scope residuals remain
  undisposed or helper outputs lack caller/disposition evidence
- A required residual gate result is missing when the item title, body, spec, or
  plan indicates sweep, batch, helper-extraction, numeric-target, or
  pattern-completeness work

Do not use `needs-fixes` for residual gate `escalate`; that is a human-decision
stop until the residual scope decision is resolved.

---

## Conditions for `ready-for-regression`

Apply this label when **all** of the following are true:

**Case A — implementation PR** (orchestrator Step 7b in `91-orchestrate-work-protocol.md`):

- [ ] The PR is an implementation PR (branch prefix `feature/*`, `fix/*`, `hotfix/*`, `refactor/*`, or `backport/hotfix/*`)
- [ ] Step 7a (internal review gate) previously produced `APPROVED`
- [ ] Step 7 (automated reviewer loop) has completed with `clean` or `skipped`

**Case B — production release PR** (`05-prepare-release-protocol.md` Step 7.4):

- [ ] The PR targets `main` from a `release/*` branch
- [ ] Step 7 (automated reviewer loop) on that PR has completed with `clean` or `skipped`

Release PRs typically do not use the same draft → `gh pr ready` path as feature work; internal review may be minimal when the change set is changelog/version-only — still apply this label only after Step 7 is `clean` or `skipped` per protocol `05`.

This label is **not removed** after e2e tests pass — it persists on the PR. The
`ready-for-human-review` label is what ultimately signals human readiness after
CI, including configured real e2e/regression checks or an explicitly enabled
placeholder, is green.

This label is **not applied** to spec or plan PRs (`spec/*`, `implementation-plan/*`). It **is** applied to qualifying release PRs per Case B above.

---

## Conditions for `needs-setup`

Apply this label when the agent's infrastructure dependency scan (Protocol 91 Step 8a) detects one or more infrastructure dependency signals in the PR diff. The agent applies it; the human removes it.

**Who applies it**: The agent, as part of Protocol 91 Step 8a, after all automated reviewer loops and CI checks pass but before applying `ready-for-human-review`. The scan runs on every pass through Step 8a (including after fixer pushes) so the label always reflects the current diff.

**Who removes it**: The human reviewer, after completing the listed setup steps (or intentionally deferring them).

**Valid label combinations**:

| Combination                              | Meaning                                                                                                                                                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ready-for-human-review` only            | No setup requirements detected — standard ready state                                                                                                                                                        |
| `ready-for-human-review` + `needs-setup` | PR is technically ready but has unmet setup requirements; human must perform setup and then remove `needs-setup` before or after merge                                                                       |
| `needs-fixes` + `needs-setup`            | Transitional state — PR has both code changes requested by reviewers and setup requirements; `needs-fixes` must be addressed first, at which point `needs-setup` persists alongside `ready-for-human-review` |

**Invariants**:

- **BR-1**: `needs-setup` must always be accompanied by a `## Pre-merge Setup` section in the PR body. Applying the label without the section is an incomplete signal.
- **BR-2**: The `## Pre-merge Setup` section must not appear in the PR body without `needs-setup` being applied at that time. After the human removes `needs-setup`, the section may remain as a historical record — this is an intentional audit trail, not an orphaned section.
- **BR-3**: `needs-setup` does not prevent `ready-for-human-review` from being applied, does not block CI from passing, and does not block automated review tools from completing. It co-exists with `ready-for-human-review`.
- **BR-7**: When the human removes `needs-setup` (Use Case 3 — setup acknowledged), the `## Pre-merge Setup` section remains in the PR body as a historical record. When the agent rescans and finds no infrastructure dependencies (Use Case 4 — dependency removed from diff), the agent removes both the label and the section.
- **BR-10**: `needs-setup` is distinct from `needs-fixes`. They have different semantics, different lifecycles, and may co-exist. `needs-fixes` signals reviewer-requested code changes; `needs-setup` signals out-of-band human configuration steps.

---

## Conditions for `human-checkpoint-required`

Apply this label when the PR's linked work item has at least one checkpoint in
`pending` state that applies to this PR's workflow stage or an earlier stage in
the ordered sequence `spec` → `plan` → `implementation` (see
`1020-human-checkpoint-policy-model` spec BR-2 and BR-4).

**Who applies it**: The Work Item Runner (Protocol 91 Step 8a) via
`run-epic-checkpoint-lifecycle.sh sync-pr-labels` after CI and automated review
are clean and before or alongside applying `ready-for-human-review`.

**Who removes it**: The script removes the label when every applicable
checkpoint transitions to `satisfied` or `waived` with audit evidence. Removing
`needs-fixes` or `needs-setup` does **not** remove this label.

**Valid label combinations**:

| Combination                                                         | Meaning                                                                                                                                                       |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ready-for-human-review` only                                       | Automation clean and no open checkpoints apply to this PR                                                                                                       |
| `ready-for-human-review` + `human-checkpoint-required`              | Automation clean but explicit human checkpoint feedback is still required before delegated review/merge may proceed                                           |
| `ready-for-human-review` + `needs-setup` + `human-checkpoint-required` | Automation clean, setup steps may still be required, and a checkpoint remains open                                                                         |
| `needs-fixes` + `human-checkpoint-required`                         | Transitional — automation/reviewer fixes needed; checkpoint state persists independently                                                                    |

**Invariants**:

- **BR-11**: `ready-for-human-review` means automation-clean only; it does not
  imply checkpoint satisfaction.
- **BR-12**: `human-checkpoint-required` persists through ordinary fix cycles
  while the checkpoint remains `pending`.
- **BR-13**: Removing `human-checkpoint-required` requires `satisfaction_state`
  of `satisfied` or `waived` with audit evidence recorded in the stable
  `<!-- run-epic:checkpoint-status -->` PR comment.
- **BR-14**: `needs-fixes` removal does not imply checkpoint satisfaction.

**Satisfaction signals** (detected on reruns):

- Explicit PR comment:
  `<!-- run-epic:checkpoint-satisfied:<item>:<stage>:<domain> -->`
- Explicit waiver comment:
  `<!-- run-epic:checkpoint-waived:<item>:<stage>:<domain> --> <rationale>`
- Human PR review approval (`APPROVED`) on a PR whose workflow stage matches
  the checkpoint's `stage` satisfies **all** pending checkpoints at that stage
  for the linked item in one action.

The `human-checkpoint-required` GitHub label must exist in the repository's label
settings before Step 8a can apply it. Suggested color: `#d93f0b` (orange-red).

---

## Workflow

### Work Item Runner advances a draft PR

1. Push branch to remote
2. Open PR **as draft** (`gh pr create --draft ...`) — spec/plan/hotfix PRs targeting `main` or `develop` as appropriate; implementation PRs targeting `develop`
3. Run the relevant internal review gate from `REVIEW.md` on the draft PR (spec/plan/code review):
   - `spec/*` → `spec-reviewer` / `01-review-spec-protocol.md`
   - `implementation-plan/*` → `implementation-plan-reviewer` / `02-review-implementation-plan-protocol.md`
   - `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` → `code-reviewer` / `03-review-implementation-protocol.md`
   - Apply fixes, commit, push; repeat until clean
   - Once the internal review gate is clean, run `gh pr ready <pr-number>` to convert the draft to non-draft
4. Run `./scripts/development-workflow/pr-review-loop.sh <pr-number> --branch <branch> [--platform <platform> ...]` when automated review tooling is configured
5. If any automated reviewer reports blocking PR feedback: apply fixes, push, and repeat Step 4
6. For implementation PRs (`feature/*`, `fix/*`, `hotfix/*`, `refactor/*`, `backport/hotfix/*`), or for production release PRs per `05-prepare-release-protocol.md` Step 7.4: apply `ready-for-regression` label to trigger e2e/regression CI checks
7. Run `./scripts/development-workflow/pr-ci-loop.sh <pr-number>`
8. If CI passes and all reviews are clean (or not configured): apply `ready-for-human-review` (the PR is already non-draft from Step 3) and move the tracker status to the matching human-review stage (`Spec in Review`, `Plan in Review`, or `Development in Review`) when the tracker is the source of truth
9. If CI fails: apply `needs-fixes`, fix PR feedback or failing checks, push, and return to Step 4

### Human requests changes

1. Human leaves review comments
2. Work Item Runner receives notification (or is manually pointed to the PR)
3. Remove `ready-for-human-review`, add `needs-fixes`
4. Address all requested changes
5. Push fixes
6. Remove `needs-fixes`, add `ready-for-human-review`
7. Notify human that feedback has been addressed

---

## Recommended Automation

These labels can be applied automatically via CI/CD pipeline rules:

**Apply `needs-fixes` automatically when**:

- Any required CI check fails

**Apply `ready-for-human-review` automatically when**:

- All required CI checks pass
- The pre-PR review gate is complete
- (And no human review has been requested on the PR)

When automation is not available, agents apply labels manually following the conditions above.

---

## Notes

- Opening a PR is not, by itself, a terminal condition for a stage. The stage continues until the PR is ready for human review or has escalated.
- Labels apply to PRs, not to the workflow stage — a PR in any stage can carry either label
- The labels are signals for humans, not enforcement gates — merging is always a human decision
- If no label tooling is available (no issue tracker, no GitHub labels configured), agents communicate readiness status in the PR comment thread instead
