# feat(tech-lead): Parser and regex plan rigor — Spec

**Depends on**: none

---

## Overview

Implementation work that adds or changes custom parsers, regex-heavy scanners, or structured-text lint rules tends to ship with correctness bugs that surface only after multiple automated and human review rounds. This specification defines what the AI development workflow must require **at the implementation-plan stage** so that edge cases and automated tests are explicit before coding begins, reducing reviewer load and preventing predictable defect classes. The change is scoped to workflow documentation (primarily the tech-lead / implementation-plan protocol and related templates), not to any particular application runtime feature.

---

## Use Cases

### Use Case 1: Tech-lead drafts a plan that introduces parser-like behavior

**Actor**: Tech-lead agent (or human tech lead) authoring an implementation plan for work that matches the **parser-risk category** (see Business Rules).
**Preconditions**: A merged or approved feature spec exists for the item; the work item is in the plan-writing stage.

**Steps**:
1. Author opens the canonical implementation-plan protocol and plan template guidance for parser-risk work.
2. Author completes the mandatory **Edge-case enumeration** subsection with concrete inputs (positive, boundary, and negative cases) before describing layer-by-layer file changes.
3. Author completes the **Testing strategy** subsection so it names at least one unit test module and maps tests to the enumerated edge cases (one or more tests per enumerated case).
4. If the feature includes inline suppression or similar directives, author completes **Suppression semantics** as specified in Business Rules.

**Postconditions**: The plan document contains reviewer-verifiable content that explains how the parser or scanner should behave on tricky inputs before implementation starts.

**Information shown**: Plan markdown as consumed by implementers and reviewers.

**Actions available**: Author revises the plan until the mandatory sections are present.

**Considerations**:
- Enumeration must go beyond happy paths: include boundary characters, false-positive shapes, multiple matches on one line, nesting or overlap where relevant, and spec-level flexibility when a formal spec applies (e.g., CommonMark fence rules).
- "Manual only" or "smoke only" testing is insufficient for parser-risk plans; unit tests must be specified for the enumerated cases.

---

### Use Case 2: Implementer executes a plan that was marked parser-risk

**Actor**: Developer agent or human developer.
**Preconditions**: Merged implementation plan includes the mandatory subsections from Use Case 1.

**Steps**:
1. Implementer reads edge-case bullets and suppression semantics before coding.
2. Implementer adds or updates the named unit tests to cover each enumerated case.
3. Implementer runs the test suite locally (or in CI) before opening the implementation PR.

**Postconditions**: Implementation PR ties behavior to the enumerated cases; reviewers can trace each bullet to a test.

**Information shown**: Plan sections and linked test file paths.

**Actions available**: Implementer requests plan clarification if an edge case is ambiguous (tracked as a plan revision or issue comment).

**Considerations**:
- If the plan omitted required subsections, the implementer should stop and route back to plan revision rather than inventing missing semantics in code alone.

---

### Use Case 3: Reviewer validates plan completeness for parser-risk work

**Actor**: Plan reviewer (human or agent) during plan review gate.
**Preconditions**: Plan PR is open; branch matches `implementation-plan/*`.

**Steps**:
1. Reviewer classifies whether the plan falls under parser-risk rules using the same signals as the tech-lead (see Business Rules).
2. Reviewer checks for edge-case enumeration, mapped unit tests, and suppression semantics when applicable.
3. Reviewer records blocking feedback if any mandatory subsection is missing or vague.

**Postconditions**: Parser-risk plans cannot pass review until the checklist is satisfied.

**Information shown**: Plan markdown and review checklist derived from this spec.

**Actions available**: Request changes on the plan PR.

**Considerations**:
- Vague bullets ("handle edge cases") do not satisfy the enumeration requirement; inputs should be concrete enough that a test author can implement without guessing product intent.

---

## Business Rules

- **Parser-risk category**: A plan is in this category when it introduces or materially changes behavior described as scanning, parsing, linting, or regex-matching of structured text (markdown, code, config, logs, etc.), including new modules under conventional tooling paths (for example `scripts/lint/`, `scripts/parse/`, or filenames suggesting lint/parser/scanner responsibilities). The published protocol must give tech-lead agents deterministic signals for this classification so they do not rely on ad hoc judgment alone.
- **Edge-case enumeration (mandatory for parser-risk)**: The plan must include a dedicated subsection listing specific inputs covering at least: boundary-character variants; negative cases (strings that look like matches but must not match); multiple occurrences on a single line; nested or overlapping constructs where applicable; and spec-level flexibility when a normative spec governs the format (e.g., flexible fence lengths).
- **Unit test requirement (mandatory for parser-risk)**: The testing strategy must name a concrete unit test file (language appropriate to the repo) and require at least one automated test per enumerated edge case. Smoke or manual-only verification does not satisfy this rule for parser-risk work.
- **Suppression semantics (conditional)**: If the feature supports inline or directive-based suppression of warnings/rules, the plan must state which directives are recognized, where they may appear, and how multiple suppressions on one line are interpreted.
- **Scope of code changes**: Delivering this spec may update workflow docs (implementation-plan protocol, tech-lead agent instructions, and/or plan template). It must not require unrelated refactors of existing parsers unless a separate work item covers that scope.

---

## UX Rules

Not applicable (workflow documentation and agent behavior).

---

## Statuses / Enum Values

Not applicable.

---

## Operational Visibility

Not applicable beyond normal PR and CI visibility for documentation changes.

---

## Acceptance Criteria

- [ ] The implementation-plan protocol (and/or plan template) documents a **conditional** "Custom parser / regex / text-scanning" block that applies only when a plan is classified as parser-risk, and lists the three mandatory elements: edge-case enumeration, unit-test mapping, and conditional suppression semantics.
- [ ] Tech-lead guidance tells the agent how to detect parser-risk plans using explicit path/name heuristics aligned with this spec (without turning the spec itself into a low-level file manifest that goes stale).
- [ ] Plan review checklist or reviewer guidance references the same three elements so reviewers can reject incomplete parser-risk plans deterministically.
- [ ] A reader can take a hypothetical markdown-lint-style feature and derive an acceptable plan outline from the new guidance without asking for undocumented rules.

---

## Out of Scope (MVP)

- Rewriting or re-testing existing production parsers (e.g., post-merge hardening of PR #198) unless covered by a separate issue.
- CI enforcement that parses plan markdown automatically (optional future work).
- Changes to the feature spec stage beyond cross-links if needed for traceability.
