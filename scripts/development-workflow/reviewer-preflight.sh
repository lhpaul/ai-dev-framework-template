#!/usr/bin/env bash
# reviewer-preflight.sh — cross-check reviewer configuration before dispatch.
#
# Issue #1561: before Protocol 91 dispatches an item, this script cross-checks
# the shared workflow reviewer configuration, the machine-local override, and
# each reviewer platform's own configuration, and reports a disagreement
# rather than letting the run proceed on an assumption. See
# docs/specs/developments/20260911230501_1561-reviewer-preflight/ for the
# spec and implementation plan.
#
# Read-only: this script runs only git show / git fetch / git rev-parse /
# git status --porcelain, gh pr view, and python3 reads of temporary copies.
# It never checks out, commits, pushes, opens a pull request, comments,
# labels, or writes any tracked file under --repo-root. git fetch updates
# only remote-tracking refs under .git/, not a tracked file or the working
# tree, and is required by the spec's "refreshed from the remote before
# reading" rule for the shared configuration on the pr-resume path. The
# pr-resume path also fetches the PR head into a temporary ref so it can be
# read the same way as every other ref this script reads; that ref is
# deleted again before exit (see the cleanup trap) and never persists.
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 3; }

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

PREFLIGHT_BUDGET_SECONDS=15
PREFLIGHT_PER_PLATFORM_CAP_SECONDS=4
if [ "${WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE:-0}" = 1 ]; then
  case "${WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS:-15}" in
    [1-9]|[1-9][0-9]) PREFLIGHT_BUDGET_SECONDS=${WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS:-15} ;;
    *) fail 'test budget must be a positive integer' ;;
  esac
  case "${WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS:-4}" in
    [1-9]|[1-9][0-9]) PREFLIGHT_PER_PLATFORM_CAP_SECONDS=${WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS:-4} ;;
    *) fail 'test per-platform cap must be a positive integer' ;;
  esac
fi
SECONDS=0

repo_root= mode= target_base= branch= pr= owner= repo=
remaining_stages_raw= remaining_stages_provided=0
pr_state_raw= json_output=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root|--mode|--target-base|--branch|--pr|--owner|--repo|--remaining-stages|--pr-state)
      [ "$#" -ge 2 ] || fail "missing value for $1"
      case "$1" in
        --repo-root) repo_root=$2 ;;
        --mode) mode=$2 ;;
        --target-base) target_base=$2 ;;
        --branch) branch=$2 ;;
        --pr) pr=$2 ;;
        --owner) owner=$2 ;;
        --repo) repo=$2 ;;
        --remaining-stages) remaining_stages_raw=$2; remaining_stages_provided=1 ;;
        --pr-state) pr_state_raw=$2 ;;
      esac
      shift 2 ;;
    --json) json_output=true; shift ;;
    --help)
      printf 'Usage: %s --repo-root <path> --mode pre-dispatch|branch-resume|pr-resume --target-base <branch> [--branch <name>] [--pr <number>] [--owner <owner> --repo <repo>] [--remaining-stages <csv>] [--pr-state <bucket=state,...>] [--json]\n' "$0"
      exit 0 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[ -n "$repo_root" ] || fail 'missing --repo-root'
[ -d "$repo_root" ] && [ -r "$repo_root" ] && [ -x "$repo_root" ] || fail '--repo-root must be a readable directory'
case "$mode" in pre-dispatch|branch-resume|pr-resume) ;; *) fail '--mode must be pre-dispatch, branch-resume, or pr-resume' ;; esac
# The preflight contract classifies an empty, unresolved, or malformed
# --target-base as OUTCOME=prerequisite-failed (exit 2, with
# PREREQUISITE_DETAIL) — the same documented outcome reviewer_preflight.py
# itself raises for other target_base problems. A bare `fail()` (exit 3,
# unstructured stderr) would route these malformed-input cases through the
# wrong documented outcome, even though validation must still happen
# before git ever sees the value.
prerequisite_failed_report() {
  local detail=$1
  if [ "$json_output" = true ]; then
    jq -n --arg detail "$detail" --argjson elapsed "$SECONDS" --argjson budget "$PREFLIGHT_BUDGET_SECONDS" \
      '{outcome:"prerequisite-failed",outcome_label:"Prerequisite not met",checked_shared_config_ref:"",checked_platform_config_ref:"",local_override_state:"none",platforms:[],prerequisite_detail:$detail,elapsed_seconds:$elapsed,budget_seconds:$budget}'
  else
    print_kv_escaped OUTCOME prerequisite-failed
    print_kv_escaped OUTCOME_LABEL 'Prerequisite not met'
    print_kv_escaped CHECKED_SHARED_CONFIG_REF ''
    print_kv_escaped CHECKED_PLATFORM_CONFIG_REF ''
    print_kv_escaped LOCAL_OVERRIDE_STATE none
    print_kv_escaped PREREQUISITE_DETAIL "$detail"
    print_kv_escaped PLATFORM_COUNT 0
    print_kv_escaped ELAPSED_SECONDS "$SECONDS"
    print_kv_escaped BUDGET_SECONDS "$PREFLIGHT_BUDGET_SECONDS"
  fi
  exit 2
}
[ -n "$target_base" ] || prerequisite_failed_report 'missing --target-base'
# --target-base and --branch reach `git fetch origin "<value>"` as a bare
# CLI argument that git itself parses, not merely a branch name string:
# `git fetch` accepts full "<src>:<dst>[+]" refspec syntax there (so
# "develop:refs/heads/injected", or a leading '+' forcing an overwrite,
# would create or update an arbitrary local ref), AND git parses a
# leading-dash value as an OPTION regardless of its position after
# "origin" — confirmed exploitable: "--upload-pack=./evil" runs an
# arbitrary repo-root program during the fetch. check-ref-format alone
# validates ref-name shape but does not reject either risk; both must be
# rejected explicitly before any value reaches git.
is_option_or_refspec_like() {
  case "$1" in
    +*|-*) return 0 ;;
  esac
  if git check-ref-format "refs/heads/$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}
if is_option_or_refspec_like "$target_base"; then
  prerequisite_failed_report "--target-base is not a valid branch name: $target_base"
fi
validate_branch_name() {
  local value=$1 label=$2
  if is_option_or_refspec_like "$value"; then
    fail "$label is not a valid branch name: $value"
  fi
}
if [ "$mode" = branch-resume ]; then
  [ -n "$branch" ] || fail '--branch is required for --mode branch-resume'
  validate_branch_name "$branch" '--branch'
fi
if [ "$mode" = pr-resume ]; then
  [ -n "$pr" ] || fail '--pr is required for --mode pr-resume'
  # --pr reaches `gh pr view "$pr" ...` as a bare argument gh itself parses:
  # a leading-dash value such as "--help" is accepted as a gh CLI flag
  # rather than a PR number (gh pr view --help exits 0 with help text,
  # misreported as a generic tooling failure here), and other flags like
  # --web could select unrelated behavior. Require a plain positive integer
  # before this value ever reaches gh.
  case "$pr" in
    ''|*[!0-9]*) fail "--pr must be a positive integer, not a flag or other value: $pr" ;;
  esac
  [ -n "$owner" ] && [ -n "$repo" ] || fail '--owner and --repo are required for --mode pr-resume'
fi

for dependency in python3 git jq mktemp; do
  have_cmd "$dependency" || fail "missing dependency: $dependency"
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/reviewer-preflight.XXXXXX") || fail 'cannot create temporary directory'
# pr-resume fetches the PR head into this ref so read_ref_file can address it
# the same way as every other ref this script reads; the ref is a temporary
# reading aid, not a change this script is allowed to leave behind (AC-2), so
# cleanup deletes it whenever it was created, on every exit path.
created_pr_ref=
cleanup() {
  local rc=$?
  if [ -n "$created_pr_ref" ]; then
    git -C "$repo_root" update-ref -d "$created_pr_ref" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001 - the immediately following verification, not this exit status, is what this script relies on
    # A cleanup failure here (e.g. another process holds the ref lock) must
    # not silently preserve whatever exit status the run was otherwise
    # going to return — that would leave refs/reviewer-preflight/... behind
    # despite this script's own read-only/no-persistent-side-effect
    # contract (AC-2), and repeated failures would accumulate persistent
    # refs. Verify the ref genuinely no longer resolves; override the exit
    # status to a tooling failure if it still does.
    if git -C "$repo_root" rev-parse --verify --quiet "$created_pr_ref" >/dev/null 2>&1; then
      printf 'ERROR: could not discard the temporary PR-head ref (%s) created during this run; resolve manually (e.g. git update-ref -d %s) before trusting this run left no trace (AC-2)\n' "$created_pr_ref" "$created_pr_ref" >&2
      rc=3
    fi
  fi
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
  # `return "$rc"` from an EXIT trap does not reliably override the
  # process's already-decided exit status outside this script's own
  # set -e context (`trap f EXIT; exit 0` still exits 0 even when f
  # returns 3, in general). Exit explicitly here instead of relying on
  # that interaction, so the overridden status in the block above is
  # unambiguously the process's real exit code.
  exit "$rc"
}
trap cleanup EXIT

# workflow-shell-guard: allow SH001 - AC-2's before/after porcelain diff only
# needs the two snapshots to match; a git failure here (e.g. repo-root is not
# a git repository) surfaces as a comparison against an empty string on both
# sides, and the real failure is already caught by the earlier --repo-root
# readable-directory check.
before_porcelain=$(git -C "$repo_root" status --porcelain 2>/dev/null || true) # workflow-shell-guard: allow SH001 - both sides of the AC-2 diff compare equal empty strings on failure; the readable-directory check above already catches a bad --repo-root

clamp_bound() {
  local remaining
  remaining=$((PREFLIGHT_BUDGET_SECONDS - SECONDS))
  [ "$remaining" -gt 0 ] || remaining=0
  bound=$remaining
  [ "$bound" -le "$1" ] || bound=$1
}

# Like clamp_bound, but never shrinks to zero: the input builder and the
# classifier do no I/O of their own (only in-memory JSON work on fragments
# every earlier bounded read has already produced), so they must always get
# a real, if small, chance to run and still produce the graceful-degrade
# outcome (check-inconclusive per platform) this preflight's time-bound
# design exists to reach — starving them to zero just because upstream
# reads consumed the whole budget would turn that intended degrade path
# into a tooling failure instead. The 1-second floor keeps the worst-case
# total overrun past PREFLIGHT_BUDGET_SECONDS small and bounded, rather
# than the unconditional per-step cap this replaces.
clamp_bound_floor() {
  local remaining
  remaining=$((PREFLIGHT_BUDGET_SECONDS - SECONDS))
  [ "$remaining" -ge 1 ] || remaining=1
  bound=$remaining
  [ "$bound" -le "$1" ] || bound=$1
}

# A binary named `timeout` is not necessarily GNU timeout (e.g. BusyBox),
# which does not support `--kill-after`; on such a host the branch below
# would fail every bounded call outright instead of reaching the manual
# fallback, breaking this mandatory dispatch gate entirely. Probe once
# (resolve-reviewer-availability.sh's own same-purpose check, condensed
# for this script's simpler single-launcher shape).
use_gnu_timeout=0
if have_cmd timeout && timeout --version 2>/dev/null | grep -q 'GNU coreutils'; then
  use_gnu_timeout=1
fi

# A lighter-weight bounded launcher than Step 7a's (resolve-reviewer-availability.sh):
# this script's own children are git/gh/python3 one-shot reads, not long-lived
# local reviewer runtimes, so a plain owned-process wait/kill loop is adequate.
run_bounded() {
  local bound=$1 output=$2 error=$3 rc=0
  shift 3
  [ "$bound" -gt 0 ] || return 124
  if [ "$use_gnu_timeout" = 1 ]; then
    timeout --kill-after=1 "$bound" "$@" >"$output" 2>"$error" || rc=$?
    case "$rc" in 124|137) return 124 ;; *) return "$rc" ;; esac
  fi
  local finish pid
  finish=$((SECONDS + bound))
  "$@" >"$output" 2>"$error" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$finish" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.05
  done
  wait "$pid" || rc=$?
  return "$rc"
}

read_ref_file() {
  # read_ref_file <ref> <path-in-repo> <outfile>
  # -> 0 present, 1 absent (path missing at a ref that itself resolves),
  #    2 ref-invalid-or-read-failed (do not treat as "file absent"), 124 timeout
  local ref=$1 path=$2 outfile=$3 rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$outfile" "$work_dir/read.err" \
    git -C "$repo_root" show "${ref}:${path}" || rc=$?
  [ "$rc" = 0 ] && return 0
  [ "$rc" = 124 ] && return 124
  # A `git show` failure for a reason other than a bounded timeout is only
  # safe to read as "this file is absent" when the ref itself resolves — a
  # ref that does not resolve (bad branch name, unfetched remote, transient
  # git error) must not be silently read as "file absent," or a caller can
  # report a coherent verdict on a shared or platform configuration it never
  # actually read.
  if git -C "$repo_root" rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1; then
    return 1
  fi
  return 2
}

fetch_ref() {
  # fetch_ref <refspec> -> best-effort; caller decides how to react to failure
  local refspec=$1 rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/fetch.out" "$work_dir/fetch.err" \
    git -C "$repo_root" fetch --quiet origin "$refspec" || rc=$?
  return "$rc"
}

# Derived from review-overrides's own LOCAL_OVERRIDE_FILE/ORIGIN once that
# runs below — not from a bare $repo_root/.ai-dev-workflow.local.yaml
# existence check, which misses the linked-worktree -> main-clone fallback
# (#1560: a linked worktree with no local override of its own but a real
# override in the main clone would otherwise report "none" here, even
# though the resolver did find and could apply one).
local_override_state=none

shared_ref= platform_ref=
checked_shared_config_ref= checked_platform_config_ref=

case "$mode" in
  pre-dispatch)
    # A swallowed fetch failure here would silently read whatever
    # origin/$target_base happened to already hold from an earlier,
    # possibly stale, fetch and report it as current — mirror pr-resume's
    # own hard failure on its equivalent base-branch refresh.
    fetch_ref "$target_base" || fail "cannot refresh origin/$target_base from the remote"
    shared_ref="origin/$target_base"
    platform_ref="origin/$target_base"
    checked_shared_config_ref="origin/$target_base:.ai-dev-workflow.yaml (this item's targeted base, before a branch exists)"
    checked_platform_config_ref="origin/$target_base:.coderabbit.yaml (this item's targeted base, before a branch exists)"
    ;;
  branch-resume)
    # Same rationale as pre-dispatch above: a swallowed failure here could
    # silently read a stale origin/$target_base as if it were current.
    fetch_ref "$target_base" || fail "cannot refresh origin/$target_base from the remote"
    shared_ref="origin/$target_base"
    checked_shared_config_ref="origin/$target_base:.ai-dev-workflow.yaml (this item's targeted base, not the branch)"
    # The branch in force for Step 7's own hosted reviewers is whichever of
    # the local checkout and the remote copy is actually ahead: GitHub reads
    # from origin (so a local checkout that is behind must not shadow a
    # disabling push already on the remote — the earlier stale-local
    # finding), but a local checkout with genuinely unpushed commits is what
    # will actually become the PR once pushed, so preferring the remote
    # there would just as wrongly read older, already-superseded content.
    # True divergence (neither is an ancestor of the other, e.g. an amended
    # or rebased local branch) cannot be resolved by "ahead" comparison at
    # all; fail closed rather than silently guessing which copy is real.
    # A swallowed failure here is the same risk as the base-branch refresh
    # above, with one legitimate exception: the branch may genuinely not
    # exist on the remote yet (not pushed). Git's own message distinguishes
    # that case from every other fetch failure (network, auth, timeout);
    # only the former is safe to treat as "no remote copy to prefer" rather
    # than a stop.
    # LC_ALL=C: the failure-reason check below parses git's own stderr text
    # ("couldn't find remote ref") to distinguish a genuinely absent branch
    # from an operational fetch failure. That message localizes on a host
    # with a non-English locale configured, which would otherwise
    # misclassify a legitimate not-yet-pushed branch as an operational
    # failure and block every such resume. Force a stable, parseable locale
    # for this one fetch regardless of the host's own locale settings.
    if ! LC_ALL=C LANGUAGE=C fetch_ref "$branch"; then
      if ! grep -q "couldn't find remote ref" "$work_dir/fetch.err" 2>/dev/null; then
        fail "cannot refresh origin/$branch from the remote: $(cat "$work_dir/fetch.err" 2>/dev/null)"
      fi
      # Confirmed absent from the remote right now — but a stale
      # refs/remotes/origin/$branch from an earlier successful fetch (the
      # branch existed on the remote before, then was deleted there) would
      # otherwise still resolve below and be read as current. `git fetch`
      # does not prune remote-tracking refs on its own; discard this one
      # explicitly so absence is reported honestly rather than stale data.
      # A deletion failure (e.g. another process holds the ref lock) must
      # not be swallowed — verify the ref genuinely no longer resolves
      # rather than trusting the delete command's own exit status alone.
      git -C "$repo_root" update-ref -d "refs/remotes/origin/$branch" >/dev/null 2>&1 || true # workflow-shell-guard: allow SH001 - the immediately following verification, not this exit status, is what this script relies on
      if git -C "$repo_root" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null 2>&1; then
        fail "the remote branch '$branch' is confirmed absent but its stale cached copy (refs/remotes/origin/$branch) could not be discarded — resolve manually (e.g. git update-ref -d refs/remotes/origin/$branch) before re-running; reading it would risk stale configuration"
      fi
    fi
    local_resolves=0 origin_resolves=0
    git -C "$repo_root" rev-parse --verify --quiet "${branch}^{commit}" >/dev/null 2>&1 && local_resolves=1
    git -C "$repo_root" rev-parse --verify --quiet "origin/${branch}^{commit}" >/dev/null 2>&1 && origin_resolves=1
    if [ "$local_resolves" = 1 ] && [ "$origin_resolves" = 1 ]; then
      if git -C "$repo_root" merge-base --is-ancestor "origin/$branch" "$branch" 2>/dev/null; then
        platform_ref="$branch"
        checked_platform_config_ref="$branch:.coderabbit.yaml (this item's existing branch; the local copy is at or ahead of the remote)"
      elif git -C "$repo_root" merge-base --is-ancestor "$branch" "origin/$branch" 2>/dev/null; then
        platform_ref="origin/$branch"
        checked_platform_config_ref="origin/$branch:.coderabbit.yaml (this item's existing branch, refreshed from the remote; the local copy is behind)"
      else
        fail "the local and remote copies of branch '$branch' have diverged (neither is an ancestor of the other) — reconcile them (pull/rebase, or push local changes) before re-running; this preflight cannot determine which copy's .coderabbit.yaml is the branch in force"
      fi
    elif [ "$origin_resolves" = 1 ]; then
      platform_ref="origin/$branch"
      checked_platform_config_ref="origin/$branch:.coderabbit.yaml (this item's existing branch, resolved from the remote; no local copy of it exists in this checkout)"
    else
      platform_ref="$branch"
      checked_platform_config_ref="$branch:.coderabbit.yaml (this item's existing branch, no pull request yet)"
    fi
    ;;
  pr-resume)
    pr_json_rc=0
    clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/pr.json" "$work_dir/pr.err" \
      gh pr view "$pr" --repo "$owner/$repo" --json baseRefName,headRefName || pr_json_rc=$?
    [ "$pr_json_rc" = 0 ] || fail "cannot read pull request #$pr metadata (exit $pr_json_rc): $(cat "$work_dir/pr.err" 2>/dev/null)"
    pr_base=$(jq -er '.baseRefName' "$work_dir/pr.json") || fail 'pull request metadata missing baseRefName'
    pr_head=$(jq -er '.headRefName' "$work_dir/pr.json") || fail 'pull request metadata missing headRefName'
    # gh-reported baseRefName is a value this script does not control (a PR
    # can target any ref-format-valid branch name) and reaches fetch_ref the
    # same unvalidated way the CLI --target-base value used to — the same
    # option/refspec-injection risk applies here, not only to CLI input.
    if is_option_or_refspec_like "$pr_base"; then
      prerequisite_failed_report "pull request #$pr's base branch is not a valid branch name: $pr_base"
    fi
    target_base="$pr_base"
    fetch_ref "$pr_base" || fail "cannot refresh origin/$pr_base from the remote"
    # A fixed ref name would race across two concurrent invocations that
    # inspect the same PR: one invocation's cleanup could delete the ref
    # before the other reads it. mktemp's own per-invocation directory name
    # (already unique) makes this ref unique too, at no extra cost.
    pr_ref="refs/reviewer-preflight/pr-$pr.$(basename "$work_dir")"
    # Register for cleanup before the fetch, not after: `git fetch` can
    # write the destination ref and then still report a failure from
    # something after that write (a timeout in post-fetch bookkeeping), in
    # which case `fail` below would otherwise run before created_pr_ref is
    # ever assigned and the EXIT trap would skip deletion entirely, leaving
    # refs/reviewer-preflight/... behind. Deleting a ref the fetch never
    # actually created is harmless (the cleanup trap already tolerates
    # that).
    created_pr_ref="$pr_ref"
    fetch_ref "pull/$pr/head:$pr_ref" || fail "cannot fetch pull request #$pr head"
    shared_ref="origin/$pr_base"
    platform_ref="$pr_ref"
    checked_shared_config_ref="origin/$pr_base:.ai-dev-workflow.yaml (PR #$pr's own target base branch, refreshed)"
    checked_platform_config_ref="PR #$pr's own branch ($pr_head):.coderabbit.yaml"
    ;;
esac

# Shared reviewer list: resolved YAML at $shared_ref, with the machine-local
# override applied from this machine (never from the branch/PR being read).
# The override file itself is resolved once, normally, against the real
# --repo-root (so the existing linked-worktree/main-clone fallback in
# resolve_local_config still applies) and copied alongside the ref snapshot,
# rather than pointed at via WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT — that env
# var's own early-return branch in resolve_local_config bypasses the
# main-clone fallback entirely, which would silently miss a linked-worktree
# override.
shared_dir="$work_dir/shared-config"
mkdir -p "$shared_dir"
shared_read_rc=0
read_ref_file "$shared_ref" .ai-dev-workflow.yaml "$shared_dir/.ai-dev-workflow.yaml" || shared_read_rc=$?
case "$shared_read_rc" in
  0) : ;;
  1) : >"$shared_dir/.ai-dev-workflow.yaml" ;;
  *) fail "cannot read $shared_ref:.ai-dev-workflow.yaml (read_ref_file exit $shared_read_rc): the shared reviewer configuration ref did not resolve or the bounded read did not complete — this is not the same as the file being absent" ;;
esac
overrides_json="$work_dir/overrides.json"
overrides_rc=0
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$overrides_json" "$work_dir/overrides.err" \
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" review-overrides --repo-root "$repo_root" --json || overrides_rc=$?
[ "$overrides_rc" = 0 ] || fail "review-overrides failed (exit $overrides_rc): $(cat "$work_dir/overrides.err" 2>/dev/null)"
local_override_file=$(jq -er '.LOCAL_OVERRIDE_FILE // ""' "$overrides_json") || fail 'cannot read LOCAL_OVERRIDE_FILE from review-overrides output'
local_override_origin=$(jq -er '.LOCAL_OVERRIDE_ORIGIN // ""' "$overrides_json") || fail 'cannot read LOCAL_OVERRIDE_ORIGIN from review-overrides output'
if [ -n "$local_override_file" ] && [ -f "$local_override_file" ]; then
  cp -- "$local_override_file" "$shared_dir/.ai-dev-workflow.local.yaml"
  # Matches the documented contract's three states (none | applied |
  # present-unpropagated <details>): a file was found (accounting for the
  # linked-worktree -> main-clone fallback via LOCAL_OVERRIDE_ORIGIN) but
  # nothing from it applied to any resolved bucket yet — the block below
  # upgrades this to "applied" when review-effective / review-github-
  # effective actually used it.
  local_override_state="present-unpropagated $local_override_file${local_override_origin:+ (origin: $local_override_origin)}"
fi

runner_json="$work_dir/runner-effective.json"
github_json="$work_dir/github-effective.json"
resolver_rc=0
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$runner_json" "$work_dir/resolver.err" \
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" review-effective --repo-root "$shared_dir" || resolver_rc=$?
[ "$resolver_rc" = 0 ] || fail "review-effective failed (exit $resolver_rc): $(cat "$work_dir/resolver.err" 2>/dev/null)"
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$github_json" "$work_dir/resolver-github.err" \
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" review-github-effective --repo-root "$shared_dir" || resolver_rc=$?
[ "$resolver_rc" = 0 ] || fail "review-github-effective failed (exit $resolver_rc): $(cat "$work_dir/resolver-github.err" 2>/dev/null)"

if jq -e '.local_review_override_applied == true' "$runner_json" >/dev/null 2>&1 ||
   jq -e '.local_review_override_applied == true' "$github_json" >/dev/null 2>&1; then
  local_override_state=applied
fi

# Each platform's own configuration: read from the branch in force for this
# item ($platform_ref), never from $shared_ref once they differ.
coderabbit_read=no-readable-surface
coderabbit_json="$work_dir/coderabbit.json"
coderabbit_raw="$work_dir/coderabbit-raw.yaml"
coderabbit_read_rc=0
read_ref_file "$platform_ref" .coderabbit.yaml "$coderabbit_raw" || coderabbit_read_rc=$?
if [ "$coderabbit_read_rc" = 124 ] || [ "$coderabbit_read_rc" = 2 ]; then
  # 124: bounded read timed out. 2: the platform ref itself did not resolve
  # or the read otherwise failed — not the same as the file being absent at
  # a ref that does resolve, and must not be reported as a readable-but-
  # default configuration.
  coderabbit_read=check-inconclusive
elif [ "$coderabbit_read_rc" = 1 ]; then
  # Missing file: CodeRabbit's own default is auto_review disabled (matches
  # reviewer_preflight_coderabbit.load_coderabbit_config's missing-file case).
  printf '{}\n' >"$coderabbit_raw"
  coderabbit_parse_rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$coderabbit_json" "$work_dir/coderabbit.err" \
    python3 "$SCRIPT_DIR/reviewer_preflight_coderabbit.py" --mode full-json "$work_dir/does-not-exist.yaml" || coderabbit_parse_rc=$?
  case "$coderabbit_parse_rc" in
    0) coderabbit_read=ok ;;
    124) coderabbit_read=check-inconclusive ;;
    *) coderabbit_read=check-inconclusive ;;
  esac
else
  coderabbit_parse_rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$coderabbit_json" "$work_dir/coderabbit.err" \
    python3 "$SCRIPT_DIR/reviewer_preflight_coderabbit.py" --mode full-json "$coderabbit_raw" || coderabbit_parse_rc=$?
  case "$coderabbit_parse_rc" in
    0) coderabbit_read=ok ;;
    124) coderabbit_read=check-inconclusive ;;
    *) coderabbit_read=check-inconclusive ;;
  esac
fi

input_json="$work_dir/input.json"
build_input_rc=0
clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$work_dir/build-input.out" "$work_dir/build-input.err" \
  python3 "$SCRIPT_DIR/reviewer_preflight_build_input.py" \
  --runner-json "$runner_json" \
  --github-json "$github_json" \
  --coderabbit-json "$coderabbit_json" \
  --coderabbit-read "$coderabbit_read" \
  --target-base "$target_base" \
  --remaining-stages "$remaining_stages_raw" \
  --remaining-stages-provided "$remaining_stages_provided" \
  --pr-state "$pr_state_raw" \
  --checked-shared-config-ref "$checked_shared_config_ref" \
  --checked-platform-config-ref "$checked_platform_config_ref" \
  --local-override-state "$local_override_state" \
  --output "$input_json" || build_input_rc=$?
[ "$build_input_rc" = 0 ] || fail "reviewer_preflight_build_input.py failed (exit $build_input_rc): $(cat "$work_dir/build-input.err" 2>/dev/null)"

# Decision 5: a malformed shared reviewer list is the pre-existing
# configuration-loading step's responsibility, not this preflight's — the run
# should already have failed before ever reaching this script. If it did not,
# surface that as a tooling failure rather than silently treating a malformed
# list as an empty (deliberately-configured) one.
malformed_count=$(jq -er '.malformed_buckets | length' "$input_json") || fail 'cannot inspect resolved reviewer-list state'
if [ "$malformed_count" -gt 0 ]; then
  malformed_list=$(jq -er '.malformed_buckets | join(", ")' "$input_json") || malformed_list='(unreadable)'
  fail "the shared reviewer list is malformed for: $malformed_list — repair .ai-dev-workflow.yaml (or the local override) before re-running; this is the pre-existing configuration-loading step's failure, not a preflight verdict"
fi

output_json="$work_dir/output.json"
preflight_rc=0
clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$output_json" "$work_dir/preflight.err" \
  python3 "$SCRIPT_DIR/reviewer_preflight.py" --input-json "$input_json" || preflight_rc=$?
if [ "$preflight_rc" -gt 3 ] || { [ "$preflight_rc" != 0 ] && ! jq -e . "$output_json" >/dev/null 2>&1; }; then
  cat "$work_dir/preflight.err" >&2
  fail "reviewer_preflight.py failed (exit $preflight_rc)"
fi

after_porcelain=$(git -C "$repo_root" status --porcelain 2>/dev/null || true) # workflow-shell-guard: allow SH001 - same rationale as before_porcelain above
if [ "$before_porcelain" != "$after_porcelain" ]; then
  fail 'reviewer-preflight.sh must not change the working tree (AC-2); the checkout differs after this run'
fi

if [ "$json_output" = true ]; then
  jq --argjson elapsed "$SECONDS" --argjson budget "$PREFLIGHT_BUDGET_SECONDS" \
    '. + {elapsed_seconds: $elapsed, budget_seconds: $budget}' "$output_json"
  exit "$preflight_rc"
fi

# A configuration listing many distinct reviewer values (every one still
# gets its own platform row, even an unsupported value — value-not-
# supported is a per-platform verdict, not a filter) previously launched
# roughly nine unbounded jq subprocesses per platform here, well after all
# deadline-controlled work had finished; a large-enough list could stall
# this mandatory dispatch gate past its advertised budget outright, not
# merely under-report ELAPSED_SECONDS (the earlier, insufficient fix).
# Render the entire report — the fixed header fields and every platform
# row — in exactly one bounded jq pass instead, NUL-delimited so no field's
# own content (detail/remedy free text) can be misread as a separator.
clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
report_rc=0
run_bounded "$bound" "$work_dir/report-fields.out" "$work_dir/report-fields.err" \
  jq -j '
    (.outcome, .outcome_label, .checked_shared_config_ref, .checked_platform_config_ref, .local_override_state, (.prerequisite_detail // ""), (.platforms | length | tostring)),
    (.platforms[] | (.name, .verdict, (.reasons | join(",")), .surface, .setting, .detail, .remedy, (.override_added | tostring), (.bucket_results | tojson)))
    | . + "\u0000"
  ' "$output_json" || report_rc=$?
[ "$report_rc" = 0 ] || fail "cannot render the report (exit $report_rc): $(cat "$work_dir/report-fields.err" 2>/dev/null)"
report_fields=()
while IFS= read -r -d '' report_field; do report_fields+=("$report_field"); done <"$work_dir/report-fields.out"
print_kv_escaped OUTCOME "${report_fields[0]}"
print_kv_escaped OUTCOME_LABEL "${report_fields[1]}"
print_kv_escaped CHECKED_SHARED_CONFIG_REF "${report_fields[2]}"
print_kv_escaped CHECKED_PLATFORM_CONFIG_REF "${report_fields[3]}"
print_kv_escaped LOCAL_OVERRIDE_STATE "${report_fields[4]}"
# Only meaningful when OUTCOME=prerequisite-failed; the orchestrator's stop
# message needs this to name the specific failed input (Protocol 91's
# named-stop contract), not just the outcome label.
print_kv_escaped PREREQUISITE_DETAIL "${report_fields[5]}"
platform_count="${report_fields[6]}"
print_kv_escaped PLATFORM_COUNT "$platform_count"
idx=7
n=0
while [ "$n" -lt "$platform_count" ]; do
  n=$((n + 1))
  print_kv_escaped "PLATFORM_${n}_NAME" "${report_fields[$idx]}"
  print_kv_escaped "PLATFORM_${n}_VERDICT" "${report_fields[$((idx + 1))]}"
  print_kv_escaped "PLATFORM_${n}_REASONS" "${report_fields[$((idx + 2))]}"
  print_kv_escaped "PLATFORM_${n}_SURFACE" "${report_fields[$((idx + 3))]}"
  print_kv_escaped "PLATFORM_${n}_SETTING" "${report_fields[$((idx + 4))]}"
  print_kv_escaped "PLATFORM_${n}_DETAIL" "${report_fields[$((idx + 5))]}"
  print_kv_escaped "PLATFORM_${n}_REMEDY" "${report_fields[$((idx + 6))]}"
  print_kv_escaped "PLATFORM_${n}_OVERRIDE_ADDED" "${report_fields[$((idx + 7))]}"
  print_kv_escaped "PLATFORM_${n}_BUCKET_JSON" "${report_fields[$((idx + 8))]}"
  idx=$((idx + 9))
done
print_kv_escaped ELAPSED_SECONDS "$SECONDS"
print_kv_escaped BUDGET_SECONDS "$PREFLIGHT_BUDGET_SECONDS"

exit "$preflight_rc"
