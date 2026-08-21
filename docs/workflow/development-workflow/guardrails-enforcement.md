# Guardrails Enforcement Reference

This page defines the single enforcement path that all orchestration protocols
(`90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, and
`95-run-epic-protocol.md`) follow when guardrails are configured. It is the
**single source of truth** for:

- How the effective guardrails are resolved from multiple sources.
- How each `guardrails` config field maps to the existing run-epic helper inputs.
- What the named stop conditions mean and how they interact with baseline stops.
- The stop-message contract every enforcement point must follow.
- What happens when the `guardrails` config is absent or unreadable.
- How audit evidence is recorded and updated.

> **Schema ownership**: The `guardrails` configuration schema — field names,
> accepted values, defaults, and examples — is defined by `guardrails.md`. This
> page only describes how orchestration **reads** that config and enforces it at
> runtime. Do not add or rename config fields here.

---

## 1. Effective-Guardrails Resolution (Three-Layer Precedence)

At the start of every orchestration run, before any artifact-mutating action,
the runner resolves the **effective guardrails** by layering three sources in
priority order:

| Layer | Source | Priority |
| ----- | ------ | -------- |
| 1 (lowest) | Repository configuration — the `guardrails` block in `.ai-dev-workflow.yaml` | Base values |
| 2 | Session overrides — values set earlier in the same conversation | Override base |
| 3 (highest) | Invocation overrides — flags or values supplied with the current invocation (e.g., `--delegate-review`, `--may-merge`, `--max-risk`) | Override session |

**Narrowing/widening rule**: An override at any layer may narrow or widen
authority **only within what the repository configuration and the effective
autonomy mode permit**. An override may never grant authority that the mode
forbids. For example, when the repository config declares `mode: assisted`
(meaning agents never merge), an invocation-override flag of `--may-merge` does
not grant merge authority unless `mode` is also elevated by the override.

The resolved set of values is the **effective guardrails** for the run. The
runner must state the effective guardrails before any artifact-mutating action
and note which values were changed by an override.

---

## 2. Config-Field → Run-Epic-Policy Mapping Table

The run-epic helpers (`run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`,
`run-epic-audit-trail.sh`) already implement the policy/risk/gate/audit behavior
that this feature generalizes. The table below is the **single, authoritative
mapping** from the `guardrails` config fields (owned by `guardrails.md`) to the
existing run-epic helper inputs.

Protocols 90 and 91 consume this mapping rather than defining their own policy
model — there is **one** policy path, not two.

| `guardrails` field | Effective concept | Maps to existing run-epic input |
| --- | --- | --- |
| `mode` (`manual`/`assisted`/`delegated`/`autonomous`) | Baseline authority summary | Baseline for `--delegate-review` / `--may-merge` / `--may-start-backlog` before per-stage refinement |
| `stages.<stage>.may_open_pr` | May open PR at this stage | PR-open gate (named gate enforced in Protocol 91 at the branch-pushed / Step 7a entry point; no run-epic flag equivalent) |
| `stages.<stage>.may_merge_pr` | May merge PR at this stage | `policy.mayMerge` consumed by `run-epic-delegated-gate.sh`, scoped per stage |
| `stages.<stage>.max_merge_risk` (`low`/`medium`/`high`) | Stage merge-risk ceiling | `--max-risk` passed to `run-epic-risk-classifier.sh` |
| `stages.<stage>.required_evidence` (e.g., `regression`) | Required readiness evidence before merge | Label/check evidence the delegated gate already checks (`ready-for-regression`, CI greenness) |
| `backlog_start.allow_without_confirmation` | Backlog-start authority | `policy.mayStartBacklog` consumed by the delegated gate; gates the Protocol 90/91 backlog-start transition |
| `audit.pr_disposition_record` | PR disposition audit required | `run-epic-audit-trail.sh apply-pr-disposition` (stable marker `<!-- run-epic:pr-disposition -->`) |
| `audit.work_item_ledger_record` | Item-level ledger required | `run-epic-audit-trail.sh apply-epic-ledger` (stable marker `<!-- run-epic:epic-ledger -->`) when a parent/epic exists; otherwise "not applicable" |
| `stop_conditions[]` | Named human-stops | Stop-and-name behavior (see section 4); these add to but never weaken the baseline stops |
| Epic checkpoint policy (`checkpoints[]` on effective policy) | Stage-scoped, item-specific human stops declared before mutation | `run-epic-policy-recommender.sh` output (`recommendedPolicy.checkpoints`, `selectedPolicy.checkpoints`, `effectivePolicy.checkpoints`, `checkpointPolicy`); consumed by delegated gate (#1023) and audit trail (#1022); **not** a `.ai-dev-workflow.yaml` schema field |

Epic human checkpoints extend the same run-epic policy object — they are not
separate guardrails config fields. The recommender proposes them from read-only
item metadata; the human selects or waives them before mutation. Audit evidence
records original, recommended, selected, and effective checkpoint policy via
`checkpointPolicy` on the recommender JSON output and later PR/epic ledger
comments.

### Per-Stage Authority Resolution

The `mode` field provides the **baseline** authority for all stages:

| Mode | Default `may_merge_pr` | Default `backlog_start` |
| ---- | ----------------------- | ----------------------- |
| `manual` | `false` | confirmation required |
| `assisted` | `false` | confirmation required |
| `delegated` | depends on explicit `stages.*` values | confirmation required unless explicitly set |
| `autonomous` | depends on explicit `stages.*` values | allowed without confirmation |

Explicit `stages.<stage>.*` values **override** the mode baseline for that
specific stage independently. A repository may grant `may_merge_pr: true` for
`spec` and `plan` while setting `may_merge_pr: false` for `implementation` —
even when `mode: delegated`.

---

## 3. Six Named Enforcement Gates

Orchestration enforces guardrails at six decision points. These gates attach
to **existing** decision points in the protocols; they do not introduce new
control-flow paths.

### Gate 1 — Load and Report at Run Start

Before any artifact-mutating action, the runner:

1. Resolves the effective guardrails using the three-layer precedence (section 1).
2. States the effective autonomy mode, per-stage open/merge permissions,
   per-stage `max_merge_risk`, backlog-start policy, configured stop conditions,
   and audit requirements in the run summary — noting which values an override
   changed.
3. If the config is unreadable or internally contradictory, stops with the
   `guardrails_config_unreadable` stop condition before any mutation.

### Gate 2 — Backlog-Start Gate

Before transitioning a **not-yet-started** backlog item into Writing Spec,
Writing Plan, or In Development for the first time:

- If `backlog_start.allow_without_confirmation` is `true` (or the effective
  mode is `autonomous`): proceed without asking.
- If the run is a direct `/run-item` invocation and Protocol 91 recorded
  `RUN_ITEM_POLICY_CONFIRMED=true` with companion bindings for the same resolved
  item identifier and normalized selected policy: proceed without asking again.
  The selected policy must grant enough backlog-start authority for the proposed
  transition. Ignore the binding when the item differs, the selected policy
  differs, or the requested action exceeds the selected policy.
- Otherwise: stop and ask the human to confirm, naming the items proposed to
  start. Do not proceed until the human confirms.

Resuming an item that is already in progress (any status other than Backlog)
is **not** a backlog start; this gate does not apply to resumes.

### Gate 3 — PR-Open Gate

Before opening a stage pull request, check `stages.<stage>.may_open_pr` for
the relevant stage (`spec`, `plan`, or `implementation`):

- If `true` (the default): open the PR and continue.
- If `false`: do not open the PR; report the exact `stages.<stage>.may_open_pr`
  guardrail that blocked it.

This gate is **independent** of the merge gate. A configuration may allow
opening a PR while still forbidding automatic merge.

### Gate 4 — Delegated Review Gate

At the Step 7a/Step 7 review handoff:

- If the effective guardrails grant delegated review authority for the stage
  (i.e., `mode` is `delegated` or `autonomous` and `stages.<stage>.may_merge_pr`
  is not explicitly `false`): the runner may make the review decision.
- Otherwise: leave the PR waiting for human review at its normal handoff point.

When the runner does make the review decision, it **reuses the existing
review-and-fix behavior** — no second review loop:
- Blocking findings → remove readiness labels, apply deterministic fixes, push,
  rerun validation + reviewer loop + CI, reassess.
- Advisory findings → explicit per-finding fix-or-accept decision with recorded
  rationale.
- **Security-sensitive advisory carve-out**: for an advisory finding
  classified security-sensitive by
  `scripts/development-workflow/security-advisory-classifier.sh`, the runner
  never itself records an "accepted" or "rejected" disposition — regardless
  of delegated review authority. Only a fixed commit (cited) or a status of
  "pending" (awaiting a verified human accept/reject decision) is available.
  See the "Security-sensitive advisory classification" subsection of
  [`protocols/93-automated-reviewer-loop-protocol.md`](protocols/93-automated-reviewer-loop-protocol.md).
- Restore readiness labels only after reviewer loop, CI, and unresolved threads
  are clean.

### Gate 5 — Delegated Merge Gate

At the Step 8/8a readiness handoff, when merge authority is granted for the
stage (`stages.<stage>.may_merge_pr` is `true`), assemble the evidence object
and run the existing helpers:

```bash
# 1. Classify PR risk against the stage max_merge_risk. A medium-risk PR only
#    ever reaches a mergeable verdict if why_safe_to_merge evidence is
#    attached; --why-safe-file lets --pr carry that evidence directly instead
#    of switching to --input:
./scripts/development-workflow/run-epic-risk-classifier.sh \
  --pr <pr-number> --why-safe-file <why-safe-file> \
  --max-risk <stages.<stage>.max_merge_risk>

# 2. Run the delegated gate with the assembled evidence
./scripts/development-workflow/run-epic-delegated-gate.sh --input <evidence-file>
```

**These two helpers use different, independently documented evidence
schemas** — see `--help` on each script for the exact shape and a worked
example. Do not feed one script's output directly into the other's `--input`;
nest `run-epic-risk-classifier.sh`'s result under a top-level `"risk"` key when
assembling the delegated gate's `<evidence-file>` instead. Feeding the wrong
shape in does not always fail loudly: the delegated gate reports an
`evidence_schema_mismatch: ...` reason (rather than a generic
`delegated review/merge authority is missing` or `required CI state is
missing` reason) whenever a required object (`.policy`) or array key
(`.statusChecks`) is entirely absent, precisely because that absence is
otherwise indistinguishable from a real denial or a real "no CI has run"
state. Treat that reason as an instruction to fix the evidence file's shape,
not as a policy or CI verdict.

The evidence file's `pr.inScope` field is meaningful only when the runner has
a resolved `/run-epic` scope to check the candidate PR against. Protocol 90 and
91 callers assembling evidence for a `/run-items` or `/run-item` PR that has no
resolved epic scope should **omit** `pr.inScope` entirely — the gate skips the
scope check when the field is absent rather than defaulting to out-of-scope.
Only set `pr.inScope: false` when scope resolution genuinely excluded the
candidate PR; the gate then short-circuits with `decision: "not_applicable"`
instead of piling the mismatch in among unrelated reasons.

Similarly, `pr.mergeable` should be **omitted entirely** when that data is not
available — never defaulted to `""`. The gate treats a blank/whitespace-only
value exactly like an absent field (not blocked), but a caller-side default of
`""` for a field that was simply never requested from `gh pr view --json` used
to read as a real "PR is not mergeable" verdict for a PR GitHub reports as
`MERGEABLE`.

Merge through the repository-approved merge path **only when all of the
following are satisfied**:

- Gate returns `merge_allowed`.
- Reviewer-loop result is clean.
- CI is green with no pending, failing, unavailable, or ambiguous required check.
- Required readiness labels are present: `ready-for-human-review` always;
  `ready-for-regression` when `stages.<stage>.required_evidence` includes
  `regression`.
- Merge state is clean (no conflicts, not a draft, no force-push).
- No unresolved blocking review thread remains.
- Reviewer disposition is acceptable.
- Required audit evidence is recorded.
- Classified risk is at or below `stages.<stage>.max_merge_risk`.
- No `.securityAdvisories[]` entry remains `pending` after reconciliation at
  the current head SHA (`security_sensitive_advisory_pending`). **This
  requirement is independent of `mode`, `stages.<stage>.may_merge_pr`, and
  the satisfaction/waiver state of any unrelated bounded-prelude
  checkpoint** — mirroring the exceptional-bypass callout below, no batch
  approval or delegated authority substitutes for a fixed commit or a
  verified human accept/reject decision on a security-sensitive finding.
  Only a human, never the delegated agent, may record that a
  security-sensitive finding's risk is accepted or that the finding is a
  false positive.

If the only remaining blocker is a verified access-restricted third-party
reviewer check, the delegated gate does **not** return normal `merge_allowed`.
It returns `human_required` classifications such as `access_restricted`,
`authorization_required`, `authorization_stale`, or `audit_required` until the
runner has current CI/reviewer/check evidence, App-access remediation evidence,
a named human authorization for the exact PR, head SHA, and evidence
fingerprint, and a verified pre-attempt `<!-- reviewer-access-bypass -->` audit
record. Only then may the gate return `exceptional_bypass_authorized`, which
authorizes exactly one named command:

<!-- workflow-shell-contract: bash-zsh -->
```text
gh pr merge <pr> --admin --match-head-commit <authorized-head-sha>
```

Delegated mode, `may_merge_pr`, batch approval, risk tolerance, or satisfied
unrelated checkpoints never substitute for that authorization.

**Medium-risk merged decisions** require a complete "why safe to merge"
explanation covering scope, tests, reviewer outcome, CI outcome, and
rollback/cleanup risk. Missing this explanation blocks the merge.

**High-risk changes** are never merged automatically under default guardrails.
Merging a high-risk PR requires explicit human selection of `max_merge_risk: high`
for the stage.

### Merge Authority Terminal Contract

The selected merge authority controls whether readiness is terminal:

- `merge_granted`: readiness labels are intermediate. After readiness, the
  runner must continue through Gate 5 and the repository-approved merge path for
  every in-scope PR whose gates pass. A clean merge path ends as `merged` only
  after GitHub reports `MERGED`, branch cleanup runs, `post-merge-cleanup.sh`
  completes, and live tracker verification is reported.
- `merge_denied`: readiness labels are terminal for this run. The runner must
  not execute a merge command. The terminal outcome is `ready_human_merge`, and
  the summary must name the exact `stages.<stage>.may_merge_pr: false` or
  invocation policy value that requires human review or merge.

If merge authority is granted but an in-scope PR cannot proceed after readiness
because a named gate fails, report `merge_blocked` with the failed gate and the
required human action. If an in-scope PR stops at readiness during a
merge-granted run without a named blocker, report `policy_inconsistent`. PRs
discovered outside the bounded scope are `out_of_scope` and must not enter
delegated merge or batch-merge commands.

### Gate 6 — Completion Gate

At the Step 8b tracker-status transition, mark an item complete for a stage
only after:

1. The stage outcome is confirmed **against live state** — the PR status is
   `MERGED`, or the configured completion condition is met. Never infer
   completion from stale memory, branch names, or prior resolver output.
2. The required audit evidence is recorded.

If audit requirements are not satisfied, apply the `missing_audit_evidence` stop
condition rather than marking the item complete.

---

## 4. Named Stop Conditions

The following stop condition names are recognized by this enforcement. They are
sourced from the `stop_conditions` list in `guardrails.md` plus the two
enforcement-specific conditions added here. Using the exact strings from this
table is required for consistent stop reporting.

| Stop condition name | When it applies |
| --- | --- |
| `unclear_requirements` | A requirement or acceptance criterion is ambiguous and cannot be resolved without a human decision. |
| `architecture_decision` | An architectural choice requires human input before the agent can safely proceed. |
| `failing_ci` | One or more required CI checks are red or in a persistent-failure state. |
| `unresolved_blocking_review` | A blocking review thread from a configured automated reviewer or a human reviewer remains unresolved. |
| `high_risk_change` | The PR is classified above the configured `max_merge_risk` for the stage. |
| `destructive_action` | The next action would delete branches, data, releases, or other non-recoverable artifacts. |
| `human_checkpoint_required` | A declared stage-scoped human checkpoint for the PR's work item is still pending, or the PR still carries `human-checkpoint-required`. |
| `security_sensitive_advisory_pending` | A security-sensitive advisory finding (per the classifier in `scripts/development-workflow/security-advisory-classifier.sh`) lacks a fixed commit or a verified human accept/reject decision at the PR's current head SHA. |
| `graduation_approval_required` | A `develop-<slug>` -> `develop` graduation PR is the next merge candidate but explicit human graduation approval has not been recorded through `/graduate-development <slug>`. |
| `missing_tracker_context` | A required tracker field (status, type, assignee, dependency link) is absent or unresolvable. |
| `missing_required_secret_or_permission` | A required credential, GitHub permission, or access token is absent. |
| `guardrails_config_unreadable` | The `guardrails` block in `.ai-dev-workflow.yaml` is missing required fields, uses invalid values, or is internally contradictory. |
| `missing_audit_evidence` | A delegated decision required an audit record but the record could not be produced or verified. |

**Additive rule**: These stop conditions may **add** to but may **never remove**
the framework's baseline human-stop conditions. The baseline stops
(`unclear_requirements`, `architecture_decision`, `failing_ci`,
`unresolved_blocking_review`, `high_risk_change`, and `destructive_action`) hold
in **all** modes, including `autonomous`. Guardrails may tighten the stop
surface but may never loosen it below the baseline.

---

## 5. Stop-Message Contract

Every stop must include all three of the following in the stop message:

1. **The exact stop condition name** (using the string from the table in section
   4 above) — for example: `STOP: guardrail 'high_risk_change' halted this run`.
2. **The affected work item** — issue number, PR number, branch name, or
   development folder path.
3. **The human action required to unblock** — a concrete, actionable instruction,
   not a generic "resolve the issue".

A stop is a **terminal condition** for the affected item in this run, not a
silent skip. Every stop must appear in the run summary under a "Stops" or
"Blocked" section with its named cause, the affected item, and the unblocking
action.

---

## 6. Unreadable / Contradictory Config Rule

When the `guardrails` block in `.ai-dev-workflow.yaml` is present but cannot be
parsed, uses values outside the accepted set, or contains internal contradictions
(for example, `mode: delegated` combined with per-stage values that would never
allow any agent action), orchestration applies the `guardrails_config_unreadable`
stop condition **before any artifact-mutating action**.

The runner must not assume a permissive value for any field it cannot read or
resolve. The stop message must identify the specific field or contradiction that
caused the stop.

---

## 7. Conservative-Defaults Statement

When no `guardrails` section is present in `.ai-dev-workflow.yaml`, the
effective guardrails resolve to the safe defaults defined in `guardrails.md`:

- **Mode**: `manual` — agents draft and propose, but a human performs every merge.
- **Backlog starts**: confirmation-gated — agents do not start backlog work without
  explicit human confirmation.
- **Per-stage merge**: `may_merge_pr: false` for all stages.
- **Per-stage risk ceiling**: `max_merge_risk: low` for all stages.
- **Audit**: no audit records required (no `pr_disposition_record` or
  `work_item_ledger_record` requirement).

The run summary must explicitly state "no `guardrails` section found — conservative
defaults are in effect" and list each resolved default value. This preserves the
existing conservative behavior for all repositories that take no action on
guardrails.

---

## 8. Audit-Evidence Rules

When `audit.pr_disposition_record` or `audit.work_item_ledger_record` is
`required` in the effective guardrails, the runner records audit evidence using
the existing run-epic audit helpers after any delegated review, fix, merge,
block, or escalation decision:

```bash
# Write or update a PR disposition record
./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <evidence-file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <evidence-file> --pr <pr-number>

# Write or update an item-level ledger record (when a parent/epic exists)
./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <evidence-file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <evidence-file> --epic <issue-number>
```

The stable markers (`<!-- run-epic:pr-disposition -->` and
`<!-- run-epic:epic-ledger -->`) ensure that reruns **update** the existing
record rather than creating duplicates.

**Each audit record must cover**:

- The original command and resolved scope.
- The effective guardrails in force for the decision.
- The risk classification and rationale.
- The reviewer-loop and CI outcome.
- The final decision (merged, fix required, waiting on human, or blocked).
- Any protocol deviations with rationale.

**Redaction requirement**: Secrets, credentials, tokens, and local-only paths
must be redacted before any audit record is written. Audit records are evidence
only — they do not by themselves grant merge authority.

**When a parent/epic does not exist**: the work-item ledger record is not
applicable. Record "not applicable — no parent/epic exists" for that field.
