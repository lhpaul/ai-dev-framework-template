# Mockup framework: manifest contract and verify script — Spec

**Depends on**: 2211-mockup-framework-layout

## Overview

Screens and states have no stable identity in the workflow. A spec or a review
cannot point at "the login screen in its invalid state" except in prose or with
a screenshot. The HTML Mockup Framework already has a manifest that names every
screen and its local states, but its contract lives only in the vault standard,
and its checks are a manual checklist that a reviewer applies by eye.

This item moves the manifest contract into the template, where #2211 put the
rest of the framework contract, and makes it checkable. The manifest checks ship
as a verify script, with the checklist as its readable description. The script
also lists the screen and state ids a spec may cite and says whether a cited id
resolves. The review gate (#2212), adoption (#2214) and the pilot (#2215) call
it. The verify script cannot rely on an LLM reviewer checking id uniqueness or
token mirroring by hand.

Nothing changes for a repository that does not opt in. The template itself has
no UI, stays not opted in, and tests the script against fixture manifests.

Source: issue #2206, epic #1470 decisions of 2026-11-24, and the human
decisions recorded for this item on 2026-11-26.

## Resolved Decisions

The template owner decided these before this spec. They are product constraints
for this spec and are not reopened here:

- **D1: The template is the canonical owner** (#1470 decision 1). The manifest
  contract goes into the template's framework reference. The vault standard
  keeps the rationale and history and points to the template for the contract.
- **D2: Opt-in scaffold distribution** (#1470 decision 2). Template sync never
  creates, changes or deletes a project's own design tree. Fixture manifests
  for this item are test material and are not a design tree.
- **D3: The manifest is data, never code** (decided 2026-11-26). A conforming
  manifest file assigns one plain JSON object to the global manifest name. Only
  comments may surround that assignment. The verify script reads the file as
  data and never runs it. It needs nothing beyond what the workflow helpers
  already require, so no JavaScript runtime or package install. Some manifests
  in consumer repositories do not conform today: RADAR writes a JavaScript
  object literal, and Leasity wraps JSON in a function and uses kind and
  status values outside the contract. They are migrated later in adoption
  (#2214) or the pilot (#2215). This item does not touch them.
- **D4: The vault edit is the owner's** (decided 2026-11-26). This item does
  not edit the vault. The implementation pull request carries the exact
  replacement text for the vault standard's Manifest section, which becomes a
  pointer to the template reference. The template owner applies it in the
  vault.
- **D5: #2206 is orthogonal to #2208** (decided 2026-11-26). Project-setup
  bootstrap depends on #2211 and #2207, not on this item, and this item does
  not depend on it.

Derived from those sources by this spec, and open to override at spec review:

- **D6: The token mirroring rule is name-and-value.** The vault rule "tokens
  are mirrored in `:root`" names no mapping from a token to a style property.
  Today one consumer mirrors `surface0` as `--s0`. That cannot be checked
  without a mapping table kept by hand. This spec fixes one rule: a token's
  path in the token file, joined by hyphens, is the property name, and the
  value must match. Consumers whose names differ migrate in adoption (#2214),
  as with D3.
- **D7: Manifest checks do not depend on the opt-in, and the tree check does.**
  A maintainer can verify a named manifest in any repository, which adoption
  needs before the project opts in. Checking a whole design tree follows
  #2211's rule that stages gate on the opt-in block: a project that is not
  opted in is reported as such and nothing is checked.

## Use Cases

### Use Case 1: Learn the manifest contract from the template

**Actor**: A maintainer of the template or of a consumer project who writes or
reviews a mockup.
**Preconditions**: The template version that includes this item is available.

**Steps**:

1. The maintainer opens the framework reference.
2. The Manifest section shows the file form, the top-level fields, the screen
   fields, the state fields, the rules between them, the link format and the
   checklist.
3. The maintainer writes or corrects a manifest against it.

**Postconditions**: The maintainer knows what makes a manifest conform, and
that the checklist is what the verify script checks.

**Information shown**:

- The file form: one plain JSON object assigned to the global manifest name,
  with only comments around it (D3).
- Every field with its accepted values, its display label where it has one,
  and whether it is required.
- The rule that a visual variant (an empty form, a validation error, an open
  modal) is a state of its screen, never another screen, and that a state
  never carries screen-level fields.
- The link format `#screen=<screen_id>&state=<state_id>`.
- The language rule: structure (ids, labels, navigation entries) in English,
  content in the product's language.
- The checklist, stated as the checks the verify script performs.

**Actions available**:

- Follow a link from the reference to the fixture manifests as worked
  examples.

**Considerations**:

- The viewer and shell (#2207) are still named as forthcoming. The reference
  does not describe how the viewer renders the manifest.

### Use Case 2: Verify one manifest

**Actor**: A maintainer, or a workflow stage acting for an agent (the review
gate #2212, adoption #2214, the pilot #2215).
**Preconditions**: A manifest file path is known. The repository may or may
not be opted in.

**Steps**:

1. The actor runs the verify script on the manifest.
2. The script reads the manifest as data and applies every check.
3. The script reports Conforms, or Does not conform with every problem named.

**Postconditions**: The actor knows whether the manifest conforms and, if not,
exactly what to fix. No file has changed.

**Information shown**:

- The outcome with its display label.
- For each problem: the manifest, where in it the problem is (for example
  screen `login-email`, state `invalid`), which rule failed, the value found
  (or that it is absent) and what was expected.

**Actions available**:

- None beyond reading the result; the script changes nothing.

**Considerations**:

- A file that is missing or cannot be read, or is not readable as data (not
  the D3 form, invalid JSON, or not an object), does not conform. The script
  reports that single reason, because no field can be checked.
- Every other problem is reported in one run, not only the first one.

### Use Case 3: Verify the design tree of an opted-in project

**Actor**: A maintainer or a workflow stage.
**Preconditions**: The actor runs the script on a repository rather than on
one manifest.

**Steps**:

1. The script reads the project's opt-in outcome (#2211).
2. If the project is opted in, the script verifies every manifest in the
   design tree's mockups folder.
3. The script reports one overall outcome and the outcome of each manifest.

**Postconditions**: The actor knows whether the whole tree conforms, or why
nothing was checked.

**Information shown**:

- The overall outcome with its display label.
- For Invalid configuration, the opt-in problems as #2211 reports them.
- For each manifest checked, its path, its outcome and its problems.

**Considerations**:

- A project that opted in with only the scaffold has no manifests yet. That is
  reported as No mockups found, which is not a failure.

### Use Case 4: List the ids a spec may cite, and check a citation

**Actor**: A spec or plan author, or a later stage that checks citations
(#2209, #2212, #2213).
**Preconditions**: A conforming manifest.

**Steps**:

1. The actor asks the script for the manifest's id inventory.
2. The script lists every screen id with its state ids, marks the initial
   state of each screen, and gives the link for each screen and state.
3. Later, the actor asks whether a cited screen, or a screen and state pair,
   resolves in that manifest.
4. The script answers Resolves or Does not resolve, and names what is unknown.

**Postconditions**: The actor can cite designs by id and can tell when a
citation is broken.

**Considerations**:

- If the manifest does not conform, the script lists no inventory and
  resolves no citation. It reports Cannot check and names the manifest
  outcome, so a broken manifest never passes as an empty or valid inventory.
- Writing citations into specs and plans, and deciding when a stage must
  check them, is #2209 and later items.

## Business Rules

- BR1 (data only): A manifest file is named `mockup-manifest.js`. It is in
  the data form only when it contains exactly one assignment of a JSON value
  to the global manifest name `window.__MOCKUP_MANIFEST__`. Comments may come
  before and after it, and a closing semicolon is allowed. Any other code, or
  an assigned value that is not valid JSON, makes the file not readable as
  data. The assigned value must also be a JSON object (verification table
  row 3). The verify script never runs, imports or evaluates a manifest (D3).
- BR2 (top-level fields): The top-level object has these fields:

  | Field | Required | Rule |
  | --- | --- | --- |
  | `$kind` | Yes | `design-intent` or `reproduction`: the mockup's kind, for the whole file. |
  | `$status` | Yes | `complete` or `skeleton`. |
  | `default_screen` | Yes | A `screen_id` that exists in `screens`. |
  | `frame` | Yes | `phone`, `desktop` or `browser`. |
  | `viewports` | No | A list of review presets, each with `id`, `label`, `width` and `height`. |
  | `navigation` | Yes | The flow-drawer navigation tree: a list of groups (BR7). It may be empty. |
  | `screens` | Yes | A non-empty list of the real screens. |

  `$status` records how complete the inventory is. It does not change which
  checks run.

- BR3 (screen fields): Each entry in `screens` has these fields:

  | Field | Required | Rule |
  | --- | --- | --- |
  | `screen_id` | Yes | An English kebab-case slug (BR6), unique across the manifest's screens. |
  | `kind` | Yes | `html` or `image`: the screen's content type, not the mockup kind. |
  | `export` | When `kind` is `image` | The path of the exported image. |
  | `route` | No | The app router path. |
  | `nav_screen` | No | The `screen_id` the flow drawer highlights; it must exist in `screens`. |
  | `dom_id` | No | The screen's page element id, needed only when it differs from `s-<screen_id>`. |
  | `title` | No | A readable metadata title. |
  | `url` | No | The address shown in a `browser` frame. |
  | `design_ref` | No | The design-tool frame name. It is never used as the `screen_id`. |
  | `state_label` | No | A title for the screen's state group. |
  | `states` | No | The screen's local states (BR4). When present it is a non-empty list. |

- BR4 (state fields): Each entry in a screen's `states` has these fields:

  | Field | Required | Rule |
  | --- | --- | --- |
  | `state_id` | Yes | A slug (BR6), unique within its screen. The same id may appear under other screens. |
  | `initial` | No | `true` or `false`. Exactly one state of the screen sets it to `true`. |
  | `label` | No | A readable state-selector label. |
  | `title` | No | A metadata title that temporarily replaces the screen title. |

- BR5 (a state is not a screen): A state never declares a screen-level
  field: any field of BR3 except `title`, which BR4 also defines for a state.
  The forbidden set is `screen_id`, `kind`, `export`, `route`, `nav_screen`,
  `dom_id`, `url`, `design_ref`, `state_label` and `states`. Each one found on
  a state is a problem. The vault standard named only the first five of these
  and ended its list with an ellipsis; the contract states the whole set. A
  visual variant (an empty form, a
  validation error, an open modal) is a state of the screen that owns it.
  `navigation` and `screens` name real destinations only.
- BR6 (slugs): A `screen_id`, a `state_id` and a viewport `id` are lowercase
  ASCII letters and digits in hyphen-separated groups, starting with a letter,
  for example `login-email`, `resend-ready` or `step-2`. A design-tool frame
  name is never a valid `screen_id`.
- BR7 (navigation tree): `navigation` is a list of groups. A group is an
  object with a required `label` and a required `items` list of entries. An
  entry is an object with a required `screen_id`, an optional `label`, and an
  optional `items` list of nested entries, to any depth. Any `items` list may
  be empty. Every `screen_id` cited at any
  depth exists in `screens`. A screen need not appear in the navigation. A
  navigation label may name a router path or a product section. This is the
  shape every reference manifest already uses (RADAR, Leasity, MOME and Zeki,
  read on 2026-11-26), so the contract records it rather than inventing one.
- BR8 (viewports): When `viewports` is present, it is a non-empty list.
  Viewport ids are unique and follow BR6, every viewport has a `label`, and
  `width` and `height` are positive whole numbers. A viewport is a review
  setting, never a state.
- BR9 (link format): A screen and state are linked as
  `#screen=<screen_id>&state=<state_id>`. A link without `state` opens the
  screen's initial state, or the screen itself when it has no states. The
  viewer (#2207) may add review settings such as the viewport. They never
  change which screen or state is named.
- BR10 (token mirroring, design intent only): For a Design intent manifest,
  every token in the design tree's token file appears in the mockup page's
  `:root` style rules. The rules are read from the page's own style blocks and from
  stylesheets it links inside the repository. The property name is `--`
  followed by the token's path joined by hyphens (`color.primary` becomes
  `--color-primary`). The value is the token's value, with only surrounding
  whitespace ignored. When the page declares a property more than once, the
  last declaration in page order counts, as in a browser. A token is a value
  at any depth that is not an object. Keys starting with `$` are metadata, and
  nothing under them is a token. A token whose value is not a string is a
  mirroring problem that names the token. Extra properties in the `:root`
  rules are allowed (D6). A Reproduction manifest is not
  checked for mirroring, because it harvests the running app's stylesheet
  (#2211 BR10).
- BR11 (where the token file and page are): The mockup page is `index.html`
  in the manifest's folder. The token file is `tokens.json` in the folder that
  contains the `mockups` folder holding the manifest. That rule finds
  `design/tokens.json` in every #2211 repository type, and
  `<design root>/tokens.json` under a configured design root. For a Design
  intent manifest, each of these is a mirroring problem: a missing or
  unreadable page, a missing or unreadable token file, a token file that is
  not a JSON object, and a manifest that is not inside a `mockups` folder, so
  that no token file can be located.
- BR12 (unknown fields): Fields the contract does not define, such as notes or
  timestamps, are ignored and do not change the outcome. The one exception is
  the screen-level fields BR5 forbids in a state.
- BR13 (all problems at once): After the file checks (rows 1 to 3 of the
  manifest verification table) pass, every check runs, and the result lists
  every problem found.
- BR14 (read-only): The verify script creates, changes and deletes nothing. It
  does not use the network, and it reads the files again on every run.
- BR15 (language): Structure text (ids, labels, navigation entries, state
  group titles) is English. A `label` is left out when it would only restate
  its id. Content is in the product's language. The reference documents this
  rule; the script checks only the slug form of ids (BR6), because whether a
  label is English is not machine-checkable.
- BR16 (citations fail closed): An id inventory or a citation check needs a
  conforming manifest. Otherwise the answer is Cannot check, never an empty
  inventory or a guess.
- BR17 (tree check gates on the opt-in): The tree check verifies manifests
  only when the project is Opted in (#2211). The manifests checked are every
  `mockup-manifest.js` file in the design root's `mockups` folder and its
  subfolders, except the shared viewer folder `mockups/shared/`. Each
  manifest's own `$kind` governs its checks; a difference from the kind
  configured in the `design` block is not a problem (#2211 Kind precedence).
- BR18 (canonical owner): After this item, the template reference is the
  manifest contract. The vault standard's Manifest section becomes a pointer,
  and its Tooling section's verify note points to the template (D1, D4).
- BR19 (value types): Every entry of `screens`, `states` and `viewports` is an
  object. Every field whose rule in BR2 to BR4 is text (`export`, `route`,
  `nav_screen`, `dom_id`, `title`, `url`, `design_ref`, `state_label`,
  `label`) is a non-empty string when present. A value of another type is a
  problem that names the field and the type found.

### Manifest verification table

Rows 1 to 3 are evaluated in order, and the first match decides the outcome
with that single problem. If none of them match, every check in row 4 runs.

| # | Situation | Outcome |
| --- | --- | --- |
| 1 | The manifest file does not exist or cannot be read | Does not conform (manifest file not found or unreadable) |
| 2 | The file is not the single BR1 assignment surrounded only by comments, or the assigned value is not valid JSON | Does not conform (not readable as data) |
| 3 | The assigned JSON value is not an object | Does not conform (manifest is not an object) |
| 4 | Every check of BR2 to BR8, BR10 to BR12 and BR19 | Conforms when no check finds a problem; otherwise Does not conform, listing every problem |

### Tree verification table

Rows are evaluated in order, and the first match decides the outcome.

| # | Situation | Outcome |
| --- | --- | --- |
| 1 | The opt-in outcome is Not opted in | Not opted in (nothing checked) |
| 2 | The opt-in outcome is Invalid configuration | Invalid configuration (opt-in problems listed, nothing checked) |
| 3 | Opted in, and the mockups folder, or any folder below it that BR17 searches, exists but cannot be read, or whether the mockups folder exists cannot be determined | Does not conform (each unreadable folder named; every manifest that could be read is still checked and listed) |
| 4 | Opted in, and the design tree has no manifest under BR17 (including a mockups folder confirmed missing) | No mockups found |
| 5 | Opted in, and every manifest found conforms | Conforms |
| 6 | Opted in, and one or more manifests found do not conform | Does not conform (each failing manifest and its problems listed) |

Row 3 comes before rows 4 and 5 because an unreadable folder means the search
is incomplete: the check can prove neither that no manifest exists nor that
every manifest conforms, so it fails rather than pass.

### Citation table

| # | Situation | Answer |
| --- | --- | --- |
| 1 | The manifest does not conform | Cannot check (names the manifest outcome) |
| 2 | The cited screen is not in the manifest | Does not resolve (unknown screen) |
| 3 | A state is cited, and the screen has no state with that id | Does not resolve (unknown state for that screen) |
| 4 | Otherwise | Resolves |

Rows 2 to 4 are evaluated only when row 1 does not match, in order.

## UX Rules

These rules cover the reference page and the messages the script shows.

- A problem message names the manifest, the place (screen, state, viewport or
  navigation entry, by id when it has one), the rule, the value found or its
  absence, and the accepted values. A maintainer can fix it without reading
  code.
- A file-level message says why: file missing or unreadable, code other than
  the single assignment, invalid JSON, or not an object. It does not echo the
  file's content.
- Each outcome is shown with its display label from the tables below.
- The reference and the script use the same names for every field, rule and
  outcome.

## Statuses / Enum Values

**Manifest values** (spelling fixed by the vault standard and #1470):

| Field | Code value | Display label | Description |
| --- | --- | --- | --- |
| Mockup kind (`$kind`) | `design-intent` | Design intent | Hand-authored from the spec; the token file is the source. |
| Mockup kind (`$kind`) | `reproduction` | Reproduction | Generated from the running app; the app's stylesheet is the source. |
| Inventory status (`$status`) | `complete` | Complete | The manifest lists every screen of the mockup. |
| Inventory status (`$status`) | `skeleton` | Skeleton | The manifest is a partial inventory still being filled in. |
| Frame (`frame`) | `phone` | Phone | Rendered in a phone frame. |
| Frame (`frame`) | `desktop` | Desktop | Rendered at desktop width with no device frame. |
| Frame (`frame`) | `browser` | Browser | Rendered in a browser window that can show a `url`. |
| Screen content (`kind`) | `html` | HTML | The screen is HTML content. |
| Screen content (`kind`) | `image` | Image | The screen shows an exported image named by `export`. |

**Verification outcomes**:

| Display label | Failing | Meaning |
| --- | --- | --- |
| Conforms | No | The manifest, or every manifest in the tree, passes every check. |
| Does not conform | Yes | At least one problem; every problem is named. |
| Not opted in | No | Tree check only: the project is not opted in; nothing was checked. |
| Invalid configuration | Yes | Tree check only: the opt-in block is unusable; nothing was checked. |
| No mockups found | No | Tree check only: opted in, with no manifest yet. |

**Citation answers**: Resolves; Does not resolve; Cannot check. A caller treats
Does not resolve and Cannot check as a broken citation.

**Valid transitions**: There is no stored state. Every run reads the files
again (BR14), so an outcome changes only when the files change.

## Template-Fit Check and Consumer Sync Impact

**Template-Fit Check (Protocol 02 Step 0, pre-assessed here):** passes. The
manifest is part of the stack-agnostic framework #2211 placed in the template.
The check reads plain files with the tools the workflow already needs, and it
does nothing in a project that does not call it. The plan stage runs the check
again.

**Sync impact by surface:**

| Surface | Sync treatment | Effect on a consumer that is not opted in |
| --- | --- | --- |
| Manifest section of the framework reference | Always synced (workflow docs tree) | New documentation only. |
| Verify script | Placement decided in the plan. It must reach a synced consumer's workflow stages without copying the scaffold. | Additive. It runs only when called. The tree check reports Not opted in. |
| Fixture manifests and their tests | Test material; placement decided in the plan | No design tree is created or changed (D2). |
| Vault standard | Outside the template repository (D4) | None. |

If the plan registers new files in the sync manifest, it records the category
and scope of each one. It also confirms that none of them makes sync write a
consumer's design tree.

## Dependencies and Related Items

- **Depends on**: #2211 (merged in #2228). It provides the design layout, the
  token file location and the opt-in outcome that the tree check reads.
- **Depend on this item** (each brief states it): #2209, #2212, #2210, #2207,
  #2213 and #2216. #2214 and #2215 call the verify script per #1470's
  sub-item list.
- **Orthogonal**: #2208 (D5).

## Acceptance Criteria

### Framework reference

- [ ] AC1: The framework reference has a Manifest section that documents the
  file form (BR1), every top-level, screen and state field with its
  requirement and accepted values (BR2 to BR4, BR8, BR19), and the rules of
  BR5 to BR7, BR9 to BR12 and BR15.
- [ ] AC2: The Manifest section states the checklist (navigation ids exist in
  screens, states are local and unique, exactly one initial state, no
  screen-level fields in a state, tokens mirrored for design intent) and says
  that the verify script performs it. It links to the fixture manifests as
  examples.
- [ ] AC3: The reference no longer lists the manifest contract and verify
  script as forthcoming. The viewer and shell (#2207) are still listed.

### Verify one manifest

- [ ] AC4: The verify script reports Conforms for a valid Design intent
  fixture. That fixture has several screens, a screen with states and one
  initial state, a nested navigation tree, viewports and an image screen. Its
  token file has a `$`-prefixed metadata key, and its page mirrors every token,
  some of them in a stylesheet it links inside the repository.
- [ ] AC5: The verify script reports Conforms for a valid Reproduction fixture
  whose page does not mirror the token file.
- [ ] AC6: For each of these invalid fixtures, the verify script reports Does
  not conform and names the matching problem: missing file; code other than the
  single assignment (a function wrapper); a JavaScript object literal that is
  not JSON; a JSON value that is not an object; missing or unknown `$kind`
  (including `design intent` with a space); missing or unknown `$status`;
  unknown `frame`; `default_screen` not in `screens`; empty `screens`;
  duplicate `screen_id`; a `screen_id` that is not a slug; missing or unknown
  screen `kind`; an image screen without `export`; a `title` that is not a
  string; an empty `states` list; a state without `state_id`; `navigation` that is not a
  list; a navigation group without `label`; a navigation group without `items`; a navigation entry without
  `screen_id`; a navigation entry citing an unknown screen at a nested depth; a `nav_screen` citing an unknown screen;
  duplicate `state_id` within a screen; a screen with states and no initial
  state; a screen with two initial states; a state declaring `route`; a
  state declaring `export`; a state declaring nested `states`; a
  duplicate viewport id; a viewport with a non-positive width; a Design intent
  page missing one token; a Design intent page with one token at a different
  value; a Design intent token file with a token that is not a string; a
  Design intent manifest whose token file is missing; a Design intent manifest
  whose token file is not valid JSON; a Design intent manifest whose token file
  is not a JSON object; a Design intent manifest with no `index.html` beside
  it; a Design intent manifest that is not inside a `mockups` folder.
- [ ] AC7: The same `state_id` under two different screens conforms.
- [ ] AC8: A fixture with several problems reports every problem in one
  result. Each problem names its place, rule, found value or absence, and the
  expected values.
- [ ] AC9: A manifest with unknown extra fields at the top level, on a screen
  and on a state still conforms, apart from the BR5 fields.
- [ ] AC10: The verify script never runs the manifest: a fixture whose body,
  if executed, would create a file, does not conform as not readable as data,
  and the file is not created.

### Tree check and citations

- [ ] AC11: In disposable test repositories, the tree check reports the
  outcome of the matching tree-table row for each of these: not opted in;
  invalid opt-in block; opted in with no manifests; opted in with all
  manifests conforming; opted in with one failing manifest among conforming
  ones (only that one is listed as failing); opted in with an unreadable
  subfolder of the mockups folder beside a conforming manifest (Does not
  conform, naming that folder). A manifest under `shared` is not checked.
- [ ] AC12: Run in the template repository, the tree check reports Not opted
  in.
- [ ] AC13: For a conforming fixture, the id inventory lists every screen id,
  each screen's state ids, the initial state, and the link of each screen and
  state in the BR9 format.
- [ ] AC14: The citation check answers Resolves for an existing screen and for
  an existing screen and state pair, Does not resolve for an unknown screen and
  for a state of another screen, and Cannot check for a non-conforming
  manifest.

### Safety and regression

- [ ] AC15: The verify script leaves the repository unchanged in every case of
  AC4 to AC14.
- [ ] AC16: The script runs with only the tools the workflow helpers already
  require; no JavaScript runtime or package install is needed.
- [ ] AC17: The automated workflow test suites that passed before this change
  still pass. No existing workflow helper changes its output.
- [ ] AC18: Applying the sync manifest's classification of every new or changed
  file to a disposable consumer without a design block creates no design tree
  and changes no configuration value.

### Vault hand-off

- [ ] AC19: The implementation pull request description contains the exact
  replacement text for the vault standard's Manifest section, and the verify
  note in its Tooling section. The replacement is a pointer to the template
  reference that keeps the rationale. The description says that the template
  owner applies it (D4).

## Brief Coverage

### Brief Objective List

| # | Objective (from #2206) |
| --- | --- |
| O1 | Top-level fields: `$kind` (`design-intent` or `reproduction`), `$status`, `default_screen`, `frame`, `viewports`, `navigation`, `screens` |
| O2 | Screen fields: `screen_id` as an English kebab-case slug, `route`, `dom_id`, `kind: html \| image`, `design_ref`, and the rest |
| O3 | State fields: `state_id`, `label`, exactly one `initial: true` |
| O4 | A state never carries screen-level fields; a visual variant is a state, not a screen |
| O5 | The hash format `#screen=<screen_id>&state=<state_id>` |
| O6 | The English structure and product-language content rule |
| O7 | The PR-check list: navigation ids exist in `screens`, states unique and local, one initial state, tokens mirrored in `:root` |
| O8 | Ship the PR checks as a verify script, with the checklist as its readable description |
| O9 | The review gate (#2212), adoption (#2214) and the pilot (#2215) call it |
| O10 | Test the script against fixture manifests (valid and invalid) in this repo |
| O11 | Expose the screen and state ids a spec may cite, so later stages can check that a citation resolves |
| O12 | Do not duplicate the vault standard's prose without the canonical-owner sync rule from #1470 |

### Coverage Matrix

| Objective | Covered by |
| --- | --- |
| O1 | AC1, AC4, AC5, AC6, BR2, BR8 |
| O2 | AC1, AC6, BR3, BR6, BR19 |
| O3 | AC1, AC6, AC7, BR4 |
| O4 | AC1, AC6, BR5 |
| O5 | AC1, AC13, BR9 |
| O6 | AC1, BR15 |
| O7 | AC2, AC6, BR7, BR10, BR11 |
| O8 | AC2, AC4 to AC10, BR13 |
| O9 | AC11, AC12 (tree check for callers); wiring the callers is Out of Scope (#2212, #2214, #2215) |
| O10 | AC4 to AC11, AC15 |
| O11 | AC13, AC14, BR16 |
| O12 | AC3, AC19, BR18, D1, D4 |

### Deferral Notes

- **O9 (the callers)**: Calling the script from the review gate, adoption and
  the pilot belongs to #2212, #2214 and #2215 per #1470's sub-item list. This
  item provides the checks they call. Human confirmation not requested (decided
  in #1470).
- **Migrating non-conforming consumer manifests** (RADAR, Leasity): deferred to
  #2214 or the pilot by the 2026-11-26 decision (D3). Human confirmation
  already given.
- **The vault edit**: done by the template owner from the text in the
  implementation pull request (D4). Human confirmation already given.

## Out of Scope (MVP)

- Changing any manifest in a consumer repository, or migrating a JavaScript
  object literal or function-wrapped manifest to the data form (#2214, #2215).
- Editing the vault standard (D4).
- The viewer, shell, `chrome=off`, the viewport switch and how the viewer
  reads the manifest (#2207).
- Calling the script from spec, plan, review, smoke, `design-reviewer`, setup
  or adoption (#2209, #2212, #2213, #2208, #2214).
- Checking that each screen's page element exists in `index.html`, or that an
  image screen's export file exists.
- Checking that labels are English or that they do not restate their ids.
- Generated reproduction manifests and their build or staleness check, pixel
  and byte gates, and the fidelity kit (#1470 out of scope; #1442).
- A token schema beyond the mirroring rule, and token tooling.
- Any change to CI workflows, reviewer configuration, checkpoint policy or the
  repository's workflow configuration.
