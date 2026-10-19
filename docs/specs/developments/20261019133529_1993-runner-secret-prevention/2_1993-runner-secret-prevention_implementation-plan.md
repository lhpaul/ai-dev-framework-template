# Private runner configuration isolation — Implementation Plan

**Issue**: #1993
**Spec**: [Approved spec](1_1993-runner-secret-prevention_specs.md), merged in #1999.
**Smoke test runbook**: [Synthetic security journeys](../../../testing/workflow/1993-runner-secret-prevention.smoke-test.md)

## Summary

Keep private-source selection checkout-local unless an existing explicit override
selects another source. Replace preflight's complete private-file staging with a
validated review-only projection. Put reusable output sanitization in the existing
resolver, expose a configuration-independent stdin command for Bash consumers,
and apply it at diagnostic/publication boundaries. Preserve functional machine
interfaces and deliberate credential transport; their values are not diagnostics.

**Estimated complexity**: M. Selection is small; source-error handling, review
projection, composed consumers, and output boundaries need coordinated regression
coverage. No database, UI, new service, or runtime dependency is required.

**Dependencies**: Approved spec only. Template-fit passes: the affected Python and
Bash helpers are framework tooling used independently of consumer application stacks.

## Verification Log

Repository evidence below was collected at
`77b728ccc2ca74472c575a508dd6268eada0285b`. Search scope is tracked source;
real private configuration was not opened. Test scaffolding lists below are
indicative coverage projections, not frozen enumerations or artifact counts.

| Search | Recorded result |
| --- | --- |
| `git grep -n -E 'resolve_local_config\(|resolve_local_review_config\(|workflow_local_review_override_root|workflow_local_config_file' -- scripts ':!scripts/development-workflow/tests/*' ':!*.md'` | Resolver consumers: `load_configs`, strict runner/GitHub review readers, review-overrides, model policy loading. Bash consumers: local config/list selectors and CodeRabbit CLI preflight. |
| `git grep -n -E 'review-effective|review-github-effective|review-overrides' -- scripts/development-workflow/reviewer-preflight.sh scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/resolve-reviewer-availability.sh scripts/development-workflow/local-ai-reviewer.sh` | Preflight resolves the local source before staging; availability invokes strict review resolution; the reviewer loop reaches the same policy through shared helpers. |
| `git grep -n -E 'main_clone_file|local_origin == "checkout"|origin == "checkout"' -- scripts/development-workflow/workflow-config-resolver.py` | Selection fallback and review-specific fallback branches exist; model loading also uses the common selector. |
| `git grep -n -E '(cp|copy|copied).*(local\.yaml|local\.env)' -- scripts/development-workflow ':!scripts/development-workflow/tests/*' ':!*.md'` | `reviewer-preflight.sh:988` stages the entire selected file. |
| `git grep -n -E 'redact_text|redact_github_remote_slug' -- scripts/development-workflow ':!scripts/development-workflow/tests/*' ':!*.md'` | Existing audit renderer and reviewer remote-slug redactors are narrower controls, not a complete configuration-diagnostic boundary. |
| `git grep -n 'unreadable_detail\|except ConfigError\|except ModelConfigError' -- scripts/development-workflow/workflow-config-resolver.py` | Strict readers and main CLI exception handlers render error details; these are required sanitization boundaries. |
| `git grep -l -E '(main.clone|linked.worktree).*(override|local)|(override|local).*(main.clone|linked.worktree)' -- docs/workflow .agents .codex .claude .cursor scripts/development-workflow/README.md` | Protocols 90/91 and provider-contingency guidance promise automatic inheritance and need correction. |
| `git ls-files '.ai-dev-workflow.local*example*' '*.pem' '*.key' '*credentials*'` | Public local YAML/env examples exist; no tracked key/PEM/credentials filename matched. Preserve the public examples. |
| `git grep -n -E 'local|\.env|pem|credential|secret|example' -- .gitignore` | Local YAML/env and env patterns already exist; add narrowly scoped private-file variants and retain explicit public-example exceptions. |
| `git grep -n -E 'main_clone|main.clone|linked_worktree' -- scripts/development-workflow/tests/test-workflow-config-resolver.sh scripts/development-workflow/tests/test-pr-review-loop.sh scripts/development-workflow/tests/test_workflow_dsh_model_routing.py scripts/development-workflow/tests/test-resolve-reviewer-availability.sh` | Existing fixtures assert automatic inheritance; update their expected behavior rather than retaining contradictory tests. |
| `git grep -n 'mode_scope: product_repo_injection\|path: scripts/development-workflow/workflow-config-resolver.py' -- sync-manifest.yaml` | The existing resolver is an injected runtime dependency. Keeping sanitization in that file avoids introducing a module absent from product checkouts. |
| `gh pr list --repo lhpaul/ai-dev-framework-template --state open --search 'config in:title' --json number,title,headRefName,baseRefName` and the same query with `'security in:title'` | Both bounded same-surface title searches returned empty. This is bounded context, not a claim that no other PR could touch a shared file. |
| `git grep -n 'def parse_review_yaml\|raw = path.read_text' -- scripts/development-workflow/workflow-config-resolver.py` | `parse_review_yaml(path, raw=...)` already supports an in-memory strict snapshot. |
| `git grep -n 'workflow_config_review_on_draft_runner\|workflow_config_review_on_draft_github\|workflow_config_review_on_ready_github\|workflow_config_review_platforms\|workflow_config_review_local_list_if_declared\|workflow_local_config_file' -- scripts/development-workflow ':!scripts/development-workflow/tests/*' ':!*.md'` | Direct Bash consumers include readiness labels, completion self-check, policy recommender, reviewer-loop aggregation/process substitutions, library check-name/configured predicates and phase aliases, and CodeRabbit CLI policy selection. Their failure outcomes are specified below. |
| `git grep -n 'RATE_LIMIT_POLICY\|rate_limit_policy_from_config' -- scripts/development-workflow/coderabbit-cli-reviewer.sh` | The selector suppresses local-source errors; the invalid-policy warning interpolates the rejected value. Both require composed corrections. |
| `git grep -n 'def review_runner_value\|def parse_review_yaml' -- scripts/development-workflow/workflow-config-resolver.py` | Modern runner declaration takes precedence over the legacy alias; YAML parsing alone does not validate reviewer-field shapes. |
| `git grep -n 'review-effective --repo-root\|review-github-effective --repo-root\|WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT' -- scripts/development-workflow/reviewer-preflight.sh scripts/development-workflow/workflow-config-resolver.py` | Staged readers select an inherited explicit root independently of `--repo-root`; a staged directory alone cannot pin them to a projection. |

The versioned `.claude/settings.json` has an allow policy and no deny list at this
revision; inspect only its versioned permission policy when editing that control.
The direct reproduction is `git show 77b728cc:.claude/settings.json` followed by
JSON inspection of `permissions` only. No machine-local settings are involved.

## Cross-Cutting Operational Assumption Check

| Surface | Recorded value/source | Verified at | Bounded scope | Result |
| --- | --- | --- | --- | --- |
| Artifact owner and approved base | This repository, `develop`; shared workflow config and Luis's invocation | 2026-10-19, verification revision above | Invocation item #1993; spec #1999 merged into this base; nested-artifact guard reports no pending same-item plan | Verified |
| Private configuration authority | Protocol scripts may read selected private settings; agent/manual inspection and disclosure prohibited | Luis's latest explicit decision, 2026-10-19 | #1993 only; no modification of real local settings or checkpoint policy | Verified |
| Scope of preflight staging | Minimum reviewer settings required | Approved spec BR-4 / AC-6 at verification revision | Same source-selection/preflight chain; bounded open-PR evidence is recorded in the Verification Log | Verified |

Implementation must re-check these source facts before its first file edit and
record `Still valid`, or stop with `Stale or conflicting` evidence for this item.
The check does not scan the portfolio or run `/run-work`.

## Design Contracts and Layer Changes

### Source selection and composed consumers — AC-1 through AC-3

Change `workflow-config-resolver.py`'s `resolve_local_config` to return the existing
tuple shape, with compatibility main-clone metadata empty, without discovering
another checkout. Precedence: explicit `WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT`, then
the current checkout's local file, then the existing missing-local result. An
explicit root must be a readable directory containing a readable regular local
file; failure does not fall back. Resolve physical paths before accepting an
implicit local file; a symlink escaping the checkout requires explicit selection.
Do not echo an invalid override's raw value.

Remove review-only rediscovery from the strict runner reader, strict GitHub reader,
and `resolve_local_review_config`. Keep declared empty review/list semantics and
strict validation. Mirror source validation in `workflow_local_review_override_root`
in `workflow-lib.sh`; a missing review section no longer selects another checkout.
Delete private-discovery helpers only after the recorded consumer query confirms
they have no remaining functional caller; keep unrelated Git worktree utilities.

| Composed consumer / path | Expected observation after the change |
| --- | --- |
| `load_configs` → mode/repository/auth readers | Selected checkout or explicit source only; ordinary main-checkout configuration continues to work. |
| Strict review readers → reviewer availability | Checkout-local/explicit review settings with existing empty-list semantics; no primary-checkout policy substitution. |
| Review-overrides → preflight and reviewer-loop initiating-root handoff | Selected file identity only, empty main-clone metadata; the exported root is an explicit handoff, never discovered from Git ancestry. |
| `load_model_policy` → validate/model-route/model-routes | Same source isolation, preserving structured model error codes and envelope semantics. |
| Bash local-file selector → draft runner/GitHub and ready GitHub list readers | Only a valid source with no applicable local declaration permits shared settings; declared local empty lists keep disabling behavior. Invalid selected sources propagate as errors, including when the shared file is absent. |
| `coderabbit-cli-reviewer.sh` local-file preflight | The shared selector yields only the current or explicit file; source failure stops policy resolution instead of selecting shared settings. Existing remote identity validation is retained. |
| `set_local_product_repo_path` | Validate its implicit local source against the same physical checkout boundary before reading a snapshot; continue writing only the current checkout's file, without changing write ownership. |

#### Bash failure propagation through ordered consumers

Give `workflow_config_review_local_list_if_declared` distinct outcomes: `0` for
an applicable declaration (including an empty list), `1` for no declaration, and
`2` for source/read/validation failure. Guard selector assignments explicitly and
retain their failure status; never depend on `set -e` inside `if`, command
substitution, or a function invoked conditionally. Only outcome `1` permits the
shared-policy branch. The public list readers return `0` for a valid list or
valid absence and `2` for failure. Validate an applicable local/explicit source
before a missing-shared-file return or other empty-success shortcut, including
temporary shared snapshots with local overrides enabled. No declaration and a
failed source must remain distinguishable through each layer.

| Ordered Bash path | Required failure outcome / implementation discharge |
| --- | --- |
| `workflow_local_config_file` → local declaration helper → each draft/ready reader | Guard assignments, inspect the three-way result, and stop on `2` before shared/legacy fallback. Valid absence alone permits fallback. |
| `workflow_config_review_platforms` draft → ready aggregation | Guard each read independently; a later successful bucket must not mask an earlier failure or expose a partial effective list. |
| `workflow_config_review_phase_after_clean_platforms` | Remove the missing-shared early return ahead of source validation; preserve the ready reader's failure. |
| `workflow_config_review_github_reviewer_configured` | Keep `1` for valid not-configured and `2` for resolution failure; propagate `2` through its predicate callers instead of treating it as absence. |
| `configured_reviewer_check_names_json` → check/CI consumers in `workflow-lib.sh` | Capture and validate platform resolution before iteration or empty-JSON success; update its callers to propagate failure. Missing shared config must not bypass explicit-source validation. |
| `apply-readiness-labels.sh` configured-ready and PR/base snapshot helpers | Retain failure through both local and temporary-config paths and cleanup; refuse/escalate readiness before label mutation, never infer an empty reviewer set. |
| `item-completion-self-check.sh` configured platforms and downstream thread evidence | Capture resolution before iteration; report unavailable/failed evidence rather than a clean empty platform set. |
| `run-epic-policy-recommender.sh` runner count | Preserve its existing read-failure branch and reach it for invalid explicit roots even without shared config; do not recommend from a zero-count substitute. |
| `pr-review-loop.sh` lifecycle duplicate collection, configured-platform helpers, repository-platform initialization and phase-after-clean loading | Guard every bucket and replace error-hiding process substitutions with checked capture before iteration. Validate before missing-file shortcuts; stop the loop on source failure rather than warn-and-continue, return success, or infer no reviewers. |
| `coderabbit-cli-reviewer.sh` source → policy reader → startup assignment | Remove source-error suppression; propagate failure through the policy function and startup even in conditional contexts. Do not reinterpret failure as an empty value or apply shared/default policy. |

Implementation must follow the recorded query through these helpers' callers and
account for their composed return statuses in residual evidence. Integration tests
must reach each affected public consumer with an explicitly invalid synthetic root
both **with and without** shared config, and assert failure before reviewer,
readiness-label or merge-related mutation. Include conditional invocation and
aggregation where an earlier failure precedes a successful bucket. Separately
prove valid no-declaration fallback and explicit-empty disabling; these are not
error cases. Stub all services and use fabricated configuration only.

### Review-only snapshot — AC-6

Add a resolver subcommand `review-snapshot` accepting the real source checkout and
a destination directory owned by reviewer preflight. Resolve the source once,
read its bytes once into memory, and parse YAML using
`parse_review_yaml(path, raw=...)` against that same snapshot. Do not re-read the
source separately per review bucket. YAML syntax/type parsing and reviewer-field
schema validation are separate steps: after parsing, resolve modern-versus-legacy
precedence before selecting fields, then validate the selected list/item shapes
and unavailable-reviewer policy values against the effective reader contract.
A declared modern runner list, including `[]`, shadows `internal_reviewers`;
apply the existing equivalent GitHub-list precedence before choosing aliases.
Do not validate or serialize a shadowed legacy field. A syntactically valid but
schema-invalid opaque legacy scalar beside a valid modern declaration must neither
enter the projection nor reject it. Malformed YAML still fails before selection.

Serialize only the selected validated review fields to a private temporary file.
Include effective runner and draft/ready GitHub lists and unavailable-reviewer
policy only when declared; emit a legacy alias only when it supplies the effective
value and no modern declaration shadows it. Preserve explicit empty lists.
Never serialize unvalidated scalar values, unrelated review subtrees, product
paths, auth settings, or arbitrary unknown keys. Shared configuration still comes
from the preflight's selected Git revision, not the current worktree.

Replace the full-file `cp` in `reviewer-preflight.sh` with this projection. Restrict
temporary-file permissions, publish the projection atomically, and retain the
existing trap-based scratch cleanup. Do not copy or rewrite the real source.
Missing source means no local projection; invalid explicitly selected source or
invalid declared review settings fail with a safe category. Test that source
selection, origin reporting, and actual staged settings agree on the same snapshot.

#### Pin staged readers to the validated projection

For preflight, `review-snapshot` owns the original source selection and the single
private-file read, returning source identity/origin metadata separately from the
staged settings. Replace the independent raw-source `review-overrides` parse in
this staging path with that snapshot result; other runtime callers of
`review-overrides` retain their existing interface. Preserve original-source
metadata for attribution without using it to select the staged readers' input.

Invoke both staged `review-effective` and `review-github-effective` with
`--repo-root "$shared_dir"` and a command-scoped removal of
`WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT` (for example `env -u` inside the existing
bounded invocation). Apply the same environment boundary to any subsequent staged
reader. Do this even when no local projection was produced. The current resolver
must then select only the private, validated projection beside the staged shared
config; it cannot reselect the original external source. Do not globally unset
the operator's override or replace original-source attribution with the temporary
directory's origin. Preserve the original source in separate metadata fields and
keep staged-file identity distinct.

`test_staged_projection_pinning` must run the composed synthetic preflight with an
explicit external root, produce the projection, then mutate the external file
before staged reads. Change runner and draft/ready GitHub buckets to different
fabricated settings, then repeat with a malformed or removed source. Both staged
commands must still resolve every bucket from the original validated projection,
without rereading the external file; an access spy verifies the single source
read. Confirm original-source metadata remains correct and the caller's override
is unchanged. Include a no-projection control proving inherited override cannot
reintroduce local settings into staged reads. No real private file is involved.

### Safe diagnostics and output redaction — AC-4 and AC-5

Add a pure redaction function and a `redact-text` stdin command in the existing
resolver. That command must not load any workflow configuration. It masks the
complete sensitive value, not a prefix, and uses a stable `[REDACTED]` marker.
Its own failure emits a fixed safe failure message, never its input. Do not add
a generic parser dependency or a separate injected runtime module.

Supported structural classes are sensitive key assignments in plain, shell,
JSON, and YAML diagnostic text; authorization header values; URL user information;
recognizable access-token prefixes; and complete private-key blocks, including an
unterminated block through end of input. Keys include case-insensitive token,
password, passphrase, secret, API/access/private-key variants and common separators.
Do not rely on a vendor's surrounding prose, token length, or observed exact
message. Unknown ordinary text remains text; this is a bounded redactor, not a
claim to recognize every possible opaque secret.

Configuration errors have a stronger rule than generic text: construct diagnostics
from source identity, safe category, field identifier and line/column as available;
never embed raw parser excerpts, rejected scalar contents, exception chains, or
invalid override values. Apply that rule to strict reader `unreadable_detail`, CLI
`ConfigError`/Unicode failures, and model-policy diagnostics while preserving their
stable machine codes, exit statuses and shape. An arbitrary unrecognized value in
a malformed private file must remain absent even if it matches no redaction pattern.

Apply the same metadata-only rule to `coderabbit-cli-reviewer.sh`'s invalid
`review.coderabbit_cli.rate_limit_policy` / `CODERABBIT_CLI_RATE_LIMIT_POLICY`
warning: identify the field, safe invalid-value category and default action,
without interpolating the rejected scalar. Preserve the existing warn default for
a successfully read but invalid policy; source failure follows the propagation
contract above and cannot become a warn/default success. Test the actual CLI
startup diagnostic with an opaque fabricated value lacking a recognizable secret
prefix, from both the selected synthetic file and environment, with services stubbed.

Expose `workflow_redact_text` from `workflow-lib.sh`. Use it at the human-facing
error/report boundaries in `reviewer-preflight.sh`,
`resolve-reviewer-availability.sh`, `pr-review-loop.sh`, and
`local-ai-reviewer.sh`, including captured stderr and command-failure reports.
Apply the same pure sanitizer to persistent reviewer diagnostic fields before
publication; retain machine-parsed reviewer verdicts and counts. Replace the audit
trail's narrow `redact_text` implementation with the shared sanitizer while keeping
its existing local-path masking and stable comment markers. Internal functional
configuration payloads and deliberate auth-command token transport are not logged
or fed through a diagnostic formatter.

Each changed boundary must have a synthetic end-to-end test reaching the composed
caller, on both successful and failing paths where that caller emits diagnostics.
The test records the original command status before filtering; filtering must not
turn a failure into success or a successful machine result into invalid JSON.

### Prevention and documentation — AC-7 and AC-9

Add narrowly scoped Git exclusions for private local workflow variants, private
keys, and conventional credential files, with exceptions for the public local
examples named in the verification log. Do not broadly ignore all certificates
or consumer configuration. Add versioned Claude Read/Edit denies for those
private surfaces while preserving its existing allow policy. Do not invoke Claude
to test them in this Codex-only run or claim universal permission enforcement.

Add portable agent prevention guidance under `AGENTS.md`: private files are not
agent inspection targets; protocol-script access is deliberate; synthetic fixtures
are used for proof. This is a local security instruction, not a new workflow
checklist category. No review/planning gate or model policy changes are introduced.

Documentation targets for implementation:

- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/provider-contingency-runner-failover.md`
- `docs/workflow/development-workflow/integrations/runner-secret-prevention.md` (new upgrade and prevention guide)
- `scripts/development-workflow/README.md`
- `AGENTS.md`

Update only the inherited-local-source claims in the existing guidance. Preserve
explicit source handoffs and all current merge/session/checkpoint requirements.
The upgrade note must explain the break from implicit inheritance, how to select
a source explicitly, the absence of automatic copying, and use of a minimal local
review configuration. It must warn against restoring fallback during downstream
sync. Do not edit consumer repositories. Add
`changelog.d/1993.security.runner-secret-prevention.md` with the repository's
`- **Title** (#1993): ...` release-note format.

### Reversal policy for the changed public contract

Reversal to implicit cross-checkout private inheritance or to Bash status handling
that conflates source failure with absence is **not supported**. No compatibility
flag, automatic downgrade, or rollback procedure will restore either behavior.
The consumer upgrade guide must state this policy for both source selection and
the public Bash statuses together; do not recommend reverting only a selector,
reader, or caller. This is a supported-operation policy, not a claim that Git
history is physically irreversible.

If rollout exposes a regression, stop the affected operation and correct it in a
reviewed forward fix preserving checkout isolation, explicit-source validation,
and the distinct failure status throughout callers. Operators can use a valid
explicit source or intentional checkout-local settings under the new contract.
Do not copy private values or recover by restoring silent inheritance. Existing
review, risk, CI and merge-session gates also apply to that forward fix.

## Testing Strategy

**Types**: Python unit tests, synthetic Bash/CLI integration, Git ignore-engine
proofs, existing affected harnesses, and the linked smoke runbook.

Add `scripts/development-workflow/tests/test_runner_secret_prevention.py` for the
new behavior and invoke it from the existing resolver test harness so current CI
selection includes it. Update affected expectations in
`test-workflow-config-resolver.sh`, `test-pr-review-loop.sh`,
`test-resolve-reviewer-availability.sh`, `test-reviewer-preflight.sh`,
`test_workflow_dsh_model_routing.py`, and audit/local-reviewer harnesses when their
actual composed behavior changes. Retain their unrelated cases. These are coverage
classes, not a binding test-case enumeration.

Fixtures must use temporary repositories, fake settings and credentials, and
explicit synthetic roots. Local tests must not fall through to this checkout's
private settings, source its real env, use real credentials, or launch a real
review CLI. Use AST-isolated selector proofs where needed; import the resolver
only when the test proves imports do not read configuration. Full affected legacy
harnesses run locally only with fixture isolation established; otherwise use clean
ephemeral CI, whose setup has no workstation configuration.

### Parser-risk edge cases and unit mapping

Parser-risk applies to the redactor and review projection. In the new Python
test file, map each row to a named test method and reach the relevant CLI/Bash
consumer in addition to pure-function coverage.

| Input class | Coverage intent / unit method |
| --- | --- |
| Case/separator variants, whitespace, quoted/unquoted sensitive values, escaped quotes/backslashes inside quotes | `test_sensitive_assignments` covers JSON/YAML/shell text and complete value removal through the closing delimiter; an escaped quote must not leave a value suffix visible. |
| Multiple sensitive assignments or authorization values on one line | `test_multiple_values` proves every value is removed. |
| Bearer/Basic header values and credentials in URL user information | `test_header_and_url_values` preserves safe operation context. |
| Recognizable token prefixes at punctuation/string boundaries | `test_token_boundaries` covers adjacent text and end-of-input. |
| Multiline, nested-looking, or unterminated private-key blocks | `test_private_key_blocks` removes the full block without leaking continuation lines. |
| Harmless words such as token count, public key names, and ordinary URLs | `test_negative_lookalikes` prevents indiscriminate destruction of useful output. |
| Malformed config with a synthetic opaque value lacking a recognized prefix | `test_config_error_metadata_only` proves no parser excerpt or scalar is rendered; `test_coderabbit_policy_metadata_only` reaches CLI startup for file/env opaque values and preserves safe default behavior. |
| Empty/non-review local mapping; modern and legacy review lists; shadowed opaque malformed legacy scalar | `test_review_projection_semantics` validates the allowlist, precedence before selection, omitted shadowed alias, and valid plus explicit-empty modern declarations. |
| External source changes after projection; inherited override present during staged reads; no local projection | `test_staged_projection_pinning` exercises both staged commands, all buckets, separate original-source metadata, source access count and unchanged caller environment. |
| Unknown nested review values, duplicate keys, invalid selected scalar/list/item/policy shapes | `test_invalid_review_projection` distinguishes YAML parse errors from selected-field schema errors and proves safe failure before staging. |
| Missing, unreadable, relative, symlinked, or explicitly selected external sources | `test_source_isolation` exercises Python/Bash parity and all source branches. |
| Invalid explicit roots with shared config present/absent; valid no-declaration and explicit-empty controls | `test_bash_source_failure_propagation` reaches the ordered consumers above, conditional contexts and aggregation, and proves fatal source errors cannot select shared/default policy or trigger mutations. |
| Source removed during staging; redactor error; caller nonzero exit | `test_failure_boundaries` proves no fallback, unsafe echo, partial snapshot, or masked command failure. |

No inline suppression directives are introduced. No new concurrent event sources
are introduced; atomic temporary-file publication and existing cleanup govern the
snapshot handoff. Test scaffold volume is proportionate to changed security
boundaries; do not build a new documentation scanner or generic test framework.

### Planted violations and residual verification

Plant an implicit primary-checkout selection in an isolated copy/AST of the selector
and show the regression test fails; restore the selector and show it passes.
Separately bypass redaction for a synthetic sensitive fixture and prove its absence
assertion fails, then passes with the filter restored. Disable a private-file ignore
rule in a temporary Git repository and show the ignore proof fails, then passes
after restoration. Record concrete fixture file/line and command results in the
implementation PR. Never plant a value in real local configuration.

Before implementation readiness, re-run the consumer searches from the Verification
Log across tracked runtime code and normative guidance. Residual evidence must
classify every remaining primary-checkout/private-config reference as removed,
historical test evidence, an explicitly selected handoff, or unrelated Git worktree
maintenance. Run the scope residual gate with this evidence; unresolved implicit
selection or unsanitized planned diagnostic boundaries blocks readiness.

## Factual Claim Evidence

**Rule 1 — external text sampling**: The redactor's ordinary-text preservation
boundary was checked against actual current PR #1999 workflow output, observed on
2026-10-19 between 16:37 and 16:59 UTC. These are workflow events, not invented
format examples: PR-Agent's review (comment `6272188731`) contains
`<strong>No security concerns identified</strong>`; its persistence notification
(`6272369624`) starts `**[Persistent review]`; the actual native Codex gate summary
(`6272196002`) contains `**Verdict**: APPROVED`. Retrieve each with
`gh api repos/lhpaul/ai-dev-framework-template/issues/comments/COMMENT_ID`.
The embedded excerpts preserve the relevant HTML, Markdown-link and plain verdict
shapes even if the remote comments change. Three occurrences yielded these three
ordinary-text variants; saturation is not claimed. This sample supports retention
of ordinary diagnostic structure, not a fixed external vocabulary or a universal
secret-detection claim. Sensitive positive classes are defined by the approved
security contract and tested with fabricated data only. The design addresses that
heterogeneity through structural matching, metadata-only config errors, and the
explicit unknown-input limit in the output contract; no real secret sample is
collected or needed. Do not match on these observations' literal review wording.

**Rules 3/4/5**: The Verification Log provides reproducible source searches;
the composed-consumer table is the required outcome enumeration. No claim of a
repository artifact quantity is used to decide scope. The implementation file
list is a projection of planned edits, not a count of existing artifacts.

**Rule 6 — scoped obligations**: Implicit and explicit input classes are discharged
at source selection and `test_source_isolation`; reviewer handoffs are discharged
at snapshot projection and its semantic/failure tests; config failures are
discharged before resolver diagnostics; generic diagnostics are discharged at the
named human/publication boundaries; upgrade completeness is discharged by the
residual verification and consumer note. These scopes also govern the conditional
requirements in their corresponding design sections.

## Implementation Order

1. Revalidate the recorded operational assumptions and spec merge, then build
   synthetic fixtures. Implement source isolation and composed-consumer coverage;
   commit this coherent verified sub-part.
2. Implement review-only projection and replace whole-file preflight staging.
   Verify precedence, minimal staging and failure behavior; commit that sub-part.
3. Implement safe config diagnostics, pure redaction and named publication/error
   boundaries with the mapped regression and planted-violation proofs; commit the
   complete verified behavior.
4. Add prevention controls, correct the documented fallback claims, write the
   consumer upgrade guide and changelog fragment, and complete residual evidence.
   Commit the coherent controls/documentation sub-part.
5. Run relevant synthetic and affected isolated harnesses, Python/Bash syntax,
   ShellCheck, workflow shell guard and snippet lint, Markdown checks and sync
   coverage. Open the implementation PR only after self-review against the spec
   and plan. Use normal internal and automated review, regression and CI gates.

The existing policy classifier may assign implementation files medium risk.
Do not change the classifier or route around that outcome: under Luis's low-only
authority, leave the implementation PR ready and report the classified blocker.
