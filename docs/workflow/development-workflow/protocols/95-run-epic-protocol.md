# Protocol: Run Epic

**Agent role**: Epic Runner (`run-epic`)
**Purpose**: Convert a native GitHub epic or explicit item list into a bounded
execution set, then run an explicitly authorized delegated review and merge
loop with pre-merge risk classification, audit evidence, cleanup, and
rediscovery

The first phase is a **read-only resolver protocol**, not an implementation
protocol. It exists to make scoped multi-item work explicit before an agent
starts specs, plans, branches, PRs, tracker updates, reviewer loops, merges, or
cleanup. Delegation flags are captured during resolution but do not make the
resolver mutating. Later delegated execution phases must stay inside that
resolved scope.

---

## Overview

Use this protocol when a human invokes `/run-epic`, `$run-epic`, or asks to run
an epic / bounded item list as a delegated workflow batch.

The resolver supports exactly one scope source:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh --epic <issue-number>
./scripts/development-workflow/run-epic-scope-resolver.sh --items <issue-number>[,<issue-number>...]
```

Optional flags:

- `--base <branch>`: override base-branch inference.
- `--delegate-review`: allow the runner to make the normal human-review gate
  decision for this invocation.
- `--may-merge`: allow the runner to merge acceptable in-scope PRs through the
  repository merge protocol.
- `--may-start-backlog <true|false>`: control whether in-scope Backlog items
  may be started.
- `--max-risk <low|medium|high>`: maximum risk the runner may merge without
  human input.
- `--json`: emit machine-readable output for an orchestrator handoff.

The resolver is read-only even when delegation flags are supplied. It must not
update tracker status, create branches, open or edit PRs, merge PRs, close
issues, or delete branches.

When a later delegated run reaches a candidate PR merge decision, classify that
PR with:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number> --max-risk <low|medium|high>
```

The risk classifier is also read-only. It must not run reviewer loops, poll CI,
update tracker status, change labels, create comments, merge PRs, close issues,
or delete branches. It is an additional pre-merge gate and does not replace the
reviewer loop, CI loop, unresolved-thread checks, merge-state checks, readiness
labels, or repository merge protocol.

Delegated decision runs also record audit comments with:

```bash
./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <pr-number>
./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <issue-number>
```

Audit comments are evidence records only; they do not grant merge authority.

Before an authorized merge decision, run the delegated gate with the current
candidate PR, resolver policy, reviewer, CI, risk, scope, and audit evidence:

```bash
./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>]
```

The gate is read-only. It explains whether the runner may proceed to merge,
must fix and rerun, must stop for human authority/setup, or is blocked by
missing state. It does not replace `/run-item-work`, reviewer-loop, CI-loop,
risk classification, audit comments, merge, cleanup, or tracker updates.
The gate consumes an assembled evidence file; live PR reads happen in the risk
classifier, audit helper, reviewer loop, CI loop, and normal GitHub checks.

---

## Step 1: Validate Scope Input

Require exactly one of:

- `--epic <issue-number>`
- `--items <issue-number>[,<issue-number>...]`

Issue numbers must be positive integers. Reject empty values, zero, non-numeric
tokens, and mixed `--epic` plus `--items` invocations before any repository or
tracker lookup.

Explicit item lists are exact. Do not expand siblings, parent epics, labels, or
linked issues from an explicit list. Duplicate item numbers may be collapsed.

---

## Step 2: Resolve Epic Children

For `--epic`, read native GitHub sub-issues using GraphQL pagination.

Required behavior:

- Read all pages of `subIssues`.
- Verify the child-side parent relationship when GitHub exposes it.
- If the epic has no native sub-issues, report an empty scope clearly.
- Do not fall back to integration branch labels as an epic membership source.
  Labels remain routing metadata, not membership metadata.

---

## Step 3: Enrich Each Item

For each in-scope item, collect best-effort read-only metadata:

- Issue number, title, and open / closed state.
- Labels, including any `integration-branch:<slug>` label.
- Project Status, Type, and Priority when available.
- Dependency signal from issue body references such as `Depends on #123`.
- Linked open or merged PRs whose branch names match the item number.

If a metadata read fails for one item, keep the item in the result as
`ambiguous` with a short reason instead of silently dropping it.

---

## Step 4: Infer Base Branch

Use this precedence:

1. Supplied `--base <branch>`.
2. One shared `integration-branch:<slug>` label across in-scope items, resolved
   as `develop-<slug>`.
3. No integration label, resolved as `develop`.
4. Conflicting integration labels, resolved as ambiguous unless `--base` is
   supplied.

When conflicting integration labels are ambiguous, every item in the result is
ambiguous. A later mutating workflow must stop until a human supplies `--base`
or narrows the scope.

---

## Step 5: Group Items

Assign each item to one group:

- `eligible`: no known blocker, no ready/open review PR, and not already merged.
- `blocked`: dependency signal points to an open dependency.
- `already_merged`: tracker status, issue state, or merged PR indicates the work
  is already complete.
- `in_review`: tracker status or open PR indicates the item is waiting for review
  or merge.
- `ambiguous`: missing / conflicting data prevents a deterministic next action.
- `out_of_scope`: reserved for consumers that compare resolver output against a
  later bounded handoff.

Do not mutate anything based on these groups. The resolver only describes the
execution set.

---

## Step 6: Handoff

Print:

- Scope source and item count.
- Base branch and inference reason.
- Read-only guarantee.
- Grouped item list with issue number, title, status, type, and issue state.

When `--json` is supplied, emit valid JSON containing the same fields plus the
full item metadata. Downstream orchestrators must treat this JSON as the bounded
scope contract and must not opportunistically mutate items outside it.

The output must also include the invocation policy:

- Delegated review authority.
- Delegated merge authority.
- Backlog-start policy.
- Maximum allowed autonomous merge risk.

---

## Step 7: Classify PR Risk Before Delegated Merge

This step applies only after a later delegated run has advanced an in-scope item
to a candidate PR merge decision. It does not run during the resolver-only
handoff.

Before an autonomous merge decision:

1. Confirm the PR is in the resolved execution set or was created for an
   in-scope item.
2. Confirm the normal readiness evidence is current: reviewer loop, CI loop,
   readiness labels, unresolved-thread audit, and merge state.
3. Run `run-epic-risk-classifier.sh` for the candidate PR with the invocation's
   maximum allowed risk.
4. Continue toward merge only when the classifier reports
   `merge_permitted: true` and the normal repository merge protocol is also
   clean.
5. If the classifier reports `blocked`, fix the deterministic blocker when
   safe, then rerun validation, reviewer loop, CI loop, and risk
   classification.
6. If the classifier reports a risk above `--max-risk`, stop or escalate rather
   than widening authority silently.

Risk levels:

- `low`: docs, tests, narrow workflow text, or isolated helper changes with
  clean readiness evidence and no blockers.
- `medium`: workflow scripts, orchestration behavior, merge or cleanup
  automation, or shared workflow tooling with contained blast radius and clean
  readiness evidence.
- `high`: auth, secrets, GitHub permissions, release automation, branch deletion
  behavior, cross-repo PR credentials, broad shared libraries, or unclear
  behavior changes.
- `blocked`: hard-blocking readiness, setup, credential, tracker/base, merge
  state, force-push, destructive-action, or reviewer/thread conditions.

Medium-risk autonomous merge decisions require a complete "why safe to merge"
explanation covering scope, tests, reviewer outcome, CI outcome, and rollback or
cleanup risk. Missing evidence blocks the merge decision.

---

## Step 8: Delegated Review and Fix Loop

This step applies only when the invocation policy includes `--delegate-review`.
Without delegated review authority, any PR that reaches the normal
`ready-for-human-review` handoff remains waiting for human review.

For each in-scope item:

1. Advance the item with the existing `/run-item-work` or stage protocol. Do not
   duplicate spec, plan, implementation, reviewer-loop, or CI-loop behavior in
   this protocol.
2. When a PR reaches review handoff, inspect the latest reviewer-loop and
   Haystack result yourself.
3. If blocking findings are present, remove `ready-for-human-review` and
   `ready-for-regression`, apply deterministic fixes, push a normal follow-up
   commit, rerun local validation, rerun reviewer-loop, rerun CI-loop, audit
   unresolved threads, and reassess.
4. Do not amend and force-push published PR commits during delegated review or
   merge work.
5. If advisory findings remain, make an explicit fix-or-accept decision. Fix an
   advisory when it materially improves risk, maintainability, security, test
   coverage, or workflow reliability. Accepted advisories require rationale in
   the PR disposition audit.
6. Restore readiness labels only after reviewer-loop, CI-loop, unresolved
   threads, and final readiness checks are clean.

---

## Step 9: Record Audit Trail

After a delegated review, fix, merge, block, or escalation decision, create or
update the audit trail before considering the item complete.

Required behavior:

- Write one PR disposition comment for every PR that reaches the delegated
  review gate.
- Use the stable marker `<!-- run-epic:pr-disposition -->` so reruns update the
  existing comment.
- For native epic runs, update one parent epic ledger comment with marker
  `<!-- run-epic:epic-ledger -->`.
- For explicit item-list runs without a parent epic, report the epic ledger as
  not applicable while still writing PR disposition comments.
- Include reviewed head SHA, reviewer-loop result, blocking/advisory counts,
  advisory decisions and rationales, risk classification and reasons, merge
  authority, final decision, verification evidence, and protocol deviations.
- Redact secrets, credentials, tokens, and local-only paths before rendering or
  applying comments.

Reruns must update existing marker comments instead of creating duplicates.

---

## Step 10: Final Delegated Merge Gate

This step applies only when the invocation policy includes `--may-merge`.
Without delegated merge authority, the runner may prepare the PR for human
review but must not merge it.

Before merge:

1. Confirm the PR belongs to the resolved execution set.
2. Confirm the PR is not draft.
3. Confirm `ready-for-human-review` is present.
4. Confirm `ready-for-regression` is present when the branch prefix is
   `feature/*`, `fix/*`, `hotfix/*`, `refactor/*`, or `backport/hotfix/*`.
   Spec and implementation-plan PRs do not require this label.
5. Confirm CI is green and no required check is pending, failing, unavailable,
   or ambiguous.
6. Confirm merge state is clean.
7. Confirm `needs-setup` is absent.
8. Confirm no unresolved blocking automated-reviewer thread remains.
9. Confirm reviewer disposition is acceptable.
10. Confirm the risk classifier permits merge under the invocation's
    `--max-risk`.
11. Confirm the PR disposition audit comment exists for the reviewed head SHA.
12. Run `run-epic-delegated-gate.sh` against the assembled evidence.

Proceed to the repository merge protocol only when the delegated gate reports
`merge_allowed`. If the gate reports `fix_required`, remove readiness labels,
fix, rerun validation/reviewer/CI, and return to Step 8. If it reports
`human_required`, stop for human authority, setup, or risk tolerance. If it
reports `blocked`, stop until required state is available.

---

## Step 11: Merge, Cleanup, Rediscovery, and Epic Closeout

When all gates permit merge:

1. Merge with the repository-approved merge path for the PR target branch.
2. Verify GitHub reports the PR state as `MERGED`.
3. Delete or prune the merged branch as appropriate.
4. Run post-merge cleanup for the correct base branch.
5. Verify issue state and Project status.
6. Update the epic ledger.
7. Rerun scope resolution so newly unblocked items can advance.

After the final native child item reaches a terminal state, verify live native
sub-issues and Project statuses before closing the parent epic or marking it
complete. Do not close the parent epic from stale memory, branch names, or prior
resolver output alone.

Stop only when all in-scope items are merged, remaining items are blocked by a
real external condition or authority boundary, or the invocation policy forbids
starting the remaining Backlog work.
