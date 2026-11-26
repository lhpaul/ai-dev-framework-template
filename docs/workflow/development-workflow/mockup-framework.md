# HTML Mockup Framework

The HTML Mockup Framework is a convention for version-controlled, interactive
HTML mockups with no build step. This page is the framework's contract inside
the template: where the design tree lives, how a repository lays it out, where
tokens come from, how the design READMEs are split, which source wins a
disagreement, how a project opts in, and what a mockup manifest contains.

## Status and ownership

This page is the canonical contract for the layout, repository types, tokens,
README sections, source-of-truth hierarchy and the `design` opt-in block
(#2211), and for the mockup manifest and its verify script (#2206). The vault standard `HTML Mockup Framework.md` keeps the rationale and
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

## Manifest

Every mockup folder has a manifest, `mockup-manifest.js`, that names each
screen and its local states (#2206). Specs, reviews and tooling cite designs
by these ids. The verify script
`scripts/development-workflow/mockup-manifest-verify.sh` checks the manifest,
so a reviewer does not check ids or token mirroring by hand.

### File form

A manifest is data, never code. The file contains exactly one assignment of a
plain JSON object to the global name `window.__MOCKUP_MANIFEST__`. Comments
(`//` and `/* … */`) may come before and after it, and a closing semicolon is
allowed:

```js
// Mockups for the sign-in flow.
window.__MOCKUP_MANIFEST__ = {
  "$kind": "design-intent",
  "$status": "complete",
  "default_screen": "login-email",
  "frame": "phone",
  "navigation": [
    { "label": "Authentication", "items": [{ "screen_id": "login-email" }] }
  ],
  "screens": [
    {
      "screen_id": "login-email",
      "kind": "html",
      "states": [
        { "state_id": "empty", "initial": true },
        { "state_id": "invalid", "label": "Validation error" }
      ]
    }
  ]
};
```

The file is not readable as data when it holds any other code (a function
wrapper, a second statement, a different global name), when the assigned value
is not valid JSON (a JavaScript object literal with unquoted keys, single
quotes or trailing commas, comments inside the value, `NaN`, a duplicate key),
or when the file is not UTF-8. The assigned value must be a JSON object. The
verify script reads the file as data and never runs, imports or evaluates it,
so it needs no JavaScript runtime.

### Top-level fields

| Field | Required | Accepted values |
| --- | --- | --- |
| `$kind` | Yes | `design-intent` (Design intent) or `reproduction` (Reproduction): the mockup kind of the whole file. |
| `$status` | Yes | `complete` (Complete: every screen is listed) or `skeleton` (Skeleton: a partial inventory). It records completeness and changes no check. |
| `default_screen` | Yes | A `screen_id` that exists in `screens`. |
| `frame` | Yes | `phone` (Phone), `desktop` (Desktop) or `browser` (Browser, which can show a `url`). |
| `viewports` | No | A non-empty list of review presets, each with `id`, `label`, `width` and `height`. |
| `navigation` | Yes | The flow-drawer navigation tree: a list of groups. It may be empty. |
| `screens` | Yes | A non-empty list of the real screens. |

### Screen fields

| Field | Required | Accepted values |
| --- | --- | --- |
| `screen_id` | Yes | An English kebab-case slug, unique across the manifest's screens. |
| `kind` | Yes | `html` (HTML) or `image` (Image, an exported image): the screen's content type, not the mockup kind. |
| `export` | When `kind` is `image` | The path of the exported image. |
| `route` | No | The app router path. |
| `nav_screen` | No | The `screen_id` the flow drawer highlights; it must exist in `screens`. |
| `dom_id` | No | The screen's page element id, needed only when it differs from `s-<screen_id>`. |
| `title` | No | A readable metadata title. |
| `url` | No | The address shown in a `browser` frame. |
| `design_ref` | No | The design-tool frame name. It is never used as the `screen_id`. |
| `state_label` | No | A title for the screen's state group. |
| `states` | No | The screen's local states. When present it is a non-empty list. |

### State fields

| Field | Required | Accepted values |
| --- | --- | --- |
| `state_id` | Yes | A slug, unique within its screen. The same id may appear under other screens. |
| `initial` | No | `true` or `false`. Exactly one state of the screen sets it to `true`. |
| `label` | No | A readable state-selector label. |
| `title` | No | A metadata title that temporarily replaces the screen title. |

**Value types.** Every entry of `screens`, `states` and `viewports` is an
object. Every text field (`export`, `route`, `nav_screen`, `dom_id`, `title`,
`url`, `design_ref`, `state_label`, and the `label` of a state, a navigation
group, a navigation entry or a viewport) is a non-empty string when present.

### Rules

- **A state is not a screen.** A visual variant (an empty form, a validation
  error, an open modal) is a state of the screen that owns it, never another
  screen; `navigation` and `screens` name real destinations only. A state
  never declares a screen-level field: `screen_id`, `kind`, `export`, `route`,
  `nav_screen`, `dom_id`, `url`, `design_ref`, `state_label` or `states`. Only
  `title` is shared, because a state has its own `title`.
- **Slugs.** A `screen_id`, a `state_id` and a viewport `id` are lowercase
  ASCII letters and digits in hyphen-separated groups, starting with a letter,
  for example `login-email`, `resend-ready` or `step-2`. A design-tool frame
  name is never a valid `screen_id`.
- **Navigation.** `navigation` is a list of groups. A group is an object with
  a required `label` and a required `items` list of entries. An entry is an
  object with a required `screen_id`, an optional `label` and an optional
  `items` list of nested entries, to any depth. Any `items` list may be empty.
  Every `screen_id` cited at any depth exists in `screens`; a screen need not
  appear in the navigation. A navigation label may name a router path or a
  product section.
- **Viewports.** When present, `viewports` is a non-empty list. Viewport ids
  are unique slugs, every viewport has a `label`, and `width` and `height` are
  positive whole numbers. A viewport is a review setting, never a state.
- **Unknown fields.** Fields this contract does not define, such as notes or
  timestamps, are ignored and do not change the outcome. The one exception is
  the screen-level fields a state must not declare.
- **Language.** Structure text (ids, labels, navigation entries, state group
  titles) is English, and a `label` is left out when it would only restate
  its id. Content is in the product's language. The verify script checks only
  the slug form of ids; whether a label is English is not machine-checkable.

### Links

A screen and state are linked as `#screen=<screen_id>&state=<state_id>`. A
link without `state` opens the screen's initial state, or the screen itself
when it has no states. The viewer may add review settings such as the
viewport; they never change which screen or state is named.

### Token mirroring

A Design intent manifest mirrors every token of the token file in its page's
`:root` style rules. A Reproduction is not checked, because it harvests the
running app's stylesheet.

- **Where the files are.** The page is `index.html` in the manifest's folder.
  The token file is `tokens.json` in the folder that contains the `mockups`
  folder holding the manifest: `design/tokens.json` for every repository type,
  or `<design root>/tokens.json` under a configured design root.
- **Names and values.** A token is a value at any depth of the token file that
  is not an object. Keys starting with `$` are metadata, and nothing under
  them is a token. The property name is `--` followed by the token's path
  joined by hyphens, so `color.primary` becomes `--color-primary`. The value
  must equal the token's value, ignoring only surrounding whitespace. A CSS
  comment counts as one space, as in a browser, so a comment around a value is
  ignored and a comment inside it (`#ff/**/ffff`) is a mismatch. A token
  whose value is not a string is a problem. Extra properties are allowed.
- **What is read.** Plain `:root` rules (a style rule whose selector list has
  `:root` as one of its selectors) in the page's own `<style>` blocks and in
  stylesheets the page links with a relative path inside the repository,
  including declarations nested in at-rules such as media queries, and the
  root element's `style` attribute. Every declaration of a token's property
  there must carry the token's value, and a declaration marked `!important` is
  a problem.
- **Stated limitation.** The check is static: it reads declarations and does
  not model the cascade or render the page. Other selectors that can match the
  root element (such as `html`, `:root.dark` or an attribute selector),
  stylesheets brought in by `@import` or from outside the repository, and
  scripts that change properties at run time are not read, so a token declared
  only there is reported missing.
- **Problems.** For a Design intent manifest, a missing or unreadable page, a
  linked in-repository stylesheet that is missing or unreadable, a missing or
  unreadable token file, a token file that is not a JSON object, and a
  manifest that is not inside a `mockups` folder are each a problem.

### Checklist and verify script

The checklist below is what `mockup-manifest-verify.sh` performs:

1. Navigation ids exist in `screens`.
2. States are local to their screen and unique within it.
3. Every screen with states has exactly one initial state.
4. No state carries a screen-level field.
5. For Design intent, every token is mirrored in `:root`.

Beyond the checklist, the script checks every field rule on this page: the
file form, required fields, accepted values, value types, slugs and
viewports. It reports every problem in one run, once the file is readable as
data, and changes no file.

<!-- workflow-shell-contract: bash -->
```bash
bash scripts/development-workflow/mockup-manifest-verify.sh manifest design/mockups/<app>/mockup-manifest.js
```

| Subcommand | Arguments | Answers |
| --- | --- | --- |
| `manifest` | `<manifest-path> [--repo-root <dir>]` | Whether one manifest conforms. Works whether or not the project is opted in. |
| `tree` | `[--repo-root <dir>]` | Whether every manifest under the design root's `mockups` folder conforms, except the shared viewer folder `mockups/shared/`. Runs only when the project is opted in. |
| `inventory` | `<manifest-path> [--repo-root <dir>]` | The screen and state ids a spec may cite, the initial state of each screen, and each link. |
| `resolve` | `<manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]` | Whether one citation resolves. |

Output is `KEY=value` lines. Each problem is one
`PROBLEM=<rule> <place>: <detail>` line naming the rule, the place (screen,
state, viewport or navigation entry), the value found or its absence, and
what was expected.
Exit 0 is a non-failing outcome, 1 a failing one, and 2 a caller or
environment error. The scripts README lists every key.

| Code value | Display label | Failing | Meaning |
| --- | --- | --- | --- |
| `conforms` | Conforms | No | The manifest, or every manifest in the tree, passes every check. |
| `does_not_conform` | Does not conform | Yes | At least one problem; every problem is named. |
| `not_opted_in` | Not opted in | No | Tree check only: the project is not opted in; nothing was checked. |
| `invalid_configuration` | Invalid configuration | Yes | Tree check only: the `design` block is unusable; nothing was checked. |
| `no_mockups_found` | No mockups found | No | Tree check only: opted in, with no manifest yet. |

A tree check also fails when a folder under `mockups` cannot be read, or is a
symlink, because the search would be incomplete; each such folder is named.

| Code value | Display label | Meaning |
| --- | --- | --- |
| `resolves` | Resolves | The screen, or the screen and state pair, exists. |
| `does_not_resolve` | Does not resolve | Unknown screen, or a state the named screen does not have. |
| `cannot_check` | Cannot check | The manifest does not conform, so no inventory or citation answer is given. |

A caller treats Does not resolve and Cannot check as a broken citation. A
manifest that does not conform never yields an inventory.

Worked examples, valid and invalid, are the
[verify script's fixtures](../../../scripts/development-workflow/tests/fixtures/mockup-manifest-verify/).

## Forthcoming

These parts of the framework are delivered by later items and are not part of
this contract yet:

- Viewer and shell — #2207.
- Setup bootstrap — #2208.
- Adoption in an existing repository — #2214.
