# Smoke Test Runbook: Pre-merge Setup Signal

**Feature**: Pre-merge Setup Signal (#367)
**Spec**: [`docs/specs/developments/20260428074150_pre-merge-setup-signal/1_pre-merge-setup-signal_specs.md`](../../specs/developments/20260428074150_pre-merge-setup-signal/1_pre-merge-setup-signal_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The `needs-setup` GitHub label exists in the repository's label settings (created as part of Step 1 of the implementation)
- [ ] You have `gh` CLI authenticated against the repository
- [ ] You have a test PR available (or can create a minimal one) that includes a diff with a new environment variable reference (e.g., a change that adds a line like `process.env.MY_NEW_API_KEY` to a source file, or a new entry in `.env.example`)
- [ ] You have a second test PR (or the same PR after a fixer push) that has a diff with no infrastructure dependency signals

---

## Test Data

| Item | Value |
|---|---|
| Test repo | The current repository (`ai-dev-framework-template` or the downstream project under test) |
| PR with env var in diff | A PR whose diff adds a new environment variable reference (see Prerequisites) |
| PR without infrastructure signals | A PR whose diff contains only documentation or logic changes |
| `needs-setup` label | Must exist in repo label settings before running TC-1 |

---

## Smoke Test Steps

### Step 1: Verify `needs-setup` label exists in the repository

1. Open the repository on GitHub.
2. Navigate to **Issues** → **Labels**.
3. Confirm that a label named `needs-setup` is present.

**Expected result**: The `needs-setup` label exists with an appropriate description (e.g., "PR introduces setup steps required before the feature can be enabled").

---

### Step 2 (TC-1): Agent applies `needs-setup` when diff contains infrastructure signals

**Maps to**: AC-1, AC-2, AC-4

Simulate or observe the agent running Step 8a on a PR whose diff contains a new environment variable reference:

1. Identify or create a PR whose diff includes an added line that matches a detection heuristic (e.g., `+MY_NEW_SECRET=` in `.env.example`, or `+process.env.NEW_API_KEY` in source code, or `+${{ secrets.NEW_SECRET }}` in a GitHub Actions workflow file).
2. Manually trigger (or observe the agent trigger) the infrastructure dependency scan step at Step 8a of protocol 91.
3. After the scan completes, run:

   ```bash
   gh pr view <pr_number> --json labels --jq '.labels[].name'
   ```

4. Confirm `needs-setup` is present in the output.
5. Run:

   ```bash
   gh pr view <pr_number> --json body --jq '.body'
   ```

6. Confirm the PR body contains a `## Pre-merge Setup` section.
7. Confirm the section lists the detected requirement with: requirement name, type, plain-language description of the expected value, and where to set it.
8. Confirm `ready-for-human-review` is also present (the two labels co-exist):

   ```bash
   gh pr view <pr_number> --json labels --jq '.labels[].name'
   ```

**Expected result**: Both `needs-setup` and `ready-for-human-review` labels are present. The PR body contains a `## Pre-merge Setup` section with at least one row for the detected requirement. CI and automated reviews are not blocked by the presence of `needs-setup`.

---

### Step 3 (TC-2): Agent does not apply `needs-setup` when diff has no infrastructure signals

**Maps to**: AC-3

Observe or simulate the agent running Step 8a on a PR whose diff contains only documentation or logic changes (no new env var references, no new secret references, no new config keys):

1. Identify a PR whose diff adds only markdown prose, comments, or application logic with no infrastructure dependency patterns.
2. Trigger (or observe) the Step 8a scan.
3. Run:

   ```bash
   gh pr view <pr_number> --json labels --jq '.labels[].name'
   ```

4. Confirm `needs-setup` is **absent** from the output.
5. Run:

   ```bash
   gh pr view <pr_number> --json body --jq '.body'
   ```

6. Confirm the PR body does **not** contain a `## Pre-merge Setup` section.

**Expected result**: `needs-setup` is absent. No `## Pre-merge Setup` section appears in the PR body. `ready-for-human-review` is applied as normal.

---

### Step 4 (TC-3): Agent removes `needs-setup` when a fixer push removes the infrastructure signal

**Maps to**: AC-5

Using the same PR from TC-1 (or a similar setup), push a fix commit that removes the infrastructure dependency signal from the diff:

1. Starting from a PR that has `needs-setup` applied (from TC-1).
2. Push a commit that removes the env var reference from the diff (e.g., replace `process.env.NEW_API_KEY` with a hardcoded default or remove it entirely).
3. The agent re-runs automated review and CI loops, then re-runs Step 8a (including the diff scan).
4. After the re-scan, run:

   ```bash
   gh pr view <pr_number> --json labels --jq '.labels[].name'
   ```

5. Confirm `needs-setup` is now **absent**.
6. Run:

   ```bash
   gh pr view <pr_number> --json body --jq '.body'
   ```

7. Confirm the `## Pre-merge Setup` section has been **removed** from the PR body.

**Expected result**: After the fixer push that eliminates the infrastructure signal, both the `needs-setup` label and the `## Pre-merge Setup` section are removed. The PR body and labels reflect the current diff, not the prior state.

---

### Step 5 (TC-4): Protocol 92 documents `needs-setup` with correct semantics

**Maps to**: AC-7, AC-8

1. Open `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.
2. Confirm the Labels table contains a `needs-setup` row with a clear description of the label's meaning.
3. Confirm there is a section defining the conditions under which `needs-setup` is applied.
4. Confirm the section lists the valid label combinations:
   - `ready-for-human-review` only (clean path)
   - `ready-for-human-review` + `needs-setup` (setup required)
   - `needs-fixes` + `needs-setup` (transitional — both conditions apply)
5. Confirm the section documents who applies `needs-setup` (the agent at Step 8a) and who removes it (the human after setup).
6. Confirm the BR-3 invariant is documented: `needs-setup` does not prevent `ready-for-human-review` from being applied and does not block CI.

**Expected result**: Protocol 92 clearly defines the `needs-setup` label, its valid combinations, the actor responsible for each transition, and the invariant that it co-exists with `ready-for-human-review`.

---

### Last Step: Validate all assertions

- [ ] All checkboxes in the Assertions Checklist below are satisfied
- [ ] No CI or automated review was blocked by the presence of `needs-setup`

---

## Assertions Checklist

- [ ] AC-1: `needs-setup` label is applied when the diff contains one or more infrastructure dependency signals (env var, secret, config key)
- [ ] AC-2: The `## Pre-merge Setup` section in the PR body lists each detected requirement with: name, type, description of the expected value, and where to set it
- [ ] AC-3: `needs-setup` is absent and no `## Pre-merge Setup` section appears when the diff has no infrastructure signals
- [ ] AC-4: `needs-setup` is applied alongside `ready-for-human-review` — not instead of it
- [ ] AC-5: After a fixer push removes the infrastructure signal from the diff, both `needs-setup` and the `## Pre-merge Setup` section are removed
- [ ] AC-7: Protocol 91 Step 8a documents `needs-setup` as a valid co-label with `ready-for-human-review` and does not treat its presence as an error
- [ ] AC-8: Protocol 92 defines `needs-setup` with: semantics, valid combinations, and who removes it

---

## Seed Data Reference

Not applicable — this feature has no database seed data requirements. The smoke test operates on GitHub PRs and protocol documentation files only.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `needs-setup` label cannot be applied (error from `gh pr edit`) | Label does not exist in the repository's label settings | Create the `needs-setup` label in **Issues → Labels** in the GitHub repository UI, then retry |
| `## Pre-merge Setup` section not appearing in PR body | The diff-scan heuristic did not match the pattern used in the test PR | Verify the diff contains a pattern explicitly listed in the detection heuristics (e.g., `+NEW_VAR=` in `.env.example`, or `+${{ secrets.SECRET_NAME }}` in a workflow file). Check the protocol 91 heuristics subsection for the exact patterns. |
| `needs-setup` not removed after fixer push | The fixer commit did not remove all lines matching the detection heuristics | Inspect the PR diff after the fixer push (`gh pr diff <pr_number>`) and confirm no added lines match any heuristic pattern |
| Both `needs-setup` and `needs-fixes` are on the PR simultaneously | Expected transitional state — both conditions apply | No fix needed; the spec explicitly allows this combination. Address `needs-fixes` first (code changes), then the `needs-setup` scan will re-run during the next Step 8a pass |

---

## Known Limitations

- The detection heuristics are best-effort (BR-9). False negatives (missed dependencies) are accepted by design — the agent may not detect all infrastructure requirements, especially when they are introduced indirectly (e.g., a new npm dependency that internally requires an env var). Human judgment is the final authority on whether all setup is complete.
- AC-6 (new signals introduced by a fixer push are added to the section) is not explicitly covered by a TC step in this runbook because it requires an artificial scenario where a fixer push introduces a new infrastructure signal. This scenario is considered a variant of TC-1 and is assumed to work correctly given the same code path is exercised.
