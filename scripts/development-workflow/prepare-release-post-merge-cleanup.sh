#!/usr/bin/env bash
#
# Post-merge cleanup for a release branch:
# - verifies release PRs to main and the configured backport base are both merged
# - deletes remote release branch (if present)
# - deletes local release branch (switching away first if needed)
# - stamps scoped issue numbers with the release version
# - transitions scoped issue numbers from merged -> released, or emits a
#   fail-closed tracker handoff when shell automation cannot complete them
#
# Usage:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh <version|release-branch> [--repo NAME --repo-root PATH --evidence-file PATH] [--backport-base BRANCH] [--from-changelog] [--issue N]... [--issues N,N,...] [--best-effort]
#
# --from-changelog:
#   GitHub Projects / GitHub Issues: extract #NNN references from the CHANGELOG
#   version section (unchanged; missing file/section fails closed). Linear:
#   CHANGELOG text alone does NOT define release scope — it is only a complement.
#   Scope is Linear IDs from merged PRs in the previous-tag..release commit
#   range (derived even when CHANGELOG.md or the version section is missing;
#   that case prints CHANGELOG_SECTION_UNAVAILABLE and continues). Each commit
#   is resolved to its PR(s) via GitHub (commits/<sha>/pulls only — subject
#   "(#N)" / "Merge pull request #N" is never sufficient PR evidence). A
#   well-formed empty array [] means the commit has no associated PR
#   (RELEASE_SCOPE_COMMIT_WITHOUT_PR; scope stays complete). Empty body,
#   non-array JSON, [null], [{}], or any element missing an integer number or
#   a merged_at/merged/mergedAt field is RELEASE_SCOPE_INCOMPLETE. IDs are
#   taken only from each PR's headRefName / REST head.ref and title — never
#   from commit text or PR body. Documentation-stage head branches (spec/*,
#   implementation-plan/*) are not shipping evidence (RELEASE_SCOPE_SKIPPED
#   reason=documentation_stage_pr_only when that is the only evidence).
#   Preceding-tag boundary must be verified from remote ls-remote --tags without
#   fetching, using the same tag PREFIX as the release (v / mobile-v / empty) and
#   full SemVer 2.0.0 precedence including prerelease (build metadata ignored).
#   first_release only when no same-prefix tag is strictly lower. Shallow /
#   remote tag-list failure / missing or disagreeing local preceding commit →
#   RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable.
#   Release tip is only refs/tags/<name> or authorized --release-head SHA (never
#   unqualified names that could resolve a branch). Merged PR prefixes other
#   than documentation-stage and release/backport count as shipping evidence
#   (chore/ci/… included; spec/implementation-plan and release/backport skipped
#   with RELEASE_SCOPE_SKIPPED). Changelog-only mentions are
#   RELEASE_SCOPE_SKIPPED. Never fall back to checkout HEAD. Zero Linear IDs
#   after complete resolution is empty scope success. Explicit --issue/--issues
#   are unioned and never filtered.
#
# Examples:
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh 1.2.3
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --issue 232 --issue 240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --from-changelog
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issues 232,240 --best-effort
#   ./scripts/development-workflow/prepare-release-post-merge-cleanup.sh mobile-app/release/v1.2.3 --backport-base release
#
# Exit codes for tracker cleanup (unless --best-effort is passed):
#   0  At least one issue was updated (or already in Released status) and no hard failures
#      occurred. Issues already in Released status count as success.
#   1  updated==0 after processing all issues, or at least one hard failure occurred
#
# Output (when --issues is supplied):
#   Emits structured key/value summary line:
#   STAMPED=N STAMP_SKIPPED=N STAMP_FAILED=N UPDATED=N SKIPPED=N FAILED=N
#
# Env overrides:
#   GITHUB_PROJECT_STATUS_MERGED   (default: Merged)
#   GITHUB_PROJECT_STATUS_RELEASED (default: Released)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_ARGS=("$@")
# shellcheck source=scripts/development-workflow/workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root
require_gh

# Detect tracker provider early so that issue-ID validation can accept
# Linear-style identifiers (e.g. LH-57) when the provider is "linear".
TRACKER_PROVIDER="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"

MERGED_LABEL="${GITHUB_PROJECT_STATUS_MERGED:-Merged}"
RELEASED_LABEL="${GITHUB_PROJECT_STATUS_RELEASED:-Released}"
RELEASE_INPUT=""
BACKPORT_BASE="${RELEASE_BACKPORT_BASE:-develop}"
BACKPORT_BASE_OVERRIDE=""
BEST_EFFORT=false
FROM_CHANGELOG=false
PRODUCT_REPO=""
REPO_ROOT_OVERRIDE=""
EVIDENCE_FILE=""
JSON_OUTPUT=false
INSPECT_TARGETS=false
RELEASE_HEAD=""
RELEASE_HEAD_SET=false
RELEASE_TARGET_ROOT=""
MERGE_SESSION=""
SESSION_CHILD=false
COMPONENT_TARGET_FILE=""
COMPONENT_LOCK_DIR=""
COMPONENT_LOCK_CREATED=false
# Set to "true" once component mode (--evidence-file) and --json are both
# confirmed. When true, cleanup_log() routes progress/diagnostic output to
# stderr so stdout carries only the final JSON summary the documented
# component-release smoke flow parses with jq -- see cleanup_log() below.
COMPONENT_JSON_MODE=false
declare -a ISSUE_NUMBERS=()
# Explicit --issue/--issues captured at parse time; Linear --from-changelog
# filter must never drop these (unioned after derived scope).
declare -a EXPLICIT_ISSUE_NUMBERS=()

usage() {
  echo "Usage: $0 <version|release-branch> [--repo NAME --repo-root PATH --evidence-file PATH] [--backport-base BRANCH] [--from-changelog] [--issue N]... [--issues N,N,...] [--best-effort] [--json] [--inspect-targets --release-head SHA [--target-root PATH]] [--merge-session PATH]" >&2
  echo "  --from-changelog  GitHub: scope from CHANGELOG #NNN refs. Linear: scope from" >&2
  echo "                    merged PRs in the release commit range (IDs from PR" >&2
  echo "                    headRefName/head.ref and title); changelog-only IDs" >&2
  echo "                    are skipped. Explicit --issue/--issues are always kept." >&2
}

# Parallel arrays populated when Linear --from-changelog omits changelog-only IDs.
declare -a RELEASE_SCOPE_SKIPPED_ISSUES=()
declare -a RELEASE_SCOPE_SKIPPED_REASONS=()

record_release_scope_skip() {
  local issue="$1"
  local reason="$2"
  local i
  # Explicit --issue/--issues are always proposed (unioned after the filter).
  # Never report them as RELEASE_SCOPE_SKIPPED / release_scope_skipped.
  for i in ${EXPLICIT_ISSUE_NUMBERS[@]+"${EXPLICIT_ISSUE_NUMBERS[@]}"}; do
    if [ "$i" = "$issue" ]; then
      return 0
    fi
  done
  for i in ${RELEASE_SCOPE_SKIPPED_ISSUES[@]+"${RELEASE_SCOPE_SKIPPED_ISSUES[@]}"}; do
    if [ "$i" = "$issue" ]; then
      return 0
    fi
  done
  RELEASE_SCOPE_SKIPPED_ISSUES+=("$issue")
  RELEASE_SCOPE_SKIPPED_REASONS+=("$reason")
  cleanup_log "RELEASE_SCOPE_SKIPPED issue=${issue} reason=${reason}"
}

normalize_release_branch() {
  local value="$1"
  value="${value#refs/heads/}"
  case "$value" in
    release/v*) printf '%s\n' "$value" ;;
    release/*/*) printf '%s\n' "$value" ;;
    release/*) printf 'release/v%s\n' "${value#release/}" ;;
    */*) printf '%s\n' "$value" ;;
    v*) printf 'release/%s\n' "$value" ;;
    *) printf 'release/v%s\n' "$value" ;;
  esac
}

release_version_from_branch() {
  local value="$1"
  printf '%s\n' "${value##*/}"
}

# Tag spelling as requested by the caller (before release-branch v-injection).
# Bare `1.1.0` stays `1.1.0` even though normalize_release_branch yields
# release/v1.1.0. Used only for Linear namespace/boundary resolution and Linear
# CHANGELOG lookup — never for github_projects/github_issues RELEASE_VERSION
# (milestones, stamps, markers, projection identity).
release_tag_request_from_input() {
  local value="$1"
  value="${value#refs/heads/}"
  value="${value#refs/tags/}"
  case "$value" in
    release/*/*) printf '%s\n' "${value##*/}" ;;
    release/*) printf '%s\n' "${value#release/}" ;;
    */*) printf '%s\n' "${value##*/}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

# Linear component tip/previous identity: validated evidence.component_tag only
# (never the branch-suffix spelling). Charset matches workflow-merge-budget
# publicationTag; SemVer shape matches Linear CHANGELOG / boundary parsing.
validate_linear_component_release_tag() {
  local tag="$1"
  case "$tag" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  python3 -c '
import re, sys
tag = sys.argv[1]
match = re.fullmatch(
    r"^(?P<prefix>.*?)(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$",
    tag,
)
if not match:
    sys.exit(1)
prefix = match.group("prefix")
if prefix not in ("", "v") and (not prefix or prefix[-1].isdigit()):
    sys.exit(1)
' "$tag"
}

validate_portable_branch_name() {
  local label="$1"
  local value="$2"
  if [ -z "$value" ]; then
    echo "Invalid ${label} branch name: value is empty" >&2
    exit 2
  fi
  if ! git check-ref-format --branch "$value" >/dev/null 2>&1; then
    echo "Invalid ${label} branch name: $value" >&2
    exit 2
  fi
}

canonical_dir() {
  local path="$1"
  (CDPATH='' cd -- "$path" && pwd -P)
}

cleanup_component_lock() {
  if [ "$COMPONENT_LOCK_CREATED" = "true" ] && [ -n "$COMPONENT_LOCK_DIR" ] && [ -d "$COMPONENT_LOCK_DIR" ]; then
    rmdir "$COMPONENT_LOCK_DIR" 2>/dev/null || true
  fi
  if [ -n "$COMPONENT_TARGET_FILE" ] && [ -f "$COMPONENT_TARGET_FILE" ]; then
    rm -f "$COMPONENT_TARGET_FILE"
  fi
}

json_field() {
  local path="$1"
  local query="$2"
  jq -r "$query // \"\"" "$path"
}

# Prints progress/diagnostic output. In COMPONENT_JSON_MODE this goes to
# stderr instead of stdout, so a single final JSON object (see the end of
# the component cleanup success path) is the only thing on stdout for
# --json callers -- otherwise identical to a plain echo.
cleanup_log() {
  if [ "$COMPONENT_JSON_MODE" = "true" ]; then
    printf '%s\n' "$*" >&2
  else
    printf '%s\n' "$*"
  fi
}

# Emits the single JSON summary object for a component cleanup run (only
# called when COMPONENT_JSON_MODE is true). Reflects what this script
# actually did this run: branch deletion and tracker mutation outcomes.
# Known gap: this script does not delete a release tag (no tag-deletion
# logic exists) and never writes cleanup_outcome back to the evidence file
# on disk -- cleanup_evidence.status here reports this run's own outcome,
# not a persisted evidence-file field.
emit_component_cleanup_json() {
  local cleanup_outcome="$1"
  local after_product_cleanup="$2"
  local cleanup_evidence_status="$3"
  local required_next_action="${4:-}"
  local lock_key issues_csv already_complete skipped_json
  local idx skipped_issue skipped_reason
  lock_key="$(json_field "$COMPONENT_TARGET_FILE" '.release_correlation_key')"
  issues_csv=""
  if [ "${#ISSUE_NUMBERS[@]}" -gt 0 ]; then
    issues_csv="$(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  fi
  already_complete="false"
  if [ "${REMOTE_BRANCH_DELETED:-false}" != "true" ] && [ "${LOCAL_BRANCH_DELETED:-false}" != "true" ]; then
    already_complete="true"
  fi

  # release_scope_skipped is Linear-only. GitHub providers keep origin/develop's
  # component JSON shape (no field) byte-identical.
  if [ "$TRACKER_PROVIDER" != "linear" ]; then
    jq -cnS \
      --arg schema_version "component_release_cleanup.v1" \
      --arg cleanup_outcome "$cleanup_outcome" \
      --arg product_repo "$PRODUCT_REPO" \
      --argjson remote_branch_deleted "${REMOTE_BRANCH_DELETED:-false}" \
      --argjson local_branch_deleted "${LOCAL_BRANCH_DELETED:-false}" \
      --argjson already_complete "$already_complete" \
      --arg lock_owner "hub" \
      --arg release_correlation_key "$lock_key" \
      --arg tracker_owner "hub_repository" \
      --arg issues_csv "$issues_csv" \
      --argjson after_product_cleanup "$after_product_cleanup" \
      --arg cleanup_evidence_status "$cleanup_evidence_status" \
      --arg required_next_action "$required_next_action" \
      '{
        schema_version:$schema_version,
        cleanup_outcome:$cleanup_outcome,
        product_cleanup:{
          repository_key:$product_repo,
          remote_branch_deleted:$remote_branch_deleted,
          local_branch_deleted:$local_branch_deleted,
          already_complete:$already_complete
        },
        cleanup_lock:{
          owner:$lock_owner,
          release_correlation_key:$release_correlation_key
        },
        tracker_mutation:{
          repository_owner:$tracker_owner,
          issues:(if ($issues_csv|length) > 0 then ($issues_csv | split(",")) else [] end),
          after_product_cleanup:$after_product_cleanup
        },
        cleanup_evidence:{
          status:$cleanup_evidence_status
        }
      } + (if ($required_next_action|length) > 0 then {required_next_action:$required_next_action} else {} end)'
    return 0
  fi

  skipped_json="[]"
  if [ "${#RELEASE_SCOPE_SKIPPED_ISSUES[@]}" -gt 0 ]; then
    skipped_json="$(
      idx=0
      while [ "$idx" -lt "${#RELEASE_SCOPE_SKIPPED_ISSUES[@]}" ]; do
        skipped_issue="${RELEASE_SCOPE_SKIPPED_ISSUES[$idx]}"
        skipped_reason="${RELEASE_SCOPE_SKIPPED_REASONS[$idx]}"
        printf '%s\t%s\n' "$skipped_issue" "$skipped_reason"
        idx=$((idx + 1))
      done | jq -Rsc 'split("\n") | map(select(length>0) | split("\t") | {issue:.[0], reason:.[1]})'
    )"
  fi
  jq -cnS \
    --arg schema_version "component_release_cleanup.v1" \
    --arg cleanup_outcome "$cleanup_outcome" \
    --arg product_repo "$PRODUCT_REPO" \
    --argjson remote_branch_deleted "${REMOTE_BRANCH_DELETED:-false}" \
    --argjson local_branch_deleted "${LOCAL_BRANCH_DELETED:-false}" \
    --argjson already_complete "$already_complete" \
    --arg lock_owner "hub" \
    --arg release_correlation_key "$lock_key" \
    --arg tracker_owner "hub_repository" \
    --arg issues_csv "$issues_csv" \
    --argjson release_scope_skipped "$skipped_json" \
    --argjson after_product_cleanup "$after_product_cleanup" \
    --arg cleanup_evidence_status "$cleanup_evidence_status" \
    --arg required_next_action "$required_next_action" \
    '{
      schema_version:$schema_version,
      cleanup_outcome:$cleanup_outcome,
      product_cleanup:{
        repository_key:$product_repo,
        remote_branch_deleted:$remote_branch_deleted,
        local_branch_deleted:$local_branch_deleted,
        already_complete:$already_complete
      },
      cleanup_lock:{
        owner:$lock_owner,
        release_correlation_key:$release_correlation_key
      },
      tracker_mutation:{
        repository_owner:$tracker_owner,
        issues:(if ($issues_csv|length) > 0 then ($issues_csv | split(",")) else [] end),
        after_product_cleanup:$after_product_cleanup
      },
      release_scope_skipped:$release_scope_skipped,
      cleanup_evidence:{
        status:$cleanup_evidence_status
      }
    } + (if ($required_next_action|length) > 0 then {required_next_action:$required_next_action} else {} end)'
}

cleanup_git() {
  if [ -n "$COMPONENT_TARGET_FILE" ]; then
    git -C "$(json_field "$COMPONENT_TARGET_FILE" '.local_checkout.path')" "$@"
  else
    git "$@"
  fi
}

cleanup_gh_pr_list() {
  local identity
  if [ -n "$COMPONENT_TARGET_FILE" ]; then
    identity="$(json_field "$COMPONENT_TARGET_FILE" '.canonical_repository_identity')"
    if ! workflow_is_valid_github_repo_slug "$identity"; then
      echo "COMPONENT_CLEANUP_ERROR=invalid_repository_identity IDENTITY=${identity:-<empty>}" >&2
      return 1
    fi
    gh pr list --repo "$identity" "$@"
    return $?
  fi
  gh pr list "$@"
}

compare_component_field() {
  local field="$1"
  local current
  local recorded
  current="$(jq -c "$field" "$COMPONENT_TARGET_FILE")"
  recorded="$(jq -c ".target_binding${field}" "$EVIDENCE_FILE")"
  if [ "$current" != "$recorded" ]; then
    echo "Component release evidence mismatch for $field: current=$current evidence=$recorded" >&2
    exit 1
  fi
}

validate_component_release_cleanup() {
  local hub_root="$1"
  local target_path target_outcome evidence_schema evidence_cleanup lock_key lock_parent safe_lock_key evidence_branch contract_base hub_git_dir

  if [ -z "$PRODUCT_REPO" ] && [ -z "$EVIDENCE_FILE" ]; then
    return 0
  fi
  if [ -z "$PRODUCT_REPO" ]; then
    echo "--repo is required when --evidence-file is supplied for component release cleanup." >&2
    exit 2
  fi
  if [ -z "$EVIDENCE_FILE" ]; then
    echo "--evidence-file is required for component release cleanup in workflow_hub mode." >&2
    exit 2
  fi
  if [ ! -f "$EVIDENCE_FILE" ]; then
    echo "Component release evidence file not found: $EVIDENCE_FILE" >&2
    exit 2
  fi
  if ! jq -e 'type == "object"' "$EVIDENCE_FILE" >/dev/null 2>&1; then
    echo "Component release evidence file must contain a JSON object: $EVIDENCE_FILE" >&2
    exit 2
  fi

  evidence_schema="$(json_field "$EVIDENCE_FILE" '.schema_version')"
  if [ "$evidence_schema" != "component_release_evidence.v1" ]; then
    echo "Component release evidence must use schema_version component_release_evidence.v1." >&2
    exit 2
  fi

  # Read release_branch before re-resolving the target and pass it as
  # --release-branch so the freshly resolved target reproduces the same
  # per-attempt release_correlation_key recorded in the persisted evidence,
  # instead of a contract-only key shared by every release of this product.
  evidence_branch="$(json_field "$EVIDENCE_FILE" '.release_branch')"
  if [ -z "$evidence_branch" ]; then
    echo "Component release evidence is missing required field: release_branch" >&2
    exit 1
  fi

  COMPONENT_TARGET_FILE="$(mktemp "${TMPDIR:-/tmp}/component-release-target.XXXXXX")"
  trap cleanup_component_lock EXIT
  component_target_args=(--repo-root "$hub_root" --repo "$PRODUCT_REPO")
  [ -n "$evidence_branch" ] && component_target_args+=(--release-branch "$evidence_branch")
  if ! "$SCRIPT_DIR/component-release-target.sh" "${component_target_args[@]}" --json > "$COMPONENT_TARGET_FILE"; then
    echo "Could not resolve current component release target for '$PRODUCT_REPO'." >&2
    exit 1
  fi
  target_outcome="$(json_field "$COMPONENT_TARGET_FILE" '.routing_outcome')"
  if [ "$target_outcome" != "component_release_routed" ]; then
    echo "Component release target is not mutation-allowed: $target_outcome" >&2
    exit 1
  fi

  require_evidence_identity_field() {
    local field="$1"
    local value
    value="$(json_field "$EVIDENCE_FILE" ".target_binding${field}")"
    if [ -z "$value" ]; then
      echo "Component release evidence is missing required identity field: ${field#.}" >&2
      exit 1
    fi
  }

  require_evidence_identity_field '.routing_outcome'
  require_evidence_identity_field '.selected_product_repo_key'
  require_evidence_identity_field '.canonical_repository_identity'
  require_evidence_identity_field '.release_correlation_key'
  require_evidence_identity_field '.contract_revision'

  owner_field=""
  for owner_field in release ci github_release deployment cleanup tracker; do
    owner_value="$(json_field "$EVIDENCE_FILE" ".target_binding.artifact_owners.${owner_field}")"
    if [ -z "$owner_value" ]; then
      echo "Component release evidence is missing required identity field: artifact_owners" >&2
      exit 1
    fi
  done

  compare_component_field '.routing_outcome'
  compare_component_field '.selected_product_repo_key'
  compare_component_field '.canonical_repository_identity'
  compare_component_field '.artifact_owners'
  compare_component_field '.release_correlation_key'
  compare_component_field '.contract_revision'

  target_path="$(json_field "$COMPONENT_TARGET_FILE" '.local_checkout.path')"
  if [ -z "$target_path" ] || [ ! -d "$target_path" ]; then
    echo "Resolved product checkout is unavailable: ${target_path:-<empty>}" >&2
    exit 1
  fi
  # Use "git rev-parse --is-inside-work-tree"/"--git-dir" instead of a bare
  # ".git is a directory" test: a linked git worktree (as used by this
  # workflow's per-item isolation) has a ".git" regular file pointing at the
  # main checkout's worktree metadata, not a ".git" directory, so the
  # directory test rejects a perfectly valid checkout. target_git_dir is also
  # reused below for the cleanup lock directory, since "$target_path/.git"
  # is not writable (or even a directory) for a linked worktree either.
  if ! git -C "$target_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Resolved product checkout is not a git repository: $target_path" >&2
    exit 1
  fi
  target_git_dir="$(git -C "$target_path" rev-parse --git-dir)"
  case "$target_git_dir" in
    /*) : ;;
    *) target_git_dir="$target_path/$target_git_dir" ;;
  esac

  if [ -z "$RELEASE_INPUT" ] && [ -n "$evidence_branch" ]; then
    RELEASE_INPUT="$evidence_branch"
  fi
  if [ -z "$RELEASE_INPUT" ]; then
    echo "Component release cleanup requires a release branch/version argument or evidence.release_branch." >&2
    exit 2
  fi
  if [ -n "$evidence_branch" ] && [ "$(normalize_release_branch "$RELEASE_INPUT")" != "$evidence_branch" ]; then
    echo "Component release evidence release_branch mismatch: input=$(normalize_release_branch "$RELEASE_INPUT") evidence=$evidence_branch" >&2
    exit 1
  fi

  evidence_cleanup="$(json_field "$EVIDENCE_FILE" '.cleanup_outcome')"
  if [ -z "$evidence_cleanup" ]; then
    echo "Component release evidence is missing required field: cleanup_outcome" >&2
    exit 1
  fi
  if [ "$evidence_cleanup" = "complete" ] && [ "$INSPECT_TARGETS" != "true" ] && [ -z "$MERGE_SESSION" ]; then
    cleanup_log "Component release cleanup evidence is already complete; exiting idempotently."
    if [ "$JSON_OUTPUT" = "true" ]; then
      jq -cnS --slurpfile evidence "$EVIDENCE_FILE" '{cleanup_outcome:"already_complete", evidence:$evidence[0]}'
    fi
    exit 0
  fi

  contract_base="$(json_field "$COMPONENT_TARGET_FILE" '.release_base')"
  if [ -n "$BACKPORT_BASE_OVERRIDE" ] && [ "$BACKPORT_BASE_OVERRIDE" != "$contract_base" ]; then
    echo "--backport-base '$BACKPORT_BASE_OVERRIDE' conflicts with the component release contract base '$contract_base'." >&2
    exit 2
  fi
  BACKPORT_BASE="$contract_base"
  # Inspection validates the existing component identity but takes no mutation lease.
  if [ "$INSPECT_TARGETS" = "true" ] || { [ -n "$MERGE_SESSION" ] && [ "$SESSION_CHILD" != "true" ]; }; then
    return 0
  fi

  lock_key="$(json_field "$COMPONENT_TARGET_FILE" '.release_correlation_key')"
  safe_lock_key="$(printf '%s' "$lock_key" | tr -c 'A-Za-z0-9._-' '_')"
  # Key the lock under the HUB checkout's git-dir, not the product checkout's
  # (target_git_dir): the hub is the single coordination point in
  # workflow_hub mode, and this makes the lock mutually exclusive across
  # cleanup runs that resolve the product repo to different local
  # checkouts (e.g. a stale local_path override vs. checkout_root) as long
  # as they share one hub checkout. This is a bounded mitigation, not a
  # fully shared cross-machine lease -- see the note below.
  hub_git_dir="$(git -C "$hub_root" rev-parse --git-dir)"
  case "$hub_git_dir" in
    /*) : ;;
    *) hub_git_dir="$hub_root/$hub_git_dir" ;;
  esac
  lock_parent="$hub_git_dir/component-release-cleanup-locks"
  mkdir -p "$lock_parent"
  COMPONENT_LOCK_DIR="$lock_parent/$safe_lock_key.lock"
  if ! mkdir "$COMPONENT_LOCK_DIR" 2>/dev/null; then
    echo "Component release cleanup lock is already held for $lock_key at $COMPONENT_LOCK_DIR." >&2
    echo "KNOWN LIMITATION: this lock is local to the hub checkout at '$hub_root'." >&2
    echo "It does not exclude a concurrent run from a different hub clone or linked worktree of the same hub repository." >&2
    exit 1
  fi
  COMPONENT_LOCK_CREATED=true

  cleanup_log "Component release target: $PRODUCT_REPO ($(json_field "$COMPONENT_TARGET_FILE" '.canonical_repository_identity'))"
  cleanup_log "Component checkout: $target_path"
  contract_base="$(json_field "$COMPONENT_TARGET_FILE" '.release_base')"
  if [ -n "$BACKPORT_BASE_OVERRIDE" ] && [ "$BACKPORT_BASE_OVERRIDE" != "$contract_base" ]; then
    echo "--backport-base '$BACKPORT_BASE_OVERRIDE' conflicts with the component release contract base '$contract_base'." >&2
    exit 2
  fi
  BACKPORT_BASE="$contract_base"
}

# Returns 0 (true) if the token is a valid issue identifier for the current
# tracker provider, 1 (false) otherwise.
#   - Numeric-only IDs are accepted for any provider.
#   - Linear-style alphanumeric IDs (e.g. LH-57, PROJ-123) are accepted when
#     TRACKER_PROVIDER is "linear".
is_valid_issue_token() {
  local token="$1"
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  if [[ "$TRACKER_PROVIDER" = "linear" && "$token" =~ ^[A-Za-z][A-Za-z0-9_]*-[0-9]+$ ]]; then
    return 0
  fi
  return 1
}

parse_issue_csv() {
  local csv="$1"
  local old_ifs="$IFS"
  local part
  IFS=','
  # shellcheck disable=SC2086
  for part in $csv; do
    part="${part//[[:space:]]/}"
    [ -z "$part" ] && continue
    if ! is_valid_issue_token "$part"; then
      echo "Invalid issue number '$part' in --issues list." >&2
      exit 2
    fi
    ISSUE_NUMBERS+=("$part")
    EXPLICIT_ISSUE_NUMBERS+=("$part")
  done
  IFS="$old_ifs"
}

# Append explicit --issue/--issues into ISSUE_NUMBERS without filtering them.
union_explicit_issue_numbers() {
  local issue existing candidate
  for issue in ${EXPLICIT_ISSUE_NUMBERS[@]+"${EXPLICIT_ISSUE_NUMBERS[@]}"}; do
    existing=false
    for candidate in ${ISSUE_NUMBERS[@]+"${ISSUE_NUMBERS[@]}"}; do
      if [ "$candidate" = "$issue" ]; then
        existing=true
        break
      fi
    done
    if [ "$existing" = false ]; then
      ISSUE_NUMBERS+=("$issue")
    fi
  done
}

append_issues_from_changelog() {
  local version="$1"
  local changelog_path="${CHANGELOG_PATH:-CHANGELOG.md}"
  local extracted
  local changelog_root
  local version_disp

  changelog_root="$PWD"
  if [ -n "$RELEASE_TARGET_ROOT" ]; then
    changelog_root="$RELEASE_TARGET_ROOT"
  fi
  if [ -n "$COMPONENT_TARGET_FILE" ]; then
    changelog_root="$(json_field "$COMPONENT_TARGET_FILE" '.local_checkout.path')"
  fi

  # Branch on provider BEFORE parsing. GitHub providers keep origin/develop's
  # parser byte-identical; Linear-only heading/complement rules live below.
  if [ "$TRACKER_PROVIDER" != "linear" ]; then
    # --- github_projects / github_issues: develop append_issues_from_changelog ---
    if [ -z "$RELEASE_HEAD" ] && [ ! -f "$changelog_path" ]; then
      echo "Could not find changelog at '$changelog_path' for --from-changelog." >&2
      return 1
    fi

    if ! extracted="$(python3 - "$version" "$changelog_path" "$TRACKER_PROVIDER" "$RELEASE_HEAD" "$changelog_root" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

version = sys.argv[1]
if version.startswith("v"):
    version = version[1:]
path = Path(sys.argv[2])
provider = sys.argv[3]
head = sys.argv[4]
if head:
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        print("CHANGELOG_REVIEWED_HEAD_INVALID", file=sys.stderr)
        sys.exit(1)
    result = subprocess.run(["git", "-C", sys.argv[5], "show", head + ":CHANGELOG.md"], text=True, capture_output=True)
    if result.returncode:
        print("CHANGELOG_REVIEWED_COMMIT_UNAVAILABLE", file=sys.stderr)
        sys.exit(1)
    text = result.stdout
else:
    text = path.read_text(encoding="utf-8")

heading = re.compile(rf"^## \[(?:v?{re.escape(version)})\].*$", re.MULTILINE)
match = heading.search(text)
if not match:
    print(f"CHANGELOG_VERSION_NOT_FOUND version=v{version}", file=sys.stderr)
    sys.exit(1)

next_heading = re.search(r"^## \[", text[match.end():], re.MULTILINE)
section_end = match.end() + next_heading.start() if next_heading else len(text)
section = text[match.end():section_end]

seen = set()
issues = []

def add(value: str) -> None:
    if value not in seen:
        seen.add(value)
        issues.append(value)

if provider == "linear":
    range_re = re.compile(r"\b([A-Z][A-Z0-9_]*-)(\d+)\s*[\u2013-]\s*(?:[A-Z][A-Z0-9_]*-)?(\d+)\b")
    for item in range_re.finditer(section):
        prefix = item.group(1)
        start = int(item.group(2))
        end = int(item.group(3))
        if end < start:
            start, end = end, start
        for number in range(start, end + 1):
            add(f"{prefix}{number}")

    for item in re.finditer(r"\b[A-Z][A-Z0-9_]*-\d+\b", section):
        add(item.group(0))
else:
    for item in re.finditer(r"(?<![\w-])#([1-9][0-9]*)\b", section):
        add(item.group(1))

if not issues:
    print(f"CHANGELOG_NO_ISSUES_FOUND version=v{version}", file=sys.stderr)
    sys.exit(1)

print("\n".join(issues))
PY
    )"; then
      return 1
    fi

    while IFS= read -r issue; do
      [ -z "$issue" ] && continue
      if ! is_valid_issue_token "$issue"; then
        echo "Invalid issue token '$issue' extracted from CHANGELOG." >&2
        return 1
      fi
      ISSUE_NUMBERS+=("$issue")
    done <<< "$extracted"
    return 0
  fi

  # --- linear: complement-only CHANGELOG + merged-PR scope (#1982) ---
  version_disp="$version"
  # Bare SemVer gets a conventional v for diagnostics; component-prefixed
  # tokens (mobile-v1.1.0) keep their spelling (do not become vmobile-…).
  case "$version_disp" in
    [0-9]*.[0-9]*.[0-9]*) version_disp="v${version_disp}" ;;
  esac

  if [ -z "$RELEASE_HEAD" ] && [ ! -f "$changelog_path" ]; then
    echo "CHANGELOG_SECTION_UNAVAILABLE version=${version_disp} (Linear scope derived from merged PRs only)" >&2
    if ! filter_linear_changelog_scope_by_merged_prs "$version" "$changelog_root"; then
      return 1
    fi
    return 0
  fi

  if ! extracted="$(python3 - "$version" "$changelog_path" "$TRACKER_PROVIDER" "$RELEASE_HEAD" "$changelog_root" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

raw_version = sys.argv[1]
path = Path(sys.argv[2])
provider = sys.argv[3]
head = sys.argv[4]

# SemVer 2.0.0 with optional prefix (bare / v / mobile-v / …).
_VERSION_RE = re.compile(
    r"^(?P<prefix>.*?)(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)
match_version = _VERSION_RE.fullmatch(raw_version or "")
if not match_version:
    print(f"CHANGELOG_VERSION_MALFORMED version={raw_version}", file=sys.stderr)
    sys.exit(1)
prefix = match_version.group("prefix")
# Same absorption guard as workflow-merge-budget.release_version_accepted.
if prefix not in ("", "v") and prefix[-1].isdigit():
    print(f"CHANGELOG_VERSION_MALFORMED version={raw_version}", file=sys.stderr)
    sys.exit(1)
core = "%s.%s.%s" % (
    match_version.group("major"),
    match_version.group("minor"),
    match_version.group("patch"),
)
if match_version.group("pre"):
    core += "-" + match_version.group("pre")
if match_version.group("build"):
    core += "+" + match_version.group("build")
if prefix in ("", "v"):
    # Bare / v-prefixed: section may be ## [1.2.3] or ## [v1.2.3].
    version = core
    version_disp = "v" + core
    heading = re.compile(rf"^## \[(?:v?{re.escape(version)})\].*$", re.MULTILINE)
else:
    # Component-prefixed: CHANGELOG must use the exact token (## [mobile-v1.1.0]).
    # A bare ## [1.1.0] section cannot represent this component release.
    version = raw_version
    version_disp = raw_version
    heading = re.compile(rf"^## \[{re.escape(version)}\].*$", re.MULTILINE)


def linear_changelog_unavailable():
    print(
        f"CHANGELOG_SECTION_UNAVAILABLE version={version_disp} "
        "(Linear scope derived from merged PRs only)",
        file=sys.stderr,
    )
    # Empty stdout → no changelog-derived IDs; caller still runs merged-PR filter.
    sys.exit(0)


if head:
    if not re.fullmatch(r"[0-9a-f]{40}", head):
        print("CHANGELOG_REVIEWED_HEAD_INVALID", file=sys.stderr)
        sys.exit(1)
    result = subprocess.run(["git", "-C", sys.argv[5], "show", head + ":CHANGELOG.md"], text=True, capture_output=True)
    if result.returncode:
        linear_changelog_unavailable()
    text = result.stdout
else:
    if not path.is_file():
        linear_changelog_unavailable()
    text = path.read_text(encoding="utf-8")

match = heading.search(text)
if not match:
    linear_changelog_unavailable()

next_heading = re.search(r"^## \[", text[match.end():], re.MULTILINE)
section_end = match.end() + next_heading.start() if next_heading else len(text)
section = text[match.end():section_end]

seen = set()
issues = []

def add(value: str) -> None:
    if value not in seen:
        seen.add(value)
        issues.append(value)

# En-dash, ASCII hyphen, or ".." range forms (e.g. LEA-298–LEA-301, LEA-298..LEA-301).
range_re = re.compile(
    r"\b([A-Z][A-Z0-9_]*-)(\d+)\s*(?:[\u2013-]|\.\.)\s*(?:[A-Z][A-Z0-9_]*-)?(\d+)\b"
)
for item in range_re.finditer(section):
    issue_prefix = item.group(1)
    start = int(item.group(2))
    end = int(item.group(3))
    if end < start:
        start, end = end, start
    for number in range(start, end + 1):
        add(f"{issue_prefix}{number}")

for item in re.finditer(r"\b[A-Z][A-Z0-9_]*-\d+\b", section):
    add(item.group(0))

# Linear may still derive scope from merged PRs when the section cites none.
print("\n".join(issues))
PY
  )"; then
    return 1
  fi

  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    if ! is_valid_issue_token "$issue"; then
      echo "Invalid issue token '$issue' extracted from CHANGELOG." >&2
      return 1
    fi
    ISSUE_NUMBERS+=("$issue")
  done <<< "$extracted"

  # Linear: changelog text is not authoritative for Released transitions (#1982).
  if ! filter_linear_changelog_scope_by_merged_prs "$version" "$changelog_root"; then
    return 1
  fi
}

# filter_linear_changelog_scope_by_merged_prs <version> <git_root>
#
# Replaces changelog-derived ISSUE_NUMBERS with Linear IDs from merged PRs in
# the release git range (previous semver tag → verified release tag or
# RELEASE_HEAD). Never uses checkout HEAD as the release tip.
#
# For every commit in the range, resolve associated merged PR(s) only through
# GitHub `commits/<sha>/pulls` (cached per SHA). Subject "(#N)" is never
# sufficient evidence. Well-formed [] → RELEASE_SCOPE_COMMIT_WITHOUT_PR (once
# per SHA) and continue; empty body / non-array / [null] / [{}] / element
# missing integer number or merged_at|merged|mergedAt → unresolved SHA
# (RELEASE_SCOPE_INCOMPLETE). Accept a PR only when it is merged and its merge
# commit or head commit is in the release range (or the associating range SHA
# when those fields are absent). Linear IDs come from PR headRefName / head.ref
# and title only. Documentation-stage and release/backport branches are
# RELEASE_SCOPE_SKIPPED; other prefixes (including chore/) are shipping
# evidence. Changelog-only IDs are RELEASE_SCOPE_SKIPPED. Explicit
# --issue/--issues are unioned afterward. Helper stdout ends with `OK` on
# complete resolution (including zero-ID scope); missing OK / empty stdout is
# filter failure. RELEASE_SCOPE_INCOMPLETE on unavailable release ref or API
# failure.
filter_linear_changelog_scope_by_merged_prs() {
  local version="$1"
  local git_root="$2"
  local changelog_csv=""
  local filter_out=""
  local line issue reason proposed unresolved
  local no_pr_sha no_pr_short
  local -a kept=()
  local -a changelog_only=()
  local filter_status=0
  local candidate is_explicit

  # Changelog-derived IDs only — explicit CLI overrides are never SKIP-filtered.
  for candidate in ${ISSUE_NUMBERS[@]+"${ISSUE_NUMBERS[@]}"}; do
    is_explicit=false
    for issue in ${EXPLICIT_ISSUE_NUMBERS[@]+"${EXPLICIT_ISSUE_NUMBERS[@]}"}; do
      if [ "$issue" = "$candidate" ]; then
        is_explicit=true
        break
      fi
    done
    if [ "$is_explicit" = false ]; then
      changelog_only+=("$candidate")
    fi
  done
  if [ "${#changelog_only[@]}" -gt 0 ]; then
    changelog_csv="$(IFS=,; printf '%s' "${changelog_only[*]}")"
  fi

  filter_out="$(
    RELEASE_HEAD_FOR_FILTER="${RELEASE_HEAD:-}" \
    python3 - "$version" "$git_root" "$changelog_csv" <<'PY'
import json
import os
import re
import subprocess
import sys

version = sys.argv[1]
git_root = sys.argv[2]
changelog_csv = sys.argv[3]
head = os.environ.get("RELEASE_HEAD_FOR_FILTER", "").strip()

LINEAR_RE = re.compile(r"\b([A-Z][A-Z0-9_]*-\d+)\b")
# Full object id from git log --format=%H / ls-remote (never shorten).
_FULL_SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def run_git(*args):
    return subprocess.run(
        ["git", "-C", git_root, *args],
        text=True,
        capture_output=True,
    )


# SemVer 2.0.0 core + optional prerelease + optional build (build ignored for
# precedence). Captures an optional non-digit prefix (v, mobile-v, …).
_SEMVER_TAG_RE = re.compile(
    r"^(?P<prefix>.*?)(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<pre>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+(?P<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

# Tags that looked SemVer-shaped but failed prerelease/build validation — emit
# one SEMVER_TAG_IGNORED diagnostic per name during boundary discovery.
_SEMVER_IGNORED_TAGS = set()


def _valid_prerelease_idents(prerelease):
    """SemVer 2.0.0: non-empty [0-9A-Za-z-]+ idents; numeric idents no leading zeros."""
    if not prerelease:
        return False
    for ident in prerelease.split("."):
        if not ident or not re.fullmatch(r"[0-9A-Za-z-]+", ident):
            return False
        if re.fullmatch(r"\d+", ident) and not re.fullmatch(r"0|[1-9]\d*", ident):
            return False
    return True


def _valid_build_idents(build):
    """Build metadata: non-empty [0-9A-Za-z-]+ identifiers (leading zeros allowed)."""
    if not build:
        return False
    for ident in build.split("."):
        if not ident or not re.fullmatch(r"[0-9A-Za-z-]+", ident):
            return False
    return True


def split_tag_prefix_and_semver(tag_name, report_invalid=False):
    """Return (prefix, precedence_key) or (None, None) for a tag/version name."""
    if not tag_name:
        return None, None
    match = _SEMVER_TAG_RE.match(tag_name)
    if not match:
        return None, None
    pre = match.group("pre")
    build = match.group("build")
    if pre is not None and not _valid_prerelease_idents(pre):
        if report_invalid and tag_name not in _SEMVER_IGNORED_TAGS:
            _SEMVER_IGNORED_TAGS.add(tag_name)
            print(
                "SEMVER_TAG_IGNORED tag=%s reason=invalid_prerelease_identifier"
                % tag_name,
                file=sys.stderr,
            )
        return None, None
    if build is not None and not _valid_build_idents(build):
        if report_invalid and tag_name not in _SEMVER_IGNORED_TAGS:
            _SEMVER_IGNORED_TAGS.add(tag_name)
            print(
                "SEMVER_TAG_IGNORED tag=%s reason=invalid_build_identifier" % tag_name,
                file=sys.stderr,
            )
        return None, None
    prefix = match.group("prefix")
    major = int(match.group("major"))
    minor = int(match.group("minor"))
    patch = int(match.group("patch"))
    return prefix, semver_precedence_key(major, minor, patch, pre)


def semver_precedence_key(major, minor, patch, prerelease):
    """Sort key: lower means lower SemVer precedence (build metadata ignored)."""
    if prerelease is None:
        # Normal version > any prerelease with the same MAJOR.MINOR.PATCH.
        return (major, minor, patch, 1, ())
    idents = []
    for ident in prerelease.split("."):
        if re.fullmatch(r"0|[1-9]\d*", ident):
            # Numeric identifiers rank below non-numeric (SemVer 11.4.3).
            idents.append((0, int(ident)))
        else:
            idents.append((1, ident))
    return (major, minor, patch, 0, tuple(idents))


def resolve_current_ref():
    """Verified release tip only: --release-head SHA or refs/tags/<version>.

    Never falls back to checkout HEAD or unqualified names (vX.Y.Z / X.Y.Z)
    that could resolve a same-named branch when the tag is absent.

    Tag candidates come only from release_namespace_spellings: bare/v aliases
    for plain SemVer; component-prefixed names match exactly (never strip a
    leading v from a component prefix such as vclient-v1.2.0 → client-v1.2.0).
    """
    if head and re.fullmatch(r"[0-9a-f]{40}", head):
        probe = run_git("rev-parse", "--verify", "--quiet", head + "^{commit}")
        if probe.returncode == 0:
            return head
        return None
    for spelling in release_namespace_spellings(version):
        candidate = "refs/tags/" + spelling
        probe = run_git("rev-parse", "--verify", "--quiet", candidate + "^{commit}")
        if probe.returncode == 0:
            return candidate
    return None


def release_namespace_spellings(version_arg):
    """Ordered spellings: as-given, then v/bare counterpart (empty/v prefix only).

    Component-prefixed versions (mobile-v1.1.0) have no v/bare counterpart.
    """
    if not version_arg:
        return []
    spellings = [version_arg]
    prefix, key = split_tag_prefix_and_semver(version_arg)
    if key is None:
        return spellings
    if prefix == "v":
        alt = version_arg[1:]
        if alt and alt not in spellings:
            spellings.append(alt)
    elif prefix == "":
        alt = "v" + version_arg
        if alt not in spellings:
            spellings.append(alt)
    return spellings


def _local_tag_sha(name):
    probe = run_git("rev-parse", "--verify", "--quiet", "refs/tags/%s^{commit}" % name)
    if probe.returncode == 0 and probe.stdout.strip():
        return probe.stdout.strip()
    return None


def resolve_release_tag_identity(version_arg, current_ref, remote_tags):
    """Canonical SemVer tag namespace for the release boundary.

    Identical with and without --release-head: current_ref does not affect
    spelling. Collect every local and remote SHA for bare/v spellings of the
    requested version (component prefixes have a single spelling).

    - exactly one existing spelling → that spelling
    - both spellings and all evidence agrees on one SHA → spelling as given
      (version_arg), so cleanup and --release-head stay aligned
    - any local↔remote disagreement for one name, or cross-spelling SHA
      mismatch → ambiguous
    - none exist → version_arg (never invent a v- prefix)
    """
    _ = current_ref  # tip SHA vs refs/tags affects the range tip only
    spellings = release_namespace_spellings(version_arg)
    if not spellings:
        return "ok", version_arg

    # name -> set of peeled SHAs seen locally and/or remotely
    evidence = {}
    for name in spellings:
        shas = set()
        local_sha = _local_tag_sha(name)
        if local_sha:
            shas.add(local_sha)
        remote_sha = remote_tags.get(name)
        if remote_sha:
            shas.add(remote_sha)
        if shas:
            evidence[name] = shas

    if not evidence:
        return "ok", version_arg

    agreed = set()
    for shas in evidence.values():
        if len(shas) != 1:
            # Same spelling disagrees between local and remote.
            return "ambiguous", None
        agreed |= shas
    if len(agreed) != 1:
        # Distinct spellings point at different commits.
        return "ambiguous", None

    existing = list(evidence.keys())
    if len(existing) == 1:
        return "ok", existing[0]

    # Both spellings exist at the same SHA: use the caller spelling as given.
    if version_arg in evidence:
        return "ok", version_arg
    return "ok", spellings[0]


def _boundary_unavailable_fetch_instruction(detail):
    print(detail, file=sys.stderr)
    print(
        "Fetch preceding release tags into this checkout "
        "(git fetch --tags origin) and rerun.",
        file=sys.stderr,
    )


def resolve_previous_boundary(current_version, current_ref):
    """Return (status, previous_ref_or_None).

    status:
      ok — preceding same-prefix SemVer tag from the remote; peeled commit
        available locally and any local tag of that name matches remote
      first_release — remote listing succeeded; no same-prefix tag is lower
      ambiguous — bare and v-prefixed tags for this version disagree on SHA
      ambiguous_previous — equal-precedence predecessors (e.g. build metadata)
        disagree on peeled SHA
      unavailable — remote listing failed, preceding commit unavailable or local
        tag disagrees, shallow clone, or version unparseable (fail closed; never
        git fetch — read-only inspection must not write refs/FETCH_HEAD)
    """
    shallow = run_git("rev-parse", "--is-shallow-repository")
    if shallow.returncode == 0 and shallow.stdout.strip() == "true":
        _boundary_unavailable_fetch_instruction(
            "PREVIOUS_RELEASE_BOUNDARY: shallow clone cannot verify the "
            "preceding release tag commit."
        )
        return "unavailable", None

    remotes = run_git("remote")
    if remotes.returncode != 0:
        return "unavailable", None
    remote_names = [line.strip() for line in remotes.stdout.splitlines() if line.strip()]
    if not remote_names:
        return "unavailable", None
    remote = "origin" if "origin" in remote_names else remote_names[0]

    listing = run_git("ls-remote", "--tags", remote)
    if listing.returncode != 0:
        return "unavailable", None

    # name -> peeled commit SHA from remote (^{} preferred).
    # Fail closed on any non-empty ls-remote line that is not sha\\trefs/tags/...
    # with a 40-hex SHA — do not silently skip malformed rows.
    remote_tags = {}
    for line in listing.stdout.splitlines():
        raw = line.rstrip("\n\r")
        if not raw.strip():
            continue
        if "\t" not in raw:
            return "unavailable", None
        sha, ref = raw.split("\t", 1)
        sha = sha.strip().lower()
        if not _FULL_SHA_RE.fullmatch(sha):
            return "unavailable", None
        if not ref.startswith("refs/tags/"):
            continue
        peeled = ref.endswith("^{}")
        name = ref[len("refs/tags/") :]
        if peeled:
            name = name[:-3]
        prior = remote_tags.get(name)
        if prior is None or peeled:
            remote_tags[name] = sha

    # Identity uses the actual tag namespace of the repository, identically with
    # and without --release-head. Never adopt a co-pointing component tag
    # (mobile-v...).
    id_status, release_tag = resolve_release_tag_identity(
        current_version, current_ref, remote_tags
    )
    if id_status == "ambiguous":
        print(
            "ambiguous_release_tag_namespace version=%s "
            "(bare/v spellings or local/remote tag SHAs disagree)"
            % current_version,
            file=sys.stderr,
        )
        return "ambiguous", None

    release_prefix, current_key = split_tag_prefix_and_semver(release_tag)
    if current_key is None:
        return "unavailable", None

    # name -> (precedence_key, commit_sha, name) for preceding same-prefix tags.
    candidates = {}
    for name, sha in remote_tags.items():
        prefix, key = split_tag_prefix_and_semver(name, report_invalid=True)
        if key is None or prefix != release_prefix:
            continue
        if key >= current_key:
            continue
        candidates[name] = (key, sha, name)

    if not candidates:
        return "first_release", None

    best_key = max(item[0] for item in candidates.values())
    top = [item for item in candidates.values() if item[0] == best_key]
    top_shas = {item[1] for item in top}
    if len(top_shas) > 1:
        print(
            "ambiguous_previous_release_boundary version=%s "
            "(equal-precedence predecessors disagree on peeled SHA)"
            % current_version,
            file=sys.stderr,
        )
        return "ambiguous_previous", None
    # Co-pointing equal-precedence tags (e.g. v1.2.0+aaa / v1.2.0+bbb): any name.
    _key, commit_sha, tag_name = sorted(top, key=lambda item: item[2])[0]

    # Never fetch: require the remote peeled commit already in the object store.
    cat = run_git("cat-file", "-e", commit_sha + "^{commit}")
    if cat.returncode != 0:
        _boundary_unavailable_fetch_instruction(
            "PREVIOUS_RELEASE_BOUNDARY: commit %s for preceding tag %s is not "
            "available locally." % (commit_sha, tag_name)
        )
        return "unavailable", None

    remote_full = run_git("rev-parse", "--verify", "--quiet", commit_sha + "^{commit}")
    if remote_full.returncode != 0 or not remote_full.stdout.strip():
        _boundary_unavailable_fetch_instruction(
            "PREVIOUS_RELEASE_BOUNDARY: could not resolve remote peeled commit "
            "%s for preceding tag %s." % (commit_sha, tag_name)
        )
        return "unavailable", None
    remote_sha = remote_full.stdout.strip()

    local_tag = run_git(
        "rev-parse", "--verify", "--quiet", "refs/tags/%s^{commit}" % tag_name
    )
    if local_tag.returncode == 0:
        local_sha = local_tag.stdout.strip()
        if local_sha != remote_sha:
            _boundary_unavailable_fetch_instruction(
                "PREVIOUS_RELEASE_BOUNDARY: local tag %s (%s) disagrees with "
                "remote peeled commit %s." % (tag_name, local_sha, remote_sha)
            )
            return "unavailable", None
        return "ok", "refs/tags/%s" % tag_name

    return "ok", remote_sha


# Documentation-stage branches are not Released shipping evidence (#1982 / #2014).
DOCUMENTATION_STAGE_PREFIXES = ("spec/", "implementation-plan/")


def is_documentation_stage_branch(head_ref):
    ref = (head_ref or "").strip()
    return any(ref.startswith(prefix) for prefix in DOCUMENTATION_STAGE_PREFIXES)


def is_release_or_backport_branch(head_ref):
    """Release/backport branches re-carry already-shipped work — not new evidence."""
    ref = (head_ref or "").strip()
    if not ref:
        return False
    if ref.startswith("release/") or ref.startswith("backport/"):
        return True
    if "/release/" in ref or "/backport/" in ref:
        return True
    return False


def extract_linear_ids(text):
    found = []
    seen = set()
    for match in LINEAR_RE.finditer(text or ""):
        token = match.group(1)
        if token not in seen:
            seen.add(token)
            found.append(token)
    return found


def resolve_repo_slug():
    # GH_REPO overrides cwd-based selection and can point at a hub repo during
    # component cleanup; drop it so lookups follow the product checkout (#1982).
    env = os.environ.copy()
    env.pop("GH_REPO", None)
    view = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"],
        cwd=git_root,
        text=True,
        capture_output=True,
        env=env,
    )
    if view.returncode == 0 and view.stdout.strip():
        return view.stdout.strip()
    remote = run_git("remote", "get-url", "origin")
    if remote.returncode != 0 or not remote.stdout.strip():
        return None
    url = remote.stdout.strip()
    match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    if match:
        return match.group(1)
    return None


def normalize_pr_payload(payload):
    """Normalize GraphQL (gh pr view) and REST (commits/<sha>/pulls) shapes.

    REST responses expose head.ref / base.ref / merged_at / merge_commit_sha;
    GraphQL uses headRefName / baseRefName / mergedAt. Branch-only Linear IDs
    (hotfix head.ref) must not be dropped when title omits the ID.

    Caller must already validate that payload is a dict with an integer
    ``number`` and a present merged_at / merged / mergedAt field.
    """
    if not isinstance(payload, dict):
        return None
    head_obj = payload.get("head") if isinstance(payload.get("head"), dict) else {}
    head_ref = payload.get("headRefName") or head_obj.get("ref") or ""
    head_sha = payload.get("headRefOid") or head_obj.get("sha") or ""
    base_obj = payload.get("base") if isinstance(payload.get("base"), dict) else {}
    base_ref = payload.get("baseRefName") or base_obj.get("ref") or ""
    merged_at = payload.get("mergedAt") or payload.get("merged_at") or ""
    if not merged_at and payload.get("merged") is True:
        # Boolean merged:true is sufficient "merged" evidence when timestamp absent.
        merged_at = "true"
    merge_commit = (
        payload.get("mergeCommitOid")
        or payload.get("merge_commit_sha")
        or ""
    )
    merge_obj = payload.get("mergeCommit")
    if not merge_commit and isinstance(merge_obj, dict):
        merge_commit = merge_obj.get("oid") or ""
    number = payload.get("number")
    if type(number) is not int:
        return None
    return {
        "number": number,
        "headRefName": head_ref,
        "headSha": head_sha,
        "title": payload.get("title") or "",
        "mergedAt": merged_at,
        "baseRefName": base_ref,
        "mergeCommitSha": merge_commit,
    }


def _pr_element_has_merged_field(item):
    """True when a merged_at / mergedAt / merged key is present (value may be null/false)."""
    return ("merged_at" in item) or ("mergedAt" in item) or ("merged" in item)


def pulls_for_commit(sha, repo_slug, commit_cache):
    """Return normalized PR list, [] for well-formed empty, or None if unresolved.

    Fetches every page via ``gh api --paginate --slurp`` (``per_page=100``).
    Any page error, empty body, non-array JSON, or non-list page is unresolved
    (None → RELEASE_SCOPE_INCOMPLETE). After pages are combined, [] is a valid
    GitHub answer (commit has no associated PR). [null], [{}], or any element
    missing an integer ``number`` or a merged_at/merged/mergedAt field is
    unresolved (None).
    """
    if sha in commit_cache:
        return commit_cache[sha]
    # --paginate --slurp yields a JSON array of page arrays; flatten before
    # the same malformed-evidence validation used for a single page.
    api = subprocess.run(
        [
            "gh",
            "api",
            "--paginate",
            "--slurp",
            "repos/%s/commits/%s/pulls?per_page=100" % (repo_slug, sha),
        ],
        cwd=git_root,
        text=True,
        capture_output=True,
    )
    if api.returncode != 0:
        commit_cache[sha] = None
        return None
    stripped = api.stdout.strip()
    if not stripped:
        # Empty HTTP body is malformed evidence (distinct from well-formed []).
        commit_cache[sha] = None
        return None
    try:
        pages = json.loads(stripped)
    except Exception:
        commit_cache[sha] = None
        return None
    if not isinstance(pages, list):
        commit_cache[sha] = None
        return None
    payload = []
    for page in pages:
        if not isinstance(page, list):
            commit_cache[sha] = None
            return None
        payload.extend(page)
    # Well-formed empty array (no pages or only empty pages): no associated PR.
    if len(payload) == 0:
        commit_cache[sha] = []
        return []
    normalized = []
    for item in payload:
        if not isinstance(item, dict):
            commit_cache[sha] = None
            return None
        number = item.get("number")
        if type(number) is not int:
            commit_cache[sha] = None
            return None
        if not _pr_element_has_merged_field(item):
            commit_cache[sha] = None
            return None
        norm = normalize_pr_payload(item)
        if norm is None:
            commit_cache[sha] = None
            return None
        normalized.append(norm)
    commit_cache[sha] = normalized
    return normalized


def pr_belongs_to_range(payload, range_shas, associating_sha):
    """Accept only when merge/head is in range, else associating commits/<sha>/pulls.

    Subject text never supplies membership. When GitHub returns merge_commit_sha
    or head SHA, at least one must appear in the release range. When those
    fields are absent, the associating range SHA from commits/<sha>/pulls is
    sufficient evidence that this PR belongs to the range.
    """
    merge_sha = (payload.get("mergeCommitSha") or "").strip().lower()
    head_sha = (payload.get("headSha") or "").strip().lower()
    assoc = (associating_sha or "").strip().lower()
    if merge_sha or head_sha:
        return bool(
            (merge_sha and merge_sha in range_shas)
            or (head_sha and head_sha in range_shas)
        )
    return bool(assoc and assoc in range_shas)


def collect_merged_pr_linear_ids(range_spec, repo_slug):
    """Return (shipped_ids, documentation_only_ids, release_backport_only_ids, unresolved).

    PR membership comes only from commits/<sha>/pulls for SHAs in the range —
    never from a PR number parsed out of a commit subject. Documentation-stage
    and release/backport head branches are excluded with explicit skip reasons;
    all other merged PR prefixes (feature/fix/refactor/hotfix/chore/ci/…) count
    as shipping evidence (#2014).
    """
    shipped_ids = set()
    documentation_ids = set()
    release_backport_ids = set()
    unresolved = []
    commit_cache = {}
    seen_prs = set()

    # Subjects are unused. Do not use %H\\t%s: strip() on an empty subject
    # removes the trailing tab and the collector would silently skip that SHA.
    log = run_git("log", range_spec, "--format=%H")
    if log.returncode != 0:
        return shipped_ids, documentation_ids, release_backport_ids, ["<git-log-failed>"]

    range_entries = []
    range_shas = set()
    for line in log.stdout.splitlines():
        sha_l = line.strip().lower()
        if not sha_l:
            continue
        if not _FULL_SHA_RE.fullmatch(sha_l):
            return (
                shipped_ids,
                documentation_ids,
                release_backport_ids,
                [sha_l],
            )
        range_shas.add(sha_l)
        range_entries.append(sha_l)

    for sha in range_entries:
        pulls = pulls_for_commit(sha, repo_slug, commit_cache)
        if pulls is None:
            unresolved.append(sha)
            continue
        if len(pulls) == 0:
            # Well-formed []: commit has no associated PR (direct push / local
            # merge). Scope stays complete; emit once per SHA for operators.
            print("NO_PR\t%s" % sha)
            continue

        for payload in pulls:
            if not payload.get("mergedAt"):
                # merged field present but false/null → not a merged PR; skip.
                continue
            # Base branch is irrelevant: evidence is a merged PR whose
            # merge/head (or associating) commit is in the release range —
            # including PRs that targeted feature/* or develop-<slug> parents.
            if not pr_belongs_to_range(payload, range_shas, sha):
                continue
            pr_num = payload.get("number")
            if pr_num is not None:
                if pr_num in seen_prs:
                    continue
                seen_prs.add(pr_num)
            head_ref = payload.get("headRefName") or ""
            pr_ids = set(extract_linear_ids(head_ref))
            pr_ids.update(extract_linear_ids(payload.get("title") or ""))
            if not pr_ids:
                continue
            if is_documentation_stage_branch(head_ref):
                documentation_ids.update(pr_ids)
            elif is_release_or_backport_branch(head_ref):
                release_backport_ids.update(pr_ids)
            else:
                shipped_ids.update(pr_ids)
    documentation_only = documentation_ids - shipped_ids
    release_backport_only = release_backport_ids - shipped_ids - documentation_only
    return shipped_ids, documentation_only, release_backport_only, unresolved


changelog_ids = [part for part in changelog_csv.split(",") if part]
current_ref = resolve_current_ref()
# Namespace (local ∪ remote, including conflicts) must run before the missing-tip
# gate. Otherwise absent local release tags exit as release_ref_unavailable and
# never surface ambiguous_release_tag_namespace — diverging from --release-head.
boundary_status, prev_tag = resolve_previous_boundary(version, current_ref)
if boundary_status == "ambiguous":
    print("INCOMPLETE\tambiguous_release_tag_namespace")
    sys.exit(0)
if boundary_status == "ambiguous_previous":
    print("INCOMPLETE\tambiguous_previous_release_boundary")
    sys.exit(0)
if current_ref is None:
    print("INCOMPLETE\trelease_ref_unavailable")
    sys.exit(0)
if boundary_status == "unavailable":
    print("INCOMPLETE\tprevious_release_boundary_unavailable")
    sys.exit(0)
if boundary_status == "ok":
    range_spec = "%s..%s" % (prev_tag, current_ref)
else:
    # Verified first release: remote ls-remote --tags found no preceding
    # same-prefix SemVer tag.
    range_spec = current_ref

repo_slug = resolve_repo_slug()
if not repo_slug:
    print("INCOMPLETE\t<repo-slug-unavailable>")
    sys.exit(0)

(
    merged_ids,
    documentation_only_ids,
    release_backport_only_ids,
    unresolved,
) = collect_merged_pr_linear_ids(range_spec, repo_slug)
if unresolved:
    print("INCOMPLETE\t%s" % ",".join(unresolved))
    sys.exit(0)

for issue in changelog_ids:
    if issue in merged_ids:
        print("KEEP\t%s" % issue)
    elif issue in documentation_only_ids:
        print("SKIP\t%s\tdocumentation_stage_pr_only" % issue)
    elif issue in release_backport_only_ids:
        print("SKIP\t%s\trelease_or_backport_branch_pr" % issue)
    else:
        print("SKIP\t%s\tchangelog_mention_without_merged_pr" % issue)

for issue in sorted(merged_ids):
    if issue not in changelog_ids:
        print("KEEP\t%s" % issue)

for issue in sorted(documentation_only_ids):
    if issue not in changelog_ids:
        print("SKIP\t%s\tdocumentation_stage_pr_only" % issue)

for issue in sorted(release_backport_only_ids):
    if issue not in changelog_ids:
        print("SKIP\t%s\trelease_or_backport_branch_pr" % issue)

# Explicit success marker so zero-ID complete scope is not treated as helper failure.
print("OK")
PY
  )" || filter_status=$?

  if [ "$filter_status" -ne 0 ] || [ -z "$filter_out" ]; then
    for issue in ${changelog_only[@]+"${changelog_only[@]}"}; do
      record_release_scope_skip "$issue" "merged_pr_evidence_unavailable"
    done
    ISSUE_NUMBERS=()
    union_explicit_issue_numbers
    cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=filter_helper_failed"
    return 1
  fi

  ISSUE_NUMBERS=()
  unresolved=""
  local saw_ok=false
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      OK)
        saw_ok=true
        ;;
      INCOMPLETE$'\t'*)
        unresolved="${line#INCOMPLETE	}"
        ;;
      KEEP$'\t'*)
        proposed="${line#KEEP	}"
        if is_valid_issue_token "$proposed"; then
          kept+=("$proposed")
        else
          record_release_scope_skip "$proposed" "invalid_linear_token"
        fi
        ;;
      SKIP$'\t'*)
        issue="$(printf '%s\n' "$line" | cut -f2)"
        reason="$(printf '%s\n' "$line" | cut -f3)"
        [ -n "$reason" ] || reason="changelog_mention_without_merged_pr"
        record_release_scope_skip "$issue" "$reason"
        ;;
      NO_PR$'\t'*)
        # Well-formed commits/<sha>/pulls → [] (no associated PR).
        no_pr_sha="${line#NO_PR	}"
        no_pr_short="$(printf '%s' "$no_pr_sha" | cut -c1-7)"
        cleanup_log "RELEASE_SCOPE_COMMIT_WITHOUT_PR sha=${no_pr_short}"
        ;;
    esac
  done <<< "$filter_out"

  if [ -z "$unresolved" ] && [ "$saw_ok" != true ]; then
    for issue in ${changelog_only[@]+"${changelog_only[@]}"}; do
      record_release_scope_skip "$issue" "merged_pr_evidence_unavailable"
    done
    ISSUE_NUMBERS=()
    union_explicit_issue_numbers
    cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=filter_helper_failed"
    return 1
  fi

  if [ -n "$unresolved" ]; then
    case "$unresolved" in
      release_ref_unavailable)
        cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=release_ref_unavailable"
        ;;
      previous_release_boundary_unavailable)
        cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=previous_release_boundary_unavailable"
        cleanup_log "Fetch preceding release tags into this checkout (git fetch --tags origin) and rerun."
        ;;
      ambiguous_release_tag_namespace)
        cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_release_tag_namespace"
        ;;
      ambiguous_previous_release_boundary)
        cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=ambiguous_previous_release_boundary"
        ;;
      *)
        cleanup_log "RELEASE_SCOPE_INCOMPLETE unresolved_shas=${unresolved}"
        ;;
    esac
    if [ -n "$changelog_csv" ]; then
      local old_ifs="$IFS" part
      IFS=','
      # shellcheck disable=SC2086
      for part in $changelog_csv; do
        part="${part//[[:space:]]/}"
        [ -n "$part" ] && record_release_scope_skip "$part" "release_scope_incomplete"
      done
      IFS="$old_ifs"
    fi
    ISSUE_NUMBERS=()
    union_explicit_issue_numbers
    return 1
  fi

  ISSUE_NUMBERS=("${kept[@]+"${kept[@]}"}")
  union_explicit_issue_numbers
  if [ "${#ISSUE_NUMBERS[@]}" -gt 0 ]; then
    cleanup_log "Linear --from-changelog scope from merged PRs in release range: $(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  else
    cleanup_log "Linear --from-changelog: no merged-PR-backed Linear IDs in the release range."
  fi
  return 0
}

dedupe_issue_numbers() {
  local deduped
  if [ "${#ISSUE_NUMBERS[@]}" -eq 0 ]; then
    return 0
  fi

  if ! deduped="$(python3 - "${ISSUE_NUMBERS[@]}" <<'PY'
import sys

seen = set()
for issue in sys.argv[1:]:
    if issue and issue not in seen:
        seen.add(issue)
        print(issue)
PY
  )"; then
    echo "Could not deduplicate issue scope." >&2
    return 1
  fi

  ISSUE_NUMBERS=()
  while IFS= read -r issue; do
    [ -z "$issue" ] && continue
    ISSUE_NUMBERS+=("$issue")
  done <<< "$deduped"
}

# detect_omitted_merged_items <version>
#
# Queries GitHub Projects for closed issues with "Merged" project status that
# were closed in the release window (between the previous release tag and the
# current release tag). Compares the found issues against ISSUE_NUMBERS[] (the
# changelog-derived scope). Reports any omitted issues and auto-adds confirmed
# shipped items (those with a merged PR referencing them) to ISSUE_NUMBERS[].
# Parent epics (issues with no merged PR referencing them in the window) are
# reported but emit TRACKER_INCOMPLETE rather than being auto-added.
#
# Skips silently when:
#   - TRACKER_PROVIDER is not github_projects
#   - GITHUB_PROJECT_NUMBER is not configured
#   - the current or previous release tag cannot be resolved
#   - the GitHub Projects item-list API call fails
# pr_merge_is_in_release <merge_sha> <version>
# 0 when <merge_sha> is an ancestor of the release tag — i.e. the code actually
# shipped in it. "Has a merged PR" is not that test: a PR merged into an
# in-flight develop-<slug> integration branch is merged, closed, and inside the
# release window, yet none of its code is in the tag. Downstream this stamped
# 16 issues onto a release whose changelog named two (#1512).
#
# An unknown SHA, an unfetched tag, or any git failure returns non-zero, so the
# caller degrades to report-only rather than auto-adding on a guess.
pr_merge_is_in_release() {
  local merge_sha="$1" version="$2"
  [ -n "$merge_sha" ] && [ -n "$version" ] || return 1
  git rev-parse --verify --quiet "${merge_sha}^{commit}" >/dev/null 2>&1 || return 1
  git rev-parse --verify --quiet "refs/tags/${version}^{commit}" >/dev/null 2>&1 || return 1
  git merge-base --is-ancestor "$merge_sha" "refs/tags/${version}" 2>/dev/null
}

detect_omitted_merged_items() {
  local version="$1"
  local provider project_number owner repo_owner repo_name repo_slug
  local current_tag_date prev_tag_name prev_tag_date project_items merged_items
  local known_scope_arg issue_num issue_closed_at in_window referencing_pr
  local referencing_pr_merge_sha referencing_pr_base
  local entry iss detail total_omitted epic_nums _ns_rest
  local omitted_epics omitted_shipped
  omitted_epics=""
  omitted_shipped=""

  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$provider" != "github_projects" ]; then
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set; skipping omitted-merged-items detection." >&2
    return 0
  fi
  case "$project_number" in
    *[!0-9]*)
      echo "Warning: project number '${project_number}' is not numeric; skipping omitted-merged-items detection." >&2
      return 0
      ;;
  esac

  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    echo "Warning: could not resolve GitHub repository; skipping omitted-merged-items detection." >&2
    return 0
  fi
  repo_slug="${repo_owner}/${repo_name}"

  owner="$(workflow_resolve_github_project_owner 2>/dev/null)" || true
  if [ -z "$owner" ]; then
    owner="$repo_owner"
  fi

  # Resolve the current release tag date.
  current_tag_date="$(gh api "repos/${repo_slug}/releases/tags/${version}" \
      --jq '.published_at // .created_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty triggers git-tag fallback below
  if [ -z "$current_tag_date" ]; then
    # Fallback: resolve via git tag annotation.
    current_tag_date="$(git log -1 --format="%aI" "refs/tags/${version}" 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort fallback; empty causes early return
  fi
  if [ -z "$current_tag_date" ]; then
    echo "Warning: could not resolve release tag date for '${version}'; skipping omitted-merged-items detection." >&2
    return 0
  fi

  # Resolve the previous release tag name (latest semver tag before current one).
  # Capture the tag list, write to a temp file, then read it in Python (cannot
  # combine a pipe and a heredoc for the same process).
  local all_tags=""
  all_tags="$(gh api "repos/${repo_slug}/tags?per_page=100" --paginate \
      --jq '[.[] | select(.name | test("^v?[0-9]+\\.[0-9]+\\.[0-9]+"))] | .[].name' \
      2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty list causes all items to qualify (safe lower bound)
  prev_tag_name=""
  if [ -n "$all_tags" ]; then
    local tags_tmp=""
    if ! tags_tmp="$(mktemp "${TMPDIR:-/tmp}/release-tags.XXXXXX")"; then
      echo "Warning: could not create temp file for tag list; skipping previous-tag resolution." >&2
      tags_tmp=""
    fi
    if [ -n "$tags_tmp" ]; then
      printf '%s\n' "$all_tags" > "$tags_tmp"
      prev_tag_name="$(python3 - "$version" "$tags_tmp" <<'PY'
import sys
import re

current   = sys.argv[1].lstrip("v")
tags_file = sys.argv[2]

with open(tags_file, encoding="utf-8") as fh:
    lines = [l.strip() for l in fh.read().splitlines() if l.strip()]

def parse(v):
    v = v.lstrip("v")
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())

current_tuple = parse(current)
if current_tuple is None:
    sys.exit(1)

candidates = []
for tag in lines:
    t = parse(tag)
    if t and t < current_tuple:
        candidates.append((t, tag))

if not candidates:
    sys.exit(0)

best = sorted(candidates, reverse=True)[0][1]
print(best)
PY
      )" || true
      rm -f "$tags_tmp"
    fi
  fi

  if [ -z "$prev_tag_name" ]; then
    # No previous tag found: use epoch as the lower bound so all closed items qualify.
    prev_tag_date="1970-01-01T00:00:00Z"
  else
    # Resolve the date for the previous tag.
    prev_tag_date="$(gh api "repos/${repo_slug}/releases/tags/${prev_tag_name}" \
        --jq '.published_at // .created_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty triggers git-tag fallback below
    if [ -z "$prev_tag_date" ]; then
      prev_tag_date="$(git log -1 --format="%aI" "refs/tags/${prev_tag_name}" 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort fallback; empty causes epoch lower bound
    fi
    if [ -z "$prev_tag_date" ]; then
      echo "Warning: could not resolve date for previous tag '${prev_tag_name}'; using epoch as lower bound." >&2
      prev_tag_date="1970-01-01T00:00:00Z"
    fi
  fi

  # Fetch all project items via GraphQL pagination.
  # gh project item-list caps at a fixed --limit (max 2000) and silently
  # truncates larger projects.  The GraphQL API supports cursor-based
  # pagination and can retrieve every item regardless of project size.
  #
  # The accumulated JSON is shaped to match the {"items":[...]} format that
  # the Python parser below expects, so no changes are needed downstream.
  local gql_project_id
  gql_project_id="$(workflow_github_project_id "$owner" "$project_number" 2>/dev/null || true)"
  if [ -z "$gql_project_id" ]; then
    echo "Warning: could not resolve GitHub Projects ID for project #${project_number}; skipping omitted-merged-items detection." >&2
    return 0
  fi
  # shellcheck disable=SC2016 # GraphQL variables are not Bash variables.
  local _gql_items_query='query($projectId:ID!,$after:String){node(id:$projectId){...on ProjectV2{items(first:100,after:$after){nodes{type content{__typename ...on Issue{number}...on PullRequest{number}}status:fieldValueByName(name:"Status"){...on ProjectV2ItemFieldSingleSelectValue{name}}}pageInfo{hasNextPage endCursor}}}}}'
  local gql_cursor="" gql_has_next="true" gql_page=0 gql_max_pages=500
  local gql_resp_tmp gql_parse_out all_gql_nodes="[]"
  project_items=""
  while [ "$gql_has_next" = "true" ] && [ "$gql_page" -lt "$gql_max_pages" ]; do
    gql_page=$(( gql_page + 1 ))
    local gql_args=( api graphql -f "projectId=${gql_project_id}" -f "query=${_gql_items_query}" )
    if [ -n "$gql_cursor" ]; then
      gql_args+=( -f "after=${gql_cursor}" )
    fi
    if ! gql_resp_tmp="$(mktemp "${TMPDIR:-/tmp}/release-gql-items.XXXXXX")"; then
      echo "Warning: could not create temp file for GQL response; skipping omitted-merged-items detection." >&2
      return 0
    fi
    if ! gh "${gql_args[@]}" > "$gql_resp_tmp" 2>/dev/null; then
      rm -f "$gql_resp_tmp"
      echo "Warning: GraphQL project item fetch failed (page ${gql_page}); skipping omitted-merged-items detection." >&2
      return 0
    fi
    gql_parse_out="$(python3 - "$gql_resp_tmp" "$all_gql_nodes" <<PY
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

node      = ((data.get("data") or {}).get("node") or {})
items_obj = node.get("items") or {}
nodes     = items_obj.get("nodes") or []
pi        = items_obj.get("pageInfo") or {}

out = []
for n in nodes:
    sf = n.get("status") or {}
    sname = sf.get("name", "") if isinstance(sf, dict) else ""
    ct = n.get("content") or {}
    out.append({
        "type":    (n.get("type") or ""),
        "content": {"number": ct.get("number")},
        "status":  sname,
    })

try:
    acc = json.loads(sys.argv[2])
except Exception:
    acc = []
acc.extend(out)

has_next   = "true"  if pi.get("hasNextPage") else "false"
end_cursor = pi.get("endCursor") or ""

print(json.dumps(acc))
print(has_next)
print(end_cursor)
PY
    )" || true
    rm -f "$gql_resp_tmp"
    if [ -z "$gql_parse_out" ]; then
      echo "Warning: could not parse GraphQL project items (page ${gql_page}); skipping omitted-merged-items detection." >&2
      return 0
    fi
    all_gql_nodes="$(printf '%s\n' "$gql_parse_out" | sed -n '1p')"
    gql_has_next="$(printf '%s\n' "$gql_parse_out" | sed -n '2p')"
    gql_cursor="$(printf '%s\n' "$gql_parse_out" | sed -n '3p')"
  done
  project_items="{\"items\":${all_gql_nodes}}"

  # Build a newline-separated list of issue numbers that have "Merged" project
  # status, are GitHub Issues (not PRs or drafts), and are not already in the
  # changelog-derived scope.
  known_scope_arg=""
  if [ "${#ISSUE_NUMBERS[@]}" -gt 0 ]; then
    known_scope_arg="$(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  fi

  # Extract omitted issue numbers from project_items using a temp file to avoid
  # the pipe-plus-heredoc conflict (cannot use both | and <<'PY' for the same process).
  local items_tmp=""
  if ! items_tmp="$(mktemp "${TMPDIR:-/tmp}/release-project-items.XXXXXX")"; then
    echo "Warning: could not create temp file for project items; skipping omitted-merged-items detection." >&2
    return 0
  fi
  printf '%s' "$project_items" > "$items_tmp"
  if ! merged_items="$(python3 - "$known_scope_arg" "$MERGED_LABEL" "$items_tmp" <<'PY'
import json
import sys

known_scope   = set(sys.argv[1].split(",")) if sys.argv[1] else set()
merged_status = sys.argv[2]
items_file    = sys.argv[3]

try:
    with open(items_file, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as e:
    print("JSON_PARSE_ERROR: " + str(e), file=sys.stderr)
    sys.exit(2)

items = data.get("items") or []

omitted = []
for item in items:
    status = (item.get("status") or "").strip()
    if status != merged_status:
        continue
    content = item.get("content") or {}
    if not content:
        continue
    # Only GitHub Issues (not PRs): the CLI sets type="ISSUE" for issues
    item_type = (item.get("type") or "").strip().upper()
    if item_type and item_type not in ("ISSUE", ""):
        continue
    issue_number = str(content.get("number") or "").strip()
    if not issue_number:
        continue
    if issue_number in known_scope:
        continue
    omitted.append(issue_number)

print("\n".join(omitted))
PY
  )"; then
    rm -f "$items_tmp"
    echo "Warning: could not parse GitHub Projects items; skipping omitted-merged-items detection." >&2
    return 0
  fi
  rm -f "$items_tmp"

  if [ -z "$merged_items" ]; then
    echo "Omitted-merged-items check: no additional Merged items found outside changelog scope."
    return 0
  fi

  # For each candidate item, verify it was closed in the release window, then
  # classify as parent epic (no merged PR referencing it) or regular shipped item.
  # Use newline-delimited strings (bash 3.2 compatible; no associative arrays).
  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] && continue

    # Fetch the issue close date.
    issue_closed_at="$(gh api "repos/${repo_slug}/issues/${issue_num}" \
        --jq '.closed_at // empty' 2>/dev/null || true)"  # workflow-shell-guard: allow SH001 - best-effort; empty routes issue to manual-review bucket

    if [ -z "$issue_closed_at" ]; then
      # Can't determine close date; report for manual review.
      omitted_epics="${omitted_epics}${issue_num}:unknown_close_date
"
      continue
    fi

    # Check if issue was closed inside the release window.
    in_window="$(python3 - "$issue_closed_at" "$prev_tag_date" "$current_tag_date" <<'PY'
import sys
from datetime import datetime, timezone

def parse_dt(s):
    # Normalise the string: strip a trailing Z (UTC) so fromisoformat
    # accepts it on Python before 3.11 (which does not handle Z natively).
    s = s.rstrip("Z")
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        # No offset present - treat as UTC (e.g. after stripping the Z).
        # Return a naive UTC datetime so all comparisons stay in the same
        # coordinate; mixing aware and naive raises TypeError in Python 3.
        return dt
    # Offset present (positive OR negative): convert to UTC, then strip
    # tzinfo so the result is a naive UTC datetime, matching the branch above.
    return dt.astimezone(timezone.utc).replace(tzinfo=None)

try:
    closed = parse_dt(sys.argv[1])
    after  = parse_dt(sys.argv[2])
    before = parse_dt(sys.argv[3])
    print("yes" if after < closed <= before else "no")
except Exception:
    print("no")
PY
    )" || true

    if [ "$in_window" != "yes" ]; then
      continue
    fi

    # Check whether a merged PR in the repository references this issue.
    # gh pr list --search uses full-text matching and can return false
    # positives: searching for #12 can match PRs referencing #123, #1234, etc.
    # Instead, use the GraphQL timeline API which records exact cross-references
    # (CrossReferencedEvent) and PR-closed events (ClosedEvent), so only PRs
    # that truly reference this specific issue number are returned.
    # The query is inlined as a single-line variable to avoid <<'PY' heredoc
    # quoting issues in bash 3.2 when the query spans multiple lines.
    # shellcheck disable=SC2016 # GraphQL variables are not Bash variables.
    local _gql_tl_query='query($owner:String!,$repo:String!,$num:Int!,$after:String){repository(owner:$owner,name:$repo){issue(number:$num){timelineItems(first:100,after:$after,itemTypes:[CROSS_REFERENCED_EVENT,CLOSED_EVENT]){nodes{__typename ...on CrossReferencedEvent{source{__typename ...on PullRequest{number merged baseRefName mergeCommit{oid}}}}...on ClosedEvent{closer{__typename ...on PullRequest{number merged baseRefName mergeCommit{oid}}}}}pageInfo{hasNextPage endCursor}}}}}'
    local gql_pr_cursor="" gql_pr_has_next="true" gql_pr_page=0 gql_pr_max=20
    referencing_pr=""
    while [ "$gql_pr_has_next" = "true" ] && [ "$gql_pr_page" -lt "$gql_pr_max" ] && [ -z "$referencing_pr" ]; do
      gql_pr_page=$(( gql_pr_page + 1 ))
      local gql_pr_args=( api graphql
          -f "owner=${repo_owner}"
          -f "repo=${repo_name}"
          -F "num=${issue_num}"
          -f "query=${_gql_tl_query}" )
      if [ -n "$gql_pr_cursor" ]; then
        gql_pr_args+=( -f "after=${gql_pr_cursor}" )
      fi
      local gql_pr_tmp=""
      if ! gql_pr_tmp="$(mktemp "${TMPDIR:-/tmp}/release-gql-tl.XXXXXX")"; then
        break
      fi
      if ! gh "${gql_pr_args[@]}" > "$gql_pr_tmp" 2>/dev/null; then
        rm -f "$gql_pr_tmp"
        break
      fi
      local gql_pr_parse_out=""
      gql_pr_parse_out="$(python3 - "$gql_pr_tmp" <<PY
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}

issue    = ((data.get("data") or {}).get("repository") or {}).get("issue") or {}
tl       = issue.get("timelineItems") or {}
nodes    = tl.get("nodes") or []
pi       = tl.get("pageInfo") or {}
found_pr = None
found_merge_sha = ""
found_base = ""

def _take(pr):
    mc = pr.get("mergeCommit") or {}
    return pr.get("number"), (mc.get("oid") or ""), (pr.get("baseRefName") or "")

for n in nodes:
    t = n.get("__typename") or ""
    if t == "CrossReferencedEvent":
        src = n.get("source") or {}
        if src.get("__typename") == "PullRequest" and src.get("merged"):
            found_pr, found_merge_sha, found_base = _take(src)
            break
    elif t == "ClosedEvent":
        closer = n.get("closer") or {}
        if closer.get("__typename") == "PullRequest" and closer.get("merged"):
            found_pr, found_merge_sha, found_base = _take(closer)
            break

has_next   = "true"  if pi.get("hasNextPage") else "false"
end_cursor = pi.get("endCursor") or ""

print(str(found_pr) if found_pr is not None else "")
print(has_next)
print(end_cursor)
print(found_merge_sha)
print(found_base)
PY
      )" || true
      rm -f "$gql_pr_tmp"
      if [ -z "$gql_pr_parse_out" ]; then
        break
      fi
      referencing_pr="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '1p')"
      referencing_pr_merge_sha="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '4p')"
      referencing_pr_base="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '5p')"
      gql_pr_has_next="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '2p')"
      gql_pr_cursor="$(printf '%s\n' "$gql_pr_parse_out" | sed -n '3p')"
    done

    if [ -n "$referencing_pr" ] && pr_merge_is_in_release "$referencing_pr_merge_sha" "$version"; then
      omitted_shipped="${omitted_shipped}${issue_num}:pr_${referencing_pr}
"
    elif [ -n "$referencing_pr" ]; then
      # Merged, closed, inside the window — but the merge commit is not an
      # ancestor of the tag, so this code did not ship in this release.
      # Report it; never auto-add it (#1512).
      omitted_epics="${omitted_epics}${issue_num}:not_shipped_pr_${referencing_pr}_into_${referencing_pr_base:-unknown}
"
    else
      omitted_epics="${omitted_epics}${issue_num}:no_merged_pr
"
    fi
  done <<< "$merged_items"

  # Count omitted items (trim trailing newlines before counting).
  local count_shipped=0 count_epics=0
  if [ -n "$omitted_shipped" ]; then
    count_shipped="$(printf '%s' "$omitted_shipped" | grep -c . || true)"
  fi
  if [ -n "$omitted_epics" ]; then
    count_epics="$(printf '%s' "$omitted_epics" | grep -c . || true)"
  fi
  total_omitted=$(( count_shipped + count_epics ))

  if [ "$total_omitted" -eq 0 ]; then
    echo "Omitted-merged-items check: no additional Merged items found in release window outside changelog scope."
    return 0
  fi

  echo "OMITTED_MERGED_ITEMS_DETECTED count=${total_omitted}"
  if [ "$count_shipped" -gt 0 ]; then
    echo "  Regular shipped items (will be auto-added to release scope):"
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      iss="${entry%%:*}"
      detail="${entry#*:}"
      pr_num="${detail#pr_}"
      echo "    #${iss} (merged PR #${pr_num})"
      ISSUE_NUMBERS+=("$iss")
    done <<< "$omitted_shipped"
  fi
  if [ "$count_epics" -gt 0 ]; then
    echo "  Likely parent epics or items without a merged PR (not auto-added):"
    epic_nums=""
    while IFS= read -r entry; do
      [ -z "$entry" ] && continue
      iss="${entry%%:*}"
      detail="${entry#*:}"
      case "$detail" in
        no_merged_pr)       echo "    #${iss} (likely parent epic — no merged PR referencing this issue in release window)" ;;
        not_shipped_pr_*)
          _ns_rest="${detail#not_shipped_pr_}"
          echo "    #${iss} [merged PR #${_ns_rest%%_into_*} into ${_ns_rest#*_into_} is not an ancestor of ${version}: merged, but not shipped in this release - report-only]"
          ;;
        unknown_close_date) echo "    #${iss} (could not determine close date — manual review required)" ;;
        *)                  echo "    #${iss} (${detail})" ;;
      esac
      epic_nums="${epic_nums}${iss},"
    done <<< "$omitted_epics"
    epic_nums="${epic_nums%,}"
    echo "TRACKER_INCOMPLETE=1 REASON=omitted_parent_epics ISSUES=${epic_nums}"
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      if ! is_valid_issue_token "$2"; then
        echo "Invalid issue number for --issue: $2" >&2
        exit 2
      fi
      ISSUE_NUMBERS+=("$2")
      EXPLICIT_ISSUE_NUMBERS+=("$2")
      shift 2
      ;;
    --issues)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      parse_issue_csv "$2"
      shift 2
      ;;
    --backport-base)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      BACKPORT_BASE="$2"
      BACKPORT_BASE_OVERRIDE="$2"
      shift 2
      ;;
    --from-changelog)
      FROM_CHANGELOG=true
      shift
      ;;
    --best-effort)
      BEST_EFFORT=true
      shift
      ;;
    --repo)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      PRODUCT_REPO="$2"
      shift 2
      ;;
    --repo-root)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      REPO_ROOT_OVERRIDE="$2"
      shift 2
      ;;
    --evidence-file)
      if [ $# -lt 2 ]; then
        usage
        exit 2
      fi
      EVIDENCE_FILE="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --inspect-targets)
      INSPECT_TARGETS=true
      FROM_CHANGELOG=true
      COMPONENT_JSON_MODE=true
      shift
      ;;
    --release-head)
      [ $# -ge 2 ] || { usage; exit 2; }
      RELEASE_HEAD="$2"
      RELEASE_HEAD_SET=true
      shift 2
      ;;
    --target-root)
      if [ $# -lt 2 ] || [ -z "$2" ] || [ "${2#--}" != "$2" ]; then
        echo "--target-root requires a nonempty checkout path." >&2
        exit 2
      fi
      RELEASE_TARGET_ROOT="$2"
      shift 2
      ;;
    --merge-session)
      if [ $# -lt 2 ] || [ -z "$2" ] || [ "${2#--}" != "$2" ]; then
        echo "--merge-session requires a nonempty session path." >&2
        exit 2
      fi
      MERGE_SESSION="$2"
      COMPONENT_JSON_MODE=true
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      if [ -n "$RELEASE_INPUT" ]; then
        echo "Unexpected extra positional argument: $1" >&2
        usage
        exit 2
      fi
      RELEASE_INPUT="$1"
      shift
      ;;
  esac
done

if [ -n "$RELEASE_TARGET_ROOT" ]; then
  if [ "$INSPECT_TARGETS" != "true" ] || [ -n "$MERGE_SESSION" ]; then
    echo "--target-root is only supported for read-only --inspect-targets." >&2
    exit 2
  fi
  RELEASE_TARGET_ROOT="$(canonical_dir "$RELEASE_TARGET_ROOT")"
fi

HUB_REPO_ROOT="$PWD"
if [ -n "$REPO_ROOT_OVERRIDE" ]; then
  if [ ! -d "$REPO_ROOT_OVERRIDE" ]; then
    echo "--repo-root does not exist or is not a directory: $REPO_ROOT_OVERRIDE" >&2
    exit 2
  fi
  if [ "$(canonical_dir "$REPO_ROOT_OVERRIDE")" != "$(canonical_dir "$HUB_REPO_ROOT")" ]; then
    echo "--repo-root must point at the current workflow hub checkout for release tracker cleanup." >&2
    exit 2
  fi
  HUB_REPO_ROOT="$(canonical_dir "$REPO_ROOT_OVERRIDE")"
fi

if [ "$JSON_OUTPUT" = "true" ] && [ -n "$EVIDENCE_FILE" ]; then
  COMPONENT_JSON_MODE=true
fi

if [ "$RELEASE_HEAD_SET" = "true" ] && [[ ! "$RELEASE_HEAD" =~ ^[0-9a-f]{40}$ ]]; then
  echo "--release-head requires a full reviewed commit SHA." >&2
  exit 2
fi
if [ -n "$MERGE_SESSION" ] && [ -n "${WORKFLOW_MERGE_BUDGET_TOKEN:-}" ]; then
  child_check_args=(check --session "$MERGE_SESSION"
    --repo "${WORKFLOW_MERGE_BUDGET_REPO:-}" --pr "${WORKFLOW_MERGE_BUDGET_PR:-0}"
    --phase cleanup --executor-pid "$$")
  if [ "$RELEASE_HEAD_SET" = "true" ]; then
    child_check_args+=(--head "$RELEASE_HEAD")
  fi
  child_binding="$(python3 "$SCRIPT_DIR/workflow-merge-budget.py" ${child_check_args[@]+"${child_check_args[@]}"})"
  SESSION_CHILD="$(printf '%s' "$child_binding" | jq -r '.nestedExecutionAuthorized')"
fi
# Reject before component leases or CHANGELOG extraction can use caller scope.
if [ "$RELEASE_HEAD_SET" = "true" ] && [ "$INSPECT_TARGETS" != "true" ]; then
  if [ "$SESSION_CHILD" != "true" ] || ! printf '%s' "$child_binding" | jq -e --arg head "$RELEASE_HEAD" \
    '.releasePair != null and .releasePair.head == $head and .selectedPR == .releasePair.backportPr' >/dev/null; then
    echo "--release-head is only supported for read-only --inspect-targets or the authenticated owning release cleanup child." >&2
    exit 2
  fi
fi
validate_component_release_cleanup "$HUB_REPO_ROOT"
if [ -n "$RELEASE_TARGET_ROOT" ] && [ -n "$COMPONENT_TARGET_FILE" ] && \
  [ "$RELEASE_TARGET_ROOT" != "$(canonical_dir "$(json_field "$COMPONENT_TARGET_FILE" '.local_checkout.path')")" ]; then
  echo "--target-root differs from the resolved component checkout." >&2
  exit 2
fi

if [ -z "$RELEASE_INPUT" ]; then
  usage
  exit 2
fi

RELEASE_BRANCH="$(normalize_release_branch "$RELEASE_INPUT")"
RELEASE_VERSION="$(release_version_from_branch "$RELEASE_BRANCH")"
# Linear-only requested tag spelling (raw CLI). Does not alter RELEASE_BRANCH /
# RELEASE_VERSION, which stay byte-identical to origin/develop for GitHub.
RELEASE_REQUESTED_TAG_SPELLING="$(release_tag_request_from_input "$RELEASE_INPUT")"
validate_portable_branch_name "release" "$RELEASE_BRANCH"
validate_portable_branch_name "backport base" "$BACKPORT_BASE"
cleanup_log "Release branch: $RELEASE_BRANCH"
cleanup_log "Release version: $RELEASE_VERSION"
cleanup_log "Backport base: $BACKPORT_BASE"

if [ "$FROM_CHANGELOG" = "true" ]; then
  changelog_scope_version="$RELEASE_VERSION"
  linear_scope_ready=true
  if [ "$TRACKER_PROVIDER" = "linear" ]; then
    changelog_scope_version="$RELEASE_REQUESTED_TAG_SPELLING"
    # Component mode: tip/previous discovery uses validated evidence.component_tag
    # (e.g. product-v1.2.3), not the branch suffix (product/release/v1.2.3 → v1.2.3).
    # Tracker RELEASE_VERSION / RELEASE_BRANCH stay unchanged for stamps/projection.
    if [ -n "$COMPONENT_TARGET_FILE" ] || [ -n "$EVIDENCE_FILE" ]; then
      linear_component_release_tag=""
      if [ -n "$EVIDENCE_FILE" ] && [ -f "$EVIDENCE_FILE" ]; then
        linear_component_release_tag="$(json_field "$EVIDENCE_FILE" '.component_tag')"
      fi
      if ! validate_linear_component_release_tag "$linear_component_release_tag"; then
        cleanup_log "RELEASE_SCOPE_INCOMPLETE reason=component_tag_unavailable"
        linear_scope_ready=false
      else
        changelog_scope_version="$linear_component_release_tag"
      fi
    fi
  fi
  if [ "$linear_scope_ready" != "true" ] || \
    ! append_issues_from_changelog "$changelog_scope_version"; then
    cleanup_log "TRACKER_INCOMPLETE=1 REASON=changelog_scope_unavailable"
    if [ "$BEST_EFFORT" != "true" ] || [ "$INSPECT_TARGETS" = "true" ]; then
      exit 1
    fi
  fi
fi

dedupe_issue_numbers

if [ "$INSPECT_TARGETS" = "true" ]; then
  if [[ ! "$RELEASE_HEAD" =~ ^[0-9a-f]{40}$ ]]; then
    echo "--inspect-targets requires a full reviewed --release-head SHA." >&2
    exit 2
  fi
  inspection_root="$PWD"
  if [ -n "$RELEASE_TARGET_ROOT" ]; then
    inspection_root="$RELEASE_TARGET_ROOT"
  fi
  if [ -n "$COMPONENT_TARGET_FILE" ]; then
    inspection_root="$(json_field "$COMPONENT_TARGET_FILE" '.local_checkout.path')"
  fi
  if ! inspection_repo="$(cd "$inspection_root" && unset GH_REPO && gh repo view --json nameWithOwner --jq .nameWithOwner)"; then
    echo "Could not resolve release checkout identity." >&2
    exit 1
  fi
  inspection_issue_owner="$(workflow_resolve_github_repo_owner)"
  inspection_issue_name="$(workflow_resolve_github_repo_name)"
  inspection_args=(project-release --repo "$inspection_repo" --repo-root "$HUB_REPO_ROOT"
    --target-root "$inspection_root" --version "$RELEASE_VERSION" --branch "$RELEASE_BRANCH"
    --head "$RELEASE_HEAD" --base "$BACKPORT_BASE" --provider "$TRACKER_PROVIDER"
    --issue-repo "$inspection_issue_owner/$inspection_issue_name"
    --merged-status "$MERGED_LABEL" --released-status "$RELEASED_LABEL")
  if [ "$TRACKER_PROVIDER" = "github_projects" ]; then
    inspection_project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
    inspection_project_owner="$(workflow_resolve_github_project_owner)"
    if ! inspection_project_id="$(workflow_github_project_id "$inspection_project_owner" "$inspection_project_number")" || [ -z "$inspection_project_id" ]; then
      echo "Owning project unavailable for complete release projection." >&2
      exit 1
    fi
    inspection_args+=(--project-id "$inspection_project_id")
  elif [ "$TRACKER_PROVIDER" = "linear" ]; then
    inspection_args+=(--release-field "$(workflow_issue_tracker_custom_field release_field)"
      --release-label-prefix "$(workflow_issue_tracker_custom_field release_label_prefix || true)")
  fi
  for issue in ${ISSUE_NUMBERS[@]+"${ISSUE_NUMBERS[@]}"}; do
    inspection_args+=(--scope-issue "$issue")
  done
  if [ -n "$EVIDENCE_FILE" ]; then
    inspection_args+=(--evidence "$EVIDENCE_FILE")
  fi
  python3 "$SCRIPT_DIR/workflow-merge-budget.py" ${inspection_args[@]+"${inspection_args[@]}"}
  exit $?
fi

if [ -n "$MERGE_SESSION" ]; then
  session_args=(release-cleanup --session "$MERGE_SESSION" --version "$RELEASE_VERSION"
    --branch "$RELEASE_BRANCH" --base "$BACKPORT_BASE" --executor-pid "$$")
  for issue in ${ISSUE_NUMBERS[@]+"${ISSUE_NUMBERS[@]}"}; do
    session_args+=(--scope-issue "$issue")
  done
  if [ -n "$PRODUCT_REPO" ]; then
    session_args+=(--product-repo "$PRODUCT_REPO" --evidence "$EVIDENCE_FILE")
  fi
  python3 "$SCRIPT_DIR/workflow-merge-budget.py" ${session_args[@]+"${session_args[@]}"} -- \
    bash "$SCRIPT_DIR/prepare-release-post-merge-cleanup.sh" ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}
  exit $?
fi

if [ "$FROM_CHANGELOG" = "true" ]; then
  detect_omitted_merged_items "$RELEASE_VERSION"
  dedupe_issue_numbers
fi

cleanup_log "Verifying merged PRs for release branch..."
MAIN_PR=$(cleanup_gh_pr_list --state merged --head "$RELEASE_BRANCH" --base main --json number --jq '.[0].number // empty')
DEVELOP_PR=$(cleanup_gh_pr_list --state merged --head "$RELEASE_BRANCH" --base "$BACKPORT_BASE" --json number --jq '.[0].number // empty')
OPEN_MAIN_PR=$(cleanup_gh_pr_list --state open --head "$RELEASE_BRANCH" --base main --json number --jq '.[0].number // empty')
OPEN_DEVELOP_PR=$(cleanup_gh_pr_list --state open --head "$RELEASE_BRANCH" --base "$BACKPORT_BASE" --json number --jq '.[0].number // empty')

if [ -n "$OPEN_MAIN_PR" ] || [ -n "$OPEN_DEVELOP_PR" ]; then
  cleanup_log "Release PRs are still open (main: ${OPEN_MAIN_PR:-none}, ${BACKPORT_BASE}: ${OPEN_DEVELOP_PR:-none})."
  echo "Do not run post-merge cleanup until both PRs are merged." >&2
  exit 1
fi

if [ -z "$MAIN_PR" ] || [ -z "$DEVELOP_PR" ]; then
  echo "Both merged PRs are required before cleanup." >&2
  echo "Detected merged PRs - main: ${MAIN_PR:-none}, ${BACKPORT_BASE}: ${DEVELOP_PR:-none}" >&2
  exit 1
fi

cleanup_log "Merged PRs verified (main #$MAIN_PR, ${BACKPORT_BASE} #$DEVELOP_PR)."

cleanup_log "Fetching origin refs..."
cleanup_git fetch origin --prune

REMOTE_BRANCH_DELETED=false
LOCAL_BRANCH_DELETED=false
if cleanup_git ls-remote --exit-code --heads origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
  cleanup_log "Deleting remote branch '$RELEASE_BRANCH'..."
  cleanup_git push origin --delete "$RELEASE_BRANCH"
  REMOTE_BRANCH_DELETED=true
else
  cleanup_log "Remote branch '$RELEASE_BRANCH' is already absent; skipping remote delete."
fi

if cleanup_git show-ref --quiet "refs/heads/$RELEASE_BRANCH"; then
  CURRENT_BRANCH="$(cleanup_git branch --show-current)"
  if [ "$CURRENT_BRANCH" = "$RELEASE_BRANCH" ]; then
    cleanup_log "Local branch '$RELEASE_BRANCH' is currently checked out; switching to '$BACKPORT_BASE' first..."
    cleanup_git switch "$BACKPORT_BASE"
  fi

  cleanup_log "Deleting local branch '$RELEASE_BRANCH'..."
  # -D is intentional: squash/rebase merges often make -d fail despite merged PRs.
  # git branch -D prints "Deleted branch ... (was ...)." to its own stdout
  # (unlike fetch/push/switch, which use stderr for progress) -- route that
  # to stderr in component JSON mode so it cannot land ahead of/inside the
  # final JSON object, same as cleanup_log's own routing.
  if [ "$COMPONENT_JSON_MODE" = "true" ]; then
    branch_delete_status=0
    cleanup_git branch -D "$RELEASE_BRANCH" >&2 || branch_delete_status=$?
  else
    branch_delete_status=0
    cleanup_git branch -D "$RELEASE_BRANCH" || branch_delete_status=$?
  fi
  if [ "$branch_delete_status" -ne 0 ]; then
    echo "Could not delete local branch '$RELEASE_BRANCH' cleanly." >&2
    echo "If it is checked out elsewhere, switch away in that worktree and retry." >&2
    exit 1
  fi
  LOCAL_BRANCH_DELETED=true
else
  cleanup_log "Local branch '$RELEASE_BRANCH' is already absent; skipping local delete."
fi

if [ "${#ISSUE_NUMBERS[@]}" -eq 0 ]; then
  cleanup_log "TRACKER_INCOMPLETE=1 REASON=no_issue_scope"
  cleanup_log "No issues supplied; release tracker transitions are incomplete."
  cleanup_log "Rerun with --from-changelog or explicit --issue/--issues after confirming the shipped issue scope."
  if [ "$BEST_EFFORT" != "true" ]; then
    echo "Pass --best-effort to keep branch cleanup as the only completed action and exit 0." >&2
    exit 1
  fi
  if [ "$COMPONENT_JSON_MODE" = "true" ]; then
    emit_component_cleanup_json "incomplete" "false" "incomplete" \
      "provide --from-changelog or --issue/--issues before tracker reconciliation can complete"
  fi
  cleanup_log "Release post-merge cleanup complete."
  exit 0
fi

# Linear status transitions cannot be performed automatically by this script
# (they require MCP/API access). Emit per-issue manual action guidance and
# exit cleanly rather than silently skipping or failing with UPDATED=0.
if [ "$TRACKER_PROVIDER" = "linear" ]; then
  cleanup_log "Recording release stamp guidance for Linear issue(s)..."
  LINEAR_STAMPED=0
  LINEAR_STAMP_SKIPPED=0
  LINEAR_STAMP_FAILED=0
  for issue in "${ISSUE_NUMBERS[@]}"; do
    if ! STAMP_OUT="$(record_release_for_issue_best_effort "$issue" "$RELEASE_VERSION")"; then
      cleanup_log "Warning: release-stamp helper failed for issue #$issue; counting as stamp failure."
      STAMP_OUT="RELEASE_STAMP_FAILED issue=${issue} version=${RELEASE_VERSION} provider=${TRACKER_PROVIDER:-unknown} reason=helper_failed"
    fi
    cleanup_log "$STAMP_OUT"
    if echo "$STAMP_OUT" | grep -q "^RELEASE_STAMPED "; then
      LINEAR_STAMPED=$((LINEAR_STAMPED + 1))
    elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_FAILED "; then
      LINEAR_STAMP_FAILED=$((LINEAR_STAMP_FAILED + 1))
    elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_SKIPPED "; then
      LINEAR_STAMP_SKIPPED=$((LINEAR_STAMP_SKIPPED + 1))
    else
      cleanup_log "Warning: unrecognized release-stamp output for issue #$issue; counting as stamp failure."
      LINEAR_STAMP_FAILED=$((LINEAR_STAMP_FAILED + 1))
    fi
  done
  cleanup_log "Linear tracker detected: automatic '$MERGED_LABEL' -> '$RELEASED_LABEL' transitions are not supported by this script."
  cleanup_log "Manually transition the following issue(s) to '$RELEASED_LABEL' in Linear (via MCP server or API):"
  for issue in "${ISSUE_NUMBERS[@]}"; do
    cleanup_log "  - Issue $issue: set status to '$RELEASED_LABEL'"
  done
  cleanup_log "TRACKER_ACTION=linear_mcp_or_api_required"
  cleanup_log "TRACKER_INCOMPLETE=1 REASON=linear_status_transition_required"
  cleanup_log "TRACKER_ISSUES=$(IFS=,; printf '%s' "${ISSUE_NUMBERS[*]}")"
  cleanup_log "See docs/workflow/development-workflow/integrations/linear.md for guidance."
  cleanup_log "STAMPED=$LINEAR_STAMPED STAMP_SKIPPED=$LINEAR_STAMP_SKIPPED STAMP_FAILED=$LINEAR_STAMP_FAILED UPDATED=0 SKIPPED=0 FAILED=0"
  if [ "$BEST_EFFORT" != "true" ]; then
    echo "Release tracker transitions are incomplete until Linear issues are moved to '$RELEASED_LABEL'." >&2
    echo "Pass --best-effort only when a human explicitly accepts completing tracker transitions outside this script." >&2
    exit 1
  fi
  if [ "$COMPONENT_JSON_MODE" = "true" ]; then
    emit_component_cleanup_json "incomplete" "false" "incomplete" \
      "manually transition the scoped issue(s) to '$RELEASED_LABEL' in Linear (via MCP server or API)"
  fi
  cleanup_log "Release post-merge cleanup complete."
  exit 0
fi

cleanup_log "Transitioning scoped issues from '$MERGED_LABEL' to '$RELEASED_LABEL'..."
RELEASE_STAMPED=0
RELEASE_STAMP_SKIPPED=0
RELEASE_STAMP_FAILED=0
TRACKER_UPDATED=0
TRACKER_SKIPPED=0
TRACKER_FAILED=0

for issue in "${ISSUE_NUMBERS[@]}"; do
  if ! STAMP_OUT="$(record_release_for_issue_best_effort "$issue" "$RELEASE_VERSION")"; then
    cleanup_log "Warning: release-stamp helper failed for issue #$issue; counting as stamp failure."
    STAMP_OUT="RELEASE_STAMP_FAILED issue=${issue} version=${RELEASE_VERSION} provider=${TRACKER_PROVIDER:-unknown} reason=helper_failed"
  fi
  cleanup_log "$STAMP_OUT"
  if echo "$STAMP_OUT" | grep -q "^RELEASE_STAMPED "; then
    RELEASE_STAMPED=$((RELEASE_STAMPED + 1))
  elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_FAILED "; then
    RELEASE_STAMP_FAILED=$((RELEASE_STAMP_FAILED + 1))
  elif echo "$STAMP_OUT" | grep -q "^RELEASE_STAMP_SKIPPED "; then
    RELEASE_STAMP_SKIPPED=$((RELEASE_STAMP_SKIPPED + 1))
  else
    cleanup_log "Warning: unrecognized release-stamp output for issue #$issue; counting as stamp failure."
    RELEASE_STAMP_FAILED=$((RELEASE_STAMP_FAILED + 1))
  fi

  ISSUE_STATE=$(gh issue view "$issue" --json state --jq '.state' 2>/dev/null || true)
  if [ -z "$ISSUE_STATE" ]; then
    cleanup_log "Warning: could not read issue #$issue; skipping tracker update."
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
    continue
  fi
  # Capture output from the best-effort helper to classify the outcome.
  # The helper always exits 0; we distinguish outcomes by its stdout:
  #   "Updating tracker status..."         (GitHub Projects) -> updated
  #   "TRACKER_ACTION_REQUIRED=set_status" (Linear provider) -> deferred (counted as updated)
  #   "Warning: ... skipping ..."          (any provider)    -> skipped
  #   "Warning: GraphQL mutation failed ..." (GitHub)        -> failed
  # When the issue is already in the target status (set by GitHub project automation
  # before this script runs), the helper emits a "does not match required source
  # status" message because the current status is already 'Released' (not 'Merged').
  # Treat that as a no-op success so that UPDATED=0 only signals a real failure.
  TRACKER_OUT=$(update_tracker_status_best_effort "$issue" "$RELEASED_LABEL" "$MERGED_LABEL" 2>&1)
  cleanup_log "$TRACKER_OUT"
  if echo "$TRACKER_OUT" | grep -q "^Updating tracker status"; then
    if echo "$TRACKER_OUT" | grep -q "Warning: GraphQL mutation failed"; then
      TRACKER_FAILED=$((TRACKER_FAILED + 1))
    else
      TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
    fi
  elif echo "$TRACKER_OUT" | grep -q "^TRACKER_ACTION_REQUIRED=set_status"; then
    # Linear provider: the mutation is deferred to the orchestrator via MCP.
    # Count as updated (the orchestrator must apply this signal after this script).
    TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
  elif echo "$TRACKER_OUT" | grep -q "current status '${RELEASED_LABEL}'"; then
    # Issue is already in the target Released status (set by GitHub project automation).
    # This is a no-op success — not a failure or a skip that warrants an error exit.
    cleanup_log "Issue #$issue is already in '$RELEASED_LABEL' status; counting as success."
    TRACKER_UPDATED=$((TRACKER_UPDATED + 1))
  elif echo "$TRACKER_OUT" | grep -q "Warning:"; then
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  else
    # Unexpected output pattern — treat conservatively as a skip
    TRACKER_SKIPPED=$((TRACKER_SKIPPED + 1))
  fi
done

cleanup_log "STAMPED=$RELEASE_STAMPED STAMP_SKIPPED=$RELEASE_STAMP_SKIPPED STAMP_FAILED=$RELEASE_STAMP_FAILED UPDATED=$TRACKER_UPDATED SKIPPED=$TRACKER_SKIPPED FAILED=$TRACKER_FAILED"

if [ "$BEST_EFFORT" != "true" ]; then
  if [ "$TRACKER_FAILED" -gt 0 ]; then
    echo "Error: $TRACKER_FAILED tracker transition(s) failed for release $RELEASE_BRANCH." >&2
    echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
    exit 1
  fi

  if [ "$TRACKER_UPDATED" -eq 0 ]; then
    case "$TRACKER_PROVIDER" in
      github_projects|github-projects|github_issues|github-issues)
        ;;
      *)
        if [ "$COMPONENT_JSON_MODE" = "true" ]; then
          emit_component_cleanup_json "incomplete" "false" "incomplete" \
            "no shell-supported tracker transitions exist for provider '${TRACKER_PROVIDER:-none}'"
        fi
        cleanup_log "No shell-supported tracker transitions ran for provider '${TRACKER_PROVIDER:-none}'; release-stamp handling completed."
        cleanup_log "Release post-merge cleanup complete."
        exit 0
        ;;
    esac
    if [ "$RELEASE_STAMPED" -gt 0 ] && [ "$TRACKER_SKIPPED" -gt 0 ] && [ "$TRACKER_FAILED" -eq 0 ]; then
      cleanup_log "Release stamping succeeded, but tracker status transitions were skipped; treating cleanup as successful because no transition failed."
    else
      echo "Error: no tracker transitions succeeded (UPDATED=0) for release $RELEASE_BRANCH." >&2
      echo "Pass --best-effort to suppress this error and exit 0 regardless of transition outcomes." >&2
      exit 1
    fi
  fi
fi

if [ "$RELEASE_STAMPED" -gt 0 ]; then
  if ! finalize_release_marker_best_effort "$RELEASE_VERSION"; then
    if [ "$BEST_EFFORT" != "true" ]; then
      echo "Error: release marker finalization failed for $RELEASE_VERSION." >&2
      echo "Pass --best-effort to suppress this error and exit 0 regardless of finalization outcomes." >&2
      exit 1
    fi
    echo "Warning: release marker finalization failed for $RELEASE_VERSION; continuing because --best-effort was passed." >&2
  fi
fi

if [ "$COMPONENT_JSON_MODE" = "true" ]; then
  emit_component_cleanup_json "complete" "true" "complete"
fi
cleanup_log "Release post-merge cleanup complete."
