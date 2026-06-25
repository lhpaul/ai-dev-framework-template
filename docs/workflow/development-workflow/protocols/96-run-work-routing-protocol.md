# Protocol 96: /run-work Routing

**Routing layer version**: 1.0
**Status**: Active

This protocol is the canonical specification for how `/run-work` classifies an
invocation into a routing mode, emits a routing-decision record, and hands off
to the appropriate underlying protocol. It is read-only: it defines a
deterministic classifier, not an execution protocol. Mutation begins only after
handoff to Protocol 90, 91, or 95.

---

## Purpose

`/run-work` is the **primary adaptive entrypoint** for workflow orchestration. A
human — or a delegating agent — can invoke it with no target, one target, several
targets, or an epic target, and the routing layer determines which underlying
behavior applies without requiring the caller to know which internal protocol
handles each case.

This protocol defines:

1. The **five routing modes** and their code values.
2. The **deterministic routing decision table** that maps (input + discovered state
   + configuration) → routing mode.
3. The **routing-decision record** format every invocation must emit.
4. The **handoff mapping** from routing mode to the appropriate downstream protocol.

---

## The Five Routing Modes

| Code value       | Display label   | Description                                                                                                                          |
| ---------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `no_target_scan` | No-target scan  | No target was supplied; the command scans tracker and repository state and proposes the largest configuration-bounded safe plan.      |
| `single_item`    | Single item     | Exactly one item, branch, PR, or development folder was resolved; the command advances only that.                                    |
| `explicit_list`  | Explicit list   | Two or more explicit targets were supplied; the list is a hard bounded scope — items outside the list are never mutated.             |
| `epic`           | Epic            | The target is epic-like; read-only scope resolution runs before any item is created, reviewed, merged, or cleaned up.               |
| `ambiguous`      | Ambiguous       | The request cannot be resolved to exactly one of the above modes; the command records the stop reason and performs no mutation.      |

**Valid transitions**:

- A request resolves to exactly one of `no_target_scan`, `single_item`,
  `explicit_list`, or `epic` based on the input and discovered state.
- `single_item` → `epic` when the single resolved target turns out to be epic-like
  (it has child items / native sub-issues). The upgrade is applied before handoff.
- Any mode → `ambiguous` when the request cannot be deterministically resolved;
  an `ambiguous` outcome stops for a human decision and performs no mutation.

---

## Routing Decision Table

This table is the authoritative, testable specification. `run-work-router.sh`
encodes the same rows. Every row maps to at least one automated test in
`scripts/development-workflow/tests/test-run-work-router.sh`.

| Input + discovered state + configuration | Routing mode (`code value`) | Reference |
| --- | --- | --- |
| No target token supplied (including empty string `""` and whitespace-only input) | `no_target_scan` | UC1, BR3, AC1 |
| Exactly one target token that resolves to exactly one issue, workflow branch, open PR, or development folder, and that target is **not** epic-like | `single_item` | UC2, BR4, AC2 |
| Exactly one target token that resolves to exactly one issue which **is** epic-like (has child items / native sub-issues) | `epic` (upgraded from `single_item`) | UC2 consideration, UC4, BR6, AC5 |
| Exactly one target token that is explicitly marked as an epic (e.g., `--epic <n>` flag, native epic issue type) | `epic` | UC4, BR6, AC4 |
| Two or more explicit target tokens (after duplicate collapse) that each resolve to a concrete target | `explicit_list` | UC3, BR5, AC3 |
| Any input that cannot be deterministically resolved: unresolvable lookalike token, mixed list with at least one unresolvable token, or a single token matching two different concrete artifacts (conflicting signal) | `ambiguous` | BR2, BR10, AC11 |

**Edge cases** (all must be covered by automated tests):

| Edge case | Expected routing mode |
| --- | --- |
| Empty argument string `""` | `no_target_scan` |
| Whitespace-only argument `"   "` | `no_target_scan` |
| Single bare non-epic issue number (e.g., `978`) | `single_item` |
| Single issue number that is epic-like (e.g., `977`) | `epic` |
| Single branch token (`feature/42-foo`, `spec/42-foo`) | `single_item` |
| Single PR token (`#118` or bare `118` resolving to an open PR) | `single_item` |
| Single development-folder token (`docs/specs/developments/2026…_42-foo`) | `single_item` |
| Space-separated list of two or more targets (`42 43`) | `explicit_list` |
| Comma-separated list of two or more targets (`42,43`) | `explicit_list` |
| List with duplicate tokens (`42 42 43` → scope `{42, 43}`) | `explicit_list` with deduplication |
| Unresolvable lookalike (e.g., `999999` with no matching artifact) | `ambiguous` |
| Mixed list with one unresolvable token (`42 not-a-target`) | `ambiguous` |
| Single token matching two different artifacts (branch + issue collision) | `ambiguous` |

---

## Configuration Consumption (No-Target Mode)

In `no_target_scan` mode the router reports which `guardrails` configuration
values bounded the proposed plan. The fields consulted and reported are:

- **`guardrails.mode`** — the overall autonomy level (`manual` / `assisted` /
  `delegated` / `autonomous`). Default when absent: `manual`.
- **`guardrails.backlog_start.allow_without_confirmation`** — whether unstarted
  backlog items may be proposed without explicit human confirmation. Default when
  absent: `false`.

The router **reports** these values; it never **overrides** them. Starting
backlog work remains gated by the existing human-approval flow in Protocol 90.
When no `guardrails` section is present in `.ai-dev-workflow.yaml`, the router
records `guardrails_section=absent` and applies the documented safe defaults:
mode `manual`, backlog starts require confirmation.

See `docs/workflow/development-workflow/guardrails.md` for the full guardrails
reference including mode descriptions, per-stage permissions, and stop
conditions.

---

## Routing-Decision Record Format

Every `/run-work` invocation must emit a routing-decision record. The record
appears on stdout before handoff begins. It contains:

**Required fields** (stable `key=value` lines, one per line):

```
MODE=<code_value>
MODE_LABEL=<display_label>
RAW_TARGET=<raw target argument or "(none)" if no target was supplied>
RESOLVED_SCOPE=<comma-separated list of resolved concrete targets, or "(none)" for no-target>
```

**Conditional fields** (emitted when applicable):

```
HELD_BACK=<comma-separated list of items held back with reason, or "(none)">
OUT_OF_SCOPE=<comma-separated list of out-of-scope items encountered, or "(none)">
STOP_REASON=<human-readable stop reason when mode is ambiguous or run does not advance>
GUARDRAILS_MODE=<mode value from .ai-dev-workflow.yaml or "manual" (default)>
GUARDRAILS_BACKLOG_START=<true|false (default: false)>
GUARDRAILS_SECTION=<present|absent>
```

**JSON output** (emitted when `--json` flag is supplied, as a single JSON object
after the `key=value` lines):

```json
{
  "mode": "<code_value>",
  "modeLabel": "<display_label>",
  "rawTarget": "<raw target or null>",
  "resolvedScope": ["<target1>", "..."],
  "heldBack": [{"item": "<id>", "reason": "<reason>"}, "..."],
  "outOfScope": ["<item1>", "..."],
  "stopReason": "<reason or null>",
  "guardrails": {
    "section": "present|absent",
    "mode": "<mode value>",
    "backlogStart": <true|false>
  }
}
```

The helper script `scripts/development-workflow/run-work-router.sh` emits this
record and is the canonical implementation of the routing decision table above.

---

## Handoff Mapping

After the routing-decision record is emitted, execution hands off to:

| Routing mode     | Handoff target                                                                                                         |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `no_target_scan` | **Protocol 90** (`90-batch-orchestrate-work-protocol.md`) — portfolio orchestration with the existing largest-safe-batch proposal and human-approval gate |
| `single_item`    | **`/run-item`** bounded prelude, then **Protocol 91** (`91-orchestrate-work-protocol.md`) for the resolved target |
| `explicit_list`  | **Protocol 90** — portfolio orchestration with the explicit item list as a hard bounded scope (existing Explicit Item List Scope Guard applies) |
| `epic`           | **Protocol 95** (`95-run-epic-protocol.md`) — bounded epic scope resolver with read-only phase before any mutation |
| `ambiguous`      | **No handoff** — record stop reason, perform no mutation, stop for a human decision |

The routing layer does not replace or modify the responsibilities of Protocols 90,
91, or 95. It only determines which one to enter and passes the resolved scope and
routing-decision record to that protocol as context.

---

## Read-Only Contract

The routing layer is **read-only**. Before the handoff completes,
`run-work-router.sh` must not:

- Update tracker status
- Create, switch, or delete branches
- Open, edit, label, or close pull requests
- Merge pull requests
- Close issues
- Post comments on PRs or issues
- Delete releases, tags, or artifacts

The read-only contract is verified by the mutating-call guard in the unit-test
suite (`test-run-work-router.sh`): any mock `gh` or `git` mutating call causes an
immediate test failure.

---

## Implementation Reference

- **Router helper**: `scripts/development-workflow/run-work-router.sh` — encodes
  this decision table, emits the routing-decision record as stable `key=value`
  lines and `--json`, read-only.
- **Unit tests**: `scripts/development-workflow/tests/test-run-work-router.sh` —
  covers every edge case in this protocol's routing decision table.
- **Protocol 90 routing block**: see "Routing Entrypoint" section in
  `90-batch-orchestrate-work-protocol.md` for the cross-reference from the
  portfolio orchestrator.
- **Protocol 91 routing note**: see "Routing From /run-work" section in
  `91-orchestrate-work-protocol.md`.
- **Protocol 95 routing note**: see "Routing From /run-work" section in
  `95-run-epic-protocol.md`.

---

## Related Documents

- `docs/workflow/development-workflow/guardrails.md` — guardrails modes, defaults,
  per-stage permissions, stop conditions, and audit requirements.
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
