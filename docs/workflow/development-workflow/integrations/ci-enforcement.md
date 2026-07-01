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

The label is a readiness signal for configured real regression checks. It does
not by itself enable inactive placeholder regression work; the template
placeholder in `.github/workflows/e2e-regression.yml` still requires explicit
downstream opt-in before dependency or browser installation runs.

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

**What it does**: Posts a GitHub commit status check (`success` or `failure`) for
in-scope implementation PRs to assert that the automated reviewer-loop summary
comment is present. Pull request events perform one fast summary check and post
the PR-scoped status immediately; the workflow no longer sleeps or polls for
several minutes by default. A summary `issue_comment` event re-checks the pull
request comments and refreshes the passing status after `pr-review-loop.sh`
posts the canonical summary. The check is named
**"Reviewer-loop completion guard (#\<PR_NUMBER\>)"** — the PR number is included
in the context name so that two PRs sharing the same commit SHA (e.g. a release
PR and its backport) cannot overwrite each other's guard result.

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

**Comment-event behavior**: The `issue_comment` path only runs for pull request
comments that contain the canonical summary markers. Normal comments do not
change reviewer-loop readiness. When a summary comment is detected, the workflow
fetches the pull request's current head SHA and branch before posting the status,
so repeated or edited summary comments are idempotent for the current PR head.

**Non-implementation branches always pass**: Branches whose prefix does not match
`IN_SCOPE_PREFIXES` receive a `success` status with the description
"Not an implementation branch; guard skipped."

**Fork-head PRs are skipped**: The guard preserves the same-repository
restriction used by the existing `pull_request_target` path. If the PR head
repository differs from the base repository, the workflow exits without posting
reviewer-loop readiness statuses.

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

Because the guard's context name includes the PR number
(`"Reviewer-loop completion guard (#<PR_NUMBER>)"`), you cannot add it as a
fixed-string required status check. Use one of the following approaches instead:

**Option A — Wildcard status check pattern (recommended if your GitHub plan supports it)**

Some GitHub Enterprise plans allow wildcard patterns in required status checks.
If available, add the pattern `Reviewer-loop completion guard (#*)` to your
branch protection rule.

**Option B — GitHub Rulesets with status-check wildcards**

GitHub repository rulesets (Settings → Rules → Rulesets) support
`starts_with` and `contains` match types for required status checks. Create a
ruleset and add a status-check requirement that matches
`Reviewer-loop completion guard`.

**Option C — Manual PR-by-PR enforcement (no branch protection)**

Without wildcard support, teams rely on the commit-status badge visible in
each PR's status summary to verify the guard passed before merging. The guard
still posts `success`/`failure` correctly — only the automated merge-blocking
at the branch-protection layer is unavailable.

To set up a ruleset (Option B):

1. Open the repository **Settings** page.
2. Navigate to **Rules** → **Rulesets** → **New branch ruleset**.
3. Set the target to the desired branch pattern (e.g. `develop`, `main`).
4. Enable **"Require status checks to pass"**.
5. Add a status check matching `Reviewer-loop completion guard` using a
   `starts_with` or `contains` match type.
6. Save the ruleset.

Once configured, GitHub blocks merges on PRs where the guard has not yet posted
a `success` status.

> **Note**: The status check context appears in the UI only after the
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
| `reviewer-loop-guard.yml` | `issues: read`, `pull-requests: read`, `statuses: write` (minimum required to read comments, read PR metadata, and post a commit status) |

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

When a downstream repository has not configured real regression tests, the
auto-applied label may be present while the template placeholder remains
inactive. That is expected: the label preserves staged workflow semantics, while
explicitly enabled placeholder or real regression workflows decide whether
expensive checks run.
