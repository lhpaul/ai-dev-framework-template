# Make /run-work the Adaptive Workflow Entrypoint — Implementation Plan

**Spec**: [1_978-run-work-adaptive-entrypoint_specs.md](./1_978-run-work-adaptive-entrypoint_specs.md)
**Smoke test runbook**: [../../../testing/workflow/978-run-work-adaptive-entrypoint.smoke-test.md](../../../testing/workflow/978-run-work-adaptive-entrypoint.smoke-test.md)

---

## Summary

**Approach**: Reframe `/run-work` as the single adaptive entrypoint by adding a
documented, deterministic **routing layer** in front of the existing portfolio
(Protocol 90), single-item (Protocol 91), and epic (Protocol 95) protocols. The
routing layer is specified in a new protocol section (a routing protocol document
plus a short "routing entrypoint" block referenced from Protocol 90) and is
backed by a deterministic shell helper, `run-work-router.sh`, that classifies a
`/run-work` invocation into one of five routing modes (`no_target_scan`,
`single_item`, `explicit_list`, `epic`, `ambiguous`) and emits a machine-readable
routing-decision record. Existing `/run-work`, `/run-item-work`, and `/run-epic`
command wrappers, skills, and the README/AGENTS user-facing language are updated
so `/run-work` is taught first and `/run-item-work` / `/run-epic` are presented as
compatibility/advanced aliases. The underlying Protocols 90/91/95 keep all their
current responsibilities; this feature only routes into them.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: No production runtime code; the work is concentrated in workflow
documentation (one new protocol section/doc plus edits across ~10 wrapper, skill,
agent, README, and AGENTS files for consistent user-facing language) and one new
deterministic shell helper with a unit-test suite. The volume of consistent
cross-file documentation edits (AC7) and the parser-style routing helper with a
full edge-case test matrix (AC8/AC9) push this past Small, but there is no schema,
API, or concurrency work, keeping it within Medium.

**Dependencies**:

- **#979 (`979-guardrails-config-model`) must be Merged before this item is
  implemented.** The no-target routing mode (Use Case 1, BR3, BR9, AC1) consults
  the repository `guardrails` configuration to decide whether unstarted backlog
  items may be proposed/started. The `guardrails` section, its `mode` values
  (`manual` / `assisted` / `delegated` / `autonomous`), the `backlog_start`
  policy, and the documented safe defaults are defined by #979 in
  `.ai-dev-workflow.yaml` and the guardrails documentation. This plan references
  those field names and defaults but **does not define them**; if #979 is not yet
  merged at implementation time, the developer must stop and escalate rather than
  inventing the guardrails schema. Both items live on the shared
  `develop-guardrails` integration branch (`integration-branch:guardrails`), so
  the implementation PR for #978 targets `develop-guardrails`, not `develop`.
- No external service dependencies.

---

## Verification Log

> Record reproducible plan-time verification commands that influenced scope, counts, or file lists. Include repo revision and concrete results.

| Check | Command / query | Result |
| --- | --- | --- |
| Base branch revision | `git rev-parse --short origin/develop-guardrails` | `bd82fae` |
| Files referencing the three commands (user-facing language scope, AC7) | `grep -rl "run-work\|run-item-work\|run-epic" README.md AGENTS.md GEMINI.md .claude/commands/ .cursor/commands/ .agents/skills/ .codex/skills/ .claude/agents/ .cursor/agents/ docs/workflow/development-workflow/` | 21 files (all listed in "Files to modify"): the 18 user-facing surfaces — `.agents/skills/{run-work,run-item-work,run-epic}/SKILL.md` + their `agents/openai.yaml`, `.claude/commands/{run-work,run-item-work,run-epic}.md`, `.cursor/commands/{run-work,run-item-work,run-epic}.md`, `AGENTS.md`, `GEMINI.md`, `README.md`, `docs/workflow/development-workflow/README.md`, `docs/workflow/development-workflow/agent-model-config.md`, `docs/workflow/development-workflow/integrations/linear.md` — plus the 3 cross-referenced protocols `90`/`91`/`95`. No `run-work`/`run-item-work`/`run-epic` alias files exist under `.codex/skills/` (those aliases live under `.agents/skills/`), so `.codex/skills/` contributes no AC7 edits. |
| `CLAUDE.md` is a symlink to `AGENTS.md` (edit once) | `ls -la CLAUDE.md` | `CLAUDE.md -> AGENTS.md` (no separate edit needed) |
| Codex skills present (no `run-work`/`run-item-work`/`run-epic` under `.codex/skills/`, only canonical `workflow-orchestrator` etc.) | `ls .codex/skills/` | `workflow-orchestrator`, `workflow-item-orchestrator`, ... (the `run-*` command aliases live under `.agents/skills/` only) |
| Existing run-epic helper + test pattern to mirror | `ls scripts/development-workflow/run-epic-*.sh scripts/development-workflow/tests/test-run-epic-*.sh` | `run-epic-scope-resolver.sh`, `run-epic-policy-recommender.sh`, `run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh` + matching `test-*` files |
| #979 guardrails config spec location (dependency) | `git show origin/develop-guardrails:docs/specs/developments/20260617083209_guardrails-config-model/1_guardrails-config-model_specs.md` | Defines `guardrails` section, four modes, `backlog_start` policy, risk scale, stop conditions; default mode `manual` |
| #979 issue state | `gh issue view 979 --json state,labels` | `OPEN`, label `integration-branch:guardrails` (not yet merged at plan time) |

---

## Routing Logic Specification (deterministic, testable — AC8)

This is the canonical routing decision table the implementation must encode both
in the new protocol document and in `run-work-router.sh`. Inputs are the target
argument tokens, discovered tracker/repository state, and repository
configuration. The output is exactly one routing mode.

| Input + discovered state + configuration | Routing mode (`code value`) | Reference |
| --- | --- | --- |
| No target token supplied | `no_target_scan` | UC1, BR3, AC1 |
| Exactly one target token that resolves to exactly one issue, workflow branch, open PR, or development folder, and that target is **not** epic-like | `single_item` | UC2, BR4, AC2 |
| Exactly one target token that resolves to a single issue which is **epic-like** (has child items / native sub-issues) | `epic` | UC2 consideration, UC4, BR6, AC5 |
| Two or more explicit target tokens (after duplicate collapse) that each resolve to a concrete target | `explicit_list` | UC3, BR5, AC3 |
| A single target token explicitly identified as an epic (e.g., a native epic issue, or an `integration-branch:<slug>` epic) | `epic` | UC4, BR6, AC4 |
| Any input that cannot be deterministically resolved to exactly one of the above (e.g., a token matching neither an issue/branch/PR/folder, an ambiguous list with at least one unresolvable token, or a conflicting signal) | `ambiguous` | BR2/BR10, AC11 |

**Transitions** (from spec "Valid transitions"):

- A request resolves to exactly one of `no_target_scan`, `single_item`,
  `explicit_list`, or `epic`.
- `single_item` → `epic` when the single resolved target turns out to be
  epic-like.
- Any mode → `ambiguous` when resolution is non-deterministic;
  `ambiguous` performs **no mutation** and stops for a human (AC11).

**Configuration consumption (no-target mode only — AC1, BR3, BR9)**: In
`no_target_scan` mode, the router reports which `guardrails` configuration values
(from #979) bound the proposed plan — at minimum the resolved autonomy `mode` and
the `backlog_start` policy — so the human can see whether unstarted backlog items
were eligible to be proposed. When no `guardrails` section is present, the
documented #979 safe defaults apply (mode `manual`, backlog starts require
confirmation), and the router records that backlog starts were not auto-proposed.
The router never **starts** backlog work; it only classifies the mode and reports
the configuration-bounded plan, then hands off to Protocol 90, which owns the
existing "largest safe start batch" proposal and human-approval gate.

**Routing-decision record (AC10, BR7)**: Every invocation emits a record
containing: the inferred `mode` (code value + display label), the resolved scope
(the concrete set of targets, or the held-back/out-of-scope set with reasons),
the inputs that drove the decision (raw target argument, tracker/repository state
consulted, and the guardrails configuration values consulted in no-target mode),
and — when the run does not advance — a `stop reason` (ambiguous, insufficient
autonomy, or blocked dependency). The helper emits this as stable `key=value`
lines plus an optional `--json` object (mirroring `run-epic-scope-resolver.sh`).

---

## Layer-by-Layer Changes

> Only the layers below apply. This is a workflow-documentation + shell-tooling
> feature; there is no database, API, frontend, or infrastructure layer.

### Shared Packages / Libraries (workflow helper scripts)

- [ ] **New** `scripts/development-workflow/run-work-router.sh` — deterministic
      routing classifier. Accepts the `/run-work` target argument(s) (zero or
      more tokens) and optional flags (`--json`, and a way to inject discovered
      state for testing, mirroring how `run-epic-*` helpers accept fixtures /
      mock `gh`). Emits the routing-decision record (stable `key=value` lines and
      `--json`) per the Routing Logic Specification above. The script is
      **read-only**: it must not update tracker status, create branches, open or
      edit PRs, merge PRs, close issues, delete branches, or post comments —
      same non-mutation contract as `run-epic-scope-resolver.sh`. (AC8, AC10,
      AC11)
- [ ] Source `scripts/development-workflow/workflow-lib.sh` for shared helpers
      and follow the existing `set -euo pipefail` + `SCRIPT_DIR` + `usage()`
      conventions used by the other `run-epic-*.sh` helpers.

### Infrastructure / Configuration (workflow protocol documents)

- [ ] **New routing protocol document** that specifies the deterministic routing
      logic (the Routing Logic Specification table above), the five routing
      modes, the routing-decision record format, and how each mode hands off to
      Protocol 90 / 91 / 95. Filename: `docs/workflow/development-workflow/
      protocols/96-run-work-routing-protocol.md` (next free protocol number;
      `95-run-epic-protocol.md` is the current highest creator/supporting
      protocol number before the `90`-block). This document is the canonical
      source the command wrappers and skills point to for routing. (AC8, BR8)
- [ ] **`90-batch-orchestrate-work-protocol.md`** — add a short "Routing
      entrypoint" block near the top (after the "When to use this protocol"
      section) stating that `/run-work` first runs the routing classifier
      (Protocol 96 / `run-work-router.sh`); `no_target_scan` and `explicit_list`
      modes continue into this protocol, `single_item` routes to Protocol 91,
      and `epic` routes to Protocol 95. Keep Protocol 90's existing
      responsibilities intact (BR11). The existing "Explicit Item List Scope
      Guard" already implements `explicit_list` non-mutation behavior (BR5, AC3)
      — cross-reference it from the routing block rather than duplicating it.
- [ ] **`91-orchestrate-work-protocol.md`** — add a one-paragraph note that
      `single_item` routing arrives here from `/run-work` and that, if a
      single-target resolves to an epic-like item, the runner re-routes to
      Protocol 95 (`single_item` → `epic` transition, AC5). The existing
      single-item scope guard already covers BR4/AC2 — cross-reference it.
- [ ] **`95-run-epic-protocol.md`** — add a one-paragraph note that `epic`
      routing may arrive here from `/run-work` and that the read-only scope
      resolver runs before any mutation (BR6, AC4). No change to the resolver's
      existing read-only contract.

### Documentation — user-facing language (AC7)

These are the user-facing surfaces that must consistently teach `/run-work` first
and present `/run-item-work` and `/run-epic` as compatibility/advanced aliases.
Listed here as the layer; the exact per-file edits are enumerated in
"Files to modify" and "Implementation Order".

- [ ] Command wrappers: `.claude/commands/run-work.md`,
      `.claude/commands/run-item-work.md`, `.claude/commands/run-epic.md`,
      `.cursor/commands/run-work.md`, `.cursor/commands/run-item-work.md`,
      `.cursor/commands/run-epic.md`.
- [ ] Codex command-alias skills: `.agents/skills/run-work/SKILL.md`,
      `.agents/skills/run-item-work/SKILL.md`, `.agents/skills/run-epic/SKILL.md`
      (and their `agents/openai.yaml` descriptions if the wording there names the
      command's role).
- [ ] Top-level docs: `README.md`, `AGENTS.md` (CLAUDE.md is a symlink — no
      separate edit), `GEMINI.md`, `docs/workflow/development-workflow/README.md`.
- [ ] Reference docs that name the commands:
      `docs/workflow/development-workflow/agent-model-config.md`,
      `docs/workflow/development-workflow/integrations/linear.md`.

---

## Files to modify

> Full enumeration. The user-facing-language edits (AC7) span every file that
> describes the three commands; the list below is the live-search result from the
> Verification Log plus the two new files. Edit `CLAUDE.md` is **not** listed
> because it is a symlink to `AGENTS.md`.

**New files (3 — including the test file)**:

1. `scripts/development-workflow/run-work-router.sh` — routing classifier helper (AC8, AC10, AC11).
2. `scripts/development-workflow/tests/test-run-work-router.sh` — routing decision unit tests (AC9).
3. `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md` — canonical routing protocol (AC8, BR8).

**Modified files (existing — routing protocol cross-references)**:

4. `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
5. `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
6. `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`

**Modified files (existing — user-facing language, AC7)**:

7. `.claude/commands/run-work.md`
8. `.claude/commands/run-item-work.md`
9. `.claude/commands/run-epic.md`
10. `.cursor/commands/run-work.md`
11. `.cursor/commands/run-item-work.md`
12. `.cursor/commands/run-epic.md`
13. `.agents/skills/run-work/SKILL.md`
14. `.agents/skills/run-item-work/SKILL.md`
15. `.agents/skills/run-epic/SKILL.md`
16. `.agents/skills/run-work/agents/openai.yaml` (only if its description names the command's role)
17. `.agents/skills/run-item-work/agents/openai.yaml` (only if its description names the command's role)
18. `.agents/skills/run-epic/agents/openai.yaml` (only if its description names the command's role)
19. `README.md`
20. `AGENTS.md`
21. `GEMINI.md`
22. `docs/workflow/development-workflow/README.md`
23. `docs/workflow/development-workflow/agent-model-config.md`
24. `docs/workflow/development-workflow/integrations/linear.md`

**Modified files (changelog)**:

25. `CHANGELOG.md` — `[Unreleased]` entry (see Implementation Order).

> **Cross-cutting checklist classification**: **Not applicable.** This feature
> does not add or rename a safety/quality/compliance checklist category in
> `REVIEW.md` or in the planning/implementation protocols, and it does not add a
> new conditional guidance block that every future feature plan must satisfy. It
> adds a routing entrypoint and a deterministic classifier. Therefore the
> mandatory cross-cutting-checklist file enumeration (developer protocol, agent
> guidance files, `REVIEW.md`, Codex skill files for the plan/impl stages) is not
> triggered. The user-facing-language file list above is driven by AC7, not by a
> cross-cutting checklist.

---

## Testing Strategy

**Test types**: Unit (shell), Smoke (manual runbook).

**Parser-risk classification**: **Applies.** `run-work-router.sh` parses the
`/run-work` target argument tokens and classifies them into routing modes via a
deterministic decision table — a rule engine over structured input tokens. Per
Protocol 02 Step 3, the parser-risk addendum below is mandatory: it requires an
edge-case enumeration plus a named unit-test file with at least one automated test
per edge case. Smoke-only coverage is insufficient for the router.

**Unit test file**: `scripts/development-workflow/tests/test-run-work-router.sh`
(mirrors the structure of `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`:
`set -euo pipefail`, a mock `gh`/`git` on `PATH` that rejects any mutating call,
a temp working dir, and per-case assertions on the router's `key=value` / `--json`
output). This satisfies AC9's requirement that tests cover the routing decision
for no target, one target, multiple targets, and an epic target.

### Parser-risk addendum

**Edge-case enumeration** (concrete inputs the router must classify correctly):

- *No-target boundary*: empty argument string `""` and whitespace-only argument
  `"   "` → both classify as `no_target_scan` (not `ambiguous`). (AC1)
- *Single bare issue number*: `42` resolving to a non-epic issue → `single_item`. (AC2)
- *Single issue number that is epic-like*: `977` resolving to an issue with child
  items → `epic` (the `single_item` → `epic` transition). (AC5)
- *Single branch token*: `feature/42-foo`, `spec/42-foo`,
  `implementation-plan/42-foo` → `single_item`. (AC2)
- *Single PR token*: `#118` / `118` resolving to an open PR → `single_item`. (AC2)
- *Single development-folder token*: `docs/specs/developments/2026..._42-foo` →
  `single_item`. (AC2)
- *Explicit multi-target list*: `42 43 44` (space-separated) and `42,43,44`
  (comma-separated) → `explicit_list`; both forms must be accepted. (AC3)
- *Duplicate collapse in a list*: `42 42 43` → `explicit_list` with scope `{42,43}`
  (duplicates collapsed, per UC3 consideration). (AC3)
- *Native epic target*: `--epic 977` style / an epic issue token → `epic` with
  read-only scope resolution before mutation. (AC4)
- *Negative lookalikes (must NOT match)*: a token that resembles an issue number
  but does not resolve to any issue/branch/PR/folder (e.g., `999999` with no such
  artifact) → `ambiguous`, not `single_item`. A free-text phrase like
  `"only spec stage"` that is a filter, not a target → must be handled per the
  documented rule (treated as a no-target filter for `no_target_scan`, or
  `ambiguous` if it cannot be deterministically classified — the protocol must
  state which, and the test asserts the documented behavior).
- *Mixed/ambiguous list*: `42 not-a-target` where one token is unresolvable →
  `ambiguous` (no partial mutation). (AC11)
- *Single token that is both branch-like and issue-like collision*: a token that
  could match two different concrete targets → `ambiguous` (conflicting signal). (AC11)

**Unit test mapping** (each edge case maps to at least one automated test in
`test-run-work-router.sh`):

| Edge case | Test asserts |
| --- | --- |
| Empty / whitespace-only argument | `MODE=no_target_scan` |
| Single bare non-epic issue | `MODE=single_item` and resolved identity |
| Single epic-like issue | `MODE=epic` (transition applied) |
| Single branch / PR / dev-folder token | `MODE=single_item` for each form |
| Space- and comma-separated list | `MODE=explicit_list` for both forms |
| Duplicate tokens in list | `MODE=explicit_list`, scope deduplicated |
| Native epic target | `MODE=epic`, record notes read-only scope step |
| Unresolvable lookalike token | `MODE=ambiguous`, no mutation, stop reason set |
| Mixed list with one unresolvable token | `MODE=ambiguous` |
| Conflicting branch/issue collision | `MODE=ambiguous` |
| Routing-decision record fields present | record includes mode, resolved scope, inputs (AC10) |
| Read-only contract | mock `gh`/`git` mutating calls cause test failure if invoked |

> **Suppression semantics**: Not applicable — the router supports no inline
> suppression/directive syntax.

**Key scenarios to test** (smoke runbook, maps to acceptance criteria):

1. `/run-work` with no target records `no_target_scan` and shows the
   configuration-bounded plan with advance/hold-back sets — AC1, AC10.
2. `/run-work <one non-epic target>` records `single_item` and advances only that
   item — AC2.
3. `/run-work <two+ targets>` records `explicit_list`, treats the list as a hard
   bounded scope, and logs out-of-scope items without mutating them — AC3.
4. `/run-work <epic target>` records `epic` and completes read-only scope
   resolution before any mutation — AC4.
5. `/run-work <single epic-like target>` routes to `epic`, not `single_item` —
   AC5.
6. `/run-item-work` and `/run-epic` invoked directly still behave as today and
   match what `/run-work` would route to — AC6.
7. Docs/README/AGENTS/wrappers/skill metadata teach `/run-work` first; aliases are
   labeled compatibility/advanced — AC7.
8. Routing logic is documented deterministically in the protocols — AC8.
9. The unit-test suite covers no/one/multiple/epic targets — AC9.
10. Every invocation emits a routing-decision record — AC10.
11. An unresolvable request records `ambiguous`, performs no mutation, and stops —
    AC11.

**Regression suite**: The repository's automated regression suite for workflow
tooling is the shell test suite under `scripts/development-workflow/tests/`. The
new `test-run-work-router.sh` is the regression spec covering the smoke runbook's
routing scenarios; add a checklist item in the implementation to ensure it is
wired into however the existing `test-*.sh` files are discovered/run (mirror
`test-run-epic-*.sh`).

---

## Seed Data

> No application seed data. The router's "discovered state" inputs are simulated
> in unit tests via a mock `gh`/`git` on `PATH` (the established
> `test-run-epic-*.sh` pattern), not via persisted fixtures.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock `gh` responses | Issue with/without child items (epic vs non-epic), open PR, branch existence, unresolvable token | inline in `scripts/development-workflow/tests/test-run-work-router.sh` |
| Mock `gh`/`git` mutating-call guard | Any `pr merge` / `issue edit` / `git push` etc. exits non-zero to prove read-only contract | inline in `scripts/development-workflow/tests/test-run-work-router.sh` |

---

## Documentation Updates

> Listed for the developer to execute during implementation (these are the
> user-facing-language updates required by AC7, plus the new protocol doc). They
> are part of the feature's deliverable, not a separate post-implementation pass.

- [ ] `README.md` — present `/run-work` as the primary adaptive entrypoint;
      relabel `/run-item-work` and `/run-epic` example prompts as
      compatibility/advanced aliases.
- [ ] `AGENTS.md` — update the Workflow Commands table rows and the Codex skills
      narrative so `/run-work` is the recommended first command and the routing
      behavior (5 modes) is noted; aliases labeled accordingly. (CLAUDE.md is a
      symlink — no separate edit.)
- [ ] `GEMINI.md` — same table/narrative updates as `AGENTS.md`.
- [ ] `docs/workflow/development-workflow/README.md` — update the command table
      and Codex-skills narrative; add a pointer to the new routing protocol (96).
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — adjust any
      wording that frames `/run-work` vs `/run-item-work` vs `/run-epic` so the
      recommended-entrypoint language is consistent.
- [ ] `docs/workflow/development-workflow/integrations/linear.md` — adjust any
      command-name wording for consistency (no behavioral change to Linear flow).
- [ ] New `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
      — the canonical routing specification.
- [ ] `docs/workflow/development-workflow/protocols/90-,91-,95-` — routing
      cross-reference notes (see Layer-by-Layer).

> No `docs/project/` or `docs/best-practices/` files require updates — this
> feature changes workflow command framing and tooling, not project domain,
> architecture, or coding standards.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| #979 not merged when implementation starts, so the `guardrails` field names/defaults the no-target mode references do not yet exist | Med | High | Implementation Order Step 0 is a hard gate: confirm #979 is merged into `develop-guardrails` before writing any no-target configuration-consumption text. If not merged, stop and escalate — do not invent the guardrails schema. |
| User-facing language drifts inconsistently across the ~14 doc/wrapper/skill files (AC7) | Med | Med | Use one canonical phrasing block (defined in Step 2) and apply it verbatim across all surfaces; the cross-section consistency self-check and Document Quality Gate verify symbol/label consistency before the PR. |
| Router classification is under-specified, leading to non-deterministic `ambiguous` fallbacks | Low | Med | The Routing Logic Specification table is the single source of truth; every row maps to an automated test in `test-run-work-router.sh`; ambiguous is the explicit safe default (AC11, no mutation). |
| Behavioral regression in Protocols 90/91/95 from the routing edits | Low | High | Routing edits are additive cross-reference blocks only; BR11 and the spec Out-of-Scope forbid merging/removing protocols or changing their stage responsibilities. |
| New protocol number `96` collides with a future/parallel item | Low | Low | Verified `95` is the current highest; the developer re-checks the highest protocol number at implementation time and bumps if needed, updating all references in one pass. |

---

## Code Samples

> No production code samples are included. `run-work-router.sh` and
> `test-run-work-router.sh` must follow the existing `run-epic-*.sh` /
> `test-run-epic-*.sh` conventions (`set -euo pipefail`, `SCRIPT_DIR` resolution,
> `workflow-lib.sh` sourcing, `usage()`, stable `key=value` + `--json` output,
> read-only mutating-call guard in tests). The detailed implementation belongs in
> the implementation PR. Any illustrative snippet added during implementation must
> be marked `# Illustrative — adapt during implementation`.

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones.

1. **Dependency gate (do first)**: Confirm #979 (`979-guardrails-config-model`) is
   merged into `develop-guardrails` and that the `guardrails` section (`mode`
   values, `backlog_start` policy, documented safe defaults) exists in
   `.ai-dev-workflow.yaml` and the guardrails docs. If not merged, **stop and
   escalate** — do not define the guardrails schema in this item.
2. **Fix canonical wording**: Draft the single canonical user-facing phrasing for
   "`/run-work` is the primary adaptive entrypoint; `/run-item-work` and
   `/run-epic` are compatibility/advanced aliases" plus a one-line summary of the
   five routing modes. This phrasing is reused verbatim in Steps 6–7 (AC7).
3. **Write the routing protocol**: Create
   `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
   with the Routing Logic Specification table, the five routing modes (code value
   + display label), the transitions, the routing-decision record format, the
   no-target guardrails-configuration consumption (referencing #979 field
   names/defaults), and the handoff mapping to Protocols 90/91/95. Re-verify `96`
   is still the next free protocol number. (AC8, BR8)
4. **Implement the router helper**: Create
   `scripts/development-workflow/run-work-router.sh` encoding the same decision
   table, emitting the routing-decision record as stable `key=value` lines and
   `--json`, read-only (no mutations). (AC8, AC10, AC11)
5. **Write the unit tests**: Create
   `scripts/development-workflow/tests/test-run-work-router.sh` covering every
   edge case in the Testing Strategy mapping (no/one/multiple/epic + negatives +
   ambiguous + read-only guard). Run it and confirm all cases pass. (AC9)
6. **Add protocol cross-references**: Add the routing-entrypoint block to
   `90-batch-orchestrate-work-protocol.md` and the routing notes to
   `91-orchestrate-work-protocol.md` and `95-run-epic-protocol.md`, pointing to
   Protocol 96 and the router. Do not change existing stage responsibilities
   (BR11).
7. **Update command wrappers and skills** (AC7) with the canonical phrasing:
   `.claude/commands/run-work.md`, `.claude/commands/run-item-work.md`,
   `.claude/commands/run-epic.md`, `.cursor/commands/run-work.md`,
   `.cursor/commands/run-item-work.md`, `.cursor/commands/run-epic.md`,
   `.agents/skills/run-work/SKILL.md`, `.agents/skills/run-item-work/SKILL.md`,
   `.agents/skills/run-epic/SKILL.md`, and the three `agents/openai.yaml`
   descriptions if they name the command role.
8. **Update top-level and reference docs** (AC7): `README.md`, `AGENTS.md`
   (CLAUDE.md symlink — no separate edit), `GEMINI.md`,
   `docs/workflow/development-workflow/README.md`,
   `docs/workflow/development-workflow/agent-model-config.md`, and
   `docs/workflow/development-workflow/integrations/linear.md`. Add the Protocol 96
   pointer to the workflow README command table.
9. **Verify aliases still work** (AC6): confirm `/run-item-work` and `/run-epic`
   wrappers still point to Protocols 91 and 95 and behave unchanged; only their
   framing (compatibility/advanced alias) changed.
10. **Run the smoke runbook scenarios** in
    `docs/testing/workflow/978-run-work-adaptive-entrypoint.smoke-test.md` and the
    `markdownlint-cli2` + shell-test checks; confirm all pass.
11. **Update project docs** per the Documentation Updates section (already covered
    by Steps 6–8; confirm no `docs/project/` or `docs/best-practices/` edits are
    needed — they are not).
12. **Update `CHANGELOG.md`** under `[Unreleased]` using the project's
    `**Bold Title** (#N):` format. Add exactly:

    ```markdown
    - **Make /run-work the adaptive workflow entrypoint** (#978): `/run-work` now routes invocations to no-target scan, single-item, explicit-list, or epic behavior via a documented deterministic routing layer (`run-work-router.sh` + protocol 96), emits a routing-decision record, and is taught as the primary entrypoint while `/run-item-work` and `/run-epic` remain compatibility/advanced aliases.
    ```
