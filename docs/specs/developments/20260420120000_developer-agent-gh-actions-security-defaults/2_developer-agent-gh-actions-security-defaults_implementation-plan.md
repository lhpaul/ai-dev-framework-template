# Developer Agent: GitHub Actions Workflow Security Defaults — Implementation Plan

**Spec**: [`1_developer-agent-gh-actions-security-defaults_specs.md`](1_developer-agent-gh-actions-security-defaults_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/developer-agent-gh-actions-security-defaults.smoke-test.md`](../../../testing/workflow/developer-agent-gh-actions-security-defaults.smoke-test.md)

---

## Summary

**Approach**: Add a single top-level section to `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` immediately after the “Which Path to Use?” table (before `## Path 1: Full Pipeline`) so every implementation path sees it. The section defines when the gate applies (new or materially changed `.github/workflows/*.yml`), states that the checklist must be satisfied **before** opening or updating a development PR with those changes, and embeds an explicit Markdown checklist covering least-privilege `permissions`, pinned `uses:` SHAs with version comments, optional `paths` / `paths-ignore`, and optional `concurrency`. Add one-line cross-references from Path 2 (Refactor), Path 3 (Fast Track), and Path 4 (Hotfix) Step 1 prep lists pointing agents to that section when their branch will touch workflow files, so the rule is not Full-Pipeline-only in practice.

**Estimated complexity**: **S**

**Rationale**: Documentation-only change in one primary protocol file plus minimal cross-refs; no code, schema, or CI workflow edits in this item.

**Dependencies**: None (matches spec `Depends on`).

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] Not applicable

### Backend / API

- [ ] Not applicable

### Shared Packages / Libraries

- [ ] Not applicable

### Frontend / UI

- [ ] Not applicable

### Infrastructure / Configuration

- [ ] Not applicable — this plan does **not** retrofit existing workflows under `.github/workflows/` (explicitly out of scope in the spec).

### Documentation

- [ ] `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` — insert **`## GitHub Actions workflow security (mandatory when applicable)`** after the “Which Path to Use?” section divider and before `## Path 1: Full Pipeline`. Include:
  - **Trigger**: new file under `.github/workflows/*.yml` or material edits (behavior, triggers, security posture — not typo-only / comment-only).
  - **Timing**: complete checklist **before** opening the development PR, or before pushing workflow commits if the PR already exists.
  - **Checklist** (checkbox list): explicit minimum `permissions:` (default read-only guidance `contents: read` when sufficient); every third-party `uses:` pinned to full commit SHA with `# vX.Y.Z` (or equivalent) comment; `paths` / `paths-ignore` when the workflow should only run for certain paths; `concurrency` when duplicate runs on the same ref are harmful; exceptions documented in the PR description.
- [ ] Same file — in **Path 2: Refactor** → Step 1 numbered list, add a bullet: when the change set includes `.github/workflows/*.yml`, complete the GitHub Actions workflow security section above before coding.
- [ ] Same file — in **Path 3: Fast Track** → Step 1 (or equivalent prep) add the same pointer if a fast-track change can include workflow files (even rare, keeps the contract complete).
- [ ] Same file — in **Path 4: Hotfix** → Step 1 prep add the same pointer when the hotfix branch will touch `.github/workflows/*.yml`.

---

## Testing Strategy

**Test types**: Manual / documentation review (no automated test harness for prose).

**Key scenarios to test**:

1. A reader finds the new section without opening Full Pipeline only — maps to **AC** “clearly titled section … used during implementation.”
2. Checklist rows map 1:1 to business rules — maps to **AC** checklist content and “before PR open” language.

**Smoke test runbook**: [`docs/testing/workflow/developer-agent-gh-actions-security-defaults.smoke-test.md`](../../../testing/workflow/developer-agent-gh-actions-security-defaults.smoke-test.md)

**Regression suite**: Not applicable for doc-only template work unless the repo adds automated spec tests for protocol text (none required today).

---

## Seed Data

| Entity | Values / Scenario | File |
|---|---|---|
| None | No seed data | — |

---

## Documentation Updates

Per protocol 02: list project docs the **developer** must touch during implementation (post-plan merge).

- [ ] `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` — as in Layer-by-Layer; this is the only required edit for acceptance criteria.
- [ ] **None** for `AGENTS.md`, `docs/project/*`, and `docs/best-practices/stack/*` unless the developer discovers an existing duplicate workflow-security note that must be deduplicated (then grep-driven consistency per Path 1 Step 1b item 6 in the same protocol).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Checklist buried below long Path 1 content | Low | Medium | Place section **above** Path 1 so it appears in the first screen of the doc. |
| Wording contradicts `.github` or security docs elsewhere | Low | Low | During implementation, run `grep -Ri "permissions:" docs/ai/development-workflow/` (and similar) to align terminology. |

---

## Code Samples

None — illustrative YAML for `permissions` / `uses:` may appear in the protocol during implementation but must be labeled **Illustrative — adapt during implementation** per plan template rules.

---

## Implementation Order

1. Re-read the merged spec and this plan in the feature branch workspace.
2. Insert `## GitHub Actions workflow security (mandatory when applicable)` in `03-implement-development-protocol.md` at the location described above; include trigger, timing, and full checklist aligned with spec Business Rules.
3. Add Refactor, Fast Track, and Hotfix cross-reference bullets so non–Full-Pipeline paths that touch workflows are covered.
4. Proofread: every spec acceptance criterion satisfied by explicit protocol text.
5. Run markdown lint / heuristic lint on touched paths if the implementation PR’s CI includes them.
6. Execute the smoke test runbook on the implementation PR branch before marking the feature PR human-ready.
7. Add `CHANGELOG.md` entry under `[Unreleased]` on the **feature** PR (plan PR is exempt); describe the new developer workflow requirement from the user’s perspective.
