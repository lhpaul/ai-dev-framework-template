# Stage-Role Permission Denial Recovery — Implementation Plan

**Spec**: [Stage-Role Permission Denial Recovery](1_1746-stage-permission-denial_specs.md)
**Smoke test runbook**: [Stage-role denial recovery](../../../testing/workflow/1746-stage-permission-denial.smoke-test.md)

## Summary

**Approach**: Establish one normative stage-role denial reporting and stop contract in the item orchestration protocol; make delegation handoffs and the affected orchestration, agent, dispatch-profile and guardrail surfaces point to it. Keep the Work Item Runner–Portfolio denial signal and its fallback separate. Extend the existing consumer sync diagnostic with an opt-in, structured check of the declared stop list, rather than trusting a stop name anywhere in the file. Add executable regression coverage and a fabricated-evidence smoke runbook.

**Estimated complexity**: L. The change spans multiple mirrored workflow contracts, cross-runner review handling, baseline configuration and consumer sync validation, with edge cases around ambiguous denial and partial effects.

**Dependencies**: Merged spec PR #2100 and the existing #1462 profile and #1378 model-source contracts. Git, Python 3, Bash and the repository's current test harness are used; no external service, credential change, application API, database, migration, frontend, or seed data is required.

## Verification Log

All repository-derived observations below were checked at `2ebf6a2b8e6f24b4da5fcbd3e8acea5780235708`. Listings are discovery evidence, not a frozen exhaustive list: re-run them before implementation and classify each current match.

| Check | Reproducible command / source | Result and implication |
| --- | --- | --- |
| Revision | `git rev-parse HEAD` | `2ebf6a2b8e6f24b4da5fcbd3e8acea5780235708`; spec PR #2100 merged. |
| Superseded statements | `rg -l 'No named stop for a harness\|No named stop condition for a harness\|no recovery path of any kind\|tracked separately as issue #1746\|tracked as #1746\|tracked separately as \*\*#1746' docs/workflow .cursor .claude .codex .agents scripts .ai-dev-workflow.yaml` | Five workflow files: guardrail enforcement, Cursor dispatch profiles, and Protocols 90, 91, and 95. The #1462 smoke test is a separate explicit spec obligation; historical spec/plan remain history. |
| Existing boundary signal | `rg -l 'SUBAGENT_PERMISSION_DENIAL\|Permission to use' .claude/agents .cursor/agents docs/workflow/development-workflow/protocols` | Two item-orchestrator role files and Protocols 90, 91, 95 match. Reclassify actual uses by boundary; do not replace the Work Item Runner signal wholesale. |
| Stop-list examples | `rg -l 'stop_conditions:' README.md .ai-dev-workflow.yaml docs/workflow` | Three tracked paths: config, workflow README and guardrails guide; enforcement and guardrails tables are additional normative surfaces. |
| Structured sync call chain | `rg -n 'check_required_additions\(' scripts/development-workflow --glob '*.py'` | Definition and call in `check-sync-manifest-coverage.py` (`run` invokes it only with `--consumer-root`). `sync-template-merge.py` imports this module for `entry_matches`, not for this check. |
| User-facing sync consumers | `rg -n 'check-sync-manifest-coverage\.py\|REQUIRED_ADDITION_MISSING\|--consumer-root' .claude/commands/sync-template.md .claude/skills/sync-template.md .cursor/commands/sync-template.md .codex/skills/workflow-sync-template/SKILL.md scripts/development-workflow/README.md` | Claude command and skill and Cursor command run the checker and surface its missing-addition output; Codex skill points to the canonical command. Preserve their existing `0`/`1`/`2` contract and the `REQUIRED_ADDITION_*` result strings. |
| Existing sync behavior | `sed -n '257,295p' scripts/development-workflow/check-sync-manifest-coverage.py` | `must_contain` currently searches the entire file. A comment or unrelated key can satisfy it, so a new list-specific requirement needs a structured check; do not silently change older entries' substring semantics. |
| Existing fixture and checks | `rg --files scripts/development-workflow/tests | rg 'test-check-sync-manifest-coverage\|test-cursor-dispatch-profile-pointers\|test-step7a-surface-consistency\|test-worktree-recipe'` | Existing suites cover consumer diagnostic, profile pointers, Step 7a and worktree stop contracts; add targeted cases rather than assuming their present coverage includes #1746. |

### Rule 1: external denial evidence

The design must not infer that all harness denial messages share a grammar. The available historical sample is limited: issue [#172](https://github.com/lhpaul/ai-dev-framework-template/issues/172) records an item-orchestrator incident on 2026-04-16 in which both `Edit` and `Bash` were denied and a redispatch repeated the same reported shape, “Permission to use [tool] has been denied”; issue [#228](https://github.com/lhpaul/ai-dev-framework-template/issues/228) records two stage-implementation incidents on 2026-04-20 summarized as `Edit`/`Write` denied, followed by two different prohibited workarounds. These are incident descriptions, not a comprehensive export of harness output: the two reports describe four denial occurrences in total (two tool denials in #172 and two implementation-stage incidents in #228). They provide one quoted redacted harness-message shape and a second, summarized denial-report shape, not four verbatim harness logs; no claim of saturation or exhaustive coverage is made. The population is historical repository-reported denials in that April window, not every runner or current harness. The sample shows why tool, path, and no-bypass context matter; it is not representative enough to justify an exhaustive regex or treating an unknown failure as a denial. Use the framework's explicit stage-role report contract and actual reported facts; unknown or unclassifiable evidence follows the approved spec's stop, and generic errors retain their existing route. Synthetic fixtures below test the new contract, not purported real harness wording.

### Rule 6: scoped obligations

- The stage-role report and no-bypass obligation bind each dispatched stage role and its item-orchestrator receiver, including the Step 7a CLI-reviewer path, before the item takes a dependent mutation or claims completion. The Work Item Runner's own separate report remains governed by Protocol 90 Step 4.1.
- On a confirmed tool/path denial with uncertain effects, the affected item keeps the new stop until an operator confirms an access or context correction and the item runner reconciles the actual effect before the same owning role resumes. The item runner holds dependent items; independently eligible items remain governed by their existing isolation gates.
- A consumer-list membership check applies only to the new manifest entry when its specified consumer file contains a declared `guardrails.stop_conditions` list. The consumer-sync diagnostic discharges it when invoked with `--consumer-root`; absence of a declared list is not a missing-list-entry finding, while an unreadable or malformed declared configuration must be an error, never a clean result.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and approved base | `single_repo`, this repository, `develop` | `workflow-config-resolver.py mode --json`; PR #2100 base | 2026-11-02, `2ebf6a2b` | #1746 and its current repository only | Verified |
| Prior contracts | #1462 profiles and #1378 model pins are merged; #2100 is approved and merged | Issue #1746, merged spec, current files | 2026-11-02, `2ebf6a2b` | This item and the affected workflow surfaces | Verified |
| Competing work | No matching open PR returned | `gh search prs --repo lhpaul/ai-dev-framework-template --state open '"stage" "permission"' --json number,title,url --limit 40` and same query for `"1746"` | 2026-11-02, `2ebf6a2b` | Open PRs on these bounded terms; not a repository-wide assertion | Verified |

Re-run these checks immediately before implementation. Mark changed or conflicting evidence `Stale or conflicting` and resolve it through the parent/human before acting; do not silently implement against stale assumptions.

## Layer-by-Layer Changes

### Workflow contracts and agent handoffs

1. In `91-orchestrate-work-protocol.md`, define a stage-role-specific structured report that carries the owning role, item, known denied tool/action or target, and known partial/uncertain state. Name a stable stage-role report marker distinct from `SUBAGENT_PERMISSION_DENIAL`; the latter stays a Work Item Runner→Portfolio signal. Add an explicit receiver decision before each item-stage handoff may advance or mutate. A confirmed tool/path denial emits `stage_role_tool_or_path_denied`; an unclassifiable established access refusal emits `unclear_requirements`; a generic error follows its existing failure path. No parser may assume an exhaustive third-party denial phrase list. AC 1, 3–4, 7–9.
2. For Step 7a, preserve its review-gate failure for all configured and cross-runner CLI reviewers. When an explicit tool/path denial is established, also stop the item with the new condition; do not interpret a failed reviewer as unavailable, approved, or a content finding. After correction, run a fresh review. AC 2, 5, 8–9.
3. At every stage-role dispatch and receiver in Protocol 91, require the stage handoff to include the reporting contract and inspect the returned report before follow-on writes. Enumerate current spec, plan, implementation and review dispatches with `rg -n 'dispatch|handoff|spec-reviewer|plan-reviewer|developer|code-reviewer' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`; trace each result to its caller and note not-applicable matches with reasons. For any command or protocol that bypasses those handoffs, add a pointer at its actual boundary; merely adding text to an unrelated introduction is insufficient. AC 1–3, 5, 9.
4. Update the applicable `.claude/agents/` and `.cursor/agents/` stage roles and `item-orchestrator.md` receivers, and the relevant `.agents/skills/` / `.codex/skills/` guidance only where they dispatch or report this work. Re-run `rg -n 'SUBAGENT_PERMISSION_DENIAL|Permission to use|stage role|dispatch' .claude/agents .cursor/agents .agents/skills .codex/skills` and classify each result by Work Item Runner boundary, stage-role boundary, unrelated use, or historical record. Preserve no-bypass and do not manufacture reports when a role does not run. AC 1–2, 7–9.
5. In Protocol 90 Step 4.1, explicitly scope the existing signal and fallback to the Portfolio↔Work Item Runner boundary. Replace the obsolete #1746 no-recovery claims in Protocols 90/91/95, `guardrails-enforcement.md`, and `integrations/cursor-dispatch-profiles.md`; preserve native/parent/inline profile semantics and the separate credential and unreachable-role stops. Update `.cursor/commands/run-item.md`, `run-items.md`, `run-epic.md` and the corresponding orchestrator role pointers where needed. `/run-work` remains read-only. AC 2, 4, 7, 9.
6. In `guardrails.md`, `guardrails-enforcement.md`, `.ai-dev-workflow.yaml`, and `docs/workflow/development-workflow/README.md`, add the new always-in-force condition to the normative tables and configured/documented baseline lists, and align both `unclear_requirements` definitions to the approved narrow unknown-cause extension. Keep the general config examples consistent. Update applicable stop-name tests if they cover a newly emitted stop; do not widen a test scoped to unrelated examples merely to change a count. AC 1, 4, 6, 9.

### Consumer sync diagnostic

7. Add an opt-in flat `required_additions` selector, for example `yaml_list_path: guardrails.stop_conditions`, to the new `sync-manifest.yaml` entry. Update `check-sync-manifest-coverage.py` to validate this selector and use the existing workflow configuration parser's supported YAML subset to inspect that exact list, without printing configuration contents. A present list containing the exact string yields `REQUIRED_ADDITION_PRESENT`; a present list without it, including an empty list, yields `REQUIRED_ADDITION_MISSING` and exit 1. An absent consumer file or an absent list yields the existing `REQUIRED_ADDITION_NOT_APPLICABLE`; an unreadable, malformed, duplicate, unsupported or wrong-type declared config yields a sanitized diagnostic and exit 2, never a false clean. Preserve all existing manifest entries' `when_pattern` and whole-file `must_contain` behavior unchanged when the opt-in selector is absent. Use an existing resolver API or a small adapter with no environment-dependent side effects; do not add a YAML dependency. AC 6.
8. The observable consumer path is the coverage checker with `--consumer-root` → `REQUIRED_ADDITION_MISSING` → sync-template Step 0.5 and its required-additive-update summary. Confirm `.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`, `.codex/skills/workflow-sync-template/SKILL.md`, and `scripts/development-workflow/README.md` accurately describe the new opt-in check and error behavior; change only surfaces that need it. `sync-template-merge.py` uses `entry_matches` from the same module but does not call the addition checker; retain that behavior and regression-test module import. Consumer project-owned configuration is never silently overwritten. AC 6, 9.

## Testing Strategy

- Add a focused synthetic workflow-contract test under `scripts/development-workflow/tests/test-stage-role-permission-denial.sh`, with `# covers:` mappings for changed contracts and code. Use fixtures and assertions that exercise the item receiver and the documented decision matrix, including confirmed denial, unknown cause, combined credential denial, unreachable role, a generic error, all guardrail modes, reviewer CLI denial, held dependents, uncertain remote effects, same-context and fresh-context recovery, repeated denial, and the separate Work Item Runner signal. A text-presence check alone does not prove the receiver routes a report correctly; exercise the nearest executable routing mechanism where one exists and otherwise validate a concrete synthetic handoff against the normative instructions, recording that limitation.
- Extend `test-check-sync-manifest-coverage.sh` with disposable consumer YAML and manifest fixtures. Cover declared list present/missing/empty, no list/file, malformed or unreadable config, duplicate keys and wrong types, unrelated comment or another key containing the stop, exact versus lookalike names, quoted scalars, valid supported block and flow forms, and legacy entries. For each fixture assert exit status and actual diagnostic; ensure no raw consumer values leak. Verify `sync-template-merge.py` import and existing sync-template tests still work.
- Run `test-cursor-dispatch-profile-pointers.sh`, `test-step7a-surface-consistency.sh`, `test-worktree-recipe.sh`, `test-check-sync-manifest-coverage.sh`, relevant sync-template tests, resolver tests as appropriate, Markdown and shell lint, sync-manifest coverage, and `git diff --check`. Use `select-test-suites.sh` to verify coverage mappings; do not substitute a default suite association for proof.
- For each new automated guard, demonstrate a planted violation in disposable fixtures: a consumer list missing the stop even with the string in a comment must fail then pass after the stop is added to the list; a stage-report routing violation must fail the new contract test then pass when restored. Record commands, concrete fixture paths/lines, exit outputs and reviewed head in the implementation PR. Do not use real product checkouts, credentials, or a live permission denial.
- Fixtures are local synthetic files; they are created and removed inside each test's isolated temporary directory. No shared fixture, persistent mutable state, database seed, or live worker is needed. Test scenario lists are indicative coverage classes, not a binding enumeration.

### Parser-risk addendum

The new opt-in check consumes a manifest selector and a consumer YAML list. Cover empty/missing and wrong-type values, valid quoted names, exact matches and prefix/suffix lookalikes, comments, sibling/unrelated fields containing the stop, duplicate keys, malformed YAML, unsupported flow syntax, empty lists, absent lists, nested mappings, and unreadable files. Map each class to a behavioral assertion in `test-check-sync-manifest-coverage.sh`; no suppression directives are supported. The structured selector must use the same supported YAML subset as the workflow resolver, reject unsupported input rather than reinterpret it, and not expose raw content in errors.

## Seed Data

None. Tests build fabricated configurations, reports, and temporary Git fixtures inside their own scratch directories.

## Documentation Updates

Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`, `91-orchestrate-work-protocol.md`, and `95-run-epic-protocol.md`; `docs/workflow/development-workflow/guardrails.md`, `guardrails-enforcement.md`, `README.md`, and `integrations/cursor-dispatch-profiles.md`; `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md`; and `scripts/development-workflow/README.md` for the actual diagnostic behavior. Check the four named sync surfaces and update only those whose guidance becomes inaccurate. Project-domain, application architecture, and database documents are template placeholders and are unaffected; `AGENTS.md` needs no change unless the implementation changes its existing repository-wide contract. Add a changelog fragment in the implementation PR, not this plan PR.

## Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Stage denial is mistaken for a Work Item Runner denial or content defect | Unsafe inline work or wrong label | Separate marker and receiver boundary; test both paths and no `needs-fixes`. |
| A denied remote mutation actually succeeded | Duplicate or conflicting writes | Reconcile live state before retry; preserve uncertain work and hold dependents. |
| Consumer list check accepts a comment or unsupported YAML | Baseline stop is silently omitted | Parse the exact list using the supported resolver subset; fail closed on malformed input and plant the comment-only violation. |
| Mirrored documents drift | Conflicting or missing recovery rules | Re-run discovery queries and record a residual report classifying every match before implementation PR readiness. |

## Implementation Order

1. Re-verify operational assumptions and inventory the live boundary and mirror surfaces; record scope and any residuals.
2. Define the canonical stage-role reporting, decision, recovery, Step 7a and Work Item Runner distinction in Protocol 91 and Protocol 90.
3. Update dispatch handoffs, role guidance, command and guardrail mirrors, stop lists, and the #1462 smoke guidance consistently.
4. Add the list-aware manifest entry and diagnostic while retaining legacy behavior; cover the consumer and module-import call sites.
5. Add and run focused tests, planted-violation proofs, existing regressions and the implementation smoke runbook. Update documentation and changelog.
6. Re-run inventory and record every residual as fixed, explicitly out of scope with reason, or linked to an existing follow-up before review. Follow the implementation review, CI and PR workflow.
