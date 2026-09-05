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
`LOCAL_AI_REVIEWER_BACKEND=openai_compat` to use the HTTP preset at
`scripts/development-workflow/local-openai-review-command.sh` instead. Set
`LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1` to restore the old missing-command
behavior for tests or minimal environments.

<!-- workflow-shell-contract: bash-zsh -->
```bash
# Optional overrides (the bundled preset is used when LOCAL_AI_REVIEWER_COMMAND is unset):
export LOCAL_CODEX_REVIEWER_BIN='codex'
export LOCAL_CODEX_REVIEWER_MODEL='gpt-5.4'   # optional; codex uses its own default when omitted
export LOCAL_AI_REVIEWER_TIMEOUT='900'

# OpenAI-compatible HTTP backend (DeepSeek, Qwen, GLM, or any /chat/completions API):
export LOCAL_AI_REVIEWER_BACKEND='openai_compat'
export LOCAL_AI_REVIEWER_MODEL='deepseek-v4-pro'
export LOCAL_AI_REVIEWER_API_BASE_URL='https://api.deepseek.com'
export LOCAL_AI_REVIEWER_API_KEY="$DEEPSEEK_API_KEY"

# Custom command instead of a bundled preset:
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

For an OpenAI-compatible HTTP backend, use the matching wrapper. It inlines
`REVIEW.md`, the context bundle, and a bounded unified diff because the remote
model cannot read the local filesystem:

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
export LOCAL_AI_REVIEWER_MODEL='deepseek-v4-pro'
export LOCAL_AI_REVIEWER_API_BASE_URL='https://api.deepseek.com'
export LOCAL_AI_REVIEWER_API_KEY="$DEEPSEEK_API_KEY"
./scripts/development-workflow/local-openai-reviewer.sh \
  <pr-number> <owner> <repo> \
  --repo-root "$PWD" \
  --timeout 900 \
  --evidence-file /tmp/local-ai-reviewer-evidence.json
```

The HTTP preset's fail-closed setup checks are proven by
`scripts/development-workflow/tests/test-local-openai-review-command.sh`
(the unit tests plant the violation, assert the command fails, then restore
the env so later assertions pass):

| Check | Planted violation | Fail assertion | Guard / test lines |
| --- | --- | --- | --- |
| missing `BASE_BRANCH` | unset `BASE_BRANCH` | `openai_missing_base_branch_exits` | command L101; test L271 |
| `git diff` failure | `MOCK_GIT_FAIL=1` | `openai_git_diff_failure_exits` | command L107; test L250 |
| missing credentials | unset API key vars | `openai_missing_credentials` | command L66; test L184 |
| missing `REVIEW.md` | rename `REVIEW.md` | `openai_missing_review_md` | command L74; test L223 |
| missing model / base URL / context | unset the env var | `openai_missing_model`, `openai_missing_base_url`, `openai_missing_context_bundle` | command L58 / L62 / L70; tests L197 / L206 / L215 |
| HTTP 401 / non-200 | `MOCK_HTTP_CODE=401` or `500` | `openai_http_401_exits`, `openai_http_500_exits` | command L179 / L183; tests L232 / L239 |

This PR does not add a repo-wide lint rule, CI job, or file scanner, so the
unit-test fail/pass pairs above are the planted-violation proofs. E2E fixture
contract is not applicable (this template still uses the placeholder E2E job).

The command runs under `sh -c` with these environment variables:

- `CONTEXT_BUNDLE_PATH`
- `PR_NUMBER`
- `OWNER`
- `REPO`
- `BASE_BRANCH`
- `HEAD_BRANCH`
- `REVIEWED_HEAD`
- `REVIEW_STAGE`, `REVIEW_STAGE_SOURCE`, `REVIEW_CHECKLISTS`
- `REVIEW_DOCTRINE_STATE`, `REVIEW_DOCTRINE_PATTERN_COUNT`, `REVIEW_DOCTRINE_VERSION`
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
- `review_stage` — `spec`, `plan`, `implementation`, or `default`
- `review_stage_source` — `branch`, `branch+files`, or `none`
- `review_checklists` — ordered list of exact `REVIEW.md` level-2 heading
  strings (may be empty for `default`)
- `review_doctrine` — full catalogue bytes when supplied, otherwise empty
- `review_doctrine_state` — `supplied`, `absent`, `unreadable`, or `oversized`
- `review_doctrine_pattern_count` — patterns **supplied** (zero when not
  `supplied`)
- `review_doctrine_version` — first twelve hex characters of the catalogue
  SHA-256 (empty when no bytes were read)

Selection is **additive and monotone**: `REVIEW.md` as a whole and its Core
Rules always apply. The branch tier names one stage checklist; changed files
may **add** `Workflow Policy Review Checklist` but never replace or drop the
branch-implied checklist. Unknown branch types (`default`) keep the legacy
stage-agnostic prompt with no named sections — even when workflow-policy files
change.

| Head branch | Policy files changed? | Stage | Checklists named |
| --- | --- | --- | --- |
| `spec/*` | no | `spec` | Spec Review Checklist |
| `spec/*` | yes | `spec` | Spec, Workflow Policy |
| `implementation-plan/*` | no | `plan` | Plan Review Checklist |
| `implementation-plan/*` | yes | `plan` | Plan, Workflow Policy |
| `feature/*`, `refactor/*`, `fix/*`, `hotfix/*` | no | `implementation` | Code Review Checklist |
| `feature/*`, `refactor/*`, `fix/*`, `hotfix/*` | yes | `implementation` | Code, Workflow Policy |
| anything else | no | `default` | none |
| anything else | yes | `default` | none |

Custom `LOCAL_AI_REVIEWER_COMMAND` values receive `REVIEW_STAGE`,
`REVIEW_STAGE_SOURCE`, and `REVIEW_CHECKLISTS` in the environment and the
three fields in the bundle; they may ignore the stage. The bundled Codex preset
names selected sections in its default prompt when `REVIEW_CHECKLISTS` is
non-empty. `LOCAL_CODEX_REVIEWER_PROMPT` overrides the built prompt entirely
and does not receive the stage sentence.

On a second, strict-mode invocation the companion script may dispatch **at most
one** strict checklist pass per review via a two-entry registry (`spec` and
`plan`). Each entry always reports its own `STRICT_<entry>_*` keys; only the
entry matching the resolved stage dispatches a second `LOCAL_AI_REVIEWER_COMMAND`
call. The ordinary-pass bundle file is never rewritten.

Use `LOCAL_AI_REVIEWER_DISABLED=1` to intentionally skip the local platform
with `RESULT=skipped` and `REASON=disabled_by_config`.

Set `LOCAL_AI_REVIEWER_EVIDENCE_FILE=/path/to/file.json` or pass
`--evidence-file` to `local-codex-reviewer.sh` to persist a local evidence
artifact. The artifact uses `schema_version: local_ai_reviewer_evidence.v1`
and records the reviewed head, graph context, result, reason, counts, changed
files, compact diff summary, a `review_stage` object (stage, source,
checklists), a `review_doctrine` object (state, pattern_count, version), a
`strict_spec` object that mirrors the `STRICT_SPEC_*` keys, and a `strict_plan`
object that mirrors the `STRICT_PLAN_*` keys (including `applied` when state is
`applied`). Keep this artifact alongside ready-phase
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

## Strict Plan Contract Checks

On `implementation-plan/*` branches, after the ordinary review completes, the
plan registry entry may run a second `LOCAL_AI_REVIEWER_COMMAND` invocation
with `LOCAL_AI_REVIEWER_MODE=strict` when the pull request changes at least one
implementation-plan document. That pass reads
`docs/workflow/development-workflow/strict-plan-checks.md` (seven closed-set
identifiers with per-check `Source:` metadata) and must respond with:

```json
{
  "mode": "strict_plan_checks",
  "findings": [
    {
      "check": "phase_ordering",
      "path": "docs/specs/.../2_..._implementation-plan.md",
      "line": 42,
      "body": "Step 3 consumes output from step 5"
    }
  ]
}
```

`mode` must be exactly `strict_plan_checks`. The strict pass receives the full
text of each changed plan document at the reviewed head via `git show`, plus
each sibling `1_*_specs.md` when present — never from the working tree or from
diff hunks alone.

**Applied set semantics**: checks marked `Source: not required` always apply.
Checks marked `Source: required` apply only when an approved spec is present in
that plan's development directory (presence alone — not what the plan declares).
When no spec is present, the applied set is exactly
`source_declaration`, `phase_ordering`, `dependency_state`, and `reversal_risk`.
When a spec is present for at least one changed plan, all seven identifiers are
admitted at review level; findings on a plan document without a sibling spec for
source-dependent checks are filtered and counted in `STRICT_PLAN_UNKNOWN_COUNT`.

Companion output always includes `STRICT_PLAN_STATE`
(`applied` | `not_applicable` | `unavailable`). When `applied`, also
`STRICT_PLAN_COUNT` (may be `0`), `STRICT_PLAN_CHECKS` (comma-separated
identifiers that fired), and `STRICT_PLAN_APPLIED` (comma-separated identifiers
that were applied — never empty in `applied`). When `not_applicable` or
`unavailable`, also `STRICT_PLAN_REASON`:

| Reason | State |
| --- | --- |
| `stage_not_plan` | `not_applicable` |
| `no_plan_document_changed` | `not_applicable` |
| `stage_unresolved` | `unavailable` |
| `checklist_unreadable` | `unavailable` |
| `strict_pass_failed` | `unavailable` |

Unknown identifiers and source-dependent findings on documents without a source
are reported as `STRICT_<n>_CHECK=unknown` and counted in
`STRICT_PLAN_UNKNOWN_COUNT`; they never become blockers. Strict findings never
change `RESULT` or `BLOCKING_<n>_*`.

The spec registry entry and plan registry entry report independently on every
review (`STRICT_SPEC_*` and `STRICT_PLAN_*`). At most one entry reaches
`applied` per review (AC-24, AC-25).

The reviewer-loop history entry includes a `strict_plan` object that mirrors
those keys plus an `applied` array when state is `applied`. The summary comment
lists strict plan findings only when state is `applied` and the count is above
zero, and includes the applied set in that section.

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
- `REVIEW_STAGE`, `REVIEW_STAGE_SOURCE`, `REVIEW_CHECKLISTS` (comma-separated
  checklist headings on one line; surfaced in loop summaries as
  `PLATFORM_<n>_REVIEW_*` via `emit_prefixed_platform_output`)
- `COMMENT_COUNT`
- `BLOCKING_COUNT`
- `SUGGESTION_COUNT`
- `REASON` when the result is not plain clean

Use `scripts/development-workflow/local-ai-reviewer-findings.py` to normalize
and compare local findings against ready-phase reviewer findings when measuring
whether the ready-phase reviewer found net-new blockers.
