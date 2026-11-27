# Smoke Test Runbook: Mockup viewer and shell scaffold

**Feature**: Viewer, shell and example mockup in the design scaffold, and the
Viewer and shell section of the mockup framework reference (#2207)
**Spec**: [1_2207-mockup-viewer-shell_specs.md](../../specs/developments/20261127063857_2207-mockup-viewer-shell/1_2207-mockup-viewer-shell_specs.md)
**Plan**: [2_2207-mockup-viewer-shell_implementation-plan.md](../../specs/developments/20261127063857_2207-mockup-viewer-shell/2_2207-mockup-viewer-shell_implementation-plan.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] A checkout of this repository on the implementation branch, with Bash,
  `python3` and Google Chrome (or Chromium) available.
- [ ] A desktop browser for the manual steps. Any current Chrome, Firefox or
  Safari works; Steps 2 to 8 were written against Chrome.
- [ ] No `.ai-dev-workflow.local.*` file is read or edited by any step.

No application is started. No design assets exist for this item: #2207 has no
`## Design assets` section, and the development folder has no `assets/`. This
runbook therefore has no design-fidelity step; the example mockup is the
deliverable itself.

---

## Test Data

| Item | Value |
| --- | --- |
| Example page | `template/design-scaffold/design/mockups/example-app/index.html` |
| Viewer | `template/design-scaffold/design/mockups/shared/viewer.js` |
| Reference page | `docs/workflow/development-workflow/mockup-framework.md` |
| Suite | `scripts/development-workflow/tests/test-mockup-viewer.sh` |

Below, `EX` stands for the absolute path of the example page.

---

## Smoke Test Steps

### Step 1: Read the reference and the scaffold README

**Maps to**: AC1, AC4, AC20, AC21

1. List `template/design-scaffold/design/mockups/shared/` and
   `.../example-app/`.
2. Open the reference page's Viewer and shell section, then its Forthcoming
   section.
3. Open the Framework section of `template/design-scaffold/design/mockups/README.md`.

**Expected result**:

- `shared/` holds `viewer.js` and `viewer.css`; `example-app/` holds
  `index.html`, `mockup-manifest.js` and `exports/overview.svg`; no
  `.gitkeep` remains in either.
- The reference documents both ways to open a mockup, the seven viewer
  operations with their purpose, the address format and its two tables, the
  drawers, inspector rows, frames, viewports and chrome-off mode.
- Forthcoming lists #2208 and #2214 only.
- The reference says a pull request changing only scaffold files is covered
  by the nightly full run (AC20).
- The README says what `shared/` holds and how to open the example both ways.

### Step 2: Open the example by double-click

**Maps to**: AC3, AC8

1. Open `EX` from the file manager (a `file://` URL, no server).

**Expected result**:

- The Home screen fills the window; the address becomes `#screen=home`.
- Two edge buttons and a viewport switch (Desktop, Mobile, none active) are
  visible; both drawers are closed.
- The tab title is the Home screen's title.

### Step 3: Pages drawer and navigation

**Maps to**: AC6, AC9, AC10, AC12

1. Press the left edge button.
2. Press `Tab` once, then `Escape`.
3. Open the pages drawer again and select Sign in.
4. Open it again and select the nested Account details entry.
5. In the product, follow the link from Account details to the edit screen,
   then open the pages drawer.
6. Close the drawer and press the browser's Back button once.

**Expected result**:

- The drawer slides over the product without moving or resizing it; a scrim
  covers the product; focus is inside the drawer; the heading is the mockup
  name with `#screen=…&state=…` under it.
- `Escape` closes the drawer and focus returns to the left edge button.
- Selecting Sign in closes the drawer and shows its initial `empty` state;
  the address is `#screen=sign-in&state=empty`.
- With Account details shown, its nested entry is highlighted and the Account
  entry is marked as its parent.
- With the edit screen shown (it has no entry of its own), the Account
  details entry is highlighted as its navigation anchor and Account is still
  marked as its parent.
- One press of Back returns to Account details.

### Step 4: Inspector and states

**Maps to**: AC6, AC9, AC11, AC13

1. On Sign in, press the right edge button.
2. Select the `invalid` state.
3. Open the inspector, then press the scrim.
4. Navigate to Home and open the inspector.

**Expected result**:

- The heading is `Inspector`. Rows read `screen sign-in`, `state empty`,
  `route`, `url`, `kind html`, `updated` (the example's date), in that order.
- Selecting `invalid` closes the drawer and shows the invalid variant; the
  address gains `state=invalid`.
- The scrim closes the drawer.
- On Home the state row shows `—` and the inspector says the screen has no
  local states.

### Step 5: Image screen and address corrections

**Maps to**: AC5, AC7, AC13

1. Open `EX#screen=overview-image`.
2. Open `EX#screen=nowhere&state=x`, then press the browser's Back button.
3. Open `EX#sign-in` (legacy form).

**Expected result**:

- The overview image is shown, with its title as the image's text
  alternative.
- The unknown screen opens Home and the address is rewritten to
  `#screen=home`; Back does not return to the corrected address.
- The legacy form opens Sign in in its initial state and is rewritten to
  `#screen=sign-in&state=empty`.

### Step 6: Viewports

**Maps to**: AC15

1. On Sign in, select Mobile in the viewport switch.
2. Make the page area narrower than 393 px (desktop Chrome windows stop
   shrinking near 500 px, so dock DevTools to the side and widen it).
3. Select Desktop.

**Expected result**:

- The product is shown at 393 × 852 (plus the browser bar), centred, with the
  mobile layout; the address gains `viewport=mobile`; the screen and state do
  not change.
- With a narrow page area, the canvas scrolls; the product is not scaled.
- Desktop shows 1440 × 900 and the canvas scrolls when the window is
  smaller.

### Step 7: Chrome-off mode

**Maps to**: AC16, AC17

1. Open `EX#screen=sign-in&state=empty&viewport=mobile&chrome=off`.
2. Press `Escape`.
3. Use the product link inside Sign in that moves to the filled state.

**Expected result**:

- No edge button, viewport switch, drawer or scrim is painted; the browser
  bar and the product are shown at the mobile size.
- `Escape` opens nothing.
- After the product link, the address is
  `#screen=sign-in&state=filled&viewport=mobile&chrome=off` and the shell is
  still hidden.

### Step 8: Open over HTTP

**Maps to**: AC3

1. From `template/design-scaffold/design/mockups/`, run
   `python3 -m http.server 8765 --bind 127.0.0.1`.
2. Open `http://127.0.0.1:8765/example-app/#screen=sign-in&state=invalid`.
3. Stop the server.

**Expected result**: the same shell and screen as Steps 2 and 4.

### Step 9: Automated suite, verify script and vault text

**Maps to**: AC2, AC18, AC19, AC20, AC22, AC23, AC24

1. Run `bash scripts/development-workflow/tests/test-mockup-viewer.sh`.
2. Run it again with `MOCKUP_VIEWER_CHROME=/nonexistent` (which disables
   every other Chrome search), once with `CI=true` and once with `CI` and
   `GITHUB_ACTIONS` unset.
3. Run `scripts/development-workflow/mockup-manifest-verify.sh manifest
   template/design-scaffold/design/mockups/example-app/mockup-manifest.js`.
4. Run `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`.
5. Create a disposable consumer: `git init` a `mktemp -d` directory and copy
   into it, at the same paths, only the new and changed files the plan's L6
   table classifies as synced (`docs/workflow/development-workflow/mockup-framework.md`,
   `scripts/development-workflow/tests/test-mockup-viewer.sh` and
   `scripts/development-workflow/tests/fixtures/mockup-viewer/`); skip the
   paths L6 marks as not in the manifest or project_specific. From the
   consumer's root, check for `design/` and `template/`, then run
   `bash scripts/development-workflow/tests/test-mockup-viewer.sh`.
6. On the implementation PR, open the `workflow test harnesses` run and the PR
   description.

**Expected result**:

- Step 1 prints the Chrome path and version and ends with every case passed.
- Step 2 prints `FAILED: Chrome not found` (exit 1) with `CI=true`, and a
  visible `SKIPPED: Chrome not found` (exit 0) without it.
- The verify script reports Conforms.
- The coverage check reports `RESULT=clean`.
- The disposable consumer has no `design/` folder and no `template/` folder,
  and the copied suite prints
  `NOT APPLICABLE: no design scaffold in this repository` and exits 0.
- The PR's test run selected and passed `test-mockup-viewer.sh` and logged the
  Chrome version; the PR description carries the vault replacement text for
  the three viewer sections and says the template owner applies it.
