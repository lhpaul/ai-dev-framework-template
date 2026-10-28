# Evidence review retry — Synthetic smoke test

## Scope

Validate [the spec](../../specs/developments/20261028125542_2061-evidence-review-retry/1_2061-evidence-review-retry_specs.md) using disposable synthetic fixtures. Implementation adds the new tests named below; this plan-stage runbook is not a claim those tests already pass.

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
