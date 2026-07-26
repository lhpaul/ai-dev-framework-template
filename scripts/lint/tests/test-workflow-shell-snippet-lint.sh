#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LINTER="$REPO_ROOT/scripts/lint/workflow-shell-snippet-lint.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name expected=$expected actual=$actual"
    FAIL=$((FAIL + 1))
  fi
}

run_fixture() {
  local name="$1" expected="$2" content="$3"
  local doc="docs/workflow/snippet-$name.md"
  local diff="$TMP_DIR/$name.diff"
  mkdir -p "$REPO_ROOT/docs/workflow"
  printf '%s\n' "$content" > "$REPO_ROOT/$doc"
  {
    printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n@@ -0,0 +1,%s @@\n' "$doc" "$doc" "$doc" "$(wc -l < "$REPO_ROOT/$doc" | tr -d ' ')"
    sed 's/^/+/' "$REPO_ROOT/$doc"
  } > "$diff"
  if python3 "$LINTER" --input "$diff" > "$TMP_DIR/$name.out" 2>&1; then
    actual=pass
  else
    actual=fail
  fi
  check "$name" "$expected" "$actual"
  rm -f "$REPO_ROOT/$doc"
}

run_fixture missing_contract fail $'```bash\necho hello\n```'
run_fixture bash_boundary fail $'<!-- workflow-shell-contract: bash -->\n```bash\necho hello\n```'
run_fixture bash_contract_pass pass $'<!-- workflow-shell-contract: bash -->\n```bash\nbash -lc "echo hello"\n```'
run_fixture portable_for fail $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nfor item in $ITEMS; do echo "$item"; done\n```'
run_fixture portable_set fail $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nset -- $pair\n```'
run_fixture portable_pass pass $'<!-- workflow-shell-contract: bash-zsh -->\n```shell\nwhile IFS= read -r item; do echo "$item"; done <<EOF\na\nEOF\n```'

if ! command -v zsh >/dev/null; then
  echo "FAIL: zsh is required for cross-shell fixture coverage"
  exit 1
fi
expected=$'one\ntwo\nowner repo 7\none\ntwo\nowner repo 7'
actual="$(bash -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''' && zsh -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''')"
check bash_and_zsh_launch_bash "$expected" "$actual"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
