# Smoke Test Runbook: Port i18n No-Literal-String Doctrine and Catalogue Reference

**Feature**: Port the no-literal-string i18n lint rule and catalogue skeleton
from `personal-finances` (#1441)
**Spec**: Refactor item #1441 - tracker brief only, no product spec
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation PR for #1441 is checked out locally.
- [ ] `npx markdownlint-cli2` is available (`npm install` at repo root, or
      rely on the repo's existing `devDependencies`).
- [ ] `python3` is available for the heuristic lint script.

---

## Test Data

| Item | Value |
| --- | --- |
| New reference doc | `docs/best-practices/stack/i18n.md` |
| STACK-SPECIFIC.md row | `| Internationalization (i18n) | [stack/i18n.md](stack/i18n.md) — if applicable |` |
| 3-testing.md cross-reference | One line inside the existing "Planted-Violation Proofs" section |
| REVIEW.md new block | `Additional checks for **PRs that add or modify user-facing copy in a project with a configured i18n / catalogue convention**` |
| Dynamic-key pitfall examples | `t('x.' + k)`-style concatenation forms (E13/E13b) |

---

## Smoke Test Steps

### Step 1: Verify the new reference doc exists and is complete

**Maps to**: brief objective "port the lint rule (with its test suite), the
catalogue/resolver skeleton, and a protocol note"

1. Open `docs/best-practices/stack/i18n.md`.
2. Confirm it contains, at minimum, these sections: a doctrine section
   (no-hardcoded-string rule, primary + fallback locale catalogues,
   machine-enforced convention), a worked React Native + i18next example
   (catalogue shape, resolver pattern, ESLint config block), a
   key-extraction scanner section with an edge-case table, and a "what is
   portable / not portable" section.
3. Confirm the worked-example section is explicitly labeled as one
   illustrative stack, not a universal requirement.

**Expected result**: The doc is present, internally consistent, and does
not present the React Native/i18next-specific tooling as mandatory for
every downstream project.

---

### Step 2: Verify the dynamic-key pitfall is documented by name

**Maps to**: brief objective "include the planted-violation proof discipline
… including the dynamic-key forms (`t('x.' + k)`) that slipped past the
first version of the scanner unverified"

1. In `docs/best-practices/stack/i18n.md`, locate the key-extraction
   scanner section.
2. Confirm the edge-case table includes at least one case for a static
   quoted key (e.g. `t('ds.a')`) and at least one case for a concatenated
   dynamic key (e.g. `t('ds.a' + suffix)` or `t('ds.' + section + '.title')`).
3. Confirm the dynamic-key case is explicitly called out as a case that an
   earlier/naive scanner implementation could mis-classify as a static key
   (accepting the quoted prefix), and that the documented fix is to treat
   any non-terminated quoted argument as dynamic rather than as the real
   key.

**Expected result**: The dynamic-key gap named in the issue is documented
as a concrete, named pitfall with its concrete fix — not only implied by a
generic edge-case list.

---

### Step 3: Verify the REVIEW.md checklist addition

**Maps to**: brief objective "a protocol note that the review gate requires
the rule to be active"

1. Open `REVIEW.md` and locate the Code Review Checklist, Pass 2 section.
2. Confirm a new `Additional checks for **PRs that add or modify
   user-facing copy in a project with a configured i18n / catalogue
   convention**` block exists, referencing `docs/best-practices/stack/i18n.md`.
3. Confirm the block checks that the enforcement mechanism is active and
   that catalogues stay in parity, and that it delegates to the existing
   "automated check, guard, lint rule, or CI job" block for planted-violation
   proof requirements rather than duplicating that language.
4. Confirm the block is clearly conditional (applies only to projects that
   have adopted the i18n convention), not a blanket requirement for every
   PR in every downstream repository.

**Expected result**: The review gate now has a discoverable, conditional
check that an i18n enforcement mechanism must be active, without forcing
i18n review overhead onto projects that do not use this pattern.

---

### Step 4: Verify cross-references

**Maps to**: general documentation quality / no content duplication

1. Open `docs/best-practices/STACK-SPECIFIC.md` and confirm a new row
   exists for i18n in the "Best Practices by Technology" table, linking to
   `stack/i18n.md`, mirroring the existing Supabase row's format.
2. Open `docs/best-practices/3-testing.md` and confirm the existing
   "Planted-Violation Proofs" section has a one-line cross-reference to
   `docs/best-practices/stack/i18n.md`'s dynamic-key scanner example.
3. Confirm neither cross-reference duplicates the full content of
   `i18n.md` — both are pointers, not copies.

**Expected result**: A reader following either `STACK-SPECIFIC.md` or
`3-testing.md` can discover `i18n.md` without content drift between files.

---

### Step 5: Run markdown lint

**Maps to**: repository quality gate

1. Run standard `markdownlint-cli2` against all six modified/added Markdown
   files, including the implementation plan itself:

   ```bash
   npx markdownlint-cli2 "docs/specs/developments/20260811002516_1441-i18n-lint-rule-port/2_1441-i18n-lint-rule-port_implementation-plan.md" "docs/best-practices/stack/i18n.md" "docs/best-practices/STACK-SPECIFIC.md" "docs/best-practices/3-testing.md" "docs/testing/workflow/1441-i18n-lint-rule-port.smoke-test.md" "REVIEW.md"
   ```

2. Confirm exit code 0.
3. Run the heuristic lint script, scoped only to
   `docs/specs/developments/` and `docs/testing/workflow/` (it does not
   apply to `i18n.md`, `STACK-SPECIFIC.md`, `3-testing.md`, or `REVIEW.md`),
   fail-closed:

   ```bash
   set -euo pipefail
   for d in docs/specs/developments/20260811002516_1441-i18n-lint-rule-port docs/testing/workflow; do
     [ -d "$d" ] || { echo "missing required directory: $d" >&2; exit 1; }
   done
   md_files=()
   while IFS= read -r -d '' f; do
     md_files+=("$f")
   done < <(find docs/specs/developments/20260811002516_1441-i18n-lint-rule-port docs/testing/workflow -name "*.md" -print0)
   [ "${#md_files[@]}" -gt 0 ] || { echo "no markdown files found to lint" >&2; exit 1; }
   python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md "${md_files[@]}"
   ```

4. Confirm exit code 0.

**Expected result**: All six files pass standard `markdownlint-cli2`
cleanly; the plan and smoke-test runbook additionally pass the
directory-scoped heuristic lint cleanly.

---

### Last Step: Assertions Checklist

- [ ] `docs/best-practices/stack/i18n.md` exists with doctrine, worked
      example, scanner/dynamic-key-pitfall, and portable/not-portable
      sections.
- [ ] The dynamic-key concatenation gap (`t('x.' + k)`) is documented by
      name with its concrete fix, distinct from the static-key cases.
- [ ] `REVIEW.md` has a new conditional checklist block requiring the
      enforcement mechanism to be active and catalogues to stay in parity.
- [ ] `docs/best-practices/STACK-SPECIFIC.md` and
      `docs/best-practices/3-testing.md` cross-reference `i18n.md` without
      duplicating its content.
- [ ] `markdownlint-cli2` and the heuristic lint script both pass on every
      changed/added file.
- [ ] No files under `apps/`, `src/`, `scripts/lint/`, or any executable
      JS/TS path were added — this port is documentation-only, per the
      plan's Template-Fit Assessment.

---

## Seed Data Reference

No seed data required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `markdownlint-cli2` fails on a relative link | A link path is wrong relative to the linting file's own directory (e.g. `docs/best-practices/stack/`) | Re-check the relative path from the linting file's own directory, not the repo root. |
| Heuristic lint flags a broken cross-reference | `STACK-SPECIFIC.md` or `3-testing.md` link text/path does not match the actual new file path | Confirm the exact path `docs/best-practices/stack/i18n.md` is used consistently. |
| Reviewer reads the worked example as a mandatory dependency | Missing or unclear "illustrative, not universal" framing at the top of the worked-example section | Add or strengthen the framing sentence; see plan Risks & Mitigations. |

---

## Known Limitations

- This smoke test is documentation-only verification; it does not execute
  any lint rule, because no executable version of the rule is shipped in
  this repository (see the plan's Template-Fit Assessment). A downstream
  project that adopts this pattern in a real application is responsible for
  producing its own planted-violation proof against its own codebase.
