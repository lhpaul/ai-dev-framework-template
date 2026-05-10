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

**`github_issues`**:

```bash
# Fetch open issues with the workflow label
gh issue list --label "workflow" --state open --limit 50 --json number,title,body

# Also fetch recent open issues without label filter (catches unlabeled items)
gh issue list --state open --limit 100 --json number,title,body
```

**`github_projects`**:

```bash
# Fetch items from GitHub Project v2
gh project item-list <PROJECT_NUMBER> --owner <OWNER> --format json --limit 50
```

Where `<PROJECT_NUMBER>` is the project number (find it via `gh project list`) and `<OWNER>` is the user or organization owning the project. This includes issues, PRs, and draft issues tracked in the project.

**`linear`**: Use the Linear MCP tool to list open issues in the relevant team or project. See [`integrations/linear.md`](../integrations/linear.md) for setup details.

**`jira`**, **`clickup`**, **`notion`**: Use their respective MCP tools or APIs to fetch open backlog items (see integration guides in `docs/workflow/development-workflow/integrations/` if available).

**`none`** or provider unavailable: Skip this substep and note in the presentation that no tracker check was performed.

For each issue retrieved, extract its title and a short description. After categorizing all findings in Step 3c below, match each finding against the retrieved items using these criteria (in priority order):

1. **Exact match**: The finding's affected file path or protocol name appears in the existing item's title or body
2. **Strong keyword overlap**: Three or more significant keywords (excluding stopwords like "the", "a", "is") appear in both the finding and the existing item title/body
3. **Root-cause category match**: The finding and existing item share the same categorization taxonomy label (e.g., both are `workflow-process`) and describe overlapping symptoms

When multiple existing items could match, prefer the most recently updated item. When no item meets at least one criterion, record `no_related_item`. When match confidence is ambiguous (one weak criterion only), present both the potential match and "No strong existing item found" and let the human decide in Step 5.

Record:

- `related_item`: issue number and title, if a match is found
- `no_related_item`: explicitly noted when no match is found

Carry this mapping into Step 4 (presentation) and Step 5 (action execution).

### 3b. Template cross-reference (runs when `template.repository` is configured; skipped otherwise)

Read `template.repository` from `.ai-dev-workflow.yaml`.

- **If absent or empty**: skip this substep silently. Do not mention it in output.
- **If present but malformed** (not `owner/repo` format): mark all findings as `check-unavailable` with `check_status: error` and continue. Report the error inline with each finding in Step 4 output.
- **If well-formed**: proceed with the queries and classification below.

**Query the template repository's issues:**

```bash
# Open issues (potential "already tracked" matches)
gh issue list --repo <owner/repo> --state open --limit 200 --json number,title,body,labels,updatedAt,url

# Closed issues (potential "already fixed" matches)
gh issue list --repo <owner/repo> --state closed --limit 500 --json number,title,body,labels,milestone,closedAt,updatedAt,url

# Template CHANGELOG (for fix-version mapping by issue reference)
gh api repos/<owner>/<repo>/contents/CHANGELOG.md --jq '.content' | base64 --decode > /tmp/template-CHANGELOG.md

# Parse CHANGELOG to build issue → version map (follows Keep a Changelog format):
# 1. Identify version section headings — lines matching `## [x.y.z]` or `## x.y.z` (ignore `## [Unreleased]`)
# 2. Within each version block, extract all issue references matching `#NNN` (where NNN is one or more digits)
# 3. Map each issue number to the version of its enclosing section (e.g., #123 → 1.2.3)
# 4. Use this map for all "already-fixed" version comparisons below
# Example entry: { "123": "1.2.3", "456": "1.1.0" }
```

If the repository is unreachable (network error, auth failure, or `gh` reports the repo as not found): mark all findings as `check-unavailable` with `check_status: warning` and continue. Do not block Step 4 on a network failure.

**Classify each finding into exactly one bucket:**

| Bucket | Label | Condition |
|---|---|---|
| `already-tracked` | Already in template backlog | Finding matches an **open** template issue (see matching heuristic below) |
| `already-fixed` | Already fixed upstream | Finding matches a **closed** template issue AND the fix version is newer than `template.last_synced_version` |
| `contribute-upstream` | Contribute upstream candidate | Finding does not match any template issue, matches a closed issue but version comparison is inconclusive, or matches a closed issue whose fix version is older than or equal to `template.last_synced_version` (fix already synced — may be a different issue or an incomplete upstream fix) |
| `check-unavailable` | Template check unavailable | Template repository was unreachable (warning) or malformed (error); classification could not be performed |

**Matching heuristic** (apply in priority order — first criterion that matches wins):

1. **Exact path match**: The finding's affected file path appears verbatim in the template issue's title or body.
2. **Keyword overlap**: Three or more significant keywords (excluding stopwords like "the", "a", "is") appear in both the finding description and the issue title/body.
3. **Category label match** *(second-pass only — apply after Step 3c taxonomy assignment is complete)*: The finding and the template issue share the same categorization taxonomy label (e.g., both are `workflow-process`) and describe overlapping symptoms. Skip this criterion on the first pass if taxonomy labels have not yet been assigned; re-run matching after Step 3c completes.

When a finding matches multiple template issues, prefer the most recently updated open issue (for `already-tracked`) or the most recently updated closed issue (for `already-fixed`) using the `updatedAt` field.

**Version comparison fallbacks:**

- If `template.last_synced_version` is absent or empty: a closed-issue match falls back to `contribute-upstream` with a note: "Template version not recorded — run sync-template to capture last-synced version."
- If the closed issue has no parseable fix version from CHANGELOG issue-reference mapping (fallback order: CHANGELOG `#NNN` reference → milestone name → `closedAt` mapped to nearest release tag): fall back to `contribute-upstream` with a note: "Fix version unknown."

**Carry classification into Step 4 output:**

Show the bucket label inline with each finding in the presentation. For `already-tracked` findings, also include:
- The matching template issue number and title
- The suggestion: "Consider **Skip** (already tracked upstream) or **Expand existing** (add downstream context to the template issue) as alternatives to creating a new upstream issue."

For `already-fixed` findings, also include:
- The matching template issue number and title
- The fix version (if determinable) and the downstream's `last_synced_version`

For `contribute-upstream` findings, no extra annotation is required beyond the label.

For `check-unavailable` findings, also include:
- The reason classification was unavailable (e.g., "Template repository unreachable" or "Malformed template repository configuration")
- The suggestion: "Fix configuration or network access and re-run the retrospective to enable template cross-reference."

### 3b Gate: mandatory completion check before Step 4

Before proceeding to Step 4, verify that Step 3b was completed when it was required:

- Read `template.repository` from `.ai-dev-workflow.yaml`.
- **If `template.repository` is set (non-empty and well-formed)** and Step 3b was skipped or not completed during this session: stop here, return to Step 3b, and complete it before classifying any findings.
- **If `template.repository` is absent or empty**: the gate is satisfied — proceed to Step 3c.

This gate prevents premature classification of findings (e.g., marking a finding as "Add to backlog" instead of `already-tracked` or `already-fixed`) when the template cross-reference data would have changed the outcome.

### 3c. Categorization taxonomy

Assign each opportunity exactly one category:

| Category | Display label | Description |
|---|---|---|
| `workflow-process` | Workflow & Process | Deviation from or friction in the defined workflow protocols (e.g., wrong base branch, skipped review step) |
| `agent-behavior` | Agent Behavior | Unexpected or incorrect agent action, model mischoice, or protocol misread |
| `configuration` | Configuration | Missing or incorrect repo/workflow configuration (e.g., labels, YAML files, `.gitignore`) |
| `documentation` | Documentation | Gap or inaccuracy in a protocol, spec, or guideline document |
| `code-quality` | Code Quality | Recurring reviewer findings that suggest a systemic pattern rather than a one-off issue |
| `tooling` | Tooling | External tool integration issue (e.g., CodeRabbit misconfiguration, `gh` CLI usage gap) |

### 3d. Populate Metrics Block

After completing Steps 3a–3c (backlog query, template cross-reference, and categorization), fill in the required metrics block for this retrospective.

**Required fields**:

| Field | Definition | Source |
|---|---|---|
| **Batch identifier** | The PR numbers or batch date used as the scope in Step 1 (e.g., "PRs #301–#315" or "2026-04-24") | Step 1 scope resolution |
| **Human interventions count** | Number of moments where the human had to correct the agent's direction mid-run (not counting routine choices like approving a retrospective output) | Step 2c conversation context, or PR event history |
| **Step 5.2 violations count** | Number of instances where the automated reviewer found a Step 5.2 (PR-readiness) violation during the batch | PR comments and review cycles |
| **Automated-reviewer retry loops count** | Number of additional `pr-review-loop.sh` iterations beyond the first pass (i.e., how many re-runs were needed after findings were addressed) | PR comment timestamps and review rounds |
| **Escalations count** | Number of items that escalated past the automated reviewer retry limit (source: PR labels or conversation notes indicating escalation) | PR labels, conversation notes |
| **Prior action item recurrence assessment** | For each open action item from prior retrospectives whose targeted failure mode was observable in this batch, record whether it "recurred" or "did not recur". If no prior action items are relevant to this batch, record "none applicable". | Comparison with prior retrospective output |

**Rules**:

- **"Unavailable" is a valid value**: if a field cannot be reliably determined from available GitHub data or conversation context, record `unavailable` — not blank and not a guess (BR-7).
- **Zero is a valid value**: a batch that produced zero human interventions is a meaningful data point (BR-1).
- This metrics block is part of the retrospective output presented in Step 4 alongside improvement opportunities.

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
- **Contribute upstream** — suitable only for **workflow, tooling, or template-process** insights that would benefit every downstream consumer of this template (not product/domain/business retrospectives)

The recommended action is a suggestion. The human makes the final choice.

### Graceful exit

If the gathered data does not surface any actionable improvement opportunities (e.g., the PR was clean on first attempt, no human corrections were needed, all labels applied correctly), report this clearly:

> No actionable improvement opportunities were found for the analyzed work. The run appears to have proceeded cleanly.

Even when there are no improvement opportunities, still populate the metrics block (Step 3d) and present it to the human in Step 4. After the human confirms the output, proceed to Step 6 to append the metrics row to `docs/workflow/retro-metrics.md`. A clean batch is a valid and useful data point (BR-1, BR-2).

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
**Template cross-reference**: `already-tracked` | `already-fixed` | `contribute-upstream` | `check-unavailable`
  *(Only include this field if Step 3b was executed — i.e., if `template.repository` was configured)*

---

#### 2. [Short title] — [Display label] | [Severity display label]
...

---

### Metrics Block

| Field | Value |
|---|---|
| Batch identifier | [PR numbers or batch date] |
| Human interventions count | [count or `unavailable`] |
| Step 5.2 violations count | [count or `unavailable`] |
| Automated-reviewer retry loops count | [count or `unavailable`] |
| Escalations count | [count or `unavailable`] |
| Prior action item recurrence assessment | [per-item assessment or "none applicable"] |
```

Then ask the human to choose an action for each opportunity:

> For each finding above, please choose: **Address now**, **Add to backlog**, **Contribute upstream** (workflow-only insights to the template repository), or **Skip**.

Wait for the human's choices before executing any action.

---

## Step 5: Execute Actions

Execute each chosen action in the order the human specified (or in the order they were presented if no specific order was given).

### Address now

1. Assess whether the opportunity is truly simple enough to address immediately.
   - If **yes**: apply the fix on a dedicated workflow branch (e.g., `fix/[slug]`) and open a PR targeting `develop`.
   - If **no**: inform the human that the fix is more complex than it appears and recommend "Add to backlog" instead. Explain why (e.g., "This change touches 4 files and would benefit from a proper review loop").
2. After applying a fix:
   - Commit with a descriptive message: `fix([scope]): [description]`
   - Push the workflow branch and open a PR through the repository's normal review/CI path
   - Report what changed with a short diff or summary

**Constraints**:
- Do **not** push retrospective code changes directly to shared branches (`develop`/`main`)
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

**`jira`**, **`clickup`**, **`notion`**: Use their respective MCP tools or APIs to read and update the issue body (see integration guides in `docs/workflow/development-workflow/integrations/` if available).

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

### Contribute upstream

Only when the human explicitly chose **Contribute upstream** for a finding that qualifies as **workflow/tooling/template-process** (per the scope rules above). This path is **opt-in** and must never run without an explicit per-finding choice.

1. Confirm the default upstream repository and issue tracker with the human when ambiguous (typically the public template repository this project was derived from).
2. Create a new issue on the **template** repository using `gh issue create` (or the tracker’s equivalent), with label **`template-feedback`** (create the label first if it does not exist), and a body that includes:
   - The retrospective insight (Observed / Impact / Proposed improvement), anonymized if needed
   - A link or name of the downstream repository that produced the insight (only with human consent)
   - Reference to the original retrospective scope (PR numbers, batch id, or date)

3. Do **not** close the downstream retrospective item automatically — the upstream issue is additive visibility, not a replacement for local backlog tracking.

### Skip

Acknowledge and move on.

---

## Step 6: Close

After all opportunities have been acted on (or skipped):

1. **Append the finalized metrics block to `docs/workflow/retro-metrics.md`**. If the file does not exist, create it with the column headers before appending. Add one new table row using the values from the metrics block presented in Step 4 (after any human corrections):

   ```markdown
   | [Batch identifier] | [Human interventions count] | [Step 5.2 violations count] | [Automated-reviewer retry loops count] | [Escalations count] | [Prior action item recurrence assessment] |
   ```

   Column order must match the headers in `docs/workflow/retro-metrics.md`:
   `Batch Identifier | Human Interventions Count | Step 5.2 Violations Count | Automated-Reviewer Retry Loops Count | Escalations Count | Prior Action Item Recurrence Assessment`

2. **Commit and push `docs/workflow/retro-metrics.md` immediately** — before the session ends or any branch switch occurs. This is mandatory; an uncommitted metrics row is silently lost when branches are switched. The commit goes directly to `develop` (this is an append-only log file, not feature work):

   ```bash
   git add docs/workflow/retro-metrics.md
   git commit -m "docs(retro): add [Batch identifier] metrics row"
   git push origin develop
   ```

   If `develop` is not the currently checked-out branch (e.g., the retrospective was run from a feature branch), switch to `develop` first, cherry-pick or re-apply the append, then commit and push. Do **not** leave the metrics row uncommitted while switching branches.

3. **Provide a confirmation summary**:

```markdown
## Retrospective Complete

| # | Title | Category | Severity | Action taken |
|---|-------|----------|----------|--------------|
| 1 | [title] | [label] | [severity] | Fixed in commit `abc1234` / Issue #42 / Skipped |
| 2 | ... | ... | ... | ... |

**Metrics block appended and committed to `docs/workflow/retro-metrics.md` on `develop`.**
```

The retrospective is now closed.

---

## See Also

For periodic verification of whether prior improvement action items are working, run the meta-retrospective protocol: `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`. Recommended cadence: every 5 batches. Can be triggered at any time.

Note: metrics blocks written before feature #458 (structured retro metrics) was deployed will naturally be absent from the log. The meta-retrospective gracefully handles a log with fewer entries than its analysis window by analyzing whatever is available.
