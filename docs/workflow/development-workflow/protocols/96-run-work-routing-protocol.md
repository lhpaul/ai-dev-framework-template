# Protocol 96: /run-work Routing

**Routing layer version**: 1.0
**Status**: Active

This protocol is the canonical specification for how `/run-work` and `/run-items`
classify an invocation into a routing mode, emit a routing-decision record, and
hand off to the appropriate underlying protocol. It is read-only: it defines a
deterministic classifier, not an execution protocol. Mutation under `/run-work`
begins only after handoff to Protocol 90 `no_target_scan` mode. Bounded execution
(`explicit_list`) is initiated by `/run-items`. Redirect modes perform no mutation.

---

## Purpose

`/run-work` is the **read-only portfolio scan** entrypoint (Protocol 90
`no_target_scan` mode). A human or delegating agent invokes it with **no target**
to scan the portfolio and receive a proposal. Single-target and epic-like
invocations produce **redirect guidance** to `/run-item` or `/run-epic` without
mutation. For bounded multi-item execution, use `/run-items` instead.

This protocol defines:

1. The **routing modes** and their code values (`no_target_scan`, `explicit_list`,
   `redirect_item`, `redirect_epic`, `ambiguous`).
2. The **deterministic routing decision table** that maps (input + discovered state
   + configuration) → routing mode.
3. The **routing-decision record** format every invocation must emit.
4. The **handoff mapping** from routing mode to the appropriate downstream protocol.

---

## Routing Modes (portfolio surface)

| Code value       | Display label     | Description                                                                                                                          |
| ---------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `no_target_scan` | No-target scan    | No target supplied; Protocol 90 scans and proposes the largest configuration-bounded safe parallel plan.                              |
| `explicit_list`  | Explicit list     | Two or more explicit targets; hard bounded portfolio batch (Protocol 90).                                                            |
| `redirect_item`  | Redirect (item)   | Single non-epic target resolved; `/run-work` performs **no mutation** and emits redirect to `/run-item`.                           |
| `redirect_epic`  | Redirect (epic)   | Epic-like or `--epic` target; `/run-work` performs **no mutation** and emits redirect to `/run-epic`.                                |
| `ambiguous`      | Ambiguous         | Cannot resolve deterministically; records stop reason and performs no mutation.                                                       |

**Valid transitions**:

- Portfolio inputs resolve to `no_target_scan` or `explicit_list`.
- Single non-epic targets resolve to `redirect_item` (not Protocol 91 under `/run-work`).
- Single epic-like targets and `--epic` resolve to `redirect_epic` (not Protocol 95 under `/run-work`).
- Any unresolved input → `ambiguous`.

---

## Routing Decision Table

This table is the authoritative, testable specification. `run-work-router.sh`
encodes the same rows. Every row maps to at least one automated test in
`scripts/development-workflow/tests/test-run-work-router.sh`.

| Input + discovered state + configuration | Routing mode (`code value`) | Reference |
| --- | --- | --- |
| No target token supplied (including empty string `""` and whitespace-only input) | `no_target_scan` | UC1, BR3, AC1 |
| Exactly one target token that resolves to exactly one issue, workflow branch, open PR, or development folder, and that target is **not** epic-like | `redirect_item` | UC5, BR4, AC5 |
| Exactly one target token that resolves to exactly one issue which **is** epic-like (has child items / native sub-issues) | `redirect_epic` | UC5, BR4, AC6 |
| Exactly one target token that is explicitly marked as an epic (e.g., `--epic <n>` flag) | `redirect_epic` | UC5, BR6, AC6 |
| Two or more explicit target tokens (after duplicate collapse) that each resolve to a concrete target | `explicit_list` | UC3, BR5, AC3 |
| Any input that cannot be deterministically resolved: unresolvable lookalike token, mixed list with at least one unresolvable token, or a single token matching two different concrete artifacts (conflicting signal) | `ambiguous` | BR2, BR10, AC11 |

**Edge cases** (all must be covered by automated tests):

| Edge case | Expected routing mode |
| --- | --- |
| Empty argument string `""` | `no_target_scan` |
| Whitespace-only argument `"   "` | `no_target_scan` |
| Single bare non-epic issue number (e.g., `978`) | `redirect_item` |
| Single issue number that is epic-like (e.g., `977`) | `redirect_epic` |
| Single branch token (`feature/42-foo`, `spec/42-foo`) | `redirect_item` |
| Single PR token (`#118` or bare `118` resolving to an open PR) | `redirect_item` |
| Single development-folder token (`docs/specs/developments/2026…_42-foo`) | `redirect_item` |
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
REDIRECT_COMMAND=<recommended /run-item or /run-epic command when mode is redirect_item or redirect_epic>
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
  "redirectCommand": "<recommended command or null>",
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

| Routing mode     | Handoff target                                                                                                                      |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `no_target_scan` | **Protocol 90** (`90-batch-orchestrate-work-protocol.md`) — portfolio scan with largest-safe-batch proposal (invoked by `/run-work`) |
| `explicit_list`  | **Protocol 90** — portfolio orchestration with explicit item list as hard bounded scope (invoked by `/run-items`)                   |
| `redirect_item`  | **No handoff** — emit `REDIRECT_COMMAND` (e.g. `/run-item <target>`); operator re-invokes `/run-item`                              |
| `redirect_epic`  | **No handoff** — emit `REDIRECT_COMMAND` (e.g. `/run-epic --epic <n>`); operator re-invokes `/run-epic`                            |
| `ambiguous`      | **No handoff** — record stop reason, perform no mutation, stop for a human decision                                                 |

The routing layer does not replace Protocols 90, 91, or 95. It determines whether
`/run-work` enters Protocol 90 scan mode or stops with redirect guidance for bounded
commands. Bounded execution (`explicit_list`) is invoked by `/run-items`, not by
`/run-work`.

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
