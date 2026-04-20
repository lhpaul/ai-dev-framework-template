# Markdown Lint for Plan and Spec Docs — Spec

**Depends on**: <!-- none -->

---

## Overview

AI agents and developers contributing spec and plan documents under `docs/specs/developments/` and `docs/testing/workflow/` currently receive no automated feedback on structural defects until a human or bot reviewer flags them in a PR review. Retrospective data from Batch 5 shows that avoidable markdown defects — broken relative links, internally inconsistent acceptance-criteria counts, and incorrect glob patterns in smoke-test instructions — drove high fix-commit ratios (67–83%) on plan PRs, burning CodeRabbit rate-limit budget and extending orchestrator supervision time on every cycle.

This feature adds a lightweight automated markdown lint step that runs in CI on every pull request touching plan and spec documents, catching the most common shape defects before human review begins. The check covers four defect categories derived from the retrospective: broken relative links, trailing whitespace, suspicious glob patterns in instruction blocks, and inconsistent acceptance-criteria (or list-item) count wording within a single document. The same lint stack also catches CHANGELOG trailing-whitespace issues, subsuming the scope of deferred item #178.

---

## Use Cases

### Use Case 1: Contributor Opens a PR That Modifies Plan or Spec Documents

**Actor**: Developer or AI agent (contributor opening a pull request)
**Preconditions**: A pull request is opened or updated that modifies one or more markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`.

**Steps**:
1. Contributor opens or pushes to a pull request with changes to plan or spec markdown files.
2. CI automatically runs the markdown lint check on the changed files.
3. The lint check produces output listing any violations found.
4. CI check passes (green) if no violations are found.
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

**Actions available**:
- Contributor proceeds with the pull request normally; no lint-related action is required when no target markdown files changed.

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

**Actions available**:
- Contributor corrects the broken relative link (fixing the path or creating the missing file) and pushes again to re-run the check.
- Contributor suppresses the rule inline with a tool-specific directive if the link is intentionally a placeholder, subject to normal PR review.

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

**Actions available**:
- Contributor removes the trailing whitespace (manually or via editor/tool) and pushes again to re-run the check.
- Contributor confirms via diff that any intentional two-space hard line breaks are preserved and not stripped.

**Considerations**:
- Intentional two-space trailing spaces (hard line breaks in Markdown) must not be flagged as trailing whitespace; the rule should apply to whitespace-only trailing characters that serve no semantic purpose.
- This use case covers CHANGELOG.md in addition to spec and plan documents, subsuming deferred item #178.

---

### Use Case 5: A Document Contains a Suspicious Glob Pattern in an Instruction Block

**Actor**: Developer or AI agent (contributor)
**Preconditions**: A spec or plan document contains a code block whose surrounding prose refers to matching files in "subdirectories" (or equivalent recursive wording) while the glob itself is a non-recursive pattern like `*.<ext>`.

**Steps**:
1. Contributor opens or updates a PR with a document whose instruction block pairs recursive-language prose (e.g., "in all subdirectories", "recursively") with a non-recursive glob (e.g., `*.sh`).
2. CI runs the markdown lint check.
3. The check detects the prose/glob mismatch in the same document.
4. The check exits red and reports the file, the line of the glob, and the prose excerpt that suggested recursion.

**Postconditions**:
- The PR is blocked (CI red) until the glob is corrected (e.g., `**/*.sh`), the surrounding prose is corrected, or the rule is suppressed inline with a reviewed rationale.

**Information shown**:
- The file path, the line of the offending glob, the prose excerpt that triggered the match, and a suggested recursive pattern.

**Actions available**:
- Contributor replaces the glob with a recursive pattern (e.g., `**/*.sh`), rewrites the prose to remove the recursive phrasing, or suppresses the rule inline with a tool-specific directive and a reviewer-visible rationale.

**Considerations**:
- Detection is heuristic: the check correlates a fixed set of recursive-language cues (e.g., "subdirectories", "recursively", "under the tree") with non-recursive globs in the same document scope. False positives must be suppressible inline, so contributors are never blocked by a heuristic on content that is genuinely non-recursive.
- The heuristic's cue list must be visible in the lint configuration so contributors can understand why a finding fired and extend the cue set over time.

---

### Use Case 6: A Document's Stated Count Disagrees With Its Own List

**Actor**: Developer or AI agent (contributor)
**Preconditions**: A spec or plan document contains prose that names a numeric count (e.g., "4 acceptance criteria", "three steps") while the list immediately following or referenced by that prose has a different number of items.

**Steps**:
1. Contributor opens or updates a PR with a document whose narrative count ("N acceptance criteria", "N use cases", "N steps") disagrees with the count of items in the corresponding list or section.
2. CI runs the markdown lint check.
3. The check detects the mismatch.
4. The check exits red and reports the file, the stated count (with its surrounding phrase), and the actual item count.

**Postconditions**:
- The PR is blocked (CI red) until the stated count is corrected to match the list, the list is corrected to match the stated count, or the rule is suppressed inline with a reviewer-visible rationale.

**Information shown**:
- The file path, the line that contains the narrative count, the phrase used, the actual count found in the referenced list, and the computed disagreement.

**Actions available**:
- Contributor updates either the narrative count or the list length so the two agree, or suppresses the rule inline with a tool-specific directive and a reviewer-visible rationale for an intentional mismatch.

**Considerations**:
- The check targets count disagreements that occur within the same document; it does not attempt to reconcile counts across different documents.
<!-- markdown-heuristic-disable COUNT001 --> <!-- False positive: "4 acceptance criteria" and "four acceptance criteria" here are illustrative examples describing how the check detects narrative count phrases, not actual counts of list items in this document. -->
- Narrative counts may appear as digits (e.g., "4 acceptance criteria") or written-out numerals ("four acceptance criteria"); both forms are checked.
- The check must not fire on narrative uses of numbers that are unrelated to a list (e.g., durations, version numbers); the heuristic must be scoped to count-of-items phrasing, and false positives must be suppressible inline.

---

## Business Rules

- The markdown lint check runs on all modified markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, and on `CHANGELOG.md` on every pull request that touches any of these paths.
- A CI failure due to lint violations is a required status check: the PR cannot proceed to human review until the check passes or the violation is suppressed with a documented inline directive.
- Inline suppressions are permitted and subject to normal PR review; they do not require a separate approval process.
- The check must complete in a reasonable time (under 2 minutes for the current document set) and must not introduce flakiness due to external network dependencies at lint time.
- External URLs in documents are not checked for liveness (network-free lint only).
- The baseline for existing documents is established at the time of implementation: any violations in existing files must be resolved or suppressed as part of the implementation PR so the check is green from day one.
- Heuristic checks (suspicious glob patterns and inconsistent count wording) must be suppressible inline with a tool-specific directive and a reviewer-visible rationale, so contributors are never blocked by a false positive on content that is genuinely correct.
- The cue set used by the suspicious-glob heuristic (recursive-language phrases such as "subdirectories", "recursively", "under the tree") must be declared in the lint configuration and extendable without changing the lint tool itself.

---

## Acceptance Criteria

- [ ] AC1: A CI check runs automatically on every pull request that modifies markdown files under `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`, and exits red when any configured lint rule is violated.
- [ ] AC2: The check detects and reports broken relative links — where a relative link in a markdown file resolves to a file path that does not exist on disk — with the file path, line number, and broken link target shown in the CI output.
- [ ] AC3: The check detects and reports trailing whitespace on lines in spec, plan, and CHANGELOG.md files, with file path and line number shown in the CI output. Intentional two-space trailing spaces used as hard line breaks in Markdown are not flagged.
- [ ] AC4: The check exits green when no violations are present in the changed files.
- [ ] AC5: A pull request that modifies only non-markdown files (or only markdown files outside the three target paths: `docs/specs/developments/`, `docs/testing/workflow/`, and `CHANGELOG.md`) is not blocked by the markdown lint check (either the check does not run, or it passes with a no-files-found result).
- [ ] AC6: Suppressing a rule inline with a tool-specific directive causes the check to exit green for that specific finding.
- [ ] AC7: The check is green from the moment the implementation PR is merged (i.e., any violations in existing baseline documents are resolved or suppressed in the implementation PR itself).
- [ ] AC8: CHANGELOG.md trailing-whitespace violations are caught by the same check, satisfying the scope of deferred item #178.
- [ ] AC9: The check detects and reports suspicious glob patterns — a non-recursive glob (e.g., `*.sh`) in a document whose surrounding prose uses recursive-language cues (e.g., "subdirectories", "recursively") — with the file path, line of the glob, and the triggering prose excerpt shown in the CI output. The rule is suppressible inline on a per-finding basis.
- [ ] AC10: The check detects and reports within-document count disagreements — when a narrative phrase names a count of items ("N acceptance criteria", "N use cases", "N steps", in digits or written-out numerals) that differs from the count of items in the corresponding list or section — with the file path, the line of the narrative count, the stated count, and the actual count shown in the CI output. The rule is suppressible inline on a per-finding basis.

---

## Out of Scope (MVP)

- Checking liveness of external URLs (http/https links) — network dependency introduces flakiness.
- Checking links to in-document anchors.
- Enforcement of markdown lint rules on markdown files outside the three target paths: `docs/specs/developments/`, `docs/testing/workflow/`, and `CHANGELOG.md` (e.g., README files, protocol docs).
- Pre-commit hook integration (this may be added in a follow-on item; the CI check is the primary gate).
- Auto-fixing violations without human review of the fix.
