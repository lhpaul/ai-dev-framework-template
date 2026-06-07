# Release Stamping Smoke Test

## Purpose

Verify that the release post-merge cleanup flow records a production release
version on shipped issues through the configured tracker provider, with GitHub
Milestones as the GitHub Issues / GitHub Projects release primitive.

## Preconditions

- `gh` is authenticated for a test repository that uses GitHub Issues.
- `.ai-dev-workflow.yaml` sets `issue_tracker.provider` to `github_projects` or
  `github_issues`.
- The repository has a GitHub Project configured when testing board visibility.
- The release cleanup helper includes the release-stamping implementation.

## Scenario 1: GitHub milestone is created and assigned

1. Create a temporary GitHub issue:

   ```bash
   set -euo pipefail

   ISSUE_URL="$(gh issue create --title "Smoke: release stamping" --body "Temporary release stamping smoke test")"
   ISSUE_NUMBER="${ISSUE_URL##*/}"
   ```

2. If testing GitHub Projects status transitions, add the issue to the project
   board and set its Status to `Merged` using the existing workflow helpers.

3. Use a clearly temporary version:

   ```bash
   set -euo pipefail

   VERSION="v999.999.999-smoke"
   ```

4. Run the release-stamp helper directly, or run the release cleanup helper in a
   controlled test repository after both release PR merge preconditions are
   satisfied.

5. Verify the milestone exists and is assigned:

   ```bash
   gh issue view "$ISSUE_NUMBER" --json milestone --jq '.milestone.title'
   ```

   Expected result: the command prints `v999.999.999-smoke`.

6. If testing GitHub Projects, add the built-in Milestone field to a board view
   and verify the issue row displays `v999.999.999-smoke`.

## Scenario 2: Existing milestone is reused

1. Re-run the same release-stamp operation for the same issue and version.
2. Verify no duplicate milestone was created:

   ```bash
   gh api repos/:owner/:repo/milestones --jq '[.[] | select(.title == "v999.999.999-smoke")] | length'
   ```

   Expected result: `1`.

## Scenario 3: Unsupported provider skips softly

1. In a temporary copy of `.ai-dev-workflow.yaml`, set:

   ```yaml
   issue_tracker:
     provider: none
   ```

2. Run the provider-routed release-stamp helper against the temporary
   configuration.

3. Verify the helper logs a skip message and exits successfully.

## Cleanup

1. Close the temporary issue:

   ```bash
   set -euo pipefail

   gh issue close "$ISSUE_NUMBER" --comment "Closing release stamping smoke test issue."
   ```

2. Close or delete the temporary milestone according to repository policy:

   ```bash
   gh api repos/:owner/:repo/milestones \
     --jq '.[] | select(.title == "v999.999.999-smoke") | .number'
   ```

   Use the returned milestone number with the GitHub API if deletion is required.

## Expected Results

- GitHub providers create or reuse a milestone named for the release version.
- The shipped issue is assigned to that milestone.
- GitHub Projects can display the release version through the built-in Milestone
  field.
- Unsupported or disabled tracker providers log a clear skip and do not fail the
  release flow.
