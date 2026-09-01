# #1653 planted-violation proof record

Recorded at head `f49b3925`. Each proof names a concrete plant location,
shows the failing assertion/output, then the passing restore.

## P1 — file tier replaces branch checklist

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:378`
  (replace append with assignment)
- **Fail run:** `FAIL: 1653_s6_refactor_foo_lists - expected 'Code Review Checklist,Workflow Policy Review Checklist', got 'Workflow Policy Review Checklist'`
- **Pass run:** `PASS: 1653_s6_refactor_foo_lists` (`bash scripts/development-workflow/tests/test-local-ai-reviewer.sh`)

## P2 — substring branch match

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:323`
  (`spec/*` → `spec*`)
- **Fail run:** `FAIL: 1653_s2_specification - expected 'default', got 'spec'`
- **Pass run:** `PASS: 1653_s2_specification`

## P3 — file tier consulted for `default`

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:372-377`
  (remove `default` short-circuit)
- **Fail run:** `FAIL: 1653_s6_main_lists - expected '', got 'Workflow Policy Review Checklist'`
- **Pass run:** `PASS: 1653_s6_main_lists` with empty checklist for unknown branch

## P4 — remove additive Core Rules sentence

- **Plant location:** `scripts/development-workflow/local-codex-review-command.sh:25`
- **Fail run:** `FAIL: 1653_s10_core_rules - expected 'yes', got 'no'`
- **Pass run:** `PASS: 1653_s10_core_rules`

## P5 — file tier requires all paths

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:334-349`
  (invert to require all paths match)
- **Fail run:** `FAIL: 1653_s4_mixed_yes - expected 'yes', got 'no'`
- **Pass run:** `PASS: 1653_s4_mixed_yes`

## P6 — empty changed-file list matches policy

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:336`
  (treat empty stdin as success)
- **Fail run:** `FAIL: 1653_s5_empty_no - expected 'no', got 'yes'`
- **Pass run:** `PASS: 1653_s5_empty_no`

## P7 — newline-separated REVIEW_CHECKLISTS evidence

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:588-590`
  (emit multiline value)
- **Fail run:** `FAIL: 1653_s13_no_fabricated_key - expected '0', got '1'`
- **Pass run:** `PASS: 1653_s13_no_fabricated_key` (`test-pr-review-loop.sh --area 1653`)

## P8 — renamed REVIEW.md heading

- **Plant location:** `REVIEW.md:202` (rename Code Review Checklist)
- **Fail run:** `FAIL: 1653_s9_heading_Code_Review_Checklist - expected 'yes', got 'no'`
- **Pass run:** `PASS: 1653_s9_heading_Code_Review_Checklist`

## P9 — skip JSON decode

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:377`
  (pipe raw JSON into predicate)
- **Fail run:** `FAIL: 1653_s5a_lists - expected 'Code Review Checklist,Workflow Policy Review Checklist', got 'Code Review Checklist'`
- **Pass run:** `PASS: 1653_s5a_lists`

## P10 — pipeline decode under pipefail

- **Plant location:** `scripts/development-workflow/local-ai-reviewer.sh:376-377`
  (`jq ... | predicate` pipeline)
- **Fail run:** `FAIL: 1653_s5b_policy_added - expected 'branch+files', got 'branch'`
- **Pass run:** `PASS: 1653_s5b_policy_added`
