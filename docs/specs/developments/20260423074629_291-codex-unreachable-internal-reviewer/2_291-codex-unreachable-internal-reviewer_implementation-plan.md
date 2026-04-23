# Fix #291: Codex Unreachable Internal Reviewer — Implementation Plan

**Issue**: [#291](https://github.com/lhpaul/ai-dev-framework-template/issues/291)
**Fast Track**: No spec required (documentation/config-only fix)

---

## Summary

**Approach**: Clarify in `.ai-dev-workflow.yaml` that `codex` as an internal
reviewer is only reachable in Cursor/Codex runner environments, not from Claude
Code (direct or subagent). Add an inline comment next to the `codex` entry and
expand the comment block above `internal_reviewers` to document the
runner-context constraint. No code or protocol changes are needed because
Protocol 91 Step 7a already handles the runtime-availability check and
`warn` policy correctly.

**Estimated complexity**: XS

**Rationale**: Every batch run from Claude Code produces "Skipped: codex
(unreachable from Claude Code subagent)" warnings. This is expected and correct
behaviour (the `warn` policy proceeds with only `claude`), but the config file
gives no indication of the constraint, so operators repeatedly see warnings with
no explanation in the config they control.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] **`.ai-dev-workflow.yaml`** — Expand the `internal_reviewers` comment block
  to document that `codex` is only reachable in Cursor/Codex runner environments.
  Add an inline comment after the `- codex` list entry. The clarification should:
  1. State that `codex` is only reachable when running from a Codex or Cursor
     runner (not from Claude Code direct or subagent context).
  2. Note that the `warn` policy (default) gracefully handles the unreachability
     and the gate proceeds with `claude` only when running from Claude Code.
  3. Reference the local override option (`.tmp/template-config.json`) for
     operators who want to suppress the recurring warning entirely.

### Documentation

- No protocol changes are needed. Protocol 91 Step 7a already documents the
  reachability classification table, the `warn` policy, and the warning comment
  format. The fix is purely about surfacing the constraint in the config file
  that operators edit directly.

---

## Testing Strategy

**Test type**: Manual inspection

1. Read the updated `.ai-dev-workflow.yaml` and verify the added comment is clear
   and accurate.
2. Verify no YAML syntax errors (run `python3 -c "import yaml; yaml.safe_load(open('.ai-dev-workflow.yaml'))"` or equivalent).
3. Verify the `internal_reviewers_unavailable_policy` comment block is still
   coherent with the new context note.

---

## Documentation Updates

- [ ] `.ai-dev-workflow.yaml` — primary change (see above)

---

## Implementation Order

1. Read current `.ai-dev-workflow.yaml` `internal_reviewers` block.
2. Add runner-context clarification comment before/after the `- codex` entry.
3. Verify YAML parses cleanly.
4. Update `CHANGELOG.md` under `[Unreleased]`.
