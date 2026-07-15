# Review Contract

`REVIEW.md` is the authoritative review contract for this repository.

Use it for every pre-PR review gate and as the normalization layer for PR review tools.

- Claude Code: use the native review flow against this file.
- Codex: use the native review flow against this file.
- Cursor: use the repo review commands, which perform a manual/self-review against this file.
- Automated PR reviewers: use them after the PR is opened and pushed. They validate the PR branch; they do not replace the pre-PR review gate.

---

## Core Rules

### Severity

| Severity     | Meaning                                                                                                                 | Default action                                                           |
| ------------ | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `blocking`   | Incorrect behavior, spec/plan deviation, broken workflow contract, security issue, missing critical validation or tests | Fix before PR is ready                                                   |
| `important`  | Edge-case gap, maintainability issue, unclear design choice, incomplete workflow update                                 | Fix by default unless a human decision is required                       |
| `suggestion` | Improvement that is optional and low-risk                                                                               | Fix by default; report if scope-expanding or requires a product decision |

### Haystack mirror findings

When a review references mirrored agent docs, compare the live repository surface map before treating the finding as blocking. A `Rules violation` that only points at tool-specific front matter differences or an absent `.cursor/skills` tree is advisory only; a real mismatch between mirrored workflow bodies is actionable.

### Fix vs. Report

Fix directly when:

- The correct change is clear and low-risk
- The issue is `blocking`, `important`, or `suggestion`
- The change is mechanical: links, wording, formatting, naming, checklist completion, or deterministic script/doc updates

Report instead of fixing when:

- A product, design, or architecture decision is required
- Multiple valid fixes exist and the tradeoff is material
- The request would expand scope beyond the approved work

### PR Readiness

A PR is ready for human review only when all of the following are true:

- The relevant `REVIEW.md` checklist is satisfied
- The branch reflects any required direct fixes from the review gate
- CI is green
- Every configured automated PR reviewer is `clean` or `skipped`
- No unresolved human-requested changes remain

If any blocking finding remains, the PR must stay out of `ready-for-human-review`.

---

## Spec Review Checklist

Read before reviewing:

- `docs/project/1-business-domain.md`
- `docs/project/3-software-architecture.md`
- The target spec

Check:

- Required spec template sections are present and no placeholders are unintentionally left behind
- Spec PRs include a current `Document Quality Gate` log in the PR description; a missing, obviously incomplete, stale, or contradictory log is an important finding by default and blocking when it claims unchecked coverage
- Use cases are explicit: actor, trigger, steps, outcome
- Acceptance criteria are specific and testable
- When a tracker issue is linked, brief objectives are fully covered via a visible matrix: each objective maps to AC(s) or explicit out-of-scope deferral with rationale
- Business rules are unambiguous and non-contradictory
- Scope boundaries and out-of-scope items are explicit
- Status or enum changes include display labels and transitions
- If the spec introduces URL-serialized state (query parameters, path parameters, hash fragments), the parameter keys and all allowed values are explicitly defined — a spec that leaves parameter names or value formats unspecified forces implementers to guess the serialization contract
- The spec stays product-focused and does not over-prescribe technical design
- Terms align with the project domain and existing business rules

Typical `blocking` issues:

- Missing or ambiguous acceptance criteria
- Contradictory business rules
- Spec drift that would force engineering to guess
- URL-serialized state introduced without explicit parameter key names and allowed values
- `CHANGELOG.md` is modified in this PR — `spec/*` branches are exempt from CHANGELOG entries; remove any CHANGELOG modification before merging

Typical `important` issues:

- Missing edge cases
- Unclear actor/trigger language
- Technical implementation detail leaking into product requirements

---

## Plan Review Checklist

Read before reviewing:

- The corresponding spec (Full Pipeline only — Refactor items have no spec; use the work item brief instead)
- The implementation plan
- Relevant code and architecture docs
- The smoke test runbook when one exists

Check:

- Every use case and acceptance criterion from the spec (or from the work item brief for Refactor items) is addressed
- Plan PRs include a current `Document Quality Gate` log in the PR description; a missing, obviously incomplete, stale, or contradictory log is an important finding by default and blocking when it claims unchecked coverage
- Steps are specific enough to execute without guessing
- Ordering is feasible and dependencies are explicit
- When pattern-based completeness applies, enumerated counts/paths are validated against the plan's Verification Log commands and outputs
- Parser-risk completeness (when protocol `02-generate-implementation-plan-protocol.md` Step 3 parser-risk signals apply):
  - Edge-case enumeration is present and concrete
  - A unit test file is named with at least one automated test mapped per enumerated case
  - When suppressions are part of the proposed feature, suppression semantics explicitly define:
    - Recognized directives
    - Allowed placement
    - Interpretation of multiple suppressions on one line
- Concurrent-event-source completeness (when protocol `02-generate-implementation-plan-protocol.md` Step 3 concurrent-event-source signals apply):
  - The plan includes a dedicated concurrency safety section
  - Each of the seven checklist items is addressed or noted as not applicable with a brief rationale: shared mutable state guards, re-entrancy / in-flight tracking, event deduplication, listener and resource cleanup, race conditions at initialization, race conditions at teardown, and error propagation across async boundaries
- Cross-cutting checklist completeness (when protocol `02-generate-implementation-plan-protocol.md` Step 3 cross-cutting checklist signals apply):
  - The plan's "Files to modify" section explicitly enumerates all applicable targets: the developer implementation protocol, all agent/skill guidance files for tech-lead and developer roles, `REVIEW.md`, and any Codex skill files that invoke the affected stage
  - The enumeration is not limited to the primary protocol file — no required target is missing
- Documentation updates are listed or intentionally declared unnecessary
- Seed data, generated artifacts, and follow-up tasks are called out when applicable
- The proposed approach matches existing architecture and repo patterns
- Testing and smoke-test coverage map back to acceptance criteria
- Technical accuracy (applies to all plans that reference framework/runtime behavior, guards, config, or helpers):
  - For each code sample, step-by-step instruction, or behavioral claim that references framework or runtime behavior (guards, middleware, config inheritance, scope, API contracts), identify the actual source file or authoritative reference that confirms the claim
  - Verify each such claim against the real source files — not just against other parts of the plan document
  - Flag any claim that cannot be verified from the codebase as "unverified — implementer must confirm before proceeding"
  - Cross-reference consistency: line numbers, counts, and symbolic references (e.g., smoke test counts, Verification Log output counts, log line references) must be consistent across the plan document; flag any number or reference that cannot be confirmed against the codebase or a prior plan step
- Behavioral guarantee mechanism citation: every behavioral guarantee stated in the plan (e.g., "at most once per run", "bounded", "idempotent") cites the specific mechanism that enforces it (flag, guard clause, constraint, lock, etc.); a guarantee without a cited enforcement mechanism is unverifiable and must be flagged
- Cross-section consistency: all references to the same function, constant, architecture decision, file path, directory name, or route/URL structure are consistent across all sections of the plan (e.g., a function described in the Architecture section must have the same signature in the Implementation Order steps; a constant must carry the same value everywhere it appears; a decision index must map to the same decision in every reference; a file path or route pattern defined in one section must match every other section where it appears)

Typical `blocking` issues:

- Plan steps do not cover required acceptance criteria
- The plan requires guessing at implementation details
- The plan introduces unsafe or contradictory architecture decisions
- A CHANGELOG literal in the Implementation Order uses conventional-commit format (`fix(scope): message`) instead of the project's `**Bold Title** (#N):` format
- `CHANGELOG.md` is modified in this PR — `implementation-plan/*` branches are exempt from CHANGELOG entries; remove any CHANGELOG modification before merging
- A behavioral claim about framework/runtime behavior (guard logic, config inheritance, scope, API contract) cannot be verified against the codebase and is not flagged as "unverified"
- A behavioral guarantee (e.g., "at most once", "bounded", "idempotent") does not cite the specific mechanism (flag, guard clause, constraint, lock) that enforces it
- Cross-section inconsistency: the same function, constant, architecture decision, file path, directory name, or route/URL structure is defined or described differently in two or more sections of the plan (e.g., incompatible function signatures, conflicting constant values, contradictory decision rationales, a file placed under different directories in different sections, a route pattern that differs between sections)

Typical `important` issues:

- Vague wording like "update as needed"
- Missing documentation/test updates
- Incomplete dependency or rollout notes
- Verification steps in Implementation Order steps use complex shell commands that are hard to verify by reading: flag any multi-flag grep one-liner with exclusion scopes or self-referencing globs, hardcoded file counts that go stale, or broad exclusion patterns that may silently under-count. Suggest replacing with a human-readable "run and confirm output" assertion instead.
- Numeric cross-references (line numbers, counts) in the plan that cannot be confirmed against source files or Verification Log output

---

## Code Review Checklist

For implementation PRs (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`), this checklist is divided into two sequential passes (Pass 1 then Pass 2). Spec and plan PRs use a single-pass review and are not affected by this split.

Read before reviewing:

- The corresponding spec (Full Pipeline only — Refactor items have no spec; use the work item brief instead)
- The implementation plan
- Relevant best-practice docs
- The changed code

### Pass 1: Spec Compliance

Check:

- Implementation matches the approved spec and plan (or the plan and work item brief for Refactor items), or any deviations are documented. All acceptance criteria addressed, no out-of-scope behaviour, no missing or extra behaviours.
- CHANGELOG and workflow-specific artifacts are updated when required (spec/plan-only PRs are exempt; fixes to unreleased work update existing entries rather than adding new ones; in parallel batches, each PR adds its own CHANGELOG entry as normal; merge conflicts are resolved by batch-merge auto-resolution per protocol 94 Step 4.3)
- For implementation PRs, flag stale debug comments, newly introduced `TODO`/`FIXME` markers, review-marker comments, sibling/caller inconsistencies, or uncovered spec/plan/issue-body requirements that should have been caught by the Protocol 03 Pre-Submission Self-Review Pass.

Typical `blocking` issues:

- Implementation diverges from the approved spec or plan in a way that changes observable behaviour
- Missing acceptance criteria coverage
- Stale markers, caller inconsistencies, or uncovered spec/plan/issue-body requirements remain in the PR after the pre-submission pass
- CHANGELOG entry absent when required, or present when exempt (spec/plan PRs)

### Pass 2: Code Quality

Check:

- Project and stack conventions are followed
- Logic and edge cases are correct
- Security boundaries and validation are respected
- Tests cover the changed business behavior
- New patterns are justified and consistent with the codebase

Additional checks for **documentation PRs** (when a PR adds or modifies documentation files — `*.md`, `*.yaml`, `*.toml` config docs, or any prose-only file):

- **Intra-file content duplication**: when a new section is added to an existing file, verify that any tables or lists in the new section are not reproducing content already present elsewhere in the same file. If a duplicate is found, flag it as `important` with a recommendation to cross-reference the canonical location instead of duplicating.
- **Wording consistency**: verify that procedural instructions in a new section (e.g., "push a commit", "apply a label", "run a script") are consistent with the existing flow described in sibling sections of the same file. Flag contradictions as `important`.
- **Shell snippet safety in protocol files**: when a PR adds or modifies shell code blocks (`` ```bash `` / `` ```sh `` fenced blocks) inside a protocol or documentation `.md` file, apply the same quality bar as for `.sh` files (see the "Shell Script Quality Checklist" in `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`). Specifically flag as `important` any multi-command state-mutating block that lacks `set -euo pipefail`, any block that commits or pushes without a wrong-branch guard, and any single-liner that can fail silently without an explicit `|| exit 1` or equivalent error guard. Read-only query snippets (e.g., `gh pr view`, `git log`) are exempt.
- **Residual evidence for sweep/batch work**: when an implementation PR can
  reach `ready-for-human-review` for sweep, batch, helper-extraction,
  numeric-target, or pattern-completeness work, verify that residual evidence is
  present and that remaining residuals are completed, explicitly out of scope, or
  linked to follow-up issues. Silent prose deferral is an important finding, and
  missing evidence that allows readiness is blocking.

Additional checks for **PRs that add or modify guardrails enforcement behavior** (orchestration protocols, agent files, skill files, or guardrails-related documentation):

- **Named-stop contract**: every stop message emitted by the changed code or documented behavior names (a) the exact stop condition string from `docs/workflow/development-workflow/guardrails-enforcement.md` section 4, (b) the affected work item, and (c) the concrete human action to unblock. Missing any of the three elements is a `blocking` finding.
- **Single run-epic policy path**: verify the changed code or documentation does not introduce a second policy model separate from the run-epic helpers (`run-epic-risk-classifier.sh`, `run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`). Adding a parallel enforcement path is a `blocking` finding.
- **Five enforcement gates present**: confirm the PR accounts for all six gates from `guardrails-enforcement.md` section 3 (load+report, backlog-start, PR-open, delegated review, delegated merge, and completion) and does not leave any gate unimplemented or bypassed.
- **Delegated merge/review/backlog-start/completion gates**: confirm the orchestration path (Protocol 90, 91, or 95) enforces each of these gates before the relevant decision point (opening a PR, making a review decision, merging, marking complete), not after.
- **Audit recording**: when `audit.pr_disposition_record` or `audit.work_item_ledger_record` is required, confirm the stable audit markers (`<!-- run-epic:pr-disposition -->` and `<!-- run-epic:epic-ledger -->`) are used so reruns update rather than duplicate records.
- **Conservative defaults declared**: the load+report step must state "conservative defaults in effect" when no `guardrails` section is present, and must enumerate each default value (mode=`manual`, `may_merge_pr: false`, `max_merge_risk: low`, backlog starts confirmation-gated, no audit requirements).

Additional checks for **PRs that add or modify branch creation, PR creation, or nested/stage-agent dispatch behavior**:

- **Nested artifact guard present**: confirm item-scoped branch and PR creation paths call `run-nested-artifact-guard.sh` with the parent-approved `--approved-base` before mutation. Missing base context, duplicate artifacts, wrong-base PRs, and scan failures must block instead of falling back to the GitHub default branch.
- **Issue matching boundaries tested**: confirm tests cover numeric boundary cases, tracker-prefixed branches, lookalike paths, local/remote/worktree artifacts, open PRs, and any new workflow branch prefix introduced by the PR.
- **Parent-visible disposition**: confirm duplicate-fork, wrong-base, scan-failure, and explicit-split results are visible in the parent runner summary or PR evidence before the item can be marked ready.

Additional checks for **PRs that add new filter parameters to a tool schema** (Zod, JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism):

- **Filter-wiring verification**: confirm the new filter is wired to the query builder's WHERE clause or equivalent filter-application function — not only declared in the schema.
- **Canary test presence** (blocking): confirm a canary test is present that calls the tool with the new filter set to a value that narrows results, calls the tool again without the filter (or with a meaningfully different value), and asserts the two result sets differ. A canary test that produces identical results for both invocations does not satisfy this requirement.
- **Same-PR inclusion** (blocking): confirm the canary test is part of this PR, not deferred to a follow-up.
- **Exemption**: this check applies to new filter parameters only. Modifications to existing filter parameters that do not change the schema contract are exempt.

Additional checks for **shell scripts** (`*.sh`):

- Option parsing validates that required values are present before `shift`
- All error paths emit structured output consistent with the script's output contract
- User-supplied input (PR numbers, branch names) is validated before interpolation into file paths or commands
- `|| true` does not silently swallow failures from external commands (e.g., `gh`, `git`) that the caller needs to know about
- Workflow shell PRs run `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop` in addition to ShellCheck; missing guard execution is an important finding

Additional checks for **database migrations** (when a migration adds or changes triggers, functions, or backfills):

- **Trigger/backfill arithmetic parity**: If both a trigger and a backfill compute the same derived value, they must use the **same formula**, including guards such as `GREATEST`, `LEAST`, `COALESCE`, and null handling. A trigger that differs from its backfill is a latent production bug.

Additional checks for **features with concurrent event sources** (when the PR introduces or modifies code where multiple execution contexts — listeners, timers, callbacks, async queues — can access shared mutable state):

- **Shared mutable state guards**: shared state is protected from concurrent reads/writes by a consistent access pattern (e.g., serialized queue, ownership transfer, copy-on-update)
- **Re-entrancy / in-flight tracking**: the handler correctly tracks or rejects concurrent in-flight operations when a second event can arrive before the first completes
- **Event deduplication**: duplicate logical events (e.g., reconnect triggers, repeated callbacks) are deduplicated or idempotent
- **Listener and resource cleanup**: all registered listeners, timers, and handles are removed at teardown; in-flight operations are drained or discarded safely
- **Race conditions at initialization**: events that arrive before initialization completes are handled correctly (queued, dropped, or deferred with correct sequencing)
- **Race conditions at teardown**: events that arrive after teardown begins are discarded or drained without causing errors or accessing freed state
- **Error propagation across async boundaries**: errors from async callbacks are surfaced to the caller; unhandled rejections or uncaught exceptions in callbacks do not silently swallow failures

Typical `blocking` issues:

- Incorrect behavior
- Security flaw
- Broken build/test path
- Missing critical test coverage for changed business logic

Typical `important` issues:

- Important edge cases missed
- Unnecessary complexity
- Inconsistent architecture or unclear code structure

---

## Tool Guidance

### Claude Code

- Prefer Claude Code's native review capability for the pre-PR review gate.
- Use the checklist in this file as the review rubric.
- If a repo compatibility protocol is explicitly requested, use the corresponding wrapper protocol under `docs/workflow/development-workflow/protocols/`.

### Codex

- Prefer Codex native review/code-review capability for the pre-PR review gate.
- Use the checklist in this file as the review rubric.
- If a repo compatibility protocol is explicitly requested, use the corresponding wrapper protocol under `docs/workflow/development-workflow/protocols/`.

### Cursor

- Use the repo commands `/review-spec`, `/review-implementation-plan`, and `/review-code`.
- Those commands should manually review against this file and apply direct fixes when appropriate.

### CodeRabbit CLI

- Use the CodeRabbit CLI as an optional pre-push review tool for local changes.
- In Claude Code: `/coderabbit:review`. Standalone: `cr` or `cr --agent`.
- CodeRabbit CLI findings complement the pre-PR review gate but do not replace it.
- See [`docs/workflow/development-workflow/integrations/coderabbit.md`](docs/workflow/development-workflow/integrations/coderabbit.md) for setup and usage modes.

### Automated PR Reviewers

- Treat automated PR reviewers as post-push validation.
- Default aggregation policy is sequential: run configured reviewers in order and do not continue to the next reviewer until the current one is `clean` or `skipped`.
- Any blocking finding from any configured reviewer keeps the PR out of `ready-for-human-review`.
- Suggestions remain non-blocking unless they are restated as a blocking review decision.
