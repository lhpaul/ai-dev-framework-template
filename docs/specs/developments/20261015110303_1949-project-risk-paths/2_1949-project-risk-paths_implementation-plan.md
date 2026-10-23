# Project Risk Paths — Implementation Plan

**Spec**: [Project Risk Paths](1_1949-project-risk-paths_specs.md)
**Smoke test runbook**: [1949 smoke test](../../../testing/workflow/1949-project-risk-paths.smoke-test.md)

## Summary

**Approach**: Add a read-only Python configuration/matching helper beside the
classifier, reusing the workflow resolver's strict YAML reader. Keep built-in
classification and protected-path floors in the classifier, applying the
project's matched category per ordinary file before PR aggregation.

**Estimated complexity**: M — configuration validation, project selection and
per-file precedence need coordinated regression coverage. No UI, database,
deployment, external API, or consumer changes are required.

**Dependencies**: The merged spec, Bash, Python 3, jq and the existing PyYAML
toolchain. Template-fit check passed: this is generic framework tooling.
Luis authorized definition of configuration design through spec and plan;
the implementation still requires human review before merge.

## Current reader dependency clarification

The PyYAML dependency statements below retain this plan's historical assumptions
and verification evidence. The later #1993 sole-reader design supersedes that
runtime dependency for framework configuration: the shared risk-map reader uses
the same dependency-free strict reader as modern review and selected-source
validation. This does not change risk rules, implementation scope or approval
history. Provider-specific CodeRabbit checks keep their separate dependency.
See the [current reader contract](../../../workflow/development-workflow/integrations/runner-secret-prevention.md).

## Verification Log

Repository-derived evidence below was collected at
`fbc356d604d0d4c250c978445f7bba77d584b848`, on 2026-10-15 UTC.
Commands are read-only and run from the repository root.

| Evidence | Reproducing command / source | Observed result |
| --- | --- | --- |
| Revision | `git rev-parse HEAD` | Revision named above; merged spec present |
| Current file-risk branch and caller | `rg -n 'changed_file_risk|classify_state|effective_root|product_repo' scripts/development-workflow/run-epic-risk-classifier.sh` | Broad release branch in changed_file_risk; classify_state consumes it; config root and product selector already exist |
| Existing YAML mechanisms | `rg -n 'def parse_review_yaml|def product_repos|def select_product_repo|def mode_from_shared|def parse_remote_slug' scripts/development-workflow/workflow-config-resolver.py` | Reusable strict reader and product identity helpers; product_repos preserves additional project fields |
| No existing path map | `rg -n 'risk_paths' scripts/development-workflow/workflow-config-resolver.py .ai-dev-workflow.yaml` | No matches |
| Framework glob convention | `rg -n 'Pattern syntax|matches any characters|glob_to_regex' scripts/development-workflow/select-test-suites.sh` | Existing distinction between star and double-star; use D2 below |
| Existing regression entry points | `rg --files scripts/development-workflow/tests -g '*risk*' -g '*delegated-gate*' -g '*workflow-config*' -g '*sync-manifest*'` | Risk-classifier, delegated-gate, config and sync suites available |
| Release-related tooling | `rg --files scripts .github .claude .cursor .agents .codex -g '*release*'` | Shell release helpers, release tests/fixtures, auto-tag workflow and command docs; skill files additionally require their directory paths, see D4 |
| Release skill directory discovery | `rg --files .agents/skills .codex/skills -g '*prepare-release*' -g 'SKILL.md'` | prepare-release skill directory exists under .agents; retain both supported skill roots in D4 |
| Sync ownership | `rg -n 'scripts/development-workflow/|workflow-config-resolver.py|.ai-dev-workflow.yaml' sync-manifest.yaml` | Workflow helpers ship through the existing recursive entry; shared config has special handling |
| Runtime dependency | `rg -n 'PyYAML|PYYAML_VERSION' scripts/cloud-agent-install.sh .github/workflows/workflow-tests.yml` | Cloud setup and workflow CI provision PyYAML; no new package family needed |
| Protected-file policy | `rg -n 'protected|protect' .ai-dev-workflow.yaml docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | No protected-file list affecting this change; fork workflow write rules are unrelated |

### Consumer enumeration and composed outcomes

Reproduce with `rg -l -F 'run-epic-risk-classifier.sh' scripts docs/workflow
.agents .codex .claude .cursor --glob '*.sh' --glob '*.py' --glob '*.md'`
(join this command onto one line). This searches runtime, workflow guidance,
agent/skill surfaces and tests rather than only the classifier directory.

| Consumer / reference group | Expected outcome after this change |
| --- | --- |
| Protocol 91 Step 8 and Protocol 95 delegated merge step; guardrails-enforcement.md | Same CLI and result schema; config error stops before a verdict; otherwise risk remains input to existing delegated gates |
| .agents/skills/run-items and run-epic; .claude/commands/run-items.md and run-epic.md; .cursor/commands/run-items.md and run-epic.md; .claude/agents/orchestrator.md and .cursor/agents/orchestrator.md | Existing classifier invocation remains valid; no caller edits needed |
| run-epic-delegated-gate.sh | Consumes current-head risk evidence after review/CI; Low path mapping cannot override its other blockers or checkpoint decisions |
| security-advisory-classifier.sh | Classifier remains a sensitive tooling surface; no advisory-policy change |
| test-run-epic-risk-classifier.sh | Existing CLI, CI, why-safe and evidence regressions remain valid; add incident, floors, aggregation and missing-evidence cases |
| test-run-epic-delegated-gate.sh and test-status-check-rollup-dedupe.sh | Risk stays nested in gate evidence; deduped CI and other blockers retain their existing behavior |
| test-workflow-merge-budget.sh and test-workflow-merge-budget-part-{2,3,4,5,6,7,8}.sh | Optional budget metadata remains read-only and cannot authorize merge |
| test-security-advisory-classifier.sh, test-select-test-suites.sh, test-run-epic-audit-trail.sh | References remain valid; new suite declares its covered helper/classifier paths |
| docs/workflow/retro-metrics.md; classifier's own help/examples | Historical reference unchanged; help gains configuration guidance without changing result keys |

The release-substring branch's former ordinary-documentation inputs now reach
the built-in docs branch, yielding Low absent another floor or map match.
Other ordinary paths reach their existing default category. D3/D4 govern
override precedence before classify_state applies existing PR-level gates.

## Cross-Cutting Operational Assumption Check

| Surface | Value and authoritative source | Verified at / bounded scope | Result |
| --- | --- | --- | --- |
| Artifact owner and base | single_repo, current repository, develop; user invocation and AGENTS.md | 2026-10-15, revision above; current invocation item list is only #1949; merged spec PR #1971 targets develop | Verified |
| Shared config location | .ai-dev-workflow.yaml; workflow_config_resolver.load_configs | Same revision; D1 uses shared policy only; local reviewer config is outside mutation scope | Verified |
| Same-surface concurrent work | `gh pr list --state open --base develop --search 'risk_paths in:body' --json number,title,headRefName` returned an empty list | 2026-10-15; bounded map-policy search, no portfolio scan | Verified |

Before implementation edits, re-read the named owner/base and configuration
sources and the bounded same-surface evidence. Record Still valid if they
agree; stop and return any Stale or conflicting evidence to the item runner.

## Design Decisions

### D1: Project-owned configuration and selection

In single_repo and product_repo modes, read optional
`guardrails.risk_paths` from the selected root's shared
`.ai-dev-workflow.yaml`. Never merge machine-local risk rules or mutate local
review configuration. A missing shared file, absent field, or empty list means
no project rules; explicit null, a bare field, or a non-list is invalid.

In workflow_hub mode, the same top-level field describes hub-owned paths.
Product-specific maps live at
`workflow_hub.product_repos[].guardrails.risk_paths` in the hub shared file,
selected by the existing explicit product selector or exact evidence repository
slug. A selected product map replaces the hub map entirely; absence in that
product means built-ins, never inheritance from the hub or a sibling.
No product checkout or new local path binding is required.

If no risk map is declared anywhere in a hub configuration, return no rules
without introducing a new product-selection prerequisite. When maps exist,
explicit CLI product name takes precedence over evidence product name; an
evidence repository slug must agree with any selected product. A slug matching
the hub remote selects hub policy only when no product selector was supplied.
An unknown, inconsistent or ambiguous target fails closed. Missing identity
may select the hub map only when no product maps exist. Do not infer the first
product merely because it appears first. These rules apply equally to --pr and
--input; configuration comes from the local approved project policy, never a
map embedded in PR evidence.

### D2: Rule shape, grammar and validation

The map is a YAML block list of mappings with exactly `glob`, `risk`, `reason`.
All values are nonblank single-line strings; risk is exactly `low`, `medium` or
`high`. Unknown/missing keys, wrong types, duplicate YAML keys and unsupported
YAML constructs fail with a field/rule diagnostic. Reuse parse_review_yaml
instead of introducing a YAML parser. Validate the entire selected map before
matching, including rules that do not match this PR. Catch parser failures
without copying raw YAML snippets or values into diagnostics.

Patterns are case-sensitive, full-path matches against repository-relative
POSIX paths: `*` matches zero or more non-slash characters, `**` matches zero or
more characters including slash, and `?` matches one non-slash character.
Other accepted characters are literals escaped before regular-expression use.
For clarity, `**/file` requires the literal slash; use a separate `file` rule
to cover the repository root. Dotfiles receive no special exclusion.
Reject bracket classes, braces, backslashes, control characters, absolute
patterns, empty segments and dot/dot-dot segments. Changed paths must be
nonblank strings with the same relative-path restrictions (literal glob
characters in actual filenames are not interpreted). A missing or empty
changed-file list is governed by spec compatibility rule 8, not by path error.

Illustrative configuration (operator example, not implementation code):

```yaml
guardrails:
  risk_paths:
    - glob: "docs/store/**"
      risk: medium
      reason: "Store review package documentation"
```

### D3: Matching, floors and aggregation

The helper reports all matching rules per changed path and their highest risk.
The shell classifier derives a built-in ordinary category per file, substitutes
the matched project category when present, then applies any High floor from D4.
Only after that does it aggregate the highest resulting risk across files.
This avoids lowering a previous file's risk when a later file matches Low.

Retain all matched reasons, identify them as project-rule reasons and include
the path; when a floor wins, also include its reason. Preserve declaration
order only for display, never as priority. Keep the existing public classifier
result schema and non-path gates. A helper/configuration error exits nonzero
without emitting a merge-eligible verdict. A map cannot supply or replace CI,
reviewer, risk-ceiling, budget, checkpoint or why-safe evidence.

### D4: High floors and release narrowing

Preserve the existing auth/authentication, secret/secrets,
credential/credentials and permission/permissions path arms exactly, applying
them independently of ordinary docs/tests categories. Preserve the existing
branch-deletion and delete-branch arms. Non-test/lint CI workflows retain their
floor; leave ci_workflow_is_test_or_lint and its conservative inspection intact.

Replace the unanchored release substring with these tooling-root patterns:
`scripts/*release*.sh`, `scripts/*release*.py`,
`.github/workflows/*release*`, `.claude/commands/*release*.md`,
`.cursor/commands/*release*.md`, `.agents/skills/*release*/*`,
`.codex/skills/*release*/*`. These are Bash case patterns, whose star crosses
directories; they are separate from the project-map grammar in D2. Existing
release test helpers under scripts retain protection. Ordinary documentation
and data outside those tooling roots no longer get a release-word floor.
Project rules cannot lower these floors. Add negative lookalike and real
tooling regressions rather than changing unrelated sensitive categories.

### D5: Implementation surfaces

| File | Change and acceptance coverage |
| --- | --- |
| scripts/development-workflow/workflow-risk-paths.py (new) | Strict shared-config read and project selection using resolver helpers; D1/D2 matching output for D3; AC4–AC7, AC10 |
| scripts/development-workflow/run-epic-risk-classifier.sh | Invoke helper once from effective root and selector; rebuild internal match evidence rather than trusting --input-supplied matches; D3/D4; AC1–AC8, AC12 |
| scripts/development-workflow/tests/test-workflow-risk-paths.sh (new) | Automated parser/matcher/selection cases in the table below, with covers header for helper and classifier |
| scripts/development-workflow/tests/test-run-epic-risk-classifier.sh | Incident, immutable floors, per-file aggregation, ceiling compatibility and composed gate regressions; AC1–AC9, AC12 |
| .ai-dev-workflow.yaml | Commented optional map example only; no active risk override for this template; AC10/AC11 |
| docs/workflow/development-workflow/guardrails.md | Maintainer-facing grammar, precedence, product-map ownership and repair guidance; AC10 |
| scripts/development-workflow/README.md | Helper usage and the existing classifier's map boundary; AC10 |
| changelog.d/1949.fixed.project-risk-paths.md (new) | Issue-specific slugged release note; AC11 |

No workflow protocol or agent checklist is changed. The new helper shares the
classifier's existing sync ownership through the recursive workflow-script
entry; do not broaden product-repo injection in sync-manifest.yaml. Product
classification driven from a hub uses the hub's shipped helper and D1 product
entry. Consumer-specific map values remain project-owned special-handling
configuration. Existing optional budget metadata and result consumers remain
unchanged.

## Testing Strategy

**Types**: Automated unit/CLI integration and the linked smoke runbook.
Parser-risk applies because this feature reads structured configuration and
implements a path rule engine. Concurrent-event-source and cross-cutting
checklist classifications are Not applicable: no listeners, shared writes or
new universal review/planning category is introduced. No suppression directives
are supported. No database seed, accounts, real GitHub writes or UI assets are
needed for feature tests; the supplied issue has no design assets.

### Parser-risk edge cases and unit-test mapping

These are coverage classes, not a binding scaffolding enumeration. The new
test-workflow-risk-paths.sh suite uses temporary repo/config/evidence fixtures;
the existing classifier suite tests final risk and permission, not only helper
internals. Fixtures are deterministic committed test inputs or inline here-docs.

| Case / concrete input | Automated coverage |
| --- | --- |
| docs/store/first-review/release-checklist.json, no map | classifier incident_low |
| scripts/development-workflow/prepare-release-post-merge-cleanup.sh and release workflow/command/skill paths, Low catch-all | classifier tooling_floors |
| Each existing sensitive path form at root/nested docs/tests with Low and Medium map values | classifier sensitive_floors, generated from the existing arms |
| Broad docs/** Low and docs/store/** High, both declaration orders and equal-risk ties | new suite overlap_order and tie_reasons; classifier aggregation |
| Unmatched apps/demo/main.ts; matched ordinary implementation path | classifier ordinary_override with full why-safe evidence for Medium |
| docs/* vs docs/**, docs/a?b.md, docs/.hidden, Docs/readme.md | new suite glob_boundaries |
| **/file versus root file; punctuation is literal; two rules on the same path | new suite exact_match and literal_punctuation |
| Missing map, empty list, null, bare key, mapping/scalar instead of list | new suite map_shapes |
| Missing/unknown rule fields, numeric/boolean/null values, blank strings, unsupported risk | new suite rule_shapes |
| Invalid unmatched rule following a valid matching rule | new suite validate_before_match |
| Duplicate keys, anchors, aliases, tags, block scalars and malformed YAML | new suite strict_yaml; stderr must not contain fixture secret-shaped value |
| Absolute, ./, ../, repeated slash, control characters, bracket/brace/backslash patterns | new suite invalid_patterns and invalid_changed_paths |
| Spaces in quoted path literals/reasons and multiple records; no eval or shell splitting | new suite literal_strings |
| Hub/product maps both match same relative path with different risks; product map absent | new suite project_isolation |
| CLI/evidence selector disagreement, unknown/ambiguous identity, hub-own slug, no-map hub without local checkout | new suite project_selection |
| Empty changed-file list at Low and High ceilings, otherwise clean evidence | classifier missing_evidence_compatibility |
| Low matching path plus unresolved review / failing CI / pending checkpoint / invalid budget evidence | existing delegated-gate and budget suites plus composed map-risk fixture in classifier suite; other gates still deny |
| Low docs followed by High secret and reverse order | classifier aggregate_order |

### Planted-violation proof

In temporary fixtures, record the concrete YAML rule line requesting Low for
`docs/secrets/value.txt` and the evidence line naming that path. At a Low
ceiling, assert final High and merge_permitted=false; a command asserting merge
permission must fail. Replace that path with `docs/public/value.txt` under the
same Low rule and clean evidence; the permission assertion must pass. Record
both commands/results and fixture file/line locators in implementation evidence.
Also demonstrate invalid-map rejection and corrected-map success. Never weaken
the production floors to manufacture this proof.

## Documentation Updates

Use D5's documentation/config rows as the authoritative update list. Project
architecture placeholders, best-practices and AGENTS.md need no change: this
adds no stack, deployment or workflow-stage contract. No spec-stage artifact
will be edited during implementation unless a real deviation is escalated.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Project Low rule bypasses sensitive paths | Independent High floor after matching, final-risk tests and planted proof |
| Hub applies sibling categories | D1 identity validation and product isolation tests |
| New syntax breaks review/config readers | Use existing strict YAML subset and test normal workflow configuration plus new block-list examples |
| Glob injection or pathological broad matching | Restricted grammar, escaped literals, no eval, deterministic full-path matcher |
| False assurance from unit-only tests | Test classifier result and composed delegated-gate behavior, then live PR readiness on actual head |

## Implementation Order

1. Revalidate operational assumptions; create the full-pipeline implementation
   branch from develop through normal guards. Preserve the human checkpoint.
2. Implement the helper and its unit suite for D1/D2. Run the new suite and
   strict-reader regression coverage; checkpoint the coherent passing sub-part.
3. Integrate D3/D4 in the classifier and extend its suite. Run classifier,
   delegated-gate, rollup-dedupe and the selected dependent harnesses. Record
   planted-violation evidence; checkpoint only after the sub-part passes.
4. Update D5's docs/config example and add the release note using the required
   bold-title bullet format. Run the smoke runbook and scope residual check.
   The residual strategy is a live re-enumeration of sensitive case arms and
   release tooling patterns with test coverage for every protected family.
5. Run ShellCheck for changed shell files, workflow-shell-guard-lint against
   origin/develop, Python syntax checks, markdown/heuristic lint and sync
   coverage checks. Inspect the selected-suite output so the helper's new suite
   is included; run the selected suites required by the final diff.
6. Continue internal two-pass review, external reviewers, regression-label and
   CI readiness gates at the implementation head. Classify risk without adding
   a template Low override. Stop before implementation merge with the ready PR
   and an approach summary for Luis; Max-risk remains Low.

## Plan Authoring Rigor Record

Evidence is in the Verification Log and consumer enumeration; the PR quality
gate binds outcomes to the committed plan revision.

| Rule | Outcome | Evidence / rationale |
| --- | --- | --- |
| Rule 1 — Sampling an external output distribution | Not applicable | No natural-language producer output is parsed; rule grammar is owned here, and paths are structured caller inputs |
| Rule 2 — One normative statement per fact | Satisfied | Decisions D1–D5 are canonical; test and order sections reference them; cross-read found no contradictory definition |
| Rule 3 — Counts of codebase artifacts | Not applicable | No artifact quantity sets scope; live queries enumerate paths and consumers without fixed counts |
| Rule 4 — Independent verification of existence claims | Satisfied | Reproducible source, absence, runtime, sync and test searches recorded at the named revision |
| Rule 5 — Expectations at the composed call site | Satisfied | Consumer enumeration records the ordered classifier → delegated gate path and unaffected reference groups; removed release branch rerouting is explicit |
| Rule 6 — A conditional obligation names its scope | Satisfied | D1/D2 bind validation to selected project/config and this invocation's path evidence; implementation-start and readiness obligations name their discharge steps |
