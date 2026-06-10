# Simplify Review Config to Two-Phase Draft/Ready Model - Implementation Plan

**Spec**: Refactor item #868 - tracker brief only, no product spec
**Smoke test runbook**: [868-review-config-two-phase-model.smoke-test.md](../../../testing/workflow/868-review-config-two-phase-model.smoke-test.md)

---

## Summary

**Approach**: Replace the overlapping `review.internal_reviewers`, `review.platforms`, and `review.phase_after_clean` configuration model with explicit lifecycle buckets under `review.on_draft` and `review.on_ready`. Keep a one-release compatibility layer that maps legacy config into the new model, then update `pr-review-loop.sh`, orchestration protocols, docs, and tests to use the lifecycle names.

**Estimated complexity**: L

**Rationale**: This touches shell config parsing, reviewer-loop scheduling, protocol language, integration docs, default template config, and test fixtures. The compatibility layer and parser-risk cases make it larger than a docs-only refactor.

**Dependencies**: None.

---

## Brief Objectives

1. Adopters can configure review with two lifecycle phases only; no reviewer appears in more than one bucket.
2. Draft-phase GitHub reviewers run while the PR is draft.
3. Ready-phase GitHub reviewers run only after draft phase is clean and `gh pr ready` has been called.
4. Legacy config using `internal_reviewers`, `platforms`, and `phase_after_clean` continues to work for one release through aliases or migration.
5. Protocols and integration docs describe the new model without presenting `phase_after_clean` as a third reviewer type.

---

## Target Configuration Semantics

Use this template default, preserving the repository's current Codex-first internal reviewer:

```yaml
review:
  on_draft:
    runner:
      - codex
    github:
      - pr-agent
  on_ready:
    github:
      - haystack
```

| New key                  | PR state         | Purpose                                                            |
| ------------------------ | ---------------- | ------------------------------------------------------------------ |
| `review.on_draft.runner` | Draft            | In-runner internal review gate from Protocol 91 Step 7a            |
| `review.on_draft.github` | Draft            | GitHub/App/CLI reviewers that can safely evaluate draft PRs        |
| `review.on_ready.github` | Ready for review | GitHub/App/CLI reviewers that run only after draft gates are clean |

Compatibility mapping for one transition release:

| Legacy key                    | New effective bucket                                                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------- |
| `review.internal_reviewers`   | `review.on_draft.runner`                                                                       |
| `review.platforms`            | `review.on_ready.github` when `phase_after_clean` is absent                                    |
| `review.platforms` + phase    | `platforms - phase_after_clean` -> `on_draft.github`; `phase_after_clean` -> `on_ready.github` |
| `review.phase_after_clean`    | Alias only; emit deprecation warning and map to `review.on_ready.github`                       |
| `--pre-after-clean-only` flag | Compatibility alias for the new draft-GitHub-only execution mode                               |

---

## Verification Log

| Check                         | Command / query                                                                                                                                                                                                                                      | Result                                                                                                                                                           |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repo revision                 | `git rev-parse --short HEAD`                                                                                                                                                                                                                         | `e91a536`                                                                                                                                                        |
| Current repo config           | `rg -n "internal_reviewers\|platforms\|phase_after_clean\|review:" .ai-dev-workflow.yaml`                                                                                                                                                            | Current config uses `review.platforms: [pr-agent, haystack]`, `review.phase_after_clean: [haystack]`, and `review.internal_reviewers: [codex]`.                  |
| Review-loop config references | `rg -n "internal_reviewers\|platforms\|phase_after_clean\|pre-after-clean\|PHASE_AFTER_CLEAN" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/workflow-lib.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | Core shell parsing lives in `workflow-lib.sh`; runtime scheduling and telemetry live in `pr-review-loop.sh`; harness coverage lives in `test-pr-review-loop.sh`. |
| Docs and agent references     | `rg -n "internal_reviewers\|platforms\|phase_after_clean\|pre-after-clean\|PHASE_AFTER_CLEAN" AGENTS.md docs/workflow/development-workflow .claude .cursor .codex .agents -g "*"`                                                                    | References appear in AGENTS, README, protocols 91/93, review-platform integration docs, Haystack/Claude/Copilot guides, and agent/command wrappers.              |
| Parser-risk classification    | `rg -n "workflow_config_review_platforms\|workflow_config_review_phase_after_clean_platforms" scripts/development-workflow/workflow-lib.sh`                                                                                                          | Parser-risk applies: YAML-like config scanning functions will be added or modified.                                                                              |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] None. No database or seed data changes.

### Backend / API

- [ ] None. No product API changes.

### Shared Workflow Scripts

- [ ] `scripts/development-workflow/workflow-lib.sh` - add lifecycle-aware config readers:
  - `workflow_config_review_on_draft_runner`
  - `workflow_config_review_on_draft_github`
  - `workflow_config_review_on_ready_github`
  - compatibility helpers that map legacy keys into the lifecycle buckets.
- [ ] `scripts/development-workflow/pr-review-loop.sh` - replace internal scheduling terms with draft/ready lifecycle terms while preserving behavior:
  - load `on_draft.github` and `on_ready.github` from the new helpers;
  - keep `--pre-after-clean-only` as a deprecated alias for the draft-GitHub-only mode;
  - add a clearer preferred flag name, for example `--draft-github-only`;
  - replace or supplement `PHASE_AFTER_CLEAN_*` telemetry with lifecycle telemetry such as `READY_PHASE_*`, while preserving old telemetry keys for one release if existing tests or metrics still consume them;
  - ensure `gh pr ready` is called exactly once at the draft/ready boundary.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` - update config parsing, membership, filtering, telemetry, and summary tests for new and legacy config forms.

### Configuration

- [ ] `.ai-dev-workflow.yaml` - replace the default review config with `review.on_draft` / `review.on_ready` and update inline comments.
- [ ] `.ai-dev-workflow.yaml` - bump `schema_version` for the new canonical review config shape while preserving one-release legacy parsing for `schema_version: 1` repositories.
- [ ] `.tmp/template-config.json` compatibility remains documented as a local override path for runner reviewers. The implementation should either preserve the old `overrides.review.internal_reviewers` key as an alias or document the local override migration to `overrides.review.on_draft.runner`.

### Protocols And Agent Guidance

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` - update Step 7a and review-loop lifecycle language:
  - use `review.on_draft.runner` for internal runner reviewers;
  - use `review.on_draft.github` for draft-compatible external reviewers;
  - use `review.on_ready.github` for ready-phase reviewers;
  - remove phrasing that makes `phase_after_clean` sound like a third reviewer type;
  - keep a migration note for legacy keys.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` - update reviewer-loop protocol, command examples, lifecycle telemetry, and compatibility aliases.
- [ ] `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` - align internal reviewer config names and draft/ready boundary instructions.
- [ ] `.claude/agents/automated-reviewer-loop.md`, `.cursor/agents/automated-reviewer-loop.md`, `.claude/commands/run-reviewer-loop.md`, and `.cursor/commands/run-reviewer-loop.md` - update command guidance and config key references.
- [ ] `.codex/skills/workflow-sync-template/SKILL.md` - update references to `review.internal_reviewers` if it remains mentioned in sync-template post-PR guidance.
- [ ] `AGENTS.md` and `docs/workflow/development-workflow/README.md` - update repository-level explanation and examples.

### Integration Documentation

- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` - make two-phase lifecycle config the canonical example.
- [ ] `docs/workflow/development-workflow/integrations/haystack.md` and `docs/workflow/development-workflow/integrations/haystack-triage.md` - describe Haystack as an `on_ready.github` reviewer.
- [ ] `docs/workflow/development-workflow/integrations/claude-code-action.md` - replace phase-after-clean examples with `on_ready.github` examples and clarify that Claude Code Action is a GitHub reviewer, not a runner reviewer.
- [ ] `docs/workflow/development-workflow/integrations/copilot.md` - replace phase-after-clean examples with `on_ready.github`.
- [ ] Other integration docs that only show `review.platforms` (for example Greptile) should be updated to the new `on_draft.github` or `on_ready.github` placement according to draft support.

### Documentation Updates For Implementation

- [ ] `CHANGELOG.md` - add a `[Unreleased]` `### Changed` entry:
  - `- **Two-phase review config** (#868): replaces overlapping reviewer config keys with explicit draft and ready lifecycle buckets while preserving legacy aliases for one transition release.`
- [ ] `docs/workflow/development-workflow/README.md` - update configuration examples and helper descriptions.
- [ ] `AGENTS.md` - update the repository-specific workflow provider summary.

---

## Testing Strategy

**Test types**: Shell harness, markdown lint, smoke/manual verification.

**Key scenarios to test**:

1. New two-phase config parses correctly:
   - `on_draft.runner` -> internal reviewer list.
   - `on_draft.github` -> draft GitHub reviewers.
   - `on_ready.github` -> ready GitHub reviewers.
2. Legacy config maps correctly for one transition release:
   - `internal_reviewers` maps to `on_draft.runner`.
   - `platforms + phase_after_clean` maps to draft GitHub reviewers plus ready GitHub reviewers.
   - `platforms` without `phase_after_clean` preserves current behavior.
3. Duplicate reviewer placement is rejected or warned clearly when the same reviewer appears in more than one new bucket, including duplicates across runner and GitHub buckets.
4. `--draft-github-only` runs only draft GitHub reviewers.
5. `--pre-after-clean-only` remains a deprecated alias for `--draft-github-only`.
6. `gh pr ready` is called once at the boundary before ready GitHub reviewers.
7. Summary comments and telemetry use lifecycle language while old `PHASE_AFTER_CLEAN_*` keys remain available or are intentionally migrated with tests.
8. Config omission still produces the existing skipped/no-platform behavior with updated wording.

**Smoke test runbook**: `docs/testing/workflow/868-review-config-two-phase-model.smoke-test.md`

**Regression suite**: update `scripts/development-workflow/tests/test-pr-review-loop.sh`; run the full harness.

### Parser-risk Addendum

**Edge-case enumeration**:

1. New config with all three lifecycle lists populated.
2. New config with empty `on_draft.github` and non-empty `on_ready.github`.
3. New config with duplicate reviewer across any lifecycle buckets, including `on_draft.runner`, `on_draft.github`, and `on_ready.github`.
4. Legacy config with `platforms` and `phase_after_clean`.
5. Legacy config with `platforms` only.
6. Legacy config with `internal_reviewers` only.
7. Mixed config where new lifecycle keys and legacy keys both exist; new lifecycle keys should win or the script should warn and choose one deterministic source.
8. Comments and blank lines inside nested YAML lists.
9. Unsupported reviewer name in one lifecycle bucket.
10. Local `.tmp/template-config.json` override for draft runner reviewers.

**Unit test mapping**: Add or update tests in `scripts/development-workflow/tests/test-pr-review-loop.sh`:

- `review_on_draft_runner_parser`
- `review_on_draft_github_parser`
- `review_on_ready_github_parser`
- `legacy_platforms_phase_mapping`
- `legacy_platforms_without_phase_mapping`
- `duplicate_lifecycle_reviewer_warning` - covers duplicate reviewers across all lifecycle buckets, including runner-vs-GitHub duplication.
- `draft_github_only_filters_ready_reviewers`
- `pre_after_clean_only_alias`
- `mixed_new_and_legacy_config_precedence`
- `local_runner_override_compatibility`

**Suppression semantics**: Not applicable. This change does not add inline suppressions.

### Concurrent-Event-Source Addendum

- **Shared mutable state guards**: Not applicable; reviewer loop execution remains single-process shell control flow.
- **Re-entrancy / in-flight tracking**: Existing single-instance lock behavior in `pr-review-loop.sh` remains the guard; no new concurrent execution path is introduced.
- **Event deduplication**: Not applicable; no new event listener.
- **Listener and resource cleanup**: Not applicable; no long-lived listener.
- **Race conditions at initialization**: Not applicable; config is read before reviewer execution.
- **Race conditions at teardown**: Not applicable; no teardown listener.
- **Error propagation across async boundaries**: Existing reviewer companion exit-code contracts remain authoritative.

---

## Seed Data

None.

---

## Risks & Mitigations

| Risk                                                                         | Likelihood | Impact | Mitigation                                                                                                       |
| ---------------------------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------- |
| Legacy repositories break because old keys stop parsing                      | Medium     | High   | Keep one-release alias mapping and tests for every legacy shape.                                                 |
| Draft/ready lifecycle changes accidentally run Haystack before `gh pr ready` | Medium     | High   | Add harness tests for reviewer ordering and ready-boundary behavior.                                             |
| Config parser silently drops nested YAML values                              | Medium     | High   | Treat as parser-risk and add edge-case tests for comments, blank lines, empty lists, and mixed config.           |
| Documentation keeps using `phase_after_clean` as a canonical concept         | Medium     | Medium | Live-search docs/agents/skills and update every canonical reference; leave only compatibility/deprecation notes. |
| Telemetry consumers lose compare-mode signal                                 | Low        | Medium | Preserve old telemetry keys for one transition release or add replacement lifecycle telemetry and tests.         |

---

## Code Samples

Illustrative target config only; implementation must adapt names to the final helper/API choices:

```yaml
review:
  on_draft:
    runner:
      - codex
    github:
      - pr-agent
  on_ready:
    github:
      - haystack
```

---

## Implementation Order

1. Add lifecycle-aware config readers in `workflow-lib.sh`, with legacy mapping helpers and clear deprecation warnings.
2. Update `pr-review-loop.sh` to consume draft/ready GitHub reviewer lists, add the preferred draft-only flag, preserve `--pre-after-clean-only` as an alias, and keep or migrate telemetry with compatibility tests.
   - Enforce the "call `gh pr ready` once" guarantee with an explicit ready-transition helper/guard equivalent to today's `ensure_pr_ready_for_after_clean` draft-state check, backed by the existing per-PR single-instance lock in `pr-review-loop.sh`.
3. Update `scripts/development-workflow/tests/test-pr-review-loop.sh` for parser edge cases, lifecycle filtering, legacy mapping, duplicate detection, ready-transition guard behavior, and telemetry.
4. Update `.ai-dev-workflow.yaml` to the new two-phase default using current reviewer choices: `codex`, `pr-agent`, and `haystack`, and bump `schema_version` for the new canonical config shape.
5. Update Protocol 91 and Protocol 93 to describe the new lifecycle model, ready boundary, and legacy compatibility.
6. Update AGENTS, README, integration docs, and agent/command wrappers found in the Verification Log.
7. Add the `CHANGELOG.md` entry under `[Unreleased]` / `### Changed`:
   - `- **Two-phase review config** (#868): replaces overlapping reviewer config keys with explicit draft and ready lifecycle buckets while preserving legacy aliases for one transition release.`
8. Run validation:
   - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/*.md" "docs/workflow/development-workflow/integrations/*.md" "docs/testing/workflow/868-review-config-two-phase-model.smoke-test.md" "CHANGELOG.md"`
   - `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/868-review-config-two-phase-model.smoke-test.md CHANGELOG.md`
   - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
9. Execute the smoke test runbook and record the results in the implementation PR.
