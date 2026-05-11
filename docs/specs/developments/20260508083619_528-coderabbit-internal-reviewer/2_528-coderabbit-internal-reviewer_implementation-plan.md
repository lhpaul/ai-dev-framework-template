# CodeRabbit as Internal Reviewer (Step 7a) — Implementation Plan

**Spec**: [1_528-coderabbit-internal-reviewer_specs.md](./1_528-coderabbit-internal-reviewer_specs.md)
**Smoke test runbook**: [docs/testing/workflow/528-coderabbit-internal-reviewer.smoke-test.md](../../../testing/workflow/528-coderabbit-internal-reviewer.smoke-test.md)

---

## Summary

**Approach**: Extend Protocol 91 Step 7a to recognise `coderabbit` as a third supported
`internal_reviewers` value alongside `claude` and `codex`. The change adds a CodeRabbit row to
the reachability classification table, documents the invocation and response-polling mechanism
(reusing the same GitHub App auto-review trigger already described for Step 7 in
`coderabbit.md`), and updates the `.ai-dev-workflow.yaml` comment block and the
`coderabbit.md` integration doc. No new scripts are required; the protocol prose is the
authoritative implementation surface for Step 7a behaviour.

**Estimated complexity**: S

**Rationale**: All three changed files are documentation/protocol text. The invocation
mechanism (GitHub App auto-review on push, polling for `coderabbitai[bot]` response) already
exists and is fully described for Step 7 in `coderabbit.md` — Step 7a reuses the same
mechanism on a draft PR. The primary work is adding the CodeRabbit availability-check rule,
draft-PR requirement (BR-5), severity classification reference (BR-3), and the `warn`/hard-fail
policy integration. No new tooling is introduced.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `0795642` |
| Current supported `internal_reviewers` values in Protocol 91 | `grep -n "Supported reviewer values" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Line 745: `` `claude`, `codex`. `` — `coderabbit` not present |
| Reachability classification table columns in Protocol 91 | `grep -n "Runner context" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Line 761: table header lists only `claude` reachable? and `codex` reachable? — no `coderabbit` column |
| `coderabbit.md` sections present | `grep -n "^##" docs/workflow/development-workflow/integrations/coderabbit.md` | Lines 9, 18, 22, 27, 48, 79 — no "Step 7a" section |
| `.ai-dev-workflow.yaml` internal_reviewers comment block | `grep -n "Supported values" .ai-dev-workflow.yaml` | Line 46 — comment lists `claude` and `codex` only; no `coderabbit` entry |
| `coderabbit` in `internal_reviewers` list | `grep -n "coderabbit" .ai-dev-workflow.yaml` | Lines 29, 31 in `review.platforms` section only — not in `internal_reviewers` |

---

## Layer-by-Layer Changes

### Protocol Documents

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`** —
  Three targeted edits:

  1. **"Supported reviewer values" sentence** (line 745): Extend from `` `claude`, `codex`. ``
     to `` `claude`, `codex`, `coderabbit`. ``

  2. **"Reachability classification table"** (starting at line 759): Add a `coderabbit`
     reachable? column. CodeRabbit reachability is not determined by runner context alone —
     it depends on whether the CodeRabbit GitHub App is installed and whether `auto_review`
     is enabled for draft PRs. Add a note that the check is performed by querying the PR
     for prior `coderabbitai[bot]` activity or confirming App installation via `gh api`, and
     that it defaults to `unreachable` when the check cannot be confirmed.

     New column values per runner context:
     | Runner context | `coderabbit` reachable? |
     |---|---|
     | Claude Code (direct human session) | Determined at runtime (App check) |
     | Claude Code subagent (dispatched by orchestrator) | Determined at runtime (App check) |
     | Codex runner / Codex skill | Determined at runtime (App check) |
     | Direct human (shell / CI with `gh`) | Determined at runtime (App check) |

     Add a paragraph immediately after the table explaining the runtime App check: to
     determine `coderabbit` reachability, the runner checks whether `coderabbitai[bot]` has
     any prior activity on the repository (via `gh api repos/{owner}/{repo}/installation`
     or by checking the PR for a prior CodeRabbit comment), **and** confirms that
     `.coderabbit.yaml` does not restrict reviews to non-draft PRs. If either check fails,
     classify as `unreachable` (BR-5 consequence: treated as "App not installed").

  3. **"Reviewer dispatch map" table** (lines 820–827): Add three new rows for `coderabbit`:

     | Reviewer | PR branch prefix | Agent / protocol to dispatch |
     |---|---|---|
     | `coderabbit` | `spec/*` | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |
     | `coderabbit` | `implementation-plan/*` | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |
     | `coderabbit` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | Trigger CodeRabbit via push (auto-review); poll for `coderabbitai[bot]` response — see `coderabbit.md` Step 7a section |

### Integration Documentation

- [ ] **`docs/workflow/development-workflow/integrations/coderabbit.md`** — Add a new top-level
  section **"Step 7a — Internal Reviewer (Draft PRs)"** after the existing "Usage Modes"
  section (before "Setup"). This section must cover:

  - **Configuration**: Set `coderabbit` in `review.internal_reviewers` in
    `.ai-dev-workflow.yaml`.
  - **Draft-PR requirement**: `reviews.auto_review.enabled: true` in `.coderabbit.yaml` is
    required. If draft PRs are filtered out by the CodeRabbit App configuration, the runner
    classifies `coderabbit` as unreachable in Step 7a (BR-5).
  - **Invocation**: CodeRabbit auto-reviews on push (same mechanism as Step 7). No trigger
    comment is needed. The runner waits for a `coderabbitai[bot]` review posted after the
    HEAD commit timestamp.
  - **Severity classification**: Identical to Step 7 — `Critical` and `Major` are blocking;
    `Minor`, `Low`, and no-marker are suggestions (BR-3).
  - **Fix-cycle limit**: Subject to the same `max_internal_review_cycles` (default: 5) as
    other internal reviewers (BR-4).
  - **Availability check**: The runner checks for prior `coderabbitai[bot]` activity on the
    repository (App installation signal) and verifies that `.coderabbit.yaml` does not
    restrict reviews to non-draft PRs before classifying as reachable.
  - **Troubleshooting** subsection covering:
    - CodeRabbit App not installed → `unreachable`, warning comment posted, `warn` policy
      proceeds with remaining reachable reviewers.
    - `auto_review.enabled: false` in `.coderabbit.yaml` → `unreachable` (App configured
      to skip reviews).
    - Draft PRs not enabled in CodeRabbit App settings → `unreachable` (BR-5).
    - All reviewers unreachable → hard-fail, PR stays draft, escalate to human.

### Configuration / YAML

- [ ] **`.ai-dev-workflow.yaml`** — Update the `review.internal_reviewers` comment block to
  add a `coderabbit` entry describing its invocation behaviour (BR-10):

  ```yaml
  #   coderabbit  — triggers CodeRabbit GitHub App auto-review on the draft PR
  #                 (same mechanism as Step 7 but on a draft PR before non-draft
  #                 conversion). Requires: App installed, auto_review.enabled: true
  #                 in .coderabbit.yaml, and draft PRs not filtered out by the App.
  #                 Reachability is determined at runtime by checking App activity
  #                 on the repository. See docs/workflow/development-workflow/
  #                 integrations/coderabbit.md Step 7a section for setup details.
  ```

  Insert after the existing `codex` block comment (before the "Runner-context constraint"
  paragraph).

---

## Testing Strategy

**Test types**: Manual smoke test (protocol documentation changes; no executable code is
modified).

**Key scenarios to test**:

1. Protocol 91 lists `coderabbit` as a supported `internal_reviewers` value — maps to AC
   (Protocol 91 Step 7a documentation updated).
2. Reachability classification table includes `coderabbit` column with "Determined at
   runtime" annotation — maps to BR-9 and BR-2.
3. `coderabbit.md` contains a "Step 7a — Internal Reviewer" section with draft-PR
   requirement, invocation mechanism, severity classification, and troubleshooting — maps to
   the spec AC requiring `coderabbit.md` update.
4. `.ai-dev-workflow.yaml` comment lists `coderabbit` as a supported `internal_reviewers`
   value — maps to BR-10.
5. Backward-compatibility check: repos using `coderabbit` only in `review.platforms` are
   unaffected — maps to BR-8 (no change to Step 7 behaviour).

**Smoke test runbook**: `docs/testing/workflow/528-coderabbit-internal-reviewer.smoke-test.md`

---

## Seed Data

None. This feature affects only protocol documentation and configuration comments.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/coderabbit.md` — This file is itself
  one of the primary change targets (see Layer-by-Layer). The "Step 7a — Internal Reviewer"
  section is added as part of implementation. No separate post-implementation update needed
  beyond what is described in the Layer-by-Layer section.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — This
  file is itself one of the primary change targets. No separate post-implementation update
  needed beyond what is described in the Layer-by-Layer section.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Protocol 91 reachability table becomes inconsistent if a fourth reviewer is added later | Low | Low | The new `coderabbit` row uses a clearly distinct pattern ("Determined at runtime (App check)") that future authors can extend without breaking existing rows |
| Draft-PR requirement (BR-5) not obvious to operators | Low | Med | The `coderabbit.md` troubleshooting section explicitly lists "draft PRs not enabled" as a common unavailability reason |
| Backward-compatibility regression: `review.platforms: [coderabbit]` repos treated as `internal_reviewers: [coderabbit]` | Low | Med | No change is made to Step 7 path logic; the new rows in the reviewer dispatch map are only consulted when `coderabbit` appears in `review.internal_reviewers` |

---

## Implementation Order

1. **Update Protocol 91 Step 7a — "Supported reviewer values" sentence** (line 745): Change
   `` `claude`, `codex`. `` to `` `claude`, `codex`, `coderabbit`. `` in
   `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.

   *Verification*: Run `grep "Supported reviewer values" -A1 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and confirm the line immediately after includes `coderabbit`.

2. **Update Protocol 91 Step 7a — "Reachability classification table"**: Add a
   `coderabbit` reachable? column to the table at line 761. Add the "Determined at runtime
   (App check)" value for all four runner contexts. Add the explanatory paragraph after the
   table describing the runtime App check mechanism and the draft-PR restriction check
   (BR-5).

   *Verification*: Open the file at the reachability table and confirm the table has three
   data columns (claude, codex, coderabbit) and the paragraph immediately after describes
   the App installation check.

3. **Update Protocol 91 Step 7a — "Reviewer dispatch map"**: Add three `coderabbit` rows
   to the reviewer dispatch map table (one per branch prefix group: `spec/*`,
   `implementation-plan/*`, and `feature/*/refactor/*/fix/*/hotfix/*`). Each row references
   the `coderabbit.md` Step 7a section.

   *Verification*: Confirm three `coderabbit` rows appear in the reviewer dispatch map table
   and each references `coderabbit.md`.

4. **Add "Step 7a — Internal Reviewer (Draft PRs)" section to `coderabbit.md`**: Insert
   after the "Usage Modes" section. Include configuration, draft-PR requirement, invocation,
   severity classification, fix-cycle limit, availability check, and troubleshooting
   subsection.

   *Verification*: Run `grep "^## " docs/workflow/development-workflow/integrations/coderabbit.md`
   and confirm "Step 7a" appears as a top-level section heading. Open the section and verify
   it contains "draft", "auto_review", "Critical", "Major", and "troubleshooting" content.

5. **Update `.ai-dev-workflow.yaml` comment block**: Insert the `coderabbit` block comment
   after the `codex` block comment and before the "Runner-context constraint" paragraph in
   the `internal_reviewers` comment block.

   *Verification*: Run `grep -A3 "coderabbit" .ai-dev-workflow.yaml` and confirm the new
   comment block appears under `internal_reviewers` (not under `review.platforms`).

6. **Run markdownlint-cli2 pre-commit check**:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260508083619_528-coderabbit-internal-reviewer/2_528-coderabbit-internal-reviewer_implementation-plan.md" \
     "docs/testing/workflow/528-coderabbit-internal-reviewer.smoke-test.md"
   ```

   Fix any reported violations before committing.

7. **Run the smoke test runbook** to confirm all acceptance criteria are satisfied.

8. **Documentation Updates**: All documentation changes are performed inline as part of
   steps 1–5 above. No separate documentation update step is needed.

9. **Update `CHANGELOG.md` under `[Unreleased]`**:

   ```markdown
   - **Support CodeRabbit as internal reviewer (Step 7a)** (#528): Add `coderabbit` as a
     supported value in `review.internal_reviewers` in `.ai-dev-workflow.yaml`, allowing
     CodeRabbit to run as a Step 7a draft-PR internal reviewer before non-draft conversion.
     Updates Protocol 91 Step 7a (supported values list, reachability classification table,
     reviewer dispatch map) and adds a "Step 7a — Internal Reviewer" section to
     `docs/workflow/development-workflow/integrations/coderabbit.md`.
   ```
