# Local AI Reviewer: Claude Backend — Implementation Plan

**Spec**: [`1_1957-local-ai-reviewer-claude-backend_specs.md`](1_1957-local-ai-reviewer-claude-backend_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1957-local-ai-reviewer-claude-backend.smoke-test.md`](../../../testing/workflow/1957-local-ai-reviewer-claude-backend.smoke-test.md)
**Tracker**: #1957 (Full Pipeline, Feature)

---

## Summary

**Approach**: Add a bundled `claude` preset,
`scripts/development-workflow/local-claude-review-command.sh`, that reviews a
throwaway detached copy of the pull request head through the Claude Code CLI
with read-only tools. Extend backend resolution in `local-ai-reviewer.sh` so
the backend can come from the environment selection or from a new shared
default `review.local_ai_reviewer.backend`. The shared default is read through
a new single-file resolver subcommand. Give the Claude preset its own default
budget for direct runs (D3). `pr-review-loop.sh` is not changed (DN-1), and
the built-in default stays `codex`.

**Estimated complexity**: M

**Rationale**: There is one new script, about the size of the MOME reference.
One function and the budget logic change in `local-ai-reviewer.sh`, and one
small resolver subcommand is added. The work is mostly fail-closed edge cases
and test fixtures. There is no schema, loop, or label change.

**Dependencies**: None. The spec is merged (PR #2128). #1789 (per-platform wait
budgets) is already on `develop` (see Verification Log V7).

**Template fit (Protocol 02 Step 0)**: Passed. `.ai-dev-workflow.yaml` sets
`template.is_template: true`. The spec changes workflow tooling that the
template itself ships. It applies to every consumer whatever their stack, and
its acceptance criteria are stack-neutral.

**Repository mode**: `.ai-dev-workflow.yaml` declares no `mode`, so this is
`single_repo`. This repository owns the plan, and the artifact base is
`develop`.

---

## Verification Log

All repository commands were run at `49e71117` (`origin/develop`, which
contains the merged spec) in the worktree
`/Users/lhpaul/Git/DevStack/adf-1957-worktree` on 2026-11-06, except V18, which was run at the plan revision `3bf2f772` and
shown to hold at `49e71117`, and V19, which tests Git itself in scratch
repositories and does not depend on the revision.

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V1 | Repo revision | `git rev-parse --short HEAD` | `49e71117` |
| V2 | No Claude review preset exists yet (Rule 4) | `git ls-files scripts/development-workflow \| grep -i claude` | Only `claude-code-action-reviewer.sh` and its test, a different platform. No `local-claude-review-command.sh`. |
| V3 | No `local_ai_reviewer` configuration key is read anywhere yet (Rule 4) | `git grep -n "local_ai_reviewer" -- .ai-dev-workflow.yaml scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/workflow-lib.sh scripts/development-workflow/local-ai-reviewer.sh scripts/development-workflow/pr-review-loop.sh` | Matches only the `resolve_local_ai_reviewer_command` / `run_local_ai_reviewer_review` function names and the `local_ai_reviewer_context.v1` / `local_ai_reviewer_evidence.v1` schema strings. No configuration key. |
| V4 | `pr-review-loop.sh` is backend-agnostic (Rule 4) | `git grep -n "LOCAL_AI_REVIEWER_BACKEND" -- scripts/development-workflow/pr-review-loop.sh` | No match. |
| V5 | Consumers of `resolve_local_ai_reviewer_command` (Rule 5) | `git grep -n "resolve_local_ai_reviewer_command" -- scripts docs ':!docs/specs/developments'` | `local-ai-reviewer.sh:100` (definition), `local-ai-reviewer.sh:1107` (main flow), `tests/test-local-http-review-command.sh:425,434,441,450,459`, `tests/test_runner_diagnostic_emitters.py:3239,3243`, `tests/test-local-ai-reviewer.sh:1528`. Outcomes: see Rule 5 consumer table. |
| V6 | Consumers of `TIMEOUT` in `local-ai-reviewer.sh` (Rule 5) | `grep -n 'TIMEOUT' scripts/development-workflow/local-ai-reviewer.sh` | Assignment `:1061`, `--timeout` `:1067`, validation `:1087`, strict remaining `:800,:837`, ordinary run `:1376-1377` (exported as `LOCAL_AI_REVIEWER_TIMEOUT` and passed to `run_with_timeout`), no-verdict diagnostic `:1390`. |
| V7 | Loop budget for local-ai-reviewer, which DN-1 and AC-11 rely on (Rule 4) | `sed -n 10360,10365p;10453,10486p scripts/development-workflow/pr-review-loop.sh` | `reviewer_platform_reviews_documentation_branches` returns 1 only for `devin`. `reviewer_wait_budget_resolve` returns the override first, then the configured value, then the built-in default. It shortens only non-reviewing platforms on documentation branches. It applies `large_diff` only when the branch is not a documentation branch and no override was given. Existing test `tests/test-pr-review-loop-no-verdict-yet.sh:187` asserts `1200 default none` for local-ai-reviewer on a documentation branch. |
| V8 | How the loop hands configuration to the local reviewer (Rule 4) | `sed -n 5133,5150p;15648,15674p scripts/development-workflow/pr-review-loop.sh` | `local_ai_config_file="${AI_DEV_WORKFLOW_CONFIG_FILE:-${config_file:-}}"` is exported as `AI_DEV_WORKFLOW_CONFIG_FILE` to `local-ai-reviewer.sh`. `config_file` is `git show "origin/${_pr_base}:.ai-dev-workflow.yaml"` written to a temporary file. When that fails, it falls back to `workflow_config_file`. |
| V9 | Shared-file config helper used by peer reviewers (Rule 4) | `grep -n "workflow_effective_config_file" scripts/development-workflow/workflow-lib.sh scripts/development-workflow/coderabbit-cli-reviewer.sh`; `grep -n "^workflow_repo_root()\|^workflow_config_file()" -A6 scripts/development-workflow/workflow-lib.sh` | Defined at `workflow-lib.sh:135`. It returns `AI_DEV_WORKFLOW_CONFIG_FILE` when that names an existing file, else `workflow_config_file` when present, else status 1. `workflow_config_file` (`workflow-lib.sh:124`) is `<workflow_repo_root>/.ai-dev-workflow.yaml` outside a merge-budget session, and `workflow_repo_root` (`workflow-lib.sh:32`) is `workflow_script_dir/../..`: the checkout that holds the scripts. It is not `--repo-root`, the loop's `repo_root`, or the current directory. `coderabbit-cli-reviewer.sh:149` uses it. |
| V10 | The private review projection does not carry the new key (Rule 4, DN-5) | `sed -n 3142,3175p scripts/development-workflow/workflow-config-resolver.py` | `project_review_settings` projects only `on_draft.runner`, `on_draft.fallback_runner`, `on_*.github`, and `internal_reviewers_unavailable_policy`. |
| V11 | Editing `.ai-dev-workflow.yaml` comments does not require a parity-fixture update (Rule 4; corrects a spec-writer note) | `git grep -n '"base"' -- scripts/development-workflow/tests/fixtures/1993-selected-yaml-parity.json`; `sed -n 293,303p scripts/development-workflow/tests/test_selected_private_yaml.py`; `git log --oneline 25e702d2..HEAD -- .ai-dev-workflow.yaml`; `git show --stat cf01e299` | The corpus is pinned to base `25e702d2…` and P11 parses the stored `raw` strings only. It never re-reads the live file. `cf01e299` (#2102) edited `.ai-dev-workflow.yaml` after that base without touching the fixture. |
| V12 | Sync coverage for new files (Rule 4) | `sed -n 109,112p;310,316p sync-manifest.yaml` | `scripts/development-workflow/` (glob `**/*`) is synced, so the new preset ships without a manifest edit. `.ai-dev-workflow.yaml` is `product_repo_injection` with template-owned comments. |
| V13 | Diagnostic-emitter registry entries for the presets (Rule 4, AC-22) | `git grep -n "local-codex-review-command" -- scripts/development-workflow/tests/test_runner_diagnostic_emitters.py scripts/development-workflow/tests/test-runner-diagnostic-emitters.sh` | `test_D35_codex_companion_preserves_response_and_status` (`:665,:670`), the D67 bootstrap list (`:1631`), and the `# covers:` header at `test-runner-diagnostic-emitters.sh:18`. |
| V14 | Test selection and registration (Rule 4) | `sed -n 11,30p scripts/development-workflow/select-test-suites.sh` | A suite `test-<name>.sh` covers `<name>.sh` by convention. `# covers:` headers add paths. No central registry exists, so new suites are selected automatically. An optional `# duration:` header tunes sharding. |
| V15 | Claude CLI flags exist (Rule 4; unverified in CI) | `claude --version`; `claude --help \| grep -E -- "--setting-sources\|--strict-mcp-config\|--no-session-persistence\|--tools\|--allowedTools\|--output-format\|--model"` | Claude Code `2.1.318` lists all seven flags. `--tools` accepts a comma list or `""`. `--setting-sources` takes a comma list of `user, project, local`. |
| V16 | Doc surfaces naming the backend selection (Rule 4) | `git grep -ln "LOCAL_AI_REVIEWER_BACKEND\|local-ai-reviewer.md" -- ':!docs/specs/developments'` | `.ai-dev-workflow.local.env.example`, `.ai-dev-workflow.yaml`, `CHANGELOG.md`, `docs/testing/workflow/1653-*.smoke-test.md`, `docs/testing/workflow/1654-*.smoke-test.md`, `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`, `docs/workflow/development-workflow/integrations/pr-review-platform.md`, `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`, `scripts/development-workflow/local-ai-reviewer.sh`, and tests. No `.agents/`, `.codex/`, `.cursor/`, or `.claude/` mirror names the backend. |
| V17 | Tests that run the real reviewer with default resolution (Rule 5, D7) | `git grep -ln "local-ai-reviewer.sh" -- scripts/development-workflow/tests`, then per file `grep -c "LOCAL_AI_REVIEWER_COMMAND\|LOCAL_AI_REVIEWER_BACKEND\|LOCAL_AI_REVIEWER_DISABLE"` | Only `test-local-ai-reviewer.sh` (`default_command_*` at `:250-251`, `1653_s0_default_command_quotes_spaces` at `:1528`) and `test-local-http-review-command.sh` (`:418-463`) reach default resolution. Every other match sets an explicit command, stubs the companion, or only reads the source. |
| V18 | Today's decoder accepts a `review.local_ai_reviewer` block, so a template revert ignores a kept key (Reversal; Rule 4) | Write `review:` / `  local_ai_reviewer:` / `    backend: claude` to a scratch file, load `scripts/development-workflow/workflow-config-resolver.py` with `importlib`, and call `validate_selected_yaml(raw, path, review_fields=True)`; `git diff --stat 49e71117 3bf2f772 -- scripts/` | Returns `{'review': {'local_ai_reviewer': {'backend': 'claude'}}}` with no `ConfigError`, run at `3bf2f772`. The diff is empty, so the result holds at `49e71117`. |
| V19 | Git status does not see every byte change in a checkout, so containment cannot rely on it (D4.4; Rule 4) | With Git `2.56.0`: in a scratch repository, set `filter.strip.clean` to `tr -d Z`, commit `.gitattributes` with `g.txt filter=strip` and `g.txt` holding `x`, run `git worktree add --detach`, append `Z` to `g.txt` in the new worktree, then run `git status --porcelain=v1 -z --untracked-files=all --ignored`. Repeat with `core.autocrlf=true` and a CRLF-to-LF rewrite of a checked-out text file. | The clean-filter edit gives empty status output, so the edit is invisible. The CRLF-to-LF rewrite was reported as `M` on this Git version, but whether Git reports it depends on Git's line-ending rules and version, so D4.4 does not rely on it. |

---

## Factual claim evidence

**Rule 1 — sampling record (Claude CLI output).**

- **Producer**: Claude Code CLI `2.1.318`, `claude -p` with the D4.5 flag set
  and the CLI's default model, run by the plan author on 2026-11-06 in a
  throwaway Git repository with a one-file diff.
- **Population and window**: Print-mode output for review prompts in the
  D4.6 shape (ordinary pass, strict spec pass) plus one forced failure
  (unknown model), from a single session on 2026-11-06.
- **Occurrences examined**: 8. The original files lived in a short-retention
  scratch directory, so the redacted captures are embedded here. They contain
  no secrets. The SHAs are fixture commits.
  1. Ordinary, defective diff, exit 0:
     `{"result":"needs_fixes","reviewed_head":"76de1629…","findings":[{"severity":"blocking","path":"calc.py","line":2,"message":"add() now returns a - b instead of a + b, which breaks addition…","clear_in_scope":true}]}`
     followed by a newline. stderr was empty.
  2. Ordinary, defective diff, exit 0: same shape, with a different message
     wording.
  3. Ordinary, defective diff, exit 0: same shape, with a different message
     wording.
  4. Ordinary, clean diff, exit 0:
     `{"result":"clean","reviewed_head":"961b06bc…","findings":[]}` followed
     by a newline.
  5. Ordinary, clean diff, exit 0: same as occurrence 4.
  6. Strict spec pass, exit 0: `{"mode":"strict_spec_checks","findings":[]}`
     followed by a newline.
  7. Unknown model, exit 1. stdout:
     `There's an issue with the selected model (no-such-model-xyz). It may not exist or you may not have access to it. Run --model to pick a different model.`
     stderr: a context-window warning line, then
     `[claude-code:unrecognized_model] {"model":"no-such-model-xyz","query_source":"sdk"}`.
  8. Ordinary, clean diff, run with the parent Claude Code environment
     inherited (`CLAUDECODE` set), exit 0: same shape as occurrence 4.
- **Distinct variants**: (a) a bare compact JSON object on one line, in all
  seven successes, with no prose and no fence; (b) failure prose on
  **stdout** with a non-zero exit and diagnostics on stderr.
- **Saturation**: The successes stopped producing new variants after
  occurrence 1. Failure classes were sampled once.
- **Adequacy rationale**: No contract fixes the model's text, so the design
  accepts a small set of wrappers but fails closed (D4.7). It relies only on
  one complete top-level JSON object with a known `result` or `mode`.
  Everything else is Reviewer failed, never Clean. The unobserved wrappers it
  accepts are a markdown fence and bracket-free prose around one object; a
  malformed or truncated container is never recovered from a nested object.
  The sample is heterogeneous: it covers the ordinary, strict, and
  CLI-failure classes. Usage-limit and capacity messages could not be induced.
  The design does not bind to their wording. The preset forwards a bounded
  excerpt of both streams (D4.8), and the reviewer's existing quota and
  capacity patterns classify it (BR-15). Occurrence 7 shows that the CLI
  writes failures to stdout, which is why D4.8 forwards both streams.
  Occurrence 8 shows that a nested run from inside a Claude Code session
  works without scrubbing the environment.

**Rule 6 — scoped obligations.**

| Obligation | Governed scope | Discharge point |
| --- | --- | --- |
| The Claude 900 s default applies only when no explicit timeout was given (D3) | `local-ai-reviewer.sh` direct runs where backend resolution selected the Claude preset (BR-3 rules 3–5). Explicit commands and loop runs are excluded, because the loop always passes `--timeout`. | Implementation Order step 3; tests T-B6 to T-B9 |
| The private local configuration is never read for the backend (D1) | The `review-local-ai-backend` subcommand and its only caller, `local_ai_reviewer_shared_backend` | Implementation Order step 1 (reader takes only `--file`); test T-B5 |
| Preset diagnostics avoid the reviewer's probe vocabulary (D4.8) | Every message the preset itself writes to stderr, but not the forwarded CLI excerpt | Implementation Order step 2; test T-B11 |
| Existing suites stay hermetic against a consumer's shared default (D7) | The test sites listed in V17 that reach default resolution | Implementation Order step 5 |
| A "no shared file" or fallback-file case runs a copied tooling tree (D7) | T-B5's missing-configuration case and T-L1's working-tree case | Implementation Order steps 3 and 4 |
| Migration note version comparison (D8) | `/sync-template` runs whose `template.last_synced_version` is below the D8 version | Implementation Order step 7; release PR check in step 9 |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and approved base | `single_repo`; plan and implementation PRs target `develop` | `.ai-dev-workflow.yaml` (no `mode` key); parent handoff | 2026-11-06T13:11Z, `49e71117` | Current invocation item list `[1957]`; parent-supplied same-surface open PR evidence: none | `Verified` |
| Built-in default backend | `codex`, set by `${LOCAL_AI_REVIEWER_BACKEND:-codex}` | `scripts/development-workflow/local-ai-reviewer.sh:106` | 2026-11-06T13:11Z, `49e71117` | Same as above. The parent reported no open PR touching `local-ai-reviewer*`, `local-*-review-command*`, `pr-review-loop.sh`, `.ai-dev-workflow.yaml`, or `workflow-config-resolver*`. | `Verified` |
| This repository's shared reviewer configuration | `review.on_ready.github: [local-ai-reviewer]`; no `review.local_ai_reviewer` key; this plan does not add one (DN-7) | `.ai-dev-workflow.yaml:71-79`; V3 | 2026-11-06T13:11Z, `49e71117` | Same as above | `Verified` |
| Loop budget for local-ai-reviewer | override, else `review.wait_budgets.local-ai-reviewer`, else 1200 s, with no documentation-branch shortening | V7 | 2026-11-06T13:11Z, `49e71117` | Same as above | `Verified` |

No `Conflict` was found. At implementation start, re-check these rows against
`origin/develop` and record `Still valid`, or stop as `Stale or conflicting`.

---

## Design Decisions

Each decision is stated here once. Other sections refer to it by its D-number.

### D1 — Shared-default reader: resolver subcommand `review-local-ai-backend`

Add `review-local-ai-backend --file <path>` to
`scripts/development-workflow/workflow-config-resolver.py`. It reads **only**
the `--file` path and never calls `resolve_local_config`. It decodes the file
with `validate_selected_yaml(raw, path, review_fields=True)`, the decoder that
every other `review.*` reader uses. It walks `review` → `local_ai_reviewer` →
`backend`. It does not validate backend names; D2 owns the name set.

| # | Input | stdout | Exit |
| --- | --- | --- | --- |
| R1 | File missing, or not a regular file | empty | 0 |
| R2 | File present, but unreadable, not UTF-8, or rejected by the decoder (any `ConfigError`, `UnicodeError`, or `OSError`) | empty | 4 |
| R3 | `review`, `local_ai_reviewer`, or `backend` absent, or any of them `null` | empty | 0 |
| R4 | `backend` is the empty string | empty | 0 |
| R5 | `review` or `local_ai_reviewer` present but neither a mapping nor `null` | empty | 3 |
| R6 | `backend` present and not a string (list, mapping, number, boolean) | empty | 3 |
| R7 | `backend` is a non-empty string | the string and a newline | 0 |

Rows are evaluated top to bottom, and the first match wins. Exit 3 means
invalid (BR-5). Exit 4 means "counts as not set" (BR-4) and gets a warning
(D2). The subcommand catches its own exceptions, so the generic `main`
handler's exit 2 does not occur for these inputs.

### D2 — Backend resolution in `local-ai-reviewer.sh`

Rework `resolve_local_ai_reviewer_command` and add the helper
`local_ai_reviewer_shared_backend`. The helper calls `workflow_effective_config_file`
(V9). Status 1, meaning no file, counts as not set. Otherwise the helper runs
`workflow_command_with_safe_stderr python3 "$(workflow_config_resolver_script 2>/dev/null)" review-local-ai-backend --file "$config"`.
Evaluation order, first match wins:

1. `LOCAL_AI_REVIEWER_COMMAND` non-empty: return 0 unchanged (matrix row 2).
2. `LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1`: return 0 with no command (row 3,
   `missing_command` later).
3. `${LOCAL_AI_REVIEWER_BACKEND:-}` non-empty: that is the backend, and its
   source is the environment (rows 4–5). The shared default is not read.
4. Otherwise call `local_ai_reviewer_shared_backend`:
   - Exit 3: write
     `ERROR: configuration validation error; key=review.local_ai_reviewer.backend`
     and return 1 (row 7).
   - Non-empty value: that is the backend, and its source is the shared default
     (rows 6–7).
   - Exit 4, or any other non-zero status: write
     `WARN: configuration unreadable; key=review.local_ai_reviewer.backend; using the built-in default backend`
     and treat as not set (row 8).
   - Empty value: not set (row 8).
5. Not set: the backend is `codex` (row 8).

The name-to-preset case statement is the single source of backend names:

| Backend | Preset script | Label | Preset budget |
| --- | --- | --- | --- |
| `codex` | `local-codex-review-command.sh` | `Codex` | none |
| `http`, `openai_compat` | `local-http-review-command.sh` | `HTTP` | none |
| `claude` | `local-claude-review-command.sh` | `Claude` | 900 |
| anything else | — | — | — |

An unknown name returns 1 and writes a diagnostic that depends on the source.
From the environment, it writes the existing line
`ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND`, byte
for byte. From the shared default, it writes the `review.local_ai_reviewer.backend`
line given in step 4. The rejected value is never echoed. When the preset file
exists, keep the existing quoting and the existing INFO line format
(`INFO: LOCAL_AI_REVIEWER_COMMAND defaulted to bundled <Label> preset: <path>`),
and set the global `LOCAL_AI_REVIEWER_PRESET_TIMEOUT` to the preset budget, or
empty. `LOCAL_AI_REVIEWER_DISABLED=1` is still checked before this function,
at `local-ai-reviewer.sh:1102`.

### D3 — Direct-run budget precedence

Add `TIMEOUT_EXPLICIT=0`. Set it to 1 when `LOCAL_AI_REVIEWER_TIMEOUT` is
non-empty at the existing `TIMEOUT=` assignment, and when `--timeout` is
parsed. The existing validation (`case "$TIMEOUT"`) stays where it is. After
`resolve_local_ai_reviewer_command` succeeds, and before the `missing_command`
check: if `TIMEOUT_EXPLICIT=0` and `LOCAL_AI_REVIEWER_PRESET_TIMEOUT` is
non-empty, set `TIMEOUT` to it and write
`INFO: local AI reviewer timeout defaulted to <seconds>s for the bundled Claude preset`.
Every downstream consumer listed in V6 then reads the resolved `TIMEOUT`
unchanged (see the Rule 5 consumer table). Update the `--timeout` help line to
say "Defaults to `LOCAL_AI_REVIEWER_TIMEOUT`, then the bundled Claude preset's
900, then 300."

### D4 — The preset `local-claude-review-command.sh`

Write it new from the spec. The MOME file is only a read-only reference, and
it differs where the spec differs (D4.9). Shell contract: Bash. It starts with
the same diagnostic bootstrap prefix as `local-codex-review-command.sh`
(`DIAGNOSTIC_SCRIPT_DIR` guard plus `source …/workflow-lib.sh`), so the D67
bootstrap test applies to it. All of its own diagnostics go through
`workflow_diagnostic` to stderr. Nothing is written to stdout except the final
forwarded JSON.

**D4.1 Inputs** come from the environment that `local-ai-reviewer.sh` exports:
`REVIEWED_HEAD`, `BASE_BRANCH`, `CONTEXT_BUNDLE_PATH`,
`LOCAL_AI_REVIEWER_MODE`, `REVIEW_STAGE`, and `REVIEW_CHECKLISTS`, plus
`LOCAL_CLAUDE_REVIEWER_BIN` (default `claude`), `LOCAL_CLAUDE_REVIEWER_MODEL`,
`LOCAL_CLAUDE_REVIEWER_PROMPT`, and `LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT`. The
reviewed commit is always `REVIEWED_HEAD`, never `git rev-parse HEAD`. As in
the Codex preset, any `LOCAL_AI_REVIEWER_MODE` other than `strict`, including
unset, is an ordinary pass.

**D4.2 Check order.** This follows the spec's "Claude preset outcomes" table.
The first failure exits, and nothing is written to stdout.

| Step | Check | On failure | Exit |
| --- | --- | --- | --- |
| P1 | `command -v "$LOCAL_CLAUDE_REVIEWER_BIN"` resolves | diagnostic names `LOCAL_CLAUDE_REVIEWER_BIN` (outcome row 1) | 127 |
| P2 | Strict mode: `CONTEXT_BUNDLE_PATH` names a file. The marker is `strict_plan_checks` when `jq -e 'has("strict_plan_checks")'` succeeds, else `strict_spec_checks`. | refusal (row 2) | 2 |
| P3 | `REVIEWED_HEAD` matches `^[0-9a-f]{40}$` or `^[0-9a-f]{64}$`. The current directory is in a Git work tree, the review copy is created (D4.3), and neither reserved path exists in it (D4.4). | refusal: review copy not created, or reserved path present (row 3) | 2 |
| P4 | `BASE_BRANCH` is non-empty and does not start with `-`. The diff is computed (D4.4) and is non-empty. The prepared files are placed and the baseline fingerprint is taken (D4.4). | refusal: diff not computed, empty diff (row 4); placement or baseline fingerprint failed (row 3) | 2 |
| P5 | Run the CLI (D4.5). The watchdog in `local-ai-reviewer.sh` owns the budget (row 5). | — | — |
| P6 | Raw-byte containment fingerprint unchanged and fully read (D4.4) | discard output; diagnostic: review copy modified (row 6) | 3 |
| P7 | CLI exit status is 0 | diagnostic with the status plus bounded excerpts (D4.8) (row 7) | the CLI's status |
| P8 | Verdict gate (D4.7) | diagnostic naming the reason plus a bounded stdout excerpt (row 8) | 3 |

**D4.3 Review copy.** `work_dir="$(mktemp -d "${TMPDIR:-/tmp}/local-claude-review.XXXXXX")"`,
and the copy is `"$work_dir/review"`. Create it with
`GIT_LFS_SKIP_SMUDGE=1 git -C "$repo_root" -c core.hooksPath=/dev/null worktree add --detach "$work_dir/review" "$REVIEWED_HEAD"`,
where `repo_root` is `git rev-parse --show-toplevel` of the current
directory. Disabling hooks and LFS smudge keeps the developer's
`post-checkout` hooks and LFS downloads from running for a throwaway copy.
Raw CLI output goes in `"$work_dir"`, outside the copy. `REVIEW.md` and agent
guidance stay in the copy (BR-8).

**D4.4 Prepared files and containment.** The two prepared files live at the
root of the review copy, as BR-10 and BO-3 require: the reserved paths
`"$work_dir/review/.review-diff.patch"` and
`"$work_dir/review/.review-context.json"`. The copy's tree comes from the
reviewed commit, so the preset never writes through anything that commit
controls:

1. **Reserved-path refusal.** Right after the copy is created, and before any
   write into it, check each reserved path with
   `[ -e "$path" ] || [ -L "$path" ]`. If either exists in any form (regular
   file, directory, or symlink, including a dangling one), refuse at P3 with
   `review copy has a reserved path committed: <name>`. This applies whether
   or not a context bundle was supplied. The reserved paths sit directly in
   `"$work_dir/review"`, which `git worktree add` creates inside the
   preset's own `mktemp -d` directory, so no parent component comes from the
   reviewed commit.
2. **Diff outside the copy first.** Write
   `git -C "$work_dir/review" diff --no-ext-diff --no-textconv --no-color "origin/$BASE_BRANCH...$REVIEWED_HEAD"`
   to `"$work_dir/diff.patch"`, outside the copy. If that fails, use the same
   command with `"$BASE_BRANCH...$REVIEWED_HEAD"`. If both fail, or the file
   is empty, refuse (P4). These options stop a developer's external diff or
   textconv drivers from running.
3. **Exclusive no-follow placement.** Copy `"$work_dir/diff.patch"`, and
   `CONTEXT_BUNDLE_PATH` when it names a file, to the reserved paths with an
   embedded Python step that opens each destination with
   `os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)`.
   `O_EXCL` fails on any existing entry, including a symlink, so nothing is
   followed or overwritten even if step 1 were bypassed. Neither `cp`, a
   shell `>` redirection, nor `set -o noclobber` is used for these writes. A
   failed open refuses with the same message (row 3, exit 2).

After both writes, take the baseline fingerprint, so the preset's own
preparation never counts as a modification (BR-12). Take it again after the
CLI exits and compare the two (P6).

4. **Raw-byte manifest.** The fingerprint is a SHA-256 digest that an
   embedded Python step computes over a manifest of every entry under
   `"$work_dir/review"`, including the root, the linked worktree's `.git`
   file, and untracked and ignored entries. It walks with
   `os.walk(top, followlinks=False, onerror=<raise>)`, visits names in sorted
   byte order, and calls `os.lstat` on each entry. Each record holds the
   relative path as bytes, the entry type, and `stat.S_IMODE`. A directory
   adds nothing else, so an added or removed empty directory changes the
   digest. A symlink adds its `os.readlink` target string and is never
   followed. A regular file adds its size and the SHA-256 of its raw bytes,
   read through `os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)`
   after checking that `os.fstat` gives the same device and inode as the
   `lstat`. Any other type (FIFO, socket, device) is recorded by type only and
   is never opened. Each field is length-prefixed, so record boundaries cannot
   be forged. Timestamps are not recorded, so the CLI's reads do not count.
   The step prints only the 64-hex digest, which the preset keeps in a shell
   variable.
5. **No Git view.** The fingerprint runs no Git command. `git status`
   compares content after Git's input conversion, so an edit that a clean
   filter or end-of-line conversion maps back to the indexed blob is
   invisible to it (V19). Running Git there would also start the
   developer's clean-filter and `core.fsmonitor` programs on bytes that the
   CLI wrote. Comparing raw bytes after placement makes the result
   independent of how the copy was checked out. The checkout therefore keeps
   the developer's `core.autocrlf`, `core.eol`, and filter configuration, as
   any checkout of theirs does, and no `-c core.autocrlf=false` is added. That
   option would not neutralize `.gitattributes` `eol` or filter drivers in any
   case. Nothing runs in the copy between the two fingerprints except the CLI.
6. **Fail closed.** If the baseline manifest cannot be read in full, refuse
   with `review copy fingerprint not taken` (row 3, exit 2) before the CLI
   runs. If the post-run manifest cannot be read in full, or the digests
   differ, discard the output (row 6, exit 3). There is no size or entry
   bound, so no part of the copy goes unchecked. The cost is two full reads
   of a fresh checkout, which is linear in its size and runs inside the
   watchdog budget. On a very large repository the worst case is therefore
   No verdict yet, never an unchecked Clean.

**D4.5 CLI invocation.** Run from inside the copy, with stdin from
`/dev/null`, stdout to `"$work_dir/out"`, and stderr to `"$work_dir/err"`.
Arguments, in this order: `-p`, `--setting-sources ""`, `--strict-mcp-config`,
`--no-session-persistence`, `--tools "Read,Grep,Glob"`,
`--allowedTools "Read,Grep,Glob"`, then `--model "$LOCAL_CLAUDE_REVIEWER_MODEL"`
only when that is non-empty, then `--output-format text`, and the prompt last.
The variadic `--tools` and `--allowedTools` options must come before a
single-value option, so the prompt is not taken as a tool name. This is the
order sampled in Rule 1. No API key or settings file is passed, so the
caller's existing login is used.

**D4.6 Prompts.** The default ordinary prompt reuses the Codex preset's
review instructions verbatim: the stage sentence when `REVIEW_CHECKLISTS` is
non-empty, the result and findings field contract, the untrusted
body/comments sentence, and the evidence-verification sentences. The only
change is that the context path is `.review-context.json` in the current
directory, and the context clause is omitted when no bundle was copied. It
adds the Claude-specific sentence: "This review is read-only: report findings
instead of applying fixes, even where REVIEW.md asks reviewers to fix
directly." It also asks for exactly one compact JSON object with no prose and
no fence. The default strict prompts are the Codex strict prompts with the
same path change. `LOCAL_CLAUDE_REVIEWER_PROMPT` replaces the ordinary
instructions, and `LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT` replaces the strict
ones. In every case the preset appends a fixed operating note: there is no
shell, the full diff of `origin/<base>...<reviewed head>` is in
`.review-diff.patch` (read it with Read, and use Read, Grep, and Glob for
context), and do not edit, create, or delete files. The note is a runtime
fact of the preset, not review policy. The integration guide documents that
it is always appended.

**D4.7 Verdict gate** (embedded Python, read from `"$work_dir/out"`; see the
parser-risk addendum for edge cases):

1. Strip whitespace. If the text is wrapped in one markdown code fence,
   remove the fence and strip again.
2. If the whole text decodes as JSON: a JSON object is the candidate.
   Anything else fails with "not a JSON object".
3. Otherwise there is exactly one decode attempt. Find the **first** `{`;
   if there is none, fail with "no JSON object". Run
   `json.JSONDecoder().raw_decode` at that `{` only. If it fails, fail with
   "invalid JSON". The extractor never retries at a later `{`, so a
   truncated or malformed enclosing object or array is never recovered from
   an object nested inside it (BR-13 invalid JSON). If it succeeds, the text
   before and after the decoded object must contain none of `{`, `}`, `[`,
   or `]`; otherwise fail with "JSON outside the verdict object". This
   rejects a second object, a truncated enclosing array, and stray closing
   brackets. Otherwise the decoded object is the candidate.
4. Ordinary mode: `result` must be exactly `clean` or `needs_fixes`, and
   `findings`, when present, must be a list. An absent `findings` becomes
   `[]`. Set `reviewed_head = REVIEWED_HEAD` and pass every other key through
   unchanged, including `evidence_verification`. Print compact JSON.
5. Strict mode: `mode` must equal the P2 marker, and `findings`, when present,
   must be a list. Print only `{"mode": <marker>, "findings": <list>}`.

**D4.8 Diagnostics and failure excerpts.** On P7, write the CLI status, then
up to 2000 bytes of the CLI stdout and up to 2000 bytes of the CLI stderr,
each under its own label, through `workflow_redact_text`. The reviewer's
existing quota, credential, and capacity probes see failure text on either
stream (Rule 1, occurrence 7). On P8, write up to 2000 bytes of stdout the
same way. The preset's own messages must not contain the reviewer probe
vocabulary (`local-ai-reviewer.sh:1358,1440,1453,1457`): no "usage limit",
"quota", "overloaded", "capacity", "429", "401", "403", "unauthorized",
"forbidden", "credentials", or "model" next to "access", "unavailable", or
"missing". A preset refusal therefore always ends as
`RESULT=escalate` / `REASON=malformed_output` (Reviewer failed). The forwarded
CLI excerpt keeps the existing classification, which is the same exposure the
Codex preset has today.

**D4.9 Differences from the MOME reference.** The spec takes precedence. The
template keeps `REVIEW.md`, `AGENTS.md`, and `.cursor/rules` in the copy. It
uses no default model. It reviews `REVIEWED_HEAD`, not the checkout `HEAD`.
It refuses a reviewed commit that holds a reserved path, and it places the
prepared files with exclusive no-follow creation instead of `>` and `cp`.
It uses fail-closed extraction of one complete top-level object, with a
single decode attempt at the first `{`, instead of a greedy `\{.*\}`. Its
containment is a raw-byte manifest of the whole copy instead of Git status. Its diff and copy creation
are hook-, driver-, and LFS-free. It forwards a strict response as
`{mode, findings}` only. It also excerpts CLI stdout on failure.

### D5 — Cleanup and interruption

The preset installs `trap cleanup EXIT` and maps TERM, INT, and HUP to
`exit 143`, `exit 130`, and `exit 129`. Each of those reaches the EXIT trap.
`cleanup` runs `git -C "$repo_root" worktree remove --force "$work_dir/review"`
as a best-effort step (`|| true` with a `# workflow-shell-guard: allow SH001`
rationale), then `rm -rf "$work_dir"`. The watchdog sends TERM to the process
group, waits 2 s, then sends KILL (`local-ai-reviewer.sh:206-253`), so a normal
budget stop cleans up. A KILL can leave a stale `local-claude-review.*`
directory and a stale `git worktree` entry. Later runs create a new unique
directory, and the developer's working-tree status does not include worktree
administration entries, so the leftover affects neither (BR-10). The preset
never runs `git worktree prune`, because that could remove another concurrent
run's or the developer's entries. The integration guide documents
`git worktree prune` as an optional manual clean-up.

### D6 — No loop change, no wrapper

`pr-review-loop.sh` is not modified (DN-1, V4, V7). No
`local-claude-reviewer.sh` wrapper is added (DN-6).

### D7 — Hermetic existing suites

The new shared-default read makes default resolution depend on the runtime
repository's `.ai-dev-workflow.yaml` (V9). In a consumer that sets
`review.local_ai_reviewer.backend: claude`, existing suites that expect the
Codex default would fail after sync. Pin `AI_DEV_WORKFLOW_CONFIG_FILE` to a
neutral fixture file (an empty YAML document created by the suite) at each
default-resolution site in V17. The new suites also pin it, to their own
fixtures.

Pinning cannot express "no shared file": an unset or missing
`AI_DEV_WORKFLOW_CONFIG_FILE` falls back to the `.ai-dev-workflow.yaml` of
the checkout that holds the scripts (V9). That fallback is a consumer's own
file after sync. A test case whose input is "no shared file", or "the
fallback file holds a value", runs a copied tooling tree. The tracked
`scripts/development-workflow/*.sh` and `*.py` files are copied into a
fixture checkout, and the fixture root holds the `.ai-dev-workflow.yaml` the
case needs, or none. `test_private_source_consumers.py:107-116` already
builds its runtime this way. This governs T-B5's missing-configuration
case and T-L1's working-tree case. Steps 3 and 4 discharge it. Every other
new case pins the variable.

### D8 — Consumer migration note in `sync-manifest.yaml`

Add a `migration_notes` entry with `version` and `applies_if_syncing_from_before`
set to `"0.50.0"`, the next minor version for a feature. If the release ships as
`0.49.x`, the note is shown again on later syncs until `0.50.0`. That is
harmless because the note is advisory, and step 9 asks the release to align
the value. The note's title is "local-ai-reviewer Claude backend replaces
local Claude patches". Its manual steps:

1. Before syncing, look for a local patch to `local-ai-reviewer.sh` that adds
   `claude` or changes the default. Look for a local
   `local-claude-review-command.sh`, which the template file with the same
   name overwrites.
2. After syncing, to keep Claude as the repository default, set
   `review.local_ai_reviewer.backend: claude` in `.ai-dev-workflow.yaml` and
   merge it to the base branch. It takes effect on later pull requests
   (BR-4).
3. `LOCAL_CLAUDE_REVIEWER_*` settings keep working. Set
   `LOCAL_CLAUDE_REVIEWER_MODEL` to keep a pinned model, because the template
   uses the CLI default.
4. `REVIEW.md` and agent guidance now stay in the review copy.
5. Drop any `doc_branch_default_max_wait` patch. local-ai-reviewer already gets
   1200 s on every branch.
6. Raise `review.wait_budgets.local-ai-reviewer` when strict checks share the
   budget.

The integration guide carries the same note in prose (BR-17, AC-21).

### D9 — Shared-default documentation stays comments-only

The `.ai-dev-workflow.yaml` change is commented guidance only, with no live
key (DN-7). Projects created from the template therefore stay on `codex`.

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] `scripts/development-workflow/local-claude-review-command.sh`: new
  executable preset implementing D4 and D5. Header comment: purpose, the
  isolation flags and why each is needed, the 900 s expectation and the
  explicit-command caveat (AC-10), and the independence caveat (BR-16).
- [ ] `scripts/development-workflow/local-ai-reviewer.sh`: D2 (resolution plus
  `local_ai_reviewer_shared_backend`) and D3 (`TIMEOUT_EXPLICIT`, preset
  budget, INFO line). Usage text (AC-8): the `--timeout` default line, the
  `LOCAL_AI_REVIEWER_COMMAND` / `LOCAL_AI_REVIEWER_BACKEND` lines (`codex`,
  `http`, `claude`), the shared default key and the BR-3 order in one short
  paragraph, and the four `LOCAL_CLAUDE_REVIEWER_*` settings.
- [ ] `scripts/development-workflow/workflow-config-resolver.py`: the D1
  subcommand (`cmd_review_local_ai_backend` plus a `build_parser`
  registration). Add `local_ai_reviewer` and `backend` to
  `CONFIG_ERROR_KEYS`, so that a future `format_config_error` with this key
  path is not shown as `unknown`.

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml`, comments only (D9, AC-8). In the "Local AI
  reviewer platform options" comment block, add `claude` to
  `LOCAL_AI_REVIEWER_BACKEND` and add the four `LOCAL_CLAUDE_REVIEWER_*`
  lines and the `LOCAL_AI_REVIEWER_TIMEOUT` note (300, or 900 for the Claude
  preset). After the `wait_budgets` example, add a commented
  `# local_ai_reviewer:` / `#   backend: claude` example with the BR-3 order
  and the "read from the base branch" note (BR-4). No parity-fixture change is
  needed (V11).
- [ ] `sync-manifest.yaml`: the D8 migration note. Category coverage is
  unchanged (V12).

### Shared Packages / Libraries

- None. `workflow-lib.sh` is not changed; `workflow_effective_config_file`,
  `workflow_command_with_safe_stderr`, and `workflow_config_resolver_script`
  are reused.

### Tests

See Testing Strategy.

---

## Decision-gate matrix coverage

Classification: **applicable**. Backend resolution and the direct-run budget
are workflow decision gates with several inputs and outcomes. They are
mirrored in help text, configuration comments, and two integration guides.

| Gate (spec matrix) | Inputs | Allowed outcomes | Next action per outcome | Tests | Mirror surfaces | Examples |
| --- | --- | --- | --- | --- | --- | --- |
| Backend resolution rows 1–8 | disabled flag, explicit command, default-disabled flag, environment selection, shared default (R1–R7) | Skipped; explicit command; `missing_command`; preset (`codex`/`http`/`claude`); `invalid_backend` with the environment or shared key | Skipped: no review evidence. Reviewer failed: operator fixes the configuration and re-runs. Preset: review runs. | T-B1 to T-B5, T-R1 to T-R7, existing `disabled_*` / `missing_command_*` | `local-ai-reviewer.sh` usage text, `.ai-dev-workflow.yaml` comments, `integrations/local-ai-reviewer.md` Configuration, `integrations/pr-review-platform.md` comment | Guide snippets: environment selection and shared-default YAML |
| Direct-run budget rows 1–4 | `--timeout`, `LOCAL_AI_REVIEWER_TIMEOUT`, command source | given value; 900 with INFO; 300 | Budget passed to the watchdog | T-B6 to T-B9 | usage `--timeout` line, YAML `LOCAL_AI_REVIEWER_TIMEOUT` comment, guide budget paragraph | Guide: explicit command plus `--timeout 900` |
| Preset outcomes rows 1–11 | D4.2 P1–P8, plus the watchdog | Reviewer failed, No verdict yet, Needs rerun (existing capacity rule), Clean, Needs fixes, strict report or `strict_pass_failed` | Existing loop handling for each class; no new class | T-C1 to T-C22, T-B10 to T-B13 | guide Failure Semantics table | None (not an example surface) |
| Loop budget (AC-11 regression) | branch type, override, configured, built-in, backend selection | the existing budget, the same for every backend | unchanged | T-L2 | none changed: Protocol 93 budget table (`:612`) already states 1200 | None |

---

## Rule 5 consumer table

The changed units are `resolve_local_ai_reviewer_command` (V5) and the
resolved `TIMEOUT` (V6).

| Consumer site | Path through the chain | Outcome after the change |
| --- | --- | --- |
| `local-ai-reviewer.sh:1107` main flow | DISABLED check, then resolution (D2), then budget (D3), then `missing_command` check | Unchanged for every existing input (BR-1). Adds `claude` and the shared default. |
| `tests/test-local-http-review-command.sh:425-459` | env `http` / `openai_compat` / `openai` / `chat_completions` / `not-a-backend` | The environment wins before the shared read. The `openai` assertion at `:445` still matches the unchanged diagnostic line. D7 pins the configuration for hermeticity. |
| `tests/test_runner_diagnostic_emitters.py:3239,3243` | env set to a secret value, then to `codex` / `http` | Unchanged. Add `claude` to the success loop (AC-22). |
| `tests/test-local-ai-reviewer.sh:1528` (`1653_s0_default_command_quotes_spaces`) | no environment, so the shared read happens (V9) | Codex stub under D7's neutral configuration. Without D7, a Claude-opted consumer would fail here. |
| `local-ai-reviewer.sh:1376-1377` ordinary run | `run_with_timeout "$TIMEOUT"` and the exported `LOCAL_AI_REVIEWER_TIMEOUT` | Claude direct run without an explicit timeout gets 900. Every other case is unchanged. |
| `local-ai-reviewer.sh:800,837` strict remaining | `TIMEOUT - elapsed` | The strict pass shares the resolved budget, as today (BR-7). |
| `local-ai-reviewer.sh:1390` no-verdict diagnostic | prints `${TIMEOUT}s` | Reports the resolved value. |
| `local-http-review-command.sh` via the exported `LOCAL_AI_REVIEWER_TIMEOUT` | HTTP is never given a preset budget | Unchanged. |
| `pr-review-loop.sh:5146` | always passes `--timeout` | `TIMEOUT_EXPLICIT=1`, so loop budgets are unchanged (BR-7). |

---

## Parser-risk addendum

Classification: **parser-risk applies**. D4.7 parses the model's free-text
output, and D1 decodes structured configuration. There are no suppressions,
so suppression semantics are not applicable.

**Edge-case enumeration — verdict gate (D4.7).** Unit tests are in
`scripts/development-workflow/tests/test-local-claude-review-command.sh`.

| Case | Input on the stand-in's stdout | Expected | Test |
| --- | --- | --- | --- |
| E1 | bare object, `result:"clean"` (Rule 1 variant a) | forwarded with `reviewed_head` stamped | T-C10 |
| E2 | object inside a json-tagged code fence | forwarded | T-C11 |
| E3 | prose without brackets, then one object, then prose without brackets | forwarded | T-C11 |
| E4 | prose with `{braces}` that are not JSON, then one object | Reviewer failed: invalid JSON (the single decode attempt is at the first `{`) | T-C12 |
| E5 | two separate objects | Reviewer failed: JSON outside the verdict object | T-C12 |
| E6 | no `{` at all, or empty output | Reviewer failed: no object | T-C12 |
| E7 | truncated object `{"result":"clean"` | Reviewer failed: invalid JSON | T-C12 |
| E8 | whole output is a JSON array holding one verdict | Reviewer failed: not an object | T-C12 |
| E9 | `result` missing, with a `findings` array (BO-12 lookalike) | Reviewer failed | T-C13 |
| E10 | `result:"Clean"`, `"needs-fixes"`, or `"skipped"` | Reviewer failed (exact match) | T-C13 |
| E11 | `findings` is a string or an object | Reviewer failed | T-C13 |
| E12 | `reviewed_head` absent, or a different SHA | forwarded with the actual `REVIEWED_HEAD` | T-C14 |
| E13 | `evidence_verification` present | preserved byte-equivalent after JSON round-trip | T-C14 |
| E14 | strict: correct marker, `findings: []` | `{"mode":…,"findings":[]}` only | T-C15 |
| E15 | strict: wrong marker, missing marker, or non-list findings | refusal, exit 3 | T-C16 |
| E16 | strict: extra `result` / `reviewed_head` keys | stripped from the output | T-C15 |
| E17 | a nested object inside a valid verdict, bare or after bracket-free prose | forwarded as one object (outer decode) | T-C10 |
| E18 | truncated enclosing verdict whose findings hold a nested verdict: `{"result":"needs_fixes","findings":[{"result":"clean"}]` | Reviewer failed: invalid JSON; the nested `clean` object is never forwarded, and stdout is empty | T-C12 |
| E19 | truncated enclosing array `[{"result":"clean"}` | Reviewer failed: JSON outside the verdict object | T-C12 |
| E20 | one valid object followed by a stray `}` or `]` | Reviewer failed: JSON outside the verdict object | T-C12 |

**Edge-case enumeration — shared default (D1).** Unit tests are in
`scripts/development-workflow/tests/test-local-ai-reviewer-backend.sh`, which
calls the resolver CLI directly.

| Case | `--file` content | Expected (D1 row) | Test |
| --- | --- | --- | --- |
| Y1 | file path does not exist | R1 | T-R1 |
| Y2 | empty file, or a comment-only file | R3 | T-R1 |
| Y3 | `review:` present without `local_ai_reviewer` | R3 | T-R1 |
| Y4 | `backend:` with no value, or `backend: null` | R3 | T-R2 |
| Y5 | `backend: ""` | R4 | T-R2 |
| Y6 | `backend: claude`, `backend: "claude"`, `backend: claude # note` | R7 `claude` | T-R3 |
| Y7 | `backend: [claude]`, a block mapping under `backend`, `backend: 3`, `backend: true` | R6 | T-R4 |
| Y8 | `local_ai_reviewer: claude` (a scalar) | R5 | T-R4 |
| Y9 | invalid YAML, a duplicate `backend` key, a non-UTF-8 byte, a flow mapping such as `local_ai_reviewer: {backend: claude}` (the `review_fields=True` decoder rejects non-empty flow mappings) | R2 | T-R5 |
| Y10 | `backend: CLAUDE` or `backend: " claude"` | R7 raw value; D2 rejects it as `invalid_backend` | T-R6 |
| Y11 | other `review.*` keys around the new block (`on_draft`, `wait_budgets`) | the platform lists and wait budgets read by the existing awk and resolver readers are unchanged | T-R7 |

---

## Concurrency safety checklist

Classification: **applies**. A watchdog signal can arrive while the preset is
creating or tearing down the review copy. Two reviews of the same repository
(for example a loop and a manual run) can also create worktrees at the same
time.

- **Shared mutable state guards**: The only shared state is the repository's
  `.git/worktrees` administration directory. Git keeps one administration
  entry per worktree path, and each run uses a unique `mktemp -d` path
  (D4.3), so concurrent runs never target the same entry. The preset never
  prunes (D5).
- **Re-entrancy / in-flight tracking**: Not applicable. Each preset process
  handles one review. The capacity retry in `local-ai-reviewer.sh` runs the
  preset again, one run after another, and each run creates its own copy.
- **Event deduplication**: Not applicable. No event is delivered twice. A
  repeated TERM after the trap fired only re-enters an `exit`, and cleanup is
  idempotent, because `worktree remove` is best-effort and `rm -rf` succeeds
  on a missing path.
- **Listener and resource cleanup**: The EXIT trap removes the worktree and
  `work_dir` (D5). The CLI child is in the watchdog's process group and gets
  the same TERM and KILL.
- **Race conditions at initialization**: A TERM before `work_dir` exists runs
  a cleanup that tolerates unset paths (`${work_dir:-}` guards). A TERM during
  `worktree add` leaves at most a half-created entry, which a later run does
  not reuse.
- **Race conditions at teardown**: A KILL during cleanup can leave the
  directory and the worktree entry. BR-10 accepts that, and test T-C18 proves
  that a later run is unaffected.
- **Error propagation across async boundaries**: The CLI's status and output
  are collected after it exits (P6–P8). The watchdog's expiry flag, not the
  preset's status, decides No verdict yet (`local-ai-reviewer.sh:1384-1399`).

This adds no new concurrency pattern. It follows the existing
watchdog/process-group pattern from #1789 and #1635.

---

## Testing Strategy

**Test types**: shell unit and integration suites that use a stand-in
`claude` binary selected through `LOCAL_CLAUDE_REVIEWER_BIN` or `PATH`. No
real Claude login is used in CI. A manual smoke run with the real CLI is
covered by the runbook.

The **stand-in CLI** (a fixture generated by the suite) appends its argv (one
argument per line), `$PWD`, the `LOCAL_AI_REVIEWER_TIMEOUT` value in its environment, and the prompt to a record file. It optionally
records whether `.review-diff.patch` and `.review-context.json` are readable
and what they contain. It can also print scripted stdout and stderr, exit with
a given status, sleep, ignore TERM, or create or edit a file in its working
directory. A **fixture repository** per suite has `REVIEW.md`, a
`refs/remotes/origin/develop` ref, one commit ahead of it, and a GitHub-style
`origin` URL.

**Coverage intent.** These enumerations are indicative, not binding. A
coverage-equivalent set is acceptable when every spec AC and every parser and
outcome row stays covered. The volume is proportionate: the deliverable is a
fail-closed reviewer gate with about a dozen distinct refusal and verdict
paths. Each needs one planted-violation case, and each case is one stand-in
configuration plus a few assertions.

**New suite `scripts/development-workflow/tests/test-local-claude-review-command.sh`**
(`# covers: scripts/development-workflow/local-claude-review-command.sh`):
the preset invoked directly with the D4.1 environment.

| Test | Covers |
| --- | --- |
| T-C1 | AC-12: the argv contains `-p`, `--setting-sources` with an empty value, `--strict-mcp-config` without `--mcp-config`, `--no-session-persistence`, `--tools Read,Grep,Glob`, and `--allowedTools Read,Grep,Glob`. The prompt is the last argument. `$PWD` is under `local-claude-review.` and is not the fixture checkout. |
| T-C2 | AC-13: the stand-in reads a `.review-diff.patch` equal to `git diff origin/develop...<head>` and a `.review-context.json` equal to the bundle. The fixture's `git status --porcelain` is identical before and after. |
| T-C3 | AC-13 / BR-10: no `local-claude-review.*` directory or worktree entry remains after a success, a non-zero CLI exit, and a P4 refusal. |
| T-C4 | AC-14: empty diff (head equals `origin/develop`) gives exit 2, a refusal message, and no stand-in record. |
| T-C5 | AC-14: no `origin/develop` and no local `develop` gives exit 2 and no stand-in record. |
| T-C6 | AC-18: `REVIEWED_HEAD` not in the repository, or not hex, gives exit 2, "review copy" in the message, and no stand-in record. |
| T-C7 | AC-15: the stand-in creates a new file, edits a tracked file, writes an ignored file, edits `.review-diff.patch`, creates an empty directory, removes an empty directory it finds, changes a tracked file's mode, or retargets a committed symlink, and prints a clean verdict. Each gives exit 3, "modified" in the message, and empty stdout. |
| T-C8 | AC-18: a missing binary gives exit 127, `LOCAL_CLAUDE_REVIEWER_BIN` in the message, and empty stdout. |
| T-C9 | AC-18 / BR-15: the stand-in exits 1 with text on stdout only, then on stderr only. Each gives the status plus a bounded excerpt on stderr; a 10 kB output is truncated. |
| T-C10 to T-C16 | AC-16, AC-17: parser cases E1–E20. T-C12 holds every extraction refusal (E4–E8, E18–E20); each asserts exit 3, empty stdout, and no `clean` text forwarded. E18 is the required truncated-container counterexample (BR-13 invalid JSON). |
| T-C17 | AC-20: `LOCAL_CLAUDE_REVIEWER_MODEL=opus` adds `--model opus`; unset adds no `--model`. The two prompt overrides replace the ordinary and strict instructions, and the operating note is still appended. |
| T-C18 | BR-10: a stale registered worktree and directory from an earlier run (simulated) does not stop a new run, and the fixture status is unchanged. |
| T-C19 | AC-19: the default prompt contains `REVIEW.md`, each `REVIEW_CHECKLISTS` entry, the untrusted-data sentence, `review_evidence_verification.v1`, `verification_request_id`, the read-only sentence, and the report-instead-of-fixing sentence. `REVIEW.md` exists in the copy. For parity, run `local-codex-review-command.sh` with a stand-in `codex` that records its prompt, and assert that the shared sentences in both prompts are identical. |
| T-C20 | AC-17 / P2: strict mode without `CONTEXT_BUNDLE_PATH` gives exit 2 before any copy is created. |
| T-C21 | AC-13 / BR-10 / P3 (D4.4): the fixture's reviewed commit adds a reserved path as (a) a symlink `.review-diff.patch` to a sentinel file outside the fixture and the temporary directory, (b) a symlink `.review-context.json` to a second sentinel, with a bundle supplied, (c) a dangling symlink `.review-diff.patch` whose target path is outside both, (d) a regular file `.review-context.json` with no bundle supplied, and (e) a directory `.review-diff.patch/`. Each gives exit 2, "reserved path" in the message, empty stdout, and no stand-in record. Each sentinel's bytes and `git hash-object` are unchanged, the dangling target is still absent, the fixture status is unchanged, and no `local-claude-review.*` directory or worktree entry remains. |
| T-C22 | AC-15 / BR-12 (D4.4 items 4–6): edits that Git status cannot see. (a) Clean filter: the fixture's developer configuration sets `filter.strip.clean` to `tr -d Z` and the reviewed commit's `.gitattributes` maps `g.txt` to it. The stand-in appends `Z` to `g.txt`, and records the copy's `git status --porcelain=v1 -z --untracked-files=all --ignored` before and after its edit to a file outside the copy; the test asserts the two are equal, which proves the edit is invisible to Git status. (b) End of line: the fixture's developer configuration sets `core.autocrlf=true`, and the reviewed commit has an LF-committed text file, which the checkout writes with CRLF, and a file committed with CRLF. The stand-in rewrites each CRLF file in the copy to LF. The status-equality assertion is not made here, because whether Git reports this edit depends on the Git version (V19). (c) Unreadable entry: the stand-in creates a directory with mode `000` that holds a file; the run fails either on the changed digest or on the unreadable post-run manifest, and both are row 6. Each prints a clean verdict and gives exit 3, "modified" in the message, and empty stdout. (d) A run whose stand-in only reads files gives the forwarded verdict, so `atime` changes do not count. |

**New suite `scripts/development-workflow/tests/test-local-ai-reviewer-backend.sh`**
(`# covers:` `local-ai-reviewer.sh`, `local-claude-review-command.sh`,
`workflow-config-resolver.py`): runs `local-ai-reviewer.sh` end to end with a
`gh` mock in the style of `test-local-ai-reviewer.sh`, `--repo-root` set to
the fixture, and stand-in `claude` and `codex` binaries.

| Test | Covers |
| --- | --- |
| T-B1 | AC-1: env `claude` runs Claude. The INFO line names the Claude preset. The `codex` stand-in record is empty. `RESULT=clean` / `needs_fixes` follows the stand-in verdict. A stand-in `clean` verdict that omits `reviewed_head`, and one that reports a different SHA, each still give `RESULT=clean` with `REVIEWED_HEAD` equal to the PR head, not a `head_mismatch` parse status (AC-16 at the `local-ai-reviewer.sh:1542-1543` head comparison). |
| T-B2 | AC-2: no command, no environment, and a neutral configuration run Codex, and the stand-in `claude` is not invoked. |
| T-B3 | AC-3: an explicit command runs whatever the environment and shared settings say. `LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1` with shared `claude` gives `missing_command`. |
| T-B4 | AC-4: shared `claude` runs Claude. Shared `claude` with env `http` gives the HTTP INFO line. An empty environment selection with shared `claude` runs Claude. |
| T-B5 | AC-5: shared `codex`, `http`, `openai_compat`, and `claude` each select their preset. Absent, empty, missing, or unparseable configuration gives Codex, and unparseable also emits the D2 WARN line. The missing case runs a copied tooling tree with no `.ai-dev-workflow.yaml` (D7). A list value gives `invalid_backend`. A `.ai-dev-workflow.local.yaml` with `backend: claude`, placed both next to the pinned neutral shared file and in the `--repo-root` fixture, with no environment selection, still gives Codex. |
| T-B6 | AC-9: a Claude direct run with no timeouts emits the budget INFO line, and the stand-in records `LOCAL_AI_REVIEWER_TIMEOUT=900` in its environment. `local-ai-reviewer.sh:1376` exports the resolved budget to the command, and the preset passes its environment through to the CLI. No 900 s sleep is run. |
| T-B7 | AC-9: `--timeout 120` makes the stand-in record 120. `LOCAL_AI_REVIEWER_TIMEOUT=600` makes it record 600. Neither emits the budget INFO line. |
| T-B8 | AC-9: an invalid `--timeout` or `LOCAL_AI_REVIEWER_TIMEOUT` still gives `configuration validation error; key=--timeout` and exit 2. |
| T-B9 | AC-10: the Codex and HTTP stand-ins record 300. An explicit command naming `local-claude-review-command.sh` makes the Claude stand-in record 300, with no budget INFO line. |
| T-B10 | AC-18 / BR-15: a usage-limit message on the stand-in's stdout, then on its stderr, each with exit 1, gives `REASON=quota_exhausted`. A `model access` message gives `REASON=missing_model_access` (spec-review note b). Both are Reviewer failed. |
| T-B11 | AC-18 / D4.8: each preset refusal (missing CLI, copy, empty diff, modified copy, malformed output, using the E18 truncated-container output as the malformed case) gives `RESULT=escalate` and `REASON=malformed_output`, never a probe reason. |
| T-B12 | AC-18: a capacity message (`overloaded`) is retried and ends `RESULT=needs_rerun` / `provider_overloaded`, never Clean. |
| T-B13 | AC-18: a stand-in that sleeps past `--timeout 3` gives `RESULT=waiting_on_reviewer`, exit 4, and no leftover directory after the grace period. A following run on the same checkout succeeds. |
| T-B14 | AC-7: an unknown env selection gives exactly the D2 environment-key line, and an unknown shared default gives exactly the D2 shared-key line, each as a whole stderr line. A rejected planted marker value appears in neither stdout nor stderr. Neither stand-in is invoked. |
| T-B15 | AC-8: the `--help` output names `claude`, `review.local_ai_reviewer.backend`, and each `LOCAL_CLAUDE_REVIEWER_*` setting. |
| T-R1 to T-R7 | D1 cases Y1–Y11, through `python3 workflow-config-resolver.py review-local-ai-backend --file …` (and the existing readers for Y11) |

**Changes to existing suites**

| Suite | Change | Covers |
| --- | --- | --- |
| `tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh` | T-L1: source the loop with `HARNESS_MODE=1`, unset `AI_DEV_WORKFLOW_CONFIG_FILE`, and run against a copied tooling tree (D7) whose root `.ai-dev-workflow.yaml` has `backend: claude`, with `workflow_repo_root` and `repo_root` both resolving to that root, so that working-tree file is the real `local-ai-reviewer.sh` fallback. Set `config_file` to a base-snapshot file without the key, and call the real `run_local_ai_reviewer_review`. Expect the Codex stand-in. Then point `config_file` at a snapshot with `claude` and expect the Claude stand-in. Then set an operator `AI_DEV_WORKFLOW_CONFIG_FILE` and expect it to take priority (spec-review note c). Add the `# covers:` line for `local-claude-review-command.sh`. | AC-6 at the composed call site. The `git show origin/<base>` snapshot construction (V8) is existing behavior; no test of it was found by a search of `tests/test-pr-review-loop*.sh` and `tests/lib/`, so the smoke runbook covers the full loop path. |
| `tests/test-pr-review-loop-no-verdict-yet.sh` | T-L2: with `LOCAL_AI_REVIEWER_BACKEND=claude` exported, `reviewer_wait_budget_resolve local-ai-reviewer` gives `1200 default none` on `spec/*` and `implementation-plan/*`, `2400 default large_diff` on a feature branch above the threshold, `1500 configured none` with a configured value on `implementation-plan/*`, `2400 configured large_diff` with the same configured value on that feature branch, and `40 override none` with an override on that feature branch, which is not lengthened. | AC-11 |
| `tests/test_runner_diagnostic_emitters.py` and `tests/test-runner-diagnostic-emitters.sh` | Add a D35-style test for the Claude companion: the secret in the stand-in's stderr is redacted, and the functional JSON is retained on stdout. Add `local-claude-review-command.sh` to the D67 bootstrap list. Add `claude` to the `:3243` backend loop. Add the `# covers:` line. | AC-22 |
| `tests/test-local-ai-reviewer.sh`, `tests/test-local-http-review-command.sh` | D7: pin `AI_DEV_WORKFLOW_CONFIG_FILE` to a neutral fixture at the default-resolution sites (V17). Keep every existing assertion unchanged, including `backend_alias_error_names_http`. | AC-2, AC-7, consumer hermeticity |

Optionally add a measured `# duration:` header to each new suite (V14).

**Smoke test runbook**: `docs/testing/workflow/1957-local-ai-reviewer-claude-backend.smoke-test.md`

**Regression suite**: no separate E2E regression suite exists for workflow
scripts. The shell suites above, selected in CI by `select-test-suites.sh`
(V14), are the regression coverage.

**AC coverage map**: AC-1 T-B1; AC-2 T-B2 plus the unchanged existing suites;
AC-3 T-B3; AC-4 T-B4; AC-5 T-B5 and T-R1 to T-R6; AC-6 T-L1 plus the smoke
runbook; AC-7 T-B14 plus the existing `:445`; AC-8 T-B15 plus the
documentation steps; AC-9 T-B6 to T-B8; AC-10 T-B9 plus the guide; AC-11 T-L2;
AC-12 T-C1; AC-13 T-C2, T-C3, and T-C21 (reserved-path refusal); AC-14 T-C4 and T-C5; AC-15 T-C7 and T-C22 (edits invisible to Git status); AC-16
T-C10 to T-C14 (invalid JSON includes the E18 truncated-container refusal in
T-C12) and T-B1; AC-17 T-C15, T-C16, and T-C20; AC-18 T-C6, T-C8, T-C9, and
T-B10 to T-B13; AC-19 T-C19; AC-20 T-C17; AC-21 is the guide (verified in the
smoke runbook); AC-22 is the diagnostic-emitter changes.

---

## Seed Data

Not applicable. There is no database. Test fixtures are generated inside each
suite's temporary directories (stand-in CLI, fixture repository, YAML files).

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`:
  in Configuration, cover the three backends, the shared default key with a
  YAML snippet, the BR-3 order, the base-branch source (BR-4), and the
  `LOCAL_CLAUDE_REVIEWER_*` settings. Add a "Claude backend" subsection
  covering the prerequisites (CLI installed and logged in;
  `LOCAL_CLAUDE_REVIEWER_BIN` when `claude` is not on `PATH`), the review copy
  and read-only isolation, the 900 s direct-run default, the explicit-command
  timeout caveat (AC-10), the recommendation to raise
  `review.wait_budgets.local-ai-reviewer` when strict checks share the budget,
  the independence caveat (BR-16), the always-appended operating note (D4.6),
  the stale-copy clean-up note (D5), and the migration note (BR-17, D8). In
  Failure Semantics, add an `invalid_backend` row naming both diagnostic keys,
  and a row for preset refusals (`malformed_output`). Any new snippet carries
  `<!-- workflow-shell-contract: bash-zsh -->`.
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md`:
  the local-ai-reviewer YAML comment (about `:103-110`) names `claude`, the
  shared default key, and the BR-3 order (AC-8).
- [ ] `.ai-dev-workflow.local.env.example` (public placeholder example, found
  by V16 at line 5): add `claude` to the accepted values documented for
  `LOCAL_AI_REVIEWER_BACKEND`, adding a comment if none lists them. Keep the
  example's assigned value unchanged, so the example does not opt anyone in
  (DN-7). Add no real value.
- [ ] `changelog.d/1957.added.local-ai-reviewer-claude-backend.md`: see
  Implementation Order step 8.
- `docs/project/`, `docs/best-practices/`, `AGENTS.md`, `REVIEW.md`, and
  Protocol 93: no change. Protocol 93's budget table already states the
  backend-independent 1200 s (V7), and no mirror names the backend (V16).

---

## Consumer and Sync Impact

- **Consumers that do not opt in**: no behavior change (BR-1). The shared read
  returns nothing (R1/R3), so Codex runs with 300 s. Their synced test suites
  stay green even if they later opt in (D7).
- **Consumers with a local Claude patch (MOME)**: sync overwrites the patched
  `local-ai-reviewer.sh` and the same-named `local-claude-review-command.sh`.
  The default returns to `codex` until they set the shared key (D8). Their
  MOME-only `local-cursor-review-command.sh` is untouched. This is the
  highest-risk path, and the D8 note plus the guide are its mitigation.
- **`.ai-dev-workflow.yaml`**: only template-owned comments change (V12, D9).
- **Mirrors**: none (V16).
- **Sync manifest**: only the D8 note. The new script is covered by the
  existing glob (V12).

---

## Reversal

Every change is additive and reversible. It writes no persisted state: no
database, no cache, no tracker field, and no file that outlives a run. The
only leftover a run can leave is a stale review copy after a KILL (D5), which
`git worktree prune` and deleting the `local-claude-review.*` directory
remove. Changes to the two published surfaces are undone as follows.

- **Shared default `review.local_ai_reviewer.backend` (D1, D2).** An opted-in
  consumer removes the key, or sets it to `codex`, in `.ai-dev-workflow.yaml`
  and merges that to the base branch. Later pull requests run Codex again
  (BR-4). A contributor who opted in through the environment unsets
  `LOCAL_AI_REVIEWER_BACKEND` or sets it to `codex`. Either change takes
  effect on the next run, with no clean-up.
- **Direct-run budget (D3).** The 900 s default applies only to direct runs
  of the bundled Claude preset without an explicit budget. To restore the
  previous 300 s on such a run, pass `--timeout 300` or set
  `LOCAL_AI_REVIEWER_TIMEOUT=300`. Switching the backend back to `codex` also
  restores 300 s. Loop budgets are not changed (D6), so they need no reversal.
- **Template revert of the scripts.** Reverting the implementation PR
  restores the earlier `local-ai-reviewer.sh` and resolver and removes the
  preset. The earlier scripts never read `review.local_ai_reviewer` (V3), and
  today's `validate_selected_yaml(raw, path, review_fields=True)` decodes a
  file that contains the block without error (V18). A consumer that keeps the key after
  such a revert therefore runs Codex with 300 s, and its other review
  settings still load. An environment selection of `claude` gets the
  existing `invalid_backend` diagnostic until it is unset. The reverting PR
  also removes the D8 migration note, or a later release supersedes it,
  because the note's step 2 tells consumers to set the key.

No step is irreversible.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| MOME sync silently reverts to Codex | High (certain without action) | Medium | D8 migration note, guide note, and changelog text |
| Claude CLI flag semantics change in a later version | Low | High (read-only isolation) | Flags verified on 2.1.318 (V15). The containment check (P6) fails closed on any write. The smoke runbook records the CLI version. |
| A strict pass is starved on documentation branches (the 1200 s loop budget is shared with a roughly 900 s pass) | Medium | Low (`strict_pass_failed` is non-blocking) | Guide recommendation (AC-21); the default is unchanged (spec Consumer Impact) |
| Model prose matches a probe pattern and is misclassified | Low | Low (still Reviewer failed or Needs rerun, never Clean) | Same exposure as the Codex preset (D4.8). Preset messages avoid the probe vocabulary (T-B11). |
| A stale worktree entry after a KILL confuses the developer | Low | Low | D5 plus the documented `git worktree prune` |
| A large repository makes the review copy slow | Medium | Low | The copy time and the two raw-byte manifest reads (D4.4) count against the budget, so the worst case is No verdict yet, never an unchecked Clean. A No verdict yet is retried once by the loop. Raise the configured budget if needed. |
| A consumer opts in and its old synced tests fail | Medium without D7 | Medium | D7 |
| The loop cannot snapshot the base-branch configuration and falls back to the working-tree file, so a PR could select its own backend | Low | Low | This is the existing #756 fallback (V8), unchanged and shared by every reviewer setting. The smoke runbook's step 7 checks the normal path. |

---

## Code Samples

Illustrative only; adapt during implementation.

```bash
# Illustrative — D2 step 4 inside resolve_local_ai_reviewer_command
backend="${LOCAL_AI_REVIEWER_BACKEND:-}"; backend_key=LOCAL_AI_REVIEWER_BACKEND
if [ -z "$backend" ]; then
  shared_status=0
  shared="$(local_ai_reviewer_shared_backend)" || shared_status=$?
  if [ "$shared_status" -eq 3 ]; then
    workflow_diagnostic "ERROR: configuration validation error; key=review.local_ai_reviewer.backend" >&2
    return 1
  fi
  [ -n "$shared" ] && { backend="$shared"; backend_key=review.local_ai_reviewer.backend; }
fi
backend="${backend:-codex}"
```

---

## Implementation Order

Commit after each completed step. Stop at implementation start to re-check the
Cross-Cutting Operational Assumption Check rows.

1. **Resolver subcommand (D1)** in `workflow-config-resolver.py`, plus T-R1 to
   T-R7 in the new `test-local-ai-reviewer-backend.sh` (resolver-only cases
   first). Run the new suite, `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`,
   and `bash scripts/development-workflow/tests/test-selected-private-yaml.sh`.
2. **Preset (D4, D5)**: `local-claude-review-command.sh` plus
   `test-local-claude-review-command.sh` (T-C1 to T-C22). Confirm that
   `shellcheck --severity=warning` and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   report nothing for the new file.
3. **Resolution and budget (D2, D3)** in `local-ai-reviewer.sh`, including the
   usage text. Add T-B1 to T-B15.
4. **Composed loop and regression tests**: T-L1 and T-L2, and the
   diagnostic-emitter changes (AC-22).
5. **Hermeticity (D7)** in `test-local-ai-reviewer.sh` and
   `test-local-http-review-command.sh`. As a hermeticity probe, run both with a
   temporary `AI_DEV_WORKFLOW_CONFIG_FILE` that sets `backend: claude`, and
   confirm the D7-pinned sites still pass. Then run them normally.
6. **Configuration comments (D9)** in `.ai-dev-workflow.yaml`. Run
   `bash scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`
   and `bash scripts/development-workflow/tests/test-selected-private-yaml.sh`
   to confirm that the live file still parses and the platform lists are
   unchanged.
7. **Documentation** per Documentation Updates, plus the D8 note in
   `sync-manifest.yaml`. Run
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
   and `bash scripts/development-workflow/tests/test-check-sync-manifest-coverage.sh`.
8. **Changelog fragment** `changelog.d/1957.added.local-ai-reviewer-claude-backend.md`,
   with this exact body:

   ```markdown
   - **Local AI reviewer Claude backend** (#1957): `local-ai-reviewer` gains a bundled `claude` backend that runs a read-only Claude Code CLI review of a throwaway copy of the pull request head (900 s default budget for direct runs), and a repository can choose its default backend with `review.local_ai_reviewer.backend`; the built-in default stays `codex`. Consumers that patched a Claude backend locally must set `review.local_ai_reviewer.backend: claude` after syncing (see the sync migration note).
   ```

9. **Smoke runbook and readiness evidence**: run the selected suites
   (`bash scripts/development-workflow/select-test-suites.sh --changed-files -`
   fed with `git diff --name-only origin/develop...HEAD`, then each listed
   suite). Run the smoke runbook against the implementation PR with the real
   CLI, and record the results in the PR. If the release that ships this
   uses a different version from D8, note on the release PR that the D8
   `version` and `applies_if_syncing_from_before` values must match it.

**Residual verification strategy**: this is not a sweep or pattern-completeness
change. Before `ready-for-human-review`, the implementation PR records:
(a) the list of selected suites and their pass results; (b) a re-run of V5,
V16, and V17, showing that no new consumer or mirror appeared after
`49e71117`, with each new match classified; and (c) the smoke runbook result
with the Claude CLI version.
