# Project Risk Paths — Spec

## Overview

Project maintainers need to classify changed files according to their role in
their own repository without weakening sensitive-path protections. Today a
documentation filename containing “release” can incorrectly make an otherwise
ordinary documentation change high risk. This feature corrects that false
positive and adds an optional project-owned path-risk map with explainable,
deterministic outcomes.

Brief: [ADF #1949](https://github.com/lhpaul/ai-dev-framework-template/issues/1949).
Incident evidence: [Zeki #696](https://github.com/zeki-cl/zeki-platform/issues/696).
Luis selected the full spec → plan → implementation route and retained a human
checkpoint before the implementation merge. Spec and plan merge authority is
limited to Low risk; this feature does not change that authority.

## Use Cases

### Use Case 1: Classify documentation without a release false positive

**Actor**: Workflow operator running a bounded item or delegated merge check.
**Preconditions**: The PR changes ordinary documentation and has current review
and CI evidence.

**Steps**:

1. Classify the PR's changed paths.
2. Inspect the risk and its reasons.
3. Continue through the existing review and merge gates when authorized.

**Postconditions**: A release-related word in a documentation filename alone
does not assign High risk. Actual release tooling keeps its protection.

**Information shown**: The classified risk and the changed paths explaining it.
**Actions available**: Continue, correct configuration, or request human review
through the existing workflow.
**Considerations**: An auth, secret, credential, or permission path remains
sensitive even when nested under documentation or tests.

### Use Case 2: Declare project-specific categories

**Actor**: Project maintainer.
**Preconditions**: The repository uses the framework's risk classifier.

**Steps**:

1. Declare path patterns, a Low/Medium/High risk for each, and a nonblank reason
   in project workflow configuration.
2. Run classification with that configuration and the PR's changed paths.
3. Inspect the matched categories and any enforced protection floor.

**Postconditions**: Matched ordinary paths use the project's declared category.
Unmatched paths retain the built-in classification. All matching project rules
participate; the highest matched risk wins, regardless of declaration order.

**Information shown**: Matched paths, category reasons, resulting risk, and any
floor preventing a requested reduction.
**Actions available**: Edit categories or proceed under existing authorization.
**Considerations**: A broad Low rule cannot cancel a narrower High rule or a
sensitive floor. Configuration validity is checked before its rules are used.

### Use Case 3: Diagnose invalid configuration

**Actor**: Workflow operator.
**Preconditions**: The selected project's path-risk configuration is invalid.

**Steps**:

1. Attempt classification.
2. Read the configuration error identifying the offending field or rule.
3. Correct the configuration and run classification again.

**Postconditions**: No merge-eligible risk result is produced from invalid
configuration. The workflow reports the error instead of silently ignoring it.

**Information shown**: A useful diagnostic without secret values.
**Actions available**: Correct configuration or escalate; no delegated merge.
**Considerations**: A malformed rule anywhere invalidates the map, even when
the rule would not match this PR. Absence and an explicitly empty rule list
are valid and both mean use built-in classification.

## Business Rules

1. Project rules may customize ordinary path categories, including lowering an
   uncategorized implementation path to Low, but cannot reduce built-in High
   protections for auth, authentication, secrets, credentials, or permissions.
2. Existing protections for actual release tooling, branch-deletion tooling,
   and non-test/lint CI workflows remain High and cannot be lowered by the map.
   Existing non-path risk signals and merge gates remain authoritative.
3. A filename containing “release” is insufficient evidence of release tooling.
   Documentation such as `docs/store/first-review/release-checklist.json` is
   ordinary documentation unless another applicable protection or project rule
   raises it. The plan enumerates actual protected release tooling paths.
4. For an ordinary file with project matches, use the highest matching project
   risk instead of its built-in ordinary category. With no match, use the
   built-in result. Apply protected-path floors after considering project rules.
5. A PR's path risk is the highest resulting risk across all changed files.
   Other existing PR risk signals may increase or block its final disposition.
6. Matching is deterministic for repository-relative paths. Rule order and
   specificity do not change the outcome; ties preserve all matching reasons.
   The plan specifies the pattern grammar and path-validation boundary.
7. A malformed map, rule, pattern, risk, or reason fails closed with a diagnostic.
   The plan specifies the supported configuration shape and exact validation.
8. Projects without a map need no migration. Their results remain unchanged
   except for the requested release-filename false-positive correction.
   In particular, missing or empty changed-file evidence retains High risk.
   That absence does not independently prohibit delegated merge: the existing
   risk ceiling and all other merge gates still decide permission. With a High
   ceiling and no other blocker, the current classifier may permit merge;
   this run's Low ceiling does not permit it.
9. Template sync ships support and guidance, not another project's categories.
   Consumer repositories choose their own map. No consumer is edited here.
10. Classification remains read-only. A project map never grants merge,
    review bypass, admin, deletion, or checkpoint authority.

## Classification Decision Matrix

Evaluate configuration validity first, then each changed file, then aggregate
files and existing PR signals. Rows are ordered; the protection row takes
precedence over ordinary matched and unmatched rows.

| Inputs | Allowed outcome | Required next action | Governing surfaces | Example |
| --- | --- | --- | --- | --- |
| Invalid map, including an invalid unmatched rule | Configuration error; no merge-eligible result | Correct configuration or escalate | Config reader, classifier, operator guidance | Unknown risk level |
| Valid absent or empty map | Use built-ins, including corrected release detection | Continue existing gates | Config reader, classifier, tests | No project categories |
| Valid map; protected file, with or without matches | At least High for this file | Existing High-risk authorization or stop | Classifier, protection tests, guidance | Low rule matching an auth directory |
| Valid map; ordinary file; one or more project matches | Highest matched project risk; all matched reasons | Continue existing gates | Classifier, match tests, guidance | Broad Low and narrow High both match → High |
| Valid map; ordinary file; no project match | Built-in category | Continue existing gates | Classifier, regression tests | Unconfigured implementation path → Medium |
| Per-file results available | Highest file risk, subject to existing PR signals | Existing risk/CI/review/checkpoint gates | Classifier and existing callers | Low docs plus High secrets → High |
| Valid configuration; missing or empty changed-file evidence | High risk, preserving existing behavior | Apply the existing risk ceiling and all other merge gates; absence alone adds no merge prohibition | Existing classifier contract and compatibility rule 8 | Empty changed-path list can pass a High ceiling, but not this run's Low ceiling |

## Operational Visibility

- Classification reports matched project reasons and enforced floors alongside
  changed paths. It must not represent a project override as a built-in default.
- Configuration errors identify their location or rule without dumping values
  that might contain secrets. No new notifications or analytics are needed.
- Existing PR disposition and checkpoint audit flows remain in force; this
  feature adds no separate merge or tracker writes.

## Brief Objective List

- O1: Correct the broad release-substring false positive while protecting real
  release tooling.
- O2: Add an optional project path-risk map with immutable sensitive floors.
- O3: Test the false positive, project matching, and floor enforcement.
- O4: Ship a release-note fragment with an issue identifier and descriptive slug.
- O5: Define overlaps, precedence against built-ins, and invalid configuration
  through spec and plan before implementation, as requested by Luis.

## Acceptance Criteria

- [ ] AC1: Without project rules, a docs-only PR changing the incident's
  release-checklist path has Low path risk when no other risk signal applies.
- [ ] AC2: Actual release and branch-deletion tooling and non-test/lint CI
  workflows retain High floors, including under a catch-all Low project rule.
- [ ] AC3: Each existing protected auth, authentication, secret, secrets,
  credential, credentials, permission, and permissions path form stays High
  under Low or Medium project rules, including nested docs and test paths.
- [ ] AC4: A matching project rule sets an ordinary path's category and exposes
  its reason; an unmatched file retains its built-in category.
- [ ] AC5: When project rules overlap, the highest risk wins; reversing their
  order gives the same risk and preserves all applicable reasons.
- [ ] AC6: Absent and empty maps use built-ins without requiring consumer edits.
- [ ] AC7: Invalid maps and invalid matched or unmatched rules report a useful
  configuration error and cannot yield merge-eligible classification.
- [ ] AC8: Mixed changed-file sets aggregate the highest per-file risk. Missing
  or empty changed-file evidence retains High risk without a new independent
  merge prohibition: it may permit merge at a High ceiling when all other
  gates pass, and cannot permit merge at this run's Low ceiling.
- [ ] AC9: Automated regression tests cover AC1–AC8, including a planted attempt
  to lower a sensitive floor that fails and the corrected case that passes.
- [ ] AC10: A maintainer can follow shipped guidance to declare categories,
  understand pattern matching and precedence, and repair invalid configuration.
- [ ] AC11: Implementation ships a slugged issue-specific release-note fragment;
  template sync exposes support without overwriting consumer-specific choices.
- [ ] AC12: Existing non-path blockers, max-risk limits, CI/review requirements,
  and human checkpoints remain enforced with or without project rules.

## Coverage Matrix

| Objective | Acceptance criteria | Deferral |
| --- | --- | --- |
| O1 | AC1, AC2, AC6 | None |
| O2 | AC2–AC8, AC10, AC12 | None |
| O3 | AC9 | None |
| O4 | AC11 | None |
| O5 | AC4–AC7, AC10 | Exact storage shape and pattern grammar belong in the plan |

## Out of Scope (MVP)

- Editing or syncing any consumer repository, submitting a store package, or
  detecting changes in submission state from file contents; Zeki follow-up
  remains owned by Zeki #696.
- Changing workflow autonomy, risk tiers, sensitive protection categories,
  release behavior, review tools, or merge-session behavior.
- Implementing #1960, #1961, #1964, #1967, #1970, or #1449 as separate work.
- Content-based risk analysis, analytics, notifications, and a configuration UI.
