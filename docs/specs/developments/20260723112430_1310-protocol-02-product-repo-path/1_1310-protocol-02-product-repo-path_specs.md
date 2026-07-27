# Portable Protocol 02 Parser Guidance — Spec

---

## Overview

Protocol 02 is distributed to repositories that do not necessarily contain the
template repository's historical development artifacts. Its parser-risk and
suppression guidance must remain usable in every supported repository mode
without directing plan authors to a missing local document. Template sync
validation must also distinguish valid distributed guidance from unavailable
hub-only material so a successful product-repository sync does not appear
incomplete.

## Use Cases

### Use Case 1: Plan author follows parser-risk guidance in a downstream repository

**Actor**: Plan author working in a repository that received Protocol 02 through
template sync

**Preconditions**:

- The repository uses a supported workflow repository mode
- Protocol 02 has been distributed to the repository
- The planned work is classified as parser-risk and includes suppression
  behavior

**Steps**:

1. The plan author reads the parser-risk and suppression guidance in Protocol 02
2. The plan author follows the acceptance intent and terminology available from
   the distributed workflow surface
3. The plan author completes the plan without needing a local historical
   development artifact that the repository was never expected to receive

**Postconditions**: The plan contains the required parser-risk and suppression
coverage without a broken or misleading document dependency.

**Information shown**:

- The required suppression topics and acceptance intent
- Any supplementary reading, clearly identified as required or optional

**Actions available**:

- Apply the guidance directly when it is available locally
- Follow an explicitly identified optional upstream reference without treating
  it as a required local file

**Considerations**:

- A product repository commonly lacks historical template or workflow-hub
  development folders
- The absence of optional upstream reading must not prevent plan authoring
- The behavioral intent of the existing parser-risk guidance must not be
  weakened while making it portable

### Use Case 2: Maintainer validates a template sync into a product repository

**Actor**: Maintainer running template synchronization and post-apply validation

**Preconditions**:

- Protocol 02 is selected for distribution to the product repository
- The product repository does not contain the template repository's historical
  development artifacts

**Steps**:

1. The maintainer applies the selected template update
2. Post-apply validation checks distributed documentation references
3. Validation evaluates Protocol 02 using the repository mode and the
   distribution contract
4. Validation completes without reporting a missing hub-only fixture as an
   unexplained broken product-repository path

**Postconditions**: The maintainer can distinguish a complete sync from a real
cross-reference defect.

**Information shown**:

- Whether all required distributed references are available
- A clear classification for any intentionally optional upstream material

**Actions available**:

- Accept the sync when every required distributed reference is valid
- Investigate a real missing required reference

**Considerations**:

- Validation must not hide genuine broken references
- Repository-mode-specific exceptions, if any remain, must be explicit and
  understandable to both humans and agents

## Business Rules

- Normative guidance in an always-distributed workflow protocol must be
  understandable and actionable in every repository mode that receives that
  protocol.
- Required acceptance intent must not depend solely on a local historical
  development artifact that is absent by design from a receiving repository.
- Supplementary hub or template reading may remain available only when it is
  clearly optional and its absence does not block plan authoring or successful
  sync validation.
- Template sync validation must continue to report genuinely missing required
  references; portability must not be implemented by broadly suppressing
  cross-reference failures.
- The existing parser-risk classification, edge-case enumeration, unit-test
  expectations, and suppression topics remain behaviorally unchanged by this
  portability correction.
- The shipped implementation must be represented in the template changelog so
  downstream maintainers can identify the version that contains the correction.

## Operational Visibility

- **Plan-author evidence**: Protocol 02 communicates the required parser-risk
  and suppression intent without an unexplained dead path.
- **Sync evidence**: Post-apply reference validation reports no broken
  product-repository path for this guidance.
- **Release evidence**: The template changelog identifies the portability
  correction for downstream consumers.

## Acceptance Criteria

- [ ] AC1: Given Protocol 02 is present in a supported product repository that
      lacks the template's historical development folders, a plan author can
      obtain all required parser-risk and suppression acceptance intent from
      available distributed guidance.
- [ ] AC2: Given Protocol 02 includes supplementary upstream reading, the
      material is clearly identified as optional and its local absence does not
      block or confuse the plan author.
- [ ] AC3: Given a product repository sync includes the corrected Protocol 02,
      post-apply cross-reference validation does not report the historical
      template fixture path as a broken required product-repository reference.
- [ ] AC4: Given any other required distributed documentation reference is
      genuinely missing, cross-reference validation continues to report that
      defect rather than suppressing it under a broad hub-only exception.
- [ ] AC5: Given a plan is parser-risk and supports suppression directives, the
      corrected guidance still requires the same directive recognition,
      placement, multiple-suppression, edge-case, and automated-test coverage
      as before this change.
- [ ] AC6: Given the correction is released for downstream synchronization, the
      template changelog states that Protocol 02 no longer relies on an
      unavailable product-repository fixture path.
- [ ] AC7: Given the repository mode and local availability combinations in the
      consistency matrix, every row produces the documented outcome without an
      unexplained missing-path failure.

## Workflow Consistency Matrix

| Repository mode | Historical fixture available locally | Required outcome | Next action | Mirror surfaces |
| --- | --- | --- | --- | --- |
| Template or workflow hub | Yes | Parser-risk guidance is usable and required references validate | Continue plan authoring or sync validation | Protocol 02; documentation reference validation |
| Template or workflow hub | No | Required acceptance intent remains available; optional upstream material is identified as optional | Continue without treating absent optional material as a defect | Protocol 02; documentation reference validation |
| Product repository | No | Parser-risk guidance is fully usable from distributed content and validation reports no broken hub-fixture dependency | Continue plan authoring and accept the reference check | Protocol 02; sync selection contract; post-apply reference validation |
| Single repository | No | Parser-risk guidance is usable without assuming a separate hub history exists | Continue plan authoring; report only genuinely missing required references | Protocol 02; documentation reference validation |

## Brief Objective List

1. Remove or clearly classify Protocol 02's dependency on a historical
   hub/template fixture that product repositories do not receive.
2. Keep post-apply sync reference validation clean for this intentional
   distribution shape without hiding genuine broken references.
3. Preserve the existing parser-risk and suppression acceptance intent.
4. Document the downstream-facing correction in the next template changelog.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Make the Protocol 02 guidance portable across receiving repository modes | Use Case 1; Business Rules; Workflow Consistency Matrix | AC1, AC2, AC7 |
| 2. Prevent the known false broken-reference result while retaining real validation | Use Case 2; Business Rules; Operational Visibility | AC3, AC4, AC7 |
| 3. Preserve parser-risk and suppression semantics | Business Rules | AC5 |
| 4. Publish a downstream-visible changelog note | Business Rules; Operational Visibility | AC6 |

## Deferral Notes

No brief objective is deferred.

## Out of Scope (MVP)

- Changing the product behavior expected from parser-risk implementations
- Redesigning unrelated Protocol 02 planning requirements
- Distributing all historical template development artifacts to every product
  repository
- Broadly disabling documentation cross-reference validation
- Repairing unrelated downstream sync findings
