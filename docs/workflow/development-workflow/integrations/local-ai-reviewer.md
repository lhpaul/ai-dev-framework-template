# Integration: Local AI Reviewer

`local-ai-reviewer` is an optional Step 7 review platform for running a
repository-local review command before ready-phase reviewers such as Bugbot.
It is implemented by `scripts/development-workflow/local-ai-reviewer.sh` and
is consumed by `scripts/development-workflow/pr-review-loop.sh`.

The platform is local-only. It does not post GitHub inline comments in this
MVP, and a local clean result does not replace human review, CI, unresolved
thread checks, or the configured ready-phase reviewer.

---

## Configuration

Enable it explicitly in `.ai-dev-workflow.yaml` or in
`.ai-dev-workflow.local.yaml`:

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

The shared template does not enable `local-ai-reviewer` by default because a
missing local command is a setup failure and emits `RESULT=escalate`.

Set the local command in the runner environment:

<!-- workflow-shell-contract: bash-zsh -->
```bash
export LOCAL_AI_REVIEWER_COMMAND='my-review-command "$CONTEXT_BUNDLE_PATH"'
```

The command runs under `sh -c` with these environment variables:

- `CONTEXT_BUNDLE_PATH`
- `PR_NUMBER`
- `OWNER`
- `REPO`
- `BASE_BRANCH`
- `HEAD_BRANCH`
- `REVIEWED_HEAD`

Use `LOCAL_AI_REVIEWER_DISABLED=1` to intentionally skip the local platform
with `RESULT=skipped` and `REASON=disabled_by_config`.

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
