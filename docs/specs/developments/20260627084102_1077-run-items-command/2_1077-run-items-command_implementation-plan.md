# Implementation Plan: `/run-items` Multi-Item Bounded Execute Command

**Spec**: `docs/specs/developments/20260627084102_1077-run-items-command/1_1077-run-items-command_specs.md`
**Issue**: #1077
**Complexity**: Medium
**Branch type**: `feature/1077-run-items-command`

---

## Step 0: Template-Fit Check

This repository has `template.is_template: true`. The feature improves the
workflow tooling that the template ships (command surfaces, router script,
documentation) — framework-agnostic across all downstream consumers. Fit check
**passes**; no halt required.

---

## Overview

`/run-items` is the new canonical multi-item bounded execute command. The
implementation is surface-only: new command files, small targeted edits to the
router script and scope resolver, and documentation updates. No new protocol or
stage contract is introduced. All multi-item execution still flows through
Protocol 90 `explicit_list` mode; `/run-items` is the single entry point to that
mode.

**Depends on**: The spec `20260627084102_1077-run-items-command` must be merged
to `develop` before this plan PR is opened. (Confirmed — PR #1083 merged.)

---

## Affected Files

### Files to create

| File | Purpose |
| --- | --- |
| `.claude/commands/run-items.md` | Claude Code `/run-items` command definition |
| `.cursor/commands/run-items.md` | Cursor `/run-items` command definition |
| `.agents/skills/run-items/SKILL.md` | Codex skill for `/run-items` |
| `.agents/skills/run-items/agents/openai.yaml` | Codex OpenAI metadata for the skill |

### Files to modify

| File | Change summary |
| --- | --- |
| `scripts/development-workflow/run-work-router.sh` | Emit `REDIRECT_COMMAND=/run-items <list>` for `explicit_list` case |
| `scripts/development-workflow/run-epic-scope-resolver.sh` | When `--items` flag is used, emit `REDIRECT_COMMAND=/run-items <list>` to stdout and exit cleanly (exit 0) without resolving any issues |
| `scripts/development-workflow/tests/test-run-work-router.sh` | Add assertions that `explicit_list` cases include `REDIRECT_COMMAND` containing `/run-items` and the resolved scope tokens |
| `.claude/commands/run-work.md` | Update routing table: `explicit_list` row now shows redirect to `/run-items` (no longer enters Protocol 90 directly) |
| `.cursor/commands/run-work.md` | Same as above |
| `.agents/skills/run-work/SKILL.md` | Same as above |
| `.claude/commands/run-epic.md` | Remove `--items` from supported flags; add note that `--items` is deprecated and redirects to `/run-items` |
| `CLAUDE.md` | Add `/run-items` row after `/run-item` row in Workflow Commands table; add to Codex skill alias list |
| `docs/workflow/development-workflow/README.md` | Add `/run-items` row after `/run-item` row in workflow commands table; update Codex skills description |
| `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md` | Update `explicit_list` handoff row: redirect to `/run-items` (no mutation under `/run-work`) |
| `CHANGELOG.md` | Add entry under `[Unreleased]` |

---

## Step-by-Step Implementation

### Step 1: Create `.claude/commands/run-items.md`

Mirror the structure of `.claude/commands/run-item.md`. The file uses a YAML
front matter block and then a Markdown body explaining the command behavior.

**YAML front matter**:
```yaml
---
description: "Multi-item bounded execute: advance an explicit list of two or more non-epic workflow items with shared prelude before Protocol 90 explicit_list. Usage: /run-items <target> <target> [<target>...] [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---
```

**Body content**:
- Header: `# Claude Code Command: Run Items`
- Brief paragraph: `/run-items` is the canonical multi-item bounded execute command for an explicit list of two or more non-epic items. Runs the shared bounded prelude (scope resolution, guardrails snapshot, policy/checkpoint recommendation) before any mutation, then advances the listed items through Protocol 90 `explicit_list` mode.
- Note: Epic-like tokens in the list cause the entire invocation to stop; use `/run-epic --epic <n>` for those. One token redirects to `/run-item`. Zero tokens redirect to `/run-work`.
- Section `## Bounded prelude and Protocol 90`:
  - Step 1 (read-only validation): Run `run-work-router.sh <list> --json` to classify the invocation. Stop with redirect guidance when mode is not `explicit_list` (e.g., `redirect_item` for one token, `redirect_epic` for an epic-like token).
  - Step 2 (read-only prelude): Run `run-bounded-prelude.sh --original-command "/run-items <list>" --items <list> [policy flags] --json`. When `policyRecommendation.requiresConfirmation` is true, present policy/checkpoint recommendations and wait for human confirmation before any mutation.
  - Step 3 (mutation): Enter Protocol 90 `explicit_list` mode per `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
  - Terminal state: all in-scope PRs at `ready-for-human-review` (plus any held/blocked/escalated items). Name `/batch-merge` as the explicit landing step. `/run-items` never merges PRs itself.

### Step 2: Create `.cursor/commands/run-items.md`

Mirror `.claude/commands/run-items.md` with Cursor command conventions (header
`# Cursor Command: Run Items`). Content is otherwise identical to Step 1.

### Step 3: Create `.agents/skills/run-items/SKILL.md`

Mirror `.agents/skills/run-item/SKILL.md` for the multi-item path.

**YAML front matter**:
```yaml
---
name: run-items
description: "Multi-item bounded execute command: advance an explicit list of two or more non-epic workflow items. Runs the shared bounded prelude then Protocol 90 explicit_list until all items reach a terminal state."
---
```

**Body content** (numbered steps mirroring the run-item skill):
1. Read `AGENTS.md` for repository-wide rules.
2. Run the read-only bounded prelude: `./scripts/development-workflow/run-bounded-prelude.sh --original-command "<invocation>" --items <list> [policy flags] --json`. See `docs/workflow/development-workflow/bounded-run-prelude.md`.
3. When `policyRecommendation.requiresConfirmation` is true in the prelude JSON, present policy/checkpoint recommendations and continue only after human acceptance or customization.
4. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` and follow it for `explicit_list` mode.
5. Before implementation mutation in `workflow_hub`, state selected product repository, artifact owner, and mutation target; stop when context is missing or ambiguous.
6. Guardrails enforcement: use portfolio-resolved guardrails when available; otherwise resolve from repo `guardrails` config. Report effective values before mutation.
7. Epic-like tokens in the list stop the entire invocation; use `$run-epic` / `/run-epic --epic <n>` for those. One token → use `$run-item`. Zero tokens → use `$run-work`.

### Step 4: Create `.agents/skills/run-items/agents/openai.yaml`

Mirror `.agents/skills/run-item/agents/openai.yaml`:

```yaml
interface:
  display_name: "Run items"
  short_description: "Multi-item bounded execute: advance an explicit list of two or more workflow items with shared prelude before Protocol 90 explicit_list."
  default_prompt: "Use $run-items to advance an explicit list of two or more non-epic workflow items. Run run-bounded-prelude.sh read-only first (scope, guardrails, policy/checkpoints), then follow Protocol 90 explicit_list mode until all items reach a terminal state. Epic-like tokens stop the entire invocation — use $run-epic for those. One token → use $run-item. Zero tokens → use $run-work."

policy:
  allow_implicit_invocation: false
```

### Step 5: Update `scripts/development-workflow/run-work-router.sh`

**Location**: In Case 4 (two or more tokens), after `RESOLVED_SCOPE="$scope_str"`.

**Add a new helper function** near the existing `build_redirect_command_item`
and `build_redirect_command_epic` functions:

```bash
build_redirect_command_items() {
  local scope="$1"  # comma-separated resolved scope string
  # Convert comma-separated to space-separated for the /run-items invocation
  local space_list
  space_list="$(printf '%s' "$scope" | tr ',' ' ')"
  printf '/run-items %s' "$space_list"
}
```

**Set `REDIRECT_COMMAND`** in Case 4, immediately after `RESOLVED_SCOPE="$scope_str"`:

```bash
REDIRECT_COMMAND="$(build_redirect_command_items "$scope_str")"
```

The existing output block already handles emitting `REDIRECT_COMMAND`:
```bash
if [ -n "${REDIRECT_COMMAND:-}" ]; then
  echo "REDIRECT_COMMAND=$REDIRECT_COMMAND"
fi
```

No change needed to the output block. The MODE value remains `explicit_list` —
only `REDIRECT_COMMAND` is added to the output. The `/run-work` surfaces already
check for `REDIRECT_COMMAND` presence and stop before entering Protocol 90 when
it is set.

**JSON output**: The existing JSON section also emits `redirectCommand` from
`REDIRECT_COMMAND`. No changes needed there.

### Step 6: Update `scripts/development-workflow/run-epic-scope-resolver.sh`

**Current behavior** when `--items` is used: deprecation warning to stderr at
parse time (line 77), then the script continues resolving using `items_arg`.

**Required behavior** (AC11): When `--items` is detected, emit a redirect notice
with `REDIRECT_COMMAND=/run-items <list>` to stdout, then exit 0 without
resolving any issues.

**Specific change**: Add an early-exit block after the validation section (after
the `valid_max_risk` check, around line 136). Insert immediately before
`require_gh`:

```bash
# --items is deprecated. Redirect callers to /run-items.
if [ -n "$items_arg" ]; then
  space_list="$(printf '%s' "$items_arg" | tr ',' ' ')"
  echo "DEPRECATED: --items is deprecated. Use /run-items for explicit item lists."
  echo "REDIRECT_COMMAND=/run-items ${space_list}"
  exit 0
fi
```

The stderr deprecation warning at parse time (line 77) is retained as an early
signal. This additional block makes the redirect machine-readable (stdout
`REDIRECT_COMMAND`) and exits cleanly.

### Step 7: Update `scripts/development-workflow/tests/test-run-work-router.sh`

**Location**: After each existing `explicit_list` test group (space list, comma
list, duplicate-token list).

Add `REDIRECT_COMMAND` assertions for each group. Example for the space-list
group (after the existing `space_list_scope_contains_979` test):

```bash
run_test_contains "space_list_redirect_command_prefix" "/run-items" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"
run_test_contains "space_list_redirect_contains_978" "978" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"
run_test_contains "space_list_redirect_contains_979" "979" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"
```

Add equivalent assertions for the comma-list and duplicate-token groups.

### Step 8: Update `/run-work` command and skill files

**`.claude/commands/run-work.md`**: Change the routing table row:

Before:
```markdown
| `explicit_list` | Protocol 90 (hard bounded batch) |
```
After:
```markdown
| `explicit_list` | `/run-items` redirect (re-invoke `/run-items <list>`; no Protocol 90 mutation under `/run-work`) |
```

**`.cursor/commands/run-work.md`**: Change the routing table row:

Before:
```markdown
| Two or more targets | `explicit_list` | Protocol 90 — bounded portfolio batch |
```
After:
```markdown
| Two or more targets | `explicit_list` | **Stop** — re-invoke `/run-items <list>` |
```

**`.agents/skills/run-work/SKILL.md`**: Change the routing table row:

Before:
```markdown
| `explicit_list` | Protocol 90 with hard bounded scope |
```
After:
```markdown
| `explicit_list` | Stop; tell the user to run `$run-items` with the resolved list |
```

Also update the numbered step 4 to note that `explicit_list` redirects to
`$run-items` instead of `workflow-orchestrator`.

### Step 9: Update `.claude/commands/run-epic.md`

In the "Key responsibilities" list, change:

Before:
```markdown
- Require exactly one of `--epic` or `--items`.
- Resolve native GitHub sub-issues for `--epic`; keep `--items` exact.
```

After:
```markdown
- Require `--epic <issue-number>`. For explicit item lists, use `/run-items`.
- `--items` is deprecated: the resolver emits `REDIRECT_COMMAND=/run-items <list>` and exits without resolving.
- Resolve native GitHub sub-issues for `--epic`.
```

Also update the YAML front matter `description` field to remove `--items` from
the supported flags list (it already says "For explicit item lists, use
/run-items" in the Cursor version; align the Claude version).

### Step 10: Update `CLAUDE.md`

**Workflow Commands table**: Add a `/run-items` row after the `/run-item` row:

```markdown
| Advance Multiple Items (explicit list) | `/run-items` command | — | `/run-items` alias | Follow `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` (Protocol 90 `explicit_list`) with shared bounded prelude before mutation |
```

**Codex skill alias list paragraph** (the sentence listing command-style
aliases): Add `/run-items` immediately after `/run-item` and before
`/run-item-work`:

Before:
```
... command-style aliases such as `/add-backlog-item`, `/run-work`, `/run-item`, `/run-item-work` (deprecated alias), `/run-epic`, ...
```
After:
```
... command-style aliases such as `/add-backlog-item`, `/run-work`, `/run-item`, `/run-items`, `/run-item-work` (deprecated alias), `/run-epic`, ...
```

### Step 11: Update `docs/workflow/development-workflow/README.md`

**Workflow commands table**: Add a `/run-items` row after the `/run-item` row
(around line 203):

```markdown
| Advance multiple items (explicit list) | `/run-items` command | `/run-items` | `/run-items` alias | Follow `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` (Protocol 90 `explicit_list`) with shared bounded prelude — `/run-work` with two or more tokens redirects here |
```

**Codex skills description paragraph** (around line 221): Add `/run-items` to
the alias list immediately after `/run-item`:

Before:
```
Command-style aliases such as `/add-backlog-item`, `/run-work`, `/run-item`, `/run-item-work` (deprecated alias), `/run-epic`, ...
```
After:
```
Command-style aliases such as `/add-backlog-item`, `/run-work`, `/run-item`, `/run-items`, `/run-item-work` (deprecated alias), `/run-epic`, ...
```

### Step 12: Update `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`

**Handoff mapping section**: Update the `explicit_list` row.

Before:
```markdown
| `explicit_list`  | **Protocol 90** — portfolio orchestration with explicit ...
```
After:
```markdown
| `explicit_list`  | **No handoff** — emit `REDIRECT_COMMAND=/run-items <list>` (no mutation under `/run-work`); operator re-invokes `/run-items` for the bounded multi-item execute |
```

**Routing-Decision Record Format section**: The conditional `REDIRECT_COMMAND`
field is currently documented as applying only when `mode is redirect_item or
redirect_epic`. Update that description to also include `explicit_list`:

Before:
```
REDIRECT_COMMAND=<recommended /run-item or /run-epic command when mode is redirect_item or redirect_epic>
```
After:
```
REDIRECT_COMMAND=<recommended command when mode is redirect_item, redirect_epic, or explicit_list>
```

Also update any routing decision table rows, Routing Modes table entries, and
narrative sections that describe `explicit_list` as directly entering Protocol
90 to clarify the redirect behavior.

### Step 13: Update `CHANGELOG.md`

Add under `[Unreleased]`:

```markdown
### Added
- **`/run-items` multi-item bounded execute command** (#1077): adds
  `.claude/commands/run-items.md`, `.cursor/commands/run-items.md`, and
  `.agents/skills/run-items/` as the canonical command surfaces for advancing
  an explicit list of two or more non-epic workflow items with the shared bounded
  prelude and Protocol 90 `explicit_list` mode.

### Changed
- **`/run-work` explicit-list redirect** (#1077): `/run-work` with two or more
  targets now redirects to `/run-items` instead of entering Protocol 90 directly;
  `run-work-router.sh` emits `REDIRECT_COMMAND=/run-items <list>` for
  `explicit_list` outcomes.
- **`/run-epic --items` deprecation** (#1077): `--items` is deprecated and
  redirects to `/run-items <list>`; `run-epic-scope-resolver.sh` now exits
  cleanly with `REDIRECT_COMMAND` output instead of continuing to resolve
  explicit item lists.
```

---

## Implementation Order

Execute the steps in this sequence to minimize risk and allow incremental
verification:

1. Create four new command/skill files (Steps 1–4) — independent of each other; no dependency on script changes.
2. Update `run-work-router.sh` (Step 5) — enables the redirect behavior; can be tested immediately.
3. Update `run-epic-scope-resolver.sh` (Step 6) — enables the deprecation redirect; independent of router.
4. Update test file (Step 7) — validates the router change from Step 5.
5. Update `/run-work` command and skill surfaces (Step 8) — documentation aligned with behavior from Step 5.
6. Update `/run-epic` command surface (Step 9) — reflects resolver change from Step 6.
7. Update `CLAUDE.md` (Step 10).
8. Update README (Step 11).
9. Update Protocol 96 (Step 12).
10. Update `CHANGELOG.md` (Step 13).
11. Run router tests: `bash scripts/development-workflow/tests/test-run-work-router.sh`

---

## Testing and Verification

### Automated tests

```bash
# Router tests — verify explicit_list cases now emit REDIRECT_COMMAND with /run-items
bash scripts/development-workflow/tests/test-run-work-router.sh

# Scope resolver — verify --items emits REDIRECT_COMMAND and exits 0
./scripts/development-workflow/run-epic-scope-resolver.sh --items 978,979 2>/dev/null | grep REDIRECT_COMMAND
echo "Exit code: $?"
```

### Manual verification checklist

- [ ] `run-work-router.sh 978 979` outputs `MODE=explicit_list` and `REDIRECT_COMMAND=/run-items 978 979`
- [ ] `run-work-router.sh 978,979` outputs `REDIRECT_COMMAND=/run-items 978 979`
- [ ] `run-epic-scope-resolver.sh --items 978,979` outputs `REDIRECT_COMMAND=/run-items 978 979` and exits 0 without resolving issues
- [ ] `.claude/commands/run-items.md` exists and correctly describes the command
- [ ] `.cursor/commands/run-items.md` exists
- [ ] `.agents/skills/run-items/SKILL.md` exists
- [ ] `.agents/skills/run-items/agents/openai.yaml` exists
- [ ] `CLAUDE.md` has a `/run-items` row in the Workflow Commands table
- [ ] `docs/workflow/development-workflow/README.md` has a `/run-items` row
- [ ] Protocol 96 `explicit_list` row reflects redirect to `/run-items`
- [ ] Router tests all pass

---

## Acceptance Criteria Traceability

| AC | Step(s) covering it |
| -- | ------------------- |
| AC1: prelude runs before mutation | Steps 1–4 (command surfaces invoke `run-bounded-prelude.sh --items`) |
| AC2: only listed items advanced | Steps 1–4 (explicit_list scope boundary documented in commands) |
| AC3: explicit_list reachable only via `/run-items` | Steps 5, 8, 12 (router emits redirect; `/run-work` stops) |
| AC4: PRs target `develop` | Steps 1–4 (documented in command surfaces; spec BR5 enforced by Protocol 90) |
| AC5: parallel stage / serialized impl | Steps 1–4 (Protocol 90 `explicit_list` handles this; documented in command surfaces) |
| AC6: per-item Protocol 93 before ready | Steps 1–4 (Protocol 91 per item; documented) |
| AC7: declare complete only after CI + reviewer loop green | Steps 1–4 (Protocol 90 handles; documented) |
| AC8: epic-like token stops entire invocation | Steps 1–4 (router guard + command-level guard documented) |
| AC9: fewer than 2 tokens redirect | Steps 1–4 (sub-two-item guard documented in command surfaces) |
| AC10: `/run-work` 2+ tokens redirects to `/run-items` | Steps 5, 8, 12 |
| AC11: `/run-epic --items` deprecated, redirects | Steps 6, 9 |
| AC12: command surfaces exist | Steps 1–4 |
| AC13: docs updated | Steps 10, 11 |

---

## Out of Scope

- Implementing new prelude scripts or Protocol 90 behaviors — both already exist
  and are reused as-is.
- Hard-removing `--items` from `run-epic-scope-resolver.sh` — this plan
  deprecates and redirects it, consistent with the spec's "redirect, not hard
  removal" intent.
- Modifying Protocol 90, 91, 93, or 95 beyond Protocol 96.
- A new Codex `.codex/skills/run-items/` entry — the `.agents/skills/run-items/`
  path is the canonical location for repo-scoped Codex discovery.

---

## Smoke Test Runbook

No browser automation is required. The smoke test is:

1. Run: `bash scripts/development-workflow/tests/test-run-work-router.sh` — all tests pass.
2. Run: `./scripts/development-workflow/run-work-router.sh 978 979` — output contains `REDIRECT_COMMAND=/run-items 978 979`.
3. Run: `./scripts/development-workflow/run-epic-scope-resolver.sh --items 978,979 2>/dev/null` — output contains `REDIRECT_COMMAND=/run-items 978 979`; exit code is 0.
4. Confirm the four new files exist and are non-empty.
5. Confirm `CLAUDE.md` Workflow Commands table includes the `/run-items` row.
6. Confirm `docs/workflow/development-workflow/README.md` command table includes the `/run-items` row.
