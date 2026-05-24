# Haystack Triage CLI — Native PR Review Platform — Implementation Plan

**Spec**: [1_720-haystack-triage-review-platform_specs.md](1_720-haystack-triage-review-platform_specs.md)
**Smoke test runbook**: [docs/testing/workflow/720-haystack-triage-review-platform.smoke-test.md](../../../../testing/workflow/720-haystack-triage-review-platform.smoke-test.md)

---

## Summary

**Approach**: Create a new companion script `haystack-reviewer.sh` that calls `haystack triage <PR> --json` synchronously, parses findings by severity, and emits the standard key-value output contract (RESULT, BLOCKING_COUNT, SUGGESTION_COUNT, COMMENT_COUNT) with the correct exit codes (0/1/2/3). Then wire it into `pr-review-loop.sh` by adding a `run_haystack_review()` function, a `haystack` case in `bot_login_for_platform()`, and a `haystack` case in `run_platform_review()`. Finally, add the integration guide and update the existing `haystack.md` and `pr-review-platform.md` docs.

**Estimated complexity**: S

**Rationale**: All the patterns exist in the codebase — `claude-code-action-reviewer.sh` and `codex-github-reviewer.sh` are the direct model. The haystack reviewer is simpler: it runs synchronously (no polling loop) and maps JSON severity fields to blocking/advisory counts. The plan has no DB, no frontend, and no infrastructure changes.

**Dependencies**: None. The spec is self-contained; the companion script pattern already exists.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `d6d5f86` |
| Existing companion scripts | `ls scripts/development-workflow/*-reviewer.sh` | `claude-code-action-reviewer.sh`, `codex-github-reviewer.sh` |
| `bot_login_for_platform` function line | `grep -n "^bot_login_for_platform" scripts/development-workflow/pr-review-loop.sh` | line 2929 |
| `run_platform_review` function line | `grep -n "^run_platform_review" scripts/development-workflow/pr-review-loop.sh` | line 3062 |
| `run_platform_review` last case (claude-code-action) | `grep -n "claude-code-action" scripts/development-workflow/pr-review-loop.sh` | line 3085–3087 |
| Total lines in `pr-review-loop.sh` | `wc -l scripts/development-workflow/pr-review-loop.sh` | 4204 |
| Existing test file | `ls scripts/development-workflow/tests/` | `test-pr-review-loop.sh` |
| No existing `haystack` references in scripts | `grep -r "haystack" scripts/development-workflow/` | 0 matches |
| Integration guides dir | `ls docs/workflow/development-workflow/integrations/` | includes `haystack.md`; no `haystack-triage.md` |

---

## Layer-by-Layer Changes

### Scripts / Tooling

- [ ] Create `scripts/development-workflow/haystack-reviewer.sh` — new companion script (see Architecture section)
- [ ] Modify `scripts/development-workflow/pr-review-loop.sh`:
  - Add `haystack` case to `bot_login_for_platform()` (line ~2929)
  - Add `run_haystack_review()` function (add after `run_claude_code_action_review` function, before `run_devin_review`)
  - Add `haystack` case to `run_platform_review()` (line ~3069–3100)
  - Update the supported-platforms comment at the top of the file (line ~26) to include `haystack`
  - Update the `.ai-dev-workflow.yaml` supported-platforms comment near the `platforms:` key

### Documentation

- [ ] Create `docs/workflow/development-workflow/integrations/haystack-triage.md` — new integration guide (AC-6)
- [ ] Modify `docs/workflow/development-workflow/integrations/haystack.md` — add cross-reference to new triage guide (AC-7)
- [ ] Modify `docs/workflow/development-workflow/integrations/pr-review-platform.md` — add `haystack` to supported platforms list

---

## Architecture

### `haystack-reviewer.sh` — companion script

**Exit code contract** (matching existing companion scripts per BR-1):

| Exit code | Meaning |
| --------- | ------- |
| `0` | APPROVED — no blocking findings |
| `1` | NEEDS_REVISION — one or more blocking findings |
| `2` | TIMED_OUT — `haystack triage` did not return within timeout |
| `3` | UNAVAILABLE — `haystack` CLI not installed or not authenticated |

**Severity mapping** (BR-2 and BR-3):

| Haystack severity | Classification |
| ----------------- | -------------- |
| `Logic error` | Blocking |
| `Critical` | Blocking |
| `Major` (if present) | Blocking (conservative safe-fail) |
| `Minor` | Advisory |
| `Advisory` | Advisory |
| `Nitpick` | Advisory |
| `Trivial` | Advisory |
| Any unrecognised severity | Blocking (conservative safe-fail per existing patterns) |

**Note on severity mapping**: The `--json` output schema of `haystack triage` must be confirmed during implementation. The field path assumed here is `.findings[].severity` (or equivalent). If the actual schema uses different field names or nesting, the implementation must document the confirmed mapping in a code comment in `haystack-reviewer.sh` and update the severity table in `haystack-triage.md`. The spec explicitly requires this (BR-3).

**Key-value output contract** (stdout, matching all other companion scripts):

```
RESULT=clean|needs_fixes|skipped
BLOCKING_COUNT=<n>
SUGGESTION_COUNT=<n>
COMMENT_COUNT=<n>
REASON=<value>   (only when RESULT=skipped)
```

**Script structure** (illustrative — adapt during implementation):

```bash
#!/usr/bin/env bash
# haystack-reviewer.sh — Haystack triage CLI reviewer for Step 7 / Step 7a
#
# Usage: haystack-reviewer.sh <pr_number> <owner> <repo> [--timeout <seconds>]
#
# Exit codes:
#   0 — APPROVED (no blocking findings)
#   1 — NEEDS_REVISION (one or more blocking findings)
#   2 — TIMED_OUT (haystack triage did not respond within timeout)
#   3 — UNAVAILABLE (haystack CLI not installed or not authenticated)

set -euo pipefail

PR_NUMBER="$1"; OWNER="$2"; REPO="$3"
# ... argument validation ...
TIMEOUT="${HAYSTACK_REVIEWER_TIMEOUT:-120}"

# Availability check
if ! command -v haystack >/dev/null 2>&1; then
  printf 'RESULT=skipped\n'
  printf 'REASON=unavailable\n'
  printf 'BLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
  exit 3
fi

# Run triage with timeout
triage_output=""
triage_exit=0
set +e
triage_output="$(timeout "$TIMEOUT" haystack triage "$PR_NUMBER" --json 2>/tmp/haystack_triage_stderr_$$ )"
triage_exit=$?
set -e

# Log raw output to stderr for debugging
cat /tmp/haystack_triage_stderr_$$ >&2 || true
rm -f /tmp/haystack_triage_stderr_$$

if [ "$triage_exit" -eq 124 ]; then
  printf 'RESULT=skipped\nREASON=timeout\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
  exit 2
fi
if [ "$triage_exit" -ne 0 ]; then
  printf 'RESULT=skipped\nREASON=unavailable\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\nCOMMENT_COUNT=0\n'
  exit 3
fi

# Parse JSON findings
blocking_count=0
suggestion_count=0
# ... jq parsing of .findings[].severity ...

if [ "$blocking_count" -gt 0 ]; then
  printf 'RESULT=needs_fixes\n'
  printf 'BLOCKING_COUNT=%d\n' "$blocking_count"
  printf 'SUGGESTION_COUNT=%d\n' "$suggestion_count"
  printf 'COMMENT_COUNT=%d\n' "$((blocking_count + suggestion_count))"
  exit 1
fi
printf 'RESULT=clean\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=%d\nCOMMENT_COUNT=%d\n' \
  "$suggestion_count" "$suggestion_count"
exit 0
```

### `run_haystack_review()` in `pr-review-loop.sh`

The function follows the same structure as `run_claude_code_action_review()` with these differences:

- No thread pre-check phase (Haystack triage does not post GitHub review threads; the Out of Scope section explicitly excludes GitHub App integration)
- No polling loop (triage runs synchronously)
- Maps exit code 3 (UNAVAILABLE) to `RESULT=skipped` / `REASON=unavailable` and returns 0 (treated as skipped, not escalation)
- Maps exit code 2 (TIMED_OUT) to `RESULT=escalate` / `REASON=timeout`

**`bot_login_for_platform("haystack")` return value**: Since Haystack triage does not post GitHub inline review threads (posting to GitHub is Out of Scope for this MVP), the function returns an empty string `""` — matching the `pr-agent` pattern. The `check_unresolved_threads` gate will not be invoked for Haystack. If a future integration adds GitHub App thread posting, this can be updated to the actual bot login.

The `haystack` case in `run_platform_review()` dispatches to `run_haystack_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"`.

---

## Testing Strategy

**Test types**: Manual smoke test (script-level), unit test additions to existing `test-pr-review-loop.sh`

**Key scenarios to test**:

1. `haystack` binary not in `$PATH` → script exits 3, emits `RESULT=skipped` / `REASON=unavailable` (AC-4)
2. `haystack triage --json` returns findings with blocking severity → exits 1, `RESULT=needs_fixes`, `BLOCKING_COUNT > 0` (AC-2)
3. `haystack triage --json` returns only advisory/no findings → exits 0, `RESULT=clean`, `BLOCKING_COUNT=0` (AC-3)
4. `haystack triage --json` times out → exits 2, `RESULT=escalate`, `REASON=timeout`
5. `bot_login_for_platform("haystack")` returns `""` (empty) (AC-5)
6. `run_platform_review("haystack", ...)` dispatches to `run_haystack_review` (AC-1 / AC-8)
7. A `.ai-dev-workflow.yaml` with `review.platforms: [haystack]` causes `pr-review-loop.sh` to invoke the haystack platform (AC-1)

**Smoke test runbook**: `docs/testing/workflow/720-haystack-triage-review-platform.smoke-test.md`

**Unit test additions** (to `scripts/development-workflow/tests/test-pr-review-loop.sh`):

Add tests in a new `=== Area N: haystack platform ===` block:

- `bot_login_for_platform_haystack` — assert `bot_login_for_platform haystack` returns `""`
- `run_platform_review_haystack_clean` — mock `run_haystack_review` to emit `RESULT=clean`; assert `run_platform_review haystack ...` routes correctly
- `run_platform_review_haystack_needs_fixes` — mock `run_haystack_review` to emit `RESULT=needs_fixes`

Note: `haystack-reviewer.sh` itself is tested by the smoke test runbook (requires the `haystack` CLI to be installed). Unit tests of severity parsing logic can be added in a follow-up item once the CLI JSON schema is confirmed during implementation.

---

## Seed Data

None — this feature adds workflow tooling scripts and documentation with no application data dependencies.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` — **created** by this implementation (AC-6); documents CLI install steps, bot login identifier, severity mapping table
- [ ] `docs/workflow/development-workflow/integrations/haystack.md` — updated to reference new triage guide and note Haystack triage as a supported automated review platform (AC-7)
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` — updated to add `haystack` to the supported platforms list
- [ ] `scripts/development-workflow/pr-review-loop.sh` header comment — update supported-platforms list to include `haystack`

No changes needed to `docs/project/`, `docs/best-practices/`, or `AGENTS.md` — this feature adds a new optional review platform integration, not a change to the core project structure or stack conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| `haystack triage --json` schema differs from assumed field names | Medium | Medium | BR-3 requires confirming the schema during implementation; plan explicitly documents the assumption and requires a code comment + doc update if schema differs |
| Haystack CLI not available on CI runner or agent machines | High | Low | BR-4 / AC-4: exit 3 (UNAVAILABLE) gracefully degrades to `RESULT=skipped`; configured `internal_reviewers_unavailable_policy: warn` continues without blocking |
| `timeout` command not available on macOS (GNU coreutils not installed) | Low | Medium | Use `command -v timeout` check; fall back to background process + `wait` pattern if `timeout` is absent, or document that GNU coreutils must be available (align with existing scripts' assumptions) |

---

## Implementation Order

1. **Read and understand the actual `haystack triage --json` output schema**. Run `haystack triage <any-PR> --json` on a test PR (or use `haystack triage --help` output) to confirm the actual JSON field path for severity. Document the confirmed mapping in a comment block at the top of `haystack-reviewer.sh`.

2. **Create `scripts/development-workflow/haystack-reviewer.sh`**. Follow the structure in the Architecture section above. Include:
   - Positional argument validation (same pattern as `codex-github-reviewer.sh` lines 75–95)
   - Availability check: `command -v haystack`
   - Configurable timeout via `HAYSTACK_REVIEWER_TIMEOUT` env var (default: 120 seconds)
   - JSON parsing using `jq` to extract severity-classified counts
   - Raw triage output logged to stderr for debugging
   - All four exit codes (0/1/2/3) with matching stdout key-value output
   - `chmod +x` the file after creation

3. **Modify `scripts/development-workflow/pr-review-loop.sh`**:
   a. In `bot_login_for_platform()` (line ~2929), add before the `*)` catch-all:
      ```
      haystack)   printf '\n' ;;
      ```
   b. Add `run_haystack_review()` function. Place it directly after the closing `}` of `run_claude_code_action_review()` (after line ~881). The function should:
      - Call `haystack-reviewer.sh "$pr_number" "$owner" "$repo_name"` and capture exit code
      - Map exit 0 → `RESULT=clean`, return 0
      - Map exit 1 → `RESULT=needs_fixes`, `BLOCKING_COUNT` from script stdout, return 1
      - Map exit 2 → `RESULT=escalate` / `REASON=timeout`, return 2
      - Map exit 3 → `RESULT=skipped` / `REASON=unavailable`, return 0
      - Emit all standard key-value pairs: PLATFORM, PR_NUMBER, BRANCH, FIX_AGENT, COMMENT_COUNT, BLOCKING_COUNT, SUGGESTION_COUNT
   c. In `run_platform_review()` (line ~3062), add before the `*)` catch-all:
      ```
      haystack)
        run_haystack_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
        ;;
      ```
   d. Update the supported-platforms comment near the top of the file (line ~26) to add `haystack` to the list.
   e. Update the `.ai-dev-workflow.yaml` comment block inside the file (the `# Supported today by pr-review-loop.sh:` comment near the platforms key) to add `haystack`.

4. **Create `docs/workflow/development-workflow/integrations/haystack-triage.md`** (AC-6). Include:
   - Overview: what `haystack triage` does and how `haystack-reviewer.sh` wraps it
   - CLI installation steps (`haystack setup` or current recommended install method)
   - Configuration: add `haystack` to `review.platforms` or `review.phase_after_clean` in `.ai-dev-workflow.yaml`
   - Bot login identifier: document that Haystack triage does not post GitHub inline review threads in this MVP, so `bot_login_for_platform("haystack")` returns `""` and no thread audit is performed
   - Severity mapping table (the confirmed mapping from Step 1)
   - Timeout configuration: `HAYSTACK_REVIEWER_TIMEOUT` env var (default: 120 s)
   - Graceful degradation: when CLI is absent, pr-review-loop.sh skips Haystack and logs a warning per `internal_reviewers_unavailable_policy`
   - Troubleshooting section

5. **Modify `docs/workflow/development-workflow/integrations/haystack.md`** (AC-7). In the "Related Files" section and/or the "Optional PR triage and review" section, add:
   - A reference to the new `haystack-triage.md` guide
   - A note that `haystack triage` is now a supported native review platform in `pr-review-loop.sh`

6. **Modify `docs/workflow/development-workflow/integrations/pr-review-platform.md`**. Add `haystack` to the supported platforms list (wherever `greptile`, `devin`, `coderabbit`, `pr-agent`, `codex-github`, `claude-code-action` are listed).

7. **Add unit tests to `scripts/development-workflow/tests/test-pr-review-loop.sh`**:
   - Add a new `=== Area N: haystack platform ===` section (find the correct area number by checking the existing section count at plan-write time: currently sections go up to "Area 6")
   - `bot_login_for_platform_haystack`: assert `bot_login_for_platform haystack` returns `""`
   - Add any additional harness-compatible tests for `run_platform_review` haystack dispatch

8. **Run pre-commit lint check**:
   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260524150346_720-haystack-triage-review-platform/2_720-haystack-triage-review-platform_implementation-plan.md" \
     "docs/testing/workflow/720-haystack-triage-review-platform.smoke-test.md"
   ```
   Fix any reported violations before committing.

9. **Verify smoke test runbook steps manually** (if `haystack` CLI is available on the developer machine) or note which steps require the CLI.

10. **Update `CHANGELOG.md`** under `[Unreleased]`:
    ```
    - **Integrate Haystack triage CLI as native PR review platform** (#720): Add `haystack-reviewer.sh` companion script and wire `haystack` as a native platform in `pr-review-loop.sh`; add `haystack-triage.md` integration guide.
    ```
