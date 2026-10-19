# Private runner configuration isolation — Spec

**Issue**: #1993

## Overview

Workflow operators must be able to run an item in an isolated checkout without
silently using private configuration from another checkout. This correction
requires explicit consent for an external configuration source, safe diagnostics,
and prevention controls that keep private data out of runner output and review
handoffs. Consumers upgrading the framework receive a migration note explaining
how to replace reliance on automatic inheritance.

## Confirmed Scope

Luis authorized the full spec, plan, and implementation pipeline for this security
fix. Each PR may merge only after a low risk classification, green CI, no open
review threads, and recorded disposition. Protocol scripts may use private local
configuration normally; the agent must not open it manually or expose its values.
Tests use synthetic data exclusively. No other backlog item or release is included.

There are no supplied design assets or UI changes. The downstream correction in
[hub PR #243](https://github.com/BaumAPPADM/legacy-platform-dev-workflow-hub/pull/243)
is reference evidence, not a substitute for these acceptance criteria. Its stated
deferral of generic output redaction does not defer that objective in this item.

## Use Cases

### Use Case 1: Run from an isolated checkout

**Actor**: Workflow operator or an agent acting on the operator's instruction.

**Preconditions**: A repository has a primary checkout and an isolated checkout.
Only the primary checkout has private local configuration.

**Steps**:

1. The operator starts a workflow helper in the isolated checkout.
2. The helper selects the current checkout's shared configuration and any private
   local configuration present in that checkout.
3. When no current local configuration is available, the helper continues with
   shared settings if its existing contract permits that, or reports a missing
   prerequisite. It does not inspect or inherit the primary checkout's private file.

**Postconditions**: The result does not depend on another checkout's private data.

**Information shown**: The selected source or the expected missing local file,
and a safe explanation of the outcome. Configuration values are not diagnostics.

**Actions available**: Continue with shared settings, supply an explicit external
source, or create intentional checkout-local settings outside this change.

**Considerations**: An existing local file without reviewer settings, or with
empty reviewer settings, never triggers a search in another checkout. An invalid,
unreadable, or missing explicit source fails without fallback. A local source
that resolves outside the checkout requires explicit external-source selection.

### Use Case 2: Intentionally select external configuration

**Actor**: Workflow operator.

**Preconditions**: The operator deliberately selects a supported external source.

**Steps**:

1. The operator explicitly identifies the source through a supported option.
2. The helper validates that source and applies its existing configuration rules.
3. A review handoff carries only the settings needed for review.

**Postconditions**: The selection is explicit and attributable; unrelated private
data is not propagated to temporary review snapshots or exposed in output.

**Information shown**: Source identity and success or failure, without values.

**Actions available**: Correct the selected source or explicitly select a different
one. The helper does not silently substitute another source after failure.

**Considerations**: Empty settings retain their existing disabling semantics.
Review precedence and supported reviewer selection must remain consistent across
the resolver, preflight, and reviewer loop.

### Use Case 3: Diagnose a failure safely

**Actor**: Workflow operator reviewing runner diagnostics or an agent review.

**Preconditions**: Configuration or a runner operation produces a diagnostic.

**Steps**:

1. The runner reports the operation, source identity, and failure category.
2. Before emitting runner-owned diagnostics, it removes configuration values and
   masks sensitive material in diagnostic text from the operations it reports.
3. The operator receives enough context to locate and correct the failure.

**Postconditions**: Terminal output and persisted review or audit diagnostics do
not disclose the sensitive values represented by the regression fixtures.

**Information shown**: A stable redaction indication where sensitive material was
removed. Supported cases include sensitive assignments, authorization headers,
credential-bearing URLs, recognizable access tokens, and private-key blocks.

**Actions available**: Inspect the identified configuration privately outside the
agent transcript, correct the failure, or retry after explicit source selection.

**Considerations**: Both successful and failing diagnostic paths are covered,
including malformed private configuration. Sanitization preserves the operation's
exit result and must not echo the unsafe input when sanitization itself fails.

## Business Rules

- BR-1: Implicit local configuration selection is confined to the current
  checkout. Other-checkout discovery must not be used even for compatibility
  metadata or reviewer fallback.
- BR-2: Explicit external selection is the only cross-checkout exception and
  never grants permission to expose the source's values.
- BR-3: Source diagnostics identify a file and a failure category, not parsed
  values, raw configuration lines, or secret-bearing exception text.
- BR-4: Review handoffs propagate the minimum required reviewer settings. They
  must not stage a complete private file containing unrelated data.
- BR-5: Private-file exclusions and agent prevention rules accompany the fix.
  Public, intentionally versioned examples remain usable and trackable.
- BR-6: Secret-output regression checks use planted synthetic sensitive material
  and prove both safe output and observable failure when prevention is disabled.
- BR-7: Existing main-checkout use and explicitly selected review handoffs remain
  supported. No automatic copying of a consumer's private settings is introduced.

## Preflight Copy Scope Assessment

Copying the complete private local file during reviewer preflight is in scope.
That operation is a runner configuration handoff in the same path that selected
the unintended primary-checkout file. Fixing only selection would still copy
unrelated private data into temporary review state whenever a legitimate source
is selected. BR-4 requires a minimal review snapshot instead. The implementation
plan owns the projection, validation, and cleanup design; this does not authorize
changes to the operator's private files or unrelated credential management.

## Operational Visibility

Runner diagnostics report selected or missing source identity, operation category,
and whether redaction occurred. They never report private configuration contents.
No telemetry, new notification service, or private-file inventory is introduced.

## Acceptance Criteria

- [ ] AC-1: With synthetic private settings only in the primary checkout, Python
  and Bash helpers in an isolated checkout use no primary-checkout setting and
  do not read or report discovery of that private file.
- [ ] AC-2: Current-checkout settings, including missing, empty, and non-review
  local settings, cannot trigger another-checkout fallback. External local-file
  indirection requires explicit external selection.
- [ ] AC-3: A valid explicit source works under existing precedence rules; an
  invalid, missing, or unreadable explicit source fails without substitution.
- [ ] AC-4: Success, missing-file, and malformed-file diagnostics identify their
  source or expected file and category without exposing configuration values.
- [ ] AC-5: Synthetic sensitive assignments, authorization headers, credential
  URLs, recognizable tokens, and private-key blocks are redacted in runner-owned
  diagnostic output and persisted review/audit diagnostics, on stdout and stderr
  as applicable; original success and failure exit outcomes are preserved.
- [ ] AC-6: Preflight review snapshots contain only validated reviewer settings
  needed for that handoff. Unrelated synthetic private data never reaches the
  snapshot, and unreadable or invalid source errors remain safe and fail closed.
- [ ] AC-7: Prevention guidance and private-file exclusions cover local workflow
  configuration and credential files; intentionally public examples remain
  readable and versionable. Controls do not claim to enforce unavailable runtime
  permissions or to sanitize arbitrary commands run outside the workflow runner.
- [ ] AC-8: Regression tests use temporary synthetic repositories and fabricated
  sensitive values, cover Python/Bash parity and explicit-source errors, and
  prove a planted fallback or disclosure violation is detected.
- [ ] AC-9: The implementation includes a changelog fragment and consumer upgrade
  guidance for replacing implicit inheritance with deliberate local settings or
  explicit external selection, without copying a consumer's private values.

## Brief Objective Coverage

| Brief objective | Spec coverage |
| --- | --- |
| No implicit private reads outside the worktree | BR-1, AC-1, AC-2, AC-3 |
| Safe source diagnostics without values | BR-3, AC-4 |
| Automatic sensitive-output redaction | Use Case 3, AC-5 |
| Prevention rules and exclusions comparable to downstream | BR-5, AC-7 |
| Synthetic regression tests for inheritance and disclosure | BR-6, AC-8 |
| Changelog fragment | AC-9 |
| Consumer upgrade note | AC-9 |
| Evaluate complete preflight copy, per Luis | BR-4, scope assessment, AC-6 |

No brief objective is deferred. Downstream runtime-specific controls are adapted
to the supported template surfaces; no claim of universal runtime enforcement is
made. The implementation plan must identify the exact runner output boundaries
and their tests rather than promise sanitization of unrelated external sessions.

## Out of Scope

- Agent inspection or modification of real private settings, rotating
  credentials, investigating historical transcripts, or supplying
  incident-response evidence. Authorized protocol scripts retain normal runtime
  access to the selected private source.
- Other backlog items, releases, deployment behavior, and changes in consumer
  repositories themselves.
- Sanitizing arbitrary terminal sessions or external application output that the
  workflow runner does not emit or persist; implementing a universal secret detector.
- New reviewer platforms, altered merge authority, risk downgrades, or bypasses.
