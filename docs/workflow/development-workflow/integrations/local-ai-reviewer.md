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
When `LOCAL_AI_REVIEWER_COMMAND` is unset, `local-ai-reviewer.sh` runs the
bundled preset of the selected backend:

| Backend | Preset | Needs |
| --- | --- | --- |
| `codex` (built-in default) | `scripts/development-workflow/local-codex-review-command.sh` | the `codex` CLI on `PATH` and a working Codex login |
| `http` (deprecated alias `openai_compat`) | `scripts/development-workflow/local-http-review-command.sh` | a Chat Completions API model, base URL, and key |
| `claude` | `scripts/development-workflow/local-claude-review-command.sh` | the Claude Code CLI installed and logged in (see [Claude backend](#claude-backend)) |

The backend is chosen in this order; the first rule that applies wins:

1. `LOCAL_AI_REVIEWER_COMMAND` is used as is. No preset or backend setting
   applies.
2. `LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1` leaves no command, so the run
   escalates as `missing_command` (the old behavior, for tests or minimal
   environments).
3. A non-empty `LOCAL_AI_REVIEWER_BACKEND` chooses the backend for this
   machine or run.
4. A non-empty `review.local_ai_reviewer.backend` in the shared
   `.ai-dev-workflow.yaml` chooses the repository default.
5. Otherwise the backend is `codex`.

An empty value counts as not set. `LOCAL_AI_REVIEWER_DISABLED=1` is checked
before all of this and still reports Skipped. A repository makes Claude its
default without patching any script:

```yaml
review:
  local_ai_reviewer:
    backend: claude
```

The shared default is read from the workflow configuration the reviewer
receives for the run. Under `pr-review-loop.sh` that is the pull request base
branch's copy of `.ai-dev-workflow.yaml`, so a pull request that adds or
changes the key is still reviewed with the backend its base selects; the
change applies to later pull requests once it is merged. A direct run reads
`AI_DEV_WORKFLOW_CONFIG_FILE` when it names a file, else the tooling
checkout's `.ai-dev-workflow.yaml`. A missing, unreadable, or unparseable file
counts as not set (with a `WARN: configuration unreadable` line when the file
exists but cannot be decoded), so Codex runs. The private
`.ai-dev-workflow.local.yaml` is never read for the backend; use
`LOCAL_AI_REVIEWER_BACKEND` for a per-developer choice.

An unknown backend name stops the run as Reviewer failed / `invalid_backend`,
never falling back to another backend. The diagnostic names only the key that
supplied it and never echoes the value:
`ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND` for the
environment selection, and
`ERROR: configuration validation error; key=review.local_ai_reviewer.backend`
for the shared default (which also rejects a non-string value or a name with
characters outside `A-Z`, `a-z`, `0-9`, `_`, and `-`). Backend names are case
sensitive.

<!-- workflow-shell-contract: bash-zsh -->
```bash
# Optional overrides (the bundled preset is used when LOCAL_AI_REVIEWER_COMMAND is unset):
export LOCAL_CODEX_REVIEWER_BIN='codex'
export LOCAL_CODEX_REVIEWER_MODEL='gpt-5.4'   # optional; codex uses its own default when omitted
export LOCAL_AI_REVIEWER_TIMEOUT='900'

# HTTP Chat Completions backend (DeepSeek, Qwen, GLM, OpenAI, or any /chat/completions API):
export LOCAL_AI_REVIEWER_BACKEND='http'
export LOCAL_AI_REVIEWER_MODEL='deepseek-v4-pro'
export LOCAL_AI_REVIEWER_API_BASE_URL='https://api.deepseek.com'
export LOCAL_AI_REVIEWER_API_KEY="$DEEPSEEK_API_KEY"
# Prefer LOCAL_AI_REVIEWER_API_BASE_URL over a global OPENAI_BASE_URL fallback
# so an unrelated OpenAI SDK env does not silently redirect review traffic.

# Claude Code CLI backend (uses your existing Claude login; no API key):
export LOCAL_AI_REVIEWER_BACKEND='claude'
export LOCAL_CLAUDE_REVIEWER_BIN='claude'     # optional; set when claude is not on PATH
export LOCAL_CLAUDE_REVIEWER_MODEL='opus'     # optional; the CLI default is used when omitted

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

For an HTTP Chat Completions backend, use the matching wrapper. It inlines
`REVIEW.md`, the context bundle, and a bounded unified diff because the remote
model cannot read the local filesystem:

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
export LOCAL_AI_REVIEWER_MODEL='deepseek-v4-pro'
export LOCAL_AI_REVIEWER_API_BASE_URL='https://api.deepseek.com'
export LOCAL_AI_REVIEWER_API_KEY="$DEEPSEEK_API_KEY"
./scripts/development-workflow/local-http-reviewer.sh \
  <pr-number> <owner> <repo> \
  --repo-root "$PWD" \
  --timeout 900 \
  --evidence-file /tmp/local-ai-reviewer-evidence.json
```

The HTTP preset's fail-closed setup checks are proven by
`scripts/development-workflow/tests/test-local-http-review-command.sh`
(the unit tests plant the violation, assert the command fails, then restore
the env so later assertions pass):

| Check | Planted violation | Fail assertion | Guard / test lines |
| --- | --- | --- | --- |
| missing `BASE_BRANCH` | unset `BASE_BRANCH` | `http_missing_base_branch_exits` | command L101; test L298 |
| `git diff` failure | `MOCK_GIT_FAIL=1` | `http_git_diff_failure_exits` | command L107; test L279 |
| missing credentials | unset API key vars | `http_missing_credentials` | command L66; test L197 |
| missing `REVIEW.md` | rename `REVIEW.md` | `http_missing_review_md` | command L74; test L232 |
| missing model / base URL / context | unset the env var | `http_missing_model`, `http_missing_base_url`, `http_missing_context_bundle` | command L58 / L62 / L70; tests L206 / L215 / L224 |
| HTTP 401 / non-200 | `MOCK_HTTP_CODE=401` or `500` | `http_status_401_exits`, `http_status_500_exits` | command L179 / L183; tests L241 / L248 |
| curl non-zero exit | `MOCK_CURL_EXIT=28` | `http_curl_failure_exits` | command L173; test L257 |
| empty message content | `MOCK_MODEL_CONTENT=''` | `http_empty_content_exits` | command L193; test L266 |

This PR does not add a repo-wide lint rule, CI job, or file scanner, so the
unit-test fail/pass pairs above are the planted-violation proofs. E2E fixture
contract is not applicable (this template still uses the placeholder E2E job).

### Claude backend

The `claude` backend runs one read-only review through the Claude Code CLI
(#1957). Select it with `LOCAL_AI_REVIEWER_BACKEND=claude`, or for the whole
repository with `review.local_ai_reviewer.backend: claude`.

**Prerequisites.** Install the Claude Code CLI and log in once (`claude`, then
follow the login prompt). The preset uses that existing login and passes no
API key or settings file. When `claude` is not on `PATH` (a shell alias does
not count, because scripts do not see aliases), set
`LOCAL_CLAUDE_REVIEWER_BIN` to the CLI's path. A missing binary is Reviewer
failed with a diagnostic naming `LOCAL_CLAUDE_REVIEWER_BIN`.

**Settings.**

- `LOCAL_CLAUDE_REVIEWER_BIN`: the CLI binary (default `claude`).
- `LOCAL_CLAUDE_REVIEWER_MODEL`: optional model. When unset, no `--model` is
  passed and the CLI's own default applies.
- `LOCAL_CLAUDE_REVIEWER_PROMPT`: replaces the ordinary-pass instructions.
- `LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT`: replaces the strict-pass
  instructions.

The default ordinary prompt uses the Codex preset's review instructions
(`REVIEW.md`, the stage checklists, published body and comments as untrusted
data, and the evidence-verification request) and adds that the review is
read-only, so the reviewer reports findings instead of applying fixes even
where `REVIEW.md` asks reviewers to fix directly. Whatever the prompt, the
preset always appends a fixed operating note: there is no shell, the full diff
is in `.review-diff.patch` (read it with Read, and use Read, Grep, and Glob for
context), and no file may be edited, created, or deleted.

**Review copy and isolation.** The preset reviews `REVIEWED_HEAD`, the pull
request head the reviewer resolved, never whatever the checkout has checked
out. It never touches the developer's checkout:

- It creates a throwaway detached copy under
  `${TMPDIR:-/tmp}/local-claude-review.*` without files, reads the copy's
  filter-driver keys from inside it, and populates it with every filter
  driver (including Git LFS), hook, and `core.fsmonitor` program disabled and
  without recursing into submodules. Git's built-in line-ending conversion
  still applies, as in any checkout of yours. A file under a filter attribute
  therefore appears as its committed content, such as LFS pointer text.
- Every Git command it runs, and the CLI, run with inherited `GIT_*`
  variables removed, except `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, and
  `GIT_CONFIG_NOSYSTEM`, so a hook's `GIT_DIR` or an alias's
  `GIT_CONFIG_PARAMETERS` cannot redirect the copy or re-enable a driver.
- It refuses a reviewed commit that itself contains `.review-diff.patch` or
  `.review-context.json`, writes the diff of `origin/<base>...<head>` (or
  `<base>...<head>`) to `.review-diff.patch` and the context bundle to
  `.review-context.json` with exclusive, no-follow creation, and refuses an
  empty or uncomputable diff.
- `REVIEW.md`, `AGENTS.md`, and other agent guidance stay in the copy.
- The CLI runs with `--setting-sources ""` (no user, project, or local
  settings, so no hooks, plugins, or permission allowlists),
  `--strict-mcp-config` (no MCP servers), `--no-session-persistence`, and
  `--tools`/`--allowedTools` `Read,Grep,Glob` (no shell, edit, write, or
  network tools), with `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` so its
  startup `git status` cannot start a filter driver.
- A raw-byte manifest of every entry in the copy is taken after the prepared
  files are placed and again after the CLI exits. Any difference, or an entry
  that cannot be read, discards the output as Reviewer failed ("review copy
  modified").
- Only one complete JSON object with `result` exactly `clean` or
  `needs_fixes` (or, in a strict pass, the expected `mode` marker) is
  forwarded, with `reviewed_head` stamped by the preset. Anything else is
  Reviewer failed, never Clean.

The copy is removed on every exit, including a stop at the wait budget. A run
killed outright (`SIGKILL`) can leave a `local-claude-review.*` directory and a
stale `git worktree` entry. Neither affects later reviews or your checkout.
To tidy up, delete the leftover directory and run `git worktree prune`; the
preset never prunes, because that could remove another run's entry.

**Budget.** One Claude pass takes about 900 s. A direct run whose backend
resolution selected the Claude preset, with no `--timeout` and no
`LOCAL_AI_REVIEWER_TIMEOUT`, gets 900 s and prints
`INFO: local AI reviewer timeout defaulted to 900s for the bundled Claude preset`.
An explicit `LOCAL_AI_REVIEWER_COMMAND` that names
`local-claude-review-command.sh` is not a backend selection and keeps 300 s,
so pass `--timeout 900` with it:

<!-- workflow-shell-contract: bash-zsh -->
```bash
LOCAL_AI_REVIEWER_COMMAND="$PWD/scripts/development-workflow/local-claude-review-command.sh" \
  ./scripts/development-workflow/local-ai-reviewer.sh <pr-number> <owner> <repo> \
  --repo-root "$PWD" --timeout 900
```

Under `pr-review-loop.sh` the loop always passes its own budget:
`review.wait_budgets.local-ai-reviewer`, or 1200 s by default, on every branch
and for every backend. On `spec/*` and `implementation-plan/*` branches the
strict contract pass shares that budget with an ordinary pass of about 900 s,
so raise `review.wait_budgets.local-ai-reviewer` (for example to 2100) when
you use the Claude backend with strict checks.

**Independence caveat.** A Claude reviewer may share a model family with the
agents that wrote the change, so a Clean result is weaker independent
evidence. Human review keeps its full weight, especially on security,
authorization, and data-migration changes.

**Migration from a local Claude patch.** A consumer that patched
`local-ai-reviewer.sh` to add a Claude backend or change the default (for
example MOME issue 3814) loses that patch when it syncs this template, and the
template's `local-claude-review-command.sh` replaces a local file with the same
name. To keep Claude as the repository default after syncing, set
`review.local_ai_reviewer.backend: claude` in `.ai-dev-workflow.yaml` and merge
it to the base branch; it applies to later pull requests. Existing
`LOCAL_CLAUDE_REVIEWER_*` settings keep working; set
`LOCAL_CLAUDE_REVIEWER_MODEL` to keep a pinned model, because the template uses
the CLI default. Unlike such a patch, the template keeps `REVIEW.md` and agent
guidance in the review copy. A patch that raised the documentation-branch wait
for local-ai-reviewer is no longer needed, because local-ai-reviewer already
gets 1200 s on every branch. The sync migration note in `sync-manifest.yaml`
lists the same steps.

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
`docs/workflow/development-workflow/strict-plan-checks.md` (eight closed-set
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
`source_declaration`, `phase_ordering`, `dependency_state`, `reversal_risk`,
and `test_scope_proportionality`.
When a spec is present for at least one changed plan, all eight identifiers are
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
| Unknown backend name (`LOCAL_AI_REVIEWER_BACKEND` or `review.local_ai_reviewer.backend`) | `RESULT=escalate`, `REASON=invalid_backend`; the diagnostic names `key=LOCAL_AI_REVIEWER_BACKEND` or `key=review.local_ai_reviewer.backend` and never the value |
| Claude preset refusal: CLI binary not found, review copy not created or holding a reserved path, empty or uncomputable diff, review copy modified, or no usable verdict | `RESULT=escalate`, `REASON=malformed_output` (Reviewer failed); a forwarded CLI failure excerpt that matches the model-access, credential, quota, or capacity rules is classified by those rules instead |
| Missing model access | `RESULT=escalate`, `REASON=missing_model_access` |
| Missing credentials or auth failure | `RESULT=escalate`, `REASON=missing_credentials` |
| Provider usage/quota refusal (no verdict on stdout) | `RESULT=escalate`, `REASON=quota_exhausted` (optional `QUOTA_RESET_AT`) |
| Checkout head mismatch | `RESULT=escalate`, `REASON=head_mismatch` |
| Missing `REVIEW.md` | `RESULT=escalate`, `REASON=review_contract_missing` |
| Reviewer still running when the wait budget ends (stopped by the watchdog) | `RESULT=waiting_on_reviewer`, `REASON=reviewer-no-verdict-yet`, `NO_VERDICT_YET=1`, `WAIT_EXPIRED_DETAIL=stopped_at_budget`, exit 4 — **No verdict yet**, not a failure |
| Command exits non-zero before the budget (including its own exit 124 or 137) | handled by the decision gate below — never No verdict yet |
| Malformed output | `RESULT=escalate`, `REASON=malformed_output` |
| Explicit disabled config | `RESULT=skipped`, `REASON=disabled_by_config` |

A skipped or escalated local result is availability evidence, not clean review
evidence.

### Wait budget and No verdict yet (#1789)

When `pr-review-loop.sh` runs the local reviewer, it passes the platform's
wait budget as `--timeout`: 1200 s by default on every branch, including
`spec/*` and `implementation-plan/*` (the local reviewer reviews documentation
branches with its own checklists, so it no longer receives the 180 s
documentation-branch budget), configurable as
`review.wait_budgets.local-ai-reviewer`. `LOCAL_AI_REVIEWER_TIMEOUT` applies
only to standalone companion runs. See "Reviewer wait budgets and outcome
classes" in
[`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md#reviewer-wait-budgets-and-outcome-classes-1789).

The command's exit status is never evidence that the budget ran out, because
a reviewer command can itself exit 124 or 137 before the budget. The
companion's watchdog runs the command in its own process group on every host
(`setsid` or `perl setpgrp`; GNU `timeout` is no longer used) and reports
expiry out of band: only when the watchdog reached the budget **and** the
command was still running does the companion stop the process group (TERM,
a 2 s grace, then KILL) and exit 4 with the No verdict yet keys. The stopped
process's partial output is not inspected. The loop reports that as
`RESULT=waiting_on_reviewer`, `REASON=reviewer-no-verdict-yet`, applies no
`reviewer-failed` label, and the runner re-waits once on the same revision
(Protocol 91 Step 7), when the local review runs again.

The strict spec and plan passes keep their non-blocking `strict_pass_failed`
state when they run out of the shared budget; they never change the ordinary
verdict.

### Setup-probe precedence (#1762)

The `missing_model_access`, `missing_credentials`, and `quota_exhausted` reasons
are derived from grep heuristics over the reviewer command's combined stdout and
stderr. Because the underlying CLI echoes parts of the reviewed document into
its log output, that text can contain quoted prose matching a heuristic (for
example a spec section about "usage limits"). A verdict on stdout therefore
outranks a heuristic match on stderr — but only a real verdict. The gate is
fail-closed: when stdout is not a valid verdict object the probes run against
the combined output on every exit code; when it is, the probes are cleared.

A *valid verdict object* is the shape the parser accepts: stdout must contain
exactly one JSON value — an object whose non-empty `result` is one of the
underscore enum values above, or — when `result` is absent or empty — an object
carrying an array in at least one of `findings`, `comments`, or `issues`.
Emitters must keep using the underscore forms exactly as listed above; the guard
and parser additionally tolerate case- and dash-variation (`NEEDS_FIXES`,
`needs-fixes`) only so that a provider-side normalization quirk cannot
masquerade as a setup failure.

The full decision gate, evaluated in this precedence order (first match wins;
rows are mutually exclusive):

| # | Precondition | stdout shape | probe pattern in combined output | Outcome | Next action |
| --- | --- | --- | --- | --- | --- |
| 1 | the watchdog stopped a command still running at the budget (`RUN_WITH_TIMEOUT_EXPIRED=1`) | not inspected | not inspected | `waiting_on_reviewer` / `reviewer-no-verdict-yet` (exit 4) | none — No verdict yet; the runner re-waits once |
| 2 | any command exit | not exactly one valid verdict object (invalid JSON, empty, multiple JSON values, `{}`, `{"issues":"quota exceeded"}`, `{"result":"provider_error"}`) | model-access pattern | `escalate` / `missing_model_access` | fix model config |
| 3 | any command exit | not a valid verdict object | auth / 401 / 403 pattern | `escalate` / `missing_credentials` | fix credentials |
| 4 | any command exit | not a valid verdict object | usage/quota pattern | `escalate` / `quota_exhausted` | wait for reset, then rerun |
| 5 | any command exit | valid verdict object with `reviewed_head` differing from the live head | — (probes cleared) | `escalate` / `head_mismatch` | rerun — a stale review is not trustworthy |
| 6 | command exit non-zero | valid verdict object whose outcome is `clean` | — (probes cleared) | `escalate` / `malformed_output` | rerun — a clean verdict on a failed run is not trustworthy |
| 7 | command exit 0 | valid verdict object whose outcome is `clean` | — (probes cleared) | parser outcome: `clean` | none |
| 8 | any command exit | valid verdict object whose outcome is `needs_fixes` / `needs_rerun` / `skipped` / `escalate` | — (probes cleared) | that parser outcome | fix reported findings or act on the verdict |
| 9 | any command exit | not a valid verdict object | none of the three patterns | `escalate` / `malformed_output` | inspect raw output |

A `result` outside the accepted enum, or a mistyped findings alias, already
fails rows 2-4/9: the gate never classifies such output as a valid verdict
object, so it cannot reach the parser's own enum check (kept as a backstop).

Genuine provider failures therefore keep their distinct reason codes on every
exit path rather than degrading to an inferred clean verdict or a bare
`malformed_output`. Non-verdict JSON that matches no probe pattern is rejected
by row 9 before the parser runs, so an empty findings set can never be read
back as clean.

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
- `QUOTA_RESET_AT` when `REASON=quota_exhausted` and the provider stderr includes
  a `try again at …` reset hint (`pr-review-loop.sh` forwards it on escalate)

Use `scripts/development-workflow/local-ai-reviewer-findings.py` to normalize
and compare local findings against ready-phase reviewer findings when measuring
whether the ready-phase reviewer found net-new blockers.
