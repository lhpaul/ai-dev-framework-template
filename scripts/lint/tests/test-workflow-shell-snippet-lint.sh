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
run_fixture typed_non_shell_boundary pass $'```text\nstatus only\n```\n\ngit status is referenced in prose, not a snippet.\n\n<!-- workflow-shell-contract: bash-zsh -->\n```bash\necho hello\n```'

contract_doc="docs/workflow/snippet-contract-only.md"
contract_diff="$TMP_DIR/contract-only.diff"
printf '%s\n' '<!-- workflow-shell-contract: bash -->' '```bash' 'echo hello' '```' > "$REPO_ROOT/$contract_doc"
printf '%s\n' "diff --git a/$contract_doc b/$contract_doc" "--- a/$contract_doc" "+++ b/$contract_doc" '@@ -0,0 +1 @@' '+<!-- workflow-shell-contract: bash -->' > "$contract_diff"
if python3 "$LINTER" --input "$contract_diff" > "$TMP_DIR/contract-only.out" 2>&1; then
  contract_only=pass
else
  contract_only=fail
fi
check contract_only_marker fail "$contract_only"
rm -f "$REPO_ROOT/$contract_doc"

fake_git_dir="$TMP_DIR/fake-git"
mkdir -p "$fake_git_dir"
printf '%s\n' '#!/usr/bin/env sh' 'exit 1' > "$fake_git_dir/git"
chmod +x "$fake_git_dir/git"
if PATH="$fake_git_dir:$PATH" python3 "$LINTER" --base-ref ignored > "$TMP_DIR/diff-exit-one.out" 2>&1; then
  diff_exit_one=pass
else
  diff_exit_one=fail
fi
check diff_exit_one pass "$diff_exit_one"

if ! command -v zsh >/dev/null; then
  echo "FAIL: zsh is required for cross-shell fixture coverage"
  exit 1
fi
expected=$'one\ntwo\nowner repo 7\none\ntwo\nowner repo 7'
actual="$(bash -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''' && zsh -lc 'bash -lc '\''printf "one\\ntwo\\nowner repo 7\\n"'\''')"
check bash_and_zsh_launch_bash "$expected" "$actual"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
