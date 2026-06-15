# Calibrate Haystack Agent-Doc Mirror Rules — Implementation Plan

**Spec**: [docs/specs/developments/20260615110334_929-calibrate-haystack-agent-doc-mirror-rules/1_929-calibrate-haystack-agent-doc-mirror-rules_specs.md](1_929-calibrate-haystack-agent-doc-mirror-rules_specs.md)
**Smoke test runbook**: [docs/testing/workflow/929-calibrate-haystack-agent-doc-mirror-rules.smoke-test.md](../../../testing/workflow/929-calibrate-haystack-agent-doc-mirror-rules.smoke-test.md)

---

## Summary

**Approach**: Calibrate the Haystack mirror guidance around the repository's actual agent-documentation surface map, then keep the reviewer loop and docs aligned with the new actionability split. The implementation should tolerate intentional tool-specific front matter differences, stop treating absent Cursor skills as required mirrors, and preserve the current fail-closed / advisory-only behavior for stale or false mirror findings.

**Estimated complexity**: M

**Rationale**: This is a multi-file workflow change across rule prompts, reviewer normalization, docs, and regression tests, but it does not require schema, data, or product-layer changes.

**Dependencies**: None

---

## Verification Log

> Record reproducible plan-time verification commands that influenced scope, counts, or file lists. Include repo revision and concrete results.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `784c613` |
| Agent / skill surface map | `rg --files .claude/agents .cursor/agents .codex/skills | sort` | 13 Claude agent docs, 13 Cursor agent docs, 27 Codex skill files; no `.cursor/skills` directory exists |
| Cursor skills absence | `if [ -d .cursor/skills ]; then echo yes; else echo no; fi` | `no` |
| Existing Haystack mirror guidance | `rg -n "keep-agent-docs-in-sync|sync-integration-docs-with-script-behavior" .haystack/pr-rules.yml` | Existing mirror-related rules are already present and should be refined, not duplicated |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Update `.haystack/pr-rules.yml` so the mirror guidance uses the actual repository surface map, compares semantic workflow content instead of byte-for-byte equality when tool-specific front matter differs, and treats absent `.cursor/skills` surfaces as intentionally out of scope.
- [ ] Update `.haystack/review-policy.md` so mirror-related findings are described as actionable drift only when they point at a real repository surface mismatch, and otherwise remain advisory / non-actionable.
- [ ] Update `scripts/development-workflow/haystack-reviewer.sh` only where needed to keep the finding classification and emitted disposition stable if the rule text or categories change.
- [ ] Update `scripts/development-workflow/pr-review-loop.sh` only where needed to keep mirror-related dispositions visible in the PR summary without turning stale advisories into blockers.

---

## Testing Strategy

**Test types**: Unit, Smoke

**Key scenarios to test**:

1. A changed Claude command and its Cursor command counterpart are evaluated semantically, and front matter differences do not register as drift. Maps to AC-2.
2. The mirror check uses the live repository surface map and does not require surfaces that are absent from the repository. Maps to AC-1.
3. A missing `.cursor/skills` surface is not reported as a required mirror. Maps to AC-3.
4. Claude skills, Codex skills, and the existing agent-doc surface map are all covered by fixtures. Maps to AC-4.
5. Reviewer output names the affected surfaces and labels a real mismatch as actionable mirror drift. Maps to AC-5.
6. Reviewer output labels a stale or false mirror finding as non-actionable and explains why it is not required. Maps to AC-6.
7. The calibrated output gives maintainers enough context to fix real drift without reading implementation internals. Maps to AC-7.

**Smoke test runbook**: `docs/testing/workflow/929-calibrate-haystack-agent-doc-mirror-rules.smoke-test.md`

### Parser-risk addendum

**Edge-case enumeration**

- Boundary-character variants: exact surface paths only. `agents/developer.md` is in scope; lookalikes such as `agents/developer.md.bak`, `agents-backup/developer.md`, and `cursor/agent` are not.
- Negative cases: an absent `.cursor/skills` tree must not become a required mirror, and a backup or archive path must not be counted as a real mirror surface.
- Multiple occurrences on one line: a single review finding may mention both a real mirror pair and an intentionally absent surface; the output must keep the actionable and non-actionable parts separate.
- Nested / overlapping constructs: a Claude command and its Cursor counterpart may differ in tool-specific front matter while still sharing the same workflow body; the rule must compare the shared behavior, not exact file bytes.
- Normative flexibility: not applicable beyond exact path existence and semantic body equivalence. There is no markdown-fence or regex-normalization rule to relax here.

**Unit test mapping**

- `scripts/development-workflow/tests/test-haystack-reviewer.sh`
  - `mirror_front_matter_diff_remains_advisory`: front matter differs, workflow body matches, result stays advisory.
  - `missing_cursor_skills_not_required`: absent `.cursor/skills` mirror is not treated as a required failure.
  - `surface_lookalike_does_not_match`: backup or substring lookalikes do not count as real mirror surfaces.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
  - `mirror_finding_summary_keeps_actionable_vs_nonactionable_separate`: the PR summary comment preserves the distinction between actionable drift and stale advisories when both appear in one run.

---

## Seed Data

None. This feature calibrates workflow rules, docs, and review output; it does not depend on application data.

---

## Documentation Updates

> Consider project documentation in `docs/`: `docs/project/`, `docs/best-practices/`, `AGENTS.md`, and any feature- or domain-specific docs. List each file that the developer must update after implementation and what to change. Use "None" only when the feature truly affects no project docs. These updates are NOT performed during Plan Ready — only listed here for the developer to execute.

- [ ] `docs/workflow/development-workflow/integrations/haystack.md` — document the surface-map-based mirror guidance and where the calibrated rule lives.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` — document the actionable vs non-actionable mirror finding split and how the reviewer output should be interpreted.
- [ ] `REVIEW.md` — add reviewer guidance for distinguishing real mirror drift from stale or false advisories.
- [ ] `AGENTS.md` — none; the repository-wide workflow contract does not need a new agent command or branching rule for this feature.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Haystack still treats absent surfaces or tool-specific front matter as drift | Medium | High | Tighten the rule prompt to name the repository surface map explicitly and add fixture coverage for absent Cursor skills and front-matter-only differences |
| Reviewer summary text becomes noisier without adding signal | Medium | Medium | Keep the mirror finding advisory-only and make the summary wording reflect only the actionable / non-actionable split |
| Docs and reviewer behavior drift apart | Low | High | Update the integration docs and `REVIEW.md` in the same PR as the rule and script changes |

---

## Implementation Order

1. Update `.haystack/pr-rules.yml` to define the calibrated mirror behavior against the live surface map, including the semantic comparison rule for command docs and the explicit non-requirement for absent `.cursor/skills` surfaces.
2. Update `.haystack/review-policy.md` so the reviewer vocabulary distinguishes actionable mirror drift from stale or false advisories without changing the existing advisory/blocking boundary.
3. Update `scripts/development-workflow/haystack-reviewer.sh` and `scripts/development-workflow/pr-review-loop.sh` only where needed to keep the reported disposition stable and readable after the rule text changes.
4. Extend `scripts/development-workflow/tests/test-haystack-reviewer.sh` with fixtures for front-matter-only differences, absent Cursor skills, and surface lookalikes.
5. Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` so the PR summary comment preserves the actionable / non-actionable distinction when both kinds of findings are present.
6. Update `docs/workflow/development-workflow/integrations/haystack.md`, `docs/workflow/development-workflow/integrations/haystack-triage.md`, and `REVIEW.md` to match the calibrated rule behavior.
7. Run the targeted unit tests and the smoke test runbook, then confirm the generated outputs match the acceptance criteria before opening the draft plan PR.
