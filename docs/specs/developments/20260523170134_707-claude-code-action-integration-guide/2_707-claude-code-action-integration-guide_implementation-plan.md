# Claude Code Action Integration Guide — Implementation Plan

**Spec**: [1_707-claude-code-action-integration-guide_specs.md](1_707-claude-code-action-integration-guide_specs.md)
**Smoke test runbook**: [docs/testing/workflow/707-claude-code-action-integration-guide.smoke-test.md](../../../testing/workflow/707-claude-code-action-integration-guide.smoke-test.md)

---

## Summary

**Approach**: Create a new integration guide
`docs/workflow/development-workflow/integrations/claude-code-action.md` covering
how an operator adds Claude Code Action as a PR review platform, following the
structure and depth of existing guides (e.g., `coderabbit.md`, `haystack.md`).
Update `pr-review-platform.md` to add `claude-code-action` to the supported
platform list with a link to the new guide. No script changes are required for
this item — the `pr-review-loop.sh` integration is covered by issue #705.

**Estimated complexity**: S

**Rationale**: Pure documentation additions to an existing directory structure.
Two files change: a new guide (~150-200 lines) and a small addition to the
platform table (~5-10 lines). No code, no schema, no config activation changes.

**Dependencies**: Issue #706 (GHA workflow file) is referenced by the guide but
does not need to be merged first — the guide references the workflow file by its
expected path (`.github/workflows/claude-code-review.yml`) without
requiring the file to exist at merge time. Issue #705 (pr-review-loop.sh
function) and issue #708 (`.ai-dev-workflow.yaml` activation) are consumers of
this guide, not prerequisites for it.

---

## Verification Log

| Check                                     | Command / query                                                                            | Result                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------- |
| Repo revision                             | `git rev-parse --short HEAD`                                                               | `0e984a7`                                         |
| Existing integration guides               | `ls docs/workflow/development-workflow/integrations/`                                      | 12 files; no `claude-code-action.md` yet          |
| Platform references in pr-review-platform | `grep -n "claude" docs/workflow/development-workflow/integrations/pr-review-platform.md`   | 0 matches — `claude-code-action` not yet listed   |
| claude-code-action in pr-review-loop.sh   | `grep -n "claude.code.action" scripts/development-workflow/pr-review-loop.sh`              | 0 matches — out of scope for this issue           |
| Platforms listed in .ai-dev-workflow.yaml | `grep -A 5 "platforms:" .ai-dev-workflow.yaml`                                             | `pr-agent`, `coderabbit` — no `claude-code-action` |

---

## Layer-by-Layer Changes

### Documentation / Integrations

- [ ] Create `docs/workflow/development-workflow/integrations/claude-code-action.md`
  — new integration guide covering: required secret (`ANTHROPIC_API_KEY`),
  workflow file reference, trigger phrase, bot login for thread attribution,
  model selection guidance, and no-per-hour-cap explanation (BR-1 through BR-7)
- [ ] Update `docs/workflow/development-workflow/integrations/pr-review-platform.md`
  — add `claude-code-action` to the "See also" links list and add an entry to
  the Platform Configuration example YAML showing `claude-code-action` as a
  recognized platform identifier (BR-7)

---

## Testing Strategy

**Test types**: Manual / Smoke (documentation review)

**Key scenarios to test**:

1. New guide exists at the correct path and all acceptance criteria pass
2. Platform reference table in `pr-review-platform.md` lists `claude-code-action`
   with a working relative link to the new guide
3. No broken relative links in either modified file
4. Platform identifier `claude-code-action` matches across guide, table, and YAML
   examples

**Smoke test runbook**: `docs/testing/workflow/707-claude-code-action-integration-guide.smoke-test.md`

---

## Seed Data

None — this feature is documentation-only.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` —
  add `claude-code-action` to the platform list (this is part of this PR's
  deliverable, not a post-implementation update)

No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md`
need updating — the guide is a new integration doc that stands alone.

---

## Risks & Mitigations

| Risk                                                        | Likelihood | Impact | Mitigation                                                                                                     |
| ----------------------------------------------------------- | ---------- | ------ | -------------------------------------------------------------------------------------------------------------- |
| Bot login name for Claude Code Action is incorrect          | Low        | Medium | Use the known GitHub App bot login (`claude[bot]` or the `claude-code-action` bot) and flag for operator check |
| Broken relative links between guide and pr-review-platform  | Low        | Low    | Run `markdownlint-cli2` with the `relative-links` rule before committing                                        |
| Model names stale at time of downstream use                 | Medium     | Low    | Guide explicitly notes operators should verify current model availability at `console.anthropic.com`            |

---

## Implementation Order

1. **Create the integration guide** at
   `docs/workflow/development-workflow/integrations/claude-code-action.md`:

   - Opening paragraph: what Claude Code Action is, why it has no per-hour
     vendor cap (BR-2 — own-key, own CI), and pointer to the shipped GHA
     workflow file at `.github/workflows/claude-code-review.yml` (BR-6)
   - **Setup section**: step-by-step operator checklist:
     1. Add `ANTHROPIC_API_KEY` as a GitHub Actions repository secret (BR-3)
     2. Reference (do not copy) the workflow file at
        `.github/workflows/claude-code-review.yml` (BR-6)
     3. Note the bot login used for thread attribution (BR-4) — the Claude Code
        Action GitHub App posts review threads as `claude[bot]`; operators must
        use this login when configuring `pr-review-loop.sh` to identify threads;
        the platform is dispatched via `workflow_dispatch` from the helper script
        so no trigger phrase configuration is required
     5. Add `claude-code-action` to `review.platforms` in `.ai-dev-workflow.yaml`
        (BR-1) with example YAML showing the platform identifier
   - **Model selection section** (BR-5):
     - Name `claude-sonnet-4-6` (or current Sonnet equivalent) as the default
     - Provide a simple guidance table: Haiku (fast/cheap, small PRs), Sonnet
       (default, balanced), Opus (deep review, large diffs)
     - Note approximate order-of-magnitude cost context, not exact prices
     - Note that model names and pricing change; operators should verify at
       `console.anthropic.com`
   - **No-per-hour-cap section**: explain that GitHub Actions minutes are free
     for public repositories; the only cost is Anthropic API token usage
   - Follow the guide structure of existing peers (e.g., `coderabbit.md`,
     `haystack.md`): use `---` section dividers, avoid H1 reuse, keep prose
     concise

   Verify: confirm file exists at correct path, markdownlint passes, all
   relative links to `pr-review-platform.md` resolve correctly from the file's
   location.

2. **Update `pr-review-platform.md`**:

   - Add `claude-code-action` to the "See also" links at the top of the
     document alongside `coderabbit.md`, `greptile.md`, and `devin.md`:
     ```
     - [`integrations/claude-code-action.md`](claude-code-action.md)
     ```
   - Update the example YAML block in the Platform Configuration section to
     include `claude-code-action` as a valid platform identifier (illustrative
     comment or added entry)

   Verify: confirm the relative link `(claude-code-action.md)` resolves from
   `pr-review-platform.md`'s location, which is the same directory as the new
   guide.

3. **Run markdownlint** on both files before committing:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/workflow/development-workflow/integrations/claude-code-action.md" \
     "docs/workflow/development-workflow/integrations/pr-review-platform.md"
   ```

   Fix any trailing whitespace, broken relative links, or missing trailing
   newline before proceeding.

4. **Commit, push, and open draft PR** targeting `develop-claude-review-platform`:

   - Commit message: `docs: add claude-code-action integration guide and update platform table (#707)`
   - PR title: `docs(plan): claude-code-action integration guide`
   - PR body: link to this plan, link to spec, complexity S estimate

   Note: CHANGELOG entry is not required — `implementation-plan/*` branches are
   exempt.

5. **Verify smoke test runbook** using
   `docs/testing/workflow/707-claude-code-action-integration-guide.smoke-test.md`.
