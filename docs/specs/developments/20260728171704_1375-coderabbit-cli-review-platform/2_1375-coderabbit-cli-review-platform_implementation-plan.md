# Add CodeRabbit CLI as Optional Step 7 Review Platform — Implementation Plan

**Spec**: [1_1375-coderabbit-cli-review-platform_specs.md](1_1375-coderabbit-cli-review-platform_specs.md)
**Smoke test runbook**: [1375-coderabbit-cli-review-platform.smoke-test.md](../../../testing/workflow/1375-coderabbit-cli-review-platform.smoke-test.md)

---

## Summary

**Approach**: Add a `coderabbit-cli` Step 7 platform that runs the local
CodeRabbit CLI in agent mode against the PR base branch, normalizes CLI output
into the existing `pr-review-loop.sh` result contract, and keeps the existing
CodeRabbit GitHub App platform unchanged. The implementation should mirror the
Haystack companion-script pattern: a dedicated CLI wrapper owns availability,
auth, rate-limit, and output parsing; `pr-review-loop.sh` only dispatches and
aggregates stable `RESULT=` records.

**Estimated complexity**: M

**Rationale**: The change is limited to workflow shell tooling, config docs,
and tests, but it is parser-risk because CLI JSON and error output must be
mapped conservatively. No product runtime, database, or UI changes are needed.

**Dependencies**: CodeRabbit CLI must be installed and authenticated only for
live smoke execution. Missing install or auth must be treated as
`RESULT=skipped`, never `RESULT=clean`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `365bcdb` |
| Template fit | `grep -n "is_template" .ai-dev-workflow.yaml` | `template.is_template: true`; spec is generic workflow tooling and fits this repository |
| Tracker state | `gh issue view 1375 --json projectItems` | Issue #1375 was `Spec Ready` before plan work began |
| Existing platform list | `sed -n '33,49p' .ai-dev-workflow.yaml` | Supported list names `coderabbit` App but not `coderabbit-cli` |
| Existing dispatch | `rg -n "bot_login_for_platform|run_platform_review|run_haystack_review|run_coderabbit_review" scripts/development-workflow/pr-review-loop.sh` | App `coderabbit` and companion-style `haystack` paths exist |
| Existing companion contract | `sed -n '1,90p' scripts/development-workflow/haystack-reviewer.sh` | Companion emits `RESULT=clean\|needs_fixes\|skipped` with counts and reasons |
| Current CodeRabbit CLI docs | `npx ctx7@latest library "CodeRabbit CLI" "CodeRabbit CLI review command agent mode base branch rate limit output"` then `npx ctx7@latest docs /websites/coderabbit_ai "CodeRabbit CLI review command agent mode base branch rate limit output"` | Docs show `cr --agent --base develop`, `coderabbit review --agent --base main`, structured JSON in agent mode, and recent CLI rate-limit notes |
| Bounded batch context | `$run-items 1201 1375` prelude plus `gh pr list --state open --base develop ...` | Exact batch is `1201,1375`; no open PR for #1375 existed at plan start |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `scripts/development-workflow/coderabbit-cli-reviewer.sh`.
  The script must use the existing shell contract style: Bash, parseable
  `KEY=value` stdout, diagnostics on stderr, and no secrets in output.
- [ ] Validate positional inputs and resolve the target repo/base branch before
  shelling out to the CLI. Use `gh pr view <number> --json baseRefName,headRefName`
  when the PR number is available so the CLI reviews against the actual PR base.
- [ ] Prefer `cr --agent --base <base>` when `cr` is installed. Fall back to
  `coderabbit review --agent --base <base>` only when `cr` is absent and
  `coderabbit` is available.
- [ ] Emit the standard companion output:
  - `RESULT=clean|needs_fixes|skipped|escalate`
  - `PLATFORM=coderabbit-cli`
  - `PR_NUMBER=<number>`
  - `BRANCH=<head branch>`
  - `FIX_AGENT=<reviewer_for_branch output from pr-review-loop.sh>`
  - `COMMENT_COUNT=<n>`
  - `BLOCKING_COUNT=<n>`
  - `SUGGESTION_COUNT=<n>`
  - `REASON=<token>` when skipped or escalated by policy
  - optional `DISPLAY_RESULT=<token>` for summaries
- [ ] Map output conservatively:
  - No blocking findings: `RESULT=clean`, exit `0`.
  - Any blocking finding: `RESULT=needs_fixes`, exit `1`.
  - Missing CLI, missing auth, unsupported command, invalid JSON, or ambiguous
    output: `RESULT=skipped`, exit `3`, with a specific `REASON`.
  - Rate limit with warn policy: `RESULT=skipped`, exit `3`,
    `REASON=rate_limited`, and `DISPLAY_RESULT=rate_limited`.
  - Rate limit with strict policy: `RESULT=escalate`, exit `2`,
    `REASON=rate_limited`.
- [ ] Add a timeout budget controlled by `CODERABBIT_CLI_REVIEW_TIMEOUT`
  with a script flag override `--timeout <seconds>`.
- [ ] Add a configurable rate-limit policy read in this order:
  `CODERABBIT_CLI_RATE_LIMIT_POLICY`, then
  `review.coderabbit_cli.rate_limit_policy` from `.ai-dev-workflow.yaml`, then
  default `warn`. Allowed values are `warn` and `strict`.

### Review Loop Integration

- [ ] Update `scripts/development-workflow/pr-review-loop.sh` to dispatch
  `coderabbit-cli` separately from the existing `coderabbit` GitHub App path.
- [ ] Keep `bot_login_for_platform coderabbit` unchanged. Add
  `bot_login_for_platform coderabbit-cli` returning an empty value because the
  CLI does not create GitHub review threads under a bot identity.
- [ ] Add `coderabbit-cli` to help text, supported-platform comments, and any
  branch/status summary normalization paths that enumerate known platforms.
- [ ] Ensure `skipped` from `coderabbit-cli` participates in the existing
  aggregate policy: all clean or skipped platforms make the aggregate clean,
  but the per-platform summary must still show why the CLI did not run.
- [ ] Ensure `RESULT=escalate` from strict rate-limit policy short-circuits the
  aggregate the same way other platform escalation paths do.

### Configuration

- [ ] Update `.ai-dev-workflow.yaml` comments to list `coderabbit-cli` as a
  supported Step 7 platform independent from `coderabbit`.
- [ ] Document the optional config block without enabling it by default:

  ```yaml
  review:
    coderabbit_cli:
      rate_limit_policy: warn
  ```

- [ ] Do not change the template default `review.on_draft.github` or
  `review.on_ready.github` selections. Users opt in by adding
  `coderabbit-cli` to one of those lists.

### Documentation

- [ ] Update `docs/workflow/development-workflow/integrations/coderabbit.md`
  with a distinct CodeRabbit CLI Step 7 path, prerequisites, expected commands,
  result mapping, rate-limit behavior, and the difference from the GitHub App.
- [ ] Update `docs/workflow/development-workflow/integrations/pr-review-platform.md`
  to list `coderabbit-cli`, describe skipped/unavailable behavior, and clarify
  that skipped is not evidence of a successful fresh review.
- [ ] Update `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  only where platform enumeration or summary language needs to include a CLI
  platform that may produce no GitHub bot comment.
- [ ] Update `scripts/development-workflow/README.md` usage examples and
  supported platform descriptions.
- [ ] Update `REVIEW.md` CodeRabbit CLI guidance if the implementation changes
  the distinction between optional pre-push local review and configured Step 7
  review.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` with:
  `- **CodeRabbit CLI review platform** (#1375): Add an optional Step 7 CodeRabbit CLI reviewer with explicit skipped and rate-limit handling.`

---

## Testing Strategy

**Test types**: Unit / Integration / Smoke / Manual

**Key scenarios to test**:

1. CLI installed, authenticated, and returns no blocking findings: maps to
   Acceptance Criteria 1, 2, and 4.
2. CLI returns at least one blocking finding: maps to Acceptance Criteria 2 and
   4.
3. CLI is missing or unauthenticated: maps to Acceptance Criteria 3 and 7.
4. CLI output indicates rate limiting with warn policy: maps to Acceptance
   Criteria 4 and 5.
5. CLI output indicates rate limiting with strict policy: maps to Acceptance
   Criteria 4 and 6.
6. `pr-review-loop.sh --platform coderabbit-cli` dispatches the new companion
   and preserves existing App behavior for `--platform coderabbit`: maps to
   Acceptance Criteria 1 and 2.

**Smoke test runbook**:
`docs/testing/workflow/1375-coderabbit-cli-review-platform.smoke-test.md`

**Regression suite**:

- [ ] Add `scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`
  with mocked `cr`, `coderabbit`, and `gh` binaries.
- [ ] Extend the existing `pr-review-loop.sh` harness tests or add a focused
  dispatch test to prove `coderabbit-cli` is accepted and `coderabbit` remains
  unchanged.
- [ ] Include `shellcheck` coverage for the new shell script and test harness.

### Parser-risk addendum

This plan is parser-risk because the companion script parses CLI JSON and
structured stderr/stdout into workflow result tokens.

**Edge-case enumeration**:

- Valid JSON with an empty findings array must map to clean.
- Valid JSON with one explicit blocking severity must map to needs fixes.
- Valid JSON with advisory-only findings must map to clean with non-zero
  suggestion count.
- Valid JSON with missing or renamed findings fields must map to skipped,
  not clean.
- Plain text containing `rate limit`, `rate-limit`, `too many requests`, or
  `HTTP 429` must map to `REASON=rate_limited`.
- Plain text containing those phrases inside a non-error finding body must not
  override a valid parsed findings result.
- Empty output with zero exit must map to skipped, not clean.
- Non-zero exit with valid completed JSON must parse the JSON instead of
  automatically classifying unavailable.
- Non-zero exit with invalid or empty output must map to skipped.
- Multiple findings in one payload must add blocking and suggestion counts
  independently.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`
  must include one test for each edge case above.
- A dispatch test must assert:
  - `--platform coderabbit-cli` calls the new companion path.
  - `--platform coderabbit` still calls the existing GitHub App path.
  - `bot_login_for_platform coderabbit-cli` returns empty.

**Suppression semantics**: Not applicable. This feature does not add inline
or directive-based suppression.

---

## Seed Data

No database or application seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock CLI JSON | Clean, blocking, advisory, malformed, and rate-limited payloads | `scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh` |
| Mock GitHub PR metadata | PR number, base branch, and head branch for dispatch tests | Test harness temporary files |

---

## Documentation Updates

- [ ] `.ai-dev-workflow.yaml` — document `coderabbit-cli` and rate-limit policy.
- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` —
  document CLI Step 7 setup, usage, and distinction from CodeRabbit App.
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md`
  — document result semantics and platform support.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — update platform enumeration and evidence expectations when needed.
- [ ] `scripts/development-workflow/README.md` — update helper usage docs.
- [ ] `REVIEW.md` — update CodeRabbit CLI reviewer guidance if implementation
  changes its current optional/pre-push description.
- [ ] `CHANGELOG.md` — add the #1375 Unreleased entry.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| CodeRabbit CLI JSON schema differs by version | Med | Med | Parse conservatively, fixture multiple shapes, and map ambiguous output to skipped |
| Rate-limit text appears in a real finding body | Low | Med | Prefer parsed JSON findings over text fallback when JSON is valid |
| CLI path accidentally changes App behavior | Low | High | Keep `coderabbit` and `coderabbit-cli` dispatch cases separate and test both |
| Missing auth is mistaken for a clean review | Med | High | Missing auth/unavailable states must exit skipped and include a reason |
| Strict policy blocks too aggressively | Low | Med | Default to warn and require explicit strict policy opt-in |

---

## Code Samples

No production code samples are included in this plan. Implementation details
belong in the implementation PR.

---

## Implementation Order

1. Add `scripts/development-workflow/coderabbit-cli-reviewer.sh` with input
   validation, command discovery, timeout handling, rate-limit policy loading,
   JSON parsing, and stable key-value output.
2. Add `scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`
   with mocked CLI and GitHub commands for every parser-risk edge case.
3. Update `scripts/development-workflow/pr-review-loop.sh` to dispatch
   `coderabbit-cli`, preserve `coderabbit`, and include the new platform in
   summary/help enumeration.
4. Add or update reviewer-loop harness coverage proving `coderabbit-cli` and
   `coderabbit` are independent.
5. Update `.ai-dev-workflow.yaml` comments and all listed workflow docs.
6. Update `CHANGELOG.md` under `[Unreleased]` with the literal entry from the
   Documentation layer above.
7. Run:
   - `bash scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`
   - The focused `pr-review-loop.sh` dispatch test added in this implementation
   - `shellcheck --severity=warning scripts/development-workflow/coderabbit-cli-reviewer.sh scripts/development-workflow/tests/test-coderabbit-cli-reviewer.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
8. Execute the smoke test runbook. If CodeRabbit CLI is unavailable in the
   runner, record the unavailable/skipped smoke evidence instead of treating it
   as clean.
