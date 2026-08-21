# Protocol 96: /run-work Routing

**Routing layer version**: 1.1
**Status**: Active

This protocol is the canonical specification for how `/run-work` classifies an
invocation into a routing mode, emits a routing-decision record, and hands off
to the appropriate underlying protocol. It is read-only: it defines a
deterministic classifier, not an execution protocol. `/run-work` is now
**scan-and-propose only** — all routing modes perform no mutation. For batch
execution, use `/run-items` (multi-item) or the redirect modes' target commands.

---

## Purpose

`/run-work` is **portfolio scan and batch proposal only** — a read-only command
that inspects the portfolio and recommends the next safe batch. It performs **no
mutation** in any routing mode: no branch creation, no tracker updates, no PR
operations, no item-orchestrator dispatch.

A human or delegating agent invokes it with **no target** (portfolio scan) to
receive a batch proposal. All invocations with targets produce redirect guidance:
single targets redirect to `/run-item` or `/run-epic`; two or more targets
redirect to `/run-items`. The human then executes the recommended command.

This protocol defines:

1. The **routing modes** and their code values (`no_target_scan`, `redirect_items`,
   `redirect_item`, `redirect_epic`, `ambiguous`, `tracker_unavailable`).
2. The **deterministic routing decision table** that maps (input + discovered state
   + configuration) → routing mode.
3. The **routing-decision record** format every invocation must emit.
4. The **handoff mapping** from routing mode to the appropriate downstream protocol.

---

## Routing Modes (portfolio surface)

| Code value        | Display label      | Description                                                                                                                                            |
| ----------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `no_target_scan`  | No-target scan     | No target supplied; `/run-work` scans the portfolio and proposes a batch recommendation — **no dispatch, no mutation**. Execute with `/run-items`.      |
| `redirect_items`  | Redirect (items)   | Two or more explicit targets; `/run-work` performs **no mutation** and emits redirect to `/run-items` with the resolved target list.                    |
| `redirect_item`   | Redirect (item)    | Single non-epic target resolved; `/run-work` performs **no mutation** and emits redirect to `/run-item`.                                               |
| `redirect_epic`   | Redirect (epic)    | Epic-like or `--epic` target; `/run-work` performs **no mutation** and emits redirect to `/run-epic`.                                                   |
| `ambiguous`       | Ambiguous          | Cannot resolve deterministically; records stop reason and performs no mutation.                                                                         |
| `tracker_unavailable` | Tracker unavailable | A `gh` probe used to resolve a target failed (rate limit, auth, network, GitHub outage, or a local repository-configuration error) rather than confirming the target does not exist; records a cause-specific stop reason and performs no mutation. Distinct from `ambiguous`, which means the input itself could not be resolved, not that the resolution attempt errored. |

**Valid transitions**:

- No-target invocations resolve to `no_target_scan` (scan and propose only — no dispatch).
- Two or more explicit targets resolve to `redirect_items` (no execution under `/run-work`).
- Single non-epic targets resolve to `redirect_item` (not Protocol 91 under `/run-work`).
- Single epic-like targets and `--epic` resolve to `redirect_epic` (not Protocol 95 under `/run-work`).
- Any unresolved input → `ambiguous`.
- Any input whose resolution could not be determined because the underlying
  `gh` probe itself failed (rate limit, auth failure, network error, GitHub
  outage, or a local repository-configuration error such as gh having no
  default remote repository configured) → `tracker_unavailable`, not
  `ambiguous`. A genuine not-found result (the probe succeeded and confirmed
  no matching target) still resolves to `ambiguous`. The `STOP_REASON` and
  operator guidance differ by sub-cause: a rate limit, auth failure, network
  error, or outage all recommend retrying (immediately, or after the
  reported quota reset time for a rate limit); a local repository-
  configuration error instead recommends running `gh repo set-default` in
  the checkout, since retrying will not help until the default repository is
  configured.

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
| Two or more explicit target tokens (after duplicate collapse) that each resolve to a concrete target | `redirect_items` | UC3, BR5, AC3 |
| Any input that cannot be deterministically resolved: unresolvable lookalike token, mixed list with at least one unresolvable token, or a single token matching two different concrete artifacts (conflicting signal) | `ambiguous` | BR2, BR10, AC11 |
| A `gh` probe used to resolve a token failed with a rate limit, auth failure, network error, or GitHub outage — the probe itself errored rather than confirming the target does not exist (single token, or the first such failure encountered in a multi-token list) | `tracker_unavailable` | #1503 |
| A `gh` probe used to resolve a token failed with a local repository-configuration error (gh has no default remote repository configured for this checkout) — a local environment problem, not evidence the target does not exist and not a transient outage | `tracker_unavailable` (with `STOP_REASON` recommending `gh repo set-default`, not a retry) | #1503 |

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
| Space-separated list of two or more targets (`42 43`) | `redirect_items` |
| Comma-separated list of two or more targets (`42,43`) | `redirect_items` |
| List with duplicate tokens (`42 42 43` → scope `{42, 43}`) | `redirect_items` with deduplication |
| Unresolvable lookalike (e.g., `999999` with no matching artifact) | `ambiguous` |
| Mixed list with one unresolvable token (`42 not-a-target`) | `ambiguous` |
| Single token matching two different artifacts (branch + issue collision) | `ambiguous` |
| `gh pr view`/`gh issue view` probe fails with a rate-limit error while resolving a token | `tracker_unavailable` |
| `gh pr view`/`gh issue view` probe fails with an authentication error while resolving a token | `tracker_unavailable` |
| `gh pr view`/`gh issue view` probe fails with a network error while resolving a token | `tracker_unavailable` |
| `gh pr view`/`gh issue view` probe fails with an unrecognized/opaque error (GitHub outage) while resolving a token | `tracker_unavailable` |
| `gh pr view`/`gh issue view` probe fails with "no default remote repository has been set" while resolving a token | `tracker_unavailable` (`STOP_REASON` recommends `gh repo set-default`, distinct from the outage/retry wording) |
| `gh pr view`/`gh issue view` probe returns gh's own "could not resolve to a PullRequest/Issue" not-found message, or a bare non-zero exit with empty stderr at gh's normal API-error exit code (`1`) | `ambiguous` (genuine not-found, unchanged) |
| A probe failure occurs partway through a multi-token list (after at least one token already resolved successfully) | `tracker_unavailable` (not masked by the earlier successful resolution) |

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
STOP_REASON=<human-readable stop reason when mode is ambiguous or tracker_unavailable, or run does not advance; for tracker_unavailable this names the probe-failure cause (rate limit, auth, network, GitHub outage, or local repository-configuration error) and, for a rate limit, the quota reset time when available; a local repository-configuration error recommends running gh repo set-default instead of retrying>
REDIRECT_COMMAND=<recommended /run-items, /run-item, or /run-epic command when mode is redirect_items, redirect_item, or redirect_epic>
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

After the routing-decision record is emitted, `/run-work` hands off as follows:

| Routing mode      | Handoff target                                                                                                                      |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `no_target_scan`  | **Protocol 90** (Steps 1–3 scan + proposal only) — outputs a categorized batch recommendation using `INFORMATIONAL - not actionable in this proposal`, `ACTIONABLE RESUME - can advance now`, `PROPOSED BATCH - your decision`, and `HELD - not included in proposed batch`; **no dispatch, no mutation** under `/run-work`. Execute only the proposed-batch items with `/run-items`. |
| `redirect_items`  | **No handoff** — emit `REDIRECT_COMMAND=/run-items <targets>`; operator re-invokes `/run-items` for batch execution               |
| `redirect_item`   | **No handoff** — emit `REDIRECT_COMMAND` (e.g. `/run-item <target>`); operator re-invokes `/run-item`                              |
| `redirect_epic`   | **No handoff** — emit `REDIRECT_COMMAND` (e.g. `/run-epic --epic <n>`); operator re-invokes `/run-epic`                           |
| `ambiguous`       | **No handoff** — record stop reason, perform no mutation, stop for a human decision                                                 |
| `tracker_unavailable` | **No handoff** — record the cause-specific stop reason, perform no mutation, and recommend the operator retry once the underlying `gh` failure clears (immediately for auth/network fixes, or after the reported quota reset time for a rate limit) rather than treating the target as unresolved. For a local repository-configuration error (no default remote configured), the recommendation is `gh repo set-default`, not a retry — retrying will not change the outcome. |

The routing layer does not replace Protocols 90, 91, or 95. `/run-work` is a
proposal surface only. Execution is delegated to `/run-items`, `/run-item`, or
`/run-epic` per the redirect guidance.

---

## Read-Only Contract

`/run-work` is **fully read-only** in all routing modes. Unlike previous
versions, even `no_target_scan` produces only a proposal — no dispatch and no
mutation occur under `/run-work`. Before any handoff (or in place of one),
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
