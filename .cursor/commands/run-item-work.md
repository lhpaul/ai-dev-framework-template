---
description: Advance a single workflow item end-to-end. Use when you already know the target development folder, branch, PR, or issue and want to keep only that item moving until it is waiting on a human, blocked, or escalated. Usage: /run-item-work <target>
---

# Cursor Command: Run Item Work

Follow the single-item orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

Key responsibilities:

- Resolve the request to exactly one workflow item
- Use the helper scripts in `scripts/development-workflow/` to classify the next deterministic action
- In `workflow_hub`, state selected product repository, artifact owner, and mutation target before implementation mutation; stop when context is missing or ambiguous
- Continue through creator, reviewer, PR, automated review, and CI work until the item reaches a real terminal condition
- If the request is portfolio-wide or requires batch selection, switch to `/run-work`
