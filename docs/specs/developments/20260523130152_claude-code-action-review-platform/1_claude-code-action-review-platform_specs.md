# Claude Code Action Review Platform — Spec

---

## Overview

This feature adds Claude Code Action as a supported automated PR review platform in the workflow tooling. Teams using this template can opt in to Claude Code Action as a review platform by setting `claude-code-action` as a value in `review.platforms` or `review.phase_after_clean` in `.ai-dev-workflow.yaml`. The review is triggered via a GitHub Actions workflow dispatch, runs under the repository's own `ANTHROPIC_API_KEY`, and is not subject to any vendor-imposed per-hour rate cap. This enables faster feedback cycles when the existing CodeRabbit Pro rate limit (5 reviews per hour) throttles the automated reviewer loop.

---

## Use Cases

### Use Case 1: Trigger Claude Code Action review during the automated reviewer loop

**Actor**: The automated PR reviewer loop (`pr-review-loop.sh`) running as part of the workflow orchestration or CI
**Preconditions**:
- A PR is open and not in draft state
- `claude-code-action` is listed in `review.platforms` or `review.phase_after_clean` in `.ai-dev-workflow.yaml`
- The repository has a Claude Code Action GitHub Actions workflow that responds to workflow dispatch events and posts a PR review
- An `ANTHROPIC_API_KEY` is configured as a repository secret available to Actions

**Steps**:

1. The reviewer loop reaches the `claude-code-action` platform in its configured platform list
2. The loop checks whether there are existing unresolved review threads from the Claude Code Action bot on the PR; if any exist, it exits immediately with a `needs_fixes` result without triggering a new review
3. If no existing blocking threads are found, the loop dispatches the Claude Code Action workflow via a GitHub Actions workflow dispatch event, passing the PR number as an input
4. The loop polls the GitHub Actions API at a configurable interval for the dispatched run to complete
5. When the run completes successfully, the loop inspects the PR for new review threads posted by the Claude Code Action bot
6. If the bot posted no new blocking threads, the loop reports `clean` for this platform
7. If the bot posted one or more blocking threads, the loop reports `needs_fixes` with the count of unresolved threads

**Postconditions**:
- The reviewer loop emits a structured result (`clean`, `needs_fixes`, or `escalate`) for the `claude-code-action` platform, consistent with the output of other supported platforms
- A subsequent fixer agent can address any blocking threads and re-trigger the loop

**Information shown**:

- The platform result (clean / needs_fixes / escalate) in the reviewer loop output key-value block
- The count of unresolved blocking review threads posted by the Claude Code Action bot
- The GitHub Actions run URL for traceability

**Actions available**:

- The orchestrator can route the result to a fixer agent when `needs_fixes` is reported
- The orchestrator can escalate to the human when `escalate` is reported

**Considerations**:

- If the dispatched GitHub Actions run fails (non-zero exit, cancelled, or timed out), the loop reports `escalate` with reason `timeout` so the orchestrator treats it as a timed-out reviewer rather than a hard failure
- If the Actions workflow file does not exist in the repository, the dispatch will fail; the loop reports `escalate` with reason `unavailable`
- The poll interval and maximum wait time are configurable via environment variables so teams can tune them for their repository's CI latency
- Duplicate review detection uses the same unresolved-thread check as `codex-github` — if the Claude Code Action bot already has unresolved threads from a prior run, those are surfaced immediately without triggering a new run

---

### Use Case 2: Configure Claude Code Action as an after-clean reviewer

**Actor**: Repository maintainer setting up the workflow
**Preconditions**:
- The repository uses the AI development workflow template
- A Claude Code Action GitHub Actions workflow is present in the repository

**Steps**:

1. The maintainer adds `claude-code-action` to `review.phase_after_clean` in `.ai-dev-workflow.yaml`
2. On each PR, the reviewer loop first clears the pre-clean platforms (e.g., `pr-agent`)
3. Only after the pre-clean gate passes does the loop trigger the Claude Code Action review
4. The Claude Code Action review result is emitted alongside results from other after-clean platforms

**Postconditions**:
- The Claude Code Action review runs only after earlier platforms are clean, so its findings are measurable as net-new signal
- The overall loop result reflects whether Claude Code Action blocked or approved the PR

**Information shown**:

- Phase-after-clean results in the reviewer loop output, including whether `claude-code-action` was filtered out before the pre-clean gate passed

**Actions available**:

- The maintainer can list `claude-code-action` in both `review.platforms` and `review.phase_after_clean` to enable it as an after-clean reviewer

**Considerations**:

- When listed in `review.phase_after_clean` but no pre-clean platforms are configured, the loop runs Claude Code Action as if it were a standard platform (no gating behavior)

---

### Use Case 3: Skip Claude Code Action review when the Actions workflow is absent

**Actor**: The automated PR reviewer loop
**Preconditions**:
- `claude-code-action` is listed in `review.platforms`
- The repository does not have the required Claude Code Action GitHub Actions workflow file

**Steps**:

1. The reviewer loop reaches the `claude-code-action` platform
2. The loop attempts to dispatch the workflow and receives a dispatch error (workflow not found)
3. The loop reports `escalate` with reason `unavailable`

**Postconditions**:
- The orchestrator treats the result as an unavailable reviewer and surfaces it in the run summary
- No review threads are posted; the PR is not blocked by an absent workflow

**Considerations**:

- The loop must not silently pass as `clean` when the workflow is absent — escalation ensures the human is informed that the platform was not reachable

---

## Business Rules

- The `claude-code-action` platform is a valid value for both `review.platforms` and `review.phase_after_clean` in `.ai-dev-workflow.yaml`
- The reviewer loop must check for existing unresolved threads from the Claude Code Action bot before dispatching a new review run; if any are found, the loop reports `needs_fixes` without triggering a new run
- The loop must poll GitHub Actions run status at a configurable interval and respect a configurable maximum wait time
- When the Actions run does not complete within the maximum wait time, the loop reports `escalate` with reason `timeout`
- When the Actions workflow cannot be dispatched (file absent, permissions error), the loop reports `escalate` with reason `unavailable`
- The result reporting format of the new platform must be identical to that of the existing `codex-github` platform: the same result tokens (`clean`, `needs_fixes`, `escalate`) and the same set of output key-value pairs are produced
- The Claude Code Action bot's review threads are identified by the bot's GitHub login; this login must be configurable via an environment variable so teams that host the bot under a different account can override the default
- The platform name used in all reviewer loop output (`PLATFORM` key) is the string `claude-code-action`

---

## Acceptance Criteria

- [ ] When `claude-code-action` is added to `review.platforms` in `.ai-dev-workflow.yaml`, running `pr-review-loop.sh` against a PR invokes the Claude Code Action review and emits a `PLATFORM=claude-code-action` key-value block in its output
- [ ] When the Claude Code Action bot has no unresolved review threads on the PR and the dispatched Actions run succeeds with no new blocking threads, the reviewer loop reports `RESULT=clean` for the `claude-code-action` platform
- [ ] When the Claude Code Action bot has unresolved review threads on the PR before the loop runs, the reviewer loop reports `RESULT=needs_fixes` and `BLOCKING_COUNT` equal to the number of unresolved threads, without dispatching a new Actions run
- [ ] When the dispatched Actions run completes and the bot posts new blocking review threads, the reviewer loop reports `RESULT=needs_fixes` and `BLOCKING_COUNT` equal to the count of new unresolved threads
- [ ] When the Actions run does not complete within the configured maximum wait time, the reviewer loop reports `RESULT=escalate` and `REASON=timeout`
- [ ] When the Claude Code Action workflow cannot be dispatched (workflow file absent or dispatch API error), the reviewer loop reports `RESULT=escalate` and `REASON=unavailable`
- [ ] The Claude Code Action bot login used for thread identification is configurable via an environment variable; the default value matches the standard Claude Code Action bot account
- [ ] When `claude-code-action` is listed in `review.phase_after_clean`, the reviewer loop skips it until all pre-clean platforms report clean, consistent with the existing `phase_after_clean` behavior for other platforms
- [ ] The key-value output format emitted for the `claude-code-action` platform (keys: `RESULT`, `PLATFORM`, `PR_NUMBER`, `BRANCH`, `FIX_AGENT`, `COMMENT_COUNT`, `BLOCKING_COUNT`, `SUGGESTION_COUNT`, and optionally `REASON`) is identical to that emitted for the `codex-github` platform

---

## Out of Scope (MVP)

- Authoring or modifying the Claude Code Action GitHub Actions workflow file itself (that is covered by sibling item #706)
- Documentation updates to `.ai-dev-workflow.yaml` schema or workflow integration guides (covered by sibling item #707)
- CHANGELOG and configuration sample updates (covered by sibling item #708)
- Support for multiple Claude Code Action bots on the same repository
- Configuring which review checklist or prompt the Claude Code Action bot uses (that is a concern of the Actions workflow, not the reviewer loop)
- Automated retry of the Actions run on transient GitHub Actions infrastructure failures (the loop escalates on timeout; retries are left to the human or a future improvement)
