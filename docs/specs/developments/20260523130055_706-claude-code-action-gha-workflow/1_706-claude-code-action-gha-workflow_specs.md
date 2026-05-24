# Claude Code Action PR-Review Workflow — Spec

---

## Overview

This feature ships a GitHub Actions workflow file that invokes `anthropics/claude-code-action@v1` as an automated PR reviewer. The workflow is triggered on demand by `pr-review-loop.sh` (and optionally by a repository maintainer via workflow dispatch) and posts structured review comments directly to the pull request. It runs with the repository's own `ANTHROPIC_API_KEY` so it is not subject to any external vendor's per-hour review quota. Because the repository is public, GitHub Actions compute minutes are free; the only cost is token consumption (~$0.30 per review pass with the default Sonnet 4.6 model).

The workflow is designed to occupy the `phase_after_clean` slot in the automated review pipeline — it runs after PR-Agent has cleared, when the diff is settled and a single focused review pass is most valuable.

---

## Use Cases

### Use Case 1: Automated review triggered by pr-review-loop.sh

**Actor**: `pr-review-loop.sh` (automated CI script), acting on behalf of the developer or the Work Item Runner.

**Preconditions**:
- A pull request is open and has been cleared by the first-pass reviewer (PR-Agent or equivalent).
- The repository secret `ANTHROPIC_API_KEY` is configured.
- `claude-code-action` is listed in `review.platforms` (or `review.phase_after_clean`) in `.ai-dev-workflow.yaml`.

**Steps**:

1. `pr-review-loop.sh` dispatches the workflow using the GitHub workflow dispatch mechanism, passing the PR number as an input.
2. GitHub Actions picks up the dispatch event and starts the workflow job.
3. The workflow checks out the repository and runs `anthropics/claude-code-action@v1`, targeting the pull request.
4. Claude Code Action analyzes the PR diff and posts inline review comments and/or a summary review thread on the PR.
5. The workflow exits with a success or failure status that `pr-review-loop.sh` polls for.
6. `pr-review-loop.sh` reads the resulting PR review threads to determine whether the review is clean (no blocking findings) or needs fixes.

**Postconditions**: The pull request has a review thread from the Claude Code Action bot. `pr-review-loop.sh` can determine clean or needs-fixes state from the posted comments.

**Information shown**: Inline review comments on the PR diff, plus a top-level review summary comment. The review output follows the same thread structure that other automated reviewers (CodeRabbit, PR-Agent) produce.

**Actions available**: Developer reads the review comments, pushes fixes, and re-triggers the loop.

**Considerations**:

- If the workflow dispatch fails (e.g., workflow file is not on the target branch), `pr-review-loop.sh` must surface a clear error rather than silently treating the PR as clean.
- The workflow should run on `ubuntu-latest` to minimize configuration overhead and cost.
- Workflow run logs must be inspectable via `gh run view` so debugging is possible without GitHub web access.

---

### Use Case 2: Manual review dispatch by a maintainer

**Actor**: Repository maintainer (human) who wants to request a Claude Code Action review outside the automated loop.

**Preconditions**:
- A pull request is open.
- The maintainer has write access to the repository.

**Steps**:

1. Maintainer navigates to the Actions tab or uses `gh workflow run` to trigger the workflow, supplying the PR number as an input.
2. The workflow runs and posts review comments on the PR.
3. Maintainer reads the comments and decides whether to request changes or approve.

**Postconditions**: The PR has a review comment from Claude Code Action. The maintainer has an independent AI review perspective.

**Information shown**: Same inline and summary threads as the automated path.

**Actions available**: Maintainer may request changes, approve, or dismiss the review based on Claude's output.

**Considerations**:

- The workflow dispatch input (PR number) must be validated; an invalid or missing PR number should fail fast with a descriptive error rather than running against an unintended PR.
- Manual dispatch should not require any additional secrets beyond `ANTHROPIC_API_KEY`.

---

## Business Rules

- BR-1: The workflow must authenticate exclusively via the repository secret `ANTHROPIC_API_KEY`. No other Anthropic authentication method (OAuth, personal access token) may be used.
- BR-2: The default review model must be Sonnet 4.6 (`claude-sonnet-4-6`). This model is Anthropic's recommended default for CI code review and provides adequate review quality at approximately one-fifth the token cost of Opus models.
- BR-3: The workflow must be triggerable by `pr-review-loop.sh` via `gh workflow run` or an equivalent dispatch mechanism. It must not require human interaction to start.
- BR-4: The workflow must accept the target pull request number as an explicit input so `pr-review-loop.sh` can target the correct PR programmatically.
- BR-5: The workflow file must follow the existing CI workflow conventions of this repository: pinned action refs (SHA or version tag), explicit `permissions` blocks, and `concurrency` groups keyed on the PR number to prevent duplicate runs.
- BR-6: The workflow must include inline comments documenting the model choice (Sonnet 4.6 as default, rationale for cost and quality), and a note that public-repository Actions minutes are free so per-invocation compute cost is zero.
- BR-7: The workflow must be scoped to trigger only on `workflow_dispatch` events (not on every PR open or push), so it does not run unsolicited and does not duplicate the role of other always-on reviewers (PR-Agent).
- BR-8: The workflow must not store or log the `ANTHROPIC_API_KEY` value. Secrets must be passed to the action exclusively as environment variables or action inputs, never echoed or printed.
- BR-9: Optional size-based model routing (Haiku for small docs/config-only PRs; Opus for large or high-risk diffs) is explicitly out of scope for v1. The workflow must not implement conditional model selection in this iteration.

---

## Operational Visibility

- **Logs**: Each workflow run produces a GitHub Actions run log accessible via `gh run view <run-id> --log`. The log must include the PR number being reviewed and the model used.
- **Notifications**: GitHub automatically notifies PR participants of new review comments posted by the action.
- **Audit trail**: The GitHub Actions run history provides a complete record of when the workflow was triggered, by whom (dispatch event attribution), and what exit code it produced.

---

## Acceptance Criteria

- [ ] A workflow file exists at `.github/workflows/claude-code-review.yml` (or an equivalent name that clearly identifies it as the Claude Code Action review workflow).
- [ ] The workflow triggers exclusively on `workflow_dispatch` with a required input field for the pull request number.
- [ ] The workflow runs `anthropics/claude-code-action@v1` with the model set to `claude-sonnet-4-6` as its default.
- [ ] The workflow authenticates via `ANTHROPIC_API_KEY` passed as a secret; no other Anthropic credential is referenced.
- [ ] The workflow file includes a `permissions` block that grants only the minimum permissions needed (pull requests write, contents read at minimum).
- [ ] The workflow file includes a `concurrency` group keyed on the PR number to prevent duplicate simultaneous runs for the same PR.
- [ ] The action reference is pinned to a specific version tag or commit SHA (not a floating `main` or `latest` reference).
- [ ] Inline comments in the workflow file document: (a) the choice of Sonnet 4.6 as the default model and its cost rationale, and (b) that public-repo Actions minutes are free.
- [ ] A maintainer can manually trigger the workflow via `gh workflow run claude-code-review.yml -f pr_number=<N>` and see a review comment posted on PR `<N>`.
- [ ] `pr-review-loop.sh` can dispatch the workflow programmatically and poll for run completion using only `gh` CLI calls.
- [ ] The workflow does not trigger automatically on PR open, push, or synchronize events.

---

## Out of Scope (MVP)

- Size-based model routing (Haiku for tiny PRs, Opus for large or high-risk diffs) — deferred to a follow-up issue as noted in the epic brief.
- Enabling prompt caching or scoping the review to the diff only — these are optimization options for a future iteration.
- Registering `claude-code-action` as a valid platform value in `.ai-dev-workflow.yaml` or implementing the `run_claude_code_review()` function in `pr-review-loop.sh` — those are covered by sibling issues #705 and #708 respectively.
- Integration documentation (`docs/workflow/development-workflow/integrations/`) — covered by sibling issue #707.
- A fallback or retry mechanism inside the workflow itself if the API is temporarily unavailable — retry logic lives in `pr-review-loop.sh`, not in the workflow file.
- Removing or replacing CodeRabbit from the review pipeline — that change is part of issue #708 (config reslotting).
