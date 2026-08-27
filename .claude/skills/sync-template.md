---
name: sync-template
description: >
  Sync framework updates from the upstream template into this project.
  Compares template files (local path or remote ref) against this project,
  shows a categorized diff for review, applies approved changes, and generates
  ready-to-use git instructions (branch + commit + PR). Run from the project root.
  Usage: /sync-template [--local=/path/to/template] [--ref=<branch|tag>] [--dry-run]
---

Follow this workflow exactly when invoked. Do not skip steps or reorder them.

---

## Step 0 — Parse arguments, determine template source, and resolve repository role

Parse the user's arguments:

- `--local=/path/to/template` → use that local directory as the template source
- `--ref=<branch|tag>` → fetch remote at that ref (e.g., `--ref=main`, `--ref=v0.4.0`)
- `--dry-run` → run Step 0.5 (comprehensive pre-flight diagnostic) only and stop; do not modify any files
- No arguments → check `.ai-dev-workflow.local.yaml` in the current project

**If `.ai-dev-workflow.local.yaml` contains a template source**, read it and use
the saved source:

```yaml
template:
  source:
    local_path: ../ai-dev-framework-template
```

or `template.source.git_url` for a remote template repository.

**If no arguments and no config file**, ask the user:

> "I need to know where to find the upstream template. Do you want to use a local path (e.g., `../ai-dev-framework-template`) or a remote GitHub URL? I'll save your answer to `.ai-dev-workflow.local.yaml` for future runs."

Save the user's answer under `template.source.local_path` or
`template.source.git_url` in `.ai-dev-workflow.local.yaml` before continuing.
The file is gitignored.

**Remote fetch** (when a URL source is used):

```bash
TEMPLATE_TEMP_DIR="/tmp/template-sync-$(date +%s)"
git clone --depth=1 --branch=<ref> <url> "$TEMPLATE_TEMP_DIR"
```

Store the exact path in `TEMPLATE_TEMP_DIR` — you must clean up this specific directory at the end (never use a wildcard).
If `--ref` is not specified for a remote source, use the default branch (`main`).

Once the template source is resolved, read its `CHANGELOG.md` and extract the latest version number (first `[X.Y.Z]` entry after `[Unreleased]` if present, otherwise the first versioned entry). Store it as `TEMPLATE_VERSION`.

**Manifest check**: After resolving the template source, check for `sync-manifest.yaml` at the template root.

- If found: read it and store its contents as `SYNC_MANIFEST`. The manifest is the authoritative file list (BR-1).
- If absent: set `SYNC_MANIFEST=absent`. The graceful fallback (BR-4 / AC-4) activates in Step 2 — the embedded lists below are used and a warning is shown.

**Repository role check**: Read the current project's `.ai-dev-workflow.yaml`
top-level `mode` value. If the file or field is absent, set
`REPOSITORY_ROLE=single_repo`. Supported roles are `single_repo`,
`workflow_hub`, and `product_repo`; any other value is a configuration error and
must stop the sync before file comparison.

When `SYNC_MANIFEST` is loaded, build the selected manifest entry set before
Step 0.5 using the selector helper from the resolved template source:

```bash
python3 "<template_source>/scripts/development-workflow/select-sync-manifest-entries.py" \
  --manifest "<template_source>/sync-manifest.yaml" \
  --role "$REPOSITORY_ROLE"
```

Store the resulting selected and skipped entries as `SYNC_SELECTED_ENTRIES` and
`SYNC_SKIPPED_ENTRIES`. This same selected entry set must be used for dry-run
diagnostics, file comparison, and apply steps so preview and apply cannot
disagree.

Role rules:

- `single_repo`: preserve compatibility by selecting every manifest entry from
  the existing categories.
- `workflow_hub`: select `shared` and `hub_only`; skip
  `product_repo_injection`.
- `product_repo`: select `shared` and `product_repo_injection`; skip
  `hub_only`.

Unknown roles, missing `mode_scope` values, unknown `mode_scope` values, or a
missing selector helper for a non-`single_repo` role must fail closed before any
file changes are applied. If the manifest is absent, use fallback mode and make
the lack of role-aware filtering explicit in the diagnostic report.

**Migration notes check**: If `SYNC_MANIFEST` is loaded, read `migration_notes` from it. Read `template.last_synced_version` from the project's `.ai-dev-workflow.yaml` (if the file or field is absent, treat it as unknown — show all notes).

For each entry in `migration_notes`: compare `entry.applies_if_syncing_from_before` against `last_synced_version` using semver. Show the entry if:

- `last_synced_version` is unknown/absent, **or**
- `last_synced_version` is strictly less than `entry.applies_if_syncing_from_before`

If any applicable notes exist, present them as a **required pre-sync checklist** before continuing:

```
⚠️  Migration steps required before this sync can proceed
═══════════════════════════════════════════════════════════
The following breaking structural changes were introduced between your last-synced
version and v{TEMPLATE_VERSION}. You must complete these steps and commit them
before the file sync diff is applied.

[For each applicable note:]
  ── {entry.title} (introduced in v{entry.version}) ──
  {entry.description}
  Steps:
    1. {step 1}
    2. {step 2}
    ...
═══════════════════════════════════════════════════════════
Have you completed all migration steps above and committed the changes? (yes/no)
```

**Do not proceed to Step 1 until the human answers "yes".** If they answer "no", stop and remind them to complete the steps first.

If no applicable notes exist, continue silently.

---

## Step 0.5 — Comprehensive pre-flight diagnostic

Run this diagnostic **after resolving the template source (Step 0) and before the git-state checks (Step 1)**. The goal is to surface all foreseeable conflict categories in a single pass so the resolution sequence can be planned upfront — avoiding the progressive-discovery loop where each category of problem is found only after the previous one is fixed.

This step is **read-only**: it inspects files and computes diffs but makes no changes. Abort only if the diagnostic itself cannot run (e.g., the template source is unreachable). Surface all findings as a structured report regardless of severity; do not filter or suppress any finding at this stage.

### Dry-run mode

If the user invokes sync-template with `--dry-run`, run only this step (Step 0.5) and then stop — do not proceed to Step 1. Print the diagnostic report and exit with a summary of what a full sync would require. This lets the agent (or maintainer) review the full conflict picture before committing to applying any changes. Example invocation:

```
/sync-template --local=../ai-dev-framework-template --dry-run
```

When `--dry-run` is active, the final output should end with:

```
Dry-run complete. No changes were applied. Re-run without --dry-run to apply changes.
```

### Category 1 — File-level merge conflicts (always-sync files)

For each selected file listed in `categories.always_sync` (or the embedded fallback list when `SYNC_MANIFEST=absent`):

1. Enumerate all files using `find` (same method as Step 2).
2. For files that exist in both the template and the project, run a diff:
   ```bash
   diff -u "<project_file>" "<template_file>"
   ```
3. Classify files as:
   - **No conflict** — identical or template is a clean superset of project (no project-local content would be overwritten)
   - **Conflict risk** — the project has local modifications not present in the template (overwriting will discard them)
   - **New file** — present in template but not in project

Report all `Conflict risk` files with a one-line summary of what differs. This preview tells the agent which always-sync files will require human attention during Step 4, rather than discovering them one at a time.

### Category 2 — CI configuration issues

Check for known CI/CD configuration mismatches between the template and the project:

1. **Workflow file presence**: compare the selected set of `.github/workflows/` files in the template (under `categories.special_handling` if manifest is loaded, otherwise the embedded special-handling list) against the project. List any files that are in the template but absent from the project — these may be needed for full CI coverage after the sync.

2. **Workflow YAML parse test** (pre-apply): for each workflow file that _would be updated_ based on the Category 1 diff, verify the _template_ version parses correctly before applying:

   ```bash
   if command -v yamllint >/dev/null 2>&1; then
     yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "<template_workflow_file>" \
       || echo "YAML PARSE ISSUE (template source): <template_workflow_file>"
   else
     python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "<template_workflow_file>" \
       || echo "YAML PARSE ISSUE (template source): <template_workflow_file>"
   fi
   ```

   A parse failure in the _template_ source is unusual but must be surfaced before applying.

3. **Script reference gaps**: scan all template workflow files for `scripts/` references and check whether those paths exist in the project:
   ```bash
   grep -hE 'scripts/[A-Za-z0-9_/.-]+' "<template_dir>"/.github/workflows/*.yml \
       "<template_dir>"/.github/workflows/*.yaml 2>/dev/null \
     | grep -oE 'scripts/[A-Za-z0-9_/.-]+' \
     | sort -u \
     | while IFS= read -r script_path; do
         [ -f "$script_path" ] || echo "MISSING (in project): $script_path"
       done
   ```
   Missing script paths indicate that the sync would introduce broken workflow references. List them here so the agent can plan to copy the missing scripts (from the template `scripts/development-workflow/` tree) as part of the same sync commit.

### Category 3 — CHANGELOG structure issues

Compare the project's `CHANGELOG.md` against the template's `CHANGELOG.md` for structural compatibility:

1. **`[Unreleased]` section presence**: verify the project's CHANGELOG has an `[Unreleased]` section:

   ```bash
   grep -c '^\#\# \[Unreleased\]' CHANGELOG.md
   ```

   If the count is 0, flag: "CHANGELOG missing [Unreleased] section — the sync commit's CHANGELOG entry cannot be placed correctly."

2. **Link reference definitions**: scan the project's CHANGELOG for any `[Unreleased]:` link reference definition line (typically at the bottom of the file):

   ```bash
   grep -n '^\[Unreleased\]:' CHANGELOG.md
   ```

   If absent, flag: "CHANGELOG missing [Unreleased] link reference — PR automation tools that render comparison links will produce broken links."

3. **Duplicate section headers**: check for duplicate `### Category` headers within the `[Unreleased]` block (a pre-existing structural defect that would cause problems when a CHANGELOG entry is added):

   ```bash
   awk '/^\#\# \[Unreleased\]/{found=1} /^\#\# \[/{if(found && !/Unreleased/) exit} found && /^\#\#\# /' CHANGELOG.md \
     | sort | uniq -d
   ```

   Any output means duplicate headers exist; flag them for pre-sync consolidation.

4. **Trailing whitespace or blank-line defects**: run a quick check on the `[Unreleased]` block for trailing whitespace:
   ```bash
   awk '/^\#\# \[Unreleased\]/{found=1} /^\#\# \[/{if(found && !/Unreleased/) exit} found' CHANGELOG.md \
     | grep -nE '[[:space:]]+$'
   ```
   Any output should be listed as a pre-existing CHANGELOG defect (non-blocking for the sync, but worth noting since the CHANGELOG will be modified).

### Category 4 — Protocol file incompatibilities

Check for known patterns where the template's protocol files reference tooling or configuration that the project does not have:

1. **`sync-manifest.yaml` presence**: if the template has a `sync-manifest.yaml` but the project does not, note this as expected behavior (manifest-driven sync vs. fallback mode). No action needed, but document it in the report.

2. **`.ai-dev-workflow.yaml` presence and validity**: the sync Step 5 writes to this file; verify it exists and parses as valid YAML:

   ```bash
   python3 -c "import sys, yaml; yaml.safe_load(open('.ai-dev-workflow.yaml'))" \
     && echo "OK" || echo "PARSE ERROR: .ai-dev-workflow.yaml"
   ```

   If missing or malformed, flag: "Step 5 will fail to record the last-synced version — fix `.ai-dev-workflow.yaml` before applying."

3. **Issue tracker integration references**: if the template's always-sync files contain references to issue tracker integrations (e.g., Linear, GitHub Projects), check that the project's `.ai-dev-workflow.yaml` has a matching `issue_tracker` section. List any referenced integration that the project has not configured as an informational note (non-blocking).

4. **Review platform references**: scan updated protocol files for references to review platforms (e.g., `devin`, `coderabbitai`, `greptile`, `codex-github`) and note which platforms are configured in the project's `.ai-dev-workflow.yaml` vs. which are referenced but not configured. Non-blocking, but helps the maintainer understand which review integrations will be active after the sync.

### Diagnostic report format

Output the report in this structure before proceeding to Step 1 (or stopping, if `--dry-run`):

```
## Pre-flight Diagnostic Report
Template version: v{TEMPLATE_VERSION}  |  Project branch: [branch]
Manifest: [loaded / absent — fallback mode]
Repository role: [single_repo / workflow_hub / product_repo]
Selected manifest entries: [N selected / M skipped by mode_scope]

### Category 1 — File-level conflicts
  No conflict:    N files (will be updated cleanly)
  Conflict risk:  N files (listed below — project-local content will be overwritten)
  New files:      N files (will be added)
  [List conflict-risk files with one-line diff summary]

### Category 2 — CI configuration
  Workflow files missing from project: [list or "none"]
  Template workflow YAML parse issues: [list or "none"]
  Script reference gaps: [list or "none"]

### Category 3 — CHANGELOG structure
  [Unreleased] section: [present / MISSING]
  [Unreleased] link reference: [present / MISSING]
  Duplicate section headers: [none / list]
  Trailing whitespace defects: [none / N lines]

### Category 4 — Protocol file incompatibilities
  sync-manifest.yaml: [present in template / absent — fallback mode]
  .ai-dev-workflow.yaml: [valid / MISSING / PARSE ERROR]
  Unconfigured issue tracker integrations: [list or "none"]
  Unconfigured review platforms: [list or "none"]

### Resolution plan
  [Summarise the sequence of actions required, ordered by dependency:
   e.g., "1. Fix .ai-dev-workflow.yaml parse error before proceeding.
          2. Resolve 2 conflict-risk files manually during Step 4.
          3. Add [Unreleased] link reference to CHANGELOG before committing."]
```

After printing the report, continue to Step 1 (unless `--dry-run` was specified).

---

## Step 1 — Pre-flight checks on the current project

Run these checks **before touching anything**. If any check fails, report the problem clearly and abort.

1. **Is this a git repository?**

   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Is the working directory clean?**

   ```bash
   git status --porcelain
   ```

   Must return empty output. If there are staged, unstaged, or untracked changes, abort with:

   > "Your working directory has uncommitted changes. Please commit or stash them before syncing."

3. **Is the project on the correct base branch?**

   ```bash
   git branch --list develop
   git branch --show-current
   ```

   - If `develop` branch exists → must be on `develop`; set `BASE_BRANCH=develop`
   - If `develop` does not exist → must be on `main`; set `BASE_BRANCH=main`

   Store `BASE_BRANCH` for use in Step 5.4. If on the wrong branch, abort with:

   > "You must be on the `develop` branch (or `main` if `develop` doesn't exist) before syncing. Please switch branches and try again."

---

## Step 2 — Compare files

Use `SYNC_MANIFEST` and `SYNC_SELECTED_ENTRIES` to determine the file lists. If `SYNC_MANIFEST=absent`, fall back to the embedded lists in each section below and display this warning before continuing:

> "Warning: sync manifest not found in upstream template. Using embedded file list — results may be incomplete."

### Always sync (apply automatically after approval)

**If `SYNC_MANIFEST` is loaded**: read selected `categories.always_sync` entries from `SYNC_SELECTED_ENTRIES` and enumerate those paths from the template. Each entry may specify a `path` (single file or directory prefix) and an optional `glob` pattern for recursive enumeration. Do not compare or apply entries from `SYNC_SKIPPED_ENTRIES`; list them in the summary under "Skipped by repository role".

**Precedence over nested project-specific files**: when enumerating an always-sync directory glob (e.g. `docs/workflow/**/*`), exclude any path that also appears as an exact `path` in the selected `categories.project_specific` entries — do not compare or apply it as always-sync. Move it into the project-specific handling described below instead. This currently applies to `docs/workflow/retro-metrics.md` and `docs/workflow/retro-metrics-platforms.md`, which are project-owned append-only logs nested inside the otherwise template-owned `docs/workflow/` tree — never overwrite them with the template's own rows.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
REVIEW.md                         <- canonical review contract for spec, plan, and code review gates
docs/workflow/                          <- full tree, all files recursively, EXCEPT retro-metrics.md
                                            and retro-metrics-platforms.md (project-specific, see below)
.claude/agents/                   <- all *.md files
.claude/commands/                 <- all *.md files
.claude/skills/                   <- all *.md files (including this skill itself)
.codex/skills/                    <- Codex skill trees shipped with the template (SKILL.md and assets)
.agents/skills/                   <- Codex repo-scoped skill discovery path and command-style aliases
.cursor/commands/                 <- all *.md files
.cursor/agents/                   <- all *.md files
.cursor/rules/                    <- all *.mdc files
scripts/development-workflow/     <- workflow helper scripts (discover state, PR/CI loops, etc.)
scripts/README.md                 <- purpose and usage of scripts in scripts/
docs/best-practices/1-general.md
docs/best-practices/2-version-control.md
docs/best-practices/3-testing.md
```

**Comparison method:** For each path in the always-sync list, enumerate files with `find` (or equivalent) and compare each path to the template using `cmp` or `diff -q`, applying the precedence exclusion above. Do not rely on ad-hoc agent inspection alone — a missed directory is a silent sync gap.

For each file in these paths:

- **Exists in template, not in project** → classify as **Add**
- **Exists in both, content differs** → classify as **Update** (prepare a concise diff summary)
- **Exists in both, content identical** → classify as **No change** (list but don't highlight)
- **Exists in project, not in template** → **ignore** (never delete project-only files)

### Rename cleanup detection

**If `SYNC_MANIFEST` is loaded and contains a `rename_detections` list**: after completing the always-sync comparison above, check each entry:

1. Verify that `entry.new_path` is present in selected `categories.always_sync`
   for the resolved repository role. If it is not, skip this entry.
2. Check whether `entry.old_path` exists as a non-empty directory in the project:
   ```bash
   [ -d "<old_path>" ] && find "<old_path>" -mindepth 1 -maxdepth 1 | wc -l
   ```
3. If `old_path` exists and is non-empty: record it as a **rename cleanup candidate** with:
   - `old_path`, `new_path`, `introduced_in`, and `description` from the manifest entry
   - A list of project-specific files that contain references to `old_path` (scan the files in `categories.project_specific` using `grep -rl "<old_path>"`; collect matching file paths for the cross-reference update offer)

Rename cleanup candidates are displayed in Step 3 and applied in Step 4 only after explicit maintainer approval. The "never delete project-only files" rule in the always-sync section does **not** apply here: `old_path` is a **former always-sync directory** whose content was superseded by `new_path`, not a project-owned directory.

**If `SYNC_MANIFEST=absent`**: skip rename cleanup detection entirely (no candidates to detect without manifest data).

### Special handling (show full diff, user decides per file)

**If `SYNC_MANIFEST` is loaded**: read selected `categories.special_handling` entries from `SYNC_SELECTED_ENTRIES`.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
.claude/settings.json                          <- may have project-specific permissions
.claude/settings.local.json.example
.github/workflows/auto-tag-release.yml         <- automated release tagging; add if CI is set up
.github/workflows/deploy.yml                   <- placeholder deployment workflow; customize with project-specific deploy logic
.github/workflows/e2e-regression.yml           <- label-gated e2e/regression placeholder; customize with project-specific test logic
e2e/                                           <- placeholder e2e/regression test project (Playwright); customize with project-specific tests
```

For each of these: show the full diff and ask the user explicitly whether to apply it.

### Project-specific files (review for additive updates — never overwrite)

These paths are project-specific and must **not** be overwritten by the template. The agent should still **read and compare** the template versions with the project's versions. Many of these files in downstream projects will have come from this template, so template improvements (new sections, clarified wording, updated links) may be useful. When the template has content that could benefit the project, the agent may **propose additive updates**: suggest adding or merging that content while **preserving all project-specific information** and avoiding inconsistencies.

**Critical:** Do not remove or replace content that is specific to the project. Only suggest additions or merges that clearly originate from the template and do not conflict with project-only content. When in doubt, list the difference under "Optional additive update" and let the user decide.

**If `SYNC_MANIFEST` is loaded**: read selected `categories.project_specific` entries from `SYNC_SELECTED_ENTRIES`. For entries with `mixed_content: true`, also read the `annotation_scheme` field and apply the mixed-content extraction logic described below.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
AGENTS.md
README.md
CHANGELOG.md
.ai-dev-workflow.yaml
docs/project/
docs/best-practices/STACK-SPECIFIC.md
docs/best-practices/stack/
.gitignore
CLAUDE.md
GEMINI.md
docs/workflow/retro-metrics.md              <- see "Append-only metrics logs" carve-out below
docs/workflow/retro-metrics-platforms.md    <- see "Append-only metrics logs" carve-out below
```

For each of these: if template and project differ, show what the template has that the project might want to add; classify as **Optional additive update** (user decides). Do not apply changes to these paths without explicit user approval.

**Append-only metrics logs carve-out**: `docs/workflow/retro-metrics.md` and `docs/workflow/retro-metrics-platforms.md` are append-only history logs, not documentation the template ever meaningfully "improves." Do not diff them against the template or propose additive updates from the template's own rows — the template's rows describe the template repository's own batch history, not this project's, and merging them in would corrupt the log. Only ever mention these two files if the manifest's `docs/workflow/retro-metrics*` migration note (see Step 0.5 / migration notes) applies.

Everything else not listed above (application code, project configs, etc.) is also never overwritten.

### Mixed-content extraction logic

When a file has `mixed_content: true` and `annotation_scheme: html_comments` in the manifest, use the following extraction logic when comparing to the upstream template:

**Detection by file extension:**

- For `.md` files: match lines that are exactly `<!-- TEMPLATE-OWNED-START -->` and `<!-- TEMPLATE-OWNED-END -->`.
- For `.yaml` / `.yml` files: match lines that are exactly `# <!-- TEMPLATE-OWNED-START -->` and `# <!-- TEMPLATE-OWNED-END -->` (YAML comment prefix required).

**Extraction behaviour:**

- Extract only the content between `TEMPLATE-OWNED-START` and `TEMPLATE-OWNED-END` marker pairs for comparison and diffing.
- Show only the extracted template-owned sections in the diff. Label all other sections as "preserved — no change" in the summary (UX Rule 2).
- If markers are absent or malformed in the downstream copy of the file, flag the file as "unstructured — full review required" and show a full diff instead. Do NOT attempt an automatic merge in this case (UX Rule 3).

---

## Step 3 — Present the change summary

Show a structured summary before asking for confirmation. Include file counts per category before the file lists so the maintainer can quickly detect an unexpectedly small always-sync list (UX Rule 1 / AC-5). Example format:

```
## Template Sync Summary
Template version: v0.4.0  |  Project branch: develop
Manifest: loaded from sync-manifest.yaml  (or: "not found — using embedded fallback list")
Repository role: workflow_hub  (selected: N entries, skipped by mode_scope: M)

### Always-sync files: N total (A to add, U to update, C up-to-date)

#### New files (will be added): A
  .claude/skills/sync-template.md

#### Modified files (will be updated): U
  .claude/agents/developer.md
    Line 3: model: claude-sonnet-4-5 -> model: claude-sonnet-4-6

  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
    [diff summary]

#### Already up to date (no changes): C
  docs/best-practices/1-general.md
  .cursor/rules/code.mdc
  ... (N files)

### Optional additive updates (project-specific — discretionary)
  AGENTS.md — template has [brief description]; project keeps its own content; suggest adding: ...
  README.md — no template additions suggested
  ...

### Escalation / hard-stop (name path or action to approve)
  Special-handling paths (never walkthrough yes/skip; never Accept-recommendations auto-apply):
  .claude/settings.json
    [full diff shown here]
  .github/workflows/deploy.yml
  .github/workflows/e2e-regression.yml
  e2e/

### Skipped by repository role
  product_repo_injection:
    AGENTS.md
  hub_only:
    docs/workflow/

### Rename cleanup (escalation only — name each action)
  docs/ai/ — was the previous location of always-sync content now in docs/workflow/ (renamed in v0.23.0).
  Stale directory still present. Proposed actions (each requires separate named approval):
    1. Delete docs/ai/  (git rm -r docs/ai/)
    2. Update cross-references in project-specific files:
         AGENTS.md  — 3 reference(s) to docs/ai/  →  docs/workflow/
         README.md  — 1 reference(s) to docs/ai/  →  docs/workflow/
```

**Taxonomy rules for the summary:**

- **Optional additive updates** is the discretionary bucket (walkthrough yes/skip under Decide with me; disposition-table rows under Accept recommendations).
- **Escalation / hard-stop** lists `categories.special_handling` paths (including `.claude/settings.json`, deploy/e2e workflows, `e2e/`). Do **not** put these under a discretionary “you decide” / manual-review walkthrough heading.
- **Rename cleanup** is escalation-only. Omit the section entirely when no candidates were detected.

After applying changes, show a final disposition summary with separate counts (AC-5 / UX Rule 4):

```
### Sync complete

Always-sync disposition:
  Updated:              N files
  Up-to-date (skipped): N files
  Declined by maintainer: N files

Discretionary disposition:
  Applied:   N
  Skipped:   N
  Escalated: N
```

Then ask (primary autonomy modes only — do **not** present `"apply all"` / `"apply always-sync only"` as the primary peer pair):

> Ready to apply? Choose how to handle discretionary items:
>
> - **"Decide with me"** — Apply always-sync, then walk each discretionary item with my recommendation and a yes/skip prompt.
> - **"Accept recommendations"** — Show a planned disposition table for every discretionary item; after you confirm once, apply those dispositions and print a disposition log.
>
> Hard-stop items (special-handling paths, rename cleanup, placeholder-guard cases) are never auto-applied in either mode. Name each path/action explicitly to approve (placeholder-guard cases also require a second named confirmation).
>
> Advanced / escape hatch: **"always-sync only"** — apply the always-sync batch and skip discretionary work (hard stops still require explicit naming).

**Do not modify any files until the maintainer has confirmed a primary mode** (and, for Accept recommendations, confirmed the disposition plan). Neither primary mode mutates files before that confirmation.

---

## Step 4 — Apply changes (only after approval)

Apply approved changes according to the selected mode.

### Shared always-sync batch

Copy/overwrite all **Add** and **Update** files from the always-sync section when the selected mode authorizes that batch:

- **Decide with me** — apply always-sync immediately after mode selection, before the discretionary walkthrough.
- **Accept recommendations** — apply always-sync only after the maintainer confirms the planned disposition table (plan confirmation authorizes always-sync + listed discretionary dispositions).
- **always-sync only** (escape hatch) — apply always-sync and stop; leave discretionary and hard-stop items unapplied unless later named explicitly.

### Decide with me

After the always-sync batch is applied, walk through **every discretionary item** (optional additive updates and any other non-hard-stop “you decide” items), **one item at a time**:

1. Show the item's diff (or proposed addition) inline.
2. State a recommendation (e.g., "I recommend applying this because …" or "This is optional — your project already has equivalent content").
3. Ask: "Apply this item? (yes / skip)"
4. Apply immediately if the user answers "yes"; skip if "skip" (or any non-yes answer).
5. Proceed to the next item.

**Exclude hard-stop items from this walkthrough.** Special-handling paths, rename cleanup actions, and placeholder-guard cases escalate separately and are never satisfied by a walkthrough “yes”.

Legacy bulk phrases such as `"apply all"`, `"apply everything"`, or `"yes to all"` map to Decide with me semantics **only for discretionary items** — they never authorize hard stops.

### Accept recommendations

Before any discretionary mutation (and before the always-sync batch in this mode):

1. Print a **planned disposition table** covering every discretionary item (recommended apply or skip, with a short why).
2. List hard-stop items under an **Escalated (not auto-applied)** section — they are not disposition rows that can be auto-applied.
3. Obtain **one** plan confirmation (or decline / switch to Decide with me). **Do not mutate files until the plan is confirmed.**
4. After confirmation: apply the always-sync batch, then apply each recommended discretionary disposition **without** further per-item prompts.
5. Print a post-apply **disposition log** with applied / skipped / escalated outcomes (and why for escalations).

Example planned table:

```
## Planned discretionary dispositions
| Item | Recommendation | Why |
| --- | --- | --- |
| AGENTS.md additive block | apply | Template adds sync-template command mention |
| README.md | skip | Project already has equivalent section |

## Escalated (not auto-applied)
| Item | Why blocked |
| --- | --- |
| .claude/settings.json | special-handling — name path to approve |
| delete docs/ai/ | rename cleanup — name action to approve |
```

### Always-sync only (advanced / escape hatch)

When the maintainer explicitly chooses the demoted **"always-sync only"** escape hatch, apply the always-sync batch and skip the discretionary walkthrough / disposition plan entirely. Hard-stop items remain unapplied unless named explicitly. Do **not** present this option as a peer of the two primary autonomy modes.

### Hard stops (both primary modes)

The following remain unapplied unless the maintainer explicitly names/confirms them:

- **Special-handling paths** (`.github/workflows/deploy.yml`, `e2e-regression.yml`, `e2e/`, `.claude/settings.json`, etc.)
- **Rename cleanup** actions (delete stale directory; update cross-references)
- **Placeholder-guard** cases (second named confirmation required)

Phrases such as `"apply all"`, `"apply everything"`, `"yes to all"`, mode selection alone, or Accept-recommendations plan confirmation **never** authorize hard-stop items. Those require the user to name each approved path or action explicitly.

- **Placeholder guard for workflow YAML** (`.github/workflows/deploy.yml`, `.github/workflows/e2e-regression.yml`): Before overwriting the project copy with the template, compare line counts. If the **project** file has **more lines** than the template and the template has **fewer than 70%** of the project's line count, treat this as likely "real implementation → template placeholder" and **refuse** unless the user sends a **second** explicit confirmation naming that exact file.

### General rules

- Do **not** delete any file from the always-sync, special-handling, or project-specific categories without explicit approval
- Do **not** overwrite project-specific files; for those paths only additive/merge changes are allowed, and only with explicit approval

### Post-apply path verification (cross-reference integrity check)

After applying any file that contains cross-references to workflow doc paths (e.g., `.claude/commands/*.md`, `.cursor/commands/*.md`, `.claude/skills/*.md`, `.cursor/agents/*.md`, `.claude/agents/*.md`), verify that every resulting path resolves to an actual file in the project. This catches cases where a path-prefix rename (e.g., `docs/ai/` → `docs/workflow/`) is applied correctly but protocol numbers that shifted between the old and new directory trees are not.

For each file that was added or updated in this step:

1. Extract all relative file paths referenced in the file (look for patterns like `docs/workflow/...`, `docs/specs/...`, or any `*.md` path under `docs/`).
2. For each extracted path, verify the file exists:
   ```bash
   ls <path>   # or: test -f <path> && echo "OK" || echo "MISSING: <path>"
   ```
3. If any path does not resolve, **do not commit**. Instead, surface it as a manual review item:
   > "⚠️ Cross-reference path not found after sync: `<path>` (in `<file>`). The path prefix was updated but the filename may have changed. Please verify the correct path and update the reference manually before committing."

Collect all broken paths and report them together before asking the user to confirm or fix them. Only proceed to Step 5 once either (a) all paths resolve, or (b) the user has explicitly acknowledged each broken path and confirmed they will fix it manually after the commit.

### Rename cleanup actions (only when maintainer approves each action individually)

For each rename cleanup candidate from Step 3, apply only the actions the maintainer explicitly approved:

**Action 1 — Delete the stale old directory** (only if the maintainer approved "delete `<old_path>`"):

```bash
git rm -r <old_path>
```

Do not use `rm -rf` — use `git rm -r` so the removal is tracked by git. After running the command, verify the directory no longer exists.

**Action 2 — Update cross-references in project-specific files** (only if the maintainer approved "update cross-references"):

For each project-specific file that contained references to `old_path` (identified during Step 2 rename detection):

- Replace every occurrence of `old_path` with `new_path` in that file (exact string substitution, preserving surrounding context)
- Show a brief diff of each change before writing
- Apply only after the maintainer does not object

After applying cross-reference updates, run a quick grep to confirm no remaining references exist:

```bash
grep -r "<old_path>" <project_specific_file_list>
```

If any references remain, list them and ask the maintainer whether to update them or leave them intentionally.

**Bulk phrases do not cover rename cleanup**: `"apply all"`, `"apply everything"`, `"yes to all"`, Decide with me walkthrough answers, and Accept recommendations plan confirmation never authorize rename cleanup actions. Each rename cleanup action (delete directory, update cross-references) requires the maintainer to name it explicitly.

If the template source was a remote clone, clean up the exact temp directory recorded in Step 0:

```bash
rm -rf "$TEMPLATE_TEMP_DIR"   # use the exact path, not a wildcard
```

---
## Step 4.5 — CI workflow health check

Run this check **after** applying changes and **before** generating git instructions. It verifies that the project's CI workflows are not silently broken after the sync.

### 1. Verify `.github/workflows/` exists

```bash
if [ ! -d ".github/workflows" ]; then
  echo "WARNING: .github/workflows/ directory not found. No CI workflows to validate."
  # Non-fatal — project may not have CI set up yet. Continue to Step 5.
fi
```

### 2. Validate all workflow YAML files are parseable

For each `.yml` / `.yaml` file in `.github/workflows/`:

```bash
yaml_parse_failed=0
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] || continue
  if command -v yamllint >/dev/null 2>&1; then
    yamllint -d "{extends: relaxed, rules: {line-length: disable}}" "$f" \
      || { echo "YAML LINT ERROR: $f"; yaml_parse_failed=1; }
  else
    python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$f" \
      || { echo "YAML PARSE ERROR: $f"; yaml_parse_failed=1; }
  fi
done

if [ "$yaml_parse_failed" -ne 0 ]; then
  echo "ERROR: One or more workflow YAML files failed validation. Fix before committing."
  exit 1
fi
```

If any file fails to parse, **do not commit**. Report the broken file(s) and ask the maintainer to fix them before committing.

### 3. Validate that `scripts/` paths referenced in workflow `run:` steps exist

```bash
grep -nHE 'scripts/[A-Za-z0-9_/.-]+' .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null \
  | while IFS=: read -r workflow_file _ matched_line; do
      printf '%s\n' "$matched_line" \
        | grep -oE 'scripts/[A-Za-z0-9_/.-]+' \
        | sort -u \
        | while IFS= read -r script_path; do
            [ -n "$script_path" ] || continue
            if [ ! -e "$script_path" ]; then
              echo "MISSING SCRIPT: $script_path (referenced in $workflow_file)"
            fi
          done
    done
```

Collect all missing script paths. If any are reported:

- If the missing path was introduced by the template sync (i.e., the file is listed under `scripts/development-workflow/` in the always-sync list but does not exist in the project), note it as a template sync gap and offer to copy the missing script from the template source if it exists there.
- Otherwise, surface it as a manual fix required:
  > "WARNING: Workflow file references `<path>` which does not exist in this project. The sync may have introduced a broken workflow reference. Please verify and fix before committing."

If no missing scripts are found, print: `CI workflow health check passed.`

This check is **advisory for the project-specific category** (e.g., `.github/workflows/deploy.yml`, `e2e-regression.yml`): a missing script path in those files may be intentional (placeholder workflow). Surface a warning but do not block the commit.

---

## Step 5 — Commit, push, and open PR

### 5.1 — Record last-synced template version

1. Read `.ai-dev-workflow.yaml` from the project root.
2. Capture the existing `template.last_synced_version` value into `PREV_LAST_VERSION` **before** writing the new value (this is used in Step 5.4 to bound the CHANGELOG extraction to changes since the previous sync):

   ```bash
   PREV_LAST_VERSION=$(grep -E 'last_synced_version:' .ai-dev-workflow.yaml | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "")
   ```

3. Set (or update) `template.last_synced_version` to `v{TEMPLATE_VERSION}` under the `template:` key. If the `template:` key does not exist yet, append the section after the `browser_automation:` block.
4. Print: `Recorded last-synced template version: v{TEMPLATE_VERSION}`

### 5.2 — Create sync branch

Execute:

```bash
git checkout -b feature/sync-template-v{TEMPLATE_VERSION}
```

### 5.3 — Stage and commit

Stage only approved paths — avoid `git add .` so unapproved files never enter the commit:

```bash
git add REVIEW.md docs/workflow/ .claude/agents/ .claude/commands/ .claude/skills/ .codex/skills/ .agents/skills/ \
  .cursor/commands/ .cursor/agents/ .cursor/rules/ \
  scripts/development-workflow/ scripts/README.md \
  docs/best-practices/1-general.md \
  docs/best-practices/2-version-control.md \
  docs/best-practices/3-testing.md
```

If `sync-manifest.yaml` was updated, stage it as well:

```bash
git add sync-manifest.yaml
```

Stage the updated `last_synced_version` field:

```bash
git add .ai-dev-workflow.yaml
```

If the user explicitly approved additional paths in Step 4 (via the manual-review, optional-additive, or rename-cleanup sections), stage them now. Track approved additional paths in an `APPROVED_ADDITIONAL_PATHS` list during Step 4 as each item is approved, then apply them here:

```bash
# Stage any additional paths approved interactively in Step 4:
if [ -n "$APPROVED_ADDITIONAL_PATHS" ]; then
  printf '%s\n' "$APPROVED_ADDITIONAL_PATHS" \
    | while IFS= read -r p; do
        [ -n "$p" ] && git add -- "$p"
      done
fi
```

Run:

```bash
git diff --stat --cached
git commit -m "chore(template): sync framework updates from template v{TEMPLATE_VERSION}"
```

### 5.4 — Push and open PR

Execute:

```bash
git push -u origin feature/sync-template-v{TEMPLATE_VERSION}
```

Then immediately create the PR (do not print instructions for the user to run manually — execute this step directly).

First, extract the relevant CHANGELOG section from the template's `CHANGELOG.md` and compose the PR body. Use `TEMPLATE_DIR` (the resolved template source path from Step 0) and `TEMPLATE_VERSION`:

```bash
# PREV_LAST_VERSION was captured in Step 5.1 before updating .ai-dev-workflow.yaml.
# Use it here to bound the CHANGELOG extraction to only changes since the previous sync.
# Extract the CHANGELOG section for changes since PREV_LAST_VERSION
if [ -n "$PREV_LAST_VERSION" ]; then
  CHANGELOG_SECTION=$(awk -v start="${TEMPLATE_VERSION#v}" -v stop="${PREV_LAST_VERSION#v}" '
    $0 ~ ("^## \\[" start "\\]") { in_range=1; next }
    in_range {
      if ($0 ~ ("^## \\[" stop "\\]")) exit
      print
    }
  ' "${TEMPLATE_DIR}/CHANGELOG.md")
else
  # No previous version — extract content after the TEMPLATE_VERSION header up to the next versioned section
  CHANGELOG_SECTION=$(awk -v tv="${TEMPLATE_VERSION#v}" '
    $0 ~ ("^## \\[" tv "\\]") { in_range=1; next }
    in_range && $0 ~ /^## \[/ { exit }
    in_range { print }
  ' "${TEMPLATE_DIR}/CHANGELOG.md")
fi

# Compose the PR body
PR_BODY="## Template sync: ${TEMPLATE_VERSION}

Sync framework-level files from the upstream template ${TEMPLATE_VERSION}.

### Changes included

${CHANGELOG_SECTION}

### What was NOT overwritten

Project-specific files (AGENTS.md, README.md, CHANGELOG.md, docs/project/, etc.)
were not overwritten; optional additive updates from the template may have been applied where you approved them, with project-specific content preserved."
```

Then create the PR using `BASE_BRANCH` from Step 1:

```bash
PR_URL=$(gh pr create \
  --title "chore(template): sync framework updates from template ${TEMPLATE_VERSION}" \
  --body "$PR_BODY" \
  --base "$BASE_BRANCH" \
  --draft)
PR_NUMBER=$(gh pr view "$PR_URL" --json number --jq '.number')
echo "PR created: $PR_URL (#$PR_NUMBER)"
```

The `--draft` flag opens the PR as a draft so automated reviewers do not trigger prematurely; Step 6 will convert it to non-draft after the reviewer gate clears. Store `$PR_NUMBER` and `$PR_URL` for use in Step 6.

---

## Step 6 — Start the reviewer loop

After the PR is open, run the reviewer loop immediately — do not ask the user to start it manually.

### 6.1 — Run the internal review gate (Step 7a)

Follow the full Step 7a procedure defined in `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` Step 7a ("Internal reviewer gate"), using the PR opened in Step 5.4 as the target.

The sync-template PR is a `feature/*` branch, so the two-pass code review procedure applies. Key focus areas for the `claude` reviewer pass on a sync PR:

- No project-specific content was accidentally overwritten by the sync.
- Always-sync files match what was approved in Step 3.
- Changelog fragment (if any) is correctly formatted under `changelog.d/`.
- `.ai-dev-workflow.yaml` was updated with `last_synced_version`.

Apply any blocking fixes, commit, and push before proceeding. Continue until all configured internal reviewers have approved (or are unavailable under the configured policy).

Once the Step 7a gate passes, ensure the PR is non-draft:

```bash
gh pr ready "$PR_NUMBER"
```

### 6.2 — Run the automated reviewer loop (Step 7)

Run `scripts/development-workflow/pr-review-loop.sh` against the PR:

```bash
bash scripts/development-workflow/pr-review-loop.sh "$PR_NUMBER"
```

Monitor the output. If the script reports unresolved findings, apply the required fixes, push, and re-run until the loop exits clean or escalates.

Oversized sync PRs may receive Haystack's authoritative
`analysis_skipped_file_limit` outcome by design. The script records that
platform as `skipped (analysis file limit)` in its workflow-owned summary and
durable history instead of waiting through the extended polling window. This
skip is permissive only for Haystack: other configured reviewers, CI,
unresolved-thread, regression, and readiness gates remain mandatory.

### 6.3 — Apply readiness labels

Once the reviewer loop exits clean:

```bash
gh pr edit "$PR_NUMBER" --add-label "ready-for-regression"
gh pr edit "$PR_NUMBER" --add-label "ready-for-human-review"
```

Update the tracker status to `Development in Review` if an issue tracker is configured.

### 6.4 — Ground-truth completion verification

Before reporting the sync PR terminal, run Protocol 91's completion self-check:

```bash
set -euo pipefail

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source scripts/development-workflow/workflow-lib.sh

# Sync PRs often have no backlog issue. Prefer an explicit ISSUE_NUMBER when
# one exists; otherwise use the PR number so set -u cannot abort the check.
ISSUE_NUMBER="${ISSUE_NUMBER:-$PR_NUMBER}"
SYNC_BRANCH=$(git rev-parse --abbrev-ref HEAD)
WORKTREE_PATH=$(pwd -P)
REVIEW_SELF_CHECK_REQUIRED=false
if workflow_config_review_platforms | grep -q .; then
  REVIEW_SELF_CHECK_REQUIRED=true
fi

./scripts/development-workflow/item-completion-self-check.sh \
  --issue "$ISSUE_NUMBER" \
  --branch "$SYNC_BRANCH" \
  --stage implementation \
  --worktree-path "$WORKTREE_PATH" \
  --pr "$PR_NUMBER" \
  --expected-base "$BASE_BRANCH" \
  --expected-label ready-for-human-review \
  --expected-label ready-for-regression \
  --forbid-label needs-fixes \
  --tracker-required false \
  --require-review-summary "$REVIEW_SELF_CHECK_REQUIRED" \
  --require-review-threads "$REVIEW_SELF_CHECK_REQUIRED"
```

Include the helper's `## Ground-Truth Completion Verification` section in the
final sync summary. Treat `discrepancy` or `unavailable_required` as non-terminal
and return to the reviewer/CI loop.

Print a final summary:

```
Sync complete. PR #$PR_NUMBER is open and ready for human review.
URL: $PR_URL
```
