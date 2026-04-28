# Pre-merge Setup Signal — Implementation Plan

**Spec**: [`1_pre-merge-setup-signal_specs.md`](1_pre-merge-setup-signal_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/367-pre-merge-setup-signal.smoke-test.md`](../../../testing/workflow/367-pre-merge-setup-signal.smoke-test.md)

---

## Summary

**Approach**: Add a lightweight `needs-setup` label and a standardised `## Pre-merge Setup` PR body section as a co-signal alongside `ready-for-human-review`. The implementation touches three areas: (1) the PR readiness signal protocol (`92-pr-readiness-signal-protocol.md`) to define the `needs-setup` label, its semantics, valid co-label combinations, and who removes it; (2) the orchestration protocol (`91-orchestrate-work-protocol.md`) at Step 8a to add a diff-scan step that detects infrastructure dependency signals and conditionally applies the label and section before `ready-for-human-review`; and (3) the smoke test runbook to cover detection on a setup PR and absence on a clean PR. No database, backend API, or frontend layer is involved — this is a pure workflow-protocol and documentation change.

**Estimated complexity**: S

**Rationale**: All changes are confined to two markdown protocol files and a new smoke test runbook. No code, scripts, or external services are modified. The detection heuristics are prose-level guidance for the agent performing the diff scan (not a compiled rule engine), so there is no parser-risk classification. The entire change is read, write, and label operations via `gh` CLI — well within the existing orchestration toolchain.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `b5b3937` |
| `needs-setup` in protocol 91 | `grep -n "needs-setup" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | No matches — label not yet defined or referenced |
| `needs-setup` in protocol 92 | `grep -n "needs-setup" docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | No matches — label not yet defined or referenced |
| `Pre-merge Setup` section referenced anywhere | `grep -rn "Pre-merge Setup" docs/workflow/` | No matches — section pattern is new |
| Existing smoke test runbooks in `docs/testing/workflow/` | `ls docs/testing/workflow/*.smoke-test.md \| wc -l` | 27 runbooks; no `367-pre-merge-setup-signal.smoke-test.md` yet |
| Step 8a location in protocol 91 | `grep -n "Step 8a" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Line 838 — "Step 8a: Label Readiness Checklist (Hard Gate)" |
| Labels section in protocol 92 | `grep -n "^## Labels" docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Line 9 — "## Labels" table |

---

## Layer-by-Layer Changes

### Protocol / Documentation Layer

- [ ] **`docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` — Labels table**: Add a `needs-setup` row to the Labels table:
  - Label: `needs-setup`
  - Meaning: PR introduces one or more infrastructure dependencies (env vars, secrets, DNS records, service account tokens, etc.) that require human setup steps before the feature can be safely enabled. Co-exists with `ready-for-human-review`; the human removes this label after completing setup.

- [ ] **`docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` — `needs-setup` semantics section**: Add a dedicated section after the Labels table defining:
  - The valid label combinations (see spec Statuses section): `ready-for-human-review` only; `ready-for-human-review` + `needs-setup`; `needs-fixes` + `needs-setup` (transitional state).
  - Who applies `needs-setup`: the agent, as part of Step 8a, after a diff scan detects infrastructure dependency signals.
  - Who removes `needs-setup`: the human, after completing the listed setup steps (or intentionally deferring).
  - Invariant (BR-1): `needs-setup` must always be accompanied by a `## Pre-merge Setup` section in the PR body. The label without the section is an incomplete signal.
  - Invariant (BR-2): The `## Pre-merge Setup` section must not appear in the PR body without the `needs-setup` label present at that time. After the human removes the label, the section remains as a historical record (BR-7).
  - Invariant (BR-3): `needs-setup` does not prevent `ready-for-human-review` from being applied, does not block CI, and does not block automated review tools from completing.
  - Invariant (BR-10): `needs-setup` is distinct from `needs-fixes` — different semantics, different lifecycle, may co-exist.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8a diff-scan step**: Insert a new sub-step into Step 8a (Label Readiness Checklist) to run the infrastructure dependency scan **after** CI is green and reviews are clean but **before** applying `ready-for-human-review`. The sub-step must:
  1. Read the PR diff via `gh pr diff <pr_number>`.
  2. Scan the diff for infrastructure dependency signals using the detection heuristics defined below (see Infrastructure Dependency Detection Heuristics subsection).
  3. If one or more signals are found:
     a. Construct a `## Pre-merge Setup` section in the PR body listing each detected requirement with: requirement name, type (env var / GitHub Actions secret / DNS record / etc.), plain-language description of the expected value, and where to set it (BR-8).
     b. Edit the PR body to include this section: `gh pr edit <pr_number> --body "<updated-body>"`. The section is appended to the existing PR body.
     c. Apply the `needs-setup` label: `gh pr edit <pr_number> --add-label "needs-setup"`.
  4. If no signals are found: ensure no `needs-setup` label is present and no `## Pre-merge Setup` section exists in the PR body.
  5. This scan runs on every pass through Step 8a (including after fixer pushes), so the label and section always reflect the current diff (AC-5, AC-6, BR-6).
  6. After the scan: proceed to apply `ready-for-human-review` as normal. The presence of `needs-setup` does not block this step (BR-3, BR-4).

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8a: infrastructure dependency detection heuristics subsection**: Add a prose subsection named "Infrastructure Dependency Detection Heuristics" inside Step 8a. The heuristics are best-effort and intentionally incomplete (BR-9). The developer agent must look for the following patterns in the PR diff (added lines, i.e., lines starting with `+` in the diff output):
  - **New environment variable references**: lines matching patterns like `process.env.NEW_VAR`, `os.environ["NEW_VAR"]`, `$NEW_VAR` (in shell), or entries added to `.env.example`, `.env.template`, or similar env template files.
  - **New GitHub Actions secret references**: added lines in `.github/workflows/**` files that reference `${{ secrets.NEW_SECRET }}`.
  - **New config key additions to environment-specific config files**: added keys in files named `*.env`, `.env.*`, `config/production.*`, or similar deployment-configuration files.
  - **Explicit "TODO: set secret/env" comments added in the diff**: comments in the diff containing phrases like `# TODO: set`, `# Set this to`, `# Required: configure`, or similar that indicate a value must be externally provided.
  - The heuristics are advisory. False negatives (missed dependencies) are acceptable (BR-9). False positives should be handled gracefully: the section informs the human, who decides whether setup is actually required.
  - Each detected signal produces one row in the `## Pre-merge Setup` section.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8a checklist update**: Add a note to the Step 8a checklist that `needs-setup` is a valid co-label with `ready-for-human-review` and must not be treated as an error condition that blocks readiness. The checklist script does not need to check for or remove `needs-setup` — it is not stale at this point; it is a deliberate signal.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8c independent verification table**: Add a row to the verification table noting that the presence of `needs-setup` is valid and expected when infrastructure dependencies are detected, and that its presence does not constitute a verification failure.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. PR diff contains a new env var entry — `needs-setup` label applied and `## Pre-merge Setup` section populated (maps to AC-1, AC-2, AC-4)
2. PR diff contains no infrastructure signals — `needs-setup` absent, no section in body (maps to AC-3)
3. After a fixer push removes the env var from the diff — `needs-setup` removed and section cleared (maps to AC-5)
4. Protocol 92 explicitly lists `needs-setup` with semantics and valid combinations (maps to AC-7, AC-8)
5. Smoke test runbook covers all verification assertions (maps to AC-9)

**Smoke test runbook**: `docs/testing/workflow/367-pre-merge-setup-signal.smoke-test.md`

**Regression suite**: None in this repository.

---

## Seed Data

Not applicable — this feature has no database or application-level seed data requirements. The smoke test exercises the feature by inspecting PR labels and body text on a GitHub pull request.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated as part of this implementation (Step 8a diff-scan step, heuristics subsection, Step 8c table row). This is an in-scope change, not a follow-up.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` — updated as part of this implementation (Labels table, `needs-setup` semantics section). This is an in-scope change, not a follow-up.

No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` require updates. This feature adds a workflow-level signal mechanism; it does not change domain entities, repo architecture, software architecture, the database model, general coding standards, version control conventions, or testing standards.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Diff-scan heuristics produce false positives on spec/plan PRs (which touch markdown, not code) | Low | Low | Detection heuristics target code-level patterns (env references in source files, secrets in workflow YAML). Markdown-only diffs will not match these patterns. No mitigation required beyond heuristic design. |
| PR body edit (`gh pr edit --body`) overwrites an existing custom body | Low | Low | Read the existing PR body first, append the section, then write the full updated body. Implementation note in Step 8a makes this explicit. |
| `needs-setup` label does not exist in the GitHub repo's label set | Low | Medium | Document in the smoke test that the label must be created in the repo's label settings before first use. The developer implementing this step should also add a note in the heuristics subsection. |
| Human forgets to remove `needs-setup` before merge | Low | Low | The label is a signal only (BR-3); it does not block merge. The human's responsibility is documented in the spec (Use Case 3) and in protocol 92. |

---

## Code Samples

Not applicable. All changes are prose additions to existing markdown protocol files. No scripts, code, or structured data files are introduced.

---

## Implementation Order

1. **Create the `needs-setup` GitHub label** in the repository's label settings (if it does not already exist). Suggested color: `#fbca04` (yellow, to indicate a prerequisite action without implying a blocking failure). This step is a one-time repo setup action, not a code change.

2. **Update `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`**:
   - Add `needs-setup` row to the Labels table (after the existing `ready-for-regression` row).
   - Add a new `## Conditions for needs-setup` section (parallel to the existing `## Conditions for ready-for-human-review` and `## Conditions for needs-fixes` sections) defining: who applies it (agent at Step 8a after diff scan), who removes it (human after setup), valid co-label combinations, and the BR-1/BR-2/BR-3/BR-10 invariants.
   - Verify the section placement is logical and consistent with the surrounding content.

3. **Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8a**:
   - Locate the Step 8a section (Label Readiness Checklist).
   - Before the existing checklist script block (Check 1–4), insert a new prose block titled "**Infrastructure Dependency Scan (pre-readiness)**" that describes the diff-scan process and heuristics (as defined in Layer-by-Layer Changes above).
   - After the scan prose, update the existing checklist commentary to note that `needs-setup` is a valid co-label with `ready-for-human-review` and is not removed by the checklist script.

4. **Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8c**:
   - Locate the verification table in Step 8c.
   - Add a note (either as a new row or as a footnote to the existing `No needs-fixes label` row) clarifying that `needs-setup` may be present alongside `ready-for-human-review` and does not constitute a verification failure.

5. **Write the smoke test runbook** at `docs/testing/workflow/367-pre-merge-setup-signal.smoke-test.md` covering:
   - TC-1: Verify `needs-setup` label is applied and `## Pre-merge Setup` section appears in the PR body when the diff contains a new env var reference (maps to AC-1, AC-2, AC-4).
   - TC-2: Verify `needs-setup` is absent and no section appears when the diff contains no infrastructure signals (maps to AC-3).
   - TC-3: Verify after a fixer push that removes the env var: `needs-setup` is removed and the section is cleared from the PR body (maps to AC-5).
   - TC-4: Verify protocol 92 contains the `needs-setup` label definition, semantics, and valid combinations (maps to AC-7, AC-8).

6. **Run markdownlint-cli2** on the two updated protocol files and the new smoke test runbook before committing:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
     "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md" \
     "docs/testing/workflow/367-pre-merge-setup-signal.smoke-test.md"
   ```

   Fix any trailing-whitespace, broken-link, or missing-trailing-newline violations before proceeding.

7. **Update `CHANGELOG.md`** under `[Unreleased]` with:

   ```
   - **Add pre-merge setup signal for PRs requiring human configuration** (#367): Adds a `needs-setup` label and a standardised `## Pre-merge Setup` PR body section so agents surface infrastructure dependencies (env vars, secrets, DNS records) at PR readiness time rather than requiring the human to read the diff. Protocol 91 Step 8a now includes a diff-scan heuristic step; protocol 92 defines the label semantics and valid co-label combinations.
   ```
