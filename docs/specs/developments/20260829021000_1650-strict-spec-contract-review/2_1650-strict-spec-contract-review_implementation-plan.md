# Strict Spec Contract Review — Implementation Plan

**Spec**:
[1_1650-strict-spec-contract-review_specs.md](./1_1650-strict-spec-contract-review_specs.md)
**Smoke test runbook**:
[1650-strict-spec-contract-review.smoke-test.md](../../../testing/workflow/1650-strict-spec-contract-review.smoke-test.md)

---

## Summary

**Approach**: Three of the four pieces already have a shape in this epic. A
checklist document supplied to the reviewer when the stage matches is #1654's
catalogue pattern; the stage itself is #1653's resolution; the state-and-count
reporting is the `key=value` and evidence plumbing both use.

The fourth piece is the one with no precedent and is where this plan spends its
attention: **the reviewer's parser has no third class of finding.** It sorts
each finding into blocking or advisory, and — this is the part that matters —
anything it cannot sort is counted as **blocking**. Strict findings must be
neither. Emitted without a change to that parser, eight new checks would turn
every spec review red.

So the strict checks get **their own invocation**. The ordinary review runs
exactly as it does today — same prompt, same bundle, same parser — and its
verdict is whatever that unchanged parser computes; the checks run as a second
call whose response carries findings and no verdict, and whose output the parser
is never allowed to merge into the blocking block. AC-3 is then structural rather than promised: the
model that decides the verdict never sees the checklist.

**Estimated complexity**: M

**Rationale**: The document, the supply and the reporting are each small and
patterned on merged plans. The parser change is not: it sits in a `jq` program
whose current invariant is *every finding is blocking unless proven advisory*,
and this feature adds a class that is neither while that invariant must keep
holding for everything else.

**Dependencies**: **#1653 must be implemented and merged before this item's
implementation PR opens** — the checks run only at the spec stage, and the
stage resolution is #1653's. **#1654 is not a dependency but overlaps**: both
add a document supplied through the context bundle and both add `print_kv`
lines. Whichever lands second inherits the other's fields; the plan records the
seam in **Interaction with #1654** rather than sequencing them.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `85dea08b` |
| The parser has two classes, and the residue is blocking | `sed -n '440,480p' scripts/development-workflow/local-ai-reviewer.sh` | `blocking` and `advisory` are `jq` predicates over severity and scope text. `$unknown` is `blocking \| not` **and** `advisory \| not`, and `$blocking_findings` is `blocking or ((blocking \| not) and (advisory \| not))` — so a finding matching neither predicate is emitted as blocking |
| An unclassifiable finding also forces `needs_fixes` | `sed -n '473,476p' scripts/development-workflow/local-ai-reviewer.sh` | `if $unknown > 0 then … RESULT=needs_fixes` — regardless of what the reviewer itself concluded. This is the behaviour strict findings must be exempted from, and the exemption must not weaken it for anything else |
| Blocking findings are what the loop forwards | Same range | `BLOCKING_<n>_PATH` / `_LINE` / `_BODY` are emitted from `$blocking_findings` only. A strict finding must not appear there, or the loop will treat it as a blocker regardless of the reviewer's own count |
| The bundle is built in one `jq -n` call | `sed -n '339,366p' scripts/development-workflow/local-ai-reviewer.sh` | Thirteen fields at this revision; #1653 adds three and #1654 four. **This plan adds none there**: it derives the strict bundle from that call's output file instead, so the ordinary bundle stays byte-identical and the site is uncontended |
| The reviewer command has exactly one invocation site | `grep -n 'LOCAL_AI_REVIEWER_COMMAND' scripts/development-workflow/local-ai-reviewer.sh` | Seven matches, of which one executes: line 380, `run_with_timeout … sh -c "$LOCAL_AI_REVIEWER_COMMAND"`. A second pass is a second call at that same site with a different bundle, not a new integration |
| The invocation is already wrapped and its failure already handled | `sed -n '372,392p' scripts/development-workflow/local-ai-reviewer.sh` | `set +e` around the call, `command_exit` captured, exit 124 handled as a timeout with `print_result escalate`. The strict pass reuses the wrapper and handles its own non-zero status locally instead of reaching that path |
| The stage resolution is #1653's | #1653's merged plan | `review_stage` is `spec` for `spec/*` branches; the strict checks key on that value and resolve nothing themselves |
| Evidence keys reach the loop **summary** unchanged | `sed -n '754,772p' scripts/development-workflow/pr-review-loop.sh` | `emit_prefixed_platform_output` re-emits every key except five reserved ones, so `STRICT_SPEC_*` reaches the comment with no loop change |
| The **ledger** does not forward arbitrary keys | `sed -n '6876,6952p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_build_entry` builds a fixed `jq -n` object from named locals and globals; no platform `key=value` output is copied in. The `strict_spec` object has to be added there, which is this item's only change to `pr-review-loop.sh` |
| That function already takes state through globals | Same range, and its `run_id` comment | `unresolved_thread_count`, `late_thread_count` and `current_run_id` are read from globals set by the caller rather than passed positionally, explicitly to avoid growing the parameter list. The five strict values follow that convention rather than inventing one |

**What this log does not establish.** It does not show the cost of a second
invocation on a real spec review, which depends on the configured reviewer
command; the plan bounds *when* it happens rather than how long it takes. Nor
does it show how often the eight checks will fire. That is the measurement the spec defers to #1657, and the
reason this feature reports counts rather than blocking on them.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1650 | 2026-08-29, repo SHA `85dea08b` | Epic #1647 items | `Verified` |
| The stage resolution exists | `review_stage` = `spec`, from #1653 | #1653's merged plan | 2026-08-29, repo SHA `85dea08b` | #1653 and #1650 | `Conflict` — see below |
| The parser's residue-is-blocking rule | A finding matching neither predicate is emitted as blocking and forces `needs_fixes` | `local-ai-reviewer.sh:440-476` | 2026-08-29, repo SHA `85dea08b` | `local-ai-reviewer.sh` and its two suites | `Verified` |

**Conflict record.** The checks run only at the spec stage, and the stage
resolution does not exist on the base branch: #1653's plan is merged, its
implementation is not. Affected plan statements: the supply condition and every
scenario that exercises it.

**Resolution status**: `Resolved` by sequencing — **Implementation Order step
0**, a hard stop on #1653. Decision owner: LH — if #1653 is implemented with
different stage values, this plan must be revised rather than adapted.

### Not applicable

**Overall result for this check**: `Applicable` — the three rows above must be
re-verified at implementation start.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API, no deployment target.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Add the checklist**,
      `docs/workflow/development-workflow/strict-spec-checks.md`, one level-3
      section per check, in the spec's order, each carrying its identifier, its
      question and the shape of finding it produces.

      The identifiers are a **closed set**, and the document is where they are
      defined. The parser and the tests read them from here rather than
      repeating them, so a ninth check is one edit and not four.

- [ ] **Give the strict pass its own bundle, derived from the ordinary one.**
      The `jq -n` site is **not touched**. The ordinary bundle is built exactly
      as today and written to exactly the same file; the strict bundle is that
      file plus one key:

      ```text
      jq --rawfile checks "$checklist" \
        '. + { strict_spec_checks: $checks }' \
        "$context_file" >"$strict_context_file"
      ```

      **The ordinary pass's bundle is therefore byte-identical, not merely
      unchanged in content** — it is the same file, unmodified, and the strict
      bundle is a copy with one key added. An earlier revision added an empty
      `strict_spec_checks` to the shared bundle and claimed in the same document
      that the ordinary review was untouched; that was a contradiction, and this
      removes it rather than restating the claim more carefully.

      It also removes the collision with #1654: nothing here edits the `jq -n`
      object, so whichever item lands second has nothing to merge at that site.

      The text is read with `jq --rawfile`, as #1654's is and for the same
      reason.

      The state is not a bundle field. Rows 1 through 3 are decided by
      `local-ai-reviewer.sh` before it dispatches anything, and they decide
      whether the strict pass runs at all; rows 4 through 6 are decided by what
      the pass returns. The count is not here either: it is not known when the bundle is
      built, and it appears only in the output and the evidence.

- [ ] **Run the ordinary review exactly as today.** No edit to its prompt, no
      checklist in its bundle, no change to the `jq` program that reads its
      response, no new field it must emit.

      **The guarantee is that the parser is unchanged, not that `result` is
      passed through.** That parser does more than echo the reviewer: it
      overrides a `clean` result when blocking or unclassifiable findings are
      present, and derives a verdict when `result` is absent. Those behaviours
      predate this item and stay exactly as they are. Saying the verdict is
      emitted "verbatim" would describe a parser this repository does not have,
      and would be unverifiable against the one it does.

      **This is the whole of AC-3's mechanism, and it is structural.** AC-3 asks
      that a review with strict findings report the same verdict as *the same
      review with the strict checks disabled*. The ordinary pass **is** that
      review: same prompt, same inputs, same parser, same overrides. There is
      nothing for the strict checks to influence, because the model that
      produces the verdict never sees them and the code that computes it never
      receives their findings.

      Four earlier revisions of this plan tried to reach AC-3 from a single
      invocation that saw both, and each failed in a way the next one inherited.
      Downgrading `needs_fixes` when no ordinary blocker was parsed unblocks a
      reviewer that blocked for a reason it never wrote as a finding. Deriving
      the verdict from the ordinary findings is that same move renamed.
      Escalating when the ordinary verdict was unavailable introduces exactly
      the gate AC-18 forbids — "no label, no gate, no escalation". Asking the
      reviewer for a separate `ordinary_result` field and forwarding `result`
      when it was missing left the verdict influenceable and called the residue
      measurement.

      They failed for one reason: **a single invocation can only ever promise
      that what it read did not affect what it concluded, and no parser can
      audit that promise.** The information is not in the response. Two
      invocations do not need the promise.

- [ ] **Run the strict checks as their own invocation.** A second call to
      `LOCAL_AI_REVIEWER_COMMAND`, with the strict bundle and a prompt that asks
      for one thing: findings against the eight checks, each carrying
      `check: "<identifier>"`, a path, a line and a body.

- [ ] **Give the command a way to know which pass it is running, and a way to
      say it understood.** The prompt lives in the reviewer command, not in
      `local-ai-reviewer.sh`, so the mode has to cross that boundary explicitly:

      - `local-ai-reviewer.sh` exports **`LOCAL_AI_REVIEWER_MODE`** —
        `ordinary` or `strict` — beside `CONTEXT_BUNDLE_PATH` on each call.
      - `local-codex-review-command.sh` selects its prompt on that variable. Its
        prompt is hard-coded today and asks for the REVIEW.md verdict schema —
        `result`, `reviewed_head`, `findings[]` with `severity` and
        `clear_in_scope` — which is the wrong request for this pass. The strict
        prompt asks for `{ mode, findings: [{check, path, line, body}] }` and
        **no verdict**.
      - Its `LOCAL_CODEX_REVIEWER_PROMPT` override applies to the ordinary
        prompt only; a second variable, `LOCAL_CODEX_REVIEWER_STRICT_PROMPT`,
        overrides the strict one. Letting the existing override apply to both
        would send an ordinary-review instruction into the strict pass whenever
        anyone customised their reviewer.

      **The response must carry `mode: "strict_spec_checks"`, and the parser
      refuses it otherwise.** This is the part that matters, and it is about
      custom commands rather than the preset. `LOCAL_AI_REVIEWER_COMMAND` is
      configurable; a command that ignores `LOCAL_AI_REVIEWER_MODE` answers the
      strict call with an ordinary review — `result` plus `findings[]` carrying
      `severity` and no `check`. Every one of those findings would be classified
      `unknown`, and the pass would report `applied` with a large
      `unknown_count`: **an ordinary review recorded as a completed run of the
      strict checks**, putting fabricated incidence into #1657's data.

      A silent contract needs a positive acknowledgement, and the mode marker is
      it: absent or different means `strict_pass_failed`, so an unconfigured
      custom command degrades to "the checks did not run" rather than to
      invented numbers.

      **Its response has no verdict, and the parser reads none.** Any
      verdict-shaped key it emits — `result`, `status`, anything else — is
      ignored rather than merged, so a reviewer that volunteers one cannot
      affect the outcome by accident. That the strict pass cannot block is a
      property of what the parser reads, not of what the model was asked to
      write.

      It is dispatched exactly when the matrix's first three rows do not match:
      the stage resolves, it is `spec`, and the checklist is readable. Those
      three inputs decide the **call**; the state is decided afterwards by what
      the call returns, which is why row 4 is `unavailable` and was dispatched.
      Rows 1 through 3 dispatch nothing, which is why `not_applicable` reviews
      and the two never-attempted `unavailable` rows cost exactly what they
      cost today.

      **The cost is one extra invocation on spec-stage reviews**, and it is the
      price of the guarantee. It falls only on spec branches with a readable
      checklist, never on plans, implementations or refactors, and it is
      independent of #1656's second pass, which runs after a clean result rather
      than within a round.

      **That cost is elapsed time and never an outcome**, which is the
      distinction AC-16a draws and AC-16b bounds. The pass is dispatched
      synchronously through the existing `run_with_timeout` wrapper with
      **whatever remains of the review's `--timeout`** once the ordinary pass
      has returned — a deadline computed from the round's start, not a second
      budget. **No new timeout setting is introduced**, which AC-16c requires in
      as many words: a second knob, even a capped one, is one more place for two
      values to disagree about a bound whose purpose is that a round cannot
      outlast it.

      So a round that runs the checks is bounded by the same maximum as one that
      does not. It is typically slower; what it is not is less bounded. If
      nothing remains when the ordinary pass returns, the checks are not
      attempted and the round reports `strict_pass_failed` — **the same cause as
      any other failed attempt**, per AC-16d, because *the checks produced no
      result* is the whole of what a reader needs and a fourth cause would be a
      distinction nobody acts on differently.

      Deferring the pass — emitting the ordinary result first and the strict
      findings later — would buy nothing: the loop reads one `key=value` block
      per platform per round, so a late strict result would have to land in the
      next round or nowhere, and a count attributed to the wrong head is worse
      than a count that cost thirty seconds.

- [ ] **Handle the strict pass failing without touching the review.** A
      non-zero exit, an empty response, or output the findings parser cannot
      read leaves the state `unavailable` with reason `strict_pass_failed`, and
      the ordinary pass's verdict and findings are emitted as if the strict pass
      had never been attempted.

      **This is a matrix row the spec did not have**, and it is added by a
      separate spec pull request — row 4, the `strict_pass_failed` cause, and
      AC-16a — which is a **hard dependency of this plan**, listed in the
      Implementation Order's step 0. The spec's matrix claimed to be the
      complete gate over three ordered inputs, all three deciding whether the
      checks *start*; a dispatched pass that does not *finish* is a fourth input
      and was unenumerated.

      That omission is precisely the `gate_matrix` shape check 3 exists to
      catch, in the specification that defines check 3. It goes through the spec
      stage rather than riding along here: a plan pull request that edits its
      own approved spec is a workflow-stage violation, and the alternative — a
      plan silently adding a state its spec does not have — is the divergence
      this epic keeps finding in other people's documents.

- [ ] **Merge the two responses.** The verdict and `BLOCKING_<n>_*` come from
      the ordinary pass. `STRICT_<n>_*` comes from the strict pass. Nothing
      crosses:

      ```text
      RESULT / BLOCKING_<n>_*   <- ordinary pass, unchanged
      STRICT_<n>_*              <- strict pass, never merged into blocking
      STRICT_SPEC_*             <- computed by the script from both
      ```

      A strict finding placed in the blocking block would be forwarded by the
      loop as a blocker whatever the counts say, so the two blocks are built
      from two different arrays and never from one partitioned list.

- [ ] **Classify identifiers the checklist does not define.** A strict-pass
      finding whose `check` is not in the closed set is reported with
      `STRICT_<n>_CHECK=unknown`, is **excluded** from `STRICT_SPEC_COUNT` and
      `STRICT_SPEC_CHECKS`, and is counted in `STRICT_SPEC_UNKNOWN_COUNT`.

      **The fail-closed direction reverses here, and the reversal is the point.**
      In the single-invocation design an unrecognised marker had to be treated
      as an ordinary blocking finding, because the marker was a way to opt out of
      blocking: mislabel a real finding and it silently stops blocking. With two
      passes there is nothing to opt out of — a strict-pass finding was never in
      the blocking set — and promoting it into blocking would *add* a blocker
      the ordinary review did not raise, which is AC-3 broken in the other
      direction. So the unknown identifier is reported and counted apart
      instead: visible, attributable to no check, and inert.

      It is excluded from the count because the count feeds #1657's per-check
      incidence, and a finding that names no known check belongs to no check's
      rate. `STRICT_SPEC_UNKNOWN_COUNT` is what keeps that exclusion from being
      a silent discard.

      **`$known_checks` is read from the checklist** via `--argjson`, so the
      closed set has one definition and a ninth check needs no parser edit. How
      the document becomes that array is the next bullet: it is a contract, not
      an implementation detail.

- [ ] **Extract the identifiers from the checklist, and refuse an ambiguous
      document.** The checklist's section heading **is** the identifier:

      ```text
      ### <identifier>
      ```

      one level-3 heading per check, the identifier alone on the line, matching
      `[a-z][a-z0-9_]*` — the same shape as the spec's eight names. The
      question and the finding shape follow as prose beneath it.

      Extraction is two commands, and the second is the validation. Both run
      inside `local-ai-reviewer.sh`, which sets `set -euo pipefail` at line 7,
      so neither may be written bare:

      ```text
      status=0
      declared="$(grep -c '^### ' "$checklist")" || status=$?
      if [ "$status" -eq 1 ]; then
        declared=0                       # no headings: a refusal, not a crash
      elif [ "$status" -ne 0 ]; then
        strict_spec_unreadable; return 0 # grep itself failed
      fi

      ids="$(sed -n 's/^### \([a-z][a-z0-9_]*\)[[:space:]]*$/\1/p' \
               "$checklist")" || { strict_spec_unreadable; return 0; }
      known="$(printf '%s\n' "$ids" \
               | jq -R -s 'split("\n") | map(select(length > 0))')" \
        || { strict_spec_unreadable; return 0; }
      ```

      **`grep -c` exits 1 when it matches nothing**, and under `set -e` that
      ends the script — on the *exact* input the refusal tests are written to
      exercise. A checklist with no level-3 headings would kill the reviewer
      before it could report `unavailable`, so the one case with no findings to
      report would instead produce no review at all. The status is therefore
      read explicitly, and **exit 1 is separated from exit greater than 1**:
      the first is "no headings", a refusal; the second is grep failing, which
      is also a refusal but not the same fact, and conflating them would report
      a broken document where the tool broke. #1654 hit this same pair in
      `review-doctrine-lint.sh` and resolved it the same way.

      The `sed` is split from the `jq` for `pipefail`'s sake: piped directly,
      a `jq` failure and a `sed` failure are one status, and the intermediate
      value is wanted anyway.

      Then three tests, all of which mean **`unavailable` with reason
      `checklist_unreadable`**, and none of which mean "carry on with what
      parsed":

      1. `known` is empty — a document with no identifiers is not a checklist.
      2. `known | length` differs from `declared` — a level-3 heading the
         pattern did not match. `### Ambiguous Phrase` is a section a reader
         sees and the extractor does not.
      3. `known | length` differs from `known | unique | length` — the same
         identifier twice, which would make one check's incidence
         double-counted and the other's invisible.

      **Test 2 is the one worth arguing for.** Without it the extractor
      *silently drops* a malformed section: the reviewer is handed seven checks,
      reports against seven, and the count reads as a completed run. That is
      the failure this whole feature exists to prevent — a review that looks
      like it happened — reproduced inside the mechanism meant to detect it. So
      the extractor refuses the document rather than working with the part of it
      it understood.

      `checklist_unreadable` covers all three. The spec's cause is "missing or
      unreadable", and a document that cannot be turned into a usable identifier
      set is unreadable in the only sense that matters here. **No fourth cause
      is added**: the owner is the same in every case — whoever edits the
      checklist — and splitting it further would put a distinction in the data
      that nobody acts on differently.

      The eight identifiers are checked against the spec's list at
      implementation time, by extraction rather than by reading, and that
      comparison is Implementation Order step 1.

- [ ] **Report the state and the count.** Five `print_kv` keys beside the
      existing block — **one** always emitted, four conditional:

      ```text
      # always emitted
      STRICT_SPEC_STATE=applied|not_applicable|unavailable

      # conditional
      STRICT_SPEC_COUNT=<n>             # only when applied; may be 0
      STRICT_SPEC_CHECKS=<ids>          # comma-separated; only when applied
      STRICT_SPEC_UNKNOWN_COUNT=<n>     # only when applied and above zero
      STRICT_SPEC_REASON=stage_unresolved|checklist_unreadable|strict_pass_failed
                                        # only when unavailable
      ```

      **`unavailable` has three causes and they have different owners**, which
      is why the state alone is not enough: `stage_unresolved` is a branch the
      resolver could not classify, `checklist_unreadable` is a missing or
      unreadable document, and `strict_pass_failed` is a dispatched pass that
      did not return usable output. The first is a defect in the pull request's
      shape, the second in the repository's contents, the third in the reviewer
      command or its environment — three different people to go and see, and a
      reader given only `unavailable` cannot tell which. The spec's outcome
      table requires the cause to be reported; the reason key is where it
      lives.

      **Only the state is unconditional**, and the spec's outcome table is
      explicit about why: outside `applied` there is *no count*, not a count
      that happens to be empty. A key present where it has no meaning invites a
      reader to interpret it, and the state is enough to tell the three
      situations apart — #1657's denominator is the set of rounds whose state is
      `applied`, which needs no second key to compute.

      `STRICT_SPEC_COUNT` and `STRICT_SPEC_CHECKS` are **absent** in the two
      non-applied states, never `0` and never an empty list rendered as
      something. The spec's reason: `0` means the checks ran and found nothing,
      and it is the only thing distinguishing a clean specification from one
      they never examined. A `0` written for `unavailable` would put unexamined
      rounds into the denominator of #1657's rate.

      The same five go into the evidence JSON under a `strict_spec` object and
      into the ledger entry, so incidence can be computed per pull request
      without re-reading comments.

      **One rule governs both surfaces: the object mirrors the output.** A key
      emitted in the `key=value` block is a field in the object; a key not
      emitted is a field that is **absent**, not present and null. So on every
      review, at any stage:

      | | `key=value` output | `strict_spec` object |
      | --- | --- | --- |
      | `state` | always, with a value | always, with a value |
      | `count` | only when `applied`; may be `0` | present only when `applied` |
      | `checks` | only when `applied` | present only when `applied` |
      | `unknown_count` | only when `applied` and above zero | present only when `applied` and above zero |
      | `reason` | only when `unavailable` | present only when `unavailable` |

      **Nothing is present-and-null anywhere**, which is the whole content of
      the rule. `0` and absent are the two values `count` can take, and they
      mean *the checks examined this specification and found nothing* and *no
      count exists for this round*. A third representation — present, `null`,
      or empty — would sit between them and be read as either.

- [ ] **Carry the five values into the ledger, which needs a change in
      `pr-review-loop.sh`.** The loop already forwards every unrecognised
      `key=value` line from a platform into its summary —
      `emit_prefixed_platform_output` re-emits all but five reserved keys — so
      `STRICT_SPEC_*` reaches the **comment** with no loop change at all. The
      **ledger** is a different path and does not:
      `reviewer_loop_history_build_entry` builds its entry from a fixed
      `jq -n` object over named locals, and platform key/value output is not
      among them. Nothing arbitrary is copied in.

      So the loop gains, at that function:

      - a `strict_spec` object in the entry, built from the five values;
      - the values themselves read from the local reviewer's `key=value` output
        by the same caller that already reads `RESULT` and `BLOCKING_COUNT`,
        passed in through globals set before the call — the convention
        `unresolved_thread_count`, `late_thread_count` and `current_run_id`
        already use there, and the reason that function takes eleven positional
        parameters and no more;
      - the object **absent** from the entry on rounds with no local reviewer
        at all, distinct from present-with-state-`not_applicable`. A repository
        that does not run `local-ai-reviewer` has no strict-check state, which
        is not the same fact as a round where the checks did not apply.

      **This is the one part of the item that changes `pr-review-loop.sh`**, and
      it is why AC-17, AC-17b and AC-17c cannot be satisfied inside
      `local-ai-reviewer.sh`: they are about what the *history* records, and the
      history is written a layer up. An earlier revision of this plan listed the
      ledger fields without naming that layer, which left the criteria resting
      on an unwritten implementation.

- [ ] **Render the findings separately.** The strict findings are emitted as
      their own `key=value` block — `STRICT_<n>_CHECK`, `STRICT_<n>_PATH`,
      `STRICT_<n>_LINE`, `STRICT_<n>_BODY` — parallel to `BLOCKING_<n>_*`.

### Frontend / UI

- [ ] In the reviewer-loop summary, one grouped section for strict findings,
      each line naming its check. The section appears only when the state is
      `applied` and the count is above zero — the spec's outcome table has the
      comment surface touched in exactly one row.

### Infrastructure / Configuration

- [ ] Document the five keys, the three states, the three `unavailable`
      reasons, the two-pass structure and what each pass may affect, the
      unknown-identifier classification, the closed identifier set, and the
      **command contract** — `LOCAL_AI_REVIEWER_MODE`, the required
      `mode: "strict_spec_checks"` response marker, and
      `LOCAL_CODEX_REVIEWER_STRICT_PROMPT` — in the `--help` block, in
      `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`,
      and in Protocol 93.
- [ ] Add the checklist to `markdown-lint.yml`'s `paths` filter — a
      checklist-only change must still be linted, the same gap #1654 found in
      its own CI wiring.
- [ ] `changelog.d/1650.added.strict-spec-contract-review.md`.

---

## Interaction with #1654

Both items add a document to the context bundle, `print_kv` lines to the same
block, and an evidence object. They do not conflict in behaviour and do conflict
in lines:

| | #1654 | This item |
| --- | --- | --- |
| Document | the review doctrine, all stages | the strict checks, spec stage only |
| Bundle fields | four, at the `jq -n` site | one, on a derived copy |
| Supplies when | always, to the one pass | only to the strict pass |
| Findings | none of its own | its own pass, its own block |

Whichever lands second re-reads the merged `print_kv` block rather than this
plan's copy of it. The `jq -n` object is no longer contended: #1654 edits it,
and this item derives a copy from its output and edits nothing there.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. The state is `applied` at the spec stage with a readable checklist and a
   pass that completes, `not_applicable` at every other stage, and `unavailable`
   when the stage cannot be resolved, the checklist cannot be read, or the pass
   does not complete — one case per row of the spec's six-row matrix, six cases.
1a. The **three** `unavailable` rows are distinguishable by their reason:
   `stage_unresolved` for row 1, `checklist_unreadable` for row 3,
   `strict_pass_failed` for row 4. Asserted as three different values, since the
   state alone leaves a reader unable to tell a defect in the pull request's
   shape from one in the repository's contents from one in the reviewer command
   — three owners. `STRICT_SPEC_REASON` is not emitted in rows 2, 5 and 6.
2. `STRICT_SPEC_COUNT` and `STRICT_SPEC_CHECKS` are **not emitted** in
   `not_applicable` and `unavailable`, and are present in `applied` — including
   `0` and an empty list when the checks found nothing. `STRICT_SPEC_REASON` is
   the mirror: emitted only in `unavailable`. Asserted on key presence, not on
   values.
3. A round recorded as `unavailable` is distinguishable from one recorded as
   `applied` with count `0`, by reading the ledger entry alone.
4. A strict-pass finding carrying a **known** `check` identifier is counted,
   appears in `STRICT_<n>_*`, does not appear in `BLOCKING_<n>_*`, and does not
   change `RESULT`.
5. A review at a non-spec stage produces **byte-identical** `key=value` output
   to the same review before this change, excluding the one key this item always
   adds, `STRICT_SPEC_STATE`. The four conditional keys must not appear at all
   at this stage, so their absence is asserted rather than excluded. No strict
   pass is dispatched, so the comparison covers the ordinary pass end to end.
5a. A **spec-stage** review whose strict pass returns no findings produces the
   same ordinary output as the same review with the checklist removed —
   verdict, blocking block, order and numbering identical. This is AC-3's own
   wording turned into a test, and the two-pass structure is what makes it
   assertable at all: the second run is literally the review with the checks
   disabled.
6. A strict-pass finding carrying an **unknown** `check` identifier is reported
   with `STRICT_<n>_CHECK=unknown`, excluded from `STRICT_SPEC_COUNT` and
   `STRICT_SPEC_CHECKS`, counted in `STRICT_SPEC_UNKNOWN_COUNT`, and does
   **not** become blocking. Asserted in both directions: it must not silently
   vanish, and it must not add a blocker the ordinary review never raised.
7. A strict-pass finding carrying `check` with a non-string value — a number,
   an object, `null` — and one carrying no `check` at all are counted as
   unknown, and the parser **does not abort**: `ascii_downcase` raises on a
   non-string, so the type guard has to run first. Asserted on all four shapes,
   since a program that errors here loses the entire strict pass.
7a. Four malformed strict responses are `strict_pass_failed` refusals, **not**
   counts: `{}` with no findings key at all, `{"findings": null}`, an
   **object** value, and a **string** value. Asserted against
   `{"findings": []}`, which must be `applied` with count `0` — the two inputs
   differ by four characters and are the two sides of silence versus zero. The
   object case is the quietest failure: without a type guard its property values
   are walked as findings and a malformed response is recorded as a completed
   run.
7b. A strict response **without** `mode: "strict_spec_checks"` is
   `strict_pass_failed`, run in two shapes: a response missing the field, and a
   complete ordinary review — `result` plus findings carrying `severity` and no
   `check` — which is what a custom `LOCAL_AI_REVIEWER_COMMAND` that ignores
   `LOCAL_AI_REVIEWER_MODE` returns. The second must **not** be `applied` with a
   large `unknown_count`.
8. A mixed review — two blocking findings from the ordinary pass and three from
   the strict pass — reports `BLOCKING_COUNT` 2, `STRICT_SPEC_COUNT` 3, and
   `RESULT=needs_fixes` driven by the ordinary two.
8a. The strict response's own verdict field is **ignored**. The same review is
   run with the strict pass returning `result: "needs_fixes"` and then
   `result: "clean"`, with the ordinary verdict held fixed in each: the emitted
   `RESULT` is identical across both, and equals the ordinary pass's.
9. A review whose ordinary pass is clean and whose strict pass returns three
   findings reports `RESULT=clean`, `BLOCKING_COUNT` 0 and `STRICT_SPEC_COUNT`
   3. This is the spec's central claim, and with two passes it is the direct
   consequence of never merging the two arrays.
9a. **The strict pass fails in five shapes** — non-zero exit, timeout, empty
   response, unparseable output, and an ordinary pass that consumed the whole
   `--timeout` so the checks were never attempted. Each is a separate run. In
   **all five** the state is `unavailable` with reason `strict_pass_failed`, and
   the ordinary verdict, blocking block and numbering are identical to the same
   review with no strict pass attempted. The fifth is the one AC-16d classifies:
   it is not distinguished from the other four, because *the checks produced no
   result* is the whole of what a reader needs.
9b. **The strict pass is dispatched exactly where the matrix says**, and the
   state is not the test — rows 1 to 3 decide dispatch, and the state is
   decided afterwards by what the pass returns, which is why row 4 is
   `unavailable` and dispatched. Asserted by counting invocations of `LOCAL_AI_REVIEWER_COMMAND`, which is 1
   in rows 1, 2 and 3 and **2** in rows 4, 5 and 6. Row 4 counts two: a pass
   that fails is a pass that was called, and the count measures dispatch rather
   than success — a row 4 asserting one invocation would be satisfied by an
   implementation that never dispatched at all, which is the opposite defect.
   A second call on a
   `not_applicable` review would double the cost of every plan and
   implementation review, which is the failure most likely to go unnoticed
   because nothing about the output would show it.
9c. The round is **bounded by `--timeout` in total**, not by twice it. This is
   scenario 9a's timeout and exhausted-budget shapes measured rather than
   classified: with `--timeout` set low enough to time, the elapsed round does
   not exceed it in either. Asserted on **elapsed time** against the single
   bound — an unbounded pass fails no other scenario here, because every other
   stub returns promptly, and 9a would pass on state alone.
9d. **No second timeout setting exists.** Asserted by absence: no environment
   variable or flag sets the strict pass's budget, and `--timeout` is the only
   thing that changes either pass's bound. The scenario greps the implementation
   and the `--help` block for a second name, since a knob nobody sets is
   invisible to every behavioural test.
10. `STRICT_SPEC_CHECKS` names the **distinct** checks that fired, not one entry
    per finding. Exercised with three findings drawn from a pair of checks: the
    key reports that pair, not three identifiers.
11. The **ordinary** bundle is byte-identical to the one built before this
    change, at every stage including `spec` — the `jq -n` site is not touched
    and the file is not rewritten. The **strict** bundle is that file plus
    exactly one key, `strict_spec_checks`, compared by `keys`.
11a. `LOCAL_AI_REVIEWER_MODE` is `ordinary` on the first call and `strict` on
    the second, asserted from a recording stub. The preset selects its prompt on
    it, and `LOCAL_CODEX_REVIEWER_PROMPT` overrides only the ordinary prompt
    while `LOCAL_CODEX_REVIEWER_STRICT_PROMPT` overrides only the strict one —
    asserted with each set alone.
12. The `strict_spec` object is present on **every** round that ran the local
    reviewer, at any stage, and mirrors the output by the table above: `state`
    always present; `count`, `checks`, `unknown_count` and `reason` **absent** —
    not null — on the rounds where their keys are not emitted. On a round with
    no local reviewer at all the object itself is absent, which is not the same
    fact as `not_applicable`. Asserted on both surfaces: the reviewer's output
    in `test-local-ai-reviewer.sh`, and the ledger entry in
    `test-pr-review-loop.sh`, since the two are written by different scripts and
    only the first is covered by the reviewer's own suite. Asserted with `has()` rather than by
    comparing values, since a present-null field and an absent one compare equal
    in the reading that matters here and not in `jq`.
13. The checklist's identifiers are read from the document: adding a ninth
    section to a fixture checklist makes a strict-pass finding carrying that
    ninth identifier counted rather than unknown, with no change to the parser
    or the tests.
13a. A checklist with a level-3 heading the identifier pattern does **not**
    match — `### Ambiguous Phrase` — yields `unavailable` with
    `checklist_unreadable`, and **not** a run over the seven that did match.
    The assertion is on both halves: the state, and `STRICT_SPEC_COUNT` not
    emitted at all.
13b. A checklist declaring the same identifier twice yields the same refusal.
    Left unchecked it would double one check's incidence and hide another's.
13c. A checklist with no level-3 headings at all, and an empty file, yield the
    same refusal. Neither is a checklist. **Both must reach the refusal**: this
    is the input on which `grep -c` exits 1, so an implementation that reads the
    count bare does not fail this scenario by reporting the wrong state — it
    fails it by producing no output at all, which is what the assertion has to
    be written against.
13d. The extraction is asserted directly, not only through its consequences:
    the eight shipped identifiers are extracted from the shipped checklist and
    compared to the spec's list as a set.
14. **The checks fire on planted violations.** Twelve fixture specifications:
    **nine** positives and **three** negative controls.

    The positives are one per check, each containing exactly one planted
    instance of that check's shape — plus a **ninth for `gate_matrix`**, because
    that check has two positive criteria and they are different documents: AC-6
    is a gate with a reachable combination unmentioned, and **AC-6b** is a gate
    that short-circuits and does **not** state its evaluation order. The second
    is the harder and more common case, since its unmentioned combinations are
    unreachable *if* the order held and indistinguishable from forgotten ones
    when the order is unstated — which is exactly the finding AC-6b requires and
    a fixture built for AC-6 does not produce.

    The negative controls are one per acceptance criterion that requires *no*
    finding: a gate enumerating every reachable combination (AC-7); a gate that
    short-circuits and **states its evaluation order** (AC-6a); and an unsettled
    phrase appearing only in a rationale (AC-13).

    AC-6a and AC-6b are the same document but for one sentence, and the pair is
    what makes `gate_matrix` falsifiable: stating the order must silence the
    check, omitting it must not.

    The reviewer is run against each with the checklist supplied, and the check
    that fired is recorded.
15. The same twelve fixtures with the checklist **absent**: the state is
    `unavailable` and no strict finding is produced. This is what separates *the
    reviewer found the violation because the checklist told it to look* from
    *the reviewer would have found it anyway* — without it, scenario 14 proves
    only that the reviewer is capable, not that this feature caused anything.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenario 12's
  ledger half, beside the existing `reviewer_loop_history_build_entry` cases at
  lines 2932 onward, which already set globals directly and assert on the
  built entry. Three cases: the five values present in `strict_spec` on an
  `applied` round; the four conditional fields absent on a `not_applicable`
  round; and the `strict_spec` object itself absent when no local reviewer ran.
- `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — scenarios 1
  through 13, and scenario 12's reviewer-output half. The parser scenarios run both real `jq` programs with crafted
  reviewer output, not stubs, and the dispatch scenarios use a recording stub
  for `LOCAL_AI_REVIEWER_COMMAND` so invocation counts can be asserted.
- The **smoke runbook** — scenarios 14 and 15, which need a real model.

**Scenarios 14 and 15 are demonstrated in the pull request rather than asserted
in CI, and that is not an exemption from the proof requirement.** Every one of
the eight checks gets its two demonstrated runs — proofs P10 through P17 — with
the fixture path, the planted line and both outcomes recorded, which is what
`REVIEW.md` requires. What they are not is a build gate.

The reason is that whether a model notices a planted contradiction is not
deterministic. A suite failing the build on a missed detection would be red for
reasons no implementer could fix, and the pressure would be to delete the
assertion rather than to improve the check. What *is* deterministic — that the
checklist reaches the strict pass at the spec stage, that the two passes never
merge, that the counts are reported — is scenarios 1 through 13, and those are
automated.

**A check that cannot demonstrate its pair does not ship.** `REVIEW.md` requires
both runs for every new check, and an undemonstrated one blocks readiness — the
proof not being a CI gate says where it is asserted, not whether it is required.
The repair is to sharpen the check's question in the checklist until it detects
its own planted violation, and that happens at step 5a, before merge.

The reason to hold the line rather than ship the check with a note: a check that
detects nothing produces a permanent zero in #1657's data, and a zero reads as
*this problem does not occur* rather than *this check does not work*. Shipping
it undemonstrated would put an unfalsifiable row into the measurement this
entire item exists to make possible.

**Smoke test runbook**:
`docs/testing/workflow/1650-strict-spec-contract-review.smoke-test.md`

**Regression suite**: the harness named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Fixture specifications | **Twelve** short specification documents: nine positives — one per check with a single planted instance of that check's shape, plus a second `gate_matrix` positive because that check has two positive criteria (AC-6, a reachable combination unmentioned; AC-6b, a short-circuit gate that does not state its evaluation order); and three negatives — a gate enumerating every reachable combination (AC-7), a gate that short-circuits and states its evaluation order (AC-6a), and an unsettled phrase confined to a rationale (AC-13) | `scripts/development-workflow/tests/fixtures/strict-spec-specs/` |
| Reviewer outputs | Two sets. **Ordinary pass**: clean; two blocking findings; one that consumes the whole `--timeout`. **Strict pass**: no findings; three findings from two checks; an unknown identifier; a non-string `check`; no `check` at all; one carrying its own `result`; one with no `mode`; a complete ordinary review; and **five** failure shapes — non-zero exit, timeout, empty, unparseable, and never attempted for want of budget | inline in `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |
| Checklist fixtures | A well-formed eight-section checklist; a nine-section one for scenario 13; and an unreadable one | `scripts/development-workflow/tests/fixtures/strict-spec-checks/` |
| Bundle field list | The field names present before this change, enumerated from the merged `jq -n` object at implementation time | inline in the same suite |

---

## Documentation Updates

- `docs/workflow/development-workflow/strict-spec-checks.md` — the checklist.
- The integration document and Protocol 93 — the keys, states and identifier
  set.
- The `--help` block of `local-ai-reviewer.sh`.
- `.github/workflows/markdown-lint.yml` — the checklist in `paths`.
- `changelog.d/1650.added.strict-spec-contract-review.md` — `added`: a class of
  finding that did not exist, and nothing changes for a repository whose
  reviewer emits none.

---

## Cross-Cutting Checklist Classification

**Classification**: `Not applicable`. Protocol 02's three signals are adding or
renaming a checklist category in `REVIEW.md` or a planning document; imposing an
acceptance criterion on every plan; and adding a conditional guidance block to a
planning or implementation protocol. This item adds a **new document read by one
script**, changes no `REVIEW.md` section, and requires nothing of any future
plan.

The contrast with #1653 is the useful one: that item added a section to
`REVIEW.md`, which is the first signal exactly. A checklist consumed only by
`local-ai-reviewer.sh` is not a review-contract category, and no agent or skill
file enumerates it.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Strict findings turn every spec review red | **High** if the two responses are merged — an unsorted finding is blocking | **High** — the feature is switched off within a day, and the counts it exists to produce are never gathered | The two arrays are never joined: blocking comes from the ordinary pass, `STRICT_<n>_*` from the strict one. Scenarios 4 and 9; proof **P1** appends one to the other |
| The verdict is influenced by checks the same model just read | **High** in any single-invocation design — and undetectable from the response | **High** — AC-3 fails on the review the feature exists to produce: counts say non-blocking, pull request red | Two invocations. The pass that decides the verdict never receives the checklist, so there is nothing to influence it and no promise to audit. Scenarios 5a and 8a; proof **P4** |
| The strict pass fails and takes the review with it | Med — any invocation can fail | **High** — an unrelated defect in the reviewer command blocks pull requests that had no findings at all | State `unavailable` with reason `strict_pass_failed`, ordinary output untouched. Scenario 9a on five failure shapes; proof **P9** |
| The strict pass hangs and the round never ends | Med — a reviewer command can hang | **High** — the cost stops being bounded, and a feature that produces measurements starts costing arbitrary wall-clock time | The remaining `--timeout` through the existing `run_with_timeout` wrapper: one budget, shared. Scenario 9c asserts on elapsed time, since no other scenario would notice |
| A second timeout setting is added for convenience | Med — it is the obvious way to make the strict pass configurable | Med — two values disagree about a bound whose purpose is that a round cannot outlast it, and the checks can be configured to outlive the review that dispatched them | AC-16c forbids it and scenario 9d asserts its absence by grep, since a knob nobody sets is invisible to behavioural tests |
| The extra invocation runs where it should not | Med | Med — every plan and implementation review costs twice as much, and nothing in the output shows it | The state test gates the dispatch, and the invocation count is asserted per matrix row. Scenario 9b; proof **P8** |
| Unknown identifiers vanish from the count | Med | Med — a renamed check or a drifted prompt loses its findings silently, and #1657's rate looks better than the reviewer's behaviour | Reported with `CHECK=unknown` and counted in `STRICT_SPEC_UNKNOWN_COUNT`, never blocking and never discarded. Scenarios 6 and 7; proof **P2** |
| A strict finding is forwarded as a blocker by the loop | Med | **High** — `BLOCKING_<n>_*` is what the loop reads; counts elsewhere would not save it | Strict findings are emitted in their own `STRICT_<n>_*` block and never in the blocking one. Scenario 4 and proof **P3** |
| The strict pass changes ordinary output | Med | Med — every review's output shifts for a feature that should be invisible to them | Byte-identical output required for an all-ordinary review. Scenario 5 and proof **P4** |
| `unavailable` is reported without its cause | Med | Med — a reader cannot tell a pull request whose stage could not be resolved from a repository missing the checklist or a reviewer command that failed, and the three have different owners | `STRICT_SPEC_REASON` carries one of three values. Scenario 1a and proof **P7** |
| `0` is written where the checks did not run | **High** — an empty numeric field invites a default | **High** — unexamined rounds enter #1657's denominator and the rate is wrong in the flattering direction | Count and identifiers are empty outside `applied`. Scenarios 2 and 3; proof **P5** |
| The identifier set is duplicated in the parser | Med | Med — a ninth check works in the document and not in the code, or the reverse | `$known_checks` is passed from the checklist. Scenario 13 and proof **P6** |
| A malformed or absent `findings` key is counted instead of refused | **High** — `// []` is the idiomatic default and reads as harmless | **High** — an empty response is recorded as `applied` with count `0`, which says the checks ran and found nothing: silence entering #1657's data as zero, which is the confusion the whole feature exists to prevent | The key must be explicitly present via `has()`, and its value must be an array before anything iterates. Four refusal shapes asserted against `{"findings": []}`. Scenario 7a |
| The extractor silently drops a malformed section | Med — one mistyped heading | **High** — the reviewer is handed seven checks, reports against seven, and the count reads as a completed run: the exact failure this feature exists to detect, inside the mechanism meant to detect it | Heading count compared against extracted count; any mismatch refuses the document as `checklist_unreadable`. Scenarios 13a to 13c |
| `grep -c` exits 1 under `set -e` and kills the review | Med — it is the idiomatic way to write the count | **High** — the checklist-with-no-headings case produces no review at all rather than a refusal, and the failure appears on the one input the refusal tests exist for | Status read explicitly, exit 1 separated from exit greater than 1. Scenario 13c asserts the refusal is reached, not merely that its state is right |

---

## Code Samples

The strict pass's parser — a **separate** program, run over the strict
response only, and the reason the ordinary program needs no edit at all:

```text
# `$known_checks` comes from the checklist via --argjson: one definition of the
# closed set, and a ninth check needs no parser edit.
def ident:
  ((.check? // null) | if type == "string" then ascii_downcase else null end);

def known($c): $c != null and ($known_checks | index($c) != null);

if (.mode? // null) != "strict_spec_checks" then { malformed: true }
else
  (if   has("findings") then .findings
   elif has("comments") then .comments
   elif has("issues")   then .issues
   else null end) as $f
  | if ($f | type) != "array" then { malformed: true }
    else
      ($f | map(select(known(ident))))       as $named
    | ($f | map(select(known(ident) | not))) as $unnamed
    | { malformed:     false,
        count:         ($named   | length),
        checks:        ($named   | map(ident) | unique | join(",")),
        unknown_count: ($unnamed | length) }
    end
end
```

Six details are not stylistic, and the first three are the same principle three
times.

**The response must claim the mode.** A configurable
`LOCAL_AI_REVIEWER_COMMAND` that ignores `LOCAL_AI_REVIEWER_MODE` answers with
an ordinary review, whose findings carry `severity` and no `check` — every one
counted `unknown`, the pass reporting `applied` with a large `unknown_count`,
and an ordinary review recorded as a completed run of the strict checks. The
marker is the positive acknowledgement that makes an unconfigured command
degrade to "the checks did not run".

**The findings key must be explicitly present**, which is why the program tests
`has()` rather than writing `.findings // .comments // .issues // []`. That
`//` chain reads as a convenience and is a silent failure: an empty response —
`{}`, a reviewer that printed nothing usable, a command that produced no JSON at
all — defaults to `[]` and is recorded as `applied` with count `0`, which says
*the checks ran and found nothing*. It is the silence-versus-zero confusion the
spec is built around, produced by the code that is supposed to report the
distinction. An absent key is `strict_pass_failed`; an explicitly empty array is
`applied` with `0`.

**The array type is checked before anything iterates it**, and `malformed` is a
refusal rather than a count. Without the guard a `findings` value that is an
**object** is walked as its property values: each becomes a "finding", none
carries a `check`, and the pass reports `applied` with a large `unknown_count`.
A **string** value is worse only in being louder: `.[]` raises and the pass dies
where it should refuse. Both are the same refusal, and so is `null`.

The other three: the identifier is passed to `known` as an
**argument** rather than piped, because inside `index(...)` the `.` is the
array, not the finding — `index(.check)` raises *Cannot index array with
string*. The `if type == "string"` guard runs before `ascii_downcase`, which
errors on a number or an object, and without it the whole strict pass aborts
instead of classifying one finding as unknown. And the program reads **no**
verdict field: `result` may be present in the response and is never referenced,
which is what makes "the strict pass cannot block" a property of the code rather
than of the prompt.

`$named` and `$unnamed` partition the strict pass's own findings and nothing
else. The ordinary pass's array is never in scope here, and this program's
output never reaches `BLOCKING_<n>_*`.

Verified as a standalone program against nine inputs. Refused for the mode: a
response with no `mode`, and a full ordinary review (`result` plus a
`severity`-carrying finding) — the shape a custom command returns if it ignores
the mode variable. Then, with the mode present, counted: a six-finding array — two known identifiers with one repeated, one undefined identifier, one
numeric, one with no `check` at all — yielding `count` 3, `checks`
`ac_consistency,gate_matrix` and `unknown_count` 3; `{"findings": []}` yielding
`count` 0; and a response using `comments` rather than `findings`, to confirm
the alternative keys still work. Refused: `{}`, `{"findings": null}`, an
**object** value and a **string** one.

The pair worth reading together is `{}` and `{"findings": []}`. They differ by
four characters and they are the two sides of the distinction this feature
exists to preserve: one is a pass that produced nothing, the other is a pass
that examined a specification and found nothing wrong with it.

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The **seventeen** proofs
fall into three groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Blocking | **5** | P1, P3, P4, P8, P9 | a non-blocking pass that blocks, that costs, or that takes the review with it |
| Measurement | **4** | P2, P5, P6, P7 | a count that admits or discards what it should not |
| Detection | **8** | P10-P17 | a check that does not find the violation it exists to find |

**The detection group is one proof per check**, and it covers what the first two
groups cannot: P1 through P9 plant defects in the dispatch, the merge and the
reporting — the machinery *around* the checks — and would every one of them pass
with eight checks that detect nothing. `REVIEW.md` asks for each new check to be
demonstrated against a concrete violation, so each of the eight gets its pair.

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Append the strict pass's findings to the ordinary array before the blocking test | a scratch copy of the merge step | scenario 9 fails: a review whose ordinary pass was clean reports `needs_fixes`, because an unsorted finding is blocking — so every specification with eight checks applied turns red and the feature is switched off before it produces a single count; restoring the separate arrays passes |
| P2 | Drop unknown-identifier findings from the strict pass silently, instead of counting them | a scratch copy of the strict `jq` program | scenario 6 fails in its first direction: `STRICT_SPEC_UNKNOWN_COUNT` is absent while findings were discarded, so a reviewer emitting an undefined identifier — a prompt drift, a renamed check — loses its findings with nothing in the output to show it; restoring the unknown class passes |
| P3 | Emit strict findings in the `BLOCKING_<n>_*` block as well as their own | a scratch copy of the merge step | scenario 4 fails: the loop reads `BLOCKING_<n>_*` and forwards each as a blocker regardless of `BLOCKING_COUNT`, so the non-blocking guarantee holds in the reviewer and breaks one layer up; restoring the separate block passes |
| P4 | Read the strict response's `result` field into the emitted verdict | a scratch copy of the merge step | scenario 8a fails: the two runs that differ only in the strict pass's verdict emit different `RESULT` values, so the pass that cannot block does block; restoring the ignored field passes |
| P8 | Dispatch the strict pass unconditionally, without testing the state | a scratch copy of the dispatch step | scenario 9b fails: the invocation count is 2 on a `not_applicable` review, doubling the cost of every plan and implementation review while the output looks correct; restoring the state test passes |
| P9 | Let a failed strict pass propagate — return its exit status, or emit no ordinary output | same scratch copy | scenario 9a fails on all five failure shapes: a reviewer command that crashes takes the ordinary review with it, so an unrelated defect blocks a pull request that had no findings; restoring the `strict_pass_failed` state passes |
| P5 | Emit `STRICT_SPEC_COUNT=0` and an empty `STRICT_SPEC_CHECKS` for `unavailable` and `not_applicable`, where both keys must not be emitted at all | a scratch copy of the print block | scenarios 2 and 3 fail: a round the checks never examined is indistinguishable from one where they ran and found nothing, so #1657's rate counts unexamined specifications as clean — an error in the flattering direction, which is the one nobody questions. Scenario 12 fails with it, since the evidence object mirrors the output. Restoring the two keys to unemitted passes |
| P7 | Report `unavailable` without a reason, or with one constant value for all three of its rows | a scratch copy of the print block | scenario 1a fails: the three `unavailable` rows — `stage_unresolved`, `checklist_unreadable`, `strict_pass_failed` — become indistinguishable, so a reader sees one state with three possible owners and no way to tell which to go and see. Scenario 9a fails too, since it asserts the reason on the failed-pass row. Every other scenario passes, because none reads the reason; restoring the three values passes |
| P10-P17 | For each check in turn, remove its planted violation from that check's positive fixture — one proof per check, in the spec's order: `ac_consistency`, `ac_testability`, `gate_matrix`, `opt_out_source`, `trigger_semantics`, `example_contradiction`, `parser_surface`, `ambiguous_phrase`. `gate_matrix`'s proof runs on **both** its positives, AC-6's and AC-6b's, since removing the violation differs between them: enumerating the missing combination in the first, stating the evaluation order in the second | the nine positive fixture specifications | the check fires on the fixture carrying its violation and does **not** fire on the same fixture with that one violation removed. Both runs are recorded with the fixture path, the line the violation sat on, and the identifier set the round reported. The pair is the demonstration `REVIEW.md` asks for: without the second run a check that fires on everything looks identical to one that works |
| P6 | Hard-code the eight identifiers in the strict pass's parser | a scratch copy of the strict `jq` program | scenario 13 fails: a ninth check added to the checklist is recognised by no code, so its findings are counted in `STRICT_SPEC_UNKNOWN_COUNT` and named by no identifier in `STRICT_SPEC_CHECKS` — the check exists in the document and is invisible in the measurement, which is the failure that matters once #1657 reads these counts. It does **not** block, because a strict-pass finding never can; the eight shipped checks still pass, which is why the scenario adds a ninth; restoring `$known_checks` passes |

P1 is the proof to read first: with the two arrays merged the feature does not
merely fail, it makes every specification review red, and the resulting pressure
is to disable the checks rather than to fix the merge.

---

## Implementation Order

0. **Hard stop**: confirm #1653 is implemented and merged and that
   `review_stage` carries `spec`. Both spec amendments are merged and are hard
   dependencies: **#1677** (matrix row 4, the `strict_pass_failed` cause,
   AC-16a) and **#1678** (AC-16a's wording, AC-16b's shared bound, AC-16c's
   single configuration source, AC-16d's classification). Steps 2 and 4 build a
   state and a bound the unamended spec does not contain.

   Re-read the merged `print_kv` block, which #1654 may also have changed. The
   `jq -n` bundle object needs no re-reading for merge purposes — this plan
   adds nothing there — but its field list is what scenario 11 enumerates at
   implementation time.
   **Each scenario is verified at the step that first makes its assertion
   observable**, which is not always the step that implements the behaviour it
   describes: the extraction's three refusals are built in step 1 and only
   become assertable in step 4, when the state and reason are emitted.

1. Add the checklist document with its eight sections and identifiers, and the
   extraction with its three refusal tests. **Verify**: scenario 13d — the
   identifiers extracted from the shipped document match the spec's list as a
   set, compared by extraction and not by reading. This is the step's own
   output, so it needs nothing downstream.
2. Add the strict pass: the state test that decides whether to dispatch, the
   derived bundle, `LOCAL_AI_REVIEWER_MODE`, the preset's second prompt and its
   override variable, the second invocation bounded by the remaining
   `--timeout`, its own
   `jq` program with the mode guard, **`$known_checks` passed to it from step
   1's extraction** via `--argjson`, and the merge that keeps the two responses
   apart. **Verify**: scenarios 4, 5, 5a, 6, 7, 7a, 7b, 8, 8a, 9, 9a, 9b, 9c, 9d, 11,
   11a and 13 — these
   first, because everything else is reporting.

   The identifier set is wired here rather than later because the parser cannot
   classify anything without it: every scenario in this step's list that
   distinguishes a known identifier from an unknown one depends on it, and
   deferring it would mean hard-coding the eight identifiers temporarily —
   exactly what proof P6 plants as a defect.
3. Add the supply condition, carrying the cause when the state is
   `unavailable`. **Verify**: scenarios 1 and 1a.
4. Add the five `print_kv` keys, the `STRICT_<n>_*` block and the evidence
   object in `local-ai-reviewer.sh`, **and** the `strict_spec` entry object in
   `reviewer_loop_history_build_entry` with the globals its caller sets.
   **Verify**: scenarios 1a, 2, 3, 10, 12, 13a, 13b and
   13c — the last three are step 1's refusals, assertable now that the state and
   reason are emitted.
5. Add the summary rendering. **Verify**: runbook Step 7.
5a. Write the twelve fixture specifications — nine positives, three negatives —
   and run the reviewer against each
   with the checklist supplied and again without it. **Verify**: scenarios 14
   and 15 — record which checks fired in each run, in the pull request. This is
   evidence, not a gate: a check firing in neither run is a finding about that
   check, and one worth having before the counts accumulate.
6. Update the `--help` block, the integration document, Protocol 93, the
   `paths` filter, and add the changelog fragment. **Verify**: runbook Step 9.
7. Produce the **seventeen** planted-violation proofs and record them in the PR
   with the command, file, line and both outcomes for each: P1-P9 against
   scratch copies of the dispatch, merge, parser and print steps, and P10-P17 as
   the detection pair for each of the eight checks, run from step 5a's fixtures.

---

## Rollback

Revert the implementation PR. It removes the checklist, the strict pass and its
dispatch, one bundle field, five `key=value` keys, the `STRICT_<n>_*` block, the
evidence object, the ledger fields, the summary section, the `paths` entry and
the documentation updates.

**The ordinary review needs no restoring, because it was never changed.** That
is the two-pass structure's second benefit after AC-3: the rollback surface is
the strict pass alone, and reverting cannot regress an ordinary review because
nothing in one was touched. Spec-stage reviews return to one invocation.
