#!/usr/bin/env bash
# Helper-gated readiness labels (issue #1408).
#
# Readiness labels (`ready-for-human-review`, `ready-for-regression`) are input
# to the merge gates (`run-epic-delegated-gate.sh`, `batch-merge.sh`,
# `workflow-next-action.sh`), not cosmetics. Delegated runners have applied them
# by hand before the ready-phase reviewer finished, asserting readiness no
# reviewer verdict supports (PR #2097 on a downstream repo; PR #77 on another).
# This script is the only sanctioned way to apply them: it refuses unless every
# configured ready-phase reviewer check run is `completed` for the *current* head
# SHA, the reviewer posted no blocking findings on that SHA, and no
# non-reviewer check is still pending or failing.
#
# An absent reviewer check run is treated as NOT clean — Cursor "Restrict
# Access" can make Bugbot refuse to run, and "no check run" must never read as
# "reviewer clean". The same applies to a `neutral` check run that accompanies a
# Bugbot usage/spend-limit notice: the reviewer never actually reviewed.
#
# The reviewer leg applies to implementation branches only (`feature/*`,
# `fix/*`, `refactor/*`, `backport/hotfix/*`) — the same boundary Protocol 91
# draws for `IS_IMPLEMENTATION_PR` and for its Step 7b label derivation table.
# Ready-phase reviewers are not dispatched on `spec/*`,
# `implementation-plan/*`, graduation (`develop-<slug>`), `release/*`, or
# `hotfix/*` PRs, so no check run can exist for them; gating on one would
# refuse every doc-stage, release, and hotfix PR. `hotfix/*` is exempt the
# same way `release/*` is because pr-review-loop.sh's `_check_release_pr_guard`
# skips the reviewer loop for `release/*` AND `hotfix/*` head branches — no
# reviewer check is ever dispatched on a hotfix, so requiring one would
# permanently refuse both readiness labels `reviewer-check-absent`. Hotfix PRs
# still get what release PRs get: the CI leg applies unchanged (PR #1818
# finding 1, round 7). The CI leg still applies on those branches.
#
# `ready-for-regression` blocks on failing non-reviewer checks but permits
# pending ones: that label is what *starts* the configured regression workflow,
# so requiring green CI before it is applied would make Step 7b depend on checks
# the label itself triggers. `ready-for-human-review` — the merge-gate input —
# blocks on pending as well.
#
# Findings are read from `pulls/N/comments` (inline review comments) and
# `pulls/N/reviews`, never from issue comments: Bugbot reports through a
# `COMMENTED` PR review with inline comments, the same surface
# `run_bugbot_review()` in pr-review-loop.sh reads.
#
# Issue comments are read for exactly one purpose: when a reviewer check run
# finishes `neutral`, `cancelled`, or `skipped`, Bugbot's own usage/spend-limit
# and restricted-access notices arrive as a `cursor[bot]` issue comment for that
# head. A bare `neutral` therefore reads as clean only when no such notice
# exists — otherwise the verdict is `refused` / `reviewer-unavailable`. Same
# rule as `run_bugbot_review()` (pr-review-loop.sh ~3838).
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'USAGE'
Usage: apply-readiness-labels.sh --pr <number> [--repo <owner/repo>] \
  --label <ready-for-human-review|ready-for-regression> [--json]

Refuses to apply the label unless every configured ready-phase reviewer check
run is `completed` for the current head SHA, the reviewer posted no blocking
findings on that SHA, and no other check is pending or failing. A `neutral`
reviewer check run with a Bugbot usage/spend-limit notice is refused as well:
the reviewer never reviewed.

Prints RESULT=<labeled|refused|escalate> and REASON=<slug>.
Exit codes: 0 labeled, 1 refused, 2 escalate (state could not be read).
Refusal reasons: reviewer-check-absent, reviewer-check-not-completed,
reviewer-unavailable, reviewer-check-name-unresolved,
reviewer-evidence-unreadable,
reviewer-check-unknown-conclusion, reviewer-policy-empty, blocking-findings,
reviewer-state-changed, ci-pending, ci-failing, head-changed-before-apply.
Escalation reasons:
head-revalidate-failed, head-changed-after-apply, ready-config-unreadable,
base-config-unreadable, revalidation-unreadable.
The ready-phase reviewer list is read from the PR head's own
.ai-dev-workflow.yaml; an unreadable head configuration escalates (fail-closed)
rather than falling back to this checkout's configuration. The required
reviewer set is the BASE branch policy — the loop dispatches ready-phase
platforms from the base configuration, so head-only additions are never
required, but a head cannot waive a base-configured reviewer. The base policy
is resolved with local review overrides applied (the same effective policy
the loop dispatches); an absent .ai-dev-workflow.local.yaml falls back to the
shared policy. hotfix/* branches are exempt from the reviewer leg exactly as
release/* branches are — the reviewer loop is never dispatched on them — but
the CI leg still applies.
USAGE
}

pr_number=""
repo=""
label=""
json_output="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --pr\n' >&2; exit 2; }
      [ -z "$pr_number" ] || { printf 'ERROR: repeated option: --pr\n' >&2; exit 2; }
      pr_number="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --repo\n' >&2; exit 2; }
      [ -z "$repo" ] || { printf 'ERROR: repeated option: --repo\n' >&2; exit 2; }
      repo="$2"
      shift 2
      ;;
    --label)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --label\n' >&2; exit 2; }
      [ -z "$label" ] || { printf 'ERROR: repeated option: --label\n' >&2; exit 2; }
      label="$2"
      shift 2
      ;;
    --json) json_output="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$pr_number" ] || [ -z "$label" ]; then
  usage >&2
  exit 2
fi
case "$label" in
  ready-for-human-review|ready-for-regression) ;;
  *) printf 'ERROR: --label must be ready-for-human-review or ready-for-regression\n' >&2; exit 2 ;;
esac
case "$pr_number" in
  ''|*[!0-9]*) printf 'ERROR: --pr must be a number\n' >&2; exit 2 ;;
esac

require_gh
cd_workflow_repo_root
[ -n "$repo" ] || repo="$(repo_slug)"

# Readiness gate verdict.
result="refused"
reason=""
head_sha=""
reviewer_report=""
blocking_count=0
pending_count=0
failing_count=0

# configured_ready_reviewer_platforms — the platforms whose check run gates
# readiness. Mirrors item-completion-self-check.sh's configured_review_platforms:
# the repo-local override file wins when it declares the list.
configured_ready_reviewer_platforms() {
  local config_file
  config_file="$(workflow_effective_config_file 2>/dev/null || workflow_config_file)"
  if [ "$config_file" = "$(workflow_config_file)" ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_on_ready_github "$config_file"
  else
    workflow_config_review_on_ready_github "$config_file"
  fi
}

# pr_head_config_ready_platforms <repo> <sha> — `review.on_ready.github` read
# from the PR's own head commit, not this checkout. The target PR may itself
# modify `.ai-dev-workflow.yaml` (drop the configured ready reviewer, add
# one); reading the local file would gate the label on a list the PR's own
# configuration no longer declares. Fail closed: a fetch/parse failure
# escalates rather than falling back to the local checkout silently — the
# reviewer set is the gate, so an unreadable one is an unreadable gate.
# When called for the BASE sha (loop_dispatched_base=1), the effective policy
# is resolved the same way pr-review-loop.sh resolves its base snapshot
# (WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 on workflow_config_review_platforms,
# pr-review-loop.sh ~12423-12449): a local `.ai-dev-workflow.local.yaml` that
# declares `review.on_ready.github` REPLACES the shared list, and the loop
# dispatches that replaced list — so this helper must gate on it too, or a
# local ronda-over-bugbot override would have the helper wait forever for a
# Bugbot check the loop never runs (PR #1818 finding 2, round 7). The override
# file is gitignored and absent from agent worktrees; an absent file falls
# back to the shared policy exactly as the loop itself does in a worktree
# (workflow_config_review_local_list_if_declared returns 1 when the local
# file is absent) — never fail, never resolve a different policy than the
# loop dispatched.
pr_head_config_ready_platforms() {
  local repo_arg="$1" sha_arg="$2"
  local content_b64 config_body head_config_file rc
  content_b64="$(gh api "repos/$repo_arg/contents/.ai-dev-workflow.yaml?ref=$sha_arg" \
      --jq '.content // ""' 2>/dev/null)" || return 1
  [ -n "$content_b64" ] || return 1
  config_body="$(printf '%s\n' "$content_b64" | tr -d '\n' | base64 -d 2>/dev/null)" || return 1
  [ -n "$config_body" ] || return 1
  head_config_file="$(mktemp)" || return 1
  printf '%s\n' "$config_body" >"$head_config_file"
  if [ "${loop_dispatched_base:-0}" = "1" ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_on_ready_github "$head_config_file"
  else
    workflow_config_review_on_ready_github "$head_config_file"
  fi
  rc=$?
  rm -f "$head_config_file"
  return "$rc"
}

# reviewer_check_name_for_platform <platform> — the check-run name a ready-phase
# reviewer publishes. Same mapping configured_reviewer_check_names_json applies
# (workflow-lib.sh), narrowed to the ready-phase list and kept separate so that
# helper's existing behavior is left untouched (#1559 audits its consumers).
reviewer_check_name_for_platform() {
  case "$1" in
    haystack) printf '%s\n' "${HAYSTACK_CHECK_NAME:-Haystack / Review}" ;;
    bugbot) printf '%s\n' "${BUGBOT_CHECK_NAME:-Cursor Bugbot}" ;;
    ronda) printf '%s\n' "${RONDA_CHECK_NAME:-Ronda review}" ;;
    *) printf '\n' ;;
  esac
}

# comment_only_reviewer_verdict <platform> <bot_login> — the verdict path for
# ready-phase reviewers that publish NO check run (codex-github, coderabbit,
# claude-code-action, copilot, devin, greptile — every documented platform
# besides haystack/bugbot/ronda). Rounds 11-13 routed every readiness-label
# producer through this helper, so refusing those platforms
# `reviewer-check-name-unresolved` was a permanent deadlock: a repository
# configured with codex-github (this PR's own ready-phase reviewer) could
# never reach either readiness label even though pr-review-loop.sh fully
# supports the platform (PR #1818 thread PRRT_kwDORWAxaM6m1Dec, round 14).
#
# Evidence semantics mirror the loop's comment-only readers
# (run_codex_github_review / run_devin_review / run_coderabbit_review): the
# "reviewer ran and was clean" verdict is the latest PR review the platform
# bot submitted against the CURRENT head SHA. Fail closed — no bot review on
# the head refuses `reviewer-check-absent`, never a silent pass. Findings are
# then counted by the shared count_reviewer_blocking_findings, time-bounded
# to that review's submitted_at (the comment-only analogue of the check run's
# started_at). Sets reviewer_started_at and scan_blocking_count; refuses or
# escalates directly on failure.
#
# Round 15 (PR #1818 thread PRRT_kwDORWAxaM6m1pF_): when no review exists,
# platform completion adapters run first — codex-github publishes its clean
# result as a SHA-pinned root PR comment (issue comment) and Greptile
# completes by reacting to its trigger comment, so a `pulls/N/reviews`-only
# read stayed `reviewer-check-absent` forever even after the loop returned
# clean. The adapters accept exactly the evidence surfaces those loop
# implementations accept (see comment_only_completion_evidence below); fail
# closed still applies when none is present.
#
# Round 15 (PR #1818 thread PRRT_kwDORWAxaM6m1pGF): the inline-comment scan
# bound is the EARLIEST of the review's submitted_at and the earliest
# created_at of that review's OWN inline comments (matched by
# pull_request_review_id) — inline comments created while the review was
# pending have created_at < submitted_at, so a submitted_at-only bound
# excluded the review's own findings. The review-body scan keeps the
# submitted_at bound, and inline comments from PREVIOUS reviews carry the
# previous review's id, so earlier-run findings stay excluded.
comment_only_reviewer_verdict() {
  local platform_arg="$1" bot_login_arg="$2"
  local reviews_json latest_review
  # Round 17 (PRRT_kwDORWAxaM6m260s): the coderabbit-cli / local-ai-reviewer
  # ledger adapter may have ALREADY resolved this platform's verdict before
  # this function was entered (the loop's persisted reviewer_loop_history.v1
  # ledger is the platform's one current-head-pinned durable evidence
  # surface). Its outcomes short-circuit the review fetch entirely.
  if [ "${_adapter_run_head_sha:-}" = "$head_sha" ] && [ "${_adapter_run_platform:-}" = "$platform_arg" ]; then
    if [ "${_adapter_ledger_clean:-0}" = "1" ]; then
      reviewer_started_at="${_adapter_ledger_started_at:-}"
      count_reviewer_blocking_findings "$bot_login_arg" "$reviewer_started_at" "$reviewer_started_at" "$platform_arg"
      return
    fi
    result="refused"
    reason="${_adapter_refusal_reason:-reviewer-evidence-unreadable}"
    reviewer_report="$platform_arg"
    refuse "$reason"
  fi
  if ! reviews_json="$(gh api "repos/$repo/pulls/$pr_number/reviews" --paginate --slurp 2>/dev/null)"; then
    escalate review-fetch-failed
  fi
  if ! latest_review="$(printf '%s\n' "${reviews_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" '
        [ .[]?[]
          | select(
              (((.user.login // "") == $bot) or ((.user.login // "") == ($bot | sub("\\[bot\\]$"; ""))) or ((.user.login // "") == ($bot + "[bot]")))
              and ((.commit_id // .commitId // "") == $sha)
            )
        ]
        | sort_by(.submitted_at // "")
        | last
      ' 2>/dev/null)"; then
    escalate review-parse-failed
  fi
  if [ -z "$latest_review" ] || [ "$latest_review" = "null" ]; then
    # Round 16: the completion adapters return 0 (clean evidence — findings
    # are then counted through the shared scan), 1 (no readable evidence —
    # fail closed below), or 2 (blocking evidence on the current head —
    # refuse blocking-findings with the needs-fixes annotation).
    _adapter_rc=0
    comment_only_completion_evidence "$platform_arg" "$bot_login_arg" || _adapter_rc=$?
    if [ "$_adapter_rc" -eq 0 ]; then
      count_reviewer_blocking_findings "$bot_login_arg" "$reviewer_started_at" "$reviewer_started_at" "$platform_arg"
      return
    fi
    if [ "$_adapter_rc" -eq 2 ]; then
      annotate_needs_fixes_best_effort
      result="refused"
      reason="blocking-findings"
      blocking_count=1
      refuse "blocking-findings"
    fi
    result="refused"
    reason="reviewer-check-absent"
    reviewer_report="${platform_arg}:review"
    refuse "reviewer-check-absent"
  fi
  reviewer_started_at="$(printf '%s\n' "$latest_review" | jq -r '.submitted_at // ""' 2>/dev/null)" || escalate review-parse-failed
  # Inline bound (thread PRRT_kwDORWAxaM6m1pGF): earliest of submitted_at and
  # the review's own inline comments' earliest created_at. Comments fetch
  # failures escalate fail-closed — an unreadable finding surface is an
  # unreadable verdict.
  local review_id comments_json inline_earliest inline_bound
  review_id="$(printf '%s\n' "$latest_review" | jq -r '.id // 0' 2>/dev/null)" || escalate review-parse-failed
  if ! comments_json="$(gh api "repos/$repo/pulls/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate review-comment-fetch-failed
  fi
  inline_earliest="$(printf '%s\n' "${comments_json:-[]}" | jq -r --argjson rid "$review_id" '
        [ .[]?[]
          | select(((.pull_request_review_id // 0) == $rid))
          | (.created_at // "")
        ]
        | min // empty
      ' 2>/dev/null)" || inline_earliest=""
  inline_bound="$reviewer_started_at"
  if [ -n "$inline_earliest" ] && [ "$inline_earliest" \< "$reviewer_started_at" ]; then
    inline_bound="$inline_earliest"
  fi
  count_reviewer_blocking_findings "$bot_login_arg" "$reviewer_started_at" "$inline_bound" "$platform_arg"
}

# codex_root_comment_body_is_approved <body> — round 17 (PRRT_kwDORWAxaM6m2604).
# The canonical Codex clean classifier, replicated EXACTLY (with provenance)
# from codex-github-reviewer.sh rather than invented here: the loop script
# sources codex-github-evidence-lib.sh at line 93 with no library-mode gate
# (its $0 argv parsing would break under a `source`), so the
# CODEX_APPROVED_TEMPLATES / codex_response_is_approved definitions are
# reproduced byte-for-byte below. Provenance: codex-github-reviewer.sh
# CODEX_APPROVED_TEMPLATES (~line 823), codex_response_is_approved (~line
# 842), CODEX_BLOCKING_PATTERN (~lines 475-521),
# codex_normalize_whitespace (~line 725), codex_strip_quoted_spans /
# codex_strip_not_only_idiom / codex_response_is_blocking (~lines 640-685).
# DO NOT simplify this into a substring test: the classifier's guarantee is
# that the ENTIRE body, whitespace-normalized, reproduces the approved
# template exactly — a clean sentence plus injected blocking text
# ("Must fix ...") matches the sentence but never the whole-body template,
# and blocking markers are checked FIRST so a disguised rejection always
# loses.
CODEX_BLOCKING_PATTERN='(changes[[:space:]]+requested|blocking[[:space:]]+issues?[[:space:]]*:|blocking[[:space:]]+finding|blocking:|must[[:space:]]+fix|action[[:space:]]+required|required:|❌)'
CODEX_NEGATION_WORDS='(not|isn.t|is[[:space:]]+not|are[[:space:]]+not|aren.t|was[[:space:]]+not|wasn.t|were[[:space:]]+not|weren.t|cannot|can.t|could[[:space:]]+not|couldn.t|will[[:space:]]+not|won.t|would[[:space:]]+not|wouldn.t|does[[:space:]]+not|doesn.t|do[[:space:]]+not|don.t|has[[:space:]]+not|hasn.t|have[[:space:]]+not|haven.t|had[[:space:]]+not|hadn.t|should[[:space:]]+not|shouldn.t|must[[:space:]]+not|mustn.t|never|unable[[:space:]]+to)'
CODEX_MERGE_REFUSAL_PATTERN="${CODEX_NEGATION_WORDS}[^.!?;,]*(be[[:space:]]+)?merged?"
CODEX_BLOCKING_PATTERN="${CODEX_BLOCKING_PATTERN%)}|${CODEX_MERGE_REFUSAL_PATTERN})"

codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}

codex_strip_not_only_idiom() {
  local body="$1"
  sed -E 's/[Nn][Oo][Tt][[:space:]]+[Oo][Nn][Ll][Yy]//g' <<< "$body"
}

# Strip quoted spans (straight double-quotes, single-quotes, and backtick
# pairs; blockquote lines deleted first), replicated EXACTLY from
# codex-github-reviewer.sh's codex_strip_quoted_spans — the blocking
# classifier runs on the stripped body so quoted example text does not
# produce a blocking false positive. Provenance: codex-github-reviewer.sh
# ~lines 594-640.
codex_strip_quoted_spans() {
  local body="$1"
  local sq="'"
  local no_blockquotes
  no_blockquotes=$(sed -E '/^[[:space:]]*>/d' <<< "$body")
  local nl_placeholder=$'\x01'
  local flattened stripped
  flattened=$(printf '%s' "$no_blockquotes" | tr '\n' "$nl_placeholder")
  stripped=$(sed -E "s/\"[^\"]*\"//g; s/\`[^\`]*\`//g; s/(^|[[:space:]]|${nl_placeholder})${sq}[^${sq}]*${sq}([[:space:].,;:!?]|${nl_placeholder}|\$)/\\1\\2/g" <<< "$flattened")
  printf '%s' "$stripped" | tr "$nl_placeholder" '\n'
}

codex_response_is_blocking() {
  local body="$1" normalized_body
  normalized_body=$(codex_strip_not_only_idiom "$(codex_strip_quoted_spans "$body")")
  grep -qiE "$CODEX_BLOCKING_PATTERN" <<< "$normalized_body"
}

CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. [^*`[:cntrl:]]{1,40} \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)

codex_response_is_approved() {
  local body="$1" normalized template
  normalized=$(codex_normalize_whitespace "$body")
  for template in "${CODEX_APPROVED_TEMPLATES[@]}"; do
    if grep -qE "$template" <<< "$normalized"; then
      return 0
    fi
  done
  return 1
}

# Blocking-first canonical order (codex-github-reviewer.sh's tiering): a
# blocking marker always wins over an approval, and approval requires the
# whole-body exact-template match.
codex_root_comment_body_is_approved() {
  local body="$1"
  [ -n "$body" ] || return 1
  if codex_response_is_blocking "$body"; then
    return 1
  fi
  codex_response_is_approved "$body"
}

# claude_action_run_log_shows_execution <run_id> — round 17
# (PRRT_kwDORWAxaM6m260z). Mirrors claude-code-action-reviewer.sh's
# verify_claude_code_action_run_log + classify_claude_code_action_log
# acceptance (the call at its line ~413-417): a successful Actions run is
# not proof Claude actually reviewed — claude-code-action exits
# successfully on a no-op (no prompt/trigger). The run log is fetched and
# classified with the same patterns: "noop" (1) and "unknown" (2) both
# fail closed here (return 1); only an explicit execution marker
# ("Trigger result: true" / a context prompt, with no NO PROMPT marker)
# passes. A log-fetch failure also returns 1 (no positive evidence — fail
# closed, never a pass), mirroring verify_claude_code_action_run_log's
# UNAVAILABLE verdict.
claude_action_run_log_shows_execution() {
  local run_id_arg="$1"
  local run_log run_log_status
  run_log="$(mktemp)" || return 1
  run_log_status=0
  # Same fetch as verify_claude_code_action_run_log (claude-code-action-
  # reviewer.sh): `gh run view --log`, not the raw logs-download API (which
  # returns a zip). A fetch failure means no positive execution evidence —
  # fail closed (its UNAVAILABLE verdict), never a pass.
  gh run view "$run_id_arg" --repo "$repo" --log >"$run_log" 2>/dev/null || run_log_status=$?
  if [ "$run_log_status" -ne 0 ]; then
    rm -f "$run_log"
    return 1
  fi
  # classify_claude_code_action_log, verbatim patterns.
  if grep -Eqi 'Context prompt: NO PROMPT|Trigger result: false|No trigger found, skipping remaining steps|"prompt": ""' "$run_log"; then
    rm -f "$run_log"
    return 1
  fi
  if grep -Eqi 'Trigger result: true|Context prompt: .+' "$run_log" \
      && ! grep -Eqi 'Context prompt: NO PROMPT' "$run_log"; then
    rm -f "$run_log"
    return 0
  fi
  rm -f "$run_log"
  return 1
}

# coderabbit_cli_local_ai_ledger_verdict <platform> — round 17
# (PRRT_kwDORWAxaM6m260s). The loop's DURABLE current-head evidence for the
# two pure-CLI ready-phase reviewers (coderabbit-cli, local-ai-reviewer):
# their verdicts persist in the reviewer_loop_history.v1 ledger the loop
# posts as (part of) the "### Automated Reviewer Loop Summary" issue
# comment (workflow-lib.sh's shared render/extract helpers —
# REVIEWER_LOOP_HISTORY_MARKER "<!-- reviewer-loop-history:v1 -->",
# reviewer_loop_history_extract_latest_json,
# reviewer_loop_history_select_latest_summary_record). Each entry's
# platform_results[] carries {platform, result} and the SAME entry's
# reviewed_heads[] carries that platform's reviewed_head — exactly the
# head-pinned per-platform verdict pr-review-loop.sh's own
# reviewer_loop_platform_clean_for_head (#1692) replays clean verdicts
# from, so this is the loop's canonical current-head-pinned surface, not
# a new one. A current-head clean entry (newest for the platform, result
# "clean", reviewed_head == current head) sets _adapter_ledger_clean=1 and
# the entry's updated_at as the findings-window start; anything else —
# absent evidence, a verdict on another head, a not-clean verdict, or an
# unreadable ledger — refuses. Never a silent pass. The bot_login for both
# platforms is empty (workflow-lib.sh bot_login_for_platform), so the
# findings scan for a clean ledger verdict finds nothing (that is the
# round-16 semantics: these reviewers post no GitHub findings surface).
coderabbit_cli_local_ai_ledger_verdict() {
  local platform_arg="$1"
  _adapter_run_head_sha="$head_sha"
  _adapter_run_platform="$platform_arg"
  _adapter_ledger_clean=0
  _adapter_refusal_reason="reviewer-evidence-unreadable"
  _adapter_ledger_started_at=""
  local summary_record ledger_body ledger_started_at payload verdict outcome verdict_head
  local invoker_login
  # Round 18 (thread PRRT_kwDORWAxaM6m36Wn): the marker strings are public,
  # so body-marker selection alone lets ANY PR participant forge a
  # reviewer_loop_history.v1 payload recording `clean` for the current head
  # and gate a merge-label with no reviewer run. The accepted ledger
  # comment must come from a TRUSTED actor: the login pr-review-loop.sh
  # itself posts the summary under (gh pr comment / the comments PATCH run
  # with this same gh token — `gh api user` is that login) OR a comment
  # whose author_association GitHub reports as OWNER / MEMBER /
  # COLLABORATOR (the repo's write-trust domain; the loop can be run by any
  # collaborator, so the trust check must not pin only THIS invoker's
  # login). The author filter lives in THIS caller's jq, not in
  # workflow-lib.sh's shared reviewer_loop_history_select_latest_summary_
  # record — that helper's other callers (pr-review-loop.sh's own cycle
  # counting and label restore) operate inside the loop's own trust domain
  # where the comment was posted by the loop itself, so their semantics
  # stay unchanged. Fail closed: an unreadable invoker lookup or a fetch/
  # parse failure with no trusted comment refuses (absent), never passes.
  if ! invoker_login="$(gh api user --jq '.login // ""' 2>/dev/null)"; then
    invoker_login=""
  fi
  if ! summary_record="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate --slurp 2>/dev/null | jq -c --arg invoker "$invoker_login" '
        [ .[]?[]
          | select(
              (.body // "" | contains("### Automated Reviewer Loop Summary")) and
              (.body // "" | contains("*Posted automatically by `pr-review-loop.sh`.*"))
            )
          | select(
              (((.user.login // "") != "") and ((.user.login // "") == $invoker))
              or (((.author_association // "") == "OWNER")
                  or ((.author_association // "") == "MEMBER")
                  or ((.author_association // "") == "COLLABORATOR"))
            )
        ]
        | sort_by(.created_at)
        | last
      ' 2>/dev/null)" || [ -z "$summary_record" ] || [ "$summary_record" = "null" ] || [ "$summary_record" = "false" ]; then
    # No TRUSTED summary comment (only forged/untrusted bodies, or none at
    # all), or a fetch/parse failure: absent evidence — the generic absent
    # refusal, matching the comment-only verdict path. An untrusted
    # author's ledger is never read, so a forged newer comment cannot
    # shadow or spoof a verdict either.
    _adapter_refusal_reason="reviewer-check-absent"
    return
  fi
  ledger_started_at="$(printf '%s\n' "$summary_record" | jq -r '.created_at // ""' 2>/dev/null)"
  ledger_body="$(printf '%s\n' "$summary_record" | jq -r '.body // ""' 2>/dev/null)"
  payload="$(printf '%s\n' "$ledger_body" | reviewer_loop_history_extract_latest_json 2>/dev/null)"
  [ -n "$payload" ] || { _adapter_refusal_reason="reviewer-check-absent"; return; }
  if ! printf '%s\n' "$payload" | jq -e --arg schema "reviewer_loop_history.v1" \
        '.schema == $schema and ((.entries | type) == "array")' >/dev/null 2>&1; then
    _adapter_refusal_reason="reviewer-evidence-unreadable"
    return
  fi
  verdict="$(printf '%s\n' "$payload" | jq -c --arg platform "$platform_arg" '
      . as $root
      | (.entries // []) as $entries
      | [ $entries[]
          | . as $entry
          | ((.platform_results // [])[]
             | select(.platform == $platform)
             | {outcome: (.result // "unknown"),
                head_sha: (
                  ($entry.reviewed_heads // [])
                  | map(select(.platform == $platform))
                  | last
                  | .reviewed_head // ""
                ),
                iteration: ($entry.iteration // 0)})
        ] as $verdicts
      | if ($verdicts | length) > 0 then
          ($verdicts | sort_by(.iteration) | last)
        else
          {outcome: "not_yet_run", head_sha: "", iteration: 0}
        end
      ' 2>/dev/null)" || verdict=""
  [ -n "$verdict" ] && [ "$verdict" != "null" ] || { _adapter_refusal_reason="reviewer-evidence-unreadable"; return; }
  outcome="$(printf '%s\n' "$verdict" | jq -r '.outcome // "unknown"' 2>/dev/null)"
  verdict_head="$(printf '%s\n' "$verdict" | jq -r '.head_sha // ""' 2>/dev/null)"
  case "$outcome" in
    clean) ;;
    not_yet_run|unknown) _adapter_refusal_reason="reviewer-check-absent"; return ;;
    *) _adapter_refusal_reason="reviewer-evidence-unreadable"; return ;;
  esac
  if [ -z "$verdict_head" ] || [ "$verdict_head" != "$head_sha" ]; then
    # Clean, but on another head (or no head recorded) — stale evidence.
    _adapter_refusal_reason="reviewer-check-absent"
    return
  fi
  _adapter_ledger_started_at="${ledger_started_at:-}"
  _adapter_ledger_clean=1
}

# comment_only_completion_evidence <platform> <bot_login> — round 15 (PR
# #1818 thread PRRT_kwDORWAxaM6m1pF_): non-review completion evidence for
# hosted comment-only reviewers, mirroring exactly what the loop's own
# platform readers accept. Round 16 (threads PRRT_kwDORWAxaM6m2Os_,
# PRRT_kwDORWAxaM6m2OtD, PRRT_kwDORWAxaM6m2OtK) tightened the codex-github
# adapter and added three more:
#   - codex-github: a root PR comment (issue comment) by the bot whose body
#     is SHA-pinned terminal evidence — a backticked "Reviewed commit"
#     marker whose token pins the current head (offset-zero prefix in
#     either direction, the same prefix classification codex_marker_classify
#     accepts) AND the approved clean sentence ("Didn't find any major
#     issues", the approved-template verdict sentence
#     codex-github-reviewer.sh matches). A SHA-pinned body WITHOUT the clean
#     sentence is the loop classifier's unrecognized/needs-fixes verdict
#     (every other terminal body safe-fails) — returned as rc 2, never a
#     pass (round-15's OR over the two markers let a "Codex Review: Needs
#     fixes ... Reviewed commit: <HEAD>" body pass clean).
#   - greptile: a `+1` reaction by the bot on the latest "@greptile review"
#     trigger comment — run_greptile_review's completion signal.
#   - claude-code-action: the loop's claude-code-action-reviewer.sh accepts
#     a successful GitHub Actions run (workflow_dispatch, the configured
#     workflow file, run-name "PR #<n>"-scoped when any candidate carries
#     one, newest by created_at) with no CHANGES_REQUESTED review from the
#     bot — the findings leg is the shared review scan the caller runs.
#   - pr-agent: run_pr_agent_review's completion surface — the latest issue
#     comment by the bot whose body contains "PR Reviewer Guide" and the
#     head SHA, classified by the same label rules _pr_agent_classify
#     applies ("No major issues detected" clean; hard-blocker focus-area
#     labels needs-fixes; unreadable section needs-fixes).
#   - coderabbit-cli / local-ai-reviewer: both reviewer scripts are pure-CLI
#     readers (coderabbit-cli-reviewer.sh and local-ai-reviewer.sh make no
#     `gh api` write call — only `gh pr view` / `gh pr diff`), so neither
#     leaves a review/comment/issue-comment surface of its own; since round
#     17 (PRRT_kwDORWAxaM6m260s) their ONE readable durable surface — the
#     loop's reviewer_loop_history.v1 ledger — IS consumed: a
#     current-head-pinned clean verdict from that ledger (the same
#     #1692-per-head replay evidence pr-review-loop.sh trusts) passes,
#     and absent/stale/not-clean/unreadable ledger evidence still refuses
#     fail-closed (reviewer-check-absent / reviewer-evidence-unreadable).
# On a clean match: sets reviewer_started_at (the evidence's timestamp —
# the comment's created_at / the trigger comment's created_at / the run's
# created_at, the same window start the loop scans findings from) and
# returns 0. Returns 1 when the platform has no readable evidence (caller
# refuses reviewer-check-absent — fail closed for genuinely absent
# evidence). Returns 2 when the platform's own readable evidence is a
# BLOCKING verdict for the current head (caller refuses blocking-findings
# with the needs-fixes annotation). Fetch/parse failures escalate
# fail-closed; a reactions read failure returns 1 (refusal), never a pass.
comment_only_completion_evidence() {
  local platform_arg="$1" bot_login_arg="$2"
  local issue_comments_json entries entry body created token trigger reactions_json
  case "$platform_arg" in
    codex-github|greptile|claude-code-action|pr-agent) ;;
    *) return 1 ;;
  esac
  if ! issue_comments_json="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate issue-comment-fetch-failed
  fi
  case "$platform_arg" in
    codex-github)
      if ! entries="$(printf '%s\n' "${issue_comments_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg plain "${bot_login_arg%\[bot\]}" '
            [ .[]?[]
              | select(
                  (((.user.login // "") == $bot) or ((.user.login // "") == $plain) or ((.user.login // "") == ($bot + "[bot]")))
                )
              | {created_at: (.created_at // ""), body: (.body // "")}
            ]
            | sort_by(.created_at)
            | reverse
            | .[]
          ' 2>/dev/null)"; then
        escalate issue-comment-parse-failed
      fi
      while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        body="$(printf '%s\n' "$entry" | jq -r '.body // ""' 2>/dev/null)"
        created="$(printf '%s\n' "$entry" | jq -r '.created_at // ""' 2>/dev/null)"
        # Only SHA-pinned terminal evidence ("Reviewed commit" + backticked
        # token naming the current head) participates; offset-zero prefix in
        # either direction, the same prefix classification
        # codex_marker_classify accepts.
        case "$body" in
          *"Reviewed commit"*) ;;
          *) continue ;;
        esac
        # shellcheck disable=SC2016  # single quotes deliberate: the sed program must not expand
        token="$(printf '%s\n' "$body" | sed -n 's/.*Reviewed commit:\{0,1\}[^`]*`\([^`]*\)`.*/\1/p' | tail -n1)"
        [ -n "$token" ] || continue
        if [ "${head_sha#"$token"}" != "$head_sha" ] || [ "${token#"$head_sha"}" != "$token" ]; then
          # SHA-pinned terminal evidence — the verdict is classified with
          # codex-github-reviewer.sh's CANONICAL classifier, not a substring
          # test (PRRT_kwDORWAxaM6m2604): a body carrying the clean sentence
          # PLUS injected/later blocking text ("Must fix ...") passes the
          # sentence but never the canonical whole-body exact-template match.
          # codex_root_comment_body_is_approved below mirrors the canonical
          # blocking-first, approved-template-exact order.
          if codex_root_comment_body_is_approved "$body"; then
            reviewer_started_at="$created"
            return 0
          fi
          return 2
        fi
      done <<< "$entries"
      return 1
      ;;
    claude-code-action)
      # claude-code-action-reviewer.sh's Phase 2/3 completion signal: a
      # workflow_dispatch run of the configured workflow file, PR-scoped by
      # run-name when any candidate carries one (concurrent dispatch — the
      # #808 run-name mechanism), newest by created_at, status=completed
      # AND conclusion=success — AND, since round 17, bound to the current
      # head and verified to have actually run (PRRT_kwDORWAxaM6m260w /
      # PRRT_kwDORWAxaM6m260z): the run's head_sha (the Actions runs API
      # carries it — the field claude-code-action-reviewer.sh's Phase 1
      # selection has always dispatched against) must equal the current
      # head, and the run log must carry a positive execution marker, the
      # same classify_claude_code_action_log acceptance
      # claude-code-action-reviewer.sh:413-417 applies through
      # verify_claude_code_action_run_log (no-op successes are real).
      # Fail closed: absent, in-progress, failed, stale-head, or no-op
      # runs return 1 (reviewer-check-absent), never a pass.
      local runs_json selected run_created run_head run_id
      runs_json="$(gh api "repos/$repo/actions/runs?event=workflow_dispatch&per_page=100" --paginate --slurp 2>/dev/null)" \
        || escalate workflow-run-fetch-failed
      selected="$(printf '%s\n' "${runs_json:-[]}" | jq -c --arg wf "${CLAUDE_CODE_ACTION_WORKFLOW_FILE:-claude-code-review.yml}" --arg pr "$pr_number" '
          [ .[]?[]?[]? | objects ]
          | [ .[] | select(((.path // "")) | endswith($wf)) ] as $candidates
          | ($candidates | if ([ $candidates[] | select((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")?) ] | length > 0) then
              [ .[] | select(((.name // "") | capture("PR #(?<pr>[0-9]+)(?:[^0-9]|$)")? | .pr) == $pr) ]
            else . end)
          | sort_by(.created_at)
          | reverse
          | first
        ' 2>/dev/null)" || escalate workflow-run-parse-failed
      [ -n "$selected" ] && [ "$selected" != "null" ] || return 1
      if [ "$(printf '%s\n' "$selected" | jq -r '.status // ""')" != "completed" ] \
          || [ "$(printf '%s\n' "$selected" | jq -r '.conclusion // ""')" != "success" ]; then
        return 1
      fi
      # Round 17 (PRRT_kwDORWAxaM6m260w): a successful run whose head_sha is
      # not the current head is STALE — it certifies a prior (already
      # superseded) head, never the unreviewed new one.
      run_head="$(printf '%s\n' "$selected" | jq -r '.head_sha // ""')"
      [ -n "$run_head" ] || return 1
      [ "$run_head" = "$head_sha" ] || return 1
      # Round 17 (PRRT_kwDORWAxaM6m260z): conclusion=success alone is not
      # proof the reviewer actually ran — claude-code-action exits
      # successfully on a no-op (no prompt/trigger). Fetch the run log and
      # apply the SAME acceptance verify_claude_code_action_run_log applies
      # (classify_claude_code_action_log): fail closed on a no-op, an
      # unreadable, or an execution-marker-less log.
      run_id="$(printf '%s\n' "$selected" | jq -r '.id // ""')"
      [ -n "$run_id" ] || return 1
      claude_action_run_log_shows_execution "$run_id" || return 1
      run_created="$(printf '%s\n' "$selected" | jq -r '.created_at // ""')"
      reviewer_started_at="$run_created"
      return 0
      ;;
    pr-agent)
      # run_pr_agent_review's strict_sha completion surface: the bot's
      # latest issue comment carrying the head SHA and "PR Reviewer Guide",
      # classified with _pr_agent_classify's rules. A hard-blocker
      # focus-area label (Critical / Must Fix / Breaking Change / Security
      # Concern / API Change / Backward Compatibility) or an unreadable
      # focus section is needs_fixes → rc 2 (blocking). "No major issues
      # detected" is clean.
      local pragent_entry
      pragent_entry="$(printf '%s\n' "${issue_comments_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" '
          [ .[]?[]
            | select(
                (((.user.login // "") == $bot) or ((.user.login // "") == ($bot | sub("\\[bot\\]$"; ""))) or ((.user.login // "") == ($bot + "[bot]")))
              )
            | select(((.body // "") | contains($sha)) and (((.body // "") | test("PR Reviewer Guide"; "i"))))
          ]
          | sort_by(.created_at)
          | last // empty
        ' 2>/dev/null)" || escalate issue-comment-parse-failed
      [ -n "$pragent_entry" ] || return 1
      body="$(printf '%s\n' "$pragent_entry" | jq -r '.body // ""')"
      created="$(printf '%s\n' "$pragent_entry" | jq -r '.created_at // ""')"
      if printf '%s\n' "$body" | grep -q "No major issues detected"; then
        reviewer_started_at="$created"
        return 0
      fi
      if printf '%s\n' "$body" | grep -q "Recommended focus areas for review"; then
        # Extract <strong>LABEL</strong> tokens from the focus section and
        # apply the same hard-blocker label set _pr_agent_classify uses.
        local focus_labels label label_lower
        focus_labels="$(printf '%s\n' "$body" \
          | awk '/Recommended focus areas for review/{found=1; next}
                 found && /^[[:space:]]*(\*\*|<\/td>|<tr>)|^---$/{found=0}
                 found{print}' \
          | grep -oE '<strong>[^<]+</strong>' \
          | sed 's|<strong>||g;s|</strong>||g;s|^[[:space:]]*||;s|[[:space:]]*$||' \
          || true)"
        [ -n "$focus_labels" ] || return 2
        while IFS= read -r label; do
          [ -n "$label" ] || continue
          label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
          case "$label_lower" in
            critical|"must fix"|"breaking change"|"security concern"|"api change"|"backward compatibility")
              return 2
              ;;
          esac
        done <<< "$focus_labels"
        reviewer_started_at="$created"
        return 0
      fi
      # No verdict markers at all: not this cycle's terminal comment shape —
      # fail closed rather than guessing.
      return 1
      ;;
    greptile)
      # Round 18 (thread PRRT_kwDORWAxaM6m36Wu): the trigger must belong to
      # the CURRENT review cycle — run_greptile_review clears an
      # already-reacted recent trigger and posts a new one, so a `+1` on a
      # trigger from a PRIOR cycle certifies the prior head's already-
      # consumed cycle, not this head. Round 17 bound this to the head
      # commit's `.commit.committer.date`, but that is AUTHOR-CONTROLLED
      # metadata: a commit created (or backdated via GIT_COMMITTER_DATE)
      # before an already-reacted trigger and pushed afterwards satisfies
      # the round-17 comparison while the push was never observed. The
      # binding is now GitHub's SERVER-RECORDED timeline: the GraphQL PR
      # timelineItems list, where GitHub appends a PullRequestCommit node
      # for the head SHA only when it OBSERVES the push. The trigger's
      # IssueComment node must appear AFTER the head commit's
      # PullRequestCommit node in that server-ordered list — an ordering
      # no committer-date forgery can move (pushedDate itself is null on
      # this repository's commits, so node order is the only server-side
      # push observation available). A timeline fetch/parse failure
      # escalates fail-closed; a trigger the server ordered before the
      # head commit refuses (absent evidence).
      local _greptile_owner="${repo%%/*}" _greptile_name="${repo#*/}"
      local _greptile_timeline
      if ! _greptile_timeline="$(gh api graphql \
            -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){timelineItems(last:100){nodes{__typename ...on PullRequestCommit{commit{oid}} ...on IssueComment{databaseId createdAt body}}}}}}' \
            -f owner="$_greptile_owner" \
            -f repo="$_greptile_name" \
            -F pr="$pr_number" \
            --jq '.data.repository.pullRequest.timelineItems.nodes' 2>/dev/null)" \
          || [ -z "$_greptile_timeline" ] || [ "$_greptile_timeline" = "null" ]; then
        escalate greptile-timeline-fetch-failed
      fi
      trigger="$(printf '%s\n' "$_greptile_timeline" | jq -c --arg sha "$head_sha" '
        ( index( [ .[] | select(.__typename == "PullRequestCommit" and ((.commit.oid // "" | ascii_downcase) == ($sha | ascii_downcase)) ) ][0] ) ) as $head_commit_idx
        | if $head_commit_idx == null then empty else
            [ .[ $head_commit_idx: ][]
              | select(.__typename == "IssueComment" and ((.body // "") == "@greptile review"))
              | {id: (.databaseId // 0), created_at: (.createdAt // "")}
            ]
            | sort_by(.created_at)
            | last // empty
          end
      ' 2>/dev/null)"
      [ -n "$trigger" ] || return 1
      local trigger_id
      trigger_id="$(printf '%s\n' "$trigger" | jq -r '.id // 0' 2>/dev/null)"
      [ "$trigger_id" != "0" ] || return 1
      if ! reactions_json="$(gh api "repos/$repo/issues/comments/$trigger_id/reactions" 2>/dev/null)" || [ -z "$reactions_json" ]; then
        return 1
      fi
      if printf '%s\n' "$reactions_json" | jq -e --arg bot "$bot_login_arg" --arg plain "${bot_login_arg%\[bot\]}" '
        [ .[]
          | select(
              (((.user.login // "") == $bot) or ((.user.login // "") == $plain) or ((.user.login // "") == ($bot + "[bot]")))
              and ((.content // "") == "+1")
            )
        ] | length > 0
      ' >/dev/null 2>&1; then
        reviewer_started_at="$(printf '%s\n' "$trigger" | jq -r '.created_at // ""' 2>/dev/null)"
        return 0
      fi
      return 1
      ;;
  esac
  return 1
}

# commented_review_body_blocks <body> <platform> — round 15 (PR #1818 thread
# PRRT_kwDORWAxaM6m1pF4): per-platform classification of a COMMENTED review
# body, mirroring the platform's own loop reader. The pre-round-15 rule
# exempted ANY COMMENTED body without Bugbot markers, so Devin's
# "**Devin Review**" findings summary (run_devin_review treats exactly that
# body shape as blocking, pr-review-loop.sh ~4620) and a codex terminal
# verdict body (codex-github-reviewer.sh safe-fails every unrecognized
# terminal body) never blocked. A body a platform's own classifier treats as
# blocking blocks here; a genuinely informational/umbrella body (completion
# summary, soft suggestion, ancillary comment) stays non-blocking.
commented_review_body_blocks() {
  local body_arg="$1" platform_arg="$2"
  case "$platform_arg" in
    devin)
      # run_devin_review: a COMMENTED body starting "**Devin Review**" is
      # Devin's findings summary — blocking regardless of severity (Devin
      # uses COMMENTED instead of CHANGES_REQUESTED). Any other COMMENTED
      # body (completion text, "No Issues Found") is informational.
      if printf '%s\n' "$body_arg" | grep -qi '^\*\*Devin Review\*\*'; then
        return 0
      fi
      return 1
      ;;
    codex-github)
      # codex-github-reviewer.sh classifies the whole terminal body: the
      # approved clean template ("Didn't find any major issues") is clean;
      # every other "Codex Review:" verdict body safe-fails (unrecognized is
      # never clean). Bodies without the verdict prefix are ancillary
      # (acknowledgement/trigger text) — informational.
      case "$body_arg" in
        "Codex Review:"*)
          if printf '%s\n' "$body_arg" | grep -q "Didn't find any major issues"; then
            return 1
          fi
          return 0
          ;;
      esac
      return 1
      ;;
    bugbot|haystack|ronda|"")
      # Bugbot's umbrella COMMENTED review carries its own finding markers
      # (the pre-round-15 rule, unchanged for the check-run-bearing
      # platforms); haystack/ronda publish findings inline, counted by the
      # inline loop.
      if printf '%s\n' "$body_arg" | grep -q "BUGBOT_REVIEW\|BUGBOT_BUG_ID\|LOCATIONS"; then
        return 0
      fi
      return 1
      ;;
    *)
      # greptile / coderabbit / copilot / claude-code-action loop readers
      # block only on CHANGES_REQUESTED reviews or inline findings; a
      # COMMENTED body is the informational umbrella.
      return 1
      ;;
  esac
}

emit_verdict() {
  print_kv RESULT "$result"
  print_kv REASON "$reason"
  print_kv PR_NUMBER "$pr_number"
  print_kv REPO "$repo"
  print_kv LABEL "$label"
  print_kv HEAD_SHA "$head_sha"
  print_kv REVIEWER_REPORT "$reviewer_report"
  print_kv BLOCKING_FINDING_COUNT "$blocking_count"
  print_kv PENDING_CHECK_COUNT "$pending_count"
  print_kv FAILING_CHECK_COUNT "$failing_count"
  if [ "$json_output" = "true" ]; then
    python3 -c 'import json,sys; print(json.dumps(dict(result=sys.argv[1], reason=sys.argv[2], prNumber=sys.argv[3], repo=sys.argv[4], label=sys.argv[5], headSha=sys.argv[6], reviewerReport=sys.argv[7], blockingFindingCount=int(sys.argv[8]), pendingCheckCount=int(sys.argv[9]), failingCheckCount=int(sys.argv[10]))))' \
      "$result" "$reason" "$pr_number" "$repo" "$label" "$head_sha" "$reviewer_report" "$blocking_count" "$pending_count" "$failing_count"
  fi
}

escalate() {
  result="escalate"
  reason="$1"
  # Same stale-label contract as refuse() (PR #1818 finding 1, round 9): an
  # escalation after the initial state read means a label the PR already
  # carried at run start has no readable verdict behind it — an
  # API/parse failure mid-rerun must not leave that stale label for the
  # delegated/batch merge gates to consume. Guarded on the flag being
  # explicitly 1: several escalations fire BEFORE the initial label-presence
  # capture (pr-state-unavailable, ready-config-unreadable, ...), and an
  # unset/empty flag must never trigger removal.
  if [ "${label_initially_present:-0}" = "1" ]; then
    remove_readiness_label_best_effort "$label"
  fi
  emit_verdict
  exit 2
}

# refuse <reason> — the single pre-apply refusal exit (PR #1818 finding 1,
# round 8). When the PR ALREADY carried the requested label when this run
# started (label_initially_present=1), the refusal verdict means that label
# no longer certifies a verified state — remove it best-effort so the
# delegated/batch merge gates cannot consume a stale readiness label on the
# strength of a refusal. WARN-and-refuse on removal failure. No removal when
# the label was not already present.
# annotate_needs_fixes_best_effort — idempotent `needs-fixes` annotation on a
# blocking verdict (PR #1818 F2, round 11; reused by the comment-only
# completion-adapter rc=2 path in round 16). Best-effort: a failure here must
# not mask the blocking verdict about to be emitted.
annotate_needs_fixes_best_effort() {
  if [ "$applied_notified" -eq 0 ]; then
    applied_notified=1
    applied_labels="$(printf '%s
' "$pr_json" | jq -r '.labels[]?.name' 2>/dev/null)" || applied_labels=""
    if ! printf '%s
' "$applied_labels" | grep -qx 'needs-fixes'; then
      gh pr edit "$pr_number" --repo "$repo" --add-label 'needs-fixes' >/dev/null 2>&1 || true  # workflow-shell-guard: allow SH001 - best-effort annotation; a failure here must not mask the blocking verdict about to be emitted.
    fi
  fi
}

refuse() {
  reason="$1"
  if [ "$label_initially_present" = "1" ]; then
    remove_readiness_label_best_effort "$label"
  fi
  result="refused"
  emit_verdict
  exit 1
}

# remove_readiness_label_best_effort <label> — after a post-apply escalation,
# the label no longer certifies a verified state, so strip it before
# escalating so no unreviewed/undrifting head carries it between the refusal
# and whatever re-runs the gate. Best-effort only: a failed removal logs a
# WARN and the caller still escalates, so a human sees the problem either way.
remove_readiness_label_best_effort() {
  local label_to_remove="$1"
  if ! gh pr edit "$pr_number" --repo "$repo" --remove-label "$label_to_remove" >/dev/null 2>&1; then
    printf 'WARN: %s\n' "failed to remove $label_to_remove on PR #$pr_number — remove it manually" >&2
  fi
}

# reviewer_check_conclusion_is_clean <conclusion> — shared conclusion→verdict
# logic for the main reviewer gate and the pre-apply revalidation (PR #1818
# finding 2, round 5). The allow-list is explicit: `success` is clean; the
# four blocking conclusions are not; `neutral`/`cancelled`/`skipped` are not
# (they carry the unavailable handling in the main loop and are simply "no
# longer a clean completed run" at revalidation); ANY other non-empty
# conclusion is not (mirrors run_ronda_review()'s fail-closed default arm).
reviewer_check_conclusion_is_clean() {
  case "$1" in
    success) return 0 ;;
    *) return 1 ;;
  esac
}

# bugbot_unavailable_notice_present <bot_login> <since> — returns 0 (true)
# when a Bugbot usage/spend-limit or restricted-access notice was posted by
# the bot at/after <since> (inclusive, PR #1818 finding 3, round 8: a notice
# created in the SAME second as the check run's start belongs to that run;
# a strict > dropped it and read the non-review as clean). Shared by the main
# gate's unavailable handling and the pre-apply revalidation (PR #1818
# finding 2, round 6), so a rerun's quota refusal is caught at revalidation
# too. Escalates fail-closed on a fetch or parse failure.
bugbot_unavailable_notice_present() {
  local bot_login_arg="$1" since_arg="$2"
  local issue_comments_json unavailable_bodies notice
  issue_comments_json=""
  if ! issue_comments_json="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate issue-comment-fetch-failed
  fi
  unavailable_bodies=""
  if ! unavailable_bodies="$(printf '%s\n' "${issue_comments_json:-[]}" | jq -r --arg bot "$bot_login_arg" --arg since "$since_arg" '
        [ .[]?[]
          | select(
              ((.user.login // "") == $bot or (.user.login // "") == ($bot + "[bot]"))
              and (($since == "") or ((.created_at // "") >= $since))
            )
          | .body // ""
        ] | .[]
      ' 2>/dev/null)"; then
    escalate issue-comment-parse-failed
  fi
  while IFS= read -r notice; do
    [ -n "$notice" ] || continue
    if is_bugbot_disabled_message "$notice" || is_bugbot_usage_limit_message "$notice"; then
      return 0
    fi
  done <<< "$unavailable_bodies"
  return 1
}

# count_reviewer_blocking_findings <bot_login> <since_body> [<since_inline>]
# [<platform>] — fetches the PR review surfaces (inline comments + reviews)
# and classifies the reviewer bot's findings on the current head, setting the
# global scan_blocking_count. Review bodies count at/after <since_body>;
# inline comments at/after <since_inline> (round 15, thread
# PRRT_kwDORWAxaM6m1pGF: the comment-only path passes the selected review's
# own start — the earliest of its submitted_at and its inline comments' min
# created_at — so a pending-review inline comment is counted; the check-run
# path passes the run's started_at for both, unchanged). <platform> routes
# the COMMENTED-body classifier (round 15, thread PRRT_kwDORWAxaM6m1pF4).
# A body carrying "✅ Addressed" (the reviewer's own resolved marker) never
# blocks — the same resolution signal check_unresolved_threads and
# codex_review_thread_evidence_counts read. Shared by the main gate and the
# pre-apply revalidation (PR #1818 finding 2, round 6): a same-SHA rerun that
# completes between the initial scan and the label mutation can post findings
# the first scan never saw, so the revalidation rescans the same surfaces
# with the same filters against the reselected run's timestamp instead of
# trusting the earlier pass. Escalates fail-closed on a fetch or parse
# failure.
count_reviewer_blocking_findings() {
  local bot_login_arg="$1" since_arg="$2"
  local inline_since_arg="${3:-$2}" review_platform="${4:-}"
  local comments_json reviews_json inline_json review_json inline_count entry body state inline
  scan_blocking_count=0
  comments_json=""
  reviews_json=""
  # Findings/comment fetches use `--paginate --slurp` and flatten in jq: an
  # unslurped paginated response is one JSON document per page, so a jq
  # pipeline runs per page and a downstream consumer sees a multiline
  # concatenation instead of one array (same defect class as the check-runs
  # read in the main loop).
  if ! comments_json="$(gh api "repos/$repo/pulls/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate review-comment-fetch-failed
  fi
  if ! reviews_json="$(gh api "repos/$repo/pulls/$pr_number/reviews" --paginate --slurp 2>/dev/null)"; then
    escalate review-fetch-failed
  fi

  # Inline comments on this SHA, posted top-level by the reviewer bot.
  inline_json=""
  if ! inline_json="$(printf '%s\n' "${comments_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" --arg since "$inline_since_arg" '
        [ .[]?[]
          | select(
              ((.user.login // "") == $bot or (.user.login // "") == ($bot | sub("\\[bot\\]$"; "")) or (.user.login // "") == ($bot + "[bot]"))
              and ((.commit_id // "") == $sha)
              and ((.in_reply_to_id // null) == null)
              and ((.created_at // "") >= $since)
            )
          | { body: (.body // "") }
        ]
      ' 2>/dev/null)"; then
    escalate review-comment-parse-failed
  fi
  inline_count="$(printf '%s\n' "$inline_json" | jq 'length' 2>/dev/null)" || escalate review-comment-parse-failed

  # Reviews submitted against this SHA. `CHANGES_REQUESTED` is always blocking;
  # a `COMMENTED` review is blocking when its body carries the platform's
  # blocking content (commented_review_body_blocks) — Bugbot's finding
  # markers, Devin's "**Devin Review**" summary, a codex terminal verdict.
  review_json=""
  if ! review_json="$(printf '%s\n' "${reviews_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" --arg since "$since_arg" --argjson inline "$inline_count" '
        [ .[]?[]
          | select(
              (((.user.login // "") == $bot) or ((.user.login // "") == ($bot | sub("\\[bot\\]$"; ""))) or ((.user.login // "") == ($bot + "[bot]")))
              and ((.commit_id // .commitId // "") == $sha)
              and (((.submitted_at // "") >= $since))
            )
          | { state: (.state // ""), body: (.body // ""), inline: $inline }
        ]
      ' 2>/dev/null)"; then
    escalate review-parse-failed
  fi

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    body="$(printf '%s\n' "$entry" | jq -r '.body')"
    state="$(printf '%s\n' "$entry" | jq -r '.state')"
    # `inline` was consumed by the pre-round-14 "COMMENTED with inline" arm;
    # the informational-umbrella rule no longer reads it (the inline loop
    # below counts inline findings on its own).
    # shellcheck disable=SC2034
    inline="$(printf '%s\n' "$entry" | jq -r '.inline')"
    if [ "$state" = "CHANGES_REQUESTED" ]; then
      scan_blocking_count=$((scan_blocking_count + 1))
      continue
    fi
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    if printf '%s\n' "$body" | grep -q "✅ Addressed"; then
      continue
    fi
    if [ "$state" = "COMMENTED" ]; then
      # Round 15 (thread PRRT_kwDORWAxaM6m1pF4): per-platform body
      # classification. Pre-round-15 this exempted ANY body without Bugbot
      # markers, so Devin's "**Devin Review**" findings summary and a codex
      # terminal verdict body (bodies the platforms' own loop classifiers
      # treat as blocking) never blocked. A genuinely informational umbrella
      # (completion summary, soft suggestion, ancillary comment) stays
      # non-blocking — its inline findings are counted in the inline loop
      # below, so the umbrella itself must not double-count or block alone
      # after its inline finding was resolved ("✅ Addressed").
      if commented_review_body_blocks "$body" "$review_platform"; then
        scan_blocking_count=$((scan_blocking_count + 1))
      fi
      continue
    fi
    scan_blocking_count=$((scan_blocking_count + 1))
  done < <(printf '%s\n' "$review_json" | jq -c '.[]' 2>/dev/null)

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    body="$(printf '%s\n' "$entry" | jq -r '.body')"
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    if printf '%s\n' "$body" | grep -q "✅ Addressed"; then
      continue
    fi
    scan_blocking_count=$((scan_blocking_count + 1))
  done < <(printf '%s\n' "$inline_json" | jq -c '.[]' 2>/dev/null)
}

# --- 1. PR state -----------------------------------------------------------
pr_json=""
if ! pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup 2>/dev/null)" || [ -z "$pr_json" ]; then
  escalate pr-state-unavailable
fi
head_sha="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
if [ -z "$head_sha" ]; then
  escalate head-sha-unavailable
fi
head_ref_name="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // ""' 2>/dev/null)" || escalate pr-state-parse-failed
base_ref_oid="$(printf '%s\n' "$pr_json" | jq -r '.baseRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
# Whether the requested label is already on the PR at the START of this run
# (PR #1818 finding 1, round 8): a rerun (same-SHA reviewer rerun, new push)
# can hit a refusal path while the PR still carries the label from an earlier
# successful gate — that stale label is a merge-gate input, so every refusal
# below removes it (refuse()); a clean rerun re-adds it.
label_initially_present="0"
if printf '%s\n' "$pr_json" | jq -e --arg l "$label" '[.labels[]?.name | select(. == $l)] | length > 0' >/dev/null 2>&1; then
  label_initially_present="1"
fi

# Implementation branches are the ones that carry a ready-phase reviewer check
# run and a required `ready-for-regression` label (Protocol 91's label derivation
# table). Doc-stage, graduation, and release PRs are not reviewer-gated.
# `hotfix/*` is exempt from the reviewer leg — same handling as `release/*`
# (PR #1818 finding 1, round 7): `_check_release_pr_guard` in
# pr-review-loop.sh skips the reviewer loop for `release/*` AND `hotfix/*`
# head branches, so no ready-phase reviewer check run can ever exist on a
# hotfix and requiring one would permanently refuse both readiness labels
# `reviewer-check-absent`. The CI leg below still applies unchanged — that is
# the release-branch handling this mirrors.
case "$head_ref_name" in
  feature/*|fix/*|refactor/*|backport/hotfix/*) is_implementation_pr="true" ;;
  *) is_implementation_pr="false" ;;
esac

# --- 2. Ready-phase reviewer check runs for the current head ----------------

# supported_comment_only_reviewer_platform <platform> — true when the platform
# is a DOCUMENTED ready-phase reviewer that publishes its verdict through PR
# reviews/comments instead of a check run. The list is the documented
# pr-review-loop.sh platform set (.ai-dev-workflow.yaml's on_ready comment)
# minus the check-run-bearing three (haystack/bugbot/ronda) and the two
# pure-CLI no-GitHub-surface ones (coderabbit-cli, local-ai-reviewer — both
# reviewer scripts are read-only against GitHub, so the verdict comes from
# the loop's reviewer_loop_history.v1 ledger, the surface their own loop
# persists; since round 17 a current-head-pinned clean ledger entry passes
# and anything else refuses — see
# coderabbit_cli_local_ai_ledger_verdict). pr-agent posts its verdict as a
# bot issue comment, so its completion adapter reads that surface (the same
# one run_pr_agent_review reads). An unknown string still refuses
# reviewer-check-name-unresolved above, which is the typo guard.
supported_comment_only_reviewer_platform() {
  case "$1" in
    # Round 17: coderabbit-cli / local-ai-reviewer are LEDGER-read platforms
    # — the main gate's verdict comes from the loop's
    # reviewer_loop_history.v1 ledger
    # (coderabbit_cli_local_ai_ledger_verdict), not from a bot review or a
    # completion adapter — but they are documented supported platforms, so
    # the typo guard must not fire for them.
    coderabbit-cli|local-ai-reviewer) return 0 ;;
    codex-github|coderabbit|claude-code-action|copilot|devin|greptile|pr-agent) return 0 ;;
    *) return 1 ;;
  esac
}

reviewer_blocking=0
verdict_blocking=0
applied_notified=0
reviewer_names_seen=""
platform=""
# Per-platform record of the first finding scan: "platform:started_at" and
# "platform:bot_login" lines, newline-separated. The pre-apply revalidation
# compares the reselected check run's timestamp against these (PR #1818
# finding 2, round 6).
first_scan_started_at=""
first_scan_bot_logins=""
scan_blocking_count=0
if [ "$is_implementation_pr" = "true" ]; then
  # The PR's own head configuration is the source of truth (see
  # pr_head_config_ready_platforms). An explicit AI_DEV_WORKFLOW_CONFIG_FILE
  # (test harness or deliberate override) short-circuits the head fetch; a
  # head fetch/parse failure escalates — fail closed — instead of silently
  # gating on this checkout's configuration, which the PR may have changed.
  if [ -n "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
    ready_platforms="$(configured_ready_reviewer_platforms)"
  elif ! ready_platforms="$(pr_head_config_ready_platforms "$repo" "$head_sha" 2>/dev/null)"; then
    escalate ready-config-unreadable
  fi
  # An empty resolved platform list would waive every reviewer gate: the
  # while loop below would run zero times and the label would apply with
  # REVIEWER_REPORT=none (PR #1818 Codex finding 1, round 4). A PR that drops
  # the ready-phase reviewer from its own `.ai-dev-workflow.yaml` must not be
  # able to un-gate its own readiness label: an empty head list is only
  # legitimate when the base branch declares no ready-phase reviewers either.
  # For implementation PRs the base-branch policy is ALWAYS fetched (an
  # unreadable one escalates `base-config-unreadable`) and the gate validates
  # the BASE policy (PR #1818 finding 3, round 6): the required reviewer set
  # is exactly what the base branch declares — pr-review-loop.sh dispatches
  # ready-phase platforms from the BASE configuration, so a head-only ADDED
  # reviewer never runs and requiring its check run would permanently refuse
  # `reviewer-check-absent`. The head cannot waive what the base requires:
  # a head that removes or replaces a base reviewer still has every base
  # platform gated (a base platform absent from the head list is required
  # regardless), so `reviewer-policy-empty` / `reviewer-check-absent` fire
  # instead of the base reviewer being dropped. Head-only additions are
  # validated only when they happen to carry a completed clean check run
  # alongside the base set; they are never required. (An explicit
  # AI_DEV_WORKFLOW_CONFIG_FILE is a deliberate override surface and is
  # trusted as resolved; no base policy is fetched there.)
  if [ -z "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
    _base_ready_platforms=""
    # loop_dispatched_base=1: apply the local review override when resolving the
    # BASE policy, the same effective-policy resolution pr-review-loop.sh uses
    # when it dispatches ready-phase platforms from the base configuration
    # (PR #1818 finding 2, round 7).
    if ! _base_ready_platforms="$(loop_dispatched_base=1 pr_head_config_ready_platforms "$repo" "$base_ref_oid" 2>/dev/null)"; then
      escalate base-config-unreadable
    fi
    if [ -z "$(printf '%s\n' "$ready_platforms" | tr -d '[:space:]')" ]; then
      # Round-4 semantics: an empty head list is a dropped reviewer, refused
      # unless the base policy is empty too (CI-only gate then applies).
      if [ -n "$(printf '%s\n' "$_base_ready_platforms" | tr -d '[:space:]')" ]; then
        result="refused"
        reason="reviewer-policy-empty"
        reviewer_report="base-declares:$(printf '%s\n' "$_base_ready_platforms" | paste -sd, -)"
        refuse "reviewer-policy-empty"
      fi
    else
      # Nonempty head list: gate on the base policy alone (see the comment
      # block above). Head-only additions are not required.
      ready_platforms="$_base_ready_platforms"
    fi
  fi
else
  ready_platforms=""
fi
while IFS= read -r platform; do
  [ -n "$platform" ] || continue
  check_name="$(reviewer_check_name_for_platform "$platform")"
  # Fail closed for an unsupported/unknown platform string only (a typo or an
  # undocumented value): every DOCUMENTED ready-phase platform is either
  # check-run-bearing (haystack/bugbot/ronda — reviewer_check_name_for_platform
  # above) or comment-only (the list in supported_comment_only_reviewer_platform
  # below). Before round 14 any non-mapped platform refused here, which
  # deadlocked every documented comment-only platform (codex-github,
  # coderabbit, ...) — rounds 11-13 routed every readiness-label producer
  # through this helper, so the fail-closed default became a permanent refusal
  # even though pr-review-loop.sh fully supports those platforms (PR #1818
  # thread PRRT_kwDORWAxaM6m1Dec).
  # Round 16 named this surface; round 17 (thread PRRT_kwDORWAxaM6m260s)
  # consumes it: coderabbit-cli and local-ai-reviewer are documented,
  # dispatchable ready-phase platforms whose reviewer scripts leave no
  # review/comment surface of their own (pure-CLI readers), so their
  # verdict is read from the loop's persisted reviewer_loop_history.v1
  # ledger — a current-head-pinned clean entry passes, and absent/stale/
  # not-clean/unreadable ledger evidence refuses fail-closed. Never a
  # silent pass.
  case "$platform" in
    coderabbit-cli|local-ai-reviewer)
      coderabbit_cli_local_ai_ledger_verdict "$platform"
      ;;
  esac
  # Fail closed for an unsupported/unknown platform string (a typo or an
  # undocumented value): every DOCUMENTED ready-phase platform is either
  # check-run-bearing (haystack/bugbot/ronda) or comment-only (the list in
  # supported_comment_only_reviewer_platform above). Before round 14 any
  # non-mapped platform refused here, which deadlocked every documented
  # comment-only platform (PR #1818 thread PRRT_kwDORWAxaM6m1Dec). The
  # two documented pure-CLI platforms (coderabbit-cli, local-ai-reviewer)
  # are handled just above with their named refusal.
  if [ -z "$check_name" ] && ! supported_comment_only_reviewer_platform "$platform"; then
    result="refused"
    reason="reviewer-check-name-unresolved"
    reviewer_report="$platform"
    refuse "reviewer-check-name-unresolved"
  fi
  bot_login="$(bot_login_for_platform "$platform")"
  # Comment-only reviewer: no check run exists, so the verdict comes from the
  # bot's latest review against the head SHA (same evidence surface the loop's
  # comment-only platform readers use). comment_only_reviewer_verdict refuses
  # (reviewer-check-absent) or escalates itself, and sets
  # reviewer_started_at/scan_blocking_count for the shared machinery below.
  if [ -z "$check_name" ]; then
    comment_only_reviewer_verdict "$platform" "$bot_login"
    reviewer_blocking=$((reviewer_blocking + scan_blocking_count))
    first_scan_started_at="${first_scan_started_at}${first_scan_started_at:+
}${platform}:${reviewer_started_at}"
    first_scan_bot_logins="${first_scan_bot_logins}${first_scan_bot_logins:+
}${platform}:${bot_login}"
    reviewer_names_seen="${reviewer_names_seen}${reviewer_names_seen:+,}${platform}:review"
    # Set here, not after the loop: the in-loop refusal paths below still emit
    # a verdict, and an empty REVIEWER_REPORT there would read as "no reviewer".
    reviewer_report="$reviewer_names_seen"
    continue
  fi
  reviewer_names_seen="${reviewer_names_seen}${reviewer_names_seen:+,}${check_name}"
  # Set here, not after the loop: the in-loop refusal paths below still emit a
  # verdict, and an empty REVIEWER_REPORT there would read as "no reviewer".
  reviewer_report="$reviewer_names_seen"

  # `--slurp` merges the paginated responses into one array; without it `gh`
  # emits one JSON object per page and the jq below runs once per page, making
  # `check_state` multiline (a first-page "completed failure" then reads
  # conclusion "failure\n " and misses the blocking case).
  check_runs_json=""
  if ! check_runs_json="$(gh api "repos/$repo/commits/$head_sha/check-runs" --paginate --slurp 2>/dev/null)" || [ -z "$check_runs_json" ]; then
    escalate check-run-fetch-failed
  fi
  if ! check_state="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
        [ .[].check_runs[]? | select(.name == $name) ]
        | sort_by(.started_at // .completed_at // "")
        | last
        | (if . == null then " " else ((.status // "") + " " + (.conclusion // "")) end)
      ' 2>/dev/null)"; then
    escalate check-run-parse-failed
  fi
  status_val="${check_state%% *}"
  conclusion="${check_state#* }"

  # started_at of the selected (latest) check run. Findings are time-bounded
  # to it: a stale same-SHA review comment from an *earlier* reviewer run must
  # not block forever — same rule pr-review-loop.sh applies (~3704-3729),
  # where `.created_at > $since` scopes the verdict read.
  reviewer_started_at="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
        [ .[].check_runs[]? | select(.name == $name) ]
        | sort_by(.started_at // .completed_at // "")
        | last
        | (.started_at // .completed_at // .created_at // "")
      ' 2>/dev/null)" || escalate check-run-parse-failed

  # Absent check run is not clean: the reviewer may have refused to run.
  if [ -z "$status_val" ] || [ "$status_val" = "null" ] || [ "$status_val" = " " ]; then
    result="refused"
    reason="reviewer-check-absent"
    refuse "reviewer-check-absent"
  fi
  if [ "$status_val" != "completed" ]; then
    result="refused"
    reason="reviewer-check-not-completed"
    refuse "reviewer-check-not-completed"
  fi
  # A non-success conclusion is itself a blocking verdict, even when no inline
  # finding survives classification — the loop applies the same rule. The
  # allow-list lives in reviewer_check_conclusion_is_clean (shared with the
  # pre-apply revalidation): `success` is clean, the four blocking conclusions
  # and neutral/cancelled/skipped are handled below, and ANY other non-empty
  # conclusion (e.g. `stale`) refuses fail-closed instead of falling through
  # as clean — mirrors run_ronda_review()'s default arm
  # (pr-review-loop.sh ~2894-2905).
  if ! reviewer_check_conclusion_is_clean "$conclusion"; then
    case "$conclusion" in
      failure|action_required|timed_out|startup_failure)
        verdict_blocking=$((verdict_blocking + 1))
        ;;
      neutral|cancelled|skipped) ;;
      *)
        result="refused"
        reason="reviewer-check-unknown-conclusion"
        reviewer_report="$check_name conclusion:$conclusion"
        refuse "reviewer-check-unknown-conclusion"
        ;;
    esac
  fi

  # `neutral` / `cancelled` / `skipped` are informational ONLY when the reviewer
  # did not also post an unavailable notice for this head. Bugbot reports a
  # usage/spend limit and a restricted-access refusal through a `neutral` check
  # run plus an issue comment, so a bare `neutral` must never read as clean —
  # that is the exact shape of "reviewer did not actually run" this gate exists
  # to catch. `run_bugbot_review()` applies the same rule (pr-review-loop.sh
  # ~3838). This is the only issue-comment read in this helper, and it is an
  # availability probe, not a finding source: findings come from
  # `pulls/N/comments` and `pulls/N/reviews`.
  # Only Bugbot reports unavailability this way, and only through an issue
  # comment authored by its own bot login, so the probe is scoped to both.
  # The probe itself is shared (bugbot_unavailable_notice_present) with the
  # pre-apply revalidation, so a rerun that concluded `neutral` with a quota
  # notice is caught at revalidation too.
  case "$conclusion" in
    neutral|cancelled|skipped)
      if [ "$platform" = "bugbot" ] && [ -n "$bot_login" ]; then
        if bugbot_unavailable_notice_present "$bot_login" "$reviewer_started_at"; then
          result="refused"
          reason="reviewer-unavailable"
          refuse "reviewer-unavailable"
        fi
      else
        # Non-Bugbot platforms report nothing through issue comments, so a
        # `neutral`/`cancelled`/`skipped` completed run cannot be cleared by
        # any notice: the reviewer never finished a successful review. Fail
        # closed — same refusal shape as the notice path above. Mirrors
        # `run_ronda_review()`'s escalation of these conclusions
        # (pr-review-loop.sh ~2894-2905).
        result="refused"
        reason="reviewer-unavailable"
        refuse "reviewer-unavailable"
      fi
      ;;
  esac

  # Read findings only where a login exists (haystack reviews through its own
  # CLI and publishes no GitHub review surface). The scan itself is shared
  # (count_reviewer_blocking_findings) with the pre-apply revalidation. The
  # per-platform timestamp the first scan ran against is recorded
  # (first_scan_started_at) so the revalidation can detect a *newer* selected
  # run — one whose findings the first scan never saw (PR #1818 finding 2,
  # round 6).
  [ -n "$bot_login" ] || continue
  count_reviewer_blocking_findings "$bot_login" "$reviewer_started_at" "$reviewer_started_at" "$platform"
  reviewer_blocking=$((reviewer_blocking + scan_blocking_count))
  first_scan_started_at="${first_scan_started_at}${first_scan_started_at:+
}${platform}:${reviewer_started_at}"
  first_scan_bot_logins="${first_scan_bot_logins}${first_scan_bot_logins:+
}${platform}:${bot_login}"
done < <(printf '%s\n' "$ready_platforms")

reviewer_report="${reviewer_names_seen:-none}"

if [ "$reviewer_blocking" -gt 0 ] || [ "$verdict_blocking" -gt 0 ]; then
  # The reviewer already flagged this SHA — annotate the PR `needs-fixes`
  # before refusing. Read the PR's existing labels so the annotation is
  # idempotent (no duplicate add when `needs-fixes` is already present).
  # Runs here, AFTER `count_reviewer_blocking_findings` accumulates, so the
  # comment-only shape is covered too: a check run concluding `success`
  # while the reviewer posted blocking inline comments refuses as
  # `blocking-findings` with the annotation applied (PR #1818 F2, round 11)
  # — the per-platform verdict block alone fired only on non-`success`
  # conclusions and missed it. Best-effort: a failure here must not mask
  # the blocking verdict about to be emitted.
  annotate_needs_fixes_best_effort
  result="refused"
  reason="blocking-findings"
  blocking_count="$reviewer_blocking"
  [ "$blocking_count" -ge 1 ] || blocking_count=1
  refuse "blocking-findings"
fi

# --- 3. Non-reviewer checks must not be pending or failing ------------------
normalized=""
if ! normalized="$(printf '%s\n' "$pr_json" | normalize_status_check_rollup 2>/dev/null)" || [ -z "$normalized" ]; then
  escalate check-rollup-parse-failed
fi

baseline_json=""
if ! baseline_json="$(printf '%s\n' "$normalized" | jq -c --argjson names "$(printf '%s\n' "$reviewer_names_seen" | tr ',' '\n' | jq -R . | jq -s '.')" '
      [ .[]
        | (.name // .context // .workflowName // "unknown") as $n
        | select(($names | index($n)) | not)
      ]
    ' 2>/dev/null)"; then
  escalate check-rollup-parse-failed
fi

pending_count="$(printf '%s\n' "$baseline_json" | jq '
  [ .[] | select(
      (((.status // "") != "") and ((.status // "") != "COMPLETED"))
      or (((.state // "") | ascii_upcase) == "EXPECTED")
      or (((.state // "") | ascii_upcase) == "PENDING")
      or (((.state // "") | ascii_upcase) == "IN_PROGRESS")
      or (((.state // "") | ascii_upcase) == "QUEUED")
    ) ] | length
' 2>/dev/null)" || escalate check-rollup-parse-failed

failing_count="$(printf '%s\n' "$baseline_json" | jq '
  [ .[] | select(
      (((.conclusion // "") | ascii_upcase) == "FAILURE")
      or (((.conclusion // "") | ascii_upcase) == "CANCELLED")
      or (((.conclusion // "") | ascii_upcase) == "TIMED_OUT")
      or (((.conclusion // "") | ascii_upcase) == "ACTION_REQUIRED")
      or (((.conclusion // "") | ascii_upcase) == "STARTUP_FAILURE")
      or (((.state // "") | ascii_upcase) == "FAILURE")
      or (((.state // "") | ascii_upcase) == "ERROR")
    ) ] | length
' 2>/dev/null)" || escalate check-rollup-parse-failed

# `ready-for-regression` is applied at Step 7b — *before* the Step 8 CI loop — so
# a pending check is normal there and must not block. `ready-for-human-review` is
# the merge-gate input and has no such excuse: pending refuses.
if [ "$pending_count" -gt 0 ] && [ "$label" != "ready-for-regression" ]; then
  result="refused"
  reason="ci-pending"
  refuse "ci-pending"
fi
if [ "$failing_count" -gt 0 ]; then
  result="refused"
  reason="ci-failing"
  refuse "ci-failing"
fi

# --- 4. Apply ---------------------------------------------------------------
# `--add-label` binds nothing to a commit: a push landing between the state
# read at the top and this mutation would leave every reviewer/CI verdict
# describing the old head while the label certifies the new one. Re-fetch the
# head immediately before the mutation and refuse on any drift. A *rerun*
# check is equally stale: if the reviewer check run was re-triggered on this
# same head (success → pending/failure) after the verdicts above were read,
# the verdicts describe a superseded run, and re-checking only `headRefOid`
# would apply the label from stale success data (PR #1818 finding 2, round 5).
# A failed or empty revalidation fetch escalates fail-closed as
# `revalidation-unreadable` — never success (PR #1818 finding 1, round 6) —
# and a rerun that completes between the first scan and the revalidation is
# rescanned for findings and availability notices against the newly selected
# run's timestamp, because a same-SHA rerun can conclude `success` while
# posting blocking comments (PR #1818 finding 2, round 6). The same applies
# to CI: a statusCheckRollup re-read must still satisfy the pending/failing
# rules applied at the main gate. The same conclusion→verdict logic is
# reused (reviewer_check_conclusion_is_clean) so the two gates cannot drift
# apart.
revalidate_reviewer_state() {
  local platform_arg check_name_arg check_runs_arg status_arg conclusion_arg
  local started_at_arg first_scan_login
  while IFS= read -r platform_arg; do
    [ -n "$platform_arg" ] || continue
    check_name_arg="$(reviewer_check_name_for_platform "$platform_arg")"
    # Comment-only platforms revalidate on the same review surface the main
    # gate gated on (comment_only_reviewer_verdict): if the bot's latest
    # head review is unchanged and still carries zero blocking findings, the
    # verdict still stands; a new review or a new finding refuses (fail
    # closed, never a silent pass).
    if [ -z "$check_name_arg" ]; then
      if [ "$platform_arg" = "coderabbit-cli" ] || [ "$platform_arg" = "local-ai-reviewer" ]; then
        # Round 17 (thread PRRT_kwDORWAxaM6m260s): re-run the ledger adapter
        # on the same durable surface the main gate gated on — the ledger
        # comment body is mutable, so the current-head clean verdict is
        # re-read, not remembered. A changed/stale ledger refuses here
        # (reviewer-state-changed at the caller).
        coderabbit_cli_local_ai_ledger_verdict "$platform_arg"
        if [ "$_adapter_ledger_clean" != "1" ]; then
          result="refused"
          reason="${_adapter_refusal_reason:-reviewer-evidence-unreadable}"
          reviewer_report="$platform_arg"
          refuse "${_adapter_refusal_reason:-reviewer-evidence-unreadable}"
        fi
        continue
      fi
      if ! supported_comment_only_reviewer_platform "$platform_arg"; then
        continue
      fi
      _revalidate_login="$(printf '%s\n' "$first_scan_bot_logins" | sed -n "s/^${platform_arg}://p" | head -1)"
      [ -n "$_revalidate_login" ] || return 1
      comment_only_reviewer_verdict "$platform_arg" "$_revalidate_login"
      [ "$scan_blocking_count" -eq 0 ] || return 1
      continue
    fi
    # Fail closed (PR #1818 finding 1, round 6): a failed or EMPTY re-fetch of
    # the check runs cannot confirm the earlier verdict still describes this
    # head — treat it as an unreadable state, never as "unchanged" success.
    if ! check_runs_arg="$(gh api "repos/$repo/commits/$head_sha/check-runs" --paginate --slurp 2>/dev/null)" || [ -z "$check_runs_arg" ]; then
      escalate revalidation-unreadable
    fi
    if ! check_state_arg="$(printf '%s\n' "$check_runs_arg" | jq -r --arg name "$check_name_arg" '
          [ .[].check_runs[]? | select(.name == $name) ]
          | sort_by(.started_at // .completed_at // "")
          | last
          | (if . == null then " " else ((.status // "") + " " + (.conclusion // "")) end)
        ' 2>/dev/null)" || [ -z "$check_state_arg" ]; then
      escalate revalidation-unreadable
    fi
    status_arg="${check_state_arg%% *}"
    conclusion_arg="${check_state_arg#* }"
    # started_at of the reselected (latest) check run — the notice probe and
    # the finding rescan below are both time-bounded to it.
    started_at_arg="$(printf '%s\n' "$check_runs_arg" | jq -r --arg name "$check_name_arg" '
          [ .[].check_runs[]? | select(.name == $name) ]
          | sort_by(.started_at // .completed_at // "")
          | last
          | (.started_at // .completed_at // .created_at // "")
        ' 2>/dev/null)" || escalate revalidation-unreadable
    # Same conclusion classes the main gate treats as a live verdict: `success`
    # plus Bugbot's `neutral`/`cancelled`/`skipped` — for those, a Bugbot
    # availability notice at/after the run timestamp must ALSO be absent (the
    # notice probe is the same one the main gate uses, so a rerun that hit a
    # quota limit mid-window is caught here too). Non-Bugbot
    # neutral/cancelled/skipped and every other non-success conclusion mean the
    # verdict no longer reads clean, so the state is stale.
    if [ "$status_arg" != "completed" ]; then
      return 1
    fi
    case "$conclusion_arg:$platform_arg" in
      success:*) ;;
      neutral:bugbot|cancelled:bugbot|skipped:bugbot)
        if bugbot_unavailable_notice_present "$(bot_login_for_platform bugbot)" "$started_at_arg"; then
          return 1
        fi
        ;;
      *) return 1 ;;
    esac
    # Rescan guard (PR #1818 finding 2, round 6): the first scan's findings
    # may belong to a superseded run — a same-SHA rerun can conclude success
    # while posting blocking comments, and the earlier scan never saw them.
    # Even when the reselected run is the same one, comment bodies are
    # mutable, so rescan unconditionally against the selected run's
    # timestamp, reusing the same fetch + filter functions as the main gate,
    # and refuse when anything blocks.
    first_scan_login="$(printf '%s\n' "$first_scan_bot_logins" | sed -n "s/^${platform_arg}://p" | head -1)"
    if [ -n "$first_scan_login" ]; then
      count_reviewer_blocking_findings "$first_scan_login" "$started_at_arg" "$started_at_arg" "$platform_arg"
      [ "$scan_blocking_count" -eq 0 ] || return 1
    fi
  done <<<"$ready_platforms"
  return 0
}

revalidate_ci_state() {
  local revalidate_pr_json normalized_arg baseline_arg pending_arg failing_arg
  if ! revalidate_pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup 2>/dev/null)" || [ -z "$revalidate_pr_json" ]; then
    return 1
  fi
  normalized_arg=""
  if ! normalized_arg="$(printf '%s\n' "$revalidate_pr_json" | normalize_status_check_rollup 2>/dev/null)" || [ -z "$normalized_arg" ]; then
    return 1
  fi
  baseline_arg=""
  if ! baseline_arg="$(printf '%s\n' "$normalized_arg" | jq -c --argjson names "$(printf '%s\n' "$reviewer_names_seen" | tr ',' '\n' | jq -R . | jq -s '.')" '
        [ .[]
          | (.name // .context // .workflowName // "unknown") as $n
          | select(($names | index($n)) | not)
        ]
      ' 2>/dev/null)"; then
    return 1
  fi
  pending_arg="$(printf '%s\n' "$baseline_arg" | jq '
    [ .[] | select(
        (((.status // "") != "") and ((.status // "") != "COMPLETED"))
        or (((.state // "") | ascii_upcase) == "EXPECTED")
        or (((.state // "") | ascii_upcase) == "PENDING")
        or (((.state // "") | ascii_upcase) == "IN_PROGRESS")
        or (((.state // "") | ascii_upcase) == "QUEUED")
      ) ] | length
  ' 2>/dev/null)" || return 1
  failing_arg="$(printf '%s\n' "$baseline_arg" | jq '
    [ .[] | select(
        (((.conclusion // "") | ascii_upcase) == "FAILURE")
        or (((.conclusion // "") | ascii_upcase) == "CANCELLED")
        or (((.conclusion // "") | ascii_upcase) == "TIMED_OUT")
        or (((.conclusion // "") | ascii_upcase) == "ACTION_REQUIRED")
        or (((.conclusion // "") | ascii_upcase) == "STARTUP_FAILURE")
        or (((.state // "") | ascii_upcase) == "FAILURE")
        or (((.state // "") | ascii_upcase) == "ERROR")
      ) ] | length
  ' 2>/dev/null)" || return 1
  if [ "$failing_arg" -gt 0 ]; then
    return 1
  fi
  if [ "$pending_arg" -gt 0 ] && [ "$label" != "ready-for-regression" ]; then
    return 1
  fi
  return 0
}

# --- Final pre-apply block (PR #1818 findings 2 and 3, round 9) --------------
# ONE ordered sequence, run once, immediately before the mutation. The
# invariant: every API-touching revalidation (reviewer revalidation, its
# finding rescan, the CI re-read) runs BEFORE the final headRefOid
# comparison, and that comparison is the LAST API call before `gh pr edit`
# — nothing may sit between the head check and the mutation.
# [reviewer revalidation + finding rescan] → [CI re-read] → [final head
# check] → [mutation].
# Rationale for the CI re-read's position: a CI rerun to pending/failure
# during the reviewer rescan window is missed by an earlier CI read, and
# unlike head drift it cannot be caught by the post-apply verification —
# the label already certified a red build. A failed/empty revalidation
# fetch escalates fail-closed inside revalidate_reviewer_state
# (`revalidation-unreadable`, round 6), never success.
if [ "$is_implementation_pr" = "true" ] && ! revalidate_reviewer_state; then
  refuse "reviewer-state-changed"
fi
if ! revalidate_ci_state; then
  refuse "reviewer-state-changed"
fi
current_head="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)" || escalate head-revalidate-failed
if [ -z "$current_head" ]; then
  escalate head-revalidate-failed
fi
if [ "$current_head" != "$head_sha" ]; then
  refuse "head-changed-before-apply"
fi

if ! gh pr edit "$pr_number" --repo "$repo" --add-label "$label" >/dev/null 2>&1; then
  escalate label-apply-failed
fi

# Re-read so a silently-dropped label is not reported as applied, and so a
# push that landed during the mutation is still caught: the label then
# certifies a head no verdict describes.
post_apply_json="$(gh pr view "$pr_number" --repo "$repo" --json labels,headRefOid 2>/dev/null)" || {
  # `--add-label` may have succeeded while this read failed: the label is on
  # the PR but unverified, so strip it before escalating (PR #1818 finding 3,
  # round 5) — never leave an unverified readiness label attached.
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
applied_labels="$(printf '%s\n' "$post_apply_json" | jq -r '.labels[].name' 2>/dev/null)" || {
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
if ! printf '%s\n' "$applied_labels" | grep -qx "$label"; then
  remove_readiness_label_best_effort "$label"
  escalate label-not-applied
fi
applied_head="$(printf '%s\n' "$post_apply_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || {
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
if [ "$applied_head" != "$head_sha" ]; then
  # The label now certifies a head no verdict describes. Remove it before
  # escalating so the new, unreviewed head does not carry a readiness label
  # between this refusal and whatever re-runs the gate. Best-effort only: a
  # failed removal logs a WARN and still escalates, so the human sees the
  # drift either way.
  remove_readiness_label_best_effort "$label"
  escalate head-changed-after-apply
fi

result="labeled"
reason="gate-passed"
emit_verdict
exit 0