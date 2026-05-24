# Claude Code Action Integration Guide — Smoke Test Runbook

**Feature**: Claude Code Action Integration Guide (#707)
**Spec**: [docs/specs/developments/20260523170134_707-claude-code-action-integration-guide/1_707-claude-code-action-integration-guide_specs.md](../../specs/developments/20260523170134_707-claude-code-action-integration-guide/1_707-claude-code-action-integration-guide_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR is merged to `develop-claude-review-platform`
- [ ] You have a local checkout of `develop-claude-review-platform` pulled to
  the latest commit

No application server, database, or seed data is needed — this feature is
documentation-only.

---

## Test Data

| Item                     | Value                                                                         |
| ------------------------ | ----------------------------------------------------------------------------- |
| New guide path           | `docs/workflow/development-workflow/integrations/claude-code-action.md`       |
| Updated platform table   | `docs/workflow/development-workflow/integrations/pr-review-platform.md`       |
| Expected platform ID     | `claude-code-action`                                                          |
| Expected secret name     | `ANTHROPIC_API_KEY`                                                           |
| Expected workflow path   | `.github/workflows/claude-code-action-review.yml`                             |
| Expected default model   | `claude-sonnet-4-6` (or current Sonnet equivalent)                            |

---

## Smoke Test Steps

### Step 1: Confirm the new integration guide exists

- Open `docs/workflow/development-workflow/integrations/claude-code-action.md`
  in your editor or `cat` it.
- Verify: the file exists and is non-empty.

### Step 2: Verify BR-1 — platform identifier consistency

**Maps to**: Acceptance Criterion 5 / BR-1

1. In `claude-code-action.md`, search for the platform identifier used in the
   YAML example for `.ai-dev-workflow.yaml`.
2. Confirm the identifier is exactly `claude-code-action` (no spaces, no
   underscores, no `claude_code_action` variant).

**Expected result**: Every occurrence in the guide and example YAML uses
`claude-code-action`.

### Step 3: Verify BR-2 — no-per-hour-cap explanation is present

**Maps to**: Acceptance Criterion 3 / BR-2

1. Read the guide's explanation of why Claude Code Action has no per-hour vendor
   review cap.
2. Confirm the explanation mentions that the workflow runs in the operator's own
   GitHub Actions CI using the operator's own Anthropic API key.

**Expected result**: The guide explicitly explains own-key, own-CI as the reason
there is no per-hour vendor cap.

### Step 4: Verify BR-3 — secret name is documented correctly

**Maps to**: Acceptance Criterion 1 / BR-3

1. Locate the setup section of the guide.
2. Confirm `ANTHROPIC_API_KEY` is named as the required GitHub Actions secret.
3. Confirm no alternative secret name is suggested.

**Expected result**: The guide specifies `ANTHROPIC_API_KEY` exactly.

### Step 5: Verify BR-4 — bot login is documented

**Maps to**: Acceptance Criterion 1 / BR-4

1. Locate the section of the guide that covers review thread attribution.
2. Confirm the GitHub bot login used by Claude Code Action is named (expected:
   `claude[bot]` or the equivalent App login).
3. Confirm the guide explains why operators need this login (to configure
   `pr-review-loop.sh` to identify threads from that account).

**Expected result**: Bot login is documented with a clear explanation of its
purpose for `pr-review-loop.sh` configuration.

### Step 6: Verify BR-5 — model guidance names the default

**Maps to**: Acceptance Criterion 2 / BR-5

1. Locate the model selection section.
2. Confirm `claude-sonnet-4-6` (or the current Sonnet equivalent) is identified
   as the default model.
3. Confirm the guide describes when to use Opus for large-diff PRs.
4. Confirm the guide notes that operators should verify current model
   availability and pricing at `console.anthropic.com`.

**Expected result**: Default model named, upgrade path to Opus described, caveat
about pricing verification present.

### Step 7: Verify BR-6 — guide does not embed the workflow file

**Maps to**: Acceptance Criterion 6 / BR-6

1. Search `claude-code-action.md` for any fenced code block longer than ~20
   lines that reproduces the full GHA workflow YAML.
2. Confirm the guide references `.github/workflows/claude-code-action-review.yml`
   by path rather than embedding a full copy of the workflow.

**Expected result**: No full workflow YAML copy embedded; only the file path is
referenced.

### Step 8: Verify BR-7 — pr-review-platform.md is updated

**Maps to**: Acceptance Criterion 4 / BR-7

1. Open `docs/workflow/development-workflow/integrations/pr-review-platform.md`.
2. Confirm `claude-code-action` appears in the "See also" or platform list links
   at the top of the document.
3. Confirm the relative link `(claude-code-action.md)` points to the new guide
   in the same directory.

**Expected result**: Platform reference table includes `claude-code-action` with
a working relative link to the new guide.

### Step 9: Verify relative links resolve

**Maps to**: Acceptance Criterion — no broken links

Run markdownlint on both files:

```bash
REPO_ROOT=$(git rev-parse --git-common-dir)/..
"$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
  "docs/workflow/development-workflow/integrations/claude-code-action.md" \
  "docs/workflow/development-workflow/integrations/pr-review-platform.md"
```

**Expected result**: Zero violations. No broken relative links, no trailing
whitespace, files end with a newline.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] `docs/workflow/development-workflow/integrations/claude-code-action.md`
  exists and covers: `ANTHROPIC_API_KEY` secret, workflow file reference,
  trigger phrase, bot login for thread attribution
- [ ] Guide includes a model choice section that names Sonnet as default and
  explains when to use Opus
- [ ] Guide explicitly explains why Claude Code Action has no per-hour vendor
  review cap (own-key, own CI)
- [ ] `pr-review-platform.md` includes `claude-code-action` in the supported
  platforms list with a link to the new guide
- [ ] Platform identifier `claude-code-action` is consistent across the guide,
  the platform table, and any YAML examples
- [ ] Guide does not embed a full copy of the workflow file; references it by
  path only
- [ ] Both files pass `markdownlint-cli2` with zero violations

---

## Seed Data Reference

None — this feature is documentation-only.
