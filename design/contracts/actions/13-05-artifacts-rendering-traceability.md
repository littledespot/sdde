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
- **Reads:** `validated_specification_unit`, `relative_feature_directory`, `accounted_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals` · **Writes:** `clarification_needs` · **Side effect:** `none`
- **Does:** Turn a generation unit's clarification response into one `spec`-stage need: the
  model's question prepared under [§12.7](../12-model-boundary.md#127-workflow-defined-model-operations),
  a fixed reason for `missing`, `ambiguous` or `conflicting`, the reference authority, a
  bounded business-text answer and the subject. A records need's subject names the source
  lines cited by its bound signal's claims, and the brief's and entities' name their unit
  ([ADR 0025](../../decisions/0025-clarification-answer-authentication.md), the clarification subject).
- **Rejects:** `InvalidSpecification` when the unit holds no clarification, the feature differs,
  a records unit names no record kind (which the subject does not use), or the question's
  citations name no line of a source the corpus holds.

## `BuildRequiredAuthorityClarificationNeedsAction` (`build-required-authority-clarification-needs`)

- **Owner:** [`src/actions/clarification/build_required_authority_clarification_needs.zig`](../../../src/actions/clarification/build_required_authority_clarification_needs.zig)
- **Reads:** `citable_reference_inputs`, `required_authority_inputs`, `required_authority_observations`, `required_authority_result`, `packet_guidance` · **Writes:** `clarification_needs` · **Side effect:** `none`
- **Does:** Convert every `clarification_required` gap into a need for its requirement's
  registered owner stage ([§14.14](../14-orchestration.md#1414-authorityreconciliationorchestrator)).
  Admitted review questions and details are carried under §12.7; a descriptor question serves
  only a `missing` or `stale` gap. The need's subject names the requirement's kind and slot and
  the unit's kind, with the source text the unit concerns: the whole source, or the lines cited
  by a signal's, a conflict's or a token's claims. The contract version and a generated unit's
  ordinal are not part of it (ADR 0025, the clarification subject). Gaps of one stage and one
  subject are one need: it asks each distinct question and gives each distinct reason, in the
  ledger's order, binds the union of the gaps' authorities and cites the union of their evidence.
  A gap over other text, or of another stage, stays its own need. The need of a reference conflict is a select-one form
  with one option for each claim of the conflict (a key naming the lines the claim cites, labelled with its quotation); two
  conflicts of one subject offer the union of their options once each, and every other need is answered in bounded text
  ([ADR 0025](../../decisions/0025-clarification-answer-authentication.md), "The answer to a conflict").
- **Rejects:** `InvalidRequiredAuthority` for an invalid ledger, a candidate defect, an
  administrative block, an upstream-rework entry, an owner mismatch, a semantic gap with no
  review question, a unit the accounted evidence or the corpus does not hold, a subject whose
  merged question or reason exceeds the form's text bound, whose authorities exceed a record's,
  or that names one canonical record at two revisions, and for a conflict whose claims cannot be options (two claims citing
  the same lines, a key or label the form cannot hold, or more than 32 options). Nothing is truncated or dropped to fit.

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
- **Rejects:** `AuthenticationRequired` for a submitted answer that was not accepted before it (a
  deferral is not one and leaves its record open), `ProtectedClarification`
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

## Specification generation

## `CheckSpecificationSourceReadinessAction` (`check-specification-source-readiness`)

- **Owner:** [`src/actions/specification/check_specification_source_readiness.zig`](../../../src/actions/specification/check_specification_source_readiness.zig)
- **Reads:** `accounted_reference_reconciliation`, `citable_reference_inputs` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `ok` when the reconciled references are ready for generation, otherwise
  `blocked`.
- **Rejects:** none.

## `InitializeSpecificationGenerationAction` (`initialize-specification-generation`)

- **Owner:** [`src/actions/specification/initialize_specification_generation.zig`](../../../src/actions/specification/initialize_specification_generation.zig)
- **Reads:** `relative_feature_directory`, `prior_specification_state`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` (optional: `specification_support_review`, `required_authority_inputs`, `required_authority_ledger`, `required_authority_observations`, `required_authority_result`, `required_authority_gate`) · **Writes:** `specification_generation_session` · **Side effect:** `none`
- **Does:** Start the generation session from the reconciled references and carry the prior ID
  ledger.
- **Rejects:** `blocked` with a typed rejection when no claim group supports a record.

## `BuildSpecificationModelInputAction` (`build-specification-model-input`)

- **Owner:** [`src/actions/specification/build_specification_model_input.zig`](../../../src/actions/specification/build_specification_model_input.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `packet_guidance`, `principle_registry` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Build the request of the unit in flight: the brief, entities or records packet or, while
  scenarios are written ([ADR 0038](../../decisions/0038-record-claims-and-scenario-coverage.md)
  Decision 3), the next group's requirements, numbered from one, each with its claim's meaning and
  source. The session's scenarios phase selects the branch. The records packet also carries the
  principle files (SPEC01 D17.1, [17-specify.md](../17-specify.md)); no other packet does.
- **Rejects:** `scenario_request.Error`, which holds `specification_session.Error`, the slot
  errors and the reference reconciliation errors.

## `CollectSpecificationModelResultAction` (`collect-specification-model-result`)

- **Owner:** [`src/actions/specification/collect_specification_model_result.zig`](../../../src/actions/specification/collect_specification_model_result.zig)
- **Reads:** `specification_generation_session`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** `raw_specification_unit` · **Side effect:** `none`
- **Does:** Bind the admitted model body to the session's current unit.
- **Rejects:** `InvalidSpecificationUnit` when the packet's owner or purpose isn't the current
  unit's initial generation.

## `ParseSpecificationUnitAction` (`parse-specification-unit`)

- **Owner:** [`src/actions/specification/parse_specification_unit.zig`](../../../src/actions/specification/parse_specification_unit.zig)
- **Reads:** `raw_specification_unit`, `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `parsed_specification_unit` · **Side effect:** `none`
- **Does:** Parse the unit's response. While scenarios are written, the answer's numbered scenarios
  become the acceptance criteria of the group's batch, each bound to its slot's claim.
- **Rejects:** an unparsable body (`invalid`); `scenario_request.Error` (`specification_session.Error`,
  the slot errors and the reference reconciliation errors).

## `ValidateSpecificationUnitAction` (`validate-specification-unit`)

- **Owner:** [`src/actions/specification/validate_specification_unit.zig`](../../../src/actions/specification/validate_specification_unit.zig)
- **Reads:** `specification_generation_session`, `parsed_specification_unit`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `validated_specification_unit` · **Side effect:** `none`
- **Does:** Validate the unit's fields and composition and its consistency with the units already
  admitted, then admit it. An invalid unit carries its issue, field origin and owner for repair.
- **Rejects:** `InvalidSpecificationUnit` for a stale reference state or revision 0; `invalid`
  with the unit issue; `needs-user` for a clarification response.

## `ComposeSpecificationStoryAction` (`compose-specification-story`)

- **Owner:** [`src/actions/specification/compose_specification_story.zig`](../../../src/actions/specification/compose_specification_story.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** replaces `specification_generation_session` · **Side effect:** `none`
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
- **Does:** Return `more` while a source group still awaits its records, then `ok`.
- **Rejects:** `invalid` when a mandatory record family the records step writes is missing; the
  criterion family is the scenarios step's, checked by `check-scenario-generation-progress`.

## `PlanScenarioGenerationAction` (`plan-scenario-generation`)

- **Owner:** [`src/actions/specification/plan_scenario_generation.zig`](../../../src/actions/specification/plan_scenario_generation.zig)
- **Reads:** `specification_generation_session`, `accounted_reference_reconciliation` · **Writes:** `scenario_generation_progress` · **Side effect:** `none`
- **Does:** Plan the scenarios step's population, the groups with at least one scenario slot
  ([ADR 0038](../../decisions/0038-record-claims-and-scenario-coverage.md) Decision 3), once every
  group's records are admitted. The session is unchanged.
- **Rejects:** `InvalidSpecificationUnit` outside the scenario phase or after a group's scenarios
  are written.

## `CheckScenarioGenerationProgressAction` (`check-scenario-generation-progress`)

- **Owner:** [`src/actions/specification/check_scenario_generation_progress.zig`](../../../src/actions/specification/check_scenario_generation_progress.zig)
- **Reads:** `specification_generation_session`, `scenario_generation_progress` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `more` while a group with a slot awaits its scenarios, then `ok`.
- **Rejects:** `invalid` when the held batches hold no criterion, the family this step writes.

## `AdvanceScenarioGenerationAction` (`advance-scenario-generation`)

- **Owner:** [`src/actions/specification/advance_scenario_generation.zig`](../../../src/actions/specification/advance_scenario_generation.zig)
- **Reads:** `accounted_reference_reconciliation`, `specification_generation_session`, `scenario_generation_progress`, `validated_specification_unit` · **Writes:** replaces `specification_generation_session`, `scenario_generation_progress`; invalidates `raw_specification_unit`, `parsed_specification_unit`, `validated_specification_unit` · **Side effect:** `none`
- **Does:** Join the validated criteria to their group's batch and count the group as written. It
  completes no unit.
- **Rejects:** `specification_session.Error`.

## `CompleteScenarioGenerationAction` (`complete-scenario-generation`)

- **Owner:** [`src/actions/specification/complete_scenario_generation.zig`](../../../src/actions/specification/complete_scenario_generation.zig)
- **Reads:** `specification_generation_session` · **Writes:** replaces `specification_generation_session` · **Side effect:** `none`
- **Does:** Merge the held batches once every group with a slot has its criteria. It is the only
  operation that merges them.
- **Rejects:** `specification_session.Error`.

## `PlanScenarioLinksAction` (`plan-scenario-links`)

- **Owner:** [`src/actions/specification/plan_scenario_links.zig`](../../../src/actions/specification/plan_scenario_links.zig)
- **Reads:** `specification_generation_session`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `scenario_link_progress` · **Side effect:** `none`
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
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Does:** Build the closed choice request for the first pending edge case.
- **Rejects:** `scenario_link_request.Error`.

## `AdmitScenarioLinkChoiceAction` (`admit-scenario-link-choice`)

- **Owner:** [`src/actions/specification/admit_scenario_link_choice.zig`](../../../src/actions/specification/admit_scenario_link_choice.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result` · **Writes:** replaces `scenario_link_progress` · **Side effect:** `none`
- **Does:** Admit the model's choice only when it names a criterion offered for the edge case next
  in the plan, and append it.
- **Rejects:** `scenario_link_request.Error`, including `InvalidScenarioLink`.

## `AssembleSpecificationContentAction` (`assemble-specification-content`)

- **Owner:** [`src/actions/specification/assemble_specification_content.zig`](../../../src/actions/specification/assemble_specification_content.zig)
- **Reads:** `specification_generation_session`, `scenario_link_progress`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals` · **Writes:** `identified_specification_content`, `specification_id_ledger` · **Side effect:** `none`
- **Does:** Assemble the admitted units and their edge-case links into identified content,
  allocating record IDs from the prior ledger.
- **Rejects:** `specification_session.Error`.

## `ValidateSpecificationCoverageAction` (`validate-specification-coverage`)

- **Owner:** [`src/actions/specification/validate_specification_coverage.zig`](../../../src/actions/specification/validate_specification_coverage.zig)
- **Reads:** `specification_generation_session`, `accounted_reference_reconciliation`, `identified_specification_content`, `citable_reference_inputs`, `reference_passive_literals` · **Writes:** `specification_coverage` · **Side effect:** `none`
- **Does:** Check the content's coverage of every reconciled claim. A coverage defect has no
  independently supported repair target, so the step returns `blocked` itself, with the coverage
  issue and `no_independent_supported_target`.
- **Rejects:** `blocked` with the coverage issue; `InvalidSpecificationCoverage`.

## Specification repair ([§22](../22-repair.md))

The specification unit and specification support repair operations are
variants of the generic repair operations, specified once in
[13-04](13-04-model.md#generic-repair-operations).

## Source review before generation

## `InitializeSpecificationReviewAction` (`initialize-specification-review`)

- **Owner:** [`src/actions/specification/initialize_specification_review.zig`](../../../src/actions/specification/initialize_specification_review.zig)
- **Reads:** `required_authority_inputs` · **Writes:** `specification_support_review` · **Side effect:** `none`
- **Does:** Start source review on a fresh source-readiness or source-preservation projection.
- **Rejects:** `InvalidRequiredAuthority` when the projection is neither source readiness nor
  source preservation, or already holds evidence or candidates.

## `BuildSpecificationSupportInputAction` (`build-specification-support-input`)

- **Owner:** [`src/actions/specification/build_specification_support_input.zig`](../../../src/actions/specification/build_specification_support_input.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `specification_support` errors.

## `CollectSpecificationSupportAction` (`collect-specification-support`)

- **Owner:** [`src/actions/specification/collect_specification_support.zig`](../../../src/actions/specification/collect_specification_support.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result`, `packet_guidance` · **Writes:** replaces `specification_support_review` · **Side effect:** `none`
- **Rejects:** `specification_support` errors; outcome `invalid`.

## `CheckSpecificationSupportLocalizationAction` (`check-specification-support-localization`)

- **Owner:** [`src/actions/specification/check_specification_support_localization.zig`](../../../src/actions/specification/check_specification_support_localization.zig)
- **Reads:** `specification_support_review` · **Writes:** none · **Side effect:** `none`
- **Does:** Return `complete`, `next` for another subject, or `localize` when a loss awaits
  localization.
- **Rejects:** none.

## `BuildSpecificationSupportLossInputAction` (`build-specification-support-loss-input`)

- **Owner:** [`src/actions/specification/build_specification_support_loss_input.zig`](../../../src/actions/specification/build_specification_support_loss_input.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `packet_guidance` · **Writes:** `model_input_packet` · **Side effect:** `none`
- **Rejects:** `InvalidRequiredAuthority` for a rejected review.

## `CollectSpecificationSupportLossAction` (`collect-specification-support-loss`)

- **Owner:** [`src/actions/specification/collect_specification_support_loss.zig`](../../../src/actions/specification/collect_specification_support_loss.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `model_request_identity_ledger`, `prepared_model_request`, `model_input_packet`, `model_payload_schema_result`, `packet_guidance` · **Writes:** replaces `specification_support_review` · **Side effect:** `none`
- **Rejects:** `specification_support` errors; outcome `invalid`.

## `ApplySpecificationSupportAction` (`apply-specification-support`)

- **Owner:** [`src/actions/specification/apply_specification_support.zig`](../../../src/actions/specification/apply_specification_support.zig)
- **Reads:** `required_authority_inputs`, `specification_support_review` · **Writes:** replaces `required_authority_inputs` · **Side effect:** `none`
- **Does:** Replace the authority inputs with the accepted review's inputs.
- **Rejects:** `InvalidRequiredAuthority` for a pending or rejected review.

## Rendering and publication output

## `ProjectSpecificationDocumentAction` (`project-specification-document`)

- **Owner:** [`src/actions/specification/project_specification_document.zig`](../../../src/actions/specification/project_specification_document.zig)
- **Reads:** `identified_specification_content`, `accounted_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals`, `specification_coverage`, `reference_directory` · **Writes:** `specification_document` · **Side effect:** `none`
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
- **Reads:** `prior_specification_state`, `reference_snapshot`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `specification_generation_session`, `identified_specification_content`, `specification_id_ledger`, `specification_coverage`, `principle_registry`, `refreshed_clarification_state`, `validated_specification_rendering` · **Writes:** `specification_publication_state` · **Side effect:** `none`
- **Does:** Build and validate the next `specification-state` revision once the rendering has
  validated (the `validated_specification_rendering` key orders this step after that validation, and
  carries no value), after checking resolved clarifications, the same reference state, and
  recomputed coverage equal to the accounted coverage.
- **Rejects:** `InvalidSpecificationState`.

## `PrepareSpecificationOutputAction` (`prepare-specification-output`)

- **Owner:** [`src/actions/specification/prepare_specification_output.zig`](../../../src/actions/specification/prepare_specification_output.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `raw_actor_evidence`, `actor_evidence_registry`, `refreshed_clarification_state`, `clarification_views`, `prior_specification_state`, `specification_publication_state`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `rendered_specification`, `validated_specification_rendering`, `rendered_reference_context` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Does:** Revalidate the state, clarifications and revision, require `spec.md` and
  `reference-context.md` to re-render byte-identically, and assemble them with the clarification
  files, the actor-evidence registry that the responses join and the workflow state as one output
  set.
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
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `raw_actor_evidence`, `actor_evidence_registry`, `refreshed_clarification_state`, `clarification_views`, `prior_specification_state`, `incomplete_specification_state`, `rendered_incomplete_specification` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Does:** Revalidate the incomplete state, require its view to re-render identically before and
  after readback with the prior ID ledger unchanged, and assemble the output set, including the
  actor-evidence registry, with outcome `needs_user`.
- **Rejects:** `InvalidWorkflowOutput`.

## Authentication chain and actor-evidence registry

[ADR 0025](../../decisions/0025-clarification-answer-authentication.md) records evidence in
this shared actor-evidence registry, `actor-evidence-registry/v1`. The chain's per-step
responsibilities that an earlier revision of this catalogue listed as actions of their own (validate
the observation, assign, build, append and validate the evidence, bind the submission, assign the
response ID, build the response, and the registry's initial state, serialization and parsing) are the
internal steps and domain functions of the operations below, not operations of their own
([ADR 0031](../../decisions/0031-stage-actions.md)). Only `authenticate-actor` reaches a port.

## `PrepareActorEvidenceAction` (`prepare-actor-evidence`)

- **Owner:** [`src/actions/specify/prepare_actor_evidence.zig`](../../../src/actions/specify/prepare_actor_evidence.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `clarification_inputs` · **Writes:** `raw_actor_evidence`, `actor_evidence_registry` · **Side effect:** `filesystem_read`
- **Does:** A stage action of three steps: capture the feature's registry file through the
  feature-input port (or report it absent), parse it through the registry parser, and validate it
  against the feature and the responses of the clarification state. A feature with no registry has
  the empty one, at revision 0 with the next ordinal 1. It runs after feature logging activates, so
  its directory is the activated one.
- **Rejects:** `FeatureInputUnavailable`, `InvalidActorEvidence` and `Cancelled`.

## `PlanClarificationAuthenticationAction` (`plan-clarification-authentication`)

- **Owner:** [`src/actions/clarification/plan_clarification_authentication.zig`](../../../src/actions/clarification/plan_clarification_authentication.zig)
- **Reads:** `clarification_inputs` · **Writes:** `authentication_progress` · **Side effect:** `none`
- **Does:** Initialize the loop's iteration: the submitted closed forms with an answer and the submitted
  cancels with a reason, in the registry's order, each one pass. A deferral and a form already
  recorded are not in it, and the population is frozen.
- **Rejects:** none beyond allocation.

## `CheckClarificationAuthenticationAction` (`check-clarification-authentication`)

- **Owner:** [`src/actions/clarification/check_clarification_authentication.zig`](../../../src/actions/clarification/check_clarification_authentication.zig)
- **Reads:** `clarification_inputs`, `authentication_progress` · **Writes:** none · **Side effect:** `none`
- **Does:** Report `more` while a form awaits its observation, else `ok`.
- **Rejects:** none.

## `AuthenticateActorAction` (`authenticate-actor`)

- **Owner:** [`src/actions/clarification/authenticate_actor.zig`](../../../src/actions/clarification/authenticate_actor.zig)
- **Reads:** `clarification_inputs`, `authentication_progress` · **Writes:** `actor_observation` · **Side effect:** `actor_authentication`
- **Does:** Call `AuthenticationPort` once with the runner-issued single-use lease: the port consumes
  the lease, then reads the operating-system account that runs the engine, with the feature log's run
  and the trusted clock's UTC time. The runner's lease table, never the envelope, holds the lease and
  ends it on every path; the observation is the step's own and nothing records it.
- **Rejects:** `AuthenticationDenied` for a lease the runner did not issue or that was spent,
  `AccountUnavailable`, `UnsupportedPlatform`, `ClockUnavailable` and `Cancelled`.

## `AdvanceClarificationAuthenticationAction` (`advance-clarification-authentication`)

- **Owner:** [`src/actions/clarification/advance_clarification_authentication.zig`](../../../src/actions/clarification/advance_clarification_authentication.zig)
- **Reads:** `clarification_inputs`, `authentication_progress`, `actor_observation` · **Writes:** none · **Replaces:** `authentication_progress` · **Invalidates:** `actor_observation` · **Side effect:** `none`
- **Does:** Join the observation to the form just authenticated and advance the iteration by one.
- **Rejects:** `InvalidClarificationInput` for an observation beyond the planned forms.

## `AcceptClarificationResponsesAction` (`accept-clarification-responses`)

- **Owner:** [`src/actions/clarification/accept_clarification_responses.zig`](../../../src/actions/clarification/accept_clarification_responses.zig)
- **Reads:** `clarification_inputs`, `raw_clarification_inputs`, `actor_evidence_registry`, `authentication_progress` · **Replaces:** `clarification_inputs`, `actor_evidence_registry` · **Side effect:** `none`
- **Does:** A stage action of four steps: pair each authenticated form with its captured bytes
  (exactly the pending forms, each once, in order), append the run's evidence to the registry in one
  revision (`AE-<ordinal>`), accept each form as a response and resolve its record (`resolved_by_user`,
  or `cancelled_by_user` for a cancel) in a state one ordinal and one revision later, and check that
  the responses join the registry. Nothing is written: the accepted state and the registry stay in
  memory until the run publishes them.
- **Rejects:** `InvalidClarificationInput` for progress that is not the pending forms or a form with no
  captured bytes, `UnsupportedActorName` for an account name outside the stored-identifier syntax,
  `InvalidActorEvidence` for responses that do not join the registry, and `Cancelled`.

## `CheckClarificationCancellationAction` (`check-clarification-cancellation`)

- **Owner:** [`src/actions/clarification/check_clarification_cancellation.zig`](../../../src/actions/clarification/check_clarification_cancellation.zig)
- **Reads:** `clarification_inputs`, `authentication_progress` · **Writes:** none · **Side effect:** `none`
- **Does:** Report `cancelled` when a form this run accepted cancelled its record, else `ok`. The
  outcome stays associated with the accepted inputs, which lets the cancelled output's publisher end
  the run `cancelled` ([ADR 0025](../../decisions/0025-clarification-answer-authentication.md)).
- **Rejects:** none.

## `PrepareCancelledClarificationOutputAction` (`prepare-cancelled-clarification-output`)

- **Owner:** [`src/actions/clarification/prepare_cancelled_clarification_output.zig`](../../../src/actions/clarification/prepare_cancelled_clarification_output.zig)
- **Reads:** `activated_feature_directory`, `feature_artifact_paths`, `raw_clarification_inputs`, `clarification_inputs`, `authentication_progress`, `raw_actor_evidence`, `actor_evidence_registry`, `citable_reference_inputs` · **Writes:** `prepared_workflow_output` · **Side effect:** `none`
- **Does:** Assemble the output of a run the user cancelled: the canonical forms of the accepted state, the
  registry and the clarification state, in that order, with terminal outcome `cancelled`, and no
  specification, reference context or workflow state. It requires one of the forms this run accepted
  to have cancelled its record.
- **Rejects:** `InvalidWorkflowOutput`, `InvalidActorEvidence` and `InvalidClarificationInput`.

## `BuildActorEvidenceIdRetirementRegistryStateAction`

Proposed, no code: from a specification-edit evidence retirement record, retire one allocated,
unreferenced evidence ID by appending it to `retiredAuthenticationEvidenceIds`; advance only
the registry's identity, revision and next ordinal, copy the entries byte for byte and append no
evidence.

## `ValidateActorEvidenceRegistryStateAction`

Built for clarification responses only, as a step of `prepare-actor-evidence`: the registry is the
feature's append-only sequence (unique monotonic `AE-<ordinal>` IDs, one revision for each run that
appends all of its forms), every response joins an entry with the same account and time, and no entry
is joined twice. Proposed, no code: the joins to specification acknowledgements, reviews,
reference feedback, reference-conflict decisions and manual evidence, and a revision of byte-equal
entries plus one unreferenced allocated-ID tombstone.

## `ValidateClarificationUserSubmissionAction`

Proposed, no code: before authentication, reject a stale or immutable-field edit; require a
non-empty matching answer to close; for `select_many`, require unique known keys within the
bounds and put only the response value into the engine's option order, never rewriting the
submitted bytes; check the bounded defer and cancel reason shapes. Each rejected form returns a
typed reason; one rejected closed form stops the run before any lease is consumed, and no
answer in that run is accepted.

The response is built by `accept-clarification-responses`: its ID is the next monotonic ordinal of
the state it builds, exposed only in the complete output candidate, and it is the sole durable owner
of the submitted bytes.

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
