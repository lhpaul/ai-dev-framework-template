# Calibrate Haystack Agent-Doc Mirror Rules — Spec

---

## Overview

This feature makes automated agent-documentation mirror findings match the
repository surfaces that actually exist. Review output should help maintainers
fix real drift between supported Claude, Cursor, Codex, and generic agent
documentation, not chase non-existent mirrors or byte-for-byte comparisons of
tool-specific files.

The result should be a calibrated review rule set that reports actionable mirror
drift, accepts intentional tool-specific front matter differences, and clearly
distinguishes stale or false advisories from findings that require a code or
documentation change.

---

## Brief Objective List

1. Mirror checks use the actual repository surface map.
2. Command docs are checked for semantic sync, not exact full-file equality,
   when tool-specific front matter differs.
3. Missing non-existent mirror paths, such as absent Cursor skills, are not
   reported as required mirrors.
4. Tests or fixtures cover Claude commands to Cursor commands, Claude skills,
   Codex skills, and absent Cursor skills.
5. Reviewer output distinguishes actionable mirror drift from stale or false
   advisory findings.

---

## Use Cases

### Use Case 1: Maintainer Reviews Agent-Doc Mirror Drift

**Actor**: Workflow maintainer
**Preconditions**: A PR changes one or more agent-facing workflow documents or
commands.

**Steps**:

1. The maintainer runs or receives automated review for the PR.
2. The review checks only the agent-documentation surfaces that exist in this
   repository.
3. The review reports any real drift between mirrored surfaces.
4. The maintainer reads the finding and can identify which surface needs a
   change and why.

**Postconditions**: The maintainer has an actionable finding when real mirror
drift exists, or no mirror-drift finding when the changed surfaces remain
semantically aligned.

**Information shown**:

- The affected agent-documentation surface.
- The expected counterpart surface when one exists.
- The reason the finding is actionable.
- Any intentional non-equivalence that makes the finding non-actionable.

**Actions available**:

- Fix the real drift.
- Record a reviewer disposition for a stale or false advisory.
- Leave intentionally different tool-specific front matter unchanged.

**Considerations**:

- Cursor command files and Claude command files can differ in tool-specific front
  matter while still documenting the same workflow behavior.
- A missing surface that is not part of this repository is not drift.

### Use Case 2: Reviewer Evaluates Missing or Non-Equivalent Mirrors

**Actor**: Automated reviewer
**Preconditions**: A PR changes an agent documentation file whose nearest
counterpart is absent or intentionally non-identical.

**Steps**:

1. The reviewer consults the current repository surface map.
2. The reviewer determines whether the expected counterpart exists.
3. If the counterpart does not exist, the reviewer does not require it as a
   mirror.
4. If the counterpart exists but has tool-specific front matter, the reviewer
   evaluates semantic workflow content rather than full-file equality.
5. The reviewer emits output that labels the finding as actionable drift or
   non-actionable advisory.

**Postconditions**: Review output avoids false requirements for non-existent
surfaces and avoids treating intentional front matter differences as mirror
drift.

**Information shown**:

- Whether the counterpart surface exists.
- Whether the comparison is semantic or exact.
- Whether the result is actionable.

**Actions available**:

- Report actionable drift.
- Suppress or downgrade stale/non-actionable mirror findings.

---

## Business Rules

- Mirror checks must use the current repository surface map as the source of
  truth.
- Supported command mirror checks include Claude commands and Cursor commands
  when both corresponding command documents exist.
- Command mirror checks must compare semantic workflow content and must tolerate
  tool-specific front matter differences.
- Supported skill mirror checks include Claude skills, Codex skills, and generic
  agent skills where this repository provides corresponding surfaces.
- Cursor skills are not a required mirror surface unless the repository actually
  contains a Cursor skills surface.
- Reviewer output must identify whether a mirror finding is actionable drift or
  a stale/non-actionable advisory.
- A missing non-existent surface must not be presented as a required work item.
- The feature must be verifiable with fixtures or tests that represent the
  actual supported and absent surfaces.

---

## Operational Visibility

- **Reviewer output**: Mirror-related findings must name the compared surfaces
  and classify the result as actionable drift or non-actionable advisory.
- **Audit trail**: When a finding is non-actionable because the mirror surface
  does not exist or only tool-specific front matter differs, the output must
  include enough context for the maintainer to justify the disposition in the PR.

---

## Acceptance Criteria

- [ ] A mirror check uses the current repository surface map and does not require
  surfaces that are absent from the repository.
- [ ] A changed Claude command and its Cursor command counterpart are evaluated
  for semantic workflow alignment, while intentional tool-specific front matter
  differences are not reported as drift.
- [ ] An absent Cursor skills surface is not reported as a missing required
  mirror.
- [ ] Fixture or test coverage includes Claude commands to Cursor commands,
  Claude skills, Codex skills, and absent Cursor skills.
- [ ] Reviewer output for a real mismatch labels the finding as actionable mirror
  drift and names the affected surfaces.
- [ ] Reviewer output for a stale or false mirror finding labels it as
  non-actionable and explains why it is not required.
- [ ] The calibrated output gives maintainers enough information to fix real
  drift without consulting the implementation internals.

---

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Mirror checks use the actual repository surface map. | AC 1 |
| Command docs are checked for semantic sync, not exact full-file equality, when tool-specific front matter differs. | AC 2 |
| Missing non-existent mirror paths, such as absent Cursor skills, are not reported as required mirrors. | AC 3 |
| Tests or fixtures cover Claude commands to Cursor commands, Claude skills, Codex skills, and absent Cursor skills. | AC 4 |
| Reviewer output distinguishes actionable mirror drift from stale or false advisory findings. | AC 5, AC 6, AC 7 |

---

## Out of Scope (MVP)

- Adding a new Cursor skills surface solely to satisfy mirror parity.
- Requiring byte-for-byte equality across tool-specific agent documentation.
- Rewriting all existing agent documentation as part of this calibration.
- Changing external reviewer service behavior outside this repository's
  configurable rules, fixtures, prompts, or review guidance.
- Defining implementation-specific parser, matcher, or file-enumeration
  mechanics; those belong in the implementation plan.
