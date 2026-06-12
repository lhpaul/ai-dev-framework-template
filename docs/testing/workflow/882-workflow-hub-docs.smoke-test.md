# Smoke Test Runbook: Workflow Hub Setup And Operations Docs

**Feature**: Workflow hub setup and operations docs
**Spec**: [1_882-workflow-hub-docs_specs.md](../../specs/developments/20260611204735_882-workflow-hub-docs/1_882-workflow-hub-docs_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #882.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.
- [ ] No live product repositories, GitHub Apps, private keys, tokens, or
      secret-manager access are required.

## Test Data

| Item | Value |
| --- | --- |
| Setup guide | `docs/workflow/development-workflow/workflow-hub-setup.md` |
| Injection guide | `docs/workflow/development-workflow/product-repo-injection.md` |
| Cross-repo PR guide | `docs/workflow/development-workflow/cross-repo-pr-flow.md` |
| Expected smoke test | `scripts/development-workflow/tests/test-workflow-hub-docs.sh` |
| Placeholder hub | `faind-workflow-hub` |
| Placeholder products | `faind-mobile-app`, `faind-admin-portal` |

## Smoke Test Steps

### Step 1: Verify Setup Guide

**Maps to**: AC1, AC2, AC7, AC8

1. Open the setup guide.
2. Confirm it explains versioned `.ai-dev-workflow.yaml`.
3. Confirm it explains local-only `.ai-dev-workflow.local.yaml`.
4. Confirm each command states that it runs from the hub checkout.
5. Confirm it links to repository modes and GitHub App authentication docs.

**Expected result**: A maintainer can configure and validate a hub without
guessing where commands run or where secrets belong.

### Step 2: Verify Product-Repo Injection Guide

**Maps to**: AC2, AC3, AC5, AC7

1. Open the injection guide.
2. Confirm it explains `product_repo` mode.
3. Confirm it describes role-aware sync-template selection:
   `shared` plus `product_repo_injection`, skipping `hub_only`.
4. Confirm it states product repos must not receive hub-owned tracker, spec,
   plan, protocol, or orchestration artifacts.

**Expected result**: Product maintainers can preview and apply the injection
surface without copying hub-owned workflow state.

### Step 3: Verify Cross-Repo PR Flow

**Maps to**: AC4, AC5, AC7

1. Open the cross-repo PR flow guide.
2. Confirm it shows hub-owned planning state and product-owned implementation
   state separately.
3. Confirm it includes commands for product status, sync, PR dry-run, reviewer
   loop, CI loop, readiness labels, merge, and cleanup.
4. Confirm command run locations are explicit.

**Expected result**: Operators can route implementation PR work to the selected
product repository while tracker/spec/plan state remains hub-owned.

### Step 4: Verify Troubleshooting And Safety

**Maps to**: AC6, AC8, AC9

1. Run the focused docs smoke test.
2. Confirm troubleshooting covers missing checkout, dirty repo, missing app
   credentials, failed CI, and reviewer-loop failures.
3. Confirm the docs avoid unsafe recovery instructions and secret material.
4. Confirm examples use only placeholder Faind-like repositories and fake IDs.

**Expected result**: Docs provide safe recovery guidance without private details
or destructive commands.

### Step 5: Run Automated Validation

**Maps to**: AC1 through AC10

Run:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-docs.sh
npx markdownlint-cli2 "docs/workflow/development-workflow/*.md" "docs/workflow/development-workflow/integrations/*.md" "docs/specs/developments/20260611204735_882-workflow-hub-docs/*.md" "docs/testing/workflow/882-workflow-hub-docs.smoke-test.md" "CHANGELOG.md"
python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/882-workflow-hub-docs.smoke-test.md CHANGELOG.md
bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
git diff --check
```

**Expected result**: All documentation validation passes with no live
credentials or private product repositories.

## Assertions Checklist

- [ ] AC1: Setup path includes concrete commands and run locations.
- [ ] AC2: Versioned and local-only config files are explained.
- [ ] AC3: Product-repo injection explains role-aware sync-template selection.
- [ ] AC4: Cross-repo PR flow covers reviewer loop, CI, readiness, merge, and
      cleanup.
- [ ] AC5: Hub-owned and product-owned artifacts are clearly separated.
- [ ] AC6: Required troubleshooting cases are present.
- [ ] AC7: Docs link to protocols and integration guides.
- [ ] AC8: Examples use non-secret Faind-like placeholder repositories.
- [ ] AC9: Unsafe recovery instructions and secret material are absent.
- [ ] AC10: New docs are discoverable from existing workflow docs.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Smoke test reports missing command text | A guide omitted a required setup or PR-flow command | Add the command with its run location. |
| Smoke test reports unsafe command text | A troubleshooting section suggested destructive recovery | Replace with a safe diagnostic or escalation path. |
| Smoke test reports private detail text | Example data is too specific or resembles a real secret | Replace with `example/*`, fake IDs, or placeholder names. |
| Markdown lint fails on long commands | Command lines exceed project markdown style | Wrap commands across lines with shell continuations. |
