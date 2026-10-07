# GraphQL budget-aware portfolio scanning — Implementation Plan

**Spec**: [Approved spec](1_1505-graphql-budget-aware-scan_specs.md)
**Smoke test runbook**: [Fixture runbook](../../../testing/workflow/1505-graphql-budget-aware-scan.smoke-test.md)

## Summary

Add a read-only scan coordinator that controls every scan-owned GraphQL read,
uses current open-issue identities rather than historical development folders,
and passes its invocation-local evidence to the existing batch classifier.
Replace the organization-project fallback's unrestricted board enumeration with
a bounded candidate query whose results are joined by exact issue identity.
Implement the spec's coverage decision, reserve, and spend report in the
coordinator, with one canonical contract consumed by the runner mirrors.

**Estimated complexity**: L. The difficult work is closing the composed
classification path over the same evidence and preserving failure handling.
**Dependencies**: None. The inspected revision includes the shared surfaces
associated with #1801, #1804, and #1583; preserve their behavior as described
in the verification and consumer records below.
**Template fit**: Passed. Bash, Python, jq, GitHub tracker integration, and
runner guidance are framework toolchain surfaces; no application stack is added.

## Verification Log

Repository-derived evidence below was gathered at
`9095fab97cdecdc8271c54d7374bd396688f5f02` on 2026-10-07. Paths are relative
to the repository root. Commands describe the inspected population, not a
frozen implementation count.

| ID | Reproducible command/query | Finding and implication |
| --- | --- | --- |
| V1 | `git rev-parse HEAD origin/develop` | Both resolve to the recorded revision; artifact base is `develop`. |
| V2 | `rg -n 'template:|is_template:|provider:|project_number:' .ai-dev-workflow.yaml` | Framework mode, GitHub Projects, project number 1. |
| V3 | `rg -n 'projectItems|page_count|graphql_exhausted|workflow_github_project_item_from_item_list' scripts/development-workflow/workflow-lib.sh` | Primary issue connection is paginated with a page guard; successful empty membership activates the organization-project fallback. |
| V4 | `rg -n 'workflow_github_project_item_for_issue|workflow_github_project_item_from_item_list' scripts .agents .codex .claude .cursor docs/workflow/development-workflow --glob '!**/fixtures/**'` | Shared direct consumers are enumerated in the composed-consumer table. Test and documentation matches are regression/documentation evidence, not new production consumers. |
| V5 | `rg -n 'project item-list|rate_limit|unavoidable|3.5' docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/integrations/github-projects.md` | Portfolio guidance prescribes an unrestricted board read and contains the superseded pause explanation. Replace those scan claims; retain out-of-scope exhaustive lookup guidance. |
| V6 | `rg -n 'tracker_status|workflow-next-action|gh pr|development_paths' scripts/development-workflow/workflow-batch-plan.sh` and `rg -n 'gh pr|get_tracker_type_for_issue' scripts/development-workflow/workflow-next-action.sh` | Batch classification can scan retained folders and make additional tracker and PR calls. The scan integration must bypass those live reads using supplied evidence, not merely optimize Step 1a. |
| V7 | `rg -n 'same_repo_item|item_repo_slug|candidate_keys|issueType' scripts/development-workflow/workflow-lib.sh` | Repository-aware joins and configured/custom/native Type precedence are present. Reuse their semantics. |
| V8 | `rg -n 'fallback_|cross_repo|paged_|truncated|rate_limited' scripts/development-workflow/tests/test-workflow-lib-github-projects.sh scripts/development-workflow/tests/test-run-work-router.sh scripts/development-workflow/tests/test-framework-mode-type-routing.sh` | Relevant existing fixture assertions cover org fallback, identity isolation, exhaustive helpers, and router/classification behavior. Extend or preserve them rather than deleting incompatible expectations. |
| V9 | `rg --files .claude .cursor .agents .codex` | Scan mirrors to update are the explicit Documentation Updates list. There is no proposed new review checklist. |
| V10 | `rg -n 'scripts/development-workflow|fixtures|workflow' sync-manifest.yaml scripts/development-workflow/select-test-suites.sh .github/workflows/workflow-tests.yml` | New runtime and test assets need shipped sync coverage and suite selection coverage. |
| V11 | `gh issue view 1505 --json body --jq .body` and `rg --files docs/specs/developments/20261002145704_1505-graphql-budget-aware-scan` | Issue references are textual; development folder has the spec and no design-asset pointers or assets. No fidelity baseline applies. |

### Factual claim evidence

**Rule 1 sampling record**: Producer is repository maintainers' issue titles,
consumed as free text by D3. The population is current target titles, sampled
on 2026-10-07 with `gh issue view <number> --json title,url` for the item and
its shared-surface references. Three real occurrences yielded three distinct
variants; saturation was not established. Durable redacted-free captures:

- [Issue 1505](https://github.com/lhpaul/ai-dev-framework-template/issues/1505):
  `fix(protocol-90): a single /run-work scan exhausts the hourly GraphQL budget at 514 board items and blocks the /run-items it recommends`
- [Issue 1801](https://github.com/lhpaul/ai-dev-framework-template/issues/1801):
  `fix(workflow-lib): Status/Type helpers miss org-project cards when issue.projectItems is empty`
- [Issue 1804](https://github.com/lhpaul/ai-dev-framework-template/issues/1804):
  `tracker: paginate + strengthen repo-identity join in framework-item project reads`

Adequacy: these captures demonstrate punctuation, CLI-looking content, and
structured-looking names, not every possible title. D3 does not bind to this
observed vocabulary: treat every title as arbitrary Unicode text, escape by
the documented filter grammar, and fail unreadable when safe encoding is not
possible. The parser fixtures expand to quotes, backslashes and filter-shaped
text; they are adversarial tests, not claims of additional real samples.
Preserve the existing #1503 error classifier; unknown API errors remain
tracker failures, never absence. No new literal stderr vocabulary is introduced.

Contracts inspected directly on 2026-10-07:

- [Issue schema](https://docs.github.com/en/graphql/reference/issues#issue):
  `projectItems` supports cursor pagination and `includeArchived`, whose
  documented default includes archived items. Make archival inclusion explicit
  where supported; never infer archived invisibility from an empty result.
- [Project schema](https://docs.github.com/en/graphql/reference/projects#projectv2):
  `items` supports `query` and `archivedStates`; it does not document an
  issue-number lookup argument. A read-only introspection query for
  `__type(name:"Issue")` and `__type(name:"ProjectV2")`, selecting field names
  and argument names/types, confirmed these fields on github.com.
- [Project filtering](https://docs.github.com/en/issues/planning-and-tracking-with-projects/customizing-views-in-your-project/filtering-projects):
  use repository/type/state filters as candidate selectors. Text search is
  title/text matching, never proof of issue identity. Exact identity is checked
  in the returned content.
- [GraphQL limits](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api):
  predict cost from connection fan-out at requested page bounds; the documented
  minimum is one point, and the formula can change. Use explicit fixed query
  shapes below, not historical average cost or `gh project item-list` internals.
- `gh project item-list --help` on gh 2.97.0 advertises `--query` for
  github.com/GHES 3.20+. The new direct GraphQL fallback must not assume that
  flag exists on older CLI versions or that older hosts support the schema.

**Rule 3**: Not applicable. No quantity of existing codebase artifacts is used
to decide scope; V4 supplies consumers explicitly. Numeric constants and fixture
sizes below are proposed behavior/test inputs, not repository artifact counts.

**Rule 6 scope**: Every budget obligation below governs one no-target
GitHub-Projects scan invocation and is discharged by its coordinator and
fixture ledger. Every bounded-fallback obligation governs one target/project
lookup and is discharged before that target can advance to mutation. Snapshot
obligations govern only the coordinator's classifier descendants, with the
same invocation ID and repository identity; later bounded commands always
perform fresh reads. Other providers and out-of-scope exhaustive readers keep
the existing paths.

## Cross-Cutting Operational Assumption Check

| Surface | Recorded value | Authoritative source | Verified at | Bounded scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner/base | Current single repository; `develop` | Parent's bounded handoff and V1/V2 | 2026-10-07, recorded revision | Invocation `[1505]`; parent reports no same-surface open PR | Verified |
| Shared tracker semantics | Preserve org fallback, repository join, framework Type gate | V3/V7/V8 | 2026-10-07, recorded revision | Same shared helper surface for this item; no new provider/configuration conflict | Verified |

## Decisions and API Contract

### D1 — Current identities and zero-GraphQL projection inputs

Read the budget first through `gh api rate_limit` and validate only
`.resources.graphql`. For readable budget, apply the spec's projection gate
before any projection read. After that gate, use paginated REST issue reads
`repos/{owner}/{repo}/issues?state=open&per_page=100` (exclude pull-request
objects) and open pull-request reads under the repository API, plus local
folders and `git ls-remote` workflow branches. Do not use `gh issue list --json`
or `gh pr list --json` for these inputs: their hidden GraphQL queries are not
part of the cost model. Follow REST Link pagination, validate payloads, dedupe
by `(repository, number)`, and refuse incomplete enumeration on a page/read
failure. REST quota failures remain tracker-unavailable errors; no pagination
failure is represented as an empty portfolio.

The full candidate set is every current open issue in the repository. The
partial set intersects that set with issue identities named by a development
folder, current workflow branch, or open workflow PR. Closed issues retained
in folders/branches never enter either candidate set. An open issue at a
terminal status remains read for full coverage but is excluded from advancement
by existing categorization rules. No board read is used to discover identities.

### D2 — Explicit query bounds and reserve proof

Define projection ceiling **P = 2 GraphQL points**. Projection GraphQL work
consists only of scalar-only user project-ID lookup followed, when needed, by
scalar-only organization lookup. Each query has no connections and costs the
documented minimum. Resolve the repository identity from the configured remote;
do not hide an additional `gh repo view` GraphQL call in projection. These
lookups use a coordinator-owned result, avoiding command-substitution cache loss.
REST and local enumeration in D1 spend no GraphQL points.

A target read retains the primary connection's maximum **20 pages**, with
`projectItems(first:100)` and singular `fieldValueByName` selections. Add
`rateLimit { cost }` to the response and no nested connections. Under the
inspected formula each page costs one point. An exhausted successful primary
read may use one D3 fallback page, whose singular field selections also cost
one point. Thus **Q = 21 points per candidate** is the conservative target
read bound, independent of terminal board history. The coordinator must use
query shapes matching this derivation; any added connection requires a revised
bound and fixture proof before implementation readiness.

Let `E` be the whole projection spend actually incurred, `N_full` the D1 full
candidate cardinality, and `N_partial` its partial cardinality. Compute
`C_full = E + Q*N_full` and `C_partial = min(C_full, E + Q*N_partial)`.
All counts come from complete current enumeration; no old board count or
cross-command cache is used. Unknown counts make that cost unfit for the
available budget, rather than assigning zero. When enumeration cannot supply a
count without further GraphQL work, use this conservative unknown outcome;
projection never exceeds P.

Ledger each query's maximum before sending it; send only when the admitted
coverage's remaining reservation can pay it. The proof is
`E <= P`, actual target spend `<= Q*N_selected`, and
`R >= C_selected + S`, therefore scan-owned spend `<= R-S`.
Do not double-count E by subtracting it from R and also comparing against a
cost including E. REST-only evidence completion/classification adds no GraphQL
cost. Both budget samples use REST; they do not consume GraphQL points.

The optional YAML key is `portfolio_scan.graphql_reserve`, default **1000**.
Only whole-number scalar values in **0..5000** are accepted; distinguish an
absent key from present empty/null. Warn and fall back for malformed values,
including booleans, decimals, signed/negative strings, and collections.
Use existing effective configuration resolution; no environment-only reserve.

This bound is tied to the inspected GitHub cost contract. Fixture tests verify
query shape and returned `rateLimit.cost`, including maximum membership pages.
If the server returns a cost inconsistent with that contract, stop further
reads and report tracker failure with explicit evidence; do not silently
continue or claim the reserve proof remains valid. Supporting a changed server
cost formula needs a revised bound. This is distinct from other consumers'
spending, which follows the spec's warning behavior.

### D3 — Organization-project fallback without exhaustive board reads

Change `workflow_github_project_item_from_item_list` internally to perform one
direct `ProjectV2.items(first:100, query:$query)` request. The selector combines
repository, `is:issue`, and escaped title text from a fresh REST target read;
add `is:open` only for an open target. Do not use issue-number text as a filter.
When the title cannot be represented safely, leave the target unreadable;
never substitute an unrestricted selector. Request item/content identity,
`pageInfo`, and the same singular Status/Type/Priority/Size values as the
primary lookup. Reuse existing Type precedence and exact repository join.

Accept an exact `(repository, issue number)` match, even if other title matches
are returned; reject conflicting duplicate exact identities. With no exact
match and `hasNextPage=true`, report a bounded-candidate limitation and leave
membership unknown; never paginate further or report absence. A complete
supported query with no exact match can establish absence. Unsupported query
arguments/host schemas, permission errors, and malformed responses are
unreadable tracker state. Do not retry without filters.

Request archived and unarchived states where the host supports the documented
argument. On older hosts, use the primary issue connection when available;
unsupported fallback remains an explicit limitation. Guidance must state that
an archived organization-project card invisible to the primary connection is
readable only through a supported archived-aware fallback whose exact card is
within the candidate cap. Require restore/reconcile by the operator when it is
not; do not automate restoration. This is the exact AC16 alternative, rather
than promising undocumented universal support.

Replace the board-sized per-process fallback cache with target/project-keyed
results preserving private storage, TTL, and post-mutation invalidation.
Include repository, project, target, and selector/archival mode in identity.
A scan uses only its own newly gathered evidence; bounded commands do not read
the scan snapshot or inherit its budget admission.

### D4 — Composed scan path and evidence completion

Add `workflow-portfolio-scan.sh` as the canonical coordinator and optional
`--json` output. Its private invocation snapshot identifies repository/project,
invocation ID, open identities, coverage, fully read records, omissions, and
spend evidence. Delete temporary files on exit. The snapshot may be passed
within this invocation only; it is not a reusable cache.

Add explicit `--scan-snapshot <path>` support to `workflow-batch-plan.sh` and
`workflow-next-action.sh`. Their scan mode checks repository/invocation scope
and complete-record membership before classification; it consumes Status/Type
and PR evidence from the coordinator and performs no additional live tracker,
PR inspection, comments, or review-thread GraphQL calls. Their normal bounded
modes continue with fresh current reads. Call batch planning with explicit
current in-flight development paths, never its no-argument historical sweep.
Use the current snapshot to apply #1583, preserving stale-Backlog artifacts and
held/unreadable classification.

Gather necessary open PR details, labels, comments, and status/check evidence
with REST only on active in-flight candidates. Where the normal next-action
path looks for a matching merged branch, replace that scan-path read with a
bounded REST lookup for that active candidate. Do not enumerate historical
PRs portfolio-wide. A scan proposes stage advancement, never merge approval;
review-thread readiness remains a fresh bounded-command gate, not a fabricated
REST equivalent. Evidence needed for Protocol 90 categorization must be
completed before atomically appending an item to `fullyRead`. Missing Status,
Type, dependency evidence, or required PR evidence yields HELD/unreadable, not
an actionable or proposed record. Named skipped items remain visible.

The coordinator returns discovery/classification data; the runner renders the
usual distinct report categories and recommended bounded command solely from
fully read eligible records. The helper performs no dispatch, tracker writes,
PR comments, branch creation, or archival. Only remote reads and temporary
private local files are permitted.

## Complex Workflow Decision-Gate Matrix

The spec's ordered pre-scan and mid-scan tables are authoritative; D2 supplies
the concrete costs. Mirrors reference Protocol 90, never independent formulas.

| Inputs / class | Outcome and required next action | Evidence / examples | Surfaces |
| --- | --- | --- | --- |
| Before sample unreadable | Full attempt; unavailable spend; after sample still attempted | Missing/malformed GraphQL budget and REST-budget-only responses | Coordinator, Protocol 90, scan mirrors |
| Readable R below P+S | Deferred before D1/D2 projection; no board read or proposal | R=900 and R=S+P-1 | Same |
| Projection complete, R admits full | Full, complete Backlog discovery | R=C_full+S equality | Same |
| Only partial fits | Partial; in-flight only, no new Backlog starts | R=C_partial+S, full bound greater | Same |
| Neither projection fits / full and partial unknown | Deferred; no board read or batch | R below partial threshold; unknown costs | Same |
| Rate limit, at least one fully read item | Narrow to partial, stop reads, drop all new-start proposals | Rejection after committed record and after fully read Backlog | Same |
| Rate limit before fully read item, including projection | Deferred, stop reads, no batch | Projection rejection and incomplete first record | Same |
| Non-rate API failure | Existing tracker-unavailable/error path; no false completion | Unsupported selector, bad JSON, REST failures | Shared readers, coordinator, #1503 router |
| After sample fails | Prior coverage stands; all spend fields unavailable; warning | Each admitted coverage | Coordinator/report |
| After sample changes reset or remaining rises | Spent unavailable due reset; newer remaining/reset retained | Reset change without remaining rise; rise with same timestamp | Coordinator/report |
| After remaining below S without rejection | Full/partial retains coverage and warns; deferred omits warning | Other-consumer spend | Coordinator/report |

Six-check preflight: overlapping rows pass through spec precedence; missing
states pass including unknown projections; order pass (gate before projection,
mid-scan override before summary); malformed input pass through typed validation;
currency pass through invocation evidence and fresh bounded reads; terminal/
waiting/escalation pass through proposal, deferred retry guidance, or existing
tracker error. No waiting loop or sleep is added to scanning.

## Composed Consumer Expectations

V4 is the reproducible consumer enumeration. Apply the same targeted reader
contract at these direct consumers; an unknown membership must not fall through
to a mutating absence branch. Preserve existing provider behavior.

| Consumer site | Ordered path and expected outcome |
| --- | --- |
| `workflow-lib.sh:get_tracker_status_for_issue` | Targeted reader → current Status; unreadable remains unreadable. Router error evidence retains #1503 classification. |
| `workflow-lib.sh:get_tracker_type_for_issue` | Targeted reader → existing Type precedence → #1583 classification; missing Type cannot become actionable. |
| `workflow-lib.sh:ensure_on_project_board` | Targeted reader → proven present skips add; proven absent may use existing add path; unknown skips add with warning. |
| `workflow-lib.sh:update_tracker_status_best_effort` | Targeted reader → item ID/status-order checks → existing update; unknown skips mutation. |
| `workflow-lib.sh:update_tracker_type_best_effort` | Targeted reader → verified item ID → existing required/best-effort handling; unknown cannot edit a guessed card. |
| `workflow-lib.sh:update_tracker_named_field_best_effort` | Targeted reader → item ID → existing Priority/Size update; unknown follows existing failure policy. |
| `add-backlog-item.sh` post-creation verification | Fresh targeted reader → field comparison; fallback cap/unsupported host is verification failure, not verified completion. |
| `workflow-lib.sh:workflow_github_project_item_for_issue` fallback edge | Successful exhausted primary → D3; rate-limit/auth failure never activates an unrestricted retry. |

Audit transitive callers with V4 and V6 again at implementation HEAD. Normal
release/retrospective exhaustive readers (`workflow_gh_project_items_exhaustive`,
`list_open_workflow_type_issues`, `list_open_framework_items.sh`) remain on their
existing exhaustive paths; do not globally replace their semantics.

## Parser/API/Consistency Checklist

**Parser risk applies** to structured configuration, query escaping, and
snapshot validation. Before implementation readiness, map each indicative case
below to an automated assertion in
`test-workflow-portfolio-scan.sh` or `test-workflow-lib-github-projects.sh`.

| Edge case | Intended automated coverage |
| --- | --- |
| Reserve absent, null, empty, whitespace, 0/5000, 5001, boolean, decimal, negative, list | Config default/validation and gate boundaries |
| Title contains quotes, backslashes, colons, Unicode, or filter-looking text | Escaped candidate selector; no query injection or unrestricted fallback |
| Foreign repository issue with same number; mixed-case slug; missing content identity | Exact identity join; fail closed on missing identity |
| Multiple title matches, exact card at cap, missing exact card with next page | One bounded request; match accepted only by identity; truncation unknown |
| Duplicate exact card or repeated cursor / missing cursor | Conflict/pagination errors; no unbounded repeat or false absence |
| Missing/null GraphQL resource, valid REST resource alone, malformed snapshot | Typed budget/snapshot validation; unchanged API failure semantics |
| Snapshot has fully read item plus incomplete item; wrong repo/invocation | Only fully read scoped records classify; invalid snapshot rejected |

No suppression directives are introduced. API behavior is the D1–D4 contract;
null/partial GraphQL data must be checked alongside `errors` even on HTTP 200.
Snapshot consistency is bounded to one scan, not a server transaction; later
commands read fresh state and apply existing pre-mutation guards.

**Concurrent-event-source**: Not applicable to listeners/queues/timers. Reads
are sequential within one coordinator, with private invocation state and no
parallel GraphQL workers. Other account consumers are external budget spend
covered by the spec; the plan adds no shared mutable event state.
**Cross-cutting checklist**: Not applicable. This modifies a discovery gate,
not a universal planning, quality, security, or compliance checklist.

## Layer-by-Layer Changes

### Runtime and configuration

- `scripts/development-workflow/workflow-portfolio-scan.sh` — implement D1/D2/D4,
  ordered coverage and reporting; AC1–AC3, AC6–AC13, AC17.
- `scripts/development-workflow/workflow-lib.sh` — D3, typed budget/config
  helpers, exact identity and failure evidence; AC4/AC5/AC9/AC16.
- `scripts/development-workflow/workflow-batch-plan.sh` and
  `scripts/development-workflow/workflow-next-action.sh` — D4 scan evidence path;
  AC1–AC3/AC10–AC13. Bounded modes remain fresh.
- `.ai-dev-workflow.yaml` — document optional key from D2 without secrets;
  AC17 and business rule 6.
- `sync-manifest.yaml` and `scripts/development-workflow/select-test-suites.sh`
  — ship/select the added helper, fixtures and tests under V10; no broad CI rewrite.

### Tests and fixtures

Add `scripts/development-workflow/tests/test-workflow-portfolio-scan.sh` and
its fixture directory
`scripts/development-workflow/tests/fixtures/workflow-portfolio-scan/`.
Extend `test-workflow-lib-github-projects.sh`, `test-run-work-router.sh`, and
`test-framework-mode-type-routing.sh` where the changed path needs coverage.
Use a fake `gh` executable and a charged-request ledger; unexpected API calls
and mutations fail immediately. REST responses, primary membership pages,
selector candidates, PR evidence, reset times, and reserve values are fixture
inputs. Seeds use invented repository/card identities, never production data.

## Testing Strategy

Coverage intent: protect decision boundaries, composed discovery-to-classifier
behavior, bounded fallback isolation, and spend accounting. Scenario lists are
indicative; equivalent grouped assertions are allowed. A single parameterized
fixture ledger is enough; no parallel custom parser or live benchmark platform.
This passes Gate B proportionality because runtime behavior, not prose alone,
is the tested deliverable.

| Coverage class | Acceptance criteria | Required observable evidence |
| --- | --- | --- |
| 500+ board-history scan and immediate bounded start | AC1/AC2 | Fixture with 41 open identities, at least one proposal, R>=4500; full scan costs <=1000, leaves reserve, recommended bounded command resolves/preflights and reaches mocked first-stage dispatch in same window |
| Terminal growth and bounded target/epic reads | AC3/AC4 | Same active/in-flight set; terminal histories 50 vs 1000; board read-request count unchanged; exact Status/Type for single, pair and epic children |
| Router rejection compatibility | AC5 | Tracker unavailable and reset time; existing #1503 suite green |
| All summaries and unreadable/reset/concurrent samples | AC6–AC9 | Exact spec fields/warnings; three unreadable permutations; REST budget never substituted; observed delta may include other consumers |
| Partial/deferred/equality/unknown projections | AC10/AC11/AC17 | Each matrix boundary, P ledger upper bound, no projection/read below gate, reserve invariant across admitted starting budgets |
| Mid-read/projection rejection and no mutation | AC12/AC13 | Stop request ledger immediately, atomic fullyRead filter, remove fully read Backlog starts, mutation counter zero |
| Archival and guidance | AC14–AC16 | Human document inspection plus archived primary/fallback fixture; explicit unsupported/capped limitation |
| Shared surface regression | Related #1801/#1804/#1583 | Org Status/Type and update remain correct; foreign card never joined; framework Workflow held; stale artifacts retain correct classification |

Runtime proofs use fixtures/stubs only under the user’s invocation restriction;
no live `/run-work`, board scan, or new-query test is authorized. The schema
inspection above is planning research, not runtime validation. Record this
user-scoped override of the general live GraphQL query testing convention in
the implementation PR; do not silently claim live validation.

Run relevant suites and `git diff --check`, `bash -n`, ShellCheck on changed
scripts, markdownlint and heuristic lint on changed Markdown, and diff-aware
`workflow-shell-snippet-lint.py`. Executable documentation snippets use a
`bash` contract, with explicit Bash launches. There is no application database
or UI seed requirement. The template E2E placeholder is not a real application
regression suite; these committed workflow fixture suites supply regression.

**Residual verification**: at implementation HEAD rerun V3–V10 and inspect
all scan-path GraphQL calls against the D2 ledger. Show the composed test's
request log (including downstream batch/next-action calls), candidate identities,
fully read omissions, and no unrestricted `project item-list` request. Preserve
out-of-scope exhaustive reader regression and link any residual change needed
outside this scope rather than silently widening implementation.

## Documentation Updates

Update during implementation, not on this plan branch:

- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  — canonical D1–D4 scan path, coverage/report matrix, and adjacent terminal
  archival guidance; keep existing post-discovery dispatch warnings.
- `docs/workflow/development-workflow/integrations/github-projects.md` — fallback
  limits/performance cross-reference and archived-read limitations.
- `.claude/commands/run-work.md`, `.cursor/commands/run-work.md`,
  `.agents/skills/run-work/SKILL.md` — require canonical coordinator evidence for
  no-target scans and preserve routing/report categories.
- `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md`,
  `.codex/skills/workflow-orchestrator/SKILL.md` — same Protocol 90 contract.
- This runbook — replace projected fixture command names only if equivalent
  implemented commands differ, retaining every AC mapping.

Project architecture and database files are template placeholders; this change
adds no product architecture/data model. `AGENTS.md` already routes discovery
to Protocol 90; no additional policy or guidance there is necessary.
Archival prose names Released/Cancelled, forbids premature Merged/in-flight
archival, requires canonical reconciliation of legacy Done, explains manual and
auto-archive options and restoring reopened issues. Do not write an archival
mutation into any command.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Hidden GraphQL classifier reads drain admitted spend | Explicit snapshot mode and fail-on-unexpected-request composed fixture; D4 forbids live fallthrough |
| Org target absent from issue membership | Identity-validated D3 fallback; unknown state blocks mutation and identifies cap/host limitation |
| Server cost/schema changes | Contract-shaped queries, cost evidence and explicit compatibility failure; never unsafe full-board retry |
| Title selector overmatches or escapes incorrectly | Parser edge cases and exact repository/number match, with a fixed request cap |
| Account concurrency or reset distorts delta | Spec warning/reset semantics; report observed delta, never claim exclusive accounting |
| Retained folders or missing fields become actionable | Open-identity intersection and atomic complete-record publication |

## Reversal Procedure

This procedure applies when an implementation of D1–D4 has landed and a
regression requires restoring the prior workflow. It does not authorize a
rollback during this plan-stage invocation. The rollback owner opens a new
`fix/1505-revert-budget-aware-scan` PR from the current `develop`, identifies the
implementation merge and any later dependent commits, and uses new compensating
commits (`git revert` where the diff is clean). Preserve shared history and all
branches; never reset, force-push, or restore entire old files over unrelated
changes. For a downstream repository, use its normal PR path and current
integration base, with that repository's owner coordinating the rollback.

The rollback PR restores the shared targeted-reader/fallback behavior and its
consumer error handling from before this implementation. In the same coherent
change, revert the coordinator integration, scan-snapshot CLI paths in batch
and next-action helpers, Protocol 90 guidance, integration guidance, and every
scan mirror in Documentation Updates. Restore sync-manifest and suite-selection
entries alongside the matching runtime/tests, preserving unrelated additions.
Keep any regression assertions still meaningful under the restored contract;
revise or remove only assertions specific to the reverted feature. Document the
rollback in a release-note fragment through the normal implementation PR path.

Remove `portfolio_scan.graphql_reserve` from template configuration when
restoring its prior configuration. Existing downstream optional values need no
data migration: the restored older runtime does not consume that new key, so a
consumer may remove it in its coordinated rollback PR or leave it inert until
resync. Code and guidance must describe the same installed version; do not
leave new reserve/snapshot instructions pointing to a restored older helper.
Coordinate consumers that already synced the feature using a paired runtime
and guidance rollback or a follow-up template sync, recording the installed
version and preserved local customizations in their rollback PRs.

No tracker schema or persisted portfolio data is introduced by this feature.
Invocation snapshots are ephemeral and need no migration; let active scans
finish or stop before replacing their executable helpers, and discard only
that invocation's temporary files through its existing cleanup. Do not delete
board items, repository data, user branches, local environment configuration,
or checkpoint files as part of reversal.

Validate the rollback with isolated fixtures and the shared-reader, router,
classification, sync-coverage and documentation gates. Verify bounded commands
follow the restored prior target-read and pre-mutation contracts, including the
prior org-project fallback. Returning to the older costly discovery path
removes this plan's reserve guarantee: do not run a real portfolio scan to test
rollback, and state the restored cost limitation in the PR. Complete normal
current-head review/CI and merge authorization before shipping the rollback.

## Implementation Order

1. Implement and fixture-test D3 and the consumer error/absence distinctions.
   Preserve shared Type/identity/update regressions before composing the scan.
2. Implement D1/D2 admission, projection, and ledger with configuration validation;
   test boundaries before adding classification.
3. Implement D4 snapshot completion and batch/next-action integration; prove no
   hidden GraphQL calls and fresh bounded-command target resolution.
4. Add matrix/spend/mid-scan fixture coverage and same-window simulated dispatch;
   execute the smoke runbook in an isolated fixture workspace.
5. Update Documentation Updates and sync/test selection coverage; run the stated
   quality gates and residual verification.
6. Add `changelog.d/1505.fixed.graphql-budget-aware-scan.md` with literal body:
   `- **Preserve GraphQL budget after portfolio scans** (#1505): Limit discovery to current open work, resolve bounded targets without full-board reads, and report budget-aware scan coverage and spend with terminal-item archival guidance.`
7. Open the implementation PR targeting `develop`; complete normal current-head
   review, CI and delegated merge gates under the parent run's selected policy.
