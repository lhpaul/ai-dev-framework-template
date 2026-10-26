# Release Reviewer Check Exclusion — Synthetic Smoke Test

**Issue**: [#1970](https://github.com/lhpaul/ai-dev-framework-template/issues/1970)
**Spec**: [Release reviewer exclusion](../../specs/developments/20261026230253_1970-release-reviewer-checks/1_1970-release-reviewer-checks_specs.md)

## Preconditions

Use the implementation checkout with Bash, Python 3 and jq. Test only fabricated data in the committed shell harnesses. No design assets or UI fidelity checks apply.

## Steps

1. Run `bash scripts/development-workflow/tests/test-pr-ci-loop.sh`.
2. Confirm the synthetic pr-agent/local-ai-reviewer configuration recognizes `PR-Agent review`; pending and failing reviewer checks do not prevent green CI for a valid release fixture.
3. Confirm an unrelated pending/failing check and missing expected workflow evidence retain their blocking results. Lookalike and unconfigured reviewer names receive no exemption.
4. Run `bash scripts/development-workflow/tests/test-apply-readiness-labels.sh`.
5. Confirm release readiness passes both initial and live evaluation with pending/failing configured reviewer checks, while unrelated live CI failures and head changes prevent readiness application.
6. Confirm the implementation fixture without required reviewer evidence still refuses readiness, and malformed/unknown evidence is not silently filtered away.
7. Run `bash scripts/development-workflow/tests/test-pr-review-loop-staged-gates.sh` to check the shared baseline consumer remains compatible.

## Expected Result

All harness assertions pass with no real GitHub writes. Release reviewer exclusion agrees between CI and initial/live readiness. Ordinary CI, reviewer requirements for implementation PRs, ownership and head freshness retain their existing gates.

## Failure Handling

Capture the synthetic assertion name and exit status. Fix only in-scope regression failures. Stop and report if repair requires changed release policy, workflow bypass, architecture changes or risk above medium.
