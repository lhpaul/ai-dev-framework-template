# Guardrails: Controlling Agent Autonomy

Guardrails are this framework's way of answering one question up front: **how much
should an AI agent be allowed to do on its own?**

Without guardrails, the answer is buried in command flags passed at invocation
time (`--delegate-review`, `--may-merge`, `--max-risk`), which means the policy
changes depending on who is running the command and what flags they remember to
pass. Guardrails move that policy into the repository's `.ai-dev-workflow.yaml`
file so it is declared once, version-controlled, and readable by any adopter
without looking at any protocol or script internals.

A repository with guardrails configured still uses the same workflow stages (spec,
plan, implementation, review, merge). Guardrails do not change the workflow's
structure — they change who acts at each decision point: a human, or an agent
acting within the repository's declared limits.

> The `guardrails` section in `.ai-dev-workflow.yaml` is declared here and
> enforced at runtime by orchestration (Protocols 90, 91, and 95). See
> `docs/workflow/development-workflow/guardrails-enforcement.md` for the
> enforcement reference: effective-guardrails resolution, config-field→policy
> mapping, six enforcement gates, named stop conditions, and audit-evidence rules.

---

## Autonomy Modes

Every guardrails configuration declares exactly one **mode**. The mode is a
named summary of the overall authority level. Per-stage permissions (see below)
can refine the mode for individual stages, but the mode sets the baseline intent.

| Code value   | Display label | What it means                                                                                                                                                         |
| ------------ | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `manual`     | Manual        | Agents draft and propose work but never merge and never start backlog work without confirmation. A human performs every merge. This is the conservative end.          |
| `assisted`   | Assisted      | Agents prepare pull requests and gather review evidence automatically, but a human still makes every merge decision.                                                  |
| `delegated`  | Delegated     | Agents may merge clean pull requests within configured per-stage permissions and risk limits, stopping for any documented stop condition.                             |
| `autonomous` | Autonomous    | Agents may start eligible backlog work and merge across stages within configured permissions and risk limits, still honoring all stop conditions.                     |

**Default**: When no `guardrails` section is present in `.ai-dev-workflow.yaml`,
the mode resolves to `manual`. Existing repositories that take no action keep
today's conservative behavior automatically.

**Mode and per-stage permissions**: The mode sets a default expectation. When
per-stage `may_merge_pr` or `max_merge_risk` values are set explicitly, those
values take precedence over the mode's baseline for that stage, allowing
fine-grained control (for example, `delegated` mode for spec and plan but `false`
for implementation merges).

---

## Risk Scale

When guardrails allow an agent to merge, a **risk level** is associated with
each pull request. The agent compares the PR's classified risk against the stage's
configured `max_merge_risk`. If the PR risk exceeds the limit, the agent stops
and defers to a human.

| Code value | Display label | What it means                                                            |
| ---------- | ------------- | ------------------------------------------------------------------------ |
| `low`      | Low           | Small, well-contained change with limited blast radius.                  |
| `medium`   | Medium        | Moderate change touching multiple areas or with non-trivial behavior.    |
| `high`     | High          | Large, sensitive, or wide-blast-radius change.                           |

**Ordering**: `low` < `medium` < `high` by increasing risk.

**Rule**: A stage's `max_merge_risk` means an agent may merge a pull request
whose classified risk is at or below that level. Any pull request classified
above that level triggers a stop, regardless of mode.

---

## Per-Stage Permissions

Permissions can be configured independently for each of the three authored stages:
`spec`, `plan`, and `implementation`. This lets a repository grant merge authority
for documentation-heavy stages (spec and plan) while keeping implementation merges
under human control.

Each stage supports three fields:

| Field              | Type    | Default | Meaning                                                                              |
| ------------------ | ------- | ------- | ------------------------------------------------------------------------------------ |
| `may_open_pr`      | boolean | `true`  | Whether an agent may open a pull request for this stage.                             |
| `may_merge_pr`     | boolean | `false` | Whether an agent may merge a clean pull request for this stage.                      |
| `max_merge_risk`   | string  | `low`   | The highest risk level (`low`, `medium`, or `high`) at which an agent may merge.    |
| `required_evidence`| list    | `[]`    | Named evidence items that must be present before an agent may merge at this stage.   |

**Example — spec and plan merges allowed, implementation merges forbidden**:

```yaml
guardrails:
  mode: delegated
  stages:
    spec:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    plan:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    implementation:
      may_open_pr: true
      may_merge_pr: false   # human must merge implementation PRs
      max_merge_risk: low
```

---

## Backlog-Start Policy

The `backlog_start` setting controls whether an agent may pick up a new backlog
item and begin work without waiting for an explicit human instruction.

| Field                          | Type    | Default | Meaning                                                                   |
| ------------------------------ | ------- | ------- | ------------------------------------------------------------------------- |
| `allow_without_confirmation`   | boolean | `false` | When `true`, agents in `autonomous` mode may start eligible items unprompted. |

**Default is `false`**: Unless a repository explicitly opts in, agents wait for a
human to confirm each new item before starting. This preserves the current
behavior where a human invokes a workflow command to start each run.

```yaml
guardrails:
  mode: autonomous
  backlog_start:
    allow_without_confirmation: true   # agents may self-start eligible backlog items
```

---

## Portfolio parallelism (optional)

The `parallelism` block under `guardrails` configures stage-lane caps for
`/run-work` portfolio batches (Protocol 90 Step 3). It does not change per-stage
protocol contracts — only how many items per lane may dispatch concurrently.

| Field | Type | Default | Meaning |
| ----- | ---- | ------- | ------- |
| `max_concurrent_by_stage.spec` | integer | `0` (unlimited) | Max concurrent spec-lane items in one batch proposal. |
| `max_concurrent_by_stage.plan` | integer | `0` (unlimited) | Max concurrent plan-lane items. |
| `max_concurrent_by_stage.review` | integer | `0` (unlimited) | Max concurrent review-lane items. |
| `max_concurrent_by_stage.implementation` | integer | `1` | Max concurrent implementation items (conservative default). |

`0` means no cap for that lane. Higher implementation concurrency requires explicit
configuration; `workflow-batch-plan.sh` may still emit `LOCAL_RUNTIME=exclusive` to
hold items that would contend for local dev servers, databases, or ports even when
the lane cap allows more than one implementation item.

```yaml
guardrails:
  mode: delegated
  parallelism:
    max_concurrent_by_stage:
      spec: 0
      plan: 0
      review: 0
      implementation: 2
```

Resolved lane assignments and hold reasons are emitted by
`scripts/development-workflow/workflow-batch-lanes.sh`.

---

## Required Evidence

The `required_evidence` field on each stage lists named evidence items that must
be present before an agent may merge a pull request for that stage. If any listed
evidence item is absent, the agent must stop and wait for a human to provide or
approve it.

**Example — implementation stage requires regression evidence**:

```yaml
guardrails:
  mode: delegated
  stages:
    implementation:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: high
      required_evidence:
        - regression       # a regression test run must have passed before merging
```

Recognized evidence values (additional values may be defined by future tooling):

- `regression` — a regression test suite run has passed for this PR.
- `smoke_test` — the smoke test runbook has been executed and passed.
- `security_review` — a security review has been completed.

---

## Stop Conditions

Stop conditions are situations in which an agent **must** stop and defer to a
human, regardless of mode and regardless of per-stage permissions. They are not
weaker than today's behavior in any mode.

The following stop conditions are always in force:

| Condition                             | When it fires                                                                          |
| ------------------------------------- | -------------------------------------------------------------------------------------- |
| `unclear_requirements`                | A requirement or acceptance criterion is ambiguous and cannot be safely resolved.      |
| `architecture_decision`               | The work requires a human decision on architecture or technology.                      |
| `failing_ci`                          | Required CI checks are red.                                                            |
| `unresolved_blocking_review`          | A blocking review thread (from a reviewer or automated tool) is unresolved.            |
| `high_risk_change`                    | The classified PR risk exceeds the stage's configured `max_merge_risk`.                |
| `destructive_action`                  | The action would delete branches, data, releases, or other non-recoverable artifacts.  |
| `human_checkpoint_required`           | A declared stage-scoped human checkpoint is still pending for the PR's work item.      |
| `security_sensitive_advisory_pending` | A security-sensitive advisory finding (per the classifier in `scripts/development-workflow/security-advisory-classifier.sh`) lacks a fixed commit or a verified human accept/reject decision at the PR's current head SHA. |
| `missing_tracker_context`             | The work item is missing required tracker metadata (status, type, or linked spec).     |
| `missing_required_secret_or_permission` | A required credential or GitHub permission is absent.                                |
| `push_verification_failed`            | A branch push could not be verified: the branch's upstream would send it somewhere other than its own remote branch, or the pushed commit is not present on the remote. |

**These stops hold in all modes, including `autonomous`.** A repository cannot
configure its way out of a stop condition. The guardrails model is about granting
authority within safe limits, not removing the ability to stop.

---

## Audit Requirements

When an agent acts under `delegated` or `autonomous` mode, it must leave a
record of what it did and why. Two audit records are required:

| Record                    | What it contains                                                                                                | Required in               |
| ------------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `pr_disposition_record`   | A stable comment on the PR summarizing the merge decision, the risk classification, and the evidence consulted. | `delegated`, `autonomous` |
| `work_item_ledger_record` | A comment on the work item (issue or tracker card) recording the stage completed, the PR merged, and the agent session that acted. | `delegated`, `autonomous` |

These records are how a human can audit what agents did and why, without reading
agent session logs. In `manual` and `assisted` modes, humans make every merge
decision directly, so no disposition record is required (though agents may still
leave informational comments).

---

## Two-Step Lifecycle and Always-Confirm

The framework ships a **two-step lifecycle** as its default operating model:

1. **Execute** — `/run-item`, `/run-items`, or `/run-epic` advance work to
   `ready-for-human-review`. These commands stop before merge.
2. **Land** — `/batch-merge` (or manual merge) lands ready PRs after a human
   confirms the merge plan.

This separation keeps humans in control of what goes into the integration branch
while still automating the preparation, review, and CI-readiness steps.

### Always-Confirm Prelude

Every mutating orchestration command (`/run-item`, `/run-items`, `/run-epic`) runs
the **shared bounded prelude** before any artifact mutation. The prelude always
sets `requiresConfirmation: true`, which means:

- The resolved policy is always printed before work starts.
- When all autonomy flags were provided explicitly in the invocation (e.g.,
  `--delegate-review --may-merge --may-start-backlog true --max-risk high`), those
  explicit flags serve as the human's confirmation and the orchestrator may
  proceed immediately after printing the summary.
- When any flag was inferred or scope is ambiguous, the orchestrator stops and
  waits for the human to confirm or re-invoke with corrected flags.

**`/run-work` is exempt**: the portfolio scan is read-only (no mutation), so the
bounded prelude is not required. Only the execute commands run the prelude.

See [`bounded-run-prelude.md`](bounded-run-prelude.md) for the full prelude
contract and script reference.

---

## Safe Defaults and Migration Note

**No action is required** for existing repositories. The `guardrails` section in
`.ai-dev-workflow.yaml` is entirely optional.

When no `guardrails` section is present — or when the section omits a field —
the framework resolves that field to its documented safe default:

| Field                                    | Safe default |
| ---------------------------------------- | ------------ |
| `mode`                                   | `manual`     |
| `backlog_start.allow_without_confirmation` | `false`    |
| `stages.*.may_open_pr`                   | `true`       |
| `stages.*.may_merge_pr`                  | `false`      |
| `stages.*.max_merge_risk`                | `low`        |
| `stages.*.required_evidence`             | `[]` (none)  |

**In `manual` mode with all defaults**, agent behavior is identical to what the
framework has always done: agents draft pull requests and gather review evidence,
but a human performs every merge and confirms each new backlog item before work
starts.

**Guardrails are opt-in.** Existing repositories that do nothing continue to work
exactly as before. Adding a `guardrails` section with `mode: manual` is
equivalent to taking no action — it documents the existing behavior explicitly
without changing it.

---

## Worked Examples

### Example 1: Manual (equivalent to taking no action)

```yaml
# .ai-dev-workflow.yaml
guardrails:
  mode: manual
  backlog_start:
    allow_without_confirmation: false
```

Agents draft PRs for all stages. Humans merge every PR. No agent starts a new
backlog item unprompted.

### Example 2: Assisted

```yaml
# .ai-dev-workflow.yaml
guardrails:
  mode: assisted
  backlog_start:
    allow_without_confirmation: false
```

Agents prepare pull requests and run review loops automatically. Humans still
make every merge decision. The assisted mode is useful when you want agents to
reduce manual setup and review-churn effort without delegating the merge click.

### Example 3: Delegated (agents may merge clean spec, plan, and implementation PRs)

```yaml
# .ai-dev-workflow.yaml
guardrails:
  mode: delegated
  backlog_start:
    allow_without_confirmation: false
  stages:
    spec:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    plan:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    implementation:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: high
      required_evidence:
        - regression
  stop_conditions:
    - unclear_requirements
    - architecture_decision
    - failing_ci
    - unresolved_blocking_review
    - high_risk_change
    - destructive_action
    - missing_tracker_context
    - missing_required_secret_or_permission
    - push_verification_failed
  audit:
    pr_disposition_record: required
    work_item_ledger_record: required
```

Agents may merge clean spec, plan, and implementation pull requests within the
configured risk limits and with regression evidence present for implementation.
Any stop condition causes the agent to defer to a human, regardless of mode.
Audit records are left after every agent-driven merge.

### Example 4: Spec and plan delegated, implementation human-only

```yaml
# .ai-dev-workflow.yaml
guardrails:
  mode: delegated
  stages:
    spec:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    plan:
      may_open_pr: true
      may_merge_pr: true
      max_merge_risk: medium
    implementation:
      may_open_pr: true
      may_merge_pr: false   # humans merge implementation PRs
      max_merge_risk: low
```

A common setup for teams that trust agents to advance documentation-heavy stages
(spec and plan) but want a human to review and merge every code change.

---

## Relationship to Existing Command Flags

The `/run-epic` protocol exposes the same concepts through invocation-time flags:
`--delegate-review`, `--may-merge`, `--max-risk <low|medium|high>`,
`--may-start-backlog`, and the PR disposition record and epic ledger audit record
requirements. These flags express the same authority model at the command level
for a single epic or batch run.

The `guardrails` section in `.ai-dev-workflow.yaml` gives these concepts a
declarative, repo-level home so they do not need to be re-specified at each
invocation. Reconciling the per-invocation flags with the repo-level guardrails
configuration (so that the config takes effect automatically in `/run-work` runs)
is tracked by issue #980 and is out of scope here.

See `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` for
the current `/run-epic` flag reference.
