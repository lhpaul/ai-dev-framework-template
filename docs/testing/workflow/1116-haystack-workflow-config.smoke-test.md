# Smoke Test Runbook: Haystack Workflow Configuration

**Feature**: Haystack workflow configuration
**Spec**: [Haystack Workflow Configuration - Spec](../../specs/developments/20260702113258_1116-haystack-workflow-config/1_1116-haystack-workflow-config_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are in a clean checkout of this repository.
- [ ] `gh`, `git`, `jq`, `bash`, and `python3` are available.
- [ ] The implementation branch for #1116 is checked out.
- [ ] The Haystack CLI is available if running the reviewer against a real PR;
      otherwise use the automated shell tests with mocked Haystack responses.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Shared config fixture | Temporary `.ai-dev-workflow.yaml` containing `review.haystack` |
| Local config fixture | Temporary `.ai-dev-workflow.local.yaml` overriding shared values |
| Mock PR target | `owner/repo#123` in `test-haystack-reviewer.sh` |
| Mock transient payload | JSON with a non-empty `status` field |
| Mock completed payload | JSON without a `status` field and with `findings` |

---

## Smoke Test Steps

### Step 1: Validate default omission behavior

**Maps to**: AC-1, AC-2

1. Run `bash scripts/development-workflow/validate-workflow-config.sh`.
2. Run `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
3. Confirm the resolver tests include a config with no `review.haystack`
   section and that it remains valid.

**Expected result**: Existing repositories without `review.haystack` validate and
keep current Haystack defaults.

### Step 2: Validate configured Haystack defaults

**Maps to**: AC-1, AC-3

1. In the resolver test output, confirm valid `review.haystack` fixtures cover:
   `major_is_blocking`, `poll_interval_sec`, `timeout_sec`,
   `stop_rule.max_triage_rounds`, and `stop_rule.no_progress_cycles`.
2. Run `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`.
3. Confirm the reviewer tests exercise config-derived timeout, poll interval,
   major policy, max triage rounds, and no-progress cycles.

**Expected result**: Valid repository config values are consumed by the reviewer
and affect Haystack review behavior.

### Step 3: Validate override precedence

**Maps to**: AC-4

1. Confirm `test-workflow-config-resolver.sh` includes shared-plus-local
   precedence coverage for `review.haystack`.
2. Confirm `test-haystack-reviewer.sh` includes environment-variable overrides
   for timeout, poll interval, and major policy.
3. Confirm a `--timeout` reviewer invocation overrides both config and
   `HAYSTACK_REVIEWER_TIMEOUT`.

**Expected result**: Runtime overrides are deterministic and do not modify
repository config files.

### Step 4: Validate invalid config failures

**Maps to**: AC-5

1. Run `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
2. Confirm invalid boolean, invalid positive-integer, unknown-key, scalar
   `stop_rule`, and malformed YAML cases fail with setting-specific messages.
3. Confirm `haystack-reviewer.sh` fails closed when the resolver reports invalid
   config.

**Expected result**: Invalid Haystack settings are caught before reviewer-loop
behavior changes.

### Step 5: Validate docs and examples

**Maps to**: AC-6, AC-7

1. Inspect `.ai-dev-workflow.yaml` for the shared `review.haystack` example.
2. Inspect `.ai-dev-workflow.local.example.yaml` for local override examples.
3. Inspect `docs/workflow/development-workflow/integrations/haystack-triage.md`
   for defaults, precedence, stop-rule explanation, and validation guidance.
4. Run markdown lint over the changed docs.

**Expected result**: Operators can discover settings, defaults, and override
rules without reading script internals.

### Last Step: Validate and shut down

1. Run all verification commands listed in the implementation plan.
2. Verify all assertions below are satisfied.
3. Remove any temporary fixture directories created during manual smoke checks.

---

## Assertions Checklist

- [ ] Optional `review.haystack` settings are supported without requiring the
      section in existing repositories.
- [ ] Valid repository settings affect Haystack reviewer behavior.
- [ ] Environment variables take precedence over repository settings.
- [ ] CLI `--timeout` takes precedence over timeout env/config defaults.
- [ ] Invalid settings fail validation with setting-specific feedback.
- [ ] Documentation explains settings, defaults, precedence, validation, and
      stop-rule purpose.
- [ ] The local workflow config example includes representative Haystack values.

---

## Seed Data Reference

No persistent seed data is required.

| Entity | Scenario | How to load |
| ------ | -------- | ----------- |
| Temporary workflow config | Shared and local Haystack settings | Created inside shell tests |
| Mock Haystack response sequence | Pending, repeated-progress, and completed payloads | Created inside `test-haystack-reviewer.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| Resolver tests fail before Haystack assertions | YAML subset parser rejected fixture syntax | Use the same two-space mapping/list style as existing resolver tests. |
| Reviewer tests skip with unavailable Haystack | Mock `haystack` binary is not first in `PATH` | Re-run the test script without overriding `TEST_REVIEWER_PATH`. |
| Markdown lint reports broken links | Relative path depth is wrong from the plan or runbook location | Recalculate links from the file containing the link and rerun markdownlint. |

---

## Known Limitations

- Real Haystack service timing is not deterministic; automated reviewer tests use
  mocked Haystack payloads for stop-rule assertions.
