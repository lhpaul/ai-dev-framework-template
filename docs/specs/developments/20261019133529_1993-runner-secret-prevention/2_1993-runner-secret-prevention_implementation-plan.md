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
| Bash local-file selector → draft runner/GitHub and ready GitHub list readers | Shared settings receive the input formerly consumed by the fallback when no local declaration exists. Declared local empty lists keep disabling behavior. |
| `coderabbit-cli-reviewer.sh` local-file preflight | The shared selector yields only the current or explicit file. Existing remote identity validation is retained. |
| `set_local_product_repo_path` | Validate its implicit local source against the same physical checkout boundary before reading a snapshot; continue writing only the current checkout's file, without changing write ownership. |

### Review-only snapshot — AC-6

Add a resolver subcommand `review-snapshot` accepting the real source checkout and
a destination directory owned by reviewer preflight. Resolve the source once,
read its bytes once into memory, and validate the supported reviewer fields using
`parse_review_yaml(path, raw=...)` against that same snapshot. Do not re-read the
source separately per review bucket.
Serialize an allowlisted review projection to a private temporary file. Include
the runner list/legacy alias, draft/ready GitHub reviewer lists, and unavailable
reviewer policy only when declared; preserve explicit empty lists and precedence.
Never serialize unvalidated scalar values, unrelated review subtrees, product
paths, auth settings, or arbitrary unknown keys. Shared configuration still comes
from the preflight's selected Git revision, not the current worktree.

Replace the full-file `cp` in `reviewer-preflight.sh` with this projection. Restrict
temporary-file permissions, publish the projection atomically, and retain the
existing trap-based scratch cleanup. Do not copy or rewrite the real source.
Missing source means no local projection; invalid explicitly selected source or
invalid declared review settings fail with a safe category. Test that source
selection, origin reporting, and actual staged settings agree on the same snapshot.

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
| Case/separator variants, whitespace, quoted/unquoted sensitive values | `test_sensitive_assignments` covers JSON/YAML/shell text and complete value removal. |
| Multiple sensitive assignments or authorization values on one line | `test_multiple_values` proves every value is removed. |
| Bearer/Basic header values and credentials in URL user information | `test_header_and_url_values` preserves safe operation context. |
| Recognizable token prefixes at punctuation/string boundaries | `test_token_boundaries` covers adjacent text and end-of-input. |
| Multiline, nested-looking, or unterminated private-key blocks | `test_private_key_blocks` removes the full block without leaking continuation lines. |
| Harmless words such as token count, public key names, and ordinary URLs | `test_negative_lookalikes` prevents indiscriminate destruction of useful output. |
| Malformed config with a synthetic opaque value lacking a recognized prefix | `test_config_error_metadata_only` proves no parser excerpt or scalar is rendered. |
| Empty/non-review local mapping; modern and legacy review lists | `test_review_projection_semantics` validates the allowlist and empty disabling behavior. |
| Unknown nested review values, duplicate keys, invalid scalar/list types | `test_invalid_review_projection` proves safe failure before staging. |
| Missing, unreadable, relative, symlinked, or explicitly selected external sources | `test_source_isolation` exercises Python/Bash parity and all source branches. |
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
