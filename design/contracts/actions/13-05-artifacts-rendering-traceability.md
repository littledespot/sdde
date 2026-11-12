# 13.5 Artifact, renderer, and traceability actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered operation, in workflow order: its owner, the data keys its
`NodeContract` reads and writes, what it does and what it rejects. "Proposed, no code" marks a
responsibility another document names that no code registers. Plan, Tasks and Implement
responsibilities are the stage pointers at the end.

## Clarification lifecycle

Capturing and validating the clarification inputs are steps 10 to 13 of `prepare-inputs`
([13.2](13-02-invocation-stage-gates.md#prepareinputsaction-prepare-inputs)).

## `BuildSpecificationClarificationNeedAction` (`build-specification-clarification-need`)

- **Owner:** [`src/actions/clarification/build_specification_clarification_need.zig`](../../../src/actions/clarification/build_specification_clarification_need.zig)
- **Reads:** `validated_specification_unit`, `relative_feature_directory`, `accounted_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `clarification_needs` · **Side effect:** `none`
- **Does:** Turn a generation unit's clarification response into one `spec`-stage need: the
  model's question prepared under [§12.7](../12-model-boundary.md#127-workflow-defined-model-operations),
  a fixed reason for `missing`, `ambiguous` or `conflicting`, the reference authority and a
  bounded business-text answer.
- **Rejects:** `InvalidSpecification` when the unit holds no clarification, the feature differs,
  or a records unit names no record kind.

## `BuildRequiredAuthorityClarificationNeedsAction` (`build-required-authority-clarification-needs`)

- **Owner:** [`src/actions/clarification/build_required_authority_clarification_needs.zig`](../../../src/actions/clarification/build_required_authority_clarification_needs.zig)
- **Reads:** `citable_reference_inputs`, `required_authority_inputs`, `required_authority_observations`, `required_authority_result`, `packet_guidance` · **Writes:** `clarification_needs` · **Side effect:** `none`
- **Does:** Convert every `clarification_required` gap into one need for its requirement's
  registered owner stage ([§14.14](../14-orchestration.md#1414-authorityreconciliationorchestrator)).
  Admitted review questions and details are carried under §12.7; a descriptor question serves
  only a `missing` or `stale` gap.
- **Rejects:** `InvalidRequiredAuthority` for an invalid ledger, a candidate defect, an
  administrative block, an owner mismatch, or a semantic gap with no review question.

## `BuildResolvedClarificationNeedsAction` (`build-resolved-clarification-needs`)

- **Owner:** [`src/actions/clarification/build_resolved_clarification_needs.zig`](../../../src/actions/clarification/build_resolved_clarification_needs.zig)
- **Reads:** `citable_reference_inputs` · **Writes:** `clarification_needs` · **Side effect:** `none`
- **Does:** Build an empty need set with the feature's original sources, so a run with no new gap
  still refreshes existing forms.
- **Rejects:** none beyond allocation.

## `RefreshClarificationsAction` (`refresh-clarifications`)

- **Owner:** [`src/actions/clarification/refresh_clarifications.zig`](../../../src/actions/clarification/refresh_clarifications.zig)
- **Reads:** `clarification_inputs`, `clarification_needs` · **Writes:** `refreshed_clarification_state` · **Side effect:** `none`
- **Does:** Open or update one record per need, keyed by stage and structural subject: an
  existing subject keeps its ID, a new one takes the next `SNN`, `PNN` or `TNN`, and a prior
  subject absent from the needs is retained, never inferred resolved.
- **Rejects:** `AuthenticationRequired` for a newly submitted answer, `ProtectedClarification`
  for reopening a user-closed or protected record, `ClarificationLimitExceeded` past 99, and
  `InvalidClarificationInput` for two needs with one stage and subject.

## `CheckClarificationProgressAction` (`check-clarification-progress`)

- **Owner:** [`src/actions/clarification/check_clarification_progress.zig`](../../../src/actions/clarification/check_clarification_progress.zig)
- **Reads:** `refreshed_clarification_state` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `ok` when no record is open, `needs_user` when one is, and `blocked` when the
  refresh is blocked.
- **Rejects:** none.

## `RenderClarificationFormsAction` (`render-clarification-forms`)

- **Owner:** [`src/actions/clarification/render_clarification_forms.zig`](../../../src/actions/clarification/render_clarification_forms.zig)
- **Reads:** `clarification_inputs`, `refreshed_clarification_state` · **Writes:** `clarification_views` · **Side effect:** `none`
- **Does:** Render every form from the refreshed state, keeping protected user-closed forms
  byte-for-byte ([§23.2](../23-rendering.md#232-workflow-reruns-and-protected-clarification-files)).
- **Rejects:** `clarification_inputs.Error`.

## `PrepareClarificationOutputAction` (`prepare-clarification-output`)

- **Owner:** [`src/actions/clarification/prepare_clarification_output.zig`](../../../src/actions/clarification/prepare_clarification_output.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `refreshed_clarification_state`, `clarification_views` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Rejects:** the output-preparation errors of `clarification_output.prepare`.

## Specification generation

## `CheckSpecificationSourceReadinessAction` (`check-specification-source-readiness`)

- **Owner:** [`src/actions/specification/check_specification_source_readiness.zig`](../../../src/actions/specification/check_specification_source_readiness.zig)
- **Reads:** `accounted_reference_reconciliation`, `citable_reference_inputs` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `ok` when the reconciled references are ready for generation, otherwise
  `blocked`.
- **Rejects:** none.

## `InitializeSpecificationGenerationAction` (`initialize-specification-generation`)

- **Owner:** [`src/actions/specification/initialize_specification_generation.zig`](../../../src/actions/specification/initialize_specification_generation.zig)
- **Reads:** `relative_feature_directory`, `prior_specification_state`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` (optional: `specification_support_review`, `required_authority_inputs`, `required_authority_ledger`, `required_authority_observations`, `required_authority_result`, `required_authority_gate`) · **Writes:** `specification_generation_session` · **Side effect:** `none`
- **Does:** Start the generation session from the reconciled references and carry the prior ID
  ledger.
- **Rejects:** `blocked` with a typed rejection when no claim group supports a record.

## `BuildSpecificationModelInputAction` (`build-specification-model-input`)

- **Owner:** [`src/actions/specification/build_specification_model_input.zig`](../../../src/actions/specification/build_specification_model_input.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `specification_session.Error`.

## `CollectSpecificationModelResultAction` (`collect-specification-model-result`)

- **Owner:** [`src/actions/specification/collect_specification_model_result.zig`](../../../src/actions/specification/collect_specification_model_result.zig)
- **Reads:** `specification_generation_session`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** `raw_specification_unit` · **Side effect:** `none`
- **Does:** Bind the admitted model body to the session's current unit.
- **Rejects:** `InvalidSpecificationUnit` when the packet's owner or purpose isn't the current
  unit's initial generation.

## `ParseSpecificationUnitAction` (`parse-specification-unit`)

- **Owner:** [`src/actions/specification/parse_specification_unit.zig`](../../../src/actions/specification/parse_specification_unit.zig)
- **Reads:** `raw_specification_unit`, `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `parsed_specification_unit` · **Side effect:** `none`
- **Rejects:** an unparsable body (`invalid`); `specification_session.Error`.

## `ValidateSpecificationUnitAction` (`validate-specification-unit`)

- **Owner:** [`src/actions/specification/validate_specification_unit.zig`](../../../src/actions/specification/validate_specification_unit.zig)
- **Reads:** `specification_generation_session`, `parsed_specification_unit`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `validated_specification_unit` · **Side effect:** `none`
- **Does:** Validate the unit's fields and composition and its consistency with the units already
  admitted, then admit it. An invalid unit carries its issue, field origin and owner for repair.
- **Rejects:** `InvalidSpecificationUnit` for a stale reference state or revision 0; `invalid`
  with the unit issue; `needs-user` for a clarification response.

## `ComposeSpecificationStoryAction` (`compose-specification-story`)

- **Owner:** [`src/actions/specification/compose_specification_story.zig`](../../../src/actions/specification/compose_specification_story.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** replaces `specification_generation_session` · **Side effect:** `none`
- **Does:** Compose the primary story natively, validate it as any unit and append it
  ([ADR 0047](../../decisions/0047-engine-composed-primary-story.md)).
- **Rejects:** `blocked` with `no_story_requirements` or `story_not_admissible`; never repaired.

## `AdvanceSpecificationGenerationAction` (`advance-specification-generation`)

- **Owner:** [`src/actions/specification/advance_specification_generation.zig`](../../../src/actions/specification/advance_specification_generation.zig)
- **Reads:** `accounted_reference_reconciliation`, `specification_generation_session`, `validated_specification_unit` · **Writes:** replaces `specification_generation_session`; invalidates `raw_specification_unit`, `parsed_specification_unit`, `validated_specification_unit` · **Side effect:** `none`
- **Rejects:** `specification_session.Error`.

## `CheckSpecificationGenerationProgressAction` (`check-specification-generation-progress`)

- **Owner:** [`src/actions/specification/check_specification_generation_progress.zig`](../../../src/actions/specification/check_specification_generation_progress.zig)
- **Reads:** `specification_generation_session` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `more` until every unit is complete, then `ok`.
- **Rejects:** `invalid` when a required record family is missing.

## `PlanScenarioLinksAction` (`plan-scenario-links`)

- **Owner:** [`src/actions/specification/plan_scenario_links.zig`](../../../src/actions/specification/plan_scenario_links.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `scenario_link_progress` · **Side effect:** `none`
- **Does:** Plan each edge case's outcome link
  ([ADR 0038](../../decisions/0038-record-claims-and-scenario-coverage.md) Decision 7): one
  candidate criterion links natively, several wait for a model choice.
- **Rejects:** `blocked` with `edge_case_without_criterion` when no criterion of the batch serves
  an edge case.

## `CheckScenarioLinkProgressAction` (`check-scenario-link-progress`)

- **Owner:** [`src/actions/specification/check_scenario_link_progress.zig`](../../../src/actions/specification/check_scenario_link_progress.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `more` while an edge case awaits its choice, then `ok`.
- **Rejects:** `InvalidScenarioLink` when more choices exist than pending edge cases.

## `BuildScenarioLinkInputAction` (`build-scenario-link-input`)

- **Owner:** [`src/actions/specification/build_scenario_link_input.zig`](../../../src/actions/specification/build_scenario_link_input.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Build the closed choice request for the first pending edge case.
- **Rejects:** `scenario_link_request.Error`.

## `AdmitScenarioLinkChoiceAction` (`admit-scenario-link-choice`)

- **Owner:** [`src/actions/specification/admit_scenario_link_choice.zig`](../../../src/actions/specification/admit_scenario_link_choice.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** replaces `scenario_link_progress` · **Side effect:** `none`
- **Does:** Admit the model's choice only when it names a criterion offered for the edge case next
  in the plan, and append it.
- **Rejects:** `scenario_link_request.Error`, including `InvalidScenarioLink`.

## `AssembleSpecificationContentAction` (`assemble-specification-content`)

- **Owner:** [`src/actions/specification/assemble_specification_content.zig`](../../../src/actions/specification/assemble_specification_content.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `identified_specification_content`, `specification_id_ledger` · **Side effect:** `none`
- **Does:** Assemble the admitted units and their edge-case links into identified content,
  allocating record IDs from the prior ledger.
- **Rejects:** `specification_session.Error`.

## `ValidateSpecificationCoverageAction` (`validate-specification-coverage`)

- **Owner:** [`src/actions/specification/validate_specification_coverage.zig`](../../../src/actions/specification/validate_specification_coverage.zig)
- **Reads:** `specification_generation_session`, `accounted_reference_reconciliation`, `identified_specification_content`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain` · **Writes:** `specification_coverage` · **Side effect:** `none`
- **Does:** Check the content's coverage of every reconciled claim; an invalid result carries the
  revision and repair dependencies.
- **Rejects:** `invalid` with the coverage issue; `InvalidSpecificationCoverage`.

## Specification repair ([§22](../22-repair.md))

## `AuthorizeSpecificationRepairAction` (`authorize-specification-repair`)

- **Owner:** [`src/actions/specification/authorize_specification_repair.zig`](../../../src/actions/specification/authorize_specification_repair.zig)
- **Reads:** `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_generation_session`, `parsed_specification_unit`, `validated_specification_unit`, `packet_guidance` · **Writes:** `specification_repair_authorization` · **Side effect:** `none`
- **Rejects:** `InvalidSpecificationRepair`, `UnsafeSpecificationRepair`; outcomes `blocked`,
  `invalid` and `more`.

## `BuildSpecificationRepairInputAction` (`build-specification-repair-input`)

- **Owner:** [`src/actions/specification/build_specification_repair_input.zig`](../../../src/actions/specification/build_specification_repair_input.zig)
- **Reads:** `specification_generation_session`, `specification_repair_authorization`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `specification_repair.Error`.

## `ParseSpecificationRepairAction` (`parse-specification-repair`)

- **Owner:** [`src/actions/specification/parse_specification_repair.zig`](../../../src/actions/specification/parse_specification_repair.zig)
- **Reads:** `specification_repair_authorization`, `model_input_packet`, `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result` · **Writes:** replaces `specification_repair_authorization` · **Side effect:** `none`
- **Rejects:** `specification_repair.Error`.

## `MergeSpecificationRepairAction` (`merge-specification-repair`)

- **Owner:** [`src/actions/specification/merge_specification_repair.zig`](../../../src/actions/specification/merge_specification_repair.zig)
- **Parameters:** required integer `retry-limit` ([§22.7](../22-repair.md#227-repair-retry-limit-and-escalation)).
- **Reads:** `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_generation_session`, `parsed_specification_unit`, `specification_repair_authorization` · **Writes:** replaces `parsed_specification_unit`; invalidates `validated_specification_unit`, `specification_repair_authorization` · **Side effect:** `none`
- **Does:** Merge the replacement into only the authorized unit, checked against canonical
  (NFC) source text.
- **Rejects:** `specification_repair.Error`.

## `AuthorizeSpecificationCoverageRepairAction` (`authorize-specification-coverage-repair`)

- **Owner:** [`src/actions/specification/authorize_specification_coverage_repair.zig`](../../../src/actions/specification/authorize_specification_coverage_repair.zig)
- **Reads:** `specification_generation_session`, `accounted_reference_reconciliation`, `identified_specification_content`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, `specification_coverage` · **Writes:** `specification_coverage_repair` · **Side effect:** `none`
- **Rejects:** `specification_repair.Error`; outcome `blocked`.

## Source review before generation

## `InitializeSpecificationReviewAction` (`initialize-specification-review`)

- **Owner:** [`src/actions/specification/initialize_specification_review.zig`](../../../src/actions/specification/initialize_specification_review.zig)
- **Reads:** `required_authority_inputs` · **Writes:** `specification_support_review` · **Side effect:** `none`
- **Does:** Start source review on a fresh source-readiness projection.
- **Rejects:** `InvalidRequiredAuthority` when the projection isn't source readiness or already
  holds evidence or candidates.

## `BuildSpecificationSupportInputAction` (`build-specification-support-input`)

- **Owner:** [`src/actions/specification/build_specification_support_input.zig`](../../../src/actions/specification/build_specification_support_input.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `specification_support` errors.

## `CollectSpecificationSupportAction` (`collect-specification-support`)

- **Owner:** [`src/actions/specification/collect_specification_support.zig`](../../../src/actions/specification/collect_specification_support.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result`, `packet_guidance` · **Writes:** replaces `specification_support_review` · **Side effect:** `none`
- **Rejects:** `specification_support` errors; outcome `invalid`.

## `CheckSpecificationSupportLocalizationAction` (`check-specification-support-localization`)

- **Owner:** [`src/actions/specification/check_specification_support_localization.zig`](../../../src/actions/specification/check_specification_support_localization.zig)
- **Reads:** `specification_support_review` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `complete`, `next` for another subject, or `localize` when a loss awaits
  localization.
- **Rejects:** none.

## `BuildSpecificationSupportLossInputAction` (`build-specification-support-loss-input`)

- **Owner:** [`src/actions/specification/build_specification_support_loss_input.zig`](../../../src/actions/specification/build_specification_support_loss_input.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `InvalidRequiredAuthority` for a rejected review.

## `CollectSpecificationSupportLossAction` (`collect-specification-support-loss`)

- **Owner:** [`src/actions/specification/collect_specification_support_loss.zig`](../../../src/actions/specification/collect_specification_support_loss.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result`, `packet_guidance` · **Writes:** replaces `specification_support_review` · **Side effect:** `none`
- **Rejects:** `specification_support` errors; outcome `invalid`.

## `AuthorizeSpecificationSupportRepairAction` (`authorize-specification-support-repair`)

- **Owner:** [`src/actions/specification/authorize_specification_support_repair.zig`](../../../src/actions/specification/authorize_specification_support_repair.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` · **Writes:** `specification_support_repair` · **Side effect:** `none`
- **Rejects:** `specification_support_repair` errors; outcome `blocked`.

## `BuildSpecificationSupportRepairInputAction` (`build-specification-support-repair-input`)

- **Owner:** [`src/actions/specification/build_specification_support_repair_input.zig`](../../../src/actions/specification/build_specification_support_repair_input.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_support_repair`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `specification_support_repair` errors.

## `ParseSpecificationSupportRepairAction` (`parse-specification-support-repair`)

- **Owner:** [`src/actions/specification/parse_specification_support_repair.zig`](../../../src/actions/specification/parse_specification_support_repair.zig)
- **Reads:** `specification_support_repair`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** replaces `specification_support_repair` · **Side effect:** `none`
- **Does:** Parse the repair response against its authorization.
- **Rejects:** `specification_support_repair` errors.

## `MergeSpecificationSupportRepairAction` (`merge-specification-support-repair`)

- **Owner:** [`src/actions/specification/merge_specification_support_repair.zig`](../../../src/actions/specification/merge_specification_support_repair.zig)
- **Parameters:** required integer `retry-limit` ([§22.7](../22-repair.md#227-repair-retry-limit-and-escalation)).
- **Reads:** `required_authority_inputs`, `specification_support_review`, `model_request_identity_ledger`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_support_repair`, `packet_guidance` · **Writes:** replaces `specification_support_review`; invalidates `specification_support_repair` · **Side effect:** `none`
- **Does:** Merge the repaired finding into the review, checked against canonical (NFC) source
  text.
- **Rejects:** `specification_support_repair` errors; outcome `invalid`.

## `ApplySpecificationSupportAction` (`apply-specification-support`)

- **Owner:** [`src/actions/specification/apply_specification_support.zig`](../../../src/actions/specification/apply_specification_support.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review` · **Writes:** replaces `required_authority_inputs` · **Side effect:** `none`
- **Does:** Replace the authority inputs with the accepted review's inputs.
- **Rejects:** `InvalidRequiredAuthority` for a pending or rejected review.

## Rendering and publication output

## `ProjectSpecificationDocumentAction` (`project-specification-document`)

- **Owner:** [`src/actions/specification/project_specification_document.zig`](../../../src/actions/specification/project_specification_document.zig)
- **Reads:** `identified_specification_content`, `accounted_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, `specification_coverage`, `reference_directory` · **Writes:** `specification_document` · **Side effect:** `none`
- **Does:** Project the identified content into the `spec.md` document, resolving exact copies,
  passive literals and `Source:` lines only from bound authorities.
- **Rejects:** `specification_projection.Error`.

## `RenderSpecificationAction` (`render-specification`)

- **Owner:** [`src/actions/specification/render_specification.zig`](../../../src/actions/specification/render_specification.zig)
- **Reads:** `specification_document` · **Writes:** `rendered_specification` · **Side effect:** `none`
- **Does:** Render `spec.md` under [§23.1](../23-rendering.md#231-canonical-byte-contract).
- **Rejects:** `specification_markdown.Error`.

## `ValidateSpecificationRenderingAction` (`validate-specification-rendering`)

- **Owner:** [`src/actions/specification/validate_specification_rendering.zig`](../../../src/actions/specification/validate_specification_rendering.zig)
- **Reads:** `specification_document`, `rendered_specification` · **Writes:** `validated_specification_rendering` · **Side effect:** `none`
- **Does:** Require the rendered bytes to equal the document's render and to re-render
  identically after a parse.
- **Rejects:** `InvalidSpecification`.

## `BuildSpecificationStateAction` (`build-specification-state`)

- **Owner:** [`src/actions/specification/build_specification_state.zig`](../../../src/actions/specification/build_specification_state.zig)
- **Reads:** `prior_specification_state`, `reference_snapshot`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_generation_session`, `identified_specification_content`, `specification_id_ledger`, `specification_coverage`, `principle_registry`, `refreshed_clarification_state`, `validated_specification_rendering` · **Writes:** `specification_publication_state` · **Side effect:** `none`
- **Does:** Build and validate the next `specification-state` revision after checking a valid
  rendering, resolved clarifications, the same reference state, and recomputed coverage equal to
  the accounted coverage.
- **Rejects:** `InvalidSpecificationState`.

## `PrepareSpecificationOutputAction` (`prepare-specification-output`)

- **Owner:** [`src/actions/specification/prepare_specification_output.zig`](../../../src/actions/specification/prepare_specification_output.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `refreshed_clarification_state`, `clarification_views`, `prior_specification_state`, `specification_publication_state`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `rendered_specification`, `validated_specification_rendering`, `rendered_reference_context` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Does:** Revalidate the state, clarifications and revision, require `spec.md` and
  `reference-context.md` to re-render byte-identically, and assemble them with the clarification
  files and workflow state as one output set.
- **Rejects:** `InvalidWorkflowOutput`.

## `BuildIncompleteSpecificationAction` (`build-incomplete-specification`)

- **Owner:** [`src/actions/specification/build_incomplete_specification.zig`](../../../src/actions/specification/build_incomplete_specification.zig)
- **Reads:** `prior_specification_state`, `reference_snapshot`, `refreshed_clarification_state` · **Writes:** `incomplete_specification_state` · **Side effect:** `none`
- **Does:** Build the incomplete-specification state for a run that waits on user answers.
- **Rejects:** `InvalidIncompleteSpecification`.

## `RenderIncompleteSpecificationAction` (`render-incomplete-specification`)

- **Owner:** [`src/actions/specification/render_incomplete_specification.zig`](../../../src/actions/specification/render_incomplete_specification.zig)
- **Reads:** `incomplete_specification_state`, `refreshed_clarification_state` · **Writes:** `rendered_incomplete_specification` · **Side effect:** `none`
- **Rejects:** `InvalidIncompleteSpecification`.

## `PrepareIncompleteSpecificationOutputAction` (`prepare-incomplete-specification-output`)

- **Owner:** [`src/actions/specification/prepare_incomplete_specification_output.zig`](../../../src/actions/specification/prepare_incomplete_specification_output.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `refreshed_clarification_state`, `clarification_views`, `prior_specification_state`, `incomplete_specification_state`, `rendered_incomplete_specification` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Does:** Revalidate the incomplete state, require its view to re-render identically before and
  after readback with the prior ID ledger unchanged, and assemble the output set with outcome
  `needs_user`.
- **Rejects:** `InvalidWorkflowOutput`.

## Proposed, no code: authentication chain and actor-evidence registry

[ADR 0025](../../decisions/0025-clarification-answer-authentication.md) records evidence in
this shared actor-evidence registry; no code implements it yet (SPEC01 E7). Today
`refresh-clarifications` rejects every newly submitted answer with `AuthenticationRequired`.

## `AuthenticateActorAction`

Proposed, no code: call `AuthenticationPort.authenticateAndConsume` once with a runner-issued
single-use lease; the runner's lease table, never the envelope, holds the credential, and the
port finalizes it on every terminal branch. ADR 0025's first provider is the operating-system
account that runs the engine, for clarification responses only.

## `ValidateAuthenticationObservationAction`

Proposed, no code: before any evidence ID is allocated, reject a missing or unknown actor, a
provider or policy mismatch, an impossible or expired time, any credential-shaped field and
assurance incompatible with the event kind.

## `AssignAuthenticationEvidenceIdAction`

Proposed, no code: assign one monotonic engine evidence ID as an allocation delta, without
mutating the registry.

## `BuildAuthenticatedActorEvidenceAction`

Proposed, no code: bind that ID to public provider, actor, assurance and time metadata, with no
credential material.

## `ValidateAuthenticatedActorEvidenceAction`

Proposed, no code: prove the evidence ID, actor, context, provider and policy, its freshness at
the event's time and its compatibility with the event kind, without authenticating again.

## `BuildInitialActorEvidenceRegistryStateAction`

Proposed, no code: create the activation-time registry at revision zero with the next evidence
ordinal set to one; the registry is new persisted state (ADR 0025).

## `AppendAuthenticatedActorEvidenceAction`

Proposed, no code: append one validated, non-duplicate evidence entry, consuming exactly the
allocated ordinal; history is append-only and no credential is accepted.

## `BuildActorEvidenceIdRetirementRegistryStateAction`

Proposed, no code: from a specification-edit evidence retirement record, retire one allocated,
unreferenced evidence ID by appending it to `retiredAuthenticationEvidenceIds`; advance only
the registry's identity, revision and next ordinal, copy the entries byte for byte and append no
evidence.

## `ValidateActorEvidenceRegistryStateAction`

Proposed, no code: prove unique monotonic IDs and append-only history; each revision holds
either one actor-, context- and time-valid evidence append, with total joins to specification
acknowledgements, clarification responses, reviews, reference feedback, reference-conflict
decisions and manual evidence, or byte-equal entries plus exactly one unreferenced allocated-ID
tombstone, never both.

## `SerializeActorEvidenceRegistryStateAction`

Proposed, no code: serialize public actor and evidence metadata only, never a credential or
token.

## `ParseActorEvidenceRegistryStateAction`

Proposed, no code: parse one persisted registry revision into an unvalidated registry.

## `ValidateClarificationUserSubmissionAction`

Proposed, no code: before authentication, reject a stale or immutable-field edit; require a
non-empty matching answer to close; for `select_many`, require unique known keys within the
bounds and put only the response value into the engine's option order, never rewriting the
submitted bytes; check the bounded defer and cancel reason shapes. Each rejected form returns a
typed reason; one rejected closed form stops the run before any lease is consumed, and no
answer in that run is accepted.

## `BindAuthenticatedClarificationSubmissionAction`

Proposed, no code: bind the validated fresh actor evidence to the already valid answer and its
event kind, allocating no ID and changing no lifecycle.

## `AssignClarificationResponseIdAction`

Proposed, no code: choose one monotonic response ID only inside the complete output candidate;
a failed pre-commit candidate exposes no ID, and a committed ordinal is never reused.

## `BuildClarificationResponseAction`

Proposed, no code: build the accepted response from the response identity, the bound
submission, the current record and state and the trusted clock, binding the answer variant, the
exact bounded submitted form bytes, actor and evidence equality and compare-and-swap revisions;
it is the sole durable owner of the submitted bytes.

## Proposed, no code: other responsibilities named elsewhere

## `BuildReferenceConflictClarificationSetTransitionAction`

Proposed, no code: apply every continued, obsolete and introduced reference-conflict subject as
one clarification-set transition ([§16](../16-reference-ingestion.md)).

## `BuildUserAuthoredProvenanceAction`

Proposed, no code: record an authenticated user edit as user-authored provenance
([§16.5](../16-reference-ingestion.md#165-human-correction-without-editing-generated-views)).

## `CompareSpecificationIRAction`

Proposed, no code: compare a reparsed `spec.md` with its authoritative predecessor by typed value,
not by rendered bytes ([§23](../23-rendering.md)).

## `ValidateClarificationStageGateAction`

Proposed, no code: apply §24.2's clarification gate matrix at each stage boundary
([§24.2](../24-workflow-state.md#242-stage-transition-state-machine)).

## `BuildWorkflowControlEventAppendSequenceAction`

Proposed, no code: derive the control events one output appends: a final failure or completion
appends one final record; localized remediation one evidence invalidation;
reference-revision, rework or reconciliation a rework invalidation, then any evidence
invalidation; other mutations none ([§24.5](../24-workflow-state.md#245-upstream-rework-and-invalidation)).

## `AppendWorkflowControlEventAction`

Proposed, no code: append one immutable control event and advance only its namespace. An output
that needs two events appends them through two runner-owned child bindings against successive
in-memory registry candidates; only the final revision is prepared with the output.

## Proposed, no code: Plan, Tasks and Implement

- **Plan** ([§18](../18-plan.md)): plan input authority and plan state; research evidence;
  obligation ledger; artifact decisions; file grants and dependency mutation surfaces; data model,
  contract, quickstart and research records; contract views; plan review units; plan rendering
  and review decisions.
- **Tasks** ([§19](../19-tasks.md)): task definition and runtime state, task IDs, and task
  rendering.
- **Implement** ([§20](../20-implement.md)): runtime file state, execution and verification
  evidence, and descendant invalidation on rework
  ([§24.5](../24-workflow-state.md#245-upstream-rework-and-invalidation)).

Plan, Tasks and Implement design writes these entries when it starts. The entries below are the
names other documents already use.

## `BuildPlanFileGrantAction`

Proposed, no code: grant one planned file to its plan unit with an exact capability
([§18](../18-plan.md)).

## `BuildContractViewRegistryAction`

Proposed, no code: register the per-contract generated views a plan output owns
([§18](../18-plan.md)).

## `ValidateReviewSubmissionAction`

Proposed, no code: validate a Plan or Tasks review submission before authentication
([§18.7](../18-plan.md#187-plan-outputs-and-gate), [§19.6](../19-tasks.md#196-rendering-and-gate)).

## `BindAuthenticatedReviewSubmissionAction`

Proposed, no code: bind validated fresh actor evidence to a validated review submission
([§18.7](../18-plan.md#187-plan-outputs-and-gate)).
