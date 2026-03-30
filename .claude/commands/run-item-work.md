---
description: Advance a single workflow item end-to-end. Use when you already know the target development folder, branch, PR, or issue and want to keep only that item moving until it is waiting on a human, blocked, or escalated. Usage: /run-item-work <target>
---

# Claude Code Command: Run Item Work

Follow the single-item orchestration protocol exactly as defined in:

`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`

Key responsibilities:

- Resolve the request to exactly one workflow item
- Use the helper scripts in `scripts/development-workflow/` to classify the next deterministic action
- Continue through creator, reviewer, PR, automated review, and CI work until the item reaches a real terminal condition
- If the request is portfolio-wide or requires batch selection, use the Agent tool to invoke the `orchestrator` agent (there is no `/run-work` slash command in Claude Code; the `orchestrator` agent is the equivalent dispatch target)
