# Bugbot Automated PR Reviewer Platform Support — Spec

---

## Overview

The framework reviewer loop coordinates a set of automated pull-request review
platforms (such as Greptile, Devin, PR-Agent, CodeRabbit, Codex, Copilot,
Claude Code Action, and Haystack) before a PR is allowed to reach human review.
This feature adds **Cursor Bugbot** as a first-class supported reviewer platform
in that loop, so that downstream repositories can declare Bugbot as one of their
automated reviewers and have its findings gate PR readiness consistently with
every other platform. Bugbot participates as a member of the existing review
workflow — it does not replace the pre-PR internal review gate or the human
review step.

---

## Background

The framework expresses each automated reviewer as a named platform that can be
listed in a repository's workflow configuration under the draft-PR reviewer set
or the ready-PR reviewer set. When the reviewer loop runs, it triggers each
configured platform, waits for that platform's verdict, classifies the verdict,
and emits a uniform set of telemetry that the orchestration layer uses to decide
whether the PR may advance toward human review. Today there is no way to declare
or run Cursor Bugbot through this mechanism, even though it is one of the review
tools available to teams that adopt Cursor. This work adds Bugbot to the
supported platform set so it behaves identically, from an operator's point of
view, to the other reviewers already integrated.

---

## Goals

- Make Bugbot selectable as an automated PR reviewer platform in the framework
  reviewer loop, on the same footing as the platforms already supported.
- Ensure Bugbot's review verdict and findings gate PR readiness the same way
  other platforms do: blocking findings hold the PR back, a clean run lets it
  progress, and ambiguous states (timeout / unavailable) are surfaced rather
  than silently treated as clean.
- Give operators clear, uniform visibility into Bugbot's outcome through the
  same telemetry the loop already produces for other platforms.

---

## Non-Goals

- This feature does not replace, weaken, or bypass the pre-PR internal review
  gate or the required human review before merge.
- This feature does not change the verdict, classification, triggering, or
  telemetry behavior of any platform other than Bugbot.
- This feature does not author the downstream Bugbot configuration/setup
  documentation (`.cursor/BUGBOT.md` guidance, setup walkthrough, rollout
  defaults). That documentation is a separate child of the parent epic.
- This feature does not audit or change non-reviewer Cursor surfaces (commands,
  agents, rules, skills). That parity work is a separate child of the parent
  epic.

---

## Use Cases

### Use Case 1: Operator declares Bugbot as a reviewer for a repository

**Actor**: Repository maintainer / workflow operator
**Preconditions**: The Cursor GitHub App that provides Bugbot is installed on
the repository, and the repository uses the framework reviewer loop.

**Steps**:

1. The operator lists Bugbot as one of the automated reviewers in the
   repository's workflow configuration, under either the draft-PR reviewer set
   or the ready-PR reviewer set.
2. The operator runs the reviewer loop on a pull request (or lets the
   orchestration run it).
3. The loop recognizes Bugbot as a known platform and runs it as part of the
   configured reviewer set.

**Postconditions**: Bugbot runs as a participating reviewer and contributes its
verdict to the PR's readiness decision, alongside any other configured
reviewers.

**Information shown**:

- The reviewer loop's per-platform telemetry includes a Bugbot entry with its
  outcome and finding counts, in the same shape used for other platforms.

**Actions available**:

- The operator can place Bugbot in the draft-PR set or the ready-PR set,
  defaulting to the ready-PR set unless the repository has enabled Bugbot
  review on draft PRs.

**Considerations**:

- If Bugbot is not configured for the repository, the loop must not block on it;
  an unconfigured platform is simply not run.

---

### Use Case 2: Bugbot reports blocking findings on a PR

**Actor**: Reviewer loop (system), acting on a PR under review
**Preconditions**: Bugbot is a configured reviewer for the repository and a PR
is open.

**Steps**:

1. The loop ensures Bugbot has been asked to review the PR, requesting a fresh
   review when one is needed.
2. The loop waits for Bugbot's verdict on the current state of the PR.
3. Bugbot returns one or more findings it considers blocking.
4. The loop classifies the run as having blocking findings, summarizes those
   findings, and reports them.

**Postconditions**: The PR is **not** allowed to reach the human-review-ready
state until the blocking findings are addressed.

**Information shown**:

- A summary of the blocking Bugbot findings, including enough context for a
  developer to locate and fix each one.
- Telemetry reflecting the blocking outcome and the number of findings.

**Considerations**:

- A finding Bugbot raises about a specific location must carry enough context to
  be actionable when summarized.
- The loop must reflect findings against the current state of the PR, not a
  stale earlier state.

---

### Use Case 3: Bugbot reports no findings on a PR

**Actor**: Reviewer loop (system), acting on a PR under review
**Preconditions**: Bugbot is a configured reviewer for the repository and a PR
is open.

**Steps**:

1. The loop ensures Bugbot has reviewed the current state of the PR.
2. Bugbot returns a verdict with no blocking findings.
3. The loop classifies the run as clean for the Bugbot platform.

**Postconditions**: Bugbot no longer holds the PR back; the PR may progress to
the subsequent CI and readiness steps (subject to other reviewers and gates).

**Information shown**:

- Telemetry reflecting a clean outcome and a finding count consistent with "no
  blocking findings".

**Considerations**:

- A non-blocking informational note from Bugbot must not be miscounted as a
  blocking finding, and must not by itself hold the PR back.

---

### Use Case 4: Bugbot times out or is unavailable

**Actor**: Reviewer loop (system), acting on a PR under review
**Preconditions**: Bugbot is a configured reviewer for the repository and a PR
is open.

**Steps**:

1. The loop asks Bugbot to review and waits for a verdict.
2. Within the allotted wait, Bugbot's verdict either never appears, or the
   underlying review service is unavailable / errors out.
3. The loop classifies the run as a timeout or unavailable state — explicitly
   distinct from a clean outcome.

**Postconditions**: The ambiguous outcome is surfaced to the operator /
orchestration as a non-clean, non-blocking-but-unresolved state. The PR is not
advanced to readiness on the basis of an absent Bugbot verdict.

**Information shown**:

- Telemetry that explicitly distinguishes the timeout / unavailable outcome from
  a clean run.

**Considerations**:

- A missing or never-published Bugbot result must never be interpreted as
  "passed". Absence of findings due to absence of a verdict is not the same as a
  clean verdict.

---

## Business Rules

- Bugbot is a recognized, selectable reviewer platform wherever the framework's
  other automated reviewer platforms can be selected.
- Bugbot may be placed in either the draft-PR reviewer set or the ready-PR
  reviewer set. The recommended default placement is the ready-PR set, unless
  the downstream repository has enabled Bugbot review on draft PRs.
- A Bugbot run with one or more blocking findings holds the PR out of the
  human-review-ready state until those findings are resolved.
- A Bugbot run with no blocking findings does not hold the PR back and allows it
  to progress toward CI and readiness, subject to other gates.
- A Bugbot timeout, an unavailable review service, or an absent verdict is
  surfaced as an explicit non-clean outcome and must never be treated as a clean
  pass.
- Bugbot's review findings are read in a form that lets the loop summarize the
  blocking ones with enough detail (severity and location context) for a
  developer to act on them.
- Bugbot's review threads are included in the framework's platform thread
  auditing wherever that auditing applies to comparable reviewer platforms.
- Adding Bugbot must not alter the behavior of any other reviewer platform, nor
  alter the loop's behavior for repositories that do not configure Bugbot.

---

## Acceptance Criteria

<!-- Each criterion must be testable — a human can verify it by following a smoke test. -->

- [ ] AC-1: A repository can list Bugbot as an automated reviewer in its
      workflow configuration, under either the draft-PR reviewer set or the
      ready-PR reviewer set, and the reviewer loop recognizes and runs it.
- [ ] AC-2: When the reviewer loop runs Bugbot, it emits the standard
      per-platform telemetry — overall result, the platform entry, comment
      count, blocking count, and suggestion count — in the same shape produced
      for other platforms.
- [ ] AC-3: When Bugbot returns one or more blocking findings, the loop
      classifies the run as blocking and the PR is kept out of the
      human-review-ready state until the findings are addressed.
- [ ] AC-4: When Bugbot returns no blocking findings, the loop classifies the
      run as clean and the PR is allowed to progress toward CI and readiness
      (subject to other gates).
- [ ] AC-5: When Bugbot times out, is unavailable, or never publishes a verdict,
      the loop reports an explicit timeout / unavailable outcome that is
      distinct from a clean run and does not advance the PR on the basis of the
      missing verdict.
- [ ] AC-6: Blocking Bugbot findings are summarized with severity and location
      context sufficient for a developer to locate and fix each one.
- [ ] AC-7: Bugbot's review threads are included in platform thread auditing
      wherever that auditing applies to comparable reviewer platforms.
- [ ] AC-8: Adding Bugbot does not change the behavior of any other reviewer
      platform, and a repository that does not configure Bugbot sees no change
      in reviewer-loop behavior.
- [ ] AC-9: The behaviors above are covered by tests that exercise
      representative Bugbot review outcomes — at minimum a blocking-findings
      outcome, a no-findings outcome, and a timeout / unavailable outcome.

---

## Coverage Matrix

This work item is backed by tracker issue #990. Every brief objective and
acceptance criterion from the tracker maps to a spec acceptance criterion or to
an explicit Out-of-Scope entry below.

| Brief objective (from #990) | Mapped to |
| --- | --- |
| Add a Bugbot platform handler to the reviewer loop | AC-1, AC-8 |
| Trigger Bugbot with a top-level PR comment when needed | AC-1, AC-3, AC-4 (covered behaviorally via "ensure a fresh review when one is needed"; exact trigger phrase is an implementation detail) |
| Poll the Bugbot check on the PR head and classify success / neutral / failure / timeout / missing states | AC-3, AC-4, AC-5 |
| Read Bugbot reviews/comments (review markers, finding identifiers, locations, severity) to summarize blocking findings | AC-6 |
| Include Bugbot's bot identity in platform thread auditing where applicable | AC-7 |
| Add tests with representative Bugbot check/review/comment payloads | AC-9 |
| Tracker AC: config can list `bugbot` under draft or ready reviewer set | AC-1 |
| Tracker AC: loop emits normal result / platform / comment / blocking / suggestion telemetry | AC-2 |
| Tracker AC: blocking findings keep the PR out of `ready-for-human-review` | AC-3 |
| Tracker AC: no-finding runs can progress to CI / readiness | AC-4 |
| Tracker AC: timeout / unavailable states surfaced explicitly, not treated as clean | AC-5 |
| Tracker AC: Project Type is Feature | Tracker classification (not a spec deliverable) — recorded here for traceability |

No brief objective is silently dropped. The two items mapped to Out of Scope
below carry Deferral Notes.

---

## Dependencies

This feature extends the existing framework reviewer loop and its platform
configuration surface. It depends on the reviewer-loop platform mechanism that
already supports the other automated reviewers, and on the Cursor GitHub App
being installed on the downstream repository so that Bugbot can review and
publish its result there. It does not depend on the sibling epic children
(Cursor surface parity and Bugbot setup documentation), which can proceed
independently.

---

## Implementation Scope

In scope:

- Bugbot is a recognized, selectable reviewer platform in the reviewer loop's
  configurable platform set (draft-PR set and ready-PR set).
- The loop triggers Bugbot, waits for its verdict, classifies the verdict
  (clean / blocking / timeout / unavailable / missing), summarizes blocking
  findings, and emits the standard per-platform telemetry.
- Bugbot's review threads are included in platform thread auditing where
  applicable.
- Tests covering the representative Bugbot outcomes listed in AC-9.

Deferred to the implementation plan (technical design, not product scope):

- The exact configuration key value, trigger phrase, polling cadence, wait /
  timeout budget, bot identity string, check-run name, and finding-parsing
  details.
- The precise mapping of Bugbot's reported states to the loop's internal result
  codes.

---

## Out of Scope (MVP)

- **Downstream Bugbot setup documentation** (setup walkthrough, `.cursor/BUGBOT.md`
  guidance, check-conclusion reference, rollout defaults). **Deferral Note**:
  the parent epic (#988) explicitly assigns this documentation to a separate
  child issue; this item is scoped to the reviewer-loop platform support only.
  Human confirmation not required — this boundary is set by the epic scope.
- **Cursor non-reviewer surface parity** (commands, agents, rules, skills audit).
  **Deferral Note**: the parent epic (#988) assigns this to a separate child
  issue; it is unrelated to reviewer-loop platform support. Human confirmation
  not required — this boundary is set by the epic scope.
- Changing the behavior, triggering, or telemetry of any reviewer platform other
  than Bugbot.
- Auto-resolving or auto-fixing Bugbot findings; this feature surfaces and gates
  on findings but does not resolve them.
