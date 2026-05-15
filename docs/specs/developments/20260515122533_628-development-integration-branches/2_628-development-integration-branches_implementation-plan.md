# Development Integration Branches — Implementation Plan

**Spec**: [1\_628-development-integration-branches\_specs.md](./1_628-development-integration-branches_specs.md)
**Smoke test runbook**: [../../../testing/workflow/628-development-integration-branches.smoke-test.md](../../../testing/workflow/628-development-integration-branches.smoke-test.md)

---

## Summary

**Approach**: This change is purely documentation: add integration-branch concepts, label schema, and the `develop-<slug>` naming convention to the relevant workflow protocol files, extend the orchestration protocols (00, 90, 91) with the integration-branch detection and creation steps, and create the new `05b-graduate-development-protocol.md`. No scripts or code are changed — all acceptance criteria are satisfied by documentation updates and the new graduation protocol.

**Estimated complexity**: M

**Rationale**: Five existing protocol files require targeted section additions, one new protocol file must be created, and the workflow README needs a branch-naming row and a graduation command row. No logic changes to scripts or agents are needed for the MVP — the integration-branch workflow is enforced by human-readable protocol text that agents read and follow.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `816f8a4` |
| Existing integration-branch references in protocols | `grep -rl "integration.branch\|develop-\|graduate" docs/workflow/development-workflow/ \| sort` | 5 files — README.md, 03, 90, 91, 94 (all use "integration branch" in the generic sense of `develop`; none implement the feature) |
| Protocol files under `docs/workflow/development-workflow/protocols/` | `ls docs/workflow/development-workflow/protocols/ \| sort` | 17 files; no `05b-*.md` exists yet |
| Agent files referencing plan/orchestration protocols | `grep -rl "02-generate-implementation-plan\|91-orchestrate-work" .claude/agents/ .cursor/agents/ .codex/skills/ 2>/dev/null \| sort` | `.claude/agents/item-orchestrator.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/item-orchestrator.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] No infrastructure or configuration changes required.

### Documentation / Protocols

This is a documentation-only change. All affected files are under `docs/workflow/development-workflow/`.

#### New file

- [ ] Create `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` — the graduation agent protocol invoked by the `/graduate-development <slug>` command

#### Existing files to modify

- [ ] `docs/workflow/development-workflow/README.md` — add the `develop-<slug>` integration-branch concept to the "Branch Naming" section and add the `/graduate-development` graduation command to the "Commands By Stage" table
- [ ] `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` — add a new Step (after existing steps) covering multi-item epic detection and the `integration-branch:<slug>` label creation
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — add integration-branch detection in Step 1 (portfolio state gathering), integration-branch creation in the pre-dispatch checks, and base-branch override logic (`develop-<slug>` instead of `develop`) when a sub-item carries the label
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — add integration-branch detection to the pre-dispatch branch check (Step 2), base-branch override when the sub-item label is present, and integration-branch creation when missing
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — add a note to the branching step (Step 5 / Path 1) about reading the `integration-branch:<slug>` label and using `develop-<slug>` as the base branch

---

## Testing Strategy

**Test types**: Manual smoke test (protocol-reading exercise and dry-run of the commands)

**Key scenarios to test**:

1. Adding two related backlog items triggers epic creation and `integration-branch:<slug>` labeling — maps to AC 1
2. A workflow agent reading a sub-item label opens its PR against `develop-<slug>` — maps to AC 2
3. The orchestrator creates `develop-<slug>` from `develop` before the first sub-item PR — maps to AC 3
4. The graduation command opens a PR from `develop-<slug>` to `develop` with sub-item summary — maps to AC 4
5. The graduation PR uses a merge commit strategy — maps to AC 5
6. The `develop-<slug>` branch is deleted after the graduation PR merges — maps to AC 6
7. A single-item development is unaffected and its PRs still target `develop` — maps to AC 7
8. All five named documentation files contain the integration-branch concept — maps to AC 8

**Smoke test runbook**: `docs/testing/workflow/628-development-integration-branches.smoke-test.md`

---

## Seed Data

None required. This is a documentation-only change; no application data is involved.

---

## Documentation Updates

The files listed below under "Layer-by-Layer Changes — Documentation / Protocols" are themselves the primary deliverable. No additional project docs in `docs/project/` or `docs/best-practices/` require updates — the integration-branch workflow is purely a developer/agent process concept captured in the workflow protocol files.

- [ ] `CLAUDE.md` / `AGENTS.md` — no changes needed; the workflow commands table already has a "Prepare release" row and does not need a "Graduate development" row (graduation is a separate sub-command of the workflow, not a top-level project command listed in CLAUDE.md). Revisit if the graduation command becomes a first-class Claude Code command.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Protocol 90 and 91 are very large files; an implementation agent may add the integration-branch sections to the wrong location, creating context gaps | Med | Med | Implementation Order steps below specify exact section anchors (section heading text) where each addition goes |
| The `05b` protocol structure may not match the style of existing protocol files | Low | Low | Provide a detailed section outline in the Implementation Order so the agent can follow it directly |
| README branch-naming table already has a row for each branch type; adding `develop-<slug>` without context may confuse readers | Low | Low | The README addition should explain this as a staging/grouping branch, not a permanent branch type used for individual PRs |

---

## Implementation Order

### Step 1: Create `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`

Create the new file with the following content outline:

```
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
   gh pr list --state merged --search "<issue-number>" --json number,headRefName,mergedAt \
     --jq '[.[] | select(.headRefName | test("^(feature|fix|refactor)/<issue-number>(-|$)"))]'
   ```
3. If any sub-item has no merged implementation PR, list the unmerged items and stop:
   > Graduation blocked: the following sub-items have no merged implementation PR on `develop-<slug>`: [list]. Complete or merge those items before graduating.

---

## Step 3: Open the Graduation PR

1. Ensure the local `develop-<slug>` branch is up to date:
   ```bash
   git fetch origin
   git checkout develop-<slug>
   git pull origin develop-<slug>
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

1. Delete the integration branch on the remote:
   ```bash
   git push origin --delete develop-<slug>
   ```
2. Delete the local branch:
   ```bash
   git branch -d develop-<slug>
   ```
3. Confirm to the human: "Integration branch `develop-<slug>` has been deleted. All sub-items are now on `develop`."

---

## Non-Goals

- This protocol does not autonomously graduate an integration branch. The human must invoke it explicitly.
- Keeping `develop-<slug>` up to date with `develop` is out of scope. The human pulls manually if needed before integration testing.
```

Verify: the file exists at the correct path and `markdownlint-cli2` reports zero violations.

---

### Step 2: Update `docs/workflow/development-workflow/README.md`

#### 2a — Branch Naming table

In the "Branch Naming" section, add a new row after the "Bug or simple fix" row:

```markdown
| Development integration | `develop-<slug>`             | `develop`   |
```

Add a note below the table:

```markdown
**Development integration branches** (`develop-<slug>`) are staging branches that collect all sub-item PRs for a multi-item grouped development. They are created by the orchestrator and deleted after the graduation PR merges to `develop`. Single-item developments do not use integration branches. See `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
```

#### 2b — Commands By Stage table

In the "Commands By Stage" table, add a new row after the "Batch merge" row (or after "Prepare release", whichever keeps the logical order):

```markdown
| Graduate integration branch | `/graduate-development <slug>` | — | — | Follow `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` |
```

Verify: run `markdownlint-cli2` on `docs/workflow/development-workflow/README.md` and confirm zero violations.

---

### Step 3: Update `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`

#### 3a — Add Step 5 (Multi-Item Epic Detection)

After the existing Step 4 "Confirm to the user", add a new Step 5:

```markdown
## Step 5: Multi-Item Epic Detection (Optional — when two or more related items are requested)

When a human requests the creation of two or more related backlog items that together form a single coherent feature, the agent must also:

1. **Identify the multi-item nature** — confirm that the requested items form a coherent unit where partial delivery would be incomplete or misleading. When in doubt, ask: "Do you want these items to land on `develop` independently as each one completes, or as a group only when all are done?"

2. **Choose a slug** — derive a human-readable kebab-case slug from the shared feature name (e.g., `multi-tenant-billing`). The slug must be unique among existing `integration-branch:*` labels.

3. **Create an epic** — create a GitHub issue with the `epic` label as the grouping container. The title should reflect the overall feature. Record the epic's issue number.

4. **Label each sub-item** — apply the label `integration-branch:<slug>` to each sub-item issue created in Step 3. If the label does not exist in the repository, create it:
   ```bash
   gh label create "integration-branch:<slug>" --color "#0075ca" --description "Sub-item of the <slug> integration branch"
   ```

5. **Confirm to the user** — include in the Step 4 confirmation:
   - The epic issue number and URL
   - The shared label `integration-branch:<slug>` applied to each sub-item
   - The note that sub-item PRs will target `develop-<slug>` (to be created by the orchestrator before the first PR)

**Single-item exemption**: When only a single item is requested, skip this step entirely. Single-item developments target `develop` directly and are not subject to the integration-branch workflow.
```

Verify: run `markdownlint-cli2` on `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` and confirm zero violations.

---

### Step 4: Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

#### 4a — Step 1 additions (portfolio state gathering)

In **Step 1b** (VCS enrichment), add a note:

> When gathering VCS state, also collect the set of open `develop-<slug>` integration branches: `git branch -r | grep "^  origin/develop-"`. For each integration branch found, look up any issues labeled `integration-branch:<slug>` to match the branch to its epic. Record the integration branch name against each matching sub-item in the portfolio map.

#### 4b — Step 3 additions (batch building — base branch override)

At the end of the **Step 3: Build Parallel Batches** section, add a new subsection:

```markdown
### Integration-branch base override

Before dispatching any Work Item Runner for a sub-item, check whether the item carries an `integration-branch:<slug>` label:

```bash
gh issue view <issue-number> --json labels --jq '.labels[].name | select(startswith("integration-branch:"))'
```

If an `integration-branch:<slug>` label is found:

1. **Derive the integration branch name**: `develop-<slug>`.
2. **Verify the branch exists on the remote**:
   ```bash
   git ls-remote origin "refs/heads/develop-<slug>" | wc -l
   ```
3. **If the branch does not exist**, create and push it from `develop`:
   ```bash
   git fetch origin develop
   git checkout -b develop-<slug> origin/develop
   git push origin develop-<slug>
   ```
   Log: `INFO: created integration branch develop-<slug> from origin/develop for epic sub-item #<issue-number>.`
4. **Pass the base branch override to the Work Item Runner handoff**: include `BASE_BRANCH=develop-<slug>` in the handoff metadata so the Work Item Runner and stage agents open PRs against `develop-<slug>` instead of `develop`.
```

Verify: run `markdownlint-cli2` on `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` and confirm zero violations.

---

### Step 5: Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

#### 5a — Step 2 additions (pre-dispatch checks)

In **Step 2** under "Pre-dispatch branch check", add a new subsection immediately after:

```markdown
### Integration-branch base override (sub-items with `integration-branch:<slug>` label)

Before dispatching any creator-stage agent, check whether the item carries an `integration-branch:<slug>` label:

```bash
gh issue view <issue-number> --json labels --jq '.labels[].name | select(startswith("integration-branch:"))'
```

If the label is present:

1. **Derive the integration branch name**: `develop-<slug>` (replace `<slug>` with the value after `integration-branch:`).
2. **Verify the branch exists on the remote**:
   ```bash
   git ls-remote origin "refs/heads/develop-<slug>" | wc -l
   ```
3. **If the branch does not exist**, create and push it from `develop`:
   ```bash
   git fetch origin develop
   git checkout -b develop-<slug> origin/develop
   git push origin develop-<slug>
   git switch develop  # return to develop immediately after creation
   ```
   Log: `INFO: created integration branch develop-<slug> from origin/develop for sub-item #<issue-number>.`
4. **Record the base branch**: store `BASE_BRANCH=develop-<slug>` and pass it to every stage-agent dispatch for this item. All PRs opened for this sub-item (spec, plan, implementation, fix, refactor) must target `develop-<slug>`.

**Single-item exemption**: When the item carries no `integration-branch:*` label, skip this check. The default base branch (`develop`) applies.
```

#### 5b — Step 2 table update (What can advance now?)

In the state/action table under **Step 2**, update the "Spec Ready" row note (or add a row note) to state:

> When the item carries an `integration-branch:<slug>` label, the plan PR targets `develop-<slug>` instead of `develop`. The ordering gate (spec PR merged before plan PR) still applies, but to `develop-<slug>` not `develop`.

#### 5c — Spec-Plan ordering gate update

In the **Spec-Plan ordering gate** section, add a parenthetical clarification:

> (When the item carries an `integration-branch:<slug>` label, "spec PR merged to the integration branch" means merged to `develop-<slug>`, not to `develop`. The ordering gate applies identically; only the target branch changes.)

Verify: run `markdownlint-cli2` on `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and confirm zero violations.

---

### Step 6: Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`

In **Path 1 (Full Pipeline)** and **Path 3 (Fast Track)** branching steps, find the section where the developer creates the feature/fix branch from `develop`. Add a note immediately before the `git checkout -b` command:

```markdown
**Integration-branch check**: Before creating the branch, check whether the work item carries an `integration-branch:<slug>` label (the orchestrator will have noted this in the handoff). If the label is present, use `develop-<slug>` as the base branch instead of `develop`:

```bash
# Standard:
git checkout develop && git pull origin develop
# If integration-branch:<slug> label is present, use develop-<slug> instead:
# git checkout develop-<slug> && git pull origin develop-<slug>
git checkout -b feature/<slug>   # or fix/<slug>
```

The PR opened at the end of this path must target `develop-<slug>` when the label is present. If the integration branch does not exist yet, the orchestrator should have created it before dispatching this protocol — do not create it here; instead, stop and inform the Work Item Runner.
```

Verify: run `markdownlint-cli2` on `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` and confirm zero violations.

---

### Step 7: Pre-commit lint check

Run `markdownlint-cli2` on all modified/created files:

```bash
REPO_ROOT=$(git rev-parse --git-common-dir)/..
"$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
  "docs/specs/developments/20260515122533_628-development-integration-branches/2_628-development-integration-branches_implementation-plan.md" \
  "docs/testing/workflow/628-development-integration-branches.smoke-test.md" \
  "docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md" \
  "docs/workflow/development-workflow/README.md" \
  "docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md" \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md"
```

Fix any violations before committing.

---

### Step 8: Commit and push

```bash
git add \
  docs/specs/developments/20260515122533_628-development-integration-branches/2_628-development-integration-branches_implementation-plan.md \
  docs/testing/workflow/628-development-integration-branches.smoke-test.md \
  docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md \
  docs/workflow/development-workflow/README.md \
  docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md \
  docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \
  docs/workflow/development-workflow/protocols/03-implement-development-protocol.md
git commit -m "docs: add implementation plan for development integration branches (#628)"
git push -u origin implementation-plan/628-development-integration-branches
```

---

### Step 9: Update `CHANGELOG.md` under `[Unreleased]`

```markdown
- **Support long-running multi-item developments via a dedicated integration branch** (#628): adds the `develop-<slug>` integration-branch workflow, epic/label creation in the add-backlog-item protocol, orchestrator-level base-branch override, developer base-branch note, and the new `05b-graduate-development-protocol.md` graduation command.
```
