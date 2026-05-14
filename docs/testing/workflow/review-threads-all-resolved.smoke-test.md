# Smoke Test Runbook: Require All Review Threads Resolved Before Ready-For-Human-Review

**Feature**: Require all automated-reviewer review threads resolved before `ready-for-human-review`
**Spec**: [`docs/specs/developments/20260417194629_review-threads-all-resolved/1_review-threads-all-resolved_specs.md`](../../specs/developments/20260417194629_review-threads-all-resolved/1_review-threads-all-resolved_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated (`gh auth status`)
- [ ] `jq` is installed
- [ ] You have a GitHub repository with at least one open PR that has received CodeRabbit inline review comments
- [ ] The `pr-review-loop.sh` changes from this feature are deployed (i.e., the feature branch is checked out or merged)

---

## Test Data

| Item                              | Value                                                                       |
| --------------------------------- | --------------------------------------------------------------------------- |
| Test PR                           | A PR where CodeRabbit has posted at least one inline thread of any severity |
| Bot login (CodeRabbit)            | `coderabbitai`                                                              |
| Bot login (Devin)                 | `devin-ai-integration`                                                      |
| `.ai-dev-workflow.yaml` platforms | `devin` and `coderabbit` (repo default)                                     |

---

## Smoke Test Steps

### Step 1: Confirm a PR has unresolved automated-reviewer threads

1. Find or create a PR where CodeRabbit has posted an inline comment that is **not** resolved (`isResolved: false`) and does **not** contain `✅ Addressed` in its body.
2. Verify using the GitHub GraphQL API:

   ```bash
   gh api graphql \
     -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{author{login}body}}}}}}}' \
     -f owner="<owner>" -f repo="<repo>" -F pr=<pr_number> \
     --jq '.data.repository.pullRequest.reviewThreads.nodes[] | {id, isResolved, author: .comments.nodes[0].author.login}'
   ```

   > **Note**: This query returns only the first 100 review threads; for smoke
   > testing this is sufficient. For PRs with >100 threads, use the paginated
   > implementation in `pr-review-loop.sh` or repeat the query with cursor-based
   > pagination.

3. Confirm at least one thread is `isResolved: false` and authored by `coderabbitai` or `devin-ai-integration`.

### Step 2: Run `pr-review-loop.sh` with an existing unresolved thread (AC1)

**Maps to**: Acceptance Criterion 1

1. Run the review loop against the test PR:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

2. Wait for the script to complete.

**Expected result**:

- Script exits with non-zero status (1)
- Output contains `RESULT=needs_fixes`
- Output contains `UNRESOLVED_THREAD_COUNT=N` where N >= 1
- Output contains `REASON=unresolved_review_threads`

### Step 3: Resolve the thread via `resolveReviewThread` mutation and re-run (AC2, AC4)

**Maps to**: Acceptance Criteria 2 and 4

1. Obtain the thread node ID from the GraphQL query run in Step 1 (the `id` field on the thread node).
2. Resolve the thread via the mutation:

   ```bash
   gh api graphql \
     -f query='mutation($threadId:ID!){resolveReviewThread(input:{threadId:$threadId}){thread{isResolved}}}' \
     -f threadId="<thread_node_id>"
   ```

3. Confirm the mutation response shows `isResolved: true`.
4. Re-run the review loop:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

**Expected result**:

- Script exits with status 0
- Output contains `RESULT=clean`
- Output contains `UNRESOLVED_THREAD_COUNT=0`

### Step 4: Verify `✅ Addressed` text is treated as resolved (AC2)

**Maps to**: Acceptance Criterion 2

1. Find or create a PR where a CodeRabbit comment body contains the text `✅ Addressed` (CodeRabbit appends this after a fix commit).
2. Even if `isResolved` is still `false` on the thread, run the loop:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

**Expected result**:

- The thread with `✅ Addressed` in the first comment body does **not** contribute to `UNRESOLVED_THREAD_COUNT`.
- If that was the only unresolved thread, `RESULT=clean`.

### Step 5: Verify human-authored threads are not counted (AC6)

**Maps to**: Acceptance Criterion 6

1. Find or create a PR where a **human** user (not a bot) has posted an unresolved inline review thread.
2. Ensure no bot-authored threads are unresolved on the same PR.
3. Run the review loop:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

**Expected result**:

- Script exits with status 0
- Output contains `RESULT=clean`
- Output contains `UNRESOLVED_THREAD_COUNT=0`
- The human-authored unresolved thread did not trigger `needs_fixes`

### Step 6: Verify Step 8c independent verification catches unresolved threads (AC3)

**Maps to**: Acceptance Criterion 3

1. Find a PR where the loop would have exited `clean` before this feature (zero blocking findings from platform classifiers) but has an unresolved bot-authored thread.
2. Manually run the GraphQL check that Step 8c now performs:

   ```bash
   gh api graphql \
     -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved comments(first:1){nodes{author{login}body}}}}}}}' \
     -f owner="<owner>" -f repo="<repo>" -F pr=<pr_number> \
     --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | select(.comments.nodes[0].author.login | IN("coderabbitai","devin-ai-integration","greptile-apps")) | select(.comments.nodes[0].body | contains("✅ Addressed") | not)] | length'
   ```

   > **Note**: This query returns only the first 100 review threads; it is a
   > simplified smoke-test check. For PRs with >100 threads, use the paginated
   > implementation in `pr-review-loop.sh` or repeat the query with cursor-based
   > pagination.

3. Confirm the output is > 0 (at least one unresolved bot thread).
4. Confirm the protocol's Step 8c logic would reject `ready-for-human-review` for this PR.

**Expected result**:

- GraphQL query returns N > 0
- Step 8c would remove `ready-for-human-review` and apply `needs-fixes` for this PR

### Step 7: Verify Automated Reviewer Loop Summary lists reply-only resolutions (AC5)

**Maps to**: Acceptance Criterion 5

1. After a fixer resolves a thread via reply + `resolveReviewThread` mutation (no code fix), run the loop to completion.
2. Check the Automated Reviewer Loop Summary comment posted on the PR.

**Expected result**:

- The summary comment includes a section (or note) indicating which threads were resolved via reply-only with a short rationale
- The `Resolved` count in the summary reflects the reply-only resolution

---

## Assertions Checklist

- [ ] AC1: `pr-review-loop.sh` exits `needs_fixes` with `UNRESOLVED_THREAD_COUNT=N` when bot-authored threads are unresolved
- [ ] AC2: `pr-review-loop.sh` exits `clean` when all bot-authored threads are `isResolved: true` or contain `✅ Addressed`
- [ ] AC3: Step 8c independent verification rejects the PR when any bot-authored thread is unresolved
- [ ] AC4: After fixer resolves threads via `resolveReviewThread` mutation and loop re-runs, PR reaches `ready-for-human-review`
- [ ] AC5: Automated Reviewer Loop Summary includes a note on threads resolved via reply-only
- [ ] AC6: Human-authored unresolved threads do not trigger the gate (`UNRESOLVED_THREAD_COUNT` counts only bot-authored threads)
- [ ] AC7: The portfolio orchestrator's pre-readiness verification includes the unresolved-thread check

---

## Seed Data Reference

No persistent seed data required. All test scenarios use live GitHub PRs.

| Entity                                    | Scenario      | How to load                                                                                  |
| ----------------------------------------- | ------------- | -------------------------------------------------------------------------------------------- |
| Test PR with unresolved CodeRabbit thread | AC1, AC2, AC4 | Create a PR; wait for CodeRabbit to post a Nitpick/Minor comment; do not resolve it          |
| Test PR with `✅ Addressed` comment       | AC2           | Push a fix commit to a PR where CodeRabbit has a finding; CodeRabbit auto-appends the marker |
| Test PR with human-authored thread        | AC6           | Open a PR; human reviewer posts an inline comment without resolving it                       |

---

## Troubleshooting

| Symptom                                                                        | Likely cause                                            | Fix                                                                                                                   |
| ------------------------------------------------------------------------------ | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `UNRESOLVED_THREAD_COUNT` not in output                                        | Running old version of `pr-review-loop.sh`              | Check out feature branch; confirm `check_unresolved_threads` function exists in script                                |
| GraphQL query returns 0 threads even though comments exist                     | Comments are REST inline comments, not review threads   | Verify the comment was posted as part of a review (pull request review thread), not a standalone PR comment           |
| `resolveReviewThread` mutation fails with "Not Found"                          | Using REST `comment_id` instead of GraphQL node `id`    | Re-run GraphQL query from Step 1; use the `id` field (node ID starting with `PRT_`)                                   |
| CodeRabbit thread still shows `isResolved: false` after `✅ Addressed` appears | Normal — `✅ Addressed` in body is the equivalence path | Script should still treat it as resolved; if not, check the `✅ Addressed` grep pattern in `check_unresolved_threads` |

---

## Known Limitations

- This smoke test requires a live GitHub PR with real CodeRabbit/Devin activity. It cannot be run in a fully offline or mocked environment.
- The `resolveReviewThread` mutation requires the authenticated user to have write access to the repository.
