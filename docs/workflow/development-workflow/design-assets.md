# Design Assets Convention

Canonical rules for capturing, storing, discovering, and lightly validating
graphical design references in the AI development workflow.

Protocols and command surfaces **link here** rather than redefining these rules.
This is intentionally lightweight: it is **not** a visual-regression platform,
pixel-diff harness, or `/merged-qa` (#1283) implementation.

---

## When this applies

Use these rules when a backlog item or later stage may have design references
such as HTML mockups, screenshots, photos, SVG comps, or PDF mockups.

Do **not** invent assets when none were supplied. Orthogonal sibling work items
are never asset sources for the current item.

---

## Recognition heuristics

Classify each candidate file by extension (case insensitive). This is
agent-facing guidance, not a parser/lint module.

### Likely design assets

Treat as design references (stage/attach without asking) when the extension is:

| Kind | Extensions |
| --- | --- |
| HTML mockups | `.html`, `.htm` |
| Images | `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg` |
| PDF mockups | `.pdf` |

### Clearly non-design

Do **not** stage as design references (unless the human explicitly says they
are):

- Logs / dumps: `.log`, `.csv`
- Common source: `.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`, `.rs`, `.java`,
  `.rb`, `.sh`
- Lock/config dumps unless explicitly marked as design references

### Ambiguous

Ask **one** brief clarifying question covering the whole ambiguous set, then
still create **exactly one** backlog item. Examples: `.md`, `.txt`, `.docx`,
`.zip`, or mixed batches where intent is unclear.

---

## Storage layout

| When | Where | Notes |
| --- | --- | --- |
| Backlog creation | Tracker attachments (GitHub Issues / Linear / provider-native) | Primary store before a development folder exists |
| After development folder exists | `<dev-folder>/assets/` | Canonical on-disk location under `docs/specs/developments/<timestamp>_<slug>/` |
| Always | Issue / work-item body section `## Design assets` | Lists locations and states that plan/smoke should use them as fidelity references |

Exact folder name: **`assets/`** (not `design-assets/`). Only confirmed design
reference files belong there; incidental attachments stay tracker-only and are
not copied into `assets/`.

### Migration rule

When a development folder is created or first used and tracker design assets
exist, copy or download confirmed design assets into `<dev-folder>/assets/` and
update the issue-body location note. Do not invent assets when none exist.

---

## Issue-body template

Include (or append) this section on the work item:

```markdown
## Design assets

- **References**: <filenames or short labels>
- **Locations**:
  - Tracker attachments: <yes/no; names if known>
  - Local / staged paths: <path notes if upload failed or pending>
  - Development folder: `<dev-folder>/assets/` <when present>
- **Usage**: Plan and smoke stages should treat these as expected visual
  references for UI-facing work. Do not invent a baseline if this section is
  absent or empty.
```

---

## Capture at `/add-backlog-item`

See protocol
[`00-add-backlog-item-protocol.md`](protocols/00-add-backlog-item-protocol.md).
Summary:

1. Detect candidate files from the invocation (chat attachments, local paths).
2. Classify each file (likely / ambiguous / non-design).
3. Ask at most one brief clarifying question for the ambiguous set.
4. Create exactly one backlog item (normal destination / Type / Priority / Size).
5. Attach or upload confirmed design assets via provider-native means when
   available; on failure, record local paths in the body and ask the human to
   attach manually — do **not** fail item creation solely because upload failed.
6. Ensure the `## Design assets` body section is present.

### GitHub attach recipe (agent-driven)

`add-backlog-item.sh` creates the issue and project fields; reliable binary
attachment to GitHub Issues is not exposed as a stable `gh` subcommand, so
agents attach after create:

1. Prefer the GitHub UI or MCP attachment upload for the issue when available.
2. Otherwise post an issue comment that lists each confirmed asset filename and
   any durable URL the human/MCP produced, and keep the `## Design assets`
   body section accurate (paths + “human attach requested” when needed).
3. Never block creation on attach failure.

Example comment body:

```markdown
## Design assets (staged)

- `mockup.png` — please attach to this issue (local path noted in issue body).
```

For Linear and other providers, use the provider-native attachment API/MCP from
the matching integration guide.

---

## Discovery order (agents)

Before UI-facing plan or smoke work, check in order:

1. Issue / work-item body `## Design assets` section (canonical pointers)
2. Tracker attachments on the work item
3. Linked files referenced from the issue body
4. `<dev-folder>/assets/` when the development folder exists

If none found: continue normally; do **not** invent a baseline.

If locations conflict: ask the human once which reference is authoritative.

---

## Lightweight fidelity checks

- **Plan writers** (protocol `02`): when discovery finds assets, include at least
  one expected-vs-actual fidelity step in the smoke runbook that names the
  reference asset(s). If none, omit fidelity steps.
- **Smoke execution** (protocol `04`): when a runbook includes fidelity steps,
  perform a lightweight human/agent visual comparison (not pixel diff). Record
  PASS/FAIL with expected-vs-actual detail on failure.
- **design-reviewer** is **not** the primary mockup-fidelity gate for this
  convention. Optional design review remains separate from AC-driven smoke
  fidelity steps.

---

## Non-goals

- `/merged-qa` / #1283 implementation
- Automated visual-regression platform (pixel diffs, baseline vaults, CI
  screenshot suites)
- Promoting design-reviewer to the primary fidelity gate
- Treating sibling issues as asset sources
