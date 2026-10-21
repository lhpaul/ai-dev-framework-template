# Private runner configuration: upgrade and prevention

Upgrading removes automatic inheritance of private workflow settings from the
primary checkout into linked worktrees. Implicit selection uses only the current
checkout's `.ai-dev-workflow.local.yaml`. Missing, empty and product-only local
files never trigger discovery in another checkout. An implicit symlink that
escapes the checkout fails and requires explicit external selection.

Select an authorized external source deliberately when that is the intended
policy source. The source must be a readable directory containing a readable
regular `.ai-dev-workflow.local.yaml`; relative roots resolve from the process's
working directory. Missing, unreadable or malformed selected sources stop the
operation without substituting shared or default settings. Do not print private
configuration values while diagnosing the safe error category and numeric locators.

Selected private sources are validated in full by the framework's strict,
dependency-free YAML subset parser before any legacy field is extracted, including
context/auth commands and Bash policy readers. Malformed unrelated or trailing
sections cannot become absent fields and activate shared/default policy. Missing,
empty and shared-only legacy paths also require no PyYAML. Syntax checking remains
separate from field/schema validation and does not expand the supported YAML
features. Modern strict `review-effective`, `review-github-effective`, selected
source validation and review projection share one dependency-free strict reader.
Review-specific schema and scalar conversion remain separate from syntax. Provider
configuration readers, such as CodeRabbit's, retain their own dependencies.

CI-policy enrichment also stays in the selected checkout. It no longer scans
sibling directories or follows an inherited `WORKFLOW_HUB_REPO_ROOT` to read a
hub's configuration. Product checkouts should declare `product_repo.ci_policy`
in their versioned manifest. To resolve a hub's product policy deliberately,
invoke the helper with that hub as `--repo-root` and select the product using
`--product-repo`; a shared hub reference or inherited locator alone does not
authorize its private source. This applies to the final context lookup as well
as mode and product-list probes.

For commands accepting `--repo-root`, private-source validation and later Bash
reviewer policy reads use that parsed entry root. A missing private file there
stays absent even when the tooling checkout has one. Changing directory, reading
a temporary shared policy or spawning a child reviewer does not grant permission
to read another checkout's private file. The Bash library keeps this entry
binding in process memory, preserves it when re-sourced, and discards a
same-name inherited environment scalar. Existing explicit shared-file overrides
still supply shared policy; they do not select adjacent private configuration.
Relative roots are resolved against the invocation directory before changing
directory or forwarding them to a child, including batch wrappers. An explicit
relative `WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT` is likewise anchored to the
invocation directory before any directory change or child handoff. Importing
the Bash library only anchors path metadata; it does not read private content.
Entry validation then preserves the validated physical source directory. Cleanup's
source selection uses the actual calling worktree independently of inherited
operation reentry flags or Git location overrides; cleanup protections and merge
session requirements still apply.

<!-- workflow-shell-contract: bash-zsh -->
```bash
export WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=/path/to/authorized-checkout
python3 scripts/development-workflow/workflow-config-resolver.py review-overrides --repo-root "$(pwd -P)" \
  | grep -E '^(LOCAL_OVERRIDE_FILE|LOCAL_OVERRIDE_ORIGIN|MAIN_CLONE_LOCAL_OVERRIDE_FILE)='
```

Alternatively, an operator can maintain intentional checkout-local settings.
Use a minimal local review configuration, containing only the declarations
needed for review, for example:

```yaml
review:
  on_draft:
    runner: [codex]
    github: []
  on_ready:
    github: [pr-agent]
  internal_reviewers_unavailable_policy: warn
```

Do not copy an existing private file into a worktree or a synthetic fixture.
There is no automatic copying or migration of private values. Explicit empty
local lists retain their disabling meaning. Modern declarations shadow legacy
aliases before projection validation; unrelated settings never enter the review
snapshot. Preflight reads the selected source once and publishes a private 0600
review-only projection atomically. Both staged readers remove inherited source
overrides and use that projection even if the original file changes or vanishes.
Original source metadata remains separate from temporary-file identity.

The public Bash source contract also changes. The local declaration helper
returns 0 for a declaration, including an empty list; 1 for valid absence; and 2
for source/read/schema failure. Public list readers return 0 for a valid list or
valid absence and 2 for failure. Configured predicates retain 1 for valid
not-configured and 2 for failure. Only valid absence permits shared-policy
fallback; conditional calls, process substitutions and bucket aggregation must
not erase status 2. Stop before reviewer or readiness mutations when it occurs.

Reversal to implicit cross-checkout inheritance or conflated public Bash
failure/absence statuses is **not supported**. No compatibility flag, automatic
downgrade or rollback procedure restores either contract. If an upgrade exposes a
regression, stop the affected operation and use a reviewed forward fix preserving
checkout isolation, explicit-source validation and distinct failure status through
all callers. Operators may use a valid explicit source or intentional checkout-local
settings. Existing review, CI, risk and merge-session gates apply to the fix.
Do not restore fallback during downstream template sync, revert only one layer,
or recover by copying private values. Sync preserves project-owned ignore rules;
adopt the template's narrow private-file exclusions deliberately where needed.

Runner-owned diagnostics redact supported sensitive assignments, authorization
values, credential URLs, recognizable tokens and private-key blocks using
`[REDACTED]`. Config errors are metadata-only even for opaque unknown values.
Unknown ordinary text remains text: this is a bounded sanitizer, not a universal
secret detector or a control over arbitrary external terminal sessions.

Private workflow variants, conventional credentials and private-key filenames are
excluded by Git; public local examples, `.pub` keys and public certificate files
remain trackable. Versioned Claude Read/Edit denies cover named private surfaces
while preserving the allow policy. Those runtime-specific rules do not claim
universal enforcement. Agents must not inspect private files manually; authorized
protocol scripts retain deliberate selected-source access. Verify controls with
fabricated values in disposable repositories, without launching a real review
service or copying workstation configuration.

Configuration parse and validation errors expose only the error type, line, column, and known schema key. Unknown keys, source excerpts, exception text, and source paths are excluded. Error payloads retain their schema with an empty `FILE` or `unreadable_file`; successful functional `SOURCE_FILE` and projection provenance remain available. Selected private-source validation and modern review parsing use the same strict framework reader without PyYAML; review-specific schema and conversion restrictions remain separate. Provider-specific configuration readers retain their own dependencies.

A review-state payload keeps functional source bindings such as `local_override_file` and `effective_*_source`, including an unreadable selected source, so callers preserve source authority and never substitute shared policy. These bindings are separate from metadata-only error fields and must not be copied into diagnostic error reports.
