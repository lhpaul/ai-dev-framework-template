# Tracker Status Mapping

This page is the single definition of which tracker **Status** a workflow event
sets. Protocols, agents, and skills link here instead of restating the mapping,
and runners resolve a Status through the helper below instead of choosing a
string themselves. Two runners given the same instruction therefore set the
same tracker state (#1564).

The machine-readable copy of this mapping is
`workflow_tracker_status_for_event` in
`scripts/development-workflow/workflow-lib.sh`.
`scripts/development-workflow/tests/test-tracker-status-mapping.sh` fails when
this page and that function disagree.

## Canonical Status Vocabulary

In workflow order:

1. `Backlog`
2. `Writing Spec`
3. `Spec in Review`
4. `Spec Ready`
5. `Writing Plan`
6. `Plan in Review`
7. `Plan Ready`
8. `In Development`
9. `Development in Review`
10. `Merged`
11. `Released`

`Cancelled` is out of band: it may be set from any state and ends the item.

Only these exact strings are valid. Names from other trackers, such as
`In Progress`, `In Review`, `Todo`, or `Done`, are not aliases. Nothing maps
them to a canonical value, because mapping them would be a guess.

## Event-to-Status Mapping

The stage is set by the branch that carries the work:

- `spec/*` is the spec stage.
- `implementation-plan/*` is the plan stage.
- `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` are the implementation
  stage.

Other branches, such as `release/*`, `backport/*`, and `develop-<slug>`, do not
set an item's Status through this mapping. Graduation and release closeout use
their own helpers.

| Event | Spec | Plan | Implementation |
| --- | --- | --- | --- |
| `dispatch` | Writing Spec | Writing Plan | In Development |
| `ready-for-human-review` | Spec in Review | Plan in Review | Development in Review |
| `merged` | Spec Ready | Plan Ready | Merged |
| `released` | — | — | Released |
| `needs-fixes` | no change | no change | no change |
| `ready-for-regression` | no change | no change | no change |
| `needs-setup` | no change | no change | no change |
| `human-checkpoint-required` | no change | no change | no change |

What each event means:

- **`dispatch`**: the Work Item Runner or Portfolio Orchestrator starts the
  stage's creator agent. When the item is already at this stage's in-flight
  Status, the call changes nothing, so it is safe to repeat.
- **`ready-for-human-review`**: the label is applied and verified on the live PR
  (Protocol 91 Step 8a). This is the Step 8b transition, and it is the only
  readiness label that changes Status.
- **`merged`**: the stage PR is merged, confirmed against live PR state (Protocol
  91 Step 10, `post-merge-cleanup.sh`, and `update-tracker-on-merge.yml`).
- **`released`**: the merged implementation ships in a release (Protocol 05
  release cleanup).
- **Labels marked "no change"**: these leave Status unchanged. A PR labeled
  `needs-fixes` stays in its `… in Review` Status while fixes land, and the
  tracker helper never moves Status backward unless the caller asks for it
  explicitly.

## Resolving and Applying a Status

Resolve the Status. This is read-only:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/tracker-status-for.sh \
  --event ready-for-human-review --branch fix/1564-tracker-status-vocabulary
# TRACKER_STATUS=Development in Review
# TRACKER_STATUS_ACTION=set
```

Resolve and apply it in one step:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/tracker-status-for.sh \
  --event ready-for-human-review --branch "$BRANCH" --apply --issue "$ISSUE_NUMBER"
```

`--stage spec|plan|implementation` can replace `--branch`. `--list` prints the
canonical vocabulary.

With `--apply`, the helper prints `TRACKER_STATUS_RESULT` with one of these
values:

- `applied`
- `skipped`: the item is already further along, or it is not on the board.
- `deferred`: the Linear MCP handoff is required.
- `none`: the event changes nothing.
- `failed`: a transient API error, or a Status field that could not be read
  (`reason=status_field_unavailable`).
- `unresolved`

The helper derives `TRACKER_STATUS_RESULT` from machine-readable markers that
`update_tracker_status_best_effort` prints, never from its human-readable
warnings:

- `TRACKER_STATUS_APPLIED issue=<n> status='<status>'`: the write succeeded.
- `TRACKER_STATUS_UPDATE_FAILED issue=<n> requested='<status>' reason=mutation_failed`:
  the write failed.
- `TRACKER_STATUS_UNRESOLVED`: the Status could not be resolved. The next
  section covers the two reasons.

Runners that source `workflow-lib.sh` directly call the same mapping:

<!-- workflow-shell-contract: bash-zsh -->
```bash
TARGET_STATUS="$(workflow_tracker_status_for_event ready-for-human-review \
  "$(workflow_tracker_stage_for_branch "$BRANCH")")"
update_tracker_status_best_effort "$ISSUE_NUMBER" "$TARGET_STATUS"
```

## When the Board Does Not Offer the Status

`update_tracker_status_best_effort` treats permanent configuration errors
differently from failures that can be transient.

### The board has no option with that name

This is a vocabulary error, and it is never transient. The warning names the
board's real options, and the helper prints a machine-readable line:

```text
TRACKER_STATUS_UNRESOLVED issue=<n> requested='<status>' reason=unknown_status_option valid_options='<option>, <option>, ...'
```

By default the helper still returns `0`, so existing best-effort callers keep
working. When `WORKFLOW_TRACKER_STATUS_STRICT=true`, it returns `2`.
`tracker-status-for.sh --apply` always runs in strict mode and exits `3` with
`TRACKER_STATUS_RESULT=unresolved`.

### The board has no Status field

The lookup read every page of the board's fields and found none named
`Status`. This is also a permanent configuration error. The helper prints the
same line with `reason=status_field_missing` and handles it like an unknown
option: it returns `2` in strict mode, and `--apply` exits `3`.

### The Status field cannot be read

This covers a failed lookup, an unparsable response, or the pagination limit.
Any of these can be transient, so the helper prints the same line with
`reason=status_field_unavailable` and stays best-effort, even in strict mode.

### What orchestrated runs do

Orchestrated runs are Protocol 90 and Protocol 91. They apply transitions with
`tracker-status-for.sh --apply`. Exit `3` is a stop under
`missing_tracker_context`. The stop names:

- the item
- the canonical Status the board is missing
- the valid options from the `TRACKER_STATUS_UNRESOLVED` line
- the unblock action: add the canonical option (or the `Status` field itself)
  to the board, or correct the caller

In an orchestrated run, silent drift costs more than a stop. Drift leaves the
board unusable as evidence of how the run went.

A transient failure (`failed` or `status_field_unavailable`) does not block
labeling or PR readiness. Record it in the Work Item Runner Summary.

## Who Applies the Transition

The Work Item Runner applies transitions for its item. In a batch, the Portfolio
Orchestrator applies them, as described in Protocol 90 Step 2.5 and in
Protocol 91 at Step 2, Step 8b, and Step 10. Stage agents that are not running
under an orchestrator follow the same mapping. For trackers without a `gh`
path, a subagent returns `TRACKER_UPDATE_REQUIRED: set issue #<N> status to
"<status from this mapping>"` instead of writing to the tracker.
