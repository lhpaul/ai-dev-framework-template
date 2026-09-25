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
# Read-only: this script runs only git show / git ls-remote / git cat-file /
# git rev-parse / git merge-base / git status --porcelain, gh pr view, and
# python3 reads of temporary copies. It never checks out, commits, pushes,
# opens a pull request, comments, labels, or writes any tracked file under
# --repo-root — and, as of #1561's round-26 fix, it never writes anything
# inside .git/ either: `git ls-remote` (unlike the `git fetch` this script
# used to run for the same "refreshed from the remote before reading" rule)
# only queries the remote and never creates or updates refs/remotes/*,
# FETCH_HEAD, or the object database. A remote tip resolved this way is read
# directly by its SHA (`git show <sha>:<path>`), not through a local
# remote-tracking ref this script would otherwise have to create. When that
# SHA's commit object is not already present in the local object database
# (this script never fetches, so nothing guarantees it is), reading it is
# impossible without a fetch this script will not perform: that surfaces as
# read_ref_file's own existing rc=2 (ref-invalid-or-read-failed) contract —
# the same path an unresolvable ref already took before this change — which
# each caller already resolves to a documented outcome consistent with the
# spec's outcome matrix: the shared-config caller fails closed (a tooling
# failure, since dispatch cannot proceed without a shared reviewer list to
# cross-check against), and the per-platform (coderabbit) caller degrades
# that one platform to Undetermined/check-inconclusive rather than blocking
# every platform on one unreadable object. The one case read_ref_file's own
# git-show/rev-parse-verify combination cannot disambiguate on its own is
# branch-resume's ancestry SELECTION between a local and a remote copy
# (`git merge-base --is-ancestor` needs both commit objects present to
# answer "is X an ancestor of Y" at all, not merely to read file content at
# one of them) — that path adds its own explicit `git cat-file -e` presence
# check before attempting the ancestry comparison and fails closed (tooling
# failure) rather than fetching when the remote object is not present.
set -euo pipefail

# In a partial clone (a supported Git checkout mode), reading an object this
# script does not already have locally can transparently trigger a lazy
# fetch from the promisor remote — confirmed live with GIT_TRACE=1: `git
# show <sha>:<path>` on a SHA resolved via ls-remote but not locally present
# ran an internal `git fetch origin --filter=blob:none`, writing new packs
# under .git while the AC-2 porcelain snapshots (which only cover the
# working tree and refs, not the object store's own pack files) stayed
# unchanged and so never detected it. This makes every child git process
# this script starts treat a missing object as a hard failure instead of
# lazily fetching it — the same "cannot read without fetching" outcome this
# script already documents and handles (read_ref_file's rc=2, the
# branch-resume ancestry cat-file presence check) for the non-partial-clone
# case, now enforced for partial clones too rather than silently fetching
# around it.
export GIT_NO_LAZY_FETCH=1

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
    # `git check-ref-format refs/heads/HEAD` alone reports this shape as
    # valid (it is a syntactically fine refname), but HEAD is git's own
    # reserved symbolic-ref name, not an ordinary branch — confirmed:
    # `git check-ref-format --branch HEAD` (git's own branch-shorthand
    # validator) rejects it, while the plain refs/heads/ form below does
    # not. Passing "HEAD" through as --target-base/--branch would fetch
    # and classify against the remote's symbolic default-branch pointer
    # (refs/remotes/origin/HEAD) under the literal name "HEAD" instead of
    # that default branch's own name, producing a verdict against the
    # wrong ref or an unstructured tooling failure rather than this
    # prerequisite check. Reject the exact reserved name directly, rather
    # than switching to --branch mode's shorthand-expansion semantics
    # (e.g. it silently accepts and expands "@{-1}"), which would trade
    # this one gap for a different unreviewed one.
    HEAD) return 0 ;;
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
  # Digits-only above still accepts "0" (and "00", "000", ...) — zero cannot
  # identify a pull request, and gh pr view 0 fails as an unstructured
  # tooling error rather than rejecting the invalid input locally. Reject
  # any all-zero value by requiring at least one non-zero digit.
  case "$pr" in
    *[1-9]*) ;;
    *) fail "--pr must be a positive integer greater than zero: $pr" ;;
  esac
  [ -n "$owner" ] && [ -n "$repo" ] || fail '--owner and --repo are required for --mode pr-resume'
fi

for dependency in python3 git jq mktemp; do
  have_cmd "$dependency" || fail "missing dependency: $dependency"
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/reviewer-preflight.XXXXXX") || fail 'cannot create temporary directory'
# As of #1561's round-26 read-only redesign, this script resolves every
# remote tip via `git ls-remote` and reads content directly by the resolved
# SHA (git show <sha>:<path>) rather than fetching a PR head into a local
# temporary ref first — there is no longer any repository-state ref this
# script creates and must remember to discard, so cleanup is just the
# scratch work_dir.
cleanup() {
  local rc=$?
  [ -z "$work_dir" ] || rm -rf -- "$work_dir"
  # `return "$rc"` from an EXIT trap does not reliably override the
  # process's already-decided exit status outside this script's own
  # set -e context (`trap f EXIT; exit 0` still exits 0 even when f
  # returns 3, in general). Exit explicitly here instead of relying on
  # that interaction, so this function's own intent (preserve whatever
  # exit status the run already decided) is unambiguous rather than
  # relying on that interaction to happen to hold.
  exit "$rc"
}
trap cleanup EXIT

clamp_bound() {
  local remaining
  remaining=$((PREFLIGHT_BUDGET_SECONDS - SECONDS))
  [ "$remaining" -gt 0 ] || remaining=0
  bound=$remaining
  [ "$bound" -le "$1" ] || bound=$1
}

# Like clamp_bound, but never shrinks to zero the FIRST time the deadline is
# already spent: several final-mile steps (the before/after porcelain
# snapshots, the input builder, the classifier, and the report renderer) do
# little or no I/O of their own, so they should still get a real, if small,
# chance to run rather than being starved to an automatic tooling failure
# purely because upstream reads already consumed the whole nominal budget.
#
# This 1-second floor extends the effective deadline itself by exactly one
# second, ONE TIME per invocation (floor_extended) — it does not grant a
# fresh 1-second budget to every call site that happens to run after the
# original deadline. This script has up to six clamp_bound_floor call
# sites in a single run (the before-porcelain snapshot, the no-review-
# remaining short-circuit's own input build, the normal-path input build,
# the classifier, the after-porcelain snapshot, and the report renderer);
# an earlier version of this function reset `remaining` to a fresh 1 on
# every post-deadline call, which could let a slow run overrun
# PREFLIGHT_BUDGET_SECONDS by several seconds in aggregate, not the single
# bounded second the design intends. A later version instead granted the
# floor to only the FIRST post-deadline caller and starved every
# subsequent one to bound=0 — but that starves the normal, expected
# T-7-shaped case (one platform read genuinely times out, and two or more
# fast in-memory steps still need to run afterward) into an outright
# tooling failure instead of the intended passed-unverified degrade.
# Extending the deadline itself, once, lets every call after the first
# floored one share whatever fraction of that single second remains
# (naturally shrinking as SECONDS advances), rather than each getting its
# own full fresh second or the later ones getting none at all.
#
# floor_deadline_extension (not PREFLIGHT_BUDGET_SECONDS itself) carries
# the one-time extension, so the nominal budget this run was actually
# given stays intact for the JSON/report BUDGET_SECONDS field and every
# other reader of PREFLIGHT_BUDGET_SECONDS — only clamp_bound_floor's own
# remaining-time arithmetic sees the extended effective deadline.
floor_deadline_extension=0
clamp_bound_floor() {
  local remaining
  remaining=$((PREFLIGHT_BUDGET_SECONDS + floor_deadline_extension - SECONDS))
  if [ "$remaining" -lt 1 ] && [ "$floor_deadline_extension" = 0 ]; then
    floor_deadline_extension=1
    remaining=$((PREFLIGHT_BUDGET_SECONDS + floor_deadline_extension - SECONDS))
  fi
  [ "$remaining" -ge 0 ] || remaining=0
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
  if [ "$bound" -le 0 ]; then
    # Every caller reads $output/$error unconditionally after a non-zero
    # return (several via a bare `cat`, not just `$(... 2>/dev/null)`
    # substitutions) — this starved-before-launch return must leave both
    # present, the same as every other exit path below, which always runs
    # the child with `>"$output" 2>"$error"` redirection even when later
    # killed for a timeout. Without this, a genuinely zero-second bound
    # (reachable once clamp_bound_floor's one-time reserve is already
    # spent) skips creating either file, and an unguarded downstream `cat`
    # then fails under `set -e` with an unrelated exit status instead of
    # this function's own documented 124/fail() contract.
    : >"$output" 2>/dev/null || true
    : >"$error" 2>/dev/null || true
    return 124
  fi
  if [ "$use_gnu_timeout" = 1 ]; then
    timeout --kill-after=1 "$bound" "$@" >"$output" 2>"$error" || rc=$?
    case "$rc" in 124|137) return 124 ;; *) return "$rc" ;; esac
  fi
  local finish pid
  finish=$((SECONDS + bound))
  # On hosts without GNU timeout (this fallback path — including the
  # explicitly supported BusyBox/macOS case), signaling only the direct PID
  # is not enough: commands run here (e.g. git ls-remote) can spawn
  # transport, credential-helper, or hook descendants that ignore or
  # outlive a signal sent only to their parent, leaving them running after
  # this function returns. Start the command as its own process group
  # leader (setsid on Linux/BusyBox; macOS has no setsid, so fall back to
  # perl's setpgrp — the same two-tier fallback resolve-reviewer-
  # availability.sh's own bounded launcher already uses) so a timeout can
  # terminate the whole group, not just the leader. When neither helper is
  # available, degrade to the previous single-PID behavior rather than
  # failing outright — this script's own children are still one-shot git/
  # gh/python3 reads, not long-lived servers, so the residual risk on that
  # rare host is a narrowing of protection, not a new one.
  if have_cmd setsid; then
    setsid "$@" >"$output" 2>"$error" &
  elif have_cmd perl; then
    perl -e 'setpgrp(0,0) or die "setpgrp: $!"; exec @ARGV; die "exec: $!"' -- "$@" >"$output" 2>"$error" &
  else
    "$@" >"$output" 2>"$error" &
  fi
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$finish" ]; then
      kill -TERM -- "-$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      # Unconditional: the group (or a lone ungrouped child, on the
      # no-setsid-or-perl fallback) can outlive TERM.
      kill -KILL -- "-$pid" 2>/dev/null || true
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.05
  done
  wait "$pid" || rc=$?
  kill -KILL -- "-$pid" 2>/dev/null || true
  return "$rc"
}

# AC-2's before/after porcelain diff only needs the two snapshots to match;
# a git failure here (e.g. repo-root is not a git repository) surfaces as a
# comparison against an empty string on both sides, and the real failure is
# already caught by the earlier --repo-root readable-directory check. A slow
# or stalled filesystem could otherwise let this run past the whole
# invocation's advertised budget before producing any outcome, since an
# unbounded call here is not subject to run_bounded's own deadline the way
# every other read in this script is; bound it the same way. Use the floor
# variant, not the plain one: `git status --porcelain` is normally a fast,
# essential, final-mile check, not one of the earlier reads this budget is
# meant to constrain — starving it to a zero-second bound purely because
# upstream (normally fast) reads already consumed the nominal total budget
# would turn a healthy run into a spurious cannot-verify failure below,
# exactly like clamp_bound_floor's own no-I/O-step rationale.
before_porcelain_rc=0
clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
# --no-optional-locks: without it, `git status` can itself write .git/index
# (refreshing its stat cache when tracked-file mtimes look stale but content
# is unchanged) — confirmed live: the index's inode and content hash changed
# across this exact before/after pair while porcelain output stayed empty,
# so the AC-2 diff could not detect it. This flag disables that optional
# write for this read-only status query without changing its reported
# output.
run_bounded "$bound" "$work_dir/porcelain-before.out" "$work_dir/porcelain-before.err" \
  git --no-optional-locks -C "$repo_root" status --porcelain || before_porcelain_rc=$?
before_porcelain=$(cat "$work_dir/porcelain-before.out" 2>/dev/null || true)

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
  # A `git show` failure for a reason other than a bounded timeout is
  # ambiguous between three cases this function must not conflate:
  #   (a) the ref itself does not resolve at all;
  #   (b) the path is genuinely absent from the tree at this ref (the file
  #       does not exist there) — the only case safe to report as "file
  #       absent" (rc=1);
  #   (c) the path IS present in the tree, but its blob object is not
  #       locally available — a partial clone (a supported Git checkout
  #       mode) with lazy fetching disabled (GIT_NO_LAZY_FETCH=1, above)
  #       refusing to fetch it.
  # Confirmed live: in a partial clone where an older commit's own tree and
  # commit object are both present (partial clone fetches the full commit
  # graph, only blobs are filtered) but that commit's own blob for this
  # path was never individually fetched (a newer commit changed the file,
  # and only the newer blob was needed for checkout), `git show` fails
  # with "bad object" while a bare commit-only `rev-parse --verify`
  # succeeds — the previous version of this function returned rc=1
  # ("absent") for that case, letting a caller report a coherent verdict
  # (including OUTCOME=passed) on configuration content it never actually
  # read. Bound every verification probe here too — same class of
  # unbounded-wall-clock risk as every other git subprocess this script
  # reads through — and treat a genuine timeout at any step as this
  # function's own 124 (inconclusive read), not silently as absent (1) or
  # invalid (2): neither is proven when a check itself could not complete.
  local verify_rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/read-verify.out" "$work_dir/read-verify.err" \
    git -C "$repo_root" rev-parse --verify --quiet "${ref}^{commit}" || verify_rc=$?
  [ "$verify_rc" = 124 ] && return 124
  [ "$verify_rc" != 0 ] && return 2 # (a): the ref itself does not resolve
  # The commit resolves; distinguish (b) from (c) by checking the tree
  # entry directly. `git ls-tree` only needs the tree object(s) along the
  # path, never the blob's own content, so it stays readable in a
  # --filter=blob:none partial clone even when the blob itself is not —
  # confirmed live (object count unchanged after this call in that
  # scenario).
  local tree_rc=0
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/read-tree.out" "$work_dir/read-tree.err" \
    git -C "$repo_root" ls-tree -r --name-only "${ref}" -- "$path" || tree_rc=$?
  [ "$tree_rc" = 124 ] && return 124
  [ "$tree_rc" != 0 ] && return 2 # ls-tree itself failed: cannot verify, fail closed
  if [ -s "$work_dir/read-tree.out" ]; then
    return 2 # (c): listed in the tree, but the blob could not be read — unknown, not absent
  fi
  return 1 # (b): genuinely absent from the tree
}

resolve_remote_sha() {
  # resolve_remote_sha <branch-name> -> on success (0), writes the resolved
  # 40-character commit SHA to $resolved_remote_sha and returns 0.
  # Read-only: `git ls-remote` only queries the remote; unlike the `git
  # fetch` this function replaces, it never creates or updates
  # refs/remotes/*, FETCH_HEAD, or the object database.
  # Returns 1 when --exit-code confirms no matching ref exists on the
  # remote right now (the documented way to distinguish "branch absent" from
  # an operational failure, replacing the old `git fetch` stderr-text
  # match on "couldn't find remote ref"), 124 on a bounded timeout, or the
  # raw git exit code for any other operational failure (network, auth).
  # A fully-qualified refs/heads/<name> pattern, not a bare branch name:
  # ls-remote's own pattern matching is otherwise vulnerable to the same
  # tag-vs-branch ambiguity already fixed for local ref resolution
  # elsewhere in this script.
  local branch_name=$1 rc=0
  resolved_remote_sha=
  clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/lsremote.out" "$work_dir/lsremote.err" \
    git -C "$repo_root" ls-remote --exit-code origin "refs/heads/${branch_name}" || rc=$?
  if [ "$rc" = 124 ]; then
    return 124
  fi
  if [ "$rc" = 2 ]; then
    return 1
  fi
  [ "$rc" = 0 ] || return "$rc"
  resolved_remote_sha=$(awk 'NR==1{print $1}' "$work_dir/lsremote.out")
  [ -n "$resolved_remote_sha" ] || return 1
  return 0
}

resolve_target_base_or_fail() {
  # resolve_target_base_or_fail <branch-name> <label-for-error-text>
  # On success, leaves the resolved commit SHA in $resolved_remote_sha and
  # returns normally. A confirmed-absent branch is a prerequisite-failed
  # run-input problem (this run's own target base does not currently exist
  # on the remote, distinct from a reviewer-configuration verdict) — not
  # merely "a swallowed failure silently reads whatever origin/<name>
  # happened to already hold from an earlier, possibly stale, fetch" (the
  # risk this exact confusion used to create when this script still
  # fetched); this script never fetches now, so there is no stale local
  # copy to guard against here at all, only the live remote answer. A
  # timeout or other operational failure is instead this script's own
  # tooling failure, consistent with every other bounded git operation.
  local branch_name=$1 label=$2 rc=0
  resolve_remote_sha "$branch_name" || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) prerequisite_failed_report "$label does not exist on the remote: $branch_name" ;;
    124) fail "cannot resolve $label ('$branch_name') on the remote: the query did not complete within the time budget" ;;
    *) fail "cannot resolve $label ('$branch_name') on the remote (exit $rc): $(cat "$work_dir/lsremote.err" 2>/dev/null)" ;;
  esac
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

# The documented prerequisite order requires no-review-remaining
# immediately after validating the target base (already done above, at
# the CLI-syntax level) — before mode dispatch resolves any ref, and
# before either configuration is ever read. An explicit empty
# --remaining-stages previously still went through mode dispatch and both
# config reads first: in a stale or partial clone unable to read
# configuration no remaining stage would ever consult anyway, that read
# failure surfaced as a tooling failure the run should never have reached.
# Short-circuit straight to building the no-review-remaining input (via
# the same reviewer_preflight_build_input.py this script always uses, so
# the two paths cannot drift in output shape) instead.
if [ "$remaining_stages_provided" = 1 ] && [ -z "$remaining_stages_raw" ]; then
  # The gate matrix requires an unresolved base to produce
  # prerequisite-failed even on this short-circuit: only the reviewer-
  # configuration reads (shared/platform config refs) are skippable when no
  # stage remains, not validation of the run's own base input. pr-resume's
  # authoritative base is the PR's own baseRefName (read via `gh pr view`),
  # not whatever --target-base happened to be passed on the CLI, so it must
  # be read here too, before the short-circuit — matching the full-path
  # pr-resume case below (which this branch never reaches).
  if [ "$mode" = pr-resume ]; then
    pr_json_rc=0
    clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/pr.json" "$work_dir/pr.err" \
      gh pr view "$pr" --repo "$owner/$repo" --json baseRefName || pr_json_rc=$?
    [ "$pr_json_rc" = 0 ] || fail "cannot read pull request #$pr metadata (exit $pr_json_rc): $(cat "$work_dir/pr.err" 2>/dev/null)"
    pr_base=$(jq -er '.baseRefName' "$work_dir/pr.json") || fail 'pull request metadata missing baseRefName'
    if is_option_or_refspec_like "$pr_base"; then
      prerequisite_failed_report "pull request #$pr's base branch is not a valid branch name: $pr_base"
    fi
    target_base="$pr_base"
  fi
  resolve_target_base_or_fail "$target_base" "--target-base"
  input_json="$work_dir/input.json"
  build_input_rc=0
  clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
  run_bounded "$bound" "$work_dir/build-input.out" "$work_dir/build-input.err" \
    python3 "$SCRIPT_DIR/reviewer_preflight_build_input.py" \
    --target-base "$target_base" \
    --remaining-stages "" \
    --remaining-stages-provided 1 \
    --pr-state "$pr_state_raw" \
    --checked-shared-config-ref "" \
    --checked-platform-config-ref "" \
    --local-override-state none \
    --output "$input_json" || build_input_rc=$?
  [ "$build_input_rc" = 0 ] || fail "reviewer_preflight_build_input.py failed (exit $build_input_rc): $(cat "$work_dir/build-input.err" 2>/dev/null)"
else
case "$mode" in
  pre-dispatch)
    resolve_target_base_or_fail "$target_base" "--target-base"
    shared_ref="$resolved_remote_sha"
    platform_ref="$resolved_remote_sha"
    checked_shared_config_ref="origin/$target_base:.ai-dev-workflow.yaml (this item's targeted base, before a branch exists)"
    checked_platform_config_ref="origin/$target_base:.coderabbit.yaml (this item's targeted base, before a branch exists)"
    ;;
  branch-resume)
    resolve_target_base_or_fail "$target_base" "--target-base"
    shared_ref="$resolved_remote_sha"
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
    # The branch may genuinely not exist on the remote yet (not pushed);
    # resolve_remote_sha's own rc=1 (via ls-remote --exit-code) distinguishes
    # that confirmed-absent case from an operational query failure — no
    # stale-local-cache risk to guard against here at all (unlike the `git
    # fetch` this used to run): ls-remote never writes a local
    # remote-tracking ref, so there is nothing left behind to go stale.
    local_branch_ref="refs/heads/$branch"
    # `rev-parse --verify` is normally instant, but on a slow object store
    # or stalled filesystem it can hang like any other git subprocess this
    # script reads through — bound it the same way as the ancestry checks
    # below (plain clamp_bound, not the floor variant, for the same
    # total-wall-clock reason). A bounded timeout (124) here is a distinct,
    # fail-closed outcome from "does not resolve" (the resolve probe's own
    # rc=1): the former means this script could not determine whether the
    # ref exists at all, not that it confirmed it does not.
    local_resolves=0 origin_resolves=0
    local_resolve_rc=0
    clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/resolve-local.out" "$work_dir/resolve-local.err" \
      git -C "$repo_root" rev-parse --verify --quiet "${local_branch_ref}^{commit}" || local_resolve_rc=$?
    if [ "$local_resolve_rc" = 124 ]; then
      fail "cannot determine whether local branch '$branch' exists: the ref resolution probe did not complete within the time budget"
    fi
    [ "$local_resolve_rc" = 0 ] && local_resolves=1
    origin_resolve_rc=0
    resolve_remote_sha "$branch" || origin_resolve_rc=$?
    case "$origin_resolve_rc" in
      0) origin_resolves=1; remote_branch_sha="$resolved_remote_sha" ;;
      1) origin_resolves=0 ;; # confirmed absent on the remote right now — not pushed yet
      124) fail "cannot determine whether remote branch '$branch' exists: the ls-remote query did not complete within the time budget" ;;
      *) fail "cannot query the remote for branch '$branch' (exit $origin_resolve_rc): $(cat "$work_dir/lsremote.err" 2>/dev/null)" ;;
    esac
    if [ "$local_resolves" = 1 ] && [ "$origin_resolves" = 1 ]; then
      # This script never fetches (issue #1561 round-26: "Keep preflight
      # fetches out of repository state"), so the remote's resolved SHA's
      # commit object is not guaranteed to already be present in the local
      # object database — and unlike read_ref_file's own git-show/
      # rev-parse-verify combination (which can already disambiguate
      # "object missing" from "path missing" for a plain content read),
      # `merge-base --is-ancestor` needs BOTH commit objects present just to
      # answer the ancestry question at all. Check presence explicitly
      # first and fail closed (a tooling failure, matching the sibling
      # "diverged" case below — this is a run-environment limitation, not a
      # bad run input, so prerequisite-failed does not apply) rather than
      # attempt a comparison merge-base cannot answer, or silently treat
      # "can't tell" as "not an ancestor."
      remote_object_rc=0
      clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
      run_bounded "$bound" "$work_dir/remote-object.out" "$work_dir/remote-object.err" \
        git -C "$repo_root" cat-file -e "${remote_branch_sha}^{commit}" || remote_object_rc=$?
      if [ "$remote_object_rc" = 124 ]; then
        fail "cannot determine whether the remote copy of branch '$branch' ($remote_branch_sha) is present locally: the object-presence check did not complete within the time budget"
      fi
      if [ "$remote_object_rc" != 0 ]; then
        fail "the remote copy of branch '$branch' is at commit $remote_branch_sha, which is not present in this local checkout — this preflight does not fetch (it is read-only by design); fetch it locally (e.g. git fetch origin $branch) before re-running so this preflight can determine which copy's .coderabbit.yaml is the branch in force"
      fi
      # `merge-base --is-ancestor` walks commit history and can be slow on a
      # large history or stalled filesystem, the same class of
      # unbounded-wall-clock risk the AC-2 porcelain checks above had.
      # Bound each call — but with the plain (non-floor) variant, not the
      # porcelain checks' clamp_bound_floor: those are each a single,
      # essential, final-mile check, while this is a decision-branching
      # step that can run up to twice per invocation. Granting a fresh
      # per-check floor here would let branch-resume repeatedly re-extend
      # past the whole invocation's nominal deadline (Decision 3's
      # total-wall-clock guarantee) once the budget is already exhausted,
      # rather than merely tolerating one bounded final check. Fail
      # closed — not silently treat a timeout as "not an ancestor" —
      # whether that timeout comes from a genuine stall or from the
      # deadline already being spent (bound=0).
      ancestry_rc_a=0
      clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
      run_bounded "$bound" "$work_dir/ancestry-a.out" "$work_dir/ancestry-a.err" \
        git -C "$repo_root" merge-base --is-ancestor "$remote_branch_sha" "$local_branch_ref" || ancestry_rc_a=$?
      if [ "$ancestry_rc_a" = 124 ]; then
        fail "cannot determine whether the local and remote copies of branch '$branch' have diverged: the ancestry check did not complete within the time budget"
      fi
      if [ "$ancestry_rc_a" = 0 ]; then
        platform_ref="$local_branch_ref"
        checked_platform_config_ref="$branch:.coderabbit.yaml (this item's existing branch; the local copy is at or ahead of the remote)"
      else
        ancestry_rc_b=0
        clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
        run_bounded "$bound" "$work_dir/ancestry-b.out" "$work_dir/ancestry-b.err" \
          git -C "$repo_root" merge-base --is-ancestor "$local_branch_ref" "$remote_branch_sha" || ancestry_rc_b=$?
        if [ "$ancestry_rc_b" = 124 ]; then
          fail "cannot determine whether the local and remote copies of branch '$branch' have diverged: the ancestry check did not complete within the time budget"
        fi
        if [ "$ancestry_rc_b" = 0 ]; then
          platform_ref="$remote_branch_sha"
          checked_platform_config_ref="origin/$branch:.coderabbit.yaml (this item's existing branch, refreshed from the remote; the local copy is behind)"
        else
          fail "the local and remote copies of branch '$branch' have diverged (neither is an ancestor of the other) — reconcile them (pull/rebase, or push local changes) before re-running; this preflight cannot determine which copy's .coderabbit.yaml is the branch in force"
        fi
      fi
    elif [ "$origin_resolves" = 1 ]; then
      platform_ref="$remote_branch_sha"
      checked_platform_config_ref="origin/$branch:.coderabbit.yaml (this item's existing branch, resolved from the remote; no local copy of it exists in this checkout)"
    elif [ "$local_resolves" = 1 ]; then
      platform_ref="$local_branch_ref"
      checked_platform_config_ref="$branch:.coderabbit.yaml (this item's existing branch, no pull request yet)"
    else
      # Neither the local nor the remote copy resolves — the branch this
      # mode was invoked to resume against does not currently exist
      # anywhere this script can see it (e.g. deleted after Protocol 91's
      # own resume-state discovery already chose branch-resume on the
      # assumption an existing branch is present). Reproduced live: the
      # previous fallback here silently set platform_ref to a nonexistent
      # local ref, which read_ref_file then correctly reported as
      # unreadable (rc=2) — but that only degrades this ONE platform's own
      # verdict to Undetermined/check-inconclusive, not the whole run, so
      # OUTCOME could still be passed-unverified (or even passed, when no
      # configured platform's own read actually exercises platform_ref) —
      # exit 0 despite branch-resume's own precondition (an existing
      # branch) being violated. Fail closed instead: this is an invalid
      # resume state, a tooling/environment inconsistency, not a
      # reviewer-configuration verdict to report.
      fail "branch-resume was invoked for branch '$branch', but it resolves neither locally nor on the remote — it does not currently exist; branch-resume requires an existing branch (Protocol 91's own resume-state discovery should not have selected this mode otherwise)"
    fi
    ;;
  pr-resume)
    pr_json_rc=0
    clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
    run_bounded "$bound" "$work_dir/pr.json" "$work_dir/pr.err" \
      gh pr view "$pr" --repo "$owner/$repo" --json baseRefName,headRefName,headRefOid || pr_json_rc=$?
    [ "$pr_json_rc" = 0 ] || fail "cannot read pull request #$pr metadata (exit $pr_json_rc): $(cat "$work_dir/pr.err" 2>/dev/null)"
    pr_base=$(jq -er '.baseRefName' "$work_dir/pr.json") || fail 'pull request metadata missing baseRefName'
    pr_head=$(jq -er '.headRefName' "$work_dir/pr.json") || fail 'pull request metadata missing headRefName'
    pr_head_sha=$(jq -er '.headRefOid' "$work_dir/pr.json") || fail 'pull request metadata missing headRefOid'
    # gh-reported baseRefName is a value this script does not control (a PR
    # can target any ref-format-valid branch name) and reaches
    # resolve_remote_sha the same unvalidated way the CLI --target-base
    # value used to — the same option/refspec-injection risk applies here,
    # not only to CLI input.
    if is_option_or_refspec_like "$pr_base"; then
      prerequisite_failed_report "pull request #$pr's base branch is not a valid branch name: $pr_base"
    fi
    target_base="$pr_base"
    resolve_target_base_or_fail "$pr_base" "pull request #$pr's base branch"
    shared_ref="$resolved_remote_sha"
    # headRefOid is GitHub's own current head SHA for this PR — read
    # directly by that SHA, no fetch and no temporary ref needed. The
    # earlier design fetched the PR head into a uniquely-named
    # refs/reviewer-preflight/pr-<n>.<work-dir> ref so read_ref_file could
    # address it the same way as every other ref; reading by raw SHA the
    # same way this script now reads every remote tip makes that temporary
    # ref, and its cleanup-trap bookkeeping, unnecessary. If the PR head
    # object is not already present locally, read_ref_file's own
    # git-show/rev-parse-verify fallback degrades gracefully
    # (Undetermined/check-inconclusive for the coderabbit platform read
    # below), the same as any other unreadable platform surface.
    platform_ref="$pr_head_sha"
    checked_shared_config_ref="origin/$pr_base:.ai-dev-workflow.yaml (PR #$pr's own target base branch, refreshed)"
    checked_platform_config_ref="PR #$pr's own branch ($pr_head):.coderabbit.yaml"
    ;;
esac

# #1561 round-8 finding: validate the remaining-stage set (and, for a
# non-empty stage set, --pr-state) BEFORE any configuration is read — a
# git-show/read_ref_file failure on the (now-resolved) base or branch/PR
# ref below must not mask an earlier malformed or omitted
# --remaining-stages/--pr-state input behind an unstructured tooling
# failure (exit 3) instead of the documented prerequisite-failed (exit 2)
# the decision matrix requires for that malformed input. reviewer_
# preflight_build_input.py's own stage-list parsing and reviewer_
# preflight.py's classify() are the single source of truth for what counts
# as a malformed stage set or pull-request state; reuse them directly here
# against an otherwise-empty payload (no shared/resolved/platform data has
# been read yet, and none of this validation needs any) rather than
# duplicating that logic in bash, where it could drift. The explicit empty
# --remaining-stages short-circuit above already handles its own case
# before ever reaching this branch, so this only ever runs for an omitted,
# non-empty, or malformed stage set.
early_input_json="$work_dir/early-input.json"
early_build_rc=0
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$work_dir/early-build.out" "$work_dir/early-build.err" \
  python3 "$SCRIPT_DIR/reviewer_preflight_build_input.py" \
  --target-base "$target_base" \
  --remaining-stages "$remaining_stages_raw" \
  --remaining-stages-provided "$remaining_stages_provided" \
  --pr-state "$pr_state_raw" \
  --output "$early_input_json" || early_build_rc=$?
[ "$early_build_rc" = 0 ] || fail "reviewer_preflight_build_input.py failed (exit $early_build_rc): $(cat "$work_dir/early-build.err" 2>/dev/null)"
early_output_json="$work_dir/early-output.json"
early_classify_rc=0
clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$early_output_json" "$work_dir/early-classify.err" \
  python3 "$SCRIPT_DIR/reviewer_preflight.py" --input-json "$early_input_json" || early_classify_rc=$?
if [ "$early_classify_rc" -gt 3 ] || { [ "$early_classify_rc" != 0 ] && ! jq -e . "$early_output_json" >/dev/null 2>&1; }; then
  cat "$work_dir/early-classify.err" >&2
  fail "reviewer_preflight.py failed (exit $early_classify_rc)"
fi
early_outcome=$(jq -er '.outcome' "$early_output_json") || fail 'cannot inspect early stage-set validation output'
if [ "$early_outcome" = prerequisite-failed ]; then
  early_detail=$(jq -er '.prerequisite_detail' "$early_output_json") || early_detail='the set of lifecycle stages this run will exercise is unresolved or malformed'
  prerequisite_failed_report "$early_detail"
fi

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
if [ -n "$local_override_file" ]; then
  if [ ! -f "$local_override_file" ]; then
    # review-overrides resolved a local override path (a non-empty
    # LOCAL_OVERRIDE_FILE), but by the time this script's own [ -f ] test
    # runs, that path is no longer a regular readable file — it
    # disappeared, or was replaced by something else, in the window
    # between review-overrides's own resolution and this check. Silently
    # falling through here (the previous behavior) leaves
    # local_override_state="none" and resolves reviewer lists as if no
    # local override existed at all — a different, unreported outcome
    # than the one review-overrides itself just proved. This is a tooling
    # failure, not "no override configured"; fail closed rather than
    # silently proceed without it.
    fail "the local override file ($local_override_file) that review-overrides resolved no longer exists as a readable regular file — it may have been deleted or replaced after review-overrides resolved it"
  fi
  # An unguarded `cp` here is terminated by `set -e` on failure with the
  # command's own exit status (typically 1) — the same exit code this
  # script's own structured `blocked` verdict (OUTCOME=blocked) uses, but
  # with no OUTCOME report at all, since the script never reaches the
  # point that would print one. A caller distinguishing outcomes by exit
  # code alone could misclassify this staging/tooling failure (the file
  # disappearing or becoming unreadable between the check above and this
  # copy) as a reviewer-configuration disagreement. Route it through
  # fail() instead, so it is unambiguously a tooling failure (exit 3)
  # with diagnostic context.
  cp -- "$local_override_file" "$shared_dir/.ai-dev-workflow.local.yaml" || fail "cannot copy the local override file ($local_override_file) for reading: it may have disappeared or become unreadable after the presence check just above"
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

after_porcelain_rc=0
clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"
run_bounded "$bound" "$work_dir/porcelain-after.out" "$work_dir/porcelain-after.err" \
  git --no-optional-locks -C "$repo_root" status --porcelain || after_porcelain_rc=$?
after_porcelain=$(cat "$work_dir/porcelain-after.out" 2>/dev/null || true)
# A bounded-timeout (124) on either snapshot is not the same as "no
# changes": both sides could time out and compare equal-empty while the
# working tree genuinely changed in between, silently defeating AC-2's own
# no-side-effects contract instead of merely failing to prove it. Any other
# git status failure (e.g. --repo-root not being a git repository) is
# already handled by both sides comparing equal-empty, per the existing
# accepted rationale below; only a timeout gets this separate, explicit
# check.
if [ "$before_porcelain_rc" = 124 ] || [ "$after_porcelain_rc" = 124 ]; then
  fail 'cannot verify reviewer-preflight.sh made no working-tree changes (AC-2): the git status --porcelain check did not complete within the time budget'
fi
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
