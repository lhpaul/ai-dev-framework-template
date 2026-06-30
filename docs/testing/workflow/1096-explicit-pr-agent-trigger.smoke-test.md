# Smoke Test Runbook: Explicit PR-Agent Trigger Model

**Feature**: Explicit PR-Agent Trigger Model
**Spec**: `docs/specs/developments/20260630151000_1096-explicit-pr-agent-trigger/1_1096-explicit-pr-agent-trigger_specs.md`
**Plan**: `docs/specs/developments/20260630151000_1096-explicit-pr-agent-trigger/2_1096-explicit-pr-agent-trigger_implementation-plan.md`

---

## Purpose

Verify that PR-Agent no longer consumes GitHub Actions minutes for broad default
pull request update or arbitrary human-comment fan-out, while remaining available
to `pr-review-loop.sh` when configured as a review platform.

---

## Preconditions

- A repository branch contains the implementation for #1096.
- PR-Agent is configured in `.ai-dev-workflow.yaml` under
  `review.on_draft.github` or an equivalent local override.
- The test environment has enough GitHub permissions to open a scratch pull
  request and post PR comments, or the shell harness tests are run locally with
  mocked `gh` calls.

---

## Scenario 1: PR synchronize does not trigger PR-Agent by default

1. Inspect `.github/workflows/pr-agent.yml`.
2. Confirm `pull_request.types` does not include `synchronize`.
3. Push a new commit to a scratch pull request branch, or inspect the Actions run
   list for the implementation PR after a normal synchronize event.

**Expected result**: PR-Agent does not run solely because the PR branch received
a new commit.

---

## Scenario 2: Arbitrary human comments do not trigger PR-Agent

1. Post a normal human comment on a scratch pull request, such as
   `Thanks, I will review this shortly.`
2. Wait long enough for issue-comment workflows to enqueue if they are going to
   run.
3. Inspect the PR-Agent workflow run list.

**Expected result**: No PR-Agent run starts from the arbitrary comment.

---

## Scenario 3: Explicit PR-Agent command triggers review

1. Post the documented explicit PR-Agent command on a scratch pull request.
2. Wait for the PR-Agent workflow to run.
3. Inspect the resulting PR-Agent comment or check result.

**Expected result**: PR-Agent runs only for the explicit command and posts its
normal review output.

---

## Scenario 4: Reviewer loop requests configured PR-Agent

1. Ensure `pr-agent` is configured for the active reviewer-loop phase.
2. Run:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <PR_NUMBER> \
     --branch <BRANCH_NAME> \
     --platform pr-agent
   ```

3. Inspect the reviewer-loop key-value output and PR comments.

**Expected result**: When no current-head PR-Agent comment exists, the reviewer
loop posts the explicit trigger command, waits within its documented bounds, and
reports PR-Agent as clean, needs-fixes, skipped, or escalated. It does not report
clean without either reusing a current-head PR-Agent comment or documenting a
non-clean skipped/unavailable state. The workflow condition must allow the
reviewer-loop posting identity even when that identity is a trusted bot or
GitHub App token.

---

## Scenario 5: Existing current-head PR-Agent comments are reused

1. Use a pull request that already has a PR-Agent comment for the current head.
2. Run the reviewer loop with `--platform pr-agent`.
3. Inspect PR comments before and after the run.

**Expected result**: The reviewer loop reuses the existing current-head PR-Agent
comment and does not post a duplicate trigger command.

---

## Scenario 6: Local regression tests cover trigger behavior

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Confirm the PR-Agent trigger tests pass.

**Expected result**: The shell harness passes and includes coverage for trigger
posting, duplicate suppression, trigger post failure, and workflow trigger
constraints.

---

## Acceptance Criteria Coverage

- [ ] AC 1: PR synchronize events do not start PR-Agent by default.
- [ ] AC 2: Human comments do not start PR-Agent unless they use the documented
      explicit trigger.
- [ ] AC 3: A manual PR-Agent trigger path exists and is documented.
- [ ] AC 4: `/run-reviewer-loop` can request PR-Agent when configured.
- [ ] AC 5: `/run-item` and `/run-epic` retain reviewer-loop semantics because
      they use the same reviewer-loop helper.
- [ ] AC 6: Reviewer-loop output distinguishes clean, findings, skipped,
      timed-out, and unavailable outcomes.
- [ ] AC 7: Tests cover default trigger suppression, explicit trigger, and
      configured reviewer-loop paths.
- [ ] AC 8: Documentation explains downstream migration impact.

---

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| PR-Agent still runs on every commit push | `synchronize` remains in the workflow trigger list | Remove `synchronize` or verify the downstream repository did not opt back in. |
| Any human comment triggers PR-Agent | The issue-comment job condition is too broad | Require an exact explicit command in the workflow condition. |
| Reviewer loop times out waiting for PR-Agent | Trigger comment did not post, PR-Agent is unavailable, or the command is not recognized | Check reviewer-loop output, workflow runs, and PR comments for the documented trigger. |
| Reviewer loop posts the trigger but no workflow starts | The issue-comment condition excludes the reviewer-loop posting identity | Allow the reviewer-loop identity while keeping exact command matching. |
| Duplicate PR-Agent runs appear | The adapter is not detecting current-head PR-Agent comments | Verify the head SHA matching logic and existing-comment test coverage. |
