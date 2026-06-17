# Integration: Cursor Bugbot (Automated PR Review)

This document describes how to use
[Cursor Bugbot](https://docs.cursor.com/bugbot)
as one automated PR reviewer tool in the workflow.

Cursor Bugbot is **optional**. The workflow functions without it.
See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the
multi-platform loop and aggregation rules.

---

## What Bugbot Adds

- Automated code review on every pull request, surfacing bugs, regressions, and
  style issues caught by Cursor's AI engine
- Per-repository review rules via `.cursor/BUGBOT.md` that let you align Bugbot's
  focus areas with your project's review contract
- Autofix suggestions that Cursor can apply directly to the PR branch (optional;
  see [Autofix considerations](#autofix-considerations) before enabling)
- Complements other review platforms — can be layered alongside CodeRabbit,
  PR-Agent, or Haystack as an additional signal, or used as a standalone reviewer
  on Cursor-primary teams

---

## Review Model

Cursor Bugbot is **post-push validation**. It does not replace the pre-PR review
gate defined in [`REVIEW.md`](../../../../REVIEW.md). The staged workflow's review
sequence is:

1. **Pre-PR review gate** (internal, before `gh pr ready`): run the code reviewer
   agent against `REVIEW.md` acceptance criteria. This is mandatory and cannot be
   replaced by any automated tool.
2. **Post-push automated review** (Step 7, after pushing): Bugbot — and other
   configured platforms — scan the PR and surface findings. Bugbot is one
   signal in this phase.

Enabling Bugbot does not relax or substitute any step of the pre-PR review gate.

---

## Prerequisites

- **Cursor account with Bugbot access**: Bugbot is a Cursor-native feature.
  Ensure Bugbot is enabled for your organization or repository in the Cursor
  dashboard. See the
  [Cursor Bugbot documentation](https://docs.cursor.com/bugbot) for current
  enablement details — Cursor maintains the authoritative product documentation
  for account-level settings and feature availability.
- **GitHub App installed**: Bugbot requires read access to pull-request contents
  and write access to post check runs and review comments. Install the Cursor
  GitHub App on the repository via Cursor's GitHub integration settings. The app
  needs at minimum:
  - `pull_requests: read` and `checks: write` (to post check-run conclusions)
  - `contents: read` (to analyze the diff)
- **GitHub.com repositories**: Bugbot operates on GitHub.com. GitHub Enterprise
  Server (GHES) support is subject to Cursor's product roadmap; consult the
  Cursor documentation for current GHES availability.
- **No additional Actions workflow file required**: Bugbot runs server-side via
  the GitHub App and does not require a `.github/workflows/` entry in your
  repository.

---

## Setup

### 1. Install the Cursor GitHub App

In the Cursor dashboard, navigate to **Settings → GitHub** (or the Bugbot
configuration page) and connect your GitHub organization or repository. Grant
the app the repository permissions described in [Prerequisites](#prerequisites).

### 2. Declare `bugbot` in `.ai-dev-workflow.yaml`

Add `bugbot` to the appropriate review phase in `.ai-dev-workflow.yaml` so the
reviewer loop and orchestration agents are aware of it:

```yaml
review:
  on_draft:
    github:
      - bugbot
```

To run Bugbot only after other draft-phase reviewers have cleared, place it
after them in the list or in the ready phase:

```yaml
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - bugbot
```

> **Note**: Declaring `bugbot` in `.ai-dev-workflow.yaml` records the intent but
> does not cause `pr-review-loop.sh` to actively run a Bugbot review cycle — see
> [Reviewer-loop status](#reviewer-loop-status) below.

---

## PR Behavior

### Check name and conclusions

Bugbot posts a GitHub check run on the pull request. The check typically appears
under a name such as `Bugbot` or `cursor/bugbot` in the PR Checks tab. Consult
the [Cursor Bugbot documentation](https://docs.cursor.com/bugbot) for the current
canonical check name, as Cursor may update this as the product evolves.

Bugbot check conclusions include:

| Conclusion  | Meaning                                                      |
| ----------- | ------------------------------------------------------------ |
| `success`   | No blocking issues found                                     |
| `failure`   | Blocking issues found; review the inline annotations         |
| `neutral`   | Review ran but produced no definitive pass/fail verdict      |

The **neutral** conclusion is a known Bugbot behavior. See
[Branch protection implications](#branch-protection-implications) for how to
handle it.

### Manual trigger

To request a fresh Bugbot review after pushing fixes, post a comment on the PR
containing:

```
@bugbot review
```

Bugbot will re-analyze the current HEAD and post an updated check run. The exact
trigger phrase is vendor-maintained; consult the
[Cursor Bugbot documentation](https://docs.cursor.com/bugbot) for the current
syntax.

### Automatic review settings

When the Cursor GitHub App is installed and Bugbot is enabled, it reviews pull
requests automatically on every push. You can configure whether Bugbot runs on
draft PRs through the Cursor dashboard settings. By default, Bugbot may or may
not auto-review draft PRs depending on your Cursor plan and settings — consult
Cursor's product documentation for the current behavior.

### Draft PR behavior

Whether Bugbot reviews draft PRs is governed by the Cursor App settings for your
repository. If you rely on Bugbot's check during the internal review gate (Step
7a, before `gh pr ready`), verify in the Cursor dashboard that draft-PR review
is enabled. If Bugbot skips draft PRs, its check run will not appear until the
PR is converted to non-draft.

---

## Branch Protection Implications

### Neutral check behavior

Bugbot occasionally reports a `neutral` check conclusion rather than `success` or
`failure`. In GitHub branch protection, a `neutral` check is treated as a
**passing** check if the check is marked as required — it does not block a merge.
However, a `neutral` conclusion means Bugbot did not complete a normal analysis
pass, so it should not be treated as an equivalent of `success`.

**Recommendation before making Bugbot a required check:**

- Observe Bugbot's check behavior on your repository for several PRs before
  requiring it in branch protection.
- If Bugbot posts `neutral` checks regularly, requiring it in branch protection
  will not block PRs even when Bugbot has not actually reviewed them, weakening
  the gate.
- A safer approach is to treat Bugbot as advisory (not required in branch
  protection) and rely on the `pr-review-loop.sh` orchestration layer to surface
  Bugbot findings to the developer before the PR reaches human review.

If you do make Bugbot a required check, also verify what happens when Bugbot is
unavailable (GitHub App outage, connectivity issue): a stuck or missing check run
can block all merges if the check is required and no timeout policy is in place.

---

## Autofix Considerations

Bugbot can automatically apply suggested fixes to your PR branch. Before enabling
Autofix:

- **Review Autofix commits carefully**: automated code modifications carry the
  risk of introducing unintended side effects. Every Autofix commit should be
  reviewed as if it were a developer commit.
- **CI impact**: Autofix pushes a new commit to the PR branch, which re-triggers
  CI. Confirm that your CI pipeline handles rapid successive pushes without
  spurious failures.
- **Scope creep**: Autofix may apply changes outside the PR's intended scope if
  Bugbot's analysis spans the full file rather than just the diff. Review the
  diff of any Autofix commit before merging.

Autofix is optional and off by default in most Cursor configurations. Consult the
[Cursor Bugbot documentation](https://docs.cursor.com/bugbot) for current Autofix
settings and how to enable or disable it per repository.

---

## Reviewer-Loop Status

Bugbot is a **first-class supported platform** in
`scripts/development-workflow/pr-review-loop.sh`. Declare it under
`review.on_draft.github` or `review.on_ready.github` in `.ai-dev-workflow.yaml`
and the loop will automatically trigger Bugbot, poll the "Cursor Bugbot" check
run on the PR head, classify the verdict, and surface blocking `cursor[bot]`
findings with severity and location context in the loop summary.

Supported outcome values emitted by the loop:

```
RESULT=clean          # Bugbot check passed with no blocking findings
RESULT=needs_fixes    # Bugbot reported blocking findings
RESULT=timeout        # Check run did not complete within the poll window
RESULT=unavailable    # Check run was not found or could not be fetched
```

Timeout and unavailable states are surfaced explicitly and are never treated as a
clean pass. Bugbot's review threads are included in the standard platform thread
auditing pass.

See [`integrations/pr-review-platform.md`](pr-review-platform.md) for the full
multi-platform loop contract and aggregation rules.

---

## Bugbot Rules

### Repository-level rules file

Bugbot reads a repository-level rules file at `.cursor/BUGBOT.md`. This file
controls what Bugbot pays attention to during a review: focus areas, patterns to
flag, and any project-specific heuristics you want Bugbot to apply.

The file lives in the `.cursor/` directory alongside other Cursor configuration.
It is checked into source control so all contributors and Bugbot itself see the
same rules.

### Nested per-directory rules

Bugbot also supports nested `BUGBOT.md` files in subdirectories. A
`src/payments/BUGBOT.md` file, for example, can add payment-domain-specific review
rules that apply only when Bugbot reviews files under `src/payments/`. Nested
rules are additive: they extend the repository-level rules for their directory
scope.

### Minimal `.cursor/BUGBOT.md` template

Copy this template into your repository as `.cursor/BUGBOT.md` and adapt it to
your project's needs. Keep it minimal — reference your review contract rather than
duplicating it:

```markdown
# Bugbot Review Rules

Apply the review standards in our review contract: see `REVIEW.md`.
Do not duplicate the full contract here — reference it.

## Focus Areas

- <project-specific concern 1 — e.g., "Flag unguarded database mutations">
- <project-specific concern 2 — e.g., "Require explicit error handling on all I/O operations">
- <project-specific concern 3 — e.g., "Ensure no secrets or PII in log output">
```

Keep the template short. Bugbot performs general code review automatically; the
rules file is for project-specific additions, not a restatement of general
principles.

### Aligning Bugbot rules with the review contract

The review contract (`REVIEW.md`) is the authoritative definition of what
constitutes a passing review in this workflow. Bugbot rules should **reference**
`REVIEW.md` rather than duplicating its acceptance criteria in `.cursor/BUGBOT.md`.
Duplicating creates a maintenance burden and risks the rules drifting out of sync.

**Pattern to follow:**

```markdown
# Bugbot Review Rules

Apply the review standards defined in `REVIEW.md`.

## Additional focus for <domain>

- <one or two project-specific heuristics>
```

**Pattern to avoid:**

```markdown
# Bugbot Review Rules

- No trailing whitespace
- All functions must have docstrings
- Tests required for all new code
- ... (restating REVIEW.md verbatim)
```

---

## Rollout Guidance for Cursor-Primary Teams

This section is for teams that use Cursor as their primary agent surface and want
to introduce Bugbot as part of the staged AI development workflow.

### Where Bugbot fits in the staged workflow

The staged workflow has a distinct pre-PR review gate that runs before a PR is
opened to human review. Bugbot is **post-push validation** that runs after the
branch is pushed and a PR is open. The sequence is:

1. Developer (or agent) writes code and commits locally.
2. Agent runs the **internal code review gate** (Step 7a) against `REVIEW.md`
   before `gh pr ready`. This is the pre-PR gate — it is mandatory.
3. PR is pushed and opened as a draft.
4. Bugbot (and other configured platforms) review the open PR — this is
   post-push validation.
5. Agent addresses Bugbot findings as part of the Step 7 loop.
6. PR is converted to non-draft and proceeds to human review.

Bugbot does not substitute for Step 7a. A PR that passes Bugbot but has not gone
through the internal review gate against `REVIEW.md` has not satisfied the
pre-PR gate.

### Adoption path

1. **Install the Cursor GitHub App** on the target repository (see [Setup](#setup)).
2. **Add `.cursor/BUGBOT.md`** using the [minimal template](#minimal-cursorbugbotmd-template).
   Reference `REVIEW.md` and add one or two project-specific focus areas.
3. **Declare `bugbot` in `.ai-dev-workflow.yaml`** so orchestration agents know
   it is in use. Until the reviewer-loop adapter lands, this is informational —
   Bugbot findings appear in the GitHub UI but are not reflected in the
   `pr-review-loop.sh` aggregate result.
4. **Observe neutral-check behavior** on a few PRs before deciding whether to add
   Bugbot as a required branch-protection check. See
   [Branch protection implications](#branch-protection-implications).
5. **Decide on Autofix** after the team has reviewed several Autofix commits and
   is comfortable with the quality. Start with Autofix disabled.
6. **Add Bugbot to branch protection (optional)** only after confirming the
   neutral-check rate is low enough that it will not silently skip reviews on
   active PRs.

### Bugbot and the pre-PR review gate

The most important guardrail is this: **Bugbot is complementary, not a
substitute.** Teams should configure their agents to always run the internal
review gate (Step 7a with a code reviewer agent) before relying on Bugbot
findings. Skipping the internal gate because Bugbot is present is a workflow
anti-pattern that weakens the quality signal reaching human reviewers.

### Neutral-check behavior and branch protection

If your team decides to make Bugbot a required check in GitHub branch protection,
monitor for the `neutral` conclusion over the first two weeks. If `neutral` checks
appear on more than 10–20% of PRs, consider leaving Bugbot as advisory rather
than required to avoid a false sense of security from a branch-protection check
that silently passes without running.

---

## Known Limitations

- **No reviewer-loop adapter**: `pr-review-loop.sh` does not yet poll for or
  surface Bugbot findings programmatically. Bugbot is reported as
  `skipped` (`REASON=unsupported-platform`) by the loop until an adapter exists.
- **Neutral check conclusions**: Bugbot sometimes reports `neutral` rather than
  `success` or `failure`. This is treated as passing by GitHub branch protection,
  which can give a false signal if the check is required.
- **Vendor-maintained details**: check names, trigger phrases, Autofix settings,
  and draft-PR behavior are controlled by Cursor and subject to change. The
  [Cursor Bugbot documentation](https://docs.cursor.com/bugbot) is the
  authoritative source for current product behavior.
- **GHES availability**: GitHub Enterprise Server support depends on Cursor's
  product roadmap; verify with Cursor before deploying to GHES.
