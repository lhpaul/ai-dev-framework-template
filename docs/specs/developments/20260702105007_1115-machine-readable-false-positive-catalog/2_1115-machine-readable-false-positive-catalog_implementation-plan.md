# Machine-readable False-positive Catalog - Implementation Plan

**Spec**: [Machine-readable False-positive Catalog Spec](1_1115-machine-readable-false-positive-catalog_specs.md)
**Smoke test runbook**: [Machine-readable false-positive catalog smoke test](../../../testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md)

---

## Summary

**Approach**: Add a repository-owned JSON catalog of known Haystack
false-positive rules and teach `haystack-reviewer.sh` to apply it while
normalizing structured findings. Matching findings will keep their original
finding context, receive a `known-false-positive` disposition with rule
rationale, and remain non-blocking. Update the reviewer-loop summary renderer so
the disposition is visible to humans and delegated audit runs.

**Estimated complexity**: M

**Rationale**: The data model is small, but the change touches workflow review
classification, structured JSON output, summary rendering, and parser-risk
matching behavior. The implementation needs focused edge-case tests to avoid
masking real findings with overly broad rules.

**Dependencies**: #1113 and #1114 must be merged first. #1113 provides the
structured Haystack finding arrays; #1114 makes advisory findings visible in the
reviewer-loop summary and disposition flow.

## Template-Fit Check

`.ai-dev-workflow.yaml` sets `template.is_template: true`. The approved spec
passes the template-fit check because it improves this template repository's
workflow tooling and does not depend on any downstream application framework.

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `ddf9fa1` |
| Existing known false-positive guidance | `rg -n "false positive\|false-positive\|Rules violation\|hotfix backport\|CHANGELOG structure" docs/workflow/development-workflow/integrations/haystack-triage.md scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/tests/test-haystack-reviewer.sh REVIEW.md` | 32 matching lines. Guidance exists in `haystack-triage.md`, script comments, `REVIEW.md`, and tests, but not as a machine-readable catalog. |
| Structured finding output consumers | `rg -n "NORMALIZED_FINDINGS_JSON\|ADVISORY_FINDINGS_JSON\|BLOCKING_FINDINGS_JSON\|render_structured_advisory_entries\|POLICY_DISPOSITION" scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-haystack-reviewer.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | 65 matching lines. The normalization point is in `haystack-reviewer.sh`; the summary renderer is `render_structured_advisory_entries` in `pr-review-loop.sh`. |
| Existing workflow smoke runbooks | `find docs/testing/workflow -maxdepth 1 -type f -name '*haystack*' -o -name '*review*.smoke-test.md' \| sort` | Existing review/Haystack runbooks include `720-haystack-triage-review-platform.smoke-test.md` and `929-calibrate-haystack-agent-doc-mirror-rules.smoke-test.md`; add a focused #1115 runbook rather than expanding an older one. |
| Approved spec artifact | `find docs/specs/developments/20260702105007_1115-machine-readable-false-positive-catalog -maxdepth 1 -type f -print \| sort` | The folder currently contains the approved spec only; this plan adds the plan artifact beside it. |

## Layer-by-Layer Changes

### Database / Data Layer

- Not applicable. This workflow tooling change stores no runtime or user data
  and does not use the repository database placeholder docs.

### Backend / API

- [ ] Add `scripts/development-workflow/haystack-false-positives.json` as the
      maintained machine-readable catalog.
      - Include one entry each for regular CHANGELOG structure false positives,
        hotfix-backport CHANGELOG false positives, and mirror-guidance stale
        advisories.
      - Each entry must include a stable `id`, user-facing `label`, `category`,
        regex match fields for `summary`, `detail`, and path-style evidence,
        and a short `rationale`.
      - Use JSON, not YAML, so the existing Bash/JQ reviewer can parse the
        catalog without introducing a new parser dependency.
- [ ] Update `scripts/development-workflow/haystack-reviewer.sh`.
      - Resolve the catalog path from `HAYSTACK_FALSE_POSITIVES_FILE` when set,
        otherwise from `scripts/development-workflow/haystack-false-positives.json`.
      - Validate that the catalog is parseable JSON and contains an array.
      - During `NORMALIZED_FINDINGS_JSON` construction, evaluate each finding
        independently against the catalog.
      - When a finding matches, keep the original category, summary, detail,
        path, line, and fix hint fields, add `disposition:
        known-false-positive`, `disposition_rule`, and `disposition_rationale`,
        and force the workflow severity to advisory.
      - When the catalog is missing, empty, malformed, or contains an invalid
        rule, do not apply any false-positive disposition; preserve the original
        severity and emit a warning to stderr.
      - Do not let a catalog rule match an unknown category unless the rule
        explicitly names that unknown category. Existing unknown-category
        safe-fail behavior must remain intact for unmatched findings.
- [ ] Update `scripts/development-workflow/pr-review-loop.sh`.
      - Extend `render_structured_advisory_entries` to show
        `Known false positive` disposition details when structured findings
        include `disposition=known-false-positive`.
      - Keep existing category, summary, detail, location, and fix-hint rendering
        unchanged for findings without a disposition.
      - Do not change advisory-disposition-required aggregate behavior from
        #1114; a known false-positive advisory is still visible and can be
        documented in the summary.

### Shared Packages / Libraries

- Not applicable. The change uses existing shell and `jq` dependencies already
  required by `haystack-reviewer.sh`.

### Frontend / UI

- Not applicable. There is no browser UI.

### Infrastructure / Configuration

- [ ] Do not add `.ai-dev-workflow.yaml` schema fields in this item. #1116 owns
      Haystack configuration in repository workflow config.
- [ ] Allow local catalog override through `HAYSTACK_FALSE_POSITIVES_FILE` for
      tests and downstream experiments, but keep the shipped catalog as the
      default source of truth.

## Parser-risk Classification

Parser-risk applies. The implementation will evaluate reviewer-provided
structured text against regular-expression catalog rules. The plan therefore
requires concrete edge-case coverage in `test-haystack-reviewer.sh`.

### Parser-risk Edge-case Enumeration

1. **CHANGELOG positive match**: category is `Rules violation`, the summary or
   detail references `keep-changelog-unreleased-structure-canonical`, and the
   path-style evidence points at `CHANGELOG.md`.
2. **Hotfix backport positive match**: category is `Rules violation`, the
   summary or detail mentions hotfix/backport CHANGELOG structure, and the path
   points at `CHANGELOG.md`.
3. **Mirror guidance positive match**: category is `Rules violation`, the
   summary or detail references agent-doc mirror guidance that is known to be a
   stale advisory, and path evidence points at agent documentation or is absent.
4. **Negative lookalike**: category is `Rules violation`, but the text describes
   a real workflow-contract violation that does not match any catalog rule. It
   remains advisory under existing category mapping but has no
   `known-false-positive` disposition.
5. **Unknown category safe-fail**: an unknown category with CHANGELOG-like text
   does not match the catalog unless a rule explicitly names that category; it
   remains blocking.
6. **Multiple findings**: one matching known false positive and one unrelated
   advisory are classified independently; only the matching finding receives the
   disposition fields.
7. **Malformed catalog**: an override file with invalid JSON produces no
   false-positive dispositions and preserves original severity.
8. **Boundary text**: summaries/details containing regex metacharacters, pipes,
   equals signs, quotes, and newlines remain valid single-line JSON output after
   classification.

### Parser-risk Unit Test Mapping

Add tests to `scripts/development-workflow/tests/test-haystack-reviewer.sh`:

| Edge case | Test expectation |
| --- | --- |
| CHANGELOG positive match | `ADVISORY_FINDINGS_JSON[0].disposition == "known-false-positive"` and `.disposition_rule` is the CHANGELOG rule id. |
| Hotfix backport positive match | The hotfix-backport fixture receives `known-false-positive` and stays `RESULT=clean`. |
| Mirror guidance positive match | The mirror-guidance fixture receives `known-false-positive` with the mirror rule id. |
| Negative lookalike | The finding stays advisory but has no `disposition` field. |
| Unknown category safe-fail | `RESULT=needs_fixes`, `BLOCKING_COUNT=1`, and no known false-positive disposition is emitted. |
| Multiple findings | The first matching finding has disposition fields; the unrelated advisory does not. |
| Malformed catalog | Override `HAYSTACK_FALSE_POSITIVES_FILE` to invalid JSON; output preserves the existing classification and has no disposition fields. |
| Boundary text | JSON remains parseable and the escaped summary/detail/fix hint values are preserved after classification. |

Suppression semantics are not introduced. There are no inline directives, no
comment-based suppressions, and no multi-suppression behavior.

### Concurrent-event-source Classification

Not applicable. The change does not add listeners, timers, async queues, or
shared mutable state across concurrent execution contexts.

### Cross-cutting Checklist Classification

Not applicable. The change does not introduce a new checklist category in
planning, implementation, or review protocols.

## Testing Strategy

**Test types**: Unit, shell lint, workflow guard lint, markdown lint, smoke
runbook.

**Key scenarios to test**:

1. Cataloged CHANGELOG false positives are marked
   `known-false-positive` and remain non-blocking. Maps to AC-1, AC-2, AC-3,
   AC-7.
2. Cataloged hotfix-backport false positives are marked
   `known-false-positive` and remain non-blocking. Maps to AC-2, AC-3, AC-7.
3. Cataloged mirror-guidance stale advisories are marked independently without
   affecting unrelated findings. Maps to AC-2, AC-4, AC-5.
4. Non-matching findings keep their normal reviewer classification. Maps to
   AC-4.
5. Reviewer-loop summaries display known false-positive disposition rationale
   from structured advisory findings. Maps to AC-2 and AC-6.
6. Documentation explains the catalog format and relationship to Helm's
   false-positive documentation pattern. Maps to AC-6.

**Smoke test runbook**:
`docs/testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `shellcheck --severity=warning -x scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-haystack-reviewer.sh scripts/development-workflow/tests/test-pr-review-loop.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/integrations/haystack-triage.md" "docs/testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/workflow/development-workflow/integrations/haystack-triage.md docs/testing/workflow/1115-machine-readable-false-positive-catalog.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
- `jq -e 'type == "array" and all(.[]; has("id") and has("category") and has("rationale"))' scripts/development-workflow/haystack-false-positives.json`
- `git diff --check`

## Seed Data

No persisted seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock Haystack output | CHANGELOG, hotfix-backport, mirror-guidance, unrelated advisory, unknown category, malformed catalog, and escaped-text fixtures | `scripts/development-workflow/tests/test-haystack-reviewer.sh` |
| Structured advisory summary fixture | Finding object containing `disposition`, `disposition_rule`, and `disposition_rationale` | `scripts/development-workflow/tests/test-pr-review-loop.sh` |

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` -
      replace the prose-only known false-positive guidance with the catalog
      contract, catalog location, rule fields, override behavior, and Helm
      format cross-reference.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` entry during implementation using
      the literal format below.
- [ ] `AGENTS.md` - no update required; this feature does not change top-level
      workflow commands, branching policy, or repository conventions.
- [ ] `docs/project/*` - no update required; the project docs are placeholders
      and this feature is specific to development-workflow review tooling.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Over-broad catalog rule masks a real finding | Medium | High | Require category plus text/path predicates, add negative lookalike tests, and preserve unmatched unknown-category safe-fail behavior. |
| Catalog parse failure changes review outcomes unexpectedly | Low | Medium | Treat malformed catalog as "no matches"; preserve original severity and emit a warning. |
| Summary renderer hides the original finding | Low | Medium | Keep existing category, summary, detail, location, and fix-hint rendering and append disposition detail rather than replacing the finding. |
| JSON output becomes invalid after adding disposition fields | Low | High | Add escaped-text tests and validate `ADVISORY_FINDINGS_JSON` with `jq`. |

## Code Samples

Illustrative catalog entry shape; adapt during implementation:

```json
{
  "id": "changelog-keep-changelog-unreleased-structure",
  "label": "CHANGELOG structure false positive",
  "category": "Rules violation",
  "summary_patterns": ["keep-changelog-unreleased-structure-canonical"],
  "detail_patterns": ["CHANGELOG", "\\[Unreleased\\]"],
  "path_patterns": ["(^|/)CHANGELOG\\.md$"],
  "rationale": "Haystack can misread correctly nested Keep a Changelog entries from PR diffs; markdownlint and the duplicate-header check are authoritative."
}
```

## Implementation Order

1. Add `scripts/development-workflow/haystack-false-positives.json`.
   - Include the three initial rules: CHANGELOG regular PR, hotfix-backport
     CHANGELOG, and mirror-guidance stale advisory.
   - Validate the file with:
     `jq -e 'type == "array" and all(.[]; has("id") and has("category") and has("rationale"))' scripts/development-workflow/haystack-false-positives.json`
2. Update `scripts/development-workflow/haystack-reviewer.sh`.
   - Add a catalog-loading helper that returns a compact JSON array or `[]`
     with a warning on missing/malformed data.
   - Add a finding-match helper in the existing `jq` normalization block.
   - Add disposition fields only to matching findings.
   - Preserve existing count derivation from `ADVISORY_FINDINGS_JSON` and
     `BLOCKING_FINDINGS_JSON`.
3. Update `scripts/development-workflow/pr-review-loop.sh`.
   - Extend `render_structured_advisory_entries` so known false-positive
     dispositions appear in the Automated Reviewer Loop Summary.
   - Keep the existing structured advisory rendering for non-matching findings.
4. Update `scripts/development-workflow/tests/test-haystack-reviewer.sh`.
   - Add the parser-risk unit tests listed above.
   - Use `HAYSTACK_FALSE_POSITIVES_FILE` to test malformed and alternate
     catalog behavior without modifying the shipped catalog during the test.
5. Update `scripts/development-workflow/tests/test-pr-review-loop.sh`.
   - Add one summary-rendering assertion for `known-false-positive`
     disposition detail.
6. Update `docs/workflow/development-workflow/integrations/haystack-triage.md`.
   - Document the catalog file, fields, matching semantics, malformed-catalog
     behavior, and Helm false-positive documentation cross-reference.
7. Update the smoke test runbook:
   - Verify catalog shape.
   - Run the focused Haystack reviewer tests.
   - Run the reviewer-loop summary test coverage.
   - Verify docs and CHANGELOG lint.
8. Update `CHANGELOG.md` under `[Unreleased]`:
   - `- **Haystack false-positive catalog** (#1115): Added a machine-readable known false-positive catalog for recurring Haystack findings and surfaced matched dispositions in reviewer output.`
9. Run the full verification list from **Testing Strategy** and record results
   in the implementation PR body.

## Cross-section Consistency Self-check

- Catalog file path is consistently
  `scripts/development-workflow/haystack-false-positives.json`.
- Override environment variable is consistently
  `HAYSTACK_FALSE_POSITIVES_FILE`.
- Disposition value is consistently `known-false-positive`.
- Test files are consistently `test-haystack-reviewer.sh` and
  `test-pr-review-loop.sh`.
- The implementation PR, not this plan PR, updates `CHANGELOG.md`.
