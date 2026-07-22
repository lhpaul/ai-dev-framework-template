# Automate Graduation Closeout on Merge — Implementation Plan

**Spec**: [1_1281-automate-graduation-closeout-on-merge_specs.md](1_1281-automate-graduation-closeout-on-merge_specs.md)
**Smoke test runbook**: [1281-automate-graduation-closeout-on-merge.smoke-test.md](../../../testing/workflow/1281-automate-graduation-closeout-on-merge.smoke-test.md)

---

## Summary

**Approach**: Keep `/graduate-development` Step 5 and
`scripts/development-workflow/graduation-closeout.sh` as the primary closeout
path. Add a thin merge-time discovery wrapper that, when a graduation PR
(`develop-<slug>` → `develop`) merges, resolves slug/epic/operator disposition
signals and invokes that same reconciler. Wire the wrapper into the existing
merge-time tracker workflow so graduation heads are no longer silently skipped
without fallback, while leaving non-graduation branch mappings unchanged.

**Estimated complexity**: M

**Rationale**: The reconciler already exists (#1178). This work is mainly
discovery + GitHub Actions wiring + durable operator disposition signals for
automation, plus tests and protocol/docs mirrors. No product application layers
change.

**Dependencies**: None. Relies on merged #1178 closeout helper already on
`develop`. Orthogonal to #1282 and #1284 (do not couple).

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `160bb5e` |
| Template-fit check | `rg -n "is_template: true" .ai-dev-workflow.yaml` | `.ai-dev-workflow.yaml:152` — template repo; this item is workflow tooling (generic enough). |
| Acceptance criteria inventory | `rg -n "^## Acceptance Criteria\|^- \\[ \\] AC" docs/specs/developments/20260721132930_1281-automate-graduation-closeout-on-merge/1_1281-automate-graduation-closeout-on-merge_specs.md` | AC1–AC9 present. |
| Merge-time skip gap | `rg -n "does not match a tracked prefix\|develop-" .github/workflows/update-tracker-on-merge.yml` | Line 70 skips non-`spec/*` / `implementation-plan/*` / impl prefixes — graduation heads (`develop-*`) fall into this silent skip today. |
| Existing closeout helper | `test -f scripts/development-workflow/graduation-closeout.sh && rg -n "DEFER_EPIC_CLOSE\|is_skip_label\|TERMINAL_STATUS" scripts/development-workflow/graduation-closeout.sh` | Helper exists; supports `--defer-epic-close`, skip labels, and `GITHUB_PROJECT_STATUS_GRADUATED` → `GITHUB_PROJECT_STATUS_MERGED` → `Merged`. |
| Existing unit tests | `test -f scripts/development-workflow/tests/test-graduation-closeout.sh` | Present (`test-graduation-closeout.sh`). Extend rather than replace. |
| Protocol Step 5 primary path | `rg -n "Run graduation closeout\|graduation-closeout.sh" docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` | Step 5 already documents the primary agent closeout command. |
| Graduate-development mirrors | `rg --files .agents .claude .cursor \| rg 'graduate-development' \| sort` | Four mirrors: `.agents/skills/graduate-development/SKILL.md`, `.agents/skills/graduate-development/agents/openai.yaml`, `.claude/commands/graduate-development.md`, `.cursor/commands/graduate-development.md`. |
| post-merge-cleanup gap | `rg -n "graduation\|develop-" scripts/development-workflow/post-merge-cleanup.sh \|\| true` | No graduation/epic handling (out of scope beyond documenting that merge-time fallback owns automation). |
| Cross-cutting checklist search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \|\| true` | References exist; this plan does not add/rename a cross-cutting checklist category — block N/A. |

---

## Layer-by-Layer Changes

### Workflow Script / Tracker Automation

- [ ] Add
      `scripts/development-workflow/graduation-closeout-from-merged-pr.sh` as the
      merge-time entrypoint (thin wrapper; do not fork closeout policy into a
      second reconciler).
- [ ] Wrapper inputs (illustrative — adapt during implementation):
      `--graduation-pr <number>` (required). Optional overrides:
      `--epic <number>`, `--slug <slug>`, repeated `--exclude-issue <number>`,
      `--defer-epic-close`.
- [ ] Discovery rules when overrides are omitted:
      1. Read the merged PR; require `merged == true`, `base == develop`, and
         `head == develop-<slug>` with a valid slug.
      2. Resolve epic in this order, fail closed if zero or ambiguous after
         exhausting sources:
         - Explicit `--epic` override
         - Closing-keyword / explicit epic reference in the graduation PR
           title/body (reuse the same closing-keyword extractor semantics as
           `graduation-closeout.sh` / `post-merge-cleanup.sh`; also accept a
           documented `Epic #<n>` / `Parent #<n>` line if present)
         - GraphQL parent of issues labeled `integration-branch:<slug>` when
           all discovered parents converge on one epic number
      3. Resolve durable automation disposition signals (so automation can honor
         operator controls without inventing a new policy):
         - Epic label `defer-epic-close` → pass `--defer-epic-close`
         - Sub-item skip labels already honored by
           `graduation-closeout.sh` (`optional`, `deferred`, `cancelled`,
           `excluded-from-graduation`, `exclude-from-graduation`)
         - Explicit `--exclude-issue` / `--defer-epic-close` CLI overrides when
           the wrapper is invoked manually
- [ ] **AC4 double-run durability**: When Step 5 / `graduation-closeout.sh` is
      invoked with `--defer-epic-close`, the primary path must also ensure the
      durable epic label `defer-epic-close` is present before returning success
      (add the label if missing). Without this, a later merge-time automation
      run would not see the operator deferral and could force-close the epic —
      a conflicting policy. Document the label in Protocol 05b as the shared
      deferral signal across agent and automation paths.
- [ ] Invoke
      `./scripts/development-workflow/graduation-closeout.sh --slug … --graduation-pr … --epic …`
      with discovered/override flags. Do not reimplement close/status logic in
      the wrapper (except the small label-ensure behavior above for deferral
      durability, which may live in the reconciler or a tiny shared helper).
- [ ] Emit a stable summary including discovery sources, whether deferral was
      inferred from a label, and the child closeout result lines
      (`GRADUATION_CLOSEOUT_RESULT=…`). Non-zero exit when discovery fails closed
      or the child reconciler fails.
- [ ] Idempotency guarantee: the wrapper always delegates to the existing
      reconciler, which already reports `already_terminal` and does not reopen
      or move terminal items backward (AC3).
- [ ] Extend
      `.github/workflows/update-tracker-on-merge.yml` with a graduation path:
      - When `head.ref` matches `develop-*` and the PR merged into `develop`,
        set `branch_type=graduation` (or equivalent) and run the wrapper instead
        of the current silent skip.
      - Keep existing `spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready,
        and impl → Merged (+ close) behavior byte-for-byte in product mapping
        (AC8).
      - Checkout the repo so the wrapper/script can run; reuse
        `GH_PROJECT_TOKEN` / project vars already required by the workflow for
        tracker mutations inside `graduation-closeout.sh`.
      - Log skip vs run vs fail clearly in the job summary (Operational
        Visibility).
- [ ] Update
      `scripts/development-workflow/check-tracker-merge-mapping.sh` (and its
      test) so the documented mapping acknowledges graduation heads invoke
      closeout fallback rather than "untracked skip", without changing
      non-graduation mappings.
- [ ] Do **not** turn `post-merge-cleanup.sh` into a full graduation/epic
      handler in this MVP (spec out of scope). Optionally add a one-line note
      pointing operators at Step 5 / merge-time fallback if an existing comment
      would otherwise imply no closeout exists.

### Protocol and Command Guidance

- [ ] Update
      `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      Step 5 to state:
      - Step 5 remains the **primary** closeout path (BR-1 / AC1).
      - Merge-time automation is a **fallback** that calls the same reconciler
        when a graduation PR merges (BR-2 / AC2).
      - Operator controls: CLI flags on Step 5; durable epic label
        `defer-epic-close` and existing sub-item skip labels for automation
        (AC4 / AC5).
      - Double-runs are safe/idempotent (AC3).
- [ ] Update graduate-development command/skill mirrors so wrappers mention the
      merge-time fallback without changing the primary Step 5 command:
      - `.agents/skills/graduate-development/SKILL.md`
      - `.claude/commands/graduate-development.md`
      - `.cursor/commands/graduate-development.md`
      - Review `.agents/skills/graduate-development/agents/openai.yaml`; update
        only if operator-facing text would contradict the fallback contract.

### Documentation

- [ ] Update
      `docs/workflow/development-workflow/integrations/github-projects.md` to
      document merge-time graduation closeout fallback, the
      `defer-epic-close` epic label, and unchanged non-graduation merge mappings.
- [ ] Update `docs/workflow/development-workflow/README.md` only if its
      graduation/merge summary would otherwise omit the automation fallback.
- [ ] Do not update `AGENTS.md` unless command names or repository-wide rules
      change.
- [ ] Do not update `CHANGELOG.md` on the plan branch (implementation-plan
      branches are exempt); the implementation PR will add the Unreleased entry.

### Test / Validation Assets

- [ ] Add
      `scripts/development-workflow/tests/test-graduation-closeout-from-merged-pr.sh`
      with mocked `gh`/GraphQL fixtures covering:
      - graduation head detection + slug extraction
      - epic discovery via PR reference and via converging label parents
      - fail-closed on missing/ambiguous epic
      - `defer-epic-close` label → child invoked with `--defer-epic-close`
      - non-graduation PR → wrapper/workflow skip (no closeout)
      - successful delegation to `graduation-closeout.sh` (assert argv, do not
        re-test the full reconciler matrix)
- [ ] Extend
      `scripts/development-workflow/tests/test-check-tracker-merge-mapping.sh`
      for the updated graduation mapping note.
- [ ] Add smoke runbook
      `docs/testing/workflow/1281-automate-graduation-closeout-on-merge.smoke-test.md`
      (created in this Plan Ready stage).

---

## Workflow Decision-Gate Matrix (plan coverage)

Complex workflow decision-gate: **applies** (merge-time graduation vs
non-graduation; discovery outcomes; deferral/exclusion; idempotent double-run).
Spec matrix is authoritative; implementation must preserve these outcomes:

| Trigger | Disposition signals | Discovery | Required outcome | Next action | Mirror surfaces |
| ------- | ------------------- | --------- | ---------------- | ----------- | --------------- |
| Operator Step 5 | CLI `--defer-epic-close` / `--exclude-issue` | Reconciler discovery | Primary closeout | Report cleanup | Protocol 05b Step 5, closeout helper |
| Graduation PR merges; automation | Epic label `defer-epic-close`; sub-item skip labels | Wrapper discovers slug+epic | Same reconciler policy | Job log success/fail | `update-tracker-on-merge.yml`, wrapper |
| Graduation merge; incomplete/ambiguous epic or no delivered items | N/A | Fail closed | Do not invent terminal status | Operator repairs; re-run Step 5 or re-trigger job | Job log + wrapper summary |
| Step 5 + automation both run | Same rules | Already reconciled | Idempotent / already_terminal | No regressive moves | Both paths |
| Non-graduation PR merges | N/A | N/A for this feature | Existing tracker mapping unchanged | Continue current path | `update-tracker-on-merge.yml` |

---

## Testing Strategy

**Test types**: Unit/integration script tests with mocked CLI fixtures;
documentation smoke; optional live-repo smoke on a disposable graduation PR.

**Key scenarios to test**:

1. Operator Step 5 path still documented and unchanged as primary. Maps to AC1.
2. Merged `develop-<slug>` → `develop` PR triggers wrapper → same reconciler.
   Maps to AC2.
3. Agent then automation (or reverse) leaves terminal items stable. Maps to AC3.
4. Epic with `defer-epic-close` (or CLI defer) remains open; automation does not
   force-close. Maps to AC4.
5. Excluded/optional/deferred labeled sub-items stay open and are reported.
   Maps to AC5.
6. Terminal status resolution order unchanged in reconciler. Maps to AC6.
7. Incomplete/ambiguous discovery fails closed. Maps to AC7.
8. `spec/*`, `implementation-plan/*`, and impl merges keep current status
   behavior. Maps to AC8.
9. No dependency wiring to #1282/#1284. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/1281-automate-graduation-closeout-on-merge.smoke-test.md`

**Regression suite**: Script tests under
`scripts/development-workflow/tests/`; no application regression suite applies.

### Parser-risk addendum

This plan is parser-risk because the wrapper extracts slug from `develop-<slug>`
and may parse graduation PR title/body for epic references / closing keywords.

**Edge-case enumeration** (concrete inputs):

| Case | Input example | Expected |
| ---- | ------------- | -------- |
| Valid slug boundary | head `develop-my.feature_1` | slug `my.feature_1` |
| Invalid slug chars | head `develop-my feature` | fail closed (not a graduation head / invalid slug) |
| Negative lookalike branch | head `feature/develop-123-x` | non-graduation path; no closeout wrapper |
| Multiple closing refs | body `Closes #10` and `Closes #11` both parents? | use documented epic resolution order; if multiple distinct epic candidates remain after parent convergence, fail closed |
| Nested/overlapping refs | `Closes issue #12` vs `see #12` | only closing-keyword forms (and documented `Epic #n` / `Parent #n`) count |
| Fence/flexibility N/A | markdown fences in PR body | ignore fenced examples that are not live closing keywords if extractor already scopes to keyword lines — document behavior in tests |

**Unit test mapping**:
`scripts/development-workflow/tests/test-graduation-closeout-from-merged-pr.sh`
must include at least one automated case per row above.

**Suppression semantics**: Not applicable — no inline suppression directives.

### Concurrent-event-source addendum

Not applicable. Double-run safety is sequential idempotency in the existing
reconciler, not concurrent event listeners sharing mutable process state.

---

## Seed Data

| Entity | Values / Scenario | File |
| ------ | ----------------- | ---- |
| Mocked graduation PR JSON | Merged PR head `develop-test-1281`, base `develop`, body with `Epic #<n>` | Fixture inside `test-graduation-closeout-from-merged-pr.sh` |
| Mocked epic + sub-issues | Epic with/without `defer-epic-close`; delivered vs optional child | Same test fixtures |
| Live disposable epic (optional smoke) | Temporary epic + integration branch slug `test-1281-closeout-automation` | Operator-created at smoke time |

---

## Documentation Updates

> Performed during implementation, not on this plan branch.

- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` — primary vs fallback closeout; durable defer label
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — merge-time graduation fallback + label
- [ ] `docs/workflow/development-workflow/README.md` — only if graduation summary would otherwise omit fallback
- [ ] `.agents/skills/graduate-development/SKILL.md` — mention merge-time fallback
- [ ] `.claude/commands/graduate-development.md` — same
- [ ] `.cursor/commands/graduate-development.md` — same
- [ ] `.agents/skills/graduate-development/agents/openai.yaml` — only if contradictory
- [ ] `AGENTS.md` — None unless command/branch rules change

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Epic discovery ambiguous for legacy integrations | Med | High (fail closed leaves board stale) | Ordered discovery + clear job failure logs; Step 5 remains primary repair path |
| Automation closes epic despite operator intent to defer | Low | High | CLI `--defer-epic-close` must apply durable epic label; wrapper reads that label; document in 05b |
| Workflow secrets missing → silent skip | Med | Med | Fail the graduation job visibly when token/project vars missing for closeout path |
| Mapping-check drift vs workflow | Low | Med | Update `check-tracker-merge-mapping.sh` + tests in same PR |
| Sibling coupling to #1282/#1284 | Low | Low | Explicit non-goals; no shared commits/branches |

---

## Code Samples

```bash
# Illustrative — adapt during implementation
./scripts/development-workflow/graduation-closeout-from-merged-pr.sh \
  --graduation-pr 1234
# → discovers slug + epic, then execs:
# ./scripts/development-workflow/graduation-closeout.sh \
#   --slug <slug> --graduation-pr 1234 --epic <epic> [--defer-epic-close]
```

```yaml
# Illustrative — adapt during implementation (inside update-tracker-on-merge.yml)
# After detect step recognizes develop-* head:
# - checkout
# - run graduation-closeout-from-merged-pr.sh --graduation-pr ${{ github.event.pull_request.number }}
```

---

## Implementation Order

1. Extend `graduation-closeout.sh` so `--defer-epic-close` ensures the durable
   epic label `defer-epic-close` is present (AC4 durability). Add
   `graduation-closeout-from-merged-pr.sh` with slug/epic discovery, label-based
   defer detection, fail-closed behavior, and delegation to the reconciler.
   Verify with mocked unit tests for parser-risk edge cases and defer-label
   round-trip (CLI defer → label present → wrapper re-defers).
2. Extend `update-tracker-on-merge.yml` graduation path; keep non-graduation
   mappings unchanged. Confirm job logs distinguish skip / run / fail.
3. Update `check-tracker-merge-mapping.sh` +
   `test-check-tracker-merge-mapping.sh` for the new graduation mapping note.
4. Update Protocol 05b Step 5 (primary vs fallback) and graduate-development
   command/skill mirrors; update `github-projects.md` (and README only if
   needed).
5. Confirm existing `test-graduation-closeout.sh` still passes; add
   `test-graduation-closeout-from-merged-pr.sh`.
6. Walk the smoke runbook
   `docs/testing/workflow/1281-automate-graduation-closeout-on-merge.smoke-test.md`
   and tick ACs.
7. Update project docs per **Documentation Updates** (done in steps 4–5 if
   already applied).
8. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Automate graduation closeout on merge** (#1281): invoke the existing graduation closeout reconciler when a develop-<slug> graduation PR merges, while keeping Step 5 as the primary path.`

---

## Document Quality Gate

- Spec/brief coverage: Checked — AC1–AC9 map to layers, tests, smoke steps, and
  Implementation Order.
- Implementation-order consistency: Checked — wrapper name, workflow file,
  mapping checker, protocol/docs mirrors agree across sections.
- Verification support: Checked — Verification Log cites live commands at
  `160bb5e`.
- Behavioral guarantees: Checked — idempotency via reuse of
  `graduation-closeout.sh`; fail-closed discovery; non-graduation mappings
  unchanged.
- Complex workflow decision-gate matrix: Checked — matrix included above;
  mirrors Protocol 05b, wrapper, and `update-tracker-on-merge.yml`.
- Parser/API/concurrency checklist: Checked for parser-risk; concurrent-event
  and cross-cutting checklist Not applicable (rationale in sections above).
