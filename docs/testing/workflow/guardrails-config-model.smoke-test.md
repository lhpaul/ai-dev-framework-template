# Smoke Test Runbook: Guardrails Configuration Model and Documentation

**Feature**: Guardrails configuration model and documentation (#979)
**Spec**: [`../../specs/developments/20260617083209_guardrails-config-model/1_guardrails-config-model_specs.md`](../../specs/developments/20260617083209_guardrails-config-model/1_guardrails-config-model_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You have a checkout of the branch that implements #979.
- [ ] `node_modules` is installed so `markdownlint-cli2` can run.
- [ ] `python3` is available so `validate-workflow-config.sh` can run.

> This feature ships documentation and a non-enforced, commented config block.
> The smoke test is a documentation/config verification pass, not an application
> walkthrough. There is no app to launch and no login.

---

## Test Data

| Item | Value |
| --- | --- |
| Guardrails reference doc | `docs/workflow/development-workflow/guardrails.md` |
| Workflow manifest | `.ai-dev-workflow.yaml` |
| Workflow README | `docs/workflow/development-workflow/README.md` |
| Config validator | `scripts/development-workflow/validate-workflow-config.sh` |

---

## Smoke Test Steps

### Step 0: Open the changed files

- Open `docs/workflow/development-workflow/guardrails.md`,
  `.ai-dev-workflow.yaml`, and `docs/workflow/development-workflow/README.md`.

### Step 1: Guardrails doc explains the concept in plain language

**Maps to**: Acceptance Criterion — plain-language documentation

1. Read the opening of `guardrails.md`.

**Expected result**: A new adopter who has not learned the orchestration
protocols can understand what guardrails are and why they exist, without reading
any code.

### Step 2: Exactly four autonomy modes are defined

**Maps to**: Acceptance Criterion — four autonomy modes

1. Read the modes table in `guardrails.md` and the `mode` comment in
   `.ai-dev-workflow.yaml`.

**Expected result**: Exactly four modes appear with code values `manual`,
`assisted`, `delegated`, `autonomous`, each with a display label (Manual,
Assisted, Delegated, Autonomous) and a meaning. The documented default is
`manual`.

### Step 3: Per-stage permissions are independent

**Maps to**: Acceptance Criterion — per-stage independent permissions

1. Read the per-stage permissions section and the worked examples.

**Expected result**: For `spec`, `plan`, and `implementation`, the model
expresses `may_open_pr`, `may_merge_pr`, and `max_merge_risk` independently. A
sample config allows spec and plan merges while forbidding implementation
merges.

### Step 4: Backlog-start policy and its default

**Maps to**: Acceptance Criterion — backlog-start policy + default

1. Read the backlog-start section in `guardrails.md` and the
   `backlog_start.allow_without_confirmation` comment in `.ai-dev-workflow.yaml`.

**Expected result**: The model expresses whether an agent may start a backlog
item without confirmation, and the documented default is `false` (may not start
without confirmation).

### Step 5: Required evidence per stage

**Maps to**: Acceptance Criterion — required evidence per stage

1. Read the required-evidence section and the implementation-stage example.

**Expected result**: The model expresses required evidence per stage, and the
documentation shows an implementation stage requiring regression evidence.

### Step 6: Stop conditions hold regardless of mode

**Maps to**: Acceptance Criterion — stop conditions

1. Read the stop-conditions section.

**Expected result**: The documentation lists at minimum: unclear requirements,
architecture decision, failing CI, unresolved blocking review, high-risk change,
destructive action, missing tracker context, and missing required secret or
permission. It states these stops hold regardless of mode and are not weaker
than today's behavior.

### Step 7: Audit requirements per mode

**Maps to**: Acceptance Criterion — audit requirements

1. Read the audit-requirements section.

**Expected result**: The documentation describes at minimum a PR disposition
record and a work-item ledger record, and which modes require them.

### Step 8: Safe defaults and migration note

**Maps to**: Acceptance Criterion — safe defaults; migration note

1. Read the safe-defaults / migration section.

**Expected result**: The documentation states that with no `guardrails` section,
behavior is unchanged (no agent merges PRs, no agent starts backlog work without
confirmation), the default mode resolves to `manual`, and that taking no action
is safe and supported (guardrails are opt-in).

### Step 9: Worked examples including delegated

**Maps to**: Acceptance Criterion — examples incl. delegated

1. Read the worked-examples section.

**Expected result**: At least one example per common setup is present, including
a delegated example in which agents may merge clean spec, plan, and
implementation PRs within risk limits. Every example uses the same field names
and value sets documented in `.ai-dev-workflow.yaml` (valid against the
documented field shape).

### Step 10: Config still validates

**Maps to**: Plan Testing Strategy scenario 7 (no config-validation regression)

1. Run `scripts/development-workflow/validate-workflow-config.sh`.

**Expected result**: The validator exits successfully with the new `guardrails`
section present.

### Last Step: Lint and shut down

- Run
  `npx markdownlint-cli2 "docs/workflow/development-workflow/guardrails.md" "docs/specs/developments/20260617083209_guardrails-config-model/**/*.md" "docs/testing/workflow/guardrails-config-model.smoke-test.md"`
  and confirm no violations.
- Verify all assertions in the checklist below are met.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] `.ai-dev-workflow.yaml` includes a documented, fully commented `guardrails`
      section an adopter can read to understand every field and its default.
- [ ] Exactly four autonomy modes (`manual`, `assisted`, `delegated`,
      `autonomous`) are defined with display labels and meanings.
- [ ] Per-stage permissions (`may_open_pr`, `may_merge_pr`, `max_merge_risk`) are
      expressible independently for spec, plan, and implementation; a sample
      allows spec/plan merges but forbids implementation merges.
- [ ] Backlog-start policy is expressible, with documented default "may not start
      without confirmation".
- [ ] Required evidence per stage is expressible; implementation requires
      regression evidence in the example.
- [ ] Stop conditions are listed (at minimum the eight named conditions) and hold
      regardless of mode.
- [ ] Audit requirements (PR disposition record, work-item ledger record) are
      documented per mode.
- [ ] With no `guardrails` section, behavior is documented as unchanged and the
      default mode resolves to `manual`.
- [ ] A migration note states taking no action is safe and guardrails are opt-in.
- [ ] At least one worked example per common setup exists, including a delegated
      example; every example is valid against the documented field shape.
- [ ] The documentation explains guardrails in plain language for a new adopter.

---

## Seed Data Reference

No seed data is required for this documentation/config feature.

| Entity | Scenario | How to load |
| --- | --- | --- |
| None | Not applicable | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `validate-workflow-config.sh` fails | A YAML syntax error was introduced in `.ai-dev-workflow.yaml` (e.g., bad indentation under `guardrails`) | Fix the indentation/quoting; the resolver does not reject the new key, only malformed YAML it parses. |
| markdownlint reports broken relative link | Wrong `../` depth in a link from the runbook or plan | Count path segments from the file's own location and correct the depth. |
| Example fields do not match config | Example in `guardrails.md` drifted from `.ai-dev-workflow.yaml` | Re-derive every example from the canonical field shape in `.ai-dev-workflow.yaml`. |

---

## Known Limitations

- This runbook verifies the **documentation and config model only**. It does not
  test enforcement behavior (reading the config at runtime, classifying risk,
  gating merges, or writing audit records), which is out of scope here and
  tracked by #980.
