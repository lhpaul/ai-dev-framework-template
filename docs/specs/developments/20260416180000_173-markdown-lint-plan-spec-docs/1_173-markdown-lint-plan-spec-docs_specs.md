# Markdown Lint for Plan and Spec Docs — Spec

**Depends on**: <!-- none -->

---

## Guiding principle (important)

This stage is intentionally **product-focused**:

- Write **user-facing behavior**, permissions, UX rules, and acceptance criteria.
- Avoid prescribing **implementation details** (database tables/columns, specific endpoints, file paths, class names, or migration design). Those belong in the **Implementation Plan** stage.
- If a technical constraint matters to the product (e.g., "an agent may belong to multiple broker companies"), express it as a **product requirement** without naming tables.

## Overview

AI agents and developers contributing spec and plan documents under `docs/specs/developments/` and `docs/testing/workflow/` currently receive no automated feedback on structural defects until a human or bot reviewer flags them in a PR review. Retrospective data from Batch 5 shows that avoidable markdown defects — broken relative links, internally inconsistent acceptance-criteria counts, and incorrect glob patterns in smoke-test instructions — drove high fix-commit ratios (67–83%) on plan PRs, burning CodeRabbit rate-limit budget and extending orchestrator supervision time on every cycle.

This feature adds a lightweight automated markdown lint step that runs in CI on every pull request touching plan and spec documents, and optionally as a pre-commit hook, to catch the most common shape defects before human review begins. The same lint stack will also catch CHANGELOG trailing-whitespace issues, subsuming the scope of deferred item #178.

---

## Use Cases

### Use Case 1: Contributor Opens a PR That Modifies Plan or Spec Documents

**Actor**: Developer or AI agent (contributor opening a pull request)
**Preconditions**: A pull request is opened or updated that modifies one or more markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`.

**Steps**:
1. Contributor opens or pushes to a pull request with changes to plan or spec markdown files.
2. CI automatically runs the markdown lint check on the changed files.
3. The lint check produces output listing any violations found.
4. CI check passes (green) if no violations above the configured severity threshold are found.
5. CI check fails (red) if one or more violations are found, displaying the specific file, line, and rule violation for each issue.

**Postconditions**:
- If the check passes: the markdown lint CI status is green; the contributor can proceed to human review.
- If the check fails: the markdown lint CI status is red; the contributor sees the exact file, line, and description for each violation.

**Information shown**:
- For each finding: file path, line number, rule code, and human-readable description.
- A summary of total findings (pass or fail).

**Actions available**:
- Contributor fixes the flagged issues in their branch and pushes again to re-run the check.
- Contributor can suppress a specific rule inline (with a tool-specific directive) when the check is a confirmed false positive, without suppressing the entire file.

**Considerations**:
- The check must not run on PRs that touch only non-markdown files (to avoid unnecessary CI noise), or if it does run, it must exit green when no target markdown files are changed.
- The check must handle the case where no markdown files exist under the target paths (exit green).
- Inline rule suppressions must be visible in the diff and are subject to normal PR review.

---

### Use Case 2: Contributor Opens a PR That Does Not Modify Plan or Spec Documents

**Actor**: Developer or AI agent
**Preconditions**: A pull request is opened or updated that does not touch any markdown files under the three target paths (`docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`).

**Steps**:
1. Contributor opens or pushes to a pull request with no changes to spec or plan markdown files.
2. The markdown lint CI check either does not run (if path-filtered) or runs and finds no files to analyze.

**Postconditions**:
- CI does not fail due to markdown lint on a PR that has no target markdown changes.

**Information shown**:
- Either no lint check visible, or a check marked as skipped/passed indicating no target files were changed.

**Considerations**:
- Avoids adding friction to PRs that have nothing to do with spec or plan documents.

---

### Use Case 3: A Document Contains a Relative Link That Does Not Resolve

**Actor**: Developer or AI agent (contributor)
**Preconditions**: A spec or plan document contains a relative link (e.g., `../../some-doc.md`) that points to a file path that does not exist from the source document's directory.

**Steps**:
1. Contributor opens or updates a PR with a document containing the broken relative link.
2. CI runs the markdown lint check.
3. The check detects that the linked file does not exist at the resolved path.
4. The check exits red and reports the broken link with file, line, and the unresolvable path.

**Postconditions**:
- The PR is blocked (CI red) until the link is corrected.

**Information shown**:
- The broken link, the source file path, and the resolved (missing) target path.

**Considerations**:
- The check validates that the target file exists on disk relative to the source document's directory; it does not make HTTP requests.
- Links to anchors within the same document are out of scope for broken-link detection.
- External URLs (http/https) are not checked for liveness (to avoid flakiness from network dependencies).

---

### Use Case 4: A Document Contains Trailing Whitespace

**Actor**: Developer or AI agent (contributor)
**Preconditions**: A spec, plan, or CHANGELOG markdown file contains one or more lines with trailing whitespace characters.

**Steps**:
1. Contributor opens or updates a PR with a file containing trailing whitespace.
2. CI runs the markdown lint check.
3. The check detects trailing whitespace.
4. The check exits red and reports the specific lines.

**Postconditions**:
- The PR is blocked (CI red) until the trailing whitespace is removed.

**Information shown**:
- File path, line number, and rule description for each trailing-whitespace violation.

**Considerations**:
- Intentional two-space trailing (hard line breaks in Markdown) must not be flagged as trailing whitespace; the rule should apply to whitespace-only trailing characters that serve no semantic purpose.
- This use case covers CHANGELOG.md in addition to spec and plan documents, subsuming deferred item #178.

---

## Business Rules

- The markdown lint check runs on all modified markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, and on `CHANGELOG.md` on every pull request that touches any of these paths.
- A CI failure due to lint violations is a required status check: the PR cannot proceed to human review until the check passes or the violation is suppressed with a documented inline directive.
- Inline suppressions are permitted and subject to normal PR review; they do not require a separate approval process.
- The check must complete in a reasonable time (under 2 minutes for the current document set) and must not introduce flakiness due to external network dependencies at lint time.
- External URLs in documents are not checked for liveness (network-free lint only).
- The baseline for existing documents is established at the time of implementation: any violations in existing files must be resolved or suppressed as part of the implementation PR so the check is green from day one.

---

## Acceptance Criteria

- [ ] AC1: A CI check runs automatically on every pull request that modifies markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`, and exits red when any configured lint rule is violated.
- [ ] AC2: The check detects and reports broken relative links — where a relative link in a markdown file resolves to a file path that does not exist on disk — with the file path, line number, and broken link target shown in the CI output.
- [ ] AC3: The check detects and reports trailing whitespace on lines in spec, plan, and CHANGELOG.md files, with file path and line number shown in the CI output.
- [ ] AC4: The check exits green when no violations are present in the changed files.
- [ ] AC5: A pull request that modifies only non-markdown files (or only markdown files outside the three target paths: `docs/specs/developments/`, `docs/testing/workflow/`, and `CHANGELOG.md`) is not blocked by the markdown lint check (either the check does not run, or it passes with a no-files-found result).
- [ ] AC6: Suppressing a rule inline with a tool-specific directive causes the check to exit green for that specific finding.
- [ ] AC7: The check is green from the moment the implementation PR is merged (i.e., any violations in existing baseline documents are resolved or suppressed in the implementation PR itself).
- [ ] AC8: CHANGELOG.md trailing-whitespace violations are caught by the same check, satisfying the scope of deferred item #178.

---

## Out of Scope (MVP)

- Checking glob-pattern correctness in instruction blocks (whether `*.sh` should be `**/*.sh`); this requires semantic understanding of the surrounding prose and is deferred.
- Checking internal acceptance-criteria count wording consistency (e.g., "4 acceptance criteria" vs. "5" in the same document); detecting this reliably without false positives requires deeper NLP and is deferred.
- Checking liveness of external URLs (http/https links) — network dependency introduces flakiness.
- Checking links to in-document anchors.
- Enforcement of markdown lint rules on markdown files outside the three target paths: `docs/specs/developments/`, `docs/testing/workflow/`, and `CHANGELOG.md` (e.g., README files, protocol docs).
- Pre-commit hook integration (this may be added in a follow-on item; the CI check is the primary gate).
- Auto-fixing violations without human review of the fix.

---

## Open Questions

<!-- All questions answered from issue brief and retrospective analysis. Section retained for completeness but no open questions remain. -->
