#!/usr/bin/env bash
# open-product-pr.sh - open or dry-run product repository PRs from a workflow hub.

set -euo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)"
RESOLVER="$SCRIPT_DIR/workflow-config-resolver.py"
TOKEN_HELPER="$SCRIPT_DIR/github-app-token.sh"

usage() {
  cat <<'USAGE'
Usage: open-product-pr.sh --repo <product-name> --base <branch> --head <branch> --title <title> --body-file <path> [--repo-root <path>] [--dry-run]

Opens a pull request in the selected product repository. Dry-run mode prints the
target repo and redacted command shape without requiring credentials.
USAGE
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

quote_arg() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/$/'/"
}

github_repo_from_url() {
  local value="$1"
  case "$value" in
    git@github.com:*/*.git)
      value="${value#git@github.com:}"
      value="${value%.git}"
      ;;
    git@github.com:*/*)
      value="${value#git@github.com:}"
      ;;
    https://github.com/*/*.git)
      value="${value#https://github.com/}"
      value="${value%.git}"
      ;;
    https://github.com/*/*)
      value="${value#https://github.com/}"
      value="${value%/}"
      ;;
    ssh://git@github.com/*/*.git)
      value="${value#ssh://git@github.com/}"
      value="${value%.git}"
      ;;
    ssh://git@github.com/*/*)
      value="${value#ssh://git@github.com/}"
      value="${value%/}"
      ;;
    *)
      value=""
      ;;
  esac
  printf '%s\n' "$value"
}

REPO_NAME=""
BASE_BRANCH=""
HEAD_BRANCH=""
TITLE=""
BODY_FILE=""
DRY_RUN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      [ "$#" -ge 2 ] || die "--repo requires a value"
      REPO_NAME="$2"
      shift 2
      ;;
    --repo-root)
      [ "$#" -ge 2 ] || die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --base)
      [ "$#" -ge 2 ] || die "--base requires a value"
      BASE_BRANCH="$2"
      shift 2
      ;;
    --head)
      [ "$#" -ge 2 ] || die "--head requires a value"
      HEAD_BRANCH="$2"
      shift 2
      ;;
    --title)
      [ "$#" -ge 2 ] || die "--title requires a value"
      TITLE="$2"
      shift 2
      ;;
    --body-file)
      [ "$#" -ge 2 ] || die "--body-file requires a value"
      BODY_FILE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument '$1'"
      ;;
  esac
done

[ -n "$REPO_NAME" ] || die "--repo is required"
[ -n "$BASE_BRANCH" ] || die "--base is required"
[ -n "$HEAD_BRANCH" ] || die "--head is required"
[ -n "$TITLE" ] || die "--title is required"
[ -n "$BODY_FILE" ] || die "--body-file is required"
[ -r "$BODY_FILE" ] || die "--body-file must be readable"

if ! CONTEXT_OUTPUT="$(python3 "$RESOLVER" resolve --repo-root "$REPO_ROOT" --repo "$REPO_NAME" 2>&1)"; then
  printf '%s\n' "$CONTEXT_OUTPUT" >&2
  exit 1
fi
eval "$CONTEXT_OUTPUT"

if [ "${WORKFLOW_MODE:-}" != "workflow_hub" ]; then
  die "product PR operations require workflow_hub mode"
fi

TARGET_REPO="${TARGET_GITHUB_REPO:-}"
if [ -z "$TARGET_REPO" ] && [ -n "${TARGET_GIT_URL:-}" ]; then
  TARGET_REPO="$(github_repo_from_url "$TARGET_GIT_URL")"
fi
[ -n "$TARGET_REPO" ] || die "selected product repository does not resolve to a GitHub owner/repo slug"

if [ "$DRY_RUN" = true ]; then
  printf 'DRY_RUN=true\n'
  printf 'TARGET_REPO=%s\n' "$TARGET_REPO"
  printf 'BASE_BRANCH=%s\n' "$BASE_BRANCH"
  printf 'HEAD_BRANCH=%s\n' "$HEAD_BRANCH"
  printf 'TITLE=%s\n' "$TITLE"
  printf 'COMMAND=%s\n' "GH_TOKEN=<redacted> gh pr create --repo $(quote_arg "$TARGET_REPO") --base $(quote_arg "$BASE_BRANCH") --head $(quote_arg "$HEAD_BRANCH") --title $(quote_arg "$TITLE") --body-file $(quote_arg "$BODY_FILE")"
  exit 0
fi

TOKEN_ERR="$(mktemp)"
if ! TOKEN="$("$TOKEN_HELPER" --repo-root "$REPO_ROOT" --repo "$REPO_NAME" --print-token 2>"$TOKEN_ERR")"; then
  cat "$TOKEN_ERR" >&2
  rm -f "$TOKEN_ERR"
  exit 1
fi
rm -f "$TOKEN_ERR"
[ -n "$TOKEN" ] || die "token helper returned an empty token"

if ! PR_OUTPUT="$(GH_TOKEN="$TOKEN" gh pr create --repo "$TARGET_REPO" --base "$BASE_BRANCH" --head "$HEAD_BRANCH" --title "$TITLE" --body-file "$BODY_FILE" 2>&1)"; then
  printf '%s\n' "$PR_OUTPUT" >&2
  exit 1
fi

printf 'PR_URL=%s\n' "$PR_OUTPUT"
