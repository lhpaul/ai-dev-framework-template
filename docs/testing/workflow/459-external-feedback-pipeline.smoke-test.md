# Smoke Test Runbook: External Feedback Pipeline

**Feature**: External Feedback Pipeline: GitHub Discussions Staging and Triage Protocol
**Spec**: [docs/specs/developments/20260504142641_459-external-feedback-pipeline/1_459-external-feedback-pipeline_specs.md](../../specs/developments/20260504142641_459-external-feedback-pipeline/1_459-external-feedback-pipeline_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `CONTRIBUTING.md` exists at the repository root
- [ ] `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md` exists
- [ ] GitHub Discussions is enabled on the repository
- [ ] The "Feedback & Ideas" Discussions category exists (created via GitHub UI)
- [ ] The `feedback-staging` label exists in the repository (`gh label list | grep feedback-staging`)
- [ ] You have maintainer-level access to the repository (needed to create Discussions, create issues, and close Discussions)
- [ ] `gh` CLI is authenticated (`gh auth status`)

---

## Test Data

| Item                                    | Value                                                                                                                         |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Repository                              | Current repository (run `gh repo view --json nameWithOwner`)                                                                  |
| Discussions category                    | "Feedback & Ideas"                                                                                                            |
| `feedback-staging` label                | Created via `gh label create` per protocol prerequisites                                                                      |
| Sample Discussion A (promote path)      | A Discussion with ≥ 3 upvotes or ≥ 2 comments from distinct users; title and body do not overlap with any existing open issue |
| Sample Discussion B (duplicate path)    | A Discussion whose title/body shares ≥ 3 significant keywords with an existing open issue                                     |
| Sample Discussion C (out-of-scope path) | A Discussion asking a support question or requesting a project-specific customization                                         |
| Sample Discussion D (below threshold)   | A Discussion with 0–2 upvotes and 0–1 comments                                                                                |

---

## Smoke Test Steps

### Step 1: Verify CONTRIBUTING.md exists and contains required content (AC-2)

1. Open `CONTRIBUTING.md` in the repository root.
2. Confirm the file contains a "Feedback & Ideas" section that:
   - Directs external users to GitHub Discussions (not Issues)
   - Mentions the signal threshold: 3 upvotes or 2 comments from distinct users
   - Explains that feedback submission does not guarantee implementation
   - Explains the triage process at a high level

**Expected result**: All four elements above are present and clearly written.

---

### Step 2: Verify the triage protocol document exists and is complete (AC-3)

1. Open `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`.
2. Confirm the document contains:
   - A Prerequisites / One-time Setup section that includes the `gh label create` command for `feedback-staging` and instructions for creating the "Feedback & Ideas" Discussions category
   - The signal threshold values (3 upvotes OR 2 comments from distinct users)
   - Duplicate detection criteria (≥ 3 shared significant keywords OR identical file paths / protocol names)
   - The scope filter criteria (what is in scope and what is out of scope)
   - The promoted issue format (Community feedback source, Summary, Signal, Original feedback sections)
   - The closing comment requirements (mandatory for all outcomes)
   - The recommended cadence (at least monthly)
   - Instructions for invoking the protocol

**Expected result**: All sections are present and unambiguous.

---

### Step 3: Verify the `feedback-staging` label exists (AC-4)

1. Run: `gh label list | grep feedback-staging`

**Expected result**: Output shows a `feedback-staging` label with a description. If the label does not exist, follow the setup steps in `07-feedback-triage-protocol.md` to create it.

---

### Step 4: Triage run — Discussion below signal threshold (Business Rules)

1. Create a test Discussion in the "Feedback & Ideas" category with 0 upvotes and 0 comments (or use Discussion D from Test Data above).
2. Follow the triage protocol steps (Step e.2: evaluate signal threshold).
3. Confirm the Discussion is identified as below threshold and skipped (not included in the list of candidates for promotion).

**Expected result**: The Discussion is excluded from the candidate list; no action is taken on it.

**Maps to**: Business Rules (signal threshold)

---

### Step 5: Triage run — Promote a qualifying Discussion (AC-5, Use Cases 1 and 2)

1. Create or identify Sample Discussion A (≥ 3 upvotes or ≥ 2 distinct comments; no duplicate in issues).
2. Follow the triage protocol steps e.1 through e.6 for Discussion A.
3. When the preview is presented, confirm the proposed action is "promote".
4. Confirm the maintainer confirmation step is required before execution (interactive mode).
5. Approve the action.
6. Verify:
   - A new GitHub issue was created with:
     - Title derived from the Discussion title
     - Label: `feedback-staging`
     - Body containing sections: "Community feedback source" (with link to Discussion), "Summary", "Signal" (upvote count and comment count), "Original feedback"
   - The Discussion was closed with a comment that references the new issue number

**Expected result**: New issue exists with `feedback-staging` label; Discussion is closed with a linking comment.

**Maps to**: AC-3, AC-4, AC-5; Use Cases 1 and 2

---

### Step 6: Triage run — Duplicate found (AC-5, Use Case 3)

1. Identify or create Sample Discussion B (title/body overlaps with an existing open issue by ≥ 3 keywords).
2. Follow the triage protocol steps for Discussion B.
3. Verify:
   - The triage runner identifies the existing issue as a duplicate match
   - The Discussion is closed with a comment linking to the existing issue (text must contain something equivalent to "already tracked in #N")
   - The existing issue is not modified

**Expected result**: Discussion closed with linking comment; existing issue unchanged.

**Maps to**: AC-5; Use Case 3

---

### Step 7: Triage run — Out-of-scope Discussion closed with explanation (AC-5, Use Case 4)

1. Use Sample Discussion C (a support question or downstream-specific request).
2. Follow the triage protocol steps for Discussion C.
3. In the preview, confirm the proposed action is "out of scope" with a reason.
4. Approve the action.
5. Verify:
   - The Discussion is closed with a comment that explains why it is not being promoted (not a generic "out of scope" — must include a brief reason)
   - No issue is created

**Expected result**: Discussion closed with a polite, specific explanatory comment; no issue created.

**Maps to**: AC-5; Use Case 4

---

### Step 8: Verify AGENTS.md workflow table entry (AC-6)

1. Open `AGENTS.md` (or `CLAUDE.md` — same file via symlink).
2. Find the Workflow Commands table.
3. Confirm a row for "Run feedback triage" exists with a link to `07-feedback-triage-protocol.md` in the "Any other tool" column.

**Expected result**: Row is present and link is correct.

**Maps to**: AC-6

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: The "Feedback & Ideas" GitHub Discussions category exists on the repository (confirmed in Prerequisites step; documented as a manual setup step in `07-feedback-triage-protocol.md`)
- [ ] AC-2: `CONTRIBUTING.md` exists at the repository root with a section directing external users to Discussions, explaining the triage process, and stating the signal threshold values
- [ ] AC-3: `docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md` exists and contains all required sections: Discussion query steps, signal threshold (3 upvotes OR 2 comments), duplicate detection criteria, scope filter, promoted issue format, closing comment requirements
- [ ] AC-4: The `feedback-staging` label exists in the repository (or its creation is documented as a setup step in the protocol with the exact `gh label create` command); its purpose is described in `07-feedback-triage-protocol.md`
- [ ] AC-5: A simulated triage run produces correct outcomes: qualifying Discussion → new issue with `feedback-staging` label + closing comment; duplicate Discussion → closed with comment linking to existing issue; out-of-scope Discussion → closed with polite explanatory comment
- [ ] AC-6: The triage protocol specifies the recommended cadence (at least monthly) and documents how to invoke it

---

## Seed Data Reference

All test data for this smoke test is created manually via GitHub UI or `gh` CLI. There is no automated seed data.

| Entity                      | Scenario                                            | How to load                                                                                                                   |
| --------------------------- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `feedback-staging` label    | Required for triage run                             | `gh label create "feedback-staging" --description "Issue promoted from a GitHub Discussions feedback entry" --color "0e8a16"` |
| "Feedback & Ideas" category | Required Discussion intake point                    | Create via GitHub repository Settings → Discussions → Categories                                                              |
| Sample Discussion A         | Promote path (≥ 3 upvotes or ≥ 2 distinct comments) | Create manually in "Feedback & Ideas" via GitHub UI; add upvote reactions or comments                                         |
| Sample Discussion B         | Duplicate path                                      | Create manually; ensure title/body shares ≥ 3 keywords with an existing open issue                                            |
| Sample Discussion C         | Out-of-scope path                                   | Create manually with a support question or downstream-specific request                                                        |

---

## Troubleshooting

| Symptom                                                  | Likely cause                                             | Fix                                                                                                                  |
| -------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `gh label list \| grep feedback-staging` returns nothing | Label was not created                                    | Run the `gh label create` command from `07-feedback-triage-protocol.md` Prerequisites section                        |
| "Feedback & Ideas" category not visible in Discussions   | Category was not created                                 | Create it via GitHub Settings → Discussions → Categories                                                             |
| GraphQL query for Discussions returns an error           | Wrong category ID or Discussions not enabled             | Re-run the category ID query; confirm `hasDiscussionsEnabled: true` via `gh repo view --json hasDiscussionsEnabled`  |
| Promoted issue is missing the `feedback-staging` label   | Label name typo or label not created                     | Confirm label exists with `gh label list`; re-apply label with `gh issue edit <number> --add-label feedback-staging` |
| Discussion closed without a comment                      | Triage runner skipped the mandatory closing comment step | Re-open the Discussion, add the required comment, then close it again                                                |

---

## Known Limitations

- The initial version of the triage protocol is interactive-only (requires a maintainer to review and confirm each action). Non-interactive/batch mode is out of scope for this release.
- Comment count for the signal threshold check (`comments.totalCount`) counts all comments including the original poster's replies. When `totalCount` is borderline (1–2), the triage runner should manually verify that at least one comment is from a distinct user other than the original poster.
- The `gh` CLI does not support creating GitHub Discussions categories; this step requires the GitHub UI.
