# Mockup framework: viewer and shell scaffold — Implementation Plan

**Spec**: [1_2207-mockup-viewer-shell_specs.md](1_2207-mockup-viewer-shell_specs.md)
**Smoke test runbook**: [2207-mockup-viewer-shell.smoke-test.md](../../../testing/workflow/2207-mockup-viewer-shell.smoke-test.md)

---

## Summary

**Approach**: Ship the viewer, a shell stylesheet and a working example mockup
inside the existing opt-in design scaffold
(`template/design-scaffold/design/mockups/`). The example's page is one HTML
file that plays two roles. Opened directly, it is the **host**: it reads the
address, paints the reviewer shell (unless `chrome=off`) and shows the product
in a frame sized by the viewport table. Loaded inside that frame, it is the
**product**: it shows the screens and nothing else. The two talk over
`postMessage`, which works under `file://` with no flag. Because the product
runs in its own window at the viewport's size, its CSS media queries respond
exactly as they would in a window of that size.

A new workflow test suite opens the example over `file://` in headless Chrome.
It runs once with no browser flag, to prove a real double-click open works, and
once through a harness page with Chrome's test-only
`--allow-file-access-from-files` flag, to drive clicks, keys and focus inside
the frames. The framework reference gains a Viewer and shell section and loses
its #2207 "forthcoming" line. The implementation PR carries the vault
replacement text.

**Estimated complexity**: L

**Rationale**: no existing file changes behaviour, but the viewer is about
500 lines of browser JavaScript with two roles, the address and viewport
tables, a small message protocol and focus handling. The test needs a browser
driver built from `--dump-dom` and a harness page, plus CI-versus-local Chrome
discovery. No workflow, reviewer configuration, checkpoint policy or
`.ai-dev-workflow.yaml` change.

**Dependencies**: #2206 (merged in #2232; its verify script checks the example
manifest, V6) and #2211 (merged in #2228; the scaffold, V3). The spec is merged
on `develop` as `b28c1192` (V1). Implementation Order step 1 re-checks both on
the implementation base; if either has been reverted, or the verify script or
the scaffold is missing there, the implementation stops and reports a blocked
dependency instead of recreating them.

**Template-Fit Check (Protocol 02 Step 0)**: re-run at plan time and passed.
The viewer is plain HTML, CSS and browser JavaScript with no framework, build
step or package. It lives only in the opt-in scaffold, which sync never copies
(#2211 P1), and it is not tied to any consumer stack. The test uses Bash,
Python 3 and a Chrome binary; none is installed by the suite.

**Repository mode**: `mode` is absent from `.ai-dev-workflow.yaml`, so the mode
is `single_repo` and this repository owns the plan (V2).

---

## Plan decisions

Each decision is stated here once; every other section refers to it by label.

- **P1 — Files.** All new, unless marked changed:

  | Path | Role |
  | --- | --- |
  | `template/design-scaffold/design/mockups/shared/viewer.js` | The viewer (BR3) |
  | `template/design-scaffold/design/mockups/shared/viewer.css` | Shell and product-frame styles, owned by the framework |
  | `template/design-scaffold/design/mockups/shared/.gitkeep` | Removed (the folder now has files) |
  | `template/design-scaffold/design/mockups/example-app/index.html` | Example page (BR18), host and product roles |
  | `template/design-scaffold/design/mockups/example-app/mockup-manifest.js` | Example manifest, data form (#2206 BR1) |
  | `template/design-scaffold/design/mockups/example-app/exports/overview.svg` | Image screen export (BR17) |
  | `template/design-scaffold/design/mockups/example-app/.gitkeep` | Removed |
  | `template/design-scaffold/design/mockups/README.md` | Changed: Framework section (AC4) |
  | `docs/workflow/development-workflow/mockup-framework.md` | Changed: Viewer and shell section, Forthcoming list (AC21) |
  | `scripts/development-workflow/tests/test-mockup-viewer.sh` | Test suite (AC18 to AC20) |
  | `scripts/development-workflow/tests/fixtures/mockup-viewer/harness.html` | Harness page driving the cases |
  | `scripts/development-workflow/tests/fixtures/mockup-viewer/variants/` | Manifest variants for table rows the example cannot reach |
  | `changelog.d/2207.added.mockup-viewer-shell.md` | Release-note fragment |
  | `docs/testing/workflow/2207-mockup-viewer-shell.smoke-test.md` | Smoke runbook (this plan stage) |

  The example uses the Monorepo apps / Knowledge repo layout the scaffold
  already ships (`mockups/<app>/`), so it links `../shared/viewer.js` and
  `../shared/viewer.css`. It does not load `../../tokens.json` at run time;
  the page mirrors the tokens in its own `:root` block (#2206 BR10).

- **P2 — One page, two roles.** The role is decided once, at load, from
  `window.name`. The host creates the product frame as
  `<iframe name="mockup-viewer-product">`; a page whose `window.name` is
  `mockup-viewer-product` is the product, any other page is the host. The
  role is never in the address, so BR5's canonical form is unaffected and a
  capture tool cannot select it by accident. A host never nests a host: the
  product role never creates a frame.
  - **Host**: resolves the address (P4), rewrites it canonically with
    `history.replaceState`, hides every page screen element in its own
    document with the `hidden` attribute (so the frame holds the only live
    copy of the product, and keyboard focus and assistive technology never
    reach a copy behind the canvas), paints the shell when chrome is on (P5), creates
    the product frame with `src` = the page's own address without its hash
    (`location.href` up to `#`, which also works when HTTP serves the page
    as a folder URL such as `/example-app/`) plus the canonical hash with
    `chrome=off` added, sizes it by the viewport table and draws the
    product frame decoration around it (P6). It never changes the frame's
    `src` after creating it; every later change is a `show` message (P3),
    because a fragment navigation inside a frame adds a browser history entry
    (V13). It sets `data-mockup-screen`, `data-mockup-state`,
    `data-mockup-viewport`, `data-mockup-chrome` and `data-mockup-hash` (the
    canonical hash it wrote) on `<body>` and the document title (UC2), so a
    plain `--dump-dom` can observe the result (P9).
  - **Product**: hides the shell markup, shows the resolved screen and state
    (P7), and reports each shown target to its parent (P3). Opened at top
    level with `chrome=off`, a page is still the host (with no shell), so
    the frame sizing of the viewport table also holds in chrome-off mode
    (viewport table, last paragraph).

- **P3 — Message protocol (`mockup-viewer/1`).** Messages are plain objects
  with a `type` and ids only; no product content crosses.

  | Direction | `type` | Fields | Effect |
  | --- | --- | --- | --- |
  | host → product | `mockup-viewer:show` | `seq` (integer), `screen`, `state`, `handler` (boolean) | Product runs `navHandlers[screen]` when `handler` is true and one exists, otherwise shows the target |
  | product → host | `mockup-viewer:shown` | `seq` (echoed, or absent), `screen`, `state` | Host updates the address, panels and title |
  | product → host | `mockup-viewer:key` | `key` (`Escape` only) | Host closes the open drawer (BR7) |

  The host accepts a message only when `event.source` is its own product
  frame's `contentWindow` and `type` starts with `mockup-viewer:`; the
  product accepts `show` only when `event.source` is `window.parent`. Under
  `file://` every origin is `null`, so the origin cannot be checked and the
  source check is the guard. `postMessage` uses target origin `*` for the
  same reason; the payload is only ids that are already in the address.
  The host sets `handler` to true only for a selection in the pages drawer
  (RADAR runs `navHandlers` on a navigation click only); a state or viewport
  selection, a hand-edited address and back or forward send false.
  The host numbers each `show` with an increasing `seq`. A `shown` that
  echoes the latest `seq` answers the host and adds no history entry (the
  host already pushed one for the selection, BR16). The product echoes the
  `seq` of the `show` it is handling on the `shown` that answers it, including
  a target a `navHandlers` entry shows before it returns. A `shown` with an
  older `seq` is stale and ignored. A `shown` with no `seq` was started by the
  product itself (a link inside the product, AC17, through P7's
  product-initiated navigation) and adds one history entry, unless it names
  the target already shown.
  **Precedence when a host request and a product navigation cross**: the
  product handles its events one at a time and posts one `shown` for each
  target it shows, and messages from one window to another are delivered in
  the order they were posted. So the last `shown` the host receives always
  names what the product is showing, and the host follows `shown` messages in
  arrival order. The `seq` check drops only a sequenced `shown` older than
  the latest `seq`, because the reply to that latest `show` is still to come
  and will supersede it. An unsequenced `shown` never invalidates an
  outstanding `seq`: if the product shows its own target and then handles the
  pending `show`, the sequenced reply arrives last and is what the product
  shows, so the host applies it (with `replaceState`, since the selection
  already pushed its entry). If the product handles the `show` first, the
  unsequenced `shown` arrives last and wins. Either way, the address, the
  panels and the product end on the same target (T-race).

- **P4 — Address resolution is one pure function.**
  `MockupViewer.getTargetFromUrl(manifest, domMap, hash)` takes the hash
  string (default `location.hash`) and returns `{ screenId, stateId,
  viewportId, chromeOff, canonicalHash, corrected }`. It implements BR5 (key
  parsing: first occurrence wins, empty is absent, unknown keys ignored, no `=`
  means legacy form), the address resolution table and the viewport table,
  and builds the canonical hash in the fixed key order. Being pure, it is
  exercised directly by the harness for every table row (AC5, AC15), in
  addition to the end-to-end cases. It reads the frame and `$kind` from the
  manifest; a missing or unknown `$kind` is treated as Design intent, and a
  missing or unknown `frame` as `desktop` (the viewer does not validate,
  BR2).

- **P5 — Shell markup is generated by the viewer.** The page provides one
  empty `<div id="mockup-viewer"></div>` and its product screens. In the host
  role with chrome on, `init` builds the shell into it: the two edge buttons,
  the scrim, the two `<aside>` drawers with the BR9 headers, `#mockup-nav`,
  `#state-panel` / `#state-list`, the BR10 rows as `#meta-<row>` elements,
  and the viewport switch. Generating it, rather than asking each page to
  copy the vault's markup, is what keeps two mockups' shells identical (the
  drift the spec's overview names). The ids follow the vault standard so
  existing tooling that reads `#meta-*` keeps working. The page sets the
  mockup name with `init(manifest, { appName })`.
  - Edge buttons: `aria-label` `Open pages` / `Open inspector`,
    `aria-controls`, `aria-expanded`. Drawers: `aria-label` `Pages` /
    `Inspector`, `aria-hidden` and `inert` while closed. Opening a drawer
    focuses its close button; closing returns focus to the edge button that
    opened it (BR8). `Escape` on the host document, or forwarded by the
    product (P3), closes the open drawer.
  - Shell styles live in `shared/viewer.css` under a `mv-` class prefix and a
    `--mv-*` custom-property namespace, with a stacking layer above the
    product frame. Drawer width is `min(320px, 92vw)` (vault standard).
    Opening a drawer changes only `transform` and visibility of fixed
    elements, never the frame's box (BR6).

- **P6 — Frame sizing.** The host's canvas is a fixed full-window element
  with `overflow: auto`. The product frame decoration (the browser bar and
  the device frame, BR13) is drawn by the host around the `<iframe>`, never
  inside the product document, so the product window is always exactly the
  size shown and its media queries and `vh` units match a window of that size.
  - Full window (desktop, browser): the frame fills the canvas, below the
    browser bar for `browser`.
  - A viewport (desktop, browser): the frame is `width` × `height` CSS
    pixels, centred, never scaled, with the browser bar above it for
    `browser`; when larger than the window the canvas scrolls (viewport table
    footnote). The product window's `innerWidth` therefore equals the
    viewport width (V8).
  - `phone`: the frame is the device's screen area, sized to the viewport
    shown, or in Full window to the first declared viewport, or 393 × 852
    when none is declared (viewport table footnote), centred inside a host-drawn
    device frame.
  - `browser`: the bar shows the current screen's `url` from the manifest,
    updated on every applied target (BR13). The bar and the device frame are
    product decoration, so the host draws them in chrome-off mode too.

- **P7 — Showing a screen and state in the product.** The page marks each
  HTML screen as an element with class `screen` and the id from
  `buildDomMap` (`s-<screen_id>` unless `dom_id`). The product shows exactly
  one screen element and hides the rest with the `hidden` attribute, and sets
  `data-state="<state_id>"` on it, so a page styles its states with
  `[data-state="invalid"]` selectors. The page may pass
  `onShow(screenId, stateId)` for product-specific side effects; it runs after
  the default switch. An image screen (`kind` `image`) is shown as an `<img>`
  the viewer creates, with `src` = the screen's `export` relative to the page
  and `alt` = title or id (BR17). A missing element shows the BR17 message
  in the product area. This keeps the vault standard's "`go()` stays in the
  page" intent: `go` is replaced by `onShow`, which receives the same
  arguments.
  - **Product-initiated navigation**: product code moves the product with
    `viewer.show(screenId, stateId)` on the object `init` returns (P8). The
    product role also intercepts clicks on `a[href^="#screen="]` links with
    `preventDefault` and routes them to `viewer.show`. The product never
    assigns `location` or `location.hash`; it updates its own hash only with
    `history.replaceState`. A fragment navigation inside the frame would add
    a browser history entry of its own (V13), so a product link would add two
    entries instead of BR16's one.

- **P8 — Viewer interface (BR3).** `window.MockupViewer`, an IIFE, no module
  syntax, so it loads as a classic script under `file://`:

  | Operation | Signature | Notes |
  | --- | --- | --- |
  | `loadManifest` | `(url?) → Promise<manifest>` | RADAR order: `window.__MOCKUP_MANIFEST__`, embedded `#mockup-manifest` JSON, then optional `fetch(url)`. Rejects when none is found. |
  | `init` | `(manifest, options) → viewer` | `options`: `appName`, `navHandlers`, `onShow`. Detects the role (P2), builds the shell (P5) or wires the product (P7). In the product role, `viewer.show(screenId, stateId)` is product-initiated navigation (P7). |
  | `buildNav` | `(manifest, navRoot, onNavigate, navHandlers)` | RADAR's flattening of nested `items`, with depth classes and `data-nav-parent`. |
  | `buildDomMap` | `(manifest) → { screen_id: dom_id }` | Unchanged from RADAR. |
  | `getTargetFromUrl` | `(manifest, domMap, hash?) → target` | P4. |
  | `updatePanels` | `(manifest, screenId, stateId)` | BR11 highlight (anchor `nav_screen` first, every citing entry, parents marked) and BR12 state list. |
  | `updateMeta` | `(manifest, screenId, stateId, options?)` | BR10 rows; `persona` and `forced` read from the current **state** (P10). |

  The page's boot script is three lines:
  `MockupViewer.loadManifest().then((m) => MockupViewer.init(m, {...}))`
  with a `.catch` that `init` also handles: when the manifest is missing or
  has no screens, the host paints the BR4 message in the canvas instead of a
  frame (`MockupViewer.init(null, options)` is allowed for this).

- **P9 — Observable state for tests.** Besides the `<body>` data attributes
  (P2, including `data-mockup-hash`), the host sets `data-mockup-ready="1"`
  after the product's first `shown`, and `data-mockup-error="<reason>"` for BR4 and frame-load
  failures. The product sets the same attributes on its own `<body>`. These
  are the only test hooks; they are documented in the reference as
  read-only signals that capture tools (#2213, #2216) may also wait on.

- **P10 — Reproduction-only rows (D6, BR10).** The Leasity reference
  manifests carry `persona` and `forced` on each **state**, not at the top
  level (V9). The viewer reads both from the current state. `synced_at` is
  read from the top level and shown as written.

- **P11 — Chrome discovery and CI detection (test outcome table).** When
  `$MOCKUP_VIEWER_CHROME` is set and non-empty it is the only candidate: used
  when executable, otherwise Chrome is not found (rows 2 and 3), with no
  further search. When it is unset or empty, Chrome is the first of
  `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser` on
  `PATH`, then `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`.
  The exclusive override is what lets T-outcomes hide Chrome on a macOS
  machine, where the application path is found whatever `PATH` holds. CI
  is detected by `CI=true` or `GITHUB_ACTIONS=true`. The suite prints the
  Chrome path and `--version` before any case, so the CI log shows which
  binary ran (V10). Chrome runs with `--headless=new --disable-gpu
  --no-first-run --no-default-browser-check`, a fresh `--user-data-dir` under
  `mktemp -d`, and `--no-sandbox` only when the effective user id is 0.

- **P12 — Not applicable outside the template.** The suite first checks that
  `template/design-scaffold/design/mockups/example-app/index.html` exists. If
  it does not, as in a synced consumer, it prints
  `NOT APPLICABLE: no design scaffold in this repository` and exits 0 (row 1).

- **P13 — CI selection.** The suite's header declares `# covers:` lines for
  the five scaffold files it exercises and for its fixtures, and
  `# duration: 60`. The existing selector picks it on any PR that also
  touches `scripts/development-workflow/**`; scaffold-only PRs rely on the
  nightly run (AC20, #1997, V11). No workflow file changes.

- **P14 — Vault hand-off (D7, AC24).** The implementation PR description
  carries replacement text for the vault sections *Viewer frame modes*,
  *Full-bleed viewer with edge drawers* (with *What each drawer says*, *The
  inspector's rows*, *The language of the structure*, *The viewport switch*,
  *Hiding the shell for a capture*) and *`viewer.js` integration*: one short
  pointer paragraph per section to the template reference, keeping the
  rationale paragraphs (why the headers are fixed, why the label rule, why
  chrome-off) and dropping the markup and API tables that the template now
  owns.

### Acceptance criteria coverage

| AC | Decision / layer | Verified by |
| --- | --- | --- |
| AC1 | P1, L1, L2 | T-files, smoke Step 1 |
| AC2 | L2 | T-verify |
| AC3 | P2, P9 | T-open (no flag), T-http, smoke Step 2 |
| AC4 | L3 | smoke Step 1 |
| AC5 | P4 | T-resolve (pure, every row), T-address (end to end) |
| AC6 | P3, P5 | T-select |
| AC7 | P3, P4 | T-history, T-race |
| AC8 | P2 | T-title |
| AC9 | P5, P6 | T-drawers |
| AC10 | P5 | T-a11y |
| AC11 | P5, P10 | T-headers, T-rows |
| AC12 | P8 `updatePanels` | T-nav |
| AC13 | P7 | T-states, T-image |
| AC14 | P8, P7 | T-no-manifest, T-missing-content |
| AC15 | P4, P6 | T-resolve, T-viewport |
| AC16 | P2, P5 | T-chrome-off |
| AC17 | P3 | T-chrome-off-nav |
| AC18 | L4 | the suite itself |
| AC19 | P11, P12 | T-outcomes |
| AC20 | P13, L5 | PR CI run log (S3), smoke Step 1 |
| AC21 | L5 | smoke Step 1 |
| AC22 | — | S4 |
| AC23 | L6 | S5, smoke Step 9 (disposable consumer) |
| AC24 | P14 | PR description, smoke Step 9 |

---

## Verification Log

Repository revision for every row: `b28c1192` (origin/develop after the spec
merge, 2026-11-27).

| # | Claim | Command / source | Result |
| --- | --- | --- | --- |
| V1 | The spec is merged on `develop` | `gh pr view 2233 --json state,baseRefName,mergeCommit` | `MERGED`, base `develop`, merge commit `b28c1192` |
| V2 | Repository mode | `grep -n '^mode:' .ai-dev-workflow.yaml` | no match, so `single_repo` |
| V3 | Scaffold content today | `git ls-tree -r --name-only HEAD template/design-scaffold` | 5 files: two READMEs, `tokens.json`, `example-app/.gitkeep`, `shared/.gitkeep` |
| V4 | The scaffold is not in the sync manifest | `grep -n design-scaffold sync-manifest.yaml` | no match (#2211 P1) |
| V5 | Sync scope of the touched trees | `sync-manifest.yaml` lines 73, 109 and 309 | `docs/workflow/` `**/*` always_sync `hub_only`; `scripts/development-workflow/` `**/*` always_sync `hub_only`; `changelog.d/` project_specific |
| V6 | The verify script exists | `ls scripts/development-workflow/mockup-manifest-verify.sh` | present (#2232) |
| V7 | `file://` self-embedding and `postMessage` work in headless Chrome with no flag | probe page in a scratch directory, `--headless=new --dump-dom` | parent received `{"type":"hello","w":393,...}`, origin `null` |
| V8 | A frame sized 393 px gives the product `innerWidth` 393 | same probe | `innerWidth` 393 |
| V9 | Where Reproduction manifests carry `persona` and `forced` | Leasity `brokers-portal*/mockup-manifest.js` and `brokers-portal-next/index.html` (read only) | per state (`state.persona`, `state.forced`); `synced_at` top level (`property-managers-portal`) |
| V10 | A harness can reach both nested frames under `file://` | probe harness, with and without `--allow-file-access-from-files` | without: `contentDocument` is `null`; with: host and product documents readable, synthetic `Escape` dispatched |
| V11 | The CI trigger and selection model | `.github/workflows/workflow-tests.yml` header; `select-test-suites.sh` lines 11-30 | `pull_request` paths limited to `scripts/development-workflow/**` with nightly backstop (#1997); suites select by `# covers:` globs and their own fixtures |
| V12 | Suite count today | `ls scripts/development-workflow/tests \| grep -c '^test-'` | 168 |
| V13 | A fragment navigation inside a frame adds a browser history entry; `history.replaceState` inside it does not | probe page framing itself under `file://` (frame clicks an `<a href="#…">`, then calls `replaceState`), parent reports `history.length`, `--headless=new --dump-dom --virtual-time-budget=5000` | `history.length` 2 before, 3 after the in-frame link click, still 3 after the in-frame `replaceState`; 4 after one parent `pushState` |
| V14 | `python3 -m http.server` prints its port line only when unbuffered | start `python3 -m http.server --bind 127.0.0.1 0 > out` and read `out` after 3 s; repeat with `python3 -u` | without `-u`: empty; with `-u`: `Serving HTTP on 127.0.0.1 port <n> (…)` |
| V15 | No existing script, test or workflow reads the removed `.gitkeep` files or the reference sections this plan edits | `git grep -n -e design-scaffold -e '\.gitkeep' -e mockup-framework b28c1192 -- scripts .github .claude .cursor .agents .codex` | 7 lines: a link to `mockup-framework.md#manifest` in `scripts/development-workflow/README.md` (an anchor this plan keeps), contract comments in `mockup-manifest-verify.py`, `mockup-manifest-verify.sh` and `workflow-lib.sh`, and `.gitkeep` only in the unrelated `changelog.d/` handling of `changelog-fragments.sh` and its test; no `design-scaffold` match |

The probes in V7, V8, V10 and V13 were run on macOS with Google Chrome; the
implementation re-runs them as suite cases, and the CI run is the evidence for
the Linux runner (S3).

### Factual claim evidence

- Rule 3 (counts): V3 and V12 are live counts at `b28c1192`.
- Rule 4 (existence claims): the verify script (V6), the selector's `# covers:`
  support (V11) and the sync entries (V5) were each read, not assumed. That
  the hosted Ubuntu image ships Google Chrome is not provable from this
  repository; P11 prints the binary and version in CI, and S3 records it.
  If CI finds no Chrome, the suite fails by design (row 2) and the
  implementation stops for a human decision rather than changing a workflow.
- Rule 5 (composed call site): not triggered. The plan changes, deletes or
  replaces no unit that has consumers: the removed `.gitkeep` files and the
  edited reference sections have none (V15), and the selector is unchanged.
  The new suite is still checked through the selector and shard runner it
  will actually run under (S3), not only by direct invocation.

---

## Cross-Cutting Operational Assumption Check

### Applicable

Verified at 2026-11-27T19:23Z against `origin/develop` `b28c1192`. Scope:
the current invocation's single item (#2207) and the open pull requests
that could touch the same surfaces (#2242, #2243, #2244, the only other
open PRs; none of them changes a path in the table). No repository-wide scan
beyond that set.

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base | `develop`, at `b28c1192`, which holds the merged spec (#2233) | run-item policy binding (`base: develop`); `git rev-parse origin/develop` | 2026-11-27T19:23Z, `b28c1192` | #2207; #2242 to #2244 file lists | `Verified` |
| Artifact owner | `single_repo`: this repository owns the plan and the code | `.ai-dev-workflow.yaml` has no `mode:` key (V2) | 2026-11-27T19:23Z, `b28c1192` | #2207; #2242 to #2244 do not change `.ai-dev-workflow.yaml` | `Verified` |
| Dependencies #2206 and #2211 | the verify script and the five scaffold files are on the base | `git ls-tree origin/develop` for `scripts/development-workflow/mockup-manifest-verify.sh` and `template/design-scaffold/` (5 files; V3, V6) | 2026-11-27T19:23Z, `b28c1192` | #2207; #2242 to #2244 touch neither path | `Verified` |
| Scaffold not synced | `sync-manifest.yaml` has no `design-scaffold` entry (#2211 P1) | `git show origin/develop:sync-manifest.yaml` (0 matches; V4) | 2026-11-27T19:23Z, `b28c1192` | #2207; #2242 to #2244 do not change `sync-manifest.yaml` | `Verified` |
| CI runner and path filter | `workflow-tests.yml` runs on `ubuntu-latest`; its `pull_request` trigger is path-filtered (#1997), with the nightly full run as backstop (AC20) | `.github/workflows/workflow-tests.yml` lines 70 to 73 and 120 | 2026-11-27T19:23Z, `b28c1192` | #2207; #2242 to #2244 do not change the workflow or `select-test-suites.sh` | `Verified` |

That the `ubuntu-latest` image ships Google Chrome is a Rule 4 claim, not an
operational value this repository records. It is handled in Factual claim
evidence: P11 prints the binary and version in CI, S3 records it, and a
missing Chrome fails the suite by design (row 2), stopping for a human
decision. Implementation step 1 re-verifies every row above on the
implementation base and stops on `Stale or conflicting` evidence.

Two design constraints that are not concurrent-work assumptions are kept
here for the implementer: opaque `file://` origins (the message guard relies
on `event.source`, P3; V7 confirms delivery with origin `null`), and
headless timing (the harness waits on P9's `data-mockup-ready` with a
bounded poll under the suite's watchdog, L4).

### Not applicable

- Tracker or GitHub API state, secrets and local configuration: the suite
  and the viewer make no network or API calls, and no
  `.ai-dev-workflow.local.*` file is read or written.

---

## Layer-by-Layer Changes

### L1 — Viewer (`shared/viewer.js`, `shared/viewer.css`, new) (AC1, AC5 to AC17)

- `viewer.js`: start from RADAR's `viewer.js` (external repository, read
  2026-11-27, D5) for `loadManifest`, `buildDomMap`, the navigation flattening and the
  state-list rendering. Add, from Leasity `brokers-portal-next`, the viewport
  switch and `chrome=off` handling, generalised into P4 and P6. Add the role
  split (P2), the message protocol (P3), shell generation (P5) and product
  showing (P7). Change from RADAR: `updateMeta` rows follow BR10 (no
  `toLocaleString('es-CL')`, `url` only for `browser`, `persona`/`forced` for
  Reproduction from the state); `renderStates` shows the list for one or more
  states (RADAR hid a single-state list); highlighting follows BR11.
- No external dependency, no module syntax, ES2019 features only, so it runs
  in every browser a reviewer double-clicks into.
- `viewer.css`: shell (`.mv-edge`, `.mv-drawer`, `.mv-scrim`,
  `.mv-viewports`), canvas and frame (`.mv-canvas`, `.mv-frame`), product
  decoration (`.mv-browser-bar`, `.mv-device`) and messages (`.mv-message`).
  Neutral palette of its own (P5), not the product's tokens.

### L2 — Example mockup (`example-app/`, new) (AC1 to AC3, BR18)

- `mockup-manifest.js`, data form: `$kind` `design-intent`, `$status`
  `complete`, `frame` `browser`, `default_screen` `home`, two viewports
  (`desktop` 1440 × 900, `mobile` 393 × 852), and these screens:
  - `home` (no states, `url`),
  - `sign-in` (states `empty` initial, `filled`, `invalid`; `state_label`),
  - `account` with a nested navigation entry `account-details`,
  - `account-details` (no `nav_screen`, so showing it highlights the nested
    entry and marks `Account` as its parent), with a product link to
    `account-edit`,
  - `account-edit` (no navigation entry, `nav_screen` `account-details`, so
    showing it highlights the nested `Account details` entry as its anchor),
  - `overview-image` (`kind` `image`, `export` `exports/overview.svg`).

  Two navigation groups (`Main`, `Account`), one nested entry. `synced_at`
  is set to a fixed date so the `updated` row shows a value; the variants
  (L4) cover its absence. **Indicative enumeration**: the implementer may
  rename screens as long as every BR18 feature remains and the example still
  shows a nested entry's parent marking and a `nav_screen` anchor (AC12).
- `index.html`: `<style>` with a `:root` block mirroring every token of
  `../../tokens.json` by name and value (#2206 BR10), product styles using
  `@media (max-width: 600px)` so the mobile viewport visibly changes layout,
  one `.screen` element per HTML screen, `[data-state]` variants for
  `sign-in`, a product link inside `sign-in` that moves to its `filled`
  state (used by AC17) and the `account-details` link to `account-edit`, both
  plain `<a href="#screen=…">` links that the product role intercepts (P7),
  `<div id="mockup-viewer"></div>`, the two scripts and
  the boot script (P8). Content is short English placeholder text marked as
  to be replaced.
- `exports/overview.svg`: a small hand-written SVG (text and shapes only).

### L3 — Scaffold README (`mockups/README.md`, changed) (AC4)

Framework section: replace the "`shared/` is reserved ... will provide" bullet
with what `shared/` now holds (`viewer.js`, `viewer.css`), that `example-app/`
is a working example to rename, and the two ways to open it (double-click
`index.html`; `python3 -m http.server` from the mockups folder and the URL
form), and that the whole mockups folder is shared together (BR1). Keep the
template-owned markers.

### L4 — Test suite (`tests/test-mockup-viewer.sh`, fixtures, new) (AC18, AC19)

- Bash, `set -euo pipefail`, Bash 3.2 compatible. Header: purpose, spec path,
  `# covers:` lines (P13), `# duration: 60`.
- Flow: P12 gate → P11 discovery (rows 2/3 on failure) → cases → summary
  `PASS: n` / `FAIL: n` lines naming each failed case; exit 1 on any failure.
- Case runner `run_chrome <url> [flag]` runs Chrome with `--dump-dom` and
  `--virtual-time-budget=15000` under a 60-second watchdog, in a fresh
  `mktemp -d` profile removed on exit (trap).
- **Layer 1 — no flag (real open)**: dump `file://…/example-app/index.html`
  with no hash and with `#screen=sign-in&state=invalid`; assert the host
  `<body>` attributes (P9), the canonical-hash rewrite is reflected in
  `data-mockup-hash` (P2), the two edge buttons and the viewport switch exist
  and carry no `hidden` attribute, and the title. This is
  T-open and proves the `postMessage` path without any flag (AC3).
- **Layer 2 — harness**: `fixtures/mockup-viewer/harness.html?case=<name>`
  with `--allow-file-access-from-files`. The harness loads the example (or a
  variant) in an iframe, waits for `data-mockup-ready` or `data-mockup-error`
  (the no-manifest variant never becomes ready), drives the case
  through the host and product documents, and writes `PASS <case>` or
  `FAIL <case>: <seen>` lines into `<pre id="results">`. The suite parses
  only that element. One Chrome run per case group, so a hang names its
  group. **Exception — T-resolve**: that group loads
  `../../../../../template/design-scaffold/design/mockups/shared/viewer.js`
  and the example's `mockup-manifest.js` straight into the harness document
  and calls `MockupViewer.getTargetFromUrl` directly, with no example frame
  and no readiness wait, so it runs before the roles exist (step 3). For the
  viewport-table rows the example manifest cannot reach, the group builds
  small manifest objects in the harness itself (P4).
- **Variants** (`fixtures/mockup-viewer/variants/`): copies of the example
  page pointing at alternative manifests, for table rows the example cannot
  reach: no viewports; one viewport (Design intent, Reproduction); several
  viewports Reproduction; `phone` frame; no manifest; a screen without a page
  element; no `synced_at`; Reproduction with `persona`/`forced`; navigation
  with two entries citing one screen and a screen no entry cites (T-nav). Each loads
  the shipped `template/design-scaffold/design/mockups/shared/viewer.js` and
  `viewer.css` by a relative path, never a copy, so the shipped viewer is what
  runs. **Indicative enumeration**: the set
  must reach every viewport-table row and every BR4/BR17 message.
- **T-verify**: `mockup-manifest-verify.sh manifest` on the example manifest
  reports Conforms (AC2).
- **T-http**: no server output is parsed. The suite picks a free port with
  a one-line `python3 -c` that binds a socket to `127.0.0.1` port 0 and
  prints `getsockname()[1]` (an integer from the socket API, checked to be
  all digits), then starts `python3 -m http.server <port> --bind 127.0.0.1`
  in the mockups folder with its output discarded. Readiness is a bounded
  poll (10 s) that requests `http://127.0.0.1:<port>/example-app/` with
  `python3 -c` and `urllib` until it returns HTTP 200. If the server process
  exits or the poll times out (for example, another process took the port
  in between), the suite retries once with a new port, then reports
  `FAIL http: server did not start`. It then dumps the example over HTTP,
  asserts the same attributes as T-open, and stops the server (trap). V14
  is why the announcement line is not used: it is free text that only
  appears unbuffered.
- **T-outcomes** (AC19): re-run the suite in a child process with
  `MOCKUP_VIEWER_CHROME=/nonexistent` (exclusive, P11), once with `CI=true` (expect exit 1, `FAILED: Chrome not found`) and once
  with `CI` and `GITHUB_ACTIONS` unset (expect exit 0, `SKIPPED: Chrome not
  found`); and in a minimal temporary root holding only the suite and its
  fixtures at their repository paths, with no `template/` or `design/`
  (expect `NOT APPLICABLE`), never a copy of the whole repository. A planted broken check
  (`MOCKUP_VIEWER_PLANT=title`, which the suite passes to the harness as a
  `plant=title` query parameter; only the harness reads it, never the
  viewer) must produce `FAIL title`. Every child run carries
  `MOCKUP_VIEWER_CHILD=1`, and a suite run with it set skips T-outcomes, so
  the planted child (the one child that finds Chrome and runs the cases) never
  starts children of its own.
- No case writes inside the repository; the HTTP server serves read-only.

### L5 — Framework reference (`mockup-framework.md`, changed) (AC21)

- **Status and ownership**: add "the viewer and shell (#2207)" to the
  contract list.
- New section **Viewer and shell**, after Manifest: opening a mockup (both
  ways, BR1), roles of the viewer and the page (BR2, P2, P7), the interface
  table (P8), the address format and canonical form (BR5) with the address
  resolution table, shell layout and drawers (BR6 to BR9), inspector rows
  (BR10, P10), pages drawer and state list (BR11, BR12), frames and viewports
  (BR13, BR14) with the viewport table, chrome-off mode (BR15) and capture
  guidance, navigation and history (BR16), messages (BR4, BR17), the
  read-only test hooks (P9), the message protocol (P3) as an informative
  note, and the product-code rules: address its own window and move only
  through `viewer.show` or `#screen=` links, never by assigning `location`
  (P7).
- Automated test coverage (AC20): the viewer suite runs on a pull request
  only when the workflow test harness starts, so a pull request changing only
  scaffold files is covered by the nightly full run (P13).
- Starting from the scaffold: mention the working example.
- Forthcoming: remove "Viewer and shell — #2207"; keep #2208 and #2214.

### L6 — Supporting surfaces

- `changelog.d/2207.added.mockup-viewer-shell.md` (Implementation Order
  step 9).
- Sync manifest: no change. Classification of every new or changed path,
  from V4 and V5:

  | Path | Category and scope | Effect on a consumer |
  | --- | --- | --- |
  | `template/design-scaffold/**` | not in the manifest (#2211 P1) | none; never copied (D2) |
  | `docs/workflow/development-workflow/mockup-framework.md` | always_sync, `hub_only` | documentation only |
  | `scripts/development-workflow/tests/test-mockup-viewer.sh` and `fixtures/mockup-viewer/**` | always_sync, `hub_only` | Not applicable without the scaffold (P12); fixtures sit in the scripts tree, never at a design root |
  | `changelog.d/2207.added.mockup-viewer-shell.md` | project_specific | not written over consumer fragments |
  | `docs/testing/workflow/2207-mockup-viewer-shell.smoke-test.md` | not in the manifest | not synced |

- No existing script, workflow, `.ai-dev-workflow.yaml`, reviewer
  configuration or checkpoint policy changes (AC22).

---

## Testing Strategy

Named cases (L4). Each maps to the ACs in the coverage table above.

| Case | Layer | What it proves |
| --- | --- | --- |
| T-files | static | the five scaffold files P1 marks new (`shared/viewer.js`, `shared/viewer.css`, `example-app/index.html`, `example-app/mockup-manifest.js`, `example-app/exports/overview.svg`) exist, and both `.gitkeep` files are absent (AC1); it does not check the changelog fragment (step 9) or any other P1 path outside the scaffold |
| T-verify | static | example manifest Conforms (AC2) |
| T-open | no flag | real `file://` open: default screen, initial state, shell nodes, canonical hash (AC3) |
| T-http | no flag | same over HTTP (AC3) |
| T-resolve | harness, pure | every address-table row and BR5 key rule: empty, repeated, unknown keys, legacy form, canonical order (AC5); and every viewport-table row, using in-harness manifest objects for rows the example cannot reach (AC15) |
| T-address | harness | rows 1 to 8 end to end, with the address rewritten and no history entry added (AC5) |
| T-race | harness | a product link and a host selection crossing in both orders end with the address, the panels and the product on the same target, and the selection's history entry is not duplicated (P3) |
| T-select | harness | screen and state selection close the drawer and push one history entry; selecting the screen, state or viewport already shown also closes the drawer and pushes exactly one entry (AC6, BR16) |
| T-history | harness | hand-edited hash and back/forward update canvas and panels; a hand edit resolving to the target already shown is still rewritten to the canonical form (AC7, AC5) |
| T-title | harness | title rule (AC8) |
| T-drawers | harness | start closed, mutual exclusion, close by selection, button, scrim and `Escape` (host and forwarded), frame box unchanged (AC9) |
| T-a11y | harness | `aria-*`, `inert`, focus into the drawer and back to its edge button; every page screen element in the host document carries `hidden` (AC10) |
| T-headers, T-rows | harness | BR9 headers; BR10 rows for a screen with and without states, `url` row for `browser`, `updated` `—` (AC11) |
| T-nav | harness | nesting, `nav_screen` anchor and parent marking on the example (L2), every citing entry and no highlight when uncited on the navigation variant (AC12) |
| T-states, T-image | harness | no-states message; image with `alt` (AC13) |
| T-no-manifest, T-missing-content | harness | BR4 and BR17 messages (AC14) |
| T-viewport | harness | every viewport-table row: frame size, centring, canvas scroll when oversize, switch state; product `innerWidth` and `innerHeight` equal the size shown, for `browser` and `phone` too; a viewport selection keeps the screen and state and pushes one history entry; the edge buttons stay visible and inside the host window at every declared viewport and with a narrow host window (AC15, BR7) |
| T-chrome-off | harness | no shell nodes painted, `Escape` inert, browser bar present, frame size same as with shell (AC16) |
| T-chrome-off-nav | harness | product link at top-level `chrome=off` keeps `chrome=off` and adds one history entry (AC17) |
| T-outcomes | child runs | rows 1, 2, 3 and a planted failure (AC19) |

**Planted-violation proof**: T-outcomes plants a failing check and requires
`FAIL`; the PR description also records one manual plant (removing
`chrome=off` propagation in a scratch copy of `viewer.js` makes
T-chrome-off-nav fail), per the framework's verification discipline.

### Parser-risk addendum (address parsing)

`getTargetFromUrl` parses the URL fragment (P4). It is small, but it is a
structured-text reader, so its edge cases are listed and each is a T-resolve
case:

- Empty hash, `#` alone, and `#&&`.
- Empty values: `#screen=&state=x` (screen absent, so row 1 and the state
  dropped).
- Repeated keys: `#screen=a&screen=b` (first wins).
- Unknown keys: `#foo=1&screen=a` (ignored, dropped from the canonical form).
- Legacy lookalikes: `#sign-in` (legacy), `#sign-in=` (not legacy: has `=`,
  so no screen given).
- Percent-encoding: `#screen=sign%2Din` decodes to `sign-in`
  (`URLSearchParams` semantics); `+` is read as a space and so never matches a
  slug.
- Case: `#chrome=OFF` is not `off` (dropped), `#screen=Home` is unknown.
- Key order in input is free; output order is fixed (BR5).

### Concurrent-event-source addendum

The host has four event sources that share the current target: shell clicks
and keys, `hashchange`/`popstate`, product `message`s, and the first-load
timer. Browser JavaScript runs each handler to completion on one thread, so
there are no data races; the hazards are ordering ones.

- **Shared mutable state guards**: one `state` object in the host (`target`,
  `seq`, `openDrawer`), written only by `applyTarget()`; every source goes
  through it.
- **Re-entrancy / in-flight tracking**: a selection increments `seq` before
  posting `show`; the answer is matched by `seq` (P3). A second selection
  before the first answer supersedes it; the late answer is stale. A
  product-initiated `shown` crossing an outstanding `show` follows P3's
  arrival-order precedence and does not invalidate the `seq` (T-race).
- **Event deduplication**: `applyTarget()` takes the event's source. A shell
  selection (a screen, a state or a viewport chosen in the shell) always
  pushes exactly one history entry, even when it names the target already
  shown (BR16: every selection adds one entry); for a same-target selection
  it posts no `show` and repaints nothing, and only closes the drawer.
  Deduplication applies to every other source: when a `shown` echo, a
  product-initiated `shown`, a `hashchange` or a `popstate` resolves to the
  target already shown, `applyTarget()` posts no `show`, pushes no history
  entry and repaints nothing, so an echoed `shown` adds nothing. It still rewrites the address
  to the canonical hash with `replaceState` when the address differs, so a
  hand-edited hash that resolves to the target already shown (for example
  `#home` while Home is shown) is corrected as BR5 and D10 require. `history.pushState` and
  `replaceState` fire no `hashchange`, so the host's own rewrites do not loop.
- **Listener and resource cleanup**: listeners live for the page's lifetime;
  the first-load timer is cleared on the first `shown`. Nothing else is
  allocated.
- **Race conditions at initialization**: the host registers its `message`
  listener before it creates the frame, so the product's first `shown` cannot
  be missed. The product posts nothing until its own `init` has shown a
  target.
- **Race conditions at teardown**: none; unloading discards both documents.
- **Error propagation across async boundaries**: a rejected `loadManifest`
  reaches `init(null, …)` and BR4's message; an exception in `onShow` is
  caught, logged with `console.error`, and sets `data-mockup-error="on-show"`
  while the default screen switch still applies; no `shown` within 10 seconds
  of frame creation sets `data-mockup-error="frame-timeout"` and paints a
  message in the canvas.

**Proportionality (Gate B)**: the harness is larger than a unit test because
the deliverable is interactive and the issue requires a real `file://`
browser open; it adds no parser or scanner, only DOM assertions.

**Commands**:

```bash
bash scripts/development-workflow/tests/test-mockup-viewer.sh
bash scripts/development-workflow/tests/test-mockup-manifest-verify.sh
shellcheck --severity=warning scripts/development-workflow/tests/test-mockup-viewer.sh
```

- S1: the suite passes locally with Chrome, and prints SKIPPED with Chrome
  hidden.
- S2: `bash -n` and `shellcheck` are clean.
- S3: the implementation PR's `workflow test harnesses` run selects and
  passes the suite; its log shows the Chrome path and version (P11).
  Because the PR adds files under `scripts/development-workflow/tests/fixtures/`,
  a full-run trigger in `select-test-suites.sh`, that run includes every suite.
- S4: the selected suites and the full suite list pass locally (AC22).
- S5: `python3 -B scripts/development-workflow/check-sync-manifest-coverage.py`
  reports `RESULT=clean` (AC23).

---

## Seed Data

None. The example mockup (L2) and the variants (L4) are the test data.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/mockup-framework.md`: L5.
- [ ] `template/design-scaffold/design/mockups/README.md`: L3.
- `AGENTS.md`, `README.md`, `docs/README.md`, `docs/project/*`,
  `docs/best-practices/*`, `REVIEW.md`, `scripts/development-workflow/README.md`:
  none. The suite is a test, not a helper; stage wiring is #2213, #2208 and
  #2214.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Hosted Ubuntu runner lacks Chrome | Low | High | P11 prints the binary; row 2 fails loudly; stop for a human decision instead of editing a workflow |
| Chrome's sandbox cannot start on the hosted runner as a non-root user | Low | High | The case fails as row 5 with Chrome's stderr in the log; widening `--no-sandbox` beyond root is a human decision, not an implementation change |
| Headless timing flakiness | Medium | Medium | P9 readiness attributes with bounded polls; one Chrome run per case group; watchdog |
| A browser blocks `file://` self-framing in future | Low | High | V7 probe becomes T-open; the reference documents HTTP as the fallback open |
| A message from another frame drives the shell | Low | Low | P3 source check; payload is ids only |
| Product code breaks inside a frame (for example `window.top` use, or assigning `location.hash`) | Low | Medium | documented in the reference (L5): product code addresses its own window and navigates only through P7 |
| Consumers run the synced suite and fail | Low | Medium | P12 Not applicable |

### Reversal

Every change is additive and inert until a project copies the scaffold.
Reverting the implementation PR's squash commit restores the previous scaffold
and reference. The vault text is applied by its owner (D7); after a revert the
owner restores the vault sections from the vault's own history.

---

## Code Samples

```js
// Illustrative — adapt during implementation. Role detection and guard (P2, P3).
const PRODUCT_NAME = 'mockup-viewer-product';
const role = window.name === PRODUCT_NAME ? 'product' : 'host';

function onMessage(event) {
  if (!frame || event.source !== frame.contentWindow) return;
  const data = event.data;
  if (!data || typeof data.type !== 'string' || !data.type.startsWith('mockup-viewer:')) return;
  if (data.type === 'mockup-viewer:key' && data.key === 'Escape') closeDrawers();
  if (data.type !== 'mockup-viewer:shown') return;
  if (typeof data.seq === 'number') {
    if (data.seq !== state.seq) return;          // stale answer (P3)
    applyTarget(data.screen, data.state, { push: false });
  } else {
    applyTarget(data.screen, data.state, { push: true }); // product-initiated (AC17)
  }
}
```

```html
<!-- Illustrative — the example page's boot (P8). -->
<div id="mockup-viewer"></div>
<script src="../shared/viewer.js"></script>
<script src="./mockup-manifest.js"></script>
<script>
  MockupViewer.loadManifest()
    .then((manifest) => MockupViewer.init(manifest, { appName: 'Example app' }))
    .catch(() => MockupViewer.init(null, { appName: 'Example app' }));
</script>
```

---

## Implementation Order

Commit after each numbered step that leaves the tree coherent.

1. Re-run V3 to V6 and V11 and every Cross-Cutting Operational Assumption Check row on the implementation base; stop on a change or a `Stale or conflicting` row, and stop as a blocked dependency if #2206 or #2211 is no longer present (Dependencies).
2. All of L2: the manifest, `exports/overview.svg` and `index.html` (its
   `:root` token mirror, screens, `#mockup-viewer` element, script tags and
   boot script), plus an initial L1 `shared/viewer.css`. The page links
   `../shared/viewer.css` (P1), and the verify script's mirroring check reads
   every stylesheet the page links, reporting a missing one as a BR11 problem
   (`mockup-manifest-verify.py` `collect_sources`), so the file must exist
   before T-verify runs. The page exists from this step on, so the mirroring
   check finds it (T-verify) and the suite's P12 gate passes in step 3.
   Remove both `.gitkeep` files (`shared/` and `example-app/` now hold
   files). Run the verify script by hand.
3. L4 suite skeleton (P12 gate, P11 discovery, `run_chrome`, the
   `<pre id="results">` parser and the summary), so steps 4 to 6 add cases to
   a runnable suite; L1 `viewer.js` pure parts (`buildDomMap`,
   `getTargetFromUrl`); the harness's T-resolve group, which loads
   `viewer.js` directly (L4 Layer 2 exception), because the step 2 page's
   boot script cannot become ready until step 4; add T-verify as a suite
   case (the manifest and page exist from step 2); run the suite.
4. L1 host and product roles; all of P5's shell markup (both edge buttons,
   both `<aside>` drawers, `#mockup-nav`, `#state-panel`, the `#meta-*` rows,
   and the viewport switch when more than one viewport is declared), with
   their behaviour left to steps 5 and 6; the shell styles in `viewer.css`,
   which the step 2 page already loads; add T-open, T-address, T-title.
5. L1 drawers, accessibility and panels; the host's `hashchange` and
   `popstate` handling (Concurrent-event-source addendum) that T-history
   exercises; the variants T-rows and T-nav need
   (no `synced_at`, Reproduction with `persona`/`forced`, and the navigation
   variant); add T-select, T-race, T-history, T-drawers, T-a11y, T-headers, T-rows,
   T-nav, T-states, T-image.
6. L1 viewports, frames and chrome-off; the BR4 (no manifest) and BR17
   (missing content) messages; the remaining variants; add
   T-viewport, T-chrome-off, T-chrome-off-nav, T-no-manifest,
   T-missing-content.
7. L4 T-files, T-http and T-outcomes; `bash -n` and `shellcheck`;
   record the suite's `# duration:`.
8. L3 README, L5 reference. Run `npx markdownlint-cli2` and
   `python3 scripts/lint/markdown-heuristic-lint.py` on the changed Markdown,
   and `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
9. Changelog fragment `changelog.d/2207.added.mockup-viewer-shell.md`:

   ```markdown
   - **Mockup viewer and shell scaffold** (#2207): the design scaffold now ships `mockups/shared/viewer.js` and `viewer.css` with a working example mockup — a full-bleed canvas with pages and inspector drawers, a persistent viewport switch and a `chrome=off` capture mode, opened over `file://` or HTTP with no build step — and the framework reference documents the viewer and shell contract; a new workflow test opens the example in headless Chrome.
   ```

10. Run S1, S2, S4 and S5. Open the implementation PR with P14's vault text
    and the manual plant in the description (AC24).
11. With every implementation commit pushed, record S3 at the final PR head
    and run the smoke runbook.
