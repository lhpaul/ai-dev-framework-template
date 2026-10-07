# Preserve Local Template Patches During Sync — Implementation Plan

**Spec**: [Approved spec](1_1875-sync-template-three-way-merge_specs.md)
**Smoke test runbook**: [Runbook](../../../testing/workflow/1875-sync-template-three-way-merge.smoke-test.md)

## Summary

**Approach**: Add a Python standard-library preview/apply helper to the existing
sync protocol. It resolves committed incoming files, compares exact per-path
baselines with consumer content, and prepares safe results before any writes.
Canonical and mirrored entrypoints consume that result through their existing
approval and PR flows.

**Estimated complexity**: L — preserving content, modes, symlinks and history
requires transaction and migration behavior as well as protocol integration.
**Dependencies**: None beyond the repository's existing Git and Python toolchain.
**Template-fit check**: Passed; this changes framework tooling independently of
a consumer's application stack. No framework-specific provider is introduced.

## Verification Log

All repository observations below were gathered at
`46d378846189246f96a6d0606a5aa53e6b34c5eb` on 2026-10-07 UTC. Reproduce
searches against that revision with `git show` or a detached read-only checkout.
The source-of-truth scope is selected committed paths, not a frozen file count.

| Check | Command / query | Result |
| --- | --- | --- |
| Overwrite consumers | `rg -n 'Copy/overwrite all|Comparison method:|Category 1' .claude/commands/sync-template.md .cursor/commands/sync-template.md .claude/skills/sync-template.md` | Command, Cursor command and Claude skill contain the comparison/apply instructions requiring replacement |
| Codex routing | `rg -n 'canonical|always-sync|last_synced_version' .codex/skills/workflow-sync-template/SKILL.md .agents/skills/sync-template/SKILL.md` | Canonical Codex wrapper routes to the command; command-style alias routes to the canonical skill |
| Discovery symlinks | `git ls-tree -r HEAD .agents/skills/` | Discovery includes mode `120000` aliases; treating every incoming object as a regular file would break consumers |
| Existing selection | `rg -n 'ROLE_SCOPE_SELECTION|def parse_manifest' scripts/development-workflow/select-sync-manifest-entries.py` | Role selection and manifest parsing are available for reuse |
| Exact exclusions | `rg -n 'def entry_matches|Exact project_specific|owned_entries' scripts/development-workflow/check-sync-manifest-coverage.py` | Matcher and cross-scope project-owned precedence are available |
| Existing sync metadata | `rg -n 'last_synced|template:' .ai-dev-workflow.yaml docs/workflow/development-workflow/README.md .claude/commands/sync-template.md` | Version provenance exists; exact per-path baseline handling must be added |
| Tests and CI routing | `rg -n 'covers:|BODIES=' scripts/development-workflow/tests/test-sync-template-apply-modes.sh scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`; `rg -n 'select-test-suites|naming convention' .github/workflows/workflow-tests.yml` | Shell suites map changed surfaces through covers headers; add a discovered shell launcher for the Python integration tests |
| Design assets | `rg --files docs/specs/developments/20261007012151_1875-sync-template-three-way-merge`; inspect issue #1875 body | No supplied design assets; smoke tests need no visual-fidelity baseline |

### Factual claim evidence and scoped obligations

Rule 1 does not fire: helper decisions use our structured manifest/state formats,
Git object metadata and exit codes, without parsing third-party free-text logs.
For the merge exit-code contract see [official Git documentation](https://git-scm.com/docs/git-merge-file).
Inspection on 2026-10-07 confirmed stdout-only `-p`, clean exit zero and positive
conflict counts; non-clean results never become applied content.

Rule 3 does not fire: this plan states no measured quantity of existing artifacts.
The file lists below are change scope, and test scenarios describe coverage intent.
Rules 2, 4 and 5 use the single contracts below and the reproducible searches above.

Rule 6 obligations: the baseline requirement governs each selected differing or
missing consumer path and is discharged during preview; equality is its explicit
safe exception. Freshness governs the complete approved batch at apply entry.
Transaction rollback governs handled apply/validation errors, before success is
reported. Role selection governs enumeration, before classification. Existing
hard-stop approvals govern their categories at the canonical Step 4 sites.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner / base | Current repository, `develop` | Successful bounded prelude; `.ai-dev-workflow.yaml` | 2026-10-07, revision in Verification Log | #1875 invocation and merged spec PR #1904 only | Verified |
| Consumer role / approved paths | Resolve on each consumer invocation | Existing manifest selector and canonical role-resolution instructions | Same observation | This sync surface; no environment or portfolio-wide assumption | Verified |

No competing deployment environment or same-surface PR dependency is claimed.

## Parser-Risk Classification and Edge Cases

**Applies**: the helper parses structured JSON state and Git tree records in a
tooling path. Reuse the scoped manifest parser rather than implementing YAML.
There are no suppression directives.

| Input class | Required behavior | Automated mapping |
| --- | --- | --- |
| Missing or malformed state; unknown schema; duplicate JSON keys | Missing state uses legacy policy; corrupt/unsupported state stops with a named reason | New `test_sync_template_merge.py` state cases |
| SHA, blob and mode disagreement; unavailable commit | Reject invalid or unverifiable baseline, without guessing from version | Baseline provenance cases |
| Quoted/commented manifest scalars, invalid mode scope | Existing parser behavior retained; parse failures stop | Existing selector suite plus helper composition case |
| Paths with spaces/non-ASCII; path escape/absolute path; symlink ancestor | Preserve safe Git paths; reject unsafe destinations before writes | Path boundary cases |
| Incoming untracked/staged changes | Ignore working-tree/index bytes; read pinned committed objects | Committed-tree selection case |
| Embedded fallback selection | Explicit JSON selected/excluded paths from fallback; same role and path validation as manifest selection | Fallback and exclusion cases |
| Binary data, file/type collision, symlink target changes | Apply only atomic equality-based decisions; incompatible changes stop | Non-text/type cases |
| Stale/tampered preview, consumer mode or state changed | Rebuild and compare the entire approved plan before writes | Freshness cases |

**Concurrent-event-source**: Not applicable; this is a synchronous CLI without
listeners, timers or shared async callbacks. Apply uses an exclusive consumer
lock so cooperating sync invocations cannot overlap; unrelated external edits
are covered by freshness checks. A leftover lock is a named stop, never auto-cleared.
**Cross-cutting checklist**: Not applicable; no new general development/review
checklist is introduced.

## Layer-by-Layer Changes

### Shared tooling: selection and baseline state (AC4–AC6, AC9)

- Add `scripts/development-workflow/sync-template-merge.py` with `preview` and
  `apply` commands. Required invocation inputs identify the template checkout,
  consumer root, resolved role, normalized template identity and pinned incoming
  commit. Preview writes its result only into caller-supplied private scratch.
- Read `sync-manifest.yaml` from the incoming commit; reuse selector roles and
  matcher semantics, including exact project-specific exclusions across scopes.
  For an absent manifest, accept a protocol-produced JSON selection file derived
  from the embedded fallback; bind its complete content to the preview. Do not
  invent category membership. Explicit declined paths are subtracted before
  preview and listed separately; changing them requires new approval.
- Enumerate with `git ls-tree -r -z` and read blobs from the pinned commit. Never
  enumerate source caches, unstaged files or staged-but-uncommitted additions.
  Include recorded baseline paths still matching selection when absent upstream
  so upstream removals cannot disappear silently from comparison.
- Use consumer-owned `.ai-dev-workflow.sync-state.json`, schema version 1. Record
  template identity plus each actually synchronized path's exact commit, source
  (`template` or verified `consumer` bootstrap), blob and Git mode. Store no
  credentials, machine paths or consumer-patched bytes as baseline content.
  Exclude this exact state path as project-owned in `sync-manifest.yaml`.
- Resolve each recorded base from the appropriate Git object database and verify
  mode/blob against that commit's tree. An unavailable object is a named stop;
  the protocol may fetch exact recorded upstream commits into its temporary
  source checkout before preview. It must not mutate a user's source checkout.
- Without a ledger, an explicit maintainer-verified prior-sync or bootstrap SHA
  may seed history via `--base-ref` and `--base-source`. A version string or
  similarity is insufficient. Once a ledger exists, missing entries remain
  unknown: never fill them from the latest global commit. Malformed ledger is
  not equivalent to absent ledger. An explicit verified base may cover previously
  unknown paths, without replacing trustworthy recorded per-path evidence.

### Shared tooling: classifier and transaction (AC1–AC3, AC7, AC8, AC10)

This is the normative classifier contract; summaries and tests refer here.
Equality includes bytes, Git kind and executable bit. Preserve other consumer
regular-file permission bits when writing an existing file.

| Ordered gate | Result |
| --- | --- |
| Unsupported/unreadable evidence or unsafe path | Named blocking disposition |
| Consumer equals incoming | No content change; synchronize baseline after success |
| Base unknown, consumer differs or missing | Baseline unavailable; batch blocks |
| Verified base absent, consumer absent | Add incoming |
| Base present, consumer deleted | Retain deletion if incoming equals base; otherwise conflict |
| Consumer equals base | Direct update; upstream removal needs the existing named deletion approval outside this helper |
| Incoming equals base | Retain local change |
| Both changed regular text files | `git merge-file -p` on private ours/base/theirs; zero yields clean merged content; any other result blocks |
| Remaining incompatible additions, types, binary changes or links | Conflict; no chosen side |

- Merge the executable bit by the same three-way equality rules independently
  of text. A content merge does not discard an independent local mode change.
- Symlinks are atomic link-target bytes, not files to dereference or text-merge.
  Allow relative targets whose normalized final destination stays inside the
  consumer root. Validate the post-apply graph, including directories implied
  by planned children, retained local links and existing unselected targets.
  Reject dangling links, cycles, path escape and ancestor-link write traversal.
  Materialized legacy directories cannot be silently replaced by a link.
- Print dispositions and counts from one machine-readable result. Step 3 shows
  **Locally modified template files**, with clean merges, retained changes,
  deletions, conflicts and baseline-unavailable paths. Unknown history is not
  claimed as proven local modification. All counts reconcile with selected paths.
- Apply consumes the preview, re-computes selection, evidence, fingerprints and
  prepared outputs, and compares them before mutation. Include content, kind,
  permissions, baseline-state bytes, manifest/selection, identity and source
  commit. Reject tampering, moved source HEAD or any stale approved input.
- Any blocking selected path stops the complete batch, including metadata. No
  approval mode or side-selection flag overrides this. Conflict output remains
  private scratch; never write conflict markers into consumer files.
- Prepare backups/results and exclusive lock before writes. On a handled write
  or validation failure restore content, modes, links, prior ledger and created
  paths; retain recovery material and stop if restoration fails. Advance ledger
  only after the data transaction validates; clean equality paths advance too,
  declined paths retain prior evidence. External process kill is not reported as
  success; retained lock/recovery material prevents an unattended retry.
- The apply transaction is the successful-sync boundary for baseline evidence.
  A later commit/PR/CI failure does not falsify which content was applied; the
  existing workflow handles that failure without silently replaying the batch.

### Protocol and entrypoint consumers (AC9, AC10)

The Verification Log identifies the composed entrypoints. Implement the shared
contract above in these consumers, preserving their respective front matter:

| Consumer | Required integration outcome |
| --- | --- |
| `.claude/commands/sync-template.md` | Canonical preview, Step 3 dispositions, Step 4 helper apply, state staging and reviewer-gate checks |
| `.cursor/commands/sync-template.md` | Same contract and approvals as canonical command |
| `.claude/skills/sync-template.md` | Same contract and approvals as canonical command |
| `.codex/skills/workflow-sync-template/SKILL.md` | Require shared helper and state-aware canonical flow; linked `.agents/skills/workflow-sync-template` receives the same content |
| `.agents/skills/sync-template/SKILL.md` | Keep routing to canonical skill; change only if residual search finds conflicting wording |

Do not execute Claude while implementing or validating these text surfaces.
Replace old superset/diff and blind copy instructions; add source-object
preparation and explicit bootstrap-evidence guidance. Keep special-handling,
rename, placeholder, primary mode, PR and CI behavior intact. If selected
conflicts are declined, produce a new preview before applying the remaining set.
Step 5 stages the ledger and records optional `template.last_synced_commit` as
batch provenance alongside the existing version; it never substitutes for a
per-path baseline. Capture prior version before changing metadata as today.

## Testing Strategy

**Types**: Python integration tests with temporary Git repositories, a discovered
shell launcher, existing sync protocol suites, and the smoke runbook.
**Coverage intent**: Exercise preservation, failure atomicity, provenance and
composed entrypoints. Scenarios are indicative; equivalent coverage may replace
individual fixtures. Avoid testing only internal implementation structure.

- Direct update and independent edits; repeated sync retains a consumer patch
  using the new upstream baseline; declined paths keep their earlier base.
- Same-line conflicts and unknown-history differing/missing paths block all
  writes; verified template/bootstrap evidence permits safe additions/merges.
- Local-only change/deletion, upstream deletion, exact equality and consumer-only
  files; mode-only changes, binary data and symlink aliases follow the classifier.
- All repository roles, exact project-owned exclusions and fallback composition;
  source caches and staged changes never enter the batch.
- Stale consumer/source/state/selection, invalid metadata and preview tampering;
  apply/validation failure restores the batch and baseline state.
- Real template aliases validate against the planned committed tree; protocol
  parity retains existing approval modes and reviewer/CI instructions.

The launcher `test-sync-template-merge.sh` carries covers headers for the helper,
Python test file and modified sync surfaces so change-scoped CI selects it.
Demonstrate planted-violation failures and corrected passes at concrete fixture
paths/lines for newly introduced safety controls; retain redacted proof evidence
in the implementation PR. This template has a placeholder E2E job, so no product
E2E seed obligation is introduced. Run selected affected existing suites too.

## Seed Data

Tests create deterministic local Git histories for template baseline/incoming and
consumer/bootstrap, using synthetic text without account data. Fixtures include
independent and overlapping edits, role-scoped paths and relative skill aliases.
No production data or live consumer repository is modified.

## Documentation Updates

- `.ai-dev-workflow.yaml` — optional batch commit provenance field and distinction
  from per-path state, without changing machine-local override files.
- `docs/workflow/development-workflow/README.md` — state, safe legacy/bootstrap
  behavior, preview stops and successful-apply boundary.
- `scripts/README.md` — helper CLI and failure/recovery semantics.
- `sync-manifest.yaml` — consumer-owned state exclusion.
- Entry-point surfaces are listed in their normative consumer table above.

Project setup placeholders and general AGENTS/review checklists need no changes.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Wrong historical base drops a patch | Medium | High | Verified exact provenance and no-base stop |
| Source filesystem ships caches/secrets | Medium | High | Committed-tree enumeration and no local config selection |
| Partial apply falsely advances history | Medium | High | Preparation, rollback and state-last commit |
| Legacy symlink/materialized-directory mismatch | Medium | High | Atomic link semantics and explicit blocker |
| Text-only comparison loses permissions | Medium | Medium | Kind/mode-aware classifier and tests |
| Mirror retains overwrite instructions | Medium | High | Residual search and composed-surface tests |

## Implementation Order

1. Implement selection, baseline/state validation and the read-only preview.
2. Implement classifier, safe link graph and transactional apply.
3. Add behavioral tests and planted-violation proof cases; run them before wiring.
4. Integrate the entrypoint consumer table and Documentation Updates.
5. Add `changelog.d/1875.added.sync-template-three-way-merge.md` using the existing
   bold-title release-note format.
6. Execute the smoke runbook and affected suites, plus diff and shell guidance
   lint. Before readiness, search the entrypoint scope for `Copy/overwrite`,
   superset heuristics and filesystem enumeration; explain every residual match.
   Record actual selected committed paths/modes and per-role exclusions from the
   helper as residual verification evidence, including real shipped aliases.
7. Complete sequential internal compliance/quality reviews, automated reviewer
   loop and CI loop. Bind readiness and delegated merge evidence to current head.

## Matrix Coherence Preflight

Passed: classifier inputs use the spec's precedence; unknown-base and unsafe
paths cannot reach an apply outcome; deletion specializes local change before
merge; batch freshness/approval precede writes; file disposition counts derive
from the result; all entrypoints consume the same normative contract. No open
architecture decisions or deferred acceptance criteria remain.
