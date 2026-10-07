# Consumer Workflow Test Portability — Smoke Test

**Issue**: [#1873](https://github.com/lhpaul/ai-dev-framework-template/issues/1873)
**Spec**: [Consumer portability](../../specs/developments/20261007000619_1873-consumer-test-portability/1_1873-consumer-test-portability_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261007000619_1873-consumer-test-portability/2_1873-consumer-test-portability_implementation-plan.md)

## Preconditions

- Use Bash, Python 3, Git, and the existing suites' dependencies, including jq.
- Prepare separate disposable template and consumer trees from versioned files;
  copy no ignored local configuration, credentials, dependencies, or .git.
- Initialize and commit each fixture with a test Git identity before running suites.
- Keep template historical documents in the template tree. In the consumer tree,
  omit template development documents and historical smoke runbooks, supply
  consumer-owned agent guidance, set consumer mode, and select a different
  supported reviewer from the template's shipped runner.
- Run suites sequentially within each tree because existing tests swap config.

## Step 1: Execute template baselines

**Maps to**: AC3, AC5.

Run the affected suites from the fixture root:

```bash
bash scripts/development-workflow/tests/test-consumer-tree-test-gating.sh
bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh
bash scripts/development-workflow/tests/test-add-backlog-item.sh
bash scripts/development-workflow/tests/test-framework-mode-type-routing.sh
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh
```

**Expected**: Each exits zero. Template defaults are checked, and framework
refusal/routing assertions retain their existing coverage.

## Step 2: Execute consumer baselines

**Maps to**: AC1, AC2, AC3, AC5.

Run Step 1's commands in the committed consumer tree, capturing their output
into consumer-gating.log, consumer-step7a.log, consumer-backlog.log,
consumer-routing.log, and consumer-reviewer.log respectively. Each command
must still exit zero; retain stderr with stdout for the evidence.

**Expected**: Each exits zero; template-only checks report explicit skips.
Alternate reviewer selection, consumer-owned guidance, absent historical
runbooks, and absent historical plan/spec documents do not cause false failures.
Shared routing/refusal and supported-reviewer checks still execute.

## Step 3: Execute planted violations

**Maps to**: AC4, AC5.

In both trees, run the following; also capture the consumer run output as
consumer-plants.log:

```bash
bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh --prove-plants
```

**Expected**: Each executed plant reports FAIL at its concrete source file/line
and PASS after repair. The template reviewer-default plant runs in the template;
its consumer skip is visible. Shared plants, including supported-reviewer
validation, still run in both modes. The routing suite's guidance plant from
Steps 1-2 is detected and repaired in both modes.

## Step 4: Verify restoration and issue coverage

**Maps to**: AC2, AC3, AC5.

In the consumer tree, require the visible skip markers with these read-only
assertions. A missing marker exits nonzero even if its suite passed:

<!-- workflow-shell-contract: bash -->
```bash
bash -euo pipefail <<'BASH'
grep -q '^SKIP: is_template_live_repo_config' consumer-gating.log
grep -q '^SKIP: D-9 ' consumer-step7a.log
grep -q '^SKIP: D-9 plant' consumer-plants.log
grep -q '^SKIP: template historical runbook checks' consumer-routing.log
BASH
```

Compare each tree's config and guidance before and after its suites. Review the
implementation diff and record disposition for each failing surface listed in
#1873, including the portion already addressed by #1874.

**Expected**: Original inputs are restored. Runtime scripts, live reviewer
policy, project-owned guidance, and sync behavior are unchanged by this repair.
The optional synthetic-consumer CI job is outside this repair's scope.

## Assertions Checklist

- [ ] Both mode baselines pass.
- [ ] Missing template history is handled.
- [ ] Shared refusal/routing assertions execute in both modes.
- [ ] Template-only skips are explicit.
- [ ] Planted fail/repair proofs preserve shared detection.
- [ ] Fixture config and guidance are restored.
