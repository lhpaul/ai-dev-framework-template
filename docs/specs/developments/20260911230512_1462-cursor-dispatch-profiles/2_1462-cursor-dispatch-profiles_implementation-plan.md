# Cursor Dispatch Profiles — Implementation Plan

**Spec**: [Cursor Dispatch Profiles](1_1462-cursor-dispatch-profiles_specs.md)
**Smoke test runbook**: [Cursor Dispatch Profiles](../../../testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md)

---

## Summary

**Approach**: Add a canonical integration guide (`cursor-dispatch-profiles.md`) that
defines the three profiles, orchestration layers, decision matrix, declaration
contract, handoff metadata, and worked examples. Mirror that contract onto every
bounded-command entrypoint, portfolio and item orchestration role documents,
Protocols 90/91/95, `agent-model-config.md`, and `.cursor/rules/workflow.mdc`.
Extend `guardrails-enforcement.md` section 4 with the two new named stop
conditions. Resolve the spec's pre-branch `/run-items` affected-item gap in this
plan and propagate it through the canonical doc and stop-message guidance.

**Estimated complexity**: L

**Rationale**: The change is documentation-heavy but must stay internally
consistent across many mirror surfaces, reproduce the full decision matrix
without restating role contracts, and give operators a self-service path under
Cursor Remote Control. Wrong or drifted wording drops gates in production runs.

**Dependencies**: Spec PR [#1732](https://github.com/lhpaul/ai-dev-framework-template/pull/1732)
is merged to `develop`. No other feature must merge first. Related gaps **#1745**
(batch-context marker enforcement) and **#1746** (stage-role harness permission
denial) remain out of scope and must be referenced, not solved, here.
Verified `2026-09-18` via `gh issue view 1745 --json state` / `gh issue view 1746
--json state`: both **OPEN**. Consequence if either closes before or during
implementation: re-check the issue resolution text, then either (a) keep the
canonical-doc / guardrails / role-agent "out of scope" callouts only if the
closed issue did not land a conflicting contract, or (b) update those surfaces
in the same implementation PR so they no longer assert an unresolved gap.

**Design assets**: None. Workflow documentation only.

---

## Verification Log

Re-run `2026-09-20` against verified head **`4095718b`** (the plan content
commit; full SHA `4095718b22718710709c2e5c61bfb9c9b4587537`). The commit that
carries this log is the **child** of `4095718b` and changes **only** this
Verification Log and the Document Quality Gate lines that cite it; no plan
content, checklist, or smoke-runbook text changed in the child. Patterns are
extended-regex alternation (`grep -E 'a|b'`); results were produced with
`grep -rlE` because the local `rg` is shadowed. Checks that need the
implementation are marked **Deferred to implementation**, not Pass.

| Check | Command / query | Result at `4095718b` |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `4095718b`. `origin/develop` is `f1d5021a`; the branch is 20 commits behind it, so A1's `git merge-base --is-ancestor origin/develop HEAD` returns **not ancestor**: **Fail now, deferred to implementation start** (rebase or merge `develop` first) |
| Canonical doc absent pre-impl | `test ! -f docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md && echo absent` | `absent` (Pass) |
| Profile strings outside development folder | `grep -rlE 'cursor-native-handoff|cursor-parent-orchestrated|cursor-inline-fallback' . --exclude-dir=.git --exclude-dir=node_modules` filtered to drop `20260911230512_1462` paths | `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` only (Pass) |
| Bounded command adapters | `grep -rl 'run-item' .cursor/commands .claude/commands .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-items .agents/skills/run-epic .agents/skills/run-work` | **18** hits (Pass): **14** command/`SKILL.md` (`5` `.cursor/commands` + `4` `.claude/commands` + `5` `SKILL.md`) + **4** `agents/openai.yaml` (`14+4=18`). The four yaml files are not edited; `.claude/commands/run-epic.md` is in Files to modify but **not** in the 18 (no `run-item` substring). |
| Orchestration role agents | `ls .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md` | All four present (Pass) |
| Files-to-modify paths | Each `Path` cell in Files to modify checked with `[ -e path ]` | 31 existing paths present; the 4 **Create** entries (canonical doc, surface guard, fixtures directory, changelog fragment) are absent as expected (Pass) |
| Spec merge gate | `gh pr view 1732 --json state,baseRefName` | `MERGED`, base `develop` (Pass) |
| Related gap #1745 | `gh issue view 1745 --json state,title` | `OPEN` — batch-context marker enforcement; out of scope here (Pass) |
| Related gap #1746 | `gh issue view 1746 --json state,title` | `OPEN` — stage-role harness permission denial; out of scope here (Pass) |
| Stop conditions pre-impl | `grep -cE 'dispatch_profile_declaration_missing|dispatch_handoff_unavailable' docs/workflow/development-workflow/guardrails-enforcement.md` | `0` (expected until implementation) (Pass) |
| Markdown lint (plan + smoke runbook) | `npx markdownlint-cli2` and `python3 scripts/lint/markdown-heuristic-lint.py` on both files | 0 issues on both files (Pass) |
| Shell-script lint (new `.sh`) | `bash -n`; `shellcheck --severity=warning`; `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop` | **Deferred to implementation** (script not yet created; `shellcheck` and the guard linter are available locally) |
| Surface guard (link, profile string, E1-E5 clauses, canonical-doc checks) | `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` | **Deferred to implementation** (script not yet created) |
| Scanner fixtures + `--self-test` (Parser-Risk cases, fence semantics) | `... --self-test` | **Deferred to implementation** |
| Planted-violation proofs (cycles 1-16 plus per-class repeats) | see Layer-by-Layer Changes → Workflow tooling | **Deferred to implementation** |
| `simulate_bounded_paths`; smoke Steps 7-14 | smoke runbook | **Deferred to implementation** (needs the implementation head) |

---

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Integration / artifact base branch | `develop` | `.ai-dev-workflow.yaml` + batch handoff | `2026-09-17T11:15:00Z`; repo `32605700` | Current invocation `#1462`; batch peers `#1757,#1462,#1496,#1515,#1561,#1583,#1529`; same-surface open PRs none | `Verified` |
| Repository mode | `single_repo` | Batch handoff `WORKFLOW_MODE` | `2026-09-17T11:15:00Z`; repo `32605700` | Peers touch adjacent workflow docs but do not change base branch or mode for this item | `Verified` |

Peer item `#1529` references dispatch profiles in its plan narrative only; it
does not alter the integration branch or artifact ownership for `#1462`.

---

## Plan-Stage Gap Resolution (spec § Known gaps)

**Gap**: Pre-branch, explicit-list `/run-items` declaration stops lack an
affected-work-item representation when no branch, PR, or development folder
exists yet.

**Decision (recorded here, propagated in implementation)**:

- For a declaration stop on an explicit-list `/run-items` invocation **before
  any item-scoped artifact exists**, the affected work item is a **single**
  string: `explicit_list_invocation_targets=<t1>,<t2>,...`, one `<ti>` per
  target **in invocation order**. Protocol 90 explicit lists accept issue
  numbers, tracker identifiers (for example `ENG-123`), branch names, and PR
  numbers, so the serialization preserves every accepted form:
  - Each `<ti>` is the target **verbatim as supplied** on the invocation, with
    only leading and trailing ASCII whitespace trimmed. **No rewriting**: a `#`
    is never added or removed, case is preserved, and a `/` in a branch name is
    kept.
  - The delimiter is a single comma with no surrounding spaces.
  - Escaping (percent-encoding, applied per target, `%` first so it is not
    double-encoded): `%` becomes `%25`, `,` becomes `%2C`, and any ASCII
    whitespace or control character inside a target becomes `%XX` (uppercase
    hex of the UTF-8 byte). All other bytes are emitted unchanged.
  - Duplicates are preserved; the value is always one line; at least two
    targets are present (the `/run-items` minimum).
  - Example: invoked as `/run-items #1462 ENG-123 feature/x,y 1771` yields
    `explicit_list_invocation_targets=#1462,ENG-123,feature/x%2Cy,1771`.
- Report **once** for the whole invocation; do not emit one stop per target.
- Mirror this rule in:
  - `integrations/cursor-dispatch-profiles.md` (Named stop reporting subsection),
  - `guardrails-enforcement.md` section 4 row text for
    `dispatch_profile_declaration_missing`,
  - Protocol 90 explicit-list preamble (declaration checkpoint before item
    resolution / first mutation),
  - The merged spec's Named Stop-Condition Mapping table (implementation PR
    updates the spec file to close the documented gap).

---

## Architecture and Decision Boundary

### Decision 1: Canonical guide owns the matrix; mirrors link back

All profile rules, evaluation order, transitions, and examples live in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Every mirror surface states the requirement and links to that file rather than
restating the matrix (AC1–AC3, AC10, AC18–AC19).

### Decision 2: Declared, not detected

Implementation adds **documentation and runner instructions only**. No shell
helper auto-detects Cursor environment capabilities (spec Out of Scope item 3).
Commands and orchestration protocols require a visible declaration block before
the first mutating action (or before reporting for read-only checkpoints).

### Decision 3: Standard declaration block

The canonical doc defines one markdown-friendly block operators and agents
copy into run output:

```markdown
<!-- Illustrative — adapt during implementation -->
**Dispatch profile**: Native handoff (`cursor-native-handoff`)
**Accountable orchestration role**: Work Item Runner (item layer)
**Accountability posture**: handed off intact
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

Re-declarations repeat the block with a **Reason** line when the profile
changes mid-run.

### Decision 4: Prelude vs declaration ordering

The shared bounded prelude (`bounded-run-prelude.md`) may complete read-only
scope and policy resolution first. The dispatch-profile declaration still must
appear **immediately before the first mutating action** (branch create, file
edit that changes tracked artifacts, tracker mutation, PR open). For
`/run-work`, declaration precedes reporting scan results.

### Decision 5: Parent-orchestrated absorbs full role contract

Under `cursor-parent-orchestrated`, the current context performs every
orchestration obligation from the absorbed role's agent + protocol surfaces and
**delegates** spec/plan/implement/review work to stage roles with full handoff
metadata (`BATCH_CONTEXT`, isolation, **worktree path**, branch, base, artifact repo root,
mutation class). No inline product work (AC4, AC19).

### Decision 6: Cursor environment defaults in agent-model-config

Add a **Cursor dispatch profiles** subsection listing, per environment ×
orchestration layer, the profile, the **model assignment**, and the evidence
class (AC15). Profile and evidence:

| Environment | Portfolio layer | Epic layer | Item layer | Evidence |
| --- | --- | --- | --- | --- |
| Cursor Desktop (local app) | Native handoff | Native handoff | Native handoff | Confirmed by observation (template default) |
| Cursor Remote Control | Parent orchestrated | Parent orchestrated | Parent orchestrated | Confirmed by observation (recorded failure mode) |
| Cursor Cloud Agents | Parent orchestrated | Parent orchestrated | Parent orchestrated | Explicit assumption (conservative default per spec) |

**Model assignments** (explicit, so implementation does not invent them). The
tiers come from the existing role table in `agent-model-config.md`: Portfolio
Orchestrator `economy` / `fast`; Work Item Runner `balanced` / `auto`. The
epic layer has no dedicated agent file; it is a coordination loop that makes
delegated merge decisions, so it takes the Work Item Runner tier (`balanced`)
as its floor. Stage roles (spec, plan, implement, review) always keep their own
configured models under every profile.

| Environment | Portfolio layer model | Epic layer model | Item layer model | Model evidence |
| --- | --- | --- | --- | --- |
| Cursor Desktop | Portfolio Orchestrator agent's own model: `economy` / `fast` | Epic-layer role's model: `balanced` / `auto` | Work Item Runner agent's own model: `balanced` / `auto` | Confirmed by observation (agent frontmatter applies on native handoff) |
| Cursor Remote Control | Absorbing current context runs at the `economy` floor; any session model at or above `economy` is acceptable, `fast` where selectable | Absorbing current context must run at `balanced` or higher, `auto` where selectable | Absorbing current context must run at `balanced` or higher, `auto` where selectable | Confirmed by observation for the profile; **explicit assumption** for the model (the remote session's model is not switched by role frontmatter) |
| Cursor Cloud Agents | Same as Remote Control portfolio: `economy` floor, `fast` where selectable | Same as Remote Control epic: `balanced` floor, `auto` where selectable | Same as Remote Control item: `balanced` floor, `auto` where selectable | **Explicit assumption** (profile and model both conservative defaults) |

Under `cursor-parent-orchestrated`, the absorbing context never uses `inherit`
as a substitute for the floor: if the session model is below the absorbed
role's tier, the declaration records the shortfall and the operator switches
the session model before the first mutating action. Unobserved environments use
the more restrictive applicable profile and the higher of the applicable model
floors until an operator confirms otherwise in run output.

### Decision 7: Portfolio batch scheduling unchanged

Parent-orchestrated portfolio runs use Protocol 90 Step 4's existing
one-item-at-a-time fallback when Work Item Runner handoff is unavailable. This
feature does not add concurrent scheduling behavior (AC17).

---

## Workflow Decision-Gate Consistency Matrix

This feature is a **complex workflow decision gate** (REVIEW.md). The **normative
matrix is the merged spec** — do not maintain a shortened copy in this plan.

**Authoritative sources** (implementation must match verbatim):

- Spec [Decision-Gate Consistency Matrix](1_1462-cursor-dispatch-profiles_specs.md#decision-gate-consistency-matrix) — all input rows, evaluation order, mirror-surfaces list, examples requirement, and out-of-scope note for #1746.
- Spec [Named Stop-Condition Mapping](1_1462-cursor-dispatch-profiles_specs.md#named-stop-condition-mapping) — including the plan-resolved pre-branch explicit-list affected-item format.

**Implementation mapping** (where each authoritative row lands):

| Spec matrix row (summary) | Canonical doc section | Guardrails / protocols |
| --- | --- | --- |
| Native handoff + mutating command | § Decision gate — full row text | Protocols 90/91/95 declaration + handoff |
| Native handoff + read-only portfolio scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Parent orchestrated + mutating command | § Decision gate + § Absorbed contract | Role agents + protocols |
| Parent orchestrated + read-only scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Unconfirmed onward-handoff capability (initial handoff confirmed) + mutating / scan | § Decision gate + § Conservative defaults | `agent-model-config.md` assumptions |
| Native → parent re-declaration (mid-run orchestration failure, initial handoff still available) | § Transitions | Protocol 91 run summary |
| Native → inline re-declaration (mid-run failure + initial handoff lost) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent → inline re-declaration (stage handoff unavailable) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent orchestrated + reachable stage credential/permission denial | § Delegation failures | Reuse `missing_required_secret_or_permission` |
| No handoff / unconfirmed initial handoff + read-only | § Decision gate | Inline fallback observing posture |
| No handoff / unconfirmed initial handoff + would mutate | § Decision gate | Stop `dispatch_handoff_unavailable` |
| Declaration missing at first mutating action | § Declaration contract | `dispatch_profile_declaration_missing` |
| Invalid profile value / missing accountable role | § Declaration contract | Same stop |
| Declaration invalid at read-only checkpoint (scan / inline-fallback) | § Declaration contract | Same stop |
| Posture mismatch (`observing` at mutation or absorbed/handoff at read-only checkpoint) | § Accountability postures | Same stop |
| Profile/fact mismatch (more or less permissive than assigned outcome) | § Declaration contract + § Evaluation order | Same stop; excludes mid-run recovery rows per spec |
| Pre-branch explicit-list `/run-items` declaration stop | § Named stop reporting | Plan gap `explicit_list_invocation_targets=<t1>,<t2>,...` (verbatim, percent-encoded) |

**Examples (required in canonical doc)**: one worked example per profile for the
item layer; at minimum Native handoff `/run-item`, Parent orchestrated
`/run-item` under Remote Control, Inline fallback mutating `/run-item`, and
read-only `/run-work` under each profile label.

---

## Layer-by-Layer Changes

### Documentation — canonical

- [ ] `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`
      — new file: profiles (code + display labels), three layers (portfolio /
      epic / item), perform / hand off / prohibit matrix by layer, detection
      heuristics (declared not detected), absorbing context (contract + scope +
      handoff arrangement), parent-orchestrated stage handoff metadata,
      workflow_hub artifact/tracker/cleanup notes, inline-fix prohibition and
      delegation outcomes (#1746 out of scope), batch-context marker honesty
      (#1745 out of scope), worked examples, pointer precedence (role contract
      wins). Maps to AC1–AC8, AC10–AC11, AC17–AC20.

### Documentation — mirror surfaces

**Mirror content contract (applies to every command/skill mirror below).** A
link to the canonical doc plus a bare "declare a profile" sentence is **not
sufficient** — AC10, AC11 and AC20 require each mirror to state the decisions
themselves, because a constrained Cursor run may have only the mirror in
context. Every mirror in the three bullets that follow must state, in its own
words and not by pointer alone:

1. **Evaluation order (AC10)**: initial handoff is evaluated first;
   onward-handoff capability is evaluated **only once** initial handoff is
   confirmed available; a profile decision never evaluates onward-handoff
   capability before initial handoff is confirmed.
2. **Unconfirmed-handoff outcomes (AC10)** — **both** cases, stated separately:
   (a) onward-handoff capability that cannot be confirmed, once initial handoff
   is confirmed available, is treated as **unavailable** and declared
   **parent-orchestrated** as the conservative default until confirmed;
   (b) **initial handoff availability that itself cannot be confirmed** is
   treated the same as no handoff of any kind, declared
   **cursor-inline-fallback**, and the run stays **read-only** for the
   remainder of that run. A later confirmation never upgrades a run in place;
   the next run declares afresh.
3. **Exact named stop conditions (AC11)**, spelled verbatim:
   `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and
   the reused `missing_required_secret_or_permission` for a reachable stage role
   reporting a specific delegated action refused for a missing credential,
   GitHub permission, or access token. For **every** stop the mirror also states
   (a) the **affected work item** (including the single
   `explicit_list_invocation_targets=<t1>,<t2>,...` form for pre-branch
   explicit-list stops, targets verbatim and percent-encoded per the plan gap
   rule) and (b) the **concrete human unblocking action**. The
   mirror further states the **no-named-stop** treatment: a reachable stage
   role's harness tool or local file-path permission denial on a specific
   delegated action is **not** a named stop condition,
   `missing_required_secret_or_permission` does not apply to it, it is only
   observably similar to `SUBAGENT_PERMISSION_DENIAL` (which governs solely a
   Work Item Runner reporting to the Portfolio Orchestrator), and it is Out of
   Scope, tracked as #1746.
4. **Invalid-declaration boundaries (AC10, AC11, AC20)**: a profile value
   outside the three defined profiles, a declaration naming no accountable
   orchestrator role (including an empty value), a posture mismatched to the
   checkpoint, and a **coarse-fact mismatch in both directions** (more
   permissive and less permissive than the assigned outcome) each equal a
   missing declaration and stop with `dispatch_profile_declaration_missing`,
   reporting which part was invalid. The mirror also states the boundary: the
   coarse check governs the initial declaration and re-declarations of the
   coarse facts only, and does **not** govern the mid-run recovery transitions
   (delegation-failure unreachable-stage-role branch, parent-orchestrated to
   inline-fallback on stage-handoff loss, native-handoff mid-run-failure
   transitions), each of which stays a valid re-declaration.
5. **The three accountability postures (AC20)**: personally accountable
   (absorbed), handed off intact, and observing (not absorbed, not handed off).
   `observing` is valid **only** at a read-only checkpoint (a portfolio scan under
   any profile, or any command under inline-fallback before it stops or
   completes); a mutating action always declares absorbed or handed off. The
   required posture follows the run's **current** checkpoint, never its earlier
   mutation history. Both mismatches (`observing` at a mutating action;
   absorbed or handed off at a read-only checkpoint) and a declaration naming no
   role under any posture are missing declarations.

A mirror that carries the link and omits any of the five does not satisfy the
acceptance criteria, and the surface guard below must fail it.

The same contract applies, scoped to the layer each surface covers, to the
orchestration role documents (`orchestrator`, `item-orchestrator`, Codex
workflow skills), Protocols 90/91/95, `agent-model-config.md`, and
`.cursor/rules/workflow.mdc`. Each of those entries below must reference the
mirror content contract and carry the elements relevant to its layer (a
protocol states evaluation order and stop names at its declaration checkpoint;
a role document states the postures and unconfirmed-handoff outcome for its
layer; `workflow.mdc` states all five compactly).

- [ ] `.cursor/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — full mirror content contract above; `/run-work` additionally states
      scanning is read-only under every profile and that acting on scan results
      requires a **new bounded run with its own declaration**. Maps to AC9, AC10,
      AC11, AC12, AC18, AC20.
- [ ] `.claude/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — same parity as Cursor commands, including the full content contract and
      the `/run-work` AC12 scan posture. Maps to AC10, AC11, AC12, AC18, AC20.
- [ ] `.agents/skills/run-item/SKILL.md`, `run-item-work/SKILL.md`, `run-items/SKILL.md`, `run-epic/SKILL.md`,
      `run-work/SKILL.md` — same parity for Codex discovery path, including the
      full content contract, the deprecated `/run-item-work` alias, and the
      `/run-work` AC12 clause. Maps to AC10, AC11, AC12, AC18, AC20.
- [ ] `.cursor/agents/orchestrator.md` and `.claude/agents/orchestrator.md` —
      no-onward-handoff behavior: return to invoking context; no inline product
      work; profile declaration when absorbing portfolio layer; portfolio-layer
      mirror content (contract elements 1-5, in particular the three postures
      and the unconfirmed-handoff outcome). Maps to AC10, AC11, AC13, AC20.
- [ ] `.cursor/agents/item-orchestrator.md` and
      `.claude/agents/item-orchestrator.md` — same for item layer; clarify
      parent-orchestrated stage delegation vs `SUBAGENT_PERMISSION_DENIAL`
      (Work Item Runner only); item-layer mirror content (contract elements 1-5). Maps to
      AC10, AC11, AC13, AC19, AC20.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` — canonical-doc
      reference for the Codex item-orchestrator alias, plus the item-layer
      no-onward-handoff behavior mirrored from the agents above, including the item-layer mirror content
      contract. Maps to AC10, AC11, AC13, AC18, AC20.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` — **portfolio** layer for
      the Codex discovery path, matching `.cursor/agents/orchestrator.md` and
      `.claude/agents/orchestrator.md`. Required because a Codex user can enter
      portfolio orchestration through this canonical skill directly; omitting it
      would leave that entrypoint with no dispatch-profile declaration contract
      while the plan claims coverage of every orchestration-role entrypoint.
      Carries the portfolio-layer mirror content contract. Maps to AC10, AC11,
      AC13, AC18, AC20.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — reference canonical doc when establishing execution arrangement;
      explicit-list declaration checkpoint; pre-branch affected-item string;
      parent-orchestrated Step 4 fallback cross-reference; mirror content contract
      elements 1-5 at the declaration checkpoint (evaluation order, unconfirmed
      outcomes, exact stop names, invalid cases, postures). Maps to AC5, AC10,
      AC11, AC14, AC17, AC20, plan gap resolution.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — reference at execution arrangement; declaration before first mutation;
      parent-orchestrated item-runner obligations; run summary fields (profile,
      transitions, absorbed layers, stage handoffs); mirror content contract elements 1-5 at the declaration
      checkpoint. Maps to AC5, AC9, AC10, AC11, AC14, AC20.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      — same reference for epic layer entry, with mirror content contract elements
      1-5. Maps to AC5, AC10, AC11, AC14, AC20.
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — Cursor
      environment × orchestration-layer table carrying **three** values per
      combination, per AC15: (a) the applicable profile, (b) the applicable
      **model assignment**, and (c) whether that assignment is confirmed by
      observation or an explicit assumption. The exact values are fixed in
      Decision 6 (Desktop: role's own model; Remote Control and Cloud Agents:
      `economy` floor for portfolio, `balanced` floor for epic and item, with
      Cloud Agents an explicit assumption for both profile and model);
      implementation copies them, it does not choose them. The model assignment is not
      optional and is not covered by the existing role-level model table, which
      does not say which assignment an **absorbing current context** uses under
      parent-orchestrated Remote Control or under Cloud Agents — both
      combinations must be answered explicitly. Maps to AC15.
- [ ] `.cursor/rules/workflow.mdc` — profile declaration requirement + canonical
      link + compact mirror content contract (elements 1-5). Maps to AC10, AC11,
      AC16, AC20.
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` section 4 —
      add `dispatch_profile_declaration_missing` and
      `dispatch_handoff_unavailable`. Each stop message must name (a) the stop
      condition string, (b) the affected work item, and (c) the human action to
      unblock: for `dispatch_profile_declaration_missing`, declare one of
      `cursor-native-handoff`, `cursor-parent-orchestrated`, or
      `cursor-inline-fallback` in the run preamble and re-invoke the bounded
      command; for `dispatch_handoff_unavailable`, either switch to a profile
      whose next layer is available or restore the handoff target, then
      re-invoke. Extend `dispatch_profile_declaration_missing` affected-item
      text for `explicit_list_invocation_targets=<t1>,<t2>,...` (verbatim,
      percent-encoded serialization, all accepted target forms); document reuse of
      `missing_required_secret_or_permission` for reachable stage credential
      denial. Maps to AC10–AC11, AC19.
- [ ] `docs/workflow/development-workflow/README.md` — add integration doc to
      integrations list. Maps to discoverability (AC17).
- [ ] `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md`
      — update Named Stop-Condition Mapping affected-item row for pre-branch
      explicit-list stops per plan gap resolution (spec already merged; align
      text with implementation). Maps to plan gap + AC10.

### Documentation — optional clarity

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — one paragraph
      on ordering: prelude read-only work may precede declaration; declaration
      still required before first mutation. Maps to Decision 4.

### Workflow tooling / tests

- [ ] `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`
      (**plan-added**; not named in the merged spec) — regression guard with
      **three independent check branches** over the mirror surfaces (bounded
      command adapters, deprecated `run-item-work` aliases, orchestration role
      agents and Codex workflow skills, protocols 90/91/95,
      `agent-model-config.md`, `workflow.mdc`):
      1. **Link branch**: the surface links to
         `integrations/cursor-dispatch-profiles.md`.
      2. **Profile-string branch**: the surface names the profile code values
         it is required to carry (`cursor-native-handoff`,
         `cursor-parent-orchestrated`, `cursor-inline-fallback`).
      3. **Mirror-content branch (one assertion per contract clause)**: every
         clause in **Mirror content contract** must be present, each checked
         by its own assertion so a failure names the missing clause ID.
         Per-clause required tokens (all fixed strings, matched by the scanner
         rules in **Parser-risk addendum**):
         - E1 evaluation order: `initial handoff`,
           `only once initial handoff is confirmed`, and
           `never evaluates onward-handoff capability before initial handoff`.
         - E2a onward unconfirmed: `treated as unavailable` and
           `cursor-parent-orchestrated` in the same paragraph as
           `conservative default`.
         - E2b **initial handoff unconfirmed**: `initial handoff availability
           that itself cannot be confirmed` (or the fixed synonym recorded in
           the token list), `cursor-inline-fallback`, and `read-only` in the
           same paragraph, plus `never upgrades a run in place`.
         - E3a stop names: `dispatch_profile_declaration_missing`,
           `dispatch_handoff_unavailable`, and
           `missing_required_secret_or_permission`.
         - E3b **affected work item**: `affected work item`, and on the
           surfaces the table assigns it to, `explicit_list_invocation_targets=`, and on
           the surfaces that carry that token the serialization tokens
           `verbatim` and `percent-encoded`.
         - E3c **human unblocking action**: `human unblocking action` (or the
           fixed synonym), and, per stop, the action token from the canonical
           doc for each of the three stops (`declare one of` for
           `dispatch_profile_declaration_missing`, `restore the handoff target`
           for `dispatch_handoff_unavailable`, `supply the missing credential`
           for `missing_required_secret_or_permission`).
         - E3d **no-named-stop denial treatment**: `is not a named stop
           condition`, `SUBAGENT_PERMISSION_DENIAL`, `observably similar`,
           and `#1746` in the same paragraph.
         - E4a invalid values: `invalid profile`, `invalid accountable role`,
           `invalid posture`.
         - E4b coarse-fact mismatch both directions: `coarse-fact mismatch`,
           `more permissive`, and `less permissive`.
         - E4c boundary exemption: `mid-run recovery` and `does not govern`.
         - E5 postures: `personally accountable`, `handed off intact`,
           `observing`, `only at a read-only checkpoint`, and `current
           checkpoint`.
         Which clauses a surface class must carry is a table inside the
         script (rows are surface classes, columns are clauses), fixed as:

         | Surface class | E1 | E2a | E2b | E3a | E3b | E3c | E3d | E4a | E4b | E4c | E5 |
         | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
         | Command / skill mirrors (15) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | Role agents (4) and Codex workflow skills (2) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | Protocols 90, 91, 95 | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | `.cursor/rules/workflow.mdc` | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | `guardrails-enforcement.md` section 4 | - | - | - | Y | Y | Y | Y | Y | Y | - | - |
         | `agent-model-config.md` | profile and model-assignment rows for all three environments only | | | | | | | | | | |

         Layer scoping is by wording, not by omission: a portfolio-layer
         surface states the clause for the portfolio layer and an item-layer
         surface for the item layer, but every clause token must be present.
         E3b's `explicit_list_invocation_targets=` token is required on
         Protocol 90, `run-items` mirrors, and guardrails only; the generic
         `affected work item` token is required everywhere E3b is `Y`.
         Exact phrases live in one shared token list at the top of the script so
         canonical wording changes touch one place.
      **Script conventions (REVIEW.md shell checks, ShellCheck-clean)**: validate
      option values before `shift`; emit structured errors consistent with the
      script's output contract (failing clause ID, surface path, expectation);
      validate any path argument against the known surface list before reading;
      no `|| true` masking of `grep`/`git` failures the caller needs; file mode
      executable like sibling `test-*.sh`. Fixtures are `.md` only (never `.sh`)
      so the ShellCheck find over `scripts/development-workflow` does not pick
      them up, and they sit outside the markdownlint globs by design because
      fail fixtures intentionally violate content rules.
      Rationale: AC18 mirror parity is easy to break across 15+ surfaces and a
      link alone does not satisfy AC10/AC11/AC20; a cheap shell guard catches
      drift without requiring live Cursor Remote Control. Maps to AC10, AC11,
      AC18, AC20 regression safety.
- [ ] **Executable path simulation** (same test file, branch
      `simulate_bounded_paths`; supports smoke Steps 12-14). For each bounded
      path (`/run-item`, `/run-items` explicit list, `/run-epic`) the guard
      replays a table of declaration scenarios (native handoff, parent
      orchestrated, inline fallback with read-only checkpoint, missing
      declaration, invalid profile, posture mismatch) against the decision-gate
      rows in the canonical doc and guardrails section 4, asserting the terminal
      outcome (declared-and-proceed, `dispatch_handoff_unavailable`,
      `dispatch_profile_declaration_missing`, or absorbed re-declaration) and,
      for the pre-branch explicit-list case, the single
      `explicit_list_invocation_targets=<t1>,<t2>,...` affected-item string, over
      a mixed-form target list (issue number with and without `#`, tracker ID,
      branch name containing `,`, PR number). This
      is the executable equivalent when live Remote Control is unavailable.
- [ ] **Planted-violation proofs — one per guard branch** (same implementation
      PR). Each branch can go inert while the others keep the suite green, so
      every branch needs its own proof. For each cycle: apply the edit to a
      mirror, run the guard and confirm non-zero exit **and that the failure
      message names that branch/element**, restore, confirm exit 0. Keep every
      other branch intact in each cycle so a non-zero exit proves the targeted
      check fired.
      1. **Link branch**: remove the canonical link from
         `.cursor/commands/run-item.md`.
      2. **Profile-string branch**: corrupt one profile code string in a mirror
         whose link is intact.
      3. **E1 evaluation order**: delete the `only once initial handoff is
         confirmed` sentence from `.claude/commands/run-items.md`.
      4. **E2a onward unconfirmed**: delete the `conservative default` sentence
         from `.agents/skills/run-epic/SKILL.md`.
      5. **E2b initial handoff unconfirmed**: delete the sentence stating that
         unconfirmed initial handoff selects read-only `cursor-inline-fallback`
         from `.cursor/commands/run-item.md` while leaving E2a intact (proves
         E2b is checked independently of E2a); repeat on
         `.cursor/rules/workflow.mdc`.
      6. **E3a stop names**: remove `missing_required_secret_or_permission`
         from `.cursor/commands/run-work.md`; repeat removing
         `dispatch_handoff_unavailable` from Protocol 91.
      7. **E3b affected work item**: remove `explicit_list_invocation_targets=`
         from Protocol 90 (and `guardrails-enforcement.md` row text) while the
         stop names remain.
         Separately remove only the `percent-encoded` token (then only
         `verbatim`) from Protocol 90 and from `run-items` mirrors.
      8. **E3c human unblocking action**: remove the unblocking action for
         `dispatch_handoff_unavailable` only, from `.claude/commands/run-item.md`,
         while its name and the other two actions remain (proves per-stop
         checking).
      9. **E3d no-named-stop denial treatment**: remove the harness/local-path
         denial paragraph from `.cursor/agents/item-orchestrator.md`, and
         separately remove only the `#1746` token from it.
      10. **E4a/E4b/E4c invalid boundaries**: delete the `coarse-fact mismatch`
          sentence from `.cursor/rules/workflow.mdc`; delete only the
          `less permissive` direction from `.claude/commands/run-epic.md`;
          delete the mid-run-recovery exemption from
          `.agents/skills/run-item/SKILL.md`.
      11. **E5 postures**: delete the `observing` posture line (and,
          separately, the `only at a read-only checkpoint` qualifier, and
          separately the `current checkpoint` sentence) from
          `.cursor/commands/run-item.md`.
      12. **Guardrails clause coverage**: in `guardrails-enforcement.md`
          section 4, separately remove each of E3b, E3d, and the `more
          permissive` direction of E4b, leaving the stop names.
      13. **Protocol E3d**: remove the harness/local-path denial paragraph from
          each of Protocols 90, 91, and 95 in turn (three cycles), leaving the
          stop names, E3b and E3c.
      14. **`agent-model-config.md` rows**: remove one environment row (and,
          separately, the model-assignment cell of one row); expect non-zero.
      15. **Canonical-doc checks**: one cycle per check name in Testing Strategy
          (`canonical_layers`, `canonical_matrix`,
          `canonical_declared_not_detected`, one per
          `canonical_handoff_metadata` field including worktree path,
          `canonical_workflow_hub`).
      16. **`simulate_bounded_paths`**: alter one decision-gate row in the
          canonical doc so a scenario's expected outcome changes; expect
          non-zero naming the path (`/run-item`, `/run-items`, or `/run-epic`).

      17. **Selector wiring / header consistency**: remove one path from the
          `# covers:` header; expect the guard's header-consistency check to
          fail and the selector verification (step 3 of Testing Strategy) to
          show the suite unselected for that path; restore.

      **Coverage rules (every branch must have a real cycle).** Each multi-token
      clause is proved token by token: one cycle deletes only one token while
      the rest of the clause remains. Each of cycles 3-11 is repeated once per
      surface class in the table above that carries the clause (command / skill
      mirror, role agent or Codex skill, protocol, `workflow.mdc`), using a
      representative surface of that class; the named surface above is one such
      representative, not the only one. Guardrails classes are covered by cycle
      12. The PR test plan records the resulting clause-by-class matrix with
      the before/after command output of **every** cycle (non-zero exit naming
      the branch or clause, then restore and exit 0). There is no substitute
      for an actual fail/pass cycle: a guard branch that cannot be proved by
      one is **removed from the guard** in the implementation PR rather than
      shipped unproved, and the plan's coverage table is updated to match.

### Database / Backend / Frontend / Infrastructure

- [ ] Not applicable — documentation and a doc-surface test only.

---

## Files to modify (implementation checklist)

Adapter/skill documentation mirrors to edit: **15** paths (5 `.cursor/commands` +
5 `.claude/commands` + 5 `.agents/skills/*/SKILL.md`). The Verification Log `rg`
returns **18** hits = **14** of those mirrors (it misses `.claude/commands/run-epic.md`)
+ **4** `agents/openai.yaml` files that are **not** edited (`14+4=18`).

| Path | Change |
| --- | --- |
| `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` | **Create** canonical guide |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Add stop conditions + affected-item guidance |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Reference + declaration gate + explicit-list stop |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Reference + declaration + summary fields |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Reference + declaration |
| `docs/workflow/development-workflow/agent-model-config.md` | Cursor profile table |
| `docs/workflow/development-workflow/bounded-run-prelude.md` | Optional ordering note |
| `docs/workflow/development-workflow/README.md` | Integrations list entry |
| `.cursor/commands/run-item.md` | Mirror |
| `.cursor/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.cursor/commands/run-items.md` | Mirror |
| `.cursor/commands/run-epic.md` | Mirror |
| `.cursor/commands/run-work.md` | Mirror |
| `.claude/commands/run-item.md` | Mirror |
| `.claude/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.claude/commands/run-items.md` | Mirror |
| `.claude/commands/run-epic.md` | Mirror |
| `.claude/commands/run-work.md` | Mirror |
| `.agents/skills/run-item/SKILL.md` | Mirror |
| `.agents/skills/run-item-work/SKILL.md` | Mirror (deprecated alias) |
| `.agents/skills/run-items/SKILL.md` | Mirror |
| `.agents/skills/run-epic/SKILL.md` | Mirror |
| `.agents/skills/run-work/SKILL.md` | Mirror |
| `.cursor/agents/orchestrator.md` | No-handoff + profile |
| `.cursor/agents/item-orchestrator.md` | No-handoff + profile |
| `.claude/agents/orchestrator.md` | Parity |
| `.claude/agents/item-orchestrator.md` | Parity |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Canonical reference + item-layer no-onward-handoff |
| `.codex/skills/workflow-orchestrator/SKILL.md` | Canonical reference + portfolio-layer no-onward-handoff |
| `.cursor/rules/workflow.mdc` | Requirement + link |
| `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md` | Named stop affected-item alignment |
| `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` | **Create** surface guard (link, profile string, clauses E1-E5, canonical-doc checks, path simulation, `--self-test`) with `# covers:` header for every protected surface |
| `scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/` | **Create** scanner self-test fixtures (one per Parser-Risk case) |
| `changelog.d/1462.added.cursor-dispatch-profiles.md` | **Create** release-note fragment (implementation PR only) |
| `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` | Created in Plan Ready; Steps 12-14 and tightened Pass criteria added in plan review (no further edit expected) |

**Explicitly not in scope**: `REVIEW.md` checklist categories (no new review
gate category); `--dispatch-profile` CLI flag (BO-9); automated environment
detection; stage-role permission denial recovery (#1746); enforcing
`BATCH_CONTEXT` marker absence as a stage stop (#1745).

---

## Parser-Risk Addendum (surface-guard scanner)

The surface guard is a structured-Markdown scanner: it reads Markdown files,
extracts scoped content, and decides pass/fail by fixed-string and same-paragraph
matches. Scanner rules: (R1) read UTF-8 text; (R2) strip fenced code blocks and
HTML comments before matching (the Decision 3 declaration block and worked
examples are illustrative and must not satisfy a clause). Fence semantics
follow CommonMark: an opening fence is a run of **3 or more** backticks or of
**3 or more** tildes, preceded by **at most 3 spaces** of indentation (4+
spaces is an indented code block or list continuation, not a fence; a fence
inside a list item may be indented relative to that item's content); a
backtick fence's info string may not contain a backtick. The closing fence
must use the **same character** as the opener, be a run **at least as long**
as the opener (longer closers are valid), be indented at most 3 spaces, and
carry no info string. A fence of the other character, or a shorter run, is
content, not a closer. An **unclosed** fence runs to **end of file** and
everything after the opener is stripped. HTML comments run from `<!--` to
`-->`, or to end of file if unclosed; (R3) normalize each
paragraph by joining soft-wrapped lines and collapsing whitespace, so phrases
wrapped across lines still match and "same paragraph" means one blank-line-
delimited block (list item, blockquote line and table cell each count as a
block); (R4) identifier tokens (stop names, profile codes) match only with
non-identifier characters or edges on both sides; prose phrases match
case-sensitively as fixed strings; (R5) every assertion runs on the surface's
own content, never a concatenation of files.

Each case below maps to a fixture under
`scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/`
and to a self-test (`test-cursor-dispatch-profile-surfaces.sh --self-test`,
also invoked by the default run). Each fail fixture must exit non-zero with a
message naming its clause ID; each pass fixture must exit 0. These are separate
from, and in addition to, the planted-deletion proofs on real surfaces.

| Class | Case | Fixture ID | Expected |
| --- | --- | --- | --- |
| Boundary | Token at first byte / last byte of file, no trailing newline | `boundary-edge-token` | pass |
| Boundary | Required phrase soft-wrapped across two lines | `boundary-wrapped-phrase` | pass (R3) |
| Boundary | Token followed by punctuation or backtick (`` `dispatch_handoff_unavailable`, ``) | `boundary-punct-token` | pass |
| Boundary | Empty file / file with only the link | `boundary-empty-surface` | fail, all clauses named |
| Negative / lookalike | Longer identifier (`dispatch_handoff_unavailable_x`, `cursor-native-handoffs`) | `lookalike-longer-identifier` | fail (R4) |
| Negative / lookalike | Wrong case (`Observing`, `DISPATCH_HANDOFF_UNAVAILABLE`) | `lookalike-case` | fail |
| Negative / lookalike | Required token only inside a fenced code block or HTML comment | `lookalike-fenced-or-comment` | fail (R2) |
| Negative / lookalike | `observing` only as an unrelated word (`observing the output`) without posture phrase | `lookalike-observing-word` | fail (E5 phrase tokens missing) |
| Negative / lookalike | E2b tokens present but in different paragraphs (read-only in one, inline-fallback in another) | `lookalike-split-paragraph` | fail (R3 same-paragraph) |
| Multiple occurrence | Token appears many times; only one clause satisfied | `multi-token-many` | pass for that clause, fail for the unmet one |
| Multiple occurrence | Token satisfied in surface A, absent from surface B | `multi-cross-surface` | fail for B (R5) |
| Multiple occurrence | Two of three stop actions present, one missing | `multi-partial-actions` | fail (E3c per stop) |
| Multiple occurrence | Duplicate canonical link lines | `multi-duplicate-link` | pass |
| Nested / overlap | Clause inside list item, blockquote, and table cell | `nested-block-kinds` | pass |
| Nested / overlap | Required phrase inside a fenced block nested in a list item | `nested-fenced-in-list` | fail (R2) |
| Fence semantics | Required token only inside a tilde (`~~~`) fence | `fence-tilde` | fail (R2) |
| Fence semantics | Tilde fence closed by a longer tilde run; token after the closer | `fence-tilde-longer-closer` | pass (token after closer counts) |
| Fence semantics | Backtick fence (3) closed by a longer backtick run (5); token after closer | `fence-backtick-longer-closer` | pass |
| Fence semantics | 4-backtick opener; inner 3-backtick line does not close; token after inner line still inside | `fence-shorter-closer-inside` | fail (token stripped, R2) |
| Fence semantics | Backtick fence closed by a tilde run (mismatched character); token after it still inside | `fence-mismatched-char-closer` | fail (R2) |
| Fence semantics | Unclosed fence at EOF with required token after opener | `fence-unclosed-eof` | fail (stripped to EOF) |
| Fence semantics | Unclosed fence at EOF, required token **before** the opener | `fence-unclosed-token-before` | pass |
| Fence semantics | Fence opener indented 3 spaces (is a fence) vs 4 spaces (is not) with token inside | `fence-indent-3` / `fence-indent-4` | fail / pass (4 spaces is not a fence, so the token counts) |
| Fence semantics | Closer indented 4 spaces does not close; token after it still inside | `fence-closer-indent-4` | fail (R2) |
| Fence semantics | Unclosed HTML comment at EOF with token after `<!--` | `comment-unclosed-eof` | fail (R2) |
| Nested / overlap | Overlapping phrases (`initial handoff` inside `only once initial handoff is confirmed`) with only the shorter present | `overlap-substring` | fail for the longer clause |
| Nested / overlap | E2a and E2b sentences sharing `cursor-parent-orchestrated` / `cursor-inline-fallback` tokens; one deleted | `overlap-e2a-e2b` | fail for the deleted clause only |
| Serialization | Mixed-form target list (`#1462`, `ENG-123`, `feature/x`, `1771`) shown verbatim | `serialization-mixed-forms` | pass |
| Serialization | Example rewrites targets (adds `#` to `ENG-123` or strips `#`) | `serialization-hash-rewritten` | fail (contradicts `verbatim`) |
| Serialization | Target containing `,` shown unescaped | `serialization-comma-unescaped` | fail (`percent-encoded` rule) |
| Surface-class table | Protocol fixture lacking only E3d (all other clauses present) | `class-protocol-missing-e3d` | fail naming E3d |
| Surface-class table | Guardrails fixture carrying only its `Y` clauses (no E1, E2, E4c, E5) | `class-guardrails-exempt-clauses` | pass (absent `-` clauses are not required) |
| Surface-class table | Guardrails fixture lacking E4b `less permissive` direction | `class-guardrails-missing-e4b` | fail naming E4b |
| Surface-class table | `agent-model-config.md` fixture missing one environment row | `class-model-config-missing-row` | fail |

Fixture-only self-tests are the regression net for the scanner itself; if a
fixture is removed the self-test count assertion (expected N fixtures) fails.

---

## Testing Strategy

**Test types**: Shell surface guard, markdown lint, manual smoke (documentation).

**Key scenarios**:

1. Every mirror surface links to `cursor-dispatch-profiles.md`, names the three
   profile code values consistently (AC18), and carries each required
   mirror-content element E1-E5 (AC10, AC11, AC20); each element has a
   planted-violation proof.
2. Guardrails section 4 lists both new stop conditions with definitions matching
   the spec matrix (AC10–AC12), including coarse-facts mismatch rejection in both
   directions (more and less permissive than assigned outcome).
3. Orchestration role agents instruct return-to-invoker when onward handoff is
   unavailable (AC13).
4. Agent-model-config states, for each Cursor environment and layer, the
   profile, the model assignment (Decision 6 values), and confirmed vs
   assumption (AC15).
5. Smoke runbook walks Native handoff desktop, Parent orchestrated Remote
   Control, Inline fallback, and read-only scan paths (AC6, AC17), and Steps
   12-14 require current-head evidence (live run or `simulate_bounded_paths`)
   for `/run-item`, `/run-items`, and `/run-epic` (AC9, AC10, AC14, AC17).
6. Smoke Step 10 (AC19): parent-orchestrated inline-product-work prohibition is
   not relaxed by any other document; #1746 remains Out of Scope;
   `SUBAGENT_PERMISSION_DENIAL` is worded as observably similar only (Work Item
   Runner boundary).
7. Smoke Step 11 (AC20): three accountability postures are defined; `observing`
   is valid only at read-only checkpoints; posture mismatch is treated as a
   missing declaration.

**Canonical-document coverage for AC2, AC3, AC5, AC7, AC8**: the surface guard
gains a canonical-doc branch, and each requirement has a named check that
fails when unmet (each with a planted-violation cycle: delete the section,
confirm non-zero exit naming the check, restore):

| AC | Check name in guard | Fails when the canonical doc lacks |
| --- | --- | --- |
| AC2 | `canonical_layers` | the three layer headings (portfolio, epic, item) each stating governing contract, entering commands, and constrained-environment behavior |
| AC3 | `canonical_matrix` | the perform / hand off / prohibit matrix with one row per layer, each row linking a role contract or protocol |
| AC5 | `canonical_declared_not_detected` | the decision-indicator list and the sentence that the decision is declared rather than automatically detected |
| AC7 | `canonical_handoff_metadata` | one assertion per handoff field, failing if any is absent (each field gets a planted-violation cycle, including worktree path): `BATCH_CONTEXT`, isolation classification (`isolation`), **expected worktree path** (spec AC7 and Protocol 91 isolation handoff), expected branch, approved base, artifact repository root, mutation class |
| AC8 | `canonical_workflow_hub` | the workflow_hub artifact-ownership, tracker, and post-merge cleanup notes |

Smoke Step coverage remains the human-facing check for the same ACs.

**Smoke test runbook**:
`docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md`

**Regression suite and CI wiring**: Add
`scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`.
File discovery alone is **not** sufficient. `.github/workflows/workflow-tests.yml`
is deliberately not path-filtered, and `select-test-suites.sh` decides which
suites a PR runs: a suite with no `# covers:` header covers only
`scripts/development-workflow/<name>.sh` / `.py` by naming convention (plus its
own file and fixture directory). This suite guards docs, commands, skills,
agents, protocols and a rule file, so it is a cross-cutting suite and **must
declare** what it covers, within the first `COVERS_HEADER_LINES` (60) lines of
the file, one `# covers:` line per group:

```text
# covers: .cursor/commands/run-item.md .cursor/commands/run-item-work.md .cursor/commands/run-items.md .cursor/commands/run-epic.md .cursor/commands/run-work.md
# covers: .claude/commands/run-item.md .claude/commands/run-item-work.md .claude/commands/run-items.md .claude/commands/run-epic.md .claude/commands/run-work.md
# covers: .agents/skills/run-item/SKILL.md .agents/skills/run-item-work/SKILL.md .agents/skills/run-items/SKILL.md .agents/skills/run-epic/SKILL.md .agents/skills/run-work/SKILL.md
# covers: .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md
# covers: .codex/skills/workflow-orchestrator/SKILL.md .codex/skills/workflow-item-orchestrator/SKILL.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md docs/workflow/development-workflow/agent-model-config.md
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md .cursor/rules/workflow.mdc
# covers: docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md
```

Every path the guard reads must be listed, so the header and the guard's
surface table are kept in step by a header-consistency check inside the guard
(each surface path in its table must appear in a `# covers:` line, and vice
versa). Other CI-wiring assumptions checked in this plan:

- **Path filters**: `workflow-tests.yml` has no `paths:` filter (selector only);
  no workflow edit is needed. `markdown-lint.yml` is path-filtered but the
  plan/smoke/changelog `.md` files are already inside its globs; fixtures are
  intentionally outside them.
- **Registration**: none in the workflow file; the `# covers:` header is the
  registration, verified below.
- **Time budget**: each suite is capped by `SUITE_TIMEOUT_SECONDS` (600s) inside
  a shard, and the guard runs `--self-test` over the whole fixture set every
  time; the guard must complete in well under that cap (target under 60s, no
  network, no `gh`). The manual planted-violation cycles are not part of the CI
  suite run.
- **Selector verification (implementation-time, planted check)**:
  1. `select-test-suites.sh --print-map` lists this suite against every path in
     the header above (assert one row per protected path).
  2. For each protected surface, write that single path to a temp changed-files
     list and run `select-test-suites.sh --changed-files <list>`; confirm the
     output contains `test-cursor-dispatch-profile-surfaces.sh`. This is the
     planted check: a touched mirror path must select the suite.
  3. Remove one `# covers:` path from the header, rerun step 2 for that path,
     confirm the suite is **not** selected (proves the check is live), restore.
  4. `select-test-suites.sh --report-gaps` shows no gap for this suite (it is
     selectable by a PR change set).
  5. Run `bash scripts/development-workflow/tests/test-select-test-suites.sh`
     to confirm the selector suite still passes with the new header.

---

## Seed Data

Not applicable — no runtime data.

---

## Documentation Updates (post-implementation, developer checklist)

- [ ] `changelog.d/1462.added.cursor-dispatch-profiles.md` — **plan-added
      release-note fragment; traces to no AC**. Rationale: repository
      convention (`AGENTS.md` CHANGELOG & Versioning) requires a
      `changelog.d/` fragment for feature PRs, and Prepare Release assembles
      those fragments. It is a process addition, not a scope expansion.
      Implementation PR only; body:
      `- **Cursor dispatch profiles** (#1462): Document native-handoff, parent-orchestrated, and inline-fallback profiles for Cursor bounded commands with consistent declaration gates and named stop conditions.`
      Do **not** edit `CHANGELOG.md` directly in the implementation PR.
- [ ] `AGENTS.md` — optional one-line link under Key Documentation to
      `integrations/cursor-dispatch-profiles.md` if the workflow table is updated
      for discoverability (recommended, not strictly required by AC).

---

## Document Quality Gate (plan stage)

| Check | Result | Notes |
| --- | --- | --- |
| Evidence currency | Pass | Verification Log re-run `2026-09-20` at verified head `4095718b`; its child commit changes only the log and these gate lines. Implementation-time checks are marked Deferred, not Pass; the `develop` ancestry check is recorded as failing now and deferred to implementation start |
| Spec coverage | Pass | Plan maps to AC1–AC20 via layer checklist; BO-9/BO-10 deferred per spec |
| Implementation-order consistency | Pass | Canonical doc before mirrors; guardrails before surface guard |
| Verification support | Pass (plan-stage design; execution deferred) | Verification Log + surface guard (link, profile string, E1-E5 clauses, canonical-doc checks, fixtures) + per-branch planted-violation proofs + smoke runbook |
| Decision-gate applicability | Pass | Complex gate — authoritative spec matrix + implementation mapping table |
| CI wiring | Pass (design; execution deferred) | `# covers:` header for every protected surface, selector planted check and `--report-gaps`, per-suite time cap, no path filter change; see Testing Strategy |
| Shell-script lint | Pass (design; execution deferred) | New `.sh` verified by `bash -n`, `shellcheck --severity=warning`, and `workflow-shell-guard-lint.py --base-ref origin/develop` per REVIEW.md; Implementation Order step 9 |
| Parser-risk addendum | Pass | Surface guard is a structured-Markdown scanner; boundary, lookalike, multiple-occurrence and nested/overlap cases each mapped to a fixture and self-test (see Parser-Risk Addendum) |
| Concurrent-event-source addendum | N/A | No concurrent event handlers |
| Cross-cutting checklist addendum | N/A | No new REVIEW.md checklist category |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surfaces drift from canonical doc | High | High | Surface guard test + smoke runbook cross-check |
| Operators confuse prelude with declaration | Medium | Medium | bounded-run-prelude ordering note + examples |
| Restating role contracts causes drift | Medium | High | Matrix links to protocols/agents only (spec Out of Scope 4) |
| Batch explicit-list stop wording inconsistent | Medium | Medium | Plan gap decision + spec row update in same PR |
| Conflicts with #1745 / #1746 scope creep | Medium | High | Explicit out-of-scope callouts in canonical doc |

---

## Implementation Order

1. **Canonical doc** — create `integrations/cursor-dispatch-profiles.md` with
   full matrix, examples, and gap references (#1745, #1746). Commit.
2. **Guardrails** — add named stop conditions and pre-branch affected-item text.
   Commit.
3. **Protocols 90, 91, 95** — reference canonical doc at execution
   arrangement; add declaration checkpoints and summary fields. Commit.
4. **Command + skill mirrors** — Cursor, Claude, Codex `.agents/skills` adapters.
   Commit.
5. **Role agents** — orchestrator + item-orchestrator (Cursor + Claude), plus
   both Codex workflow skills: `.codex/skills/workflow-orchestrator/SKILL.md`
   (portfolio entrypoint) and `.codex/skills/workflow-item-orchestrator/SKILL.md`
   (item entrypoint), each carrying its layer's mirror content contract
   (AC10, AC11, AC13, AC18, AC20). Commit.
6. **agent-model-config + workflow rule + README + optional bounded-prelude** —
   Commit.
7. **Spec alignment** — update merged spec Named Stop-Condition Mapping row for
   explicit-list affected item. Commit. **Order note / reversal risk**: do not
   run this before step 2 (guardrails) or before the plan-gap wording is stable
   in the canonical doc (step 1). Reversing step 7 ahead of guardrails risks
   shipping a merged-spec row that disagrees with section 4 stop text, or
   rewriting the spec twice when guardrail wording settles. Spec alignment may
   land in the same commit as guardrails if both use the identical
   `explicit_list_invocation_targets=...` string; otherwise keep this after
   step 2.
8. **Surface guard test** — add the shell guard (link, profile-string, E1-E5
   clause, canonical-doc, and `simulate_bounded_paths` branches), the scanner
   fixtures directory with one fixture per Parser-Risk case (including the
   fence-semantics rows), and the `--self-test` mode; with the `# covers:` header
   declared (Testing Strategy: discovery alone does not wire it into PR suite
   selection) and the selector verification run. Run locally. Commit.
9. **Verify** — run every repo lint that applies to the files the PR adds:
   markdown lint commands from `AGENTS.md` (`npx markdownlint-cli2` over
   specs, testing runbook, and `changelog.d`; `markdown-heuristic-lint.py`;
   `check-changelog-duplicate-headers.sh` only if `CHANGELOG.md` changed),
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
   (protocol/mirror `.md` edits), and for the new shell script
   `bash -n`, `shellcheck --severity=warning`, and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   (also run `bash scripts/lint/tests/test-workflow-shell-guard-lint.sh`
   when the guard linter's inputs change), then run the selector verification
   (`--print-map`, per-surface `--changed-files` planted check,
   `--report-gaps`, `test-select-test-suites.sh`), then run the surface guard, run
   the scanner `--self-test`, and execute the smoke runbook: Steps 1-6 and
   10-14 must PASS at the implementation head (Steps 12-14 via live run or
   `simulate_bounded_paths`); only live Steps 7-9 may be documented NOT RUN,
   per the runbook's Pass criteria.
10. **Changelog fragment** — create `changelog.d/1462.added.cursor-dispatch-profiles.md`
      with the literal bullet from **Documentation Updates** (implementation PR only).
11. **Planted-violation proofs** — run every fail/pass cycle (link, profile
      string, E1-E5 clauses, and canonical-doc checks) plus the scanner self-tests documented in
      **Layer-by-Layer Changes → Workflow tooling** and **Testing Strategy**.

---

## Reversal / Rollback

The change publishes a workflow contract (declaration gate, two new named stop
conditions) across many mirror surfaces. It is documentation-only with no data
or runtime state, so reversal is a plain `git revert` of the implementation PR
merge commit (or of its per-step commits in reverse order, keeping the
step 2 / step 7 ordering constraint). Consequences to note in the revert PR:
runs started during the window may have emitted declaration blocks and stop
names that no longer exist; those are informational text in past run output and
need no cleanup. If only the surface guard is faulty, revert or fix the script
alone; docs stand independently. Partial reversal of the guardrails stop
conditions without the mirrors leaves mirrors naming unknown stops, so revert
guardrails and mirrors together.

---

## Cross-Cutting Operational Assumption Records (for implementer)

| ID | Assumption | Authoritative source | Implementation-start check |
| --- | --- | --- | --- |
| A1 | Artifact base branch remains `develop` | `.ai-dev-workflow.yaml` / handoff | `git merge-base --is-ancestor origin/develop HEAD` |
| A2 | `single_repo` — hub owns all artifacts | Batch handoff | No product-repo selector required |
| A3 | Pre-branch explicit-list affected item format | This plan § Plan-Stage Gap Resolution | Still valid if canonical + guardrails rows match |

Implementer must record `Still valid` or `Stale or conflicting` before file
edits per Protocol 03 assumption check.
