# Markdown Lint for Plan and Spec Docs — Implementation Plan

**Spec**: [1_173-markdown-lint-plan-spec-docs_specs.md](./1_173-markdown-lint-plan-spec-docs_specs.md)
**Smoke test runbook**: [docs/testing/workflow/173-markdown-lint-plan-spec-docs.smoke-test.md](../../../testing/workflow/173-markdown-lint-plan-spec-docs.smoke-test.md)

---

## Summary

**Approach**: Add a new GitHub Actions workflow (`markdown-lint.yml`) that runs on every pull request touching `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`. The workflow uses `markdownlint-cli2` (npm) for standard rules (trailing whitespace, relative-link validation) together with a custom Python script for the two heuristic rules (suspicious glob patterns and within-document count disagreements). Existing baseline violations in all target files are resolved or suppressed in the same implementation PR so the check is green from day one.

**Estimated complexity**: M

**Rationale**: The standard rules (trailing whitespace, broken relative links) are well-served by `markdownlint-cli2` and the `markdownlint-rule-relative-links` plugin; these are battle-tested npm packages with inline-suppression support. The two heuristic rules (glob pattern mismatch, count disagreement) require custom logic that no off-the-shelf markdownlint rule provides — a small Python script handles these cleanly without additional runtime dependencies beyond the standard GitHub-hosted runner. The baseline cleanup effort is bounded (the target file set is small) but requires careful scanning.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Create `.github/workflows/markdown-lint.yml` — new GitHub Actions workflow triggered on `pull_request` for paths `docs/specs/developments/**`, `docs/testing/workflow/**`, and `CHANGELOG.md`; runs `markdownlint-cli2` and the custom heuristic script.
- [ ] Create `.markdownlint.jsonc` at the repository root — markdownlint-cli2 configuration enabling rules MD009 (trailing whitespace, hard-break exception), MD047 (files end with newline), and the `markdownlint-rule-relative-links` plugin for relative-link checking; disabling all other default rules that are not in scope.
- [ ] Create `scripts/lint/markdown-heuristic-lint.py` — custom Python 3 script implementing the two heuristic checks:
  - **Suspicious glob**: scans each input file for code blocks containing non-recursive globs (e.g., `*.sh`, `*.md`) while the surrounding document prose within a configurable window uses any phrase from a declared cue list (e.g., "subdirectories", "recursively", "under the tree", "all files in", "in all subdirectories"); emits `file:line: GLOB001 Suspicious non-recursive glob '<pattern>' — surrounding prose suggests recursion ('<cue>'); use '**/<pattern>' or suppress inline`.
  - **Count disagreement**: scans each input file for narrative count phrases (e.g., "4 acceptance criteria", "three use cases", "N steps") in digits or written-out numerals (0–20), then counts items in the list or section that immediately follows (within 30 lines); emits `file:line: COUNT001 Count disagreement — stated '<N> <label>' but found <actual> items; update the narrative or the list, or suppress inline`.
  - Supports inline suppression via `<!-- markdown-heuristic-disable GLOB001 -->` and `<!-- markdown-heuristic-disable COUNT001 -->` on the same or preceding line.
  - Accepts one or more file paths as positional arguments; exits 0 if no violations, exits 1 if any violations found.
  - The cue list for GLOB001 is declared as a top-level constant in the script so contributors can extend it without changing the detection logic.
- [ ] Add `scripts/lint/` directory with a `README.md` briefly describing the scripts it contains and their invocation.
- [ ] Create a new `package.json` at the repository root (no root-level `package.json` exists yet; the `e2e/package.json` is scoped to the Playwright suite and must not be modified for this feature) declaring `markdownlint-cli2` and `markdownlint-rule-relative-links` as `devDependencies`. Pin each dependency to the latest stable version available at implementation time using an exact version specifier (no `^` or `~`) so CI does not silently pick up upstream changes. Run `npm install` to generate the accompanying `package-lock.json`.
- [ ] Baseline cleanup: scan all files under `docs/specs/developments/`, `docs/testing/workflow/`, and `CHANGELOG.md` with both the markdownlint-cli2 rules and the heuristic script; fix any violations directly (remove trailing whitespace, fix broken relative links, correct count phrases or list lengths, correct glob patterns) or add an inline suppression with a reviewer-visible rationale where a fix is not appropriate.

---

## Testing Strategy

**Test types**: Smoke (manual CI trigger via PR; verifying green/red states)

**Key scenarios to test**:

1. PR touching only non-target markdown files — lint check passes or is skipped (AC5)
2. PR introducing a trailing-whitespace violation in a spec file — lint check fails with file/line detail (AC3, AC1)
3. PR introducing a broken relative link in a plan file — lint check fails with broken-link detail (AC2, AC1)
4. PR with no violations — lint check passes green (AC4)
5. PR with an inline suppression directive covering a violation — lint check passes (AC6)
6. CHANGELOG.md trailing whitespace — lint check fails (AC8)
7. Suspicious glob pattern with recursive prose — heuristic check fails (AC9)
8. Within-document count disagreement — heuristic check fails (AC10)
9. Implementation PR itself is green with no suppressions or with only documented suppressions (AC7)

**Smoke test runbook**: [`docs/testing/workflow/173-markdown-lint-plan-spec-docs.smoke-test.md`](../../../testing/workflow/173-markdown-lint-plan-spec-docs.smoke-test.md)

---

## Seed Data

None — this feature has no database layer or application state. The "data" is the markdown files in the repository, which are already present.

---

## Documentation Updates

- [ ] `AGENTS.md` (via `CLAUDE.md` symlink) — add a note in the **Common Commands** or **Troubleshooting** section describing how to run the markdown lint check locally: `npx markdownlint-cli2 <files>` and `python3 scripts/lint/markdown-heuristic-lint.py <files>`.
- [ ] `docs/best-practices/1-general.md` — add a bullet under **Formatting** pointing contributors to the markdown lint rules for spec/plan/CHANGELOG files, referencing `.markdownlint.jsonc`.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `markdownlint-rule-relative-links` produces false positives on intentional placeholder links or in-document anchors | Med | Med | Inline suppression is available; out-of-scope link types (anchors, external URLs) are explicitly excluded from the rule configuration |
| Heuristic count-disagreement check fires on numeric content unrelated to lists (version numbers, durations) | Med | Low | The regex is scoped to count-of-items phrasing keywords ("acceptance criteria", "use cases", "steps", "items"); inline suppression is available |
| Baseline cleanup surfaces many violations, delaying the PR | Med | Med | Scan the baseline before writing other plan artefacts (Step 5 of implementation order); block the PR only after cleanup is included in the same commit |
| `markdownlint-cli2` npm install time slows CI | Low | Low | Cache `node_modules` with `actions/cache` keyed on `package-lock.json` |
| Python 3 unavailable on the GitHub-hosted runner image | Low | High | GitHub-hosted `ubuntu-latest` includes Python 3 by default; verify in the first CI run |

---

## Implementation Order

1. Create the `scripts/lint/` directory and write `markdown-heuristic-lint.py` with both heuristic checks (GLOB001, COUNT001), inline suppression support, and the declared cue list constant.
2. Add `scripts/lint/README.md` briefly describing the script and its invocation.
3. Create or update `package.json` at the repository root to add `markdownlint-cli2` and `markdownlint-rule-relative-links` as `devDependencies`; run `npm install` to generate / update `package-lock.json`.
4. Create `.markdownlint.jsonc` at the repository root with the scoped rule set (MD009 with hard-break exception, relative-link plugin enabled, all out-of-scope default rules disabled).
5. Scan all baseline files (`docs/specs/developments/**/*.md`, `docs/testing/workflow/**/*.md`, `CHANGELOG.md`) with `markdownlint-cli2` and `python3 scripts/lint/markdown-heuristic-lint.py`; fix all violations directly or add inline suppressions with reviewer-visible rationale.
6. Create `.github/workflows/markdown-lint.yml` with path-filtered `pull_request` trigger, `npm ci`, `markdownlint-cli2` step, and heuristic script step.
7. Run the full lint check locally against the implementation branch's files to confirm the check exits green.
8. Update `AGENTS.md` with the local-run commands and update `docs/best-practices/1-general.md` with the formatting note.
9. Update `CHANGELOG.md` under `[Unreleased]` with a new entry for this feature.
10. Verify smoke test runbook scenarios manually or via a draft PR CI run.
