# 13.4 Model actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

One entry per registered operation; reads and writes are its action's `NodeContract` data keys.
Where the registered workflow step that wraps the action declares different keys or parameters,
a **Registered step** line gives the step's, which is what a workflow definition must match.
The request-preparation parameters are required `slot` and `prompt`, and optional `context`,
`protocol-prompt`, `result-schema`, `composition-part`, `result-selection` and `input`
([`model_request_workflow.zig`](../../../src/application/model_request_workflow.zig)); a
definition supplies exactly one of `result-schema` or `composition-part`, and
`composition-part` excludes `result-selection` and `input`
([`workflow_model.zig`](../../../src/domain/workflow_model.zig)). Three entries are actions
without a workflow step: `check-workflow-token-budget` and `reconcile-workflow-token-usage`
are called inside the runner's token accounting, and `build-immutable-unit-owner-id` has no
production caller.
[§12](../12-model-boundary.md) owns the model boundary and
[model-request-operations.md](../model-request-operations.md) the request lifecycle these
operations implement. Under [ADR 0030](../../decisions/0030-engine-owned-model-request.md)
(not yet implemented) the request-lifecycle operations become stages of one `request-model`
step. Entries marked "Proposed, no code" are named elsewhere but have no registered operation.

## Request identity and preparation

## `BuildInitialModelRequestIdentityLedgerAction` (`build-initial-model-request-identity-ledger`)

- **Owner:** [`src/actions/model/build_initial_model_request_identity_ledger.zig`](../../../src/actions/model/build_initial_model_request_identity_ledger.zig)
- **Reads:** none · **Writes:** `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Creates the run's empty request-identity ledger from the closed request-purpose registry; it is the key's sole producer.
- **Rejects:** `InvalidRequestPurposeRegistry` and the other `model_request_identity.ValidationError` cases.

## `BuildImmutableUnitOwnerIdAction` (`build-immutable-unit-owner-id`)

- **Owner:** [`src/actions/model/build_immutable_unit_owner_id.zig`](../../../src/actions/model/build_immutable_unit_owner_id.zig)
- **Reads:** none · **Writes:** none (returns the owner) · **Side effect:** `none`
- **Does:** Validates one immutable unit-owner descriptor and returns it unchanged.
- **Rejects:** `InvalidImmutableUnitOwnerId`.

## `AssignModelRequestIdAction` (`assign-model-request-id`)

- **Owner:** [`src/actions/model/assign_model_request_id.zig`](../../../src/actions/model/assign_model_request_id.zig)
- **Reads:** `model_request_identity_ledger` · **Writes:** replaces `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Allocates one logical request ordinal for a unit owner, model operation and purpose binding at the expected ledger revision; protocol retries reuse the identity.
- **Registered step:** reads `model_request_identity_ledger` (optional: `model_input_packet`, `json_composition`), writes `assigned_model_request` and replaces the ledger, with the request-preparation parameters.
- **Rejects:** `ModelRequestRevisionConflict`, `InvalidRequestPurposeBinding`, `RequestPurposeNotRegistered`, ordinal or revision exhaustion.

## `ValidateModelRequestBindingAction` (`validate-model-request-binding`)

- **Owner:** [`src/actions/model/validate_model_request_binding.zig`](../../../src/actions/model/validate_model_request_binding.zig)
- **Reads:** `model_request_identity_ledger` · **Writes:** none (returns binding evidence) · **Side effect:** `none`
- **Does:** Proves a request ID's ledger membership, unit owner, model operation and purpose at the expected revision.
- **Registered step:** reads `model_request_identity_ledger`, `assigned_model_request` and writes `validated_model_request`.
- **Rejects:** `ModelRequestBindingInvalid`, `ModelRequestNotFound`, `ModelRequestRevisionConflict`.

## `BuildModelRequestAction` (`build-model-request`)

- **Owner:** [`src/actions/model/build_model_request.zig`](../../../src/actions/model/build_model_request.zig)
- **Reads:** `model_request_identity_ledger`, `validated_provider_model_binding` · **Writes:** none (returns the prepared request) · **Side effect:** `none`
- **Does:** Builds one identified provider-neutral request from a validated source and its model-visible content.
- **Registered step:** reads `model_request_identity_ledger`, `validated_model_request` and writes `prepared_model_request`.
- **Rejects:** `InvalidModelRequestSource`, `ModelRequestAssociationInvalid`, `ModelRequestBindingInvalid`.

## `PrepareModelRequestAction` (`prepare-model-request`)

- **Owner:** [`src/actions/model/prepare_model_request.zig`](../../../src/actions/model/prepare_model_request.zig)
- **Reads:** `model_request_identity_ledger` (optional: `model_input_packet`, `json_composition`) · **Writes:** `assigned_model_request`, `validated_model_request`, `prepared_model_request`; replaces `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Assigns, validates and prepares one request in a single runner delta through the identity, binding and request-construction owners ([ADR 0012](../../decisions/0012-workflow-owned-model-request.md)); no authorization, call, retry or accounting.
- **Registered step:** the same keys, with the request-preparation parameters.
- **Rejects:** the request-handoff and identity errors (`ModelRequestRevisionConflict`, `InvalidModelRequestSource`, packet errors).

## `CheckModelRequestPhaseAction` (`check-model-request-phase`)

- **Owner:** [`src/actions/model/check_model_request_phase.zig`](../../../src/actions/model/check_model_request_phase.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request` · **Writes:** none · **Side effect:** `none`
- **Does:** Routes on the request's status: `ok` when assigned, `more` when invoked.
- **Rejects:** `failed` when the request is terminal or absent.

## `AdvanceModelRequestLifecycleAction` (`advance-model-request-lifecycle`)

- **Owner:** [`src/actions/model/advance_model_request_lifecycle.zig`](../../../src/actions/model/advance_model_request_lifecycle.zig)
- **Reads:** `model_request_identity_ledger` · **Writes:** replaces `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Applies one compare-and-swap request transition: `assigned`→`invoked`, `invoked`→`terminal`, or the approved `assigned`→`terminal` closure of a request never invoked ([model-request-operations.md](../model-request-operations.md)); a terminal transition first requires every provider operation of the request to be closed.
- **Registered step:** [`model_request_lifecycle_workflow.zig`](../../../src/application/model_request_lifecycle_workflow.zig) reads `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `assigned_provider_operation`, `provider_authorization_result`, takes the required `transition` parameter whose only value is `invoked`, and has outcomes `ok` and `failed`: as a step it applies only `assigned`→`invoked`. The two terminal transitions run through `complete-model-request` and `terminate-model-request` (Lifecycle steps).
- **Rejects:** `ModelRequestStatusConflict`, `InvalidModelRequestLifecycleTransition`, `ModelRequestNotFound`, `ProviderOperationStillOpen`.

## `CapturePacketGuidanceAction` (`capture-packet-guidance`)

- **Owner:** [`src/actions/model/capture_packet_guidance.zig`](../../../src/actions/model/capture_packet_guidance.zig)
- **Parameters:** required `guidance` resource (the workflow's `packet-guidance`).
- **Reads:** none (the compiled `packet-guidance` resource) · **Writes:** `packet_guidance` · **Side effect:** `none`
- **Does:** Publishes the compiler-validated packet guidance as run data, so consumers never read the resource ([ADR 0016](../../decisions/0016-configured-json-response-composition.md)).
- **Rejects:** none.

## Attempt accounting and invocation

## `AdvanceModelAttemptAccountingAction` (`advance-model-attempt-accounting`)

- **Owner:** [`src/actions/model/advance_model_attempt_accounting.zig`](../../../src/actions/model/advance_model_attempt_accounting.zig)
- **Reads:** `model_request_identity_ledger` · **Writes:** runner accounting transition `increment_model_attempt` · **Side effect:** `none`
- **Does:** Proposes the next model attempt for a live request: the initial attempt once, a correction only within the step's `retry-limit` ([§22.7](../22-repair.md#227-repair-retry-limit-and-escalation)), and a runaway re-send without counting against it ([ADR 0039](../../decisions/0039-configured-temperatures-and-runaway-resend.md)).
- **Registered step:** [`model_attempt_workflow.zig`](../../../src/application/model_attempt_workflow.zig) reads `model_request_identity_ledger`, `prepared_model_request`, writes `accounted_model_attempt` and takes the required `retry-limit` parameter.
- **Rejects:** `ModelRetryLimitExhausted`, `InvalidAttemptClassification`, `ModelAttemptAccountingRevisionConflict`, `ModelRequestUnavailableForAttempt`, `ModelRequestLedgerRevisionConflict`.

## `CheckWorkflowTokenBudgetAction` (`check-workflow-token-budget`)

- **Owner:** [`src/actions/model/check_workflow_token_budget.zig`](../../../src/actions/model/check_workflow_token_budget.zig)
- **Reads:** none (the runner's token ledger) · **Writes:** none · **Side effect:** `none`
- **Does:** Blocks a further provider call when accounted usage has reached `workflowTokenBudget` ([ADR 0037](../../decisions/0037-configured-workflow-token-budget.md)); reserves nothing.
- **Rejects:** `WorkflowTokenBudgetExceeded`, `ProviderTokenUsageUnavailable`.

## `PrepareProviderOperationAuthorizationAction` (`prepare-provider-operation-authorization`)

- **Owner:** [`src/actions/model/prepare_provider_operation_authorization.zig`](../../../src/actions/model/prepare_provider_operation_authorization.zig)
- **Reads:** `validated_provider_model_binding` · **Writes:** `validated_provider_authorization` · **Side effect:** `none`
- **Does:** Prepares the single-use credential lease for one provider operation through the authorization port.
- **Registered step:** [`provider_authorization_workflow.zig`](../../../src/application/provider_authorization_workflow.zig) reads `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `assigned_provider_operation` and writes `provider_authorization_result`.
- **Rejects:** a `not_sent`, never-retried provider failure: `timeout` (deadline or expiry), `authorization_denied`, `authentication_failed`; cancellation returns `cancelled`.

## `AdvanceProviderOperationLifecycleAction` (`advance-provider-operation-lifecycle`)

- **Owner:** [`src/actions/model/advance_provider_operation_lifecycle.zig`](../../../src/actions/model/advance_provider_operation_lifecycle.zig)
- **Reads:** `model_request_identity_ledger` · **Writes:** runner accounting transition `advance_provider_operation` · **Side effect:** `none`
- **Does:** Proposes one compare-and-swap transition of a provider operation's lifecycle.
- **Registered step:** [`provider_operation_lifecycle_workflow.zig`](../../../src/application/provider_operation_lifecycle_workflow.zig) reads the authorization step's keys plus `provider_authorization_result`, writes `invoked_provider_operation`, invalidates `assigned_provider_operation` and takes the required `transition` parameter whose only value is `invoked`.
- **Rejects:** `provider_operation_lifecycle.ValidationError` (`ProviderOperationRevisionConflict`, `InvalidProviderOperationTransition`, `ProviderOperationNotFound` and the rest).

## `InvokeModelAction` (`invoke-model`)

- **Owner:** [`src/actions/model/invoke_model.zig`](../../../src/actions/model/invoke_model.zig)
- **Reads:** `model_request_identity_ledger`, `validated_provider_model_binding`, `validated_provider_authorization` · **Writes:** none (returns the provider observation) · **Side effect:** `model_call`
- **Does:** Makes the one provider call for an applied invocation record through the provider port, which consumes the lease.
- **Registered step:** [`model_invocation_workflow.zig`](../../../src/application/model_invocation_workflow.zig) reads `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `invoked_provider_operation`, `provider_authorization_result`, writes `provider_invocation_result`, with outcomes `ok`, `failed` and `cancelled`.
- **Rejects:** the provider port's `LlmProviderInterface` errors; provider failures arrive as a `failed` observation.

## `ReconcileWorkflowTokenUsageAction` (`reconcile-workflow-token-usage`)

- **Owner:** [`src/actions/model/reconcile_workflow_token_usage.zig`](../../../src/actions/model/reconcile_workflow_token_usage.zig)
- **Reads:** none (the runner's token ledger) · **Writes:** runner accounting transition `reconcile_workflow_tokens` · **Side effect:** `none`
- **Does:** Accounts one inference operation's reported usage exactly once.
- **Rejects:** `TokenUsageAlreadyAccounted`, `InvalidProviderTokenUsage`, `InvalidTokenAccountingOperation`, `TokenAccountingRevisionConflict`.

## Lifecycle steps

These steps bind the two lifecycle actions above to fixed transitions; their rules are in
[model-request-operations.md](../model-request-operations.md). Each has side effect `none`.

## `provider_operation_workflow.Assign` (`assign-provider-operation`)

- **Owner:** [`src/application/provider_operation_workflow.zig`](../../../src/application/provider_operation_workflow.zig) (wraps `advance-provider-operation-lifecycle`)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt` · **Writes:** `assigned_provider_operation` · **Side effect:** `none`
- **Does:** Opens the provider operation for the accounted attempt.
- **Rejects:** outcome `failed`.

## `provider_operation_completion_workflow.Complete` (`complete-provider-operation`)

- **Owner:** [`src/application/provider_operation_completion_workflow.zig`](../../../src/application/provider_operation_completion_workflow.zig) (wraps `advance-provider-operation-lifecycle`)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `invoked_provider_operation`, `provider_invocation_validation_result` · **Writes:** `terminal_provider_operation`; invalidates `invoked_provider_operation` · **Side effect:** `none`
- **Does:** Closes an invoked provider operation from its validated observation, keeping the request association.
- **Rejects:** outcomes `failed`, `cancelled`.

## `provider_operation_termination_workflow.Terminate` (`terminate-provider-operation`)

- **Owner:** [`src/application/provider_operation_termination_workflow.zig`](../../../src/application/provider_operation_termination_workflow.zig) (wraps `advance-provider-operation-lifecycle`)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `assigned_provider_operation`, `provider_authorization_result` · **Writes:** `terminal_provider_operation`; invalidates `assigned_provider_operation` · **Side effect:** `none`
- **Does:** Closes an assigned provider operation that was never invoked, after a failed or cancelled authorization.
- **Rejects:** outcomes `failed`, `cancelled` only.

## `model_request_completion_workflow.Complete` (`complete-model-request`)

- **Owner:** [`src/application/model_request_completion_workflow.zig`](../../../src/application/model_request_completion_workflow.zig) (wraps `advance-model-request-lifecycle`)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result` · **Writes:** replaces `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Moves an invoked request to `terminal` from its admitted response, forwarding the admission outcome.
- **Rejects:** forwards `invalid`, `failed` or `cancelled`.

## `model_request_termination_workflow.Terminate` (`terminate-model-request`)

- **Owner:** [`src/application/model_request_termination_workflow.zig`](../../../src/application/model_request_termination_workflow.zig) (wraps `advance-model-request-lifecycle`)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `provider_authorization_result` · **Writes:** replaces `model_request_identity_ledger` · **Side effect:** `none`
- **Does:** Applies the approved `assigned`→`terminal` closure of a request never invoked.
- **Rejects:** outcomes `failed`, `cancelled` only.

## Response admission and correction

## `ValidateProviderInvocationObservationAction` (`validate-provider-invocation-observation`)

- **Owner:** [`src/actions/model/validate_provider_invocation_observation.zig`](../../../src/actions/model/validate_provider_invocation_observation.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `invoked_provider_operation`, `provider_invocation_result` · **Writes:** `provider_invocation_validation_result` · **Side effect:** `none`
- **Does:** Proves call association, delivery, stop and usage before any decode.
- **Rejects:** `InvalidProviderInvocationContext`, `ProviderInvocationAssociationInvalid`, `InvalidProviderTokenUsage`.

## `DecodeModelEnvelopeAction` (`decode-model-envelope`)

- **Owner:** [`src/actions/model/decode_model_envelope.zig`](../../../src/actions/model/decode_model_envelope.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `provider_invocation_validation_result` · **Writes:** `model_envelope_result` · **Side effect:** `none`
- **Does:** Parses the complete candidate as one JSON object with its syntax diagnostic.
- **Rejects:** `InvalidModelEnvelope`.

## `ValidateModelPayloadSchemaAction` (`validate-model-payload-schema`)

- **Owner:** [`src/actions/model/validate_model_payload_schema.zig`](../../../src/actions/model/validate_model_payload_schema.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `model_envelope_result` · **Writes:** `model_payload_schema_result` · **Side effect:** `none`
- **Does:** Applies only the bound closed result schema; parsing and call association are earlier steps.
- **Rejects:** a schema diagnostic in the result.

## `AdmitModelResponseAction` (`admit-model-response`)

- **Owner:** [`src/actions/model/admit_model_response.zig`](../../../src/actions/model/admit_model_response.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `provider_invocation_validation_result` · **Writes:** `model_envelope_result`, `model_payload_schema_result` · **Side effect:** `none`
- **Does:** Decodes and schema-validates a complete candidate in one step, through the same envelope and schema owners. A first runaway admits as `invalid`; a runaway on a re-send fails with `RunawayRepeated` ([ADR 0039](../../decisions/0039-configured-temperatures-and-runaway-resend.md)).
- **Rejects:** `InvalidModelEnvelope`; a schema diagnostic in the result.

## `CheckModelRunawayAction` (`check-model-runaway`)

- **Owner:** [`src/actions/model/check_model_runaway.zig`](../../../src/actions/model/check_model_runaway.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `model_payload_schema_result` · **Writes:** none · **Side effect:** `none`
- **Does:** Routes `more` when the rejected attempt is a first runaway of the current request (its one re-send), otherwise `ok` (the ordinary correction).
- **Rejects:** none.

## `BuildModelRunawayResendAction` (`build-model-runaway-resend`)

- **Owner:** [`src/actions/model/build_model_runaway_resend.zig`](../../../src/actions/model/build_model_runaway_resend.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result` · **Writes:** replaces `prepared_model_request`; invalidates the attempt keys · **Side effect:** `none`
- **Does:** Rebuilds the identical prepared request at the runaway-retry temperature, with no diagnostic and no partial text ([ADR 0039](../../decisions/0039-configured-temperatures-and-runaway-resend.md)).
- **Rejects:** `ModelRequestAssociationInvalid` for any evidence that isn't a first runaway.

## `BuildModelProtocolRetryAction` (`build-model-protocol-retry`)

- **Owner:** [`src/actions/model/build_model_protocol_retry.zig`](../../../src/actions/model/build_model_protocol_retry.zig)
- **Reads:** `model_request_identity_ledger`, `validated_model_request`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result` · **Writes:** replaces `prepared_model_request`; invalidates the attempt keys · **Side effect:** `none`
- **Does:** Builds the correction request for a rejected response under the same request identity, with the diagnostic and repetition fact ([§22.6](../22-repair.md#226-unparseable-output)).
- **Rejects:** the request-preparation errors (`ModelRequestAssociationInvalid`, `InvalidModelRequestSource`).

## Retirement

The three retirement operations read `model_request_identity_ledger`, `prepared_model_request`,
`accounted_model_attempt`, `terminal_provider_operation` and `model_payload_schema_result`, have
side effect `none`, write nothing but invalidations, and reject `InvalidTransportRetirement`
unless the request is terminal. The **attempt keys** are `accounted_model_attempt`,
`terminal_provider_operation`, `provider_authorization_result`, `provider_invocation_result`,
`provider_invocation_validation_result`, `model_envelope_result` and
`model_payload_schema_result`; the **request keys** are those plus `assigned_model_request`,
`validated_model_request` and `prepared_model_request`
([`model_transport.zig`](../../../src/domain/model_transport.zig)).

## `RetireModelInputAction` (`retire-model-input`)

- **Owner:** [`src/actions/model/retire_model_input.zig`](../../../src/actions/model/retire_model_input.zig)
- **Reads:** as above · **Writes:** invalidates `model_input_packet` · **Side effect:** `none`
- **Does:** Releases the model input packet of a terminal request.
- **Rejects:** `InvalidTransportRetirement`.

## `RetireModelRequestAction` (`retire-model-request`)

- **Owner:** [`src/actions/model/retire_model_request.zig`](../../../src/actions/model/retire_model_request.zig)
- **Reads:** as above · **Writes:** invalidates the attempt keys and the assigned, validated and prepared request · **Side effect:** `none`
- **Does:** Releases a terminal request's transport data.
- **Rejects:** `InvalidTransportRetirement`.

## `RetireModelTransportAction` (`retire-model-transport`)

- **Owner:** [`src/actions/model/retire_model_transport.zig`](../../../src/actions/model/retire_model_transport.zig)
- **Reads:** as above · **Writes:** invalidates the request keys and `model_input_packet` · **Side effect:** `none`
- **Does:** Releases a terminal request's transport data and its input packet together.
- **Rejects:** `InvalidTransportRetirement`.

## JSON composition

[ADR 0016](../../decisions/0016-configured-json-response-composition.md) owns composition;
request preparation selects a part through its `composition-part` parameter.

## `InitializeJsonCompositionAction` (`initialize-json-composition`)

- **Owner:** [`src/actions/model/initialize_json_composition.zig`](../../../src/actions/model/initialize_json_composition.zig)
- **Reads:** `model_input_packet`, `model_request_identity_ledger` · **Writes:** `json_composition` · **Side effect:** `none`
- **Does:** Binds the `composition` plan to the current packet and execution epoch.
- **Registered step:** the same keys, with the required `composition` resource parameter ([`json_composition_workflow.zig`](../../../src/application/json_composition_workflow.zig)).
- **Rejects:** `json_composition_runtime.Error` (`InvalidCompositionBinding`).

## `RetainJsonPartAction` (`retain-json-part`)

- **Owner:** [`src/actions/model/retain_json_part.zig`](../../../src/actions/model/retain_json_part.zig)
- **Reads:** `json_composition`, `model_request_identity_ledger`, `prepared_model_request`, `model_payload_schema_result` · **Writes:** replaces `json_composition` · **Side effect:** `none`
- **Does:** Retains one schema-admitted part result with its origin.
- **Rejects:** `InvalidCompositionBinding`, `ConflictingCompositionPart`.

## `AssembleJsonAction` (`assemble-json`)

- **Owner:** [`src/actions/model/assemble_json.zig`](../../../src/actions/model/assemble_json.zig)
- **Reads:** `json_composition` · **Writes:** `assembled_json`; invalidates `json_composition` · **Side effect:** `none`
- **Does:** Assembles the complete, unvalidated candidate from the retained parts.
- **Rejects:** `IncompleteComposition`.

## `ValidateAssembledJsonAction` (`validate-assembled-json`)

- **Owner:** [`src/actions/model/validate_assembled_json.zig`](../../../src/actions/model/validate_assembled_json.zig)
- **Reads:** `assembled_json` · **Writes:** `validated_assembled_json` · **Side effect:** `none`
- **Rejects:** the complete schema's diagnostic for the assembled candidate.

## Proposed, no code

Named by other documents; no operation registers them.

## `SelectContextAction`

Proposed, no code: select the bounded known context for a unit ([§12](../12-model-boundary.md)).

## `BuildInitialGuidanceAction`

Proposed, no code: build a unit's deterministic initial guidance packet ([§12](../12-model-boundary.md)).

> **ADR 0033 (not yet implemented).** The repair entries below become domain functions of
> [ADR 0033](../../decisions/0033-generic-repair-operations.md)'s four generic repair operations;
> today each owner registers its own `authorize`/`parse`/`merge` operations. Whether the
> no-invention and semantic-review branches stay is an open decision (SPEC01 "Design–code
> conflicts").

## `ClassifyRepairAuthorizationPurposeAction`

Proposed, no code: choose ordinary atomic repair or the no-invention replacement for a selected diagnostic ([§14](../14-orchestration.md), [§22](../22-repair.md)).

## `CreateRepairAuthorizationAction`

Proposed, no code: bind one closed repair operation to current values, preconditions and cited rules ([§22](../22-repair.md)).

## `CreateNoInventionClarificationReplacementAuthorizationAction`

Proposed, no code: authorize the one-shot whole-result replacement of unsupported content by a clarification ([§14](../14-orchestration.md)).

## `BuildAtomicRepairGuidanceAction`

Proposed, no code: explain exactly the authorized change from bound rule values ([§12](../12-model-boundary.md)).

## `ValidateRepairEnvelopeAction`

Proposed, no code: check a repair candidate against its retained authorization and current revision ([ADR 0006](../../decisions/0006-minimal-model-response.md)).

## `ValidateRepairScopeAction`

Proposed, no code: prove a repair touches only authorized pointers and update repair accounting ([§22](../22-repair.md)).

## `MergeAtomicRepairAction`

Proposed, no code: compare-and-swap one authorized repair into the candidate ([§12](../12-model-boundary.md), [§22](../22-repair.md)).
