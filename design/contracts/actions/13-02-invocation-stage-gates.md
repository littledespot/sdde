# 13.2 Invocation, feature, and stage-gate actions

Part of [design §13](../../design.md#13-action-catalogue). Action names define responsibility
boundaries under [§6](../06-pipeline-nodes.md). Results remain execution-local until
whole-workflow publication; [§25](../25-publication.md) and the clarification exception apply.

> **ADR 0032 (not yet implemented).** The two `specify` invocation actions below become the
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

## `NormalizeFeatureDirectoryAction` (`normalize-feature-directory`)

- **Owner:** [`src/actions/specify/normalize_feature_directory.zig`](../../../src/actions/specify/normalize_feature_directory.zig)
- **Reads:** `specify_invocation` · **Writes:** `normalized_feature_directory` · **Side effect:** `none`
- **Does:** Normalize the raw `--feature` value to NFC through the Unicode port, then apply the
  shared relative-path normalization; it adds no slug, truncation or suffix.
- **Rejects:** the Unicode port's `InvalidUtf8`, `NormalizationLimitExceeded` and
  `NormalizationFailed`.

## `ValidateFeatureDirectoryAction` (`validate-feature-directory`)

- **Owner:** [`src/actions/specify/validate_feature_directory.zig`](../../../src/actions/specify/validate_feature_directory.zig)
- **Reads:** `normalized_feature_directory` · **Writes:** `relative_feature_directory` · **Side effect:** `none`
- **Does:** Parse the feature ID and join it to the configured specs root; require lexical path
  safety, containment in the specs root and exclusion from the archive root. No filesystem
  access or ownership lookup.
- **Rejects:** `InvalidFeatureDirectory`, also when no roots are bound.

## `InspectFeatureDirectoryAction` (`inspect-feature-directory`)

- **Owner:** [`src/actions/specify/inspect_feature_directory.zig`](../../../src/actions/specify/inspect_feature_directory.zig)
  (adapter [`feature_directory_inspector.zig`](../../../src/adapters/filesystem/feature_directory_inspector.zig))
- **Reads:** `relative_feature_directory` · **Writes:** `feature_directory` · **Side effect:** `filesystem_read`
- **Does:** Through the bound read capability, observe only the selected directory and its
  specs root: absent, or a readable directory with its identity. No other feature is scanned.
- **Rejects:** `FeatureDirectoryUnavailable` for a missing capability, a selector that no
  longer revalidates, or an unreadable or unsafe node.

## `ResolveFeatureArtifactPathsAction` (`resolve-feature-artifact-paths`)

- **Owner:** [`src/actions/specify/resolve_feature_artifact_paths.zig`](../../../src/actions/specify/resolve_feature_artifact_paths.zig)
- **Reads:** `feature_directory` · **Writes:** `feature_artifact_paths` · **Side effect:** `none`
- **Does:** Derive every registered artifact path for the feature (specification, reference
  context, clarification forms and state, workflow state, event and prompt logs) from the
  configured roots; no model or user supplies a path.
- **Rejects:** `InvalidFeatureArtifactPath` when roots are unbound or the selector no longer
  revalidates against them.

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
