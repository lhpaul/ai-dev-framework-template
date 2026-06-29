# Implementation Plan: Orchestration Command Finalization (#1075)

**Spec**: `1_1075-orchestration-command-finalization_specs.md`
**Epic**: #1072 Finalize orchestration commands
**Branch convention**: `feature/1075-orchestration-command-finalization`

---

## Complexity

**Medium** — primarily text/documentation changes across command files, skill files, protocol
documents, and one shell script. No new runtime dependencies. No database or API changes.

---

## Dependencies

- Epic #1047 (Refactor orchestration commands) graduated to `develop` ✓
- Spec #1048 already in force — this plan builds on its decisions

---

## Template-Fit Check

Passes. This spec improves the workflow tooling and protocol documents that the template itself
ships. All changes are framework-agnostic; no stack-specific references.

---

## Implementation Order

Changes are ordered from inner-most (script, protocol) to outer-most (command/skill surfaces,
documentation), so downstream references are always stable before dependents are updated.

### Phase 1 — Router script: rename modes + remove execution paths (BR1–BR3, BR8, BR16)

**File**: `scripts/development-workflow/run-work-router.sh`

1. Rename constant `MODE_NO_TARGET="no_target_scan"` → `MODE_SCAN="scan"`.
2. Rename constant `LABEL_NO_TARGET="No-target scan"` → `LABEL_SCAN="Scan"`.
3. Rename constant `MODE_LIST="explicit_list"` → `MODE_REDIRECT_ITEMS="redirect_items"`.
4. Rename constant `LABEL_LIST="Explicit list"` → `LABEL_REDIRECT_ITEMS="Redirect (items)"`.
5. Update all references to the old constant names throughout the script.
6. Update the two-or-more-token routing branch: output `ROUTING_MODE=redirect_items` and
   `REDIRECT_COMMAND=/run-items <resolved-list>` instead of triggering Protocol 90 execution.
7. Remove or disable any code path that allowed the script to proceed to Protocol 90 mutation
   for `no_target_scan` or `explicit_list` — the script is read-only; it must stop at redirect.
8. Update the help/usage comment block at the top of the script to reflect the new mode names
   and the fact that the script is always read-only.

**Invariants preserved**: `redirect_item`, `redirect_epic`, and `ambiguous` modes are unchanged.

---

### Phase 2 — Protocol 96: update routing spec (BR1–BR3, BR8, BR16)

**File**: `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`

1. Replace the introductory paragraph that says "mutation begins only after handoff to Protocol 90
   (`no_target_scan` or `explicit_list`)" with language stating `/run-work` is scan-only; mutation
   is delegated to `/run-items` (Protocol 90 `explicit_list`), `/run-item` (Protocol 91), or
   `/run-epic` (Protocol 95).
2. Replace the routing modes table rows:
   - `no_target_scan` → `scan` (Scan): read-only portfolio scan proposing 1–3 batch options.
   - `explicit_list` → `redirect_items` (Redirect (items)): 2+ resolvable tokens; redirect to
     `/run-items`.
3. Update the decision table (token-count classification section) to match: two-or-more resolvable
   tokens → `redirect_items`; no-target → `scan`.
4. Update the handoff table at the end of the protocol:
   - `scan` → stop (no Protocol 90 handoff); emit copy-ready execute commands.
   - `redirect_items` → stop; emit `REDIRECT_COMMAND=/run-items <list>`.
5. Update any inline examples that reference `no_target_scan` or `explicit_list`.

---

### Phase 3 — New `/run-items` command and skill files (BR4–BR5, BR8, BR9, BR10)

Create the following files:

#### 3a. `.claude/commands/run-items.md`

New Claude Code command file. Content:

- Description: bounded explicit multi-item execution (Protocol 90 `explicit_list`).
- Required: 2+ target tokens.
- Steps: run bounded prelude → always-confirm → Protocol 90 `explicit_list` → base `develop` →
  no integration branch → stop at `ready-for-human-review`.
- Two-step lifecycle note: merging is a separate `/batch-merge` step.
- Deprecation note: accepts redirects from deprecated `/run-work explicit_list` form.

#### 3b. `.cursor/commands/run-items.md`

Mirror of the Claude Code command for Cursor (same content, `# Cursor Command: Run Items` header).

#### 3c. `.agents/skills/run-items/SKILL.md`

New Codex command-style alias skill. Content:

- YAML front-matter: `name: run-items`, description that mirrors `.claude/commands/run-items.md`.
- Body: same steps as 3a.
- Reference `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  for the `explicit_list` execution contract.

#### 3d. `.agents/skills/run-items/openai.yaml`

Add `openai.yaml` consistent with other skills under `.agents/skills/` (label + default prompt).

---

### Phase 4 — Update `/run-work` command and skill files (BR1, BR3, BR8)

#### 4a. `.claude/commands/run-work.md`

Replace the routing-mode table with the new five-row table:

| Routing mode | Action |
|---|---|
| `scan` | Read-only portfolio scan — propose 1–3 batch options with copy-ready execute commands |
| `redirect_items` | 2+ resolvable tokens — stop; re-invoke `/run-items <list>` |
| `redirect_item` | 1 non-epic token — stop; re-invoke `/run-item <target>` |
| `redirect_epic` | 1 epic token or `--epic` — stop; re-invoke `/run-epic --epic <n>` |
| `ambiguous` | Stop for human clarification |

Update the frontmatter `description:` to say "scan-only portfolio discovery" (not "portfolio
parallel orchestration").

Remove the reference to Protocol 90 as the execution handoff for no-target or multi-target cases.

#### 4b. `.cursor/commands/run-work.md`

Same table and description update as 4a.

#### 4c. `.agents/skills/run-work/SKILL.md`

Same updates as 4a.

---

### Phase 5 — Update `/run-epic` command and skill files (BR6, BR8)

#### 5a. `.claude/commands/run-epic.md`

1. Remove the `--items <list>` form from the description frontmatter and body.
2. Add deprecation handler: if `--items` is supplied, emit a deprecation notice naming
   `/run-items` as the replacement and perform no mutation.
3. Enforce `--epic <n>` as the only supported invocation form (native sub-issues only).

#### 5b. `.cursor/commands/run-epic.md`

Already partially updated (references `/run-items` for explicit lists). Verify it enforces
no `--items` flag and add the deprecation notice if not already present.

#### 5c. `.agents/skills/run-epic/SKILL.md`

Same updates as 5a. Verify the frontmatter `description:` already reflects `--items`
removal; update if needed.

---

### Phase 6 — Protocol 90 updates (BR4, BR9)

**File**: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`

1. Update the preamble to clarify that `/run-work` no longer enters Protocol 90 for execution.
   Protocol 90 is now entered via `/run-items` (for `explicit_list` mode) and remains the
   canonical multi-item execution contract.
2. Replace references to `no_target_scan` with `scan` and references to `/run-work`'s
   `explicit_list` execution entry point with `/run-items`.
3. Add or update the two-step lifecycle note: Protocol 90 advances items to
   `ready-for-human-review` and stops; merging is via `/batch-merge`.

---

### Phase 7 — Bounded prelude doc: add `/run-items` (BR10)

**File**: `docs/workflow/development-workflow/bounded-run-prelude.md`

1. Add `/run-items` to the list of commands that run the shared bounded prelude (currently lists
   `/run-item` and `/run-epic`).
2. Add a usage example for `/run-items` invocation.
3. Add a note that the prelude is always run and always requires human confirmation before mutation
   (always-confirm), and that the operator may waive checkpoints with recorded rationale.

---

### Phase 8 — Guardrails defaults: uncomment sensible defaults (BR11, AC9)

**File**: `.ai-dev-workflow.yaml`

Uncomment the `guardrails:` block with the conservative defaults already documented in the file's
comments. The values to uncomment are:

```yaml
guardrails:
  mode: manual
  backlog_start:
    allow_without_confirmation: false
  stages:
    spec:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
    plan:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
    implementation:
      may_open_pr: true
      may_merge_pr: false
      max_merge_risk: low
      required_evidence:
        - regression
  stop_conditions:
    - unclear_requirements
    - architecture_decision
    - failing_ci
    - unresolved_blocking_review
    - high_risk_change
    - destructive_action
    - missing_tracker_context
    - missing_required_secret_or_permission
  audit:
    pr_disposition_record: required
    work_item_ledger_record: required
```

Retain the explanatory comment block above each field for downstream readability. These values
match the conservative safe defaults already described in the comments; uncommenting makes the
defaults explicit without changing behavior.

---

### Phase 9 — Surface sync: AGENTS.md (BR15, AC10)

**File**: `AGENTS.md` (= `CLAUDE.md` symlink)

1. In the **Workflow Commands** table, add a new `/run-items` row after `/run-item`:

   | Advance Explicit List | `/run-items` command | `/run-items` | `/run-items` alias | Follow Protocol 90 `explicit_list` |

2. Update the **Orchestrate Work (portfolio)** row description to say "scan-only portfolio
   discovery — proposes batch options; execute with `/run-items`."

3. In the Codex Skills paragraph (starting "repo-scoped Codex discovery path"), add
   `/run-items` to the list of command-style aliases.

4. Update the "For normal Codex usage" paragraph to reference `/run-items` for explicit
   multi-item execution.

---

### Phase 10 — Surface sync: README.md (BR15, AC10)

**File**: `README.md`

1. Add `/run-items` to the command examples in the workflow section (around line 250).
2. Update any description of `/run-work` as an execution command to clarify it is now
   scan-only (proposes options; execution is via `/run-items` or other execute commands).

---

### Phase 11 — CHANGELOG entry

**File**: `CHANGELOG.md`

Add under `[Unreleased]` → `### Added`:

```markdown
- Orchestration command finalization (Epic #1072, spec #1075): `/run-work` is now
  scan-only (proposes 1–3 batch options; emits copy-ready execute commands; no
  mutation); new `/run-items` command owns explicit multi-item execution via Protocol
  90 `explicit_list` mode (base `develop`, no integration branch); `/run-epic` is
  now epic-only (native sub-issues via Protocol 95; `--items` form deprecated and
  redirected to `/run-items`); sensible default `guardrails` uncommented in
  `.ai-dev-workflow.yaml` (conservative: `mode: manual`, `may_merge_pr: false` for
  all stages). Traces to children #1076 (scan-only router), #1077 (`/run-items`
  command), #1078 (epic-only `/run-epic`), #1079 (guardrails), #1080 (surface sync).
```

---

## Testing Strategy

This feature is documentation and configuration changes with one shell-script rename. No new
runtime code paths are added.

### Automated tests (lint)

1. `markdownlint-cli2` must report 0 errors on all new and modified `.md` files.
2. Heuristic lint (`scripts/lint/markdown-heuristic-lint.py`) must report 0 errors on spec
   and plan files.
3. `shellcheck scripts/development-workflow/run-work-router.sh` must pass with no errors.

### Script spot-checks

4. `./scripts/development-workflow/run-work-router.sh --json` (no args) must emit
   `ROUTING_MODE=scan` (not `no_target_scan`).
5. `./scripts/development-workflow/run-work-router.sh 1075 1076 --json` must emit
   `ROUTING_MODE=redirect_items` and `REDIRECT_COMMAND=/run-items 1075 1076`.
6. `./scripts/development-workflow/run-work-router.sh 1075 --json` must still emit
   `ROUTING_MODE=redirect_item` (single non-epic token — unchanged behavior).
7. `python3 -c "import yaml; yaml.safe_load(open('.ai-dev-workflow.yaml'))"` must succeed
   after uncommenting the guardrails block.

### No smoke-test runbook required

No browser automation or UI changes. The smoke-test stage is skipped for this item.

---

## Documentation Updates

The following docs are updated as part of implementation (not deferred):

- `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md` (Phase 2)
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` (Phase 6)
- `docs/workflow/development-workflow/bounded-run-prelude.md` (Phase 7)
- `AGENTS.md` / `CLAUDE.md` (Phase 9)
- `README.md` (Phase 10)

---

## Implementation Traceability (spec → plan)

| Spec BR / AC | Plan Phase |
|---|---|
| BR1 (scan-only `/run-work`) | Phase 1, 2, 4 |
| BR2 (`redirect_items` for 2+ resolvable tokens) | Phase 1, 2, 4 |
| BR3 (`redirect_item` / `redirect_epic` for 1 token) | Phase 1, 2 (invariant) |
| BR4 (`/run-items` owns explicit-list execution) | Phase 3, 6 |
| BR5 (base `develop`, no integration branch) | Phase 3 |
| BR6 (`/run-epic` epic-only) | Phase 5 |
| BR7 (integration branch label-driven) | Phase 5 (invariant) |
| BR8 (deprecated paths redirect to `/run-items`) | Phase 1, 3, 5 |
| BR9 (two-step lifecycle) | Phase 3, 6 |
| BR10 (always-confirm prelude) | Phase 7 |
| BR11 (guardrails defaults uncommented) | Phase 8 |
| BR12 (protocols remain authoritative) | All phases |
| BR13 (`run` prefix retained) | Phase 3 |
| BR14 (stop conditions unchanged) | Phase 8 |
| BR15 / AC10 (surface sync) | Phase 9, 10 |
| BR16 (`ambiguous` for unresolvable tokens) | Phase 1 (invariant) |
| AC1 (scan mode, no mutation) | Phase 1, 2 |
| AC2 (`redirect_items` for 2+ resolvable tokens) | Phase 1, 2, 4 |
| AC3 (`redirect_item` / `redirect_epic`) | Phase 1, 2 (invariant) |
| AC4 (`/run-items` with bounded prelude, base develop) | Phase 3, 6, 7 |
| AC5 (`/run-epic` native sub-issues only) | Phase 5 |
| AC6 (deprecation notice + redirect) | Phase 1, 3, 5 |
| AC7 (two-step lifecycle) | Phase 3, 6 |
| AC8 (always-confirm execute commands) | Phase 7 |
| AC9 (guardrails uncommented) | Phase 8 |
| AC10 (surface sync) | Phase 9, 10 |
| AC11 (spec self-consistency) | Delivered by spec PR #1084 |
