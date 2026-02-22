# Protocol: PR Readiness Signal

**Purpose**: Define the labels and conditions that signal whether an agent's PR is ready for human review or needs fixes.

This is a **repo-wide definition**. All agents apply these labels consistently.

---

## Labels

| Label | Meaning |
|---|---|
| `agent:ready-for-review` | The agent has completed its work. CI is green. Automated review (if enabled) is clean. Ready for human review. |
| `agent:needs-fixes` | The human has requested changes on the PR, OR CI is failing, OR the automated review has blocking issues. |

---

## Conditions for `agent:ready-for-review`

Apply this label when **all** of the following are true:

- [ ] CI checks are green (build, lint, tests all pass)
- [ ] Automated PR review tool has no blocking issues (or no automated review tool is configured)
- [ ] All feedback from a previous human review cycle has been addressed

---

## Conditions for `agent:needs-fixes`

Apply this label when **any** of the following is true:

- CI checks are failing
- The automated PR review tool reports blocking issues
- A human has requested changes on the PR (and those changes have not yet been addressed)

---

## Workflow

### Agent opens PR
1. Push branch and open PR
2. Wait for CI to complete
3. If CI passes and automated review is clean (or not configured): apply `agent:ready-for-review`
4. If CI fails or automated review has blocking issues: fix issues, push, wait again

### Human requests changes
1. Human leaves review comments
2. Agent receives notification (or is manually pointed to the PR)
3. Remove `agent:ready-for-review`, add `agent:needs-fixes`
4. Address all requested changes
5. Push fixes
6. Remove `agent:needs-fixes`, add `agent:ready-for-review`
7. Notify human that feedback has been addressed

---

## Recommended Automation

These labels can be applied automatically via CI/CD pipeline rules:

**Apply `agent:needs-fixes` automatically when**:
- Any required CI check fails

**Apply `agent:ready-for-review` automatically when**:
- All required CI checks pass
- (And no human review has been requested on the PR)

When automation is not available, agents apply labels manually following the conditions above.

---

## Notes

- Labels apply to PRs, not to the workflow stage — a PR in any stage can carry either label
- The labels are signals for humans, not enforcement gates — merging is always a human decision
- If no label tooling is available (no issue tracker, no GitHub labels configured), agents communicate readiness status in the PR comment thread instead
