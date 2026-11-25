# HTML Mockup Framework

The HTML Mockup Framework is a convention for version-controlled, interactive
HTML mockups with no build step. This page is the framework's contract inside
the template: where the design tree lives, how a repository lays it out, where
tokens come from, how the design READMEs are split, which source wins a
disagreement, and how a project opts in.

## Status and ownership

This page is the canonical contract for the layout, repository types, tokens,
README sections, source-of-truth hierarchy and the `design` opt-in block
(#2211). The vault standard `HTML Mockup Framework.md` keeps the rationale and
history behind these rules and points here; when the two differ, this page
wins. Later changes to the contract are made here first.

The framework is opt-in. A repository that does not declare the `design` block
is not affected by anything on this page.

## Design tree

Paths are relative to the repository root and use the default design root
`design/`. A configured `design.root` relocates the whole tree; every path
below the root stays the same.

```text
design/                  # design root (default design/)
├── README.md            # design README: Framework section, then Project section
├── tokens.json          # token file
└── mockups/
    ├── README.md        # mockups README: Framework section, then Project section
    ├── shared/          # shared viewer assets
    └── <app>/           # one folder per app (Monorepo apps, Knowledge repo)
```

| Path (default root `design/`) | Purpose |
| --- | --- |
| `design/README.md` | Design README |
| `design/tokens.json` | Token file |
| `design/mockups/README.md` | Mockups README |
| `design/mockups/shared/` | Shared folder for viewer assets |
| `design/mockups/<app>/` | Per-app folder, one per app |

A Single app repository puts its mockups directly in `design/mockups/` instead
of a per-app folder (see Repository types).

## Repository types

Choose one layout per repository; do not mix them.

| Repository type | Mockup location | Shared viewer folder | Token file | Link from a mockup to the token file |
| --- | --- | --- | --- | --- |
| Monorepo apps | `design/mockups/<app>/`, one folder per app | `design/mockups/shared/` | `design/tokens.json` | `../../tokens.json` |
| Single app | `design/mockups/` | `design/mockups/shared/` | `design/tokens.json` | `../tokens.json` |
| Knowledge repo | `design/mockups/<app>/`, same as Monorepo apps | `design/mockups/shared/` | `design/tokens.json` | `../../tokens.json` |

Every layout has the design README `design/README.md`, the token file
`design/tokens.json` and the mockups README `design/mockups/README.md`. The
Knowledge repo layout has the same shape as Monorepo apps; it differs only in
where the tree lives (see Home below). Paths assume the default design root
`design/`.

## Mockup kinds and tokens

### Home

| Code value | Display label | Meaning |
| --- | --- | --- |
| `knowledge` | Knowledge repository | The design tree lives in a knowledge or specs repository; specs own UX and mockups change in the same PR as the spec. |
| `product` | Product repository | The design tree lives next to the app code; engineers are the daily consumers. |

### Kind

| Code value | Display label | Meaning |
| --- | --- | --- |
| `design-intent` | Design intent | Hand-authored from the spec before the code exists; the token file is the source; the mockup wins a disagreement. |
| `reproduction` | Reproduction | Generated from the running app; the app's stylesheet is the source; the app wins a disagreement. |

### Token rule by kind

- **Design intent**: the token file `design/tokens.json` is the source. Its
  values are mirrored in the mockup's root style block in the same commit.
- **Reproduction**: the source is the running app's stylesheet, harvested from
  it. The token file is not mirrored.

### Kind precedence

The kind configured in the `design` block is the project's declared default
and the kind new mockups start as. A mockup's own declared kind governs that
mockup, so one repository can hold a Design intent mockup and a Reproduction
side by side. A difference between the configured kind and a mockup's own kind
is not an error at this level.

## Source-of-truth hierarchy

For Design intent, in order of precedence:

1. Product specifications.
2. The token file and the design-system screens.
3. Product mockup screens.
4. The design tool, when one is used.
5. Production code, which converges toward the sources above.

For a Reproduction the hierarchy is inverted: production code is the source and
the mockup converges toward it. When a Reproduction and the app disagree, the
mockup is wrong.

## README sections

The design README (`design/README.md`) and the mockups README
(`design/mockups/README.md`) each have two sections:

- **Framework** — template contract text. It sits between the
  `<!-- TEMPLATE-OWNED-START -->` and `<!-- TEMPLATE-OWNED-END -->` markers,
  the same HTML-comment markers template sync uses for template-owned text.
- **Project** — the product's own inventory (product name, repository type,
  home and kind, app list, screen inventory). It sits after the end marker.

The markers keep the two apart, so a later refresh of the Framework section can
leave the Project section untouched.

Structure text (headings, section names, folder names) is in English; mockup
content is in the product's language.

## Opting in

### The `design` block

A repository opts in with the top-level `design` key in its versioned
`.ai-dev-workflow.yaml`:

```yaml
design:
  root: design/        # optional; defaults to design/ when omitted
  home: knowledge
  kind: design-intent
```

| Field | Required | Accepted values |
| --- | --- | --- |
| `root` | No; defaults to `design/` | A non-empty string path relative to the repository root that stays inside the repository. A number, boolean, list or mapping, an absolute path, or a path that leaves the repository is invalid. |
| `home` | Yes | `knowledge` (Knowledge repository) or `product` (Product repository) |
| `kind` | Yes | `design-intent` (Design intent) or `reproduction` (Reproduction) |

Key names and values are matched exactly, including case, so `Home` or
`Knowledge` are not accepted. Fields the check does not define are ignored and
do not change the outcome, so later items can extend the block.

### Rules

- The block is the only opt-in record. Prose in project documentation, the
  presence of a design folder, or a copied scaffold never opts a project in,
  and workflow stages gate on the block, never on prose.
- When the configuration file or the block is absent, the project is not opted
  in and every workflow behaviour is unchanged.
- The opt-in is a repository decision, so it is read only from the versioned
  `.ai-dev-workflow.yaml`. Machine-local configuration
  (`.ai-dev-workflow.local.yaml`) can neither opt a project in nor out, nor
  change its design root (default `design/`), home or kind.
- The check reads configuration only. It does not create, change or inspect
  design files, and it reads the configuration again every time it is asked.

### Opt-in resolution table

Rows 1 to 4 are evaluated in order, and the first match decides the outcome.
If none of them match, rows 5 to 7 are all evaluated: when one or more match,
the outcome is Invalid configuration listing the problem of every matching row;
when none match, row 8 applies.

| # | Situation | Outcome |
| --- | --- | --- |
| 1 | The versioned workflow configuration file does not exist | Not opted in |
| 2 | The configuration file exists but cannot be read or parsed | Invalid configuration (configuration unreadable) |
| 3 | The configuration has no top-level `design` key at all | Not opted in |
| 4 | The `design` key is present but its value is empty, null, or not a set of fields | Invalid configuration (block has no usable fields) |
| 5 | `design.home` is missing or not one of the accepted values | Invalid configuration (names home) |
| 6 | `design.kind` is missing or not one of the accepted values | Invalid configuration (names kind) |
| 7 | `design.root` is present and is not a string (number, boolean, list or mapping), or is empty, null, absolute, or outside the repository | Invalid configuration (names design root) |
| 8 | None of rows 1 to 7 apply | Opted in, with design root (`design.root`, default `design/` when absent), home and kind |

### Outcomes

| Display label | Code value | Meaning |
| --- | --- | --- |
| Not opted in | `not_opted_in` | No configuration file or no design block; behaviour unchanged. |
| Opted in | `opted_in` | Valid design block; design-aware stages may apply. |
| Invalid configuration | `invalid` | Block present but unusable, or configuration unreadable; every problem is named. |

### Reading the outcome from a stage

Stages call `workflow_design_opt_in` from
`scripts/development-workflow/workflow-lib.sh`. It takes an optional
repository root (default: the checkout the library belongs to) and prints one
`KEY=value` line per field:

<!-- workflow-shell-contract: bash -->
```bash
bash -c 'source scripts/development-workflow/workflow-lib.sh && workflow_design_opt_in "$PWD"'
```

| Line | Not opted in | Opted in | Invalid configuration |
| --- | --- | --- | --- |
| `DESIGN_OPT_IN=` | `not_opted_in` | `opted_in` | `invalid` |
| `DESIGN_OPT_IN_LABEL=` | `Not opted in` | `Opted in` | `Invalid configuration` |
| `DESIGN_ROOT=` | — | configured string, or `design/` | — |
| `DESIGN_ROOT_SOURCE=` | — | `configured` or `default` | — |
| `DESIGN_HOME=` / `DESIGN_HOME_LABEL=` | — | code value / display label | — |
| `DESIGN_KIND=` / `DESIGN_KIND_LABEL=` | — | code value / display label | — |
| `DESIGN_PROBLEM_COUNT=` | — | — | number of problem lines |
| `DESIGN_PROBLEM=` (repeated) | — | — | `<field>: <detail>` |

- Every outcome exits 0. Exit 2 with no output means a caller error: the
  repository root argument is empty or not a directory, or the library could
  not resolve its own checkout.
- `<field>` is `configuration`, `design`, `design.home`, `design.kind` or
  `design.root`; field problems are listed in that order. Each detail names the
  value found, or says it is absent, and the accepted values. A configuration
  problem never echoes file content.
- Values are printed on one line with backslash, CR, LF, tab and other control
  characters escaped (`\\`, `\r`, `\n`, `\t`, `\xNN`, `\uNNNN`). Inside a
  problem detail a found string longer than 80 characters is cut to 80
  characters plus `…`, and a list or mapping is described by its type only.
- If `python3` or the configuration reader cannot run, the check fails closed:
  Not opted in when no file exists, otherwise Invalid configuration with a
  `configuration` problem saying the check could not run and the file may be
  valid.

## Starting from the scaffold

The template ships a starter design tree as an opt-in scaffold at
`template/design-scaffold/design/`, available on GitHub at
<https://github.com/lhpaul/ai-dev-framework-template/tree/develop/template/design-scaffold/design>.
Template sync never copies the scaffold into a project and never creates,
changes or deletes a project's own design tree.

To start a design tree by hand:

1. Copy the scaffold into the project at the design root (default `design/`).
2. Keep the layout that matches the project's repository type: per-app folders
   (Monorepo apps, Knowledge repo) or a single mockups folder (Single app).
   Remove the other.
3. Fill in the Project sections of the design README and the mockups README,
   leaving the Framework sections untouched.
4. Replace the example tokens in `tokens.json` with the product's own.
5. Add the `design` block to `.ai-dev-workflow.yaml` with the home and kind,
   and the design root if it is not the default `design/`.

Copying the scaffold does not by itself opt the project in; only step 5 does.

## Forthcoming

These parts of the framework are delivered by later items and are not part of
this contract yet:

- Manifest contract and verify script — #2206.
- Viewer and shell — #2207.
- Setup bootstrap — #2208.
- Adoption in an existing repository — #2214.
