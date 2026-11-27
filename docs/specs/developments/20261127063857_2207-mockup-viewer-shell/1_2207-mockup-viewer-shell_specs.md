# Mockup framework: viewer and shell scaffold — Spec

**Depends on**: 2206-mockup-manifest-contract

## Overview

A mockup manifest names every screen and state, but nothing in the template
turns it into a page a reviewer can use. The HTML Mockup Framework's answer is
a shared viewer plus a fixed shell: a full-bleed product canvas with a pages
drawer on the left and an inspector drawer on the right, both rendered from
the manifest. RADAR, Leasity (two portals) and Zeki each carry their own copy,
and those copies have already drifted apart.

This item puts one viewer and one shell into the template's opt-in design
scaffold, with a working example mockup. It also adds an automated test that
opens that example over `file://` in a real browser, so the scaffold cannot
rot in a template that has no app of its own. The framework reference gains
the viewer and shell contract. Nothing changes for a repository that does not
copy the scaffold.

Source: issue #2207, epic #1470 decisions of 2026-11-24, the vault standard
`HTML Mockup Framework.md` (sections *Viewer frame modes*, *Full-bleed viewer
with edge drawers* and *`viewer.js` integration*), the RADAR and Leasity
reference shells read on 2026-11-27, and the human decisions recorded for this
item on 2026-11-27.

## Resolved Decisions

The template owner decided these before this spec. They are product
constraints for this spec and are not reopened here:

- **D1: The template is the canonical owner** (#1470 decision 1). The viewer
  and shell contract goes into the template's framework reference. The vault
  standard keeps the rationale and history and points to the template.
- **D2: Opt-in scaffold distribution** (#1470 decision 2). The viewer and the
  example shell ship inside the existing design scaffold. Template sync never
  copies the scaffold into a project and never creates, changes or deletes a
  project's own design tree. Setup (#2208) and adoption (#2214) are the ways a
  project gets it.
- **D3: The test runs in headless Chrome, with no package install** (decided
  2026-11-27). The automated test opens the example mockup over `file://` in
  the Google Chrome that the hosted Linux CI runners already provide, running
  headless. It installs no package and needs no change to the CI workflows. In
  CI, a missing Chrome fails the test. On a maintainer's machine without
  Chrome, the test shows a visible skip.
- **D4: Placement** (decided 2026-11-27). The viewer is the scaffold's shared
  viewer file. The scaffold's example app folder gets a starter page with the
  shell and a conforming manifest. That example is the fixture the test opens,
  so what ships is what is tested.
- **D5: Starting point** (decided 2026-11-27). The viewer starts from the
  RADAR reference viewer, as the issue requires. The viewport switch and the
  chrome-off mode, which RADAR does not have, are generalised from the Leasity
  `brokers-portal-next` shell.
- **D6: Fields outside the manifest contract** (decided 2026-11-27). The
  inspector's `updated`, `persona` and `forced` values come from manifest
  fields that #2206 does not define (BR12 there ignores them). The viewer
  shows them only when they exist: `updated` shows `—` when absent, and
  `persona` and `forced` rows appear only for a Reproduction, and only when
  the value exists.
- **D7: The vault edit is the owner's** (same rule as #2206 D4). This item does
  not edit the vault. The implementation pull request carries the exact
  replacement text for the vault standard's viewer sections. The template
  owner applies it.

Derived from those sources by this spec, and open to override at spec review:

- **D8: A Design intent mockup is full window until a viewport is chosen.**
  The vault standard says a Design intent `desktop` or `browser` frame is
  fluid and full-bleed, and also that a reviewer switches between declared
  viewports. This spec reconciles the two. With no viewport in the address, a
  Design intent frame fills the window. Choosing a viewport renders the
  product at that viewport's width and height, centred, with the canvas around
  it. A Reproduction that declares viewports always shows one of them, because
  the standard holds it to an exact size.
- **D9: Every declared viewport is available for every state.** The vault
  standard disables, rather than hides, a viewport that a state was not
  captured at. The manifest contract (#2206) has no field that says which
  viewports a state was captured at, so no viewport is ever disabled. That
  rule returns when a later item adds such a field (Out of Scope).
- **D10: An unresolvable address is corrected, not kept.** When the address
  names an unknown screen, state or viewport, the viewer opens the default it
  falls back to and rewrites the address to match what is shown. An address
  that leaves a value out is completed the same way. The address bar then
  never names something the canvas is not showing, and copying it always links
  to exactly what is shown.

## Use Cases

### Use Case 1: Start a mockup from the scaffold

**Actor**: A maintainer starting a design tree by hand, or setup (#2208) and
adoption (#2214) acting for one.
**Preconditions**: The template version that includes this item is available.

**Steps**:

1. The maintainer copies the scaffold into the project, as the reference's
   *Starting from the scaffold* section already describes.
2. The shared viewer folder now holds the viewer. The example app folder holds
   a starter page with the shell, a conforming manifest and the assets they
   use.
3. The maintainer opens the example page by double-clicking it (`file://`) or
   over a local HTTP server. It works with no build step and no install.
4. The maintainer renames the example app, replaces its screens with the
   product's own and edits its manifest.

**Postconditions**: The project has a working mockup that follows the shell
contract, without recreating the shell from memory.

**Information shown**:

- The example's product canvas with its default screen.
- The two edge controls, and, because the example declares several viewports,
  the viewport switch.

**Considerations**:

- The example is Design intent. Its page mirrors the scaffold's example token
  file, so the manifest verify script (#2206) reports Conforms for it.
- Copying the scaffold still does not opt the project in (#2211).

### Use Case 2: Review a mockup in the shell

**Actor**: A reviewer: a product owner, designer, engineer or reviewing agent.
**Preconditions**: A mockup page built on the shell, opened over `file://` or
HTTP.

**Steps**:

1. The page opens on the screen and state the address names, or on the
   default screen in its initial state when it names none.
2. The reviewer opens the pages drawer from the left edge control and selects
   a screen. The drawer closes and the canvas shows that screen in its initial
   state.
3. The reviewer opens the inspector from the right edge control, reads the
   screen's metadata and selects another state. The drawer closes and the
   canvas shows that state.
4. When the mockup declares several viewports, the reviewer uses the viewport
   switch to see the same screen and state at another size.
5. The reviewer copies the address to link to exactly what they are looking
   at.

**Postconditions**: The reviewer has seen every declared screen and state they
needed, and can link to each one.

**Information shown**:

- Pages drawer: the mockup's name as a heading, the link format
  `#screen=…&state=…` verbatim under it, and the navigation groups with their
  entries. The entry for the current screen, or for its navigation anchor, is
  highlighted, and the entries above it in the tree are marked as its parents
  (BR11).
- Inspector drawer: the heading `Inspector`, the current screen's states with
  the current one marked, and the metadata rows (BR10).
- The page title in the browser tab: the state's title when it has one,
  otherwise the screen's title, otherwise the screen id.

**Actions available**:

- Open or close either drawer; select a screen; select a state; switch
  viewport; follow or share a link.

**Considerations**:

- A screen with no states shows no state list, and the inspector says so.
- An address naming something unknown opens the fallback and corrects the
  address (D10).

### Use Case 3: Capture a screen without the reviewer shell

**Actor**: A capture or comparison tool, such as smoke and `design-reviewer`
(#2213) or the implementation comparison (#2216), or a person taking a
screenshot.
**Preconditions**: A mockup page built on the shell.

**Steps**:

1. The actor opens the page with `chrome=off` in the address, together with a
   screen, a state and, where declared, a viewport.
2. The page renders the product only, with no reviewer controls painted
   anywhere.
3. The actor selects another state or screen through the page. The product
   changes and the reviewer shell stays hidden.

**Postconditions**: Everything in the window is product, at the requested
size.

**Considerations**:

- The chrome-off mode is carried through every navigation the shell performs.
  A capture that selects a state after load must not bring the shell back.

### Use Case 4: Prove the scaffold still works

**Actor**: A template maintainer, or the template's CI: a pull request that
starts the workflow test harness, or the harness's nightly full run.
**Preconditions**: The template repository.

**Steps**:

1. The actor runs the viewer test suite.
2. The suite opens the scaffold's example mockup over `file://` in headless
   Chrome, with no server, and checks it against this spec's rules.
3. The suite reports Passed, Failed (naming each failed check), Skipped or
   Not applicable.

**Postconditions**: The actor knows whether the shipped scaffold works.

**Considerations**:

- In CI, a missing Chrome is a failure, never a skip (D3).
- In a repository without the scaffold, such as a synced consumer, the suite
  is Not applicable and never fails.
- Because no CI workflow changes (D3), the suite runs only where the existing
  workflow test harness already runs. A pull request that changes only
  scaffold files does not start the harness, so its CI coverage is the
  nightly full run (AC20).

## Business Rules

- BR1 (no build, two ways to open): A mockup built on the shell opens by
  double-clicking its page (`file://`) and over a local HTTP server. It needs
  no build step, no install and no network. The manifest is loaded as a
  classic script, so no data request is needed under `file://`. The reference
  documents both ways to open it, and says that the whole mockups folder (the
  shared viewer folder, the app folder and its assets) is shared together.
- BR2 (the viewer reads the manifest, the page owns the product): The viewer
  renders the pages drawer, the state list, the inspector rows, the viewport
  switch and the chrome-off mode from the manifest. Each app's page owns its
  product content, its screens and any product-specific behaviour, such as
  starting a wizard. The viewer never edits product content. It does not check
  the manifest either: the verify script (#2206) does.
- BR3 (viewer interface): The viewer is the file `mockups/shared/viewer.js`.
  It defines one global, `MockupViewer`, with the operations named by the
  framework and by the issue: `loadManifest` (load the manifest), `init`
  (initialise the viewer), `buildNav` (build the pages navigation),
  `buildDomMap` (map each screen to its page element), `getTargetFromUrl`
  (read the target from the address), `updatePanels` (update the drawers for a
  screen and state) and `updateMeta` (update the metadata). The reference
  names each with its purpose. Their exact signatures are decided in the plan,
  starting from the RADAR viewer (D5).
- BR4 (loading the manifest): The viewer takes the manifest the page's
  manifest script defined. When no manifest is found, or the manifest lists no
  screens, the canvas shows a visible message saying so. The page is never
  blank or silent.
- BR5 (address format and resolution): The address is the page's hash, in the
  form `#screen=<screen_id>&state=<state_id>&viewport=<viewport_id>&chrome=off`.
  Its keys are `screen` (a screen id), `state` (a state id of that screen),
  `viewport` (a declared viewport id) and `chrome` (only `off` has a meaning,
  BR15). Every key is optional. A key with an empty value counts as not given,
  and when a key repeats, its first occurrence counts. Other keys are ignored.
  A hash that contains no `=` is the legacy form `#<screen_id>`. The address
  resolution table and the viewport table below decide what opens. After every
  resolution the address is replaced with the canonical form of what is shown:
  the keys in the order above, `state` only when the screen has states,
  `viewport` only when the size shown is a viewport, and `chrome=off` only in
  chrome-off mode. Replacing the address on load or after a correction never
  adds a browser history entry, so going back never returns to an address that
  would be corrected again. Review settings never change which screen or state
  is named (#2206 BR9).
- BR6 (shell layout): The product canvas fills the whole window. The two
  drawers and the scrim are overlays fixed to the window. Opening or closing a
  drawer never resizes, moves or reflows the product canvas. The shell's
  controls are visibly distinct from the product and sit above it. The product
  is never placed inside a drawer.
- BR7 (drawer behaviour): Both drawers start closed. Opening one closes the
  other. A drawer closes when a screen or state is selected in it, when its
  close button is pressed, when the scrim is selected, and when `Escape` is
  pressed. The scrim covers the product while either drawer is open. The edge
  controls stay reachable at every declared viewport and at narrow window
  widths.
- BR8 (accessibility): Each edge control has an accessible name and says
  whether its drawer is open. Each drawer is labelled (`Pages`, `Inspector`)
  and is hidden from assistive technology while closed. Opening a drawer moves
  keyboard focus into it. Closing it returns focus to the control that opened
  it. Every control is a button that the keyboard can reach.
- BR9 (fixed drawer headers): The pages drawer header is a level-two heading
  with the mockup's name as a reader would say it, set by the page, followed by
  the link format `#screen=…&state=…` verbatim. The inspector header is a
  level-two heading `Inspector` with no subtitle. Each header has a close
  button.
- BR10 (inspector rows): The inspector shows these rows in this order, labelled
  with the lowercase field names:

  | Row | Value | When |
  | --- | --- | --- |
  | `screen` | The screen id | Always |
  | `state` | The state id, or `—` when the screen has no states | Always |
  | `route` | The screen's route, or `—` | Always |
  | `url` | The screen's URL, or `—` | `browser` frame only |
  | `kind` | The screen's content type, `html` when absent | Always |
  | `persona` | The manifest's `persona` value | Reproduction only, and only when present (D6) |
  | `forced` | The current state's `forced` value | Reproduction only, and only when present (D6) |
  | `updated` | The manifest's top-level `synced_at` value as written, or `—` | Always |

  The vault standard names these source fields. It does not say where a
  Reproduction manifest carries `persona`; the plan confirms that from the
  Leasity reference manifest (D5). The sync date is shown as written. The viewer does not convert it to a
  locale, because the shell's structure is English (#2206 BR15).
- BR11 (pages drawer): The pages drawer shows each navigation group under its
  label, with its entries in manifest order. A nested entry is indented under
  its parent. An entry without a label shows its screen id. The highlighted
  screen is the current screen's navigation anchor (`nav_screen`, #2206 BR3)
  when it names one, and otherwise the current screen itself. Every entry
  citing the highlighted screen is highlighted. When no entry cites it,
  nothing is highlighted. The entries above a highlighted one are marked as
  its parents.
- BR12 (state list): For a screen with one or more states, the inspector lists
  every state in manifest order under the screen's state-group title, or the
  screen title when it has none, or the screen id when it has neither. The current state is marked. A state without
  a label shows its state id. For a screen with no states, the inspector shows
  a short message that the screen has no local states.
- BR13 (frames): The manifest's frame decides how the product is framed.
  `desktop` and `browser` render the product full-bleed. `browser` adds a
  browser bar that shows the current screen's URL. `phone` centres a fixed
  device frame in the canvas. The browser bar and the device frame are part of
  the product frame, not the reviewer shell, so the chrome-off mode keeps
  them.
- BR14 (viewports): A mockup that declares more than one viewport shows a
  persistent viewport switch in the canvas, outside the drawers, above the
  product. The switch lists each viewport by its label and marks the active
  one. The viewport is part of the address, so a size can be linked. It is a
  review setting and never a state. Without declared viewports, or with only
  one, there is no switch. Every declared viewport is available for every
  state (D9). The size shown follows the viewport table below.
- BR15 (chrome-off mode): With `chrome=off` in the address, the page shows no
  edge control, no viewport switch, no drawer and no scrim, and `Escape` opens
  nothing. Every navigation the shell performs keeps `chrome=off` in the
  address. Any other value, or no value, means the shell is shown. A value
  other than `off` is dropped from the address.
- BR16 (navigation keeps the address in step): Every selection in the shell
  (a screen, a state, a viewport) updates the address and adds one browser
  history entry. Changing the address by
  hand, or with the browser's back and forward, updates the canvas and the
  drawers to match, using the same table.
- BR17 (missing screen content): When the page has no element for the
  resolved screen, the canvas shows a visible message naming the screen id,
  instead of an empty canvas. An image screen (`kind` `image`) needs no page
  element: the canvas shows the image at its `export` path, read from the app
  folder, with the screen's title, or its id, as the image's text
  alternative.
- BR18 (example mockup): The scaffold's example mockup is Design intent. It
  has at least two navigation groups, a nested navigation entry, a screen with
  several states and one initial state, a screen with no states, an image
  screen, a `browser` frame with a URL, and at least two viewports. Its page
  mirrors the scaffold's example tokens, so the verify script (#2206) reports
  Conforms for its manifest. Its structure text is English, and its content is
  short placeholder text a maintainer replaces.
- BR19 (the reference is the contract): After this item, the framework
  reference documents the viewer and shell contract (BR1 to BR17, and the
  tables below) and the two ways to open a mockup. It no longer lists the
  viewer and shell as forthcoming. The vault standard's viewer sections become
  a pointer (D1, D7).
- BR20 (test outcomes): The viewer test suite reports one outcome by the test
  outcome table below. A failure names each check that failed and what was
  seen.

### Address resolution table

Evaluate the screen first, then the state, then the viewport, then the chrome
mode. After resolution, the address is rewritten to the canonical form of what
opened (BR5, D10). "Default screen" is the manifest's default screen, or its first
screen when the default names no screen.

| # | Address | Screen opened | State opened |
| --- | --- | --- | --- |
| 1 | No screen given, and no legacy form | Default screen | Its initial state |
| 2 | A screen given that exists | That screen | Rows 6 to 8 |
| 3 | A screen given that does not exist | Default screen | Its initial state |
| 4 | Legacy form `#<screen_id>` naming a screen that exists | That screen | Its initial state |
| 5 | Legacy form naming no screen | Default screen | Its initial state |
| 6 | The opened screen has no states | — | None, and any state given is dropped |
| 7 | A state given that exists in the opened screen | — | That state |
| 8 | No state given, or one the opened screen does not have | — | The screen's initial state, or its first state when none is marked initial |

Rows 1 to 5 decide the screen; exactly one matches. Rows 6 to 8 then decide
the state; exactly one matches. A state given in the address counts only for
row 2. After rows 1, 3, 4 and 5 the opened screen is treated as if no state
were given, so row 6 or row 8 applies and any state given is dropped. A legacy
address is rewritten to the canonical form. A screen id is never read as
carrying a state.

### Viewport table

| # | Manifest and address | Size shown | Switch |
| --- | --- | --- | --- |
| 1 | No viewports declared | Full window (any viewport given is dropped) | None |
| 2 | One viewport declared, Design intent | Full window, or that viewport when the address names it | None |
| 3 | One viewport declared, Reproduction | That viewport | None |
| 4 | Several declared, Design intent, no viewport given | Full window | Shown, no viewport marked active |
| 5 | Several declared, Design intent, a declared viewport given | That viewport | Shown, that viewport active |
| 6 | Several declared, Reproduction, no viewport given | The first declared viewport | Shown, that viewport active |
| 7 | Several declared, Reproduction, a declared viewport given | That viewport | Shown, that viewport active |
| 8 | Viewports declared, and the address names one that is not declared | As if no viewport were given (rows 2, 3, 4 or 6), and the unknown value is dropped | As in that row |

Row 8 is checked first: an address naming an undeclared viewport is resolved
as if it named none. Otherwise exactly one of rows 1 to 7 matches. The Switch
column applies while the shell is shown. In chrome-off mode no switch is
painted (BR15), and the size shown is the same as with the shell shown.

"Full window" means the product fills the canvas, except a `phone` frame,
which shows its device frame at the first declared viewport's size, or at the
standard's phone size of 393 × 852 when none is declared. "That viewport"
means the product is rendered at exactly that width and height, centred in the
canvas. The product is laid out as it would be in a window of that size. The
product is never scaled. When that size is larger than the window, the canvas
scrolls so that every part of the product can be reached.

### Test outcome table

Rows are evaluated in order, and the first match decides the outcome.

| # | Situation | Outcome |
| --- | --- | --- |
| 1 | The repository has no design scaffold | Not applicable (nothing checked) |
| 2 | Chrome cannot be found, running in CI | Failed (Chrome not found) |
| 3 | Chrome cannot be found, not running in CI | Skipped (Chrome not found), shown visibly |
| 4 | Chrome is found and every check passes | Passed |
| 5 | Chrome is found and any check fails, or Chrome cannot open the page | Failed, naming each failed check |

## UX Rules

- The shell's structure text is English: headings, labels, row names, the
  viewport switch and every message. The example's product content is
  placeholder text (BR18).
- Shell controls never look like product navigation. They use a neutral style
  of their own and stay above the product.
- A drawer uses a bounded width that fits narrow windows, so the product is
  never pushed aside.
- Every message the shell shows (no manifest, missing screen content, no local
  states) says what is missing in one sentence. It never leaves a blank
  canvas.
- Screenshots and comparisons use `chrome=off`. Closing the drawers alone is
  not enough, because the edge controls stay painted over the product.

## Statuses / Enum Values

**Frame** (from the manifest contract):

| Code value | Display label | Description |
| --- | --- | --- |
| `phone` | Phone | A centred device frame. |
| `desktop` | Desktop | The product full-bleed, with no device frame. |
| `browser` | Browser | The product full-bleed, under a browser bar showing the screen's URL. |

**Chrome mode** (address setting):

| Code value | Display label | Description |
| --- | --- | --- |
| absent | Shell shown | The reviewer shell is shown. |
| `off` | Chrome off | No reviewer shell is painted; for captures. |

**Size shown** (viewport table):

| Value | Display label | Description |
| --- | --- | --- |
| no viewport | Full window | The product fills the canvas, or a `phone` frame shows its device frame (viewport table). Design intent, or any mockup that declares no viewport. |
| a viewport id | The viewport's label | The product at that viewport's exact width and height. |

**Test outcomes**: Passed; Failed; Skipped; Not applicable. Only Failed is
failing.

**Valid transitions**: The shell keeps no stored state. The address is the
whole review state, and reopening an address shows the same screen, state,
size and chrome mode.

## Template-Fit Check and Consumer Sync Impact

**Template-Fit Check (Protocol 02 Step 0, pre-assessed here):** passes. The
viewer and shell are the stack-agnostic part of the framework that #1470 puts
in the template. They ship only inside the opt-in scaffold (D2), and they do
nothing in a project that does not copy them. The plan stage runs the check
again.

**Sync impact by surface:**

| Surface | Sync treatment | Effect on a consumer that did not copy the scaffold |
| --- | --- | --- |
| Viewer and example mockup in the scaffold | Not synced (#2211 places the scaffold outside sync) | None. |
| Viewer and shell section of the framework reference | Always synced (workflow docs tree) | New documentation only. |
| Viewer test suite | Placement decided in the plan | Not applicable in a repository without the scaffold (test outcome table row 1); never a failure. |
| Vault standard | Outside the template repository (D7) | None. |

If the plan registers new files in the sync manifest, it records the category
and scope of each one, and confirms that none makes sync write a consumer's
design tree.

## Dependencies and Related Items

- **Depends on**: #2206 (merged in #2232). Its manifest contract is what the
  viewer reads, and its verify script checks the example manifest. #2211
  (merged in #2228) provides the scaffold and the design tree layout.
- **Depend on this item**: #2213 (opens declared states with `chrome=off`),
  #2216 (captures), #2208 (setup copies the scaffold). #2214 may use it.
- **Related**: #1442 (fidelity tooling, out of scope).

## Acceptance Criteria

### Scaffold

- [ ] AC1: The scaffold's shared viewer folder contains the viewer, and its
  example app folder contains a starter page, a manifest and the assets they
  use, meeting BR18.
- [ ] AC2: The verify script (#2206) reports Conforms for the example manifest.
- [ ] AC3: Opening the example page over `file://`, with no server, shows the
  default screen in its initial state, the two edge controls and the viewport
  switch. Opening the example over a local HTTP server shows the same.
- [ ] AC4: The scaffold's mockups README no longer describes the shared viewer
  folder as forthcoming. It says what the viewer folder holds and how to open
  a mockup both ways.

### Address and navigation

- [ ] AC5: Each row of the address resolution table produces the screen and
  state it names, and the address then reads the canonical form of what opened
  (BR5). A corrected value (rows 3, 5, 6 and 8, and any legacy address) is
  replaced, a missing state is filled in, and neither adds a browser history
  entry. A key with an empty value, a repeated key and an unknown key behave
  as BR5 says.
- [ ] AC6: Selecting a screen in the pages drawer opens it in its initial
  state, closes the drawer and updates the address. Selecting a state in the
  inspector opens it, closes the drawer and updates the address.
- [ ] AC7: Changing the address by hand, and going back and forward in the
  browser, update the canvas, the highlighted entry, the state list and the
  inspector rows to match.
- [ ] AC8: The page title follows UC2: the state's title, otherwise the
  screen's title, otherwise the screen id.

### Shell

- [ ] AC9: Both drawers start closed. Opening one closes the other. Each
  closes by selection, its close button, the scrim and `Escape`. Opening or
  closing a drawer does not change the product canvas's size or position.
- [ ] AC10: The edge controls expose their accessible names and open state,
  and each drawer is labelled and hidden from assistive technology while
  closed (BR8). Opening a drawer moves focus into it, and closing it returns
  focus to its edge control.
- [ ] AC11: The drawer headers match BR9, and the inspector rows match BR10 for
  a screen with states, a screen without states, and the `browser` frame's
  `url` row. `updated` shows `—` when the manifest has no sync date.
- [ ] AC12: The pages drawer matches BR11, including a nested entry, the
  highlight of a navigation anchor and the parent marking.
- [ ] AC13: A screen with no states shows the no-local-states message, and an
  image screen shows its exported image with its text alternative (BR12,
  BR17).
- [ ] AC14: A page with no manifest shows the no-manifest message. A manifest
  naming a screen the page has no element for shows the missing-content
  message naming that screen.

### Viewports and chrome-off

- [ ] AC15: Each row of the viewport table produces the size and switch it
  names, for the example mockup and for test variants of its manifest. A
  viewport selection updates the address and keeps the screen and state.
- [ ] AC16: With `chrome=off`, no edge control, viewport switch, drawer or
  scrim is painted, and `Escape` opens nothing. The browser bar of a `browser`
  frame is still shown.
- [ ] AC17: Starting from an address with `chrome=off`, a navigation the shell
  performs (selecting another state through the page) keeps `chrome=off` in
  the address, and the shell stays hidden.

### Automated test

- [ ] AC18: The viewer test suite opens the example mockup over `file://` in
  headless Chrome, with no server, no package install and no change to the CI
  workflows, and checks at least: initial state with no address, a screen and
  state address, an unknown state, an unknown screen, a legacy address,
  `chrome=off` including its persistence across a navigation, a viewport
  address, and the drawer behaviour of AC9.
- [ ] AC19: The suite reports each outcome of the test outcome table: Not
  applicable without the scaffold, Failed when Chrome is missing in CI, a
  visible Skipped when Chrome is missing outside CI, Passed when every check
  passes, and Failed naming the check when a check is broken on purpose.
- [ ] AC20: The template's existing workflow test harness selects the suite
  with no CI workflow change (D3), and the suite passes in CI on the
  implementation pull request. Its coverage declaration names the scaffold's
  viewer and example, so the harness's nightly full run and every pull request
  that starts the harness and changes them run it. The reference states that a
  pull request changing only scaffold files is covered by the nightly run.

### Reference and regression

- [ ] AC21: The framework reference documents the viewer and shell contract
  (BR19), names each viewer operation with its purpose (BR3), and documents the
  `file://` and HTTP open recipe. It no longer lists the viewer and shell as
  forthcoming; setup (#2208) and adoption (#2214) are still listed.
- [ ] AC22: The automated workflow test suites that passed before this change
  still pass. No existing workflow helper changes its output.
- [ ] AC23: Applying the sync manifest's classification of every new or
  changed file to a disposable consumer creates no design tree and copies no
  scaffold file.

### Vault hand-off

- [ ] AC24: The implementation pull request description contains the exact
  replacement text for the vault standard's *Viewer frame modes*, *Full-bleed
  viewer with edge drawers* (with its sub-sections) and *`viewer.js`
  integration* sections. The replacement points to the template reference and
  keeps the rationale. The description says that the template owner applies it
  (D7).

## Brief Coverage

### Brief Objective List

| # | Objective (from #2207) |
| --- | --- |
| O1 | The viewer with the `MockupViewer` operations: load manifest, init, build nav, build DOM map, target from URL, update panels, update meta |
| O2 | The shell contract: full-bleed canvas, left (pages) and right (inspector) drawers as fixed overlays, scrim, `Escape` and close behaviour, `aria-*` |
| O3 | The fixed drawer headers and inspector rows from the standard |
| O4 | The persistent viewport switch and the `chrome=off` hash mode |
| O5 | A `file://` and HTTP open recipe |
| O6 | A fixture mockup and an automated test in this repo: hash navigation, initial state, `chrome=off`, `file://` open |
| O7 | Distribution as an opt-in scaffold copied by setup (#2208) or adoption (#2214), not live files synced into every consumer |
| O8 | Bootstrap from the RADAR reference shell, not from memory |
| O9 | No fidelity or capture tooling (#1442) |
| O10 | #2213 needs it for `chrome=off` |

### Coverage Matrix

| Objective | Covered by |
| --- | --- |
| O1 | BR2, BR3, BR4, AC1, AC21 |
| O2 | BR6, BR7, BR8, AC9, AC10 |
| O3 | BR9, BR10, AC11 |
| O4 | BR14, BR15, AC15, AC16, AC17 |
| O5 | BR1, AC3, AC4, AC21 |
| O6 | BR18, BR20, AC5, AC18, AC19, AC20 |
| O7 | D2, D4, AC1, AC23 |
| O8 | D5 (evidence recorded in the plan) |
| O9 | Out of Scope |
| O10 | BR15, AC16, AC17 (wiring #2213 is Out of Scope) |

### Deferral Notes

- **O9 (fidelity and capture tooling)**: excluded by the brief itself and by
  #1470 (#1442). Human confirmation not requested.
- **O10 (#2213's use of chrome-off)**: this item provides the mode. Calling it
  from smoke and `design-reviewer` belongs to #2213. Human confirmation not
  requested (decided in #1470's sub-item list).

## Out of Scope (MVP)

- Calling the viewer or `chrome=off` from smoke, `design-reviewer`, setup or
  adoption (#2213, #2208, #2214).
- Copying the scaffold into any consumer, or changing any consumer's existing
  mockup or viewer (RADAR, Leasity, Zeki), including migrating them to this
  viewer.
- Editing the vault standard (D7).
- Disabling a viewport for a state that was not captured at it (D9). It needs
  a manifest field that the contract does not have.
- Reproduction build tooling: per-state sources, generated manifests and the
  build that assembles them, pixel and byte gates, and the fidelity kit (#1442,
  #1470 out of scope).
- Capture tooling and screenshot comparison (#2216, #1442).
- Validating the manifest inside the viewer; the verify script does it (#2206).
- Any change to CI workflows, reviewer configuration, checkpoint policy or the
  repository's workflow configuration.
