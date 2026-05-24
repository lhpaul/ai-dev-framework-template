# GitHub Copilot Code Review Backstop — Spec

---

## Overview

This feature adds GitHub Copilot code review as a supported automated PR review
platform in the workflow's `pr-review-loop.sh` script. When a Copilot seat is
active on a repository, Copilot's built-in code review capability can run as a
lightweight, always-on secondary reviewer at no additional API cost beyond the
Copilot subscription. The goal is to let repository owners opt in to Copilot as
a backstop reviewer — complementing existing platforms such as CodeRabbit,
PR-Agent, and Claude Code Action — by declaring `copilot` in the `review.platforms`
list of `.ai-dev-workflow.yaml`.

---

## Use Cases

### Use Case 1: Enable Copilot as an automated PR reviewer

**Actor**: Repository administrator configuring the workflow

**Preconditions**:
- The repository has the GitHub Copilot for Pull Requests feature available (via
  an active Copilot seat or the Copilot GitHub App installed and configured on
  the repository).
- The administrator has write access to `.ai-dev-workflow.yaml`.

**Steps**:

1. The administrator adds `copilot` to the `review.platforms` list in
   `.ai-dev-workflow.yaml` (optionally also adding it to `phase_after_clean`).
2. A developer opens a pull request or pushes a new commit to an existing PR.
3. The orchestrator (or developer) runs `pr-review-loop.sh <pr-number>`.
4. The script requests a Copilot code review on the PR via the GitHub API.
5. The script polls until Copilot posts its review result (approved, commented,
   or changes requested).
6. The script reports the outcome: `clean` if Copilot approved or left only
   suggestions, `needs_fixes` if Copilot requested changes with blocking
   findings, or `escalate` if the platform timed out or was unavailable.

**Postconditions**:
- The PR review loop reflects Copilot's verdict as part of the aggregate result.
- Any blocking Copilot findings are surfaced to the developer as actionable
  feedback before human review.

**Information shown**:

- The platform name (`copilot`), result token (`clean`, `needs_fixes`, or
  `escalate`), comment count, and blocking count in the script's key-value output.

**Actions available**:

- When `RESULT=needs_fixes`, the developer addresses Copilot's review comments
  and re-runs the loop.
- When `RESULT=escalate` with `REASON=timeout` or `REASON=unavailable`, the
  orchestrator treats the platform as unreachable under the configured
  unavailability policy (skip, warn, or fail).

**Considerations**:

- GitHub Copilot code review is only available when the feature is active on the
  repository. If the feature is absent, the platform returns `escalate` with
  `REASON=unavailable` rather than crashing.
- Copilot may not post a formal review on spec branches or implementation-plan
  branches; the script applies the same branch-type-aware short timeout as other
  platforms.
- As of the knowledge cutoff (August 2025), Copilot code review is triggered by
  requesting Copilot as a reviewer via the GitHub Pulls API (the same mechanism
  as requesting a human reviewer). The review result is read back via the standard
  GitHub pull request reviews endpoint. The spec does not prescribe which exact
  API version or endpoint to use — those decisions belong in the implementation
  plan.

---

### Use Case 2: Copilot as a phase-after-clean secondary reviewer

**Actor**: Repository administrator

**Preconditions**:
- `copilot` is listed under both `review.platforms` and `review.phase_after_clean`
  in `.ai-dev-workflow.yaml`.
- At least one earlier platform (e.g., PR-Agent) is also configured.

**Steps**:

1. The orchestrator runs `pr-review-loop.sh`.
2. Earlier platforms run and reach a `clean` result.
3. The phase-after-clean gate opens; the script proceeds to run Copilot review.
4. Copilot reviews the PR and posts its verdict.
5. The script reports Copilot's result as a net-new secondary signal.

**Postconditions**:
- Copilot's verdict is recorded as a phase-after-clean net-new result separate
  from the primary gate.
- The `PHASE_AFTER_CLEAN_NET_NEW_BLOCKER` flag is set if Copilot requests changes.

**Information shown**:

- The same key-value output as Use Case 1, plus the phase-after-clean
  telemetry fields emitted by `pr-review-loop.sh`.

**Actions available**:

- Same as Use Case 1.

**Considerations**:

- Phase-after-clean behavior is inherited from the existing loop mechanism;
  no Copilot-specific logic is needed beyond implementing the platform function.

---

### Use Case 3: Copilot unavailable or not configured

**Actor**: Developer running `pr-review-loop.sh`

**Preconditions**:
- `copilot` is listed in `review.platforms` but the Copilot feature is not
  active on the repository (no seat, App not installed, or review feature
  disabled).

**Steps**:

1. The script attempts to request a Copilot review via the GitHub API.
2. The API returns an error or the reviewer request is silently ignored (no
   review posted within the timeout window).
3. The script returns `escalate` with `REASON=unavailable` or `REASON=timeout`.

**Postconditions**:
- The loop handles the result according to the `internal_reviewers_unavailable_policy`
  (or the equivalent external platform policy): either skipping the platform
  with a warning or hard-failing the loop.
- No unhandled crash or undefined exit code is emitted.

**Information shown**:

- `RESULT=escalate`, `REASON=unavailable` (or `timeout`) in the key-value output.

**Actions available**:

- The administrator can remove `copilot` from the platforms list or investigate
  why the Copilot feature is inactive on the repository.

**Considerations**:

- This use case must be handled gracefully — unavailability must not abort the
  workflow in an unexpected way.

---

## Business Rules

- `copilot` must be recognized as a valid value for `review.platforms` and
  `review.phase_after_clean` in `.ai-dev-workflow.yaml`.
- The Copilot review platform function must follow the same signature and exit
  code contract as all other platform functions in `pr-review-loop.sh`:
  - Exit 0 → `RESULT=clean`
  - Exit 1 → `RESULT=needs_fixes`
  - Exit 2 → `RESULT=escalate`
- Blocking Copilot review threads (changes-requested findings) must set
  `RESULT=needs_fixes` and report a non-zero `BLOCKING_COUNT`.
- Non-blocking Copilot comments (suggestions, informational notes) must not
  set `RESULT=needs_fixes`; they may be counted in `SUGGESTION_COUNT`.
- When Copilot is unavailable or the timeout elapses, the platform function must
  return exit code 2 (`escalate`) with an appropriate `REASON` value
  (`unavailable` or `timeout`).
- Copilot review is always optional — no existing workflow configuration or
  default behavior must change for repositories that do not declare `copilot` in
  their platforms list.
- The implementation must be marked clearly as optional in all new documentation.

---

## Operational Visibility

- **Logs**: The `pr-review-loop.sh` script emits platform-level key-value output
  lines (`PLATFORM_<n>_NAME`, `PLATFORM_<n>_RESULT`, etc.) for every platform
  run, including Copilot. No additional logging is required.
- **Audit trail**: Copilot's formal review (approved or changes-requested) is
  recorded on the PR by GitHub's own review system; no workflow-level audit trail
  is needed.

---

## Acceptance Criteria

- [ ] AC-1: When `copilot` is added to `review.platforms` in `.ai-dev-workflow.yaml`
  and `pr-review-loop.sh` is run on a PR in a repository with Copilot code
  review active, the script requests a Copilot review, polls for the result, and
  prints `PLATFORM_<n>_NAME=copilot` and `PLATFORM_<n>_RESULT=clean` (or
  `needs_fixes`) in its key-value output without error.

- [ ] AC-2: When Copilot requests changes on the PR (blocking findings), the
  script returns exit code 1 and prints `RESULT=needs_fixes`,
  `BLOCKING_COUNT>=1`.

- [ ] AC-3: When Copilot approves the PR or leaves only non-blocking comments,
  the script returns exit code 0 and prints `RESULT=clean`, `BLOCKING_COUNT=0`.

- [ ] AC-4: When the Copilot feature is not active on the repository and the
  review request fails or no review is posted within the timeout window, the
  script returns exit code 2 and prints `RESULT=escalate` with `REASON=unavailable`
  or `REASON=timeout`.

- [ ] AC-5: Repositories that do not include `copilot` in `review.platforms`
  experience no change in `pr-review-loop.sh` behavior; their existing
  configurations continue to work as before.

- [ ] AC-6: An integration guide document for the Copilot platform is added under
  `docs/workflow/development-workflow/integrations/`, clearly marked as optional
  and describing prerequisites (Copilot seat, App, or feature availability).

- [ ] AC-7: The `.ai-dev-workflow.yaml` template comment listing supported
  platforms is updated to include `copilot` as an optional backstop option.

- [ ] AC-8: The `run_copilot_review()` platform function passes a HARNESS_MODE
  unit test confirming the exit-code and key-value output contract for at least
  the `clean`, `needs_fixes`, and `escalate` (timeout) scenarios.

---

## Out of Scope (MVP)

- Supporting Copilot review on repositories that use GitHub Enterprise Server
  (GHES) with a self-hosted Copilot deployment — this requires different API
  endpoints and is not addressed here.
- Parsing individual Copilot review comment threads via GraphQL — the
  implementation may use the simpler REST pull-request-reviews endpoint; GraphQL
  thread resolution is not required unless the implementation plan determines it
  is necessary.
- Configuring the Copilot review model or review instructions via
  `.ai-dev-workflow.yaml` — only on/off participation is in scope.
- Triggering Copilot review automatically on PR open (that is a GitHub App or
  GitHub Actions concern, not a `pr-review-loop.sh` concern).
- A dedicated companion reviewer shell script analogous to
  `claude-code-action-reviewer.sh` — the implementation plan will decide whether
  inlining the logic in `pr-review-loop.sh` is sufficient.
