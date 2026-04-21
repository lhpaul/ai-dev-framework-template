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

| Severity | Meaning | Default action |
|---|---|---|
| `blocking` | Incorrect behavior, spec/plan deviation, broken workflow contract, security issue, missing critical validation or tests | Fix before PR is ready |
| `important` | Edge-case gap, maintainability issue, unclear design choice, incomplete workflow update | Fix by default unless a human decision is required |
| `suggestion` | Improvement that is optional and low-risk | Fix by default; report if scope-expanding or requires a product decision |

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
- Use cases are explicit: actor, trigger, steps, outcome
- Acceptance criteria are specific and testable
- When a tracker issue is linked, brief objectives are fully covered via a visible matrix: each objective maps to AC(s) or explicit out-of-scope deferral with rationale
- Business rules are unambiguous and non-contradictory
- Scope boundaries and out-of-scope items are explicit
- Status or enum changes include display labels and transitions
- The spec stays product-focused and does not over-prescribe technical design
- Terms align with the project domain and existing business rules

Typical `blocking` issues:
- Missing or ambiguous acceptance criteria
- Contradictory business rules
- Spec drift that would force engineering to guess

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
- Documentation updates are listed or intentionally declared unnecessary
- Seed data, generated artifacts, and follow-up tasks are called out when applicable
- The proposed approach matches existing architecture and repo patterns
- Testing and smoke-test coverage map back to acceptance criteria

Typical `blocking` issues:
- Plan steps do not cover required acceptance criteria
- The plan requires guessing at implementation details
- The plan introduces unsafe or contradictory architecture decisions

Typical `important` issues:
- Vague wording like "update as needed"
- Missing documentation/test updates
- Incomplete dependency or rollout notes

---

## Code Review Checklist

Read before reviewing:
- The corresponding spec (Full Pipeline only — Refactor items have no spec; use the work item brief instead)
- The implementation plan
- Relevant best-practice docs
- The changed code

Check:
- Implementation matches the approved spec and plan (or the plan and work item brief for Refactor items), or any deviations are documented
- Project and stack conventions are followed
- Logic and edge cases are correct
- Security boundaries and validation are respected
- Tests cover the changed business behavior
- CHANGELOG and workflow-specific artifacts are updated when required (spec/plan-only PRs are exempt; fixes to unreleased work update existing entries rather than adding new ones; in parallel batches, each PR adds its own CHANGELOG entry as normal; merge conflicts are resolved by batch-merge auto-resolution per protocol 94 Step 4.3)
- New patterns are justified and consistent with the codebase

Additional checks for **shell scripts** (`*.sh`):
- Option parsing validates that required values are present before `shift`
- All error paths emit structured output consistent with the script's output contract
- User-supplied input (PR numbers, branch names) is validated before interpolation into file paths or commands
- `|| true` does not silently swallow failures from external commands (e.g., `gh`, `git`) that the caller needs to know about

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
- If a repo compatibility protocol is explicitly requested, use the corresponding wrapper protocol under `docs/ai/development-workflow/protocols/`.

### Codex

- Prefer Codex native review/code-review capability for the pre-PR review gate.
- Use the checklist in this file as the review rubric.
- If a repo compatibility protocol is explicitly requested, use the corresponding wrapper protocol under `docs/ai/development-workflow/protocols/`.

### Cursor

- Use the repo commands `/review-spec`, `/review-implementation-plan`, and `/review-code`.
- Those commands should manually review against this file and apply direct fixes when appropriate.

### CodeRabbit CLI

- Use the CodeRabbit CLI as an optional pre-push review tool for local changes.
- In Claude Code: `/coderabbit:review`. Standalone: `cr` or `cr --agent`.
- CodeRabbit CLI findings complement the pre-PR review gate but do not replace it.
- See [`docs/ai/development-workflow/integrations/coderabbit.md`](docs/ai/development-workflow/integrations/coderabbit.md) for setup and usage modes.

### Automated PR Reviewers

- Treat automated PR reviewers as post-push validation.
- Default aggregation policy is sequential: run configured reviewers in order and do not continue to the next reviewer until the current one is `clean` or `skipped`.
- Any blocking finding from any configured reviewer keeps the PR out of `ready-for-human-review`.
- Suggestions remain non-blocking unless they are restated as a blocking review decision.
