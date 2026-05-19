# Enforce Ready-for-Regression Label and Reviewer-Loop Handoff via CI — Spec

---

## Overview

This feature replaces protocol-text enforcement of two recurring workflow gaps with structural enforcement that runs as CI on every implementation pull request. The first gap is the `ready-for-regression` label being missing when an agent declares a PR ready for human review (observed in nine separate batches). The second gap is a PR being treated as ready while the automated reviewer loop never ran to completion — leaving unresolved review findings on a PR that appears merge-eligible. The template ships a re-usable GitHub Actions workflow skeleton that downstream repositories adopt to (a) automatically apply the regression label based on branch prefix and (b) surface reviewer-loop completion as a visible status check, so neither gap depends on agent compliance.

---

## Use Cases

### Use Case 1: A workflow runner opens a draft implementation PR

**Actor**: Workflow runner (any AI agent or human) opening a draft pull request from an implementation branch.
**Preconditions**:

- The PR is opened from a branch whose name starts with `feature/`, `fix/`, `refactor/`, or `hotfix/`.
- The PR targets a development integration branch or release branch (the same branches that today gate `ready-for-regression`-driven regression jobs).

**Steps**:

1. The runner pushes the branch and opens the PR (draft or non-draft, either path is supported).
2. The CI label-management workflow runs automatically on the PR-opened event.
3. The CI workflow applies the `ready-for-regression` label to the PR based on the branch prefix.
4. The runner continues its normal lifecycle (internal review gate, automated reviewer loop, etc.).

**Postconditions**:

- The PR carries the `ready-for-regression` label without the runner needing to apply it manually.
- The runner's protocol checklist for "label applied" is satisfied by CI rather than by agent action.

**Information shown**:

- A CI run is visible on the PR with a clear name identifying it as the regression-label management workflow.
- The applied label is visible in the PR labels list.

**Actions available**:

- A maintainer can remove the label manually if a PR is intentionally out of scope for regression (the existing "remove on push" behaviour continues to apply on subsequent commits).

**Considerations**:

- Branches that are explicitly out of regression scope today (`spec/*`, `implementation-plan/*`, `docs/*`, `chore/*`, and any other prefixes the downstream repo opts out of) must not receive the label. The template ships the in-scope branch prefix list as a documented default but allows downstream repos to override it.
- If the label is already present (re-runs, manual application), the workflow is a no-op and does not fail.
- Converting a draft PR to non-draft must also result in the label being present (covers runners that open as draft and convert later).

---

### Use Case 2: A workflow runner declares a PR ready before the reviewer loop has produced its summary

**Actor**: Workflow runner attempting to converge a PR to "ready for human review".
**Preconditions**:

- The PR is on one of the in-scope implementation branch prefixes.
- The automated reviewer loop has not yet completed (no canonical summary comment present on the PR).

**Steps**:

1. The runner pushes commits and prepares to converge the PR.
2. The CI reviewer-loop completion guard runs on every PR update.
3. The guard inspects the PR's comment timeline for the canonical "Automated Reviewer Loop Summary" completion comment (the comment posted by the template's reviewer-loop script when it runs to completion).
4. If the summary comment is absent, the guard reports a failing status check with a clear human-readable reason.
5. The PR remains visibly not-ready: the failing check is shown in the PR header, and the regression-driven downstream jobs treat the PR as not yet handed off.

**Postconditions**:

- A PR that lacks a reviewer-loop summary cannot pass the guard, regardless of which agent applied which label.
- Once the reviewer loop posts (or updates in place) its summary comment, the guard re-runs and passes.

**Information shown**:

- A named CI status check whose label clearly indicates whether the reviewer-loop summary is present.
- On failure, an actionable message explaining that the reviewer loop must run to completion before the PR is treated as handed off.

**Actions available**:

- Re-run the automated reviewer loop (which posts/updates the summary comment) to make the check pass.
- A maintainer with appropriate permissions may, in an exceptional case, override the check at merge time using whatever branch-protection override the downstream repo configures (the template does not prescribe a forced override mechanism).

**Considerations**:

- The check must look at the same canonical summary comment shape the reviewer-loop script produces today, so existing PRs that already follow the contract automatically pass.
- The check must re-evaluate on subsequent pushes (`synchronize`), because the existing "remove regression label on push" behaviour resets readiness when new commits arrive.
- The check must distinguish "summary absent" (true failure) from "API error fetching comments" (transient failure that should be retried, not treated as a hard fail of the contract).

---

### Use Case 3: A maintainer adopts the template in a downstream repository

**Actor**: Maintainer of a downstream repository that consumes this template.
**Preconditions**:

- The downstream repo has copied or synced the template's `.github/workflows/` files.
- The downstream repo uses the standard branch prefixes for implementation work.

**Steps**:

1. The maintainer reviews the shipped CI workflow file(s) for label enforcement and reviewer-loop guarding.
2. The maintainer confirms the default in-scope branch prefixes (`feature/`, `fix/`, `refactor/`, `hotfix/`) match the downstream repo's conventions, or adjusts them via the documented override mechanism the template exposes.
3. The maintainer enables the reviewer-loop completion guard as a required status check in branch protection for the integration and release branches.
4. The maintainer verifies that subsequent implementation PRs receive the label automatically and that the guard's status check is visible on the PR.

**Postconditions**:

- The downstream repo enforces both gaps structurally, with no further agent-side protocol text required.
- Maintainers can rely on PRs reaching "human review" only when both contracts are satisfied.

**Information shown**:

- Documentation in the template explaining what the workflow does, which branch prefixes are in scope by default, how to override them, and how to wire the guard into branch protection as a required check.

**Actions available**:

- Override the in-scope branch prefix list per repo.
- Disable the workflow entirely if the downstream repo opts out (the workflow files are template-owned files and can be removed locally with documented sync rules).

**Considerations**:

- The template repo is itself `is_template: true`, so the spec must define both "what the template ships" and "what downstream repos configure". The template ships a working default; downstream repos consume it.

---

## Business Rules

- An implementation PR (branch prefix `feature/`, `fix/`, `refactor/`, or `hotfix/`) targeting the configured integration or release branch must carry the `ready-for-regression` label by the time it is treated as merge-eligible, and the label must be applied by CI rather than by an agent.
- A PR may not be considered handed off to human review unless the canonical automated reviewer-loop summary comment is present on its timeline. This invariant is independent of which labels are applied.
- The two contracts are independent: a PR can have the label without a reviewer-loop summary (which the guard must catch), and a PR can have a reviewer-loop summary without the label (the label workflow must apply it).
- Spec, plan, documentation, chore, and other non-implementation branches must never receive the `ready-for-regression` label via this workflow, regardless of target branch.
- Both CI mechanisms must be idempotent: re-runs on the same PR state must not produce duplicate labels, duplicate comments, or spurious failures.
- The workflow must not depend on protocol text being followed; if the agent does nothing related to labels, the label must still appear, and if the agent posts the wrong summary, the guard must still fail.
- The workflow must not require any new tokens, secrets, or third-party services beyond what is already available to GitHub Actions in the template (i.e. the default `GITHUB_TOKEN` with appropriate per-job permissions).
- The reviewer-loop completion check must use the same canonical summary marker that the existing reviewer-loop script writes, so adopting this feature does not require changes to the reviewer-loop script's output contract.

---

## Operational Visibility

- **Logs**: Each CI run logs the PR number, branch name, whether the branch is in the in-scope prefix list, whether the label was newly applied or already present, and whether the reviewer-loop summary comment was found.
- **Notifications**: The standard GitHub PR check UI surfaces both jobs. No additional notification channel is introduced by this feature.
- **Audit trail**: GitHub records the label application as a PR event with the workflow as the actor, making it trivially auditable in the PR timeline and via the GitHub API. The reviewer-loop guard's pass/fail state is similarly recorded as a check run.

---

## Acceptance Criteria

- [ ] Opening a PR from a `feature/`, `fix/`, `refactor/`, or `hotfix/` branch causes the `ready-for-regression` label to be applied automatically, without any agent or human action, and the label is visible on the PR within one CI run.
- [ ] Opening a PR from a `spec/`, `implementation-plan/`, `docs/`, or `chore/` branch does not result in the `ready-for-regression` label being applied by this workflow.
- [ ] Converting a draft implementation PR to non-draft results in the label being present on the PR (covers cases where the open event is draft).
- [ ] If the label is already present when the workflow runs, the workflow completes successfully without duplicate labels and without failure.
- [ ] An implementation PR with no "Automated Reviewer Loop Summary" comment shows a failing required-status check named clearly (e.g. "Reviewer-loop completion guard" or equivalent).
- [ ] The same PR's check transitions to passing once the reviewer-loop script posts (or updates in place) its summary comment.
- [ ] The reviewer-loop completion check re-evaluates on every push to the PR branch (`synchronize` event), so the check resets to failing once new commits arrive and the reviewer-loop summary is invalidated by the existing "remove regression label on push" behaviour.
- [ ] The template ships documentation that explains (a) which branch prefixes are in scope by default, (b) how downstream repos override the prefix list, and (c) how to add the reviewer-loop completion check to branch protection as a required check.
- [ ] Both workflows pass `actionlint` (or the equivalent GitHub Actions linter already used in the template) with no new warnings.
- [ ] Both workflows declare the minimum permissions needed (e.g. `pull-requests: write` for the label workflow; read-only for the guard) and do not request broader scopes than required.
- [ ] A smoke test on a downstream repo (or a deliberate fixture PR in this repo) demonstrates: (1) opening a `feature/*` PR auto-applies the label, (2) the guard fails until a reviewer-loop summary appears, and (3) the guard passes once the summary is present.
- [ ] None of the changes in this feature add new protocol text or new agent-side checklists for the regression label or reviewer-loop completion. The protocol surface for these two contracts shrinks (or stays flat) once CI ownership is in place.

---

## Out of Scope (MVP)

- Removing existing protocol-text references to the `ready-for-regression` label and reviewer-loop summary from the various protocol files. The plan stage will decide how much existing protocol text to deprecate and in what order; this spec is focused on standing up the CI enforcement first.
- Backfilling the label or reviewer-loop summary check on already-merged or already-closed PRs.
- Changing the canonical shape of the "Automated Reviewer Loop Summary" comment itself. This feature consumes the existing marker as-is; any change to the marker is a separate workflow concern.
- Changing the existing "remove `ready-for-regression` label on push" workflow behaviour. That workflow continues to run unchanged and complements (not conflicts with) the new auto-apply workflow.
- Enforcing label or reviewer-loop completion via a third-party service (e.g. an external bot). This feature is intentionally limited to GitHub Actions and the default `GITHUB_TOKEN`.
- Enforcing similar contracts for branches outside the four implementation prefixes (e.g. release branches or batch-merge integration branches) — those flows already have separate gates and are not in scope here.
- Defining the downstream repo's branch protection rules. The template ships the workflow and documents how to wire it into branch protection; actually configuring branch protection is a per-repo administrative action.

---

## Coverage Matrix (Brief Objectives → Spec Artifacts)

| # | Brief objective (from issue #613) | Mapped to |
| - | --- | --- |
| 1 | Auto-apply `ready-for-regression` via `pull_request` event workflow on `fix/*`, `feature/*`, `refactor/*`, `hotfix/*` branches (opened or converted to non-draft) | Use Case 1; Acceptance Criteria #1, #2, #3, #4; Business Rules (label-application invariant, non-implementation branch exclusion, idempotency) |
| 2 | Reviewer-loop completion guard: required status check that asserts the canonical reviewer-loop summary comment exists before the PR is treated as ready | Use Case 2; Acceptance Criteria #5, #6, #7; Business Rules (handoff invariant, marker reuse, independence from labels) |
| 3 | Fix strategy must be structural CI/GitHub Actions, not new protocol text | Use Case 3; Acceptance Criterion #11 (no new protocol text); Business Rule ("must not depend on protocol text being followed") |
| 4 | Cover both gaps: (a) label missing at PR-ready time, (b) reviewer-loop handoff missing/premature | Use Case 1 covers gap (a); Use Case 2 covers gap (b); Acceptance Criteria #1–#4 cover (a); Acceptance Criteria #5–#7 cover (b) |
| 5 | Implementation must be a re-usable CI workflow skeleton; spec written in terms of what downstream repos configure (template-aware framing) | Use Case 3; Acceptance Criterion #8 (template ships documentation, downstream override mechanism, branch-protection wiring); Business Rule on default `GITHUB_TOKEN` and no new services |

No objective is silently dropped. All five objectives map to use cases, acceptance criteria, or both.

---

## Deferral Notes

The following items were intentionally moved to **Out of Scope (MVP)** rather than dropped. Each is recorded here with rationale; none require human confirmation to defer because all of them either (a) are explicitly downstream of this feature or (b) are non-template administrative actions.

1. **Removing existing protocol-text references to the label and summary contract.**
   - **Rationale**: This spec replaces enforcement with CI but does not require simultaneously rewriting every protocol file. The plan stage will decide what protocol text to deprecate and when. Stripping protocol text in the same change would expand blast radius and make rollback harder.
   - **Human confirmation requested**: No.

2. **Backfilling label/summary checks on already-merged or already-closed PRs.**
   - **Rationale**: Historical PRs were merged under the previous regime; retroactive enforcement provides no value and could trigger noisy failing checks on closed PRs.
   - **Human confirmation requested**: No.

3. **Changing the canonical summary comment shape.**
   - **Rationale**: This feature is intentionally a consumer of the existing marker. Any change to the marker would be a separate, broader concern coordinated with the reviewer-loop script's contract.
   - **Human confirmation requested**: No.

4. **Modifying the existing "remove label on push" workflow.**
   - **Rationale**: That workflow already complements this feature correctly: when commits land, the label is removed, the reviewer loop must re-run, the guard re-evaluates, and once both are satisfied the label is reapplied. Changing it now would broaden scope unnecessarily.
   - **Human confirmation requested**: No.

5. **External-service or third-party enforcement.**
   - **Rationale**: Adds a token/secret surface, increases adoption friction for downstream repos, and provides no value over GitHub Actions with `GITHUB_TOKEN`.
   - **Human confirmation requested**: No.

6. **Enforcing similar contracts on non-implementation branches (release branches, batch-merge integration branches).**
   - **Rationale**: Release and batch-merge flows already have their own readiness gates defined in separate protocols. Conflating their enforcement with this feature risks regressing those flows.
   - **Human confirmation requested**: No.

7. **Configuring downstream-repo branch protection.**
   - **Rationale**: Branch protection is a per-repo administrative action. The template's job is to ship the workflow and document how to wire it; configuring protected branches in each downstream repo is outside the workflow itself.
   - **Human confirmation requested**: No.
