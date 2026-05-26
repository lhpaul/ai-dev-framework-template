# Register Claude Code Action and Reslot phase_after_clean — Spec

**Depends on**: 705-claude-code-action-script, 706-claude-code-action-ci, 707-claude-code-action-docs

---

## Overview

This chore surfaces `claude-code-action` as a supported and recommended PR review platform within the template's configuration and documentation. With the underlying script support, CI workflow, and integration guide provided by sibling items, this item updates the central workflow manifest (`.ai-dev-workflow.yaml`) and the project-level documentation files so that template consumers know `claude-code-action` is available and understand how to slot it into the `phase_after_clean` position in place of CodeRabbit. The goal is to remove the CodeRabbit rate-limit bottleneck from the hot-path review cycle by recommending a configuration that does not have a per-hour review cap.

---

## Use Cases

### Use Case 1: Template Consumer Configures claude-code-action as the Phase-After-Clean Reviewer

**Actor**: A developer adopting or maintaining a project built from this template, who wants to replace CodeRabbit in the `phase_after_clean` slot to avoid rate-limit stalls.

**Preconditions**: The developer has a project created from the template and has installed the Claude Code Action GitHub App or has the `ANTHROPIC_API_KEY` secret configured in their repository.

**Steps**:

1. Developer opens `.ai-dev-workflow.yaml` in their project.
2. Developer reads the inline comment listing supported platforms and sees `claude-code-action` in the list.
3. Developer reads the comment describing the `phase_after_clean` field and sees the guidance to swap `coderabbit` for `claude-code-action`.
4. Developer updates `review.platforms` to include `claude-code-action` and updates `review.phase_after_clean` to list `claude-code-action` instead of `coderabbit`.
5. Developer saves the file and the automated review loop uses `claude-code-action` as the after-clean reviewer on the next PR.

**Postconditions**: The project no longer experiences CodeRabbit rate-limit stalls; `claude-code-action` serves as the primary after-clean reviewer.

**Information shown**:

- Inline YAML comments in `.ai-dev-workflow.yaml` indicating `claude-code-action` is supported and is the recommended `phase_after_clean` value.

**Actions available**:

- Developer can choose to keep `coderabbit` alongside `claude-code-action` in `review.platforms` for occasional deeper audits.
- Developer can choose to remove `coderabbit` from `phase_after_clean` and rely exclusively on `claude-code-action` for the after-clean phase.

**Considerations**:

- If the developer's project does not have the `ANTHROPIC_API_KEY` secret or the Claude Code Action workflow, the platform will fail gracefully at runtime. The config change alone does not enable functionality — the CI workflow (sibling item #706) must also be present.
- The existing configuration with `coderabbit` in `phase_after_clean` continues to work without change; this update only adds guidance, it does not force migration.

---

### Use Case 2: Template Consumer Reads README / Documentation to Understand Review Platform Options

**Actor**: A developer or team lead evaluating the template's automated review capabilities.

**Preconditions**: The developer is reading the template's `README.md`, `AGENTS.md`, or related documentation.

**Steps**:

1. Developer reads the documentation section describing the PR review workflow.
2. Developer sees `claude-code-action` mentioned as the recommended `phase_after_clean` platform.
3. Developer understands that choosing `claude-code-action` removes the rate-limit constraint present with CodeRabbit and that it requires their own Anthropic API key.
4. Developer follows the link to the integration guide (provided by sibling item #707) for detailed setup instructions.

**Postconditions**: Developer has the information needed to decide whether to adopt `claude-code-action` as their primary automated reviewer.

**Information shown**:

- `claude-code-action` listed as the recommended `phase_after_clean` value in any documentation that references review platform configuration.

**Actions available**:

- Developer follows the integration guide for setup.
- Developer keeps the default CodeRabbit configuration if they prefer.

**Considerations**:

- Documentation must not duplicate full setup instructions; it should reference the integration guide (from sibling item #707) for those details.

---

## Business Rules

- `claude-code-action` must be added to the inline comment listing supported platforms in `.ai-dev-workflow.yaml` so the comment remains accurate after the platform is added.
- The `phase_after_clean` comment in `.ai-dev-workflow.yaml` must describe `claude-code-action` as the recommended value to remove the CodeRabbit rate-limit bottleneck.
- Any documentation files that describe the review platform configuration (README, AGENTS.md, or equivalent) must mention `claude-code-action` as the recommended `phase_after_clean` value, or reference the section of the documentation that does.
- A CHANGELOG entry under `[Unreleased]` must be added describing the configuration and documentation update.
- The default value of `review.phase_after_clean` in the template's own `.ai-dev-workflow.yaml` must remain `coderabbit` until the implementation item (#708 implementation stage) updates it; this spec item only updates comments and documentation, not the active configuration value.

---

## Acceptance Criteria

- [ ] Opening `.ai-dev-workflow.yaml` shows `claude-code-action` in the inline comment next to `review.platforms` that lists currently supported platforms.
- [ ] The comment block near `review.phase_after_clean` in `.ai-dev-workflow.yaml` explicitly states that `claude-code-action` is the recommended value in place of `coderabbit` for removing rate-limit stalls.
- [ ] Any documentation file (`README.md`, `AGENTS.md`, or a linked reference page) that describes PR review platform configuration mentions `claude-code-action` as the recommended `phase_after_clean` option.
- [ ] The CHANGELOG contains a new entry under `[Unreleased]` describing this configuration and documentation update.
- [ ] Existing `coderabbit` entries in `.ai-dev-workflow.yaml` are not removed by this change; only comments and documentation are updated.

---

## Out of Scope (MVP)

- Changing the active `review.phase_after_clean` value in the template's own `.ai-dev-workflow.yaml` from `coderabbit` to `claude-code-action` — that is the implementation stage's responsibility.
- Adding `claude-code-action` to `review.platforms` in the template's own `.ai-dev-workflow.yaml` — same scope boundary as above.
- Writing the integration guide for `claude-code-action` — that is sibling item #707.
- Implementing the `run_claude_code_review()` function in `pr-review-loop.sh` — that is sibling item #705.
- Shipping the Claude Code Action GitHub Actions workflow — that is sibling item #706.
- Updating the internal reviewers (`review.internal_reviewers`) list — no change needed for this item.
- Removing or deprecating CodeRabbit support from the template — CodeRabbit remains a supported platform.
