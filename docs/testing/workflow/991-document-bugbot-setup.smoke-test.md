# Smoke Test Runbook: Document Bugbot Setup and Framework Rollout Guidance

**Feature**: Document Bugbot setup and framework rollout guidance (#991)
**Spec**: [`../../specs/developments/20260617122749_document-bugbot-setup/1_document-bugbot-setup_specs.md`](../../specs/developments/20260617122749_document-bugbot-setup/1_document-bugbot-setup_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out (the PR targets
      `develop-cursor-bugbot-integration`).
- [ ] `markdownlint-cli2` is available via the repo's `node_modules/.bin`.
- [ ] A Markdown viewer (or the GitHub PR "Files changed" rendered view) is
      available to follow links.

This is a documentation-only feature: there is no application to run and no
database to seed. "Testing" means reviewing the rendered documentation and
verifying lint/links.

---

## Test Data

| Item | Value |
| --- | --- |
| New guide | `docs/workflow/development-workflow/integrations/bugbot.md` |
| Generic platform guide | `docs/workflow/development-workflow/integrations/pr-review-platform.md` |
| Integration index | `docs/workflow/development-workflow/README.md` |
| Review contract | `REVIEW.md` |

---

## Smoke Test Steps

### Step 0: Open the rendered docs

- Open the PR "Files changed" view (or the Markdown files in a viewer).

### Step 1: Guide exists and is discoverable

**Maps to**: Acceptance Criteria AC-1, AC-10

1. Confirm `docs/workflow/development-workflow/integrations/bugbot.md` exists in
   the integrations directory alongside the other review-tool guides.
2. Open `docs/workflow/development-workflow/integrations/pr-review-platform.md`
   and confirm its "See:" list links to `bugbot.md`.
3. Open `docs/workflow/development-workflow/README.md` and confirm the
   "Integration Guides" list includes `bugbot.md`.

**Expected result**: The guide is present and reachable from both index listings;
both links resolve.

### Step 2: Setup and PR-behavior coverage

**Maps to**: Acceptance Criterion AC-2

1. Read the guide's setup and PR-behavior sections.

**Expected result**: The guide documents GitHub/Cursor setup, required repository
access, the Bugbot check name(s), possible check conclusions, how to trigger a
manual review, automatic review settings, draft-PR behavior, and Autofix
considerations.

### Step 3: Manifest configuration location

**Maps to**: Acceptance Criterion AC-3

1. Read the configuration section of the guide.

**Expected result**: The guide explains where Bugbot is declared in
`.ai-dev-workflow.yaml` so a downstream team knows where to configure it.

### Step 4: Post-push positioning

**Maps to**: Acceptance Criterion AC-4

1. Read the review-model section.

**Expected result**: The guide explicitly states Bugbot is post-push validation
and does not replace the pre-PR review gate.

### Step 5: Neutral check and branch protection

**Maps to**: Acceptance Criterion AC-5

1. Read the neutral-check / branch-protection section.

**Expected result**: The guide describes the known neutral check behavior and its
implications for making (or not making) Bugbot a required status check.

### Step 6: Bugbot rules template and nested files

**Maps to**: Acceptance Criteria AC-6, AC-7

1. Read the Bugbot rules section.

**Expected result**: The guide includes a minimal, copy-ready `.cursor/BUGBOT.md`
template (fenced code block), explains nested per-directory Bugbot rule files, and
explains keeping Bugbot rules aligned with `REVIEW.md` by referencing it rather
than duplicating the full contract. The template does not restate the whole review
contract.

### Step 7: Rollout guidance for Cursor-primary teams

**Maps to**: Acceptance Criterion AC-8

1. Read the rollout guidance section.

**Expected result**: The guide includes rollout guidance tailored to client teams
that use Cursor as their primary agent surface, reinforcing Bugbot as
complementary post-push validation.

### Step 8: Reviewer-loop status

**Maps to**: Acceptance Criterion AC-9

1. Read the reviewer-loop status / known-limitations section.

**Expected result**: The guide states Bugbot is currently planned-but-unsupported
by `scripts/development-workflow/pr-review-loop.sh` and is reported as `skipped` by
that loop until an adapter exists, consistent with the generic platform guidance.

### Last Step: Validate & Lint

- Run `markdownlint-cli2` plus the heuristic lint and duplicate-header checks on
  the new/edited files and confirm they pass.
- Verify every assertion in the checklist below is met.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Bugbot guide exists in the integrations area and is reachable from the
      index/README listing.
- [ ] AC-2: Guide documents GitHub/Cursor setup, repo access, check name(s), check
      conclusions, manual trigger, automatic review settings, draft-PR behavior,
      and Autofix considerations.
- [ ] AC-3: Guide explains where Bugbot is declared in `.ai-dev-workflow.yaml`.
- [ ] AC-4: Guide states Bugbot is post-push validation and does not replace the
      pre-PR review gate.
- [ ] AC-5: Guide describes neutral-check behavior and branch-protection
      implications.
- [ ] AC-6: Guide includes a minimal, copy-ready `.cursor/BUGBOT.md` template and
      explains nested Bugbot rule files.
- [ ] AC-7: Guide explains aligning Bugbot rules with `REVIEW.md` by reference, not
      duplication.
- [ ] AC-8: Guide includes rollout guidance for Cursor-primary teams.
- [ ] AC-9: Guide states Bugbot is planned-but-unsupported by `pr-review-loop.sh`
      and reported as `skipped`.
- [ ] AC-10: Generic platform guide cross-references the new guide, and the
      integration index lists it.

---

## Seed Data Reference

No seed data is required (documentation-only feature).

| Entity | Scenario | How to load |
| --- | --- | --- |
| None | N/A | N/A |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `markdownlint-cli2` reports broken relative link | Wrong `../` depth from the file's location | Recount `../` segments from the file path; the lint step is authoritative |
| Guide implies the reviewer loop runs Bugbot | AC-9 language not aligned with `pr-review-platform.md` | Use the "planned but unsupported" / `skipped` wording from the generic platform guide |
| Guide not discoverable | Cross-reference omitted | Confirm both the `pr-review-platform.md` "See:" list and README "Integration Guides" list include `bugbot.md` |

---

## Known Limitations

- This runbook validates documentation content and discoverability only; it cannot
  exercise Bugbot's live GitHub/Cursor behavior, which depends on the adopter's
  own Cursor account and repository configuration.
