# Retrospective: Template-Aware Backlog Cross-Reference with Version Tracking — Implementation Plan

**Spec**: [1_retro-template-backlog-crossref_specs.md](./1_retro-template-backlog-crossref_specs.md)
**Smoke test runbook**: [retro-template-backlog-crossref.smoke-test.md](../../../testing/workflow/retro-template-backlog-crossref.smoke-test.md)

---

## Summary

**Approach**: Add two optional fields (`template.repository` and `template.last_synced_version`) to `.ai-dev-workflow.yaml` with comments explaining their purpose. Extend the retrospective protocol Step 3 with a new substep 3b that classifies each finding against three buckets when the template repository is configured (the existing `### 3b. Categorization taxonomy` becomes `### 3c.` and the forward-reference at line 125 of the protocol is updated accordingly). Update the sync-template skill (all three carrier files: `.claude/commands/sync-template.md`, `.cursor/commands/sync-template.md`, `.codex/skills/workflow-sync-template/SKILL.md`) to record the last-synced version after a successful sync. Document the new config fields in `docs/workflow/development-workflow/README.md`.

**Estimated complexity**: S

**Rationale**: All changes are documentation and configuration only — no code execution paths, no schema migrations, no UI components. The largest change is a new subsection (Step 3b) inserted into the retrospective protocol and a small inline update to the sync-template skill. No existing logic is removed; everything new is guarded by an explicit opt-in condition.

**Dependencies**: None

---

## Verification Log

| Check                                   | Command / query                                                                   | Result                                 |
| --------------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------- |
| Repo revision                           | `git rev-parse --short HEAD`                                                      | `a314508`                              |
| Retrospective protocol line count       | `wc -l docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` | 350 lines                              |
| Sync-template Claude command line count | `wc -l .claude/commands/sync-template.md`                                         | 296 lines                              |
| Sync-template Cursor command line count | `wc -l .cursor/commands/sync-template.md`                                         | 287 lines                              |
| Codex sync-template skill files         | `ls .codex/skills/workflow-sync-template/`                                        | `SKILL.md` only                        |
| .ai-dev-workflow.yaml line count        | `wc -l .ai-dev-workflow.yaml`                                                     | 96 lines                               |
| README workflow config section          | `grep -n "schema_version" docs/workflow/development-workflow/README.md`           | line 373                               |
| Existing retro smoke test               | `ls docs/testing/workflow/ \| grep retro`                                         | `retrospective-protocol.smoke-test.md` |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml` — add `template:` section with two optional fields (`repository` and `last_synced_version`) with inline comments explaining their purpose. Place the section after the `browser_automation:` section.

### Documentation / Protocol Files

- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` — insert a new Step 3b "Template cross-reference" immediately after Step 3a (existing backlog query). The existing `### 3b. Categorization taxonomy` heading (line 140) must be renamed to `### 3c. Categorization taxonomy`, and the forward-reference on line 125 ("After categorizing all findings in Step 3b below") must be updated to reference "Step 3c". The new Step 3b checks `template.repository` in `.ai-dev-workflow.yaml`; if absent or empty, the step is silently skipped (BR-1). If present, the step queries the template repo's issues, classifies each finding into one of three buckets (BR-2), and carries the classification into Step 4 presentation.

- [ ] `.claude/commands/sync-template.md` — add a new sub-step in "Step 5 — Generate git instructions": after applying template changes and before printing the git instructions, record `TEMPLATE_VERSION` into `.ai-dev-workflow.yaml`'s `template.last_synced_version` field and include the updated file in the git stage instructions. Print a confirmation line `"Recorded last-synced template version: vX.Y.Z"` as part of the Step 5 output.

- [ ] `.cursor/commands/sync-template.md` — same change as the Claude command above (parallel file).

- [ ] `.codex/skills/workflow-sync-template/SKILL.md` — add a note that after generating git instructions, the skill must also record the last-synced version in `.ai-dev-workflow.yaml` per the canonical sync-template protocol.

- [ ] `docs/workflow/development-workflow/README.md` — extend the "Workflow Configuration" section's schema example to include the `template:` section, and add a bullet under "Important implementation notes" explaining what the two fields do.

---

## Testing Strategy

**Test types**: Smoke (manual walkthrough via runbook)

**Key scenarios to test**:

1. Template repository not configured — retrospective runs without any mention of template cross-reference (maps to AC: "when template repository reference is absent, retrospective runs identically to pre-feature behavior")
2. Template repository configured, repository reachable — each finding carries a classification label before Step 4 (maps to AC: "each finding carries one of the three classification labels")
3. `already-tracked` classification — finding matches an open template issue; presentation includes template issue number AND suggests Skip or Expand as alternatives to creating a new upstream issue (maps to AC 3)
4. `already-fixed` classification — finding matches a closed issue whose fix version is newer than `last_synced_version` (maps to AC: "presentation includes both fix version and downstream's synced version")
5. `last_synced_version` absent, closed issue match — finding falls back to "Contribute upstream candidate" with a note (maps to AC)
6. Fix version unknown — finding falls back to "Contribute upstream candidate" with a note (maps to AC)
7. Malformed repository reference — retrospective completes with error, all findings show "Template check unavailable" (maps to AC)
8. Repository unreachable — retrospective completes with warning, all findings show "Template check unavailable" (maps to AC)
9. Sync-template successful run — `.ai-dev-workflow.yaml` contains updated `last_synced_version`; git instructions include the file (maps to AC)
10. Exact path match (AC 12) — finding whose affected area is an exact file path in a template issue's title or body is classified as "Already in template backlog"
11. Keyword overlap match (AC 13) — finding sharing 3+ significant keywords with a template issue (no exact match) is classified correctly
12. Category label match (AC 14) — finding sharing same categorization taxonomy label and overlapping symptoms is classified correctly

**Smoke test runbook**: `docs/testing/workflow/retro-template-backlog-crossref.smoke-test.md`

---

## Seed Data

| Entity                | Values / Scenario                                  | File |
| --------------------- | -------------------------------------------------- | ---- |
| No seed data required | All scenarios are protocol-level text walkthroughs | N/A  |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/README.md` — covered in Layer-by-Layer Changes above (extend schema example + add implementation notes bullet)
- [ ] `.ai-dev-workflow.yaml` — covered in Layer-by-Layer Changes above (add `template:` section)

No other `docs/project/` or `AGENTS.md` files require updates for this feature.

---

## Risks & Mitigations

| Risk                                                                                                             | Likelihood | Impact | Mitigation                                                                                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------------------------- | ---------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 5 version-recording change in sync-template disrupts existing sync flow                                     | Low        | Low    | The recording step is purely additive — it writes to a new field that did not exist before. Implementation Order step 4 adds `.ai-dev-workflow.yaml` to the git stage instructions so the updated file is included in the commit. |
| Retrospective Step 3b calling `gh issue list` on external template repo fails in offline/restricted environments | Low        | Low    | BR-5 graceful degradation: mark all findings as "Template check unavailable" and continue                                                                                                                                         |
| Parallel worktrees or batch agents write different `last_synced_version` values to `.ai-dev-workflow.yaml`       | Low        | Low    | `last_synced_version` is written only by the sync-template skill (BR-7), which is always run in a single-developer context, not in parallel batch orchestration                                                                   |

---

## Code Samples

The following are illustrative — adapt during implementation.

```yaml
# Illustrative — adapt during implementation
# New section to append to .ai-dev-workflow.yaml after browser_automation:
template:
  # Optional: upstream template repository reference (owner/repo format for GitHub).
  # When set, the retrospective protocol (Step 3b) cross-references each finding
  # against this repository's issue tracker. Leave empty or omit to skip.
  repository: ""

  # Optional: the template version last applied by the sync-template skill.
  # Written automatically by sync-template after a successful sync.
  # Used by the retrospective cross-reference step to identify "already fixed upstream" findings.
  last_synced_version: ""
```

```markdown
<!-- Illustrative — adapt during implementation -->
<!-- Insertion point: after Step 3a (line ~138) in 06-retrospective-protocol.md, -->
<!-- before the renamed ### 3c. Categorization taxonomy.                          -->
<!-- Also rename existing ### 3b to ### 3c and update the line-125 forward-ref.   -->

### 3b. Template cross-reference (opt-in — skipped when not configured)

Read `template.repository` from `.ai-dev-workflow.yaml`.

- **If absent or empty**: skip this substep silently. Do not mention it in output (BR-1, BR-8).
- **If present but malformed** (not `owner/repo` format): mark all findings as "Template check unavailable" (error severity) and continue. Report error in Step 4 output (BR-9).
- **If well-formed**: query the template repository's open issues, then for each finding classify into one bucket (BR-2 through BR-6).
```

---

## Implementation Order

1. **Add `template:` section to `.ai-dev-workflow.yaml`** — append after `browser_automation:`. Include `repository: ""` and `last_synced_version: ""` with comment blocks explaining each field. Verify: open the file and confirm the new section is present with correct YAML indentation.

2. **Extend `docs/workflow/development-workflow/README.md` Workflow Configuration section** — add the `template:` block to the schema YAML example (lines ~373–390) and add one bullet to the "Important implementation notes" list explaining `template.repository` and `template.last_synced_version`. Verify: confirm the schema example includes the new section and the notes list mentions both fields.

3. **Update `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`** — three coordinated edits:

   a. **Rename existing `### 3b. Categorization taxonomy` (line 140) to `### 3c. Categorization taxonomy`** to make room for the new Step 3b.

   b. **Update the forward-reference on line 125**: change "After categorizing all findings in Step 3b below" to "After categorizing all findings in Step 3c below".

   c. **Insert the new `### 3b. Template cross-reference (opt-in — skipped when not configured)`** between the end of Step 3a (line ~138) and the now-renamed Step 3c. The new Step 3b must:
   - Read `template.repository` from `.ai-dev-workflow.yaml`
   - Silently skip if absent/empty (do not mention in output per BR-1, BR-8)
   - Report error (not warning) and fall back to "Template check unavailable" if malformed (not `owner/repo` format per BR-9)
   - Query open template issues via `gh issue list --repo <owner/repo> --state open --limit 200 --json number,title,body,labels`
   - Query closed template issues via `gh issue list --repo <owner/repo> --state closed --limit 500 --json number,title,body,labels,closedAt`
   - For each finding, apply BR-4 matching heuristic (exact path match, 3+ keyword overlap, shared category label)
   - Assign exactly one classification per BR-2 (already-tracked, already-fixed, contribute-upstream) with BR-3/BR-6 fallbacks when version data is absent
   - If repository unreachable: mark all findings "Template check unavailable" (warning, BR-5)
   - Carry classification into Step 4 output: show label + template issue number or version comparison inline with each finding. For `already-tracked` findings, also suggest Skip or Expand as alternatives to creating a new upstream issue (per AC 3)

   Verify: confirm the forward-reference on line ~125 now says "Step 3c", confirm the `### 3b. Template cross-reference` heading appears immediately before the renamed `### 3c. Categorization taxonomy`, confirm the three classification labels match the spec's Classification Labels table, and confirm that `already-tracked` presentation output includes Skip/Expand suggestion text.

4. **Update `.claude/commands/sync-template.md`** — in "Step 5 — Generate git instructions", add a sub-step before the git instructions block:
   - After applying template changes and before printing the git instructions, write `TEMPLATE_VERSION` to `.ai-dev-workflow.yaml` under `template.last_synced_version`
   - Print confirmation: `"Recorded last-synced template version: v{TEMPLATE_VERSION}"`
   - Include `.ai-dev-workflow.yaml` in the `git add` instructions shown to the user

   Verify: confirm the new sub-step appears in Step 5 and the git add list includes `.ai-dev-workflow.yaml`.

5. **Update `.cursor/commands/sync-template.md`** — apply the same sync-template update described in step 4 above (add a sub-step before the git instructions block that records `TEMPLATE_VERSION`). Verify: confirm the changes match the Claude command version.

6. **Update `.codex/skills/workflow-sync-template/SKILL.md`** — add a new step 7 after the existing step 6 (the last step): "After applying template changes and before generating git instructions, record `TEMPLATE_VERSION` to `.ai-dev-workflow.yaml` under `template.last_synced_version` per the canonical sync-template protocol Step 5." Verify: confirm the new step appears after the existing step 6 and references the protocol.

7. **Update `CHANGELOG.md`** under `[Unreleased]`:

   ```
   - **Retrospective template-aware backlog cross-reference with version tracking** (#299): Adds optional `template.repository` and `template.last_synced_version` fields to `.ai-dev-workflow.yaml`. Extends retrospective Step 3 to classify findings against the upstream template backlog (already tracked / already fixed / contribute upstream). Updates sync-template skill to record the last-synced version automatically. Backwards-compatible — silently skipped when not configured.
   ```

8. **Run markdownlint-cli2 pre-commit check** on all modified `.md` files, including `CHANGELOG.md`:

   ```bash
   npx markdownlint-cli2 \
     "docs/specs/developments/**/*.md" \
     "docs/testing/workflow/**/*.md" \
     "CHANGELOG.md"
   ```

   Fix any violations before committing.
