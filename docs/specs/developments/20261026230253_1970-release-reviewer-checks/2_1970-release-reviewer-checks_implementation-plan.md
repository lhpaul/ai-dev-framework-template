# Release Reviewer Check Exclusion — Implementation Plan

**Issue**: [#1970](https://github.com/lhpaul/ai-dev-framework-template/issues/1970)
**Spec**: [Approved spec](1_1970-release-reviewer-checks_specs.md)
**Smoke test runbook**: [Synthetic release reviewer checks](../../../testing/workflow/1970-release-reviewer-checks.smoke-test.md)

## Summary

**Approach**: Extend the existing configured-reviewer classification, then consume it consistently for release readiness. See Shared workflow mapping and Composed Consumer Expectations for the normative classification and consumer behavior. Preserve implementation reviewer evaluation and all other existing CI gates.

**Estimated complexity**: S. This repairs existing classification and consumption rather than introducing a new policy or architecture. Luis approved this approach and satisfied the technical checkpoint. The risk ceiling is medium, solely for #1970.

**Dependencies**: The approved spec is merged through #2055. No deployment, database, external-service configuration or new dependency is required.

## Verification Log

Repository-derived records below were gathered at `cd54297af9f8b54aeef51262ed3ea8b15d00e8f2` on 2026-10-26. Counts describe that snapshot; implementation must recheck the named consumers before editing.

| Check | Reproducible command or source | Result |
| --- | --- | --- |
| Mapping and consumers | `git grep -n 'configured_reviewer_check_names_json' cd54297a -- 'scripts/development-workflow/*.sh' ':!scripts/development-workflow/tests/**'` | Definition in workflow-lib.sh; executable consumers in pr-ci-loop.sh and pr-review-loop.sh; readiness currently has only a descriptive mapping reference |
| PR-Agent check producer | `git grep -n 'PR-Agent review' cd54297a -- .github/workflows/pr-agent.yml` | Repository-owned job name at line 25: `PR-Agent review` |
| Initial/live readiness filters and head gate | `git grep -n 'baseline_json=\|baseline_arg=\|head-changed-before-apply' cd54297a -- scripts/development-workflow/apply-readiness-labels.sh` | Both CI filters use ready-reviewer names; final head refusal remains separate |
| Existing synthetic harnesses | `git ls-tree -r --name-only cd54297a scripts/development-workflow/tests` | test-pr-ci-loop.sh, test-apply-readiness-labels.sh and lib/readiness-label-fixture.sh are available for extension |
| Template fit | `.ai-dev-workflow.yaml` template.is_template and approved spec | Template mode; generic workflow tooling correction, no downstream application framework |

## Factual Claim Evidence

Rule 1 sampling record: producer GitHub's PR CheckRun rollup; population sampled is the #2055 head `4a619f4a` check rollup returned at 2026-10-26T23:24:27Z, not all historical GitHub output. Query: `gh pr view 2055 --json headRefOid,statusCheckRollup`. Four real occurrences were examined in the order below, yielding two observed status/conclusion variants. The final occurrence added no variant; this is local saturation only, not an assertion of global completeness. Each selected entry had CheckRun as its type; the embedded name/status/conclusion preserves the relevant text even after Actions log retention expires.

| Source occurrence | Embedded name | Embedded status | Embedded conclusion |
| --- | --- | --- | --- |
| [PR-Agent job](https://github.com/lhpaul/ai-dev-framework-template/actions/runs/40417653352/job/121903864183) | PR-Agent review | COMPLETED | SUCCESS |
| [E2E job](https://github.com/lhpaul/ai-dev-framework-template/actions/runs/40417653287/job/121903867795) | E2E regression (placeholder) | COMPLETED | SKIPPED |
| [Markdown job](https://github.com/lhpaul/ai-dev-framework-template/actions/runs/40417653267/job/121903863853) | Markdown lint (spec/plan/CHANGELOG) | COMPLETED | SUCCESS |
| [Closing-scope job](https://github.com/lhpaul/ai-dev-framework-template/actions/runs/40418493665/job/121906724566) | Validate closing-keyword scope (2055) | COMPLETED | SUCCESS |

Adequacy: these real entries establish the check-name/type/status/conclusion shape and distinguish the repository-owned reviewer name from ordinary CI. They do not establish the full status distribution, especially pending/failing states. The design relies only on those structured fields and the repository-owned exact-name mapping; the conservative accepted shapes are defined in Readiness, and every unseen variant remains ordinary CI. Synthetic regressions exercise pending, failing and malformed states rather than treating this small observed population as a fixed producer contract.

Rule 6 scope and discharge points are recorded in the Decision Matrix and the named consumer paths. Rule 2's normative classification is stated in Shared workflow mapping, its accepted shapes in Readiness and consumer behavior in Composed Consumer Expectations; other sections reference those decisions. Rule 3's only codebase quantities concern the empty same-surface open-PR scope and are derived by the commands in Cross-Cutting Operational Assumption Check. Rule 4 and Rule 5 use the recorded-revision queries in Verification Log.

## Cross-Cutting Operational Assumption Check

Current invocation item list: #1970 only. Artifact owner and mutation target: this single repository, `lhpaul/ai-dev-framework-template`; approved base: `develop`.

| Surface | Value | Source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base and artifact owner | develop; current repository | Explicit invocation and merged spec #2055 | 2026-10-26, cd54297a | #1970; `gh pr list --state open --base develop --limit 100 --json number` returned an empty array | Verified |
| Existing release policy | Configured external reviewers do not gate release readiness | Protocol 05 section 7; approved spec Business Rules | 2026-10-26, cd54297a | #1970 and same-surface open PR query for workflow-lib.sh, pr-ci-loop.sh and apply-readiness-labels.sh returned none; total open develop PRs was zero | Verified |

Implementation-start re-verification must report Still valid against these sources before file edits. A new conflicting base/ownership/policy fact stops implementation until resolved; an unrelated PR alone is not a conflict.

## Classification and Edge Cases

Parser-risk applies because readiness filters structured check evidence. No new parser, regex grammar, suppression directives or config schema is introduced. Concurrent-event-source classification does not apply: this changes no listeners, timers, shared mutable state or asynchronous lifecycle. It preserves the existing ordered live revalidation against concurrent head changes. Cross-cutting checklist classification does not apply: no review/planning checklist is changed.

| Input class | Required coverage and observation | Automated test location |
| --- | --- | --- |
| Exact configured PR-Agent name, pending and failure | Release CI remains green with ordinary CI complete; readiness succeeds after live revalidation | test-pr-ci-loop.sh; test-apply-readiness-labels.sh |
| Draft pr-agent plus ready local-ai-reviewer | Mapping includes exactly the repository-owned PR-Agent check, without inventing a local reviewer check | test-pr-ci-loop.sh |
| Unconfigured reviewer or similar-name job | Failing/pending evidence stays in ordinary CI | Both harnesses |
| Ordinary pending/failing check | Existing CI refusal remains; readiness applies its existing label-specific pending rule | Both harnesses |
| Missing expected workflow | CI loop refuses despite a reviewer exemption | test-pr-ci-loop.sh |
| Malformed or unknown check evidence | No removal based on fuzzy names or a fallback unknown name; existing parse/refusal handling remains | Both harnesses |
| Initial reviewer failure followed by live reviewer pending | Release readiness still passes when ordinary CI and head remain valid | test-apply-readiness-labels.sh |
| Ordinary CI becomes pending/failing during live evaluation | Pending refuses ready-for-human-review but remains allowed for ready-for-regression; failing refuses both labels | test-apply-readiness-labels.sh |
| Head changes during readiness | Existing head-changed-before-apply refusal; no readiness label is added | test-apply-readiness-labels.sh |
| Implementation missing required reviewer evidence | Existing reviewer refusal remains even with passing ordinary CI | test-apply-readiness-labels.sh |

These are coverage classes, not a fixed scaffold enumeration. Reuse fixtures and combine equivalent cases rather than duplicating harnesses. Unknown evidence is not granted an exemption: a recognizable reviewer name alone must not hide a malformed check entry.

## Layer-by-Layer Changes

### Shared workflow mapping

- [ ] `scripts/development-workflow/workflow-lib.sh`: recognize `pr-agent` as owning the exact check `PR-Agent review`, using the existing configured-platform resolution. Update the mapping comment. Do not add a fictitious check for the comment/ledger-based local reviewer. Add a shared jq predicate alongside the existing shared rollup jq definition: a reviewer exclusion requires an exact configured name on a CheckRun with a recognized status and a coherent known conclusion (or no conclusion while pending). An entry with unknown type/status/conclusion or contradictory pending/concluded state stays in ordinary CI; malformed JSON retains existing parse-error handling. This predicate only classifies reviewer exclusions and does not redefine ordinary CI verdicts. Covers AC-1 and AC-6.
- [ ] `scripts/development-workflow/pr-ci-loop.sh`: apply that predicate consistently to the baseline and reviewer count/list/JSON projections so malformed entries cannot disappear behind the newly recognized PR-Agent name. Preserve all ordinary CI, current-head and expected-workflow logic. Covers AC-3 and AC-6.
- [ ] `scripts/development-workflow/pr-review-loop.sh`: use the same predicate at the existing expensive baseline mapping consumer; change no review dispatch or verdict requirements. Covers AC-5 and AC-6.

### Readiness

For the Shared workflow mapping predicate, pending status means QUEUED, IN_PROGRESS, WAITING, REQUESTED, PENDING or EXPECTED with an absent/null/empty conclusion. COMPLETED requires SUCCESS, FAILURE, CANCELLED, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE, NEUTRAL or SKIPPED. These deliberately conservative accepted shapes follow the existing workflow rollup classifications in workflow-lib.sh and pr-ci-loop.sh at the recorded revision; an unseen variant stays ordinary CI instead of being asserted impossible. This is repository-controlled classification policy, not a claim that the external producer has a closed output distribution.

- [ ] `scripts/development-workflow/apply-readiness-labels.sh`: introduce a distinct JSON set of CI reviewer exclusions. On `release/*`, obtain all recognized configured reviewer check names through the shared mapping and apply its safe predicate. On other heads, preserve the existing ready-reviewer-name exclusions. Both initial and live CI filters consume this same resolved set and branch handling. A configuration resolution failure escalates through the existing safe error path; it never falls back to an empty passing policy. Covers AC-1 and AC-2.
- [ ] Keep implementation reviewer requirement selection, current-head checks, ownership guard, regression pending semantics and final apply ordering unchanged. Retain unknown or malformed entries in CI evaluation rather than excluding them solely by name. Covers AC-3 through AC-6.

### Tests and release notes

- [ ] Extend `scripts/development-workflow/tests/test-pr-ci-loop.sh` with the synthetic effective reviewer configuration and the CI coverage classes above.
- [ ] Extend `scripts/development-workflow/tests/test-apply-readiness-labels.sh` using its disposable shared fixture for initial/live readiness and preserved implementation requirements. Fabricate configuration in its temporary directory; never read or copy workstation configuration.
- [ ] Add `changelog.d/1970.fixed.release-reviewer-checks.md` describing the release filtering correction. Covers AC-7 and the repository release-note requirement.

## Composed Consumer Expectations

The Verification Log's mapping search enumerates the existing consumers and the following outcomes. This is the single normative list of mapping consumer expectations for this plan.

| Consumer | Ordered path and outcome |
| --- | --- |
| pr-ci-loop.sh configured mapping call | Normalization precedes the Shared workflow mapping predicate; the remaining ordinary CI and expected-workflow evidence still decide green/red. Review requirements remain owned by the reviewer loop. |
| pr-review-loop.sh expensive_gate_baseline_checks_status | Its existing mapping call and the Shared workflow mapping predicate classify baseline CI. Draft and ready reviewer execution and verdict requirements remain unchanged. |
| apply-readiness-labels.sh new release-only mapping call | Existing ownership/branch selection precedes CI evaluation. The initial and live filters use the resolved exclusion set; remaining CI and final head revalidation can still refuse readiness. Implementation heads continue through their existing reviewer path. |

## Decision Matrix

Rows are independent constraints with cumulative blocking, following the approved spec. Every applicable existing blocker must clear; the reviewer exemption never grants readiness by itself. This plan changes no short-circuit precedence or error-reporting order.

| Scope/input | Result | Discharge point |
| --- | --- | --- |
| release/*; exact configured reviewer check with valid check evidence | Exclude reviewer contribution | Initial and live readiness CI filtering; CI loop mapping consumer |
| Other branch or unconfigured/unknown/malformed/lookalike evidence | Preserve existing classification and reviewer requirements | Existing consumer paths and synthetic negative cases |
| Ordinary CI pending/failing or expected workflow absent | Preserve existing refusal and label-specific pending rule | Initial/live CI gates and CI loop evidence gate |
| Ownership or head validation fails | Refuse mutation | Existing ownership guard and final pre-apply head gate |
| All applicable requirements pass | Existing readiness application is allowed | Existing helper mutation and post-apply verification |

## Testing Strategy

Use synthetic shell integration tests with mocked gh at the process boundary. No real release PR is mutated for tests. Seed data consists only of fabricated head SHAs, PR metadata, status-check payloads and disposable YAML created inside the existing harness temporary directories. The fixture scripts own cleanup.

Run the affected CI and readiness suites, plus staged reviewer-loop baseline tests because they consume the changed mapping. Run ShellCheck and bash syntax checks on changed shell files, Markdown lint on the fragment, and the smoke runbook. The full repository CI remains mandatory before merge.

Planted-violation proof: demonstrate an unrelated failing or missing CI fixture refuses readiness/green; change only that fixture's blocking evidence to success/present and show the valid release reviewer case passes. Record the test location and both results in the implementation PR. Also demonstrate that the new release reviewer regression fails against the unmodified implementation before applying the fix.

## Documentation Updates

None beyond the release-note fragment and this already-authored smoke runbook. Protocol 05 already specifies the desired behavior. Project docs, best-practice docs, AGENTS.md and REVIEW.md need no change because policy, architecture, commands and review obligations are unchanged.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Overbroad filtering hides ordinary CI | Medium | Medium | Exact configured names; retain malformed/unrecognized evidence; negative fixtures |
| Initial and live evaluation diverge | Medium | Medium | Same resolved JSON set in both filters; live-state regressions |
| Implementation reviewer requirements weaken | Low | Medium | Release-only readiness branch; existing reviewer-gate regression suite |
| Current head drifts | Low | Medium | Preserve final head check and exercise the drift refusal |

Rollback is a normal revert of the focused implementation commit(s); it restores conservative blocking and changes no stored data. No branch deletion is authorized.

## Implementation Order

1. Reverify operational assumptions and intended implementation branch before file edits.
2. Add synthetic reviewer configuration and release regressions; reproduce the existing failure on the old code.
3. Update the shared PR-Agent mapping and readiness release-only exclusion set together, then verify both affected suites and the staged baseline consumer tests.
4. Complete the negative and live-head regression proofs. Commit the coherent tested fix and tests promptly; do not commit failing intermediate code.
5. Add the release-note fragment, perform pre-submission self-review against the spec and this plan, and complete review, CI, readiness, merge-session and tracker gates.

Residual verification: the shared classification predicate requires the scope-residual gate before readiness. Re-run the Verification Log's mapping query and search for the new predicate across workflow scripts; supply evidence that every consumer in Composed Consumer Expectations uses the intended classification and that both readiness evaluations agree. Implementation must classify and verify this bounded residual scope through scope-residual-gate.sh. Additional unrelated consumers or architecture changes beyond #1970 require a stop and report.
