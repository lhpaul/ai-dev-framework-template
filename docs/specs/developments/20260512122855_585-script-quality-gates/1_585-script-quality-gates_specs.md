# Script Quality Gates to Prevent Downstream Drift — Spec

---

## Overview

When downstream projects run `sync-template`, they receive workflow scripts verbatim from this template. If the template ships scripts with bugs, automated reviewers in the downstream sync PR flag them as blocking, forcing the downstream maintainer to fix template bugs inside a sync PR. Each downstream fix creates drift from the template and must eventually be re-upstreamed manually or will be silently overwritten by the next sync.

Two recent sync cycles demonstrated the pattern: the v0.26.0 sync required 8 fix commits on `pr-review-loop.sh` across 7+ CodeRabbit rounds, and the v0.26.1 sync found 6 more logic bugs in the same scripts — none of which were caught by the template's own CI before release.

This feature adds a pre-release quality gate that runs CodeRabbit on the production release PR targeting `main`, and adds a lightweight automated test harness for `pr-review-loop.sh` to catch logic regressions before release. ShellCheck CI already exists (added in issue #136) and covers static analysis; this feature addresses the logic-bug gap not covered by ShellCheck.

---

## Use Cases

### Use Case 1: Automated Reviewer Catches Script Logic Bugs Before Release

**Actor**: Release operator preparing a `release/vX.Y.Z` branch and opening the production PR to `main`
**Preconditions**: The prepare-release protocol has opened the production PR to `main`. The PR includes all changes accumulated since the last release, including any modifications to `scripts/development-workflow/pr-review-loop.sh` or other workflow scripts.

**Steps**:
1. The release operator follows the prepare-release protocol (`05-prepare-release-protocol.md`), which runs the automated reviewer loop (CodeRabbit, pr-agent) on the production PR to `main`.
2. CodeRabbit reviews all modified workflow scripts in the production PR and flags any logic bugs found.
3. The operator addresses all blocking findings in the release branch before the production PR is labeled `ready-for-human-review`.
4. The production PR reaches human-ready state only after all automated reviewers return clean.

**Postconditions**: The production release includes no script bugs that CodeRabbit would catch. Downstream projects that sync from this release receive clean scripts.

**Information shown**:
- CodeRabbit review results on the production PR (blocking, advisory, or clean verdict)
- Clear indication that the reviewer loop ran to completion on the release PR

**Actions available**:
- Address blocking findings in the release branch
- Accept advisory findings with explicit disposition if appropriate

**Considerations**:
- The prepare-release protocol already requires running the automated reviewer loop on the production PR. This use case formalizes the expectation that the loop must cover all modified workflow scripts, not only the files changed since the last prepare-release commit.
- If CodeRabbit is not installed on the repository, the reviewer loop reports `skipped` for CodeRabbit; the operator must manually review the scripts or escalate.

---

### Use Case 2: Test Harness Catches pr-review-loop.sh Regressions Before Release

**Actor**: CI system running on a PR that modifies `scripts/development-workflow/pr-review-loop.sh` or its supporting functions in `scripts/development-workflow/workflow-lib.sh`
**Preconditions**: A PR is open against `develop` that modifies `pr-review-loop.sh` or `workflow-lib.sh`. The test harness is present and enabled in CI.

**Steps**:
1. The CI system detects that `pr-review-loop.sh` or `workflow-lib.sh` was modified in the PR.
2. CI runs the test harness, which exercises the key logic paths of `pr-review-loop.sh` using mocked `gh` and `git` calls — no real GitHub API calls or PRs are needed.
3. Each test case verifies a specific behavior within the three targeted logic areas: verdict normalization (`normalize_platform_verdict`), thread-resolution detection (`check_unreplied_rest_comments`), and compare-mode analytics. Future test cases may extend coverage to retry logic, async grace period handling, and other logic paths — those are out of scope for the initial harness.
4. If any test case fails, CI reports the failure with the test name and a description of the expected versus actual behavior.
5. If all test cases pass, CI reports success and the PR can proceed.

**Postconditions**: The PR's changes to `pr-review-loop.sh` have been validated against known-good behavior for all covered logic paths.

**Information shown**:
- Test case names and pass/fail status for each case
- Failure output showing expected versus actual behavior when a test fails

**Actions available**:
- Fix the regression in `pr-review-loop.sh` and push a new commit to re-run CI
- Add a new test case to cover the fixed behavior if it was not previously covered

**Considerations**:
- The harness uses mocked external commands (`gh`, `git`, `curl`). It does not test network behavior or real GitHub API responses.
- The harness targets the logic paths most frequently changed and most frequently the source of downstream bugs: verdict normalization (`normalize_platform_verdict`), thread-resolution detection (`check_unreplied_rest_comments`), and the compare-mode analytics section.
- The harness does not need to achieve complete code coverage. Coverage of the three highest-risk sections is the initial target.
- The harness is a shell script that can be run locally without any additional tooling beyond `bash`.

---

### Use Case 3: Developer Runs the Test Harness Locally Before Opening a PR

**Actor**: Developer who has modified `pr-review-loop.sh` and wants to verify correctness before pushing
**Preconditions**: The developer has the repository checked out locally and has modified `pr-review-loop.sh`.

**Steps**:
1. The developer runs the test harness script directly from the repository root.
2. The harness outputs pass/fail results for each test case.
3. If any test fails, the developer iterates on the fix and re-runs the harness before pushing.

**Postconditions**: The developer has verified their changes do not break any covered behavior before creating a PR.

**Information shown**:
- Test case names and pass/fail status
- Summary: total passed, total failed

**Actions available**:
- Fix the failing behavior and re-run locally
- Push the PR once all tests pass

**Considerations**:
- No additional tooling is required. The harness is a self-contained shell script.
- Running the harness locally does not substitute for CI — CI is the authoritative gate.

---

## Business Rules

- The test harness must pass in CI on any PR that modifies `pr-review-loop.sh` or `workflow-lib.sh`. A harness failure is a blocking CI signal.
- The test harness runs in CI only when `pr-review-loop.sh` or `workflow-lib.sh` is in the PR's changed files. It is not required to run on every PR.
- The test harness must not require external network access. All `gh`, `git`, and `curl` calls within the tested functions must be interceptable by the harness mock layer.
- The prepare-release protocol must document that the automated reviewer loop (including CodeRabbit when available) must run to completion on the production PR before it can be labeled `ready-for-human-review`. This requirement is a process rule — no code change enforces it; it is enforced by the operator following the protocol.
- Each downstream fix applied to a template script during a sync PR must be tracked as a prospective upstream issue. This rule already exists informally in the retrospective protocol; this feature makes it explicit in the prepare-release checklist.
- ShellCheck CI (added in issue #136) is not in scope for this feature — it already covers the static-analysis layer. This feature addresses the logic-bug gap not covered by ShellCheck.

---

## Acceptance Criteria

- [ ] A test harness script exists at `scripts/development-workflow/tests/test-pr-review-loop.sh` (or equivalent path) and is executable without external tooling beyond `bash`.
- [ ] The harness covers at least these three logic areas of `pr-review-loop.sh`: (1) `normalize_platform_verdict` verdict mapping (including `skipped` → `unavailable` in compare mode), (2) `check_unreplied_rest_comments` bot-account exclusion (all `[bot]`-suffixed accounts excluded, not only the primary reviewer), (3) compare-mode analytics: platform config change detection by ordered platform names rather than column count.
- [ ] A CI workflow step (or addition to the existing `shellcheck.yml`) runs the harness on pull requests that modify `pr-review-loop.sh` or `workflow-lib.sh`, and fails the CI run if any test case fails.
- [ ] The harness runs successfully to completion locally using only `bash` (no additional runtime required).
- [ ] The prepare-release protocol (`05-prepare-release-protocol.md`) contains an explicit checklist item requiring the automated reviewer loop — including CodeRabbit when available — to run to completion on the production PR to `main` before the PR is labeled `ready-for-human-review`.
- [ ] The prepare-release protocol contains an explicit checklist item to review open script-bug issues filed from downstream sync retrospectives before cutting the release, so that known bugs can be addressed in the release rather than shipping downstream.
- [ ] The retrospective protocol (`06-retrospective-protocol.md`) or the prepare-release protocol contains an explicit prompt: "Were any template script bugs fixed in a downstream sync PR during this cycle? If so, file a template issue and link it from the downstream fix commit."

---

## Out of Scope (MVP)

- Complete unit test coverage for all of `pr-review-loop.sh` — only the three highest-risk sections are targeted in the initial harness.
- Integration tests that exercise real GitHub API calls or real CodeRabbit review cycles.
- A test harness for scripts other than `pr-review-loop.sh` and `workflow-lib.sh` — those may be addressed in follow-up issues.
- Enforcement tooling that automatically blocks a release if known downstream script bugs exist — the prepare-release checklist item is a process control, not an automated gate.
- Changes to the ShellCheck CI workflow (already correct as shipped in issue #136).
- Any changes to `pr-review-loop.sh` logic itself — the bugs from PR #588 are already fixed; this issue is about the quality gate, not additional logic fixes.
