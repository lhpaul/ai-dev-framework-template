# Smoke Test Runbook: PR-Agent Classifiable Inline Code

**Spec**: [#2070 spec](../../specs/developments/20261029131436_2070-pr-agent-inline-code/1_2070-pr-agent-inline-code_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261029131436_2070-pr-agent-inline-code/2_2070-pr-agent-inline-code_implementation-plan.md)
**Created in**: Plan stage; execute and record results during implementation.

## Prerequisites

- The implementation is checked out; Python 3, Bash, jq, Docker and the launcher's pinned image are available.
- Use a read-only repository mount for the image and disable its networking. GitHub create/readback is mocked; no credentials or model API is used.
- Data is fabricated in `test_pr_agent_inline_code.py`. Do not import historical incident bodies, inspect private config, edit published bot comments or touch sibling work items.
- No application server, database, login or design asset is required.

## Test Data

Use the plan's E1–E8 classes and T2 provider context. These are coverage classes, not a binding fixture count. A wrong-head control uses a distinct fabricated SHA. Independent blockers are added one at a time.

## Smoke Test Steps

### Step 1: Source-formatting controls — AC1, AC2

Run the synthetic unit suite:

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash scripts/development-workflow/tests/test-pr-agent-inline-code.sh
```

Verify E1 decodes to the same original expression, ordinary code is byte-identical, non-target text is retained, multiple spans stay ordered, and the input/state objects are untouched. Check malformed delimiters, fences and non-GFM controls against E5/E6/E8 expectations. Expected: suite passes without network or historical payloads.

### Step 2: Pinned renderer to readback to host consumer — AC1, AC2, AC4, AC6

Run the composed image/host suite:

<!-- workflow-shell-contract: bash-zsh -->
```bash
bash scripts/development-workflow/tests/test-pr-agent-inline-code.sh --image-smoke
```

Verify T2 enters through the installed reviewer renderer alias, appends actual producer state, creates a new comment and independently reads it. For fresh/edit-review/persistent consumers, inspect synthetic assertions of one create/readback and zero old edits. The host's unchanged classifier must report clean with verification-only false for the advisory-only expression and ordinary control. D15 must match the reviewed synthetic head; the wrong head and hidden-state-only controls must fail. Expected: no manufactured current-head identity or provenance.

### Step 3: Genuine ambiguity and independent blockers — AC3, AC5

In the same suite, exercise E7 at both boundaries: supply malformed raw HTML in source `issue_content` through the installed renderer alias, and separately feed the composed-comment negative to the consumer. Assert the whole source field remains byte-identical under D2, including an eligible span before later raw markup; the genuine boundary-crossing example must still reject through the original guard and classify `escalate`. The paired source positive, with HTML only inside supported code spans, must still pass Step 2. Verify security, verification-required evidence and hard-focus blockers independently retain their original non-clean classification beside E1. Expected: formatting never suppresses a blocker or repairs source or composed structural HTML.

### Step 4: Publication boundary failures and limits — AC4, AC6

Check T3's missing/wrong/stale identity, mismatched/invalid state, head drift and readback failures. Expected pre-create failures perform zero creates, and uncertain writes are not retried or edited. Below-limit positives must retain the expression; exact/over-limit expansion follows the existing fitter without treating a manual-verification diagnostic as a positive E1 result.

### Step 5: Hook compatibility and final evidence — AC6

Verify T4's incompatible signature and alias mismatch fail before patching/publication; compatible restoration succeeds. Record concrete planted test locations and both outcomes in the implementation PR. Check idempotence, teardown restoration, non-review delegation and diff-driven suite discovery. Record unit/image commands, image digest, reviewed commit and actual results; leave CI and review gates in force.

### Reversal verification — policy only at plan stage

Follow the plan's Reversal Policy only in a separately authorized rollback PR; this runbook does not execute a rollback. In synthetic verification of that PR, retain an already-formatted fabricated review and confirm the predecessor consumer still reads its code, identity and state. Generate a new fabricated review through the restored producer and disclose the returning closing-tag ambiguity behavior. No previously published comment may be rewritten, deleted or republished to simulate reversal; normal future reviews create independent records. Keep the existing guard/publication checks and workflow/configuration intact.

## Assertions Checklist

- [ ] AC1: The mixed closing-tag expression is readable and clean through the actual publication/readback/consumer chain, without verification-only fallback.
- [ ] AC2: Ordinary inline-code presentation and findings remain unchanged.
- [ ] AC3: Ambiguous/cross-boundary HTML retains fail-closed rejection.
- [ ] AC4: Content, severity, reviewed identity and state provenance retain their original meaning and failure handling.
- [ ] AC5: Security and verification blockers each independently block.
- [ ] AC6: Actual renderer/hooks, publication/readback, limits, compatibility and unchanged host consumers are exercised with synthetic data.

## Execution Record

Not executed at plan stage: the proposed synthetic suite does not exist yet. Implementation must fill in command results, commit, digest and planted-violation locations after delivering the suite. The plan's feasibility experiment is documented separately and does not check off this runbook.
