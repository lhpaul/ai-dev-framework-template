#!/usr/bin/env bash
# covers: scripts/development-workflow/changelog-fragments.sh
# covers: .github/workflows/markdown-lint.yml
# covers: changelog.d/**
# covers: docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
HELPER="$ROOT_DIR/scripts/development-workflow/changelog-fragments.sh"
TMP_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s - expected %s, got %s\n' "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

contains() {
  local needle="$1" haystack="$2"
  case "$haystack" in
    *"$needle"*) printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

new_case() {
  local name="$1"
  local dir="$TMP_ROOT/$name"
  mkdir -p "$dir/changelog.d"
  cat > "$dir/CHANGELOG.md" <<'MD'
# Changelog

## [Unreleased]

### Added

- **Existing alpha** (#1): already pending.

### Fixed

- **Existing beta** (#2): already pending.

## [0.1.0] - 2026-01-01

- Prior release.

[Unreleased]: https://example.com/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/releases/v0.1.0
MD
  printf '%s' "$dir"
}

write_fragment() {
  local dir="$1" name="$2" body="$3"
  printf '%s\n' "$body" > "$dir/changelog.d/$name"
}

validate_case() {
  local dir="$1"
  "$HELPER" validate --dir "$dir/changelog.d" 2>&1 || true
}

assemble_case() {
  local dir="$1"
  shift
  "$HELPER" assemble --dir "$dir/changelog.d" --changelog "$dir/CHANGELOG.md" "$@" 2>&1 || true
}

echo ""
echo "=== filename grammar ==="
dir="$(new_case grammar)"
write_fragment "$dir" "1554.fixed.a.md" "- **A** (#1554): ok."
write_fragment "$dir" "1554.fixed.changelog-fragments-collide.md" "- **B** (#1554): ok."
write_fragment "$dir" "ENG-42.added.export-button.md" "- **C** (#42): ok."
write_fragment "$dir" "1554.fixed.fixed-fixed.md" "- **D** (#1554): ok."
out="$(validate_case "$dir")"
run_test "valid_names_clean" "yes" "$(contains "VALIDATE_RESULT=clean" "$out")"
run_test "valid_names_count" "yes" "$(contains "FRAGMENT_COUNT=4" "$out")"

dir="$(new_case invalid-names)"
write_fragment "$dir" "1554.improved.x.md" "- **A** (#1554): bad kind."
write_fragment "$dir" "1554.Fixed.x.md" "- **A** (#1554): uppercase kind."
write_fragment "$dir" "1554.fixed.md" "- **A** (#1554): too few fields."
write_fragment "$dir" "1554.fixed.a.b.md" "- **A** (#1554): dot in slug."
write_fragment "$dir" ".fixed.a.md" "- **A** (#1554): empty item."
write_fragment "$dir" "1554.fixed.notes.txt" "- **A** (#1554): wrong extension."
touch "$dir/changelog.d/.gitkeep" "$dir/changelog.d/.DS_Store"
printf '# docs\n' > "$dir/changelog.d/README.md"
mkdir -p "$dir/changelog.d/manifests"
printf 'ignored\n' > "$dir/changelog.d/manifests/v1.0.0.txt"
out="$(validate_case "$dir")"
run_test "invalid_names_result" "yes" "$(contains "VALIDATE_RESULT=invalid" "$out")"
run_test "invalid_names_loud" "yes" "$(contains "1554.fixed.notes.txt" "$out")"

echo ""
echo "=== body validation ==="
dir="$(new_case body)"
write_fragment "$dir" "1554.fixed.empty.md" ""
write_fragment "$dir" "1555.fixed.not-bullet.md" "not a bullet"
write_fragment "$dir" "1556.fixed.heading.md" $'- **Heading** (#1556): ok.\n## Bad'
printf -- '- **Trailing** (#1557): bad. \n' > "$dir/changelog.d/1557.fixed.trailing.md"
out="$(validate_case "$dir")"
run_test "body_invalid_result" "yes" "$(contains "VALIDATE_RESULT=invalid" "$out")"
run_test "body_empty_rejected" "yes" "$(contains "empty or whitespace-only" "$out")"
run_test "body_heading_rejected" "yes" "$(contains "markdown headings" "$out")"
run_test "body_trailing_rejected" "yes" "$(contains "trailing whitespace" "$out")"

dir="$(new_case body-valid)"
write_fragment "$dir" "1554.fixed.multi.md" $'- **One** (#1554): ok.\n  continued\n- **Two** (#1554): ok.'
printf -- '- **CRLF** (#1555): ok.\r\n' > "$dir/changelog.d/1555.fixed.crlf.md"
out="$(validate_case "$dir")"
run_test "body_valid_multi_and_crlf" "yes" "$(contains "VALIDATE_RESULT=clean" "$out")"

echo ""
echo "=== list and assemble ==="
dir="$(new_case assemble)"
write_fragment "$dir" "902.changed.gamma.md" "- **Gamma** (#902): changed."
write_fragment "$dir" "900.added.alpha.md" "- **Alpha** (#900): added."
write_fragment "$dir" "901.fixed.beta.md" "- **Beta** (#901): fixed."
out="$("$HELPER" list --dir "$dir/changelog.d")"
run_test "list_count" "yes" "$(contains "PENDING_COUNT=3" "$out")"
dir="$(new_case list-empty)"
out="$("$HELPER" list --dir "$dir/changelog.d")"
run_test "list_empty_count" "yes" "$(contains "PENDING_COUNT=0" "$out")"
out="$("$HELPER" list --dir "$dir/changelog.d" --json)"
run_test "list_empty_json" '{"pending":[]}' "$(printf '%s\n' "$out" | jq -c .)"
dir="$(new_case assemble)"
write_fragment "$dir" "902.changed.gamma.md" "- **Gamma** (#902): changed."
write_fragment "$dir" "900.added.alpha.md" "- **Alpha** (#900): added."
write_fragment "$dir" "901.fixed.beta.md" "- **Beta** (#901): fixed."
out="$(assemble_case "$dir" --version 0.2.0 --date 2026-02-03)"
run_test "assemble_result" "yes" "$(contains "ASSEMBLE_RESULT=assembled" "$out")"
run_test "assemble_counts_fragments" "yes" "$(contains "FRAGMENT_COUNT=3" "$out")"
run_test "assemble_counts_carried" "yes" "$(contains "CARRIED_OVER_COUNT=2" "$out")"
run_test "assemble_items" "yes" "$(contains "ITEMS=900,902,901" "$out")"
run_test "assemble_deletes_fragments" "0" "$(find "$dir/changelog.d" -maxdepth 1 -name '*.md' ! -name README.md | wc -l | tr -d ' ')"
run_test "assemble_version_present" "yes" "$(contains "## [0.2.0] - 2026-02-03" "$(cat "$dir/CHANGELOG.md")")"
run_test "assemble_fresh_unreleased" "yes" "$(contains $'## [Unreleased]\n\n## [0.2.0]' "$(cat "$dir/CHANGELOG.md")")"
run_test "assemble_added_before_changed" "yes" "$(
  awk '/### Added/{a=NR} /### Changed/{c=NR} END{print (a<c ? "yes" : "no")}' "$dir/CHANGELOG.md"
)"
second="$(assemble_case "$dir" --version 0.2.0 --date 2026-02-04)"
run_test "assemble_idempotent_different_date" "yes" "$(contains "ASSEMBLE_RESULT=already_assembled" "$second")"
run_test "assemble_keeps_first_date" "no" "$(contains "2026-02-04" "$(cat "$dir/CHANGELOG.md")")"
printf 'invalid late note\n' > "$dir/changelog.d/9999.fixed.late-invalid.md"
second_with_invalid="$(assemble_case "$dir" --version 0.2.0 --date 2026-02-05)"
run_test "assemble_idempotent_ignores_late_invalid_fragment" "yes" "$(contains "ASSEMBLE_RESULT=already_assembled" "$second_with_invalid")"

printf '[0.2.0]: https://example.com/compare/v0.1.0...v0.2.0\n' >> "$dir/CHANGELOG.md"
node_modules/.bin/markdownlint-cli2 "$dir/CHANGELOG.md" >/dev/null
python3 "$ROOT_DIR/scripts/lint/markdown-heuristic-lint.py" "$dir/CHANGELOG.md"
bash "$ROOT_DIR/scripts/lint/check-changelog-duplicate-headers.sh" "$dir/CHANGELOG.md"
run_test "assembled_output_lints" "yes" "yes"

echo ""
echo "=== no notes and allow-empty ==="
dir="$(new_case empty)"
python3 - "$dir/CHANGELOG.md" <<'PY'
import sys
p = sys.argv[1]
text = open(p, encoding="utf-8").read()
start = text.index("## [Unreleased]")
end = text.index("## [0.1.0]")
open(p, "w", encoding="utf-8").write(text[:start] + "## [Unreleased]\n\n" + text[end:])
PY
out="$(assemble_case "$dir" --version 0.3.0 --date 2026-03-04)"
run_test "no_notes_result" "yes" "$(contains "ASSEMBLE_RESULT=no_notes" "$out")"
out="$(assemble_case "$dir" --version 0.3.0 --date 2026-03-04 --allow-empty)"
run_test "allow_empty_assembled" "yes" "$(contains "ASSEMBLE_RESULT=assembled" "$out")"
run_test "allow_empty_zero_counts" "yes" "$(contains "FRAGMENT_COUNT=0" "$out")"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
