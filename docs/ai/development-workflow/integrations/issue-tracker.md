# Integration: Issue Tracker (Generic)

This document defines **tracker-agnostic** expectations for how agents should use an issue tracker (Linear, GitHub Issues, Jira, etc.) as an input source.

> Tracker-specific setup (APIs/MCP) lives in `docs/ai/development-workflow/integrations/`.

---

## What Agents Must Read (when available)

Before starting work on an item, agents must treat the issue tracker as the **source of the current brief** and read:

- **Title**
- **Description/body**
- **Most recent comments** (at minimum: the last 5, or any comments since the last agent run)
- **Linked issues / dependencies** (if the tracker supports it)
- **Priority + due date + status** (for orchestration/prioritization)

If the agent does not have direct issue tracker access, it must ask the human to paste:
- the current description, and
- the relevant recent comments (especially any decisions/changes).

---

## How to Interpret Comments

- **Prefer recency**: newer comments override older ones if they conflict.
- **Prefer explicit decisions**: “Decision: …”, “We will …”, “Out of scope: …” are high-signal.
- **Don’t guess**: if comments introduce ambiguity or contradict the spec/plan, **stop and ask** for clarification.
- **Don’t silently discard** issue tracker context: if it changes scope/requirements, call it out explicitly in the stage output (spec/plan/PR).

---

## Stage-Specific Rules

- **Spec Ready**: use the issue description/comments as the starting point for the alignment checklist; any decision captured in comments must be reflected in the spec (or surfaced as an Open Question if still unresolved).
- **Plan Ready**: if comments contain new constraints after the spec was merged, flag the discrepancy and request a spec update before proceeding.
- **In Development (Full Pipeline)**: scan recent comments for post-plan scope changes. If anything conflicts with the spec or plan, stop and request an update before coding.
- **In Development (Fast Track)**: the issue description/comments can be the brief; confirm scope is bounded and stop if it expands beyond the brief.
