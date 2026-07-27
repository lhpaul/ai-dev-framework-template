# Native GitHub Issue Type Classification - Spec

**Issue**: #1280

---

## Overview

GitHub Projects can classify issues with either project-specific single-select
fields or GitHub's native Issue Type. The workflow currently recognizes only
project-specific fields, so repositories that rely on native Issue Type can
have valid `Feature`, `Bug`, or `Task` classifications treated as missing. This
feature makes native Issue Type a supported classification source while
preserving existing custom-field behavior and warnings.

## Brief Objective List

- **BO-1**: Recognize a project item's native GitHub Issue Type as a valid
  workflow classification source.
- **BO-2**: Preserve deterministic precedence when configured, native, and
  conventional custom classification sources are present together.
- **BO-3**: Preserve existing custom-field fallback behavior when native Issue
  Type is absent or empty.
- **BO-4**: Return `Feature` when a project item has native Issue Type
  `Feature` and no custom `Type` value.
- **BO-5**: Do not emit a misleading missing-classification warning when a
  native Issue Type supplies the classification.
- **BO-6**: Cover native classification, fallback behavior, and precedence with
  automated regression tests.

## Use Cases

### Use Case 1: Classify an issue from native Issue Type

**Actor**: Workflow runner
**Preconditions**: The repository uses GitHub Projects, the issue belongs to the
configured project, and the issue has a native GitHub Issue Type.

**Steps**:

1. The runner reads the issue's project item before choosing a workflow path.
2. No higher-precedence configured classification value is available.
3. The runner recognizes the native Issue Type as the issue's classification.
4. The runner continues with the workflow path associated with that
   classification.

**Postconditions**: A valid native Issue Type is returned as the issue's
workflow classification and is not treated as missing.

**Information shown**:

- The resolved classification is available to workflow routing and reporting.
- No missing-classification warning is shown for this item.

**Actions available**:

- Continue the normal workflow for the resolved classification.

**Considerations**:

- Native Issue Type names are returned without being remapped by this feature.
- A native type that exists alongside a configured classification field does
  not override the configured value.

### Use Case 2: Preserve custom classification fallback

**Actor**: Workflow runner
**Preconditions**: The repository uses GitHub Projects and the project item has
no native Issue Type value.

**Steps**:

1. The runner reads the issue's project item.
2. The runner finds no usable native Issue Type.
3. The runner checks the existing supported custom classification sources in
   their established order.
4. The runner uses the first available custom classification value.

**Postconditions**: Repositories that do not use native Issue Type retain their
current classification behavior.

**Information shown**:

- The resolved custom classification is available to workflow routing and
  reporting.

**Actions available**:

- Continue the normal workflow for the resolved classification.

**Considerations**:

- An absent or empty native Issue Type is equivalent to having no value; it is
  not an error.
- Existing configured and convention-based project fields remain supported.

### Use Case 3: Report a genuinely unclassified issue

**Actor**: Workflow runner
**Preconditions**: The issue belongs to the configured GitHub Project and none
of the supported classification sources has a value.

**Steps**:

1. The runner checks each supported classification source in precedence order.
2. No source provides a classification.
3. The runner preserves the existing untyped result and warning behavior.

**Postconditions**: A genuinely unclassified project item remains visibly
untyped instead of being assigned an invented default.

**Information shown**:

- The existing missing-classification warning identifies that no supported
  classification value was found.

**Actions available**:

- A maintainer can assign a supported native or project-specific
  classification and rerun the workflow.

**Considerations**:

- The warning is emitted only after all supported classification sources have
  been checked.

## Business Rules

- **BR-1**: Native GitHub Issue Type is a valid workflow classification source
  for GitHub Projects issues.
- **BR-2**: Classification source precedence is: configured project
  classification field, native GitHub Issue Type, `Custom Type`, `CustomType`,
  then `Type`.
- **BR-3**: The first non-empty classification in the precedence order is the
  resolved classification.
- **BR-4**: An absent, null, or empty native Issue Type must not interrupt or
  change the existing custom-field fallback chain.
- **BR-5**: A native Issue Type that resolves the classification must suppress
  the missing-classification warning.
- **BR-6**: If every supported classification source is empty, the workflow
  preserves the existing untyped result and missing-classification warning.
- **BR-7**: This feature does not rename, normalize, or translate classification
  values; the selected source's name is returned as provided by GitHub.
- **BR-8**: All workflow consumers of the shared GitHub Projects
  classification result must observe the same precedence and outcome.

## Classification Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Configured project classification has a value | Use configured value | Stop evaluating lower-precedence sources and continue the matching workflow | All consumers of the shared GitHub Projects classification result | Configured value `Workflow` wins over native `Feature` |
| Configured value is empty and native Issue Type has a value | Use native value | Continue the workflow without a missing-classification warning | Tracker reads, workflow routing, and regression evidence | Native `Feature` resolves to `Feature` |
| Configured and native values are empty; `Custom Type` has a value | Use `Custom Type` value | Continue the matching workflow | Existing custom-field consumers and regression evidence | `Custom Type` value `Refactor` is preserved |
| Higher-precedence sources are empty; `CustomType` has a value | Use `CustomType` value | Continue the matching workflow | Existing compact custom-field consumers and regression evidence | `CustomType` value `Bug` is preserved |
| Higher-precedence sources are empty; `Type` has a value | Use `Type` value | Continue the matching workflow | Existing conventional-field consumers and regression evidence | `Type` value `Workflow` is preserved |
| Native Issue Type is absent or null and a lower-precedence custom source has a value | Use the first available lower-precedence value | Continue normal fallback behavior | All repositories that do not use native Issue Type | Null native type does not block custom `Type` |
| Every supported source is empty | Return untyped result | Emit the existing missing-classification warning and require tracker correction before typed routing | Tracker warning and workflow reporting | No type value produces the existing warning |

## Operational Visibility

- **Resolved classification**: Workflow routing and diagnostic output use the
  selected classification value.
- **Warning behavior**: A missing-classification warning remains visible when,
  and only when, every supported source is empty.
- **Regression evidence**: Automated tests demonstrate the selected source for
  native-only, precedence, fallback, and fully missing cases.

## Acceptance Criteria

- **AC-1**: Given a GitHub Project item with native Issue Type `Feature` and no
  custom `Type` value, when the workflow reads its classification, then it
  returns `Feature`.
- **AC-2**: Given the item in AC-1, when classification completes, then no
  missing-classification warning is emitted.
- **AC-3**: Given both a configured project classification value and a native
  Issue Type, when classification runs, then the configured value is selected.
- **AC-4**: Given no configured value, a native Issue Type, and one or more
  conventional custom classification values, when classification runs, then
  the native Issue Type is selected.
- **AC-5**: Given no configured or native value and values in multiple
  conventional custom classification fields, when classification runs, then
  the existing custom-field precedence remains `Custom Type`, `CustomType`,
  then `Type`.
- **AC-6**: Given a null or absent native Issue Type and an existing custom
  classification value, when classification runs, then the custom value is
  returned without error.
- **AC-7**: Given no value in any supported classification source, when
  classification runs, then the workflow returns an untyped result and emits
  the existing missing-classification warning.
- **AC-8**: Automated regression coverage verifies native-only resolution, the
  configured-over-native precedence, native-over-custom precedence, existing
  custom fallback order, and the fully missing warning case.

## Coverage Matrix

| Brief objective | Covered by | Notes |
| --- | --- | --- |
| BO-1 | BR-1, BR-3, Use Case 1, AC-1 | Makes native Issue Type a supported classification source. |
| BO-2 | BR-2, BR-3, Classification Consistency Matrix, AC-3, AC-4, AC-5 | Defines and verifies the complete source precedence. |
| BO-3 | BR-4, Use Case 2, AC-5, AC-6 | Preserves behavior for projects without native Issue Type. |
| BO-4 | Use Case 1, AC-1 | Covers the native `Feature` case from the brief. |
| BO-5 | BR-5, Operational Visibility, AC-2, AC-7 | Distinguishes resolved native classifications from genuinely missing ones. |
| BO-6 | Operational Visibility, AC-8 | Requires automated evidence for all decision branches. |

## Out of Scope (MVP)

- Changing how GitHub Project items are added, updated, or assigned a type.
- Renaming or normalizing native or custom classification values.
- Adding new workflow classifications or changing how `Feature`, `Bug`,
  `Refactor`, or `Workflow` routes behave after classification.
- Prescribing the query structure, parser implementation, helper names, or test
  fixture mechanics; those decisions belong in the implementation plan.
- Extending native issue-type support to issue tracker providers other than
  GitHub Projects.
