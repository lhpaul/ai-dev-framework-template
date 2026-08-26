# Changelog Fragments

Implementation PRs record release notes as one file per work item in this
directory instead of editing `CHANGELOG.md` directly.

## File Names

Use this exact format:

```text
<item>.<kind>.<slug>.md
```

- `<item>` is the bare issue or tracker identifier, such as `1554` or
  `ENG-42`. Do not include `#`.
- `<kind>` is one of `added`, `changed`, `deprecated`, `removed`, `fixed`, or
  `security`.
- `<slug>` is a short kebab-case description.

Examples:

```text
1554.changed.per-item-release-notes.md
1589.fixed.integration-branch-ci.md
ENG-42.added.export-button.md
```

## Body

The body is the final changelog bullet, including the bold title and issue
reference:

```markdown
- **Short user-facing title** (#1554): concise release-note text.
```

Continuation lines are allowed when indented under the bullet.

For repositories without an issue tracker, open the draft PR first and use the
PR number as `<item>`. In that no-tracker case, omit the `(#N)` reference from
the bullet body because there is no issue number to cite.

Validate fragments before pushing:

```bash
bash scripts/development-workflow/changelog-fragments.sh validate
```

Release preparation gathers pending fragments into `CHANGELOG.md` and deletes
the gathered files on the release branch. Do not add aggregate indexes,
manifests, or ordering files under this directory.
