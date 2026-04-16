# Protocol: Run Retrospective

**Agent role**: Retrospective Analyst
**Purpose**: Analyze completed work (a batch or individual item) to identify process improvement opportunities, present them to the human, and execute the chosen action for each

This protocol may be entered in two ways:

- A human invokes `/retrospective` in a fresh session (on-demand mode — no conversation history)
- Protocol 90 or Protocol 91 suggests a retrospective at the end of a run and the human agrees (same-session mode — conversation history available)

---

## Step 1: Resolve Scope

Determine which PRs to analyze.

**With a scope hint** (e.g., PR number, branch name, or batch date provided by the human):
- Use the hint directly. Query the specified PR(s) via `gh pr view` and `gh pr list`.

**Without a scope hint, same-session mode** (triggered from Protocol 90 or 91):
- Use the PRs processed during the current session. These are already known from the conversation context.

**Without a scope hint, on-demand mode** (fresh session, `/retrospective` with no argument):
- Default to recent PRs in the current repository:
  ```bash
  gh pr list --state all --limit 10 --json number,title,headRefName,baseRefName,mergedAt,createdAt,labels,reviews
  ```
- Focus on PRs merged or opened in the last 7 days. If no PRs meet this threshold, widen to 14 days or the last 5 closed PRs, whichever is smaller.

If no PRs can be found at all, report this clearly and close the retrospective gracefully — do not proceed.

---

## Step 2: Gather Data

### 2a. GitHub PR metadata

For each PR in scope, collect:

```bash
# PR metadata
gh pr view <number> --json number,title,headRefName,baseRefName,mergedAt,state,labels,reviews,comments,reviewDecision

# PR review comments (inline findings)
gh api repos/{owner}/{repo}/pulls/<number>/comments

# PR timeline events (label changes, base branch edits, re-requests)
gh api repos/{owner}/{repo}/issues/<number>/events
```

From this data, extract:

- **Review cycle count**: how many times a reviewer (automated or human) requested changes
- **Finding types**: labeling issues, wrong base branch, CHANGELOG conflicts, agent misbehavior signals visible in PR comments
- **Labels applied / missing**: were expected labels (`ready-for-human-review`, `needs-fixes`, `ready-for-regression`) applied correctly?
- **Merge conflicts**: did the PR require conflict resolution?
- **Automated reviewer findings**: CodeRabbit, Greptile, or other configured platforms (if visible in PR comments or reviews)

### 2b. Git history analysis

For each PR branch in scope:

```bash
# Commit history for the PR branch
gh api repos/{owner}/{repo}/pulls/<number>/commits

# Or using git directly if the branch is available locally
git log origin/<base-branch>..origin/<pr-branch> --oneline
```

From this data, extract:

- **Total commit count**
- **Fix-commit ratio**: commits with messages starting with `fix:`, `fixup!`, or similar correction indicators as a proportion of all commits
- **Review iteration count**: number of distinct pushes that followed a review comment or `needs-fixes` label

### 2c. Conversation context (same-session mode only)

When the retrospective is triggered in the same session as a completed batch or item run, analyze the conversation history for:

- **Manual interventions**: moments where the human had to correct the agent's direction mid-run
- **Human corrections**: instances where the agent made an error the human caught and fixed
- **Agent deviations from protocol**: explicit statements in the conversation that the agent did something unexpected or against protocol
- **Friction points surfaced verbally**: anything the human flagged as annoying, slow, or incorrect during the run

Conversation findings are often the highest-value source — weight them accordingly.

---

## Step 3: Synthesize Findings

Analyze all gathered data and produce a categorized list of improvement opportunities.

### 3a. Query existing backlog for related items

Before categorizing findings, query the configured issue tracker for existing open items that may overlap with what was discovered. This prevents duplicate issues and surfaces opportunities to expand existing backlog items instead.

Use the `issue_tracker.provider` from `.ai-dev-workflow.yaml` to determine the query method:

**`github_issues` or `github_projects`**:

```bash
# Fetch open issues with the workflow label
gh issue list --label "workflow" --state open --limit 50 --json number,title,body

# Also fetch recent open issues without label filter (catches unlabeled items)
gh issue list --state open --limit 100 --json number,title,body
```

**`linear`**: Use the Linear MCP tool to list open issues in the relevant team or project. See [`integrations/linear.md`](../integrations/linear.md) for setup details.

**`jira`**, **`clickup`**, **`notion`**: Use their respective MCP tools or APIs to fetch open backlog items (see integration guides in `docs/ai/development-workflow/integrations/` if available).

**`none`** or provider unavailable: Skip this substep and note in the presentation that no tracker check was performed.

For each issue retrieved, extract its title and a short description. After categorizing all findings in Step 3b below, match each finding against the retrieved items using these criteria (in priority order):

1. **Exact match**: The finding's affected file path or protocol name appears in the existing item's title or body
2. **Strong keyword overlap**: Three or more significant keywords (excluding stopwords like "the", "a", "is") appear in both the finding and the existing item title/body
3. **Root-cause category match**: The finding and existing item share the same categorization taxonomy label (e.g., both are `workflow-process`) and describe overlapping symptoms

When multiple existing items could match, prefer the most recently updated item. When no item meets at least one criterion, record `no_related_item`. When match confidence is ambiguous (one weak criterion only), present both the potential match and "No strong existing item found" and let the human decide in Step 5.

Record:

- `related_item`: issue number and title, if a match is found
- `no_related_item`: explicitly noted when no match is found

Carry this mapping into Step 4 (presentation) and Step 5 (action execution).

### 3b. Categorization taxonomy

Assign each opportunity exactly one category:

| Category | Display label | Description |
|---|---|---|
| `workflow-process` | Workflow & Process | Deviation from or friction in the defined workflow protocols (e.g., wrong base branch, skipped review step) |
| `agent-behavior` | Agent Behavior | Unexpected or incorrect agent action, model mischoice, or protocol misread |
| `configuration` | Configuration | Missing or incorrect repo/workflow configuration (e.g., labels, YAML files, `.gitignore`) |
| `documentation` | Documentation | Gap or inaccuracy in a protocol, spec, or guideline document |
| `code-quality` | Code Quality | Recurring reviewer findings that suggest a systemic pattern rather than a one-off issue |
| `tooling` | Tooling | External tool integration issue (e.g., CodeRabbit misconfiguration, `gh` CLI usage gap) |

### Severity signals

Assign each opportunity a severity level:

| Code | Display label | Description |
|---|---|---|
| `high` | High | The issue caused rework, required human intervention, or has high likelihood of recurring and significantly disrupting future runs |
| `medium` | Medium | The issue caused friction or delay but did not require human intervention; likely to recur without a fix |
| `low` | Low | The issue is a minor deviation or a one-off occurrence with low likelihood of recurring or causing meaningful disruption |

**Bias toward `high`** when an issue required direct human correction.

### Recommended action per opportunity

For each opportunity, recommend one of:

- **Address now** — suitable for changes the agent can self-assess as simple and safe to apply without a review loop (e.g., one-line config fix, missing label in a YAML file, a `.gitignore` entry)
- **Add to backlog** — suitable for anything requiring implementation planning, cross-file changes, or a review loop

The recommended action is a suggestion. The human makes the final choice.

### Graceful exit

If the gathered data does not surface any actionable improvement opportunities (e.g., the PR was clean on first attempt, no human corrections were needed, all labels applied correctly), report this clearly:

> No actionable improvement opportunities were found for the analyzed work. The run appears to have proceeded cleanly.

Then close the retrospective.

---

## Step 4: Present Findings

Present the categorized findings to the human in a structured format:

```markdown
## Retrospective Analysis

**Scope**: [PR number(s) or batch identifier]
**Data sources**: GitHub data + conversation context | GitHub data only

---

### Improvement Opportunities

#### 1. [Short title] — [Display label] | [Severity display label]

**Observed**: [What happened — specific, factual description]
**Impact**: [What it caused or could cause if unaddressed]
**Recommended action**: Address now | Add to backlog
**Related existing item**: #NNN — [title] | No existing backlog item found

---

#### 2. [Short title] — [Display label] | [Severity display label]
...
```

Then ask the human to choose an action for each opportunity:

> For each finding above, please choose: **Address now**, **Add to backlog**, or **Skip**.

Wait for the human's choices before executing any action.

---

## Step 5: Execute Actions

Execute each chosen action in the order the human specified (or in the order they were presented if no specific order was given).

### Address now

1. Assess whether the opportunity is truly simple enough to apply without a review loop.
   - If **yes**: apply the fix directly, commit, and push on the current or appropriate branch.
   - If **no**: inform the human that the fix is more complex than it appears and recommend "Add to backlog" instead. Explain why (e.g., "This change touches 4 files and would benefit from a proper review loop").
2. After applying a fix:
   - Commit with a descriptive message: `fix([scope]): [description]`
   - Push to the appropriate branch
   - Report what changed with a short diff or summary

**Constraints**:
- Do **not** open a new PR for "Address now" changes
- Do **not** run a review loop for "Address now" changes
- If the fix requires changes to multiple files, a schema migration, or introduces a new pattern, stop and recommend "Add to backlog" instead

### Add to backlog

First, check whether a related existing item was found in Step 3a for this finding.

**If a related existing item exists**: offer the human a choice before creating a new issue:

> Finding #N has a related existing item: **#NNN — [title]**.
> Would you like to:
> - **Expand existing**: add the new observation to the existing issue's body
> - **Create new**: create a separate issue (use when the scope is distinct enough to warrant tracking separately)

If the human chooses **Expand existing**, append the new observation to the existing issue body. Use the `issue_tracker.provider` from `.ai-dev-workflow.yaml` to determine the method:

**`github_issues` or `github_projects`**:

```bash
# Read current body, append new section via temp file to avoid shell quoting issues
TEMP_FILE=$(mktemp)
gh issue view <number> --json body -q '.body' > "$TEMP_FILE"
cat >> "$TEMP_FILE" <<'EOF'

---

## Additional observation from retrospective on [date]

[What was observed — specific, factual]

[Impact if unaddressed]
EOF

gh issue edit <number> --body-file "$TEMP_FILE"
rm -f "$TEMP_FILE"
```

**`linear`**: Use the Linear MCP tool to read the issue description, append the new observation section, and update the issue. See [`integrations/linear.md`](../integrations/linear.md) for setup details.

**`jira`**, **`clickup`**, **`notion`**: Use their respective MCP tools or APIs to read and update the issue body (see integration guides in `docs/ai/development-workflow/integrations/` if available).

**`none`** or provider unavailable: Fall back to **Create new** and note that the existing item could not be expanded programmatically.

Report the updated issue with its URL.

**If no related existing item exists** (or the human chose **Create new**), create a new issue using the configured tracker.

**`github_issues` or `github_projects`**:

```bash
gh issue create \
  --title "[Descriptive title of the improvement opportunity]" \
  --body "[Body — see format below]" \
  --label "workflow"
```

**`linear`**, **`jira`**, **`clickup`**, **`notion`**: Use the respective MCP tool or API to create a new issue with an equivalent title, body, and label/tag.

Issue body format:

```markdown
## Observed

[What was observed during the retrospective — specific, factual]

## Impact

[What it caused or could cause if unaddressed]

## Category

[Category display label] — [Severity display label]

## Source

Retrospective analysis of [PR number(s) or batch/session identifier] on [date]
```

Report the created issue with its URL.

**Constraints**:
- Do **not** run the full `00-add-backlog-item-protocol.md` flow — that would disrupt the retrospective with its own alignment conversation
- The issue body must contain enough context that someone picking it up later can understand what was observed without needing the original conversation

### Skip

Acknowledge and move on.

---

## Step 6: Close

After all opportunities have been acted on (or skipped), provide a confirmation summary:

```markdown
## Retrospective Complete

| # | Title | Category | Severity | Action taken |
|---|-------|----------|----------|--------------|
| 1 | [title] | [label] | [severity] | Fixed in commit `abc1234` / Issue #42 / Skipped |
| 2 | ... | ... | ... | ... |
```

The retrospective is now closed.
