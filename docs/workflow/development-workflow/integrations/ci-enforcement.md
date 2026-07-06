# Integration: CI Enforcement of Regression Label and Reviewer-Loop Handoff

This document describes the consolidated GitHub Actions PR policy workflow that
enforces structural compliance with the `ready-for-regression` label and
reviewer-loop handoff contracts on every implementation pull request. The
workflow replaces protocol-text-only enforcement with CI-level enforcement that
runs regardless of agent behaviour.

The workflow ships as part of the template and requires no new secrets, tokens,
or third-party services beyond the default `GITHUB_TOKEN`.

---

## Workflow

### `pr-policy.yml` — Consolidated PR policy

**File**: `.github/workflows/pr-policy.yml`

**What it does**: Handles the lightweight PR policy surface that previously
lived in separate apply-label, stale-label removal, and reviewer-loop guard
workflows. Keeping these behaviours in one API-only workflow reduces redundant
short-job fan-out for downstream private repositories while preserving reviewer
readiness, regression readiness, fork safety, and PR-scoped status semantics.

The workflow handles these events:

- `pull_request_target`: `opened`, `reopened`, `ready_for_review`,
  `synchronize`
- `issue_comment`: `created`, `edited`

The workflow does not use `actions/checkout`, does not execute PR head code, and
does not read files from untrusted fork heads.

---

## Event Routing

| Event | In-scope same-repository implementation PR | Non-implementation PR | Fork-head PR |
| --- | --- | --- | --- |
| `opened`, `reopened`, `ready_for_review` | Ensures and applies `ready-for-regression`, then evaluates reviewer-loop guard status. | Skips implementation labels and posts successful skipped-guard status. | Skips privileged label and status mutation. |
| `synchronize` | Removes stale `ready-for-regression` only when no canonical reviewer-loop summary exists, then evaluates reviewer-loop guard status. | Skips implementation labels and posts successful skipped-guard status. | Skips privileged label and status mutation. |
| Summary `issue_comment` | Re-fetches current PR metadata and comments, then refreshes the PR-scoped guard status. | Posts successful skipped-guard status. | Skips privileged label and status mutation. |
| Non-summary `issue_comment` | Exits without changing labels or statuses. | Exits without changing labels or statuses. | Exits without changing labels or statuses. |

The `ready-for-regression` label is a readiness signal for configured real
regression checks. It does not by itself enable inactive placeholder regression
work; the template placeholder in `.github/workflows/e2e-regression.yml` still
requires explicit downstream opt-in before dependency or browser installation
runs.

---

## Reviewer-Loop Guard Status

The workflow posts a GitHub commit status check (`success` or `failure`) for
in-scope implementation PRs to assert that the automated reviewer-loop summary
comment is present.

The check is named **"Reviewer-loop completion guard (#\<PR_NUMBER\>)"**. The PR
number is included in the context name so that two PRs sharing the same commit
SHA, such as a release PR and its backport, cannot overwrite each other's guard
result.

**Markers checked**: The guard looks for a comment body that contains **both**:

- `### Automated Reviewer Loop Summary`
- `*Posted automatically by \`pr-review-loop.sh\`.*`

These are the same two markers used in
`scripts/development-workflow/pr-review-loop.sh` to identify its own summary
comments. No changes to the reviewer-loop script's output contract are
required.

**Status outcomes**:

- `success` — at least one matching comment was found on the PR.
- `failure` — no matching comment found; the PR is not yet
  reviewer-loop-complete.
- `failure` (transient) — required PR metadata, head fields, or comments could
  not be read; the workflow exits with code 1 so GitHub can retry on the next
  event.

---

## Regression Label Lifecycle

The workflow manages `ready-for-regression` for same-repository implementation
PRs only:

1. On `opened`, `reopened`, and `ready_for_review`, it creates the label if
   needed and applies it to in-scope implementation PRs.
2. On `synchronize`, it removes the label only when the PR has the label and no
   canonical reviewer-loop summary comment exists.
3. If the comments API fails on `synchronize`, it skips label removal. Unknown
   reviewer-loop state is treated conservatively so the workflow does not drop a
   label that may have been deliberately applied by the reviewer loop.
4. If a canonical reviewer-loop summary already exists, the workflow leaves the
   label in place because `pr-review-loop.sh` owns re-establishing readiness on
   its next invocation.

The label operation is idempotent: re-runs on an already-labeled PR complete
without duplicating the label.

---

## Default In-Scope Branch Prefixes

The workflow uses the default implementation branch prefixes:

```text
feature/   fix/   refactor/   hotfix/
```

These match the four standard implementation branch types defined in the
development workflow. Spec branches (`spec/`), plan branches
(`implementation-plan/`), and all other non-implementation branches are excluded
by default.

---

## Overriding the In-Scope Prefix List

To customise which branch prefixes receive the label and are subject to the
guard, edit the `IN_SCOPE_PREFIXES` environment variable in
`.github/workflows/pr-policy.yml`:

```yaml
env:
  IN_SCOPE_PREFIXES: "feature/ fix/ refactor/ hotfix/ your-custom-prefix/"
```

No other changes are required to add or remove a prefix.

---

## Wiring the Guard into Branch Protection

Because the guard's context name includes the PR number
(`"Reviewer-loop completion guard (#<PR_NUMBER>)"`), you cannot add it as a
fixed-string required status check. Use one of the following approaches instead:

**Option A — Wildcard status check pattern (recommended if your GitHub plan supports it)**

Some GitHub Enterprise plans allow wildcard patterns in required status checks.
If available, add the pattern `Reviewer-loop completion guard (#*)` to your
branch protection rule.

**Option B — GitHub Rulesets with status-check wildcards**

GitHub repository rulesets (Settings -> Rules -> Rulesets) support
`starts_with` and `contains` match types for required status checks. Create a
ruleset and add a status-check requirement that matches
`Reviewer-loop completion guard`.

**Option C — Manual PR-by-PR enforcement**

Without wildcard support, teams rely on the commit-status badge visible in each
PR's status summary to verify the guard passed before merging. The guard still
posts `success` or `failure` correctly; only automated merge-blocking at the
branch-protection layer is unavailable.

To set up a ruleset:

1. Open the repository **Settings** page.
2. Navigate to **Rules** -> **Rulesets** -> **New branch ruleset**.
3. Set the target to the desired branch pattern, such as `develop` or `main`.
4. Enable **"Require status checks to pass"**.
5. Add a status check matching `Reviewer-loop completion guard` using a
   `starts_with` or `contains` match type.
6. Save the ruleset.

The status check context appears in the UI only after `pr-policy.yml` has run at
least once on a PR targeting the protected branch. Open a test PR first if the
check does not appear yet.

---

## No Manual Label Setup Required

`pr-policy.yml` creates the `ready-for-regression` label automatically on its
first same-repository implementation PR run when the label is absent. There is
no need to create the label manually in a newly forked or synced downstream
repository.

---

## Permissions

| Permission | Why it is needed |
| --- | --- |
| `issues: read` | Read PR issue comments to find the reviewer-loop summary. |
| `pull-requests: write` | Read PR metadata and apply or remove PR labels. |
| `statuses: write` | Post the reviewer-loop guard commit status. |

No other permissions are requested. The workflow uses the default
`GITHUB_TOKEN` injected by GitHub Actions and does not require additional
secrets or service accounts.

---

## Relationship to Existing Workflow Steps

The CI workflow complements, not replaces, the agent-side checklist:

| Contract | Agent-side enforcement | CI enforcement |
| --- | --- | --- |
| `ready-for-regression` label applied to implementation PRs | Protocol 91 Step 5.1 checklist | `pr-policy.yml` |
| Stale `ready-for-regression` removed before reviewer-loop readiness exists | Protocol 91 review and CI ordering | `pr-policy.yml` |
| Reviewer-loop summary present before PR is ready | Protocol 91 Step 7 / Step 5.1 checklist | `pr-policy.yml` |

The agent Step 5.1 check in Protocol 91 remains the authoritative gate for the
agent runner. `pr-policy.yml` provides a structural backstop that catches cases
where the agent did not run or skipped the check.

When a downstream repository has not configured real regression tests, the
auto-applied label may be present while the template placeholder remains
inactive. That is expected: the label preserves staged workflow semantics, while
explicitly enabled placeholder or real regression workflows decide whether
expensive checks run.
