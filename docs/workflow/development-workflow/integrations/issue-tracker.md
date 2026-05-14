# Integration: Issue Tracker (Generic)

This document defines **tracker-agnostic** expectations for how agents should use a work-item tracker (Linear, GitHub Issues, Jira, etc.) as an input source.

> Tracker-specific setup (APIs/MCP) lives in `docs/workflow/development-workflow/integrations/`.
> If this repository uses a tracker, declare it in `.ai-dev-workflow.yaml` under `issue_tracker.provider`.

---

## What Agents Must Read (when available)

Before starting work on an item, agents must treat the tracker work item as the **source of the current brief** and read:

- **Title**
- **Description/body**
- **Most recent comments** (at minimum: the last 5, or any comments since the last agent run)
- **Linked work items / dependencies** (if the tracker supports it)
- **Priority + due date + status** (for orchestration/prioritization)

If the agent does not have direct tracker access, it must ask the human to paste:

- the current description, and
- the relevant recent comments (especially any decisions/changes).

---

## How to Interpret Comments

- **Prefer recency**: newer comments override older ones if they conflict.
- **Prefer explicit decisions**: “Decision: …”, “We will …”, “Out of scope: …” are high-signal.
- **Don’t guess**: if comments introduce ambiguity or contradict the spec/plan, **stop and ask** for clarification.
- **Don’t silently discard** tracker context: if it changes scope/requirements, call it out explicitly in the stage output (spec/plan/PR).

---

## Stage-Specific Rules

- **Writing Spec**: treat the work item as “in flight” until the spec PR is human-ready; keep the brief and any new comments in sync with the spec branch/PR.
- **Writing Plan (Full Pipeline)**: same as **Writing Spec**, but for the implementation-plan branch/PR after the spec is merged.
- **Writing Plan (Refactor)**: treat the work item as “in flight” until the plan PR is human-ready; keep the brief and any new comments in sync with the plan branch/PR. There is no spec — the work item brief is the starting input.
- **Development in Review**: treat the work item as waiting on a human merge decision for the feature/fix PR; address `needs-fixes` promptly if the human requests changes.
- **Spec Ready**: use the work item description/comments as the starting point for the alignment checklist; any decision captured in comments must be reflected in the spec (or surfaced as an Open Question if still unresolved).
- **Plan Ready (Full Pipeline)**: if comments contain new constraints after the spec was merged, flag the discrepancy and request a spec update before proceeding.
- **Plan Ready (Refactor)**: if comments contain new constraints after the plan was written, flag the discrepancy and request a plan update before proceeding. There is no spec — the plan and work item brief are the authoritative sources.
- **In Development (Full Pipeline)**: scan recent comments for post-plan scope changes. If anything conflicts with the spec or plan, stop and request an update before coding.
- **In Development (Refactor)**: scan recent comments for post-plan scope changes. If anything conflicts with the plan, stop and request an update before coding. There is no spec for refactor items — the plan and work item brief are the authoritative sources.
- **In Development (Fast Track)**: the work item description/comments can be the brief; confirm scope is bounded and stop if it expands beyond the brief.
