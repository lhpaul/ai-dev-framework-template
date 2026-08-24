# Changelog Fragments — Implementation Plan

**Spec**: [1_1554-changelog-fragments_specs.md](1_1554-changelog-fragments_specs.md)
**Smoke test runbook**: [1554-changelog-fragments.smoke-test.md](../../../testing/workflow/1554-changelog-fragments.smoke-test.md)
**Work item**: #1554 (Type: Refactor, Priority: High)

---

## Summary

**Approach**: Give every work item its own release-note file under a new
`changelog.d/` directory, named `<item>.<kind>.<slug>.md`, whose body is the
finished changelog bullet. Because the first field is the tracker identifier,
two different items always write different paths, and git does not conflict
across different paths — the collision is removed by construction rather than
resolved more cleverly. A new helper,
`scripts/development-workflow/changelog-fragments.sh`, gathers the pending
notes at release time into a draft `## [X.Y.Z]` section in `CHANGELOG.md`
(`assemble`) and removes them in a separate, later step (`consume`), so an
interrupted release loses neither notes nor the releaser's edits. Assembly also
carries whatever is still sitting in the shared `## [Unreleased]` block into
the same version section, which is what makes the transition release work
without a migration and without a one-release-only code path. Every readiness
check, protocol, agent surface, and lint that today asserts "this PR touched
`CHANGELOG.md`" is updated to accept a fragment instead.

**Estimated complexity**: L

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: One new shell helper with a strict filename grammar and a
CHANGELOG rewriter, one new test suite, and a wide but shallow sweep across
protocol, agent, skill, lint, workflow, and manifest surfaces. The sweep is
what makes this large: the changelog convention is stated in many places, and
leaving any one of them saying "edit `[Unreleased]`" reintroduces the conflict
for whichever agent reads that surface.

**Dependencies**: None blocking. #1537 (change-scoped CI suite selection) is
already merged at the plan-time revision, so the new suite
`test-changelog-fragments.sh` is selected by CI automatically — the handoff
comment's concern that most affected scripts are unrun in CI does not apply to
the new code this plan adds.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `19c0f46e` (equals `origin/develop`) |
| Files referencing the changelog | Repository-wide case-insensitive scan for `changelog`, excluding `.git`, `node_modules`, worktree directories, `docs/specs/`, `hooks/node_modules`, and `CHANGELOG.md` itself | 107 files; the ones this plan changes are enumerated in **Layer-by-Layer Changes**, and the ones deliberately left alone are enumerated in **Verified, no change needed** |
| Cross-cutting agent/skill search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/` | `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md` |
| Codex skill mirroring | `ls -la .agents/skills/` | `.agents/skills/workflow-*`, `batch-merge`, and `post-merge-cleanup` are symlinks into `.codex/skills/`; `.agents/skills/prepare-release/` is a real directory and needs its own edit |
| Bullets pending in the shared block | Count of top-level `- ` bullets between `## [Unreleased]` and the next `## [` heading in `CHANGELOG.md` | 56 |
| Category headers in the shared block | Headings between `## [Unreleased]` and the next `## [` heading | `### Added`, `### Fixed`, `### Changed` |
| Readiness assertion on `CHANGELOG.md` | `grep -n "CHANGELOG presence" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Step 5.1 artifact table, one row; pass condition is `[.files[].path] \| any(. == "CHANGELOG.md")` for `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` |
| `PR_HAS_CHANGELOG` semantics | Read `fetch_pr_meta` and `cmd_discover` in `scripts/development-workflow/batch-merge.sh` | It is a **merge-ordering** signal (non-CHANGELOG PRs merge first), not a readiness gate. The issue body's description of it as an assertion is inaccurate; this plan does not change its meaning |
| Release scope parser | Read `append_issues_from_changelog` in `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | Extracts `#N` tokens from the published `## [X.Y.Z]` section. Requires no change **provided** assembled bullets keep the `(#N)` reference, which the fragment body convention mandates |
| Hotfix tagging path | Read `.github/workflows/auto-tag-release.yml` | Reads only `CHANGELOG.md` version sections; the hotfix path writes those directly and is untouched by this plan |
| Haystack rule identifier | `grep -n "changelog" .haystack/pr-rules.yml` and the comment block in `scripts/development-workflow/haystack-reviewer.sh` | The live rule id is `keep-single-unreleased-changelog-section`; the script's comment names `keep-changelog-unreleased-structure-canonical`, which does not exist in the rules file. Pre-existing drift, observed but not yet corrected — the fix is scheduled for Implementation Order Step 10 and is out of scope for this plan-writing PR |
| Documentation-stage allowlist | Read `path_allowed_for_stage` in `scripts/development-workflow/check-documentation-stage-alignment.sh` | `spec/*` and `implementation-plan/*` allow only their own stage artifacts, so a fragment on a documentation-stage branch is correctly reported as unexpected. No change needed |
| CI suite selection | Read the `# covers:` convention in `scripts/development-workflow/select-test-suites.sh` | A suite named `test-changelog-fragments.sh` covers `changelog-fragments.sh` by naming convention with no workflow edit |
| Sync manifest precedence | Read the precedence paragraph in `sync-manifest.yaml` | Only "project-specific exact path beats always-sync directory glob" is defined. The reverse is undefined, so this plan lists **only** `changelog.d/README.md` and leaves downstream fragment files unlisted (the manifest header already states unlisted files are never synced) |
| Same-surface open PRs | `gh pr list --state open` then `gh pr diff --name-only` for each | #1589 (`fix/1525-integration-branch-ci`) and #1592 (`fix/1579-coderabbit-rate-limit-window`). Both add `[Unreleased]` bullets; neither changes the changelog convention. #1589 also edits `.github/workflows/markdown-lint.yml` (branch filters) and `05b-graduate-development-protocol.md` (a new section at the top), in regions disjoint from this plan's edits |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Repository mode and artifact owner | `single_repo` (no `mode` key present), so this repository owns both the plan and the implementation | `.ai-dev-workflow.yaml` | 2026-08-24, repo `19c0f46e` | Current invocation is item #1554 only; no open PR changes `.ai-dev-workflow.yaml` | `Verified` |
| Approved artifact base branch | `develop` | Protocol 02 Step 5 plus the tracker handoff for #1554 | 2026-08-24, repo `19c0f46e` | `gh pr list --state open`: #1589 and #1592, both based on `develop` | `Verified` |
| The shared `[Unreleased]` block is **not** migrated and is released from where it is, once | 56 bullets remain in `CHANGELOG.md` under `## [Unreleased]` | Spec "Out of Scope"; alignment decision recorded in PR #1555's description | 2026-08-24, repo `19c0f46e` | Open PRs #1589 and #1592 each add one more bullet to that block; both are additive and consistent with "released from where it is" | `Verified` — the transition design reads the block at assembly time rather than at plan time, so its exact size when the transition release is cut is irrelevant |
| `template.is_template` is `true`, so the convention ships to downstream consumers | `true` | `.ai-dev-workflow.yaml` | 2026-08-24, repo `19c0f46e` | No open PR changes `sync-manifest.yaml` or `template.is_template` | `Verified` |

Shared keywords are not treated as conflict evidence: #1589 and #1592 add
changelog **entries**, which is the behaviour this plan changes, but neither
changes the changelog **convention**, which is the operational surface. The
file-level overlap with #1589 is recorded in **Risks & Mitigations** instead,
where it belongs.

---

## Design Decisions

Each decision below is referenced by index from the Layer-by-Layer changes and
the Implementation Order. The indices are stable within this document.

### Decision 1 — Fragment location and filename grammar

**Chosen**: `changelog.d/<item>.<kind>.<slug>.md`, exactly three dot-separated
fields before the `.md` extension, with dots forbidden inside every field.

```text
changelog.d/1554.changed.per-item-release-notes.md
changelog.d/1589.fixed.integration-branch-ci.md
changelog.d/ENG-42.added.export-button.md
```

- `<item>` is the bare tracker identifier for the work item, exactly as it
  appears in the branch name (`1554`, `ENG-42`) and never with a `#`.
- `<kind>` is one of `added`, `changed`, `deprecated`, `removed`, `fixed`,
  `security` — lowercase.
- `<slug>` is a short kebab-case description chosen by the author.

**Why collisions are impossible, not merely unlikely**: the discriminator is an
externally allocated unique identifier, not a date, a hash, or a free-text
string. The tracker assigns each work item exactly one identifier, and
`run-nested-artifact-guard.sh` already refuses a second in-flight artifact
branch for the same issue, so at most one branch is authoring notes for a given
`<item>` at a time. Two **different** items therefore differ in the first field
and write different paths, and git produces a conflict only when both sides
modify the same path. The name contains no date at all, which is the direct
answer to the spec's "two items completed on the same day must never be able to
claim the same file": the day is not part of the identity, so it cannot be
shared.

Two notes from the **same** item (for example one `added` and one `fixed`) live
on one branch, where the author sees both files; that is an ordinary
same-branch edit, not a cross-branch merge.

**Named exception — an explicitly approved split.** The guard's
`--allow-split true` path (Protocol 03) exists precisely to let two branches
carry the same tracker identifier at once, on explicit parent-run approval.
In that documented case two split branches could each write a fragment for
the same `<item>`, and if both authors independently choose the same
`<kind>.<slug>` the paths collide — this is the one case where "impossible"
is not literal. It surfaces as an ordinary same-path git conflict, which
Decision 6 already classifies as non-trivial and routes to human resolution
rather than auto-combining, so no note is silently lost or merged
incorrectly; only the "cannot happen at all" framing is narrowed to "cannot
happen outside an explicitly human-approved split, and is safely caught as a
conflict if it does."

Repositories with no issue tracker fall back to the branch slug as `<item>`.
Uniqueness then rests on branch-name uniqueness, which git already enforces for
concurrently existing branches.

**Corollary that must not be violated**: `changelog.d/` carries no index,
ordering file, or aggregate manifest that every item edits. Any such file would
be a shared path and would recreate exactly the conflict this item removes. The
per-release manifest introduced by Decision 3 is written only by the releaser,
on the release branch, and is never touched by item branches.

### Decision 2 — Change-kind encoding

**Chosen**: encode the kind as the second filename field. **Rejected**: YAML
front matter or a `Kind:` header line inside the file.

- The readiness checks that must accept a fragment (Decision 5) all operate on
  a PR's changed-file list — `gh pr view --json files`, `gh pr diff
  --name-only`. A kind in the filename means readiness is decidable from the
  file list alone, with zero file reads and zero additional API calls.
- A filename field cannot drift from the file's content, because there is no
  second copy of the kind to disagree with.
- Front matter adds a second parser on a path that must not fail at release
  time, and introduces malformed-YAML and missing-delimiter failure modes for
  no gain — assembly must read the body anyway, but reading a body verbatim is
  strictly simpler than parsing it.
- A directory per kind (`changelog.d/fixed/1554-...`) was also rejected: it
  adds six directories, complicates the scan, and encodes exactly the same
  information as a filename field.

**Dot as the separator, not hyphen**: hyphens appear inside both tracker
identifiers (`ENG-42`) and slugs (`per-item-release-notes`), so a
hyphen-separated grammar is ambiguous and, worse, silently mis-parses
`1554.fixed.fixed-typo`-style names. Dots appear in neither field, so a strict
four-way split on `.` is unambiguous for every legal name and rejects every
illegal one.

### Decision 3 — Consumption semantics: how "assembled but not yet published" is represented

The state is represented by **two artifacts that exist together only between
assembly and publication**, both living on the release branch, **written in a
fixed order so an interruption between them lands on a detected, named state
rather than an ambiguous one**:

1. A release manifest at `changelog.d/manifests/v<X.Y.Z>.txt`, naming exactly
   the fragment files that will feed the draft, one repository-relative path
   per line, preceded by a single comment line recording the assembly
   timestamp, the fragment count, and the count of bullets carried over from
   the shared block. **Written first**, via a temp file plus atomic rename,
   so its existence durably commits to one specific fragment set before
   `CHANGELOG.md` is touched.
2. The draft `## [X.Y.Z] - YYYY-MM-DD` section written into `CHANGELOG.md`,
   built from exactly the fragment set already recorded in the manifest —
   never a fresh directory scan. **Written second**, and with the same
   atomicity guarantee as the manifest: the full new file content is written
   to a temp file in the same directory, flushed and `fsync`'d, then renamed
   over `CHANGELOG.md` in one `rename(2)` call. A process stop during this
   step therefore never produces a truncated or partially-rewritten
   `CHANGELOG.md` — on disk, the file is always either byte-for-byte the
   pre-assembly content or byte-for-byte the fully assembled content, with no
   third possibility. This is what makes the four states below exhaustive:
   without it, a stop mid-rewrite would leave a *fifth*, undetectable state (a
   corrupt file) that none of them names.

Fragment files themselves are **not touched by assembly**. This is the literal
requirement from the spec ("Assembling a draft never destroys anything") and
from the tracker handoff, which records that the first spec draft left the
interrupted case undefined and that any design where assembly destroys or moves
fragments violates the corrected clause.

- **The set is fixed at assembly.** Once the manifest is written, it — not a
  fresh directory scan — is the authority for what this release contains. A
  fragment added afterwards (on `develop`, or cherry-picked onto the release
  branch as part of a late fix) is absent from the manifest and is therefore
  not in this release. It stays in `changelog.d/` and is picked up by the next
  assembly.
- **Assembly's four states are each named, and none is inferred.** `assemble`
  checks the manifest for the target version and the `## [X.Y.Z]` heading
  independently:
  - Manifest present, heading present: `ASSEMBLE_RESULT=already_assembled`,
    exit 0, no write. The normal resume path.
  - Manifest present, heading absent: the run was interrupted between the two
    writes — and, because the `CHANGELOG.md` write is itself atomic (point 2
    above), `CHANGELOG.md` on disk is guaranteed to still be exactly its
    pre-assembly content, never a partial rewrite. `assemble` performs the
    `CHANGELOG.md` write (temp file, `fsync`, atomic rename) from the
    already-frozen manifest, not a rescan, then reports
    `ASSEMBLE_RESULT=assembled`, exit 0. Because the set was fixed before the
    interruption, this is safe even if new fragments landed on `develop`
    afterward — "the set is fixed at assembly" still holds.
  - Manifest absent, heading present: the manifest was lost by something other
    than `consume` (which moves it — see below — rather than deleting it),
    since assembly never reaches the `CHANGELOG.md` write before the manifest
    is committed. `assemble` reports `ASSEMBLE_RESULT=assembled_unmanifested`,
    a non-zero exit. **The remediation is `assemble --repair-manifest`, never
    a live directory rescan.** A rescan is explicitly wrong here: the spec
    guarantees a note recorded after assembly belongs to the next release,
    never retroactively to the one being prepared, and a fragment can
    legitimately have landed in `changelog.d/` between the original assembly
    and the manifest's loss (a late fix cherry-picked onto the release branch,
    for instance). Recomputing "the current set" would silently pull that
    fragment into an already-published-looking section. `--repair-manifest`
    instead restores the manifest from the one source that reflects the set
    **as it was at assembly time**: git history. It walks the current
    branch's log for `changelog.d/manifests/v<X.Y.Z>.txt` and selects the
    **most recent** commit that wrote that exact path — the path can
    legitimately be written more than once (an earlier `--repair-manifest`, or
    an explicit `--reassemble`, both write it again), and the most recent
    write is always the one that reflects the currently-authoritative content,
    never an earlier one. If such a commit exists, it restores that commit's
    blob verbatim (`git show <commit>:<path>`), through the same temp-file,
    `fsync`, atomic-rename discipline as every other write in this plan — a
    stop mid-restore therefore lands on the still-absent manifest (safe to
    retry), never a half-written one, which is what keeps this recovery path
    from reopening the "fifth, undetectable corrupt state" the atomic-rename
    discipline exists to rule out. On success it reports
    `ASSEMBLE_RESULT=repaired`, exit 0. Before concluding no commit exists,
    `--repair-manifest` checks `git rev-parse --is-shallow-repository`: a
    shallow clone truncates the log before it reaches a commit that exists but
    is outside the fetched depth, which is a clone-configuration problem, not
    a data-loss one. In that case it reports a distinct
    `ASSEMBLE_RESULT=history_truncated`, exit 1, naming `git fetch
    --unshallow` as the remediation, rather than `manifest_unrecoverable`,
    which would wrongly imply the data itself is gone. Only on a full clone,
    with no commit ever having written that path (the manifest was lost before
    it was committed), does `--repair-manifest` **refuse to guess**: it
    reports `ASSEMBLE_RESULT=manifest_unrecoverable`, exit 1, and instructs
    the operator to reconcile by hand — compare the `## [X.Y.Z]` section's
    bullets against the fragment bodies still present in `changelog.d/` to
    reconstruct the original set, or, only as a knowing last resort whose risk
    the operator accepts explicitly, fall back to `assemble --reassemble` (see
    below), which is never invoked automatically. `--reassemble` recomputes
    and writes the manifest and rewrites `CHANGELOG.md` in the identical
    manifest-first, atomic-rename order as a normal `assemble`, so a stop
    mid-`--reassemble` also lands on one of the named states above rather than
    a sixth, undocumented one.
  - Manifest absent, heading absent: nothing has happened yet; `assemble` runs
    normally.
- **Interrupted preparation resumes intact — because Protocol 05 commits
  twice inside Step 3, not only once at Step 5.** "Both artifacts are
  ordinary committed files on the release branch" is true only if something
  commits them, and Protocol 05's existing single "Commit" step (Step 5) runs
  *after* Step 3's assemble, editorial pass, link-reference definitions, and
  `consume` have all already happened. Left at that, the manifest and the
  editorial pass would sit uncommitted for the entire span this design exists
  to protect, and `--repair-manifest`'s git-history restore would find
  nothing to restore for the whole of that span. The Layer-by-Layer Changes
  entry restructuring Protocol 05 Step 3 therefore adds two commits inside it,
  both before Step 5's version-bump commit: one immediately after `assemble` succeeds
  (before the editorial pass touches anything), and one after the editorial
  pass and link-reference definitions, immediately before `consume` runs.
  With those in place, resuming on the *same* working tree needs no git
  operation at all — the temp+rename writes already persisted to disk — and
  resuming on a *different* clone, or after the original working tree is
  lost, is `git checkout` of the release branch followed by re-running
  `assemble`, which lands on one of the four states above because the
  manifest and the editorial pass are both already committed. If the release
  branch is discarded entirely, `develop` still holds every fragment, because
  nothing was ever deleted there — but the releaser's editorial pass is not
  on `develop`, and is genuinely lost in that specific scenario; only a
  discarded *working tree*, not a discarded *branch*, is protected by the two
  intermediate commits.
- **Consumption requires a publishable section, not just a manifest.** Before
  deleting anything, `consume` checks the manifest **and** the `## [X.Y.Z]`
  heading — the same two facts `assemble` checks, in the same order of
  concern. A manifest can exist while the heading does not: that is exactly
  the "manifest present, heading absent" interrupted-assembly state above,
  and it means assembly never finished writing the section. If `consume` ran
  anyway, it would delete the source fragments and move the manifest with no
  version section to show for them — the release's notes would be gone with
  nothing published, which is precisely the "no unreleased note may be
  silently left behind" failure the spec forbids. So: manifest present,
  heading absent → `CONSUME_RESULT=not_assembled`, non-zero exit, deletes
  nothing, and names the remediation: run `assemble` first (which completes
  the interrupted write and lands on `already_assembled`, at which point
  `consume` is safe).
- **Consumption happens at publication, and its idempotence marker is a
  positive fact, not an absence.** Once the section-exists precondition
  passes, `consume` deletes the fragment files named in the manifest one at a
  time, then **moves** — never deletes — the manifest itself to
  `changelog.d/manifests/consumed/v<X.Y.Z>.txt` via a single `rename(2)` call
  (both paths are on the same filesystem, under `changelog.d/`), so the move
  itself cannot be interrupted into a state where the manifest is absent from
  both locations — the "absent from both" state below can only result from
  something outside these two commands, never from `consume`'s own crash
  window. This both strengthens the spec's Audit Trail principle (a permanent
  record of what fed each published release) and removes the ambiguity a
  delete would otherwise reintroduce, as a commit on the release branch:
  - Heading present, manifest present in `changelog.d/manifests/`, every
    listed file present: normal `consumed` path.
  - Heading present, manifest present in `changelog.d/manifests/`, **some or
    all** listed files already absent: an interrupted consume — a prior run
    stopped after deleting some fragments but before moving the manifest.
    Per-file deletion is idempotent (skipping a file that is already gone is
    not an error), so resuming simply finishes deleting whatever remains and
    then performs the manifest move. This still reports
    `CONSUME_RESULT=consumed`, exit 0 — from the operator's point of view, the
    step that was interrupted just completes.
  - Manifest present in `changelog.d/manifests/consumed/`, absent from
    `changelog.d/manifests/`: `CONSUME_RESULT=already_consumed`, exit 0 —
    confirmed by the moved file's presence, not its absence.
  - Manifest absent from **both** locations, heading present: no longer
    conflated with `already_consumed`. Reports `CONSUME_RESULT=inconsistent`,
    non-zero exit, and instructs the operator to reconcile by hand — this is
    `assembled_unmanifested`'s sibling failure mode surfacing at `consume`
    time instead of `assemble` time (both manifest locations empty is not a
    state either command's normal flow produces), and it must fail loudly for
    the same reason.
  Those deletions and the manifest move reach `main` and `develop` only when
  the release PRs merge — which is what "published" means. An abandoned
  release deletes nothing anywhere that survives.
- **Re-assembly is possible but explicit, and is not a recovery mechanism.**
  `assemble --reassemble` recomputes the manifest from the current directory
  and replaces the existing version section. It prints the section it is
  about to replace before replacing it, because that section may contain the
  releaser's editorial pass. It is the only path that discards editorial
  edits, it is never invoked by protocol 05's normal flow, and — unlike
  `--repair-manifest` above — it is never invoked automatically by any
  recovery path, because a live rescan can pull in a fragment that arrived
  after the original assembly.
- **If a fragment is edited between assembly and consumption**, the draft in
  `CHANGELOG.md` wins: it is what the releaser reviewed. `consume` deletes the
  file regardless of its content.

### Decision 4 — The transition release

Assembly performs, in one operation:

1. Rename the existing `## [Unreleased]` heading to `## [X.Y.Z] - YYYY-MM-DD`,
   preserving every bullet already under it. This is exactly the rename the
   releaser performs by hand today.
2. Merge the manifest's fragment bullets into that same section, per kind:
   append to an existing `### Category` heading when one is present, and create
   the heading in canonical Keep a Changelog order (Added, Changed, Deprecated,
   Removed, Fixed, Security) when it is not.
3. Insert a fresh, empty `## [Unreleased]` heading above the new version
   section.

Each entry appears exactly once because the carried-over bullets are **moved**
with the heading rather than copied, and each fragment is emitted once from the
manifest. Appending into an existing `### Category` rather than creating a
second one is also what keeps `check-changelog-duplicate-headers.sh` passing on
the assembled output.

The transition is therefore not a special mode and leaves no dead code: after
it, `## [Unreleased]` is simply always empty, the rename produces an empty
section, and fragments fill it. The same behaviour is what lets a downstream
project that already has a populated shared block adopt fragments with no
migration step (Decision 7).

### Decision 5 — Readiness checks that must accept a fragment

The authoritative check is the **CHANGELOG presence** row of Protocol 90 Step
5.1's artifact table. It is the gate: a PR whose file list lacks the required
release-note artifact is redispatched rather than accepted as ready. The
pass condition is now **branch-specific** rather than a single OR across every
implementation branch type, and it matches only the strict top-level fragment
grammar (Decision 1) — not `changelog.d/README.md`, not anything under
`changelog.d/manifests/`, and not a malformed fragment name:

```text
# feature/*, fix/*, refactor/*: a valid fragment, matching the top-level
# grammar exactly (Decision 1's six kinds; no nested path)
[.files[].path] | any(test(
  "^changelog\\.d/[A-Za-z0-9][A-Za-z0-9_-]*\\.(added|changed|deprecated|removed|fixed|security)\\.[a-z0-9][a-z0-9-]*\\.md$"
))

# hotfix/*: unchanged — a versioned CHANGELOG.md section, never a fragment.
# A fragment-only hotfix/* PR does not satisfy this gate, because the hotfix
# path (Protocol 03 Path 4) still writes CHANGELOG.md directly (Decisions 4
# and 5's Step 5.1 table row)
[.files[].path] | any(. == "CHANGELOG.md")
```

The complete set of surfaces that today assert or instruct "a release note was
recorded", each of which must accept a fragment:

| Surface | What it asserts today | Change |
| --- | --- | --- |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 5.1 table | `CHANGELOG.md` in `files` for `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` | Split into two branch-specific conditions: `feature/*`, `fix/*`, `refactor/*` require a strict-grammar `changelog.d/` fragment (not `CHANGELOG.md`, and not README/manifest/malformed paths under `changelog.d/`); `hotfix/*` still requires `CHANGELOG.md` exclusively — a fragment does not satisfy the hotfix gate |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Four per-path "Update CHANGELOG" steps and two PR-body "CHANGELOG entry preview" bullets | Paths 1–3 write a fragment; Path 4 (hotfix) unchanged; previews renamed to "release note preview" |
| `REVIEW.md` (spec exemption, plan exemption, code-review checklist, reviewer-finding list) | Spec and plan branches must not touch `CHANGELOG.md`; code review flags a missing entry | Extend the exemptions to `changelog.d/`; restate the code-review item in terms of a release note |
| `LLM_RULES.md` | "Do not skip CHANGELOG updates for feature/fix PRs" | Restate as "record a release note"; point at the fragment convention |
| `.haystack/pr-rules.yml` rule `keep-single-unreleased-changelog-section` | Agents must not create duplicate `[Unreleased]` headers | Keep the rule (it still guards hotfix and release edits); retarget its message to those contexts |
| `scripts/development-workflow/haystack-reviewer.sh` comment block | Documents a `Rules violation` false positive, naming a rule id that does not exist in the rules file | Correct the rule id and rescope the guidance to hotfix/release edits |
| `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.cursor/rules/workflow.mdc`, `.cursor/commands/implement-development.md` | "Always update CHANGELOG before opening the PR", plus duplicate-header avoidance | Replace with the fragment instruction; the duplicate-header guidance is no longer reachable for item PRs |
| `AGENTS.md` (`CLAUDE.md` and `GEMINI.md` are symlinks to it) | "Feature and fix PRs add entries under `[Unreleased]`" | Restate; keep the hotfix exception verbatim |
| `docs/best-practices/2-version-control.md` | "Every PR must update `CHANGELOG.md` under `[Unreleased]`" plus the parallel-batch note | Restate as the fragment convention and make this file the canonical format reference |
| `scripts/development-workflow/batch-merge.sh` `PR_HAS_CHANGELOG` | Whether the diff touches `CHANGELOG.md`; drives merge **ordering** only | No semantic change — see Decision 6 |

### Decision 6 — What happens to Protocol 94 Step 4.3

**Chosen**: narrow and keep, rather than remove.

Fragments make a `CHANGELOG.md` conflict between two in-flight item PRs
impossible in this repository, but they do not make `CHANGELOG.md` conflicts
impossible in general:

- The hotfix path still writes versioned sections directly into `CHANGELOG.md`
  (spec Use Case 3), so two hotfixes in flight, or a hotfix racing a release,
  can still collide there.
- Release and backport PRs edit `CHANGELOG.md` by design.
- Downstream projects created from earlier template versions still use the
  shared block. The spec's Out of Scope explicitly declines to ship a migration
  tool for them, which means non-adopted consumers are an expected population,
  and Protocol 94 is synced to them.

Removal is therefore the higher-cost error: the failure mode is a downstream
batch merge hitting a `CHANGELOG.md` conflict with no documented resolution,
against a benefit of one dormant branch in a protocol. Concretely:

- Step 4.3's `CHANGELOG.md` auto-resolution procedure stays, with its trigger
  restated: expected for hotfix, release, backport, and not-yet-adopted
  repositories, rather than "every PR in a wave".
- A new `changelog.d/` clause is added: a conflict on a `changelog.d/` path is
  **never** auto-resolved. Identical paths on both sides mean the same item
  identifier was used twice, which is a real mistake, not a trivial collision.
  Classify as non-trivial and escalate.
- `PR_HAS_CHANGELOG` keeps its current meaning and name. It is emitted metadata
  that tests and callers depend on, it accurately describes the diff, and
  renaming an output contract field to make a documentation point would be a
  gratuitous break. Its header comment gains one sentence clarifying that it is
  an ordering signal, not a readiness gate.
- The batch-merge hold-annotation text, which currently tells a runner that a
  `CHANGELOG.md`-only conflict can be resolved at merge time, keeps that
  sentence and gains the `changelog.d/` clause.

### Decision 7 — Downstream template consumers

The acceptance criterion is that a project created from this template records
release notes the new way with no additional setup. Three things make that true:

1. **The directory ships.** `changelog.d/README.md` is committed in the
   template and documents the filename grammar and the six kinds. Its presence
   is also what makes the directory exist in a fresh clone, since git does not
   track empty directories.
2. **The tooling ships.** `scripts/development-workflow/` and `scripts/lint/`
   are already `always_sync` directory entries in `sync-manifest.yaml`, so
   `changelog-fragments.sh` and its test arrive with no manifest edit. The
   protocols and agent surfaces that instruct authors are likewise already
   covered by the `docs/workflow/`, `.claude/`, `.cursor/`, and `.codex/`
   entries.
3. **The manifest gains exactly one entry**: `changelog.d/README.md` as
   `always_sync`, `mode_scope: shared`. Downstream fragment files are
   deliberately **not** listed in any category. The manifest header already
   states that files absent from the manifest are not included in always-sync
   batches, so a project's own notes are never overwritten, and the template's
   own fragments are never pushed into a consumer.

The reason for leaving fragments unlisted rather than adding a
`project_specific` glob is recorded in the Verification Log: `sync-manifest.yaml`
defines precedence only for "project-specific exact path beats always-sync
directory glob". A `project_specific` glob for `changelog.d/` combined with an
`always_sync` exact path for its README would depend on the reverse precedence,
which is undefined. Relying on undefined manifest semantics for a
data-preservation property is not acceptable; being absent from the manifest is
unambiguous.

Finally, a downstream project that already has a populated `[Unreleased]` block
needs no migration: Decision 4's assembly carries that block into the version
section on the project's next release, exactly as it does for this repository's
transition release.

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

New helper — `scripts/development-workflow/changelog-fragments.sh`. Shell
contract: `bash` (it uses `set -euo pipefail`, arrays, and `local`, matching
every sibling in that directory). It emits `KEY=VALUE` lines on stdout like the
other workflow helpers, and every exit path prints its documented fields.

- [ ] `validate [--dir <path>]` — parse and check every fragment. Emits
      `VALIDATE_RESULT=clean|invalid`, `FRAGMENT_COUNT=<n>`, and one
      `INVALID_FRAGMENT=<path>: <reason>` per failure. (Spec AC-2, AC-9)
- [ ] `list [--json]` — report the pending notes without changing anything.
      Emits `PENDING_COUNT=<n>` and one `PENDING=<path>` per fragment.
      (Spec "Operational Visibility")
- [ ] `assemble --version <X.Y.Z> [--date <YYYY-MM-DD>] [--reassemble]
      [--repair-manifest] [--allow-empty]` — acquire the per-release `mkdir`
      lock (Concurrent-event-source addendum), write the manifest first (temp
      file, `fsync`, atomic rename) into `changelog.d/manifests/v<X.Y.Z>.txt`,
      then write `CHANGELOG.md` the same way (temp file, `fsync`, atomic
      rename) — rename `## [Unreleased]` to the version heading, merge
      fragment bullets per kind (from the manifest, not a rescan, when
      resuming), and insert a fresh empty `## [Unreleased]`. Emits
      `ASSEMBLE_RESULT`, `VERSION`, `FRAGMENT_COUNT`, `CARRIED_OVER_COUNT`,
      `MANIFEST_PATH`, and `ITEMS`. `ASSEMBLE_RESULT` includes
      `assembled_unmanifested` for the manifest-absent, heading-present
      recovery state; `repaired` when `--repair-manifest` restores the
      manifest from the most recent commit that wrote it, via the same
      atomic temp-file-and-rename write as every other write in this plan;
      `history_truncated` when `--repair-manifest` is run against a shallow
      clone whose fetched depth cannot rule out an existing-but-unreachable
      commit; `manifest_unrecoverable` when `--repair-manifest` finds no
      committed manifest to restore on a full clone; and `locked` when the
      lock is already held. `--reassemble` follows the identical
      manifest-first, atomic-rename write order as a normal assembly. (Spec
      AC-3, AC-5, AC-7, AC-10; Decisions 3 and 4)
- [ ] `consume --version <X.Y.Z>` — acquire the same per-release lock, require
      the `## [X.Y.Z]` heading to exist (else refuse — see below), delete the
      manifest-listed fragments one at a time (idempotent: a file already
      absent is not an error), then move (not delete) the manifest to
      `changelog.d/manifests/consumed/v<X.Y.Z>.txt`. Emits `CONSUME_RESULT`,
      `REMOVED_COUNT`, `MANIFEST_PATH`. `CONSUME_RESULT` includes
      `not_assembled` when the manifest exists but the heading does not (do
      not delete anything in this case); `inconsistent` when neither manifest
      location holds the target version but the heading is present; and
      `locked` when the lock is already held. (Spec AC-5, AC-7; Decision 3)
- [ ] Exit codes: `0` for `clean`, `assembled`, `already_assembled`,
      `reassembled`, `repaired`, `consumed`, `already_consumed`; `1` for a
      validation, assembly, `assembled_unmanifested`,
      `manifest_unrecoverable`, `history_truncated`, `not_assembled`,
      `inconsistent`, or `locked` error; `3` for `no_notes` without
      `--allow-empty`; `64` for a usage
      error, matching `check-documentation-stage-alignment.sh`.
- [ ] Reporting on assembly names each contributing item, and reports bullets
      carried over from the shared block as a single unattributed group, per
      the spec's Operational Visibility section.

New directory:

- [ ] `changelog.d/README.md` — the filename grammar, the six kinds, the body
      convention (a complete markdown bullet including the `**Bold Title**
      (#N):` prefix), and a worked example. It is excluded from the fragment
      scan by name.
- [ ] `changelog.d/manifests/.gitkeep` — so the manifest directory exists on a
      fresh clone even though manifests exist only during a release.
- [ ] `changelog.d/manifests/consumed/.gitkeep` — so the durable, post-publish
      manifest archive (Decision 3) exists on a fresh clone even before any
      release has been consumed.

### Infrastructure / Configuration

- [ ] `.github/workflows/markdown-lint.yml` — add `changelog.d/**` to the
      `paths:` filter. The file has **two independent file-discovery blocks**,
      not one: the `find` in the "Collect target markdown files" step, and a
      second, separately duplicated `find` inside the "Run heuristic lint
      checks" step; the `markdownlint-cli2` step uses its own literal glob
      list. Add `changelog.d/**` to all three (the two `find` commands and the
      `markdownlint-cli2` glob list) so fragments get both lint passes, not
      only `markdownlint-cli2`. Add a step running `changelog-fragments.sh
      validate` so a malformed fragment fails on the item's own PR rather than
      at release time. (Spec AC-9)
- [ ] `sync-manifest.yaml` — one `always_sync` entry for
      `changelog.d/README.md`, `mode_scope: shared`, with a note recording that
      fragment files are intentionally unlisted. (Spec AC-12; Decision 7)
- [ ] `.haystack/pr-rules.yml` — retarget the
      `keep-single-unreleased-changelog-section` rule message to hotfix and
      release edits.
- [ ] `.haystack/review-policy.md` — add `changelog.d/**` to the "Review
      release and changelog automation" section's path list (currently
      `CHANGELOG.md`, `.github/workflows/auto-tag-release.yml`, severity
      `critical`). That section's stated reason — "version parsing or
      changelog structure mistakes can create incorrect release tags that are
      hard to undo" — applies verbatim to `changelog-fragments.sh`'s
      `assemble`/`consume` rewriting and to the `changelog.d/manifests/*.txt`
      state files; without this the new automation and state files fall back
      to the generic `scripts/development-workflow/**` = `high` policy row (or
      no row at all for `changelog.d/manifests/`), one severity level below
      what its own risk rationale calls for.
- [ ] Verified as needing **no** change: `.github/workflows/auto-tag-release.yml`
      (reads published version sections only), `.markdownlint.jsonc` and
      `.markdownlint-cli2.jsonc` (rule set is file-agnostic),
      `.pr_agent.toml` (its changelog note remains accurate),
      `scripts/development-workflow/check-documentation-stage-alignment.sh`
      (fragments are correctly unexpected on documentation-stage branches),
      `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`
      (its `--from-changelog` parser reads the assembled section and keeps
      working because fragment bodies carry `(#N)`),
      `scripts/development-workflow/component-release-target.sh` (ownership
      resolution only), `.github/workflows/workflow-tests.yml` (selection is
      computed, so the new suite needs no workflow edit).

### Backend / API

Not applicable — this repository ships workflow tooling and documentation; it
has no application backend, database, or UI.

### Documentation, protocols, and agent surfaces

This plan **introduces or modifies a cross-cutting checklist**: the release-note
requirement applies to every implementation across the workflow, and this change
alters how every implementer, reviewer, and orchestrator satisfies it. The full
enumeration below is the result of the live searches recorded in the
Verification Log, not a copied list.

Protocols:

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      — replace the "Update CHANGELOG" step in Path 1 (feature), Path 2
      (refactor), and Path 3 (fix) with "Record the release note", writing a
      fragment and running `changelog-fragments.sh validate`. Delete the
      duplicate-`### Category` avoidance machinery from those three paths — it
      is unreachable once no item edits a shared section. Leave Path 4 (hotfix)
      byte-for-byte unchanged. Rename both "CHANGELOG entry preview" PR-body
      bullets to "release note preview". (Spec AC-2, AC-11)
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      — restructure Step 3 into: assemble the draft; **commit** (the manifest
      and the rewritten `CHANGELOG.md`); editorial pass (today's polish
      guidance retargeted at the assembled draft, unchanged in substance);
      link-reference definitions (unchanged); **commit** (the editorial pass
      and link-reference definitions); consume the notes. The two commits are
      both new and both precede Step 5's existing version-bump commit — see
      Decision 3's "Interrupted preparation resumes intact" bullet: without
      them, neither artifact is a "committed file on the release branch" until
      Step 5, and `--repair-manifest`'s git-history restore has no commit to
      find for the entire span between assembly and Step 5. Extend Step 7.2's
      release-artifact validation with the two checks that prove consumption
      ran: `changelog.d/manifests/consumed/v<X.Y.Z>.txt` is present (not
      merely `changelog.d/manifests/v<X.Y.Z>.txt` absent — see Decision 3) and
      `## [X.Y.Z] - YYYY-MM-DD` is present. (Spec AC-3, AC-4, AC-5, AC-8)
- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      — extend Step 2.5 so the graduation PR is verified to carry the
      `changelog.d/` additions accumulated on `develop-<slug>`, alongside the
      existing `CHANGELOG.md` check. Note that #1589 is adding a new section
      near the top of this file; the Step 2.5 edit is in a different region.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — update the Step 5.1 CHANGELOG-presence row per Decision 5; rewrite Step
      3.6 from "conflicts are expected and auto-resolved" to "disjoint paths
      make the conflict impossible", retaining a short note for repositories
      that have not adopted fragments; update the Step 5.1 preamble sentence
      about the `files` field. (Spec AC-1, AC-2)
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — update the "CHANGELOG in parallel batches" paragraphs in both places
      they appear.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      — apply Decision 6: restate the Step 4.3 `CHANGELOG.md` trigger, add the
      `changelog.d/` never-auto-resolve clause, and update the merge-ordering
      rationale text.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
      and `02-generate-implementation-plan-protocol.md` — extend the "Do NOT
      update CHANGELOG" steps to cover `changelog.d/`, and update Protocol 02's
      "CHANGELOG literal format" guardrail to describe the fragment a plan
      hands to the implementer.
- [ ] `docs/workflow/development-workflow/templates/implementation-plan-template.md`
      — update the final Implementation Order step.
- [ ] `docs/workflow/development-workflow/README.md` — the implementation and
      release narrative, and the hotfix section (which stays correct but should
      name the contrast explicitly).
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` — the
      changelog false-positive guidance, rescoped and with the rule id
      corrected.

Review contract, agent, command, and skill surfaces:

- [ ] `REVIEW.md` — spec exemption, plan exemption, code-review checklist item,
      and the reviewer-finding list.
- [ ] `.claude/agents/developer.md` and `.cursor/agents/developer.md`
- [ ] `.claude/agents/tech-lead.md` and `.cursor/agents/tech-lead.md` — only if
      the plan-stage CHANGELOG-literal guidance is quoted there; verify at
      implementation time and record the result either way.
- [ ] `.cursor/rules/workflow.mdc` and `.cursor/commands/implement-development.md`
- [ ] `.claude/commands/prepare-release.md`, `.cursor/commands/prepare-release.md`,
      `.agents/skills/prepare-release/SKILL.md` (a real directory, not a
      symlink)
- [ ] `.claude/commands/batch-merge.md`, `.cursor/commands/batch-merge.md`,
      `.codex/skills/batch-merge/SKILL.md`, and
      `.codex/skills/batch-merge/agents/openai.yaml`
- [ ] `.claude/commands/graduate-development.md` and
      `.cursor/commands/graduate-development.md`
- [ ] `.codex/skills/workflow-implementer/SKILL.md` and
      `.codex/skills/workflow-plan-writer/SKILL.md` — these delegate to the
      protocols and contain no changelog text at the plan-time revision.
      Re-check at implementation time; change only if that has changed.
- [ ] `.codex/skills/workflow-sync-template/SKILL.md`,
      `.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`,
      `.cursor/commands/sync-template.md` — their changelog references are
      about the sync tool's own changelog handling; verify and record.
- [ ] `AGENTS.md` — the "CHANGELOG & Versioning" section and the lint command
      block. `CLAUDE.md` and `GEMINI.md` are symlinks and need no separate edit.
- [ ] `LLM_RULES.md`, `README.md`, `docs/best-practices/1-general.md`,
      `docs/best-practices/2-version-control.md`
- [ ] `scripts/development-workflow/README.md` and `scripts/lint/README.md` —
      document the new helper.
- [ ] `docs/testing/workflow/batch-merge.smoke-test.md` — its CHANGELOG-conflict
      scenarios describe behaviour that no longer occurs for item PRs.

---

## Testing Strategy

**Test types**: Unit (shell suite), Integration (end-to-end merge and release
rehearsal), Smoke (runbook).

**Key scenarios to test**:

1. Two branches each adding a fragment merge one after the other with no
   conflict, and both notes survive — Spec AC-1.
2. A PR carrying only a fragment satisfies the release-note readiness check
   without touching `CHANGELOG.md` — Spec AC-2.
3. Assembly gathers every pending note into a version section grouped by kind —
   Spec AC-3.
4. Edits made to the assembled draft survive to publication — Spec AC-4.
5. Assembly followed by interruption and resumption loses neither notes nor
   edits — Spec AC-5.
6. A fragment written after assembly is absent from that release and present
   for the next one — Spec AC-6.
7. After consumption no manifest-listed fragment remains, and a repeat
   assembly produces no duplicate section — Spec AC-7.
8. After publication the changelog is ready for the next release and every
   version link resolves — Spec AC-8.
9. The assembled section passes `markdownlint-cli2`,
   `markdown-heuristic-lint.py`, and `check-changelog-duplicate-headers.sh` —
   Spec AC-9.
10. A release cut with both a populated shared block and pending fragments
    contains every entry exactly once — Spec AC-10.
11. A hotfix writes its own versioned section and is untouched by assembly —
    Spec AC-11.
12. A fresh clone of the template can record a note with no setup — Spec AC-12.
13. Published history above the new version section is byte-identical before
    and after — Spec AC-13.

**Suites to add or extend**:

- **Add** `scripts/development-workflow/tests/test-changelog-fragments.sh`. It
  covers `changelog-fragments.sh` by the naming convention, and declares
  additional `# covers:` lines for `.github/workflows/markdown-lint.yml`,
  `changelog.d/**`, and
  `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
  so a change to any of them selects this suite in CI.
- **Extend** `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
  with a fixture whose version section was produced by assembly, proving
  `--from-changelog` still extracts the issue scope from fragment-derived
  bullets.
- **Extend** `scripts/development-workflow/tests/test-batch-merge-changelog-race.sh`
  with a case asserting that a `changelog.d/` conflict is classified
  non-trivial rather than auto-resolved.
- **Extend** `scripts/development-workflow/tests/test-select-test-suites.sh`
  only if its expected-mapping fixtures enumerate suites; verify at
  implementation time.
- **Run** `scripts/lint/check-changelog-duplicate-headers.sh` and
  `scripts/lint/markdown-heuristic-lint.py` against every assembled fixture
  produced by the new suite, so lint conformance of the output is asserted by
  the suite itself rather than only observed in CI.

**Smoke test runbook**: `docs/testing/workflow/1554-changelog-fragments.smoke-test.md`

**Regression suite**: the repository's automated regression surface is the
shell suites under `scripts/development-workflow/tests/`, selected per change
set by `select-test-suites.sh`. The new suite above is that regression
coverage; no separate regression project applies.

### Parser-risk addendum

This plan is **parser-risk**: `changelog-fragments.sh` performs structured-text
scanning of filenames against a strict grammar and rewrites `CHANGELOG.md` by
locating section boundaries. Every case below maps to at least one automated
test in `scripts/development-workflow/tests/test-changelog-fragments.sh`.

**Edge-case enumeration — filename grammar**

| # | Input | Required behaviour |
| --- | --- | --- |
| 1 | `1554.fixed.a.md` | Accepted; minimal legal name |
| 2 | `1554.fixed.changelog-fragments-collide.md` | Accepted; hyphens in the slug |
| 3 | `ENG-42.added.export-button.md` | Accepted; hyphen inside the tracker identifier |
| 4 | `1554.fixed.fixed-fixed.md` | Accepted as kind `fixed`, slug `fixed-fixed` — the strict field split makes a kind-lookalike slug harmless |
| 5 | `1554.improved.x.md` | Rejected; message names the six recognized kinds |
| 6 | `1554.Fixed.x.md` | Rejected; kinds are lowercase |
| 7 | `1554.fixed.md` | Rejected; too few fields |
| 8 | `1554.fixed.a.b.md` | Rejected; dots are forbidden inside fields |
| 9 | `.fixed.a.md` | Rejected; empty item field |
| 10 | `README.md` | Ignored — never a fragment, never an error |
| 11 | `.gitkeep`, `.DS_Store` | Ignored |
| 12 | `1554.fixed.notes.txt` | Rejected loudly rather than skipped, so a note cannot be silently left behind |
| 13 | `manifests/v1.0.0.txt` | Ignored by the fragment scan, which reads only the top level of `changelog.d/` |

**Edge-case enumeration — fragment body**

| # | Input | Required behaviour |
| --- | --- | --- |
| 14 | Empty or whitespace-only file | Rejected |
| 15 | First non-blank line does not begin with `- ` | Rejected; a non-bullet body would corrupt the assembled list |
| 16 | Multiple top-level bullets in one fragment | Accepted; copied verbatim without renumbering |
| 17 | Continuation lines indented by two spaces | Preserved verbatim; assembly never re-wraps |
| 18 | CRLF line endings | Normalized to LF before insertion |
| 19 | A body line beginning with `## [` or `### ` | Rejected by `validate`, for the same reason as row 20: `check-changelog-duplicate-headers.sh` and `auto-tag-release.yml` re-parse `CHANGELOG.md` from scratch by matching `^## ` / `^### ` on raw lines, with no notion of "this line came from inside a fragment body." A verbatim-copied heading-shaped line would be interpreted as a real section or category boundary by every downstream consumer, even though the assembler's own single-pass boundary computation stays correct for that one run. Escaping (rather than rejecting) was considered and rejected: it would leave the releaser's rendered CHANGELOG.md containing an escaped artifact instead of the intended bullet, which is a worse outcome than asking the fragment's author to reword the line before assembly ever happens |
| 20 | Trailing whitespace on a body line | Rejected by `validate`, so it fails on the item's PR rather than producing an MD009 failure on the assembled changelog |

**Edge-case enumeration — changelog rewriting**

| # | Input | Required behaviour |
| --- | --- | --- |
| 21 | No `## [Unreleased]` heading | Rejected; the heading is a precondition that `auto-tag-release.yml` also depends on |
| 22 | Two `## [Unreleased]` headings | Rejected |
| 23 | `## [X.Y.Z]` already present, manifest for that version also present in `changelog.d/manifests/` | `ASSEMBLE_RESULT=already_assembled`, exit 0, no write — the idempotence mechanism (Decision 3 requires both artifacts, not the heading alone) |
| 24 | Populated shared block plus pending fragments | Both merged into one version section, each entry once, with no duplicate `### Category` heading |
| 25 | Populated shared block, zero fragments | Rename only — the pre-fragment behaviour, preserved |
| 26 | Empty shared block, zero fragments | `ASSEMBLE_RESULT=no_notes`, exit 3, unless `--allow-empty` |
| 27 | A kind present in fragments but absent from the shared block | Heading created in canonical Keep a Changelog order |
| 28 | Deterministic ordering | Bullets sorted by kind rank, then by the item field (numerically when it is all digits, lexicographically otherwise), then by full filename — so two runs on the same input produce identical bytes |
| 29 | `consume` when the manifest is absent from both `changelog.d/manifests/` and `changelog.d/manifests/consumed/`, and the version section is also absent | `CONSUME_RESULT=manifest_missing`, non-zero, with the remediation named (run `assemble` first) |
| 30 | `consume` run twice | First run reports `consumed`. Second run finds the manifest already moved to `changelog.d/manifests/consumed/` and reports `CONSUME_RESULT=already_consumed`, exit 0 |
| 31 | `consume` when the `## [X.Y.Z]` heading is absent, a manifest-listed file is already gone, and the manifest is not in either manifest location | Rejected — `CONSUME_RESULT=inconsistent`; the release state is corrupted and must not be papered over |
| 32 | `assemble` when the manifest for the target version is present but the `## [X.Y.Z]` heading is absent (interrupted between the two writes) | `assemble` performs the `CHANGELOG.md` write (temp file, `fsync`, atomic rename) from the already-frozen manifest, never a rescan. `ASSEMBLE_RESULT=assembled`, exit 0 |
| 33 | `assemble` when the `## [X.Y.Z]` heading is present but the manifest for that version is absent from both manifest locations | `ASSEMBLE_RESULT=assembled_unmanifested`, exit 1, naming `assemble --repair-manifest` (git-history restore) as the remediation — never a directory rescan |
| 34 | `consume` when neither manifest location holds the target version but the `## [X.Y.Z]` version section is present | `CONSUME_RESULT=inconsistent`, exit 1 — no longer conflated with `already_consumed`; the operator must reconcile by hand |
| 35 | `consume` when the manifest is present in `changelog.d/manifests/` but the `## [X.Y.Z]` heading is absent | `CONSUME_RESULT=not_assembled`, exit 1, deletes nothing — assembly never finished; remediation is to run `assemble` first |
| 36 | `consume` when the heading is present, the manifest is present in `changelog.d/manifests/`, and some or all manifest-listed fragment files are already absent (a prior run stopped after deleting fragments but before moving the manifest) | Resume: finish deleting whatever remains (idempotent — an absent file is not an error), then move the manifest. `CONSUME_RESULT=consumed`, exit 0 |
| 37 | `assemble --repair-manifest` when a commit on the current branch previously wrote `changelog.d/manifests/v<X.Y.Z>.txt` | Restore that commit's blob verbatim, via the same atomic temp-file-and-rename write as every other write in this plan. `ASSEMBLE_RESULT=repaired`, exit 0 — the restored set is exactly what was frozen at the original assembly, never a live rescan |
| 38 | `assemble --repair-manifest` when the path was written by more than one commit (for example, an earlier `--repair-manifest` or `--reassemble`) | Restore the **most recent** commit's blob — the one that reflects the currently-authoritative content, not an earlier one. `ASSEMBLE_RESULT=repaired`, exit 0 |
| 39 | `assemble --repair-manifest` on a shallow clone, where no commit in the fetched history wrote the manifest but one may exist outside the fetched depth | `ASSEMBLE_RESULT=history_truncated`, exit 1, naming `git fetch --unshallow` as the remediation — distinct from `manifest_unrecoverable`, which asserts no such commit exists at all |
| 40 | `assemble --repair-manifest` on a full (non-shallow) clone when no commit on the current branch ever wrote the manifest for the target version | Refuse to guess. `ASSEMBLE_RESULT=manifest_unrecoverable`, exit 1, naming manual reconciliation (or an explicit, risk-accepted `--reassemble`) as the only remaining paths |

**Suppression semantics**: not applicable. `changelog-fragments.sh` recognizes
no inline suppression directives. Declining to write a release note is
expressed by not creating a fragment, exactly as declining to edit
`CHANGELOG.md` is expressed today, and it is not a directive the parser reads.

### Concurrent-event-source addendum

**Partially applicable, split by scope.** `changelog-fragments.sh` is a
single-threaded command-line helper with no listeners, timers, sockets, or
async queues, so every *in-process* async concern is not applicable: event
deduplication, listener and resource cleanup, and error propagation across
async boundaries. The concurrency between independent item PRs is likewise not
applicable to runtime synchronization — it is handled structurally, by
disjoint fragment file paths (Decision 1), before any of these commands run.

**Concurrent *process* invocation on the same release branch is a real,
narrower case**, and this plan does not leave it unguarded: `assemble` and
`consume` both rewrite `CHANGELOG.md` and the manifest across several
non-atomic file operations (Decision 3), so two invocations racing on the
same release branch checkout could interleave and produce exactly the
lost-note or inconsistent-state outcomes the spec's "no unreleased note may be
silently left behind" rule forbids. This repository already has a precedent
for this exact shape of problem: `prepare-release-post-merge-cleanup.sh`
guards its own shared release-state mutation with an `mkdir`-based lock,
scoped to the coordinating checkout's git-dir (not the tracked working tree),
that fails clearly with a non-zero exit and a named remediation when already
held, rather than allowing a second run to interleave.

`assemble` and `consume` follow the same convention: before performing any
write, each acquires an `mkdir`-created lock directory at
`$(git rev-parse --git-dir)/changelog-fragments-locks/v<X.Y.Z>.lock`, scoped
per target version (so `assemble` for `0.44.0` never blocks `consume` for
`0.43.0`), and removes it on exit via a `trap`. If the `mkdir` fails because
the lock is already held, the command exits non-zero immediately with
`ASSEMBLE_RESULT=locked` / `CONSUME_RESULT=locked`, the lock directory path,
and the instruction to retry once the other invocation completes — it never
waits or retries silently. This is a bounded, single-checkout mitigation, the
same known limitation `prepare-release-post-merge-cleanup.sh` documents for
its own lock: it does not exclude a concurrent run from a different clone or
worktree of the same release branch, and the plan does not claim otherwise.

**Staleness — a gap the precedent script leaves open, which this plan does
not repeat.** `prepare-release-post-merge-cleanup.sh`'s lock has no built-in
staleness recovery at all: if its owning process is killed, the lock directory
is empty (`mkdir` with no marker file inside it) and stays held forever, with
no documented way for an operator to tell "still running" apart from "leaked."
Copying that as-is would mean this plan's own troubleshooting guidance — "wait
for it to finish, or confirm it is stale and remove the lock directory" —
gives the operator no actual mechanism to confirm staleness, which risks the
operator guessing wrong and `rmdir`-ing a lock a still-running invocation
holds, recreating the exact interleaving the lock exists to prevent. This plan
closes that gap: at acquisition, `assemble`/`consume` write a single file
inside the lock directory, `owner` (PID, hostname, and UTC start timestamp, one
per line — no atomicity requirement on this file, since it exists only after
the `mkdir` that already committed the lock). When `mkdir` fails, the reported
remediation reads that file and instructs the operator to check
`ps -p <pid>` (or the equivalent on the owner's host, if different from the
current one) before removing the lock directory — remove it only when the
recorded PID is confirmed not running on the recorded host. This is still a
manual, human-in-the-loop judgment (there is no cross-host liveness protocol),
so a wrong manual judgment remains possible; it is a strict improvement over
"confirm it is stale" with no data to confirm it against, not a hard
guarantee.

The test suite (Implementation Order Step 2) adds one interleaving case per
command: start a run, hold its lock open, start a second run of the same
command against the same version, and assert the second run reports `locked`
and makes no write; and one stale-lock case: create a lock directory with an
`owner` file naming a PID that is not running, and assert the reported
remediation names that file rather than only the lock directory path.

---

## Complex Workflow Decision-Gate Matrix

This plan adds a workflow decision gate: the release-time assemble/consume step
in Protocol 05, whose behaviour depends on several inputs and produces several
distinct next actions. It also changes an existing gate: the release-note
readiness check.

### Gate A — `changelog-fragments.sh assemble`

| Gate inputs | Outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| No manifest for the target version; no `## [X.Y.Z]` heading; at least one pending fragment or a non-empty shared block | `assembled` | Continue to the editorial pass (Protocol 05 Step 3) | Protocol 05; `.claude/commands/prepare-release.md`; `.cursor/commands/prepare-release.md`; `.agents/skills/prepare-release/SKILL.md` |
| Manifest for the target version present; `## [X.Y.Z]` heading also present | `already_assembled` | No write; continue. This is the resume path and the idempotence guarantee — both artifacts, not the heading alone (Decision 3) | Same |
| Manifest for the target version present; `## [X.Y.Z]` heading absent | `assembled` | Interrupted between the two writes. Perform the `CHANGELOG.md` write (temp file, `fsync`, atomic rename) from the already-frozen manifest, never a rescan; continue to the editorial pass | Same |
| Manifest for the target version absent; `## [X.Y.Z]` heading present | `assembled_unmanifested` (exit 1) | Stop; run `assemble --repair-manifest` to restore the manifest from git history — never a directory rescan (a live rescan can pull in a fragment added since the original assembly) | Protocol 05 Step 3 |
| `--repair-manifest` passed; a commit on the branch previously wrote the manifest for this version (the most recent such commit, if more than one) | `repaired` | The manifest is restored verbatim from that commit, via the same atomic temp-file-and-rename write as every other write in this plan; continue to `already_assembled` on the next run | Same |
| `--repair-manifest` passed; the clone is shallow and cannot rule out a commit outside the fetched depth | `history_truncated` (exit 1) | Stop; run `git fetch --unshallow`, then retry `--repair-manifest` — this is a clone-configuration gap, not evidence the manifest is unrecoverable | Protocol 05 Step 7.2 |
| `--repair-manifest` passed; the clone is not shallow and no commit on the branch ever wrote the manifest for this version | `manifest_unrecoverable` (exit 1) | Stop; reconcile by hand (compare the published section's bullets against fragments still in `changelog.d/`), or explicitly accept the risk of `--reassemble` | Protocol 05 Step 7.2 |
| `--reassemble` passed and the heading is present | `reassembled` | Print the replaced section first; the releaser must redo any editorial pass. Not invoked automatically by any recovery path | Same |
| No pending fragment and an empty shared block | `no_notes` (exit 3) | Stop; either there is nothing to release or a fragment was lost. Pass `--allow-empty` only for a deliberate no-notes release | Same |
| Any fragment fails the grammar or body checks | `invalid` (exit 1) | Fix the named fragment on `develop` and re-run; never assemble a partial set | Protocol 05; `.github/workflows/markdown-lint.yml` |
| `CHANGELOG.md` lacks exactly one `## [Unreleased]` heading | `error` (exit 1) | Repair the changelog before releasing | Protocol 05 Step 7.2 |

### Gate B — `changelog-fragments.sh consume`

| Gate inputs | Outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| Heading present; manifest present in `changelog.d/manifests/`, every listed file present | `consumed` | Commit the deletions and the manifest move (to `changelog.d/manifests/consumed/`) with the release commit | Protocol 05 Step 3 |
| Manifest present in `changelog.d/manifests/`, `## [X.Y.Z]` heading absent | `not_assembled` (exit 1) | Stop; deletes nothing. Run `assemble` first — assembly never finished writing the section | Protocol 05 Step 3 |
| Heading present; manifest present in `changelog.d/manifests/`; some or all listed files already absent | `consumed` | Interrupted consume, safe to resume: finish deleting whatever remains (idempotent), then move the manifest | Protocol 05 Step 3 |
| Manifest present in `changelog.d/manifests/consumed/`, absent from `changelog.d/manifests/` | `already_consumed` | Continue; confirmed by the moved file's presence, not by absence | Protocol 05 Steps 3 and 7.2 |
| Manifest absent from both locations, heading absent | `manifest_missing` (non-zero) | Run `assemble` first | Protocol 05 Step 3 |
| Manifest absent from both locations, heading present | `inconsistent` (exit 1) | Stop and reconcile by hand; no longer conflated with `already_consumed` | Protocol 05 Step 7.2 |
| Heading absent; manifest absent from both locations; a listed file (from the last-known manifest state) already gone | `inconsistent` (exit 1) | Stop and reconcile by hand; the release state is corrupted | Protocol 05 Step 7.2 |

### Gate C — release-note readiness (changed, not added)

| Gate inputs | Outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| `feature/*`, `fix/*`, `refactor/*` PR whose files include a `changelog.d/` path | Pass | Continue to the remaining Step 5.1 checks | Protocol 90 Step 5.1; `REVIEW.md`; `.claude/agents/developer.md`; `.cursor/agents/developer.md` |
| `hotfix/*` PR whose files include `CHANGELOG.md` | Pass | Continue — the hotfix path is unchanged | Protocol 90 Step 5.1; Protocol 03 Path 4 |
| Implementation PR with neither | Fail | Redispatch to record a release note; do not accept as ready | Protocol 90 Step 5.1 |
| `spec/*` or `implementation-plan/*` PR | Not applicable | Exempt; a fragment on these branches is a finding, not a pass | `REVIEW.md`; `check-documentation-stage-alignment.sh` |
| `backport/hotfix/*` PR | Not applicable | Exempt; the versioned entry already exists on `main` and flows through the merge | Protocol 90 Step 5.1 |

**Examples**: the changed surfaces carry worked examples today (Protocol 03's
per-path changelog snippets, Protocol 05's rename instructions, Protocol 94's
auto-resolution report text). Each must be rewritten to the new convention in
the same edit, and the implementation must not leave an example demonstrating
the retired convention on a surface whose prose describes the new one.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Valid fragments spanning several kinds | `900.added.alpha.md`, `901.fixed.beta.md`, `902.changed.gamma.md` | Fixtures created by `scripts/development-workflow/tests/test-changelog-fragments.sh` in a temporary directory |
| Invalid fragments | One per rejected row of the parser-risk tables above | Same |
| Changelog with a populated shared block | `## [Unreleased]` carrying `### Added` and `### Fixed` bullets, plus prior version sections and their link-reference definitions | Same — the transition-release fixture |
| Changelog with an empty shared block | `## [Unreleased]` with no bullets | Same — the steady-state fixture |
| This item's own release note | `changelog.d/1554.changed.per-item-release-notes.md` (content in Implementation Order Step 12) | Committed by the implementation PR |

---

## Documentation Updates

The developer must update the following after implementation. These are listed
for execution, not performed during Plan Ready.

- [ ] `AGENTS.md` — rewrite the "CHANGELOG & Versioning" section for the
      fragment convention, keeping the hotfix exception; extend the markdown
      lint command block to cover `changelog.d/`. `CLAUDE.md` and `GEMINI.md`
      are symlinks to this file and must not be edited separately.
- [ ] `README.md` — the repository-structure listing and the CHANGELOG-required
      bullet.
- [ ] `REVIEW.md` — spec exemption, plan exemption, code-review checklist item,
      reviewer-finding list.
- [ ] `LLM_RULES.md` — the agent commit rule.
- [ ] `docs/best-practices/1-general.md` — the lint command block.
- [ ] `docs/best-practices/2-version-control.md` — becomes the canonical
      statement of the release-note convention.
- [ ] `docs/workflow/development-workflow/README.md` — implementation and
      release narrative, hotfix contrast.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` —
      changelog false-positive guidance and rule id.
- [ ] `scripts/development-workflow/README.md` and `scripts/lint/README.md` —
      document `changelog-fragments.sh`.
- [ ] `docs/testing/workflow/batch-merge.smoke-test.md` — its
      CHANGELOG-conflict scenarios.
- [ ] `changelog.d/README.md` — new; the authoritative filename and body
      reference that ships to downstream projects.
- [ ] `docs/project/` — no update required. This repository's project docs are
      unfilled template placeholders and describe no changelog behaviour.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| An entry is lost or duplicated at the transition release, which is the hardest failure to detect after the fact | Med | High | Design the transition first, not last (tracker handoff). Assembly **moves** the shared block by renaming its heading rather than copying bullets, so duplication requires a coding error rather than an oversight; edge cases 24, 25, and 27 are asserted by fixtures before any protocol text is written |
| The sweep misses a surface, leaving one agent instructed to edit `[Unreleased]` and reintroducing the conflict for whatever it builds | Med | High | The residual verification strategy below requires the implementation PR to re-run the repository-wide scan and account for every hit, either as changed or with a written no-change rationale |
| The risk classifier grades the implementation PR `high` because it touches `.github/workflows/`, blocking delegated merge under the `medium` ceiling | High | Low | Known and filed as #1565. Expect an explicit merge authorization request rather than treating it as a failure |
| File-level overlap with open PR #1589 on `.github/workflows/markdown-lint.yml` and `05b-graduate-development-protocol.md` | Med | Low | The edits are in disjoint regions (branch filters and a new top section, versus `paths:`/targets and Step 2.5). If #1589 merges first, rebase; the conflict, if any, is a normal two-region docs conflict, not the combinatorial one this item removes |
| A release-branch delete of a fragment races an edit of that same fragment on `develop` | Low | Low | Git reports a delete/modify conflict on one file owned by one item. Editing a note after its release is already a mistake; document the resolution (keep the deletion) in Protocol 94's `changelog.d/` clause |
| `--reassemble` discards a releaser's editorial pass | Low | Med | The flag is never used by Protocol 05's normal flow, and the command prints the section it is about to replace before replacing it |
| A recovery path (`--repair-manifest`, `assembled_unmanifested`/`not_assembled` handling) is implemented incorrectly, silently reintroducing the truncation or retroactive-inclusion bugs Decision 3 exists to prevent | Low | High | Edge cases 31–38 fixture every recovery combination (interrupted write, lost manifest with and without git history, interrupted consume, premature consume) as red tests before the corresponding code exists (Implementation Order Steps 2, 4, 5) |
| Downstream projects that have not adopted fragments receive protocol updates describing a convention they do not use | Med | Low | Decision 6 keeps Protocol 94's auto-resolution and states the not-yet-adopted case explicitly; Decision 4's assembly works unchanged on a populated shared block, so adoption needs no migration |

---

## Code Samples

The filename grammar, expressed as a regular expression. **Illustrative —
adapt during implementation**; the authoritative behaviour is the edge-case
tables above.

```text
^(?<item>[A-Za-z0-9][A-Za-z0-9_-]*)\.(?<kind>added|changed|deprecated|removed|fixed|security)\.(?<slug>[a-z0-9][a-z0-9-]*)\.md$
```

An example fragment file, `changelog.d/1589.fixed.integration-branch-ci.md`.
**Illustrative** — the body is the finished bullet, copied verbatim into the
assembled section:

```markdown
- **Integration-branch PRs now run CI** (#1525): workflows that gated only on
  `develop` ran zero checks on sub-item PRs targeting `develop-<slug>`.
```

An example release manifest, `changelog.d/manifests/v0.43.0.txt`.
**Illustrative**:

```text
# assembled 2026-09-01T09:14:22Z version=0.43.0 fragments=2 carried_over=56
changelog.d/1554.changed.per-item-release-notes.md
changelog.d/1589.fixed.integration-branch-ci.md
```

---

## Implementation Order

1. **Create the directory and its reference.** Add `changelog.d/README.md`
   documenting the grammar, the six kinds, and the body convention, and
   `changelog.d/manifests/.gitkeep` and
   `changelog.d/manifests/consumed/.gitkeep`. (Decisions 1, 2, 7)

   *Verify*: `ls changelog.d` lists the README and the manifests directory,
   `ls changelog.d/manifests` lists the `consumed` subdirectory, and
   `node_modules/.bin/markdownlint-cli2 "changelog.d/README.md"` reports no
   violations.

2. **Write the test suite first, red.** Create
   `scripts/development-workflow/tests/test-changelog-fragments.sh` with one
   case per row of the three parser-risk tables (including edge cases 31–38,
   the recovery-state matrix), one interleaving case per command for the
   per-release lock (Concurrent-event-source addendum), and a case that
   verifies `CHANGELOG.md` is left byte-identical to its pre-assembly content
   when the process is killed after the temp-file write but before the atomic
   rename, plus its `# covers:` header lines. Every case fails at this point
   because the helper does not exist.

   *Verify*: running the suite reports failures for every case and no case is
   silently skipped.

3. **Implement `validate` and `list`.** Filename grammar, body checks, and the
   reporting fields.

   *Verify*: the filename-grammar and fragment-body cases in the suite pass;
   the changelog-rewriting cases still fail.

4. **Implement `assemble`.** The per-release `mkdir` lock (Concurrent-event-
   source addendum); manifest-first write (temp file, `fsync`, atomic
   rename); then the `CHANGELOG.md` write with the same atomicity guarantee
   (temp file, `fsync`, atomic rename) — heading rename, per-kind merge,
   fresh empty `## [Unreleased]`, deterministic ordering; all four assembly
   states from Decision 3 (`assembled`, `already_assembled`, the
   manifest-present/heading-absent resume, and `assembled_unmanifested`);
   `--repair-manifest` (git-history restore of the most recent writing
   commit, itself written atomically; `repaired`, `history_truncated` on a
   shallow clone, or `manifest_unrecoverable` on a full clone, never a
   directory rescan); `--reassemble` (identical manifest-first, atomic-rename
   write order as normal assembly); and `no_notes`.

   *Verify*: the changelog-rewriting cases pass, and the suite's assembled
   fixtures are checked with `check-changelog-duplicate-headers.sh` and
   `markdown-heuristic-lint.py` inside the suite itself. The kill-before-rename
   case from Step 2 confirms `CHANGELOG.md` is untouched, not truncated.

5. **Implement `consume`.** The per-release `mkdir` lock; the `## [X.Y.Z]`
   heading precondition (`not_assembled` when the manifest exists but the
   heading does not — deletes nothing); manifest-driven, idempotent
   per-file deletion (resuming an interrupted consume simply finishes
   whatever remains); moving (not deleting) the manifest into
   `changelog.d/manifests/consumed/`; the `already_consumed` outcome
   (detected from the moved file's presence); and the `inconsistent`
   rejection when neither manifest location holds the target version.

   *Verify*: the whole suite passes. Run `consume` twice in a row and confirm
   the first run reports `consumed` and the second reports `already_consumed`.
   Run it against a fixture with the heading absent and confirm
   `not_assembled` with zero fragment files deleted. Run it against a fixture
   with some manifest-listed fragments pre-deleted and confirm it completes
   and reports `consumed` rather than erroring.

6. **Wire the lint and CI surfaces.** Update
   `.github/workflows/markdown-lint.yml` (`paths:`, both independent
   file-discovery `find` blocks, the `markdownlint-cli2` glob list, and a
   `validate` step).

   *Verify*: `bash scripts/development-workflow/select-test-suites.sh
   --changed-files <file listing the changed paths>` lists
   `test-changelog-fragments.sh`; running the repository's markdown lint
   commands locally passes; and running `python3
   scripts/lint/markdown-heuristic-lint.py` against a file under
   `changelog.d/` confirms it is picked up (not just `markdownlint-cli2`).

7. **Update the release path.** Protocol 05 Step 3 (assemble, editorial pass,
   link definitions, consume) and Step 7.2's artifact validation, then the three
   prepare-release command and skill surfaces. **Add two commits inside the
   restructured Step 3, both before Step 5's existing version-bump commit**:
   one immediately after `assemble` succeeds (before the editorial pass touches
   anything) and one immediately after the editorial pass and link-reference
   definitions, before `consume` runs. Without these, the manifest and the
   editorial pass sit uncommitted for the whole span Decision 3's recovery
   design protects, and `--repair-manifest`'s git-history restore has nothing
   to restore from until Step 5 — see Decision 3's "Interrupted preparation
   resumes intact" bullet, which this step implements.

   *Verify*: read Step 3 end to end and confirm a releaser can execute it
   without consulting this plan, that the editorial pass still appears
   between assembly and consumption, and that the two new commit points are
   both present and both precede Step 5. Confirm by inspection that a
   `--repair-manifest` run immediately after the first of the two commits
   (i.e. before the editorial pass) would find that commit in `git log`.

8. **Update the implementation path.** Protocol 03 Paths 1–3, leaving Path 4
   untouched; then `.claude/agents/developer.md`,
   `.cursor/agents/developer.md`, `.cursor/rules/workflow.mdc`, and
   `.cursor/commands/implement-development.md`.

   *Verify*: `git diff` on Protocol 03 shows no change within the hotfix path,
   and the four agent surfaces carry the same instruction as each other.

9. **Update the orchestration and merge paths.** Protocol 90 Steps 3.6 and 5.1,
   Protocol 91's two parallel-batch paragraphs, Protocol 94 Step 4.3 per
   Decision 6, Protocol 05b Step 2.5, and the batch-merge command and skill
   surfaces. In `batch-merge.sh`, add the clarifying sentence to the
   `PR_HAS_CHANGELOG` header comment and the `changelog.d/` clause to the
   hold-annotation text; change no logic.

   *Verify*: `bash scripts/development-workflow/tests/test-batch-merge-changelog-race.sh`
   and the other batch-merge suites pass unchanged, confirming no behavioural
   change was introduced.

10. **Update the review contract and remaining documentation.** `REVIEW.md`,
    `LLM_RULES.md`, `.haystack/pr-rules.yml`, `.haystack/review-policy.md`
    (add `changelog.d/**` to the release-and-changelog-automation path list),
    the `haystack-reviewer.sh` comment block (including the corrected rule
    id), `haystack-triage.md`, `AGENTS.md`, `README.md`, both best-practices
    files, both script READMEs, the spec and plan protocols, the plan
    template, and `docs/testing/workflow/batch-merge.smoke-test.md`.

    *Verify*: `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
    passes, and the rule id quoted in the script matches an id present in
    `.haystack/pr-rules.yml`.

11. **Ship the convention downstream.** Add the `changelog.d/README.md` entry to
    `sync-manifest.yaml` under `always_sync` with `mode_scope: shared` and a
    note recording that fragment files are intentionally unlisted.

    *Verify*: `bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`
    passes, and reading the manifest confirms no `project_specific` entry was
    added for `changelog.d/`.

12. **Record this item's own release note the new way.** Create
    `changelog.d/1554.changed.per-item-release-notes.md` containing exactly:

    ```markdown
    - **Per-item release notes replace the shared `[Unreleased]` block** (#1554):
      each work item now records its release note in its own `changelog.d/` file,
      so two items worked in parallel no longer edit the same lines and cannot
      conflict. Release preparation gathers the pending notes into a draft
      version section, which the releaser edits before publishing; the notes are
      removed when the release merges.
    ```

    Do **not** add an entry to `CHANGELOG.md` — this PR is the change that ends
    that practice, and doing both would produce the duplicate the transition
    design exists to prevent.

    *Verify*: `bash scripts/development-workflow/changelog-fragments.sh validate`
    reports `VALIDATE_RESULT=clean` with the new fragment counted, and
    `git diff --name-only origin/develop...HEAD` does not list `CHANGELOG.md`.

13. **Run the residual verification** described in the next section and include
    its table in the PR description.

14. **Execute the smoke test runbook** at
    `docs/testing/workflow/1554-changelog-fragments.smoke-test.md` and record
    the results.

---

## Residual Verification Strategy

This is a sweep with a pattern-completeness claim ("every surface that states
the changelog convention is updated"), so the implementation must produce
evidence rather than assert coverage.

**Evidence source**: a re-run, at implementation time, of the repository-wide
scan recorded in the Verification Log — a case-insensitive search for
`changelog` across the repository, excluding `.git`, `node_modules`, worktree
directories, `docs/specs/`, `hooks/node_modules`, and `CHANGELOG.md` itself.

**Evidence form**: a table in the PR description with one row per file the scan
returns, each classified as **changed**, **no change needed** with a one-line
rationale, or **out of scope** with a rationale. Historical smoke-test runbooks
for unrelated items and the published sections of `CHANGELOG.md` are expected to
fall in the last two categories; every protocol, agent, command, skill, script,
lint, workflow, and root-level document must fall in the first two.

**Why a re-run rather than this plan's list**: `develop` moves during
implementation, and a stale enumeration is exactly the failure this plan's own
Verification Log exists to prevent. The scan is the authority; this plan's
enumeration is the starting point.
