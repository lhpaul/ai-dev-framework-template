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
notes at release time into a draft `## [X.Y.Z]` section in `CHANGELOG.md` and
deletes the fragments it gathered, **in the same `assemble` invocation** —
both as ordinary uncommitted edits on the release branch, riding along on
Protocol 05's existing single release commit (Decision 3). An interrupted
release loses neither notes nor the releaser's edits for the same reason an
interrupted editorial pass already doesn't today: nothing is durable until
that one commit runs. Assembly also carries whatever is still sitting in the
shared `## [Unreleased]` block into the same version section, which is what
makes the transition release work without a migration and without a
one-release-only code path. Every readiness check, protocol, agent surface,
and lint that today asserts "this PR touched `CHANGELOG.md`" is updated to
accept a fragment instead.

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
| Release scope parser | Read `append_issues_from_changelog` in `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | Extracts `#N` tokens from the published `## [X.Y.Z]` section. Requires no change **provided** assembled bullets keep the `(#N)` reference, which the fragment body convention mandates except in the no-tracker fallback (Decision 1) — there, no `#N` exists to extract, so that bullet is correctly absent from the scope, exactly as it would be if hand-written without a reference today |
| Hotfix tagging path | Read `.github/workflows/auto-tag-release.yml` | Reads only `CHANGELOG.md` version sections; the hotfix path writes those directly and is untouched by this plan |
| Haystack rule identifier | `grep -n "changelog" .haystack/pr-rules.yml` and the comment block in `scripts/development-workflow/haystack-reviewer.sh` | The live rule id is `keep-single-unreleased-changelog-section`; the script's comment names `keep-changelog-unreleased-structure-canonical`, which does not exist in the rules file. Pre-existing drift, observed but not yet corrected — the fix is scheduled for Implementation Order Step 9 and is out of scope for this plan-writing PR |
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

**Repositories with no issue tracker configured** (`issue_tracker.provider:
none` or absent) fall back to **the pull request number** as `<item>` — for
example `changelog.d/1610.fixed.improve-caching.md` for PR #1610. This is a
second, independent instance of the same principle Decision 1 already relies
on for the tracker case: *the discriminator is an externally allocated
unique identifier*, not something this plan derives by transforming a
string it does not control.

**A sanitized branch name was considered and rejected** — the first draft of
this fallback used one, and a CodeRabbit round demonstrated it was not
collision-resistant: `feature/a/b` and `feature/a-b` both normalize to the
same string once `/` is folded into `-`, two different forks can use the
identical branch name (each fork's branch namespace is independent, so git's
own same-name-refusal — the property the sanitized-name design leaned on —
does not apply across forks at all), and the transformation could produce a
leading `-` or `_` that the filename grammar itself rejects. Every one of
these is a structural consequence of deriving an identifier from a string
whose only uniqueness guarantee is "no two *local* branches of the identical
name coexist" — a guarantee that does not extend to cross-fork or
lossy-normalization collisions. No further transformation of a branch name
closes that gap; a different kind of identifier is needed, not a better
sanitizer.

**Why the PR number closes it completely**: GitHub assigns pull request
numbers per repository, monotonically, regardless of which fork or branch
name the PR's head is — two PRs from two different forks, or two branches
that would sanitize to the same string, are still two different numbers.
This is exactly the same allocation model as an issue tracker's own
identifiers (Decision 1's primary case), just issued by the hosting platform
instead of the tracker.

**Consequence for authoring order**: in no-tracker mode, the fragment's
final filename cannot be written before the PR exists, because the number
it depends on does not exist yet. An author working before opening a PR
uses any locally convenient temporary name and **renames** the file to the
assigned PR number as part of opening the PR (or promptly afterward) — the
rename is a single `git mv`, not a data migration, since the body content is
unaffected. `changelog.d/README.md` states this explicitly, and `validate`
does not special-case it: the readiness gate (Decision 5) that checks for a
fragment on the PR's file list already runs *after* the PR exists, so by the
time it matters the number is always known.

In this mode the body's `(#N)` reference (Decision 2's worked examples) is
**omitted entirely** — there is no issue number to reference (the PR number
is used only as the filename's uniqueness discriminator, a distinct role
from the body's issue citation), and `changelog.d/README.md` states this
exception explicitly so an author does not invent a placeholder number that
`validate` has no way to distinguish from a real one.

**Corollary that must not be violated**: `changelog.d/` carries no index,
ordering file, or aggregate manifest that every item edits, ever. Any such
file would be a shared path and would recreate exactly the conflict this item
removes. (Decision 3 confirms release preparation introduces no such file
either — see "Why no manifest.")

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

### Decision 3 — Consumption semantics: fragments are deleted at assembly, not at a separate later step

**Revised.** The first draft of this decision represented "assembled but not
yet published" with a separate durable artifact (a per-release manifest) and
a separate `consume` command, on the theory that assembly and publication
were necessarily far apart in time and needed their own crash-recovery state
machine. Three CodeRabbit rounds on that design (10 findings, then 4, then 12)
each fixed the previous round's gaps by adding another artifact, command flag,
or exit state — a manifest, then `changelog.d/manifests/consumed/`, then
`--repair-manifest`, `history_truncated`, `not_assembled`, a per-release lock,
an owner-record file — and each addition reopened a new interruption window
of its own. That trend, not any single finding, is the signal that the
design was wrong, not merely incomplete: **the recovery apparatus had become
the dominant complexity in a plan whose actual job is putting each entry in
its own file.**

**Corrected**: `assemble` writes the version section into `CHANGELOG.md`
*and* deletes the fragment files that fed it, **in the same invocation**,
both as ordinary uncommitted working-tree edits. There is no manifest, no
`consume` command, no lock, and no separate "assembled but not consumed"
state to represent, because there is no longer a gap between the two
mutations for anything to sit in.

**Why no manifest.** Read literally, Protocol 05 already has exactly **one**
commit for this entire span. Its existing, unmodified Step 3 does the
editorial polish, the heading rename, and the link-reference definitions —
all in the working tree — and Step 5, immediately after Step 4's version
bump, is the *only* "Commit" step in the whole protocol. Nothing today
commits the assembled draft separately from the editorial pass; the working
tree simply sits, uncommitted, for however long the polish takes, exactly as
it always has. A manifest-based recovery model implicitly assumed assembly
and consumption were separated by an unknown, possibly-long span that needed
its own durability guarantee — but Protocol 05 was never designed that way,
and the previous round's fix (adding two brand-new commits inside Step 3 so
the manifest would have something to be "restored from") was solving a
problem this plan itself introduced, not one the protocol had. Once assembly
and deletion share a single working-tree edit that rides along on Protocol
05's *existing, unmodified* Step 5 commit, there is nothing for a manifest to
record that the commit's own diff doesn't already show.

**How the three spec rules hold, by construction, not by a state machine:**

1. **Gathering is repeatable.** `assemble --version <X.Y.Z>` checks exactly
   one fact: does `## [X.Y.Z] - YYYY-MM-DD` already exist in `CHANGELOG.md`?
   If yes, `ASSEMBLE_RESULT=already_assembled`, exit 0, no write — the
   idempotence guarantee, decidable from the working tree alone, no second
   artifact to cross-check. (See "Residual interruption window" below for the
   one narrow case this check alone does not fully close, and how it is
   closed without a new artifact.)
2. **Notes are consumed at publish, not at assembly.** `assemble` runs on
   the release branch's local working tree. Its edits — the new
   `CHANGELOG.md` section and the fragment deletions — are ordinary
   uncommitted changes until Protocol 05's existing Step 5 commits them,
   exactly like the editorial pass already is today. Nothing reaches
   `develop` or `main` until the release PR **merges**. Abandon the release
   (delete the branch, close the PR) and nothing was ever consumed, because
   the commit that would have deleted the fragments never reached a branch
   anyone reads from. "Published" is defined by the ordinary GitHub PR-merge
   event, not by which local script ran.
3. **A note recorded after assembly belongs to the next release.** In the
   ordinary case, a fragment added to `develop` after the release branch was
   cut is simply absent from that branch's tree — branches diverge, and the
   next release (cut from a later `develop`) picks it up naturally. In the
   rarer case of a fragment cherry-picked directly onto the *same* release
   branch after `assemble` already ran: the idempotence check (fact 1) fires
   before any directory scan, so a plain re-run of `assemble` reports
   `already_assembled` and never looks at `changelog.d/` again — the late
   fragment is untouched, stays in `changelog.d/`, and is picked up by the
   next assembly. It is included in *this* release only if the releaser
   deliberately discards the assembled state first (below, "There is no
   `--reassemble` flag") and re-runs `assemble` fresh — a human editorial
   choice, never something any part of `assemble` itself does automatically.

**Assembly, concretely.** When the heading does not yet exist, `assemble`:
validates every top-level fragment in `changelog.d/` (Decision 1's grammar);
builds the new section (Decision 4: rename `## [Unreleased]`, merge fragment
bullets by kind, carry over the existing shared-block bullets); writes
`CHANGELOG.md` via a temp file, `fsync`, and one atomic `rename(2)` call (kept
from the earlier design — it is one `mktemp`/`mv` pair, not a state machine,
and it means a process kill mid-write leaves `CHANGELOG.md` exactly at its
pre-assembly content, never truncated); then deletes each fragment file that
fed the section. It reports `ASSEMBLE_RESULT=assembled`, `VERSION`,
`FRAGMENT_COUNT`, `CARRIED_OVER_COUNT`, and `ITEMS` — the same reporting the
manifest previously existed partly to support, now emitted directly from the
one live scan `assemble` already performed, with nothing persisted to disk
for later inspection because nothing needs to be inspected later: the commit
diff is that record (see "Audit trail" below).

**Residual interruption window, and why it does not need a manifest.** A
process kill *between* the `CHANGELOG.md` write succeeding and the fragment
deletions finishing is still possible (deleting N small files is not one
atomic operation). Left unaddressed, a re-run's idempotence check would see
the heading and stop before finishing those deletions, permanently orphaning
the undeleted fragment — which a *later* release's assembly would then
gather again, publishing its bullet a second time.

**The sweep matches on the fragment's own body, not on the item reference.**
An earlier version of this fix matched by searching the published section for
`(#<item>)` — the item's tracker or PR-number reference. That is not precise
enough: this plan explicitly permits more than one fragment for the same
item (two notes from the same item "live on one branch," Decision 1), and in
no-tracker mode the body carries no `(#N)` at all, so there would be nothing
to match against. Matching on the item reference cannot distinguish "this
exact fragment's bullet was published" from "some fragment for this item was
published" — a second, still-pending fragment for the same item would match
and be wrongly deleted, exactly reproducing the loss the sweep exists to
prevent, just relocated to a same-item case instead of the interruption case.

The corrected check matches on **the fragment's own body**: `assemble`
normalizes each remaining fragment's body the same way `validate` already
does (CRLF to LF, trailing whitespace trimmed) and checks whether that exact
text — the complete bullet, including any continuation lines, as one
contiguous block — appears verbatim inside the already-published
`## [X.Y.Z]` section. Only then is the fragment deleted. This is precise by
construction, in every mode: two fragments for the same item necessarily
have different bodies (they are different bullets), so body matching tells
them apart where item-number matching could not; and no-tracker fragments
are matched the same way, since the check never depended on `(#N)` existing
in the first place. A fragment is only ever removed by this path if its own
content is already visible in the published section, so a genuinely late
fragment — for a new item, a second fragment on the same item, or a
no-tracker fragment — is never touched by it. Rule 3 still holds. This
closes the gap with a body-text comparison inside the idempotence check, not
a new command, file, exit code, or recovery flag.

**There is no `--reassemble` flag.** An earlier draft included one, to let
the releaser deliberately discard the published section and redo assembly
from a live rescan — but a CodeRabbit round found it non-transactional (it
deleted the existing section before validating and building the
replacement, so a failure between those two steps left `CHANGELOG.md`
without a section at all, and without one to restore from). Rather than add
the machinery to make deletion-then-rebuild safe (build the replacement
first, then swap it in — itself a second atomic-write path to design and
test), this plan asks whether the flag is still pulling its weight now that
there is no manifest for it to repair, and the answer is no: nothing is
committed until the releaser's own Step 5, so "discard and redo" is already
an ordinary git operation with no data at risk — `git checkout -- CHANGELOG.md
changelog.d/` before any commit, or `git revert`/`git reset` after one,
followed by a fresh `assemble` run, which naturally rescans because nothing
still claims `already_assembled`. Removing the flag deletes the
transactionality problem along with it, rather than solving it, and shrinks
the interface `assemble` presents to exactly one command with no redo path
to keep safe.

**Audit trail.** The spec's Operational Visibility principle — "released"
and "not yet released" visible from repository state rather than inferred —
holds directly from `changelog.d/`'s contents (a fragment present there is
not yet released) and from ordinary git history (`git show <commit>` on the
commit that deleted a fragment shows exactly what its bullet became). This is
a *stronger* audit trail than the manifest the earlier design added, because
it reuses git's native history instead of a bespoke, separately-maintained
file format.

**Why no lock — declined a third time, on the same grounds, now with the
specific failure mode named.** `assemble` is a single, synchronous,
sub-second shell invocation run by one releaser (human or one delegated
agent) in one working tree, and nothing it does is durable until that same
releaser's own Step 5 commit. A literal simultaneous double-invocation in
the same checkout — the only scenario a lock would guard against — is an
operator mistake (running the command twice in two terminals), not a
scheduled or expected occurrence, because Protocol 05 Step 3 does not
support two people cutting the same version at once: it is one releaser,
one release branch, run sequentially. This is not a new conclusion; it is
the same one reached earlier in this review, when the prior review round's
"serialize all mutations of `CHANGELOG.md`" and "define recovery for a
missing or partial lock owner record" findings led to removing the lock
Decision 3's earlier draft had built, and that removal was accepted. A
concrete failure mode was raised again for the same scenario: two
concurrent invocations could scan different pending sets, each write a
different `CHANGELOG.md` snapshot (the later atomic rename wins), and each
delete the fragments *it* gathered regardless of whether its own write
survived — so the losing invocation's fragments can be deleted without
their bullets surviving in the final file, and a later `git diff` cannot
prove a missing bullet was never assembled. That mechanism is real *if* the
precondition holds, but the precondition is exactly the scenario named
above: two invocations of `assemble --version X` against the *same
checkout* at overlapping instants. The protocol does not produce that
precondition; only an operator running the command twice by hand does, and
that operator has not yet committed anything when the interleaving would
happen, so the same `git status`/`git diff` review before Step 5 that
already catches a locally confusing `CHANGELOG.md` also catches this shape
of it — nothing distinguishes "confusing" from "silently missing a bullet"
from the releaser's point of view, since the reviewer would notice a
smaller assembled section than the confirmed pending count either way.
Building a per-release `mkdir` lock, an owner-record file, and staleness
detection to guard a race whose precondition the protocol does not permit,
and whose consequence is still caught before anything is committed, was
solving a problem `assemble`'s narrow, uncommitted window does not actually
create; Decision 3's earlier draft needed the lock only because it had
opened a much wider, commit-spanning window in the first place, and that
window is what was removed, not the underlying concern.

**If a fragment is edited between assembly and the release merging**, the
draft in `CHANGELOG.md` wins: it is what the releaser reviewed. The fragment
file is already deleted by that point, so there is nothing left to disagree
with it.

### Decision 4 — The transition release

Assembly performs, in one operation (Decision 3):

1. Rename the existing `## [Unreleased]` heading to `## [X.Y.Z] - YYYY-MM-DD`,
   preserving every bullet already under it. This is exactly the rename the
   releaser performs by hand today.
2. Merge the pending fragments' bullets into that same section, per kind:
   append to an existing `### Category` heading when one is present, and create
   the heading in canonical Keep a Changelog order (Added, Changed, Deprecated,
   Removed, Fixed, Security) when it is not.
3. Insert a fresh, empty `## [Unreleased]` heading above the new version
   section.
4. Delete each fragment file whose bullet was just merged in step 2.

Each entry appears exactly once because the carried-over bullets are **moved**
with the heading rather than copied, and each fragment is deleted in the same
pass that emits its bullet. Appending into an existing `### Category` rather
than creating a second one is also what keeps `check-changelog-duplicate-headers.sh`
passing on the assembled output.

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
- [ ] `assemble --version <X.Y.Z> [--date <YYYY-MM-DD>] [--allow-empty]` — the
      release-preparation command, and the **only** write path this helper
      has (Decision 3). There is no `--reassemble` flag (Decision 3). Checks
      run in this fixed order, so the outcomes are mutually exclusive by
      construction (Gate A):
      1. Validate every pending fragment. Any grammar or body failure is
         `ASSEMBLE_RESULT=invalid`, exit 1, regardless of the heading or
         shared-block state — a malformed fragment is never assembled and
         never mistaken for "nothing pending."
      2. Else, if `## [X.Y.Z] - YYYY-MM-DD` already exists in `CHANGELOG.md`:
         perform the residual-interruption sweep (delete any remaining
         fragment whose exact, normalized body already appears verbatim in
         that section — see Decision 3's "Residual interruption window"),
         then report `ASSEMBLE_RESULT=already_assembled`, exit 0, no
         `CHANGELOG.md` write.
      3. Else, if there is no pending fragment and the shared block is
         empty: `ASSEMBLE_RESULT=no_notes`, exit 3, unless `--allow-empty`.
      4. Else: build the version section (Decision 4), write `CHANGELOG.md`
         via temp file, `fsync`, and one atomic `rename(2)`, then delete each
         fragment that fed the section. `ASSEMBLE_RESULT=assembled`, exit 0.
      Emits `ASSEMBLE_RESULT`, `VERSION`, `FRAGMENT_COUNT`,
      `CARRIED_OVER_COUNT`, and `ITEMS`. (Spec AC-3, AC-5, AC-6, AC-7, AC-10;
      Decisions 3 and 4)
- [ ] Exit codes: `0` for `clean`, `assembled`, or `already_assembled`; `1`
      for a validation or assembly error; `3` for `no_notes` without
      `--allow-empty`; `64` for a usage error, matching
      `check-documentation-stage-alignment.sh`. There is no `consume`
      subcommand and no `CONSUME_RESULT` (Decision 3).
- [ ] Reporting on assembly names each contributing item, and reports bullets
      carried over from the shared block as a single unattributed group, per
      the spec's Operational Visibility section.

New directory:

- [ ] `changelog.d/README.md` — the filename grammar, the six kinds, the body
      convention (a complete markdown bullet including the `**Bold Title**
      (#N):` prefix, and the no-tracker exception that drops `(#N)`
      entirely — Decision 1), and a worked example. It is excluded from the
      fragment scan by name.

`changelog.d/` has no other new directory to create: Decision 3 introduces no
manifest, so there is nothing for a fresh downstream clone to be missing —
`README.md` alone is both the only new file and the reason the directory
exists on a fresh clone (git does not track empty directories).

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
      `assemble` rewriting `CHANGELOG.md`; without this the new automation
      falls back to the generic `scripts/development-workflow/**` = `high`
      policy row, one severity level below what its own risk rationale calls
      for.
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
      — restructure Step 3 into: assemble the draft (now also deletes the
      fragments it gathered — Decision 3); editorial pass (today's polish
      guidance retargeted at the assembled draft, unchanged in substance);
      link-reference definitions (unchanged). **No new commit is added
      anywhere in Step 3.** Step 5 remains the protocol's only "Commit" step,
      exactly as it is today, and now covers the assembled section, the
      fragment deletions, the editorial pass, and the version bump together —
      the same single commit Step 5 already produces, just with more of the
      release branch's changes folded into it. Extend Step 7.2's
      release-artifact validation with the one check that proves assembly
      ran: `## [X.Y.Z] - YYYY-MM-DD` is present in the merged `CHANGELOG.md`.
      (Spec AC-3, AC-4, AC-5, AC-6, AC-8)
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
7. After assembly, no fragment that fed the section remains in `changelog.d/`,
   and a repeat assembly produces no duplicate section — Spec AC-7.
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
- **Run** `node_modules/.bin/markdownlint-cli2`,
  `scripts/lint/markdown-heuristic-lint.py`, and
  `scripts/lint/check-changelog-duplicate-headers.sh` against every assembled
  fixture produced by the new suite — all three checks AC-9 requires, not
  only two of them — so lint conformance of the output is asserted by the
  suite itself rather than only observed in CI.

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
| 19 | A body line beginning with `## ` (any level-2 heading, not only `## [`) or `### ` | Rejected by `validate`, for the same reason as row 20: `check-changelog-duplicate-headers.sh` and `auto-tag-release.yml` re-parse `CHANGELOG.md` from scratch by matching `^## ` / `^### ` on raw lines, with no notion of "this line came from inside a fragment body." A verbatim-copied heading-shaped line — bracketed (`## [X]`) or not (`## Internal`) — would be interpreted as a real section or category boundary by every downstream consumer, even though the assembler's own single-pass boundary computation stays correct for that one run. Escaping (rather than rejecting) was considered and rejected: it would leave the releaser's rendered CHANGELOG.md containing an escaped artifact instead of the intended bullet, which is a worse outcome than asking the fragment's author to reword the line before assembly ever happens |
| 20 | Trailing whitespace on a body line | Rejected by `validate`, so it fails on the item's PR rather than producing an MD009 failure on the assembled changelog |

**Edge-case enumeration — changelog rewriting**

| # | Input | Required behaviour |
| --- | --- | --- |
| 21 | No `## [Unreleased]` heading | Rejected; the heading is a precondition that `auto-tag-release.yml` also depends on |
| 22 | Two `## [Unreleased]` headings | Rejected |
| 23 | Any fragment fails validation, regardless of whether `## [X.Y.Z]` already exists or the shared block is empty | `ASSEMBLE_RESULT=invalid`, exit 1 — validation is checked first (Gate A), so this is never overridden by `already_assembled` or `no_notes` |
| 24 | `## [X.Y.Z]` already present, every fragment valid | `ASSEMBLE_RESULT=already_assembled`, exit 0, no `CHANGELOG.md` write — the idempotence mechanism (Decision 3). Before returning, the residual-interruption sweep (row 32) still runs |
| 25 | Populated shared block plus pending fragments, every fragment valid | Both merged into one version section, each entry once, with no duplicate `### Category` heading; every merged fragment is deleted in the same pass |
| 26 | Populated shared block, zero fragments | Rename only — the pre-fragment behaviour, preserved. Nothing to delete |
| 27 | Empty shared block, zero fragments | `ASSEMBLE_RESULT=no_notes`, exit 3, unless `--allow-empty` |
| 28 | A kind present in fragments but absent from the shared block | Heading created in canonical Keep a Changelog order |
| 29 | Deterministic ordering | Bullets sorted by kind rank, then by the item field (numerically when it is all digits, lexicographically otherwise), then by full filename — so two runs on the same input produce identical bytes |
| 30 | `assemble` run twice in a row, no interruption in between | First run: `assembled`, writes the section, deletes every fragment that fed it. Second run: `already_assembled`, exit 0, no write — `changelog.d/` already has nothing left for that version to delete |
| 31 | `assemble` interrupted after the `CHANGELOG.md` rename succeeds but before every fed fragment is deleted | On the next run, the idempotence check (row 24) fires, then the residual-interruption sweep deletes any fragment still present whose exact, normalized body already appears verbatim in the published `## [X.Y.Z]` section — closing the gap without a rescan of "what should this release contain" (only "what does this section already say") |
| 32 | A second fragment for the same item as one already published, still pending when the sweep runs | Left untouched — the sweep matches the fragment's own body, not its item reference, so a same-item fragment whose bullet is *not* in the section is correctly distinguished from the one that already fed it |
| 33 | A fragment sitting in `changelog.d/` whose body does **not** appear in the published `## [X.Y.Z]` section, encountered during the sweep (including a no-tracker fragment, whose body carries no `(#N)` to match on in the first place) | Left untouched — this is what keeps the sweep from ever behaving like a rescan: a fragment is deleted only when its own content is already visible in the published section, never merely because the section exists or because another fragment for the same item is there |

**Suppression semantics**: not applicable. `changelog-fragments.sh` recognizes
no inline suppression directives. Declining to write a release note is
expressed by not creating a fragment, exactly as declining to edit
`CHANGELOG.md` is expressed today, and it is not a directive the parser reads.

### Concurrent-event-source addendum

**Not applicable**, and this is a corrected conclusion, not the original one.
`changelog-fragments.sh` is a single-threaded command-line helper with no
listeners, timers, sockets, or async queues, so every in-process async
concern is not applicable, as before. The concurrency between independent
item PRs is likewise not applicable to runtime synchronization — handled
structurally, by disjoint fragment file paths (Decision 1).

A prior draft of this plan additionally built a per-release `mkdir` lock, an
`owner` metadata file, and staleness-detection guidance for concurrent
*process* invocation, reasoning by analogy to
`prepare-release-post-merge-cleanup.sh`'s own lock. That reasoning no longer
applies, because the thing it was protecting no longer exists: the earlier
`assemble`/`consume` split left `CHANGELOG.md` and a manifest file mutated
across two separate commands and (after the previous round's fix) two
separate git commits, a multi-minute-to-multi-hour window in which a second
invocation could plausibly land. Decision 3's simplification collapses that
to one synchronous, sub-second `assemble` call, writing one file, that is not
durable until the *releaser's own* Step 5 commit — the same commit that
already exists, unmodified, in today's release process. A literal
simultaneous double-invocation in the same checkout is now an operator
mistake (two terminals, one command, at once), not a scheduled occurrence,
and its worst case — a locally confusing `CHANGELOG.md` — is caught by the
same `git status`/`git diff` review the releaser already performs before
Step 5 commits anything, exactly the posture today's *unmodified* editorial
pass already has. `prepare-release-post-merge-cleanup.sh`'s lock protects a
different, genuinely longer-lived, cross-invocation window (component
release cleanup coordinating across repositories); `assemble`'s window is not
that shape, and copying the precedent regardless was solving a problem this
design does not have.

---

## Complex Workflow Decision-Gate Matrix

This plan adds a workflow decision gate: `assemble` in Protocol 05, whose
behaviour depends on a small number of inputs and produces a small number of
distinct next actions — Decision 3's simplification is directly visible here
as the shrink from a two-command, manifest-driven gate pair to one gate with
five rows, and there is no longer a `--reassemble` row: Decision 3 removed
the flag. It also changes an existing gate: the release-note readiness
check.

### Gate A — `changelog-fragments.sh assemble`

**Evaluated in this order**, so the rows below are mutually exclusive by
construction — no input can match more than one row, because each row after
the first is qualified by every earlier row not matching:

1. `CHANGELOG.md` lacks exactly one `## [Unreleased]` heading.
2. Any pending fragment fails the grammar or body checks.
3. `## [X.Y.Z]` heading already present.
4. No pending fragment and an empty shared block.
5. Otherwise.

| Order | Gate inputs | Outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- | --- |
| 1 | `CHANGELOG.md` lacks exactly one `## [Unreleased]` heading | `error` (exit 1) | Repair the changelog before releasing | Protocol 05 Step 7.2 |
| 2 | Any fragment fails the grammar or body checks (checked before the heading or shared-block state is considered) | `invalid` (exit 1) | Fix the named fragment on `develop` and re-run; never assemble a partial set, and never report `already_assembled` or `no_notes` for an input that also has a malformed fragment | Protocol 05; `.github/workflows/markdown-lint.yml` |
| 3 | Every fragment valid; `## [X.Y.Z]` heading already present | `already_assembled` | No `CHANGELOG.md` write (the residual-interruption sweep may still delete leftover fragments — edge cases 31–33); continue | Same |
| 4 | Every fragment valid; heading absent; no pending fragment and an empty shared block | `no_notes` (exit 3) | Stop; either there is nothing to release or a fragment was lost. Pass `--allow-empty` only for a deliberate no-notes release | Same |
| 5 | Every fragment valid; heading absent; at least one pending fragment or a non-empty shared block | `assembled` | Continue to the editorial pass (Protocol 05 Step 3) | Protocol 05; `.claude/commands/prepare-release.md`; `.cursor/commands/prepare-release.md`; `.agents/skills/prepare-release/SKILL.md` |

There is no Gate B: Decision 3 removed `consume` as a distinct command, so
there is no second gate for it to define.

### Gate B — release-note readiness (changed, not added)

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
| This item's own release note | `changelog.d/1554.changed.per-item-release-notes.md` (content in Implementation Order Step 11) | Committed by the implementation PR |

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
| An entry is lost or duplicated at the transition release, which is the hardest failure to detect after the fact | Med | High | Design the transition first, not last (tracker handoff). Assembly **moves** the shared block by renaming its heading rather than copying bullets, so duplication requires a coding error rather than an oversight; edge cases 25, 26, and 28 are asserted by fixtures before any protocol text is written |
| The sweep misses a surface, leaving one agent instructed to edit `[Unreleased]` and reintroducing the conflict for whatever it builds | Med | High | The residual verification strategy below requires the implementation PR to re-run the repository-wide scan and account for every hit, either as changed or with a written no-change rationale |
| The risk classifier grades the implementation PR `high` because it touches `.github/workflows/`, blocking delegated merge under the `medium` ceiling | High | Low | Known and filed as #1565. Expect an explicit merge authorization request rather than treating it as a failure |
| File-level overlap with open PR #1589 on `.github/workflows/markdown-lint.yml` and `05b-graduate-development-protocol.md` | Med | Low | The edits are in disjoint regions (branch filters and a new top section, versus `paths:`/targets and Step 2.5). If #1589 merges first, rebase; the conflict, if any, is a normal two-region docs conflict, not the combinatorial one this item removes |
| A release-branch delete of a fragment races an edit of that same fragment on `develop` | Low | Low | Git reports a delete/modify conflict on one file owned by one item. Editing a note after its release is already a mistake; document the resolution (keep the deletion) in Protocol 94's `changelog.d/` clause |
| The residual-interruption sweep (edge cases 31–33) matches a fragment it should not, either deleting an unpublished same-item fragment or leaving an orphan behind | Low | Med | Edge cases 30–33 fixture the interruption, the same-item case, and the no-match case as red tests before the code exists (Implementation Order Steps 2 and 4); the sweep's correctness bar is exact-body matching, not item-reference matching, precisely because item-reference matching was tried and found imprecise in review |
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

There is no manifest file to sample: Decision 3 does not introduce one.

---

## Implementation Order

1. **Create the directory and its reference.** Add `changelog.d/README.md`
   documenting the grammar, the six kinds, and the body convention (including
   the no-tracker exception — Decision 1). No other file or directory is
   needed: Decision 3 introduces no manifest. (Decisions 1, 2, 7)

   *Verify*: `ls changelog.d` lists the README, and
   `node_modules/.bin/markdownlint-cli2 "changelog.d/README.md"` reports no
   violations.

2. **Write the test suite first, red.** Create
   `scripts/development-workflow/tests/test-changelog-fragments.sh` with one
   case per row of the three parser-risk tables (including edge cases 30–33,
   the interruption and residual-sweep cases), plus its `# covers:` header
   lines. Every case fails at this point because the helper does not exist.

   *Verify*: running the suite reports failures for every case and no case is
   silently skipped.

3. **Implement `validate` and `list`.** Filename grammar, body checks, and the
   reporting fields.

   *Verify*: the filename-grammar and fragment-body cases in the suite pass;
   the changelog-rewriting cases still fail.

4. **Implement `assemble`.** Precedence order (Gate A: invalid before
   already_assembled/no_notes/assembled); the idempotence check (does
   `## [X.Y.Z]` already exist); the residual-interruption sweep on that path,
   matching each remaining fragment's exact normalized body against the
   published section text, never its item reference (edge cases 31–33);
   otherwise: validate pending fragments, build the section (heading rename,
   per-kind merge, fresh empty `## [Unreleased]`, deterministic ordering),
   write `CHANGELOG.md` via temp file, `fsync`, and one atomic `rename(2)`,
   then delete every fragment that fed the section; and `no_notes`. There is
   no lock, no manifest, and no `--reassemble` flag to implement (Decision 3).

   *Verify*: the changelog-rewriting cases pass, and the suite's assembled
   fixtures are checked with `node_modules/.bin/markdownlint-cli2`,
   `markdown-heuristic-lint.py`, and `check-changelog-duplicate-headers.sh`
   inside the suite itself — all three AC-9 checks, not two. A case that
   kills the process after the `CHANGELOG.md` write but before every fed
   fragment is deleted, then re-runs `assemble`, confirms the sweep finishes
   the deletions and `CHANGELOG.md` is unchanged by the second run. A case
   with a genuinely unrelated fragment present during that same re-run
   confirms the sweep does not touch it. A case with a **second, still-pending
   fragment for the same item** as the one just published (edge case 32)
   confirms the sweep leaves it alone — proving the match is on body content,
   not the item reference. A case with a no-tracker fragment (no `(#N)` in
   its body) present during the same re-run confirms the sweep still
   correctly leaves it untouched when it was never published, and still
   correctly deletes it when it was.

5. **Wire the lint and CI surfaces.** Update
   `.github/workflows/markdown-lint.yml` (`paths:`, both independent
   file-discovery `find` blocks, the `markdownlint-cli2` glob list, and a
   `validate` step).

   *Verify*: `bash scripts/development-workflow/select-test-suites.sh
   --changed-files <file listing the changed paths>` lists
   `test-changelog-fragments.sh`; running the repository's markdown lint
   commands locally passes; and running `python3
   scripts/lint/markdown-heuristic-lint.py` against a file under
   `changelog.d/` confirms it is picked up (not just `markdownlint-cli2`).

6. **Update the release path.** Protocol 05 Step 3 (assemble — now also
   deletes the fragments it gathered — editorial pass, link definitions) and
   Step 7.2's artifact validation, then the three prepare-release command and
   skill surfaces. **No new commit is added anywhere in Protocol 05.** Step 5
   remains the protocol's only "Commit" step, unchanged, and now covers the
   assembled section, the fragment deletions, the editorial pass, and the
   version bump together, in the one commit it already produces today.

   *Verify*: read Step 3 end to end and confirm a releaser can execute it
   without consulting this plan, that the editorial pass still appears
   between assembly and the link-reference definitions, and that `git diff`
   on Protocol 05 adds no new "Commit" step anywhere before the existing
   Step 5.

7. **Update the implementation path.** Protocol 03 Paths 1–3, leaving Path 4
   untouched; then `.claude/agents/developer.md`,
   `.cursor/agents/developer.md`, `.cursor/rules/workflow.mdc`, and
   `.cursor/commands/implement-development.md`.

   *Verify*: `git diff` on Protocol 03 shows no change within the hotfix path,
   and the four agent surfaces carry the same instruction as each other.

8. **Update the orchestration and merge paths.** Protocol 90 Steps 3.6 and 5.1,
   Protocol 91's two parallel-batch paragraphs, Protocol 94 Step 4.3 per
   Decision 6, Protocol 05b Step 2.5, and the batch-merge command and skill
   surfaces. In `batch-merge.sh`, add the clarifying sentence to the
   `PR_HAS_CHANGELOG` header comment and the `changelog.d/` clause to the
   hold-annotation text; change no logic.

   *Verify*: `bash scripts/development-workflow/tests/test-batch-merge-changelog-race.sh`
   and the other batch-merge suites pass unchanged, confirming no behavioural
   change was introduced.

9. **Update the review contract and remaining documentation.** `REVIEW.md`,
   `LLM_RULES.md`, `.haystack/pr-rules.yml`, `.haystack/review-policy.md`
   (add `changelog.d/**` to the release-and-changelog-automation path list),
   the `haystack-reviewer.sh` comment block (including the corrected rule
   id), `haystack-triage.md`, `AGENTS.md`, `README.md`, both best-practices
   files, both script READMEs, the spec and plan protocols, the plan
   template, and `docs/testing/workflow/batch-merge.smoke-test.md`.

   *Verify*: `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
   passes, and the rule id quoted in the script matches an id present in
   `.haystack/pr-rules.yml`.

10. **Ship the convention downstream.** Add the `changelog.d/README.md` entry to
    `sync-manifest.yaml` under `always_sync` with `mode_scope: shared` and a
    note recording that fragment files are intentionally unlisted.

    *Verify*: `bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`
    passes, and reading the manifest confirms no `project_specific` entry was
    added for `changelog.d/`.

11. **Record this item's own release note the new way.** Create
    `changelog.d/1554.changed.per-item-release-notes.md` containing exactly:

    ```markdown
    - **Per-item release notes replace the shared `[Unreleased]` block** (#1554):
      each work item now records its release note in its own `changelog.d/` file,
      so two items worked in parallel no longer edit the same lines and cannot
      conflict. Release preparation gathers the pending notes into a draft
      version section and deletes the fragments in the same step; the releaser
      edits the draft before publishing, and the deletions become permanent
      only when the release merges.
    ```

    Do **not** add an entry to `CHANGELOG.md` — this PR is the change that ends
    that practice, and doing both would produce the duplicate the transition
    design exists to prevent.

    *Verify*: `bash scripts/development-workflow/changelog-fragments.sh validate`
    reports `VALIDATE_RESULT=clean` with the new fragment counted, and
    `git diff --name-only origin/develop...HEAD` does not list `CHANGELOG.md`.

12. **Run the residual verification** described in the next section and include
    its table in the PR description.

13. **Execute the smoke test runbook** at
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
