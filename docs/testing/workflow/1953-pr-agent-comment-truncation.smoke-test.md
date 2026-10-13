# Smoke Test Runbook: PR-Agent Comment Truncation

**Feature**: PR-Agent Comment Truncation (#1953)
**Spec**: [Approved spec](../../specs/developments/20261013200317_1953-pr-agent-comment-truncation/1_1953-pr-agent-comment-truncation_specs.md)
**Created in**: Plan Ready stage

## Prerequisites

- Use the implementation branch after the runtime helper and regression suite exist.
- Python 3, Bash and Docker are available. No API key or GitHub token is needed for this smoke test.
- Use the image snapshot recorded in the implementation plan; do not replace it with a floating tag.

## Test Data

The committed suite generates deterministic clean/blocking reviews, hidden finding-state history, resolved-history suffixes and boundary-sized comments. No production comments or consumer data are copied into the suite.

## Smoke Test Steps

### Step 1: Preserve Current Visible Reviews

**Maps to**: AC1–AC2, AC5.

Run the standard regression suite wrapper:

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash scripts/development-workflow/tests/test-pr-agent-runtime.sh
```

**Expected result**: Oversized comments retain their complete fitting visible review, the published body respects the limit, and the unchanged classifier returns clean for a clean review and needs-fixes for a blocking review. Current finding details remain intact when generated history is removed.

### Step 2: Verify Limit and Notice Boundaries

**Maps to**: AC1, AC3–AC5.

Inspect the suite's full/short/omitted-notice, unchanged-comment, Unicode, malformed-state and oversized-visible cases.

**Expected result**: Exact-limit and below-limit bodies remain unchanged. The notice never displaces a fitting visible summary or verdict. Retained state round-trips intact or is absent; no partial snapshot claims completeness. Unsupported oversized content produces a bounded diagnostic that escalates rather than approving a sliced review.

### Step 3: Verify the Real Runtime Publication Path

**Maps to**: AC5–AC6.

Run the suite's Docker compatibility mode against the plan's image snapshot after implementation supplies that mode:

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash scripts/development-workflow/tests/test-pr-agent-runtime.sh --image-smoke
```

It must invoke hook installation and mocked GitHub create/edit paths without starting a live review or calling GitHub.

**Expected result**: Both composer bindings defer the cap, final create and persistent edit publish bounded bodies after metadata insertion, and a deliberately incompatible hook fails before runner invocation. Logs show omission reasons/counts without review bodies or credentials.

### Step 4: Verify Consumer Delivery and Preserved Workflow

**Maps to**: AC6.

Compare the implementation workflow with the baseline from the plan's Verification Log. Run sync-manifest selection for `product_repo` and verify that the launcher accompanies the shared PR-Agent workflow. Run the existing suite selector against the runtime and wrapper paths.

**Expected result**: Events, repository-origin guard, permissions, secret names and model settings are preserved. Consumer sync includes the runtime dependency, and ordinary diff-driven CI selects the regression suite.

## Assertions Checklist

- [ ] AC1: Full, abbreviated and absent notice cases preserve fitting visible content.
- [ ] AC2: The existing classifier preserves both clean and blocking verdicts.
- [ ] AC3: Final create/edit bodies never exceed the publication limit.
- [ ] AC4: Below-limit and exact-limit comments are byte-for-byte unchanged.
- [ ] AC5: Omission is observable, and retained history never falsely claims completeness.
- [ ] AC6: Actual runtime hooks, incompatible-runtime failure, workflow preservation and shared sync dependency are verified.

## Results

Record commands, image digest, reviewed commit and PASS/FAIL per step during implementation. This plan-stage runbook does not claim execution results.
