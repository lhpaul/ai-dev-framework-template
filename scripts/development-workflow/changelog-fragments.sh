#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"

FRAGMENT_DIR="changelog.d"
CHANGELOG_FILE="CHANGELOG.md"

usage() {
  cat <<'EOF'
Usage:
  changelog-fragments.sh validate [--dir <path>]
  changelog-fragments.sh list [--dir <path>] [--json]
  changelog-fragments.sh assemble --version <X.Y.Z> [--date <YYYY-MM-DD>] [--allow-empty] [--dir <path>] [--changelog <path>]

Validates and assembles per-item changelog fragments.
EOF
}

die_usage() {
  printf 'ERROR: %s\n' "$1" >&2
  usage >&2
  exit 64
}

is_valid_fragment_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*\.(added|changed|deprecated|removed|fixed|security)\.[a-z0-9][a-z0-9-]*\.md$ ]]
}

fragment_kind() {
  local name="$1" rest
  rest="${name#*.}"
  printf '%s' "${rest%%.*}"
}

fragment_item() {
  printf '%s' "${1%%.*}"
}

kind_heading() {
  case "$1" in
    added) printf 'Added' ;;
    changed) printf 'Changed' ;;
    deprecated) printf 'Deprecated' ;;
    removed) printf 'Removed' ;;
    fixed) printf 'Fixed' ;;
    security) printf 'Security' ;;
    *) printf '%s' "$1" ;;
  esac
}

kind_rank() {
  case "$1" in
    added) printf '1' ;;
    changed) printf '2' ;;
    deprecated) printf '3' ;;
    removed) printf '4' ;;
    fixed) printf '5' ;;
    security) printf '6' ;;
    *) printf '99' ;;
  esac
}

item_sort_key() {
  local item="$1"
  if [[ "$item" =~ ^[0-9]+$ ]]; then
    printf '0:%012d' "$item"
  else
    printf '1:%s' "$item"
  fi
}

collect_entries() {
  local dir="$1" path name
  [ -d "$dir" ] || return 0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    name="$(basename "$path")"
    case "$name" in
      README.md|.gitkeep|.DS_Store) continue ;;
    esac
    if [ -f "$path" ]; then
      if is_valid_fragment_name "$name"; then
        printf 'fragment\t%s\t%s\t%s\t%s\t%s\n' \
          "$(kind_rank "$(fragment_kind "$name")")" \
          "$(item_sort_key "$(fragment_item "$name")")" \
          "$name" \
          "$(fragment_kind "$name")" \
          "$path"
      else
        printf 'candidate\t%s\n' "$path"
      fi
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type f | LC_ALL=C sort)
}

validate_body() {
  local path="$1" normalized first_non_blank top_bullets
  normalized="$(tr -d '\r' < "$path")"
  if ! printf '%s' "$normalized" | grep -q '[^[:space:]]'; then
    printf 'empty or whitespace-only file'
    return 1
  fi
  first_non_blank="$(printf '%s\n' "$normalized" | awk 'NF {print; exit}')"
  case "$first_non_blank" in
    "- "*) ;;
    *)
      printf 'first non-blank line must begin with "- "'
      return 1
      ;;
  esac
  if printf '%s\n' "$normalized" | grep -Eq '^(## |### )'; then
    printf 'body must not contain level-2 or level-3 markdown headings'
    return 1
  fi
  if printf '%s\n' "$normalized" | grep -Eq '[[:blank:]]$'; then
    printf 'body contains trailing whitespace'
    return 1
  fi
  top_bullets="$(printf '%s\n' "$normalized" | grep -Ec '^- ' || true)"
  if [ "$top_bullets" -lt 1 ]; then
    printf 'body must contain at least one top-level bullet'
    return 1
  fi
  return 0
}

validate_fragments() {
  local dir="$1" kind_rank_value item_key name kind path invalid=0 count=0 reason
  while IFS=$'\t' read -r tag a b c d e; do
    [ -n "$tag" ] || continue
    if [ "$tag" = "candidate" ]; then
      printf 'INVALID_FRAGMENT=%s: invalid filename; expected <item>.<kind>.<slug>.md with kind added|changed|deprecated|removed|fixed|security\n' "$a"
      invalid=$((invalid + 1))
      continue
    fi
    kind_rank_value="$a"; item_key="$b"; name="$c"; kind="$d"; path="$e"
    : "$kind_rank_value" "$item_key" "$name" "$kind"
    count=$((count + 1))
    if ! reason="$(validate_body "$path")"; then
      printf 'INVALID_FRAGMENT=%s: %s\n' "$path" "$reason"
      invalid=$((invalid + 1))
    fi
  done < <(collect_entries "$dir")
  if [ "$invalid" -eq 0 ]; then
    printf 'VALIDATE_RESULT=clean\n'
  else
    printf 'VALIDATE_RESULT=invalid\n'
  fi
  printf 'FRAGMENT_COUNT=%s\n' "$count"
  [ "$invalid" -eq 0 ]
}

list_fragments() {
  local dir="$1" json="$2" paths=() path
  while IFS=$'\t' read -r tag a b c d e; do
    [ -n "$tag" ] || continue
    [ "$tag" = "fragment" ] || continue
    path="$e"
    paths+=("$path")
  done < <(collect_entries "$dir" | LC_ALL=C sort -t $'\t' -k2,2n -k3,3 -k4,4)
  if [ "$json" = "true" ]; then
    printf '%s\n' "${paths[@]}" | jq -R -s '{pending: (split("\n") | map(select(length > 0)))}'
  else
    printf 'PENDING_COUNT=%s\n' "${#paths[@]}"
    for path in "${paths[@]}"; do
      printf 'PENDING=%s\n' "$path"
    done
  fi
}

count_shared_bullets() {
  local changelog="$1"
  awk '
    /^## \[Unreleased\]/ {in_unreleased=1; next}
    in_unreleased && /^## \[/ {exit}
    in_unreleased && /^- / {count++}
    END {print count + 0}
  ' "$changelog"
}

shared_block_empty() {
  [ "$(count_shared_bullets "$1")" -eq 0 ]
}

require_single_unreleased() {
  local changelog="$1" count
  count="$(grep -Ec '^## \[Unreleased\]([[:space:]]*)$' "$changelog" || true)"
  if [ "$count" -ne 1 ]; then
    printf 'ERROR: expected exactly one ## [Unreleased] heading; found %s\n' "$count" >&2
    return 1
  fi
}

version_exists() {
  local changelog="$1" version="$2"
  grep -Eq "^## \\[${version//./\\.}\\]([[:space:]]|$)" "$changelog"
}

assemble_changelog() {
  local changelog="$1" dir="$2" version="$3" release_date="$4" allow_empty="$5"
  local tmp fragment_count carried_count items_csv
  local entries_file bodies_file
  entries_file="$(mktemp "${TMPDIR:-/tmp}/changelog-fragments.entries.XXXXXX")"
  bodies_file="$(mktemp "${TMPDIR:-/tmp}/changelog-fragments.bodies.XXXXXX")"
  trap 'rm -f "$entries_file" "$bodies_file"' RETURN

  if ! validate_fragments "$dir"; then
    printf 'ASSEMBLE_RESULT=invalid\n'
    printf 'VERSION=%s\n' "$version"
    return 1
  fi

  if version_exists "$changelog" "$version"; then
    printf 'ASSEMBLE_RESULT=already_assembled\n'
    printf 'VERSION=%s\n' "$version"
    return 0
  fi

  require_single_unreleased "$changelog" || {
    printf 'ASSEMBLE_RESULT=invalid\n'
    printf 'VERSION=%s\n' "$version"
    return 1
  }

  collect_entries "$dir" | awk -F '\t' '$1 == "fragment"' | LC_ALL=C sort -t $'\t' -k2,2n -k3,3 -k4,4 > "$entries_file"
  fragment_count="$(wc -l < "$entries_file" | tr -d ' ')"
  carried_count="$(count_shared_bullets "$changelog")"
  if [ "$fragment_count" -eq 0 ] && [ "$carried_count" -eq 0 ] && [ "$allow_empty" != "true" ]; then
    printf 'ASSEMBLE_RESULT=no_notes\n'
    printf 'VERSION=%s\n' "$version"
    printf 'FRAGMENT_COUNT=0\n'
    printf 'CARRIED_OVER_COUNT=0\n'
    printf 'ITEMS=\n'
    return 3
  fi

  while IFS=$'\t' read -r _tag _rank _item_key name kind path; do
    {
      printf -- '---FRAGMENT\t%s\t%s\t%s\n' "$kind" "$(fragment_item "$name")" "$path"
      tr -d '\r' < "$path"
      printf '\n'
    } >> "$bodies_file"
  done < "$entries_file"

  tmp="$(mktemp "${TMPDIR:-/tmp}/CHANGELOG.XXXXXX")"
  python3 - "$changelog" "$bodies_file" "$version" "$release_date" "$tmp" <<'PY'
import sys
from collections import OrderedDict

changelog_path, bodies_path, version, date, out_path = sys.argv[1:6]
kind_order = ["added", "changed", "deprecated", "removed", "fixed", "security"]
heading_for = {
    "added": "Added",
    "changed": "Changed",
    "deprecated": "Deprecated",
    "removed": "Removed",
    "fixed": "Fixed",
    "security": "Security",
}

with open(changelog_path, encoding="utf-8", newline="") as f:
    lines = f.read().splitlines()

unreleased_indices = [i for i, line in enumerate(lines) if line == "## [Unreleased]"]
if len(unreleased_indices) != 1:
    raise SystemExit("expected exactly one ## [Unreleased] heading")
start = unreleased_indices[0]
end = len(lines)
for i in range(start + 1, len(lines)):
    if lines[i].startswith("## ["):
        end = i
        break

prefix = lines[:start]
old_block = lines[start + 1:end]
suffix = lines[end:]

sections: OrderedDict[str, list[str]] = OrderedDict((k, []) for k in kind_order)
current = None
for line in old_block:
    if line.startswith("### "):
        label = line[4:].strip().lower()
        current = label if label in sections else None
        continue
    if current is not None:
        sections[current].append(line)

current_kind = None
with open(bodies_path, encoding="utf-8", newline="") as f:
    for raw in f.read().splitlines():
        if raw.startswith("---FRAGMENT\t"):
            current_kind = raw.split("\t", 3)[1]
            continue
        if current_kind in sections:
            sections[current_kind].append(raw)

version_lines = [f"## [{version}] - {date}"]
for kind in kind_order:
    body = sections[kind]
    while body and body[0] == "":
        body.pop(0)
    while body and body[-1] == "":
        body.pop()
    if not body:
        continue
    if version_lines[-1] != "":
        version_lines.append("")
    version_lines.append(f"### {heading_for[kind]}")
    version_lines.append("")
    version_lines.extend(body)

new_lines = []
new_lines.extend(prefix)
if new_lines and new_lines[-1] != "":
    new_lines.append("")
new_lines.append("## [Unreleased]")
new_lines.append("")
new_lines.extend(version_lines)
if suffix:
    new_lines.append("")
    new_lines.extend(suffix)

with open(out_path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(new_lines).rstrip() + "\n")
PY
  python3 - "$tmp" <<'PY'
import os, sys
with open(sys.argv[1], "rb") as f:
    os.fsync(f.fileno())
PY
  mv "$tmp" "$changelog"

  items_csv="$(awk -F '\t' '$1 == "fragment" {split($4, parts, "."); print parts[1]}' "$entries_file" | awk '!seen[$0]++' | paste -sd, -)"
  while IFS=$'\t' read -r _tag _rank _item_key _name _kind path; do
    rm -f "$path"
  done < "$entries_file"

  printf 'ASSEMBLE_RESULT=assembled\n'
  printf 'VERSION=%s\n' "$version"
  printf 'FRAGMENT_COUNT=%s\n' "$fragment_count"
  printf 'CARRIED_OVER_COUNT=%s\n' "$carried_count"
  printf 'ITEMS=%s\n' "$items_csv"
}

cmd="${1:-}"
[ -n "$cmd" ] || die_usage "missing command"
shift

case "$cmd" in
  validate)
    dir="$REPO_ROOT/$FRAGMENT_DIR"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dir) [ "$#" -ge 2 ] || die_usage "--dir requires a value"; dir="$2"; shift 2 ;;
        *) die_usage "unknown validate option: $1" ;;
      esac
    done
    validate_fragments "$dir"
    ;;
  list)
    dir="$REPO_ROOT/$FRAGMENT_DIR"
    json=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dir) [ "$#" -ge 2 ] || die_usage "--dir requires a value"; dir="$2"; shift 2 ;;
        --json) json=true; shift ;;
        *) die_usage "unknown list option: $1" ;;
      esac
    done
    list_fragments "$dir" "$json"
    ;;
  assemble)
    dir="$REPO_ROOT/$FRAGMENT_DIR"
    changelog="$REPO_ROOT/$CHANGELOG_FILE"
    version=""
    release_date="$(date +%F)"
    allow_empty=false
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --dir) [ "$#" -ge 2 ] || die_usage "--dir requires a value"; dir="$2"; shift 2 ;;
        --changelog) [ "$#" -ge 2 ] || die_usage "--changelog requires a value"; changelog="$2"; shift 2 ;;
        --version) [ "$#" -ge 2 ] || die_usage "--version requires a value"; version="$2"; shift 2 ;;
        --date) [ "$#" -ge 2 ] || die_usage "--date requires a value"; release_date="$2"; shift 2 ;;
        --allow-empty) allow_empty=true; shift ;;
        *) die_usage "unknown assemble option: $1" ;;
      esac
    done
    [ -n "$version" ] || die_usage "assemble requires --version"
    [ -f "$changelog" ] || { printf 'ERROR: changelog not found: %s\n' "$changelog" >&2; exit 1; }
    assemble_changelog "$changelog" "$dir" "$version" "$release_date" "$allow_empty"
    ;;
  --help|-h)
    usage
    ;;
  *)
    die_usage "unknown command: $cmd"
    ;;
esac
