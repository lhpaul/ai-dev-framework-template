# Integration: Local AI Reviewer

`local-ai-reviewer` is the default first Step 7 draft GitHub review platform in
this template. It runs a repository-local review command before draft GitHub
reviewers such as PR-Agent and before ready-phase reviewers such as Bugbot. It
is implemented by `scripts/development-workflow/local-ai-reviewer.sh` and is
consumed by `scripts/development-workflow/pr-review-loop.sh`.

The platform is local-only. It does not post GitHub inline comments in this
MVP, and a local clean result does not replace human review, CI, unresolved
thread checks, or the configured ready-phase reviewer.

---

## Configuration

The shared template enables it before PR-Agent in `.ai-dev-workflow.yaml`:

```yaml
review:
  on_draft:
    github:
      - local-ai-reviewer
      - pr-agent
  on_ready:
    github:
      - bugbot
```

Set the local command in the runner environment when you need a custom command.
When `LOCAL_AI_REVIEWER_COMMAND` is unset, `local-ai-reviewer.sh` defaults to
the bundled Codex preset at
`scripts/development-workflow/local-codex-review-command.sh` (requires the
`codex` CLI on `PATH` and a working Codex login). Set
`LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1` to restore the old missing-command
behavior for tests or minimal environments.

<!-- workflow-shell-contract: bash-zsh -->
```bash
# Optional overrides (the bundled preset is used when LOCAL_AI_REVIEWER_COMMAND is unset):
export LOCAL_CODEX_REVIEWER_BIN='codex'
export LOCAL_CODEX_REVIEWER_MODEL='gpt-5.4'   # optional; codex uses its own default when omitted
export LOCAL_AI_REVIEWER_TIMEOUT='900'

# Custom command instead of the bundled Codex preset:
export LOCAL_AI_REVIEWER_COMMAND='my-review-command "$CONTEXT_BUNDLE_PATH"'
```

A missing local command **after** default resolution is a setup failure and
emits `RESULT=escalate` with `REASON=missing_command`. To intentionally skip
the default local reviewer for one run or one checkout, set
`LOCAL_AI_REVIEWER_DISABLED=1` or override `review.on_draft.github` in
`.ai-dev-workflow.local.yaml`.

For Codex, use the bundled preset wrapper instead of hand-writing the full
`codex exec` command:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/local-codex-reviewer.sh \
  <pr-number> <owner> <repo> \
  --repo-root "$PWD" \
  --timeout 900 \
  --evidence-file /tmp/local-ai-reviewer-evidence.json
```

The wrapper sets `LOCAL_AI_REVIEWER_COMMAND` to
`scripts/development-workflow/local-codex-review-command.sh`, which runs
`codex exec --sandbox read-only` and writes only the model JSON output back to
the companion script. Override `LOCAL_CODEX_REVIEWER_BIN`,
`LOCAL_CODEX_REVIEWER_MODEL`, or `LOCAL_CODEX_REVIEWER_PROMPT` when a local
machine needs a different Codex binary, model, or prompt.

The command runs under `sh -c` with these environment variables:

- `CONTEXT_BUNDLE_PATH`
- `PR_NUMBER`
- `OWNER`
- `REPO`
- `BASE_BRANCH`
- `HEAD_BRANCH`
- `REVIEWED_HEAD`
- `LOCAL_AI_REVIEWER_MODE` — `ordinary` (default) or `strict`

The context bundle JSON uses `schema_version:
local_ai_reviewer_context.v1` and includes:

- PR metadata and `reviewed_head`
- `changed_files`
- bounded `pr_body` text, so validation notes and planted-violation proof in
  the PR description are visible to the local model
- compact `diff_name_status` and `diff_stat` fields when the base ref is
  available in the checkout
- `review_contract`
- `graph_context`

On a second, strict-mode invocation the companion script derives a copy of that
bundle and adds `strict_spec_checks` (the checklist text). The ordinary-pass
bundle file is never rewritten.

Use `LOCAL_AI_REVIEWER_DISABLED=1` to intentionally skip the local platform
with `RESULT=skipped` and `REASON=disabled_by_config`.

Set `LOCAL_AI_REVIEWER_EVIDENCE_FILE=/path/to/file.json` or pass
`--evidence-file` to `local-codex-reviewer.sh` to persist a local evidence
artifact. The artifact uses `schema_version: local_ai_reviewer_evidence.v1`
and records the reviewed head, graph context, result, reason, counts, changed
files, compact diff summary, and a `strict_spec` object that mirrors the
`STRICT_SPEC_*` keys. Keep this artifact alongside ready-phase
reviewer-loop evidence when measuring whether Bugbot or another ready-phase
reviewer found net-new blockers. Relative evidence paths are resolved from the
operator's original working directory before `--repo-root` changes the checkout
directory.

---

## Strict Spec Contract Checks

On `spec/*` branches, after the ordinary review completes, `local-ai-reviewer.sh`
runs a second `LOCAL_AI_REVIEWER_COMMAND` invocation with
`LOCAL_AI_REVIEWER_MODE=strict`. That pass reads
`docs/workflow/development-workflow/strict-spec-checks.md` (eight closed-set
identifiers) and must respond with:

```json
{
  "mode": "strict_spec_checks",
  "findings": [
    {
      "check": "ac_consistency",
      "path": "docs/specs/.../1_..._specs.md",
      "line": 42,
      "body": "AC-A and AC-B cannot both hold"
    }
  ]
}
```

`mode` must be exactly `strict_spec_checks`. Responses missing that marker, or
with a non-array `findings` value, are recorded as `unavailable` /
`strict_pass_failed` and do not change the ordinary verdict.

Override prompts separately:

- `LOCAL_CODEX_REVIEWER_PROMPT` — ordinary pass only
- `LOCAL_CODEX_REVIEWER_STRICT_PROMPT` — strict pass only

There is no second timeout setting. The strict pass uses whatever remains of
`--timeout` / `LOCAL_AI_REVIEWER_TIMEOUT` after the ordinary pass.

Companion output always includes `STRICT_SPEC_STATE`
(`applied` | `not_applicable` | `unavailable`). When `applied`, also
`STRICT_SPEC_COUNT` (may be `0`) and `STRICT_SPEC_CHECKS` (comma-separated
identifiers that fired). When `unavailable`, also `STRICT_SPEC_REASON`
(`stage_unresolved` | `checklist_unreadable` | `strict_pass_failed`). Unknown
identifiers are reported as `STRICT_<n>_CHECK=unknown` and counted in
`STRICT_SPEC_UNKNOWN_COUNT`; they never become blockers. Strict findings never
change `RESULT` or `BLOCKING_<n>_*`.

The reviewer-loop history entry includes a `strict_spec` object that mirrors
those keys (absent fields are omitted, not null). The summary comment lists
strict findings only when state is `applied` and the count is above zero.

---

## Command Output

The local command must emit JSON on stdout. It may either emit an explicit
terminal result:

```json
{
  "result": "clean",
  "reviewed_head": "abc123",
  "findings": []
}
```

or emit findings and let the companion script infer the terminal result:

```json
{
  "findings": [
    {
      "severity": "important",
      "path": "scripts/example.sh",
      "line": 42,
      "message": "Missing test coverage for this branch."
    }
  ]
}
```

Accepted raw result values are:

- `clean`
- `needs_fixes`
- `needs_rerun`
- `skipped`
- `escalate`

Do not emit display labels such as `needs-fixes`.

Clear in-scope suggestions, important findings, and blocking findings map to
`RESULT=needs_fixes`. Scope-expanding or decision-bound advisory findings may
remain clean when they are marked with fields such as `advisory: true`,
`scope_expanding: true`, `decision_bound: true`, or a matching scope/disposition
string.

---

## Failure Semantics

The local reviewer fails closed:

| Condition | Result |
| --- | --- |
| Missing `LOCAL_AI_REVIEWER_COMMAND` | `RESULT=escalate`, `REASON=missing_command` |
| Missing model access | `RESULT=escalate`, `REASON=missing_model_access` |
| Missing credentials or auth failure | `RESULT=escalate`, `REASON=missing_credentials` |
| Checkout head mismatch | `RESULT=escalate`, `REASON=head_mismatch` |
| Missing `REVIEW.md` | `RESULT=escalate`, `REASON=review_contract_missing` |
| Timeout | `RESULT=escalate`, `REASON=timeout` |
| Malformed output | `RESULT=escalate`, `REASON=malformed_output` |
| Explicit disabled config | `RESULT=skipped`, `REASON=disabled_by_config` |

A skipped or escalated local result is availability evidence, not clean review
evidence.

---

## Graph Context

Graph context is optional. The default strategy is no graph context.

Set:

<!-- workflow-shell-contract: bash-zsh -->
```bash
export LOCAL_AI_REVIEWER_GRAPH_STRATEGY=auto
```

Accepted values:

- `none`
- `auto`
- `code-review-graph`
- `graphify`

When a requested optional graph tool is absent, the platform still runs with
the no-graph context and emits `GRAPH_CONTEXT=skipped`. Missing optional graph
tooling does not turn the platform result into clean or escalation.

Before making graph context required, evaluate no-graph,
`code-review-graph`, and `graphify` against the representative inputs named in
the #1604 plan and record the adoption result as Deferred, Optional, or
Required.

---

## Evidence

`local-ai-reviewer` does not own a GitHub bot login. `bot_login_for_platform`
returns empty, and the Automated Reviewer Loop Summary is the durable evidence.

The companion script emits:

- `REVIEWED_HEAD`
- `GRAPH_CONTEXT`
- `COMMENT_COUNT`
- `BLOCKING_COUNT`
- `SUGGESTION_COUNT`
- `REASON` when the result is not plain clean

Use `scripts/development-workflow/local-ai-reviewer-findings.py` to normalize
and compare local findings against ready-phase reviewer findings when measuring
whether the ready-phase reviewer found net-new blockers.
