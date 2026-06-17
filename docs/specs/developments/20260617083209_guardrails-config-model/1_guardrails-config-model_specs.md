# Guardrails Configuration Model and Documentation — Spec

---

## Overview

The framework needs one named, repo-owned concept that describes how much
authority AI agents have when they move work through the development workflow.
Today that authority is implied piecemeal through command flags (such as
delegate-review and may-merge) and protocol-specific wording, which makes it
hard for a new adopter to understand or safely change. This feature introduces a
**guardrails** configuration concept in `.ai-dev-workflow.yaml` and accompanying
workflow documentation. Guardrails let a repository declare, in plain terms, an
overall autonomy **mode**, per-stage permissions for opening and merging spec,
plan, and implementation pull requests, merge risk limits, a backlog-start
policy, required evidence, the conditions under which an agent must stop and ask
a human, and the audit trail an agent must leave behind. The default
configuration preserves today's conservative, human-reviewed behavior so that
existing repositories that never opt in see no change.

This spec covers only the **configuration model and its documentation** — what
fields exist, what values they accept, what the safe defaults are, and how
adopters reason about them. Enforcement of guardrails inside delegated
`/run-work` execution is a separate work item (#980) and is out of scope here.

---

## Use Cases

### Use Case 1: Adopter reads guardrails documentation to understand agent authority

**Actor**: Framework adopter (a maintainer of a repository created from or synced
with the template)
**Preconditions**: The repository contains `.ai-dev-workflow.yaml` and the
workflow documentation. The adopter has not previously configured guardrails.

**Steps**:

1. The adopter opens the workflow documentation section that describes
   guardrails.
2. The adopter reads a plain-language explanation of what guardrails are and why
   they exist.
3. The adopter reads the description of each autonomy mode (Manual, Assisted,
   Delegated, Autonomous) and what each one means for agent behavior.
4. The adopter reads worked configuration examples for common setups, including
   a delegated setup in which agents may merge clean spec, plan, and
   implementation pull requests within risk limits.
5. The adopter reads the description of stop conditions and audit requirements.

**Postconditions**: The adopter can describe, without reading any code, what
each mode does and which configuration values change agent behavior.

**Information shown**:

- A definition of guardrails in non-technical language.
- The four named modes with their display labels and meanings.
- A field-by-field description of the guardrails configuration section.
- The list of recognized stop conditions and their meanings.
- The audit requirements associated with each mode.
- At least one example per common setup, including the delegated example.

**Actions available**:

- Copy an example into the repository's `.ai-dev-workflow.yaml`.
- Decide which mode best matches the repository's risk tolerance.

**Considerations**:

- The documentation must be understandable by a new adopter who has not yet
  learned the internal orchestration protocols.
- Examples must be valid against the documented field shape so an adopter can
  copy them without edits beyond their own values.

---

### Use Case 2: Adopter configures guardrails in `.ai-dev-workflow.yaml`

**Actor**: Framework adopter
**Preconditions**: The adopter has read the guardrails documentation and decided
which autonomy mode and stage permissions the repository should use.

**Steps**:

1. The adopter adds a `guardrails` section to `.ai-dev-workflow.yaml`.
2. The adopter selects an overall mode from the four supported modes.
3. The adopter optionally sets the backlog-start policy.
4. The adopter optionally sets per-stage permissions for spec, plan, and
   implementation: whether an agent may open a pull request, whether an agent
   may merge a pull request, and the maximum merge risk allowed for that stage.
5. The adopter optionally sets required evidence for a stage (for example, that
   implementation merges require regression evidence).
6. The adopter optionally reviews or adjusts the stop conditions and audit
   requirements.
7. The adopter saves the file.

**Postconditions**: The repository declares an explicit guardrails contract.
Any value the adopter did not set falls back to the documented safe default.

**Information shown**:

- The current values the adopter has set.
- Inline comments in `.ai-dev-workflow.yaml` explaining each field and its
  default, consistent with the rest of that file's commenting style.

**Actions available**:

- Set only an overall mode and rely on defaults for everything else.
- Override individual stage permissions while keeping the mode.

**Considerations**:

- A `guardrails` section is optional. A repository with no `guardrails` section
  must behave exactly as it does today.
- Stage-level permissions are expressed independently for spec, plan, and
  implementation so an adopter can, for example, allow agents to merge spec and
  plan pull requests but never implementation pull requests.

---

### Use Case 3: Adopter relies on safe defaults without opting in

**Actor**: Framework adopter who has not added a `guardrails` section
**Preconditions**: The repository's `.ai-dev-workflow.yaml` has no `guardrails`
section, or has a `guardrails` section that omits some fields.

**Steps**:

1. The adopter runs the existing workflow commands as before.
2. The framework resolves guardrails values from documented safe defaults for
   every field that is absent.

**Postconditions**: Behavior is identical to the conservative, human-reviewed
behavior that existed before guardrails were introduced. No agent gains merge
authority or autonomous backlog-start authority by default.

**Information shown**:

- The documented statement that absent guardrails resolve to safe defaults and
  that those defaults preserve existing behavior.

**Actions available**:

- Continue using the framework with no configuration change.

**Considerations**:

- This use case is the migration path for existing repositories: doing nothing
  is safe and supported.

---

## Business Rules

- The `guardrails` section in `.ai-dev-workflow.yaml` is optional. When the
  section is entirely absent, the framework must resolve every guardrails value
  to its documented safe default.
- The documented safe defaults must preserve the framework's current
  conservative behavior: agents do not merge pull requests and do not start
  backlog work without confirmation unless a repository explicitly opts in.
- Exactly four autonomy modes are supported, identified by the user-facing
  values `manual`, `assisted`, `delegated`, and `autonomous`.
- The mode is a single, named summary of authority. Per-stage permissions, when
  present, express authority at a finer granularity than the mode alone.
- Stage-level permissions must be expressible independently for the spec, plan,
  and implementation stages.
- For each stage, the model must be able to express: whether an agent may open a
  pull request, whether an agent may merge a pull request, and the maximum merge
  risk allowed.
- Merge risk limits use a single, named risk scale documented in the workflow
  docs; the same scale and the same display labels are used everywhere
  guardrails risk appears.
- The model must be able to express a backlog-start policy: whether an agent may
  start a backlog item without human confirmation.
- The model must be able to express required evidence per stage (for example,
  that implementation merges require regression evidence).
- The model must be able to express stop conditions: named situations in which
  an agent must stop and defer to a human regardless of mode.
- The model must be able to express audit requirements: what record an agent
  must leave after acting (for example, a pull request disposition record and a
  work-item ledger record).
- Stop conditions for unclear requirements, architecture decisions, failing CI,
  unresolved blocking review, and high-risk changes remain in force and must not
  be weaker than today's behavior, regardless of mode.
- Documentation must explain guardrails in plain language aimed at a new adopter
  and must include at least one example per common setup, including a delegated
  setup where agents may merge clean spec, plan, and implementation pull
  requests within risk limits.

---

## Modes

The guardrails model supports exactly four autonomy modes. Each mode is a
named, plain-language summary of how much authority agents have. Per-stage
permissions, when set, refine the mode.

| Code value   | Display label | Description                                                                                                                                                  |
| ------------ | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `manual`     | Manual        | Agents draft and propose work but never merge and never start backlog work without confirmation. A human performs every merge. This is the conservative end. |
| `assisted`   | Assisted      | Agents prepare pull requests and gather review evidence automatically, but a human still makes every merge decision.                                         |
| `delegated`  | Delegated     | Agents may merge clean pull requests within configured per-stage permissions and risk limits, stopping for any documented stop condition.                    |
| `autonomous` | Autonomous    | Agents may start eligible backlog work and merge across stages within configured permissions and risk limits, still honoring all stop conditions.            |

**Mode relationship to defaults**:

- The default mode (when no `guardrails` section is present) is `manual`,
  preserving existing behavior.
- A mode sets baseline expectations; explicit per-stage permission values, when
  present, take precedence over the mode's baseline for that stage.

---

## Risk Levels

Merge risk limits and high-risk stop conditions reference a single named risk
scale.

| Code value | Display label | Description                                                              |
| ---------- | ------------- | ------------------------------------------------------------------------ |
| `low`      | Low           | Small, well-contained change with limited blast radius.                  |
| `medium`   | Medium        | Moderate change touching multiple areas or with non-trivial behavior.    |
| `high`     | High          | Large, sensitive, or wide-blast-radius change.                           |

**Valid ordering**:

- `low` < `medium` < `high` by increasing risk.
- A stage's maximum merge risk means an agent may merge a pull request whose
  classified risk is at or below that level, and must stop for any higher risk.

---

## Acceptance Criteria

- [ ] `.ai-dev-workflow.yaml` includes a documented `guardrails` section (with
      inline comments matching the file's existing comment style) that an
      adopter can read to understand every field and its default. The section is
      present as guidance even though it is optional to set.
- [ ] The documentation and the config comments define exactly four autonomy
      modes with the user-facing values `manual`, `assisted`, `delegated`, and
      `autonomous`, each with its display label and meaning.
- [ ] The model can express stage-level permissions independently for spec,
      plan, and implementation, where each stage can declare whether an agent may
      open a pull request, whether an agent may merge a pull request, and the
      maximum merge risk allowed. A reviewer can verify a sample config that
      allows spec and plan merges but forbids implementation merges.
- [ ] The model can express a backlog-start policy (whether an agent may start a
      backlog item without human confirmation), and the documented default for
      that policy is that an agent may not start without confirmation.
- [ ] The model can express required evidence per stage, and the documentation
      shows an implementation stage requiring regression evidence.
- [ ] The documentation lists the recognized stop conditions — at minimum
      unclear requirements, architecture decision, failing CI, unresolved
      blocking review, high-risk change, destructive action, missing tracker
      context, and missing required secret or permission — and explains that
      these stops hold regardless of mode.
- [ ] The documentation describes the audit requirements per mode — at minimum a
      pull request disposition record and a work-item ledger record — and which
      modes require them.
- [ ] With no `guardrails` section present, the documentation states (and the
      defaults specify) that behavior is unchanged: no agent merges pull requests
      and no agent starts backlog work without confirmation. A reviewer can
      confirm the default mode resolves to `manual`.
- [ ] The documentation includes a migration note for existing repositories
      stating that taking no action is safe and that guardrails are opt-in.
- [ ] The documentation includes at least one worked example per common setup,
      including a delegated example in which agents may merge clean spec, plan,
      and implementation pull requests within risk limits. Every example is
      valid against the documented field shape.
- [ ] The documentation explains guardrails in plain language understandable by a
      new adopter who has not yet learned the internal orchestration protocols.

---

## Out of Scope (MVP)

- **Enforcing guardrails in delegated `/run-work` execution.** Wiring the
  configuration into runtime agent decisions (reading the config, classifying
  risk, gating merges, writing audit records) is tracked by #980. This spec
  defines only the model and its documentation.
- **Removing or renaming existing command flags.** Existing flags such as
  delegate-review, may-merge, and max-risk are not removed or changed here;
  reconciling them with guardrails is part of enforcement work (#980 / #978).
- **Making `/run-work` the adaptive entrypoint.** That is tracked by #978.
- **Automated validation tooling for the `guardrails` section** (for example, a
  schema validator or linter that rejects invalid values). The model is
  documented and human-readable in this pass; programmatic validation can be a
  later improvement.
- **Per-branch or per-environment guardrails overrides.** This pass defines a
  single repository-level guardrails contract.
