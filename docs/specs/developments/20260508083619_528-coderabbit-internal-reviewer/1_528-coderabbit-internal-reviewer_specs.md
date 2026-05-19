# CodeRabbit as Internal Reviewer (Step 7a) — Spec

**Depends on**: <!-- none -->

---

## Overview

The workflow currently supports CodeRabbit only as an external PR review platform (Step 7, post-draft, triggered by push). This feature adds `coderabbit` as a supported value in `review.internal_reviewers` (Step 7a), enabling CodeRabbit to run before a draft PR is converted to non-draft — the same gate that currently runs `claude` and `codex`.

The goal is to let teams use CodeRabbit as an early-draft reviewer alongside or instead of the existing internal reviewers, with consistent availability-check semantics, a clear interaction model with the existing Step 7 external reviewer loop, and documented backward compatibility for repos that already use CodeRabbit only in Step 7.

---

## Use Cases

### Use Case 1: CodeRabbit Runs as Internal Reviewer and Approves

**Actor**: Work Item Runner (orchestrator agent or human-delegated CI run)
**Preconditions**:

- `.ai-dev-workflow.yaml` includes `coderabbit` in `review.internal_reviewers` (e.g., `[claude, coderabbit]`).
- A draft PR is open on a spec, plan, or implementation branch.
- The CodeRabbit GitHub App is installed on the repository and auto-review is enabled.
- The runner context can reach the CodeRabbit GitHub App (i.e., can push to the branch and observe PR comments via `gh`).

**Steps**:

1. The Work Item Runner enters Step 7a for the draft PR.
2. The runner reads the `review.internal_reviewers` list and performs a runtime-availability check for `coderabbit`.
3. `coderabbit` passes the availability check (see Business Rules BR-2).
4. The runner invokes CodeRabbit on the draft PR using the same auto-review mechanism as Step 7, which fires automatically on push (no trigger comment required). The runner confirms that `auto_review.enabled` is `true` in `.coderabbit.yaml` and that CodeRabbit will respond to the draft PR (see BR-5). If a manual trigger comment is needed (e.g., `@coderabbitai review`), that is an implementation detail for the plan stage.
5. The runner polls for CodeRabbit's response on the draft PR — either an inline review comment or a PR review posted by `coderabbitai[bot]`.
6. The runner parses the response using the same severity classification as Step 7: `Critical` and `Major` findings are blocking; `Minor` and below are suggestions.
7. No blocking findings are detected. CodeRabbit's result for this cycle is `APPROVED`.
8. All other internal reviewers (e.g., `claude`) also return `APPROVED` in their respective turns.
9. The runner posts the Step 7a summary comment and calls `gh pr ready` to convert the draft PR to non-draft.
10. Step 7 (external automated reviewer loop) then runs as normal.

**Postconditions**:

- The draft PR is converted to non-draft.
- The Step 7a summary comment lists CodeRabbit as an effective reviewer that approved.
- The PR is ready to enter Step 7 (external review loop).

**Information shown**:

- Step 7a summary comment: effective reviewer set (including `coderabbit`), final verdict `APPROVED`.

**Actions available**:

- The runner proceeds to Step 7.
- Human reviewers can inspect the Step 7a summary comment to see that CodeRabbit ran internally.

**Considerations**:

- CodeRabbit's invocation in Step 7a reuses the same auto-review mechanism as Step 7, but the context is a draft PR. CodeRabbit may behave differently on draft PRs depending on its configuration (e.g., the `draft_pr_reviews` setting in `.coderabbit.yaml`). The spec requires the integration work correctly for draft PRs (see BR-5). Specific invocation details — auto-trigger vs. explicit trigger comment — are an implementation decision for the plan stage.
- If `coderabbit` also appears in `review.platforms` (Step 7), both gates are distinct: Step 7a runs on the draft PR before non-draft conversion, and Step 7 runs after conversion. The same CodeRabbit finding may surface in both stages if not resolved between the two (see BR-7).

---

### Use Case 2: CodeRabbit Returns Blocking Findings — Fix Loop

**Actor**: Work Item Runner
**Preconditions**:

- `.ai-dev-workflow.yaml` includes `coderabbit` in `review.internal_reviewers`.
- A draft PR is open. The CodeRabbit GitHub App is installed and reachable.
- CodeRabbit finds one or more `Critical` or `Major` issues in the draft PR.

**Steps**:

1. The Work Item Runner enters Step 7a.
2. CodeRabbit is triggered on the draft PR. It responds with one or more `Critical` or `Major` findings.
3. The runner classifies these findings as blocking (per the existing severity classification table).
4. The runner records the findings, dispatches the stage-appropriate fixer agent (following the same fixer dispatch rules as in Step 7), and waits for the fix push.
5. After the fix is pushed, CodeRabbit reviews the updated draft PR (via auto-review on push or an explicit trigger comment, per the implementation detail selected in the plan stage). The runner polls for a new response.
6. CodeRabbit finds no more blocking issues. The result for this cycle is `APPROVED`.
7. Any remaining internal reviewers run and also `APPROVED`.
8. The runner posts the Step 7a summary comment and calls `gh pr ready`.

**Postconditions**:

- Blocking issues surfaced by CodeRabbit in the draft stage are resolved before the PR is made non-draft.
- The Step 7a summary comment records the number of fix cycles and the final verdict.

**Information shown**:

- Step 7a summary comment: effective reviewer set, fix cycles taken, final verdict `APPROVED`.

**Actions available**:

- If the fix cycle limit is reached before approval, the runner escalates to the human.

**Considerations**:

- The maximum fix-cycle count for Step 7a (currently 5) applies to CodeRabbit the same way it does to other reviewers; CodeRabbit blocking findings do not get unlimited cycles.

---

### Use Case 3: CodeRabbit Unavailable — Warning and Skip (Default `warn` Policy)

**Actor**: Work Item Runner
**Preconditions**:

- `review.internal_reviewers` includes `coderabbit` (and at least one other reachable reviewer such as `claude`).
- CodeRabbit is unreachable (e.g., GitHub App is not installed, or the runner cannot post PR comments).
- The configured `internal_reviewers_unavailable_policy` is `warn` (default).

**Steps**:

1. The Work Item Runner performs the runtime-availability check for `coderabbit`.
2. The check determines `coderabbit` is unreachable (per the availability classification table, BR-2).
3. The runner posts a warning comment to the draft PR:
   > `WARNING: internal_reviewer 'coderabbit' unreachable from current runner — skipping. Only '[reachable-reviewers]' will run in this Step 7a cycle. Reviewer coverage is reduced from N to M.`
4. `coderabbit` is recorded as `skipped (unreachable)`.
5. Remaining reachable reviewers run normally. If all approve, the runner posts the Step 7a summary comment (listing `coderabbit` as skipped) and calls `gh pr ready`.

**Postconditions**:

- The draft PR is converted to non-draft once all reachable reviewers approve.
- A warning comment and the Step 7a summary comment are posted, both noting `coderabbit` was skipped.

**Information shown**:

- Warning comment: which reviewer was skipped and why.
- Step 7a summary comment: effective reviewer set, skipped reviewers with reason, final verdict.

**Actions available**:

- Human reviewers can inspect the PR and choose not to merge if reduced reviewer coverage is unacceptable.

**Considerations**:

- If ALL reviewers including `coderabbit` are unreachable, the existing hard-fail rule applies: the draft PR is not converted and the item is escalated.

---

### Use Case 4: CodeRabbit Configured Only in Step 7a, Not Step 7 (No Duplicate Run)

**Actor**: Work Item Runner
**Preconditions**:

- `.ai-dev-workflow.yaml` includes `coderabbit` in `review.internal_reviewers` but NOT in `review.platforms`.
- A draft PR is open.

**Steps**:

1. Step 7a runs, triggers CodeRabbit on the draft PR, and awaits a verdict.
2. CodeRabbit approves. The PR is converted to non-draft.
3. Step 7 runs. Since `coderabbit` is not listed in `review.platforms`, the external reviewer loop does not re-trigger CodeRabbit.
4. Step 7 completes with only the other configured platforms (or is skipped if none are configured).

**Postconditions**:

- CodeRabbit runs exactly once (in Step 7a). No duplicate trigger occurs in Step 7.

**Information shown**:

- Step 7a summary comment notes CodeRabbit ran and approved.
- Step 7 summary notes CodeRabbit was not in the external platforms list.

**Considerations**:

- This is the expected configuration when a team wants CodeRabbit only as an early draft gate without a second post-non-draft review.

---

### Use Case 5: CodeRabbit Configured in Both Step 7a and Step 7 (Both Stages Run)

**Actor**: Work Item Runner
**Preconditions**:

- `.ai-dev-workflow.yaml` includes `coderabbit` in both `review.internal_reviewers` AND `review.platforms`.
- A draft PR is open.

**Steps**:

1. Step 7a runs. CodeRabbit is triggered on the draft PR. Findings addressed and resolved.
2. PR is converted to non-draft (after all internal reviewers approve).
3. Step 7 runs. CodeRabbit is triggered again (per the external review loop contract) on the non-draft PR.
4. Since fixes were already applied in Step 7a, CodeRabbit may find no new issues in Step 7 and report clean.

**Postconditions**:

- CodeRabbit runs twice: once in Step 7a (draft stage), once in Step 7 (external reviewer loop).
- This is a valid and explicitly supported configuration; the two runs are independent and complement each other.

**Information shown**:

- Step 7a summary: CodeRabbit internal review verdict.
- Step 7 summary: CodeRabbit external reviewer verdict.

**Considerations**:

- This is an intentional choice for teams that want coverage at both the draft stage and the post-non-draft stage. The two runs are not redundant in general: new pushes between Step 7a and Step 7 may introduce new issues.
- Both runs count against their respective loop limits (Step 7a fix-cycle limit and Step 7 cycle limit). They do not share a cycle counter.

---

## Business Rules

- **BR-1 — `coderabbit` is a supported `internal_reviewers` value**: The value `coderabbit` must be recognized and handled by the Step 7a internal review gate. Unrecognized values in `internal_reviewers` are an error and must be flagged (this is existing behavior for unknown values; `coderabbit` is added to the recognized set alongside `claude` and `codex`).

- **BR-2 — Runtime-availability check for `coderabbit`**: The availability check for `coderabbit` is determined by whether the CodeRabbit GitHub App is installed and accessible on the repository — i.e., whether the runner can post trigger comments and observe `coderabbitai[bot]` responses via `gh`. Unlike `codex`, which is determined by runner context alone, `coderabbit` availability depends on the repository's GitHub App configuration. The check may inspect `coderabbitai[bot]` activity on the PR or confirm App installation via `gh api`. The exact detection mechanism is an implementation decision for the plan stage; the spec requires only that it be deterministic, fast (no multi-minute wait), and documented.

- **BR-3 — Severity classification is identical to Step 7**: When CodeRabbit runs in Step 7a, blocking vs. suggestion classification follows the same severity table already defined for Step 7: `Critical` and `Major` are blocking; `Minor` and `Low`/no-marker are suggestions. No new classification rules are introduced for the internal reviewer role.

- **BR-4 — Fix-cycle limit applies uniformly**: CodeRabbit blocking findings in Step 7a are subject to the same `max_internal_review_cycles` limit (default: 5) as other internal reviewers. There are no special extended limits for CodeRabbit.

- **BR-5 — Draft PR support required**: The CodeRabbit trigger and response-parsing mechanism used in Step 7a must work on draft PRs. If CodeRabbit does not review draft PRs in the current configuration (e.g., `.coderabbit.yaml` restricts reviews to non-draft PRs), that must be treated as a runtime-availability failure (same outcome as "App not installed").

- **BR-6 — Step 7a and Step 7 are independent, non-deduplicating runs**: When `coderabbit` appears in both `review.internal_reviewers` and `review.platforms`, both runs execute independently. The Step 7a run does not suppress the Step 7 run or vice versa. Each run uses its own cycle counter. This is the documented behavior and not a configuration conflict.

- **BR-7 — No double-counting of findings across Step 7a and Step 7**: If a finding reported by CodeRabbit in Step 7a is fixed before the PR is converted to non-draft, it must not count as an open finding in Step 7. The independence of the two runs (BR-6) does not mean findings carry over; each run starts fresh from the current PR state at the time of the trigger.

- **BR-8 — Backward compatibility for repos using CodeRabbit only in Step 7**: Repos that list `coderabbit` only in `review.platforms` (not in `review.internal_reviewers`) must continue to work exactly as before. The new feature has no effect on Step 7 behavior.

- **BR-9 — Reachability table is updated**: The reachability classification table in Protocol 91 Step 7a must be extended to include `coderabbit`. The new row must document the conditions under which `coderabbit` is classified as reachable vs. unreachable.

- **BR-10 — `.ai-dev-workflow.yaml` comments updated**: The `review.internal_reviewers` key comment in `.ai-dev-workflow.yaml` must be updated to list `coderabbit` as a supported value with a brief description of its invocation behavior.

---

## Operational Visibility

- **PR Comments**: When CodeRabbit runs in Step 7a, the trigger comment and CodeRabbit's response are visible on the PR. Blocking findings and their resolution are tracked in the Step 7a fix-cycle ledger.
- **Step 7a Summary Comment**: The mandatory Step 7a summary comment (posted before `gh pr ready`) lists `coderabbit` as an effective reviewer (if it ran), its verdict, and any fix cycles taken. If it was skipped, the summary notes it as `skipped (unreachable)`.
- **Console / Agent Log**: Availability-check outcomes (reachable, unreachable, or availability-detection errors) are logged to the agent output.
- **Audit Trail**: The PR comment history contains the full CodeRabbit Step 7a interaction (trigger, findings, fixes, summary). This is separate from any Step 7 interaction that follows.

---

## Acceptance Criteria

- [ ] A repo can set `review.internal_reviewers: [claude, coderabbit]` in `.ai-dev-workflow.yaml` and Step 7a runs both reviewers in that order before converting the draft PR to non-draft.
- [ ] When CodeRabbit runs in Step 7a and posts no `Critical` or `Major` findings, the verdict for CodeRabbit is `APPROVED` and Step 7a proceeds normally.
- [ ] When CodeRabbit posts `Critical` or `Major` findings in Step 7a, those findings are treated as blocking and the PR stays draft until fixes are applied and re-reviewed (subject to the existing `max_internal_review_cycles` limit).
- [ ] `Minor`, `Low`, and unmarked CodeRabbit findings in Step 7a are non-blocking (suggestions only) and do not prevent Step 7a from completing.
- [ ] When CodeRabbit is listed in `review.internal_reviewers` but is unreachable (App not installed, or App installed but draft PRs not enabled), the runner posts a warning comment to the PR, records CodeRabbit as `skipped (unreachable)`, and proceeds with the remaining reachable reviewers under the `warn` policy (default).
- [ ] When CodeRabbit is the only reviewer in `review.internal_reviewers` and is unreachable, the gate hard-fails (PR stays draft, item escalated to human).
- [ ] Step 7a exits with a deterministic result in all conditions: approved, needs-revision (fix loop), skipped-with-warning, or hard-fail. No ambiguous or timeout-without-result states are permitted.
- [ ] The Step 7a summary comment lists `coderabbit` in the effective reviewer set (if it ran) or in the skipped reviewers section (if it was unavailable), with reason.
- [ ] When `coderabbit` is listed in both `review.internal_reviewers` and `review.platforms`, both Step 7a and Step 7 run CodeRabbit independently without conflict. The Step 7a run does not suppress or shortcut the Step 7 run.
- [ ] Repos that list `coderabbit` only in `review.platforms` (existing behavior) are unaffected; no Step 7a change is triggered by `review.platforms` alone.
- [ ] Protocol 91 Step 7a documentation is updated to include `coderabbit` in the supported-reviewer list and in the reachability classification table.
- [ ] `coderabbit.md` integration doc is updated with a "Step 7a — Internal Reviewer" section describing invocation behavior, draft-PR requirements, and troubleshooting for common unavailability reasons.
- [ ] `.ai-dev-workflow.yaml` template comments are updated to list `coderabbit` as a supported `internal_reviewers` value.

---

## Out of Scope (MVP)

- Adding CodeRabbit support to the Codex `workflow-*-reviewer` skills (Step 7a CodeRabbit invocation is handled by the Work Item Runner's own loop, not by dispatched reviewer agents; Codex skill updates are a separate concern).
- Changing how CodeRabbit severity labels work at a product level (e.g., configuring custom severity thresholds via `.coderabbit.yaml`); this spec only defines how existing severity markers are classified as blocking or non-blocking.
- Supporting CodeRabbit as a reviewer in environments without `gh` CLI access (the implementation relies on `gh` for PR comment posting and polling, consistent with all other Step 7a and Step 7 tooling).
- Automatic installation or configuration of the CodeRabbit GitHub App; the feature requires the App to be pre-installed and configured by the operator.
- New `.coderabbit.yaml` configuration options; this spec defines workflow behavior, not CodeRabbit product configuration.
- Merging or deduplicating the Step 7a and Step 7 fix-cycle ledgers when `coderabbit` is listed in both.
- Supporting a CodeRabbit "CLI-only" (Path A) mode as an internal reviewer; this spec targets the GitHub App (Path B) only, which is the mechanism used in Step 7.
