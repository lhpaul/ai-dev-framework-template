# Integration: CI Enforcement of Regression Label and Reviewer-Loop Handoff

This document describes the two GitHub Actions workflows that enforce structural
compliance with the `ready-for-regression` label and reviewer-loop handoff
contracts on every implementation pull request. These workflows replace
protocol-text-only enforcement with CI-level enforcement that runs regardless
of agent behaviour.

Both workflows ship as part of the template and require no new secrets, tokens,
or third-party services beyond the default `GITHUB_TOKEN`.

---

## Workflows

### 1. `apply-regression-label.yml` — Auto-apply `ready-for-regression`

**File**: `.github/workflows/apply-regression-label.yml`

**What it does**: Automatically applies the `ready-for-regression` label to any
pull request opened from an in-scope implementation branch prefix (`feature/`,
`fix/`, `refactor/`, `hotfix/`). Runs on PR `opened`, `reopened`,
`ready_for_review`, and `synchronize` events.

**Idempotent**: If the label is already present, the workflow completes without
error and without duplicating the label.

**Label auto-creation**: The workflow calls `gh label create --force` before
applying the label, so the label is created in the repository if it does not
exist. The `--force` flag makes this a no-op when the label already exists with
a different color or description.

**Non-implementation branches are excluded**: Branches whose prefix does not
match any entry in `IN_SCOPE_PREFIXES` (e.g. `spec/`, `implementation-plan/`,
`docs/`, `chore/`) are skipped silently with an exit code of 0.

**Complements the remove-on-push workflow**: The existing
`remove-regression-label-on-push.yml` workflow removes the label when new
commits arrive. These two workflows together implement the full label lifecycle:
label is applied on open/reopen/ready/synchronize (this workflow), and removed
on subsequent pushes (existing workflow), so the reviewer loop must re-run after
every commit batch.

### 2. `reviewer-loop-guard.yml` — Reviewer-loop completion guard

**File**: `.github/workflows/reviewer-loop-guard.yml`

**What it does**: Posts a GitHub commit status check (`success` or `failure`) on
every in-scope implementation PR push to assert that the automated reviewer-loop
summary comment is present. The check is named **"Reviewer-loop completion guard"**
so it can be added to branch protection as a required status check by that exact
name.

**Markers checked**: The guard looks for a comment body that contains **both**:
- `### Automated Reviewer Loop Summary`
- `*Posted automatically by \`pr-review-loop.sh\`.*`

These are the same two markers used in `scripts/development-workflow/pr-review-loop.sh`
to identify its own summary comments (see lines 3335–3336 of that script). No
changes to the reviewer-loop script's output contract are required.

**Status outcomes**:
- `success` — at least one matching comment was found on the PR.
- `failure` — no matching comment found; the PR is not yet reviewer-loop-complete.
- `failure` (transient) — the GitHub API call to fetch comments failed; the
  workflow exits with code 1 so GitHub retries the check on the next event.

**Non-implementation branches always pass**: Branches whose prefix does not match
`IN_SCOPE_PREFIXES` receive a `success` status with the description
"Not an implementation branch; guard skipped."

---

## Default In-Scope Branch Prefixes

Both workflows use the same default set of in-scope branch prefixes:

```
feature/   fix/   refactor/   hotfix/
```

These match the four standard implementation branch types defined in the
development workflow (`docs/workflow/development-workflow/README.md`). Spec
branches (`spec/`), plan branches (`implementation-plan/`), and all other
non-implementation branches are excluded by default.

---

## Overriding the In-Scope Prefix List (Downstream Repos)

To customise which branch prefixes receive the label and are subject to the
guard, edit the `IN_SCOPE_PREFIXES` environment variable in each workflow file:

```yaml
# In .github/workflows/apply-regression-label.yml
# and .github/workflows/reviewer-loop-guard.yml
env:
  IN_SCOPE_PREFIXES: "feature/ fix/ refactor/ hotfix/ your-custom-prefix/"
```

Both workflow files must be updated together so their in-scope lists remain
consistent. Alternatively, implement a shared repository variable or a called
workflow to centralise the list.

No other changes are required to add or remove a prefix.

---

## Wiring the Guard into Branch Protection (Required Status Check)

To make the reviewer-loop guard a **required** status check on the integration
branch (e.g. `develop`) or release branch (`main`), follow these steps in the
downstream repository:

1. Open the repository **Settings** page.
2. Navigate to **Branches** → **Branch protection rules**.
3. Edit or create the rule for the target branch (e.g. `develop`).
4. Enable **"Require status checks to pass before merging"**.
5. In the search box, type `Reviewer-loop completion guard` and select the
   check that appears.
6. Save the rule.

Once configured, GitHub blocks merges on PRs where the guard has not yet posted
a `success` status.

> **Note**: The status check appears in the search box only after the
> `reviewer-loop-guard.yml` workflow has run at least once on a PR targeting
> the protected branch. Open a test PR first if the check does not appear yet.

---

## No Manual Label Setup Required

The `apply-regression-label.yml` workflow creates the `ready-for-regression`
label automatically via `gh label create --force` on its first run. There is no
need to create the label manually in a newly forked or synced downstream
repository.

---

## Permissions

| Workflow | Permissions declared |
| -------- | -------------------- |
| `apply-regression-label.yml` | `pull-requests: write` (minimum required to add a label) |
| `reviewer-loop-guard.yml` | `pull-requests: read`, `statuses: write` (minimum required to read comments and post a commit status) |

No other permissions are requested. Both workflows use the default
`GITHUB_TOKEN` injected by GitHub Actions and do not require any additional
secrets or service accounts.

---

## Relationship to Existing Workflow Steps

These CI workflows enforce contracts that were previously described only in
protocol text:

| Contract | Previous enforcement | CI enforcement |
| -------- | -------------------- | -------------- |
| `ready-for-regression` label applied to implementation PRs | Protocol 91 Step 5.1 checklist (agent-side) | `apply-regression-label.yml` (structural) |
| Reviewer-loop summary present before PR is ready | Protocol 91 Step 7 / Step 5.1 checklist (agent-side) | `reviewer-loop-guard.yml` (structural) |

The CI workflows complement, not replace, the agent-side checklist. The agent
Step 5.1 check in Protocol 91 remains the authoritative gate for the agent
runner; the CI workflows provide a structural backstop that catches cases where
the agent did not run or skipped the check.
