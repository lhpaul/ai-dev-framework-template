# Release Stamping for Shipped Issues — Implementation Plan

**Spec**: [1_release-stamping_specs.md](/docs/specs/developments/20260606104420_release-stamping/1_release-stamping_specs.md)
**Smoke test runbook**: [release-stamping.smoke-test.md](../../../testing/workflow/release-stamping.smoke-test.md)

---

## Summary

**Approach**: Extend the existing release post-merge cleanup path so each
explicit shipped issue is stamped with the production version before or alongside
the current `Merged` to `Released` transition. For GitHub Issues and GitHub
Projects, implement the MVP with GitHub Milestones through `gh`: create the
milestone when absent, assign it to each shipped issue, and close the milestone
after successful release cleanup. Keep the operation best effort and
provider-routed, with clear warnings for unsupported or partially configured
providers.

**Estimated complexity**: L

**Rationale**: This crosses release protocol behavior, shell helper code,
tracker-provider routing, GitHub milestone mutation flows, release cleanup
summaries, and integration docs. The implementation must preserve the current
safe release boundary: only run after both release PRs have merged and only for
explicitly scoped issues.

**Dependencies**: The existing post-merge release cleanup helper must remain the
single entry point for branch cleanup and scoped tracker transitions:
`scripts/development-workflow/prepare-release-post-merge-cleanup.sh`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `0b52d0d` |
| Release protocol surface | `sed -n '1,260p' docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` | Step 9 already delegates post-merge branch cleanup and explicit issue `Merged` to `Released` transitions to `prepare-release-post-merge-cleanup.sh`. |
| Cleanup helper surface | `sed -n '1,320p' scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | The helper verifies both release PRs merged, deletes release branches, accepts `--issue`/`--issues`, supports `--best-effort`, and emits `UPDATED`, `SKIPPED`, `FAILED`. |
| Tracker helper surface | `rg -n "issue_tracker|tracker_status|custom_field|Released|release" scripts/development-workflow/workflow-lib.sh` | Existing helpers provide provider normalization, `issue_tracker.custom_fields` reads, targeted GitHub Projects Status updates, and Linear shell fallbacks. |
| Integration docs present | `find docs/workflow/development-workflow/integrations -maxdepth 1 -type f -name '*.md' -print | sort` | Tracker-specific docs currently include `github-projects.md`, `issue-tracker.md`, and `linear.md`; no Jira, ClickUp, or Notion provider guide exists yet. |
| Prepare-release command surfaces | `rg -n "prepare-release|post-merge cleanup|release" .claude .cursor .agents .codex -g '*.md' -g 'SKILL.md'` | Claude/Cursor commands and the Codex alias delegate to Protocol 05 and mention Step 9 cleanup, so protocol updates cover most entrypoints with small summary edits where useful. |

## Layer-by-Layer Changes

### Release Cleanup Script

- [ ] Extend
      `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` so
      release stamping runs when `--issue` or `--issues` is supplied.
- [ ] Normalize the version argument once and expose both:
      - `RELEASE_BRANCH`, e.g. `release/v1.2.0`;
      - `RELEASE_VERSION`, e.g. `v1.2.0`.
- [ ] Stamp each issue before the status transition from `Merged` to `Released`
      in the same per-issue loop.
- [ ] Keep release-stamp failures best effort by default: increment a separate
      stamp warning count, print provider, issue identifier, version, and reason,
      then continue to the status transition.
- [ ] Extend the structured summary to include release-stamp counts, for
      example `STAMPED=N STAMP_SKIPPED=N STAMP_FAILED=N UPDATED=N SKIPPED=N FAILED=N`.
- [ ] Preserve existing failure semantics for status transitions. A stamp failure
      alone must not cause a non-zero exit, even without `--best-effort`.
- [ ] Close or finalize the release marker after the per-issue loop only when at
      least one issue was stamped and the provider supports a lifecycle.

### Workflow Library Helpers

- [ ] Add a tracker-agnostic helper in
      `scripts/development-workflow/workflow-lib.sh`, such as
      `record_release_for_issue_best_effort <issue> <version>`, that routes by
      `issue_tracker.provider`.
- [ ] Add GitHub provider helpers:
      - resolve repository owner/name with existing GitHub repo resolver helpers;
      - create a milestone named `<version>` if it is absent;
      - assign the milestone to a GitHub issue with `gh issue edit`;
      - treat an existing assignment to the same milestone as success;
      - print warning details and return success for fail-soft caller behavior.
- [ ] Add a GitHub release-marker finalizer helper, such as
      `finalize_release_marker_best_effort <version>`, that closes the milestone
      only after release cleanup has completed.
- [ ] Route `issue_tracker.provider: none` or an empty provider to a no-op with
      an informational skip message.
- [ ] Route unsupported providers to warnings that include provider, issue,
      version, and the missing mechanism.
- [ ] For Linear, use configuration keys from `issue_tracker.custom_fields`:
      - `release_field` for a future custom-field write path;
      - `release_label_prefix` for label-based fallback, defaulting to
        `release/`.
      Shell code should warn when MCP/API access is required rather than silently
      pretending the write happened.
- [ ] For Jira, ClickUp, and Notion, define configuration key names and warning
      behavior in docs, but do not add untestable shell writes unless the
      repository has a provider integration available.

### Changelog Issue Set Source

- [ ] Keep `CHANGELOG.md` as the provider-independent source of release contents.
- [ ] Update Protocol 05 to tell release operators to derive the explicit
      `--issues` list from the finalized version section, using referenced issue
      IDs in that section.
- [ ] Do not make the cleanup helper parse `CHANGELOG.md` implicitly in the MVP.
      The helper should keep its current explicit-scope contract so release
      cleanup cannot accidentally stamp or release the wrong issue set.
- [ ] Document a future-compatible helper boundary for changelog parsing if a
      later implementation wants an optional `--from-changelog` flag.

### Protocols and Command Surfaces

- [ ] Update
      `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      Step 9 so the preferred cleanup command is described as branch cleanup,
      release stamping, and tracker transition.
- [ ] Add a Step 9 sub-step that extracts or confirms the shipped issue set from
      the released changelog section before running the cleanup helper.
- [ ] Update the manual equivalent to include release-stamp repair guidance
      rather than only branch deletion.
- [ ] Update `.claude/commands/prepare-release.md` and
      `.cursor/commands/prepare-release.md` only if their short summaries need
      the post-merge cleanup wording refreshed.
- [ ] Do not duplicate release-stamping logic in `.agents/skills/prepare-release`
      or `.codex/skills/prepare-release`; both delegate to Protocol 05.

### Tracker Integration Documentation

- [ ] Update
      `docs/workflow/development-workflow/integrations/github-projects.md` to
      document the milestone-per-release convention:
      - milestone names match production version tags, e.g. `v1.2.0`;
      - the cleanup helper creates missing milestones;
      - GitHub Projects can show the built-in Milestone field on board views;
      - release milestones are closed after publication when cleanup succeeds.
- [ ] Update
      `docs/workflow/development-workflow/integrations/issue-tracker.md` with the
      tracker-agnostic release-stamp contract and fail-soft semantics.
- [ ] Update
      `docs/workflow/development-workflow/integrations/linear.md` with the
      default `release/<version>` label convention and optional
      `release_field` / `release_label_prefix` configuration.
- [ ] If Jira, ClickUp, or Notion guides are added before implementation, update
      them with their native configured release field behavior. Otherwise,
      document unsupported providers in `issue-tracker.md` as graceful skips.

### Tests and Smoke Runbooks

- [ ] Add shell tests in
      `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
      for:
      - GitHub milestone lookup and create path;
      - existing milestone reuse;
      - issue assignment command construction;
      - provider `none` no-op;
      - unsupported-provider warning;
      - cleanup summary accounting when stamping succeeds, skips, or fails.
- [ ] Add tests that prove release-stamp failures do not block status-transition
      processing.
- [ ] Add `docs/testing/workflow/release-stamping.smoke-test.md` for a manual
      GitHub issue and milestone smoke test.
- [ ] Run markdown lint for changed protocol, integration, and smoke docs.
- [ ] Run the workflow-lib GitHub Projects shell test harness.

## Testing Strategy

**Test types**: shell unit tests, markdown lint, manual GitHub tracker smoke test.

**Key scenarios to test**:

1. A release cleanup run for issue `#N` creates missing milestone `vX.Y.Z`,
   assigns it to `#N`, transitions `#N` from `Merged` to `Released`, and closes
   the milestone after cleanup.
2. A release cleanup run reuses an existing milestone and does not create a
   duplicate release marker.
3. A release cleanup run with `issue_tracker.provider: none` logs a release-stamp
   skip and does not fail.
4. A release cleanup run with unsupported provider configuration logs provider,
   issue, version, and reason while continuing the rest of cleanup.
5. A GitHub milestone assignment failure increments stamp failure accounting but
   still attempts the issue's `Merged` to `Released` transition.
6. GitHub Projects board views can expose the built-in Milestone field for
   shipped issues.

**Smoke test runbook**:
`docs/testing/workflow/release-stamping.smoke-test.md`

**Regression suite**:
`bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`

## Seed Data

No permanent seed data is required. The smoke test uses a temporary GitHub issue
and release milestone in the configured repository, then removes or closes them
after verification.

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      — describe release stamping in Step 9 and require deriving the explicit
      issue list from the finalized release changelog section.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` —
      document GitHub milestone-per-release setup and project board visibility.
- [ ] `docs/workflow/development-workflow/integrations/issue-tracker.md` —
      document the provider-agnostic release-stamp operation and fail-soft
      behavior.
- [ ] `docs/workflow/development-workflow/integrations/linear.md` — document the
      Linear release label/custom-field configuration keys and MCP/API
      requirement.
- [ ] `.claude/commands/prepare-release.md` and
      `.cursor/commands/prepare-release.md` — refresh post-merge cleanup wording
      if needed.
- [ ] `docs/testing/workflow/release-stamping.smoke-test.md` — add the manual
      smoke runbook.
- [ ] `CHANGELOG.md` — add a `### Added` entry for #829 during implementation,
      using the format below.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The helper stamps the wrong issues because changelog parsing is too broad. | Medium | High | Keep the MVP explicit with `--issues`; Protocol 05 makes the operator derive the list from the finalized release section. |
| Milestone creation or assignment failure blocks a release. | Medium | High | Keep release stamping best effort and separate stamp accounting from status-transition failure semantics. |
| Closing a milestone too early hides issues that failed assignment. | Low | Medium | Close the milestone only after the per-issue loop and report stamp failures separately. |
| Non-GitHub provider docs imply automation that shell scripts cannot perform. | Medium | Medium | Document MCP/API requirements and make unsupported shell paths warn clearly without claiming success. |
| Existing status transition behavior regresses while adding stamping. | Medium | High | Add tests that cover stamping success, skip, failure, and status-transition continuation. |

## Code Samples

The implementation should prefer small Bash helper functions that mirror the
existing status helper shape. Expected call-site shape:

```bash
STAMP_OUT="$(record_release_for_issue_best_effort "$issue" "$RELEASE_VERSION" 2>&1)"
echo "$STAMP_OUT"
```

The helper must print stable warning prefixes so the cleanup script can count
`STAMPED`, `STAMP_SKIPPED`, and `STAMP_FAILED` without parsing provider-specific
error text.

## Implementation Order

1. Add release-version normalization and stamp counters to
   `prepare-release-post-merge-cleanup.sh`.
2. Add provider-routed release-stamp helpers to `workflow-lib.sh`, starting with
   GitHub milestone create/assign/finalize and no-op/warning paths for other
   providers.
3. Wire the cleanup script to stamp each explicit issue before attempting the
   `Merged` to `Released` transition, preserving existing transition semantics.
4. Add shell tests for GitHub milestone behavior, provider routing, summary
   accounting, and stamp-failure continuation.
5. Update Protocol 05 to describe the changelog-derived issue list, release
   stamping, and manual repair path.
6. Update GitHub Projects, generic issue-tracker, and Linear integration docs.
7. Refresh prepare-release command summaries only if needed.
8. Add the release-stamping smoke runbook.
9. Run the workflow-lib test harness, markdown lint, and `git diff --check`.
10. Add this CHANGELOG entry under `[Unreleased]` -> `### Added`:
    `- **Release stamping** (#829): records the production release version on shipped tracker issues using provider-native release markers such as GitHub Milestones, while failing softly for unsupported providers.`
