# Codex GitHub Integration Reviewer Path — Spec

**Depends on**: codex-reviewer-runtime-fallback

---

## Brief Coverage (issue #309)

Brief objectives extracted from the issue description, mapped to spec coverage:

| Brief objective | Spec coverage |
|---|---|
| Post a review-trigger comment on the PR addressed to the Codex GitHub bot | Use Case 1 (steps 2–3), BR-2, AC-2 |
| Poll for the Codex bot's response comment on the PR | Use Case 1 (steps 4–6), BR-3, BR-9, AC-2 |
| Interpret the bot's verdict (APPROVE / CHANGES_REQUESTED) as the reviewer decision | BR-4, AC-3, AC-4 |
| Works from ANY runner — not just Codex CLI contexts (Claude Code, Cursor, headless CI) | BR-1, AC-1 |
| Document the new reviewer path in the Step 7a reviewer dispatch mechanism | AC-8 |
| Document the new reviewer value in the workflow configuration manifest | AC-9 |
| Update agent guidance files for all supported runner contexts | AC-10 |
| Relevant Codex skills if the trigger mechanism differs for Codex-native runs | Out of Scope — see Deferral Note below |

**Deferral notes**:

- "Relevant Codex skills if the trigger mechanism differs for Codex-native runs":
  The `codex-github` reviewer path uses only `gh` CLI access, which is identical
  across all runner contexts by design. There is no per-runner variation in the
  trigger mechanism, so no separate Codex skill path is required. The existing
  `codex` (CLI) reviewer path and its Codex skills remain unchanged. No new Codex
  skill is needed for `codex-github`. Human confirmation not requested — the
  rationale is self-evident from the feature goal (runner-agnostic operation).

---

## Overview

The Step 7a internal review gate dispatches `codex` as an internal reviewer by
invoking the Codex CLI directly. This works when Codex is the top-level runner,
but fails in all automated subagent contexts (Claude Code subagents, Cursor
subagents, headless CI) because those environments cannot invoke the Codex CLI.
Every batch run from such contexts produces "Skipped: codex (unreachable)"
warnings on every PR.

This feature adds a `codex-github` reviewer entry that works from any runner by
interacting with the Codex GitHub App instead of the Codex CLI. A runner posts a
review-trigger comment on the PR, waits for the Codex bot to respond, and
interprets the bot's reply as the reviewer verdict. Because the interaction uses
only `gh` CLI calls — which are available in every runner context — `codex-github`
is reachable wherever the existing `gh`-based polling is already used.

---

## Use Cases

### Use Case 1: Codex GitHub Bot Review — Approve Path

**Actor**: Work Item Runner (any runner context: Claude Code subagent, Cursor
subagent, Codex runner, or direct human shell)
**Preconditions**:
- A draft PR is open on a workflow branch.
- `.ai-dev-workflow.yaml` lists `codex-github` in `review.internal_reviewers`.
- The Codex GitHub App is installed on the repository and configured to respond
  to review-trigger comments.
- The runner has `gh` CLI access to the repository.

**Steps**:
1. The Work Item Runner reaches `codex-github` in the Step 7a reviewer list.
2. The runner classifies `codex-github` as reachable (it only requires `gh` CLI
   access, which is available in all supported runner contexts).
3. The runner posts a review-trigger comment to the PR via `gh pr comment`,
   addressed to the Codex GitHub bot using the configured trigger phrase.
4. The runner begins polling the PR for a response comment from the Codex bot,
   checking at the configured poll interval.
5. The Codex GitHub App processes the trigger and posts a review response to the
   PR within the polling window.
6. The runner detects the bot's response comment and parses it to determine the
   verdict.
7. The bot's response indicates approval (no blocking findings or an explicit
   approval signal).
8. The runner records the verdict as `APPROVED` for the `codex-github` reviewer.

**Postconditions**:
- The `codex-github` reviewer verdict is `APPROVED`.
- The PR now has both the trigger comment and the Codex bot response in its
  comment history.
- The Step 7a gate proceeds to check remaining reviewers or, if all approved,
  calls `gh pr ready`.

**Information shown**:
- Trigger comment: visible in the PR comment thread, identifying the review
  trigger and the runner context.
- Bot response comment: the Codex bot's review output, visible to all PR
  participants.

**Actions available**:
- Human reviewers can inspect the Codex bot response in the PR comment history
  before merging.

**Considerations**:
- If the Codex GitHub App is not installed or does not respond within the
  configured timeout, the runner treats this as a hard timeout (see Use Case 3).
- The trigger phrase format is determined by the Codex GitHub App's configuration
  and must be documented in the workflow configuration.

---

### Use Case 2: Codex GitHub Bot Review — Changes Requested Path

**Actor**: Work Item Runner (any runner context)
**Preconditions**:
- Same as Use Case 1.
- The Codex bot finds blocking issues in the PR content.

**Steps**:
1–6. Same as Use Case 1 steps 1–6.
7. The bot's response indicates changes are required (blocking findings are
   present in the response).
8. The runner records the verdict as `NEEDS REVISION` for the `codex-github`
   reviewer.
9. The runner extracts the blocking findings from the bot response to provide
   context to the fixer.

**Postconditions**:
- The `codex-github` verdict is `NEEDS REVISION`.
- The Step 7a gate applies fixes (per the existing multi-reviewer fix loop) and
  re-runs all internal reviewers.
- The Codex bot response remains visible in the PR comment history.

**Information shown**:
- The bot response comment with specific findings.

**Actions available**:
- The fixer agent (or human) reviews the findings in the Codex bot response
  comment and applies corrections.

**Considerations**:
- After fixes are pushed, the runner re-triggers the `codex-github` review by
  posting a new trigger comment on the updated PR. The bot's previous response
  remains in the thread as history.

---

### Use Case 3: Codex GitHub Bot Timeout

**Actor**: Work Item Runner (any runner context)
**Preconditions**:
- Same as Use Case 1.
- The Codex bot does not respond within the configured maximum wait time.

**Steps**:
1–4. Same as Use Case 1 steps 1–4.
5. The runner polls for the bot response until the maximum wait time is reached.
6. No response from the Codex bot is detected.
7. The runner records the `codex-github` reviewer as `timed out`.
8. The runner applies the configured timeout policy:
   - Under the default `warn` policy: records the timeout as equivalent to
     `skipped (unavailable)`, posts a warning comment to the PR, and proceeds
     with the remaining reachable reviewers.
   - Under `fail-if-any-unavailable` policy: hard-fails the Step 7a gate.

**Postconditions**:
- The PR has a warning comment noting that the Codex GitHub bot did not respond.
- The Step 7a gate exits according to the configured policy.

**Information shown**:
- Warning comment in the PR noting the timeout, the trigger comment that was
  posted, and remediation guidance (e.g., manually trigger the review or re-run
  Step 7a).

**Actions available**:
- A human can manually trigger the Codex GitHub App review by posting the
  trigger comment themselves.
- The operator can adjust the timeout duration in the workflow configuration.

**Considerations**:
- A timeout does not indicate a bug in the PR; it indicates an infrastructure
  availability issue with the Codex GitHub App.

---

### Use Case 4: Codex GitHub Integration Misconfigured (App Not Installed)

**Actor**: Work Item Runner (any runner context)
**Preconditions**:
- `codex-github` is listed in `review.internal_reviewers`.
- The Codex GitHub App is NOT installed on the repository (or is installed but
  not responding to the trigger comment format).
- The runner has no way to verify app installation before posting the trigger
  comment.

**Steps**:
1. The runner classifies `codex-github` as reachable (it only requires `gh` CLI).
2. The runner posts a trigger comment.
3. No bot response appears within the maximum wait time (same as Use Case 3).
4. The runner treats this identically to a timeout (Use Case 3).

**Postconditions**:
- Same as Use Case 3.
- The human operator is alerted via the warning comment that the bot did not
  respond, with guidance to verify the Codex GitHub App installation.

**Considerations**:
- Distinguishing "app not installed" from "app slow to respond" is not required
  at the spec level — both are handled as timeouts. The warning comment should
  suggest verifying the app installation as part of the remediation guidance.

---

### Use Case 5: `codex-github` Alongside `codex` CLI Reviewer

**Actor**: Work Item Runner operating from a Codex-native runner context
**Preconditions**:
- `.ai-dev-workflow.yaml` lists both `codex` (direct CLI) and `codex-github`
  (GitHub integration) in `review.internal_reviewers`.
- The runner is a Codex runner where the Codex CLI is directly reachable.

**Steps**:
1. The runner classifies both `codex` (CLI) and `codex-github` (GitHub bot) as
   reachable.
2. Both reviewers run sequentially in the declared order.
3. Each reviewer produces an independent verdict.
4. The Step 7a gate requires all reviewers to approve before proceeding.

**Postconditions**:
- Both reviewer paths ran; the PR has both direct CLI review output and a bot
  response comment from the GitHub App.

**Considerations**:
- Running both is allowed but doubles the review time. This is a valid
  configuration for teams requiring dual coverage.
- Most teams will prefer one or the other, not both.

---

## Business Rules

- **BR-1 — `codex-github` is classified as universally reachable**: Unlike
  `codex` (CLI), which requires the Codex runtime to be present, `codex-github`
  only requires `gh` CLI access. The runtime-availability check must classify
  `codex-github` as reachable from all supported runner contexts (Claude Code,
  Cursor, Codex, and direct human shell) as long as `gh` CLI is authenticated.

- **BR-2 — Trigger comment is required before polling**: The runner must post
  the review-trigger comment to the PR before starting to poll for a response.
  Polling without a prior trigger is not permitted.

- **BR-3 — Bot response detection is comment-based**: The runner detects the
  Codex bot's response by scanning new PR comments from the known Codex GitHub
  App bot account. The response must appear after the trigger comment timestamp.

- **BR-4 — Verdict parsing**: A bot response is classified as:
  - `APPROVED`: the response contains no blocking findings or includes an
    explicit approval signal as defined by the Codex GitHub App output format.
  - `NEEDS REVISION`: the response contains one or more blocking findings.
  The exact parsing rules for the bot response format are an implementation
  decision for the plan stage.

- **BR-5 — Timeout treated as unavailability**: If no bot response is detected
  within the maximum wait time, the outcome is treated identically to an
  unreachable reviewer under the configured policy (`warn` or
  `fail-if-any-unavailable`). The reviewer is recorded as `timed out`, which
  is a sub-case of `skipped (unavailable)`.

- **BR-6 — Re-trigger on each fix cycle**: When `codex-github` requires
  revision and fixes are applied, a new trigger comment must be posted after the
  fix push to start a fresh `codex-github` review cycle. The previous bot
  response is not re-used.

- **BR-7 — Configurable trigger phrase**: The trigger phrase used in the
  trigger comment (e.g., `@codex review`) must be configurable in
  `.ai-dev-workflow.yaml` or have a documented default. The implementation plan
  determines the exact configuration key.

- **BR-8 — `codex-github` is independent of `codex` (CLI)**: The two reviewer
  entries are distinct. Having `codex-github` in `internal_reviewers` does not
  affect the reachability classification of `codex` (CLI) and vice versa.

- **BR-9 — Poll interval and timeout are configurable**: The polling interval
  and maximum wait time for the bot response must have documented defaults and
  be overridable in `.ai-dev-workflow.yaml` or `.tmp/template-config.json`.
  Default values are an implementation decision for the plan stage.

- **BR-10 — No duplicate trigger comments**: If the runner detects that it
  already posted a trigger comment for the current review cycle (same commit
  SHA), it must not post a second trigger. This prevents duplicate reviews when
  Step 7a is retried.

---

## Operational Visibility

- **Trigger comment**: Posted to the PR by the runner before polling begins.
  Visible to all PR participants. Identifies the runner context and review cycle.
- **Bot response comment**: The Codex GitHub App's response, posted to the PR.
  Contains the full review output from the bot.
- **Warning or timeout comment**: If the bot does not respond in time or is
  unavailable, the runner posts a warning comment identifying the reviewer,
  the trigger comment that was posted, and remediation guidance.
- **Step 7a summary comment**: The mandatory Step 7a summary comment (per the
  existing requirement) lists `codex-github` in the effective reviewer set when
  it runs to completion, or in the skipped/timed-out list when it does not.
- **Console / agent log**: The runner logs trigger, polling status, and verdict
  events to the agent output for the Portfolio Orchestrator to observe.

---

## Acceptance Criteria

- [ ] When `codex-github` is listed in `review.internal_reviewers`, the
      runtime-availability check classifies it as reachable from Claude Code
      subagent, Cursor subagent, Codex runner, and direct human shell contexts
      (any runner with `gh` CLI access).
- [ ] The runner posts a review-trigger comment to the PR before polling for
      the bot response. The trigger comment is visible in the PR comment thread.
- [ ] When the Codex GitHub App responds with no blocking findings, the runner
      records the verdict as `APPROVED` and the Step 7a gate proceeds normally.
- [ ] When the Codex GitHub App responds with blocking findings, the runner
      records the verdict as `NEEDS REVISION`. The fix loop is entered and a
      new trigger comment is posted after the fix push.
- [ ] When the Codex bot does not respond within the configured timeout, the
      runner posts a warning comment and applies the configured
      `internal_reviewers_unavailable_policy` (default: `warn` — proceed with
      remaining reachable reviewers).
- [ ] A new trigger comment is posted for each Step 7a review cycle on a given
      commit SHA; duplicate trigger comments for the same cycle are not posted.
- [ ] The Step 7a summary comment lists `codex-github` in the effective reviewer
      set when it produces a verdict, or in the skipped/timed-out list when it
      does not, using the existing summary comment format.
- [ ] The workflow documentation reflects `codex-github` as a reachable reviewer
      from all supported runner contexts for every PR branch type (spec, plan,
      implementation).
- [ ] The workflow configuration manifest documents `codex-github` as a supported
      reviewer value with its configuration requirements (trigger phrase and
      timeout) so that operators can enable it by listing it in
      `review.internal_reviewers`.
- [ ] Agent guidance for all supported runner contexts (Claude Code, Cursor)
      reflects the `codex-github` dispatch path so that runners dispatched from
      any of those contexts know how to execute the GitHub bot review.

---

## Out of Scope (MVP)

- Modifying the Codex GitHub App itself or its server-side behavior — this
  feature only adds a client-side interaction path using the app's existing
  trigger comment mechanism.
- Adding a new reviewer type other than `codex-github` (e.g., other GitHub App
  bot reviewers).
- Automating the installation or configuration of the Codex GitHub App on the
  repository — that is a one-time manual setup step documented in the integration
  guide.
- Implementing cursor-based pagination for PR comment polling (the number of
  comments between trigger and response is expected to be small).
- Changing the existing `codex` (CLI) reviewer behavior — `codex` and
  `codex-github` are independent entries.
- Adding `codex-github` as a replacement for the `review.platforms` external
  reviewer loop (Step 7) — this feature is scoped to Step 7a (internal review
  gate) only.
- Per-stage dispatch customization for `codex-github` (e.g., different trigger
  phrases for spec vs. implementation PRs) — a single trigger phrase applies to
  all branch types in the MVP.
