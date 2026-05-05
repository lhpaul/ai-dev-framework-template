# Contributing

Thank you for your interest in this project! This document explains how to contribute
feedback and ideas as an external community member.

---

## Submitting Feedback and Ideas

If you have a suggestion, a feature request, or feedback about the template workflow,
please open a **GitHub Discussion** in the **Feedback & Ideas** category — do **not**
open a GitHub Issue for feature requests or general ideas.

**Why Discussions, not Issues?**

The Issues backlog is reserved for tracked work items that maintainers have already
decided to pursue. Unfiltered feature requests mixed into Issues make it harder to
manage in-progress work. GitHub Discussions gives your feedback a permanent home where
other community members can upvote and comment, letting signal build naturally before
a maintainer triages it.

### How to submit

1. Go to the repository's Discussions page (navigate to the **Discussions** tab on
   GitHub).
2. Click **New discussion** and choose the **Feedback & Ideas** category.
3. Give your discussion a descriptive title and describe your feedback in the body.
   Include concrete examples, affected protocols or scripts, and any workarounds you
   are currently using.
4. Submit the discussion. Other community members can upvote (thumbs-up reaction on
   the opening post) or comment.

### What happens to your feedback?

Maintainers periodically run a **feedback triage protocol** to review open discussions.
During a triage run:

- Discussions are evaluated against a **signal threshold**: a discussion is a candidate
  for promotion if it has **at least 3 upvote reactions** on the opening post **or at
  least 2 comments from distinct users** (other than the original poster).
- Candidate discussions that are not duplicates of existing tracked items and are
  in-scope for this template may be promoted to a tracked backlog issue.
- Duplicate discussions are closed with a comment linking to the existing issue.
- Out-of-scope discussions (support questions, project-specific downstream requests,
  general questions) are closed with a polite explanatory comment.

**Triage cadence**: at least once per month. The schedule is a guideline — there is no
guarantee of a specific turnaround time.

**Submitting feedback is not a commitment to implement it.** Maintainers evaluate
community signal alongside roadmap priorities, scope fit, and implementation cost.
High-signal discussions in scope for the template are more likely to be promoted, but
promotion itself does not mean the item will be implemented in any particular timeframe.

### What is in scope?

This template focuses on AI-assisted development workflow tooling. Discussions in scope
for promotion include:

- Template workflow improvements (new or improved protocols, agent instructions, scripts)
- Tooling gaps in existing protocol scripts or agent outputs
- Protocol deficiencies (ambiguous, incomplete, or missing protocol steps)
- Configuration usability issues (`.ai-dev-workflow.yaml`, setup, onboarding)

Out of scope (will be closed with a helpful comment):

- Support questions ("How do I configure X for my project?")
- Project-specific (downstream) customization requests ("Can you add support for my
  framework?")
- General programming questions unrelated to the workflow template

If you are looking for help with your own project built on this template, consider
opening a Discussion in the **Q&A** category instead (if available), or search the
existing Issues and Discussions for prior answers.

---

## If You Accidentally Open an Issue

If you open a GitHub Issue for a feature request or idea, a maintainer may close it
and ask you to repost in Discussions. This is not a rejection of your idea — it is
just routing it to the right place so it can accumulate signal and be triaged fairly.

---

## Triage Protocol Reference

Maintainers follow
[`docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md`](docs/workflow/development-workflow/protocols/07-feedback-triage-protocol.md)
when running a triage session. That document defines the full signal threshold criteria,
duplicate detection rules, promoted issue format, and closing comment requirements.
