---
description: "Compatibility/advanced alias: advance exactly one known workflow item without routing. Use when you already know the target development folder, branch, PR, or issue and want to bypass /run-work routing. For the recommended starting point, use /run-work instead. Usage: /run-item-work <target>"
---

# Claude Code Command: Run Item Work

> **Compatibility/advanced alias**: `/run-item-work` bypasses the `/run-work`
> routing layer and advances exactly one known item directly. If you are not
> sure which command to use, start with `/run-work` — it will route to this
> protocol automatically when the target resolves to a single non-epic item.

Follow the single-item orchestration protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

Key responsibilities:

- Resolve the request to exactly one workflow item
- Use the helper scripts in `scripts/development-workflow/` to classify the next deterministic action
- In `workflow_hub`, state selected product repository, artifact owner, and mutation target before implementation mutation; stop when context is missing or ambiguous
- Continue through creator, reviewer, PR, automated review, and CI work until the item reaches a real terminal condition
- If the request is portfolio-wide or requires batch selection, use `/run-work` instead
