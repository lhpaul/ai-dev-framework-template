# Document Bugbot Setup and Framework Rollout Guidance — Spec

---

## Overview

Framework adopters who use Cursor as their primary agent surface need clear,
authoritative guidance on how to enable Cursor Bugbot and how it fits into the
staged AI development workflow. Today the workflow documents several automated
PR review tools (CodeRabbit, Haystack, PR-Agent, Greptile, Devin, Copilot,
Claude Code Action) but has no guidance for Bugbot, leaving adopters without a
canonical place to learn how to configure it, where it sits in the review
lifecycle, or how its known behaviors (such as neutral check conclusions)
interact with branch protection. This feature delivers a dedicated Bugbot
integration guide plus the cross-references and rollout guidance needed for a
downstream team to adopt Bugbot confidently. It is a documentation-only feature:
it changes what the framework explains, not how any script behaves.

---

## Use Cases

### Use Case 1: A downstream maintainer enables Bugbot for their repository

**Actor**: Framework adopter / repository maintainer
**Preconditions**: The maintainer has a repository created from this template and
uses Cursor as their primary agent surface.

**Steps**:

1. The maintainer opens the new Bugbot integration guide from the integrations
   index.
2. The maintainer follows the GitHub/Cursor setup instructions, including the
   repository access Bugbot requires.
3. The maintainer learns where Bugbot is declared in the workflow integration
   manifest and what value to add.
4. The maintainer reads how Bugbot reports its status on a pull request,
   including the check name(s), the possible check conclusions, how to trigger a
   manual review, and how automatic review settings behave.
5. The maintainer confirms the expected behavior on draft pull requests and
   reviews the Autofix considerations before enabling it.

**Postconditions**: The maintainer has enabled Bugbot and knows exactly where to
configure it and what to expect on their pull requests.

**Information shown**:

- The setup steps for connecting Bugbot to GitHub and Cursor.
- The required repository access for Bugbot to operate.
- The workflow integration manifest entry used to declare Bugbot.
- The Bugbot check name(s), possible check conclusions, manual trigger method,
  automatic review settings, draft-PR behavior, and Autofix considerations.

**Considerations**:

- The guide must state that Bugbot is currently not yet wired into the
  repository's automated reviewer loop helper and is therefore reported as
  skipped by that loop until an adapter exists. This avoids implying behavior the
  tooling does not yet provide.

---

### Use Case 2: A team aligns Bugbot rules with the review contract

**Actor**: Framework adopter / repository maintainer
**Preconditions**: Bugbot is enabled (Use Case 1) and the repository has a review
contract document.

**Steps**:

1. The maintainer reads the guidance on the repository-level Bugbot rules file
   and any nested per-directory Bugbot rule files.
2. The maintainer copies the provided minimal repository-level Bugbot rules
   template into their repository.
3. The maintainer follows the guidance on keeping Bugbot rules aligned with the
   review contract by referencing it rather than duplicating the entire contract.

**Postconditions**: The repository has a starting Bugbot rules file whose intent
is consistent with the review contract, without restating the whole contract.

**Information shown**:

- What the repository-level Bugbot rules file is for and where it lives.
- How nested Bugbot rule files apply to specific directories.
- A minimal repository-level Bugbot rules template the maintainer can copy.
- Guidance on referencing the review contract instead of duplicating it.

**Considerations**:

- The template must be minimal and copy-ready; it must not reproduce the full
  review contract.

---

### Use Case 3: A client team using Cursor rolls Bugbot out across the workflow

**Actor**: Framework adopter / team lead at a client using Cursor as the primary
agent surface
**Preconditions**: The team uses Cursor for day-to-day development and follows the
staged AI development workflow.

**Steps**:

1. The team lead reads the rollout guidance section written for teams that use
   Cursor as their primary agent surface.
2. The team lead learns where Bugbot sits in the staged workflow: it is
   post-push validation and does not replace the pre-PR review gate.
3. The team lead reviews the branch protection implications of Bugbot's known
   neutral check behavior before deciding whether to make Bugbot a required
   check.

**Postconditions**: The team has a clear adoption path for Bugbot that does not
weaken the existing pre-PR review gate and accounts for neutral-check behavior in
branch protection decisions.

**Information shown**:

- Where Bugbot fits in the staged workflow relative to the pre-PR review gate.
- The known neutral check behavior and its branch protection implications.
- Rollout guidance tailored to Cursor-primary teams.

**Considerations**:

- The rollout guidance must reinforce that Bugbot is complementary post-push
  validation, not a substitute for the pre-PR review gate.

---

## Business Rules

- The Bugbot integration guide must live alongside the other automated PR review
  tool guides in the integrations area of the development workflow docs.
- The documentation must state that Bugbot is post-push validation and does not
  replace the pre-PR review gate defined in the review contract.
- The documentation must describe Bugbot's known neutral check behavior and its
  implications for branch protection (for example, whether and how to make Bugbot
  a required check).
- The documentation must explain where Bugbot is declared in the workflow
  integration manifest so a downstream team knows where to configure it.
- Because Bugbot is not yet supported by the repository's automated reviewer loop
  helper, the documentation must describe Bugbot as planned-but-unsupported by
  that loop and reported as skipped there, consistent with the generic automated
  PR review platform guidance.
- The minimal repository-level Bugbot rules template must reference the review
  contract rather than duplicate it in full.
- Cross-references to the new guide must be added to the generic automated PR
  review platform guide and any relevant index/README/agent-guidance references,
  so the new guide is discoverable.

---

## Acceptance Criteria

- [ ] A new Bugbot integration guide exists alongside the other automated PR
      review tool guides in the development workflow integrations area, and is
      reachable from the integrations index/README listing.
- [ ] The guide documents the GitHub/Cursor setup, the required repository
      access, the Bugbot check name(s), the possible check conclusions, how to
      trigger a manual review, the automatic review settings, the draft pull
      request behavior, and the Autofix considerations.
- [ ] The guide explains where Bugbot is declared in the workflow integration
      manifest so a downstream team knows where to configure it.
- [ ] The guide explicitly states that Bugbot is post-push validation and does
      not replace the pre-PR review gate.
- [ ] The guide describes the known neutral check behavior and its branch
      protection implications.
- [ ] The guide includes a minimal, copy-ready repository-level Bugbot rules
      template (or an equivalent clearly marked guidance section) and explains
      nested Bugbot rule files.
- [ ] The guide explains how to keep Bugbot rules aligned with the review
      contract by referencing it rather than duplicating the entire contract.
- [ ] The guide includes rollout guidance for client teams that use Cursor as
      their primary agent surface.
- [ ] The guide states that Bugbot is currently planned-but-unsupported by the
      repository's automated reviewer loop helper and is reported as skipped by
      that loop until an adapter exists, consistent with the generic automated PR
      review platform guidance.
- [ ] The generic automated PR review platform guide cross-references the new
      Bugbot guide, and any relevant README/agent-guidance references that list
      review-tool integrations are updated to include it.

---

## Coverage Matrix

| Brief objective | Covered by |
| --- | --- |
| Add a Bugbot integration guide under the integrations area | AC-1 |
| Document GitHub/Cursor setup, required repository access, check names, check conclusions, manual triggers, automatic review settings, draft PR behavior, and Autofix considerations | AC-2 |
| Add guidance for the repository-level Bugbot rules file, nested Bugbot rule files, and keeping Bugbot rules aligned with the review contract without duplicating it | AC-6, AC-7 |
| Update the generic automated PR review platform guide and relevant README/agent references | AC-10 |
| Include rollout guidance for client teams using Cursor as their primary agent surface | AC-8 |
| Downstream team can enable Bugbot and know where to configure it in the workflow integration manifest | AC-3 |
| Docs explain Bugbot is post-push validation and does not replace the pre-PR review gate | AC-4 |
| Docs describe known neutral-check behavior and branch protection implications | AC-5 |
| Docs include a minimal repository-level Bugbot rules template or guidance section | AC-6 |
| Project Type is Feature | Tracker metadata (no spec artifact required); see Deferral Note |

---

## Out of Scope (MVP)

- Implementing a Bugbot adapter in the repository's automated reviewer loop
  helper (i.e., making `bugbot` a runnable platform value in the review loop
  script). This spec documents Bugbot's place in the workflow and records that it
  is planned-but-unsupported by the loop; building the adapter is a separate
  implementation item.
- Changing the default review platform configuration of this template repository
  to enable Bugbot by default. The template documents how adopters opt in; it does
  not turn Bugbot on for the template itself.
- Authoring exhaustive, vendor-maintained Bugbot reference material that
  duplicates Cursor's own product documentation; the guide links out for
  product-level detail and focuses on workflow integration.

### Deferral Notes

- **"Project Type is Feature"**: This brief item is a tracker classification
  requirement, satisfied by setting the GitHub Projects Type field to `Feature`
  on the issue. It is not a documentation deliverable and produces no spec or
  guide content. No human confirmation requested.
- **Bugbot review-loop adapter**: Deferred because the brief scope is
  documentation and rollout guidance, and the generic platform contract already
  defines how an unsupported-but-planned platform is reported (skipped). Building
  the adapter is a code change with its own acceptance criteria and belongs to a
  separate work item. Human confirmation requested before closing the epic if the
  adapter is expected within this epic's scope.
