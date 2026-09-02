# Cross-PR Closing Keyword Validation — Implementation Plan

**Spec**: [`1_1644-cross-pr-closing-keyword-validation_specs.md`](./1_1644-cross-pr-closing-keyword-validation_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md`](../../../testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md)

---

## Summary

**Approach**: One new script, `scripts/development-workflow/validate-closing-keyword-scope.sh`, decides the outcome for a single pull request and is the only place the rules live. It reuses the canonical filter from `post-merge-cleanup.sh` verbatim rather than reimplementing it, so parity is structural rather than promised. One new workflow, `.github/workflows/closing-keyword-scope.yml`, routes `pull_request_target` events to it — for the triggering pull request, and, on a sibling's lifecycle event, for the open pull requests whose descriptions declare that sibling's issue. Reporting is a single updated-in-place comment; the indeterminate outcome is a `neutral` check run.

**Estimated complexity**: L

**Rationale**: The rule set is large — 45 acceptance criteria across eight groups, counted rather than estimated (see the Verification Log) — and three of them are hard in their own right: byte-exact filtering parity with an existing parser whose behaviour differs by base branch, an indeterminate-versus-clean distinction that must hold for *every* input without enumeration, and an ordering guarantee across overlapping workflow runs. None of the individual pieces is large; the plan is L because the correctness surface is.

**Dependencies**: none outstanding. #1702 — the spec amendment that moved the five undeliverable re-evaluation criteria out of scope (alignment option B, 2026-09-02) — merged as `e9bee842` before this plan; this plan is written against the amended spec. **If it does not hold when work starts** — the amendment reverted, or the branch this plan is implemented from predates `e9bee842` — stop before writing code: the spec would again require five criteria this plan does not deliver, and the implementation PR would be reviewed against them. Confirm with `git log --oneline e9bee842 -1` on the implementation base, or re-read the spec's *Out of Scope (MVP)* for the entry naming the branch-rename and default-branch-change triggers. Restoring it is a spec-branch change, not an implementation one. #1593 (merged) added `push_verification_failed` and the self-refspec push rules; this feature touches neither.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `e9bee842` |
| Acceptance-criterion count | `awk '/^## Acceptance Criteria/{f=1;next} /^## /{if(f)exit} f' <spec> \| grep -c '^- \[ \] '` | `45` |
| Acceptance-criterion group count | same extraction, `grep -c '^### '` | `8` |
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
| Canonical filtering semantics for closing keywords | `strip_fenced_pr_body_blocks` in `post-merge-cleanup.sh` | The script itself, read at plan time | 2026-09-02, repo SHA `e9bee842` | This item only; no open PR changes that parser | `Verified` |
| Approved base branch for this plan's PR | `develop` | Bounded prelude for #1644 (`baseReason: no integration branch label`) | 2026-09-02, repo SHA `e9bee842` | This item only | `Verified` |
| Repository writes are commit statuses today; this feature introduces the first check run | `pr-policy.yml` uses `repos/$REPO/statuses/$sha` | `.github/workflows/pr-policy.yml` lines 105, 377, 442, 461 — every status write in the file | 2026-09-02, repo SHA `e9bee842` | This item only | `Verified` |

---

## Layer-by-Layer Changes

### Backend / API

- [ ] **`scripts/development-workflow/validate-closing-keyword-scope.sh`** (new; shell contract `bash`, it is an executable script rather than documentation guidance). Single entry point: `validate-closing-keyword-scope.sh <pr_number> <owner> <repo>`. Decides and publishes the outcome for one pull request. Every rule below lives here, not in the workflow YAML, so the logic is testable without GitHub. *Acceptance criteria: all groups.*
- [ ] **Reuse, do not reimplement, the canonical filter.** Extract `strip_fenced_pr_body_blocks` from `post-merge-cleanup.sh` into `scripts/development-workflow/closing-keyword-lib.sh`, and source it from both. The extraction must be byte-identical — move, not rewrite — so the two can never drift. *Acceptance criteria: Which keywords count as live.*
- [ ] **Base-branch-dependent filtering.** Read the PR's base and the repository's default branch. When the base **is** the default branch, filter the description alone. Otherwise, filter `title + "\n" + description` as one text, exactly as `fetch_pr_closing_issues` does. *Acceptance criteria: Which keywords count as live (title-fence rows).*
- [ ] **Report from the description only, by differential filtering.** In the concatenated case, the run needs to know which of the *live* closing references the closer will act on were contributed by the description. It gets that by filtering twice and subtracting:

  - **A** = the multiset of live closing references from `filter(title + "\n" + description)`. This is exactly what the closer sees, by construction — the same function over the same text.
  - **B** = the same, over `filter(title + "\n" + description′)`, where `description′` is the description with the **first letter of every closing-keyword token replaced by `Z`** — `Closes` → `Zloses`, `fixes` → `Zixes`, `resolved` → `Zesolved`. None of those is a keyword, and the substitution is **length-preserving**, so every byte offset, fence delimiter and inline-code span in the concatenated text is unchanged and the filter's suppression decisions are byte-for-byte identical.
  - The reported set is the multiset difference **A − B**: references that were live *and* whose liveness came from the description.

  Multiset, not set, matters: when the title and the description both name issue 12 and both are live, `#12` appears twice in A and once in B, and the difference correctly yields one description-contributed reference. Set subtraction would have yielded none.

  This replaces an earlier boundary-sentinel design, which inserted a marker line between title and description and reported only what followed it. Review found the case that breaks it: a title that opens a fence which the description *closes* part-way through, leaving a later `Closes #12` live. The sentinel is inside the fence and is filtered out, but the keyword after the closing fence is not — the sentinel design would have gone silent on a reference the closer will act on. Differential filtering has no such blind spot, because it never reasons about position; it asks the filter itself, twice, and both runs see structurally identical text.

  It also removes what the sentinel design needed to stay safe: no nonce, no collision detection, no retry, no unforgeability argument about a marker the pull request's author could type. *Acceptance criteria: a closing keyword that appears only in the title is not reported; the title-fence rows; Which keywords count as live.*
- [ ] **Ownership resolution.** List open pull requests, keep those whose head branch matches `^(feature|fix|refactor|hotfix|backport/hotfix)/([A-Z][A-Z0-9]*-)?<issue>(-|$)`, and apply the four ownership rules: none → silent for that issue; two or more → contested, silent; self → in scope, silent; exactly one other → reported. Platform-derived issue links are never consulted. *Acceptance criteria: Establishing ownership.*
- [ ] **Opt-out.** Skip reporting when the PR carries `multi-issue-intentional`. Provision the label idempotently on first use with the `ensure_reviewer_failed_label_exists` pattern; a failed creation warns in the report and never suppresses it. *Acceptance criteria: The opt-out.*
- [ ] **Indeterminate outcome, stated over the input set rather than a list.** Read every gate input through one accessor that appends the input's name and its read status to **two parallel indexed arrays** — not an associative array, which is Bash 4+ and this repository targets Bash 3.2 (macOS system bash). The outcome is indeterminate when any recorded status is a failure, so an input added later is covered by construction rather than by extending a list. On indeterminate: leave any existing report untouched, post nothing, write a `neutral` check run naming every input that could not be read. *Acceptance criteria: The indeterminate outcome.*
- [ ] **Check-run identity.** The run publishes to a single check, found by a stable identity. The check run carries a fixed `name` (`Closing-keyword scope`) and a fixed `external_id` (`closing-keyword-scope:v1`), and is addressed per pull request head SHA. A run lists the check runs for that SHA **with `filter=all` and full pagination** — the default `filter=latest` returns only the most recent run per name, which would make a duplicate unobservable and the "oldest match wins" rule undecidable — selects the entry matching both the name and the external id, and **updates it in place** rather than creating another, so a conclusive re-run replaces the neutral conclusion on the same check instead of leaving two. When the listing returns more than one match, the run updates the **oldest** and leaves the rest untouched: unlike comments, check runs cannot be deleted through the API, so reconciliation is deterministic selection rather than cleanup, and the extras age out with the head SHA. *Acceptance criteria: The indeterminate outcome — "a conclusive re-run … replaces the neutral 'did not conclude' check, including when the conclusive result is silent".*
- [ ] **Where duplicate checks arise, and why that is the right trade.** An unreadable check-run listing is circular: it makes the run indeterminate, and publishing an indeterminate outcome *requires* writing a check run that the run can no longer locate. The rule is explicit rather than left to the implementer: **create** the neutral check. The spec requires an indeterminate run to leave a neutral, non-blocking conclusion and a log line, so declining to publish would trade a visible non-conclusion for an invisible one — the failure the whole indeterminate design exists to prevent. **The cost is not bounded at one.** Every subsequent run that also cannot read the listing is in the same position and creates another neutral check on that SHA, because the thing that would let it find the previous one is the thing that is broken. The honest statement is per-run: an indeterminate-by-unreadable-listing run adds a neutral check, and the next such run adds another. They are non-blocking, the first readable run selects the oldest match deterministically and updates it, and all of them age out with the head SHA — but a repository whose check-run listing stays broken accumulates them, and no mechanism in this design prevents that. Serialization does not help; two runs that cannot see each other's writes are not a concurrency problem. This is the only path in the design that can produce a second check, and it produces no second *report*, because the comment path is independent and its own unreadable listing leaves the existing comment untouched. *Acceptance criteria: The indeterminate outcome — "leaves a neutral, non-blocking check conclusion and a log line naming what could not be read".*
- [ ] **Report identity.** The run publishes to a single comment, found by a stable marker. The report carries an HTML-comment marker as its first line, following the repository's existing idiom — `REVIEWER_LOOP_HISTORY_MARKER = "<!-- reviewer-loop-history:v1 -->"` in `workflow-lib.sh:3410`. This feature's marker carries the ordering stamp, so it cannot be a single fixed string the way the reviewer-loop one is. The library defines the two halves separately: `CLOSING_KEYWORD_SCOPE_MARKER_PREFIX = "<!-- closing-keyword-scope:v1 "` — **including the trailing space**, which is what terminates the version — is the **identity**, and the stamp plus the closing delimiter follow it, giving `<!-- closing-keyword-scope:v1 started=… run=… attempt=… -->`. Without that space the prefix would also match `<!-- closing-keyword-scope:v10 …`, and a future v10 run's report would be adopted, updated, or deleted as a v1 duplicate. Lookup is the regex `^<!-- closing-keyword-scope:v1 ` against each line of a comment body — version, then a space, and nothing said about what follows. `v10` fails it because `0` is not a space. There is no *earlier* form to accommodate, since this feature introduces the marker; what the rule does accommodate is a **degenerate** one, `<!-- closing-keyword-scope:v1 -->` with the stamp missing or truncated, which still matches (the space is present) and is then treated as older than any run by the stamp rule below. A comment this feature wrote is always findable, whatever happened to its stamp. A run finds its own comment by listing the pull request's issue comments and selecting those whose body contains a line starting with the prefix; it updates that comment rather than posting a new one. **A clean result deletes it**: the spec is explicit that a clean pull request has no comment and that "silence is the clean signal", and a comment announcing that nothing is wrong is not silence. Editing it in place to a clean state would have kept the comment id stable, which is convenient and contrary to the spec.

  Deleting it removes the ordering stamp with it, so **ordering evidence is read from the check run whenever no marked comment exists**. The check run is written on every run, conclusive or not, and cannot be deleted through the API, which makes it the durable half of the pair — and that is what stops an earlier-started warning run from resurrecting a warning behind a later-started clean one. *Acceptance criteria: Ordering and idempotence — "Running the validation twice on an unchanged pull request leaves a single report".*
- [ ] **Inherited duplicates are reconciled, not ignored.** If the listing returns more than one marked comment — possible from a partial rollout, or from a run interrupted between posting and its next read — the run updates the **oldest** and deletes the rest, so the surviving comment id is deterministic regardless of which run reconciles them. A listing that cannot be read is an unreadable input and makes the run indeterminate; it never leads to posting a second comment.
- [ ] **Where `started` comes from.** It is the **validator's own clock, read once at start** and reused for both artifacts, so the report and the check run always carry the same stamp. It is *not* derived from `GITHUB_RUN_ID`, which GitHub documents as unique and not chronological, and not from a workflow context field — none supplies a millisecond timestamp. The library defines:

  ```bash
  closing_keyword_scope_started_at() {
    python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")'
  }
  ```

  `python3` is already a hard dependency — the canonical filter is a `python3 -c` program — and this is portable where `date +%3N` is not, since macOS `date` has no sub-second format. Fixed width, so string comparison is chronological comparison. Being a function, it is also the tests' seam for scripted timestamps, the same way the nonce generator was.

  The comparison assumes runner clocks agree to better than the gap between two runs' starts. On GitHub-hosted runners they are NTP-synchronised, and the target-keyed concurrency group means two runs writing to one pull request are separated by a whole run rather than by milliseconds — so the assumption is not load-bearing in the way it would be for a lock. *Acceptance criteria: Ordering and idempotence.*
- [ ] **Freshness: what is snapshotted, how it is compared, and when it is checked.** After reading the gate inputs, the run records a **snapshot hash** over the concatenation of every input value it read — the description, the title, the base branch, the repository's default branch, the labels, the head branch, the sibling pull request list, the target's open/closed state, **the existing report comment's body**, and **the existing check run's stamp and conclusion** — in a fixed order, each length-prefixed so no two field boundaries can be confused. The last two are gate inputs in the spec's own matrix and belong here for the same reason as the rest: if another writer publishes between this run's read and its write, the run's decision was made against a state that no longer holds.

  Including them makes freshness strictly stronger than the ordering rule rather than redundant with it. The ordering stamp answers "may I overwrite what is there?"; freshness answers "is what I computed still about the current state?" A run whose stamp would have won still abandons when any input moved, because winning the tie-break is not the same as being right. The hash is `shasum -a 256` output, which is on both platforms.

  **The check point is once, immediately before the first write**: the run re-reads every one of those inputs through the same accessor, recomputes the hash, and compares. Equal means publish; different means abandon — no write at all, exit 0, and log which input moved. The next event recomputes from current state, so abandoning is not a lost result. A failed *re-read* is an unreadable input like any other, and makes the run indeterminate rather than clean.

  **Between the two writes there is no second check**, and the order is deliberate: the **check run is written first**, then the comment. The check run carries the ordering stamp and cannot be deleted, so a run that dies between the two leaves durable evidence of what it decided; the next run reads that stamp, sees its own is later, and republishes both. The reverse order would leave a comment no stamp accounts for. *Acceptance criteria: Ordering and idempotence.*
- [ ] **The stamp's location in each artifact.** Every published artifact carries the same stamp — `started=<ISO-8601 UTC, milliseconds> run=<GITHUB_RUN_ID> attempt=<GITHUB_RUN_ATTEMPT>` — and a run refuses to write over one whose stamp sorts **after** its own. The comparison is a **total** order over the triple, taken in that order: `started` compared as a string, which is why it is ISO-8601 UTC with a fixed number of digits; then `run` numerically; then `attempt` numerically.

  **What the tie-break claims, and what it does not.** `started` carries the ordering: a run whose stamp is strictly earlier is genuinely earlier, and refusing to overwrite a later one is the spec's later-result-wins rule. The `run` and `attempt` fields decide only an exact tie, and they are **not** evidence of start order — GitHub documents run ids as unique, not as monotonic in start time, and does not guarantee the start order of concurrent runs at all. Their job is narrower: to make every run agree on the same winner instead of resolving the tie by completion order, which is the reordering the stamp exists to prevent.

  **Why the tie cannot arise: only serialized callers write.** Writes to one pull request are serialized by the target-keyed concurrency group, so two workflow runs writing to the same target never overlap — the second starts after the first finishes, and a run makes several API calls, so their `started` values cannot land in the same millisecond. The one way around the group would be invoking the validator by hand while a run is in flight, so **that path does not write**: publication requires `--publish` *and* the serialized-context check described in Layer-by-Layer. Short of deliberately forging the CI environment variables, every writer is inside the group and an exact `started` tie cannot occur; under that forgery the tie-break still converges on one artifact, it just stops being evidence of which run started later.

  This is a real constraint on the tool, not a formality: someone debugging a wrong warning runs the validator, reads the verdict, and cannot accidentally overwrite the workflow's report while doing so. Freshness is **not** offered as cover here — it catches a run whose inputs moved while it worked, a different failure and one both tied runs would pass. The tests cover the equal-timestamp case explicitly, not only the strictly-ordered one:
  - **The report comment** carries it inside its marker line, after the identity prefix: `<!-- closing-keyword-scope:v1 started=… run=… attempt=… -->`, read back from the comment body the run already fetched to locate it.
  - **The check run** carries it as the first line of `output.summary`, in the same HTML-comment form, so it is invisible in the rendered check and returned by the same `filter=all` listing used for identity — no second API call is needed to read it.
  - With no marked comment present, the stamp is read from the check run alone. That is the normal state after a clean result, not a missing-evidence case, and it is why the check run is never deleted.
  - A stamp that is missing or unparseable is treated as **older than any run**, so a pre-stamp artifact is adopted rather than becoming permanently un-writable. Only a well-formed stamp that sorts strictly after the writing run's own blocks the write.
  *Acceptance criteria: Ordering and idempotence.*
- [ ] **Fork guard, in the script.** Compare `head.repo.full_name` with the target repository and exit before any write when they differ. This is the inner half of a two-layer guard; the workflow-level `if:` is the outer half, specified under Infrastructure. *Acceptance criteria: Fork-originated pull requests.*

### Shared Packages / Libraries

- [ ] **`scripts/development-workflow/closing-keyword-lib.sh`** (new): the extracted canonical filter plus the keyword regex, sourced by `post-merge-cleanup.sh` and the new validator. `post-merge-cleanup.sh` keeps its current behaviour; this is a move with a `source` added.

### Infrastructure / Configuration

- [ ] **`.github/workflows/closing-keyword-scope.yml`** (new). `pull_request_target` types `opened, reopened, edited, labeled, unlabeled, closed, ready_for_review`. Permissions: `pull-requests: write` (comment), `issues: write` (label creation), `checks: write` (the neutral conclusion — the first check-run writer in this repository), `contents: read`.
- [ ] **How the workflow obtains the validator.** The validator is a repository script, so unlike `pr-policy.yml` this workflow cannot be checkout-free: a GitHub-hosted runner has no copy of it otherwise. Exactly one checkout step, written as:

  ```yaml
  - name: Check out the base commit
    uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd  # v5
    with:
      ref: ${{ github.event.pull_request.base.sha }}
      persist-credentials: false
  ```

  The action itself is pinned to a full commit SHA with the version in an adjacent comment, per the Protocol 03 workflow security checklist; the SHA is the one every other workflow in this repository already uses for `actions/checkout` v5. The `ref` is the **base** commit — trusted code the pull request cannot influence — and never `github.event.pull_request.head.sha` or `refs/pull/<n>/merge`. That is the `pull_request_target` safety rule: the elevated token is paired only with code from the base. Everything from the pull request — description, labels, branch names, base — is read through the API as data and never executed.
- [ ] **Fork guard, at the workflow.** The job carries `if: github.event.pull_request.head.repo.full_name == github.repository`, as the Protocol 03 checklist requires of every step that writes to the repository — and this one comments, creates a label and writes a check run. The script's own guard stays as defence in depth. `pr-policy.yml` guards in the script only; this workflow does both, because the checklist asks for the `if:` explicitly. *Acceptance criteria: Fork-originated pull requests.*
- [ ] **Sibling fan-out, as two jobs.** A run never writes to more than one pull request, because a concurrency group cannot serialize a job that writes to many. The workflow splits:

  - **`resolve-targets`** — no writes. It computes the list of pull requests this event should re-validate: the event's own pull request **only while it is open**, plus, on `opened`, `reopened` and `closed` for an implementation branch, every open pull request whose description declares the issue that branch names. A `closed` event therefore fans out to the siblings it affects and drops its own pull request from the list, because the spec says a closed pull request is not evaluated at all. It emits the list as a JSON array output, **always set** — `[]` when there is nothing to validate, never unset. An unset output would pass the `validate` gate below (unset is not the string `[]`) and then fail the workflow on `fromJSON('')`, turning "nothing to do" into a red run.
  - **`resolve-targets` fails open, not closed.** If the open-pull-request listing fails or returns unparseable JSON, the job does **not** fail and does not emit an empty list. It emits the triggering pull request alone — when that pull request is open — together with a second output, `sibling_list_unreadable=true`. Failing closed here would swallow the very outcome the spec demands: an unreadable open-pull-request list is an unreadable *gate input*, and the spec requires a neutral check and a log line naming it, which nothing can publish if no matrix leg runs. The `validate` leg receives the flag, records that input as unread through the same accessor as every other input, and therefore reaches the indeterminate outcome by the ordinary path rather than a special case. Sibling targets stay unknown, which is honest — they could not be listed. When the triggering pull request is itself closed and the listing fails, there is nothing to publish on and nothing to publish about; the job logs the failure and emits `prs=[]`, which skips `validate` cleanly rather than failing it. *Acceptance criteria: The indeterminate outcome — "when the open pull request list cannot be read".*
  - **`validate`** — `needs: resolve-targets`, `strategy: matrix: pr: ${{ fromJSON(needs.resolve-targets.outputs.prs) }}`, with `if: needs.resolve-targets.outputs.prs != '' && needs.resolve-targets.outputs.prs != '[]'` — the emptiness check the `[]` guarantee above makes sufficient, plus the unset check as belt and braces, so neither an empty list nor a missing output fails the matrix. One leg per target, each writing only to its own target.

  The fan-out stays bounded by the open pull request list, and every target is validated through the same single-PR entry point.
- [ ] **Publication requires the serialized context, not just the flag.** The validator computes and prints its verdict on any invocation. Writing — the report comment, the label, the check run — requires **both** `--publish` **and** a context check: `GITHUB_ACTIONS` is `true`, `GITHUB_WORKFLOW` is the closing-keyword-scope workflow, and `GITHUB_JOB` is `validate`. Any of those missing makes the run exit non-zero without writing, logging the reason `publication_context_not_serialized`. This is a script-level refusal, not a workflow stop condition, so it is deliberately not declared on the guardrails surfaces — nothing in the staged workflow pauses on it, and adding a canonical stop condition for a script's own argument validation would dilute the ones that exist. A flag alone would not have been a guard: `--publish` is a public option, and "the workflow is the only caller" is a claim about today's callers, not a property of the script.

  What this does **not** claim: a shell script cannot prove its own execution context. Someone who exports those variables by hand can publish from outside the group. The guard's job is to make out-of-group publication a deliberate forgery of the CI environment rather than an ordinary command-line mistake, and that is the strongest form available here. In that forged case the ordering rule still converges — the stamp comparison and the freshness re-read make the two writers agree on one artifact — it simply stops being a guarantee about which run started later. *Acceptance criteria: Ordering and idempotence.*
- [ ] **A closed pull request is never written to, checked twice.** `resolve-targets` drops it from the list, and the validator re-reads the target's state and exits before any write when it is not open. The second check is not redundancy for its own sake: the target list is computed before the matrix leg runs, so a pull request can close in between. *Acceptance criteria: Re-evaluation triggers; The opt-out is not involved.*
- [ ] **Concurrency, keyed to the target rather than the trigger.** The `validate` job carries `concurrency: group: closing-keyword-scope-${{ matrix.pr }}`, `cancel-in-progress: false`. Job-level `concurrency` can read the `matrix` context, so each matrix leg is its own group. Keying the group to the *triggering* pull request would not serialize anything: two different sibling events can fan out to the same claimant, and their writes would sit in different groups and race. Keyed to the target, every write to a given pull request — whoever triggered it — is serialized against every other.

  GitHub keeps at most one running and one pending job per group and cancels the older pending one when a third arrives. That is the outcome we want and not a loss: the survivor starts later, so it reads fresher state, and the cancelled run's result would have been superseded anyway. The script's ordering stamp remains, because serialization does not cover a run cancelled mid-write, a re-run of an old workflow run, or an artifact written before the stamp existed.

---

## Out-of-scope triggers, and what is still tested (alignment decision: option B, 2026-09-02)

GitHub Actions has no event for two of the changes that alter a result: `pull_request_target` has no `renamed` activity type, and nothing fires when a repository's default branch changes. A scheduled sweep is the only mechanism that covers them, and it was declined on 2026-09-02.

The spec now says so itself. #1703 (issue #1702, merged as `e9bee842`) removed the five acceptance criteria that depended on those events from *Re-evaluation triggers* and put the deferral in *Out of Scope (MVP)*, together with the residual the review surfaced: the delay is **not** bounded. The readiness backstop helps only when readiness arrives *after* the unobservable change, so a branch renamed on an already-ready pull request can carry a stale warning to merge unless some other trigger happens to fire. This plan therefore covers every acceptance criterion the spec asks for; nothing here is undelivered.

What remains is that the validator must still compute the right answer when it *does* run after such a change — the spec keeps requiring that, and it is the half that is testable. The tests are named here so they are not lost with the criteria that were removed:

| Behaviour, exercised by invoking the validator directly | Test |
| --- | --- |
| A sibling renamed into sole ownership of a declared issue produces a warning | `sibling_rename_into_sole_ownership_warns` |
| A sibling renamed into an issue this pull request already owns, or another sibling already names, stays silent | `sibling_rename_into_owned_or_contested_stays_silent` |
| A sibling renamed out of naming the issue clears the warning | `sibling_rename_out_clears_warning` |
| A pull request's own branch renamed into naming a declared issue clears the warning | `own_rename_into_ownership_clears_warning` |
| Each default-branch value selects the filtering its base implies | `default_branch_change_flips_filtering` |

The workflow does not invoke the validator on either change, because no event exists to invoke it from. Nothing in the workflow needs to be written to make that true, and nothing in the plan claims otherwise.

---

## Testing Strategy

**Test types**: Unit (script-level, against stubbed `gh`), plus a smoke runbook for the GitHub-side wiring.

**Key scenarios to test**: the traceability matrix below maps every acceptance-criterion group and every parser-risk edge case to the implementation item that satisfies it and the named test or runbook step that proves it. All test names refer to `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh` unless a runbook step is named instead. Three of them — `workflow_job_carries_fork_if_guard`, `workflow_checkout_uses_base_sha_never_head` and `workflow_concurrency_group_is_keyed_to_matrix_target` — assert on the text of `.github/workflows/closing-keyword-scope.yml` rather than on script behaviour: the first that the job's `if:` compares `head.repo.full_name` with `github.repository`, the second that the checkout's `ref` is `base.sha` and that neither `head.sha` nor `refs/pull/` appears anywhere in the file; the third that the `validate` job's concurrency group interpolates `matrix.pr` and not the triggering pull request's number. They are structural because the guard they protect cannot be exercised from a test runner — a fork event cannot be synthesized locally — and a silently dropped `if:` is exactly the regression that would otherwise ship unnoticed.

### Traceability: acceptance criteria → implementation → test

| Spec group | Implementation item | Named coverage |
| --- | --- | --- |
| Reporting a mismatch | Ownership resolution; report publication | `sibling_owned_issue_warns`, `warning_names_issue_and_sibling_pr`, `all_issues_self_owned_is_silent`, `no_closing_keywords_is_silent`; runbook Steps 1–2 |
| Which keywords count as live | Reuse of the canonical filter; base-branch-dependent filtering; differential attribution | `fenced_keyword_not_reported`, `blockquoted_keyword_not_reported`, `inline_span_keyword_not_reported`, `unclosed_fence_suppresses_rest`, `title_fence_suppresses_for_non_default_base`, `title_fence_does_not_suppress_for_default_base`, `title_only_keyword_not_reported`, `title_opens_fence_description_closes_it_later_keyword_is_reported`, `same_issue_live_in_title_and_description_reports_one`, `hotfix_to_default_branch_is_validated`, `substring_lookalikes_not_reported`; runbook Step 5 |
| Fork-originated pull requests | Fork guard, in the script + workflow-level `if:` | `fork_pr_is_not_validated_and_writes_nothing`, `workflow_job_carries_fork_if_guard`, `workflow_checkout_uses_base_sha_never_head` |
| Re-evaluation triggers — a closed pull request is not evaluated | Source dropped from the target list on `closed`; validator re-checks the target is open | `closed_source_pr_fans_out_without_writing_to_itself`, `target_closed_between_resolve_and_validate_writes_nothing` |
| The opt-out | Opt-out check; idempotent provisioning | `label_present_is_silent`, `label_created_on_first_use`, `concurrent_creation_does_not_fail`, `label_creation_failure_still_warns_and_names_label`, `applying_label_clears_existing_warning`, `removing_label_restores_warning`, `dropping_keyword_clears_warning`; runbook Step 4 |
| Establishing ownership | Ownership resolution | `no_owner_is_silent`, `contested_ownership_is_silent`, `team_prefixed_sibling_is_owner`, `platform_link_is_not_ownership`, `non_naming_branch_is_not_owner`, `spec_and_plan_branches_are_never_owners`, `closed_or_merged_pr_is_never_owner`; runbook Step 6 |
| Re-evaluation triggers | Workflow trigger set; sibling fan-out | `sibling_open_raises_warning`, `sibling_close_or_merge_clears_warning`, `sibling_reopen_restores_warning`, `base_retarget_flips_filtering`, `reopen_reevaluates`, `readiness_backstop_reevaluates`; runbook Steps 2 and 5 |
| Correct filtering after a rename or a default-branch change — out of scope as a *trigger*, still required as *behaviour* | Validator invoked directly; no workflow event exists | The five tests named under *Out-of-scope triggers, and what is still tested* |
| The indeterminate outcome | Single-accessor input reads; check-run identity | `unreadable_description_leaves_report`, `unreadable_pr_list_leaves_report`, `unreadable_label_is_indeterminate`, `unreadable_base_is_indeterminate`, `unreadable_existing_report_is_indeterminate`, `unreadable_head_branch_is_indeterminate`, `unreadable_check_run_list_is_indeterminate`, `unreadable_check_run_list_still_publishes_neutral_check`, `unreadable_check_run_list_posts_no_second_report`, `indeterminate_writes_neutral_check_and_log`, `indeterminate_does_not_change_mergeability`, `conclusive_rerun_updates_same_check_run`, `silent_conclusive_rerun_replaces_neutral_check`, `inherited_duplicate_check_runs_update_the_oldest`, `earlier_run_does_not_overwrite_later_check_run`, `unparseable_check_run_stamp_is_adopted`, `repeated_unreadable_listings_each_add_a_neutral_check`, ; runbook Step 7 covers only that the check publishes and does not block; the indeterminate path itself is unit-only, for the reason the runbook states |
| Ordering and idempotence | Report marker; freshness; ordering stamp; target-keyed concurrency | `late_started_conclusive_survives_earlier_indeterminate`, `earlier_run_does_not_restore_cleared_warning`, `earlier_run_does_not_clear_raised_warning`, `repeated_run_leaves_one_report`, `overlapping_runs_leave_one_report`, `clean_result_deletes_the_report`, `earlier_warning_run_does_not_resurrect_a_deleted_report`, `inherited_duplicate_reports_are_reconciled_to_the_oldest`, `cross_trigger_fan_out_to_one_target_writes_once`, `workflow_concurrency_group_is_keyed_to_matrix_target`, `equal_started_resolves_to_one_deterministic_winner`, `equal_started_and_run_breaks_the_tie_on_attempt`, `marker_without_a_stamp_is_still_found`, `v10_marker_is_not_recognised_as_v1`, `invocation_without_publish_writes_nothing`, `publish_without_the_workflow_context_stops`, `unreadable_sibling_list_still_validates_the_triggering_pr`, `nothing_to_validate_emits_an_empty_array_not_an_unset_output`, `input_changed_between_read_and_write_abandons_without_writing`, `unreadable_input_on_the_freshness_recheck_is_indeterminate`, `death_between_check_run_and_comment_is_repaired_by_the_next_run` |

### Traceability: parser-risk edge cases → test

| Edge case | Named test |
| --- | --- |
| Boundary characters (`Closes #12`, `(Fixes #12)`, `resolved issue #12`, `CLOSES #12`) | `boundary_characters_match_and_near_misses_do_not` |
| Negative lookalikes (`disclose`, `hotfix`, `unfixes`) | `substring_lookalikes_not_reported` |
| Multiple occurrences on one line | `multiple_keywords_on_one_line_yield_all` |
| Nested and overlapping fences | `nested_backtick_in_tilde_fence`, `longer_closing_fence_closes`, `shorter_closing_fence_does_not_close` |
| Normative-spec flexibility (fence length, ≤3-space indent) | `closing_fence_length_at_least_opening`, `three_space_indent_is_a_fence`, `four_space_indent_is_indented_code` |
| Unclosed fence extends to end of input | `unclosed_fence_suppresses_rest` |
| Inline code spans, single and multi-backtick, multi-line within a paragraph | `inline_span_keyword_not_reported`, `multiline_inline_span_within_paragraph`, `paragraph_break_ends_span_scope` |
| Blockquote lines | `blockquoted_keyword_not_reported` |
| Title interaction, evaluated for both base kinds | `title_fence_suppresses_for_non_default_base`, `title_fence_does_not_suppress_for_default_base` |
| A construct opened in the title that the description closes part-way through, with a live keyword after it | `title_opens_fence_description_closes_it_later_keyword_is_reported` |
| The same issue live in both the title and the description | `same_issue_live_in_title_and_description_reports_one` |
| A keyword token mangled by attribution is not itself a keyword, and mangling changes no byte offset | `mangled_keyword_tokens_are_not_keywords`, `mangling_preserves_text_length_and_filter_output_structure` |
| Branch forms and non-owners | `team_prefixed_sibling_is_owner`, `backport_hotfix_branch_is_owner`, `spec_and_plan_branches_are_never_owners`, `issue_number_in_slug_is_not_ownership` |
| Report identity: zero, one, two marked comments | `repeated_run_leaves_one_report`, `inherited_duplicate_reports_are_reconciled_to_the_oldest` |
| Check-run identity: zero, one, two matching check runs | `conclusive_rerun_updates_same_check_run`, `inherited_duplicate_check_runs_update_the_oldest` |
| Ordering stamp: absent, unparseable, earlier, later | `unparseable_check_run_stamp_is_adopted`, `earlier_run_does_not_overwrite_later_check_run`, `earlier_run_does_not_restore_cleared_warning` |
| Filter parity with the canonical parser | `filter_output_is_byte_identical_to_post_merge_cleanup` |

**Smoke test runbook**: `docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md`

**Regression suite**: `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh` (new). It declares `# covers:` for the validator, the shared library, `post-merge-cleanup.sh`, and the workflow, so diff-based CI runs it when any of them changes.

### Parser-risk addendum

This plan is parser-risk: it adds a scanner over markdown and moves an existing one.

**Edge-case enumeration** — each becomes at least one unit test in `test-validate-closing-keyword-scope.sh`:

- **Boundary characters**: `Closes #12`, `(Fixes #12)`, `resolved issue #12`, `CLOSES #12`; `Closes #12x` and `Closes#12` must not match.
- **Negative lookalikes**: `disclose #12`, `hotfix #12`, `unfixes #12` — the canonical regex requires a non-word character before the keyword.
- **Attribution by differential filtering**: a title opening a fence that the description closes before a later live `Closes #12` — the case that broke the earlier boundary-sentinel design; the same issue live in both title and description, where set subtraction would report nothing and multiset subtraction reports one; and the mangled tokens themselves (`Zloses`, `Zixes`, `Zesolved`), which must match no keyword and must leave every byte offset unchanged.
- **Multiple occurrences on one line**: `Closes #1, closes #2` yields both.
- **Report identity**: a pull request carrying no marked comment, one marked comment, and two marked comments — the last asserting the oldest survives.
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

- **Shared mutable state guards**: the only shared mutable state is the published report comment and the check run for one pull request. Each has a stable identity — the comment by the `<!-- closing-keyword-scope:v1 ` marker prefix, trailing space included, matched without the stamp that follows it; the check run by its fixed name and external id on the head SHA — and both are updated in place. A run never creates a second **report**, and never creates a second check run on the readable path. The single exception is the one named in Layer-by-Layer: when the check-run listing itself cannot be read, the run creates the neutral check rather than leaving an indeterminate outcome invisible. That exception has **no bound** — every run that also cannot read the listing creates another, since the listing is exactly what would let it find the previous one — and the plan states it that way rather than claiming a limit it cannot enforce. Covered by `unreadable_check_run_list_still_publishes_neutral_check`, `unreadable_check_run_list_posts_no_second_report` and `repeated_unreadable_listings_each_add_a_neutral_check`, which asserts the unbounded behaviour rather than a bound. Concurrent writes are guarded by the `validate` job's concurrency group — keyed to the **target** pull request via `matrix.pr`, not to the triggering one, so two sibling events fanning out to the same claimant land in the same group instead of racing in different ones — plus the script's own ordering stamp for what serialization cannot cover. `cross_trigger_fan_out_to_one_target_writes_once` is the test for that overlap.
- **Re-entrancy / in-flight tracking**: yes, a second event can arrive mid-run — a sibling opening while an author applies the label. Tracked by the run-start stamp, written into the report's marker line and into the check run's `output.summary`, and read back from the same fetches that locate each artifact; a run refuses to overwrite either one stamped by a later-started run. A missing or unparseable stamp counts as older, so a pre-stamp artifact is adopted rather than frozen.
- **Event deduplication**: GitHub can deliver the same event twice. Two duplicate runs read identical inputs, so freshness cannot separate them; the ordering stamp does, and the marker lookup means the outcome is one report either way. Named tests: `repeated_run_leaves_one_report`, `overlapping_runs_leave_one_report`, `inherited_duplicate_reports_are_reconciled_to_the_oldest`.
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
| Attribution to the description is wrong, so a live reference is missed or a title-only one is reported | Med | High — the feature's whole output is the reported set | Differential filtering asks the canonical filter itself rather than reasoning about position, and the mangling is length-preserving so both runs see structurally identical text. The title-opens-then-description-closes case that broke the earlier sentinel design has its own test |
| The first check-run writer in the repository needs a permission no other workflow requests | Low | Med — the run fails to publish its neutral conclusion | `checks: write` is declared in the workflow; an unpublishable check is itself an unreadable-output condition and is logged |
| A check run cannot be deleted through the API, so an inherited duplicate cannot be cleaned up the way a duplicate comment can | Low | Low — two checks on one head SHA, both non-blocking | Selection is deterministic (oldest matching name and external id), so runs agree on which one they update; the extras age out with the head SHA and never block a merge |
| Sibling fan-out grows with the number of open pull requests | Low | Low | Bounded by the open PR list, one API call plus one validation per declaring PR; no scheduled sweep was added (option B) |
| An unreadable check-run listing is circular: the run is indeterminate, and saying so requires writing the check it cannot find. Neutral checks then accumulate on that head SHA, one per such run, with no bound | Low — it needs a sustained API failure | Low — the checks are non-blocking, the first readable run updates the oldest, and all of them age out with the head SHA | Resolved by an explicit rule rather than left to the implementer: create the check. The accumulation is **not prevented**, and the plan says so rather than claiming a bound it cannot enforce — declining to publish would trade a visible non-conclusion for an invisible one, the failure the whole indeterminate design exists to prevent. This is the only duplicate-producing path in the design, and it produces no second report |
| The workflow cannot be smoke-tested before merge, so a wiring defect ships to `main` before anyone can see it | High — it is structural, not a possibility | Med — a broken workflow comments wrongly or not at all on real pull requests until the next release | Pre-merge evidence is the unit suite plus structural assertions on the YAML for the three guards a test runner cannot exercise; the runbook is scheduled as post-release verification, and the rollback is deleting one file |
| The out-of-scope triggers are forgotten once their criteria left the spec | Med | Med — a later reader assumes rename coverage, or the five behaviour tests get dropped as unmotivated | Kept in a section of their own that names each test and says plainly that no workflow event invokes the validator on those changes |

---

## Code Samples

None. The one design element that would benefit from a sample — the differential attribution — is described in prose above deliberately: a sample would be read as production code, and the exact filter invocation belongs in the implementation PR.

---

## When the workflow actually starts running

GitHub loads a `pull_request_target` workflow **from the repository's default branch**, which here is `main` — pull requests target `develop`. So the workflow is inert on the implementation branch and inert on `develop`: it starts firing only once a release merges `develop` into `main`, the same path `pr-policy.yml` and every other `pull_request_target` workflow in this repository took. Nothing in the implementation can change that, and a plan that asked the implementer to smoke-test before merge would be asking for something GitHub will not do.

**Pre-merge evidence** is therefore everything that does not need the workflow to fire:

- the unit suite, which is where the rules live;
- the three structural assertions on the workflow file — the fork `if:`, the base-SHA checkout, the target-keyed concurrency group — which exist precisely because the guards they protect cannot be exercised from a test runner;
- `actionlint` on the new workflow, and the Protocol 03 GitHub Actions workflow security checklist;
- the **planted-violation proofs** below, which are what makes the three structural assertions evidence rather than description.

### Planted-violation proofs (REVIEW.md, blocking)

This feature adds an automated validation gate — the workflow itself — plus three structural assertions that guard it. REVIEW.md requires each new check to be demonstrated failing on a planted violation and passing once it is removed, in this PR's own evidence, at a concrete file and line. Descriptions do not satisfy it. The implementation PR must therefore carry six runs, three pairs:

| Check | Planted violation, at a named line | Must fail | Must pass after removal |
| --- | --- | --- | --- |
| `workflow_job_carries_fork_if_guard` | Delete the `if:` line from the `validate` job in `.github/workflows/closing-keyword-scope.yml` | Yes, naming the missing fork guard | Yes |
| `workflow_checkout_uses_base_sha_never_head` | Change the checkout's `ref:` from `github.event.pull_request.base.sha` to `github.event.pull_request.head.sha` on the checkout step's `with:` block | Yes, naming the head ref | Yes |
| `workflow_concurrency_group_is_keyed_to_matrix_target` | Change the `validate` job's `concurrency.group` from `closing-keyword-scope-${{ matrix.pr }}` to `closing-keyword-scope-${{ github.event.pull_request.number }}` | Yes, naming the trigger-keyed group | Yes |

Each violation is planted on a **copy** of the shipped workflow, never on the shipped file, following the pattern `test-worktree-recipe.sh` established in #1593. The PR evidence records the file and line of each plant and both runs.

The validator's own rules are covered by the unit suite rather than by planted violations: they are not an automated *check* in REVIEW.md's sense, they are the feature's behaviour, and the suite asserts them directly.

**Post-release verification** is the smoke runbook, run against a scratch pull request pair after the release that lands this on `main`. Until then it is a written artifact, not an executed one, and the implementation PR should say so rather than claim a smoke test it could not have run.

The first release carrying this feature therefore has one manual step beyond the usual: run the runbook, and if it fails, the rollback is deleting the workflow file — no state needs unwinding, as the next section describes.

---

## What this leaves behind, and how to remove it

The feature creates state that outlives the pull request that introduced it. None of it is destructive, and none of it is automatically cleaned up, so the removal path is written down rather than assumed.

| What is created | Where it lives | Removing it |
| --- | --- | --- |
| The `multi-issue-intentional` label | Repository labels, created idempotently on first use | `gh label delete multi-issue-intentional`. Deleting it removes it from every pull request that carried it, which silently re-enables the warning on those; delete only together with the workflow |
| Report comments | One per validated pull request | Not swept. Deleting the workflow leaves the last report standing on each pull request it touched, stating a result that is no longer maintained. To remove them, list comments whose body has a line starting with the marker prefix and delete them — the same lookup the validator uses |
| Check runs | One per validated head SHA on the normal path, and one **more per run** whenever the check-run listing is unreadable — see the indeterminate rule; that count has no bound | **Cannot be deleted through the API.** They age out with their head SHA and never block a merge. This is a one-way door and the reason the indeterminate conclusion is `neutral` rather than a failure |
| The workflow file and the scripts | `.github/workflows/closing-keyword-scope.yml`, `scripts/development-workflow/` | Ordinary revert. `closing-keyword-lib.sh` is also sourced by `post-merge-cleanup.sh` after the extraction, so a revert must restore the filter inline there or `post-merge-cleanup.sh` breaks |

Disabling without removing is the cheaper rollback and should be the first move if the feature misbehaves: delete or rename the workflow file. Nothing else in the repository depends on it running, existing reports go stale but stay accurate about the moment they were written, and no state needs unwinding.

---

## Implementation Order

1. Extract `strip_fenced_pr_body_blocks` and the keyword regex into `scripts/development-workflow/closing-keyword-lib.sh`; source it from `post-merge-cleanup.sh`. **Verify**: run `scripts/development-workflow/tests/test-post-merge-cleanup.sh` and confirm it still passes, so the move changed no behaviour.
2. Add `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh` with the parity test only, and confirm it passes against the extracted library before any new logic exists.
3. Implement filtering and keyword extraction in `validate-closing-keyword-scope.sh`, including the base-branch selection and the differential attribution. **Verify**: the parser edge-case tests pass, including the title-opens-then-description-closes case.
4. Implement ownership resolution. **Verify**: the ownership tests pass, including contested, no-signal, team-prefixed, documentation-stage and closed-sibling cases.
5. Implement the opt-out, including idempotent provisioning and the failed-provisioning warning line.
6. Implement the single-accessor input reads and the indeterminate outcome. **Verify**: one test per gate input confirms an unreadable input leaves an existing report untouched and posts nothing.
7. Implement report publication, freshness and the ordering stamp. **Verify**: the overlapping-run tests pass.
8. Add `.github/workflows/closing-keyword-scope.yml` with the trigger set, permissions, the SHA-pinned base-commit checkout, the job-level fork `if:`, the `resolve-targets` / `validate` split and the target-keyed concurrency group. Complete the Protocol 03 GitHub Actions workflow security checklist for it before opening the development PR.
9. Add the sibling fan-out to the workflow. **Verify**: run the workflow's job locally where possible, and confirm the fan-out list is derived from open pull requests only.
9b. Produce the three planted-violation proof pairs described under *When the workflow actually starts running*, and record each plant's file and line plus both runs in the PR evidence. This is blocking for `ready-for-human-review`, not optional.
10. Write `docs/testing/workflow/1644-cross-pr-closing-keyword-validation.smoke-test.md`. **Do not attempt to execute it before merge** — see *When the workflow actually starts running* below for why it cannot fire yet, and for what replaces it as pre-merge evidence.
11. Update the project docs listed under **Documentation Updates**.
12. Add the changelog fragment. This traces to no acceptance criterion — it is a **repository process requirement**: Step 6 of `03-implement-development-protocol.md` requires a `changelog.d/<item>.<kind>.<slug>.md` fragment for normal feature work, written as the finished bullet from the user's perspective. The literal is fixed here so the implementer does not restate the feature in conventional-commit form, which the repository's changelog assembly rejects. Add `changelog.d/1644.added.cross-pr-closing-keyword-validation.md` containing:
    `- **Cross-PR closing keyword validation** (#1644): a pull request that declares a closing keyword for an issue a sibling pull request is carrying now gets an advisory warning naming the issue and the sibling, so the mistake is caught while the batch is still in flight rather than after a release has been assembled around the wrong scope. The warning never blocks a merge, and a pull request that deliberately closes several issues can silence it with the multi-issue-intentional label.`
