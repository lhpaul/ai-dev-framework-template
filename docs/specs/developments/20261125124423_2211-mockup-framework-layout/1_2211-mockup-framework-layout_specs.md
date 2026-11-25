# Mockup framework: design layout, tokens, README sections and the design opt-in key — Spec

## Overview

The template has no convention for where a project's UI mockups live and no
machine-readable way to say that a project uses the HTML Mockup Framework.
Each consumer repository invents its own paths, and no workflow stage can tell
whether a design tree exists or how to treat it. This item is the foundation
of epic #1470: it moves the framework's layout and token rules into the
template as its canonical contract, ships a starter design tree as an opt-in
scaffold, and adds a small configuration block whose presence is the single
opt-in signal that every later design-aware stage checks.

Nothing changes for a repository that does not opt in. The template itself
has no UI and stays not opted in.

Source: issue #2211 and the decisions recorded in epic #1470 on 2026-11-24.

## Resolved Decisions

These were decided by the template owner in #1470 and are product constraints
for this spec, not reopened here:

- **D1 — The template is the canonical owner.** The template holds the
  framework contract. The vault standard `HTML Mockup Framework.md` keeps the
  rationale and history and points to the template for the contract. That
  vault edit lands with this item. Later contract changes go to the template
  first (#1470 decision 1).
- **D2 — Opt-in scaffold distribution.** Starter design files ship as a
  scaffold that setup (#2208) or adoption (#2214) copies into a project, not
  as live files at the template root. Template sync must never create or
  overwrite a project's own design tree. Placement is confirmed by the
  Protocol 02 Step 0 Template-Fit Check (#1470 decision 2).
- **D3 — The configuration block is the opt-in record.** An absent block means
  not opted in. Every downstream stage (#2209, #2212, #2213, #2210) checks the
  block, never prose in the project docs. #2208 and #2214 write it. #1669
  extends this block instead of defining its own (#2211, #1669 coordination
  note).

Derived from those sources by this spec, and open to override at spec review:

- **D4 — Repository kind is a default, not a per-mockup override.** The vault
  standard records one repository holding a design-intent mockup and a
  reproduction side by side, and states that a design-intent mockup becomes a
  reproduction when its screen ships. A single repository-wide kind therefore
  cannot be authoritative for every mockup. The configured kind is the kind
  the project chose at setup or adoption and the default for new mockups; a
  mockup's own declared kind (manifest contract, #2206) governs that mockup.
- **D5 — Invalid configuration is a third outcome.** A block that is present
  but unusable is reported as invalid, with every problem named. It is never
  silently treated as opted in with guessed values, and never silently treated
  as not opted in. This follows the epic's fail-closed rule for unresolved
  design references (#1389).

## Use Cases

### Use Case 1: Learn the framework layout and token rules from the template

**Actor**: A maintainer of the template or of a consumer project who is
deciding how to lay out mockups.
**Preconditions**: The template version that includes this item is available
(in the template repository or synced into a consumer).

**Steps**:

1. The maintainer opens the workflow documentation index and follows the link
   to the mockup framework reference.
2. The reference shows the design tree, the three repository types, the token
   rules for each mockup kind, the source-of-truth hierarchy and how the
   project opts in.
3. The maintainer chooses the repository type that fits the project.

**Postconditions**: The maintainer knows which single layout to use, where
tokens live, which source wins in a disagreement, and how to opt in.

**Information shown**:

- The design tree: a design README, a token file, a mockups README, a shared
  folder for viewer assets, and one folder per app.
- The three repository types (monorepo apps, single app, knowledge repo), each
  with its mockup location and how the token file is reached from a mockup.
- The rule: choose one layout per repository and do not mix them.
- Token rules: a design-intent mockup mirrors the token file in its root style
  block in the same commit; a reproduction harvests the running app's
  stylesheet instead and does not mirror the token file.
- The source-of-truth hierarchy and its inversion for a reproduction.
- How the opt-in works: the configuration block, its three fields, its
  default, and the three outcomes.

**Actions available**:

- Follow a link from the reference to the scaffold.
- Follow a link to the epic sub-items that deliver the manifest contract
  (#2206), the viewer (#2207), setup (#2208) and adoption (#2214).

**Considerations**:

- Contract parts delivered by later items (manifest, viewer and shell) are
  named as forthcoming, not described from memory.

### Use Case 2: Start a design tree from the scaffold

**Actor**: A consumer project maintainer opting in by hand before setup
(#2208) or adoption (#2214) exist, or the setup and adoption flows once they
do.
**Preconditions**: The project has UI and has not yet got a design tree.

**Steps**:

1. The maintainer copies the scaffold into the project at the design root.
2. The maintainer keeps the layout that matches the project's repository type
   (per-app folders, or a single mockups folder) and removes the other.
3. The maintainer fills in the Project sections of the design README and the
   mockups README.
4. The maintainer adds the configuration block with the home and kind, and the
   design root if it is not the default.

**Postconditions**: The project has a design tree that follows the framework
layout, with Framework sections untouched and Project sections filled in, and
the project reads as opted in.

**Information shown**:

- Each scaffold README starts with a Framework section (the template's
  contract text) followed by a clearly separated Project section for the
  product's own inventory.
- The starter token file states that its values are examples to replace.

**Actions available**:

- Choose the repository type and keep only the matching layout.
- Replace the starter tokens with the product's own.

**Considerations**:

- The scaffold contains no product screens, no manifest and no viewer code;
  those arrive with #2206 and #2207.
- Copying the scaffold does not by itself opt the project in. Only the
  configuration block does.

### Use Case 3: A workflow stage asks whether the project opted in

**Actor**: A workflow stage or helper (spec, plan, review, smoke or a later
design-aware item) acting for the agent running it.
**Preconditions**: The stage runs inside a repository checkout.

**Steps**:

1. The stage asks the shared workflow helper whether the project opted in.
2. The helper reads the repository's workflow configuration at that moment.
3. The helper returns exactly one outcome: Not opted in, Opted in (with the
   design root, home and kind), or Invalid configuration (with every problem
   named).

**Postconditions**: The stage acts on the outcome. For Not opted in it behaves
exactly as before this item. For Invalid configuration it can report the named
problems instead of guessing.

**Information shown**:

- For Opted in: the design root (the default when none is configured), the home
  and the kind, each with its display label.
- For Invalid configuration: each problem, naming the field and why it is not
  usable.

**Actions available**:

- None beyond reading the outcome; the helper changes nothing.

**Considerations**:

- The helper does not look at the design tree itself. A missing or malformed
  tree is reported by the manifest verification (#2206), not by the opt-in
  check.
- Fields the helper does not know (for example those #1669 adds) do not change
  the outcome.

### Use Case 4: A consumer syncs the template without opting in

**Actor**: A consumer project maintainer running template sync.
**Preconditions**: The consumer has no design block.

**Steps**:

1. The maintainer runs template sync after this item lands.
2. Sync offers the updated framework documentation, the documented (inactive)
   design block in the configuration schema comments, and the updated shared
   workflow helper.

**Postconditions**: The consumer has the new documentation and helper, its
configuration values are unchanged, no design tree was created, and every
workflow stage behaves as before.

**Considerations**:

- A consumer that already has its own design tree (Radar, Leasity Exchanges,
  Zeki) keeps it untouched. Comparing it with the framework is #2214.

### Use Case 5: Read the vault standard after the move

**Actor**: The template owner or anyone reading the vault standard.
**Preconditions**: This item has landed.

**Steps**:

1. The reader opens the vault standard.
2. Its header states that the template is canonical for the contract and
   links to the template reference.
3. Sections whose contract now lives in the template are replaced by short
   pointers; rationale and the framework changelog stay in the vault.

**Postconditions**: The reader cannot mistake the vault for the contract on any
part the template now owns, and still finds the reasoning and history there.

**Considerations**:

- Contract parts the template does not hold yet (manifest, viewer and shell,
  fidelity gate) stay in the vault until their items land, marked as moving to
  the template, so the vault never points at template content that does not
  exist.

## Business Rules

- BR1 (one opt-in signal): Whether a project uses the framework is decided only
  by the presence and validity of the design configuration block. Prose in
  project docs, the presence of a design folder, or a copied scaffold never
  opts a project in.
- BR2 (absent means unchanged): When the configuration file or the block is
  absent, the outcome is Not opted in, and every existing workflow behaviour is
  unchanged.
- BR3 (opt-in outcomes): The opt-in check always returns exactly one of Not
  opted in, Opted in, or Invalid configuration, decided by the opt-in
  resolution table below. It never returns a guessed value.
- BR4 (fields): The block has three fields this item defines: the design root,
  the home and the kind. Home and kind are required. The design root is
  optional and defaults to `design/` at the repository root.
- BR5 (exact values): Home accepts only `knowledge` or `product`. Kind accepts
  only `design-intent` or `reproduction`. Values are matched exactly, including
  case; anything else is invalid.
- BR6 (design root): A configured design root must be a non-empty path
  relative to the repository root that stays inside the repository. An
  absolute path or one that leaves the repository is invalid.
- BR7 (extensible block): Fields the opt-in check does not define are ignored
  and do not change the outcome, so #1669 and later items can add fields
  without breaking older helpers.
- BR8 (kind precedence): The configured kind is the project's declared default
  and the kind new mockups start as. A mockup's own declared kind governs that
  mockup. A difference between the two is not an error at this level (D4).
- BR9 (one layout): A repository uses exactly one of the three repository-type
  layouts. The documentation states this rule; the knowledge-repo layout is the
  same shape as monorepo apps.
- BR10 (tokens by kind): For a design-intent mockup, the token file is the
  source and its values are mirrored in the mockup's root style block in the
  same commit. For a reproduction, the source is the running app's stylesheet,
  harvested from it, and the token file is not mirrored.
- BR11 (source-of-truth hierarchy): For design intent, product specifications
  come first, then the token file and design-system screens, then product
  mockup screens, then the design tool, then production code, which converges
  toward the sources above. For a reproduction the hierarchy is inverted:
  production code is the source and the mockup converges toward it.
- BR12 (README sections): The design README and the mockups README each have a
  Framework section, which is template contract text, and a separate Project
  section, which is product inventory. The two are delimited clearly enough
  that a later refresh of the Framework section can leave the Project section
  untouched.
- BR13 (scaffold is opt-in): The scaffold is not live at the template root and
  template sync never creates, modifies or deletes a project's own design tree.
- BR14 (template stays out): The template repository does not opt itself in.
  Its configuration documents the block as an inactive, commented example.
- BR15 (read-only check): The opt-in check reads configuration only. It does
  not create, change or inspect design files.
- BR16 (fresh read): The opt-in check reads the configuration of the checkout
  it runs in each time it is asked; it does not reuse an earlier answer.
- BR18 (versioned record only): The opt-in is a repository decision, so it is
  read only from the versioned repository workflow configuration. Machine-local
  workflow configuration can neither opt a project in nor out, nor change its
  design root, home or kind.
- BR17 (canonical owner): After this item, the template reference is the
  contract for layout, repository types, tokens, README sections, the
  source-of-truth hierarchy and the opt-in block. The vault standard points to
  it and keeps rationale and history.

### Opt-in resolution table

Rows 1 to 4 are evaluated in order, and the first match decides the outcome.
If none of them match, rows 5 to 7 are all evaluated: when one or more match,
the outcome is Invalid configuration listing the problem of every matching
row, not only the first; when none match, row 8 applies. Every situation ends
in exactly one of the three outcomes.

| # | Situation | Outcome |
| --- | --- | --- |
| 1 | The versioned workflow configuration file does not exist | Not opted in |
| 2 | The configuration file exists but cannot be read or parsed | Invalid configuration (configuration unreadable) |
| 3 | The configuration has no design key at all | Not opted in |
| 4 | The design key is present but its value is empty, null, or not a set of fields | Invalid configuration (block has no usable fields) |
| 5 | Home is missing or not one of the accepted values | Invalid configuration (names home) |
| 6 | Kind is missing or not one of the accepted values | Invalid configuration (names kind) |
| 7 | Design root is present and empty, null, absolute, or outside the repository | Invalid configuration (names design root) |
| 8 | None of rows 1 to 7 apply | Opted in, with design root (default `design/` when absent), home and kind |

Unknown extra fields in the block never match any row (BR7).

## UX Rules

These apply to the written reference, the scaffold READMEs and the messages a
stage shows from the opt-in check.

- The reference names each repository type and each kind with its display
  label from the table below, and uses the same names everywhere.
- Structure text in the scaffold (headings, section names, folder names) is in
  English, matching the vault rule that mockup structure is English and
  content is in the product's language.
- An Invalid configuration message names the field, the value found and the
  accepted values, so the maintainer can fix it without reading code.
- The reference states the default design root wherever the root is
  mentioned.

## Statuses / Enum Values

**Configuration values** (the spelling was fixed in #2211 and #1470):

| Field | Code value | Display label | Description |
| --- | --- | --- | --- |
| Home | `knowledge` | Knowledge repository | The design tree lives in a knowledge or specs repository; specs own UX and mockups change in the same PR as the spec. |
| Home | `product` | Product repository | The design tree lives next to the app code; engineers are the daily consumers. |
| Kind | `design-intent` | Design intent | Hand-authored from the spec before the code exists; the token file is the source; the mockup wins a disagreement. |
| Kind | `reproduction` | Reproduction | Generated from the running app; the app's stylesheet is the source; the app wins a disagreement. |

**Opt-in outcomes**:

| Display label | Meaning |
| --- | --- |
| Not opted in | No configuration file or no design block; behaviour unchanged. |
| Opted in | Valid design block; design-aware stages may apply. |
| Invalid configuration | Block present but unusable, or configuration unreadable; every problem is named. |

**Valid transitions**: The opt-in outcome is recomputed on every read (BR16);
there is no stored lifecycle. A project moves between outcomes only by editing
its configuration.

## Template-Fit Check and Consumer Sync Impact

**Template-Fit Check (Protocol 02 Step 0, pre-assessed here):** passes. The
framework is a stack-agnostic convention for design artifacts: plain HTML
mockups with no build step, a token file and a configuration flag. It does not
depend on the consumer's application language or framework, it is opt-in, and
a project without UI is unaffected. The plan stage re-runs the check.

**Sync impact by surface:**

| Surface | Sync treatment today | Effect on a consumer that is not opted in |
| --- | --- | --- |
| Framework reference documentation under the workflow docs tree | Always synced (workflow docs tree) | New documentation only; no behaviour change. |
| Documented design block in the configuration schema comments | Project-specific file with template-owned comment sections | Comment text only; the consumer's configuration values are untouched and stay not opted in. |
| Opt-in read in the shared workflow helper library | Always synced (workflow scripts) | Additive; no existing helper changes behaviour. |
| Scaffold files (starter design tree) | Placement decided in the plan; must not be a live tree at the template root | No design tree is created or changed by sync (BR13). Whether sync delivers the scaffold source so adoption can copy it is decided by the plan with #2214. |
| Workflow documentation index and repository README pointers | Index is always synced; repository README is project-specific | Discoverability links only. |
| Vault standard | Outside the template repository | None. |

If the plan registers new files in the sync manifest, it records the category
and scope for each and confirms none of them makes sync write a consumer's
design tree.

## Dependencies and Related Items

- **Depends on**: nothing. The canonical-owner and distribution decisions are
  settled in #1470.
- **Depend on this item** (stated in their briefs or in #1470's sub-item
  list): #2206 (manifest contract), #2208 (setup bootstrap), #2214 (adoption),
  #1669 (extends the block). #2209, #2212, #2213 and #2210 gate on the opt-in
  outcome defined here; #2207 builds on #2206 and fills the shared viewer
  folder this layout reserves.
- A relationship helper run for this spec flagged #2207, #2210 and #2212 as
  unclear because they share vocabulary (for example the shared viewer folder).
  #1470's sub-item list and each brief's own dependency line resolve them:
  each is downstream of this item, and none is a dependency of it.

## Acceptance Criteria

### Framework reference

- [ ] AC1: The template ships a framework reference page reachable from the
  workflow documentation index. It shows the design tree with the design
  README, token file, mockups README, shared folder and per-app folders.
- [ ] AC2: The reference describes the three repository types (monorepo apps,
  single app, knowledge repo) with the mockup location and token path for each,
  and states "choose one layout per repository; do not mix them".
- [ ] AC3: The reference states the token rule for each kind: design intent
  mirrors the token file in the mockup's root style block in the same commit;
  a reproduction harvests the running app's stylesheet and does not mirror the
  token file.
- [ ] AC4: The reference states the source-of-truth hierarchy in the order of
  BR11 and its inversion for a reproduction.
- [ ] AC5: The reference documents the design block: its three fields, the
  accepted values with display labels, the default design root, the opt-in
  resolution table and the rule that stages gate on the block, never on prose.
- [ ] AC6: The reference names the contract parts delivered by later items
  (#2206, #2207, #2208, #2214) as forthcoming and does not describe them.

### Scaffold

- [ ] AC7: The template provides a scaffold containing a design README, a
  starter token file, a mockups README, a shared folder and an example per-app
  folder, and none of these files exist as a live design tree at the template
  root.
- [ ] AC8: Each scaffold README has a Framework section followed by a
  separately delimited Project section; the Project section contains only
  guidance for the product's own inventory.
- [ ] AC9: The starter token file is valid JSON and states that its values are
  examples to replace.
- [ ] AC10: The scaffold contains no product screens, manifest or viewer code.

### Opt-in configuration and check

- [ ] AC11: The template's workflow configuration documents the design block
  as a commented, inactive example in its template-owned comments; running the
  opt-in check in the template repository returns Not opted in.
- [ ] AC12: In a disposable test repository, the opt-in check returns the
  outcome of the matching resolution-table row for each of these cases: no
  configuration file; unparseable configuration; no design block; empty block;
  missing home; unknown home; missing kind; unknown kind; wrong-case value;
  absolute design root; design root outside the repository; valid block
  without a design root (default root reported); valid block with a custom
  root; valid block with an unknown extra field (still Opted in); a design
  block present only in machine-local configuration (Not opted in).
- [ ] AC13: A block with several problems reports every problem in one result,
  each naming the field, the value found and the accepted values.
- [ ] AC14: The opt-in check leaves the repository unchanged (no file created,
  modified or deleted) in every case of AC12.
- [ ] AC15: The automated workflow test suites that passed before this change
  still pass, and no existing workflow helper changes its output for a
  repository without a design block.

### Sync and ownership

- [ ] AC16: Simulating template sync into a consumer without a design block
  creates no design tree and changes no configuration value; the only
  configuration difference offered is the template-owned comment text.
- [ ] AC17: The vault standard's header names the template as canonical for
  the contract and links to the template reference; each section now owned by
  the template (layout, repository types, tokens, README sections,
  source-of-truth hierarchy) is replaced by a pointer; rationale and the
  framework changelog remain; sections not yet in the template remain and are
  marked as moving with their item.
- [ ] AC18: The implementation PR description records the vault change (file,
  summary and commit) because the vault lives outside the template repository.

## Brief Coverage

### Brief Objective List

| # | Objective (from #2211) |
| --- | --- |
| O1 | Design tree: design README, token file, mockups README, shared folder, per-app folders |
| O2 | Three repository types with "choose one layout per repository" |
| O3 | Token file and the design-intent mirror rule (same commit); a reproduction harvests the app's CSS |
| O4 | Framework sections of the design and mockups READMEs, with a separate Project section |
| O5 | Source-of-truth hierarchy including its inversion for a reproduction |
| O6 | Minimal design block: design root (default `design/`), home, kind |
| O7 | A read helper in the shared workflow helper library |
| O8 | Absent block = not opted in; downstream stages gate on the key, never on prose |
| O9 | #2208 and #2214 write the block |
| O10 | #1669 extends the block instead of defining its own |
| O11 | Scope is documentation, scaffold, config schema and read helper; no other script behaviour changes |
| O12 | Placement follows the opt-in scaffold distribution, confirmed by the Template-Fit Check |
| O13 | Update the vault standard to point to the template and keep only rationale and history |

### Coverage Matrix

| Objective | Covered by |
| --- | --- |
| O1 | AC1, AC7, AC10 |
| O2 | AC2, BR9 |
| O3 | AC3, BR10, AC9 |
| O4 | AC8, BR12 |
| O5 | AC4, BR11 |
| O6 | AC5, AC11, AC12, BR4, BR5, BR6 |
| O7 | AC12, AC13, AC14, BR15, BR16, BR18 |
| O8 | AC11, AC12, BR1, BR2 |
| O9 | AC5 (documented, writable shape); writing it is Out of Scope (setup, adoption) |
| O10 | AC12 (unknown extra field), BR7 |
| O11 | AC14, AC15, Out of Scope |
| O12 | AC7, AC16, BR13, Template-Fit Check and Consumer Sync Impact |
| O13 | AC17, AC18, BR17 |

### Deferral Notes

- **O9 (writing the block from setup and adoption)**: Deferred to #2208 and
  #2214 per #1470's sub-item list; this item only defines the shape they write.
  Human confirmation not requested (decided in #1470).
- **Cross-repository home (a product repository whose design tree lives in a
  knowledge repository)**: How a repository references a design tree that it
  does not hold is #1470 decision 3, explicitly left to #2208 and #2214. Here,
  the block describes the tree in the repository that declares it. Human
  confirmation not requested (decided in #1470).

## Out of Scope (MVP)

- The manifest contract, screen and state identifiers, and the verify script
  (#2206), including checking that tokens are mirrored.
- The viewer, shell and their fixture and test (#2207).
- Writing the design block from project setup (#2208) or from adoption in an
  existing repository (#2214), and comparing an existing design tree with the
  framework (#2214).
- Referencing a design tree held in another repository (#1470 decision 3,
  resolved in #2208 and #2214).
- Wiring spec, plan, review, smoke or `design-reviewer` to the opt-in outcome
  (#2209, #2212, #2213) and reconciling `design-assets.md` (#2210).
- The surface to implementation-path mapping (#1669).
- A token schema beyond valid JSON, and token tooling.
- Reproduction tooling, pixel and byte gates, and the fidelity kit (#1470 out
  of scope; #1442).
- Refreshing the Framework sections of README copies already in consumer
  projects.
- Any behaviour change to existing workflow scripts, CI workflows, reviewer
  configuration or checkpoint policy.
