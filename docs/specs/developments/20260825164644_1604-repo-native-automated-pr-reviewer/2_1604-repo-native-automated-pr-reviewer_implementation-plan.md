# Repo-Native Automated PR Reviewer Spike/MVP - Implementation Plan

**Spec**: [1_1604-repo-native-automated-pr-reviewer_specs.md](1_1604-repo-native-automated-pr-reviewer_specs.md)
**Smoke test runbook**: [1604-repo-native-automated-pr-reviewer.smoke-test.md](../../../testing/workflow/1604-repo-native-automated-pr-reviewer.smoke-test.md)
**Work item**: #1604 (Type: Workflow, Priority: High)

---

## Template-Fit Check (Protocol 02 Step 0)

`.ai-dev-workflow.yaml` sets `template.is_template: true`, so this check is mandatory.

**Result**: **Pass - generic.** This work adds repository-owned workflow tooling for the template's Step 7
automated PR reviewer loop. The implementation surface is the existing template workflow layer:
`scripts/development-workflow/`, `.ai-dev-workflow.yaml`, `docs/workflow/development-workflow/integrations/`,
`docs/testing/workflow/`, and workflow tests. No downstream product runtime, domain model, app framework, or
service-specific business code is involved. Downstream repositories can opt into the platform the same way
they opt into `coderabbit-cli`, `bugbot`, `haystack`, or `codex-github`.

---

## Summary

**Approach**: Implement a new `local-ai-reviewer` Step 7 platform using the same companion-script plus
`pr-review-loop.sh` adapter shape already used by `coderabbit-cli` and `haystack`. The companion script will
perform deterministic pre-review checks, build a bounded review context bundle, invoke a caller-configured
local review command, normalize its machine output into the existing key-value contract, and fail closed when
the command is missing, unavailable, timed out, malformed, or bound to the wrong head. The shared reviewer
loop will dispatch the new platform in draft phase when configured, keep current ready-phase Bugbot behavior
unchanged, and expose enough structured evidence to compare whether Bugbot finds net-new blockers after the
local pass.

The implementation will not add native GitHub inline comments. Local findings will remain script-owned
evidence in reviewer-loop output and summaries. Graph context is optional evaluation input only: the default
MVP path is no-graph context, with explicit `GRAPH_CONTEXT=skipped` when graph tooling is not configured.

**Estimated complexity**: L

**Rationale**: The adapter itself follows an existing pattern, but the correctness bar is higher than a thin
CLI wrapper. The implementation needs current-head binding, stage-boundary checks, strict result parsing,
finding normalization, fixture coverage for net-new ready-phase comparison, integration docs, and a smoke
runbook. The graph-tool evaluation must be represented without making either `code-review-graph` or
`graphify` a hard dependency.

**Dependencies**: None blocking. The repo currently uses `pr-agent` for draft GitHub review and `bugbot` for
ready-phase review. The plan preserves that configuration while adding an opt-in local platform.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` and `git rev-parse --short origin/develop` | Both `0fbeb371` |
| Current review config | Read `.ai-dev-workflow.yaml` review section | `review.on_draft.runner: [codex]`, `review.on_draft.github: [pr-agent]`, `review.on_ready.github: [bugbot]` |
| Ready-phase reviewer change | Read `.ai-dev-workflow.yaml` comments | Bugbot is documented as the repository's default ready-phase GitHub reviewer; CodeRabbit and CodeRabbit CLI remain opt-in |
| Existing platform adapter pattern | Read `run_haystack_review`, `run_coderabbit_cli_review`, and `run_platform_review` in `scripts/development-workflow/pr-review-loop.sh` | Companion-script adapters map exit codes to `RESULT`, `REASON`, `COMMENT_COUNT`, `BLOCKING_COUNT`, and `SUGGESTION_COUNT` |
| Existing compare-mode support | Read `normalize_platform_verdict` and `append_compare_metrics_row` in `pr-review-loop.sh` | Compare mode records platform verdicts, but it does not yet compare finding identity or net-new ready-phase blockers |
| Existing local reviewer scripts | `ls scripts/development-workflow/*reviewer*.sh` | `claude-code-action-reviewer.sh`, `coderabbit-cli-reviewer.sh`, `codex-github-reviewer.sh`, `haystack-reviewer.sh` |
| Existing reviewer integration docs | `ls docs/workflow/development-workflow/integrations/*review*.md docs/workflow/development-workflow/integrations/bugbot.md docs/workflow/development-workflow/integrations/coderabbit.md` | `pr-review-platform.md`, `bugbot.md`, `coderabbit.md`, plus platform-specific docs |
| Existing tests to extend | `find scripts/development-workflow/tests -maxdepth 1 -type f \| rg 'coderabbit|bugbot|pr-review-loop|platform'` | `test-coderabbit-cli-pr-review-loop-dispatch.sh`, `test-coderabbit-cli-reviewer.sh`, `test-pr-review-loop.sh` |
| Smoke-test precedent | Read `docs/testing/workflow/1375-coderabbit-cli-review-platform.smoke-test.md` | Companion CLI platforms have plan-stage runbooks covering dispatch, unavailable paths, result mapping, and evidence wording |
| Same-surface open PRs | `gh pr list --state open --json number,title,headRefName,baseRefName --limit 20` | `[]`; no open PRs observed |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact base branch | `develop` | Issue #1604 spec PR #1605 merged into `develop`; current worktree based on `origin/develop` | 2026-08-25, repo `0fbeb371` | Current invocation only; no same-surface open PRs | `Verified` |
| Artifact owner / repository mode | `single_repo` default, with `template.is_template: true` | `.ai-dev-workflow.yaml` | 2026-08-25, repo `0fbeb371` | Current invocation only | `Verified` |
| Current ready-phase reviewer | `bugbot` | `.ai-dev-workflow.yaml` | 2026-08-25, repo `0fbeb371` | User explicitly changed config from `codex-github` to Bugbot because Codex GitHub was too slow; no plan step reverts it | `Verified` |
| Local reviewer lifecycle bucket | `review.on_draft.github` / `pr-review-loop.sh` platform, not `review.on_draft.runner` | Spec business rules plus existing `.ai-dev-workflow.yaml` comments | 2026-08-25, repo `0fbeb371` | Implementation will add a Step 7 platform only | `Verified` |
| Graph tooling dependency policy | Optional evaluation input; no mandatory graph dependency for MVP | Spec graph adoption criteria | 2026-08-25, repo `0fbeb371` | Implementation will detect configured graph tooling and otherwise emit skipped graph context | `Verified` |

No conflict was found. The only drift from the original spec wording is the ready-phase reviewer name:
the spec preserved `codex-github` for measurement, while the live repository has already switched that
ready-phase slot to Bugbot. The implementation should therefore refer to the "configured ready-phase
reviewer" in generic docs and use Bugbot as this repository's current example.

---

## Design Decisions

### Decision 1 - Add `local-ai-reviewer` as an opt-in Step 7 platform

Add a new supported platform token: `local-ai-reviewer`.

The platform belongs to `review.on_draft.github` or an explicit `--platform local-ai-reviewer` invocation.
It is not an internal Step 7a runner reviewer. This keeps the lifecycle aligned with the spec and avoids
confusing the local reviewer with the native spec/plan/code review gate.

The shared `.ai-dev-workflow.yaml` should document the platform and its options but should not make it a
repository default until a real local review command is configured. A missing local model command is an
availability failure, not clean evidence, so enabling it by default without configuration would block the
workflow for every contributor.

### Decision 2 - Use a companion script with a strict command boundary

Add `scripts/development-workflow/local-ai-reviewer.sh`.

The script accepts:

- Pull request number, owner, and repository name.
- `--repo-root <path>` for worktree-bound review.
- `--timeout <seconds>` for the complete local review command.
- Optional graph/context flags or environment variables.

The script invokes a configured local review command via `LOCAL_AI_REVIEWER_COMMAND`. The command receives a
path to a generated context bundle and must emit a machine-readable result file or stdout payload. The exact
implementation can use shell-safe argument passing rather than `eval`; if a command string is required for
developer ergonomics, document that it runs under `sh -c` and add tests for quoting and failure behavior.

Missing `LOCAL_AI_REVIEWER_COMMAND`, missing model access, missing credentials, timeout, malformed output, and
head mismatch all emit `RESULT=escalate` with the spec's underscore reason values. `disabled_by_config` is the
only non-error skip path for the companion script.

### Decision 3 - Deterministic checks run before the model command

Before invoking `LOCAL_AI_REVIEWER_COMMAND`, `local-ai-reviewer.sh` performs the spec's deterministic checks:

- Confirm PR metadata head SHA, checkout `HEAD`, and emitted `REVIEWED_HEAD` match.
- Collect changed files and derive branch/stage from branch name and artifact paths.
- Enforce spec/plan/implementation artifact boundaries using the same stage-alignment rules as the workflow.
- Verify `REVIEW.md` and the applicable stage checklist/protocol are readable.
- Scan changed files and stage artifacts for placeholders, stale review markers, TODO/FIXME/debug text, and
  known review-marker patterns.
- Record expected validation evidence by stage.
- Check unresolved reviewer threads when GitHub metadata is available.
- Classify missing tools, credentials, timeout, malformed payloads, and head mismatch before normalization.

If a deterministic check finds a blocking workflow violation, the script may return `RESULT=needs_fixes`
without invoking the model command. If it cannot determine whether the result is safe, it returns
`RESULT=escalate`.

### Decision 4 - Context bundle is explicit and auditable

The script writes a temporary context bundle with:

- PR number, base branch, head branch, reviewed head SHA, and changed files.
- The loaded review contract and stage checklist references.
- A diff summary and bounded file excerpts for changed files.
- Deterministic-check results.
- Graph context status and selected graph snippets when enabled.
- Local validation evidence detected from workflow logs or provided by the caller.

The context bundle path may be emitted as `CONTEXT_BUNDLE_PATH` only when it is safe to expose in logs. It must
not contain credentials, local override secrets, or unbounded repository dumps.

### Decision 5 - Graph context is optional and measured, not mandatory

The first implementation defaults to no graph context. Add configuration for:

- `LOCAL_AI_REVIEWER_GRAPH_STRATEGY=none|code-review-graph|graphify|auto`
- Optional command overrides for the graph tools if the implementation needs them.

When a graph strategy is not configured or the tool is absent, emit `GRAPH_CONTEXT=skipped` and
`REASON=graph_context_skipped` only in the graph-context fields, not as the platform's terminal result. A
missing optional graph tool must not turn a review into clean or escalation.

Add an evaluation section in the docs and smoke runbook that compares no graph, `code-review-graph`, and
`graphify` over the three representative inputs required by the spec. The adoption decision is recorded as
Deferred, Optional, or Required using the spec's ordered rules. Until that evidence exists, the default remains
no graph.

### Decision 6 - Preserve Bugbot as ready-phase validation

Do not change this repository's ready-phase platform from Bugbot. Update docs to use "configured ready-phase
reviewer" generically and Bugbot as the current repository example.

The local reviewer is intended to reduce what reaches Bugbot, not to replace Bugbot. If the local reviewer
returns `needs_fixes`, the loop stops for fixes. If it returns `clean` with advisory suggestions, the loop may
continue and Bugbot can still report net-new blockers.

### Decision 7 - Add finding normalization for net-new ready-phase measurement

Add a small helper, preferably Python for structured parsing, named
`scripts/development-workflow/local-ai-reviewer-findings.py`.

The helper normalizes findings from the local reviewer and ready-phase reviewers into records containing:

- head SHA
- severity
- path and line/range when available
- affected scope key
- title
- stable category key
- canonical requirement key
- canonical failure-mode key
- summary

Matching follows the spec:

- Compare only findings from the same head.
- Collapse local duplicates by head, scope, category, requirement, and failure mode.
- Collapse ready-phase duplicates by head, scope, category, requirement, failure mode, and normalized title.
- Match one-to-one; consumed local findings cannot match multiple ready-phase findings.
- Treat ambiguous matches as net-new and list candidate local IDs.
- Only match `unclassified` findings on exact affected scope plus normalized title.

The first implementation can consume local reviewer JSON plus ready-phase finding fixtures or summaries
captured from platform output. It does not need to parse every historical platform's prose perfectly, but it
must preserve `unclassified` instead of inventing false certainty.

### Decision 8 - Strict result contract, no raw `advisory` result

The companion script emits only these terminal raw result values:

- `clean`
- `needs_fixes`
- `needs_rerun`
- `skipped`
- `escalate`

Advisory-only local findings emit `RESULT=clean`, `BLOCKING_COUNT=0`, `SUGGESTION_COUNT>0`, and
`COMMENT_COUNT` equal to total advisory suggestions. Do not emit `RESULT=advisory` unless a separate item
adds normal-loop support for that raw value.

The `pr-review-loop.sh` adapter maps companion exit codes to this contract and forwards structured fields
without silently downgrading malformed output.

### Decision 9 - Tests own the parser-risk boundary

This feature is parser-risky because it consumes model/tool output and normalizes reviewer prose into
workflow decisions. Tests must cover both the terminal result parser and the finding matcher before the
platform is used as a workflow gate.

Minimum parser fixtures:

- Clean output with advisory count zero.
- Clean output with advisory suggestions and no blocking findings.
- Blocking finding with file path and line.
- Blocking repo-wide finding without line.
- `needs_rerun` with retry reason.
- Missing command.
- Missing model access.
- Missing credentials.
- Timeout.
- Malformed output.
- Head mismatch.
- Optional graph skipped.
- Same path with different requirement keys.
- Ambiguous same-category match.
- Multiple ready-phase findings that otherwise match one local finding.
- Rephrased same issue.
- Severity-promoted same issue.
- `unclassified` exact-title match and non-match.

---

## Layer-by-Layer Changes

### 1. Companion script

Add `scripts/development-workflow/local-ai-reviewer.sh`.

Responsibilities:

- Parse arguments and resolve repo root.
- Query PR metadata with `gh`.
- Bind checkout `HEAD` to PR head.
- Run deterministic pre-review checks.
- Build the context bundle.
- Optionally collect graph context.
- Invoke `LOCAL_AI_REVIEWER_COMMAND`.
- Parse and validate the local command output.
- Emit normalized key-value output and exit codes.

Exit-code mapping:

| Exit | Meaning | Required output |
| --- | --- | --- |
| 0 | Clean or advisory-only | `RESULT=clean`, counts, `REVIEWED_HEAD` |
| 1 | Blocking findings | `RESULT=needs_fixes`, `BLOCKING_COUNT>0`, summaries |
| 2 | Unsafe/unavailable | `RESULT=escalate`, specific underscore `REASON` |
| 3 | Intentional disabled skip | `RESULT=skipped`, `REASON=disabled_by_config` |

### 2. Finding helper

Add `scripts/development-workflow/local-ai-reviewer-findings.py`.

Responsibilities:

- Normalize finding records.
- Collapse duplicates.
- Compare local and ready-phase findings.
- Emit machine-readable comparison output for tests and reviewer-loop summaries.

Use Python's JSON parser and explicit schemas rather than shell string splitting for this layer.

### 3. Reviewer-loop adapter

Update `scripts/development-workflow/pr-review-loop.sh`.

Changes:

- Add `local-ai-reviewer` to usage and supported platform lists.
- Add `run_local_ai_reviewer_review`.
- Add dispatch in `run_platform_review`.
- Ensure `bot_login_for_platform local-ai-reviewer` returns empty because the MVP does not post GitHub inline comments.
- Forward local reviewer structured fields such as `REVIEWED_HEAD`, `GRAPH_CONTEXT`,
  `LOCAL_REVIEW_FINDINGS_JSON`, and advisory summaries where existing output conventions permit.
- Keep ready-phase Bugbot dispatch unchanged.

### 4. Configuration and docs

Update:

- `.ai-dev-workflow.yaml` comments to document `local-ai-reviewer` as an opt-in draft-phase platform and
  Bugbot as the current ready-phase example.
- `docs/workflow/development-workflow/integrations/pr-review-platform.md` to include the new platform token,
  no-fresh-review semantics, and recommended ordering before ready-phase reviewers.
- Add `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` with setup, command contract,
  graph evaluation, failure modes, and examples.
- Update `docs/workflow/development-workflow/integrations/bugbot.md` only if needed to reference local-review
  measurement generically; do not change Bugbot setup behavior.

### 5. Tests

Add:

- `scripts/development-workflow/tests/test-local-ai-reviewer.sh`
- `scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`
- `scripts/development-workflow/tests/test-local-ai-reviewer-findings.py`

Extend:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` for platform-list and summary behavior only
  where the existing harness already covers shared reviewer-loop behavior.

Use `# covers:` comments so suite selection can associate the tests with the new scripts and changed
reviewer-loop file.

### 6. Smoke test runbook

Add the plan-stage smoke runbook at:

`docs/testing/workflow/1604-repo-native-automated-pr-reviewer.smoke-test.md`

The implementation stage updates its "Updated in" line and records whether graph evaluation was run live,
deferred, or skipped for missing tools.

### 7. Changelog

The implementation PR adds a release note using the repository's current changelog convention at the time of
implementation. This plan PR does not change `CHANGELOG.md`.

---

## Implementation Order

1. Re-verify `.ai-dev-workflow.yaml` review config and keep Bugbot as the current ready-phase platform.
2. Add `local-ai-reviewer.sh` with argument parsing, PR metadata lookup, current-head binding, and strict
   terminal result output.
3. Add deterministic pre-review checks and fixtures for each failure reason.
4. Add context-bundle generation with explicit file/path bounds and credential redaction tests.
5. Add optional graph context detection and `GRAPH_CONTEXT=skipped` behavior.
6. Add `local-ai-reviewer-findings.py` and parser fixtures for the spec's net-new matching cases.
7. Add `pr-review-loop.sh` dispatch, supported-platform docs in usage text, and summary/output forwarding.
8. Add local reviewer integration docs and config comments.
9. Add unit and dispatch tests, then extend shared reviewer-loop tests only for shared behavior.
10. Add the implementation changelog entry.
11. Run the smoke-test runbook with a mock local command and, if practical, with one real local command.
12. Record graph evaluation evidence across at least three representative inputs or explicitly record why
    graph evaluation was deferred.

---

## Testing Strategy

Automated checks:

```bash
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh
bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh
python3 scripts/development-workflow/tests/test-local-ai-reviewer-findings.py
bash scripts/development-workflow/tests/test-pr-review-loop.sh
npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"
find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
  | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop
```

Manual/smoke checks:

- Run `pr-review-loop.sh` with `--platform local-ai-reviewer` and a mock clean command.
- Run it with a mock blocking command.
- Run it with missing `LOCAL_AI_REVIEWER_COMMAND` and confirm escalation, not clean.
- Run it with optional graph context absent and confirm the platform can still review with
  `GRAPH_CONTEXT=skipped`.
- Run draft-phase local review followed by ready-phase Bugbot on a disposable PR if credentials and reviewer
  availability permit.

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Missing local model command blocks contributors if enabled globally | Keep platform opt-in by default; document local override and explicit configuration |
| Model output parser accepts malformed or partial evidence | Require strict JSON or key-value schema, fail `RESULT=escalate` on malformed output, and cover parser fixtures |
| Local reviewer claims clean on the wrong head | Bind PR head, checkout head, context bundle head, and emitted `REVIEWED_HEAD`; mismatch escalates |
| Graph tooling adds setup cost without review value | Default to no graph and record optional/deferred adoption evidence before making graph required |
| Ready-phase Bugbot findings are counted as duplicates incorrectly | Use conservative one-to-one matching; ambiguous matches count as net-new |
| Advisory suggestions accidentally block the workflow | Preserve advisory-only as `RESULT=clean` with positive `SUGGESTION_COUNT`, not raw `RESULT=advisory` |
| Local reviewer creates false confidence without GitHub comments | Make no-inline-comments explicit in docs and summaries; local output is evidence, not a GitHub review thread |

---

## Out of Scope

- Replacing Bugbot or any configured ready-phase reviewer.
- Adding native GitHub inline comments for local findings.
- Making `code-review-graph` or `graphify` mandatory.
- Changing Step 7a internal reviewer semantics.
- Auto-installing or committing third-party graph tool dependencies.
- Merging PRs without human review.
