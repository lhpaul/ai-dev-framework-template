# Retrospective Protocol — Spec

**Depends on**: <!-- None -->

---

## Guiding principle (important)

This stage is intentionally **product-focused**:

- Write **user-facing behavior**, permissions, UX rules, and acceptance criteria.
- Avoid prescribing **implementation details** (database tables/columns, specific endpoints, file paths, class names, or migration design). Those belong in the **Implementation Plan** stage.
- If a technical constraint matters to the product (e.g., "an agent may belong to multiple broker companies"), express it as a **product requirement** without naming tables.

## Overview

This feature adds a retrospective analysis capability to the AI development workflow. After completing a batch or individual item, the agent analyzes the work that was done, identifies process improvement opportunities, presents them to the human, and takes the action the human chooses for each. The retrospective is always suggested at natural completion points — never forced — and works whether or not conversation context is available.

---

## Use Cases

### Use Case 1: On-Demand Retrospective (Fresh Session)

**Actor**: Developer (human) invoking `/retrospective` in a new session without prior conversation history about the completed work
**Preconditions**: One or more PRs have been opened or merged recently in the repository

**Steps**:
1. The developer invokes `/retrospective` (optionally with a scope hint, e.g., a PR number, branch name, or batch date)
2. The agent queries GitHub for PR metadata: review cycle count, finding types (labeling issues, wrong base branch, CHANGELOG conflicts, agent misbehavior signals visible in PR comments), labels applied/missing, and merge conflicts
3. The agent analyzes git history for the relevant PRs: commit patterns, fix-commit ratio, and review iteration count
4. The agent synthesizes findings into a categorized list of improvement opportunities (see Business Rules: Categorization)
5. The agent presents the opportunities to the human with a recommended action for each
6. For each opportunity, the human chooses: **Address now** or **Add to backlog**
7. The agent executes the chosen action for each opportunity (see Use Case 3 and 4)
8. The agent confirms what was done and closes the retrospective

**Postconditions**: Each improvement opportunity has either been addressed in the current session or added as a backlog issue

**Information shown**:
- Categorized improvement opportunities, each with: description, category label, severity signal, and recommended action
- After action execution: confirmation of what was done (fix applied or issue created with link)

**Actions available**:
- Choose "Address now" for a given opportunity
- Choose "Add to backlog" for a given opportunity
- Skip an opportunity (take no action)

**Considerations**:
- If no scope hint is provided, the agent uses recent PRs from the current repository as the default scope
- If GitHub data is insufficient to surface meaningful findings, the agent says so and closes gracefully
- The agent does not make any changes or create any issues without the human's explicit choice

---

### Use Case 2: End-of-Batch / End-of-Item Retrospective (Same Session)

**Actor**: Portfolio Orchestrator (protocol 90) or Work Item Runner (protocol 91) suggesting a retrospective at the end of a run, with conversation context available
**Preconditions**: At least one PR was processed in the current session

**Steps**:
1. After presenting the batch or item summary, the agent suggests running a retrospective: *"Would you like to run a retrospective on this session's work?"*
2. If the human agrees, the agent runs the retrospective
3. In addition to GitHub data (as in Use Case 1), the agent also analyzes the conversation history from the current session: manual interventions, human corrections, agent deviations from protocol, and friction points that were surfaced verbally
4. The agent synthesizes all findings (GitHub + conversation) into a categorized list of improvement opportunities
5. The agent presents the opportunities to the human with a recommended action for each
6. For each opportunity, the human chooses: **Address now** or **Add to backlog**
7. The agent executes the chosen action for each opportunity
8. The agent confirms what was done and closes the retrospective

**Postconditions**: Each improvement opportunity has either been addressed in the current session or added as a backlog issue

**Information shown**:
- Same as Use Case 1, with additional findings sourced from conversation context
- A note indicating whether findings came from GitHub data only or from both GitHub and conversation context

**Actions available**:
- Same as Use Case 1

**Considerations**:
- The agent suggests a retrospective only once per session at the end of a batch/item run
- In protocol 91 (Work Item Runner), the suggestion is made only when the item was run standalone (not dispatched by a batch orchestrator). When `BATCH_CONTEXT=true`, the suggestion is suppressed to avoid double-triggering (the batch orchestrator handles it)
- In protocol 90 (Portfolio Orchestrator), the suggestion is always made after the batch summary
- Conversation context is the richest source of findings; GitHub data alone is the fallback

---

### Use Case 3: Address Now

**Actor**: Agent (on behalf of human who chose "Address now" for an opportunity)
**Preconditions**: The human has chosen "Address now" for a specific improvement opportunity; the opportunity has been assessed as simple enough to not require its own review loop

**Steps**:
1. The agent applies the fix directly in the current session (e.g., corrects a configuration file, updates a protocol line, fixes a `.gitignore` entry)
2. The agent commits and pushes the change on the current or appropriate branch
3. The agent reports completion with a diff or summary of what changed

**Postconditions**: The fix is committed and pushed; no new PR or review loop is opened

**Information shown**:
- Summary of the change made
- Confirmation that it was committed and pushed

**Actions available**:
- None after confirmation (the opportunity is closed)

**Considerations**:
- "Address now" is only valid for changes the agent can self-assess as simple (e.g., a one-line config fix, a missing label in a YAML file). The agent uses its own judgment to determine this — no fixed criteria are enumerated
- If the agent determines that an opportunity is too complex for "Address now", it should recommend "Add to backlog" instead and explain why
- The agent must not open a new PR or run a review loop for "Address now" changes; those belong in backlog items

---

### Use Case 4: Add to Backlog

**Actor**: Agent (on behalf of human who chose "Add to backlog" for an opportunity)
**Preconditions**: The human has chosen "Add to backlog" for a specific improvement opportunity

**Steps**:
1. The agent creates a GitHub issue directly using `gh issue create` with a descriptive title, a body that describes the problem and the improvement opportunity, and the appropriate labels
2. The agent reports the created issue with its URL

**Postconditions**: A GitHub issue exists representing the improvement opportunity

**Information shown**:
- Issue title and URL

**Actions available**:
- None after confirmation (the opportunity is closed)

**Considerations**:
- The issue creation is lightweight and direct — it does not go through the full `00-add-backlog-item-protocol.md` flow (which would disrupt the retrospective with its own alignment conversation)
- The issue body should include enough context that someone picking it up later can understand what was observed and why it matters, without needing the original conversation

---

## Business Rules

- The retrospective is **always opt-in** — it is suggested at natural completion points but never auto-triggered without human consent
- The retrospective operates in two modes:
  - **With conversation context** (preferred): analyzes both GitHub data and the current session's conversation history
  - **Without conversation context** (fallback): analyzes GitHub data only (PR metadata, git history, PR comments)
- **Categorization taxonomy** — each improvement opportunity is assigned one of the following categories:

  | Category | Description |
  |---|---|
  | `workflow-process` | Deviation from or friction in the defined workflow protocols (e.g., wrong base branch, skipped review step) |
  | `agent-behavior` | Unexpected or incorrect agent action, model mischoice, or protocol misread |
  | `configuration` | Missing or incorrect repo/workflow configuration (e.g., labels, YAML files, `.gitignore`) |
  | `documentation` | Gap or inaccuracy in a protocol, spec, or guideline document |
  | `code-quality` | Recurring reviewer findings that suggest a systemic pattern rather than a one-off issue |
  | `tooling` | External tool integration issue (e.g., CodeRabbit misconfiguration, `gh` CLI usage gap) |

- Each opportunity is presented with its category, a short description, a severity signal (High / Medium / Low), and a recommended action (Address now / Add to backlog)
- Severity signals are the agent's best-effort assessment based on frequency, impact, and whether the issue caused rework or human intervention
- **"Address now"** is reserved for changes the agent can self-assess as simple and safe to apply without a review loop; the agent uses its own judgment
- **"Add to backlog"** issue creation uses `gh issue create` directly — not the full `00-add-backlog-item-protocol.md` flow
- The human may skip any individual opportunity (take no action); the agent moves on
- The retrospective scope is limited to work from the current session or the PRs specified in the scope hint — no cross-session trend analysis
- No persistent state is required or maintained between sessions

---

## Delivery

The retrospective capability is delivered across all three platforms following existing patterns:

- **New protocol**: `docs/ai/development-workflow/protocols/06-retrospective-protocol.md`
- **Claude Code**: a `retrospective` agent / `/retrospective` command following existing agent patterns
- **Cursor**: a `/retrospective` subagent under `.cursor/agents/` following existing Cursor agent patterns
- **Codex**: a `workflow-retrospective` skill under `.codex/skills/` following existing Codex skill patterns

Integration points (suggestion, not auto-trigger) are added to:
- **Protocol 90, Step 6** (after batch summary): always suggest a retrospective
- **Protocol 91** (after item summary, before terminal handoff): suggest only when `BATCH_CONTEXT != true`

---

## Acceptance Criteria

- [ ] A developer can invoke `/retrospective` in a fresh session and receive a categorized list of improvement opportunities derived from GitHub PR data for recent work in the repository
- [ ] Each improvement opportunity is labeled with its category (from the taxonomy), severity signal, and recommended action
- [ ] The developer can choose "Address now", "Add to backlog", or skip for each opportunity
- [ ] When "Address now" is chosen for a simple fix, the agent applies the fix, commits, and pushes without opening a new PR or running a review loop
- [ ] When "Add to backlog" is chosen, the agent creates a GitHub issue via `gh issue create` with a descriptive title and body, and returns the issue URL
- [ ] When invoked in the same session as a completed batch/item run, the retrospective also surfaces findings from the conversation history (manual interventions, human corrections, agent deviations)
- [ ] Protocol 90 (batch orchestrator) suggests a retrospective after the Step 6 batch summary
- [ ] Protocol 91 (work item runner) suggests a retrospective after the item summary only when `BATCH_CONTEXT != true`
- [ ] The `/retrospective` command/skill is available in Claude Code, Cursor, and Codex following existing platform patterns
- [ ] The agent never applies fixes or creates issues without the human's explicit choice

---

## Out of Scope (MVP)

- Cross-session trend analysis (no persistent state between sessions)
- Automated retrospective triggering without human consent
- Post-merge-cleanup integration (detecting "last item in batch" is too hard without persistent state)
- A full backlog-item alignment conversation for "Add to backlog" (lightweight direct issue creation is used instead)
- Custom categorization taxonomy configuration (the taxonomy is fixed at the protocol level)
- Retrospective analytics or dashboards

---

## Open Questions

<!-- No blocking open questions remain. -->
