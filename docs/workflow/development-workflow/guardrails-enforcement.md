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

<!-- workflow-shell-contract: bash-zsh -->
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
missing` reason) whenever `.policy` is missing or not an object, or
`.statusChecks` is missing, `null`, or not an array — precisely because that
absence/malformation is otherwise indistinguishable from a real denial or a
real "no CI has run" state. The `.statusChecks` check is skipped when
`ciPolicy`/`ci_policy` resolves to `none` (no CI configured for this
repository/product), since CI-disabled evidence is never expected to carry
`.statusChecks` at all. Treat that reason as an instruction to fix the
evidence file's shape, not as a policy or CI verdict.

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
| `missing_required_secret_or_permission` | A required credential, GitHub permission, or access token is absent. Also reused, per `integrations/cursor-dispatch-profiles.md`, when a run declared `cursor-parent-orchestrated` delegates an action to a reachable stage role that receives the delegation but reports the action refused because a credential, GitHub permission, or access token it needs is absent (not an inability to reach the role at all, and not a harness tool or local file-path permission denial — see the Cursor dispatch-profile stop conditions subsection below). |
| `dispatch_profile_declaration_missing` | A bounded Cursor run (`/run-item`, `/run-items`, `/run-epic`, or `/run-work`) reaches a mutating action, or a read-only checkpoint, without a valid dispatch-profile declaration on record — see the Cursor dispatch-profile stop conditions subsection below for the full set of causes and the unblocking action. |
| `dispatch_handoff_unavailable` | A bounded Cursor run has no handoff of any kind available (or cannot confirm initial handoff availability) for the next mutating action, or a run declared `cursor-parent-orchestrated` or `cursor-native-handoff` discovers mid-run that stage or orchestration handoff has become unavailable — see the Cursor dispatch-profile stop conditions subsection below for the full set of causes and the unblocking action. |
| `push_verification_failed` | A branch push could not be verified. Either the branch's upstream would send a bare `git push` somewhere other than its own remote branch on `origin`, or the commit the protocol pushed is not present on the remote afterwards. Silence is not success: a refused push prints a multi-line message that shell-output filtering can truncate to nothing. |
| `guardrails_config_unreadable` | The `guardrails` block in `.ai-dev-workflow.yaml` is missing required fields, uses invalid values, or is internally contradictory. |
| `missing_audit_evidence` | A delegated decision required an audit record but the record could not be produced or verified. |
| `evidence_schema_mismatch` | `run-epic-delegated-gate.sh` evidence is missing a required object (`.policy`), or `.statusChecks` is missing, `null`, or not an array — which cannot be distinguished from a genuine authority denial or a genuine "no CI has run" state (unless `ciPolicy`/`ci_policy` is `none`, where `.statusChecks` is not required at all); fix the evidence file's shape before treating the result as a real denial or CI verdict. |
| `reviewer_preflight_blocked` | The reviewer preflight (`reviewer-preflight.sh`, Protocol 91 § Reviewer preflight before child dispatch) found the shared reviewer configuration, the machine-local override, and a reviewer platform's own configuration disagree for a lifecycle stage still ahead of this item (`OUTCOME=blocked`). |
| `reviewer_preflight_prerequisite_failed` | The reviewer preflight's own run inputs — target base, remaining-stage set, or per-stage pull-request state — are unresolved or malformed (`OUTCOME=prerequisite-failed`); a run-input failure, not a reviewer-configuration verdict. |
| `reviewer_preflight_tooling_failed` | The reviewer preflight script itself failed before reaching any `OUTCOME` (exit `3`) — a helper crash, a git/gh operation that failed or could not complete within its bounded time budget, or a missing dependency. Distinct from `reviewer_preflight_prerequisite_failed`, which is reserved for `OUTCOME=prerequisite-failed`'s run-input failures; conflating the two misclassifies a tooling outage as bad item input in stop-condition consumers and audit summaries. |

**Additive rule**: These stop conditions may **add** to but may **never remove**
the framework's baseline human-stop conditions. The baseline stops
(`unclear_requirements`, `architecture_decision`, `failing_ci`,
`unresolved_blocking_review`, `high_risk_change`, and `destructive_action`) hold
in **all** modes, including `autonomous`. Guardrails may tighten the stop
surface but may never loosen it below the baseline. This section adds
`dispatch_profile_declaration_missing` and `dispatch_handoff_unavailable` under
this additive rule, and reuses `missing_required_secret_or_permission`
(already defined above) for one additional cause rather than inventing a
third new string. It also adds `reviewer_preflight_blocked`,
`reviewer_preflight_prerequisite_failed`, and `reviewer_preflight_tooling_failed`
under this additive rule for the reviewer preflight gate (issue #1561).

### Cursor dispatch-profile stop conditions

This subsection applies **only in a Cursor environment**; **other runners are
unchanged** by it — see `integrations/cursor-dispatch-profiles.md`, the
canonical, normative source for the profile declaration gate these stops
enforce. This subsection states the affected work item and the human
unblocking action for each cause the stop can fire for, covering every
cause, not only the most common one.

**`dispatch_profile_declaration_missing`** — fires when: the declaration is
missing at the first mutating action; the declared profile value is
**invalid profile** (outside the three defined profiles); the declaration
names no accountable orchestrator role (**invalid accountable role**,
including an empty value); the declared posture does not match the run's
checkpoint (**invalid posture** — `observing` at a mutating action, or
`absorbed`/`handed off intact` at a read-only checkpoint); or the declared
profile does not match the profile outcome the decision gate already assigns
to the run's known handoff facts, in either direction (a **coarse-fact
mismatch**, whether **more permissive** or **less permissive** than the
assigned outcome). This coarse-facts check does not apply to a re-declaration
produced by a mid-run recovery row (native-handoff mid-run failure, or
parent-orchestrated stage-handoff-unavailable); those remain valid
re-declarations.

- **Affected work item**: the branch, pull request, or development-folder
  path the bounded run was invoked against; for a read-only portfolio scan,
  the scan invocation itself. For a pre-branch, explicit-list `/run-items`
  invocation, before any item-scoped artifact exists, the affected work item
  is the single string `explicit_list_invocation_targets=<t1>,<t2>,...`, one
  `<ti>` per target of the router's normalized target list, rendered
  **verbatim** (no rewriting of `#`, case, `/`, or a leading `./`) and
  **percent-encoded** only for the defensive whitespace/control/`%` cases
  documented in `integrations/cursor-dispatch-profiles.md`. Report this once
  for the whole invocation, never once per target.
- **Human unblocking action**: the stopped run is **not resumed or corrected
  in place** — it stops with no profile in force and does not accept an
  in-run correction. Invoke the command again as a **fresh invocation**,
  supplying: a **valid profile** (one of `cursor-native-handoff`,
  `cursor-parent-orchestrated`, or `cursor-inline-fallback`); a **named
  accountable role**; a **posture valid for the checkpoint** (absorbed or
  handed off intact for a mutating action, observing for a read-only
  checkpoint); and, when the prior run's declaration was rejected for a
  coarse-fact mismatch, the **profile the known facts assign**.

**`dispatch_handoff_unavailable`** — fires when: no handoff of any kind is
available (or initial handoff availability itself cannot be confirmed) and
the command would mutate; a run declared `cursor-parent-orchestrated` whose
stage handoff for a specific action proves unavailable mid-run (the stage
role cannot be reached at all); or a run declared `cursor-native-handoff`
whose orchestration-role handoff fails mid-run while the invoking context's
own initial handoff capability is also lost or cannot be confirmed.

- **Affected work item**: the branch, pull request, or development-folder
  path the mutating action would have applied to (or the
  `explicit_list_invocation_targets=<t1>,<t2>,...` form for a pre-branch
  explicit-list stop, per the affected-item rule above).
- **Human unblocking action**: move the run to an **environment where
  initial handoff is confirmed available** (native-handoff or
  parent-orchestrated capable) and re-run, or **explicitly accept the
  read-only result** reported for this invocation. **Exception for the
  parent-orchestrated stage-handoff-unavailable cause**: initial handoff was
  already confirmed available, and it is one **specific stage role** (the
  role the affected action needed — spec, plan, implementation, or review)
  that became unreachable; moving to a merely parent-orchestrated-capable
  environment does not by itself restore that role's reachability. Confirm
  the specific stage role the affected action needed is **reachable** in the
  target environment before re-running, or explicitly accept the read-only
  result.

**`missing_required_secret_or_permission` (reused, Cursor dispatch-profile
cause)** — fires when a run declared `cursor-parent-orchestrated` delegates a
specific action to the stage role that owns it, and that stage role is
reachable and receives the delegation but reports that this specific action
was refused because a credential, GitHub permission, or access token it
needs is absent — not an inability to reach the role at all, and not a
harness tool or local file-path permission denial (Out of Scope; tracked
separately as issue #1746).

- **Affected work item**: the branch, pull request, or development-folder
  path the denied action would have applied to, and the denied target named
  by the stage role's report.
- **Human unblocking action**: **grant** the stage role the specific
  credential, GitHub permission, or access token its report identified as
  denied, then **re-run the same delegated action**. If the identified
  permission is a structural restriction that will not be granted, the human
  instead either reassigns the action to a different context that can act as
  the **same stage role** the action already belongs to — never to a
  different stage role — or explicitly accepts that this action **does not
  proceed** under the current run and records that decision; the absorbing
  context **never performs** the action inline in either case, and the
  action's owning stage role is unchanged by the reassignment. This
  reassignment path does not extend to a harness or local file-path
  permission denial, which stays Out of Scope under issue #1746 with no
  recovery path of any kind. The run remains declared parent-orchestrated
  throughout; unlike `dispatch_handoff_unavailable`, no re-declaration or
  environment change is required, because the stage role's onward-handoff
  capability for other actions was never in question.

**No named stop condition for a harness or local file-path denial.** A
reachable stage role's harness tool (`Edit`, `Write`, or `Bash`) or local
file-path permission denial on a specific delegated action, dispatched as a
subagent under Protocol 90/91's batch dispatch mechanism, **is not a named
stop condition** at all: `missing_required_secret_or_permission` does not
apply because no credential, GitHub permission, or access token is missing,
and `dispatch_handoff_unavailable` does not apply because the stage role was
reached. This failure is only **observably similar** to the
`SUBAGENT_PERMISSION_DENIAL` contract `91-orchestrate-work-protocol.md`
defines, which governs solely a Work Item Runner subagent reporting that
denial to the Portfolio Orchestrator; no corresponding contract exists today
for a stage role dispatched by an item-orchestrator. This case is declared
**Out of Scope** and tracked separately as **#1746**; the absorbing context
never performs the action inline for it.

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

### `architecture_decision` escalation content

When a stop's named cause is `architecture_decision`, the stop message's third
element (the human action required to unblock) is additionally shaped by the
axis-separated coverage analysis defined in the canonical page
[`architecture-decision-escalation.md`](architecture-decision-escalation.md).
The three baseline stop elements above are **unchanged and still required** —
this shapes element 3 only, and is never a replacement for any of the three:

- For a **complete** escalation report (no citation whose conformance or
  substance could not be determined), the required human action names the
  **genuinely open axes only** — never settled axes.
- For an **incomplete** report under the canonical page's malformed-input
  rows, the required human action instead supplies what that rule names: the
  missing question or its source, a redone decomposition, the missing
  conformance evidence, or confirmation of a citation's substance.
- A **substance-confirmation** request is stated **only where a reviewer or a
  human has actually raised** the citation's substance in question and the
  runner genuinely cannot resolve it — internal runner uncertainty alone,
  absent an actually raised question, does not trigger this request (the
  canonical page's raised-question gate).
- Where a malformed-input request is combined with genuinely open axes in the
  same report, the required human action names both, and the report is
  incomplete regardless of how many axes it also settles or leaves open.

See the canonical page for the full vocabulary, mandatory report outline, and
worked example; this section states the stop-message shaping rule only.

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

---

## 7. Known Heuristic Limits

Two of the signals used above are keyword- or path-driven. Both have a failure
mode worth recognising rather than rediscovering.

### CI workflow risk is judged by filename

`run-epic-risk-classifier.sh` is handed a list of changed paths and never the
file contents, so it cannot inspect what a workflow actually does. It therefore
scores `.github/workflows/**` by filename.

This table is the authoritative rule; it is matched against the **basename**,
and the deny-list is checked first.

| Order | Rule | Patterns | Risk |
| ----- | ---- | -------- | ---- |
| 1 | Deny-list (checked first, wins over any allowlist match) | basename containing `deploy`, `release`, `publish`, `tag`, `secret`, `credential`, `permission`, `policy`, or `token` | `high` |
| 2 | Test workflows | `test-*.yml`, `test-*.yaml`, `*-test.yml`, `*-test.yaml`, `*-tests.yml`, `*-tests.yaml` | `medium` |
| 3 | Lint workflows | `*lint*.yml`, `*lint*.yaml`, `shellcheck.yml`, `shellcheck.yaml` | `medium` |
| 4 | Anything else under `.github/workflows/**` | — | `high` |

So `workflow-tests.yml` and `markdown-lint.yml` are `medium`, while
`deploy.yml`, `auto-tag-release.yml`, `pr-policy.yml`, and `e2e-regression.yml`
are `high`. A name matching both lists (`test-release.yml`) is `high`: rule 1
wins.

This is deliberately an allowlist that yields to that deny-list: an
unrecognised workflow stays `high`. Before issue #1565 every workflow change
scored `high`, which meant a PR that wired a test suite into CI exceeded a
`medium` ceiling and could not merge under delegated policy — the risk model
penalised closing a test-coverage gap.

**Consequence for authors**: name a new test or lint workflow conventionally,
or expect it to be classified `high` and to need explicit human merge
authorization. That is the intended trade — misjudging a deployment workflow as
a test job is far worse than making someone rename a file.

### A bug report about a heuristic will trip that heuristic

A bug report has to name its trigger in order to explain it, so any
keyword-driven gate in this framework mishandles its own bug reports. Observed
twice on one run:

- The policy recommender flagged the issue reporting that its keyword test
  over-matches, because the body quotes the keyword list.
- The overlap classifier serialized the issue reporting that it over-serializes,
  because the brief necessarily contains the triggering vocabulary.

This is a property of keyword matching, not a defect in those specific lists,
and it bites exactly when correct handling matters most. **Operators should
expect it** and treat a heuristic's verdict on an item filed *against* that
heuristic as uninformative — re-read the item and decide directly rather than
deferring to the signal. Do not "fix" it by broadening the keyword list, which
makes over-matching worse everywhere else.
