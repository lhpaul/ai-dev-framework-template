#!/usr/bin/env bash
#
# validate-closing-keyword-scope.sh — warn when a pull request declares a
# closing keyword for an issue a sibling pull request is carrying.
#
# Every rule lives here rather than in the workflow YAML, so the logic is
# testable without GitHub. The workflow is routing.
#
# Usage:
#   validate-closing-keyword-scope.sh <pr_number> <owner/repo> [--publish]
#                                     [--sibling-list-unreadable]
#
# Without --publish the run computes its verdict, prints it, and writes
# nothing. Publication additionally requires the serialized workflow context
# (see require_publication_context) — a flag alone is a convention, not a
# guard, and the ordering guarantee rests on every writer being inside the
# target-keyed concurrency group.
#
# Exit codes:
#   0  verdict computed (and published, when publishing was requested and the
#      freshness re-read agreed)
#   1  publication was requested from outside the serialized context, or an
#      argument was invalid
#   2  a gate input could not be read AND the indeterminate outcome could not
#      itself be published

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/closing-keyword-lib.sh
. "$SCRIPT_DIR/closing-keyword-lib.sh"

OPT_OUT_LABEL="multi-issue-intentional"
OPT_OUT_LABEL_COLOR="0e8a16"
OPT_OUT_LABEL_DESCRIPTION="This pull request deliberately closes several issues; do not warn about its closing-keyword scope"

usage() {
  sed -n '3,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --------------------------------------------------------------------------
# Gate inputs
#
# Every input is read through record_input, which appends its name and read
# status to two parallel indexed arrays. Bash 3.2 (macOS system bash) has no
# associative arrays, hence the pair.
#
# The outcome is indeterminate when ANY recorded status is a failure. Stating
# it over the input set rather than over a list of known failures means an
# input added later is covered by construction: whoever adds it uses the same
# accessor, and the rule already applies to it.
# --------------------------------------------------------------------------

INPUT_NAMES=""
INPUT_STATUSES=""
INPUT_VALUES=""
LAST_INPUT_VALUE=""

reset_inputs() {
  INPUT_NAMES=""
  INPUT_STATUSES=""
  INPUT_VALUES=""
}

# record_input <name> <command...>
# Runs the command, records ok/failed under <name>, and leaves the captured
# stdout in LAST_INPUT_VALUE. Always returns 0: a failed read is data, not a
# control-flow event, and the caller decides nothing on its own.
record_input() {
  local name="$1"
  shift
  local value status
  set +e
  value="$("$@" 2>/dev/null)"
  status=$?
  set -e
  LAST_INPUT_VALUE="$value"
  INPUT_NAMES="${INPUT_NAMES}${name}
"
  if [ "$status" -eq 0 ]; then
    INPUT_STATUSES="${INPUT_STATUSES}ok
"
  else
    INPUT_STATUSES="${INPUT_STATUSES}failed
"
  fi
  # Length-prefixed, so no two field boundaries can be confused when the
  # values are concatenated into the freshness snapshot.
  INPUT_VALUES="${INPUT_VALUES}${name}:${#value}:${value}
"
  return 0
}

# The names published in an indeterminate check. Normally the current read's
# failures — but on the recovery path the current read has none, and the check
# would say "did not conclude" while naming nothing. Whatever failed is what a
# person needs to see, so the first read's failures are carried forward
# explicitly rather than recomputed from a state that no longer holds them.
REPORTED_UNREADABLE_OVERRIDE=""

reported_unreadable_inputs() {
  if [ -n "$REPORTED_UNREADABLE_OVERRIDE" ]; then
    printf '%s\n' "$REPORTED_UNREADABLE_OVERRIDE"
    return 0
  fi
  unreadable_inputs
}

unreadable_inputs() {
  local i=1 name status
  while :; do
    name="$(printf '%s' "$INPUT_NAMES" | sed -n "${i}p")"
    [ -n "$name" ] || break
    status="$(printf '%s' "$INPUT_STATUSES" | sed -n "${i}p")"
    if [ "$status" = "failed" ]; then
      printf '%s\n' "$name"
    fi
    i=$((i + 1))
  done
}

any_input_unreadable() {
  [ -n "$(unreadable_inputs)" ]
}

snapshot_hash() {
  printf '%s' "$INPUT_VALUES" | shasum -a 256 | awk '{print $1}'
}

# --------------------------------------------------------------------------
# Ordering stamp
# --------------------------------------------------------------------------

STAMP_STARTED=""
STAMP_RUN=""
STAMP_ATTEMPT=""

init_stamp() {
  STAMP_STARTED="$(closing_keyword_scope_started_at)"
  STAMP_RUN="${GITHUB_RUN_ID:-0}"
  STAMP_ATTEMPT="${GITHUB_RUN_ATTEMPT:-0}"
}

own_stamp() {
  printf 'started=%s run=%s attempt=%s' "$STAMP_STARTED" "$STAMP_RUN" "$STAMP_ATTEMPT"
}

# parse_stamp_field <field> <text>
# Echoes the field's value from a stamp, or nothing when absent.
parse_stamp_field() {
  printf '%s' "$2" | sed -n "s/.*${1}=\\([^ ]*\\).*/\\1/p" | head -1
}

# stamp_is_later_than_ours <stamp-bearing text>
# True when the text carries a well-formed stamp that sorts strictly AFTER
# this run's own. A missing or unparseable stamp counts as older than any run,
# so a degenerate artifact is adopted rather than becoming permanently
# un-writable.
#
# The order is total over (started, run, attempt) taken in that order:
# `started` as a string, which is why it is fixed-width ISO-8601 UTC; then
# `run` and `attempt` numerically. `run` and `attempt` are NOT evidence of
# start order — GitHub documents run ids as unique, not chronological. They
# decide only an exact `started` tie, and only so that every writer agrees on
# the same winner instead of resolving it by completion order.
stamp_is_later_than_ours() {
  local text="$1"
  local started run attempt
  started="$(parse_stamp_field started "$text")"
  run="$(parse_stamp_field run "$text")"
  attempt="$(parse_stamp_field attempt "$text")"

  case "$started" in
    ????-??-??T??:??:??.???Z) : ;;
    *) return 1 ;;
  esac
  case "$run" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$attempt" in
    ''|*[!0-9]*) return 1 ;;
  esac

  if [ "$started" \> "$STAMP_STARTED" ]; then return 0; fi
  if [ "$started" \< "$STAMP_STARTED" ]; then return 1; fi
  if [ "$run" -gt "$STAMP_RUN" ]; then return 0; fi
  if [ "$run" -lt "$STAMP_RUN" ]; then return 1; fi
  if [ "$attempt" -gt "$STAMP_ATTEMPT" ]; then return 0; fi
  return 1
}

# --------------------------------------------------------------------------
# Publication context
#
# `--publish` alone would be a convention, not a guard: it is a public option,
# and "the workflow is the only caller" is a claim about today's callers
# rather than a property of the script. The ordering guarantee rests on every
# writer being serialized by the target-keyed concurrency group, so writing
# also requires being inside the job that group covers.
#
# A shell script cannot prove its own execution context. Someone who exports
# these variables by hand can publish from outside the group. The guard's job
# is to make that a deliberate forgery of the CI environment rather than an
# ordinary command-line mistake.
# --------------------------------------------------------------------------

EXPECTED_WORKFLOW_NAME="Closing-keyword scope"
EXPECTED_JOB_ID="validate"

require_publication_context() {
  if [ "${GITHUB_ACTIONS:-}" != "true" ] \
    || [ "${GITHUB_WORKFLOW:-}" != "$EXPECTED_WORKFLOW_NAME" ] \
    || [ "${GITHUB_JOB:-}" != "$EXPECTED_JOB_ID" ]; then
    echo "ERROR: publication_context_not_serialized — --publish requires running inside the '${EXPECTED_JOB_ID}' job of the '${EXPECTED_WORKFLOW_NAME}' workflow, which is what serializes writers per target pull request." >&2
    return 1
  fi
  return 0
}

# --------------------------------------------------------------------------
# Reading the pull request
# --------------------------------------------------------------------------

gh_pr_field() {
  gh pr view "$PR_NUMBER" --repo "$REPO" --json "$1" --jq "$2"
}

gh_default_branch() {
  gh api "repos/${REPO}" --jq '.default_branch'
}

# Full pagination, not `gh pr list --limit N`. A ceiling would silently drop an
# owner or a claimant past the cut, and the verdict would be wrong rather than
# unavailable — the worst failure shape this feature has, because a dropped
# owner reads as "no sibling carries it" and the run goes silent.
gh_open_pr_list() {
  gh api "repos/${REPO}/pulls?state=open&per_page=100" --paginate \
    --jq '[.[] | {number, headRefName: .head.ref, title, body: (.body // ""), baseRefName: .base.ref}]' \
  | jq -sc 'add // []'
}

# `--paginate` with a `--jq` that wraps each page in `[...]` emits ONE ARRAY
# PER PAGE, not one array. Every consumer below sorts and takes `.[0]`, so
# without slurping they would do that per page and return several answers —
# several ids for one PATCH URL, and a stamp chosen from the wrong page. The
# `jq -sc 'add // []'` merges the pages first, and `// []` covers the
# no-pages-at-all case, where `add` is null rather than an empty array.
gh_existing_report() {
  gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" --paginate \
    --jq '[.[] | {id, body: (.body // ""), created_at}]' \
  | jq -sc 'add // []'
}

# The listing is filter=all with full pagination on purpose: the default
# filter=latest returns only the most recent run per name, which would make a
# duplicate unobservable and the "oldest match wins" rule undecidable.
gh_existing_checks() {
  gh api "repos/${REPO}/commits/${HEAD_SHA}/check-runs?filter=all&per_page=100" --paginate \
    --jq "[.check_runs[] | select(.name == \"${CLOSING_KEYWORD_SCOPE_CHECK_NAME}\" and .external_id == \"${CLOSING_KEYWORD_SCOPE_CHECK_EXTERNAL_ID}\") | {id, started_at, conclusion, summary: (.output.summary // \"\")}]" \
  | jq -sc 'add // []'
}

read_all_inputs() {
  reset_inputs

  record_input title gh_pr_field title '.title // ""'
  PR_TITLE="$LAST_INPUT_VALUE"
  record_input description gh_pr_field body '.body // ""'
  PR_BODY="$LAST_INPUT_VALUE"
  record_input base_branch gh_pr_field baseRefName '.baseRefName // ""'
  PR_BASE="$LAST_INPUT_VALUE"
  record_input head_branch gh_pr_field headRefName '.headRefName // ""'
  PR_HEAD_BRANCH="$LAST_INPUT_VALUE"
  record_input pr_state gh_pr_field state '.state // ""'
  PR_STATE="$LAST_INPUT_VALUE"
  record_input labels gh_pr_field labels '[.labels[].name] | join("\n")'
  PR_LABELS="$LAST_INPUT_VALUE"
  record_input default_branch gh_default_branch
  DEFAULT_BRANCH="$LAST_INPUT_VALUE"

  # resolve-targets may already have found the sibling list unreadable. It is
  # recorded here as the same kind of failure rather than a separate code
  # path, so the indeterminate rule covers it by construction.
  if [ "$SIBLING_LIST_UNREADABLE" = "true" ]; then
    record_input sibling_pull_requests false
    SIBLING_LIST=""
  else
    record_input sibling_pull_requests gh_open_pr_list
    SIBLING_LIST="$LAST_INPUT_VALUE"
  fi

  record_input existing_report gh_existing_report
  EXISTING_REPORT_JSON="$LAST_INPUT_VALUE"
  record_input existing_check gh_existing_checks
  EXISTING_CHECK_JSON="$LAST_INPUT_VALUE"
}

# --------------------------------------------------------------------------
# Which references the description contributes
#
# The closer this pull request will meet decides how the text is filtered:
# merging to the default branch, the platform closes from the description
# alone; merging anywhere else, this repository's own cleanup reads title and
# description as one text, so a fence opened in the title suppresses what
# follows it in the description.
#
# In the concatenated case, attribution is differential rather than
# positional. A first pass filters `title + "\n" + description`; a second
# filters the same text with every closing-keyword token in the DESCRIPTION
# mangled length-preservingly. The reported set is the multiset difference.
#
# Multiset, not set: when the title and description both name issue 12 and
# both are live, 12 appears twice in the first pass and once in the second,
# and the difference correctly yields one description-contributed reference.
#
# An earlier design put a sentinel line between title and description and
# reported what followed it. A title that opens a fence which the description
# CLOSES part-way through, before a later live `Closes #12`, breaks it: the
# sentinel is inside the fence and filtered away, the keyword after the
# closing fence is not, and the run would have gone silent on a reference the
# closer will act on. Differential filtering never reasons about position; it
# asks the filter itself, twice, over structurally identical text.
# --------------------------------------------------------------------------

# multiset_difference <file-a> <file-b>
# Echoes the lines of A that B does not account for, respecting multiplicity.
multiset_difference() {
  sort "$1" > "$1.sorted"
  sort "$2" > "$2.sorted"
  comm -23 "$1.sorted" "$2.sorted"
}

# description_live_refs
# Echoes the issue numbers this pull request's DESCRIPTION contributes as live
# closing references, one per line, sorted and deduplicated for reporting.
# Returns 1 if any filtering stage failed.
description_live_refs() {
  local work all_file mangled_file mangled_description
  work="$(mktemp -d)"
  all_file="$work/all"
  mangled_file="$work/mangled"

  if [ "$PR_BASE" = "$DEFAULT_BRANCH" ]; then
    # The platform closes from the description alone and never saw the title,
    # so there is nothing to attribute: everything live here is the
    # description's.
    if ! printf '%s' "$PR_BODY" | closing_keyword_live_refs > "$all_file"; then
      rm -rf "$work"
      return 1
    fi
    sort -un "$all_file"
    rm -rf "$work"
    return 0
  fi

  if ! printf '%s\n%s' "$PR_TITLE" "$PR_BODY" | closing_keyword_live_refs > "$all_file"; then
    rm -rf "$work"
    return 1
  fi
  if ! mangled_description="$(printf '%s' "$PR_BODY" | closing_keyword_mangle)"; then
    rm -rf "$work"
    return 1
  fi
  if ! printf '%s\n%s' "$PR_TITLE" "$mangled_description" | closing_keyword_live_refs > "$mangled_file"; then
    rm -rf "$work"
    return 1
  fi

  multiset_difference "$all_file" "$mangled_file" | sort -un
  rm -rf "$work"
  return 0
}

# --------------------------------------------------------------------------
# Ownership
#
# There is exactly one ownership signal: an implementation branch whose name
# carries the issue number. Platform-derived issue links are never consulted —
# GitHub creates one from the very closing keyword this feature examines, so a
# pull request that wrongly claimed an issue would be linked to it BECAUSE of
# that claim, read as the issue's owner, and suppress the warning it was
# supposed to produce.
#
# Spec and plan branches are never owners: they carry documentation for an
# issue, not the work that closes it.
# --------------------------------------------------------------------------

IMPLEMENTATION_BRANCH_PREFIXES='^(feature|fix|refactor|hotfix|backport/hotfix)/'
# The team prefix is case-INSENSITIVE. The spec's own canonical example is
# lowercase — `fix/lh-97-some-slug` — and an uppercase-only pattern would leave
# every lowercase team-prefixed sibling invisible, which is the spec's stated
# reason for reading the form at all: "the warning would go silent on precisely
# the mistake it exists to catch".
#
# The cost is real and the spec accepts it. A descriptive slug that happens to
# start `<word>-<number>-` — `fix/retro-517-doc-gaps` — is indistinguishable in
# shape from a team-prefixed identifier, so it reads as naming issue 517. That
# produces a visible, correctable warning; missing a team-prefixed sibling
# produces silence, which is the failure nobody notices.
BRANCH_OWNS_ISSUE_PATTERN_PREFIX="${IMPLEMENTATION_BRANCH_PREFIXES}([A-Za-z][A-Za-z0-9]*-)?"

# is_implementation_branch <branch>
# The spec's precondition: this validation is for IMPLEMENTATION pull requests.
# A spec, plan, release or docs pull request is not one, and warning on it
# would be noise about a closing keyword that is doing its job — a spec PR
# legitimately declares the issue it specifies. Ownership is a separate
# question with a stricter pattern; this is only "is this the kind of pull
# request the feature is about".
is_implementation_branch() {
  printf '%s' "$1" | grep -qE "$IMPLEMENTATION_BRANCH_PREFIXES"
}

branch_owns_issue() {
  local branch="$1" issue="$2"
  printf '%s' "$branch" | grep -qE "${BRANCH_OWNS_ISSUE_PATTERN_PREFIX}${issue}(-|$)"
}

# owners_of_issue <issue>
# Echoes the numbers of open pull requests whose head branch names the issue.
owners_of_issue() {
  local issue="$1" number branch
  printf '%s' "$SIBLING_LIST" | jq -r '.[] | "\(.number)\t\(.headRefName)"' 2>/dev/null \
  | while IFS="$(printf '\t')" read -r number branch; do
      [ -n "$number" ] || continue
      if branch_owns_issue "$branch" "$issue"; then
        printf '%s\n' "$number"
      fi
    done
}

# --------------------------------------------------------------------------
# The verdict
#
# VERDICT is one of:
#   silent        nothing to report; a published report, if any, is deleted
#   warn          REPORT_ISSUES names the contested issues and their owners
#   indeterminate an input could not be read; an existing report is left
#                 exactly as it was and a neutral check records what failed
# --------------------------------------------------------------------------

VERDICT=""
REPORT_ROWS=""
LABEL_WARNING=""
NOT_VALIDATED_REASON=""

decide() {
  local refs issue owners owner_count sole_owner

  if any_input_unreadable; then
    VERDICT="indeterminate"
    return 0
  fi

  # A closed pull request is not evaluated at all. resolve-targets drops it
  # from the target list; this is the second half of that check, because the
  # list is computed before the matrix leg runs and a pull request can close
  # in between.
  if [ "$PR_STATE" != "OPEN" ]; then
    VERDICT="silent"
    NOT_VALIDATED_REASON="target_is_not_open"
    return 0
  fi

  # The spec's precondition: an implementation pull request. Checked before the
  # opt-out and before any label provisioning, so a spec or release pull
  # request neither warns nor causes a repository-wide label to be created on
  # its behalf.
  if ! is_implementation_branch "$PR_HEAD_BRANCH"; then
    VERDICT="silent"
    NOT_VALIDATED_REASON="not_an_implementation_branch"
    return 0
  fi

  if printf '%s' "$PR_LABELS" | grep -Fxq "$OPT_OUT_LABEL"; then
    VERDICT="silent"
    return 0
  fi

  if ! refs="$(description_live_refs)"; then
    # Filtering is a gate input like any other; a failure here is unreadable
    # input, not a clean result.
    INPUT_NAMES="${INPUT_NAMES}description_filtering
"
    INPUT_STATUSES="${INPUT_STATUSES}failed
"
    VERDICT="indeterminate"
    return 0
  fi

  REPORT_ROWS=""
  for issue in $refs; do
    [ -n "$issue" ] || continue
    owners="$(owners_of_issue "$issue")"
    owner_count="$(printf '%s' "$owners" | grep -c '[0-9]' || true)"

    # No owner: this pull request may legitimately be the first and only one
    # to address the issue. Two or more: ownership is contested, and guessing
    # is the mistake this feature exists to catch. Itself: in scope.
    [ "$owner_count" -eq 1 ] || continue
    sole_owner="$(printf '%s' "$owners" | tr -d '[:space:]')"
    [ "$sole_owner" != "$PR_NUMBER" ] || continue

    REPORT_ROWS="${REPORT_ROWS}| #${issue} | #${sole_owner} |
"
  done

  if [ -n "$REPORT_ROWS" ]; then
    VERDICT="warn"
  else
    VERDICT="silent"
  fi
  return 0
}

# --------------------------------------------------------------------------
# Publication
# --------------------------------------------------------------------------

ensure_opt_out_label_exists() {
  if gh label view "$OPT_OUT_LABEL" --repo "$REPO" >/dev/null 2>&1; then
    return 0
  fi
  if gh label create "$OPT_OUT_LABEL" --repo "$REPO" \
      --color "$OPT_OUT_LABEL_COLOR" \
      --description "$OPT_OUT_LABEL_DESCRIPTION" >/dev/null 2>&1; then
    return 0
  fi

  # A failed create is not the same as an absent label. Two validations can
  # both see it missing; the second's create then fails BECAUSE the first
  # succeeded. Re-checking is what tells "someone beat me to it" — the outcome
  # the spec asks this to tolerate — apart from a genuine provisioning failure.
  if gh label view "$OPT_OUT_LABEL" --repo "$REPO" >/dev/null 2>&1; then
    return 0
  fi

  # An opt-out an author cannot reach is not an opt-out, so the warning says
  # so — but a failed provisioning never suppresses the warning itself.
  LABEL_WARNING="The \`${OPT_OUT_LABEL}\` label could not be created, so applying it may fail. Ask a maintainer to add it."
  echo "WARN: could not provision the ${OPT_OUT_LABEL} label" >&2
  return 0
}

report_body() {
  printf '%s%s -->\n' "$CLOSING_KEYWORD_SCOPE_MARKER_PREFIX" "$(own_stamp)"
  printf '\n### Closing-keyword scope\n\n'
  printf 'This pull request declares a closing keyword for an issue another open pull request is carrying. Merging it would close that issue on this work rather than on the work that addresses it.\n\n'
  printf '| Issue this PR declares | Pull request carrying it |\n| --- | --- |\n'
  printf '%s' "$REPORT_ROWS"
  # shellcheck disable=SC2016  # backticks are markdown, not command substitution
  printf '\nThis is advisory and never blocks a merge. If this pull request deliberately closes several issues, apply the `%s` label and the warning clears.\n' "$OPT_OUT_LABEL"
  if [ -n "$LABEL_WARNING" ]; then
    printf '\n> %s\n' "$LABEL_WARNING"
  fi
}

check_summary() {
  printf '%s%s -->\n' "$CLOSING_KEYWORD_SCOPE_MARKER_PREFIX" "$(own_stamp)"
  case "$VERDICT" in
    indeterminate)
      printf '\nThe validation did not conclude. These inputs could not be read:\n\n'
      reported_unreadable_inputs | sed 's/^/- /'
      printf '\nAn existing report, if any, was left exactly as it was rather than cleared on incomplete information.\n'
      ;;
    warn)
      printf '\nThis pull request declares a closing keyword for an issue a sibling pull request is carrying. See the report comment.\n'
      ;;
    *)
      printf '\nNo closing keyword on this pull request names an issue a sibling is carrying.\n'
      ;;
  esac
}

# find_report_comment_ids
# Echoes the ids of every comment carrying this feature's marker, oldest
# first. Lookup is the marker PREFIX at line start, never the whole marker:
# the marker carries the stamp, so an exact match would never find anything
# the writer emitted. The trailing space in the prefix is what terminates the
# version — without it, a future v10 report would match as a v1 duplicate.
find_report_comment_ids() {
  printf '%s' "$EXISTING_REPORT_JSON" \
    | jq -r --arg prefix "$CLOSING_KEYWORD_SCOPE_MARKER_PREFIX" \
        '[.[] | select(.body | split("\n") | any(startswith($prefix)))]
         | sort_by(.created_at, .id) | .[].id' 2>/dev/null
}

existing_report_stamp() {
  printf '%s' "$EXISTING_REPORT_JSON" \
    | jq -r --arg prefix "$CLOSING_KEYWORD_SCOPE_MARKER_PREFIX" \
        '[.[] | select(.body | split("\n") | any(startswith($prefix)))]
         | sort_by(.created_at, .id) | .[0].body // ""' 2>/dev/null \
    | head -1
}

existing_check_id() {
  printf '%s' "$EXISTING_CHECK_JSON" | jq -r 'sort_by(.started_at, .id) | .[0].id // empty' 2>/dev/null | head -1
}

existing_check_stamp() {
  printf '%s' "$EXISTING_CHECK_JSON" | jq -r 'sort_by(.started_at, .id) | .[0].summary // ""' 2>/dev/null | head -1
}

# would_overwrite_a_later_run
# True when either published artifact carries a stamp that sorts strictly
# after this run's own. With no marked comment present the stamp is read from
# the check run alone — that is the normal state after a clean result, not a
# missing-evidence case, and it is why the check run is never deleted.
would_overwrite_a_later_run() {
  local comment_stamp check_stamp
  comment_stamp="$(existing_report_stamp)"
  check_stamp="$(existing_check_stamp)"
  if [ -n "$comment_stamp" ] && stamp_is_later_than_ours "$comment_stamp"; then
    return 0
  fi
  if [ -n "$check_stamp" ] && stamp_is_later_than_ours "$check_stamp"; then
    return 0
  fi
  return 1
}

publish_check_run() {
  local conclusion="$1" id
  id="$(existing_check_id)"
  local payload
  payload="$(jq -n \
    --arg name "$CLOSING_KEYWORD_SCOPE_CHECK_NAME" \
    --arg external_id "$CLOSING_KEYWORD_SCOPE_CHECK_EXTERNAL_ID" \
    --arg head_sha "$HEAD_SHA" \
    --arg conclusion "$conclusion" \
    --arg summary "$(check_summary)" \
    '{name: $name, external_id: $external_id, head_sha: $head_sha,
      status: "completed", conclusion: $conclusion,
      output: {title: $name, summary: $summary}}')"

  if [ -n "$id" ]; then
    # Update in place, so a conclusive re-run replaces the neutral conclusion
    # on the same check instead of leaving two. When the listing returned more
    # than one match the oldest wins: check runs cannot be deleted through the
    # API, so reconciliation is deterministic selection, not cleanup.
    printf '%s' "$payload" | gh api --method PATCH "repos/${REPO}/check-runs/${id}" --input - >/dev/null
  else
    printf '%s' "$payload" | gh api --method POST "repos/${REPO}/check-runs" --input - >/dev/null
  fi
}

publish_report() {
  local ids first rest body id
  ids="$(find_report_comment_ids)"
  first="$(printf '%s\n' "$ids" | head -1)"
  rest="$(printf '%s\n' "$ids" | tail -n +2)"

  if [ "$VERDICT" = "silent" ]; then
    # Silence is the clean signal. A comment announcing that nothing is wrong
    # is not silence, so a clean result deletes the report rather than editing
    # it to a clean state. The ordering stamp goes with it; the check run,
    # which cannot be deleted, carries it from here.
    for id in $ids; do
      [ -n "$id" ] || continue
      if ! gh api --method DELETE "repos/${REPO}/issues/comments/${id}" >/dev/null 2>&1; then
        # A failed delete leaves a stale warning standing. Say so rather than
        # swallowing it: the next event re-runs and tries again, and a log
        # line is what tells a human the difference between "the warning is
        # correct" and "the warning could not be cleared".
        echo "WARN: could not delete report comment ${id} on #${PR_NUMBER}; the stale warning survives until the next run." >&2
      fi
    done
    return 0
  fi

  body="$(report_body)"
  if [ -n "$first" ]; then
    jq -n --arg body "$body" '{body: $body}' \
      | gh api --method PATCH "repos/${REPO}/issues/comments/${first}" --input - >/dev/null
    # Inherited duplicates are reconciled, not ignored: the oldest survives so
    # the surviving comment id is deterministic regardless of which run gets
    # here first.
    for id in $rest; do
      [ -n "$id" ] || continue
      if ! gh api --method DELETE "repos/${REPO}/issues/comments/${id}" >/dev/null 2>&1; then
        # The surviving duplicate is cosmetic — the oldest comment already
        # carries the current result — so this does not fail the run, but it
        # is not silent either.
        echo "WARN: could not delete duplicate report comment ${id} on #${PR_NUMBER}." >&2
      fi
    done
  else
    jq -n --arg body "$body" '{body: $body}' \
      | gh api --method POST "repos/${REPO}/issues/${PR_NUMBER}/comments" --input - >/dev/null
  fi
}

publish() {
  case "$VERDICT" in
    indeterminate)
      # The spec requires a visible non-conclusion. Declining to publish would
      # trade a visible non-conclusion for an invisible one — the failure the
      # whole indeterminate design exists to prevent.
      publish_check_run neutral
      # An existing report is left exactly as it was: it was written on
      # complete information, and this run does not have any.
      return 0
      ;;
    warn)
      ensure_opt_out_label_exists
      ;;
  esac

  # The check run is written FIRST, then the comment. It carries the ordering
  # stamp and cannot be deleted, so a run that dies between the two leaves
  # durable evidence of what it decided; the next run reads that stamp, sees
  # its own is later, and republishes both. The reverse order would leave a
  # comment no stamp accounts for.
  publish_check_run success
  publish_report
  return 0
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

PR_NUMBER=""
REPO=""
PUBLISH="false"
SIBLING_LIST_UNREADABLE="false"
HEAD_SHA=""

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --publish) PUBLISH="true" ;;
      --sibling-list-unreadable) SIBLING_LIST_UNREADABLE="true" ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 1 ;;
      *)
        if [ -z "$PR_NUMBER" ]; then PR_NUMBER="$1"
        elif [ -z "$REPO" ]; then REPO="$1"
        else echo "ERROR: unexpected argument: $1" >&2; exit 1
        fi
        ;;
    esac
    shift
  done

  case "$PR_NUMBER" in
    ''|*[!0-9]*) echo "ERROR: <pr_number> must be a number." >&2; usage >&2; exit 1 ;;
  esac
  case "$REPO" in
    */*) : ;;
    *) echo "ERROR: <owner/repo> is required." >&2; usage >&2; exit 1 ;;
  esac
}

main() {
  parse_args "$@"

  if [ "$PUBLISH" = "true" ] && ! require_publication_context; then
    exit 1
  fi

  init_stamp

  # The fork guard, inner half. The workflow's job-level `if:` is the outer
  # half; this one also holds when the validator is invoked directly.
  local head_repo
  if ! head_repo="$(gh_pr_field headRepository '.headRepository.owner.login + "/" + .headRepository.name' 2>/dev/null)"; then
    echo "ERROR: could not read the pull request's head repository; refusing to continue." >&2
    exit 2
  fi
  if [ "$head_repo" != "$REPO" ]; then
    echo "SKIP: pull request #${PR_NUMBER} originates from ${head_repo}, not ${REPO}. Fork pull requests are not validated."
    echo "VERDICT=skipped_fork"
    exit 0
  fi

  if ! HEAD_SHA="$(gh_pr_field headRefOid '.headRefOid')"; then
    echo "ERROR: could not read the pull request's head SHA; refusing to continue." >&2
    exit 2
  fi

  read_all_inputs
  local snapshot_before
  snapshot_before="$(snapshot_hash)"
  decide

  echo "VERDICT=${VERDICT}"
  [ -z "$NOT_VALIDATED_REASON" ] || echo "NOT_VALIDATED=${NOT_VALIDATED_REASON}"
  echo "STAMP=$(own_stamp)"
  if [ "$VERDICT" = "indeterminate" ]; then
    echo "UNREADABLE_INPUTS=$(unreadable_inputs | tr '\n' ',' | sed 's/,$//')"
  fi
  if [ -n "$REPORT_ROWS" ]; then
    printf 'REPORT_ROWS<<EOF\n%sEOF\n' "$REPORT_ROWS"
  fi

  if [ "$PUBLISH" != "true" ]; then
    echo "PUBLISHED=false (no --publish)"
    exit 0
  fi

  # "Not validated" means exactly that: no writes at all, not a clean result
  # published quietly. A closed target must not be written to — it can close
  # between the matrix resolving and this leg running — and a
  # non-implementation pull request is outside the feature's precondition, so
  # neither its report nor the shared opt-out label is this run's business.
  if [ -n "$NOT_VALIDATED_REASON" ]; then
    echo "PUBLISHED=false (${NOT_VALIDATED_REASON})"
    exit 0
  fi

  # Freshness. Re-read every input through the same accessor and compare the
  # snapshot. Equal means publish; different means abandon — no write at all,
  # because the decision was made against a state that no longer holds and the
  # next event recomputes from the current one.
  local decided_verdict="$VERDICT"
  local first_read_unreadable
  first_read_unreadable="$(unreadable_inputs)"
  read_all_inputs

  # A failed RE-READ is an unreadable input, not a changed one, and the two
  # need different answers. The spec requires any unreadable input to leave the
  # existing report untouched and publish a neutral check naming what failed —
  # so this path publishes the indeterminate outcome rather than abandoning.
  # Abandoning would have swallowed the non-conclusion entirely, which is the
  # failure the whole indeterminate design exists to prevent. It is checked
  # BEFORE the hash comparison, because a failed read also changes the hash and
  # would otherwise be misread as a change.
  #
  # The FIRST read's failure counts too, and read_all_inputs has just cleared
  # it. An input that failed then and recovered now would otherwise reach the
  # hash comparison, differ, and abandon — publishing nothing about a read that
  # did fail. The spec asks for a visible indeterminate outcome for any gate
  # input failure, so recovery on the second read does not erase the first.
  if [ "$decided_verdict" = "indeterminate" ] && ! any_input_unreadable; then
    VERDICT="indeterminate"
    # The re-read succeeded, so the current failure list is empty. Publishing
    # that would produce a check saying "did not conclude" while naming
    # nothing, which tells a reader less than no check at all.
    REPORTED_UNREADABLE_OVERRIDE="$first_read_unreadable"
    echo "VERDICT_ON_RECHECK=indeterminate (the first read failed; the second recovered)"
    echo "UNREADABLE_INPUTS_ON_RECHECK=$(printf '%s' "$first_read_unreadable" | tr '\n' ',' | sed 's/,$//')"
    publish
    echo "PUBLISHED=true"
    exit 0
  fi

  if any_input_unreadable; then
    VERDICT="indeterminate"
    # A distinct key rather than a second VERDICT= line: two conflicting
    # VERDICT= lines in one run's log is exactly the kind of output that gets
    # misread by a person and by whatever parses it next.
    echo "VERDICT_ON_RECHECK=indeterminate"
    echo "UNREADABLE_INPUTS_ON_RECHECK=$(unreadable_inputs | tr '\n' ',' | sed 's/,$//')"
    publish
    echo "PUBLISHED=true"
    exit 0
  fi

  local snapshot_after
  snapshot_after="$(snapshot_hash)"
  if [ "$snapshot_before" != "$snapshot_after" ]; then
    # Readable, and different. The decision was made against a state that no
    # longer holds; the next event recomputes from the current one, so nothing
    # is lost by writing nothing.
    echo "ABANDONED=inputs_changed_between_read_and_write"
    echo "PUBLISHED=false"
    exit 0
  fi
  VERDICT="$decided_verdict"

  if would_overwrite_a_later_run; then
    echo "ABANDONED=a_later_started_run_already_published"
    echo "PUBLISHED=false"
    exit 0
  fi

  publish
  echo "PUBLISHED=true"
  exit 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
