# Local AI Reviewer: Claude Backend — Smoke Test

**Spec**: [Local AI reviewer Claude backend](../../specs/developments/20261106092627_1957-local-ai-reviewer-claude-backend/1_1957-local-ai-reviewer-claude-backend_specs.md)

**Plan**: [Implementation plan](../../specs/developments/20261106092627_1957-local-ai-reviewer-claude-backend/2_1957-local-ai-reviewer-claude-backend_implementation-plan.md)

**Created in**: Plan Ready stage
**Updated in**: In Development stage

Run against the implementation PR checkout. Steps 1–3 need no Claude login.
Steps 4–7 use the real Claude Code CLI on the operator's existing login.
Record `claude --version` with the results. Never paste private configuration
or credential values into the PR. Use only disposable configuration files
under a temporary directory. No design assets exist for this item, because it
has no UI, so the runbook has no fidelity step.

## Prerequisites

- [ ] Implementation branch checked out, with `origin/develop` fetched
- [ ] `claude` CLI installed and logged in (Steps 4–7), and `gh` authenticated
- [ ] An open PR to review. The implementation PR itself is fine. Set
  `PR=<number>`, `OWNER=lhpaul`, and `REPO=ai-dev-framework-template`.
- [ ] Local checkout `HEAD` equals that PR's head SHA

## Steps

1. **Automated suites** (all ACs). Run
   `bash scripts/development-workflow/tests/test-local-claude-review-command.sh`,
   `bash scripts/development-workflow/tests/test-local-ai-reviewer-backend.sh`,
   `bash scripts/development-workflow/tests/test-local-ai-reviewer.sh`,
   `bash scripts/development-workflow/tests/test-local-http-review-command.sh`,
   `bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`,
   `bash scripts/development-workflow/tests/test-pr-review-loop-no-verdict-yet.sh`,
   and `bash scripts/development-workflow/tests/test-runner-diagnostic-emitters.sh`.
   **Expected**: every suite passes, and `backend_alias_error_names_http` still
   passes unchanged (AC-7).

2. **Default unchanged, without spending Codex** (AC-2, AC-10). Set
   `LOCAL_CODEX_REVIEWER_BIN=/usr/bin/false`, leave every other
   local-reviewer variable unset, point `AI_DEV_WORKFLOW_CONFIG_FILE` at an
   empty temporary YAML file, and run
   `./scripts/development-workflow/local-ai-reviewer.sh "$PR" "$OWNER" "$REPO" --repo-root "$PWD"`.
   **Expected**: stderr names the bundled **Codex** preset. No Claude budget
   line appears. The result is Reviewer failed, because the stand-in binary
   fails, and the Claude CLI is never started.

3. **Invalid selections** (AC-5, AC-7). Repeat step 2 with
   `LOCAL_AI_REVIEWER_BACKEND=not-a-backend`. Then unset it and use a temporary
   YAML file containing `review:` / `  local_ai_reviewer:` / `    backend: [claude]`.
   **Expected**: `REASON=invalid_backend` both times. The diagnostics are
   exactly `ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND`
   and `ERROR: configuration validation error; key=review.local_ai_reviewer.backend`.
   The rejected value is not echoed.

4. **Environment-selected Claude review** (AC-1, AC-9, AC-12, AC-13,
   AC-19). Note `git status --porcelain` and `git worktree list`. Run
   `LOCAL_AI_REVIEWER_BACKEND=claude ./scripts/development-workflow/local-ai-reviewer.sh "$PR" "$OWNER" "$REPO" --repo-root "$PWD"`.
   **Expected**: stderr names the bundled **Claude** preset, and a line says
   the timeout defaulted to 900s for the bundled Claude preset. The output
   ends in `RESULT=clean` or `RESULT=needs_fixes` with
   `REVIEWED_HEAD=<PR head>`. Afterwards `git status --porcelain` and
   `git worktree list` match the earlier capture, and no
   `local-claude-review.*` directory remains under `${TMPDIR:-/tmp}`.

5. **Shared default** (AC-4, AC-5). With `LOCAL_AI_REVIEWER_BACKEND` unset,
   point `AI_DEV_WORKFLOW_CONFIG_FILE` at a temporary YAML file with
   `review.local_ai_reviewer.backend: claude`, and run the step-4 command
   with `--timeout 60`. **Expected**: the Claude preset is selected, and there
   is no 900s line because `--timeout` was given. Then also export
   `LOCAL_AI_REVIEWER_BACKEND=http`. **Expected**: the HTTP preset is
   selected. Its own setup failure is acceptable here.

6. **Explicit command and budget** (AC-3, AC-10). Run
   `LOCAL_AI_REVIEWER_COMMAND="$PWD/scripts/development-workflow/local-claude-review-command.sh" ./scripts/development-workflow/local-ai-reviewer.sh "$PR" "$OWNER" "$REPO" --repo-root "$PWD"`.
   **Expected**: there is no preset INFO line and no 900s line, so the budget
   is 300 s. The integration guide's Claude section tells the operator to add
   `--timeout 900` in this case.

7. **Through the reviewer loop** (AC-6, AC-11). On a disposable test PR whose
   own branch adds `review.local_ai_reviewer.backend: claude` while
   `develop` does not, run
   `./scripts/development-workflow/pr-review-loop.sh <test-pr> --platform local-ai-reviewer`
   with `LOCAL_AI_REVIEWER_BACKEND` unset. **Expected**: the local-ai-reviewer
   stderr names the **Codex** preset, because the loop reads the base-branch
   configuration. `PLATFORM_WAIT_BUDGETS` shows `local-ai-reviewer:1200:default`
   (or the configured value) whatever the backend. Close the test PR without
   merging it.

8. **Documentation check** (AC-8, AC-21). Read `--help`, the
   `.ai-dev-workflow.yaml` local-reviewer comments, the
   `integrations/local-ai-reviewer.md` Configuration, Claude backend, and
   Failure Semantics sections, and the `integrations/pr-review-platform.md`
   comment. **Expected**: each names `claude`, `review.local_ai_reviewer.backend`,
   the BR-3 order, and the `LOCAL_CLAUDE_REVIEWER_*` settings. The guide also
   covers the prerequisites, the 900 s expectation, the strict-budget
   recommendation, the independence caveat, and the migration note.
   `sync-manifest.yaml` carries the migration note.

## Results Checklist

- [ ] Steps 1–8 pass, with the Claude CLI version recorded
- [ ] Checkout status and worktree list unchanged after every real run
- [ ] No Codex invocation in steps 4–6
