# Enforce Guardrails in Delegated /run-work Execution — Implementation Plan

**Spec**: [`1_980-enforce-guardrails-delegated-run-work_specs.md`](./1_980-enforce-guardrails-delegated-run-work_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/980-enforce-guardrails-delegated-run-work.smoke-test.md`](../../../testing/workflow/980-enforce-guardrails-delegated-run-work.smoke-test.md)

---

## Implementation Order Gate — Dependency on #979 (do not skip)

**Step 0 (hard gate)**: Do **not** begin implementation of this plan until issue
#979 ("Guardrails Configuration Model and Documentation") is **merged into
`develop-guardrails`**. This feature reads the `guardrails` configuration block
and `docs/workflow/development-workflow/guardrails.md` reference that #979
creates; both are the canonical contract for field names, mode codes, the risk
scale, stop-condition names, and safe defaults this enforcement consumes.

Verification before starting:

```bash
# Confirm the #979 deliverables are present on the integration base branch.
git fetch origin develop-guardrails
git show origin/develop-guardrails:.ai-dev-workflow.yaml | grep -n "guardrails:"
git show origin/develop-guardrails:docs/workflow/development-workflow/guardrails.md >/dev/null && echo "guardrails.md present"
```

If either check fails, the `guardrails` config block or `guardrails.md` is not
yet merged. **Stop and wait** — implementing enforcement against a config shape
that does not yet exist would force a rework cycle once #979 lands and could
hard-code field names that diverge from the merged model. This gate is named
`dependency:#979-not-merged` so a stop here is reported with an explicit cause.

> **Dependency status at plan-write time**: #979 **merged into
> `develop-guardrails`** as commit `0fe9e88` while this plan was being written.
> The field names used throughout this plan (`mode`,
> `backlog_start.allow_without_confirmation`, `stages.<stage>.may_open_pr` /
> `may_merge_pr` / `max_merge_risk` / `required_evidence`, `stop_conditions`,
> `audit.pr_disposition_record`, `audit.work_item_ledger_record`) were
> **confirmed verbatim against the merged `.ai-dev-workflow.yaml` `guardrails`
> block and `guardrails.md`** (see Verification Log). The Step 0 gate is retained
> because this plan branch may be rebased or implementation may begin on a
> different base; the implementer must re-confirm the field names and
> `stop_conditions` strings against the base branch at implementation time and
> use the merged names verbatim if any differ.

---

## Summary

**Approach**: This is a **documentation-and-protocol** feature (no runtime
application code, no database, no UI). It teaches the orchestration protocols to
(1) load the **effective guardrails** at run start by layering repository config
→ session overrides → invocation overrides, (2) **report** them in the run
summary, and (3) **enforce** them at five decision points already present in the
orchestration loop: backlog-start, PR-open per stage, delegated review decision,
delegated merge gate, and item completion. It does this by **generalizing the
existing `/run-epic` helpers** — `run-epic-risk-classifier.sh`,
`run-epic-delegated-gate.sh`, and `run-epic-audit-trail.sh` — so that normal
`/run-work` (Protocol 90) and `/run-item-work` (Protocol 91) consume the same
policy/risk/gate/audit path that `/run-epic` (Protocol 95) already uses, rather
than building a second, conflicting policy model. The work edits the three
orchestration protocols, their agent/skill mirrors, and `REVIEW.md`, and adds a
new "Guardrails Enforcement" reference page that defines the
config-field → run-epic-policy mapping and the named stop conditions.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: No code paths or scripts change behavior — the existing run-epic
helpers already implement risk classification, the delegated gate, and audit
records (see Verification Log). The effort is (a) defining a precise,
internally-consistent **mapping** from the #979 `guardrails` config fields onto
the existing helper inputs, (b) wiring named guardrail checks into the five
decision points across three large protocols without weakening any baseline
human-stop, and (c) keeping the agent/skill mirrors and `REVIEW.md` in lockstep.
The breadth across multiple lockstep documents (protocols + agents + skills +
review contract) plus the dependency on #979 lifts it above Small.

**Dependencies**: **#979 (Guardrails Configuration Model) must be merged into
`develop-guardrails` first** — see the Step 0 dependency gate above. No external
service dependencies. #978 (adaptive `/run-work` entrypoint) is **not** a
dependency: this plan enforces guardrails inside whatever orchestration path is
invoked and does not change how `/run-work` selects scope (#978 is explicitly
out of scope per the spec).

---

## Verification Log

> Reproducible plan-time verification commands that influenced scope, the
> file/decision-point list, and the "reuse existing helpers" approach. Repo SHA
> `2589b05`, branch `plan/980-enforce-guardrails` based on
> `origin/develop-guardrails`.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `2589b05` (branch `plan/980-enforce-guardrails`, based on `origin/develop-guardrails`). |
| #979 deliverables present on base (dependency met) | `git show HEAD:.ai-dev-workflow.yaml \| grep -n guardrails:` and `ls docs/workflow/development-workflow/guardrails.md` | `guardrails:` block present in `.ai-dev-workflow.yaml` and `guardrails.md` present — #979 merged as commit `0fe9e88`. The merged field names (`mode`, `backlog_start.allow_without_confirmation`, `stages.<stage>.may_open_pr`/`may_merge_pr`/`max_merge_risk`/`required_evidence`, the 8 `stop_conditions`, `audit.pr_disposition_record`/`work_item_ledger_record`) match this plan's mapping table verbatim. |
| Existing run-epic helpers already implement the policy path | `ls scripts/development-workflow/run-epic-*.sh` | `run-epic-scope-resolver.sh`, `run-epic-policy-recommender.sh`, `run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh` all exist. No new helper scripts are required. |
| Delegated gate already consumes a policy + evidence object | `grep -nE "policy.delegateReview\|policy.mayMerge\|policy.mayStartBacklog\|merge_allowed\|fix_required\|human_required" scripts/development-workflow/run-epic-delegated-gate.sh` | Gate reads `policy.delegateReview`, `policy.mayMerge`, `policy.mayStartBacklog`, plus `pr`/`risk`/`reviewer`/`statusChecks` evidence and emits `merge_allowed` / `fix_required` / `human_required` / `blocked`. The guardrails config maps directly onto these fields — no gate change needed. |
| Risk classifier interface | `grep -nE "run-epic-risk-classifier.sh --pr\|--max-risk\|merge_permitted" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | `run-epic-risk-classifier.sh --pr <n> --max-risk <low\|medium\|high>` returns `merge_permitted`; risk scale `low\|medium\|high` matches the #979 model exactly. |
| Audit helpers and stable markers | `grep -nE "run-epic-audit-trail.sh\|run-epic:pr-disposition\|run-epic:epic-ledger" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | `run-epic-audit-trail.sh render/apply pr-disposition` (marker `<!-- run-epic:pr-disposition -->`) and `render/apply epic-ledger` (marker `<!-- run-epic:epic-ledger -->`) already exist; reruns update existing markers. Reused for audit-evidence recording. |
| Decision points already exist in Protocol 91 | `grep -nE "Step 7a\|Step 7\|Step 8\|Backlog\|ready-for-human-review\|Determine the Next Deterministic Action" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Backlog-start (Step 2 routing table), PR-open (Step 2 "branch pushed, no PR yet" rows + Step 7a), review handoff (Step 7a/7), readiness/merge handoff (Step 8/8a), completion (Step 8b tracker update). Enforcement attaches at these existing points; no new control flow. |
| Run-start summary surface exists | `grep -n "Work Item Runner Summary\|Step 6: Notify Humans" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`; `grep -n "Step 6a\|policy\|preflight" docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Protocol 95 Step 6a already prints an effective-policy preflight summary; Protocol 91 has a "Work Item Runner Summary". The effective-guardrails report attaches to these surfaces. |
| Files that reference the orchestration protocols (lockstep targets) | `grep -rl "90-batch-orchestrate-work-protocol\|91-orchestrate-work-protocol\|95-run-epic-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/` | `.claude/agents/orchestrator.md`, `.claude/agents/item-orchestrator.md`, `.cursor/agents/orchestrator.md`, `.cursor/agents/item-orchestrator.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/post-merge-cleanup/SKILL.md`, `.agents/skills/run-epic/SKILL.md`. |
| README index location for the new reference page | `grep -nE "^### (Core Protocols\|Tooling And Configuration)\|guardrails" docs/workflow/development-workflow/README.md` | "Core Protocols" lists protocols; "Tooling And Configuration" lists `.ai-dev-workflow.yaml` and helpers — the new `guardrails-enforcement.md` belongs in "Tooling And Configuration" next to the #979 `guardrails.md` reference. |
| No prior guardrails-enforcement doc/term | `grep -rln "guardrails" docs/workflow/ scripts/ REVIEW.md` | Only incidental English uses in unrelated protocols/integrations; no enforcement doc and no `guardrails`-keyed config consumed by any script. The enforcement reference is net-new. |

---

## Layer-by-Layer Changes

> This feature has no Database, Backend/API, Shared Package, or Frontend/UI
> layers. The only affected layers are **Workflow Protocols & Documentation**
> and **Configuration (read-only consumption)**. No script behavior changes —
> the existing run-epic helpers are reused as-is.

### Workflow Protocols & Documentation

#### A. New canonical reference: `docs/workflow/development-workflow/guardrails-enforcement.md`

- [ ] Create the enforcement reference page that the three protocols link to so
      the mapping is defined once and reused. It must cover (each maps to spec
      ACs / Business Rules):
  1. **Effective-guardrails resolution** — the three-layer precedence
     (repository config base → session overrides → invocation overrides) and
     the rule that an override may narrow or widen authority only within what
     the repository config and autonomy mode permit; it may never grant
     authority the mode forbids. (UC1, BR "layering"; BR "override may not grant
     authority the mode forbids".)
  2. **Config-field → run-epic-policy mapping table** — the single source of
     truth that maps the #979 `guardrails` fields onto the existing run-epic
     helper inputs, so enforcement reuses one policy path:

     | #979 guardrails field | Effective concept | Maps to existing run-epic input |
     | --- | --- | --- |
     | `mode` (`manual`/`assisted`/`delegated`/`autonomous`) | Baseline authority summary | Baseline for `--delegate-review` / `--may-merge` / `--may-start-backlog` before per-stage refinement |
     | `stages.<stage>.may_open_pr` | May open PR at stage | PR-open gate (no run-epic flag equivalent — new named gate, enforced in Protocol 91 PR-open point) |
     | `stages.<stage>.may_merge_pr` | May merge PR at stage | `policy.mayMerge` consumed by `run-epic-delegated-gate.sh`, scoped per stage |
     | `stages.<stage>.max_merge_risk` (`low`/`medium`/`high`) | Stage merge-risk ceiling | `--max-risk` passed to `run-epic-risk-classifier.sh` |
     | `stages.<stage>.required_evidence` (e.g. `regression`) | Required readiness evidence | Maps to label/check evidence the delegated gate already checks (`ready-for-regression`, CI greenness) |
     | `backlog_start.allow_without_confirmation` | Backlog-start authority | `policy.mayStartBacklog` consumed by the delegated gate; gates the Protocol 90/91 backlog-start transition |
     | `audit.pr_disposition_record` | PR disposition audit required | `run-epic-audit-trail.sh apply-pr-disposition` (marker `<!-- run-epic:pr-disposition -->`) |
     | `audit.work_item_ledger_record` | Item-level ledger required | `run-epic-audit-trail.sh apply-epic-ledger` (marker `<!-- run-epic:epic-ledger -->`) when an epic/parent exists; otherwise "not applicable" |
     | `stop_conditions[]` | Named human-stops | Stop-and-name behavior (UC7); these add to but never weaken the baseline stops |

     (BR "reuse or generalize the existing `/run-epic` concepts and must not
     create a second, conflicting policy path"; UC4/UC5/UC8.)
  3. **Per-stage authority resolution** — how `mode` provides the baseline and
     explicit `stages.<stage>.*` values refine it per stage (spec/plan/
     implementation), independently. (UC1, UC3.)
  4. **Named stop conditions** — enumerate the recognized stop names consumed by
     this enforcement, **at minimum** the eight from the #979 model plus the
     enforcement-specific ones named in the spec: `unclear_requirements`,
     `architecture_decision`, `failing_ci`, `unresolved_blocking_review`,
     `high_risk_change`, `destructive_action`, `missing_tracker_context`,
     `missing_required_secret_or_permission`, plus
     `guardrails_config_unreadable` (UC1 considerations / UC7 / AC "unreadable or
     contradictory config") and `missing_audit_evidence` (UC6/UC8). State that
     these **add to but never weaken** the baseline human-stops, regardless of
     mode. The exact stop-name strings must match the `stop_conditions` values
     defined in the merged #979 `guardrails.md`; re-confirm in Step 0. (BR
     "configured stop conditions may add to, but may never remove, the
     framework's baseline human-stop conditions"; UC7.)
  5. **Stop-message contract** — every stop names (a) the exact guardrail or stop
     condition, (b) the affected work item, and (c) the human action required to
     unblock. (UC7, AC unclear-requirements stop.)
  6. **Unreadable / contradictory config rule** — an unreadable or internally
     contradictory `guardrails` block is the `guardrails_config_unreadable` stop
     condition; orchestration stops **before any artifact-mutating action** and
     never assumes a permissive value. (UC1 considerations, UC7, AC
     unreadable-config.)
  7. **Conservative-defaults statement** — when no `guardrails` section is
     present, the effective guardrails resolve to the #979 documented safe
     defaults (mode `manual`: no delegated merge; `backlog_start` confirmation-
     gated) and the run summary states defaults are in effect. (UC1, BR
     "conservative defaults", AC no-config.)
  8. **Audit-evidence rules** — reuse the run-epic disposition/ledger markers so
     reruns update existing records; redact secrets/credentials/tokens/local-only
     paths before writing any audit record; audit records are evidence only and
     never grant merge authority. (UC8, BR "redact secrets", BR "audit records
     do not grant merge authority".)

#### B. Protocol 91 — `91-orchestrate-work-protocol.md` (Work Item Runner)

This is where the five decision points live for a single item. Add a new
**"Step 0: Load Effective Guardrails"** subsection and attach named gates to the
existing decision points (do not restructure the existing flow):

- [ ] **Load + report effective guardrails (Step 0, new)**: resolve repo config
      → session → invocation overrides; resolve effective mode, per-stage
      open/merge permissions, per-stage max merge risk, backlog-start policy,
      required evidence, stop conditions, and audit requirements; state them in
      the **Work Item Runner Summary** before any artifact-mutating action,
      noting which values an override changed. If the config is unreadable or
      contradictory, stop with `guardrails_config_unreadable` before mutating.
      (UC1; AC run-summary-states-effective-guardrails; AC unreadable-config.)
- [ ] **Backlog-start gate** at the Step 2 "Backlog (…)" routing rows: before
      transitioning a not-yet-started item into Writing Spec / Writing Plan /
      In Development, check `backlog_start.allow_without_confirmation`; if not
      allowed, stop and ask the human, naming the items proposed to start.
      Resuming an in-progress item is **not** a backlog start. (UC2; AC
      backlog-start-requires-confirmation; AC backlog-start-allowed.)
- [ ] **PR-open gate** at the Step 2 "branch pushed, no PR yet" rows and the
      Step 7a draft-PR entry: before opening a stage PR, check
      `stages.<stage>.may_open_pr`; if not permitted, do not open the PR and
      report the exact `may_open_pr` guardrail that blocked it. Independent of
      the merge gate. (UC3; AC stage-open-forbidden.)
- [ ] **Delegated review-decision gate** at the Step 7a/Step 7 review handoff:
      only make the review decision when the effective guardrails grant delegated
      review authority for the stage (per the mapping table); otherwise leave the
      PR waiting for human review at its normal handoff. Reuse the existing
      review-and-fix loop (do not introduce a second loop): blocking findings →
      remove readiness, fix, re-run validation + reviewer loop + CI, reassess;
      advisory findings → explicit per-finding fix-or-accept with recorded
      rationale; restore readiness only when reviewer loop, CI, and unresolved
      threads are clean. (UC4; AC no-delegated-review-leaves-waiting.)
- [ ] **Delegated merge gate** at the Step 8/8a readiness handoff: only when the
      effective guardrails grant merge authority for the stage, assemble the
      evidence object and run `run-epic-risk-classifier.sh` (with the stage
      `max_merge_risk`) and `run-epic-delegated-gate.sh`. Merge through the
      repository-approved path only when the gate returns `merge_allowed` **and**
      every required-evidence check passes: clean reviewer loop, green CI with no
      pending/failing/unavailable/ambiguous required check, required readiness
      labels (including `ready-for-regression` when implementation
      `required_evidence` includes regression), clean merge state, no unresolved
      blocking thread, acceptable reviewer disposition, recorded audit evidence,
      and classified risk at or below the stage `max_merge_risk`. A
      medium-risk delegated merge requires a complete "why safe to merge"
      explanation (scope, tests, reviewer outcome, CI outcome, rollback/cleanup
      risk). High risk is never merged automatically under default guardrails. A
      risk above the stage maximum stops the run naming the
      `high_risk_change` / stage `max_merge_risk` guardrail. (UC5; ACs
      allowed-merge, blocked-merge-missing-evidence, high-risk-stop.)
- [ ] **Completion gate** at the Step 8b tracker-status transition: mark an item
      complete for a stage only after the stage outcome is confirmed **against
      live state** (PR `MERGED` or the configured completion condition) **and**
      the required audit evidence is recorded; never infer completion from stale
      memory, branch names, or prior resolver output. Missing audit →
      `missing_audit_evidence` stop. (UC6; BR completion-verified-against-live-
      state.)
- [ ] **Stop-and-name behavior** anywhere a configured stop condition is met or
      required state is missing: stop before the guarded action and report the
      exact stop condition, the work item, and the human action required.
      Guardrail stops never weaken the baseline human-stops. (UC7; all stop ACs.)
- [ ] **Audit recording** after any delegated review/fix/merge/block/escalation:
      use `run-epic-audit-trail.sh` to write/update the PR disposition record
      (and the item ledger when a parent/epic exists), reusing the stable markers
      so reruns update rather than duplicate; redact secrets before writing.
      (UC8; AC audit-record-exists-and-rerun-updates.)

#### C. Protocol 90 — `90-batch-orchestrate-work-protocol.md` (Portfolio Orchestrator)

- [ ] **Load + report effective guardrails at portfolio run start** (new
      subsection near Step 1/Step 2.5), before any tracker mutation or dispatch,
      and state them in the portfolio run summary — noting override-changed
      values. Unreadable/contradictory config → `guardrails_config_unreadable`
      stop before any mutation. (UC1; AC run-summary; AC unreadable-config.)
- [ ] **Backlog-start gate** at the Step 2/Step 2.5 transition where the
      orchestrator would move a not-yet-started item into an active stage: honor
      `backlog_start.allow_without_confirmation`; otherwise stop and confirm,
      naming the items. (UC2.)
- [ ] **Pass effective guardrails into each dispatched Work Item Runner** so the
      per-item gates in Protocol 91 enforce the same resolved guardrails (state
      that the dispatched runner inherits the portfolio-resolved guardrails;
      invocation/session overrides resolved at the portfolio level flow down).
      (UC1; BR layering.)
- [ ] Reference `guardrails-enforcement.md` as the single source for the mapping
      and stop-condition names rather than restating the mapping inline.

#### D. Protocol 95 — `95-run-epic-protocol.md` (Epic Runner)

- [ ] **Reconcile guardrails with the existing epic policy flags** without
      changing flag behavior: state that the `--delegate-review`, `--may-merge`,
      `--may-start-backlog`, and `--max-risk` flags are the **invocation-override
      layer** over the repository `guardrails` config, and that the effective
      guardrails are resolved by the same three-layer precedence. The risk
      classifier, delegated gate, and audit trail referenced here are the same
      helpers Protocols 90/91 now reuse — confirm this is the **one** policy
      path. Add a short cross-link to `guardrails-enforcement.md` so the mapping
      and stop names are defined once. (BR "reuse/generalize run-epic concepts,
      no second policy path"; UC5 consideration "reuses the existing `/run-epic`
      risk-classification and delegated-gate concepts".)
- [ ] No change to the read-only resolver guarantees, the helper invocations, or
      the merge/cleanup steps — this is documentation alignment only.

#### E. Lockstep agent and skill mirrors

The five orchestration decision points and the "load + report effective
guardrails" behavior are a **cross-cutting authority contract** that the agent
and skill files describing orchestration must reflect, or a runner following the
agent/skill text alone would skip the new gates. Update each to reference
`guardrails-enforcement.md` and summarize the load/report + five-gate behavior
(do not restate the full mapping — link to the reference):

- [ ] `.claude/agents/orchestrator.md` — Portfolio Orchestrator (Protocol 90).
- [ ] `.claude/agents/item-orchestrator.md` — Work Item Runner (Protocol 91).
- [ ] `.cursor/agents/orchestrator.md` — Cursor Portfolio Orchestrator.
- [ ] `.cursor/agents/item-orchestrator.md` — Cursor Work Item Runner.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` — Codex orchestrator skill.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` — Codex item-orchestrator skill.
- [ ] `.agents/skills/run-epic/SKILL.md` — run-epic skill (note guardrails are
      the repo-config layer under the epic flags; same policy path).
- [ ] `.agents/skills/run-work/SKILL.md` — run-work skill entrypoint (load +
      report effective guardrails at run start; enforce the five gates).
- [ ] `.agents/skills/run-item-work/SKILL.md` — run-item-work skill entrypoint
      (inherits/loads effective guardrails; enforce the five per-item gates).
- [ ] `.claude/commands/run-work.md`, `.claude/commands/run-item-work.md`,
      `.claude/commands/run-epic.md` — add a one-line note that delegated
      execution enforces the repository guardrails (link to
      `guardrails-enforcement.md`). Keep command files thin — a pointer only.

> The implementer must run the live-search command in the Implementation Order
> (Step 2) at implementation time and reconcile this list against the result,
> because new orchestration-referencing files may have landed on
> `develop-guardrails` after this plan was written.

#### F. Review contract — `REVIEW.md`

- [ ] Add a guardrails-enforcement review expectation to `REVIEW.md` so plan and
      code reviewers verify that any change to orchestration behavior preserves
      the named-stop contract and the single run-epic policy path, and that
      delegated merge/review/backlog-start/completion gates and audit recording
      are present where the protocols require them. This is the cross-cutting
      review category for this contract. (BR "must not create a second,
      conflicting policy path"; baseline-stop-preservation BRs.)

### Configuration (read-only consumption)

- [ ] **No change to `.ai-dev-workflow.yaml`.** The `guardrails` block is owned
      by #979. This feature only **reads** that block. Confirm in Step 0 that the
      merged field names match this plan's mapping table; do not add or rename
      config keys here. (Spec Out-of-Scope: "Defining the guardrails
      configuration schema … is owned by #979".)

---

## Testing Strategy

**Test types**: Documentation/protocol review + smoke-test runbook
(documentation-and-protocol verification). No automated unit tests apply — this
feature ships protocol/doc prose and **reuses** existing scripts whose behavior
does not change. The relevant automated gate is the existing run-epic helper
behavior (already unit/scenario-covered under
`scripts/development-workflow/tests/`) plus markdown lint on the changed docs.

**Key scenarios to test** (all via the smoke test runbook; each maps to a spec
acceptance criterion):

1. Run summary states effective guardrails (mode, per-stage open/merge
   permissions, per-stage max merge risk, backlog-start policy, stop conditions)
   and notes override-changed values — AC run-summary-with-override.
2. With no `guardrails` section, run summary states conservative defaults
   (no delegated merge, backlog confirmation-gated) — AC no-config-defaults.
3. Backlog-start policy requiring confirmation stops before starting a
   not-yet-started item and names the items — AC backlog-start-confirmation.
4. Backlog-start policy allowing start proceeds without asking — AC
   backlog-start-allowed.
5. A stage forbidding `may_open_pr` for implementation blocks the PR-open and
   names the `may_open_pr` guardrail — AC stage-open-forbidden.
6. Guardrails without delegated review authority leave the PR waiting for human
   review — AC no-delegated-review.
7. Full delegated merge with clean reviewer/CI, required labels, clean merge
   state, no unresolved thread, recorded audit, and risk at/below the stage
   maximum merges via the repository-approved path — AC allowed-merge.
8. The same setup with one missing evidence item (CI not green / missing label /
   unresolved thread / missing audit) does **not** merge and names the exact
   missing evidence — AC blocked-merge-missing-evidence.
9. Implementation `max_merge_risk: medium` with a PR classified high stops and
   names the risk guardrail — AC high-risk-stop.
10. Unclear-requirements item stops at the decision point and names
    `unclear_requirements` (or the configured stop) plus the human action — AC
    unclear-requirements-stop.
11. A delegated merge/block decision produces an audit record covering original
    command, resolved scope, effective guardrails, risk rationale, reviewer/CI
    outcome, and final decision; a rerun **updates** the record — AC audit-record.
12. Unreadable/contradictory `guardrails` config stops before any
    artifact-mutating action and reports the config problem — AC unreadable-config.
13. All of the above are exercisable through the existing reviewer-loop and
    CI-gate infrastructure and the run-epic helpers without new external services
    — AC verifiable-with-existing-harness.

**Smoke test runbook**: `docs/testing/workflow/980-enforce-guardrails-delegated-run-work.smoke-test.md`

**Regression suite**: The repository has no application-level regression suite
for protocol prose. The relevant automated gates are (a) the existing run-epic
helper tests under `scripts/development-workflow/tests/` (unchanged — this
feature does not modify the helpers, so no new helper test is required) and
(b) `markdownlint-cli2` + heuristic lint on the changed docs, which run in CI.
No new automated regression spec is added because no script behavior changes.

> **Parser-risk addendum**: Not applicable. No file under `scripts/lint/`,
> `scripts/parse/`, or any scanner/tokenizer/regex module is introduced or
> changed. The `guardrails` config is read by the existing config resolver and
> the existing run-epic helpers, none of which this feature modifies; no new
> structured-text scanning behavior is added.
>
> **Concurrent-event-source addendum**: Not applicable. Orchestration advances
> one deterministic action at a time; no event listeners, socket callbacks,
> timers, async queues, or shared mutable state are introduced. Parallel batches
> already use worktree isolation (Protocol 90/91) and this feature adds no new
> concurrent execution context.

### Cross-cutting checklist note

This plan **introduces a cross-cutting authority/safety contract** (guardrails
enforcement applies across every orchestration stage decision and adds a
`REVIEW.md` review expectation). Per Protocol 02, the full set of lockstep files
is enumerated in **Layer-by-Layer §E and §F** and the Documentation Updates
section: the three orchestration protocols (90/91/95), the new
`guardrails-enforcement.md`, the README index, the orchestrator/item-orchestrator
agents (Claude + Cursor), the orchestrator/item-orchestrator/run-epic/run-work/
run-item-work skills, the run-work/run-item-work/run-epic command files, and
`REVIEW.md`. The developer/tech-lead planning and implementation protocols
(`02-…`, `03-…`) and the `developer.md` agents are **not** modified, because this
contract governs **orchestration runtime decisions**, not what every feature plan
or implementation PR must contain — the live search in Implementation Order
Step 2 confirms which files reference the orchestration protocols and must stay
in lockstep.

---

## Seed Data

> No application or database seed data applies. "Seed" for the smoke test is the
> set of fixture `guardrails` config blocks the runbook supplies.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Effective-guardrails fixtures | A `manual`/no-section config, a `delegated` config allowing spec/plan/impl merges within risk limits, a config with implementation `max_merge_risk: medium` + `required_evidence: [regression]`, and an intentionally contradictory config | Inline in the smoke test runbook (no committed fixture files; documentation-only) |

---

## Documentation Updates

> For this feature, protocol and reference documentation **is** the deliverable,
> so these edits are in scope for the implementation PR. The list below is the
> contract.

- [ ] **Create** `docs/workflow/development-workflow/guardrails-enforcement.md`
      (the 8-section reference in Layer-by-Layer §A).
- [ ] **Update** `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      (load + report guardrails; five named gates; stop-and-name; audit) — §B.
- [ ] **Update** `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      (load + report at portfolio start; backlog-start gate; pass guardrails to
      dispatched runners) — §C.
- [ ] **Update** `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      (reconcile epic flags as the invocation-override layer; single policy
      path; cross-link the reference) — §D.
- [ ] **Update** `docs/workflow/development-workflow/README.md` — add
      `guardrails-enforcement.md` to the "Tooling And Configuration" index
      (next to the #979 `guardrails.md` entry).
- [ ] **Update** the lockstep agent files: `.claude/agents/orchestrator.md`,
      `.claude/agents/item-orchestrator.md`, `.cursor/agents/orchestrator.md`,
      `.cursor/agents/item-orchestrator.md` — §E.
- [ ] **Update** the lockstep skill files:
      `.codex/skills/workflow-orchestrator/SKILL.md`,
      `.codex/skills/workflow-item-orchestrator/SKILL.md`,
      `.agents/skills/run-epic/SKILL.md`, `.agents/skills/run-work/SKILL.md`,
      `.agents/skills/run-item-work/SKILL.md` — §E.
- [ ] **Update** the command files: `.claude/commands/run-work.md`,
      `.claude/commands/run-item-work.md`, `.claude/commands/run-epic.md`
      (one-line pointer each) — §E.
- [ ] **Update** `REVIEW.md` — add the guardrails-enforcement review
      expectation — §F.
- [ ] `AGENTS.md` / `CLAUDE.md` — _None required._ The "Key Documentation" table
      already links the workflow README, which will index
      `guardrails-enforcement.md`. A row may be added for discoverability but no
      acceptance criterion requires it.
- [ ] `docs/project/*`, `docs/best-practices/*` — _None._ This feature changes
      workflow orchestration behavior, not project domain/architecture or coding
      standards.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| #979 config field names differ from this plan's mapping table once #979 merges | Med | Med | Step 0 dependency gate re-confirms every field name against the merged `.ai-dev-workflow.yaml` and `guardrails.md`; the mapping table is the single place to reconcile. Implementer uses merged names verbatim. |
| Enforcement accidentally weakens a baseline human-stop (e.g., a guardrail "allows" something the baseline forbids) | Med | High | The reference page and `REVIEW.md` state explicitly that guardrails may only **add** stops and may **never** remove the baseline human-stops; an override may not grant authority the mode forbids. Smoke scenarios 9, 10, 12 exercise stops. |
| A second, conflicting policy path is created instead of reusing run-epic helpers | Med | High | The mapping table binds every guardrail field to an existing run-epic helper input; §D requires Protocol 95 to confirm a single policy path; no new scripts are introduced (Verification Log). |
| Agent/skill mirrors drift from the protocols, so a runner skips the new gates | High | Med | §E enumerates every lockstep file; Implementation Order Step 2 re-runs the live search; cross-section consistency self-check confirms gate names match across protocols, reference, agents, skills, and `REVIEW.md`. |
| Reader infers the `guardrails` config schema is defined here | Low | Med | Every surface states the schema is #979-owned and this feature only reads it; no `.ai-dev-workflow.yaml` change. |
| Stop-condition name strings diverge between the reference, the protocols, and the #979 `guardrails.md` | Med | Med | Re-confirm stop-name strings against merged #979 in Step 0; define them once in `guardrails-enforcement.md` and reference (not restate) elsewhere. |
| Markdown lint failures (broken relative links, trailing whitespace) across many edited files | Med | Low | Run `markdownlint-cli2` + heuristic lint on every changed doc before commit, per Implementation Order. |

---

## Code Samples

> The only "code" is the documented field → helper mapping and the assembled
> evidence object passed to the existing run-epic delegated gate. The block below
> is **illustrative — adapt wording during implementation**; field names are the
> #979-owned contract and must match the merged `guardrails.md`. No new scripts
> are written.

```jsonc
// Illustrative — the evidence/policy object the existing
// run-epic-delegated-gate.sh already consumes, populated from the effective
// guardrails for one candidate PR. Field names on the `policy` side derive from
// the #979 `guardrails` config via the mapping table; reuse the gate as-is.
{
  "policy": {
    "delegateReview": true,        // from effective mode + stage authority
    "mayMerge": true,              // from stages.<stage>.may_merge_pr
    "mayStartBacklog": false       // from backlog_start.allow_without_confirmation
  },
  "item":   { "status": "Development in Review" },
  "pr":     { "isDraft": false, "inScope": true, "labels": ["ready-for-human-review", "ready-for-regression"],
              "mergeStateStatus": "CLEAN", "unresolvedBlockingThreads": 0,
              "auditDispositionPresent": true },
  "reviewer": { "status": "clean", "blockingCount": 0, "acceptedAdvisoriesWithoutRationale": 0 },
  "statusChecks": [ { "status": "completed", "conclusion": "success" } ],
  "risk":   { "mergePermitted": true } // from run-epic-risk-classifier.sh --max-risk <stages.<stage>.max_merge_risk>
}
```

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones. **Step 1 is a hard
> dependency gate.**

1. **Dependency gate (#979)** — run the Step 0 verification at the top of this
   plan. Confirm the `guardrails` block in `.ai-dev-workflow.yaml` and
   `docs/workflow/development-workflow/guardrails.md` exist on
   `develop-guardrails`. If either is missing, **stop** with named cause
   `dependency:#979-not-merged` and wait for #979 to merge. Once present, read
   both and record the canonical field names and `stop_conditions` strings to
   use verbatim in every edit below.
2. **Re-run the lockstep live search** and reconcile the §E/§F file list:

   ```bash
   grep -rl "90-batch-orchestrate-work-protocol\|91-orchestrate-work-protocol\|95-run-epic-protocol" \
     .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ .claude/commands/
   ```

   Add any new orchestration-referencing file to the edit set; confirm the
   command files (`run-work`, `run-item-work`, `run-epic`) and skills are still
   present.
3. **Create `docs/workflow/development-workflow/guardrails-enforcement.md`** with
   the 8 sections in Layer-by-Layer §A, using the merged #979 field names and
   stop-condition strings from Step 1. This is the single source for the mapping
   and stop names that the other edits link to.
4. **Edit Protocol 91** (§B): add "Step 0: Load Effective Guardrails", the
   load+report behavior in the Work Item Runner Summary, and the five named gates
   plus stop-and-name and audit recording attached to the existing decision
   points. Link to `guardrails-enforcement.md` rather than restating the mapping.
5. **Edit Protocol 90** (§C): add load+report at portfolio start, the
   backlog-start gate, and the rule that dispatched Work Item Runners inherit the
   portfolio-resolved guardrails. Link to the reference.
6. **Edit Protocol 95** (§D): reconcile the epic flags as the invocation-override
   layer over the repo `guardrails` config; state the single policy path; add the
   cross-link. No helper-invocation or merge/cleanup changes.
7. **Update README** (Tooling And Configuration index) to list
   `guardrails-enforcement.md`.
8. **Update the lockstep agent files** (Claude + Cursor orchestrator and
   item-orchestrator) to reference the enforcement reference and summarize the
   load/report + five-gate behavior.
9. **Update the lockstep skill files** (`workflow-orchestrator`,
   `workflow-item-orchestrator`, `run-epic`, `run-work`, `run-item-work`) and the
   three command files with the guardrails pointer.
10. **Update `REVIEW.md`** with the guardrails-enforcement review expectation.
11. **Cross-section consistency pass**: confirm the five gate names, the stop-
    condition strings, the config-field → helper mapping, the `guardrails-
    enforcement.md` filename/links, and the helper script names are identical
    across the reference, Protocols 90/91/95, the agents, the skills, the command
    files, and `REVIEW.md`.
12. **Verify the smoke test runbook** scenarios are each satisfied by the protocol
    text, by reading the runbook against the edited protocols.
13. **Run markdown lint** on every changed/added doc:

    ```bash
    REPO_ROOT=$(git rev-parse --git-common-dir)/..
    "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
      "docs/specs/developments/20260617083237_980-enforce-guardrails-delegated-run-work/2_980-enforce-guardrails-delegated-run-work_implementation-plan.md" \
      "docs/testing/workflow/980-enforce-guardrails-delegated-run-work.smoke-test.md" \
      "docs/workflow/development-workflow/guardrails-enforcement.md" \
      "docs/workflow/development-workflow/README.md" \
      "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
      "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
      "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
      "REVIEW.md"
    ```

    Then run the heuristic lint on the changed docs; fix any violations.
14. **Documentation is the deliverable** — there are no additional project-doc
    updates beyond those listed in Documentation Updates.
15. **Update `CHANGELOG.md`** under `[Unreleased]` using the project's
    `**Bold Title** (#N):` format. Suggested literal entry under `### Added`:
    `- **Enforce guardrails in delegated /run-work execution** (#980): orchestration now loads the effective guardrails (repository config, then session, then invocation overrides), reports them in the run summary, and enforces them at backlog-start, per-stage PR-open, delegated review, delegated merge (risk + reviewer/CI/label/thread/audit), and completion — naming the exact guardrail on every stop. Reuses the existing /run-epic risk-classifier, delegated-gate, and audit-trail helpers as one policy path rather than a second model. Reads the #979 guardrails config; no schema change.`
