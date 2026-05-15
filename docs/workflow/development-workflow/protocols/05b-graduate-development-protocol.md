# Protocol: Graduate Development Integration Branch

**Agent role**: Graduation Agent (invoked via `/graduate-development <slug>`)
**Purpose**: Verify all sub-items are merged to `develop-<slug>`, then open a merge-commit PR from `develop-<slug>` to `develop` summarising all included sub-items.

---

## Prerequisites

- All planned sub-items for the epic labeled `integration-branch:<slug>` are merged to `develop-<slug>`.
- The human has completed integration testing on `develop-<slug>` and is satisfied the feature is ready to land on `develop`.
- `gh` CLI is authenticated and the local repo has the latest remote refs (`git fetch origin`).

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

3. If any sub-item has no merged implementation PR, list the unmerged items and stop:

   > Graduation blocked: the following sub-items have no merged implementation PR on `develop-<slug>`: [list]. Complete or merge those items before graduating.

---

## Step 3: Open the Graduation PR

1. Ensure the local `develop-<slug>` branch is up to date:

   ```bash
   git fetch origin
   git checkout -B develop-<slug> origin/develop-<slug>
   ```

2. Build the PR body: list each sub-item with its issue number, title, and implementation PR number.
3. Open the graduation PR:

   ```bash
   gh pr create \
     --base develop \
     --head develop-<slug> \
     --title "Graduate \`<slug>\` integration branch to develop" \
     --body "<generated-body>"
   ```

4. The PR body must include:
   - A one-paragraph summary of what the feature delivers.
   - A bulleted list of all sub-items: `- #<issue> <title> (PR #<pr>)`.
   - A note that the merge strategy must be **merge commit** (not squash or rebase).

---

## Step 4: Run the Standard Review Loop

Run the automated reviewer loop (`pr-review-loop.sh`) and CI loop on the graduation PR. Apply `ready-for-human-review` once clean.

---

## Step 5: Post-Merge Cleanup

After the human merges the graduation PR (must use a **merge commit**):

1. Switch to `develop` and sync the merge commit:

   ```bash
   git checkout develop
   git pull origin develop
   ```

2. Delete the integration branch on the remote:

   ```bash
   git push origin --delete develop-<slug>
   ```

3. Delete the local branch:

   ```bash
   git branch -d develop-<slug>
   ```

4. Confirm to the human: "Integration branch `develop-<slug>` has been deleted. All sub-items are now on `develop`."

---

## Non-Goals

- This protocol does not autonomously graduate an integration branch. The human must invoke it explicitly.
- Keeping `develop-<slug>` up to date with `develop` is out of scope. The human pulls manually if needed before integration testing.
