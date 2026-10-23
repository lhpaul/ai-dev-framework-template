# shellcheck shell=bash
# Shared original #1946 fixture expressions; each invocation belongs to one part.
_ticket_body_1946=$'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n<table>\n<tr><td>\n**🎫 Ticket compliance analysis ✅**\n**[42](https://example.test/issues/42) - Fully compliant**\nCompliant requirements:\n- All required behavior is implemented.\n</td></tr>\n</table>\n'
readiness_fixture_1946() {
  local name="$1" expected="$2" body="$3" output expected_reason="${4:-}" expected_classifier="${5:-escalate}"
  READINESS_MATRIX_INDEX=$((READINESS_MATRIX_INDEX + 1))
  READINESS_CASE_SELECTED=0
  if [ "$(((READINESS_MATRIX_INDEX - 1) % 4 + 1))" -ne "$READINESS_MATRIX_PART" ]; then
    return 0
  fi
  READINESS_CASE_SELECTED=1
  MOCK_ISSUE_COMMENTS="$(jq -nc --arg body "$body" '[{user:{login:"github-actions[bot]"},created_at:"2026-01-08T00:00:00Z",id:923,body:$body}]')"
  if [ -n "${READINESS_MATRIX_RECORD_FILE:-}" ]; then
    # shellcheck disable=SC2154 # Provided by the shared readiness fixture or its caller.
    READINESS_RECORD_INDEX="$READINESS_MATRIX_INDEX" READINESS_RECORD_NAME="$name" \
    READINESS_RECORD_EXPECTED="$expected" READINESS_RECORD_REASON="$expected_reason" \
    READINESS_RECORD_CLASSIFIER="$expected_classifier" READINESS_RECORD_BODY="$body" \
    HELPER="$SCRIPT_DIR/lib/readiness-matrix-record.py" run_helper_platform "$_codex_config" >/dev/null
    return 0
  fi
  output="$(run_helper_platform "$_codex_config")"
  run_test "1946_${name}_readiness" "$expected" "$(field "$output" RESULT)"
  if [ -n "$expected_reason" ]; then
    run_test "1946_${name}_reason" "$expected_reason" "$(field "$output" REASON)"
    run_test "1946_${name}_classifier" "$expected_classifier" "$(printf '%s' "$body" | bash "$REPO_ROOT/scripts/development-workflow/apply-readiness-labels.sh" --classify-pr-agent)"
  fi
  if [ "$expected" = refused ]; then
    run_test "1946_${name}_no_readiness_write" "0" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
  fi
}
readiness_fixture_1946 complete labeled "$_ticket_body_1946"
readiness_fixture_1946 partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"
readiness_fixture_1946 human_verification refused "${_ticket_body_1946/Fully compliant/PR Code Verified}"
readiness_fixture_1946 truncated refused "${_ticket_body_1946%</table>*}"
readiness_fixture_1946 unknown refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n**Ticket compliance analysis ✅**\n'
readiness_fixture_1946 hidden_clean refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n<!-- pr-agent-review-state:v1\n{"body":"No major issues detected"}\n-->\n'
readiness_fixture_1946 hidden_blocker labeled "${_ticket_body_1946}"$'<!-- pr-agent-review-state:v1\n{"body":"Recommended focus areas for review\\n<strong>Critical</strong>"}\n-->\n'
readiness_fixture_1946 hidden_current_head refused $'## PR Reviewer Guide\ncommit: stalehead\nNo major issues detected\n<!-- pr-agent-review-state:v1\n{"last_seen_head_sha":"'"$HEAD"$'"}\n-->\n'
readiness_fixture_1946 visible_current_marker labeled "${_ticket_body_1946/commit: $HEAD/#### (Review updated until commit https:\/\/github.com\/owner\/repo\/commit\/$HEAD)}"
readiness_fixture_1946 empty_markdown_analysis refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n\n---\n'
readiness_fixture_1946 malformed_second_ticket refused "${_ticket_body_1946/<\/td>/$'**[43](url) - Not compliant*\n</td>'}"
readiness_fixture_1946 legacy_truncated refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n<table>\n<tr><td>Recommended focus areas for review\n<strong>Possible Issue</strong>\n'
readiness_fixture_1946 tableless_unclosed_details refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<details><summary><strong>Possible Issue</strong></summary>\nAdvisory text\n'
readiness_fixture_1946 indented_malformed_ticket refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Done.\n  **[43](url) - Not compliant*\nNon-compliant requirements:\n- Missing.\n'
readiness_fixture_1946 blank_focus_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong> </strong><br>Unknown issue.\n'
readiness_fixture_1946 code_example_html labeled "${_ticket_body_1946}"$'\n\n```html\n<table><tr><td>Example only.\n```\n'
readiness_fixture_1946 code_example_not_verdict refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n```markdown\nNo major issues detected\n```\n'
readiness_fixture_1946 inline_code_html labeled "${_ticket_body_1946}"$'\nInline example: `<table><td>` is code, not layout.\n'
# #1959: Luis authorizes simple one-line code only; ambiguity escalates.
readiness_fixture_1946 markdown_code_inline_head labeled "${_ticket_body_1946}"$'\nRead `git show <head>:CHANGELOG.md`.\n'
readiness_fixture_1946 markdown_code_outside_blocker refused "${_ticket_body_1946}"$'\n`<head>`\n### Recommended focus areas for review\n<strong>Critical</strong>\n\n' blocking-findings needs_fixes
readiness_fixture_1946 markdown_code_raw_head refused "${_ticket_body_1946}"$'\nRead <head> outside code.\n' reviewer-check-absent escalate
readiness_fixture_1946 markdown_code_longer_fence labeled "${_ticket_body_1946}"$'\n````html\n```\n<head>\n`````\n\n'
readiness_fixture_1946 markdown_code_tilde_fence labeled "${_ticket_body_1946}"$'\n~~~~html\n<head>\n~~~~\n\n'
readiness_fixture_1946 markdown_code_unclosed_fence refused "${_ticket_body_1946}"$'\n```html\n<head>\n' reviewer-check-absent escalate
readiness_fixture_1946 markdown_code_invalid_fence refused "${_ticket_body_1946}"$'\n```invalid`info\n<strong>Critical</strong>\n```\n' reviewer-check-absent escalate
readiness_fixture_1946 markdown_code_indented_fence refused "${_ticket_body_1946}"$'\n    ```html\n<strong>Critical</strong>\n```\n' reviewer-check-absent escalate
readiness_fixture_1946 markdown_code_double_backtick refused "${_ticket_body_1946}"$'\nRead ``git `<head>`:CHANGELOG.md``.\n' reviewer-check-absent escalate
readiness_fixture_1946 markdown_code_comment_example labeled "${_ticket_body_1946}"$'\nRead `<!--`.\n'
for _boundary_1959 in $'\n' $'\n\n' $'\r\n' $'\n---\n' $'\n***\n' $'\n- item\n' $'\n1. item\n' $'\n> quote\n' $'\n### Heading\n' $'\n~~~text\nsample\n~~~\n' $'\n```text\nsample\n```\n' $'\n<span>\n' $'\f' $'\v' $'\u2028'; do
  for _ticks_1959 in '`' '``'; do
    readiness_fixture_1946 conservative_boundary refused "${_ticket_body_1946}"$'\n'"Unmatched ${_ticks_1959} example.${_boundary_1959}"$'Recommended focus areas for review\n<strong>Critical</strong>'$'\n'"Later ${_ticks_1959} prose." reviewer-check-absent escalate
    readiness_fixture_1946 conservative_boundary refused "${_ticket_body_1946}"$'\n'"Unmatched ${_ticks_1959} example.${_boundary_1959}"'<span title="a" title="b">bad</span>'$'\n'"Later ${_ticks_1959} prose." reviewer-check-absent escalate
  done
done
for _tag_1959 in div pre style script textarea blockquote span custom details summary table td; do
  # #1967: quoted HTML is literal only in the admitted table context. Real
  # malformed HTML and every unsupported raw wrapper retain refusal below.
  _html_result_1967=refused
  _html_reason_1967=reviewer-check-absent
  _html_classifier_1967=escalate
  if [ "$_tag_1959" = table ]; then
    _html_result_1967=labeled
    _html_reason_1967=gate-passed
    _html_classifier_1967=clean
  fi
  readiness_fixture_1946 conservative_html "$_html_result_1967" "${_ticket_body_1946}"$'\n'"<${_tag_1959}>"$'\n`<strong>Critical</strong>`\n'"</${_tag_1959}>" "$_html_reason_1967" "$_html_classifier_1967"
  if [ "$_tag_1959" = table ] && [ "$READINESS_CASE_SELECTED" -eq 1 ]; then
    run_test "1946_conservative_html_readiness_write" "1" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
  fi
  readiness_fixture_1946 conservative_html_same_line "$_html_result_1967" "${_ticket_body_1946}"$'\n'"<${_tag_1959}>"'`<span title="a" title="b">bad</span>`'"</${_tag_1959}>" "$_html_reason_1967" "$_html_classifier_1967"
  if [ "$_tag_1959" = table ] && [ "$READINESS_CASE_SELECTED" -eq 1 ]; then
    run_test "1946_conservative_html_same_line_readiness_write" "1" "$(grep -c 'add-label ready-for-human-review' "$_LABEL_LOG" || true)"
  fi
done
unset _boundary_1959 _ticks_1959 _tag_1959 _html_result_1967 _html_reason_1967 _html_classifier_1967
readiness_fixture_1946 conservative_attribute refused "${_ticket_body_1946}"$'\n<span title="`">Text</span>\n' reviewer-check-absent escalate
readiness_fixture_1946 conservative_comment labeled "${_ticket_body_1946}"$'\n<!-- `Critical` -->\n'
readiness_fixture_1946 conservative_unmatched refused "${_ticket_body_1946}"$'\nUnmatched ` example.\n' reviewer-check-absent escalate

readiness_fixture_1946 inline_code_not_verdict refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n`No major issues detected` is an example.\n'
readiness_fixture_1946 mixed_empty_focus_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n<strong></strong><br>Unknown issue.\n'
readiness_fixture_1946 mixed_unclosed_focus_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n<strong>Critical\n'
readiness_fixture_1946 mixed_truncated_html_tag refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n<strong\n'
readiness_fixture_1946 mixed_unclosed_markdown_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n**Critical\n'
readiness_fixture_1946 encoded_blocker_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n<strong>Security&#32;Concern</strong>\n'
readiness_fixture_1946 encoded_empty_label refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n<strong>&nbsp;</strong>\n'
readiness_fixture_1946 encoded_empty_analysis refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n&nbsp;\n'
readiness_fixture_1946 prose_marker_not_verdict refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\nThe phrase No major issues detected is an example.\n'
readiness_fixture_1946 prose_ticket_not_section labeled $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>The phrase Ticket compliance analysis names another format.\n'
readiness_fixture_1946 quoted_attribute_blocker refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong title=">">Security Concern</strong>\n'
readiness_fixture_1946 colon_focus_blocker refused "${_ticket_body_1946}"$'### Key issues to review:\n<strong>Critical</strong>\n'
readiness_fixture_1946 duplicate_security_sections refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>No security concerns identified.</td></tr>\n<tr><td><strong>Security concerns</strong><br>Unsafe input execution.</td></tr>\n'
readiness_fixture_1946 invalid_fence_closer refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n```markdown\n```example\nNo major issues detected\n'
readiness_fixture_1946 valid_then_unknown_focus refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Possible Issue</strong><br>Advisory text.\n### Review Key issues to review\n<strong>Critical</strong>\n'
readiness_fixture_1946 same_line_html_blocker refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n<strong>Key issues to review</strong><br><strong>Critical</strong>\n<strong>Possible Issue</strong>\n'
readiness_fixture_1946 nonbreaking_space_blocker refused $'## PR Reviewer Guide\ncommit: '"$HEAD"$'\n### Recommended focus areas for review\n<strong>Security&nbsp;Concern</strong>\n'
readiness_fixture_1946 unparsed_verification_heading refused "${_ticket_body_1946}"$'Requires further human verification\n- Authorization must be checked manually.\n'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_ISSUE_COMMENTS='[]'
readiness_fixture_1946 extra_rendered_human refused "${_ticket_body_1946}"$'<strong>Requires further human verification</strong><br>\n- Verify authorization manually.\n'
readiness_fixture_1946 extra_malformed_second_section refused "${_ticket_body_1946}"$'**Ticket compliance analysis ❌*\n**[43](url) - Not compliant**\nNon-compliant requirements:\n- Missing.\n'
readiness_fixture_1946 extra_partial_bold_focus refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Recommended focus areas for review**\n<strong>Critical</strong>\n'
readiness_fixture_1946 extra_partial_human_ticket refused "commit: $HEAD"$'\n**Ticket compliance analysis 🔶**\n**[42](url) - Partially compliant**\nNon-compliant requirements:\n- Missing.\n**[43](url) - PR Code Verified**\nCompliant requirements:\n- Implemented; human verification pending.\n'
readiness_fixture_1946 extra2_unreadable_legacy_focus refused "commit: $HEAD"$'\n### Recommended focus areas for review\nNo parseable labels\n' reviewer-check-absent
readiness_fixture_1946 extra2_empty_security refused "${_ticket_body_1946}"$'<strong>Security concerns</strong><br>\n' reviewer-check-absent
readiness_fixture_1946 extra2_blank_security refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br><span> &nbsp; </span></td></tr>\n' reviewer-check-absent
readiness_fixture_1946 extra2_markup_only_security refused "${_ticket_body_1946}"$'<strong>Security concerns</strong><br>\n- ** **\n' reviewer-check-absent
readiness_fixture_1946 extra2_partial_empty_security refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Security concerns</strong><br>\n' reviewer-check-absent
readiness_fixture_1946 extra2_security_fix_unreadable_focus refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>Unsafe input execution.</td></tr>\n### Recommended focus areas for review\nNo parseable labels\n' reviewer-check-absent
# Closed-set policy: every verdict branch rejects unknown values (#1946).
readiness_fixture_1946 closed_security_negative labeled "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>None</td></tr>\n'
readiness_fixture_1946 closed_security_finding refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>Yes</td></tr>\n'
readiness_fixture_1946 closed_security_unknown refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_security_unlisted refused "${_ticket_body_1946}"$'<tr><td><strong>Security concerns</strong><br>Unrecognized vulnerability status</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_security_unknown_after_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Security concerns</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_focus_negative labeled "${_ticket_body_1946}"$'### Key issues to review\n<strong>No major issues detected</strong>\n'
readiness_fixture_1946 closed_focus_advisory labeled "${_ticket_body_1946}"$'### Key issues to review\n<strong>Possible Issue</strong>\n'
readiness_fixture_1946 closed_focus_finding refused "${_ticket_body_1946}"$'### Key issues to review\n<strong>Critical</strong>\n'
readiness_fixture_1946 closed_focus_unknown refused "${_ticket_body_1946}"$'### Key issues to review\n<strong>Unknown</strong>\n' reviewer-check-absent
readiness_fixture_1946 closed_focus_unlisted refused "${_ticket_body_1946}"$'### Key issues to review\n<strong>Unexpected Label</strong>\n' reviewer-check-absent
readiness_fixture_1946 closed_focus_mixed_unknown refused "${_ticket_body_1946}"$'### Key issues to review\n<strong>Critical</strong>\n<strong>Unknown</strong>\n' reviewer-check-absent
readiness_fixture_1946 closed_compliance_unknown refused "${_ticket_body_1946/Fully compliant/Unknown}" reviewer-check-absent
readiness_fixture_1946 closed_compliance_unlisted refused "${_ticket_body_1946/Fully compliant/Newly approved}" reviewer-check-absent
readiness_fixture_1946 closed_analysis_unknown refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\nUnknown\n' reviewer-check-absent
readiness_fixture_1946 closed_analysis_bullet_unknown refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Unknown\n' reviewer-check-absent
readiness_fixture_1946 closed_analysis_unknown_heading refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Implemented.\nUnknown requirements:\n- Not known.\n' reviewer-check-absent
readiness_fixture_1946 closed_verification_negative labeled "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>None</td></tr>\n'
readiness_fixture_1946 closed_verification_request refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_verification_unknown refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_verification_unlisted refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>Unexpected</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_verification_after_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 closed_legacy_unknown refused "commit: $HEAD"$'\n## PR Reviewer Guide\nReview complete: Unknown\n' reviewer-check-absent
readiness_fixture_1946 closed_bare_security_unknown refused "${_ticket_body_1946}"$'Security concerns: Unknown\n' reviewer-check-absent
readiness_fixture_1946 closed_malformed_verification_unknown refused "${_ticket_body_1946}"$'### Verification status Unknown\n' reviewer-check-absent
readiness_fixture_1946 scoped_human_no_colon refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Requires further human verification\n' reviewer-check-absent
readiness_fixture_1946 scoped_human_colon refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Requires further human verification:\n' reviewer-check-absent
readiness_fixture_1946 scoped_human_rendered refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Fully compliant**\nCompliant requirements:\n- Requires&nbsp;further <em>human</em> verification\n' reviewer-check-absent
readiness_fixture_1946 scoped_partial_human_no_colon refused "commit: $HEAD"$'\n## PR Reviewer Guide\n**Ticket compliance analysis ✅**\n**[42](url) - Partially compliant**\nCompliant requirements:\n- Requires further human verification\n' reviewer-check-absent
# Raw HTML attributes remain opaque while Markdown code is masked.
readiness_fixture_1946 raw_structure_h1_full refused "${_ticket_body_1946}"$'<h1 data-note=pre`bad`post>Reviewer notes</h1>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h1_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1 data-note=pre`bad`post>Reviewer notes</h1>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h2_full refused "${_ticket_body_1946}"$'<h2 data-note=pre`bad`post>Reviewer notes</h2>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h2_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h2 data-note=pre`bad`post>Reviewer notes</h2>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h3_full refused "${_ticket_body_1946}"$'<h3 data-note=pre`bad`post>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h3_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 data-note=pre`bad`post>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h4_full refused "${_ticket_body_1946}"$'<h4 data-note=pre`bad`post>Reviewer notes</h4>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h4_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h4 data-note=pre`bad`post>Reviewer notes</h4>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h5_full refused "${_ticket_body_1946}"$'<h5 data-note=pre`bad`post>Reviewer notes</h5>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h5_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h5 data-note=pre`bad`post>Reviewer notes</h5>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h6_full refused "${_ticket_body_1946}"$'<h6 data-note=pre`bad`post>Reviewer notes</h6>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_h6_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6 data-note=pre`bad`post>Reviewer notes</h6>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_strong_full refused "${_ticket_body_1946}"$'<strong data-note=pre`bad`post>Reviewer notes</strong>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_strong_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong data-note=pre`bad`post>Reviewer notes</strong>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_b_full refused "${_ticket_body_1946}"$'<b data-note=pre`bad`post>Reviewer notes</b>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_b_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b data-note=pre`bad`post>Reviewer notes</b>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_span_full refused "${_ticket_body_1946}"$'<span data-note=pre`bad`post>Reviewer notes</span>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_span_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span data-note=pre`bad`post>Reviewer notes</span>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_p_full refused "${_ticket_body_1946}"$'<p data-note=pre`bad`post>Reviewer notes</p>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_p_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<p data-note=pre`bad`post>Reviewer notes</p>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_div_full refused "${_ticket_body_1946}"$'<div data-note=pre`bad`post>Reviewer notes</div>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_div_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div data-note=pre`bad`post>Reviewer notes</div>\n' reviewer-check-absent
readiness_fixture_1946 raw_structure_fenced_bad_attribute_full labeled "${_ticket_body_1946}"$'```html\n<h3 data-note=pre`bad`post>Reviewer notes</h3>\n```\n'
readiness_fixture_1946 raw_structure_fenced_bad_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'```html\n<h3 data-note=pre`bad`post>Reviewer notes</h3>\n```\n' blocking-findings needs_fixes
readiness_fixture_1946 raw_structure_inline_bad_attribute_full refused "${_ticket_body_1946}"$'``<h3 data-note=pre`bad`post>Reviewer notes</h3>``\n' reviewer-check-absent escalate
readiness_fixture_1946 raw_structure_inline_bad_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'``<h3 data-note=pre`bad`post>Reviewer notes</h3>``\n' reviewer-check-absent escalate
readiness_fixture_1946 raw_structure_fenced_unclosed_full labeled "${_ticket_body_1946}"$'```html\n<h3>Reviewer notes\n```\n'
readiness_fixture_1946 raw_structure_fenced_unclosed_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'```html\n<h3>Reviewer notes\n```\n' blocking-findings needs_fixes
readiness_fixture_1946 raw_structure_inline_unclosed_full labeled "${_ticket_body_1946}"$'\n`<h3>Reviewer notes`\n'
readiness_fixture_1946 raw_structure_inline_unclosed_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'\n`<h3>Reviewer notes`\n' blocking-findings needs_fixes
readiness_fixture_1946 raw_structure_quoted_backticks refused "${_ticket_body_1946}"$'<h3 data-note="pre`bad`post">Reviewer notes</h3>\n' reviewer-check-absent escalate
readiness_fixture_1946 raw_structure_quoted_spaced_literal labeled "${_ticket_body_1946}"$'<h3 title="< h3">Reviewer notes</h3>\n'
readiness_fixture_1946 raw_structure_opaque_history labeled "${_ticket_body_1946}"$'<!-- <h3 data-note=pre`bad`post>old malformed sample -->\n'
readiness_fixture_1946 raw_structure_opaque_spaced_literal labeled "${_ticket_body_1946}"$'<!-- < h3>old malformed sample -->\n'
readiness_fixture_1946 raw_structure_complete_fenced labeled "${_ticket_body_1946}"$'```html\n<h3>Recommended focus areas for review</h3><strong>Critical</strong>\n```\n'
readiness_fixture_1946 raw_structure_complete_inline labeled "${_ticket_body_1946}"$'\n`<h3>Recommended focus areas for review</h3><strong>Critical</strong>`\n'
readiness_fixture_1946 raw_structure_ordinary_inline labeled "${_ticket_body_1946}"$'\nUse `known_helper()` for this operation.\n'
# Malformed HTML headers/children cannot hide behind compliant evidence.
readiness_fixture_1946 html_structure_unknown_decl_full refused "${_ticket_body_1946}"$'<h3><![invalid[header]]></h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unknown_decl_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><![invalid[header]]></h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bogus_comment_full refused "${_ticket_body_1946}"$'<h3><!bogus>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bogus_comment_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><!bogus>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_doctype_inside_full refused "${_ticket_body_1946}"$'<h3><!DOCTYPE html>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_doctype_inside_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><!DOCTYPE html>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_processing_instruction_full refused "${_ticket_body_1946}"$'<h3><?unknown?>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_processing_instruction_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><?unknown?>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h1_full refused "${_ticket_body_1946}"$'<h1>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h1_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h2_full refused "${_ticket_body_1946}"$'<h2>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h2_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h2>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h3_full refused "${_ticket_body_1946}"$'<h3>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h3_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h4_full refused "${_ticket_body_1946}"$'<h4>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h4_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h4>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h5_full refused "${_ticket_body_1946}"$'<h5>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h5_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h5>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h6_full refused "${_ticket_body_1946}"$'<h6>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_h6_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_strong_full refused "${_ticket_body_1946}"$'<strong>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_strong_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_b_full refused "${_ticket_body_1946}"$'<b>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_b_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_em_full refused "${_ticket_body_1946}"$'<em>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_em_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<em>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_span_full refused "${_ticket_body_1946}"$'<span>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_span_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_div_full refused "${_ticket_body_1946}"$'<div>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_div_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_summary_full refused "${_ticket_body_1946}"$'<summary>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_summary_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<summary>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_header_full refused "${_ticket_body_1946}"$'<header>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_header_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<header>Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_prefixed_h3_full refused "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_prefixed_h3_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Custom Recommended focus areas for review<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_mismatched_full refused "${_ticket_body_1946}"$'<h3>Reviewer notes</h4>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_mismatched_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Reviewer notes</h4>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_crossed_full refused "${_ticket_body_1946}"$'<h3><strong>Reviewer notes</h3></strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_crossed_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><strong>Reviewer notes</h3></strong>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_child_full refused "${_ticket_body_1946}"$'<h3><a href="url">Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unclosed_child_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><a href="url">Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_orphan_close_full refused "${_ticket_body_1946}"$'</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_orphan_close_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_self_closed_full refused "${_ticket_body_1946}"$'<h3/>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_self_closed_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3/>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_self_close_full refused "${_ticket_body_1946}"$'<h3/ >\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_self_close_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3/ >\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_attribute_full refused "${_ticket_body_1946}"$'<h3 data-note=<oops>>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 data-note=<oops>>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_missing_attribute_value_full refused "${_ticket_body_1946}"$'<h3 data-note=>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_missing_attribute_value_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 data-note=>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unterminated_attribute_full refused "${_ticket_body_1946}"$'<h3 data-note="unterminated>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_unterminated_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 data-note="unterminated>Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_duplicate_attribute_full refused "${_ticket_body_1946}"$'<h3 class="a" class="b">Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_duplicate_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="a" class="b">Reviewer notes</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_end_attribute_full refused "${_ticket_body_1946}"$'<h3>Reviewer notes</h3 extra>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_end_attribute_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Reviewer notes</h3 extra>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_end_slash_full refused "${_ticket_body_1946}"$'<h3>Reviewer notes</h3/>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_bad_end_slash_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Reviewer notes</h3/>\n' reviewer-check-absent
readiness_fixture_1946 html_structure_spaced_open_full refused "${_ticket_body_1946}"$'< h3>Reviewer notes\n' reviewer-check-absent
readiness_fixture_1946 html_structure_spaced_open_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'< h3>Reviewer notes\n' reviewer-check-absent
readiness_fixture_1946 html_structure_spaced_slash_full refused "${_ticket_body_1946}"$'< /h3>Reviewer notes\n' reviewer-check-absent
readiness_fixture_1946 html_structure_spaced_slash_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'< /h3>Reviewer notes\n' reviewer-check-absent
readiness_fixture_1946 html_structure_truncated_open_full refused "${_ticket_body_1946}"$'<h3\n' reviewer-check-absent
readiness_fixture_1946 html_structure_truncated_open_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3\n' reviewer-check-absent
readiness_fixture_1946 html_structure_truncated_end_full refused "${_ticket_body_1946}"$'<h3>Reviewer notes</h3\n' reviewer-check-absent
readiness_fixture_1946 html_structure_truncated_end_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Reviewer notes</h3\n' reviewer-check-absent
readiness_fixture_1946 html_structure_complete_h1 labeled "${_ticket_body_1946}"$'<h1>Reviewer notes</h1>\n'
readiness_fixture_1946 html_structure_complete_h6 labeled "${_ticket_body_1946}"$'<h6><span>Reviewer notes</span></h6>\n'
readiness_fixture_1946 html_structure_valid_inline_child labeled "${_ticket_body_1946}"$'<h3><a href="url" title="notes">Reviewer notes</a></h3>\n'
readiness_fixture_1946 html_structure_valid_boolean_attribute labeled "${_ticket_body_1946}"$'<h3 hidden>Reviewer notes</h3>\n'
readiness_fixture_1946 html_structure_valid_quoted_gt labeled "${_ticket_body_1946}"$'<h3 title=">">Reviewer notes</h3>\n'
readiness_fixture_1946 html_structure_valid_voids labeled "${_ticket_body_1946}"$'<h3>Reviewer notes<br><img src="x" /></h3><hr/>\n'
readiness_fixture_1946 html_structure_closed_focus refused "${_ticket_body_1946}"$'<h3>Recommended focus areas for review</h3><strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_structure_escaped_literal labeled "${_ticket_body_1946}"$'&lt; h3&gt; is a literal example.\n'
readiness_fixture_1946 html_structure_hidden labeled "${_ticket_body_1946}"$'<!-- <h3>Reviewer notes -->\n'
readiness_fixture_1946 html_structure_fenced labeled "${_ticket_body_1946}"$'```html\n<h3>Reviewer notes\n```\n'
# Hard focus blockers override compliant tickets, even with heading prefixes.
readiness_fixture_1946 focus_hard_h3_bare_full refused "${_ticket_body_1946}"$'<h3>Recommended focus areas for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h3_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Recommended focus areas for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h3_prefix_full refused "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h3_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Custom Recommended focus areas for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_strong_bare_full refused "${_ticket_body_1946}"$'<strong>Recommended focus areas for review</strong>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_strong_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Recommended focus areas for review</strong>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_strong_prefix_full refused "${_ticket_body_1946}"$'<strong>Custom Recommended focus areas for review</strong>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_strong_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Custom Recommended focus areas for review</strong>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h1_bare_full refused "${_ticket_body_1946}"$'<h1>Recommended focus areas for review</h1>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h1_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Recommended focus areas for review</h1>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h1_prefix_full refused "${_ticket_body_1946}"$'<h1>Custom Recommended focus areas for review</h1>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h1_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Custom Recommended focus areas for review</h1>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h6_bare_full refused "${_ticket_body_1946}"$'<h6>Recommended focus areas for review</h6>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h6_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Recommended focus areas for review</h6>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h6_prefix_full refused "${_ticket_body_1946}"$'<h6>Custom Recommended focus areas for review</h6>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_h6_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Custom Recommended focus areas for review</h6>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_b_bare_full refused "${_ticket_body_1946}"$'<b>Recommended focus areas for review</b>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_b_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Recommended focus areas for review</b>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_b_prefix_full refused "${_ticket_body_1946}"$'<b>Custom Recommended focus areas for review</b>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_b_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Custom Recommended focus areas for review</b>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_span_bare_full refused "${_ticket_body_1946}"$'<span>Recommended focus areas for review</span>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_span_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Recommended focus areas for review</span>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_span_prefix_full refused "${_ticket_body_1946}"$'<span>Custom Recommended focus areas for review</span>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_span_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Custom Recommended focus areas for review</span>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_div_bare_full refused "${_ticket_body_1946}"$'<div>Recommended focus areas for review</div>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_div_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Recommended focus areas for review</div>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_div_prefix_full refused "${_ticket_body_1946}"$'<div>Custom Recommended focus areas for review</div>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_div_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Custom Recommended focus areas for review</div>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_attributes_bare_full refused "${_ticket_body_1946}"$'<h3 class="focus">Recommended focus areas for review:</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_attributes_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="focus">Recommended focus areas for review:</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_attributes_prefix_full refused "${_ticket_body_1946}"$'<h3 class="focus">Custom Recommended focus areas for review:</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_attributes_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="focus">Custom Recommended focus areas for review:</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_nested_bare_full refused "${_ticket_body_1946}"$'<h3><strong>Recommended focus areas for review</strong></h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_nested_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><strong>Recommended focus areas for review</strong></h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_nested_prefix_full refused "${_ticket_body_1946}"$'<h3>Custom <strong>Recommended focus areas for review</strong></h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_nested_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Custom <strong>Recommended focus areas for review</strong></h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_fragmented_bare_full refused "${_ticket_body_1946}"$'<h3>Recommended focus <em>areas</em> for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_fragmented_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Recommended focus <em>areas</em> for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_fragmented_prefix_full refused "${_ticket_body_1946}"$'<h3>Custom Recommended focus <em>areas</em> for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_fragmented_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Custom Recommended focus <em>areas</em> for review</h3>\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_markdown_bare_full refused "${_ticket_body_1946}"$'### Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_markdown_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_markdown_prefix_full refused "${_ticket_body_1946}"$'### Custom Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_markdown_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### Custom Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_bold_bare_full refused "${_ticket_body_1946}"$'**Recommended focus areas for review**\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_bold_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Recommended focus areas for review**\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_bold_prefix_full refused "${_ticket_body_1946}"$'**Custom Recommended focus areas for review**\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_bold_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Custom Recommended focus areas for review**\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_plain_bare_full refused "${_ticket_body_1946}"$'Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_plain_bare_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_plain_prefix_full refused "${_ticket_body_1946}"$'Custom Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_plain_prefix_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Custom Recommended focus areas for review\n<strong>Critical</strong>\n' blocking-findings needs_fixes
readiness_fixture_1946 focus_hard_unknown refused "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review</h3>\n<strong>Unknown</strong>\n' reviewer-check-absent
readiness_fixture_1946 focus_hard_mixed_unknown refused "${_ticket_body_1946}"$'<h3>Recommended focus areas for review</h3>\n<strong>Critical</strong>\n<strong>Unknown</strong>\n' reviewer-check-absent
readiness_fixture_1946 focus_hard_advisory labeled "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review</h3>\n<strong>Possible Issue</strong>\n'
readiness_fixture_1946 focus_hard_negative labeled "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review</h3>\n<strong>No major issues detected</strong>\n'
readiness_fixture_1946 focus_hard_empty refused "${_ticket_body_1946}"$'<h3>Custom Recommended focus areas for review</h3>\n' reviewer-check-absent
readiness_fixture_1946 focus_hard_duplicate refused "${_ticket_body_1946}"$'<h3>Recommended focus areas for review</h3>\n<strong>Possible Issue</strong>\n<h3>Custom Recommended focus areas for review</h3>\n<strong>Critical</strong>\n' reviewer-check-absent
readiness_fixture_1946 focus_hard_wrapper_duplicate refused "${_ticket_body_1946}"$'<div><h3>Recommended focus areas for review</h3><strong>Critical</strong><h3>Recommended focus areas for review</h3></div>\n' reviewer-check-absent
readiness_fixture_1946 focus_hard_hidden labeled "${_ticket_body_1946}"$'<!-- <h3>Recommended focus areas for review</h3><strong>Critical</strong> -->\n'
readiness_fixture_1946 focus_hard_code labeled "${_ticket_body_1946}"$'```html\n<h3>Recommended focus areas for review</h3><strong>Critical</strong>\n```\n'
# HTML security headings use the same explicit value lists (#1946).
readiness_fixture_1946 html_security_h1_negative_full labeled "${_ticket_body_1946}"$'<h1>Security concerns</h1><p>None</p>\n'
readiness_fixture_1946 html_security_h1_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Security concerns</h1><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h1_finding_full refused "${_ticket_body_1946}"$'<h1>Security concerns</h1><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h1_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Security concerns</h1><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h1_unknown_full refused "${_ticket_body_1946}"$'<h1>Security concerns</h1><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h1_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Security concerns</h1><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h2_negative_full labeled "${_ticket_body_1946}"$'<h2>Security concerns</h2><p>None</p>\n'
readiness_fixture_1946 html_security_h2_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h2>Security concerns</h2><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h2_finding_full refused "${_ticket_body_1946}"$'<h2>Security concerns</h2><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h2_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h2>Security concerns</h2><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h2_unknown_full refused "${_ticket_body_1946}"$'<h2>Security concerns</h2><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h2_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h2>Security concerns</h2><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h3_negative_full labeled "${_ticket_body_1946}"$'<h3>Security concerns</h3><p>None</p>\n'
readiness_fixture_1946 html_security_h3_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Security concerns</h3><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h3_finding_full refused "${_ticket_body_1946}"$'<h3>Security concerns</h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h3_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Security concerns</h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h3_unknown_full refused "${_ticket_body_1946}"$'<h3>Security concerns</h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h3_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Security concerns</h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h4_negative_full labeled "${_ticket_body_1946}"$'<h4>Security concerns</h4><p>None</p>\n'
readiness_fixture_1946 html_security_h4_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h4>Security concerns</h4><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h4_finding_full refused "${_ticket_body_1946}"$'<h4>Security concerns</h4><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h4_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h4>Security concerns</h4><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h4_unknown_full refused "${_ticket_body_1946}"$'<h4>Security concerns</h4><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h4_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h4>Security concerns</h4><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h5_negative_full labeled "${_ticket_body_1946}"$'<h5>Security concerns</h5><p>None</p>\n'
readiness_fixture_1946 html_security_h5_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h5>Security concerns</h5><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h5_finding_full refused "${_ticket_body_1946}"$'<h5>Security concerns</h5><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h5_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h5>Security concerns</h5><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h5_unknown_full refused "${_ticket_body_1946}"$'<h5>Security concerns</h5><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h5_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h5>Security concerns</h5><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h6_negative_full labeled "${_ticket_body_1946}"$'<h6>Security concerns</h6><p>None</p>\n'
readiness_fixture_1946 html_security_h6_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Security concerns</h6><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h6_finding_full refused "${_ticket_body_1946}"$'<h6>Security concerns</h6><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h6_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Security concerns</h6><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_h6_unknown_full refused "${_ticket_body_1946}"$'<h6>Security concerns</h6><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_h6_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Security concerns</h6><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_strong_negative_full labeled "${_ticket_body_1946}"$'<strong>Security concerns</strong><p>None</p>\n'
readiness_fixture_1946 html_security_strong_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Security concerns</strong><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_strong_finding_full refused "${_ticket_body_1946}"$'<strong>Security concerns</strong><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_strong_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Security concerns</strong><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_strong_unknown_full refused "${_ticket_body_1946}"$'<strong>Security concerns</strong><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_strong_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Security concerns</strong><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_b_negative_full labeled "${_ticket_body_1946}"$'<b>Security concerns</b><p>None</p>\n'
readiness_fixture_1946 html_security_b_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Security concerns</b><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_b_finding_full refused "${_ticket_body_1946}"$'<b>Security concerns</b><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_b_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Security concerns</b><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_b_unknown_full refused "${_ticket_body_1946}"$'<b>Security concerns</b><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_b_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Security concerns</b><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_em_negative_full labeled "${_ticket_body_1946}"$'<em>Security concerns</em><p>None</p>\n'
readiness_fixture_1946 html_security_em_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<em>Security concerns</em><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_em_finding_full refused "${_ticket_body_1946}"$'<em>Security concerns</em><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_em_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<em>Security concerns</em><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_em_unknown_full refused "${_ticket_body_1946}"$'<em>Security concerns</em><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_em_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<em>Security concerns</em><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_span_negative_full labeled "${_ticket_body_1946}"$'<span>Security concerns</span><p>None</p>\n'
readiness_fixture_1946 html_security_span_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Security concerns</span><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_span_finding_full refused "${_ticket_body_1946}"$'<span>Security concerns</span><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_span_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Security concerns</span><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_span_unknown_full refused "${_ticket_body_1946}"$'<span>Security concerns</span><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_span_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Security concerns</span><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_div_negative_full labeled "${_ticket_body_1946}"$'<div>Security concerns</div><p>None</p>\n'
readiness_fixture_1946 html_security_div_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Security concerns</div><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_div_finding_full refused "${_ticket_body_1946}"$'<div>Security concerns</div><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_div_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Security concerns</div><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_div_unknown_full refused "${_ticket_body_1946}"$'<div>Security concerns</div><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_div_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Security concerns</div><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_p_negative_full labeled "${_ticket_body_1946}"$'<p>Security concerns</p><p>None</p>\n'
readiness_fixture_1946 html_security_p_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<p>Security concerns</p><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_p_finding_full refused "${_ticket_body_1946}"$'<p>Security concerns</p><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_p_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<p>Security concerns</p><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_p_unknown_full refused "${_ticket_body_1946}"$'<p>Security concerns</p><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_p_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<p>Security concerns</p><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_summary_negative_full labeled "${_ticket_body_1946}"$'<summary>Security concerns</summary><p>None</p>\n'
readiness_fixture_1946 html_security_summary_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<summary>Security concerns</summary><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_summary_finding_full refused "${_ticket_body_1946}"$'<summary>Security concerns</summary><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_summary_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<summary>Security concerns</summary><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_summary_unknown_full refused "${_ticket_body_1946}"$'<summary>Security concerns</summary><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_summary_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<summary>Security concerns</summary><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_attributes_negative_full labeled "${_ticket_body_1946}"$'<h3 class="security">Security concerns:</h3><p>None</p>\n'
readiness_fixture_1946 html_security_attributes_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="security">Security concerns:</h3><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_attributes_finding_full refused "${_ticket_body_1946}"$'<h3 class="security">Security concerns:</h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_attributes_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="security">Security concerns:</h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_attributes_unknown_full refused "${_ticket_body_1946}"$'<h3 class="security">Security concerns:</h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_attributes_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="security">Security concerns:</h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_nested_negative_full labeled "${_ticket_body_1946}"$'<h3><strong>Security concerns</strong></h3><p>None</p>\n'
readiness_fixture_1946 html_security_nested_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><strong>Security concerns</strong></h3><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_nested_finding_full refused "${_ticket_body_1946}"$'<h3><strong>Security concerns</strong></h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_nested_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><strong>Security concerns</strong></h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_nested_unknown_full refused "${_ticket_body_1946}"$'<h3><strong>Security concerns</strong></h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_nested_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3><strong>Security concerns</strong></h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_fragmented_negative_full labeled "${_ticket_body_1946}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>None</p>\n'
readiness_fixture_1946 html_security_fragmented_negative_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>None</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_fragmented_finding_full refused "${_ticket_body_1946}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_fragmented_finding_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>Unsafe input execution.</p>\n' blocking-findings needs_fixes
readiness_fixture_1946 html_security_fragmented_unknown_full refused "${_ticket_body_1946}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_fragmented_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Secu<em>rity</em> con<strong>cerns</strong></h3><p>Unknown</p>\n' reviewer-check-absent escalate
readiness_fixture_1946 html_security_empty refused "${_ticket_body_1946}"$'<h3>Security concerns</h3>\n' reviewer-check-absent
readiness_fixture_1946 html_security_unclosed refused "${_ticket_body_1946}"$'<h3>Security concerns<p>Unknown</p>\n' reviewer-check-absent
readiness_fixture_1946 html_security_duplicate refused "${_ticket_body_1946}"$'<h3>Security concerns</h3><p>None</p><h3>Security concerns</h3><p>Unknown</p>\n' reviewer-check-absent
readiness_fixture_1946 html_security_next_heading labeled "${_ticket_body_1946}"$'<h3>Security concerns</h3><p>None</p><h3>Review metadata</h3><p>Effort 2/5</p>\n'
readiness_fixture_1946 html_security_prefix labeled "${_ticket_body_1946}"$'<h3>Custom Security concerns</h3><p>Unknown</p>\n'
readiness_fixture_1946 html_security_prose labeled "${_ticket_body_1946}"$'<p>Document Security concerns in the user guide.</p>\n'
readiness_fixture_1946 html_security_hidden labeled "${_ticket_body_1946}"$'<!-- <h3>Security concerns</h3><p>Unknown</p> -->\n'
readiness_fixture_1946 html_security_code labeled "${_ticket_body_1946}"$'```html\n<h3>Security concerns</h3><p>Unknown</p>\n```\n'
# Unprefixed rendered manual-request headings outrank compliance (#1946).
readiness_fixture_1946 html_human_h3_full refused "${_ticket_body_1946}"$'<h3>Requires further human verification</h3><p>Verify authorization manually.</p>\n' reviewer-check-absent
readiness_fixture_1946 html_human_h3_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Requires further human verification</h3><p>Verify authorization manually.</p>\n' reviewer-check-absent
readiness_fixture_1946 html_human_h1_colon_full refused "${_ticket_body_1946}"$'<h1>Requires further human verification:</h1>\n' reviewer-check-absent
readiness_fixture_1946 html_human_h1_colon_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h1>Requires further human verification:</h1>\n' reviewer-check-absent
readiness_fixture_1946 html_human_h6_full refused "${_ticket_body_1946}"$'<h6>Requires further human verification</h6>\n' reviewer-check-absent
readiness_fixture_1946 html_human_h6_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h6>Requires further human verification</h6>\n' reviewer-check-absent
readiness_fixture_1946 html_human_strong_full refused "${_ticket_body_1946}"$'<strong>Requires further human verification</strong><br>Verify authorization manually.\n' reviewer-check-absent
readiness_fixture_1946 html_human_strong_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Requires further human verification</strong><br>Verify authorization manually.\n' reviewer-check-absent
readiness_fixture_1946 html_human_b_full refused "${_ticket_body_1946}"$'<b>Requires further human verification</b><br>Verify authorization manually.\n' reviewer-check-absent
readiness_fixture_1946 html_human_b_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<b>Requires further human verification</b><br>Verify authorization manually.\n' reviewer-check-absent
readiness_fixture_1946 html_human_em_full refused "${_ticket_body_1946}"$'<em>Requires further human verification</em>\n' reviewer-check-absent
readiness_fixture_1946 html_human_em_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<em>Requires further human verification</em>\n' reviewer-check-absent
readiness_fixture_1946 html_human_span_full refused "${_ticket_body_1946}"$'<span>Requires further human verification</span>\n' reviewer-check-absent
readiness_fixture_1946 html_human_span_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<span>Requires further human verification</span>\n' reviewer-check-absent
readiness_fixture_1946 html_human_div_full refused "${_ticket_body_1946}"$'<div>Requires further human verification</div>\n' reviewer-check-absent
readiness_fixture_1946 html_human_div_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<div>Requires further human verification</div>\n' reviewer-check-absent
readiness_fixture_1946 html_human_p_full refused "${_ticket_body_1946}"$'<p>Requires further human verification</p>\n' reviewer-check-absent
readiness_fixture_1946 html_human_p_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<p>Requires further human verification</p>\n' reviewer-check-absent
readiness_fixture_1946 html_human_summary_full refused "${_ticket_body_1946}"$'<details><summary>Requires further human verification</summary>Verify authorization manually.</details>\n' reviewer-check-absent
readiness_fixture_1946 html_human_summary_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<details><summary>Requires further human verification</summary>Verify authorization manually.</details>\n' reviewer-check-absent
readiness_fixture_1946 html_human_fragmented_full refused "${_ticket_body_1946}"$'<h3 class="verification"> Requires&nbsp;further <em>human</em> <strong>verification</strong>: </h3>\n' reviewer-check-absent
readiness_fixture_1946 html_human_fragmented_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3 class="verification"> Requires&nbsp;further <em>human</em> <strong>verification</strong>: </h3>\n' reviewer-check-absent
readiness_fixture_1946 html_human_custom_prefix labeled "${_ticket_body_1946}"$'<h3>Custom Requires further human verification</h3>\n'
readiness_fixture_1946 html_human_prose labeled "${_ticket_body_1946}"$'<p>Support Requires further human verification descriptions.</p>\n'
readiness_fixture_1946 html_human_hidden labeled "${_ticket_body_1946}"$'<!-- <h3>Requires further human verification</h3> -->\n'
readiness_fixture_1946 html_human_code labeled "${_ticket_body_1946}"$'```html\n<h3>Requires further human verification</h3>\n```\n'
# Verification status is independent of presentation and compliance verdict.
readiness_fixture_1946 format_plain_colon_required_full refused "${_ticket_body_1946}"$'Verification status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_plain_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verification status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_plain_colon_unknown_full refused "${_ticket_body_1946}"$'Verification status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_plain_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verification status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_plain_no_colon_required_full refused "${_ticket_body_1946}"$'Verification status Required\n' reviewer-check-absent
readiness_fixture_1946 format_plain_no_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verification status Required\n' reviewer-check-absent
readiness_fixture_1946 format_plain_no_colon_unknown_full refused "${_ticket_body_1946}"$'Verification status Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_plain_no_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verification status Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_bold_colon_required_full refused "${_ticket_body_1946}"$'**Verification status**: Required\n' reviewer-check-absent
readiness_fixture_1946 format_bold_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status**: Required\n' reviewer-check-absent
readiness_fixture_1946 format_bold_colon_unknown_full refused "${_ticket_body_1946}"$'**Verification status**: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_bold_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status**: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_bold_no_colon_required_full refused "${_ticket_body_1946}"$'**Verification status** Required\n' reviewer-check-absent
readiness_fixture_1946 format_bold_no_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status** Required\n' reviewer-check-absent
readiness_fixture_1946 format_bold_no_colon_unknown_full refused "${_ticket_body_1946}"$'**Verification status** Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_bold_no_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status** Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_bold_value_required_full refused "${_ticket_body_1946}"$'**Verification status** : **Required**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_value_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status** : **Required**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_value_unknown_full refused "${_ticket_body_1946}"$'**Verification status** : **Unknown**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_value_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status** : **Unknown**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_entire_required_full refused "${_ticket_body_1946}"$'**Verification status: Required**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_entire_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status: Required**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_entire_unknown_full refused "${_ticket_body_1946}"$'**Verification status: Unknown**\n' reviewer-check-absent
readiness_fixture_1946 format_bold_entire_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status: Unknown**\n' reviewer-check-absent
readiness_fixture_1946 format_html_colon_required_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong>: Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong>: Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_colon_unknown_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong>: Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong>: Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_no_colon_required_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong> Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_no_colon_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong> Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_no_colon_unknown_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong> Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_no_colon_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong> Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_break_required_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_break_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong><br>Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_break_unknown_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification status</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_break_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification status</strong><br>Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_attributes_required_full refused "${_ticket_body_1946}"$'<tr><td><strong class="field" title=">">Verification status</strong><br><span>Required</span></td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_attributes_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong class="field" title=">">Verification status</strong><br><span>Required</span></td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_attributes_unknown_full refused "${_ticket_body_1946}"$'<tr><td><strong class="field" title=">">Verification status</strong><br><span>Unknown</span></td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_attributes_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong class="field" title=">">Verification status</strong><br><span>Unknown</span></td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_spaces_required_full refused "${_ticket_body_1946}"$'  ** Verification\tstatus **  :  ** Required ** \n' reviewer-check-absent
readiness_fixture_1946 format_spaces_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'  ** Verification\tstatus **  :  ** Required ** \n' reviewer-check-absent
readiness_fixture_1946 format_spaces_unknown_full refused "${_ticket_body_1946}"$'  ** Verification\tstatus **  :  ** Unknown ** \n' reviewer-check-absent
readiness_fixture_1946 format_spaces_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'  ** Verification\tstatus **  :  ** Unknown ** \n' reviewer-check-absent
readiness_fixture_1946 format_entities_required_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification&nbsp;status</strong>&nbsp;:&nbsp;Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_entities_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification&nbsp;status</strong>&nbsp;:&nbsp;Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_entities_unknown_full refused "${_ticket_body_1946}"$'<tr><td><strong>Verification&nbsp;status</strong>&nbsp;:&nbsp;Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_entities_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td><strong>Verification&nbsp;status</strong>&nbsp;:&nbsp;Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_multiline_required_full refused "${_ticket_body_1946}"$'**Verification status**\n:\nRequired\n' reviewer-check-absent
readiness_fixture_1946 format_multiline_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status**\n:\nRequired\n' reviewer-check-absent
readiness_fixture_1946 format_multiline_unknown_full refused "${_ticket_body_1946}"$'**Verification status**\n:\nUnknown\n' reviewer-check-absent
readiness_fixture_1946 format_multiline_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'**Verification status**\n:\nUnknown\n' reviewer-check-absent
readiness_fixture_1946 format_inline_bold_required_full refused "${_ticket_body_1946}"$'Review metadata: **Verification status**: Required\n' reviewer-check-absent
readiness_fixture_1946 format_inline_bold_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Review metadata: **Verification status**: Required\n' reviewer-check-absent
readiness_fixture_1946 format_inline_bold_unknown_full refused "${_ticket_body_1946}"$'Review metadata: **Verification status**: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_inline_bold_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Review metadata: **Verification status**: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_inline_html_required_full refused "${_ticket_body_1946}"$'<tr><td>Review metadata: <strong>Verification status</strong>: Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_inline_html_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td>Review metadata: <strong>Verification status</strong>: Required</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_inline_html_unknown_full refused "${_ticket_body_1946}"$'<tr><td>Review metadata: <strong>Verification status</strong>: Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_inline_html_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<tr><td>Review metadata: <strong>Verification status</strong>: Unknown</td></tr>\n' reviewer-check-absent
readiness_fixture_1946 format_html_heading_required_full refused "${_ticket_body_1946}"$'<h3>Verification status</h3><p>Required</p>\n' reviewer-check-absent
readiness_fixture_1946 format_html_heading_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Verification status</h3><p>Required</p>\n' reviewer-check-absent
readiness_fixture_1946 format_html_heading_unknown_full refused "${_ticket_body_1946}"$'<h3>Verification status</h3><p>Unknown</p>\n' reviewer-check-absent
readiness_fixture_1946 format_html_heading_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<h3>Verification status</h3><p>Unknown</p>\n' reviewer-check-absent
readiness_fixture_1946 format_markdown_heading_required_full refused "${_ticket_body_1946}"$'### Verification status\nRequired\n' reviewer-check-absent
readiness_fixture_1946 format_markdown_heading_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### Verification status\nRequired\n' reviewer-check-absent
readiness_fixture_1946 format_markdown_heading_unknown_full refused "${_ticket_body_1946}"$'### Verification status\nUnknown\n' reviewer-check-absent
readiness_fixture_1946 format_markdown_heading_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### Verification status\nUnknown\n' reviewer-check-absent
readiness_fixture_1946 format_emoji_heading_required_full refused "${_ticket_body_1946}"$'### 👤 Verification status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_emoji_heading_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### 👤 Verification status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_emoji_heading_unknown_full refused "${_ticket_body_1946}"$'### 👤 Verification status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_emoji_heading_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'### 👤 Verification status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_decorated_plain_required_full refused "${_ticket_body_1946}"$'Review status — Verification status Required\n' reviewer-check-absent
readiness_fixture_1946 format_decorated_plain_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Review status — Verification status Required\n' reviewer-check-absent
readiness_fixture_1946 format_decorated_plain_unknown_full refused "${_ticket_body_1946}"$'Review status — Verification status Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_decorated_plain_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Review status — Verification status Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_unknown_heading_required refused "${_ticket_body_1946}"$'### Custom Verification status: Required\n' reviewer-check-absent
readiness_fixture_1946 descriptive_status_reference labeled "${_ticket_body_1946/All required behavior is implemented./Support Verification status Required values.}"
readiness_fixture_1946 descriptive_styled_status_reference labeled "${_ticket_body_1946/All required behavior is implemented./<strong>Support Verification status Required values.<\/strong>}"
readiness_fixture_1946 format_fragmented_label_required_full refused "${_ticket_body_1946}"$'Verifi<strong>cation</strong> status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_label_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verifi<strong>cation</strong> status: Required\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_label_unknown_full refused "${_ticket_body_1946}"$'Verifi<strong>cation</strong> status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_label_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'Verifi<strong>cation</strong> status: Unknown\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_value_required_full refused "${_ticket_body_1946}"$'<strong>Verification status</strong>: <span>Req</span><em>uired</em>\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_value_required_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Verification status</strong>: <span>Req</span><em>uired</em>\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_value_unknown_full refused "${_ticket_body_1946}"$'<strong>Verification status</strong>: <span>Unk</span><em>nown</em>\n' reviewer-check-absent
readiness_fixture_1946 format_fragmented_value_unknown_partial refused "${_ticket_body_1946/Fully compliant/Partially compliant}"$'<strong>Verification status</strong>: <span>Unk</span><em>nown</em>\n' reviewer-check-absent
unset _ticket_body_1946
unset -f readiness_fixture_1946
