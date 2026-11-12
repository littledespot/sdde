# 13.2 Invocation, feature, and stage-gate actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

> **ADR 0032 (not yet implemented for the Specify invocation).** The two `specify` invocation actions below become the
> internal functions of one [ADR 0031](../../decisions/0031-stage-actions.md) stage action
> (parse, then validate, side effect `none`), named by the definition's `invoke:` field and run
> by the engine before the graph starts ([ADR 0032](../../decisions/0032-engine-routines.md)).

## Core operations

[`core_workflow_operations.zig`](../../../src/composition/core_workflow_operations.zig) registers
two capability-free operations any workflow may use; neither reads or writes data.

- **`core.empty-invocation`:** an invocation operation that accepts no arguments; any argument,
  or use as a step, fails. Outcome `ok`.
- **`core.noop`:** a step that does nothing; use as an invocation fails. Outcome `ok`.

## `specify_invocation_runner.Invocation` (`specify-invocation`)

- **Owner:** [`src/application/specify_invocation_runner.zig`](../../../src/application/specify_invocation_runner.zig)
- **Reads:** none (the workflow arguments) · **Writes:** `specify_invocation` · **Side effect:** `none`
- **Does:** The Spec workflow's registered invocation operation: runs `parse-specify-invocation`
  then `validate-specify-arguments` through its capability-free orchestrator and publishes only
  the validated invocation; the parsed arguments stay private.
- **Rejects:** the two actions' `InvalidSpecifyArguments`.

## `ParseSpecifyInvocationAction` (`parse-specify-invocation`)

- **Owner:** [`src/actions/specify/parse_specify_invocation.zig`](../../../src/actions/specify/parse_specify_invocation.zig)
- **Reads:** none (the remaining workflow arguments) · **Writes:** `parsed_specify_invocation` · **Side effect:** `none`
- **Does:** Parse `--feature` and `--reference` flag/value pairs without resolving paths or
  reading files.
- **Rejects:** `InvalidSpecifyArguments` for a flag with no value, a repeated flag, or a
  positional or unknown input.

## `ValidateSpecifyArgumentsAction` (`validate-specify-arguments`)

- **Owner:** [`src/actions/specify/validate_specify_arguments.zig`](../../../src/actions/specify/validate_specify_arguments.zig)
- **Reads:** `parsed_specify_invocation` · **Writes:** `specify_invocation` · **Side effect:** `none`
- **Does:** Require both values, each non-empty, within the relative-path byte limit and not
  starting with `-`.
- **Rejects:** `InvalidSpecifyArguments`.

## `PrepareInputsAction` (`prepare-inputs`)

[ADR 0031](../../decisions/0031-stage-actions.md) made the thirteen former operations the internal
steps of this one stage action. [F0100](../../features/F0100-SpecWorkflow.md) owns where it sits in
the Specify workflow.

- **Owner:** [`src/actions/specify/prepare_inputs.zig`](../../../src/actions/specify/prepare_inputs.zig)
  (binding [`input_preparation_workflow.zig`](../../../src/application/input_preparation_workflow.zig);
  adapters [`feature_directory_inspector.zig`](../../../src/adapters/filesystem/feature_directory_inspector.zig),
  [`reference_directory_inspector.zig`](../../../src/adapters/filesystem/reference_directory_inspector.zig),
  [`feature_input_source.zig`](../../../src/adapters/filesystem/feature_input_source.zig))
- **Reads:** `specify_invocation` · **Writes:** `feature_directory`, `relative_feature_directory`,
  `reference_directory`, `feature_artifact_paths`, `prior_specification_state`,
  `prior_principle_registry`, `raw_clarification_inputs`, `clarification_inputs` · **Side effect:** `filesystem_read`
- **Ports:** the Unicode normalizer and the feature-directory, reference-directory, workflow-state
  and feature-input ports, one per step; the binding derives `feature-read`, `reference-read` and
  `feature-input-read` only.
- **Outcomes:** `ok`, `failed`. Each internal step's success continues to the next and every
  failure ends the stage with the step's own error. The stage records the step it stopped at in
  its diagnostic slot, which the binding hands the runner's step slot, and the runner records it
  as `step_id` in the failed action's event ([§27](../27-observability.md)). It checks the runtime
  between steps, so a cancelled run stops before the next step.
- **Does:** Runs these functions in order. Each keeps its former action's responsibility, input,
  output and rejection rules; intermediates are function-local values, and the prior specification
  state is the only value owned beyond the run's scratch space.
  1. `normalizeFeature`: NFC-normalizes the raw `--feature` value through the Unicode port, then
     applies the shared relative-path normalization; it adds no slug, truncation or suffix.
     Rejects the port's `InvalidUtf8`, `NormalizationLimitExceeded` and `NormalizationFailed`.
  2. `validateFeature`: parses the feature ID and joins it to the configured specs root; requires
     lexical path safety, containment in the specs root and exclusion from the archive root. No
     filesystem access or ownership lookup. Rejects `InvalidFeatureDirectory`, also when no roots
     are bound.
  3. `inspectFeature`: through the bound read capability, observes only the selected directory and
     its specs root: absent, or a readable directory with its identity. No other feature is
     scanned. Rejects `FeatureDirectoryUnavailable` for a missing capability, a selector that no
     longer revalidates, or an unreadable or unsafe node.
  4. `normalizeReference`: NFC-normalizes the raw `--reference` value within the selector byte
     limit, then normalizes it as a relative directory path. Rejects the Unicode port's errors.
  5. `validateReference`: requires a safe relative selector. Rejects `InvalidReferenceSelector`.
  6. `inspectReference`: observes the selected reference directory through the read-only
     inspector. Rejects `ReferenceDirectoryUnavailable`.
  7. `resolvePaths`: derives every registered artifact path for the feature (specification,
     reference context, clarification forms and state, workflow state, event and prompt logs)
     from the configured roots; no model or user supplies a path. Rejects
     `InvalidFeatureArtifactPath` when roots are unbound or the selector no longer revalidates.
  8. `captureState`: reads the feature's canonical workflow-state file through the state-source
     port, or reports it absent; it never parses the bytes. Rejects `FeatureInputUnavailable`.
  9. `parseState`: parses the feature's prior `specification-state` or incomplete state; a first
     run has none. Rejects `specification_state.Error`, including `InvalidSpecificationState`.
  10. `captureClarifications`: captures the feature's clarification-state bytes and every
      `clarify/` form through the feature-input port. Rejects the port's typed errors.
  11. `parseClarificationState`: parses the captured state bytes through the state-parser port;
      no bytes give no state. Rejects `InvalidClarificationInput` from the parser.
  12. `validateClarificationState`: checks the schema and feature, then each record: stage IDs in
      order with no gap, revisions within the state's, nonempty bounded question and reason, at
      most 64 distinct authorities, and one record per stage and subject. Rejects
      `InvalidClarificationInput`.
  13. `validateClarificationForms`: pairs each record with exactly one captured form and parses
      it against the record's binding. An authority-resolved form must equal its re-rendered
      audit bytes, and a recorded response's form must equal its saved bytes and answer. A
      `closed` form becomes protected. Rejects `InvalidClarificationInput` for a form-count or ID
      mismatch, changed audit or saved bytes, or a requested status that contradicts the record.

Feature-log identities ([ADR 0018](../../decisions/0018-debug-model-exchange-logging.md)): one
adapter builds the policy ID (`LOGPOL-` and the SHA-256 of the compiled policy), a fresh random
`RUN-` ID and the binding ID together
([`feature_log_identity.zig`](../../../src/adapters/system/feature_log_identity.zig)); no
registered action builds them, and nothing recomputes the policy ID. Feature-log operations are
in [13.9](13-09-logging.md).

## `ActivateFeatureLogPolicyTransitionAction`

Proposed, no code: swap the run-local logging observer to the validated successor sink once
every enabled stream is safe ([§14.10](../14-orchestration.md#1410-featurelogpolicytransitionorchestrator)).

## `BuildHistoricalFeatureLogStreamFinalizationEvidenceAction`

Proposed, no code (deferred by [ADR 0009](../../decisions/0009-atomic-workflow-execution.md)):
join one historical log group to its terminal close observation and released lock
([§14](../14-orchestration.md)).

## `ValidateHistoricalFeatureLogRunFinalizationAction`

Proposed, no code (deferred by ADR 0009): prove every prior-run log group is finalized before
the current run's sink starts ([§14](../14-orchestration.md)).

## `ValidateWorkflowMetadataAction`

Proposed, no code: validate one reference, state or artifact expectation of a stage gate
([§14](../14-orchestration.md), [§24](../24-workflow-state.md)).

## `ValidateWorkflowStateAction`

Proposed, no code: prove monotonic revision, a legal transition, sorted unique bound workflow
IDs (the selected one added when it first participates, each resolving in the current
bootstrap registry), exact current pointers, open sets and approvals, and no dangling authority.
Only a feature's initial `specifying` revision, with no clarification history, request or
specification, may lack its reference pointer ([§24](../24-workflow-state.md)).

Proposed, no code: the SDD stage gates and persisted workflow state that Plan, Tasks and
Implement need: predecessor order, required-artifact presence and readability, and building,
parsing and serializing the next workflow-state revision ([§14](../14-orchestration.md),
[§21.1](../21-validation.md#211-cross-stage-validators), [§24](../24-workflow-state.md)).
