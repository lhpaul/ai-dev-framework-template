# Backlog review protocol (`/review-backlog`), tracker-agnostic — Implementation Plan

**Spec**: [1_2155-review-backlog-protocol_specs.md](1_2155-review-backlog-protocol_specs.md)
**Smoke test runbook**: [review-backlog-protocol.smoke-test.md](../../../testing/workflow/review-backlog-protocol.smoke-test.md)

---

## Summary

**Approach**: Port the origin consumer protocol into a new template protocol,
Protocol 09, rewritten so that every tracker-dependent behaviour is keyed to a
detected capability and every provider name lives inside one marked
capability-resolution reference. Add thin `/review-backlog` aliases for Claude
Code, Cursor, and the shared skills directory; list the command in the agent
guide and the workflow guide (with the `/run-work` relationship); ship the
runbook through the synchronization manifest; and guard the contract with one
documentation-contract test suite that is discovered by its own `# covers:`
header.

**Estimated complexity**: M

**Rationale**: One long normative document plus small mirror edits and one
contract test; no runtime script, configuration, or workflow change.

**Dependencies**: None. The spec is merged on `develop` (Verification Log V1).

---

## Verification Log

| ID | Check | Command / query | Result |
| --- | --- | --- | --- |
| V0 | Repo revision | `git rev-parse --short HEAD` on `implementation-plan/2155-review-backlog-protocol` at creation | `7b64564d` (= `origin/develop`) |
| V1 | Spec merged | `git merge-base --is-ancestor 7b64564d origin/develop` | exit 0; spec PR #2165 merged |
| V2 | Protocol number free | `ls docs/workflow/development-workflow/protocols \| grep '^09'` at V0 | no output |
| V3 | No prior artifacts | `grep -rln -e review-backlog -e backlog-review . --exclude-dir=.git --exclude-dir=node_modules`, excluding this development folder, at V0 | no output (searched the whole working tree, where protocols, aliases, tests and manifests live) |
| V4 | Alias directories already synced | `sed -n 68,222p sync-manifest.yaml \| grep -n 'path: \.claude/commands/\|path: \.cursor/commands/\|path: \.agents/skills/\|path: docs/workflow/'` at V0 | all four directory entries present under `always_sync` |
| V5 | Runbook needs its own entry | `grep -n 'docs/testing/workflow/' sync-manifest.yaml` at V0 | only per-file entries exist (for example `retrospective-protocol.smoke-test.md`); no directory entry |
| V6 | Project-owned docs directory | `grep -n 'path: docs/project/' sync-manifest.yaml` at V0 | present under `project_specific` |
| V7 | Suite discovery | `sed -n 1,30p scripts/development-workflow/select-test-suites.sh` at V0 | a suite declares covered paths with `# covers:` lines; new suites are wired without workflow edits |
| V8 | Dispatcher priority vocabulary | `grep -n PRIORITY_RANK scripts/development-workflow/workflow-portfolio-scan.py scripts/development-workflow/workflow-batch-overlap.sh` at V0 | both define `urgent`/`high`/`normal`/`medium`/`low`, with `normal` = `medium` |
| V9 | Canonical status events | `./scripts/development-workflow/tracker-status-for.sh --help` at V0 | events `dispatch`, `ready-for-human-review`, `merged`, `released` per stage `spec`/`plan`/`implementation` |
| V10 | Manifest coverage baseline | `python3 scripts/development-workflow/check-sync-manifest-coverage.py` at V0 | `RESULT=clean` |
| V11 | Codex installer picks up new skills | `sed -n 1,51p scripts/development-workflow/install-codex-skills.sh` at V0 | links every directory under `.agents/skills/` (`for skill_dir in "$source_dir"/*` with `ln -sfn`, lines 27 and 44); no registry to edit |
| V12 | Open PRs on the same surfaces | `gh pr list --state open` at plan time | none open |
| V13 | No sentry-triage protocol | `git ls-tree -r --name-only 7b64564d \| grep -i sentry` and `git grep -il sentry-triage 7b64564d -- .` (whole tree) | no output for either |
| V14 | Tracker integration pages | `ls docs/workflow/development-workflow/integrations/` at V0 | `issue-tracker.md` (generic), `github-projects.md`, `linear.md`; no page for Jira or for repository issues without a project |

## Factual claim evidence

**Rule 1 — sampling record** (the landed-work sweep matches free text written
by backlog authors, outside this project's control).

- Producer: humans and agents writing tracker item bodies.
- Population and window: all issues (open and closed) of
  `lhpaul/ai-dev-framework-template` up to 2026-11-12, searched with
  `gh issue list --state all --search '"<phrase>" in:body'` for seven of the
  origin protocol's eight seed forms (`already fixed`, `fixed in this branch`,
  `landed in the same change`, `fixed in the same change`, `file it anyway`,
  `for the record`, and `fixed on` for `fixed on <date>`). The eighth,
  `FIXED —`, is not sampled separately: the forge's search ignores case and
  punctuation, so it reduces to the bare word "fixed", whose hits are not a
  population of that form. The origin consumer's own tracker is not a GitHub
  tracker, so its GitHub issues returned no hits and are not part of the
  population.
- Occurrences examined, excluding #2155 itself (which quotes the phrases):
  #1529 (heading "Concrete instances already fixed (as evidence of the
  pattern)"), #1574 ("Why this is not already fixed by #1556"), #1531,
  #372 and #554/#593 (search token matches where "already" and "fixed" are not
  a claim about the item), #299 (template prose "Already fixed upstream in
  vX.Y.Z"), #1584 ("#1391 is partly fixed on `develop`", a statement about
  another item) and #1722 (token match "Fixed per-job overhead").
- Distinct variants: evidence-list heading, negation, incidental token match,
  quoted template prose, statement about another item. None is a claim that
  the item's own work shipped.
- Saturation: not reached; the population holds no true positive.
- Adequacy rationale: the sample is heterogeneous and dominated by false
  positives, which is exactly what the design must tolerate. The design binds
  to no phrase: the phrase list is a non-exhaustive seed that only nominates
  candidates, every candidate is classified by the artifact found (merged,
  partial, live branch, abandoned, absent) or by "no claim" for a negated or
  incidental match or a statement about another item, and items with no phrase at all are still covered by the
  status-drift check. An output outside the observed variants therefore
  changes only which items become candidates, never a status outcome.

**Rule 6 — scoped obligations**: listed where each obligation is stated, in
Layer-by-Layer changes L1.3, L1.6 and L5.2, and in Testing Strategy T2.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Dispatcher priority vocabulary the order reconstruction must mirror | V8 | `workflow-portfolio-scan.py` and `workflow-batch-overlap.sh` | 2026-11-12, `7b64564d` | this invocation (#2155 only) and open PRs touching those files (V12: none) | `Verified` |
| Canonical tracker status events the status-drift check resolves through | V9 | `tracker-status-mapping.md` / `tracker-status-for.sh` | 2026-11-12, `7b64564d` | same as above | `Verified` |

The protocol references both sources instead of copying their values (L1.4,
L1.5), so a later change to either is picked up without editing Protocol 09.

---

## Layer-by-Layer Changes

### L1 — Protocol 09 (`docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md`, new)

Port the origin protocol section by section (Purpose, Prerequisites, Read and
write budget, Mutation authority, Step 1, Gate 1 checks 1a–1j, Ledger format,
Gate 1 close, Gate 2 2a–2e, Gate 2 close, Gate 3, Non-goals, Relationship to
other protocols). Prose stays English; report labels stay the Spanish set in
the spec's Statuses table. The changes from the origin are:

- [ ] **L1.1 Capability-resolution reference (AC1, AC2, BR8, BR10).** One
  section wrapped in `<!-- capability-resolution:start -->` /
  `<!-- capability-resolution:end -->`, holding one table with one row per
  capability: project scope, milestone scope, parent/child hierarchy,
  priority field, priority that can be left unset, classification carrier,
  free-form labels, item closure, duplicate relation, readable rate-limit
  surface. Columns: how the run detects it (a probe against the configured
  tracker, never the provider's name), checks that depend on it, outcome when
  missing (`no aplica — <capability>`; for the rate-limit surface the outcome
  is `full (sin presupuesto)` with unmetered admission, not "no aplica"), and
  a last column "where configured integrations expose it" — the only place a
  provider or configuration value is named, each cell pointing at that
  provider's integration page under `integrations/` where one exists
  (`github-projects.md`, `linear.md`) and at `integrations/issue-tracker.md`
  otherwise (V14). Every other section
  refers to capabilities by the row name.
- [ ] **L1.2 Detection failure is not a missing capability.** A probe that
  errors or returns a malformed response marks the capability `unverified`:
  dependent checks are held and named, and coverage drops to `partial`; it
  never yields "no aplica" (spec, malformed-response paragraph).
- [ ] **L1.3 Scope (AC13, BR9).** Keep the origin's scope table, re-keyed to
  capability rows, and add the missing branch: a configured scope the tracker
  rejects or cannot find stops before reading and asks once, naming it. This
  obligation binds Step 1 before the first item read and is discharged by the
  run header's scope line.
- [ ] **L1.4 Status vocabulary by reference (AC14, BR11).** Rewrite 1a's
  evidence table so each row maps evidence to a (stage, event) pair of the
  canonical mapping (for example "spec branch or PR never human-ready →
  (spec, `dispatch`)") and tells the runner to resolve the Status through
  `tracker-status-mapping.md` / `tracker-status-for.sh`. The protocol does not
  spell out multi-word Status names; the pre-dispatch status is called "the
  initial backlog status".
- [ ] **L1.5 Classification by reference (AC14, BR11).** 1c cites
  `00-add-backlog-item-protocol.md` for the classification values, the
  heuristics and the framework-mode rule (that protocol states all three); it
  does not list the values. It does not cite the agent guide's Tracker
  Classification section: that section sits outside the agent guide's
  template-owned block, so a consumer's copy may lack it (the same
  project-ownership T2 handles).
- [ ] **L1.6 Mutation authority (AC7, BR2–BR6).** Replace the origin's
  "never" list with the spec's three classes:
  - gate-confirmable writes: upward status changes, classification changes,
    the two label corrections, and priority changes — priority only in Gate 2
    (Gate 1 may recommend a priority, never write it);
  - explicit-confirmation actions: cancel/close, duplicate merge, and item
    creation, each authorized only by a confirmation naming that item or a
    group the run presented by name; a class, range, or gate-wide answer is
    refused with a request for the explicit form. Creation runs Protocol 00
    once per confirmed item. When the item-closure or duplicate-relation
    capability is missing, the action is delivered under `PENDIENTE DE TI`.
    This obligation binds every Gate 1 and Gate 2 answer and is discharged at
    the gate close, before admission;
  - report-only: body/title/description edits (proposed text), status
    regressions, dependency edits, tracker rank fields, and any epic status
    write (1j stays report-only, so BR4's upward status changes never apply to
    an epic).
  Confirmed explicit-confirmation actions end, like every other write, as
  applied, drift, not applied, or pending (Use Case 1 postconditions).
- [ ] **L1.7 Write contract (AC7, AC17, BR3, BR7).** Keep the origin's
  admission rules and add: the observed readback value is printed per row; a
  readback that fails is a rejection.
- [ ] **L1.8 Coverage values (AC17, BR1).** Keep the origin's coverage table
  with these edits: `deferred` applies only to the initial read and ends the
  run before Gate 1 is delivered (no Gate 1 → end exit); `partial` covers any
  non-deferred read that misses items for any reason (budget, cut-short
  listing, malformed responses), naming the omitted items or declaring the
  unlisted remainder unread; a `partial` re-read after the Gate 2 writes opens
  Gate 3 with the final state marked `partial` and the same naming rule. In
  repository-only mode the forge's own rate-limit surface is sampled, the
  coverage field reads `n/a (sin tracker)`, and a read cut short names the
  repository evidence it did not reach.
- [ ] **L1.9 Gate transitions (AC6, AC17, BR1).** A short transition table
  mirroring the spec's Valid transitions, including the outstanding-action hold
  (run ends at the Gate 1 close unless the maintainer asks to rank as-is,
  recorded as an override) and that grouping by class never removes a
  confirmation.
- [ ] **L1.10 Early-end delivery (BR15).** Any run that ends before Gate 3
  prints `PENDIENTE DE TI` and the precedent lines in its last gate close
  report.
- [ ] **L1.11 Precedent record location (BR15).** The record is
  `docs/project/backlog-review-precedents.md` (project-owned, V6), read in
  Step 1 when present; the template ships no copy. The origin's
  `docs/workflow/...` location is not used because that tree is
  template-owned and would be overwritten on synchronization.
- [ ] **L1.12 Landed-work sweep (AC15, BR12).** Keep 1i with the phrase list
  marked "seed, not exhaustive" and the per-candidate "no claim" outcome for
  negated or incidental matches and statements about another item (Rule 1
  record above).
- [ ] **L1.13 Tracker path (BR10).** Prerequisites and both gate closes point
  at `integrations/issue-tracker.md`, including its deferred-action protocol
  for providers the shell cannot reach.
- [ ] **L1.14 Relationship section (AC8, BR16).** State that the review
  complements `/run-work` (Protocol 96), never dispatches, and runs before
  batch selection; relate it to Protocols 00, 06, 07, 90 and 91. Drop the
  origin's reference to a sentry-triage protocol the template does not have
  (V13).

### L2 — Command aliases (AC9, BR17)

Each alias points at Protocol 09 and restates nothing normative. This
resolves the spec's mirror-surface note: aliases are mirror surfaces only in
the sense that they must not contradict the protocol.

- [ ] `.claude/commands/review-backlog.md` (new): frontmatter `description`,
  "Follow the backlog review protocol exactly as defined in" + protocol path,
  and an optional scope-hint argument.
- [ ] `.cursor/commands/review-backlog.md` (new): same shape as the Claude
  file, Cursor wording.
- [ ] `.agents/skills/review-backlog/SKILL.md` (new) and
  `.agents/skills/review-backlog/agents/openai.yaml` (new,
  `allow_implicit_invocation: false`), following the `post-merge-qa` alias
  shape.

### L3 — Agent guide (`AGENTS.md`, template-owned block)

- [ ] Add a "Review backlog" row after "Add backlog item" in the Workflow
  Commands table: `/review-backlog` for Claude Code and Cursor,
  `/review-backlog` alias for Codex and DSH, and "Follow
  `docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md`
  — periodic three-gate backlog audit; complements `/run-work`".
- [ ] Add `/review-backlog` to the Codex Skills alias list sentence.

### L4 — Workflow guide (`docs/workflow/development-workflow/README.md`)

- [ ] Commands By Stage table: same row as L3.
- [ ] Codex alias sentence: add `/review-backlog`.
- [ ] Backlog section: one paragraph stating that `/review-backlog` audits
  whether the backlog's data and order are still right, that `/run-work`
  decides what to advance next, that neither replaces the other, and the
  sequence (periodic review, then `/run-work` selects the batch).

### L5 — Synchronization manifest (`sync-manifest.yaml`) (AC10)

- [ ] **L5.1** Add an `always_sync` entry for
  `docs/testing/workflow/review-backlog-protocol.smoke-test.md` with
  `mode_scope: hub_only` and a note naming the suite that reads it. Hub-only,
  the scope of the protocol, the aliases and the suite (V4; the suite lives
  under the `hub_only` `scripts/development-workflow/` entry), and the scope
  of the existing suite-read runbooks (V5, for example
  `retrospective-protocol.smoke-test.md`): a role that does not receive the
  suite or the protocol has no use for the runbook.
- [ ] **L5.2** No entry for the protocol or the aliases: their directories are
  already `always_sync` (V4). The obligation "every new file is shipped" binds
  each file added by L1, L2 and L6 and is discharged by
  `check-sync-manifest-coverage.py` in Implementation Order step 9.

### L6 — Contract test suite (`scripts/development-workflow/tests/test-review-backlog-protocol.sh`, new) (AC11)

- [ ] `# covers:` header for the protocol, the three alias paths, the runbook,
  the workflow guide, and `AGENTS.md` (read by the T2 assertion).
- [ ] A Python heredoc, following `test-dsh-model-routing.sh`, with fixed
  substring checks and one bounded regex, cases in Testing Strategy T1.
- [ ] Planted-violation proofs (T3), printed as `PROOF <name>: FAIL at
  <file>:<line>` then `PASS after repair`, run against temporary copies, never
  the working files.

### L7 — Changelog fragment (AC12)

- [ ] `changelog.d/2155.added.review-backlog-protocol.md`:

```markdown
- **Backlog review protocol (`/review-backlog`)** (#2155): new Protocol 09 audits the whole backlog in three confirmed gates (structural ledger, order, closeout), detects tracker capabilities instead of assuming them by provider, reports "no aplica" for missing ones, and complements `/run-work`; aliases for Claude Code, Cursor, Codex and DSH.
```

---

## Testing Strategy

**Test types**: documentation-contract suite (automated, CI) and a manual
smoke runbook executed by an agent against real and simulated tracker
configurations.

**T1 — Contract cases** (coverage intent: one assertion family per spec
contract the protocol text must carry; indicative, not binding):

- provider-neutral text: one regex matching the word-bounded product names
  Linear, Jira, GitHub Issues and GitHub Projects, plus the configuration
  values github_projects and github_issues and the backticked values linear,
  jira and none, finds matches only between the capability-resolution markers
  (AC1);
- capability table: the marker block exists once and contains each capability
  row name from L1.1 and the `no aplica` outcome (AC2, AC5);
- gates and authority: fragments for three gates in order, "no flag",
  readback/drift/failed-readback, explicit per-item or per-group confirmation,
  proposed text for body edits, and report-only rank/dependency/regression
  (AC6, AC7, AC17);
- references, not copies: the protocol links `tracker-status-mapping.md` and
  `00-add-backlog-item-protocol.md` and contains none of the multi-word Status
  names from the canonical mapping (AC14);
- sweeps, recommendations, scope, relationship: fragments for the two
  mandatory sweeps, the four recommendation fields, the scope stop-and-ask
  cases, and "complements `/run-work`" in both the protocol and the workflow
  guide (AC8, AC13, AC15, AC16);
- aliases: each of the three alias files contains the protocol path and none
  contains `--apply` (AC9);
- runbook: exists and contains one step per AC from AC3 to AC5 and the
  early-end delivery step (AC3–AC5, AC11).

**T2 — Template-only assertion.** The agent-guide row check runs only when
`workflow_template_is_template` reports `true`, because `AGENTS.md` is
project-owned in consumers (#1873). Scope: the `AGENTS.md` assertion in this
suite only; discharge point: the suite's mode branch.

**T3 — Planted-violation proofs**: (a) a provider name appended outside the
marker block fails the AC1 check; (b) an alias with the protocol path removed
fails the AC9 check; (c) a multi-word Status name inserted in the protocol
fails the AC14 check. Each is reverted and re-run green. Three proofs are
enough because they cover the three distinct check kinds (bounded regex,
per-file pointer, absence list); the remaining checks share the substring
mechanism proven by (b).

**Edge cases for the bounded regex (parser-risk note).** The suite scans
Markdown with one regex; inputs to cover: a provider name inside the block
(allowed), the same name one line after the end marker (fails), lowercase
`linear` in prose such as "non-linear" (must not match: only the backticked
config value is matched), two names on one line outside the block (one
failure naming the line), and a second marker pair (fails: the block must be
unique). No suppression directives are supported.

**Proportionality (Gate B).** The deliverable is prose; the suite is a small
fixed-string checker plus one regex that AC1 itself requires, so it is not a
custom parser for the prose.

**Smoke test runbook**:
`docs/testing/workflow/review-backlog-protocol.smoke-test.md`.

**Regression suite**: none beyond the contract suite.

---

## Seed Data

None. The smoke runbook uses this repository's own tracker, a scratch
configuration with `issue_tracker.provider: none`, and simulated capability
gaps described in the runbook; no fixture data is committed.

---

## Documentation Updates

- [ ] `AGENTS.md` — L3.
- [ ] `docs/workflow/development-workflow/README.md` — L4.
- [ ] `docs/project/*` — None: the template's project docs are placeholders
  and the precedent record is created by each repository from Gate 3 output.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Provider vocabulary leaks into normative prose during the port | Med | Med | T1 AC1 regex and proof T3(a) |
| A consumer that synced an older template lacks the runbook | Low | Low | L5.1 ships it with the suite that reads it |
| The suite asserts template-only state in a consumer | Low | Med | T2 mode branch |
| An agent reads a range answer as authority to cancel | Med | High | L1.6 refusal rule and its smoke step |

**Reversal.** Everything this plan adds is reversible with one revert PR on
`develop`: delete Protocol 09, the three aliases, the suite, the runbook and
its manifest entry, and remove the guide rows and the changelog fragment.
Consumers that already synchronized the files keep their copies until their
next `/sync-template`; files removed upstream are not deleted downstream
automatically, so the revert PR's changelog entry must tell consumers to
delete them. Tracker writes made by runs of the protocol are not reverted by
removing it; each one is already confirmed and read back per L1.7.

---

## Implementation Order

1. Create `feature/2155-review-backlog-protocol` from `develop`.
2. Write Protocol 09 (L1).
3. Write the three aliases (L2).
4. Write the contract suite (L6) and run it; at this point it must fail only
   on the missing workflow-guide and agent-guide rows.
5. Update the runbook from this plan PR if implementation changed any step
   wording.
6. Edit `AGENTS.md` (L3) and the workflow guide (L4).
7. Add the manifest entry (L5.1).
8. Add the changelog fragment (L7).
9. Verify: `bash scripts/development-workflow/tests/test-review-backlog-protocol.sh`
   (all cases and proofs pass);
   `python3 scripts/development-workflow/check-sync-manifest-coverage.py`
   (`RESULT=clean`);
   `bash scripts/development-workflow/tests/test-check-sync-manifest-coverage.sh`;
   `bash scripts/development-workflow/changelog-fragments.sh validate`;
   `npx markdownlint-cli2` on the new and edited Markdown files;
   `python3 scripts/lint/markdown-heuristic-lint.py` on the same files;
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`;
   `shellcheck --severity=warning` on the new suite;
   `./scripts/development-workflow/select-test-suites.sh --changed-files -`
   fed the changed paths, confirming the new suite is selected.
10. Execute the smoke runbook and record results in the PR.
