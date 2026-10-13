# PR-Agent Comment Truncation — Implementation Plan

**Spec**: [Approved spec](1_1953-pr-agent-comment-truncation_specs.md)
**Smoke test runbook**: [Runbook](../../../testing/workflow/1953-pr-agent-comment-truncation.smoke-test.md)
**Work item**: [#1953](https://github.com/lhpaul/ai-dev-framework-template/issues/1953)

## Summary

**Approach**: Execute the existing PR-Agent image through a template-owned Python launcher that installs a narrow runtime patch before invoking the original action runner. Defer premature history-first truncation until GitHub publication, where a fitter preserves the current visible review and removes history before considering a notice. The decision contract below is the authoritative algorithm; other sections reference it.

**Estimated complexity**: M — integration with a third-party runtime, persistent comment updates, consumer sync and boundary tests require more than a Fast Track patch.

**Dependencies**: Spec PR #1954 is merged. No other work item is required. Docker is required for the runtime compatibility smoke test; ordinary unit tests use Python's standard library.

## Verification Log

Repository-derived evidence was gathered at `3667dba706f2a52d383070c92597871abaeab357` on 2026-10-13. Reproduce searches at that revision; future file additions below are proposed artifacts rather than claims about existing files.

| Check | Reproducible command or query | Observed result |
| --- | --- | --- |
| Publication wiring | `git show 3667dba7:.github/workflows/pr-agent.yml` | Docker action pinned to action commit `0bd56c0508504c718cc03d504cd4ceb6725ba3c7`; existing triggers, condition, permissions and model environment are the preservation baseline. |
| Action implementation | `gh api 'repos/the-pr-agent/pr-agent/contents/Dockerfile.github_action_dockerhub?ref=0bd56c0508504c718cc03d504cd4ceb6725ba3c7' --jq .content` and base64 decode | Its base is the floating `pragent/pr-agent:github_action` image. |
| Image snapshot | `docker buildx imagetools inspect pragent/pr-agent:github_action` | The inspected image index digest is `sha256:31b9aac6ab067bada9a0c1b001d30ebc500ea4487e00a93c18c59b9ef5fa66db`. Use this immutable image snapshot for the planned launcher and its compatibility test; do not silently follow a changed tag. |
| Runtime source inspection | Run Python with `--entrypoint python` in the image snapshot; use `pathlib.Path.read_text()` and `ast.get_source_segment()` for the functions named in the consumer table below | Composer reserves the full hidden state before slicing human text. GitHub create and edit both call `limit_output_characters`; persistent update inserts identity/head metadata before edit. |
| Upstream history helpers | Inspect `/app/pr_agent/algo/review_finding_state.py` in that image | `parse_review_state` distinguishes absent state (`state=None`, `present=False`) from a valid state object and invalid/duplicate markers. `serialize_review_state` escapes comment terminators; `_render_resolved_section` renders the resolved-history suffix. |
| Review identity | Inspect `/app/pr_agent/algo/comment_identity.py` in that image | `PRReviewHeader` declares regular and incremental review headers. Use these producer-defined identities rather than model-generated wording to recognize review output. |
| Classifier consumers | `git grep -n 'classify-pr-agent-review\|classify_pr_agent_review' 3667dba7 -- scripts/development-workflow` | Pure classifier entry in `apply-readiness-labels.sh`; reviewer-loop integration delegates to that classifier. Keep classification behavior unchanged. |
| Sync scope | `git grep -n 'scripts/development-workflow/\|pr-agent.yml\|mode_scope' 3667dba7 -- sync-manifest.yaml` | Workflow is shared; the general scripts glob is hub-only. The launcher needs an explicit shared entry. |
| Test selection | Read `select-test-suites.sh` at the recorded revision, especially `infer_map` | A suite named `test-pr-agent-runtime.sh` maps to `pr-agent-runtime.py`. Include the suite wrapper so normal diff-driven CI selects it. |
| Documentation | `git grep -n 'PR-Agent\|pr-agent' 3667dba7 -- docs/workflow/development-workflow/integrations/pr-agent.md scripts/development-workflow/README.md` | Integration documentation and helper reference are the documentation targets. Project architecture/stack documents are placeholders; no database or product UI is involved. |

The following verification command references the image snapshot recorded above and reproduces the runtime consumer enumeration and source inspection. It inspects source only; it does not invoke a review or use credentials.

<!-- workflow-shell-contract: bash-zsh -->
```bash
docker run --rm --entrypoint python pragent/pr-agent@sha256:31b9aac6ab067bada9a0c1b001d30ebc500ea4487e00a93c18c59b9ef5fa66db -c '
import ast
from pathlib import Path
names = {"append_review_state", "parse_review_state", "split_review_state_marker", "serialize_review_state", "_render_resolved_section", "publish_comment", "edit_comment", "publish_persistent_comment_full", "limit_output_characters", "PRReviewHeader"}
for path in Path("/app/pr_agent").rglob("*.py"):
    source = path.read_text()
    for number, line in enumerate(source.splitlines(), 1):
        if "append_review_state" in line or "limit_output_characters" in line:
            print(path, number, line)
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)) and node.name in names:
            print(path, ast.get_source_segment(source, node))
'
```

### External output sampling record (Rule 1)

Producer: PR-Agent's GitHub issue comments. Population sampled: real review outputs associated with the issue's large-PR evidence and the spec PR, captured on 2026-10-13; the population is open and this is not a fixed output-set claim. Three PR-Agent comments were inspected through `gh api repos/<owner>/<repo>/issues/<pr>/comments --paginate --slurp`, selecting actual bodies beginning with a producer-defined review header rather than human comments that quote it.

| Occurrence locator | Relevant observed shape |
| --- | --- |
| [Template #1945, comment 6101053266](https://github.com/lhpaul/ai-dev-framework-template/pull/1945#issuecomment-6101053266) | 65,000-character body; a complete hidden state block occupies 64,791 characters; visible text ends in `Here are so...`. |
| [Radar #837, comment 6110004634](https://github.com/RADAR-Insights/radar-insights-platform/pull/837#issuecomment-6110004634) | 65,000-character body; hidden state occupies 64,741 characters; visible introduction ends in `review proces...`. |
| [Template #1954, comment 6157076766](https://github.com/lhpaul/ai-dev-framework-template/pull/1954#issuecomment-6157076766) | 548-character body with a complete visible review table and no hidden state block. |

Distinct structural variants: oversized state-bearing review with cut visible text, and small review without state. No saturation is claimed. The sample supports the reported failure and unchanged-small-comment requirement; it does not establish every model wording, every history shape or every verdict. Adequacy rests on handling the history through the inspected producer parser/renderer and preserving current-review text opaquely, rather than matching the sampled prose. Unknown or malformed oversized structured output follows the diagnostic outcome below. Synthetic tests add blocking verdicts, resolved-history sections and malformed variants without presenting them as observed samples. The issue #809 evidence comment is a human diagnostic report, not a fourth PR-Agent sample.

### Composed consumer expectations (Rule 5)

Enumerate runtime consumers by searching the image's `/app/pr_agent` tree for `append_review_state` and `limit_output_characters`; use `Path.rglob('*.py')` and report matching source lines. The patch is scoped to the review composer alias and the GitHub provider override, not every git provider or inline-suggestion tool.

| Consumer site | Producing path and expected outcome |
| --- | --- |
| `PRReviewer._prepare_pr_review`, current-state append and previous-state preservation append | Rebind the imported `append_review_state` alias and its defining module to a wrapper that uses the original composer without a size cap. Its full result reaches final publication; it does not cut the current review to preserve history. Invalid state continues to use the producer's existing error handling. |
| `GithubProvider.publish_comment` | Original method calls the patched provider limiter immediately before `create_issue_comment`; the transmitted review body follows the decision contract after identity composition. |
| `GitProvider.publish_persistent_comment_full` → `GithubProvider.edit_comment` | Keep original update selection, authorship checks and metadata insertion. Final fitting happens on the body passed to edit, including the current-head marker. No earlier fitting can leave truncated verdict text for this site. |
| Other `GithubProvider.limit_output_characters` consumers, including inline comments and status messages | Non-review output delegates to the original limiter unchanged. Review identification uses `PRReviewHeader`; do not apply history removal to arbitrary comments. |
| `apply-readiness-labels.sh` classifier → reviewer loop | Tests feed final published review bodies to the existing pure classifier. A complete visible clean or blocking review retains its original classification; a diagnostic outcome must escalate. No classifier code or merge-policy change is planned. |

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner/base | This repository, `develop` | Current invocation and merged spec PR | Recorded repository revision above | Invocation item list: `[1953]`; #1954 merged; nested-artifact guard clean for the expected plan branch | Verified |
| Runtime and model preservation | Use the image snapshot and workflow baseline from the Verification Log | Docker registry inspection and `.github/workflows/pr-agent.yml` | 2026-10-13 | Same-surface open-PR search: `gh pr list --state open --search 'pr-agent' --json number,title,headRefName,baseRefName,files` returned no open matches | Verified |

Before implementation edits, recheck these sources against the implementation base and record `Still valid`. A changed runtime/configuration assumption requires reconciliation before editing, rather than copying stale evidence. No portfolio board scan is part of this check.

## Files to Modify

| File | Planned responsibility | Spec coverage |
| --- | --- | --- |
| `scripts/development-workflow/pr-agent-runtime.py` | New stdlib-importable fitter and runtime launcher; install hooks and invoke the original action runner | AC1–AC6 |
| `.github/workflows/pr-agent.yml` | Check out the approved event revision without persisted credentials and launch the image snapshot with the runtime patch | AC6 |
| `sync-manifest.yaml` | Explicit shared launcher entry so product-repo consumers receive the dependency alongside the shared workflow | AC6 |
| `scripts/development-workflow/tests/test_pr_agent_runtime.py` | Deterministic unit and mocked-publication integration tests | AC1–AC6 |
| `scripts/development-workflow/tests/test-pr-agent-runtime.sh` | Standard suite wrapper for CI selection and local execution | AC1–AC6 |
| `docs/workflow/development-workflow/integrations/pr-agent.md` | Runtime patch, omission behavior, image compatibility and migration guidance | AC5–AC6 |
| `scripts/development-workflow/README.md` | Launcher invocation and suite reference | AC6 |
| `changelog.d/1953.fixed.pr-agent-comment-truncation.md` | Consumer release note for preserved large-PR review content | Brief requirement |

No local workflow configuration, checkpoint policy, classifier, model, issue unrelated to #1953, or release artifact is changed.

## Layer-by-Layer Changes

### Runtime and Publication Decision Contract

The pure fitter accepts a fully composed review body and a positive integer limit. The launcher supplies the GitHub provider's existing limit. Unsupported limit types/values raise an explicit error rather than producing a publishable clean review.

1. A complete body at or below the limit returns exactly as received, before any parsing or normalization.
2. For oversized review bodies, use the producer's state parser/splitter. A complete valid state block can be retained only in its entirety. Remove the resolved-history suffix only when it is the exact suffix produced by `_render_resolved_section` for that state; current finding `<details>`, identity comments and current-head metadata remain part of the visible review.
3. Try omission of the resolved-history suffix, then omission of the entire hidden state block, retaining the current visible review. Never serialize a prefix or subset of the finding state as if it were complete. When the state is omitted, subsequent producer parsing must yield absent state (`None`), never an empty-but-complete state snapshot or synthetic resolved finding.
4. After choosing retained history, use remaining capacity for a full history-omission notice; shorten it to a meaningful shorter notice when necessary; otherwise omit it. Preserve the visible review even when it exactly fills the limit. Separators, markup and any retained notice count against the limit. Emit an omission warning with character counts in existing logs, without logging the body or secrets.
5. If history removal leaves visible content exceeding the limit, or an oversized body's state is malformed, duplicated or unsupported, publish a bounded diagnostic review summary requiring manual review. Keep only provider-generated identity/head metadata that fits and the diagnostic text; do not copy a sliced verdict-bearing model section that could hide a blocker. The existing classifier must escalate this diagnostic; log the reason and counts. This is the fail-closed reduction path when the original verdict cannot safely be retained, not a clean verdict.
6. Apply the contract at the final GitHub create/edit limiter, after persistent-update metadata insertion. The early composer hook only defers the cap. Non-review limiter calls retain their original behavior.

These conditional obligations govern only oversized review publications from the pinned GitHub runtime. Unit and mocked-create/edit tests discharge them before the implementation PR opens; the real-image smoke test confirms hook binding and producer parsing before readiness.

### Infrastructure and Consumer Sync

Retain the workflow event list, job condition, token permissions, secret names and all model/action environment keys from the baseline in the Verification Log. Add checkout with `persist-credentials: false`: pull-request events use that event's head revision, while issue-comment events use the trusted workflow revision rather than executing commenter-selected PR code. Continue to rely on the existing same-repository PR condition; do not broaden fork authority or add `pull_request_target`.

The workflow launches the image snapshot with the helper mounted from the checkout and invokes its original Python action runner after hook installation. Forward required GitHub event/context values and the existing PR-Agent/model configuration; pass secret environment variable names to Docker, not their values as command arguments. Mount the event file at the container's expected event path and the workspace at its expected workspace path. Do not echo the environment or event payload. An incompatible image/hook signature must fail visibly before invoking the action runner; no silent unpatched fallback is allowed.

Store the image reference once in the launcher, exposed through a side-effect-free `--image` mode. The workflow and test wrapper read that value instead of maintaining separate pins. The wrapper's `--image-smoke` mode runs compatibility and mocked-publication tests inside that image; its default mode runs the stdlib suite without Docker. Importing the launcher for either suite must not invoke the live action runner.

The integration and sync tests must show that the shared workflow and launcher are selected together for `product_repo`, while the test-suite wrapper is selected by the repository's existing diff-driven suite mechanism. Inline workflow shell code has a `bash` contract; documentation invocation examples use `bash-zsh` without positional splitting or loop examples.

## Testing Strategy

**Test types**: stdlib unit tests, mocked create/edit publication tests, actual-image compatibility smoke test, existing classifier regression suite and sync-selection checks. No live LLM call or GitHub write is required by automated regression tests.

### Parser-Risk Edge Cases and Unit Mapping

All proposed tests below live in `test_pr_agent_runtime.py`. The names express coverage intent and can be replaced with equivalent cases; they are not a binding test-count enumeration.

| Input class | Automated coverage intent |
| --- | --- |
| Under-limit, exact-limit, empty review | `test_unchanged_comments`: byte-for-byte equality through final fitting |
| Oversized valid state with a fitting visible clean/blocking review | `test_visible_verdict_survives`: preserve full visible text, bounded body, original classifier result |
| Remaining capacity for full, short or no notice | `test_notice_capacity`: all branches including a visible review exactly at the limit |
| Resolved-history suffix plus current finding details | `test_history_suffix_only`: discard only generated history, retaining current blocker labels and nested current details |
| Unicode, JSON quoting and escaped `-->` / `--!>` in state bodies | `test_state_round_trip`: retained marker parses unchanged; omitted marker is absent, not partially valid |
| Multiple marker occurrences, inline markers, unsupported version and malformed/unclosed marker | `test_unsafe_history`: oversized malformed state yields a bounded diagnostic and classifier escalation; below-limit input remains unchanged |
| Ordinary HTML comments and negative lookalikes inside current text | `test_non_history_content`: do not treat arbitrary comments or details as history |
| Visible content alone exceeds limit, including a blocker near the end | `test_visible_oversize`: bounded diagnostic cannot classify clean |
| Invalid limit values | `test_invalid_limit`: explicit error; no clean publication |
| Fresh create and persistent edit with added current-head metadata | `test_publication_consumers`: mock outbound GitHub calls and assert their actual final bodies satisfy the contract |
| Unsupported hook signature or missing runtime helper | `test_runtime_compatibility`: startup fails visibly before runner/network invocation |
| Non-review provider comments | `test_non_review_delegation`: original limiter behavior retained |

No suppression directives or new generic Markdown/HTML parser are introduced. Concurrency-source guidance is not applicable: the patch uses deterministic synchronous composition within the existing action process, without listeners, timers, queues or shared cross-run state. Cross-cutting checklist guidance is not applicable: no workflow-wide checklist is changed.

**Coverage proportionality**: fixtures are generated deterministically from small clean/blocking reviews and repeated history text. They exercise data-loss boundaries and actual outbound bodies; no mass fixture manifest or bespoke validation framework is needed. Existing classifier tests remain the authoritative format coverage.

## Seed Data

Generate synthetic state and current-review fixtures inside the Python test suite. Use fixed finding identifiers, paths and timestamps; vary only body size, state validity and notice capacity. Do not commit the sampled comments or consumer production code as fixtures. No database seed, user account, API key or live review is needed for unit tests.

## Documentation Updates

The developer updates the integration document and helper README listed in Files to Modify. Describe the runtime hooks, publication priority, log visibility, pinned-image upgrade procedure and shared sync dependency. Ensure the description of preserved triggers agrees with the recorded workflow baseline. Leave unrelated provider pricing, project placeholders and policy documents alone.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Imported composer alias escapes the patch | Hook both the defining module and reviewer alias; test the actual image and final create/edit consumers. |
| History removal changes current verdict content | Remove only parsed state and its exact generated resolved suffix; classify the final visible review with the unchanged existing classifier. |
| Omitted state masquerades as complete or resolved history | Drop the complete marker atomically, verify absent-state parsing, log omission, and never synthesize an empty snapshot or partial finding list. |
| Provider metadata exceeds the composed body budget | Fit at the final limiter after metadata insertion and test persistent edit. |
| Consumer receives workflow without helper | Add and test explicit shared sync selection. |
| Workflow change exceeds delegated merge authority | `.github/workflows/pr-agent.yml` is a high-risk path under the existing classifier; do not weaken it. The eventual implementation may be prepared and reviewed, but cannot merge under the current low ceiling if that classification remains. |

## Implementation Order

1. Revalidate the operational assumptions and record `Still valid`; create the implementation branch from the merged plan's approved base. Keep this plan PR limited to the plan and smoke runbook.
2. Implement the fitter, launcher hooks and deterministic regression suite under the decision contract. Run the suite and existing classifier tests; use mocked final publication bodies rather than testing only the early composer.
3. Wire the workflow to the launcher and add its shared sync entry. Prove the compatibility guard fails for a planted unsupported hook and passes for the supported image; prove missing shared dependency is detected by the sync-selection test and corrected by the entry.
4. Run the smoke runbook, ShellCheck for the wrapper, workflow shell/snippet lints, Markdown lints and sync checks. Verify the suite selector includes the wrapper without changing unrelated suites.
5. Complete the documentation updates and add the changelog fragment in the repository's bold-title issue-reference format. Commit each coherent verified part; do not rewrite published history.
6. Open the implementation PR and complete internal review, external review, CI and readiness through Protocol 91. A new blocking finding stops this run per Luis's instruction. Merge only after live risk classification is within the authorized ceiling and durable session admission, required audits and the delegated gate all pass; otherwise report the named blocker without merging.
