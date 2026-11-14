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
the request-lifecycle entries below (attempt accounting, provider operation, authorization,
phase check, invocation, observation, completion, admission, correction, re-send, closure and
termination) are the **stages** of one `request-model` step, which the Spec workflow and the
packaging fixture use. A stage is a native binding held by the `request-model` registry entry,
not an operation a workflow can select: a definition that names a stage's ID fails to compile.
Entries marked "Proposed, no code" are named elsewhere but have no registered operation.

The runner has one seam beside the stages: an optional stage gate, consulted before each stage
of a `request-model` step, that a caller such as the provider compatibility probe uses to end a
request once its one exchange is retained. It names one of two typed stops (`cancelled` or
`failed`), which the runner maps to its own rejection; the stage it precedes does not run and
emits no event. It holds no capability and runs nothing. Only the E2E harness `Trace` sets it,
and an architecture test pins that.

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

## Release

## `ReleaseModelRequestAction` (`release-model-request`) and `ReleaseModelTransportAction` (`release-model-transport`)

- **Owners:** [`src/actions/model/release_model_request.zig`](../../../src/actions/model/release_model_request.zig), [`src/actions/model/release_model_transport.zig`](../../../src/actions/model/release_model_transport.zig)
- **Reads:** `model_request_identity_ledger`, `prepared_model_request`, `accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result` · **Writes:** invalidate the **released keys** (`accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result`, `prepared_model_request`), and `release-model-transport` also `model_input_packet` ([`model_transport.zig`](../../../src/domain/model_transport.zig)) · **Side effect:** `none`
- **Does:** Release a closed [ADR 0030](../../decisions/0030-engine-owned-model-request.md) `request-model` request's kept keys; the ledger is replaced, never retired, and the other request keys ended with the step.
- **Rejects:** `InvalidTransportRetirement` unless the request is terminal.

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

> **ADR 0033 (implemented).** The repair entries below are domain functions inside
> [ADR 0033](../../decisions/0033-generic-repair-operations.md)'s four generic repair operations
> (`authorize-repair`, `build-repair-input`, `parse-repair`, `merge-repair`), whose per-owner
> variants are specified once, in [Generic repair operations](#generic-repair-operations) below.

## Generic repair operations

Four registered operations replace the 29 per-owner repair operations of the Specify
definition ([ADR 0033](../../decisions/0033-generic-repair-operations.md)). Each is **one
registered contract made of closed variants**, one per owner it serves, selected at compile
time by the required enumeration parameter `owner`
([ADR 0030](../../decisions/0030-engine-owned-model-request.md), "Contract variants"). The
owners are the 13 members of `RepairOwner`
([`src/domain/repair_owner.zig`](../../../src/domain/repair_owner.zig)); each operation's
allowed `owner` values are exactly the owners that have a variant of it, so a step that names
an owner with no variant rejects at compilation.

- **Common facts.** Every variant has side effect `none`, declares no gates and holds no
  capability. No variant makes a model call: the call is the separate `request-model` step
  between `build-repair-input` and `parse-repair`. A repair route is `authorize-repair`,
  `build-repair-input`, `request-model`, `parse-repair`, `merge-repair`; an authorizer's `more`
  skips input, request and parse and goes to merge.
- **Where the rules live.** The generic operation selects the owner's rules through one
  exhaustive `switch` over `RepairOwner`
  ([`src/application/repair_workflow.zig`](../../../src/application/repair_workflow.zig)), with no
  default branch, table or dispatcher. Each owner's binding declares its data effects once
  (`repair_owner.Effects`) and holds its rules in the owner's domain module, reusing the shared
  `atomic_repair.Contract`.
- **`owner` selects no policy, scope or defect identity.** Where a variant's required keys prove
  the owner, the compiler checks it. Otherwise the owner's binding reads only its own native
  facts, and a mismatch is a terminal runner rejection, never a routable outcome. Retry identity
  is the compiled step instance, so two steps using one operation keep separate counters.
- **Retry.** Only merges retry. The `reference-text` and `reference-extraction` merges forbid
  `retry-limit`. The others require it, within their variant's maximum: `reference-reconciliation`
  128, `source-omission-extraction` 1, `source-omission-reconciliation` 1, `specification-unit`
  64, `specification-support` 2 ([§22.7](../22-repair.md#227-repair-retry-limit-and-escalation)).
- **Source omission.** The current native pre-generation phase witness is checked inside
  authorize, input and both merges whatever `owner` says. Its authorize `ok` selects the
  extraction branch and `more` the reconciliation branch; each branch merges through its own
  owner.
- **`.packet_guidance`** is read by exactly seven (operation, owner) variants:
  `authorize-repair` and `build-repair-input` for `specification-unit` and `specification-support`,
  `merge-repair` for `specification-support`, and `build-repair-input` for
  `reference-reconciliation` and `source-omission`.

### `authorize-repair`

Decides whether one engine-selected unit may be repaired and binds its target, old value,
revision, dependencies and retry identity. Role `authorize`; association `repair_authorize`.
Rejects with the owner's own errors.

| Owner | Reads | Writes | Outcomes | Association (kind; subject; evidence) |
| --- | --- | --- | --- | --- |
| `reference-text` | `valid_toolchain`, `citable_reference_inputs`, `reference_passive_literals`, `parsed_reference_extraction`, `text_validated_reference_extraction` | `reference_text_repair_authorization` | `ok`, `invalid`, `failed` | candidate; `parsed_reference_extraction`; `text_validated_reference_extraction` |
| `reference-extraction` | `citable_reference_inputs`, `structured_token_candidates`, `text_validated_reference_extraction`, `validated_reference_selections` | `reference_extraction_repair_authorization` | `ok`, `invalid`, `failed` | candidate; `text_validated_reference_extraction`; `validated_reference_selections` |
| `reference-summary` | `parsed_reference_reconciliation`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, `validated_reference_summary` | `reference_reconciliation_repair`; invalidates `validated_reference_summary` | `ok`, `more`, `blocked`, `failed` | candidate; `parsed_reference_reconciliation`; `validated_reference_summary` |
| `reference-dispositions` | as `reference-summary`, with `validated_reference_dispositions` | `reference_reconciliation_repair`; invalidates `validated_reference_dispositions` | `ok`, `blocked`, `failed` (no `more`: ADR 0046) | candidate; `parsed_reference_reconciliation`; `validated_reference_dispositions` |
| `reference-signals` | as `reference-summary`, with `validated_reference_signals` | `reference_reconciliation_repair`; invalidates `validated_reference_dispositions`, `validated_reference_signals` | `ok`, `more`, `blocked`, `failed` | candidate; `parsed_reference_reconciliation`; `validated_reference_signals` |
| `reference-conflicts` | as `reference-summary`, with `validated_reference_conflicts` | `reference_reconciliation_repair`; invalidates `validated_reference_dispositions`, `validated_reference_signals`, `validated_reference_conflicts` | `ok`, `more`, `blocked`, `failed` | candidate; `parsed_reference_reconciliation`; `validated_reference_conflicts` |
| `source-omission` | `citable_reference_inputs`, `structured_token_candidates`, `text_validated_reference_extraction`, `parsed_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `required_authority_inputs`, `required_authority_observations`, `required_authority_result`, `specification_support_review` (optional: `specification_generation_session`, `identified_specification_content`) | `source_omission_repair` | `ok` (extraction branch), `more` (reconciliation branch), `invalid`, `failed` | authority; `required_authority_inputs`; `required_authority_result` |
| `specification-unit` | `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_generation_session`, `parsed_specification_unit`, `validated_specification_unit`, `packet_guidance` | `specification_repair_authorization` | `ok`, `more` (a delete), `invalid`, `blocked`, `failed` | candidate; `parsed_specification_unit`; `validated_specification_unit` |
| `specification-support` | `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` | `specification_support_repair` | `ok`, `more`, `blocked`, `failed` | candidate; `specification_support_review`; `specification_support_review` |
| `specification-coverage` | `specification_generation_session`, `accounted_reference_reconciliation`, `identified_specification_content`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, `specification_coverage` | `specification_coverage_repair` | `blocked`, `failed` only | candidate; `specification_generation_session`; `specification_coverage` |

### `build-repair-input`

Builds the repair packet for the authorization. Writes `model_input_packet`; outcomes `ok` and
`failed`; role `none`; association independent. Reads the owner's inputs and its authorization key:

| Owner | Reads |
| --- | --- |
| `reference-text` | `valid_toolchain`, `citable_reference_inputs`, `reference_passive_literals`, `parsed_reference_extraction`, `structured_token_candidates`, `reference_text_repair_authorization` |
| `reference-extraction` | `citable_reference_inputs`, `reference_passive_literals`, `structured_token_candidates`, `text_validated_reference_extraction`, `reference_extraction_repair_authorization` |
| `reference-reconciliation` | `parsed_reference_reconciliation`, `reference_reconciliation_repair`, `citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` (only a summary input carries the workflow's summary purpose) |
| `source-omission` | the `source-omission` authorize reads, plus `source_omission_repair` and `packet_guidance`; builds the extraction or reconciliation packet the authorization selected |
| `specification-unit` | `specification_generation_session`, `specification_repair_authorization`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `packet_guidance` |
| `specification-support` | `required_authority_inputs`, `specification_support_review`, `citable_reference_inputs`, `accounted_reference_reconciliation`, `reference_passive_literals`, `valid_toolchain`, `specification_support_repair`, `packet_guidance` |

### `parse-repair`

Decodes and validates the admitted replacement. Role `none`; association `preserve` (candidate;
authority for `source-omission`). Reads the owner's authorization key and the request evidence
(`model_input_packet`, `model_request_identity_ledger`, `prepared_model_request`,
`accounted_model_attempt`, `terminal_provider_operation`, `model_payload_schema_result`);
`specification-support` reads only five keys: `specification_support_repair`,
`model_request_identity_ledger`, `prepared_model_request`, `model_input_packet` and
`model_payload_schema_result`.

| Owner | Authorization read | Writes | Outcomes |
| --- | --- | --- | --- |
| `reference-text` | `reference_text_repair_authorization` | `reference_text_repair_result` | `ok`, `invalid`, `failed` |
| `reference-extraction` | `reference_extraction_repair_authorization` | `reference_extraction_repair_result` | `ok`, `invalid`, `failed` |
| `reference-reconciliation` | `reference_reconciliation_repair` | replaces `reference_reconciliation_repair` | `ok`, `failed` |
| `source-omission` | `source_omission_repair` | replaces `source_omission_repair`; parses the extraction or reconciliation replacement its authorization names, keeping the response origin | `ok`, `failed` |
| `specification-unit` | `specification_repair_authorization` | replaces `specification_repair_authorization` | `ok`, `failed` |
| `specification-support` | `specification_support_repair` | replaces `specification_support_repair` | `ok`, `failed` |

### `merge-repair`

Compare-and-swaps the authorized replacement into the candidate, over the canonical (NFC)
captured text. Another authorization, or a missing response, is `InvalidAtomicRepair`.

| Owner | Replaces | Invalidates | Outcomes | Role; association | `retry-limit` |
| --- | --- | --- | --- | --- | --- |
| `reference-text` | `parsed_reference_extraction` | `text_validated_reference_extraction`, `reference_text_repair_authorization`, `reference_text_repair_result` | `ok`, `invalid`, `failed` | `merge`; `repair_merge` | forbidden |
| `reference-extraction` | `text_validated_reference_extraction` | `validated_reference_selections`, `reference_extraction_repair_authorization`, `reference_extraction_repair_result` | `ok`, `invalid`, `failed` | `merge`; `repair_merge` | forbidden |
| `reference-reconciliation` | `parsed_reference_reconciliation` | `reference_reconciliation_repair` | `ok`, `failed` | `merge`; `repair_merge` | required, at most 128 |
| `source-omission-extraction` | `text_validated_reference_extraction` | every key derived from it, through `source_omission_repair` (`source_omission.extraction_dependents`) | `ok`, `failed` | `merge`; `repair_merge` | required, at most 1 |
| `source-omission-reconciliation` | `parsed_reference_reconciliation` | every key derived from it, through `source_omission_repair` (`source_omission.reconciliation_dependents`) | `ok`, `failed` | `merge`; `repair_merge` | required, at most 1 |
| `specification-unit` | `parsed_specification_unit` | `validated_specification_unit`, `specification_repair_authorization` | `ok`, `failed` | `merge`; `repair_merge` | required, at most 64 |
| `specification-support` | `specification_support_review` | `specification_support_repair` | `ok`, `more`, `invalid`, `failed` | `merge_validate`; `repair_validate` | required, at most 2 |

The two source-omission merges merge only in the repair phase; their reads are the merge
context (`citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`,
`required_authority_inputs`, `required_authority_observations`, `required_authority_result`,
`specification_support_review`, `source_omission_repair`), plus
`structured_token_candidates` and `text_validated_reference_extraction` for the extraction merge
or `parsed_reference_reconciliation` for the reconciliation merge (optional:
`specification_generation_session`, `identified_specification_content`). The other owners read
the keys they replace, their authorization or repair key and the shared inputs
(`citable_reference_inputs`, `reference_passive_literals`, `valid_toolchain`, and for the
specification owners `accounted_reference_reconciliation`).

## `CreateRepairAuthorizationAction`

Proposed, no code: bind one closed repair operation to current values, preconditions and cited rules ([§22](../22-repair.md)).

## `BuildAtomicRepairGuidanceAction`

Proposed, no code: explain exactly the authorized change from bound rule values ([§12](../12-model-boundary.md)).

## `ValidateRepairEnvelopeAction`

Proposed, no code: check a repair candidate against its retained authorization and current revision ([ADR 0006](../../decisions/0006-minimal-model-response.md)).

## `ValidateRepairScopeAction`

Proposed, no code: prove a repair touches only authorized pointers and update repair accounting ([§22](../22-repair.md)).

## `MergeAtomicRepairAction`

Proposed, no code: compare-and-swap one authorized repair into the candidate ([§12](../12-model-boundary.md), [§22](../22-repair.md)).
