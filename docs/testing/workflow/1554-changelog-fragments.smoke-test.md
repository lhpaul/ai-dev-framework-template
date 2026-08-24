# Smoke Test Runbook: Changelog Fragments

**Feature**: Per-item release notes assembled at release time
**Spec**: [1_1554-changelog-fragments_specs.md](../../specs/developments/20260821080421_1554-changelog-fragments/1_1554-changelog-fragments_specs.md)
**Implementation plan**: [2_1554-changelog-fragments_implementation-plan.md](../../specs/developments/20260821080421_1554-changelog-fragments/2_1554-changelog-fragments_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch is checked out and `changelog.d/` exists
- [ ] `bash`, `git`, `python3`, and `node_modules/` are available in the repository
- [ ] A scratch clone or worktree is available for the merge exercise in Step 2,
      so no shared branch is disturbed
- [ ] No release is currently in preparation on the branch under test

There is no running application, no database, and no login step: this feature is
repository tooling, and every step below is executed from a shell at the
repository root.

---

## Test Data

| Item | Value |
| --- | --- |
| Fragment directory | `changelog.d/` |
| Manifest directory | `changelog.d/manifests/` |
| Helper | `scripts/development-workflow/changelog-fragments.sh` |
| Rehearsal version | `9.9.9` (never released; used only for this runbook) |
| Scratch item identifiers | `9001`, `9002`, `9003` |

---

## Design assets

None discovered for this item. The issue body carries no `## Design assets`
section, the tracker item has no attachments, and the development folder has no
`assets/` directory, so this runbook contains no visual fidelity step.

---

## Smoke Test Steps

### Step 0: Establish a clean starting point

1. From the repository root, run `git status` and confirm the working tree is clean.
2. Run `bash scripts/development-workflow/changelog-fragments.sh list`.
3. Record the reported `PENDING_COUNT` — later steps compare against it.

**Expected result**: the command exits 0 and reports a pending count. `README.md`
is not reported as a pending note.

### Step 1: Record a release note without touching the changelog

**Maps to**: Acceptance Criteria 1 and 2

1. Create `changelog.d/9001.fixed.smoke-alpha.md` containing a single bullet in
   the documented body format, including an issue reference.
2. Run `bash scripts/development-workflow/changelog-fragments.sh validate`.
3. Run `git status --short` and confirm `CHANGELOG.md` is unmodified.

**Expected result**: `VALIDATE_RESULT=clean`, the fragment count is one higher
than Step 0's, and the only changed path is the new fragment.

### Step 2: Two items in parallel, no conflict

**Maps to**: Acceptance Criterion 1

1. From a scratch clone or worktree, create two branches from the same base.
2. On the first, add `changelog.d/9002.added.smoke-beta.md`; commit.
3. On the second, add `changelog.d/9003.fixed.smoke-gamma.md`; commit.
4. Merge the first branch into the base.
5. Merge the second branch into the base.

**Expected result**: neither merge reports a conflict, no manual resolution is
performed, and after both merges the base contains both fragment files with
their original content.

### Step 3: Malformed notes are rejected at the item's own PR

**Maps to**: Acceptance Criterion 9

1. Create `changelog.d/9001.improved.smoke-bad.md` with a valid bullet body.
2. Run `bash scripts/development-workflow/changelog-fragments.sh validate`.
3. Delete that file, then create `changelog.d/9001.fixed.smoke-bad.md` whose
   first line is a plain sentence rather than a bullet.
4. Run `validate` again, then delete the file.

**Expected result**: both runs exit non-zero with `VALIDATE_RESULT=invalid`, and
each names the offending path and the reason — an unrecognized kind in the first
case, a non-bullet body in the second.

### Step 4: Assemble the draft

**Maps to**: Acceptance Criteria 3 and 10

1. On a scratch branch, run
   `bash scripts/development-workflow/changelog-fragments.sh assemble --version 9.9.9`.
2. Read the reported `FRAGMENT_COUNT`, `CARRIED_OVER_COUNT`, and `ITEMS`.
3. Open `CHANGELOG.md` and read the new `## [9.9.9]` section.
4. Open `changelog.d/manifests/v9.9.9.txt`.
5. Run `git status --short` on `changelog.d/`.

**Expected result**: `ASSEMBLE_RESULT=assembled`. The version section groups
entries by kind and contains both every pending fragment's bullet and every
bullet that was previously in `## [Unreleased]`, each appearing once. A fresh,
empty `## [Unreleased]` heading sits above it. The manifest names exactly the
fragments that contributed. **No fragment file has been deleted or modified** —
this is the check that assembly destroys nothing.

### Step 5: Assembly is repeatable

**Maps to**: Acceptance Criterion 7

1. Record the current contents of `CHANGELOG.md`.
2. Run the same `assemble --version 9.9.9` command a second time.
3. Compare `CHANGELOG.md` against the recording.

**Expected result**: `ASSEMBLE_RESULT=already_assembled`, exit 0, and
`CHANGELOG.md` is byte-identical to before the second run. No entry is
duplicated.

### Step 6: The releaser's edits survive, and a late note waits for the next release

**Maps to**: Acceptance Criteria 4, 5, and 6

1. Edit the `## [9.9.9]` section by hand: merge two bullets and shorten a third,
   the way the release editorial pass does.
2. Add a new fragment `changelog.d/9002.changed.smoke-late.md`.
3. Run `assemble --version 9.9.9` again.
4. Simulate an interruption: switch to another branch and back.
5. Read `CHANGELOG.md` and `changelog.d/`.

**Expected result**: the hand edits are intact, the run reports
`already_assembled` without rewriting anything, and the late fragment is present
in `changelog.d/` but absent from both the `## [9.9.9]` section and the
manifest. Nothing was lost by the interruption.

### Step 7: Publish consumes the notes

**Maps to**: Acceptance Criteria 5, 7, and 8

1. Run `bash scripts/development-workflow/changelog-fragments.sh consume --version 9.9.9`.
2. List `changelog.d/` and `changelog.d/manifests/`.
3. Run `consume --version 9.9.9` a second time.
4. Add the `[9.9.9]` link-reference definition at the bottom of `CHANGELOG.md`
   and update the `[Unreleased]` definition, following Protocol 05.
5. Run `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`.

**Expected result**: `CONSUME_RESULT=consumed` with a removed count matching the
manifest. Every manifest-listed fragment and the manifest itself are gone; the
late fragment from Step 6 remains. The second run reports `already_consumed` and
exits 0. The duplicate-header and link-reference checks both pass, so the
changelog is ready to accumulate the next release's notes and its version links
resolve.

### Step 8: The published section passes the repository's document checks

**Maps to**: Acceptance Criterion 9

1. Run the repository's `markdownlint-cli2` command over the changelog.
2. Run `python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`.
3. Run `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`.

**Expected result**: all three exit 0 with no violations reported.

### Step 9: Published history is untouched

**Maps to**: Acceptance Criterion 13

1. Run `git diff` on `CHANGELOG.md` against the pre-assembly commit.
2. Read the diff hunks.

**Expected result**: every change is confined to the new `## [Unreleased]`
heading, the new `## [9.9.9]` section, and the link-reference definitions. No
line inside any previously published version section is added, removed, or
altered.

### Step 10: Hotfixes are unaffected

**Maps to**: Acceptance Criterion 11

1. Follow Protocol 03 Path 4's changelog step on a scratch branch: write a new
   versioned section directly below `## [Unreleased]`.
2. Run `bash scripts/development-workflow/changelog-fragments.sh list`.
3. Read Protocol 03 Path 4 and confirm no step instructs the author to write a
   fragment.

**Expected result**: the hotfix section is written directly into `CHANGELOG.md`,
the pending-note list is unchanged by it, and the hotfix path's instructions are
identical to the pre-change version.

### Step 11: Readiness accepts a fragment

**Maps to**: Acceptance Criterion 2

1. Open Protocol 90's Step 5.1 artifact table and read the release-note row.
2. Against a real implementation PR that carries a fragment and no
   `CHANGELOG.md` change, run the row's documented query.

**Expected result**: the query returns `true`, so the PR satisfies the
release-note readiness check without having edited the shared changelog.

### Step 12: A fresh consumer needs no setup

**Maps to**: Acceptance Criterion 12

1. Clone the repository into a fresh directory, or inspect a downstream project
   that has synced the template.
2. Confirm `changelog.d/README.md` and
   `scripts/development-workflow/changelog-fragments.sh` are present.
3. Create a fragment following only the README's instructions and run `validate`.
4. Read `sync-manifest.yaml` and confirm `changelog.d/README.md` is listed under
   `always_sync` and that no entry claims the fragment files themselves.

**Expected result**: the fragment validates on the first attempt with no
configuration, no directory creation, and no manifest edit.

### Last Step: Restore the working tree

1. Discard the scratch branch, the rehearsal `## [9.9.9]` section, and every
   `9001`, `9002`, and `9003` fragment.
2. Run `git status` and confirm the working tree matches the branch under test.
3. Run `bash scripts/development-workflow/changelog-fragments.sh list` and
   confirm the pending count matches Step 0's recording.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] Two items completed at the same time merge one after the other with no
      conflict, and both notes are present afterward (Step 2)
- [ ] A pull request recording a note the new way passes the release-note
      readiness check without editing the shared changelog (Steps 1 and 11)
- [ ] Preparing a release gathers every unreleased note into a draft version
      section grouped by kind, with none missing (Step 4)
- [ ] The releaser can edit the assembled draft, and the published section
      reflects those edits (Steps 6 and 7)
- [ ] A release preparation interrupted after assembly resumes with no note lost
      and the edits intact (Step 6)
- [ ] A note recorded after assembly is absent from that release and available
      for the next one (Step 6)
- [ ] After the release no consumed note remains, and running assembly again
      produces no duplicate entries (Steps 5 and 7)
- [ ] After publishing, the changelog is ready for the next release and every
      version link resolves (Step 7)
- [ ] The published version section passes the repository's existing document
      checks (Steps 3 and 8)
- [ ] A release cut during the transition includes both the shared-block notes
      and the per-item notes, each exactly once (Step 4)
- [ ] An urgent production fix still writes its own versioned section and is
      unaffected by gathering (Step 10)
- [ ] A project created from this template records release notes the new way
      without additional setup (Step 12)
- [ ] The changelog's existing published history is unchanged (Step 9)

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Scratch fragments `9001`, `9002`, `9003` | Valid notes across several kinds, plus two deliberately malformed ones | Created by hand in Steps 1, 2, 3, and 6 |
| Populated shared block | The transition-release case | Present on `develop` until the first release after this change merges; recreate by hand in a scratch branch afterwards |
| Rehearsal version `9.9.9` | Assembly and consumption without touching a real release | Passed with `--version` in Steps 4 through 7 |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `VALIDATE_RESULT=invalid` naming a file you did not create | A stray non-markdown file or a leftover rehearsal fragment in `changelog.d/` | Remove it; only fragments, `README.md`, and the manifests directory belong there |
| `ASSEMBLE_RESULT=already_assembled` when you expected a fresh draft | The version section already exists from an earlier run | Intended behaviour. Use `--reassemble` only if you accept losing the editorial pass on that section |
| `ASSEMBLE_RESULT=no_notes` | Nothing is pending and the shared block is empty | Confirm the notes were not consumed by an earlier release before reaching for `--allow-empty` |
| `CONSUME_RESULT=manifest_missing` | `consume` ran before `assemble`, or on the wrong branch | Run `assemble` first, and confirm you are on the release branch |
| A `changelog.d/` path appears in a merge conflict | Two branches used the same item identifier | Treat as non-trivial per Protocol 94; find out which branch is misnamed rather than combining the files |
| Duplicate `### Category` headings after assembly | A defect in the per-kind merge | Report against this feature; `check-changelog-duplicate-headers.sh` is the detector |

---

## Known Limitations

- Steps 4 through 7 rehearse a release using version `9.9.9` rather than cutting
  a real one. A genuine release additionally opens the production and backport
  PRs, which this runbook does not exercise; Protocol 05's own steps cover that.
- Step 12's downstream check inspects a fresh clone of this repository. Verifying
  a real consumer project requires a sync-template run in that project, which is
  outside this runbook's scope.
- The transition-release case (Step 4 with a populated shared block) can be
  exercised faithfully only once against real data. Afterwards it must be
  reproduced with a hand-built fixture, which is why the implementation's test
  suite asserts it rather than relying on this runbook.
