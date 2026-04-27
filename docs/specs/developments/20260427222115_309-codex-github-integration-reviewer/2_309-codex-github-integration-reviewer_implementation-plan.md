# Codex GitHub Integration Reviewer Path — Implementation Plan

**Spec**: [`1_309-codex-github-integration-reviewer_specs.md`](1_309-codex-github-integration-reviewer_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/309-codex-github-integration-reviewer.smoke-test.md`](../../../testing/workflow/309-codex-github-integration-reviewer.smoke-test.md)

---

## Summary

**Approach**: Add a `codex-github` reviewer entry to the Step 7a internal review gate in Protocol 91. The new reviewer posts a trigger comment to the PR via `gh pr comment`, polls for the Codex GitHub App's response using the `gh api` PR comments endpoint, interprets the bot's response as a verdict (`APPROVED` / `NEEDS REVISION`), and handles timeout as unavailability under the existing policy. Because all interactions use only `gh` CLI (already available in every supported runner context), `codex-github` is classified as universally reachable. The implementation adds: (1) a new reachability entry in Protocol 91 Step 7a's classification table, (2) a new dispatch row in the Step 7a reviewer dispatch map that invokes a new helper script `scripts/development-workflow/codex-github-reviewer.sh`, (3) the helper script itself that encapsulates trigger/poll/parse logic, (4) configuration keys in `.ai-dev-workflow.yaml` and its inline documentation, and (5) agent guidance updates to `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md`.

**Estimated complexity**: M

**Rationale**: The protocol documentation changes are bounded and follow the pattern established by the codex-reviewer-runtime-fallback feature. The net-new work is the `codex-github-reviewer.sh` script which requires a trigger/poll/parse loop with configurable timeouts — straightforward shell scripting but non-trivial to get right (idempotency guard, bot response detection, verdict parsing). No DB, frontend, or backend API layers are affected.

**Dependencies**: codex-reviewer-runtime-fallback (issue #252 / `20260417203329_codex-reviewer-runtime-fallback`) — must be Merged. The `codex-github` feature builds on the reachability classification table and policy machinery introduced by that feature. Confirmed merged on `develop` (spec merged as PR #371, dependency was already merged before that).

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `0039ddb` |
| Protocol 91 Step 7a reachability table location | `grep -n "Reachability classification table" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Line 542: `#### Reachability classification table` |
| Protocol 91 Step 7a reviewer dispatch map location | `grep -n "Reviewer dispatch map" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Line 599: `### Reviewer dispatch map` |
| Existing workflow scripts | `ls scripts/development-workflow/*.sh` | 11 files; no `codex-github-reviewer.sh` yet |
| Existing smoke test runbooks in `docs/testing/workflow/` | `ls docs/testing/workflow/*.smoke-test.md \| wc -l` | 21 runbooks; no `309-codex-github-integration-reviewer.smoke-test.md` yet |
| Agent guidance files requiring update | `ls .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md` | Both present |
| `.ai-dev-workflow.yaml` internal_reviewers comment block | `grep -n "codex-github" .ai-dev-workflow.yaml` | No match — `codex-github` not yet documented |

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] **New script `scripts/development-workflow/codex-github-reviewer.sh`**: Shell script that implements the trigger/poll/parse loop for the Codex GitHub bot reviewer. Accepts PR number, owner, repo, and optional config overrides as arguments. Outputs a structured result (`APPROVED` / `NEEDS_REVISION` / `TIMED_OUT`) to stdout and exits with 0 (approved), 1 (needs revision), or 2 (timed out / unavailable). Internal logic:
  - **Idempotency guard (BR-10)**: before posting a trigger comment, query existing PR comments (`gh api repos/{owner}/{repo}/issues/{pr}/comments`) and check whether a trigger comment for the current commit SHA already exists (authored by the runner, containing the commit SHA). If found, skip posting and proceed directly to polling.
  - **Trigger comment**: post via `gh pr comment <pr_number> --body "<trigger-phrase> (review triggered by workflow runner, commit: <sha>)"`. The trigger phrase defaults to `@codex review` and is overridable via `--trigger-phrase` argument or the `CODEX_GITHUB_TRIGGER_PHRASE` env variable.
  - **Polling loop**: query `gh api repos/{owner}/{repo}/issues/{pr}/comments --paginate` every `<poll_interval>` seconds (default: 30s), filter for comments authored by the configured bot login (default: `codex-ai[bot]`), and check for comments whose `created_at` timestamp is after the trigger comment timestamp.
  - **Verdict parsing**: a bot response comment is classified `APPROVED` when it contains no blocking findings. Classification is performed by looking for the absence of markers indicating required changes — the exact markers are an implementation detail (see Code Samples below for the illustrative approach). If blocking markers are present, the result is `NEEDS_REVISION`.
  - **Timeout handling**: if no bot response is detected within `<max_wait>` seconds (default: 300s / 5 minutes), exit with code 2 (`TIMED_OUT`).
  - **Configuration**: accept `--poll-interval <seconds>`, `--max-wait <seconds>`, `--bot-login <login>`, `--trigger-phrase <phrase>` flags. Defaults documented in the script header.

### Infrastructure / Configuration

- [ ] **`.ai-dev-workflow.yaml` — document `codex-github` as a supported `internal_reviewers` value**: Update the `internal_reviewers` comment block to list `codex-github` alongside `claude` and `codex`. Add a sub-comment explaining the `codex-github` path, its runner-context reachability (any runner with `gh` CLI), and the required one-time setup (Codex GitHub App installation). Add documented configuration keys: `codex_github_trigger_phrase` (default: `@codex review`), `codex_github_poll_interval` (default: 30s), `codex_github_max_wait` (default: 300s), `codex_github_bot_login` (default: `codex-ai[bot]`). These keys are advisory in the YAML comment; Protocol 91 and the helper script are the enforcement points.

### Protocol / Documentation Layer

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a reachability classification table**: Add a `codex-github` column (or a new row block) to the reachability table. `codex-github` is `reachable` from all runner contexts (Claude Code direct session, Claude Code subagent, Codex runner, direct human shell) because it requires only `gh` CLI access. Example addition:

  | Runner context | `claude` reachable? | `codex` reachable? | `codex-github` reachable? |
  |---|---|---|---|
  | Claude Code (direct human session) | Yes | No | Yes |
  | Claude Code subagent | Yes | No | Yes |
  | Codex runner / Codex skill | Yes | Yes | Yes |
  | Direct human (shell / CI with `gh`) | Yes | Yes | Yes |

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a reviewer dispatch map**: Add a `codex-github` dispatch block to the reviewer dispatch map table. The dispatch mechanism for `codex-github` is the same across all branch types — invoke `scripts/development-workflow/codex-github-reviewer.sh` with the PR number, owner, and repo:

  | Reviewer | PR branch prefix | Agent / protocol to dispatch |
  |---|---|---|
  | `codex-github` | `spec/*` | `scripts/development-workflow/codex-github-reviewer.sh <pr> <owner> <repo>` |
  | `codex-github` | `implementation-plan/*` | `scripts/development-workflow/codex-github-reviewer.sh <pr> <owner> <repo>` |
  | `codex-github` | `feature/*` / `refactor/*` / `fix/*` / `hotfix/*` | `scripts/development-workflow/codex-github-reviewer.sh <pr> <owner> <repo>` |

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a multi-reviewer execution rules**: Add a note after the reviewer dispatch map explaining how to interpret the `codex-github` exit codes: exit 0 = `APPROVED`, exit 1 = `NEEDS REVISION` (blocking findings present), exit 2 = `TIMED_OUT` (treat as `skipped (unavailable)` under the configured policy). Explain that on `NEEDS REVISION`, the runner must extract the blocking findings from the script's stdout for the fixer agent, and that a new trigger comment is posted for each Step 7a review cycle (BR-6). Explain the idempotency guard (BR-10): the script checks for an existing trigger comment for the current commit SHA before posting a new one.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a "Determining which reviewers to run"**: Add `codex-github` to the supported values listed in the local override example, alongside `claude` and `codex`, and add a brief parenthetical noting that `codex-github` requires the Codex GitHub App to be installed on the repository.

- [ ] **`.claude/agents/item-orchestrator.md`**: Update the agent guidance to document the `codex-github` dispatch path. Add a brief bullet explaining that when `codex-github` is in `internal_reviewers`, the runner invokes `codex-github-reviewer.sh` (which only uses `gh` CLI and is reachable from all runner contexts), and maps exit codes to verdicts.

- [ ] **`.cursor/agents/item-orchestrator.md`**: Same update as `.claude/agents/item-orchestrator.md` above.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. `codex-github` configured, Codex GitHub App installed and responsive — trigger comment posted, bot responds with approval, verdict `APPROVED`, Step 7a proceeds to `gh pr ready` (maps to Use Case 1 and AC-1, AC-2, AC-3, AC-7)
2. `codex-github` configured, bot responds with blocking findings — verdict `NEEDS REVISION`, fix loop entered, new trigger comment posted after fix push (maps to Use Case 2 and AC-4, AC-6)
3. `codex-github` configured, bot does not respond within timeout — `TIMED_OUT` result, warning comment posted, policy applied (maps to Use Case 3 and AC-5)
4. `codex-github` configured but App not installed — behaves identically to timeout scenario (maps to Use Case 4)
5. Both `codex` (CLI) and `codex-github` configured — both run sequentially, each produces independent verdict (maps to Use Case 5)
6. Duplicate trigger guard — runner detects existing trigger comment for current SHA, skips posting a second one (maps to BR-10, AC-6)
7. `codex-github` classified as reachable from Claude Code subagent context — no "unreachable" warning posted for `codex-github` (maps to BR-1, AC-1)

**Smoke test runbook**: [`docs/testing/workflow/309-codex-github-integration-reviewer.smoke-test.md`](../../../testing/workflow/309-codex-github-integration-reviewer.smoke-test.md)

---

## Seed Data

Not applicable — this feature is a protocol/documentation/script change with no runtime data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — primary change (see Layer-by-Layer Changes above)
- [ ] `.ai-dev-workflow.yaml` — add `codex-github` documentation in the `internal_reviewers` comment block and add configuration key comments (`codex_github_trigger_phrase`, `codex_github_poll_interval`, `codex_github_max_wait`, `codex_github_bot_login`)
- [ ] `.claude/agents/item-orchestrator.md` — add `codex-github` dispatch path documentation
- [ ] `.cursor/agents/item-orchestrator.md` — add `codex-github` dispatch path documentation

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Codex GitHub App response format changes without notice — verdict parsing breaks silently | Med | Med | Parse conservatively: default to `NEEDS_REVISION` when the response format is unrecognized (safe-fail). Document the expected format in the script header. |
| Bot login name differs from the documented default (`codex-ai[bot]`) | Med | Med | Make `--bot-login` configurable; document that operators must verify the actual bot account login name via the GitHub App settings page. |
| Poll interval too long / timeout too short for slow App response | Low | Med | Default 30s interval and 300s max wait are conservative; configurable via `--max-wait` and `--poll-interval` flags. Operators can increase for slower environments. |
| `codex-github` and `codex` (CLI) both configured — operator confusion about dual coverage | Low | Low | Document Use Case 5 explicitly in the protocol; add a note in `.ai-dev-workflow.yaml` that running both doubles review time and is typically unnecessary. |
| `gh` CLI authentication unavailable in some CI environments | Low | High | `codex-github` reachability is conditional on `gh` CLI being authenticated. Add a pre-flight `gh auth status` check in the script; emit a clear error if unauthenticated. |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

### `codex-github-reviewer.sh` — outline (illustrative)

```bash
#!/usr/bin/env bash
# codex-github-reviewer.sh — Codex GitHub App reviewer path for Step 7a
# Illustrative — adapt during implementation.
#
# Usage: codex-github-reviewer.sh <pr_number> <owner> <repo> [options]
#   --trigger-phrase <phrase>   Default: "@codex review"
#   --bot-login     <login>     Default: "codex-ai[bot]"
#   --poll-interval <seconds>   Default: 30
#   --max-wait      <seconds>   Default: 300
#
# Exit codes:
#   0 — APPROVED
#   1 — NEEDS_REVISION
#   2 — TIMED_OUT (treat as unavailable under configured policy)

set -euo pipefail

PR_NUMBER="$1"; OWNER="$2"; REPO="$3"
TRIGGER_PHRASE="${CODEX_GITHUB_TRIGGER_PHRASE:-@codex review}"
BOT_LOGIN="codex-ai[bot]"
POLL_INTERVAL=30
MAX_WAIT=300

# Parse optional flags...

# Pre-flight: verify gh auth
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI not authenticated"; exit 2; }

# Get current commit SHA for idempotency guard
CURRENT_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | cut -c1-12)

# Idempotency guard: check if trigger comment already posted for this SHA
EXISTING=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq ".[] | select(.body | test(\"$CURRENT_SHA\")) | .created_at" | head -1)

if [ -z "$EXISTING" ]; then
  gh pr comment "$PR_NUMBER" --repo "$OWNER/$REPO" \
    --body "$TRIGGER_PHRASE (review triggered by workflow runner, commit: $CURRENT_SHA)"
  TRIGGER_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
else
  TRIGGER_TIME="$EXISTING"
  echo "INFO: trigger comment already posted for commit $CURRENT_SHA — skipping duplicate post"
fi

# Poll for bot response
ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  BOT_RESPONSE=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    --jq ".[] | select(.user.login == \"$BOT_LOGIN\") | select(.created_at > \"$TRIGGER_TIME\") | .body" \
    | head -1)

  if [ -n "$BOT_RESPONSE" ]; then
    # Verdict parsing: look for explicit blocking markers
    # Exact marker strings are implementation details; safe-fail to NEEDS_REVISION on unknown format
    if echo "$BOT_RESPONSE" | grep -qiE "(changes requested|blocking|must fix|required:)"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "$BOT_RESPONSE"
      exit 1
    else
      echo "VERDICT: APPROVED"
      exit 0
    fi
  fi
done

echo "VERDICT: TIMED_OUT — no response from $BOT_LOGIN within ${MAX_WAIT}s"
exit 2
```

---

## Implementation Order

1. Read the current `91-orchestrate-work-protocol.md` Step 7a block in full to locate the exact insertion points for the reachability table column and the reviewer dispatch map row.

2. Create `scripts/development-workflow/codex-github-reviewer.sh`:
   - Implement the trigger/poll/parse/timeout logic per the Layer-by-Layer Changes section.
   - Add the `gh auth status` pre-flight check.
   - Add the idempotency guard (query existing trigger comments for current commit SHA before posting).
   - Make trigger phrase, bot login, poll interval, and max wait configurable via flags and env variables.
   - Document exit codes (0 = APPROVED, 1 = NEEDS_REVISION, 2 = TIMED_OUT) in the script header.
   - Mark it executable: `chmod +x scripts/development-workflow/codex-github-reviewer.sh`.
   - Verify: run `bash -n scripts/development-workflow/codex-github-reviewer.sh` to check for syntax errors.

3. Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a reachability classification table:
   - Expand the table to add a `codex-github` reachable? column. Set `Yes` for all runner contexts (universal reachability via `gh` CLI).
   - Verify: confirm the table renders correctly in Markdown by inspecting the final column count.

4. Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a reviewer dispatch map:
   - Add three `codex-github` rows (one for each branch prefix group) pointing to `scripts/development-workflow/codex-github-reviewer.sh`.
   - Add a note below the map explaining exit code semantics, `TIMED_OUT` policy mapping, `NEEDS REVISION` finding extraction, re-trigger on fix cycle (BR-6), and idempotency guard (BR-10).

5. Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a "Determining which reviewers to run" section:
   - Add `codex-github` to the local override example JSON `internal_reviewers` array.
   - Add a parenthetical noting the Codex GitHub App installation prerequisite.

6. Update `.ai-dev-workflow.yaml` — `internal_reviewers` comment block:
   - Document `codex-github` as a supported value with its reachability characteristic.
   - Add commented-out configuration key examples (`codex_github_trigger_phrase`, `codex_github_poll_interval`, `codex_github_max_wait`, `codex_github_bot_login`) with documented defaults and purpose.
   - Optionally add a note suggesting that teams replace `codex` (CLI-only) with `codex-github` to eliminate recurring skipped-reviewer warnings from automated subagent runners.

7. Update `.claude/agents/item-orchestrator.md`:
   - Add a bullet point explaining that `codex-github` is universally reachable (requires only `gh` CLI), invokes `codex-github-reviewer.sh`, and maps exit codes to verdicts.

8. Update `.cursor/agents/item-orchestrator.md`:
   - Same addition as step 7 above.

9. Write the smoke test runbook at `docs/testing/workflow/309-codex-github-integration-reviewer.smoke-test.md`.

10. Verify the smoke test runbook relative link from the plan file resolves correctly (three `../` hops from `docs/specs/developments/<folder>/` to `docs/testing/workflow/`).

11. Update `CHANGELOG.md` under `[Unreleased]`:
    - `- **Add codex-github integration reviewer path for Step 7a** (#309): adds a runner-agnostic internal reviewer that posts a trigger comment to a PR and polls for the Codex GitHub App bot response; works from Claude Code, Cursor, headless CI, and Codex runner contexts.`
