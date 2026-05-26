# Haystack Triage CLI — Native PR Review Platform — Spec

---

## Overview

This feature integrates the Haystack triage CLI (`haystack triage <PR> --json`) as a native automated review platform in `pr-review-loop.sh`, placing it alongside CodeRabbit, PR-Agent, and Claude Code Action. A new companion script (`haystack-reviewer.sh`) wraps the CLI call, parses structured findings by severity, and emits the same exit-code and key-value output contract as the other companion scripts. Teams that declare `haystack` in `review.platforms` gain a rate-cap-free review platform that produces actionable, file-anchored findings with fix suggestions — without requiring any additional GitHub App installation. An integration guide documents the CLI install, bot login identifier, and severity mapping.

---

## Use Cases

### Use Case 1: Automated Haystack review triggered by pr-review-loop.sh

**Actor**: `pr-review-loop.sh` (automated CI script), acting on behalf of the developer or the Work Item Runner.

**Preconditions**:
- A pull request is open and non-draft.
- The `haystack` CLI is installed and authenticated on the runner machine (typically via `haystack setup`).
- `haystack` is listed in `review.platforms` (or `review.phase_after_clean`) in `.ai-dev-workflow.yaml`.

**Steps**:

1. `pr-review-loop.sh` calls `haystack-reviewer.sh <pr_number> <owner> <repo>`.
2. `haystack-reviewer.sh` runs `haystack triage <pr_number> --json` and captures the structured output.
3. The script parses each finding's severity level and classifies it as blocking (Logic error / Critical) or advisory (Minor / Advisory / Nitpick / Trivial).
4. The script emits `RESULT=`, `BLOCKING_COUNT=`, `SUGGESTION_COUNT=`, and `COMMENT_COUNT=` key-value lines matching the standard companion-script output contract.
5. The script exits with the appropriate code: `0` (APPROVED — no blocking findings), `1` (NEEDS_REVISION — one or more blocking findings), or `3` (UNAVAILABLE — `haystack` CLI not installed or not authenticated).
6. `pr-review-loop.sh` reads the exit code and key-value output to continue the review loop: stop and emit `needs_fixes` if blocking, continue to the next platform if clean.

**Postconditions**: `pr-review-loop.sh` has a deterministic verdict from Haystack. If blocking findings exist, the loop stops and the developer is told how many blocking findings were found.

**Information shown**: Key-value summary block (RESULT, BLOCKING_COUNT, SUGGESTION_COUNT, COMMENT_COUNT). The raw `haystack triage` output may be logged to stderr for debugging.

**Actions available**: Developer reads the blocking findings from the `haystack triage <PR>` (human-readable form), pushes fixes, and re-runs the review loop.

**Considerations**:

- If the `haystack` CLI is not installed on the runner, the script must exit `3` (UNAVAILABLE) rather than failing with an unrelated error message.
- If `haystack triage --json` returns a non-zero exit code for reasons other than "not installed" (e.g., network error, authentication failure), the script should exit `3` (UNAVAILABLE) and log the raw error.
- The script must not hang indefinitely: a configurable timeout should bound the `haystack triage` call.

---

### Use Case 2: Haystack as a phase-after-clean reviewer

**Actor**: `pr-review-loop.sh`, after earlier platforms (e.g., PR-Agent) have cleared.

**Preconditions**:
- The earlier-phase review platform(s) returned `clean`.
- `haystack` is listed in `review.phase_after_clean` in `.ai-dev-workflow.yaml`.
- The `haystack` CLI is installed and authenticated.

**Steps**:

1. `pr-review-loop.sh` enters the second review phase after the first-phase platforms are clean.
2. It calls `haystack-reviewer.sh` for the PR.
3. Haystack triage runs and classifies findings as blocking or advisory.
4. The loop reports the verdict and exits accordingly.

**Postconditions**: The PR has been reviewed by Haystack in the after-clean phase. Blocking findings stop the loop; advisory findings are reported but do not block readiness.

**Information shown**: Same key-value summary block as Use Case 1. The Haystack bot login identifier is available for the unresolved-threads check (`check_unresolved_threads`).

**Actions available**: Developer addresses blocking findings if any; otherwise the PR advances to `ready-for-human-review`.

**Considerations**:

- The phase-after-clean flow is identical at the script level; the placement in the pipeline is purely a configuration concern in `.ai-dev-workflow.yaml`.
- Haystack's lack of a per-hour rate cap makes it a natural fit for the after-clean phase alongside or instead of CodeRabbit.

---

### Use Case 3: Graceful degradation when Haystack CLI is not installed

**Actor**: `pr-review-loop.sh` on a machine where `haystack` CLI has not been installed.

**Preconditions**:
- `haystack` is listed in `review.platforms`.
- The `haystack` binary is not present in `$PATH` (or is not authenticated).

**Steps**:

1. `pr-review-loop.sh` calls `haystack-reviewer.sh`.
2. `haystack-reviewer.sh` detects that the `haystack` CLI is unavailable.
3. The script exits `3` (UNAVAILABLE) and emits `RESULT=skipped` / `REASON=unavailable`.
4. `pr-review-loop.sh` applies the configured `internal_reviewers_unavailable_policy` (default: `warn`) — logs a warning and continues to the next platform.

**Postconditions**: The review loop does not abort; it continues with the remaining configured platforms. The developer is warned that Haystack was skipped.

**Information shown**: A warning message noting that Haystack is unavailable on this runner, with a pointer to the installation guide.

**Actions available**: Developer may install the Haystack CLI to activate this reviewer.

**Considerations**:

- The unavailability of Haystack must not prevent other platforms from running.
- The warning must include the documentation link for installing `haystack` so the developer knows the remediation step.

---

## Business Rules

- BR-1: `haystack-reviewer.sh` must exit `0` (APPROVED), `1` (NEEDS_REVISION), or `3` (UNAVAILABLE) — matching the same exit-code contract as `claude-code-action-reviewer.sh` and other companion scripts. Exit `2` (TIMED_OUT) is reserved for cases where the CLI call does not return within the configured timeout.
- BR-2: Findings with Haystack severity "Logic error" or "Critical" (or equivalent high-severity labels returned by the CLI) are classified as blocking. All other severities (Minor, Advisory, Nitpick, Trivial) are advisory and do not block readiness.
- BR-3: The severity mapping must be confirmed against the actual `haystack triage --json` output schema during implementation. If the schema uses different field names or values than expected, the implementation plan must document the confirmed mapping.
- BR-4: If `haystack` CLI is absent from `$PATH`, the script must exit `3` (UNAVAILABLE) without emitting any error about the review findings themselves.
- BR-5: `bot_login_for_platform()` in `pr-review-loop.sh` must return the Haystack bot login identifier for the `haystack` platform case so `check_unresolved_threads` can filter threads by bot author.
- BR-6: `run_platform_review()` in `pr-review-loop.sh` must dispatch to `haystack-reviewer.sh` for the `haystack` platform case.
- BR-7: `haystack` must be registerable in `.ai-dev-workflow.yaml` under `review.platforms` and/or `review.phase_after_clean` using the plain string `haystack`.
- BR-8: The integration guide must document CLI installation, the bot login identifier used by `check_unresolved_threads`, and the severity mapping table so operators can validate and troubleshoot the integration.
- BR-9: `haystack-reviewer.sh` must be universally reachable from all runner contexts (Claude Code, Cursor, Codex, headless CI) — it must require no runner-specific binary beyond the `haystack` CLI and `gh` CLI.

---

## Statuses / Enum Values

The companion script emits a `RESULT` field using the existing enum values from the pr-review-loop contract. No new statuses are introduced.

| RESULT value  | Meaning                                                                          |
| ------------- | -------------------------------------------------------------------------------- |
| `clean`       | No blocking findings; the PR may advance                                         |
| `needs_fixes` | One or more blocking findings; the PR must be revised                            |
| `skipped`     | Haystack CLI unavailable on this runner; review was not performed                |
| `escalate`    | Unrecoverable error (e.g., timed out, unexpected CLI failure after retry)        |

---

## Operational Visibility

- **Logs**: `haystack-reviewer.sh` logs the raw `haystack triage --json` output to stderr (at INFO level) so operators can inspect raw findings without re-running triage manually. Blocking and advisory counts are emitted as key-value pairs to stdout for `pr-review-loop.sh` to parse.
- **Notifications**: No new notifications. The existing `pr-review-loop.sh` summary mechanism surfaces the Haystack verdict alongside other platform verdicts.
- **Audit trail**: The key-value output block (RESULT, BLOCKING_COUNT, SUGGESTION_COUNT, COMMENT_COUNT, PLATFORM) is captured in the review loop's session log, consistent with other platforms.

---

## Acceptance Criteria

- [ ] AC-1: A repository with `review.platforms: [haystack]` in `.ai-dev-workflow.yaml` causes `pr-review-loop.sh` to run `haystack-reviewer.sh` for the configured PR.
- [ ] AC-2: When `haystack triage <PR> --json` returns findings with blocking severity (Logic error / Critical), `haystack-reviewer.sh` exits `1` and emits `RESULT=needs_fixes` with a non-zero `BLOCKING_COUNT`.
- [ ] AC-3: When `haystack triage <PR> --json` returns only advisory findings (or no findings), `haystack-reviewer.sh` exits `0` and emits `RESULT=clean` with `BLOCKING_COUNT=0`.
- [ ] AC-4: When the `haystack` binary is absent from `$PATH`, `haystack-reviewer.sh` exits `3` and emits `RESULT=skipped` / `REASON=unavailable`. No other platforms are blocked.
- [ ] AC-5: `bot_login_for_platform("haystack")` returns the correct Haystack bot login identifier so `check_unresolved_threads` can filter threads by bot author.
- [ ] AC-6: The integration guide (`docs/workflow/development-workflow/integrations/haystack-triage.md`) documents CLI install steps, the bot login identifier, and the severity mapping table.
- [ ] AC-7: The existing `haystack.md` integration guide is updated to reference the new triage integration guide and to note that Haystack triage is now a supported automated review platform.
- [ ] AC-8: `haystack-reviewer.sh` is invocable as `haystack-reviewer.sh <pr_number> <owner> <repo>` with the same key-value output format and exit-code contract as `claude-code-action-reviewer.sh`, so `pr-review-loop.sh` can dispatch it using the existing platform-review dispatch logic without modification to that dispatch mechanism.

---

## Out of Scope (MVP)

- Posting Haystack findings back to the PR as inline GitHub review comments (the script reads the JSON output locally; it does not push results to GitHub review threads).
- Auto-resolving Haystack review threads via the GitHub GraphQL resolve mutation (threads posted by any future Haystack GitHub App integration are not in scope here).
- Haystack GitHub App installation or configuration (this integration uses the CLI only).
- Modifying the Haystack CLI itself or its JSON output format.
- Integration with the `haystack submit` PR-creation workflow (separate concern from automated review).
- Providing a `haystack-reviewer` Codex skill or Claude Code command shortcut.
