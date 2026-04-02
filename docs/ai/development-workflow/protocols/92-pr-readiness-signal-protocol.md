# Protocol: PR Readiness Signal

**Purpose**: Define the labels and conditions that signal whether an agent's PR is ready for human review or needs fixes.

This is a **repo-wide definition**. All agents apply these labels consistently.

---

## Labels

| Label | Meaning |
| --- | --- |
| `ready-for-human-review` | The PR is ready for a human reviewer. CI is green. The `REVIEW.md` gate is satisfied. Every configured automated reviewer is clean or skipped. |
| `needs-fixes` | The PR still needs fixes before it is ready for human review. This may be due to human-requested changes, failing CI, or blocking automated PR feedback. |

---

## Conditions for `ready-for-human-review`

Apply this label when **all** of the following are true:

- [ ] CI checks are green (build, lint, tests all pass)
- [ ] The relevant pre-PR review gate from `REVIEW.md` has been completed
- [ ] Every configured automated PR reviewer has no blocking PR feedback (or is skipped)
- [ ] All feedback from a previous human review cycle has been addressed

---

## Conditions for `needs-fixes`

Apply this label when **any** of the following is true:

- CI checks are failing
- Any automated PR reviewer reports blocking PR feedback
- A human has requested changes on the PR (and those changes have not yet been addressed)

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
6. Run `./scripts/development-workflow/pr-ci-loop.sh <pr-number>`
7. If CI passes and all reviews are clean (or not configured): apply `ready-for-human-review` (the PR is already non-draft from Step 3) and move the tracker status to the matching human-review stage (`Spec in Review`, `Plan in Review`, or `Development in Review`) when the tracker is the source of truth
8. If CI fails: apply `needs-fixes`, fix PR feedback or failing checks, push, and return to Step 4

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
