# 13.10 Cross-stage authority-reconciliation actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

These actions own the shared contract
([§12.8.1](../12-model-boundary.md), [§14.14](../14-orchestration.md#1414-authorityreconciliationorchestrator));
domain code ([`required_authority.zig`](../../../src/domain/required_authority.zig)) supplies
registered requirements, candidates and evidence only. No domain action may add a parallel
reconciliation outcome, clarification shortcut or stage-specific success rule. Turning gaps
into clarification needs is `build-required-authority-clarification-needs`
([13.5](13-05-artifacts-rendering-traceability.md)).

## `BuildSpecificationAuthorityRequirementsAction` (`build-specification-authority-requirements`)

- **Owner:** [`src/actions/authority/build_specification_authority_requirements.zig`](../../../src/actions/authority/build_specification_authority_requirements.zig)
- **Reads:** `relative_feature_directory`, `accounted_reference_reconciliation` (optional:
  `specification_generation_session`, `identified_specification_content`) · **Writes:**
  `required_authority_inputs` · **Side effect:** `none`
- **Does:** Project the source-readiness requirements for the feature's required subjects from
  the accounted reference reconciliation, detected at `spec`
  ([`specification_authority.zig`](../../../src/domain/specification_authority.zig)).
- **Rejects:** `InvalidRequiredAuthority` (outcome `blocked`).

## `BuildSourcePreservationRequirementsAction` (`build-source-preservation-requirements`)

- **Owner:** [`src/actions/authority/build_source_preservation_requirements.zig`](../../../src/actions/authority/build_source_preservation_requirements.zig)
- **Reads:** `relative_feature_directory`, `accounted_reference_reconciliation`,
  `citable_reference_inputs` (optional: `specification_generation_session`,
  `identified_specification_content`) · **Writes:**
  `required_authority_inputs` · **Side effect:** `none`
- **Does:** Project the optional source-preservation requirements from the reconciled records
  and captured sources
  ([ADR 0021](../../decisions/0021-optional-source-preservation-review.md);
  [`source_preservation.zig`](../../../src/domain/source_preservation.zig)).
- **Rejects:** `InvalidRequiredAuthority` (outcome `blocked`).

## `BuildRequiredAuthorityLedgerAction` (`build-required-authority-ledger`)

- **Owner:** [`src/actions/authority/build_required_authority_ledger.zig`](../../../src/actions/authority/build_required_authority_ledger.zig)
- **Reads:** `required_authority_inputs` · **Writes:** `required_authority_ledger` · **Side effect:** `none`
- **Does:** Re-derive the projection the inputs claim and require it to match, then build one
  requirement per seed in requirement-identity order with its registered policy; candidate or
  model order never decides order.
- **Rejects:** `InvalidRequiredAuthority` for an invalid feature, a projection mismatch, a
  repeated or invalid requirement, authority, evidence, exception, candidate or forced gap, or
  one naming an unknown requirement.

## `BuildRequiredAuthorityObservationsAction` (`build-required-authority-observations`)

- **Owner:** [`src/actions/authority/build_required_authority_observations.zig`](../../../src/actions/authority/build_required_authority_observations.zig)
- **Reads:** `required_authority_ledger` · **Writes:** `required_authority_observations` · **Side effect:** `none`
- **Does:** Record, natively, each requirement's inspected input authorities and the IDs of its
  bound evidence.
- **Rejects:** none beyond allocation failure.

## `ParseRequiredAuthorityObservationsAction` (`parse-required-authority-observations`)

- **Owner:** [`src/actions/authority/parse_required_authority_observations.zig`](../../../src/actions/authority/parse_required_authority_observations.zig)
- **Reads:** `raw_required_authority_observations` · **Writes:** `required_authority_observations` · **Side effect:** `none`
- **Does:** Strictly decode an observation document; observations may reference evidence IDs
  but never create the evidence registry. The Spec workflow doesn't use it.
- **Rejects:** `InvalidRequiredAuthority` for any document that isn't the closed shape.

## `ReconcileRequiredAuthoritiesAction` (`reconcile-required-authorities`)

- **Owner:** [`src/actions/authority/reconcile_required_authorities.zig`](../../../src/actions/authority/reconcile_required_authorities.zig)
- **Reads:** `required_authority_ledger`, `required_authority_observations` · **Writes:** `required_authority_result` · **Side effect:** `none`
- **Does:** Give each requirement exactly one outcome (resolved, explicit not-applicable or
  explicit exception; clarification required; upstream rework; administrative block) and any
  candidate defect, and set the continuation: all resolved, invalid, needs user or blocked.
- **Rejects:** `InvalidRequiredAuthority`.

## `ValidateRequiredAuthorityReconciliationAction` (`validate-required-authority-reconciliation`)

- **Owner:** [`src/actions/authority/validate_required_authority_reconciliation.zig`](../../../src/actions/authority/validate_required_authority_reconciliation.zig)
  (runner [`required_authority_workflow.zig`](../../../src/application/required_authority_workflow.zig))
- **Reads:** `required_authority_inputs`, `required_authority_observations`,
  `required_authority_result` · **Writes:** `required_authority_gate` · **Side effect:** `none`
- **Does:** Rebuild the result from current native inputs and compare it, so no earlier ledger
  or result certifies a newer revision; it is the sole issuer of the `required-authority@1`
  gate.
- **Rejects:** outcome `invalid` for a candidate defect, `needs-user` for clarification gaps,
  `blocked` for upstream rework, an administrative block or `InvalidRequiredAuthority`.

## `RetireRequiredAuthorityProjectionAction` (`retire-required-authority-projection`)

- **Owner:** [`src/actions/authority/retire_required_authority_projection.zig`](../../../src/actions/authority/retire_required_authority_projection.zig)
- **Reads:** none · **Writes:** invalidates `specification_support_review`,
  `required_authority_inputs`, `required_authority_ledger`, `required_authority_observations`,
  `required_authority_result` and `required_authority_gate` · **Side effect:** `none`
- **Does:** Retire the source-review authority before generation consumes the sources.
- **Rejects:** none.

### Native source review

`specification_support.Source` owns required pre-generation source review through the
existing collection, diagnostics, atomic repair and validation. Spec runs no principle review
and no review after generation
([ADR 0023](../../decisions/0023-advisory-post-generation-review.md)). Only completed review
replaces the source authority inputs, and no action changes a negative verdict to obtain
admission.
