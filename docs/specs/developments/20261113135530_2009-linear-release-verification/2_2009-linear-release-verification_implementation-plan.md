# Verified Linear release completion — Implementation Plan

**Spec**: [1_2009-linear-release-verification_specs.md](1_2009-linear-release-verification_specs.md)
**Smoke test runbook**: [2009-linear-release-verification.smoke-test.md](../../../testing/workflow/2009-linear-release-verification.smoke-test.md)

---

## Summary

**Approach**: Add a small, pure evaluator,
`scripts/development-workflow/linear-release-verification.py`, that compares an
operator-supplied, normalized Linear read-back file with the release scope and
prints per-item results, release-level action items, counts and the overall
outcome. Wire it into the existing Linear branch of
`prepare-release-post-merge-cleanup.sh` behind a new optional
`--linear-readback <path>` flag, keep every existing Linear handoff line for an
Incomplete outcome, and let a Complete outcome end the run without an error.
The first cleanup run start per release and the read-back used by each run are
kept in a local state directory under the repository's git common directory.
GitHub Projects, GitHub Issues and every other provider path are untouched.

**Estimated complexity**: M

**Rationale**: One new self-contained helper with a closed decision table, one
bounded edit to the Linear branch and argument parsing of an existing script,
one new test suite, one new section in an existing suite, and documentation
mirrors. No configuration, workflow or tracker-schema change.

**Dependencies**: None. The spec is merged on `develop` (V1). Scope derivation
(#1982) is already on `develop` and is not changed.

---

## Design decisions

Each decision below is the single normative statement of its fact; other
sections refer to it by its ID.

- **D1 — Read-back input.** The operator supplies the independent reads as one
  JSON file through `--linear-readback <path>`. The shell helper never calls
  Linear; the operator reads through the Linear integration the workflow
  already documents (V12) and normalizes each read into the D2 shape. The flag
  is optional: without it, every in-scope item has no read (spec Use Case 4).
- **D2 — Read-back schema `linear_release_readback.v1`.** Top level:
  `{"schemaVersion": "linear_release_readback.v1", "reads": [...]}`. Each read
  is an object with: `suppliedFor` (the in-scope item the operator supplies it
  for), `provider` (`"linear"`), `issue` (the identifier the read itself
  returned), `team` (the team key the read itself returned), `releaseVersion`
  (the release version this read was taken for), `labels` (array of label
  names the read returned), `statusName` (status name the read returned),
  `observedAt` (ISO 8601 instant with an explicit offset or `Z`),
  `readRequestId` (non-empty string identifying the read call) and optional
  `mutationRequestId` (identifier of the write the operator made, when any).
  The field names follow the durable merge-operation bridge proof (V12) so one
  normalization serves both. Unknown extra fields are ignored.
- **D3 — Attribution.** A read is attributed to `suppliedFor` when that is a
  valid Linear identifier (same pattern the cleanup script already accepts,
  V13), otherwise to `issue` when that is valid. A read with neither is
  reported as ignored with reason `unattributable`. A read attributed to an
  identifier outside the release scope is reported as ignored with reason
  `out_of_scope` (spec AC8). Ignored reads never change any result.
- **D4 — Read usability.** For an attributed in-scope read, the first failing
  check below gives the read's reason; a read passing every check is usable.
  Identifiers and team keys are compared case-insensitively; labels, release
  version and status name are compared exactly.
  1. `unreadable` — `provider` is not `"linear"`; any required D2 field is
     missing or has the wrong type; `observedAt` does not parse, has no offset,
     or is later than the evaluation time; or `mutationRequestId` equals
     `readRequestId` (an echoed write is not a read, spec BR3).
  2. `mismatch` — `issue` differs from the attributed item, `releaseVersion`
     differs from the run's release version, or `team` differs from the owning
     team, which is the part of the attributed identifier before its last `-`.
  3. `stale` — `observedAt` is not strictly later than the D6 starting point.
- **D5 — Per-item result.** With no attributed read, the result is
  `not_verified` with reason `no_read`. With attributed reads but no usable
  read, the result is `not_verified` with every distinct read reason listed in
  D4 order. Otherwise the usable reads with the latest `observedAt` decide: if
  two or more share that instant and differ in release-label presence or
  `statusName`, the result is `not_verified` with reason `conflicting`;
  otherwise the label is present when `labels` contains the exact D7 label,
  the status is Released when `statusName` equals the run's released status
  name (the script's existing `RELEASED_LABEL`, default `Released`), and the
  result is `verified`, `missing_label`, `not_released` or
  `missing_label_and_not_released` per the spec's status table. A usable read
  that shows another version's label but not this one is `missing_label`
  (spec BR12).
- **D6 — Starting point.** The evaluator keeps one record per release branch at
  `<git-common-dir>/ai-dev-workflow/linear-release-verification/<key>/first-run.json`,
  where `<key>` is the release branch with every `/` replaced by `__`. The
  record holds `releaseBranch`, `releaseVersion` and `firstRunStartedAt`. When
  it is absent, the evaluator creates it with exclusive-create semantics using
  the current run's start, so concurrent first runs keep exactly one record and
  later runs never move it (spec BR2). The run start is the UTC second the
  cleanup script started, captured once at script start. A record that exists
  but cannot be read or does not match the release branch makes the evaluator
  report `unavailable` (D9).
- **D7 — Release label.** The label is the configured `release_label_prefix`
  (default `release/`) followed by the script's existing `RELEASE_VERSION`,
  exactly as `record_release_for_issue_best_effort` already prints it (V7).
  Hotfix and patch versions use the same rule (spec AC4).
- **D8 — Output contract.** Every line is printed through `cleanup_log` by the
  shell after the evaluator returns, in this order, and only after D10 has
  retained the run record:
  - `LINEAR_RELEASE_VERIFICATION release_version=<v> release_label=<label> required_status=<json> first_run_started_at=<ts> run_started_at=<ts> readback=<supplied|none>`
  - one `LINEAR_RELEASE_ITEM issue=<id> result=<code> ...` line per in-scope
    item, in scope order; a decided item adds `label=<present|absent>
    status=<json> read_at=<ts>`, a `not_verified` item adds
    `reasons=<r1[,r2...]>`
  - one `LINEAR_RELEASE_READ_IGNORED issue=<json> reason=<reason>` line per
    ignored read
  - `LINEAR_RELEASE_LABEL_ACTION label=<label> teams=<k1[,k2...]> action=create_label_in_owning_team_if_missing_then_apply`
    when no usable read of any in-scope item shows the D7 label (spec BR5,
    UC3); `teams` lists the owning teams of the in-scope items without one
  - `LINEAR_RELEASE_COUNTS verified=N missing_label=N not_released=N missing_label_and_not_released=N not_verified=N`
  - `LINEAR_RELEASE_VERIFICATION_RECORD path=<path>`
  - `LINEAR_RELEASE_OUTCOME=<complete|incomplete>`
  - for `incomplete` only, `TRACKER_ISSUES_UNVERIFIED=<id[,id...]>` naming
    every item that is not `verified` (spec BR6)

  Any value that comes from the read-back file (`status`, an ignored read's
  `issue`) is printed JSON-encoded, so a crafted value cannot add a line or
  forge another key. Identifiers printed unquoted are only scope identifiers,
  which already passed the script's identifier validation.
- **D9 — Evaluator exit codes.** `0` complete, `1` incomplete, `3` unavailable
  (state record unreadable or unwritable, run record unwritable, git common
  directory unresolvable, or any unexpected exception, which the evaluator
  catches as reason `internal_error`), `2` usage error. On `3` the evaluator prints only
  `LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=<reason>` and no item,
  count or outcome line. The read-back file failing to parse is not `3`: every
  in-scope item is then `not_verified` with reason `unreadable` (spec AC6).
- **D10 — Run record.** Before printing, the evaluator writes
  `<state>/<key>/runs/<run-started-at>-<pid>.json` (temporary file then
  rename) holding the run's inputs, the verbatim read-back content, every
  per-item result with the read that decided it, the ignored reads, the action
  items, the counts and the outcome (spec Operational Visibility, AC1).
- **D11 — Shell wiring in the Linear branch.** In
  `prepare-release-post-merge-cleanup.sh`, the existing
  `if [ "$TRACKER_PROVIDER" = "linear" ]` tracker block (V2) changes as
  follows, and nothing else in that block or before it changes:
  - when `issue_tracker.custom_fields.release_field` is configured, the block
    runs exactly as today and no verification line is printed; if
    `--linear-readback` was passed, one stderr notice
    `LINEAR_RELEASE_VERIFICATION_SKIPPED reason=release_field_configured` is
    printed (spec AC14, BR4);
  - otherwise, after the existing stamp-guidance loop, the shell runs the
    evaluator. When the helper file is missing, the shell prints
    `LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=verifier_missing` and
    continues as for evaluator `3`. The shell treats an exit `0` whose output
    lacks `LINEAR_RELEASE_OUTCOME=complete`, and any exit other than `0` or
    `1`, as evaluator `3`, so no failure path can end as Complete;
  - evaluator `0`: print its lines, then `STAMPED=...` as today, emit the
    component JSON `complete`/`true`/`complete` when in component JSON mode,
    print `Release post-merge cleanup complete.` and exit `0`. The manual
    transition list, `TRACKER_ACTION=linear_mcp_or_api_required`,
    `TRACKER_INCOMPLETE=1 ...` and `TRACKER_ISSUES=` are not printed;
  - evaluator `1` or `3`: print its lines, then the existing handoff lines
    unchanged (manual transition list, `TRACKER_ACTION=...`,
    `TRACKER_INCOMPLETE=1 REASON=linear_status_transition_required`,
    `TRACKER_ISSUES=...`, the guide pointer and `STAMPED=...`), then the
    existing exit logic unchanged: exit `1` without `--best-effort`; with it,
    the existing component JSON `incomplete` and exit `0` (spec BR7, AC7).
- **D12 — Flag validation.** `--linear-readback` takes a non-empty path. After
  argument parsing and before any mutation, the script exits `2` when the
  provider is not `linear` (`--linear-readback is only supported with
  issue_tracker.provider: linear`) or when the path is not a readable regular
  file. The read-only `--inspect-targets` path and the empty-scope and
  scope-failure exits (V2, before the Linear block) are not changed, so they
  report no verification outcome (spec AC13, BR9).
- **D13 — Merge sessions.** The merge-session route (`--merge-session`) and
  the read-only projection it requests are not changed (spec Out of Scope).
  A session child that reaches the Linear block evaluates exactly as a
  standalone run with the same argv (V6).

---

## Verification Log

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V0 | Repo revision | `git rev-parse --short HEAD` on `implementation-plan/2009-linear-release-verification` at creation | `768382de` (= `origin/develop`) |
| V1 | Spec merged | `git log --oneline -1 768382de` | `docs(spec): verified Linear release completion (#2009) (#2186)` |
| V2 | Linear tracker block and earlier exits | `grep -n 'TRACKER_PROVIDER" = "linear" ]; then\|TRACKER_ACTION=linear_mcp_or_api_required\|REASON=no_issue_scope\|REASON=changelog_scope_unavailable\|INSPECT_TARGETS" = "true" ]; then' scripts/development-workflow/prepare-release-post-merge-cleanup.sh` at V0 | Linear block starts at line 2715 with the handoff line at 2742; the scope-failure exit (line 2560), the `--inspect-targets` block (2569–2611) and the no-scope exit (2696–2710) all precede it |
| V3 | No read-back verification exists today | `grep -n -i -e readback -e read-back -e observedAt scripts/development-workflow/prepare-release-post-merge-cleanup.sh` and `ls scripts/development-workflow \| grep -i 'linear-release'` at V0 | no output for either |
| V4 | GitHub parity suite exists | `grep -n 'Differential GitHub parity' scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh` at V0 | section at lines 4168–4741, comparing HEAD with the frozen develop baseline for both GitHub providers |
| V5 | Consumers of the cleanup script | `git grep -l prepare-release-post-merge-cleanup -- . ':!docs/specs/developments'` at V0 | listed in the Rule 5 consumer table below |
| V6 | Merge-budget invocations | `grep -n 'prepare-release-post-merge-cleanup.sh\|args.argv + \["--release-head"' scripts/development-workflow/workflow-merge-budget.py` at V0 | line 562 builds an `--inspect-targets` argv (read-only projection); the cleanup child reuses the operator's original argv plus `--release-head` |
| V7 | Release label and field precedence | `sed -n 3552,3561p scripts/development-workflow/workflow-lib.sh` at V0 | Linear prints `release_field=` when configured, else `release_label=<prefix><version>` with prefix default `release/` |
| V8 | Sync coverage of a new helper | `sed -n 109,112p sync-manifest.yaml` at V0 | `scripts/development-workflow/` with glob `**/*` (`hub_only`) already ships any new file there; the cleanup script itself has no individual entry |
| V9 | Suite discovery | `sed -n 24,27p scripts/development-workflow/select-test-suites.sh` and `grep -n "name 'test-\*.sh'" scripts/development-workflow/select-test-suites.sh` at V0 | suites are `tests/test-*.sh`; `test-<name>.sh` covers `<name>.sh` and `<name>.py` by default; extra paths via `# covers:` |
| V10 | Open PRs on the same surfaces | `gh pr list --state open --limit 50 --json number,files` filtered to the cleanup script, its suite, `integrations/linear.md` and Protocol 05, at plan time | no open PR in the repository |
| V11 | Prepare-release mirrors that describe the Linear handoff | `git grep -l linear_mcp_or_api_required -- . ':!docs/specs/developments' ':!CHANGELOG.md'` at V0 | `.agents/skills/prepare-release/SKILL.md`, `.claude/commands/prepare-release.md`, `.cursor/commands/prepare-release.md`, `integrations/linear.md`, Protocol 05, `scripts/development-workflow/README.md`, the script, its frozen baseline and its suite |
| V12 | Existing Linear read-back proof shape | `sed -n 169,200p docs/workflow/development-workflow/integrations/linear.md` at V0 | bridge proof fields `provider`, `issue`, `repo`, `statusName`, `statusId`, `mutationRequestId`, `readRequestId`, `observedAt`; "an echoed mutation response is not an independent read"; "No new Linear API client is introduced" |
| V13 | Linear identifier pattern | `sed -n 585,594p scripts/development-workflow/prepare-release-post-merge-cleanup.sh` at V0 | `^[A-Za-z][A-Za-z0-9_]*-[0-9]+$` when the provider is `linear` |
| V14 | Linear fixtures copy only two scripts | `sed -n 1665,1679p scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh` at V0 | `init_linear_git_repo` copies `workflow-lib.sh` and the cleanup script only |

## Factual claim evidence

**Rule 5 — consumers of the changed unit** (the Linear tracker block and the
argument parser of `prepare-release-post-merge-cleanup.sh`; search V5 over the
whole working tree, where scripts, tests, commands, skills and docs live):

| Consumer | Path through the change | Outcome after the change |
| --- | --- | --- |
| `workflow-merge-budget.py` projection (line 562) | `--inspect-targets` exits before the Linear block (V2) | Unchanged; no new flag passed |
| `workflow-merge-budget.py` cleanup child (V6) | Original operator argv; reaches the Linear block only as a standalone run would | Same outcome as a standalone run with that argv (D13) |
| `test-workflow-merge-budget*.sh`, `test_workflow_merge_budget.py`, its frozen baseline, `test_pr_agent_runtime.py`, `test-run-epic-risk-classifier.sh` | Reference or drive the script without `--linear-readback` | Unchanged results; run in Implementation Order step 6 |
| `test-prepare-release-tracker-cleanup.sh` existing Linear cases | Reach the Linear block without the flag; fixtures lack the helper (V14) | Evaluator treated as unavailable (D11), so exit codes and every existing asserted line are unchanged; new verification lines are added |
| GitHub parity section (V4) | GitHub providers never enter the Linear block or D12 | Byte-identical outputs and call logs vs the frozen baseline (spec AC9) |
| Frozen baseline `prepare-release-post-merge-cleanup.develop-baseline` | Test input, not executed for Linear | Not edited |
| Protocol 05, `integrations/linear.md`, `scripts/development-workflow/README.md`, prepare-release command/skill mirrors (V11) | Describe the handoff | Updated per Documentation Updates |
| Smoke runbooks 232, 1356, 1529, `component-release-evidence-contract.md`, `repository-modes.md`, `integrations/github-projects.md`, `CHANGELOG.md` | Describe GitHub or component cleanup, or history | Unchanged; none describes Linear completion |

**Rule 6 — scoped obligations**:

- D11's "runs exactly as today" governs one input class: Linear runs where
  `release_field` is configured; it is discharged by the release-field case in
  the cleanup suite (Testing Strategy, I7).
- D12's rejection governs every invocation that passes `--linear-readback`
  with a non-Linear provider or an unreadable path; it is discharged at the
  validation step right after argument parsing and before the first mutation,
  and checked by I8.
- D6's "never moves" governs every evaluator run for the same release branch
  after the first; it is discharged by the exclusive create in the evaluator
  and checked by U10 and I5.
- The fixture obligation "copy the helper next to the cleanup script" governs
  only fixtures created for the new cases (I1–I9); existing fixtures stay as
  they are (Rule 5 table) and are checked by running the whole suite.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base for spec, plan and implementation PRs | `develop` | Bounded prelude for #2009 (`baseBranch: develop`, no integration label) | 2026-11-13, `768382de` | This invocation's single item; V10 open-PR check | `Verified` |
| Linear release marker key names and default | `release_label_prefix` default `release/`, `release_field` takes precedence | `workflow-lib.sh` (V7) and `integrations/linear.md` Custom Fields | 2026-11-13, `768382de` | V10 open-PR check on the same surfaces | `Verified` |
| Linear Released status name | `RELEASED_LABEL` (`GITHUB_PROJECT_STATUS_RELEASED`, default `Released`) | `prepare-release-post-merge-cleanup.sh` lines 81–82 at V0 | 2026-11-13, `768382de` | V10 open-PR check on the same surfaces | `Verified` |

---

## Layer-by-Layer Changes

### L1 — Evaluator (`scripts/development-workflow/linear-release-verification.py`, new)

- [ ] CLI `evaluate --state-dir DIR --release-branch B --release-version V
  --release-label L --released-status S --run-started-at TS --now TS
  [--readback PATH] --scope ID [--scope ID ...]`. `--now` is the evaluation
  time used by D4; the shell passes the current UTC time.
- [ ] Implements D2–D10 with the standard library only (`json`, `datetime`,
  `os`, `pathlib`, `argparse`); `Z` suffixes are normalized before
  `datetime.fromisoformat` so older Python 3 releases parse them.
- [ ] Prints exactly the D8 lines, in D8 order, to stdout; prints nothing to
  stdout on D9 exit `3` other than the unavailable line.

### L2 — Cleanup script (`scripts/development-workflow/prepare-release-post-merge-cleanup.sh`)

- [ ] Capture the run start once near the top (`date -u +%Y-%m-%dT%H:%M:%SZ`).
- [ ] Parse `--linear-readback` and validate it per D12; add it to `usage()`
  and to the header comment, including the D11 exit behaviour.
- [ ] In the Linear tracker block, apply D11. Resolve the state directory
  with `git -C "$HUB_REPO_ROOT" rev-parse --git-common-dir`; an unresolvable
  directory is evaluator outcome `3` with reason `state_unavailable`.

### L3 — Tests

- [ ] New suite `scripts/development-workflow/tests/test-linear-release-verification.sh`
  (covered by naming convention, V9) driving the evaluator CLI directly with
  temporary state directories and read-back files (cases U1–U14).
- [ ] New section `=== Linear release verification (#2009) ===` in
  `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
  for the shell wiring (cases I1–I9), reusing the Linear scope fixtures with
  explicit `--issue` scope, copying the helper into those new fixtures, and
  seeding `first-run.json` in the fixture's git directory where a fixed
  starting point is needed. Add
  `# covers: scripts/development-workflow/linear-release-verification.py` to
  that suite's header.

### L4 — Documentation (spec AC10)

- [ ] As listed in Documentation Updates.

### L5 — Changelog fragment

- [ ] `changelog.d/2009.fixed.linear-release-verification.md` with the body
  given in Implementation Order step 8.

---

## Testing Strategy

**Test types**: unit (evaluator CLI), integration (cleanup script with stubbed
`gh` and real git), existing GitHub parity regression, manual smoke.

**Coverage intent**: the U cases cover every row of the spec's decision-gate
matrix that the evaluator decides and every D4 reason, plus the D8 injection
guard and D6/D9 state behaviour. The I cases cover each D11/D12 branch once,
because the decision logic itself is already covered by U. The lists are
indicative: an implementer may merge or split cases if every listed class
stays covered. The suite sizes are proportionate: the evaluator is the only
new decision logic and the shell change is a branch with four exits.

**Unit cases (`test-linear-release-verification.sh`)**:

- U1 all items verified → exit 0, `LINEAR_RELEASE_OUTCOME=complete`, counts,
  record file holds the read-back (AC1).
- U2 one item `Merged` with the label → `not_released`, others verified,
  exit 1 (AC2).
- U3 `Released` without the label → `missing_label` (AC3); neither →
  `missing_label_and_not_released`.
- U4 hotfix `v1.29.1` with no read-back → label action names
  `release/v1.29.1` and the owning team, every item `not_verified no_read`
  (AC4, AC5).
- U5 one reason each: other release version, other item, other team, stale,
  missing `observedAt`, offset-less `observedAt`, future `observedAt`,
  `provider` not `linear`, `mutationRequestId` equal to `readRequestId` →
  `not_verified` with that reason (AC6, BR3).
- U6 two unusable reads with different reasons → both reasons listed in D4
  order (BR12).
- U7 read-back file that is not JSON, or has another `schemaVersion` → every
  item `not_verified unreadable` (AC6).
- U8 read for an out-of-scope item, and a read with no valid identifier →
  ignored lines, outcome unaffected (AC8).
- U9 two usable reads, older verified and newer `Merged` → `not_released`;
  same instant and disagreeing → `conflicting` (AC12).
- U10 no state record → created with the run start; a second run with a later
  run start keeps the first value; a read after the first start counts (AC11,
  BR2).
- U11 state record unreadable, and state directory not writable → exit 3 with
  only the unavailable line (D9).
- U12 read shows `release/v1.29.0` only during `v1.29.1` → `missing_label`
  (BR12).
- U13 `statusName` containing a newline and `LINEAR_RELEASE_OUTCOME=complete`
  → printed JSON-encoded on one line; outcome remains `incomplete` (D8).
- U14 identifiers and team keys in different case still match; label case
  difference does not (D4).

**Integration cases (`test-prepare-release-tracker-cleanup.sh`)**:

- I1 Linear, every item verified, no `--best-effort` → exit 0, no
  `TRACKER_ACTION=` line, `Release post-merge cleanup complete.` (AC1).
- I2 Linear, one item not released, no `--best-effort` → exit 1, existing
  handoff lines present, `TRACKER_ISSUES_UNVERIFIED` names the item (AC2).
- I3 Same with `--best-effort` → exit 0, outcome `incomplete` (AC7).
- I4 Linear without `--linear-readback` → exit 1 as today; all `no_read`
  (AC5).
- I5 First run creates `first-run.json`; a re-run does not change it (AC11).
- I6 Linear empty scope and unresolved scope with `--linear-readback` →
  existing exits, no `LINEAR_RELEASE_OUTCOME` line (AC13).
- I7 Linear with `release_field` configured and `--linear-readback` → existing
  handoff, skipped notice, no outcome line (AC14).
- I8 `--linear-readback` with `github_projects`, and with a missing file → exit
  2 before any `gh pr list` call (D12, AC9).
- I9 Helper missing from the fixture, and a stub helper that exits 0 without
  an outcome line → unavailable handling, existing handoff, exit 1 (D11).

**Regression**: the existing GitHub parity section (V4) and every other case
in the cleanup suite pass unchanged (AC9); the merge-budget suites in the
Rule 5 table pass unchanged.

**Smoke test runbook**: `docs/testing/workflow/2009-linear-release-verification.smoke-test.md`

### Parser-risk addendum

The evaluator parses a structured JSON file, so this addendum applies.

- **Edge-case enumeration**: non-JSON text; JSON that is an array or lacks
  `reads`; `reads` that is not an array; a read that is not an object;
  `labels` that is a string instead of an array or contains a non-string;
  `observedAt` with `Z`, with `+00:00`, with a non-UTC offset, without an
  offset, empty, and not a date; identifiers that look like Linear IDs but do
  not match V13 (`LEA_1`, `-1`, `LEA-`); identifiers in lower case; a team key
  that is a prefix of the owning key (`LE` for `LEA-1`); multi-hyphen team
  derivation (`AB-CD-12` → team `AB-CD`); status and label values containing
  quotes, spaces or newlines; duplicate identical reads (same instant, same
  state — not a conflict).
- **Unit test mapping**: all in
  `scripts/development-workflow/tests/test-linear-release-verification.sh`:
  shape errors → U7; per-read type errors and timestamp forms → U5 (one
  assertion per form); identifier and case forms → U8 and U14; team-prefix and
  multi-hyphen derivation → U5; value injection → U13; duplicate identical
  reads → U9.
- **Suppression semantics**: not applicable — the format has no directives.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Read-back files | Per U and I case, written by the suites into temporary directories | Created at test runtime |
| First-run record | Fixed `firstRunStartedAt` for cases needing a known starting point | Created at test runtime in the fixture's git directory |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
  — §9.2 adds the optional `--linear-readback` flag; §9.4 Linear bullet
  describes the read-back, the per-item results and the label action item;
  §9.5 states that a Linear release is complete only when cleanup reports
  `LINEAR_RELEASE_OUTCOME=complete`, and that `--best-effort` keeps it
  Incomplete.
- [ ] `docs/workflow/development-workflow/integrations/linear.md` — Release
  Stamping: the D2 schema with one example, how to read items independently,
  the starting point and its local scope (D6), that every run evaluates only
  the reads supplied to it, so a re-run supplies reads for every in-scope item
  and not only the fixed ones (spec BR11), the outcome lines (D8), and that
  release-field projects keep the existing handoff.
- [ ] `scripts/development-workflow/README.md` — the cleanup entry gains the
  flag and the Complete/Incomplete meaning; add an entry for
  `linear-release-verification.py`.
- [ ] `.claude/commands/prepare-release.md`, `.cursor/commands/prepare-release.md`,
  `.agents/skills/prepare-release/SKILL.md` — the Linear handoff sentence
  states that the release is complete only when cleanup reports Complete from
  the supplied read-back.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Clock skew makes a fresh read look future-dated | Low | Low | Fails closed as `unreadable`; operator re-reads and re-runs (D4) |
| State kept per clone: a different clone has no first-run record | Med | Low | Fails closed (current run becomes the start, earlier reads are stale); documented in `linear.md` (D6) |
| Operator normalizes a read wrongly | Med | Med | Every mismatch is named per item; the record keeps the verbatim read-back for review (D10) |
| Existing Linear tests change output | Low | Low | Only new lines are added; exits and asserted lines are unchanged (Rule 5 table) |
| Read-back content forges output lines | Low | High | JSON-encoded values (D8), checked by U13 |

---

## Code Samples

None. D2's field list is the normative schema; the `linear.md` example is
written during implementation.

---

## Implementation Order

1. Write `linear-release-verification.py` (L1).
2. Write `test-linear-release-verification.sh` (L3, U1–U14) and make it pass.
3. Wire the cleanup script (L2).
4. Add the integration section and `# covers:` header (L3, I1–I9).
5. Update the documentation (L4).
6. Run, and confirm each passes: the two suites above,
   `test-workflow-merge-budget.sh` and its parts,
   `python3 scripts/development-workflow/tests/test_workflow_merge_budget.py`,
   `bash scripts/development-workflow/select-test-suites.sh --report-gaps`
   (no gap for the new helper), the markdown lint commands from `AGENTS.md`,
   and `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
7. Walk the smoke runbook.
8. Add `changelog.d/2009.fixed.linear-release-verification.md` with this body:

   ```markdown
   - **Verify Linear release completion from tracker read-back** (#2009): Linear release cleanup now reports Complete only when an independent read of every in-scope item shows the release label (including hotfix versions) and the Released status; otherwise it reports Incomplete, names each item with what is missing and flags a missing release label as an action item. GitHub Projects and GitHub Issues release cleanup is unchanged.
   ```
