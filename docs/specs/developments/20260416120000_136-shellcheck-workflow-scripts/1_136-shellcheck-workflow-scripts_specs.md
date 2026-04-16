# ShellCheck Static Analysis for Workflow Scripts — Spec

**Depends on**: <!-- none -->

---

## Guiding principle (important)

This stage is intentionally **product-focused**:

- Write **user-facing behavior**, permissions, UX rules, and acceptance criteria.
- Avoid prescribing **implementation details** (database tables/columns, specific endpoints, file paths, class names, or migration design). Those belong in the **Implementation Plan** stage.
- If a technical constraint matters to the product (e.g., "an agent may belong to multiple broker companies"), express it as a **product requirement** without naming tables.

## Overview

Developers and AI agents contributing shell scripts under `scripts/development-workflow/` currently receive no automated static analysis feedback until a human or bot reviewer flags an issue in a PR review. Retrospective data shows that common shell scripting mistakes (unquoted variables, missing error handling, incorrect `set -e` interactions with pipeline commands) regularly produce high fix-commit ratios that trigger CodeRabbit's auto-pause and extend review cycles.

This feature adds automated ShellCheck static analysis that runs on pull requests touching shell script files, giving contributors immediate feedback on detectable issues before human review begins.

---

## Use Cases

### Use Case 1: Contributor Opens a PR That Modifies Shell Scripts

**Actor**: Developer or AI agent (contributor opening a pull request)
**Preconditions**: A pull request is opened or updated that modifies one or more `.sh` files under `scripts/development-workflow/`.

**Steps**:
1. Contributor opens or pushes to a pull request with changes to shell scripts.
2. CI automatically runs ShellCheck on all `.sh` files under `scripts/development-workflow/`.
3. ShellCheck produces output listing any warnings or errors found.
4. CI check passes (green) if no issues at or above the configured severity threshold are found.
5. CI check fails (red) if one or more issues at or above the threshold are found.

**Postconditions**:
- If the check passes: the ShellCheck CI status check is green; the contributor can proceed to human review.
- If the check fails: the ShellCheck CI status check is red; the contributor sees the specific file, line, and ShellCheck error code for each issue.

**Information shown**:
- For each finding: file path, line number, ShellCheck error/warning code, and human-readable description.
- A summary of total findings count (pass or fail).

**Actions available**:
- Contributor can fix the flagged issues in their branch and push again to re-run the check.
- Contributor can suppress a specific finding inline (with a `# shellcheck disable=SCxxxx` directive) when the check is a known false positive, without suppressing the entire file.

**Considerations**:
- The check must not run on PRs that touch only non-shell files (to avoid unnecessary CI noise), or if it does run, it must exit green when no shell files are changed.
- The check must handle the case where no `.sh` files exist under the target path (exit green).
- The check must not block PRs for `info` or `style`-level ShellCheck findings; only findings at or above `warning` severity are blocking.

---

### Use Case 2: Contributor Opens a PR That Does Not Modify Shell Scripts

**Actor**: Developer or AI agent
**Preconditions**: A pull request is opened or updated that does not touch any `.sh` files under `scripts/development-workflow/`.

**Steps**:
1. Contributor opens or pushes to a pull request with no shell script changes.
2. The ShellCheck CI check either does not run (if path-filtered) or runs and finds no files to analyze.

**Postconditions**:
- CI does not fail due to ShellCheck on a PR that has no shell changes.

**Information shown**:
- Either no ShellCheck check visible, or a check marked as skipped/passed with a message indicating no shell files were changed.

**Considerations**:
- Avoids adding friction to PRs that have nothing to do with shell scripts.

---

### Use Case 3: Existing Scripts Have Known Acceptable Patterns

**Actor**: Maintainer (human approving suppression decisions)
**Preconditions**: A ShellCheck finding is a known false positive or an intentionally accepted pattern in the codebase (e.g., a `source` of a dynamically constructed path that ShellCheck cannot follow).

**Steps**:
1. Maintainer or contributor identifies a ShellCheck finding that should not be treated as a defect.
2. Contributor applies an inline suppression directive or, for file-wide patterns, a `.shellcheckrc` configuration entry.
3. The suppression is reviewed in the PR like any other code change.

**Postconditions**:
- The CI check passes for the affected file.
- The suppression is documented as a code-level comment or configuration entry, making the decision visible to future reviewers.

**Information shown**:
- The suppression directive is visible in the diff.

**Considerations**:
- Blanket suppression of entire files (excluding a file from ShellCheck analysis entirely) is out of scope for this feature. Suppressions should be as targeted as possible — prefer inline directives scoped to specific lines over project-wide rules.
- A `.shellcheckrc` file for project-wide suppression of specific error codes that are structurally unfixable in this repository (e.g., SC1091 for unresolvable `source` paths) is acceptable and within scope, provided each suppressed code includes a comment explaining the reason.

---

## Business Rules

- ShellCheck analysis runs on all `*.sh` files under `scripts/development-workflow/` — no individual files are permanently excluded unless suppressed via an inline directive or `.shellcheckrc`.
- The severity threshold for blocking the CI check is **warning** level and above (ShellCheck severity: `error` and `warning` block; `info` and `style` do not block).
- A CI failure due to ShellCheck findings is a required status check: the PR cannot be merged until the check passes or the finding is suppressed with a documented inline directive.
- Inline suppression directives (`# shellcheck disable=SCxxxx`) are permitted and subject to the same PR review process as other code changes; they do not require a separate approval process.
- The ShellCheck check must complete in a reasonable time (under 2 minutes for the current script set) and must not introduce flakiness due to external network dependencies at analysis time.
- The baseline for existing scripts is established at the time of implementation: any existing warnings that cannot be immediately fixed must be suppressed with inline directives as part of the implementation PR, so the check is green from day one.

---

## Acceptance Criteria

- [ ] A CI check named (or clearly labeled) `shellcheck` (or equivalent) runs automatically on every pull request that modifies `.sh` files under `scripts/development-workflow/`.
- [ ] The check exits red and displays specific findings (file, line, code, message) when any `error` or `warning`-level ShellCheck issue is present in the changed or baseline scripts.
- [ ] The check exits green when no `error` or `warning`-level findings are present.
- [ ] A pull request that modifies only non-shell files is not blocked by the ShellCheck check (either the check does not run, or it passes with a no-files-found result).
- [ ] Suppressing a finding with an inline `# shellcheck disable=SCxxxx` directive causes the check to exit green for that finding.
- [ ] The check is green from the moment the implementation PR is merged (i.e., any existing warnings in the baseline scripts are addressed or suppressed in the implementation PR itself).
- [ ] A `.shellcheckrc` file (if used) is committed to the repository and lists only project-wide suppressed codes with a comment explaining the reason for each suppression.

---

## Out of Scope (MVP)

- Running ShellCheck on shell scripts outside of `scripts/development-workflow/` (e.g., scripts in other directories, CI workflow files themselves).
- Auto-fixing ShellCheck findings automatically without human review of the fix.
- Enforcing `info` or `style`-level ShellCheck findings as blocking.
- Pre-commit hook integration (this may be added in a follow-on item; the CI check is the primary gate).
- Shellcheck analysis as part of the local developer `npm run lint` or equivalent command (advisory only; CI is the authoritative gate).
- Reporting ShellCheck findings as inline PR comments (findings appear in CI job logs; inline annotation is a future enhancement).

