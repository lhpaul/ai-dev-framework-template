# Plan-Authoring Rigor — Implementation Plan

**Spec**:
[1_1496-plan-authoring-rigor_specs.md](./1_1496-plan-authoring-rigor_specs.md)
**Smoke test runbook**:
[1496-plan-authoring-rigor.smoke-test.md](../../../testing/workflow/1496-plan-authoring-rigor.smoke-test.md)

---

## Summary

**Approach**: Add one canonical, framework-portable rules document for the six
plan-authoring rules, wire it into Protocol 02 and plan-writer agent/skill
surfaces as authoring obligations, extend `REVIEW.md` and the plan-reviewer
agents with the matching backstop check, extend the implementation-plan
template so firing-rule evidence has a predictable home in the plan body, and
extend Protocol 02's existing `Document Quality Gate` PR-description block with a
mandatory **per-rule outcome record** (Groups A and H). No linter, bot, or
script **detects or enforces the six authoring rules against plan text** —
that remains Out of Scope for MVP. The mirror harness added below is an
**addition** (not in the spec): a doc-consistency check that mirrors agree on
rule names, outcome labels, and the canonical path — it does not score plan
claims.

**Canonical surface decision (spec Business Rules — mirror surfaces)**: The
single canonical statement of the six rules **and** the plan review gate
extension lives in
`docs/workflow/development-workflow/plan-authoring-rigor-rules.md`. Every other
surface agrees with it: same rule names (`Rule 1` … `Rule 6`), same three
outcome labels (`Satisfied`, `Not applicable`, `Unsatisfied`), same blocking vs
non-blocking classifications for gate rows. The spec's full Decision-Gate
Consistency Matrix is **copied into** that file as the normative gate section
during implementation (do not paraphrase pass conditions). The approved spec
remains historical product intent; after merge, engineers treat the new rules
file as authoritative for day-to-day plan work. To keep exactly one canonical
surface, the implementation PR also edits the retained spec's matrix
introduction (`## Decision-Gate Consistency Matrix`, the sentence declaring the
matrix canonical) into a pointer stating that the matrix is now canonical in
`plan-authoring-rigor-rules.md` and that the spec copy is historical.

**Estimated complexity**: L

**Rationale**: Six rules with a large gate matrix, seven mirror surfaces, and
cross-cutting updates to protocols, `REVIEW.md`, four agent files, one Codex
skill, a template, and a mirror-consistency test harness. No runtime code, but
documentation must stay internally consistent or downstream adopters inherit
silent drift — the failure mode this feature exists to prevent.

**Dependencies**: None. Spec merged (#1736). Does not depend on #1655 strict
plan checks; strict checks stay non-blocking; this feature adds blocking
backstop obligations in `REVIEW.md` only where the spec gate matrix says
blocking.

**Parser-risk classification**: **Applicable** — the mirror harness parses
structured Markdown and agent docs with `grep`/`awk`/`sed` to find rule names,
outcome labels, and canonical path references. A false match or missed mirror
silently ships drift.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `6c84855e` — the revision at which every row below was gathered (base `origin/develop` tip: `f1d5021a`); the later plan-branch commits only add rows or edit plan prose and change no gathered result. This is the **evidence-gathered** revision (spec Rule 3/4: evidence names the revision it was gathered at). The plan revision that must equal the PR head is recorded in the PR body's per-rule outcome record, which is not part of the branch and so can name the head without changing it; that record is re-determined against the head before `ready-for-human-review`. Re-gather any row whose claim a later commit changes |
| Template path | `test -f docs/workflow/development-workflow/templates/implementation-plan-template.md`; `test ! -f docs/workflow/development-workflow/implementation-plan-template.md` | exit `0` for both — the `templates/` path is the only real path; every plan reference uses it |
| Codex skill alias | `test -L .agents/skills/workflow-plan-writer && readlink .agents/skills/workflow-plan-writer` | `../../.codex/skills/workflow-plan-writer` — symlink; the `.codex` edit is the only source edit |
| Codex reviewer skill | `test -f .codex/skills/workflow-plan-reviewer/SKILL.md && test -L .agents/skills/workflow-plan-reviewer && grep -n '02-review-implementation-plan-protocol' .codex/skills/workflow-plan-reviewer/SKILL.md` | present; symlink; line `11` reads the Protocol 02 review file — no-edit disposition |
| Spec merged | `test -f docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | present on branch |
| Protocol 02 review target | `test -f docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md` | Present — verified 2026-09-20. Named in Layer-by-Layer, Files to modify, and Implementation Order step 5 |
| Protocol 02 authoring target | `test -f docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Present — verified 2026-09-20 |
| Mirror agent/skill targets | `for f in .claude/agents/tech-lead.md .cursor/agents/tech-lead.md .claude/agents/implementation-plan-reviewer.md .cursor/agents/implementation-plan-reviewer.md .codex/skills/workflow-plan-writer/SKILL.md; do test -f "$f" \|\| echo MISSING:$f; done` | All five present — verified 2026-09-20 |
| Spec Decision-Gate Consistency Matrix | `grep -n 'Decision-Gate Consistency Matrix' docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | Present as a top-level `## Decision-Gate Consistency Matrix` section at spec line 338 — verified 2026-09-20. Copy verbatim during implementation (Rule 4 backstop) |
| Rule headings in spec | `awk '/^### Rule [0-9]/{c++} END{print c}' docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | `6` |
| Existing plan Document Quality Gate | `grep -n 'Document Quality Gate' docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | first hit `441:7. **Document Quality Gate (mandatory — do not skip)**:` — Step 5 item 7; extension point for per-rule record |
| Plan review checklist location | `awk '/^## Plan Review Checklist/{print NR; exit}' REVIEW.md` | line `117` |
| Agent/skill protocol references | `grep -rl '02-generate-implementation-plan-protocol\|03-implement-development-protocol' .claude/agents/ .cursor/agents/ .codex/skills/` | six paths: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` |
| Plan reviewer agents | `ls .claude/agents/implementation-plan-reviewer.md .cursor/agents/implementation-plan-reviewer.md` | both present |
| Mirror harness pattern file | `test -f scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh` | exit `0` — present; pattern for new mirror harness |
| `AGENTS.md` Key Documentation table | `grep -n '## Key Documentation' AGENTS.md` | `25:## Key Documentation` — table exists for new rules-file row |
| Workflow README plan-stage section | `grep -n '### Implementation Plan' docs/workflow/development-workflow/README.md` | `73:### Implementation Plan` — plan-stage section exists for one-line pointer |
| Workflow test CI selector | `grep -n 'select-test-suites.sh\|Adding a suite' .github/workflows/workflow-tests.yml`; `grep -n "name 'test-\*\.sh'" scripts/development-workflow/select-test-suites.sh` | workflow lines `11`–`13` state suites are selected by `select-test-suites.sh` (no hard-coded list); `list_suites` at line `222` runs `find … -name 'test-*.sh'` — **enforced in CI**: a new `test-plan-authoring-rigor-mirror.sh` is discovered automatically; no separate aggregator file to edit |
| Strict plan checks (orthogonal) | `head -5 docs/workflow/development-workflow/strict-plan-checks.md` | non-blocking contract checks — unchanged scope |
| Markdown CI covers workflow docs | `sed -n '12,16p' .github/workflows/markdown-lint.yml` | includes `docs/workflow/**` |
| Smoke runbook on plan branch | `test -f docs/testing/workflow/1496-plan-authoring-rigor.smoke-test.md` | present on this plan branch — execute scenarios during implementation QA (do not re-author) |
| No existing rules file | `test ! -e docs/workflow/development-workflow/plan-authoring-rigor-rules.md` | true at recorded revision — file is created in implementation |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop` | Batch handoff / Protocol 91 default | 2026-09-18, SHA `b0491be3` (plan HEAD); `origin/develop` tip `f1d5021a` | Item #1496 only | `Verified` |
| Batch invocation peers | `1757,1462,1496,1515,1561,1583,1529` | Parent `/run-items` explicit list | 2026-09-17 | Same-surface open PRs: none per handoff | `Verified` — no same-surface plan/spec PR conflict for #1496 |
| Canonical rules not yet on disk | rules file absent | Verification Log last row | 2026-09-18 | N/A | `Verified` — implementation creates it |

**Overall result**: `Applicable` — re-verify base branch at implementation start.

### Not applicable

Database, runtime services, product repositories, deployment targets, and
external API contracts do not apply.

---

## Decision gate — plan review backstop (extended)

This feature **modifies** the plan review gate: new inputs (per-rule outcome
record, evidence in plan body, repository re-runs) and new blocking /
non-blocking outcomes. The **full** gate inputs, triggers, allowed outcomes,
required next actions, mirror surfaces, and examples are defined in the spec
section **Decision-Gate Consistency Matrix**. Implementation copies that section
into `plan-authoring-rigor-rules.md` under a dedicated heading so the canonical
rules file carries both authoring rules and reviewer gate behavior (spec mirror
table row "plan review checklist" + "quality gate log").

Summary for plan reviewers reading **this** document only:

| Gate input (added or emphasized) | Source |
| --- | --- |
| Whether each rule fires | Plan text |
| Evidence for firing rules | Plan document only |
| Reproducibility at recorded revision / population / window | Re-run recorded commands |
| Per-rule outcome record | Plan PR `Document Quality Gate` |
| Stale outcome record vs plan HEAD | Compare record's plan revision to PR head SHA |

| Representative blocking situation | Author next action |
| --- | --- |
| Firing rule with no evidence in plan | Add evidence or remove claim |
| Record missing or wrong revision SHA | Re-determine all outcomes at current head |
| Rule 4 claim supported only by delegation | Record direct search or drop claim |
| Rule 2 disagreeing duplicate assertions | Resolve to one assertion |

| Representative non-blocking situation | Notes |
| --- | --- |
| Rule 2 agreeing duplicates | Consolidation finding; rule stays Satisfied |
| Rule 1 adequacy rationale structurally complete but unpersuasive | Reviewer judgment; Satisfied while open |

**Triggers**: plan PR reaches plan review gate; each correction round
re-determines outcomes afresh (Group H).

**Mirror surfaces** (implementation must update every row):

| Surface | Role | Consistency requirement |
| --- | --- | --- |
| `plan-authoring-rigor-rules.md` | Canonical rules + gate matrix | Full normative text |
| Protocol 02 Step 3 + Document Quality Gate | Authoring obligations + outcome record schema | Points to canonical file; no weaker pass conditions |
| `implementation-plan-template.md` | Evidence placement in plan body | Verification Log / plan sections hold Rule 3/4/5 evidence |
| `REVIEW.md` Plan Review Checklist | Backstop check | Same rule names and blocking classes |
| `.claude/.cursor/agents/tech-lead.md` + Codex `workflow-plan-writer` | Plan-writer routing | Author obligations only |
| `.claude/.cursor/agents/implementation-plan-reviewer.md` | Reviewer routing | Backstop + outcome record checks |
| Plan PR `Document Quality Gate` | Per-rule outcome record | All six rules + revision SHA + N/A rationales |

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable.

### Shared Packages / Libraries

Not applicable.

### Documentation / Workflow

- [ ] **Create `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.**
      Structure:

      1. Purpose (one paragraph — plans read as fact; backstop complements diff
         review).
      2. Rules 1–6 — port **verbatim** from the spec **Business Rules**
         section (including "Rules that apply across all six"). Do not introduce
         repository-specific paths or stack names.
      3. Status labels — table from spec **Statuses / Enum Values** (code values
         may stay in backticks for tooling; display labels must match Group H).
      4. **Plan review gate** — copy spec **Decision-Gate Consistency Matrix**
         subsections (Gate inputs, Triggers, Allowed outcomes and required next
         actions, Mirror surfaces, Examples) unchanged in substance.
      5. Cross-link to spec dev folder for historical context only.

      Maps to Groups A, B–G (normative text), H (gate).

- [ ] **Protocol 02 — authoring and PR gate.**
      File:
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.

      - Step 3 **Quality guardrails**: add a bullet block "Plan authoring
        rigor" requiring authors to read the canonical rules file, record
        firing-rule evidence **in the plan** (Verification Log and/or dedicated
        subsections), and treat Rule 2 as firing on every non-empty plan.
      - Step 5 **Document Quality Gate**: extend the example markdown with a
        subsection:

        ```markdown
        ### Plan authoring rigor — per-rule outcome record

        Plan revision: `<git rev-parse --short HEAD of plan branch>`

        | Rule | Outcome | Rationale / first external inspection finding |
        | --- | --- | --- |
        | Rule 1 | Not applicable | No design depends on external free-text output. |
        | Rule 2 | Satisfied | Single assertion per fact; see Verification Log. |
        | … | … | … |
        ```

        Document that:

        - All six rules appear exactly once.
        - Outcomes use the three display labels only.
        - `Not applicable` rows include a one-line trigger rationale.
        - Rows for Rules 1 external citations (contract, manifest, notice,
          protected artifact) include the first-inspecting round's finding when
          applicable.
        - Authors refresh the record whenever plan text changes; revision SHA
          must match PR head before `ready-for-human-review`.
      - These obligations apply to **every** Protocol 02 plan, including
        Refactor / no-spec work items — there is no bypass when a product
        spec is absent.
      - Step 3 cross-cutting checklist enumeration: this plan **is** a
        cross-cutting checklist change — the Files to modify section below is
        authoritative.

      Maps to Groups A, H; Operational Visibility.

- [ ] **`REVIEW.md` Plan Review Checklist.**
      Add a checklist block **Plan authoring rigor (backstop)** after existing
      items (before Typical blocking issues):

      - Read the canonical rules file and the plan's per-rule outcome record.
      - For each rule recorded as firing, re-run repository-derived evidence at
        the recorded revision; for Rule 1 sampling/enumeration, follow spec
        Group A external-source exception.
      - Raise blocking findings per the gate matrix; distinguish non-blocking
        consolidation and adequacy judgments.
      - Treat missing outcome record, missing N/A rationale, stale revision SHA,
        or evidence only in PR comments as blocking per Group H.

      Do **not** duplicate the full matrix prose — reference the canonical file.

      Maps to Use Case 7; Group H.

      **Reversal**: To undo after merge, revert in reverse mirror order —
      remove the `REVIEW.md` backstop block and Protocol 02 outcome-record
      schema, delete agent/skill pointers, remove the template evidence
      subsection, delete `plan-authoring-rigor-rules.md` and the mirror
      harness, then drop the `AGENTS.md` / README rows. Spec Out of Scope
      defers per-repository opt-out; there is no feature flag.

- [ ] **Plan review protocol pointer.**
      File:
      `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`.
      Add one paragraph: plan reviewers apply the backstop in `REVIEW.md` and
      the gate matrix in `plan-authoring-rigor-rules.md`; outcome record lives
      in PR description Document Quality Gate.

- [ ] **Implementation plan template.**
      File:
      `docs/workflow/development-workflow/templates/implementation-plan-template.md`.

      - Expand Verification Log intro to state it holds Rule 3 count
        derivations, Rule 4 existence searches, and Rule 5 consumer enumerations
        when those rules fire.
      - Add optional subsection **Factual claim evidence** (after Verification
        Log) with placeholders for Rule 1 sampling/enumeration records and Rule
        6 scoped obligations — authors delete if not applicable.

      Maps to mirror surface "plan document evidence area".

- [ ] **Agent and skill mirrors.**
      - `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md`: before
        Document Quality Gate step, require reading canonical rules file,
        filling in-plan evidence, and completing per-rule outcome record in PR
        description.
      - `.claude/agents/implementation-plan-reviewer.md` and
        `.cursor/agents/implementation-plan-reviewer.md`: require backstop
        check against canonical gate matrix and outcome record freshness.
      - `.codex/skills/workflow-plan-writer/SKILL.md`: same author obligations
        as tech-lead; delegate to Protocol 02, do not restate rules.

      Maps to Groups A, G (Rule 6 author obligation wording in canonical file
      only — agents point there).

- [ ] **`AGENTS.md` Key Documentation table** (Documentation Updates — executed
      during implementation): add row linking
      `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`.

### Infrastructure / Configuration

Not applicable.

---

## Files to modify

Live search at plan HEAD `b0491be3` (`grep -rl` for protocol references;
Verification Log re-run) plus spec mirror table:

| File | Change |
| --- | --- |
| `docs/workflow/development-workflow/plan-authoring-rigor-rules.md` | **Create** — canonical rules + gate matrix |
| `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Authoring + Document Quality Gate extension |
| `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md` | Reviewer pointer |
| `docs/workflow/development-workflow/templates/implementation-plan-template.md` | Evidence sections |
| `REVIEW.md` | Backstop checklist block |
| `.claude/agents/tech-lead.md` | Author routing |
| `.cursor/agents/tech-lead.md` | Author routing |
| `.claude/agents/implementation-plan-reviewer.md` | Reviewer routing |
| `.cursor/agents/implementation-plan-reviewer.md` | Reviewer routing |
| `.codex/skills/workflow-plan-reviewer/SKILL.md` (also `.agents/skills/workflow-plan-reviewer/SKILL.md`, a symlink) | **No edit** — it only routes to Protocol 02 review, which is edited; harness asserts Protocol 02 review directly |
| `.codex/skills/workflow-plan-writer/SKILL.md` (also served as `.agents/skills/workflow-plan-writer/SKILL.md`, a symlink to it — one edit covers both) | Author routing |
| `docs/specs/developments/20260911230253_1496-plan-authoring-rigor/1_1496-plan-authoring-rigor_specs.md` | Matrix introduction only — replace the "canonical statement" sentence with a historical pointer to the rules file (Implementation Order step 1) |
| `scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh` | **Create** — mirror consistency harness |
| `scripts/development-workflow/tests/fixtures/plan-authoring-rigor/` | **Create** — parser-risk fixture snippets (parser-risk addendum + Implementation Order step 7) |
| `docs/testing/workflow/1496-plan-authoring-rigor.smoke-test.md` | Present on this plan branch — execute scenarios during implementation QA |
| `AGENTS.md` | Key docs table row |
| `docs/workflow/development-workflow/README.md` | One-line pointer under `### Implementation Plan` (Documentation Updates + Implementation Order step 8) |

### Cross-cutting checklist — Protocol 02 targets not edited

Protocol 02 requires naming every surface in its cross-cutting checklist block.
This plan modifies plan-stage authoring and review only; the spec **Out of
Scope** entry "Extension to other artifacts" keeps specs, code reviews, and
implementation protocols out of scope unless they duplicate plan-stage
obligations.

| Required Protocol 02 target | Disposition | Rationale |
| --- | --- | --- |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | **No edit** | Rules apply at plan authoring/review; implementers execute approved plans. No new implementer checklist category is introduced. |
| `.claude/agents/developer.md` | **No edit** | Developer role does not write implementation plans. |
| `.cursor/agents/developer.md` | **No edit** | Same as Claude developer agent. |
| `.codex/skills/workflow-implementer/SKILL.md` | **No edit** | Implementation skill delegates to Protocol 03; plan evidence is already fixed when implementation starts. |

**Other explicit non-edits** (spec Out of Scope): workflow scripts
(`local-ai-reviewer.sh`, new linters), `strict-plan-checks.md` behavior, merged
plans retrofits.

---

## Testing Strategy

**Test types**: Shell mirror-consistency test (**addition** — doc drift
detection, not rule enforcement against plan claims); manual smoke test
runbook.

**Key scenarios**:

1. Mirror harness — rule names and outcome labels appear in canonical file,
   `REVIEW.md`, and Protocol 02 (`test-plan-authoring-rigor-mirror.sh`).
   Smoke Scenario 1 additionally requires that no mirror weakens a pass
   condition relative to the canonical file (pass-condition equivalence).
2. Smoke Scenarios 1–7 in
   `docs/testing/workflow/1496-plan-authoring-rigor.smoke-test.md`.
3. Negative: remove one rule from outcome record table in a test PR — reviewer
   checklist treats as blocking (Group H).

**Required smoke-matrix rows** — every row of the smoke runbook's acceptance
traceability matrix is required and must be executed and recorded before
implementation is complete (one completion requirement, matching the runbook).
The index below groups the IDs by acceptance group:

| Spec group | Required matrix IDs |
| --- | --- |
| A (wiring + no-spec inheritance) | Scenarios 1–2; confirm Protocol 02 applies to Refactor/no-spec plans |
| B | B1, B2, B3, B4, B5, B6, B7, B8, B9, B10 |
| C | C1, C2 |
| D | D1, D2 |
| E | E1, E2, E3 |
| F | F1, F2, F3, F4 |
| G | G1 |
| H | H1, H2, H3, H4, H5 |

**Regression suite**: Not applicable as a deliberate testing-scope decision —
this feature changes only workflow docs, agent files, and a shell harness. The
repository's only Playwright suite, `e2e/` (searched at revision `6c84855e`:
`find . -path ./node_modules -prune -o -name 'playwright.config.*' -print`
returns `e2e/playwright.config.ts`; `e2e/tests/` holds only
`baseline.spec.ts`, a placeholder `expect(true).toBe(true)`), exercises no
product or workflow-doc behavior, so it cannot regress from this change.

### Parser-risk addendum (mirror harness)

**Edge-case enumeration** (concrete inputs the harness must handle):

| Case | Example input | Expected harness behavior |
| --- | --- | --- |
| Boundary heading | `### Rule 1` vs `### Rule 10` vs `Rule 1 — foo` in prose | Count only spec-style rule headings in canonical file, not substring `Rule 1` inside `Rule 10` |
| Negative lookalike | `Rule 1` mentioned only inside a code block or HTML comment in `REVIEW.md` | Do not treat comment/code fences as mirror requirements |
| Multiple on one line | `Rule 1 and Rule 2` on one checklist line | Line-level grep may match both; heading-level checks remain authoritative for canonical file |
| Nested context | Rule name inside markdown link text `[Rule 3](./plan-authoring-rigor-rules.md)` | Reference check passes when path matches; do not require bare `Rule 3` substring elsewhere |
| Outcome label casing | `satisfied` vs `Satisfied` | Assert display labels from spec (`Satisfied`, `Not applicable`, `Unsatisfied`) appear in Protocol 02 / REVIEW mirror text, not code-value typos alone |

**Unit test file**: `scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`
(executable test script — one `run_test` assertion per row above using fixture
snippets under `scripts/development-workflow/tests/fixtures/plan-authoring-rigor/`
created during implementation).

**Suppression semantics**: Not applicable — no inline suppressions.

### Mirror test harness (new)

Create `scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`:

- Assert canonical file exists and contains headings `Rule 1` through `Rule 6`.
- Assert `REVIEW.md` references `plan-authoring-rigor-rules.md`, all six
  rule names, and all three outcome labels (`Satisfied`, `Not applicable`,
  `Unsatisfied`).
- Assert Protocol 02 references canonical path,
  `Plan authoring rigor — per-rule outcome record`, and all three outcome
  labels. Planted violation: delete one label from a fixture copy of each file
  and confirm the assertion fails.
- Assert tech-lead and implementation-plan-reviewer agents (Claude + Cursor)
  reference the canonical file.
- Exit non-zero on first failure; follow pattern of
  `test-protocol-02-portable-parser-guidance.sh` (verified present — see
  Verification Log).
- Missing canonical file: fail immediately with a message naming the missing
  path (same as other presence assertions).
- Add `# covers:` headers for **every path the harness asserts**, so
  change-scoped CI selects the suite whenever any of them drifts. Listing only
  a subset means a drifting mirror is caught solely by the nightly full run,
  while the Risks table claims per-change CI enforcement — the guarantee and
  the mechanism must agree. The full list:
  - `docs/workflow/development-workflow/plan-authoring-rigor-rules.md`
  - `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`
  - `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
  - `REVIEW.md`
  - `docs/workflow/development-workflow/templates/implementation-plan-template.md`
  - `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`
  - `.claude/agents/implementation-plan-reviewer.md`,
    `.cursor/agents/implementation-plan-reviewer.md`
  - `.codex/skills/workflow-plan-writer/SKILL.md`

- **Harness assertions must cover every Mirror-surfaces row.** The table above
  requires implementation to update all seven rows, so the harness asserts all
  seven. Three had no drift assertion and must gain one — this is exactly the
  drift the feature exists to prevent:
  - `.codex/skills/workflow-plan-writer/SKILL.md`
  - `docs/workflow/development-workflow/templates/implementation-plan-template.md`
  - `docs/workflow/development-workflow/protocols/02-review-implementation-plan-protocol.md`

  Any row deliberately left unasserted must carry an explicit out-of-scope
  rationale in this plan; silence is not an acceptable record.

**Planted-violation proof (implementation PR evidence)** — required before the
mirror test is considered done. Run it **once per distinct assertion** in the
harness, not once overall. Distinct assertions: canonical file present; each of
`Rule 1`–`Rule 6` headings; `REVIEW.md` canonical-path reference; `REVIEW.md`
rule names; `REVIEW.md` three outcome labels; Protocol 02 canonical-path
reference; Protocol 02 outcome-record heading; Protocol 02 three outcome labels;
each mirror surface's canonical reference (tech-lead and reviewer agents for
Claude and Cursor, the Codex plan-writer skill, the plan template, Protocol 02
review); and each parser edge case row above.

For each assertion:

1. Plant exactly one defect that assertion must catch (delete the heading, drop
   the label, break the reference) in a fixture copy under
   `scripts/development-workflow/tests/fixtures/plan-authoring-rigor/`.
2. Run `bash scripts/development-workflow/tests/test-plan-authoring-rigor-mirror.sh`
   and confirm non-zero exit with a message naming that defect.
3. Revert; re-run and confirm exit `0`.
4. Record both outcomes in the implementation PR as a table keyed by assertion
   name with the harness file and line of the assertion and the failing/passing
   exit codes.
4. Record the failing and passing exit codes in the implementation PR
   description (no need to commit the planted defect).

**CI wiring (verified)**: No separate aggregator file. `.github/workflows/workflow-tests.yml`
delegates suite selection to `scripts/development-workflow/select-test-suites.sh`,
which discovers every `scripts/development-workflow/tests/test-*.sh` via
`list_suites` (`find … -name 'test-*.sh'`). Adding
`test-plan-authoring-rigor-mirror.sh` with `# covers:` headers is sufficient —
enforced in CI when those covered paths (or the suite itself) change, and on
the nightly full run.

---

## Seed Data

Not applicable.

---

## Documentation Updates

- [ ] `AGENTS.md` — add Key Documentation row for `plan-authoring-rigor-rules.md`
      (table confirmed at line `25`).
- [ ] `docs/workflow/development-workflow/README.md` — add one-line pointer under
      `### Implementation Plan` (section confirmed at line `73`).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surfaces drift after merge | Med | High | Mirror shell test enforced in CI via `.github/workflows/workflow-tests.yml` + `select-test-suites.sh` auto-discovery of `test-*.sh` (Verification Log) |
| Authors put evidence only in PR comments | Med | Med | Protocol 02 + template + blocking REVIEW findings |
| Gate matrix copy introduces typos vs spec | Low | High | Verbatim copy from merged spec; spec reviewer diff in implementation PR |
| Plan PR description record stale vs HEAD | Med | Med | Protocol 02 requires SHA match; REVIEW blocking row Group H |
| Rule 1 external-source inspection burden | Low | Med | Document first-inspection finding field in outcome record; no re-inspect on later rounds per spec |

---

## Implementation Order

1. Create `plan-authoring-rigor-rules.md` with verbatim spec rules + gate matrix,
   and in the same change turn the retained spec's matrix-canonical sentence
   into a historical pointer to it (one canonical surface).
2. Update `implementation-plan-template.md` evidence sections.
3. Extend Protocol 02 Step 3 guardrails and Document Quality Gate example.
4. Extend `REVIEW.md` backstop checklist.
5. Update `02-review-implementation-plan-protocol.md` pointer.
6. Update tech-lead, implementation-plan-reviewer, and workflow-plan-writer
   mirrors (four agent files + one skill).
7. Add mirror fixtures under
   `scripts/development-workflow/tests/fixtures/plan-authoring-rigor/` and
   `test-plan-authoring-rigor-mirror.sh` with one assertion per parser-risk row
   and `# covers:` headers; no aggregator edit — CI auto-discovers `test-*.sh`
   via `select-test-suites.sh` (see Verification Log); run planted-violation
   proof (fail then pass).
8. Update `AGENTS.md` (and README plan-stage pointer — section exists at line
   `73`).
9. Run markdown lint on all touched paths; run mirror test at exit `0`.
10. Execute smoke runbook Scenarios 1–7 plus every matrix row (B1–B10, C1–C2,
    D1–D2, E1–E3, F1–F4, G1, H1–H5) named in Testing Strategy.

**Changelog fragment** (for later feature PR — not on this plan branch):

```markdown
### Added

- **Plan authoring rigor rules** (#1496): Six portable plan-authoring rules, reviewer backstop, and per-rule outcome record on plan pull requests.
```

---

## Acceptance criteria traceability

| Spec group / criterion | Plan coverage |
| --- | --- |
| A — Rules stated for both roles | Canonical file + mirror table + agents |
| A — Rules apply to every plan, including no-spec / Refactor | Protocol 02 authoring obligations + tech-lead / plan-writer mirrors apply to all Protocol 02 plans; no separate no-spec bypass — Refactor plans still open via Protocol 02 and must carry the per-rule outcome record |
| A — Exactly one canonical surface; no divergent pass conditions | Canonical file is sole normative text; mirrors point to it; Smoke Scenario 1 + mirror harness presence checks; Scenario 1 desk-check for pass-condition equivalence |
| B — Rule 1 | Canonical Rule 1 text + gate rows + smoke matrix rows B1–B4 (mandatory B1, B3) |
| C — Rule 2 | Canonical Rule 2 + REVIEW duplicate findings + smoke C1–C2 (both mandatory) |
| D — Rule 3 | Template + Verification Log guidance + smoke D1–D2 (mandatory D1) |
| E — Rule 4 | Template + REVIEW delegated-claim blocking + smoke E1–E2 (mandatory E1) |
| F — Rule 5 | Template consumer enumeration guidance + smoke F1–F2 (mandatory F1) |
| G — Rule 6 | Canonical Rule 6 author obligation + REVIEW backstop + smoke G1 (mandatory) |
| H — Outcomes and gate | Outcome record schema + REVIEW + copied gate matrix + smoke H1–H3 (mandatory H1, H3) |

**Addition vs spec**: Mirror harness + fixtures + planted-violation proof are
plan additions for mirror-surface consistency only (Group A agreement), not
automated detection of Rules 1–6 violations in plan prose (spec Out of Scope).

Detailed smoke traceability lives in the smoke runbook **Acceptance traceability
matrix** section (present on this plan branch).

Brief Coverage Matrix objectives: all covered; no Out of Scope deferrals beyond
spec's deliberate rejections (automation of rule scoring, size ceiling, etc.).
