# Reduce Shell Workflow Review-Fix Churn — Implementation Plan

**Tracker brief**: [#910 Reduce shell workflow review-fix churn before PR submission](https://github.com/lhpaul/ai-dev-framework-template/issues/910)
**Smoke test runbook**: [docs/testing/workflow/910-reduce-shell-workflow-review-fix-churn.smoke-test.md](../../../testing/workflow/910-reduce-shell-workflow-review-fix-churn.smoke-test.md)

---

## Summary

**Approach**: Extend the existing diff-based `workflow-shell-guard-lint.py` guard
instead of adding another prose-only checklist. The implementation should add targeted
rules for the shell patterns that caused PR #908 review churn, expand fixture coverage,
and update implementation guidance so agents run the guard locally before opening PRs
that touch workflow shell scripts.

**Estimated complexity**: M

**Rationale**: The scanner already parses added diff lines and is wired into CI. The
work is a focused parser/lint extension with new fixtures and documentation updates,
not a rewrite of workflow scripts.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `b4b722e` |
| Template-fit check | `.ai-dev-workflow.yaml` has `template.is_template: true`; #910 brief concerns repository workflow tooling | Passes; generic template workflow improvement |
| Workflow shell scripts in scope | `find scripts/development-workflow -maxdepth 1 -name '*.sh' \| sort \| wc -l` | 28 top-level workflow shell scripts |
| Existing shell test harnesses | `find scripts/development-workflow/tests scripts/lint/tests -name 'test-*.sh' \| sort \| wc -l` | 21 shell harnesses |
| Existing shell guard entrypoint | `rg -n "workflow-shell-guard-lint\|SH001" scripts/lint .github/workflows/shellcheck.yml` | Guard exists, tests exist, and CI runs it from `shellcheck.yml` |
| Existing implementation guidance | `rg -n "Shell Script Quality Checklist\|Pre-Submission Self-Review" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Protocol already requires shell checklist and pre-submission pass |
| Cross-cutting guidance surfaces | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol\|workflow-shell-guard-lint\|Shell Script Quality Checklist" .claude/agents/ .cursor/agents/ .codex/skills/ docs/ AGENTS.md REVIEW.md 2>/dev/null \| sort` | Developer agents, Codex implementer skill, `REVIEW.md`, best-practices, protocol 03, and lint README are relevant surfaces |

---

## Layer-by-Layer Changes

### Scripts / Tooling

- [ ] Extend `scripts/lint/workflow-shell-guard-lint.py` with additional
  diff-based rules. Keep the default scope to added lines under
  `scripts/development-workflow/**/*.sh` so historical debt does not block
  unrelated PRs.
- [ ] Preserve the existing `--diff-file` test mode and `--base-ref` CI mode.
- [ ] Keep suppressions explicit and local. Existing `workflow-shell-guard: allow
  SH001 - <reason>` semantics should remain valid; new rules should use the same
  shape with their own rule IDs, for example `workflow-shell-guard: allow SH003 -
  <reason>`.

### Tests

- [ ] Expand `scripts/lint/tests/test-workflow-shell-guard-lint.sh` with one
  failing fixture, one passing fixture, and one suppression fixture for each new
  rule.
- [ ] Add at least one continuation-line fixture where a risky pattern spans two
  added diff lines.
- [ ] Add one out-of-scope fixture proving the rule does not apply outside
  `scripts/development-workflow/**/*.sh`.

### CI / Configuration

- [ ] Keep `.github/workflows/shellcheck.yml` running the shell guard. Update the
  workflow only if a new file path must be included in the trigger list.
- [ ] Do not add a new CI workflow; extend the existing ShellCheck workflow so
  shell quality remains a single gate.

### Documentation / Protocols

- [ ] Update `scripts/lint/README.md` with the new rule IDs, examples, and
  suppression syntax.
- [ ] Update `docs/best-practices/1-general.md` to point workflow-script authors
  at the shell guard in addition to ShellCheck.
- [ ] Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
  so the implementation-stage ShellCheck sections also run
  `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref <base>`.
- [ ] Update `.claude/agents/developer.md` and `.cursor/agents/developer.md`
  because both duplicate the shell checklist summary.
- [ ] Update `.codex/skills/workflow-implementer/SKILL.md` only if the
  implementation protocol reference is not enough for Codex to run the new guard
  before draft PR creation.
- [ ] Confirm `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
  `.codex/skills/workflow-plan-writer/SKILL.md` do not need text changes. These
  files appeared in the cross-cutting search because they reference the planning
  protocol, but this change affects implementation-stage shell verification.
- [ ] Update `REVIEW.md` so reviewers treat missing shell guard execution as an
  important finding on workflow shell PRs.

---

## Testing Strategy

**Test types**: Unit-style shell harness, static checks, and smoke verification.

**Key scenarios to test**:

1. New risky added lines fail with precise file, line, rule ID, and message.
2. Safe equivalents pass without suppressions.
3. Intentional exceptions pass only with inline rule-specific rationale.
4. Existing SH001 behavior and tests remain unchanged.
5. CI still runs the guard from the ShellCheck workflow.

**Smoke test runbook**: `docs/testing/workflow/910-reduce-shell-workflow-review-fix-churn.smoke-test.md`

### Parser-Risk Addendum

This plan is parser-risk because it changes a diff scanner under `scripts/lint/`.

**Edge-case enumeration**:

- Added-line rule match with the risky command on one line.
- Continuation-line rule match where the logical command spans two added lines.
- Negative lookalike where the same text appears in a comment.
- Negative lookalike outside `scripts/development-workflow/**/*.sh`.
- Suppressed finding with a rule-specific inline rationale.
- Suppression for the wrong rule ID must not suppress the finding.
- Multiple findings in one diff should report all findings, not just the first.

**Unit test mapping**:

- `scripts/lint/tests/test-workflow-shell-guard-lint.sh`
  - `critical_suppression_fails` and `continued_critical_suppression_fails`
    continue to cover SH001.
  - Add one failing, one passing, and one suppression test for each new rule.
  - Add a multi-finding fixture that confirms all findings are reported.

**Suppression semantics**:

- Recognized directives: `workflow-shell-guard: allow <RULE_ID> - <reason>`.
- Placement: same added logical line as the finding.
- Multiple suppressions: allow multiple directives on the same line only when
  each names a distinct rule ID and has its own rationale.

### Proposed Rule Set

- **SH002: `local` command-substitution masking** — flag `local NAME=$(...)`,
  `declare NAME=$(...)`, and `export NAME=$(...)` in functions. Safe form:
  declare first, assign on a separate line, and check the assignment result when
  it drives control flow.
- **SH003: unguarded control-flow `jq -r` extraction** — flag added assignments
  where `jq -r` output feeds a scalar used by later logic without `-e` or an
  explicit exit-code guard. Exempt display-only pipelines that are not assigned.
- **SH004: unanchored branch-prefix grep** — flag branch prefix checks such as
  `grep "fix/"` or `grep "feature/"` that can match substrings like `hotfix/`.
  Safe forms anchor the prefix, use a `case`, or use a more precise regex.
- **SH005: bash 4 associative array syntax** — flag `local -A` and `declare -A`
  in workflow scripts because this repo supports macOS bash 3.2.

---

## Seed Data

No application seed data is required. Test data is synthetic unified-diff
fixtures generated inside `scripts/lint/tests/test-workflow-shell-guard-lint.sh`.

---

## Documentation Updates

- [ ] `scripts/lint/README.md` — document all shell guard rules and suppression
  examples.
- [ ] `docs/best-practices/1-general.md` — add the shell guard to the shell
  scripting guidance.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
  — add the guard command to implementation pre-submission checks for workflow
  shell PRs.
- [ ] `.claude/agents/developer.md` — mirror the new developer guidance.
- [ ] `.cursor/agents/developer.md` — mirror the new developer guidance.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — update only if protocol
  delegation is insufficient after implementation review.
- [ ] `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
  `.codex/skills/workflow-plan-writer/SKILL.md` — review and leave unchanged
  unless implementation discovers planning-stage wording that directly conflicts
  with the new implementation-stage guard.
- [ ] `REVIEW.md` — add reviewer expectation for the guard on workflow shell
  changes.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Regex rules over-match legitimate shell | Med | Med | Keep rules diff-scoped, add negative fixtures, and require local suppressions with rationale |
| New rules miss multiline shell constructs | Med | Med | Reuse and extend existing logical-line continuation handling before adding rule matching |
| Agents skip the new guard locally | Med | Low | Update protocol 03 and developer agent guidance; CI remains the enforcement fallback |
| Existing historical debt blocks unrelated PRs | Low | Med | Keep default behavior added-line-only against `origin/develop...HEAD` |

---

## Code Samples

No production-ready code samples are required in the plan. Implementation should
prefer named regular expressions and small predicate helpers in
`workflow-shell-guard-lint.py` so each rule has an isolated test path.

---

## Implementation Order

1. Extend `scripts/lint/workflow-shell-guard-lint.py` with named rule constants,
   per-rule suppression matching, and predicates for SH002 through SH005.
2. Add fixtures and assertions to `scripts/lint/tests/test-workflow-shell-guard-lint.sh`
   for all parser-risk edge cases listed above.
3. Run `bash scripts/lint/tests/test-workflow-shell-guard-lint.sh` and confirm the
   output reports all tests passing.
4. Run `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   on the implementation branch and confirm the branch's own added lines pass.
5. Run ShellCheck on changed shell files.
6. Update `scripts/lint/README.md`, `docs/best-practices/1-general.md`, protocol
   03, developer-agent guidance, and `REVIEW.md` per the documentation section.
7. Re-run markdown lint and the heuristic lint against changed docs.
8. Add this CHANGELOG entry under `[Unreleased]` / `### Changed`:
   `- **Reduce shell workflow review-fix churn** (#910): Extend the workflow shell guard to catch high-churn shell patterns before PR submission.`
9. Complete the pre-submission self-review pass and include the shell guard result
   in the implementation PR description.
