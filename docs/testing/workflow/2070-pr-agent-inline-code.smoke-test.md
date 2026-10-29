# Smoke Test Runbook: PR-Agent Classifiable Inline Code

**Spec**: [#2070 spec](../../specs/developments/20261029131436_2070-pr-agent-inline-code/1_2070-pr-agent-inline-code_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261029131436_2070-pr-agent-inline-code/2_2070-pr-agent-inline-code_implementation-plan.md)
**Created in**: Plan stage; execute and record results during implementation.

## Prerequisites

- The implementation is checked out; Python 3, Bash, jq, Docker and the launcher's pinned image are available. Image mode also requires public Git object `e0d16ef7e4ea48e351a071f872b1caf2bd0515cc` locally; no fetch or fallback occurs.
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

Verify T2 enters through the installed reviewer renderer alias, appends actual producer state, creates a new comment and independently reads it. For fresh/edit-review/persistent consumers, inspect synthetic assertions of one create/readback and zero old edits. The host's candidate classifier with preserved blocker policy must report clean with verification-only false for the advisory-only expression and ordinary control. D15 must match the reviewed synthetic head; the wrong head and hidden-state-only controls must fail. Expected: no manufactured current-head identity or provenance.

### Step 3: Genuine ambiguity and independent blockers — AC3, AC5

In the same suite, exercise E7 at both boundaries: supply malformed raw HTML in source `issue_content` through the installed renderer alias, and separately feed the composed-comment negative to the consumer. Assert the whole source field remains byte-identical under D2, including an eligible span before later raw markup; the genuine boundary-crossing example must still reject through the original guard and classify `escalate`. The paired source positive, with HTML only inside supported code spans, must still pass Step 2. Verify security, verification-required evidence and hard-focus blockers independently retain their original non-clean classification beside E1. Expected: formatting never suppresses a blocker or repairs source or composed structural HTML.

### Step 4: Publication boundary failures and limits — AC4, AC6

Check T3's missing/wrong/stale identity, mismatched/invalid state, head drift and readback failures. Expected pre-create failures perform zero creates, and uncertain writes are not retried or edited. Below-limit positives must retain the expression; exact/over-limit expansion follows the existing fitter without treating a manual-verification diagnostic as a positive E1 result.

### Step 5: Hook compatibility and final evidence — AC6

Verify T4's incompatible signature and alias mismatch fail before patching/publication; compatible restoration succeeds. Record concrete planted test locations and both outcomes in the implementation PR. Check idempotence, teardown restoration, non-review delegation and diff-driven suite discovery. Record unit/image commands, image digest, reviewed commit and actual results; leave CI and review gates in force.

### Reversal verification — policy only at plan stage

Follow the plan's Reversal Policy only in a separately authorized rollback PR; this runbook does not execute a rollback. In synthetic verification of that PR, retain an already-formatted fabricated review and confirm the predecessor consumer still reads its code, identity and state. Generate a new fabricated review through the restored producer and disclose the returning closing-tag ambiguity behavior. No previously published comment may be rewritten, deleted or republished to simulate reversal; normal future reviews create independent records. Keep the existing guard/publication checks and workflow/configuration intact.

## Assertions Checklist

- [x] AC1: The mixed closing-tag expression is readable and clean through the actual publication/readback/consumer chain, without verification-only fallback.
- [x] AC2: Ordinary inline-code presentation and findings remain unchanged.
- [x] AC3: Ambiguous/cross-boundary HTML retains fail-closed rejection.
- [x] AC4: Content, severity, reviewed identity and state provenance retain their original meaning and failure handling.
- [x] AC5: Security and verification blockers each independently block.
- [x] AC6: Actual renderer/hooks, publication/readback, limits, compatibility and host-consumer gates are exercised with synthetic data.

## Execution Record — original single-delimiter checkpoint

Executed 2026-10-29 UTC on implementation checkpoint `86973b81` with synthetic
fixtures only. The final PR's reviewed head and CI record provide the subsequent
review/readiness evidence; this record describes the delivered behavior tests.

- Default suite: PASS, eight source test families; nine image-only families skipped on the host.
- `--image-smoke`: PASS, all 17 families, then 12 host classification controls and D15 correct-head/wrong-head/hidden-only checks. Affected and ordinary controls each exercise fresh, review-edit and persistent publication; security and hard focus independently report `needs_fixes`, verification reports `escalate` with verification-only true, and renderer-source/composed structural negatives report `escalate` with verification-only false.
- Image: `pragent/pr-agent@sha256:31b9aac6ab067bada9a0c1b001d30ebc500ea4487e00a93c18c59b9ef5fa66db`; read-only checkout, networking disabled, in-memory GitHub boundary.
- Identity failures before publication create zero records. Readback mismatch and uncertain-write cases create at most once, without retry. Below/exact limits preserve the expression; HTML expansion can omit the complete hidden state, while oversized protected content produces the existing verification diagnostic.
- Compatibility planted-violation proof: `test_pr_agent_inline_code.py`, `probe_compatibility`, lines 399–405 plants an incompatible signature or a distinct imported alias. In separate disposable image processes, `--probe-compatibility signature` exits 1 with `incompatible PR-Agent runtime hook`; `--probe-compatibility alias` exits 1 with `incompatible PR-Agent renderer alias`; `--probe-compatibility compatible` exits 0 with `PASS: compatible renderer installed`. Automated tests also assert no partial hook installation and restore all captured references.
- ShellCheck, workflow shell guard and shell snippet lint: PASS. Diff-driven suite selection includes the new wrapper for runtime and synthetic test changes. The consumer guard's AST matches the approved base unchanged.

The initial synthetic regression was run before implementation against the pinned
producer and failed with `inline span crosses HTML markup`; the same source now
passes the publication/readback/host-consumer chain. No live historical comment,
provider configuration or workflow was changed for this evidence.

## Double-delimiter extension execution record

Executed 2026-10-29 UTC at checkpoint `8f36efb8`, following Luis’s explicit
scope-extension approval. The original checkpoint above records earlier evidence;
its unchanged-guard claim applies only to that earlier revision.

- Default synthetic suite: PASS, ten source families; nine image families skipped on host.
- `--image-smoke`: PASS, all 19 families and 34 host-consumer records. Double-code candidate controls cover fresh/edit/persistent publication. The predecessor runs in a separate process from public Git source, passed intact over stdin, with network disabled and candidate checkout read-only. Its supported double-code fresh/edit/persistent readbacks and resolved history classify clean on the candidate consumer; its own old guard rejects the double-delimited fixture. Correct-head, wrong-head and hidden-only D15 controls pass.
- Predecessor security and hard focus independently report `needs_fixes`; verification reports `escalate` with verification-only true. Source/composed double HTML crossings, raw markup after eligible code, mismatched/unclosed/escaped/multiline runs and quoted verdicts escalate. Old-producer over-limit diagnostics remain non-clean. Missing reviewed identity performs zero creates.
- `test_double_backticks` originally failed before implementation; matching doubles now preserve embedded single backticks and GFM padding semantics. Triple runs, source fences and HTML context protections remain conservative. Two affected existing synthetic negative tests now use mismatched delimiters; no historical incident payload was changed.
- ShellCheck, workflow shell guard and snippet lint pass. Native review, external review and CI must bind to the final PR head; none is waived by these results.

- [x] AC7: Double-backtick producer and consumer support with equivalent visible text.
- [x] AC8: Unmodified predecessor publication/readback reaches the candidate consumer while independent blockers and ambiguity protections remain enforced.
