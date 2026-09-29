# Smoke Test Runbook: Matrix Coherence Preflight

**Feature**: Matrix coherence preflight for spec reviewer loops
**Work item brief**: GitHub issue #1759 (Refactor — brief replaces spec)
**Created in**: Plan Ready stage
**Updated in**: —

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR for #1759 is merged into `develop` (or checked out locally)
- [ ] No application, database, or service is required — this is a documentation-contract smoke test

## Test Data

| Item | Value |
| --- | --- |
| Matrix-bearing document | `docs/specs/developments/20260915075927_1757-resolved-codex-findings/1_1757-resolved-codex-findings_specs.md` (its `## Complex Workflow Decision-Gate Matrix` section) |
| Simple non-matrix document | any spec under `docs/specs/developments/` with no decision matrix, state table, lifecycle, or precedence rules |

---

## Smoke Test Steps

### Step 1: Creator-stage gate is present (spec side)

**Maps to**: brief scope — "Document where the pass belongs in the spec/reviewer-loop workflow"

1. Open `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
2. Locate the pre-PR "Before the PR is opened, verify" list
3. Confirm a "Matrix coherence preflight" bullet follows the "Complex workflow decision-gate matrix" bullet
4. Confirm the bullet names the trigger (stateful contract), the six checks inlined verbatim (canonical shipped definition), the pre-first-push timing, and the Document Quality Gate row requirement

**Expected result**: All four elements present; the bullet inlines the six checks (canonical definition) and cross-references `review-doctrine.md` patterns for their detection guidance.

### Step 2: Plan-stage gate is present

**Maps to**: same brief scope, plan surface

1. Open `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
2. Confirm Step 5 (cross-section consistency self-check) covers plan decision tables and Refactor work item briefs
3. Confirm the Document Quality Gate template includes a `Matrix coherence preflight` row example

**Expected result**: Both edits present; no restated six-check list (pointer to the canonical definition only).

### Step 3: Loop re-run rule is present

**Maps to**: brief desired outcome — "run … again after repeated meaningful reviewer findings on the same matrix"

1. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
2. Locate the "Long spec/plan review-cycle guidance" section
3. Confirm the re-run rule: two consecutive cycles whose blocking findings implicate the same matrix (matrix identity: its section heading, table, or step anchor in the reviewed spec, plan, or Refactor work-item brief) trigger a full six-check re-audit by the loop runner before the next fix push, with the result recorded in the fix commit comment and the counter-reset semantics stated (resets on a non-implicating cycle and after the re-audit)
4. Confirm the existing stuck-loop escalation path is stated as unchanged

**Expected result**: Re-run rule (loop-runner ownership, matrix identity, counter-reset semantics) and unchanged-escalation statement both present.

### Step 4: Simple specs gain no ceremony

**Maps to**: brief scope — "Keep the check targeted to matrix/state-machine specs"

1. Open the simple non-matrix document from Test Data
2. Read the Protocol 01 gate bullet: confirm the trigger requires a stateful contract
3. Confirm a `Not applicable — no stateful contract` row with rationale is the documented path for such documents

**Expected result**: The audit is not required for the simple document; the escape valve is a reasoned log row, not silent skipping.

### Step 5: Evidence shape is concrete

**Maps to**: brief scope — "what evidence it should produce"

1. Open `REVIEW.md`'s Spec Review Checklist
2. Confirm the bullet requiring the `Matrix coherence preflight` row on matrix-bearing spec PRs, requiring an audit summary (`Checked` or `Checked — gaps found`); a `Not applicable — no stateful contract` row on a matrix-bearing spec is itself a blocking misclassification finding (`Not applicable` is reserved for the non-stateful case in Step 4)
3. Repeat for the Plan Review Checklist
4. Open the `#1757` spec's decision-gate matrix and walk one check (e.g. check 2, missing states) as a dry run: confirm the six-check definition inlined in Protocol 01's preflight bullet is answerable against that real matrix

**Expected result**: Reviewer-side checks present; the six checks are answerable against the real #1757 matrix.

### Step 6: Mirror surfaces cross-reference only

**Maps to**: Decision 2 / Rule 2 (no drift)

1. Run: `grep -rn "Matrix coherence preflight"` over the 22 implementation targets listed in the plan's Verification Log row "Full 22-file population" (exclude the retained plan and this runbook, which necessarily restate the checks)
2. Read each hit
3. Confirm every hit is the canonical definition, a pointer to it, or the gate-row name — no restated variant of the audit checks
4. Drift catch beyond the phrase: diff the audit-check list inlined in Protocol 01's preflight bullet against each other surface's text. Run `grep -n "overlapping rows\|missing states\|precedence"` over the same 22 targets (same exclusions) and read each hit: a surface naming check classes in its own words (rather than pointing to Protocol 01 or `review-doctrine.md`) is a restatement

**Expected result**: No file redefines the checks; agent/skill mirrors carry pointer sentences only.

### Last Step: Validate

- Verify all assertions in the checklist below are met

---

## Assertions Checklist

Each checkbox maps to a scope bullet or desired-outcome sentence of the #1759 brief.

- [ ] The preflight's first run is documented at creator stage before first push (brief: "run before entering the automated reviewer loop")
- [ ] The re-run trigger after two same-matrix review cycles is documented (brief: "again after repeated meaningful reviewer findings on the same matrix")
- [ ] The six audit classes are documented: overlapping rows, missing states, precedence/order ambiguity, malformed/unknown input handling, stale-vs-current evidence, terminal vs waiting vs escalation outcomes (brief scope bullet 1)
- [ ] Ordinary simple specs gain no ceremony — reasoned `Not applicable` path (brief scope bullet 2)
- [ ] Workflow placement and required evidence are documented (brief scope bullet 3)
- [ ] No new script/parser/config surface is added — the audit composes with, and does not duplicate, #1561's reviewer preflight

---

## Seed Data Reference

None — documentation-only feature.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A mirror file restates the audit checks with different wording | Step 8 of Implementation Order (drift review) skipped, or this runbook's Step 6 drift checks skipped | Replace the restatement with a pointer sentence; re-run the Step 6 greps |
| Doctrine file exceeds 12,000 bytes | New pattern written too large | Merge or trim the pattern per `review-doctrine.md`'s own bound rule — never raise the bound in the same change |
| `REVIEW.md` row missing on a matrix-bearing spec PR | Implementer skipped the checklist bullet | Add the row with audit summary; treat as blocking per the checklist |

---

## Known Limitations

- The audit's pass/fail is a human judgment against doctrine Detect questions; there is no automated oracle (deliberate — see the plan's Decision 1).
- This runbook validates document state after merge; it does not exercise a live reviewer loop.
