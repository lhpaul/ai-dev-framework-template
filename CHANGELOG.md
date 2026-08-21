# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Change-scoped CI test selection with a coverage-gap report** (#1537): adds
  `scripts/development-workflow/select-test-suites.sh`, which resolves the
  suites a change set requires from the repository itself — a `test-<name>.sh`
  covers `<name>.sh` by convention, and a suite whose name does not match its
  subject declares what it exercises with `# covers:` header lines next to the
  test rather than in a central map that drifts. `--report-gaps` lists workflow
  scripts with no suite (4 of 64 once the `# covers:` headers land, down from
  the 15 reported on the issue) and suites no change set can select (0 of 66),
  so the gap stays visible rather than silent.
- **Artifact ownership and product release contract** (#1353): documents and
  validates multi-repository release artifact ownership and product release
  configuration for workflow hubs.
- **One product repository per implementation item** (#1354): enforce
  one-target workflow-hub routing before product implementation mutation.
- **Route component releases to selected product repositories** (#1356): add
  canonical component release target and evidence helpers, plus product-aware
  release cleanup validation for workflow hubs.
- **Add delivery bundle manifest workflow** (#1357): add hub-owned delivery
  bundle issue and manifest tooling for coordinated component delivery evidence.
- **Add component milestone release statuses** (#1358): add workflow-hub
  component milestone and parent release-state reconciliation for
  multi-repository releases.
- **Add multi-repository release adoption assurance** (#1359): add
  workflow-hub adoption guidance and deterministic assurance coverage for
  multi-repository releases.

### Fixed
- **Adding a test job to a CI workflow no longer scores the same risk as
  changing deployment behavior** (#1565): `run-epic-risk-classifier.sh` treated
  every `.github/workflows/**` change as a sensitive category and escalated the
  PR to `high`, so a PR that wires a test suite into CI exceeded a `medium`
  ceiling and could not merge under delegated policy — the risk model penalised
  closing a test-coverage gap, which is what #1537 asked for. Recognised test
  and lint workflows now score `medium` with a distinct
  `test or lint CI workflow change:` reason; deployment, release, and permission
  behavior still score `high`, as does any unrecognised workflow. The classifier
  only ever receives changed paths, never file contents, so this is judged by
  filename — see the authoritative pattern table under "Known Heuristic Limits"
  in
  [guardrails-enforcement.md](docs/workflow/development-workflow/guardrails-enforcement.md).
- **Every test suite is now reachable from CI, so a green check rollup means
  the changed script's own tests ran** (#1537): CI ran a hard-coded list of six
  suites behind a path filter, leaving 59 of 65 suites never executed by any
  workflow. Because "all checks green" is the signal the reviewer loop, the
  readiness labels, the delegated merge gate, and `item-completion-self-check.sh`
  all lean on, that signal was vacuous for most scripts in this repository — it
  reported that six unrelated suites passed. `.github/workflows/test-pr-review-loop.yml`
  is replaced by `.github/workflows/workflow-tests.yml`, which asks the new
  `select-test-suites.sh` which suites a pull request's changed files require
  and runs those as a matrix, with a nightly scheduled full run as the backstop.
  The workflow contains no list of suites, so adding a `test-*.sh` no longer
  requires a workflow edit — the drift that let the count reach 59.
- **`github-app-token.sh` no longer leaves the signed JWT (and, on the
  `secret_ref` path, the private key) behind in a temp directory** (#1537):
  `exchange_token` is called as `TOKEN="$(exchange_token ...)"`, so its
  `TOKEN_TMP_DIR` assignment was confined to that command-substitution
  subshell. The parent's `EXIT` trap therefore had an empty path and cleaned
  nothing, leaking `header.json`, `payload.json`, `signature.bin`, and any
  resolved `private-key.pem` on every successful token mint. The scratch
  directory is now created in the parent shell so the trap can remove it. The
  suite asserted this all along, but BSD `mktemp -d` ignores `TMPDIR` while GNU
  `mktemp -d` honours it, so the assertion was vacuous on macOS and the suite
  never ran on Linux to catch it.
- **Five test suites that could never have passed in CI now do** (#1537):
  wiring the suites into CI surfaced latent environment assumptions in suites
  that had only ever been run on developer machines.
  `test-component-milestone-reconciliation.sh` required `ripgrep`, which is not
  installed on `ubuntu-latest` (now `grep -c -E`, whose semantics match).
  `test-run-nested-artifact-guard.sh` and `test-prepare-release-tracker-cleanup.sh`
  built a `PATH` from real system directories to hide or shadow `gh`, which
  works only where `git` and `gh` live in different directories — true under
  Homebrew, false on runners where both are `/usr/bin`, so one silently tested
  nothing and the other ran the real `gh` instead of its mock.
  `test-workflow-orchestration-product-repo-aware.sh` reached `require_gh`
  before its `gh` stub was defined, making it depend on an ambient GitHub
  login. `test-workflow-hub-pr-auth.sh` is covered by the entry above.
- **`test-haystack-reviewer.sh` no longer fails intermittently when run
  alongside other work** (#1537): the suite failed roughly 2 runs in 17 on a
  clean tree at the same commit (205 passed / 5 failed versus 210 / 0), always
  during or just after a full sweep. All five failures came from one test,
  which gave the reviewer a 3-second budget; `haystack-reviewer.sh` derives the
  per-call triage timeout as half the remaining budget, so its first call had a
  1-second allowance polled at 1-second granularity. Under CPU contention,
  forking the mock CLI exceeded that, the call was killed, and the budget
  expired before any call completed. Reproduced deterministically at load
  average ~42 on an 11-core machine and fixed by widening the budget to 12
  seconds against a 30-second hang, preserving the ratio the test depends on.
  This mattered before batching the suites, not after: a suite that passes
  alone and fails in a batch is exactly the failure mode running them together
  would have introduced, and intermittent red teaches everyone to re-run until
  green.
- **`run-epic-risk-classifier.sh --pr` can now attach `why_safe_to_merge`
  evidence, and Gate 5 evidence-schema mismatches no longer read as a denied
  merge authority** (#1497): a medium-risk PR classified via `--pr` always
  reached `blocked` ("medium-risk PR is missing complete why_safe_to_merge
  evidence") because `--pr` had no way to attach that evidence — only
  `--input`'s undocumented, hand-normalized shape could carry it. A new
  `--why-safe-file <file>` flag merges a `why_safe_to_merge` object into the
  classified state for either `--pr` or `--input` mode, and `--help` on both
  `run-epic-risk-classifier.sh` and `run-epic-delegated-gate.sh` now
  documents each script's evidence schema with a worked example, including
  that the two schemas are different and must not be fed into one another
  directly (nest the classifier's result under a top-level `risk` key
  instead). Separately, `run-epic-delegated-gate.sh` used to report a
  malformed or incompatible evidence file (e.g. one built from the risk
  classifier's own flat output) as `delegated review authority is missing`,
  `delegated merge authority is missing`, or `required CI state is missing`
  — three reasons that read as a policy or CI verdict when the real problem
  was a missing `.policy` object or an entirely absent `.statusChecks[]` key,
  risking an operator concluding they lack merge permission when they
  actually have a JSON shape bug. Both cases now report a distinct
  `evidence_schema_mismatch: ...` reason (still routed to `human_required`,
  since the gate cannot safely default an authority/CI verdict either way)
  naming exactly which required shape is missing, with `nextAction` text that
  explicitly says this is not a policy or CI-state blocker. A present-but-
  empty `.statusChecks: []` (a genuine "no CI has run" state) keeps its
  original wording and `blocked` decision unchanged — only the schema-shaped
  absence is new. When `ciPolicy`/`ci_policy` is `none`, no CI reason is
  added at all (as before this PR); the overall decision then depends only
  on other evidence and is not necessarily `blocked`. A
  CodeRabbit review on the PR caught a sharper variant of the same bug: a
  key-existence check alone (`has("statusChecks")`) accepted `null`, an
  object, or a scalar for `.statusChecks`, none of which are the array the
  gate actually expects — a `null` silently defaulted to `[]` and reported
  the old generic message instead of a schema mismatch; an **object** had its
  *values* iterated as individual check entries (jq's `map`/`.[]` accept
  objects), so a single well-formed-looking check value one level too deep
  could read as CI having passed, silently producing a false
  `merge_allowed` verdict for malformed input rather than merely an unclear
  message; a scalar aborted the whole jq program. `.statusChecks` is now
  required to literally be an array before any CI evaluation runs against
  it, and (per a CodeRabbit follow-up finding) every array member must
  itself be an object — a string or number member reached the same field
  accessors and crashed the same way a non-array top-level value did, and a
  `null` member silently read as a generic CI failure instead of the more
  legible schema-mismatch reason. Also fixed: a `.pr.mergeable` value
  defaulted to `""` by a
  caller that omitted `mergeable` from its `gh pr view --json` field list
  used to be read as a real "PR is not mergeable" verdict for a PR GitHub
  reports as `MERGEABLE`; a blank/whitespace-only `mergeable` string is now
  treated exactly like an absent field (not blocked), while a genuine
  non-mergeable state (e.g. `CONFLICTING`) still blocks. `guardrails-
  enforcement.md`'s Gate 5 section documents the evidence schemas, the
  `--why-safe-file` flag, and both pitfalls. New regression coverage in
  `scripts/development-workflow/tests/test-run-epic-risk-classifier.sh` and
  `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
  reproduces all three failure modes against the unfixed scripts before
  confirming the fix.
- **`workflow-batch-overlap.sh` no longer treats ordinary prose as a module
  collision or serializes provably independent pairs** (#1540): brief text
  like "the helper **emits** false rows" no longer produces a fake `module`
  signal, and a pair with a signal on only one side (nothing shared or
  related) no longer defaults to `suspected`/serial — it now requires
  independence-defeating evidence on **both** sides. Genuinely overlapping
  pairs still classify `concrete`. `suspected` explanations now name the
  specific triggering signal(s). Regression tests cover the issue's
  reproduction, verb-capture fixtures, a concrete-overlap control, and the
  two real overnight-batch wave sets from the issue (previously one serial
  group of 4 each, now fully parallel-eligible).
- **Item runners no longer park permanently after backgrounding a long step
  and ending the turn to wait for it** (#1548): three of four Work Item
  Runners in one overnight wave backgrounded a step (`test-pr-review-loop.sh`,
  `pr-review-loop.sh`) and ended their turn expecting an external notification
  to resume them — ending a turn ends the agent, so nothing ever resumed
  them, and each item was recovered only because a supervising parent noticed
  the returned report named no terminal state. `91-orchestrate-work-protocol.md`
  now states plainly, in a new "Execution Discipline: A Paused Turn Does Not
  Resume" section read before Step 0, that a paused turn does not resume, and
  prescribes foreground-or-poll for every long step, not only
  `pr-review-loop.sh`/`pr-ci-loop.sh`; Step 7 and the agent/skill instruction
  files (`.claude/agents/item-orchestrator.md`,
  `.cursor/agents/item-orchestrator.md`,
  `.codex/skills/workflow-item-orchestrator/SKILL.md`) carry the same rule
  directly, plus a companion warning against re-invoking `pr-review-loop.sh`
  on a PR whose loop is already running (it exits `75` with
  `REASON=lock_contention` and reports nothing useful) — read the outcome
  from PR state instead. On the parent side, `90-batch-orchestrate-work-
  protocol.md` Step 5's supervision loop now classifies any returned report
  that names no terminal state (no PR number paired with
  `ready-for-human-review`, `blocked`, or `escalated` — or, for an item with
  no PR yet, a concretely-named blocking reason; a bare "waiting" report never
  satisfies that exception regardless of phrasing) as `stalled` and requires
  resume/re-dispatch rather than acceptance, extending the existing "in-flight
  CI/watch states are non-terminal" rule from governing runner behavior to
  governing how the parent reads runner reports. Added the
  [runner-stall supervision smoke-test runbook](docs/testing/workflow/1548-runner-stall-supervision.smoke-test.md),
  since there is no automated test harness for protocol prose in this repo.
- **`list_open_workflow_type_issues` no longer hardcodes a `.type` field key**
  (#1400): `gh project item-list --format json` derives each item's field key
  from the field's display name, lowercasing only its first character (for
  example `Custom Type` -> `custom Type`). Because `Type` is a reserved
  GitHub Projects field name, no conforming board can actually name its
  classification field `Type`, so the hardcoded `select((.type // "") ==
  "Workflow")` never matched anything on a real board — release protocol
  §7.2's "downstream script-bug review" gate silently returned `[]` on every
  release regardless of how many open Workflow items existed. The lookup now
  resolves the same field-name order as
  `workflow_github_project_type_field_json`:
  `issue_tracker.custom_fields.type_field`, then `Custom Type`, `CustomType`,
  then `Type`, each converted to its gh item-list key. When the item-list
  payload has at least one item and none of those keys are present on any of
  them, the function now emits a distinct stderr warning so a genuinely
  unreadable Type field is no longer indistinguishable from a clean "no open
  Workflow items" result — an empty board (zero items on the project, e.g.
  open issues not yet triaged onto it) is left alone and does not trigger the
  warning, since there is nothing to judge the candidate keys against. The
  shipped regression test's fixture previously mocked a `"type":"Workflow"`
  key that real `gh` cannot produce; it now uses `"custom Type"`, matching a
  real board, plus new cases for a configured `type_field` override, the
  unreadable-field warning, and the empty-board non-warning case.
- **A replied-to but unresolved review thread no longer blocks the very
  re-review it was replied about** (#1508): `check_unresolved_threads` in
  `scripts/development-workflow/pr-review-loop.sh` gated the phase-1
  "should we trigger a new review" check in `run_codex_github_review` and
  `run_claude_code_action_review` purely on GraphQL `isResolved` state. When a
  fixer pushed a fix and replied to a thread without also calling
  `resolveReviewThread` — the normal state immediately after a push — the
  loop returned `RESULT=needs_fixes REASON=existing_findings` and never
  re-triggered the platform review, so the reviewer never saw the fix commit
  until a human resolved the thread manually out of band. `check_unresolved_
  threads` now takes a required `mode` argument. `mode=provisional`, used only
  by those two phase-1 pre-trigger gates, additionally treats a thread as not
  blocking re-review when its last comment is from a non-bot author posted
  after the PR's current head-commit `committedDate` — modeling "fixed and
  replied to, awaiting explicit resolution". Every gate that decides
  `RESULT=clean` (the aggregate thread gate, `coderabbit_thread_gate_clean`,
  the post-trigger findings recount, and the post-clean recheck) keeps using
  `mode=strict`, which is byte-for-byte the prior behavior — a reply alone
  still can never mark a thread resolved there, so this cannot reintroduce the
  false-clean class fixed by #1531 and #1437. Unrecognized mode values fail
  safe to `strict`. New regression tests in
  `scripts/development-workflow/tests/test-pr-review-loop.sh` cover both
  directions: the reply-after-head-commit case that must not block
  re-triggering (confirmed to fail against the pre-fix code), and reply-
  before-head-commit / bot-authored-reply / no-reply / true-resolution cases
  that must still block under both modes.
- **`post-merge-cleanup.sh` no longer closes the wrong issue for team-prefixed
  branch slugs** (#1511): the team-prefixed identifier pattern
  (`^(fix|feature|hotfix|refactor)/([a-zA-Z]{2,6}-([0-9]+))($|-)`) matches any
  slug beginning with 2-6 letters followed by `-<digits>` — including ordinary
  descriptive fragments with no relation to an issue number
  (`fix/retro-517-doc-gaps`, `fix/http-500-retry`, `feature/sha-256-hashing`).
  A downstream consumer observed the script silently update and close an
  unrelated issue derived from such a slug. The merged PR body/title is now
  checked first for GitHub closing keywords (`Closes #N`, `Fixes #N`,
  `Resolves #N`, etc.) whenever the branch slug's identifier is
  team-prefixed, and that reference is treated as authoritative when present
  — including when the PR closes more than one issue. The slug-derived
  identifier is only used as a fallback when the PR body carries no closing
  reference at all, preserving existing behavior for legitimate team-prefixed
  slugs (`fix/lh-97-real-issue`) merged without an explicit closing keyword.
  Plain numeric identifiers (`fix/42-slug`) are unambiguous and are unaffected.
  The closing-keyword matcher also now requires only a non-word boundary
  (rather than specifically whitespace) before the keyword, so
  punctuation-delimited references like `(Fixes #601)` are recognized, and it
  strips fenced code blocks before matching so an example `Closes #999` in a
  code sample within the PR body is not mistaken for a live reference —
  mirroring `graduation-closeout-from-merged-pr.sh`'s existing
  `extract_closing_issue_numbers` / `strip_fenced_blocks` behavior.
- **Security-checkpoint keyword test no longer matches substrings** (#1504):
  `recommend_checkpoints_for_item` in
  `scripts/development-workflow/run-epic-policy-recommender.sh` matched the
  security/auth checkpoint keywords with a bare, unanchored alternation, so
  ordinary vocabulary ("authoring", "author", "authority", "insensitive")
  tripped a pending human checkpoint and halted an otherwise fully delegated
  `/run-epic`/`/run-items` run on issues with no actual security content (live
  reproduction on `/run-items 1502 1501`). The keyword regex is now
  `\b`-anchored so real security/auth terms — including negated forms like
  `unauthorized`/`unauthenticated` — still match while incidental substrings no
  longer do. The checkpoint `reason` now names the matched term and quotes the
  source line instead of a generic static message. The sibling unresolved-
  product and trade-off/architecture classifiers shared the same
  bare-alternation defect and are now `\b`-anchored too. 13 new regression
  tests cover the false-positive corpus (confirmed to fail against the pre-fix
  regex) and the true-positive corpus.
- **CodeRabbit "Review skipped" banner no longer reports an unreviewed PR as
  clean** (#1531): `run_coderabbit_review` in
  `scripts/development-workflow/pr-review-loop.sh` counted any CodeRabbit issue
  comment as evidence of a completed review, excluding only the pause,
  rate-limit, and resume markers. CodeRabbit's fourth non-review banner —
  `Review skipped`, posted whenever it declines by configuration rather than by
  capacity (`auto_review.enabled: false`, `drafts: false` on a draft PR, or an
  `auto_review.base_branches` list that omits the PR's base) — satisfied that
  check, broke the poll loop into Phase 3, and returned `RESULT=clean` after
  collecting zero inline comments. The banner is now matched by
  `CODERABBIT_SKIP_BANNER_RE`, excluded from the activity probe so the existing
  silent-non-trigger path nudges CodeRabbit with an explicit
  `@coderabbitai review` (which works even when auto review is disabled), and
  escalated as `REASON=review_skipped_banner` if it is still standing when the
  poll window closes — a distinct reason from `rate_limit_max_retries`, since
  the operator fix is a `.coderabbit.yaml` change rather than waiting out vendor
  quota. Same false-clean class as #1437 and the PR #650 pause-banner incident.
- **CodeRabbit rate-limit tolerance now spans an hourly quota reset** (#1531):
  `CODERABBIT_RATE_LIMIT_MAX_RETRIES` and `CODERABBIT_RATE_LIMIT_WAIT` defaulted
  to `2` and `180`, giving roughly six minutes of tolerance against a vendor
  whose quota resets hourly — so a loop that hit the cap exhausted its retries
  about 54 minutes before CodeRabbit could possibly answer, then escalated a PR
  with nothing wrong with it. Defaults are now `4` and `900`, covering a full
  60-minute reset window; both env vars still override.
- **ShellCheck CI no longer hangs indefinitely installing zsh** (#1517):
  the `Install zsh for cross-shell snippet tests` step in
  `.github/workflows/shellcheck.yml` was observed hanging on three PRs, and
  reproducibly on two consecutive runs of the same commit — 24 minutes before
  manual cancellation, with `Run ShellCheck` itself already passed. The step
  declared no timeout, so the job inherited the 6-hour Actions default and held
  the PR's merge state `UNSTABLE` for that entire window. The step now bounds
  itself with `timeout-minutes: 5`, skips entirely when `zsh` is already present,
  waits explicitly (bounded) for any `dpkg`/`apt` lock holder such as the runner
  image's `unattended-upgrades` job instead of blocking inside `apt-get`, sets
  `DEBIAN_FRONTEND=noninteractive`, and retries up to three times before failing
  with a clear error. A stall now surfaces as a fast, legible failure rather than
  a silent multi-hour block.
- **Retrospective follow-ups to batch-merge output and CHANGELOG guidance** (#1520):
  `batch-merge.sh`'s `WARNING: gh pr merge failed` message now explains what
  `MERGE_RESULT=clean` does and does not cover, instead of leaving the two
  looking contradictory: the local merge and push succeeded, but GitHub has not
  recorded the PR as merged, and per Protocol 94 Step 4.2 the PR is `failed`
  unless the MERGED-state poll converges within 30s. The `WARNING:` prefix is
  deliberately retained — Protocol 94 Step 4.2 references that exact string —
  and the protocol wording is updated to match. `usage()` also documents that `recheck-remaining --after-merged-pr`
  must name a PR that appears in the `--prs` frozen list, which previously was
  discoverable only by triggering `reason=after_merged_pr_not_in_frozen_list`.
  `docs/best-practices/2-version-control.md` now states that CHANGELOG entries
  describe shipped behavior rather than the review history of the PR that produced
  them — a content rule, not a length rule. No behavior change.
- **`pr-review-loop.sh` ready-phase gate no longer reports a GitHub API
  rate-limit outage as a review verdict** (#1509): a `gh pr view`/`gh pr ready`
  failure in `ensure_pr_ready_for_ready_phase` previously always produced
  `RESULT=escalate REASON=ready_for_review_failed` plus the `reviewer-failed`
  label, with no distinction from a genuine review-gate failure. The gate now
  probes `gh api rate_limit` on that failure; a confirmed core/graphql
  exhaustion reports `REASON=rate_limited` with the reset timestamp instead,
  and `reviewer_failed_label_required_for_result` no longer applies
  `reviewer-failed` for that reason. An unexplained `gh` failure keeps the
  original `REASON=ready_for_review_failed` behavior.

- **Codex GitHub terminal evidence**: `codex-github-reviewer.sh` no longer
  treats a thumbs-up reaction on the trigger comment as a clean review result,
  ignores submitted Codex reviews that are not pinned to the current PR head,
  accepts only root PR comments that include a current-head `Reviewed commit`
  marker as terminal evidence, and reports missing Codex cloud environments as
  unavailable instead of clean. Timestamp ties between a SHA-pinned root
  comment and a submitted review now resolve away from a clean approval
  regardless of which side supplied it — covering both explicitly blocking
  evidence and an unrecognized-format response that the verdict classifier
  would otherwise safe-fail to `NEEDS_REVISION`; the terminal root comment is
  selected independently of the latest (possibly non-terminal) root comment
  so a later acknowledgement can no longer discard an earlier blocking one; a
  failed root-comments fetch during the async grace period, the
  post-acknowledgement re-poll, and the post-reaction re-poll now fails
  closed (`TIMED_OUT`) instead of silently falling through to a clean
  submitted review; the final acknowledgement re-poll now preserves a
  recorded environment-setup error over a thumbs-up reaction, matching the
  post-reaction re-poll's existing behavior; all four `APPROVED` exit sites
  (main poll loop, async-arrival grace, async-final, async-reaction-final)
  now check a previously recorded environment-setup error before exiting
  clean, instead of only some of them, and now also allow a genuinely fresh
  (strictly newer) current-head review to supersede a now-stale recorded
  environment error rather than blocking recovery indefinitely within the
  same invocation; the timestamp tie-break helper now treats a response
  containing both a blocking marker and an approval phrase as blocking
  first, matching the verdict classifier's own blocking-first priority,
  instead of misclassifying it as a clean approval; a submitted review body
  large enough to exceed a pipe buffer no longer crashes the script with
  `SIGPIPE`/exit 141 under `pipefail` — truncation now happens inside `jq`
  (codepoint slice) instead of via a piped `head`; a clean review and a
  strictly newer environment-setup-error comment observed in the same poll
  no longer resolve to a silent `APPROVED` — the setup error is retained
  unless the review is itself strictly newer; and an environment-setup-error
  comment is no longer silently discarded by a later plain acknowledgement
  observed in the same comments fetch; a clean SHA-pinned terminal root
  comment and a strictly newer environment-setup-error comment in the same
  fetch no longer resolve to a silent `APPROVED` — environment-error
  checking is now a final, independent step applied to whichever of
  (terminal comment, review) won, instead of only being reachable from the
  review-vs-ancillary-comment branch; and root-comment-sourced bodies (not
  truncated at scan time, unlike review bodies) are now also truncated via
  `jq -Rrs` instead of a piped `head`, closing the same `SIGPIPE` crash path
  for a root comment body large enough to exceed a pipe buffer; a blocking
  SHA-pinned terminal or review finding is no longer discarded by a
  same-or-newer environment-setup-error comment — blocking evidence now
  always wins outright, regardless of timing; and a SHA-pinned terminal
  comment is no longer misclassified as an environment-setup error when its
  finding text happens to quote the setup sentence verbatim (e.g. flagging
  stale documentation) — terminal evidence is never routed through the
  environment-error classifier; multiple current-head reviews tied at the
  same second-resolution `submitted_at` timestamp no longer collapse to an
  arbitrary array-order pick via `sort_by | last` — every tied review is
  now considered and the one requiring attention (if any) wins, so a
  blocking review can no longer be silently discarded by a clean one
  submitted in the same second; and usage-limit comments are now retained
  and compared independently the same way environment-error comments
  already were, so an older clean review no longer silently wins over a
  newer usage-limit notice; two current-head terminal root comments tied at
  the same second no longer collapse to whichever was scanned last —
  terminal-comment selection now applies the same not-a-clean-approval-
  first tie-break as reviews; and blocking is now checked before
  usage-limit in every verdict path, so a blocking finding whose text
  happens to mention "usage limit" is no longer misrouted to an
  unavailable verdict; and a bodyless submitted review tied with a clean
  SHA-pinned terminal comment is no longer treated as absent — presence is
  now checked via the review's timestamp (always set for a genuine review)
  instead of its body, so an empty body still participates in the
  not-a-clean-approval-first tie-break instead of silently losing to a
  clean terminal comment; and the main-loop and async verdict paths' entry
  into verdict parsing is now gated on the winning evidence's timestamp
  instead of its body content, so a bodyless-but-selected review reaches
  the documented unrecognized-response safe-fail (`NEEDS_REVISION`)
  instead of falling through to `TIMED_OUT`; and among tied current-head
  reviews, a blocking one now always wins outright over any other
  non-clean type (e.g. a usage-limit response) instead of the scan
  stopping at whichever "requires attention" response was returned first,
  so a usage-limit review returned before a tied blocking review no longer
  silently discards the blocker; and the shared terminal-evidence tie-break
  (used for terminal-comment-vs-review and terminal-comment-vs-terminal-
  comment ties) now checks blocking before the binary requires-attention
  distinction, so two tied responses that are both "requires attention"
  (e.g. a usage-limit root comment and a blocking submitted review, or two
  tied root comments) no longer keep whichever was evaluated first when
  one side is strictly more severe; a usage-limit response that ALSO
  contains an approval phrase (e.g. "No blocking issues could be evaluated
  because you have reached your Codex usage limits") is no longer
  misclassified as a clean approval by the tie-break; and the previously
  binary "requires attention" tie-break is replaced by a four-tier numeric
  priority (`codex_response_priority`: blocking > unrecognized format >
  usage-limit > clean approval), so two tied responses that were both
  merely "requires attention" (e.g. a usage-limit notice and a genuinely
  unrecognized-format response) are now ranked correctly against each
  other instead of the scan keeping whichever was evaluated first; and
  verdict classification now runs against the full, untruncated response
  instead of the 10000-char truncated copy — a SHA-pinned root review
  longer than the cutoff with an approval phrase before it and a blocking
  marker after it no longer has its blocker silently discarded (the
  truncated copy is still used for the script's own displayed output).
  The classification helpers (`codex_response_is_blocking` and friends)
  now match via a here-string instead of a piped `printf`, since
  classifying the untruncated response means `grep -q`'s early-exit
  behavior on a long input could otherwise SIGPIPE the writer; and the
  four reviews-endpoint jq queries (main poll, async-arrival, async-final,
  async-reaction-final) no longer slice a submitted review's body to
  5000 characters inside the query itself — that upstream truncation
  fed directly into the "full, untruncated response" classification path
  described above, so a submitted review with an approval phrase before
  the 5000-char query cutoff and a blocking marker after it was still
  misclassified as APPROVED even with the shell-level fix in place (the
  slice is dropped entirely; GitHub review bodies are capped well below
  any size that would make this unsafe, and the query already writes to
  a temp file rather than a piped consumer, so there is no SIGPIPE risk);
  `codex_response_is_approved` now rejects negated approval phrases (e.g.
  "This change is **not** approved") instead of matching the unbounded
  `approved`/`lgtm`/`looks good` alternatives unconditionally, which used
  to report a rejecting terminal response as APPROVED instead of the
  documented unrecognized-format safe-fail; and `codex_response_priority`
  now ranks an ancillary environment-setup-error comment at the same
  lower availability tier as a usage-limit notice instead of at the
  unrecognized-format tier, so a setup-error comment tied at the same
  timestamp as a genuine but unrecognized-format review can no longer win
  the tie-break and replace the review's safe-fail NEEDS_REVISION with an
  UNAVAILABLE-style `codex-github-environment-missing` verdict;
  `CODEX_APPROVAL_PATTERN`'s positive alternatives now require `\b` word
  boundaries, since the negated-approval fix above only catches
  SPACE-separated negations ("not approved") — a CONCATENATED negation
  prefix like "unapproved" or "disapproved" still matched the bare
  "approved" substring and was reported as APPROVED; and
  `CODEX_NEGATED_APPROVAL_PATTERN` now tolerates optional Markdown
  emphasis markers between the negation and approval words, since GitHub's
  rendered bold (e.g. "This change is **not** approved") has `**` wedged
  directly between "not" and the following space in the raw comment body,
  which broke the pattern's original unbroken-whitespace adjacency
  requirement and let the negation go undetected; and
  `CODEX_NEGATED_APPROVAL_PATTERN` now tolerates up to 3 intervening
  qualifier words between the negation and approval words (e.g. "This
  change is not **yet** approved"), generalizing past the specific
  adjacency assumptions of the three prior negation fixes above instead
  of special-casing yet another interrupting-word pattern; and
  `codex_response_is_usage_limit`'s broad "codex ... usage limit/quota/
  capacity" alternative now requires an accompanying exhaustion/
  unavailability word directly after the noun, since it previously matched
  ANY mention of those words — a clean submitted review merely discussing
  this PR's own usage-limit-detection code (e.g. "No blocking issues
  found. The Codex usage limit handling looks correct.") was itself
  misclassified as a usage-limit notice, winning a same-timestamp tie
  against a genuinely clean terminal comment and returning UNAVAILABLE
  instead of APPROVED for an actually-clean PR. Also corrected
  `docs/workflow/development-workflow/integrations/codex-github.md`,
  which claimed a usage-limit notice follows the same *retention* rule as
  an environment-setup error — it does not: unlike an environment-setup
  error, a usage-limit notice terminates the invocation immediately upon
  detection rather than being retained through the rest of the poll
  window for a later, strictly newer review to potentially supersede;
  `CODEX_NEGATED_APPROVAL_PATTERN`'s target alternation now also covers
  "no blocking issues"/"didn't find any major issues", not just
  "approved"/"lgtm"/"looks good" — those are approval signals in
  `CODEX_APPROVAL_PATTERN` too, but were left unguarded, so a
  hedged/uncertain response like "I cannot confirm there are no blocking
  issues" still matched "no blocking issues" and was classified APPROVED;
  and `codex_response_is_usage_limit`'s second alternative ("codex usage
  limits for code reviews") had the exact same unguarded-mention gap as
  the third alternative fixed in the same round — missed in that first
  pass since only the third alternative was narrowed then — so a clean
  review discussing the phrase in a docs context was itself misclassified
  as a usage-limit notice; it now requires an exhaustion word after "code
  reviews" too; and `CODEX_NEGATED_APPROVAL_PATTERN`'s bounded `{0,3}`
  filler-word window (added to handle "not YET approved") was itself
  proven insufficient — a response with 5 intervening words between the
  negation and approval word exceeded the bound and was still classified
  APPROVED. Replaced with an unbounded same-sentence scope (`[^.!?]*`
  between the negation and approval words): this closes the whole class
  of "negation not immediately adjacent to approval word" gap at once
  (this was the fourth round of narrowly-scoped fixes to this same
  pattern — space-separated, concatenated-prefix, Markdown-wrapped,
  bounded-window — each of which Codex found the next edge of), while a
  sentence terminator between them still correctly prevents an unrelated
  later sentence's approval phrase from being treated as negated by an
  earlier sentence's negation word. Also corrected the same *retention*
  vs *priority* rule ambiguity as the integrations-doc fix above in
  `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`,
  which had not yet been updated when the integrations doc was fixed. Two
  more negation gaps surfaced once the pattern was unbounded: the target
  alternation had "approved" but not the bare verb "approve", and the
  pattern only checked negation-THEN-approval order, so an approval
  phrase appearing BEFORE the negation in the same sentence (e.g. "This
  looks good at first glance, but I cannot approve this change") wasn't
  caught. Both alternation orders are now checked, and the target list
  includes the bare verb. Separately, `codex_scan_comment_evidence` now
  tracks `COMMENT_LATEST_IS_TERMINAL` (whether the "latest ancillary
  comment" is actually the SHA-pinned terminal comment itself, not a
  genuinely separate one): when a clean terminal review's own finding
  text happened to quote the environment-setup message or usage-limit
  wording, `codex_combine_terminal_evidence`'s ancillary-override check
  re-classified that SAME terminal comment as a genuinely separate
  ancillary setup failure, downgrading APPROVED to
  `codex-github-environment-missing` — a case the existing "terminal
  comment never routed through the environment-error classifier"
  guarantee did not cover, since it only applied to the terminal-vs-review
  combine path, not this separate ancillary-override check. The reverse
  alternation order added above ("looks good ... cannot approve") turned
  out to be over-broad in practice: it matched ANY later negation word in
  the same sentence regardless of what it actually negated, so a
  genuinely clean response like "Looks good overall; tests were not run."
  was incorrectly flagged as negated. It has been removed — the
  forward-only match plus the bare-verb addition already covers the
  original "cannot approve" case without this false-positive class.
  Separately, `codex_combine_terminal_evidence` previously applied the
  same newest-wins comparison to a usage-limit ancillary comment as it
  does to an environment-setup error, so a clean current-head review
  returned in the SAME poll fetch as (and strictly newer than) a
  usage-limit notice let the review win, and the quota body never reached
  `codex_return_usage_limit` — contradicting the documented immediate-
  termination contract for usage-limit. Usage-limit and environment-error
  are now handled as two separate checks with their own retention
  semantics: a usage-limit notice wins unconditionally over non-blocking
  terminal/review evidence (no newest-wins comparison at all, since
  detecting it terminates the invocation immediately by design), while an
  environment-setup error keeps the existing newest-wins comparison. That
  fix only protected usage-limit precedence INSIDE
  `codex_combine_terminal_evidence`, but `codex_scan_comment_evidence`'s
  upstream tracking could already discard a usage-limit comment in favor
  of a LATER environment-error comment within the SAME fetch, before
  `codex_combine_terminal_evidence` was ever reached — both set
  `is_actionable=1`, so the unconditional overwrite let the later
  setup-error body silently replace the quota body. `codex_scan_comment_
  evidence` now tracks whether the currently-held ancillary comment is
  specifically a usage-limit notice, and once one is tracked, only
  another usage-limit notice may replace it. `codex_response_is_approved`
  now strips quoted spans (text between a pair of straight double-quotes)
  before matching `CODEX_APPROVAL_PATTERN`, since a SHA-pinned review can
  quote a clean phrase while rejecting it (e.g. `The documented bot
  response "No blocking issues found" is inaccurate`) and the pattern's
  substring match couldn't distinguish quotation/discussion of a phrase
  from an assertion of it. Separately, `CODEX_NEGATED_APPROVAL_PATTERN`'s
  `[^.!?]*` span only excluded sentence terminators, not clause
  separators, so an unrelated negation in an earlier semicolon-joined
  clause of the same sentence (e.g. "Tests are not required for this
  documentation-only change; looks good") still spanned into a later,
  unrelated clean clause; the character class now also excludes `;` and
  `,` (a followup finding showed a comma-joined clause crossed the
  semicolon-only exclusion the same way). A new shared
  `codex_strip_quoted_spans` helper now strips both straight-double-quoted
  spans AND backtick-quoted (Markdown inline code) spans — the earlier
  quote-stripping fix only handled straight quotes, so a review quoting a
  clean phrase with backticks instead still matched — and this stripping
  now runs ONCE, before BOTH the negation check and the positive approval
  check, since the earlier fix only quote-stripped the positive check: an
  otherwise-clean response quoting a REJECTION phrase from elsewhere
  (e.g. test/documentation text) still tripped the negation check on the
  unstripped body and incorrectly safe-failed. The helper is scoped to
  `codex_response_is_approved` only and never applied before
  `codex_response_reviews_current_head`'s SHA extraction, which itself
  relies on backtick-delimited `Reviewed commit:` markers. Separately,
  the top-level verdict-parsing elif chains' usage-limit check (all 4
  call sites) had no source gate and was not quote-stripped, so a clean
  terminal review that merely quotes an actual quota message (e.g. "No
  blocking issues found. The docs accurately quote: You have reached
  your Codex usage limits.") was reclassified as UNAVAILABLE instead of
  APPROVED — a case `COMMENT_LATEST_IS_TERMINAL` does not cover, since
  that guard only protects the ancillary-evidence combination stage, not
  this separate final verdict check. The check now quote-strips its
  input before classifying (a source gate isn't used here, unlike the
  already-safe environment-error check, since a genuine usage-limit
  notice can legitimately arrive via the reviews endpoint too).
  `codex_response_is_approved` now also strips the "not only X" idiom
  before running the negation check: "Not only X, (but) Y" is an
  affirmative intensifier construction (both X and Y are being asserted,
  not negated), not a negation of X, so `CODEX_NEGATION_WORDS`' bare
  "not" alternative — which has no way to distinguish this idiom from a
  genuine negation — misclassified "Not only does this look good, it is
  approved" as negated even though both phrases are affirmative. That
  strip only covered Title-Case and lowercase forms; a fully uppercase
  emphasis form ("NOT ONLY does this look good, it is approved") slipped
  through. Every letter is now bracket-expanded for both cases (rather
  than relying on sed's `I` substitution flag, whose support varies
  across sed implementations). `CODEX_NEGATION_WORDS` also now includes
  "unable to", which was absent entirely, so "I am unable to approve
  this change" wasn't recognized as a rejection while an earlier "looks
  good" in the same sentence still matched. `codex_strip_quoted_spans`
  now also deletes GitHub-flavored Markdown blockquote lines (a line
  starting with `>`), since a review discussing a quoted clean phrase via
  blockquote syntax rather than straight/backtick quotes was likewise
  unprotected. And `codex_response_is_blocking` — never quote-stripped at
  all, unlike the approval/negation checks — now shares the same
  `codex_strip_quoted_spans` normalization, since a quoted blocker token
  in an otherwise clean review (e.g. "No blocking issues found. The
  tests correctly cover the `must fix` marker.") still matched
  `CODEX_BLOCKING_PATTERN` and returned `NEEDS_REVISION` for an
  actually-clean review. `codex_strip_quoted_spans` now also strips
  single-quoted spans (`'...'`) — the fourth quoting style found
  unprotected after straight-quote, backtick, and blockquote. Single
  quotes needed a stricter boundary than the other three styles: a bare
  `'[^']*'` would also match the span between two unrelated apostrophes
  in contractions (e.g. "isn't approved, but it's fine" would have its
  "approved" deleted by a naive strip treating those two apostrophes as
  an opening/closing pair), so the opening quote must be preceded by
  whitespace-or-start-of-line and the closing quote by whitespace or
  punctuation, which a contraction's word-internal apostrophe never
  satisfies. `codex_strip_quoted_spans` now also strips fenced Markdown
  code blocks (```` ```...``` ````) via a separate `awk` pre-pass, since
  they're a multi-line construct the existing single-line `sed`
  substitutions can't handle (a fence marker line has no paired backtick
  on the same line to match, and the quoted content between the opening
  and closing fence spans arbitrarily many separate lines) — the fifth
  quoting style found unprotected, after straight-quote, backtick,
  blockquote, and single-quote. That pass's initial implementation
  toggled its "inside fence" state on ANY line with 3+ backticks, with no
  regard for the LENGTH of the opening delimiter; GitHub-flavored
  Markdown's actual fence semantics require a delimiter of at least the
  opening fence's length to close it, so a longer outer fence (e.g. four
  backticks) safely quoting content that itself contains a shorter
  (three-backtick) fence incorrectly closed on the inner delimiter,
  re-exposing everything after it — including a quoted clean phrase — to
  classification. The awk pass now tracks the opening delimiter's length
  (via the POSIX two-argument `match()`, not the gawk-only three-argument
  array-capture form, since this environment's `awk` is the POSIX "one
  true awk") and only closes on a delimiter of at least that length. That
  fix checked length but not GitHub-flavored Markdown's other closing-
  fence requirement: a closing delimiter must be followed by nothing but
  optional whitespace. A line like `` ```not-a-close `` is, per GFM, a
  new *opening* fence with an info string, not a close, but the
  length-only check treated it as closing regardless, incorrectly
  re-exposing a quoted clean phrase positioned after it (and hiding
  genuine rejection text positioned after THAT, since the length-only
  check then misread the real closing delimiter as opening yet another
  fence). This completes GFM's fenced-code-block spec — open, length,
  close-only-whitespace — as the deliberately final fence-specific
  refinement here, rather than another reactive edge-case patch: an
  unclosed fence at end-of-input is already handled safely by
  construction (everything after an opening delimiter that never finds a
  valid close stays stripped), so the state machine now correctly
  implements the finite GFM fence-closing rule end to end.
- **Codex GitHub fenced-code-block detection replaced with a conservative
  heuristic**: a fifth consecutive fence-parsing gap surfaced — GitHub-
  flavored Markdown's entirely separate TILDE-delimited fence syntax
  (`~~~...~~~`), which the backtick-only precise parser never recognized
  at all, so a quoted clean phrase inside a tilde fence stayed fully
  exposed to classification. Rather than continue precisely
  re-implementing GFM's fence grammar one construct at a time (detect,
  length, close-only-whitespace, and now tilde variants — each round
  surfaced the next undiscovered edge case), `codex_strip_quoted_spans`
  no longer attempts to parse fence boundaries at all: the entire awk
  state machine was removed. `codex_response_is_approved` instead treats
  the mere presence of a fence-opener marker (3+ consecutive backticks or
  tildes) anywhere in the response as disqualifying for a clean verdict,
  without attempting to determine where it opens or closes. This is a
  deliberate tradeoff — a small amount of false-`NEEDS_REVISION` risk (a
  genuinely clean response that happens to include an example code fence)
  in exchange for closing the entire class of quoted/fenced-phrase-
  misread-as-assertion bugs in one step, since four rounds of chasing
  precision produced four more false-`APPROVED` gaps instead of
  converging. Single/inline backtick pairs on one line (not a 3+-backtick
  run) are unaffected and still get precise, stable stripping, since
  inline code references are common in genuinely clean review comments
  and have not shown this same repeated-edge-case pattern. That fence-
  marker guard was added to `codex_response_is_approved` only, so a
  clean SHA-pinned review that quotes a REAL quota notice inside a fenced
  example (e.g. "No blocking issues found" followed by a fenced block
  containing "You have reached your Codex usage limits") still matched
  the usage-limit pattern on the unstripped fence content and returned
  `UNAVAILABLE` instead of the safe-fail `NEEDS_REVISION` a fenced
  response should produce. The guard now lives in a new shared
  `codex_response_has_fence_marker` helper used INSIDE every
  positive/actionable classifier (usage-limit, environment-error,
  approved) rather than scattered at call sites, so every current and
  future caller benefits automatically — the same lesson
  `codex_response_is_blocking` already taught for quote-stripping.
  `codex_response_is_blocking` briefly gained the same fence-marker guard
  "for consistency" and was found to be the wrong call for that one
  classifier: unlike a usage-limit/environment-error/approval false
  negative (always safe — it only defaults toward `NEEDS_REVISION`), a
  blocking false negative is unsafe, since Protocol 93 requires a
  detected blocking finding to always win outright over other evidence
  (e.g. a same-fetch usage-limit notice); bailing out on fence presence
  let a real blocker outside a fence go undetected just because the same
  review also contained an unrelated fenced example elsewhere, silently
  breaking that "blocking always wins" invariant. `codex_response_is_blocking`
  no longer bails out on fence markers — it keeps only its existing
  `codex_strip_quoted_spans` normalization, since a blocking false
  positive on quoted/fenced text is safe on its own.
- **Codex GitHub reviewer now consults GitHub's structured review `state`
  field**: `codex-github-reviewer.sh` relied entirely on free-text body
  parsing (`codex_response_is_blocking`/`codex_response_is_approved`) to
  classify a submitted review, even though the reviews-endpoint response
  carries GitHub's own authoritative `state`
  (`APPROVED`/`CHANGES_REQUESTED`/`COMMENTED`/`PENDING`/`DISMISSED`)
  directly. A review with state `CHANGES_REQUESTED` but a clean-sounding
  or ambiguous body (e.g. "Looks good overall, but see the note below.")
  fell through to the unrecognized-format safe-fail — or, worse, could
  match `CODEX_APPROVAL_PATTERN` outright and return `APPROVED` — instead
  of being recognized as blocking on GitHub's own signal. All four
  reviews-endpoint `jq` queries (main poll, async-arrival, async-final,
  async-reaction-final) now also extract `state`; `codex_select_review_
  evidence` tracks it as `SELECTED_REVIEW_STATE` alongside the tied
  review's body/timestamp; `codex_combine_terminal_evidence` threads it
  through as a new `review_state` parameter and exposes
  `COMBINED_REVIEW_STATE`, set only when an actual submitted review (not
  a SHA-pinned terminal comment, which has no review state) is the
  winning evidence. Every verdict-parsing call site now short-circuits to
  blocking when the winning review's state is `CHANGES_REQUESTED`, ahead
  of free-text classification; the two "blocking terminal/review evidence
  always wins outright" checks inside `codex_combine_terminal_evidence`
  (guarding against a same-fetch usage-limit notice or environment-setup
  error silently overriding a real blocker) now also treat a
  `CHANGES_REQUESTED` state as blocking, not just a free-text match. Two
  followup gaps in that same `state`-field integration were also fixed:
  (1) `codex_select_review_evidence`'s tie-break for reviews sharing the
  same second-resolution timestamp ranked purely on `codex_response_
  priority(body)`, which had no notion of `state` — two tied reviews, one
  clean and one `CHANGES_REQUESTED` whose body also happened to contain
  an approval phrase, both scored the same priority from body text alone,
  so whichever the API returned first silently kept the selection and the
  `CHANGES_REQUESTED` review's state was discarded before the caller's
  short-circuit ever saw it; `codex_response_priority` now also ranks a
  `CHANGES_REQUESTED` state at the blocking tier regardless of body text.
  (2) A review with state `DISMISSED` still matched the SHA/commit/
  timestamp filters (dismissal doesn't change `commit_id` or
  `submitted_at`), so its now-stale body text could still be selected as
  fresh terminal evidence on an idempotent rerun even though GitHub no
  longer treats a dismissed review as active; all four reviews-endpoint
  `jq` queries now exclude `state == DISMISSED` entirely at the source.
  (3) A third, separate tie-break — `codex_select_terminal_evidence`,
  used when a SHA-pinned terminal root comment and a current-head review
  share the same second-resolution timestamp — had the same class of gap
  as (1) but was missed by that fix, since it's a different function with
  its own `codex_response_priority` calls: a clean-looking root comment
  and a same-timestamp `CHANGES_REQUESTED` review whose body also read
  clean both scored priority 0 from body text, and since the comment is
  always the "current" side of this comparison, the review could never
  outrank it, discarding its `CHANGES_REQUESTED` state. `codex_select_
  terminal_evidence` now accepts optional current/candidate state
  parameters (empty for a root comment, which has no review state) and
  passes them into `codex_response_priority`, so a same-timestamp
  `CHANGES_REQUESTED` review wins this tie-break too, regardless of which
  side is "current".
- **Codex GitHub reviewer strips multi-line quoted spans**:
  `codex_strip_quoted_spans`' double-quote stripping ran inside a single
  `sed` invocation, which operates per-line by default (each line is its
  own pattern space) — a straight-double-quote pair spanning a newline
  (e.g. a bot quoting multi-line text as `The documented response "` /
  `No blocking issues found` / `" is inaccurate` across three lines) was
  never stripped at all, since the opening and closing quote sit in
  different sed pattern spaces. The quoted clean phrase reached
  classification unstripped and matched `CODEX_APPROVAL_PATTERN`,
  returning `APPROVED` instead of the documented unrecognized-format
  safe-fail. Newlines are now swapped for a control-character placeholder
  before the double-/single-quote stripping passes (restoring them
  immediately after, before the line-oriented backtick pass), so a quote
  pair is stripped regardless of how many original lines it spans.
  Blockquote-line deletion remains line-oriented, which is correct by
  design (a GFM blockquote marker only means anything at the start of a
  line); backtick-pair stripping was ALSO kept line-oriented at the time,
  reasoning that GFM inline code spans never cross a line — see the
  followup fix below, which found that reasoning incorrect.
- **Codex GitHub reviewer fixes two followup gaps in the multi-line quote
  fix above**: (1) the single-quote pattern's boundary alternatives
  (`(^|[[:space:]])` and `([[:space:].,;:!?]|$)`) didn't include the
  newline-flattening placeholder character, so a single-quoted span
  occupying an ENTIRE original line by itself (e.g. a bot's `The
  documented response is:` / `'No blocking issues found'` / `That claim
  is inaccurate` across three lines) has the placeholder — not real
  whitespace, not true start/end-of-string — immediately before/after the
  quote once flattened, so neither boundary matched and the quoted clean
  phrase survived, returning `APPROVED`. The placeholder is now included
  as an additional valid boundary character. (2) Backtick-pair stripping
  was deliberately kept line-oriented in the multi-line quote fix,
  reasoning that "GFM defines an inline code span as never crossing a
  line" — that reasoning was wrong: CommonMark/GFM inline code spans CAN
  legitimately span multiple lines (embedded line endings are normalized
  to spaces in the rendered output); only FENCED, triple-backtick code
  blocks have line-anchored open/close semantics, a different construct.
  A single-backtick code span split across lines was never stripped,
  letting the coded clean phrase reach classification unstripped and
  return `APPROVED`. Backtick-pair stripping now runs on the same
  newline-flattened body as the double-/single-quote passes, alongside
  them, instead of as a separate line-oriented pass afterward.
- **Codex GitHub reviewer recognizes "don't approve" and multi-backtick
  code spans**: `CODEX_NEGATION_WORDS` was missing "don't"/"do not"
  entirely — only the third-person singular form ("does not"/"doesn't")
  was covered — so a response like "This looks good at first glance, but
  I don't approve this change." had the earlier positive phrase win and
  returned `APPROVED` instead of falling through to the negated-approval
  check; "don't"/"do not" is now included alongside every other verb's
  contracted and space-separated forms. Separately,
  `codex_strip_quoted_spans`' backtick-pair regex (`` `[^`]*` ``)
  mishandled CommonMark's actual code-span delimiter-run matching: a code
  span can be delimited by a run of 2+ backticks, not just a single pair,
  and the naive regex treated an adjacent 2-backtick run as two separate
  EMPTY single-backtick pairs (each backtick immediately "closing"
  against its neighbor with zero content between), stripping only the
  empty delimiter markers and leaving the actual enclosed content fully
  exposed. Rather than write CommonMark-compliant delimiter-run matching
  in regex, `codex_response_has_fence_marker`'s backtick threshold is
  lowered from 3+ to 2+, so a 2+-backtick run disqualifies the same way a
  3+ run always has; single backtick pairs are unaffected and still get
  precise stripping. The tilde threshold stays at 3+, since GFM only uses
  tildes for fenced code blocks, never inline code spans.
- **Codex GitHub reviewer recognizes explicit merge-refusal verdicts**:
  the negated-approval mechanism (`CODEX_NEGATED_APPROVAL_PATTERN`) only
  fires when a negation word is followed by one of a fixed list of
  approval-vocabulary target words (`approve[ds]?`, `lgtm`, `looks good`,
  etc.) within the same sentence. A response like "This looks good at
  first glance, but this should not be merged until tests pass." negates
  "merged" — a word outside that target list entirely — so the
  negated-approval check never matched, and the earlier "looks good"
  phrase alone won, returning `APPROVED`. `CODEX_BLOCKING_PATTERN` (checked
  first in the verdict-parsing chain, before approval) now recognizes an
  explicit should/must-not-be-merged verdict outright, regardless of what
  an earlier hedge phrase in the same response says. That fix only
  covered the PASSIVE form; the IMPERATIVE form ("do not merge"/"don't
  merge") is a separate, common phrasing the same gap applies to for the
  identical reason — "merge" isn't in the negated-approval mechanism's
  target-word list either, and unlike the passive form's "not be merged",
  the imperative form's negation word isn't even adjacent to an
  approval-vocabulary word at all. `do not merge`/`don't merge` are now
  recognized alongside the passive form. That fix immediately surfaced a
  third sibling — `cannot be merged` — the same underlying gap: enumerating
  one merge-refusal phrasing at a time in `CODEX_BLOCKING_PATTERN` kept
  producing the next unenumerated synonym. Rather than add a fourth
  one-off alternative, a new `CODEX_MERGE_REFUSAL_PATTERN` is built from
  the existing `CODEX_NEGATION_WORDS` list against a `merge(d)` target —
  the same construction `CODEX_NEGATED_APPROVAL_PATTERN` already uses —
  so any negation word already known to this file, including future
  additions, automatically covers merge refusals too, without needing
  its own enumeration round-trip. `CODEX_BLOCKING_PATTERN`'s three
  manually-enumerated merge-refusal alternatives are replaced by this
  single generalized pattern. Two more gaps surfaced immediately from
  that generalization: `CODEX_NEGATION_WORDS` was still missing
  "shouldn't"/"should not" and "mustn't"/"must not", so those contracted
  refusals bypassed both the merge-refusal and negated-approval checks —
  now added, automatically fixing both checks at once (the point of
  generalizing on a shared word list). Separately, `codex_response_is_
  blocking`'s new merge-refusal pattern reuses `CODEX_NEGATION_WORDS`'
  bare "not" alternative the same way the negated-approval pattern does,
  so it inherited the same "not only X" affirmative-idiom
  misclassification that `codex_strip_not_only_idiom` was originally
  written to fix for approval only — a clean response like "This is not
  only safe to merge but looks good" was misread as a merge refusal.
  `codex_response_is_blocking` now applies that same idiom-stripping
  normalization before matching. A fourth consecutive missing-negation-word
  finding (`wouldn't`) prompted a proactive sweep of the remaining common
  English negation forms in one pass — `was/wasn't`, `were/weren't`,
  `would/wouldn't`, `has/hasn't`, `have/haven't`, `had/hadn't` (contracted
  and space-separated) are now all included in `CODEX_NEGATION_WORDS`,
  rather than continuing to fix them one synonym at a time. `did not`/
  `didn't` is deliberately excluded from this sweep despite being an
  equally common form: it already appears baked into
  `CODEX_NEGATED_APPROVAL_TARGET_WORDS` as part of the atomic phrase
  "didn't find any major issues" (itself a clean signal). Adding bare
  `didn't` as a general negation word was verified during development to
  introduce a genuine false positive — a doubly-reinforced clean response
  ("Codex didn't find any major issues and looks good.") would misclassify
  as `NEEDS_REVISION` because "didn't" matches as a bare negation and
  reaches the separate "looks good" target later in the same unpunctuated
  sentence — caught and reverted before being committed. A regression test
  guards against this specific gap being silently reintroduced later.
- **Workflow sync hardening backports**: delegated epic resolution now fails
  closed on unknown tracker statuses, security-advisory fix evidence is verified
  against the current PR head, CodeRabbit CLI review evidence fails closed when
  PR metadata cannot be resolved, and batch merge rechecks preserve explicit
  approvals for unready PRs.
- **`post-merge-cleanup.sh` fails fast on missing `--pr`**: the `--pr <merged-pr-number>`
  requirement for cleaning up an implementation branch's remote copy is now
  checked immediately after the branch's ownership kind is resolved (and after
  the existing `workflow_hub` product-repo-selection check, preserving that
  check's original priority), before any fetch/checkout/pull/delete work runs,
  instead of surfacing only after the rest of cleanup had already mutated
  local state. The structured `REMOTE_DELETE_RESULT`/`REMOTE_DELETE_REASON`/
  `ERROR_MESSAGE` output is emitted from a single shared helper used by both
  the new early guard and the pre-existing (now defensive, unreachable via
  the main flow) check inside `cleanup_remote_implementation_branch()`, so the
  message text can't drift between the two call sites. The early guard exits
  with status 64, this script's usage-error convention shared by every other
  argument-validation check, rather than the incidental status 1 that used to
  result from `set -e` propagating the deep check's generic `return 1`. A
  planted-violation proof (both directions, including before/after
  `git rev-parse HEAD` / `git branch --show-current` / `git for-each-ref` /
  `git ls-remote` evidence that nothing mutates before the guard fires) and a
  regression test proving a reverted guard placement turns the suite red are
  recorded in [PR #1500](https://github.com/lhpaul/ai-dev-framework-template/pull/1500#issuecomment-5335650280).
- **Reviewer-loop cycle caps now enforced (dual cap)** (#1502):
  `pr-review-loop.sh` previously had no code path that could ever trip
  Protocol 93's documented hard cycle cap ("a hard limit independent of
  finding counts") — PR #1492 in this repository reached 18 reviewer-loop
  cycles against a documented cap of 10 with no escalation. The script now
  enforces **two independent caps**, per operator decision recorded on PR
  #1507's review: a **per-run cap** (`CYCLE_COUNT`/`MAX_CYCLES`, default 10)
  that resets to 0 at each orchestration-run boundary — conforming verbatim
  to `91-orchestrate-work-protocol.md:1719` ("Initialize `cycle = 0` once
  per orchestration run ... escalate when the run reaches `max_cycles`") —
  and a **lifetime ceiling** (`TOTAL_CYCLE_COUNT`/`MAX_TOTAL_CYCLES`, default
  25) that never resets and counts across the PR's entire review-loop
  lifetime, as the structural backstop for a PR resumed across many
  separate orchestration runs (a per-run-only cap would give such a PR a
  fresh budget every run, which is exactly the "runs until someone
  notices" failure this issue exists to end). Both caps read the persisted
  `reviewer_loop_history.v1` ledger, counting only the DISTINCT (HEAD SHA,
  result) pairs among prior entries whose result is `needs_fixes` or
  `needs_rerun` — the entries that actually trigger a fixer dispatch,
  deduped so a restarted runner or a duplicate review invocation with no
  progress (same HEAD SHA, same result) cannot exhaust either budget
  without a real fix ever being applied, while still counting a
  `needs_rerun` entry immediately followed by a `needs_fixes` entry on the
  *same* resulting HEAD SHA as two distinct dispatches rather than
  incorrectly merging them (a completed auto-fix cycle and a different,
  newly-found issue on that state are not the same event).
  Each ledger entry now also carries an optional `run_id` field (an
  additive, non-breaking change — no schema version bump), resolved once
  per invocation from the new `PR_REVIEW_LOOP_RUN_ID` env var (or a freshly
  generated per-invocation id when unset) and threaded through to scope the
  per-run count; entries written before this field existed are counted
  toward the lifetime cap but can never satisfy a per-run query, so an
  older PR's history does not get artificially reset. Neither cap resets on
  a HEAD SHA change alone — the counters are cumulative within their
  respective scope, matching the exact failure pattern that motivated this
  fix, where nearly every cycle produces a new commit. A "clean" result is
  never overridden, and the inline-fix retry lane is bounded by the same
  counters as sub-agent-dispatched retries, with no separate logic needed.
  Exits `RESULT=escalate` / `REASON=max_cycles_exceeded` when the per-run
  cap is reached, or the distinct `REASON=max_total_cycles_exceeded` when
  only the lifetime ceiling is reached, so an operator can tell "one run ran
  away" apart from "many runs cumulatively ran away". Both limits are
  configurable via `PR_REVIEW_LOOP_MAX_CYCLES`/`review.max_cycles` and
  `PR_REVIEW_LOOP_MAX_TOTAL_CYCLES`/`review.max_total_cycles` in
  `.ai-dev-workflow.yaml`. The current counts and configured limits are
  emitted as `RUN_ID`/`CYCLE_COUNT`/`MAX_CYCLES`/`TOTAL_CYCLE_COUNT`/
  `MAX_TOTAL_CYCLES` in the script's key=value output on every invocation.
  The ledger fetch retries once on a transient GitHub API failure before
  giving up; if the ledger still cannot be read reliably, the script fails
  closed and exits `RESULT=escalate` / `REASON=cycle_count_unavailable`
  (rather than silently disabling both backstops for that PR indefinitely)
  whenever the loop would otherwise still report `needs_fixes` or
  `needs_rerun`, matching this script's existing fail-closed convention for
  other safety-critical audits (e.g. the unresolved-review-thread check).
  Two further gaps in that fail-closed guarantee, found in later review of
  the same PR, are also closed: (1) cycle counting now uses a dedicated
  selector that reads the newest summary comment's own history status
  (rather than a render-only selector that intentionally falls back to an
  older "available" snapshot), so a genuinely unreadable newest ledger
  state can no longer resolve to a stale, silently under-counted prior
  count; and (2) if this cycle's own ledger entry cannot be persisted at
  all (both the comment update and the create-fallback fail) for a
  dispatch-triggering result, the script now escalates with the distinct
  `REASON=ledger_persist_failed` instead of letting an uncounted fixer
  dispatch happen, and a failed/empty HEAD SHA lookup while building a
  ledger entry now falls back to a guaranteed-unique synthetic identifier
  instead of an empty one (an empty HEAD SHA was excluded from both cap
  counts by design, which a persistent lookup failure could otherwise
  exploit to grant unlimited uncounted dispatches). Three smaller gaps
  found in the same review round are also closed: the ledger-fetch retry
  count (`CYCLE_LEDGER_MAX_RETRIES`) and retry wait
  (`CYCLE_LEDGER_RETRY_WAIT`) are now bounded the same way as the two
  cycle-cap variables, since an unbounded value could exceed Bash's signed
  integer range and make the retry loop's own give-up comparison silently
  evaluate as false forever instead of failing closed; `REASON=ledger_
  persist_failed` now also fires when only the pre-write READ of the
  existing summary comment fails (even if the subsequent write itself
  succeeds): a read failure previously made the write fall back to posting
  an "unavailable" stub that silently drops this cycle's own entry (an
  unavailable-history existing body is never appended onto), so a dispatch
  could complete, get reported to the caller, and then vanish from both
  cap counters on the very next successful invocation; and the script's
  tail was restructured so `_post_review_summary` (and any `ledger_
  persist_failed` correction it triggers) now runs BEFORE `RESULT=`/
  `REASON=` and the `--compare`-mode metrics row are ever emitted, instead
  of after — the previous design printed a second, corrected `RESULT=`
  line following the original one and relied on an assumed "last line
  wins" parsing convention that the script's own `kv_value` helper does not
  actually follow (it returns the *first* matching key), so a caller using
  that same convention would have read the stale, pre-correction `RESULT=`
  and could still dispatch another fixer despite the script exiting
  escalated. Exactly one `RESULT=`/`REASON=` pair, and one compare-mode
  metrics row, are now emitted per invocation, valid under either parsing
  convention.
- **Backlog item Priority was silently never set**: `update_tracker_priority_best_effort`
  in `workflow-lib.sh` rewrote `Medium` — the board's actual Priority field
  option — into `Normal`, a value that does not exist on the board, so the
  mutation could never resolve; the inverted alias is removed, and
  `add-backlog-item.sh`'s implicit default (used whenever `--priority` is
  omitted) changes from the nonexistent `Normal` to `Medium`. Priority
  resolution already read the project's actual field options dynamically
  (no hardcoded value list to fix there). A requested priority that still
  cannot be resolved against the board's real options is now a hard error
  (non-zero exit, `Error:`-prefixed message) instead of a fail-open
  `Warning:` that let the item get created with no priority at all; this
  applies narrowly to the Priority field via a new opt-in `required` mode
  on `update_tracker_named_field_best_effort` — the Type and Size helpers,
  and cases where the tracker provider or project genuinely does not apply,
  remain best-effort as before. `add-backlog-item.sh` now validates an
  explicit `--priority` against the board's real Priority field options via
  the new no-mutation `workflow_tracker_priority_resolvable` check
  **before** calling `gh issue create`, so an unresolvable explicit value is
  rejected without ever creating the issue (exit 1) — closing a
  partial-success window where the post-creation required update could
  otherwise fail after the issue already existed, which a caller retrying
  on non-zero exit without inspecting stdout could turn into duplicate
  issues. The rarer failure modes the
  pre-check cannot see (issue unexpectedly missing from the board, a
  transient GraphQL write failure) still surface after issue creation but
  now exit with a distinct code (`5`) and an explicit "issue was already
  created, do not retry" message instead of a generic failure. The
  implicit **default** (used when `--priority` is omitted) is no longer a
  single hardcoded literal either: the new `workflow_tracker_default_priority_value`
  adapts to whatever the configured board actually supports — preferring
  `Medium` (this repo's board), falling back to `Normal` for downstream
  repos whose board is still set up per the framework's pre-#1501 docs
  (`github-projects.md` previously told every template consumer to create
  a `Normal` option), and
  leaving Priority unset (no error) only when a board's Priority field
  confirms neither candidate exists — the same way an omitted `--size` or
  `--type` is left unset. A Priority update failure no longer skips the
  independent Type/Size updates that follow it in `create_cmd` — every
  requested field is attempted before
  the exit-5 partial-success signal is raised. `--priority` help text
  updated to match, including the new documented exit codes. Protocol 00's
  Priority inference heuristics now tell agents to **omit** `--priority`
  for the routine/default case instead of hardcoding `--priority Medium`:
  an explicit value is validated
  against the board's real options and hard-fails if absent, so the
  authoritative example was itself bypassing the adaptive default it
  documented, breaking on any board still using `Normal`. `Urgent`,
  `High`, and `Low` are unaffected — those literals are common to both the
  current and legacy board vocabularies. `README.md` and Protocol 90's
  abstract Priority ordering rules and summary templates now list
  `Normal/Medium` as an equal-rank pair
  instead of only `Normal`, matching `workflow-batch-overlap.sh`'s existing
  `PRIORITY_RANK` table (which already ranked both names equally) — a real
  board can now literally carry a `Medium` Priority value after this fix,
  and the framework's own prioritization docs previously had no rule for it.
  Live reproduction on the real board (see issue #1501) showed `High`
  already worked correctly and the alias/default were the whole defect —
  no separate `High` resolution bug exists.
- **Multi-repository release tooling hardening**: the prepare-release
  protocol now documents a one-PR flow for product repositories whose
  resolved release base is `main` — the previous two-PR instructions could
  not be followed for that configuration, since the production and backport
  PRs would need identical head and base branches.
  `delivery-bundle-manifest.sh` now rejects `add-component`/`update-component`
  calls whose `--component-key` does not match the evidence file's
  `selected_product_repo_key`, instead of silently binding mismatched
  evidence into the wrong component slot.
  `component-milestone-reconciliation.sh`'s `inspect-parent`/`apply-parent`
  now validate that `--parent-issue` matches the delivery manifest's
  `parent_ref` before evaluating component readiness, instead of allowing an
  unrelated issue to be recorded as released.
  `component-release-target.sh` now verifies the resolved product repository
  checkout directory actually exists on disk before reporting
  `mutation_allowed=true`, instead of trusting an unreachable configured
  `local_path`.
  `workflow-config-resolver.py`'s branch-name validation now applies git's
  ref-format component rules (no leading dot, no trailing dot, no `.lock`
  suffix) in addition to the existing character allowlist, so names such as
  `release/v1.2.3.lock` or `release/v1.2.3.` are rejected instead of accepted
  as portable branch names.
  `component-milestone-reconciliation.sh apply-component`/`inspect-component`
  now accept `--hub-tracker-reconciliation-outcome` and `--child-release-state`
  as explicit flags (mirroring `delivery-bundle-manifest.sh`'s existing
  flags) and treat a schema-correct evidence file with no `evidence_state` as
  verified, instead of requiring three fields the evidence producer,
  `component-release-evidence.sh`, never emits — the documented
  producer-to-consumer handoff between those two scripts could not
  previously complete.
  `delivery-bundle-manifest.sh update-component` now rejects a
  `component_tag`/`component_version` change for an already-accepted
  component when the `release_pr` is unchanged, instead of silently
  overwriting the accepted release composition; a different `release_pr`
  still accepts a new tag/version as the documented re-tag/re-release flow.
  `workflow-next-action.sh --pr` in `workflow_hub` mode now reads the PR's
  branch name before classifying it, instead of after, so hub-only spec,
  plan, and hub-owned implementation PRs resolve directly instead of always
  requiring a product-repository selection.
  `prepare-release-post-merge-cleanup.sh` now validates a resolved product
  checkout and locates its cleanup lock directory with
  `git rev-parse --is-inside-work-tree`/`--git-dir` instead of a bare
  `.git`-is-a-directory test, so a linked git worktree checkout (whose
  `.git` is a file, not a directory) is recognized instead of rejected.
  `component-release-target.sh` now accepts an optional `--release-branch`
  flag and folds it into `release_correlation_key`, so two release attempts
  for the same product and unchanged contract (for example `v1.2.3` and a
  later `v1.2.4`) get distinct correlation keys instead of colliding on the
  same key and conflating separate releases in cleanup locking, conflict
  detection, and audit records; `prepare-release-post-merge-cleanup.sh` and
  the prepare-release protocol now pass it once the release branch is known,
  so re-resolution at cleanup time reproduces the same key.
  `component-release-evidence.sh` now rejects a `--release-branch` that does
  not match the target binding's `release_branch_pattern` (for example an
  unrelated branch such as `totally/wrong`) instead of accepting any
  syntactically valid branch name, and now accepts an optional
  `--component-tag` flag so rendered evidence can bind a component tag.
  `component-milestone-reconciliation.sh` now requires evidence to bind a
  matching `component_tag` before treating a component as released, instead
  of treating a missing evidence tag as a match for any caller-supplied
  `--component-tag` — closing a gap where `apply-component` could stamp an
  arbitrary, unverified release milestone.
  `workflow-next-action.sh --pr` in `workflow_hub` mode now gates the
  implementation-only repository-routing preflight on the branch actually
  being an implementation branch, instead of running it unconditionally, so
  spec and plan PRs (and other hub-owned, non-implementation branches)
  resolve directly instead of always requiring a product-repository
  selection.
  `multi-repo-release-assurance.sh` now validates that required evidence
  values match the established format for the artifact they claim to
  represent (a component/delivery-bundle schema string, a `sha256:`-prefixed
  contract revision, a product repository key, a GitHub `owner/repo` slug,
  or a `<product-repo>@<component-tag>` milestone title) instead of only
  checking that the value is non-empty, so fabricated evidence such as
  `release_contract:"garbage"` is rejected instead of producing
  `adoption_status:"validated"`.
  `delivery-bundle-manifest.sh update-component` now requires evidence to
  bind a matching `component_tag` before accepting it, the same fix applied
  to `component-milestone-reconciliation.sh` in the prior fix, closing the
  same gap in this second consumer; `create` now rejects a repeated
  `--component` instead of silently writing duplicate component entries
  that `update-component` could only ever update the first of.
  `prepare-release-post-merge-cleanup.sh` now emits its documented
  structured `--json` summary on every component-release cleanup run
  (previously only the already-complete shortcut path did), routing
  progress output to stderr so it cannot corrupt the JSON on stdout; and
  its per-release cleanup lock is now keyed under the hub checkout's git
  directory instead of the product checkout's, so two cleanup runs that
  resolve the product repository to different local checkouts of the same
  hub no longer both proceed for the same release.
- **`run-work-router.sh` no longer treats a `gh` probe failure as "target not
  found"** (#1503): `resolve_token()` probed `gh pr view`/`gh issue view` with
  `2>/dev/null || true` and treated any empty result as unresolved, so a rate
  limit, auth failure, network error, or GitHub outage was indistinguishable
  from the target genuinely not existing — both produced `MODE=ambiguous`,
  which every bounded command (`/run-item`, `/run-items`, `/run-epic`) treats
  as a hard stop with a misdirecting reason. Live reproduction: `/run-items
  1502 1501` stopped reporting both issues unresolvable immediately after a
  `/run-work` scan exhausted the hourly GraphQL quota, even though both were
  open and had resolved successfully minutes earlier. `resolve_token()` now
  captures each probe's stdout, stderr, and exit code separately (`gh_probe`)
  and classifies a non-zero exit's stderr (`classify_gh_probe_error`) into
  `rate_limited`, `auth_failed`, `network_error`, or `github_unavailable`
  before falling back to `not_found` for gh's own "could not resolve to a
  PullRequest/Issue" message, or for an empty stderr **only** when the exit
  code is gh's normal API-error code (`1`) — preserving current behavior for
  a genuine not-found while an empty stderr at any other exit code (a
  signal death, an OOM kill) still falls back to `github_unavailable`
  instead of being silently treated as not-found. gh's own "no default
  remote repository has been set" message (a local repo-configuration
  error, not evidence the target doesn't exist) is likewise never
  classified as `not_found`, and gets its own `local_config_error`
  classification distinct from `github_unavailable` since the operator fix
  is running `gh repo set-default` locally, not waiting out an outage.
  `gh_probe()` also now guards its own
  temp-file setup and stderr capture: a failing `mktemp` or `cat` reports a
  diagnostic `PROBE_ERR` at a dedicated internal exit code instead of
  silently producing an empty stderr that could otherwise be misread as a
  not-found. A probe failure now stops with the distinct
  `MODE=tracker_unavailable` (not `ambiguous`) and a `STOP_REASON` naming the
  cause; a rate-limited probe additionally reports the GraphQL quota reset
  time from `gh api rate_limit` when available.
  `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`
  (the canonical routing specification) is updated to document the new
  `tracker_unavailable` mode, its decision-table row, edge cases, and handoff
  mapping (routing layer version 1.0 → 1.1).
- **`item-completion-self-check.sh` no longer reports an indistinguishable
  false discrepancy when the caller's `--worktree-path` is the main clone
  (or the wrong sibling worktree)** (#1333): when `--worktree-path` resolves
  to a path other than the item's actual worktree, `repository.branch`
  reported a generic `discrepancy` (`HEAD` was the trunk branch checked out
  in the main clone rather than the item branch) that looked identical to
  genuine branch contamination — a downstream 5-sub-item epic run hit this
  in every runner completion report and had to be manually triaged. The
  script now also inspects `git worktree list --porcelain` (which enumerates
  every linked worktree regardless of which one it is invoked from) for the
  path where the expected branch is actually checked out. When that path
  differs from the supplied `--worktree-path`, a new, distinct
  `caller.worktree_path` diagnostic row is added alongside the existing
  `repository.branch` row, naming the actual worktree path and the correct
  `--worktree-path` to re-run with. This is strictly additive: the
  pre-existing `repository.branch`/`workspace.worktrees` rows and their
  `discrepancy` outcome are unchanged, so a genuine contamination case
  (the expected branch not checked out anywhere) still reports a plain,
  unexplained discrepancy with no caller-error row and no change to the
  non-zero exit code.
- **`graduation-closeout.sh` no longer refuses nested graduation PRs** (#1513):
  the graduation PR base-branch validation hard-coded `develop` as the only
  acceptable base, so a nested integration lineage (e.g. a wave branch
  `develop-ventas-e3b` graduating into a module branch
  `develop-sales-module` rather than directly into `develop`) failed
  closeout even though that base is correct for that layer — reproduced
  downstream on `mome-cl/mome-platform` PR #2138. A new `--base <branch>`
  flag (default `develop`, matching `batch-merge.sh`'s existing `--base`
  convention) lets the operator declare the expected graduation base; the
  script still fails closed with a clear error when the PR's actual base
  does not match, and rejects an arbitrary non-integration-branch `--base`
  value (anything other than `develop` or `develop-*`) up front regardless
  of what the graduation PR happens to target. The sub-item closing comment
  no longer hard-codes "to `develop`" either, and the summary output now
  reports `GRADUATION_BASE`. `graduation-closeout-from-merged-pr.sh` (the
  merge-time automation fallback invoked by
  `.github/workflows/update-tracker-on-merge.yml`) intentionally keeps its
  own `develop`-only check: that workflow only triggers on PRs targeting
  `develop`, so a nested-base graduation can never reach it regardless, and
  Step 5 of `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
  is the primary closeout path for nested graduations — invoked manually
  with `--base`. This issue is distinct from #1329 (documentation of
  `/run-epic --base`, the per-sub-item-PR integration base) and does not
  attempt to resolve it; #1329 remains open. 8 new regression tests cover
  the default `develop` base (confirmed unaffected), a matching non-default
  base, a mismatched non-default base, and an invalid `--base` value
  (confirmed to fail against the pre-fix script).
- **`test-item-completion-self-check.sh` no longer reads this repository's
  live reviewer configuration** (#1549): the suite's mock review threads and
  CI checks are authored as `cursor` / `Cursor Bugbot` — bugbot's bot login
  and check name — but `bugbot` was not present in
  `review.on_draft.github` / `review.on_ready.github`, so eight
  thread-detection assertions (unresolved-thread, REST-unreplied-thread,
  graph/REST same-thread dedup, and paginated-thread detection — two
  assertions each) and four CI-check-exclusion assertions silently went
  inert: the script correctly ignored threads/checks from an unconfigured
  platform, exited 0, and every test expecting exit 1 failed — 12 of 81
  assertions, entirely a function of which platforms this repository happens
  to commit. Each affected test now pins a `review:` config with `bugbot`
  configured for the duration of its call via `AI_DEV_WORKFLOW_CONFIG_FILE`
  — a shared fixture file, since the content is identical across tests —
  rather than re-pinning the coupling to a different platform: the seam
  `configured_review_platforms()` already honors, and the same pattern
  already used by `non_thread_platform_logins`/`no_thread_bot_logins`. The
  suite now passes 99/99 (the fix also added regression coverage) and was
  re-verified clean under three independent reviewer configurations: this
  checkout's local override (`pr-agent`/`coderabbit`), an unrelated platform
  set (`coderabbit`/`codex-github`), and an explicitly empty one. Two new
  regression tests guard the coupling from returning: the same
  unresolved-thread fixture still detects under an unrelated platform set
  that also configures `bugbot`, and no longer detects (unavailable_required)
  under an explicitly empty config — proving detection tracks `bugbot`'s
  presence rather than being hardcoded. The eight thread-detection
  assertions were confirmed to genuinely exercise detection by temporarily
  forcing the graph and REST thread-counting `jq` filters to always report
  zero and re-running the suite: all eight (plus the new alt-config
  regression test) failed loudly as expected, then the change was reverted.
- **`PR_HAS_CHANGELOG` and sibling label checks in `batch-merge.sh` were
  flaky under `pipefail`** (#1516): `discover`'s `PR_HAS_CHANGELOG`,
  `PR_READY_LABEL`, `PR_HAS_NEEDS_FIXES`, and `PR_HAS_HUMAN_CHECKPOINT`
  checks used a `producer | grep -q needle` shape. `grep -q` exits as soon
  as it finds its first match, closing the pipe while the producer (`gh pr
  diff` or `jq`) may still be writing — killing the producer with `SIGPIPE`
  and, under `set -o pipefail`, making the pipeline report failure even
  though `grep` itself found a match. The result was a false negative that
  only reproduced when the producer still had output queued at the moment
  `grep -q` exited, which is why it surfaced as an intermittent
  `PR_HAS_CHANGELOG=false` on a PR that unambiguously touched
  `CHANGELOG.md` (observed live on PR #1507). All four call sites now
  capture the producer's full output into a variable first — a `$(...)`
  command substitution always drains its command to completion, so nothing
  downstream can close its pipe early — then match with pure bash (`case`
  pattern matching), which uses no subprocess and no pipe on the matching
  side, so it cannot reintroduce the race regardless of payload size. A
  genuine `gh pr diff` failure is now also distinguished from "CHANGELOG.md
  legitimately not in the diff" (a `WARNING:` diagnostic is emitted) instead of
  both collapsing to `PR_HAS_CHANGELOG=false` indistinguishably. That
  diagnostic is written to a dedicated fd 3 (a duplicate of the script's real
  stderr, opened before `cmd_discover`'s local `meta="$(fetch_pr_meta "$pr_num"
  2>&1)"` capture exists) instead of fd 2, so it can no longer be swept into
  that capture and re-emitted on real stdout inside a discovery candidate
  block — a `KEY=VALUE`-only contract violation caught in review on PR #1536.
  `cmd_delete_branch`'s case-insensitive `push_err` classification
  (`printf | grep -qi`) was audited under the same shape and switched to
  `tr` + a pure-bash substring match; `tr` always drains its input to EOF
  rather than exiting early, so it was not actually racy, but the change
  keeps every producer-into-consumer match in this script off the
  `| grep -q` pattern. New regression coverage in
  `scripts/development-workflow/tests/test-batch-merge-changelog-race.sh`
  reproduces the underlying SIGPIPE race in isolation (an `awk`-generated
  producer with no pipe of its own — so its only possible failure is the
  actual race under test, not an unrelated `yes | head` pipefail quirk —
  forced to still have ~1 MB queued when `grep -q` exits: 10/10 reproducible
  in local and CI runs) and exercises the real `batch-merge.sh
  discover`/`delete-branch` commands against the same kind of adversarial,
  oversized `gh` mock payload across repeated runs, including a stdout/stderr
  separation check for the fd 3 fix, to confirm the fix holds.

### Changed

- **Conservative Codex verdict classifier** (#1491): `codex-github-reviewer.sh` now requires the response —
  whitespace-normalized, with no truncation step of any kind — to be an exact match, from its first
  character to its last, against one of a small set of clean-response templates captured verbatim from real
  Codex responses (each template including the complete vendor `<details>` footer text), and safe-fails to
  `NEEDS_REVISION` for anything else, including responses that are plausibly clean but use different
  wording anywhere in the body. This replaces both the open-ended negated-approval vocabulary enumeration
  this plan originally targeted and the allow-list/closed-grammar/truncate-then-match designs this plan
  shipped and then found further false-`APPROVED` gaps in across subsequent review rounds — no vocabulary,
  grammar, or partial-body match converged, so this revision applies exact literal comparison to the entire
  response, leaving no discarded byte range for a novel construction to hide in. GitHub's structured
  `CHANGES_REQUESTED` review-state short-circuit and the blocking classifier are unchanged. The template's one
  "flavor" slot (the word or phrase directly after "Didn't find any major issues.") is a single bounded
  placeholder (up to 40 characters, excluding `*`, backtick, and control characters), not a fixed literal —
  the vendor rotates this slot, confirmed after the shipped single-literal version safe-failed on this
  feature's own first real-traffic PR. A first fix enumerated every observed token as a literal alternation,
  but a 14-token discovery rate from under 50 samples showed that vocabulary would not converge by
  enumeration either, so the bounded placeholder replaced it before merge — the accepted residual is a
  disclosed, narrow false-`APPROVED` surface (self-contradictory vendor output only), not an enumeration that
  needs ongoing maintenance.

## [0.42.0] - 2026-08-13

### Added

- **Codex GitHub as the default ready-phase reviewer**: `review.on_ready.github`
  now defaults to `codex-github` instead of the CodeRabbit GitHub App. CodeRabbit
  remains supported as an explicit opt-in reviewer, but is no longer a default
  readiness gate because vendor rate limits/spending caps can block otherwise
  clean PRs.
- **Security-sensitive advisory findings require human decisions** (#1432):
  delegated merge now blocks on workflow-surface advisory findings involving
  auth bypasses, secret exposure, unsafe git operations, injection risk, or
  workflow guardrail bypasses until a verified human decision or cited fix is
  recorded.
- **Review discipline now requires planted-violation proofs and E2E fixture
  coverage** (#1443): `REVIEW.md` and testing guidance now require new guards,
  lint rules, checks, or CI jobs to prove they catch a planted violation, and
  feature PRs to extend real E2E fixtures when a repository has one.
- **Portable i18n no-literal-string guidance** (#1441): add the stack-specific
  i18n doctrine, a React Native/i18next example, dynamic-key scanner guidance,
  and a conditional review-gate check.

### Fixed

- **Run-epic marker comments are safer under API latency and concurrency**
  (#1474): targeted GitHub API calls now use bounded timeouts, structured
  marker-comment mutation failures, and a final duplicate check before posting.
- **PR disposition audit rendering rejects invalid policy evidence** (#1461):
  invalid invocation and checkpoint policy values, including boolean `false`,
  now fail instead of being rendered as absent.
- **Shell snippet lint respects explicit non-shell code fences** (#1468):
  TypeScript, Python, SQL, and other explicitly tagged non-shell fences no
  longer trigger WS001 because their contents happen to resemble shell.
- **Project-specific retro metrics are protected from template sync overwrites**
  (#1438): retro metrics files are now carved out of the sync manifest, with
  an approval-based bootstrap cleanup path for inherited template rows.
- **CodeRabbit reviewer-loop fallbacks are faster and more accurate**
  (#1433, #1437): silent-review fallback timing now scales with `--max-wait`,
  and successful CodeRabbit statuses with review-limit descriptions no longer
  count as completed review evidence.
- **Workflow runners may not park on backgrounded review or CI loops** (#1434):
  protocols, agents, and Codex command surfaces now require foreground
  `pr-review-loop.sh` and `pr-ci-loop.sh` execution.
- **Post-merge QA scope discovery is tracker-aware**: configured tracker
  post-merge items on `develop` are preferred, integration-branch QA semantics
  stay explicit, and provider-backed tracker IDs can seed the read-only scope
  helper.
- **Template sync review hardening was backported**: safeguards now cover batch
  merge metadata, reviewed-head pinning, delegated epic merge evidence,
  reviewer-loop blockers, reviewer bypass authorization, PR-bound cleanup, and
  workflow branch push-lock cleanup.
- **Run-epic audit rendering fails loudly on malformed evidence** (#1430):
  required-field and optional-section guards now report wrong-typed values
  reliably in both render and apply paths.
- **PR disposition audit comments include merge-safety evidence** (#1436):
  `why_safe_to_merge` is now rendered, invalid values fail loudly, and unknown
  top-level disposition keys emit warnings instead of being silently dropped.
- **Delegated gate input validation avoids false `human_required` verdicts**
  (#1435): missing or wrong-typed PR identity fields now error before
  evaluation, and explicit out-of-scope PRs produce a distinct
  `not_applicable` decision.

## [0.41.0] - 2026-08-02

### Changed

- **Guard workflow branch pushes** (#1423): Add an execution-time
  no-force-push guard for workflow PR branch updates and exact
  human-authorized exceptions.
- **Cursor model quota guidance** (#1407): Clarify Cursor Task/subagent model
  quota behavior and the decision path for one-off subagent model overrides.
- **Recheck batch mergeability after sibling merges** (#1424): Refresh
  remaining PR mergeability after each batch merge and hold stale or non-clean
  PRs.

### Fixed

- **Bugbot explicit skip handling** (#1381): Treat Cursor Bugbot explicit skip
  comments as warning-only skipped reviews instead of unavailable or blocking
  reviewer failures.

## [0.40.0] - 2026-07-30

### Added

- **Planless batch overlap fallback** (#1289): Derive explicit implementation
  targets for planless item pairs and serialize confirmed or suspected overlap.
- **Project advisory checks** (#1279): Let downstream projects append
  diff-scoped informational checks to reviewer summaries without changing
  reviewer outcomes.
- **Plan assumption cross-checks** (#1201): Re-verify cross-cutting plan
  assumptions so concurrent workflow work cannot silently invalidate
  implementation guidance.
- **Epic continuation gate** (#1372): Require delegated epic runs to re-resolve
  remaining child work before closeout.
- **CodeRabbit CLI review platform** (#1375): Add an optional Step 7 CodeRabbit
  CLI reviewer with explicit skipped and rate-limit handling.

### Changed

- **Ready-phase reviewer defaults** (#1375): Replace Bugbot with CodeRabbit as
  the default ready-phase external PR reviewer and enable budget-conscious
  non-draft `develop` auto-review.
- **Agent model defaults** (#1394): Refresh Cursor, Claude Code, and Codex model
  mappings for economy, balanced, and complex workflow agents.
- **Access-restricted reviewer merge gate** (#1288): Distinguish verified
  reviewer App-access restrictions from CI and review failures, prefer access
  remediation, and permit audited protection bypass only after fresh named
  human authorization.

### Fixed

- **Bugbot usage-limit reviewer classification** (#1394): Escalate Cursor
  Bugbot usage/spend-limit responses instead of treating neutral checks as
  clean.
- **Checkpoint resume isolation** (#1285): Require complete worktree context and
  stop resumed isolated runners before mutation when assignment cannot be
  proven.
- **Bounded-prelude data-model checkpoint signals** (#1287): Stop incidental
  data-adjacent issue-body terms from creating technical checkpoints while
  preserving explainable checkpoints for explicit migration and schema-change
  evidence.

## [0.39.0] - 2026-07-27

### Added

- **Lint executable workflow shell snippets** (#1180): Validate explicit Bash
  and Bash-zsh shell contracts in framework guidance and CI.
- **Validate reusable workflow branches** (#1179): Require approved-base
  ancestry before resuming an existing item branch.

### Fixed

- **Strengthen workflow branch and CI validation** (#1286): Reject unsafe
  branch names and use the latest successful check rerun as completion evidence.
- **Make portable workflow guidance and classification more reliable** (#1310,
  #1280): Embed parser safeguards and recognize native GitHub Issue Types.
- **Improve automated review reliability** (#1311, #1350, #1348): Handle
  authoritative Haystack skips, parse clean Bugbot reviews, and use Bugbot for
  ready-phase review.
- **Improve workflow closeout and QA safeguards** (#1304, #1305, #1306): Keep
  downstream tracker closeout in sync, allow its read-only checkout, and report
  clear missing scope-flag errors.

## [0.38.0] - 2026-07-21

### Added

- **Post-merge QA command** (#1283): `/post-merge-qa` (alias `/merged-qa-tester`), protocol `08`, and a read-only scope helper to QA work on `develop` or `develop-<slug>`, with optional design-asset fidelity and a single fix-PR path for safely actionable defects.
- **Automate graduation closeout on merge** (#1281): invoke the graduation closeout reconciler when a `develop-<slug>` graduation PR merges, while keeping Step 5 as the primary path.
- **Graphical design assets in the workflow** (#1282): capture, storage, discovery, and lightweight plan/smoke fidelity hooks for design references without a visual-regression platform.

### Changed

- **Sync-template decide-with-me vs accept-recommendations** (#1284): replace the primary sync apply confirmation with Decide with me and Accept recommendations; keep hard stops for special-handling / rename cleanup / placeholder-guard cases; demote always-sync-only to an escape hatch.

## [0.37.1] - 2026-07-20

### Fixed

- **Hub-owned sync-template cleanup** (#1273): Allow merged
  `feature/sync-template-*` branches to clean up in workflow-hub repositories
  without a product-repository selection.
- **Enable delegated medium-risk execution** (#1274): Allow Backlog starts and
  delegated merges through medium risk for spec, plan, and implementation
  stages.
- **Faind sync-template follow-ups** (#1271): port reusable downstream fixes for
  team-prefixed epic head-search, nested-guard guidance, terminal completion
  self-check requirements, sync-template completion verification, and
  implementation-branch cleanup outcomes.

## [0.37.0] - 2026-07-19

### Added

- **Prevent false dependency dispatch context** (#1182): Add
  spec-dispatch relationship context so orchestrators do not infer dependencies
  from keyword overlap alone.
- **Block Implementation Code in Plan PRs** (#1206): Add a
  documentation-stage alignment gate that blocks spec and plan PR readiness when
  implementation files are present.
- **Add residual verification gate for sweep sub-items** (#1175): Require
  broad-scope workflow items to record residual evidence before readiness.
- **Auto-close graduation sub-items** (#1178): Reconcile delivered
  integration-branch sub-items and parent epics during graduation closeout.
- **Prevent unsanctioned nested agent PRs** (#1200): Add workflow guards that
  stop duplicate nested-agent artifacts and reject missing or wrong PR base
  context.
- **Require ground-truth completion verification** (#1202): Add a completion
  self-check helper and require terminal item reports to include live branch,
  worktree, PR, CI, review, tracker, and runtime-claim evidence.

### Changed

- **Reviewer-loop retry history** (#1243): Preserve machine-readable
  reviewer-loop iteration history so retrospectives can report exact retry
  metrics.
- **Decision gate consistency matrix** (#1242): Added consistency-matrix
  evidence for complex workflow decision-gate documentation changes before PR
  readiness.
- **Require incremental checkpoint commits for item dispatch** (#1176): Adds
  recoverability guidance requiring coherent checkpoint commits after completed
  logical sub-parts of long-running item work.
- **Clarify delegated merge terminal behavior** (#1177): Document that
  merge-authorized runs continue from readiness through merge and cleanup while
  merge-denied runs stop at human handoff.
- **Fast Track blast-radius routing** (#1207): Add call-site volume and
  external-system impact checks before Fast Track dispatch.
- **Deprecate direct Cursor item-orchestrator path** (#1190): Clarify that
  Cursor users start single-item work with `/run-item` while internal handoff
  preserves configured subagent model routing.

### Fixed

- **Clarify pushed branch updates** (#1262): Require focused follow-up commits
  for corrections after a branch is published for review, preserving shared
  history without force-pushing.
- **Preserve local reviewer overrides** (#1033): Apply the initiating
  checkout's effective reviewer policy when review work resolves temporary
  target-branch configuration, without exposing local settings.
- **Clarify run-work batch proposal categories** (#1187): Label
  informational, actionable-resume, proposed-batch, and held items separately
  in run-work scan proposals.
- **Delete remote implementation branches after merge** (#1185): Ensure
  multi-stage item cleanup deletes merged implementation branches while treating
  spec and plan branches as expected-persistent.
- **Fix bounded-prelude acceptance criteria checkpoints** (#1184): Stop treating
  populated Acceptance Criteria sections as standalone product checkpoint
  signals while preserving checkpoints for unresolved, empty, or placeholder
  criteria.
- **Require worktree isolation for concurrent runners** (#1205): Require
  concurrent mutating batch dispatches to use distinct isolated worktrees and
  pre-mutation runner self-checks.
- **Restore worktree CWD on checkpoint resume** (#1174): Add a resume preflight
  so checkpointed worktree-isolated runs cannot continue from the main clone.
- **Bounded prelude base selection** (#1204): Require explicit-list
  integration labels to cover the whole item set and verify shared
  integration branches before selecting `develop-<slug>`.
- **Bounded prelude PR lookup**: avoid paginating every historical PR targeting
  `develop` for unlabeled `/run-items` Backlog starts by using targeted
  issue-head PR search before falling back to legacy lookup paths.
- **Zeki overlay workflow helper fixes** (#1191, #1192, #1193, #1194): honor
  configured GitHub Projects classification fields, default backlog priority to
  Normal, fail closed when GitHub trackers lack merge-status automation, and
  encode/dedupe run-epic PR base lookups.
- **Run-work scan helper caveats** (#1198): parse router guardrails without a
  PyYAML dependency and make batch-lane scan mode Bash 3.2 safe when no paths
  are supplied.
- **Haystack GitHub App review checks** (#1188): treat configured Haystack
  check runs as reviewer-loop state instead of generic CI, with check-run
  fallback/readback when CLI triage cannot return completed findings.

## [0.36.3] - 2026-07-08

### Fixed

- **Faind sync-template follow-ups** (#1171) (hotfix): port reusable downstream
  fixes for backlog Type propagation, release/hotfix reviewer-loop summary
  failures, explicit-list resolver invocation, PR head-search scope fallback,
  and delegated `/run-items` merge guidance.

## [0.36.2] - 2026-07-07

### Fixed

- **Downstream sync-template guardrails** (#1168) (hotfix): clarify that
  GitHub Projects merge automation is provider-specific and ensure mixed-stage
  guardrail scopes use the highest configured merge-risk ceiling. Release and
  hotfix reviewer-loop skips now also post the canonical summary marker required
  by the PR policy guard.

## [0.36.1] - 2026-07-07

### Fixed

- **Run-items CI continuation** (#1162): clarify that same-session
  `/run-items` supervision must continue past transient watch failures,
  skipped duplicate check noise, and incomplete CI evidence until a real
  terminal condition is reached.
- **Pre-edit branch guard** (#1133): require implementation agents to create or
  enter the item branch/worktree before the first file edit instead of starting
  changes in a shared checkout.
- **Retroactive backlog tracking gate** (#1134): require implementation PRs
  that grew from ad-hoc work to create or reference a tracker item before the PR
  opens.
- **Downstream template-sync follow-ups**: upstream reusable Leasity sync-review
  corrections for PR-Agent triggering, guarded command matching, guardrails
  parse diagnostics, tracker-provider checks, scope-base resolution, and GitHub
  App token signing.

## [0.36.0] - 2026-07-06

### Changed

- **Clarify run-item autonomy confirmation** (#1152): add a run-epic-style
  confirmation summary for single-item runs, preserve checkpoint and guardrail
  stops, and avoid redundant approval prompts after an invocation-scoped
  confirmation.
- **Consolidate PR policy workflows** (#1150): Replace redundant lightweight PR
  policy workflow fan-out with one API-only PR policy workflow while preserving
  reviewer-loop and regression-readiness guarantees.
- **AI Workflow — guarded run-items batch merge**: `/run-items` command surfaces
  now require Guardrails Enforcement Gate 5 `merge_allowed` before routing ready
  in-scope PRs into scoped Protocol 94 batch merge, never use auto-discovery for
  explicit item batches, and otherwise report the merge guardrail and handoff
  action at human review.

### Fixed

- **Run-epic scope resolver PR lookup**: Avoid scanning the full repository PR
  history by resolving linked PRs from cached, paginated results scoped to
  `develop` and each item's integration branch.
- **Workflow graduation guard**: Stop `/run-epic` delegated merges at
  `graduation_approval_required` for `develop-<slug>` -> `develop` graduation
  PRs unless explicit graduation approval is recorded.
- **Delegated merge cleanup guidance**: `/run-item` and `/run-epic` now state
  that delegated `merge_allowed` runs continue through branch cleanup,
  `post-merge-cleanup`, and live tracker verification before reporting terminal.
- **Linear-backed run-item guardrails**: bounded `/run-item` runs now accept
  Linear issue keys, apply repository guardrail defaults before policy
  recommendation, and avoid requiring PyYAML for guardrail parsing.

## [0.35.0] - 2026-07-02

### Added

- **Actions cost-audit guidance** (#1099): Add lightweight workflow run-volume
  and wall-time audit guidance for retrospectives and downstream template-sync
  reviews.

### Changed

- **Make PR-Agent explicit** (#1096): Reduce default PR-Agent Actions fan-out
  while preserving configured reviewer-loop review.
- **Event-driven reviewer guard** (#1097): Replace default long reviewer-loop
  guard polling with a fast PR check plus summary-comment readiness refresh.
- **Placeholder workflows opt-in** (#1098): Make template placeholder deploy and
  regression workflows opt-in so downstream repositories do not spend runner
  minutes before configuring real pipelines.
- **Release readiness wording**: command and overview surfaces now state that
  `release/*` PR reviewer loops are skipped while the production PR still gets
  regression and CI readiness before merge.

### Fixed

- **Workflow item routing no longer treats every GitHub issue as epic-like**:
  `/run-work` and `/run-item` now read GitHub sub-issue `totalCount` instead of
  the `subIssues` object key count, and the bounded prelude uses bash-3.2-safe
  empty-array expansion for stock macOS shells.
- **Reviewer-loop guard metadata failures** (#1097): Post retry-oriented failure
  statuses when PR metadata or head fields cannot be resolved, isolate
  summary-comment, non-summary comment, and PR-event guard concurrency lanes, and
  count summary-comment event payloads directly when the comments API lags or
  fails.
- **Downstream template-sync reviewer corrections**: Codex reviewer idempotency,
  workflow-hub GitHub App private-key paths, and optional Claude workflow tests
  now handle downstream sync edge cases without false failures.

## [0.34.0] - 2026-06-30

### Changed

- **Final orchestration command map** (#1050, #1051, #1076, #1077, #1078, #1080):
  `/run-work` is now a read-only portfolio scan, `/run-items` is the bounded
  multi-item execution command, `/run-epic` is epic-only, and `/run-item` is the
  canonical single-item command across AGENTS, README, protocol, skill, Cursor,
  and Claude command surfaces.
- **Bounded orchestration guardrails** (#1049, #1052, #1079): the template now
  ships delegated guardrails by default, always confirms mutating bounded runs
  before execution, records PR disposition and work-item ledger audit evidence,
  and documents optional parallelism limits with default serialized
  implementation lanes.

### Added

- **Human checkpoint lifecycle** (#1021, #1022, #1023, #1024): adds checkpoint
  policy recommendations, `human-checkpoint-required` readiness signaling,
  checkpoint satisfaction and waiver evidence, delegated merge blocking, batch
  merge discovery support, and an end-to-end smoke-test runbook.
- **Workflow hub product-repo preflight** (#1038, #1040): `hub-preflight-product-repos.sh`
  bootstraps workflow readiness labels, validates product-repo CI policy, and
  lets delegated merge gates honor explicit `ciPolicy: none` when checks are absent.
- **Reviewer-loop preflight guards** (#1028, #1035, #1037): Bugbot activation is
  detected from `cursor[bot]` comments before polling; Haystack triage HTTP 401/403
  errors fail fast with `REASON=unauthorized`/`forbidden` instead of
  `pending_timeout`; draft PRs skip Haystack with `REASON=pr-is-draft` and guidance
  to mark ready before rerunning.
- **Model cost resilience documentation** (#1044, #1045, #1046): pins explicit
  Cursor subagent models in `.cursor/agents/*.md` and documents tier defaults in
  `agent-model-config.md`; adds a provider quota/timeout/runner failover runbook
  and an experimental opt-in LLM router integration pattern for tier-aligned
  fallback chains.
- **Cursor and local config workflow surfaces**: adds Cursor as a Step 7a runner
  reviewer option, exposes Bugbot review overrides, ships Bugbot rules and local
  runner examples, and moves local workflow overrides to
  `.ai-dev-workflow.local.yaml`.

### Fixed

- **Workflow readiness handoff guards** (#1071, #1073, #1074): Protocol 91 now
  states the mandatory Step 7a -> Step 7 -> Step 7b -> Step 8 -> Step 8a order
  before `ready-for-human-review`; Protocol 90 treats missing reviewer-loop
  summaries or failing CI as non-terminal batch states; Protocol 03 calls out
  `post-merge-cleanup.sh` changes as requiring the workflow shell guard before
  PR creation.
- **Scan-only and ShellCheck consistency** (#1076): ShellCheck fetches enough
  base history for `workflow-shell-guard-lint.py`, and Protocol 90 plus command
  surfaces now consistently skip dispatch-only tracker updates during
  `/run-work` scan mode.
- **Spec review checklist: URL-parameterized state completeness check** (#973): adds an explicit check item to the Spec Review Checklist in `REVIEW.md` requiring that any URL-serialized state (query parameters, path parameters, hash fragments) introduced by a spec must define all parameter key names and allowed values; adds a corresponding `blocking` finding type to catch specs that leave the serialization contract underspecified, preventing this class of gap from reaching the external reviewer loop.
- **Linear orchestrator project scoping** (#972): Portfolio Orchestrator (`/run-work`) now
  reads `issue_tracker.custom_fields.project` from `.ai-dev-workflow.yaml` and filters
  Linear item-discovery queries to only items belonging to the configured project. If the
  field is absent, a visible warning is emitted and the orchestrator falls back to the
  previous unscoped team query. Prevents cross-codebase items from appearing as candidates
  in repositories with multi-project Linear workspaces. Updated Protocol 90 Step 1a and
  `integrations/linear.md` to document the new scoping behavior.
- **Linear priority drift detection** (#974): orchestrators applying Linear
  MCP status updates now compare the post-write priority against the
  dispatch-time value and emit `PRIORITY_DRIFT_WARNING` when drift is detected;
  adds optional post-write re-read with `TRACKER_WRITE_UNCONFIRMED` and
  one-retry logic when the status update is not reflected in the API read-back.
  Updated `linear.md` and Protocol 90 deferred-action collection loop.
- **Post-merge cleanup pull without upstream tracking** (#1058): `post-merge-cleanup.sh`
  now uses `git pull --ff-only origin "$DEVELOP_BRANCH"` instead of bare `git pull` so
  integration branches created without `--set-upstream` no longer cause "no tracking
  information" errors during cleanup.
- **Post-merge cleanup closes issues from PR body when branch slug lacks issue number** (#1059):
  `post-merge-cleanup.sh` now parses the merged PR body and title for GitHub
  closing keywords (`Closes #N`, `Fixes #N`, `Resolves #N`, etc.) when the
  branch name contains no embedded issue number (e.g. `feature/model-cost-resilience`).
  Each referenced issue is closed and its tracker status updated to Merged,
  preventing silent skip of issue closeout on epic-slug branches.
- **Post-merge cleanup missing local branch** (#1039): `post-merge-cleanup.sh`
  continues fetch, base checkout, and tracker closeout when the local branch is
  already deleted but a merged PR exists for that branch head (common after
  delegated merge with `--delete-branch`).
- **Workflow-hub base branch routing**: `/run-epic` scope resolution and
  spec/plan orchestration now distinguish hub artifact bases from product
  implementation bases, so a hub repository can use `main` while product
  implementation PRs target `develop`.

## [0.33.1] - 2026-06-19

### Fixed

- **Downstream template-sync corrections**: `run_bugbot_review` now fails closed on Bugbot fetch/parse errors before trigger and while collecting comments/reviews, and workflow shell tests use portable `cp` syntax.

## [0.33.0] - 2026-06-17

### Added

- **Cursor Bugbot reviewer platform** (#990): `bugbot` is now a recognized value for `review.on_draft.github`/`review.on_ready.github` in `.ai-dev-workflow.yaml`. `pr-review-loop.sh` triggers Cursor Bugbot, polls its check run, classifies the verdict (clean/blocking/timeout/unavailable), summarizes blocking `cursor[bot]` findings with severity and location context, and includes Bugbot threads in platform thread auditing.
- **Guardrails config and enforcement** (#979, #980): an optional `guardrails` section in `.ai-dev-workflow.yaml` defines autonomy modes, per-stage permissions, and risk limits. Orchestration enforces guardrails at backlog-start, PR-open, delegated review, delegated merge, and completion, naming the exact guardrail on every stop. New `guardrails.md` and `guardrails-enforcement.md` document the full policy.
- **`/run-work` as the adaptive workflow entrypoint** (#978): `/run-work` routes to Protocol 90 (portfolio/explicit-list), Protocol 91 (single-item), or Protocol 95 (epic) via `run-work-router.sh`. New Protocol 96 documents the five routing modes and read-only contract. `/run-item-work` and `/run-epic` are now compatibility/advanced aliases.
- **Cursor workflow surfaces** (#989, #991): adds `smoke-tester` and `graduate-development` Cursor slash commands, a Cursor Bugbot integration guide (`docs/workflow/development-workflow/integrations/bugbot.md`), and records the decision not to ship a Cursor-native skills mirror.
- **Regression tests for `run_bugbot_review`** (#1009): four new test paths in `test-pr-review-loop.sh` covering idempotency fast-path, trigger-failed escalation, fetch-failed escalation, and neutral clean. All 219 tests pass.

### Changed

- **Cursor workflow documentation** (#989): AGENTS.md, README.md, and `docs/testing/README.md` updated to reflect `/graduate-development <slug>` and the corrected smoke-tester command name.

### Fixed

- **Pre-branch HEAD guard** (#1004): Protocols 01–03 now verify the current HEAD SHA against `origin/develop` or `origin/main` before `git checkout -b`, preventing silent stacked-branch creation when parallel agents share a checkout.
- **Tracker verification after delegated merge** (#1005): Protocol 95 re-reads live GitHub Projects status after each delegated merge, re-applies if stale, and records the outcome in the audit comment.
- **Bugbot polling sleep signal-safety** (#1008): inline comment confirms `_interruptible_sleep` in `run_bugbot_review` is SIGTERM-safe.

## [0.32.0] - 2026-06-16

### Added

- **Linear orchestration support** (#966): `run-work`, `run-item-work`, and `run-epic` now emit structured `TRACKER_ACTION_REQUIRED=` deferred-action lines for the Linear provider (`set_status`, `read_status`, `create_item`) instead of silent empty returns or unstructured warnings. Protocols 90, 91, 95, and 00 document the bridge pattern end-to-end; `issue-tracker.md` and the Linear integration guide include a full `TRACKER_ACTION_REQUIRED=` reference table.

### Changed

- **Release PR reviewer loop skip** (#960): `pr-review-loop.sh` exits immediately with `RESULT=skipped` for release and hotfix PRs targeting `main`, eliminating the ~40-minute poll timeout that added no review value.

### Fixed

- **Per-finding advisory decisions in run-epic Step 8** (#962): Protocol 95 now requires one `advisories[]` entry per Haystack finding; bulk-acceptance with a single rationale is no longer permitted. `run-epic-audit-trail.sh` warns on under-populated or generic entries; `run-epic-delegated-gate.sh` reminds runners when the count is mismatched.
- **Backlog creation sets `Priority` and `Size` fields** (#965): GitHub Projects backlog items now receive `Priority: Medium` (not `Normal`) and a `Size` field on creation.
- **Release cleanup detects shipped issues outside changelog scope** (#964): `prepare-release-post-merge-cleanup.sh --from-changelog` cross-references closed `Merged` project items against the changelog-derived scope and auto-adds confirmed shipped items; parent epics without a referencing PR emit `TRACKER_INCOMPLETE=1`. Milestone stamping uses the GitHub Issues REST API with the resolved milestone number. Additional fixes: GraphQL timeline API replaces text-search PR matching (prevents substring false positives), project item enumeration uses paginated GraphQL (handles projects > 2000 items), and `parse_dt()` returns consistent naive UTC datetimes.

## [0.31.0] - 2026-06-15

### Added

- **Workflow hub operating model** (#874): repository modes, artifact ownership, target repository selection, and PR ownership for hub deployments.
- **Shared and local workflow configuration** (#875): separates versioned repository identity from local checkout and secret references, with repository-context helpers for hub routing.
- **Workflow hub template skeletons** (#876): inspectable hub and product-repo-injection skeletons with mode-specific sync-scope metadata.
- **Workflow hub product repository commands** (#877): status, sync, and pull-request visibility for product repository checkouts.
- **Workflow hub PR authentication** (#880): local-only GitHub App auth guidance for opening product repository pull requests.
- **Workflow hub setup and operations docs** (#882): setup, product-repo injection, cross-repo PR flow, and troubleshooting.
- **Workflow hub smoke fixtures** (#883): non-secret hub and product repository fixture coverage.
- **`/run-epic` autonomy and delegation** (#917, #918, #919, #920, #949): scope resolver, PR risk classification, delegated review/merge loop, audit trail, and autonomy policy recommendations.
- **Release stamping** (#829): records the production release version on shipped tracker issues using provider-native release markers.
- **Document PR quality gate** (#816): pre-submission quality gate for spec and implementation-plan PRs.

### Changed

- **Two-phase review config** (#868): explicit draft and ready lifecycle buckets, with legacy aliases for one transition release.
- **Codex review routing**: Codex is the default Step 7a internal reviewer; Claude Code Action after-clean reviewer replaced with `codex-github`.
- **Workflow hub orchestration** (#878): routes branch, PR, reviewer, CI, and cleanup operations to the selected product repository while keeping tracker/spec/plan state in the hub.
- **Workflow agent product-repo awareness** (#879): Claude, Cursor, Codex, and command wrappers declare repository context and route implementation to product repos in hub mode.
- **Sync-template hub scopes** (#881): role-aware template sync so hubs receive hub-owned files and product repos receive injection-safe files.
- **Workflow shell guard lint** (#910): catches command-substitution masking, unguarded `jq -r` assignments, unanchored branch-prefix grep, and bash 4 associative arrays.

### Fixed

- **`/run-epic` regression gates** (#955): delegated merge gates accept completed skipped or neutral regression checks while still blocking real failures and pending checks.
- **Haystack reviewer-loop** (#890, #909): policy acknowledgements stay advisory; stale clean summaries cannot hide active findings.
- **Prepare-release Linear cleanup** (#914): derives shipped issue scope from the finalized changelog and emits actionable Linear MCP/API handoff when tracker completion is missing.
- **Post-merge cleanup** (#911): switches to the merged PR base branch, including workflow hub integration branches, instead of always defaulting to `develop`.
- **Native GitHub sub-issues** (#884): documents native sub-issue linking for epics; preserves `integration-branch:<slug>` as the routing contract.
- **Codex GitHub reviewer loop**: aligns bot default with reviewer scripts, ignores outdated threads, and waits for a definitive approval signal.
- **Claude Code Action reviewer** (#866): explicit code-review prompt; fails closed when Claude did not execute.
- **Tool-fix merge ordering** (#825): foundational reviewer-tool fixes must merge before dependent tool-fixes are trusted.

## [0.30.2] - 2026-06-08

### Fixed

- **Downstream sync hardening** (#862, #863) (hotfix): preserves canonical Codex skill precedence during legacy alias installation and avoids dynamic regex construction in Claude Code Action run polling.

## [0.30.1] - 2026-06-08

### Fixed

- **Template sync hotfixes** (#858, #859) (hotfix): hardens GitHub Projects helper diagnostics and fallback remote parsing, and syncs lint helpers referenced by workflow protocols.

## [0.30.0] - 2026-06-07

### Added

- **Codex command aliases**: adds repo-scoped `.agents/skills/` aliases for the main workflow commands, including `/add-backlog-item`, `/run-work`, `/run-item-work`, `/run-reviewer-loop`, `/batch-merge`, `/post-merge-cleanup`, `/prepare-release`, `/graduate-development`, `/retrospective`, and `/sync-template`.
- **Reviewer failure labeling** (#804): adds a `reviewer-failed` PR label for automated reviewer timeouts, escalations, and unavailable reviewer platforms.
- **Pre-submission self-review** (#799): requires implementation agents to run a pre-PR diff self-review before opening draft PRs.
- **Workflow shell guard lint**: adds diff-based linting for unsafe `|| true` suppression in workflow shell scripts.

### Changed

- **GitHub Projects Type classification** (#828): makes the Project Type field the source of truth for workflow item classification and retires legacy repository classification labels.
- **`/run-work` backlog batching** (#838): makes unrestricted portfolio orchestration propose the largest safe prioritized Backlog start batch instead of stopping when no in-flight work remains.
- **Haystack routing and policy reporting** (#818): routes Haystack after draft cleanup, surfaces `pr-status` policy verdicts, and reports advisory human-review states without blocking clean reviewer-loop results.
- **Hotfix backport readiness** (#783): requires reviewer-loop, regression, CI, and human-review readiness labels before merging hotfix backport PRs.
- **Prepare-release and merge cleanup guidance** (#826): documents GitHub Projects close-workflow configuration and reasserts `Merged` after normal repo-owned merge cleanup.

### Fixed

- **Reviewer-loop readiness gates** (#827): blocks `ready-for-human-review` when the latest reviewer-loop summary is not clean or skipped.
- **Reviewer-loop summary freshness** (#823): verifies updated reviewer-loop summaries by `updated_at` instead of the original comment `created_at`.
- **GitHub Projects status reads** (#824): replaces full-board scans with targeted single-issue project item lookups to preserve GraphQL budget.
- **Regression labels after fix commits** (#805): preserves or restores `ready-for-regression` after the reviewer loop has already run.
- **Haystack pending and error handling** (#795, #800): poll-retries transient `pending` and `error` states and prevents incomplete analysis from producing false clean results.
- **Haystack diagnostics and false positives** (#796, #807, #782): surfaces Haystack reviewer stderr, documents the recurring changelog rule false positive, and treats Rules violation findings as advisory.
- **PR-Agent stuck-loop handling** (#815): distinguishes high-confidence security findings from low-confidence possible issues and escalates repeated low-confidence loops.
- **PR-Agent fallback instructions** (#817): documents a label-only metadata path when review body access is blocked by classifier or tool policy.
- **Claude Code Action reviewer selection** (#806, #808): removes the ineffective `inputs.pr_number` check and scopes concurrent workflow runs by PR-numbered run names.
- **Reviewer-loop guard race** (#790, #781): waits for the actual summary comment and includes the PR number in the status context to avoid cross-PR overwrites.
- **Copilot and reviewer-loop failure handling** (#776, #780): escalates missing head SHAs, surfaces SHA-refresh errors, and reports unreadable lock metadata.
- **Workflow script portability and guards** (#792): allows `workflow-lib.sh` to degrade when `BASH_SOURCE` is unset in non-Bash contexts.
- **Workflow shell guard release lint**: removes an unsafe suppressed `haystack` lookup from the Haystack reviewer test harness.
- **Downstream sync fixes**: backports multiple shell, Copilot, CodeRabbit, summary-comment, and protocol fixes found during downstream template sync review.
- **Reviewer-loop follow-up coverage** (#802, #803): adds regression coverage for lock-unlock failures, Codex thread audit escalation, summary temp-file cleanup, timestamp fallback, and paginated Actions run selection.

## [0.29.1] - 2026-05-28

### Fixed

- **`pr-review-loop.sh`: move `unlock` before the single-instance lock guard** — when a stale lock exists, the guard was re-acquiring it before `unlock` could run, causing `unlock` to see a live PID and refuse to remove the lock, breaking manual stale-lock recovery.
- **`claude-code-action-reviewer.sh`: emit `UNAVAILABLE`/exit 3 for preflight failures** — auth failure and unresolvable PR base branch were returning `TIMED_OUT`/exit 2, causing callers to apply the timeout policy instead of the unavailable policy.
- **`pr-review-loop.sh`: add `claude-code-action` and `copilot` to usage string** — both platforms were omitted from the help text, making CLI discoverability inconsistent with the actual dispatcher.
- **`claude-code-action.md`: fix dispatch-ref troubleshooting row** — the table incorrectly said the dispatch `ref` must match the PR base branch; the correct value is the repository default branch.
- **`pr-review-loop.sh`: re-fetch Copilot review SHA each poll iteration** — if a new commit is pushed while the Copilot review is in-flight, the initial SHA becomes stale and the SHA-filtered poll would never match the submitted review, causing a spurious timeout.
- **`pr-review-loop.sh`: guard `since_iso` against future-dated commit timestamps** — a committer date ahead of wall-clock time (clock skew or rebase) caused all existing bot comments to be excluded, producing false-clean results or duplicate review requests in the Devin, PR-Agent, and codex-github platforms.
- **`pr-review-loop.sh`: keep `comment_count` consistent with forced `blocking_count`** — when the Haystack companion script exits 1 with unparseable stdout, `blocking_count` was forced to 1 but `comment_count` stayed at 0, producing inconsistent output for downstream consumers.
- **`haystack-triage.md`: add language specifiers to fenced code blocks** — unlabeled fences triggered MD040 markdownlint warnings.

## [0.29.0] - 2026-05-27

### Added

- **`copilot` review platform** (#709) — add `copilot` to `review.platforms` in `.ai-dev-workflow.yaml` to use GitHub Copilot code review in the automated reviewer loop. `run_copilot_review()` requests Copilot via the GitHub Pulls API, polls for the verdict, and maps review states to the standard exit-code contract. Falls back gracefully when not enabled. Bot login overridable via `COPILOT_BOT_LOGIN`. Guide: `docs/workflow/development-workflow/integrations/copilot.md`.
- **`haystack` review platform** (#720) — `haystack-reviewer.sh` wraps the Haystack triage CLI as a native `pr-review-loop.sh` platform. Declare `haystack` in `review.platforms` or `review.phase_after_clean` in `.ai-dev-workflow.yaml`. Guide: `docs/workflow/development-workflow/integrations/haystack-triage.md`.
- **`claude-code-action` review platform** (#706, #708) — `.github/workflows/claude-code-review.yml` invokes `anthropics/claude-code-action` as an on-demand `workflow_dispatch` reviewer. `claude-code-action-reviewer.sh` dispatches the run, polls for completion, and returns the standard exit-code contract. Recommended for `phase_after_clean` (no hourly rate-limit cap, uses your own Anthropic API key). Guide: `docs/workflow/development-workflow/integrations/pr-review-platform.md`.
- **Haystack Editor git hooks** (#722) — `haystack hooks install` adds agent-aware pre-commit checks (`hooks/`) and `LLM_RULES.md` aligned with the `gh pr create` + reviewer-loop workflow (Option B; entire session tracking not adopted). Guide: `docs/workflow/development-workflow/integrations/haystack.md`.
- **Integration branch graduation ceremony** (#727) — Protocol 05b expanded with human-approval gate, divergence check, CHANGELOG handling, optional sub-item disposition, and epic issue closure. Protocol 90 Step 1b now surfaces graduation-eligible branches. Graduation PRs (`develop-<slug>` → `develop`) exempt from `ready-for-regression`.
- **Script-Accuracy Self-Check Checklist** (#735) — `03-implement-development-protocol.md` requires agents to verify all script-behavior claims (input/output format, exit codes, flags, API calls) against source before opening documentation PRs. Self-check log appended to PR description. Cross-referenced in all four implementation paths.

### Changed

- **CodeRabbit auto-review disabled** — `.coderabbit.yaml` `auto_review.enabled` set to `false`. Trigger on demand via `@coderabbitai review` in the reviewer loop.

### Fixed

- **`pr-review-loop.sh`: read `review.platforms` from PR target branch** (#756) — resolves `.ai-dev-workflow.yaml` from `origin/<base>` via `git show` instead of the working tree, so platform coverage is consistent regardless of local checkout state. Falls back to working-tree config if remote ref is unavailable.
- **`pr-review-loop.sh`: fix `run_copilot_review()` returning stale verdict after new commits** (#759) — filters the reviews poll to entries whose `commit_id` matches the current head SHA. Falls back to unfiltered if head SHA cannot be resolved.
- **`pr-review-loop.sh`: report per-platform results and skipped platforms in summary comment** (#755) — each platform now shows its outcome (`clean`, `skipped`, `unavailable`, `escalated`, `needs_fixes`) in the summary comment. A summary is posted even when no platforms are configured, so the reviewer-loop-guard always has a comment to find. Fixes a forward-reference bug in the no-platforms early-exit path.
- **`reviewer-loop-guard.yml`: add grace-period polling before failing** (#733) — polls up to `GUARD_MAX_POLLS` times (default 3, 30 s apart) before posting a failure status, giving `pr-review-loop.sh` up to 60 s to post its summary without a race. Both values configurable via env vars.
- **`pr-review-loop.sh`: stale-lock detection and recovery** (#734) — new `unlock <pr>` subcommand removes stale locks autonomously (refuses to remove a live-PID lock). Error message now includes the lock path and recovery one-liner.
- **`batch-merge.sh`: support non-`develop` base branches** (#736) — `merge` and `discover` subcommands now honor `--base <branch>` flag and `TARGET_BASE` env var for integration-branch contexts (`develop-<slug>`).
- **`graduate-development-protocol.md`: add Step 2.6 — verify review platform coverage before graduation** (#754) — agents must sync missing `review.platforms` entries from `develop` to `develop-<slug>` before opening the graduation PR.
- **Shell Script Quality Checklist: add `jq`, timeout, and structured-input items** (#752) — items 9–11 in `03-implement-development-protocol.md`: `jq -e` exit-code guards, `timeout` for external CLIs, non-empty validation for structured input.
- **`claude-code-action-reviewer.sh`: dispatch against default branch, not PR base branch** — fixes permanent 404 when the workflow file is not yet on the default branch.
- **`pr-review-loop.sh`: clarify REST-vs-GraphQL bot-login normalization** — comments now explicitly state REST returns logins with `[bot]` suffix, GraphQL without, preventing future Haystack triage misreads.

## [0.28.4] - 2026-05-27

### Fixed

- **`claude-code-review.yml`: add `id-token: write` and remove deprecated `pr_number`/`model` inputs** (hotfix): `claude-code-action` v1.0.133+ requires `id-token: write` for OIDC token auth; without it every `workflow_dispatch` run fails with "Could not fetch an OIDC token". Also removes the deprecated `pr_number` and `model` inputs and moves `anthropic_api_key` from `env:` to `with:` as now supported by the action. The `main` branch still carried the original v1 workflow; this hotfix brings it to parity with the fix already applied to `develop` via PR #767.

## [0.28.3] - 2026-05-26

### Fixed

- **`.github/workflows/claude-code-review.yml`: add missing workflow to `main`** (hotfix): the workflow was only present on `develop`, causing GitHub's Actions API to return 404 on every `workflow_dispatch` call from `claude-code-action-reviewer.sh`. GitHub serves `workflow_dispatch` events only for workflows registered on the default branch (`main`). Added the workflow file to `main` to restore the `claude-code-action` reviewer.

## [0.28.2] - 2026-05-23

### Fixed

- **`apply-regression-label.yml`: remove `synchronize` trigger** (hotfix): both `apply-regression-label.yml` and `remove-regression-label-on-push.yml` fired on `synchronize` events with separate concurrency groups, creating a race where the two workflows could interleave and leave the label in an inconsistent state. Removed `synchronize` from `apply-regression-label.yml`'s trigger list; the remove workflow already handles `synchronize` and is sufficient.
- **`reviewer-loop-guard.yml`: add fork/same-repo guard to status-posting step** (hotfix): the workflow uses `pull_request_target` with `statuses: write` but had no same-repo check, allowing status writes to be attempted for fork-originated PRs where the SHA may not be resolvable in the base repo. Added `if: github.event.pull_request.head.repo.full_name == github.repository` to the status-posting step.
- **`shellcheck.yml`: declare explicit minimal token permissions** (hotfix): the ShellCheck workflow had no `permissions:` block, causing `GITHUB_TOKEN` to inherit the repo-level default (potentially broader than needed for a read-only checkout). Added `permissions: contents: read` to the job.
- **`update-tracker-on-merge.yml`: rename `GITHUB_PROJECT_NUMBER/OWNER` to `PROJECT_NUMBER/OWNER`** (hotfix): `GITHUB_` is a reserved prefix for GitHub's own variables; using it as a repository variable name violates the naming convention and causes `actionlint` errors. Renamed to `PROJECT_NUMBER` and `PROJECT_OWNER` in the `env:` block, header comment, and warning message.
- **`update-tracker-on-merge.yml`: add concurrency control** (hotfix): rapid merges to `develop` could trigger concurrent runs updating the same project item, risking GraphQL conflicts. Added `concurrency: group: tracker-update-${{ github.event.pull_request.number }}, cancel-in-progress: false`.
- **`retro-metrics.md`: wrap `worktree-agent-*` in backticks** (hotfix): bare `worktree-agent-*` text in the table was parsed as emphasis by markdownlint, triggering MD037 ("spaces inside emphasis markers"). Wrapped the token in backticks.
- **`pr-review-loop.sh`: emit last-known counts in REST re-check failure path** (hotfix): when `check_unreplied_rest_comments` fails after auto-reply, `coderabbit_thread_gate_clean` was emitting hardcoded `COMMENT_COUNT 0` / `BLOCKING_COUNT 0`, misrepresenting an unknown state as "no blockers". Changed to emit `${rest_unreplied_raw:-0}` (the pre-auto-reply count) as the best available approximation.

## [0.28.1] - 2026-05-22

### Fixed

- **`/sync-template` skill and Cursor command: hard-stop on YAML validation failure** (hotfix): the `yaml_parse_failed` check in both `.claude/skills/sync-template.md` and `.cursor/commands/sync-template.md` only echoed an error but did not exit, allowing the sync to proceed past a broken workflow YAML file. Added `exit 1` to match the reference implementation in `.claude/commands/sync-template.md`.
- **`pr-review-platform.md`: fix `phase_after_clean` config example** (hotfix): the YAML example listed `coderabbit` only under `review.phase_after_clean` but not under `review.platforms`, contradicting the requirement that phase platforms must also appear in the platforms list. Added `- coderabbit` to the `platforms` array in the example.

## [0.28.0] - 2026-05-22

### Added

- **Phased PR-Agent clean gate before CodeRabbit** (#691): `review.phase_after_clean` support in `.ai-dev-workflow.yaml` and `pr-review-loop.sh` runs CodeRabbit only after PR-Agent is already clean, with `PHASE_AFTER_CLEAN_*` telemetry to measure CodeRabbit's net-new blocker rate. Protocols 91 and 93 updated to document the draft-PR gate.
- **Database best practices: RLS migration safety checklist** (#680): new `docs/best-practices/4-database.md` with an RLS section. Enabling RLS on an existing table requires revoking broad grants first to prevent legacy permissions from silently bypassing policies.
- **Supabase: TypeScript type narrowing for CHECK-constrained columns** (#681): new `docs/best-practices/stack/supabase.md` covering how to narrow Supabase-generated `string` types to union literals for `text CHECK (...) IN (...)` columns (Option A: override file; Option B: Zod source of truth). `STACK-SPECIFIC.md` updated with a Quick Reference entry.

### Changed

- **`/batch-merge`: remove interactive approval prompt** (#689): batch-merge now proceeds immediately after printing the merge plan; no user confirmation required. Protocol 94, the Claude Code command, Cursor command, and Codex skill all updated.
- **PR-Agent noise reduction** (#691): `.pr_agent.toml` instructions tightened to suppress speculative env-var, redundant shell-guard, and low-confidence style findings; PR-Agent Action pinned to `v0.35.0` (was `v0.34.3`); CodeRabbit removed from Step 7a default internal reviewer list.
- **Mandatory fork-PR guard for write-step GitHub Actions workflows** (#670): `03-implement-development-protocol.md` now requires every write step in a `pull_request`-triggered workflow (label, comment, release, status) to include an `if: github.event.pull_request.head.repo.full_name == github.repository` guard.

### Fixed

- **`.coderabbit.yaml`: suppress shell-script docstring-coverage false positive** (#700): `path_instructions` entry for `**/*.sh` disables CodeRabbit's docstring-coverage warning on Bash/shell files, which have no docstring standard.
- **`pr-review-loop.sh`: `timeout_incomplete_count` misses rate-limit edits to walkthrough** (#696): filter now uses `(.created_at > $since or .updated_at > $since)` so edited "Reviews paused" banners are detected and the guard escalates correctly.
- **`pr-review-loop.sh`: escalate on CodeRabbit rate-limit/pause instead of false-clean** (#688): emits `RESULT=escalate/REASON=rate_limit_max_retries` (exit 2) when CodeRabbit is rate-limited or paused, replacing the previous `RESULT=skipped/REASON=no_review` (exit 0). Retrigger command corrected from `@coderabbitai review` to `@coderabbitai resume`.
- **`pr-review-loop.sh`: preserve `phase_after_clean_platforms` in `--pre-after-clean-only` mode** (#693): `filter_phase_after_clean_platforms` is now skipped when `--pre-after-clean-only` is active, preventing it from clearing the list that `filter_pre_after_clean_platforms` had already set.
- **`pr-review-loop.sh`: extend poll window for large-diff PRs** (#669): automatically raises `max_wait` to `LARGE_DIFF_MAX_WAIT` (2400 s) when changed-files count exceeds `LARGE_DIFF_THRESHOLD` (50), preventing premature clean exits on release and sync-template PRs.
- **`prepare-release-post-merge-cleanup.sh`: treat pre-existing `Released` status as success** (#671): `UPDATED=0` from GitHub Projects automation is no longer flagged as a failure when the issue is already in `Released` state.
- **`pr-review-loop.sh`: post-clean recheck for late bot review threads** (#672): waits `POST_CLEAN_WAIT` seconds (default 30) after a clean exit to catch asynchronous bot threads. Emits `RESULT=needs_fixes/REASON=late_review_threads` if late unresolved threads are found. Strips `[bot]` suffix from logins before GraphQL comparison. Set `SKIP_POST_CLEAN_RECHECK=1` to suppress on corrective reruns.
- **`pr-review-loop.sh`: pagination guard in `check_unresolved_threads`** (#667): adds `hasNextPage=true + empty endCursor` break guard to prevent infinite pagination on malformed GitHub GraphQL responses.
- **`pr-review-loop.sh`: treat empty `endCursor` as incomplete audit in `check_unresolved_threads`**: changes the malformed-page-info handler from `break` to `return 2` so a partial thread count never produces a false `clean` gate outcome.
- **`pr-review-loop.sh`: add `FALLBACK_THREAD_SETTLE_WAIT` settle period before `coderabbit_status_success_fallback` thread audit**: CodeRabbit can set a `SUCCESS` commit status while still posting inline review threads asynchronously. Without a wait, `coderabbit_thread_gate_clean` runs before those threads arrive and returns a false-clean count. Both fallback paths (early-retry and timeout) now wait `FALLBACK_THREAD_SETTLE_WAIT` seconds (default 60) before the thread audit, giving CodeRabbit time to finish. Set to `0` to restore previous behaviour.
- **`pr-review-loop.sh`: mode-aware skip explanation in `--pre-after-clean-only` summary**: the "After-clean reviewer phase" line in the PR summary comment now distinguishes between "invoked in pre-after-clean-only mode" and "earlier platform did not exit clean".
- **`pr-agent.yml`: add fork-PR guard to prevent write operations on fork PRs**: the job-level `if` now requires `github.event.pull_request.head.repo.full_name == github.repository` for `pull_request` events, consistent with the mandatory fork-PR guard policy.
- **`docs/best-practices/4-database.md`: hyphenate "Row-Level Security" heading**: corrects "Row Level Security" to "Row-Level Security" for consistency.
- **`docs/best-practices/stack/supabase.md`: use markdown link for cross-reference**: the `docs/project/4-database-model.md` path is now a clickable link.
- **`docs/testing/workflow/batch-merge.smoke-test.md`: remove stale confirmation-step reference**: updates the expected-result line to reflect the no-confirmation flow.
- **Protocol 91: remove duplicated phase-after-clean runbook**: the detailed draft-phase steps are replaced with a short summary and a link to the canonical runbook in Protocol 93, reducing drift risk.
- **Retrospective protocol: remove `workflow` label from upstream issue filing** (#690): `gh issue create` in Step 3e no longer passes `--label "workflow"`, fixing permission errors for users without collaborator access.

## [0.27.4] - 2026-05-20

### Fixed

- **`pr-review-loop.sh`: slurp paginated pages in `activity_count`, `paused_count`, and `rate_limit_comment_count`** (hotfix): three additional paginated comment-count queries in `run_coderabbit_review` used `jq` without `-s`, producing multi-line counts on multi-page PRs and breaking integer comparisons. Applied the same `jq -s` / `.[].[]` fix as `silent_no_paused_count` (v0.27.3).

## [0.27.3] - 2026-05-19

### Fixed

- **`pr-review-loop.sh`: slurp paginated pages in `silent_no_paused_count`** (hotfix): `gh api --paginate` emits one JSON array per page; without `-s`/`--slurp` the `jq` filter iterated over pages rather than comments, producing a multi-line count that caused integer-expression errors in the silent non-trigger retrigger path. Added `-s` and changed `.[]` to `.[].[]`.
- **`pr-review-loop.sh`: use jq-encoded JSON body in `auto_reply_unreplied_rest_comments`** (hotfix): replaced `--raw-field body=` with a `jq -n --arg body` pipe and `--input -` so special characters in the reply body are correctly JSON-escaped before being sent to the GitHub API.
- **`pr-review-loop.sh`: clarify auto-reply body and comment** (hotfix): the reply message now reads "Acknowledged — outside-diff comment noted…" (was "Resolved — addressed in this PR.") to make clear it is an automated gate acknowledgement, not a claim that the comment content was addressed. Added an explanatory code comment.

## [0.27.2] - 2026-05-19

### Fixed

- **`pr-review-loop.sh`: scope `HARNESS_MODE` bypass to sourced loads only** (hotfix): the single-instance lock guard was bypassed whenever `HARNESS_MODE=1` was set, even for direct executions against real PRs. A new `_HARNESS_MODE_EFFECTIVE` flag is only set when the script is sourced (`BASH_SOURCE[0] != $0`), so normal runs always retain the lock guard and signal traps.
- **`pr-review-loop.sh`: re-validate REST gate after auto-reply** (hotfix): after posting auto-replies to unreplied outside-diff comments, `coderabbit_thread_gate_clean` now re-calls `check_unreplied_rest_comments` to confirm the count is zero before returning `clean`. Prevents a false-clean result when one or more auto-replies silently fail to post.
- **`pr-review-loop.sh`: fix misleading docstring on `auto_reply_unreplied_rest_comments`** (hotfix): the function comment incorrectly described the target as "comments whose GraphQL thread is already resolved"; corrected to "outside-diff comments with no corresponding GraphQL thread".
- **`.claude/skills/sync-template.md`: restore `yaml_parse_failed` tracking in YAML validation loop** (hotfix): the CI workflow YAML validation loop was missing the `yaml_parse_failed=0` initializer and `|| { ...; yaml_parse_failed=1; }` compound commands, so parse errors were printed but never blocked the commit. Restored to match the `.claude/commands/sync-template.md` reference implementation.

## [0.27.1] - 2026-05-19

### Fixed

- **`markdown-lint.yml`: disable `relative-links` rule in CI** (hotfix): implementation plans intentionally reference smoke test runbooks that are created later in the workflow — those forward references caused CI failures for any downstream project with plans. `markdownlint-rule-relative-links` is removed from `.markdownlint-cli2.jsonc` (the CI/runner config); `.markdownlint.jsonc` retains the rule for editor integrations.

## [0.27.0] - 2026-05-19

### Added

- **Integration branches for long-running multi-item developments** (#628): adds the `develop-<slug>` integration-branch workflow — epic/label creation in the add-backlog-item protocol, orchestrator base-branch override in protocols 90 and 91, and the new `05b-graduate-development-protocol.md` graduation command.
- **Stale local branch detection in pre-batch environment check** (#653): Protocol 90 Step 3.3 gains Check 3, which scans for workflow-prefix branches (`feature/`, `fix/`, etc.) whose PR has been merged and `worktree-agent-*` branches with no remote counterpart, listing them with suggested `git branch -D` cleanup commands before dispatch.
- **Project board auto-registration from spec/plan/developer agents** (#656): adds `ensure_on_project_board` to `workflow-lib.sh` and integrates it across all agent checklists, Codex skills, and development protocols so issues are guaranteed to be on the GitHub Projects board before their tracker status is updated.
- **CI enforcement: auto-apply `ready-for-regression` and assert reviewer-loop summary** (#613): two new GitHub Actions workflows — `apply-regression-label.yml` (auto-labels implementation PRs by branch prefix) and `reviewer-loop-guard.yml` (blocks merge-eligibility when the reviewer-loop summary comment is absent).
- **Auto-remove `ready-for-regression` label on push** (#612): `remove-regression-label-on-push.yml` removes the label when new commits are pushed, preventing stale regression-readiness signals.
- **Canary test requirement for filter-schema additions** (#606): developer and code-reviewer protocols now require a two-invocation canary test for every new filter parameter; absence is a blocking review finding.
- **Mandatory advisory finding dispositions in reviewer loop summary**: Protocol 93 requires runners to evaluate each non-breaking advisory finding and record a disposition (Addressed / Accepted / Deferred / Rejected) in the summary comment on clean exits.
- **Script quality gates and test harness for `pr-review-loop.sh`** (#585): adds `scripts/development-workflow/tests/test-pr-review-loop.sh` and a path-triggered CI workflow; prepare-release and retrospective protocols gain script-coverage and downstream bug-review checklist items.
- **Prettier for markdown formatting** (#584): adds `prettier` v3.8.3 and formats all `.md` files so downstream `/sync-template` runs see no spurious diffs.

### Fixed

- **`pr-review-loop.sh`: detect and auto-resume CodeRabbit auto-pause at loop start** (#651): inspects the most recent CodeRabbit comment before the poll loop; if "Reviews paused" is found, posts `@coderabbitai resume` and resets `since_iso` so the resumed review is captured.
- **`pr-review-loop.sh`: auto-reply to resolved CodeRabbit REST outside-diff comments** (#616): `coderabbit_thread_gate_clean` now auto-posts an acknowledgement reply to unreplied outside-diff comments after all GraphQL threads resolve, instead of returning `needs_fixes`.
- **`pr-review-loop.sh`: auto-trigger `@coderabbitai review` on silent non-trigger** (#587): posts a retrigger comment once when no CodeRabbit activity is seen within `CODERABBIT_NO_TRIGGER_TIMEOUT` seconds (default 600 s).
- **`pr-review-loop.sh`: REST comment check excludes already-resolved GraphQL threads** (#586): `check_unreplied_rest_comments` now receives resolved-thread IDs and skips them, preventing false `needs_fixes` loops on threads resolved via the GitHub UI.
- **`pr-review-loop.sh`: SIGTERM/SIGINT traps clean up lock directory on signal delivery** (#615): adds `TERM` and `INT` traps that remove the lockdir and re-raise the signal, preventing orphaned lockfiles after CI timeouts.
- **`pr-review-loop.sh`: various metrics and verdict-classification fixes**: `normalize_platform_verdict` maps `skipped` → `unavailable` in compare mode; bot accounts (any login ending in `[bot]`) are excluded from human-reply detection; "Metrics row appended" summary line is conditional on actual success; compare-mode platform-change detection compares column names, not just count.
- **Protocol 90: filter project board queries to prevent GraphQL rate-limit exhaustion** (#655): Step 1a documents an open-issue-first query pattern and a rate-limit check (`gh api rate_limit`) with warn/pause thresholds; `github-projects.md` is updated with the same guidance.
- **Protocol 90/91: explicit item list scope guard** (#605): hard-refuses all artifact mutations on items outside an explicit dispatch list; out-of-scope items trigger a WARNING log and appear in the Step 6 summary.
- **Protocol 90: orchestrator done-report must query artifact state, not trust agent self-reports** (#604): Step 5.1 and Step 6 now require every verification field (labels, CHANGELOG presence, reviewer loop, CI) to be sourced from independently queried `gh` CLI output.
- **Protocol 90/91: fixer redispatches in parallel batches require worktree isolation** (#589): Step 5 / Step 5.1 and Protocol 91 Step 7 explicitly require `BATCH_CONTEXT=true` and the resolved `<worktree-path>` on every redispatch within a parallel batch.
- **Protocol 90/91: `ready-for-regression` requirement explicitly covers `refactor/*` PRs** (#590): Step 7b and Step 5.1 direct-apply rule enumerate all four implementation branch types and add a `refactor/* is not exempt` guardrail note.
- **Protocol 91/93: convert draft PR to non-draft before internal review gate** (#657): Protocol 91 Step 7a gains a draft-state pre-check that runs `gh pr ready` automatically when CodeRabbit (or another `auto_review.drafts: false` reviewer) is listed; Protocol 93 gains a matching pre-flight check for standalone reviewer-loop invocations.
- **Protocol 91: strengthen GraphQL `reviewThreads` gate** (#634): Step 7 `clean` result table now explicitly states that `clean` from `pr-review-loop.sh` does NOT authorize applying `ready-for-human-review`; Step 8a gains a Warning block reiterating that the full GraphQL thread audit is always required.
- **Protocol 93: CodeRabbit silence pattern documentation** (#643, #644): new "CodeRabbit silence patterns" and "summary comment update-in-place" sections document how the script detects and handles auto-pause and silent non-trigger, and why comment timestamp is an unreliable completion signal.
- **Protocol 93: pre-post verification guard for reviewer comment composition** (#603): mandatory guard requires re-fetching the platform transcript and cross-checking every pass/approval claim before posting any `gh pr comment` characterizing a platform result.
- **Protocol 93: mandatory post-push SHA verification before resolving threads** (#602): after every `git push`, runners must compare local `HEAD` against `gh pr view --json headRefOid`; mismatches trigger one retry before reporting BLOCKED.
- **Protocol 03: mandatory test harness coverage checklist** (#614): new `## Test Harness Coverage Checklist` section requires edge-case verification (empty input, boundary values, concurrent execution, negative assertions) before self-approving any implementation that ships or modifies a test harness.
- **Shell script quality checklist extended to embedded markdown snippets** (#635): Protocol 03's Shell Script Quality Checklist now applies to `bash`/`sh` code blocks in protocol `.md` files; `developer` agent files and `REVIEW.md` are updated to reflect the extended scope.
- **`sync-template`: end-to-end automation — auto-create PR and run reviewer loop** (#630): Steps 5–6 now execute git/PR steps and the full reviewer loop automatically instead of printing instructions for the human.
- **`sync-template`: "apply all" walks through manual-review and optional-additive items inline** (#629): "apply all" no longer silently skips non-always-sync items; it presents each inline for confirm/skip.
- **Plan-writer cross-section consistency check extended to file paths and routes** (#591): the mandatory self-check in Protocol 02 Step 5.5 now covers file paths, directory names, and route/URL structures in addition to function names and constants.
- **Spec template: prevent placeholder artifacts from reaching spec PRs** (#568): the spec template converts instruction blocks to HTML comments; Protocol 01 adds a mandatory placeholder-removal grep check before every spec PR.
- **PR-Agent ticket compliance check disabled** (#569): `require_ticket_analysis_review = false` prevents false-positive compliance findings from cross-repository issue references.
- **Release post-merge cleanup: Linear tracker support for `Merged` → `Released` transitions** (#627): `workflow-lib.sh` now detects `provider: linear` and emits actionable per-issue guidance instead of a misleading skip message.
- **Item-orchestrator: cross-layer scope check before Fast Track classification** (#601): Protocol 91 Step 2 gains a mandatory check — items with signals spanning multiple architectural layers must route to the Full Pipeline, not Fast Track.
- **Retrospective protocol: Step 3b subagent detection and fallback** (#593): Step 3b clarifies that the template cross-reference uses `gh` CLI only and provides a filesystem-based YAML read command for subagent runners.
- **ShellCheck SC1007: replace `CDPATH= cd` with `CDPATH='' cd`** across all workflow scripts (16 occurrences, 11 files).
- **`check-tracker-merge-mapping.sh`: `get_target_status` uses `awk` block extraction** instead of `grep -A5` to avoid silent empty results when `TARGET_STATUS` is more than 5 lines below the branch marker.

## [0.26.1] - 2026-05-11

### Fixed

- **`pr-review-loop.sh`: remove duplicate `RESULT=needs_rerun` output** (hotfix): `print_kv RESULT needs_rerun` was emitted twice — once by the general emit block and again inside the final `case` switch. The redundant emission in the `needs_rerun)` branch is removed; only the general block emits the value.
- **`pr-review-loop.sh`: `normalize_platform_verdict` now handles `advisory` result** (hotfix): compare-mode runs where a platform returned `advisory` fell through to the `*)` catch-all and were logged as `unavailable` in the metrics file. An explicit `advisory) printf 'advisory' ;;` case is added.
- **`codex-github-reviewer.sh`: async grace trigger comment respects `--max-retriggers=0`** (hotfix): the async grace period unconditionally posted a trigger comment even when callers passed `--max-retriggers=0`. The `gh api POST` call is now guarded by `[ "$MAX_RETRIGGERS" -gt 0 ]`; when retriggers are disabled the grace poll still runs but no comment is posted.

## [0.26.0] - 2026-05-11

### Added

- **Comparison mode for `pr-review-loop.sh`** (#563): `--compare` flag runs all configured review platforms to completion regardless of individual blocking verdicts, records per-platform metrics in `docs/workflow/retro-metrics-platforms.md`, and includes per-platform details in the Automated Reviewer Loop Summary comment. A new meta-retrospective Step 2b reads this data to track each platform's exclusive-block rate. Normal invocations are unaffected.
- **AI evaluation for PR-Agent "Possible Issue" findings** (#562): when PR-Agent returns clean with a "Possible Issue" advisory label, the reviewer loop dispatches a code-reviewer agent to evaluate the finding. A confirmed bug triggers a fix and loop re-run; an acceptable finding gets an acknowledgment comment and the loop proceeds clean. Other advisory labels remain non-blocking and unevaluated.
- **CodeRabbit as Step 7a internal reviewer** (#528): `coderabbit` is now a valid value for `review.internal_reviewers` in `.ai-dev-workflow.yaml`, allowing CodeRabbit to run as a draft-PR internal reviewer before non-draft conversion.

### Fixed

- **`pr-review-loop.sh`: detect CodeRabbit outside-diff comments as unresolved**: comments on lines outside the PR diff are invisible to the GraphQL `reviewThreads` API; a new `check_unreplied_rest_comments` function queries the REST pulls-comments endpoint so these findings are no longer silently ignored.
- **`pr-review-loop.sh`: label-aware PR-Agent classifier and advisory findings in summary** (#518, #523): `_pr_agent_classify` now parses bold `<strong>LABEL</strong>` tokens to distinguish advisory labels (non-blocking) from hard blockers, stopping false `needs_fixes` loops on chore/sync PRs. Advisory labels found on clean passes are surfaced in the Automated Reviewer Loop Summary under an "Advisory findings (non-blocking)" section.
- **`pr-review-loop.sh`: automated reviewer loop summary now script-owned** (#504, #570): the `### Automated Reviewer Loop Summary` comment is posted automatically by the script on `clean` and `escalate` exits, eliminating recurring agent omissions. Subsequent invocations update the existing comment in place via PATCH instead of appending duplicates.
- **`pr-review-loop.sh`: enforce `ready-for-regression` on Fast Track `fix/*` PRs** (#556): Path 3 Step 9 now inlines the full two-phase pre-label ordering gate so Fast Track agents see the requirement without a cross-reference lookup. A Step 7b assertion in `_post_review_summary` surfaces the missing label immediately when the loop exits clean.
- **Agent branch discipline: main-tree return and worktree branch-leak prevention**: `item-orchestrator` and `developer` agents now switch back to the integration branch before returning (preventing Step 5.2 false fires in serial batches); an explicit `BATCH_CONTEXT` branch-skip rule closes the worktree CWD-guard propagation gap in dispatched subagents; Protocol 91 Step 3 adds a mandatory branch-context verification block after `git switch` (#520).
- **Batch orchestration: spec/plan stage items excluded from `TOOL_FIX=unknown` serialization** (#571): items at `Writing Spec` or `Writing Plan` are now treated as `TOOL_FIX=no`, preventing unnecessary single-item sub-batches. Step 5.2 violation counter clarified to apply only to parallel batches — serial-dispatch residuals are expected and do not count (#516).
- **Stale tracker status transitions corrected in orchestrator pre-dispatch** (#487): stale "In Development" detection and correction added to Protocols 90/91; `check-tracker-merge-mapping.sh` added to verify the workflow-to-tracker mapping; `update-tracker-on-merge.yml` now logs a mapping summary for CI auditability.
- **`GITHUB_PROJECT_OWNER` resolution hardened in `workflow-lib.sh`** (#549): new `workflow_resolve_github_project_owner` helper implements a three-tier fallback (env var → `gh repo view` → git remote URL) so tracker updates are not silently lost in subagent shells where `GITHUB_TOKEN` is absent.
- **Retrospective protocol strengthened** (#552, #554, #555): Step 3b now has a mandatory completion gate when `template.repository` is configured; `retro-metrics.md` must be committed and pushed immediately after appending the metrics row; `contribute-upstream` findings are auto-filed as upstream GitHub issues before being presented to the human.
- **Intra-file content-duplication check added to documentation PR review pass** (#553): `REVIEW.md` Pass 2 now flags new sections that reproduce tables or lists already present in the same file, and contradictions between sibling sections.
- **Shell scripting best practices documented** (#521, #512): `docs/best-practices/1-general.md` adds a `## Shell Scripting` section covering fail-open error handling, input validation, `pipefail`, grep anchoring, glob precision, and rules for `# shellcheck disable=` directives with mandatory inline explanations.
- **Protocol 03 implementation guards tightened** (#536, #509, #515): every `gh pr create` step now includes a mandatory base-branch guard; hotfix Path 4 requires a pre-commit edge-case reasoning checklist; implementation plans must cite the enforcement mechanism for every behavioral guarantee.
- **Hotfix CHANGELOG placement corrected**: `auto-tag-release.yml` updated to use a semver-anchored grep pattern so it correctly skips `[Unreleased]`; `AGENTS.md` and Protocol 03 now correctly document that hotfix entries go directly below `[Unreleased]` (above all prior versioned sections).
- **sync-template: pre-flight diagnostic and CI validation** (#538, #513): Step 0.5 runs a read-only diagnostic before modifying any files, detecting conflict risks, CI workflow gaps, CHANGELOG structural defects, and protocol incompatibilities. A `--dry-run` flag stops after diagnostics. Step 4.5 validates all workflow YAML files and `scripts/` path references after applying changes.
- **CHANGELOG link reference definition lint check** (#539): `check-changelog-duplicate-headers.sh` now verifies that every versioned section heading has a corresponding link definition at the bottom of the file, preventing broken comparison links in rendered CHANGELOGs.
- **CodeRabbit scope restricted to PR diff** (#537): `.coderabbit.yaml` sets `changed_files_only: true`; Protocol 93 adds a "Cross-file expansion" section directing agents to defer out-of-scope suggestions to a new backlog issue.
- **`codex-github-reviewer.sh` async-arrival grace period** (#505): after all poll retries are exhausted, the script waits one additional `POLL_INTERVAL` before declaring `TIMED_OUT`, catching bot responses that arrive just after the polling window closes.
- **Hotfix backport PR reviewer-loop exemption documented** (#508): identical cherry-pick backport PRs may proceed directly to merge when automated reviewers return clean or no result; backports with conflict-resolution changes must still run the full loop.

## [0.25.1] - 2026-05-06

### Fixed

- `codex-github-reviewer.sh`: verdict parsing now requires a colon after "blocking issues" (matching list form "blocking issues: …") to disambiguate from clean responses like "No blocking issues found"; also adds "no blocking issues" as an explicit approval signal, eliminating false NEEDS_REVISION verdicts on clean Codex responses
- `codex-github-reviewer.sh`: idempotency guard now uses `contains($sha)` instead of `test($sha)` in jq for literal substring matching instead of unanchored regex matching

## [0.25.0] - 2026-05-06

### Added

- **External feedback pipeline: GitHub Discussions staging and triage protocol** (#459): Adds `CONTRIBUTING.md` directing external users to submit feedback via GitHub Discussions, a triage protocol (`07-feedback-triage-protocol.md`) for periodic review and promotion of high-signal community feedback to tracked issues, and the `feedback-staging` label for promoted issues.
- **PR-Agent integration**: self-hosted automated PR review via GitHub Actions using a configurable LLM backend (DeepSeek or Kimi K2.6) — no per-seat pricing; cost is LLM API token usage only. Adds `pr-agent` platform support to `pr-review-loop.sh` with a new `run_pr_agent_review()` adapter, `.github/workflows/pr-agent.yml`, `.pr_agent.toml`, and an integration guide at `docs/workflow/development-workflow/integrations/pr-agent.md`. (#499) Fixes a config race condition where PR-Agent merges TOML settings after its initial fallback check — a TOML-only configuration silently fell back to OpenAI defaults (`gpt-5.4` / `gpt-5.4-mini`) and failed with `dummy_key` auth errors. Pins `config.model`, `config.fallback_models`, `config.model_weak`, `github_action_config.pr_actions`, `auto_review`, `auto_describe`, and `auto_improve` as GHA env vars in the workflow so they take effect before the fallback fires; `model_weak` is also added to `.pr_agent.toml` as defense-in-depth.
- **Add structured retro metrics and meta-retrospective protocol** (#458): Adds a required metrics block step (Step 3d) to the retrospective protocol and a new `06b-meta-retrospective-protocol.md` for periodic verification of improvement effectiveness, along with the initial `docs/workflow/retro-metrics.md` tracking log. Updates agent, skill, and documentation files to reference the metrics block and the meta-retrospective protocol.
- **Add Playwright-based design review for frontend changes** (#450): Adds a `design-reviewer` agent (`.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md`) that uses `playwright_cli` to render affected pages, capture screenshots, check browser console errors, and run axe-core accessibility checks (WCAG 2.1 Level AA). Protocol 91 Step 7a is updated to invoke the design-reviewer agent during the internal review gate for implementation PRs that include frontend file changes. Gracefully skips when no frontend changes are detected, when the browser automation provider is unavailable, or when the preview URL cannot be reached.
- **Split code review into spec-compliance and code-quality passes** (#449): Step 7a internal review gate now runs two sequential passes for implementation PRs — Pass 1 (Spec Compliance) before Pass 2 (Code Quality). Spec and plan PRs remain single-pass. REVIEW.md Code Review Checklist is split accordingly, and code-reviewer agent/skill files are updated to scope evaluation per pass.
- **Add attempt tracking to reviewer loop prompts** (#448): Fixer agents dispatched on retry (cycle ≥ 2) now receive an attempt-context prefix in their prompt summarising what prior attempts addressed and what findings remain open, enabling them to avoid repeating failing approaches and converge faster. Protocol 91 Step 7 and Protocol 93 both document the injection rule and required prompt format.
- **Add pre-merge setup signal for PRs requiring human configuration** (#367): Adds a `needs-setup` label and a standardised `## Pre-merge Setup` PR body section so agents surface infrastructure dependencies (env vars, secrets, DNS records) at PR readiness time rather than requiring the human to read the diff. Protocol 91 Step 8a now includes a diff-scan heuristic step; protocol 92 defines the label semantics and valid co-label combinations.
- **Add `custom_fields` support for issue tracker config** (#453): Adds a `custom_fields` flat map under `issue_tracker` in `.ai-dev-workflow.yaml` and a `workflow_issue_tracker_custom_field` helper function in `workflow-lib.sh` to read individual custom field values. Updates Linear and GitHub Projects integration docs to document recognised fields.

### Fixed

- **Apply mechanical reviewer findings inline before dispatching a fixer sub-agent** (#495): Protocols 91 (Step 7) and 93 now include an inline fix rule — when all blocking findings are mechanical (single file, fully described, ≤ 5 lines), the orchestrator applies them directly using Edit/Bash tools without spawning a sub-agent, eliminating the 10–20 minute startup overhead for one-line changes.
- **Automate GitHub Projects tracker status update on PR merge** (#463): adds `.github/workflows/update-tracker-on-merge.yml` — a GitHub Actions workflow triggered when a `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*` PR is merged to `develop`. The workflow extracts the issue number from the branch name and updates the GitHub Projects v2 Status field to `Spec Ready`, `Plan Ready`, or `Merged` accordingly; implementation branches also close the linked issue. Eliminates stale statuses that persisted until the next orchestrator run. Requires `GITHUB_PROJECT_NUMBER` and `GITHUB_PROJECT_OWNER` repository variables. Updates `docs/workflow/development-workflow/integrations/github-projects.md` with setup instructions.
- **Branch-type-aware timeout in `pr-review-loop.sh`** (#462): on `spec/*` and `implementation-plan/*` branches, Devin has no trigger condition and exits immediately with `REASON=no_check_run`. The script now automatically reduces `--max-wait` from 1200 s to 60 s and `--poll-interval` from 120 s to 30 s for these branch types when the caller does not pass the respective flag explicitly, preventing 20-minute wait-budget waste on non-implementation PRs.
- **Fixer agents must fix all occurrences of flagged literal values** (#426): added mandatory all-occurrences rule to Protocol 93 fix-cycle guidance — when a reviewer flags a literal value (numeric constant, hex value, identifier, repeated string), fixer agents must `grep -n` the old value across all affected files and fix every occurrence in the same commit before pushing.
- **Mandatory "Automated Reviewer Loop Summary" comment after `pr-review-loop.sh`** (#461): Protocol 91 Step 7 now uses explicit mandatory language ("You MUST post a PR comment...") for the summary comment after every non-skipped exit result (`clean`, `needs_fixes`/escalate, `max_cycles`). The result table is updated to call out the requirement per exit path. Previously, the language was passive and agents omitted the comment when the loop exited cleanly, causing the Step 8c `hasReviewSummary` hard gate to block `ready-for-human-review`.
- **Cross-section consistency check in tech-lead plan protocol** (#427): added mandatory self-check step in `02-generate-implementation-plan-protocol.md` requiring the tech-lead to verify all function names, constants, and decision indices are defined consistently across plan sections before committing; added matching blocking checklist entry in `REVIEW.md` plan review
- **CHANGELOG duplicate section headers after clean parallel merge** (#468): `batch-merge.sh` now runs `check-changelog-duplicate-headers.sh` immediately after each clean merge; if duplicate `### Category` headers are detected within `[Unreleased]`, they are auto-consolidated (bullets merged under the first occurrence, original section order preserved) and the merge commit is amended before pushing. Protocol 94 Step 4.1 documents the new `CHANGELOG_DEDUPED` output field and deduplication behavior.
- **Async bot thread re-check in Step 8a.1** (#486): adds a mandatory 10-second wait + GraphQL re-query after the label readiness checklist passes to catch late-arriving review threads from async bots (e.g., `codex-github`). If new unresolved threads are detected, the agent removes `ready-for-human-review`, adds `needs-fixes`, and returns to Step 7a. Introduces exit code 5 (`late-arriving async bot threads detected`). Uses a shell-interpolated `JQ_FILTER` variable (instead of the unsupported `--jq --arg` flag combination) in both the pre-Check-4 gate and the Step 8a.1 re-check, injecting `CODEX_GITHUB_BOT_LOGIN` at assignment time so the correct bot login is always matched. Strips the `[bot]` suffix from `CODEX_BOT_LOGIN` before use in the JQ filter and in `run_codex_github_review()` before calling `check_unresolved_threads()` — GraphQL `author.login` values omit the `[bot]` suffix that REST API logins carry, so the default `"codex-ai[bot]"` would otherwise never match any Codex-authored thread.
- **`codex-github-reviewer.sh` response detection**: script now polls both `issues/{PR}/comments` (matching bot login with and without `[bot]` suffix) and `pulls/{PR}/reviews` (for finding-based reviews), eliminating the 5-minute timeout on clean PRs and detecting findings immediately instead of waiting for a timeout
- **`codex-github-reviewer.sh` retry-on-timeout** (#497): default `--max-wait` raised from 300 s to 600 s (10 min) per attempt, and a new `--max-retriggers` option (default `1`) automatically re-posts the trigger comment once after a timeout before exiting. Handles the recurring failure mode where Codex silently drops the first `@codex review` request — a re-post usually produces a response. Worst-case wait is `(MAX_RETRIGGERS + 1) * MAX_WAIT` (default 20 min); set `--max-retriggers 0` to keep the previous single-attempt behavior.

### Changed

- **Retrospective command dispatches agent; balanced model tier** (#457): `/retrospective` (Claude Code and Cursor) now dispatches the `retrospective` agent instead of running inline. The `retrospective` agent model is upgraded from `economy` (`claude-haiku-4-5-20251001` / `fast`) to `balanced` (`claude-sonnet-4-6` / `inherit`) — synthesis and pattern-recognition across multiple PRs requires a capable model.
- **Default internal reviewer switched from `codex` to `codex-github`**: replaced the `codex` CLI reviewer (unreachable from Claude Code and Cursor subagent runners, causing a warning on every automated PR) with `codex-github` (Codex GitHub App — universally reachable via `gh` CLI from any runner context) in the default `.ai-dev-workflow.yaml` `internal_reviewers` list. Requires the Codex GitHub App to be installed on the repository.
- **`codex-github` promoted from `internal_reviewers` (Step 7a) to `review.platforms` (Step 7)** (#486): `codex-github` now behaves like `greptile` and `devin` — handled deterministically by `pr-review-loop.sh` with idempotent pre-check, trigger, poll, and result phases. Removes the async race condition inherent in the synchronous internal-reviewer gate. Adds `run_codex_github_review()` to `pr-review-loop.sh`, updates `bot_login_for_platform()` to return the configured bot login, moves the `codex-github` entry from `internal_reviewers` to `platforms` in `.ai-dev-workflow.yaml`, and removes `codex-github` from the Step 7a reviewer dispatch table and reachability table in Protocol 91.
- **Exit code contract table in Protocol 91 Step 8a** (#433): added a prominent table documenting exit codes 0–4 at the top of the Label Readiness Checklist to prevent future exit code collisions
- **`product-manager` agent upgraded to `premium` model tier** (#456): spec writing is the highest-leverage task in the pipeline — a weak spec cascades into worse plans and worse implementations. Updated `agent-model-config.md` rationale, model IDs in `.claude/agents/product-manager.md` and `.cursor/agents/product-manager.md` (to `claude-opus-4-7`), and Codex skill tier in `.codex/skills/workflow-spec-writer/SKILL.md` (to `premium`).

## [0.24.0] - 2026-04-29

### Fixed

- **GitHub Actions SHA pinning**: pin `actions/checkout` and `actions/setup-node` to commit SHAs instead of version tags in `deploy.yml`, `e2e-regression.yml`, and `shellcheck.yml` for supply chain security
- **`add-backlog-item.sh` empty value validation**: `--body-file` and `--label` options now reject empty strings in addition to missing arguments
- **`workflow-batch-plan.sh` issue-number skip logic**: gate the "no issue number" skip on GitHub Projects being configured — repos using Linear (no `GITHUB_PROJECT_NUMBER`) no longer incorrectly skip all folders without numeric prefixes in their slugs

## [0.24.1] - 2026-04-30

### Added

- **`codex-github` integration reviewer path** (#309): runner-agnostic internal reviewer that posts a trigger comment to a PR and polls for the Codex GitHub App bot response. Works from Claude Code, Cursor, headless CI, and Codex runner contexts.
- **Parallel batch file-level conflict detection** (#324): batch orchestrator extracts declared file sets from implementation plans and automatically serializes items with overlapping files before dispatch.
- **Async/concurrency safety checklist** (#348): conditional checklist in plan protocol and review contract for concurrent event sources — covers shared mutable state, re-entrancy, event deduplication, listener cleanup, and race conditions.
- **Template-fit check in plan protocol** (#413): Step 0 gate verifies specs are sufficiently generic for template repositories before writing plan content. Prevents wasted cycles on framework-specific specs.
- **Sync-template migration notes**: versioned manual migration steps in `sync-manifest.yaml` with pre-sync checklist presentation when downstream `last_synced_version` predates a breaking change.

### Changed

- **Bash 3.2 compatibility rule**: workflow scripts must avoid bash 4+-only syntax (`local -A`, `declare -A`, etc.) since macOS ships bash 3.2. Added to developer agent rules and Protocol 03 ShellCheck blocks.

### Fixed

#### Review verification gates

- **GraphQL `reviewThreads` verification before `ready-for-human-review`** (#425): mandatory gate runs the query inline and blocks with exit code 4 if unresolved bot-authored threads exist.
- **`ready-for-regression` verification before `ready-for-human-review`** (#424): hard blocking gate with exit code 3 prevents skipping Step 7b under token pressure.
- **Re-query `reviewThreads` after each push** (#330): mandatory fresh query after every fixer push before proceeding to Step 7b/8.
- **Commit SHA verification before marking findings resolved**: agents must confirm cited commits exist in `git log` before recording `resolved_commit`.

#### Worktree isolation

- **Runtime CWD guard** (#411): new `worktree-cwd-guard.sh` provides wrapper functions that assert CWD is inside the worktree before executing state-changing git commands.
- **CWD safety for Step 5.2** (#383): `MAIN_REPO_ROOT` derived via `git-common-dir` instead of `--show-toplevel` to prevent false results when CWD drifts.
- **Worktree discipline pre-operation checklist**: explicit confirmation required before state-changing git commands in Protocol 91, 93, and all four Protocol 03 branching paths.

#### Batch merge and PR state

- **`batch-merge.sh` now pushes and calls `gh pr merge`** (#412): PRs no longer left in `OPEN` state after batch push.
- **Branch deletion waits for MERGED confirmation**: new `delete-branch` subcommand re-checks PR state before deletion.
- **Pre-merge conflict marker guard**: exits non-zero with diagnostic if unresolved markers present.
- **Sequential merge calls required** (protocol 94): explicit sequencing rule prevents conflicted working tree cascade.

#### Shell script robustness

- **Shell script quality checklist** (#388): covers jq variable injection, SIGPIPE handling, exit code semantics, `local` trap, `gh` error handling, and input validation.
- **`jq` control character handling** (#375): replaced `jq` pipelines with Python3 `json.load()` for tracker API responses.
- **GraphQL mutation parameterization**: switched to `-f` typed variables, eliminating shell interpolation injection risk.

#### Tracker and project board

- **Project board update before issue close** (#361): ensures project item is visible during lookup.
- **`GITHUB_PROJECT_NUMBER` fallback to YAML config**: reads `issue_tracker.project_number` from `.ai-dev-workflow.yaml` when env var absent.
- **Team-prefixed issue identifiers** (#341): extended regex to match Linear-style `<team>-<number>` patterns.

#### Sync-template

- **Post-apply path verification**: verifies cross-references resolve to actual files after applying synced content.
- **Rename detection and cleanup**: detects stale old directories after template renames and offers cleanup actions.
- **Wildcard `rm -rf` fix**: scoped cleanup to `$TEMPLATE_TEMP_DIR` instead of `/tmp/template-sync-*`.

#### Protocol enforcement

- **`ready-for-regression` enforcement at Step 5.1** (#422): orchestrator is primary enforcement point, applies label directly and re-runs CI loop.
- **Pre-dispatch environment validation** (#423): Step 3.3 checks for stale worktrees and integration-branch divergence before dispatch.
- **Spec-plan ordering gate** (#373): plan PR cannot open until spec PR is merged.
- **Trivial-fix skip rule** (#402): skips Step 7a re-run for cosmetic fixes under 10 lines.
- **Retrospective timing guardrail** (#410, #419): structural separation prevents retrospective offer before PRs merge.
- **Step 5.2 recurrence tracking** (#362): tallies violations across batches with escalation threshold.

#### Other fixes

- **Stale Devin error status bypass** (#404): `pr-ci-loop.sh` detects stale commit-status errors with no remaining findings.
- **Stale development folders without issue numbers** (#399): emits `skip` instead of false Plan Ready status.
- **Plan reviewer technical accuracy checklist** (#403): requires verification of behavioral claims against source files.
- **`hasReviewSummary` check false negatives**: extended patterns to match both full and abbreviated comment titles.
- **CHANGELOG exemption for spec/plan PRs** (#340): explicit steps and blocking review finding.
- **Cross-cutting checklist file enumeration** (#389): plans must list all affected agent/skill files.
- **Fixer batching rule** (#372): all fixes applied and pushed once per dispatch cycle.
- **`.worktrees/` gitignored**: both worktree path conventions now excluded.

## [0.23.2] - 2026-04-27

### Fixed

- **`shift 2` without guarding `$2` in `add-backlog-item.sh`**: Option parsing for `--title`, `--body`, `--body-file`, and `--label` called `shift 2` even when no value argument followed, which aborts the script under `set -e`. Fixed by validating `$# -lt 2` before each shift and emitting a clear error message.

- **`local IFS=','` leaking across function scope in `batch-merge.sh`**: Setting `local IFS=','` inside the explicit-PR parsing block left IFS altered for all subsequent code in the same function. Replaced with `IFS=',' read -r -a _pr_tokens <<< "$explicit_prs"` (IFS scoped to the read command only) and declared the array with `local -a` to prevent it from escaping the function.

- **Branch name used as unescaped grep regex in `post-merge-cleanup.sh`**: The worktree lookup used `grep -B2 "branch refs/heads/$TO_DELETE$"`, interpreting the branch name as a regex pattern. Branch names containing `.`, `+`, or other metacharacters could produce false matches, and `grep -F` without a line-boundary check would additionally match branch names that are a prefix of another checked-out branch. Replaced the grep pipeline with an `awk` exact-string comparison (`$0 == branch`) against the structured porcelain output, eliminating both the regex-injection risk and the prefix-match false positive.

## [0.23.1] - 2026-04-26

### Fixed

- **Bot login format mismatch in GraphQL thread audit** (`pr-review-loop.sh`):
  `bot_login_for_platform()` passed `[bot]`-suffixed bot logins to `check_unresolved_threads`,
  but the GitHub GraphQL API returns `author.login` without the suffix for bot-authored comments.
  The string comparison always failed, causing the unresolved thread gate to report zero unresolved
  threads even when unresolved bot threads existed. Fixed by removing the `[bot]` suffix from
  `bot_login_for_platform()` return values to match the GraphQL API contract. Updated documentation
  and smoke test to reflect that GraphQL returns bare bot login strings.

## [0.23.0] - 2026-04-25

### Added

- **Retrospective template-aware backlog cross-reference with version tracking** (#299): Adds optional `template.repository` and `template.last_synced_version` fields to `.ai-dev-workflow.yaml`. Extends retrospective Step 3 to classify findings against the upstream template backlog (already tracked / already fixed / contribute upstream). Updates sync-template skill to record the last-synced version automatically. Backwards-compatible — silently skipped when not configured.

- **Sync-template manifest-driven reliability** (#252): Introduce `sync-manifest.yaml` as the authoritative file list for sync-template; add `<!-- TEMPLATE-OWNED-START -->` / `<!-- TEMPLATE-OWNED-END -->` HTML-comment annotation markers to mixed-content files (`AGENTS.md`, `.ai-dev-workflow.yaml`); update all sync-template artefacts (`.claude/commands/sync-template.md`, `.claude/skills/sync-template.md`, `.cursor/commands/sync-template.md`) to consume the manifest with graceful fallback when absent; add new Codex skill `workflow-sync-template`; update `AGENTS.md` Maintenance Commands table to include `workflow-sync-template` in the Codex column.

- **Database migration review checklist** (`REVIEW.md`): trigger/backfill arithmetic parity when both exist in the same migration.

- **Scope-drift guardrails for spec and plan authoring**: protocol updates now require brief-objective coverage matrices and PR-visible deferral notes in spec writing, plus live repo verification logs for pattern-based plan scope checks; review checklists and agent/skill entrypoints were aligned, and a workflow fixture was added for stale-enumeration validation.
- **Release post-merge cleanup command** (`prepare-release-post-merge-cleanup.sh`): verifies both release PRs are merged before deleting `release/vX.Y.Z`, removes remote/local release branches safely, and transitions explicitly scoped tracker items from `Merged` to `Released`.

### Changed

- **Rename docs/ai/ to docs/workflow/** (#251): renamed the `docs/ai/` directory to `docs/workflow/` to clarify framework ownership. Updated all cross-references across agent definitions, Cursor/Codex wrappers, scripts, protocol files, and root documentation. No content changes — pure structural refactor.

- **Sync-template skill and commands** (GitHub #239, #240, #243): include `.codex/skills/` in always-sync paths; require deterministic directory enumeration and `diff`/`cmp` comparison; treat "apply all" as always-sync only (never bulk-applies special-handling files); add placeholder guard for `deploy.yml` / `e2e-regression.yml`; scope `git add` paths in the Claude command variant instead of `git add .`.

- **Retrospective protocol** (GitHub #248): optional **Contribute upstream** action for workflow-only insights via labeled issues on the template repository.

- **Spec authoring guardrails** (GitHub #260, #261): `spec-template.md` and `01-generate-spec-protocol.md` reinforce product language, consistency, testable acceptance criteria, and a pre-PR self-check pass.

- **Automated reviewer loop protocol** (GitHub #241): shell workflow fixes require `bash -n` and a narrow behavioral verification before push.

- **GitHub Actions workflow security checklist** (`03-implement-development-protocol.md`): developer guidance now requires least-privilege `permissions`, full-SHA `uses:` pinning, scoped path filters, and `concurrency` controls whenever `.github/workflows/*.yml` files are created or materially updated.
- **Parser-risk implementation-plan requirements** (`02-generate-implementation-plan-protocol.md`, `implementation-plan-template.md`, `REVIEW.md`, `tech-lead` agents): plans that touch parser/regex/structured-text scanning now require deterministic classification plus mandatory edge-case enumeration, unit-test mapping, and conditional suppression semantics.
- **Prepare-release protocol and command wrappers** now include a required post-merge Step 9 that runs branch cleanup plus tracker transition guidance after both release PRs merge.

### Fixed

- **Protocol 91 Step 8c: require explicit GraphQL reviewThreads query** (#319): Step 8c now includes a standalone `gh api graphql` bash block (matching the Protocol 90 Step 5.1 pattern) that agents must execute to verify all bot-authored review threads are resolved before labeling a PR `ready-for-human-review`. Previously the query was embedded inline in a dense table cell, causing agents to rely on their own thread-tracking state rather than querying the API directly. The table row for this check is simplified to reference the new standalone block.

- **Re-trigger CodeRabbit for skipped (no_review) PRs after parallel batch completes** (#300): Protocol 90 Step 5.3 (new) instructs the orchestrator to scan all batch PRs for a `REASON=no_review` signal (emitted by `pr-review-loop.sh` when CodeRabbit exhausts its rate-limit budget without producing a review) in their reviewer loop summary comments after every Work Item Runner returns. For any affected PR, the orchestrator posts `@coderabbitai review`, re-runs `pr-review-loop.sh`, and re-applies readiness labels before declaring the batch complete. Step 3.7 is updated to cross-reference Step 5.3 so the per-PR rate-limit description and the post-batch recovery step are linked. This eliminates the manual second-reviewer-loop that humans previously had to run when CodeRabbit exhausted its per-hour budget across a parallel batch.
- **Skip development folders with terminal tracker status in `workflow-batch-plan.sh`** (#301): when `GITHUB_PROJECT_NUMBER` is set, `workflow-batch-plan.sh` now queries the GitHub Projects tracker for each candidate development folder and skips any whose status is `Released`, `Merged`, or `Cancelled` before invoking `workflow-next-action.sh`. This eliminates false-positive "Plan Ready" candidates for already-completed items and removes unnecessary tracker lookups from batch runs. Added `is_terminal_tracker_status()` and `get_tracker_status_for_issue()` helpers to `workflow-lib.sh`; issue numbers are resolved from `**Issue**: #NNN` frontmatter in spec/plan files, with a fallback to the leading numeric prefix of the folder slug.
- **Spec template Open Questions removal instruction** (#302): clarified the instruction comment in `spec-template.md` and the Step 2 rule in `01-generate-spec-protocol.md` to explicitly require deleting the entire `## Open Questions` heading and body (not replacing content with a placeholder comment) when all questions are resolved. <!-- markdown-heuristic-disable COUNT001 -->
- **Document Codex-reviewer runner-context constraint in `.ai-dev-workflow.yaml`** (#291): added an inline comment after the `- codex` entry and an explanatory comment block above `internal_reviewers` clarifying that `codex` is typically only reachable when Codex is the top-level runner itself — not from Claude Code subagents, Cursor subagents, headless environments, or any nested runner context. The `warn` policy (default) already handles this gracefully; the new comments make the constraint visible in the config file that operators edit directly, so the recurring "Skipped: codex" PR warnings are no longer surprising. A future GitHub-integration-based path will enable Codex review from any runner. For now, operators can suppress the warning by removing `codex` from the list or using a `.tmp/template-config.json` local override.
- **Worktree gotcha: `git rev-parse --show-toplevel` returns worktree path** (#293): Protocol 91 Step 3 now documents that `git rev-parse --show-toplevel` returns the _worktree_ path (e.g., `.claude/worktrees/agent-xyz/`) rather than the main repo root when run inside an isolated worktree. The correct alternative — `$(git rev-parse --git-common-dir)/..` — is shown alongside the existing worktree git discipline block; `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` add a matching concise gotcha note.
- **Pre-push ShellCheck self-check for `.sh` file changes** (#292): `03-implement-development-protocol.md` now requires running `shellcheck --severity=warning` on any modified or newly created `.sh` files before committing, across all four implementation paths (Full Pipeline, Refactor, Fast Track, Hotfix). This agent-side gate mirrors the existing CI `shellcheck.yml` check and prevents ShellCheck violations from surfacing in the external reviewer loop (CodeRabbit/Devin), reducing unnecessary review-loop churn. `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with a matching rule.
- **Tracker status routing for subagents** (#310): Protocol 91 Step 8b now documents two explicit routing paths for tracker status updates. For GitHub Projects (`provider: github_projects`), subagents must use `gh` CLI via Bash — no MCP server required — and update status directly from their execution context. For other providers (Linear, Jira, etc.) where no CLI equivalent exists, subagents cannot reach MCP and must instead emit a `TRACKER_UPDATE_REQUIRED:` line in their summary; Protocol 90 Step 5 (Supervise Until Terminal) now codifies that the Portfolio Orchestrator owns all such deferred transitions and must scan each returning subagent's summary to apply them. Protocol 90 Step 2.5 documents the same CLI-vs-MCP routing choice and the invariant that the orchestrator always has MCP access for pre-dispatch updates. `docs/workflow/development-workflow/integrations/github-projects.md` gains a new "CLI Update Patterns for Agents and Subagents" section with a ready-to-use one-shot status update script, a status-value lookup table for Step 8b targets, and a field/option-ID caching strategy.
- **Skip tracker status update when current status is unrecognized** (#304): `update_tracker_status_best_effort()` in `workflow-lib.sh` now skips the GraphQL mutation and emits a warning when `workflow_status_order()` returns `-1` for the item's current status — indicating a custom or unknown label not present in the hardcoded ordering map. Previously the rollback guard (`current_order > target_order`) never triggered for `-1`, so the mutation would silently overwrite an advanced status (e.g., "Development in Review") with an earlier one. The guard is bypassed only when the caller explicitly provides a `required_current_status` argument that matches the actual current status, which is treated as an intentional opt-in.
- **`prepare-release-post-merge-cleanup.sh` fails non-zero on zero tracker updates** (#305): when `--issues` is supplied the script now tracks `updated / skipped / failed` counters per issue, emits a structured `UPDATED=N SKIPPED=N FAILED=N` summary line, and exits non-zero if `UPDATED=0` or any hard failure occurred. Adds `--best-effort` flag to restore the previous always-exit-0 behaviour for callers that require it.
- **Thread-audit GraphQL failure now escalates instead of emitting RESULT=clean** (#303): `coderabbit_thread_gate_clean()` and the aggregate thread gate in `pr-review-loop.sh` previously treated `check_unresolved_threads` exit code 3 (GraphQL query failure) as "not blocking on threads", returning 0 and allowing `RESULT=clean` to propagate even when the thread audit was skipped. Both gates now retry up to `THREAD_AUDIT_MAX_RETRIES` times (default: 3) with a 5-second wait between attempts; after all retries are exhausted they emit `RESULT=escalate` with `REASON=review_thread_audit_failed`. Any other unexpected non-zero exit code also escalates. `RESULT=clean` is never emitted when the thread audit could not be completed.

- **Require all review threads resolved before ready-for-human-review** (#167): `pr-review-loop.sh` now enumerates all review threads on a PR via the GitHub GraphQL API (cursor-based pagination, up to 10 pages), filters to threads authored by configured bot logins (`coderabbitai[bot]`, `devin-ai-integration[bot]`, `greptile-apps[bot]`), and exits `needs_fixes` with `UNRESOLVED_THREAD_COUNT=N` when any thread is unresolved — regardless of severity (Critical, Major, Minor, Nitpick, Trivial). A thread is considered resolved when `isResolved=true` or the first comment body contains `✅ Addressed`. The check runs as the final gate in the aggregate exit block after all platforms return `clean` or `skipped`. Bot logins are derived at runtime from `review.platforms` in `.ai-dev-workflow.yaml`. Protocol 91 Step 8c is updated with a `reviewThreads` GraphQL verification row as a hard gate; the Step 7 Automated Reviewer Loop Summary template is extended with a "Reply-only resolutions" subsection listing threads resolved via reply + `resolveReviewThread` mutation with their rationale. Protocol 90 Step 5.1 post-dispatch PR verification checklist includes the same `reviewThreads` check.
- **Pre-label orphaned PR detection in Step 5.1** (#269): Protocol 90 "Stale / Incomplete PR Detection" now covers the case where an agent times out before any post-review labels are applied, leaving a non-draft PR with no `ready-for-regression`, no `ready-for-human-review`, and no reviewer loop summary comment. A classification table formalises all detection states and identifies this pattern as a pre-label orphaned run requiring redispatch from Step 7a. `workflow-next-action.sh` now emits `ORPHANED_PR=true` for non-draft, labelless PRs without a reviewer loop summary comment so orchestrators can detect and log the pattern without changing the existing `NEXT_ACTION=resolve-pr-readiness` output.
- **Pre-label ordering gate in developer protocol** (#270, #346): `03-implement-development-protocol.md` Step 9 now documents an explicit hard sequential two-phase gate that agents must pass before applying readiness labels — Phase 1 requires the reviewer loop summary comment to be present and all automated-reviewer threads to be resolved before applying `ready-for-regression`; Phase 2 requires all CI checks to reach a terminal state with no failures before applying `ready-for-human-review`. The gate was originally written as prose, which allowed agents to skip it accidentally (#346); Phase 1 and Phase 2 are now each expressed as a numbered checklist of executable steps: Step 1.1 runs `gh pr view --json comments` to confirm the summary comment exists, Step 1.2 runs the GraphQL thread-resolution audit and requires empty output, Step 1.3 applies `ready-for-regression`, Step 2.1 runs `pr-ci-loop.sh` and requires `RESULT=green`, and Step 2.2 applies `ready-for-human-review`. Skipping any step is explicitly labelled a protocol violation.
- **Orchestrator parallel impl batch merges must use batch-merge.sh** (#273): Protocol 90 Step 5.5 now includes an explicit batch-merge routing rule clarifying that parallel implementation batches must always be merged via `batch-merge.sh discover --prs <list>` + Protocol 94 (which provides CHANGELOG auto-resolution and active-worktree awareness); direct `gh pr merge` calls are only acceptable for single-PR or non-implementation (spec/plan) merges. A summary table and reference to the Batch 4 incident are included.
- **Devin `COMMENTED` review with inline findings treated as blocking** (#274): `pr-review-loop.sh` now treats a `COMMENTED` review from `devin-ai-integration[bot]` as blocking when it is accompanied by unresolved inline PR review comments, not only when the review body starts with `**Devin Review**`. Previously, a Devin review that submitted findings exclusively as inline comments (without a matching summary body) was silently treated as non-blocking, allowing PRs with real bugs to be incorrectly labeled `ready-for-human-review`. Protocol docs (`91-orchestrate-work-protocol.md`, `93-automated-reviewer-loop-protocol.md`) updated to document the full blocking classification rules.
- **CodeRabbit retry loop skips SUCCESS status before retry wait** (`pr-review-loop.sh`): script now checks for an existing CodeRabbit SUCCESS commit status on the current HEAD before entering the rate-limit retry sleep; if SUCCESS is already present (and thread gate passes), the loop exits immediately via `coderabbit_status_success_fallback` rather than waiting indefinitely.
- **Single-instance guard** (`pr-review-loop.sh`): added atomic mkdir lock directory (`/tmp/pr-review-loop-<pr>.lockdir`) at script startup so a second invocation for the same PR exits immediately with `RESULT=escalate` / `REASON=lock_contention` (exit code 75) rather than running in parallel.
- **Plan verification step simplicity** (#280): added guidance to `02-generate-implementation-plan-protocol.md` requiring verification commands in Implementation Order steps to be simple and human-readable (prefer prose assertions over exact counts, avoid complex multi-flag grep one-liners); added a corresponding `important`-severity reviewer note to `REVIEW.md` Plan Review Checklist instructing plan reviewers to flag complex shell verification commands and suggest simpler "run and confirm output" assertions.
- **Mass-rename reference-type coverage** (#281): `03-implement-development-protocol.md` Refactor path now includes a mandatory mass-rename sub-step requiring post-substitution verification of three reference categories — link targets (both href and display text when text mirrors the old path), display text in already-updated links, and non-link occurrences (prose, code blocks, directory trees, YAML values) — plus a residual-occurrence grep command to confirm no old-string instances remain before staging.
- **Document complete hotfix protocol** (#295): closes five documentation gaps in the hotfix workflow. (1) `03-implement-development-protocol.md` Path 4 Step 6 now specifies that hotfix CHANGELOG entries go in a new versioned section (e.g., `[1.0.1] - YYYY-MM-DD`) directly below `[Unreleased]` (above all prior versioned sections), not under `[Unreleased]`, since hotfixes patch released code and are released immediately on merge. (2) Step 9 now includes concrete backport steps: create a dedicated `backport/hotfix/[slug]` branch from `origin/main` post-merge, open a draft PR targeting `develop`, and run the standard review + CI loop. (3) Branch lifecycle is now explicit: `hotfix/[slug]` merges to `main` and is not reused; the backport uses a separate branch. (4) `auto-tag-release.yml` now triggers on `hotfix/*` merges to `main` and extracts the version from the topmost versioned CHANGELOG section (since hotfix branch names do not encode the version). (5) `workflow-next-action.sh` `--branch` mode already handles `fix|hotfix|refactor` prefixes correctly (no code change needed). `docs/workflow/development-workflow/README.md` hotfix section, `docs/best-practices/2-version-control.md` CHANGELOG rules, `.claude/agents/developer.md`, `.cursor/agents/developer.md`, `AGENTS.md`, and `.cursor/rules/workflow.mdc` updated consistently.

- **Post-agent main working tree sanity check** (#229): Protocol 90 Step 5.2 now runs immediately after each Work Item Runner returns — before PR verification, before the next dispatch, and before any action that assumes the integration branch context; the Case 1 postcondition table now documents the root-cause implication of a wrong-branch + clean result (agent ran in main tree instead of worktree). Protocol 91 post-terminal check upgraded from a single error branch to the same four-case handling (auto-correct Case 1, halt-and-escalate Cases 2 and 4, proceed Case 3) with explicit cross-reference to Protocol 90 Step 5.2.

- **MD047 trailing-newline pre-staging check** (#227): `03-implement-development-protocol.md` (all four paths) now includes an explicit MD047 check that scans every modified `.md` file for a missing trailing newline before `git add`; `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with the matching rule (parity with the #178 trailing-whitespace step).

- **Tech-lead CHANGELOG literal format** (#226): plan protocol, plan template, and `REVIEW.md` plan-review checklist now require and enforce the project's `**Bold Title** (#N):` CHANGELOG entry format; conventional-commit-style literals (`fix(scope): message`) in Implementation Order steps are now a blocking plan-review finding.

- **CodeRabbit review pass vs unresolved threads** (GitHub #242, `pr-review-loop.sh`): Phase 3 clean and SUCCESS commit-status fallback now honor the GraphQL review-thread audit so old unresolved CodeRabbit threads cannot coexist with a "clean" platform result. Follow-up: emit `UNRESOLVED_THREAD_COUNT` from the per-platform gate and restore shell `errexit` after `check_unresolved_threads` so aggregate output stays contract-correct.

- **`workflow-next-action.sh`**: `--development` path always exits zero after emitting key=value lines (empty `LINEAR_ISSUE` no longer yields exit status 1), restoring `workflow-batch-plan.sh` parsing.

- **`post-merge-cleanup.sh` worktrees** (GitHub #250): run `git worktree unlock` before remove to clear common agent lock files without manual intervention.

- **Duplicate check-name handling in CI polling** (`pr-ci-loop.sh`): GitHub `statusCheckRollup` can contain historical entries for the same check name (for example an older `CANCELLED` run plus a newer `SKIPPED` run). The CI loop now evaluates only the latest entry per check name so stale results do not incorrectly force `RESULT=red`.

- **Internal reviewers now fix `suggestion`-level findings by default** (`REVIEW.md`): `suggestion` severity was previously "report or fix at discretion", meaning internal reviewers (Step 7a) could skip them. This left low-risk improvements for external reviewers to re-raise, lengthening the review loop. The default action is now "fix by default; report only if scope-expanding or requires a product decision."

- **`UNRESOLVED_THREAD_COUNT` now emits `-1` (not `"unknown"`) on page-cap escalation** (`pr-review-loop.sh`): the output contract specifies an integer field; using the string `"unknown"` violated the contract and required a defensive string-guard on the downstream consumer. Replaced with `-1` as an integer sentinel and removed the now-redundant guard.

- **`PR_IS_DRAFT` and `PR_HAS_NEEDS_FIXES` documented in discovery output contract** (`batch-merge.sh`): these fields were emitted by `fetch_pr_meta` but absent from the script header comment, leaving the documented contract out of sync with actual output.

- **Draft-state revalidation in `cmd_merge` to close TOCTOU gap** (`batch-merge.sh`): a PR could be switched to draft between discovery and merge execution. Added `isDraft` revalidation immediately before merge so the guard reflects current state.

- **CodeRabbit completion via issue comments** (`pr-review-loop.sh`): when CodeRabbit posts only an issue-thread summary (no `pulls/{id}/reviews` entry) for the current HEAD, the poll loop now proceeds to Phase 3 instead of spinning until `timeout` and returning a false `escalate`.

- **Plan-writer pre-commit lint step** (#271): `02-generate-implementation-plan-protocol.md` Step 5 now includes a mandatory `markdownlint-cli2` run on the plan file and smoke test runbook before staging. This catches broken relative links (wrong `../../` depth), trailing spaces, and missing trailing newlines before the first push, preventing Devin fix cycles caused by off-by-one path errors. The lint command resolves `node_modules/` from the git repo root so it works inside isolated worktrees.

- **Silent workaround loophole in item-orchestrator permission-denial contract** (#228): when `Edit`/`Write` is denied on `.claude/agents/**` or any other path, subagents were silently falling back to Bash redirects, Python subprocess writes, or `gh api --method PUT` instead of returning `SUBAGENT_PERMISSION_DENIAL`. Protocol 91 Step 3 now explicitly prohibits all alternative write mechanisms and requires the denied path(s) to be listed in the exit string; `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` add a matching enforcement note; `.claude/settings.json` adds `Edit(.claude/agents/**)`, `Write(.claude/agents/**)`, `Edit(.cursor/agents/**)`, and `Write(.cursor/agents/**)` allow-list entries to close the root-cause permission gap that triggered the workarounds.

- **Duplicate CHANGELOG section headers in developer protocol** (#272): `03-implement-development-protocol.md` (all four paths) now includes an explicit duplicate-section prevention step that requires reading the existing `[Unreleased]` block before writing an entry, appending to an existing category section rather than creating a new header, and verifying with an awk-scoped `grep -c` that each category header appears exactly once **within the `[Unreleased]` block**; `.claude/agents/developer.md` and `.cursor/agents/developer.md` key-rules sections were updated with the matching rule.
- **Duplicate CHANGELOG section-header lint check** (#318): `scripts/lint/check-changelog-duplicate-headers.sh` (new) detects duplicate `### ` headers (e.g., repeated `### Fixed`) within the same `## ` section of CHANGELOG.md. The script is added as a CI step in `.github/workflows/markdown-lint.yml` (runs unconditionally on every triggered push) and documented in the `AGENTS.md` "Common Commands" section. Protocol guidance alone (added in #272) had not prevented recurrence; this automated check enforces the constraint at CI time.

- **Policy grep coverage before multi-file changes** (#316): `03-implement-development-protocol.md` Step 1b item 6 (all four paths) and the Quality Rules section now require grepping for all existing references to a policy **before writing any code** — the grep is the discovery step, not a confirmation step. Instructions no longer say "if documented in more than one location" (which assumed prior knowledge of sibling files); they now direct agents to run the grep unconditionally to discover all locations, list every matched file as a candidate, and explicitly confirm coverage of each before submitting. `.claude/agents/developer.md` and `.cursor/agents/developer.md` were updated with a matching key rule.

- **Script-emitted signal verification in developer protocol** (#317): `03-implement-development-protocol.md` Step 1b (all four paths) now includes a mandatory item 7 requiring developers to read the relevant source script and verify the exact string before committing whenever protocol text cites a script-emitted signal value (`REASON=`, `RESULT=`, `STATUS=`, etc.). The Quality Rules section adds a matching bullet with an example `grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh` command. `.claude/agents/developer.md` and `.cursor/agents/developer.md` were updated with a matching key rule.

## [0.22.0] - 2026-04-20

### Added

- **Batch merge command** (`/batch-merge`): merges all `ready-for-human-review` PRs into `develop` sequentially; auto-resolves CHANGELOG conflicts; produces a structured outcome summary. Available in Claude Code, Cursor, and as a Codex skill.
- **Retrospective analysis command** (`/retrospective`): analyze completed batches or individual items for process improvement opportunities; findings are categorized and actioned interactively. Available in Claude Code, Cursor, and as a Codex skill.
- **Worktree isolation for parallel batch dispatch**: each Work Item Runner in a parallel batch now operates in a dedicated git worktree, preventing cross-item interference.
- **Worktree git switch guardrail** (Protocol 91): explicit prohibited-command list (`switch`, `checkout`, `reset`, `restore`) against the main repo root in batch context; Protocol 90 handles all four postcondition states after each runner returns.
- **Markdown lint CI** (`.github/workflows/markdown-lint.yml`): gates PRs touching spec, plan, and CHANGELOG docs with `markdownlint-cli2` (trailing whitespace, relative links, file newline) and a custom heuristic script (GLOB001, COUNT001).
- **ShellCheck CI** (`.github/workflows/shellcheck.yml`): gates PRs touching workflow scripts with ShellCheck `--severity=warning`.
- **Agent timeout handling guidance**: expected run durations table, resume checklist, and stale-PR detection heuristic added to `agent-model-config.md` and Protocols 90/91.
- **Pre-dispatch tracker status update** (Protocol 90 Step 2.5 / Protocol 91 Step 2): orchestrator sets the item's tracker status to the correct in-flight value and ensures it is on the project board before dispatching any runner.
- **CHANGELOG conflict mitigation** (Protocol 90 Step 3.6): each PR adds its own entry; batch-merge auto-resolution handles conflicts at merge time.

### Changed

- **Workflow agent model bump**: `tech-lead` upgraded from Opus 4.6 to Opus 4.7; Sonnet and Haiku unchanged.
- Protocol 93 (`automated-reviewer-loop`): mandatory cross-reference check before committing fixes.
- `implementation-plan-template.md`: new "Code Samples" section with guidance on illustrative samples and cross-section consistency.

### Fixed

- **Subagent permission-denial mitigation** (Protocol 90 Step 4.1 / Protocol 91 Step 3.5): subagents that hit a tool-permission denial exit with a structured signal; orchestrator falls back to inline execution from the main session.
- **Require all review threads resolved** (`pr-review-loop.sh`): new `check_unresolved_threads` gate (GraphQL `reviewThreads` API) blocks `ready-for-human-review` until all bot threads are resolved.
- **CodeRabbit SUCCESS commit-status fallback** (`pr-review-loop.sh`): avoids spurious `timeout` escalations when CodeRabbit signals via commit status during rate-limit windows.
- **CodeRabbit rate-limit handling** (`pr-review-loop.sh`): detects rate-limit comments, waits 3 min, and retries up to 2 times before falling back.
- **Transient `git pull --ff-only` retry** (`batch-merge.sh`): one automatic retry with a fresh `git fetch` before failing the merge.
- **Locked-worktree handling** (`post-merge-cleanup.sh`): tries `git worktree unlock` then double-force removal before failing.
- **Worktree blocking branch deletion** (`post-merge-cleanup.sh`): detects and removes worktrees before deleting their branch.
- **Post-merge cleanup tracker status update** (`post-merge-cleanup.sh`): unified issue-number extraction; new `update_tracker_status` helper sets `Spec Ready`, `Plan Ready`, or `Merged` with rollback prevention.
- **Post-merge cleanup closes GitHub issues**: issue number extracted from branch name; issue closed with a PR-linking comment on merge.
- **Worktree leak prevention**: three safeguards added across Protocols 90, 91, and 94 to catch unexpected main-working-tree modifications during parallel batch runs.
- **Label readiness checklist gate** (Protocol 91 Steps 8a/8b): `ready-for-human-review` now requires non-draft state, `ready-for-regression` label, and absence of `needs-fixes`; tracker update extracted to Step 8b.
- **Codex reviewer runtime fallback** (Protocol 91 Step 7a): unreachable reviewers are skipped with a PR warning; zero reachable reviewers hard-fails the gate.
- **Enforce `develop` as default PR base branch** (Protocol 03): all four paths now use explicit `--base develop` or `--base main`.
- **Scope boundary rule** (Protocols 03/91): agents must not fix out-of-scope findings in the current PR; document as a separate issue instead.
- **Pre-implementation scope checklist** (Protocol 03): enumerate all files to change before writing code.
- **Cross-reference consistency check** (Protocol 03): grep all locations of modified policy text before opening a PR.
- **Implementation protocol pre-branch fetch** (Protocol 03): `git fetch origin` before branching, matching the release protocol.
- **Reviewer loop verification** (Protocol 93): re-read file/line references before marking findings resolved.
- **Stuck-loop detection** (Protocol 93): max cycle count with mandatory escalation; no-progress and reappearing-finding heuristics.
- **Post-dispatch PR verification** (Protocols 90/91 Step 8c): orchestrator independently verifies PR state via `gh pr view` before reporting ready.
- **Pre-dispatch merged-PR cross-check** (Protocol 90 Step 1a): stale tracker items with merged PRs are closed and excluded before dispatch.
- **Prepare-release pre-flight sync**: `git fetch origin && git pull origin develop` added to the release protocol and command wrappers.
- **CHANGELOG trailing-whitespace prevention** (Protocol 03): explicit format verification sub-step in all four implementation paths.
- **Worktree Write/Edit path discipline** (item-orchestrator): reminder to target worktree paths in all Write/Edit calls.
- **Item-orchestrator upgraded to balanced tier** (Sonnet): economy (Haiku) was insufficient for multi-step review-fix-review cycles.
- **Same-batch tool-fix ordering hazard detection** (`workflow-batch-plan.sh`): classifies items that modify canonical workflow tool files; serializes them to run before the rest of the batch.
- **Unbound variable in `add-backlog-item.sh`**: `labels[@]` guard prevents `set -u` failure when no labels are passed.
- **Missing Cursor retrospective command**: `.cursor/commands/retrospective.md` created for parity with Claude Code.
- **Removed boilerplate "Guiding principle" section** from spec template and all existing spec files.

## [0.21.0] - 2026-04-13

### Added

- **CodeRabbit integration**: CodeRabbit is now available as an automated PR reviewer platform (`coderabbit` in `review.platforms`) and as a pre-push CLI tool. Includes adapter in `pr-review-loop.sh` with severity-based blocking (Critical/Major block, Minor/Low don't), `CHANGES_REQUESTED` review handling, stale-findings recovery with resolved-comment filtering, `.coderabbit.yaml` config, and setup guide at `docs/workflow/development-workflow/integrations/coderabbit.md`.
- **`/run-work` command for Claude Code**: batch orchestrator command (`.claude/commands/run-work.md`), matching the existing Cursor `/run-work`.

### Changed

- **Multi-reviewer internal review gate (Step 7a)**: Step 7a now runs all configured internal reviewers (`review.internal_reviewers` in `.ai-dev-workflow.yaml`) sequentially on draft PRs before converting to non-draft. Added `max_internal_review_cycles` (default: 5) to prevent infinite loops and local override support via `.tmp/template-config.json`. Codex reviewer dispatch uses stage-specific skills. Step 9 feedback loop corrected to include Step 7a before Step 7.
- **Post-merge status transitions (Step 10)**: new Step 10 in `91-orchestrate-work-protocol.md` maps branch type to tracker status (`spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready, implementation branches → Merged). All post-merge-cleanup commands updated accordingly.

### Fixed

- **Missing `/sync-template` command for Claude Code**: added `.claude/commands/sync-template.md` covering template source resolution, categorized diff, approval gate, file application, and git/PR instructions.

## [0.20.0] - 2026-04-10

### Added

- **Label-gated e2e/regression test workflow**: new `.github/workflows/e2e-regression.yml` runs only when the `ready-for-regression` label is applied, with a Playwright-based `e2e/` placeholder project for downstream projects to customize. The orchestrator applies the label automatically on implementation PRs after automated review is clean (new Step 7b, documented in protocols 91 and 92), and the release protocol applies it on production PRs targeting `main`. See `docs/workflow/development-workflow/integrations/e2e-regression.md` for the label-gate pattern.
- **Backlog intake stage**: new protocol `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` and `/add-backlog-item` command (Cursor + Claude Code) create work items in the configured issue tracker, backed by `scripts/development-workflow/add-backlog-item.sh` (`resolve` / `create` for GitHub) and destination helpers in `workflow-lib.sh`.
- **Template deployment scaffold**: new `.github/workflows/deploy.yml` triggers on `develop` and `main`, maps to `develop`/`production` environments, and keeps deploy steps as explicit no-op placeholders. Accompanied by `docs/workflow/development-workflow/integrations/ci-cd-deployment.md` and new CI/CD onboarding prompts in `docs/workflow/setup/protocol.md` plus branch-to-environment guidance in `docs/project/3-software-architecture.md`.
- **Prepare release drives production PR readiness**: after opening release PRs, `05-prepare-release-protocol.md` and `/prepare-release` run the automated reviewer loop, apply `ready-for-regression` on the PR targeting `main`, and run the CI loop (including label-gated e2e/regression) before handing off for human merge.

### Changed

- `92-pr-readiness-signal-protocol.md` and `integrations/e2e-regression.md`: align `ready-for-regression` conditions with production release PRs (`release/*` → `main`) per protocol `05`, removing the implementation-only contradiction.
- CHANGELOG policy: spec-only and plan-only PRs are exempt from CHANGELOG updates; fixes to unreleased work update the existing `[Unreleased]` entry instead of adding a new one. Hotfixes still require a new entry since they fix released code.
- `03-implement-development-protocol.md`: Path 2 (Refactor) and Fast Track / Hotfix paths now spell out their own draft PR metadata and `gh pr create` examples (`feat(...)` with spec/plan link for refactor; `fix(...)` with incident-focused body for hotfix) instead of reusing Path 1 Step 8; handoff steps correctly reference Step 8–9 and the Work Item Runner lifecycle.

### Fixed

- `workflow-next-action.sh --development`: branch existence and merged-PR checks now use `feature/` when the folder has a spec (full pipeline) and `refactor/` when plan-only, so parallel items with the same slug are not cross-matched across prefixes.

## [0.19.0] - 2026-04-02

### Added

- GitHub Projects v2 integration guide (status mapping, custom fields, `gh`/GraphQL, branch naming).
- Implementation plan template: regression suite checklist reminder.

### Changed

- Orchestration treats the issue tracker as the source of truth for work-item status; development folders and Git state supplement it.
- **Refactor** path: `refactor/[slug]` (plan → implement, no spec); plan-only development folders supported. Renamed `Improvement` label to `Refactor`.
- Default issue tracker: `github_projects` (was `github_issues`). Greptile removed from default review platforms in this repo.
- Renamed stage `Implementation in Review` → `Development in Review` across protocols and integration docs.
- `gh pr ready` runs after the internal review gate (Step 7a), before external reviewers and CI, so automation sees a ready PR after internal approval.

### Removed

- `Chore` tracker label; track that work as **Refactor**.

### Fixed

- Automated reviewer loop recovers stale unresolved findings from full PR history so blockers are not dropped when the latest HEAD has no fresh automated review (e.g. after base-branch merges).
- Next-action detection uses merged GitHub PRs (and slug match) so items are not misclassified as Plan Ready after the feature branch is deleted.

## [0.18.1] - 2026-03-30

### Fixed

- Automated Devin review loops now recover stale unresolved findings from PR history when the latest HEAD has no fresh Devin review, preventing blocking issues from being dropped after base-branch merges.
- Devin resolved-confirmation comments (`✅ **Resolved**`) are excluded from blocking issue counts so previously fixed findings are not reclassified as new blockers.
- Devin review detection now considers both GitHub Check Runs and Status Contexts (deduplicated by context), avoiding false `no_check_run` skips when Devin reports via statuses.

### Changed

- Automated reviewer-loop protocol pre-flight now explicitly defines unresolved findings and blocking Devin outcomes, and documents ledger bootstrap from full PR history before fix cycles.
- Workflow protocols were renumbered and normalized (`04-*` -> `03-*`, `05-*` -> `04-*`, `06-*` -> `05-*`, `89-*` -> `90-*`, `90-*` -> `91-*`, `91-*` -> `92-*`, `92-*` -> `93-*`) and several protocol filenames were standardized (`generate-specs` -> `generate-spec`, `review-specs` -> `review-spec`, `review-implemented-development` -> `review-implementation`).
- PR readiness labels were renamed to simpler defaults: `agent:ready-for-review` -> `ready-for-human-review` and `agent:needs-fixes` -> `needs-fixes`.
- `.ai-dev-workflow.yaml` now uses a versioned nested schema (`review.platforms`) and includes declarative sections for `issue_tracker`, `vcs`, and `browser_automation`.
- Stage protocols now open draft PRs first, then mark them ready with `gh pr ready` after the internal review gate (Step 7a) passes.
- Orchestration now includes an explicit Step 7a internal review gate before external automated reviewers.
- Workflow docs were refreshed, including a full rewrite of `docs/workflow/development-workflow/README.md` and terminology updates to "Portfolio Orchestrator" and "Work Item Runner".

### Removed

- `docs/workflow/development-workflow/tooling-assumptions.md`; capability assumptions and fallback guidance now live in the workflow README.

## [0.18.0] - 2026-03-18

### Added

- New Claude Code slash commands: `/run-item-work` (single-item workflow orchestration, mirrors Cursor), `/run-reviewer-loop` (automated reviewer + CI loop, mirrors Cursor), and `/post-merge-cleanup` (post-merge branch cleanup and issue tracker update, mirrors Cursor). All three are now autocompleted in Claude Code and listed as the primary entry points in the CLAUDE.md workflow table.
- Pre-flight check for existing unresolved review findings in `/run-reviewer-loop` (Claude Code and Cursor): before running the review scripts, the agent now inspects existing PR reviews for blocking findings posted by configured platforms after a previous run timed out, and dispatches a fixer first. Protocol 92 updated to document this step.
- Automated issue ledger tracking for PR review loops: the `automated-reviewer-loop` agent now maintains an issue ledger across cycles, keyed by `(platform, path, body_snippet)` to survive line shifts. After each fixer push, agents post a fix-commit comment listing resolved vs. remaining issues. When the loop terminates, agents post a final summary table with resolution status and commit SHAs.
- Devin review state expansion: `pr-review-loop.sh` now treats `COMMENTED`-state reviews from Devin as blocking findings (previously only `CHANGES_REQUESTED` was captured). This ensures out-of-diff findings posted by Devin are surfaced in the review loop.
- Protocol 90 blocking classification documentation: updated "Blocking vs. suggestion classification" section to clarify that both `CHANGES_REQUESTED` and `COMMENTED` reviews are treated as blocking.

### Fixed

- `pr-review-loop.sh`: Devin adapter now returns `skipped` instead of polling until timeout when no Devin check run exists for the HEAD commit. Subsequent pushes to an already-reviewed PR often have no check run, causing spurious timeouts and escalations.

## [0.17.0] - 2026-03-17

### Added

- Devin automated PR review adapter: `pr-review-loop.sh` now supports `--platform devin`, polling Devin check runs for completion and collecting inline findings. Added `docs/workflow/development-workflow/integrations/devin.md` with setup, bot identity, and adapter contract details.
- Workflow config file (`.ai-dev-workflow.yaml`): declares which review platforms are active for the repository. `pr-review-loop.sh` reads this file automatically when no `--platform` flag is passed, replacing the hardcoded `greptile` default. The project setup protocol generates this file during onboarding.

## [0.16.0] - 2026-03-14

### Changed

- Workflow-next-action: `--development` mode now discovers spec and implementation-plan files with either `.md` or `.doc.md` suffixes (`1_*_specs.md` / `1_*_specs.doc.md` and `2_*_implementation-plan.md` / `2_*_implementation-plan.doc.md`), taking the first match so Cursor/Notion-style doc filenames are supported without requiring a single canonical pattern.
- Prepare-release protocol: added instructions for updating reference-style link definitions in `CHANGELOG.md` so version headers remain clickable comparison links on GitHub; retain existing definitions and use the same tag format as CI (e.g. `v1.2.0`).
- Sync-template: project-specific files are now "review for additive updates" instead of "never touch". The agent compares template vs project and may propose adding template improvements while preserving project-specific content; differences are classified as optional additive updates. Step 3 summary, Step 4 apply rules, and PR description wording updated in the sync-template skill/command.
- Auto-tag-release workflow: upgraded `actions/checkout` from v4 to v5; refactored release notes extraction to use a variable and improved clarity (version stripping and awk escaping for CHANGELOG section matching).

- Review workflow: `REVIEW.md` is now the canonical review contract for spec, plan, and code review gates. Claude Code and Codex now default to native review flows against `REVIEW.md`, Cursor review commands explicitly follow the same contract, and the old review-stage protocols are reduced to compatibility wrappers.
- Automated PR review: `pr-review-loop.sh` and the workflow docs now support ordered multi-platform review loops. Review platforms run sequentially, all gating platforms must be clean or skipped before `ready-for-human-review`, and unsupported adapters such as the planned Devin integration are documented explicitly.
- Workflow orchestration is now split into two supporting protocols: `90-batch-orchestrate-work-protocol.md` for portfolio-level discovery, batching, dispatch, and supervision, and `91-orchestrate-work-protocol.md` for single-item orchestration through reviewer/PR/CI readiness. Added `workflow-batch-plan.sh`, `workflow-item-orchestrator` wrappers for Codex/Cursor/Claude, and updated docs so `workflow-orchestrator` / `/run-work` remain the portfolio-wide entrypoint while targeted resume/advance uses the new item-orchestrator path.

### Fixed

- Claude Code orchestrator agents: added the `Agent` tool to `orchestrator`, `item-orchestrator`, and `automated-reviewer-loop` so they can dispatch sub-agents (developer, code-reviewer, etc.) instead of running all stages inline in a single session.
- pr-review-loop.sh: existing-findings path now correctly counts and reports existing soft-suggestion comments; COMMENT_COUNT and SUGGESTION_COUNT were previously undercounting.
- pr-review-loop.sh: fallback date when neither BSD nor GNU date is available now uses epoch (1970-01-01T00:00:00Z) instead of current time, so all comments are considered rather than none.
- sync-template: include `.cursor/agents/` in the Always sync list so `/sync-template` detects and propagates Cursor agent files; aligns with README framework-level propagation paths.

### Added

- Smoke tester agent: added `smoke-tester` to the AGENTS.md workflow commands table and `agent-model-config.md` (tier assignment, per-agent model recommendations, and tool restrictions) to complete documentation coverage for the smoke test stage.
- Cursor subagents: workflow agents (orchestrator, developer, tech-lead, etc.) are now defined in `.cursor/agents/` with per-agent model selection (`fast`, `inherit`, or specific model ID). Orchestration protocol and `agent-model-config.md` document how to execute with Cursor subagents and override models.

## [0.15.0] - 2026-03-10

### Changed

- Workflow status derivation: `workflow-next-action.sh --development` now infers the current workflow stage from repo state (presence of implementation plan file, feature branch) instead of requiring a `**Status**` line in the spec file. When an issue tracker (e.g. Linear) is the source of truth, the spec file's status field is optional. Updated protocols (01-review-specs, 02-generate-implementation-plan, 02-review-implementation-plan, 04-implement-development, 04-review-implemented-development, 90-orchestrate-work) and `integrations/linear.md` to document the tracker-as-source-of-truth model.
- Post-merge cleanup: the agent now updates the related issue in the issue tracker after running the cleanup script. When the merged branch name contains an issue identifier (e.g. `ENG-123`), the skill/command instructs the agent to set that issue to the merged/done state (e.g. Linear → **Merged**). See `docs/workflow/development-workflow/integrations/linear.md` and the post-merge-cleanup skill/command docs.

### Fixed

- Reviewer loop: `pr-review-loop.sh` now checks for existing blocking findings from the bot (e.g. from a review that already ran on PR open) before posting a new trigger. If any exist, it reports `needs_fixes` and exits without triggering so the fixer addresses them first; avoids triggering a new review and ignoring issues already raised. Protocol 92 is now a thin wrapper (scope + follow 90) with no duplicated Step 7/8 procedure.

### Added

- Standalone automated reviewer loop: new protocol `93-automated-reviewer-loop-protocol.md`, Cursor command `/run-reviewer-loop`, Claude Code agent `automated-reviewer-loop`, and Codex skill `workflow-reviewer-loop`. Run the automated reviewer and CI loop for a specific PR (or current branch's PR) until ready for human review or escalated, without full orchestration.
- Post-merge cleanup: `scripts/development-workflow/post-merge-cleanup.sh` plus `/post-merge-cleanup` for Cursor and Claude Code and `post-merge-cleanup` Codex skill. After a development PR is merged and the remote branch deleted, fetches origin, checks out develop, pulls, and deletes the local branch to keep the repo clean.

## [0.14.0] - 2026-03-08

### Fixed

- Implementation plans now explicitly consider project documentation in `docs/`: generate-plan protocol and template require listing doc updates (or "None" with justification), and plan review checks that docs were considered ([#25](https://github.com/lhpaul/ai-dev-framework-template/issues/25)).

### Added

- Workflow helper scripts: `scripts/greptile-review-loop.sh`, `scripts/pr-ci-loop.sh`, `scripts/workflow-next-action.sh`, and `scripts/workflow-lib.sh` so any AI agent or human can deterministically inspect state, poll automated review, and poll CI.

### Changed

- Workflow scripts moved into `scripts/development-workflow/` so template workflow helpers are separate from scripts that downstream repositories add (e.g. `scripts/build.sh`, `scripts/deploy.sh`). All references in docs, AGENTS.md, and skills updated to the new paths.
- AI workflow protocols now treat creator stages as subroutines instead of terminal steps: spec, plan, and implementation runs continue through reviewer gate, PR creation, automated review, and CI until they are actually waiting on a human or escalated.
- Orchestration guidance across Codex skills, Claude agents, Cursor commands, `README.md`, and `AGENTS.md` now defines a persistent control loop with explicit terminal conditions instead of stopping after the next stage finishes.
- Claude agent tool restrictions now allow spec and plan stage agents to use `Bash` when needed for branch creation, commits, pushes, and PR readiness loops.
- Workflow docs now describe the optional GitHub Actions + Codex runtime needed for truly background Greptile fix loops.

## [0.13.0] - 2026-03-02

### Changed

- AI workflow: add a reviewer-agent gate before opening PRs for spec, plan, and implementation stages (so automated PR review tools run only after reviewer approval).
- AI workflow: keep the template's `develop` integration branch + `main` releases, and enforce the reviewer gate before opening PRs.

## [0.12.0] - 2026-03-02

### Added

- `scripts/README.md` documenting the purpose and usage of each helper script in the `scripts/` directory.

## [0.11.0] - 2026-03-02

### Added

- `.codex/skills/` workflow skills for Codex (`workflow-project-setup`, `workflow-spec-writer`, `workflow-spec-reviewer`, `workflow-plan-writer`, `workflow-plan-reviewer`, `workflow-implementer`, `workflow-code-reviewer`, `workflow-orchestrator`) as thin wrappers over the existing protocol documents.
- `.codex/skills/*/agents/openai.yaml` metadata so downstream projects get human-friendly skill names, descriptions, and starter prompts in Codex-compatible UIs.
- `scripts/install-codex-skills.sh` to symlink the repository's Codex skills into the local Codex skill directory.
- `scripts/discover-workflow-state.sh` and `scripts/check-workflow-branch.sh` to give the orchestrator deterministic shell helpers for state discovery and branch/worktree checks.

### Changed

- `AGENTS.md`, `README.md`, and `docs/workflow/development-workflow/README.md` to document Codex skill usage and installation alongside the existing Claude Code and Cursor wrappers.
- `.codex/skills/*/SKILL.md`, `AGENTS.md`, and `README.md` to document recommended model tiers for each Codex skill, with `workflow-orchestrator` positioned as the default `economy` entrypoint.
- `README.md` to include copy-paste starter examples for Claude Code, Cursor, and Codex users testing the orchestration flow in downstream repositories.
- `docs/workflow/development-workflow/README.md` to use "default integration branch" wording where the template previously hard-coded `develop`, so repository-level branch overrides in `AGENTS.md` remain consistent.
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` to document the Codex helper scripts and Codex-specific execution behavior while preserving the shared orchestration protocol.

## [0.10.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` — authoritative release protocol: pre-flight checks, versioning guidance, CHANGELOG update, two-PR approach (main + mandatory develop backport), and CI auto-tagging note.
- `.claude/commands/prepare-release.md` — Claude Code `/prepare-release` command (thin wrapper delegating to the new protocol).
- `.github/workflows/auto-tag-release.yml` — GitHub Actions workflow that automatically creates a git tag and GitHub release when a `release/*` PR is merged into `main`. Extracts the version from the branch name and release notes from `CHANGELOG.md`.

### Changed

- `.cursor/commands/prepare-release.md` — refactored to thin wrapper delegating to `05-prepare-release-protocol.md`; previously had inline steps.
- `docs/workflow/development-workflow/README.md` — Release Process section replaced with a summary and link to the new protocol.
- `AGENTS.md` — Prepare Release row now lists `/prepare-release` for Claude Code (was `—`) and references the protocol in the "Any other tool" column.
- `.claude/skills/sync-template.md` — added `.claude/commands/` to always-sync paths; added `.github/workflows/auto-tag-release.yml` to special-handling paths.

## [0.9.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow`: Added automated reviewer loop to `protocols/91-orchestrate-work-protocol.md` (Step 8). The orchestrator polls for feedback after every push, dispatches the appropriate fixing agent when blocking issues are found, and escalates to human after timeout or 3 fix cycles. Updated Steps 1, 2, 6, and 7 for consistency.
- `docs/workflow/development-workflow/integrations/pr-review-platform.md`: New platform-agnostic integration doc defining what any automated code review tool must provide and what each platform-specific integration doc must specify. Mirrors the `issue-tracker.md` / `linear.md` pattern.
- `docs/workflow/development-workflow/integrations/greptile.md`: Added Greptile-specific Step 8 implementation (bot identity, re-trigger command, review completion detection, inline comment fetch). Generic loop mechanics remain in the protocol; only tool-specific commands live here.

## [0.8.0] - 2026-02-26

### Added

- `docs/workflow/development-workflow`: Added `Spec In Review` and `Plan In Review` stages to the workflow. These stages make PR-open states explicit so the orchestrator agent knows not to re-dispatch when a spec or plan PR is already awaiting human review. Updated `README.md` (stage diagram, issue tracker status list, Agent Roles Summary table) and `protocols/91-orchestrate-work-protocol.md` (mental map, eligibility table, pre-dispatch branch check).

## [0.7.1] - 2026-02-26

### Changed

- Sync-template workflow now stores template source config in `.tmp/template-config.json` (framework-agnostic, gitignored) instead of `.claude/template-config.json`. Single source for Claude Code remains `.claude/skills/sync-template.md`; Cursor uses `.cursor/commands/sync-template.md`.

## [0.7.0] - 2026-02-26

### Added

- `.claude/commands/code-review.md` — new pipeline for automated PR reviews using parallel Claude agents and confidence scoring.

### Changed

- `docs/workflow/development-workflow/protocols/03-review-implementation-protocol.md` — updated implementation review protocol to include Step 2 (Run code-review command) and improved section navigation with an explicit Flow Overview.

## [0.6.1] - 2026-02-26

### Added

- `.claude/agents/smoke-tester.md` — missing Claude Code sub-agent for the smoke test stage; delegates execution to `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` and `docs/testing/README.md`.

## [0.6.0] - 2026-02-25

### Added

- `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` — new agnostic smoke test execution protocol with a two-path decision (run committed spec if it exists, fall back to ad-hoc script), standard output format, pass criteria, and fail handling rules. References the project testing README for all project-specific details.
- `docs/testing/README.md` — template for the project-specific smoke test execution guide: decision tree, committed suite path, ad-hoc fallback scaffold (Node.js + Playwright example), selector/waiting conventions, and troubleshooting sections for projects to fill in during setup.
- Testing Strategy section in `docs/project/3-software-architecture.md` — placeholder documenting the two-tier model (committed automated suite as primary path, ad-hoc scripts as stepping stone), the runbook-to-spec relationship, and setup instructions.

### Changed

- `docs/best-practices/3-testing.md` — testing strategy ownership moved to `docs/project/3-software-architecture.md`; this file now points there and focuses on principles and conventions only. Added two-tier execution model note and link to `docs/testing/README.md` in the Smoke Tests section.
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — Step 5 now includes an explicit e2e spec maintenance instruction (keep committed specs in sync; create one when adding a feature with a runbook). Step 6 pre-commit verification separates unit/integration tests from the e2e suite command. Fast Track path updated accordingly.
- Refactored issue tracker integration protocols to remove redundant field definitions and fallback logic.
- Centralized "current brief" definitions and agent expectations in `docs/workflow/development-workflow/integrations/issue-tracker.md`.
- Updated `Spec Ready`, `Plan Ready`, and `In Development` protocols to delegate issue-tracker-specific logic to the centralized source.

### Fixed

- Updated all Cursor slash commands to use the correct `/` prefix (replacing incorrect `@` prefix) in all documentation, command descriptions, and protocols.

## [0.5.0] - 2026-02-24

### Added

- `.claude/skills/sync-template.md` — Claude Code skill (`/sync-template`) to sync framework updates from the upstream template into a downstream project; compares files, shows a categorized diff, applies changes only after explicit approval, and generates ready-to-use git instructions
- `.cursor/commands/sync-template.md` — Cursor equivalent (`/sync-template`) with identical behaviour
- `.claude/skills/` added to the list of framework-level paths to propagate in `README.md`
- "Maintenance Commands" table in `AGENTS.md` documenting `/sync-template` and `/sync-template`

## [0.4.0] - 2026-02-24

### Refactored

- Moved `docs/workflow/agent-model-config.md` to `docs/workflow/development-workflow/agent-model-config.md` for better repository organization.
- Updated documentation links in `AGENTS.md` and `CHANGELOG.md` to reflect the new path for `agent-model-config.md`.

### Changed

- `docs/workflow/development-workflow/README.md` — Updated the development lifecycle diagram to specify the `develop` branch as the merge target.

## [0.3.0] - 2026-02-24

### Added

- `docs/workflow/development-workflow/agent-model-config.md` — documents model assignments, tool restrictions, and override instructions for all Claude Code agents
- Link to `agent-model-config.md` in the Key Documentation table in `AGENTS.md`

### Changed

- All Claude Code agents (`.claude/agents/`) now declare an explicit `model` field in their YAML frontmatter:
  - `tech-lead` → `claude-opus-4-6` (highest-reasoning stage; architecture decisions benefit from Opus depth)
  - `developer`, `product-manager`, `spec-reviewer`, `implementation-plan-reviewer`, `code-reviewer`, `project-setup` → `claude-sonnet-4-6` (capable and cost-effective for their respective tasks)
  - `orchestrator` → `claude-haiku-4-5-20251001` (mechanical dispatch work; speed and cost matter at orchestration frequency)
- `product-manager`, `spec-reviewer`, and `implementation-plan-reviewer` agents: `Bash` removed from `tools` (least-privilege — these agents only read and write documentation files)
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` Step 5: expanded with explicit parallel subagent dispatch instructions — the orchestrator now uses the Claude Code `Task` tool to launch all eligible agents simultaneously in a single message rather than sequentially
- AI development workflow: clarified the Spec Ready stage is product-focused and technical design details belong in the Plan Ready stage.

### Removed

- Framework sync scripts (manual propagation/backporting only).

## [0.2.0] - 2026-02-24

### Added

- Issue tracker branch naming convention: when an issue tracker is in use, branch slugs are prefixed with the issue identifier (e.g., `feature/ENG-123-user-auth`); without a tracker the existing slug convention applies. Documented in `docs/best-practices/2-version-control.md`, `docs/workflow/development-workflow/README.md`, all three development protocols, and `docs/workflow/development-workflow/integrations/linear.md`

### Changed

- `AGENTS.md` — Git & Branching and CHANGELOG sections updated with project-specific overrides: no `develop` branch (all PRs target `main`), and every merged PR releases a new version
- `docs/best-practices/STACK-SPECIFIC.md` — fixed broken Markdown in placeholder table: replaced nested-bracket links with backtick paths and an inline example for the setup agent

## [0.1.0] - 2026-02-24

### Added

- Staged AI-assisted development workflow (Spec → Plan → Implement → Review → Release) with 8 protocol documents in `docs/workflow/development-workflow/protocols/`
- Claude Code agents for all workflow stages (`.claude/agents/`): `product-manager`, `spec-reviewer`, `tech-lead`, `implementation-plan-reviewer`, `developer`, `code-reviewer`, `orchestrator`, `project-setup`
- Cursor commands and rules (`.cursor/`) mirroring the full Claude Code workflow
- Project setup onboarding agent (`docs/workflow/setup/protocol.md`) — 12-step structured conversation to generate all project-specific documentation
- Project documentation placeholders (`docs/project/`): business domain, repo architecture, software architecture, database model
- General best practices: coding standards (`1-general.md`), version control (`2-version-control.md`), testing (`3-testing.md`)
- `docs/best-practices/STACK-SPECIFIC.md` as a coordinator document — provides stack summary, quick reference, and links to `docs/best-practices/stack/[technology].md` detail files generated by the setup agent per technology area
- Optional integrations for Linear and Greptile (`docs/workflow/development-workflow/integrations/`)
- Spec, implementation plan, and smoke test runbook templates (`docs/workflow/development-workflow/templates/`)
- `AGENTS.md` as the universal AI entry point (AGENTS.md open format), with `CLAUDE.md` and `GEMINI.md` symlinks for Claude Code and Gemini CLI compatibility
- `.claude/settings.json` with pre-approved permissions for common git and fetch operations; `.claude/settings.local.json.example` documenting machine-specific overrides for optional integrations
- `.gitignore` covering local Claude settings, `.env` files, and common system files

[Unreleased]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.42.0...HEAD
[0.42.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.41.0...v0.42.0
[0.41.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.40.0...v0.41.0
[0.40.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.39.0...v0.40.0
[0.39.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.38.0...v0.39.0
[0.38.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.37.1...v0.38.0
[0.37.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.37.0...v0.37.1
[0.37.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.36.3...v0.37.0
[0.36.3]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.36.2...v0.36.3
[0.36.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.36.1...v0.36.2
[0.36.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.36.0...v0.36.1
[0.36.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.35.0...v0.36.0
[0.35.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.34.0...v0.35.0
[0.34.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.33.1...v0.34.0
[0.33.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.33.0...v0.33.1
[0.33.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.32.0...v0.33.0
[0.32.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.31.0...v0.32.0
[0.31.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.30.2...v0.31.0
[0.30.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.30.1...v0.30.2
[0.30.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.30.0...v0.30.1
[0.30.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.29.1...v0.30.0
[0.29.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.29.0...v0.29.1
[0.29.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.28.4...v0.29.0
[0.28.4]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.28.3...v0.28.4
[0.28.3]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.28.2...v0.28.3
[0.28.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.28.1...v0.28.2
[0.28.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.28.0...v0.28.1
[0.28.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.27.4...v0.28.0
[0.27.4]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.27.3...v0.27.4
[0.27.3]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.27.2...v0.27.3
[0.27.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.27.1...v0.27.2
[0.27.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.27.0...v0.27.1
[0.27.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.26.1...v0.27.0
[0.26.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.26.0...v0.26.1
[0.26.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.25.1...v0.26.0
[0.25.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.25.0...v0.25.1
[0.25.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.24.1...v0.25.0
[0.24.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.24.0...v0.24.1
[0.24.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.2...v0.24.0
[0.23.2]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.1...v0.23.2
[0.23.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.23.0...v0.23.1
[0.23.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.22.0...v0.23.0
[0.22.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.21.0...v0.22.0
[0.21.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.20.0...v0.21.0
[0.20.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.19.0...v0.20.0
[0.19.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.18.1...v0.19.0
[0.18.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.18.0...v0.18.1
[0.18.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.17.0...v0.18.0
[0.17.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.16.0...v0.17.0
[0.16.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.15.0...v0.16.0
[0.15.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.14.0...v0.15.0
[0.14.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.13.0...v0.14.0
[0.13.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.7.1...v0.8.0
[0.7.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/lhpaul/ai-dev-framework-template/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/lhpaul/ai-dev-framework-template/releases/tag/v0.1.0
