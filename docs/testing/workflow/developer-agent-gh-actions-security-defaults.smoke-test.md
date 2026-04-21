# Smoke Test Runbook: Developer Agent — GitHub Actions Workflow Security Defaults

**Feature**: Developer Agent: GitHub Actions Workflow Security Defaults (#200)
**Spec**: [docs/specs/developments/20260420120000_developer-agent-gh-actions-security-defaults/1_developer-agent-gh-actions-security-defaults_specs.md](../../specs/developments/20260420120000_developer-agent-gh-actions-security-defaults/1_developer-agent-gh-actions-security-defaults_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR for #200 has been merged into `develop` (or you are reviewing the feature branch pre-merge)
- [ ] Local checkout includes `docs/ai/development-workflow/protocols/03-implement-development-protocol.md`

---

## Test Data

| Item | Value |
|---|---|
| Canonical protocol | `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` |
| Workflow glob | `.github/workflows/*.yml` |

---

## Smoke Test Steps

### Step 1: Section exists and is easy to find

**Maps to**: Acceptance criterion — “clearly titled section … for **GitHub Actions workflow security**”

1. Open `docs/ai/development-workflow/protocols/03-implement-development-protocol.md`.
2. Locate a top-level `##` heading whose title includes **GitHub Actions** and **workflow** / **security** (exact wording may vary slightly but must be unambiguous).
3. Confirm the section appears **before** `## Path 1: Full Pipeline` (so it is not hidden deep inside one path only).

**Expected result**: The section is present, titled clearly, and positioned at or near the top of the protocol (after “Which Path to Use?”).

---

### Step 2: Checklist covers all business rules

**Maps to**: Acceptance criteria — checklist content aligned with spec Business Rules

1. In the same section, verify an explicit Markdown checklist (or equivalent bullet checklist) requires:
   - Least-privilege `permissions:` with guidance that read-only jobs default to `contents: read` unless broader scope is justified.
   - Pinned `uses:` values to full commit SHAs with a human-readable version in a comment.
   - Path-based triggers (`paths:` / `paths-ignore:`) when appropriate.
   - `concurrency:` when duplicate runs would be harmful.
2. Confirm the text states that **exceptions** must be justified (e.g., in the PR description).

**Expected result**: All four checklist themes plus exception handling are present in prose or checklist form.

---

### Step 3: “Before PR” gate is explicit

**Maps to**: Acceptance criterion — checklist satisfied **before** a development PR when workflows change

1. Read the section’s timing language.
2. Confirm it states the checklist must be completed **before** opening the development PR when adding or materially changing `.github/workflows/*.yml`, or equivalent language for “before PR exists / before workflow lands on PR” (including the case where the PR already exists and workflow commits are added later).

**Expected result**: Timing is unambiguous; a reviewer can verify intent in one pass.

---

### Step 4: Reviewer single-pass sanity check

**Maps to**: Acceptance criterion — reviewer can confirm compliance without tribal knowledge

1. Open any `.github/workflows/*.yml` on a branch that claims to follow this protocol.
2. Without external docs, use only the new protocol section to decide whether the workflow appears to satisfy the documented checklist (permissions present, actions pinned, etc.).

**Expected result**: The protocol alone is sufficient to evaluate a workflow PR for the documented defaults.

---

## Assertions Checklist

- [ ] Clearly titled GitHub Actions workflow security section exists in `03-implement-development-protocol.md`.
- [ ] Checklist includes: `permissions`, pinned `uses:` SHAs + version comment, paths filters, concurrency, and exception guidance.
- [ ] Protocol states the checklist applies before opening (or before landing) workflow changes on a development PR when `.github/workflows/*.yml` is in scope.
- [ ] A reviewer can validate a workflow file using only the protocol text.

---

## Seed Data Reference

Not applicable.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Cannot find the new section | Implementation used a different heading | Search the file for `permissions` and `GITHUB_TOKEN`; align heading with spec. |
| Only Path 1 mentions workflows | Missing cross-refs | Add pointers from other paths per implementation plan. |

---

## Known Limitations

- This runbook validates **documentation** only; it does not execute GitHub Actions.
