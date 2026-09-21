# Axis-Separated Architecture Decision Escalations — Implementation Plan

**Spec**: [1_1515-architecture-decision-axes_specs.md](1_1515-architecture-decision-axes_specs.md)
**Smoke test runbook**: [1515-architecture-decision-axes.smoke-test.md](../../../testing/workflow/1515-architecture-decision-axes.smoke-test.md)

---

## Summary

**Approach**: Add one canonical workflow reference page that states the
operational requirement for well-formed `architecture_decision` escalations
(axis decomposition, coverage verdicts, conformance declarations, requested
decision scoped to open axes only, and incompleteness handling). Wire that page
into Protocol 91 (work-item runner stops), Protocol 93 (review-thread replies
that cite specification lines as support), Protocol 90 (batch runner stop
reporting parity), the stop-message contract in `guardrails-enforcement.md`, and
the runner-facing agent/skill mirrors — without changing when
`architecture_decision` fires or the three-element stop-message baseline.

**Estimated complexity**: M

**Rationale**: No application code or scripts change runtime behavior; the work
is a broad documentation-and-protocol alignment across the canonical page,
three orchestration protocols, stop-message contract text, README indexing,
`REVIEW.md`, and thirteen agent/skill surfaces (plus three conditional
orchestrator files). The spec's Decision-Gate
Consistency Matrix is already authoritative for behavior; this plan adds the
concrete file names, PR durability marker, report outline, and the two
spec-stage gap resolutions required before implementation.

**Dependencies**: Spec PR [#1735](https://github.com/lhpaul/ai-dev-framework-template/pull/1735)
merged to `develop`. No other work item is required first.

**Implementation Order Gate — spec prerequisite (do not skip)**: Before
implementation begins, confirm the approved spec is present on the integration
base (`docs/specs/developments/20260911230558_1515-architecture-decision-axes/1_1515-architecture-decision-axes_specs.md` on `develop`). If absent, stop with
`unclear_requirements` and wait for the spec merge — do not author canonical
guidance against a missing spec.

**Published contract change / rollback**: This feature tightens runner-facing
documentation only (no script behavior change in the MVP). Rollback is a
follow-up PR reverting the canonical page, protocol/agent edits, and audit
fixture extension; downstream consumers see the prior lighter escalation wording
again. The change is **not irreversible** but is **breaking for runner
compliance expectations** once merged — treat as a published workflow contract
update.

**Design assets**: None. Workflow-documentation feature only.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3260570` (worktree branch matches `origin/develop`) |
| Spec merged | `gh pr view 1735 --json state,mergedAt,baseRefName` | Merged to `develop` (handoff: spec PR #1735 merged) |
| No existing canonical escalation page | `ls docs/workflow/development-workflow/architecture-decision-escalation.md 2>/dev/null \|\| echo absent` | Absent — net-new canonical surface |
| Current `architecture_decision` mentions | `grep -rl architecture_decision docs/workflow .ai-dev-workflow.yaml` | `guardrails.md`, `guardrails-enforcement.md`, `README.md`, `.ai-dev-workflow.yaml`, plus this spec only |
| Lockstep mirror files (explicit list) | `for f in .cursor/agents/item-orchestrator.md .claude/agents/item-orchestrator.md .codex/skills/workflow-item-orchestrator/SKILL.md .agents/skills/run-item/SKILL.md .cursor/agents/automated-reviewer-loop.md .claude/agents/automated-reviewer-loop.md .codex/skills/workflow-reviewer-loop/SKILL.md .cursor/agents/developer.md .claude/agents/developer.md .codex/skills/workflow-implementer/SKILL.md .cursor/agents/code-reviewer.md .claude/agents/code-reviewer.md .codex/skills/workflow-code-reviewer/SKILL.md; do test -f "$f" && echo OK:$f \|\| echo MISSING:$f; done` | All thirteen `OK:` — verified 2026-09-20, every path exists (orchestrator batch agents verified separately in Layer H) |
| PR marker upsert precedent | `grep -n find_marker_comment_id scripts/development-workflow/run-epic-audit-trail.sh \| head` | Existing find-by-marker-then-PATCH-or-POST helper used for durable PR comments |
| Stop-surface audit helper | `grep -n audit_stop_surfaces scripts/development-workflow/tests/test-worktree-recipe.sh` | Existing audit covers `guardrails-enforcement.md` stop contract — extend to reference the new canonical page |

---

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved implementation base | `develop` | Batch handoff + `validate-branch-reuse.sh` | `3260570` | Batch items `1757,1462,1496,1515,1561,1583,1529`; same-surface open PRs: none | `Verified` |
| Spec artifact location | `docs/specs/developments/20260911230558_1515-architecture-decision-axes/` | Issue #1515 handoff | Plan-write | No concurrent PR editing this development folder | `Verified` |

No batch peer changes the escalation vocabulary, stop-condition trigger, or
canonical stop-message three-element contract for this item.

---

## Spec-Stage Gap Resolutions (mandatory before implementation)

The approved spec records two known gaps under **Known gaps deferred to plan
stage**. This plan resolves both here; implementation must follow these
decisions (implementation must **not** silently re-open spec edits unless a
reviewer directs a spec follow-up PR).

### Gap 1 — Operational Visibility "Stop message" raised-question gate

**Decision**: Extend `guardrails-enforcement.md` §5 (Stop-Message Contract) with
an `architecture_decision`-specific subsection that points to the canonical page
and states explicitly:

- For a **complete** escalation report, the required human action names
  genuinely open axes only (never settled axes).
- For an **incomplete** report under the malformed-input rule, the required
  human action supplies what that rule names (missing question/source, redone
  decomposition, conformance evidence, or substance confirmation).
- Substance-confirmation requests apply **only where a reviewer or human
  actually raised** the citation's substance and the runner could not resolve
  it — matching Business Rule 188 and malformed-input row four in the spec.

The canonical page repeats the raised-question gate in its report-outline
section so readers need not infer it from the spec alone.

### Gap 2 — Declaration requirement inside incomplete (mixed) reports

**Decision**: The canonical page carries an explicit **Per-citation declaration
rule (mixed reports)** bullet: every determinable citation offered as support
must carry `Conforms`, `Departs`, or `Not yet implemented` even when the
overall report is incomplete because a different citation triggered
conformance-undetermined or substance-undetermined malformed input. Undetermined
citations carry none of the three declarations, per spec. Implementation does
**not** change the spec acceptance-criterion wording in this plan PR; the
canonical page plus `REVIEW.md` checklist make the composition rule auditable
for reviewers.

---

## Workflow Decision-Gate Matrix (Implementation-Detail Delta)

The spec's **Decision-Gate Consistency Matrix** is authoritative for gate
inputs, outcomes, malformed-input rows, composition, and examples. This table
records only concrete names and surfaces deferred to the plan:

| Deferred item | Concrete choice |
| --- | --- |
| Canonical runner reference | `docs/workflow/development-workflow/architecture-decision-escalation.md` |
| PR durable-record HTML marker | `<!-- architecture-decision-escalation -->` |
| PR comment section heading | `## Architecture decision escalation` |
| Run-summary attachment | Full report body duplicated in the Work Item Runner Summary **Stops** section when stopping under `architecture_decision` |
| Review-thread surface | Protocol 93 disposition/reply steps — conformance declaration inline when citing a workflow specification line **as support** |
| Vocabulary source of truth | Display labels from spec **Statuses / Enum Values** (no new machine codes) |

### Matrix coverage (changed gate behavior)

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Runner about to stop under `architecture_decision` | Escalated with axis-separated report **or** stop recategorized when analysis shows trigger not met | Complete coverage analysis per canonical page; attach report; stop **or** apply settled lines and continue | Protocol 91, item-orchestrator agents/skills, canonical page | Spec worked example: settled reset boundary + open cumulative-effort axis |
| Determinable citation offered as support (report or review thread) | Declaration attached | State `Conforms` / `Departs` / `Not yet implemented` before treating citation as support | Protocol 93, developer **and code-reviewer** agents/skills, canonical page | Departs citation not offered as support |
| Citation conformance cannot be determined | Incomplete escalation | Plain statement; no declaration enum value | Canonical page + malformed-input rows | — |
| Reviewer/human raised substance; runner cannot resolve | Incomplete escalation | Substance confirmation request; coverage verdict unchanged | guardrails-enforcement §5 + canonical page | Spec gap 1 resolution |
| Every axis settled, every citation `Conforms` **or** `Not yet implemented`, no disputes, **and no reviewer- or human-raised question about a citation's substance left unresolved** | Not an architecture decision | Continue without `architecture_decision` stop; if such a substance question is unresolved, use the substance-undetermined row above instead | Protocol 91 stop-and-name section | Spec matrix "No escalation" rows |
| Every axis settled but some citation declares `Departs` | Not eligible for the no-escalation path | Correct the behavior to conform where that is the obvious correction (the axis is then settled by the correction), otherwise raise the departure as its own genuinely open axis and stop | Protocol 91 stop-and-name section, canonical page | Spec: a `Departs` citation "is never presented as support for the current behavior" |

---

## Layer-by-Layer Changes

> Documentation-and-protocol feature only. Database, API, UI, and infrastructure
> layers are not applicable.

### A. New canonical reference — `docs/workflow/development-workflow/architecture-decision-escalation.md`

- [ ] **Purpose**: Canonical runner-facing requirement for
      `architecture_decision` escalation **content** (spec Mirror surfaces
      table). Do not duplicate the full spec prose; include:
  - Scope boundary (escalation reports + review-thread replies that cite spec
    lines as support; planning artifacts and source comments out of scope per
    spec MVP).
  - Vocabulary tables (coverage verdict, open-axis reason, conformance
    declaration) matching spec display labels verbatim.
  - Mandatory report outline: question + source; axes; per-axis verdict +
    citation/reason; per-citation conformance; arguments tied to one axis;
    requested decision (open axes only); optional **Recommendation** element
    labelled separately from the requested decision (spec AC under *The
    requested decision covers only the open axes*); incompleteness markers when
    malformed-input rows apply.
  - **Per-citation declaration rule (mixed reports)** (gap 2 resolution).
  - **Raised-question gate** for substance-undetermined incomplete reports
    (gap 1 resolution).
  - Worked example copied from spec **Examples** table (review-cycle /
    cumulative-effort incident) showing one settled axis, one open axis, a
    `Departs` citation, and a mis-attached argument — satisfies AC "worked
    example alongside requirement".
  - Pointer: spec Decision-Gate Matrix for full outcome/precedence/composition
    logic.
- [ ] Maps to acceptance groups: *The escalation names the question and its
      axes*, *Every axis carries a verdict*, *Citations carry a conformance
      declaration*, *The requested decision covers only the open axes*, *The
      requirement never suppresses a stop*, *The guidance carries a worked
      example*, *Surfaces agree*.

### B. Stop-message contract — `docs/workflow/development-workflow/guardrails-enforcement.md`

- [ ] Add §5 subsection **`architecture_decision` escalation content**:
  requires the canonical page report when stopping under this condition;
  restates three baseline stop elements unchanged; documents human-action
  shaping (open axes vs malformed-input requests) including the raised-question
  gate (gap 1).
- [ ] Maps to *Operational Visibility* / stop-message ACs and gap 1.

### C. Protocol 91 — `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`

- [ ] In **Step 11: Guardrails Audit Recording** / named stop-and-name behavior:
  when the stop condition is `architecture_decision`, require the coverage
  analysis and well-formed report per canonical page **before** emitting the
  terminal Work Item Runner Summary.
- [ ] Add PR durability step when a PR exists for the work item: **upsert** (not
      append-only) a PR issue comment whose body starts with
      `<!-- architecture-decision-escalation -->` and
      `## Architecture decision escalation`, containing the same report attached
      to the run summary. Protocol text must name the algorithm: paginate issue
      comments, locate an existing body containing the marker (reuse
      `find_marker_comment_id` from `run-epic-audit-trail.sh`), `gh api` PATCH
      that comment when found, otherwise POST a new comment — same idempotency
      contract as checkpoint-status and security-advisory marker comments. Smoke
      test step 3 verifies the algorithm is documented; no new script is
      required for MVP unless implementation extracts a shared helper.
- [ ] **Scope reconciliation (spec Out of Scope item 7)**: this is not a routing
      change. The approved spec requires, as an acceptance criterion, that the
      report be "readable on that pull request after the run ends" where a PR
      exists (Escalation report definition and the durability acceptance
      criterion), while stating it adds no new destination for runs with no PR
      and changes no notification or answer-recording path. Protocol 91 has no
      architecture-stop PR comment today, so the plan satisfies that criterion
      by reusing the *existing* PR-comment mechanism (`gh pr comment` /
      marker upsert, as Step 7a summaries and checkpoint markers already do)
      with the same report content already attached to the run summary. The
      implementation states this reuse in the Protocol 91 text; if review
      concludes the criterion cannot be met without a new route, that is a spec
      question for the human, not something the implementation decides.
- [ ] Document the "analysis shows no genuinely open axis" continuation path:
  does **not** stop under `architecture_decision` when the spec matrix says the
  trigger was not met — without weakening baseline stops.
- [ ] Link to canonical page; do not restate the full vocabulary inline.
- [ ] Maps to escalation content ACs and PR durability AC.

### D. Protocol 93 — `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`

- [ ] In the review-disposition / runner-reply guidance: when a runner cites a
      workflow specification line **as support** for its behavior or decision
      in a review-thread reply, require the conformance declaration per canonical
      page (including undetermined-conformance plain statement path).
- [ ] When a reviewer finding would lead to `architecture_decision`, point to
      Protocol 91 + canonical page for the full escalation report (no lighter
      requirement).
- [ ] Maps to review-thread citation ACs and *Surfaces agree*.

### E. Protocol 90 — `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

- [ ] In batch stop reporting: when a child item stops with
      `architecture_decision`, require the batch summary to reference that the
      child carried the canonical escalation report (not the whole question as
      undifferentiated open).
- [ ] Link to canonical page.
- [ ] Maps to *Surfaces agree*.

### F. README index — `docs/workflow/development-workflow/README.md`

- [ ] Add `architecture-decision-escalation.md` under **Tooling And Configuration**
      next to `guardrails-enforcement.md`. *Addition beyond the spec's use
      cases:* the index entry is needed so the new canonical page is
      discoverable from the workflow README, which the *Surfaces agree*
      criterion relies on to keep every surface pointing at one page.

### G. Review contract — `REVIEW.md`

- [ ] Add a concise checklist bullet under workflow-documentation review: when
      a PR touches escalation/stop guidance, verify axis separation,
      per-citation declarations (including mixed incomplete reports), open-axis
      scoped requested decision, and that `Departs` citations are not used as
      support.

### H. Runner-facing mirrors (lockstep — do not weaken)

Each file gets a short, direct requirement plus a link to the canonical page
(no pointer-only edits):

- [ ] `.cursor/agents/item-orchestrator.md`
- [ ] `.claude/agents/item-orchestrator.md`
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md`
- [ ] `.agents/skills/run-item/SKILL.md`
- [ ] `.cursor/agents/automated-reviewer-loop.md`
- [ ] `.claude/agents/automated-reviewer-loop.md`
- [ ] `.codex/skills/workflow-reviewer-loop/SKILL.md`
- [ ] `.cursor/agents/developer.md`
- [ ] `.claude/agents/developer.md`
- [ ] `.codex/skills/workflow-implementer/SKILL.md` (completes the developer
      triple — its cursor and claude counterparts are listed above)
- [ ] `.cursor/agents/code-reviewer.md`
- [ ] `.claude/agents/code-reviewer.md`
- [ ] `.codex/skills/workflow-code-reviewer/SKILL.md`

The `code-reviewer` mirrors are **required, not optional**: Protocol 91
dispatches `code-reviewer` during implementation review-fix cycles and makes
replying to each addressed inline comment mandatory
(`91-orchestrate-work-protocol.md`, "Resolve inline review comments"). A
review-thread reply is one of the two surfaces this feature covers — the spec's
Business Rules say a declaration is required on "every citation the runner
offers in an escalation report **or in a reply on a review thread**". Updating
only the `developer` mirrors would leave the agents that actually post those
replies free to cite a specification line as support without declaring
`Conforms` / `Departs` / `Not yet implemented`.

Orchestrator batch agents (`.cursor/agents/orchestrator.md`,
`.claude/agents/orchestrator.md`, `.codex/skills/workflow-orchestrator/SKILL.md`)
receive the Protocol 90 parity sentence only if not already covered by protocol
pointer — verify during implementation; add if missing.

### I. Tests (documentation parity)

- [ ] `scripts/development-workflow/tests/test-worktree-recipe.sh` — add a
      **new** helper `audit_escalation_mirrors <repo-root>` beside
      `audit_stop_surfaces` (`test-worktree-recipe.sh:366-415`). The existing
      helper only discovers `stop_conditions:` surfaces and greps for
      `push_verification_failed`, so it can neither validate the canonical
      escalation page nor detect a weakened mirror; it is left unchanged.
      - **Discovery scope**: the explicit thirteen-file mirror list from the
        Lockstep mirror files row of the plan's Verification table (the same
        list as section H), plus Protocol 90, Protocol 91, Protocol 93, and the
        canonical page. Discovery is by that list, not by grep, so a deleted mirror is
        reported rather than silently skipped.
      - **Invariants** (per file): a mirror and each protocol contain the
        literal `architecture-decision-escalation.md` link **and** the three
        declaration terms `Conforms`, `Departs`, `Not yet implemented` (agents
        that only escalate carry the link plus the "no lighter escalation
        wording" sentence instead — the helper takes the per-file required
        terms as data). The canonical page contains the terms `Recommendation`,
        `Conforms`, `Departs`, `Not yet implemented`.
      - **Output contract**: prints `COUNT=<n>` and one
        `MISSING=<file>:<term>` per violation, like `audit_stop_surfaces`.
      - **Non-vacuous guard**: assert `COUNT` equals 17 (thirteen mirrors +
        three protocols + canonical page) so an empty discovery cannot pass.
      - **Planted-violation evidence**: copy the mirror tree to a temp root,
        delete the canonical link from `.claude/agents/code-reviewer.md`, and
        assert the audit prints exactly
        `MISSING=.claude/agents/code-reviewer.md:architecture-decision-escalation.md`
        (failure at a concrete mirror location); restore the file and assert
        the audit prints no `MISSING=` line (passing run after restoration).
        Repeat once for a weakened declaration term in a
        `.codex/skills/workflow-code-reviewer/SKILL.md` copy.
- [ ] Maps to *Surfaces agree* and REVIEW.md Verification Discipline.

### Database / Backend / Frontend / Infrastructure

- [ ] Not applicable.

---

## Testing Strategy

**Test types**: Shell unit test (stop-surface audit extension), manual smoke
test runbook.

**Key scenarios** (each names a falsifiable smoke or audit check):

1. Canonical page exists with vocabulary, outline, worked example, gap
   resolutions — smoke step 1.
2. **Recommendation separation**: canonical outline requires a labelled
   Recommendation distinct from requested decision — smoke step 1 checklist item.
3. **Declaration misuse**: `Not yet implemented` is never used for built
   behavior — smoke step 4 checklist item.
4. **No pre-answer / ratification**: canonical page + Protocol 91 state the
   report must not act on or pre-answer open axes — smoke step 1.
5. Protocol 91 requires report + **documented marker upsert algorithm** when a
   PR exists — smoke step 3.
6. Protocol 93 requires inline declaration on supportive spec citations in
   review replies — smoke step 4.
7. Agent/skill mirrors link to canonical page and forbid lighter escalation
   wording — smoke step 5 + `test-worktree-recipe.sh` negative fixture.
8. Stop-message human action names open axes only on complete reports — smoke
   step 2.

**Smoke test runbook**:
`docs/testing/workflow/1515-architecture-decision-axes.smoke-test.md`

**Regression suite**: Not applicable — no automated regression suite for
workflow-doc parity beyond the shell audit extension above.

---

## Seed Data

Not applicable — no database or runtime fixtures.

---

## Documentation Updates

Implementation PR (not this plan PR) must add a changelog fragment only.
*Addition beyond the spec's use cases:* required by the repository's
CHANGELOG convention (`changelog.d/README.md`) for every feature PR, not by the
spec itself:

- [ ] `changelog.d/1515.added.architecture-decision-axes.md` with body:
  `- **Axis-separated architecture decision escalations** (#1515): require
    per-axis coverage analysis and conformance declarations before
    architecture_decision stops; canonical guidance in
    docs/workflow/development-workflow/architecture-decision-escalation.md.`

Other project docs are updated **in this feature branch** as listed in Layer-by-Layer
Changes; no additional `docs/project/` files expected.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surface omitted from lockstep list | Med | Med | Verification Log grep + smoke test step enumerating all thirteen mandatory paths (plus the three conditional orchestrator files) |
| Protocol 91 PR comment step conflicts with existing comment templates | Low | Med | Reuse upsert marker pattern from other workflow comments; idempotent section heading |
| Runners treat "all settled" continuation as suppressing stops | Med | High | Canonical page + Protocol 91 repeat spec's "trigger not met" wording prominently |
| Over-long duplication of spec matrix in protocols | Med | Low | Canonical page + pointer; protocols state requirement and durability only |

---

## Code Samples

Illustrative PR comment skeleton only (adapt during implementation):

```markdown
<!-- architecture-decision-escalation -->
## Architecture decision escalation

**Question (source):** Reviewer asked to reset the review-cycle counter at orchestration start (PR review thread).

### Axes
1. Reset boundary for the counter — **Settled by specification** — citation: Protocol 91 `PR_REVIEW_LOOP_RUN_ID` paragraph — **Departs** — behavior today: counter is not reset at that boundary; **next action:** conform to the cited line (correction), not an architecture decision.
2. Whether run-scoped counting alone bounds total effort across resumed runs — **Genuinely open** — No governing line — surfaces consulted: Protocol 91, guardrails-enforcement.md, REVIEW.md.

**Requested decision:** Axis 2 only.

**Recommendation (optional, separate):** Prefer documenting cumulative-effort policy in guardrails-enforcement if axis 2 is answered yes.
```

---

## Implementation Order

1. Create `architecture-decision-escalation.md` (canonical vocabulary, outline,
   gap resolutions, worked example).
2. Update `guardrails-enforcement.md` §5 `architecture_decision` subsection.
3. Update Protocol 91 (stop-and-name + PR durability + continuation path).
4. Update Protocol 93 (review-thread declarations + escalation pointer).
5. Update Protocol 90 (batch stop reporting parity).
6. Update `README.md` index entry.
7. Update `REVIEW.md` checklist bullet.
8. Update all lockstep agent/skill files (incremental commits per 2–3 files).
9. Extend `test-worktree-recipe.sh` audit fixtures; run the test file locally.
10. Execute smoke test runbook on the implementation PR branch.
11. Add `changelog.d` fragment on the **implementation** PR only.

**Verification commands (implementation stage)**:

```bash
# Confirm canonical page is linked from protocols (expect multiple hits)
grep -n architecture-decision-escalation docs/workflow/development-workflow/protocols/9*.md

# Confirm marker string appears in Protocol 91
grep -n 'architecture-decision-escalation' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md

# Run stop-surface audit tests
bash scripts/development-workflow/tests/test-worktree-recipe.sh
```

---

## Files to modify (implementation PR)

| File | Action |
| --- | --- |
| `docs/workflow/development-workflow/architecture-decision-escalation.md` | Create |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Edit §5 |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Edit |
| `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Edit |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Edit |
| `docs/workflow/development-workflow/README.md` | Edit index |
| `REVIEW.md` | Edit |
| `.cursor/agents/item-orchestrator.md` | Edit |
| `.claude/agents/item-orchestrator.md` | Edit |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Edit |
| `.agents/skills/run-item/SKILL.md` | Edit |
| `.cursor/agents/automated-reviewer-loop.md` | Edit |
| `.claude/agents/automated-reviewer-loop.md` | Edit |
| `.codex/skills/workflow-reviewer-loop/SKILL.md` | Edit |
| `.cursor/agents/developer.md` | Edit |
| `.claude/agents/developer.md` | Edit |
| `.codex/skills/workflow-implementer/SKILL.md` | Edit |
| `.cursor/agents/code-reviewer.md` | Edit |
| `.claude/agents/code-reviewer.md` | Edit |
| `.codex/skills/workflow-code-reviewer/SKILL.md` | Edit |
| `.cursor/agents/orchestrator.md` | Edit if missing Protocol 90 parity sentence (Layer H) |
| `.claude/agents/orchestrator.md` | Edit if missing Protocol 90 parity sentence (Layer H) |
| `.codex/skills/workflow-orchestrator/SKILL.md` | Edit if missing Protocol 90 parity sentence (Layer H) |
| `scripts/development-workflow/tests/test-worktree-recipe.sh` | Edit |
| `changelog.d/1515.added.architecture-decision-axes.md` | Create (implementation PR) |
