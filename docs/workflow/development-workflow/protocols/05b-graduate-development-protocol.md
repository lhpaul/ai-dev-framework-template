# Protocol: Graduate Development Integration Branch

**Agent role**: Graduation Agent (invoked via `/graduate-development <slug>`)
**Purpose**: Verify all sub-items are merged to `develop-<slug>`, then open a merge-commit PR from `develop-<slug>` to `develop` summarising all included sub-items.

---

## Prerequisites

- All planned sub-items for the epic labeled `integration-branch:<slug>` are merged to `develop-<slug>`.
- The human has completed integration testing on `develop-<slug>` and is satisfied the feature is ready to land on `develop`.
- `gh` CLI is authenticated and the local repo has the latest remote refs (`git fetch origin`).

---

## Step 0: Human Approval Gate

**This step is mandatory. The Graduation Agent must not proceed past this point without explicit human approval (BR-1).**

1. Retrieve the full list of sub-items labeled `integration-branch:<slug>`:

   ```bash
   gh issue list --label "integration-branch:<slug>" --state all --json number,title,state --jq '.[] | "#\(.number) \(.title) [\(.state)]"'
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

1. List all GitHub issues labeled `integration-branch:<slug>` using `gh issue list --label "integration-branch:<slug>"`.
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
git diff origin/develop..origin/develop-<slug> -- CHANGELOG.md | head -40
```

If the diff shows `[Unreleased]` entries on `develop-<slug>` that are absent from `develop`, these will be carried over by the graduation PR as expected — no additional action is needed.

If the diff is empty (no CHANGELOG difference), warn the human:

> Warning: CHANGELOG.md appears identical between `develop` and `develop-<slug>`. If no CHANGELOG entries were added by the sub-item PRs, this may be expected. If entries were expected, check whether they were accidentally merged to `develop` separately before the graduation PR.

---

## Step 2.6: Verify Review Platform Coverage

Before opening the graduation PR, confirm that the integration branch's `.ai-dev-workflow.yaml` lists all applicable review platforms.

When an integration branch is created, it branches off `develop` at a point in time. If `review.platforms` entries are later added to `develop` (e.g., `haystack` was added in v0.27.0), those additions are **not** automatically propagated to existing integration branches. A graduation PR run against a branch missing a platform will silently skip that platform's triage.

**Checklist — run before Step 3**:

1. Fetch the integration branch's `.ai-dev-workflow.yaml` and compare `review.platforms` against the same list on `develop`:

   ```bash
   # Show review.platforms on develop
   git show origin/develop:.ai-dev-workflow.yaml | grep -A 20 'platforms:'

   # Show review.platforms on the integration branch
   git show origin/develop-<slug>:.ai-dev-workflow.yaml | grep -A 20 'platforms:'
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
   # Edit .ai-dev-workflow.yaml to add any missing platforms under review.platforms
   git add .ai-dev-workflow.yaml
   git commit -m "chore: sync review.platforms from develop before graduation"
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

---

## Step 4: Run the Standard Review Loop

Run the automated reviewer loop (`pr-review-loop.sh`) and CI loop on the graduation PR. Apply `ready-for-human-review` once clean.

> **`ready-for-regression` is NOT required for graduation PRs** (BR-6): Graduation PRs from `develop-<slug>` to `develop` do not carry new implementation — all code was already included in each sub-item's implementation PR and tested there. Do not apply the `ready-for-regression` label to a graduation PR.

---

## Step 5: Post-Merge Cleanup

After the human merges the graduation PR (must use a **merge commit**):

1. Switch to `develop` and sync the merge commit:

   ```bash
   git checkout develop
   git pull origin develop
   ```

2. Delete the integration branch on the remote (BR-7):

   ```bash
   git push origin --delete develop-<slug>
   ```

3. Delete the local branch:

   ```bash
   git branch -d develop-<slug>
   ```

4. **Close the epic issue** (BR-8, AC-9): Close the epic GitHub issue in the tracker, since the core planned deliverable has landed on `develop`. If optional sub-items remain open, leave a note on the epic before closing:

   ```bash
   # Close the epic issue; substitute <epic-issue-number> with the actual issue number
   gh issue close <epic-issue-number> --comment "Core deliverable graduated to \`develop\` via graduation PR. Epic closed. Remaining optional sub-items (if any) are listed below for disposition."
   ```

   If the human has explicitly requested to leave the epic open until all optional sub-items are resolved, defer the closure and note this in the cleanup summary.

5. **Optional sub-item disposition** (Use Case 4, AC-10): For any sub-items labeled `integration-branch:<slug>` that remain open at graduation time, surface them to the human for disposition:

   ```bash
   gh issue list --label "integration-branch:<slug>" --state open --json number,title,labels \
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

7. Confirm to the human: "Integration branch `develop-<slug>` has been deleted. All sub-items are now on `develop`. Epic issue closed (or: left open — see disposition notes above)."

---

## Non-Goals

- This protocol does not autonomously graduate an integration branch. The human must invoke it explicitly and approve the graduation in Step 0 before any action is taken (BR-1).
- Keeping `develop-<slug>` up to date with `develop` is out of scope. The human pulls manually if needed before integration testing.
- Partially-completed graduations (where only some planned sub-items are done) are not supported — all planned sub-items must be merged before graduation (BR-3).
- Automated disposition of optional sub-items: the orchestrator surfaces the list (Step 5) but does not make autonomous decisions about their future (BR-4).

---

## Business Rules Reference

The following business rules from the spec are enforced by this protocol:

| Rule | Enforced in | Description |
| ---- | ----------- | ----------- |
| BR-1 | Step 0 | Human approval required before graduation |
| BR-2 | Steps 3, 4, 5 | Merge commit is mandatory (not squash or rebase) |
| BR-3 | Step 2 | All planned sub-items must be merged before graduation |
| BR-4 | Steps 0, 5 | Optional sub-items surfaced to human; do not silently skip |
| BR-5 | Step 2.5 | CHANGELOG absorb must be part of the graduation branch, not a prior merge |
| BR-6 | Step 4 | `ready-for-regression` NOT required for graduation PRs |
| BR-7 | Step 5 | Post-graduation remote branch deletion is mandatory |
| BR-8 | Step 5 | Epic issue closed after graduation (unless human defers) |
| BR-9 | Step 5 | Sub-items already marked Done at merge time; no additional tracker update needed |
