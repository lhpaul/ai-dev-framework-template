# Smoke Test Runbook: Two-Phase Review Config

**Feature**: Simplify review config to two-phase draft/ready model (#868)
**Spec**: Refactor item #868 - tracker brief only
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation PR for #868 is checked out locally.
- [ ] `gh` CLI is authenticated.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` is executable.
- [ ] The PR branch is up to date with its remote.

---

## Test Data

| Item                    | Value                                           |
| ----------------------- | ----------------------------------------------- |
| New draft runner config | `review.on_draft.runner`                        |
| New draft GitHub config | `review.on_draft.github`                        |
| New ready GitHub config | `review.on_ready.github`                        |
| Legacy runner config    | `review.internal_reviewers`                     |
| Legacy reviewer config  | `review.platforms` + `review.phase_after_clean` |

---

## Smoke Test Steps

### Step 1: Verify New Default Config Shape

**Maps to**: Brief objectives 1, 2, 3

1. Open `.ai-dev-workflow.yaml`.
2. Confirm `schema_version` is bumped for the new canonical review config shape.
3. Confirm reviewers are configured under `review.on_draft.runner`, `review.on_draft.github`, and `review.on_ready.github`.
4. Confirm the same reviewer does not appear in more than one lifecycle bucket, including runner-vs-GitHub buckets.
5. Confirm legacy keys are absent from the canonical example except in compatibility comments.

**Expected result**: The shared template config uses only the two lifecycle phases as canonical configuration.

---

### Step 2: Verify Config Parser Coverage

**Maps to**: Brief objective 4

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Confirm the output includes passing tests for:
   - new `on_draft.runner` parsing;
   - new `on_draft.github` parsing;
   - new `on_ready.github` parsing;
   - legacy `internal_reviewers` mapping;
   - legacy `platforms + phase_after_clean` mapping;
   - duplicate reviewer detection across all lifecycle buckets;
   - `--pre-after-clean-only` alias behavior.

**Expected result**: The harness exits 0 and covers both new lifecycle config and legacy aliases.

---

### Step 3: Verify Reviewer-Loop CLI Semantics

**Maps to**: Brief objectives 2, 3, 4

1. Run the reviewer-loop help:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh --help
   ```

2. Confirm the preferred draft-only flag is documented.
3. Confirm `--pre-after-clean-only` is documented only as a deprecated compatibility alias.
4. Confirm lifecycle telemetry names are documented, or old `PHASE_AFTER_CLEAN_*` telemetry is explicitly marked as compatibility output.

**Expected result**: Help output describes draft/ready lifecycle behavior without presenting `phase_after_clean` as a canonical third reviewer type.

---

### Step 4: Verify Protocol And Docs Language

**Maps to**: Brief objective 5

1. Search canonical docs:

   ```bash
   rg -n "phase_after_clean|pre-after-clean|internal_reviewers|review.platforms" AGENTS.md docs/workflow/development-workflow .claude .cursor .codex .agents
   ```

2. Confirm remaining matches are either:
   - legacy compatibility notes;
   - historical changelog entries;
   - intentionally named compatibility telemetry or CLI aliases.

3. Confirm Protocol 91 describes `on_draft.runner`, `on_draft.github`, and `on_ready.github`.
4. Confirm Protocol 93 describes the draft/ready boundary and `gh pr ready` ordering.

**Expected result**: Canonical workflow guidance uses the new lifecycle names; legacy names are clearly scoped as compatibility.

---

### Step 5: Verify PR Readiness Behavior

**Maps to**: Brief objectives 2 and 3

1. Open a test PR or use a dry-run/mocked harness path from `test-pr-review-loop.sh`.
2. Confirm draft GitHub reviewers run before ready GitHub reviewers.
3. Confirm the ready-phase path calls `gh pr ready` once before ready GitHub reviewers run, using the explicit ready-transition helper/guard and existing per-PR single-instance lock.
4. Confirm CI and readiness labels still happen after reviewer-loop completion.

**Expected result**: Review scheduling follows draft -> ready ordering and preserves the existing PR readiness sequence.

---

### Last Step: Assertions Checklist

- [ ] Review config uses `on_draft` and `on_ready` as the canonical buckets.
- [ ] `schema_version` reflects the new canonical config shape.
- [ ] No canonical reviewer appears in more than one bucket, including runner-vs-GitHub buckets.
- [ ] Legacy config forms still parse through compatibility mapping.
- [ ] Draft GitHub reviewers run before `gh pr ready`.
- [ ] Ready GitHub reviewers run only after a single guarded `gh pr ready` transition.
- [ ] Protocols and integration docs no longer describe `phase_after_clean` as a third reviewer type.
- [ ] Reviewer-loop tests pass.

---

## Seed Data Reference

No seed data required.

---

## Troubleshooting

| Symptom                                  | Likely cause                                                 | Fix                                                                        |
| ---------------------------------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------- |
| Legacy config tests fail                 | Compatibility mapping missed one old key shape               | Add a focused parser test and update the mapping helper.                   |
| Ready reviewer runs on draft PR          | Ready boundary condition regressed                           | Check `pr-review-loop.sh` lifecycle filtering and `gh pr ready` placement. |
| Docs still recommend `phase_after_clean` | Search coverage missed an integration guide or agent wrapper | Update the remaining canonical reference or mark it as compatibility-only. |

---

## Known Limitations

- Full end-to-end reviewer execution still depends on configured external services. The shell harness should cover parser and scheduling behavior without requiring live reviewer accounts.
