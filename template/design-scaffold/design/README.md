# Design

<!-- TEMPLATE-OWNED-START -->
## Framework

This folder is the design root of the HTML Mockup Framework (default
`design/`; a configured `design.root` relocates the whole tree). It holds:

- `README.md` — this design README.
- `tokens.json` — the token file.
- `mockups/` — the mockups, with their own README and a `shared/` folder for
  viewer assets.

Use exactly one repository-type layout; do not mix them:

- **Monorepo apps** and **Knowledge repo**: one folder per app under
  `mockups/<app>/`; a mockup reaches the token file by `../../tokens.json`.
- **Single app**: mockups directly in `mockups/`; a mockup reaches the token
  file by `../tokens.json`.

Token rule by kind:

- **Design intent**: `tokens.json` is the source; mirror its values in the
  mockup's root style block in the same commit.
- **Reproduction**: harvest the running app's stylesheet; do not mirror
  `tokens.json`.

Keep this Framework section unchanged; write product details in the Project
section below. The contract, including the source-of-truth hierarchy and the
`design` opt-in block in `.ai-dev-workflow.yaml`, is
`docs/workflow/development-workflow/mockup-framework.md` in the AI Development
Framework template. Copying this folder does not opt a project in; only the
`design` block does.
<!-- TEMPLATE-OWNED-END -->

## Project

Replace this guidance with the product's own details:

- Product name.
- Repository type: Monorepo apps, Single app or Knowledge repo.
- Home: Knowledge repository or Product repository.
- Kind: Design intent or Reproduction (the default for new mockups).
- Apps and their mockup folders.
- The values in `tokens.json` are examples; replace them with the product's
  own tokens.
