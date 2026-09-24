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
# reading" rule for the shared configuration on the pr-resume path.
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
[ -n "$target_base" ] || fail 'missing --target-base'
if [ "$mode" = branch-resume ]; then [ -n "$branch" ] || fail '--branch is required for --mode branch-resume'; fi
if [ "$mode" = pr-resume ]; then
  [ -n "$pr" ] || fail '--pr is required for --mode pr-resume'
  [ -n "$owner" ] && [ -n "$repo" ] || fail '--owner and --repo are required for --mode pr-resume'
fi

for dependency in python3 git jq mktemp; do
  have_cmd "$dependency" || fail "missing dependency: $dependency"
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/reviewer-preflight.XXXXXX") || fail 'cannot create temporary directory'
cleanup() {
  local rc=$?
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
  return "$rc"
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

# A lighter-weight bounded launcher than Step 7a's (resolve-reviewer-availability.sh):
# this script's own children are git/gh/python3 one-shot reads, not long-lived
# local reviewer runtimes, so a plain owned-process wait/kill loop is adequate.
run_bounded() {
  local bound=$1 output=$2 error=$3 rc=0
  shift 3
  [ "$bound" -gt 0 ] || return 124
  if have_cmd timeout; then
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
  # read_ref_file <ref> <path-in-repo> <outfile> -> 0 present, 1 absent, 124 timeout
  local ref=$1 path=$2 outfile=$3 rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$outfile" "$work_dir/read.err" \
    git -C "$repo_root" show "${ref}:${path}" || rc=$?
  return "$rc"
}

fetch_ref() {
  # fetch_ref <refspec> -> best-effort; caller decides how to react to failure
  local refspec=$1 rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/fetch.out" "$work_dir/fetch.err" \
    git -C "$repo_root" fetch --quiet origin "$refspec" || rc=$?
  return "$rc"
}

local_override_state=none
if [ -f "$repo_root/.ai-dev-workflow.local.yaml" ]; then
  local_override_state=present
fi

shared_ref= platform_ref=
checked_shared_config_ref= checked_platform_config_ref=

case "$mode" in
  pre-dispatch)
    fetch_ref "$target_base" || true
    shared_ref="origin/$target_base"
    platform_ref="origin/$target_base"
    checked_shared_config_ref="origin/$target_base:.ai-dev-workflow.yaml (this item's targeted base, before a branch exists)"
    checked_platform_config_ref="origin/$target_base:.coderabbit.yaml (this item's targeted base, before a branch exists)"
    ;;
  branch-resume)
    fetch_ref "$target_base" || true
    shared_ref="origin/$target_base"
    platform_ref="$branch"
    checked_shared_config_ref="origin/$target_base:.ai-dev-workflow.yaml (this item's targeted base, not the branch)"
    checked_platform_config_ref="$branch:.coderabbit.yaml (this item's existing branch, no pull request yet)"
    ;;
  pr-resume)
    pr_json_rc=0
    clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/pr.json" "$work_dir/pr.err" \
      gh pr view "$pr" --repo "$owner/$repo" --json baseRefName,headRefName || pr_json_rc=$?
    [ "$pr_json_rc" = 0 ] || fail "cannot read pull request #$pr metadata (exit $pr_json_rc): $(cat "$work_dir/pr.err" 2>/dev/null)"
    pr_base=$(jq -er '.baseRefName' "$work_dir/pr.json") || fail 'pull request metadata missing baseRefName'
    pr_head=$(jq -er '.headRefName' "$work_dir/pr.json") || fail 'pull request metadata missing headRefName'
    target_base="$pr_base"
    fetch_ref "$pr_base" || fail "cannot refresh origin/$pr_base from the remote"
    fetch_ref "pull/$pr/head:refs/reviewer-preflight/pr-$pr" || fail "cannot fetch pull request #$pr head"
    shared_ref="origin/$pr_base"
    platform_ref="refs/reviewer-preflight/pr-$pr"
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
if read_ref_file "$shared_ref" .ai-dev-workflow.yaml "$shared_dir/.ai-dev-workflow.yaml"; then :; else
  : >"$shared_dir/.ai-dev-workflow.yaml"
fi
overrides_json="$work_dir/overrides.json"
overrides_rc=0
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$overrides_json" "$work_dir/overrides.err" \
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" review-overrides --repo-root "$repo_root" --json || overrides_rc=$?
[ "$overrides_rc" = 0 ] || fail "review-overrides failed (exit $overrides_rc): $(cat "$work_dir/overrides.err" 2>/dev/null)"
local_override_file=$(jq -er '.LOCAL_OVERRIDE_FILE // ""' "$overrides_json") || fail 'cannot read LOCAL_OVERRIDE_FILE from review-overrides output'
if [ -n "$local_override_file" ] && [ -f "$local_override_file" ]; then
  cp -- "$local_override_file" "$shared_dir/.ai-dev-workflow.local.yaml"
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
if [ "$coderabbit_read_rc" = 124 ]; then
  coderabbit_read=check-inconclusive
elif [ "$coderabbit_read_rc" != 0 ]; then
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
  --output "$input_json"

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
python3 "$SCRIPT_DIR/reviewer_preflight.py" --input-json "$input_json" >"$output_json" 2>"$work_dir/preflight.err" || preflight_rc=$?
if [ "$preflight_rc" -gt 3 ] || { [ "$preflight_rc" != 0 ] && ! jq -e . "$output_json" >/dev/null 2>&1; }; then
  cat "$work_dir/preflight.err" >&2
  fail "reviewer_preflight.py failed (exit $preflight_rc)"
fi

after_porcelain=$(git -C "$repo_root" status --porcelain 2>/dev/null || true) # workflow-shell-guard: allow SH001 - same rationale as before_porcelain above
if [ "$before_porcelain" != "$after_porcelain" ]; then
  fail 'reviewer-preflight.sh must not change the working tree (AC-2); the checkout differs after this run'
fi

elapsed="$SECONDS"

if [ "$json_output" = true ]; then
  jq --argjson elapsed "$elapsed" --argjson budget "$PREFLIGHT_BUDGET_SECONDS" \
    '. + {elapsed_seconds: $elapsed, budget_seconds: $budget}' "$output_json"
  exit "$preflight_rc"
fi

print_kv_escaped OUTCOME "$(jq -r '.outcome' "$output_json")"
print_kv_escaped OUTCOME_LABEL "$(jq -r '.outcome_label' "$output_json")"
print_kv_escaped CHECKED_SHARED_CONFIG_REF "$(jq -r '.checked_shared_config_ref' "$output_json")"
print_kv_escaped CHECKED_PLATFORM_CONFIG_REF "$(jq -r '.checked_platform_config_ref' "$output_json")"
print_kv_escaped LOCAL_OVERRIDE_STATE "$(jq -r '.local_override_state' "$output_json")"
platform_count=$(jq -er '.platforms | length' "$output_json") || fail 'cannot read platform count from reviewer_preflight.py output'
print_kv_escaped PLATFORM_COUNT "$platform_count"
i=0
while [ "$i" -lt "$platform_count" ]; do
  n=$((i + 1))
  print_kv_escaped "PLATFORM_${n}_NAME" "$(jq -r ".platforms[$i].name" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_VERDICT" "$(jq -r ".platforms[$i].verdict" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_REASONS" "$(jq -r ".platforms[$i].reasons | join(\",\")" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_SURFACE" "$(jq -r ".platforms[$i].surface" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_SETTING" "$(jq -r ".platforms[$i].setting" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_DETAIL" "$(jq -r ".platforms[$i].detail" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_REMEDY" "$(jq -r ".platforms[$i].remedy" "$output_json")"
  print_kv_escaped "PLATFORM_${n}_BUCKET_JSON" "$(jq -c ".platforms[$i].bucket_results" "$output_json")"
  i=$((i + 1))
done
print_kv_escaped ELAPSED_SECONDS "$elapsed"
print_kv_escaped BUDGET_SECONDS "$PREFLIGHT_BUDGET_SECONDS"

exit "$preflight_rc"
