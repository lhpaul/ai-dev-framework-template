# Guardrails Configuration Model and Documentation — Implementation Plan

**Spec**: [`1_guardrails-config-model_specs.md`](./1_guardrails-config-model_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/guardrails-config-model.smoke-test.md`](../../../testing/workflow/guardrails-config-model.smoke-test.md)

---

## Summary

**Approach**: This is a documentation-and-configuration feature with no runtime
enforcement (enforcement is tracked separately by #980). Two layers change.
First, add an optional, fully commented `guardrails` section to the template's
`.ai-dev-workflow.yaml` so adopters can read every field, its accepted values,
and its safe default directly in the manifest. Second, add a new workflow
documentation page (`docs/workflow/development-workflow/guardrails.md`) that
explains guardrails in plain language for new adopters, defines the four
autonomy modes and the three-level risk scale, enumerates stop conditions and
audit requirements, gives worked examples per common setup (including a
delegated example), and states the migration path (doing nothing is safe). The
model deliberately reuses the autonomy vocabulary that the `/run-epic` protocol
already exposes through command flags (`--delegate-review`, `--may-merge`,
`--max-risk low|medium|high`, `--may-start-backlog`, PR disposition record, epic
ledger record), giving those concepts a declarative repo-level home without
changing any flag behavior.

**Estimated complexity**: S

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: The change is additive documentation plus a commented,
non-enforced config block. No scripts, agents, or protocols change their runtime
behavior; the existing config resolver already tolerates unknown top-level keys
(see Verification Log), so adding the `guardrails` section cannot break
validation. The bulk of the effort is writing clear, internally consistent prose
and examples that match the documented field shape.

**Dependencies**: None for this item. The spec for `/run-work` adaptive
entrypoint (#978) and the enforcement work (#980) both depend on this model but
are out of scope here. This plan does not require either to be merged first.

---

## Verification Log

> Record reproducible plan-time verification commands that influenced scope, counts, or file lists. Include repo revision and concrete results.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `bd82fae` (branch `plan/979-guardrails-config-model`, based on `origin/develop-guardrails`) |
| Config does not reject unknown top-level keys | `grep -n "VALID_MODES\|unexpected\|unknown\|reject" scripts/development-workflow/workflow-config-resolver.py` | Validation enforces only `mode` (against `VALID_MODES`) and `workflow_hub.product_repos`; no closed top-level key set. Adding a `guardrails:` block is additive and safe. |
| Validator is a thin wrapper | `sed -n '34,39p' scripts/development-workflow/validate-workflow-config.sh` | Delegates to `workflow-config-resolver.py validate`; no per-key allowlist to update. |
| Existing autonomy/risk vocabulary already present | `grep -n "delegate-review\|may-merge\|max-risk\|may-start-backlog\|disposition\|ledger" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | `--delegate-review`, `--may-merge`, `--max-risk <low\|medium\|high>`, `--may-start-backlog`, PR disposition record, and epic ledger record already exist. Risk scale `low\|medium\|high` matches the spec exactly. |
| Current config sections and comment style | Read `.ai-dev-workflow.yaml` | Sections: `schema_version`, `review`, `issue_tracker`, `vcs`, `browser_automation`, `template`. Comment style: leading `#` block per section with `field — meaning / default` inline notes. New `guardrails` section will match this style. |
| README schema reference location | `grep -n "Current schema\|schema_version: 2\|template:" docs/workflow/development-workflow/README.md` | The "Workflow Configuration" section (around the `Current schema:` fenced block and the "Important implementation notes" list) documents each top-level config field; the new section and bullet belong here. |
| No existing guardrails doc/term | `grep -rn "guardrails" docs/ REVIEW.md .ai-dev-workflow.yaml` | No prior `guardrails` references; this is net-new documentation. |

---

## Layer-by-Layer Changes

> Only the two layers below apply. Database, Backend/API, Shared Packages, and Frontend/UI are not affected by this feature.

### Infrastructure / Configuration

- [ ] Add an optional, fully commented `guardrails:` section to
      `.ai-dev-workflow.yaml`, placed after `template:` (or another logical
      location consistent with the file's ordering), expressing:
  - `mode` — one of `manual` | `assisted` | `delegated` | `autonomous`;
    documented default `manual`. (AC: modes, default `manual`.)
  - `backlog_start.allow_without_confirmation` — boolean; documented default
    `false` (an agent may not start a backlog item without human confirmation).
    (AC: backlog-start policy + its default.)
  - `stages.spec`, `stages.plan`, `stages.implementation` — each with
    `may_open_pr` (bool), `may_merge_pr` (bool), and `max_merge_risk`
    (`low` | `medium` | `high`). Documented defaults: agents may open PRs but
    `may_merge_pr` defaults `false` for every stage. (AC: per-stage independent
    permissions; sample allowing spec/plan merges but forbidding implementation
    merges.)
  - `stages.<stage>.required_evidence` — list of named evidence requirements;
    documented example: implementation requires regression evidence. (AC:
    required evidence per stage.)
  - `stop_conditions` — documented list naming, at minimum: unclear
    requirements, architecture decision, failing CI, unresolved blocking review,
    high-risk change, destructive action, missing tracker context, and missing
    required secret or permission; with a comment that these hold regardless of
    mode. (AC: stop conditions list.)
  - `audit` — names the required records (PR disposition record, work-item
    ledger record) and a comment on which modes require them. (AC: audit
    requirements.)
  - A leading comment block stating the section is **optional**, that absent
    values resolve to documented safe defaults, that the default mode is
    `manual`, and that this section is **documentation/model only** in this pass
    — enforcement is tracked by #980. (AC: safe defaults; no-section behavior;
    migration note.)
- [ ] Keep the section commented in the file-comment style already used by
      `review:`, `issue_tracker:`, and `template:` (leading `#` notes per field
      with `default:` annotations). Do not introduce a schema bump:
      `schema_version` stays `2` (the change is additive and optional).

### Documentation

- [ ] Create `docs/workflow/development-workflow/guardrails.md` — the canonical
      plain-language guardrails reference (full content outline in the
      "Documentation Updates" section below). This file satisfies the
      "adopter reads guardrails documentation" use case and every documentation
      acceptance criterion.
- [ ] Update `docs/workflow/development-workflow/README.md` "Workflow
      Configuration" section: add `guardrails` to the `Current schema:` example
      block and add one "Important implementation notes" bullet describing the
      `guardrails` section, its optionality, its safe defaults (mode resolves to
      `manual`), and a link to `guardrails.md`. Also add `guardrails.md` to the
      relevant index list (e.g., under "Tooling And Configuration").
- [ ] Update `.ai-dev-workflow.yaml`'s inline comments to cross-reference
      `docs/workflow/development-workflow/guardrails.md` (consistent with how the
      file already points to README and integration docs).

---

## Testing Strategy

**Test types**: Manual / documentation review (no automated unit tests apply —
this feature ships documentation and a non-enforced, commented config block; no
parser, runtime code path, or behavior change exists to unit-test).

**Key scenarios to test** (all via the smoke test runbook, which is
documentation-verification only):

1. An adopter can read `guardrails.md` and describe each mode without reading
   code — maps to AC "plain-language documentation" and the four-modes AC.
2. The `.ai-dev-workflow.yaml` `guardrails` section is present, fully commented,
   and every field has a documented default — maps to the "documented section"
   AC.
3. The delegated worked example allows agents to merge clean spec, plan, and
   implementation PRs within risk limits and is valid against the documented
   field shape — maps to the delegated-example AC.
4. A sample config can allow spec and plan merges while forbidding
   implementation merges — maps to the per-stage independence AC.
5. The implementation stage example requires regression evidence — maps to the
   required-evidence AC.
6. With no `guardrails` section, the docs state behavior is unchanged and the
   default mode resolves to `manual` — maps to the safe-defaults and migration
   ACs.
7. `scripts/development-workflow/validate-workflow-config.sh` still passes with
   the new `guardrails` section present (additive-key sanity check) — confirms
   no regression in config validation.

**Smoke test runbook**: `docs/testing/workflow/guardrails-config-model.smoke-test.md`

**Regression suite**: No automated regression suite covers documentation/config
prose in this repository, so no new regression spec is added. The repository's
markdown lint (`markdownlint-cli2` + heuristic lint) is the relevant automated
gate and runs in CI on the changed docs.

> Parser-risk addendum: Not applicable. No file under `scripts/lint/`,
> `scripts/parse/`, or any scanner/tokenizer/regex module is introduced or
> changed; no structured-text scanning behavior is added. The config resolver is
> not modified.
>
> Concurrent-event-source addendum: Not applicable. No event listeners, socket
> callbacks, timers, async queues, or shared mutable state are introduced.
>
> Cross-cutting checklist: Not applicable. This pass documents a config *model*
> only. It does not add or modify a safety/quality/compliance checklist category
> in `REVIEW.md`, the planning protocol, or the implementation protocol, and it
> does not add acceptance criteria that every future feature plan must satisfy.
> Stop conditions are *documented as part of the guardrails model*, not wired
> into any review/planning gate (enforcement is #980).

---

## Seed Data

> No application or database seed data applies to this documentation/config feature.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| None | Not applicable — documentation and config only | — |

---

## Documentation Updates

> These are the documentation deliverables and edits the developer must make
> during implementation. For this feature, documentation IS the deliverable, so
> these are in scope for the implementation PR (unlike a typical feature where
> docs are only listed). The content outline below is the contract the developer
> implements.

- [ ] **Create** `docs/workflow/development-workflow/guardrails.md` with the
      following sections (each maps to one or more acceptance criteria):
  1. **What guardrails are** — plain-language definition aimed at a new adopter
     who has not learned the orchestration protocols. (AC: plain language.)
  2. **Autonomy modes** — a table with the four code values (`manual`,
     `assisted`, `delegated`, `autonomous`), display labels (Manual, Assisted,
     Delegated, Autonomous), and meanings, copied/adapted from the spec's Modes
     table; state the default mode is `manual` and that explicit per-stage
     permissions refine the mode. (AC: four modes; default `manual`.)
  3. **Risk scale** — a table with `low`/`medium`/`high`, display labels
     (Low/Medium/High), meanings, the ordering `low < medium < high`, and the
     rule that a stage's max merge risk means "merge at or below this level,
     stop above it." (AC: single named risk scale.)
  4. **Per-stage permissions** — explain `may_open_pr`, `may_merge_pr`, and
     `max_merge_risk` for `spec`, `plan`, and `implementation`, stressing
     independence (e.g., allow spec/plan merges but forbid implementation
     merges). (AC: per-stage independence.)
  5. **Backlog-start policy** — explain `backlog_start.allow_without_confirmation`
     and its default `false`. (AC: backlog-start policy + default.)
  6. **Required evidence** — explain `required_evidence` per stage with the
     implementation-requires-regression-evidence example. (AC: required
     evidence.)
  7. **Stop conditions** — list the recognized stop conditions (the eight named
     in the spec, at minimum) and state they hold regardless of mode and are not
     weaker than today's behavior. (AC: stop conditions.)
  8. **Audit requirements** — describe the PR disposition record and work-item
     ledger record and which modes require them. (AC: audit requirements.)
  9. **Safe defaults & migration note** — state that absent guardrails resolve
     to safe defaults preserving current behavior (no merges, no autonomous
     backlog starts), that the default mode is `manual`, and that taking no
     action is safe and supported (guardrails are opt-in). (AC: safe defaults;
     migration note.)
  10. **Worked examples** — at least one example per common setup, each valid
      against the documented field shape, including: a `manual` example (or
      "omit the section entirely" note), an `assisted` example, and a
      `delegated` example where agents may merge clean spec, plan, and
      implementation PRs within risk limits. (AC: examples incl. delegated.)
  11. **Relationship to existing command flags** — a short note that the
      `/run-epic` flags (`--delegate-review`, `--may-merge`, `--max-risk`,
      `--may-start-backlog`) and the disposition/ledger audit records are the
      runtime expression of these concepts today, and that reconciling them with
      guardrails enforcement is tracked by #980 (out of scope here). Keep this
      consistent with `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
- [ ] **Update** `docs/workflow/development-workflow/README.md` — add
      `guardrails` to the `Current schema:` block, add one "Important
      implementation notes" bullet, and add `guardrails.md` to the
      "Tooling And Configuration" index list.
- [ ] **Update** `.ai-dev-workflow.yaml` — add the commented `guardrails`
      section and cross-reference `guardrails.md`.
- [ ] `AGENTS.md` / `CLAUDE.md` — _None required._ The "Key Documentation" table
      lists authoritative docs; adding a `guardrails.md` row is optional and may
      be left out to keep this PR focused, since `guardrails.md` is already
      indexed from the workflow README. The developer may add a row if it
      improves discoverability, but it is not required by any acceptance
      criterion.
- [ ] `REVIEW.md` — _None._ No review checklist category changes (enforcement
      and any review-gate wiring are #980).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Worked examples drift from the documented field shape (field names/values in an example do not match the `.ai-dev-workflow.yaml` comments) | Med | Med | Author the `.ai-dev-workflow.yaml` field shape first, then derive every doc example from it. The smoke test runbook includes an explicit "every example is valid against the documented field shape" assertion. |
| Terminology diverges from existing `/run-epic` flags (e.g., calling it `risk_limit` in docs but `max_merge_risk` in config, or a different risk label set) | Med | Med | Use one canonical name per concept across config, `guardrails.md`, and README. Reuse the spec's exact code values (`manual/assisted/delegated/autonomous`, `low/medium/high`). Reference the `/run-epic` flags by their existing names. Cross-section consistency self-check (Step 5) enforces this. |
| Reader infers guardrails are enforced now | Med | Low | Every surface (config comment, `guardrails.md`, README bullet) states explicitly that this pass is model + documentation only and enforcement is #980. |
| Adding the section is mistaken for a schema change | Low | Low | Keep `schema_version: 2`; the section is optional and additive. Verification Log confirms the resolver tolerates unknown top-level keys. |
| Markdown lint failures (broken relative links, trailing whitespace) | Med | Low | Run `markdownlint-cli2` and the heuristic lint on the new/changed docs before commit, per Implementation Order. |

---

## Code Samples

> The only "code" in this feature is YAML config and documentation prose. The
> developer should treat the field names below as the canonical contract and
> keep all documentation examples consistent with them. The block below is
> **illustrative — adapt wording/comments during implementation**, but keep the
> field names and value sets stable so the docs and config agree.

```yaml
# Illustrative — adapt during implementation. Field names and value sets are the
# canonical contract; keep guardrails.md examples consistent with these.
guardrails:
  # Optional. Omit the entire section to keep today's conservative behavior.
  # Absent values resolve to the documented safe defaults below.
  # MODEL ONLY in this pass — enforcement is tracked by #980.
  mode: manual            # manual | assisted | delegated | autonomous (default: manual)
  backlog_start:
    allow_without_confirmation: false   # default: false
  stages:
    spec:
      may_open_pr: true       # default: true
      may_merge_pr: false     # default: false
      max_merge_risk: low     # low | medium | high (default: low)
    plan:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
    implementation:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
      required_evidence:
        - regression        # e.g. implementation merges require regression evidence
  stop_conditions:          # hold regardless of mode; not weaker than today
    - unclear_requirements
    - architecture_decision
    - failing_ci
    - unresolved_blocking_review
    - high_risk_change
    - destructive_action
    - missing_tracker_context
    - missing_required_secret_or_permission
  audit:
    pr_disposition_record: required     # which modes require it documented in guardrails.md
    work_item_ledger_record: required
```

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones.

1. **Define the canonical field shape** in `.ai-dev-workflow.yaml`: add the
   commented `guardrails:` section using the field names and value sets from the
   Code Samples block, matching the existing file comment style and documenting
   each field's default. Keep `schema_version: 2`.
2. **Write `docs/workflow/development-workflow/guardrails.md`** following the
   11-section outline in the Documentation Updates section. Derive every worked
   example from the field shape defined in step 1 so they stay valid against it.
3. **Update `docs/workflow/development-workflow/README.md`**: add `guardrails`
   to the `Current schema:` example block, add one "Important implementation
   notes" bullet, and add `guardrails.md` to the "Tooling And Configuration"
   index list.
4. **Add the cross-reference comment** in `.ai-dev-workflow.yaml` pointing to
   `guardrails.md`.
5. **Cross-check consistency**: confirm field names, mode code values, risk
   labels, and stop-condition names are identical across `.ai-dev-workflow.yaml`,
   `guardrails.md`, and README. Confirm the delegated example and the
   spec/plan-merge-but-not-implementation example are present and valid.
6. **Verify the smoke test runbook** scenarios pass by reading the runbook and
   confirming each documentation assertion is satisfied.
7. **Run `scripts/development-workflow/validate-workflow-config.sh`** and confirm
   it passes with the new section present (additive-key sanity check).
8. **Run markdown lint** on the new and changed docs:
   `npx markdownlint-cli2 "docs/specs/developments/20260617083209_guardrails-config-model/**/*.md" "docs/workflow/development-workflow/guardrails.md" "docs/testing/workflow/guardrails-config-model.smoke-test.md"`
   and the heuristic lint; fix any violations.
9. **Documentation is the deliverable** for this feature — there are no separate
   "project doc" updates beyond those already listed in the Documentation
   Updates section.
10. **Update `CHANGELOG.md`** under `[Unreleased]` using the project's
    `**Bold Title** (#N):` format. Suggested literal entry under
    `### Added`:
    `- **Add guardrails config model and documentation** (#979): introduce an optional, fully commented \`guardrails\` section in \`.ai-dev-workflow.yaml\` and a new \`guardrails.md\` reference covering the four autonomy modes, per-stage permissions, the risk scale, stop conditions, audit requirements, and safe defaults that preserve current behavior. Documentation/model only; enforcement is tracked by #980.`
