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

**Downstream script-bug tracking prompt**: Were any template workflow script bugs
fixed in a downstream sync PR during this retrospective's cycle? If yes, treat the
bug as a finding and classify it as `contribute-upstream` in Step 3b so that Step 3e
automatically files exactly one upstream issue (labelled `workflow`) with a link to
the downstream fix commit. This prevents the same bug from shipping to future
downstream syncs without creating duplicate issues.

### 3b. Template cross-reference (runs when `template.repository` is configured; skipped otherwise)

**Subagent context note**: Step 3b uses `gh` CLI exclusively — it does not require MCP tools. When the retrospective agent is dispatched as a subagent (i.e., without an interactive system prompt that lists available MCP tools), it must still execute Step 3b if `template.repository` is configured. The agent must read `.ai-dev-workflow.yaml` directly from the filesystem (`cat .ai-dev-workflow.yaml` or equivalent) to obtain the `template.repository` value — do not rely on memory or assume the field is empty. Failure to read the YAML (e.g., file not found, parse error) is treated as `check-unavailable` with `check_status: warning` — mark all findings accordingly and continue.

Read `template.repository` from `.ai-dev-workflow.yaml`:

```bash
# Read template.repository from the config file (works without yq)
# Scans only the template: block; stops at the next top-level key to avoid
# picking up unrelated repository: keys from other YAML blocks (e.g. vcs:).
awk '
/^[[:space:]]*template:[[:space:]]*$/ { in_template=1; next }
in_template && /^[^[:space:]]/ { in_template=0 }
in_template && /^[[:space:]]*repository:[[:space:]]*/ {
  val=$0; sub(/^[[:space:]]*repository:[[:space:]]*/, "", val); gsub(/"/, "", val); print val; exit
}
' .ai-dev-workflow.yaml
# Or use yq if available:
# yq '.template.repository' .ai-dev-workflow.yaml
```

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

| Bucket                | Label                         | Condition                                                                                                                                                                                                                                                                                    |
| --------------------- | ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `already-tracked`     | Already in template backlog   | Finding matches an **open** template issue (see matching heuristic below)                                                                                                                                                                                                                    |
| `already-fixed`       | Already fixed upstream        | Finding matches a **closed** template issue AND the fix version is newer than `template.last_synced_version`                                                                                                                                                                                 |
| `contribute-upstream` | Contribute upstream candidate | Finding does not match any template issue, matches a closed issue but version comparison is inconclusive, or matches a closed issue whose fix version is older than or equal to `template.last_synced_version` (fix already synced — may be a different issue or an incomplete upstream fix) |
| `check-unavailable`   | Template check unavailable    | Template repository was unreachable (warning) or malformed (error); classification could not be performed                                                                                                                                                                                    |

**Matching heuristic** (apply in priority order — first criterion that matches wins):

1. **Exact path match**: The finding's affected file path appears verbatim in the template issue's title or body.
2. **Keyword overlap**: Three or more significant keywords (excluding stopwords like "the", "a", "is") appear in both the finding description and the issue title/body.
3. **Category label match** _(second-pass only — apply after Step 3c taxonomy assignment is complete)_: The finding and the template issue share the same categorization taxonomy label (e.g., both are `workflow-process`) and describe overlapping symptoms. Skip this criterion on the first pass if taxonomy labels have not yet been assigned; re-run matching after Step 3c completes.

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

### 3b Gate: mandatory completion check before classifying findings

Before proceeding to Step 3c (classification) and Step 4, verify that Step 3b was completed when it was required:

- Read `template.repository` from `.ai-dev-workflow.yaml` using the filesystem command shown in Step 3b (do not rely on memory).
- **If `template.repository` is set (non-empty)** and Step 3b was skipped or not completed during this session: stop here, return to Step 3b, and complete it before classifying any findings. Step 3b handles the well-formed case (full cross-reference), the malformed case (`check-unavailable`), and the subagent / YAML-unreadable case (`check-unavailable` with `check_status: warning`) — the gate is satisfied for all three outcomes. The gate fires only when Step 3b was entirely omitted.
- **If `template.repository` is absent or empty**: the gate is satisfied — proceed to Step 3c.

**Subagent-specific guidance**: When this gate runs in a subagent context and Step 3b was skipped because the agent assumed `template.repository` was empty without reading the YAML, the gate is **not** satisfied. The agent must read the YAML (even in a subagent shell with no MCP tools), run Step 3b using `gh` CLI, and return. If the YAML is unreadable, mark all findings `check-unavailable` — that satisfies the gate and allows the retrospective to continue.

This gate prevents premature classification of findings (e.g., marking a finding as "Add to backlog" instead of `already-tracked` or `already-fixed`) when the template cross-reference data would have changed the outcome.

### 3c. Categorization taxonomy

Assign each opportunity exactly one category:

| Category           | Display label      | Description                                                                                                 |
| ------------------ | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `workflow-process` | Workflow & Process | Deviation from or friction in the defined workflow protocols (e.g., wrong base branch, skipped review step) |
| `agent-behavior`   | Agent Behavior     | Unexpected or incorrect agent action, model mischoice, or protocol misread                                  |
| `configuration`    | Configuration      | Missing or incorrect repo/workflow configuration (e.g., labels, YAML files, `.gitignore`)                   |
| `documentation`    | Documentation      | Gap or inaccuracy in a protocol, spec, or guideline document                                                |
| `code-quality`     | Code Quality       | Recurring reviewer findings that suggest a systemic pattern rather than a one-off issue                     |
| `tooling`          | Tooling            | External tool integration issue (e.g., CodeRabbit misconfiguration, `gh` CLI usage gap)                     |

### 3d. Populate Metrics Block

After completing Steps 3a–3c (backlog query, template cross-reference, and categorization), fill in the required metrics block for this retrospective.

**Required fields**:

| Field                                       | Definition                                                                                                                                                                                                                                    | Source                                            |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **Batch identifier**                        | The PR numbers or batch date used as the scope in Step 1 (e.g., "PRs #301–#315" or "2026-04-24")                                                                                                                                              | Step 1 scope resolution                           |
| **Human interventions count**               | Number of moments where the human had to correct the agent's direction mid-run (not counting routine choices like approving a retrospective output)                                                                                           | Step 2c conversation context, or PR event history |
| **Step 5.2 violations count**               | Number of instances where the automated reviewer found a Step 5.2 (PR-readiness) violation during the batch                                                                                                                                   | PR comments and review cycles                     |
| **Automated-reviewer retry loops count**    | Number of additional `pr-review-loop.sh` iterations beyond the first pass (i.e., how many re-runs were needed after findings were addressed)                                                                                                  | PR comment timestamps and review rounds           |
| **Escalations count**                       | Number of items that escalated past the automated reviewer retry limit (source: PR labels or conversation notes indicating escalation)                                                                                                        | PR labels, conversation notes                     |
| **Prior action item recurrence assessment** | For each open action item from prior retrospectives whose targeted failure mode was observable in this batch, record whether it "recurred" or "did not recur". If no prior action items are relevant to this batch, record "none applicable". | Comparison with prior retrospective output        |

**Rules**:

- **"Unavailable" is a valid value**: if a field cannot be reliably determined from available GitHub data or conversation context, record `unavailable` — not blank and not a guess (BR-7).
- **Zero is a valid value**: a batch that produced zero human interventions is a meaningful data point (BR-1).
- This metrics block is part of the retrospective output presented in Step 4 alongside improvement opportunities.

### Severity signals

Assign each opportunity a severity level:

| Code     | Display label | Description                                                                                                                        |
| -------- | ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `high`   | High          | The issue caused rework, required human intervention, or has high likelihood of recurring and significantly disrupting future runs |
| `medium` | Medium        | The issue caused friction or delay but did not require human intervention; likely to recur without a fix                           |
| `low`    | Low           | The issue is a minor deviation or a one-off occurrence with low likelihood of recurring or causing meaningful disruption           |

**Bias toward `high`** when an issue required direct human correction.

### Recommended action per opportunity

For each opportunity, recommend one of:

- **Address now** — suitable for changes the agent can self-assess as simple and safe to apply without a review loop (e.g., one-line config fix, missing label in a YAML file, a `.gitignore` entry)
- **Add to backlog** — suitable for anything requiring implementation planning, cross-file changes, or a review loop

The recommended action is a suggestion. The human makes the final choice.

**Note**: Do **not** recommend "Contribute upstream" as an action here. Findings classified `contribute-upstream` by Step 3b are filed automatically in Step 3e — no human opt-in is required. If `template.repository` is not configured, the `contribute-upstream` classification is not produced and this path does not apply.

### 3e. Mandatory auto-file for `contribute-upstream` findings

**This step runs automatically — no human opt-in required.**

For every finding classified as `contribute-upstream` in Step 3b, create a GitHub issue on `template.repository` before presenting findings to the human. This step applies only when `template.repository` is configured (non-empty) and well-formed; skip silently when `template.repository` is absent or empty (Step 3b did not run). Findings classified `check-unavailable` in Step 3b are excluded — do not attempt to file those.

**Precondition**: `template.repository` must be set, non-empty, and well-formed (`owner/repo` format) before auto-filing. If the repository is unreachable at filing time (network error, auth failure), skip auto-filing for affected findings and note the failure inline in Step 4 output. Do not block the retrospective on a network failure.

**For each `contribute-upstream` finding**, run:

```bash
gh issue create \
  --repo <template.repository> \
  --title "<finding title>" \
  --label "workflow" \
  --body "<issue body — see format below>"
```

Issue body format:

```markdown
## Finding

[Finding description — root cause, impact, and proposed fix]

## Downstream context

Project: [repo name or anonymised slug, with human consent]
Batch/date: [batch identifier or date from Step 1 scope]

## Proposed improvement

[Proposed fix or change to the template protocol/tooling]
```

- Use the `workflow` label. If it does not exist on the template repo, create it first:

  ```bash
  gh label create "workflow" --repo <template.repository> --color "0075ca" --description "Workflow improvement"
  ```

- Record the created issue URL for each filing. Print all filed URLs in the Step 4 output alongside the `contribute-upstream` label so the human has direct links for follow-up.
- If `gh issue create` fails (e.g., auth error, label creation failure), record the failure inline in Step 4 rather than blocking the retrospective. The human can follow up manually using the printed command.
- Do **not** automatically close any backlog items that may be created later in Step 5, and do not auto-close pre-existing downstream items identified in Step 3a — the upstream issue is additive visibility, not a replacement for local backlog tracking.

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
_(Only include this field if Step 3b was executed — i.e., if `template.repository` was configured)_
**Upstream issue filed**: <url> | filing failed: <reason>
_(Only include this field for `contribute-upstream` findings; show the URL when Step 3e succeeded, or "filing failed: &lt;reason&gt;" when it did not)_

---

#### 2. [Short title] — [Display label] | [Severity display label]

...

---

### Metrics Block

| Field                                   | Value                                      |
| --------------------------------------- | ------------------------------------------ |
| Batch identifier                        | [PR numbers or batch date]                 |
| Human interventions count               | [count or `unavailable`]                   |
| Step 5.2 violations count               | [count or `unavailable`]                   |
| Automated-reviewer retry loops count    | [count or `unavailable`]                   |
| Escalations count                       | [count or `unavailable`]                   |
| Prior action item recurrence assessment | [per-item assessment or "none applicable"] |
```

Then ask the human to choose an action for each opportunity:

> For each finding above, please choose: **Address now**, **Add to backlog**, or **Skip**.
> _(Findings classified `contribute-upstream` have already been filed as upstream issues in Step 3e — no additional action is needed unless you want to expand the filed issue with more context.)_

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
>
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

**Upstream issues for `contribute-upstream` findings are filed automatically in Step 3e — no separate action is needed here.** The Step 4 output includes the filed issue URL for each finding.

The only remaining human-driven action in this path is optional: if the human wants to add more context to a filed upstream issue (e.g., attach a downstream PR link, adjust the proposed fix, or confirm consent to name the downstream repository), do so by editing the upstream issue:

```bash
gh issue edit <upstream-issue-number> --repo <template.repository> --body-file <updated-body-file>
```

If Step 3e filing failed for a finding (noted as "filing failed: &lt;reason&gt;" in Step 4 output), attempt the filing now by running the `gh issue create` command from Step 3e — substituting `<template.repository>` with the actual value from `.ai-dev-workflow.yaml`, `<finding title>` with the finding's short title, and the body with the body format from Step 3e populated with the finding's details. Report the result to the human.

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

| #   | Title   | Category | Severity   | Action taken                                    |
| --- | ------- | -------- | ---------- | ----------------------------------------------- |
| 1   | [title] | [label]  | [severity] | Fixed in commit `abc1234` / Issue #42 / Skipped |
| 2   | ...     | ...      | ...        | ...                                             |

**Metrics block appended and committed to `docs/workflow/retro-metrics.md` on `develop`.**
```

The retrospective is now closed.

---

## See Also

For periodic verification of whether prior improvement action items are working, run the meta-retrospective protocol: `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md`. Recommended cadence: every 5 batches. Can be triggered at any time.

Note: metrics blocks written before feature #458 (structured retro metrics) was deployed will naturally be absent from the log. The meta-retrospective gracefully handles a log with fewer entries than its analysis window by analyzing whatever is available.
