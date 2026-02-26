# Protocol: Smoke Test

**Agent role**: Smoke Tester
**Stage**: In Development (step after code review is approved)
**Output**: Pass/fail report per runbook step

---

## Project-specific details

This protocol is project-agnostic. **Project-specific instructions** — environment setup, execution approach (e.g. committed test suite vs ad-hoc script), known limitations, troubleshooting, and cleanup commands — live in the project's testing README.

- **In this repo**: See `docs/testing/README.md`.

---

## Prerequisites

Before running the smoke test, the following must be true. If the human asks you to set up the environment yourself, follow the project testing README for exact commands.

- Any required backing services (e.g. Docker, local database) are running
- The database is in the expected state (e.g. reset and seeded)
- The target application is running locally and responding to HTTP requests
- The smoke test runbook path is provided by the human (or found via the project testing README)

If a migration or seed step fails, **do not fix it** — report the failure to the human and stop.

---

## Inputs

The human (or the workflow) provides:

1. **Runbook path**: Path to the smoke test runbook.
2. **Application URL** (optional): Base URL of the app under test. See the project testing README for defaults.

---

## Steps

### 1. Read Context

Before writing any test code, read:

- The **smoke test runbook**
- The **project testing README** — for environment setup, execution approach, known limitations, and troubleshooting
- **Application source code** for the pages under test (e.g. component templates) to understand selectors, labels, routes, and UI library patterns

### 2. Choose and Execute the Test Approach

Before writing any code, check whether a committed automated spec already exists for the feature under test. The project testing README (`docs/testing/README.md`) has the decision tree for this project — follow it.

**Path A — Committed spec exists**:

Run the project's automated test suite for the affected feature. See the project testing README for the exact command. Do not write a duplicate ad-hoc script. Report the suite output as the test result.

**Path B — No spec exists yet** (ad-hoc fallback):

Write a browser automation script following the approach described in the project testing README. The script should:

1. Log into the application
2. Execute each runbook step sequentially
3. Record PASS/FAIL for each step
4. Use database queries for verification when UI elements are inaccessible (see project testing README for connection details and workarounds)

### 3. Record Results

For each runbook step, record:

- **Step number and description**
- **Result**: PASS or FAIL
- **Details**: What was observed (for failures, include expected vs. actual)

---

## Output Format

```
## Smoke Test Report: [feature-name]

### Environment
- Application: [URL]
- Runbook: [path]
- Date: [YYYY-MM-DD]

### Results

| # | Step | Result | Details |
|---|------|--------|---------|
| 1 | [step description] | PASS/FAIL | [observation] |
| 2 | [step description] | PASS/FAIL | [observation] |
| ... | ... | ... | ... |

### Summary
- Total steps: [N]
- Passed: [N]
- Failed: [N]

### Verdict
[ ] PASSED — all steps pass, ready for merge
[ ] FAILED — see failed steps above
```

---

## Pass Criteria

- **All** runbook steps must pass for the smoke test to be considered successful

---

## Fail Handling

When a step fails:

1. Record the failure with details (expected vs. actual)
2. Take a screenshot if possible for context
3. Continue executing remaining steps (do not stop at first failure)
4. **Do NOT apply fixes** — that is the developer's responsibility
5. Report the full results to the human

---

## Cleanup

**Always run cleanup when the smoke test finishes or is interrupted**, regardless of pass/fail outcome. See the **project testing README** for the exact cleanup commands.
