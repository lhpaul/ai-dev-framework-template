#!/usr/bin/env bash
# validate-workflow-branch-name.sh - enforce workflow branch naming convention.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: validate-workflow-branch-name.sh <branch-name>

Validates a tracked workflow branch name before branch creation or push.
USAGE
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

branch_name="$1"

case "$branch_name" in
  *'#'*|*'?'*|*'^'*|*'~'*|*':'*|*'\'*|*' '*)
    printf 'ERROR: workflow branch name violates the branch convention: %s\n' "$branch_name" >&2
    printf 'Unsafe characters are not allowed: # ? ^ ~ : backslash, or spaces.\n' >&2
    printf 'Use a bare numeric tracker identifier, for example fix/1858-slug (not fix/#1858-slug).\n' >&2
    exit 2
    ;;
esac

if [[ ! "$branch_name" =~ ^(spec|implementation-plan|feature|fix|refactor|hotfix|backport/hotfix)/([A-Za-z][A-Za-z0-9]{0,7}-)?[1-9][0-9]*-[a-z0-9][a-z0-9-]*$ ]]; then
  printf 'ERROR: workflow branch name must use an accepted prefix and issue-prefixed kebab-case slug: %s\n' "$branch_name" >&2
  printf 'Use a bare numeric tracker identifier, for example fix/1858-slug (not fix/#1858-slug).\n' >&2
  exit 2
fi

printf 'VALID_WORKFLOW_BRANCH=%s\n' "$branch_name"
