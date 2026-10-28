# Evidence review retry — Synthetic smoke test

## Scope

Validate [the spec](../../specs/developments/20261028125542_2061-evidence-review-retry/1_2061-evidence-review-retry_specs.md) using disposable synthetic fixtures. The synthetic suites below exercise context collection, explicit verification, durable retry accounting, dispatch and readiness.

No live downstream PR, private local configuration, credential, or user data is a fixture. Use explicit synthetic reviewer/config settings and mocked GitHub responses. No force push, branch deletion, checkpoint-policy edit, or live merge is part of this runbook.

## Preconditions

- Implementation branch includes the production changes and synthetic regression harnesses from the plan.
- Python 3, Bash, jq and git are available.
- Run from the implementation checkout with a clean worktree.

## Checks

1. Run `python3 scripts/development-workflow/tests/test-review-evidence-context.py`. Confirm full body/comment context, deterministic ordering, paginated collection coverage, edit/delete invalidation and conservative unavailable evidence handling.
2. Run `bash scripts/development-workflow/tests/test-local-ai-reviewer.sh`. Confirm proof can be read from the body or a comment, including long/Unicode content. Missing, incomplete or unrelated proof cannot yield explicit verified evidence.
3. Run `bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`. Confirm a prior same-head finding followed by published synthetic proof and an explicit matching retry invokes a fresh reviewer without a new commit. History persists and code findings remain blocking.
4. In that dispatch suite, confirm wrong-head/no-flag/unreadable-history/exhausted-limit cases refuse, a failed retry stays unresolved, and head/evidence drift during a pass cannot approve.
   Run `bash scripts/development-workflow/tests/test-pr-review-loop-cycles-labels.sh` as well. With a synthetic small cap and the same SHA/result for every failure, verify each distinct retry reservation consumes a slot and the next request cannot dispatch. Check fixed-run per-run exhaustion and changing-run lifetime exhaustion. Mixed historical entries retain their previous counts; reservation/completion records for one attempt count once, a crashed reserved attempt remains spent, and malformed/conflicting attempt metadata refuses dispatch.
5. Run `bash scripts/development-workflow/tests/test-pr-review-loop-pr-agent-coderabbit.sh`. Confirm the verification-only PR-Agent variant proceeds after explicit matching local verification; ordinary publication, unrelated clean review, malformed requests and independent blockers do not clear it.
6. Run `bash scripts/development-workflow/tests/test-apply-readiness-labels.sh`. Confirm loop/readiness agreement for current trusted verification and refusal of stale, absent, forged or wrong-identity evidence.
7. Run the Codex and HTTP prompt suites named in the plan. Confirm ordinary evidence assessment is requested while strict spec/plan mode remains intact.
8. Inspect the implementation PR's planted-violation record. For each changed gate, locate the exact synthetic fixture/line or helper invocation, see its failing result with the violation present, and its passing result after only that violation is corrected.

## Expected Outcome

The successful fixture publishes evidence and obtains fresh reviewer verification at the original SHA. All unresolved, code-blocking, unavailable, stale and unauthorized cases remain blocked. Each suite exits zero and the implementation PR records its run and proof locations.

## Evidence to Record

Record the implementation commit, commands, suite outcomes, synthetic proof locations and the AC mapping. Do not copy private configuration or real comment bodies into the report. No visual-fidelity check applies because the issue supplies no UI or design assets.

## Planted-Violation Evidence

All records below use fabricated inputs and mocked transport/model responses.
The implementation PR records the reviewed commit and final suite outcomes.

| Guard | Violation and observed refusal | Corrected fixture and observed success |
| --- | --- | --- |
| Retry pre-dispatch cap | `test-pr-review-loop-cycles-labels.sh`, `_retry2061_plant`, removes the actual per-run guard in a subshell: three dispatches and four spent cycles exceed the limit | `_retry2061_exercise run` uses the production guard: two retries after one historical cycle; the next invocation reports `max_cycles_exceeded` without dispatch |
| Lifetime and durable reservation | Shared `tests/lib/review-retry-fixture.sh` changes run IDs without resetting lifetime; uncertain writes and mismatching readback cause zero dispatches while persisted reservations remain spent | Matching readback permits a real dispatch stub; reservation/completion share one UUID and count once |
| Explicit verification | `test-review-evidence-context.py`, `test_shared_loop_readiness_predicate_requires_trusted_current_proof`: unverified, stale, deleted, forged, wrong-head/request and bookkeeping-only proof stay pending | The same current snapshot with trusted explicit verified proof returns clean |
| Local reviewer context and proof | `test-local-ai-reviewer.sh`, the `#2061` cases: missing/unverified/stale proof, an independent code finding, evidence drift and API failure cannot approve | Full body and second-page proof reach the backend; explicit matching proof is accepted and its snapshot hash survives metadata transport |
| Loop targeted review and replay | `test-pr-review-loop-pr-agent-coderabbit.sh`, `2061_targeted_*`, and staged-gates `2061_*`: unverified proof, prior failure without retry, code findings and stale fingerprints refuse clearance | A configured fresh local assessment at the original SHA verifies proof; current fingerprint and compact metadata survive replay |
| Readiness | `test-apply-readiness-labels.sh`, `2061_*`: unverified, edited, forged or independently security-blocking proof applies no label | Only the matching trusted verified fixture returns `labeled` |

The head-binding regression also composes the actual PR-Agent handler output,
the production platform processor and the trusted readiness predicate for both
the existing-summary and polling phases (`_2061_platform_entry` in
`test-pr-review-loop-pr-agent-coderabbit.sh`). Removing the two successful
`REVIEWED_HEAD` emissions in a disposable subshell makes seven assertions fail:
the emitted head is missing, the persisted head is empty and readiness remains
`verification_pending`. With the emissions restored, all 27 targeted assertions
pass. The ledger in this regression receives the processor's actual head data;
the test does not supply a reviewed head directly.

## Immutable cumulative history recovery

Run `bash scripts/development-workflow/tests/test-reviewer-loop-history.sh` and
the cycle harness area 10c. Fork two synthetic histories, copy a cumulative
prefix, and persist reservation/completion records with the same UUID plus a
second UUID. Verify historical accounting is unchanged, distinct attempts exhaust
the cap, and interrupted reservations remain spent. Original comment objects
must remain unchanged. Quote the summary markers inside an ordinary comment; it
must not become an authoritative summary. Malformed or unavailable histories
must keep accounting unavailable, including when a newer valid snapshot exists.

For each summary write, verify one POST and an independent GET of the returned
ID and exact body. Plant a failed/uncertain POST, a failed GET, a mismatching
body, and a mismatching ID. Each must stop without PATCH or repeated POST; an
uncertain stored reservation must still be counted on the next read.
