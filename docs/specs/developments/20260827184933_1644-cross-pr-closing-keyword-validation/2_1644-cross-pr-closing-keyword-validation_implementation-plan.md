# Cross-PR Closing Keyword Validation — Implementation Plan

**Spec**: [`1_1644-cross-pr-closing-keyword-validation_specs.md`](./1_1644-cross-pr-closing-keyword-validation_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md`](../../../testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md)

---

## Summary

**Approach**: One new script, `scripts/development-workflow/validate-closing-keyword-scope.sh`, decides the outcome for a single pull request and is the only place the rules live. It reuses the canonical filter from `post-merge-cleanup.sh` verbatim rather than reimplementing it, so parity is structural rather than promised. One new workflow, `.github/workflows/closing-keyword-scope.yml`, routes `pull_request_target` events to it — for the triggering pull request, and, on a sibling's lifecycle event, for the open pull requests whose descriptions declare that sibling's issue. Reporting is a single updated-in-place comment; the indeterminate outcome is a `neutral` check run.

**Estimated complexity**: L

**Rationale**: The rule set is large — roughly sixty acceptance criteria across eight groups — and three of them are hard in their own right: byte-exact filtering parity with an existing parser whose behaviour differs by base branch, an indeterminate-versus-clean distinction that must hold for *every* input without enumeration, and an ordering guarantee across overlapping workflow runs. None of the individual pieces is large; the plan is L because the correctness surface is.

**Dependencies**: None. #1593 (merged, `1b6b3443`) added `push_verification_failed` and the self-refspec push rules; this feature touches neither.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `1b6b3443` |
| Canonical filter location | `grep -n 'strip_fenced_pr_body_blocks' scripts/development-workflow/post-merge-cleanup.sh` | Defined at line 564; invoked by `fetch_pr_closing_issues` at lines 679 (title+body) and 683 (commit messages) |
| Canonical keyword regex | `grep -n 'close\[sd\]' scripts/development-workflow/post-merge-cleanup.sh` | `(^\|[^[:alnum:]_])(close[sd]?\|fix(es\|ed)?\|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+` |
| Canonical concatenation for non-default-branch merges | `grep -n 'json body,title' scripts/development-workflow/post-merge-cleanup.sh` | `(.title // "") + "\n" + (.body // "")` — title and body are one text before filtering |
| Branch issue-number forms | `grep -n 'A-Z\]\[A-Z0-9\]' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | `^(feature\|fix\|refactor\|hotfix)/([A-Z][A-Z0-9]*-)?<N>(-\|$)` at line 581 — bare and team-prefixed |
| Idempotent label creation precedent | `grep -n 'ensure_reviewer_failed_label_exists' -A 12 scripts/development-workflow/pr-review-loop.sh` | Line 7488: `gh label view` then `gh label create`, warning and continuing on failure |
| Existing workflow style and permissions | `grep -n 'permissions:' -A 5 .github/workflows/pr-policy.yml` | Line 51: `actions: write`, `issues: write`, `pull-requests: write`, `statuses: write`; API-only, no checkout of PR code |
| Repository uses commit statuses, not check runs, for its own signals | `grep -rn 'statuses/' .github/workflows/*.yml` | Three call sites in `pr-policy.yml`; no workflow creates a check run |
| Does a commit status support a neutral state? | GitHub commit-status states are `error`, `failure`, `pending`, `success` | **No.** The spec's neutral, non-blocking conclusion requires the Checks API, so this workflow needs `checks: write` — the first in the repository |
| Is there a `pull_request_target` type for a branch rename? | GitHub `pull_request` / `pull_request_target` activity types | **No `renamed` type exists.** See *Declared trigger gaps* |
| Is there an Actions event for a default-branch change? | GitHub Actions event list | **None exists.** See *Declared trigger gaps* |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Canonical filtering semantics for closing keywords | `strip_fenced_pr_body_blocks` in `post-merge-cleanup.sh` | The script itself, read at plan time | 2026-09-02, repo SHA `1b6b3443` | This item only; no open PR changes that parser | `Verified` |
| Approved base branch for this plan's PR | `develop` | Bounded prelude for #1644 (`baseReason: no integration branch label`) | 2026-09-02, repo SHA `1b6b3443` | This item only | `Verified` |
| Repository writes are commit statuses today; this feature introduces the first check run | `pr-policy.yml` uses `repos/$REPO/statuses/$sha` | `.github/workflows/pr-policy.yml` lines 105, 377, 442 | 2026-09-02, repo SHA `1b6b3443` | This item only | `Verified` |

---

## Layer-by-Layer Changes

### Backend / API

- [ ] **`scripts/development-workflow/validate-closing-keyword-scope.sh`** (new; shell contract `bash`, it is an executable script rather than documentation guidance). Single entry point: `validate-closing-keyword-scope.sh <pr_number> <owner> <repo>`. Decides and publishes the outcome for one pull request. Every rule below lives here, not in the workflow YAML, so the logic is testable without GitHub. *Acceptance criteria: all groups.*
- [ ] **Reuse, do not reimplement, the canonical filter.** Extract `strip_fenced_pr_body_blocks` from `post-merge-cleanup.sh` into `scripts/development-workflow/closing-keyword-lib.sh`, and source it from both. The extraction must be byte-identical — move, not rewrite — so the two can never drift. *Acceptance criteria: Which keywords count as live.*
- [ ] **Base-branch-dependent filtering.** Read the PR's base and the repository's default branch. When the base **is** the default branch, filter the description alone. Otherwise, filter `title + "\n" + description` as one text, exactly as `fetch_pr_closing_issues` does. *Acceptance criteria: Which keywords count as live (title-fence rows).*
- [ ] **Report from the description only, with a boundary sentinel.** In the concatenated case, insert a sentinel line between title and description before filtering, and report only keywords found after it. If the sentinel does not survive filtering, the title opened a construct that swallowed the description too, so there is nothing to report and the run is silent — which is the required outcome for that row. *Acceptance criteria: a closing keyword that appears only in the title is not reported; the title-fence rows.*
- [ ] **Ownership resolution.** List open pull requests, keep those whose head branch matches `^(feature|fix|refactor|hotfix|backport/hotfix)/([A-Z][A-Z0-9]*-)?<issue>(-|$)`, and apply the four ownership rules: none → silent for that issue; two or more → contested, silent; self → in scope, silent; exactly one other → reported. Platform-derived issue links are never consulted. *Acceptance criteria: Establishing ownership.*
- [ ] **Opt-out.** Skip reporting when the PR carries `multi-issue-intentional`. Provision the label idempotently on first use with the `ensure_reviewer_failed_label_exists` pattern; a failed creation warns in the report and never suppresses it. *Acceptance criteria: The opt-out.*
- [ ] **Indeterminate outcome, stated over the input set rather than a list.** Read every gate input through one accessor that appends the input's name and its read status to **two parallel indexed arrays** — not an associative array, which is Bash 4+ and this repository targets Bash 3.2 (macOS system bash). The outcome is indeterminate when any recorded status is a failure, so an input added later is covered by construction rather than by extending a list. On indeterminate: leave any existing report untouched, post nothing, write a `neutral` check run naming every input that could not be read. *Acceptance criteria: The indeterminate outcome.*
- [ ] **Freshness and ordering.** Re-read the inputs immediately before writing and discard if any moved (freshness). Stamp each published report and check run with the run's start time and run id, and refuse to overwrite one stamped by a later-started run (ordering). *Acceptance criteria: Ordering and idempotence.*
- [ ] **Fork guard.** Compare `head.repo.full_name` with the target repository and exit before any write when they differ. *Acceptance criteria: Fork-originated pull requests.*

### Shared Packages / Libraries

- [ ] **`scripts/development-workflow/closing-keyword-lib.sh`** (new): the extracted canonical filter plus the keyword regex, sourced by `post-merge-cleanup.sh` and the new validator. `post-merge-cleanup.sh` keeps its current behaviour; this is a move with a `source` added.

### Infrastructure / Configuration

- [ ] **`.github/workflows/closing-keyword-scope.yml`** (new). `pull_request_target` types `opened, reopened, edited, labeled, unlabeled, closed, ready_for_review`. API-only, no checkout of pull request code, following `pr-policy.yml`'s shape. Permissions: `pull-requests: write` (comment), `issues: write` (label creation), `checks: write` (the neutral conclusion — the first check-run writer in this repository), `contents: read`.
- [ ] **Sibling fan-out.** On `opened`, `reopened` and `closed` for an implementation branch, resolve the issue its branch names and re-run the validator for each open pull request whose description declares that issue. The fan-out is bounded by the open pull request list and each target is validated by the same single-PR entry point.
- [ ] **Concurrency.** `concurrency: group: closing-keyword-scope-<pr>` with `cancel-in-progress: false`, so writes for one pull request are serialized. Ordering across serialized runs is still enforced in the script, because a cancelled or duplicated delivery can still finish out of order.

---

## Declared trigger gaps (alignment decision: option B, 2026-09-02)

The spec lists triggers that GitHub Actions cannot deliver. The human chose to cover what exists and record the rest rather than add a scheduled sweep. These are gaps in *timeliness*, not in correctness: the result is recomputed correctly at the next event that does fire, and the readiness backstop bounds the staleness for any pull request heading for review.

| Spec trigger | Status | Consequence |
| --- | --- | --- |
| The pull request's own head branch is renamed | **Not delivered.** `pull_request_target` has no `renamed` activity type | A rename that flips ownership is reflected at the next edit, label change, or readiness event |
| A sibling is renamed into or out of naming an issue | **Not delivered**, same reason | Same |
| The repository's default branch changes | **Not delivered.** Actions has no event for it | Pull requests keep the filtering their base implied until their next event |

Five acceptance criteria depend on these events, all under *Re-evaluation triggers*. Naming them, in the spec's own words:

| Acceptance criterion (spec text, abbreviated) | Gap | Test that covers the behaviour |
| --- | --- | --- |
| "Renaming an open sibling's branch so that it becomes the sole owner … raises a warning that no lifecycle event would have triggered" | No `renamed` event | `sibling_rename_into_sole_ownership_warns` — validator invoked directly after the rename |
| "Renaming an open sibling's branch into naming an issue this pull request already owns, or that another sibling already names, leaves the result silent" | No `renamed` event | `sibling_rename_into_owned_or_contested_stays_silent` |
| "Renaming an open sibling's branch so that it no longer names the issue clears a warning" | No `renamed` event | `sibling_rename_out_clears_warning` |
| "Renaming a pull request's own branch so that it now names an issue its description declares … clears a warning" | No `renamed` event | `own_rename_into_ownership_clears_warning` |
| "Changing the repository's default branch re-evaluates the affected pull requests, even those whose own base was never touched" | No default-branch-change event | `default_branch_change_flips_filtering` — validator invoked with each default-branch value |

Each is implemented as **script behaviour**: invoking the validator after the rename or the default-branch change produces the correct result, and the named test asserts it. What is not delivered is the automatic invocation. The plan states this rather than letting the criteria read as satisfied.

---

## Testing Strategy

**Test types**: Unit (script-level, against stubbed `gh`), plus a smoke runbook for the GitHub-side wiring.

**Key scenarios to test**: one per acceptance-criterion group, enumerated in the addenda below.

**Smoke test runbook**: `docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md`

**Regression suite**: `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh` (new). It declares `# covers:` for the validator, the shared library, `post-merge-cleanup.sh`, and the workflow, so diff-based CI runs it when any of them changes.

### Parser-risk addendum

This plan is parser-risk: it adds a scanner over markdown and moves an existing one.

**Edge-case enumeration** — each becomes at least one unit test in `test-validate-closing-keyword-scope.sh`:

- **Boundary characters**: `Closes #12`, `(Fixes #12)`, `resolved issue #12`, `CLOSES #12`; `Closes #12x` and `Closes#12` must not match.
- **Negative lookalikes**: `disclose #12`, `hotfix #12`, `unfixes #12` — the canonical regex requires a non-word character before the keyword.
- **Multiple occurrences on one line**: `Closes #1, closes #2` yields both.
- **Nested and overlapping fences**: a ```` ``` ```` fence containing a ```` ```` ```` line; a `~~~` fence containing a ```` ``` ```` line; a fence closed by a longer run of the same character (valid) and by a shorter one (not valid).
- **Normative-spec flexibility**: closing fence length ≥ opening fence length; a fence indented up to three spaces is a fence, four or more is indented code.
- **Unclosed fence** extends to end of input.
- **Inline code spans**: single and multi-backtick delimiters; a span spanning two lines within one paragraph; a paragraph break ending span scope.
- **Blockquote** lines (`^\s*>`).
- **Title interaction**: an unclosed fence in the title, and a lone backtick in the title closed by one in the description — each evaluated twice, once with a default-branch base and once without, which must give opposite answers.
- **Branch forms**: `fix/97-slug`, `fix/lh-97-slug`, `backport/hotfix/97-slug`; the non-owners `spec/97-slug`, `implementation-plan/97-slug`, and `feature/456-add-97-logs` (97 appears in the slug, not as the issue).

**Unit test mapping**: every bullet above maps to a named test in `test-validate-closing-keyword-scope.sh`. In addition, a **parity test** runs the extracted filter and `post-merge-cleanup.sh`'s use of it over the same corpus and asserts byte-identical output — the guarantee that the two cannot drift.

**Suppression semantics**: the only suppression is the `multi-issue-intentional` label. It is repository-level state, not an inline directive: it applies to the whole pull request, there is no per-issue form, and no description marker is recognized. A description marker is deliberately excluded because the description is the text this feature parses.

### Concurrent-event-source addendum

- **Shared mutable state guards**: the only shared mutable state is the published report comment and the check run for one pull request. Guarded by the workflow's per-PR concurrency group plus the script's own ordering stamp.
- **Re-entrancy / in-flight tracking**: yes, a second event can arrive mid-run — a sibling opening while an author applies the label. Tracked by the run-start stamp written into the report; a run refuses to overwrite a report stamped by a later-started run.
- **Event deduplication**: GitHub can deliver the same event twice. Two duplicate runs read identical inputs, so freshness cannot separate them; the ordering stamp does, and the outcome is one report either way.
- **Listener and resource cleanup**: not applicable — each run is a process that exits; there are no listeners or timers.
- **Race conditions at initialization**: an event can arrive before the `multi-issue-intentional` label exists. Provisioning is idempotent and its failure never suppresses a warning, so an early event produces a correct outcome with a warning line about the label.
- **Race conditions at teardown**: a run cancelled mid-write leaves either the old report or the new one, never a merged one, because the comment is updated in a single API call.
- **Error propagation across async boundaries**: every `gh` read is checked; a failure is recorded as an unreadable input rather than an empty result, which is what makes the outcome indeterminate instead of falsely clean.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Stubbed `gh` responses | PR bodies covering every parser edge case above; open-PR lists covering none, one, two and team-prefixed owners; label present and absent; unreadable variants for each gate input | `scripts/development-workflow/tests/fixtures/closing-keyword-scope/` |
| Throwaway git repository | Not required — the validator reads GitHub, not git; branch names arrive from the stubbed PR list | — |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — note that the validation is advisory and never gates the reviewer loop.
- [ ] `scripts/lint/README.md` — no change (this is not a lint script); listed only to record that it was considered.
- [ ] `AGENTS.md` — add the `multi-issue-intentional` opt-out to the conventions an agent should know when writing a PR description.
- [ ] `docs/workflow/development-workflow/README.md` — one line in the workflow overview describing when the validation runs and that it warns rather than blocks.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The extracted filter drifts from `post-merge-cleanup.sh` | Med | High — a false warning or a missed one | Extract by moving, source from both, and assert byte-identical output over a shared corpus in the parity test |
| The sentinel used to locate the title/description boundary is itself filtered out | Med | Med — a live reference could be missed | That case is exactly when the title swallowed the description too; the required outcome is silence, and a test asserts it |
| The first check-run writer in the repository needs a permission no other workflow requests | Low | Med — the run fails to publish its neutral conclusion | `checks: write` is declared in the workflow; an unpublishable check is itself an unreadable-output condition and is logged |
| Sibling fan-out grows with the number of open pull requests | Low | Low | Bounded by the open PR list, one API call plus one validation per declaring PR; no scheduled sweep was added (option B) |
| The declared trigger gaps read as satisfied criteria | Med | Med — a reviewer or a later reader assumes rename coverage | Stated in its own section with the affected criteria named, and the script-level behaviour is tested separately from the invocation |

---

## Code Samples

None. The one design element that would benefit from a sample — the boundary sentinel — is described in prose above deliberately: a sample would be read as production code, and the exact filter invocation belongs in the implementation PR.

---

## Implementation Order

1. Extract `strip_fenced_pr_body_blocks` and the keyword regex into `scripts/development-workflow/closing-keyword-lib.sh`; source it from `post-merge-cleanup.sh`. **Verify**: run `scripts/development-workflow/tests/test-post-merge-cleanup.sh` and confirm it still passes, so the move changed no behaviour.
2. Add `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh` with the parity test only, and confirm it passes against the extracted library before any new logic exists.
3. Implement filtering and keyword extraction in `validate-closing-keyword-scope.sh`, including the base-branch selection and the boundary sentinel. **Verify**: the parser edge-case tests pass.
4. Implement ownership resolution. **Verify**: the ownership tests pass, including contested, no-signal, team-prefixed, documentation-stage and closed-sibling cases.
5. Implement the opt-out, including idempotent provisioning and the failed-provisioning warning line.
6. Implement the single-accessor input reads and the indeterminate outcome. **Verify**: one test per gate input confirms an unreadable input leaves an existing report untouched and posts nothing.
7. Implement report publication, freshness and the ordering stamp. **Verify**: the overlapping-run tests pass.
8. Add `.github/workflows/closing-keyword-scope.yml` with the trigger set, permissions, fork guard and concurrency group.
9. Add the sibling fan-out to the workflow. **Verify**: run the workflow's job locally where possible, and confirm the fan-out list is derived from open pull requests only.
10. Write `docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md` and execute it against a scratch pull request pair.
11. Update the project docs listed under **Documentation Updates**.
12. Add `changelog.d/1644.added.cross-pr-closing-keyword-validation.md` containing:
    `- **Cross-PR closing keyword validation** (#1644): a pull request that declares a closing keyword for an issue a sibling pull request is carrying now gets an advisory warning naming the issue and the sibling, so the mistake is caught while the batch is still in flight rather than after a release has been assembled around the wrong scope. The warning never blocks a merge, and a pull request that deliberately closes several issues can silence it with the multi-issue-intentional label.`
