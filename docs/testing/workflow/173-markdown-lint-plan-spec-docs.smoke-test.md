# Smoke Test Runbook: Markdown Lint for Plan and Spec Docs

**Feature**: Markdown Lint for Plan and Spec Docs (#173)
**Spec**: [docs/specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md](../../specs/developments/20260416180000_173-markdown-lint-plan-spec-docs/1_173-markdown-lint-plan-spec-docs_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation PR has been merged into `develop`
- [ ] You have a local checkout of `develop` (or a fresh branch from `develop`)
- [ ] Node.js 20+ is available locally (for running `markdownlint-cli2`)
- [ ] Python 3.8+ is available locally (for running `markdown-heuristic-lint.py`)
- [ ] GitHub repository access to open pull requests and read CI check results

---

## Test Data

| Item | Value |
|---|---|
| Target paths | `docs/specs/developments/`, `docs/testing/workflow/`, `CHANGELOG.md` |
| Lint config | `.markdownlint.jsonc` at repo root |
| Heuristic script | `scripts/lint/markdown-heuristic-lint.py` |
| Workflow file | `.github/workflows/markdown-lint.yml` |
| Inline suppression (markdownlint) | `<!-- markdownlint-disable MD009 -->` (or the relevant rule code) |
| Inline suppression (heuristic) | `<!-- markdown-heuristic-disable GLOB001 -->` or `<!-- markdown-heuristic-disable COUNT001 -->` |

---

## Smoke Test Steps

### Step 1: Verify the markdown lint CI check exists on a spec/plan PR

**Maps to**: AC1

1. Open (or find) any open pull request that modifies a file under `docs/specs/developments/` or `docs/testing/workflow/`.
2. Navigate to the PR's **Checks** tab on GitHub.
3. Confirm a check named `Markdown Lint` (or similar) appears in the list.

**Expected result**: The `Markdown Lint` CI check is present on the PR checks list.

---

### Step 2: PR with trailing whitespace — check fails

**Maps to**: AC1, AC3

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-trailing-ws develop
   ```
2. Add a trailing space to any line in a file under `docs/specs/developments/` (e.g., append a space to a line in the spec file).
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits red. The check output shows the file path, line number, and rule description (`MD009` or equivalent) for the trailing-whitespace violation.

---

### Step 3: Hard line break is not flagged as trailing whitespace

**Maps to**: AC3

1. In the same test branch (or a new one), add a line ending with exactly two spaces (intentional Markdown hard line break) to a spec or plan file.
2. Commit and push.
3. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check does not flag the two-space hard line break as a trailing-whitespace violation (the check exits green if no other violations are present).

---

### Step 4: PR with a broken relative link — check fails

**Maps to**: AC1, AC2

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-broken-link develop
   ```
2. Add a relative link pointing to a nonexistent file to any spec or plan document:
   ```markdown
   See [nonexistent file](../../nonexistent-doc.md) for details.
   ```
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits red. The output shows the file path, line number, and the broken relative link target.

---

### Step 5: PR with no violations — check passes

**Maps to**: AC4

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-clean develop
   ```
2. Make a trivial, lint-clean change to a file under `docs/specs/developments/` (e.g., add a line with no trailing whitespace, no broken links).
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits green.

---

### Step 6: PR touching only non-target files — check passes or is skipped

**Maps to**: AC5

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-non-target develop
   ```
2. Modify only a file outside the three target paths (e.g., `docs/project/1-business-domain.md` or a shell script).
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the CI checks to complete.

**Expected result**: The `Markdown Lint` CI check either does not appear (path-filtered out) or appears and exits green with a "no target files changed" message. The PR is not blocked by the lint check.

---

### Step 7: Inline suppression silences a violation

**Maps to**: AC6

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-suppression develop
   ```
2. Add a trailing-whitespace line to a spec file.
3. On the same line or the line above the violation, add the markdownlint inline suppression:
   ```markdown
   <!-- markdownlint-disable-next-line MD009 -->
   This line has a trailing space intentionally.   
   ```
4. Commit and push, then open a draft PR targeting `develop`.
5. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits green for the suppressed finding. The suppression directive is visible in the diff.

---

### Step 8: CHANGELOG.md trailing whitespace is caught

**Maps to**: AC8

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-changelog-ws develop
   ```
2. Add a trailing space to a line in `CHANGELOG.md`.
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits red and reports the trailing-whitespace violation in `CHANGELOG.md`.

---

### Step 9: Suspicious glob pattern heuristic fires

**Maps to**: AC9

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-glob-heuristic develop
   ```
2. Add the following content to a file under `docs/specs/developments/` (e.g., append to the spec file). The prose should contain "subdirectories" (or another recursive-language cue) while the code block contains a non-recursive glob such as `*.sh` — for example, a paragraph reading "Run the linter on all shell scripts in subdirectories:" followed by a bash code block containing `lint *.sh`.
   (Note: the prose says "subdirectories" but `lint *.sh` only matches files in the current directory, not subdirectories — making this a genuine non-recursive pattern.)
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits red. The output shows the file path, the line of the glob pattern, the triggering prose excerpt (containing "subdirectories"), and rule code `GLOB001`.

---

### Step 10: Within-document count disagreement heuristic fires

**Maps to**: AC10

1. Create a test branch from `develop`:
   ```bash
   git checkout -b smoke-test/173-count-heuristic develop
   ```
2. Add the following content to a file under `docs/specs/developments/`:
   ```markdown
   There are 4 acceptance criteria:

   - AC1: First criterion
   - AC2: Second criterion
   - AC3: Third criterion
   ```
   (The prose says "4" but only 3 items follow.)
3. Commit and push, then open a draft PR targeting `develop`.
4. Wait for the `Markdown Lint` CI check to complete.

**Expected result**: The `Markdown Lint` CI check exits red. The output shows the file path, the line of the count phrase, the stated count (4), and the actual count (3), with rule code `COUNT001`.

---

### Step 11: Verify the implementation PR itself is green (baseline check)

**Maps to**: AC7

1. Navigate to the closed implementation PR for issue #173 on GitHub.
2. Check the `Markdown Lint` CI check result on that PR.

**Expected result**: The `Markdown Lint` CI check was green on the implementation PR, confirming no unresolved baseline violations exist in the merged files.

---

### Last Step: Clean up smoke test branches

1. Delete all `smoke-test/173-*` branches created during this runbook (locally and remotely).
2. Confirm no open smoke-test PRs remain.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: A CI check runs on PRs touching target markdown paths and exits red when a configured rule is violated.
- [ ] AC2: Broken relative links are detected and reported with file path, line number, and broken link target.
- [ ] AC3: Trailing whitespace is detected and reported; intentional two-space hard line breaks are not flagged.
- [ ] AC4: The check exits green when no violations are present.
- [ ] AC5: PRs touching only non-target files are not blocked by the markdown lint check.
- [ ] AC6: An inline suppression directive causes the check to exit green for that specific finding.
- [ ] AC7: The check was green on the implementation PR itself (no unresolved baseline violations).
- [ ] AC8: Trailing whitespace in `CHANGELOG.md` is caught by the same check.
- [ ] AC9: Suspicious glob patterns (non-recursive glob with recursive prose) are detected and reported with file path, glob line, and triggering prose excerpt (GLOB001).
- [ ] AC10: Within-document count disagreements are detected and reported with file path, count-phrase line, stated count, and actual count (COUNT001).

---

## Seed Data Reference

None — this feature operates on repository files; no database seed data is required.

| Entity | Scenario | How to load |
|---|---|---|
| Spec/plan files | Files under `docs/specs/developments/` already present in the repository | Already in repository; no additional loading needed |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Markdown Lint` check does not appear on a PR | PR does not touch any path in the workflow's path filter | Confirm the PR modifies at least one file under `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md` |
| `markdownlint-cli2` not found in CI | `npm ci` step failed or `package.json` is missing the dependency | Check the workflow logs for the `npm ci` step; verify `package.json` lists `markdownlint-cli2` in `devDependencies` |
| Heuristic script exits with `python3: command not found` | Runner image lacks Python 3 | Add a `setup-python` step in the workflow before the heuristic script step |
| False positive on a relative link that intentionally does not resolve | The lint tool resolves the link relative to the file and the target is absent | Add an inline `<!-- markdownlint-disable-next-line relative-links -->` suppression with a rationale comment |
| Count heuristic fires on a version number or duration phrase | Regex too broad | Check whether the phrase matches count-of-items keywords ("acceptance criteria", "use cases", "steps", "items"); if it is a genuine false positive, add `<!-- markdown-heuristic-disable COUNT001 -->` on the triggering line |

---

## Known Limitations

- The suspicious-glob heuristic is correlation-based: it matches recursive-language cues and non-recursive globs within the same document, not necessarily in the same paragraph. Inline suppression is always available for confirmed false positives.
- The count-disagreement heuristic looks ahead at most 30 lines from the count phrase to find the corresponding list. Lists separated from their count phrase by large blocks of text may not be correlated correctly.
- External URLs (http/https) are not checked for liveness (by design — network-free lint only).
