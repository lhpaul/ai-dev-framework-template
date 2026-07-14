# Bounded Prelude Base-Branch Resolver Label Scope - Implementation Plan

**Spec**: [1_1204-bounded-prelude-base-branch-resolver-label-scope_specs.md](1_1204-bounded-prelude-base-branch-resolver-label-scope_specs.md)
**Smoke test runbook**: [1204-bounded-prelude-base-branch-resolver-label-scope.smoke-test.md](../../../testing/workflow/1204-bounded-prelude-base-branch-resolver-label-scope.smoke-test.md)

---

## Summary

**Approach**: Tighten base-branch selection in the shared bounded-prelude
resolver by making explicit-list integration labels scope-aware, adding visible
fallback warnings, and validating any current-repository integration base before
the prelude adopts it. Preserve the read-only prelude contract by using only
metadata reads and remote head probes.

**Estimated complexity**: M

**Rationale**: The change is localized to shell workflow tooling, but it touches
operator-facing JSON/text output, GitHub label fixtures, remote branch
validation, and regression tests across the explicit-list and epic/single-item
resolver paths.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` | `template.is_template: true`; spec is workflow-tooling generic and passes. |
| Existing resolver path | `rg -n "integration-branch\|baseBranch\|baseReason" scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/run-bounded-prelude.sh` | Base is selected in `run-epic-scope-resolver.sh`; `run-bounded-prelude.sh` forwards it into the confirmation summary. |
| Explicit-list implementation | `nl -ba scripts/development-workflow/run-epic-scope-resolver.sh \| sed -n '745,785p'` | `--items` and epic scopes share one base-selection block; one unique label currently selects `develop-<slug>`. |
| Label lookup behavior | `nl -ba scripts/development-workflow/run-epic-scope-resolver.sh \| sed -n '457,501p'` | `resolve_scope_pr_bases` appends each item label-derived base before enrichment. |
| Existing tests | `find scripts/development-workflow/tests -maxdepth 1 -type f -name 'test-run-*.sh' \| sort` | Resolver coverage exists in `test-run-epic-scope-resolver.sh` and prelude output coverage exists in `test-run-bounded-prelude.sh`. |
| Runbook location pattern | `find docs/testing/workflow -maxdepth 1 -type f -name '*.smoke-test.md' \| sort` | Workflow smoke runbooks live under `docs/testing/workflow/`. |
| Cross-cutting checklist search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/` | Used only to classify this plan; no new cross-cutting checklist is introduced. |

---

## Plan Classifications

### Parser Risk

Not applicable under Protocol 02's deterministic parser-risk signals. The
implementation changes shell resolver logic over GitHub label JSON and branch
names, but it does not add or materially change a parser, scanner, linter,
regex engine, or structured-text rule engine. The testing strategy still names
concrete label and branch edge cases because the bug is boundary-sensitive.

### Cross-Cutting Checklist

Not applicable. The plan does not introduce or modify a safety, quality, or
compliance checklist that every future feature plan or implementation must
satisfy.

### Concurrent Event Sources

Not applicable. The workflow scripts run as synchronous CLI commands and do not
introduce concurrent listeners, timers, queues, or shared mutable state across
execution contexts.

### API / CLI Surface

Applies. The bounded prelude and resolver are CLI/JSON surfaces consumed by
agents and humans. Any new warning or validation data must be additive in JSON
and must preserve existing fields: `baseBranch`, `baseAmbiguous`, `baseReason`,
`baseBranchAppliesTo`, `baseBranchValidationNote`, `items`, and `groups`.

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] `scripts/development-workflow/run-epic-scope-resolver.sh` - add a
      read-only base-selection helper that evaluates integration labels by
      scope source and emits structured warning data.
- [ ] `scripts/development-workflow/run-epic-scope-resolver.sh` - for explicit
      `--items` scope, select an integration base only when every resolved item
      has the same `integration-branch:<slug>` label; otherwise select
      `develop` and report partial or mixed-label fallback.
- [ ] `scripts/development-workflow/run-epic-scope-resolver.sh` - validate a
      selected current-repository integration base with `git ls-remote --heads
      origin <branch>` before adopting it; if the branch is missing, fall back
      to `develop` with a warning.
- [ ] `scripts/development-workflow/run-epic-scope-resolver.sh` - preserve
      explicit `--base` override precedence and do not reinterpret a human
      supplied base as label-derived.
- [ ] `scripts/development-workflow/run-epic-scope-resolver.sh` - preserve
      workflow-hub repository-mode semantics by not validating product
      implementation branches against the hub remote; surface deferred
      validation in the summary instead of silently claiming validation passed.
- [ ] `scripts/development-workflow/run-bounded-prelude.sh` - include resolver
      warnings and validation status in the operator-facing confirmation summary
      without weakening the read-only guarantee.

### Tests

- [ ] `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` -
      extend the mock `gh` and `git` fixtures to cover no-label, partial-label,
      mixed-label, valid shared-label, missing shared-branch, and validation
      failure scenarios for explicit item lists.
- [ ] `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` -
      add assertions that no mutating GitHub commands are invoked while warnings
      and branch validation are produced.
- [ ] `scripts/development-workflow/tests/test-run-bounded-prelude.sh` - add a
      fixture asserting that confirmation-summary scope lines expose the
      selected base, base source/reason, read-only guarantee, and resolver
      warning when fallback occurs.

### Documentation

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` - document
      label-scope warnings, remote-branch validation, and additive warning JSON
      for bounded prelude output.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      clarify that label-derived integration bases must be validated or marked
      as validation-deferred according to repository mode.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` -
      align explicit-list handoff guidance with the bounded-prelude resolver:
      partial or mixed labels do not override the batch base.
- [ ] `.agents/skills/run-items/SKILL.md`, `.claude/commands/run-items.md`, and
      `.cursor/commands/run-items.md` - clarify the explicit-list default to
      `develop` and the shared valid integration-label exception, if the
      implementation keeps that exception.
- [ ] `.agents/skills/run-epic/SKILL.md`, `.claude/commands/run-epic.md`, and
      `.cursor/commands/run-epic.md` - clarify remote-validation behavior for
      label-derived integration bases.

### Infrastructure / Configuration

- [ ] No infrastructure or persistent configuration changes.

### Database / Data Layer

- [ ] None.

### Frontend / UI

- [ ] None.

---

## Base-Resolution Decisions

1. **Explicit `--base` wins**: A human-supplied base remains authoritative and
   keeps the existing `supplied --base override` reason.
2. **Explicit-list all-or-develop rule**: In `scopeSource=items`, a label-derived
   integration base is eligible only when every item has exactly the same
   integration label.
3. **Partial labels fall back**: If only a subset of explicit-list items has an
   integration label, set `baseBranch` to `develop` and emit a partial-label
   warning naming the label and affected items.
4. **Mixed labels fall back**: If explicit-list items contain more than one
   integration label, set `baseBranch` to `develop` and emit a mixed-label
   warning naming the labels and affected items.
5. **Remote existence check**: A label-derived current-repository integration
   base is adopted only after `git ls-remote --heads origin <branch>` confirms
   the remote branch exists.
6. **Validation failures are visible**: If the remote check fails or finds no
   branch, select `develop` and add a warning that explains whether validation
   failed or the branch was missing.
7. **Read-only behavior remains strict**: The resolver may read tracker labels,
   PR state, repository mode, and remote refs only. It must not mutate labels,
   branches, tracker status, PRs, comments, or issues.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, workflow smoke runbook.

**Key scenarios to test**:

1. Explicit-list no-label batch selects `develop` without warning (AC1).
2. Explicit-list partial-label batch selects `develop` and warns with the label
   and affected item numbers (AC2, AC8).
3. Explicit-list mixed-label batch selects `develop` and warns with every
   conflicting label (AC3, AC8).
4. Explicit-list shared label plus existing remote branch selects
   `develop-<slug>` and reports validation success (AC4).
5. Explicit-list shared label plus missing remote branch selects `develop` and
   warns about the missing branch (AC5).
6. Remote validation command failure selects `develop` and reports validation
   failure instead of silently adopting the integration base (AC6).
7. Bounded-prelude text and JSON output preserve the read-only guarantee and
   expose selected base plus selection reason (AC7, AC8).
8. Single-item or epic-scoped label-derived integration base still works when
   valid, while a missing current-repository remote branch is not adopted
   silently (AC9).

**Smoke test runbook**:
`docs/testing/workflow/1204-bounded-prelude-base-branch-resolver-label-scope.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh`
- `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `shellcheck scripts/development-workflow/run-epic-scope-resolver.sh scripts/development-workflow/run-bounded-prelude.sh scripts/development-workflow/tests/test-run-epic-scope-resolver.sh scripts/development-workflow/tests/test-run-bounded-prelude.sh`

---

## Seed Data

No persistent seed data is required. The implementation tests should use the
existing shell harness style with mocked `gh` and `git` commands, fixture issue
numbers, fixture labels, and temporary directories.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` - document
      base-selection warnings, validation status, and read-only remote checks.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` -
      align integration-base validation language with the resolver behavior.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` -
      remove or qualify any guidance implying one label on one explicit-list
      item can force the whole batch base.
- [ ] `.agents/skills/run-items/SKILL.md` - align command alias guidance with
      the resolver's explicit-list label-scope contract.
- [ ] `.claude/commands/run-items.md` - same as above.
- [ ] `.cursor/commands/run-items.md` - same as above.
- [ ] `.agents/skills/run-epic/SKILL.md` - document label-derived base
      validation.
- [ ] `.claude/commands/run-epic.md` - same as above.
- [ ] `.cursor/commands/run-epic.md` - same as above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Workflow-hub product bases are validated against the wrong remote. | Medium | Medium | Use existing `baseBranchAppliesTo` semantics; validate only current-repository bases and mark product-remote validation as deferred. |
| New warning JSON breaks consumers expecting a fixed schema. | Low | Medium | Add warnings as optional/additive fields and preserve existing field names and types. |
| Branch validation introduces network flakiness. | Medium | Low | Fail safe to `develop` with a visible validation-failure warning; keep tests mocked and deterministic. |
| Partial-label fallback hides valid integration intent for a subset. | Low | Medium | Warning names affected items so operators can rerun a narrower batch or fix labels before mutation. |

---

## Code Samples

No production code samples are included. The implementation should keep shell
helpers small and testable rather than copying large snippets from this plan.

---

## Implementation Order

1. Update `scripts/development-workflow/run-epic-scope-resolver.sh` with a
   helper that summarizes integration labels per in-scope item after
   `items_json` is built.
2. Add explicit-list base-selection logic that distinguishes no labels, partial
   coverage, mixed labels, and one shared label across every item.
3. Add a current-repository remote-head validation helper for label-derived
   integration bases; wire missing-branch and validation-failure fallbacks to
   `develop` with structured warnings.
4. Preserve `--base` override behavior and repository-mode ownership semantics,
   especially workflow-hub validation deferral.
5. Extend resolver JSON and text output with optional warning and validation
   fields while preserving existing fields.
6. Update `run-bounded-prelude.sh` confirmation summary to surface resolver
   warnings and branch-validation status.
7. Extend `test-run-epic-scope-resolver.sh` mocked label and branch fixtures for
   no-label, partial-label, mixed-label, valid shared-label, stale shared-label,
   and remote-validation-failure cases.
8. Extend `test-run-bounded-prelude.sh` to verify warning and base-selection
   visibility in the confirmation summary.
9. Update the documentation files listed in **Documentation Updates**.
10. Run the regression commands listed in **Testing Strategy** and then execute
    the smoke test runbook.
11. Do not update `CHANGELOG.md` in the implementation-plan PR. The future
    implementation PR should add an `[Unreleased]` entry under `Fixed` using:
    `- **Bound bounded-prelude integration labels** (#1204): Prevent stale or partial integration-branch labels from redirecting explicit-list batches away from develop.`
