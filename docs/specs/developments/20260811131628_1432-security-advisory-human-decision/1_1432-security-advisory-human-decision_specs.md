# Security-Sensitive Advisory Human Decision Requirement - Spec

---

## Overview

Automated reviewers (PR-Agent, CodeRabbit, and similar Step 7/7a platforms)
sometimes raise advisory findings that a clean reviewer-loop result and a
delegated merge policy currently allow to pass through without any human ever
looking at them. That is safe for the great majority of advisory findings,
which are code-correctness or style suggestions unrelated to security. It is
not safe for the small minority of advisory findings that describe an actual
weakening of an authentication check, a credential/secret exposure, an unsafe
or destructive git operation, an injection risk, or a bypass of an existing
workflow guardrail — the class of finding that motivated this issue when
PR-Agent flagged raw `git push --force` semantics and permissive GitHub remote
URL parsing on the branch-push guard implementation in PR #1431.

This feature introduces a **narrow, two-part classification** for advisory
findings ("security-sensitive") and a **distinct** human-decision requirement
that applies whenever a finding is classified that way. The classification is
deliberately narrower than the risk classifier's existing broad `high`-risk
path taxonomy (`auth/`, `secret(s)/`, `credential(s)/`, `permission(s)/`,
`.github/workflows/`, release, and branch-deletion paths): that taxonomy
triggers on file location alone and, applied to advisory content, would fire
constantly and be dismissed as noise — the exact failure mode this feature
exists to prevent. Evidence for that concern comes from this same
implementation batch: three advisory findings were raised on unrelated code
(PR-Agent on PR #1459, CodeRabbit on PR #1460, PR-Agent on PR #1467), and none
were security-relevant, yet a path-only trigger would have fired on all
three. Applied to the same evidence, the definition in this spec matches
zero of the three (see AC2) and matches both PR #1431 findings that
originally motivated this issue (see AC3). Based on that 0-of-3 /
positive-on-known-incident evidence, and on the observation that most
advisory findings in this project's history concern code correctness rather
than security-relevant defect categories, this feature's **expected trigger
rate is a small minority of advisory findings — no more than roughly one in
twenty (5%) in typical batches, with most batches expected to see zero
matches.** This is a stated design target to be validated empirically over
time (see Business Rules), not a hard ceiling enforced in code.

The mechanism introduced here is a **distinct signal**, not a reuse of the
existing `human-checkpoint-required` label or `human_checkpoint_required`
stop condition. Those carry their own pending/satisfied/waived lifecycle tied
to epic/stage checkpoints declared and resolved (including via blanket
waiver) before or during a run. A security-sensitive advisory finding is
discovered later — during the Step 7/7a reviewer loop, after work has already
started — and by design **cannot** be resolved by a blanket action taken
earlier in the run. This batch's own bounded prelude recommended four human
checkpoints and the human waived all four in a single gesture; that gesture
must not be able to resolve a security-sensitive advisory finding, because
the finding did not exist yet when the waiver was recorded and because
collapsing the two mechanisms would let exactly the blanket-approval pattern
this feature exists to guard against satisfy it by accident.

Finally, the requirement applies to **every delegated-merge caller** —
`/run-item`, `/run-items`, and `/run-epic` — not only epic-scoped runs. Gate
5 evidence assembly already runs for all three surfaces, and the issue's own
motivating example (PR #1431) was not an epic. This batch alone invoked the
delegated gate eleven times, none of them epic-scoped; an epic-only version
of this requirement would have covered none of them. Because `pr.inScope` is
now optional on delegated-gate evidence (following the change delivered in
issue #1435) and the gate skips its scope check entirely when the field is
absent, this feature must be wired into the gate's normal reasons cascade —
not the epic-scope short-circuit — so it does not silently no-op on the
common non-epic path.

## Brief Objective List

Derived from issue #1432:

1. Ensure a security-sensitive advisory finding requires an explicit human
   decision even when the general Step 7/7a reviewer-loop result is clean.
2. Prevent the current delegated-merge path from treating a security-sensitive
   advisory finding as resolved without a human ever deciding it.
3. (Derived from the human's alignment decisions) Define "security-sensitive"
   narrowly enough that the requirement does not fire on most advisory
   findings, and state the expected trigger rate with supporting evidence.
4. (Derived from the human's alignment decisions) Use a mechanism distinct
   from the existing checkpoint label/stop-condition/lifecycle, so that a
   blanket checkpoint waiver cannot resolve a security-sensitive advisory
   finding.
5. (Derived from the human's alignment decisions) Apply the requirement to
   every delegated-merge invocation surface (`/run-item`, `/run-items`,
   `/run-epic`), not only epic-scoped runs, and ensure it does not depend on
   `pr.inScope` being present.

---

## Use Cases

### Use Case 1: A security-sensitive advisory finding is discovered during delegated review

**Actor**: Work Item Runner / delegated review agent operating under
delegated review authority (Gate 4).

**Preconditions**: A PR is in the automated reviewer loop; a configured
platform has raised an advisory finding; the finding matches both parts of
the security-sensitive classification test (see Business Rules).

**Steps**:

1. The runner reads the finding's content and the file(s) it targets.
2. The runner classifies the finding against the two-part test: does its
   content describe one of the defined security-relevant defect categories,
   and is it raised against a file within the defined security-enforcement
   surface?
3. Both parts match: the finding is classified security-sensitive.
4. If the finding describes an actionable, verifiable defect, the runner may
   still apply a code fix and cite the resulting commit — fixing is not a
   judgment that the risk is acceptable, so it remains available to the
   runner under delegated authority.
5. If the runner would otherwise classify the finding as "accepted" (leave it
   in place) or "rejected" (false positive), it does not make that call
   itself. It records the finding as pending a human decision and raises the
   distinct signal introduced by this feature.
6. Other, non-security-sensitive advisory findings on the same PR continue to
   follow the existing fix/accept/rationale disposition path unaffected.
7. Gate 4 and Gate 5 do not treat the pending security-sensitive finding as
   resolved; readiness may still be reached, but delegated merge does not
   proceed past it.

**Postconditions**: The finding is either fixed with a cited commit, or left
pending an explicit human decision; the delegated agent never unilaterally
decides that a security-sensitive risk is acceptable or a false positive.

**Information shown**:

- The finding's matched content category and matched file/mechanism.
- The distinct pending signal, visibly different from the general advisory
  disposition record and from checkpoint state.

**Actions available**:

- Fix the underlying defect (available to the runner).
- Wait for a human decision (required to resolve "accept" or "reject").

**Considerations**:

- This is the scenario PR #1431 exposed: the runner correctly could not have
  self-resolved "raw force instead of a lease" or "permissive remote URL
  parsing" as acceptable without a human decision.

### Use Case 2: A human records the decision for a pending security-sensitive advisory finding

**Actor**: Human reviewer/maintainer with sufficient repository permission.

**Preconditions**: A PR carries one or more security-sensitive advisory
findings pending a human decision.

**Steps**:

1. The human reads the finding and the runner's classification rationale.
2. The human decides: accept the risk (with a rationale) or confirm the
   finding is a false positive (reject, with a rationale).
3. The human records that decision through the workflow's recognized
   decision-recording surface, referencing the specific finding, PR number,
   and current head commit.
4. The workflow verifies the decision was authored by a human with adequate
   repository permission and that it is tied to the exact finding, PR, and
   head commit currently under review — not a generic prior approval, an
   unrelated comment, or agent-authored rationale.
5. Once every pending security-sensitive finding on the PR has a verified
   human decision (or a fix), the distinct pending signal is cleared and
   Gate 4/5 proceed evaluating the PR as normal.

**Postconditions**: The PR is unblocked from this requirement only when a
verified human decision (or fix) exists for every security-sensitive
finding raised against its current head commit.

**Information shown**:

- Decider identity, timestamp, disposition (accepted/rejected), and rationale
  for each resolved finding.
- Any security-sensitive finding still pending a decision.

**Actions available**:

- Accept the risk with rationale.
- Reject the finding as a false positive with rationale.
- Request the runner fix it instead.

**Considerations**:

- Any later push to the PR — whether or not it touches the code the finding
  was about — invalidates the decision (see BR7); a decision recorded against
  a superseded head commit must not be silently reused across commits.

### Use Case 3: A blanket checkpoint waiver does not resolve a pending security-sensitive advisory finding

**Actor**: Human operator waiving multiple pending bounded-prelude
checkpoints in a single action, and the Work Item Runner processing PRs
later in the same run.

**Preconditions**: The human has waived several pending checkpoints (for
example, four checkpoints across four different items) at the bounded
prelude. Separately, during the run, a PR's own reviewer loop later surfaces
a security-sensitive advisory finding.

**Steps**:

1. The blanket waiver is recorded against the named checkpoints only.
2. Later, the reviewer loop for a different PR (or the same PR, at a later
   stage) raises a security-sensitive advisory finding.
3. Gate 4/5 evaluate that finding using the distinct signal introduced by
   this feature, independent of the earlier checkpoint waiver.
4. The earlier waiver does not satisfy, waive, or otherwise touch the new
   finding's pending state — they are unrelated mechanisms with unrelated
   lifecycles.
5. The PR remains blocked from delegated merge until its own finding-specific
   human decision (or fix) is recorded.

**Postconditions**: No batch-level or earlier-in-run human action can resolve
a security-sensitive advisory finding by coincidence or convenience; only a
decision specific to that finding can.

**Considerations**:

- This is the exact scenario the human's alignment decision cites: this
  batch's prelude recommended and the human waived four checkpoints in one
  gesture. A security-sensitive advisory finding discovered afterward, during
  a PR's own reviewer loop, must not be treated as covered by that gesture.

### Use Case 4: The requirement applies the same way across `/run-item`, `/run-items`, and `/run-epic`

**Actor**: Any Work Item Runner or Portfolio Orchestrator assembling Gate
4/5 evidence for a candidate PR, regardless of invocation surface.

**Preconditions**: A candidate PR carries one or more security-sensitive
advisory findings. The run may or may not have a resolved `/run-epic` scope
for this PR (`pr.inScope` present-true, present-false, or absent).

**Steps**:

1. Evidence assembly for the candidate PR includes the security-sensitive
   advisory data the same way regardless of whether the caller is
   `/run-item`, `/run-items`, or `/run-epic`.
2. When `pr.inScope` is absent (the common shape for non-epic runs) or
   explicitly `true`, the security-sensitive advisory check runs as part of
   the gate's normal evaluation — it is not skipped for lack of an epic
   scope.
3. When `pr.inScope` is explicitly `false` (the PR is confirmed outside a
   resolved `/run-epic` scope), the gate's existing not-applicable
   short-circuit applies as it already does for every other reason, and no
   action is required from this gate for that PR in that run.
4. The runner reports the same distinct signal and the same blocking
   behavior on delegated merge no matter which surface dispatched the run.

**Postconditions**: Coverage of this requirement is not limited to epic-scoped
work; a PR opened and merged through `/run-item` or `/run-items` gets the same
protection as one merged through `/run-epic`.

**Considerations**:

- Eleven delegated-gate invocations occurred in this batch, none of them
  epic-scoped. An epic-only version of this requirement would have covered
  zero of them.

---

## Business Rules

- **BR1 (classification is two-part and conjunctive)**: An advisory finding
  is classified security-sensitive only when **both** of the following are
  true:
  1. Its content describes one of these defect categories: (a) an
     authentication or authorization check that can be bypassed, skipped, or
     spoofed; (b) exposure, logging, or insecure handling of a secret,
     credential, or token; (c) an unsafe or destructive git/version-control
     operation, such as a force operation without a safety lease, a
     non-atomic destructive branch operation, or a history rewrite; (d) an
     injection risk, such as unsanitized input reaching a shell, `eval`, or
     similar execution context, or a path-traversal risk; or (e) a bypass or
     weakening of an existing workflow guardrail, gate, or policy-enforcement
     mechanism (merge gate, push guard, artifact guard, or delegated
     authorization check).
  2. It is raised against a file within the workflow's security-enforcement
     surface: the workflow's own guardrail/gate scripts that enforce branch,
     push, merge, or authorization policy; the workflow's reviewer-access
     authorization/bypass-audit logic; or a `.github/workflows/*.yml` file's
     permissions or secrets configuration.
  A finding matching only one part (content category without being on the
  enforcement surface, or vice versa) is **not** security-sensitive and
  follows the existing general advisory fix/accept/rationale path unchanged.
- **BR2 (narrower than the risk classifier)**: This classification is
  independent of, and deliberately narrower than, the risk classifier's
  existing `high`-risk path taxonomy. This feature does not add categories to
  that taxonomy, and the risk classifier's use for `max_merge_risk` ceilings
  is unchanged.
- **BR3 (expected trigger rate is a stated, evidence-backed target)**: The
  classification is expected to match no more than roughly one in twenty
  (5%) of advisory findings in typical operation, based on the 0-of-3 result
  against this batch's non-security advisory findings (AC2) and the
  positive match against the PR #1431 findings that motivated this issue
  (AC3). This target should be revisited if observed trigger rates diverge
  meaningfully from it.
- **BR4 (distinct mechanism)**: The signal, label, and stop condition
  introduced for this requirement are named distinctly from
  `human-checkpoint-required` / `human_checkpoint_required` and do not read,
  write, or otherwise participate in the checkpoint pending/satisfied/waived
  lifecycle. Satisfying, waiving, or batch-waiving any checkpoint has no
  effect on a pending security-sensitive advisory finding, and vice versa.
- **BR5 (delegated authority carve-out)**: Regardless of `mode: delegated`,
  a stage's `may_merge_pr: true`, or any granted delegated review authority,
  the runner may not itself record an "accepted" or "rejected" disposition
  for a security-sensitive advisory finding. The runner may still apply a
  verifiable code fix and cite the resulting commit; fixing the underlying
  defect is a code change, not a judgment that a security risk is
  acceptable or a false positive.
- **BR6 (human decision must be verifiable and specific)**: A recorded human
  decision resolves a pending security-sensitive advisory finding only when
  the workflow can verify that it was authored by a human with sufficient
  repository permission, and that it is tied to the specific finding, PR
  number, and current head commit. A generic prior PR approval, an unrelated
  comment, or agent-authored rationale does not satisfy this rule.
- **BR7 (decisions do not carry across any later push)**: A human decision
  recorded for a security-sensitive advisory finding is valid only for the
  exact PR head commit it was recorded against, matching BR6's "current head
  commit" requirement precisely. Any later push to the PR — whether or not
  it touches the code the finding was about — invalidates the decision. If
  the finding still applies at the new head commit, it returns to pending
  and requires a fresh fix or a fresh human decision recorded against the
  new head commit; a decision recorded against a superseded head commit must
  not be silently treated as still resolving the finding. This mirrors the
  exact-head-SHA invalidation rule the workflow already uses for verified
  reviewer-access-bypass authorization, so the same push invalidates both
  consistently rather than requiring two different staleness definitions.
- **BR8 (applies to every delegated-merge caller)**: The requirement is
  evaluated the same way for `/run-item`, `/run-items`, and `/run-epic` Gate
  4/5 evidence. It is part of the gate's normal reasons evaluation, not
  conditioned on a resolved `/run-epic` scope.
- **BR9 (does not silently no-op when `pr.inScope` is absent)**: When
  `pr.inScope` is absent from Gate 4/5 evidence (the common shape for
  non-epic runs) or explicitly `true`, the security-sensitive advisory check
  runs as part of the gate's normal evaluation. It is skipped only when
  `pr.inScope` is explicitly `false`, matching the gate's existing
  not-applicable short-circuit for out-of-scope candidate PRs.
- **BR10 (does not weaken existing gates)**: This requirement adds a new
  blocking condition; it does not relax, replace, or substitute for any
  existing reviewer-loop, CI, thread-resolution, risk, or checkpoint
  requirement.

---

## Statuses / Enum Values

| Code value       | Display label                | Description                                                                                     |
| ----------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| `pending`         | Pending Human Decision        | Finding classified security-sensitive; not yet fixed or human-decided.                           |
| `fixed`           | Fixed                         | Runner (or human) applied a verifiable code fix; cited commit SHA recorded.                      |
| `human-accepted`  | Accepted by Human              | A verified human decision accepted the risk with a recorded rationale.                           |
| `human-rejected`  | Rejected by Human (False Positive) | A verified human decision confirmed the finding does not apply, with a recorded rationale.  |

These four values are the only persisted dispositions Gate 4/5 evaluate for a
security-sensitive advisory finding. "Superseded by new commit" (see below)
is not a fifth persisted status — it is the audit reason recorded at the
moment a `fixed` / `human-accepted` / `human-rejected` disposition is
invalidated; the finding's persisted value at that point is `pending`, and
that is the value Gate 4/5 read.

**Valid transitions**:

- `pending` → `fixed` when a verifiable code fix is applied and cited (runner
  or human), recorded against the current head commit.
- `pending` → `human-accepted` when a verified human decision accepts the
  risk with rationale, recorded against the current head commit.
- `pending` → `human-rejected` when a verified human decision confirms a
  false positive with rationale, recorded against the current head commit.
- `fixed` / `human-accepted` / `human-rejected` → `pending`, immediately and
  automatically, on any later push to the PR (per BR7). The workflow records
  an audit reason ("superseded by new commit") for the invalidation, but the
  finding's evaluated status becomes `pending` — not a separate `stale`
  status — re-entering the decision requirement for the new head commit.

---

## Operational Visibility

- **Distinct summary section**: The reviewer-loop / Gate 4-5 summary lists
  each security-sensitive advisory finding, its matched content category, its
  matched file/mechanism, and its current disposition state, kept visibly
  separate from the existing (non-security) "Advisory dispositions"
  subsection.
- **Distinct label/stop-condition naming**: The label and stop condition
  introduced for this requirement are never displayed, logged, or referenced
  using the existing `human-checkpoint-required` label text or
  `human_checkpoint_required` stop-condition text.
- **Human decision record**: A resolved finding's decider identity,
  timestamp, disposition, and rationale are visible on the PR itself (via the
  decision-recording comment/review) and are referenced in the Gate 5 audit
  evidence.
- **Coverage across surfaces**: Run summaries for `/run-item`, `/run-items`,
  and `/run-epic` all report this requirement's evaluation the same way for
  any candidate PR they assemble Gate 4/5 evidence for.

---

## Workflow Decision-Gate Matrix

| Gate inputs | Allowed outcome | Required next action | Operator-visible evidence | Mirror surfaces |
| --- | --- | --- | --- | --- |
| Advisory finding matches both the content-category test and the security-enforcement-surface test | Classified security-sensitive | Runner may fix with a cited commit; may not itself record accept/reject | Matched category, matched file/mechanism | Step 7/7a reviewer-loop summary; Gate 4/5 evidence |
| Advisory finding matches only one of the two tests, or neither | Not classified security-sensitive | Existing general advisory fix/accept/rationale path applies unchanged | Existing advisory disposition record | Existing "Advisory dispositions" summary subsection |
| Security-sensitive finding disposition = fixed, with a cited commit | Finding resolved | Gate 4/5 continue evaluating the PR normally | Cited commit SHA | Reviewer-loop / Gate 5 summary |
| Security-sensitive finding pending, no verified human decision | Finding remains pending | Gate 4 leaves the accept/reject decision to a human; Gate 5 blocks delegated merge regardless of mode, `may_merge_pr`, or unrelated checkpoint state | Distinct pending signal; matched category/mechanism | Gate 4/5 reasons; PR-visible label |
| Security-sensitive finding has a verified human decision matched to the current PR, head commit, and finding | Finding resolved (accepted or rejected) | Gate 4/5 proceed treating it as resolved | Decider identity, timestamp, disposition, rationale, matched PR/head SHA/finding | PR comment/review referenced by Gate 5 evidence |
| Any new push occurs on a PR carrying a previously resolved (`fixed`/`human-accepted`/`human-rejected`) security-sensitive finding | Prior disposition is invalidated | Finding's evaluated status returns to `pending`; requires a fresh fix or fresh human decision recorded against the new head commit | "Superseded by new commit" audit reason; persisted/evaluated value is `pending`, not a separate stale status | Gate 4/5 reasons |
| An unrelated bounded-prelude checkpoint (or a blanket waiver of several) is satisfied or waived | No effect on any pending security-sensitive advisory finding | Continue requiring the finding's own decision | Distinctness from checkpoint lifecycle | Gate 4/5 reasons vs. checkpoint reasons |
| Gate 4/5 evidence assembled by `/run-item`, `/run-items`, or `/run-epic`, with `pr.inScope` absent or `true` | Security-sensitive advisory check runs as part of normal evaluation | Same reasons cascade regardless of invocation surface | Same evidence fields across surfaces | Gate 4/5 for all three invocation surfaces |
| Gate 4/5 evidence assembled with `pr.inScope` explicitly `false` | Existing not-applicable scope short-circuit applies | No action required from this gate for this PR in this run | Existing `not_applicable` decision | Existing scope short-circuit behavior |

---

## Acceptance Criteria

- [ ] **AC1**: An advisory finding is classified security-sensitive only when
      it matches both the content-category test and the
      security-enforcement-surface test defined in BR1; a match on only one
      part does not classify it as security-sensitive.
- [ ] **AC2**: The three non-security advisory findings from this batch
      (PR-Agent's jq iteration claim on PR #1459, CodeRabbit's JSON key-type
      claim on PR #1460, and PR-Agent's quote-escaping claim on PR #1467) do
      not classify as security-sensitive under this definition.
- [ ] **AC3**: Findings of the same shape as the PR #1431 findings that
      motivated this issue (unsafe git force semantics without a lease;
      permissive remote URL parsing in a workflow branch-push guard) classify
      as security-sensitive.
- [ ] **AC4**: A security-sensitive advisory finding blocks the delegated
      agent from self-recording an "accepted" or "rejected" disposition; a
      verifiable code fix with a cited commit remains available to the
      agent.
- [ ] **AC5**: A security-sensitive advisory finding without a fix or a
      verified human decision blocks delegated merge (Gate 5), regardless of
      `mode: delegated`, `stages.<stage>.may_merge_pr: true`, or the
      satisfaction/waiver state of unrelated checkpoints.
- [ ] **AC6**: A blanket waiver of multiple pending bounded-prelude
      checkpoints (recorded before or independent of the finding) does not
      satisfy, waive, or otherwise resolve a pending security-sensitive
      advisory finding.
- [ ] **AC7**: The label and stop condition introduced for this requirement
      are distinct in name from `human-checkpoint-required` and
      `human_checkpoint_required`, and this requirement does not read, write,
      or alter the existing checkpoint pending/satisfied/waived lifecycle.
- [ ] **AC8**: Gate 4/5 evaluate the security-sensitive advisory requirement
      identically for evidence assembled by `/run-item`, `/run-items`, and
      `/run-epic`.
- [ ] **AC9**: When `pr.inScope` is absent from Gate 4/5 evidence, the
      security-sensitive advisory check still runs; it is skipped only when
      `pr.inScope` is explicitly `false`, matching the gate's existing
      not-applicable scope short-circuit.
- [ ] **AC10**: For each security-sensitive advisory finding, the workflow
      records the matched content category, the matched file/mechanism, and
      either a cited fix commit or a verified human decision (decider
      identity, timestamp, disposition, rationale) before treating it as
      resolved.
- [ ] **AC11**: A human decision recorded for a security-sensitive finding is
      accepted only when verifiably tied to the specific finding, PR number,
      and current head commit; a generic prior approval, an unrelated
      comment, or agent-authored rationale does not satisfy this
      requirement.
- [ ] **AC12**: If any later push occurs on a PR carrying a previously
      fixed/human-accepted/human-rejected security-sensitive finding —
      whether or not that push touches the code the finding was about — the
      finding's evaluated status returns to `pending` (recorded with a
      "superseded by new commit" audit reason) and requires a fresh fix or a
      fresh human decision recorded against the new head commit; a decision
      recorded against a superseded head commit does not resolve the finding
      at the new head commit.
- [ ] **AC13**: The reviewer-loop / Gate 5 summary surfaces each
      security-sensitive advisory finding and its current disposition state
      in a section visibly distinct from the existing non-security advisory
      dispositions.

---

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Security-sensitive advisory findings require an explicit human decision even when the reviewer loop is otherwise clean | Use Cases 1-2, BR1, BR5, BR6 | AC1, AC4, AC10, AC11 |
| 2. The delegated-merge path does not treat a security-sensitive finding as resolved without a human decision | Use Cases 1-2, BR5, BR7 | AC4, AC5, AC12 |
| 3. Narrow, evidence-backed definition with a stated expected trigger rate | Overview, BR1-BR3 | AC1, AC2, AC3 |
| 4. Distinct mechanism, not reused checkpoint label/stop-condition/lifecycle | Use Case 3, BR4 | AC6, AC7 |
| 5. Applies to every delegated-merge invocation surface, independent of `pr.inScope` | Use Case 4, BR8, BR9 | AC8, AC9 |

---

## Out of Scope (MVP)

- Modifying `run-epic-risk-classifier.sh`'s existing `high`-risk path
  taxonomy or its role in `max_merge_risk` ceiling checks; this feature is an
  independent classification of advisory content, not a change to path-based
  risk scoring.
- Changing the existing general (non-security) advisory fix/accept/rationale
  disposition workflow for findings that do not classify as
  security-sensitive.
- Retroactively re-evaluating advisory findings on PRs merged before this
  feature ships.
- Classifying a finding as security-sensitive from broad keyword matching on
  words like "security" appearing anywhere in a finding's text; classification
  requires both parts of the BR1 test to hold, mirroring the structured
  (not free-text) signal approach already established for checkpoint
  classification in issue #1287.
- Extending this requirement to advisory-producing tools not currently
  configured as Step 7/7a reviewer platforms.
- The exact label string, stop-condition token, decision-recording comment
  format, and verification implementation (deferred to the implementation
  plan; see PR-Visible Deferral Notes).

## PR-Visible Deferral Notes

- **Exact label/stop-condition token names**: Deferred to the implementation
  plan. Human confirmation is not requested beyond BR4/AC7's requirement that
  the chosen names be distinct from `human-checkpoint-required` /
  `human_checkpoint_required`.
- **Human-decision verification mechanism**: Deferred to the implementation
  plan. The spec requires (BR6) that the workflow verify author identity,
  permission, and an exact match to the specific finding/PR/head commit; the
  concrete comment format and GitHub API verification approach are
  implementation decisions, reasonably built on the existing verified
  authorization-event pattern already used for reviewer-access bypass
  authorization. Human confirmation is not requested; this is a technical
  design choice.
