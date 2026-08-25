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
| Helper | `scripts/development-workflow/changelog-fragments.sh` |
| Rehearsal version | `9.9.9` (never released; used only for this runbook) |
| Scratch item identifiers | `9001`, `9002`, `9003` |

There is no manifest directory: `assemble` writes `CHANGELOG.md` and deletes
the fragments it gathered in the same invocation, so there is no second
artifact for this runbook to inspect.

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

1. From a scratch clone or worktree, create a local `base` branch from the
   branch under test: `git checkout -b base`.
2. From `base`, create `item-a` and switch to it: `git checkout -b item-a base`.
3. On `item-a`, add `changelog.d/9002.added.smoke-beta.md`; commit.
4. From `base`, create `item-b` and switch to it: `git checkout -b item-b base`.
5. On `item-b`, add `changelog.d/9003.fixed.smoke-gamma.md`; commit.
6. Check out `base` and merge `item-a` into it (`git merge item-a`).
7. Merge `item-b` into `base` (`git merge item-b`).

**Expected result**: neither merge reports a conflict, no manual resolution is
performed, and after both merges `base` contains both fragment files with
their original content. Discard `base`, `item-a`, and `item-b` (or the whole
scratch clone) once this step is done — they are not reused by later steps.

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

### Step 4: Assemble the draft — and its fragments are gone in the same step

**Maps to**: Acceptance Criteria 3, 7, and 10

1. Create and check out a scratch branch **from the branch under test** (so it
   carries the `9001.fixed.smoke-alpha.md` fragment from Step 1 and any
   fragments the real implementation already added):
   `git checkout -b smoke-test/1554-release-rehearsal`. Steps 4 through 7 all
   run on this branch; the "Last Step" discards it.
2. Record, by name, every fragment `list` currently reports as pending.
3. Run
   `bash scripts/development-workflow/changelog-fragments.sh assemble --version 9.9.9`.
4. Read the reported `FRAGMENT_COUNT`, `CARRIED_OVER_COUNT`, and `ITEMS`.
5. Open `CHANGELOG.md` and read the new `## [9.9.9]` section.
6. Run `git status --short` on `changelog.d/`, and confirm against the list
   from step 2.

**Expected result**: `ASSEMBLE_RESULT=assembled`. The version section groups
entries by kind and contains both every pending fragment's bullet and every
bullet that was previously in `## [Unreleased]`, each appearing once. A fresh,
empty `## [Unreleased]` heading sits above it. **Every fragment recorded in
step 2 is now gone from `changelog.d/`** — assembly deletes the fragments it
gathers in the same operation that writes the section (Decision 3); this is
the check that the two are inseparable, not that nothing was touched.

### Step 5: Assembly is repeatable

**Maps to**: Acceptance Criterion 7

1. Record the current contents of `CHANGELOG.md`.
2. Run the same `assemble --version 9.9.9` command a second time.
3. Compare `CHANGELOG.md` against the recording.

**Expected result**: `ASSEMBLE_RESULT=already_assembled`, exit 0, and
`CHANGELOG.md` is byte-identical to before the second run. No entry is
duplicated. There is nothing left in `changelog.d/` for this version to
delete, so the second run's residual-interruption sweep (Step 4's design,
Decision 3) is a no-op.

### Step 6: The releaser's edits survive an interruption, and a late note waits for the next release

**Maps to**: Acceptance Criteria 4, 5, 6, and 8

1. Edit the `## [9.9.9]` section by hand: merge two bullets and shorten a third,
   the way the release editorial pass does.
2. Add the `[9.9.9]` link-reference definition at the bottom of `CHANGELOG.md`
   and update the `[Unreleased]` definition, following Protocol 05 Step 3's
   link-reference sub-step.
3. Commit **everything** changed on the scratch branch so far — `CHANGELOG.md`
   *and* the fragment deletions Step 4's `assemble` already made (they are
   still sitting uncommitted; `git commit CHANGELOG.md` alone would leave
   those deletions behind): run `git add -A` then
   `git commit -m "rehearsal: assembled draft + editorial pass"`. This is
   what a real release branch looks like just before Protocol 05's Step 5
   commit, and it is what makes the next step a genuine resumption test
   rather than a dirty-working-tree no-op. (In the real protocol this is the
   *only* commit in the whole sequence — Step 5, unmodified. This rehearsal
   commits early purely to simulate the interruption in step 4 below; a real
   release preparation would still be sitting uncommitted at this point,
   exactly like today's editorial pass, and that is fine — see Known
   Limitations.)
4. Simulate an interruption: run `git status --porcelain` and confirm it
   prints nothing (step 3 committed everything on this branch; an empty
   result is what makes the switch below guaranteed-clean, not merely
   assumed clean), then switch to another branch and back.
5. Run `assemble --version 9.9.9` again — **after** the switch, so this
   actually exercises resumption rather than repeating an assembly that ran
   before any interruption was simulated.
6. Add a new fragment `changelog.d/9002.changed.smoke-late.md` (left
   uncommitted and untracked — it represents a note added to the release
   branch, e.g. via a late cherry-pick, after assembly already ran).
7. Run `assemble --version 9.9.9` a third time.
8. Run `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
   to verify the `[9.9.9]` and `[Unreleased]` link-reference definitions added
   in step 2 are both well-formed.
9. Read `CHANGELOG.md` and `changelog.d/`.

**Expected result**: step 5's post-interruption run reports `already_assembled`
without rewriting anything, and the hand edits (including the link-reference
definitions from step 2) are intact — verifiable because they are part of the
committed history, not just the working tree, so nothing was lost by the
interruption. Step 6's third run (item 7 above) also reports
`already_assembled`; the late fragment from item 6 above is present in
`changelog.d/` but absent from both the `## [9.9.9]` section and — because it
was never gathered — was never a candidate for deletion by the
residual-interruption sweep either. The duplicate-header and link-reference
checks (item 8) both pass (the one script performs both), so the changelog is
ready to accumulate the next release's notes and its version links resolve.

### Step 7: The published section passes the repository's document checks

**Maps to**: Acceptance Criterion 9

1. Run:

   ```bash
   npx markdownlint-cli2 "CHANGELOG.md"
   ```

2. Run:

   ```bash
   python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
   ```

3. Run:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

**Expected result**: all three exit 0 with no violations reported.

### Step 8: Published history is untouched

**Maps to**: Acceptance Criterion 13

1. Run `git diff` on `CHANGELOG.md` against the pre-assembly commit.
2. Read the diff hunks.

**Expected result**: every change is confined to the new `## [Unreleased]`
heading, the new `## [9.9.9]` section, and the link-reference definitions. No
line inside any previously published version section is added, removed, or
altered.

### Step 9: Hotfixes are unaffected

**Maps to**: Acceptance Criterion 11

1. Create and check out a separate, throwaway scratch branch — not
   `smoke-test/1554-release-rehearsal` — and follow Protocol 03 Path 4's
   changelog step on it: write a new versioned section directly below
   `## [Unreleased]`.
2. Run `bash scripts/development-workflow/changelog-fragments.sh list`.
3. Read Protocol 03 Path 4 and confirm no step instructs the author to write a
   fragment.
4. **Before switching away**, discard the uncommitted hotfix edit on this
   branch — its content is not needed by any later step: run
   `git checkout -- CHANGELOG.md`, then `git status --porcelain` and confirm
   it prints nothing.
5. Now switch and discard the branch itself:
   `git checkout <branch under test> && git branch -D <the throwaway branch>`.

**Expected result**: the hotfix section is written directly into `CHANGELOG.md`,
the pending-note list is unchanged by it, and the hotfix path's instructions are
identical to the pre-change version.

### Step 10: Readiness accepts a fragment

**Maps to**: Acceptance Criterion 2

1. Open Protocol 90's Step 5.1 artifact table and read the release-note row,
   and the [implementation plan's Decision 5](../../specs/developments/20260821080421_1554-changelog-fragments/2_1554-changelog-fragments_implementation-plan.md#decision-5--readiness-checks-that-must-accept-a-fragment)
   for the exact pass condition.
2. Against a real `feature/*`, `fix/*`, or `refactor/*` implementation PR that
   carries a fragment and no `CHANGELOG.md` change, run:

   ```bash
   gh pr view <pr_number> --json files --jq \
     '[.files[].path] | any(test("^changelog\\.d/[A-Za-z0-9][A-Za-z0-9_-]*\\.(added|changed|deprecated|removed|fixed|security)\\.[a-z0-9][a-z0-9-]*\\.md$"))'
   ```

**Expected result**: the query returns `true`, so the PR satisfies the
release-note readiness check without having edited the shared changelog.

### Step 11: A fresh consumer needs no setup

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

1. Commit or discard any remaining uncommitted change on the rehearsal branch
   (Step 6 leaves the late fragment `changelog.d/9002.changed.smoke-late.md`
   untracked): switch to `smoke-test/1554-release-rehearsal`, run
   `git status --short`, and resolve anything it reports before the next
   step, so the branch switch below cannot be refused or carry rehearsal
   state forward. (Step 9 uses its own separate scratch branch for the
   hotfix scenario and is unaffected by this step.)
2. Check out the branch under test, then delete the scratch branch
   (`git branch -D smoke-test/1554-release-rehearsal`) — this removes the
   scratch branch's own committed history, including the rehearsal
   `## [9.9.9]` section.
3. Branch deletion does not remove untracked files. From the branch under
   test, remove exactly the rehearsal artifacts by name — never a directory
   glob, which could delete files this runbook did not create:

   ```bash
   rm -f changelog.d/9001.fixed.smoke-alpha.md \
         changelog.d/9001.improved.smoke-bad.md \
         changelog.d/9001.fixed.smoke-bad.md \
         changelog.d/9002.added.smoke-beta.md \
         changelog.d/9002.changed.smoke-late.md \
         changelog.d/9003.fixed.smoke-gamma.md
   ```

   Before running it, run
   `git status --short --ignored -- 'changelog.d/900*'`. Plain
   `git status --short` does not list ignored files, so an ignored file that
   happens to share one of the six names above would pass a narrower check
   and still be deleted by `rm -f`; `--ignored` closes that. Confirm every
   path it lists is one of the six above — if anything else appears
   (including an `!! ` ignored-file line), stop and remove files by hand
   instead of running the command.
4. Run `git status` and confirm the working tree matches the branch under test.
5. Run `bash scripts/development-workflow/changelog-fragments.sh list` and
   confirm the pending count matches Step 0's recording.

---

## Assertions Checklist

The canonical acceptance criteria live in the
[spec's Acceptance Criteria section](../../specs/developments/20260821080421_1554-changelog-fragments/1_1554-changelog-fragments_specs.md#acceptance-criteria)
(AC-1 through AC-13, in spec order); this checklist tracks execution against
each one without restating its full text, to avoid the two documents drifting
apart.

- [ ] AC-1 — no merge conflict, both notes survive (Step 2)
- [ ] AC-2 — readiness passes on a fragment alone (Steps 1 and 10)
- [ ] AC-3 — assembly gathers every pending note, grouped by kind (Step 4)
- [ ] AC-4 — editorial edits survive to publication (Step 6)
- [ ] AC-5 — interrupted-then-resumed preparation loses nothing (Step 6)
- [ ] AC-6 — a post-assembly note waits for the next release (Step 6)
- [ ] AC-7 — no duplicate entries after a repeat assembly (Steps 4 and 5)
- [ ] AC-8 — changelog and version links are ready for the next release (Step 6)
- [ ] AC-9 — the published section passes existing document checks (Steps 3 and 7)
- [ ] AC-10 — transition release merges shared-block and per-item notes once each (Step 4)
- [ ] AC-11 — the hotfix path is unaffected (Step 9)
- [ ] AC-12 — a fresh consumer needs no setup (Step 11)
- [ ] AC-13 — published history is unchanged (Step 8)

---

## Seed Data Reference

The following seed data must be present:

| Entity | Scenario | How to load |
| --- | --- | --- |
| Scratch fragments `9001`, `9002`, `9003` | Valid notes across several kinds, plus two deliberately malformed ones | Created by hand in Steps 1, 2, 3, and 6 |
| Populated shared block | The transition-release case | Present on `develop` until the first release after this change merges; recreate by hand in a scratch branch afterwards |
| Rehearsal version `9.9.9` | Assembly without touching a real release | Passed with `--version` in Steps 4 through 6 |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `VALIDATE_RESULT=invalid` naming a file you did not create | A stray non-markdown file or a leftover rehearsal fragment in `changelog.d/` | Remove it; only fragments and `README.md` belong at the top level of `changelog.d/` |
| `ASSEMBLE_RESULT=already_assembled` when you expected a fresh draft | The version section already exists from an earlier run | Intended behaviour. There is no `--reassemble` flag (Decision 3). To deliberately redo the section, discard the assembled state first — `git checkout -- CHANGELOG.md changelog.d/` if nothing is committed yet, or `git revert`/`git reset` if it is — accepting that this loses the editorial pass, then re-run `assemble` |
| `ASSEMBLE_RESULT=no_notes` | Nothing is pending and the shared block is empty | Confirm the notes were not already assembled by an earlier release before reaching for `--allow-empty` |
| A fragment you expected `assemble` to gather is still present in `changelog.d/` after a run that reported `assembled` | It arrived after that run started (a late cherry-pick or a fresh scan started before the fragment landed) | Correct behaviour, not a bug — Decision 3 requires a note recorded after assembly to wait for the next release. To deliberately include it now, discard the assembled state (see the `already_assembled` row above) and re-run `assemble` fresh |
| A `changelog.d/` path appears in a merge conflict | Two branches used the same item identifier | Treat as non-trivial per Protocol 94; find out which branch is misnamed rather than combining the files |
| Duplicate `### Category` headings after assembly | A defect in the per-kind merge | Report against this feature; `check-changelog-duplicate-headers.sh` is the detector |

---

## Known Limitations

- Steps 4 through 6 rehearse a release using version `9.9.9` rather than
  cutting a real one. A genuine release additionally opens the production and
  backport PRs, which this runbook does not exercise; Protocol 05's own steps
  cover that.
- Step 6 commits the assembled draft and the editorial pass on the scratch
  branch before simulating the interruption, so the interruption-and-resume
  behaviour this runbook exercises is "resume on a different clone or after
  the local working tree is lost." A real release preparation more often sits
  uncommitted through the whole of Protocol 05's existing Step 3 — exactly
  like today's manual editorial pass already does — and resumes simply by
  returning to the same working tree, with no git operation involved at all.
  Both cases are covered by the design (Decision 3); this runbook exercises
  the git-level one because it is the one that needs a "does it actually
  work" check, not the trivial one.
- The one narrow interruption window Decision 3 still names — a process
  killed after the `CHANGELOG.md` write but before every fed fragment is
  deleted — is exercised by the implementation's automated test suite
  (edge cases 30–31), not by this runbook: reliably killing a process
  mid-loop is not something a manual runbook can script.
- Step 11's downstream check inspects a fresh clone of this repository.
  Verifying a real consumer project requires a sync-template run in that
  project, which is outside this runbook's scope.
- The transition-release case (Step 4 with a populated shared block) can be
  exercised faithfully only once against real data. Afterwards it must be
  reproduced with a hand-built fixture, which is why the implementation's test
  suite asserts it rather than relying on this runbook.
