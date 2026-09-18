# 13.10 Cross-stage authority-reconciliation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.


## `BuildAuthorityRequirementLedgerAction`

- **Input:** exact stage, closed schema/policy registries, accepted upstream authorities, and
  current obligation sources
- **Output:** complete `AuthorityRequirementLedger` candidate
- **Responsibility:** Enumerate every contract-required datum/decision exactly once with
  structural identity, earliest owner, required slot, reconciliation policy, and downstream
  obligations; add no domain interpretation.

## `ValidateAuthorityRequirementLedgerAction`

- **Input:** ledger candidate and the same closed requiredness/ownership registries
- **Output:** requirement-ledger evidence
- **Responsibility:** Prove exhaustive required-slot coverage, unique structural IDs, current
  input-authority bindings, registered ownership/policy, and no model/caller-defined or omitted
  requirement.

## `BuildAuthorityCandidateSetAction`

- **Input:** one validated requirement and the exact authorities/read-only evidence permitted by
  its reconciliation policy
- **Output:** closed candidate-set candidate
- **Responsibility:** Select and type every potentially supporting current authority under the
  registered policy; do not rank, approximate, choose a winner, or invoke semantic
  interpretation.

## `ValidateAuthorityCandidateSetAction`

- **Input:** candidate set, requirement, current authority registries, and policy
- **Output:** candidate-set evidence
- **Responsibility:** Prove total permitted-source accounting, identity/currentness, no extra or
  missing candidate, and exact deterministic equivalence partitions where the policy defines
  them.

## `BuildAuthoritySemanticAssessmentRequestAction`

- **Input:** one validated candidate set whose policy permits semantic assessment and for which
  deterministic comparison cannot decide support/equivalence
- **Output:** bounded input for the YAML-declared semantic-review operation
- **Responsibility:** Expose only the requirement, supplied candidates, citations, and closed
  allowed assessment labels; create no authority or resolution.

## `BuildAuthorityReconciliationOutcomeAction`

- **Input:** one requirement, validated candidate set, deterministic comparison evidence,
  optional validated model-assisted assessment, current exception/clarification authorities, and
  ownership registry
- **Output:** one closed `AuthorityReconciliationOutcome` candidate
- **Responsibility:** Produce exactly one resolution, clarification, upstream-rework, or
  administrative-block variant; never default, approximate, use model memory, or repair missing
  authority into content.

## `ValidateAuthorityReconciliationOutcomeAction`

- **Input:** outcome candidate and all bound requirement/candidate/authority/ownership evidence
- **Output:** reconciliation evidence
- **Responsibility:** Prove cardinality, currentness, allowed `not_applicable`/exception scope,
  earliest-owner routing, semantic-assessment labelling, and the absence of a success variant
  for a gap.

## `BuildAuthorityReconciliationLedgerAction`

- **Input:** validated requirement ledger and exactly one validated outcome per requirement
- **Output:** complete reconciliation-ledger projection
- **Responsibility:** Join outcomes to requirements in canonical structural order without
  dropping, merging, or locally reclassifying an entry.

## `ValidateAuthorityReconciliationLedgerAction`

- **Input:** reconciliation projection, requirement ledger, current stage/authorities, and
  closed stage-gate policy
- **Output:** complete-success evidence or exact ordered non-success entries
- **Responsibility:** Prove one-to-one exhaustive coverage; authorize stage continuation only
  when every entry is an allowed resolved variant, otherwise return every gap for typed routing.

## `RouteAuthorityReconciliationGapAction`

- **Input:** validated non-success entries, current workflow stage, clarification registry,
  descendant/approval state, implementation watermark, and ownership/rework registries
- **Output:** one closed clarification, upstream-rework, or administrative-block route plan
- **Responsibility:** Select the earliest owner by the locked dominance/order policy,
  deduplicate same-subject needs, include complete descendant/runtime/evidence invalidation when
  required, and never route to the detecting caller merely for convenience.

## `BuildAuthorityGapClarificationNeedAction`

- **Input:** one validated clarification route plan, its selected `clarification_required`
  outcome, structural requirement, and compiler-locked question/answer-schema descriptor
- **Output:** engine-built `ClarificationNeedProposal` candidate plus
  `authority_reconciliation_gap` origin
- **Responsibility:** Build the bounded question/why/answer schema, subject descriptor, and
  exact requirement/evidence origin from registered fields and current evidence; accept no
  model/caller wording, owner, ID, path, resolution, or fallback.
- Apply [shared clarification preparation](../12-model-boundary.md#127-workflow-defined-model-operations)
  through existing question/reason fields: identify the requirement, relevant facts/evidence
  and exact permitted decision. Model review detail remains evidence, not an automatic
  question. Reuse registered descriptions; add no summary call or answer-grouping authority.


These actions own the shared contract. Domain actions only produce registered requirements, candidates, and evidence. They may not create a parallel reconciliation outcome, clarification shortcut, or stage-specific success rule.

### Native source and principle review

`specification_support.Contract` specializes the existing collection, diagnostics,
atomic repair and persisted-evidence validation by native review purpose. Source
findings retain the business-evidence contract. Principle findings contain only
`decision`, `citations` and `detail`; permitted decisions are `compatible`,
`conflicting` and `uncertain`. Native policy assigns the Plan owner.

`initialize-specification-review` binds progress to the current authority projection.
`advance-specification-review` advances accepted source review to policy assessment
only after complete business content is supported; empty selected prose needs no
model call. Both assessments use the same declared request and repair loop. Only
completed review replaces the source authority inputs. No action selects a successor,
invokes another action, or changes a negative verdict to obtain admission.

The v2 canonical Specify state requires the assessment. Readback reconstructs the
business requirements and policy ledger, re-admits evidence against the exact registry
and selection, and compares the complete reconciled result. Missing, stale, foreign
or erased obligations reject. `reference-context.md` renders this canonical handoff;
it is never imported as policy authority.
