# Local AI Reviewer: Claude Backend — Spec

## Overview

The local AI reviewer (the `local-ai-reviewer` review platform) runs a
repository-local review of a pull request and reports a verdict to the
reviewer loop. Today its bundled presets need either the Codex CLI (the
default) or an HTTP Chat Completions API key. A maintainer whose Codex access
is reduced or gone cannot run the local reviewer, and in a repository where it
is the ready-phase reviewer, no pull request can reach human review.

This feature adds a third bundled backend, `claude`, which runs the review
through the Claude Code CLI on the developer's existing Claude login. The
review is read-only and runs on a throwaway copy of the reviewed commit. The
feature also lets a repository choose its default backend in shared workflow
configuration instead of patching the script, and gives the Claude backend a
review budget long enough for one Claude pass. The built-in default stays
`codex`, so a consumer that does not opt in sees no change.

## Alignment Record

This run was unattended. The tracker brief (#1957) and the owner's run
instructions are the alignment input. The owner asked that the per-preset
budget, the configurable default backend, and the related observations each be
decided here, either in scope or deferred. The decisions are recorded below as
business rules and out-of-scope deferral notes. The spec-dispatch context
reported no confirmed decisions, no peer relationships, and nothing blocking.

The owner's constraints are binding product constraints:

- The local reviewer and the ready-phase reviewer must be able to run without
  Codex.
- The built-in default backend stays `codex` for every consumer that does not
  opt in.
- Existing settings keep their current meaning: the explicit reviewer command,
  the backend environment selection, the reviewer timeout setting, the
  `--timeout` option, and the reviewer loop's documentation-branch wait.
- Any change that could break a consumer is out of scope or called out as high
  risk.

## Brief Objective List

- **BO-1**: Add a `claude` backend that resolves to a new bundled Claude Code CLI preset when no explicit reviewer command is set.
- **BO-2**: The preset reviews a throwaway, detached copy of the pull request head. It runs the CLI without user or project settings, without MCP servers, without session persistence, and with read-only file tools only.
- **BO-3**: The reviewer has no shell; the diff is precomputed into a file inside the review copy.
- **BO-4**: The preset refuses an empty diff or a diff that cannot be computed.
- **BO-5**: The preset checks that the review copy is unchanged after the run.
- **BO-6**: The preset accepts only a JSON object whose result is `clean` or `needs_fixes` (or, in strict mode, the expected strict marker), and stamps the reviewed head itself.
- **BO-7**: A per-preset default budget: about 900 s for a Claude pass. It applies only when neither `--timeout` nor `LOCAL_AI_REVIEWER_TIMEOUT` chose a value.
- **BO-8**: Raise the reviewer loop's documentation-branch default wait to 900 s while `local-ai-reviewer` is a configured platform and `PR_REVIEW_LOOP_DOC_MAX_WAIT` is not a valid number.
- **BO-9**: Decide whether the default backend is configurable in shared workflow configuration (for example `review.local_ai_reviewer.backend`), so a consumer does not patch the script.
- **BO-10** (observation): When `local-ai-reviewer` is the only ready-phase platform, the loop runs it twice on a head the ledger has not seen. Replaying the same-run local pass for the ready-phase dispatch would halve the cost.
- **BO-11** (observation): `test-apply-readiness-labels.sh` lets a developer's private local configuration, found through the main clone from a linked worktree, replace the mocked base policy, so 77 cases fail locally.
- **BO-12** (observation): `local-ai-reviewer.sh` infers `clean` from a verdict object that has a findings array and no result.
- **BO-13** (observation): The unknown-backend error text is asserted verbatim by `test-local-http-review-command.sh`, so adding a backend name to it would break that test.

## Coverage Matrix

| Objective | Disposition | Where |
| --- | --- | --- |
| BO-1 | In scope | AC-1, AC-2, AC-3; BR-1, BR-2 |
| BO-2 | In scope | AC-12, AC-13; BR-9, BR-10 |
| BO-3 | In scope | AC-12, AC-13; BR-10 |
| BO-4 | In scope | AC-14; BR-11 |
| BO-5 | In scope | AC-15; BR-12 |
| BO-6 | In scope | AC-16, AC-17; BR-13, BR-14 |
| BO-7 | In scope | AC-9, AC-10; BR-6, BR-7 |
| BO-8 | Out of scope: superseded by #1789 | Out of Scope DN-1; regression guard AC-11 |
| BO-9 | In scope (decided: yes) | AC-4, AC-5, AC-6, AC-7, AC-8; BR-3, BR-4, BR-5 |
| BO-10 | Out of scope: separate follow-up | Out of Scope DN-2 |
| BO-11 | Out of scope: separate follow-up | Out of Scope DN-3 |
| BO-12 | Out of scope for the shared parser; the Claude preset is not exposed to it | Out of Scope DN-4; AC-16 |
| BO-13 | In scope as a constraint: the diagnostic does not change | AC-7; BR-5 |

## Use Cases

### Use Case 1: A maintainer selects the Claude backend for their machine

**Actor**: A maintainer or orchestration runner who runs the reviewer loop or
the local reviewer on their own machine.

**Preconditions**: The Claude Code CLI is installed and logged in for this
user. No explicit reviewer command is set. The repository may or may not
configure a shared default backend.

**Steps**:

1. The maintainer sets the backend environment selection to `claude` for
   their shell or runner environment.
2. They run the reviewer loop on a pull request (or run the local reviewer
   directly).
3. The local reviewer reports that it is using the bundled Claude preset and
   runs one read-only Claude review of the reviewed commit.

**Postconditions**: The loop receives a verdict for the reviewed commit, or a
reviewer-failure or no-verdict-yet outcome. Codex is never invoked.

**Information shown**: A diagnostic line naming the Claude preset. When the
direct run applies the Claude default budget, a line naming that budget. The
verdict, the reviewed commit, and the counts of blocking and advisory findings.

**Actions available**: Accept the verdict, address the findings, or choose a
different backend or command for the next run.

**Considerations**: The environment selection overrides any shared default
for this run only (BR-3).

### Use Case 2: A repository makes Claude its shared default backend

**Actor**: A repository owner who edits the repository's shared workflow
configuration.

**Preconditions**: The repository uses `local-ai-reviewer` as a draft or
ready-phase platform.

**Steps**:

1. The owner sets the shared default backend to `claude` in the
   repository's workflow configuration and merges that change to the base
   branch.
2. Later reviewer-loop runs on pull requests against that base use the
   Claude preset for every contributor who has not set an environment
   selection or an explicit command.

**Postconditions**: Contributors get the Claude backend without patching any
script. A contributor who sets their own environment selection still gets
the backend they chose.

**Information shown**: The same diagnostic line as Use Case 1.

**Actions available**: Revert or change the shared default. Individual
contributors can override it with the environment selection.

**Considerations**:

- A pull request that adds or changes the shared default does not choose its
  own reviewer. The loop reads the base branch's configuration, so the change
  takes effect after merge (BR-4).
- An invalid shared value stops the review as a configuration failure. It
  does not silently fall back to another backend (BR-5).

### Use Case 3: The Claude review cannot produce a trustworthy verdict

**Actor**: The local reviewer, acting for the maintainer or runner.

**Preconditions**: The Claude backend was selected.

**Steps**: One of these happens: the CLI is missing or not logged in, the
usage limit is exhausted, the provider reports it is over capacity, the review
copy cannot be created, the diff is empty or cannot be computed, the CLI
changes a file in the review copy, the CLI returns no usable verdict, or the
budget runs out.

**Postconditions**: The outcome is a reviewer failure, No verdict yet when
the budget ran out, or Needs rerun when the reviewer's existing capacity rule
applies. It is never Clean. The maintainer's checkout is unchanged.

**Information shown**: A diagnostic that names the cause: missing CLI (with
the setting that points at another CLI binary), review copy not created, CLI
exit status, refused
empty or uncomputable diff, review copy modified, or missing or invalid
verdict. Private values are redacted under the repository's existing
diagnostic rules.

**Actions available**: Fix the cause and re-run the loop, or select another
backend.

**Considerations**: A usage-limit or capacity message from the CLI is
classified by the reviewer's existing quota and capacity rules: an exhausted
quota is Reviewer failed, and a capacity message is retried and can end as
Needs rerun, as for the other presets. The Claude preset adds no separate
classification.

## Configuration Contract

These names are the user-facing configuration of a developer tool. Operators
type them, consumers already depend on them, and the brief names them. They
are part of the product contract.

- **Backend names**: `codex` (built-in default), `http` (with the deprecated
  alias `openai_compat`), and the new `claude`.
- **Environment selection**: `LOCAL_AI_REVIEWER_BACKEND` accepts the backend
  names above. Its meaning is unchanged.
- **Shared default**: `review.local_ai_reviewer.backend` in
  `.ai-dev-workflow.yaml` accepts the same names as the environment selection.
- **Claude preset settings**: `LOCAL_CLAUDE_REVIEWER_BIN` selects the CLI
  binary (default `claude`). `LOCAL_CLAUDE_REVIEWER_MODEL` is an optional
  model; when unset, the CLI's own default model is used.
  `LOCAL_CLAUDE_REVIEWER_PROMPT` overrides the ordinary-pass prompt and
  `LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT` overrides the strict-pass prompt.
  These mirror the Codex preset's settings. They also match the names a
  consumer (MOME) already uses for its local patch, so that consumer can
  adopt the template preset without renaming its environment.
- **Claude default budget**: 900 s.
- **Unchanged meanings**: `LOCAL_AI_REVIEWER_COMMAND`,
  `LOCAL_AI_REVIEWER_DISABLE_DEFAULT`, `LOCAL_AI_REVIEWER_DISABLED`,
  `LOCAL_AI_REVIEWER_TIMEOUT`, `--timeout`, `PR_REVIEW_LOOP_DOC_MAX_WAIT`, and
  `review.wait_budgets.local-ai-reviewer`.

## Business Rules

1. **BR-1 Default unchanged.** With no explicit command, no environment
   selection, and no shared default, the local reviewer uses the Codex preset
   exactly as it does today, with the same standalone budget (300 s).
2. **BR-2 New backend.** The backend name `claude` resolves to the bundled
   Claude preset. The diagnostic line that names the selected preset says
   `Claude` the way it says `Codex` or `HTTP` today.
3. **BR-3 Backend precedence.** The reviewer command is chosen in this order.
   The first rule that applies wins:
   1. An explicit reviewer command is used as is. No preset and no backend
      setting apply.
   2. Disabling the bundled default leaves no command. The run escalates as
      `missing_command`, as it does today.
   3. A non-empty environment selection chooses the backend.
   4. A non-empty shared default chooses the backend.
   5. Otherwise the backend is `codex`.

   An empty environment selection or an empty or absent shared default counts
   as not set. Disabling the reviewer (`LOCAL_AI_REVIEWER_DISABLED=1`) is
   checked before any of this and still reports Skipped.
4. **BR-4 Configuration source.** The shared default is read from the same
   workflow configuration the local reviewer receives for the run. Under the
   reviewer loop, that is the pull request base branch's configuration
   snapshot the loop already uses for reviewer settings. When the reviewer
   runs directly, it is the repository's workflow configuration. If the
   configuration is missing, unreadable, or cannot be parsed, the shared
   default counts as not set, which preserves today's Codex behavior; a
   parseable value that is not a string backend name is invalid (BR-5). The
   private local workflow configuration is never a source for the shared
   default, even where it overrides other reviewer settings (DN-5).
5. **BR-5 Invalid backend.** An unknown backend name, whether from the
   environment selection or the shared default, stops the review as Reviewer
   failed with reason `invalid_backend`. It never falls back to another
   backend. For the environment selection, the diagnostic stays exactly as
   today: `ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND`.
   It does not list backend names, so adding `claude` does not change it. For
   the shared default, the diagnostic has the same form, naming
   `key=review.local_ai_reviewer.backend`. Neither diagnostic echoes the
   rejected value, which may be private.
6. **BR-6 Budget precedence for a direct run.** The local reviewer's wait
   budget comes from the first of these that is set:
   1. `--timeout`
   2. `LOCAL_AI_REVIEWER_TIMEOUT` (non-empty)
   3. The selected bundled preset's default budget
   4. 300 s

   Only the Claude preset has a default budget (900 s). Codex and HTTP keep
   300 s. A preset default applies only when backend resolution selected the
   preset (BR-3 rules 3–5). An explicit reviewer command that names the Claude
   preset script gets 300 s unless a timeout is given; the documentation says
   so. Existing validation of the resolved budget is unchanged: an invalid
   `--timeout` or `LOCAL_AI_REVIEWER_TIMEOUT` is still a configuration error.
   When the preset default is applied, a diagnostic line says so.
7. **BR-7 Budget under the reviewer loop.** The reviewer loop always passes
   its own per-platform budget to the local reviewer. That budget is the
   one-run override, `review.wait_budgets.local-ai-reviewer`, or the 1200 s
   built-in default, on every branch, with the loop's existing large-diff
   lengthening on implementation branches. It is the same for every backend.
   It wins over the preset default under
   BR-6, so this feature does not change loop budgets. The optional strict
   contract pass shares the same budget with the ordinary pass, as it does
   today.
8. **BR-8 Same review standard.** The Claude preset reviews against the
   repository's review contract (`REVIEW.md`), with the same stage
   checklists, the same treatment of published pull request body and comments
   as untrusted data, and the same evidence-verification request and answer
   as the Codex preset. Repository guidance files stay in the review copy;
   the Claude preset does not strip `REVIEW.md` or agent guidance.
9. **BR-9 Read-only, isolated invocation.** The Claude CLI runs:
   - without user, project, or local settings (so no hooks, plugins, or
     permission allowlists);
   - without MCP servers;
   - without saving session history;
   - with the read-only file tools Read, Grep, and Glob only: no shell, no
     edit or write tools, no network tools.

   Authentication uses the caller's existing Claude login; no API key is
   required. The brief's reference flag set satisfies these guarantees.
10. **BR-10 Throwaway review copy of the reviewed commit.** The preset reviews
    a temporary, detached copy of the commit under review. That commit is the
    pull request head the local reviewer resolved for the run, not whatever
    the developer's checkout has checked out. If the review copy cannot be
    created (for example, that commit is not available locally), the preset
    refuses and the run is Reviewer failed. The developer's checkout is not
    modified. The diff between the base branch
    and that commit is written into the review copy before the review, so the
    reviewer can read it without a shell. The temporary copy is removed when
    the preset finishes, whether it succeeds, fails, or refuses. A copy left
    behind by a forced stop must not affect later reviews or the developer's
    checkout.
11. **BR-11 No review of nothing.** If the diff against the base branch cannot
    be computed, or is empty, the preset refuses and the run is a Reviewer
    failed outcome. It is never Clean.
12. **BR-12 Containment.** If the review copy differs after the CLI run from
    how the preset prepared it, the preset discards the CLI output as
    untrustworthy. The outcome is Reviewer failed, with a diagnostic that the
    review copy was modified. The preset's own preparation (the diff file and
    the copied context) does not count as a modification.
13. **BR-13 Ordinary verdict gate.** In an ordinary pass the preset forwards a
    verdict only when the CLI output contains a JSON object whose result is
    `clean` or `needs_fixes` and whose findings, if present, are a list. The
    forwarded verdict names the commit the preset actually reviewed,
    whatever head the model reported or omitted. Other fields, including the
    evidence-verification answer, pass through unchanged. Output with no JSON
    object, invalid JSON, a missing or other result, or non-list findings is
    Reviewer failed. It is never inferred as Clean.
14. **BR-14 Strict pass gate.** In a strict contract pass the preset requires
    a context bundle, and it requires the response's mode marker to match the
    strict check being applied (spec or plan, from the context bundle). It
    forwards findings without a verdict or reviewed head, in the shape the
    Codex preset uses. A missing context bundle, a wrong or missing marker, or
    non-list findings is a refusal, which the reviewer reports as the strict
    check being unavailable, as today. Neither strict findings nor a strict
    refusal ever change the ordinary verdict.
15. **BR-15 CLI failures.** A missing CLI binary, a non-zero CLI exit, a
    missing login, or an exhausted usage limit is Reviewer failed. A bounded
    excerpt of the CLI's failure message is surfaced, whether the CLI wrote it
    to its error output or its standard output, so the reviewer's existing
    credential, quota, and capacity classification applies; under that
    existing classification a capacity message is retried and can end as
    Needs rerun rather than Reviewer failed. A budget that
    runs out while the CLI is still running is No verdict yet, through the
    existing watchdog.
16. **BR-16 Independence caveat.** Documentation states that a Claude
    reviewer may share a model family with the agents that wrote the change,
    so a Clean result is weaker independent evidence. Human review keeps its
    weight. This is guidance only; no gate changes.
17. **BR-17 Consumer migration note.** A consumer that patched the script
    locally to add a Claude backend or to change the default (MOME issue 3814)
    gets a migration note. It explains how to keep the Claude backend after
    syncing by setting the shared default to `claude`, which reviewer-loop
    budget patch the template already makes unnecessary (DN-1), and the
    differences from the patch: the template keeps `REVIEW.md` in the review
    copy, and uses the CLI's default model unless one is configured.

## Decision Matrices

### Backend resolution

The rows are evaluated top to bottom. The first matching row wins, so rows
never conflict.

| # | Reviewer disabled | Explicit command | Default disabled | Environment selection | Shared default | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | yes | any | any | any | any | Skipped (`disabled_by_config`) |
| 2 | no | set | any | any | any | Explicit command; 300 s unless a timeout is given |
| 3 | no | unset | yes | any | any | Reviewer failed (`missing_command`) |
| 4 | no | unset | no | known name | any (not read) | That backend's preset |
| 5 | no | unset | no | unknown name | any (not read) | Reviewer failed (`invalid_backend`), environment key diagnostic |
| 6 | no | unset | no | unset or empty | known name | That backend's preset |
| 7 | no | unset | no | unset or empty | unknown name | Reviewer failed (`invalid_backend`), shared-default key diagnostic |
| 8 | no | unset | no | unset or empty | unset, empty, or configuration missing, unreadable, or unparseable | Codex preset |

### Direct-run budget

The rows are evaluated top to bottom. The first matching row wins.

| # | `--timeout` | `LOCAL_AI_REVIEWER_TIMEOUT` | Command source | Budget |
| --- | --- | --- | --- | --- |
| 1 | given | any | any | `--timeout` (validated as today) |
| 2 | not given | non-empty | any | That value (validated as today) |
| 3 | not given | unset or empty | Claude preset chosen by backend resolution | 900 s, with a diagnostic line |
| 4 | not given | unset or empty | Any other source (Codex, HTTP, explicit command) | 300 s |

Under the reviewer loop, row 1 always applies, because the loop passes its
per-platform budget (BR-7).

### Claude preset outcomes

Checks run in the order listed. The first failing check decides the outcome.

| # | Condition | Outcome class | Display label |
| --- | --- | --- | --- |
| 1 | CLI binary not found | Reviewer failed | Reviewer failed |
| 2 | Strict pass without a context bundle | Strict check unavailable (see below) | (strict report) |
| 3 | Review copy of the reviewed commit cannot be created | Reviewer failed | Reviewer failed |
| 4 | Diff cannot be computed or is empty | Reviewer failed | Reviewer failed |
| 5 | The preset was still running when the budget ran out | No verdict yet | No verdict yet |
| 6 | Review copy modified after the run | Reviewer failed | Reviewer failed |
| 7 | CLI exited non-zero (including login, usage-limit, or capacity failures) | Classified by the existing credential, quota, and capacity rules: Reviewer failed, or Needs rerun when capacity stays unavailable after the existing retries | Reviewer failed or Needs rerun |
| 8 | No JSON object, invalid JSON, invalid result or marker, or non-list findings | Reviewer failed | Reviewer failed |
| 9 | Valid ordinary verdict `clean` | Clean (after the reviewer's existing blocking-finding rules) | Clean |
| 10 | Valid ordinary verdict `needs_fixes` | Needs fixes (after existing rules) | Needs fixes |
| 11 | Valid strict response | Strict findings reported; the ordinary verdict is unchanged | (strict report) |

The budget check (row 5) is applied by the local reviewer's watchdog, which
can stop the preset at any point. When it does, row 5 decides the outcome
whatever stage the preset had reached, and the stopped run's partial output
is not inspected. Rows 6–11 apply only to a run that finished within the
budget.

The outcome classes in rows 1 and 3–10 are those of an ordinary pass. In a
strict contract pass, any failing check (rows 1–8) is reported through the
reviewer's existing strict-pass failure report: the strict check is
unavailable (`strict_pass_failed`), and the ordinary verdict is unchanged. A
strict pass never produces Reviewer failed, No verdict yet, or Needs rerun on
its own. Row 11 is the only strict success.

## Statuses / Enum Values

This feature adds no outcome. The Claude preset reports through the
local reviewer's existing outcomes.

| Code value | Display label | Description |
| --- | --- | --- |
| `clean` | Clean | The reviewed commit has no blocking findings. |
| `needs_fixes` | Needs fixes | Blocking findings were reported for the reviewed commit. |
| `needs_rerun` | Needs rerun | Existing outcome: the provider stayed over capacity after the reviewer's existing retries, or review evidence changed during the review. Never counted as Clean. |
| `escalate` | Reviewer failed | Setup, configuration, refusal, containment, CLI, or verdict-shape failure. Never counted as review evidence. |
| `waiting_on_reviewer` | No verdict yet | The budget ran out while the reviewer was still running. Not a failure. |
| `skipped` | Skipped | The reviewer was disabled by configuration. |

**Valid transitions**: none are introduced. Each run produces one outcome for
one reviewed commit.

## Operational Visibility

- **Logs**: Diagnostic lines name the selected preset and say when the Claude
  default budget was applied. They name each refusal or failure cause from
  the preset outcome table. All diagnostics follow the repository's existing
  diagnostic and redaction rules, and none echo a rejected backend value.
- **Notifications**: none beyond the reviewer loop's existing reporting.
- **Audit trail**: the reviewer's existing evidence artifact records the
  outcome and the reviewed commit. The backend adds no new artifact.

## Acceptance Criteria

Every criterion can be verified without a real Claude login. The tests use
a stand-in CLI selected through the binary setting, which records its
arguments and the prompt and returns scripted output.

- [ ] **AC-1** With the environment selection set to `claude` and no explicit
  command, the local reviewer runs the Claude preset. Its diagnostic names the
  Claude preset, and the Codex binary is never invoked.
- [ ] **AC-2** With no explicit command, no environment selection, and no
  shared default, the Codex preset runs and the direct-run budget is 300 s,
  matching current behavior. Existing Codex and HTTP preset tests pass
  unchanged.
- [ ] **AC-3** With an explicit reviewer command set, that command runs no
  matter what the environment selection or shared default says. With the
  bundled default disabled and no command, the run reports Reviewer failed /
  `missing_command`, even when the shared default is `claude`.
- [ ] **AC-4** With the shared default set to `claude` and no environment
  selection, the Claude preset runs. With the shared default `claude` and the
  environment selection `http`, the HTTP preset runs. An empty environment
  selection does not override the shared default.
- [ ] **AC-5** The shared default accepts `codex`, `http`, `openai_compat`, and
  `claude`, with the same meaning as the environment selection. An absent or
  empty key, or a missing or unparseable configuration file, gives the Codex
  preset. A non-string value (for example a list) gives Reviewer failed /
  `invalid_backend`. A backend value placed in the private local workflow
  configuration is ignored: with no environment selection and no shared
  default, the Codex preset runs.
- [ ] **AC-6** Under the reviewer loop, a pull request whose own branch adds
  `review.local_ai_reviewer.backend: claude`, against a base branch without
  it, is reviewed with the backend the base configuration selects. After the
  change is on the base branch, later pull requests use the Claude preset.
- [ ] **AC-7** An unknown environment selection gives Reviewer failed /
  `invalid_backend`. The diagnostic is exactly
  `ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND`, so
  the existing verbatim assertion in `test-local-http-review-command.sh`
  passes unchanged. An unknown shared default gives Reviewer failed /
  `invalid_backend` with the same diagnostic form naming
  `review.local_ai_reviewer.backend`. In both cases the rejected value never
  appears in output, and no other backend runs.
- [ ] **AC-8** The help text, the commented reviewer options in
  `.ai-dev-workflow.yaml`, the local AI reviewer integration guide, and the
  local-ai-reviewer comment in the PR review platform integration guide list
  `claude`, the shared default key, the precedence in BR-3, and the Claude
  preset settings.
- [ ] **AC-9** In a direct run of the Claude preset chosen by backend
  resolution, with no `--timeout` and no `LOCAL_AI_REVIEWER_TIMEOUT`, the
  budget is 900 s and a diagnostic line says so. With `--timeout 120`, the
  budget is 120 s. With `LOCAL_AI_REVIEWER_TIMEOUT=600`, the budget is 600 s.
  An invalid value for either still exits as a configuration error.
- [ ] **AC-10** Codex and HTTP direct runs without a timeout keep 300 s. An
  explicit reviewer command that names the Claude preset script, without a
  timeout, gets 300 s, and the integration guide documents setting a timeout
  in that case.
- [ ] **AC-11** Under the reviewer loop, local-ai-reviewer's budget on
  `spec/*`, `implementation-plan/*`, and implementation branches is the same
  for every backend: the one-run override, the configured
  `review.wait_budgets.local-ai-reviewer`, or 1200 s (lengthened by the
  existing large-diff adjustment on implementation branches only). The
  documentation-branch
  shortening still applies only to Devin, and `PR_REVIEW_LOOP_DOC_MAX_WAIT`
  keeps its current meaning.
- [ ] **AC-12** The stand-in CLI records that it was started with no settings
  sources, no MCP servers (strict MCP configuration with none supplied), no
  session persistence, and only the Read, Grep, and Glob tools available and
  allowed. It was started inside
  a temporary copy of the reviewed commit, not inside the developer's
  checkout.
- [ ] **AC-13** Inside the review copy, the stand-in CLI can read the diff file
  for base...reviewed commit and the copied context bundle. The developer's
  checkout status is identical before and after the run. The temporary copy
  is gone after a successful run, a failed run, and a refusal.
- [ ] **AC-14** If the diff against the base branch is empty, or cannot be
  computed against either the remote or the local base branch, the run is
  Reviewer failed, with a diagnostic naming the refusal. The stand-in CLI is
  not invoked.
- [ ] **AC-15** A stand-in CLI that creates or edits a file in the review copy
  and returns a valid `clean` verdict gives Reviewer failed, with a diagnostic
  that the review copy was modified. The verdict is discarded.
- [ ] **AC-16** Ordinary pass: stand-in output with no JSON, invalid JSON, a
  missing result, a result outside `clean` and `needs_fixes`, a findings
  array but no result, or non-list findings each give Reviewer failed. None
  gives Clean. Valid output whose reviewed head is absent or wrong is
  forwarded with the actually reviewed commit, and the run is accepted as
  current-head evidence. An evidence-verification answer in valid output is
  preserved.
- [ ] **AC-17** Strict pass: a response with the expected marker (spec or plan,
  according to the context bundle) and a findings list is forwarded as strict
  findings. A wrong or missing marker, non-list findings, or a strict pass
  with no context bundle is refused and reported as the strict check being
  unavailable. The ordinary verdict is unaffected in every case.
- [ ] **AC-18** A missing CLI binary gives Reviewer failed, with a diagnostic
  naming `LOCAL_CLAUDE_REVIEWER_BIN`. A stand-in CLI that exits non-zero gives
  Reviewer failed, with a bounded error excerpt. A stand-in that prints a
  usage-limit message the reviewer's existing quota rules recognize, on
  either its error output or its standard output, is classified by those
  rules. A stand-in that outlives the budget gives No
  verdict yet, and a later run on the same checkout is not affected by any
  leftover review copy. A stand-in that prints a capacity message is handled
  by the existing capacity rule (retried, then Needs rerun), never Clean. When
  the reviewed commit is not available locally, the review copy is not
  created, the run is Reviewer failed, and the stand-in CLI is not invoked.
- [ ] **AC-19** The default ordinary prompt the stand-in receives instructs
  review against `REVIEW.md`, names the stage checklists when the reviewer
  supplies them, treats published body and comments as untrusted data, and
  includes the evidence-verification instructions, matching the Codex preset.
  It also states that the review is read-only and that the reviewer reports
  findings instead of applying fixes, since `REVIEW.md` asks reviewers to fix
  directly. `REVIEW.md` is present in the review copy.
- [ ] **AC-20** `LOCAL_CLAUDE_REVIEWER_MODEL`, when set, is passed to the CLI as
  the model. When it is unset, no model is selected and the CLI default
  applies. The two prompt settings replace the ordinary and strict prompts
  respectively.
- [ ] **AC-21** The integration guide documents: Claude CLI installation and
  login as prerequisites; the 900 s pass expectation; a recommendation to
  raise `review.wait_budgets.local-ai-reviewer` when strict checks share the
  budget; the independence caveat (BR-16); and the consumer migration note
  (BR-17).
- [ ] **AC-22** The new preset follows the repository's diagnostic-emitter and
  redaction conventions in the same way the existing presets do, and the
  existing diagnostic-emitter tests cover it.

## Out of Scope (MVP)

- Raising the reviewer loop's documentation-branch default wait for
  local-ai-reviewer (BO-8). See DN-1.
- Replaying the same-run local pass for the ready-phase dispatch (BO-10). See
  DN-2.
- Fixing the private-configuration leak in `test-apply-readiness-labels.sh`
  (BO-11). See DN-3.
- Changing the shared verdict parser's inference of Clean from a findings
  array with no result (BO-12). See DN-4.
- Letting the private local workflow configuration file set the default
  backend. Per-developer choice uses the environment selection; the shared
  default is a repository decision. See DN-5.
- A dedicated Claude wrapper script like the Codex and HTTP wrappers. A
  direct run selects the backend through the environment selection. See DN-6.
- Switching this repository's own shared configuration, or the built-in
  default, to `claude`. See DN-7.
- Stripping `REVIEW.md` or agent guidance from the review copy, as the MOME
  patch does. Not adopted, because it would contradict BR-8.
- Pinning a default Claude model, posting inline comments, or any change to
  the Codex or HTTP presets.

### Deferral Notes

- **DN-1 — BO-8, documentation-branch wait of 900 s.** Rationale: the brief
  describes a consumer patch made before per-platform wait budgets (#1789).
  In this template the loop no longer shortens local-ai-reviewer on
  documentation branches. Only Devin is shortened, and local-ai-reviewer
  gets its own 1200 s default or configured budget on every branch, which is
  already above the 900 s Claude pass. Changing it would alter
  `PR_REVIEW_LOOP_DOC_MAX_WAIT` semantics for every consumer for no gain.
  AC-11 guards the current behavior. Human confirmation: not requested.
- **DN-2 — BO-10, replay the local pass for the ready-phase dispatch.**
  Rationale: this changes the #1656 second-pass and ready-phase evidence
  contract for every backend and every consumer, not only Claude. It needs
  its own decision matrix for head drift, stale evidence, and failed-for-head
  records. It is a worthwhile cost cut and should be filed as a separate
  item. Human confirmation: requested, to file the follow-up item.
- **DN-3 — BO-11, test isolation leak.** Rationale: this is a test hermeticity
  defect in readiness-label tests. It shows only on machines that have a
  private local configuration, and it is unrelated to backend selection. It
  belongs in its own bug item so the fix can be proven against a planted
  local configuration. Human confirmation: requested, to file it as a Bug.
- **DN-4 — BO-12, inferred Clean without a result.** Rationale: custom
  reviewer commands in consumer repositories may rely on the current
  inference, so changing the shared parser could turn their Clean results
  into failures, a consumer-breaking change. The Claude preset is not exposed
  to it, because it never forwards a verdict without an explicit result
  (BR-13, AC-16). It should be a separate, announced change. Human
  confirmation: requested.
- **DN-5 — Private local configuration for the backend.** Rationale: the
  environment selection already gives per-developer control. Adding a third
  source widens the precedence contract with no stated need. Human
  confirmation: not requested.
- **DN-6 — Claude wrapper script.** Rationale: not in the brief. Backend
  resolution covers direct runs, and a wrapper that set an explicit command
  would bypass the Claude default budget (BR-6). Human confirmation: not
  requested.
- **DN-7 — Make `claude` this repository's or the template's default.**
  Rationale: the owner requires `codex` to remain the default for anyone who
  does not opt in. The repository configuration file is project-owned and is
  not overwritten by template sync. However, projects created from this
  template start from a copy of it, so switching it here would opt new
  projects in silently. The owner can opt in now with the environment
  selection, or decide on a one-line configuration change after this
  feature merges. Human confirmation: requested.

## Consumer Impact

- **No-opt-in consumers**: no behavior change (BR-1, AC-2, AC-11).
- **Consumers with a local Claude patch (MOME)**: after sync, the script patch
  is replaced, and the default returns to `codex` unless they set the shared
  default to `claude` (BR-17). This is the highest-risk path and is covered by
  the migration note. Their `LOCAL_CLAUDE_REVIEWER_*` settings keep working.
  Their loop-budget patch is unnecessary (DN-1). Two behavior differences
  remain: `REVIEW.md` stays in the review copy, and the CLI's default model is
  used unless they set the model.
- **Strict-check budget**: on `spec/*` and `implementation-plan/*` branches the
  strict pass shares the 1200 s loop budget with an ordinary Claude pass of
  about 900 s. The strict pass may get too little time. The documentation
  recommends a larger `review.wait_budgets.local-ai-reviewer` for the Claude
  backend (AC-21). The default budget is not changed.
