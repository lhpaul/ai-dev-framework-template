# Evidence review retry — Implementation Plan

**Spec**: [Evidence review retry](1_2061-evidence-review-retry_specs.md)
**Smoke test runbook**: [Synthetic evidence retry](../../../testing/workflow/2061-evidence-review-retry.smoke-test.md)

## Summary

**Approach**: Extend the existing local-review context and reviewer-loop ledger with evidence identity, permit an explicit fresh local review on the same commit, and make the loop and readiness use the same verification predicate for PR-Agent requests. Evidence publication never grants approval; a current local reviewer must explicitly verify the requested proof. Keep the existing providers, stage ownership, history, and merge gates.

**Estimated complexity**: M. The work coordinates context collection, parser outcomes, replay, and readiness; tests must exercise their composition rather than only isolated helpers.

**Dependencies**: The linked spec is merged in PR #2062. No downstream configuration change or schema migration is proposed. Template-fit check passed: the change improves the template's own stack-independent review tooling.

## Verification Log

Repository-derived records below were collected at `9c1f4b36073304157d91af3bef60a984f7bd70db`. Paths listed as implementation targets later in this plan are prospective scope, not claims that those changes already exist.

| Check | Reproducible command / query | Result |
| --- | --- | --- |
| Revision | `git rev-parse HEAD` | Recorded revision above |
| Context and retry entrypoints | `rg -n 'LOCAL_AI_REVIEWER_EVIDENCE_FILE|pr_body:|reviewer_loop_local_retry_allowed|_pr_agent_classify\(|--classify-pr-agent|pragent_verdict=' scripts/development-workflow/{local-ai-reviewer.sh,local-codex-review-command.sh,local-http-review-command.sh,pr-review-loop.sh,apply-readiness-labels.sh}` | Local context contains PR body with an existing slice; retry whitelist is in the loop; PR-Agent pure classification and readiness live in apply-readiness-labels |
| Composed consumers | `rg -n 'reviewer_loop_local_retry_allowed|_pr_agent_classify|classify_pr_agent_review|coderabbit_cli_local_ai_ledger_verdict' scripts/development-workflow --glob '*.sh' --glob '!**/tests/**'` | Consumer disposition is recorded in the table below |
| Ledger consumers | `rg -n 'reviewer_loop_history_extract_latest_json|reviewer_loop_local_latest_verdict|local_second_pass' scripts/development-workflow/{workflow-lib.sh,pr-review-loop.sh,apply-readiness-labels.sh}` | Shared ledger extraction, loop replay/second pass, and readiness ledger adapter are the relevant consumers |
| Tests and integration guidance | `rg --files scripts/development-workflow/tests docs/workflow/development-workflow/integrations | rg '(local-ai-reviewer|local-codex-review-command|local-http-review-command|pr-review-loop-pr-agent|apply-readiness-labels|pr-review-platform)'` | Existing shell harnesses and local-review integration guidance provide extension points |
| Retry policy references | `rg -l 'retry-local-review-head|Only prior infrastructure escalations|failed_for_head' docs .agents .codex .claude .cursor README.md REVIEW.md scripts/development-workflow --glob '!**/tests/**'` | Current loop help, Protocol 93, and the 1656 smoke/proof documents need consistency review. Merged 1656/1789 plans are historical evidence and remain unchanged |
| Reproduction | Extract `reviewer_loop_local_retry_allowed` from the recorded loop revision; call it with an explicit matching forty-character lowercase SHA and a synthetic readable v1 ledger containing a same-head `needs_fixes` / `existing_findings` entry | Exit 1: the retry is refused despite explicit same-head selection |
| Retry-counter correction, inspected at `188c821cece32b40f610edc0058aade995c6aa6e` | `sed -n '13532,13600p' scripts/development-workflow/pr-review-loop.sh`; `rg -n 'reviewer_loop_history_entries_count|reviewer_loop_resolve_cycle_counts|reviewer_loop_cap_exceeded|CYCLE_COUNT|TOTAL_CYCLE_COUNT' scripts/development-workflow --glob '*.sh' --glob '!**/tests/**'` | The current counter deduplicates qualifying entries by head/result; its production consumers are the loop's count resolver, startup telemetry, and final cap checks. These need the attempt-aware path below; historical entries retain the existing computation |

## Factual Claim Evidence

### External output contract

The PR-Agent renderer publishes the ticket-heading and compliance-label contract in [ticket_markdown_logic](https://github.com/The-PR-Agent/pr-agent/blob/4ea729335fec89f0ccd12f9bb68b90f21e749974/pr_agent/algo/utils.py). The inspected blob is `aea96d1268e4dc5d2c224970cfb4a2584dc77a90`, retrieved with `gh api repos/The-PR-Agent/pr-agent/contents/pr_agent/algo/utils.py`; the commit was resolved with `gh api repos/The-PR-Agent/pr-agent/commits/main --jq '.sha'` on 2026-10-28. This is the producer's rendering contract, used under Rule 1's fixed-output-contract route, rather than synthetic strings presented as observed samples.

The renderer maps outstanding verification to the displayed compliance label `PR Code Verified` and a dedicated verification heading; it renders requirement explanations from model-generated text. Bind only to the published section/label structure, never to the wording of the explanation. Unknown headings, malformed structure, unknown statuses, and independently non-compliant requirements remain conservative outcomes. This record does not claim that the producer's free-text distribution is closed or that its future versions cannot change.

### Composed Consumer Disposition

| Consumer site | Proposed path and observable outcome |
| --- | --- |
| Loop `_pr_agent_classify`, existing-summary phase and polling phase | Pure classification identifies a well-formed verification-only request separately from malformed output. The request remains pending until the evidence-verification path below succeeds. Both phases use the shared predicate; neither silently grants clean |
| Pure `--classify-pr-agent` mode | Remains a no-network classifier; without verification evidence its conservative public result remains escalation. Add a distinct internal inspection mode for identifying a verification-only request without treating it as approval |
| `classify_pr_agent_review labels` / `--pr-agent-focus-labels` | Advisory focus extraction remains unchanged; verification cannot erase code/security focus blockers |
| Readiness `pragent_verdict` in issue-comment interpretation | Validate current trusted local proof before admitting the verification-only variant; other malformed/ambiguous outcomes still refuse readiness |
| `coderabbit_cli_local_ai_ledger_verdict` via platform readiness and current-head rechecks | Keep existing author/write-trust selection. Local evidence-based clean requires matching evidence identity as well as current head; coderabbit-cli behavior remains unchanged |
| `reviewer_loop_local_retry_allowed` through second-local-pass guard | Explicit matching retry dispatches a full real local review after prior findings or infrastructure failure. Absent explicit authorization, unreadable history, wrong SHA, or exhausted limits preserve refusal |
| Loop local latest-verdict, staged replay, second pass, and history rendering | Changed evidence invalidates evidence-dependent replay; preserve earlier records and add current proof/retry metadata. Existing consumers without new fields cannot manufacture verified evidence |
| `reviewer_loop_history_entries_count` through `reviewer_loop_resolve_cycle_counts`, startup CYCLE_COUNT/TOTAL_CYCLE_COUNT, final cap checks, and the new retry pre-dispatch check | Use the attempt-accounting definition below on both axes; the pre-dispatch check refuses an already exhausted budget before calling the reviewer. Existing non-retry entries keep their historical counting behavior |

### Scoped Conditional Obligations

Each obligation in the following design binds to the current repository, PR, commit and snapshot collected for that invocation. Context validation discharges collection obligations; local-result validation discharges verification obligations; loop pre-dispatch/live-head rechecks discharge retry obligations; the independently fetched readiness snapshot discharges reuse obligations. The test mapping below names the corresponding observable boundary for each input class.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base | This repository, develop | Current invocation and spec PR #2062 live base/merge evidence | 2026-10-28, recorded repository revision | Item list: #2061; supplied same-surface open PR evidence: none. No portfolio scan performed | Verified |
| Review authority | Reviewer must verify evidence; explicit same-commit retry allowed; maximum risk medium only for #2061 | Human alignment in this session; spec Business Rules and AC1–AC6 | 2026-10-28, recorded repository revision | #2061 only | Verified |

Implementation re-reads these sources and records `Still valid` before file edits. A conflict stops the affected statement for parent resolution, without changing architecture or scope.

## Parser-Risk and Concurrency Classification

Parser-risk applies: the PR-Agent classifier interprets Markdown/HTML and the new evidence predicate validates structured results. The edge-case/unit-test table below is mandatory coverage. No suppression syntax is introduced. Concurrent-event-source classification does not apply: this plan adds no asynchronous listener, callback, timer, or shared service. Remote head/evidence drift during an existing synchronous review is handled explicitly in the design.

## Layer-by-Layer Changes

### Evidence Context and Local Review

Introduce `scripts/development-workflow/review-evidence-context.py` as a dependency-free helper for deterministic snapshot identity and verification matching, using the existing shell/Python helper pattern. It receives JSON through files/stdin rather than large argv. Shell callers collect PR identity/body and every issue-comment page with existing gh/REST facilities; API/JSON/pagination failures leave evidence unavailable and cannot approve. No new GraphQL query is necessary.

The snapshot contains repository/PR/head identity, the full PR body, and evidence-bearing comments with stable comment IDs and revision metadata. Present published comments to the reviewer as untrusted data, not instructions. Do not add truncation or retain the current body slice on the new evidence path. Redaction and private-configuration protection continue through existing safe output mechanisms; do not persist raw comment bodies in public history.

Use context field `evidence_context` with schema `review_evidence_context.v1` and keys `repository`, `pr_number`, `head_sha`, `body`, `comments`, `available`, and `snapshot_sha256`. Each comment carries `id`, `body`, and `updated_at`. Unavailable collection sets `available` false and an empty identity, never a hash over a partial response. Hash canonical UTF-8 JSON of repository/PR/head/body and eligible comments, with sorted object keys and compact separators. Do not hash the identity field itself.

Define a deterministic SHA-256 identity over the body and eligible comment IDs/bodies/revisions sorted by ID. Exclude workflow bookkeeping comments identified by the existing exact summary, disposition, checkpoint and quality-gate markers; excluded text cannot be cited as verification proof. Include PR-Agent's actual request comment so a changed request invalidates its proof. Document the inclusion rule and test it; a marker substring in ordinary prose must not silently erase a comment from evidence.

In `local-ai-reviewer.sh`, put the snapshot and its availability/identity in the context bundle, and retain its identity in the optional evidence artifact. Extend the ordinary prompts in `local-codex-review-command.sh` and `local-http-review-command.sh`: distinguish missing proof from defects, inspect supplied proof, and return explicit structured verification only for outstanding PR-Agent requests whose proof was actually checked. Preserve ordinary result and reviewed-head validation and strict spec/plan checks.

Proposed verification metadata is an additive object containing snapshot identity, request comment identity, status (`verified` or `unverified`), and nonempty references to eligible proof locations (`body` or a comment ID). The runner independently binds repository/PR/head from its own snapshot, not from model assertions. Missing metadata never verifies a PR-Agent request; an ordinary clean review unrelated to that request is insufficient. A verification assertion cannot turn a `needs_fixes`, strict-check failure, malformed response, or missing reviewed head into clean.

The ordinary result's additive `evidence_verification` object uses schema `review_evidence_verification.v1` and keys `snapshot_sha256`, `request_id`, `status`, and `sources`. Supply the selected authenticated, current-head PR-Agent summary ID as `verification_request_id` in the context. A `verified` result covers every outstanding verification requirement in that summary; references must be `body` or `comment:<decimal-id>` for a current eligible comment other than the request itself. Empty/unknown/duplicate malformed source values, missing keys, wrong types, and identities not matching the independently collected snapshot cannot verify. Preserve these compact fields with the local platform result in history; absence means no verification, not an implicit success.

After local review, re-fetch head and evidence before accepting proof. Drift leaves the request pending and requires a fresh review. Store only compact identity/reference metadata with the platform result in the existing trusted loop ledger; retain prior entries. Schema additions are optional for historical entries; historical clean entries with no evidence proof do not satisfy new verification requests.

### Loop Retry and PR-Agent Integration

In `pr-review-loop.sh`, preserve default failed-head refusal and extend `--retry-local-review-head` to authorize a fresh full review after same-head findings, as well as its existing infrastructure-repair route. Require the exact current SHA and readable history, consume the explicit request before dispatch, retain earlier records, and count evidence retries against existing per-run/lifetime bounds. Rejected proof remains `needs_fixes`; unknown or unavailable review never clears it. Code findings remain blocking even on an explicitly retried head.

#### Same-Head Retry Attempt Accounting

For every newly authorized explicit retry, generate a fresh UUID in the loop and add `local_review_retry_attempt: {id, head_sha, run_id}` to its existing v1 history entries. The ID identifies the attempt, not the SHA/result pair; bind its head to the selected invocation SHA and its run to the current stable run ID. Do not reuse an ID for another dispatch. This additive metadata preserves the existing ledger schema and all earlier records.

Before dispatch, re-read counts under the existing loop lock. Reject a negative/unavailable count or a per-run/lifetime count at its configured ceiling. Use the existing `cycle_count_unavailable`, `max_cycles_exceeded`, and `max_total_cycles_exceeded` reasons as applicable; change no configuration or limit. Add `reviewer_loop_reserve_local_retry_attempt` in the loop to publish a pending reservation through the existing summary/history writer and independently read it back before executing the reviewer. The reservation carries the attempt object and remains pending/non-clean. Failure to persist or verify it prevents dispatch. The final outcome appends a record with the same attempt object; it never erases the reservation or the preceding failure. A crash after reservation consumes that attempt conservatively, including when no final outcome is available.

In `reviewer_loop_history_entries_count`, partition entries by presence of the attempt object. For entries without it, retain the exact current qualifying-result filters, head/result deduplication and per-run filtering. For attempt-bearing entries, count distinct valid attempt IDs irrespective of result, including reservations, infrastructure failures and clean outcomes; reservation plus completion for one ID counts once. Lifetime count is the historical partition's count plus distinct attempt IDs over all runs. Per-run count applies the same historical algorithm within the selected run and adds IDs bound to that run. Repeated same-head failures with different IDs therefore each consume a slot without double-counting their reservation/completion records. A present-but-malformed object, invalid UUID/head/run binding, or conflicting metadata for a repeated ID makes counts unavailable rather than falling into the historical partition. Old entries are neither rewritten nor assigned synthetic IDs.

Feed the combined counts through `reviewer_loop_resolve_cycle_counts` to startup telemetry and existing final cap checks; the retry pre-dispatch guard reuses the same resolver and ceilings. A completion at the last admitted slot may be clean; an additional retry cannot start once the budget is exhausted. A new run ID resets only the per-run axis; the lifetime axis still includes all reserved IDs. Update the loop's counter help text and Protocol 93 to describe this hybrid computation. Their old distinct-head wording applies only to historical entries.

For a well-formed verification-only PR-Agent request, run a targeted local evidence assessment through the existing local reviewer dispatch before continuing past that request. This assessment is authorized by the explicit retry for a previously failed head; on a first request it is normal verification work, not a bypass. A missing configured/reachable local reviewer leaves the request unresolved. Do not convert a draft merely to bypass an unresolved request; the existing transition still requires a successful draft gate. Retain full local code/strict validation during this assessment so it cannot hide an independent blocker.

Use the shared predicate from `review-evidence-context.py` to admit only the exact well-formed request with explicit matching verified proof. Preserve existing PR-Agent code/security classifications and unknown-format escalation. In `apply-readiness-labels.sh`, the pure inspection mode identifies this variant while default stdin classification remains conservative; loop and live readiness pass independently validated proof to the same narrow classification path. A generic environment boolean or arbitrary comment claiming verification is not an authorization source.

Name the internal pure inspection mode `--inspect-pr-agent`: return JSON with `verdict` (the existing conservative classification) and `verification_only` (boolean). The latter is true only for a structurally valid request with no independent code/security/non-compliance blocker; it does not change `verdict` by itself. Both shell consumers collect and validate proof before asking the classifier to discharge that specific request. The snapshot helper exits nonzero with metadata-only diagnostics for malformed input; a valid predicate mismatch returns an explicit unverified result. Neither condition creates a clean verdict.

On same-head replay, compare current evidence identity before replaying local evidence-based approval or a PR-Agent result cleared by that approval. Evidence changes require a new local verification even without a code commit. Reuse the existing trusted-author/write-permission rules in readiness when reading the ledger. Never clear review threads, human changes, or existing code/security blockers as a side effect of evidence verification.

### Documentation and Release Notes

Update `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`, Protocol 93's retry/second-pass section, and the loop's usage text to describe supported body/comment locations, proof verification, explicit same-head retry, preserved limits and conservative failure outcomes. Update the current 1656 smoke/proof guidance to distinguish default refusal from an authorized evidence retry, while leaving historical merged plans untouched. Review `pr-review-platform.md` for consistency; change it only where the evidence behavior needs clarification.

Add `changelog.d/2061.fixed.evidence-review-retry.md` in the implementation PR. Project placeholder architecture/database docs and AGENTS.md need no changes: no product layer, provider configuration, checkpoint policy, or branching authority changes.

## Decision-Gate Consistency Matrix

The spec's ordered Review Decision Matrix is authoritative. This table maps its branches to implementation boundaries without restating its outcomes.

| Gate inputs / spec branch | Implementing boundary | Mirror / validation |
| --- | --- | --- |
| Code/human blockers | Local result normalization and existing loop aggregation | Readiness; composed negative tests |
| Missing, malformed, unknown, or incomplete evidence | Snapshot helper and local-result validation | Loop and readiness predicate |
| Explicit retry, current SHA, history and limits | Retry predicate, pre-dispatch guard, cycle accounting | Usage text, Protocol 93, existing retry harness |
| Retry reservation, completion, duplicate ID, historical entry and run boundary | Attempt-aware history count and pre-dispatch reservation/read-back | Cycle-count and composed dispatch suites; both telemetry axes and both existing ceilings |
| Verified/rejected proof and unchanged identity | Local assessment plus post-review snapshot/head check | Trusted history and independently fetched readiness snapshot |
| PR-Agent verification-only request vs independent code/unknown request | Pure classifier inspection and evidence-aware classification | Loop existing/polling phases and readiness issue-comment interpreter |
| Same-head evidence change | Replay identity check | Readiness current-snapshot check |

## Testing Strategy

Use dependency-free Python unit tests and the repository's mocked gh/git/reviewer shell harnesses. All fixtures are fabricated; no downstream PR export, real user comment body, credential, or private configuration is test data. Tests invoke production predicates and composed dispatch/readiness paths. Use synthetic configuration selected explicitly in disposable repositories, never inherit another checkout's local settings.

| Input class / edge case | Automated test target and observation | Coverage |
| --- | --- | --- |
| Body proof; comment proof beyond first page; Unicode/long evidence | New `tests/test-review-evidence-context.py` and existing `tests/test-local-ai-reviewer.sh`: complete context reaches mocked backend; deterministic identity independent of API ordering | AC1, AC3 |
| Comment edited/deleted; body changed; request changed; bookkeeping comment added | Snapshot unit tests: relevant changes invalidate identity; exact bookkeeping exclusion is stable; marker lookalikes remain data | AC3, AC4 |
| API/pagination/JSON failure; missing/unknown verification status or proof refs | Context and local-review tests: no verified result; no silent empty-evidence success | AC2, AC3 |
| Same-head prior findings, matching explicit retry, no artificial commit | Existing `tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`: real dispatch stub invoked, fresh verified result accepted, old history retained | AC1, AC4 |
| No explicit retry; wrong SHA; unreadable ledger; retry fails; exhausted limits | Same dispatch harness: refusal or unresolved result remains; retry accounting cannot bypass caps | AC2, AC4 |
| Repeated unsuccessful retries at one SHA, with identical needs_fixes outcomes | Existing `tests/test-pr-review-loop-cycles-labels.sh` plus `tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`: use a small synthetic cap, reserve distinct attempt IDs until it is consumed, then prove the next request causes no reviewer dispatch and reports the appropriate cap reason. Run once with a fixed run ID for the per-run ceiling and again with changing run IDs for the lifetime ceiling | AC4, AC6 |
| Historical duplicate head/result entries mixed with retries; reservation/completion duplication; interrupted reservation; malformed/conflicting attempt metadata | Cycle-count suite: historical counts unchanged; distinct retry IDs add individually; repeated records for one ID count once; a reserved-only attempt remains spent; malformed/conflicting identities produce unavailable counts and prevent dispatch | AC4, AC6 |
| Changed head during review; changed evidence during review; unrelated clean | Snapshot/dispatch/readiness tests: no current verification accepted | AC2, AC4, AC5 |
| Producer Markdown and HTML ticket headings, PR Code Verified label, multiple tickets | Existing `tests/test-pr-review-loop-pr-agent-coderabbit.sh` and `tests/test-apply-readiness-labels.sh`: verification-only requests can proceed only with matching proof | AC5 |
| Partial/not compliant, independent security/code blocker, malformed/nested/duplicate/unknown heading, quoted/fenced lookalike | Same classifier harnesses: proof does not erase another blocker; unknown remains conservative; existing code masking remains effective | AC2, AC5 |
| Trusted valid ledger vs forged/untrusted, stale, absent, wrong-repo/PR proof | Readiness harness: only trusted matching proof can clear the exact request | AC5 |
| Prompt contracts in Codex and HTTP presets | Existing `tests/test-local-codex-review-command.sh` and `tests/test-local-http-review-command.sh`: request explicit proof assessment; preserve strict modes | AC3, AC5 |

These test groups express coverage intent; fixture counts are indicative. Include `# covers:` metadata so diff-driven selection can discover new test files. Run the relevant shell suites, Python unit suite, ShellCheck, shell guard lint, shell snippet lint, Markdown lint and heuristic lint. Run GraphQL literal lint only if implementation unexpectedly changes a query; obtain live query validation before readiness in that case.

For every changed validation gate, record a planted violation at a concrete synthetic fixture path/line or exact helper invocation: missing/stale/untrusted proof must fail, and replacing only that violation with matching verified proof must pass. Include composed loop/readiness proof, not only helper-unit success. Do not create a test that merely mirrors a new condition without proving the escaped failure class.

## Seed Data

The test matrix defines the seed population: fabricated PR identities, SHA strings, body/comment revisions, PR-Agent summaries, reviewer responses and history entries generated in disposable fixtures. No database or real E2E seed applies; this repository's regression job is a placeholder. The linked runbook exercises the synthetic functional harnesses.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Evidence claim mistaken for approval | Explicit local assessment, full ordinary/strict result validation, exact request/proof binding |
| Old clean replay after evidence edit | Current identity comparison at dispatch acceptance, replay and readiness |
| Workflow summary invalidates itself | Defined bookkeeping exclusions; excluded text cannot supply proof |
| PR-Agent parsing relaxes a code/security blocker | Narrow verification-only inspection, shared predicate, negative composition tests |
| Repeated explicit retries evade execution limits | Preserve history and charge retries against existing bounds |
| Context contents reach diagnostics | File-based transport, existing redaction, hashes/references only in public ledger |

## Reversal and Recovery

Revert the implementation through a normal reviewed PR that reverses the context producer, prompt contracts, retry/replay logic and readiness consumer together. Do not deploy a partial reversal that leaves a consumer treating an unsupported verification object as approval. Preserve published history and evidence artifacts; no destructive migration, ledger rewrite, force push, or synthetic commit to a reviewed PR is part of reversal.

Before that coordinated reversal is enabled, pause automated evidence-resolution retries and identify the affected PRs from their published evidence-verification records. Withdraw their readiness through the normal owned-PR path and require a fresh ordinary review or human handoff before merging them. The prior PR-Agent classifier's conservative verification-request behavior resumes after rollback; historical verification objects are retained as audit evidence and cannot waive its unresolved request. A prior evidence-dependent clean ledger entry or label is not sufficient reversal-time readiness evidence. Keep evidence-based automation paused for an affected PR until its fresh review or human disposition is recorded; a stand-alone producer/consumer rollback without this reconciliation is unavailable.

For interrupted execution without a code rollback, retain the current ledger, re-fetch the PR head and evidence, and retry only through the existing explicit current-head route and cycle limits. Unreadable or mismatched proof remains unresolved. Synthetic regression proof must include an old/historical verification record that cannot clear an unsupported or currently unverified request.

## Implementation Order

1. Revalidate assumptions and branch from the approved base through the normal guards; use an implementation branch, not this plan branch.
2. Implement snapshot helper and regression cases, then integrate complete evidence context and explicit verification into local reviewer/presets. Commit this coherent, verified sub-part.
3. Integrate explicit retry, evidence-sensitive replay and PR-Agent verification handling with readiness. Add composed regressions and planted-violation proofs; commit the coherent verified integration.
4. Update the documentation targets above and release-note fragment, run the linked synthetic smoke and required lints/suites, and record AC coverage and proof locations in the implementation PR.
5. Perform internal two-pass review, configured external reviewer loop, regression/readiness labels and CI through Protocol 91. Preserve branches per the explicit session instruction and use durable merge admission for any authorized merge.
