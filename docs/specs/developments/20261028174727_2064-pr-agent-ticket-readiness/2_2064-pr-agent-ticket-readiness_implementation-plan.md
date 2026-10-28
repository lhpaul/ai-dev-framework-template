# PR-Agent ticket analysis and downstream readiness — Implementation Plan

**Spec**: [Approved revision f163244f](https://github.com/lhpaul/ai-dev-framework-template/blob/f163244f90010062094f6c3b1f370efca86f5f0c/docs/specs/developments/20261028174727_2064-pr-agent-ticket-readiness/1_2064-pr-agent-ticket-readiness_specs.md)
**Smoke test runbook**: [Synthetic downstream readiness](../../../testing/workflow/2064-pr-agent-ticket-readiness.smoke-test.md)

## Summary

**Approach**: Narrow the existing classifier's ticket branch while preserving its
structure validation and the independent evidence, security, focus-area and human
checks. Deliver downstream configuration guidance in ordinary sync preview,
without changing project-owned TOML.

**Estimated complexity**: M. The main risk is section isolation across the shared
classifier, evidence predicate, loop and readiness path; synthetic composed tests
are needed alongside the parser regression cases.

**Dependencies and execution boundary**: #2061 is present at the recorded base.
Spec PR #2066 was squash-merged to develop as
`f62b494c54abca0d57cd3528e7d18fdf4bd3b6f5` with Luis's approval. Plan publication
is authorized; plan and implementation merges require Luis's explicit OK.
Implementation starts only after the plan merges under Protocol 91 ordering.
The invocation authorizes medium risk only for #2064 and forbids adding it to
Project 1 or changing Type. Do not change tracker Status without authorization.

**Template fit**: Pass. The deliverable changes generic workflow shell/Python and
configuration guidance, using the template's existing toolchain.

## Verification Log

Repository-derived evidence below was inspected on 2026-10-28 at
`ba5d80b109c1330443cdcb79e2c359a9ed8f1868`. Re-run these searches at implementation
start; retain the resulting path list and explain new or removed consumers before
readiness. This is scope-residual evidence rather than a frozen sweep list.

| Check | Reproducible command | Observed scope / conclusion |
| --- | --- | --- |
| Base | `git rev-parse HEAD` | Recorded base above; #2061 implementation is in its history. |
| Classifier and consumers | `rg -n 'classify_pr_agent_review|classify-pr-agent|inspect-pr-agent|workflow_pr_agent_evidence_verdict|_pr_agent_classify' scripts .agents .codex .claude .cursor docs/workflow --glob '!*.json'` | Classifier/inspection in `apply-readiness-labels.sh`; shared predicate in `workflow-lib.sh`; loop call sites and readiness issue-comment selector; tests include runtime and evidence-context suites. See composed contract below. |
| Ticket grammar and regressions | `rg -n 'Ticket compliance|PR Code Verified|ticket_compliance' scripts/development-workflow --glob '!*.json'` | Existing ticket grammar, classifier/loop cases in `tests/test-pr-review-loop-pr-agent-coderabbit.sh`, readiness cases in `tests/lib/readiness-label-matrix-cases.sh`, evidence cases in `tests/test-review-evidence-context.py`, runtime tests. |
| Replay and proof branch | `rg -n 'verification_only|workflow_pr_agent_evidence_verdict|PR Code Verified' scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/workflow-lib.sh scripts/development-workflow/apply-readiness-labels.sh` | `_pr_agent_classify` proof collection is conditional on inspection; replay independently withholds cached evidence on verification strings. Preserve the latter conservative freshness rule. |
| Sync entrypoints | `rg -n 'sync-template-merge.py|preview|canonical' .claude/commands/sync-template.md .claude/skills/sync-template.md .cursor/commands/sync-template.md .codex/skills/workflow-sync-template/SKILL.md .agents/skills/sync-template/SKILL.md` | Claude command is canonical; `.claude/skills/sync-template.md` and Cursor carry full procedure mirrors; Codex skill and alias delegate to it. Preview is ordinary sync and dry-run entrypoint. |
| Sync implementation | `rg -n 'def show|def main|consumer_root|RESULT=|error_diagnostic' scripts/development-workflow/sync-template-merge.py` | Preview has consumer root and renders report through `show`; apply and blocking/error handling are separate. |
| Configuration and delivery | `rg -n 'require_ticket_analysis_review|Ticket compliance' .pr_agent.toml; rg -n 'project_specific|apply-readiness|development-workflow' sync-manifest.yaml` | Template disables ticket analysis; comment needs correction. Shared workflow helpers are synchronized; do not add TOML to always-sync. |
| Integration guidance | `rg -n 'classif|Ticket|TOML|precedence' docs/workflow/development-workflow/integrations/pr-agent.md` | Existing classification and TOML guidance is the documentation update target. |
| Design discovery | `gh issue view 2064 --json body` and `git ls-tree -r --name-only f163244f90010062094f6c3b1f370efca86f5f0c docs/specs/developments/20261028174727_2064-pr-agent-ticket-readiness` | Issue contains no Design assets section or linked graphical assets; spec tree contains no asset baseline. No UI fidelity step. |

## Factual Claim Evidence

### Producer contract (Rule 1)

The design binds recognized status spellings to the inspected producer renderer,
not to a claimed sample of live reviewer output. Source:
[The-PR-Agent/pr-agent utils.py at 4ea7293](https://github.com/The-PR-Agent/pr-agent/blob/4ea729335fec89f0ccd12f9bb68b90f21e749974/pr_agent/algo/utils.py#L563),
`ticket_markdown_logic`, source blob `aea96d1268e4dc5d2c224970cfb4a2584dc77a90`.
Reproduce inspection using
`gh api 'repos/The-PR-Agent/pr-agent/contents/pr_agent/algo/utils.py?ref=4ea729335fec89f0ccd12f9bb68b90f21e749974' --jq .content`
and decode the returned base64 before reading that function.

The renderer defines `Fully compliant`, `Partially compliant`, `Not compliant`,
`PR Code Verified`; requirement headers `Compliant requirements:`,
`Non-compliant requirements:`, `Requires further human verification:`; GFM
`<tr><td>` with a bold ticket-analysis heading and Markdown `###` alternative.
Its verification-only branch emits PR Code Verified. This contract fixes the
literals being recognized, not every possible historical or LLM-generated
review. Unknown output follows the unchanged fail-closed grammar. Synthetic
cases below exercise that contract and adversarial boundaries; they are not
observed external samples and no historical-population closure is claimed.

First inspection finding: the pinned function directly assigns those labels and
renders those headers/styles; it supports retaining the existing recognized
set while changing its policy weight. No broadened free-text acceptance follows
from this contract.

### Scoped obligations (Rule 6)

For structurally valid recognized ticket sections only, implementation step 1
removes ticket compliance/proof as a reason to block; parser cases and composed
cases discharge this obligation in steps 2 and 4. For any content outside that
validated section, those steps preserve the existing independent checks. For
consumer TOML inspection, step 3 discharges warning-only handling before sync
preview returns, including blocked-preview reports; errors already owned by
sync keep their existing exit paths. Publication and merge prerequisites are
owned by the Summary execution boundary, checked at future plan publication.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact ownership and base | `single_repo`, lhpaul/ai-dev-framework-template, develop | Public `.ai-dev-workflow.yaml`, invocation isolation handoff | 2026-10-28; recorded base | #2064 only | Verified |
| Configuration ownership and disable setting | Downstream TOML project-owned; template setting false | Configuration/delivery search above; spec BR5 | 2026-10-28; recorded base | #2064 and same-surface PR queries below | Verified |
| Ticket policy precedence | Approved Ticket Exception supersedes #2061 only in validated ticket analysis | Immutable approved spec, Approved Ticket Exception | 2026-10-28; spec f163244f | #2064 only; human resolution supplied by Luis | Resolved |
| Concurrent operational edits | Parent bounded queries found only spec #2066 for PR-Agent; no sync-template match | `gh pr list --state open --search '"PR-Agent"' --limit 30 --json number,title,headRefName,baseRefName`; corresponding query with `"sync-template"` | 2026-10-28, parent handoff at recorded base | Current invocation [2064]; same-surface open PRs only | Verified |

No unrelated portfolio scan is required. Repeat the bounded check before future
publication and resolve a new same-surface conflict with the orchestrator.

## Parser-Risk Classification and Edge-Case Mapping

Parser-risk applies: structured Markdown/HTML classification and TOML inspection.
No suppression directives, new API surface, concurrent listeners or cross-cutting
implementation checklist are introduced. Input normalization stays within the
existing grammar; this change is not a Markdown parser replacement.

Each row maps an automated test into the named existing suite (paths are relative
to `scripts/development-workflow/tests/`). Cases are indicative scaffolding;
coverage classes and spec behavior govern equivalent consolidations.

| Concrete input class | Expected boundary / unit-test mapping |
| --- | --- |
| Valid table and `###` analysis, status Fully compliant / Partially compliant / Not compliant, populated known requirements | `test-pr-review-loop-pr-agent-coderabbit.sh`: classifier parameter cases for informational ticket status. |
| PR Code Verified with populated ticket-only `Requires further human verification:` and no matching proof | Same suite and `test-review-evidence-context.py`: clean inspection with verification_only false and shared-predicate clean without proof. |
| Multiple tickets, including compliant plus non-compliant and ticket-only verification | Classifier suite: every ticket structurally checked; status mix informational. |
| Ticket heading only, unknown status `Maybe compliant`, empty or `&nbsp;` analysis, truncated `**[43](url) - Not compliant*` | Classifier suite: escalation; retain malformed regression cases. |
| Duplicate ticket sections on separate lines or multiple headings on one line; nested table/details closing boundaries | Classifier suite: refuse duplicate/malformed constructs; preserve structural checks. |
| Boundary presentation variants already accepted (emoji heading, whitespace, HTML entity in analysis) | Classifier suite: retain current accepted grammar; valid section isolation verified. |
| Prose mention `Ticket compliance analysis`, quoted/fenced lookalike, unknown heading prefix | Classifier suite: no invented ticket exemption; apply existing grammar/result. |
| Valid ticket plus outside `Requires further human verification:`, HTML/emphasized verification, `Verification: pending` | Classifier/evidence suites: preserve independent escalation and fail-closed rendering. |
| Valid ticket plus focus-area Must Fix or Security Concern; independent security section unknown/positive | Classifier suite: existing code/security result; escalation precedes fixes when both apply. |
| TOML `[pr_reviewer]` key false / true / absent / empty string / string `"false"` / duplicate key / parse error | `test_sync_template_merge.py`: only boolean false suppresses warning; no substring matching. |
| TOML commented-out key, lookalike `[other]` key false, dotted-key equivalent | Sync Python suite: parse section semantics; dotted-key form follows TOML meaning. |
| Missing file, unreadable file, symlink, invalid UTF-8, unavailable TOML parser | Sync Python suite: bounded safe warning; no raw file content, exception, target path or values leaked. |

## Layer-by-Layer Changes

### Shared classifier and composed contract (AC1–AC4)

- [ ] In `scripts/development-workflow/apply-readiness-labels.sh`, retain full
  structure/heading/analysis validation before informational treatment. Remove
  the valid ticket status and ticket-only proof dependency; mask only the
  validated ticket slice from independent verification scanning. The remaining
  original body still drives code/security classification. Do not strip a
  malformed slice and accidentally manufacture a clean review.
- [ ] Keep `--inspect-pr-agent` JSON fields and return classes compatible.
  Valid ticket-only requests produce the ordinary clean verdict rather than
  verification_only=true. Independent requests remain outside the exception.
- [ ] Check the composed consumers enumerated in the Verification Log using
  the following outcome contract; prefer leaving their production code intact
  where the revised shared classification already produces the required path.

| Consumer site | Producing path and post-change outcome |
| --- | --- |
| `workflow-lib.sh:workflow_pr_agent_evidence_verdict` | Inspection returns clean/verification_only false for valid ticket-only commentary, so the ordinary non-verification branch returns clean before ticket-proof lookup. The former verification-pending ticket inputs are absorbed by this branch; no proof or request authentication rule elsewhere is weakened. |
| `pr-review-loop.sh:_pr_agent_classify`, initial and subsequent bound summaries | Existing head-bound selection → shared predicate → clean → ordinary reviewer progress. Snapshot collection for ledger identity remains; its missing ticket proof cannot create verification_pending when inspection is false. Global unavailable evidence and independent human/code/security outcomes retain their existing path. |
| `apply-readiness-labels.sh`, pr-agent issue-comment check | Current-head authenticated PR-Agent selection → shared predicate → existing readiness gates. Ticket-only analysis cannot refuse the label; other configured reviewers, CI, checkpoint and human gates still decide. |
| `pr-review-loop.sh:reviewer_loop` current-head replay evidence check | Existing fingerprint and verification-string replay refusal may request normal re-dispatch. That dispatch reaches the revised classifier rather than blocking on ticket proof. Preserve this conservative replay rule and expensive-reviewer scheduling. |
| Runtime classifier consumers in `tests/test_pr_agent_runtime.py` | Producer-generated safe review is classified through the same CLI; publication identity and sanitizer behavior stay unchanged. |

### Sync warning (AC5)

- [ ] Add a small read-only ticket-setting diagnostic to
  `scripts/development-workflow/sync-template-merge.py` preview, using its
  explicitly selected consumer root. Run it after input validation and before
  preview reporting, including classified blocked batches. Apply behavior,
  approved digest, plan payload and merge decisions remain unchanged.
- [ ] Inspect only the consumer's `.pr_agent.toml` in this authorized script,
  never workflow local/private config. Use stdlib `tomllib` when available;
  absence emits a visible inspection-unavailable warning rather than adding a
  runtime dependency or guessing with regex. Refuse symlinks/non-regular files
  for diagnostic reads. Parsing/IO failures emit a static repair warning.
- [ ] Suppress this warning only for boolean false at
  `pr_reviewer.require_ticket_analysis_review`. Other states receive static
  guidance naming that key and supported `false` setting, explaining that
  valid ticket commentary is informational. Do not echo TOML values, exception
  text, absolute paths, model names or credentials, or serialize configuration
  bytes into a sync plan. The diagnostic is advisory and does not change sync
  exit status or overwrite project configuration.
- [ ] Extend `test_sync_template_merge.py` with synthetic TOML and CLI-preview
  coverage, preserving existing sync apply/preview safety tests. Prove warning
  delivery in the normal preview path, not only a standalone helper test.

### Documentation and release note (AC6)

- [ ] Update `.pr_agent.toml`'s explanation adjacent to the disabled setting.
- [ ] Update `docs/workflow/development-workflow/integrations/pr-agent.md` with
  the section-scoped exception and downstream warning behavior.
- [ ] Update canonical `.claude/commands/sync-template.md` and genuine procedure
  mirrors `.claude/skills/sync-template.md` and
  `.cursor/commands/sync-template.md` to explain the preview diagnostic.
  Delegating Codex skill wrappers require no duplicated policy. No general
  developer/review checklist change is planned.
- [ ] Add `changelog.d/2064.fixed.pr-agent-ticket-readiness.md`, using the
  repository's bold-title issue bullet convention; no CHANGELOG.md edit.

## Testing Strategy

Use the parser mapping above plus composed synthetic fixtures in
`test-pr-review-loop-pr-agent-coderabbit.sh`,
`test-review-evidence-context.py`, `test-apply-readiness-labels.sh` and
`tests/lib/readiness-label-matrix-cases.sh`. Update old ticket-only expected
blocking outcomes, preserving malformed cases and independent #2061 proof tests.
A clean summary alone is insufficient: exercise actual loop progression with
configured peer reviewer dispatch and final readiness gates using mocked GitHub
responses; do not force expensive reviewers or rewrite their gate.

Extend existing fixtures with ticket-only proof absent, code blocker,
independent verification, evidence unavailable/malformed, security and human
blocker combinations. Verify the independent blocker's original refusal remains.
Run affected readiness/consumer matrix partitions and runtime regression suite;
no live downstream mutation, billable reviewer run or remote fixture is needed.

Proportionality (Gate B): reuse existing fixture drivers with focused parameter
cases, rather than a new harness or exhaustive cross-product. Synthetic parser
boundaries protect executable classifier changes; the docs receive ordinary
Markdown checks. No fixed test-count target is imposed.

Planted-violation evidence: at implementation readiness, cite concrete fixture
file/line for the pre-fix ticket-only refusal and post-fix clean path; for the
new sync diagnostic, cite enabled/absent setting warning versus boolean-false
control with unchanged file bytes. Preserve sanitized command results in the
implementation PR. This is future evidence, not a claim that these tests ran
at plan time.

## Seed Data

Only disposable repositories, fabricated PR/head IDs, synthetic review text and
TOML with fabricated sentinel values are required. Reuse the existing test
fixture drivers; never open actual downstream or private configuration. The
smoke runbook identifies the scenario classes and cleanup boundary.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Ticket masking swallows independent verification | Medium | High | Validate exact slice; parser adversarial cases and composed independent-blocker tests. |
| Shared classifier clean does not reach final readiness | Medium | Medium | Exercise shared predicate, bound loop dispatch and readiness CLI, including proof absent. |
| Diagnostic exposes configuration or alters sync | Low | High | Static messages, no exception values, no plan serialization; byte-identity and sentinel tests. |
| Old readiness expectations reject the approved policy | Medium | Medium | Update ticket-only assertions, retain malformed/evidence/security regressions, record residual search. |

## Implementation Order

1. Revalidate recorded scope and consumer searches; implement classifier policy
   and focused parser cases from the mapping, with the spec matrix as authority.
2. Update existing evidence-context and loop/readiness fixture expectations;
   prove the composed contract before changing an untouched consumer.
3. Implement and exercise sync preview warning with synthetic TOML controls.
4. Run focused suites and smoke runbook; retain residual consumer/surface search
   results and planted-violation evidence against the implementation revision.
5. Execute the Documentation and release note checklist; run Markdown and shell
   guidance checks, then normal review/CI/readiness. No merge authority follows
   from passing these checks; the Summary execution boundary governs handoff.
