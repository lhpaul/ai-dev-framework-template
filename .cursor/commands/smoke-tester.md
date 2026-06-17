---
description: Run a smoke test for a feature or PR. Usage: /smoke-tester [runbook path or PR number]
---

# Cursor Command: Smoke Tester

Invoke the `smoke-tester` agent to run the smoke test for the specified feature or PR.

Pass any scope hint provided by the user (runbook path or PR number) directly to the agent. When no hint is given, the agent reads the testing README to determine the correct runbook.

The agent follows the smoke test protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md`
