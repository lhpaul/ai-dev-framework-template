# Protocol: Graduate Development Integration Branch

**Agent role**: Graduation Agent (invoked via `/graduate-development <slug>`)
**Purpose**: Verify all sub-items are merged to `develop-<slug>`, then open a merge-commit PR from `develop-<slug>` to `develop` summarising all included sub-items.

---

## CI coverage for integration branches

A project's own CI workflows must include `develop-**` in their
`pull_request` branch filters, alongside `develop`. Sub-item PRs in an epic
target `develop-<slug>`; a workflow that gates only on `develop` runs **zero
checks** on them, and the epic's entire implementation reaches this
graduation PR having never been tested, linted, or typechecked (#1525 —
measured downstream at 4 checks on a sub-item PR versus 13 on the graduation
PR, which then surfaced four real defects in already-merged code).

Use the `develop-**` glob, never a hardcoded slug: a stale
`develop-<old-slug>` entry reads as coverage while the current integration
branch is absent. [`scripts/development-workflow/tests/test-workflow-branch-filters.sh`](../../../../scripts/development-workflow/tests/test-workflow-branch-filters.sh)
enforces both rules for the workflows this template ships.

## Release Evidence Ownership

For workflow-hub product releases, graduation evidence must preserve the
release ownership contract: delivery manifests and tracker reconciliation
evidence remain hub-owned, while product changelog, release branch, tag,
GitHub Release, deployment evidence, and product cleanup evidence remain owned
by the selected product repository.

When graduation hands off to component release preparation, carry forward the
`component_release_target.v1` binding and `component_release_evidence.v1`
record produced by `scripts/development-workflow/component-release-target.sh`
and `scripts/development-workflow/component-release-evidence.sh`; do not infer
the product repository from the hub checkout or integration branch name.

---

## Prerequisites

- All planned sub-items for the epic are discoverable through native GitHub sub-issues when available, or through the legacy `integration-branch:<slug>` label fallback.
- All planned sub-items for the epic are merged to `develop-<slug>`.
- The human has completed integration testing on `develop-<slug>` and is satisfied the feature is ready to land on `develop`.
- `gh` CLI is authenticated and the local repo has the latest remote refs (`git fetch origin`).

---

## Step 0: Human Approval Gate

**This step is mandatory. The Graduation Agent must not proceed past this point without explicit human approval (BR-1).**

1. Retrieve the full list of sub-items. Prefer native GitHub sub-issues when the epic issue number is known:

   ```bash
   gh api graphql \
     -F owner=<owner> \
     -F repo=<repo> \
     -F number=<epic-issue-number> \
     -f query='
       query($owner: String!, $repo: String!, $number: Int!) {
         repository(owner: $owner, name: $repo) {
           issue(number: $number) {
             number
             title
             subIssues(first: 100) {
               nodes { number title state }
               pageInfo { hasNextPage endCursor }
             }
           }
         }
       }
     '
   ```

   If `pageInfo.hasNextPage` is `true`, continue querying with the returned `endCursor` and merge every page before presenting the planned sub-item list.

   If native sub-issues are unavailable or the epic issue number is unknown, use the legacy label fallback:

   ```bash
   gh issue list --label "integration-branch:<slug>" --state all --limit 1000 --json number,title,state --jq '.[] | "#\(.number) \(.title) [\(.state)]"'
   ```

2. For each sub-item, fetch its latest implementation PR targeting `develop-<slug>`:

   ```bash
   gh pr list --state merged --base "develop-<slug>" --json number,title,headRefName \
     --jq '.[] | "PR #\(.number): \(.headRefName) — \(.title)"'
   ```

3. Present the following to the human before taking any action:
   - Which integration branch is eligible for graduation: `develop-<slug>`.
   - A list of all planned sub-items with issue numbers, titles, and merged PR numbers.
   - A note identifying any sub-items that are open, deferred, or optional — so the human can confirm whether to include them or defer graduation.

4. Wait for the human to explicitly approve graduation. Do **not** open the graduation PR, push any commit, or run any review until the human responds with an approval.
   - **Human approves** → continue to Step 1.
   - **Human defers** → stop and record the hold; do not modify any artifact.
   - **Human requests more sub-items be merged first** → stop and wait; do not open the graduation PR.

> **Note**: The merge strategy for the graduation PR must be **merge commit** (not squash or rebase). Squash or rebase would collapse the sub-item contribution history into a single synthetic commit, losing individual contribution history.

---

## Step 1: Resolve the Slug

Accept `<slug>` as input. Derive the integration branch name: `develop-<slug>`.

---

## Step 2: Verify All Sub-Items Are Merged

1. List all planned GitHub sub-items. Prefer native sub-issues from the epic issue, then fall back to `gh issue list --label "integration-branch:<slug>"` for legacy epics:

   ```bash
   gh api graphql \
     -F owner=<owner> \
     -F repo=<repo> \
     -F number=<epic-issue-number> \
     -f query='
       query($owner: String!, $repo: String!, $number: Int!) {
         repository(owner: $owner, name: $repo) {
           issue(number: $number) {
             subIssues(first: 100) {
               nodes { number title state labels(first: 20) { nodes { name } } }
               pageInfo { hasNextPage endCursor }
             }
           }
         }
       }
     '
   ```

   If `pageInfo.hasNextPage` is `true`, continue querying with the returned `endCursor` and merge every page before filtering or checking completion. Graduation decisions must be based on the complete native sub-issue set, not only the first page.

   For each native sub-issue, verify the child-side parent relationship before treating it as planned:

   ```bash
   gh api graphql \
     -F owner=<owner> \
     -F repo=<repo> \
     -F number=<sub-item-issue-number> \
     -f query='
       query($owner: String!, $repo: String!, $number: Int!) {
         repository(owner: $owner, name: $repo) {
           issue(number: $number) {
             number
             parent { number title }
           }
         }
       }
     '
   ```

   If native sub-issues are unavailable, use:

   ```bash
   gh issue list --label "integration-branch:<slug>" --state all --limit 1000 --json number,title,state --jq '.[] | "#\(.number) \(.title) [\(.state)]"'
   ```

2. For each sub-item, confirm that its implementation PR is merged:

   ```bash
   # Substitute <issue-number> and <slug> with actual values before running:
   gh pr list --state merged --search "<issue-number>" --json number,headRefName,baseRefName,mergedAt \
     --jq '[.[] | select((.headRefName | test("^(feature|fix|refactor)/<issue-number>(-|$)")) and .baseRefName=="develop-<slug>")]'
   ```

3. If any planned (non-optional, non-cancelled) sub-item has no merged implementation PR, list the unmerged items and stop:

   > Graduation blocked: the following sub-items have no merged implementation PR on `develop-<slug>`: [list]. Complete or merge those items before graduating. (BR-3)

4. **Divergence check**: after confirming all planned sub-items are merged, check whether `develop-<slug>` has fallen behind `develop` in a way that would cause conflicts:

   ```bash
   git fetch origin
   BEHIND=$(git rev-list --count origin/develop-<slug>..origin/develop)
   echo "$BEHIND commits on develop not yet in develop-<slug>"
   ```

   If `$BEHIND` is non-zero, surface the divergence to the human before proceeding:

   > `develop-<slug>` is behind `develop` by $BEHIND commit(s). A merge-commit graduation PR will still work, but the human should review for potential conflicts before proceeding. Continue?

   Wait for confirmation before opening the PR if divergence is detected.

---

## Step 2.5: CHANGELOG Handling

Before opening the graduation PR, verify that all `[Unreleased]` CHANGELOG entries accumulated on `develop-<slug>` will be present in the graduation PR diff.

The sub-item PRs each added CHANGELOG entries to `develop-<slug>`. The graduation PR must carry those entries intact — they will land on `develop` together with the code when the graduation PR is merged.

**Important (BR-5)**: Do not pre-absorb CHANGELOG entries separately from the graduation PR. The absorb commit must be part of the graduation branch itself (or already present via the sub-item PRs), not a separate prior merge into `develop`. This was a lesson learned during PR #737.

**Verification**:

```bash
# Check whether CHANGELOG.md differs between develop and develop-<slug>
git diff origin/develop..origin/develop-<slug> -- CHANGELOG.md | head -n 40
```

If the diff shows `[Unreleased]` entries on `develop-<slug>` that are absent from `develop`, these will be carried over by the graduation PR as expected — no additional action is needed.

If the diff is empty (no CHANGELOG difference), warn the human:

> Warning: CHANGELOG.md appears identical between `develop` and `develop-<slug>`. If no CHANGELOG entries were added by the sub-item PRs, this may be expected. If entries were expected, check whether they were accidentally merged to `develop` separately before the graduation PR.

---

## Step 2.6: Verify Review Platform Coverage

Before opening the graduation PR, confirm that the integration branch's `.ai-dev-workflow.yaml` lists all applicable GitHub reviewers.

When an integration branch is created, it branches off `develop` at a point in time. If `review.on_draft.github` or `review.on_ready.github` entries are later added to `develop` (e.g., `haystack` was added in v0.27.0), those additions are **not** automatically propagated to existing integration branches. A graduation PR run against a branch missing a reviewer will silently skip that reviewer's triage.

**Checklist — run before Step 3**:

1. Fetch the integration branch's `.ai-dev-workflow.yaml` and compare `review.on_draft.github` plus `review.on_ready.github` against the same lists on `develop`:

   ```bash
   # Show GitHub reviewer buckets on develop
   git show origin/develop:.ai-dev-workflow.yaml | grep -A 20 'on_draft:'
   git show origin/develop:.ai-dev-workflow.yaml | grep -A 10 'on_ready:'

   # Show GitHub reviewer buckets on the integration branch
   git show origin/develop-<slug>:.ai-dev-workflow.yaml | grep -A 20 'on_draft:'
   git show origin/develop-<slug>:.ai-dev-workflow.yaml | grep -A 10 'on_ready:'
   ```

2. If any platform present on `develop` is absent from `develop-<slug>`, update `.ai-dev-workflow.yaml` on the integration branch to match. At minimum, both `pr-agent` and `haystack` must be listed if the main repository uses them.

   ```bash
   set -euo pipefail
   git fetch origin
   git checkout -B develop-<slug> origin/develop-<slug>
   CURRENT_BRANCH=$(git branch --show-current)
   if [ "$CURRENT_BRANCH" != "develop-<slug>" ]; then
     echo "ERROR: expected branch develop-<slug>, got $CURRENT_BRANCH — aborting" >&2
     exit 1
   fi
   # Edit .ai-dev-workflow.yaml to add any missing reviewers under review.on_draft.github or review.on_ready.github
   git add .ai-dev-workflow.yaml
   git commit -m "chore: sync review config from develop before graduation"
   git push origin develop-<slug>
   ```

3. If the platforms already match, no action is needed — proceed to Step 3.

> **Why this matters**: PRs targeting an integration branch use that branch's `.ai-dev-workflow.yaml` to determine which review platforms run. A missing platform means PR triage is silently incomplete for every sub-item PR on that branch, not just the graduation PR. Catching the gap before graduation ensures the ceremony retrospective has accurate platform coverage data and that the graduation PR itself is fully reviewed. (Root cause: Batch 64, issue #754.)

---

## Step 3: Open the Graduation PR

1. Ensure the local `develop-<slug>` branch is up to date:

   ```bash
   git fetch origin
   git checkout -B develop-<slug> origin/develop-<slug>
   ```

2. Build the PR body: list each sub-item with its issue number, title, and implementation PR number. The PR body **must** include all of the following (AC-3, AC-4, AC-5):
   - A one-paragraph summary of what the epic delivers.
   - A bulleted list of all sub-items: `- #<issue> <title> (PR #<pr>)`.
   - An explicit statement: "Merge strategy: **merge commit** (not squash or rebase)."
   - A note on any optional/deferred sub-items that were not included in this graduation, if applicable.

3. Open the graduation PR:

   ```bash
   gh pr create \
     --base develop \
     --head develop-<slug> \
     --title "Graduate \`<slug>\` integration branch to develop" \
     --body "<generated-body>"
   ```

   **Nested graduation**: for a nested integration lineage (e.g. a wave
   branch `develop-ventas-e3b` graduating into a module branch
   `develop-sales-module` rather than directly into `develop`), pass the
   parent integration branch to `--base` instead of `develop`, and use that
   same branch name for `--base` in `graduation-closeout.sh` at Step 5.

---

## Step 4: Run the Standard Review Loop

Run the automated reviewer loop (`pr-review-loop.sh`) and CI loop on the graduation PR. Apply `ready-for-human-review` once clean.

> **`ready-for-regression` is NOT required for graduation PRs** (BR-6): Graduation PRs from `develop-<slug>` to `develop` do not carry new implementation — all code was already included in each sub-item's implementation PR and tested there. Do not apply the `ready-for-regression` label to a graduation PR.

---

## Step 5: Post-Merge Cleanup

After the human merges the graduation PR (must use a **merge commit**):

1. Switch to the graduation PR's base branch and sync the merge commit —
   this is `develop`, unless the graduation PR was a nested graduation
   (Step 3) whose base was a parent integration branch such as
   `develop-sales-module`, in which case use that branch instead:

   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   git checkout <graduation-pr-base>   # develop, or the parent integration branch
   git pull origin <graduation-pr-base>
   ```

2. Delete the integration branch on the remote (BR-7):

   ```bash
   git push origin --delete develop-<slug>
   ```

3. Delete the local branch:

   ```bash
   git branch -d develop-<slug>
   ```

4. **Run graduation closeout** (BR-8, BR-9, AC-9): Reconcile delivered planned sub-items and the parent epic with the tracker before reporting the integration branch as fully closed.

   **This Step 5 command remains the primary closeout path.** Merge-time automation
   is a fallback only: when a graduation PR (`develop-<slug>` → `develop`) merges,
   `.github/workflows/update-tracker-on-merge.yml` invokes
   `graduation-closeout-from-merged-pr.sh`, which discovers slug/epic/deferral
   signals and calls the **same** reconciler below. Agent and automation
   double-runs are safe/idempotent (`already_terminal` / no regressive moves).

   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   ./scripts/development-workflow/graduation-closeout.sh \
     --slug <slug> \
     --graduation-pr <graduation-pr-number> \
     --epic <epic-issue-number>
   ```

   Add `--base <branch>` when this is a nested graduation whose PR base is a
   parent integration branch rather than `develop` (e.g. `--base
   develop-sales-module`) — it must match the graduation PR's actual base,
   and it must be `develop` or a `develop-*` integration branch. Add
   `--exclude-issue <issue-number>` for optional, deferred, cancelled, or explicitly excluded sub-items that must remain open for human disposition. Add `--defer-epic-close` only when the human explicitly requests that the parent epic remain open after the core deliverable graduates.

   **Operator deferral durability:** `--defer-epic-close` also ensures the epic
   carries the durable label `defer-epic-close` before closeout reports success.
   Merge-time automation reads that label (and the existing sub-item skip labels
   `optional`, `deferred`, `cancelled`, `excluded-from-graduation`,
   `exclude-from-graduation`) so a later fallback run does not force-close a
   deferred epic or excluded sub-item.

   The helper:
   - validates that the graduation PR is already merged from `develop-<slug>` to its expected base (`develop` by default, or the branch passed via `--base` for a nested graduation);
   - identifies planned sub-items from native GitHub sub-issues or the `integration-branch:<slug>` label fallback;
   - includes issue references from closing keywords in merged PRs targeting `develop-<slug>`;
   - closes open delivered sub-items and reasserts the configured terminal Project status;
   - updates closed-but-non-terminal delivered sub-items to the terminal Project status;
   - reports already terminal sub-items without moving them backward;
   - skips optional/deferred/excluded sub-items and reports the required human disposition;
   - fails closed when candidate discovery is incomplete or no delivered sub-items can be identified;
   - closes the parent epic only after delivered planned sub-items reconcile, unless epic closure is explicitly deferred.

   Terminal Project status is resolved in this order: `GITHUB_PROJECT_STATUS_GRADUATED`, `GITHUB_PROJECT_STATUS_MERGED`, then `Merged`.

   If `GRADUATION_CLOSEOUT_RESULT=failed`, stop and repair the listed `failed` items before claiming graduation cleanup is complete. Do not close the parent epic manually while delivered sub-item failures remain.

5. **Optional sub-item disposition** (Use Case 4, AC-10): For any items listed under `skipped_optional`, surface them to the human for disposition. The helper has already left them open intentionally.

   ```bash
   gh issue list --label "integration-branch:<slug>" --state open --limit 1000 --json number,title,labels \
     --jq '.[] | "#\(.number): \(.title)"'
   ```

   Present the human with the following options for each remaining open sub-item:
   - Reassign as a standalone work item targeting `develop` directly (remove the `integration-branch:<slug>` label).
   - Create a new integration branch for a follow-up epic.
   - Cancel/close the sub-item if it will not be pursued.

   The orchestrator does not silently drop open sub-items — it surfaces them and waits for the human's decision (BR-4).

6. **Worktree cleanup** (optional): Check for stale worktrees associated with the graduated integration branch or its sub-items:

   ```bash
   git worktree list
   ```

   Remove any worktrees whose branches have already been merged and deleted:

   ```bash
   # From the repo root (not from inside any worktree):
   git worktree remove <worktree-path>
   ```

7. Confirm to the human: "Integration branch `develop-<slug>` has been deleted. Delivered planned sub-items were reconciled by graduation closeout. Epic issue closed (or: left open — see disposition notes above)."

---

## Non-Goals

- This protocol does not autonomously graduate an integration branch. The human must invoke it explicitly and approve the graduation in Step 0 before any action is taken (BR-1).
- Keeping `develop-<slug>` up to date with `develop` is out of scope. The human pulls manually if needed before integration testing.
- Partially-completed graduations (where only some planned sub-items are done) are not supported — all planned sub-items must be merged before graduation (BR-3).
- Automated disposition of optional sub-items: the orchestrator surfaces the list (Step 5) but does not make autonomous decisions about their future (BR-4).

---

## Business Rules Reference

The following business rules from the spec are enforced by this protocol:

| Rule | Enforced in   | Description                                                                      |
| ---- | ------------- | -------------------------------------------------------------------------------- |
| BR-1 | Step 0        | Human approval required before graduation                                        |
| BR-2 | Steps 3, 4, 5 | Merge commit is mandatory (not squash or rebase)                                 |
| BR-3 | Step 2        | All planned sub-items must be merged before graduation                           |
| BR-4 | Steps 0, 5    | Optional sub-items surfaced to human; do not silently skip                       |
| BR-5 | Step 2.5      | CHANGELOG absorb must be part of the graduation branch, not a prior merge        |
| BR-6 | Step 4        | `ready-for-regression` NOT required for graduation PRs                           |
| BR-7 | Step 5        | Post-graduation remote branch deletion is mandatory                              |
| BR-8 | Step 5        | Epic issue closed after delivered sub-items reconcile (unless human defers)      |
| BR-9 | Step 5        | Graduation closeout reconciles delivered sub-items and terminal Project status   |
