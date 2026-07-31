#!/usr/bin/env bash
#
# Resolve the canonical release target for single-repository and workflow-hub
# component releases before any release mutation.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/workflow-config-resolver.py"

REPO_ROOT="$(pwd)"
PRODUCT_REPO=""
JSON_OUTPUT=false
REQUIRE_LOCAL=true

usage() {
  cat >&2 <<'EOF'
Usage: component-release-target.sh [--repo-root PATH] [--repo NAME] [--require-local|--no-require-local] [--json]
EOF
}

json_quote() {
  jq -Rn --arg value "$1" '$value'
}

sha256_string() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "no SHA-256 utility available; install sha256sum or shasum" >&2
    return 1
  fi
}

emit_target() {
  local routing_outcome="$1"
  local mutation_allowed="$2"
  local selected_key="$3"
  local identity="$4"
  local local_path="$5"
  local local_source="$6"
  local release_base="$7"
  local release_branch_pattern="$8"
  local owner_release="$9"
  local owner_ci="${10}"
  local owner_github_release="${11}"
  local owner_deployment="${12}"
  local owner_cleanup="${13}"
  local owner_tracker="${14}"
  local contract_revision="${15}"
  local human_action="${16}"

  local correlation_input release_correlation_key
  correlation_input="$(jq -cn \
    --arg schema_version "component_release_correlation.v1" \
    --arg routing_outcome "$routing_outcome" \
    --arg selected_key "$selected_key" \
    --arg identity "$identity" \
    --arg release_base "$release_base" \
    --arg release_branch_pattern "$release_branch_pattern" \
    --arg contract_revision "$contract_revision" \
    '{schema_version:$schema_version,routing_outcome:$routing_outcome,selected_product_repo_key:$selected_key,canonical_repository_identity:$identity,release_base:$release_base,release_branch_pattern:$release_branch_pattern,contract_revision:$contract_revision}')"
  release_correlation_key="sha256:$(printf '%s' "$correlation_input" | sha256_string)"

  if [ "$JSON_OUTPUT" = "true" ]; then
    jq -cnS \
      --arg schema_version "component_release_target.v1" \
      --arg routing_outcome "$routing_outcome" \
      --argjson mutation_allowed "$mutation_allowed" \
      --arg selected_key "$selected_key" \
      --arg identity "$identity" \
      --arg local_path "$local_path" \
      --arg local_source "$local_source" \
      --arg release_base "$release_base" \
      --arg release_branch_pattern "$release_branch_pattern" \
      --arg owner_release "$owner_release" \
      --arg owner_ci "$owner_ci" \
      --arg owner_github_release "$owner_github_release" \
      --arg owner_deployment "$owner_deployment" \
      --arg owner_cleanup "$owner_cleanup" \
      --arg owner_tracker "$owner_tracker" \
      --arg release_correlation_key "$release_correlation_key" \
      --arg contract_revision "$contract_revision" \
      --arg human_action "$human_action" \
      '{
        schema_version:$schema_version,
        routing_outcome:$routing_outcome,
        mutation_allowed:$mutation_allowed,
        selected_product_repo_key:($selected_key | if . == "" then null else . end),
        canonical_repository_identity:$identity,
        local_checkout:{path:$local_path,source:$local_source},
        release_base:$release_base,
        release_branch_pattern:$release_branch_pattern,
        artifact_owners:{
          release:$owner_release,
          ci:$owner_ci,
          github_release:$owner_github_release,
          deployment:$owner_deployment,
          cleanup:$owner_cleanup,
          tracker:$owner_tracker
        },
        release_correlation_key:$release_correlation_key,
        contract_revision:$contract_revision,
        human_action:$human_action
      }'
    return 0
  fi

  printf 'SCHEMA_VERSION=%s\n' "component_release_target.v1"
  printf 'ROUTING_OUTCOME=%s\n' "$routing_outcome"
  printf 'MUTATION_ALLOWED=%s\n' "$mutation_allowed"
  printf 'SELECTED_PRODUCT_REPO_KEY=%s\n' "$selected_key"
  printf 'CANONICAL_REPOSITORY_IDENTITY=%s\n' "$identity"
  printf 'LOCAL_CHECKOUT_PATH=%s\n' "$local_path"
  printf 'LOCAL_CHECKOUT_SOURCE=%s\n' "$local_source"
  printf 'RELEASE_BASE=%s\n' "$release_base"
  printf 'RELEASE_BRANCH_PATTERN=%s\n' "$release_branch_pattern"
  printf 'ARTIFACT_OWNER_RELEASE=%s\n' "$owner_release"
  printf 'ARTIFACT_OWNER_CI=%s\n' "$owner_ci"
  printf 'ARTIFACT_OWNER_GITHUB_RELEASE=%s\n' "$owner_github_release"
  printf 'ARTIFACT_OWNER_DEPLOYMENT=%s\n' "$owner_deployment"
  printf 'ARTIFACT_OWNER_CLEANUP=%s\n' "$owner_cleanup"
  printf 'ARTIFACT_OWNER_TRACKER=%s\n' "$owner_tracker"
  printf 'RELEASE_CORRELATION_KEY=%s\n' "$release_correlation_key"
  printf 'CONTRACT_REVISION=%s\n' "$contract_revision"
  printf 'HUMAN_ACTION=%s\n' "$human_action"
}

emit_stop() {
  local outcome="$1"
  local action="$2"
  local tracker_owner="${3:-not_applicable}"
  emit_target "$outcome" "false" "" "" "" "" "" "" \
    "not_applicable" "not_applicable" "not_applicable" "not_applicable" "not_applicable" "$tracker_owner" "" "$action"
}

resolve_mode() {
  local output
  if ! output="$(python3 "$RESOLVER" mode --repo-root "$REPO_ROOT" --json 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 2
  fi
  jq -r '.WORKFLOW_MODE // "single_repo"' <<< "$output"
}

resolver_json() {
  local output status=0
  set +e
  if [ "$REQUIRE_LOCAL" = "true" ]; then
    output="$(python3 "$RESOLVER" validate --repo-root "$REPO_ROOT" --repo "$PRODUCT_REPO" --require-local --json 2>&1)"
  else
    output="$(python3 "$RESOLVER" validate --repo-root "$REPO_ROOT" --repo "$PRODUCT_REPO" --json 2>&1)"
  fi
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

owner_from_resolver() {
  local raw="$1"
  case "$raw" in
    current_repo) printf 'current_repository\n' ;;
    product_repo) printf 'product_repository\n' ;;
    hub|hub_reference) printf 'hub_repository\n' ;;
    not_applicable|"") printf 'not_applicable\n' ;;
    *) printf 'invalid\n' ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      REPO_ROOT="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || { usage; exit 2; }
      if [ -n "$PRODUCT_REPO" ]; then
        PRODUCT_REPO="${PRODUCT_REPO},$2"
      else
        PRODUCT_REPO="$2"
      fi
      shift 2
      ;;
    --require-local)
      REQUIRE_LOCAL=true
      shift
      ;;
    --no-require-local)
      REQUIRE_LOCAL=false
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

case "$PRODUCT_REPO" in
  *,*|*" "*)
    emit_stop "multiple_product_targets" "select exactly one product repository for this component release" "hub_repository"
    exit 0
    ;;
esac

MODE="$(resolve_mode)"

if [ "$MODE" = "single_repo" ]; then
  resolver_args=(validate --repo-root "$REPO_ROOT" --json)
  if [ "$REQUIRE_LOCAL" = "true" ]; then
    resolver_args+=(--require-local)
  fi
  output="$(python3 "$RESOLVER" "${resolver_args[@]}")"
  identity="$(jq -r '.TARGET_GITHUB_REPO // ""' <<< "$output")"
  if [ -z "$identity" ]; then
    identity="$(jq -r '.TARGET_LOCAL_PATH // ""' <<< "$output")"
  fi
  emit_target "single_repo_release" "true" "" "$identity" \
    "$(jq -r '.TARGET_LOCAL_PATH // ""' <<< "$output")" \
    "$(jq -r '.TARGET_LOCAL_PATH_SOURCE // ""' <<< "$output")" \
    "$(jq -r '.TARGET_RELEASE_BASE // ""' <<< "$output")" \
    "$(jq -r '.TARGET_RELEASE_BRANCH_PATTERN // ""' <<< "$output")" \
    "current_repository" "current_repository" "current_repository" "current_repository" "current_repository" "current_repository" \
    "$(jq -r '.TARGET_RELEASE_CONTRACT_REVISION // ""' <<< "$output")" ""
  exit 0
fi

if [ "$MODE" = "product_repo" ]; then
  emit_stop "unsupported_repository_mode" "run the single-repository release workflow from the product repository or correct repository mode"
  exit 0
fi

if [ "$MODE" != "workflow_hub" ]; then
  emit_stop "unsupported_repository_mode" "correct repository mode before preparing a component release"
  exit 0
fi

if [ -z "$PRODUCT_REPO" ]; then
  emit_stop "missing_product_selection" "pass --repo with one configured product repository key" "hub_repository"
  exit 0
fi

resolver_result="$(resolver_json)"
resolver_status="$(printf '%s\n' "$resolver_result" | sed -n '1p')"
resolver_output="$(printf '%s\n' "$resolver_result" | sed '1d')"
if [ "$resolver_status" -ne 0 ]; then
  case "$resolver_output" in
    *"no workflow_hub.product_repos entry named"*)
      emit_stop "unknown_product_repository" "select one configured product repository key" "hub_repository"
      exit 0
      ;;
    *"product repository selection is ambiguous"*)
      emit_stop "ambiguous_product_selection" "select exactly one configured product repository key" "hub_repository"
      exit 0
      ;;
    *"local path for product repo"*)
      emit_stop "unavailable_product_repository_checkout" "configure a local checkout path for the selected product repository" "hub_repository"
      exit 0
      ;;
    *workflow_hub.product_repos*.release.*|*product_repo.release.*|*"contains forbidden local or secret value"*)
      emit_stop "invalid_release_contract" "correct the selected product repository release contract before mutation" "hub_repository"
      exit 0
      ;;
    *)
      printf '%s\n' "$resolver_output" >&2
      exit "$resolver_status"
      ;;
  esac
fi

release_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_CHANGELOG_OWNER // ""' <<< "$resolver_output")")"
ci_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_TAG_OWNER // ""' <<< "$resolver_output")")"
github_release_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_GITHUB_RELEASE_OWNER // ""' <<< "$resolver_output")")"
deployment_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_DEPLOYMENT_EVIDENCE_OWNER // ""' <<< "$resolver_output")")"
cleanup_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_CLEANUP_EVIDENCE_OWNER // ""' <<< "$resolver_output")")"
tracker_owner="$(owner_from_resolver "$(jq -r '.TARGET_RELEASE_TRACKER_RECONCILIATION_OWNER // ""' <<< "$resolver_output")")"
if [ "$release_owner" != "product_repository" ] || \
   [ "$ci_owner" != "product_repository" ] || \
   [ "$github_release_owner" != "product_repository" ] || \
   [ "$deployment_owner" != "product_repository" ] || \
   [ "$cleanup_owner" != "product_repository" ] || \
   [ "$tracker_owner" != "hub_repository" ]; then
  emit_stop "invalid_release_contract" "route release, ci, GitHub release, deployment, and cleanup artifacts to the product repository and tracker reconciliation to the hub" "hub_repository"
  exit 0
fi

identity="$(jq -r '.TARGET_GITHUB_REPO // ""' <<< "$resolver_output")"
if [ -z "$identity" ]; then
  identity="$(jq -r '.TARGET_GIT_URL // .TARGET_REPO_NAME // ""' <<< "$resolver_output")"
fi
emit_target "component_release_routed" "true" "$PRODUCT_REPO" "$identity" \
  "$(jq -r '.TARGET_LOCAL_PATH // ""' <<< "$resolver_output")" \
  "$(jq -r '.TARGET_LOCAL_PATH_SOURCE // ""' <<< "$resolver_output")" \
  "$(jq -r '.TARGET_RELEASE_BASE // ""' <<< "$resolver_output")" \
  "$(jq -r '.TARGET_RELEASE_BRANCH_PATTERN // ""' <<< "$resolver_output")" \
  "product_repository" "product_repository" "product_repository" "product_repository" "product_repository" "hub_repository" \
  "$(jq -r '.TARGET_RELEASE_CONTRACT_REVISION // ""' <<< "$resolver_output")" ""
