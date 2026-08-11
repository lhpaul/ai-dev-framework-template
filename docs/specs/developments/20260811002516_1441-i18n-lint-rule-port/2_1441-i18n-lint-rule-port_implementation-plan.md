# Port i18n No-Literal-String Doctrine and Catalogue Reference — Implementation Plan

**Spec**: Refactor item #1441 - tracker brief only, no product spec
**Smoke test runbook**: [1441-i18n-lint-rule-port.smoke-test.md](../../../testing/workflow/1441-i18n-lint-rule-port.smoke-test.md)

---

## Summary

**Approach**: This template ships no application source code and no
per-project i18n runtime. The only tracked JS/TS surfaces are the
placeholder `e2e/` Playwright scaffold (a single `baseline.spec.ts`
placeholder test, explicitly meant to be replaced by a downstream project's
own specs) and the `hooks/` Haystack tooling (git-hook internals, not a unit
test runner) — neither is a product application source tree, and neither
hosts a unit-test runner (Jest/Vitest) suited to the source PR's
`.test.ts` suites (`docs/best-practices/stack/` files are curated,
framework-owned **reference documentation**, not executable project code —
see `stack/supabase.md` for the established pattern). The
`personal-finances` reference (`#34` / PR #41) is a React Native + i18next
implementation; the template cannot host it as live, CI-enforced code without
inventing a JS toolchain this repo does not otherwise have, which is out of
this item's scope. The port therefore ships as: (1) a new
`docs/best-practices/stack/i18n.md` worked-reference doc that separates the
portable doctrine from the illustrative React Native/i18next example code
(catalogue/resolver skeleton, ESLint config block, and the key-extraction
scanner with its E1-E13b edge-case table, including the dynamic-key
concatenation gap the issue calls out by name), and (2) a conditional
`REVIEW.md` checklist addition requiring, for any project that has adopted
this convention, that the enforcement mechanism be active and that any new
or materially modified instance of it carry a planted-violation proof per
the existing generic Verification Discipline clause. A short cross-reference
is added from `docs/best-practices/3-testing.md`'s existing
"Planted-Violation Proofs" section, and a reference row is added to
`docs/best-practices/STACK-SPECIFIC.md`'s technology table, mirroring the
existing Supabase row.

**Estimated complexity**: S

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: No code, no scripts, no CI changes, and no new automated check
is added to this repository. The work is a single cohesive documentation
addition plus one conditional `REVIEW.md` checklist block and two small
cross-reference edits, all verified against an already-merged, already-proven
reference implementation. The main cost is precision — separating doctrine
from illustration and citing the source PR's own verified proof transcript
correctly — not volume or novel design.

**Dependencies**: None.

---

## Template-Fit Assessment (Protocol 02 Step 0 — mandatory, `template.is_template: true`)

**Evaluation**: The issue's literal ask — "port the lint rule (with its test
suite) and the catalogue/resolver skeleton" — fails the fit check as
literally stated: `eslint-plugin-i18next`, `i18next`/`react-i18next`,
`expo-localization`, and the Jest test suites in the source PR are all
React Native/JS-stack-specific, and this template repository's own toolchain
has no Node application source tree and no unit-test runner (Jest/Vitest)
capable of hosting them. The repository's only tracked JS/TS surfaces are
the placeholder `e2e/` Playwright E2E scaffold (a single
`baseline.spec.ts` placeholder, per `REVIEW.md`'s own "E2E regression
(placeholder)" framing — not a committed functional suite) and the
`hooks/` Haystack git-hook internals; neither is a product application, and
neither is a unit-test runner suited to the source PR's `.test.ts` suites.
Shipping the source PR's `.ts`/`.test.ts` files here would create orphaned
code with no CI job ever executing it — which is itself a
"declared-but-unverified control" under `REVIEW.md`'s own Verification
Discipline clause, the opposite of what the issue is asking for.

**Resolution — narrowed scope (Protocol 02 Step 0 option 2)**: The task
handoff that dispatched this item explicitly pre-authorized this narrowing,
walking through the same three-bucket split applied below (portable
doctrine / stack-specific worked example / not portable at all) and stating
"if you conclude the portable core is much smaller than the issue implies,
say so plainly rather than over-porting." That framing **is** the human's
scope-narrowing instruction for Step 0 option 2, supplied in advance rather
than requested interactively; this plan applies it rather than re-asking a
question the dispatching instructions already answered. The bucket split:

| Bucket | Content | Where it lands |
| --- | --- | --- |
| **1. Portable framework doctrine** | No-hardcoded-string rule, catalogue with primary + fallback locale, "enforcement must be machine-checked, not prose," planted-violation-proof discipline applied to the enforcement mechanism itself, data-driven-copy-through-catalogue pattern | `docs/best-practices/stack/i18n.md` (doctrine sections) + a conditional `REVIEW.md` checklist block |
| **2. Stack-specific worked example** | The exact `i18next`/`react-i18next`/`expo-localization` config, the flat-key JSON catalogue shape, the ESLint rule block, the regex-based key-extraction scanner (including its E1-E13b edge-case table and the dynamic-key concatenation gap) | `docs/best-practices/stack/i18n.md` (illustrative code blocks, explicitly labeled as one worked JS/React-Native example, not a universal law) |
| **3. Not portable at all** | The actual `apps/mobile/src/i18n/*.ts` runtime files, the Jest test files, the `eslint-plugin-i18next` dependency, and the specific `es`/`en` catalogue content | Stays in `personal-finances`; not shipped in this repository at all |

No template content is added for bucket 3. Continuing to Step 1 is
appropriate under this resolution; no further human confirmation is sought
before writing the plan, matching the max-autonomy default in Step 2 below.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `6830fd9` (worktree base = `origin/develop` after PR #1465 merge) |
| Template ships no product application source tree or unit-test runner | `find . -maxdepth 2 -type d ! -path './.git*' ! -path './node_modules*'` (top-level dirs) and `git ls-files -- '*.ts' '*.tsx'` (every tracked `.ts`/`.tsx` file repo-wide, any depth, in `ai-dev-framework-template`) | Top-level dirs: `.agents/ .claude/ .codex/ .codex-worktrees/ .cursor/ .entire/ .git/ .github/ .haystack/ .tmp/ .worktrees/ docs/ e2e/ hooks/ scripts/ template/`. The `git ls-files` scan is the source of truth for tracked `.ts`/`.tsx` files at any depth (the top-level `find` alone cannot prove this): it returns exactly 12 files — `e2e/playwright.config.ts` and `e2e/tests/baseline.spec.ts` (a tracked Playwright placeholder spec, run by `"test": "playwright test"` in `e2e/package.json`), plus 10 files under `hooks/agent-context/` and `hooks/truncation-checker/` (Haystack git-hook internals, not a unit-test runner). Neither surface is a product application source tree, and neither hosts a unit-test runner (Jest/Vitest) suited to the source PR's `.test.ts` suites. |
| `docs/best-practices/stack/` precedent | `ls docs/best-practices/stack/` | Only `.gitkeep` and `supabase.md`; `supabase.md` is pure prose + illustrative TypeScript code blocks, not a runnable/tested file, confirming the doc-only pattern this plan follows. |
| `STACK-SPECIFIC.md` precedent row | `sed -n '1,40p' docs/best-practices/STACK-SPECIFIC.md` | The "Best Practices by Technology" table already has a concrete `| Supabase | [stack/supabase.md](stack/supabase.md) |` row alongside placeholder rows, confirming new concrete rows are added directly to this shared template file rather than left for per-project setup only. |
| Reference implementation is merged and proven | `gh pr view 41 --repo lhpaul/personal-finances` | MERGED. PR body includes a three-run lint transcript (fails on a planted literal at `apps/mobile/src/dev/DesignSystemGallery.tsx:76:34`, passes before/after) and a `grep -rn "no-literal-string"` showing zero `eslint-disable` usages. |
| Scanner already covers the dynamic-key gap named in the issue | `sed -n '1,135p' apps/mobile/src/test-utils/catalogue-key-scan.ts`, `sed -n '1,111p' apps/mobile/src/test-utils/catalogue-key-scan.test.ts`, and `git log --follow --oneline -- apps/mobile/src/test-utils/catalogue-key-scan.ts` (in `personal-finances`) | `parseFirstArgument`'s E13 handling and tests `E13`/`E13b` explicitly classify `t('ds.a' + suffix)` and `t('ds.' + section + '.title')` as **dynamic**, not as the quoted prefix — this is the fixed behavior. `git log --follow` returns exactly one commit (`54d4390`) for this file, confirming PR #41 was merged as a single squashed commit; the "first version… unverified" regression is therefore documented only in the plan/PR review history, not recoverable from `git log`. This plan documents the pitfall and its fix explicitly in `i18n.md` rather than relying on inaccessible git history. |
| `REVIEW.md` "Additional checks" block format | `grep -n "Additional checks for" REVIEW.md` | 10 existing conditional blocks follow a consistent `Additional checks for **<condition>**:` heading + bullet-list format; this plan's new block follows the same format, placed after the existing "automated check, guard, lint rule, or CI job" block (line ~318) since it is a specialization of that same discipline. |
| Parser-risk classifier | Applied Protocol 02 Step 3 classification criteria against Layer-by-Layer Changes below | **Not applicable** — no file under `scripts/lint/`/`scripts/parse/` (or equivalent) is added or modified; the scanner is reproduced only as an illustrative, non-executed code block inside a documentation file. See "Parser-risk classification" note under Layer-by-Layer Changes. |
| Cross-cutting checklist classifier | Applied Protocol 02 Step 3 classification criteria against the `REVIEW.md` change | **Not applicable** — the new block is a narrow, conditional "Additional checks for…" entry (the same pattern as the ten existing conditional blocks), not a new mandatory category every plan/implementation must address, and it does not rename or restructure an existing checklist category. |

---

## Cross-Cutting Operational Assumption Check

### Not applicable

**Result**: `Not applicable` — this plan does not depend on a shared
environment target, linked cloud resource, approved base branch, artifact
owner, or canonical configuration value that concurrent batch work could
invalidate. The worktree was created from `origin/develop` at `6830fd9`,
which already includes PR #1465 (#1443's `REVIEW.md` Verification
Discipline additions) merged ahead of this item in the same batch; this
plan's `REVIEW.md` edit builds on that already-merged content rather than
conflicting with it. No other item in the current batch (#1434, #1437,
#1433, #1430, #1436, #1435, #1438, #1443 merged; #1432 stopped for a spec)
touches `docs/best-practices/stack/`, `docs/best-practices/3-testing.md`,
`docs/best-practices/STACK-SPECIFIC.md`, or the same `REVIEW.md` section.

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] None. No database or seed data changes.

### Backend / API

- [ ] None. No product API changes — this repository ships no product
      application.

### Shared Packages / Libraries

- [ ] None. No script or shell-helper changes; no new automated check is
      added to this repository's own CI.

### Frontend / UI

- [ ] None. Not applicable — no application UI exists in this repository.

### Documentation

- [ ] `docs/best-practices/stack/i18n.md` (new) — worked reference doc with:
  - **Doctrine** section: no-hardcoded-user-facing-string rule, catalogue
    with primary + fallback locale, "enforcement must be machine-checked,"
    planted-violation-proof discipline applied to i18n enforcement
    specifically, data-driven-copy-through-catalogue pattern. Framed as
    stack-agnostic guidance any project can apply regardless of language or
    UI framework.
  - **Worked example: React Native + i18next** section: the catalogue
    layout (flat, dotted keys; `es`/`en` shape), the `index.ts`/`locale.ts`
    resolver pattern, and the `eslint-plugin-i18next` config block —
    reproduced and adapted from `personal-finances`
    `apps/mobile/eslint.config.mjs` and `apps/mobile/src/i18n/{index,locale}.ts`,
    explicitly labeled as one illustrative stack, not a universal
    requirement.
  - **Key-extraction scanner and the dynamic-key pitfall** section: the
    `findTranslationKeys` regex-scanner pattern from
    `apps/mobile/src/test-utils/catalogue-key-scan.ts`, its E1-E13b
    edge-case table, and an explicit callout that an earlier draft of this
    class of scanner can accept the quoted prefix of `t('x.' + k)` as if it
    were the real key — E13/E13b close that gap — and that any downstream
    port of this scanner must include equivalent dynamic-key test coverage
    before the enforcement can be trusted. This satisfies the issue's
    "including the dynamic-key forms… that slipped past the first version
    of the scanner unverified" instruction as a documented, named pitfall
    with its concrete fix, since the original regression itself is not
    recoverable from `personal-finances`' squashed git history (see
    Verification Log).
  - **What is portable / not portable** section: restates the three-bucket
    split from the Template-Fit Assessment above, explicit that bucket 3
    (the actual runtime `.ts` files, Jest suites, and `eslint-plugin-i18next`
    dependency) stays in `personal-finances` and is not shipped here.
  - **Source** section: cites `lhpaul/personal-finances` issue #34 and PR
    #41, including the three-run lint transcript summary (fails at
    `apps/mobile/src/dev/DesignSystemGallery.tsx:76:34` on a planted
    literal, passes before/after) as the proof that the worked example is
    production-proven — not re-run here, since the code is not executable
    in this repository.
- [ ] `docs/best-practices/STACK-SPECIFIC.md` — add one row to the "Best
      Practices by Technology" table: `| Internationalization (i18n) | [stack/i18n.md](stack/i18n.md) — if applicable |`, mirroring the existing Supabase row.
- [ ] `docs/best-practices/3-testing.md` — add a one-line cross-reference
      inside the existing "Planted-Violation Proofs" section pointing to
      `docs/best-practices/stack/i18n.md`'s dynamic-key scanner example as a
      worked instance of this generic rule. No new subsection; avoid
      duplicating content already stated in either file (`REVIEW.md`'s own
      "Intra-file content duplication" check applies equally well to
      cross-file duplication and this plan treats it as the same bar).
- [ ] `REVIEW.md` — add one new conditional "Additional checks for…" block
      to the Code Review Checklist, Pass 2, placed immediately after the
      existing "PRs that add or modify an automated check, guard, lint
      rule, or CI job" block (current line ~318-323), reading (illustrative
      wording, final copy may adapt for house style consistency with the
      surrounding ten blocks):

  ```markdown
  Additional checks for **PRs that add or modify user-facing copy in a
  project with a configured i18n / catalogue convention** (see
  `docs/best-practices/stack/i18n.md`):

  - **Enforcement is active**: confirm the project's no-hardcoded-string
    enforcement mechanism (lint rule or equivalent machine check) is
    configured and currently enabled, not just documented.
  - **Catalogue parity**: confirm every catalogue/locale file the project
    ships is updated together — no locale is left with a missing or stale
    key that another locale added.
  - **Planted-violation proof for enforcement changes**: when the PR adds
    or materially modifies the enforcement mechanism itself (the lint rule
    config, a custom key-extraction scanner, or equivalent), apply the
    existing "automated check, guard, lint rule, or CI job" block above in
    full, including explicit coverage of any dynamic/non-literal key
    argument form the scanner is meant to reject.
  ```

### Infrastructure / Configuration

- [ ] None.

**Parser-risk classification note**: the key-extraction scanner is
reproduced only as an illustrative code block inside
`docs/best-practices/stack/i18n.md`; no file under `scripts/lint/`,
`scripts/parse/`, or an equivalent scanner directory is added or modified by
this plan, so the parser-risk addendum (edge-case enumeration mapped to
named unit test files) does not apply to this repository's own test suite.
The E1-E13b edge-case table is still included in the doc itself, in full,
because it is exactly the content a downstream implementer needs to
reproduce the scanner correctly and prove it with their own tests — see the
"Key-extraction scanner and the dynamic-key pitfall" section above.

---

## Testing Strategy

**Test types**: Markdown lint, manual documentation review (no code is
added, so no unit/integration/smoke automated test tier applies to this
repository's own CI).

**Key scenarios to test**:

1. `docs/best-practices/stack/i18n.md` renders correctly, its code blocks
   are syntactically plausible TypeScript/YAML/JS, and its "portable /
   stack-specific / not portable" section correctly enumerates all three
   buckets without contradiction. Maps to brief objective "port the lint
   rule and catalogue skeleton, generalized for a stack-agnostic template."
2. The dynamic-key pitfall (`t('x.' + k)`) is documented with its own
   labeled edge cases (E13/E13b) distinct from the static-key cases
   (E1-E12), matching the issue's explicit callout. Maps to brief objective
   "include the planted-violation proof discipline… including the
   dynamic-key forms."
3. The new `REVIEW.md` block is placed correctly, does not duplicate the
   existing generic Verification Discipline / "automated check" block, and
   is conditional on a project having adopted the i18n convention (does not
   force every downstream project through an i18n checklist it does not
   need). Maps to brief objective "a protocol note that the review gate
   requires the rule to be active."
4. `docs/best-practices/STACK-SPECIFIC.md` and `docs/best-practices/3-testing.md`
   cross-references resolve to the new file and do not duplicate its
   content.
5. All six modified/added Markdown files (the implementation plan itself,
   `i18n.md`, `STACK-SPECIFIC.md`, `3-testing.md`, `REVIEW.md`, and the
   smoke-test runbook) pass standard `markdownlint-cli2` linting. The two
   files under `docs/specs/developments/` and `docs/testing/workflow/` (the
   plan and the smoke-test runbook) additionally pass the heuristic lint
   script, which is scoped to those two directories only per
   `scripts/lint/README.md` and does not apply to `i18n.md`,
   `STACK-SPECIFIC.md`, `3-testing.md`, or `REVIEW.md`. See Implementation
   Order step 7.

**Smoke test runbook**: `docs/testing/workflow/1441-i18n-lint-rule-port.smoke-test.md`

**Regression suite**: Not applicable — this repository has no committed
JS/TS regression suite for this content to extend, and no shell/Python
helper is added or modified.

### Parser-risk addendum

Not applicable — see "Parser-risk classification note" above.

### Concurrent-event-source addendum

Not applicable — this plan adds documentation only; no listeners, timers,
callbacks, or shared mutable state are introduced.

---

## Seed Data

None.

---

## Documentation Updates

- [ ] `docs/best-practices/stack/i18n.md` — new file (see Layer-by-Layer
      Changes → Documentation).
- [ ] `docs/best-practices/STACK-SPECIFIC.md` — add the i18n technology row.
- [ ] `docs/best-practices/3-testing.md` — add the one-line cross-reference
      in "Planted-Violation Proofs."
- [ ] `REVIEW.md` — add the new conditional checklist block.
- [ ] `AGENTS.md` — None. This change does not alter project overview,
      commands, or cross-cutting conventions AGENTS.md is responsible for;
      `docs/best-practices/STACK-SPECIFIC.md` is already the correct
      pointer surface for per-technology docs.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A future reviewer or downstream project mistakes the illustrative React Native/i18next code blocks in `i18n.md` for a mandatory dependency choice | Low | Medium | Explicit "worked example, not a universal requirement" framing at the top of that section, plus the dedicated "what is portable / not portable" section. |
| Duplicating the generic Verification Discipline / planted-violation-proof language between `REVIEW.md`'s existing block and the new i18n-specific block | Medium | Low | New block only adds i18n-specific checks (enforcement active, catalogue parity) and explicitly delegates to the existing "automated check" block for proof requirements, rather than restating it. |
| REVIEW.md's `Additional checks for **PRs that add or modify an automated check…**` block already covers this without a dedicated i18n block, making the new block redundant | Low | Low | The new block adds project-scoped checks (catalogue parity, "is it actually turned on") that are not covered by the generic block, which only concerns proof of new/modified checks, not whether an existing one stays active and configured. |
| The issue's ask ("port the lint rule with its test suite") reads as expecting runnable code, and a documentation-only port under-delivers relative to that expectation | Medium | Medium | Template-Fit Assessment section states the reasoning plainly and is surfaced to the human in the plan PR; the dispatching instructions explicitly pre-authorized this narrowing and asked to "say so plainly" if the portable core is smaller than the issue implies. |

---

## Code Samples

> Illustrative — adapt during implementation. The final `i18n.md` prose and
> exact block wording, ordering, and headings are decided during
> implementation, not fixed here.

```markdown
## Doctrine

- No user-facing literal string in UI markup — copy lives in catalogues,
  resolved by key lookup.
- Catalogues have a primary locale and at least one fallback locale.
- ...
```

```markdown
Additional checks for **PRs that add or modify user-facing copy in a
project with a configured i18n / catalogue convention** (see
`docs/best-practices/stack/i18n.md`):

- **Enforcement is active**: ...
```

---

## Implementation Order

1. Create `docs/best-practices/stack/i18n.md` with the Doctrine, Worked
   example, Key-extraction scanner and dynamic-key pitfall, What is
   portable / not portable, and Source sections described in
   Layer-by-Layer Changes → Documentation.
2. Add the i18n row to `docs/best-practices/STACK-SPECIFIC.md`'s "Best
   Practices by Technology" table.
3. Add the one-line cross-reference to `docs/best-practices/3-testing.md`'s
   "Planted-Violation Proofs" section.
4. Add the new conditional "Additional checks" block to `REVIEW.md`'s Code
   Review Checklist, Pass 2, after the existing "automated check, guard,
   lint rule, or CI job" block.
5. Update project docs per **Documentation Updates** above (already
   completed by steps 1-4; no additional doc beyond those four files
   requires an update).
6. Update `CHANGELOG.md` under `[Unreleased]` — **do not do this in the
   plan PR**; `implementation-plan/*` branches are exempt from CHANGELOG
   entries per `REVIEW.md`'s Plan Review Checklist. The implementation PR
   adds:
   - `- **Port i18n no-literal-string doctrine and catalogue reference** (#1441): adds \`docs/best-practices/stack/i18n.md\` with the portable no-hardcoded-string doctrine, a React Native/i18next worked example, and the dynamic-key scanner pitfall, plus a conditional \`REVIEW.md\` review-gate check.`
7. Run validation (`bash` — the second command relies on Bash's `pipefail`
   and process substitution, not portable `sh`):
   - `npx markdownlint-cli2 "docs/specs/developments/20260811002516_1441-i18n-lint-rule-port/2_1441-i18n-lint-rule-port_implementation-plan.md" "docs/best-practices/stack/i18n.md" "docs/best-practices/STACK-SPECIFIC.md" "docs/best-practices/3-testing.md" "docs/testing/workflow/1441-i18n-lint-rule-port.smoke-test.md" "REVIEW.md"`
   - Heuristic lint, fail-closed (validates both scan directories exist and
     the discovered file list is non-empty before invoking the linter, and
     propagates `find`/`python3` failures instead of allowing a silent
     success):

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

     (Bash 3.2-compatible — uses process substitution, not the Bash-4-only
     `mapfile`/`readarray` builtins, since this repository's shell
     conventions target Bash 3.2 as documented in
     `scripts/lint/workflow-shell-snippet-lint.py`'s `BASH4` check.)
8. Execute the smoke test runbook and record the results in the
   implementation PR.
