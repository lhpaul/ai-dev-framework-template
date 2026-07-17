#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/spec-dispatch-context.sh --selected <issue-number> --items <comma-separated-issue-numbers> [--confirmed-decision-file <path>] [--json]

Build conservative spec-dispatch relationship context for Backlog spec starts.
EOF
}

selected=""
items_arg=""
confirmed_decision_file=""
json_output=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --selected)
      shift
      selected="${1:-}"
      shift
      ;;
    --items)
      shift
      items_arg="${1:-}"
      shift
      ;;
    --confirmed-decision-file)
      shift
      confirmed_decision_file="${1:-}"
      shift
      ;;
    --json)
      json_output=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if ! printf '%s\n' "$selected" | grep -Eq '^[1-9][0-9]*$'; then
  echo "--selected must be a positive issue number" >&2
  exit 64
fi

if [ -z "$items_arg" ]; then
  items_arg="$selected"
fi

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

items_file="$tmp_dir/items"
printf '%s\n' "$items_arg" \
  | tr ',' '\n' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
  | awk 'NF && !seen[$0]++ { print }' > "$items_file"

if ! grep -qx "$selected" "$items_file"; then
  printf '%s\n' "$selected" >> "$items_file"
fi

while IFS= read -r issue; do
  if ! printf '%s\n' "$issue" | grep -Eq '^[1-9][0-9]*$'; then
    echo "Invalid issue in --items: $issue" >&2
    exit 64
  fi
done < "$items_file"

issue_json_dir="$tmp_dir/issues"
mkdir -p "$issue_json_dir"

while IFS= read -r issue; do
  if ! gh issue view "$issue" --json number,title,body,comments > "$issue_json_dir/$issue.json"; then
    echo "Failed to read issue #$issue" >&2
    exit 1
  fi
done < "$items_file"

issue_text() {
  local issue="$1"
  jq -r '[.title // "", .body // "", (.comments[]?.body // empty)] | join("\n")' "$issue_json_dir/$issue.json"
}

significant_terms() {
  awk '
    BEGIN {
      split("a an and are as at be by can for from has have if in into is it its of on or that the this to was were when with without will would should could must issue issues item items spec specs plan plans implementation workflow agent agents add added update updated selected peer current target context dispatch human", stop_words)
      for (i in stop_words) stop[stop_words[i]] = 1
    }
    {
      line = tolower($0)
      gsub(/[^a-z0-9#]+/, " ", line)
      n = split(line, parts, /[[:space:]]+/)
      delete kept
      kept_count = 0
      for (i = 1; i <= n; i++) {
        term = parts[i]
        gsub(/^#+/, "", term)
        if (length(term) < 4 || stop[term]) {
          continue
        }
        kept[++kept_count] = term
        print "term:" term
      }
      for (i = 1; i < kept_count; i++) {
        print "phrase:" kept[i] " " kept[i + 1]
      }
    }
  ' | sort -u
}

issue_ref_pattern() {
  local issue="$1"
  printf '(^|[^0-9#])#%s([^0-9]|$)|(^|[^0-9#])%s([^0-9]|$)' "$issue" "$issue"
}

dependency_phrase_pattern() {
  printf 'depends on|dependent on|blocked by|requires|waiting on'
}

text_contains_dependency() {
  local text="$1" issue="$2"
  local lower sentence match issue_pattern dependency_pattern first_ref
  lower="$(printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]')"
  issue_pattern="$(issue_ref_pattern "$issue")"
  dependency_pattern="$(dependency_phrase_pattern)"
  while IFS= read -r sentence; do
    if [ -z "$sentence" ]; then
      continue
    fi
    if text_contains_negated_dependency "$sentence" "$issue"; then
      continue
    fi
    while IFS= read -r match; do
      if [ -z "$match" ]; then
        continue
      fi
      first_ref="$(printf '%s\n' "$match" | grep -Eo '#[0-9]+' | head -1 || true)"
      if [ -n "$first_ref" ] && [ "$first_ref" != "#$issue" ]; then
        continue
      fi
      return 0
    done <<EOF_MATCH
$(printf '%s\n' "$sentence" | grep -Eio "(${dependency_pattern})[^.!?]{0,120}(${issue_pattern})" || true)
EOF_MATCH
  done <<EOF
$(printf '%s\n' "$lower" | tr '\n' ' ' | awk '{ gsub(/[.!?]+/, "\n"); print }')
EOF
  return 1
}

text_contains_negated_dependency() {
  local text="$1" issue="$2"
  local lower compact issue_pattern
  lower="$(printf '%s\n' "$text" | tr '[:upper:]' '[:lower:]')"
  compact="$(printf '%s\n' "$lower" | tr '\n' ' ')"
  issue_pattern="$(issue_ref_pattern "$issue")"
  printf '%s\n' "$compact" \
    | grep -Eiq "(not|without)[^.!?]{0,120}(${issue_pattern})"
}

has_coupling_language() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' \
    | awk '
      {
        line = $0
        gsub(/[^a-z0-9]+/, " ", line)
        if (line ~ /(^| )(coupled|coupling|shared|coordinate|coordination)( |$)/ ||
            line ~ /(^| )same data( |$)/ ||
            line ~ /(^| )same schema( |$)/ ||
            line ~ /(^| )must align( |$)/ ||
            line ~ /(^| )must share( |$)/) {
          found = 1
        }
      }
      END { exit found ? 0 : 1 }
    '
}

json_array_from_lines() {
  if [ -s "$1" ]; then
    jq -R . "$1" | jq -s .
  else
    printf '[]\n'
  fi
}

selected_text_file="$tmp_dir/selected.txt"
issue_text "$selected" > "$selected_text_file"
selected_terms="$tmp_dir/selected_terms"
significant_terms < "$selected_text_file" > "$selected_terms"

relationships_file="$tmp_dir/relationships.jsonl"
: > "$relationships_file"

while IFS= read -r peer; do
  [ "$peer" = "$selected" ] && continue

  peer_text_file="$tmp_dir/peer-$peer.txt"
  issue_text "$peer" > "$peer_text_file"
  peer_terms="$tmp_dir/peer-$peer-terms"
  significant_terms < "$peer_text_file" > "$peer_terms"

  selected_text="$(cat "$selected_text_file")"
  peer_text="$(cat "$peer_text_file")"
  selected_depends_on_peer=false
  peer_depends_on_selected=false
  if text_contains_dependency "$selected_text" "$peer"; then
    selected_depends_on_peer=true
  fi
  if text_contains_dependency "$peer_text" "$selected"; then
    peer_depends_on_selected=true
  fi

  overlap_file="$tmp_dir/overlap-$peer"
  comm -12 "$selected_terms" "$peer_terms" > "$overlap_file"

  phrase_count="$(grep -c '^phrase:' "$overlap_file" || true)"
  term_count="$(grep -c '^term:' "$overlap_file" || true)"
  if [ "$selected_depends_on_peer" != "true" ] && [ "$peer_depends_on_selected" != "true" ] && [ "$phrase_count" -lt 1 ] && [ "$term_count" -lt 2 ]; then
    continue
  fi

  overlap_terms_file="$tmp_dir/overlap-$peer-terms"
  sed 's/^[^:]*://' "$overlap_file" > "$overlap_terms_file"

  evidence_file="$tmp_dir/evidence-$peer"
  : > "$evidence_file"
  outcome="Orthogonal"

  if [ "$selected_depends_on_peer" = "true" ]; then
    outcome="Dependent"
    printf 'Selected issue contains an explicit dependency phrase referencing #%s.\n' "$peer" >> "$evidence_file"
  fi
  if [ "$peer_depends_on_selected" = "true" ]; then
    outcome="Dependent"
    printf 'Peer issue #%s contains an explicit dependency phrase referencing #%s.\n' "$peer" "$selected" >> "$evidence_file"
  fi

  negated_dependency=false
  if text_contains_negated_dependency "$selected_text" "$peer"; then
    negated_dependency=true
    printf 'Selected issue explicitly negates a dependency on #%s.\n' "$peer" >> "$evidence_file"
  fi
  if text_contains_negated_dependency "$peer_text" "$selected"; then
    negated_dependency=true
    printf 'Peer issue #%s explicitly negates a dependency on #%s.\n' "$peer" "$selected" >> "$evidence_file"
  fi

  if [ "$outcome" != "Dependent" ] && {
    has_coupling_language "$selected_text" || has_coupling_language "$peer_text"
  } && [ "$negated_dependency" != "true" ]; then
    outcome="Unclear"
    printf 'Meaningful overlap plus coupling language lacks concrete dependency or independence evidence.\n' >> "$evidence_file"
  fi

  if [ ! -s "$evidence_file" ]; then
    printf 'Meaningful terminology overlap without concrete dependency evidence.\n' >> "$evidence_file"
  fi

  blocking=false
  human_action_json=null
  dispatch_instruction="Treat the relationship as orthogonal; do not add dependency context from shared terminology alone."
  if [ "$outcome" = "Dependent" ]; then
    dispatch_instruction="Include the concrete dependency evidence in the spec-dispatch context."
  elif [ "$outcome" = "Unclear" ]; then
    blocking=true
    human_action_json="$(jq -n --arg peer "$peer" --arg selected "$selected" '"Confirm whether #\($selected) depends on #\($peer), is orthogonal to it, or needs a narrower design decision before spec dispatch."')"
    dispatch_instruction="Stop before spec dispatch until a human resolves the relationship."
  fi

  overlap_json="$(json_array_from_lines "$overlap_terms_file")"
  evidence_json="$(json_array_from_lines "$evidence_file")"
  peer_title="$(jq -r '.title // ""' "$issue_json_dir/$peer.json")"

  jq -nc \
    --argjson issue "$peer" \
    --arg title "$peer_title" \
    --arg outcome "$outcome" \
    --argjson overlapTerms "$overlap_json" \
    --argjson evidence "$evidence_json" \
    --arg dispatchInstruction "$dispatch_instruction" \
    --argjson blocking "$blocking" \
    --argjson humanAction "$human_action_json" \
    '{issue: $issue, title: $title, outcome: $outcome, overlapTerms: $overlapTerms, evidence: $evidence, dispatchInstruction: $dispatchInstruction, blocking: $blocking, humanAction: $humanAction}' \
    >> "$relationships_file"
done < "$items_file"

decision_file_json="$tmp_dir/decisions-file.json"
if [ -n "$confirmed_decision_file" ] && [ -s "$confirmed_decision_file" ]; then
  jq -s --argjson selected "$selected" \
    '[.[] | select((.issue // .item_number // .number | tonumber) == $selected) | {summary: (.summary // .decision // .body // ""), source: (.source // "confirmed decision file")} | select(.summary != "")]' \
    "$confirmed_decision_file" > "$decision_file_json"
else
  printf '[]\n' > "$decision_file_json"
fi

comment_decisions_json="$tmp_dir/decisions-comments.json"
jq '
  [
    .comments[]?
    | (.body // "") as $body
	    | select($body | test("(?i)\\b(confirmed|approved|correction|clarifying|decision)\\b"))
    | {
        summary: ($body | gsub("\\s+"; " ") | .[0:240]),
        source: (.url // (.author.login // "issue comment"))
      }
  ]
' "$issue_json_dir/$selected.json" > "$comment_decisions_json"

confirmed_json="$(jq -s 'add' "$decision_file_json" "$comment_decisions_json")"
relationships_json="$(if [ -s "$relationships_file" ]; then jq -s . "$relationships_file"; else printf '[]\n'; fi)"
blocking="$(printf '%s\n' "$relationships_json" | jq 'any(.[]; .blocking == true)')"
human_actions_json="$(printf '%s\n' "$relationships_json" | jq '[.[] | select(.blocking == true) | .humanAction] | map(select(. != null)) | unique')"
decision_conflict="$(printf '%s\n' "$confirmed_json" | jq '
  def normalized: (.summary // "" | ascii_downcase);
  def says_independent: normalized | test("orthogonal|independent|unrelated|no dependency|not dependent|not blocked");
  def says_dependent: normalized | test("(depends on|dependent on|blocked by|requires|waiting on|prerequisite)[^.?!;]{0,80}#[0-9]+");
  (any(.[]; says_independent) and any(.[]; says_dependent))
')"
if [ "$decision_conflict" = "true" ]; then
  blocking=true
  human_actions_json="$(printf '%s\n' "$human_actions_json" | jq --arg selected "$selected" '. + ["Resolve conflicting confirmed decisions for #\($selected) before spec dispatch."]')"
fi
human_action="$(printf '%s\n' "$human_actions_json" | jq -r 'join(" ")')"
if [ -n "$human_action" ]; then
  human_action_json="$(jq -n --arg action "$human_action" '$action')"
else
  human_action_json=null
fi

selected_json="$(jq '{number, title, briefExcerpt: ((.body // "") | gsub("\\s+"; " ") | .[0:300])}' "$issue_json_dir/$selected.json")"

if [ "$json_output" -eq 1 ]; then
  jq -n \
    --argjson selected "$selected_json" \
    --argjson confirmedDecisions "$confirmed_json" \
    --argjson relationships "$relationships_json" \
    --argjson blocking "$blocking" \
    --argjson humanAction "$human_action_json" \
    '{selected: $selected, confirmedDecisions: $confirmedDecisions, relationships: $relationships, blocking: $blocking, humanAction: $humanAction}'
else
  printf 'Selected: #%s %s\n' "$selected" "$(jq -r '.title // ""' "$issue_json_dir/$selected.json")"
  printf 'Blocking: %s\n' "$blocking"
  printf '%s\n' "$relationships_json" | jq -r '.[] | "- #\(.issue) \(.outcome): \(.dispatchInstruction)"'
  if [ -n "$human_action" ]; then
    printf 'Human action: %s\n' "$human_action"
  fi
fi
