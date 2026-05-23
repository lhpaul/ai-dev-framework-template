# Claude Code Action Integration Guide — Spec

---

## Overview

This feature ships the user-facing setup documentation for `claude-code-action` as an automated PR review platform. It creates a new integration guide (`claude-code-action.md`) covering how a downstream project operator adds the platform to their repository, and it updates the platform reference table in `pr-review-platform.md` to include `claude-code-action` as a supported platform. The goal is to give any downstream project that adopts this framework template a clear, self-contained path to wiring up Claude Code Action as an uncapped, own-key PR reviewer without per-hour vendor rate limits.

---

## Use Cases

### Use Case 1: Operator Sets Up Claude Code Action for the First Time

**Actor**: Repository operator (a developer or DevOps engineer setting up a downstream project that uses this framework template)
**Preconditions**:

- The operator has a repository that uses this AI development framework template.
- The operator has admin access to the repository's GitHub settings (to add secrets).
- The operator has an Anthropic API key (from `console.anthropic.com`).
- The sibling workflow file (`claude-code-action-review.yml` or equivalent, shipped by issue #706) exists at `.github/workflows/` in the template.

**Steps**:

1. The operator opens the integration guide at `docs/workflow/development-workflow/integrations/claude-code-action.md`.
2. The operator follows the setup steps:
   a. Adds `ANTHROPIC_API_KEY` as a GitHub Actions repository secret.
   b. Copies or references the `.github/workflows/` workflow file that ships the Claude Code Action job.
   c. Configures the trigger phrase (default: `@claude review`) and notes which GitHub user or bot login posts review threads (for attribution purposes).
3. The operator updates `.ai-dev-workflow.yaml` to include `claude-code-action` in `review.platforms` (and optionally in `review.phase_after_clean`), following the example in the guide.
4. The operator opens or re-runs a PR to confirm that `pr-review-loop.sh` triggers the Claude Code Action workflow and receives a review result.

**Postconditions**:

- The Claude Code Action workflow fires on the next PR review trigger.
- Review threads from `claude-code-action` are visible on the PR and correctly parsed by `pr-review-loop.sh`.
- The operator understands the model selection guidance and cost profile.

**Information shown**:

- The integration guide shows the full setup checklist, example YAML snippets, and notes on model selection, cost, and why there is no per-hour vendor cap.

**Actions available**:

- The operator can follow the guide's setup checklist to diagnose common issues (e.g., missing secret, workflow not triggering, review threads not detected).

**Considerations**:

- The guide must note the GitHub bot login used by Claude Code Action for thread attribution, so operators can configure `pr-review-loop.sh` to identify review threads posted by that bot.
- The guide must note that GitHub Actions minutes are free for public repositories, so the only cost is Anthropic API token usage.
- The guide must not duplicate the contents of the workflow file itself — it should reference the shipped workflow file rather than embedding a full copy.

---

### Use Case 2: Operator Chooses a Non-Default Review Model

**Actor**: Repository operator
**Preconditions**:

- The operator has already completed the basic setup from Use Case 1.
- The operator has PRs with large diffs (e.g., over 500 lines changed) where they want deeper analysis, or small docs/config PRs where they want lower cost.

**Steps**:

1. The operator reads the model choice guidance section of the integration guide.
2. The operator decides to configure Opus as the default for large diffs (or Haiku for small PRs), following the guidance's example workflow input configuration.
3. The operator updates the workflow file to set the `model` input to the desired value (e.g., `claude-opus-4-7`).
4. The next review run uses the selected model.

**Postconditions**:

- The review runs with the chosen model.
- The operator understands the cost tradeoffs between Sonnet (default), Haiku (fast/cheap), and Opus (deep review).

**Information shown**:

- Guidance table or prose: model name, recommended use case, approximate per-review cost, and when to escalate from Sonnet to Opus.

**Actions available**:

- The operator can switch models by editing the workflow input and does not need to change `pr-review-loop.sh` or `.ai-dev-workflow.yaml`.

**Considerations**:

- Model names and pricing change over time; the guide should note that operators should verify current model availability and pricing at `console.anthropic.com`.
- The guide is not authoritative on Anthropic pricing — it should give representative order-of-magnitude figures (e.g., "approximately $X per typical PR") rather than exact token prices.

---

### Use Case 3: Operator Reads the Platform Reference Table

**Actor**: Repository operator or framework user browsing `pr-review-platform.md`
**Preconditions**:

- The operator is reviewing the available automated PR review platforms supported by this framework.

**Steps**:

1. The operator opens `docs/workflow/development-workflow/integrations/pr-review-platform.md`.
2. The operator finds `claude-code-action` listed in the supported platforms table alongside `coderabbit`, `greptile`, `devin`, and `codex-github`.
3. The operator follows the link to the full `claude-code-action.md` integration guide for setup instructions.

**Postconditions**:

- The operator can discover and navigate to the Claude Code Action integration guide from the platform reference table.

**Information shown**:

- Platform name, brief description (one-liner), link to the full guide.

**Actions available**:

- Navigate to the full guide.

**Considerations**:

- The platform table entry must be consistent with the platform identifier used in `.ai-dev-workflow.yaml` (`claude-code-action`).

---

## Business Rules

- **BR-1 — Platform identifier consistency**: The platform name used in the integration guide, in `pr-review-platform.md`, and in `.ai-dev-workflow.yaml` examples must all use the same identifier: `claude-code-action`.

- **BR-2 — No per-hour vendor cap explanation is mandatory**: The guide must explicitly explain why Claude Code Action has no per-hour vendor review cap: it runs in the operator's own GitHub Actions CI using the operator's own Anthropic API key. This is the primary differentiator from CodeRabbit's Pro rate limit.

- **BR-3 — Secret name is fixed**: The required GitHub Actions secret name is `ANTHROPIC_API_KEY`. The guide must document this exact name and not suggest alternatives.

- **BR-4 — Bot login documentation is mandatory**: The guide must document the GitHub login name of the bot or user account that posts review threads when Claude Code Action runs. This is required so operators can correctly configure `pr-review-loop.sh` to parse threads from the right account.

- **BR-5 — Model guidance must name the default**: The guide must identify Sonnet (specifically `claude-sonnet-4-6` or the recommended equivalent at the time) as the default model for the workflow, and explain the upgrade path to Opus for large-diff PRs.

- **BR-6 — The guide does not reproduce the workflow file**: The integration guide describes what to configure and why; the workflow file itself is the canonical implementation. The guide should reference the workflow file by its path (e.g., `.github/workflows/claude-code-action-review.yml`) rather than embedding a full copy.

- **BR-7 — `pr-review-platform.md` update is in scope**: Updating the platform reference table in `pr-review-platform.md` is part of this feature's deliverable and must be done in the same PR as the new guide.

- **BR-8 — CHANGELOG entry is not required**: This is a `spec/*` branch. CHANGELOG entries are only required for `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches.

---

## Acceptance Criteria

- [ ] A new file `docs/workflow/development-workflow/integrations/claude-code-action.md` exists and covers: adding the `ANTHROPIC_API_KEY` secret, referencing the shipped workflow file, configuring the trigger phrase, and noting the bot login used for thread attribution.
- [ ] The guide includes a model choice section that names Sonnet as the default, explains when to use Opus for large diffs, and gives approximate cost context.
- [ ] The guide explicitly explains why Claude Code Action has no per-hour vendor review cap (own-key, own CI).
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` is updated to include `claude-code-action` in the supported platforms table with a link to the new guide.
- [ ] The platform identifier used throughout (`claude-code-action`) matches the value used in `.ai-dev-workflow.yaml` examples and the script platform dispatch table.
- [ ] The guide does not embed a full copy of the workflow file; it references the workflow file by its path.
- [ ] All template placeholder content is removed from the spec and the guide documents are complete before the PR is opened.

---

## Out of Scope (MVP)

- Updating `.ai-dev-workflow.yaml` to activate `claude-code-action` in the live config (that is issue #708).
- Implementing the `run_claude_code_review()` function in `pr-review-loop.sh` (that is issue #705).
- Shipping the `.github/workflows/` workflow file (that is issue #706).
- Documenting cost optimization strategies beyond the basic model selection guidance (e.g., prompt caching configuration, diff scoping).
- Adding a troubleshooting section beyond the basic setup failure scenarios (can be added in a follow-up).
- Documenting GitHub Copilot code review as an alternative backstop platform (that is a separate optional epic sub-item).
- Updating the `REVIEW.md` canonical review contract with Claude Code Action specifics.
