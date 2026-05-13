# Smoke Test Runbook: CodeRabbit as Internal Reviewer (Step 7a)

**Feature**: CodeRabbit as Internal Reviewer — Step 7a (Issue #528)
**Spec**: [`docs/specs/developments/20260508083619_528-coderabbit-internal-reviewer/1_528-coderabbit-internal-reviewer_specs.md`](../../specs/developments/20260508083619_528-coderabbit-internal-reviewer/1_528-coderabbit-internal-reviewer_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Protocol 91 Step 7a has been updated (supported values list, reachability table,
      reviewer dispatch map)
- [ ] `coderabbit.md` has a "Step 7a — Internal Reviewer (Draft PRs)" section
- [ ] `.ai-dev-workflow.yaml` comment block lists `coderabbit` as a supported
      `internal_reviewers` value
- [ ] You have access to the repository files to inspect

---

## Test Data

| Item                           | Value                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------ |
| Protocol file                  | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Integration doc                | `docs/workflow/development-workflow/integrations/coderabbit.md`                |
| Config file                    | `.ai-dev-workflow.yaml`                                                        |
| Supported values line (before) | `` `claude`, `codex`. ``                                                       |
| Supported values line (after)  | `` `claude`, `codex`, `coderabbit`. ``                                         |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 lists `coderabbit` as a supported value

- Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- Locate the "Determining which reviewers to run" sub-section under Step 7a
- Find the sentence beginning with "Supported reviewer values:"

**Expected result**: The sentence reads: `Supported reviewer values: 'claude', 'codex', 'coderabbit'.`

---

### Step 2: Verify the reachability classification table includes `coderabbit`

**Maps to**: BR-2, BR-9

- In the same file, locate the "Reachability classification table" under "Runtime-availability
  check"
- Inspect the table header row

**Expected result**: The table has three `reachable?` columns: `claude`, `codex`, and
`coderabbit`. All four runner-context rows have an entry in the `coderabbit` column
indicating "Determined at runtime (App check)" or equivalent wording.

---

### Step 3: Verify the runtime App check explanation is present

**Maps to**: BR-2, BR-5

- Immediately after the reachability classification table, look for an explanatory paragraph

**Expected result**: A paragraph is present that describes:

1. How the runner detects CodeRabbit App installation (e.g., `gh api` or checking prior
   `coderabbitai[bot]` PR activity)
2. That `.coderabbit.yaml` is checked for draft-PR restrictions
3. That failure of either check results in `coderabbit` being classified as `unreachable`

---

### Step 4: Verify `coderabbit` rows in the reviewer dispatch map

**Maps to**: AC (Protocol 91 Step 7a documentation updated)

- Locate the "Reviewer dispatch map" table in Protocol 91 Step 7a

**Expected result**: The table contains three rows for `coderabbit`:

- One row for `spec/*` branch prefix
- One row for `implementation-plan/*` branch prefix
- One row for `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` branch prefixes
- Each row references the `coderabbit.md` Step 7a section for invocation details

---

### Step 5: Verify `coderabbit.md` has a Step 7a section

**Maps to**: AC (`coderabbit.md` integration doc updated)

- Open `docs/workflow/development-workflow/integrations/coderabbit.md`
- Scan the top-level headings (lines starting with `## `)

**Expected result**: A heading "Step 7a — Internal Reviewer (Draft PRs)" or equivalent is
present as a top-level section.

---

### Step 6: Verify `coderabbit.md` Step 7a section content

**Maps to**: AC, BR-3, BR-4, BR-5

- Open the "Step 7a — Internal Reviewer (Draft PRs)" section in `coderabbit.md`

**Expected result**: The section contains all of the following:

- [ ] Configuration instructions (set `coderabbit` in `review.internal_reviewers`)
- [ ] Draft-PR requirement: `reviews.auto_review.enabled: true` in `.coderabbit.yaml`
- [ ] Invocation mechanism: CodeRabbit auto-reviews on push; runner polls for
      `coderabbitai[bot]` response
- [ ] Severity classification: `Critical` and `Major` blocking; `Minor`/`Low`/no-marker
      are suggestions
- [ ] Fix-cycle limit: subject to `max_internal_review_cycles` (default: 5)
- [ ] Troubleshooting subsection with entries for: App not installed, `auto_review.enabled:
false`, draft PRs not enabled, all reviewers unreachable

---

### Step 7: Verify `.ai-dev-workflow.yaml` comment block updated

**Maps to**: BR-10

- Open `.ai-dev-workflow.yaml`
- Locate the `internal_reviewers` comment block (above the `internal_reviewers:` key)

**Expected result**: The comment block contains a `coderabbit` entry with a brief description
of its invocation behaviour (GitHub App auto-review, draft-PR requirement). The entry appears
after the `codex` entry and before the "Runner-context constraint" paragraph.

---

### Step 8: Verify backward compatibility — `review.platforms` not affected

**Maps to**: BR-8

- In `.ai-dev-workflow.yaml`, locate `review.platforms`
- Confirm `coderabbit` is still listed there (existing configuration)
- In Protocol 91, confirm the Step 7 section (Automated Reviewer Loop) has no reference to
  `internal_reviewers` that would affect its behaviour

**Expected result**: The `review.platforms` section and Step 7 behaviour are unchanged.
Adding `coderabbit` to `review.internal_reviewers` is independent of its presence in
`review.platforms`.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Protocol 91 Step 7a "Supported reviewer values" sentence includes `coderabbit`
- [ ] Reachability classification table has a `coderabbit` column with runtime-check
      annotation
- [ ] Reviewer dispatch map has `coderabbit` rows for all three branch-prefix groups
- [ ] `coderabbit.md` has a "Step 7a — Internal Reviewer (Draft PRs)" section
- [ ] The Step 7a section in `coderabbit.md` covers: configuration, draft-PR requirement,
      invocation, severity classification (BR-3), fix-cycle limit (BR-4), availability check
      (BR-2), and troubleshooting
- [ ] `.ai-dev-workflow.yaml` comment block lists `coderabbit` as a supported
      `internal_reviewers` value (BR-10)
- [ ] No change to Step 7 (external reviewer loop) behaviour — `review.platforms` path
      unaffected (BR-8)

---

## Seed Data Reference

None. This feature affects only protocol documentation and configuration comments.

| Entity | Scenario | How to load |
| ------ | -------- | ----------- |
| —      | —        | —           |

---

## Troubleshooting

| Symptom                                                        | Likely cause                      | Fix                                                                                         |
| -------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------- |
| `coderabbit` still not in "Supported reviewer values" sentence | Implementation step 1 not applied | Re-check the exact line in Protocol 91 and apply the change                                 |
| Reachability table missing `coderabbit` column                 | Implementation step 2 not applied | Add the column with "Determined at runtime (App check)" values for all four runner contexts |
| `coderabbit.md` has no Step 7a section                         | Implementation step 4 not applied | Add the section after "Usage Modes" with required subsections                               |
| `.ai-dev-workflow.yaml` comment not updated                    | Implementation step 5 not applied | Insert the `coderabbit` block comment after the `codex` comment block                       |

---

## Known Limitations

- This smoke test is documentation-only; it does not exercise the runtime CodeRabbit
  invocation path (requires a live draft PR with CodeRabbit GitHub App installed).
- End-to-end testing of the Step 7a CodeRabbit flow (including polling, severity
  classification, and fix cycles) requires a real repository with the CodeRabbit App
  configured for draft-PR reviews.
